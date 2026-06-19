-- 行为 ping（系统快捷指令心跳）：免登录、用每人专属 token 的网址被 POST/GET。
-- 只记"时间戳 + 行为类别"（闹钟/插电/拔电/开了某App），绝不含 App 身份或名字。
-- 接入现有引擎：每个 ping 同时刷新 device_state.last_heartbeat_at，沿用沉默/暗设备升级逻辑。

-- 专属 token 单独成表（不放 profiles，避免被同组成员的 profiles_select 读到）
create table public.heartbeat_tokens (
  user_id uuid primary key references auth.users (id) on delete cascade,
  token text not null unique default encode(gen_random_bytes(16), 'hex'),
  created_at timestamptz not null default now()
);
alter table public.heartbeat_tokens enable row level security;
create policy heartbeat_tokens_select on public.heartbeat_tokens
  for select to authenticated using ((select auth.uid()) = user_id);

-- 行为 ping 历史（用于"使用频率"展示；判断仍走 device_state 心跳）
create table public.behavior_pings (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null default 'app',  -- coarse pulse marker; triggers are intentionally not classified
  at timestamptz not null default now()
);
create index behavior_pings_user_at_idx on public.behavior_pings (user_id, at desc);
alter table public.behavior_pings enable row level security;
create policy behavior_pings_select on public.behavior_pings
  for select to authenticated using ((select auth.uid()) = user_id);
-- 写入仅经 service-role 的 Edge Function，无 user insert 策略

-- 新用户自动建 token
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', null));
  insert into public.heartbeat_tokens (user_id) values (new.id) on conflict do nothing;
  return new;
end;
$$;

-- 回填现有用户
insert into public.heartbeat_tokens (user_id)
select id from auth.users on conflict do nothing;
