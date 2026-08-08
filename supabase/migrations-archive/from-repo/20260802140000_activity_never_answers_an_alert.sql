-- 告警的问题是「你还好吗」，而答案只有一个形式：本人刻意解锁。
--
-- 实现里却一直是：只要用户产生任何活动（打开 App、解锁屏幕、被动 ping），
-- private.apply_liveness_side_effects 就把 silence / dark_device 告警自动解除。
-- 于是第一环——「设备对用户发出 concern，要求解锁证明一切正常」——从来没有真
-- 正生效过：用户点开通知的那一刻告警就没了，根本走不到解锁这一步。
--
-- 2026-08-02 实测：
--   11:11:00      silence 告警升起
--   11:42:00      升级到小组
--   11:43:44.129  behavior ping kind='app'（本人点开通知）
--   11:43:44.958  auto_resolved，无任何手势
--
-- 20260802120000 给被 concern 附身的告警加了 requires_explicit_unlock 豁免，
-- 但那只堵住了一条分支。根子在于「有活动」被当成了「已回答」。这两件事不等价：
-- 一个病得很重却硬撑的人完全可能在手机上有活动，而这正是这套机制要照顾的人。
--
-- 因此：被动活动只更新在线状态，永不解除任何告警。告警只由本人解锁、认领者确认
-- 安全、或 GM 介入来关闭。
create or replace function private.apply_liveness_side_effects(
  _user_id uuid,
  _observed_at timestamptz,
  _received_at timestamptz
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
BEGIN
  -- 活动只证明设备还活着，不证明人已回答。
  INSERT INTO public.device_state (user_id, status, last_heartbeat_at, updated_at)
  VALUES (_user_id, 'normal', _received_at, now())
  ON CONFLICT (user_id) DO UPDATE
    SET status = 'normal',
        last_heartbeat_at = greatest(device_state.last_heartbeat_at, excluded.last_heartbeat_at),
        updated_at = now();

  -- 催促通知在告警仍然开着时必须留着：此前它随着「用户有活动」一起被删，
  -- 于是人打开一次 App，既解除了告警又清掉了催促，两头都断。现在只有在确实
  -- 没有未决告警时才清理。
  IF NOT (auth.uid() IS NOT NULL AND auth.uid() <> _user_id)
     AND NOT EXISTS (
       SELECT 1 FROM public.alerts
       WHERE user_id = _user_id AND status = 'open'
     ) THEN
    DELETE FROM public.notifications
      WHERE recipient_id = _user_id
        AND kind in ('self', 'concern');
  END IF;
END;
$function$;

-- 本人解锁成功时，把针对本人的催促通知一并清掉——此刻它才真正失去意义。
create or replace function public.resolve_my_alert()
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare _uid uuid := auth.uid(); _aid uuid;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  update public.alerts set status = 'resolved', resolved_at = now(), resolved_by = _uid, updated_at = now()
    where user_id = _uid and status = 'open' returning id into _aid;
  if _aid is not null then
    insert into public.alert_events (alert_id, actor_id, kind) values (_aid, _uid, 'resolved');
  end if;

  insert into public.behavior_pings (user_id, kind, at)
  values (_uid, 'manual_checkin', now());

  delete from public.notifications
    where recipient_id = _uid and kind in ('self', 'concern');

  perform private.trigger_push_dispatch();
end;
$function$;
