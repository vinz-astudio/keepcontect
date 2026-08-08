-- Sleep window stored as UTC times-of-day (set_sleep_window converts local->UTC),
-- but private.is_in_sleep_window and public.my_routine_status were treating the
-- stored values as LOCAL times-of-day. Result: the alert-pause window (and its UI
-- label) was offset by the user's UTC offset (e.g. Asia/Thimphu sleep 23:00-07:00
-- behaved as 17:00-01:00 local — pausing alerts in the evening, missing real
-- early-morning sleep). Fix: convert the stored UTC time-of-day to the user's
-- local time-of-day before the existing local-date anchoring / display.
CREATE OR REPLACE FUNCTION private.is_in_sleep_window(_user_id uuid, _now timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _start      time;
  _end        time;
  _timezone   text;
  _local_now  timestamptz;
  _local_time time;
  _local_date date;
  _start_ts   timestamptz;
  _end_ts     timestamptz;
  _dur        interval;
  _last_active    timestamptz;
  _dynamic_end    timestamptz;
begin
  select sleep_start_utc, sleep_end_utc, coalesce(timezone, 'UTC')
    into _start, _end, _timezone
    from public.user_settings
   where user_id = _user_id;

  if _start is null or _end is null then
    return false;
  end if;

  -- Stored sleep_start_utc/sleep_end_utc are UTC times-of-day; convert to the
  -- user's LOCAL time-of-day so the local-date anchoring below is correct.
  _start := (((current_date + _start) at time zone 'UTC') at time zone _timezone)::time;
  _end   := (((current_date + _end)   at time zone 'UTC') at time zone _timezone)::time;

  -- Convert _now into user's local timezone (wall-clock)
  _local_now  := _now at time zone _timezone;
  _local_time := _local_now::time;
  _local_date := _local_now::date;

  -- Build start/end timestamps anchored to local date, handling overnight windows
  if _start > _end then
    -- Overnight (e.g. 23:00 -> 07:00)
    if _local_time < _end then
      _start_ts := (_local_date - 1 + _start) at time zone _timezone;
      _end_ts   := (_local_date     + _end  ) at time zone _timezone;
    else
      _start_ts := (_local_date     + _start) at time zone _timezone;
      _end_ts   := (_local_date + 1 + _end  ) at time zone _timezone;
    end if;
  else
    -- Same-day (e.g. 14:00 -> 16:00 nap)
    if _local_time < _start then
      _start_ts := (_local_date - 1 + _start) at time zone _timezone;
      _end_ts   := (_local_date - 1 + _end  ) at time zone _timezone;
    else
      _start_ts := (_local_date + _start) at time zone _timezone;
      _end_ts   := (_local_date + _end  ) at time zone _timezone;
    end if;
  end if;

  _dur := _end_ts - _start_ts;

  -- Dynamic extension: if user pinged shortly before sleep started
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
$function$;

CREATE OR REPLACE FUNCTION public.my_routine_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  _uid uuid := auth.uid();
  _threshold interval;
  _last_at timestamptz;
  _s text;
  _sleep_start time;
  _sleep_end time;
  _timezone text;
  _in_sleep_window boolean;
  _model_confidence double precision;
  _model_explanation text;
  _model_version text;
begin
  if _uid is null then raise exception 'not authenticated'; end if;

  select sensitivity, sleep_start_utc, sleep_end_utc, timezone
    into _s, _sleep_start, _sleep_end, _timezone
    from public.user_settings
   where user_id = _uid;

  -- Stored sleep times are UTC times-of-day; return them in the user's local
  -- time-of-day so the UI label matches what the user actually set.
  _sleep_start := (((current_date + _sleep_start) at time zone 'UTC') at time zone coalesce(_timezone, 'UTC'))::time;
  _sleep_end   := (((current_date + _sleep_end)   at time zone 'UTC') at time zone coalesce(_timezone, 'UTC'))::time;

  select model_confidence, model_explanation, model_version
    into _model_confidence, _model_explanation, _model_version
    from public.user_activity_profiles
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
    'in_sleep_window', coalesce(_in_sleep_window, false),
    'model_confidence', _model_confidence,
    'model_explanation', _model_explanation,
    'model_version', _model_version
  );
end;
$function$;
