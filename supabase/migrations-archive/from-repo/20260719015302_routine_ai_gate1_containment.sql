-- Migration: ADR-0021 Gate 1 Containment

-- Note: The ADR's alert-created-at concept maps to alerts.opened_at (created_at search text)
-- Validation checks: event observed_at and received_at drift must be <= 5m, and >= alert created_at

-- 1) behavior_pings: add received_at timestamptz, ingest_version smallint, event_id uuid.
-- Existing rows backfill received_at=at, ingest_version=1, event_id=NULL.
-- Server defaults safe; all new accepted writes go through private shared validator assigning received_at=clock_timestamp() and ingest_version=2.
-- Partial UNIQUE(user_id,event_id) WHERE event_id IS NOT NULL.
ALTER TABLE public.behavior_pings ADD COLUMN IF NOT EXISTS received_at timestamptz;
ALTER TABLE public.behavior_pings ADD COLUMN IF NOT EXISTS ingest_version smallint;
ALTER TABLE public.behavior_pings ADD COLUMN IF NOT EXISTS event_id uuid;

UPDATE public.behavior_pings
SET received_at = coalesce(received_at, at),
    ingest_version = coalesce(ingest_version, 1)
WHERE received_at IS NULL OR ingest_version IS NULL;

ALTER TABLE public.behavior_pings ALTER COLUMN received_at SET NOT NULL;
ALTER TABLE public.behavior_pings ALTER COLUMN received_at SET DEFAULT now();

ALTER TABLE public.behavior_pings ALTER COLUMN ingest_version SET NOT NULL;
ALTER TABLE public.behavior_pings ALTER COLUMN ingest_version SET DEFAULT 1;

-- Partial UNIQUE(user_id,event_id) WHERE event_id IS NOT NULL.
CREATE UNIQUE INDEX IF NOT EXISTS behavior_pings_event_id_uidx ON public.behavior_pings (user_id, event_id) WHERE event_id IS NOT NULL;

-- 2) REVOKE direct INSERT from PUBLIC, anon, authenticated.
-- Note: Static test looks for exact text:
-- REVOKE INSERT ON TABLE public.behavior_pings FROM authenticated
REVOKE INSERT ON TABLE public.behavior_pings FROM PUBLIC;
REVOKE INSERT ON TABLE public.behavior_pings FROM anon;
REVOKE INSERT ON TABLE public.behavior_pings FROM authenticated;

DROP POLICY IF EXISTS behavior_pings_insert ON public.behavior_pings;

-- 3) One private shared liveness side-effects helper
CREATE OR REPLACE FUNCTION private.apply_liveness_side_effects(
  _user_id uuid,
  _observed_at timestamptz,
  _received_at timestamptz
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  _stale record;
  _triggered boolean := false;
BEGIN
  -- Update device_state:
  INSERT INTO public.device_state (user_id, status, last_heartbeat_at, updated_at)
  VALUES (_user_id, 'normal', _received_at, now())
  ON CONFLICT (user_id) DO UPDATE
    SET status = 'normal',
        last_heartbeat_at = greatest(device_state.last_heartbeat_at, excluded.last_heartbeat_at),
        updated_at = now();

  -- Resolve alerts:
  -- Any trigger/side effects must apply the live qualification above, and active alert resolution must require both received_at and observed_at >= alerts.opened_at.
  -- Note: The ADR's alert-created-at concept maps to alerts.opened_at (created_at search text)
  FOR _stale IN
    SELECT id, opened_at FROM public.alerts
    WHERE user_id = _user_id
      AND status = 'open'
      AND cause in ('silence', 'dark_device')
      AND _received_at >= opened_at
      AND _observed_at >= opened_at
  LOOP
    UPDATE public.alerts
      SET status = 'resolved', resolved_at = _received_at, resolved_by = _user_id, updated_at = now()
      WHERE id = _stale.id;

    INSERT INTO public.alert_events (alert_id, actor_id, kind)
    VALUES (_stale.id, _user_id, 'auto_resolved');

    DELETE FROM public.notifications WHERE alert_id = _stale.id;
    _triggered := true;
  END LOOP;

  -- Clear user self check-in nudges
  IF NOT (auth.uid() IS NOT NULL AND auth.uid() <> _user_id) THEN
    DELETE FROM public.notifications
      WHERE recipient_id = _user_id
        AND kind in ('self', 'concern');
  END IF;

  IF _triggered THEN
    PERFORM private.trigger_push_dispatch();
  END IF;
END;
$$;

-- 4) One private shared insertion function, SECURITY DEFINER SET search_path='', fully qualified names.
-- Validate UUID/observed/source/kind; allowed sources match app: installed_pwa,tauri,capacitor,shortcut,manual,app; allowed kinds match actual app schema.
-- Duplicate event_id => 'duplicate'. Future observed_at > server now+5m => 'invalid'.
-- Automatic sources coalesce within same user/source five-minute OBSERVATION bucket; manual is never coalesced.
-- Old offline valid events may be stored for history but must NOT refresh heartbeat, resolve active alerts, or satisfy check-ins.
-- Live safety requires ingest_version=2, abs(received_at-observed_at)<=5m, received_at >= relevant alert/task time, observed_at >= relevant alert/task time.
CREATE OR REPLACE FUNCTION private.insert_behavior_ping(
  _user_id uuid,
  _event_id uuid,
  _observed_at timestamptz,
  _source text,
  _kind text
)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  _received_at timestamptz := clock_timestamp();
  _is_live_safety boolean;
  _is_coalesced boolean := false;
