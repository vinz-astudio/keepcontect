-- ADR-0045 (human direction 2026-09-23): qualified own activity normally
-- answers automatic alerts. An active designated guardian may opt into pattern.
-- No old migrations, evidence, alert history or relationship permissions change.

CREATE TABLE private.guardian_pattern_requirements (
  guardianship_id uuid PRIMARY KEY REFERENCES public.guardianships(id) ON DELETE CASCADE,
  require_pattern boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE private.guardian_pattern_requirements ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.guardian_pattern_requirements FROM PUBLIC, anon, authenticated;

CREATE FUNCTION private.guardian_requires_pattern(_user uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM private.guardian_pattern_requirements p
    JOIN public.guardianships g ON g.id=p.guardianship_id
    WHERE g.ward_id=_user AND g.status='active' AND p.require_pattern
  );
$$;
REVOKE ALL ON FUNCTION private.guardian_requires_pattern(uuid) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.my_guardian_pattern_requirements()
RETURNS TABLE(guardianship_id uuid,require_pattern boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
  SELECT g.id,coalesce(p.require_pattern,false) AND g.status='active'
  FROM public.guardianships g
  LEFT JOIN private.guardian_pattern_requirements p ON p.guardianship_id=g.id
  WHERE auth.uid() IN (g.guardian_id,g.ward_id);
$$;
REVOKE ALL ON FUNCTION public.my_guardian_pattern_requirements() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.my_guardian_pattern_requirements() TO authenticated;

CREATE FUNCTION public.set_guardian_pattern_requirement(_guardianship_id uuid,_required boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _ward uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='28000'; END IF;
  SELECT ward_id INTO _ward FROM public.guardianships
  WHERE id=_guardianship_id AND guardian_id=auth.uid() AND status='active';
  IF _ward IS NULL THEN RAISE EXCEPTION 'active guardian required' USING ERRCODE='42501'; END IF;
  IF _required IS NULL THEN RAISE EXCEPTION 'required flag is missing'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('kc:alert-policy:'||_ward::text,0));
  PERFORM 1 FROM public.guardianships WHERE id=_guardianship_id
    AND guardian_id=auth.uid() AND status='active' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'active guardian required' USING ERRCODE='42501'; END IF;
  IF _required AND NOT EXISTS(SELECT 1 FROM public.user_settings
    WHERE user_id=_ward AND pattern_hash ~ '^[0-9a-f]{64}$') THEN
    RAISE EXCEPTION 'ward_pattern_not_set';
  END IF;
  INSERT INTO private.guardian_pattern_requirements(guardianship_id,require_pattern)
  VALUES(_guardianship_id,_required)
  ON CONFLICT(guardianship_id) DO UPDATE SET require_pattern=excluded.require_pattern,updated_at=clock_timestamp();
  UPDATE public.alerts SET requires_explicit_unlock=private.guardian_requires_pattern(_ward),updated_at=clock_timestamp()
  WHERE user_id=_ward AND status='open';
END;
$$;
REVOKE ALL ON FUNCTION public.set_guardian_pattern_requirement(uuid,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_guardian_pattern_requirement(uuid,boolean) TO authenticated;

CREATE FUNCTION private.set_alert_pattern_policy() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
  NEW.requires_explicit_unlock := private.guardian_requires_pattern(NEW.user_id);
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.set_alert_pattern_policy() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER alert_pattern_policy BEFORE INSERT OR UPDATE ON public.alerts
FOR EACH ROW EXECUTE FUNCTION private.set_alert_pattern_policy();

CREATE FUNCTION private.refresh_revoked_guardian_pattern() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
  UPDATE public.alerts SET requires_explicit_unlock=private.guardian_requires_pattern(OLD.ward_id),updated_at=clock_timestamp()
  WHERE user_id=OLD.ward_id AND status='open';
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION private.refresh_revoked_guardian_pattern() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER guardian_pattern_revoked AFTER DELETE OR UPDATE OF status ON public.guardianships
FOR EACH ROW EXECUTE FUNCTION private.refresh_revoked_guardian_pattern();
COMMENT ON COLUMN public.alerts.requires_explicit_unlock IS
  'ADR-0045: pattern requirement derives only from active guardian policy. SOS still requires an explicit confirmation, but not a default pattern.';

CREATE FUNCTION private.resolve_activity_alerts(_user uuid) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE r record; _count integer:=0; _name text;
BEGIN
  IF _user IS NULL OR (auth.uid() IS NOT NULL AND auth.uid()<>_user) THEN RETURN 0; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('kc:alert-policy:'||_user::text,0));
  -- The passive evaluator takes the account before touching alerts.
  PERFORM 1 FROM public.passive_checkin_accounts WHERE user_id=_user FOR UPDATE;
  IF private.guardian_requires_pattern(_user) THEN RETURN 0; END IF;
  FOR r IN SELECT a.id FROM public.alerts a
    WHERE a.user_id=_user AND a.status='open' AND a.cause IN('silence','dark_device','concern')
      AND EXISTS(SELECT 1 FROM public.behavior_pings b
        WHERE b.user_id=a.user_id AND b.ingest_version=2
          AND b.kind IN('app','interaction','steps','unlock','manual_checkin')
          AND b.source IN('installed_pwa','tauri','capacitor','shortcut','manual','app')
          AND b.at>=a.opened_at AND b.received_at>=a.opened_at
          AND b.at<=b.received_at AND b.received_at<=clock_timestamp()
          AND b.received_at-b.at<=interval '5 minutes')
    FOR UPDATE OF a
  LOOP
    UPDATE public.alerts SET status='resolved',resolved_at=clock_timestamp(),resolved_by=NULL,
      next_deadline=NULL,paused_until=NULL,paused_by=NULL,updated_at=clock_timestamp()
    WHERE id=r.id AND status='open';
    IF NOT FOUND THEN CONTINUE; END IF;
    INSERT INTO public.alert_events(alert_id,kind,note) VALUES(r.id,'auto_resolved','qualified_subject_activity');
    -- Withdraw unsent escalation notices and stale self prompts, preserve history.
    UPDATE public.notifications SET read_at=coalesce(read_at,clock_timestamp()),
      delivery_outcome=CASE WHEN pushed_at IS NULL THEN 'no_target' ELSE delivery_outcome END,
      pushed_at=coalesce(pushed_at,clock_timestamp()),delivery_lease_expiry=NULL
    WHERE alert_id=r.id AND kind IN('self','concern','group','community','terminal');
    SELECT coalesce(display_name,'') INTO _name FROM public.profiles WHERE id=_user;
    INSERT INTO public.notifications(recipient_id,alert_id,kind,body,params)
    SELECT recipient,r.id,'auto_resolved',coalesce(nullif(_name,''),'成员')||' 的告警已自动解除（检测到本人活动）。',
      jsonb_build_object('target',_name,'reason','qualified_subject_activity')
    FROM (SELECT _user AS recipient UNION SELECT recipient_id FROM public.notifications
      WHERE alert_id=r.id AND kind IN('group','community','terminal','concern')) recipients;
    _count:=_count+1;
  END LOOP;
  IF _count>0 THEN PERFORM private.trigger_push_dispatch(); END IF;
  RETURN _count;
END;
$$;
REVOKE ALL ON FUNCTION private.resolve_activity_alerts(uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION private.apply_liveness_side_effects(
  _user_id uuid,_observed_at timestamptz,_received_at timestamptz
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid()<>_user_id THEN RETURN; END IF;
  -- Match explicit confirmation: policy -> passive account -> device -> alert.
  -- Taking device_state first would deadlock with confirmation's manual ping.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('kc:alert-policy:'||_user_id::text,0));
  PERFORM 1 FROM public.passive_checkin_accounts WHERE user_id=_user_id FOR UPDATE;
  INSERT INTO public.device_state(user_id,status,last_heartbeat_at,updated_at)
  VALUES(_user_id,'normal',_received_at,now())
  ON CONFLICT(user_id) DO UPDATE SET status='normal',
    last_heartbeat_at=greatest(device_state.last_heartbeat_at,excluded.last_heartbeat_at),updated_at=now();
  -- Read canonical rows, never trust this helper's arguments as standalone evidence.
  PERFORM private.resolve_activity_alerts(_user_id);
  IF NOT EXISTS(SELECT 1 FROM public.alerts WHERE user_id=_user_id AND status='open') THEN
    UPDATE public.notifications SET read_at=coalesce(read_at,clock_timestamp())
    WHERE recipient_id=_user_id AND kind IN('self','concern');
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION private.apply_liveness_side_effects(uuid,timestamptz,timestamptz) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION private.confirm_subject_safety(_alert_id uuid,_pattern integer[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _uid uuid:=auth.uid(); _alert public.alerts%ROWTYPE; _hash text; _result text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='28000'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('kc:alert-policy:'||_uid::text,0));
  PERFORM 1 FROM public.passive_checkin_accounts WHERE user_id=_uid FOR UPDATE;
  SELECT * INTO _alert FROM public.alerts WHERE user_id=_uid
    AND ((_alert_id IS NOT NULL AND id=_alert_id) OR (_alert_id IS NULL AND status='open'))
    ORDER BY opened_at DESC LIMIT 1 FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',_alert_id IS NULL,'cleared_alert',false,
      'already_resolved',_alert_id IS NULL,'reason','alert_not_found');
  END IF;
  IF _alert.status<>'open' THEN
    RETURN jsonb_build_object('ok',true,'cleared_alert',false,'already_resolved',true);
  END IF;
  IF private.guardian_requires_pattern(_uid) THEN
    IF _pattern IS NULL THEN RAISE EXCEPTION 'pattern_required' USING ERRCODE='42501'; END IF;
    SELECT pattern_hash INTO _hash FROM public.user_settings WHERE user_id=_uid;
    IF _hash IS NULL OR cardinality(_pattern)<4 OR cardinality(_pattern)>9
      OR EXISTS(SELECT 1 FROM unnest(_pattern) n WHERE n IS NULL OR n<0 OR n>8)
      OR (SELECT count(DISTINCT n) FROM unnest(_pattern) n)<>cardinality(_pattern)
      OR encode(sha256(convert_to('kc:'||array_to_string(_pattern,'-'),'UTF8')),'hex')<>_hash THEN
      RAISE EXCEPTION 'invalid_pattern' USING ERRCODE='42501';
    END IF;
  END IF;
  UPDATE public.alerts SET status='resolved',resolved_at=clock_timestamp(),resolved_by=_uid,
    next_deadline=NULL,paused_until=NULL,paused_by=NULL,updated_at=clock_timestamp() WHERE id=_alert.id;
  INSERT INTO public.alert_events(alert_id,actor_id,kind,note)
  VALUES(_alert.id,_uid,'resolved',CASE WHEN private.guardian_requires_pattern(_uid)
    THEN 'self_pattern_confirmed' ELSE 'self_acknowledged' END);
  UPDATE public.notifications SET read_at=coalesce(read_at,clock_timestamp()),
    delivery_outcome=CASE WHEN pushed_at IS NULL THEN 'no_target' ELSE delivery_outcome END,
    pushed_at=coalesce(pushed_at,clock_timestamp()),delivery_lease_expiry=NULL
  WHERE alert_id=_alert.id AND kind IN('self','concern','group','community','terminal');
  INSERT INTO public.notifications(recipient_id,alert_id,kind,body,params)
  SELECT recipient,_alert.id,'resolved',coalesce(nullif(p.display_name,''),'成员')||' 已确认安全，告警解除。',
    jsonb_build_object('target',coalesce(p.display_name,''))
  FROM (SELECT _uid AS recipient UNION SELECT recipient_id FROM public.notifications
    WHERE alert_id=_alert.id AND kind IN('group','community','terminal','concern')) recipients
  LEFT JOIN public.profiles p ON p.id=_uid;
  _result:=private.insert_behavior_ping(_uid,gen_random_uuid(),clock_timestamp(),'manual','manual_checkin');
  IF _result<>'inserted' THEN RAISE EXCEPTION 'manual_checkin_rejected: %',_result; END IF;
  PERFORM private.trigger_push_dispatch();
  RETURN jsonb_build_object('ok',true,'cleared_alert',true);
END;
$$;
REVOKE ALL ON FUNCTION private.confirm_subject_safety(uuid,integer[]) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.acknowledge_safe(_alert_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO '' AS $$
  SELECT private.confirm_subject_safety(_alert_id,NULL);
$$;
REVOKE ALL ON FUNCTION public.acknowledge_safe(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.acknowledge_safe(uuid) TO authenticated,service_role;

CREATE FUNCTION public.acknowledge_safe_with_pattern(_alert_id uuid,_pattern integer[])
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO '' AS $$
  SELECT private.confirm_subject_safety(_alert_id,_pattern);
$$;
REVOKE ALL ON FUNCTION public.acknowledge_safe_with_pattern(uuid,integer[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.acknowledge_safe_with_pattern(uuid,integer[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.resolve_my_alert() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
  PERFORM private.confirm_subject_safety(NULL,NULL);
END;
$$;
REVOKE ALL ON FUNCTION public.resolve_my_alert() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.resolve_my_alert() TO authenticated,service_role;

-- Old flags were unconditional. New values are derived from active opt-in policy.
UPDATE public.alerts SET requires_explicit_unlock=private.guardian_requires_pattern(user_id)
WHERE status='open';

-- A recovered passive alert must not immediately re-open from its old miss
-- chain. Keep the old evidence/windows and start a new epoch with honest origin.
ALTER TABLE public.passive_monitoring_epochs
  DROP CONSTRAINT passive_monitoring_epochs_start_reason_check;
ALTER TABLE public.passive_monitoring_epochs
  ADD CONSTRAINT passive_monitoring_epochs_start_reason_check CHECK (
    start_reason IN('contract_saved','explicit_resolution','manual_reset','rollback','activity_resolution')
  );
CREATE OR REPLACE FUNCTION private.restart_passive_epoch_after_resolution()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE
  _account public.passive_checkin_accounts%ROWTYPE;
  _contract public.passive_checkin_contract_versions%ROWTYPE;
  _at timestamptz; _epoch_id uuid; _finish timestamptz;
  _reason text:='explicit_resolution';
BEGIN
  IF OLD.status<>'open' OR NEW.status<>'resolved'
     OR NOT EXISTS(SELECT 1 FROM private.passive_alert_causal_windows WHERE alert_id=NEW.id) THEN
    RETURN NEW;
  END IF;
  _at:=coalesce(NEW.resolved_at,clock_timestamp());
  IF NEW.resolved_by IS NULL THEN
    IF NEW.cause='sos' OR private.guardian_requires_pattern(NEW.user_id) THEN RETURN NEW; END IF;
    SELECT max(b.at) INTO _at FROM public.behavior_pings b
    WHERE b.user_id=NEW.user_id AND b.ingest_version=2
      AND b.kind IN('app','interaction','steps','unlock','manual_checkin')
      AND b.source IN('installed_pwa','tauri','capacitor','shortcut','manual','app')
      AND b.at>=NEW.opened_at AND b.received_at>=NEW.opened_at
      AND b.at<=b.received_at AND b.received_at<=clock_timestamp()
      AND b.received_at-b.at<=interval '5 minutes';
    IF _at IS NULL THEN RETURN NEW; END IF;
    _reason:='activity_resolution';
  END IF;
  SELECT * INTO _account FROM public.passive_checkin_accounts WHERE user_id=NEW.user_id FOR UPDATE;
  IF NOT FOUND OR _account.active_contract_version_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO STRICT _contract FROM public.passive_checkin_contract_versions
  WHERE id=_account.active_contract_version_id;
  _at:=greatest(_at,(SELECT started_at FROM public.passive_monitoring_epochs WHERE id=_account.active_epoch_id));
  UPDATE public.passive_checkin_windows SET outcome='superseded',finalized_at=clock_timestamp(),superseded_reason=_reason
  WHERE user_id=NEW.user_id AND outcome='pending';
  UPDATE public.passive_monitoring_epochs SET ended_at=_at,end_reason=_reason
  WHERE user_id=NEW.user_id AND ended_at IS NULL;
  INSERT INTO public.passive_monitoring_epochs(user_id,contract_version_id,started_at,start_reason)
  VALUES(NEW.user_id,_contract.id,_at,_reason) RETURNING id INTO _epoch_id;
  _finish:=private.passive_awake_deadline(NEW.user_id,_at,_contract.interval_minutes);
  INSERT INTO public.passive_checkin_windows(
    user_id,epoch_id,contract_version_id,ordinal,window_start,window_end,arrival_deadline
  ) VALUES(NEW.user_id,_epoch_id,_contract.id,0,_at,_finish,
    _finish+private.passive_window_arrival_allowance(NEW.user_id,_at,_finish));
  UPDATE public.passive_checkin_accounts SET active_epoch_id=_epoch_id,updated_at=clock_timestamp()
  WHERE user_id=NEW.user_id;
  RETURN NEW;
END;
$$;


-- Recheck recovery before escalation; do not send from a stale loop record.
CREATE OR REPLACE FUNCTION public.process_escalations()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE
  _self_grace CONSTANT interval:=interval '30 minutes';
  _group_dur CONSTANT interval:=interval '1 hour';
  _comm_dur CONSTANT interval:=interval '2 hours';
  r record; _aid uuid; _new text; _triggered boolean:=false;
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

-- Plain notification taps open the confirmation screen; do not promise a
-- one-tap bypass for subjects whose guardian explicitly requires a pattern.
DO $$
DECLARE _fn record; _definition text;
BEGIN
  FOR _fn IN SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='private' AND p.proname IN('notify_stage','notify_stage_before_passive_checkin')
  LOOP
    _definition:=pg_get_functiondef(_fn.oid);
    IF strpos(_definition,'KC 正在确认您的安全。点开或轻按即完成确认，不会打扰亲友。')>0 THEN
      EXECUTE replace(_definition,'KC 正在确认您的安全。点开或轻按即完成确认，不会打扰亲友。',
        'KC 正在确认您的安全。请点“一切安好”，或打开应用按提示确认。');
    END IF;
  END LOOP;
END;
$$;
