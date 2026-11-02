-- Losing the device never escalates to terminal (human decisions 2026-11-02:
-- plan A for device_unreachable; also cap collection_restricted and legacy dark_device).
--
-- KC losing the device (powered off, flat, unplugged), or the subject turning detection
-- off, is not evidence that the person stopped moving. ADR-0040 rev.1 forbids judging
-- device_off as a missing person; ADR-0039 rev.1 lets it reach group / community only,
-- worded as "KC lost contact".
--
-- Production, 90 days before this migration: terminal was reached by 17 passive
-- device_unreachable alerts (6 "address unlocked" notices; 11 closed by the subject
-- themselves) and 11 legacy dark_device alerts (23 notices). No alert was open when
-- this was written, so no historical row is rewritten (human decision: leave history).
--
-- 1. process_escalations() holds these alerts at their current stage instead of
--    promoting them to terminal, and clears next_deadline so they stop being
--    re-evaluated. Applies to: passive alerts whose last causal window is
--    device_unreachable or collection_restricted, and legacy cause='dark_device'.
--    emergency_info_select only reveals data at stage='terminal' (or cause='sos'), so
--    holding the stage is what keeps the profile locked. Unchanged: passive 'silent',
--    legacy cause='silence', SOS. Alerts still close on recovered activity or
--    acknowledgement (resolve_activity_alerts covers dark_device).
-- 2. The legacy notifier stops calling a dark device "abnormal silence" / "long missing",
--    uses the passive engine's device_unreachable wording, and sends
--    params.miss_kind='device_unreachable' like the passive notifier. The web and Android
--    clients render group/community copy from params.miss_kind (they ignore the server
--    body for these kinds). SOS and legacy silence wording is unchanged.
-- 3. A trigger on public.alerts refuses to set stage='terminal' on such an alert, so the
--    guarantee does not live only in process_escalations(). A protection written as a
--    field check inside one function is exactly what another branch, or a later
--    CREATE OR REPLACE copied from an older body (Memory M6), silently bypasses. If that
--    happens the UPDATE fails, process_escalations() records it in private.job_failures,
--    and the alert stays where it was instead of unlocking the profile. Rows already at
--    terminal are untouched.
--
-- Bodies copied from the latest definitions, verified identical to production on
-- 2026-11-02 (whitespace-insensitive md5): process_escalations from
-- 20260923054905_activity_auto_resolution_guardian_pattern.sql; the legacy notifier from
-- 20260920000000_proactive_care_and_safe_ack.sql with the 20260923054905 self-stage
-- wording already applied. CREATE OR REPLACE keeps owners and EXECUTE grants.

CREATE OR REPLACE FUNCTION public.process_escalations()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE
  _self_grace CONSTANT interval:=interval '30 minutes';
  _group_dur CONSTANT interval:=interval '1 hour';
  _comm_dur CONSTANT interval:=interval '2 hours';
  r record; _aid uuid; _new text; _kind text; _triggered boolean:=false;
