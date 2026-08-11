-- Synchronize activity truth across GM, group watch boards, and escalation.
-- behavior_pings.max(at) is the real user/device behavior clock.

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
          when not coalesce(us.share_activity, true) and not coalesce(al.alerted, false) then 'hidden'
          when _visibility = 'watchers_only' and not _i_watching and not coalesce(al.alerted, false) then 'hidden'
          when coalesce(al.alerted, false) then 'alert'
          when bp.last_at is null then 'unknown'
          when bp.last_at > now() - interval '6 hours' then 'active'
          when bp.last_at > now() - interval '24 hours' then 'quiet'
          else 'silent'
        end,
      'hours',
        case
          when bp.last_at is null then null
          else floor(extract(epoch from (now() - bp.last_at)) / 3600)::int
        end,
      'last_behavior_at', bp.last_at,
      'last_heartbeat_at', ds.last_heartbeat_at,
      'threshold_hours', round(extract(epoch from private.silence_threshold(m.user_id)) / 3600.0, 2),
      'alerted', coalesce(al.alerted, false)
    )
    order by (m.user_id = _uid) desc, p.display_name nulls last, m.user_id
  ) into _members
  from public.group_members m
  left join public.profiles p on p.id = m.user_id
  left join public.user_settings us on us.user_id = m.user_id
  left join public.device_state ds on ds.user_id = m.user_id
  left join lateral (
    select max(at) as last_at
    from public.behavior_pings
    where user_id = m.user_id
  ) bp on true
  left join lateral (
    select exists (
      select 1 from public.alerts a
      where a.user_id = m.user_id and a.status = 'open'
        and a.stage in ('group', 'community', 'terminal')
    ) as alerted
  ) al on true
  where m.group_id = _group and m.status = 'active';

  return jsonb_build_object(
    'visibility', _visibility,
    'is_owner', _is_owner,
    'i_share', _i_share,
    'members', coalesce(_members, '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_group_activity(uuid) to authenticated;

create or replace function public.process_escalations()
returns void language plpgsql security definer set search_path to '' as $$
declare
  _self_grace constant interval := interval '30 minutes';
  _group_dur  constant interval := interval '1 hour';
  _comm_dur   constant interval := interval '2 hours';
  r record; _aid uuid; _new text; _triggered boolean := false;
begin
  -- First clear open alerts that no longer match current account-level truth.
  for r in
    select a.id, a.user_id, a.cause, ds.last_heartbeat_at, bp.last_at as last_behavior_at
    from public.alerts a
    left join public.device_state ds on ds.user_id = a.user_id
    left join lateral (
      select max(at) as last_at
      from public.behavior_pings
      where user_id = a.user_id
    ) bp on true
    where a.status = 'open'
      and a.cause in ('silence', 'dark_device')
      and (
        (
          a.cause = 'silence'
          and bp.last_at is not null
          and (
            private.is_in_sleep_window(a.user_id, now())
            or now() - bp.last_at <= private.silence_threshold(a.user_id)
          )
        )
        or (
          a.cause = 'dark_device'
          and ds.last_heartbeat_at is not null
          and now() - ds.last_heartbeat_at <= interval '18 hours'
        )
      )
  loop
    update public.alerts
      set status = 'resolved', resolved_at = now(), resolved_by = null, updated_at = now()
      where id = r.id;
    insert into public.alert_events (alert_id, kind, note)
      values (r.id, 'auto_resolved', 'condition_cleared');
    delete from public.notifications where alert_id = r.id;
    _triggered := true;
  end loop;

  for r in
    select ds.user_id,
           (now() - ds.last_heartbeat_at) > interval '18 hours' as is_dark
    from public.device_state ds
    where (
      ds.status = 'alert'
      or now() - ds.last_heartbeat_at > interval '18 hours'
      or (
        not private.is_in_sleep_window(ds.user_id, now())
        and now() - (
          select coalesce(max(at), to_timestamp(0))
          from public.behavior_pings
          where user_id = ds.user_id
        ) > private.silence_threshold(ds.user_id)
      )
    )
      and exists (select 1 from public.group_members gm
                  where gm.user_id = ds.user_id and gm.monitored and gm.status = 'active')
      and not exists (select 1 from public.alerts a where a.user_id = ds.user_id and a.status = 'open')
      and not exists (
        select 1 from public.alerts recent
        where recent.user_id = ds.user_id
          and recent.status = 'resolved'
          and recent.cause in ('silence', 'dark_device')
          and recent.resolved_by is not null
          and recent.resolved_by <> recent.user_id
          and recent.resolved_at > now() - _self_grace
      )
  loop
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    values (r.user_id, case when r.is_dark then 'dark_device' else 'silence' end,
            'self', now(), now() + _self_grace)
    returning id into _aid;
    insert into public.alert_events (alert_id, kind) values (_aid, 'raised');
    perform private.notify_stage(_aid, r.user_id, 'self');
    _triggered := true;
  end loop;

  for r in
    select * from public.alerts
    where status = 'open'
      and next_deadline is not null and next_deadline <= now()
      and coalesce(paused_until, to_timestamp(0)) <= now()
  loop
    _new := case r.stage
              when 'self' then 'group'
              when 'group' then 'community'
              when 'community' then 'terminal'
              else 'terminal' end;
    update public.alerts
      set stage = _new, stage_entered_at = now(), paused_until = null, paused_by = null, updated_at = now(),
          next_deadline = case _new when 'group' then now() + _group_dur
                                    when 'community' then now() + _comm_dur
                                    else null end
      where id = r.id;
    insert into public.alert_events (alert_id, kind, note) values (r.id, 'escalated', _new);
    perform private.notify_stage(r.id, r.user_id, _new);
    _triggered := true;
  end loop;

  if _triggered then
    perform private.trigger_push_dispatch();
  end if;
end;
$$;

revoke execute on function public.process_escalations() from public, anon, authenticated;

create or replace function public.resolve_alert(_alert_id uuid)
returns void language plpgsql security definer set search_path to '' as $$
declare _uid uuid := auth.uid(); _target uuid; _tname text;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if not private.can_see_alert(_alert_id, _uid) then raise exception 'forbidden'; end if;
  if not exists (select 1 from public.alerts where id = _alert_id and paused_by = _uid) then
    raise exception 'only the responder who reached out can confirm safe';
  end if;

  update public.alerts
    set status = 'resolved', resolved_at = now(), resolved_by = _uid, updated_at = now()
    where id = _alert_id and status = 'open' returning user_id into _target;
  if _target is null then raise exception 'alert not open'; end if;

  insert into public.alert_events (alert_id, actor_id, kind) values (_alert_id, _uid, 'confirmed_safe');

  insert into public.notifications (recipient_id, alert_id, kind, body)
  values (_target, _alert_id, 'self', '【系统提示】小组已确认你安全，但检测到设备仍未活动。请解锁或使用手机以恢复自动守护！');

  select coalesce(display_name, '') into _tname from public.profiles where id = _target;
  insert into public.notifications (recipient_id, alert_id, kind, body, params)
  select distinct s.r, _alert_id, 'resolved', _tname || ' 已确认安全，告警解除。',
    jsonb_build_object('target', _tname)
  from (
    select _target as r
    union
    select w.user_id from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _target and t.monitored and t.status = 'active'
        and w.watching and w.status = 'active'
  ) s;

  perform private.trigger_push_dispatch();
end;
$$;

grant execute on function public.resolve_alert(uuid) to authenticated;

create or replace function public.resolve_my_alert()
returns void language plpgsql security definer set search_path to '' as $$
declare _uid uuid := auth.uid(); _aid uuid;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  update public.alerts set status = 'resolved', resolved_at = now(), resolved_by = _uid, updated_at = now()
    where user_id = _uid and status = 'open' returning id into _aid;
  if _aid is not null then
    insert into public.alert_events (alert_id, actor_id, kind) values (_aid, _uid, 'resolved');
  end if;

  insert into public.behavior_pings (user_id, kind, at)
  values (_uid, 'manual_checkin', now());

  perform private.trigger_push_dispatch();
end;
$$;

grant execute on function public.resolve_my_alert() to authenticated;
