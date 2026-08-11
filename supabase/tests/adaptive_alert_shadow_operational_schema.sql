-- ADR-0028 bounded operational evidence producers: private, consent-safe, no live authority.
BEGIN;
SELECT plan(42);

-- 1..3 locked worker surface.
SELECT has_function('private', 'capture_alert_shadow_subject_contexts',
  ARRAY['uuid','timestamp with time zone','integer']);
SELECT has_function('private', 'capture_alert_shadow_interventions',
  ARRAY['uuid','timestamp with time zone','integer']);
SELECT has_function('private', 'maintain_adaptive_alert_shadow',
  ARRAY['timestamp with time zone','integer']);

-- 4..10 exact private operational objects.
SELECT has_table('private', 'adaptive_alert_shadow_user_state',
  'private latest user state exists');
SELECT has_table('private', 'adaptive_alert_shadow_cycle_runs',
  'private cycle run aggregate exists');
SELECT has_table('private', 'adaptive_alert_shadow_daily_reports',
  'private suppressed daily report exists');
SELECT has_table('private', 'adaptive_alert_shadow_profile_dirty',
  'private profile invalidation queue exists');
SELECT has_table('private', 'adaptive_alert_shadow_cohort_dirty',
  'private cohort invalidation queue exists');
SELECT has_table('private', 'adaptive_alert_shadow_subject_context_state',
  'private context capture state exists');
SELECT has_table('private', 'adaptive_alert_shadow_intervention_cursor',
  'private intervention cursor exists');

-- 11..17 every private object is RLS protected.
SELECT is((SELECT relrowsecurity FROM pg_class WHERE oid =
  'private.adaptive_alert_shadow_user_state'::regclass), true);
SELECT is((SELECT relrowsecurity FROM pg_class WHERE oid =
  'private.adaptive_alert_shadow_cycle_runs'::regclass), true);
SELECT is((SELECT relrowsecurity FROM pg_class WHERE oid =
  'private.adaptive_alert_shadow_daily_reports'::regclass), true);
SELECT is((SELECT relrowsecurity FROM pg_class WHERE oid =
  'private.adaptive_alert_shadow_profile_dirty'::regclass), true);
SELECT is((SELECT relrowsecurity FROM pg_class WHERE oid =
  'private.adaptive_alert_shadow_cohort_dirty'::regclass), true);
SELECT is((SELECT relrowsecurity FROM pg_class WHERE oid =
  'private.adaptive_alert_shadow_subject_context_state'::regclass), true);
SELECT is((SELECT relrowsecurity FROM pg_class WHERE oid =
  'private.adaptive_alert_shadow_intervention_cursor'::regclass), true);

-- 18..24 no client-role table reads.
SELECT is(has_table_privilege('authenticated',
  'private.adaptive_alert_shadow_user_state', 'SELECT'), false);
SELECT is(has_table_privilege('authenticated',
  'private.adaptive_alert_shadow_cycle_runs', 'SELECT'), false);
SELECT is(has_table_privilege('authenticated',
  'private.adaptive_alert_shadow_daily_reports', 'SELECT'), false);
SELECT is(has_table_privilege('authenticated',
  'private.adaptive_alert_shadow_profile_dirty', 'SELECT'), false);
SELECT is(has_table_privilege('authenticated',
  'private.adaptive_alert_shadow_cohort_dirty', 'SELECT'), false);
SELECT is(has_table_privilege('authenticated',
  'private.adaptive_alert_shadow_subject_context_state', 'SELECT'), false);
SELECT is(has_table_privilege('authenticated',
  'private.adaptive_alert_shadow_intervention_cursor', 'SELECT'), false);

-- 25 no operational object enters Realtime.
SELECT is((
  SELECT count(*)::integer
  FROM pg_publication_tables
  WHERE schemaname = 'private'
    AND tablename LIKE 'adaptive_alert_shadow_%'
), 0);

