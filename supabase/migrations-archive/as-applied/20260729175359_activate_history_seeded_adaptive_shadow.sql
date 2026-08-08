-- ADR-0028 Phase 2 + ADR-0029 P1 production activation.
-- Start shadow profiles from retained sessionized v1 history and extend them
-- with canonical-v2 evidence. Live alert authority remains unchanged.

CREATE FUNCTION private.dispatch_adaptive_alert_shadow_maintenance()
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET TimeZone = 'UTC'
AS $$
DECLARE
  _runtime private.adaptive_alert_shadow_runtime_config%ROWTYPE;
  _version public.alert_model_versions%ROWTYPE;
  _through_at timestamptz := clock_timestamp();
  _through_date date;
  _before_dml bigint := 0;
  _after_dml bigint := 0;
  _failure_code text;
  _failures integer;
BEGIN
  SELECT runtime.* INTO _runtime
  FROM private.adaptive_alert_shadow_runtime_config AS runtime
  WHERE runtime.singleton;

  IF _runtime.enabled IS NOT TRUE OR _runtime.version_id IS NULL THEN
    RETURN;
  END IF;

  PERFORM set_config('statement_timeout', '120s', true);
  PERFORM set_config('lock_timeout', '2s', true);
  _through_date := (_through_at AT TIME ZONE 'UTC')::date;

  BEGIN
    SELECT version.* INTO _version
    FROM public.alert_model_versions AS version
    WHERE version.id = _runtime.version_id;

    IF NOT FOUND
       OR _version.status <> 'shadow'
       OR _version.shadow_enabled_at IS NULL
       OR _version.evidence_version <> 'canonical-v2'
       OR _version.config_sha256 <> encode(
         extensions.digest(_version.config::text, 'sha256'), 'hex'
       ) THEN
      RAISE EXCEPTION 'shadow_version_validation_failed';
    END IF;

    IF _version.config #>> '{sessionization,historical_v1_policy}'
       <> 'sessionized_training_only_v1' THEN
      RAISE EXCEPTION 'shadow_history_policy_validation_failed';
    END IF;

    IF NOT private.shadow_live_definition_matches(
      _version.config #>> '{emergency,expected_live_definition_sha256}',
      pg_get_functiondef('private.silence_threshold(uuid)'::regprocedure)
    ) THEN
      RAISE EXCEPTION 'shadow_live_hash_mismatch';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_catalog.pg_class AS relation
      WHERE relation.oid IN (
        'public.alert_gap_profiles'::regclass,
        'public.routine_mode_cohort_priors'::regclass,
        'private.adaptive_alert_shadow_daily_reports'::regclass
      )
        AND NOT relation.relrowsecurity
    )
    OR has_table_privilege('authenticated','public.alert_gap_profiles','SELECT')
    OR EXISTS (
      SELECT 1
      FROM pg_catalog.pg_publication_tables AS publication
      WHERE publication.schemaname IN ('private', 'public')
        AND publication.tablename IN (
          'alert_gap_profiles',
          'routine_mode_cohort_priors',
          'adaptive_alert_shadow_daily_reports'
        )
    ) THEN
      RAISE EXCEPTION 'shadow_acl_validation_failed';
    END IF;

    SELECT coalesce(sum(stats.n_tup_ins + stats.n_tup_upd + stats.n_tup_del),0)
      INTO _before_dml
    FROM pg_catalog.pg_stat_xact_user_tables AS stats
    WHERE stats.relid IN (
      'public.alerts'::regclass,
      'public.alert_events'::regclass,
      'public.notifications'::regclass
    );

    PERFORM private.rebuild_alert_gap_profiles(_runtime.version_id,_through_date);
    PERFORM private.rebuild_routine_mode_cohort_priors(_runtime.version_id,_through_date,'regular_9to5');
    PERFORM private.rebuild_routine_mode_cohort_priors(_runtime.version_id,_through_date,'semester_break');
    PERFORM private.rebuild_routine_mode_cohort_priors(_runtime.version_id,_through_date,'shift_irregular');
    PERFORM private.maintain_adaptive_alert_shadow(_through_at,_runtime.max_population);

    SELECT coalesce(sum(stats.n_tup_ins + stats.n_tup_upd + stats.n_tup_del),0)
      INTO _after_dml
    FROM pg_catalog.pg_stat_xact_user_tables AS stats
    WHERE stats.relid IN (
      'public.alerts'::regclass,
      'public.alert_events'::regclass,
      'public.notifications'::regclass
    );

    IF _after_dml <> _before_dml THEN
      RAISE EXCEPTION 'shadow_live_write_detected';
    END IF;

    UPDATE private.adaptive_alert_shadow_runtime_config
    SET consecutive_failures = 0,
        last_failure_code = NULL,
        updated_at = clock_timestamp()
    WHERE singleton;
  EXCEPTION WHEN OTHERS THEN
    _failure_code := CASE
      WHEN SQLSTATE = '57014' THEN 'shadow_timeout'
      WHEN SQLERRM LIKE '%shadow_live_write_detected%' THEN 'shadow_live_write_detected'
      WHEN SQLERRM LIKE '%shadow_live_hash_mismatch%' THEN 'shadow_live_hash_mismatch'
      WHEN SQLERRM LIKE '%shadow_acl_validation_failed%' THEN 'shadow_acl_validation_failed'
      WHEN SQLERRM LIKE '%shadow_history_policy_validation_failed%' THEN 'shadow_malformed_result'
      WHEN SQLERRM LIKE '%shadow_version_validation_failed%' THEN 'shadow_malformed_result'
      ELSE 'ordinary_failure'
    END;

    IF _failure_code <> 'ordinary_failure' THEN
      PERFORM private.disable_adaptive_alert_shadow(_failure_code);
      RETURN;
    END IF;

    UPDATE private.adaptive_alert_shadow_runtime_config
    SET consecutive_failures = least(max_consecutive_failures,consecutive_failures + 1),
        last_failure_code = 'ordinary_failure',
        updated_at = clock_timestamp()
    WHERE singleton
    RETURNING consecutive_failures INTO _failures;

    IF _failures >= _runtime.max_consecutive_failures THEN
      PERFORM private.disable_adaptive_alert_shadow('ordinary_failure');
    END IF;
  END;
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.dispatch_adaptive_alert_shadow_maintenance()
FROM PUBLIC, anon, authenticated, service_role;

