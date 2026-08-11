-- The live alert path gets the same per-subject isolation the nightly rebuild
-- got in 20260808230000.
--
-- Both of these already loop per subject, so the fix is only that one subject
-- raising no longer aborts the run. process_escalations is the alert engine: an
-- exception in any iteration meant that minute raised nothing, escalated
-- nothing and notified nobody, for everybody. It recovers on the next minute
-- unless the condition persists - and a persistent condition would have stopped
-- alerts for every user indefinitely. Nothing was failing when this was written
-- (4320 consecutive successful runs over three days); this closes the shape,
-- not an active fire.
--
-- The bodies below were produced mechanically from the current definitions
-- rather than retyped. Transcribing 149 and 93 lines of escalation and
-- check-in rules by hand in order to add two keywords is how a typo reaches
-- the alert path. The transform inserts BEGIN after each loop opener and an
-- exception handler before each closer, and it was verified line by line: every
-- original line is still present in its original order, and the only additions
-- are the handler itself.
--
-- Skips are recorded in private.job_failures, which private.scheduled_job_health
-- reads - so an isolated failure makes the job report unhealthy rather than
-- disappearing quietly. Isolation without that would just be a slower silence.

CREATE OR REPLACE FUNCTION public.process_escalations()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  _self_grace CONSTANT interval := interval '30 minutes';
  _group_dur  CONSTANT interval := interval '1 hour';
  _comm_dur   CONSTANT interval := interval '2 hours';
  r record;
  _aid uuid;
  _new text;
  _triggered boolean := false;
