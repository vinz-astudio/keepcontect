-- device_unreachable alerts never reach terminal (plan A, human decision 2026-11-02).
--
-- A silence whose causal window was classified device_unreachable means KC lost the
-- device (powered off, flat, unplugged), not that the person stopped moving. ADR-0040
-- rev.1 forbids judging device_off as a missing person; ADR-0039 rev.1 lets it reach
-- group / community only, worded as "KC lost contact". In the 30 days before this,
-- every cause=silence alert in production was device_unreachable and 6 of 31 reached
-- terminal, telling real emergency contacts that the subject's address had been unlocked.
--
-- Change: process_escalations() holds such an alert at its current stage instead of
-- promoting it to terminal, and clears next_deadline so it stops being re-evaluated.
-- The emergency_info_select policy only reveals data at stage='terminal' (or cause='sos'),
-- so holding the stage is what keeps the profile locked. Everything else is unchanged:
-- silent, collection_restricted, legacy alerts without causal windows, and SOS.
-- The alert still closes normally on recovered activity or acknowledgement.
--
-- Not done here (awaiting human decision): alerts already at terminal in production,
-- and whether collection_restricted should be capped too.
--
-- Body copied from 20260923054905_activity_auto_resolution_guardian_pattern.sql (the
-- latest definition); CREATE OR REPLACE keeps the existing owner and EXECUTE grants.

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
    IF _new='terminal' AND _kind IS NOT DISTINCT FROM 'device_unreachable' THEN
      -- A dead or unplugged device is not a missing person: hold at the current stage,
      -- stop the clock, send nothing, and never unlock address or emergency contacts.
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
