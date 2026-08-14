BEGIN;
SELECT plan(16);
SELECT has_function('public','activate_passive_checkin_contract',ARRAY['integer','integer','text','time without time zone','time without time zone','text','text'],'explicit live activation RPC exists');
SELECT has_function('public','my_passive_collector_health',ARRAY[]::text[],'subject health RPC exists');
SELECT ok(has_function_privilege('authenticated','public.activate_passive_checkin_contract(integer,integer,text,time without time zone,time without time zone,text,text)','EXECUTE')
 AND NOT has_function_privilege('anon','public.activate_passive_checkin_contract(integer,integer,text,time without time zone,time without time zone,text,text)','EXECUTE'),'activation is authenticated only');
SELECT ok(position('passive_collector_health_summary' in pg_get_functiondef('private.process_passive_checkin_subject(uuid,timestamp with time zone)'::regprocedure))=0,'health remains absent from miss authority');

INSERT INTO auth.users(id,email,aud,role) VALUES
 ('75000000-0000-4000-8000-000000000001','activation@example.invalid','authenticated','authenticated'),
 ('75000000-0000-4000-8000-000000000002','activation-off@example.invalid','authenticated','authenticated')
ON CONFLICT(id) DO NOTHING;
INSERT INTO public.profiles(id,display_name) VALUES
 ('75000000-0000-4000-8000-000000000001','Activation'),
 ('75000000-0000-4000-8000-000000000002','Activation Off')
ON CONFLICT(id) DO NOTHING;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','75000000-0000-4000-8000-000000000002',true);
SELECT is((public.my_passive_collector_health()->>'state'),'off','no bound collector displays Off');
SELECT throws_ok($$ SELECT public.activate_passive_checkin_contract(60,4,'none',NULL,NULL,NULL,'passive-checkin-v1') $$,'55000',NULL,'legacy account cannot silently activate');

SELECT set_config('request.jwt.claim.sub','75000000-0000-4000-8000-000000000001',true);
SELECT public.set_passive_checkin_contract(60,4,'none',NULL,NULL,NULL,'shadow','passive-checkin-v1');
SELECT throws_ok($$ SELECT public.activate_passive_checkin_contract(60,4,'none',NULL,NULL,NULL,'passive-checkin-v1') $$,'55000',NULL,'live activation requires a bound collector');
SELECT public.bind_passive_collector('activation-android','android_native','android-passive-evidence-v1','0.7.0');
SELECT is((public.my_passive_collector_health()->>'state'),'limited','scheduled collector without contact is Limited');
SELECT ok((public.my_passive_collector_health()->>'miss_counting_continues')::boolean,'health explicitly says miss counting continues');
SELECT is((public.my_passive_collector_health()->'devices'->0->>'reason'),'silent','affected device exposes the exact reason');
SELECT throws_ok($$ SELECT public.activate_passive_checkin_contract(60,4,'none',NULL,NULL,NULL,'passive-checkin-v1') $$,'55000',NULL,'fourteen shadow days are enforced');
UPDATE public.passive_monitoring_epochs SET started_at=clock_timestamp()-interval '14 days 1 minute'
WHERE user_id='75000000-0000-4000-8000-000000000001' AND ended_at IS NULL;
SELECT lives_ok($$ SELECT public.activate_passive_checkin_contract(60,4,'none',NULL,NULL,NULL,'passive-checkin-v1') $$,'explicit activation succeeds after shadow gate');
SELECT is((SELECT engine_mode FROM public.passive_checkin_accounts WHERE user_id='75000000-0000-4000-8000-000000000001'),'passive_checkin','server acknowledgement is live truth');
SELECT is((SELECT count(*)::integer FROM public.passive_checkin_contract_versions WHERE user_id='75000000-0000-4000-8000-000000000001'),2,'one activation RPC creates one immutable revision');
SELECT is((SELECT count(*)::integer FROM public.alerts WHERE user_id='75000000-0000-4000-8000-000000000001'),0,'activation itself has no alert side effect');
SELECT throws_ok($$ SELECT public.activate_passive_checkin_contract(19,4,'none',NULL,NULL,NULL,'passive-checkin-v1') $$,'22023',NULL,'activation reuses full contract validation');
SELECT * FROM finish();
ROLLBACK;
