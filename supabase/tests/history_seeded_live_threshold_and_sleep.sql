BEGIN;

SELECT plan(10);

INSERT INTO auth.users (id, email, aud, role) VALUES
  ('30730000-0000-4000-8000-000000000001', 'history-live@example.invalid', 'authenticated', 'authenticated'),
  ('30730000-0000-4000-8000-000000000002', 'sleep-grace@example.invalid', 'authenticated', 'authenticated'),
  ('30730000-0000-4000-8000-000000000003', 'history-gm@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, display_name) VALUES
  ('30730000-0000-4000-8000-000000000001', 'History live threshold'),
  ('30730000-0000-4000-8000-000000000002', 'Sleep grace'),
  ('30730000-0000-4000-8000-000000000003', 'History GM')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

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
      "definition_version": "history-live-v1",
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
  id, name, status, config, config_sha256, evidence_version, shadow_enabled_at
)
SELECT
  '30730000-0000-4000-8000-000000000010',
  'history-seeded-live-test',
  'shadow',
  value,
  encode(extensions.digest(value::text, 'sha256'), 'hex'),
  'canonical-v2',
  now() - interval '1 day'
FROM config;

UPDATE private.adaptive_alert_shadow_runtime_config
SET version_id = '30730000-0000-4000-8000-000000000010',
    enabled = true,
    accept_coverage_leases = true,
    consecutive_failures = 0,
    last_failure_code = NULL;

INSERT INTO public.user_settings (
  user_id, sensitivity, timezone, sleep_start_local, sleep_end_local
) VALUES
  ('30730000-0000-4000-8000-000000000001', 'high', 'UTC', NULL, NULL),
  (
    '30730000-0000-4000-8000-000000000002',
    'high',
    'UTC',
    ((now() AT TIME ZONE 'UTC') - interval '9 hours')::time,
    ((now() AT TIME ZONE 'UTC') - interval '1 hour')::time
  )
ON CONFLICT (user_id) DO UPDATE SET
  sensitivity = EXCLUDED.sensitivity,
  timezone = EXCLUDED.timezone,
  sleep_start_local = EXCLUDED.sleep_start_local,
  sleep_end_local = EXCLUDED.sleep_end_local;

INSERT INTO public.alert_gap_profiles (
  version_id, user_id, context_key, through_date,
  neutral_p95_minutes, sample_count, distinct_support_dates,
  support_started_on, support_ended_on, latest_evidence_at,
  quality_state, confidence, profile_sha256, input_sha256,
  config_sha256, evidence_version
)
SELECT
  v.id,
  '30730000-0000-4000-8000-000000000001',
  'personal_global',
  current_date,
  295,
  154,
  20,
  current_date - 20,
  current_date,
  now() - interval '2 days',
  'valid',
  1,
  repeat('a', 64),
  repeat('b', 64),
  v.config_sha256,
  v.evidence_version
FROM public.alert_model_versions AS v
WHERE v.id = '30730000-0000-4000-8000-000000000010';

SELECT is(
  private.silence_threshold('30730000-0000-4000-8000-000000000001'),
  interval '295 minutes',
  'valid retained personal history is the immediate live threshold'
);

INSERT INTO public.behavior_pings (
  user_id, kind, at, source, received_at, ingest_version, event_id
) VALUES
  (
    '30730000-0000-4000-8000-000000000001',
    'app', now() - interval '36 hours', 'app',
    now() - interval '36 hours', 2, gen_random_uuid()
  ),
  (
    '30730000-0000-4000-8000-000000000001',
    'app', now() - interval '28 hours', 'app',
    now() - interval '28 hours', 2, gen_random_uuid()
  );

SELECT is(
  private.silence_threshold('30730000-0000-4000-8000-000000000001'),
  interval '480 minutes',
  'new canonical records extend the retained baseline without claiming coverage'
);

UPDATE public.alert_gap_profiles
SET neutral_p95_minutes = 250,
    latest_evidence_at = now(),
    profile_sha256 = repeat('c', 64),
    input_sha256 = repeat('d', 64)
WHERE version_id = '30730000-0000-4000-8000-000000000010'
  AND user_id = '30730000-0000-4000-8000-000000000001'
  AND context_key = 'personal_global';

SELECT is(
  private.silence_threshold('30730000-0000-4000-8000-000000000001'),
  interval '250 minutes',
  'a newer rebuilt profile replaces the temporary extension'
);

