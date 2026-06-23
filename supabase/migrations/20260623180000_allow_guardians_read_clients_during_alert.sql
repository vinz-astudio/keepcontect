-- Allow guardians and group members to select client device states during active alerts.
drop policy if exists "clients self select" on public.clients;

create policy "clients select during active alert" on public.clients
  for select to authenticated
  using (
    auth.uid() = user_id
    or (
      exists (
        select 1 from public.alerts a
        where a.user_id = clients.user_id
          and a.status = 'open'
          and a.stage in ('group', 'community', 'terminal')
      )
      and (
        private.is_guardian_of(user_id, (select auth.uid()))
        or private.watches_user((select auth.uid()), clients.user_id)
        or private.shares_community((select auth.uid()), clients.user_id)
      )
    )
  );
