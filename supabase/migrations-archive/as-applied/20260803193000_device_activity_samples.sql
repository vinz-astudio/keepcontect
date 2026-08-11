-- Multi-signal liveness sampling (KC-IOS-HEALTHWAKE-SPIKE-001 follow-on).
-- Shadow-only. Nothing here feeds alert judgement: the composite scoring cannot
-- be written until there is real data to calibrate it against.
-- Every signal column is nullable, and null means "this device or this build
-- could not read it" rather than "zero".

create table if not exists public.device_activity_samples (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  trigger text not null check (trigger in (
    'push-wake', 'health-wake', 'location-relaunch', 'foreground', 'unlock'
  )),
  observed_at timestamptz not null,
  received_at timestamptz not null default now(),

  -- Operation-class signals: evidence a human worked the device.
  protected_data_available boolean,
  battery_level real check (battery_level is null or (battery_level >= 0 and battery_level <= 1)),
  battery_state text check (battery_state is null or battery_state in ('unknown', 'unplugged', 'charging', 'full')),
  low_power_mode boolean,
  pasteboard_change_count bigint,
  system_uptime_seconds double precision,
  other_audio_playing boolean,
  motion_variance double precision,
  motion_sample_count integer,

  -- Motion-class signals: evidence a person moved. Kept apart on purpose --
  -- a phone forgotten in a moving vehicle produces motion and no operation.
  steps_since_last_sample integer,
  floors_since_last_sample integer,
  dominant_activity text check (dominant_activity is null or dominant_activity in (
    'stationary', 'walking', 'running', 'cycling', 'automotive', 'unknown'
  )),
  activity_confidence smallint check (activity_confidence is null or activity_confidence between 0 and 2),

  volume_available_bytes bigint,

  client_id text,
  app_version text,
  collector_contract text not null,
  always_unlocked_suspect boolean
);

create index if not exists device_activity_samples_user_time_idx
  on public.device_activity_samples (user_id, observed_at desc);

create index if not exists device_activity_samples_trigger_idx
  on public.device_activity_samples (trigger, observed_at desc);

-- No policies on purpose: these readings are richer than anything else KC
-- stores about a device, so nothing client-side may read them back.
alter table public.device_activity_samples enable row level security;

comment on table public.device_activity_samples is
  'Shadow-only multi-signal liveness sampling. Never feeds alert judgement. A null signal column means the device or build could not read it, not that the value was zero.';

create or replace function private.insert_device_sample(
  _user_id uuid,
  _event_id uuid,
  _payload jsonb
) returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
  _observed_at timestamptz;
  _received_at timestamptz := clock_timestamp();
  _trigger text;
begin
  if _user_id is null or _event_id is null or _payload is null then
    return 'invalid';
  end if;

  _observed_at := (_payload ->> 'observed_at')::timestamptz;
  _trigger := _payload ->> 'trigger';

  if _observed_at is null or _trigger is null then
    return 'invalid';
  end if;

  -- A sample claiming to be from the future is a clock problem, not evidence.
  -- No lower bound: backfilled samples are normal here and carry no
  -- live-safety authority to abuse.
  if _observed_at > _received_at + interval '5 minutes' then
    return 'invalid';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(_user_id::text || ':sample:' || _event_id::text, 0)
  );

  if exists (
    select 1 from public.device_activity_samples
    where user_id = _user_id and id = _event_id
  ) then
    return 'duplicate';
  end if;

  insert into public.device_activity_samples (
    id, user_id, trigger, observed_at, received_at,
    protected_data_available, battery_level, battery_state, low_power_mode,
    pasteboard_change_count, system_uptime_seconds, other_audio_playing,
    motion_variance, motion_sample_count,
    steps_since_last_sample, floors_since_last_sample,
    dominant_activity, activity_confidence,
    volume_available_bytes,
    client_id, app_version, collector_contract
  ) values (
    _event_id, _user_id, _trigger, _observed_at, _received_at,
    (_payload ->> 'protected_data_available')::boolean,
    (_payload ->> 'battery_level')::real,
    _payload ->> 'battery_state',
    (_payload ->> 'low_power_mode')::boolean,
    (_payload ->> 'pasteboard_change_count')::bigint,
    (_payload ->> 'system_uptime_seconds')::double precision,
    (_payload ->> 'other_audio_playing')::boolean,
    (_payload ->> 'motion_variance')::double precision,
    (_payload ->> 'motion_sample_count')::integer,
    (_payload ->> 'steps_since_last_sample')::integer,
    (_payload ->> 'floors_since_last_sample')::integer,
    _payload ->> 'dominant_activity',
    (_payload ->> 'activity_confidence')::smallint,
    (_payload ->> 'volume_available_bytes')::bigint,
    _payload ->> 'client_id',
    _payload ->> 'app_version',
    coalesce(_payload ->> 'collector_contract', 'unknown')
  );

  return 'inserted';
exception
  when check_violation or invalid_text_representation then
    -- A malformed field must not land as a half-truth; rejecting loudly keeps
    -- the null-means-unreadable contract honest.
    return 'invalid';
end;
$function$;

revoke all on function private.insert_device_sample(uuid, uuid, jsonb) from public;

-- PostgREST can only reach the public schema, so the edge function needs this
-- thin wrapper. It takes the user id as an argument rather than reading
-- auth.uid(): the caller is a service-role function that has already resolved
-- the heartbeat token, exactly as record_behavior_ping_for_user does.
create or replace function public.record_device_sample_for_user(
  _user_id uuid,
  _event_id uuid,
  _payload jsonb
) returns text
language plpgsql
security definer
set search_path to ''
as $function$
begin
  return private.insert_device_sample(_user_id, _event_id, _payload);
end;
$function$;

-- Only the service role calls this. A signed-in client reaching it directly
-- could write samples for itself, which would let a device manufacture its own
-- evidence trail.
revoke all on function public.record_device_sample_for_user(uuid, uuid, jsonb) from public;
revoke all on function public.record_device_sample_for_user(uuid, uuid, jsonb) from anon, authenticated;