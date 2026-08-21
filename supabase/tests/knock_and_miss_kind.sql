-- The server asks before it judges, and it says which silence it found.
BEGIN;
SELECT plan(19);

SELECT has_table('private','passive_knock_attempts','knocks are recorded');
SELECT ok(NOT has_table_privilege('authenticated','private.passive_knock_attempts','SELECT'),
  'knock history is private');
SELECT ok(has_function_privilege('service_role','public.passive_knock_targets()','EXECUTE')
  AND NOT has_function_privilege('authenticated','public.passive_knock_targets()','EXECUTE'),
  'only the job role learns who is near a deadline');
SELECT ok(has_function_privilege('service_role','public.record_passive_knock(uuid,uuid,integer)','EXECUTE')
  AND NOT has_function_privilege('authenticated','public.record_passive_knock(uuid,uuid,integer)','EXECUTE'),
  'only the job role records a knock');

INSERT INTO auth.users(id,email,aud,role) VALUES
 ('7b000000-0000-4000-8000-000000000001','knock-due@example.invalid','authenticated','authenticated'),
 ('7b000000-0000-4000-8000-000000000002','knock-kind@example.invalid','authenticated','authenticated')
ON CONFLICT(id) DO NOTHING;
INSERT INTO public.profiles(id,display_name) VALUES
 ('7b000000-0000-4000-8000-000000000001','Knock Due'),
 ('7b000000-0000-4000-8000-000000000002','Knock Kind')
