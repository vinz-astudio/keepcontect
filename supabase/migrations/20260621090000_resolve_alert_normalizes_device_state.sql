-- 确认安全=人工核实对方无恙:除解除告警外,把其活跃状态归正常,
-- 看板立即恢复(不再 alerted,且显示活跃),也避免立刻被重新升级。
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

  -- 归一化被关注者的活跃状态 → 看板立即回到正常
  insert into public.device_state (user_id, status, last_heartbeat_at, updated_at)
  values (_target, 'normal', now(), now())
  on conflict (user_id) do update set status = 'normal', last_heartbeat_at = now(), updated_at = now();

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
end;
$$;
