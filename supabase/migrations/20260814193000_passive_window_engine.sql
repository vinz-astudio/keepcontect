-- ADR-0042 package 6: deterministic windows, miss chains and alert authority.

CREATE TABLE private.passive_window_transitions (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  window_id uuid NOT NULL REFERENCES public.passive_checkin_windows(id) ON DELETE CASCADE,
  old_outcome text NOT NULL,
  new_outcome text NOT NULL,
  reason text NOT NULL CHECK (reason IN (
    'positive_evidence','deadline_elapsed','contract_changed','epoch_reset','late_positive','other'
  )),
  causal_evidence_id uuid,
  actor text NOT NULL DEFAULT current_user,
  changed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE private.passive_window_transitions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.passive_window_transitions FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.capture_passive_window_transition()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
  IF OLD.outcome IS DISTINCT FROM NEW.outcome THEN
    INSERT INTO private.passive_window_transitions(
      user_id,window_id,old_outcome,new_outcome,reason,causal_evidence_id
    ) VALUES (
      NEW.user_id,NEW.id,OLD.outcome,NEW.outcome,
      CASE
        WHEN NEW.outcome='checked_in' AND OLD.outcome='missed' THEN 'late_positive'
        WHEN NEW.outcome='checked_in' THEN 'positive_evidence'
        WHEN NEW.outcome='missed' THEN 'deadline_elapsed'
        WHEN NEW.outcome='superseded' AND NEW.superseded_reason='contract_changed' THEN 'contract_changed'
        WHEN NEW.outcome='superseded' THEN 'epoch_reset'
        ELSE 'other'
      END,
      NEW.causal_evidence_id
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER passive_checkin_windows_transition_audit
AFTER UPDATE ON public.passive_checkin_windows
FOR EACH ROW EXECUTE FUNCTION private.capture_passive_window_transition();

CREATE FUNCTION private.reject_passive_snapshot_mutation()
RETURNS trigger LANGUAGE plpgsql SET search_path TO '' AS $$
BEGIN
  RAISE EXCEPTION 'passive causal snapshots and transitions are immutable' USING ERRCODE='55000';
END;
$$;
CREATE TRIGGER passive_alert_causal_windows_immutable
BEFORE UPDATE ON private.passive_alert_causal_windows
FOR EACH ROW EXECUTE FUNCTION private.reject_passive_snapshot_mutation();
CREATE TRIGGER passive_window_transitions_immutable
BEFORE UPDATE ON private.passive_window_transitions
FOR EACH ROW EXECUTE FUNCTION private.reject_passive_snapshot_mutation();

CREATE FUNCTION private.passive_window_arrival_allowance(
  _user_id uuid, _window_start timestamptz, _window_end timestamptz
) RETURNS interval LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
  SELECT coalesce(max(registry.arrival_allowance), interval '0')
  FROM private.passive_collector_bindings AS binding
  JOIN private.passive_surface_registry AS registry USING(surface_type)
  WHERE binding.user_id = _user_id
    AND binding.bound_at < _window_end
    AND coalesce(binding.revoked_at, 'infinity'::timestamptz) > _window_start
$$;

CREATE FUNCTION private.passive_sleep_relaxed(
  _user_id uuid, _contract_id uuid, _at timestamptz
) RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE
  _c public.passive_checkin_contract_versions%ROWTYPE;
  _local timestamp;
  _date date;
  _time time;
  _start timestamptz;
  _finish timestamptz;
  _duration interval;
  _last_active timestamptz;
BEGIN
  SELECT * INTO _c FROM public.passive_checkin_contract_versions
  WHERE id=_contract_id AND user_id=_user_id;
  IF NOT FOUND OR _c.sleep_policy <> 'configured' THEN RETURN false; END IF;

  _local := _at AT TIME ZONE _c.timezone;
  _date := _local::date;
  _time := _local::time;
  IF _c.sleep_start_local > _c.sleep_end_local THEN
    -- Between wake and the next bedtime, keep the just-finished night as the
    -- anchor so the two-hour post-wake grace remains representable.
    IF _time < _c.sleep_start_local THEN
      _start := ((_date-1)+_c.sleep_start_local) AT TIME ZONE _c.timezone;
      _finish := (_date+_c.sleep_end_local) AT TIME ZONE _c.timezone;
    ELSE
      _start := (_date+_c.sleep_start_local) AT TIME ZONE _c.timezone;
      _finish := ((_date+1)+_c.sleep_end_local) AT TIME ZONE _c.timezone;
    END IF;
  ELSE
    IF _time < _c.sleep_start_local THEN
      _start := ((_date-1)+_c.sleep_start_local) AT TIME ZONE _c.timezone;
      _finish := ((_date-1)+_c.sleep_end_local) AT TIME ZONE _c.timezone;
    ELSE
      _start := (_date+_c.sleep_start_local) AT TIME ZONE _c.timezone;
      _finish := (_date+_c.sleep_end_local) AT TIME ZONE _c.timezone;
    END IF;
  END IF;
  _duration := _finish-_start;

  SELECT max(activity_at) INTO _last_active FROM (
    SELECT max(event.observed_at) AS activity_at
    FROM private.passive_evidence_events AS event
    WHERE event.user_id=_user_id AND event.observed_at BETWEEN _start-interval '1 hour' AND _finish
    UNION ALL
    SELECT max(ping.received_at)
    FROM public.behavior_pings AS ping
    WHERE ping.user_id=_user_id AND ping.ingest_version=2
      AND abs(extract(epoch FROM (ping.received_at-ping.at)))<=300
      AND ping.received_at BETWEEN _start-interval '1 hour' AND _finish
  ) activity;
  IF _last_active IS NOT NULL THEN
    _finish := least(_last_active+_duration,_finish+interval '3 hours');
  END IF;
  RETURN _at>=_start AND _at<_finish+interval '2 hours';
END;
$$;

CREATE FUNCTION private.maybe_open_passive_checkin_alert(
  _user_id uuid, _epoch_id uuid, _contract_id uuid, _now timestamptz
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _account public.passive_checkin_accounts%ROWTYPE;
  _contract public.passive_checkin_contract_versions%ROWTYPE;
  _chain bigint; _alert_id uuid;
BEGIN
  SELECT * INTO _account FROM public.passive_checkin_accounts WHERE user_id=_user_id;
  SELECT * INTO STRICT _contract FROM public.passive_checkin_contract_versions WHERE id=_contract_id;
  SELECT count(*) INTO _chain FROM public.passive_checkin_windows candidate
  WHERE candidate.epoch_id=_epoch_id AND candidate.outcome='missed'
    AND NOT EXISTS(SELECT 1 FROM public.passive_checkin_windows later
      WHERE later.epoch_id=_epoch_id AND later.ordinal>candidate.ordinal
        AND later.outcome IN('checked_in','superseded'));
  IF _account.engine_mode<>'passive_checkin' OR _account.kill_switch_active
     OR _chain<_contract.consecutive_misses
     OR private.passive_sleep_relaxed(_user_id,_contract_id,_now)
     OR EXISTS(SELECT 1 FROM public.alerts WHERE user_id=_user_id AND status='open') THEN
    RETURN NULL;
  END IF;
  INSERT INTO public.alerts(user_id,cause,stage,stage_entered_at,next_deadline,requires_explicit_unlock)
  VALUES(_user_id,'silence','self',_now,_now+interval '30 minutes',true)
  RETURNING id INTO _alert_id;
  INSERT INTO public.alert_events(alert_id,kind,note)
  VALUES(_alert_id,'raised','passive_checkin_consecutive_misses');
  INSERT INTO private.passive_alert_causal_windows(alert_id,window_id,ordinal)
  SELECT _alert_id,id,(row_number() OVER(ORDER BY ordinal)-1)::integer
  FROM (SELECT id,ordinal FROM public.passive_checkin_windows
    WHERE epoch_id=_epoch_id AND outcome='missed'
    ORDER BY ordinal DESC LIMIT _contract.consecutive_misses) causal
  ORDER BY ordinal;
  RETURN _alert_id;
END;
$$;

CREATE FUNCTION private.process_passive_checkin_subject(_user_id uuid, _now timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' SET TimeZone TO 'UTC' AS $$
DECLARE
  _account public.passive_checkin_accounts%ROWTYPE;
  _contract public.passive_checkin_contract_versions%ROWTYPE;
  _epoch public.passive_monitoring_epochs%ROWTYPE;
  _current_ordinal bigint;
  _last_ordinal bigint;
  _start timestamptz;
  _finish timestamptz;
  _deadline timestamptz;
  _window record;
  _chain bigint;
  _alert_id uuid;
BEGIN
  IF _now IS NULL THEN RAISE EXCEPTION 'evaluation time is required'; END IF;
  SELECT * INTO _account FROM public.passive_checkin_accounts
  WHERE user_id=_user_id FOR UPDATE;
  IF NOT FOUND OR _account.engine_mode NOT IN ('shadow','passive_checkin')
     OR _account.active_epoch_id IS NULL THEN
    RETURN jsonb_build_object('status','inactive');
  END IF;
  SELECT * INTO STRICT _contract FROM public.passive_checkin_contract_versions
  WHERE id=_account.active_contract_version_id AND user_id=_user_id;
  SELECT * INTO STRICT _epoch FROM public.passive_monitoring_epochs
  WHERE id=_account.active_epoch_id AND user_id=_user_id AND ended_at IS NULL;

  _current_ordinal := greatest(0,floor(extract(epoch FROM (_now-_epoch.started_at))/60/_contract.interval_minutes)::bigint);
  SELECT coalesce(max(ordinal),-1) INTO _last_ordinal
  FROM public.passive_checkin_windows WHERE epoch_id=_epoch.id;
  WHILE _last_ordinal < _current_ordinal LOOP
    _last_ordinal := _last_ordinal+1;
    _start := _epoch.started_at+make_interval(mins=>(_last_ordinal*_contract.interval_minutes)::integer);
    _finish := _start+make_interval(mins=>_contract.interval_minutes);
    _deadline := _finish+private.passive_window_arrival_allowance(_user_id,_start,_finish);
    INSERT INTO public.passive_checkin_windows(
      user_id,epoch_id,contract_version_id,ordinal,window_start,window_end,arrival_deadline
    ) VALUES (_user_id,_epoch.id,_contract.id,_last_ordinal,_start,_finish,_deadline)
    ON CONFLICT(epoch_id,ordinal) DO NOTHING;
  END LOOP;

  FOR _window IN
    SELECT * FROM public.passive_checkin_windows
    WHERE epoch_id=_epoch.id AND outcome='pending' ORDER BY ordinal FOR UPDATE
  LOOP
    _deadline := _window.window_end+private.passive_window_arrival_allowance(
      _user_id,_window.window_start,_window.window_end
    );
    UPDATE public.passive_checkin_windows SET arrival_deadline=_deadline WHERE id=_window.id;
    CONTINUE WHEN _deadline>_now;
    IF EXISTS (
      SELECT 1 FROM private.passive_evidence_events AS event
      WHERE event.window_id=_window.id
        AND event.observed_at>=_window.window_start AND event.observed_at<_window.window_end
    ) THEN
      UPDATE public.passive_checkin_windows
      SET outcome='checked_in',finalized_at=_now,
          causal_evidence_id=(SELECT id FROM private.passive_evidence_events WHERE window_id=_window.id ORDER BY observed_at,id LIMIT 1)
      WHERE id=_window.id AND outcome='pending';
    ELSE
      UPDATE public.passive_checkin_windows
      SET outcome='missed',finalized_at=_now
      WHERE id=_window.id AND outcome='pending';
      _alert_id:=coalesce(
        _alert_id,
        private.maybe_open_passive_checkin_alert(_user_id,_epoch.id,_contract.id,_now)
      );
    END IF;
  END LOOP;

  SELECT count(*) INTO _chain
  FROM public.passive_checkin_windows AS candidate
  WHERE candidate.epoch_id=_epoch.id AND candidate.outcome='missed'
    AND NOT EXISTS (
      SELECT 1 FROM public.passive_checkin_windows AS later
      WHERE later.epoch_id=_epoch.id AND later.ordinal>candidate.ordinal
        AND later.outcome IN ('checked_in','superseded')
    );

  IF _account.engine_mode='passive_checkin' AND NOT _account.kill_switch_active
     AND _chain>=_contract.consecutive_misses THEN
    _alert_id:=private.maybe_open_passive_checkin_alert(_user_id,_epoch.id,_contract.id,_now);
  END IF;
  RETURN jsonb_build_object('status','processed','consecutive_misses',_chain,'alert_id',_alert_id);
END;
$$;

CREATE FUNCTION public.process_passive_checkins()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _subject record;
BEGIN
  FOR _subject IN
    SELECT user_id FROM public.passive_checkin_accounts
    WHERE engine_mode IN ('shadow','passive_checkin') AND active_epoch_id IS NOT NULL
  LOOP
    BEGIN
      PERFORM private.process_passive_checkin_subject(_subject.user_id,clock_timestamp());
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO private.job_failures(job_name,subject_id,sqlstate,message)
      VALUES('process_passive_checkins',_subject.user_id,SQLSTATE,SQLERRM);
    END;
  END LOOP;
END;
$$;

CREATE FUNCTION public.my_passive_window_state()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _uid uuid:=auth.uid(); _account public.passive_checkin_accounts%ROWTYPE;
  _contract public.passive_checkin_contract_versions%ROWTYPE; _window record;
  _chain bigint:=0; _alert record;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='28000'; END IF;
  SELECT * INTO _account FROM public.passive_checkin_accounts WHERE user_id=_uid;
  IF NOT FOUND THEN RETURN jsonb_build_object('engine_mode','legacy','consecutive_misses',0,
    'current_window',NULL,'open_alert',NULL,'sleep_deferred',false); END IF;
  SELECT * INTO _contract FROM public.passive_checkin_contract_versions WHERE id=_account.active_contract_version_id;
  SELECT * INTO _window FROM public.passive_checkin_windows WHERE epoch_id=_account.active_epoch_id
  ORDER BY ordinal DESC LIMIT 1;
  SELECT count(*) INTO _chain FROM public.passive_checkin_windows candidate
  WHERE candidate.epoch_id=_account.active_epoch_id AND candidate.outcome='missed'
    AND NOT EXISTS(SELECT 1 FROM public.passive_checkin_windows later
      WHERE later.epoch_id=_account.active_epoch_id AND later.ordinal>candidate.ordinal
        AND later.outcome IN('checked_in','superseded'));
  SELECT a.id,a.stage,a.opened_at INTO _alert FROM public.alerts a
  WHERE a.user_id=_uid AND a.status='open'
    AND EXISTS(SELECT 1 FROM private.passive_alert_causal_windows c WHERE c.alert_id=a.id)
  LIMIT 1;
  RETURN jsonb_build_object(
    'engine_mode',_account.engine_mode,'consecutive_misses',_chain,
    'current_window',CASE WHEN _window.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id',_window.id,'ordinal',_window.ordinal,'window_start',_window.window_start,
      'window_end',_window.window_end,'arrival_deadline',_window.arrival_deadline,'outcome',_window.outcome) END,
    'open_alert',CASE WHEN _alert.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id',_alert.id,'stage',_alert.stage,'opened_at',_alert.opened_at) END,
    'sleep_deferred',_account.engine_mode='passive_checkin' AND _alert.id IS NULL
      AND _chain>=coalesce(_contract.consecutive_misses,2147483647)
      AND private.passive_sleep_relaxed(_uid,_account.active_contract_version_id,clock_timestamp())
  );
END;
$$;

CREATE FUNCTION private.restart_passive_epoch_after_resolution()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE
  _account public.passive_checkin_accounts%ROWTYPE;
  _at timestamptz;
  _epoch_id uuid;
  _contract public.passive_checkin_contract_versions%ROWTYPE;
  _finish timestamptz;
BEGIN
  IF OLD.status<>'open' OR NEW.status<>'resolved' OR NEW.resolved_by IS NULL
     OR NOT EXISTS(SELECT 1 FROM private.passive_alert_causal_windows WHERE alert_id=NEW.id) THEN
    RETURN NEW;
  END IF;
  _at:=coalesce(NEW.resolved_at,clock_timestamp());
  SELECT * INTO _account FROM public.passive_checkin_accounts WHERE user_id=NEW.user_id FOR UPDATE;
  IF NOT FOUND OR _account.active_contract_version_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO STRICT _contract FROM public.passive_checkin_contract_versions
  WHERE id=_account.active_contract_version_id;
  UPDATE public.passive_checkin_windows SET outcome='superseded',finalized_at=_at,
    superseded_reason='explicit_resolution'
  WHERE user_id=NEW.user_id AND outcome='pending';
  UPDATE public.passive_monitoring_epochs SET ended_at=_at,end_reason='explicit_resolution'
  WHERE user_id=NEW.user_id AND ended_at IS NULL;
  INSERT INTO public.passive_monitoring_epochs(user_id,contract_version_id,started_at,start_reason)
  VALUES(NEW.user_id,_contract.id,_at,'explicit_resolution') RETURNING id INTO _epoch_id;
  _finish:=_at+make_interval(mins=>_contract.interval_minutes);
  INSERT INTO public.passive_checkin_windows(
    user_id,epoch_id,contract_version_id,ordinal,window_start,window_end,arrival_deadline
  ) VALUES(NEW.user_id,_epoch_id,_contract.id,0,_at,_finish,
    _finish+private.passive_window_arrival_allowance(NEW.user_id,_at,_finish));
  UPDATE public.passive_checkin_accounts SET active_epoch_id=_epoch_id,updated_at=_at
  WHERE user_id=NEW.user_id;
  RETURN NEW;
END;
$$;
CREATE TRIGGER alerts_restart_passive_epoch_after_resolution
AFTER UPDATE OF status ON public.alerts FOR EACH ROW
EXECUTE FUNCTION private.restart_passive_epoch_after_resolution();

-- Route passive escalation copy without changing SOS or legacy wording.
ALTER FUNCTION private.notify_stage(uuid,uuid,text) RENAME TO notify_stage_before_passive_checkin;
CREATE FUNCTION private.notify_stage(_alert_id uuid,_user uuid,_stage text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _name text; _params jsonb;
BEGIN
  IF NOT EXISTS(SELECT 1 FROM private.passive_alert_causal_windows WHERE alert_id=_alert_id) THEN
    PERFORM private.notify_stage_before_passive_checkin(_alert_id,_user,_stage);
    RETURN;
  END IF;
  IF _stage='self' THEN RETURN; END IF;
  SELECT coalesce(display_name,'') INTO _name FROM public.profiles WHERE id=_user;
  _params:=jsonb_build_object('name',_name,'cause','passive_checkin_lost_contact');
  IF _stage='group' THEN
    INSERT INTO public.notifications(recipient_id,alert_id,kind,body,params)
    SELECT DISTINCT recipient,_alert_id,'group',_name||' 与 KC 失去联系，请尝试联系本人确认。',_params
    FROM (
      SELECT watcher.user_id AS recipient FROM public.group_members subject
      JOIN public.group_members watcher ON watcher.group_id=subject.group_id
      WHERE subject.user_id=_user AND subject.monitored AND subject.status='active'
        AND watcher.watching AND watcher.status='active' AND watcher.user_id<>_user
      UNION SELECT guardian_id FROM public.guardianships
      WHERE ward_id=_user AND status='active'
    ) recipients;
  ELSIF _stage='community' THEN
    INSERT INTO public.notifications(recipient_id,alert_id,kind,body,params)
    SELECT DISTINCT member.user_id,_alert_id,'community',
      'KC 与 '||_name||' 持续失去联系且小组尚未响应，请协助联系。',_params
    FROM public.community_members subject
    JOIN public.community_members member ON member.community_id=subject.community_id
    WHERE subject.user_id=_user AND subject.status='active'
      AND member.status='active' AND member.user_id<>_user;
  ELSIF _stage='terminal' THEN
    INSERT INTO public.notifications(recipient_id,alert_id,kind,body,params)
    SELECT DISTINCT recipient,_alert_id,'terminal',
      'KC 与 '||_name||' 持续失去联系，请上门探视或协助联系。',_params
    FROM (
      SELECT watcher.user_id AS recipient FROM public.group_members subject
      JOIN public.group_members watcher ON watcher.group_id=subject.group_id
      WHERE subject.user_id=_user AND subject.monitored AND subject.status='active'
        AND watcher.watching AND watcher.status='active' AND watcher.user_id<>_user
      UNION SELECT guardian_id FROM public.guardianships
      WHERE ward_id=_user AND status='active'
    ) recipients;
  END IF;
END;
$$;

-- Existing escalation funnel remains authoritative for stage progression, but
-- its inactivity creator cannot run for live passive accounts and its sleep
-- auto-resolution cannot answer a passive alert.
CREATE OR REPLACE FUNCTION public.process_escalations()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE
  _self_grace CONSTANT interval:=interval '30 minutes';
  _group_dur CONSTANT interval:=interval '1 hour';
  _comm_dur CONSTANT interval:=interval '2 hours';
  r record; _aid uuid; _new text; _triggered boolean:=false;
BEGIN
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
    WHERE a.status='open' AND a.cause='silence' AND private.sleep_relaxed(a.user_id,now())
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
    _new:=CASE r.stage WHEN 'self' THEN 'group' WHEN 'group' THEN 'community'
      WHEN 'community' THEN 'terminal' ELSE 'terminal' END;
    UPDATE public.alerts SET stage=_new,stage_entered_at=now(),paused_until=NULL,paused_by=NULL,
      updated_at=now(),next_deadline=CASE _new WHEN 'group' THEN now()+_group_dur
        WHEN 'community' THEN now()+_comm_dur ELSE NULL END WHERE id=r.id;
    INSERT INTO public.alert_events(alert_id,kind,note) VALUES(r.id,'escalated',_new);
    PERFORM private.notify_stage(r.id,r.user_id,_new); _triggered:=true;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO private.job_failures(job_name,subject_id,sqlstate,message)
    VALUES('process_escalations',r.user_id,SQLSTATE,SQLERRM);
  END; END LOOP;
  IF _triggered THEN PERFORM private.trigger_push_dispatch(); END IF;
END;
$$;

REVOKE ALL ON FUNCTION private.capture_passive_window_transition() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.reject_passive_snapshot_mutation() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.passive_window_arrival_allowance(uuid,timestamptz,timestamptz) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.passive_sleep_relaxed(uuid,uuid,timestamptz) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.maybe_open_passive_checkin_alert(uuid,uuid,uuid,timestamptz) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.process_passive_checkin_subject(uuid,timestamptz) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.restart_passive_epoch_after_resolution() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.process_passive_checkins() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.process_passive_checkins() TO service_role;
REVOKE ALL ON FUNCTION public.my_passive_window_state() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.my_passive_window_state() TO authenticated;
REVOKE ALL ON FUNCTION private.notify_stage(uuid,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.notify_stage(uuid,uuid,text) TO service_role;

COMMENT ON FUNCTION private.process_passive_checkin_subject(uuid,timestamptz) IS
  'ADR-0042 deterministic per-subject evaluator. Reads evidence and contract, never collector health.';
