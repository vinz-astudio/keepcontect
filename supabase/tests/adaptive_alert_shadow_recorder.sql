-- ADR-0023 Task 8: fixture-only, unscheduled, non-notifying shadow recorder.
-- private.record_alert_judgment_shadow has zero live-alert authority: it only
-- consumes a version explicitly marked 'shadow' and private.resolve_alert_candidate
-- (Task 6), and only ever produces idempotent public.alert_judgment_shadow_decisions
-- rows. It is callable only by the owner in fixture validation and does not
-- schedule itself; because this task authorizes no subject-context, coverage,
-- or sleep-evidence producer, every successful call here legitimately reports
-- execution_scope='fixture_only_unscheduled' and operational_shadow=false.

BEGIN;

SELECT plan(67);

------------------------------------------------------------------------------
-- Fixture: users, groups, memberships, device_state, guardianship
------------------------------------------------------------------------------

INSERT INTO auth.users (id, email, aud, role) VALUES
  ('47000000-0000-0000-0000-000000000010', 'shadow-rec-success@example.invalid', 'authenticated', 'authenticated'),
  ('47000000-0000-0000-0000-000000000011', 'shadow-rec-nocontext@example.invalid', 'authenticated', 'authenticated'),
  ('47000000-0000-0000-0000-000000000012', 'shadow-rec-ambiguous@example.invalid', 'authenticated', 'authenticated'),
  ('47000000-0000-0000-0000-000000000013', 'shadow-rec-badprov@example.invalid', 'authenticated', 'authenticated'),
  ('47000000-0000-0000-0000-000000000014', 'shadow-rec-nosession@example.invalid', 'authenticated', 'authenticated'),
  ('47000000-0000-0000-0000-000000000015', 'shadow-rec-pending@example.invalid', 'authenticated', 'authenticated'),
  ('47000000-0000-0000-0000-000000000016', 'shadow-rec-unmonitored@example.invalid', 'authenticated', 'authenticated'),
  ('47000000-0000-0000-0000-000000000017', 'shadow-rec-ward@example.invalid', 'authenticated', 'authenticated'),
  ('47000000-0000-0000-0000-000000000018', 'shadow-rec-nodevice@example.invalid', 'authenticated', 'authenticated'),
  ('47000000-0000-0000-0000-000000000019', 'shadow-rec-duplicate@example.invalid', 'authenticated', 'authenticated'),
  ('47000000-0000-0000-0000-000000000021', 'shadow-rec-guardian@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.groups (id, name, created_by) VALUES
  ('47000000-0000-0000-0000-000000000001', 'shadow-recorder-g1', '47000000-0000-0000-0000-000000000010'),
  ('47000000-0000-0000-0000-000000000002', 'shadow-recorder-g2', '47000000-0000-0000-0000-000000000010')
ON CONFLICT (id) DO NOTHING;

-- Active + monitored: population members.
INSERT INTO public.group_members (group_id, user_id, status, monitored, watching) VALUES
  ('47000000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000010', 'active', true, true),
  ('47000000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000011', 'active', true, true),
  ('47000000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000012', 'active', true, true),
  ('47000000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000013', 'active', true, true),
  ('47000000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000014', 'active', true, true),
  ('47000000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000018', 'active', true, true),
  ('47000000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000019', 'active', true, true),
  ('47000000-0000-0000-0000-000000000002', '47000000-0000-0000-0000-000000000019', 'active', true, true)
ON CONFLICT (group_id, user_id) DO NOTHING;

-- Pending membership: excluded (not active).
INSERT INTO public.group_members (group_id, user_id, status, monitored, watching) VALUES
  ('47000000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000015', 'pending', true, true)
ON CONFLICT (group_id, user_id) DO NOTHING;

-- Active but unmonitored: excluded.
INSERT INTO public.group_members (group_id, user_id, status, monitored, watching) VALUES
  ('47000000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000016', 'active', false, true)
ON CONFLICT (group_id, user_id) DO NOTHING;

-- Guardianship-only: no group_members row at all.
INSERT INTO public.guardianships (guardian_id, ward_id, status) VALUES
  ('47000000-0000-0000-0000-000000000021', '47000000-0000-0000-0000-000000000017', 'active'),
  ('47000000-0000-0000-0000-000000000021', '47000000-0000-0000-0000-000000000010', 'active')
ON CONFLICT (guardian_id, ward_id) DO NOTHING;

-- device_state for every candidate except the no-device-state exclusion case.
INSERT INTO public.device_state (user_id) VALUES
  ('47000000-0000-0000-0000-000000000010'),
  ('47000000-0000-0000-0000-000000000011'),
  ('47000000-0000-0000-0000-000000000012'),
  ('47000000-0000-0000-0000-000000000013'),
  ('47000000-0000-0000-0000-000000000014'),
  ('47000000-0000-0000-0000-000000000015'),
  ('47000000-0000-0000-0000-000000000016'),
  ('47000000-0000-0000-0000-000000000017'),
  ('47000000-0000-0000-0000-000000000019')
ON CONFLICT (user_id) DO NOTHING;
-- 000018 deliberately has no device_state row.

-- A populated user already in device alert state and carrying an open alert
-- must still reach the evaluator; these are deliberately not population gates.
UPDATE public.device_state
SET status = 'alert'
WHERE user_id = '47000000-0000-0000-0000-000000000011';
INSERT INTO public.alerts (user_id, cause, stage, status, opened_at, stage_entered_at)
VALUES (
  '47000000-0000-0000-0000-000000000011',
  'silence', 'self', 'open',
  '2026-07-26 11:00:00+00', '2026-07-26 11:00:00+00'
);

------------------------------------------------------------------------------
-- Fixture: alert_model_versions (shadow + draft/replay/retired siblings)
------------------------------------------------------------------------------

CREATE TEMP TABLE shadow_recorder_config AS
SELECT '{
  "sessionization":{"gap_minutes":30,"per_user_day_gap_cap":8,"training_horizon_days":30,"intervention_window_minutes":30},
  "context":{"definition_version":"shadow-recorder-v1","day_partition":"all_days","hour_bucket_minutes":60},
  "personal":{"min_samples":3,"min_support_dates":2,"min_span_days":2,"max_age_days":30,"min_confidence":0.7,"confidence_formula_version":"support_ratio_v1"},
  "cohort":{"min_contributors":3,"min_support_dates":2,"min_span_days":2,"max_age_days":30,"min_confidence":0.5,"contribution_floor_minutes":1,"contribution_ceiling_minutes":600,"confidence_formula_version":"cohort_support_min_v1","algorithm":"trimmed_mean","trim_fraction":0.1},
  "sensitivity_buffers_minutes":{"high":0,"balanced":45,"low":90},
  "candidate_bounds":{"floor_minutes":1,"ceiling_minutes":600},
  "sleep_compensation":{"max_start_delay_minutes":60,"max_wake_advance_minutes":60,"max_wake_delay_minutes":60,"max_update_minutes_per_day":30,"min_positive_nights":2,"lookback_nights":3,"min_late_events_per_night":1,"timezone_tolerance_minutes":30},
  "evaluator":{"contract_version":"adaptive_candidate_v1"},
  "emergency":{"contract_version":"adr0022_v1","neutral_minutes":90,"expected_live_definition_sha256":"c3efc6cc664dc334166a034651ff584d4c7766d80775c3fe3bc012eb97a9b150"}
}'::jsonb AS config;

