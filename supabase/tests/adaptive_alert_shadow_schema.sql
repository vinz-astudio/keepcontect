BEGIN;

SELECT plan(63);

INSERT INTO auth.users (id, email, aud, role)
VALUES (
  '41000000-0000-0000-0000-000000000002',
  'shadow-schema-owner@example.invalid',
  'authenticated',
  'authenticated'
)
ON CONFLICT (id) DO NOTHING;

SELECT has_table('public', 'alert_model_versions', 'versioned candidate models have a table');
SELECT has_table('public', 'alert_gap_profiles', 'derived personal gaps have a table');
SELECT has_table('public', 'routine_mode_cohort_priors', 'aggregate routine priors have a table');
SELECT has_table('public', 'alert_judgment_shadow_decisions', 'shadow decisions have a table');
SELECT has_table('public', 'alert_judgment_evaluations', 'aggregate evaluations have a table');

SELECT col_is_pk('public', 'alert_model_versions', 'id', 'model version id is the primary key');
SELECT has_column('public', 'alert_gap_profiles', 'context_key', 'gap profile includes its comparable context');
SELECT has_column('public', 'alert_gap_profiles', 'distinct_support_dates', 'gap profile records distinct support dates');
SELECT has_column('public', 'alert_gap_profiles', 'support_started_on', 'gap profile records support start');
SELECT has_column('public', 'alert_gap_profiles', 'support_ended_on', 'gap profile records support end');
SELECT has_column('public', 'alert_gap_profiles', 'latest_evidence_at', 'gap profile records evidence freshness');
SELECT has_column('public', 'routine_mode_cohort_priors', 'contributor_count', 'cohort prior includes aggregate contributor support');
SELECT has_column('public', 'routine_mode_cohort_priors', 'distinct_support_dates', 'cohort prior records aggregate support dates');
SELECT has_column('public', 'routine_mode_cohort_priors', 'support_started_on', 'cohort prior records support start');
SELECT has_column('public', 'routine_mode_cohort_priors', 'support_ended_on', 'cohort prior records support end');
SELECT has_column('public', 'routine_mode_cohort_priors', 'latest_evidence_at', 'cohort prior records evidence freshness');
SELECT has_column('public', 'routine_mode_cohort_priors', 'config_sha256', 'cohort prior binds its model configuration');
SELECT has_column('public', 'routine_mode_cohort_priors', 'evidence_version', 'cohort prior identifies its evidence contract');
SELECT has_column('public', 'routine_mode_cohort_priors', 'published_at', 'cohort prior records publication for invalidation');
SELECT has_column('public', 'alert_judgment_shadow_decisions', 'fallback_path', 'shadow decision records its hierarchy path');
SELECT has_column('public', 'alert_judgment_shadow_decisions', 'evaluator_version', 'shadow decision identifies its evaluator');
SELECT has_column('public', 'alert_judgment_shadow_decisions', 'provenance_sha256', 'shadow decision hashes provenance');
SELECT has_column('public', 'alert_judgment_shadow_decisions', 'evidence_cutoff', 'shadow decision records the recorder evidence cutoff');
SELECT has_column('public', 'alert_judgment_shadow_decisions', 'unclamped_candidate_threshold_minutes', 'shadow decision records the pre-clamp candidate threshold');
SELECT has_column('public', 'alert_judgment_shadow_decisions', 'candidate_floor_minutes', 'shadow decision records the applied candidate floor');
SELECT has_column('public', 'alert_judgment_shadow_decisions', 'candidate_ceiling_minutes', 'shadow decision records the applied candidate ceiling');
SELECT has_column('public', 'alert_judgment_shadow_decisions', 'candidate_cap_reason', 'shadow decision records why the candidate was capped');
SELECT has_column('public', 'alert_judgment_shadow_decisions', 'deadline_basis', 'shadow decision records how its deadline was derived');
SELECT has_column('public', 'alert_judgment_shadow_decisions', 'selected_source_sha256', 'shadow decision records its nullable selected source hash');
SELECT has_column('public', 'alert_judgment_shadow_decisions', 'subject_context_sha256', 'shadow decision binds its subject context hash');
SELECT has_column('public', 'alert_judgment_shadow_decisions', 'decision_provenance', 'shadow decision stores its canonical provenance object');
SELECT has_column('public', 'alert_judgment_shadow_decisions', 'decision_sha256', 'shadow decision hashes its complete canonical decision');
SELECT has_column('public', 'alert_judgment_evaluations', 'evaluation_kind', 'evaluation identifies its aggregate kind');
SELECT has_column('public', 'alert_judgment_evaluations', 'evaluated_from', 'evaluation records its lower bound');
SELECT has_column('public', 'alert_judgment_evaluations', 'evaluated_to', 'evaluation records its upper bound');
SELECT has_column('public', 'alert_judgment_evaluations', 'input_sha256', 'evaluation hashes its input');
SELECT has_column('public', 'alert_judgment_evaluations', 'output_sha256', 'evaluation hashes its output');
SELECT has_column('public', 'alert_judgment_evaluations', 'evaluator_version', 'evaluation identifies its evaluator');
SELECT hasnt_column('public', 'routine_mode_cohort_priors', 'user_id', 'cohort priors never retain membership identity');
SELECT hasnt_column('public', 'alert_judgment_evaluations', 'user_id', 'evaluations stay aggregate-only');

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.alert_judgment_shadow_decisions'::regclass
      AND conname = 'alert_judgment_shadow_decisions_check'
  ),
  'the invalid final-threshold-at-least-neutral constraint is removed'
);
SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.alert_judgment_shadow_decisions'::regclass
      AND conname =
        'alert_judgment_shadow_decisions_candidate_threshold_nonnegative'
      AND pg_get_constraintdef(oid) !~ 'neutral_threshold_minutes'
  ),
  'the replacement final-threshold check preserves non-negativity without a neutral lower bound'
);
SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.alert_judgment_shadow_decisions'::regclass
      AND conname = 'alert_judgment_shadow_decisions_candidate_cap_contract'
  ),
  'the decision table pins the evaluator cap-reason contract'
);
SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.alert_judgment_shadow_decisions'::regclass
      AND conname =
        'alert_judgment_shadow_decisions_decision_provenance_check'
  ),
  'the decision table validates canonical decision provenance'
);

