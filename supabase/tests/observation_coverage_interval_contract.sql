-- ADR-0039 · The coverage-interval contract that coverage-valid learning rests on.
--
-- The single question this table answers is "were we actually watching?". If
-- that answer can be faked, widened, or read as yes by default, then every
-- downstream safety judgement is spending evidence it never had. These
-- assertions exist so that stays impossible.
BEGIN;

SELECT plan(14);

-- 1..4: the three axes exist and are separately answerable. They fail
-- independently — a phone can be collecting activity fine while notifications
-- are blocked — so collapsing them would let one blindness hide behind another
-- kind of sight.
SELECT has_table(
  'public', 'alert_observation_coverage_intervals',
  'observation coverage is recorded as bounded intervals'
);

SELECT has_column(
  'public', 'alert_observation_coverage_intervals', 'activity_coverage_state',
  'activity observability is its own axis'
);

SELECT has_column(
  'public', 'alert_observation_coverage_intervals', 'intervention_coverage_state',
  'reachability of the person is its own axis'
);

SELECT has_column(
  'public', 'alert_observation_coverage_intervals', 'sleep_context_state',
  'trustworthiness of sleep context is its own axis'
);

-- 5..7: each axis admits an explicit unknown. There is no boolean that would
-- force "not proven good" to be stored as "proven bad", or the reverse.
SELECT ok(
  (SELECT count(*)::integer
   FROM pg_constraint
   WHERE conrelid = 'public.alert_observation_coverage_intervals'::regclass
     AND contype = 'c'
     AND pg_get_constraintdef(oid) ~ 'activity_coverage_state'
     AND pg_get_constraintdef(oid) ~ '''valid'''
     AND pg_get_constraintdef(oid) ~ '''unknown''') = 1,
  'activity coverage is constrained to a vocabulary that includes unknown'
);

SELECT ok(
  (SELECT count(*)::integer
   FROM pg_constraint
   WHERE conrelid = 'public.alert_observation_coverage_intervals'::regclass
     AND contype = 'c'
     AND pg_get_constraintdef(oid) ~ 'intervention_coverage_state'
     AND pg_get_constraintdef(oid) ~ '''valid'''
     AND pg_get_constraintdef(oid) ~ '''unknown''') = 1,
  'intervention coverage is constrained to a vocabulary that includes unknown'
);

SELECT ok(
  (SELECT count(*)::integer
   FROM pg_constraint
   WHERE conrelid = 'public.alert_observation_coverage_intervals'::regclass
     AND contype = 'c'
     AND pg_get_constraintdef(oid) ~ 'sleep_context_state'
     AND pg_get_constraintdef(oid) ~ '''valid'''
     AND pg_get_constraintdef(oid) ~ '''unknown''') = 1,
  'sleep context is constrained to a vocabulary that includes unknown'
);

-- 8..10: privacy and authority. Coverage says where a person was observed and
-- by what, which is exactly the kind of record that must never be readable
-- through the Data API.
SELECT ok(
  (SELECT c.relrowsecurity
   FROM pg_class AS c
   JOIN pg_namespace AS n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public'
     AND c.relname = 'alert_observation_coverage_intervals'),
  'row level security is enabled on coverage intervals'
);

SELECT ok(
  NOT has_table_privilege('authenticated', 'public.alert_observation_coverage_intervals', 'SELECT')
  AND NOT has_table_privilege('authenticated', 'public.alert_observation_coverage_intervals', 'INSERT')
  AND NOT has_table_privilege('anon', 'public.alert_observation_coverage_intervals', 'SELECT')
  AND NOT has_table_privilege('anon', 'public.alert_observation_coverage_intervals', 'INSERT'),
  'no client role may read or write coverage intervals'
);

SELECT is(
  (SELECT count(*)::integer
   FROM pg_policies
   WHERE schemaname = 'public'
     AND tablename = 'alert_observation_coverage_intervals'),
  0,
  'there is no policy, because there is no client path to police'
);

-- 11..13: an interval is a claim about a bounded stretch of real time, and the
-- schema refuses claims that cannot be true.
SELECT throws_ok(
  $$
    INSERT INTO public.alert_observation_coverage_intervals (
      version_id, user_id, starts_at, ends_at, timezone, utc_offset_minutes,
      activity_coverage_state, intervention_coverage_state, sleep_context_state,
      captured_at, evidence_version, provenance_sha256
    ) VALUES (
      gen_random_uuid(), gen_random_uuid(),
      '2026-08-09 10:00+00', '2026-08-09 09:00+00',
      'UTC', 0, 'valid', 'valid', 'valid',
      '2026-08-09 09:00+00', 'canonical-v2', repeat('a', 64)
    )
  $$,
  '23514',
  NULL,
  'an interval cannot end before it starts'
);

SELECT throws_ok(
  $$
    INSERT INTO public.alert_observation_coverage_intervals (
      version_id, user_id, starts_at, ends_at, timezone, utc_offset_minutes,
      activity_coverage_state, intervention_coverage_state, sleep_context_state,
      captured_at, evidence_version, provenance_sha256
    ) VALUES (
      gen_random_uuid(), gen_random_uuid(),
      '2026-08-09 09:00+00', '2026-08-09 10:00+00',
      'UTC', 0, 'assumed_fine', 'valid', 'valid',
      '2026-08-09 10:00+00', 'canonical-v2', repeat('a', 64)
    )
  $$,
  '23514',
  NULL,
  'coverage state cannot be invented outside the accepted vocabulary'
);

SELECT throws_ok(
  $$
    INSERT INTO public.alert_observation_coverage_intervals (
      version_id, user_id, starts_at, ends_at, timezone, utc_offset_minutes,
      activity_coverage_state, intervention_coverage_state, sleep_context_state,
      captured_at, evidence_version, provenance_sha256
    ) VALUES (
      gen_random_uuid(), gen_random_uuid(),
      '2026-08-09 09:00+00', '2026-08-09 10:00+00',
      'UTC', 0, 'valid', 'valid', 'valid',
      '2026-08-09 10:00+00', 'canonical-v2', 'not-a-hash'
    )
  $$,
  '23514',
  NULL,
  'an interval must carry real provenance, not a placeholder'
);

-- 14: the default answer. A person with no interval at all is not covered, and
-- must never be counted as covered. This is the assertion the whole package
-- exists to protect.
SELECT is(
  (SELECT count(*)::integer
   FROM public.alert_observation_coverage_intervals
   WHERE user_id = '54000000-0000-4000-8000-000000000001'
     AND activity_coverage_state = 'valid'),
  0,
  'a person with no recorded interval has no valid coverage; absence is unknown, never yes'
);

SELECT * FROM finish();
ROLLBACK;
