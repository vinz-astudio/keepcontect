-- 新用户:display_name 优先取 OAuth 提供的 name / full_name(之前只取 display_name,
-- 导致 Google/Apple/Facebook 登录的用户 profiles.display_name 为空、到处显示 id)。
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, nullif(btrim(coalesce(
    new.raw_user_meta_data ->> 'display_name',
    new.raw_user_meta_data ->> 'name',
    new.raw_user_meta_data ->> 'full_name'
  )), ''))
  on conflict (id) do nothing;
  insert into public.heartbeat_tokens (user_id) values (new.id) on conflict (user_id) do nothing;
  insert into public.user_settings (user_id) values (new.id) on conflict (user_id) do nothing;
  return new;
end;
$$;

-- 回填:名字只在 auth 元数据里、profiles.display_name 为空的现有用户补上
update public.profiles p
set display_name = nullif(btrim(coalesce(
    u.raw_user_meta_data ->> 'display_name',
    u.raw_user_meta_data ->> 'name',
    u.raw_user_meta_data ->> 'full_name'
  )), '')
from auth.users u
where u.id = p.id
  and (p.display_name is null or btrim(p.display_name) = '')
  and nullif(btrim(coalesce(
    u.raw_user_meta_data ->> 'display_name',
    u.raw_user_meta_data ->> 'name',
    u.raw_user_meta_data ->> 'full_name'
  )), '') is not null;
