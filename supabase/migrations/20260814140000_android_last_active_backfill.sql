-- Android 早就知道用户上次用手机是什么时候，只是从来不说。
--
-- 起因(2026-08-13 定位，2026-08-14 落地第一段):
--   PassivePing.queryLastActiveTime() 读 UsageStats 最近 24 小时的
--   ACTIVITY_RESUMED / USER_INTERACTION / KEYGUARD_HIDDEN，返回精确时间戳。
--   它只有两个调用方——本地通知判断与状态显示——从不上传。
--   而 PassivePing.ping() 发出的 observed_at 永远是 now()。
--   于是 Android 从 Doze 里醒来，明明能证明「这人 30 分钟前解锁过手机」，
--   却把这条证据扔掉，只报一句「我现在醒着」。与 iOS 同一个病。
--
-- 这个函数是那条证据的落库口。它刻意什么都不影响:
--
--   insert_behavior_ping 只在 |received_at - observed_at| <= 300s 时才调用
--   apply_liveness_side_effects。补报的时间戳是历史的，必然超出这个窗口，
--   所以这条 ping **进得了 behavior_pings，碰不到心跳，也碰不到任何告警**。
--   这不是限制，这正是要的语义:14:00 收到「13:35 解锁过」，我们知道的是
--   13:35 那一刻他在，不是 14:00 这一刻他在。
--
--   现行 rebuild_account_normal_bounds 同样用 ±5 分钟规则过滤，并且用
--   date_trunc('minute', received_at) 而不是 at 建时间线。所以这条证据
--   **现在也进不了学习**。同样是刻意的:让学习器接受历史证据会改变已生效的
--   阈值，属于要人类拍板并且必须先跑影子期的改动，不在本迁移范围内。
--
-- 那本迁移买到了什么:真实的活动时间线开始在 behavior_pings 里积累。
-- 在此之前它根本不存在，也就没有任何数据能用来论证第二段该怎么改。
--
-- 幂等:event_id 由 (user_id, 观测时刻) 派生。Android 每 15 分钟醒一次，
-- 只要 last_active 没变，反复上报都落在同一个 event_id 上，靠
-- behavior_pings (user_id, event_id) 唯一索引兜住，不需要客户端记状态。
-- 命名空间与 kc.sample-liveness 平行，不会与客户端随机 UUID 相撞。

CREATE OR REPLACE FUNCTION public.record_last_active_backfill(
  _user_id uuid,
  _last_active_at timestamptz,
  _source text DEFAULT 'capacitor'
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
SET "TimeZone" TO 'UTC'
AS $$
DECLARE
  _now timestamptz := clock_timestamp();
  _event_id uuid;
BEGIN
  IF _user_id IS NULL OR _last_active_at IS NULL THEN
    RETURN 'invalid';
  END IF;

  -- 未来时间戳是客户端时钟错乱，不是证据。insert_behavior_ping 也会拒，
  -- 这里先挡掉，免得为一条注定失败的记录派生 id。
  IF _last_active_at > _now + interval '5 minutes' THEN
    RETURN 'invalid';
  END IF;

  -- 超过 24 小时的补报没有意义:queryLastActiveTime 本来就只查最近 24 小时，
  -- 更老的值只可能来自陈旧队列或时钟漂移。不接受，也不静默丢——如实返回。
  IF _last_active_at < _now - interval '24 hours' THEN
    RETURN 'too_old';
  END IF;

  -- 毫秒精度足够:UsageEvents 的时间戳就是毫秒。截到毫秒可以让同一个事件
  -- 在不同次上报里派生出同一个 id，而不会因为格式化差异裂成两条。
  _event_id := (
    md5(
      'kc.android-last-active:'
      || _user_id::text
      || ':'
      || to_char(_last_active_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS')
    )
  )::uuid;

  RETURN private.insert_behavior_ping(
    _user_id,
    _event_id,
    _last_active_at,
    _source,
    'unlock'
  );
END;
$$;

ALTER FUNCTION public.record_last_active_backfill(uuid, timestamptz, text)
  OWNER TO postgres;

COMMENT ON FUNCTION public.record_last_active_backfill(uuid, timestamptz, text) IS
  'ADR-0040 D1 环②:把 Android UsageStats 已知的上次活动时刻补报为一条历史 behavior_ping。历史时间戳必然落在 insert_behavior_ping 的 ±5 分钟活体窗口之外，因此不刷新心跳、不触碰告警，当前也不进入学习。';

-- 只有服务角色调用(edge function 用 service role)。与 record_behavior_ping_for_user
-- 一致:不给 anon / authenticated，避免客户端绕过 token 校验直接补报任意时间点。
REVOKE ALL ON FUNCTION public.record_last_active_backfill(uuid, timestamptz, text)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_last_active_backfill(uuid, timestamptz, text)
  FROM anon, authenticated;
