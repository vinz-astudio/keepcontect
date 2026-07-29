-- ADR-0028 production-shadow coverage lease contract.
-- Phase 2 enables the bounded runtime, while its explicit kill switch remains
-- source-identified, non-notifying, and fail-closed.

BEGIN;
SELECT plan(38);

INSERT INTO auth.users (id, email, aud, role)
VALUES (
  '48000000-0000-0000-0000-000000000001',
  'coverage-contract@example.invalid',
  'authenticated',
  'authenticated'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.user_settings (user_id, timezone)
VALUES ('48000000-0000-0000-0000-000000000001', 'UTC')
ON CONFLICT (user_id) DO UPDATE SET timezone = EXCLUDED.timezone;

INSERT INTO public.clients (
  user_id, client_id, platform, app_version, first_seen_at, last_seen_at
) VALUES
  (
    '48000000-0000-0000-0000-000000000001',
    'tauri-a', 'tauri', '0.5.20', clock_timestamp(), clock_timestamp()
  ),
  (
    '48000000-0000-0000-0000-000000000001',
    'android-a', 'android-apk', '0.5.20', clock_timestamp(), clock_timestamp()
  ),
  (
    '48000000-0000-0000-0000-000000000001',
    'android-legacy', 'android', '0.5.20', clock_timestamp(), clock_timestamp()
  )
ON CONFLICT (user_id, client_id) DO UPDATE
SET platform = EXCLUDED.platform, app_version = EXCLUDED.app_version;

CREATE TEMP TABLE coverage_contract_config AS
SELECT '{
  "sessionization":{"gap_minutes":30,"per_user_day_gap_cap":8,"training_horizon_days":30,"intervention_window_minutes":30},
  "context":{"definition_version":"coverage-contract-v1","day_partition":"all_days","hour_bucket_minutes":60},
  "personal":{"min_samples":3,"min_support_dates":2,"min_span_days":2,"max_age_days":30,"min_confidence":0.7,"confidence_formula_version":"support_ratio_v1"},
  "cohort":{"min_contributors":3,"min_support_dates":2,"min_span_days":2,"max_age_days":30,"min_confidence":0.5,"contribution_floor_minutes":1,"contribution_ceiling_minutes":600,"confidence_formula_version":"cohort_support_min_v1","algorithm":"trimmed_mean","trim_fraction":0.1},
  "sensitivity_buffers_minutes":{"high":0,"balanced":45,"low":90},
  "candidate_bounds":{"floor_minutes":1,"ceiling_minutes":600},
  "sleep_compensation":{"max_start_delay_minutes":60,"max_wake_advance_minutes":60,"max_wake_delay_minutes":60,"max_update_minutes_per_day":30,"min_positive_nights":2,"lookback_nights":3,"min_late_events_per_night":1,"timezone_tolerance_minutes":30},
  "evaluator":{"contract_version":"adaptive_candidate_v1"},
  "emergency":{"contract_version":"adr0022_v1","neutral_minutes":90,"expected_live_definition_sha256":"1907d59473d274d46a0e8e0b9ce8027037b4494b0dddf073cb46abf67db92e21"}
}'::jsonb AS config;

INSERT INTO public.alert_model_versions (
  id, name, status, config, config_sha256, evidence_version, shadow_enabled_at
)
SELECT
  '48100000-0000-0000-0000-000000000001',
  'coverage-contract-shadow',
  'shadow',
  config,
  encode(extensions.digest(config::text, 'sha256'), 'hex'),
  'coverage-contract-v1',
  '2026-07-01 00:00:00+00'
FROM coverage_contract_config;

-- 1..3: exact callable surface.
SELECT has_function(
  'public', 'record_alert_shadow_coverage_lease',
  ARRAY['text','text','text','text','text','timestamp with time zone','uuid']
);
SELECT has_function(
  'public', 'record_alert_shadow_coverage_lease_for_user',
  ARRAY['uuid','text','text','text','text','text','timestamp with time zone','uuid']
);
SELECT has_function(
  'private', 'finalize_alert_shadow_coverage',
  ARRAY['uuid','timestamp with time zone','integer']
);

