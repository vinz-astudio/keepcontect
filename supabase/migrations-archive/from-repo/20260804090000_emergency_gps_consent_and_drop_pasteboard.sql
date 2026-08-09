-- Two corrections to things that were not what they claimed to be.
--
-- 1. Emergency GPS consent had no effect and no home.
--
-- The Me screen offered a switch called "emergency GPS consent". It wrote
-- `kc.emergency_gps_consent` into localStorage, and nothing anywhere read it
-- back except the switch itself, to render its own tick. dispatchSos fetched
-- coordinates and uploaded them unconditionally, so turning the consent *off*
-- did not stop KC from capturing and sending the user's location. A control
-- that promises a privacy boundary and does not enforce one is worse than no
-- control: the user makes a decision, and the decision is discarded.
--
-- Living in localStorage compounded it — the answer did not survive a
-- reinstall, could not be seen or audited from the server, and did not follow
-- the account to another device.
--
-- The column below is where the answer belongs. Default false: consent is
-- something a user gives, never something inferred from silence.
--
-- 2. The pasteboard counter is dropped.
--
-- The iOS sampler read UIPasteboard.changeCount — a number of copies, never any
-- content. It returned a usable value in 9 of 56 field samples, so iOS is
-- evidently restricting it from a background wake. Keeping a column named
-- `pasteboard_change_count` implies KC watches the clipboard; that is an
-- expensive thing to have to explain to a user, and it was buying almost no
-- evidence. Removed from the collector in the same change.

alter table public.user_settings
  add column if not exists emergency_gps_consent boolean not null default false;

comment on column public.user_settings.emergency_gps_consent is
  'Whether the user has agreed to their coordinates being captured and shared with their circle during an SOS. Enforced in dispatchSos; false means no location is fetched at all.';

alter table public.device_activity_samples
  drop column if exists pasteboard_change_count;

-- Rewritten without the dropped column. Everything else is unchanged: still
-- shadow-only, still no liveness side effects of any kind.
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
    system_uptime_seconds, other_audio_playing,
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
    return 'invalid';
end;
$function$;

revoke all on function private.insert_device_sample(uuid, uuid, jsonb) from public;