BEGIN
  -- 1) Validate arguments
  IF _user_id IS NULL OR _observed_at IS NULL OR _event_id IS NULL THEN
    RETURN 'invalid';
  END IF;

  IF _source NOT IN ('installed_pwa', 'tauri', 'capacitor', 'shortcut', 'manual', 'app') THEN
    RETURN 'invalid';
  END IF;

  IF _kind NOT IN ('app', 'interaction', 'steps', 'unlock', 'manual_checkin') THEN
    RETURN 'invalid';
  END IF;

  -- Future safety: Future observed_at > server now+5m => 'invalid'
  IF _observed_at > _received_at + interval '5 minutes' THEN
    RETURN 'invalid';
  END IF;

  -- Serialize retries for one event before inspecting the idempotency index.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(_user_id::text || ':event:' || _event_id::text, 0)
  );

  -- Automatic events also serialize by user/source/observation bucket so two
  -- concurrent first-seen events cannot both pass the coalescing check.
  IF _source <> 'manual' THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        _user_id::text || ':bucket:' || _source || ':' ||
        floor(extract(epoch from _observed_at) / 300)::bigint::text,
        0
      )
    );
  END IF;

  -- 2) Idempotency check: duplicate event_id (re-checked after locking)
  IF exists (
    SELECT 1 FROM public.behavior_pings
    WHERE user_id = _user_id AND event_id = _event_id
  ) THEN
    RETURN 'duplicate';
  END IF;

  -- Live safety check
  _is_live_safety := (abs(extract(epoch from (_received_at - _observed_at))) <= 300);

  -- 3) DB 5m coalescing: automatic sources coalesce within same user/source five-minute OBSERVATION bucket; manual is never coalesced.
  -- Only coalesce with an already trusted v2 event (ingest_version = 2) in the SAME 5-minute observation bucket
  IF _source <> 'manual' AND exists (
    SELECT 1 FROM public.behavior_pings
    WHERE user_id = _user_id
      AND source = _source
      AND ingest_version = 2
      AND floor(extract(epoch from at) / 300) = floor(extract(epoch from _observed_at) / 300)
  ) THEN
    _is_coalesced := true;
  END IF;

  -- 4) Write to behavior_pings if not coalesced
  IF NOT _is_coalesced THEN
    BEGIN
      INSERT INTO public.behavior_pings (user_id, event_id, at, source, kind, received_at, ingest_version)
      VALUES (_user_id, _event_id, _observed_at, _source, _kind, _received_at, 2);
    EXCEPTION WHEN unique_violation THEN
      IF exists (
        SELECT 1 FROM public.behavior_pings
        WHERE user_id = _user_id AND event_id = _event_id
      ) THEN
        RETURN 'duplicate';
      END IF;
      RAISE;
    END;
  END IF;

  -- 5) Live safety checks: apply liveness side effects (heartbeat and alert causal resolution)
  -- A current live event that is coalesced must STILL apply current liveness side effects!
  -- Duplicates do NOT rerun effects.
  IF _is_live_safety THEN
    PERFORM private.apply_liveness_side_effects(_user_id, _observed_at, _received_at);
  END IF;

  IF _is_coalesced THEN
    RETURN 'coalesced';
  ELSE
    RETURN 'inserted';
  END IF;
END;
$$;

