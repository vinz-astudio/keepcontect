BEGIN;
SELECT plan(42);

INSERT INTO auth.users (id, email, aud, role) VALUES
  ('45000000-0000-0000-0000-000000000001', 'cohort-120@example.invalid', 'authenticated', 'authenticated'),
  ('45000000-0000-0000-0000-000000000002', 'cohort-180@example.invalid', 'authenticated', 'authenticated'),
  ('45000000-0000-0000-0000-000000000003', 'cohort-240@example.invalid', 'authenticated', 'authenticated'),
  ('45000000-0000-0000-0000-000000000004', 'cohort-1200@example.invalid', 'authenticated', 'authenticated'),
  ('45000000-0000-0000-0000-000000000005', 'cohort-no-consent@example.invalid', 'authenticated', 'authenticated'),
  ('45000000-0000-0000-0000-000000000006', 'cohort-semester@example.invalid', 'authenticated', 'authenticated'),
  ('45000000-0000-0000-0000-000000000007', 'cohort-trigger-old@example.invalid', 'authenticated', 'authenticated'),
  ('45000000-0000-0000-0000-000000000008', 'cohort-trigger-new@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, display_name, consent_data_sharing, routine_pattern) VALUES
  ('45000000-0000-0000-0000-000000000001', 'Cohort 120', true, 'regular_9to5'),
  ('45000000-0000-0000-0000-000000000002', 'Cohort 180', true, 'regular_9to5'),
  ('45000000-0000-0000-0000-000000000003', 'Cohort 240', true, 'regular_9to5'),
  ('45000000-0000-0000-0000-000000000004', 'Cohort 1200', true, 'regular_9to5'),
  ('45000000-0000-0000-0000-000000000005', 'Cohort no consent', false, 'regular_9to5'),
  ('45000000-0000-0000-0000-000000000006', 'Cohort semester', true, 'semester_break'),
  ('45000000-0000-0000-0000-000000000007', 'Cohort trigger old', false, 'regular_9to5'),
  ('45000000-0000-0000-0000-000000000008', 'Cohort trigger new', false, 'semester_break');

WITH config AS (
  SELECT '{"sessionization":{"gap_minutes":30,"per_user_day_gap_cap":1,"training_horizon_days":30,"intervention_window_minutes":30},"context":{"definition_version":"cohort-test-v1","day_partition":"all_days","hour_bucket_minutes":60},"personal":{"min_samples":1,"min_support_dates":1,"min_span_days":1,"max_age_days":30,"min_confidence":0.7,"confidence_formula_version":"support_ratio_v1"},"cohort":{"min_contributors":4,"min_support_dates":5,"min_span_days":5,"max_age_days":30,"min_confidence":0.5,"contribution_floor_minutes":100,"contribution_ceiling_minutes":1000,"confidence_formula_version":"cohort_support_min_v1","algorithm":"weighted_median","trim_fraction":0.25},"sensitivity_buffers_minutes":{"high":0,"balanced":45,"low":90},"candidate_bounds":{"floor_minutes":1,"ceiling_minutes":600},"sleep_compensation":{"max_start_delay_minutes":0,"max_wake_advance_minutes":0,"max_wake_delay_minutes":0,"max_update_minutes_per_day":0,"min_positive_nights":1,"lookback_nights":1,"min_late_events_per_night":1,"timezone_tolerance_minutes":0},"evaluator":{"contract_version":"adaptive_candidate_v1"},"emergency":{"contract_version":"adr0022_v1","neutral_minutes":90,"expected_live_definition_sha256":"c3efc6cc664dc334166a034651ff584d4c7766d80775c3fe3bc012eb97a9b150"}}'::jsonb AS value
)
INSERT INTO public.alert_model_versions (id, name, status, config, config_sha256, evidence_version)
SELECT '45000000-0000-0000-0000-000000000010', 'cohort-weighted-median', 'replay', value,
  encode(extensions.digest(value::text, 'sha256'), 'hex'), 'canonical-v2'
FROM config;

WITH config AS (
  SELECT '{"sessionization":{"gap_minutes":30,"per_user_day_gap_cap":1,"training_horizon_days":30,"intervention_window_minutes":30},"context":{"definition_version":"cohort-test-v1","day_partition":"all_days","hour_bucket_minutes":60},"personal":{"min_samples":1,"min_support_dates":1,"min_span_days":1,"max_age_days":30,"min_confidence":0.7,"confidence_formula_version":"support_ratio_v1"},"cohort":{"min_contributors":4,"min_support_dates":5,"min_span_days":5,"max_age_days":30,"min_confidence":0.5,"contribution_floor_minutes":100,"contribution_ceiling_minutes":1000,"confidence_formula_version":"cohort_support_min_v1","algorithm":"trimmed_mean","trim_fraction":0.25},"sensitivity_buffers_minutes":{"high":0,"balanced":45,"low":90},"candidate_bounds":{"floor_minutes":1,"ceiling_minutes":600},"sleep_compensation":{"max_start_delay_minutes":0,"max_wake_advance_minutes":0,"max_wake_delay_minutes":0,"max_update_minutes_per_day":0,"min_positive_nights":1,"lookback_nights":1,"min_late_events_per_night":1,"timezone_tolerance_minutes":0},"evaluator":{"contract_version":"adaptive_candidate_v1"},"emergency":{"contract_version":"adr0022_v1","neutral_minutes":90,"expected_live_definition_sha256":"c3efc6cc664dc334166a034651ff584d4c7766d80775c3fe3bc012eb97a9b150"}}'::jsonb AS value
)
INSERT INTO public.alert_model_versions (id, name, status, config, config_sha256, evidence_version)
SELECT '45000000-0000-0000-0000-000000000020', 'cohort-trimmed-mean', 'replay', value,
  encode(extensions.digest(value::text, 'sha256'), 'hex'), 'canonical-v2'
FROM config;

INSERT INTO public.alert_gap_profiles (
  version_id, user_id, context_key, through_date, neutral_p95_minutes,
  sample_count, distinct_support_dates, support_started_on, support_ended_on,
  latest_evidence_at, quality_state, confidence, profile_sha256, input_sha256
)
SELECT version_id, user_id, 'personal_global', '2026-07-10', neutral,
  CASE WHEN user_id='45000000-0000-0000-0000-000000000004'::uuid THEN 10000 ELSE 10 END, 10, '2026-07-01', '2026-07-10', CASE WHEN user_id='45000000-0000-0000-0000-000000000002'::uuid THEN '2026-07-10 16:00+00'::timestamptz ELSE '2026-07-10 12:00+00'::timestamptz END,
  'valid', 1, repeat(profile_hash, 64), repeat(input_hash, 64)
FROM (
  VALUES
    ('45000000-0000-0000-0000-000000000010'::uuid, '45000000-0000-0000-0000-000000000001'::uuid, 120, 'a', 'b'),
    ('45000000-0000-0000-0000-000000000010'::uuid, '45000000-0000-0000-0000-000000000002'::uuid, 180, 'c', 'd'),
    ('45000000-0000-0000-0000-000000000010'::uuid, '45000000-0000-0000-0000-000000000003'::uuid, 240, 'e', 'f'),
    ('45000000-0000-0000-0000-000000000010'::uuid, '45000000-0000-0000-0000-000000000004'::uuid, 1200, '1', '2'),
    ('45000000-0000-0000-0000-000000000010'::uuid, '45000000-0000-0000-0000-000000000005'::uuid, 999, '3', '4'),
    ('45000000-0000-0000-0000-000000000010'::uuid, '45000000-0000-0000-0000-000000000006'::uuid, 300, '5', '6'),
    ('45000000-0000-0000-0000-000000000020'::uuid, '45000000-0000-0000-0000-000000000001'::uuid, 120, '7', '8'),
    ('45000000-0000-0000-0000-000000000020'::uuid, '45000000-0000-0000-0000-000000000002'::uuid, 180, '9', 'a'),
    ('45000000-0000-0000-0000-000000000020'::uuid, '45000000-0000-0000-0000-000000000003'::uuid, 240, 'b', 'c'),
    ('45000000-0000-0000-0000-000000000020'::uuid, '45000000-0000-0000-0000-000000000004'::uuid, 1200, 'd', 'e')
) AS fixture(version_id, user_id, neutral, profile_hash, input_hash);

INSERT INTO public.alert_gap_profiles (version_id,user_id,context_key,through_date,neutral_p95_minutes,sample_count,distinct_support_dates,support_started_on,support_ended_on,latest_evidence_at,quality_state,confidence,profile_sha256,input_sha256)
VALUES ('45000000-0000-0000-0000-000000000010','45000000-0000-0000-0000-000000000007','personal_global','2026-07-10',300,10,10,'2026-07-01','2026-07-10','2026-07-10 12:00+00','valid',1,repeat('7',64),repeat('8',64));

SELECT has_column('public', 'routine_mode_cohort_priors', 'source_generation', 'prior stores invalidation generation');
SELECT has_column('public', 'routine_mode_cohort_priors', 'valid_until', 'prior stores conservative expiry');
SELECT has_column('public', 'routine_mode_cohort_priors', 'oldest_evidence_at', 'prior stores only aggregate oldest freshness');
SELECT has_column('public', 'routine_mode_cohort_priors', 'conservative_span_days', 'prior stores the minimum admitted per-user span');
SELECT has_function('private', 'rebuild_routine_mode_cohort_priors', ARRAY['uuid', 'date', 'text'], 'cohort builder exists');
SELECT has_function('private', 'routine_mode_cohort_prior_is_valid', ARRAY['uuid', 'text', 'date', 'timestamp with time zone'], 'cohort selection helper exists');
SELECT throws_ok($$ INSERT INTO public.alert_model_versions(name,status,config,config_sha256,evidence_version) VALUES ('cohort-config-missing','draft','{"sessionization":{"gap_minutes":1,"per_user_day_gap_cap":1,"training_horizon_days":1,"intervention_window_minutes":0},"context":{"definition_version":"x","day_partition":"all_days","hour_bucket_minutes":60},"personal":{"min_samples":1,"min_support_dates":1,"min_span_days":1,"max_age_days":1,"confidence_formula_version":"support_ratio_v1"},"cohort":{"min_contributors":1,"min_support_dates":1,"min_span_days":1,"max_age_days":1,"min_confidence":1,"contribution_floor_minutes":1,"contribution_ceiling_minutes":2,"algorithm":"weighted_median","trim_fraction":0},"sensitivity_buffers_minutes":{"high":0,"balanced":45,"low":90},"candidate_bounds":{"floor_minutes":1,"ceiling_minutes":2},"sleep_compensation":{"max_start_delay_minutes":0,"max_wake_advance_minutes":0,"max_wake_delay_minutes":0,"max_update_minutes_per_day":0,"min_positive_nights":1,"lookback_nights":1,"min_late_events_per_night":1,"timezone_tolerance_minutes":0}}'::jsonb,repeat('0',64),'canonical-v2') $$, '23514'::char(5), NULL, 'missing cohort confidence formula is rejected');
SELECT throws_ok($$ INSERT INTO public.alert_model_versions(name,status,config,config_sha256,evidence_version) VALUES ('cohort-config-domain','draft','{"sessionization":{"gap_minutes":1,"per_user_day_gap_cap":1,"training_horizon_days":1,"intervention_window_minutes":0},"context":{"definition_version":"x","day_partition":"all_days","hour_bucket_minutes":60},"personal":{"min_samples":1,"min_support_dates":1,"min_span_days":1,"max_age_days":1,"confidence_formula_version":"support_ratio_v1"},"cohort":{"min_contributors":1,"min_support_dates":1,"min_span_days":1,"max_age_days":1,"min_confidence":0,"contribution_floor_minutes":3,"contribution_ceiling_minutes":2,"confidence_formula_version":"cohort_support_min_v1","algorithm":"weighted_median","trim_fraction":0},"sensitivity_buffers_minutes":{"high":0,"balanced":45,"low":90},"candidate_bounds":{"floor_minutes":1,"ceiling_minutes":2},"sleep_compensation":{"max_start_delay_minutes":0,"max_wake_advance_minutes":0,"max_wake_delay_minutes":0,"max_update_minutes_per_day":0,"min_positive_nights":1,"lookback_nights":1,"min_late_events_per_night":1,"timezone_tolerance_minutes":0}}'::jsonb,repeat('1',64),'canonical-v2') $$, '23514'::char(5), NULL, 'cohort bounds and confidence domain are enforced');

SELECT is((private.rebuild_routine_mode_cohort_priors('45000000-0000-0000-0000-000000000010', '2026-07-10', 'regular_9to5') ->> 'published')::integer, 1, 'weighted cohort rebuild publishes one aggregate row');
SELECT results_eq(
  $$ SELECT neutral_p95_minutes, contributor_count, conservative_span_days, oldest_evidence_at, latest_evidence_at, quality_state, confidence, algorithm FROM public.routine_mode_cohort_priors WHERE version_id='45000000-0000-0000-0000-000000000010' AND routine_mode='regular_9to5' AND context_key='personal_global' AND through_date='2026-07-10' $$,
  $$ VALUES (180,4,10,'2026-07-10 12:00+00'::timestamptz,'2026-07-10 16:00+00'::timestamptz,'valid'::text,1::double precision,'weighted_median'::text) $$,
  'weighted median is the exact one-user-one-value result, not raw-event weighted'
);
SELECT is((SELECT contributor_count FROM public.routine_mode_cohort_priors WHERE version_id='45000000-0000-0000-0000-000000000010' AND routine_mode='regular_9to5'), 4, 'non-consenting profile is excluded despite a valid personal row');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='routine_mode_cohort_priors' AND column_name IN ('user_id','contributor_ids','contributors')), 'published prior has no membership column');
SELECT is((private.rebuild_routine_mode_cohort_priors('45000000-0000-0000-0000-000000000010', '2026-07-10', 'shift_irregular') ->> 'published')::integer, 0, 'zero contributors publish no row');
SELECT is_empty($$ SELECT * FROM public.routine_mode_cohort_priors WHERE version_id='45000000-0000-0000-0000-000000000010' AND routine_mode='shift_irregular' $$, 'zero contributor rebuild removes no-support prior');
INSERT INTO public.routine_mode_cohort_priors (version_id,routine_mode,context_key,through_date,contributor_count,distinct_support_dates,support_started_on,support_ended_on,latest_evidence_at,neutral_p95_minutes,quality_state,confidence,algorithm,config_sha256,evidence_version,input_sha256,prior_sha256)
SELECT id,'shift_irregular','personal_global','2026-07-10',4,10,'2026-07-01','2026-07-10','2026-07-10 12:00+00',180,'valid',1,'weighted_median',config_sha256,evidence_version,repeat('a',64),repeat('b',64)
FROM public.alert_model_versions WHERE id='45000000-0000-0000-0000-000000000010';
SELECT is((private.rebuild_routine_mode_cohort_priors('45000000-0000-0000-0000-000000000010', '2026-07-10', 'shift_irregular') ->> 'published')::integer, 0, 'zero contributor rebuild removes a previously published target');
SELECT is_empty($$ SELECT * FROM public.routine_mode_cohort_priors WHERE version_id='45000000-0000-0000-0000-000000000010' AND routine_mode='shift_irregular' $$, 'zero contributor rebuild deletes the old target row');
SELECT is((private.rebuild_routine_mode_cohort_priors('45000000-0000-0000-0000-000000000010', '2026-07-10', 'semester_break') ->> 'published')::integer, 1, 'under-supported mode is stored for audit');
SELECT results_eq($$ SELECT contributor_count, quality_state, round(confidence::numeric,2) FROM public.routine_mode_cohort_priors WHERE version_id='45000000-0000-0000-0000-000000000010' AND routine_mode='semester_break' $$, $$ VALUES (1,'low_support'::text,0.25::numeric) $$, 'low support uses conservative support-min confidence and cannot become valid');

