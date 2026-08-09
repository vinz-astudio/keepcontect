-- 防逞强：沉默/暗设备告警的解除不能仅靠"打开 App 发 normal 心跳"，
-- 必须 pattern 解锁(resolve_my_alert) 或 一个真实行为 ping(充电/闹钟，经 ping 接口)。
-- 改动：① send_heartbeat 不再因 normal 自动解除告警；② cron 去掉"设备 normal 即自动解除"那一步。
-- 行为 ping 仍在 ping 接口里直接解除（真实人为动作=有效报活），pattern 解锁照常解除。

create or replace function public.send_heartbeat(_status text)
returns void language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if _status not in ('normal', 'alert') then raise exception 'bad status'; end if;
  insert into public.device_state (user_id, status, last_heartbeat_at, updated_at)
  values (_uid, _status, now(), now())
  on conflict (user_id) do update
    set status = excluded.status, last_heartbeat_at = now(), updated_at = now();
end;
$$;

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