INSERT INTO auth.users (id,email,aud,role) VALUES
  ('49000000-0000-0000-0000-000000000001','op-good-device@example.invalid','authenticated','authenticated'),
  ('49000000-0000-0000-0000-000000000002','op-good-monitored@example.invalid','authenticated','authenticated'),
  ('49000000-0000-0000-0000-000000000003','op-unmonitored@example.invalid','authenticated','authenticated'),
  ('49000000-0000-0000-0000-000000000004','op-bad-zone@example.invalid','authenticated','authenticated'),
  ('49000000-0000-0000-0000-000000000005','op-future-source@example.invalid','authenticated','authenticated'),
  ('49000000-0000-0000-0000-000000000006','op-guardian@example.invalid','authenticated','authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, display_name, routine_pattern, consent_data_sharing) VALUES
  ('49000000-0000-0000-0000-000000000001','Operational good device','regular_9to5',true),
  ('49000000-0000-0000-0000-000000000002','Operational monitored','regular_9to5',true),
  ('49000000-0000-0000-0000-000000000003','Operational unmonitored','regular_9to5',false),
  ('49000000-0000-0000-0000-000000000004','Operational bad zone','regular_9to5',true),
  ('49000000-0000-0000-0000-000000000005','Operational future source','regular_9to5',true),
  ('49000000-0000-0000-0000-000000000006','Operational guardian','regular_9to5',false);

INSERT INTO public.user_settings (user_id, sensitivity, timezone, updated_at) VALUES
  ('49000000-0000-0000-0000-000000000001','balanced','UTC','2026-07-27 09:00:00+00'),
  ('49000000-0000-0000-0000-000000000002','balanced','UTC','2026-07-27 09:00:00+00'),
  ('49000000-0000-0000-0000-000000000004','balanced','UTC','2026-07-27 09:00:00+00'),
  ('49000000-0000-0000-0000-000000000005','balanced','UTC','2026-07-27 09:00:00+00');

INSERT INTO public.groups(id,name,created_by)
VALUES ('49000000-0000-0000-0000-000000000010','operational-g',
  '49000000-0000-0000-0000-000000000001');
UPDATE public.group_members
SET monitored=true, watching=true
WHERE group_id='49000000-0000-0000-0000-000000000010'
  AND user_id='49000000-0000-0000-0000-000000000001';
INSERT INTO public.group_members(group_id,user_id,status,monitored,watching) VALUES
  ('49000000-0000-0000-0000-000000000010','49000000-0000-0000-0000-000000000002','active',true,true),
  ('49000000-0000-0000-0000-000000000010','49000000-0000-0000-0000-000000000003','active',false,true);
INSERT INTO public.device_state(user_id) VALUES
  ('49000000-0000-0000-0000-000000000001'),
  ('49000000-0000-0000-0000-000000000003');

CREATE TEMP TABLE op_config AS SELECT '{
  "sessionization":{"gap_minutes":30,"per_user_day_gap_cap":8,"training_horizon_days":35,"intervention_window_minutes":30},
  "context":{"definition_version":"operational-v1","day_partition":"all_days","hour_bucket_minutes":60},
  "personal":{"min_samples":3,"min_support_dates":2,"min_span_days":2,"max_age_days":35,"min_confidence":0.7,"confidence_formula_version":"support_ratio_v1"},
  "cohort":{"min_contributors":10,"min_support_dates":2,"min_span_days":2,"max_age_days":35,"min_confidence":0.5,"contribution_floor_minutes":1,"contribution_ceiling_minutes":600,"confidence_formula_version":"cohort_support_min_v1","algorithm":"trimmed_mean","trim_fraction":0.1},
  "sensitivity_buffers_minutes":{"high":0,"balanced":45,"low":90},
  "candidate_bounds":{"floor_minutes":90,"ceiling_minutes":360},
  "sleep_compensation":{"max_start_delay_minutes":60,"max_wake_advance_minutes":60,"max_wake_delay_minutes":60,"max_update_minutes_per_day":30,"min_positive_nights":2,"lookback_nights":3,"min_late_events_per_night":1,"timezone_tolerance_minutes":30},
  "evaluator":{"contract_version":"adaptive_candidate_v1"},
  "emergency":{"contract_version":"adr0022_v1","neutral_minutes":90,"expected_live_definition_sha256":"c3efc6cc664dc334166a034651ff584d4c7766d80775c3fe3bc012eb97a9b150"}
}'::jsonb AS config;
INSERT INTO public.alert_model_versions(
  id,name,status,config,config_sha256,evidence_version,shadow_enabled_at
)
SELECT '49100000-0000-0000-0000-000000000001','operational-schema-shadow',
  'shadow',config,encode(extensions.digest(config::text,'sha256'),'hex'),
  'canonical-v2','2026-07-01 00:00:00+00' FROM op_config;

CREATE TEMP TABLE capture_one AS
SELECT private.capture_alert_shadow_subject_contexts(
  '49100000-0000-0000-0000-000000000001',
  '2026-07-27 10:00:00+00', 10
) AS result;

-- 26..31 population and canonical as-of provenance.
SELECT is((SELECT (result->>'population_count')::integer FROM capture_one), 1);
SELECT ok(EXISTS(SELECT 1 FROM public.alert_judgment_subject_contexts
  WHERE user_id='49000000-0000-0000-0000-000000000001'));
SELECT ok(NOT EXISTS(SELECT 1 FROM public.alert_judgment_subject_contexts
  WHERE user_id='49000000-0000-0000-0000-000000000002'));
SELECT ok(NOT EXISTS(SELECT 1 FROM public.alert_judgment_subject_contexts
  WHERE user_id='49000000-0000-0000-0000-000000000003'));
SELECT is((SELECT context_state FROM private.adaptive_alert_shadow_subject_context_state
  WHERE user_id='49000000-0000-0000-0000-000000000001'), 'replayable');
SELECT ok((SELECT subject_context_sha256 ~ '^[a-f0-9]{64}$'
  FROM private.adaptive_alert_shadow_subject_context_state
  WHERE user_id='49000000-0000-0000-0000-000000000001'));