INSERT INTO public.alert_model_versions (id, name, status, config, config_sha256, evidence_version, shadow_enabled_at)
SELECT '47100000-0000-0000-0000-000000000001', 'shadow-recorder-shadow', 'shadow',
  config, encode(extensions.digest(config::text, 'sha256'), 'hex'), 'canonical-v2',
  '2026-07-01 00:00:00+00'
FROM shadow_recorder_config;

INSERT INTO public.alert_model_versions (id, name, status, config, config_sha256, evidence_version, shadow_enabled_at)
SELECT '47100000-0000-0000-0000-000000000002', 'shadow-recorder-draft', 'draft',
  config, encode(extensions.digest(config::text, 'sha256'), 'hex'), 'canonical-v2', NULL
FROM shadow_recorder_config;

INSERT INTO public.alert_model_versions (id, name, status, config, config_sha256, evidence_version, shadow_enabled_at)
SELECT '47100000-0000-0000-0000-000000000003', 'shadow-recorder-replay', 'replay',
  config, encode(extensions.digest(config::text, 'sha256'), 'hex'), 'canonical-v2', NULL
FROM shadow_recorder_config;

INSERT INTO public.alert_model_versions (id, name, status, config, config_sha256, evidence_version, shadow_enabled_at)
SELECT '47100000-0000-0000-0000-000000000004', 'shadow-recorder-retired', 'retired',
  config, encode(extensions.digest(config::text, 'sha256'), 'hex'), 'canonical-v2', NULL
FROM shadow_recorder_config;

------------------------------------------------------------------------------
-- Fixture: subject contexts (canonically hashed; one row deliberately bad)
------------------------------------------------------------------------------

