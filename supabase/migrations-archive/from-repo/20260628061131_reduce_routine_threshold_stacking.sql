-- Reduce threshold stacking after observing active users still getting overly
-- wide current-hour thresholds. Keep sensitivity additive and cap the broad
-- weekend multiplier so it cannot dominate every weekend hour.

create or replace function private.silence_threshold(_user_id uuid)
returns interval language plpgsql security definer set search_path to '' stable as $$
declare
  _s text;
  _timezone text;
  _threshold double precision;
  _multiplier double precision;
  _hour int;
  _is_weekend boolean;
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
      _threshold := _threshold * least(coalesce(_multiplier, 1.0), 1.10);
    end if;

    -- Sensitivity is a user-facing tool, not another model layer:
    -- sensitive ~= neutral + 15m; balanced +30m; relaxed +90m.
    if _s = 'high' then
      _threshold := _threshold + 0.25;
      _floor := 1.0;
    elsif _s = 'low' then
      _threshold := _threshold + 1.5;
      _floor := 3.0;
    else
      _threshold := _threshold + 0.5;
      _floor := 2.0;
    end if;

    _threshold := least(12.0, greatest(_floor, _threshold));
    return _threshold * interval '1 hour';
  end if;

  return case _s
    when 'high' then interval '1.5 hours'
    when 'low' then interval '6 hours'
    else interval '3 hours'
  end;
end;
$$;
