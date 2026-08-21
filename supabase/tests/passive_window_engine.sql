BEGIN;
SELECT plan(35);

SELECT has_table('private','passive_window_transitions','window state changes are audited');
SELECT has_function('private','process_passive_checkin_subject',ARRAY['uuid','timestamp with time zone'],'per-subject evaluator exists');
SELECT has_function('public','process_passive_checkins',ARRAY[]::text[],'failure-isolated wrapper exists');
SELECT has_function('public','my_passive_window_state',ARRAY[]::text[],'subject display state is RPC-only');
SELECT has_function('private','passive_window_arrival_allowance',ARRAY['uuid','timestamp with time zone','timestamp with time zone'],'allowance is historical per window');
SELECT has_function('private','passive_sleep_relaxed',ARRAY['uuid','uuid','timestamp with time zone'],'contract sleep gate is explicit');
SELECT ok(NOT has_table_privilege('authenticated','private.passive_window_transitions','SELECT'),'transition audit is private');
SELECT ok(has_function_privilege('service_role','public.process_passive_checkins()','EXECUTE')
  AND NOT has_function_privilege('authenticated','public.process_passive_checkins()','EXECUTE'),'only the job role evaluates all subjects');
SELECT ok(has_function_privilege('authenticated','public.my_passive_window_state()','EXECUTE')
  AND NOT has_function_privilege('anon','public.my_passive_window_state()','EXECUTE'),'only the subject can read summarized window state');

INSERT INTO auth.users(id,email,aud,role) VALUES
 ('73000000-0000-4000-8000-000000000001','window-live@example.invalid','authenticated','authenticated'),
 ('73000000-0000-4000-8000-000000000002','window-shadow@example.invalid','authenticated','authenticated'),
 ('73000000-0000-4000-8000-000000000003','window-sleep@example.invalid','authenticated','authenticated'),
 ('73000000-0000-4000-8000-000000000004','window-failure@example.invalid','authenticated','authenticated'),
 ('73000000-0000-4000-8000-000000000005','window-good@example.invalid','authenticated','authenticated')
ON CONFLICT(id) DO NOTHING;
INSERT INTO public.profiles(id,display_name) VALUES
 ('73000000-0000-4000-8000-000000000001','Window Live'),
 ('73000000-0000-4000-8000-000000000002','Window Shadow'),
 ('73000000-0000-4000-8000-000000000003','Window Sleep'),
 ('73000000-0000-4000-8000-000000000004','Window Failure'),
 ('73000000-0000-4000-8000-000000000005','Window Good')
ON CONFLICT(id) DO NOTHING;

SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','73000000-0000-4000-8000-000000000001',true);
SELECT public.set_passive_checkin_contract(20,2,'none',NULL,NULL,NULL,'shadow','passive-checkin-v1');
UPDATE public.passive_checkin_accounts SET engine_mode='passive_checkin'
WHERE user_id='73000000-0000-4000-8000-000000000001';
UPDATE public.passive_monitoring_epochs SET started_at='2030-01-01 00:00Z'
WHERE user_id='73000000-0000-4000-8000-000000000001' AND ended_at IS NULL;
UPDATE public.passive_checkin_windows SET window_start='2030-01-01 00:00Z',window_end='2030-01-01 00:20Z',arrival_deadline='2030-01-01 00:20Z'
WHERE user_id='73000000-0000-4000-8000-000000000001';

SELECT lives_ok($$ SELECT private.process_passive_checkin_subject(
  '73000000-0000-4000-8000-000000000001','2030-01-01 01:05Z') $$,'live evaluator processes elapsed windows');
SELECT is((SELECT count(*)::integer FROM public.passive_checkin_windows WHERE user_id='73000000-0000-4000-8000-000000000001'),4,'server creates half-open windows through the current ordinal');
SELECT is((SELECT count(*)::integer FROM public.passive_checkin_windows WHERE user_id='73000000-0000-4000-8000-000000000001' AND outcome='missed'),3,'absence finalizes every due window as missed');
SELECT is((SELECT count(*)::integer FROM public.alerts WHERE user_id='73000000-0000-4000-8000-000000000001' AND status='open'),1,'exactly N misses opens one alert');
SELECT ok((SELECT stage='self' AND cause='silence' AND requires_explicit_unlock FROM public.alerts WHERE user_id='73000000-0000-4000-8000-000000000001' AND status='open'),'passive alert enters the existing funnel at self and requires an answer');
SELECT is((SELECT count(*)::integer FROM private.passive_alert_causal_windows c JOIN public.alerts a ON a.id=c.alert_id WHERE a.user_id='73000000-0000-4000-8000-000000000001'),2,'snapshot contains exactly N windows');
SELECT set_eq(
  $$ SELECT w.ordinal::integer FROM private.passive_alert_causal_windows c JOIN public.passive_checkin_windows w ON w.id=c.window_id JOIN public.alerts a ON a.id=c.alert_id WHERE a.user_id='73000000-0000-4000-8000-000000000001' $$,
  ARRAY[0,1],'delayed evaluation snapshots the first eligibility chain, not later misses');