WITH ctx(user_id, effective_from, effective_to, raw_sensitivity, canonical_sensitivity, routine_mode, tz, utc_offset_minutes, settings_updated_at, captured_at, force_bad_hash) AS (
  VALUES
    ('47000000-0000-0000-0000-000000000010'::uuid, '2026-07-01 00:00:00+00'::timestamptz, NULL::timestamptz, NULL::text, 'balanced'::text, 'regular_9to5'::text, 'UTC'::text, 0::integer, '2026-07-26 12:00:00+00'::timestamptz, '2026-07-26 12:00:00+00'::timestamptz, false),
    ('47000000-0000-0000-0000-000000000014'::uuid, '2026-07-01 00:00:00+00'::timestamptz, NULL::timestamptz, NULL::text, 'balanced'::text, 'regular_9to5'::text, 'UTC'::text, 0::integer, '2026-07-26 12:00:00+00'::timestamptz, '2026-07-26 12:00:00+00'::timestamptz, false),
    ('47000000-0000-0000-0000-000000000012'::uuid, '2026-07-01 00:00:00+00'::timestamptz, NULL::timestamptz, NULL::text, 'balanced'::text, 'regular_9to5'::text, 'UTC'::text, 0::integer, '2026-07-26 12:00:00+00'::timestamptz, '2026-07-26 12:00:00+00'::timestamptz, false),
    ('47000000-0000-0000-0000-000000000012'::uuid, '2026-07-10 00:00:00+00'::timestamptz, NULL::timestamptz, NULL::text, 'balanced'::text, 'regular_9to5'::text, 'UTC'::text, 0::integer, '2026-07-26 12:00:00+00'::timestamptz, '2026-07-26 12:00:00+00'::timestamptz, false),
    ('47000000-0000-0000-0000-000000000013'::uuid, '2026-07-01 00:00:00+00'::timestamptz, NULL::timestamptz, NULL::text, 'balanced'::text, 'regular_9to5'::text, 'UTC'::text, 0::integer, '2026-07-26 12:00:00+00'::timestamptz, '2026-07-26 12:00:00+00'::timestamptz, true)
), versioned AS (
  SELECT ctx.*,
    '47100000-0000-0000-0000-000000000001'::uuid AS version_id,
    (SELECT config_sha256 FROM public.alert_model_versions WHERE id = '47100000-0000-0000-0000-000000000001') AS config_sha256,
    'canonical-v2'::text AS evidence_version,
    '{}'::jsonb AS settings_provenance
  FROM ctx
), hashed AS (
  SELECT versioned.*,
    encode(extensions.digest(jsonb_build_object(
      'version_id', versioned.version_id,
      'user_id', versioned.user_id,
      'effective_from_utc', to_char(versioned.effective_from AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'effective_to_utc', CASE WHEN versioned.effective_to IS NULL THEN NULL
        ELSE to_char(versioned.effective_to AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') END,
      'raw_sensitivity', versioned.raw_sensitivity,
      'canonical_sensitivity', versioned.canonical_sensitivity,
      'routine_mode', versioned.routine_mode,
      'timezone', versioned.tz,
      'utc_offset_minutes', versioned.utc_offset_minutes,
      'settings_updated_at_utc', to_char(versioned.settings_updated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'settings_provenance', versioned.settings_provenance,
      'captured_at_utc', to_char(versioned.captured_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'config_sha256', versioned.config_sha256,
      'evidence_version', versioned.evidence_version
    )::text, 'sha256'), 'hex') AS computed_sha
  FROM versioned
)
INSERT INTO public.alert_judgment_subject_contexts (
  version_id, user_id, effective_from, effective_to, raw_sensitivity,
  canonical_sensitivity, routine_mode, timezone, utc_offset_minutes,
  settings_updated_at, settings_provenance, captured_at, config_sha256,
  evidence_version, subject_context_sha256
)
SELECT version_id, user_id, effective_from, effective_to, raw_sensitivity,
  canonical_sensitivity, routine_mode, tz, utc_offset_minutes,
  settings_updated_at, settings_provenance, captured_at, config_sha256,
  evidence_version,
  CASE WHEN force_bad_hash THEN repeat('f', 64) ELSE computed_sha END
FROM hashed;

------------------------------------------------------------------------------
-- Fixture: a genuine qualified session for the one fully-replayable user.
------------------------------------------------------------------------------

INSERT INTO public.alert_observation_coverage_intervals (
  version_id, user_id, starts_at, ends_at, timezone, utc_offset_minutes,
  activity_coverage_state, intervention_coverage_state, sleep_context_state,
  captured_at, finalized_at, evidence_version, provenance_sha256
) VALUES (
  '47100000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000010',
  '2026-07-26 08:00:00+00', '2026-07-26 10:00:00+00', 'UTC', 0,
  'valid', 'valid', 'valid',
  '2026-07-26 10:00:00+00', '2026-07-26 10:05:00+00', 'canonical-v2', repeat('4', 64)
);

INSERT INTO public.behavior_pings (user_id, kind, at, received_at, ingest_version)
VALUES ('47000000-0000-0000-0000-000000000010', 'app', '2026-07-26 09:00:00+00', '2026-07-26 09:00:00+00', 2);

------------------------------------------------------------------------------
-- Object / security assertions
------------------------------------------------------------------------------

SELECT ok(
  (
    SELECT p.prosecdef
      AND p.provolatile = 'v'
      AND p.proconfig @> ARRAY['search_path=""', 'TimeZone=UTC']
      AND r.rolname = current_user
    FROM pg_proc p
    JOIN pg_roles r ON r.oid = p.proowner
    WHERE p.oid = 'private.record_alert_judgment_shadow(uuid,timestamptz)'::regprocedure
  ),
  'recorder is owner-only VOLATILE SECURITY DEFINER with empty path and UTC'
);
SELECT ok(
  (
    SELECT r1.oid = r2.oid
    FROM (SELECT proowner AS oid FROM pg_proc
      WHERE oid = 'private.record_alert_judgment_shadow(uuid,timestamptz)'::regprocedure) r1,
    (SELECT proowner AS oid FROM pg_proc
      WHERE oid = 'private.resolve_alert_candidate(uuid,timestamptz,uuid)'::regprocedure) r2
  ),
  'recorder owner matches the Task 6 evaluator owner'
);
SELECT ok(
  (
    SELECT p.proowner = c.relowner
    FROM pg_proc p, pg_class c
    WHERE p.oid = 'private.record_alert_judgment_shadow(uuid,timestamptz)'::regprocedure
      AND c.oid = 'public.alert_judgment_shadow_decisions'::regclass
  ),
  'recorder owner matches the target table owner'
);
SELECT function_privs_are(
  'private', 'record_alert_judgment_shadow', ARRAY['uuid', 'timestamp with time zone'],
  'anon', ARRAY[]::text[]
);
SELECT function_privs_are(
  'private', 'record_alert_judgment_shadow', ARRAY['uuid', 'timestamp with time zone'],
  'authenticated', ARRAY[]::text[]
);
SELECT function_privs_are(
  'private', 'record_alert_judgment_shadow', ARRAY['uuid', 'timestamp with time zone'],
  'service_role', ARRAY[]::text[]
);
SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    WHERE p.oid = 'private.record_alert_judgment_shadow(uuid,timestamptz)'::regprocedure
      AND acl.grantee = 0
  ),
  'PUBLIC cannot execute the recorder'
);
SELECT ok(
  (
    SELECT count(*) = 1 AND bool_and(c.relrowsecurity)
    FROM pg_class c
    WHERE c.oid = 'public.alert_judgment_shadow_decisions'::regclass
  ),
  'shadow decision table still has RLS enabled after Task 8'
);
SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_policy p
    WHERE p.polrelid = 'public.alert_judgment_shadow_decisions'::regclass
  ),
  0,
  'shadow decision table still has zero RLS policies after Task 8'
);
SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM information_schema.column_privileges
    WHERE table_schema = 'public'
      AND table_name = 'alert_judgment_shadow_decisions'
      AND grantee IN ('PUBLIC', 'anon', 'authenticated', 'service_role')
  ),
  'shadow decision table still grants no Data API column privilege after Task 8'
);
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid = 'public.alert_judgment_shadow_decisions'::regclass
      AND NOT t.tgisinternal
  ),
  'shadow decision table has no producer trigger'
);
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'alert_judgment_shadow_decisions'
  ),
  'shadow decision table is not realtime after Task 8'
);
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM cron.job
    WHERE lower(command) ~ 'record_alert_judgment_shadow|resolve_alert_candidate'
       OR lower(jobname) ~ 'record_alert_judgment_shadow|resolve_alert_candidate'
  ),
  'no cron job references the recorder or the evaluator'
);
SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE NOT t.tgisinternal
      AND pg_get_functiondef(p.oid) ~* 'resolve_alert_candidate|record_alert_judgment_shadow'
  ),
  'no live-evidence trigger function references the candidate evaluator or recorder'
);
SELECT ok(
  (
    SELECT bool_and(r.rolname = current_user)
    FROM (VALUES
      ('private.silence_threshold(uuid)'::regprocedure::oid),
      ('public.process_escalations()'::regprocedure::oid)
    ) f(oid)
    JOIN pg_proc p ON p.oid = f.oid
    JOIN pg_roles r ON r.oid = p.proowner
  ),
  'process_escalations and silence_threshold remain owned by the migration role'
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
    ('process_escalations'::text, '8fc104c8b8a13ce2cb1dfc8c3958fd1cc1ff9ef451aaece8297c1584b88458c2'::text),
    ('silence_threshold'::text, 'c3efc6cc664dc334166a034651ff584d4c7766d80775c3fe3bc012eb97a9b150'::text)
  $$,
  'ADR-0042 pins the dual-engine guard while preserving the legacy threshold and Guardian state machine'
);
SELECT ok(
  pg_get_functiondef('private.record_alert_judgment_shadow(uuid,timestamptz)'::regprocedure) !~*
    'net\.http|pg_notify|notify\s|insert\s+into\s+public\.alerts|insert\s+into\s+public\.notifications|cron\.',
  'recorder source contains no network, notification, live-alert-write, or scheduling call'
);
-- The recorder pre-validates version/status/enable-minute/config-hash/evidence
-- before ever calling the evaluator, so the evaluator can never legitimately
-- return a run-level reason or a malformed shape to it in this fixture suite.
-- These are provable-by-source defensive guards, not mockable behavior.
SELECT ok(
  pg_get_functiondef('private.record_alert_judgment_shadow(uuid,timestamptz)'::regprocedure) ~
    'invalid_version_status'
  AND pg_get_functiondef('private.record_alert_judgment_shadow(uuid,timestamptz)'::regprocedure) ~
    'config_hash_mismatch'
  AND pg_get_functiondef('private.record_alert_judgment_shadow(uuid,timestamptz)'::regprocedure) ~
    'unsupported_evidence_version',
  'recorder aborts atomically if the evaluator ever returns a run-level reason'
);
SELECT ok(
  pg_get_functiondef('private.record_alert_judgment_shadow(uuid,timestamptz)'::regprocedure) ~ '\?&',
  'recorder validates the complete evaluator result key contract before use'
);

------------------------------------------------------------------------------
-- Live snapshot, taken after all fixtures and before any recorder call.
------------------------------------------------------------------------------

