BEGIN;

SELECT plan(23);

INSERT INTO auth.users (id, email, aud, role)
VALUES (
  '29100000-0000-4000-8000-000000000001',
  'adr0029-p1@example.invalid',
  'authenticated',
  'authenticated'
)
ON CONFLICT (id) DO NOTHING;

WITH config AS (
  SELECT '{
    "sessionization": {
      "gap_minutes": 30,
      "per_user_day_gap_cap": 8,
      "training_horizon_days": 35,
      "intervention_window_minutes": 30,
      "historical_v1_policy": "sessionized_training_only_v1"
    },
    "context": {
      "definition_version": "adr0029-p1-test-v1",
      "day_partition": "all_days",
      "hour_bucket_minutes": 60
    },
    "personal": {
      "min_samples": 1,
      "min_support_dates": 1,
      "min_span_days": 1,
      "max_age_days": 35,
      "min_confidence": 0.7,
      "confidence_formula_version": "support_ratio_v1"
    },
    "cohort": {
      "min_contributors": 3,
      "min_support_dates": 2,
      "min_span_days": 2,
      "max_age_days": 35,
      "min_confidence": 0.5,
      "contribution_floor_minutes": 1,
      "contribution_ceiling_minutes": 600,
      "confidence_formula_version": "cohort_support_min_v1",
      "algorithm": "trimmed_mean",
      "trim_fraction": 0.1
    },
    "sensitivity_buffers_minutes": {"high": 0, "balanced": 45, "low": 90},
    "candidate_bounds": {"floor_minutes": 1, "ceiling_minutes": 600},
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
    "evaluator": {"contract_version": "adaptive_candidate_v1"},
    "emergency": {
      "contract_version": "adr0022_v1",
      "neutral_minutes": 90,
      "expected_live_definition_sha256": "1907d59473d274d46a0e8e0b9ce8027037b4494b0dddf073cb46abf67db92e21"
    }
  }'::jsonb AS value
)
INSERT INTO public.alert_model_versions (
  id, name, status, config, config_sha256, evidence_version
)
SELECT
  '29100000-0000-4000-8000-000000000010',
  'adr0029-p1-v1-opt-in',
  'replay',
  value,
  encode(extensions.digest(value::text, 'sha256'), 'hex'),
  'canonical-v2'
FROM config;

WITH config AS (
  SELECT '{
    "sessionization": {
      "gap_minutes": 30,
      "per_user_day_gap_cap": 8,
      "training_horizon_days": 35,
      "intervention_window_minutes": 30
    },
    "context": {
      "definition_version": "adr0029-p1-control-v1",
      "day_partition": "all_days",
      "hour_bucket_minutes": 60
    },
    "personal": {
      "min_samples": 1,
      "min_support_dates": 1,
      "min_span_days": 1,
      "max_age_days": 35,
      "min_confidence": 0.7,
      "confidence_formula_version": "support_ratio_v1"
    },
    "cohort": {
      "min_contributors": 3,
      "min_support_dates": 2,
      "min_span_days": 2,
      "max_age_days": 35,
      "min_confidence": 0.5,
      "contribution_floor_minutes": 1,
      "contribution_ceiling_minutes": 600,
      "confidence_formula_version": "cohort_support_min_v1",
      "algorithm": "trimmed_mean",
      "trim_fraction": 0.1
    },
    "sensitivity_buffers_minutes": {"high": 0, "balanced": 45, "low": 90},
    "candidate_bounds": {"floor_minutes": 1, "ceiling_minutes": 600},
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
    "evaluator": {"contract_version": "adaptive_candidate_v1"},
    "emergency": {
      "contract_version": "adr0022_v1",
      "neutral_minutes": 90,
      "expected_live_definition_sha256": "1907d59473d274d46a0e8e0b9ce8027037b4494b0dddf073cb46abf67db92e21"
    }
  }'::jsonb AS value
)
INSERT INTO public.alert_model_versions (
  id, name, status, config, config_sha256, evidence_version
)
SELECT
  '29100000-0000-4000-8000-000000000020',
  'adr0029-p1-v2-only-control',
  'replay',
  value,
  encode(extensions.digest(value::text, 'sha256'), 'hex'),
  'canonical-v2'
FROM config;