DO $activation$
DECLARE
  _config jsonb := '{
    "sessionization": {
      "gap_minutes": 30,
      "per_user_day_gap_cap": 8,
      "training_horizon_days": 30,
      "intervention_window_minutes": 30,
      "historical_v1_policy": "sessionized_training_only_v1"
    },
    "context": {
      "definition_version": "kc-shadow-prod-v1",
      "day_partition": "all_days",
      "hour_bucket_minutes": 60
    },
    "personal": {
      "min_samples": 20,
      "min_support_dates": 7,
      "min_span_days": 14,
      "max_age_days": 30,
      "min_confidence": 0.7,
      "confidence_formula_version": "support_ratio_v1"
    },
    "cohort": {
      "min_contributors": 5,
      "min_support_dates": 7,
      "min_span_days": 14,
      "max_age_days": 30,
      "min_confidence": 0.5,
      "contribution_floor_minutes": 30,
      "contribution_ceiling_minutes": 600,
      "confidence_formula_version": "cohort_support_min_v1",
      "algorithm": "weighted_median",
      "trim_fraction": 0
    },
    "sensitivity_buffers_minutes": {"high": 0,"balanced": 45,"low": 90},
    "candidate_bounds": {"floor_minutes": 90,"ceiling_minutes": 600},
    "sleep_compensation": {
      "max_start_delay_minutes": 45,
      "max_wake_advance_minutes": 45,
      "max_wake_delay_minutes": 90,
      "max_update_minutes_per_day": 30,
      "min_positive_nights": 3,
      "lookback_nights": 7,
      "min_late_events_per_night": 2,
      "timezone_tolerance_minutes": 0
    },
    "evaluator": {"contract_version": "adaptive_candidate_v1"},
    "emergency": {
      "contract_version": "adr0022_v1",
      "neutral_minutes": 90,
      "expected_live_definition_sha256": "1907d59473d274d46a0e8e0b9ce8027037b4494b0dddf073cb46abf67db92e21"
    }
  }'::jsonb;
  _version_id uuid;
  _old_version_id uuid;
  _activation_minute timestamptz;
  _job_id bigint;
  _cycle_result jsonb;
