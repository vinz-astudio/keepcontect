-- 服务器侧"时段感知沉默阈值"：用 behavior_pings 历史学每个时段的常态间隔，
-- 判断"此刻这个时段、按你平时频率，沉默这么久正常吗"。天然理解睡眠（夜里常态间隔大）。
-- UTC 坐标即可（用户作息在本地固定=在 UTC 固定）。数据不足/学习期回退到 18h 冷启动阈值。
create or replace function private.silence_threshold(_user uuid)
returns interval language plpgsql security definer set search_path = '' stable as $$
declare
  _mult     constant numeric := 1.8;        -- 平衡档倍数（后续可绑用户灵敏度）
  _floor_s  constant numeric := 10800;      -- 下限 3h（避免白天毛刺）
  _cap_s    constant numeric := 72000;      -- 上限 20h
  _cold     constant interval := interval '18 hours';
  _total    int;
  _last_hour int;
  _global   numeric;
  _hourly   numeric;
  _hourly_n int;
  _expected numeric;
begin
  select count(*) into _total
  from public.behavior_pings
  where user_id = _user and at > now() - interval '30 days';

  if _total < 30 then
    return _cold;  -- 数据不足/学习期：维持冷启动阈值
  end if;

  select extract(hour from max(at))::int into _last_hour
  from public.behavior_pings
  where user_id = _user and at > now() - interval '30 days';

  with ev as (
    select at, lag(at) over (order by at) as prev
    from public.behavior_pings
    where user_id = _user and at > now() - interval '30 days'
  ),
  gaps as (
    select extract(hour from prev)::int as start_hour,
           extract(epoch from (at - prev)) as gap_sec
    from ev where prev is not null and at > prev
  )
  select
    percentile_cont(0.9) within group (order by gap_sec),
    count(*) filter (where start_hour = _last_hour),
    percentile_cont(0.9) within group (order by gap_sec) filter (where start_hour = _last_hour)
  into _global, _hourly_n, _hourly
  from gaps;

  _expected := case when coalesce(_hourly_n, 0) >= 3 then _hourly else _global end;
  if _expected is null then return _cold; end if;
  _expected := greatest(_floor_s, least(_cap_s, _expected * _mult));
  return make_interval(secs => _expected::int);
end;
$$;

revoke execute on all functions in schema private from public;
grant execute on all functions in schema private to authenticated;

-- process_escalations：创建条件从"一刀切 18h"改为"超过该用户此时段的常态阈值"
create or replace function public.process_escalations()
returns void language plpgsql security definer set search_path = '' as $$
declare
  _self_grace constant interval := interval '30 minutes';
  _group_dur  constant interval := interval '1 hour';
  _comm_dur   constant interval := interval '2 hours';
  r record;
  _aid uuid;
  _new text;
begin
  for r in
    select ds.user_id,
           (now() - ds.last_heartbeat_at) > interval '18 hours' as is_dark
    from public.device_state ds
    where (ds.status = 'alert'
           or (now() - ds.last_heartbeat_at) > private.silence_threshold(ds.user_id))
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