INSERT INTO public.behavior_pings (
  user_id, kind, at, source, received_at, ingest_version
) VALUES
  ('29100000-0000-4000-8000-000000000001', 'app', '2026-07-01 00:00+00', 'app', '2026-07-01 00:00+00', 1),
  ('29100000-0000-4000-8000-000000000001', 'app', '2026-07-01 00:05+00', 'app', '2026-07-01 00:05+00', 1),
  ('29100000-0000-4000-8000-000000000001', 'app', '2026-07-01 00:10+00', 'app', '2026-07-01 00:10+00', 1),
  ('29100000-0000-4000-8000-000000000001', 'app', '2026-07-01 04:00+00', 'app', '2026-07-01 04:00+00', 1),
  ('29100000-0000-4000-8000-000000000001', 'app', '2026-07-01 04:05+00', 'app', '2026-07-01 04:05+00', 1);

CREATE TEMP TABLE p1_before AS
SELECT
  (
    SELECT encode(
      extensions.digest(
        coalesce(
          jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text)::text,
          '[]'
        ),
        'sha256'
      ),
      'hex'
    )
    FROM public.behavior_pings t
  ) AS behavior_pings_sha256,
  (
    SELECT encode(
      extensions.digest(
        coalesce(
          jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text)::text,
          '[]'
        ),
        'sha256'
      ),
      'hex'
    )
    FROM public.device_state t
  ) AS device_state_sha256,
  (
    SELECT encode(
      extensions.digest(
        coalesce(
          jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text)::text,
          '[]'
        ),
        'sha256'
      ),
      'hex'
    )
    FROM public.alerts t
  ) AS alerts_sha256,
  (
    SELECT encode(
      extensions.digest(
        coalesce(
          jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text)::text,
          '[]'
        ),
        'sha256'
      ),
      'hex'
    )
    FROM public.alert_events t
  ) AS alert_events_sha256,
  (
    SELECT encode(
      extensions.digest(
        coalesce(
          jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text)::text,
          '[]'
        ),
        'sha256'
      ),
      'hex'
    )
    FROM public.notifications t
  ) AS notifications_sha256,
  encode(
    extensions.digest(
      pg_get_functiondef('private.silence_threshold(uuid)'::regprocedure),
      'sha256'
    ),
    'hex'
  ) AS silence_threshold_sha256;

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.alert_model_versions'::regclass
      AND conname = 'alert_model_versions_historical_v1_policy_check'
  ),
  'model config constrains the historical-v1 training policy'
);

SELECT has_function(
  'private',
  'normalized_behavior_training_sessions',
  ARRAY[
    'uuid',
    'timestamp with time zone',
    'timestamp with time zone',
    'uuid'
  ],
  'owner-only normalized training evidence source exists'
);

CREATE TEMP TABLE p1_sessions AS
SELECT *
FROM private.normalized_behavior_training_sessions(
  '29100000-0000-4000-8000-000000000001',
  '2026-07-01 00:00+00',
  '2026-07-02 00:00+00',
  '29100000-0000-4000-8000-000000000010'
);

SELECT results_eq(
  $$
    SELECT
      session_start,
      session_end,
      context_key,
      evidence_count,
      source_ingest_version,
      training_provenance,
      quality_state
    FROM p1_sessions
    ORDER BY session_start
  $$,
  $$
    VALUES
      (
        '2026-07-01 00:00+00'::timestamptz,
        '2026-07-01 00:10+00'::timestamptz,
        NULL::text,
        3,
        1::smallint,
        'historical_v1_training_only'::text,
        'valid'::text
      ),
      (
        '2026-07-01 04:00+00'::timestamptz,
        '2026-07-01 04:05+00'::timestamptz,
        NULL::text,
        2,
        1::smallint,
        'historical_v1_training_only'::text,
        'valid'::text
      )
  $$,
  'v1 rows become sessionized training evidence without invented context'
);

SELECT ok(
  (
    SELECT count(*) = 2
      AND count(DISTINCT provenance_sha256) = 2
      AND bool_and(provenance_sha256 ~ '^[0-9a-f]{64}$')
    FROM p1_sessions
  ),
  'each historical session has distinct auditable SHA-256 provenance'
);

SELECT results_eq(
  $$
    SELECT *
    FROM p1_sessions
    EXCEPT
    SELECT *
    FROM private.normalized_behavior_training_sessions(
      '29100000-0000-4000-8000-000000000001',
      '2026-07-01 00:00+00',
      '2026-07-02 00:00+00',
      '29100000-0000-4000-8000-000000000010'
    )
  $$,
  $$ SELECT * FROM p1_sessions WHERE false $$,
  'normalized historical sessions are deterministic'
);