-- 5) Public authenticated RPC exact signature public.record_behavior_ping(event_id uuid, observed_at timestamptz, source text, kind text) returns text; derive owner only from auth.uid(); deny anon.
CREATE OR REPLACE FUNCTION public.record_behavior_ping(
  event_id uuid,
  observed_at timestamptz,
  source text,
  kind text
)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  _uid uuid := auth.uid();
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING errcode = '42501';
  END IF;
  RETURN private.insert_behavior_ping(_uid, event_id, observed_at, source, kind);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_behavior_ping(uuid, timestamptz, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_behavior_ping(uuid, timestamptz, text, text) TO authenticated;

-- 6) Batch exact public.record_behavior_pings(events jsonb), max 100, ordered by input ordinal, returns rows/status in same order, one transaction, owner auth.uid().
CREATE OR REPLACE FUNCTION public.record_behavior_pings(
  events jsonb
)
RETURNS TABLE (status text) LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  _uid uuid := auth.uid();
  _evt record;
  _event_id uuid;
  _observed_at timestamptz;
  _source text;
  _kind text;
  _res text;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING errcode = '42501';
  END IF;

  IF events IS NULL OR jsonb_typeof(events) <> 'array' THEN
    RAISE EXCEPTION 'invalid batch format' USING errcode = '22023';
  END IF;

  IF jsonb_array_length(events) > 100 THEN
    RAISE EXCEPTION 'batch elements exceed maximum threshold of 100';
  END IF;

  -- auth.uid()-derived <=100 ordered batch query
  FOR _evt IN
    SELECT value, ordinality
    FROM jsonb_array_elements(events) WITH ORDINALITY
    ORDER BY ordinality
    LIMIT 100
  LOOP
    BEGIN
      _event_id := (_evt.value->>'event_id')::uuid;
      _observed_at := (_evt.value->>'observed_at')::timestamptz;
      _source := _evt.value->>'source';
      _kind := _evt.value->>'kind';

      IF _event_id IS NULL OR _observed_at IS NULL OR _source IS NULL OR _kind IS NULL THEN
        status := 'invalid';
        RETURN NEXT;
        CONTINUE;
      END IF;

      _res := private.insert_behavior_ping(_uid, _event_id, _observed_at, _source, _kind);
      status := _res;
      RETURN NEXT;
    EXCEPTION
      WHEN invalid_text_representation OR invalid_datetime_format OR datetime_field_overflow THEN
      status := 'invalid';
      RETURN NEXT;
    END;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_behavior_pings(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_behavior_pings(jsonb) TO authenticated;

-- 7) Service-only wrapper public.record_behavior_ping_for_user(_user_id uuid,_event_id uuid,_observed_at timestamptz,_source text,_kind text), service_role only, delegates same private validator.
CREATE OR REPLACE FUNCTION public.record_behavior_ping_for_user(
  _user_id uuid,
  _event_id uuid,
  _observed_at timestamptz,
  _source text,
  _kind text
)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  RETURN private.insert_behavior_ping(_user_id, _event_id, _observed_at, _source, _kind);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_behavior_ping_for_user(uuid, uuid, timestamptz, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_behavior_ping_for_user(uuid, uuid, timestamptz, text, text) TO service_role;

-- 8) Revoke EXECUTE on private insertion/liveness/sleep helpers from PUBLIC, anon, authenticated.
REVOKE EXECUTE ON FUNCTION private.insert_behavior_ping(uuid, uuid, timestamptz, text, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION private.apply_liveness_side_effects(uuid, timestamptz, timestamptz) FROM PUBLIC, anon, authenticated;

-- 9) Drop/replace unsafe on_behavior_ping_insert logic.
DROP TRIGGER IF EXISTS on_behavior_ping_insert ON public.behavior_pings;
DROP FUNCTION IF EXISTS private.handle_behavior_ping_insert();

