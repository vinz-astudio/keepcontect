-- A row that carries its own integrity digest must never disagree with itself.
--
-- Every downstream guard trusts config_sha256: the shadow cycle refuses to run
-- when it does not match. A migration that edits `config` and forgets the digest
-- therefore does not fail loudly at write time — it fails later, inside a
-- fail-closed guard, and looks exactly like the outage it is not.
BEGIN;

SELECT plan(3);

-- 1: whatever is stored right now is self-consistent.
SELECT is(
  (SELECT count(*)::integer FROM public.alert_model_versions
   WHERE config_sha256 IS DISTINCT FROM encode(extensions.digest(config::text, 'sha256'), 'hex')),
  0,
  'every stored model version agrees with its own config digest'
);

-- 2..3: and the assertion actually bites. Insert a row whose digest is wrong on
-- purpose, prove the check catches it, then prove the repair expression fixes it.
INSERT INTO auth.users (id, email, aud, role)
VALUES ('58000000-0000-4000-8000-000000000001', 'sha-integrity@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

WITH integrity_config AS (
  SELECT '{
  "sessionization":{"gap_minutes":30,"per_user_day_gap_cap":8,"training_horizon_days":30,"intervention_window_minutes":30},
  "context":{"definition_version":"sha-integrity-v1","day_partition":"all_days","hour_bucket_minutes":60},
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
  '58100000-0000-4000-8000-000000000001',
  'sha-integrity-fixture', 'shadow', value,
  repeat('f', 64),
  'canonical-v2', now() - interval '1 day'
FROM integrity_config;

SELECT is(
  (SELECT count(*)::integer FROM public.alert_model_versions
   WHERE config_sha256 IS DISTINCT FROM encode(extensions.digest(config::text, 'sha256'), 'hex')),
  1,
  'a row whose digest was not recomputed after a config edit is detected'
);

UPDATE public.alert_model_versions
SET config_sha256 = encode(extensions.digest(config::text, 'sha256'), 'hex')
WHERE config_sha256 IS DISTINCT FROM encode(extensions.digest(config::text, 'sha256'), 'hex');

SELECT is(
  (SELECT count(*)::integer FROM public.alert_model_versions
   WHERE config_sha256 IS DISTINCT FROM encode(extensions.digest(config::text, 'sha256'), 'hex')),
  0,
  'recomputing the digest restores self-consistency'
);

SELECT * FROM finish();
ROLLBACK;