CREATE TEMP TABLE weighted_before AS SELECT input_sha256, prior_sha256, published_at FROM public.routine_mode_cohort_priors WHERE version_id='45000000-0000-0000-0000-000000000010' AND routine_mode='regular_9to5';
SELECT is((private.rebuild_routine_mode_cohort_priors('45000000-0000-0000-0000-000000000010', '2026-07-10', 'regular_9to5') ->> 'published')::integer, 0, 'identical weighted rebuild is idempotent');
SELECT results_eq($$ SELECT * FROM weighted_before EXCEPT SELECT input_sha256, prior_sha256, published_at FROM public.routine_mode_cohort_priors WHERE version_id='45000000-0000-0000-0000-000000000010' AND routine_mode='regular_9to5' $$, $$ SELECT * FROM weighted_before WHERE false $$, 'identical aggregate input preserves hashes and publication time');
SELECT ok(NOT private.routine_mode_cohort_prior_is_valid('45000000-0000-0000-0000-000000000010','regular_9to5','2026-07-10','2026-07-10 23:59:59+00'), 'prior cannot be selected before its exclusive through-date cutoff');
SELECT ok(NOT private.routine_mode_cohort_prior_is_valid('45000000-0000-0000-0000-000000000010','regular_9to5','2026-07-10','2026-08-09 12:00+00'), 'prior is invalid exactly at valid_until');
CREATE TEMP TABLE profile_key_before AS SELECT generation FROM public.routine_mode_cohort_generations WHERE routine_mode='regular_9to5';
UPDATE public.alert_gap_profiles SET context_key='non_global_context' WHERE version_id='45000000-0000-0000-0000-000000000010' AND user_id='45000000-0000-0000-0000-000000000007' AND context_key='personal_global';
SELECT ok((SELECT current.generation = b.generation + 1 FROM public.routine_mode_cohort_generations current CROSS JOIN profile_key_before b WHERE current.routine_mode='regular_9to5'), 'personal-global to non-global invalidates the OLD user mode');
SELECT ok(NOT private.routine_mode_cohort_prior_is_valid('45000000-0000-0000-0000-000000000010','regular_9to5','2026-07-10','2026-07-11 00:00+00'), 'old-side profile-key invalidation makes a published prior unusable immediately');
CREATE TEMP TABLE profile_key_new_before AS SELECT generation FROM public.routine_mode_cohort_generations WHERE routine_mode='regular_9to5';
UPDATE public.alert_gap_profiles SET context_key='personal_global' WHERE version_id='45000000-0000-0000-0000-000000000010' AND user_id='45000000-0000-0000-0000-000000000007' AND context_key='non_global_context';
SELECT ok((SELECT current.generation = b.generation + 1 FROM public.routine_mode_cohort_generations current CROSS JOIN profile_key_new_before b WHERE current.routine_mode='regular_9to5'), 'non-global to personal-global invalidates the NEW user mode');
CREATE TEMP TABLE profile_user_before AS SELECT routine_mode, generation FROM public.routine_mode_cohort_generations WHERE routine_mode IN ('regular_9to5','semester_break');
UPDATE public.alert_gap_profiles SET user_id='45000000-0000-0000-0000-000000000008' WHERE version_id='45000000-0000-0000-0000-000000000010' AND user_id='45000000-0000-0000-0000-000000000007' AND context_key='personal_global';
SELECT results_eq($$ SELECT current.routine_mode, current.generation-b.generation FROM public.routine_mode_cohort_generations current JOIN profile_user_before b USING (routine_mode) WHERE current.routine_mode IN ('regular_9to5','semester_break') ORDER BY current.routine_mode $$, $$ VALUES ('regular_9to5'::text,1::bigint), ('semester_break'::text,1::bigint) $$, 'personal-global user reassignment invalidates both OLD and NEW current modes once');
SELECT is((private.rebuild_routine_mode_cohort_priors('45000000-0000-0000-0000-000000000010', '2026-07-10', 'regular_9to5') ->> 'published')::integer, 1, 'rebuild republishes after profile-key invalidations');
UPDATE public.routine_mode_cohort_priors SET prior_sha256=repeat('0',64) WHERE version_id='45000000-0000-0000-0000-000000000010' AND routine_mode='regular_9to5';
SELECT ok(NOT private.routine_mode_cohort_prior_is_valid('45000000-0000-0000-0000-000000000010','regular_9to5','2026-07-10','2026-07-11 00:00+00'), 'selection helper rejects a row whose aggregate hash no longer recomputes');