-- 4: accepted Phase-2 singleton is enabled but remains bounded.
SELECT results_eq(
  $$
    SELECT enabled, accept_coverage_leases, max_population,
      detail_retention_days, cycle_timeout_seconds,
      max_consecutive_failures, consecutive_failures
    FROM private.adaptive_alert_shadow_runtime_config
    WHERE singleton
  $$,
  $$ VALUES (true, true, 10000, 35, 120, 3, 0) $$,
  'Phase-2 runtime is enabled and bounded'
);

UPDATE private.adaptive_alert_shadow_runtime_config
SET accept_coverage_leases = false;

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"48000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

-- 5: no lease can enter after the explicit kill switch is closed.
SELECT is(
  public.record_alert_shadow_coverage_lease(
    'tauri-a','tauri','tauri-idle-v1','operational',
    repeat('a',64),clock_timestamp(),gen_random_uuid()
  ),
  'disabled',
  'lease acceptance fails closed when the kill switch is off'
);
RESET ROLE;

UPDATE private.adaptive_alert_shadow_runtime_config
SET version_id = '48100000-0000-0000-0000-000000000001',
    enabled = true,
    accept_coverage_leases = true;

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"48000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

CREATE TEMP TABLE accepted_lease_event(event_id uuid);
INSERT INTO accepted_lease_event VALUES ('48200000-0000-0000-0000-000000000001');

-- 6: registered native Tauri source is accepted.
SELECT is(
  public.record_alert_shadow_coverage_lease(
    'tauri-a','tauri','tauri-idle-v1','operational',
    repeat('a',64),clock_timestamp(),
    (SELECT event_id FROM accepted_lease_event)
  ),
  'inserted',
  'registered Tauri native lease is inserted'
);

-- 7: duplicate event is idempotently accepted.
SELECT is(
  public.record_alert_shadow_coverage_lease(
    'tauri-a','tauri','tauri-idle-v1','operational',
    repeat('a',64),clock_timestamp(),
    (SELECT event_id FROM accepted_lease_event)
  ),
  'duplicate',
  'duplicate event ID returns the stable duplicate status'
);

-- 8..12: stable source/contract rejection codes.
SELECT is(
  public.record_alert_shadow_coverage_lease(
    'missing-client','tauri','tauri-idle-v1','operational',
    repeat('a',64),clock_timestamp(),gen_random_uuid()
  ),
  'unregistered_client',
  'unregistered client returns the stable rejection status'
);
SELECT is(
  public.record_alert_shadow_coverage_lease(
    'tauri-a','browser','tauri-idle-v1','operational',
    repeat('a',64),clock_timestamp(),gen_random_uuid()
  ),
  'unsupported',
  'browser cannot claim continuous coverage'
);
SELECT is(
  public.record_alert_shadow_coverage_lease(
    'tauri-a','manual','tauri-idle-v1','operational',
    repeat('a',64),clock_timestamp(),gen_random_uuid()
  ),
  'unsupported',
  'manual activity cannot claim continuous coverage'
);
SELECT is(
  public.record_alert_shadow_coverage_lease(
    'tauri-a','guardian','tauri-idle-v1','operational',
    repeat('a',64),clock_timestamp(),gen_random_uuid()
  ),
  'unsupported',
  'Guardian activity cannot claim continuous coverage'
);
SELECT is(
  public.record_alert_shadow_coverage_lease(
    'tauri-a','tauri','android-passive-v1','operational',
    repeat('a',64),clock_timestamp(),gen_random_uuid()
  ),
  'unsupported',
  'channel and collector contract must match'
);

