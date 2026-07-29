BEGIN;

SELECT plan(33);

-- Task 7 is an aggregate-only historical replay boundary: no context/
-- coverage/sleep producer, no scheduler, no live-alert write.
SELECT has_function(
  'private', 'run_alert_judgment_replay',
  ARRAY['uuid', 'timestamp with time zone', 'timestamp with time zone'],
  'locked replay entrypoint exists'
);
SELECT function_privs_are(
  'private', 'run_alert_judgment_replay',
  ARRAY['uuid', 'timestamp with time zone', 'timestamp with time zone'],
  'anon', ARRAY[]::text[]
);
SELECT function_privs_are(
  'private', 'run_alert_judgment_replay',
  ARRAY['uuid', 'timestamp with time zone', 'timestamp with time zone'],
  'authenticated', ARRAY[]::text[]
);
SELECT function_privs_are(
  'private', 'run_alert_judgment_replay',
  ARRAY['uuid', 'timestamp with time zone', 'timestamp with time zone'],
  'service_role', ARRAY[]::text[]
);
SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    WHERE p.oid =
      'private.run_alert_judgment_replay(uuid,timestamptz,timestamptz)'::regprocedure
      AND acl.grantee = 0
  ),
  'PUBLIC cannot execute the replay entrypoint'
);
SELECT ok(
  (
    SELECT p.prosecdef
      AND p.provolatile = 'v'
      AND p.proconfig @> ARRAY[
        'search_path=""', 'TimeZone=UTC', 'DateStyle=ISO, YMD',
        'extra_float_digits=3'
      ]
      AND r.rolname = current_user
    FROM pg_proc p
    JOIN pg_roles r ON r.oid = p.proowner
    WHERE p.oid =
      'private.run_alert_judgment_replay(uuid,timestamptz,timestamptz)'::regprocedure
  ),
  'replay is owner-only VOLATILE SECURITY DEFINER with empty path and UTC'
);

-- Owner-repair regression: enumeration/sessionization must happen exactly
-- once, in one MATERIALIZED CTE, with the bounded result captured into an
-- in-memory jsonb array rather than re-read from behavior_pings by a later
-- statement or persisted anywhere. This is a mechanical source-shape check,
-- not a substitute for the behavioral max_units/idempotency assertions below.
SELECT is(
  (
    SELECT count(*)::integer
    FROM regexp_matches(
      pg_get_functiondef(
        'private.run_alert_judgment_replay(uuid,timestamptz,timestamptz)'::regprocedure
      ),
      'candidate_replay_units\s+AS\s+MATERIALIZED',
      'gi'
    )
  ),
  1,
  'the compiled replay function sessionizes via exactly one candidate_replay_units AS MATERIALIZED CTE'
);
SELECT ok(
  pg_get_functiondef(
    'private.run_alert_judgment_replay(uuid,timestamptz,timestamptz)'::regprocedure
  ) !~* 'CREATE\s+(TEMP|TEMPORARY|UNLOGGED)?\s*TABLE',
  'the compiled replay function creates no temp/permanent per-user table'
);
SELECT ok(
  (
    SELECT pg_get_functiondef(
      'private.run_alert_judgment_replay(uuid,timestamptz,timestamptz)'::regprocedure
    ) ~ 'received_at >= _from'
      AND pg_get_functiondef(
        'private.run_alert_judgment_replay(uuid,timestamptz,timestamptz)'::regprocedure
      ) ~ 'ORDER BY p.received_at DESC, p.id DESC'
      AND pg_get_functiondef(
        'private.run_alert_judgment_replay(uuid,timestamptz,timestamptz)'::regprocedure
      ) ~ 'LIMIT 1'
  ),
  'enumeration admits the bounded range plus exactly the last eligible pre-range ping'
);

