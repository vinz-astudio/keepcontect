revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.handle_new_community() from public, anon, authenticated;
revoke execute on function public.handle_new_group() from public, anon, authenticated;

alter policy communities_update on public.communities
  with check (
    exists (
      select 1 from public.community_members cm
      where cm.community_id = communities.id and cm.user_id = (select auth.uid())
        and cm.role = 'admin' and cm.status = 'active'
    )
  );

alter policy groups_update on public.groups
  with check (
    exists (
      select 1 from public.group_members gm
      where gm.group_id = groups.id and gm.user_id = (select auth.uid())
        and gm.role = 'admin' and gm.status = 'active'
    )
  );

create index if not exists communities_created_by_idx on public.communities (created_by);
create index if not exists groups_created_by_idx on public.groups (created_by);