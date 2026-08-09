BEGIN;

SELECT plan(18);

SELECT has_function(
  'private',
  'dispatch_adaptive_alert_shadow_maintenance',
  ARRAY[]::text[],
  'phase-2 exposes one owner-only cumulative maintenance dispatcher'
);

-- ADR-0028/ADR-0038: activation is an environment stage, not something a
-- migration ships. A fresh base therefore carries no model version and no
-- enabled runtime; this file builds its own activation fixture below and then
-- asserts the same activation semantics against it.
SELECT is(
  (SELECT count(*)::integer FROM public.alert_model_versions),
  0,
  'fresh base seeds no shadow model version'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM private.adaptive_alert_shadow_runtime_config
    WHERE singleton
      AND (enabled OR accept_coverage_leases)
  ),
  0,
  'fresh base leaves the shadow runtime unactivated'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM private.adaptive_alert_shadow_runtime_config
    WHERE singleton AND version_id IS NOT NULL
  ),
  'fresh base points the runtime at no model version'
);

SELECT results_eq(
  $$
    SELECT jobname, schedule, trim(command)
    FROM cron.job
    WHERE jobname IN (
      'adaptive-alert-shadow-cycle-v1',
      'adaptive-alert-shadow-maintenance-v1'
    )
    ORDER BY jobname
  $$,
  $$
    VALUES
      (
        'adaptive-alert-shadow-cycle-v1'::text,
        '*/5 * * * *'::text,
        'select private.dispatch_adaptive_alert_shadow_cycle();'::text
      ),
      (
        'adaptive-alert-shadow-maintenance-v1'::text,
        '17 2 * * *'::text,
        'select private.dispatch_adaptive_alert_shadow_maintenance();'::text
      )
  $$,
  'phase-2 schedules only the accepted five-minute cycle and daily cumulative maintenance'
);

SELECT ok(
  to_regprocedure(
    'private.dispatch_adaptive_alert_shadow_maintenance()'
  ) IS NOT NULL,
  'maintenance dispatcher has a catalog identity for owner-only ACL checks'
);

INSERT INTO auth.users (id, email, aud, role)
VALUES (
  '29200000-0000-4000-8000-000000000001',
  'history-seed-activation@example.invalid',
  'authenticated',
  'authenticated'
)
ON CONFLICT (id) DO NOTHING;

WITH config AS (
  SELECT '{
    "sessionization": {
      "gap_minutes": 30,
      "per_user_day_gap_cap": 8,
      "training_horizon_days": 30,
      "intervention_window_minutes": 30,
      "historical_v1_policy": "sessionized_training_only_v1"
    },
    "context": {
      "definition_version": "history-seed-activation-test-v1",
      "day_partition": "all_days",
      "hour_bucket_minutes": 60
    },
    "personal": {
      "min_samples": 3,
      "min_support_dates": 3,
      "min_span_days": 3,
      "max_age_days": 30,
      "min_confidence": 0.7,
      "confidence_formula_version": "support_ratio_v1"
    },
    "cohort": {
      "min_contributors": 3,
      "min_support_dates": 2,
      "min_span_days": 2,
      "max_age_days": 30,
      "min_confidence": 0.5,
      "contribution_floor_minutes": 1,
      "contribution_ceiling_minutes": 600,
      "confidence_formula_version": "cohort_support_min_v1",
      "algorithm": "weighted_median",
      "trim_fraction": 0
    },
    "sensitivity_buffers_minutes": {
      "high": 0,
      "balanced": 45,
      "low": 90
    },
    "candidate_bounds": {
      "floor_minutes": 90,
      "ceiling_minutes": 600
    },
    "sleep_compensation": {
      "max_start_delay_minutes": 0,
      "max_wake_advance_minutes": 0,
      "max_wake_delay_minutes": 0,
      "max_update_minutes_per_day": 0,
      "min_positive_nights": 1,
      "lookback_nights": 1,
      "min_late_events_per_night": 1,
      "timezone_tolerance_minutes": 0
    },
    "evaluator": {
      "contract_version": "adaptive_candidate_v1"
    },
    "emergency": {
      "contract_version": "adr0022_v1",
      "neutral_minutes": 90,
      "expected_live_definition_sha256": "c3efc6cc664dc334166a034651ff584d4c7766d80775c3fe3bc012eb97a9b150"
    }
  }'::jsonb AS value
)
INSERT INTO public.alert_model_versions (
  id,
  name,
  status,
  config,
  config_sha256,
  evidence_version,
  shadow_enabled_at
)
SELECT
  '29200000-0000-4000-8000-000000000010',
  'history-seed-activation-fixture',
  'shadow',
  value,
  encode(extensions.digest(value::text, 'sha256'), 'hex'),
  'canonical-v2',
  clock_timestamp()
