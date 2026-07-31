-- Repair the membership write policies introduced by
-- 20260624180000_admin_delete_promote.sql.
--
-- That migration inlined an admin check as:
--
--   exists (select 1 from public.group_members gm
--           where gm.group_id = group_id and gm.user_id = ... and gm.role = 'admin')
--
-- Two defects follow from that single line.
--
-- 1. Recursion. The policy queries public.group_members from inside a policy on
--    public.group_members, so Postgres aborts every DELETE and UPDATE with
--    42P17 "infinite recursion detected in policy". Leaving a group or a
--    community has therefore never worked in production: the statement fails
--    before any row is touched, which is why other members still saw the
--    departing user.
--
-- 2. Privilege escalation. Inside the subquery the unqualified `group_id`
--    binds to the inner alias, not the outer row, so the condition reduces to
--    `gm.group_id = gm.group_id` -- always true. The admin clause therefore
--    read "is this user an admin of ANY group", granting every group admin
--    write access to every membership row in the database, including groups
--    they have never joined.
--
-- The fix follows the pattern core_relationships.sql already established for
-- exactly this reason: membership checks live in private SECURITY DEFINER
-- helpers, which bypass RLS and so cannot recurse. The intended semantics are
-- unchanged from what 20260624180000 described in its own comments -- a member
-- may leave, and an admin may manage members of that same group. No new
-- authority is granted here; one that was never intended is withdrawn.

------------------------------------------------------------
-- 1. SECURITY DEFINER admin helpers (mirrors private.is_group_member)
------------------------------------------------------------

create or replace function private.is_group_admin(_group_id uuid, _user uuid)
returns boolean language sql security definer set search_path = '' stable as $$
  select exists (
    select 1 from public.group_members gm
    where gm.group_id = _group_id
      and gm.user_id = _user
      and gm.role = 'admin'
      and gm.status = 'active'
  );
$$;

create or replace function private.is_community_admin(_community_id uuid, _user uuid)
returns boolean language sql security definer set search_path = '' stable as $$
  select exists (
    select 1 from public.community_members cm
    where cm.community_id = _community_id
      and cm.user_id = _user
      and cm.role = 'admin'
      and cm.status = 'active'
  );
$$;

-- An RLS policy runs as the calling role, so the role evaluating the policy has
-- to be able to execute the helper. Revoking from PUBLIC without granting to
-- authenticated makes every membership write fail with 42501 instead -- which
-- is exactly what happened on the first attempt at this repair. These grants
-- mirror private.is_group_member, whose SELECT policy has always worked.
grant execute on function private.is_group_admin(uuid, uuid) to authenticated;
grant execute on function private.is_community_admin(uuid, uuid) to authenticated;

------------------------------------------------------------
-- 2. group_members write policies
------------------------------------------------------------

drop policy if exists group_members_delete on public.group_members;

create policy group_members_delete on public.group_members
  for delete to authenticated
  using (
    -- Self: can leave the group
    (select auth.uid()) = user_id
    -- Admin: can remove a member of THIS group
    or private.is_group_admin(group_id, (select auth.uid()))
  );

drop policy if exists group_members_update on public.group_members;

create policy group_members_update on public.group_members
  for update to authenticated
  using (
    (select auth.uid()) = user_id
    or private.is_group_admin(group_id, (select auth.uid()))
  )
  with check (
    (select auth.uid()) = user_id
    or private.is_group_admin(group_id, (select auth.uid()))
  );

------------------------------------------------------------
-- 3. community_members write policies (identical defect, copied verbatim)
------------------------------------------------------------

drop policy if exists community_members_delete on public.community_members;

create policy community_members_delete on public.community_members
  for delete to authenticated
  using (
    (select auth.uid()) = user_id
    or private.is_community_admin(community_id, (select auth.uid()))
  );

drop policy if exists community_members_update on public.community_members;

create policy community_members_update on public.community_members
  for update to authenticated
  using (
    (select auth.uid()) = user_id
    or private.is_community_admin(community_id, (select auth.uid()))
  )
  with check (
    (select auth.uid()) = user_id
    or private.is_community_admin(community_id, (select auth.uid()))
  );
