-- Split group activity reads by UI intent.
-- Watch page: watcher lens, only people this user should watch in this group.
-- Circle group page: group lens, all active group members with normal share_activity privacy.

create or replace function public.get_group_activity_view(_group uuid, _view text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  _uid uuid := auth.uid();
  _mode text := coalesce(nullif(btrim(_view), ''), 'group');
  _is_owner boolean;
  _i_watching boolean;
  _i_share boolean;
  _members jsonb;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if _mode not in ('watch', 'group') then raise exception 'invalid activity view'; end if;

  select exists (
           select 1 from public.group_members gm
           where gm.group_id = g.id and gm.user_id = _uid
             and gm.role = 'admin' and gm.status = 'active'
         ),
         coalesce(me.watching, false)
    into _is_owner, _i_watching
  from public.groups g
  join public.group_members me
    on me.group_id = g.id and me.user_id = _uid and me.status = 'active'
  where g.id = _group;
  if not found then raise exception 'forbidden'; end if;

  select coalesce(us.share_activity, true) into _i_share
  from public.user_settings us where us.user_id = _uid;
  _i_share := coalesce(_i_share, true);

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'user_id', m.user_id,
      'name', coalesce(nullif(p.display_name, ''), left(m.user_id::text, 8)),
      'is_me', m.user_id = _uid,
      'status',
        case
          when m.user_id = _uid then 'self'
          when not coalesce(us.share_activity, true) and not coalesce(al.alerted, false) then 'hidden'
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
  ), '[]'::jsonb) into _members
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
  where m.group_id = _group
    and m.status = 'active'
    and (
      _mode = 'group'
      or m.user_id = _uid
      or (_i_watching and m.monitored)
    );

  return jsonb_build_object(
    'visibility', case when _mode = 'watch' then 'watchers_only' else 'group_wide' end,
    'view', _mode,
    'is_owner', _is_owner,
    'i_share', _i_share,
    'members', _members
  );
end;
$$;

revoke execute on function public.get_group_activity_view(uuid, text) from public, anon;
grant execute on function public.get_group_activity_view(uuid, text) to authenticated;