BEGIN
  -- Sleep/post-wake grace withdraws a silence alert it was wrong to raise.
  -- Activity never closes an alert here; see the migration header.
  FOR r IN
    SELECT
      a.id,
      a.user_id
    FROM public.alerts AS a
    WHERE a.status = 'open'
      AND a.cause = 'silence'
      AND private.sleep_relaxed(a.user_id, now())
  LOOP
    BEGIN
    UPDATE public.alerts
    SET status = 'resolved',
        resolved_at = now(),
        resolved_by = NULL,
        updated_at = now()
    WHERE id = r.id;

    INSERT INTO public.alert_events (alert_id, kind, note)
    VALUES (r.id, 'auto_resolved', 'sleep_grace');

    PERFORM private.notify_auto_resolved(r.id, r.user_id);
    _triggered := true;
    EXCEPTION WHEN OTHERS THEN
      -- One subject must not take the rest of the run down with it. The
      -- skip is recorded rather than swallowed, and private.scheduled_job_health
      -- reports the job unhealthy while these rows are recent.
      INSERT INTO private.job_failures (job_name, subject_id, sqlstate, message)
      VALUES ('process_escalations', r.user_id, SQLSTATE, SQLERRM);
    END;
  END LOOP;

  -- device_state.status is descriptive state, not an independent authority to
  -- bypass the canonical silence calculation or sleep grace.
  FOR r IN
    SELECT
      ds.user_id,
      (now() - ds.last_heartbeat_at) > interval '18 hours' AS is_dark
    FROM public.device_state AS ds
    WHERE (
      now() - ds.last_heartbeat_at > interval '18 hours'
      OR (
        NOT private.sleep_relaxed(ds.user_id, now())
        AND now() - (
          SELECT coalesce(max(received_at), to_timestamp(0))
          FROM public.behavior_pings
          WHERE user_id = ds.user_id
            AND ingest_version = 2
            AND abs(extract(epoch FROM (received_at - at))) <= 300
        ) > private.silence_threshold(ds.user_id)
      )
    )
      AND EXISTS (
        SELECT 1
        FROM public.group_members AS gm
        WHERE gm.user_id = ds.user_id
          AND gm.monitored
          AND gm.status = 'active'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.alerts AS a
        WHERE a.user_id = ds.user_id
          AND a.status = 'open'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.alerts AS recent
        WHERE recent.user_id = ds.user_id
          AND recent.status = 'resolved'
          AND recent.cause IN ('silence', 'dark_device')
          AND recent.resolved_by IS NOT NULL
          AND recent.resolved_by <> recent.user_id
          AND recent.resolved_at > now() - _self_grace
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.gm_mutes AS mute
        WHERE mute.user_id = ds.user_id
          AND (mute.muted_until IS NULL OR mute.muted_until > now())
      )
  LOOP
    BEGIN
    INSERT INTO public.alerts (
      user_id, cause, stage, stage_entered_at, next_deadline
    )
    VALUES (
      r.user_id,
      CASE WHEN r.is_dark THEN 'dark_device' ELSE 'silence' END,
      'self',
      now(),
      now() + _self_grace
    )
    RETURNING id INTO _aid;

    INSERT INTO public.alert_events (alert_id, kind)
    VALUES (_aid, 'raised');

    PERFORM private.notify_stage(_aid, r.user_id, 'self');
    _triggered := true;
    EXCEPTION WHEN OTHERS THEN
      -- One subject must not take the rest of the run down with it. The
      -- skip is recorded rather than swallowed, and private.scheduled_job_health
      -- reports the job unhealthy while these rows are recent.
      INSERT INTO private.job_failures (job_name, subject_id, sqlstate, message)
      VALUES ('process_escalations', r.user_id, SQLSTATE, SQLERRM);
    END;
  END LOOP;

  FOR r IN
    SELECT *
    FROM public.alerts
    WHERE status = 'open'
      AND next_deadline IS NOT NULL
      AND next_deadline <= now()
      AND coalesce(paused_until, to_timestamp(0)) <= now()
  LOOP
    BEGIN
    _new := CASE r.stage
      WHEN 'self' THEN 'group'
      WHEN 'group' THEN 'community'
      WHEN 'community' THEN 'terminal'
      ELSE 'terminal'
    END;

    UPDATE public.alerts
    SET stage = _new,
        stage_entered_at = now(),
        paused_until = NULL,
        paused_by = NULL,
        updated_at = now(),
        next_deadline = CASE _new
          WHEN 'group' THEN now() + _group_dur
          WHEN 'community' THEN now() + _comm_dur
          ELSE NULL
        END
    WHERE id = r.id;

    INSERT INTO public.alert_events (alert_id, kind, note)
    VALUES (r.id, 'escalated', _new);

    PERFORM private.notify_stage(r.id, r.user_id, _new);
    _triggered := true;
    EXCEPTION WHEN OTHERS THEN
      -- One subject must not take the rest of the run down with it. The
      -- skip is recorded rather than swallowed, and private.scheduled_job_health
      -- reports the job unhealthy while these rows are recent.
      INSERT INTO private.job_failures (job_name, subject_id, sqlstate, message)
      VALUES ('process_escalations', r.user_id, SQLSTATE, SQLERRM);
    END;
  END LOOP;

  IF _triggered THEN
    PERFORM private.trigger_push_dispatch();
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.process_checkin_tasks()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  t record;
  _done boolean;
  _wname text;
  _timezone text;
  _local_date date;
  _candidate timestamptz;