BEGIN
  FOR r IN SELECT DISTINCT user_id FROM public.alerts WHERE status='open' LOOP BEGIN
    PERFORM private.resolve_activity_alerts(r.user_id);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO private.job_failures(job_name,subject_id,sqlstate,message)
    VALUES('process_escalations',r.user_id,SQLSTATE,SQLERRM);
  END; END LOOP;
  IF to_regclass('private.passive_checkin_runtime_control') IS NOT NULL
     AND (SELECT NOT globally_disabled FROM private.passive_checkin_runtime_control WHERE singleton) THEN
    BEGIN
      PERFORM public.process_passive_checkins();
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO private.job_failures(job_name,subject_id,sqlstate,message)
      VALUES('process_passive_checkins',NULL,SQLSTATE,SQLERRM);
    END;
  END IF;
  FOR r IN SELECT a.id,a.user_id FROM public.alerts a
    WHERE a.status='open' AND a.cause='silence' AND NOT private.guardian_requires_pattern(a.user_id) AND private.sleep_relaxed(a.user_id,now())
      AND NOT EXISTS(SELECT 1 FROM private.passive_alert_causal_windows c WHERE c.alert_id=a.id)
  LOOP BEGIN
    UPDATE public.alerts SET status='resolved',resolved_at=now(),resolved_by=NULL,updated_at=now() WHERE id=r.id;
    INSERT INTO public.alert_events(alert_id,kind,note) VALUES(r.id,'auto_resolved','sleep_grace');
    PERFORM private.notify_auto_resolved(r.id,r.user_id); _triggered:=true;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO private.job_failures(job_name,subject_id,sqlstate,message)
    VALUES('process_escalations',r.user_id,SQLSTATE,SQLERRM);
  END; END LOOP;

  FOR r IN
    SELECT ds.user_id,(now()-ds.last_heartbeat_at)>interval '18 hours' AS is_dark
    FROM public.device_state ds
    WHERE (now()-ds.last_heartbeat_at>interval '18 hours' OR (
      NOT private.sleep_relaxed(ds.user_id,now()) AND now()-(
        SELECT coalesce(max(received_at),to_timestamp(0)) FROM public.behavior_pings
        WHERE user_id=ds.user_id AND ingest_version=2
          AND abs(extract(epoch FROM(received_at-at)))<=300
      )>private.silence_threshold(ds.user_id)))
      AND EXISTS(SELECT 1 FROM public.group_members gm WHERE gm.user_id=ds.user_id AND gm.monitored AND gm.status='active')
      AND NOT EXISTS(SELECT 1 FROM public.alerts a WHERE a.user_id=ds.user_id AND a.status='open')
      AND NOT EXISTS(SELECT 1 FROM public.passive_checkin_accounts p
        WHERE p.user_id=ds.user_id AND p.engine_mode='passive_checkin')
      AND NOT EXISTS(SELECT 1 FROM public.alerts recent WHERE recent.user_id=ds.user_id
        AND recent.status='resolved' AND recent.cause IN('silence','dark_device')
        AND recent.resolved_by IS NOT NULL AND recent.resolved_by<>recent.user_id
        AND recent.resolved_at>now()-_self_grace)
      AND NOT EXISTS(SELECT 1 FROM public.gm_mutes mute WHERE mute.user_id=ds.user_id
        AND(mute.muted_until IS NULL OR mute.muted_until>now()))
  LOOP BEGIN
    INSERT INTO public.alerts(user_id,cause,stage,stage_entered_at,next_deadline)
    VALUES(r.user_id,CASE WHEN r.is_dark THEN 'dark_device' ELSE 'silence' END,'self',now(),now()+_self_grace)
    RETURNING id INTO _aid;
    INSERT INTO public.alert_events(alert_id,kind) VALUES(_aid,'raised');
    PERFORM private.notify_stage(_aid,r.user_id,'self'); _triggered:=true;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO private.job_failures(job_name,subject_id,sqlstate,message)
    VALUES('process_escalations',r.user_id,SQLSTATE,SQLERRM);
  END; END LOOP;

  FOR r IN SELECT * FROM public.alerts a WHERE status='open' AND next_deadline IS NOT NULL
    AND next_deadline<=now() AND coalesce(paused_until,to_timestamp(0))<=now()
    AND (NOT EXISTS(SELECT 1 FROM private.passive_alert_causal_windows c WHERE c.alert_id=a.id)
      OR NOT EXISTS(
        SELECT 1 FROM public.passive_checkin_accounts p
        WHERE p.user_id=a.user_id AND private.passive_sleep_relaxed(a.user_id,p.active_contract_version_id,now())
      ))
  LOOP BEGIN
    PERFORM private.resolve_activity_alerts(r.user_id);
    _new:=CASE r.stage WHEN 'self' THEN 'group' WHEN 'group' THEN 'community'
      WHEN 'community' THEN 'terminal' ELSE 'terminal' END;
    -- Same lookup as private.notify_stage: the kind of the last causal window.
    _kind:=NULL;
    SELECT causal_window.miss_kind INTO _kind
    FROM private.passive_alert_causal_windows AS causal
    JOIN public.passive_checkin_windows AS causal_window ON causal_window.id=causal.window_id
    WHERE causal.alert_id=r.id
    ORDER BY causal_window.ordinal DESC LIMIT 1;
    IF _new='terminal' AND (r.cause='dark_device'
        OR _kind IN('device_unreachable','collection_restricted')) THEN
      -- Losing the device, or not being allowed to look, is not evidence about the person:
      -- hold at the current stage, stop the clock, send nothing, and never unlock the
      -- address or emergency contacts.
      UPDATE public.alerts SET next_deadline=NULL,updated_at=now()
      WHERE id=r.id AND status='open' AND stage=r.stage;
      CONTINUE;
    END IF;
    UPDATE public.alerts SET stage=_new,stage_entered_at=now(),paused_until=NULL,paused_by=NULL,
      updated_at=now(),next_deadline=CASE _new WHEN 'group' THEN now()+_group_dur
        WHEN 'community' THEN now()+_comm_dur ELSE NULL END WHERE id=r.id AND status='open' AND stage=r.stage;
    IF NOT FOUND THEN CONTINUE; END IF;
    INSERT INTO public.alert_events(alert_id,kind,note) VALUES(r.id,'escalated',_new);
    PERFORM private.notify_stage(r.id,r.user_id,_new); _triggered:=true;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO private.job_failures(job_name,subject_id,sqlstate,message)
    VALUES('process_escalations',r.user_id,SQLSTATE,SQLERRM);
  END; END LOOP;
  IF _triggered THEN PERFORM private.trigger_push_dispatch(); END IF;
