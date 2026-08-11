-- Fix is_in_sleep_window to compare against user's LOCAL wall-clock time
-- instead of raw UTC. This means sleep_start_utc / sleep_end_utc are now
-- interpreted as "local time numbers" (e.g. 23:00 = 11 PM wherever you are),
-- and we convert now() into the user's timezone before comparing.
-- If the user's device auto-adjusts timezone when traveling, the stored
-- "23:00" will still mean 11 PM in the new location — no manual reconfiguration needed.

create or replace function private.is_in_sleep_window(_user_id uuid, _now timestamptz)
returns boolean language plpgsql security definer set search_path to '' stable as $$
declare
  _start      time;
  _end        time;
  _timezone   text;
  _local_now  timestamptz;   -- _now expressed in user's local tz
  _local_time time;          -- just the time portion
  _local_date date;
  _start_ts   timestamptz;
  _end_ts     timestamptz;
  _dur        interval;
  _last_active    timestamptz;
  _dynamic_end    timestamptz;
begin
  -- Load sleep window (stored as wall-clock local time numbers) and user timezone
  select sleep_start_utc, sleep_end_utc, coalesce(timezone, 'UTC')
    into _start, _end, _timezone
    from public.user_settings
   where user_id = _user_id;

  if _start is null or _end is null then
    return false;
  end if;

  -- Convert _now into user's local timezone
  _local_now  := _now at time zone _timezone;
  _local_time := _local_now::time;
  _local_date := _local_now::date;

  -- Build start/end timestamps in local tz, handling overnight windows (start > end)
  if _start > _end then
    -- Overnight window (e.g. 23:00 → 07:00)
    if _local_time < _end then
      -- We are in the early-morning half (after midnight)
      _start_ts := (_local_date - 1 + _start) at time zone _timezone;
      _end_ts   := (_local_date     + _end  ) at time zone _timezone;
    else
      _start_ts := (_local_date     + _start) at time zone _timezone;
      _end_ts   := (_local_date + 1 + _end  ) at time zone _timezone;
    end if;
  else
    -- Same-day window (e.g. 14:00 → 16:00 nap)
    if _local_time < _start then
      _start_ts := (_local_date - 1 + _start) at time zone _timezone;
      _end_ts   := (_local_date - 1 + _end  ) at time zone _timezone;
    else
      _start_ts := (_local_date + _start) at time zone _timezone;
      _end_ts   := (_local_date + _end  ) at time zone _timezone;
    end if;
  end if;

  _dur := _end_ts - _start_ts;

  -- Dynamic extension: if user was active shortly before sleep started
  -- (stayed up late or woke briefly), extend the window to match.
  select max(at) into _last_active
    from public.behavior_pings
   where user_id = _user_id;

  if _last_active is not null then
    if _last_active >= _start_ts - interval '1 hour' and _last_active <= _end_ts then
      _dynamic_end := least(_last_active + _dur, _end_ts + interval '3 hours');
      return _now >= _start_ts and _now < _dynamic_end;
    end if;
  end if;

  return _now >= _start_ts and _now < _end_ts;
end;
$$;