SELECT ok(
  (
    SELECT count(*) = 5 AND bool_and(c.relrowsecurity)
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname IN (
        'alert_model_versions',
        'alert_gap_profiles',
        'routine_mode_cohort_priors',
        'alert_judgment_shadow_decisions',
        'alert_judgment_evaluations'
      )
  ),
  'every shadow-only table has RLS enabled'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_policy p
    JOIN pg_class c ON c.oid = p.polrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname IN (
        'alert_model_versions', 'alert_gap_profiles', 'routine_mode_cohort_priors',
        'alert_judgment_shadow_decisions', 'alert_judgment_evaluations'
      )
  ),
  0,
  'shadow boundary has no RLS policy until a separately approved UI contract exists'
);

SELECT results_eq(
  $$
    WITH roles(role_name) AS (
      VALUES ('anon'::text), ('authenticated'::text), ('service_role'::text)
    ), tables(table_name) AS (
      VALUES
        ('alert_model_versions'::text),
        ('alert_gap_profiles'::text),
        ('routine_mode_cohort_priors'::text),
        ('alert_judgment_shadow_decisions'::text),
        ('alert_judgment_evaluations'::text)
    ), actions(privilege_name) AS (
      VALUES
        ('DELETE'::text), ('INSERT'::text), ('MAINTAIN'::text), ('REFERENCES'::text),
        ('SELECT'::text), ('TRIGGER'::text), ('TRUNCATE'::text), ('UPDATE'::text)
    )
    SELECT role_name, table_name,
      string_agg(privilege_name, ',' ORDER BY privilege_name)
        FILTER (WHERE has_table_privilege(role_name, format('public.%I', table_name), privilege_name))
        AS privileges
    FROM roles CROSS JOIN tables CROSS JOIN actions
    GROUP BY role_name, table_name
    ORDER BY role_name, table_name
  $$,
  $$
    SELECT role_name, table_name, NULL::text
    FROM (VALUES ('anon'::text), ('authenticated'::text), ('service_role'::text)) roles(role_name)
    CROSS JOIN (VALUES
      ('alert_model_versions'::text), ('alert_gap_profiles'::text), ('routine_mode_cohort_priors'::text),
      ('alert_judgment_shadow_decisions'::text), ('alert_judgment_evaluations'::text)
    ) tables(table_name)
    ORDER BY role_name, table_name
  $$,
  'shadow boundary grants no table action to any Data API role or PUBLIC'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
    WHERE n.nspname = 'public'
      AND c.relname IN (
        'alert_model_versions', 'alert_gap_profiles', 'routine_mode_cohort_priors',
        'alert_judgment_shadow_decisions', 'alert_judgment_evaluations'
      )
      AND acl.grantee = 0
  ),
  'PUBLIC has no direct table privilege on the shadow boundary'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM information_schema.column_privileges
    WHERE table_schema = 'public'
      AND table_name IN (
        'alert_model_versions', 'alert_gap_profiles', 'routine_mode_cohort_priors',
        'alert_judgment_shadow_decisions', 'alert_judgment_evaluations'
      )
      AND grantee IN ('PUBLIC', 'anon', 'authenticated', 'service_role')
  ),
  'shadow boundary grants no column privilege'
);