-- 13: device time cannot extend server-authoritative coverage.
SELECT is(
  public.record_alert_shadow_coverage_lease(
    'tauri-a','tauri','tauri-idle-v1','operational',
    repeat('a',64),clock_timestamp() - interval '6 minutes',gen_random_uuid()
  ),
  'invalid',
  'observed time outside five minutes returns invalid'
);
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"48000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
SELECT is(
  public.record_alert_shadow_coverage_lease(
    'tauri-a','android-apk','android-passive-v1','operational',
    repeat('a',64),clock_timestamp(),gen_random_uuid()
  ),
  'capability_mismatch',
  'registered client platform mismatch returns capability_mismatch'
); -- 14
SELECT is(
  public.record_alert_shadow_coverage_lease(
    'android-a','android-apk','android-passive-v1','operational',
    repeat('b',64),clock_timestamp(),gen_random_uuid()
  ),
  'inserted',
  'canonical report_client Android platform is accepted'
); -- 15
SELECT is(
  public.record_alert_shadow_coverage_lease(
    'android-legacy','android-apk','android-passive-v1','operational',
    repeat('b',64),clock_timestamp(),gen_random_uuid()
  ),
  'capability_mismatch',
  'non-canonical Android platform is rejected'
); -- 16
SELECT is(
  public.record_alert_shadow_coverage_lease(
    'tauri-a','tauri','tauri-idle-v1','operational',
    'not-a-hash',clock_timestamp(),gen_random_uuid()
  ),
  'invalid',
  'malformed capability hash returns invalid'
); -- 17
RESET ROLE;

-- The duplicate did not create a second source row.
SELECT is(
  (
    SELECT count(*)::integer
    FROM private.alert_shadow_coverage_leases
    WHERE user_id = '48000000-0000-0000-0000-000000000001'
      AND event_id = '48200000-0000-0000-0000-000000000001'
  ),
  1,
  'duplicate event ID stores one lease row'
); -- 16

UPDATE private.alert_shadow_coverage_leases
SET received_at = '2026-07-27 00:00:00+00',
    observed_at = '2026-07-27 00:00:00+00'
WHERE event_id = '48200000-0000-0000-0000-000000000001';

SELECT private.finalize_alert_shadow_coverage(
  '48000000-0000-0000-0000-000000000001',
  '2026-07-27 00:01:00+00',
  35
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM public.alert_observation_coverage_intervals
    WHERE user_id = '48000000-0000-0000-0000-000000000001'
  ),
  0,
  'one lease yields no interval'
); -- 17

INSERT INTO private.alert_shadow_coverage_leases (
  user_id,event_id,client_id,channel,collector_contract,collector_state,
  capability_sha256,observed_at,received_at,app_version,timezone,utc_offset_minutes
) VALUES (
  '48000000-0000-0000-0000-000000000001',
  '48200000-0000-0000-0000-000000000002',
  'tauri-a','tauri','tauri-idle-v1','operational',repeat('a',64),
  '2026-07-27 00:05:00+00','2026-07-27 00:05:00+00','0.5.20','UTC',0
);
SELECT private.finalize_alert_shadow_coverage(
  '48000000-0000-0000-0000-000000000001',
  '2026-07-27 00:06:00+00',
  35
);

SELECT results_eq(
  $$
    SELECT starts_at, ends_at
    FROM public.alert_observation_coverage_intervals
    WHERE user_id = '48000000-0000-0000-0000-000000000001'
      AND starts_at = '2026-07-27 00:00:00+00'
  $$,
  $$
    VALUES (
      '2026-07-27 00:00:00+00'::timestamptz,
      '2026-07-27 00:05:00+00'::timestamptz
    )
  $$,
  'two Tauri leases close exactly the server-received interval'
); -- 18

SELECT results_eq(
  $$
    SELECT activity_coverage_state, intervention_coverage_state, sleep_context_state
    FROM public.alert_observation_coverage_intervals
    WHERE user_id = '48000000-0000-0000-0000-000000000001'
      AND starts_at = '2026-07-27 00:00:00+00'
  $$,
  $$ VALUES ('valid','valid','valid') $$,
  'Tauri gap within twelve minutes is valid'
); -- 19

