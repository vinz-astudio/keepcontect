BEGIN;
SELECT plan(39);

INSERT INTO auth.users (id, email, aud, role) VALUES
  ('42000000-0000-0000-0000-000000000001', 'sleep-owner@example.invalid', 'authenticated', 'authenticated'),
  ('42000000-0000-0000-0000-000000000002', 'sleep-missing@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

WITH config AS (
  SELECT '{"sessionization":{"gap_minutes":30,"per_user_day_gap_cap":8},"context":{"definition_version":"sleep-candidate-v1"},"personal":{"min_samples":3,"min_support_dates":2,"min_span_days":2,"max_age_days":30},"cohort":{"min_contributors":3,"min_support_dates":2,"max_age_days":30,"algorithm":"trimmed_mean","trim_fraction":0.1},"sensitivity_buffers_minutes":{"high":0,"balanced":45,"low":90},"candidate_bounds":{"floor_minutes":1,"ceiling_minutes":600},"sleep_compensation":{"max_start_delay_minutes":45,"max_wake_advance_minutes":45,"max_wake_delay_minutes":90,"max_update_minutes_per_day":30,"min_positive_nights":2,"lookback_nights":3,"min_late_events_per_night":2,"timezone_tolerance_minutes":30}}'::jsonb AS value
)
INSERT INTO public.alert_model_versions (id, name, status, config, config_sha256, evidence_version)
SELECT '42000000-0000-0000-0000-000000000010', 'sleep-candidate-test', 'replay', value,
  encode(extensions.digest(value::text, 'sha256'), 'hex'), 'canonical-v2'
FROM config;

INSERT INTO public.alert_sleep_night_contexts (
  version_id, user_id, anchor_date, timezone, sleep_start_local, sleep_end_local,
  anchor_starts_at, anchor_ends_at, utc_offset_minutes, coverage_state, captured_at,
  finalized_at, evidence_version, provenance_sha256
) VALUES
  ('42000000-0000-0000-0000-000000000010', '42000000-0000-0000-0000-000000000001', '2026-03-07', 'America/New_York', '23:00', '07:00', '2026-03-08 04:00+00', '2026-03-08 11:00+00', -300, 'valid', '2026-03-08 04:00+00', '2026-03-08 11:00+00', 'canonical-v2', repeat('a', 64)),
  ('42000000-0000-0000-0000-000000000010', '42000000-0000-0000-0000-000000000001', '2026-03-08', 'America/New_York', '23:00', '07:00', '2026-03-09 03:00+00', '2026-03-09 11:00+00', -240, 'valid', '2026-03-09 03:00+00', '2026-03-09 11:00+00', 'canonical-v2', repeat('b', 64)),
  ('42000000-0000-0000-0000-000000000010', '42000000-0000-0000-0000-000000000001', '2026-11-01', 'America/New_York', '23:00', '07:00', '2026-11-02 04:00+00', '2026-11-02 12:00+00', -300, 'unknown', '2026-11-02 04:00+00', NULL, 'canonical-v2', repeat('c', 64)),
  ('42000000-0000-0000-0000-000000000010', '42000000-0000-0000-0000-000000000001', '2026-04-01', 'UTC', '23:00', '07:00', '2026-04-01 23:00+00', '2026-04-02 07:00+00', 0, 'valid', '2026-04-01 23:00+00', '2026-04-02 07:00+00', 'canonical-v2', repeat('d', 64)),
  ('42000000-0000-0000-0000-000000000010', '42000000-0000-0000-0000-000000000001', '2026-04-02', 'UTC', '23:00', '07:00', '2026-04-02 23:00+00', '2026-04-03 07:00+00', 0, 'valid', '2026-04-02 23:00+00', '2026-04-03 07:00+00', 'canonical-v2', repeat('e', 64)),
  ('42000000-0000-0000-0000-000000000010', '42000000-0000-0000-0000-000000000001', '2026-04-03', 'UTC', '23:00', '07:00', '2026-04-03 23:00+00', '2026-04-04 07:00+00', 0, 'valid', '2026-04-03 23:00+00', '2026-04-04 07:00+00', 'canonical-v2', repeat('f', 64)),
  ('42000000-0000-0000-0000-000000000010', '42000000-0000-0000-0000-000000000001', '2026-04-10', 'UTC', '14:00', '16:00', '2026-04-10 14:00+00', '2026-04-10 16:00+00', 0, 'outage', '2026-04-10 14:00+00', '2026-04-10 16:00+00', 'canonical-v2', repeat('0', 64));

INSERT INTO public.behavior_pings (user_id, kind, at, received_at, ingest_version) VALUES
  ('42000000-0000-0000-0000-000000000001', 'app', '2026-03-08 04:40+00', '2026-03-08 04:40+00', 2),
  ('42000000-0000-0000-0000-000000000001', 'app', '2026-03-08 04:50+00', '2026-03-08 04:50+00', 2),
  ('42000000-0000-0000-0000-000000000001', 'app', '2026-03-08 10:20+00', '2026-03-08 10:20+00', 2),
  ('42000000-0000-0000-0000-000000000001', 'app', '2026-03-09 03:40+00', '2026-03-09 03:40+00', 2),
  ('42000000-0000-0000-0000-000000000001', 'app', '2026-03-09 03:50+00', '2026-03-09 03:50+00', 2),
  ('42000000-0000-0000-0000-000000000001', 'app', '2026-04-01 23:40+00', '2026-04-01 23:40+00', 2),
  ('42000000-0000-0000-0000-000000000001', 'app', '2026-04-01 23:50+00', '2026-04-01 23:50+00', 2),
  ('42000000-0000-0000-0000-000000000001', 'app', '2026-04-02 23:30+00', '2026-04-02 23:30+00', 2),
  ('42000000-0000-0000-0000-000000000001', 'app', '2026-04-02 23:40+00', '2026-04-02 23:40+00', 2),
  ('42000000-0000-0000-0000-000000000001', 'app', '2026-11-02 04:40+00', '2026-11-02 04:40+00', 2),
  ('42000000-0000-0000-0000-000000000001', 'app', '2026-11-02 11:20+00', '2026-11-02 11:20+00', 1),
  ('42000000-0000-0000-0000-000000000001', 'app', '2026-11-02 11:30+00', '2026-11-02 11:40+00', 2);

INSERT INTO public.alerts (id, user_id, cause, stage, status, opened_at, stage_entered_at, resolved_at)
VALUES ('42000000-0000-0000-0000-000000000020', '42000000-0000-0000-0000-000000000001', 'silence', 'self', 'resolved', '2026-03-08 06:00+00', '2026-03-08 06:00+00', '2026-03-08 06:01+00');
INSERT INTO public.alert_events (alert_id, actor_id, kind, at)
VALUES ('42000000-0000-0000-0000-000000000020', '42000000-0000-0000-0000-000000000002', 'confirmed_safe', '2026-03-08 06:01+00');

CREATE TEMP TABLE live_snapshot AS
SELECT
  (SELECT coalesce(md5(string_agg(to_jsonb(a)::text, ',' ORDER BY a.id)), '') FROM public.alerts a) AS alerts_hash,
  (SELECT coalesce(md5(string_agg(to_jsonb(e)::text, ',' ORDER BY e.id)), '') FROM public.alert_events e) AS events_hash,
  (SELECT coalesce(md5(string_agg(to_jsonb(n)::text, ',' ORDER BY n.id)), '') FROM public.notifications n) AS notifications_hash;

SELECT has_table('public', 'alert_sleep_night_contexts', 'persisted nightly contexts are recorded');
SELECT col_is_pk('public', 'alert_sleep_night_contexts', ARRAY['version_id', 'user_id', 'anchor_date'], 'night context is version/user/date keyed');
SELECT has_function('private', 'candidate_sleep_intervals', ARRAY['uuid', 'timestamp with time zone', 'timestamp with time zone', 'uuid'], 'candidate interval function exists');
SELECT function_privs_are('private', 'candidate_sleep_intervals', ARRAY['uuid', 'timestamp with time zone', 'timestamp with time zone', 'uuid'], 'anon', ARRAY[]::text[]);
SELECT function_privs_are('private', 'candidate_sleep_intervals', ARRAY['uuid', 'timestamp with time zone', 'timestamp with time zone', 'uuid'], 'authenticated', ARRAY[]::text[]);
SELECT function_privs_are('private', 'candidate_sleep_intervals', ARRAY['uuid', 'timestamp with time zone', 'timestamp with time zone', 'uuid'], 'service_role', ARRAY[]::text[]);
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl WHERE p.oid = 'private.candidate_sleep_intervals(uuid,timestamptz,timestamptz,uuid)'::regprocedure AND acl.grantee = 0), 'PUBLIC cannot execute the candidate function');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.alert_sleep_night_contexts'::regclass), 'night contexts have RLS');
SELECT is((SELECT count(*)::integer FROM pg_policy WHERE polrelid = 'public.alert_sleep_night_contexts'::regclass), 0, 'night contexts have no policy');

