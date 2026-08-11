-- ADR-0039 / ADR-0040 rev.1 · iOS reports coverage, on honest terms.
--
-- iOS reaches Android's median cadence with a much heavier tail, so what
-- matters is not that it reports but that a long gap between reports is not
-- quietly counted as coverage. Measured: iOS p50 15.0 min, p90 40-76 min,
-- p95 89-187 min against Android's p95 of 18.9.
BEGIN;

SELECT plan(9);

INSERT INTO auth.users (id, email, aud, role) VALUES
  ('59000000-0000-4000-8000-000000000001', 'ios-cov@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, display_name)
VALUES ('59000000-0000-4000-8000-000000000001', 'iOS coverage')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

INSERT INTO public.clients (user_id, client_id, platform, app_version, first_seen_at, last_seen_at)
VALUES ('59000000-0000-4000-8000-000000000001', 'ios-cov-client', 'ios-app', '0.5.26',
        now() - interval '3 days', now() - interval '5 minutes')
ON CONFLICT (user_id, client_id) DO UPDATE SET platform = EXCLUDED.platform;

-- ADR-0028: a fresh base ships the shadow runtime switched off, so this test
-- owns its own activation. Without it every call below returns 'disabled' and
-- the assertions pass over a system that did nothing.
UPDATE private.adaptive_alert_shadow_runtime_config
SET enabled = true, accept_coverage_leases = true
WHERE singleton;

CREATE TEMP TABLE ios_base_config AS
SELECT '{
  "sessionization":{
    "gap_minutes":30,
    "per_user_day_gap_cap":8,
    "training_horizon_days":30,
    "intervention_window_minutes":30
  },
  "context":{
    "definition_version":"candidate-eval-v1",
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
    "expected_live_definition_sha256":"c3efc6cc664dc334166a034651ff584d4c7766d80775c3fe3bc012eb97a9b150"
  }
}'::jsonb AS config;

-- The finalizer reads its version from the runtime config, and a fresh base
-- leaves that unset, so the fixture supplies one and points the config at it.
INSERT INTO public.alert_model_versions
  (id, name, status, config, config_sha256, evidence_version, shadow_enabled_at)
SELECT '59100000-0000-4000-8000-000000000001', 'ios-coverage-fixture', 'shadow',
       config, encode(extensions.digest(config::text, 'sha256'), 'hex'),
       'canonical-v2', now() - interval '30 days'
FROM ios_base_config;

UPDATE private.adaptive_alert_shadow_runtime_config
SET version_id = '59100000-0000-4000-8000-000000000001'
WHERE singleton;

-- 1: the channel is accepted at all.
SELECT is(
  private.record_alert_shadow_coverage_lease_core(
    '59000000-0000-4000-8000-000000000001', 'ios-cov-client', 'ios-app',
    'ios-wake-v1', 'operational', repeat('a', 64), now(), gen_random_uuid()
  ),
  'inserted',
  'an iOS wake lease is accepted'
);

-- 2: paired with the wrong collector contract it is not.
SELECT is(
  private.record_alert_shadow_coverage_lease_core(
    '59000000-0000-4000-8000-000000000001', 'ios-cov-client', 'ios-app',
    'android-passive-v1', 'operational', repeat('a', 64), now(), gen_random_uuid()
  ),
  'unsupported',
  'an iOS lease carrying another collector''s contract is refused'
);

-- 3: a channel whose platform does not match the registered client is refused,
-- which is the check that silently swallowed every desktop lease for a week.
UPDATE public.clients SET platform = 'ios-web'
WHERE user_id = '59000000-0000-4000-8000-000000000001';

SELECT is(
  private.record_alert_shadow_coverage_lease_core(
    '59000000-0000-4000-8000-000000000001', 'ios-cov-client', 'ios-app',
    'ios-wake-v1', 'operational', repeat('a', 64), now(), gen_random_uuid()
  ),
  'capability_mismatch',
  'a lease is refused when the client is not registered on that platform'
);

UPDATE public.clients SET platform = 'ios-app'
WHERE user_id = '59000000-0000-4000-8000-000000000001';

-- 4: a web channel is still not a collector.
SELECT is(
  private.record_alert_shadow_coverage_lease_core(
    '59000000-0000-4000-8000-000000000001', 'ios-cov-client', 'ios-pwa',
    'ios-wake-v1', 'operational', repeat('a', 64), now(), gen_random_uuid()
  ),
  'unsupported',
  'a channel with no background collector cannot lease coverage'
);

-- 5..8: the interval builder must not stretch a wake into coverage it did not
-- observe. Two leases 20 minutes apart are within the 35-minute allowance; two
-- 90 minutes apart are not, and the span between them is unknown, not valid.
DELETE FROM private.alert_shadow_coverage_leases
WHERE user_id = '59000000-0000-4000-8000-000000000001';
DELETE FROM public.alert_observation_coverage_intervals
WHERE user_id = '59000000-0000-4000-8000-000000000001';

INSERT INTO private.alert_shadow_coverage_leases
  (user_id, event_id, client_id, channel, collector_contract, collector_state,
   capability_sha256, observed_at, received_at, app_version, timezone, utc_offset_minutes)
SELECT '59000000-0000-4000-8000-000000000001', gen_random_uuid(), 'ios-cov-client',
       'ios-app', 'ios-wake-v1', 'operational', repeat('a', 64),
       now() - offset_minutes * interval '1 minute',
       now() - offset_minutes * interval '1 minute',
       '0.5.26', 'UTC', 0
FROM unnest(ARRAY[200, 180, 90, 70]) AS offset_minutes;

SELECT lives_ok(
  $$SELECT private.finalize_alert_shadow_coverage(
      '59000000-0000-4000-8000-000000000001', now(), 35)$$,
  'the finalizer builds intervals from iOS leases'
);

SELECT is(
  (SELECT count(*)::int FROM public.alert_observation_coverage_intervals
   WHERE user_id = '59000000-0000-4000-8000-000000000001'
     AND activity_coverage_state = 'valid'),
  2,
  'two twenty-minute gaps count as observed coverage'
);

SELECT is(
  (SELECT count(*)::int FROM public.alert_observation_coverage_intervals
   WHERE user_id = '59000000-0000-4000-8000-000000000001'
     AND activity_coverage_state = 'unknown'),
  1,
  'the ninety-minute gap is unknown, not stretched into coverage'
);

SELECT is(
  (SELECT count(*)::int FROM public.alert_observation_coverage_intervals
   WHERE user_id = '59000000-0000-4000-8000-000000000001'
     AND activity_coverage_state = 'unknown'
     AND (intervention_coverage_state <> 'unknown' OR sleep_context_state <> 'unknown')),
  0,
  'an unknown span is unknown on every axis, not just the activity one'
);

-- 9: and iOS now counts as a platform whose silence means something.
SELECT is(
  private.coverage_capable_subject('59000000-0000-4000-8000-000000000001'),
  true,
  'an iOS install is a platform whose protection health can be judged'
);

SELECT * FROM finish();
ROLLBACK;