INSERT INTO private.alert_shadow_coverage_leases (
  user_id,event_id,client_id,channel,collector_contract,collector_state,
  capability_sha256,observed_at,received_at,app_version,timezone,utc_offset_minutes
) VALUES (
  '48000000-0000-0000-0000-000000000001',
  '48200000-0000-0000-0000-000000000003',
  'tauri-a','tauri','tauri-idle-v1','operational',repeat('a',64),
  '2026-07-27 00:18:00+00','2026-07-27 00:18:00+00','0.5.20','UTC',0
);
SELECT private.finalize_alert_shadow_coverage(
  '48000000-0000-0000-0000-000000000001',
  '2026-07-27 00:19:00+00',
  35
);
SELECT results_eq(
  $$
    SELECT activity_coverage_state
    FROM public.alert_observation_coverage_intervals
    WHERE user_id = '48000000-0000-0000-0000-000000000001'
      AND starts_at = '2026-07-27 00:05:00+00'
  $$,
  $$ VALUES ('unknown') $$,
  'thirteen-minute Tauri gap is unknown'
); -- 20

INSERT INTO private.alert_shadow_coverage_leases (
  user_id,event_id,client_id,channel,collector_contract,collector_state,
  capability_sha256,observed_at,received_at,app_version,timezone,utc_offset_minutes
) VALUES
  (
    '48000000-0000-0000-0000-000000000001',
    '48200000-0000-0000-0000-000000000010',
    'android-a','android-apk','android-passive-v1','operational',repeat('b',64),
    '2026-07-27 01:00:00+00','2026-07-27 01:00:00+00','0.5.20','UTC',0
  ),
  (
    '48000000-0000-0000-0000-000000000001',
    '48200000-0000-0000-0000-000000000011',
    'android-a','android-apk','android-passive-v1','operational',repeat('b',64),
    '2026-07-27 01:30:00+00','2026-07-27 01:30:00+00','0.5.20','UTC',0
  ),
  (
    '48000000-0000-0000-0000-000000000001',
    '48200000-0000-0000-0000-000000000012',
    'android-a','android-apk','android-passive-v1','operational',repeat('b',64),
    '2026-07-27 02:06:00+00','2026-07-27 02:06:00+00','0.5.20','UTC',0
  );
SELECT private.finalize_alert_shadow_coverage(
  '48000000-0000-0000-0000-000000000001',
  '2026-07-27 02:07:00+00',
  35
);
SELECT results_eq(
  $$ SELECT activity_coverage_state FROM public.alert_observation_coverage_intervals
     WHERE user_id='48000000-0000-0000-0000-000000000001'
       AND starts_at='2026-07-27 01:00:00+00' $$,
  $$ VALUES ('valid') $$,
  'thirty-minute Android gap is valid'
); -- 21
SELECT results_eq(
  $$ SELECT activity_coverage_state FROM public.alert_observation_coverage_intervals
     WHERE user_id='48000000-0000-0000-0000-000000000001'
       AND starts_at='2026-07-27 01:30:00+00' $$,
  $$ VALUES ('unknown') $$,
  'thirty-six-minute Android gap is unknown'
); -- 22

