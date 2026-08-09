BEGIN;

SELECT plan(6);

SELECT results_eq(
  $$
    WITH roles(role_name) AS (
      VALUES ('anon'::text), ('authenticated'::text), ('service_role'::text)
    ), tables(table_name) AS (
      VALUES
        ('account_gap_profiles'::text),
        ('account_normal_bounds'::text),
        ('account_threshold_shadow'::text),
        ('alert_gap_profiles'::text),
        ('alert_intervention_events'::text),
        ('alert_judgment_evaluations'::text),
        ('alert_judgment_shadow_decisions'::text),
        ('alert_judgment_subject_contexts'::text),
        ('alert_model_versions'::text),
        ('alert_observation_coverage_intervals'::text),
        ('alert_sleep_night_contexts'::text),
        ('routine_mode_cohort_generations'::text),
        ('routine_mode_cohort_invalidations'::text),
        ('routine_mode_cohort_priors'::text)
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
      ('account_gap_profiles'::text),
      ('account_normal_bounds'::text),
      ('account_threshold_shadow'::text),
      ('alert_gap_profiles'::text),
      ('alert_intervention_events'::text),
      ('alert_judgment_evaluations'::text),
      ('alert_judgment_shadow_decisions'::text),
      ('alert_judgment_subject_contexts'::text),
      ('alert_model_versions'::text),
      ('alert_observation_coverage_intervals'::text),
      ('alert_sleep_night_contexts'::text),
      ('routine_mode_cohort_generations'::text),
      ('routine_mode_cohort_invalidations'::text),
      ('routine_mode_cohort_priors'::text)
    ) tables(table_name)
    ORDER BY role_name, table_name
  $$,
  'S2-ACL-01 internal operational tables expose no Data API table action'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
    WHERE n.nspname = 'public'
      AND c.relname IN (
        'account_gap_profiles', 'account_normal_bounds', 'account_threshold_shadow',
        'alert_gap_profiles', 'alert_intervention_events', 'alert_judgment_evaluations',
        'alert_judgment_shadow_decisions', 'alert_judgment_subject_contexts',
        'alert_model_versions', 'alert_observation_coverage_intervals',
        'alert_sleep_night_contexts', 'routine_mode_cohort_generations',
        'routine_mode_cohort_invalidations', 'routine_mode_cohort_priors'
      )
      AND acl.grantee = 0
  ),
  'S2-ACL-02 internal operational tables expose no PUBLIC privilege'
);

SELECT results_eq(
  $$
    WITH roles(role_name) AS (
      VALUES ('anon'::text), ('authenticated'::text), ('service_role'::text)
    ), actions(privilege_name) AS (
      VALUES
        ('DELETE'::text), ('INSERT'::text), ('MAINTAIN'::text), ('REFERENCES'::text),
        ('SELECT'::text), ('TRIGGER'::text), ('TRUNCATE'::text), ('UPDATE'::text)
    )
    SELECT role_name,
      string_agg(privilege_name, ',' ORDER BY privilege_name)
        FILTER (WHERE has_table_privilege(role_name, 'public.gm_mutes', privilege_name))
        AS privileges
    FROM roles CROSS JOIN actions
    GROUP BY role_name
    ORDER BY role_name
  $$,
  $$ VALUES
    ('anon'::text, NULL::text),
    ('authenticated'::text, NULL::text),
    ('service_role'::text, NULL::text)
  $$,
  'S2-ACL-03 GM mute storage is RPC-only for Data API roles'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_class c
    CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
    WHERE c.oid = 'public.gm_mutes'::regclass
      AND acl.grantee = 0
  ),
  'S2-ACL-04 GM mute storage exposes no PUBLIC privilege'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname IN (
        'account_gap_profiles', 'account_normal_bounds', 'account_threshold_shadow',
        'alert_gap_profiles', 'alert_intervention_events', 'alert_judgment_evaluations',
        'alert_judgment_shadow_decisions', 'alert_judgment_subject_contexts',
        'alert_model_versions', 'alert_observation_coverage_intervals',
        'alert_sleep_night_contexts', 'routine_mode_cohort_generations',
        'routine_mode_cohort_invalidations', 'routine_mode_cohort_priors', 'gm_mutes'
      )
      AND c.relrowsecurity
  ),
  15,
  'S2-ACL-05 all repaired tables retain RLS'
);

SELECT ok(
  has_function_privilege(
    'authenticated',
    'public.gm_mute_user(uuid,timestamptz,text)',
    'EXECUTE'
  ),
  'S2-ACL-06 authenticated callers retain the GM-gated mute RPC'
);

SELECT * FROM finish();
ROLLBACK;
