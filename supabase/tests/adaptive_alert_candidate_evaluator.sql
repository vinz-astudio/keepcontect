BEGIN;

SELECT plan(79);

-- Task 6 is an owner-only, prospective snapshot/evaluator boundary.
SELECT has_table('public', 'alert_judgment_subject_contexts',
  'prospective as-of subject contexts have a table');
SELECT has_column('public', 'alert_judgment_subject_contexts', 'effective_from',
  'subject context stores its half-open lower bound');
SELECT has_column('public', 'alert_judgment_subject_contexts', 'effective_to',
  'subject context stores its half-open upper bound');
SELECT has_column('public', 'alert_judgment_subject_contexts', 'raw_sensitivity',
  'subject context preserves raw sensitivity');
SELECT has_column('public', 'alert_judgment_subject_contexts', 'canonical_sensitivity',
  'subject context stores canonical sensitivity');
SELECT has_column('public', 'alert_judgment_subject_contexts', 'routine_mode',
  'subject context stores canonical Routine mode');
SELECT has_column('public', 'alert_judgment_subject_contexts', 'subject_context_sha256',
  'subject context binds deterministic provenance');
SELECT has_column('public', 'alert_gap_profiles', 'config_sha256',
  'personal profiles pin their source config');
SELECT has_column('public', 'alert_gap_profiles', 'evidence_version',
  'personal profiles pin their evidence contract');
SELECT has_function(
  'private', 'resolve_alert_candidate',
  ARRAY['uuid', 'timestamp with time zone', 'uuid'],
  'locked candidate evaluator signature exists'
);
SELECT ok(
  (SELECT relrowsecurity
   FROM pg_class
   WHERE oid = 'public.alert_judgment_subject_contexts'::regclass),
  'subject contexts have RLS'
);
SELECT is(
  (SELECT count(*)::integer
   FROM pg_policy
   WHERE polrelid = 'public.alert_judgment_subject_contexts'::regclass),
  0,
  'subject contexts have no Data API policy'
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
        FILTER (
          WHERE has_table_privilege(
            role_name,
            'public.alert_judgment_subject_contexts',
            privilege_name
          )
        )
    FROM roles CROSS JOIN actions
    GROUP BY role_name
    ORDER BY role_name
  $$,
  $$ VALUES
    ('anon'::text, NULL::text),
    ('authenticated'::text, NULL::text),
    ('service_role'::text, NULL::text)
  $$,
  'subject contexts expose zero table action to Data API roles'
);
SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_class c
    CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
    WHERE c.oid = 'public.alert_judgment_subject_contexts'::regclass
      AND acl.grantee = 0
  ),
  'PUBLIC has no subject-context table privilege'
);
SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM information_schema.column_privileges
    WHERE table_schema = 'public'
      AND table_name = 'alert_judgment_subject_contexts'
      AND grantee IN ('PUBLIC', 'anon', 'authenticated', 'service_role')
  ),
  'subject contexts expose no Data API column privilege'
);
SELECT function_privs_are(
  'private', 'resolve_alert_candidate',
  ARRAY['uuid', 'timestamp with time zone', 'uuid'],
  'anon', ARRAY[]::text[]
);
SELECT function_privs_are(
  'private', 'resolve_alert_candidate',
  ARRAY['uuid', 'timestamp with time zone', 'uuid'],
  'authenticated', ARRAY[]::text[]
);
SELECT function_privs_are(
  'private', 'resolve_alert_candidate',
  ARRAY['uuid', 'timestamp with time zone', 'uuid'],
  'service_role', ARRAY[]::text[]
);
SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    WHERE p.oid =
      'private.resolve_alert_candidate(uuid,timestamptz,uuid)'::regprocedure
      AND acl.grantee = 0
  ),
  'PUBLIC cannot execute the evaluator'
);
SELECT ok(
  (
    SELECT p.prosecdef
      AND p.provolatile = 's'
      AND p.proconfig @> ARRAY['search_path=""', 'TimeZone=UTC']
      AND r.rolname = current_user
    FROM pg_proc p
    JOIN pg_roles r ON r.oid = p.proowner
    WHERE p.oid =
      'private.resolve_alert_candidate(uuid,timestamptz,uuid)'::regprocedure
  ),
  'evaluator is owner-only STABLE SECURITY DEFINER with empty path and UTC'
);
SELECT is(
  (SELECT count(*)::integer
   FROM public.alert_judgment_subject_contexts),
  0,
  'Task 6 seeds or backfills no subject context'
);
SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid = 'public.alert_judgment_subject_contexts'::regclass
      AND NOT tgisinternal
  ),
  'subject context has no producer trigger'
);
SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'alert_judgment_subject_contexts'
  ),
  'subject context is not realtime'
);
SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM cron.job
    WHERE lower(command) ~ '(resolve_alert_candidate|subject_context)'
       OR lower(jobname) ~ '(resolve_alert_candidate|subject_context)'
  ),
  'Task 6 schedules no evaluator or context capture'
);

-- The contract-bearing config is valid but is not seeded by a migration.
CREATE TEMP TABLE candidate_eval_base_config AS
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
    "expected_live_definition_sha256":"1907d59473d274d46a0e8e0b9ce8027037b4494b0dddf073cb46abf67db92e21"
  }
}'::jsonb AS config;

INSERT INTO public.alert_model_versions (
  id, name, status, config, config_sha256, evidence_version
)
SELECT fixture.id, fixture.name, fixture.status, fixture.config,
  encode(extensions.digest(fixture.config::text, 'sha256'), 'hex'),
  fixture.evidence_version
FROM candidate_eval_base_config base
CROSS JOIN LATERAL (
  VALUES
    (
      '46000000-0000-0000-0000-000000000010'::uuid,
      'candidate-evaluator-main'::text,
      'replay'::text,
      base.config,
      'canonical-v2'::text
    ),
    (
      '46000000-0000-0000-0000-000000000020'::uuid,
      'candidate-evaluator-bounded'::text,
      'replay'::text,
      jsonb_set(
        jsonb_set(base.config, '{candidate_bounds,floor_minutes}', '100'::jsonb),
        '{candidate_bounds,ceiling_minutes}', '150'::jsonb
      ),
      'canonical-v2'::text
    ),
    (
      '46000000-0000-0000-0000-000000000030'::uuid,
      'candidate-evaluator-draft'::text,
      'draft'::text,
      base.config,
      'canonical-v2'::text
    ),
    (
      '46000000-0000-0000-0000-000000000040'::uuid,
      'candidate-evaluator-bad-hash'::text,
      'replay'::text,
      base.config,
      'canonical-v2'::text
    ),
    (
      '46000000-0000-0000-0000-000000000050'::uuid,
      'candidate-evaluator-unsupported-evidence'::text,
      'replay'::text,
      base.config,
      'canonical-v3'::text
    )
) AS fixture(id, name, status, config, evidence_version);

UPDATE public.alert_model_versions
SET config_sha256 = repeat('f', 64)
WHERE id = '46000000-0000-0000-0000-000000000040';

-- Simulate contract-corrupt pre-Task-6 rows whose stored hashes are canonical.
-- The NOT VALID constraint protects new writes; the evaluator must also reject
-- legacy rows where a required scalar is absent or the evaluator object is malformed.
CREATE TEMP TABLE candidate_eval_contract_constraints AS
SELECT conname, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.alert_model_versions'::regclass
  AND contype = 'c';

DO $$
DECLARE
  _r record;
BEGIN
  FOR _r IN SELECT * FROM candidate_eval_contract_constraints LOOP
    EXECUTE format('ALTER TABLE public.alert_model_versions DROP CONSTRAINT IF EXISTS %I', _r.conname);
  END LOOP;
END;
$$;

INSERT INTO public.alert_model_versions (
  id, name, status, config, config_sha256, evidence_version
)
SELECT fixture.id, fixture.name, 'replay', fixture.config,
  encode(extensions.digest(fixture.config::text, 'sha256'), 'hex'),
  'canonical-v2'
FROM candidate_eval_base_config base
CROSS JOIN LATERAL (
  VALUES
    (
      '46000000-0000-0000-0000-000000000060'::uuid,
      'candidate-evaluator-missing-personal-key'::text,
      base.config #- '{personal,min_confidence}'
    ),
    (
      '46000000-0000-0000-0000-000000000061'::uuid,
      'candidate-evaluator-missing-sessionization-key'::text,
      base.config #- '{sessionization,gap_minutes}'
    ),
    (
      '46000000-0000-0000-0000-000000000062'::uuid,
      'candidate-evaluator-wrong-json-type-string'::text,
      jsonb_set(base.config, '{personal,min_confidence}', '"0.7"'::jsonb)
    ),
    (
      '46000000-0000-0000-0000-000000000063'::uuid,
      'candidate-evaluator-negative-horizon'::text,
      jsonb_set(base.config, '{sessionization,training_horizon_days}', '-1'::jsonb)
    ),
    (
      '46000000-0000-0000-0000-000000000064'::uuid,
      'candidate-evaluator-non-integral-horizon'::text,
      jsonb_set(base.config, '{sessionization,training_horizon_days}', '30.5'::jsonb)
    ),
    (
      '46000000-0000-0000-0000-000000000065'::uuid,
      'candidate-evaluator-invalid-context-enum'::text,
      jsonb_set(base.config, '{context,day_partition}', '"invalid_partition"'::jsonb)
    ),
    (
      '46000000-0000-0000-0000-000000000066'::uuid,
      'candidate-evaluator-out-of-range-trim-fraction'::text,
      jsonb_set(base.config, '{cohort,trim_fraction}', '0.6'::jsonb)
    ),
    (
      '46000000-0000-0000-0000-000000000067'::uuid,
      'candidate-evaluator-invalid-sensitivity-buffer'::text,
      jsonb_set(base.config, '{sensitivity_buffers_minutes,high}', '10'::jsonb)
    ),
    (
      '46000000-0000-0000-0000-000000000068'::uuid,
      'candidate-evaluator-non-integral-bound-floor'::text,
      jsonb_set(base.config, '{candidate_bounds,floor_minutes}', '30.5'::jsonb)
    ),
    (
      '46000000-0000-0000-0000-000000000069'::uuid,
      'candidate-evaluator-non-integral-sleep-start-delay'::text,
      jsonb_set(base.config, '{sleep_compensation,max_start_delay_minutes}', '45.5'::jsonb)
    ),
    (
      '46000000-0000-0000-0000-000000000070'::uuid,
      'candidate-evaluator-malformed-contract'::text,
      jsonb_set(base.config, '{evaluator}', '42'::jsonb)
    ),
    (
      '46000000-0000-0000-0000-000000000071'::uuid,
      'candidate-evaluator-non-integral-emergency-neutral'::text,
      jsonb_set(base.config, '{emergency,neutral_minutes}', '90.5'::jsonb)
    )
) AS fixture(id, name, config);

DO $$
DECLARE
  _r record;
BEGIN
  FOR _r IN SELECT * FROM candidate_eval_contract_constraints LOOP
    EXECUTE format(
      'ALTER TABLE public.alert_model_versions ADD CONSTRAINT %I %s NOT VALID',
      _r.conname,
      _r.definition
    );
  END LOOP;
END;
$$;

INSERT INTO auth.users (id, email, aud, role)
SELECT
  format('46000000-0000-0000-0000-%s', lpad(n::text, 12, '0'))::uuid,
  format('candidate-eval-%s@example.invalid', n),
  'authenticated',
  'authenticated'
FROM generate_series(1, 20) AS n
ON CONFLICT (id) DO NOTHING;

INSERT INTO auth.users (id, email, aud, role)
VALUES (
  '46000000-0000-0000-0000-000000000099',
  'candidate-guardian@example.invalid',
  'authenticated',
  'authenticated'
)
ON CONFLICT (id) DO NOTHING;

