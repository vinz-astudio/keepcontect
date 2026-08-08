-- 改 Group 所属 Community（仅创建者；移入的 Community 须本人也是其成员；null=独立）
create or replace function public.set_group_community(_group uuid, _community uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if _community is not null and not exists (
    select 1 from public.community_members
    where community_id = _community and user_id = auth.uid() and status = 'active'
  ) then
    raise exception 'not a member of target community';
  end if;
  update public.groups set community_id = _community
    where id = _group and created_by = auth.uid();
  if not found then raise exception 'not group owner'; end if;
end; $$;
revoke execute on function public.set_group_community(uuid, uuid) from public, anon;
grant execute on function public.set_group_community(uuid, uuid) to authenticated;