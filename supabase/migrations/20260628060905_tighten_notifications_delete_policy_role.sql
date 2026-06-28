drop policy if exists notifications_delete on public.notifications;

create policy notifications_delete
  on public.notifications
  for delete
  to authenticated
  using ((select auth.uid()) = recipient_id);