SELECT is((private.process_passive_checkin_subject('73000000-0000-4000-8000-000000000001','2030-01-01 01:06Z')->>'consecutive_misses')::integer,3,'later misses do not duplicate or reset the chain');
SELECT is((SELECT count(*)::integer FROM public.alerts WHERE user_id='73000000-0000-4000-8000-000000000001'),1,'re-evaluation cannot duplicate an open alert');
SELECT is((SELECT count(*)::integer FROM private.passive_window_transitions WHERE user_id='73000000-0000-4000-8000-000000000001' AND new_outcome='missed'),3,'every miss has a transition audit');

UPDATE public.passive_checkin_windows SET outcome='checked_in',causal_evidence_id=NULL
WHERE user_id='73000000-0000-4000-8000-000000000001' AND ordinal=1;
SELECT is((SELECT status FROM public.alerts WHERE user_id='73000000-0000-4000-8000-000000000001'),'open','late positive history never resolves the alert');
SELECT throws_ok($$ UPDATE private.passive_alert_causal_windows SET ordinal=9 WHERE alert_id=(SELECT id FROM public.alerts WHERE user_id='73000000-0000-4000-8000-000000000001') $$,'55000',NULL,'causal snapshot is immutable');
SELECT is((private.process_passive_checkin_subject('73000000-0000-4000-8000-000000000001','2030-01-01 01:07Z')->>'consecutive_misses')::integer,1,'a corrected checked-in window clears the derived trailing chain');

UPDATE public.alerts SET status='resolved',resolved_at='2030-01-01 01:08Z',resolved_by='73000000-0000-4000-8000-000000000001'
WHERE user_id='73000000-0000-4000-8000-000000000001' AND status='open';
SELECT is((SELECT count(*)::integer FROM public.passive_monitoring_epochs WHERE user_id='73000000-0000-4000-8000-000000000001' AND ended_at IS NULL),1,'explicit resolution leaves exactly one active epoch');
SELECT is((SELECT start_reason FROM public.passive_monitoring_epochs WHERE user_id='73000000-0000-4000-8000-000000000001' AND ended_at IS NULL),'explicit_resolution','explicit answer starts a fresh epoch');
SELECT is((SELECT ordinal::integer FROM public.passive_checkin_windows w JOIN public.passive_checkin_accounts a ON a.active_epoch_id=w.epoch_id WHERE a.user_id='73000000-0000-4000-8000-000000000001'),0,'resolution starts a fresh first window');

-- A report at the window's end belongs to that window, because the end is a
-- rolling deadline rather than a grid boundary: the report moves it.
SELECT set_config('request.jwt.claim.sub','73000000-0000-4000-8000-000000000002',true);
SELECT public.set_passive_checkin_contract(20,2,'none',NULL,NULL,NULL,'shadow','passive-checkin-v1');
UPDATE public.passive_monitoring_epochs SET started_at=clock_timestamp()-interval '20 minutes'
WHERE user_id='73000000-0000-4000-8000-000000000002' AND ended_at IS NULL;
UPDATE public.passive_checkin_windows SET window_start=clock_timestamp()-interval '20 minutes',window_end=clock_timestamp(),arrival_deadline=clock_timestamp()+interval '5 minutes'
WHERE user_id='73000000-0000-4000-8000-000000000002';
CREATE TEMP TABLE boundary_binding(id uuid);
INSERT INTO boundary_binding SELECT (public.bind_passive_collector('boundary-pwa','pwa_browser','pwa-interaction-v1','0.7.0')->>'binding_id')::uuid;
SELECT is(public.record_authenticated_passive_evidence((SELECT id FROM boundary_binding),'73000000-0000-4000-8000-000000000201',0,clock_timestamp(),'direct_device_use','passive-qualification-v1',NULL,'{"interaction":true}'),'inserted','boundary evidence is accepted');
SELECT is((SELECT w.ordinal::integer FROM private.passive_evidence_events e JOIN public.passive_checkin_windows w ON w.id=e.window_id WHERE e.event_id='73000000-0000-4000-8000-000000000201'),0,'evidence at the window end extends that window rather than opening the next');
SELECT is((SELECT count(*)::integer FROM public.alerts WHERE user_id='73000000-0000-4000-8000-000000000002'),0,'shadow evaluation has no alert side effect');

