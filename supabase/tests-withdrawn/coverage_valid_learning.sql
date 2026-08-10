-- ADR-0039 · The account normal bound may only be learned from stretches the
-- system could actually observe, from evidence this person actually produced,
-- and — for an exceptional long silence — only with repeat support.
--
-- Every assertion here is about the same failure: a threshold widened by the
-- system's own blindness stops noticing the person it was meant to protect.
BEGIN;

SELECT plan(10);

INSERT INTO auth.users (id, email, aud, role)
SELECT
  format('55000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
  format('coverage-learn-%s@example.invalid', n),
  'authenticated', 'authenticated'
FROM generate_series(1, 8) AS n
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, display_name)
SELECT
  format('55000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
  format('coverage learner %s', n)
FROM generate_series(1, 8) AS n
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

INSERT INTO public.user_settings (user_id, sensitivity, timezone)
SELECT
  format('55000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
  'high', 'UTC'
FROM generate_series(1, 8) AS n
ON CONFLICT (user_id) DO UPDATE
SET sensitivity = EXCLUDED.sensitivity, timezone = EXCLUDED.timezone;

-- A model version, because an interval must name the version it was produced
-- under. Its config is irrelevant here; only the coverage claim matters.
WITH config AS (
  SELECT '{
  "sessionization":{"gap_minutes":30,"per_user_day_gap_cap":8,"training_horizon_days":30,"intervention_window_minutes":30},
  "context":{"definition_version":"coverage-learn-v1","day_partition":"all_days","hour_bucket_minutes":60},
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
  '55100000-0000-4000-8000-000000000001',
  'coverage-learning-fixture', 'shadow', value,
  encode(extensions.digest(value::text, 'sha256'), 'hex'),
  'canonical-v2', now() - interval '10 days'
FROM config;

-- Helper fixtures ---------------------------------------------------------
-- Every subject below gets the same shape of day: two live pings separated by
-- a silence. What differs is whether we could see it, who produced it, and
-- how often it happened.

CREATE TEMP TABLE learn_subject(n integer, uid uuid);
INSERT INTO learn_subject
SELECT n, format('55000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid
FROM generate_series(1, 8) AS n;

-- Subject 1: uncovered silence. Subject 2: the same silence, covered.
-- Subject 3: covered only partially. Subject 4: covered, but the app could not
-- have reached them. Subject 5: manual check-in. Subject 6: Shortcut.
-- Subject 7: replayed history. Subject 8: nothing at all.
INSERT INTO public.behavior_pings (user_id, kind, at, source, received_at, ingest_version, event_id)
SELECT s.uid, 'app', t.at, t.src, t.recv, 2, gen_random_uuid()
FROM learn_subject AS s
CROSS JOIN LATERAL (
  VALUES
    (now() - interval '5 days' - interval '200 minutes', 'app'::text,
     now() - interval '5 days' - interval '200 minutes'),
    (now() - interval '5 days', 'app'::text, now() - interval '5 days')
) AS t(at, src, recv)
WHERE s.n IN (1, 2, 3, 4);

-- Subject 5 answers a prompt by hand; subject 6 fires a Shortcut.
INSERT INTO public.behavior_pings (user_id, kind, at, source, received_at, ingest_version, event_id)
SELECT s.uid, k.kind, t.at, k.src, t.at, 2, gen_random_uuid()
FROM learn_subject AS s
CROSS JOIN LATERAL (
  SELECT CASE WHEN s.n = 5 THEN 'manual_checkin' ELSE 'app' END AS kind,
         CASE WHEN s.n = 5 THEN 'manual' ELSE 'shortcut' END AS src
) AS k
CROSS JOIN LATERAL (
  VALUES (now() - interval '5 days' - interval '200 minutes'), (now() - interval '5 days')
) AS t(at)
WHERE s.n IN (5, 6);

-- Subject 7's history was re-imported long after the fact.
INSERT INTO public.behavior_pings (user_id, kind, at, source, received_at, ingest_version, event_id)
SELECT s.uid, 'app', t.at, 'app', now() - interval '1 hour', 2, gen_random_uuid()
FROM learn_subject AS s
CROSS JOIN LATERAL (
  VALUES (now() - interval '5 days' - interval '200 minutes'), (now() - interval '5 days')
) AS t(at)
WHERE s.n = 7;

-- Coverage claims. Subject 1 has none at all.
INSERT INTO public.alert_observation_coverage_intervals (
  version_id, user_id, starts_at, ends_at, timezone, utc_offset_minutes,
  activity_coverage_state, intervention_coverage_state, sleep_context_state,
  captured_at, evidence_version, provenance_sha256
)
SELECT
  '55100000-0000-4000-8000-000000000001', s.uid,
  now() - interval '6 days',
  bound.ends_at,
  'UTC', 0,
  'valid',
  CASE WHEN s.n = 4 THEN 'incomplete' ELSE 'valid' END,
  'valid',
  bound.ends_at, 'canonical-v2', repeat('b', 64)
FROM learn_subject AS s
CROSS JOIN LATERAL (
  SELECT CASE
    WHEN s.n = 3 THEN now() - interval '5 days' - interval '100 minutes'
    ELSE now() - interval '4 days'
  END AS ends_at
) AS bound
WHERE s.n IN (2, 3, 4, 5, 6, 7);

SELECT private.rebuild_account_normal_bounds(
  (now() AT TIME ZONE 'UTC')::date, 30, 1, 0, 45, 90, 120
);

CREATE TEMP TABLE learned AS
SELECT b.user_id, b.normal_upper_bound_minutes, b.has_usable_signal, b.threshold_minutes
FROM public.account_normal_bounds AS b
WHERE b.through_date = (now() AT TIME ZONE 'UTC')::date
  AND b.lookback_days = 30;

-- 1..4: the coverage gate.
SELECT ok(
  (SELECT NOT has_usable_signal FROM learned
   WHERE user_id = (SELECT uid FROM learn_subject WHERE n = 1)),
  'a silence nobody was watching teaches nothing'
);

SELECT ok(
  (SELECT has_usable_signal AND normal_upper_bound_minutes >= 190 FROM learned
   WHERE user_id = (SELECT uid FROM learn_subject WHERE n = 2)),
  'the same silence, fully covered, is admissible evidence'
);

SELECT ok(
  (SELECT NOT has_usable_signal FROM learned
   WHERE user_id = (SELECT uid FROM learn_subject WHERE n = 3)),
  'coverage that stops midway does not partially count; the uncovered half is where someone could have been missed'
);

SELECT ok(
  (SELECT NOT has_usable_signal FROM learned
   WHERE user_id = (SELECT uid FROM learn_subject WHERE n = 4)),
  'a collector that ran but could not reach the person is not coverage'
);

-- 5..7: the source gate.
SELECT ok(
  (SELECT NOT has_usable_signal FROM learned
   WHERE user_id = (SELECT uid FROM learn_subject WHERE n = 5)),
  'a manual check-in is a person answering a prompt, not evidence of an ordinary day'
);

SELECT ok(
  (SELECT NOT has_usable_signal FROM learned
   WHERE user_id = (SELECT uid FROM learn_subject WHERE n = 6)),
  'a Shortcut is an automation firing, not the person being observed'
);

SELECT ok(
  (SELECT NOT has_usable_signal FROM learned
   WHERE user_id = (SELECT uid FROM learn_subject WHERE n = 7)),
  'replayed history arrives long after the moment it claims to describe and may not train'
);

-- 8: the no-evidence outcome.
SELECT ok(
  (SELECT NOT has_usable_signal AND threshold_minutes IS NULL FROM learned
   WHERE user_id = (SELECT uid FROM learn_subject WHERE n = 8)),
  'an account with nothing qualifying records an absence, not an invented number'
);

-- 9..10: the repeat-evidence gate. Subject 2 already has ordinary days plus one
-- exceptional silence; give it companions and watch the bound move only when a
-- second independent date agrees.
INSERT INTO public.behavior_pings (user_id, kind, at, source, received_at, ingest_version, event_id)
SELECT
  (SELECT uid FROM learn_subject WHERE n = 2),
  'app', t.at, 'app', t.at, 2, gen_random_uuid()
FROM (
  VALUES
    (now() - interval '3 days' - interval '600 minutes'),
    (now() - interval '3 days')
) AS t(at);

INSERT INTO public.alert_observation_coverage_intervals (
  version_id, user_id, starts_at, ends_at, timezone, utc_offset_minutes,
  activity_coverage_state, intervention_coverage_state, sleep_context_state,
  captured_at, evidence_version, provenance_sha256
)
VALUES (
  '55100000-0000-4000-8000-000000000001',
  (SELECT uid FROM learn_subject WHERE n = 2),
  now() - interval '4 days', now() - interval '2 days', 'UTC', 0,
  'valid', 'valid', 'valid',
  now() - interval '2 days', 'canonical-v2', repeat('c', 64)
);

SELECT private.rebuild_account_normal_bounds(
  (now() AT TIME ZONE 'UTC')::date, 30, 1, 0, 45, 90, 120
);

SELECT ok(
  (SELECT b.normal_upper_bound_minutes < 590
   FROM public.account_normal_bounds AS b
   WHERE b.user_id = (SELECT uid FROM learn_subject WHERE n = 2)
     AND b.through_date = (now() AT TIME ZONE 'UTC')::date
     AND b.lookback_days = 30),
  'one exceptional silence on a single date does not become the new normal'
);

-- A second, independent date carrying a comparable silence.
INSERT INTO public.behavior_pings (user_id, kind, at, source, received_at, ingest_version, event_id)
SELECT
  (SELECT uid FROM learn_subject WHERE n = 2),
  'app', t.at, 'app', t.at, 2, gen_random_uuid()
FROM (
  VALUES
    (now() - interval '9 days' - interval '600 minutes'),
    (now() - interval '9 days')
) AS t(at);

INSERT INTO public.alert_observation_coverage_intervals (
  version_id, user_id, starts_at, ends_at, timezone, utc_offset_minutes,
  activity_coverage_state, intervention_coverage_state, sleep_context_state,
  captured_at, evidence_version, provenance_sha256
)
VALUES (
  '55100000-0000-4000-8000-000000000001',
  (SELECT uid FROM learn_subject WHERE n = 2),
  now() - interval '10 days', now() - interval '8 days', 'UTC', 0,
  'valid', 'valid', 'valid',
  now() - interval '8 days', 'canonical-v2', repeat('d', 64)
);

SELECT private.rebuild_account_normal_bounds(
  (now() AT TIME ZONE 'UTC')::date, 30, 1, 0, 45, 90, 120
);

SELECT ok(
  (SELECT b.normal_upper_bound_minutes >= 590
   FROM public.account_normal_bounds AS b
   WHERE b.user_id = (SELECT uid FROM learn_subject WHERE n = 2)
     AND b.through_date = (now() AT TIME ZONE 'UTC')::date
     AND b.lookback_days = 30),
  'two independent comparable dates make the longer silence a real part of this person''s normal'
);

SELECT * FROM finish();
ROLLBACK;