CREATE TEMP TABLE shadow_recorder_live_snapshot AS
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
  (SELECT coalesce(md5(string_agg(to_jsonb(c)::text, ',' ORDER BY c.id)), '') FROM public.checkin_tasks c) AS checkin_tasks_hash,
  (SELECT count(*)::bigint FROM net.http_request_queue) AS net_queue_count,
  (SELECT coalesce(md5(string_agg(to_jsonb(q)::text, ',' ORDER BY to_jsonb(q)::text)), '') FROM net.http_request_queue q) AS net_queue_hash;

------------------------------------------------------------------------------
-- Failure-mode assertions: run-level errors before user enumeration.
------------------------------------------------------------------------------

SELECT throws_ok(
  $$ SELECT private.record_alert_judgment_shadow(NULL, '2026-07-26 12:34:56+00') $$,
  NULL, NULL, 'a null evaluated_at fails'
);
SELECT throws_ok(
  $$ SELECT private.record_alert_judgment_shadow(
       '47100000-0000-0000-0000-000000000001', NULL
     ) $$,
  NULL, NULL, 'a null evaluated_at fails for a real version'
);
SELECT throws_ok(
  $$ SELECT private.record_alert_judgment_shadow(
       '47100000-0000-0000-0000-000000000001', 'infinity'::timestamptz
     ) $$,
  NULL, NULL, 'an infinite evaluated_at fails'
);
SELECT throws_ok(
  $$ SELECT private.record_alert_judgment_shadow(
       '47100000-0000-0000-0000-000000000001', '-infinity'::timestamptz
     ) $$,
  NULL, NULL, 'a negative-infinite evaluated_at fails'
);
SELECT throws_ok(
  $$ SELECT private.record_alert_judgment_shadow(
       '47100000-0000-0000-0000-000000000099', '2026-07-26 12:34:56+00'
     ) $$,
  NULL, NULL, 'a nonexistent version fails before user enumeration'
);
SELECT throws_ok(
  $$ SELECT private.record_alert_judgment_shadow(
       '47100000-0000-0000-0000-000000000001', '2026-06-30 23:59:00+00'
     ) $$,
  NULL, NULL, 'a call before shadow_enabled_at fails before user enumeration'
);
SELECT throws_ok(
  $$ SELECT private.record_alert_judgment_shadow(
       '47100000-0000-0000-0000-000000000002', '2026-07-26 12:34:56+00'
     ) $$,
  NULL, NULL, 'a draft-status version cannot record'
);
SELECT throws_ok(
  $$ SELECT private.record_alert_judgment_shadow(
       '47100000-0000-0000-0000-000000000003', '2026-07-26 12:34:56+00'
     ) $$,
  NULL, NULL, 'a replay-status version cannot record'
);
SELECT throws_ok(
  $$ SELECT private.record_alert_judgment_shadow(
       '47100000-0000-0000-0000-000000000004', '2026-07-26 12:34:56+00'
     ) $$,
  NULL, NULL, 'a retired-status version cannot record'
);
SELECT is(
  (SELECT count(*)::integer FROM public.alert_judgment_shadow_decisions),
  0,
  'every failed run-level call above leaves zero shadow decision rows'
);

------------------------------------------------------------------------------
-- Successful call #1: population filtering, per-user reasons, one insert.
------------------------------------------------------------------------------

SELECT results_eq(
  $$
    SELECT
      (r ->> 'recorder_contract_version'),
      (r ->> 'evaluator_version'),
      (r ->> 'execution_scope'),
      (r ->> 'operational_shadow'),
      (r ->> 'result_status'),
      (r ->> 'population_count'),
      (r ->> 'evaluated_count'),
      (r ->> 'replayable_count'),
      (r ->> 'inserted_count'),
      (r ->> 'duplicate_count'),
      (r ->> 'unreplayable_count'),
      (r -> 'unreplayable_reason_counts'),
      (r ->> 'skipped_count'),
      (r ->> 'error_count')
    FROM (
      SELECT private.record_alert_judgment_shadow(
        '47100000-0000-0000-0000-000000000001', '2026-07-26 12:34:56+00'
      ) AS r
    ) call
  $$,
  $$
    VALUES (
      'adaptive_shadow_recorder_v1', 'adaptive_candidate_v1', 'fixture_only_unscheduled',
      'false', 'partial', '6', '6', '1', '1', '0', '5',
      '{"missing_subject_context":2,"ambiguous_subject_context":1,"subject_context_provenance_invalid":1,"missing_qualified_session":1}'::jsonb,
      '5', '0'
    )
  $$,
  'first shadow recorder call reports the exact fixture-only aggregate contract'
);

SELECT is(
  (SELECT count(*)::integer FROM public.alert_judgment_shadow_decisions
   WHERE version_id = '47100000-0000-0000-0000-000000000001'),
  1,
  'exactly one shadow row exists per user/version/minute after the first call'
);
SELECT is(
  (SELECT count(*)::integer FROM public.alert_judgment_shadow_decisions
   WHERE version_id = '47100000-0000-0000-0000-000000000001'
     AND user_id = '47000000-0000-0000-0000-000000000010'),
  1,
  'the fully-replayable user got a shadow row'
);
SELECT ok(
  (
    SELECT guardian_used_as_activity = false
    FROM public.alert_judgment_shadow_decisions
    WHERE version_id = '47100000-0000-0000-0000-000000000001'
      AND user_id = '47000000-0000-0000-0000-000000000010'
  ),
  'Guardian evidence cannot change the stored decision and guardian_used_as_activity=false'
);

-- Population exclusions: excluded users never receive a shadow row nor are counted.
SELECT is(
  (SELECT count(*)::integer FROM public.alert_judgment_shadow_decisions
   WHERE user_id IN (
     '47000000-0000-0000-0000-000000000015', -- pending
     '47000000-0000-0000-0000-000000000016', -- unmonitored
     '47000000-0000-0000-0000-000000000017', -- guardianship-only
     '47000000-0000-0000-0000-000000000018'  -- no device_state
   )),
  0,
  'pending, unmonitored, guardianship-only, and no-device_state users are excluded'
);

------------------------------------------------------------------------------
-- Successful call #2: same UTC minute, exact representation -> idempotent.
------------------------------------------------------------------------------

CREATE TEMP TABLE shadow_recorder_row_before AS
SELECT to_jsonb(decision) AS payload
FROM public.alert_judgment_shadow_decisions AS decision
WHERE version_id = '47100000-0000-0000-0000-000000000001'
  AND user_id = '47000000-0000-0000-0000-000000000010';

SELECT results_eq(
  $$
    SELECT (r ->> 'inserted_count'), (r ->> 'duplicate_count'), (r ->> 'replayable_count')
    FROM (
      SELECT private.record_alert_judgment_shadow(
        '47100000-0000-0000-0000-000000000001', '2026-07-26 12:34:56+00'
      ) AS r
    ) call
  $$,
  $$ VALUES ('0', '1', '1') $$,
  'the second identical-minute call is a pure duplicate, not a new insert'
);