-- Metadata partitions must never bridge coverage.
INSERT INTO private.alert_shadow_coverage_leases (
  user_id,event_id,client_id,channel,collector_contract,collector_state,
  capability_sha256,observed_at,received_at,app_version,timezone,utc_offset_minutes
) VALUES
  ('48000000-0000-0000-0000-000000000001','48200000-0000-0000-0000-000000000020','split-client-a','tauri','tauri-idle-v1','operational',repeat('c',64),'2026-07-27 03:00+00','2026-07-27 03:00+00','1','UTC',0),
  ('48000000-0000-0000-0000-000000000001','48200000-0000-0000-0000-000000000021','split-client-b','tauri','tauri-idle-v1','operational',repeat('c',64),'2026-07-27 03:05+00','2026-07-27 03:05+00','1','UTC',0),
  ('48000000-0000-0000-0000-000000000001','48200000-0000-0000-0000-000000000022','split-cap','tauri','tauri-idle-v1','operational',repeat('d',64),'2026-07-27 03:10+00','2026-07-27 03:10+00','1','UTC',0),
  ('48000000-0000-0000-0000-000000000001','48200000-0000-0000-0000-000000000023','split-cap','tauri','tauri-idle-v1','operational',repeat('e',64),'2026-07-27 03:15+00','2026-07-27 03:15+00','1','UTC',0),
  ('48000000-0000-0000-0000-000000000001','48200000-0000-0000-0000-000000000024','split-version','tauri','tauri-idle-v1','operational',repeat('f',64),'2026-07-27 03:20+00','2026-07-27 03:20+00','1','UTC',0),
  ('48000000-0000-0000-0000-000000000001','48200000-0000-0000-0000-000000000025','split-version','tauri','tauri-idle-v1','operational',repeat('f',64),'2026-07-27 03:25+00','2026-07-27 03:25+00','2','UTC',0),
  ('48000000-0000-0000-0000-000000000001','48200000-0000-0000-0000-000000000026','split-timezone','tauri','tauri-idle-v1','operational',repeat('1',64),'2026-07-27 03:30+00','2026-07-27 03:30+00','1','UTC',0),
  ('48000000-0000-0000-0000-000000000001','48200000-0000-0000-0000-000000000027','split-timezone','tauri','tauri-idle-v1','operational',repeat('1',64),'2026-07-27 03:35+00','2026-07-27 03:35+00','1','Asia/Dhaka',360);
SELECT private.finalize_alert_shadow_coverage(
  '48000000-0000-0000-0000-000000000001',
  '2026-07-27 03:36:00+00',
  35
);
SELECT is((SELECT count(*)::integer FROM public.alert_observation_coverage_intervals WHERE starts_at='2026-07-27 03:00+00'),0,'client change splits intervals'); -- 23
SELECT is((SELECT count(*)::integer FROM public.alert_observation_coverage_intervals WHERE starts_at='2026-07-27 03:10+00'),0,'capability change splits intervals'); -- 24
SELECT is((SELECT count(*)::integer FROM public.alert_observation_coverage_intervals WHERE starts_at='2026-07-27 03:20+00'),0,'app version change splits intervals'); -- 25
SELECT is((SELECT count(*)::integer FROM public.alert_observation_coverage_intervals WHERE starts_at='2026-07-27 03:30+00'),0,'timezone change splits intervals'); -- 26

INSERT INTO private.alert_shadow_coverage_leases (
  user_id,event_id,client_id,channel,collector_contract,collector_state,
  capability_sha256,observed_at,received_at,app_version,timezone,utc_offset_minutes
) VALUES
  ('48000000-0000-0000-0000-000000000001','48200000-0000-0000-0000-000000000030','observed-order','tauri','tauri-idle-v1','operational',repeat('2',64),'2026-07-27 05:00+00','2026-07-27 04:00+00','1','UTC',0),
  ('48000000-0000-0000-0000-000000000001','48200000-0000-0000-0000-000000000031','observed-order','tauri','tauri-idle-v1','operational',repeat('2',64),'2026-07-27 03:00+00','2026-07-27 04:05+00','1','UTC',0);
SELECT private.finalize_alert_shadow_coverage(
  '48000000-0000-0000-0000-000000000001',
  '2026-07-27 04:06:00+00',
  35
);
SELECT results_eq(
  $$ SELECT starts_at,ends_at FROM public.alert_observation_coverage_intervals
     WHERE starts_at='2026-07-27 04:00+00' $$,
  $$ VALUES ('2026-07-27 04:00+00'::timestamptz,'2026-07-27 04:05+00'::timestamptz) $$,
  'received_at, not out-of-order observed_at, bounds coverage'
); -- 27