UPDATE public.profiles
SET routine_pattern = CASE
      WHEN id = '46000000-0000-0000-0000-000000000001'::uuid
        THEN 'regular_9to5'
      WHEN id = '46000000-0000-0000-0000-000000000003'::uuid
        THEN 'semester_break'
      ELSE 'shift_irregular'
    END,
    consent_data_sharing = CASE
      WHEN id = '46000000-0000-0000-0000-000000000003'::uuid THEN false
      ELSE consent_data_sharing
    END
WHERE id::text LIKE '46000000-0000-0000-0000-%';

INSERT INTO public.user_settings (user_id, sensitivity, timezone)
SELECT
  format('46000000-0000-0000-0000-%s', lpad(n::text, 12, '0'))::uuid,
  CASE n
    WHEN 1 THEN 'low'
    WHEN 2 THEN 'high'
    WHEN 3 THEN 'low'
    WHEN 4 THEN 'high'
    WHEN 5 THEN 'balanced'
    WHEN 6 THEN 'low'
    ELSE 'balanced'
  END,
  'Asia/Tokyo'
FROM generate_series(1, 20) AS n
ON CONFLICT (user_id) DO UPDATE
SET sensitivity = EXCLUDED.sensitivity,
    timezone = EXCLUDED.timezone;

-- Persisted subject context, not current mutable settings, is authoritative.
INSERT INTO public.alert_judgment_subject_contexts (
  id, version_id, user_id, effective_from, effective_to,
  raw_sensitivity, canonical_sensitivity, routine_mode,
  timezone, utc_offset_minutes, settings_updated_at, settings_provenance,
  captured_at, config_sha256, evidence_version, subject_context_sha256
)
SELECT
  format('46100000-0000-0000-0000-%s', lpad(fixture.ordinal::text, 12, '0'))::uuid,
  fixture.version_id,
  fixture.user_id,
  '2026-07-01 00:00+00',
  '2026-08-01 00:00+00',
  fixture.raw_sensitivity,
  fixture.canonical_sensitivity,
  fixture.routine_mode,
  'UTC',
  0,
  '2026-06-30 23:00+00',
  jsonb_build_object('source', 'candidate-evaluator-test', 'ordinal', fixture.ordinal),
  '2026-06-30 23:30+00',
  version.config_sha256,
  version.evidence_version,
  repeat('0', 64)
FROM (
  VALUES
    (1,  '46000000-0000-0000-0000-000000000001'::uuid, '46000000-0000-0000-0000-000000000010'::uuid, 'high',    'high',     'regular_9to5'),
    (2,  '46000000-0000-0000-0000-000000000002'::uuid, '46000000-0000-0000-0000-000000000010'::uuid, 'balanced','balanced', 'regular_9to5'),
    (3,  '46000000-0000-0000-0000-000000000003'::uuid, '46000000-0000-0000-0000-000000000010'::uuid, 'balanced','balanced', 'regular_9to5'),
    (4,  '46000000-0000-0000-0000-000000000004'::uuid, '46000000-0000-0000-0000-000000000020'::uuid, 'sensitive','high',    'regular_9to5'),
    (5,  '46000000-0000-0000-0000-000000000005'::uuid, '46000000-0000-0000-0000-000000000020'::uuid, 'mystery', 'balanced', 'regular_9to5'),
    (6,  '46000000-0000-0000-0000-000000000006'::uuid, '46000000-0000-0000-0000-000000000020'::uuid, 'relaxed', 'low',      'regular_9to5'),
    (7,  '46000000-0000-0000-0000-000000000007'::uuid, '46000000-0000-0000-0000-000000000020'::uuid, 'high',    'high',     'regular_9to5'),
    (8,  '46000000-0000-0000-0000-000000000008'::uuid, '46000000-0000-0000-0000-000000000020'::uuid, 'low',     'low',      'regular_9to5'),
    (9,  '46000000-0000-0000-0000-000000000009'::uuid, '46000000-0000-0000-0000-000000000010'::uuid, 'high',    'high',     'regular_9to5'),
    (10, '46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000010'::uuid, 'high',    'high',     'regular_9to5'),
    (12, '46000000-0000-0000-0000-000000000012'::uuid, '46000000-0000-0000-0000-000000000010'::uuid, 'balanced','balanced', 'regular_9to5'),
    (13, '46000000-0000-0000-0000-000000000013'::uuid, '46000000-0000-0000-0000-000000000010'::uuid, 'balanced','balanced', 'regular_9to5'),
    (14, '46000000-0000-0000-0000-000000000014'::uuid, '46000000-0000-0000-0000-000000000010'::uuid, 'balanced','balanced', 'regular_9to5'),
    (15, '46000000-0000-0000-0000-000000000015'::uuid, '46000000-0000-0000-0000-000000000010'::uuid, 'balanced','balanced', 'regular_9to5'),
    (16, '46000000-0000-0000-0000-000000000016'::uuid, '46000000-0000-0000-0000-000000000010'::uuid, 'high',    'high',     'regular_9to5'),
    (17, '46000000-0000-0000-0000-000000000017'::uuid, '46000000-0000-0000-0000-000000000010'::uuid, 'high',    'high',     'regular_9to5'),
    (18, '46000000-0000-0000-0000-000000000018'::uuid, '46000000-0000-0000-0000-000000000010'::uuid, 'high',    'high',     'regular_9to5'),
    (19, '46000000-0000-0000-0000-000000000019'::uuid, '46000000-0000-0000-0000-000000000010'::uuid, 'high',    'high',     'regular_9to5')
) AS fixture(ordinal, user_id, version_id, raw_sensitivity, canonical_sensitivity, routine_mode)
JOIN public.alert_model_versions version ON version.id = fixture.version_id;

-- A second covering row makes user 12 explicitly ambiguous.
INSERT INTO public.alert_judgment_subject_contexts (
  id, version_id, user_id, effective_from, effective_to,
  raw_sensitivity, canonical_sensitivity, routine_mode,
  timezone, utc_offset_minutes, settings_updated_at, settings_provenance,
  captured_at, config_sha256, evidence_version, subject_context_sha256
)
SELECT
  '46100000-0000-0000-0000-000000000112',
  version.id,
  '46000000-0000-0000-0000-000000000012',
  '2026-07-01 00:00+00',
  '2026-08-01 00:00+00',
  'balanced', 'balanced', 'regular_9to5', 'UTC', 0,
  '2026-06-30 23:00+00',
  '{"source":"ambiguous-second-capture"}'::jsonb,
  '2026-06-30 23:45+00',
  version.config_sha256, version.evidence_version, repeat('0', 64)
FROM public.alert_model_versions version
WHERE version.id = '46000000-0000-0000-0000-000000000010';

-- Hash all contexts except user 13; that row intentionally remains corrupt.
UPDATE public.alert_judgment_subject_contexts context
SET subject_context_sha256 = encode(extensions.digest(jsonb_build_object(
  'version_id', context.version_id,
  'user_id', context.user_id,
  'effective_from_utc',
    to_char(context.effective_from AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'effective_to_utc',
    CASE WHEN context.effective_to IS NULL THEN NULL
      ELSE to_char(context.effective_to AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    END,
  'raw_sensitivity', context.raw_sensitivity,
  'canonical_sensitivity', context.canonical_sensitivity,
  'routine_mode', context.routine_mode,
  'timezone', context.timezone,
  'utc_offset_minutes', context.utc_offset_minutes,
  'settings_updated_at_utc',
    to_char(context.settings_updated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'settings_provenance', context.settings_provenance,
  'captured_at_utc',
    to_char(context.captured_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'config_sha256', context.config_sha256,
  'evidence_version', context.evidence_version
)::text, 'sha256'), 'hex')
WHERE context.user_id <> '46000000-0000-0000-0000-000000000013';

-- Canonical-v2 coverage and one protected-user session at 22:30.
INSERT INTO public.alert_observation_coverage_intervals (
  version_id, user_id, starts_at, ends_at, timezone, utc_offset_minutes,
  activity_coverage_state, intervention_coverage_state, sleep_context_state,
  captured_at, finalized_at, evidence_version, provenance_sha256
)
SELECT fixture.version_id, fixture.user_id,
  '2026-07-10 20:00+00', '2026-07-11 07:59+00', 'UTC', 0,
  'valid', 'valid', 'valid',
  '2026-07-10 19:00+00', '2026-07-11 07:59+00',
  'canonical-v2', repeat(fixture.hash_character, 64)
FROM (
  VALUES
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000001'::uuid, '1'),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000002'::uuid, '2'),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000003'::uuid, '3'),
    ('46000000-0000-0000-0000-000000000020'::uuid, '46000000-0000-0000-0000-000000000004'::uuid, '4'),
    ('46000000-0000-0000-0000-000000000020'::uuid, '46000000-0000-0000-0000-000000000005'::uuid, '5'),
    ('46000000-0000-0000-0000-000000000020'::uuid, '46000000-0000-0000-0000-000000000006'::uuid, '6'),
    ('46000000-0000-0000-0000-000000000020'::uuid, '46000000-0000-0000-0000-000000000007'::uuid, '7'),
    ('46000000-0000-0000-0000-000000000020'::uuid, '46000000-0000-0000-0000-000000000008'::uuid, '8'),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000009'::uuid, '9'),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000010'::uuid, 'a'),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000012'::uuid, 'b'),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000013'::uuid, 'c'),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000015'::uuid, 'd'),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000016'::uuid, 'e'),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000017'::uuid, 'f'),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000018'::uuid, '0'),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000019'::uuid, '1')
) AS fixture(version_id, user_id, hash_character);

INSERT INTO public.behavior_pings (user_id, kind, at, received_at, ingest_version)
SELECT DISTINCT
  user_id,
  'app',
  '2026-07-10 22:30+00'::timestamptz,
  '2026-07-10 22:30+00'::timestamptz,
  2
FROM public.alert_observation_coverage_intervals
WHERE version_id IN (
  '46000000-0000-0000-0000-000000000010',
  '46000000-0000-0000-0000-000000000020'
);

-- Overlapping accepted ranges must be clipped and unioned once.
INSERT INTO public.alert_sleep_night_contexts (
  version_id, user_id, anchor_date, timezone, sleep_start_local, sleep_end_local,
  anchor_starts_at, anchor_ends_at, utc_offset_minutes, coverage_state,
  captured_at, finalized_at, evidence_version, provenance_sha256
) VALUES
  ('46000000-0000-0000-0000-000000000010', '46000000-0000-0000-0000-000000000001',
   '2026-07-10', 'UTC', '23:00', '07:00',
   '2026-07-10 23:00+00', '2026-07-11 07:00+00', 0, 'valid',
   '2026-07-10 22:00+00', '2026-07-11 07:00+00', 'canonical-v2', repeat('1', 64)),
  ('46000000-0000-0000-0000-000000000010', '46000000-0000-0000-0000-000000000001',
   '2026-07-11', 'UTC', '00:00', '02:00',
   '2026-07-11 00:00+00', '2026-07-11 02:00+00', 0, 'valid',
   '2026-07-10 22:00+00', '2026-07-11 02:00+00', 'canonical-v2', repeat('2', 64)),
  ('46000000-0000-0000-0000-000000000010', '46000000-0000-0000-0000-000000000017',
   '2026-07-10', 'UTC', '23:00', '07:00',
   '2026-07-10 23:00+00', '2026-07-11 07:00+00', 0, 'valid',
   '2026-07-10 22:00+00', '2026-07-11 07:00+00', 'canonical-v2', repeat('3', 64)),
  ('46000000-0000-0000-0000-000000000010', '46000000-0000-0000-0000-000000000018',
   '2026-07-10', 'UTC', '23:00', '07:00',
   '2026-07-10 23:00+00', '2026-07-11 07:00+00', 0, 'valid',
   '2026-07-10 22:00+00', '2026-07-11 09:00+00', 'canonical-v2', repeat('4', 64)),
  -- This prior row is finalized after the evaluator cutoff. Its positive
  -- activity must not extend user 17's otherwise-known current anchor.
  ('46000000-0000-0000-0000-000000000010', '46000000-0000-0000-0000-000000000017',
   '2026-07-09', 'UTC', '23:00', '07:00',
   '2026-07-09 23:00+00', '2026-07-10 07:00+00', 0, 'valid',
   '2026-07-09 22:00+00', '2026-07-11 09:00+00', 'canonical-v2', repeat('5', 64));

