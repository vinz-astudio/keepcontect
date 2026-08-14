BEGIN;
SELECT plan(25);

SELECT has_table('public','passive_checkin_recommendations','recommendation provenance is durable');
SELECT has_function('private','rebuild_passive_checkin_recommendation',ARRAY['uuid','timestamp with time zone'],'service learner exists');
SELECT has_function('public','my_passive_checkin_recommendation',ARRAY[]::text[],'subject summary exists');
SELECT ok(NOT has_table_privilege('authenticated','public.passive_checkin_recommendations','SELECT'),'raw provenance is not client-readable');
SELECT ok(has_function_privilege('service_role','private.rebuild_passive_checkin_recommendation(uuid,timestamp with time zone)','EXECUTE')
  AND NOT has_function_privilege('authenticated','private.rebuild_passive_checkin_recommendation(uuid,timestamp with time zone)','EXECUTE'),'only service role can rebuild');
SELECT ok(has_function_privilege('authenticated','public.my_passive_checkin_recommendation()','EXECUTE')
  AND NOT has_function_privilege('anon','public.my_passive_checkin_recommendation()','EXECUTE'),'only an authenticated subject can read its summary');
SELECT ok(position('passive_surface_health_intervals' in pg_get_functiondef('private.rebuild_passive_checkin_recommendation(uuid,timestamp with time zone)'::regprocedure))>0
  AND position('passive_checkin_windows' in pg_get_functiondef('private.rebuild_passive_checkin_recommendation(uuid,timestamp with time zone)'::regprocedure))>0
  AND position('public.alerts' in pg_get_functiondef('private.rebuild_passive_checkin_recommendation(uuid,timestamp with time zone)'::regprocedure))>0,'required exclusion sources are explicit');
SELECT ok(position('UPDATE public.passive_checkin_accounts' in pg_get_functiondef('private.rebuild_passive_checkin_recommendation(uuid,timestamp with time zone)'::regprocedure))=0
  AND position('UPDATE public.passive_checkin_windows' in pg_get_functiondef('private.rebuild_passive_checkin_recommendation(uuid,timestamp with time zone)'::regprocedure))=0
  AND position('INSERT INTO public.alerts' in pg_get_functiondef('private.rebuild_passive_checkin_recommendation(uuid,timestamp with time zone)'::regprocedure))=0,'learner has no contract, window, or alert authority');

INSERT INTO auth.users(id,email,aud,role) VALUES
 ('74000000-0000-4000-8000-000000000001','recommend-default@example.invalid','authenticated','authenticated'),
 ('74000000-0000-4000-8000-000000000002','recommend-android@example.invalid','authenticated','authenticated')
ON CONFLICT(id) DO NOTHING;
INSERT INTO public.profiles(id,display_name) VALUES
 ('74000000-0000-4000-8000-000000000001','Recommendation Default'),
 ('74000000-0000-4000-8000-000000000002','Recommendation Android')
ON CONFLICT(id) DO NOTHING;

SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','74000000-0000-4000-8000-000000000001',true);
SELECT public.set_passive_checkin_contract(120,2,'none',NULL,NULL,NULL,'shadow','passive-checkin-v1');
CREATE TEMP TABLE default_binding(id uuid);
INSERT INTO default_binding SELECT (public.bind_passive_collector('recommend-pwa','pwa_browser','pwa-interaction-v1','0.7.0')->>'binding_id')::uuid;
CREATE TEMP TABLE authority_before AS
SELECT
 (SELECT count(*) FROM public.passive_checkin_contract_versions WHERE user_id='74000000-0000-4000-8000-000000000001') contracts,
 (SELECT count(*) FROM public.passive_checkin_windows WHERE user_id='74000000-0000-4000-8000-000000000001') windows,
 (SELECT count(*) FROM public.alerts WHERE user_id='74000000-0000-4000-8000-000000000001') alerts;
SELECT lives_ok($$ SELECT private.rebuild_passive_checkin_recommendation('74000000-0000-4000-8000-000000000001','2026-08-15 12:00Z') $$,'insufficient history builds a safe default');
SELECT is((SELECT reference_minutes FROM public.passive_checkin_recommendations WHERE user_id='74000000-0000-4000-8000-000000000001'),360,'insufficient history defaults to six hours');
SELECT is((SELECT source_confidence FROM public.passive_checkin_recommendations WHERE user_id='74000000-0000-4000-8000-000000000001'),'insufficient','default is labelled insufficient');
SELECT ok((SELECT proposed_interval_minutes=360 AND proposed_consecutive_misses=2 AND proposed_horizon_minutes=720
  AND platform_floor_basis=ARRAY['pwa_browser'] FROM public.passive_checkin_recommendations
  WHERE user_id='74000000-0000-4000-8000-000000000001'),'PWA floors map R to D=360, N=2, H=720');