SELECT results_eq(
  $$ SELECT starts_at, ends_at, basis FROM private.candidate_sleep_intervals('42000000-0000-0000-0000-000000000001', '2026-03-08 00:00+00', '2026-03-10 00:00+00', '42000000-0000-0000-0000-000000000010') ORDER BY starts_at $$,
  $$ VALUES ('2026-03-08 04:45+00'::timestamptz, '2026-03-08 10:20+00'::timestamptz, 'positive_evidence_adjusted'::text), ('2026-03-09 03:45+00'::timestamptz, '2026-03-09 11:00+00'::timestamptz, 'positive_evidence_adjusted'::text) $$,
  'direct activity narrows each full anchor and prior late evidence extends only the later valid night');
SELECT results_eq(
  $$ SELECT starts_at, ends_at, basis FROM private.candidate_sleep_intervals('42000000-0000-0000-0000-000000000001', '2026-11-02 00:00+00', '2026-11-03 00:00+00', '42000000-0000-0000-0000-000000000010') $$,
  $$ VALUES ('2026-11-02 04:40+00'::timestamptz, '2026-11-02 12:00+00'::timestamptz, 'positive_evidence_adjusted'::text) $$,
  'unknown coverage admits direct narrowing but never a wake extension');
SELECT is((SELECT confidence FROM private.candidate_sleep_intervals('42000000-0000-0000-0000-000000000001', '2026-04-10 00:00+00', '2026-04-11 00:00+00', '42000000-0000-0000-0000-000000000010')), 0::double precision, 'absence retains the anchor with zero candidate confidence');
SELECT is_empty($$ SELECT * FROM private.candidate_sleep_intervals('42000000-0000-0000-0000-000000000002', '2026-03-08 00:00+00', '2026-03-10 00:00+00', '42000000-0000-0000-0000-000000000010') $$, 'missing historical context is never projected from current settings');
SELECT is_empty($$ SELECT * FROM private.candidate_sleep_intervals('42000000-0000-0000-0000-000000000001', '2026-03-08 04:00+00', '2026-03-08 04:00+00', '42000000-0000-0000-0000-000000000010') $$, 'empty query range returns no interval');
SELECT results_eq(
  $$ SELECT starts_at, ends_at, basis FROM private.candidate_sleep_intervals('42000000-0000-0000-0000-000000000001', '2026-04-01 00:00+00', '2026-04-05 00:00+00', '42000000-0000-0000-0000-000000000010') ORDER BY starts_at $$,
  $$ VALUES ('2026-04-01 23:45+00'::timestamptz, '2026-04-02 07:00+00'::timestamptz, 'positive_evidence_adjusted'::text), ('2026-04-02 23:40+00'::timestamptz, '2026-04-03 07:00+00'::timestamptz, 'positive_evidence_adjusted'::text), ('2026-04-03 23:00+00'::timestamptz, '2026-04-04 07:30+00'::timestamptz, 'positive_evidence_adjusted'::text) $$,
  'two qualified prior nights affect only the next valid night and one-step rate cap limits the prospective wake delay');