CREATE TEMP TABLE invalidation_before AS SELECT generation FROM public.routine_mode_cohort_invalidations WHERE routine_mode='regular_9to5';
UPDATE public.profiles SET consent_data_sharing=false WHERE id='45000000-0000-0000-0000-000000000004';
SELECT ok((SELECT i.generation = b.generation + 1 FROM public.routine_mode_cohort_invalidations i CROSS JOIN invalidation_before b WHERE i.routine_mode='regular_9to5'), 'withdrawal increments the affected mode generation exactly once');
SELECT ok(NOT private.routine_mode_cohort_prior_is_valid('45000000-0000-0000-0000-000000000010','regular_9to5','2026-07-10','2026-07-11 00:00+00'), 'withdrawal invalidates the old published prior before rebuild');
SELECT is((private.rebuild_routine_mode_cohort_priors('45000000-0000-0000-0000-000000000010', '2026-07-10', 'regular_9to5') ->> 'published')::integer, 1, 'rebuild replaces old valid prior after withdrawal');
SELECT is((SELECT quality_state FROM public.routine_mode_cohort_priors WHERE version_id='45000000-0000-0000-0000-000000000010' AND routine_mode='regular_9to5'), 'low_support', 'low-support rebuild overwrites old valid row');

CREATE TEMP TABLE dual_mode_before AS SELECT routine_mode, generation FROM public.routine_mode_cohort_invalidations WHERE routine_mode IN ('regular_9to5','semester_break');
UPDATE public.profiles SET routine_pattern='semester_break' WHERE id='45000000-0000-0000-0000-000000000001';
SELECT results_eq($$ SELECT i.routine_mode, i.generation-b.generation FROM public.routine_mode_cohort_invalidations i JOIN dual_mode_before b USING (routine_mode) WHERE i.routine_mode IN ('regular_9to5','semester_break') ORDER BY i.routine_mode $$, $$ VALUES ('regular_9to5'::text,1::bigint), ('semester_break'::text,1::bigint) $$, 'mode change invalidates both modes once under lexical locking');

