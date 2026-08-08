-- Multi-signal liveness sampling (KC-IOS-HEALTHWAKE-SPIKE-001 follow-on).
--
-- iOS gives a third-party app no way to ask "was this device operated in the
-- last half hour". Every direct answer to that question sits behind an
-- entitlement Apple has to approve. What is available instead is a handful of
-- indirect readings, each individually weak, that a background wake can take:
-- how fast the battery drained since the last wake, whether the pasteboard
-- counter moved, whether the phone is being held rather than lying flat.
--
-- Two of those properties matter more than the readings themselves:
--
--   * Several are *interval* evidence, not instantaneous. A battery level on
--     its own says nothing; the drop between two wakes summarises everything
--     that happened in between. Wakes are scarce, so interval evidence is worth
--     far more than a point sample.
--   * They fail independently. A phone lying on a table defeats motion; a phone
--     with no passcode defeats lock state; a stationary user in bed defeats
--     steps. Collecting them together is what makes the set useful.
--
-- This table is deliberately inert. Nothing here feeds alert judgement: the
-- composite scoring cannot be written until there is real data to calibrate it
-- against, and guessing at thresholds is what produced the false alerts this
-- work exists to fix. Collection first, judgement later, exactly as ADR-0029
-- required of the shadow pipeline.
--
-- Every signal column is nullable, and null means "this device or this build
-- could not read it" rather than "zero". That is the whole point of the shape:
-- one run on real hardware then tells us which of the nine signals are actually
-- available, instead of leaving us to guess why a number looks low.

create table if not exists public.device_activity_samples (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,

  -- Which wake produced this sample. The spike's primary question is whether
  -- 'health-wake' ever appears while the app is force-quit, so this column is
  -- the one the result is read off.
  trigger text not null check (trigger in (
    'push-wake',        -- silent push (passive-poll)
    'health-wake',      -- HealthKit background delivery
    'location-relaunch',-- significant location change
    'foreground',       -- user opened the app; the control case
    'unlock'            -- protectedDataDidBecomeAvailable, process happened to run
  )),

  observed_at timestamptz not null,
  received_at timestamptz not null default now(),

  -- —— Operation-class signals: evidence a human worked the device ——

  -- Instantaneous. Always true on a device with no passcode, which is why
  -- always_unlocked_suspect exists below rather than trusting this alone.
  protected_data_available boolean,

  -- Interval evidence. Idle drain sits near 1%/h; a screen held on runs an
  -- order of magnitude higher. Stored raw so the rate is derived server-side
  -- against the previous sample, where it can be recomputed if the model
  -- changes.
  battery_level real check (battery_level is null or (battery_level >= 0 and battery_level <= 1)),
  battery_state text check (battery_state is null or battery_state in ('unknown', 'unplugged', 'charging', 'full')),
  low_power_mode boolean,

  -- Interval evidence. A monotonic counter; only the delta is meaningful, and
  -- no pasteboard *content* is ever read. A rise means a human copied
  -- something, which no background process does on its own.
  pasteboard_change_count bigint,

  -- Interval evidence. A reset means the phone was restarted, which is a
  -- deliberate human act and one of the few unambiguous ones available.
  system_uptime_seconds double precision,

  -- Instantaneous. Covers the case motion cannot: someone lying still with a
  -- podcast or video running.
  other_audio_playing boolean,

  -- Instantaneous, sampled over a couple of seconds at wake. A phone resting on
  -- a surface has near-zero acceleration variance; a phone in a hand never
  -- does. This is the closest thing to "being operated right now" that needs no
  -- entitlement.
  motion_variance double precision,
  motion_sample_count integer,

  -- —— Motion-class signals: evidence a person moved ——
  -- Deliberately kept apart from the operation signals above. A phone forgotten
  -- in a moving vehicle produces motion and no operation, which is exactly the
  -- false positive that makes motion auxiliary rather than primary.

  steps_since_last_sample integer,
  floors_since_last_sample integer,   -- barometric; vehicle vibration cannot fake it
  dominant_activity text check (dominant_activity is null or dominant_activity in (
    'stationary', 'walking', 'running', 'cycling', 'automotive', 'unknown'
  )),
  activity_confidence smallint check (activity_confidence is null or activity_confidence between 0 and 2),

  -- —— Weak / experimental ——
  volume_available_bytes bigint,

  -- —— Provenance ——
  client_id text,
  app_version text,
  collector_contract text not null,

  -- Set server-side once a device has answered "unlocked" across enough wakes
  -- spanning enough of the night to make a passcode implausible. Nulls until
  -- there is enough history to judge.
  always_unlocked_suspect boolean
);

create index if not exists device_activity_samples_user_time_idx
  on public.device_activity_samples (user_id, observed_at desc);

create index if not exists device_activity_samples_trigger_idx
  on public.device_activity_samples (trigger, observed_at desc);

-- No policies on purpose. These readings are richer than anything else KC
-- stores about a device, so nothing client-side may read them back; the only
-- writer is the edge function running as service role, and the only readers are
-- offline analysis and the future scoring job.
alter table public.device_activity_samples enable row level security;

comment on table public.device_activity_samples is
  'Shadow-only multi-signal liveness sampling. Never feeds alert judgement. A null signal column means the device or build could not read it, not that the value was zero.';

-- Insert path. Mirrors the discipline of private.insert_behavior_ping: it
-- validates, it is idempotent per event, and it deliberately triggers no
-- liveness side effects whatsoever — this data must not be able to refresh a
-- heartbeat or resolve an alert, however tempting that becomes later.
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
  -- Unlike behavior_pings there is no lower bound: backfilled samples are the
  -- normal case here and carry no live-safety authority to abuse.
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
    -- A malformed field must not cost the whole sample silently, but it also
    -- must not land as a half-truth. Rejecting loudly keeps the null-means-
    -- unreadable contract honest.
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