BEGIN
  -- 1) 到点：提醒承担者 (Claim rows using FOR UPDATE SKIP LOCKED to prevent concurrent cron double-firing)
  FOR t IN
    SELECT * FROM public.checkin_tasks ct
    WHERE status = 'active' AND cycle_state = 'idle'
      AND next_due_at IS NOT NULL AND next_due_at <= now()
      AND NOT private.sleep_relaxed(ct.ward_id, now())
    FOR UPDATE SKIP LOCKED
  LOOP
    BEGIN
    INSERT INTO public.notifications (recipient_id, kind, body, params)
    VALUES (t.ward_id, 'task_due', '到点报平安啦，点开 App 完成确认。',
            jsonb_build_object('label', t.label));

    UPDATE public.checkin_tasks
    SET cycle_state = 'due_notified', updated_at = now()
    WHERE id = t.id;
    EXCEPTION WHEN OTHERS THEN
      -- One subject must not take the rest of the run down with it. The
      -- skip is recorded rather than swallowed, and private.scheduled_job_health
      -- reports the job unhealthy while these rows are recent.
      INSERT INTO private.job_failures (job_name, subject_id, sqlstate, message)
      VALUES ('process_checkin_tasks', t.ward_id, SQLSTATE, SQLERRM);
    END;
  END LOOP;

  -- 2) 宽限到期：心跳判定完成与否；漏卡 → 通知设置者(自设则通知守护人/同组守望者)
  -- (Claim rows using FOR UPDATE SKIP LOCKED to prevent concurrent cron double-firing)
  FOR t IN
    SELECT * FROM public.checkin_tasks ct
    WHERE status = 'active' AND cycle_state = 'due_notified'
      AND next_due_at + make_interval(mins => ct.grace_minutes) <= now()
      AND NOT private.sleep_relaxed(ct.ward_id, now())
    FOR UPDATE SKIP LOCKED
  LOOP
    BEGIN
    -- Judge completion by REAL activity in behavior_pings (exists a behavior_pings row for ward_id with received_at >= next_due_at), NOT device_state.
    -- Live safety requires ingest_version=2, abs(received_at-observed_at)<=5m, received_at >= relevant alert/task time, observed_at >= relevant alert/task time.
    SELECT EXISTS (
      SELECT 1 FROM public.behavior_pings bp
      WHERE bp.user_id = t.ward_id
        AND bp.ingest_version = 2
        AND abs(extract(epoch from (bp.received_at - bp.at))) <= 300 -- drift <= 5m
        AND bp.received_at >= t.next_due_at
        AND bp.at >= t.next_due_at
    ) INTO _done;

    IF NOT _done THEN
      SELECT coalesce(display_name, '') INTO _wname FROM public.profiles WHERE id = t.ward_id;

      INSERT INTO public.notifications (recipient_id, kind, body, params)
      SELECT DISTINCT r.uid, 'task_missed',
        _wname || ' 未完成定时报平安，请关注。',
        jsonb_build_object('name', _wname, 'label', t.label)
      FROM (
        SELECT t.created_by AS uid WHERE t.created_by <> t.ward_id
        UNION
        SELECT g.guardian_id FROM public.guardianships g
          WHERE t.created_by = t.ward_id AND g.ward_id = t.ward_id AND g.status = 'active'
        UNION
        SELECT w.user_id FROM public.group_members gm
          JOIN public.group_members w ON w.group_id = gm.group_id
          WHERE t.created_by = t.ward_id
            AND gm.user_id = t.ward_id AND gm.monitored AND gm.status = 'active'
            AND w.watching AND w.status = 'active' AND w.user_id <> t.ward_id
            AND NOT EXISTS (SELECT 1 FROM public.guardianships g2
                            WHERE g2.ward_id = t.ward_id AND g2.status = 'active')
      ) r;
    END IF;

    -- 滚动下一轮（漏卡也滚动，避免重复轰炸；daily 跳到未来最近一个周期）
    IF t.kind = 'daily' THEN
      _timezone := null;
      SELECT timezone INTO _timezone FROM public.user_settings WHERE user_id = t.ward_id;
      _timezone := coalesce(_timezone, 'UTC');
      _local_date := (now() at time zone _timezone)::date;
      _candidate := (_local_date + t.due_time_local) at time zone _timezone;
      WHILE _candidate <= now() OR _candidate <= t.next_due_at LOOP
        _local_date := _local_date + 1;
        _candidate := (_local_date + t.due_time_local) at time zone _timezone;
      END LOOP;
    ELSE
      _candidate := now() + make_interval(hours => t.interval_hours);
    END IF;

    UPDATE public.checkin_tasks SET
      cycle_state = 'idle',
      next_due_at = _candidate,
      updated_at = now()
      WHERE id = t.id;
    EXCEPTION WHEN OTHERS THEN
      -- One subject must not take the rest of the run down with it. The
      -- skip is recorded rather than swallowed, and private.scheduled_job_health
      -- reports the job unhealthy while these rows are recent.
      INSERT INTO private.job_failures (job_name, subject_id, sqlstate, message)
      VALUES ('process_checkin_tasks', t.ward_id, SQLSTATE, SQLERRM);
    END;
  END LOOP;
END;
$$;