SELECT results_eq(
  $$
    SELECT to_jsonb(decision)
    FROM public.alert_judgment_shadow_decisions AS decision
    WHERE version_id = '47100000-0000-0000-0000-000000000001'
      AND user_id = '47000000-0000-0000-0000-000000000010'
  $$,
  $$ SELECT payload FROM shadow_recorder_row_before $$,
  'the second call preserves row id, created_at, full payload, and both provenance hashes'
);

------------------------------------------------------------------------------
-- Successful call #3: same absolute instant, different UTC offset -> idempotent.
------------------------------------------------------------------------------

SELECT results_eq(
  $$
    SELECT (r ->> 'inserted_count'), (r ->> 'duplicate_count')
    FROM (
      SELECT private.record_alert_judgment_shadow(
        '47100000-0000-0000-0000-000000000001', '2026-07-26 14:34:56+02'
      ) AS r
    ) call
  $$,
  $$ VALUES ('0', '1') $$,
  'an equivalent instant in a different UTC offset canonicalizes to the same duplicate decision'
);
SELECT is(
  (SELECT count(*)::integer FROM public.alert_judgment_shadow_decisions
   WHERE version_id = '47100000-0000-0000-0000-000000000001'
     AND user_id = '47000000-0000-0000-0000-000000000010'),
  1,
  'still exactly one shadow row after three calls at the same canonical minute'
);

------------------------------------------------------------------------------
-- Live snapshot unchanged across all recorder calls.
------------------------------------------------------------------------------

SELECT results_eq(
  $$
    SELECT * FROM shadow_recorder_live_snapshot
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
      (SELECT coalesce(md5(string_agg(to_jsonb(c)::text, ',' ORDER BY c.id)), '') FROM public.checkin_tasks c),
      (SELECT count(*)::bigint FROM net.http_request_queue),
      (SELECT coalesce(md5(string_agg(to_jsonb(q)::text, ',' ORDER BY to_jsonb(q)::text)), '') FROM net.http_request_queue q)
  $$,
  $$ SELECT * FROM shadow_recorder_live_snapshot WHERE false $$,
  'three shadow recorder calls leave all live alert-path counts and hashes unchanged'
);

------------------------------------------------------------------------------
-- Table-constraint assertions: the replaced candidate_threshold check.
------------------------------------------------------------------------------