INSERT INTO public.behavior_pings (user_id, kind, at, received_at, ingest_version)
VALUES (
  '46000000-0000-0000-0000-000000000017',
  'app',
  '2026-07-09 23:40+00',
  '2026-07-09 23:40+00',
  2
);

-- Personal/context rows use the exact Task 4 hash contract. The Task 6 trigger
-- supplies immutable config/evidence pins on every candidate-row mutation.
INSERT INTO public.alert_gap_profiles (
  version_id, user_id, context_key, through_date, neutral_p95_minutes,
  sample_count, distinct_support_dates, support_started_on, support_ended_on,
  latest_evidence_at, quality_state, confidence, profile_sha256, input_sha256
)
SELECT *
FROM (
  VALUES
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000001'::uuid, 'candidate-eval-v1:all_days:h1320'::text, '2026-07-10'::date, 60, 4, 4, '2026-07-01'::date, '2026-07-10'::date, '2026-07-10 20:00+00'::timestamptz, 'valid'::text, 0.8::double precision, repeat('0',64), repeat('1',64)),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000001'::uuid, 'personal_global'::text, '2026-07-10'::date, 300, 4, 4, '2026-07-01'::date, '2026-07-10'::date, '2026-07-10 20:00+00'::timestamptz, 'valid'::text, 0.8::double precision, repeat('0',64), repeat('2',64)),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000001'::uuid, 'candidate-eval-v1:all_days:h1320'::text, '2026-07-11'::date, 500, 4, 4, '2026-07-01'::date, '2026-07-11'::date, '2026-07-11 07:00+00'::timestamptz, 'valid'::text, 0.9::double precision, repeat('0',64), repeat('3',64)),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000002'::uuid, 'candidate-eval-v1:all_days:h1320'::text, '2026-07-10'::date, 80, 4, 4, '2026-07-01'::date, '2026-07-10'::date, '2026-07-10 20:00+00'::timestamptz, 'valid'::text, 0.5::double precision, repeat('0',64), repeat('4',64)),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000002'::uuid, 'personal_global'::text, '2026-07-10'::date, 120, 4, 4, '2026-07-01'::date, '2026-07-10'::date, '2026-07-10 20:00+00'::timestamptz, 'valid'::text, 0.85::double precision, repeat('0',64), repeat('5',64)),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000003'::uuid, 'candidate-eval-v1:all_days:h1320'::text, '2026-07-10'::date, 80, 1, 1, '2026-07-10'::date, '2026-07-10'::date, '2026-07-10 20:00+00'::timestamptz, 'low_support'::text, 0.3::double precision, repeat('0',64), repeat('6',64)),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000003'::uuid, 'personal_global'::text, '2026-07-10'::date, 90, 1, 1, '2026-07-10'::date, '2026-07-10'::date, '2026-07-10 20:00+00'::timestamptz, 'low_support'::text, 0.3::double precision, repeat('0',64), repeat('7',64)),
    ('46000000-0000-0000-0000-000000000020'::uuid, '46000000-0000-0000-0000-000000000007'::uuid, 'candidate-eval-v1:all_days:h1320'::text, '2026-07-10'::date, 60, 4, 4, '2026-07-01'::date, '2026-07-10'::date, '2026-07-10 20:00+00'::timestamptz, 'valid'::text, 0.8::double precision, repeat('0',64), repeat('8',64)),
    ('46000000-0000-0000-0000-000000000020'::uuid, '46000000-0000-0000-0000-000000000008'::uuid, 'candidate-eval-v1:all_days:h1320'::text, '2026-07-10'::date, 120, 4, 4, '2026-07-01'::date, '2026-07-10'::date, '2026-07-10 20:00+00'::timestamptz, 'valid'::text, 0.8::double precision, repeat('0',64), repeat('9',64)),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000009'::uuid, 'personal_global'::text, '2026-07-10'::date, 60, 4, 4, '2026-07-01'::date, '2026-07-10'::date, '2026-07-10 20:00+00'::timestamptz, 'valid'::text, 0.8::double precision, repeat('0',64), repeat('a',64)),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000010'::uuid, 'candidate-eval-v1:all_days:h1320'::text, '2026-07-10'::date, 90, 4, 4, '2026-07-01'::date, '2026-07-10'::date, '2026-07-10 20:00+00'::timestamptz, 'valid'::text, 0.8::double precision, repeat('0',64), repeat('b',64)),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000015'::uuid, 'candidate-eval-v1:all_days:h1320'::text, '2026-07-10'::date, 100, 4, 4, '2026-07-01'::date, '2026-07-10'::date, '2026-07-10 20:00+00'::timestamptz, 'valid'::text, 0.8::double precision, repeat('0',64), repeat('c',64)),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000015'::uuid, 'personal_global'::text, '2026-07-10'::date, 130, 4, 4, '2026-07-01'::date, '2026-07-10'::date, '2026-07-10 20:00+00'::timestamptz, 'valid'::text, 0.8::double precision, repeat('0',64), repeat('d',64)),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000016'::uuid, 'candidate-eval-v1:all_days:h1320'::text, '2026-07-10'::date, 500, 4, 4, '2026-07-01'::date, '2026-07-10'::date, '2026-07-11 08:00+00'::timestamptz, 'valid'::text, 0.9::double precision, repeat('0',64), repeat('e',64)),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000016'::uuid, 'personal_global'::text, '2026-07-10'::date, 110, 4, 4, '2026-07-01'::date, '2026-07-10'::date, '2026-07-10 20:00+00'::timestamptz, 'valid'::text, 0.8::double precision, repeat('0',64), repeat('f',64)),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000017'::uuid, 'candidate-eval-v1:all_days:h1320'::text, '2026-07-10'::date, 120, 4, 4, '2026-07-01'::date, '2026-07-10'::date, '2026-07-10 20:00+00'::timestamptz, 'valid'::text, 0.8::double precision, repeat('0',64), repeat('1',64)),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000018'::uuid, 'candidate-eval-v1:all_days:h1320'::text, '2026-07-10'::date, 60, 4, 4, '2026-07-01'::date, '2026-07-10'::date, '2026-07-10 20:00+00'::timestamptz, 'valid'::text, 0.8::double precision, repeat('0',64), repeat('2',64)),
    ('46000000-0000-0000-0000-000000000010'::uuid, '46000000-0000-0000-0000-000000000019'::uuid, 'candidate-eval-v1:all_days:h1320'::text, '2026-07-10'::date, 60, 4, 4, '2026-07-01'::date, '2026-07-10'::date, '2026-07-10 20:00+00'::timestamptz, 'valid'::text, 0.8::double precision, repeat('0',64), repeat('3',64))
) AS rows(
  version_id, user_id, context_key, through_date, neutral_p95_minutes,
  sample_count, distinct_support_dates, support_started_on, support_ended_on,
  latest_evidence_at, quality_state, confidence, profile_sha256, input_sha256
);