BEGIN
  _activation_minute := date_trunc('minute',clock_timestamp() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';

  IF NOT private.shadow_live_definition_matches(
    _config #>> '{emergency,expected_live_definition_sha256}',
    pg_get_functiondef('private.silence_threshold(uuid)'::regprocedure)
  ) THEN
    RAISE EXCEPTION 'shadow_live_hash_mismatch';
  END IF;

  SELECT runtime.version_id INTO _old_version_id
  FROM private.adaptive_alert_shadow_runtime_config AS runtime
  WHERE runtime.singleton;

  INSERT INTO public.alert_model_versions (
    name,status,config,config_sha256,evidence_version,shadow_enabled_at
  ) VALUES (
    'kc-shadow-prod-v2-history-seeded',
    'shadow',
    _config,
    encode(extensions.digest(_config::text,'sha256'),'hex'),
    'canonical-v2',
    _activation_minute
  ) RETURNING id INTO _version_id;

  UPDATE private.adaptive_alert_shadow_runtime_config
  SET version_id = _version_id,
      enabled = true,
      accept_coverage_leases = true,
      consecutive_failures = 0,
      last_failure_code = NULL,
      updated_at = clock_timestamp()
  WHERE singleton;

  UPDATE public.alert_model_versions
  SET status = 'retired'
  WHERE id = _old_version_id
    AND id <> _version_id
    AND status = 'shadow';

  PERFORM private.rebuild_alert_gap_profiles(
    _version_id,(_activation_minute AT TIME ZONE 'UTC')::date
  );
  PERFORM private.rebuild_routine_mode_cohort_priors(
    _version_id,(_activation_minute AT TIME ZONE 'UTC')::date,'regular_9to5'
  );
  PERFORM private.rebuild_routine_mode_cohort_priors(
    _version_id,(_activation_minute AT TIME ZONE 'UTC')::date,'semester_break'
  );
  PERFORM private.rebuild_routine_mode_cohort_priors(
    _version_id,(_activation_minute AT TIME ZONE 'UTC')::date,'shift_irregular'
  );

  _cycle_result := private.run_adaptive_alert_shadow_cycle(_version_id,_activation_minute);
  IF _cycle_result ->> 'status' <> 'completed' THEN
    RAISE EXCEPTION 'shadow_initial_cycle_failed';
  END IF;

  FOR _job_id IN
    SELECT job.jobid FROM cron.job AS job
    WHERE job.jobname IN (
      'adaptive-alert-shadow-cycle-v1',
      'adaptive-alert-shadow-maintenance-v1'
    )
  LOOP
    PERFORM cron.unschedule(_job_id);
  END LOOP;

  PERFORM cron.schedule(
    'adaptive-alert-shadow-cycle-v1',
    '*/5 * * * *',
    'select private.dispatch_adaptive_alert_shadow_cycle();'
  );
  PERFORM cron.schedule(
    'adaptive-alert-shadow-maintenance-v1',
    '17 2 * * *',
    'select private.dispatch_adaptive_alert_shadow_maintenance();'
  );

  IF (SELECT count(*) FROM cron.job AS job WHERE job.jobname IN (
    'adaptive-alert-shadow-cycle-v1','adaptive-alert-shadow-maintenance-v1'
  )) <> 2 THEN
    RAISE EXCEPTION 'shadow_scheduler_activation_failed';
  END IF;

  IF (SELECT count(*) FROM cron.job) > 8 THEN
    RAISE EXCEPTION 'shadow_scheduler_concurrency_budget_exceeded';
  END IF;
END;
$activation$;