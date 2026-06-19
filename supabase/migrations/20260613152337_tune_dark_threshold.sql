-- 调整暗设备阈值：90 分钟 → 18 小时。
-- PWA 形态下心跳只在 App 开着 / 行为 ping 触发时刷新，90min 会把正常过夜/外出误判为暗设备。
-- 18h = 正常过夜(约8h)与稀疏白天都不误报，真·一整天零行为信号才触发。其余逻辑不变。

create or replace function public.process_escalations()
returns void language plpgsql security definer set search_path = '' as $$
declare
  _self_grace   constant interval := interval '30 minutes';
  _group_dur    constant interval := interval '1 hour';
  _comm_dur     constant interval := interval '2 hours';
  _dark         constant interval := interval '18 hours';
  r record;
  _aid uuid;
  _new text;
begin
  for r in
    select ds.user_id,
           (ds.last_heartbeat_at < now() - _dark) as is_dark
    from public.device_state ds
    where (ds.status = 'alert' or ds.last_heartbeat_at < now() - _dark)
      and exists (select 1 from public.group_members gm
                  where gm.user_id = ds.user_id and gm.monitored and gm.status = 'active')
      and not exists (select 1 from public.alerts a where a.user_id = ds.user_id and a.status = 'open')
  loop
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    values (r.user_id, case when r.is_dark then 'dark_device' else 'silence' end,
            'self', now(), now() + _self_grace)
    returning id into _aid;
    insert into public.alert_events (alert_id, kind) values (_aid, 'raised');
    perform private.notify_stage(_aid, r.user_id, 'self');
  end loop;

  for r in
    select a.id from public.alerts a
    join public.device_state ds on ds.user_id = a.user_id
    where a.status = 'open' and a.cause in ('silence', 'dark_device')
      and ds.status = 'normal' and ds.last_heartbeat_at > now() - _dark
  loop
    update public.alerts set status = 'resolved', resolved_at = now(), updated_at = now() where id = r.id;
    insert into public.alert_events (alert_id, kind) values (r.id, 'auto_resolved');
  end loop;

  for r in
    select * from public.alerts
    where status = 'open'
      and next_deadline is not null and next_deadline <= now()
      and coalesce(paused_until, to_timestamp(0)) <= now()
  loop
    _new := case r.stage
              when 'self' then 'group'
              when 'group' then 'community'
              when 'community' then 'terminal'
              else 'terminal' end;
    update public.alerts
      set stage = _new, stage_entered_at = now(), paused_until = null, updated_at = now(),
          next_deadline = case _new when 'group' then now() + _group_dur
                                    when 'community' then now() + _comm_dur
                                    else null end
      where id = r.id;
    insert into public.alert_events (alert_id, kind, note) values (r.id, 'escalated', _new);
    perform private.notify_stage(r.id, r.user_id, _new);
  end loop;
end;
$$;