-- Fixture: a contract-bearing config valid for both the Task 6 evaluator and
-- the Task 7 replay preflight.
CREATE TEMP TABLE replay_base_config AS
SELECT '{
  "sessionization":{
    "gap_minutes":30,
    "per_user_day_gap_cap":8,
    "training_horizon_days":30,
    "intervention_window_minutes":30
  },
  "context":{
    "definition_version":"replay-test-v1",
    "day_partition":"all_days",
    "hour_bucket_minutes":60
  },
  "personal":{
    "min_samples":2,
    "min_support_dates":2,
    "min_span_days":2,
    "max_age_days":30,
    "min_confidence":0.7,
    "confidence_formula_version":"support_ratio_v1"
  },
  "cohort":{
    "min_contributors":2,
    "min_support_dates":2,
    "min_span_days":2,
    "max_age_days":30,
    "min_confidence":0.5,
    "contribution_floor_minutes":1,
    "contribution_ceiling_minutes":1000,
    "confidence_formula_version":"cohort_support_min_v1",
    "algorithm":"weighted_median",
    "trim_fraction":0
  },
  "sensitivity_buffers_minutes":{"high":0,"balanced":45,"low":90},
  "candidate_bounds":{"floor_minutes":30,"ceiling_minutes":600},
  "sleep_compensation":{
    "max_start_delay_minutes":45,
    "max_wake_advance_minutes":45,
    "max_wake_delay_minutes":90,
    "max_update_minutes_per_day":30,
    "min_positive_nights":1,
    "lookback_nights":1,
    "min_late_events_per_night":1,
    "timezone_tolerance_minutes":0
  },
  "evaluator":{"contract_version":"adaptive_candidate_v1"},
  "emergency":{
    "contract_version":"adr0022_v1",
    "neutral_minutes":90,
    "expected_live_definition_sha256":"1907d59473d274d46a0e8e0b9ce8027037b4494b0dddf073cb46abf67db92e21"
  }
}'::jsonb AS config;

INSERT INTO public.alert_model_versions (
  id, name, status, config, config_sha256, evidence_version
)
SELECT fixture.id, fixture.name, fixture.status, fixture.config,
  encode(extensions.digest(fixture.config::text, 'sha256'), 'hex'),
  'canonical-v2'
FROM replay_base_config base
CROSS JOIN LATERAL (
  VALUES
    (
      '47000000-0000-0000-0000-000000000010'::uuid,
      'replay-main'::text,
      'replay'::text,
      jsonb_set(base.config, '{replay}',
        '{"contract_version":"adaptive_replay_v1","max_range_days":400,"max_units":50}'::jsonb)
    ),
    (
      '47000000-0000-0000-0000-000000000020'::uuid,
      'replay-missing-replay-config'::text,
      'replay'::text,
      base.config
    ),
    (
      '47000000-0000-0000-0000-000000000030'::uuid,
      'replay-draft-status'::text,
      'draft'::text,
      jsonb_set(base.config, '{replay}',
        '{"contract_version":"adaptive_replay_v1","max_range_days":400,"max_units":50}'::jsonb)
    ),
    (
      '47000000-0000-0000-0000-000000000040'::uuid,
      'replay-small-range'::text,
      'replay'::text,
      jsonb_set(base.config, '{replay}',
        '{"contract_version":"adaptive_replay_v1","max_range_days":1,"max_units":50}'::jsonb)
    ),
    (
      '47000000-0000-0000-0000-000000000050'::uuid,
      'replay-small-units'::text,
      'replay'::text,
      jsonb_set(base.config, '{replay}',
        '{"contract_version":"adaptive_replay_v1","max_range_days":400,"max_units":1}'::jsonb)
    )
) AS fixture(id, name, status, config);