SET LOCAL ROLE anon;
SELECT throws_ok($$ SELECT * FROM public.alert_model_versions $$, '42501'::char(5), NULL,
  'anonymous callers cannot select candidate versions directly');
SELECT throws_ok($$ INSERT INTO public.alert_model_versions (name, status, config, config_sha256, evidence_version) VALUES ('forbidden-anon', 'draft', '{}'::jsonb, repeat('2', 64), 'canonical-v2') $$, '42501'::char(5), NULL,
  'anonymous callers cannot insert candidate versions directly');

SET LOCAL ROLE authenticated;
SELECT throws_ok($$ SELECT * FROM public.alert_model_versions $$, '42501'::char(5), NULL,
  'authenticated callers cannot select candidate versions directly');
SELECT throws_ok($$ INSERT INTO public.alert_model_versions (name, status, config, config_sha256, evidence_version) VALUES ('forbidden-authenticated', 'draft', '{}'::jsonb, repeat('0', 64), 'canonical-v2') $$, '42501'::char(5), NULL,
  'authenticated callers cannot insert candidate versions directly');

SET LOCAL ROLE service_role;
SELECT throws_ok($$ SELECT * FROM public.alert_model_versions $$, '42501'::char(5), NULL,
  'service-role Data API callers cannot select private candidate versions directly');
SELECT throws_ok($$ INSERT INTO public.alert_model_versions (name, status, config, config_sha256, evidence_version) VALUES ('forbidden-service', 'draft', '{}'::jsonb, repeat('1', 64), 'canonical-v2') $$, '42501'::char(5), NULL,
  'service-role Data API callers cannot insert candidate versions directly');

