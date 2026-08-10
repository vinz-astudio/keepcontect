-- ADR-0039/0040 · The chain only counts if something runs it.
--
-- evaluate_protection_health and dispatch_special_attention_notices were both
-- correct and both unreachable: no cron job, no caller. Production held zero
-- incidents and zero notices while coverage arrived normally, which made
-- Special Attention inert end to end. These assertions are about the cycle
-- that connects them, and about the order it connects them in.
BEGIN;

SELECT plan(15);

INSERT INTO auth.users (id, email, aud, role) VALUES
  ('58000000-0000-4000-8000-000000000001', 'cycle-stale@example.invalid', 'authenticated', 'authenticated'),
  ('58000000-0000-4000-8000-000000000002', 'cycle-fresh@example.invalid', 'authenticated', 'authenticated'),
  ('58000000-0000-4000-8000-000000000003', 'cycle-watcher@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, display_name) VALUES
  ('58000000-0000-4000-8000-000000000001', 'Cycle stale'),
  ('58000000-0000-4000-8000-000000000002', 'Cycle fresh'),
  ('58000000-0000-4000-8000-000000000003', 'Cycle watcher')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

INSERT INTO public.groups (id, name, created_by)
VALUES ('58000000-0000-4000-8000-000000000010', 'cycle-fixture',
        '58000000-0000-4000-8000-000000000001');

INSERT INTO public.group_members (group_id, user_id, role, status, monitored, watching) VALUES
  ('58000000-0000-4000-8000-000000000010', '58000000-0000-4000-8000-000000000001', 'member', 'active', true, false),
  ('58000000-0000-4000-8000-000000000010', '58000000-0000-4000-8000-000000000003', 'member', 'active', false, true)
ON CONFLICT (group_id, user_id) DO UPDATE SET status = EXCLUDED.status;

CREATE TEMP TABLE cycle_base_config AS
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

INSERT INTO public.alert_model_versions
  (id, name, status, config, config_sha256, evidence_version, shadow_enabled_at)
SELECT '58100000-0000-4000-8000-000000000001',
       'protection-health-cycle-fixture',
       'shadow',
       config,
       encode(extensions.digest(config::text, 'sha256'), 'hex'),
       'canonical-v2',
       now()
FROM cycle_base_config;

-- The gate reads the platform of the most recently seen client, so every
-- subject in this fixture needs one that can report coverage.
INSERT INTO public.clients (user_id, client_id, platform, app_version, first_seen_at, last_seen_at) VALUES
  ('58000000-0000-4000-8000-000000000001', 'cycle-stale-apk', 'android-apk', '0.5.26', now() - interval '9 days', now() - interval '5 days'),
  ('58000000-0000-4000-8000-000000000002', 'cycle-fresh-apk', 'android-apk', '0.5.26', now() - interval '9 days', now() - interval '1 hour')
ON CONFLICT (user_id, client_id) DO UPDATE SET platform = EXCLUDED.platform;

-- One subject lapsed well past the 26-hour window; one is still covered.
INSERT INTO public.alert_observation_coverage_intervals
  (version_id, user_id, starts_at, ends_at, timezone, utc_offset_minutes,
   activity_coverage_state, intervention_coverage_state, sleep_context_state,
   captured_at, evidence_version, provenance_sha256) VALUES
  ('58100000-0000-4000-8000-000000000001', '58000000-0000-4000-8000-000000000001',
   now() - interval '5 days', now() - interval '4 days', 'UTC', 0,
   'valid', 'valid', 'valid', now() - interval '4 days', 'canonical-v2', repeat('a', 64)),
  ('58100000-0000-4000-8000-000000000001', '58000000-0000-4000-8000-000000000002',
   now() - interval '2 hours', now() - interval '1 hour', 'UTC', 0,
   'valid', 'valid', 'valid', now() - interval '1 hour', 'canonical-v2', repeat('b', 64));

-- 1
SELECT is(
  (SELECT count(*)::int FROM public.protection_health_incidents
   WHERE user_id = '58000000-0000-4000-8000-000000000001'),
  0,
  'nothing has opened an incident before the cycle runs'
);

-- 2
SELECT lives_ok(
  $$SELECT private.run_protection_health_cycle(interval '2 hours')$$,
  'the cycle runs'
);

-- 3
SELECT is(
  (SELECT count(*)::int FROM public.protection_health_incidents
   WHERE user_id = '58000000-0000-4000-8000-000000000001' AND closed_at IS NULL),
  1,
  'a subject whose coverage went stale gets exactly one open incident'
);

-- 4
SELECT is(
  (SELECT count(*)::int FROM public.protection_health_incidents
   WHERE user_id = '58000000-0000-4000-8000-000000000002'),
  0,
  'a subject with fresh coverage is left alone'
);

-- 5: the server prompts, because an app that stopped watching cannot.
SELECT is(
  (SELECT count(*)::int FROM public.notifications
   WHERE recipient_id = '58000000-0000-4000-8000-000000000001'
     AND kind = 'protection_limited'),
  1,
  'the subject is prompted by the server, not by the app that stopped watching'
);

-- 6
SELECT is(
  (SELECT params ->> 'means_danger' FROM public.notifications
   WHERE recipient_id = '58000000-0000-4000-8000-000000000001'
     AND kind = 'protection_limited'),
  'false',
  'the prompt says machine-readably that it is not a claim about the person'
);

-- 7
SELECT isnt(
  (SELECT prompted_at FROM public.protection_health_incidents
   WHERE user_id = '58000000-0000-4000-8000-000000000001'),
  NULL,
  'prompted_at records the moment the subject was actually reached'
);

-- 8: the watcher opts in, but the grace period has not passed.
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', '58000000-0000-4000-8000-000000000003', true);
SELECT public.set_special_attention('58000000-0000-4000-8000-000000000001', true);
RESET ROLE;

SELECT is(
  (SELECT count(*)::int FROM public.special_attention_notices),
  0,
  'nobody else is told in the same cycle that prompted the subject'
);

-- 9: age the prompt past grace.
UPDATE public.protection_health_incidents
SET prompted_at = now() - interval '3 hours'
WHERE user_id = '58000000-0000-4000-8000-000000000001';

SELECT lives_ok(
  $$SELECT private.run_protection_health_cycle(interval '2 hours')$$,
  'the cycle runs again once the grace period has passed'
);

-- 10
SELECT is(
  (SELECT count(*)::int FROM public.notifications
   WHERE recipient_id = '58000000-0000-4000-8000-000000000003'
     AND kind = 'coverage_interrupted'),
  1,
  'the watcher is told only after the subject was prompted and grace elapsed'
);

-- 11: a repeat cycle must not repeat the news.
SELECT lives_ok(
  $$SELECT private.run_protection_health_cycle(interval '2 hours')$$,
  'a third cycle runs without error'
);

-- 12
SELECT is(
  (SELECT count(*)::int FROM public.notifications
   WHERE recipient_id = '58000000-0000-4000-8000-000000000003'
     AND kind = 'coverage_interrupted'),
  1,
  'the same incident never notifies the same watcher twice'
);


-- 13..15: a subject on a channel that cannot report coverage is unobservable,
-- not broken. Telling them to check their permissions would be blaming them
-- for a gap that is ours.
INSERT INTO auth.users (id, email, aud, role)
VALUES ('58000000-0000-4000-8000-000000000004', 'cycle-pwa@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, display_name)
VALUES ('58000000-0000-4000-8000-000000000004', 'Cycle moved to PWA')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

-- They produced coverage on the APK, then moved to a channel that has no
-- background collector at all. iOS is deliberately not used here: iOS reports
-- coverage from its wakes as of 20260811020000, so using it as the example of
-- an unobservable platform would quietly stop testing anything.
INSERT INTO public.clients (user_id, client_id, platform, app_version, first_seen_at, last_seen_at) VALUES
  ('58000000-0000-4000-8000-000000000004', 'moved-apk', 'android-apk', '0.5.26', now() - interval '20 days', now() - interval '7 days'),
  ('58000000-0000-4000-8000-000000000004', 'moved-web', 'ios-pwa',     '0.5.26', now() - interval '6 days',  now() - interval '2 hours')
ON CONFLICT (user_id, client_id) DO UPDATE SET platform = EXCLUDED.platform;

INSERT INTO public.alert_observation_coverage_intervals
  (version_id, user_id, starts_at, ends_at, timezone, utc_offset_minutes,
   activity_coverage_state, intervention_coverage_state, sleep_context_state,
   captured_at, evidence_version, provenance_sha256)
VALUES
  ('58100000-0000-4000-8000-000000000001', '58000000-0000-4000-8000-000000000004',
   now() - interval '8 days', now() - interval '7 days', 'UTC', 0,
   'valid', 'valid', 'valid', now() - interval '7 days', 'canonical-v2', repeat('c', 64));

SELECT is(
  (SELECT private.coverage_capable_subject('58000000-0000-4000-8000-000000000004')),
  false,
  'someone whose current channel cannot report coverage is not coverage-capable'
);

SELECT lives_ok(
  $$SELECT private.run_protection_health_cycle(interval '2 hours')$$,
  'the cycle runs with an unobservable subject present'
);

SELECT is(
  (SELECT count(*)::int FROM public.notifications
   WHERE recipient_id = '58000000-0000-4000-8000-000000000004'),
  0,
  'an unobservable subject is never told to fix a gap that is not theirs'
);

SELECT * FROM finish();
ROLLBACK;
