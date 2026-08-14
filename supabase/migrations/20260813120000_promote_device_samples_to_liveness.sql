-- 把已经收到、却在「这人还活着吗」上不算数的采样，提升为合格活体证据。
--
-- 起因(2026-08-13 生产实测,iOS tester 账号):
--   8-11 19:49 → 8-13 03:05,31 小时零活体上报。同一段时间里:
--     · 106 次 push-wake 采样全部到达,守望者一小时没落下
--     · 其中 4 次记到 steps > 0,最高一次 814 步
--     · 电量 65% → 95%,有人给它插了电
--     · 低电量模式全程关闭
--   而同一台手机上另一个账号的捷径当天打了约 130 次,手机整天在被解锁使用。
--   唯一的原因是 iOS 唤醒时记活体的门槛是 `isProtectedDataAvailable`,这 106 次
--   全读到 false。814 步被完整上传、完整入库,然后在活体问题上一条不算。
--   rebuild_account_normal_bounds 于是学出「这人正常能安静 22 小时」。
--
-- 为什么落在这里,而不是 device-sample 函数里:
--   `device-sample` 端点被明确设计成永远不能创造活体、永远不能碰告警,并且这一点
--   要靠部署隔离来保证,而不是靠代码注释里的承诺。那堵墙原封不动:端点只负责存,
--   提升由这个独立的库内任务做,现有的 apply_liveness_side_effects 语义照旧
--   —— 刷新 device_state 心跳,绝不解除任何 open 告警(ADR-0039)。
--
-- 为什么在服务端算,而不是改客户端:
--   DeviceSample 的设计注释本来就是这么写的 ——「原始值上传,差值在服务端算,
--   这样改主意不需要每个人重装一次」。客户端一行不改,也就不新增任何权限、
--   不新增后台模式、不需要重新过 App Store 或 Google Play 审核。
--
-- 合格规则(刻意最保守):
--   步数或楼层在这段间隔内增加了,且该间隔不是「在车上」。
--   放在桌上的手机造不出步数;车里颠簸造得出,所以 automotive 一票否决
--   (DeviceSample 里 dominant_activity 的存在意义就是废掉这种运动证据)。
--   电量上涨、播放音频、加速度方差三项**故意不认**:手机放在无线充电座上过夜、
--   播客自动连播,都能在旁边没人的情况下持续成立,那正是 ADR-0039 最不想要的
--   失效模式 —— 一台放在桌上的手机永远刷新心跳。
--
-- 为什么必须每分钟跑:
--   insert_behavior_ping 用 |received_at - at| <= 300s 判定这条是不是活体安全证据,
--   而学习函数用的是同一条 ±5 分钟规则。提升晚于采样 5 分钟,这条证据既进不了
--   活体也进不了训练,等于白做。所以本任务只提升「观测时间还在 5 分钟内」的采样,
--   并把错过窗口的条数如实返回 —— 节奏配错了会在返回值里显形,而不是悄悄失效。

