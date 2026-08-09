create table public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now()
);
create index push_subscriptions_user_idx on public.push_subscriptions (user_id);

alter table public.push_subscriptions enable row level security;

create policy push_subs_select on public.push_subscriptions
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy push_subs_insert on public.push_subscriptions
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy push_subs_update on public.push_subscriptions
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy push_subs_delete on public.push_subscriptions
  for delete to authenticated
  using ((select auth.uid()) = user_id);

alter table public.notifications
  add column pushed_at timestamptz;

create index notifications_unpushed_idx on public.notifications (created_at)
  where pushed_at is null;

create table if not exists private.app_config (
  key text primary key,
  value text not null
);

create or replace function public.get_app_config()
returns jsonb language sql security definer set search_path = '' stable as $$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from private.app_config;
$$;

revoke execute on function public.get_app_config() from public, anon, authenticated;
grant execute on function public.get_app_config() to service_role;

create extension if not exists pg_net;