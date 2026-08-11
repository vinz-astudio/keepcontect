-- ADR-0035 step 2: candidate-vs-live recording and counterfactual replay.
--
-- Every fixture uses a fixed through_date and a UTC sleep window so each
-- expected alert count is arithmetic rather than a guess about "now".

BEGIN;

SELECT plan(18);

INSERT INTO auth.users (id, email, aud, role) VALUES
  ('36000000-0000-4000-8000-000000000001', 'ats-tighten@example.invalid', 'authenticated', 'authenticated'),
  ('36000000-0000-4000-8000-000000000002', 'ats-sleep@example.invalid', 'authenticated', 'authenticated'),
  ('36000000-0000-4000-8000-000000000003', 'ats-quiet@example.invalid', 'authenticated', 'authenticated'),
  ('36000000-0000-4000-8000-000000000004', 'ats-no-live@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, display_name, routine_pattern, consent_data_sharing) VALUES
  ('36000000-0000-4000-8000-000000000001', 'ATS tighten', 'regular_9to5', false),
  ('36000000-0000-4000-8000-000000000002', 'ATS sleep', 'regular_9to5', false),
  ('36000000-0000-4000-8000-000000000003', 'ATS quiet', 'regular_9to5', false),
  ('36000000-0000-4000-8000-000000000004', 'ATS no live comparator', 'regular_9to5', false)
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  routine_pattern = EXCLUDED.routine_pattern,
  consent_data_sharing = EXCLUDED.consent_data_sharing;

INSERT INTO public.user_settings (user_id, sensitivity, timezone, sleep_start_local, sleep_end_local) VALUES
  ('36000000-0000-4000-8000-000000000001', 'high', 'UTC', NULL, NULL),
  ('36000000-0000-4000-8000-000000000002', 'high', 'UTC', '23:00', '07:00'),
  ('36000000-0000-4000-8000-000000000003', 'high', 'UTC', '23:00', '07:00'),
  ('36000000-0000-4000-8000-000000000004', 'high', 'UTC', NULL, NULL)
ON CONFLICT (user_id) DO UPDATE SET
  sensitivity = EXCLUDED.sensitivity,
  timezone = EXCLUDED.timezone,
  sleep_start_local = EXCLUDED.sleep_start_local,
  sleep_end_local = EXCLUDED.sleep_end_local;

-- The first three subjects have an evidence-backed live comparator. Subject 4
-- deliberately does not: ADR-0037 requires the live threshold to stay NULL.
INSERT INTO public.account_normal_bounds (
  user_id, through_date, lookback_days, false_alarm_budget,
  window_starts_at, window_ends_at, event_count, gap_count, evidence_days,
  first_event_at, last_event_at, sleep_window_applied, order_index,
  normal_upper_bound_minutes, largest_gap_minutes,
  second_largest_gap_minutes, has_usable_signal, sensitivity,
  buffer_minutes, threshold_minutes, episodes_new
)
SELECT
  subject.user_id, '2026-03-10'::date, 30, 1,
  '2026-02-09T00:00:00Z'::timestamptz,
  '2026-03-11T00:00:00Z'::timestamptz,
  2, 1, 2,
  '2026-03-01T00:00:00Z'::timestamptz,
  '2026-03-01T03:20:00Z'::timestamptz,
  false, 1, 90, 90, 90, true, 'high', 0, 90, 0
FROM (VALUES
  ('36000000-0000-4000-8000-000000000001'::uuid),
  ('36000000-0000-4000-8000-000000000002'::uuid),
  ('36000000-0000-4000-8000-000000000003'::uuid)
) AS subject(user_id);

-- 'high' sensitivity keeps the buffer at 0, so every threshold below is the
-- neutral value itself and the arithmetic stays visible.
-- Subject 1: twenty 10-minute gaps and then one 200-minute silence. Twenty-one
-- gaps put the 95th percentile squarely on a 10-minute value, so the neutral
-- number is exact rather than an interpolation between 10 and 200.
INSERT INTO public.behavior_pings (user_id, kind, source, at, received_at, ingest_version)
SELECT
  '36000000-0000-4000-8000-000000000001', 'app', 'capacitor',
  moment.t, moment.t, 2
FROM generate_series(
  '2026-03-01T00:00:00Z'::timestamptz,
  '2026-03-01T03:20:00Z'::timestamptz,
  interval '10 minutes'
) AS moment(t);

INSERT INTO public.behavior_pings (user_id, kind, source, at, received_at, ingest_version) VALUES
  ('36000000-0000-4000-8000-000000000001', 'app', 'capacitor', '2026-03-01T06:40:00Z', '2026-03-01T06:40:00Z', 2),

  -- Subject 2: one silence that begins before the sleep window and ends after
  -- the post-wake grace. 22:00 -> 10:00 is 720 raw minutes.
  ('36000000-0000-4000-8000-000000000002', 'app', 'capacitor', '2026-03-01T22:00:00Z', '2026-03-01T22:00:00Z', 2),
  ('36000000-0000-4000-8000-000000000002', 'app', 'capacitor', '2026-03-02T10:00:00Z', '2026-03-02T10:00:00Z', 2),

  -- Subject 3: the same silence, but it ends at 08:30, while the post-wake
  -- grace still runs to 09:00. Nothing may fire.
  ('36000000-0000-4000-8000-000000000003', 'app', 'capacitor', '2026-03-01T22:00:00Z', '2026-03-01T22:00:00Z', 2),
  ('36000000-0000-4000-8000-000000000003', 'app', 'capacitor', '2026-03-02T08:30:00Z', '2026-03-02T08:30:00Z', 2),

  -- Subject 4 has enough candidate evidence, but no accepted live comparator.
  ('36000000-0000-4000-8000-000000000004', 'app', 'capacitor', '2026-03-01T00:00:00Z', '2026-03-01T00:00:00Z', 2),
  ('36000000-0000-4000-8000-000000000004', 'app', 'capacitor', '2026-03-01T03:20:00Z', '2026-03-01T03:20:00Z', 2);

CREATE TEMP TABLE _live_before ON COMMIT DROP AS
SELECT
  (SELECT count(*) FROM public.alerts) AS alerts,
  (SELECT count(*) FROM public.alert_events) AS alert_events,
  (SELECT count(*) FROM public.notifications) AS notifications,
  (SELECT count(*) FROM public.behavior_pings) AS behavior_pings,
  (SELECT count(*) FROM public.device_state) AS device_state,
  (SELECT private.silence_threshold('36000000-0000-4000-8000-000000000001')) AS live_threshold,
  (SELECT private.silence_threshold('36000000-0000-4000-8000-000000000004')) AS missing_live_threshold;

-- k = 0 keeps the neutral value equal to the account's own p95.
SELECT lives_ok(
  $$SELECT private.rebuild_account_gap_profiles(
      '2026-03-10'::date, 30, 0, 0.95, 1, 2, 90, true
    )$$,
  'step 1 profiles exist for the parameters step 2 will record'
);

SELECT lives_ok(
  $$SELECT private.record_account_threshold_shadow('2026-03-10'::date, 30, 0, 0.95)$$,
  'the recorder runs for the same parameters'
);

SELECT is(
  (SELECT neutral_minutes FROM public.account_threshold_shadow
   WHERE user_id = '36000000-0000-4000-8000-000000000001' AND shrinkage_k = 0),
  10,
  'the recorded neutral value is the one step 1 wrote, not a recomputation'
);

SELECT is(
  (SELECT candidate_unfloored_minutes FROM public.account_threshold_shadow
   WHERE user_id = '36000000-0000-4000-8000-000000000001' AND shrinkage_k = 0),
  10,
  'without the floor the candidate is the neutral value plus the buffer'
);

SELECT is(
  (SELECT candidate_floored_minutes FROM public.account_threshold_shadow
   WHERE user_id = '36000000-0000-4000-8000-000000000001' AND shrinkage_k = 0),
  90,
  'with the floor the candidate cannot go below the neutral floor plus the buffer'
);

SELECT is(
  (SELECT live_threshold_minutes FROM public.account_threshold_shadow
   WHERE user_id = '36000000-0000-4000-8000-000000000001' AND shrinkage_k = 0),
  round(extract(epoch FROM private.silence_threshold('36000000-0000-4000-8000-000000000001')) / 60)::integer,
  'the live column is the live function, not a reimplementation of it'
);

SELECT is(
  (SELECT gaps_evaluated FROM public.account_threshold_shadow
   WHERE user_id = '36000000-0000-4000-8000-000000000001' AND shrinkage_k = 0),
  21,
  'every gap in the window is evaluated, not only the ones that fire'
);

SELECT is(
  (SELECT episodes_live FROM public.account_threshold_shadow
   WHERE user_id = '36000000-0000-4000-8000-000000000001' AND shrinkage_k = 0),
  1,
  'the live rule fires once: only the 200-minute silence exceeds 90 minutes'
);

SELECT is(
  (SELECT episodes_candidate_unfloored FROM public.account_threshold_shadow
   WHERE user_id = '36000000-0000-4000-8000-000000000001' AND shrinkage_k = 0),
  1,
  'a 10-minute threshold still fires only once: ten-minute gaps do not exceed it'
);

SELECT is(
  (SELECT episodes_candidate_only FROM public.account_threshold_shadow
   WHERE user_id = '36000000-0000-4000-8000-000000000001' AND shrinkage_k = 0),
  0,
  'no divergence is invented where both rules agree'
);

SELECT is(
  (SELECT episodes_candidate_floored FROM public.account_threshold_shadow
   WHERE user_id = '36000000-0000-4000-8000-000000000002' AND shrinkage_k = 0),
  1,
  'a silence that outlasts the sleep window and its grace does fire, once'
);

SELECT is(
  (SELECT episodes_candidate_floored FROM public.account_threshold_shadow
   WHERE user_id = '36000000-0000-4000-8000-000000000003' AND shrinkage_k = 0),
  0,
  'a silence that ends inside the post-wake grace never fires'
);

SELECT is(
  (SELECT gaps_evaluated FROM public.account_threshold_shadow
   WHERE user_id = '36000000-0000-4000-8000-000000000003' AND shrinkage_k = 0),
  1,
  'the withheld alert is still an evaluated gap, not a silently dropped one'
);

SELECT ok(
  NOT (SELECT is_alertable FROM public.account_threshold_shadow
       WHERE user_id = '36000000-0000-4000-8000-000000000001' AND shrinkage_k = 0),
  'an account with no device state and no monitored membership is marked unalertable'
);

SELECT is(
  (SELECT count(*) FROM public.account_threshold_shadow
   WHERE user_id = '36000000-0000-4000-8000-000000000004' AND shrinkage_k = 0),
  1::bigint,
  'a candidate row is retained when the accepted live comparator is unavailable'
);

SELECT ok(
  (SELECT neutral_minutes IS NOT NULL
          AND candidate_floored_minutes IS NOT NULL
          AND candidate_unfloored_minutes IS NOT NULL
          AND gaps_evaluated IS NOT NULL
          AND episodes_candidate_floored IS NOT NULL
          AND episodes_candidate_unfloored IS NOT NULL
   FROM public.account_threshold_shadow
   WHERE user_id = '36000000-0000-4000-8000-000000000004' AND shrinkage_k = 0),
  'candidate evidence remains populated without a live comparator'
);

SELECT ok(
  (SELECT live_threshold_minutes IS NULL
          AND episodes_live IS NULL
          AND episodes_candidate_only IS NULL
          AND episodes_live_only IS NULL
          AND earliest_divergence_at IS NULL
          AND earliest_divergence_gap_minutes IS NULL
          AND longest_candidate_only_gap_minutes IS NULL
   FROM public.account_threshold_shadow
   WHERE user_id = '36000000-0000-4000-8000-000000000004' AND shrinkage_k = 0),
  'all live-dependent values stay NULL when comparison is impossible'
);

SELECT ok(
  (SELECT count(*) FROM public.alerts) = (SELECT alerts FROM _live_before)
  AND (SELECT count(*) FROM public.alert_events) = (SELECT alert_events FROM _live_before)
  AND (SELECT count(*) FROM public.notifications) = (SELECT notifications FROM _live_before)
  AND (SELECT count(*) FROM public.behavior_pings) = (SELECT behavior_pings FROM _live_before)
  AND (SELECT count(*) FROM public.device_state) = (SELECT device_state FROM _live_before)
  AND (SELECT private.silence_threshold('36000000-0000-4000-8000-000000000001'))
      IS NOT DISTINCT FROM (SELECT live_threshold FROM _live_before)
  AND (SELECT private.silence_threshold('36000000-0000-4000-8000-000000000004'))
      IS NOT DISTINCT FROM (SELECT missing_live_threshold FROM _live_before),
  'replaying a counterfactual raises no real alert and moves no live threshold'
);

SELECT * FROM finish();
ROLLBACK;