UPDATE public.alert_gap_profiles
SET neutral_p95_minutes = 30,
    profile_sha256 = repeat('e', 64)
WHERE version_id = '30730000-0000-4000-8000-000000000010'
  AND user_id = '30730000-0000-4000-8000-000000000001'
  AND context_key = 'personal_global';

SELECT is(
  private.silence_threshold('30730000-0000-4000-8000-000000000001'),
  interval '90 minutes',
  'personal history can never shorten the fixed high-sensitivity floor'
);

UPDATE public.alert_gap_profiles
SET neutral_p95_minutes = 295,
    quality_state = 'low_support',
    profile_sha256 = repeat('f', 64)
WHERE version_id = '30730000-0000-4000-8000-000000000010'
  AND user_id = '30730000-0000-4000-8000-000000000001'
  AND context_key = 'personal_global';

SELECT is(
  private.silence_threshold('30730000-0000-4000-8000-000000000001'),
  interval '90 minutes',
  'invalid or insufficient history falls back to the fixed template'
);

UPDATE public.alert_gap_profiles
SET quality_state = 'valid',
    neutral_p95_minutes = 590,
    profile_sha256 = repeat('1', 64)
WHERE version_id = '30730000-0000-4000-8000-000000000010'
  AND user_id = '30730000-0000-4000-8000-000000000001'
  AND context_key = 'personal_global';

UPDATE public.user_settings
SET sensitivity = 'low'
WHERE user_id = '30730000-0000-4000-8000-000000000001';

SELECT is(
  private.silence_threshold('30730000-0000-4000-8000-000000000001'),
  interval '600 minutes',
  'personal threshold plus sensitivity buffer remains capped at ten hours'
);

SELECT ok(
  private.sleep_relaxed('30730000-0000-4000-8000-000000000002', now())
  AND NOT private.is_in_sleep_window('30730000-0000-4000-8000-000000000002', now()),
  'fixture is inside post-wake grace but outside the configured sleep window'
);

INSERT INTO public.groups (id, created_by, name)
VALUES (
  '30730000-0000-4000-8000-000000000020',
  '30730000-0000-4000-8000-000000000003',
  'History live sleep test'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.group_members (
  group_id, user_id, role, status, monitored, watching
) VALUES (
  '30730000-0000-4000-8000-000000000020',
  '30730000-0000-4000-8000-000000000002',
  'member',
  'active',
  true,
  true
)
ON CONFLICT (group_id, user_id) DO UPDATE SET
  monitored = true,
  status = 'active';

INSERT INTO public.device_state (user_id, status, last_heartbeat_at)
VALUES (
  '30730000-0000-4000-8000-000000000002',
  'alert',
  now()
)
ON CONFLICT (user_id) DO UPDATE SET
  status = 'alert',
  last_heartbeat_at = now();

INSERT INTO public.behavior_pings (
  user_id, kind, at, source, received_at, ingest_version, event_id
) VALUES (
  '30730000-0000-4000-8000-000000000002',
  'app',
  now() - interval '5 hours',
  'app',
  now() - interval '5 hours',
  2,
  gen_random_uuid()
);

INSERT INTO public.alerts (
  id, user_id, cause, stage, status, opened_at, stage_entered_at, next_deadline
) VALUES (
  '30730000-0000-4000-8000-000000000030',
  '30730000-0000-4000-8000-000000000002',
  'silence',
  'self',
  'open',
  now() - interval '6 hours',
  now() - interval '6 hours',
  now() + interval '30 minutes'
);

SELECT public.process_escalations();

SELECT is(
  (
    SELECT count(*)::integer
    FROM public.alerts
    WHERE user_id = '30730000-0000-4000-8000-000000000002'
      AND status = 'open'
      AND cause = 'silence'
  ),
  0,
  'device status cannot bypass post-wake grace to create a silence alert'
);

SELECT is(
  (
    SELECT status
    FROM public.alerts
    WHERE id = '30730000-0000-4000-8000-000000000030'
  ),
  'resolved',
  'an existing silence alert auto-resolves during post-wake grace'
);

SELECT ok(
  NOT has_function_privilege(
    'authenticated',
    'private.silence_threshold(uuid)',
    'EXECUTE'
  ),
  'live personalized threshold remains owner-only'
);

SELECT * FROM finish();
ROLLBACK;
