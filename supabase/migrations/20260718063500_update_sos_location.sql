-- Migration: update_sos_location
-- Created: 2026-07-18

create or replace function public.update_sos_location(
  _lat double precision,
  _lng double precision
)
returns boolean language plpgsql security definer set search_path to '' as $$
declare
  _uid uuid := auth.uid();
begin
  -- 1. Explicit auth validation
  if _uid is null then
    raise exception 'not authenticated';
  end if;

  -- 2. Explicit null/NaN/infinite/out-of-range validation
  if _lat is null or _lng is null or
     _lat = 'NaN'::double precision or _lng = 'NaN'::double precision or
     _lat = 'Infinity'::double precision or _lat = '-Infinity'::double precision or
     _lng = 'Infinity'::double precision or _lng = '-Infinity'::double precision or
     not (_lat between -90 and 90) or
     not (_lng between -180 and 180)
  then
    raise exception 'invalid coordinates';
  end if;

  -- 3. Update caller-owned open SOS only (and only coords+updated_at)
  update public.alerts
  set
    sos_lat = _lat,
    sos_lng = _lng,
    updated_at = now()
  where
    user_id = _uid
    and status = 'open'
    and cause = 'sos';

  -- Return FOUND (boolean indicating if a row was updated)
  return FOUND;
end;
$$;

revoke execute on function public.update_sos_location(double precision, double precision) from public, anon;
grant execute on function public.update_sos_location(double precision, double precision) to authenticated;
