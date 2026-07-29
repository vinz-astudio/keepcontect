-- ADR-0028 scheduler-off operational cycle and fail-closed dispatcher.
BEGIN;
SELECT plan(46);

-- 1..4 locked operational worker surface.
SELECT has_function('private','record_alert_judgment_shadow_operational',
  ARRAY['uuid','timestamp with time zone','integer']);
SELECT has_function('private','run_adaptive_alert_shadow_cycle',
  ARRAY['uuid','timestamp with time zone']);
SELECT has_function('private','dispatch_adaptive_alert_shadow_cycle',ARRAY[]::text[]);
SELECT has_function('private','disable_adaptive_alert_shadow',ARRAY['text']);

-- 5..6 state/run objects.
SELECT has_table('private','adaptive_alert_shadow_user_state',
  'operational latest user state exists');
SELECT has_table('private','adaptive_alert_shadow_cycle_runs',
  'deidentified cycle runs exist');

-- 7..8 default dispatcher is a strict no-op.
SELECT is((SELECT enabled FROM private.adaptive_alert_shadow_runtime_config WHERE singleton),false);
SELECT lives_ok($$SELECT private.dispatch_adaptive_alert_shadow_cycle()$$);

-- 9..12 operational workers are owner-only.
SELECT is(has_function_privilege('authenticated',
  'private.record_alert_judgment_shadow_operational(uuid,timestamptz,integer)','EXECUTE'),false);
SELECT is(has_function_privilege('authenticated',
  'private.run_adaptive_alert_shadow_cycle(uuid,timestamptz)','EXECUTE'),false);
SELECT is(has_function_privilege('service_role',
  'private.dispatch_adaptive_alert_shadow_cycle()','EXECUTE'),false);
SELECT is(has_function_privilege('service_role',
  'private.disable_adaptive_alert_shadow(text)','EXECUTE'),false);

CREATE TEMP TABLE cycle_source AS
SELECT pg_get_functiondef(
  'private.run_adaptive_alert_shadow_cycle(uuid,timestamptz)'::regprocedure
) || pg_get_functiondef(
  'private.dispatch_adaptive_alert_shadow_cycle()'::regprocedure
) || pg_get_functiondef(
  'private.record_alert_judgment_shadow_operational(uuid,timestamptz,integer)'::regprocedure
) AS source;
-- 13..20 mechanical guardrails in executable source.
SELECT ok((SELECT source ~* 'pg_try_advisory_xact_lock' FROM cycle_source));
SELECT ok((SELECT source ~* 'pg_stat_xact_user_tables' FROM cycle_source));
SELECT ok((SELECT source ~* 'statement_timeout' FROM cycle_source));
SELECT ok((SELECT source ~* 'lock_timeout' FROM cycle_source));
SELECT ok((SELECT source ~* 'public\.alerts' FROM cycle_source));
SELECT ok((SELECT source ~* 'public\.alert_events' FROM cycle_source));
SELECT ok((SELECT source ~* 'public\.notifications' FROM cycle_source));
SELECT ok((SELECT source ~* '36' AND source ~* 'interval ''1 hour''' FROM cycle_source));

-- Fixture population and canonical shadow version.
INSERT INTO auth.users(id,email,aud,role) VALUES
  ('49300000-0000-0000-0000-000000000001','cycle-device@example.invalid','authenticated','authenticated'),
  ('49300000-0000-0000-0000-000000000002','cycle-monitored@example.invalid','authenticated','authenticated')
ON CONFLICT (id) DO NOTHING;
UPDATE public.profiles SET routine_pattern='regular_9to5',consent_data_sharing=true
WHERE id IN ('49300000-0000-0000-0000-000000000001','49300000-0000-0000-0000-000000000002');
UPDATE public.user_settings SET sensitivity='balanced',timezone='UTC',
  updated_at='2026-07-27 09:00:00+00'
WHERE user_id IN ('49300000-0000-0000-0000-000000000001','49300000-0000-0000-0000-000000000002');
INSERT INTO public.device_state(user_id) VALUES
  ('49300000-0000-0000-0000-000000000001');
INSERT INTO public.groups(id,name,created_by) VALUES(
  '49300000-0000-0000-0000-000000000010','cycle-g',
  '49300000-0000-0000-0000-000000000001');
UPDATE public.group_members
SET monitored=true, watching=true
WHERE group_id='49300000-0000-0000-0000-000000000010'
  AND user_id='49300000-0000-0000-0000-000000000001';
INSERT INTO public.group_members(group_id,user_id,status,monitored,watching) VALUES
  ('49300000-0000-0000-0000-000000000010',
   '49300000-0000-0000-0000-000000000002','active',true,true);