-- Users: A (candidate_only_proxy), B (both_proxy + duplicate-alert dedupe),
-- C (unreplayable: no subject context ever captured for it).
INSERT INTO auth.users (id, email, aud, role)
VALUES
  ('47000000-0000-0000-0000-000000000001', 'replay-a@example.invalid', 'authenticated', 'authenticated'),
  ('47000000-0000-0000-0000-000000000002', 'replay-b@example.invalid', 'authenticated', 'authenticated'),
  ('47000000-0000-0000-0000-000000000003', 'replay-c@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

-- Persisted as-of subject context for A and B only; C intentionally has none.
INSERT INTO public.alert_judgment_subject_contexts (
  id, version_id, user_id, effective_from, effective_to,
  raw_sensitivity, canonical_sensitivity, routine_mode,
  timezone, utc_offset_minutes, settings_updated_at, settings_provenance,
  captured_at, config_sha256, evidence_version, subject_context_sha256
)
SELECT
  fixture.id, version.id, fixture.user_id,
  '2026-07-01 00:00+00', '2026-08-01 00:00+00',
  'high', 'high', 'regular_9to5', 'UTC', 0,
  '2026-06-30 23:00+00',
  jsonb_build_object('source', 'replay-test'),
  '2026-07-01 00:00+00',
  version.config_sha256, version.evidence_version, repeat('0', 64)
FROM public.alert_model_versions version
CROSS JOIN LATERAL (
  VALUES
    ('47100000-0000-0000-0000-000000000001'::uuid, '47000000-0000-0000-0000-000000000001'::uuid),
    ('47100000-0000-0000-0000-000000000002'::uuid, '47000000-0000-0000-0000-000000000002'::uuid)
) AS fixture(id, user_id)
WHERE version.id = '47000000-0000-0000-0000-000000000010';

UPDATE public.alert_judgment_subject_contexts context
SET subject_context_sha256 = encode(extensions.digest(jsonb_build_object(
  'version_id', context.version_id,
  'user_id', context.user_id,
  'effective_from_utc',
    to_char(context.effective_from AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'effective_to_utc',
    CASE WHEN context.effective_to IS NULL THEN NULL
      ELSE to_char(context.effective_to AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    END,
  'raw_sensitivity', context.raw_sensitivity,
  'canonical_sensitivity', context.canonical_sensitivity,
  'routine_mode', context.routine_mode,
  'timezone', context.timezone,
  'utc_offset_minutes', context.utc_offset_minutes,
  'settings_updated_at_utc',
    to_char(context.settings_updated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'settings_provenance', context.settings_provenance,
  'captured_at_utc',
    to_char(context.captured_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'config_sha256', context.config_sha256,
  'evidence_version', context.evidence_version
)::text, 'sha256'), 'hex')
WHERE context.version_id = '47000000-0000-0000-0000-000000000010';

-- Coverage intervals qualifying each user's single overnight session.
INSERT INTO public.alert_observation_coverage_intervals (
  version_id, user_id, starts_at, ends_at, timezone, utc_offset_minutes,
  activity_coverage_state, intervention_coverage_state, sleep_context_state,
  captured_at, finalized_at, evidence_version, provenance_sha256
)
SELECT '47000000-0000-0000-0000-000000000010', fixture.user_id,
  '2026-07-10 20:00+00', '2026-07-11 07:59:00+00', 'UTC', 0,
  'valid', 'valid', 'valid',
  '2026-07-10 19:00+00', '2026-07-11 07:59:00+00', 'canonical-v2',
  repeat(fixture.hash_char, 64)
FROM (
  VALUES
    ('47000000-0000-0000-0000-000000000001'::uuid, '1'),
    ('47000000-0000-0000-0000-000000000002'::uuid, '2')
) AS fixture(user_id, hash_char);

-- Raw canonical-v2 pings drive both the Task 3 qualified session (via
-- coverage above) and Task 7's own independent raw-gap sessionization.
-- A/B: one ping ends the observed session at 22:30, a later ping the next
-- morning opens a new session, so next_start=08:00 becomes the replay unit
-- boundary. C has the same shape one day later but no subject context.
INSERT INTO public.behavior_pings (user_id, kind, at, received_at, ingest_version)
VALUES
  ('47000000-0000-0000-0000-000000000001', 'app', '2026-07-10 22:30:00+00', '2026-07-10 22:30:00+00', 2),
  ('47000000-0000-0000-0000-000000000001', 'app', '2026-07-11 08:00:00+00', '2026-07-11 08:00:00+00', 2),
  ('47000000-0000-0000-0000-000000000002', 'app', '2026-07-10 22:30:00+00', '2026-07-10 22:30:00+00', 2),
  ('47000000-0000-0000-0000-000000000002', 'app', '2026-07-11 08:00:00+00', '2026-07-11 08:00:00+00', 2),
  ('47000000-0000-0000-0000-000000000003', 'app', '2026-07-12 22:30:00+00', '2026-07-12 22:30:00+00', 2),
  ('47000000-0000-0000-0000-000000000003', 'app', '2026-07-13 08:00:00+00', '2026-07-13 08:00:00+00', 2);

-- A: one unmatched silence alert (outside A's gap) and one dark_device
-- alert inside A's gap (must never count as a matched silence proxy).
-- B: two silence alerts inside the same gap (dedupe to one matched unit,
-- but live_alert_rows_observed sums the raw count).
INSERT INTO public.alerts (
  user_id, cause, stage, status, opened_at, stage_entered_at, resolved_at, resolved_by
)
VALUES
  ('47000000-0000-0000-0000-000000000001', 'silence', 'self', 'resolved',
    '2026-07-10 10:00:00+00', '2026-07-10 10:00:00+00', '2026-07-10 10:05:00+00',
    '47000000-0000-0000-0000-000000000001'),
  ('47000000-0000-0000-0000-000000000001', 'dark_device', 'self', 'resolved',
    '2026-07-11 02:00:00+00', '2026-07-11 02:00:00+00', '2026-07-11 02:05:00+00',
    '47000000-0000-0000-0000-000000000001'),
  ('47000000-0000-0000-0000-000000000002', 'silence', 'self', 'resolved',
    '2026-07-10 23:00:00+00', '2026-07-10 23:00:00+00', '2026-07-10 23:05:00+00',
    '47000000-0000-0000-0000-000000000002'),
  ('47000000-0000-0000-0000-000000000002', 'silence', 'self', 'resolved',
    '2026-07-11 01:00:00+00', '2026-07-11 01:00:00+00', '2026-07-11 01:05:00+00',
    '47000000-0000-0000-0000-000000000002');

-- Preflight failures raise before any evaluation or write.
SELECT throws_ok(
  $$ SELECT private.run_alert_judgment_replay(
    '47000000-0000-0000-0000-000000000010', '2026-07-14 00:00+00', '2026-07-10 00:00+00'
  ) $$,
  'P0001',
  'adaptive_alert_replay_invalid_range',
  'from must be strictly less than to raises'
);
SELECT throws_ok(
  $$ SELECT private.run_alert_judgment_replay(
    '47000000-0000-0000-0000-000000000030', '2026-07-10 00:00+00', '2026-07-14 00:00+00'
  ) $$,
  'P0001',
  'adaptive_alert_replay_invalid_version_status',
  'a non-replay (draft) version status raises'
);
SELECT throws_ok(
  $$ SELECT private.run_alert_judgment_replay(
    '47000000-0000-0000-0000-000000000020', '2026-07-10 00:00+00', '2026-07-14 00:00+00'
  ) $$,
  'P0001',
  'adaptive_alert_replay_invalid_replay_config',
  'a version with no replay config section raises'
);
SELECT throws_ok(
  $$ SELECT private.run_alert_judgment_replay(
    '47000000-0000-0000-0000-000000000040', '2026-07-10 00:00+00', '2026-07-14 00:00+00'
  ) $$,
  'P0001',
  'adaptive_alert_replay_range_exceeds_max_range_days',
  'a range exceeding replay.max_range_days raises'
);
SELECT throws_ok(
  $$ SELECT private.run_alert_judgment_replay(
    '47000000-0000-0000-0000-000000000050', '2026-07-10 00:00+00', '2026-07-14 00:00+00'
  ) $$,
  'P0001',
  'adaptive_alert_replay_max_units_exceeded',
  'exceeding replay.max_units raises before any write'
);

-- No live write before the partial run: only the aggregate evaluation table
-- may change. Snapshot live tables, run replay, and prove they are stable.
CREATE TEMP TABLE replay_live_snapshot_before AS
SELECT
  (SELECT count(*) FROM public.alerts) AS alerts_count,
  (SELECT count(*) FROM public.alert_events) AS alert_events_count,
  (SELECT count(*) FROM public.behavior_pings) AS pings_count;

SELECT results_eq(
  $$
    SELECT
      result ->> 'report_status',
      (result ->> 'evaluated_count')::integer,
      (result ->> 'replayable_count')::integer,
      (result ->> 'unreplayable_count')::integer,
      result -> 'unreplayable_reason_counts',
      (result ->> 'replayable_completed_gap_count')::integer,
      (result ->> 'live_alert_rows_observed')::integer,
      (result ->> 'unmatched_live_silence_alert_rows')::integer,
      (result ->> 'candidate_would_alert_gaps')::integer,
      (result ->> 'proxy_denominator_replayable_gaps')::integer,
      (result ->> 'both_proxy')::integer,
      (result ->> 'live_only_proxy')::integer,
      (result ->> 'candidate_only_proxy')::integer,
      (result ->> 'neither_proxy')::integer,
      (result ->> 'threshold_delta_denominator_replayable_gaps')::integer,
      round((result ->> 'median_candidate_minus_adr0022_threshold_proxy_minutes')::numeric, 2),
      round((result ->> 'p95_candidate_minus_adr0022_threshold_proxy_minutes')::numeric, 2),
      result -> 'basis_counts',
      result -> 'quality_counts',
      result -> 'cap_reason_counts',
      (result ->> 'adjudicated_risk_outcomes')::integer,
      (result ->> 'unadjudicated_replayable_count')::integer,
      result ->> 'safety_claim',
      (result ->> 'promotion_eligible')::boolean
    FROM (SELECT private.run_alert_judgment_replay(
      '47000000-0000-0000-0000-000000000010',
      '2026-07-10 00:00+00', '2026-07-14 00:00+00'
    ) AS result) evaluated
  $$,
  $$ VALUES (
    'partial'::text, 3, 2, 1,
    '{"missing_subject_context":1}'::jsonb,
    2, 2, 1, 2, 2, 1, 0, 1, 0, 2,
    0.00::numeric, 0.00::numeric,
    '{"deterministic_emergency":2}'::jsonb,
    '{"low_support":2}'::jsonb,
    '{"emergency_exempt":2}'::jsonb,
    0, 2, 'not_evaluated'::text, false
  ) $$,
  'partial replay counts, 2x2 proxy dedupe, dark-device exclusion, and hard non-promotion match exactly'
);
SELECT ok(
  (
    SELECT metrics::text NOT LIKE '%47000000-0000-0000-0000-000000000001%'
      AND metrics::text NOT LIKE '%47000000-0000-0000-0000-000000000002%'
      AND metrics::text NOT LIKE '%"user_id"%'
      AND metrics::text NOT LIKE '%"alert_id"%'
    FROM public.alert_judgment_evaluations
    WHERE version_id = '47000000-0000-0000-0000-000000000010'
      AND evaluation_kind = 'historical_replay'
      AND evaluated_from = '2026-07-10 00:00+00'
      AND evaluated_to = '2026-07-14 00:00+00'
  ),
  'stored aggregate metrics contain no user UUID, alert id, user_id key, or per-user object'
);

SELECT results_eq(
  $$
    SELECT alerts_count, alert_events_count, pings_count
    FROM replay_live_snapshot_before
  $$,
  $$
    SELECT
      (SELECT count(*) FROM public.alerts),
      (SELECT count(*) FROM public.alert_events),
      (SELECT count(*) FROM public.behavior_pings)
  $$,
  'replay performs no live alert, event, or ping write'
);

-- Empty, all_unreplayable, complete, and the half-open next_start<_to
-- boundary are each distinct and exact.
SELECT is(
  (private.run_alert_judgment_replay(
    '47000000-0000-0000-0000-000000000010',
    '2030-01-01 00:00+00', '2030-01-02 00:00+00'
  ) ->> 'report_status'),
  'empty',
  'a range with zero enumerated units reports empty, not zero-with-NaN'
);
SELECT is(
  (private.run_alert_judgment_replay(
    '47000000-0000-0000-0000-000000000010',
    '2026-07-12 00:00+00', '2026-07-14 00:00+00'
  ) ->> 'report_status'),
  'all_unreplayable',
  'a range covering only user C reports all_unreplayable'
);
SELECT is(
  (private.run_alert_judgment_replay(
    '47000000-0000-0000-0000-000000000010',
    '2026-07-10 00:00+00', '2026-07-12 00:00+00'
  ) ->> 'report_status'),
  'complete',
  'a range covering only users A and B reports complete'
);
SELECT is(
  (private.run_alert_judgment_replay(
    '47000000-0000-0000-0000-000000000010',
    '2026-07-10 00:00+00', '2026-07-11 08:00:00+00'
  ) ->> 'evaluated_count')::integer,
  0,
  'next_start exactly equal to _to is excluded by the half-open range'
);

-- Idempotency: running the same fixture/version/range twice must not
-- duplicate the aggregate row, change its created_at, or change its output.
CREATE TEMP TABLE replay_idempotency_first AS
SELECT
  private.run_alert_judgment_replay(
    '47000000-0000-0000-0000-000000000010',
    '2026-07-10 00:00+00', '2026-07-12 00:00+00'
  ) AS result,
  (
    SELECT created_at FROM public.alert_judgment_evaluations
    WHERE version_id = '47000000-0000-0000-0000-000000000010'
      AND evaluation_kind = 'historical_replay'
      AND evaluated_from = '2026-07-10 00:00+00'
      AND evaluated_to = '2026-07-12 00:00+00'
  ) AS created_at;

CREATE TEMP TABLE replay_idempotency_second AS
SELECT
  private.run_alert_judgment_replay(
    '47000000-0000-0000-0000-000000000010',
    '2026-07-10 00:00+00', '2026-07-12 00:00+00'
  ) AS result,
  (
    SELECT created_at FROM public.alert_judgment_evaluations
    WHERE version_id = '47000000-0000-0000-0000-000000000010'
      AND evaluation_kind = 'historical_replay'
      AND evaluated_from = '2026-07-10 00:00+00'
      AND evaluated_to = '2026-07-12 00:00+00'
  ) AS created_at;

SELECT is(
  (SELECT result FROM replay_idempotency_second)::text,
  (SELECT result FROM replay_idempotency_first)::text,
  'the identical fixture/version/range replay run twice returns byte-identical aggregate JSON'
);
SELECT is(
  (SELECT created_at FROM replay_idempotency_second),
  (SELECT created_at FROM replay_idempotency_first),
  'a duplicate run never advances created_at on the aggregate row'
);
SELECT is(
  (
    SELECT count(*)::integer FROM public.alert_judgment_evaluations
    WHERE version_id = '47000000-0000-0000-0000-000000000010'
      AND evaluation_kind = 'historical_replay'
      AND evaluated_from = '2026-07-10 00:00+00'
      AND evaluated_to = '2026-07-12 00:00+00'
  ),
  1,
  'exactly one aggregate row exists per (version, kind, from, to) after two runs'
);
SELECT is(
  (
    SELECT promotion_eligible FROM public.alert_judgment_evaluations
    WHERE version_id = '47000000-0000-0000-0000-000000000010'
      AND evaluation_kind = 'historical_replay'
      AND evaluated_from = '2026-07-10 00:00+00'
      AND evaluated_to = '2026-07-12 00:00+00'
  ),
  false,
  'the persisted row hard-pins promotion_eligible=false regardless of proxy metrics'
);

CREATE TEMP TABLE replay_guc_baseline AS
SELECT private.run_alert_judgment_replay(
  '47000000-0000-0000-0000-000000000010',
  '2026-07-10 00:00+00', '2026-07-12 00:00+00'
) AS result;
SET LOCAL TimeZone = 'Pacific/Chatham';
SET LOCAL "DateStyle" = 'Postgres, DMY';
SET LOCAL extra_float_digits = -15;
CREATE TEMP TABLE replay_guc_extreme AS
SELECT private.run_alert_judgment_replay(
  '47000000-0000-0000-0000-000000000010',
  '2026-07-10 00:00+00', '2026-07-12 00:00+00'
) AS result;
SET LOCAL TimeZone = 'UTC';
SET LOCAL "DateStyle" = 'ISO, YMD';
SET LOCAL extra_float_digits = 3;
SELECT is(
  (SELECT result::text FROM replay_guc_extreme),
  (SELECT result::text FROM replay_guc_baseline),
  'caller TimeZone, DateStyle, and extra_float_digits cannot change replay output or hashes'
);

CREATE TEMP TABLE replay_mutable_baseline AS
SELECT private.run_alert_judgment_replay(
  '47000000-0000-0000-0000-000000000010',
  '2026-07-10 00:00+00', '2026-07-12 00:00+00'
) AS result;
UPDATE public.profiles
SET routine_pattern = 'shift_irregular'
WHERE id IN (
  '47000000-0000-0000-0000-000000000001',
  '47000000-0000-0000-0000-000000000002'
);
INSERT INTO public.user_settings (user_id, sensitivity, timezone)
VALUES
  ('47000000-0000-0000-0000-000000000001', 'low', 'Asia/Tokyo'),
  ('47000000-0000-0000-0000-000000000002', 'low', 'Asia/Tokyo')
ON CONFLICT (user_id) DO UPDATE
SET sensitivity = EXCLUDED.sensitivity,
    timezone = EXCLUDED.timezone;
SELECT is(
  private.run_alert_judgment_replay(
    '47000000-0000-0000-0000-000000000010',
    '2026-07-10 00:00+00', '2026-07-12 00:00+00'
  )::text,
  (SELECT result::text FROM replay_mutable_baseline),
  'current mutable Routine mode, sensitivity, and timezone do not rewrite historical replay'
);

-- Hash contract sanity: both stored hashes are canonical hex, distinct from
-- each other, and the input hash actually varies with the enumerated unit
-- set (not a constant placeholder).
SELECT ok(
  (
    SELECT input_sha256 ~ '^[a-f0-9]{64}$' AND output_sha256 ~ '^[a-f0-9]{64}$'
    FROM public.alert_judgment_evaluations
    WHERE version_id = '47000000-0000-0000-0000-000000000010'
      AND evaluation_kind = 'historical_replay'
      AND evaluated_from = '2026-07-10 00:00+00'
      AND evaluated_to = '2026-07-12 00:00+00'
  ),
  'input_sha256 and output_sha256 are canonical lowercase hex-64'
);
SELECT isnt(
  (
    SELECT input_sha256 FROM public.alert_judgment_evaluations
    WHERE version_id = '47000000-0000-0000-0000-000000000010'
      AND evaluation_kind = 'historical_replay'
      AND evaluated_from = '2026-07-10 00:00+00'
      AND evaluated_to = '2026-07-12 00:00+00'
  ),
  (
    SELECT output_sha256 FROM public.alert_judgment_evaluations
    WHERE version_id = '47000000-0000-0000-0000-000000000010'
      AND evaluation_kind = 'historical_replay'
      AND evaluated_from = '2026-07-10 00:00+00'
      AND evaluated_to = '2026-07-12 00:00+00'
  ),
  'output_sha256 binds finalized metrics on top of input_sha256, not a copy of it'
);

SELECT isnt(
  (
    private.run_alert_judgment_replay(
      '47000000-0000-0000-0000-000000000010', '2026-07-10 00:00+00', '2026-07-12 00:00+00'
    ) ->> 'input_sha256'
  ),
  (
    private.run_alert_judgment_replay(
      '47000000-0000-0000-0000-000000000010', '2026-07-12 00:00+00', '2026-07-14 00:00+00'
    ) ->> 'input_sha256'
  ),
  'a different enumerated unit set produces a different input_sha256'
);

SELECT has_function(
  'private', 'replay_config_is_valid', ARRAY['jsonb'],
  'the raw-type-first replay config gate exists'
);
SELECT results_eq(
  $$
    SELECT
      private.replay_config_is_valid(
        (SELECT config FROM public.alert_model_versions
         WHERE id = '47000000-0000-0000-0000-000000000010')
      ),
      private.replay_config_is_valid(
        (SELECT config FROM public.alert_model_versions
         WHERE id = '47000000-0000-0000-0000-000000000020')
      ),
      private.replay_config_is_valid(jsonb_set(
        (SELECT config FROM replay_base_config),
        '{replay,max_units}', '"100"'::jsonb
      )),
      private.replay_config_is_valid(jsonb_set(
        (SELECT config FROM replay_base_config),
        '{replay,max_units}', '1.5'::jsonb
      )),
      private.replay_config_is_valid(jsonb_set(
        (SELECT config FROM replay_base_config),
        '{replay,max_units}', '2147483648'::jsonb
      )),
      private.replay_config_is_valid(jsonb_set(
        (SELECT config FROM replay_base_config),
        '{replay,max_range_days}', '{}'::jsonb
      ))
  $$,
  $$ VALUES (true, false, false, false, false, false) $$,
  'raw-type-first replay config accepts the contract and rejects missing, string, fractional, overflow, and object limits without cast errors'
);

SELECT results_eq(
  $$
    SELECT input_sha256, output_sha256
    FROM public.alert_judgment_evaluations
    WHERE version_id = '47000000-0000-0000-0000-000000000010'
      AND evaluation_kind = 'historical_replay'
      AND evaluated_from = '2026-07-10 00:00+00'
      AND evaluated_to = '2026-07-12 00:00+00'
  $$,
  $$
    VALUES (
      '3a297cdf808840972909a1c0426fe3bbe4a6e67aeca3d68ece4c32589e40a63a'::text,
      '2eb3a5de8ffb9532ad7c6e698fc3b763b31054f82abc228f8dfccb14adf67314'::text
    )
  $$,
  'stable replay fixture matches the locked golden input and output hashes'
);

SELECT * FROM finish();
ROLLBACK;
