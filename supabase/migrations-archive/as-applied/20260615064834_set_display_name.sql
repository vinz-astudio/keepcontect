-- 用户自设显示名（用于 app 内与其他用户沟通、确认身份）。
-- 同步更新 profiles.display_name（别人看到的名字）；客户端另调 auth.updateUser 更新 metadata。
create or replace function public.set_display_name(_name text)
returns void language plpgsql security definer set search_path = '' as $$
declare _clean text := nullif(btrim(_name), '');
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if _clean is null then raise exception 'name required'; end if;
  if length(_clean) > 40 then _clean := left(_clean, 40); end if;
  update public.profiles set display_name = _clean where id = auth.uid();
end; $$;
revoke execute on function public.set_display_name(text) from public, anon;
grant execute on function public.set_display_name(text) to authenticated;