SELECT is_empty(
  $$
    SELECT *
    FROM private.normalized_behavior_training_sessions(
      '29100000-0000-4000-8000-000000000001',
      '2026-07-01 00:00+00',
      '2026-07-02 00:00+00',
      '29100000-0000-4000-8000-000000000020'
    )
  $$,
  'models without explicit opt-in remain canonical-v2-only'
);

SELECT is_empty(
  $$
    SELECT *
    FROM private.qualified_behavior_sessions(
      '29100000-0000-4000-8000-000000000001',
      '2026-07-01 00:00+00',
      '2026-07-02 00:00+00',
      '29100000-0000-4000-8000-000000000010'
    )
  $$,
  'canonical qualified sessions remain v2-only'
);

SELECT is(
  (
    private.rebuild_alert_gap_profiles(
      '29100000-0000-4000-8000-000000000010',
      '2026-07-01'
    ) ->> 'completed_gaps'
  )::integer,
  1,
  'opted-in rebuild admits exactly one completed historical gap'
);

SELECT results_eq(
  $$
    SELECT
      neutral_p95_minutes,
      sample_count,
      distinct_support_dates,
      support_started_on,
      support_ended_on,
      quality_state
    FROM public.alert_gap_profiles
    WHERE version_id = '29100000-0000-4000-8000-000000000010'
      AND user_id = '29100000-0000-4000-8000-000000000001'
      AND context_key = 'personal_global'
      AND through_date = '2026-07-01'
  $$,
  $$
    VALUES (
      230,
      1,
      1,
      '2026-07-01'::date,
      '2026-07-01'::date,
      'valid'::text
    )
  $$,
  'historical v1 contributes the session-to-session gap to personal global training'
);

SELECT is_empty(
  $$
    SELECT *
    FROM public.alert_gap_profiles
    WHERE version_id = '29100000-0000-4000-8000-000000000010'
      AND user_id = '29100000-0000-4000-8000-000000000001'
      AND context_key <> 'personal_global'
  $$,
  'historical v1 never invents comparable context profiles'
);

SELECT is(
  (
    private.rebuild_alert_gap_profiles(
      '29100000-0000-4000-8000-000000000020',
      '2026-07-01'
    ) ->> 'completed_gaps'
  )::integer,
  0,
  'v2-only control rebuild admits no historical gaps'
);

SELECT is_empty(
  $$
    SELECT *
    FROM public.alert_gap_profiles
    WHERE version_id = '29100000-0000-4000-8000-000000000020'
      AND user_id = '29100000-0000-4000-8000-000000000001'
  $$,
  'v2-only control writes no profile from v1 rows'
);

CREATE TEMP TABLE p1_profile_before AS
SELECT profile_sha256, input_sha256, computed_at
FROM public.alert_gap_profiles
WHERE version_id = '29100000-0000-4000-8000-000000000010'
  AND user_id = '29100000-0000-4000-8000-000000000001'
  AND context_key = 'personal_global'
  AND through_date = '2026-07-01';

SELECT is(
  (
    private.rebuild_alert_gap_profiles(
      '29100000-0000-4000-8000-000000000010',
      '2026-07-01'
    ) ->> 'profiles_written'
  )::integer,
  0,
  'identical historical rebuild is idempotent'
);

SELECT results_eq(
  $$
    SELECT *
    FROM p1_profile_before
    EXCEPT
    SELECT profile_sha256, input_sha256, computed_at
    FROM public.alert_gap_profiles
    WHERE version_id = '29100000-0000-4000-8000-000000000010'
      AND user_id = '29100000-0000-4000-8000-000000000001'
      AND context_key = 'personal_global'
      AND through_date = '2026-07-01'
  $$,
  $$ SELECT * FROM p1_profile_before WHERE false $$,
  'identical historical input preserves profile hashes and computed time'
);

SELECT results_eq(
  $$
    SELECT behavior_pings_sha256
    FROM p1_before
  $$,
  $$
    SELECT encode(
      extensions.digest(
        coalesce(
          jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text)::text,
          '[]'
        ),
        'sha256'
      ),
      'hex'
    )
    FROM public.behavior_pings t
  $$,
  'historical source rows remain byte-for-byte unchanged'
);

