-- Parity migration for passive sensing, SOS coordinates, group activity,
-- user settings, and task editing. These objects are already reflected in
-- generated client types; this file makes local migrations reproducible.

alter table public.alerts
  add column if not exists sos_lat double precision,
  add column if not exists sos_lng double precision;

alter table public.groups
  add column if not exists activity_visibility text not null default 'watchers_only';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'groups_activity_visibility_check'
  ) then
    alter table public.groups
      add constraint groups_activity_visibility_check
      check (activity_visibility in ('watchers_only', 'group_wide'));
  end if;
end $$;

create table if not exists public.user_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  sensitivity text not null default 'balanced'
    check (sensitivity in ('high', 'balanced', 'low')),
  share_activity boolean not null default true,
  sleep_start_utc time,
  sleep_end_utc time,
  updated_at timestamptz not null default now()
);

alter table public.user_settings enable row level security;
drop policy if exists user_settings_select on public.user_settings;
drop policy if exists user_settings_insert on public.user_settings;
drop policy if exists user_settings_update on public.user_settings;
create policy user_settings_select on public.user_settings
  for select to authenticated using ((select auth.uid()) = user_id);
create policy user_settings_insert on public.user_settings
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy user_settings_update on public.user_settings
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

insert into public.user_settings (user_id)
select id from auth.users
on conflict (user_id) do nothing;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', null))
  on conflict (id) do nothing;
  insert into public.heartbeat_tokens (user_id) values (new.id)
  on conflict (user_id) do nothing;
  insert into public.user_settings (user_id) values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create or replace function public.set_display_name(_name text)
returns void language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  update public.profiles
    set display_name = nullif(btrim(_name), '')
    where id = _uid;
end;
$$;

create or replace function public.set_sensitivity(_s text)
returns void language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if _s not in ('high', 'balanced', 'low') then raise exception 'bad sensitivity'; end if;
  insert into public.user_settings (user_id, sensitivity, updated_at)
  values (_uid, _s, now())
  on conflict (user_id) do update
    set sensitivity = excluded.sensitivity, updated_at = now();
end;
$$;

create or replace function public.set_sleep_window(_start time default null, _end time default null)
returns void language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  insert into public.user_settings (user_id, sleep_start_utc, sleep_end_utc, updated_at)
  values (_uid, _start, _end, now())
  on conflict (user_id) do update
    set sleep_start_utc = excluded.sleep_start_utc,
        sleep_end_utc = excluded.sleep_end_utc,
        updated_at = now();
end;
$$;

