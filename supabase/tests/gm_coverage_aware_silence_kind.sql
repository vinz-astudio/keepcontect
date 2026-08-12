BEGIN;

SELECT plan(5);

INSERT INTO auth.users (id, email, aud, role) VALUES
  ('61000000-0000-4000-8000-000000000001', 'gm-coverage-admin@example.invalid', 'authenticated', 'authenticated'),
  ('61000000-0000-4000-8000-000000000002', 'gm-coverage-ios@example.invalid', 'authenticated', 'authenticated'),
  ('61000000-0000-4000-8000-000000000003', 'gm-coverage-android@example.invalid', 'authenticated', 'authenticated'),
  ('61000000-0000-4000-8000-000000000004', 'gm-coverage-expired@example.invalid', 'authenticated', 'authenticated'),
  ('61000000-0000-4000-8000-000000000005', 'gm-coverage-fresh-heartbeat@example.invalid', 'authenticated', 'authenticated'),
  ('61000000-0000-4000-8000-000000000006', 'gm-coverage-no-heartbeat@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, display_name) VALUES
  ('61000000-0000-4000-8000-000000000001', 'GM Coverage Admin'),
  ('61000000-0000-4000-8000-000000000002', 'GM Coverage iOS'),
  ('61000000-0000-4000-8000-000000000003', 'GM Coverage Android'),
  ('61000000-0000-4000-8000-000000000004', 'GM Coverage Expired'),
  ('61000000-0000-4000-8000-000000000005', 'GM Coverage Fresh Heartbeat'),
  ('61000000-0000-4000-8000-000000000006', 'GM Coverage No Heartbeat')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

INSERT INTO public.app_admins (user_id)
VALUES ('61000000-0000-4000-8000-000000000001')
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO public.clients (
  user_id, client_id, platform, app_version, first_seen_at, last_seen_at
) VALUES
  ('61000000-0000-4000-8000-000000000002', 'gm-coverage-ios', 'ios', '0.6.0', now() - interval '7 days', now() - interval '30 minutes'),
  ('61000000-0000-4000-8000-000000000003', 'gm-coverage-android', 'android', '0.6.0', now() - interval '7 days', now() - interval '30 minutes')
ON CONFLICT (user_id, client_id) DO UPDATE
SET platform = EXCLUDED.platform,
    app_version = EXCLUDED.app_version,
    last_seen_at = EXCLUDED.last_seen_at;

INSERT INTO public.device_state (user_id, last_heartbeat_at, updated_at) VALUES
  ('61000000-0000-4000-8000-000000000002', now() - interval '2 days', now() - interval '2 days'),
  ('61000000-0000-4000-8000-000000000003', now() - interval '2 days', now() - interval '2 days'),
  ('61000000-0000-4000-8000-000000000004', now() - interval '2 days', now() - interval '2 days'),
  ('61000000-0000-4000-8000-000000000005', now() - interval '10 minutes', now() - interval '10 minutes')
ON CONFLICT (user_id) DO UPDATE
SET last_heartbeat_at = EXCLUDED.last_heartbeat_at,
    updated_at = EXCLUDED.updated_at;

INSERT INTO public.behavior_pings (
  user_id, kind, at, source, received_at, ingest_version, event_id
) VALUES
  ('61000000-0000-4000-8000-000000000002', 'app', now() - interval '2 days', 'capacitor', now() - interval '2 days', 2, '61100000-0000-4000-8000-000000000002'),
  ('61000000-0000-4000-8000-000000000003', 'app', now() - interval '2 days', 'capacitor', now() - interval '2 days', 2, '61100000-0000-4000-8000-000000000003'),
  ('61000000-0000-4000-8000-000000000004', 'app', now() - interval '2 days', 'capacitor', now() - interval '2 days', 2, '61100000-0000-4000-8000-000000000004'),
  ('61000000-0000-4000-8000-000000000005', 'app', now() - interval '2 days', 'capacitor', now() - interval '2 days', 2, '61100000-0000-4000-8000-000000000005'),
  ('61000000-0000-4000-8000-000000000006', 'app', now() - interval '2 days', 'capacitor', now() - interval '2 days', 2, '61100000-0000-4000-8000-000000000006')
ON CONFLICT (user_id, event_id) WHERE event_id IS NOT NULL DO NOTHING;

WITH model_config AS (
  SELECT '{
    "sessionization":{"gap_minutes":30,"per_user_day_gap_cap":8,"training_horizon_days":30,"intervention_window_minutes":30},
    "context":{"definition_version":"gm-coverage-v1","day_partition":"all_days","hour_bucket_minutes":60},
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
  id, name, status, config, config_sha256, evidence_version
)
SELECT
  '61200000-0000-4000-8000-000000000001',
  'gm-coverage-aware-silence-fixture',
  'replay',
  value,
  encode(extensions.digest(value::text, 'sha256'), 'hex'),
  'canonical-v2'
FROM model_config;

INSERT INTO public.alert_observation_coverage_intervals (
  version_id, user_id, starts_at, ends_at, timezone, utc_offset_minutes,
  activity_coverage_state, intervention_coverage_state, sleep_context_state,
  captured_at, finalized_at, evidence_version, provenance_sha256
) VALUES
  ('61200000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000002', now() - interval '8 hours', now() - interval '30 minutes', 'UTC', 0, 'valid', 'valid', 'valid', now() - interval '30 minutes', now() - interval '30 minutes', 'canonical-v2', repeat('a', 64)),
  ('61200000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000003', now() - interval '8 hours', now() - interval '30 minutes', 'UTC', 0, 'valid', 'valid', 'valid', now() - interval '30 minutes', now() - interval '30 minutes', 'canonical-v2', repeat('b', 64)),
  ('61200000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000004', now() - interval '4 days', now() - interval '3 days', 'UTC', 0, 'valid', 'valid', 'valid', now() - interval '3 days', now() - interval '3 days', 'canonical-v2', repeat('c', 64));

SELECT set_config('request.jwt.claim.sub', '61000000-0000-4000-8000-000000000001', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT item ->> 'silence_kind'
   FROM jsonb_array_elements(public.gm_list_clients()) AS item
   WHERE item ->> 'user_id' = '61000000-0000-4000-8000-000000000002'),
  'person_quiet',
  'recent valid iOS coverage outranks a stale legacy heartbeat'
);

SELECT is(
  (SELECT item ->> 'silence_kind'
   FROM jsonb_array_elements(public.gm_list_clients()) AS item
   WHERE item ->> 'user_id' = '61000000-0000-4000-8000-000000000003'),
  'person_quiet',
  'recent valid Android coverage outranks a stale legacy heartbeat'
);

SELECT is(
  (SELECT item ->> 'silence_kind'
   FROM jsonb_array_elements(public.gm_list_clients()) AS item
   WHERE item ->> 'user_id' = '61000000-0000-4000-8000-000000000004'),
  'device_dark',
  'expired coverage with a stale heartbeat remains device dark'
);

SELECT is(
  (SELECT item ->> 'silence_kind'
   FROM jsonb_array_elements(public.gm_list_clients()) AS item
   WHERE item ->> 'user_id' = '61000000-0000-4000-8000-000000000005'),
  'person_quiet',
  'fresh heartbeat remains the compatibility fallback when coverage is absent'
);

SELECT is(
  (SELECT item ->> 'silence_kind'
   FROM jsonb_array_elements(public.gm_list_clients()) AS item
   WHERE item ->> 'user_id' = '61000000-0000-4000-8000-000000000006'),
  'unknown',
  'no coverage and no heartbeat stays unknown'
);

SELECT * FROM finish();
ROLLBACK;