-- Sleep counts misses but defers the alert through post-wake grace.
SELECT set_config('request.jwt.claim.sub','73000000-0000-4000-8000-000000000003',true);
SELECT public.set_passive_checkin_contract(20,1,'configured','23:00','07:00','UTC','shadow','passive-checkin-v1');
UPDATE public.passive_checkin_accounts SET engine_mode='passive_checkin' WHERE user_id='73000000-0000-4000-8000-000000000003';
UPDATE public.passive_monitoring_epochs SET started_at='2030-01-01 23:00Z' WHERE user_id='73000000-0000-4000-8000-000000000003' AND ended_at IS NULL;
UPDATE public.passive_checkin_windows SET window_start='2030-01-01 23:00Z',window_end='2030-01-01 23:20Z',arrival_deadline='2030-01-01 23:20Z' WHERE user_id='73000000-0000-4000-8000-000000000003';
SELECT private.process_passive_checkin_subject('73000000-0000-4000-8000-000000000003','2030-01-02 08:00Z');
SELECT ok(EXISTS(SELECT 1 FROM public.passive_checkin_windows WHERE user_id='73000000-0000-4000-8000-000000000003' AND outcome='missed') AND NOT EXISTS(SELECT 1 FROM public.alerts WHERE user_id='73000000-0000-4000-8000-000000000003'),'sleep/post-wake counts misses but defers alert');
SELECT private.process_passive_checkin_subject('73000000-0000-4000-8000-000000000003','2030-01-02 09:01Z');
SELECT is((SELECT count(*)::integer FROM public.alerts WHERE user_id='73000000-0000-4000-8000-000000000003'),1,'first evaluator after grace opens the deferred alert');

SELECT ok(position('passive_surface_health' in pg_get_functiondef('private.process_passive_checkin_subject(uuid,timestamp with time zone)'::regprocedure))=0,'collector health is mechanically absent from miss and alert authority');
SELECT ok(position('engine_mode=''passive_checkin''' in pg_get_functiondef('public.process_escalations()'::regprocedure))>0,'legacy inactivity creation explicitly excludes live passive accounts');
SELECT ok(position('失去联系' in pg_get_functiondef('private.notify_stage(uuid,uuid,text)'::regprocedure))>0
  AND position('危险' in pg_get_functiondef('private.notify_stage(uuid,uuid,text)'::regprocedure))=0,'passive group/community copy says lost contact, never danger');

-- One broken subject cannot prevent the next account from finalizing.
SELECT set_config('request.jwt.claim.sub','73000000-0000-4000-8000-000000000004',true);
SELECT public.set_passive_checkin_contract(20,2,'none',NULL,NULL,NULL,'shadow','passive-checkin-v1');
SELECT set_config('request.jwt.claim.sub','73000000-0000-4000-8000-000000000005',true);
SELECT public.set_passive_checkin_contract(20,2,'none',NULL,NULL,NULL,'shadow','passive-checkin-v1');
UPDATE public.passive_monitoring_epochs SET started_at=clock_timestamp()-interval '45 minutes'
WHERE user_id IN('73000000-0000-4000-8000-000000000004','73000000-0000-4000-8000-000000000005') AND ended_at IS NULL;
UPDATE public.passive_checkin_windows w SET window_start=e.started_at,
  window_end=e.started_at+interval '20 minutes',arrival_deadline=e.started_at+interval '20 minutes'
FROM public.passive_monitoring_epochs e WHERE e.id=w.epoch_id
  AND w.user_id IN('73000000-0000-4000-8000-000000000004','73000000-0000-4000-8000-000000000005');
CREATE FUNCTION pg_temp.reject_one_passive_subject() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.user_id='73000000-0000-4000-8000-000000000004' THEN RAISE EXCEPTION 'fixture failure'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER passive_window_fixture_failure BEFORE INSERT ON public.passive_checkin_windows
FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_one_passive_subject();
SELECT public.process_passive_checkins();
DROP TRIGGER passive_window_fixture_failure ON public.passive_checkin_windows;
SELECT ok(EXISTS(SELECT 1 FROM private.job_failures WHERE job_name='process_passive_checkins' AND subject_id='73000000-0000-4000-8000-000000000004'),'subject failure is recorded');
SELECT ok(EXISTS(SELECT 1 FROM public.passive_checkin_windows WHERE user_id='73000000-0000-4000-8000-000000000005' AND outcome='missed'),'a later subject still finalizes after another account fails');

SELECT * FROM finish();
ROLLBACK;
