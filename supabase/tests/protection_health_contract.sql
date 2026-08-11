-- ADR-0039 · When the app can no longer watch over someone, it must say so.
--
-- Quiet is exactly what this app looks like when everything is fine, which is
-- why a silent failure is the most expensive one it can have. Every assertion
-- below defends one of three rules: ready needs evidence, acknowledgement is
-- not recovery, and an outage never becomes a personal alert.
BEGIN;

SELECT plan(12);

INSERT INTO auth.users (id, email, aud, role) VALUES
  ('56000000-0000-4000-8000-000000000001', 'health-a@example.invalid', 'authenticated', 'authenticated'),
  ('56000000-0000-4000-8000-000000000002', 'health-b@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, display_name) VALUES
  ('56000000-0000-4000-8000-000000000001', 'Health A'),
  ('56000000-0000-4000-8000-000000000002', 'Health B')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

WITH health_config AS (
  SELECT '{
  "sessionization":{"gap_minutes":30,"per_user_day_gap_cap":8,"training_horizon_days":30,"intervention_window_minutes":30},
  "context":{"definition_version":"health-v1","day_partition":"all_days","hour_bucket_minutes":60},
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
  '56100000-0000-4000-8000-000000000001',
  'protection-health-fixture', 'shadow', value,
  encode(extensions.digest(value::text, 'sha256'), 'hex'),
  'canonical-v2', now() - interval '30 days'
FROM health_config;

SELECT set_config('request.jwt.claim.sub', '56000000-0000-4000-8000-000000000001', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);

-- 1: nothing known. The absence of bad news must not read as good news.
SELECT is(
  (SELECT state FROM public.my_protection_health()),
  'unknown',
  'an account we have never covered is unknown, never ready'
);

-- 2: positive evidence, and only then, ready.
INSERT INTO public.alert_observation_coverage_intervals (
  version_id, user_id, starts_at, ends_at, timezone, utc_offset_minutes,
  activity_coverage_state, intervention_coverage_state, sleep_context_state,
  captured_at, evidence_version, provenance_sha256
) VALUES (
  '56100000-0000-4000-8000-000000000001',
  '56000000-0000-4000-8000-000000000001',
  now() - interval '8 hours', now() - interval '1 hour', 'UTC', 0,
  'valid', 'valid', 'valid',
  now() - interval '1 hour', 'canonical-v2', repeat('a', 64)
);

SELECT is(
  (SELECT state FROM public.my_protection_health()),
  'ready',
  'recent continuous valid coverage is what ready means'
);

-- 3: coverage that is merely old is not coverage now.
RESET ROLE;
UPDATE public.alert_observation_coverage_intervals
SET starts_at = now() - interval '5 days',
    ends_at = now() - interval '4 days',
    captured_at = now() - interval '4 days'
WHERE user_id = '56000000-0000-4000-8000-000000000001';

SELECT is(
  (SELECT state FROM public.my_protection_health()),
  'unknown',
  'coverage that has gone stale returns the account to unknown'
);

-- 4: the server opens an incident, and the state becomes visibly limited.
SELECT is(
  (SELECT private.evaluate_protection_health(
     '56000000-0000-4000-8000-000000000001') ->> 'action'),
  'opened',
  'stale coverage opens a protection health incident'
);

SELECT is(
  (SELECT state FROM public.my_protection_health()),
  'limited',
  'an open incident is shown as limited, not left quiet'
);

-- 6..8: acknowledgement is not recovery.
SELECT lives_ok(
  $$ SELECT public.acknowledge_protection_health() $$,
  'the subject can dismiss the prompt'
);

SELECT is(
  (SELECT state FROM public.my_protection_health()),
  'limited',
  'dismissing the prompt does not restore protection; the state stays limited'
);

SELECT ok(
  (SELECT acknowledged_at IS NOT NULL AND recovered_at IS NULL AND closed_at IS NULL
   FROM public.protection_health_incidents
   WHERE user_id = '56000000-0000-4000-8000-000000000001'),
  'acknowledgement is recorded separately and recovery is left untouched'
);

-- 9..10: only real new coverage recovers, and it must carry its evidence.
INSERT INTO public.alert_observation_coverage_intervals (
  version_id, user_id, starts_at, ends_at, timezone, utc_offset_minutes,
  activity_coverage_state, intervention_coverage_state, sleep_context_state,
  captured_at, evidence_version, provenance_sha256
) VALUES (
  '56100000-0000-4000-8000-000000000001',
  '56000000-0000-4000-8000-000000000001',
  now() - interval '3 hours', now() - interval '10 minutes', 'UTC', 0,
  'valid', 'valid', 'valid',
  now() - interval '10 minutes', 'canonical-v2', repeat('b', 64)
);

SELECT is(
  (SELECT private.evaluate_protection_health(
     '56000000-0000-4000-8000-000000000001') ->> 'action'),
  'recovered',
  'fresh continuous valid coverage is what recovery requires'
);

SELECT ok(
  (SELECT recovered_at IS NOT NULL AND recovery_evidence IS NOT NULL
   FROM public.protection_health_incidents
   WHERE user_id = '56000000-0000-4000-8000-000000000001'),
  'a recovery is recorded together with the evidence that recovered it'
);

-- 11: the whole path is technical. It never manufactures a personal emergency.
SELECT is(
  (SELECT count(*)::integer FROM public.alerts
   WHERE user_id = '56000000-0000-4000-8000-000000000001'),
  0,
  'a coverage outage never becomes a personal alert'
);

-- 12: health is owner-scoped, and incident maintenance is not a client power.
SELECT ok(
  NOT has_function_privilege(
    'authenticated', 'private.evaluate_protection_health(uuid)', 'EXECUTE'
  ),
  'no client can open or close another account''s protection incident'
);

SELECT * FROM finish();
ROLLBACK;