-- 28..32: Data API and publication boundaries.
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM information_schema.table_privileges
    WHERE table_schema='private' AND table_name='alert_shadow_coverage_leases'
      AND grantee IN ('PUBLIC','anon','authenticated','service_role')
  ),
  'lease table grants no Data API role'
);
SELECT function_privs_are(
  'public','record_alert_shadow_coverage_lease',
  ARRAY['text','text','text','text','text','timestamp with time zone','uuid'],
  'authenticated',ARRAY['EXECUTE']
);
SELECT function_privs_are(
  'public','record_alert_shadow_coverage_lease_for_user',
  ARRAY['uuid','text','text','text','text','text','timestamp with time zone','uuid'],
  'authenticated',ARRAY[]::text[]
);
SELECT function_privs_are(
  'public','record_alert_shadow_coverage_lease_for_user',
  ARRAY['uuid','text','text','text','text','text','timestamp with time zone','uuid'],
  'service_role',ARRAY['EXECUTE']
);
SELECT function_privs_are(
  'private','record_alert_shadow_coverage_lease_core',
  ARRAY['uuid','text','text','text','text','text','timestamp with time zone','uuid'],
  'service_role',ARRAY[]::text[]
);
SELECT function_privs_are(
  'private','finalize_alert_shadow_coverage',
  ARRAY['uuid','timestamp with time zone','integer'],
  'service_role',ARRAY[]::text[]
);
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname='supabase_realtime'
      AND (
        (schemaname='private' AND tablename='alert_shadow_coverage_leases')
        OR (schemaname='public' AND tablename='alert_observation_coverage_intervals')
      )
  ),
  'lease and coverage tables are not in Realtime'
);

-- 35: every security-definer function is UTC, empty-path, and owner-only.
SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_proc p
    WHERE p.oid IN (
      'private.record_alert_shadow_coverage_lease_core(uuid,text,text,text,text,text,timestamptz,uuid)'::regprocedure,
      'public.record_alert_shadow_coverage_lease(text,text,text,text,text,timestamptz,uuid)'::regprocedure,
      'public.record_alert_shadow_coverage_lease_for_user(uuid,text,text,text,text,text,timestamptz,uuid)'::regprocedure,
      'private.finalize_alert_shadow_coverage(uuid,timestamptz,integer)'::regprocedure
    )
      AND p.prosecdef
      AND p.proconfig @> ARRAY['search_path=""','TimeZone=UTC']
  ),
  4,
  'all coverage functions are security-definer with empty path and UTC'
);

INSERT INTO private.alert_shadow_coverage_leases (
  user_id,event_id,client_id,channel,collector_contract,collector_state,
  capability_sha256,observed_at,received_at,app_version,timezone,utc_offset_minutes
) VALUES (
  '48000000-0000-0000-0000-000000000001',
  '48200000-0000-0000-0000-000000000099',
  'old-source','tauri','tauri-idle-v1','operational',repeat('9',64),
  '2026-06-01 00:00+00','2026-06-01 00:00+00','1','UTC',0
);
INSERT INTO public.alert_observation_coverage_intervals (
  version_id,user_id,starts_at,ends_at,timezone,utc_offset_minutes,
  activity_coverage_state,intervention_coverage_state,sleep_context_state,
  captured_at,finalized_at,evidence_version,provenance_sha256
) VALUES (
  '48100000-0000-0000-0000-000000000001',
  '48000000-0000-0000-0000-000000000001',
  '2026-06-01 00:00+00','2026-06-01 00:05+00','UTC',0,
  'valid','valid','valid','2026-06-01 00:05+00','2026-06-01 00:06+00',
  'coverage-lease-v1',repeat('8',64)
);
SELECT private.finalize_alert_shadow_coverage(
  '48000000-0000-0000-0000-000000000001',
  '2026-07-27 05:00:00+00',
  35
);
SELECT is(
  (
    SELECT
      (SELECT count(*) FROM private.alert_shadow_coverage_leases
       WHERE event_id='48200000-0000-0000-0000-000000000099')
      +
      (SELECT count(*) FROM public.alert_observation_coverage_intervals
       WHERE provenance_sha256=repeat('8',64))
  )::integer,
  0,
  'cleanup removes source-identifiable lease and detail rows older than 35 days'
); -- 36

SELECT * FROM finish();
ROLLBACK;
