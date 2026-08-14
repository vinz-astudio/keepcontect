-- ADR-0042 package 9: replayable shadow decisions, aggregate metrics, and kill switch.

CREATE TABLE private.passive_checkin_runtime_control(
  singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
  globally_disabled boolean NOT NULL DEFAULT false,
  reason text,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO private.passive_checkin_runtime_control(singleton) VALUES(true);

CREATE TABLE private.passive_shadow_candidates(
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  epoch_id uuid NOT NULL REFERENCES public.passive_monitoring_epochs(id) ON DELETE CASCADE,
  contract_version_id uuid NOT NULL REFERENCES public.passive_checkin_contract_versions(id) ON DELETE RESTRICT,
  terminal_ordinal bigint NOT NULL CHECK(terminal_ordinal>=0),
  decision text NOT NULL CHECK(decision IN('would_open','duplicate_suppressed','sleep_deferred')),
  causal_window_ids uuid[] NOT NULL CHECK(cardinality(causal_window_ids)>0),
  evaluated_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(epoch_id,terminal_ordinal)
);

ALTER TABLE private.passive_checkin_runtime_control ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.passive_shadow_candidates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.passive_checkin_runtime_control FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON TABLE private.passive_shadow_candidates FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.capture_passive_shadow_candidate()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE
  _account public.passive_checkin_accounts%ROWTYPE;
  _contract public.passive_checkin_contract_versions%ROWTYPE;
  _last_reset bigint:=-1; _chain bigint; _ids uuid[]; _decision text;
BEGIN
  IF OLD.outcome=NEW.outcome OR NEW.outcome<>'missed' THEN RETURN NEW; END IF;
  SELECT * INTO _account FROM public.passive_checkin_accounts WHERE user_id=NEW.user_id;
  IF NOT FOUND OR _account.engine_mode<>'shadow' THEN RETURN NEW; END IF;
  SELECT * INTO STRICT _contract FROM public.passive_checkin_contract_versions WHERE id=NEW.contract_version_id;
  SELECT coalesce(max(ordinal),-1) INTO _last_reset FROM public.passive_checkin_windows
  WHERE epoch_id=NEW.epoch_id AND ordinal<NEW.ordinal AND outcome IN('checked_in','superseded');
  SELECT count(*),array_agg(id ORDER BY ordinal) INTO _chain,_ids FROM (
    SELECT id,ordinal FROM public.passive_checkin_windows
    WHERE epoch_id=NEW.epoch_id AND ordinal>_last_reset AND ordinal<=NEW.ordinal AND outcome='missed'
    ORDER BY ordinal DESC LIMIT _contract.consecutive_misses
  ) causal;
  IF _chain<_contract.consecutive_misses THEN RETURN NEW; END IF;
  _decision:=CASE
    WHEN private.passive_sleep_relaxed(NEW.user_id,NEW.contract_version_id,coalesce(NEW.finalized_at,clock_timestamp())) THEN 'sleep_deferred'
    WHEN EXISTS(SELECT 1 FROM private.passive_shadow_candidates prior
      WHERE prior.epoch_id=NEW.epoch_id AND prior.terminal_ordinal>_last_reset AND prior.decision='would_open') THEN 'duplicate_suppressed'
    ELSE 'would_open' END;
  INSERT INTO private.passive_shadow_candidates(
    user_id,epoch_id,contract_version_id,terminal_ordinal,decision,causal_window_ids,evaluated_at
  ) VALUES(NEW.user_id,NEW.epoch_id,NEW.contract_version_id,NEW.ordinal,_decision,_ids,
    coalesce(NEW.finalized_at,clock_timestamp())) ON CONFLICT(epoch_id,terminal_ordinal) DO NOTHING;
  RETURN NEW;
END;
$$;
CREATE TRIGGER passive_windows_capture_shadow_candidate
AFTER UPDATE OF outcome ON public.passive_checkin_windows
FOR EACH ROW EXECUTE FUNCTION private.capture_passive_shadow_candidate();

CREATE FUNCTION private.reject_passive_observability_mutation()
RETURNS trigger LANGUAGE plpgsql SET search_path TO '' AS $$
BEGIN RAISE EXCEPTION 'passive observability records are immutable' USING ERRCODE='55000'; END $$;
CREATE TRIGGER passive_shadow_candidates_immutable BEFORE UPDATE ON private.passive_shadow_candidates
FOR EACH ROW EXECUTE FUNCTION private.reject_passive_observability_mutation();

CREATE FUNCTION private.set_passive_checkin_global_kill_switch(_active boolean,_reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
  IF _active IS NULL OR (_active AND (_reason IS NULL OR length(btrim(_reason))=0)) THEN
    RAISE EXCEPTION 'active kill switch requires a reason' USING ERRCODE='22023';
  END IF;
  UPDATE private.passive_checkin_runtime_control
  SET globally_disabled=_active,reason=CASE WHEN _active THEN btrim(_reason) END,updated_at=clock_timestamp()
  WHERE singleton;
  UPDATE public.passive_checkin_accounts SET kill_switch_active=_active,updated_at=clock_timestamp()
  WHERE engine_mode IN('shadow','passive_checkin');
END;
$$;

CREATE FUNCTION private.enforce_passive_global_kill_switch()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _disabled boolean;
BEGIN
  SELECT globally_disabled INTO _disabled FROM private.passive_checkin_runtime_control WHERE singleton;
  IF _disabled AND NEW.engine_mode IN('shadow','passive_checkin') THEN
    NEW.kill_switch_active:=true;
    IF NEW.engine_mode='passive_checkin'
      AND (TG_OP='INSERT' OR OLD.engine_mode IS DISTINCT FROM 'passive_checkin') THEN
      RAISE EXCEPTION 'global passive safety switch is active' USING ERRCODE='55000';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER passive_accounts_enforce_global_kill_switch
BEFORE INSERT OR UPDATE ON public.passive_checkin_accounts
FOR EACH ROW EXECUTE FUNCTION private.enforce_passive_global_kill_switch();

CREATE OR REPLACE FUNCTION public.my_passive_collector_health()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _uid uuid:=auth.uid(); _summary jsonb; _control private.passive_checkin_runtime_control%ROWTYPE;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='28000'; END IF;
  _summary:=private.passive_collector_health_summary(_uid,clock_timestamp());
  SELECT * INTO _control FROM private.passive_checkin_runtime_control WHERE singleton;
  IF _control.globally_disabled AND EXISTS(SELECT 1 FROM public.passive_checkin_accounts WHERE user_id=_uid AND engine_mode IN('shadow','passive_checkin')) THEN
    _summary:=_summary||jsonb_build_object('state','limited','global_reason',_control.reason,
      'global_repair_action','Wait for Keep Contact service recovery; completed windows are unchanged.');
  END IF;
  RETURN _summary;
END;
$$;

CREATE FUNCTION private.passive_checkin_shadow_report(_since timestamptz,_until timestamptz)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _cohorts jsonb; _invariants jsonb; _days numeric;
BEGIN
  IF _since IS NULL OR _until IS NULL OR _until<=_since THEN
    RAISE EXCEPTION 'invalid report interval' USING ERRCODE='22023';
  END IF;
  SELECT coalesce(min(extract(epoch FROM(_until-greatest(_since,e.started_at)))/86400),0)
  INTO _days FROM public.passive_checkin_accounts a
  JOIN public.passive_monitoring_epochs e ON e.id=a.active_epoch_id
  WHERE a.engine_mode='shadow' AND e.started_at<_until;
  WITH subject_cohort AS (
    SELECT a.user_id,c.client_contract_version,c.interval_minutes,c.consecutive_misses,
      coalesce(string_agg(DISTINCT b.surface_type,'+' ORDER BY b.surface_type),'none') platform_mix,
      coalesce(string_agg(DISTINCT b.client_version,'+' ORDER BY b.client_version),'none') client_versions
    FROM public.passive_checkin_accounts a
    JOIN public.passive_checkin_contract_versions c ON c.id=a.active_contract_version_id
    LEFT JOIN private.passive_collector_bindings b ON b.user_id=a.user_id AND b.revoked_at IS NULL
    WHERE a.engine_mode='shadow'
    GROUP BY a.user_id,c.client_contract_version,c.interval_minutes,c.consecutive_misses
  ), subject_rates AS (
    SELECT s.*,(count(candidate.id)::numeric/_days) interruption_rate
    FROM subject_cohort s LEFT JOIN private.passive_shadow_candidates candidate
      ON candidate.user_id=s.user_id AND candidate.decision='would_open'
      AND candidate.evaluated_at>=_since AND candidate.evaluated_at<_until
    GROUP BY s.user_id,s.client_contract_version,s.interval_minutes,s.consecutive_misses,s.platform_mix,s.client_versions
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'platform_mix',platform_mix,'client_versions',client_versions,'client_contract_version',client_contract_version,
    'interval_minutes',interval_minutes,'consecutive_misses',consecutive_misses,
    'subjects',subjects,'median_interruptions_per_user_day',median_rate,
    'p90_interruptions_per_user_day',p90_rate
  ) ORDER BY platform_mix,client_versions,client_contract_version,interval_minutes,consecutive_misses),'[]'::jsonb)
  INTO _cohorts FROM (
    SELECT platform_mix,client_versions,client_contract_version,interval_minutes,consecutive_misses,
      count(*)::integer subjects,
      percentile_cont(.5) WITHIN GROUP(ORDER BY interruption_rate) median_rate,
      percentile_cont(.9) WITHIN GROUP(ORDER BY interruption_rate) p90_rate
    FROM subject_rates GROUP BY platform_mix,client_versions,client_contract_version,interval_minutes,consecutive_misses
  ) grouped;

  SELECT jsonb_build_object(
    'late_absence_miss',(SELECT count(*) FROM private.passive_window_transitions t
      WHERE t.changed_at>=_since AND t.changed_at<_until AND t.reason='deadline_elapsed' AND t.causal_evidence_id IS NOT NULL),
    'passive_resolution',(SELECT count(*) FROM public.alerts a
      WHERE a.resolved_at>=_since AND a.resolved_at<_until AND a.status='resolved' AND a.resolved_by IS NULL
      AND EXISTS(SELECT 1 FROM private.passive_alert_causal_windows c WHERE c.alert_id=a.id)),
    'guardian_as_subject_evidence',(SELECT count(*) FROM private.passive_evidence_events e
      WHERE e.received_at>=_since AND e.received_at<_until AND e.correlation_id LIKE 'guardian:%'),
    'cross_account_acceptance',(SELECT count(*) FROM private.passive_evidence_events e
      JOIN private.passive_collector_bindings b ON b.id=e.binding_id
      JOIN public.passive_checkin_windows w ON w.id=e.window_id
      WHERE e.received_at>=_since AND e.received_at<_until AND (e.user_id<>b.user_id OR e.user_id<>w.user_id)),
    'dual_engine_alert',(
      SELECT count(*) FROM public.alerts passive_alert WHERE passive_alert.opened_at>=_since
      AND EXISTS(SELECT 1 FROM private.passive_alert_causal_windows pc WHERE pc.alert_id=passive_alert.id)
      AND EXISTS(SELECT 1 FROM public.alerts legacy_alert WHERE legacy_alert.user_id=passive_alert.user_id
        AND legacy_alert.id<>passive_alert.id AND legacy_alert.status='open'
        AND NOT EXISTS(SELECT 1 FROM private.passive_alert_causal_windows lc WHERE lc.alert_id=legacy_alert.id))
    ),
    'prohibited_raw_fields',(SELECT count(*) FROM private.passive_evidence_events e
      WHERE e.received_at>=_since AND e.received_at<_until AND e.qualification_facts ?| ARRAY[
      'app_name','package_name','url','key','content','location','coordinates','motion_raw','health_raw'])
  ) INTO _invariants
  ;

  RETURN jsonb_build_object(
    'schema_version','passive-shadow-report-v1','since',_since,'until',_until,'duration_days',_days,
    'window_counts',(SELECT coalesce(jsonb_object_agg(outcome,total),'{}'::jsonb) FROM (
      SELECT outcome,count(*)::integer total FROM public.passive_checkin_windows
      WHERE created_at>=_since AND created_at<_until GROUP BY outcome) q),
    'overdue_pending',(SELECT count(*) FROM public.passive_checkin_windows WHERE outcome='pending' AND arrival_deadline<_until),
    'arrival_gap_minutes',(SELECT jsonb_build_object(
      'p50',coalesce(percentile_cont(.5) WITHIN GROUP(ORDER BY extract(epoch FROM(received_at-observed_at))/60),0),
      'p90',coalesce(percentile_cont(.9) WITHIN GROUP(ORDER BY extract(epoch FROM(received_at-observed_at))/60),0))
      FROM private.passive_evidence_events WHERE received_at>=_since AND received_at<_until),
    'late_corrections',jsonb_build_object(
      'total',(SELECT count(*) FROM private.passive_window_transitions WHERE reason='late_positive' AND changed_at>=_since AND changed_at<_until),
      'causal_snapshot',(SELECT count(*) FROM private.passive_window_transitions t WHERE t.reason='late_positive'
        AND t.changed_at>=_since AND t.changed_at<_until AND EXISTS(
          SELECT 1 FROM private.passive_alert_causal_windows c WHERE c.window_id=t.window_id))),
    'ingest_incidents',(SELECT coalesce(jsonb_object_agg(reason,total),'{}'::jsonb) FROM (
      SELECT reason,count(*)::integer total FROM private.passive_evidence_incidents
      WHERE received_at>=_since AND received_at<_until GROUP BY reason) q),
    'chain_transitions',(SELECT count(*) FROM private.passive_window_transitions WHERE changed_at>=_since AND changed_at<_until),
    'passive_alert_opens',(SELECT count(DISTINCT c.alert_id) FROM private.passive_alert_causal_windows c JOIN public.alerts a ON a.id=c.alert_id WHERE a.opened_at>=_since AND a.opened_at<_until),
    'duplicate_suppressions',(SELECT count(*) FROM private.passive_shadow_candidates WHERE decision='duplicate_suppressed' AND evaluated_at>=_since AND evaluated_at<_until),
    'recommendation_changes',(SELECT count(*) FROM public.passive_checkin_recommendations WHERE revision_number>1 AND generated_at>=_since AND generated_at<_until),
    'job_failures',(SELECT count(*) FROM private.job_failures WHERE failed_at>=_since AND failed_at<_until AND job_name LIKE '%passive%'),
    'cohorts',_cohorts,'hard_invariants',_invariants,
    'global_kill_switch',(SELECT jsonb_build_object('active',globally_disabled,'reason',reason,'updated_at',updated_at) FROM private.passive_checkin_runtime_control WHERE singleton)
  );
END;
$$;

REVOKE ALL ON FUNCTION private.capture_passive_shadow_candidate() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.reject_passive_observability_mutation() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.enforce_passive_global_kill_switch() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.set_passive_checkin_global_kill_switch(boolean,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.passive_checkin_shadow_report(timestamptz,timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.set_passive_checkin_global_kill_switch(boolean,text) TO service_role;
GRANT EXECUTE ON FUNCTION private.passive_checkin_shadow_report(timestamptz,timestamptz) TO service_role;

COMMENT ON FUNCTION private.passive_checkin_shadow_report(timestamptz,timestamptz) IS
  'Aggregate-only ADR-0042 rollout report. No subject, device, event, window, alert or episode identifiers are returned.';
