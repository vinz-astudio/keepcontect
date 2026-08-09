create table public.heartbeat_tokens (
  user_id uuid primary key references auth.users (id) on delete cascade,
  token text not null unique default encode(gen_random_bytes(16), 'hex'),
  created_at timestamptz not null default now()
);
alter table public.heartbeat_tokens enable row level security;
create policy heartbeat_tokens_select on public.heartbeat_tokens
  for select to authenticated using ((select auth.uid()) = user_id);

create table public.behavior_pings (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null default 'app',
  at timestamptz not null default now()
);
create index behavior_pings_user_at_idx on public.behavior_pings (user_id, at desc);
alter table public.behavior_pings enable row level security;
create policy behavior_pings_select on public.behavior_pings
  for select to authenticated using ((select auth.uid()) = user_id);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', null));
  insert into public.heartbeat_tokens (user_id) values (new.id) on conflict do nothing;
  return new;
end;
$$;

insert into public.heartbeat_tokens (user_id)
select id from auth.users on conflict do nothing;