SELECT is((SELECT expected_interruptions_per_day FROM public.passive_checkin_recommendations WHERE user_id='74000000-0000-4000-8000-000000000001'),2::numeric,'interruption estimate is explicit');
SELECT ok((SELECT contracts=(SELECT count(*) FROM public.passive_checkin_contract_versions WHERE user_id='74000000-0000-4000-8000-000000000001')
  AND windows=(SELECT count(*) FROM public.passive_checkin_windows WHERE user_id='74000000-0000-4000-8000-000000000001')
  AND alerts=(SELECT count(*) FROM public.alerts WHERE user_id='74000000-0000-4000-8000-000000000001') FROM authority_before),'rebuild leaves authoritative state unchanged');
SELECT throws_ok($$ UPDATE public.passive_checkin_recommendations SET reference_minutes=5 WHERE user_id='74000000-0000-4000-8000-000000000001' $$,'55000',NULL,'recommendation rows are immutable');

SELECT set_config('request.jwt.claim.sub','74000000-0000-4000-8000-000000000002',true);
SELECT public.set_passive_checkin_contract(60,4,'none',NULL,NULL,NULL,'shadow','passive-checkin-v1');
CREATE TEMP TABLE android_fixture(binding_id uuid,epoch_id uuid,window_id uuid);
INSERT INTO android_fixture
SELECT (bound->>'binding_id')::uuid,a.active_epoch_id,w.id
FROM (SELECT public.bind_passive_collector('recommend-android','android_native','android-passive-evidence-v1','0.7.0') bound) b
JOIN public.passive_checkin_accounts a ON a.user_id='74000000-0000-4000-8000-000000000002'
JOIN public.passive_checkin_windows w ON w.epoch_id=a.active_epoch_id AND w.ordinal=0;
UPDATE public.passive_monitoring_epochs SET started_at='2026-08-01 00:00Z'
WHERE user_id='74000000-0000-4000-8000-000000000002' AND ended_at IS NULL;
UPDATE public.passive_checkin_windows SET window_start='2026-08-01 00:00Z',window_end='2026-08-15 00:00Z',arrival_deadline='2026-08-15 00:35Z',outcome='missed',finalized_at='2026-08-15 00:35Z'
WHERE id=(SELECT window_id FROM android_fixture);

INSERT INTO private.passive_evidence_events(
 user_id,binding_id,epoch_id,window_id,event_id,collector_sequence,collector_time_epoch,
 observed_at,evidence_class,qualification_policy_version,collector_contract,client_version,
 qualification_facts,payload_sha256
)
SELECT '74000000-0000-4000-8000-000000000002',f.binding_id,f.epoch_id,f.window_id,v.event_id,v.seq,1,
 v.observed_at,'direct_device_use','passive-qualification-v1','android-passive-evidence-v1','0.7.0',
 '{"interaction":true}',repeat(to_hex(v.seq+1),64)
FROM android_fixture f CROSS JOIN (VALUES
 ('74000000-0000-4000-8000-000000000101'::uuid,0,'2026-08-10 08:00Z'::timestamptz),
 ('74000000-0000-4000-8000-000000000102'::uuid,1,'2026-08-10 10:00Z'::timestamptz),
 ('74000000-0000-4000-8000-000000000103'::uuid,2,'2026-08-11 08:00Z'::timestamptz),
 ('74000000-0000-4000-8000-000000000104'::uuid,3,'2026-08-11 11:00Z'::timestamptz),
 ('74000000-0000-4000-8000-000000000105'::uuid,4,'2026-08-12 08:00Z'::timestamptz),
 ('74000000-0000-4000-8000-000000000106'::uuid,5,'2026-08-12 12:00Z'::timestamptz)
) v(event_id,seq,observed_at);
INSERT INTO private.passive_surface_health_intervals(user_id,binding_id,started_at,ended_at,reason)
SELECT '74000000-0000-4000-8000-000000000002',binding_id,v.started_at,v.ended_at,'silent'
FROM android_fixture CROSS JOIN (VALUES
 ('2026-08-10 10:01Z'::timestamptz,'2026-08-11 08:00Z'::timestamptz),
 ('2026-08-11 11:01Z'::timestamptz,'2026-08-12 08:00Z'::timestamptz)
) v(started_at,ended_at);
SELECT private.rebuild_passive_checkin_recommendation('74000000-0000-4000-8000-000000000002','2026-08-15 12:00Z');
SELECT ok((SELECT eligible_episode_count=3 AND evidence_days=3 AND excluded_counts->>'surface_health'='2'
  FROM public.passive_checkin_recommendations WHERE user_id='74000000-0000-4000-8000-000000000002' AND revision_number=1),'health-crossing gaps are excluded with provenance counts');
SELECT ok((SELECT reference_minutes=240 AND source_confidence='low' AND proposed_interval_minutes=60
  AND proposed_consecutive_misses=4 AND proposed_horizon_minutes=240
  FROM public.passive_checkin_recommendations WHERE user_id='74000000-0000-4000-8000-000000000002' AND revision_number=1),'three-day history yields the largest B=1 eligible gap');