-- A genuine learned ceiling cap whose final threshold sits below its own
-- neutral p95 must insert successfully (this is exactly the case the old
-- `candidate_threshold_minutes >= neutral_threshold_minutes` check forbade).
SELECT lives_ok(
  $$
    INSERT INTO public.alert_judgment_shadow_decisions (
      version_id, user_id, evaluated_at, basis, evaluator_version, context_key,
      neutral_threshold_minutes, sensitivity_buffer_minutes, candidate_threshold_minutes,
      effective_silence_minutes, candidate_deadline, would_alert, confidence, quality_state,
      fallback_path, sleep_interval_provenance, provenance_sha256, guardian_used_as_activity,
      evidence_cutoff, unclamped_candidate_threshold_minutes, candidate_floor_minutes,
      candidate_ceiling_minutes, candidate_cap_reason, deadline_basis,
      selected_source_sha256, subject_context_sha256, decision_provenance, decision_sha256
    ) VALUES (
      '47100000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000011',
      '2026-07-26 13:00:00+00', 'personal_context', 'adaptive_candidate_v1', 'ceiling-case',
      700, 0, 120, 500, '2026-07-26 13:05:00+00', true, 0.9, 'valid',
      ARRAY['personal_context']::text[], '[]'::jsonb, encode(extensions.digest('{}'::jsonb::text, 'sha256'), 'hex'), false,
      '2026-07-26 13:00:00+00', 700, 1, 120, 'ceiling', 'no_future_exclusion',
      repeat('6', 64), repeat('7', 64), '{}'::jsonb, repeat('8', 64)
    )
  $$,
  'a replayable learned ceiling result below its neutral p95 inserts successfully'
);
SELECT throws_ok(
  $$
    INSERT INTO public.alert_judgment_shadow_decisions (
      version_id, user_id, evaluated_at, basis, evaluator_version, context_key,
      neutral_threshold_minutes, sensitivity_buffer_minutes, candidate_threshold_minutes,
      effective_silence_minutes, candidate_deadline, would_alert, confidence, quality_state,
      fallback_path, sleep_interval_provenance, provenance_sha256, guardian_used_as_activity,
      evidence_cutoff, unclamped_candidate_threshold_minutes, candidate_floor_minutes,
      candidate_ceiling_minutes, candidate_cap_reason, deadline_basis,
      selected_source_sha256, subject_context_sha256, decision_provenance, decision_sha256
    ) VALUES (
      '47100000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000012',
      '2026-07-26 13:00:00+00', 'personal_context', 'adaptive_candidate_v1', 'ceiling-mismatch',
      700, 0, 999, 500, '2026-07-26 13:05:00+00', true, 0.9, 'valid',
      ARRAY['personal_context']::text[], '[]'::jsonb, encode(extensions.digest('{}'::jsonb::text, 'sha256'), 'hex'), false,
      '2026-07-26 13:00:00+00', 700, 1, 120, 'ceiling', 'no_future_exclusion',
      repeat('6', 64), repeat('7', 64), '{}'::jsonb, repeat('a', 64)
    )
  $$,
  NULL, NULL, 'a ceiling cap_reason with a value not equal to the ceiling fails'
);
SELECT throws_ok(
  $$
    INSERT INTO public.alert_judgment_shadow_decisions (
      version_id, user_id, evaluated_at, basis, evaluator_version, context_key,
      neutral_threshold_minutes, sensitivity_buffer_minutes, candidate_threshold_minutes,
      effective_silence_minutes, candidate_deadline, would_alert, confidence, quality_state,
      fallback_path, sleep_interval_provenance, provenance_sha256, guardian_used_as_activity,
      evidence_cutoff, unclamped_candidate_threshold_minutes, candidate_floor_minutes,
      candidate_ceiling_minutes, candidate_cap_reason, deadline_basis,
      selected_source_sha256, subject_context_sha256, decision_provenance, decision_sha256
    ) VALUES (
      '47100000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000013',
      '2026-07-26 13:00:00+00', 'personal_context', 'adaptive_candidate_v1', 'none-mismatch',
      90, 0, 135, 500, '2026-07-26 13:05:00+00', true, 0.9, 'valid',
      ARRAY['personal_context']::text[], '[]'::jsonb, encode(extensions.digest('{}'::jsonb::text, 'sha256'), 'hex'), false,
      '2026-07-26 13:00:00+00', 90, 1, 600, 'none', 'no_future_exclusion',
      repeat('6', 64), repeat('7', 64), '{}'::jsonb, repeat('c', 64)
    )
  $$,
  NULL, NULL, 'a none cap_reason whose final differs from unclamped fails'
);
SELECT throws_ok(
  $$
    INSERT INTO public.alert_judgment_shadow_decisions (
      version_id, user_id, evaluated_at, basis, evaluator_version, context_key,
      neutral_threshold_minutes, sensitivity_buffer_minutes, candidate_threshold_minutes,
      effective_silence_minutes, candidate_deadline, would_alert, confidence, quality_state,
      fallback_path, sleep_interval_provenance, provenance_sha256, guardian_used_as_activity,
      evidence_cutoff, unclamped_candidate_threshold_minutes, candidate_floor_minutes,
      candidate_ceiling_minutes, candidate_cap_reason, deadline_basis,
      selected_source_sha256, subject_context_sha256, decision_provenance, decision_sha256
    ) VALUES (
      '47100000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000014',
      '2026-07-26 13:00:00+00', 'personal_context', 'adaptive_candidate_v1', 'floor-mismatch',
      1, 0, 60, 500, '2026-07-26 13:05:00+00', true, 0.9, 'valid',
      ARRAY['personal_context']::text[], '[]'::jsonb, encode(extensions.digest('{}'::jsonb::text, 'sha256'), 'hex'), false,
      '2026-07-26 13:00:00+00', 60, 60, 600, 'floor', 'no_future_exclusion',
      repeat('6', 64), repeat('7', 64), '{}'::jsonb, repeat('e', 64)
    )
  $$,
  NULL, NULL, 'a floor cap_reason where unclamped is not below the floor fails'
);
SELECT throws_ok(
  $$
    INSERT INTO public.alert_judgment_shadow_decisions (
      version_id, user_id, evaluated_at, basis, evaluator_version, context_key,
      neutral_threshold_minutes, sensitivity_buffer_minutes, candidate_threshold_minutes,
      effective_silence_minutes, candidate_deadline, would_alert, confidence, quality_state,
      fallback_path, sleep_interval_provenance, provenance_sha256, guardian_used_as_activity,
      evidence_cutoff, unclamped_candidate_threshold_minutes, candidate_floor_minutes,
      candidate_ceiling_minutes, candidate_cap_reason, deadline_basis,
      selected_source_sha256, subject_context_sha256, decision_provenance, decision_sha256
    ) VALUES (
      '47100000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000018',
      '2026-07-26 13:00:00+00', 'personal_context', 'adaptive_candidate_v1', 'emergency-mismatch',
      90, 0, 90, 500, '2026-07-26 13:05:00+00', true, 0.9, 'valid',
      ARRAY['personal_context']::text[], '[]'::jsonb, encode(extensions.digest('{}'::jsonb::text, 'sha256'), 'hex'), false,
      '2026-07-26 13:00:00+00', 90, 1, 600, 'emergency_exempt', 'no_future_exclusion',
      repeat('6', 64), repeat('7', 64), '{}'::jsonb, repeat('1', 64)
    )
  $$,
  NULL, NULL, 'emergency_exempt with a non-emergency basis fails'
);
SELECT throws_ok(
  $$
    INSERT INTO public.alert_judgment_shadow_decisions (
      version_id, user_id, evaluated_at, basis, evaluator_version, context_key,
      neutral_threshold_minutes, sensitivity_buffer_minutes, candidate_threshold_minutes,
      effective_silence_minutes, candidate_deadline, would_alert, confidence, quality_state,
      fallback_path, sleep_interval_provenance, provenance_sha256, guardian_used_as_activity,
      evidence_cutoff, unclamped_candidate_threshold_minutes, candidate_floor_minutes,
      candidate_ceiling_minutes, candidate_cap_reason, deadline_basis,
      selected_source_sha256, subject_context_sha256, decision_provenance, decision_sha256
    ) VALUES (
      '47100000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000019',
      '2026-07-26 13:00:00+00', 'deterministic_emergency', 'adaptive_candidate_v1', 'bounds-invalid',
      90, 0, 90, 500, '2026-07-26 13:05:00+00', true, 0.9, 'low_support',
      ARRAY['deterministic_emergency']::text[], '[]'::jsonb, encode(extensions.digest('{}'::jsonb::text, 'sha256'), 'hex'), false,
      '2026-07-26 13:00:00+00', 90, 600, 1, 'emergency_exempt', 'no_future_exclusion',
      NULL, repeat('7', 64), '{}'::jsonb, repeat('3', 64)
    )
  $$,
  NULL, NULL, 'candidate_ceiling_minutes below candidate_floor_minutes fails'
);



------------------------------------------------------------------------------
-- Complete persistence, determinism, aggregate statuses, and source boundary.
------------------------------------------------------------------------------

SELECT results_eq(
  $$
    SELECT evaluated_at, evaluated_minute, evidence_cutoff
    FROM public.alert_judgment_shadow_decisions
    WHERE version_id = '47100000-0000-0000-0000-000000000001'
      AND user_id = '47000000-0000-0000-0000-000000000010'
      AND evaluated_minute = '2026-07-26 12:34:00+00'
  $$,
  $$
    VALUES (
      '2026-07-26 12:34:00+00'::timestamptz,
      '2026-07-26 12:34:00+00'::timestamptz,
      '2026-07-26 12:34:00+00'::timestamptz
    )
  $$,
  'recorder uses one canonical UTC minute for evaluation, identity, and evidence cutoff'
);

SELECT ok(
  (
    SELECT provenance_sha256 = encode(
      extensions.digest(decision_provenance::text, 'sha256'),
      'hex'
    )
    FROM public.alert_judgment_shadow_decisions
    WHERE version_id = '47100000-0000-0000-0000-000000000001'
      AND user_id = '47000000-0000-0000-0000-000000000010'
      AND evaluated_minute = '2026-07-26 12:34:00+00'
  ),
  'stored provenance_sha256 is the canonical decision_provenance hash'
);

SELECT ok(
  (
    WITH evaluated AS (
      SELECT private.resolve_alert_candidate(
        '47000000-0000-0000-0000-000000000010',
        '2026-07-26 12:34:00+00',
        '47100000-0000-0000-0000-000000000001'
      ) AS result
    )
    SELECT decision.decision_sha256 = encode(
      extensions.digest(jsonb_build_object(
        'version_id', decision.version_id,
        'user_id', decision.user_id,
        'evaluated_minute', '2026-07-26T12:34:00.000000Z',
        'evaluator_result', evaluated.result
      )::text, 'sha256'),
      'hex'
    )
    FROM public.alert_judgment_shadow_decisions AS decision
    CROSS JOIN evaluated
    WHERE decision.version_id = '47100000-0000-0000-0000-000000000001'
      AND decision.user_id = '47000000-0000-0000-0000-000000000010'
      AND decision.evaluated_minute = '2026-07-26 12:34:00+00'
  ),
  'decision_sha256 binds version, user, canonical minute, and complete evaluator JSON'
);

