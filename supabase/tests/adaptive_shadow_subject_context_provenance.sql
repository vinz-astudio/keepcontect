BEGIN;

SELECT plan(6);

INSERT INTO auth.users (id, email, aud, role)
VALUES (
  '29300000-0000-4000-8000-000000000001',
  'subject-provenance@example.invalid',
  'authenticated',
  'authenticated'
)
ON CONFLICT (id) DO NOTHING;

-- The base carries no auth.users provisioning trigger, so this test owns its
-- application-layer rows explicitly instead of relying on a side effect.
INSERT INTO public.profiles (id, display_name)
VALUES ('29300000-0000-4000-8000-000000000001', 'Subject provenance fixture')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

INSERT INTO public.user_settings (user_id, sensitivity, timezone, updated_at)
VALUES (
  '29300000-0000-4000-8000-000000000001',
  'balanced',
  'UTC',
  clock_timestamp() - interval '1 minute'
)
ON CONFLICT (user_id) DO UPDATE
SET sensitivity = EXCLUDED.sensitivity,
    timezone = EXCLUDED.timezone,
    updated_at = EXCLUDED.updated_at;

-- ADR-0038 leaves a fresh base unactivated, so this test owns its own shadow
-- model version and activation rather than inheriting a migration-seeded one.
WITH config AS (
  SELECT '{
  "sessionization":{"gap_minutes":30,"per_user_day_gap_cap":8,"training_horizon_days":30,"intervention_window_minutes":30},
  "context":{"definition_version":"subject-provenance-v1","day_partition":"all_days","hour_bucket_minutes":60},
  "personal":{"min_samples":3,"min_support_dates":2,"min_span_days":2,"max_age_days":30,"min_confidence":0.7,"confidence_formula_version":"support_ratio_v1"},
  "cohort":{"min_contributors":3,"min_support_dates":2,"min_span_days":2,"max_age_days":30,"min_confidence":0.5,"contribution_floor_minutes":1,"contribution_ceiling_minutes":600,"confidence_formula_version":"cohort_support_min_v1","algorithm":"trimmed_mean","trim_fraction":0.1},
  "sensitivity_buffers_minutes":{"high":0,"balanced":45,"low":90},
  "candidate_bounds":{"floor_minutes":1,"ceiling_minutes":600},
  "sleep_compensation":{"max_start_delay_minutes":60,"max_wake_advance_minutes":60,"max_wake_delay_minutes":60,"max_update_minutes_per_day":30,"min_positive_nights":2,"lookback_nights":3,"min_late_events_per_night":1,"timezone_tolerance_minutes":30},
  "evaluator":{"contract_version":"adaptive_candidate_v1"},
  "emergency":{"contract_version":"adr0022_v1","neutral_minutes":90,"expected_live_definition_sha256":"c3efc6cc664dc334166a034651ff584d4c7766d80775c3fe3bc012eb97a9b150"}
}'::jsonb AS value
)
INSERT INTO public.alert_model_versions (
  id, name, status, config, config_sha256, evidence_version, shadow_enabled_at
)
SELECT
  '29300000-0000-4000-8000-000000000020',
  'subject-provenance-fixture',
  'shadow',
  value,
  encode(extensions.digest(value::text, 'sha256'), 'hex'),
  'canonical-v2',
  clock_timestamp() - interval '1 hour'
FROM config;

UPDATE private.adaptive_alert_shadow_runtime_config
SET version_id = '29300000-0000-4000-8000-000000000020',
    enabled = true,
    accept_coverage_leases = true,
    consecutive_failures = 0,
    last_failure_code = NULL,
    updated_at = clock_timestamp()
WHERE singleton;

INSERT INTO public.device_state (user_id)
VALUES ('29300000-0000-4000-8000-000000000001')
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO public.groups (id, name, created_by)
VALUES (
  '29300000-0000-4000-8000-000000000010',
  'subject-provenance-fixture',
  '29300000-0000-4000-8000-000000000001'
);

UPDATE public.group_members
SET monitored = true,
    watching = true,
    status = 'active'
WHERE group_id = '29300000-0000-4000-8000-000000000010'
  AND user_id = '29300000-0000-4000-8000-000000000001';