INSERT INTO private.passive_evidence_events(
 user_id,binding_id,epoch_id,window_id,event_id,collector_sequence,collector_time_epoch,
 observed_at,evidence_class,qualification_policy_version,collector_contract,client_version,qualification_facts,payload_sha256
)
SELECT '74000000-0000-4000-8000-000000000002',f.binding_id,f.epoch_id,f.window_id,v.event_id,v.seq,1,
 v.observed_at,'direct_device_use','passive-qualification-v1','android-passive-evidence-v1','0.7.0','{"interaction":true}',repeat(to_hex(v.seq+1),64)
FROM android_fixture f CROSS JOIN (VALUES
 ('74000000-0000-4000-8000-000000000107'::uuid,6,'2026-08-13 08:00Z'::timestamptz),
 ('74000000-0000-4000-8000-000000000108'::uuid,7,'2026-08-13 18:00Z'::timestamptz)
) v(event_id,seq,observed_at);
INSERT INTO private.passive_surface_health_intervals(user_id,binding_id,started_at,ended_at,reason)
SELECT '74000000-0000-4000-8000-000000000002',binding_id,'2026-08-12 12:01Z','2026-08-13 08:00Z','silent' FROM android_fixture;
SELECT private.rebuild_passive_checkin_recommendation('74000000-0000-4000-8000-000000000002','2026-08-15 12:00Z');
SELECT is((SELECT reference_minutes FROM public.passive_checkin_recommendations WHERE user_id='74000000-0000-4000-8000-000000000002' AND revision_number=2),240,'one >150 percent outlier is clamped to the prior reference');

INSERT INTO private.passive_evidence_events(
 user_id,binding_id,epoch_id,window_id,event_id,collector_sequence,collector_time_epoch,
 observed_at,evidence_class,qualification_policy_version,collector_contract,client_version,qualification_facts,payload_sha256
)
SELECT '74000000-0000-4000-8000-000000000002',f.binding_id,f.epoch_id,f.window_id,v.event_id,v.seq,1,
 v.observed_at,'direct_device_use','passive-qualification-v1','android-passive-evidence-v1','0.7.0','{"interaction":true}',repeat(to_hex(v.seq+1),64)
FROM android_fixture f CROSS JOIN (VALUES
 ('74000000-0000-4000-8000-000000000109'::uuid,8,'2026-08-14 08:00Z'::timestamptz),
 ('74000000-0000-4000-8000-000000000110'::uuid,9,'2026-08-14 17:30Z'::timestamptz)
) v(event_id,seq,observed_at);
INSERT INTO private.passive_surface_health_intervals(user_id,binding_id,started_at,ended_at,reason)
SELECT '74000000-0000-4000-8000-000000000002',binding_id,'2026-08-13 18:01Z','2026-08-14 08:00Z','silent' FROM android_fixture;
SELECT private.rebuild_passive_checkin_recommendation('74000000-0000-4000-8000-000000000002','2026-08-15 12:00Z');
SELECT is((SELECT reference_minutes FROM public.passive_checkin_recommendations WHERE user_id='74000000-0000-4000-8000-000000000002' AND revision_number=3),600,'two comparable outliers on different dates admit the larger reference');
SELECT ok((SELECT cardinality(eligible_episode_ids)=5 AND eligible_episode_sha256~'^[a-f0-9]{64}$'
  FROM public.passive_checkin_recommendations WHERE user_id='74000000-0000-4000-8000-000000000002' AND revision_number=3),'eligible episode IDs and digest pin the learner input');

SELECT is((public.my_passive_checkin_recommendation()->>'reference_minutes')::integer,600,'subject RPC returns latest own recommendation');
SELECT set_config('request.jwt.claim.sub','74000000-0000-4000-8000-000000000001',true);
SELECT is((public.my_passive_checkin_recommendation()->>'reference_minutes')::integer,360,'subject RPC cannot cross accounts');

INSERT INTO public.passive_checkin_recommendations(
 user_id,revision_number,eligible_episode_sha256,eligible_episode_count,evidence_days,source_confidence,
 reference_minutes,proposed_interval_minutes,proposed_consecutive_misses,proposed_horizon_minutes,
 platform_d_floor_minutes,platform_h_floor_minutes,platform_floor_basis,expected_interruptions_per_day,generated_at
) VALUES('74000000-0000-4000-8000-000000000001',99,repeat('a',64),0,0,'insufficient',360,360,2,720,360,720,ARRAY['pwa_browser'],2,clock_timestamp()-interval '91 days');
SELECT ok((private.prune_passive_checkin_data()->>'recommendations')::integer>=1,'shared cleanup removes recommendations after 90 days');
SELECT is((SELECT count(*)::integer FROM public.passive_checkin_recommendations WHERE user_id='74000000-0000-4000-8000-000000000001' AND revision_number=99),0,'expired recommendation is deleted');
SELECT is((SELECT count(*)::integer FROM cron.job WHERE command ILIKE '%rebuild_passive_checkin_recommendation%'),0,'package 7 does not schedule production jobs');

SELECT * FROM finish();
ROLLBACK;
