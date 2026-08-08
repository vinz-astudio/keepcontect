-- 每个用户的各个客户端(按设备):平台 + App 版本 + 最后活跃时间。
-- 仅运营遥测,不含行为/隐私内容。
create table if not exists public.clients (
  user_id uuid not null references auth.users(id) on delete cascade,
  client_id text not null,
  platform text,
  app_version text,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key (user_id, client_id)
);

alter table public.clients enable row level security;

drop policy if exists "clients self select" on public.clients;
create policy "clients self select" on public.clients
  for select using (auth.uid() = user_id);

-- App 打开时上报(SECURITY DEFINER:绕过 RLS 写入自己的那行)
create or replace function public.report_client(
  _client_id text, _platform text, _version text
) returns void language plpgsql security definer set search_path to '' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if _client_id is null or length(_client_id) = 0 then return; end if;
  insert into public.clients (user_id, client_id, platform, app_version, first_seen_at, last_seen_at)
  values (_uid, left(_client_id, 64), left(_platform, 32), left(_version, 32), now(), now())
  on conflict (user_id, client_id) do update
    set platform = excluded.platform,
        app_version = excluded.app_version,
        last_seen_at = now();
end;
$$;

grant execute on function public.report_client(text, text, text) to authenticated;