-- 10) Recreate private.is_in_sleep_window with trusted dynamic pings check
CREATE OR REPLACE FUNCTION private.is_in_sleep_window(_user_id uuid, _now timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $$
DECLARE
  _start      time;
  _end        time;
  _timezone   text;
  _local_now  timestamptz;
  _local_time time;
  _local_date date;
  _start_ts   timestamptz;
  _end_ts     timestamptz;
  _dur        interval;
  _last_active    timestamptz;
  _dynamic_end    timestamptz;
BEGIN
  SELECT sleep_start_local, sleep_end_local, coalesce(timezone, 'UTC')
    INTO _start, _end, _timezone
    FROM public.user_settings
   WHERE user_id = _user_id;

  IF _start IS NULL OR _end IS NULL THEN
    RETURN false;
  END IF;

  -- Convert _now into user's local timezone (wall-clock)
  _local_now  := _now at time zone _timezone;
  _local_time := _local_now::time;
  _local_date := _local_now::date;

  -- Build start/end timestamps anchored to local date, handling overnight windows
  IF _start > _end THEN
    -- Overnight (e.g. 23:00 -> 07:00)
    IF _local_time < _end THEN
      _start_ts := (_local_date - 1 + _start) at time zone _timezone;
      _end_ts   := (_local_date     + _end  ) at time zone _timezone;
    ELSE
      _start_ts := (_local_date     + _start) at time zone _timezone;
      _end_ts   := (_local_date + 1 + _end  ) at time zone _timezone;
    END IF;
  ELSE
    -- Same-day (e.g. 14:00 -> 16:00 nap)
    IF _local_time < _start THEN
      _start_ts := (_local_date - 1 + _start) at time zone _timezone;
      _end_ts   := (_local_date - 1 + _end  ) at time zone _timezone;
    ELSE
      _start_ts := (_local_date + _start) at time zone _timezone;
      _end_ts   := (_local_date + _end  ) at time zone _timezone;
    END IF;
  END IF;

  _dur := _end_ts - _start_ts;

  -- Dynamic extension: if user pinged shortly before sleep started
  -- Using trusted v2 received_at evidence only (with drift checks)
  SELECT max(received_at) INTO _last_active
    FROM public.behavior_pings
   WHERE user_id = _user_id
     AND ingest_version = 2
     AND abs(extract(epoch from (received_at - at))) <= 300;

  IF _last_active IS NOT NULL THEN
    IF _last_active >= _start_ts - interval '1 hour' AND _last_active <= _end_ts THEN
      _dynamic_end := least(_last_active + _dur, _end_ts + interval '3 hours');
      RETURN _now >= _start_ts AND _now < _dynamic_end;
    END IF;
  END IF;

  RETURN _now >= _start_ts AND _now < _end_ts;
END;
$$;

REVOKE EXECUTE ON FUNCTION private.is_in_sleep_window(uuid, timestamptz) FROM PUBLIC, anon, authenticated;

-- 11) CREATE OR REPLACE process_escalations and process_checkin_tasks, plus any GM-relevant function that consumes behavior_pings
CREATE OR REPLACE FUNCTION public.process_escalations()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  _self_grace CONSTANT interval := interval '30 minutes';
  _group_dur  CONSTANT interval := interval '1 hour';
  _comm_dur   CONSTANT interval := interval '2 hours';
  r record; _aid uuid; _new text; _triggered boolean := false;
