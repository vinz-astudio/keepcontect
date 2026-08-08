-- 每位成员是否公开自己的活跃状态（opt-in，默认关，符合隐私优先）
alter table public.user_settings
  add column if not exists share_activity boolean not null default false;

-- 每个 Group 的活跃可见范围：watchers_only（仅守望者可看）| group_wide（全组互看）
alter table public.groups
  add column if not exists activity_visibility text not null default 'watchers_only';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'groups_activity_visibility_chk') then
    alter table public.groups add constraint groups_activity_visibility_chk
      check (activity_visibility in ('watchers_only','group_wide'));
  end if;
end $$;

-- 本人开关"公开我的活跃状态"
create or replace function public.set_share_activity(_share boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  insert into public.user_settings (user_id, share_activity)
  values (auth.uid(), _share)
  on conflict (user_id) do update
    set share_activity = excluded.share_activity, updated_at = now();
end; $$;
revoke execute on function public.set_share_activity(boolean) from public, anon;
grant execute on function public.set_share_activity(boolean) to authenticated;

-- 组主设置本组活跃可见范围
create or replace function public.set_group_visibility(_group uuid, _visibility text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if _visibility not in ('watchers_only','group_wide') then
    raise exception 'bad visibility';
  end if;
  update public.groups set activity_visibility = _visibility
    where id = _group and created_by = auth.uid();
  if not found then raise exception 'not group owner'; end if;
end; $$;
revoke execute on function public.set_group_visibility(uuid, text) from public, anon;
grant execute on function public.set_group_visibility(uuid, text) to authenticated;

-- 读取本组"平安看板"：仅返回粗略状态桶，绝不返回精确时间
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
revoke execute on function public.get_group_activity(uuid) from public, anon;
grant execute on function public.get_group_activity(uuid) to authenticated;