-- _live_window 默认 4 分钟而不是 5:insert_behavior_ping 用它自己的
-- clock_timestamp() 重新算一次时差,那一刻永远晚于本函数取的 _now。卡在 5 分钟
-- 上选出来的采样,可能在几百毫秒后被判成非活体 —— ping 照样写进去,却既不刷新
-- 心跳也进不了训练。留一分钟余量,让「选中」和「被采信」不会各说各话。
CREATE OR REPLACE FUNCTION private.promote_device_samples_to_liveness(
  _live_window interval DEFAULT interval '4 minutes',
  _limit integer DEFAULT 500
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
SET "TimeZone" TO 'UTC'
AS $$
DECLARE
  _now timestamptz := clock_timestamp();
  _sample record;
  _status text;
  _inserted integer := 0;
  _duplicate integer := 0;
  _invalid integer := 0;
  _failed integer := 0;
  _missed_window integer := 0;
BEGIN
  IF _live_window IS NULL OR _live_window <= interval '0'
     OR _limit IS NULL OR _limit <= 0 THEN
    RAISE EXCEPTION 'promote_device_samples_to_liveness: invalid parameters';
  END IF;

  -- 错过活体窗口的合格采样。不提升,但要数出来:这个数字持续大于 0,说明
  -- 调度节奏或上传延迟出了问题,而不是「没人走路」。
  SELECT count(*)::integer INTO _missed_window
  FROM public.device_activity_samples AS s
  WHERE s.received_at >= _now - interval '1 hour'
    AND s.observed_at <= _now - _live_window
    AND (
      coalesce(s.steps_since_last_sample, 0) > 0
      OR coalesce(s.floors_since_last_sample, 0) > 0
    )
    AND s.dominant_activity IS DISTINCT FROM 'automotive'
    AND NOT EXISTS (
      SELECT 1
      FROM public.behavior_pings AS p
      WHERE p.user_id = s.user_id
        AND p.event_id = (md5('kc.sample-liveness:' || s.id::text))::uuid
    );

  FOR _sample IN
    SELECT
      s.id,
      s.user_id,
      s.observed_at,
      -- 与采样自己的 event_id 处在不同命名空间,既不会撞上客户端生成的 id,
      -- 又让同一条采样无论被扫到几次都只能产生同一条 ping —— 幂等性由
      -- behavior_pings 上 (user_id, event_id) 的唯一索引兜住,不需要在
      -- device_activity_samples 上加一个会漂移的「已提升」状态列。
      (md5('kc.sample-liveness:' || s.id::text))::uuid AS ping_event_id
    FROM public.device_activity_samples AS s
    WHERE s.observed_at > _now - _live_window
      -- 未来时间戳是客户端时钟错乱,不是证据;insert_behavior_ping 也会拒,
      -- 在这里先挡掉,免得白占一次循环。
      AND s.observed_at <= _now
      AND (
        coalesce(s.steps_since_last_sample, 0) > 0
        OR coalesce(s.floors_since_last_sample, 0) > 0
      )
      AND s.dominant_activity IS DISTINCT FROM 'automotive'
    ORDER BY s.observed_at
    LIMIT _limit
  LOOP
    -- 一个账户失败不得带走整批(per-subject failure isolation)。
    BEGIN
      _status := private.insert_behavior_ping(
        _sample.user_id,
        _sample.ping_event_id,
        _sample.observed_at,
        'capacitor',
        'steps'
      );

      IF _status = 'inserted' THEN
        _inserted := _inserted + 1;
      ELSIF _status = 'duplicate' THEN
        _duplicate := _duplicate + 1;
      ELSE
        _invalid := _invalid + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      _failed := _failed + 1;
      RAISE WARNING 'promote_device_samples_to_liveness: sample % failed: %',
        _sample.id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'ran_at', _now,
    'live_window', _live_window,
    'inserted', _inserted,
    'duplicate', _duplicate,
    'invalid', _invalid,
    'failed', _failed,
    'missed_live_window_last_hour', _missed_window
  );
END;
$$;

ALTER FUNCTION private.promote_device_samples_to_liveness(interval, integer)
  OWNER TO postgres;

COMMENT ON FUNCTION private.promote_device_samples_to_liveness(interval, integer) IS
  'ADR-0040 D1 第一层:把带间隔性人类活动痕迹(步数/楼层,排除 automotive)的设备采样提升为 self_observed 活体证据。仅读 device_activity_samples,写入走 insert_behavior_ping,不改变告警语义。';

REVOKE ALL ON FUNCTION private.promote_device_samples_to_liveness(interval, integer)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION private.promote_device_samples_to_liveness(interval, integer)
  FROM anon, authenticated;

-- 扫描条件是 observed_at 上的一个窄窗口,每分钟一次全表扫不划算。
CREATE INDEX IF NOT EXISTS device_activity_samples_movement_idx
  ON public.device_activity_samples (observed_at)
  WHERE (
    coalesce(steps_since_last_sample, 0) > 0
    OR coalesce(floors_since_last_sample, 0) > 0
  );

-- 每分钟一次。理由见文件头:晚于 5 分钟提升,这条证据既进不了活体也进不了训练。
SELECT cron.unschedule('promote-device-sample-liveness')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'promote-device-sample-liveness');

SELECT cron.schedule(
  'promote-device-sample-liveness',
  '* * * * *',
  $job$select private.promote_device_samples_to_liveness();$job$
);

-- 这个任务停掉的样子和「最近没人走路」一模一样:采样照收、覆盖照报、界面照常,
-- 只有阈值会慢慢松回 20 小时那一档。正是必须被大声报出来的那种失效。
INSERT INTO private.scheduled_job_expectations (job_name, max_gap, matters_because)
VALUES (
  'promote-device-sample-liveness',
  interval '15 minutes',
  'Movement evidence stops becoming liveness. Nothing errors: samples keep '
  'arriving and coverage keeps reporting, so the account looks watched while '
  'its learned threshold quietly drifts back out to the twenty-hour range.'
)
ON CONFLICT (job_name) DO UPDATE
  SET max_gap = EXCLUDED.max_gap,
      matters_because = EXCLUDED.matters_because;
