-- Harden emergency_info RLS policies.
-- Restrict guardians and watchers from viewing emergency info unless there is an active open alert.

drop policy if exists emergency_info_select on public.emergency_info;

create policy emergency_info_select on public.emergency_info
  for select to authenticated
  using (
    (select auth.uid()) = user_id
    or (
      exists (
        select 1 from public.alerts a
        where a.user_id = emergency_info.user_id
          and a.status = 'open'
          and a.stage in ('group', 'community', 'terminal')
      )
      and (
        private.is_guardian_of(user_id, (select auth.uid()))
        or private.watches_user((select auth.uid()), emergency_info.user_id)
        or private.shares_community((select auth.uid()), emergency_info.user_id)
      )
    )
  );