RESET ROLE;
SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_constraint fk
    JOIN pg_class child ON child.oid = fk.conrelid
    JOIN pg_namespace child_ns ON child_ns.oid = child.relnamespace
    JOIN pg_class parent ON parent.oid = fk.confrelid
    JOIN pg_namespace parent_ns ON parent_ns.oid = parent.relnamespace
    WHERE fk.contype = 'f'
      AND (
        child_ns.nspname = 'public'
        AND child.relname IN (
        'alert_model_versions', 'alert_gap_profiles', 'routine_mode_cohort_priors',
        'alert_judgment_shadow_decisions', 'alert_judgment_evaluations'
        )
        AND parent_ns.nspname = 'public'
        AND parent.relname IN ('alerts', 'alert_events', 'notifications')
      ) OR (
        parent_ns.nspname = 'public'
        AND parent.relname IN (
          'alert_model_versions', 'alert_gap_profiles', 'routine_mode_cohort_priors',
          'alert_judgment_shadow_decisions', 'alert_judgment_evaluations'
        )
        AND child_ns.nspname = 'public'
        AND child.relname IN ('alerts', 'alert_events', 'notifications')
      )
  ),
  'no shadow table references a live alert or notification table'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname IN (
        'alert_model_versions', 'routine_mode_cohort_priors',
        'alert_judgment_shadow_decisions', 'alert_judgment_evaluations'
      )
      AND NOT t.tgisinternal
  ),
  'published shadow tables have no non-internal trigger path; profile-derived evidence may invalidate cohort generations'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename IN (
        'alert_model_versions', 'alert_gap_profiles', 'routine_mode_cohort_priors',
        'alert_judgment_shadow_decisions', 'alert_judgment_evaluations'
      )
  ),
  'shadow tables are not published to realtime'
);

SELECT results_eq(
  $$
    SELECT jobname, schedule
    FROM cron.job
    WHERE lower(command) ~ '(adaptive|candidate|shadow|replay)'
       OR lower(jobname) ~ '(adaptive|candidate|shadow|replay)'
    ORDER BY jobname
  $$,
  $$
    VALUES
      ('account-shadow-cycle-v1'::text, '37 2 * * *'::text),
      ('adaptive-alert-shadow-cycle-v1'::text, '*/5 * * * *'::text),
      ('adaptive-alert-shadow-maintenance-v1'::text, '17 2 * * *'::text)
  $$,
  'shadow-family cron is exactly the three accepted jobs and nothing else'
);

CREATE TEMP TABLE shadow_live_snapshot AS
SELECT
  (SELECT count(*)::bigint FROM public.alerts) AS alerts_count,
  (SELECT coalesce(md5(string_agg(to_jsonb(a)::text, ',' ORDER BY a.id)), '') FROM public.alerts a) AS alerts_hash,
  (SELECT count(*)::bigint FROM public.alert_events) AS alert_events_count,
  (SELECT coalesce(md5(string_agg(to_jsonb(e)::text, ',' ORDER BY e.id)), '') FROM public.alert_events e) AS alert_events_hash,
  (SELECT count(*)::bigint FROM public.notifications) AS notifications_count,
  (SELECT coalesce(md5(string_agg(to_jsonb(n)::text, ',' ORDER BY n.id)), '') FROM public.notifications n) AS notifications_hash,
  (SELECT count(*)::bigint FROM public.behavior_pings) AS behavior_pings_count,
  (SELECT coalesce(md5(string_agg(to_jsonb(b)::text, ',' ORDER BY b.id)), '') FROM public.behavior_pings b) AS behavior_pings_hash,
  (SELECT count(*)::bigint FROM public.device_state) AS device_state_count,
  (SELECT coalesce(md5(string_agg(to_jsonb(d)::text, ',' ORDER BY d.user_id)), '') FROM public.device_state d) AS device_state_hash,
  (SELECT count(*)::bigint FROM public.checkin_tasks) AS checkin_tasks_count,
  (SELECT coalesce(md5(string_agg(to_jsonb(c)::text, ',' ORDER BY c.id)), '') FROM public.checkin_tasks c) AS checkin_tasks_hash;

-- ADR-0028/ADR-0038: a fresh base ships no model version at all. Seeding one is
-- an environment activation step, so this file creates its own below rather
-- than inheriting a migration-seeded row.
SELECT is(
  (SELECT count(*)::integer FROM public.alert_model_versions),
  0,
  'fresh base seeds no shadow model version'
);

