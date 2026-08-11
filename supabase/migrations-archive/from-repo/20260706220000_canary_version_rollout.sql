-- Create table for tracking client app versions and rollout status
create table if not exists public.app_versions (
  version varchar(50) primary key,
  apk_url text,
  exe_url text,
  status varchar(20) not null default 'canary', -- 'canary' or 'released'
  created_at timestamptz not null default now()
);

-- Enable Row Level Security
alter table public.app_versions enable row level security;

-- Policy 1: Anyone (including unauthenticated/recipients) can read released versions
create policy "Allow public read of released versions"
  on public.app_versions for select
  using (status = 'released');

-- Policy 2: GMs can read any version
create policy "Allow GMs to read any version"
  on public.app_versions for select
  using (
    auth.uid() is not null and
    private.is_admin(auth.uid())
  );

-- Policy 3: GMs can insert/update versions
create policy "Allow GMs to manage versions"
  on public.app_versions for all
  using (
    auth.uid() is not null and
    private.is_admin(auth.uid())
  );

-- Grant permissions to authenticated and anon roles
grant select on public.app_versions to authenticated, anon;
grant insert, update, delete on public.app_versions to authenticated;

-- Seed the current version as released
insert into public.app_versions (version, status)
values ('0.5.16', 'released')
on conflict (version) do nothing;

-- Seed a new canary version (0.5.17) for testing
insert into public.app_versions (version, status, apk_url, exe_url)
values (
  '0.5.17', 
  'canary', 
  'https://keep-contact-mauve.vercel.app/keep-contact.apk', 
  'https://keep-contact-mauve.vercel.app/desktop/KeepContact-Setup.exe'
)
on conflict (version) do nothing;