SELECT results_eq(
  $$ SELECT starts_at, ends_at, basis FROM private.candidate_sleep_intervals('42000000-0000-0000-0000-000000000001', '2026-04-10 00:00+00', '2026-04-11 00:00+00', '42000000-0000-0000-0000-000000000010') $$,
  $$ VALUES ('2026-04-10 14:00+00'::timestamptz, '2026-04-10 16:00+00'::timestamptz, 'configured_anchor'::text) $$,
  'same-day outage context remains its persisted anchor when no positive evidence exists');
SELECT ok(NOT EXISTS (
  SELECT 1 FROM pg_constraint fk
  JOIN pg_class parent ON parent.oid = fk.confrelid
  JOIN pg_namespace parent_ns ON parent_ns.oid = parent.relnamespace
  WHERE fk.conrelid = 'public.alert_sleep_night_contexts'::regclass
    AND parent_ns.nspname = 'public' AND parent.relname IN ('alerts', 'alert_events', 'notifications')
), 'context has no foreign key to a live alert table');
SELECT results_eq(
  $$ WITH roles(role_name) AS (VALUES ('anon'::text), ('authenticated'::text), ('service_role'::text)), actions(privilege_name) AS (VALUES ('DELETE'::text), ('INSERT'::text), ('MAINTAIN'::text), ('REFERENCES'::text), ('SELECT'::text), ('TRIGGER'::text), ('TRUNCATE'::text), ('UPDATE'::text)) SELECT role_name, string_agg(privilege_name, ',' ORDER BY privilege_name) FILTER (WHERE has_table_privilege(role_name, 'public.alert_sleep_night_contexts', privilege_name)) FROM roles CROSS JOIN actions GROUP BY role_name ORDER BY role_name $$,
  $$ VALUES ('anon'::text, NULL::text), ('authenticated'::text, NULL::text), ('service_role'::text, NULL::text) $$,
  'night contexts have no effective table action for Data API roles');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl WHERE c.oid = 'public.alert_sleep_night_contexts'::regclass AND acl.grantee = 0), 'night contexts have no PUBLIC table privilege');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.column_privileges WHERE table_schema = 'public' AND table_name = 'alert_sleep_night_contexts' AND grantee IN ('PUBLIC', 'anon', 'authenticated', 'service_role')), 'night contexts have no Data API column privilege');
