-- private.promote_device_samples_to_liveness 的契约。
--
-- 这些断言守的是 2026-08-13 那次实测暴露的两头风险:
--   一头是漏 —— 814 步被完整收上来却在活体问题上不算数;
--   另一头是滥 —— 一台放在桌上自己充电、自己放播客的手机永远刷新心跳,
--   那是 ADR-0039 最不想要的失效模式,比不报还糟。
-- 所以「认什么」和「不认什么」在这里是同等重要的断言。

BEGIN;

SELECT plan(14);

INSERT INTO auth.users (id, email, aud, role) VALUES
  ('41000000-0000-4000-8000-000000000001', 'dslp-steps@example.invalid', 'authenticated', 'authenticated'),
  ('41000000-0000-4000-8000-000000000002', 'dslp-floors@example.invalid', 'authenticated', 'authenticated'),
  ('41000000-0000-4000-8000-000000000003', 'dslp-car@example.invalid', 'authenticated', 'authenticated'),
  ('41000000-0000-4000-8000-000000000004', 'dslp-idle@example.invalid', 'authenticated', 'authenticated'),
  ('41000000-0000-4000-8000-000000000005', 'dslp-stale@example.invalid', 'authenticated', 'authenticated'),
  ('41000000-0000-4000-8000-000000000006', 'dslp-alert@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, display_name, routine_pattern, consent_data_sharing) VALUES
  ('41000000-0000-4000-8000-000000000001', 'DSLP steps', 'regular_9to5', false),
  ('41000000-0000-4000-8000-000000000002', 'DSLP floors', 'regular_9to5', false),
  ('41000000-0000-4000-8000-000000000003', 'DSLP in a car', 'regular_9to5', false),
  ('41000000-0000-4000-8000-000000000004', 'DSLP on a table', 'regular_9to5', false),
  ('41000000-0000-4000-8000-000000000005', 'DSLP stale sample', 'regular_9to5', false),
  ('41000000-0000-4000-8000-000000000006', 'DSLP open alert', 'regular_9to5', false)
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

-- 六个采样,只有前两个和最后一个该被提升。
INSERT INTO public.device_activity_samples (
  id, user_id, trigger, observed_at, received_at, collector_contract,
  protected_data_available, steps_since_last_sample, floors_since_last_sample,
  dominant_activity, other_audio_playing, battery_level, battery_state
) VALUES
  -- 走了 814 步,唤醒时手机是锁着的 —— 正是被漏掉的那一类
  ('41100000-0000-4000-8000-000000000001', '41000000-0000-4000-8000-000000000001',
   'push-wake', now() - interval '30 seconds', now() - interval '29 seconds',
   'ios-passive-v1', false, 814, 0, 'walking', false, 0.7, 'unplugged'),
  -- 只有楼层:气压计造不了假,车里颠簸也变不出爬楼
  ('41100000-0000-4000-8000-000000000002', '41000000-0000-4000-8000-000000000002',
   'push-wake', now() - interval '30 seconds', now() - interval '29 seconds',
   'ios-passive-v1', false, 0, 3, 'stationary', false, 0.7, 'unplugged'),
  -- 车里:有步数也不认
  ('41100000-0000-4000-8000-000000000003', '41000000-0000-4000-8000-000000000003',
   'push-wake', now() - interval '30 seconds', now() - interval '29 seconds',
   'ios-passive-v1', false, 260, 0, 'automotive', false, 0.7, 'unplugged'),
  -- 桌上充电 + 播客连播,没有任何位移
  ('41100000-0000-4000-8000-000000000004', '41000000-0000-4000-8000-000000000004',
   'push-wake', now() - interval '30 seconds', now() - interval '29 seconds',
   'ios-passive-v1', false, 0, 0, 'stationary', true, 0.95, 'charging'),
  -- 合格但已经超出活体窗口:补传的历史不得刷新当下安全
  ('41100000-0000-4000-8000-000000000005', '41000000-0000-4000-8000-000000000005',
   'push-wake', now() - interval '40 minutes', now() - interval '39 minutes',
   'ios-passive-v1', false, 500, 0, 'walking', false, 0.7, 'unplugged'),
  -- 有 open 告警的人也在走路:证据要收,但告警不许被它解除
  ('41100000-0000-4000-8000-000000000006', '41000000-0000-4000-8000-000000000006',
   'push-wake', now() - interval '30 seconds', now() - interval '29 seconds',
   'ios-passive-v1', false, 120, 0, 'walking', false, 0.7, 'unplugged');

INSERT INTO public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
VALUES ('41000000-0000-4000-8000-000000000006', 'silence', 'self', now(), NULL);

-- —— 第一次运行 ——

CREATE TEMP TABLE _first AS
SELECT private.promote_device_samples_to_liveness() AS result;

SELECT is(
  (SELECT (result->>'inserted')::int FROM _first),
  3,
  '只有位移证据被提升:步数、楼层、以及有 open 告警的那位'
);

SELECT is(
  (SELECT (result->>'missed_live_window_last_hour')::int FROM _first),
  1,
  '错过活体窗口的合格采样被数出来,而不是悄悄消失'
);

SELECT is(
  (SELECT (result->>'failed')::int FROM _first),
  0,
  '没有账户失败'
);

SELECT is(
  (SELECT count(*)::int FROM public.behavior_pings
   WHERE user_id = '41000000-0000-4000-8000-000000000001'),
  1,
  '走了 814 步的人拿到了一条活体证据'
);

SELECT is(
  (SELECT kind FROM public.behavior_pings
   WHERE user_id = '41000000-0000-4000-8000-000000000001'),
  'steps',
  '沿用既有的 steps 词汇,不新增 kind'
);

SELECT is(
  (SELECT source FROM public.behavior_pings
   WHERE user_id = '41000000-0000-4000-8000-000000000001'),
  'capacitor',
  '沿用既有的 capacitor 来源,不新增 source'
);

SELECT is(
  (SELECT count(*)::int FROM public.behavior_pings
   WHERE user_id = '41000000-0000-4000-8000-000000000002'),
  1,
  '只有楼层增加也算数:气压计比计步器更难造假'
);

SELECT is(
  (SELECT count(*)::int FROM public.behavior_pings
   WHERE user_id = '41000000-0000-4000-8000-000000000003'),
  0,
  '车上的步数一票否决'
);

SELECT is(
  (SELECT count(*)::int FROM public.behavior_pings
   WHERE user_id = '41000000-0000-4000-8000-000000000004'),
  0,
  '桌上充电加播客连播不构成活体 —— 这是 ADR-0039 最怕的失效模式'
);

SELECT is(
  (SELECT count(*)::int FROM public.behavior_pings
   WHERE user_id = '41000000-0000-4000-8000-000000000005'),
  0,
  '超出活体窗口的补传采样不得刷新当下安全'
);

-- 学习函数用的是同一条 ±5 分钟规则;提升出来的证据必须落在窗口内,
-- 否则它既进不了活体也进不了训练,整件事白做。
SELECT ok(
  (SELECT abs(extract(epoch FROM (received_at - at))) <= 300
   FROM public.behavior_pings
   WHERE user_id = '41000000-0000-4000-8000-000000000001'),
  '提升出来的证据落在 ±5 分钟内,才会被 rebuild_account_normal_bounds 采信'
);

SELECT ok(
  (SELECT last_heartbeat_at IS NOT NULL AND status = 'normal'
   FROM public.device_state
   WHERE user_id = '41000000-0000-4000-8000-000000000001'),
  '心跳被刷新'
);

SELECT is(
  (SELECT count(*)::int FROM public.alerts
   WHERE user_id = '41000000-0000-4000-8000-000000000006' AND status = 'open'),
  1,
  '被动活动绝不解除 open 告警(ADR-0039)'
);

-- —— 第二次运行:同一批采样不得再产生第二条 ——

SELECT is(
  (SELECT (private.promote_device_samples_to_liveness()->>'inserted')::int),
  0,
  '重复运行不再产生新证据:幂等由 (user_id, event_id) 唯一索引兜住'
);

SELECT * FROM finish();
ROLLBACK;