CREATE TEMP TABLE live_snapshot AS
SELECT
  (SELECT coalesce(md5(string_agg(to_jsonb(a)::text, ',' ORDER BY a.id)), '') FROM public.alerts a) AS alerts_hash,
  (SELECT coalesce(md5(string_agg(to_jsonb(e)::text, ',' ORDER BY e.id)), '') FROM public.alert_events e) AS events_hash,
  (SELECT coalesce(md5(string_agg(to_jsonb(n)::text, ',' ORDER BY n.id)), '') FROM public.notifications n) AS notifications_hash,
  (SELECT coalesce(md5(string_agg(to_jsonb(p)::text, ',' ORDER BY p.id)), '') FROM public.behavior_pings p) AS pings_hash,
  (SELECT coalesce(md5(string_agg(to_jsonb(p)::text, ',' ORDER BY p.id)), '') FROM public.profiles p) AS profiles_hash;

SELECT is((private.rebuild_routine_mode_cohort_priors('45000000-0000-0000-0000-000000000020', '2026-07-10', 'regular_9to5') ->> 'published')::integer, 1, 'trimmed-mean rebuild publishes one aggregate row');
SELECT is((SELECT neutral_p95_minutes FROM public.routine_mode_cohort_priors WHERE version_id='45000000-0000-0000-0000-000000000020' AND routine_mode='regular_9to5'), 210, 'trimmed mean clamps then trims exactly one value from each tail');
UPDATE public.alert_model_versions SET config_sha256=repeat('f',64) WHERE id='45000000-0000-0000-0000-000000000020';
SELECT is((private.rebuild_routine_mode_cohort_priors('45000000-0000-0000-0000-000000000020', '2026-07-10', 'regular_9to5') ->> 'published')::integer, 0, 'config hash mismatch fails closed');

