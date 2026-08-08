-- Migration: Add sleep_start_local and sleep_end_local columns, backfill from UTC columns, and update functions to use local sleep columns
-- ID: 20260716120000

-- 1) Add local columns to public.user_settings
ALTER TABLE public.user_settings ADD COLUMN sleep_start_local time DEFAULT NULL;
ALTER TABLE public.user_settings ADD COLUMN sleep_end_local time DEFAULT NULL;

-- 2) Backfill existing rows using current_date (behavior-preserving at migration time)
UPDATE public.user_settings
SET 
  sleep_start_local = CASE 
    WHEN sleep_start_utc IS NOT NULL THEN (((current_date + sleep_start_utc) at time zone 'UTC') at time zone coalesce(timezone, 'UTC'))::time 
    ELSE NULL 
  END,
  sleep_end_local = CASE 
    WHEN sleep_end_utc IS NOT NULL THEN (((current_date + sleep_end_utc) at time zone 'UTC') at time zone coalesce(timezone, 'UTC'))::time 
    ELSE NULL 
  END
WHERE sleep_start_utc IS NOT NULL OR sleep_end_utc IS NOT NULL;

-- 3) Rewrite private.is_in_sleep_window to read sleep_start_local, sleep_end_local and delete conversion lines
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
  select sleep_start_local, sleep_end_local, coalesce(timezone, 'UTC')
    into _start, _end, _timezone
    from public.user_settings
   where user_id = _user_id;

  if _start is null or _end is null then
    return false;
  end if;

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
end; $function$;

-- 4) Rewrite public.my_routine_status to read sleep_start_local, sleep_end_local and delete conversion lines
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

  select sensitivity, sleep_start_local, sleep_end_local, timezone
    into _s, _sleep_start, _sleep_end, _timezone
    from public.user_settings
   where user_id = _uid;

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
end; $function$;

-- 5) Rewrite private.sleep_relaxed in local tod with 2-hour post-wake grace
-- (parameter stays `_user` — CREATE OR REPLACE cannot rename the deployed function's parameter)
CREATE OR REPLACE FUNCTION private.sleep_relaxed(_user uuid, _at timestamp with time zone)
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
  _wake_ts    timestamptz;
begin
  select sleep_start_local, sleep_end_local, coalesce(timezone, 'UTC')
    into _start, _end, _timezone
    from public.user_settings
   where user_id = _user;

  if _start is null or _end is null then
    return false;
  end if;

  -- Convert _at to user's local timezone (wall-clock)
  _local_now  := _at at time zone _timezone;
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

  -- If currently inside the sleep window
  if _at >= _start_ts and _at < _end_ts then
    return true;
  end if;

  -- Check 2-hour post-wake grace period
  _wake_ts := (_local_date + _end) at time zone _timezone;
  if _wake_ts > _at then
    _wake_ts := _wake_ts - interval '1 day';
  end if;

  if _at >= _wake_ts and _at - _wake_ts < interval '2 hours' then
    return true;
  end if;

  return false;
end; $function$;

-- 6) Rewrite set_sleep_window: store directly, add _tz parameter, and update timezone
DROP FUNCTION IF EXISTS public.set_sleep_window(time, time);
CREATE OR REPLACE FUNCTION public.set_sleep_window(
  _start time DEFAULT NULL,
  _end time DEFAULT NULL,
  _tz text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
declare
  _uid uuid := auth.uid();
  _existing_tz text;
begin
  if _uid is null then
    raise exception 'not authenticated';
  end if;

  -- TRANSITION SHIM: Pre-wall-clock clients never send _tz. If they set a window,
  -- they send UTC time-of-day digits. We convert these to local digits using their stored timezone.
  -- This shim should be removed in a future ADR once old clients age out.
  if _tz is null and _start is not null and _end is not null then
    select timezone into _existing_tz from public.user_settings where user_id = _uid;
    _start := (((current_date + _start) at time zone 'UTC') at time zone coalesce(_existing_tz, 'UTC'))::time;
    _end   := (((current_date + _end)   at time zone 'UTC') at time zone coalesce(_existing_tz, 'UTC'))::time;
  end if;

  insert into public.user_settings (user_id, sleep_start_local, sleep_end_local, timezone, updated_at)
  values (_uid, _start, _end, coalesce(_tz, 'UTC'), now())
  on conflict (user_id) do update
    set sleep_start_local = excluded.sleep_start_local,
        sleep_end_local = excluded.sleep_end_local,
        timezone = case when _tz is not null then excluded.timezone else user_settings.timezone end,
        updated_at = now();
end;
$$;

REVOKE EXECUTE ON FUNCTION public.set_sleep_window(time, time, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.set_sleep_window(time, time, text) TO authenticated;
