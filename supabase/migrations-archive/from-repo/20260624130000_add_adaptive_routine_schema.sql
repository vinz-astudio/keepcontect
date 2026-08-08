-- Alter public.profiles to add routine pattern and data sharing consent columns
alter table public.profiles
  add column routine_pattern text not null default 'regular_9to5',
  add column consent_data_sharing boolean not null default false;

-- Create daily_activity_aggregates table
create table public.daily_activity_aggregates (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  date date not null,
  -- 24 integers representing hourly counts of behavior pings
  hourly_density integer[] not null check (cardinality(hourly_density) = 24),
  created_at timestamptz not null default now(),
  unique(user_id, date)
);

-- Enable RLS on daily_activity_aggregates
alter table public.daily_activity_aggregates enable row level security;

-- RLS policies for daily_activity_aggregates
create policy daily_aggregates_all_own on public.daily_activity_aggregates
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Create user_activity_profiles table
create table public.user_activity_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  -- 24 double precision floats representing custom hourly thresholds (hours)
  hourly_thresholds double precision[] not null check (cardinality(hourly_thresholds) = 24),
  weekend_multiplier double precision not null default 1.0,
  updated_at timestamptz not null default now()
);

-- Enable RLS on user_activity_profiles
alter table public.user_activity_profiles enable row level security;

-- RLS policies for user_activity_profiles (select only, write by service role)
create policy user_profiles_select_own on public.user_activity_profiles
  for select to authenticated using (auth.uid() = user_id);