FROM config;

UPDATE private.adaptive_alert_shadow_runtime_config
SET version_id = '29200000-0000-4000-8000-000000000010',
    enabled = true,
    accept_coverage_leases = true,
    consecutive_failures = 0,
    last_failure_code = NULL,
    updated_at = clock_timestamp()
WHERE singleton;

INSERT INTO public.behavior_pings (
  user_id,
  kind,
  at,
  received_at,
  ingest_version
)
SELECT
  '29200000-0000-4000-8000-000000000001',
  'app',
  (
    current_date - make_interval(days => day_offset) + interval '08:00'
  )::timestamptz,
  (
    current_date - make_interval(days => day_offset) + interval '08:00'
  )::timestamptz,
  1
FROM generate_series(6, 2, -1) AS day_offset;

DO $normalize_live_definition$
BEGIN
  EXECUTE replace(
    pg_get_functiondef(
      'private.silence_threshold(uuid)'::regprocedure
    ),
    E'\r\n',
    E'\n'
  );
END;
$normalize_live_definition$;

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
  'c3efc6cc664dc334166a034651ff584d4c7766d80775c3fe3bc012eb97a9b150',
  'fixture reproduces the authorized live threshold definition hash'
);

-- Activation semantics, now asserted against the fixture this file owns.
SELECT is(
  (
    SELECT config #>> '{sessionization,historical_v1_policy}'
    FROM public.alert_model_versions
    WHERE name = 'history-seed-activation-fixture'
  ),
  'sessionized_training_only_v1',
  'the activated shadow model explicitly admits sessionized v1 training evidence'
);

SELECT is(
  (
    SELECT v.name
    FROM private.adaptive_alert_shadow_runtime_config AS runtime
    JOIN public.alert_model_versions AS v ON v.id = runtime.version_id
    WHERE runtime.singleton
      AND runtime.enabled
      AND runtime.accept_coverage_leases
  ),
  'history-seed-activation-fixture',
  'runtime points at the enabled activated model'
);

CREATE TEMP TABLE activation_live_before AS
SELECT
  (
    SELECT coalesce(
      md5(string_agg(to_jsonb(a)::text, ',' ORDER BY a.id)),
      ''
    )
    FROM public.alerts AS a
  ) AS alerts_hash,
  (
    SELECT coalesce(
      md5(string_agg(to_jsonb(e)::text, ',' ORDER BY e.id)),
      ''
    )
    FROM public.alert_events AS e
  ) AS alert_events_hash,
  (
    SELECT coalesce(
      md5(string_agg(to_jsonb(n)::text, ',' ORDER BY n.id)),
      ''
    )
    FROM public.notifications AS n
  ) AS notifications_hash,
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
    SELECT private.rebuild_alert_gap_profiles(
      '29200000-0000-4000-8000-000000000010',
      current_date
    )
  $$,
  'retained v1 history builds the initial personal profile without a template'
);

SELECT results_eq(
  $$
    SELECT
      sample_count,
      distinct_support_dates,
      quality_state,
      confidence
    FROM public.alert_gap_profiles
    WHERE version_id = '29200000-0000-4000-8000-000000000010'
      AND user_id = '29200000-0000-4000-8000-000000000001'
      AND context_key = 'personal_global'
      AND through_date = current_date
  $$,
  $$
    VALUES (
      4,
      4,
      'valid'::text,
      1::double precision
    )
  $$,
  'five historical sessions create four valid personalized gaps'
);

CREATE TEMP TABLE activation_profile_before AS
SELECT
  version_id,
  user_id,
  context_key,
  through_date,
  sample_count,
  input_sha256,
  profile_sha256
FROM public.alert_gap_profiles
WHERE version_id = '29200000-0000-4000-8000-000000000010'
  AND user_id = '29200000-0000-4000-8000-000000000001'
  AND context_key = 'personal_global'
  AND through_date = current_date;

INSERT INTO public.alert_observation_coverage_intervals (
  version_id,
  user_id,
  starts_at,
  ends_at,
  timezone,
  utc_offset_minutes,
  activity_coverage_state,
  intervention_coverage_state,
  sleep_context_state,
  captured_at,
  finalized_at,
  evidence_version,
  provenance_sha256
)
VALUES (
  '29200000-0000-4000-8000-000000000010',
  '29200000-0000-4000-8000-000000000001',
  current_date::timestamptz,
  current_date::timestamptz + interval '18 hours',
  'UTC',
  0,
  'valid',
  'valid',
  'valid',
  current_date::timestamptz,
  current_date::timestamptz + interval '18 hours',
  'canonical-v2',
  repeat('2', 64)
);

