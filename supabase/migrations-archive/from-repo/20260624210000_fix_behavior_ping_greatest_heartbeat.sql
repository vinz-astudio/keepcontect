-- Fix: handle_behavior_ping_insert now uses greatest() to ensure last_heartbeat_at
-- only moves forward and is never overwritten by historical/older sync pings.
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

  -- 3) 清除本人的 "please check in" 提示
  delete from public.notifications
    where recipient_id = new.user_id
      and kind in ('self', 'concern');

  if _triggered then
    perform private.trigger_push_dispatch();
  end if;

  return new;
end;
$$;
