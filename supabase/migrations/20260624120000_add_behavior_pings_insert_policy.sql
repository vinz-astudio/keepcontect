-- Add policy to allow authenticated users to insert their own behavior pings.
create policy behavior_pings_insert on public.behavior_pings
  for insert to authenticated with check (auth.uid() = user_id);
