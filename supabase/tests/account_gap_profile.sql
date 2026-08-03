-- ADR-0035 step 1: account-level gap profile.
--
-- Fixtures use a fixed through_date so every window boundary and every
-- percentile is arithmetic, not a guess about "now".

BEGIN;

SELECT plan(21);

INSERT INTO auth.users (id, email, aud, role) VALUES
  ('35000000-0000-4000-8000-000000000001', 'agp-sleep@example.invalid', 'authenticated', 'authenticated'),
  ('35000000-0000-4000-8000-000000000002', 'agp-uncapped@example.invalid', 'authenticated', 'authenticated'),
  ('35000000-0000-4000-8000-000000000003', 'agp-multidevice@example.invalid', 'authenticated', 'authenticated'),
  ('35000000-0000-4000-8000-000000000004', 'agp-cohort-a@example.invalid', 'authenticated', 'authenticated'),
  ('35000000-0000-4000-8000-000000000005', 'agp-cohort-b@example.invalid', 'authenticated', 'authenticated'),
  ('35000000-0000-4000-8000-000000000006', 'agp-thin@example.invalid', 'authenticated', 'authenticated'),
  ('35000000-0000-4000-8000-000000000007', 'agp-noconsent@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, display_name, routine_pattern, consent_data_sharing) VALUES
  ('35000000-0000-4000-8000-000000000001', 'AGP sleep', 'regular_9to5', false),
  ('35000000-0000-4000-8000-000000000002', 'AGP uncapped', 'regular_9to5', false),
  ('35000000-0000-4000-8000-000000000003', 'AGP multidevice', 'regular_9to5', false),
  ('35000000-0000-4000-8000-000000000004', 'AGP cohort A', 'shift_irregular', true),
  ('35000000-0000-4000-8000-000000000005', 'AGP cohort B', 'shift_irregular', true),
  ('35000000-0000-4000-8000-000000000006', 'AGP thin', 'shift_irregular', false),
  ('35000000-0000-4000-8000-000000000007', 'AGP no consent', 'semester_break', false)
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  routine_pattern = EXCLUDED.routine_pattern,
  consent_data_sharing = EXCLUDED.consent_data_sharing;

-- Only the sleep subject has a configured sleep window; everyone else must be
-- measured on raw elapsed time so the other assertions stay pure arithmetic.
INSERT INTO public.user_settings (user_id, sensitivity, timezone, sleep_start_local, sleep_end_local) VALUES
  ('35000000-0000-4000-8000-000000000001', 'balanced', 'UTC', '23:00', '07:00'),
  ('35000000-0000-4000-8000-000000000002', 'balanced', 'UTC', NULL, NULL),
  ('35000000-0000-4000-8000-000000000003', 'balanced', 'UTC', NULL, NULL),
  ('35000000-0000-4000-8000-000000000004', 'balanced', 'UTC', NULL, NULL),
  ('35000000-0000-4000-8000-000000000005', 'balanced', 'UTC', NULL, NULL),
  ('35000000-0000-4000-8000-000000000006', 'balanced', 'UTC', NULL, NULL),
  ('35000000-0000-4000-8000-000000000007', 'balanced', 'UTC', NULL, NULL)
ON CONFLICT (user_id) DO UPDATE SET
  timezone = EXCLUDED.timezone,
  sleep_start_local = EXCLUDED.sleep_start_local,
  sleep_end_local = EXCLUDED.sleep_end_local;

INSERT INTO public.behavior_pings (user_id, kind, source, at, received_at, ingest_version) VALUES
  -- Sleep subject: 22:00 -> 09:00 is 660 raw minutes across a 23:00-07:00
  -- window, so 480 minutes are sleep and 180 minutes are real silence.
  ('35000000-0000-4000-8000-000000000001', 'app', 'capacitor', '2026-03-01T22:00:00Z', '2026-03-01T22:00:00Z', 2),
  ('35000000-0000-4000-8000-000000000001', 'app', 'capacitor', '2026-03-02T09:00:00Z', '2026-03-02T09:00:00Z', 2),

  -- Uncapped subject: a single 1800-minute gap, far above the retired 600
  -- minute ceiling.
  ('35000000-0000-4000-8000-000000000002', 'app', 'installed_pwa', '2026-03-01T00:00:00Z', '2026-03-01T00:00:00Z', 2),
  ('35000000-0000-4000-8000-000000000002', 'app', 'installed_pwa', '2026-03-02T06:00:00Z', '2026-03-02T06:00:00Z', 2),

  -- Multi-device subject: three devices, four rows, but the 10:00 minute is
  -- reported twice. Three events, two 30-minute gaps.
  ('35000000-0000-4000-8000-000000000003', 'app', 'capacitor', '2026-03-03T10:00:05Z', '2026-03-03T10:00:05Z', 2),
  ('35000000-0000-4000-8000-000000000003', 'interaction', 'tauri', '2026-03-03T10:00:41Z', '2026-03-03T10:00:41Z', 2),
  ('35000000-0000-4000-8000-000000000003', 'interaction', 'installed_pwa', '2026-03-03T10:30:00Z', '2026-03-03T10:30:00Z', 2),
  ('35000000-0000-4000-8000-000000000003', 'app', 'capacitor', '2026-03-03T11:00:00Z', '2026-03-03T11:00:00Z', 2),

  -- Cohort contributors: one 100-minute gap and one 200-minute gap, so the
  -- cohort median is 150.
  ('35000000-0000-4000-8000-000000000004', 'app', 'installed_pwa', '2026-03-04T08:00:00Z', '2026-03-04T08:00:00Z', 2),
  ('35000000-0000-4000-8000-000000000004', 'app', 'installed_pwa', '2026-03-04T09:40:00Z', '2026-03-04T09:40:00Z', 2),
  ('35000000-0000-4000-8000-000000000005', 'app', 'installed_pwa', '2026-03-04T08:00:00Z', '2026-03-04T08:00:00Z', 2),
  ('35000000-0000-4000-8000-000000000005', 'app', 'installed_pwa', '2026-03-04T11:20:00Z', '2026-03-04T11:20:00Z', 2),

  -- No-consent subject: real evidence, but it may only reach the cohort when
  -- the consent gate is explicitly lifted.
  ('35000000-0000-4000-8000-000000000007', 'app', 'installed_pwa', '2026-03-05T08:00:00Z', '2026-03-05T08:00:00Z', 2),
  ('35000000-0000-4000-8000-000000000007', 'app', 'installed_pwa', '2026-03-05T12:00:00Z', '2026-03-05T12:00:00Z', 2),

  -- Skew guard: the live detector cannot see this ping, so learning must not
  -- see it either. It would otherwise split the multi-device 10:30-11:00 gap.
  ('35000000-0000-4000-8000-000000000003', 'app', 'capacitor', '2026-03-03T10:45:00Z', '2026-03-03T11:45:00Z', 2),

  -- Legacy pipeline: v1 rows are not what the detector watches.
  ('35000000-0000-4000-8000-000000000003', 'app', 'app', '2026-03-03T10:50:00Z', '2026-03-03T10:50:00Z', 1);

-- An alert that was open across the multi-device subject's second gap.
INSERT INTO public.alerts (id, user_id, cause, stage, status, opened_at, resolved_at) VALUES
  ('35000000-0000-4000-8000-0000000000a1', '35000000-0000-4000-8000-000000000003',
   'silence', 'self', 'resolved', '2026-03-03T10:40:00Z', '2026-03-03T10:55:00Z');

CREATE TEMP TABLE _live_before ON COMMIT DROP AS
SELECT
  (SELECT count(*) FROM public.alerts) AS alerts,
  (SELECT count(*) FROM public.alert_events) AS alert_events,
  (SELECT count(*) FROM public.behavior_pings) AS behavior_pings,
  (SELECT count(*) FROM public.device_state) AS device_state,
  (SELECT count(*) FROM public.alert_gap_profiles) AS alert_gap_profiles,
  (SELECT private.silence_threshold('35000000-0000-4000-8000-000000000001')) AS live_threshold;

-- Run 1: k = 0 isolates the personal value from any shrinkage.
SELECT lives_ok(
  $$SELECT private.rebuild_account_gap_profiles(
      '2026-03-10'::date, 30, 0, 0.95, 1, 2, 90, true
    )$$,
  'rebuild runs with an explicit through_date and no shrinkage'
);

SELECT is(
  (SELECT personal_pctl_minutes FROM public.account_gap_profiles
   WHERE user_id = '35000000-0000-4000-8000-000000000001' AND shrinkage_k = 0),
  180,
  'the sleep window is subtracted before the percentile: 660 raw minutes become 180'
);

SELECT is(
  (SELECT sleep_minutes_removed FROM public.account_gap_profiles
   WHERE user_id = '35000000-0000-4000-8000-000000000001' AND shrinkage_k = 0),
  480::double precision,
  'the removed sleep minutes are recorded, not silently absorbed'
);

SELECT ok(
  (SELECT sleep_window_applied FROM public.account_gap_profiles
   WHERE user_id = '35000000-0000-4000-8000-000000000001' AND shrinkage_k = 0)
  AND NOT (SELECT sleep_window_applied FROM public.account_gap_profiles
   WHERE user_id = '35000000-0000-4000-8000-000000000002' AND shrinkage_k = 0),
  'an account without a configured sleep window is measured on raw elapsed time'
);

SELECT is(
  (SELECT blended_pctl_minutes FROM public.account_gap_profiles
   WHERE user_id = '35000000-0000-4000-8000-000000000002' AND shrinkage_k = 0),
  1800,
  'no ceiling clamps the result: a 30-hour rhythm survives intact'
);

SELECT is(
  (SELECT event_count FROM public.account_gap_profiles
   WHERE user_id = '35000000-0000-4000-8000-000000000003' AND shrinkage_k = 0),
  3,
  'three devices form one stream, and a doubly reported minute counts once'
);

SELECT is(
  (SELECT gap_count FROM public.account_gap_profiles
   WHERE user_id = '35000000-0000-4000-8000-000000000003' AND shrinkage_k = 0),
  2,
  'gaps are measured across devices, not within a device'
);

SELECT is(
  (SELECT personal_pctl_minutes FROM public.account_gap_profiles
   WHERE user_id = '35000000-0000-4000-8000-000000000003' AND shrinkage_k = 0),
  30,
  'a ping the live detector cannot see (clock skew, v1) cannot shorten a learned gap'
);

SELECT is(
  (SELECT gaps_overlapping_open_alert FROM public.account_gap_profiles
   WHERE user_id = '35000000-0000-4000-8000-000000000003' AND shrinkage_k = 0),
  1,
  'a gap that overlapped an alert is admitted but counted'
);

SELECT is(
  (SELECT cohort_pctl_minutes FROM public.account_gap_profiles
   WHERE user_id = '35000000-0000-4000-8000-000000000006' AND shrinkage_k = 0),
  150,
  'the preset model is the median of its members own values'
);

SELECT is(
  (SELECT cohort_source FROM public.account_gap_profiles
   WHERE user_id = '35000000-0000-4000-8000-000000000006' AND shrinkage_k = 0),
  'cohort',
  'a preset with enough contributors anchors its members'
);

SELECT is(
  (SELECT blended_pctl_minutes FROM public.account_gap_profiles
   WHERE user_id = '35000000-0000-4000-8000-000000000006' AND shrinkage_k = 0),
  150,
  'an account with no evidence of its own is carried entirely by its preset'
);

SELECT is(
  (SELECT blend_weight FROM public.account_gap_profiles
   WHERE user_id = '35000000-0000-4000-8000-000000000006' AND shrinkage_k = 0),
  0::double precision,
  'no evidence means no personal weight, whatever k is'
);

SELECT is(
  (SELECT cohort_source FROM public.account_gap_profiles
   WHERE user_id = '35000000-0000-4000-8000-000000000007' AND shrinkage_k = 0),
  'fallback',
  'an account that has not consented to sharing does not feed the preset model'
);

-- Run 2: k = 3 exercises the shrinkage arithmetic on a known personal value.
SELECT lives_ok(
  $$SELECT private.rebuild_account_gap_profiles(
      '2026-03-10'::date, 30, 3, 0.95, 1, 2, 90, true
    )$$,
  'a second run with a different k coexists with the first'
);

SELECT is(
  (SELECT blend_weight FROM public.account_gap_profiles
   WHERE user_id = '35000000-0000-4000-8000-000000000002' AND shrinkage_k = 3),
  0.25::double precision,
  'the shrinkage weight is n/(n+k)'
);

SELECT is(
  (SELECT blended_pctl_minutes FROM public.account_gap_profiles
   WHERE user_id = '35000000-0000-4000-8000-000000000002' AND shrinkage_k = 3),
  518,
  'one sample of 1800 minutes against a fallback of 90 blends to 518, not to 1800'
);

SELECT is(
  (SELECT count(*)::integer FROM public.account_gap_profiles
   WHERE user_id = '35000000-0000-4000-8000-000000000002'),
  2,
  'calibrating k never destroys the previous run'
);

-- Run 3: lifting the consent gate is the only thing that admits the
-- unconsented account into its preset.
SELECT lives_ok(
  $$SELECT private.rebuild_account_gap_profiles(
      '2026-03-10'::date, 30, 7, 0.95, 1, 1, 90, false
    )$$,
  'the consent gate is a parameter, not a hard-coded assumption'
);

SELECT is(
  (SELECT cohort_source FROM public.account_gap_profiles
   WHERE user_id = '35000000-0000-4000-8000-000000000007' AND shrinkage_k = 7),
  'cohort',
  'with the consent gate lifted the same account does feed its preset'
);

SELECT ok(
  (SELECT count(*) FROM public.alerts) = (SELECT alerts FROM _live_before)
  AND (SELECT count(*) FROM public.alert_events) = (SELECT alert_events FROM _live_before)
  AND (SELECT count(*) FROM public.behavior_pings) = (SELECT behavior_pings FROM _live_before)
  AND (SELECT count(*) FROM public.device_state) = (SELECT device_state FROM _live_before)
  AND (SELECT count(*) FROM public.alert_gap_profiles) = (SELECT alert_gap_profiles FROM _live_before)
  AND (SELECT private.silence_threshold('35000000-0000-4000-8000-000000000001'))
      IS NOT DISTINCT FROM (SELECT live_threshold FROM _live_before),
  'three rebuilds change no live alert row and no live threshold'
);

SELECT * FROM finish();
ROLLBACK;
