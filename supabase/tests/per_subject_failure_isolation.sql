-- One account that cannot be computed must not stop the others.
--
-- On 2026-08-05 through 2026-08-08 the nightly rebuild aborted every night on a
-- single account with no usable signal, because the vestigial
-- live_threshold_minutes column was NOT NULL while ADR-0037 requires an account
-- without evidence to have no threshold at all. Every account's number froze at
-- 2026-08-04 and nothing reported it.
--
-- Fixing that column alone would have left the real defect in place: the
-- rebuild was one statement for all accounts, so any future per-account
-- condition could zero out everybody again. These tests are about the shape,
-- not that one column - the failure is injected deliberately with a constraint,
-- so the test still means something after the original trigger is long gone.

BEGIN;

SELECT plan(12);

-- Two accounts with real evidence, one with none at all.
INSERT INTO auth.users (id, email, aud, role) VALUES
  ('f1000000-0000-4000-8000-000000000001', 'iso-healthy-a@example.invalid', 'authenticated', 'authenticated'),
  ('f1000000-0000-4000-8000-000000000002', 'iso-healthy-b@example.invalid', 'authenticated', 'authenticated'),
  ('f1000000-0000-4000-8000-000000000003', 'iso-no-evidence@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, display_name) VALUES
  ('f1000000-0000-4000-8000-000000000001', 'ISO healthy A'),
  ('f1000000-0000-4000-8000-000000000002', 'ISO healthy B'),
  ('f1000000-0000-4000-8000-000000000003', 'ISO no evidence')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

-- Evidence for the two healthy accounts across the window ending 2026-08-08.
-- Regular pings an hour apart give each of them a computable upper bound.
INSERT INTO public.behavior_pings (user_id, at, received_at, ingest_version, kind)
SELECT
  u.id,
  '2026-08-01 00:00:00+00'::timestamptz + make_interval(hours => h),
  '2026-08-01 00:00:00+00'::timestamptz + make_interval(hours => h),
  2,
  'unlock'
FROM (VALUES
  ('f1000000-0000-4000-8000-000000000001'::uuid),
  ('f1000000-0000-4000-8000-000000000002'::uuid)
) AS u(id)
CROSS JOIN generate_series(0, 150) AS h;

-- Baseline: the rebuild completes and covers all three accounts.
SELECT lives_ok(
  $$ SELECT private.rebuild_account_normal_bounds('2026-08-08'::date) $$,
  'the rebuild completes with an account that has no evidence at all'
);

SELECT is(
  (SELECT count(*)::int FROM public.account_normal_bounds
    WHERE through_date = '2026-08-08'
      AND user_id::text LIKE 'f1000000%'),
  3,
  'every account gets a row, including the one that cannot be computed'
);

-- ADR-0037: no evidence means a recorded absence, not an invented number.
SELECT is(
  (SELECT threshold_minutes FROM public.account_normal_bounds
    WHERE user_id = 'f1000000-0000-4000-8000-000000000003' AND through_date = '2026-08-08'),
  NULL,
  'an account with no evidence has no threshold'
);

SELECT is(
  (SELECT has_usable_signal FROM public.account_normal_bounds
    WHERE user_id = 'f1000000-0000-4000-8000-000000000003' AND through_date = '2026-08-08'),
  false,
  'and says so explicitly rather than leaving it to be guessed'
);

SELECT isnt(
  (SELECT threshold_minutes FROM public.account_normal_bounds
    WHERE user_id = 'f1000000-0000-4000-8000-000000000001' AND through_date = '2026-08-08'),
  NULL,
  'an account with evidence still gets its own number'
);

-- The columns that caused the outage are gone, not merely relaxed. They
-- measured the old threshold against the new one, and the old threshold retired
-- on 2026-08-04, so the comparison had become the table against itself.
SELECT hasnt_column('public', 'account_normal_bounds', 'live_threshold_minutes',
  'the retired parallel-run column is dropped');
SELECT hasnt_column('public', 'account_normal_bounds', 'episodes_live',
  'and so is the count that depended on it');

-- account_threshold_shadow is a different table with the same column names and
-- a shadow that is still real. Dropping the wrong pair would have been silent.
SELECT has_column('public', 'account_threshold_shadow', 'live_threshold_minutes',
  'the genuine shadow table keeps its comparison columns');

SELECT has_table('private', 'job_failures',
  'a skipped subject has somewhere to be recorded');

-- Now the actual property. Reject one account at the storage layer and confirm
-- the others are still written and the rejection is recorded rather than lost.
DELETE FROM public.account_normal_bounds WHERE user_id::text LIKE 'f1000000%';

ALTER TABLE public.account_normal_bounds
  ADD CONSTRAINT iso_test_reject_one
  CHECK (user_id <> 'f1000000-0000-4000-8000-000000000002');

SELECT lives_ok(
  $$ SELECT private.rebuild_account_normal_bounds('2026-08-08'::date) $$,
  'one account failing at write time does not abort the run'
);

SELECT is(
  (SELECT count(*)::int FROM public.account_normal_bounds
    WHERE through_date = '2026-08-08'
      AND user_id::text LIKE 'f1000000%'),
  2,
  'the other accounts are still written - this is what four nights of outage cost'
);

SELECT is(
  (SELECT count(*)::int FROM private.job_failures
    WHERE job_name = 'rebuild_account_normal_bounds'
      AND subject_id = 'f1000000-0000-4000-8000-000000000002'),
  1,
  'and the skipped account is recorded, so isolation is not silent dropping'
);

ALTER TABLE public.account_normal_bounds DROP CONSTRAINT iso_test_reject_one;

SELECT * FROM finish();

ROLLBACK;
