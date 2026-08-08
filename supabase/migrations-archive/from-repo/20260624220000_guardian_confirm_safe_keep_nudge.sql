-- Fix: Update resolve_alert and handle_behavior_ping_insert triggers
-- to keep user self check-in nudges when confirmed safe by a guardian,
-- and insert a fresh self check-in reminder nudge for the user themselves.

-- 1) Update trigger function private.handle_behavior_ping_insert() to conditionally clear notifications
create or replace function private.handle_behavior_ping_insert()
returns trigger language plpgsql security definer set search_path to '' as $$
declare _stale record; _triggered boolean := false;
begin
  -- 1) 更新心跳状态为正常 (使用 greatest 确保时间只往前，不退后)
  insert into public.device_state (user_id, status, last_heartbeat_at, updated_at)
  values (new.user_id, 'normal', new.at, now())
  on conflict (user_id) do update
    set status = 'normal',
        last_heartbeat_at = greatest(device_state.last_heartbeat_at, excluded.last_heartbeat_at),
        updated_at = now();

  -- 2) 自动解除 open 的 silence/dark_device 告警
  for _stale in
    select id from public.alerts
    where user_id = new.user_id
      and status = 'open'
      and cause in ('silence', 'dark_device')
  loop
    update public.alerts
      set status = 'resolved', resolved_at = new.at, resolved_by = new.user_id, updated_at = now()
      where id = _stale.id;
      
    insert into public.alert_events (alert_id, actor_id, kind)
    values (_stale.id, new.user_id, 'auto_resolved');

    -- 清除该告警产生的所有通知
    delete from public.notifications where alert_id = _stale.id;
    _triggered := true;
  end loop;

  -- 3) 清除本人的 "please check in" 提示 (仅当不是由监护人/管理员帮其确认安全时)
  if not (auth.uid() is not null and auth.uid() <> new.user_id) then
    delete from public.notifications
      where recipient_id = new.user_id
        and kind in ('self', 'concern');
  end if;

  if _triggered then
    perform private.trigger_push_dispatch();
  end if;

  return new;
end;
$$;


-- 2) Update public.resolve_alert(_alert_id uuid) to insert behavior ping and send nudge to the user themselves
create or replace function public.resolve_alert(_alert_id uuid)
returns void language plpgsql security definer set search_path to '' as $$
declare _uid uuid := auth.uid(); _target uuid; _tname text;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if not private.can_see_alert(_alert_id, _uid) then raise exception 'forbidden'; end if;
  if not exists (select 1 from public.alerts where id = _alert_id and paused_by = _uid) then
    raise exception 'only the responder who reached out can confirm safe';
  end if;

  update public.alerts
    set status = 'resolved', resolved_at = now(), resolved_by = _uid, updated_at = now()
    where id = _alert_id and status = 'open' returning user_id into _target;
  if _target is null then raise exception 'alert not open'; end if;

  insert into public.alert_events (alert_id, actor_id, kind) values (_alert_id, _uid, 'confirmed_safe');

  -- 归一化被关注者的活跃状态
  insert into public.device_state (user_id, status, last_heartbeat_at, updated_at)
  values (_target, 'normal', now(), now())
  on conflict (user_id) do update set status = 'normal', last_heartbeat_at = now(), updated_at = now();

  -- 写入一条 behavior_ping，确保其最新活跃时间变成 now()，重置静默计时器防止立即重新报警
  insert into public.behavior_pings (user_id, kind, at)
  values (_target, 'manual_checkin', now());

  -- 给被关注者自己发送一条 kind = 'self' 的通知，保留提示，并在外部推送触发再次提示
  insert into public.notifications (recipient_id, alert_id, kind, body)
  values (_target, _alert_id, 'self', '【系统提示】小组已确认你安全，但检测到设备仍未活动。请解锁或使用手机以恢复自动守护！');

  -- 给小组其他成员发送解除通知
  select coalesce(display_name, '') into _tname from public.profiles where id = _target;
  insert into public.notifications (recipient_id, alert_id, kind, body, params)
  select distinct s.r, _alert_id, 'resolved', _tname || ' 已确认安全，告警解除。',
    jsonb_build_object('target', _tname)
  from (
    select _target as r
    union
    select w.user_id from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _target and t.monitored and t.status = 'active'
        and w.watching and w.status = 'active'
  ) s;

  perform private.trigger_push_dispatch();
end;
$$;
