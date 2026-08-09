-- Make the user-visible routine threshold match the real alert path:
-- dynamic routine profile -> sensitivity scaling -> sleep-window gate.

create or replace function private.silence_threshold(_user_id uuid)
returns interval language plpgsql security definer set search_path to '' stable as $$
declare
  _s text;
  _timezone text;
  _threshold double precision;
  _multiplier double precision;
  _hour int;
  _is_weekend boolean;
  _factor double precision;
  _floor double precision;
begin
  select sensitivity, timezone
    into _s, _timezone
    from public.user_settings
   where user_id = _user_id;

  _s := coalesce(_s, 'balanced');
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

    _factor := case _s
      when 'high' then 0.65
      when 'low' then 1.60
      else 1.00
    end;
    _floor := case _s
      when 'high' then 1.25
      when 'low' then 3.00
      else 1.50
    end;

    _threshold := least(12.0, greatest(_floor, _threshold * _factor));
    return _threshold * interval '1 hour';
  end if;

  return case _s
    when 'high' then interval '1.5 hours'
    when 'low' then interval '6 hours'
    else interval '3 hours'
  end;
end;
$$;

create or replace function public.my_routine_status()
returns jsonb language plpgsql security definer set search_path to '' stable as $$
declare
  _uid uuid := auth.uid();
  _threshold interval;
  _last_at timestamptz;
  _s text;
  _sleep_start time;
  _sleep_end time;
  _timezone text;
  _in_sleep_window boolean;
begin
  if _uid is null then raise exception 'not authenticated'; end if;

  select sensitivity, sleep_start_utc, sleep_end_utc, timezone
    into _s, _sleep_start, _sleep_end, _timezone
    from public.user_settings
   where user_id = _uid;

  _threshold := private.silence_threshold(_uid);
  _in_sleep_window := private.is_in_sleep_window(_uid, now());

  select max(at)
    into _last_at
    from public.behavior_pings
   where user_id = _uid;

  return jsonb_build_object(
    'threshold_seconds', extract(epoch from _threshold)::bigint,
    'last_behavior_at', _last_at,
    'sensitivity', coalesce(_s, 'balanced'),
    'sleep_start', _sleep_start,
    'sleep_end', _sleep_end,
    'timezone', coalesce(_timezone, 'UTC'),
    'in_sleep_window', coalesce(_in_sleep_window, false)
  );
end;
$$;

revoke execute on function public.my_routine_status() from public, anon;
grant execute on function public.my_routine_status() to authenticated;