SELECT results_eq(
  $$
    SELECT basis, candidate_cap_reason, selected_source_sha256,
      guardian_used_as_activity
    FROM public.alert_judgment_shadow_decisions
    WHERE version_id = '47100000-0000-0000-0000-000000000001'
      AND user_id = '47000000-0000-0000-0000-000000000010'
      AND evaluated_minute = '2026-07-26 12:34:00+00'
  $$,
  $$
    VALUES (
      'deterministic_emergency'::text,
      'emergency_exempt'::text,
      NULL::text,
      false
    )
  $$,
  'emergency fallback stays explicit, source-free, and Guardian-independent'
);

CREATE TEMP TABLE shadow_recorder_original_sha AS
SELECT decision_sha256
FROM public.alert_judgment_shadow_decisions
WHERE version_id = '47100000-0000-0000-0000-000000000001'
  AND user_id = '47000000-0000-0000-0000-000000000010'
  AND evaluated_minute = '2026-07-26 12:34:00+00';
UPDATE public.alert_judgment_shadow_decisions
SET decision_sha256 = repeat('f', 64)
WHERE version_id = '47100000-0000-0000-0000-000000000001'
  AND user_id = '47000000-0000-0000-0000-000000000010'
  AND evaluated_minute = '2026-07-26 12:34:00+00';
SELECT throws_ok(
  $$ SELECT private.record_alert_judgment_shadow(
       '47100000-0000-0000-0000-000000000001',
       '2026-07-26 12:34:56+00'
     ) $$,
  NULL, NULL,
  'same-minute conflict raises instead of concealing a decision hash mismatch'
);
UPDATE public.alert_judgment_shadow_decisions AS decision
SET decision_sha256 = original.decision_sha256
FROM shadow_recorder_original_sha AS original
WHERE decision.version_id = '47100000-0000-0000-0000-000000000001'
  AND decision.user_id = '47000000-0000-0000-0000-000000000010'
  AND decision.evaluated_minute = '2026-07-26 12:34:00+00';

UPDATE public.group_members
SET monitored = false
WHERE user_id = '47000000-0000-0000-0000-000000000010';
SELECT results_eq(
  $$
    SELECT r ->> 'result_status', r ->> 'population_count',
      r ->> 'replayable_count', r ->> 'unreplayable_count'
    FROM (
      SELECT private.record_alert_judgment_shadow(
        '47100000-0000-0000-0000-000000000001',
        '2026-07-26 13:10:00+00'
      ) AS r
    ) call
  $$,
  $$ VALUES ('all_unreplayable', '5', '0', '5') $$,
  'nonempty population with no replayable result reports all_unreplayable'
);

UPDATE public.group_members
SET monitored =
  (user_id = '47000000-0000-0000-0000-000000000010')
WHERE group_id IN (
  '47000000-0000-0000-0000-000000000001',
  '47000000-0000-0000-0000-000000000002'
)
  AND status = 'active';
SELECT results_eq(
  $$
    SELECT r ->> 'result_status', r ->> 'population_count',
      r ->> 'replayable_count', r ->> 'unreplayable_count'
    FROM (
      SELECT private.record_alert_judgment_shadow(
        '47100000-0000-0000-0000-000000000001',
        '2026-07-26 13:20:00+00'
      ) AS r
    ) call
  $$,
  $$ VALUES ('complete', '1', '1', '0') $$,
  'one fully replayable population reports complete'
);

UPDATE public.group_members
SET monitored = false
WHERE group_id IN (
  '47000000-0000-0000-0000-000000000001',
  '47000000-0000-0000-0000-000000000002'
);
SELECT results_eq(
  $$
    SELECT r ->> 'result_status', r ->> 'population_count',
      r ->> 'evaluated_count', r ->> 'skipped_count'
    FROM (
      SELECT private.record_alert_judgment_shadow(
        '47100000-0000-0000-0000-000000000001',
        '2026-07-26 13:30:00+00'
      ) AS r
    ) call
  $$,
  $$ VALUES ('empty', '0', '0', '0') $$,
  'zero population reports empty with zero evaluation or skip counts'
);
UPDATE public.group_members
SET monitored = true
WHERE user_id IN (
  '47000000-0000-0000-0000-000000000010',
  '47000000-0000-0000-0000-000000000011',
  '47000000-0000-0000-0000-000000000012',
  '47000000-0000-0000-0000-000000000013',
  '47000000-0000-0000-0000-000000000014',
  '47000000-0000-0000-0000-000000000018',
  '47000000-0000-0000-0000-000000000019'
);

SELECT ok(
  pg_get_functiondef(
    'private.record_alert_judgment_shadow(uuid,timestamptz)'::regprocedure
  ) !~* 'execute[[:space:]]|format[[:space:]]*\(',
  'recorder contains no dynamic SQL'
);
SELECT ok(
  pg_get_functiondef(
    'private.record_alert_judgment_shadow(uuid,timestamptz)'::regprocedure
  ) ~* 'select[[:space:]]+distinct[[:space:]]+ds\.user_id[[:space:]]+from[[:space:]]+public\.device_state'
  AND pg_get_functiondef(
    'private.record_alert_judgment_shadow(uuid,timestamptz)'::regprocedure
  ) ~* 'gm\.status[[:space:]]*=[[:space:]]*''active'''
  AND pg_get_functiondef(
    'private.record_alert_judgment_shadow(uuid,timestamptz)'::regprocedure
  ) ~* 'gm\.monitored',
  'recorder population is exactly distinct device_state users with active monitored membership'
);

CREATE FUNCTION pg_temp.insert_shadow_cap_case(
  _suffix integer,
  _basis text,
  _final integer,
  _unclamped integer,
  _floor integer,
  _ceiling integer,
  _reason text,
  _provenance_sha text
)
RETURNS void
LANGUAGE sql
AS $cap$
  INSERT INTO public.alert_judgment_shadow_decisions (
    version_id, user_id, evaluated_at, basis, evaluator_version, context_key,
    neutral_threshold_minutes, sensitivity_buffer_minutes,
    candidate_threshold_minutes, effective_silence_minutes,
    candidate_deadline, would_alert, confidence, quality_state, fallback_path,
    sleep_interval_provenance, provenance_sha256, guardian_used_as_activity,
    evidence_cutoff, unclamped_candidate_threshold_minutes,
    candidate_floor_minutes, candidate_ceiling_minutes, candidate_cap_reason,
    deadline_basis, selected_source_sha256, subject_context_sha256,
    decision_provenance, decision_sha256
  )
  SELECT
    version_id,
    user_id,
    evaluated_at + make_interval(mins => _suffix),
    _basis,
    evaluator_version,
    context_key || '-' || _suffix::text,
    neutral_threshold_minutes,
    sensitivity_buffer_minutes,
    _final,
    effective_silence_minutes,
    candidate_deadline + make_interval(mins => _suffix),
    would_alert,
    confidence,
    quality_state,
    fallback_path,
    sleep_interval_provenance,
    _provenance_sha,
    guardian_used_as_activity,
    evidence_cutoff + make_interval(mins => _suffix),
    _unclamped,
    _floor,
    _ceiling,
    _reason,
    deadline_basis,
    selected_source_sha256,
    subject_context_sha256,
    decision_provenance,
    encode(extensions.digest(_suffix::text, 'sha256'), 'hex')
  FROM public.alert_judgment_shadow_decisions
  WHERE version_id = '47100000-0000-0000-0000-000000000001'
    AND user_id = '47000000-0000-0000-0000-000000000011'
    AND evaluated_minute = '2026-07-26 13:00:00+00'