INSERT INTO public.alert_model_versions (id, name, status, config, config_sha256, evidence_version)
VALUES (
  '41000000-0000-0000-0000-000000000001',
  'shadow-schema-test',
  'draft',
  '{"sessionization":{"gap_minutes":30,"per_user_day_gap_cap":8,"training_horizon_days":30,"intervention_window_minutes":30},"context":{"definition_version":"shadow-schema-test-v1","day_partition":"all_days","hour_bucket_minutes":60},"personal":{"min_samples":3,"min_support_dates":2,"min_span_days":2,"max_age_days":30,"min_confidence":0.7,"confidence_formula_version":"support_ratio_v1"},"cohort":{"min_contributors":3,"min_support_dates":2,"min_span_days":2,"max_age_days":30,"min_confidence":0.5,"contribution_floor_minutes":1,"contribution_ceiling_minutes":600,"confidence_formula_version":"cohort_support_min_v1","algorithm":"trimmed_mean","trim_fraction":0.1},"sensitivity_buffers_minutes":{"high":0,"balanced":45,"low":90},"candidate_bounds":{"floor_minutes":1,"ceiling_minutes":600},"sleep_compensation":{"max_start_delay_minutes":60,"max_wake_advance_minutes":60,"max_wake_delay_minutes":60,"max_update_minutes_per_day":30,"min_positive_nights":2,"lookback_nights":3,"min_late_events_per_night":1,"timezone_tolerance_minutes":30},"evaluator":{"contract_version":"adaptive_candidate_v1"},"emergency":{"contract_version":"adr0022_v1","neutral_minutes":90,"expected_live_definition_sha256":"c3efc6cc664dc334166a034651ff584d4c7766d80775c3fe3bc012eb97a9b150"}}'::jsonb,
  repeat('a', 64),
  'canonical-v2'
);

WITH gap_profile AS (
      INSERT INTO public.alert_gap_profiles (
        version_id, user_id, context_key, through_date, neutral_p95_minutes,
        sample_count, distinct_support_dates, support_started_on, support_ended_on,
        latest_evidence_at, quality_state, confidence,
        profile_sha256
      ) VALUES (
        '41000000-0000-0000-0000-000000000001',
        '41000000-0000-0000-0000-000000000002', 'global', '2026-07-26', 120,
        3, 2, '2026-07-25', '2026-07-26', '2026-07-26 10:00+00',
        'valid', 0.9, repeat('b', 64)
      )
    ), cohort_prior AS (
      INSERT INTO public.routine_mode_cohort_priors (
        version_id, routine_mode, context_key, through_date, contributor_count,
        distinct_support_dates, support_started_on, support_ended_on,
        latest_evidence_at, neutral_p95_minutes, quality_state, confidence,
        algorithm, config_sha256, evidence_version, input_sha256, prior_sha256
      ) VALUES (
        '41000000-0000-0000-0000-000000000001', 'regular_9to5', 'global',
        '2026-07-26', 3, 2, '2026-07-25', '2026-07-26',
        '2026-07-26 10:00+00', 120, 'valid', 0.9, 'trimmed_mean',
        repeat('c', 64), 'canonical-v2', repeat('d', 64), repeat('e', 64)
      )
    ), evaluation AS (
      INSERT INTO public.alert_judgment_evaluations (
        version_id, evaluation_kind, evaluated_from, evaluated_to, metrics,
        input_sha256, output_sha256, evaluator_version
      ) VALUES (
        '41000000-0000-0000-0000-000000000001', 'historical_replay',
        '2026-07-25 00:00+00', '2026-07-26 00:00+00',
        '{"would_alert_count":1}'::jsonb, repeat('f', 64), repeat('0', 64),
        'shadow-schema-test-v1'
      )
    ), decision AS (
      INSERT INTO public.alert_judgment_shadow_decisions (
        version_id, user_id, evaluated_at, basis, evaluator_version, context_key,
      neutral_threshold_minutes, sensitivity_buffer_minutes, candidate_threshold_minutes,
      effective_silence_minutes, candidate_deadline, would_alert, confidence, quality_state,
       fallback_path, sleep_interval_provenance, provenance_sha256, guardian_used_as_activity,
       evidence_cutoff, unclamped_candidate_threshold_minutes, candidate_floor_minutes,
       candidate_ceiling_minutes, candidate_cap_reason, deadline_basis,
       selected_source_sha256, subject_context_sha256, decision_provenance, decision_sha256
    ) VALUES (
      '41000000-0000-0000-0000-000000000001',
      '41000000-0000-0000-0000-000000000002',
      '2026-07-26 12:34:56+00',
       'deterministic_emergency', 'shadow-schema-test-v1', 'global', 90, 0, 90, 91,
      '2026-07-26 12:33:00+00', true, 0.1, 'low_support',
       ARRAY['deterministic_emergency']::text[], '[]'::jsonb,
       encode(extensions.digest('{}'::jsonb::text, 'sha256'), 'hex'), false,
       '2026-07-26 12:33:00+00', 90, 1, 600, 'emergency_exempt', 'no_future_exclusion',
       NULL, repeat('2', 64), '{}'::jsonb, repeat('3', 64)
    ) RETURNING evaluated_minute
    )
