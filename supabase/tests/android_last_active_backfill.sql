-- public.record_last_active_backfill 的契约。
--
-- 这个函数存在的意义只有一句:Android 醒来时知道「这人 30 分钟前解锁过」,
-- 那条证据必须落库。但它同样必须**什么都不影响** —— 历史时间戳不得刷新
-- 心跳、不得触碰告警。这两头在这里是同等重要的断言,漏掉任何一头都会
-- 把一次补报变成一次伪造的「他现在还在」。
--
-- 幂等那几条守的是另一件事:Android 每 15 分钟醒一次,同一个 last_active
-- 会被反复上报。如果每次都新建一条 ping,活动时间线会被灌成假的密集,
-- 学习器将来读到的就是被污染的数据。

BEGIN;

SELECT plan(12);

INSERT INTO auth.users (id, email, aud, role) VALUES
  ('42000000-0000-4000-8000-000000000001', 'alab-normal@example.invalid', 'authenticated', 'authenticated'),
  ('42000000-0000-4000-8000-000000000002', 'alab-alert@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, display_name, routine_pattern, consent_data_sharing) VALUES
  ('42000000-0000-4000-8000-000000000001', 'ALAB normal', 'regular_9to5', false),
  ('42000000-0000-4000-8000-000000000002', 'ALAB open alert', 'regular_9to5', false)
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

-- —— 基本落库 ——

SELECT is(
  public.record_last_active_backfill(
    '42000000-0000-4000-8000-000000000001',
    now() - interval '30 minutes'
  ),
  'inserted',
  '30 分钟前的解锁时刻被接受并落库'
);

SELECT is(
  (SELECT count(*)::int FROM public.behavior_pings
   WHERE user_id = '42000000-0000-4000-8000-000000000001'),
  1,
  '恰好写入一条 ping'
);

SELECT is(
  (SELECT kind FROM public.behavior_pings
   WHERE user_id = '42000000-0000-4000-8000-000000000001'),
  'unlock',
  'kind 记为 unlock —— 这条证据的来源是解锁/交互事件,不是 App 自己醒着'
);

-- at 必须是观测时刻,不是收到时刻。学习器将来要靠这个字段建真实时间线;
-- 如果这里存成 now(),补报就退化成又一条「我现在醒着」,整件事白做。
SELECT ok(
  (SELECT abs(extract(epoch FROM (at - (now() - interval '30 minutes')))) < 5
   FROM public.behavior_pings
   WHERE user_id = '42000000-0000-4000-8000-000000000001'),
  'at 记的是观测时刻(30 分钟前),不是上传时刻'
);

-- —— 不得影响当下安全 ——

SELECT ok(
  (SELECT abs(extract(epoch FROM (received_at - at))) > 300
   FROM public.behavior_pings
   WHERE user_id = '42000000-0000-4000-8000-000000000001'),
  '历史证据落在 ±5 分钟活体窗口之外,因此不会触发 apply_liveness_side_effects'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.device_state
    WHERE user_id = '42000000-0000-4000-8000-000000000001'
      AND last_heartbeat_at >= now() - interval '5 minutes'
  ),
  '补报没有刷新心跳'
);

-- —— 幂等 ——

SELECT is(
  public.record_last_active_backfill(
    '42000000-0000-4000-8000-000000000001',
    now() - interval '30 minutes'
  ),
  'duplicate',
  '同一个 last_active 反复上报只认第一次'
);

SELECT is(
  (SELECT count(*)::int FROM public.behavior_pings
   WHERE user_id = '42000000-0000-4000-8000-000000000001'),
  1,
  '重复上报没有把活动时间线灌密'
);

SELECT is(
  public.record_last_active_backfill(
    '42000000-0000-4000-8000-000000000001',
    now() - interval '20 minutes'
  ),
  'inserted',
  'last_active 前进之后是一条新证据'
);

-- —— 边界 ——

SELECT is(
  public.record_last_active_backfill(
    '42000000-0000-4000-8000-000000000001',
    now() + interval '30 minutes'
  ),
  'invalid',
  '未来时间戳是客户端时钟错乱,不是证据'
);

SELECT is(
  public.record_last_active_backfill(
    '42000000-0000-4000-8000-000000000001',
    now() - interval '30 hours'
  ),
  'too_old',
  '超过 24 小时的补报如实拒绝,不静默丢弃'
);

-- —— 绝不解除 open 告警(ADR-0039)——

INSERT INTO public.alerts (id, user_id, cause, stage, status, opened_at)
VALUES (
  '42200000-0000-4000-8000-000000000001',
  '42000000-0000-4000-8000-000000000002',
  'silence', 'self', 'open', now() - interval '1 hour'
)
ON CONFLICT (id) DO NOTHING;

SELECT public.record_last_active_backfill(
  '42000000-0000-4000-8000-000000000002',
  now() - interval '30 minutes'
);

SELECT is(
  (SELECT status FROM public.alerts
   WHERE id = '42200000-0000-4000-8000-000000000001'),
  'open',
  '补报不解除 open 告警'
);

SELECT * FROM finish();
ROLLBACK;