CREATE TEMP TABLE subject_provenance_active AS
SELECT
  runtime.version_id,
  date_trunc(
    'minute',
    clock_timestamp() AT TIME ZONE 'UTC'
  ) AT TIME ZONE 'UTC' AS captured_at,
  runtime.max_population
FROM private.adaptive_alert_shadow_runtime_config AS runtime
WHERE runtime.singleton;

CREATE TEMP TABLE subject_provenance_live_before AS
SELECT
  (SELECT count(*)::bigint FROM public.alerts) AS alerts_count,
  (SELECT count(*)::bigint FROM public.alert_events) AS alert_events_count,
  (SELECT count(*)::bigint FROM public.notifications) AS notifications_count,
  encode(
    extensions.digest(
      pg_get_functiondef(
        'private.silence_threshold(uuid)'::regprocedure
      ),
      'sha256'
    ),
    'hex'
  ) AS live_threshold_hash;

SELECT lives_ok(
  $$
    SELECT private.capture_alert_shadow_subject_contexts(
      version_id,
      captured_at,
      max_population
    )
    FROM subject_provenance_active
  $$,
  'operational producer captures a monitored subject context'
);

SELECT is(
  (
    SELECT context.subject_context_sha256
    FROM public.alert_judgment_subject_contexts AS context
    CROSS JOIN subject_provenance_active AS active
    WHERE context.version_id = active.version_id
      AND context.user_id =
        '29300000-0000-4000-8000-000000000001'
      AND context.effective_to IS NULL
  ),
  (
    SELECT encode(
      extensions.digest(
        jsonb_build_object(
          'version_id', context.version_id,
          'user_id', context.user_id,
          'effective_from_utc',
            to_char(
              context.effective_from AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
          'effective_to_utc', NULL,
          'raw_sensitivity', context.raw_sensitivity,
          'canonical_sensitivity', context.canonical_sensitivity,
          'routine_mode', context.routine_mode,
          'timezone', context.timezone,
          'utc_offset_minutes', context.utc_offset_minutes,
          'settings_updated_at_utc',
            to_char(
              context.settings_updated_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
          'settings_provenance', context.settings_provenance,
          'captured_at_utc',
            to_char(
              context.captured_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
          'config_sha256', context.config_sha256,
          'evidence_version', context.evidence_version
        )::text,
        'sha256'
      ),
      'hex'
    )
    FROM public.alert_judgment_subject_contexts AS context
    CROSS JOIN subject_provenance_active AS active
    WHERE context.version_id = active.version_id
      AND context.user_id =
        '29300000-0000-4000-8000-000000000001'
      AND context.effective_to IS NULL
  ),
  'producer stores the exact complete-row hash recomputed by the evaluator'
);

SELECT is(
  (
    SELECT private.resolve_alert_candidate(
      '29300000-0000-4000-8000-000000000001',
      captured_at,
      version_id
    ) ->> 'unreplayable_reason'
    FROM subject_provenance_active
  ),
  'missing_qualified_session',
  'valid subject provenance advances evaluation to the next legitimate evidence gate'
);

SELECT is(
  (
    SELECT canonical_sensitivity
    FROM public.alert_judgment_subject_contexts AS context
    CROSS JOIN subject_provenance_active AS active
    WHERE context.version_id = active.version_id
      AND context.user_id =
        '29300000-0000-4000-8000-000000000001'
      AND context.effective_to IS NULL
  ),
  'balanced',
  'producer persists the evaluator canonical sensitivity'
);

SELECT results_eq(
  $$
    SELECT * FROM subject_provenance_live_before
    EXCEPT
    SELECT
      (SELECT count(*)::bigint FROM public.alerts),
      (SELECT count(*)::bigint FROM public.alert_events),
      (SELECT count(*)::bigint FROM public.notifications),
      live_threshold_hash
    FROM subject_provenance_live_before
  $$,
  $$
    SELECT * FROM subject_provenance_live_before WHERE false
  $$,
  'context recapture does not mutate live alert tables'
);

SELECT is(
  encode(
    extensions.digest(
      pg_get_functiondef(
        'private.silence_threshold(uuid)'::regprocedure
      ),
      'sha256'
    ),
    'hex'
  ),
  (
    SELECT live_threshold_hash FROM subject_provenance_live_before
  ),
  'context repair leaves the live threshold function unchanged'
);

SELECT * FROM finish();
ROLLBACK;
