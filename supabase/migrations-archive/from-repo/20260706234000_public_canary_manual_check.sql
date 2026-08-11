-- Allow GM to temporarily expose a canary to ordinary users' manual update check.
-- Automatic update banners still query released only.

alter table public.app_versions
  add column if not exists public_rollout boolean not null default false;

drop policy if exists "Allow public read of released versions" on public.app_versions;
drop policy if exists "Allow public read of released or public canary versions" on public.app_versions;

create policy "Allow public read of released or public canary versions"
  on public.app_versions for select
  using (
    status = 'released'
    or (status = 'canary' and public_rollout = true)
  );
