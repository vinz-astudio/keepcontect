-- Migration: Admin delete and promote powers
-- Allows community/group admins (created_by) to delete their entity,
-- and allows admins to update the role of other members.

------------------------------------------------------------
-- 1. DELETE policies for communities and groups
------------------------------------------------------------

-- Community admin (created_by) can delete their community
create policy communities_delete on public.communities
  for delete to authenticated
  using (
    exists (
      select 1 from public.community_members cm
      where cm.community_id = id
        and cm.user_id = (select auth.uid())
        and cm.role = 'admin'
        and cm.status = 'active'
    )
  );

-- Group admin (created_by) can delete their group
create policy groups_delete on public.groups
  for delete to authenticated
  using (
    exists (
      select 1 from public.group_members gm
      where gm.group_id = id
        and gm.user_id = (select auth.uid())
        and gm.role = 'admin'
        and gm.status = 'active'
    )
  );

------------------------------------------------------------
-- 2. Allow admin to update other members' role in group_members
------------------------------------------------------------

-- Drop the existing update policy (only allows self-update) and replace with
-- a policy that also allows admins to change other members' role.
drop policy if exists group_members_update on public.group_members;

create policy group_members_update on public.group_members
  for update to authenticated
  using (
    -- Self: can update own monitoring preferences
    (select auth.uid()) = user_id
    or
    -- Admin: can promote/demote other members in their group
    exists (
      select 1 from public.group_members gm
      where gm.group_id = group_id
        and gm.user_id = (select auth.uid())
        and gm.role = 'admin'
        and gm.status = 'active'
    )
  )
  with check (
    -- Self can only update own row
    (select auth.uid()) = user_id
    or
    -- Admin can update any row in their group
    exists (
      select 1 from public.group_members gm
      where gm.group_id = group_id
        and gm.user_id = (select auth.uid())
        and gm.role = 'admin'
        and gm.status = 'active'
    )
  );

------------------------------------------------------------
-- 3. Allow admin to update other members' role in community_members
------------------------------------------------------------

-- Drop the existing update policy and replace with admin-aware version
drop policy if exists community_members_update on public.community_members;

create policy community_members_update on public.community_members
  for update to authenticated
  using (
    -- Self: can update own row
    (select auth.uid()) = user_id
    or
    -- Admin: can promote/demote other members in their community
    exists (
      select 1 from public.community_members cm
      where cm.community_id = community_id
        and cm.user_id = (select auth.uid())
        and cm.role = 'admin'
        and cm.status = 'active'
    )
  )
  with check (
    (select auth.uid()) = user_id
    or
    exists (
      select 1 from public.community_members cm
      where cm.community_id = community_id
        and cm.user_id = (select auth.uid())
        and cm.role = 'admin'
        and cm.status = 'active'
    )
  );

------------------------------------------------------------
-- 4. Also allow admins to delete members from group/community
--    (so admin can remove a member, not just the member leaving themselves)
------------------------------------------------------------

drop policy if exists group_members_delete on public.group_members;

create policy group_members_delete on public.group_members
  for delete to authenticated
  using (
    -- Self: can leave the group
    (select auth.uid()) = user_id
    or
    -- Admin: can remove any member from their group
    exists (
      select 1 from public.group_members gm
      where gm.group_id = group_id
        and gm.user_id = (select auth.uid())
        and gm.role = 'admin'
        and gm.status = 'active'
    )
  );

drop policy if exists community_members_delete on public.community_members;

create policy community_members_delete on public.community_members
  for delete to authenticated
  using (
    (select auth.uid()) = user_id
    or
    exists (
      select 1 from public.community_members cm
      where cm.community_id = community_id
        and cm.user_id = (select auth.uid())
        and cm.role = 'admin'
        and cm.status = 'active'
    )
  );
