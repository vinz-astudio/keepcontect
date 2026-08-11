-- 用户设置（灵敏度）同步到服务器，让 silence_threshold 用用户自选档而非固定 1.8 倍。
create table public.user_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  sensitivity text not null default 'balanced' check (sensitivity in ('high', 'balanced', 'low')),
  updated_at timestamptz not null default now()
);
alter table public.user_settings enable row level security;
create policy user_settings_select on public.user_settings
  for select to authenticated using ((select auth.uid()) = user_id);

create or replace function public.set_sensitivity(_s text)
returns void language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if _s not in ('high', 'balanced', 'low') then raise exception 'bad sensitivity'; end if;
  insert into public.user_settings (user_id, sensitivity, updated_at)
  values (_uid, _s, now())
  on conflict (user_id) do update set sensitivity = excluded.sensitivity, updated_at = now();
end;
$$;
revoke execute on function public.set_sensitivity(text) from public, anon;
grant execute on function public.set_sensitivity(text) to authenticated;

-- silence_threshold 改为读用户灵敏度档（倍数 + 下限 + 冷启动阈值都随档变）
create or replace function private.silence_threshold(_user uuid)
returns interval language plpgsql security definer set search_path = '' stable as $$
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
    _mult := 1.3; _floor_s := 5400;  _cold := interval '14 hours';   -- 1.5h floor
  elsif _sens = 'low' then
    _mult := 2.6; _floor_s := 21600; _cold := interval '24 hours';   -- 6h floor
  else
    _mult := 1.8; _floor_s := 10800; _cold := interval '18 hours';   -- 3h floor
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
$$;