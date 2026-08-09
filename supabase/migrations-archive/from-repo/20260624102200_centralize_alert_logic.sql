-- #1 Define silence_threshold to return user's custom baseline duration based on sensitivity setting
create or replace function private.silence_threshold(_user_id uuid)
returns interval language plpgsql security definer set search_path to '' stable as $$
declare _s text;
begin
  select sensitivity into _s from public.user_settings where user_id = _user_id;
  return case coalesce(_s, 'balanced')
    when 'high' then interval '1.5 hours'
    when 'low' then interval '6 hours'
    else interval '3 hours'
  end;
end;
$$;

-- #2 Define dynamic sleep window calculation
create or replace function private.is_in_sleep_window(_user_id uuid, _now timestamptz)
returns boolean language plpgsql security definer set search_path to '' stable as $$
declare
  _start time; _end time;
  _now_utc timestamptz;
  _date date;
  _start_ts timestamptz;
  _end_ts timestamptz;
  _dur interval;
  _last_active timestamptz;
  _dynamic_end timestamptz;
begin
  select sleep_start_utc, sleep_end_utc into _start, _end
    from public.user_settings where user_id = _user_id;
  if _start is null or _end is null then
    return false;
  end if;

  _now_utc := _now at time zone 'UTC';
  _date := _now_utc::date;

  if _start > _end then
    if _now_utc::time < _end then
      _start_ts := (_date - 1 + _start) at time zone 'UTC';
      _end_ts := (_date + _end) at time zone 'UTC';
    else
      _start_ts := (_date + _start) at time zone 'UTC';
      _end_ts := (_date + 1 + _end) at time zone 'UTC';
    end if;
  else
    if _now_utc::time < _start then
      _start_ts := (_date - 1 + _start) at time zone 'UTC';
      _end_ts := (_date - 1 + _end) at time zone 'UTC';
    else
      _start_ts := (_date + _start) at time zone 'UTC';
      _end_ts := (_date + _end) at time zone 'UTC';
    end if;
  end if;

  _dur := _end_ts - _start_ts;

  -- 取得用户最近的行为 ping 时间
  select max(at) into _last_active
    from public.behavior_pings
    where user_id = _user_id;

  if _last_active is not null then
    -- 如果最近活动在 [开始前 1 小时, 结束时间] 范围内，说明此活动属于该睡眠周期的晚睡或中途醒来
    if _last_active >= _start_ts - interval '1 hour' and _last_active <= _end_ts then
      -- 动态延长结束时间为：最后活动时间 + 睡眠窗时长，但最多延长 3 小时
      _dynamic_end := least(_last_active + _dur, _end_ts + interval '3 hours');
      return _now >= _start_ts and _now < _dynamic_end;
    end if;
  end if;

  -- 默认：严格按设定的时间段判定
  return _now >= _start_ts and _now < _end_ts;
end;
$$;

-- #3 Define instant push-dispatch trigger
create or replace function private.trigger_push_dispatch()
returns void language plpgsql security definer set search_path to '' as $$
begin
  perform net.http_post(
    url := 'https://byekgmqyqlftgoveqnku.supabase.co/functions/v1/push-dispatch',
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := '{}'::jsonb
  );
exception when others then
  -- Fail silently to avoid blocking parent transaction
  null;
end;
$$;

-- #4 Redefine process_escalations to check behavior pings instead of ds.last_heartbeat_at
create or replace function public.process_escalations()
returns void language plpgsql security definer set search_path to '' as $$
declare
  _self_grace constant interval := interval '30 minutes';
  _group_dur  constant interval := interval '1 hour';
  _comm_dur   constant interval := interval '2 hours';
  r record; _aid uuid; _new text; _triggered boolean := false;
begin
  for r in
    select ds.user_id,
           (now() - ds.last_heartbeat_at) > interval '18 hours' as is_dark
    from public.device_state ds
    where (
      ds.status = 'alert'
      or now() - ds.last_heartbeat_at > interval '18 hours'
      or (
        not private.is_in_sleep_window(ds.user_id, now())
        and now() - (
          select coalesce(max(at), to_timestamp(0))
          from public.behavior_pings
          where user_id = ds.user_id
        ) > private.silence_threshold(ds.user_id)
      )
    )
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
    _triggered := true;
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
      set stage = _new, stage_entered_at = now(), paused_until = null, paused_by = null, updated_at = now(),
          next_deadline = case _new when 'group' then now() + _group_dur
                                    when 'community' then now() + _comm_dur
                                    else null end
      where id = r.id;
    insert into public.alert_events (alert_id, kind, note) values (r.id, 'escalated', _new);
    perform private.notify_stage(r.id, r.user_id, _new);
    _triggered := true;
  end loop;

  if _triggered then
    perform private.trigger_push_dispatch();
  end if;
end;
$$;

-- #5 Define trigger function to auto-update device state and resolve alerts on behavior ping insert
create or replace function private.handle_behavior_ping_insert()
returns trigger language plpgsql security definer set search_path to '' as $$
declare _stale record; _triggered boolean := false;
begin
  -- 1) 更新心跳状态为正常
  insert into public.device_state (user_id, status, last_heartbeat_at, updated_at)
  values (new.user_id, 'normal', new.at, now())
  on conflict (user_id) do update
    set status = 'normal', last_heartbeat_at = new.at, updated_at = now();

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

drop trigger if exists on_behavior_ping_insert on public.behavior_pings;
create trigger on_behavior_ping_insert
  after insert on public.behavior_pings
  for each row execute function private.handle_behavior_ping_insert();

-- #6 Update RPCs to trigger push dispatch immediately
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

create or replace function public.resolve_my_alert()
returns void language plpgsql security definer set search_path to '' as $$
declare _uid uuid := auth.uid(); _aid uuid;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  update public.alerts set status = 'resolved', resolved_at = now(), resolved_by = _uid, updated_at = now()
    where user_id = _uid and status = 'open' returning id into _aid;
  if _aid is not null then
    insert into public.alert_events (alert_id, actor_id, kind) values (_aid, _uid, 'resolved');
  end if;
  -- 同步设备状态为正常
  insert into public.device_state (user_id, status, last_heartbeat_at, updated_at)
  values (_uid, 'normal', now(), now())
  on conflict (user_id) do update set status = 'normal', last_heartbeat_at = now(), updated_at = now();

  perform private.trigger_push_dispatch();
end;
$$;

create or replace function public.raise_sos()
returns uuid language plpgsql security definer set search_path to '' as $$
declare _uid uuid := auth.uid(); _aid uuid;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  select id into _aid from public.alerts where user_id = _uid and status = 'open';
  if _aid is null then
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    values (_uid, 'sos', 'group', now(), now() + interval '1 hour')
    returning id into _aid;
    insert into public.alert_events (alert_id, actor_id, kind) values (_aid, _uid, 'raised');
  else
    update public.alerts set cause = 'sos', stage = 'group', stage_entered_at = now(),
      next_deadline = now() + interval '1 hour', paused_until = null, updated_at = now()
      where id = _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note) values (_aid, _uid, 'escalated', 'sos');
  end if;
  perform private.notify_stage(_aid, _uid, 'group');

  perform private.trigger_push_dispatch();
  return _aid;
end;
$$;