create or replace function public.set_share_activity(_share boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  insert into public.user_settings (user_id, share_activity, updated_at)
  values (_uid, coalesce(_share, false), now())
  on conflict (user_id) do update
    set share_activity = excluded.share_activity, updated_at = now();
end;
$$;

create or replace function public.set_group_visibility(_group uuid, _visibility text)
returns void language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if _visibility not in ('watchers_only', 'group_wide') then
    raise exception 'bad visibility';
  end if;
  update public.groups g
    set activity_visibility = _visibility
    where g.id = _group
      and exists (
        select 1 from public.group_members gm
        where gm.group_id = g.id
          and gm.user_id = _uid
          and gm.role = 'admin'
          and gm.status = 'active'
      );
  if not found then raise exception 'forbidden'; end if;
end;
$$;

create or replace function public.set_group_community(_group uuid, _community uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if _community is not null and not private.is_community_member(_community, _uid) then
    raise exception 'community not visible';
  end if;
  update public.groups g
    set community_id = _community
    where g.id = _group
      and exists (
        select 1 from public.group_members gm
        where gm.group_id = g.id and gm.user_id = _uid
          and gm.role = 'admin' and gm.status = 'active'
      );
  if not found then raise exception 'forbidden'; end if;
end;
$$;

create or replace function public.rename_group(_group uuid, _name text)
returns void language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  update public.groups g
    set name = nullif(btrim(_name), '')
    where g.id = _group
      and exists (
        select 1 from public.group_members gm
        where gm.group_id = g.id and gm.user_id = _uid
          and gm.role = 'admin' and gm.status = 'active'
      )
      and nullif(btrim(_name), '') is not null;
  if not found then raise exception 'forbidden'; end if;
end;
$$;

create or replace function public.rename_community(_community uuid, _name text)
returns void language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  update public.communities c
    set name = nullif(btrim(_name), '')
    where c.id = _community and c.created_by = _uid
      and nullif(btrim(_name), '') is not null;
  if not found then raise exception 'forbidden'; end if;
end;
$$;

create or replace function public.get_group_activity(_group uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  _uid uuid := auth.uid();
  _visibility text;
  _is_owner boolean;
  _i_watching boolean;
  _i_share boolean;
  _members jsonb;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  select g.activity_visibility,
         exists (
           select 1 from public.group_members gm
           where gm.group_id = g.id and gm.user_id = _uid
             and gm.role = 'admin' and gm.status = 'active'
         ),
         coalesce(me.watching, false)
    into _visibility, _is_owner, _i_watching
  from public.groups g
  join public.group_members me
    on me.group_id = g.id and me.user_id = _uid and me.status = 'active'
  where g.id = _group;
  if not found then raise exception 'forbidden'; end if;

  select coalesce(us.share_activity, true) into _i_share
  from public.user_settings us where us.user_id = _uid;
  _i_share := coalesce(_i_share, true);

  select jsonb_agg(
    jsonb_build_object(
      'user_id', m.user_id,
      'name', coalesce(nullif(p.display_name, ''), left(m.user_id::text, 8)),
      'is_me', m.user_id = _uid,
      'status',
        case
          when m.user_id = _uid then 'self'
          when not coalesce(us.share_activity, true) then 'hidden'
          when _visibility = 'watchers_only' and not _i_watching then 'hidden'
          when ds.last_heartbeat_at is null then 'unknown'
          when ds.last_heartbeat_at > now() - interval '6 hours' then 'active'
          when ds.last_heartbeat_at > now() - interval '24 hours' then 'quiet'
          else 'silent'
        end,
      'hours',
        case
          when ds.last_heartbeat_at is null then null
          else floor(extract(epoch from (now() - ds.last_heartbeat_at)) / 3600)::int
        end,
      'alerted',
        exists (
          select 1 from public.alerts a
          where a.user_id = m.user_id and a.status = 'open'
            and a.stage in ('group', 'community', 'terminal')
        )
    )
    order by (m.user_id = _uid) desc, p.display_name nulls last, m.user_id
  ) into _members
  from public.group_members m
  left join public.profiles p on p.id = m.user_id
  left join public.user_settings us on us.user_id = m.user_id
  left join public.device_state ds on ds.user_id = m.user_id
  where m.group_id = _group and m.status = 'active';

  return jsonb_build_object(
    'visibility', _visibility,
    'is_owner', _is_owner,
    'i_share', _i_share,
    'members', coalesce(_members, '[]'::jsonb)
  );
end;
$$;

create or replace function public.send_concern(_target uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid(); _name text;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if _uid = _target then raise exception 'bad target'; end if;
  if not private.shares_group_with(_target, _uid) and not private.is_guardian_of(_target, _uid) then
    raise exception 'forbidden';
  end if;
  select coalesce(display_name, '') into _name from public.profiles where id = _uid;
  insert into public.notifications (recipient_id, kind, body, params)
  values (
    _target,
    'concern',
    coalesce(nullif(_name, ''), '有人') || ' 在关心你，请打开 App 完成解锁报平安。',
    jsonb_build_object('name', _name)
  );
end;
$$;

create or replace function public.raise_sos(_lat double precision default null, _lng double precision default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid(); _aid uuid;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  select id into _aid from public.alerts where user_id = _uid and status = 'open';
  if _aid is null then
    insert into public.alerts
      (user_id, cause, stage, stage_entered_at, next_deadline, sos_lat, sos_lng)
    values
      (_uid, 'sos', 'group', now(), now() + interval '1 hour', _lat, _lng)
    returning id into _aid;
    insert into public.alert_events (alert_id, actor_id, kind) values (_aid, _uid, 'raised');
  else
    update public.alerts
      set cause = 'sos',
          stage = 'group',
          stage_entered_at = now(),
          next_deadline = now() + interval '1 hour',
          paused_until = null,
          sos_lat = coalesce(_lat, sos_lat),
          sos_lng = coalesce(_lng, sos_lng),
          updated_at = now()
      where id = _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note)
    values (_aid, _uid, 'escalated', 'sos');
  end if;
  perform private.notify_stage(_aid, _uid, 'group');
  return _aid;
end;
$$;

create or replace function public.update_checkin_task(
  _task uuid,
  _kind text,
  _due_time_utc time default null,
  _interval_hours int default null,
  _first_due timestamptz default null,
  _grace int default 30,
  _label text default ''
) returns void language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid(); _ward uuid;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if _kind not in ('daily', 'interval') then raise exception 'bad kind'; end if;
  update public.checkin_tasks t
    set kind = _kind,
        due_time_utc = case when _kind = 'daily' then _due_time_utc else null end,
        interval_hours = case when _kind = 'interval' then _interval_hours else null end,
        grace_minutes = coalesce(_grace, 30),
        label = coalesce(_label, ''),
        cycle_state = 'idle',
        next_due_at = coalesce(
          _first_due,
          case when _kind = 'interval' then now() + make_interval(hours => _interval_hours) end
        ),
        status = case when status = 'declined' then 'pending' else status end,
        updated_at = now()
    where t.id = _task
      and t.created_by = _uid
      and t.status in ('pending', 'active', 'declined')
    returning t.ward_id into _ward;
  if _ward is null then raise exception 'task not found'; end if;

  insert into public.notifications (recipient_id, kind, body, params)
  values (_ward, 'task_updated', '你的报平安任务已被修改，请留意新的时间安排。',
          jsonb_build_object('label', coalesce(_label, '')));
end;
$$;

revoke execute on function public.set_display_name(text) from public, anon;
revoke execute on function public.set_sensitivity(text) from public, anon;
revoke execute on function public.set_sleep_window(time, time) from public, anon;
revoke execute on function public.set_share_activity(boolean) from public, anon;
revoke execute on function public.set_group_visibility(uuid, text) from public, anon;
revoke execute on function public.set_group_community(uuid, uuid) from public, anon;
revoke execute on function public.rename_group(uuid, text) from public, anon;
revoke execute on function public.rename_community(uuid, text) from public, anon;
revoke execute on function public.get_group_activity(uuid) from public, anon;
revoke execute on function public.send_concern(uuid) from public, anon;
revoke execute on function public.raise_sos(double precision, double precision) from public, anon;
revoke execute on function public.update_checkin_task(uuid, text, time, int, timestamptz, int, text) from public, anon;

grant execute on function public.set_display_name(text) to authenticated;
grant execute on function public.set_sensitivity(text) to authenticated;
grant execute on function public.set_sleep_window(time, time) to authenticated;
grant execute on function public.set_share_activity(boolean) to authenticated;
grant execute on function public.set_group_visibility(uuid, text) to authenticated;
grant execute on function public.set_group_community(uuid, uuid) to authenticated;
grant execute on function public.rename_group(uuid, text) to authenticated;
grant execute on function public.rename_community(uuid, text) to authenticated;
grant execute on function public.get_group_activity(uuid) to authenticated;
grant execute on function public.send_concern(uuid) to authenticated;
grant execute on function public.raise_sos(double precision, double precision) to authenticated;
grant execute on function public.update_checkin_task(uuid, text, time, int, timestamptz, int, text) to authenticated;

create extension if not exists pg_cron;
do $do$
declare _jobid bigint;
begin
  select jobid into _jobid from cron.job where jobname = 'process-checkin-tasks';
  if _jobid is not null then perform cron.unschedule(_jobid); end if;
  perform cron.schedule('process-checkin-tasks', '* * * * *', $$ select public.process_checkin_tasks(); $$);
end $do$;
