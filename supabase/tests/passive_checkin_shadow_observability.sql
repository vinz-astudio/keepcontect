BEGIN;
SELECT plan(25);
SELECT has_table('private','passive_shadow_candidates','shadow decisions are durable');
SELECT has_table('private','passive_checkin_runtime_control','global runtime control exists');
SELECT has_function('private','passive_checkin_shadow_report',ARRAY['timestamp with time zone','timestamp with time zone'],'aggregate report exists');
SELECT has_function('private','set_passive_checkin_global_kill_switch',ARRAY['boolean','text'],'kill switch setter exists');
SELECT ok(has_function_privilege('service_role','private.passive_checkin_shadow_report(timestamp with time zone,timestamp with time zone)','EXECUTE')
 AND NOT has_function_privilege('authenticated','private.passive_checkin_shadow_report(timestamp with time zone,timestamp with time zone)','EXECUTE'),'report is service-only');
SELECT ok(NOT has_table_privilege('authenticated','private.passive_shadow_candidates','SELECT'),'raw replay records are private');

INSERT INTO auth.users(id,email,aud,role) VALUES('76000000-0000-4000-8000-000000000001','shadow-observe@example.invalid','authenticated','authenticated') ON CONFLICT(id) DO NOTHING;
INSERT INTO public.profiles(id,display_name) VALUES('76000000-0000-4000-8000-000000000001','Shadow Observe') ON CONFLICT(id) DO NOTHING;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','76000000-0000-4000-8000-000000000001',true);
SELECT public.set_passive_checkin_contract(20,2,'none',NULL,NULL,NULL,'shadow','passive-checkin-v1');
SELECT public.bind_passive_collector('shadow-observe-pwa','pwa_browser','pwa-interaction-v1','0.7.0');
UPDATE public.passive_monitoring_epochs SET started_at=clock_timestamp()-interval '65 minutes'
WHERE user_id='76000000-0000-4000-8000-000000000001' AND ended_at IS NULL;
UPDATE public.passive_checkin_windows w SET window_start=e.started_at,window_end=e.started_at+interval '20 minutes',arrival_deadline=e.started_at+interval '25 minutes'
FROM public.passive_monitoring_epochs e WHERE w.epoch_id=e.id AND w.user_id='76000000-0000-4000-8000-000000000001';
CREATE TEMP TABLE notice_before AS SELECT count(*)::integer total FROM public.notifications;
SELECT private.process_passive_checkin_subject('76000000-0000-4000-8000-000000000001',clock_timestamp());
SELECT is((SELECT count(*)::integer FROM private.passive_shadow_candidates WHERE user_id='76000000-0000-4000-8000-000000000001' AND decision='would_open'),1,'shadow records the first would-open decision');
SELECT is((SELECT cardinality(causal_window_ids) FROM private.passive_shadow_candidates WHERE user_id='76000000-0000-4000-8000-000000000001' AND decision='would_open'),2,'shadow replay pins exactly N causal windows');
SELECT is((SELECT count(*)::integer FROM public.alerts WHERE user_id='76000000-0000-4000-8000-000000000001'),0,'shadow never inserts an alert');
SELECT is((SELECT count(*)::integer FROM public.notifications),(SELECT total FROM notice_before),'shadow never inserts a notification');
SELECT private.process_passive_checkin_subject('76000000-0000-4000-8000-000000000001',clock_timestamp()+interval '25 minutes');
SELECT ok(EXISTS(SELECT 1 FROM private.passive_shadow_candidates WHERE user_id='76000000-0000-4000-8000-000000000001' AND decision='duplicate_suppressed'),'later chain windows record duplicate suppression');
SELECT throws_ok($$ UPDATE private.passive_shadow_candidates SET decision='would_open' WHERE decision='duplicate_suppressed' $$,'55000',NULL,'shadow decisions are immutable');

CREATE TEMP TABLE shadow_report(payload jsonb);
INSERT INTO shadow_report SELECT private.passive_checkin_shadow_report(clock_timestamp()-interval '1 day',clock_timestamp()+interval '1 day');
SELECT is((SELECT payload->>'schema_version' FROM shadow_report),'passive-shadow-report-v1','report schema is versioned');
SELECT ok((SELECT payload ?& ARRAY['window_counts','overdue_pending','arrival_gap_minutes','late_corrections','ingest_incidents','chain_transitions','passive_alert_opens','duplicate_suppressions','recommendation_changes','job_failures','cohorts','hard_invariants','global_kill_switch'] FROM shadow_report),'report exposes the required aggregate families');
SELECT is((SELECT payload->'cohorts'->0->>'subjects' FROM shadow_report),'1','cohort report contains only an aggregate subject count');
SELECT ok((SELECT NOT payload::text LIKE '%76000000-0000-4000-8000-000000000001%' AND NOT payload::text LIKE '%shadow-observe-pwa%' FROM shadow_report),'report leaks no subject or device identifier');
SELECT is((SELECT (value)::integer FROM shadow_report,jsonb_each_text(payload->'hard_invariants') ORDER BY value::integer DESC LIMIT 1),0,'hard-invariant alarms are zero for valid data');

SELECT throws_ok($$ SELECT private.set_passive_checkin_global_kill_switch(true,NULL) $$,'22023',NULL,'active kill switch requires a reason');
UPDATE public.passive_checkin_accounts SET engine_mode='passive_checkin' WHERE user_id='76000000-0000-4000-8000-000000000001';
SELECT private.set_passive_checkin_global_kill_switch(true,'operator safety stop');
SELECT ok((SELECT kill_switch_active FROM public.passive_checkin_accounts WHERE user_id='76000000-0000-4000-8000-000000000001'),'global stop marks affected account Limited');
SELECT is((public.my_passive_collector_health()->>'state'),'limited','subject health displays Limited during global stop');
SELECT is((public.my_passive_collector_health()->>'global_reason'),'operator safety stop','health explains the global reason');
SELECT private.process_passive_checkin_subject('76000000-0000-4000-8000-000000000001',clock_timestamp()+interval '2 hours');
SELECT is((SELECT count(*)::integer FROM public.alerts WHERE user_id='76000000-0000-4000-8000-000000000001'),0,'kill switch prevents new passive alerts without legacy fallback');
SELECT ok(EXISTS(SELECT 1 FROM public.passive_checkin_windows WHERE user_id='76000000-0000-4000-8000-000000000001' AND outcome='missed'),'kill switch does not rewrite or pause completed window truth');
UPDATE public.passive_checkin_accounts SET engine_mode='shadow' WHERE user_id='76000000-0000-4000-8000-000000000001';
SELECT throws_ok($$ UPDATE public.passive_checkin_accounts SET engine_mode='passive_checkin' WHERE user_id='76000000-0000-4000-8000-000000000001' $$,'55000',NULL,'new live activation fails while global stop is active');
SELECT private.set_passive_checkin_global_kill_switch(false,NULL);
SELECT ok(NOT (SELECT kill_switch_active FROM public.passive_checkin_accounts WHERE user_id='76000000-0000-4000-8000-000000000001'),'operator can clear the switch without rewriting history');
SELECT * FROM finish();
ROLLBACK;