INSERT INTO public.behavior_pings (
  user_id,
  kind,
  at,
  received_at,
  ingest_version,
  event_id,
  source
)
VALUES
  (
    '29200000-0000-4000-8000-000000000001',
    'app',
    current_date::timestamptz + interval '10 hours',
    current_date::timestamptz + interval '10 hours',
    2,
    '29200000-0000-4000-8000-000000000101',
    'app'
  ),
  (
    '29200000-0000-4000-8000-000000000001',
    'app',
    current_date::timestamptz + interval '14 hours',
    current_date::timestamptz + interval '14 hours',
    2,
    '29200000-0000-4000-8000-000000000102',
    'app'
  );

SELECT lives_ok(
  $$
    SELECT private.dispatch_adaptive_alert_shadow_maintenance()
  $$,
  'daily maintenance accepts new canonical evidence after the historical seed'
);

SELECT results_eq(
  $$
    SELECT
      p.version_id = b.version_id
        AND p.user_id = b.user_id
        AND p.context_key = b.context_key
        AND p.through_date = b.through_date AS same_profile_key,
      p.sample_count,
      p.input_sha256 <> b.input_sha256 AS input_extended,
      p.profile_sha256 <> b.profile_sha256 AS profile_extended
    FROM public.alert_gap_profiles AS p
    CROSS JOIN activation_profile_before AS b
    WHERE p.version_id = '29200000-0000-4000-8000-000000000010'
      AND p.user_id = '29200000-0000-4000-8000-000000000001'
      AND p.context_key = 'personal_global'
      AND p.through_date = current_date
  $$,
  $$
    VALUES (true, 5, true, true)
  $$,
  'new v2 evidence extends the same personal profile from four to five gaps'
);

SELECT results_eq(
  $$
    SELECT ingest_version, count(*)::bigint
    FROM public.behavior_pings
    WHERE user_id = '29200000-0000-4000-8000-000000000001'
    GROUP BY ingest_version
    ORDER BY ingest_version
  $$,
  $$
    VALUES
      (1::smallint, 5::bigint),
      (2::smallint, 2::bigint)
  $$,
  'maintenance preserves original evidence versions instead of rewriting history'
);

SELECT results_eq(
  $$
    SELECT * FROM activation_live_before
    EXCEPT
    SELECT
      (
        SELECT coalesce(
          md5(string_agg(to_jsonb(a)::text, ',' ORDER BY a.id)),
          ''
        )
        FROM public.alerts AS a
      ),
      (
        SELECT coalesce(
          md5(string_agg(to_jsonb(e)::text, ',' ORDER BY e.id)),
          ''
        )
        FROM public.alert_events AS e
      ),
      (
        SELECT coalesce(
          md5(string_agg(to_jsonb(n)::text, ',' ORDER BY n.id)),
          ''
        )
        FROM public.notifications AS n
      ),
      live_threshold_hash
    FROM activation_live_before
  $$,
  $$
    SELECT * FROM activation_live_before WHERE false
  $$,
  'history seeding and cumulative maintenance do not mutate live alert tables'
);

SELECT is(
  (
    SELECT encode(
      extensions.digest(
        pg_get_functiondef(
          'private.silence_threshold(uuid)'::regprocedure
        ),
        'sha256'
      ),
      'hex'
    )
  ),
  (
    SELECT live_threshold_hash FROM activation_live_before
  ),
  'phase-2 leaves the live silence-threshold function byte-for-byte unchanged'
);

-- ADR-0038 moved the initial validation cycle out of the migration and into the
-- environment activation step, so this file runs the cycle it is asserting on.
SELECT lives_ok(
  $$
    SELECT private.run_adaptive_alert_shadow_cycle(
      '29200000-0000-4000-8000-000000000010',
      clock_timestamp() + interval '1 minute'
    )
  $$,
  'the activated model can run one shadow validation cycle'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM private.adaptive_alert_shadow_cycle_runs AS run
    JOIN public.alert_model_versions AS version
      ON version.id = run.version_id
    WHERE version.name = 'history-seed-activation-fixture'
  ),
  'activation records an initial shadow validation cycle for the activated model'
);

SELECT * FROM finish();
ROLLBACK;
