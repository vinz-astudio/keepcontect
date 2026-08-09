alter policy communities_select on public.communities
  using (
    created_by = (select auth.uid())
    or private.is_community_member(id, (select auth.uid()))
  );

alter policy groups_select on public.groups
  using (
    created_by = (select auth.uid())
    or private.is_group_member(id, (select auth.uid()))
    or (community_id is not null and private.is_community_member(community_id, (select auth.uid())))
  );