SELECT results_eq(
  $$
    SELECT count(*)::integer, bool_and(event_id IS NULL)
    FROM public.behavior_pings
    WHERE user_id = '29100000-0000-4000-8000-000000000001'
      AND ingest_version = 1
  $$,
  $$ VALUES (5, true) $$,
  'historical rows retain ingest-version and non-idempotent event-id semantics'
);

SELECT results_eq(
  $$
    SELECT
      device_state_sha256,
      alerts_sha256,
      alert_events_sha256,
      notifications_sha256
    FROM p1_before
  $$,
  $$
    SELECT
      (
        SELECT encode(
          extensions.digest(
            coalesce(
              jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text)::text,
              '[]'
            ),
            'sha256'
          ),
          'hex'
        )
        FROM public.device_state t
      ),
      (
        SELECT encode(
          extensions.digest(
            coalesce(
              jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text)::text,
              '[]'
            ),
            'sha256'
          ),
          'hex'
        )
        FROM public.alerts t
      ),
      (
        SELECT encode(
          extensions.digest(
            coalesce(
              jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text)::text,
              '[]'
            ),
            'sha256'
          ),
          'hex'
        )
        FROM public.alert_events t
      ),
      (
        SELECT encode(
          extensions.digest(
            coalesce(
              jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text)::text,
              '[]'
            ),
            'sha256'
          ),
          'hex'
        )
        FROM public.notifications t
      )
  $$,
  'training-only rebuild cannot mutate live heartbeat, alert, or notification state'
);

SELECT results_eq(
  $$
    SELECT silence_threshold_sha256
    FROM p1_before
  $$,
  $$
    SELECT encode(
      extensions.digest(
        pg_get_functiondef('private.silence_threshold(uuid)'::regprocedure),
        'sha256'
      ),
      'hex'
    )
  $$,
  'live silence threshold definition is unchanged'
);

SELECT ok(
  (
    SELECT
      p.prosecdef
      AND p.provolatile = 's'
      AND r.rolname = current_user
    FROM pg_proc p
    JOIN pg_roles r ON r.oid = p.proowner
    WHERE p.oid = (
      'private.normalized_behavior_training_sessions('
      'uuid,timestamptz,timestamptz,uuid)'
    )::regprocedure
  ),
  'normalized evidence source is owner-only stable security definer'
);

SELECT ok(
  (
    SELECT proconfig @> ARRAY['search_path=""', 'TimeZone=UTC']
    FROM pg_proc
    WHERE oid = (
      'private.normalized_behavior_training_sessions('
      'uuid,timestamptz,timestamptz,uuid)'
    )::regprocedure
  ),
  'normalized evidence source pins an empty search path and UTC timezone'
);

SELECT ok(
  NOT has_function_privilege(
    'public',
    'private.normalized_behavior_training_sessions(uuid,timestamptz,timestamptz,uuid)',
    'EXECUTE'
  )
  AND NOT has_function_privilege(
    'anon',
    'private.normalized_behavior_training_sessions(uuid,timestamptz,timestamptz,uuid)',
    'EXECUTE'
  )
  AND NOT has_function_privilege(
    'authenticated',
    'private.normalized_behavior_training_sessions(uuid,timestamptz,timestamptz,uuid)',
    'EXECUTE'
  )
  AND NOT has_function_privilege(
    'service_role',
    'private.normalized_behavior_training_sessions(uuid,timestamptz,timestamptz,uuid)',
    'EXECUTE'
  ),
  'PUBLIC and every Data API role are denied normalized evidence execution'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM cron.job
    WHERE lower(coalesce(jobname, '')) ~ '(historical_v1|normalized_behavior_training)'
      OR lower(coalesce(command, '')) ~ '(historical_v1|normalized_behavior_training)'
  ),
  'historical-v1 training introduces no scheduler'
);

SELECT throws_ok(
  $$
    INSERT INTO public.alert_model_versions (
      name, status, config, config_sha256, evidence_version
    )
    SELECT
      'adr0029-p1-invalid-policy',
      'draft',
      jsonb_set(
        config,
        '{sessionization,historical_v1_policy}',
        '"live_and_training_v1"'::jsonb
      ),
      repeat('f', 64),
      evidence_version
    FROM public.alert_model_versions
    WHERE id = '29100000-0000-4000-8000-000000000020'
  $$,
  '23514'::char(5),
  NULL,
  'unknown or live historical-v1 policy is rejected'
);

SELECT * FROM finish();
ROLLBACK;
