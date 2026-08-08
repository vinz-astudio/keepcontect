-- 1. Add timezone column to public.user_settings
alter table public.user_settings
  add column if not exists timezone text not null default 'UTC';

-- 2. Ensure cron secret exists in private.app_config
insert into private.app_config (key, value)
values ('cron_secret', encode(gen_random_bytes(16), 'hex'))
on conflict (key) do nothing;

-- 3. Create function to initialize/seed user routine aggregates
create or replace function public.initialize_user_routine_data(_user_id uuid)
returns void language plpgsql security definer set search_path to '' as $$
declare
  _pattern text;
  _date date;
  _hourly_density integer[];
  _d int;
  _h int;
  _is_weekend boolean;
  _val int;
  _month int;
  _is_break boolean;
begin
  -- Fetch current pattern
  select routine_pattern into _pattern from public.profiles where id = _user_id;
  _pattern := coalesce(_pattern, 'regular_9to5');

  -- Delete existing aggregates to prevent duplicates
  delete from public.daily_activity_aggregates where user_id = _user_id;

  -- Generate 180 days of data ending yesterday
  for _d in 1..180 loop
    _date := current_date - _d;
    _is_weekend := extract(isodow from _date) in (6, 7);
    _month := extract(month from _date)::int;
    
    -- Determine if it's a break month (July, August, January) for semester_break
    _is_break := (_month in (1, 7, 8));

    _hourly_density := array_fill(0, array[24]);

    for _h in 0..23 loop
      _val := 0;
      if _pattern = 'regular_9to5' then
        if _is_weekend then
          -- Weekend: Sleep 01:00 - 09:00
          if _h >= 9 or _h = 0 then
            _val := floor(random() * 8 + 2)::int; -- random 2 to 9 pings
          end if;
        else
          -- Weekday: Sleep 23:00 - 07:00
          if _h >= 7 and _h < 23 then
            if _h in (8, 9, 12, 13, 17, 18, 21, 22) then
              _val := floor(random() * 12 + 8)::int; -- Peak commute/lunch/evening hours
            else
              _val := floor(random() * 5 + 3)::int; -- Standard work hours
            end if;
          end if;
        end if;

      elsif _pattern = 'semester_break' then
        if _is_break then
          -- Vacation: sleep 02:00 - 10:00
          if _h >= 10 or _h < 2 then
            _val := floor(random() * 6 + 1)::int;
          end if;
        else
          -- Semester: active 08:00 - 23:00
          if _h >= 8 and _h < 23 then
            if _h in (9, 10, 14, 15, 19, 20) then
              _val := floor(random() * 10 + 6)::int; -- Class and dinner times
            else
              _val := floor(random() * 6 + 2)::int;
            end if;
          end if;
        end if;

      else -- shift_irregular
        -- Shift work / irregular: active at erratic hours
        -- We model this by alternating active hours on different days
        if ((_d % 3 = 0 and (_h >= 0 and _h < 8)) or (_d % 3 <> 0 and (_h >= 8 and _h < 24))) then
          _val := floor(random() * 7 + 1)::int;
        end if;
      end if;

      _hourly_density[_h + 1] := _val;
    </loop>

    insert into public.daily_activity_aggregates (user_id, date, hourly_density)
    values (_user_id, _date, _hourly_density)
    on conflict (user_id, date) do nothing;
  end loop;
end;
$$;

-- 4. Create function to trigger single user routine update via Edge Function
create or replace function private.trigger_update_routine_profile(_user_id uuid)
returns void language plpgsql security definer set search_path to '' as $$
declare
  _secret text;
  _payload jsonb;
begin
  select value into _secret from private.app_config where key = 'cron_secret';
  _payload := jsonb_build_object('user_id', _user_id);
  perform net.http_post(
    url := 'https://byekgmqyqlftgoveqnku.supabase.co/functions/v1/update-routine-profile',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || _secret
    ),
    body := _payload
  );
exception when others then
  -- Fail silently to avoid blocking transaction
  null;
end;
$$;