ON CONFLICT(id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Who gets knocked
-- ---------------------------------------------------------------------------

SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','7b000000-0000-4000-8000-000000000001',true);
SELECT public.set_passive_checkin_contract(120,2,'none',NULL,NULL,NULL,'shadow','passive-checkin-v1');
UPDATE public.passive_checkin_accounts SET engine_mode='passive_checkin'
WHERE user_id='7b000000-0000-4000-8000-000000000001';

-- Comfortably inside the threshold: nothing to look for, so nothing to ask.
UPDATE public.passive_checkin_windows
SET window_end=clock_timestamp()+interval '150 minutes',
    arrival_deadline=clock_timestamp()+interval '150 minutes'
WHERE user_id='7b000000-0000-4000-8000-000000000001' AND outcome='pending';
SELECT is((SELECT count(*)::integer FROM public.passive_knock_targets()
  WHERE user_id='7b000000-0000-4000-8000-000000000001'),0,
  'a subject who reported recently is never disturbed');

UPDATE public.passive_checkin_windows
SET window_end=clock_timestamp()+interval '10 minutes',
    arrival_deadline=clock_timestamp()+interval '10 minutes'
WHERE user_id='7b000000-0000-4000-8000-000000000001' AND outcome='pending';
SELECT is((SELECT count(*)::integer FROM public.passive_knock_targets()
  WHERE user_id='7b000000-0000-4000-8000-000000000001'),1,
  'a subject about to be judged is asked first');

SELECT public.record_passive_knock('7b000000-0000-4000-8000-000000000001',
  (SELECT id FROM public.passive_checkin_windows
   WHERE user_id='7b000000-0000-4000-8000-000000000001' AND outcome='pending'),0);
SELECT is((SELECT count(*)::integer FROM public.passive_knock_targets()
  WHERE user_id='7b000000-0000-4000-8000-000000000001'),0,
  'a window already knocked is not knocked again this half hour');
SELECT is((SELECT surfaces FROM private.passive_knock_attempts
  WHERE user_id='7b000000-0000-4000-8000-000000000001'),0,
  'a knock that reached no device is recorded as reaching no device');

-- 旧网格会让一个 epoch 同时挂着好几个待判窗口。每一行都敲一次,就是把推送花在
-- 没有人在judge的窗口上。定向必须和引擎对「当前窗口」的定义一致。
INSERT INTO public.passive_checkin_windows(
  user_id,epoch_id,contract_version_id,ordinal,window_start,window_end,arrival_deadline)
SELECT '7b000000-0000-4000-8000-000000000001',
  account.active_epoch_id,account.active_contract_version_id,9,
  clock_timestamp()+interval '150 minutes',
  clock_timestamp()+interval '210 minutes',
  clock_timestamp()+interval '210 minutes'
FROM public.passive_checkin_accounts AS account
WHERE account.user_id='7b000000-0000-4000-8000-000000000001';
DELETE FROM private.passive_knock_attempts WHERE user_id='7b000000-0000-4000-8000-000000000001';
SELECT is((SELECT count(*)::integer FROM public.passive_knock_targets()
  WHERE user_id='7b000000-0000-4000-8000-000000000001'),1,
  'a legacy epoch with several pending windows is still knocked once');

-- ---------------------------------------------------------------------------
-- Which silence it was
-- ---------------------------------------------------------------------------

SELECT set_config('request.jwt.claim.sub','7b000000-0000-4000-8000-000000000002',true);
SELECT public.set_passive_checkin_contract(120,2,'none',NULL,NULL,NULL,'shadow','passive-checkin-v1');
UPDATE public.passive_checkin_accounts SET engine_mode='passive_checkin'
WHERE user_id='7b000000-0000-4000-8000-000000000002';

SELECT is(private.passive_miss_kind('7b000000-0000-4000-8000-000000000002',clock_timestamp()-interval '2 hours',clock_timestamp()),
  'collection_restricted','nothing bound means the silence proves nothing');

CREATE TEMP TABLE kind_binding(id uuid);
INSERT INTO kind_binding SELECT (public.bind_passive_collector(
  'kind-pwa','pwa_browser','pwa-interaction-v1','0.7.0')->>'binding_id')::uuid;

SELECT is(private.passive_miss_kind('7b000000-0000-4000-8000-000000000002',clock_timestamp()-interval '2 hours',clock_timestamp()),
  'device_unreachable','a bound collector that said nothing at all is an equipment fact');

UPDATE private.passive_collector_bindings SET last_contact_at=clock_timestamp()
WHERE id=(SELECT id FROM kind_binding);
SELECT is(private.passive_miss_kind('7b000000-0000-4000-8000-000000000002',clock_timestamp()-interval '2 hours',clock_timestamp()),
  'silent','a collector that checked in with nothing to report means the person was quiet');

-- pwa_browser 自己声明的到达宽限是 5 分钟。两小时前报过一次然后没电的手机,
-- 不能被说成「这个人很安静」—— 那是把设备的故障说成关于人的证据。
UPDATE private.passive_collector_bindings SET last_contact_at=clock_timestamp()-interval '2 hours'
WHERE id=(SELECT id FROM kind_binding);
SELECT is(private.passive_miss_kind('7b000000-0000-4000-8000-000000000002',clock_timestamp()-interval '3 hours',clock_timestamp()),
  'device_unreachable','a collector that spoke once and then went flat is not evidence about the person');
UPDATE private.passive_collector_bindings SET last_contact_at=clock_timestamp()
WHERE id=(SELECT id FROM kind_binding);

UPDATE private.passive_collector_bindings SET permission_state='denied'
WHERE id=(SELECT id FROM kind_binding);
SELECT is(private.passive_miss_kind('7b000000-0000-4000-8000-000000000002',clock_timestamp()-interval '2 hours',clock_timestamp()),
  'collection_restricted','a collector that is not allowed to look cannot report absence');
UPDATE private.passive_collector_bindings SET permission_state='not_applicable'
WHERE id=(SELECT id FROM kind_binding);

-- The evaluator stamps the reason at the moment the window closes, because
-- binding health will have moved on by the time anybody reads about it.
UPDATE public.passive_monitoring_epochs SET started_at=clock_timestamp()-interval '5 hours'
WHERE user_id='7b000000-0000-4000-8000-000000000002' AND ended_at IS NULL;
UPDATE public.passive_checkin_windows
SET window_start=clock_timestamp()-interval '5 hours',
    window_end=clock_timestamp()-interval '3 hours',
    arrival_deadline=clock_timestamp()-interval '3 hours'
WHERE user_id='7b000000-0000-4000-8000-000000000002';
SELECT private.process_passive_checkin_subject('7b000000-0000-4000-8000-000000000002',clock_timestamp());
SELECT is((SELECT miss_kind FROM public.passive_checkin_windows
  WHERE user_id='7b000000-0000-4000-8000-000000000002' AND outcome='missed' ORDER BY ordinal LIMIT 1),
  'silent','an elapsed deadline carries the reason it elapsed');
SELECT is(public.my_daily_checkin()->>'last_miss_kind','silent',
  'the subject is told which kind of silence was recorded');

-- ---------------------------------------------------------------------------
-- The dispatcher stays a dispatcher
-- ---------------------------------------------------------------------------

SELECT ok(position('notify_stage_before_passive_checkin' in
  pg_get_functiondef('private.notify_stage(uuid,uuid,text)'::regprocedure))>0,
  'alerts that did not come from passive check-in are still delegated');
SELECT ok(position('设备上的检测被关闭' in
  pg_get_functiondef('private.notify_stage(uuid,uuid,text)'::regprocedure))>0,
  'a restricted collector is reported as a restriction, not as a missing person');
SELECT ok(position('危险' in
  pg_get_functiondef('private.notify_stage(uuid,uuid,text)'::regprocedure))=0,
  'no wording claims danger the engine cannot see');

SELECT * FROM finish();
ROLLBACK;