SELECT is(
  (SELECT evaluated_minute FROM decision),
  '2026-07-26 12:34:00+00'::timestamptz,
  'representative owner DML stores the UTC-truncated shadow minute'
);

SELECT results_eq(
  $$
    SELECT
      evidence_cutoff,
      unclamped_candidate_threshold_minutes,
      candidate_floor_minutes,
      candidate_ceiling_minutes,
      candidate_cap_reason,
      deadline_basis,
      selected_source_sha256,
      subject_context_sha256,
      decision_provenance,
      decision_sha256
    FROM public.alert_judgment_shadow_decisions
    WHERE version_id = '41000000-0000-0000-0000-000000000001'
  $$,
  $$
    VALUES (
      '2026-07-26 12:33:00+00'::timestamptz,
      90,
      1,
      600,
      'emergency_exempt'::text,
      'no_future_exclusion'::text,
      NULL::text,
      repeat('2', 64),
      '{}'::jsonb,
      repeat('3', 64)
    )
  $$,
  'representative owner DML preserves every appended non-null decision field'
);

SELECT results_eq(
  $$
    SELECT * FROM shadow_live_snapshot
    EXCEPT
    SELECT
      (SELECT count(*)::bigint FROM public.alerts),
      (SELECT coalesce(md5(string_agg(to_jsonb(a)::text, ',' ORDER BY a.id)), '') FROM public.alerts a),
      (SELECT count(*)::bigint FROM public.alert_events),
      (SELECT coalesce(md5(string_agg(to_jsonb(e)::text, ',' ORDER BY e.id)), '') FROM public.alert_events e),
      (SELECT count(*)::bigint FROM public.notifications),
      (SELECT coalesce(md5(string_agg(to_jsonb(n)::text, ',' ORDER BY n.id)), '') FROM public.notifications n),
      (SELECT count(*)::bigint FROM public.behavior_pings),
      (SELECT coalesce(md5(string_agg(to_jsonb(b)::text, ',' ORDER BY b.id)), '') FROM public.behavior_pings b),
      (SELECT count(*)::bigint FROM public.device_state),
      (SELECT coalesce(md5(string_agg(to_jsonb(d)::text, ',' ORDER BY d.user_id)), '') FROM public.device_state d),
      (SELECT count(*)::bigint FROM public.checkin_tasks),
      (SELECT coalesce(md5(string_agg(to_jsonb(c)::text, ',' ORDER BY c.id)), '') FROM public.checkin_tasks c)
  $$,
  $$ SELECT * FROM shadow_live_snapshot WHERE false $$,
  'representative shadow owner DML leaves all live alert-path counts and hashes unchanged'
);

SELECT * FROM finish();
ROLLBACK;