END;
$$;

-- Legacy (non-passive) notifier: a dark device is reported as lost contact, not silence.
CREATE OR REPLACE FUNCTION private.notify_stage_before_passive_checkin(
  _alert_id uuid, _user uuid, _stage text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
declare _name text; _p jsonb; _sos boolean; _dark boolean;
begin
  select coalesce(display_name,'') into _name from public.profiles where id = _user;
  select (cause = 'sos'), (cause = 'dark_device') into _sos, _dark from public.alerts where id = _alert_id;
  -- Same machine-readable kind the passive notifier sends, so every client picks the
  -- device wording from one rule (params.miss_kind) instead of calling it silence.
  _p := jsonb_build_object('name', _name) || CASE WHEN _dark
    THEN jsonb_build_object('cause','dark_device','miss_kind','device_unreachable')
    ELSE '{}'::jsonb END;

  if _stage = 'self' then
    if not _sos then
      insert into public.notifications (recipient_id, alert_id, kind, body, params)
      values (_user, _alert_id, 'self',
        'KC 正在确认您的安全。请点“一切安好”，或打开应用按提示确认。', _p);
    end if;
    return;
  end if;

  if _stage = 'group' then
    insert into public.notifications (recipient_id, alert_id, kind, body, params)
    select distinct s.r, _alert_id,
      case when _sos then 'sos' else 'group' end,
      case when _sos then _name || ' 发出了紧急求助！'
           when _dark then _name || ' 的设备与 KC 失去联系，可能已关机或没电。请尝试联系本人确认。'
           else _name || ' 出现异常沉默，请尽快联系确认其安全。' end,
      _p
    from (
      select w.user_id as r from public.group_members t
        join public.group_members w on w.group_id = t.group_id
        where t.user_id = _user and t.monitored and t.status = 'active'
          and w.watching and w.status = 'active' and w.user_id <> _user
      union
      select guardian_id as r from public.guardianships
        where ward_id = _user and status = 'active'
    ) s;
  elsif _stage = 'community' then
    insert into public.notifications (recipient_id, alert_id, kind, body, params)
    select distinct m.user_id, _alert_id, 'community',
      case when _dark then 'KC 与 ' || _name || ' 的设备持续失去联系且小组尚未响应，请协助联系。'
           else '社区警示：' || _name || ' 长时间失联且其小组无人响应，请协助推动联系。' end, _p
    from public.community_members m
    where m.community_id in (
      select community_id from public.community_members where user_id = _user and status = 'active'
    ) and m.user_id <> _user and m.status = 'active';
  elsif _stage = 'terminal' then
    insert into public.notifications (recipient_id, alert_id, kind, body, params)
    select distinct s.r, _alert_id, 'terminal',
      '紧急：' || _name || ' 持续无响应。已为你解锁其地址与紧急联系人，请上门探视或协助报警。', _p
    from (
      select w.user_id as r from public.group_members t
        join public.group_members w on w.group_id = t.group_id
        where t.user_id = _user and t.monitored and t.status = 'active'
          and w.watching and w.status = 'active' and w.user_id <> _user
      union
      select guardian_id as r from public.guardianships
        where ward_id = _user and status = 'active'
    ) s;
  end if;
end;
$$;

-- Defense in depth: no code path may move a device-loss alert to terminal.
CREATE OR REPLACE FUNCTION private.device_loss_alert_never_terminal()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _kind text;
BEGIN
  IF NEW.stage IS DISTINCT FROM 'terminal'
     OR (TG_OP='UPDATE' AND OLD.stage IS NOT DISTINCT FROM 'terminal') THEN
    RETURN NEW;
  END IF;
  SELECT causal_window.miss_kind INTO _kind
  FROM private.passive_alert_causal_windows AS causal
  JOIN public.passive_checkin_windows AS causal_window ON causal_window.id=causal.window_id
  WHERE causal.alert_id=NEW.id
  ORDER BY causal_window.ordinal DESC LIMIT 1;
  IF NEW.cause='dark_device' OR _kind IN('device_unreachable','collection_restricted') THEN
    RAISE EXCEPTION 'device_loss_alert_never_terminal: alert % (cause %, miss_kind %)',
      NEW.id, NEW.cause, coalesce(_kind,'none')
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.device_loss_alert_never_terminal() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS alerts_device_loss_never_terminal ON public.alerts;
CREATE TRIGGER alerts_device_loss_never_terminal
BEFORE INSERT OR UPDATE OF stage ON public.alerts
FOR EACH ROW EXECUTE FUNCTION private.device_loss_alert_never_terminal();
