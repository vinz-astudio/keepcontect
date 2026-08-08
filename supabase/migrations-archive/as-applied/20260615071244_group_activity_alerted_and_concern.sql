-- 扩展 get_group_activity：每位成员加 alerted（是否处于"已升级到 group+ 的开放告警"）。
-- alerted 用于状态看板把"异常沉默"的成员置顶；不受 share_activity 限制（安全优先，
-- 与现有 group 阶段会通知全组的设计一致）。
create or replace function public.get_group_activity(_group uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  _uid uuid := auth.uid();
  _vis text;
  _owner uuid;
  _i_watch boolean;
  _i_share boolean;
  _members jsonb;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  select g.activity_visibility, g.created_by into _vis, _owner
    from public.groups g where g.id = _group;
  if _vis is null then raise exception 'group not found'; end if;
  perform 1 from public.group_members
    where group_id = _group and user_id = _uid and status = 'active';
  if not found then raise exception 'not a member'; end if;

  select coalesce(gm.watching, false) into _i_watch
    from public.group_members gm where gm.group_id = _group and gm.user_id = _uid;
  select coalesce(us.share_activity, false) into _i_share
    from public.user_settings us where us.user_id = _uid;

  select jsonb_agg(
    jsonb_build_object(
      'user_id', m.user_id,
      'name', coalesce(p.display_name, left(m.user_id::text, 8)),
      'is_me', (m.user_id = _uid),
      'alerted', exists(
        select 1 from public.alerts a
        where a.user_id = m.user_id and a.status = 'open'
          and a.stage in ('group', 'community', 'terminal')
      ),
      'status', case
        when m.user_id = _uid then 'self'
        when not coalesce(us.share_activity, false) then 'hidden'
        when _vis = 'group_wide' then coalesce(b.bucket, 'unknown')
        when _vis = 'watchers_only' and _i_watch then coalesce(b.bucket, 'unknown')
        else 'hidden'
      end,
      'hours', case
        when m.user_id = _uid then null
        when not coalesce(us.share_activity, false) then null
        when _vis = 'group_wide' or (_vis = 'watchers_only' and _i_watch) then b.hours
        else null
      end
    )
    order by (m.user_id = _uid) desc, p.display_name
  ) into _members
  from public.group_members m
  left join public.profiles p on p.id = m.user_id
  left join public.user_settings us on us.user_id = m.user_id
  left join lateral (
    select
      case
        when extract(epoch from (now() - ds.last_heartbeat_at)) / 3600 < 6 then 'active'
        when extract(epoch from (now() - ds.last_heartbeat_at)) / 3600 < 24 then 'quiet'
        else 'silent'
      end as bucket,
      round(extract(epoch from (now() - ds.last_heartbeat_at)) / 3600)::int as hours
    from public.device_state ds where ds.user_id = m.user_id
  ) b on true
  where m.group_id = _group and m.status = 'active';

  return jsonb_build_object(
    'visibility', _vis,
    'is_owner', (_owner = _uid),
    'i_share', _i_share,
    'members', coalesce(_members, '[]'::jsonb)
  );
end; $$;

-- "Send concern"：向同组成员发一条即时关怀通知（催对方打开 App 解锁报平安，确认非误报）。
create or replace function public.send_concern(_target uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid(); _name text;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if _target = _uid then raise exception 'cannot concern self'; end if;
  if not exists (
    select 1 from public.group_members a
    join public.group_members b on a.group_id = b.group_id
    where a.user_id = _uid and b.user_id = _target
      and a.status = 'active' and b.status = 'active'
  ) then raise exception 'not in same group'; end if;
  select display_name into _name from public.profiles where id = _uid;
  insert into public.notifications (recipient_id, kind, body, params)
  values (_target, 'concern',
          '有成员在关心你，请打开 App 完成解锁报平安。',
          jsonb_build_object('name', coalesce(_name, '')));
end; $$;
revoke execute on function public.send_concern(uuid) from public, anon;
grant execute on function public.send_concern(uuid) to authenticated;