UPDATE public.user_settings SET sensitivity='low', updated_at='2026-07-27 10:30:00+00'
WHERE user_id='49000000-0000-0000-0000-000000000001';
SELECT private.capture_alert_shadow_subject_contexts(
  '49100000-0000-0000-0000-000000000001',
  '2026-07-27 11:00:00+00', 10
);
-- 32..34 changed context closes old and opens new instead of rewriting.
SELECT is((SELECT count(*)::integer FROM public.alert_judgment_subject_contexts
  WHERE user_id='49000000-0000-0000-0000-000000000001'), 2);
SELECT is((SELECT count(*)::integer FROM public.alert_judgment_subject_contexts
  WHERE user_id='49000000-0000-0000-0000-000000000001'
    AND effective_to='2026-07-27 11:00:00+00'), 1);
SELECT is((SELECT canonical_sensitivity FROM public.alert_judgment_subject_contexts
  WHERE user_id='49000000-0000-0000-0000-000000000001'
    AND effective_to IS NULL), 'low');

INSERT INTO public.device_state(user_id) VALUES
  ('49000000-0000-0000-0000-000000000004'),
  ('49000000-0000-0000-0000-000000000005');
INSERT INTO public.group_members(group_id,user_id,status,monitored,watching) VALUES
  ('49000000-0000-0000-0000-000000000010','49000000-0000-0000-0000-000000000004','active',true,true),
  ('49000000-0000-0000-0000-000000000010','49000000-0000-0000-0000-000000000005','active',true,true);
UPDATE public.user_settings SET timezone='Bad/Zone'
WHERE user_id='49000000-0000-0000-0000-000000000004';
UPDATE public.user_settings SET updated_at='2026-07-28 12:00:00+00'
WHERE user_id='49000000-0000-0000-0000-000000000005';
SELECT private.capture_alert_shadow_subject_contexts(
  '49100000-0000-0000-0000-000000000001',
  '2026-07-27 12:00:00+00', 10
);
-- 35..36 malformed timezone/future source are stable unreplayable states.
SELECT is((SELECT unreplayable_reason FROM private.adaptive_alert_shadow_subject_context_state
  WHERE user_id='49000000-0000-0000-0000-000000000004'), 'invalid_timezone');
SELECT is((SELECT unreplayable_reason FROM private.adaptive_alert_shadow_subject_context_state
  WHERE user_id='49000000-0000-0000-0000-000000000005'), 'future_source_timestamp');

INSERT INTO public.notifications(id,recipient_id,kind,body,created_at)
VALUES ('49200000-0000-0000-0000-000000000001',
  '49000000-0000-0000-0000-000000000001','self','shadow fixture',
  '2026-07-27 11:30:00+00');
INSERT INTO public.guardianships(id,guardian_id,ward_id,status,created_at)
VALUES ('49200000-0000-0000-0000-000000000002',
  '49000000-0000-0000-0000-000000000006',
  '49000000-0000-0000-0000-000000000001','active',
  '2026-07-27 11:40:00+00');
SELECT private.capture_alert_shadow_interventions(
  '49100000-0000-0000-0000-000000000001','2026-07-27 12:00:00+00',10);
-- 37..39 idempotent minimal intervention copy; Guardian is intervention only.
SELECT ok(EXISTS(SELECT 1 FROM public.alert_intervention_events
  WHERE source_kind='notification' AND source_id='49200000-0000-0000-0000-000000000001'));
SELECT is((private.capture_alert_shadow_interventions(
  '49100000-0000-0000-0000-000000000001','2026-07-27 12:00:00+00',10
)->>'inserted_count')::integer, 0);
SELECT ok(EXISTS(SELECT 1 FROM public.alert_intervention_events
  WHERE kind='guardian_confirmation'
    AND source_id='49200000-0000-0000-0000-000000000002'));

UPDATE public.profiles SET consent_data_sharing=false
WHERE id='49000000-0000-0000-0000-000000000001';
-- 40 consent withdrawal immediately queues cohort invalidation.
SELECT ok(EXISTS(SELECT 1 FROM private.adaptive_alert_shadow_cohort_dirty
  WHERE routine_mode='regular_9to5'));

UPDATE public.alert_judgment_subject_contexts
SET effective_from='2026-06-01 00:00:00+00',
    effective_to='2026-06-02 00:00:00+00',
    settings_updated_at='2026-06-01 00:00:00+00',
    captured_at='2026-06-01 00:00:00+00'
WHERE user_id='49000000-0000-0000-0000-000000000001';
SELECT private.maintain_adaptive_alert_shadow('2026-07-27 12:00:00+00',100);
-- 41 identifiable detail older than 35 days is removed.
SELECT ok(NOT EXISTS(SELECT 1 FROM public.alert_judgment_subject_contexts
  WHERE user_id='49000000-0000-0000-0000-000000000001'
    AND effective_to='2026-06-02 00:00:00+00'));
-- 42 small contributor cells are suppressed and contain no identifying keys.
SELECT ok(EXISTS(
  SELECT 1 FROM private.adaptive_alert_shadow_daily_reports
  WHERE suppressed
    AND contributor_count < 10
    AND NOT (metrics ?| ARRAY['user_id','client_id','event_id','alert_id','occurred_at'])
));

SELECT * FROM finish();
ROLLBACK;