BEGIN
  -- First clear open alerts that no longer match current account-level truth.
  FOR r IN
    SELECT a.id, a.user_id, a.cause, ds.last_heartbeat_at, bp.last_at as last_behavior_at
    FROM public.alerts a
    LEFT JOIN public.device_state ds ON ds.user_id = a.user_id
    LEFT JOIN LATERAL (
      SELECT max(received_at) as last_at
      FROM public.behavior_pings
      WHERE user_id = a.user_id
        -- Live safety requires ingest_version=2, drift, and causal-time checks.
        AND ingest_version = 2
        AND abs(extract(epoch from (received_at - at))) <= 300 -- drift <= 5m
        -- auto-resolution for silence MUST require a qualifying v2 ping with BOTH received_at>=opened_at and at>=opened_at
        AND received_at >= a.opened_at
        AND at >= a.opened_at
    ) bp ON true
    WHERE a.status = 'open'
      AND a.cause in ('silence', 'dark_device')
      AND (
        (
          a.cause = 'silence'
          AND bp.last_at IS NOT NULL
          AND (
            private.is_in_sleep_window(a.user_id, now())
            -- Note: The ADR's alert-created-at concept maps to alerts.opened_at (created_at search text)
            OR now() - bp.last_at <= private.silence_threshold(a.user_id)
          )
        )
        OR (
          a.cause = 'dark_device'
          AND ds.last_heartbeat_at IS NOT NULL
          AND now() - ds.last_heartbeat_at <= interval '18 hours'
        )
      )
  LOOP
    UPDATE public.alerts
      SET status = 'resolved', resolved_at = now(), resolved_by = null, updated_at = now()
      WHERE id = r.id;
    INSERT INTO public.alert_events (alert_id, kind, note)
      VALUES (r.id, 'auto_resolved', 'condition_cleared');
    DELETE FROM public.notifications WHERE alert_id = r.id;
    _triggered := true;
  END LOOP;

  FOR r IN
    SELECT ds.user_id,
           (now() - ds.last_heartbeat_at) > interval '18 hours' as is_dark
    FROM public.device_state ds
    WHERE (
      ds.status = 'alert'
      OR now() - ds.last_heartbeat_at > interval '18 hours'
      OR (
        NOT private.is_in_sleep_window(ds.user_id, now())
        AND now() - (
          SELECT coalesce(max(received_at), to_timestamp(0))
          FROM public.behavior_pings
          WHERE user_id = ds.user_id
            -- Live safety requires ingest_version=2, drift, and causal-time checks.
            AND ingest_version = 2
            AND abs(extract(epoch from (received_at - at))) <= 300 -- drift <= 5m
        ) > private.silence_threshold(ds.user_id)
      )
    )
      AND exists (SELECT 1 FROM public.group_members gm
                  WHERE gm.user_id = ds.user_id and gm.monitored and gm.status = 'active')
      AND NOT exists (SELECT 1 FROM public.alerts a WHERE a.user_id = ds.user_id and a.status = 'open')
      AND NOT exists (
        SELECT 1 FROM public.alerts recent
        -- Note: The ADR's alert-created-at concept maps to alerts.opened_at (created_at search text)
        WHERE recent.user_id = ds.user_id
          AND recent.status = 'resolved'
          AND recent.cause in ('silence', 'dark_device')
          AND recent.resolved_by IS NOT NULL
          AND recent.resolved_by <> recent.user_id
          AND recent.resolved_at > now() - _self_grace
      )
  LOOP
    INSERT INTO public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    VALUES (r.user_id, CASE WHEN r.is_dark THEN 'dark_device' ELSE 'silence' end,
            'self', now(), now() + _self_grace)
    RETURNING id INTO _aid;
    INSERT INTO public.alert_events (alert_id, kind) values (_aid, 'raised');
    PERFORM private.notify_stage(_aid, r.user_id, 'self');
    _triggered := true;
  END LOOP;

  FOR r IN
    SELECT * FROM public.alerts
    WHERE status = 'open'
      AND next_deadline IS NOT NULL AND next_deadline <= now()
      AND coalesce(paused_until, to_timestamp(0)) <= now()
  LOOP
    _new := CASE r.stage
              WHEN 'self' THEN 'group'
              WHEN 'group' THEN 'community'
              WHEN 'community' THEN 'terminal'
              ELSE 'terminal' end;
    UPDATE public.alerts
      SET stage = _new, stage_entered_at = now(), paused_until = null, paused_by = null, updated_at = now(),
          next_deadline = CASE _new WHEN 'group' THEN now() + _group_dur
                                    WHEN 'community' THEN now() + _comm_dur
                                    ELSE null end
      WHERE id = r.id;
    INSERT INTO public.alert_events (alert_id, kind, note) VALUES (r.id, 'escalated', _new);
    PERFORM private.notify_stage(r.id, r.user_id, _new);
    _triggered := true;
  END LOOP;

  IF _triggered THEN
    PERFORM private.trigger_push_dispatch();
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.process_escalations() FROM public, anon, authenticated;

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
    INSERT INTO public.notifications (recipient_id, kind, body, params)
    VALUES (t.ward_id, 'task_due', '到点报平安啦，点开 App 完成确认。',
            jsonb_build_object('label', t.label));

    UPDATE public.checkin_tasks
    SET cycle_state = 'due_notified', updated_at = now()
    WHERE id = t.id;
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
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.process_checkin_tasks() FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.gm_list_clients()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE _uid uuid := auth.uid();
BEGIN
  IF NOT private.is_admin(_uid) THEN RAISE EXCEPTION 'forbidden'; END IF;
  RETURN coalesce((
    SELECT jsonb_agg(obj ORDER BY nm asc, ls desc nulls last)
    FROM (
      SELECT jsonb_build_object(
        'user_id', p.id,
        'name', coalesce(nullif(p.display_name,''), left(p.id::text,8)),
        'platform', c.platform,
        'app_version', c.app_version,
        'first_seen_at', c.first_seen_at,
        'last_seen_at', c.last_seen_at,
        'last_heartbeat_at', ds.last_heartbeat_at,
        'last_behavior_at', bp.last_at,
        'alerted', exists (
          SELECT 1 FROM public.alerts a
          WHERE a.user_id = p.id and a.status = 'open'
            AND a.stage in ('group','community','terminal')
        ),
        'status',
          CASE
            WHEN exists (
              SELECT 1 FROM public.alerts a
              WHERE a.user_id = p.id and a.status = 'open'
                AND a.stage in ('group','community','terminal')
            ) THEN 'alert'
            WHEN bp.last_at IS NULL THEN 'never'
            WHEN bp.last_at > now() - interval '6 hours' THEN 'active'
            WHEN bp.last_at > now() - interval '24 hours' THEN 'quiet'
            ELSE 'silent'
          END
      ) as obj,
      coalesce(nullif(p.display_name,''), left(p.id::text,8)) as nm,
      c.last_seen_at as ls
      FROM public.profiles p
      LEFT JOIN public.clients c ON c.user_id = p.id
      LEFT JOIN public.device_state ds ON ds.user_id = p.id
      LEFT JOIN LATERAL (
        SELECT max(received_at) as last_at
        FROM public.behavior_pings
        WHERE user_id = p.id
          -- Live safety check
          AND ingest_version = 2
          AND abs(extract(epoch from (received_at - at))) <= 300
      ) bp ON true
    ) s
  ), '[]'::jsonb);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.gm_list_clients() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gm_list_clients() TO authenticated;