-- 5. Create trigger to seed data & invoke Edge Function on profile routine pattern changes
create or replace function private.handle_profile_pattern_change()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if tg_op = 'INSERT' or new.routine_pattern <> old.routine_pattern then
    -- 1) Seed the aggregates data
    perform public.initialize_user_routine_data(new.id);
    -- 2) Call Edge Function to analyze routine pattern
    perform private.trigger_update_routine_profile(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists on_profile_pattern_change on public.profiles;
create trigger on_profile_pattern_change
  after insert or update of routine_pattern on public.profiles
  for each row execute function private.handle_profile_pattern_change();

-- 6. Create function to aggregate a single user's pings for a specific local date
create or replace function private.aggregate_user_daily_activity(_user_id uuid, _date date)
returns void language plpgsql security definer set search_path to '' as $$
declare
  _timezone text;
  _hourly_density integer[] := array_fill(0, array[24]);
  _ping record;
  _hour int;
begin
  -- Fetch user timezone
  select timezone into _timezone from public.user_settings where user_id = _user_id;
  _timezone := coalesce(_timezone, 'UTC');

  -- Count pings per local hour for the specified local date
  for _ping in
    select extract(hour from at at time zone _timezone)::int as hr
    from public.behavior_pings
    where user_id = _user_id
      and (at at time zone _timezone)::date = _date
  loop
    _hour := _ping.hr;
    if _hour >= 0 and _hour <= 23 then
      _hourly_density[_hour + 1] := _hourly_density[_hour + 1] + 1;
    end if;
  end loop;

  -- Upsert aggregate row
  insert into public.daily_activity_aggregates (user_id, date, hourly_density)
  values (_user_id, _date, _hourly_density)
  on conflict (user_id, date) do update
    set hourly_density = excluded.hourly_density;
end;
$$;

-- 7. Create nightly aggregation runner
create or replace function public.run_daily_aggregations()
returns void language plpgsql security definer set search_path to '' as $$
declare
  _user record;
  _timezone text;
  _yesterday date;
begin
  for _user in select id from auth.users loop
    select timezone into _timezone from public.user_settings where user_id = _user.id;
    _timezone := coalesce(_timezone, 'UTC');
    
    -- Yesterday in user's timezone
    _yesterday := (now() at time zone _timezone)::date - 1;
    
    perform private.aggregate_user_daily_activity(_user.id, _yesterday);
  end loop;
end;
$$;

-- 8. Create function to trigger weekly routine updates via Edge Function
create or replace function public.trigger_weekly_routine_updates()
returns void language plpgsql security definer set search_path to '' as $$
declare
  _secret text;
begin
  select value into _secret from private.app_config where key = 'cron_secret';
  perform net.http_post(
    url := 'https://byekgmqyqlftgoveqnku.supabase.co/functions/v1/update-routine-profile',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || _secret
    ),
    body := '{}'::jsonb
  );
exception when others then
  -- Fail silently to avoid blocking transaction
  null;
end;
$$;

-- 9. Redefine silence_threshold to look up thresholds dynamically from user_activity_profiles
create or replace function private.silence_threshold(_user_id uuid)
returns interval language plpgsql security definer set search_path to '' stable as $$
declare
  _s text;
  _timezone text;
  _threshold double precision;
  _multiplier double precision;
  _hour int;
  _is_weekend boolean;
begin
  -- Try to fetch dynamic AI/rule thresholds
  select timezone into _timezone from public.user_settings where user_id = _user_id;
  _timezone := coalesce(_timezone, 'UTC');
  
  _hour := extract(hour from now() at time zone _timezone)::int;
  
  select hourly_thresholds[_hour + 1], weekend_multiplier
  into _threshold, _multiplier
  from public.user_activity_profiles
  where user_id = _user_id;
  
  if _threshold is not null then
    _is_weekend := extract(isodow from now() at time zone _timezone) in (6, 7);
    if _is_weekend then
      _threshold := _threshold * coalesce(_multiplier, 1.0);
    end if;
    return _threshold * interval '1 hour';
  end if;
  
  -- Fallback to static sensitivity setting
  select sensitivity into _s from public.user_settings where user_id = _user_id;
  return case coalesce(_s, 'balanced')
    when 'high' then interval '1.5 hours'
    when 'low' then interval '6 hours'
    else interval '3 hours'
  end;
end;
$$;

-- 10. Setup pg_cron schedules
do $$
declare _jobid bigint;
begin
  select jobid into _jobid from cron.job where jobname = 'run-daily-aggregations';
  if _jobid is not null then perform cron.unschedule(_jobid); end if;
  perform cron.schedule('run-daily-aggregations', '5 0 * * *', '$cron$ select public.run_daily_aggregations(); $cron$');
end $$;

do $$
declare _jobid bigint;
begin
  select jobid into _jobid from cron.job where jobname = 'update-routine-profiles-weekly';
  if _jobid is not null then perform cron.unschedule(_jobid); end if;
  perform cron.schedule('update-routine-profiles-weekly', '0 1 * * 0', '$cron$ select public.trigger_weekly_routine_updates(); $cron$');
end $$;