SELECT function_privs_are('private', 'rebuild_routine_mode_cohort_priors', ARRAY['uuid','date','text'], 'anon', ARRAY[]::text[]);
SELECT function_privs_are('private', 'rebuild_routine_mode_cohort_priors', ARRAY['uuid','date','text'], 'authenticated', ARRAY[]::text[]);
SELECT function_privs_are('private', 'rebuild_routine_mode_cohort_priors', ARRAY['uuid','date','text'], 'service_role', ARRAY[]::text[]);
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='routine_mode_cohort_priors'), 'cohort priors are not realtime');
SELECT ok(NOT EXISTS (SELECT 1 FROM cron.job WHERE lower(command) ~ 'cohort_prior' OR lower(jobname) ~ 'cohort_prior'), 'cohort builder schedules no cron');
SELECT results_eq($$ SELECT * FROM live_snapshot EXCEPT SELECT (SELECT coalesce(md5(string_agg(to_jsonb(a)::text, ',' ORDER BY a.id)), '') FROM public.alerts a), (SELECT coalesce(md5(string_agg(to_jsonb(e)::text, ',' ORDER BY e.id)), '') FROM public.alert_events e), (SELECT coalesce(md5(string_agg(to_jsonb(n)::text, ',' ORDER BY n.id)), '') FROM public.notifications n), (SELECT coalesce(md5(string_agg(to_jsonb(p)::text, ',' ORDER BY p.id)), '') FROM public.behavior_pings p), (SELECT coalesce(md5(string_agg(to_jsonb(p)::text, ',' ORDER BY p.id)), '') FROM public.profiles p) $$, $$ SELECT * FROM live_snapshot WHERE false $$, 'candidate cohort build leaves live snapshots unchanged apart from explicit fixture updates');

SELECT * FROM finish();
ROLLBACK;