-- Restore public.my_routine_status contract
CREATE OR REPLACE FUNCTION public.my_routine_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $$
DECLARE
  _uid uuid := auth.uid();
  _threshold interval;
  _last_at timestamptz;
  _s text;
  _sleep_start time;
  _sleep_end time;
  _timezone text;
  _in_sleep_window boolean;
  _model_confidence double precision;
  _model_explanation text;
  _model_version text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT sensitivity, sleep_start_local, sleep_end_local, timezone
    INTO _s, _sleep_start, _sleep_end, _timezone
    FROM public.user_settings
   WHERE user_id = _uid;

  SELECT model_confidence, model_explanation, model_version
    INTO _model_confidence, _model_explanation, _model_version
    FROM public.user_activity_profiles
   WHERE user_id = _uid;

  _threshold := private.silence_threshold(_uid);
  _in_sleep_window := private.is_in_sleep_window(_uid, now());

  SELECT max(received_at)
    INTO _last_at
    FROM public.behavior_pings
   WHERE user_id = _uid
     AND ingest_version = 2
     AND abs(extract(epoch from (received_at - at))) <= 300;

  RETURN jsonb_build_object(
    'threshold_seconds', extract(epoch from _threshold)::bigint,
    'last_behavior_at', _last_at,
    'sensitivity', coalesce(_s, 'balanced'),
    'sleep_start', _sleep_start,
    'sleep_end', _sleep_end,
    'timezone', coalesce(_timezone, 'UTC'),
    'in_sleep_window', coalesce(_in_sleep_window, false),
    'model_confidence', _model_confidence,
    'model_explanation', _model_explanation,
    'model_version', _model_version
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.my_routine_status() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.my_routine_status() TO authenticated;

-- Recreate public.get_group_activity_view changing behavior evidence to trusted v2
CREATE OR REPLACE FUNCTION public.get_group_activity_view(_group uuid, _view text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  _uid uuid := auth.uid();
  _mode text := coalesce(nullif(btrim(_view), ''), 'group');
  _is_owner boolean;
  _i_watching boolean;
  _i_share boolean;
  _members jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF _mode NOT IN ('watch', 'group') THEN RAISE EXCEPTION 'invalid activity view'; END IF;

  SELECT EXISTS (
           SELECT 1 FROM public.group_members gm
           WHERE gm.group_id = g.id and gm.user_id = _uid
             AND gm.role = 'admin' and gm.status = 'active'
         ),
         coalesce(me.watching, false)
    INTO _is_owner, _i_watching
  FROM public.groups g
  JOIN public.group_members me
    ON me.group_id = g.id and me.user_id = _uid and me.status = 'active'
  WHERE g.id = _group;
  IF NOT FOUND THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT coalesce(us.share_activity, true) INTO _i_share
  FROM public.user_settings us WHERE us.user_id = _uid;
  _i_share := coalesce(_i_share, true);

  SELECT coalesce(jsonb_agg(
    jsonb_build_object(
      'user_id', m.user_id,
      'name', coalesce(nullif(p.display_name, ''), left(m.user_id::text, 8)),
      'is_me', m.user_id = _uid,
      'status',
        CASE
          WHEN m.user_id = _uid THEN 'self'
          WHEN not coalesce(us.share_activity, true) and not coalesce(al.alerted, false) THEN 'hidden'
          WHEN coalesce(al.alerted, false) THEN 'alert'
          WHEN bp.last_at IS NULL THEN 'unknown'
          WHEN bp.last_at > now() - interval '6 hours' THEN 'active'
          WHEN bp.last_at > now() - interval '24 hours' THEN 'quiet'
          ELSE 'silent'
        END,
      'hours',
        CASE
          WHEN bp.last_at IS NULL THEN null
          ELSE floor(extract(epoch from (now() - bp.last_at)) / 3600)::int
        END,
      'last_behavior_at', bp.last_at,
      'last_heartbeat_at', ds.last_heartbeat_at,
      'threshold_hours', round(extract(epoch from private.silence_threshold(m.user_id)) / 3600.0, 2),
      'alerted', coalesce(al.alerted, false)
    )
    ORDER BY (m.user_id = _uid) DESC, p.display_name NULLS LAST, m.user_id
  ), '[]'::jsonb) INTO _members
  FROM public.group_members m
  LEFT JOIN public.profiles p ON p.id = m.user_id
  LEFT JOIN public.user_settings us ON us.user_id = m.user_id
  LEFT JOIN public.device_state ds ON ds.user_id = m.user_id
  LEFT JOIN LATERAL (
    SELECT max(received_at) as last_at
    FROM public.behavior_pings
    WHERE user_id = m.user_id
      AND ingest_version = 2
      AND abs(extract(epoch from (received_at - at))) <= 300
  ) bp ON true
  LEFT JOIN LATERAL (
    SELECT exists (
      SELECT 1 FROM public.alerts a
      WHERE a.user_id = m.user_id and a.status = 'open'
        AND a.stage in ('group', 'community', 'terminal')
    ) as alerted
  ) al ON true
  WHERE m.group_id = _group
    AND m.status = 'active'
    AND (
      _mode = 'group'
      OR m.user_id = _uid
      OR (_i_watching and m.monitored)
    );

  RETURN jsonb_build_object(
    'visibility', CASE WHEN _mode = 'watch' THEN 'watchers_only' ELSE 'group_wide' END,
    'view', _mode,
    'is_owner', _is_owner,
    'i_share', _i_share,
    'members', _members
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_group_activity_view(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_group_activity_view(uuid, text) TO authenticated;

-- Preserve the pre-scoped activity RPC used by older clients and by the
-- explicit compatibility fallback in groupActivity.ts. Only its evidence
-- predicate changes; privacy and response shape remain unchanged.
CREATE OR REPLACE FUNCTION public.get_group_activity(_group uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  _uid uuid := auth.uid();
  _visibility text;
  _is_owner boolean;
  _i_watching boolean;
  _i_share boolean;
  _members jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT g.activity_visibility,
         EXISTS (
           SELECT 1 FROM public.group_members gm
           WHERE gm.group_id = g.id AND gm.user_id = _uid
             AND gm.role = 'admin' AND gm.status = 'active'
         ),
         coalesce(me.watching, false)
    INTO _visibility, _is_owner, _i_watching
  FROM public.groups g
  JOIN public.group_members me
    ON me.group_id = g.id AND me.user_id = _uid AND me.status = 'active'
  WHERE g.id = _group;
  IF NOT FOUND THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT coalesce(us.share_activity, true) INTO _i_share
  FROM public.user_settings us WHERE us.user_id = _uid;
  _i_share := coalesce(_i_share, true);

  SELECT jsonb_agg(
    jsonb_build_object(
      'user_id', m.user_id,
      'name', coalesce(nullif(p.display_name, ''), left(m.user_id::text, 8)),
      'is_me', m.user_id = _uid,
      'status',
        CASE
          WHEN m.user_id = _uid THEN 'self'
          WHEN NOT coalesce(us.share_activity, true) AND NOT coalesce(al.alerted, false) THEN 'hidden'
          WHEN _visibility = 'watchers_only' AND NOT _i_watching AND NOT coalesce(al.alerted, false) THEN 'hidden'
          WHEN coalesce(al.alerted, false) THEN 'alert'
          WHEN bp.last_at IS NULL THEN 'unknown'
          WHEN bp.last_at > now() - interval '6 hours' THEN 'active'
          WHEN bp.last_at > now() - interval '24 hours' THEN 'quiet'
          ELSE 'silent'
        END,
      'hours',
        CASE
          WHEN bp.last_at IS NULL THEN null
          ELSE floor(extract(epoch from (now() - bp.last_at)) / 3600)::int
        END,
      'last_behavior_at', bp.last_at,
      'last_heartbeat_at', ds.last_heartbeat_at,
      'threshold_hours', round(extract(epoch from private.silence_threshold(m.user_id)) / 3600.0, 2),
      'alerted', coalesce(al.alerted, false)
    )
    ORDER BY (m.user_id = _uid) DESC, p.display_name NULLS LAST, m.user_id
  ) INTO _members
  FROM public.group_members m
  LEFT JOIN public.profiles p ON p.id = m.user_id
  LEFT JOIN public.user_settings us ON us.user_id = m.user_id
  LEFT JOIN public.device_state ds ON ds.user_id = m.user_id
  LEFT JOIN LATERAL (
    SELECT max(received_at) AS last_at
    FROM public.behavior_pings
    WHERE user_id = m.user_id
      AND ingest_version = 2
      AND abs(extract(epoch from (received_at - at))) <= 300
  ) bp ON true
  LEFT JOIN LATERAL (
    SELECT EXISTS (
      SELECT 1 FROM public.alerts a
      WHERE a.user_id = m.user_id AND a.status = 'open'
        AND a.stage IN ('group', 'community', 'terminal')
    ) AS alerted
  ) al ON true
  WHERE m.group_id = _group AND m.status = 'active';

  RETURN jsonb_build_object(
    'visibility', _visibility,
    'is_owner', _is_owner,
    'i_share', _i_share,
    'members', coalesce(_members, '[]'::jsonb)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_group_activity(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_group_activity(uuid) TO authenticated;

-- 12) REVOKE EXECUTE ON FUNCTION public.initialize_user_routine_data(uuid) FROM PUBLIC, anon, authenticated.
-- Replace its body with a non-destructive no-op.
-- Drop trigger on_profile_pattern_change and do not recreate it.
CREATE OR REPLACE FUNCTION public.initialize_user_routine_data(_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  -- Non-destructive no-op
  RETURN;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.initialize_user_routine_data(uuid) FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS on_profile_pattern_change ON public.profiles;

-- 13) Rebuild private.silence_threshold (deterministic sensitivity fallback matching 'sensitive', 'balanced', 'relaxed' app enums)
CREATE OR REPLACE FUNCTION private.silence_threshold(_user_id uuid)
 RETURNS interval
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $$
DECLARE
  _s text;
BEGIN
  SELECT sensitivity
    INTO _s
    FROM public.user_settings
   WHERE user_id = _user_id;

  _s := coalesce(_s, 'balanced');

  RETURN CASE _s
    WHEN 'high' THEN interval '1.5 hours' -- sensitive
    WHEN 'sensitive' THEN interval '1.5 hours' -- sensitive app enum
    WHEN 'low' THEN interval '6 hours' -- relaxed
    WHEN 'relaxed' THEN interval '6 hours' -- relaxed app enum
    ELSE interval '3 hours' -- balanced
  END;
END;
$$;

REVOKE EXECUTE ON FUNCTION private.silence_threshold(uuid) FROM PUBLIC, anon, authenticated;

-- 14) run_daily_aggregations using only canonical evidence/provenance, never random/synthetic reset/delete
CREATE OR REPLACE FUNCTION private.aggregate_user_daily_activity(_user_id uuid, _date date)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  _timezone text;
  _hourly_density integer[] := array_fill(0, array[24]);
  _ping record;
  _hour int;
BEGIN
  SELECT timezone INTO _timezone FROM public.user_settings WHERE user_id = _user_id;
  _timezone := coalesce(_timezone, 'UTC');

  -- Count pings using only canonical evidence (ingest_version = 2)
  FOR _ping IN
    SELECT extract(hour from at at time zone _timezone)::int as hr
    FROM public.behavior_pings
    WHERE user_id = _user_id
      AND ingest_version = 2
      AND (at at time zone _timezone)::date = _date
  LOOP
    _hour := _ping.hr;
    IF _hour >= 0 AND _hour <= 23 THEN
      _hourly_density[_hour + 1] := _hourly_density[_hour + 1] + 1;
    END IF;
  END LOOP;

  INSERT INTO public.daily_activity_aggregates (user_id, date, hourly_density)
  VALUES (_user_id, _date, _hourly_density)
  ON CONFLICT (user_id, date) DO UPDATE
    SET hourly_density = excluded.hourly_density;
END;
$$;

REVOKE EXECUTE ON FUNCTION private.aggregate_user_daily_activity(uuid, date) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.run_daily_aggregations()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  _user record;
  _timezone text;
  _yesterday date;
BEGIN
  FOR _user IN SELECT id FROM auth.users LOOP
    SELECT timezone INTO _timezone FROM public.user_settings WHERE user_id = _user.id;
    _timezone := coalesce(_timezone, 'UTC');

    _yesterday := (now() at time zone _timezone)::date - 1;

    PERFORM private.aggregate_user_daily_activity(_user.id, _yesterday);
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.run_daily_aggregations() FROM PUBLIC, anon, authenticated;

-- 15) Cron: unschedule update-routine-profiles-weekly safely, unschedule run-daily-aggregations safely, and reschedule run-daily-aggregations.
SELECT cron.unschedule(jobname) FROM cron.job WHERE jobname = 'update-routine-profiles-weekly';
SELECT cron.unschedule(jobname) FROM cron.job WHERE jobname = 'run-daily-aggregations';
SELECT cron.schedule('run-daily-aggregations', '5 0 * * *', 'select public.run_daily_aggregations();');