UPDATE public.alert_gap_profiles profile
SET profile_sha256 = encode(extensions.digest(jsonb_build_object(
  'version_id', profile.version_id,
  'user_id', profile.user_id,
  'context_key', profile.context_key,
  'through_date', profile.through_date,
  'neutral_p95_minutes', profile.neutral_p95_minutes,
  'sample_count', profile.sample_count,
  'distinct_support_dates', profile.distinct_support_dates,
  'support_started_on', profile.support_started_on,
  'support_ended_on', profile.support_ended_on,
  'latest_evidence_at_utc',
    to_char(profile.latest_evidence_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'quality_state', profile.quality_state,
  'confidence', profile.confidence,
  'input_sha256', profile.input_sha256
)::text, 'sha256'), 'hex');

-- A corrupt context profile must fall to the still-valid personal global row.
UPDATE public.alert_gap_profiles
SET profile_sha256 = repeat('f', 64)
WHERE version_id = '46000000-0000-0000-0000-000000000010'
  AND user_id = '46000000-0000-0000-0000-000000000015'
  AND context_key <> 'personal_global';

-- Published prior contains no contributor identity and can be consumed by user 3,
-- whose current consent is false.
INSERT INTO public.routine_mode_cohort_priors (
  version_id, routine_mode, context_key, through_date,
  contributor_count, distinct_support_dates, support_started_on, support_ended_on,
  latest_evidence_at, oldest_evidence_at, valid_until,
  conservative_span_days, minimum_profile_confidence,
  neutral_p95_minutes, quality_state, confidence, algorithm,
  config_sha256, evidence_version, source_generation,
  input_sha256, prior_sha256
)
SELECT
  version.id, 'regular_9to5', 'personal_global', '2026-07-10',
  2, 5, '2026-07-01', '2026-07-10',
  '2026-07-10 16:00+00', '2026-07-10 12:00+00', '2026-08-09 12:00+00',
  10, 0.8, 100, 'valid', 1, 'weighted_median',
  version.config_sha256, version.evidence_version, generation.generation,
  repeat('c', 64), repeat('0', 64)
FROM public.alert_model_versions version
JOIN public.routine_mode_cohort_generations generation
  ON generation.routine_mode = 'regular_9to5'
WHERE version.id = '46000000-0000-0000-0000-000000000010';

UPDATE public.routine_mode_cohort_priors prior
SET prior_sha256 = encode(extensions.digest(concat_ws('|',
  prior.input_sha256,
  prior.version_id::text,
  prior.routine_mode,
  prior.context_key,
  prior.through_date::text,
  prior.contributor_count::text,
  prior.distinct_support_dates::text,
  prior.conservative_span_days::text,
  prior.support_started_on::text,
  prior.support_ended_on::text,
  prior.latest_evidence_at::text,
  prior.oldest_evidence_at::text,
  prior.valid_until::text,
  prior.neutral_p95_minutes::text,
  prior.quality_state,
  prior.confidence::text,
  prior.minimum_profile_confidence::text,
  prior.algorithm,
  prior.config_sha256,
  prior.evidence_version,
  prior.source_generation::text
), 'sha256'), 'hex')
WHERE prior.version_id = '46000000-0000-0000-0000-000000000010'
  AND prior.routine_mode = 'regular_9to5';

CREATE FUNCTION pg_temp.rehash_candidate_prior(
  _version_id uuid,
  _routine_mode text,
  _through_date date
)
RETURNS void
LANGUAGE sql
SET search_path = ''
AS $$
  UPDATE public.routine_mode_cohort_priors prior
  SET prior_sha256 = encode(extensions.digest(concat_ws('|',
    prior.input_sha256,
    prior.version_id::text,
    prior.routine_mode,
    prior.context_key,
    prior.through_date::text,
    prior.contributor_count::text,
    prior.distinct_support_dates::text,
    prior.conservative_span_days::text,
    prior.support_started_on::text,
    prior.support_ended_on::text,
    prior.latest_evidence_at::text,
    prior.oldest_evidence_at::text,
    prior.valid_until::text,
    prior.neutral_p95_minutes::text,
    prior.quality_state,
    prior.confidence::text,
    prior.minimum_profile_confidence::text,
    prior.algorithm,
    prior.config_sha256,
    prior.evidence_version,
    prior.source_generation::text
  ), 'sha256'), 'hex')
  WHERE prior.version_id = _version_id
    AND prior.routine_mode = _routine_mode
    AND prior.through_date = _through_date
$$;

-- Exact stable JSON shape and hierarchy.
SELECT results_eq(
  $$
    SELECT key
    FROM jsonb_object_keys(private.resolve_alert_candidate(
      '46000000-0000-0000-0000-000000000001',
      '2026-07-11 08:00+00',
      '46000000-0000-0000-0000-000000000010'
    )) AS key
    ORDER BY key
  $$,
  $$
    SELECT key
    FROM unnest(ARRAY[
      'basis','candidate_cap_reason','candidate_ceiling_minutes',
      'candidate_deadline','candidate_floor_minutes','candidate_threshold_minutes',
      'confidence','context_key','deadline_basis','decision_provenance',
      'effective_silence_minutes','evaluated_at','evaluator_version','evidence_cutoff',
      'fallback_path','guardian_used_as_activity','neutral_threshold_minutes',
      'provenance_sha256','quality_state','replayable','selected_source_sha256',
      'sensitivity_buffer_minutes','sleep_interval_provenance',
      'subject_context_sha256','unclamped_candidate_threshold_minutes',
      'unreplayable_reason','version_id','would_alert'
    ]::text[]) AS key
    ORDER BY key
  $$,
  'evaluator returns exactly the locked stable JSON keys'
);
SELECT results_eq(
  $$
    SELECT
      result ->> 'evaluator_version',
      result ->> 'basis',
      (result ->> 'neutral_threshold_minutes')::integer,
      (result ->> 'sensitivity_buffer_minutes')::integer,
      (result ->> 'candidate_threshold_minutes')::integer,
      result ->> 'candidate_cap_reason',
      round((result ->> 'confidence')::numeric, 2),
      result -> 'fallback_path'
    FROM (SELECT private.resolve_alert_candidate(
      '46000000-0000-0000-0000-000000000001',
      '2026-07-11 08:00+00',
      '46000000-0000-0000-0000-000000000010'
    ) AS result) evaluated
  $$,
  $$ VALUES (
    'adaptive_candidate_v1'::text,
    'personal_context'::text,
    60, 0, 60, 'none'::text, 0.80::numeric,
    '["personal_context"]'::jsonb
  ) $$,
  'valid as-of context p95 wins and confidence is support confidence, not p95 tail probability'
);
SELECT results_eq(
  $$
    SELECT
      result ->> 'version_id',
      result ->> 'evaluated_at',
      result ->> 'evidence_cutoff',
      (result ->> 'replayable')::boolean,
      result ->> 'unreplayable_reason',
      result ->> 'selected_source_sha256',
      result ->> 'subject_context_sha256',
      result #>> '{decision_provenance,model_config_sha256}',
      result #>> '{decision_provenance,evidence_version}',
      result #>> '{decision_provenance,selected_source_sha256}',
      result #>> '{decision_provenance,candidate_cap_reason}',
      result #>> '{decision_provenance,deadline_basis}',
      result ->> 'provenance_sha256'
        = encode(extensions.digest(
            (result -> 'decision_provenance')::text,
            'sha256'
          ), 'hex')
    FROM (SELECT private.resolve_alert_candidate(
      '46000000-0000-0000-0000-000000000001',
      '2026-07-11 08:00+00',
      '46000000-0000-0000-0000-000000000010'
    ) AS result) evaluated
  $$,
  $$
    SELECT
      version.id::text,
      '2026-07-11T08:00:00.000000Z'::text,
      '2026-07-11T08:00:00.000000Z'::text,
      true,
      NULL::text,
      profile.profile_sha256,
      context.subject_context_sha256,
      version.config_sha256,
      version.evidence_version,
      profile.profile_sha256,
      'none'::text,
      'known_interval_inversion'::text,
      true
    FROM public.alert_model_versions version
    JOIN public.alert_gap_profiles profile
      ON profile.version_id = version.id
     AND profile.user_id = '46000000-0000-0000-0000-000000000001'
     AND profile.context_key = 'candidate-eval-v1:all_days:h1320'
     AND profile.through_date = '2026-07-10'
    JOIN public.alert_judgment_subject_contexts context
      ON context.version_id = version.id
     AND context.user_id = profile.user_id
    WHERE version.id = '46000000-0000-0000-0000-000000000010'
  $$,
  'successful output binds exact identity, source, subject, model, deadline, and canonical provenance hash'
);
SELECT results_eq(
  $$
    SELECT
      result ->> 'basis',
      (result ->> 'neutral_threshold_minutes')::integer,
      (result ->> 'sensitivity_buffer_minutes')::integer,
      (result ->> 'candidate_threshold_minutes')::integer,
      result -> 'fallback_path'
    FROM (SELECT private.resolve_alert_candidate(
      '46000000-0000-0000-0000-000000000002',
      '2026-07-11 08:00+00',
      '46000000-0000-0000-0000-000000000010'
    ) AS result) evaluated
  $$,
  $$ VALUES (
    'personal_global'::text, 120, 45, 165,
    '["personal_context","personal_global"]'::jsonb
  ) $$,
  'low-confidence context falls to valid personal-global and applies sensitivity once'
);
SELECT results_eq(
  $$
    SELECT
      result ->> 'basis',
      (result ->> 'candidate_threshold_minutes')::integer,
      result -> 'fallback_path'
    FROM (SELECT private.resolve_alert_candidate(
      '46000000-0000-0000-0000-000000000003',
      '2026-07-11 08:00+00',
      '46000000-0000-0000-0000-000000000010'
    ) AS result) evaluated
  $$,
  $$ VALUES (
    'routine_cohort'::text, 145,
    '["personal_context","personal_global","routine_cohort"]'::jsonb
  ) $$,
  'invalid personal tiers fall to a published same-mode cohort even for a non-contributor'
);
SELECT results_eq(
  $$
    SELECT user_id, basis, neutral, buffer, threshold, cap_reason
    FROM (
      SELECT fixture.user_id,
        result ->> 'basis' AS basis,
        (result ->> 'neutral_threshold_minutes')::integer AS neutral,
        (result ->> 'sensitivity_buffer_minutes')::integer AS buffer,
        (result ->> 'candidate_threshold_minutes')::integer AS threshold,
        result ->> 'candidate_cap_reason' AS cap_reason
      FROM (VALUES
        ('46000000-0000-0000-0000-000000000004'::uuid, '46000000-0000-0000-0000-000000000020'::uuid),
        ('46000000-0000-0000-0000-000000000005'::uuid, '46000000-0000-0000-0000-000000000020'::uuid),
        ('46000000-0000-0000-0000-000000000006'::uuid, '46000000-0000-0000-0000-000000000020'::uuid)
      ) fixture(user_id, version_id)
      CROSS JOIN LATERAL (
        SELECT private.resolve_alert_candidate(
          fixture.user_id,
          '2026-07-11 08:00+00',
          fixture.version_id
        ) AS result
      ) resolved
    ) values_by_user
    ORDER BY user_id
  $$,
  $$ VALUES
    ('46000000-0000-0000-0000-000000000004'::uuid, 'deterministic_emergency'::text, 90, 0, 90, 'emergency_exempt'::text),
    ('46000000-0000-0000-0000-000000000005'::uuid, 'deterministic_emergency'::text, 90, 45, 135, 'emergency_exempt'::text),
    ('46000000-0000-0000-0000-000000000006'::uuid, 'deterministic_emergency'::text, 90, 90, 180, 'emergency_exempt'::text)
  $$,
  'pure ADR-0022 emergency reproduces 90/135/180 and ignores learned bounds'
);
SELECT results_eq(
  $$
    SELECT user_id,
      result ->> 'candidate_cap_reason',
      (result ->> 'unclamped_candidate_threshold_minutes')::integer,
      (result ->> 'candidate_threshold_minutes')::integer
    FROM (VALUES
      ('46000000-0000-0000-0000-000000000007'::uuid),
      ('46000000-0000-0000-0000-000000000008'::uuid)
    ) fixture(user_id)
    CROSS JOIN LATERAL (
      SELECT private.resolve_alert_candidate(
        fixture.user_id,
        '2026-07-11 08:00+00',
        '46000000-0000-0000-0000-000000000020'
      ) AS result
    ) evaluated
    ORDER BY user_id
  $$,
  $$ VALUES
    ('46000000-0000-0000-0000-000000000007'::uuid, 'floor'::text, 60, 100),
    ('46000000-0000-0000-0000-000000000008'::uuid, 'ceiling'::text, 210, 150)
  $$,
  'candidate-only floor and ceiling clamp learned results with explicit reasons'
);
SELECT results_eq(
  $$
    SELECT
      round((result ->> 'effective_silence_minutes')::numeric, 3),
      result ->> 'candidate_deadline',
      result ->> 'deadline_basis',
      (result ->> 'would_alert')::boolean,
      jsonb_array_length(result -> 'sleep_interval_provenance'),
      result #>> '{sleep_interval_provenance,0,starts_at_utc}',
      result #>> '{sleep_interval_provenance,0,ends_at_utc}'
    FROM (SELECT private.resolve_alert_candidate(
      '46000000-0000-0000-0000-000000000001',
      '2026-07-11 08:00+00',
      '46000000-0000-0000-0000-000000000010'
    ) AS result) evaluated
  $$,
  $$ VALUES (
    90.000::numeric,
    '2026-07-11T07:30:00.000000Z'::text,
    'known_interval_inversion'::text,
    true,
    1,
    '2026-07-10T23:00:00.000000Z'::text,
    '2026-07-11T07:00:00.000000Z'::text
  ) $$,
  'clipped overlapping sleep is unioned once and deadline inverts the same effective clock'
);
SELECT results_eq(
  $$
    SELECT
      round((result ->> 'effective_silence_minutes')::numeric, 3),
      result ->> 'candidate_deadline',
      result ->> 'deadline_basis',
      (result ->> 'would_alert')::boolean
    FROM (SELECT private.resolve_alert_candidate(
      '46000000-0000-0000-0000-000000000017',
      '2026-07-11 08:00+00',
      '46000000-0000-0000-0000-000000000010'
    ) AS result) evaluated
  $$,
  $$ VALUES (
    90.000::numeric,
    '2026-07-11T08:30:00.000000Z'::text,
    'no_future_exclusion'::text,
    false
  ) $$,
  'deadline beyond known evidence is conservative and assumes no future exclusion'
);
SELECT results_eq(
  $$
    SELECT
      ends_at,
      (provenance ->> 'prior_positive_night_count')::integer,
      provenance ->> 'evidence_cutoff'
    FROM private.candidate_sleep_intervals(
      '46000000-0000-0000-0000-000000000017',
      '2026-07-10 22:30+00',
      '2026-07-11 08:00+00',
      '46000000-0000-0000-0000-000000000010'
    )
  $$,
  $$ VALUES (
    '2026-07-11 07:00+00'::timestamptz,
    0,
    '2026-07-11T08:00:00+00:00'::text
  ) $$,
  'a prior night finalized after cutoff cannot extend the as-of sleep interval'
);
SELECT results_eq(
  $$
    SELECT
      round((result ->> 'effective_silence_minutes')::numeric, 3),
      jsonb_array_length(result -> 'sleep_interval_provenance')
    FROM (SELECT private.resolve_alert_candidate(
      '46000000-0000-0000-0000-000000000018',
      '2026-07-11 08:00+00',
      '46000000-0000-0000-0000-000000000010'
    ) AS result) evaluated
  $$,
  $$ VALUES (570.000::numeric, 0) $$,
  'sleep finalized after the fixed cutoff is not projected into history'
);
SELECT results_eq(
  $$
    SELECT
      result ->> 'basis',
      (result ->> 'neutral_threshold_minutes')::integer
    FROM (SELECT private.resolve_alert_candidate(
      '46000000-0000-0000-0000-000000000016',
      '2026-07-11 08:00+00',
      '46000000-0000-0000-0000-000000000010'
    ) AS result) evaluated
  $$,
  $$ VALUES ('personal_global'::text, 110) $$,
  'latest evidence at the evaluation instant is future leakage and falls to an older valid tier'
);
SELECT results_eq(
  $$
    SELECT
      result ->> 'basis',
      (result ->> 'neutral_threshold_minutes')::integer
    FROM (SELECT private.resolve_alert_candidate(
      '46000000-0000-0000-0000-000000000015',
      '2026-07-11 08:00+00',
      '46000000-0000-0000-0000-000000000010'
    ) AS result) evaluated
  $$,
  $$ VALUES ('personal_global'::text, 130) $$,
  'recomputed profile hash rejects a corrupt context row and falls one tier'
);

-- All seven unreplayable states are explicit and stable.
SELECT results_eq(
  $$
    SELECT label, result ->> 'unreplayable_reason'
    FROM (
      VALUES
        ('invalid_version_status'::text, private.resolve_alert_candidate(
          '46000000-0000-0000-0000-000000000001',
          '2026-07-11 08:00+00',
          '46000000-0000-0000-0000-000000000030')),
        ('config_hash_mismatch'::text, private.resolve_alert_candidate(
          '46000000-0000-0000-0000-000000000001',
          '2026-07-11 08:00+00',
          '46000000-0000-0000-0000-000000000040')),
        ('unsupported_evidence_version'::text, private.resolve_alert_candidate(
          '46000000-0000-0000-0000-000000000001',
          '2026-07-11 08:00+00',
          '46000000-0000-0000-0000-000000000050')),
        ('missing_subject_context'::text, private.resolve_alert_candidate(
          '46000000-0000-0000-0000-000000000011',
          '2026-07-11 08:00+00',
          '46000000-0000-0000-0000-000000000010')),
        ('ambiguous_subject_context'::text, private.resolve_alert_candidate(
          '46000000-0000-0000-0000-000000000012',
          '2026-07-11 08:00+00',
          '46000000-0000-0000-0000-000000000010')),
        ('subject_context_provenance_invalid'::text, private.resolve_alert_candidate(
          '46000000-0000-0000-0000-000000000013',
          '2026-07-11 08:00+00',
          '46000000-0000-0000-0000-000000000010')),
        ('missing_qualified_session'::text, private.resolve_alert_candidate(
          '46000000-0000-0000-0000-000000000014',
          '2026-07-11 08:00+00',
          '46000000-0000-0000-0000-000000000010'))
    ) cases(label, result)
    ORDER BY label
  $$,
  $$
    VALUES
      ('ambiguous_subject_context'::text, 'ambiguous_subject_context'::text),
      ('config_hash_mismatch'::text, 'config_hash_mismatch'::text),
      ('invalid_version_status'::text, 'invalid_version_status'::text),
      ('missing_qualified_session'::text, 'missing_qualified_session'::text),
      ('missing_subject_context'::text, 'missing_subject_context'::text),
      ('subject_context_provenance_invalid'::text, 'subject_context_provenance_invalid'::text),
      ('unsupported_evidence_version'::text, 'unsupported_evidence_version'::text)
  $$,
  'the exact seven-value unreplayable enum is observable'
);
SELECT results_eq(
  $$
    SELECT version_id, result ->> 'unreplayable_reason', (result ->> 'replayable')::boolean
    FROM (
      VALUES
        ('46000000-0000-0000-0000-000000000060'::uuid),
        ('46000000-0000-0000-0000-000000000061'::uuid),
        ('46000000-0000-0000-0000-000000000062'::uuid),
        ('46000000-0000-0000-0000-000000000063'::uuid),
        ('46000000-0000-0000-0000-000000000064'::uuid),
        ('46000000-0000-0000-0000-000000000065'::uuid),
        ('46000000-0000-0000-0000-000000000066'::uuid),
        ('46000000-0000-0000-0000-000000000067'::uuid),
        ('46000000-0000-0000-0000-000000000068'::uuid),
        ('46000000-0000-0000-0000-000000000069'::uuid),
        ('46000000-0000-0000-0000-000000000070'::uuid),
        ('46000000-0000-0000-0000-000000000071'::uuid)
      ) fixture(version_id)
    CROSS JOIN LATERAL (
      SELECT private.resolve_alert_candidate(
        '46000000-0000-0000-0000-000000000001',
        '2026-07-11 08:00+00',
        fixture.version_id
      ) AS result
    ) evaluated
    ORDER BY version_id
  $$,
  $$
    VALUES
      ('46000000-0000-0000-0000-000000000060'::uuid, 'config_hash_mismatch'::text, false),
      ('46000000-0000-0000-0000-000000000061'::uuid, 'config_hash_mismatch'::text, false),
      ('46000000-0000-0000-0000-000000000062'::uuid, 'config_hash_mismatch'::text, false),
      ('46000000-0000-0000-0000-000000000063'::uuid, 'config_hash_mismatch'::text, false),
      ('46000000-0000-0000-0000-000000000064'::uuid, 'config_hash_mismatch'::text, false),
      ('46000000-0000-0000-0000-000000000065'::uuid, 'config_hash_mismatch'::text, false),
      ('46000000-0000-0000-0000-000000000066'::uuid, 'config_hash_mismatch'::text, false),
      ('46000000-0000-0000-0000-000000000067'::uuid, 'config_hash_mismatch'::text, false),
      ('46000000-0000-0000-0000-000000000068'::uuid, 'config_hash_mismatch'::text, false),
      ('46000000-0000-0000-0000-000000000069'::uuid, 'config_hash_mismatch'::text, false),
      ('46000000-0000-0000-0000-000000000070'::uuid, 'config_hash_mismatch'::text, false),
      ('46000000-0000-0000-0000-000000000071'::uuid, 'config_hash_mismatch'::text, false)
  $$,
  'canonical-hash legacy configs fail closed across all groups and malformed condition types'
);
SELECT is(private.resolve_alert_candidate('46000000-0000-0000-0000-000000000061', '2026-07-11 08:00+00', '46000000-0000-0000-0000-000000000061') ->> 'unreplayable_reason', 'config_hash_mismatch', 'missing sessionization key fails closed with config_hash_mismatch');
SELECT is(private.resolve_alert_candidate('46000000-0000-0000-0000-000000000062', '2026-07-11 08:00+00', '46000000-0000-0000-0000-000000000062') ->> 'unreplayable_reason', 'config_hash_mismatch', 'wrong json string type fails closed with config_hash_mismatch');
SELECT is(private.resolve_alert_candidate('46000000-0000-0000-0000-000000000063', '2026-07-11 08:00+00', '46000000-0000-0000-0000-000000000063') ->> 'unreplayable_reason', 'config_hash_mismatch', 'negative horizon fails closed with config_hash_mismatch');
SELECT is(private.resolve_alert_candidate('46000000-0000-0000-0000-000000000064', '2026-07-11 08:00+00', '46000000-0000-0000-0000-000000000064') ->> 'unreplayable_reason', 'config_hash_mismatch', 'non-integral horizon fails closed with config_hash_mismatch');
SELECT is(private.resolve_alert_candidate('46000000-0000-0000-0000-000000000065', '2026-07-11 08:00+00', '46000000-0000-0000-0000-000000000065') ->> 'unreplayable_reason', 'config_hash_mismatch', 'invalid context enum fails closed with config_hash_mismatch');
SELECT is(private.resolve_alert_candidate('46000000-0000-0000-0000-000000000066', '2026-07-11 08:00+00', '46000000-0000-0000-0000-000000000066') ->> 'unreplayable_reason', 'config_hash_mismatch', 'out-of-range trim fraction fails closed with config_hash_mismatch');
SELECT is(private.resolve_alert_candidate('46000000-0000-0000-0000-000000000067', '2026-07-11 08:00+00', '46000000-0000-0000-0000-000000000067') ->> 'unreplayable_reason', 'config_hash_mismatch', 'invalid sensitivity buffer value fails closed with config_hash_mismatch');
SELECT is(private.resolve_alert_candidate('46000000-0000-0000-0000-000000000068', '2026-07-11 08:00+00', '46000000-0000-0000-0000-000000000068') ->> 'unreplayable_reason', 'config_hash_mismatch', 'non-integral floor minutes fails closed with config_hash_mismatch');
SELECT is(private.resolve_alert_candidate('46000000-0000-0000-0000-000000000069', '2026-07-11 08:00+00', '46000000-0000-0000-0000-000000000069') ->> 'unreplayable_reason', 'config_hash_mismatch', 'non-integral start delay fails closed with config_hash_mismatch');
SELECT is(private.resolve_alert_candidate('46000000-0000-0000-0000-000000000070', '2026-07-11 08:00+00', '46000000-0000-0000-0000-000000000070') ->> 'unreplayable_reason', 'config_hash_mismatch', 'malformed evaluator contract fails closed with config_hash_mismatch');
SELECT is(private.resolve_alert_candidate('46000000-0000-0000-0000-000000000071', '2026-07-11 08:00+00', '46000000-0000-0000-0000-000000000071') ->> 'unreplayable_reason', 'config_hash_mismatch', 'non-integral emergency neutral fails closed with config_hash_mismatch');
SELECT results_eq(
  $$
    SELECT
      (result ->> 'replayable')::boolean,
      result ->> 'quality_state',
      result ->> 'basis',
      result ->> 'context_key',
      result ->> 'neutral_threshold_minutes',
      result ->> 'sensitivity_buffer_minutes',
      result ->> 'unclamped_candidate_threshold_minutes',
      result ->> 'candidate_floor_minutes',
      result ->> 'candidate_ceiling_minutes',
      result ->> 'candidate_cap_reason',
      result ->> 'candidate_threshold_minutes',
      result ->> 'effective_silence_minutes',
      result ->> 'candidate_deadline',
      result ->> 'deadline_basis',
      result ->> 'would_alert',
      result ->> 'confidence',
      result ->> 'selected_source_sha256',
      result ->> 'subject_context_sha256',
      result ->> 'evaluator_version',
      result -> 'fallback_path',
      result -> 'sleep_interval_provenance',
      result -> 'decision_provenance',
      result ->> 'provenance_sha256',
      encode(extensions.digest((result -> 'decision_provenance')::text, 'sha256'), 'hex'),
      (result ->> 'guardian_used_as_activity')::boolean
    FROM (SELECT private.resolve_alert_candidate(
      '46000000-0000-0000-0000-000000000011',
      '2026-07-11 08:00+00',
      '46000000-0000-0000-0000-000000000010'
    ) AS result) evaluated
  $$,
  $$ VALUES (
    false, 'coverage_invalid'::text,
    NULL::text, NULL::text,
    NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
    NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
    NULL::text, NULL::text,
    'adaptive_candidate_v1'::text,
    '[]'::jsonb, '[]'::jsonb,
    jsonb_build_object(
      'version_id', '46000000-0000-0000-0000-000000000010'::uuid,
      'evaluator_version', 'adaptive_candidate_v1',
      'evaluated_at', '2026-07-11T08:00:00.000000Z',
      'evidence_cutoff', '2026-07-11T08:00:00.000000Z',
      'replayable', false,
      'unreplayable_reason', 'missing_subject_context'
    ),
    encode(extensions.digest(jsonb_build_object(
      'version_id', '46000000-0000-0000-0000-000000000010'::uuid,
      'evaluator_version', 'adaptive_candidate_v1',
      'evaluated_at', '2026-07-11T08:00:00.000000Z',
      'evidence_cutoff', '2026-07-11T08:00:00.000000Z',
      'replayable', false,
      'unreplayable_reason', 'missing_subject_context'
    )::text, 'sha256'), 'hex'),
    encode(extensions.digest(jsonb_build_object(
      'version_id', '46000000-0000-0000-0000-000000000010'::uuid,
      'evaluator_version', 'adaptive_candidate_v1',
      'evaluated_at', '2026-07-11T08:00:00.000000Z',
      'evidence_cutoff', '2026-07-11T08:00:00.000000Z',
      'replayable', false,
      'unreplayable_reason', 'missing_subject_context'
    )::text, 'sha256'), 'hex'),
    false
  ) $$,
  'unreplayable output nulls decision fields but retains authoritative evaluator identity'
);

-- As-of subject truth is prospective and half-open; valid row hashes cannot
-- rescue a future capture or mismatched model/evidence pin.
CREATE FUNCTION pg_temp.rehash_candidate_subject(_context_id uuid)
RETURNS void
LANGUAGE sql
SET search_path = ''
AS $$
  UPDATE public.alert_judgment_subject_contexts context
  SET subject_context_sha256 = encode(extensions.digest(jsonb_build_object(
    'version_id', context.version_id,
    'user_id', context.user_id,
    'effective_from_utc',
      to_char(context.effective_from AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'effective_to_utc',
      CASE WHEN context.effective_to IS NULL THEN NULL
        ELSE to_char(context.effective_to AT TIME ZONE 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
      END,
    'raw_sensitivity', context.raw_sensitivity,
    'canonical_sensitivity', context.canonical_sensitivity,
    'routine_mode', context.routine_mode,
    'timezone', context.timezone,
    'utc_offset_minutes', context.utc_offset_minutes,
    'settings_updated_at_utc',
      to_char(context.settings_updated_at AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'settings_provenance', context.settings_provenance,
    'captured_at_utc',
      to_char(context.captured_at AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'config_sha256', context.config_sha256,
    'evidence_version', context.evidence_version
  )::text, 'sha256'), 'hex')
  WHERE context.id = _context_id
$$;

INSERT INTO public.alert_judgment_subject_contexts (
  id, version_id, user_id, effective_from, effective_to,
  raw_sensitivity, canonical_sensitivity, routine_mode,
  timezone, utc_offset_minutes, settings_updated_at, settings_provenance,
  captured_at, config_sha256, evidence_version, subject_context_sha256
)
SELECT
  '46100000-0000-0000-0000-000000000020',
  version.id,
  '46000000-0000-0000-0000-000000000020',
  '2026-07-01 00:00+00',
  '2026-08-01 00:00+00',
  'balanced', 'balanced', 'regular_9to5', 'UTC', 0,
  '2026-07-11 08:00+00',
  '{"source":"as-of-boundary-test"}'::jsonb,
  '2026-07-11 08:01+00',
  version.config_sha256,
  version.evidence_version,
  repeat('0', 64)
FROM public.alert_model_versions version
WHERE version.id = '46000000-0000-0000-0000-000000000010';
SELECT pg_temp.rehash_candidate_subject(
  '46100000-0000-0000-0000-000000000020'
);
SELECT is(
  private.resolve_alert_candidate(
    '46000000-0000-0000-0000-000000000020',
    '2026-07-11 08:00+00',
    '46000000-0000-0000-0000-000000000010'
  ) ->> 'unreplayable_reason',
  'missing_subject_context',
  'a subject context captured after evaluation is not projected backward'
);

UPDATE public.alert_judgment_subject_contexts
SET captured_at = '2026-07-11 08:00+00',
    effective_to = '2026-07-11 08:00+00'
WHERE id = '46100000-0000-0000-0000-000000000020';
SELECT pg_temp.rehash_candidate_subject(
  '46100000-0000-0000-0000-000000000020'
);
SELECT is(
  private.resolve_alert_candidate(
    '46000000-0000-0000-0000-000000000020',
    '2026-07-11 08:00+00',
    '46000000-0000-0000-0000-000000000010'
  ) ->> 'unreplayable_reason',
  'missing_subject_context',
  'subject context effective ranges use an exact half-open upper bound'
);

UPDATE public.alert_judgment_subject_contexts
SET effective_to = '2026-08-01 00:00+00',
    config_sha256 = repeat('a', 64)
WHERE id = '46100000-0000-0000-0000-000000000020';
SELECT pg_temp.rehash_candidate_subject(
  '46100000-0000-0000-0000-000000000020'
);
SELECT is(
  private.resolve_alert_candidate(
    '46000000-0000-0000-0000-000000000020',
    '2026-07-11 08:00+00',
    '46000000-0000-0000-0000-000000000010'
  ) ->> 'unreplayable_reason',
  'subject_context_provenance_invalid',
  'a correctly hashed subject row with the wrong config pin fails closed'
);

UPDATE public.alert_judgment_subject_contexts context
SET config_sha256 = version.config_sha256,
    evidence_version = 'canonical-v1'
FROM public.alert_model_versions version
WHERE context.id = '46100000-0000-0000-0000-000000000020'
  AND version.id = context.version_id;
SELECT pg_temp.rehash_candidate_subject(
  '46100000-0000-0000-0000-000000000020'
);
SELECT is(
  private.resolve_alert_candidate(
    '46000000-0000-0000-0000-000000000020',
    '2026-07-11 08:00+00',
    '46000000-0000-0000-0000-000000000010'
  ) ->> 'unreplayable_reason',
  'subject_context_provenance_invalid',
  'a correctly hashed subject row with the wrong evidence pin fails closed'
);

-- Current mutable settings differ from the persisted snapshot, but the snapshot wins.
SELECT results_eq(
  $$
    SELECT
      result #>> '{decision_provenance,canonical_sensitivity}',
      result #>> '{decision_provenance,routine_mode}',
      result #>> '{decision_provenance,timezone}'
    FROM (SELECT private.resolve_alert_candidate(
      '46000000-0000-0000-0000-000000000001',
      '2026-07-11 08:00+00',
      '46000000-0000-0000-0000-000000000010'
    ) AS result) evaluated
  $$,
  $$ VALUES ('high'::text, 'regular_9to5'::text, 'UTC'::text) $$,
  'evaluator never projects current mutable sensitivity, mode, or timezone backward'
);

-- A newly committed canonical protected-user ping becomes the latest session.
INSERT INTO public.behavior_pings (user_id, kind, at, received_at, ingest_version)
VALUES (
  '46000000-0000-0000-0000-000000000009',
  'app',
  '2026-07-11 07:50+00',
  '2026-07-11 07:50+00',
  2
);
SELECT results_eq(
  $$
    SELECT
      (result ->> 'would_alert')::boolean,
      round((result ->> 'effective_silence_minutes')::numeric, 3),
      result #>> '{decision_provenance,latest_session,session_end_utc}'
    FROM (SELECT private.resolve_alert_candidate(
      '46000000-0000-0000-0000-000000000009',
      '2026-07-11 08:00+00',
      '46000000-0000-0000-0000-000000000010'
    ) AS result) evaluated
  $$,
  $$ VALUES (
    false,
    10.000::numeric,
    '2026-07-11T07:50:00.000000Z'::text
  ) $$,
  'atomic canonical activity changes would-alert to false in the evaluator snapshot'
);

-- A post-cutoff receipt is not historical activity.
INSERT INTO public.behavior_pings (user_id, kind, at, received_at, ingest_version)
VALUES (
  '46000000-0000-0000-0000-000000000019',
  'app',
  '2026-07-11 07:50+00',
  '2026-07-11 08:01+00',
  2
);
SELECT is(
  (private.resolve_alert_candidate(
    '46000000-0000-0000-0000-000000000019',
    '2026-07-11 08:00+00',
    '46000000-0000-0000-0000-000000000010'
  ) #>> '{decision_provenance,latest_session,session_end_utc}'),
  '2026-07-10T22:30:00.000000Z',
  'activity received after the exclusive evidence cutoff is ignored'
);

-- Guardian confirmation is external evidence and cannot alter protected-user timing.
CREATE TEMP TABLE guardian_before AS
SELECT private.resolve_alert_candidate(
  '46000000-0000-0000-0000-000000000010',
  '2026-07-11 08:00+00',
  '46000000-0000-0000-0000-000000000010'
) AS result;

INSERT INTO public.alerts (
  id, user_id, cause, stage, status, opened_at, stage_entered_at, resolved_at
) VALUES (
  '46200000-0000-0000-0000-000000000010',
  '46000000-0000-0000-0000-000000000010',
  'silence', 'self', 'resolved',
  '2026-07-11 06:00+00', '2026-07-11 06:00+00', '2026-07-11 07:00+00'
);
INSERT INTO public.alert_events (alert_id, actor_id, kind, at)
VALUES (
  '46200000-0000-0000-0000-000000000010',
  '46000000-0000-0000-0000-000000000099',
  'confirmed_safe',
  '2026-07-11 07:00+00'
);
SELECT results_eq(
  $$
    SELECT
      after.result ->> 'effective_silence_minutes',
      after.result ->> 'candidate_deadline',
      after.result #>> '{decision_provenance,latest_session,session_end_utc}',
      (after.result ->> 'guardian_used_as_activity')::boolean,
      after.result ->> 'provenance_sha256'
    FROM guardian_before before
    CROSS JOIN LATERAL (
      SELECT private.resolve_alert_candidate(
        '46000000-0000-0000-0000-000000000010',
        '2026-07-11 08:00+00',
        '46000000-0000-0000-0000-000000000010'
      ) AS result
    ) after
    WHERE after.result ->> 'effective_silence_minutes'
          = before.result ->> 'effective_silence_minutes'
      AND after.result ->> 'candidate_deadline'
          = before.result ->> 'candidate_deadline'
      AND after.result ->> 'provenance_sha256'
          = before.result ->> 'provenance_sha256'
  $$,
  $$ VALUES (
    '570'::text,
    '2026-07-11T00:00:00.000000Z'::text,
    '2026-07-10T22:30:00.000000Z'::text,
    false,
    (SELECT result ->> 'provenance_sha256' FROM guardian_before)
  ) $$,
  'Guardian confirmation leaves canonical session, effective silence, deadline, and provenance unchanged'
);

-- Simulate a pre-Task-6 legacy personal row whose evidence pin no longer
-- matches. The owner-only pin trigger prevents this on normal new mutations.
ALTER TABLE public.alert_gap_profiles
  DISABLE TRIGGER on_alert_gap_profile_contract_pin;
UPDATE public.alert_gap_profiles
SET evidence_version = 'canonical-v1'
WHERE version_id = '46000000-0000-0000-0000-000000000010'
  AND user_id = '46000000-0000-0000-0000-000000000015'
  AND context_key = 'personal_global';
ALTER TABLE public.alert_gap_profiles
  ENABLE TRIGGER on_alert_gap_profile_contract_pin;
SELECT results_eq(
  $$
    SELECT
      result ->> 'basis',
      (result ->> 'neutral_threshold_minutes')::integer,
      result -> 'fallback_path'
    FROM (SELECT private.resolve_alert_candidate(
      '46000000-0000-0000-0000-000000000015',
      '2026-07-11 08:00+00',
      '46000000-0000-0000-0000-000000000010'
    ) AS result) evaluated
  $$,
  $$ VALUES (
    'routine_cohort'::text,
    100,
    '["personal_context","personal_global","routine_cohort"]'::jsonb
  ) $$,
  'personal evidence-pin mismatch falls through without reinterpreting the row'
);

-- Profile config pins make old rows unusable after a same-version config change,
-- once a newly captured subject context binds the new config.
UPDATE public.alert_model_versions
SET config = jsonb_set(config, '{candidate_bounds,ceiling_minutes}', '160'::jsonb)
WHERE id = '46000000-0000-0000-0000-000000000020';
UPDATE public.alert_model_versions
SET config_sha256 = encode(extensions.digest(config::text, 'sha256'), 'hex')
WHERE id = '46000000-0000-0000-0000-000000000020';
UPDATE public.alert_judgment_subject_contexts context
SET config_sha256 = version.config_sha256
FROM public.alert_model_versions version
WHERE context.version_id = version.id
  AND context.version_id = '46000000-0000-0000-0000-000000000020'
  AND context.user_id = '46000000-0000-0000-0000-000000000007';
UPDATE public.alert_judgment_subject_contexts context
SET subject_context_sha256 = encode(extensions.digest(jsonb_build_object(
  'version_id', context.version_id,
  'user_id', context.user_id,
  'effective_from_utc',
    to_char(context.effective_from AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'effective_to_utc',
    to_char(context.effective_to AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'raw_sensitivity', context.raw_sensitivity,
  'canonical_sensitivity', context.canonical_sensitivity,
  'routine_mode', context.routine_mode,
  'timezone', context.timezone,
  'utc_offset_minutes', context.utc_offset_minutes,
  'settings_updated_at_utc',
    to_char(context.settings_updated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'settings_provenance', context.settings_provenance,
  'captured_at_utc',
    to_char(context.captured_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'config_sha256', context.config_sha256,
  'evidence_version', context.evidence_version
)::text, 'sha256'), 'hex')
WHERE context.version_id = '46000000-0000-0000-0000-000000000020'
  AND context.user_id = '46000000-0000-0000-0000-000000000007';
SELECT is(
  (private.resolve_alert_candidate(
    '46000000-0000-0000-0000-000000000007',
    '2026-07-11 08:00+00',
    '46000000-0000-0000-0000-000000000020'
  ) ->> 'basis'),
  'deterministic_emergency',
  'same-version config drift invalidates pinned personal rows until rebuild'
);

-- The cohort tier independently enforces its safe UTC cutoff and every
-- aggregate pin/gate before it can be consumed.
INSERT INTO public.routine_mode_cohort_priors (
  version_id, routine_mode, context_key, through_date,
  contributor_count, distinct_support_dates, support_started_on, support_ended_on,
  latest_evidence_at, oldest_evidence_at, valid_until,
  conservative_span_days, minimum_profile_confidence,
  neutral_p95_minutes, quality_state, confidence, algorithm,
  config_sha256, evidence_version, source_generation,
  input_sha256, prior_sha256
)
SELECT
  version_id, routine_mode, context_key, '2026-07-11',
  contributor_count, distinct_support_dates, support_started_on, support_ended_on,
  latest_evidence_at, oldest_evidence_at, valid_until,
  conservative_span_days, minimum_profile_confidence,
  999, quality_state, confidence, algorithm,
  config_sha256, evidence_version, source_generation,
  repeat('d', 64), repeat('0', 64)
FROM public.routine_mode_cohort_priors
WHERE version_id = '46000000-0000-0000-0000-000000000010'
  AND routine_mode = 'regular_9to5'
  AND through_date = '2026-07-10';
SELECT pg_temp.rehash_candidate_prior(
  '46000000-0000-0000-0000-000000000010',
  'regular_9to5',
  '2026-07-11'
);
SELECT results_eq(
  $$
    SELECT
      result ->> 'basis',
      (result ->> 'neutral_threshold_minutes')::integer
    FROM (SELECT private.resolve_alert_candidate(
      '46000000-0000-0000-0000-000000000003',
      '2026-07-11 08:00+00',
      '46000000-0000-0000-0000-000000000010'
    ) AS result) evaluated
  $$,
  $$ VALUES ('routine_cohort'::text, 100) $$,
  'a newer cohort row whose exclusive UTC cutoff is future cannot leak into evaluation'
);
DELETE FROM public.routine_mode_cohort_priors
WHERE version_id = '46000000-0000-0000-0000-000000000010'
  AND routine_mode = 'regular_9to5'
  AND through_date = '2026-07-11';

UPDATE public.routine_mode_cohort_priors
SET config_sha256 = repeat('f', 64)
WHERE version_id = '46000000-0000-0000-0000-000000000010'
  AND routine_mode = 'regular_9to5'
  AND through_date = '2026-07-10';
SELECT pg_temp.rehash_candidate_prior(
  '46000000-0000-0000-0000-000000000010',
  'regular_9to5',
  '2026-07-10'
);
SELECT is(
  private.resolve_alert_candidate(
    '46000000-0000-0000-0000-000000000003',
    '2026-07-11 08:00+00',
    '46000000-0000-0000-0000-000000000010'
  ) ->> 'basis',
  'deterministic_emergency',
  'cohort config-pin mismatch falls to deterministic emergency'
);
UPDATE public.routine_mode_cohort_priors prior
SET config_sha256 = version.config_sha256
FROM public.alert_model_versions version
WHERE prior.version_id = version.id
  AND prior.version_id = '46000000-0000-0000-0000-000000000010'
  AND prior.routine_mode = 'regular_9to5'
  AND prior.through_date = '2026-07-10';
SELECT pg_temp.rehash_candidate_prior(
  '46000000-0000-0000-0000-000000000010',
  'regular_9to5',
  '2026-07-10'
);

UPDATE public.routine_mode_cohort_priors
SET evidence_version = 'canonical-v1'
WHERE version_id = '46000000-0000-0000-0000-000000000010'
  AND routine_mode = 'regular_9to5'
  AND through_date = '2026-07-10';
SELECT pg_temp.rehash_candidate_prior(
  '46000000-0000-0000-0000-000000000010',
  'regular_9to5',
  '2026-07-10'
);
SELECT is(
  private.resolve_alert_candidate(
    '46000000-0000-0000-0000-000000000003',
    '2026-07-11 08:00+00',
    '46000000-0000-0000-0000-000000000010'
  ) ->> 'basis',
  'deterministic_emergency',
  'cohort evidence-pin mismatch falls to deterministic emergency'
);
UPDATE public.routine_mode_cohort_priors prior
SET evidence_version = version.evidence_version
FROM public.alert_model_versions version
WHERE prior.version_id = version.id
  AND prior.version_id = '46000000-0000-0000-0000-000000000010'
  AND prior.routine_mode = 'regular_9to5'
  AND prior.through_date = '2026-07-10';
SELECT pg_temp.rehash_candidate_prior(
  '46000000-0000-0000-0000-000000000010',
  'regular_9to5',
  '2026-07-10'
);

UPDATE public.routine_mode_cohort_priors
SET valid_until = '2026-07-11 08:00+00'
WHERE version_id = '46000000-0000-0000-0000-000000000010'
  AND routine_mode = 'regular_9to5'
  AND through_date = '2026-07-10';
SELECT pg_temp.rehash_candidate_prior(
  '46000000-0000-0000-0000-000000000010',
  'regular_9to5',
  '2026-07-10'
);
SELECT is(
  private.resolve_alert_candidate(
    '46000000-0000-0000-0000-000000000003',
    '2026-07-11 08:00+00',
    '46000000-0000-0000-0000-000000000010'
  ) ->> 'basis',
  'deterministic_emergency',
  'expired or non-canonical cohort validity horizon is rejected'
);
UPDATE public.routine_mode_cohort_priors
SET valid_until = '2026-08-09 12:00+00'
WHERE version_id = '46000000-0000-0000-0000-000000000010'
  AND routine_mode = 'regular_9to5'
  AND through_date = '2026-07-10';
SELECT pg_temp.rehash_candidate_prior(
  '46000000-0000-0000-0000-000000000010',
  'regular_9to5',
  '2026-07-10'
);

UPDATE public.routine_mode_cohort_priors
SET contributor_count = 1,
    confidence = 0.5
WHERE version_id = '46000000-0000-0000-0000-000000000010'
  AND routine_mode = 'regular_9to5'
  AND through_date = '2026-07-10';
SELECT pg_temp.rehash_candidate_prior(
  '46000000-0000-0000-0000-000000000010',
  'regular_9to5',
  '2026-07-10'
);
SELECT is(
  private.resolve_alert_candidate(
    '46000000-0000-0000-0000-000000000003',
    '2026-07-11 08:00+00',
    '46000000-0000-0000-0000-000000000010'
  ) ->> 'basis',
  'deterministic_emergency',
  'cohort support and confidence gates are independently rechecked'
);
UPDATE public.routine_mode_cohort_priors
SET contributor_count = 2,
    confidence = 1
WHERE version_id = '46000000-0000-0000-0000-000000000010'
  AND routine_mode = 'regular_9to5'
  AND through_date = '2026-07-10';
SELECT pg_temp.rehash_candidate_prior(
  '46000000-0000-0000-0000-000000000010',
  'regular_9to5',
  '2026-07-10'
);

-- Cohort digest and source generation mismatches are candidate-tier failures,
-- not corrupt replay truth.
UPDATE public.routine_mode_cohort_priors
SET prior_sha256 = repeat('0', 64)
WHERE version_id = '46000000-0000-0000-0000-000000000010'
  AND routine_mode = 'regular_9to5';
SELECT is(
  (private.resolve_alert_candidate(
    '46000000-0000-0000-0000-000000000003',
    '2026-07-11 08:00+00',
    '46000000-0000-0000-0000-000000000010'
  ) ->> 'basis'),
  'deterministic_emergency',
  'corrupt cohort hash falls to deterministic emergency'
);
UPDATE public.routine_mode_cohort_priors prior
SET prior_sha256 = encode(extensions.digest(concat_ws('|',
  prior.input_sha256, prior.version_id::text, prior.routine_mode,
  prior.context_key, prior.through_date::text, prior.contributor_count::text,
  prior.distinct_support_dates::text, prior.conservative_span_days::text,
  prior.support_started_on::text, prior.support_ended_on::text,
  prior.latest_evidence_at::text, prior.oldest_evidence_at::text,
  prior.valid_until::text, prior.neutral_p95_minutes::text,
  prior.quality_state, prior.confidence::text,
  prior.minimum_profile_confidence::text, prior.algorithm,
  prior.config_sha256, prior.evidence_version, prior.source_generation::text
), 'sha256'), 'hex')
WHERE prior.version_id = '46000000-0000-0000-0000-000000000010'
  AND prior.routine_mode = 'regular_9to5';
UPDATE public.profiles
SET consent_data_sharing = NOT consent_data_sharing
WHERE id = '46000000-0000-0000-0000-000000000001';
SELECT is(
  (private.resolve_alert_candidate(
    '46000000-0000-0000-0000-000000000003',
    '2026-07-11 08:00+00',
    '46000000-0000-0000-0000-000000000010'
  ) ->> 'basis'),
  'deterministic_emergency',
  'cohort source-generation mismatch falls to deterministic emergency'
);

-- The immutable pre-promotion pin recognizes only its explicitly authorized
-- history-seeded successor definition.
SELECT ok(
  private.shadow_live_definition_matches(
    (
      SELECT config #>> '{emergency,expected_live_definition_sha256}'
      FROM public.alert_model_versions
      WHERE id = '46000000-0000-0000-0000-000000000010'
    ),
    pg_get_functiondef(
      'private.silence_threshold(uuid)'::regprocedure
    )
  ),
  'configured pre-promotion pin recognizes the authorized live successor'
);
SELECT results_eq(
  $$
    SELECT settings.sensitivity,
      extract(epoch FROM private.silence_threshold(settings.user_id))::integer / 60
    FROM (VALUES
      ('46000000-0000-0000-0000-000000000004'::uuid, 'high'::text),
      ('46000000-0000-0000-0000-000000000005'::uuid, 'balanced'::text),
      ('46000000-0000-0000-0000-000000000006'::uuid, 'low'::text)
    ) settings(user_id, sensitivity)
    ORDER BY settings.sensitivity
  $$,
  $$ VALUES
    ('balanced'::text, 135),
    ('high'::text, 90),
    ('low'::text, 180)
  $$,
  'pure emergency high/default/low results match the live ADR-0022 contract'
);

-- Deterministic provenance is independent of caller timezone.
CREATE TEMP TABLE utc_candidate AS
SELECT private.resolve_alert_candidate(
  '46000000-0000-0000-0000-000000000001',
  '2026-07-11 08:00+00',
  '46000000-0000-0000-0000-000000000010'
) AS result;
SET LOCAL TIME ZONE 'Asia/Tokyo';
SELECT results_eq(
  $$
    SELECT
      tokyo.result ->> 'provenance_sha256',
      tokyo.result ->> 'candidate_deadline',
      tokyo.result ->> 'evidence_cutoff'
    FROM utc_candidate utc
    CROSS JOIN LATERAL (
      SELECT private.resolve_alert_candidate(
        '46000000-0000-0000-0000-000000000001',
        '2026-07-11 08:00+00',
        '46000000-0000-0000-0000-000000000010'
      ) AS result
    ) tokyo
    WHERE tokyo.result ->> 'provenance_sha256'
          = utc.result ->> 'provenance_sha256'
  $$,
  $$
    SELECT
      result ->> 'provenance_sha256',
      result ->> 'candidate_deadline',
      result ->> 'evidence_cutoff'
    FROM utc_candidate
  $$,
  'UTC canonical timestamps make decision provenance caller-timezone independent'
);
SET LOCAL TIME ZONE 'UTC';

-- Browser-local quiet windows have no server table. The nearest live-path
-- exclusions (sleep-window helper, alert pause, check-in deadline, and
-- device absence/outage state) must all leave the versioned candidate intact.
CREATE TEMP TABLE forbidden_exclusion_before AS
SELECT
  private.resolve_alert_candidate(
    '46000000-0000-0000-0000-000000000016',
    '2026-07-11 08:00+00',
    '46000000-0000-0000-0000-000000000010'
  ) AS result,
  NOT EXISTS (
    SELECT 1
    FROM public.device_state
    WHERE user_id = '46000000-0000-0000-0000-000000000016'
  ) AS device_absent;

UPDATE public.user_settings
SET timezone = 'UTC',
    sleep_start_local = '22:00',
    sleep_end_local = '09:00'
WHERE user_id = '46000000-0000-0000-0000-000000000016';
INSERT INTO public.alerts (
  id, user_id, cause, stage, status, opened_at, stage_entered_at,
  next_deadline, paused_until, paused_by
) VALUES (
  '46200000-0000-0000-0000-000000000016',
  '46000000-0000-0000-0000-000000000016',
  'silence', 'self', 'open',
  '2026-07-11 06:00+00', '2026-07-11 06:00+00',
  '2026-07-11 07:00+00', '2026-07-11 12:00+00',
  '46000000-0000-0000-0000-000000000099'
);
INSERT INTO public.checkin_tasks (
  id, ward_id, created_by, kind, interval_hours, grace_minutes,
  label, status, cycle_state, next_due_at
) VALUES (
  '46300000-0000-0000-0000-000000000016',
  '46000000-0000-0000-0000-000000000016',
  '46000000-0000-0000-0000-000000000016',
  'interval', 2, 30, 'forbidden evaluator deadline',
  'active', 'due_notified', '2026-07-11 07:00+00'
);
DELETE FROM public.device_state
WHERE user_id = '46000000-0000-0000-0000-000000000016';

INSERT INTO public.device_state (
  user_id, status, last_heartbeat_at, updated_at
) VALUES (
  '46000000-0000-0000-0000-000000000016',
  'alert',
  '2026-07-01 00:00+00',
  '2026-07-11 08:00+00'
);
SELECT results_eq(
  $$
    SELECT
      before.device_absent,
      private.is_in_sleep_window(
        '46000000-0000-0000-0000-000000000016',
        '2026-07-11 08:00+00'
      ),
      alert.paused_until > '2026-07-11 08:00+00',
      task.next_due_at + make_interval(mins => task.grace_minutes)
        <= '2026-07-11 08:00+00',
      device.status = 'alert'
        AND '2026-07-11 08:00+00'::timestamptz
          - device.last_heartbeat_at > interval '18 hours',
      private.resolve_alert_candidate(
        '46000000-0000-0000-0000-000000000016',
        '2026-07-11 08:00+00',
        '46000000-0000-0000-0000-000000000010'
      ) = before.result,
      lower(pg_get_functiondef(
        'private.resolve_alert_candidate(uuid,timestamptz,uuid)'::regprocedure
      )) !~ 'localstorage|kc[.]baselineconfig|quietwindows|quiet_windows|paused_until|checkin_tasks|next_due_at|device_state|is_in_sleep_window'
    FROM forbidden_exclusion_before before
    JOIN public.alerts alert
      ON alert.id = '46200000-0000-0000-0000-000000000016'
    JOIN public.checkin_tasks task
      ON task.id = '46300000-0000-0000-0000-000000000016'
    JOIN public.device_state device
      ON device.user_id = '46000000-0000-0000-0000-000000000016'
  $$,
  $$ VALUES (true, true, true, true, true, true, true) $$,
  'candidate ignores browser quiet, current sleep, pause, task, and device absence/outage gates'
);

-- The evaluator is pure: representative calls cannot mutate any live path.
CREATE TEMP TABLE evaluator_live_before AS
SELECT
  (SELECT count(*)::bigint FROM public.alerts) AS alerts_count,
  (SELECT coalesce(md5(string_agg(to_jsonb(a)::text, ',' ORDER BY a.id)), '')
   FROM public.alerts a) AS alerts_hash,
  (SELECT count(*)::bigint FROM public.alert_events) AS events_count,
  (SELECT coalesce(md5(string_agg(to_jsonb(e)::text, ',' ORDER BY e.id)), '')
   FROM public.alert_events e) AS events_hash,
  (SELECT count(*)::bigint FROM public.notifications) AS notifications_count,
  (SELECT coalesce(md5(string_agg(to_jsonb(n)::text, ',' ORDER BY n.id)), '')
   FROM public.notifications n) AS notifications_hash,
  (SELECT count(*)::bigint FROM public.behavior_pings) AS pings_count,
  (SELECT coalesce(md5(string_agg(to_jsonb(p)::text, ',' ORDER BY p.id)), '')
   FROM public.behavior_pings p) AS pings_hash,
  (SELECT count(*)::bigint FROM public.device_state) AS device_count,
  (SELECT coalesce(md5(string_agg(to_jsonb(d)::text, ',' ORDER BY d.user_id)), '')
   FROM public.device_state d) AS device_hash,
  (SELECT count(*)::bigint FROM public.checkin_tasks) AS tasks_count,
  (SELECT coalesce(md5(string_agg(to_jsonb(t)::text, ',' ORDER BY t.id)), '')
   FROM public.checkin_tasks t) AS tasks_hash;

SELECT private.resolve_alert_candidate(
  '46000000-0000-0000-0000-000000000001',
  '2026-07-11 08:00+00',
  '46000000-0000-0000-0000-000000000010'
);
SELECT private.resolve_alert_candidate(
  '46000000-0000-0000-0000-000000000003',
  '2026-07-11 08:00+00',
  '46000000-0000-0000-0000-000000000010'
);
SELECT private.resolve_alert_candidate(
  '46000000-0000-0000-0000-000000000004',
  '2026-07-11 08:00+00',
  '46000000-0000-0000-0000-000000000010'
);

SELECT results_eq(
  $$
    SELECT * FROM evaluator_live_before
    EXCEPT
    SELECT
      (SELECT count(*)::bigint FROM public.alerts),
      (SELECT coalesce(md5(string_agg(to_jsonb(a)::text, ',' ORDER BY a.id)), '')
       FROM public.alerts a),
      (SELECT count(*)::bigint FROM public.alert_events),
      (SELECT coalesce(md5(string_agg(to_jsonb(e)::text, ',' ORDER BY e.id)), '')
       FROM public.alert_events e),
      (SELECT count(*)::bigint FROM public.notifications),
      (SELECT coalesce(md5(string_agg(to_jsonb(n)::text, ',' ORDER BY n.id)), '')
       FROM public.notifications n),
      (SELECT count(*)::bigint FROM public.behavior_pings),
      (SELECT coalesce(md5(string_agg(to_jsonb(p)::text, ',' ORDER BY p.id)), '')
       FROM public.behavior_pings p),
      (SELECT count(*)::bigint FROM public.device_state),
      (SELECT coalesce(md5(string_agg(to_jsonb(d)::text, ',' ORDER BY d.user_id)), '')
       FROM public.device_state d),
      (SELECT count(*)::bigint FROM public.checkin_tasks),
      (SELECT coalesce(md5(string_agg(to_jsonb(t)::text, ',' ORDER BY t.id)), '')
       FROM public.checkin_tasks t)
  $$,
  $$ SELECT * FROM evaluator_live_before WHERE false $$,
  'evaluator leaves all live alert-path counts and full-row hashes unchanged'
);
SELECT results_eq(
  $$
    SELECT fn, encode(
      extensions.digest(replace(pg_get_functiondef(oid), E'\r\n', E'\n'), 'sha256'),
      'hex'
    )
    FROM (
      VALUES
        ('private.silence_threshold(uuid)'::regprocedure::oid, 'silence_threshold'::text),
        ('public.process_escalations()'::regprocedure::oid, 'process_escalations'::text)
    ) functions(oid, fn)
    ORDER BY fn
  $$,
  $$ VALUES
    ('process_escalations'::text, 'fde0f2ec750cec9b3e55e04c95f14f93fecea39843a661abd2d37b8a2f6108c5'::text),
    ('silence_threshold'::text, '6be4ed54feff52428cf1d86210126bd9362953201fc5ac8b9e885abd586092ce'::text)
  $$,
  'Task 6 leaves ADR-0022 live threshold and Guardian 30-minute state machine definitions unchanged'
);
-- An unknown sleep context finalized after evaluated_at cannot change
-- sleep/effective-silence results and cannot leak that future finalized timestamp into provenance.
CREATE TEMP TABLE unknown_future_sleep_before AS
SELECT private.resolve_alert_candidate(
  '46000000-0000-0000-0000-000000000001',
  '2026-07-11 08:00+00',
  '46000000-0000-0000-0000-000000000010'
) AS result;

INSERT INTO public.alert_sleep_night_contexts (
  version_id, user_id, anchor_date, timezone, sleep_start_local, sleep_end_local,
  anchor_starts_at, anchor_ends_at, utc_offset_minutes, coverage_state,
  captured_at, finalized_at, evidence_version, provenance_sha256
) VALUES (
  '46000000-0000-0000-0000-000000000010',
  '46000000-0000-0000-0000-000000000001',
  '2026-07-09', 'UTC', '23:00', '07:00',
  '2026-07-09 23:00+00', '2026-07-10 07:00+00', 0, 'unknown',
  '2026-07-09 22:00+00', '2026-07-11 09:00+00', 'canonical-v2', repeat('9', 64)
);

CREATE TEMP TABLE unknown_future_sleep_after AS
SELECT private.resolve_alert_candidate(
  '46000000-0000-0000-0000-000000000001',
  '2026-07-11 08:00+00',
  '46000000-0000-0000-0000-000000000010'
) AS result;

SELECT results_eq(
  $$ SELECT result FROM unknown_future_sleep_after $$,
  $$ SELECT result FROM unknown_future_sleep_before $$,
  'unknown sleep context finalized after evaluated_at does not alter evaluator result or provenance'
);
SELECT ok(
  (SELECT (result -> 'sleep_interval_provenance')::text FROM unknown_future_sleep_after) !~ '2026-07-11T09:00:00',
  'future finalized timestamp of unknown sleep context is not leaked into sleep interval provenance'
);

-- Evaluator under extreme caller DateStyle and extra_float_digits yields identical selected basis,
-- payload, provenance, profile, and prior hashes as baseline.
CREATE TEMP TABLE baseline_personal_eval AS
SELECT private.resolve_alert_candidate(
  '46000000-0000-0000-0000-000000000001',
  '2026-07-11 08:00+00',
  '46000000-0000-0000-0000-000000000010'
) AS result;

CREATE TEMP TABLE baseline_cohort_eval AS
SELECT private.resolve_alert_candidate(
  '46000000-0000-0000-0000-000000000003',
  '2026-07-11 08:00+00',
  '46000000-0000-0000-0000-000000000010'
) AS result;

SET LOCAL "DateStyle" = 'Postgres, MDY';
SET LOCAL extra_float_digits = -15;

SELECT results_eq(
  $$
    SELECT private.resolve_alert_candidate(
      '46000000-0000-0000-0000-000000000001',
      '2026-07-11 08:00+00',
      '46000000-0000-0000-0000-000000000010'
    )
  $$,
  $$ SELECT result FROM baseline_personal_eval $$,
  'extreme caller DateStyle and extra_float_digits yield identical personal-basis payload and hashes'
);

SELECT results_eq(
  $$
    SELECT private.resolve_alert_candidate(
      '46000000-0000-0000-0000-000000000003',
      '2026-07-11 08:00+00',
      '46000000-0000-0000-0000-000000000010'
    )
  $$,
  $$ SELECT result FROM baseline_cohort_eval $$,
  'extreme caller DateStyle and extra_float_digits yield identical cohort-basis payload and hashes'
);

SET LOCAL "DateStyle" = 'ISO, YMD';
SET LOCAL extra_float_digits = 3;

SELECT throws_ok(
  $$ SET LOCAL ROLE authenticated;
     SELECT private.resolve_alert_candidate(
       '46000000-0000-0000-0000-000000000001',
       '2026-07-11 08:00+00',
       '46000000-0000-0000-0000-000000000010'
     ) $$,
  '42501'::char(5),
  NULL,
  'authenticated Data API caller cannot execute the owner-only evaluator'
);

SELECT * FROM finish();
ROLLBACK;