SELECT ok((SELECT p.prosecdef AND p.provolatile = 's' FROM pg_proc p WHERE p.oid = 'private.candidate_sleep_intervals(uuid,timestamptz,timestamptz,uuid)'::regprocedure), 'candidate function is stable security definer');
SELECT is((SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid = 'private.candidate_sleep_intervals(uuid,timestamptz,timestamptz,uuid)'::regprocedure), 'search_path=""', 'candidate function pins an empty search path');
SELECT is((SELECT r.rolname FROM pg_proc p JOIN pg_roles r ON r.oid = p.proowner WHERE p.oid = 'private.candidate_sleep_intervals(uuid,timestamptz,timestamptz,uuid)'::regprocedure), current_user, 'candidate function remains owner-only');
SELECT throws_ok($$ SET LOCAL ROLE anon; SELECT * FROM public.alert_sleep_night_contexts $$, '42501'::char(5), NULL, 'anonymous callers cannot read nightly contexts');
INSERT INTO public.alert_sleep_night_contexts (version_id, user_id, anchor_date, timezone, sleep_start_local, sleep_end_local, anchor_starts_at, anchor_ends_at, utc_offset_minutes, coverage_state, captured_at, finalized_at, evidence_version, provenance_sha256)
VALUES ('42000000-0000-0000-0000-000000000010', '42000000-0000-0000-0000-000000000001', '2026-05-01', 'Not/AZone', '23:00', '07:00', '2026-05-01 23:00+00', '2026-05-02 07:00+00', 0, 'valid', '2026-05-01 23:00+00', '2026-05-02 07:00+00', 'canonical-v2', repeat('1', 64));
SELECT is_empty($$ SELECT * FROM private.candidate_sleep_intervals('42000000-0000-0000-0000-000000000001', '2026-05-01 00:00+00', '2026-05-03 00:00+00', '42000000-0000-0000-0000-000000000010') $$, 'invalid persisted zone produces no inferred interval');
SELECT throws_ok($$ INSERT INTO public.alert_sleep_night_contexts (version_id, user_id, anchor_date, timezone, sleep_start_local, sleep_end_local, anchor_starts_at, anchor_ends_at, utc_offset_minutes, coverage_state, captured_at, finalized_at, evidence_version, provenance_sha256) VALUES ('42000000-0000-0000-0000-000000000010', '42000000-0000-0000-0000-000000000001', '2026-05-02', 'UTC', '23:00', '23:00', '2026-05-02 23:00+00', '2026-05-03 23:00+00', 0, 'valid', '2026-05-02 23:00+00', '2026-05-03 23:00+00', 'canonical-v2', repeat('2', 64)) $$, '23514'::char(5), NULL, 'equal local endpoints are rejected rather than widened');
SELECT is((SELECT extract(epoch FROM (anchor_ends_at - anchor_starts_at))::integer / 3600 FROM public.alert_sleep_night_contexts WHERE anchor_date = '2026-03-07'), 7, 'spring DST anchor retains its persisted seven-hour UTC interval');
SELECT is((SELECT extract(epoch FROM (anchor_ends_at - anchor_starts_at))::integer / 3600 FROM public.alert_sleep_night_contexts WHERE anchor_date = '2026-11-01'), 8, 'fall DST anchor retains its persisted eight-hour UTC interval');
UPDATE public.alert_model_versions SET status = 'draft' WHERE id = '42000000-0000-0000-0000-000000000010';
SELECT is_empty($$ SELECT * FROM private.candidate_sleep_intervals('42000000-0000-0000-0000-000000000001', '2026-04-01 00:00+00', '2026-04-05 00:00+00', '42000000-0000-0000-0000-000000000010') $$, 'draft version has no candidate interval');
UPDATE public.alert_model_versions SET status = 'retired' WHERE id = '42000000-0000-0000-0000-000000000010';
SELECT is_empty($$ SELECT * FROM private.candidate_sleep_intervals('42000000-0000-0000-0000-000000000001', '2026-04-01 00:00+00', '2026-04-05 00:00+00', '42000000-0000-0000-0000-000000000010') $$, 'retired version has no candidate interval');
UPDATE public.alert_model_versions SET status = 'replay', config_sha256 = repeat('9', 64) WHERE id = '42000000-0000-0000-0000-000000000010';
SELECT is_empty($$ SELECT * FROM private.candidate_sleep_intervals('42000000-0000-0000-0000-000000000001', '2026-04-01 00:00+00', '2026-04-05 00:00+00', '42000000-0000-0000-0000-000000000010') $$, 'configuration hash mismatch has no candidate interval');
UPDATE public.alert_model_versions SET config_sha256 = encode(extensions.digest(config::text, 'sha256'), 'hex') WHERE id = '42000000-0000-0000-0000-000000000010';
SELECT is_empty($$ SELECT * FROM private.candidate_sleep_intervals('42000000-0000-0000-0000-000000000001', '2026-04-01 00:00+00', '2026-04-05 00:00+00', '42000000-0000-0000-0000-000000000099') $$, 'missing model version produces no inferred interval');

