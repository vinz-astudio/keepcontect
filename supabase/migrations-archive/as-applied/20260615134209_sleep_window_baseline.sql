-- 显式睡眠窗（UTC 存储；客户端按设备本地时间换算）。null = 未设。
alter table public.user_settings
  add column if not exists sleep_start_utc time,
  add column if not exists sleep_end_utc time;

-- 是否应"放宽"：在睡眠窗内，或睡眠窗结束后 2 小时醒后宽限内。
create or replace function private.sleep_relaxed(_user uuid, _at timestamptz)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare _s time; _e time; _utc timestamp; _tod time; _end timestamp;
begin
  select sleep_start_utc, sleep_end_utc into _s, _e
  from public.user_settings where user_id = _user;
  if _s is null or _e is null or _s = _e then return false; end if;
  _utc := (_at at time zone 'UTC');  -- UTC 墙钟
  _tod := _utc::time;
  -- 睡眠窗内（处理跨午夜）
  if _s < _e then
    if _tod >= _s and _tod < _e then return true; end if;
  else
    if _tod >= _s or _tod < _e then return true; end if;
  end if;
  -- 醒后宽限 2h：最近一次睡眠结束时刻
  _end := date_trunc('day', _utc) + _e;
  if _end > _utc then _end := _end - interval '1 day'; end if;
  if _utc - _end < interval '2 hours' then return true; end if;
  return false;
end; $$;

-- 时段感知阈值：睡眠/醒后宽限期放宽到上限；清醒期沿用学习/冷启动。
create or replace function private.silence_threshold(_user uuid)
returns interval language plpgsql stable security definer set search_path = '' as $function$
declare
  _cap_s    constant numeric := 86400;     -- 上限 24h
  _sens     text;
  _mult     numeric;
  _floor_s  numeric;
  _cold     interval;
  _total    int;
  _last_hour int;
  _global   numeric;
  _hourly   numeric;
  _hourly_n int;
  _expected numeric;
begin
  select coalesce(sensitivity, 'balanced') into _sens
  from public.user_settings where user_id = _user;
  _sens := coalesce(_sens, 'balanced');

  if _sens = 'high' then
    _mult := 1.3; _floor_s := 5400;  _cold := interval '14 hours';
  elsif _sens = 'low' then
    _mult := 2.6; _floor_s := 21600; _cold := interval '24 hours';
  else
    _mult := 1.8; _floor_s := 10800; _cold := interval '18 hours';
  end if;

  -- 睡眠窗 / 醒后宽限：放宽到上限，夜里不误报（任何数据量下都生效）
  if private.sleep_relaxed(_user, now()) then
    return make_interval(secs => _cap_s::int);
  end if;

  select count(*) into _total
  from public.behavior_pings
  where user_id = _user and at > now() - interval '30 days';

  if _total < 30 then
    return _cold;
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
$function$;

-- 本人设置睡眠窗（传 null 即关闭）
create or replace function public.set_sleep_window(_start time, _end time)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  insert into public.user_settings (user_id, sleep_start_utc, sleep_end_utc)
  values (auth.uid(), _start, _end)
  on conflict (user_id) do update
    set sleep_start_utc = excluded.sleep_start_utc,
        sleep_end_utc = excluded.sleep_end_utc,
        updated_at = now();
end; $$;
revoke execute on function public.set_sleep_window(time, time) from public, anon;
grant execute on function public.set_sleep_window(time, time) to authenticated;