$cap$;

SELECT throws_ok(
  $$ SELECT pg_temp.insert_shadow_cap_case(
       1, 'personal_context', -1, 90, 1, 600, 'none',
       encode(extensions.digest('{}'::jsonb::text, 'sha256'), 'hex')
     ) $$,
  NULL, NULL, 'negative final threshold fails'
);
SELECT throws_ok(
  $$ SELECT pg_temp.insert_shadow_cap_case(
       2, 'personal_context', 0, -1, 1, 600, 'floor',
       encode(extensions.digest('{}'::jsonb::text, 'sha256'), 'hex')
     ) $$,
  NULL, NULL, 'negative unclamped threshold fails'
);
SELECT throws_ok(
  $$ SELECT pg_temp.insert_shadow_cap_case(
       3, 'personal_context', 90, 90, -1, 600, 'none',
       encode(extensions.digest('{}'::jsonb::text, 'sha256'), 'hex')
     ) $$,
  NULL, NULL, 'negative candidate floor fails'
);
SELECT throws_ok(
  $$ SELECT pg_temp.insert_shadow_cap_case(
       4, 'personal_context', 90, 90, 1, -1, 'none',
       encode(extensions.digest('{}'::jsonb::text, 'sha256'), 'hex')
     ) $$,
  NULL, NULL, 'negative candidate ceiling fails'
);
SELECT throws_ok(
  $$ SELECT pg_temp.insert_shadow_cap_case(
       5, 'personal_context', 2, 0, 1, 600, 'floor',
       encode(extensions.digest('{}'::jsonb::text, 'sha256'), 'hex')
     ) $$,
  NULL, NULL, 'floor reason with final not equal to floor fails'
);
SELECT throws_ok(
  $$ SELECT pg_temp.insert_shadow_cap_case(
       6, 'personal_context', 120, 120, 1, 120, 'ceiling',
       encode(extensions.digest('{}'::jsonb::text, 'sha256'), 'hex')
     ) $$,
  NULL, NULL, 'ceiling reason without unclamped above ceiling fails'
);
SELECT throws_ok(
  $$ SELECT pg_temp.insert_shadow_cap_case(
       7, 'deterministic_emergency', 91, 90, 1, 600, 'emergency_exempt',
       encode(extensions.digest('{}'::jsonb::text, 'sha256'), 'hex')
     ) $$,
  NULL, NULL, 'emergency exemption with final not equal to unclamped fails'
);
SELECT throws_ok(
  $$ SELECT pg_temp.insert_shadow_cap_case(
       8, 'personal_context', 700, 700, 1, 600, 'none',
       encode(extensions.digest('{}'::jsonb::text, 'sha256'), 'hex')
     ) $$,
  NULL, NULL, 'none reason outside candidate bounds fails'
);
SELECT throws_ok(
  $$ SELECT pg_temp.insert_shadow_cap_case(
       9, 'personal_context', 120, 700, 1, 120, 'ceiling', repeat('0', 64)
     ) $$,
  NULL, NULL, 'noncanonical provenance hash fails'
);



------------------------------------------------------------------------------
-- Evaluator-contract corruption aborts atomically (test-transaction mocks).
------------------------------------------------------------------------------

CREATE TEMP TABLE shadow_recorder_count_before_contract_mock AS
SELECT count(*)::integer AS row_count
FROM public.alert_judgment_shadow_decisions;

CREATE OR REPLACE FUNCTION private.resolve_alert_candidate(
  _user_id uuid,
  _evaluated_at timestamptz,
  _version_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
SET TimeZone = 'UTC'
AS $mock$
  SELECT jsonb_build_object(
    'version_id', _version_id,
    'evaluator_version', 'adaptive_candidate_v1',
    'evaluated_at', to_char(
      _evaluated_at AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
    ),
    'evidence_cutoff', to_char(
      _evaluated_at AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
    ),
    'replayable', false,
    'unreplayable_reason', 'config_hash_mismatch',
    'basis', NULL,
    'context_key', NULL,
    'neutral_threshold_minutes', NULL,
    'sensitivity_buffer_minutes', NULL,
    'unclamped_candidate_threshold_minutes', NULL,
    'candidate_floor_minutes', NULL,
    'candidate_ceiling_minutes', NULL,
    'candidate_cap_reason', NULL,
    'candidate_threshold_minutes', NULL,
    'effective_silence_minutes', NULL,
    'candidate_deadline', NULL,
    'deadline_basis', NULL,
    'would_alert', NULL,
    'confidence', NULL,
    'quality_state', 'coverage_invalid',
    'fallback_path', '[]'::jsonb,
    'sleep_interval_provenance', '[]'::jsonb,
    'selected_source_sha256', NULL,
    'subject_context_sha256', NULL,
    'decision_provenance', '{}'::jsonb,
    'provenance_sha256',
      encode(extensions.digest('{}'::jsonb::text, 'sha256'), 'hex'),
    'guardian_used_as_activity', false
  )
$mock$;

SELECT throws_ok(
  $$ SELECT private.record_alert_judgment_shadow(
       '47100000-0000-0000-0000-000000000001',
       '2026-07-26 14:00:00+00'
     ) $$,
  NULL, NULL,
  'an evaluator run-level reason aborts the complete recorder statement'
);

CREATE OR REPLACE FUNCTION private.resolve_alert_candidate(
  _user_id uuid,
  _evaluated_at timestamptz,
  _version_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
SET TimeZone = 'UTC'
AS $mock$
  SELECT '{}'::jsonb
$mock$;

SELECT throws_ok(
  $$ SELECT private.record_alert_judgment_shadow(
       '47100000-0000-0000-0000-000000000001',
       '2026-07-26 14:01:00+00'
     ) $$,
  NULL, NULL,
  'a missing evaluator result key aborts the complete recorder statement'
);

SELECT is(
  (SELECT count(*)::integer FROM public.alert_judgment_shadow_decisions),
  (SELECT row_count FROM shadow_recorder_count_before_contract_mock),
  'run-level and malformed evaluator results retain zero partial decision rows'
);

SELECT * FROM finish();
ROLLBACK;