CREATE TEMP TABLE cycle_config AS SELECT '{
  "sessionization":{"gap_minutes":30,"per_user_day_gap_cap":8,"training_horizon_days":35,"intervention_window_minutes":30},
  "context":{"definition_version":"cycle-v1","day_partition":"all_days","hour_bucket_minutes":60},
  "personal":{"min_samples":3,"min_support_dates":2,"min_span_days":2,"max_age_days":35,"min_confidence":0.7,"confidence_formula_version":"support_ratio_v1"},
  "cohort":{"min_contributors":10,"min_support_dates":2,"min_span_days":2,"max_age_days":35,"min_confidence":0.5,"contribution_floor_minutes":1,"contribution_ceiling_minutes":600,"confidence_formula_version":"cohort_support_min_v1","algorithm":"trimmed_mean","trim_fraction":0.1},
  "sensitivity_buffers_minutes":{"high":0,"balanced":45,"low":90},
  "candidate_bounds":{"floor_minutes":90,"ceiling_minutes":360},
  "sleep_compensation":{"max_start_delay_minutes":60,"max_wake_advance_minutes":60,"max_wake_delay_minutes":60,"max_update_minutes_per_day":30,"min_positive_nights":2,"lookback_nights":3,"min_late_events_per_night":1,"timezone_tolerance_minutes":30},
  "evaluator":{"contract_version":"adaptive_candidate_v1"},
  "emergency":{"contract_version":"adr0022_v1","neutral_minutes":90,"expected_live_definition_sha256":"1907d59473d274d46a0e8e0b9ce8027037b4494b0dddf073cb46abf67db92e21"}
}'::jsonb AS config;
INSERT INTO public.alert_model_versions(
  id,name,status,config,config_sha256,evidence_version,shadow_enabled_at
)
SELECT '49400000-0000-0000-0000-000000000001','operational-cycle-shadow',
  'shadow',config,encode(extensions.digest(config::text,'sha256'),'hex'),
  'canonical-v2','2026-07-01 00:00:00+00' FROM cycle_config;

-- 21 direct cycle fails closed while runtime is disabled.
SELECT is(private.run_adaptive_alert_shadow_cycle(
  '49400000-0000-0000-0000-000000000001','2026-07-27 10:00:00+00'
)->>'status','disabled');

UPDATE private.adaptive_alert_shadow_runtime_config
SET version_id='49400000-0000-0000-0000-000000000001',
  enabled=true,accept_coverage_leases=false,consecutive_failures=2,
  last_failure_code='ordinary_failure';
CREATE TEMP TABLE live_before AS SELECT
  (SELECT count(*) FROM public.alerts) alerts,
  (SELECT count(*) FROM public.alert_events) events,
  (SELECT count(*) FROM public.notifications) notifications;
CREATE TEMP TABLE cycle_result AS SELECT private.run_adaptive_alert_shadow_cycle(
  '49400000-0000-0000-0000-000000000001','2026-07-27 10:00:00+00'
) AS result;

-- 22..32 bounded evaluation and zero live DML.
SELECT is((SELECT result->>'status' FROM cycle_result),'completed');
SELECT is((SELECT (result->>'population_count')::integer FROM cycle_result),1);
SELECT is((SELECT (result->>'evaluated_count')::integer FROM cycle_result),1);
SELECT is((SELECT count(*)::integer FROM private.adaptive_alert_shadow_cycle_runs),1);
SELECT is((SELECT count(*)::integer FROM private.adaptive_alert_shadow_user_state),1);
SELECT is((SELECT count(*)::integer FROM public.alerts),
  (SELECT alerts::integer FROM live_before));
SELECT is((SELECT count(*)::integer FROM public.alert_events),
  (SELECT events::integer FROM live_before));
SELECT is((SELECT count(*)::integer FROM public.notifications),
  (SELECT notifications::integer FROM live_before));
SELECT is(private.run_adaptive_alert_shadow_cycle(
  '49400000-0000-0000-0000-000000000001','2026-07-27 10:00:00+00'
)->>'status','duplicate');
SELECT is((SELECT count(*)::integer FROM private.adaptive_alert_shadow_cycle_runs),1);
SELECT ok((SELECT NOT (metrics ?| ARRAY['user_id','client_id','event_id','alert_id','raw_error'])
  FROM private.adaptive_alert_shadow_cycle_runs LIMIT 1));

-- 33 dispatcher success resets prior ordinary failures.
SELECT lives_ok($$SELECT private.dispatch_adaptive_alert_shadow_cycle()$$);
SELECT is((SELECT consecutive_failures FROM private.adaptive_alert_shadow_runtime_config
  WHERE singleton),0);

-- 35..38 explicit kill switch uses fixed codes and stores no raw exception.
SELECT lives_ok($$SELECT private.disable_adaptive_alert_shadow('shadow_live_write_detected')$$);
SELECT is((SELECT enabled FROM private.adaptive_alert_shadow_runtime_config WHERE singleton),false);
SELECT is((SELECT last_failure_code FROM private.adaptive_alert_shadow_runtime_config
  WHERE singleton),'shadow_live_write_detected');
SELECT ok((SELECT last_failure_code !~* '(user|select|insert|update|delete|exception)'
  FROM private.adaptive_alert_shadow_runtime_config WHERE singleton));

-- 39 bounded max population constraint.
SELECT throws_ok($$UPDATE private.adaptive_alert_shadow_runtime_config
  SET max_population=10001 WHERE singleton$$);

-- 40..43 validation surfaces are present.
SELECT ok((SELECT source ~* 'config_sha256' FROM cycle_source));
SELECT ok((SELECT source ~* 'relrowsecurity|has_table_privilege|acl' FROM cycle_source));
SELECT ok((SELECT source ~* 'pg_publication_tables' FROM cycle_source));
SELECT ok((SELECT source ~* 'shadow_detail_budget_exceeded' FROM cycle_source));

-- 44..45 base creates no shadow Cron and preserves the live job.
SELECT is((SELECT count(*)::integer FROM cron.job
  WHERE jobname LIKE 'adaptive-alert-shadow-%'),0);
SELECT ok(NOT EXISTS(SELECT 1 FROM cron.job
  WHERE jobname='adaptive-alert-shadow-cycle-v1'
     OR jobname='adaptive-alert-shadow-maintenance-v1'));

-- 46 operational code never invokes live escalation/notification functions.
SELECT ok((SELECT source !~* '(process_escalations|notify_stage|push-dispatch)'
  FROM cycle_source));

SELECT * FROM finish();
ROLLBACK;
