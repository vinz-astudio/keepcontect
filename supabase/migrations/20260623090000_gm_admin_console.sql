-- GM/管理员名单(仅 SECURITY DEFINER 函数可读)
create table if not exists public.app_admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.app_admins enable row level security;
insert into public.app_admins (user_id)
values ('b897a59f-0a54-42df-9926-8452e477d8bd') on conflict do nothing;

create or replace function private.is_admin(_uid uuid)
returns boolean language sql security definer set search_path to '' stable as $$
  select exists (select 1 from public.app_admins where user_id = _uid)
$$;

-- 当前用户是否 GM(决定是否显示 GM 页)
create or replace function public.am_i_gm()
returns boolean language sql security definer set search_path to '' stable as $$
  select private.is_admin(auth.uid())
$$;
grant execute on function public.am_i_gm() to authenticated;

-- 列出所有用户及其各客户端的版本/平台(GM-only)
create or replace function public.gm_list_clients()
returns jsonb language plpgsql security definer set search_path to '' as $$
declare _uid uuid := auth.uid();
begin
  if not private.is_admin(_uid) then raise exception 'forbidden'; end if;
  return coalesce((
    select jsonb_agg(obj order by nm asc, ls desc nulls last)
    from (
      select jsonb_build_object(
        'user_id', p.id,
        'name', coalesce(nullif(p.display_name,''), left(p.id::text,8)),
        'platform', c.platform,
        'app_version', c.app_version,
        'last_seen_at', c.last_seen_at
      ) as obj,
      coalesce(nullif(p.display_name,''), left(p.id::text,8)) as nm,
      c.last_seen_at as ls
      from public.profiles p
      left join public.clients c on c.user_id = p.id
    ) s
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.gm_list_clients() to authenticated;

-- GM 提醒某用户更新版本
create or replace function public.gm_nudge_update(_target uuid)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_admin(auth.uid()) then raise exception 'forbidden'; end if;
  insert into public.notifications (recipient_id, kind, body, params)
  values (_target, 'update', '请更新到最新版本的 Keep Contact。', '{}'::jsonb);
end;
$$;
grant execute on function public.gm_nudge_update(uuid) to authenticated;

-- GM 向任意用户发送关怀(不受同组限制)
create or replace function public.gm_send_concern(_target uuid)
returns void language plpgsql security definer set search_path to '' as $$
declare _name text;
begin
  if not private.is_admin(auth.uid()) then raise exception 'forbidden'; end if;
  select coalesce(display_name,'') into _name from public.profiles where id = auth.uid();
  insert into public.notifications (recipient_id, kind, body, params)
  values (_target, 'concern',
    coalesce(nullif(_name,''),'管理员') || ' 在关心你,请打开 App 完成解锁报平安。',
    jsonb_build_object('name', _name));
end;
$$;
grant execute on function public.gm_send_concern(uuid) to authenticated;