SELECT throws_ok($$ INSERT INTO public.alert_model_versions (name, status, config, config_sha256, evidence_version) VALUES ('missing-sleep-fields', 'draft', '{"sessionization":{"gap_minutes":1,"per_user_day_gap_cap":1},"context":{"definition_version":"x"},"personal":{"min_samples":1,"min_support_dates":1,"min_span_days":1,"max_age_days":1},"cohort":{"min_contributors":1,"min_support_dates":1,"max_age_days":1,"algorithm":"trimmed_mean","trim_fraction":0},"sensitivity_buffers_minutes":{"high":0,"balanced":45,"low":90},"candidate_bounds":{"floor_minutes":1,"ceiling_minutes":2},"sleep_compensation":{"max_start_delay_minutes":0,"max_wake_advance_minutes":0,"max_wake_delay_minutes":0,"max_update_minutes_per_day":0,"min_positive_nights":1,"timezone_tolerance_minutes":0}}'::jsonb, repeat('d',64), 'canonical-v2') $$, '23514'::char(5), NULL, 'model config requires late evidence fields');
SELECT throws_ok($$ INSERT INTO public.alert_model_versions (name, status, config, config_sha256, evidence_version) VALUES ('invalid-sleep-relationship', 'draft', '{"sessionization":{"gap_minutes":1,"per_user_day_gap_cap":1},"context":{"definition_version":"x"},"personal":{"min_samples":1,"min_support_dates":1,"min_span_days":1,"max_age_days":1},"cohort":{"min_contributors":1,"min_support_dates":1,"max_age_days":1,"algorithm":"trimmed_mean","trim_fraction":0},"sensitivity_buffers_minutes":{"high":0,"balanced":45,"low":90},"candidate_bounds":{"floor_minutes":1,"ceiling_minutes":2},"sleep_compensation":{"max_start_delay_minutes":0,"max_wake_advance_minutes":0,"max_wake_delay_minutes":0,"max_update_minutes_per_day":0,"min_positive_nights":2,"lookback_nights":1,"min_late_events_per_night":1,"timezone_tolerance_minutes":0}}'::jsonb, repeat('e',64), 'canonical-v2') $$, '23514'::char(5), NULL, 'positive-night support cannot exceed lookback');
SELECT throws_ok($$ SET LOCAL ROLE authenticated; SELECT * FROM private.candidate_sleep_intervals('42000000-0000-0000-0000-000000000001', '2026-03-08 00:00+00', '2026-03-09 00:00+00', '42000000-0000-0000-0000-000000000010') $$, '42501'::char(5), NULL, 'authenticated Data API caller cannot execute candidate function');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.alert_sleep_night_contexts'::regclass AND NOT t.tgisinternal), 'night context has no trigger');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'alert_sleep_night_contexts'), 'night context is not realtime');
SELECT ok(NOT EXISTS (SELECT 1 FROM cron.job WHERE lower(command) LIKE '%sleep_candidate%' OR lower(jobname) LIKE '%sleep_candidate%'), 'sleep candidate schedules no cron');
SELECT results_eq($$ SELECT * FROM live_snapshot EXCEPT SELECT (SELECT coalesce(md5(string_agg(to_jsonb(a)::text, ',' ORDER BY a.id)), '') FROM public.alerts a), (SELECT coalesce(md5(string_agg(to_jsonb(e)::text, ',' ORDER BY e.id)), '') FROM public.alert_events e), (SELECT coalesce(md5(string_agg(to_jsonb(n)::text, ',' ORDER BY n.id)), '') FROM public.notifications n) $$, $$ SELECT * FROM live_snapshot WHERE false $$, 'candidate reads preserve full live alert-path rows, including guardian confirmation');
SELECT * FROM finish();
ROLLBACK;
