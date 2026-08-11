-- Keep Contact — P1 核心 schema：身份 / Community / Group / 监护关系 / 守护人 / 紧急信息
-- 隐私原则：行为数据不在此层；这里只有身份、关系、以及仅限本人/守护人可见的地址与紧急信息。
-- RLS 安全要点：所有 public 表启用 RLS；策略一律 TO authenticated 且带所有权谓词；
--   SECURITY DEFINER 辅助函数放入未暴露的 private schema；UPDATE 同时带 USING + WITH CHECK。

------------------------------------------------------------
-- 0. private schema（不经 Data API 暴露，用于 SECURITY DEFINER 辅助函数，避免 RLS 递归）
------------------------------------------------------------
create schema if not exists private;

------------------------------------------------------------
-- 1. 表
------------------------------------------------------------

-- 1:1 对应 auth.users
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now()
);

create table public.communities (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  invite_code text not null unique default encode(gen_random_bytes(6), 'hex'),
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now()
);

-- Group 可隶属于某 Community（community_id 可空 = 独立 Group）
create table public.groups (
  id uuid primary key default gen_random_uuid(),
  community_id uuid references public.communities (id) on delete set null,
  name text not null check (char_length(name) between 1 and 80),
  invite_code text not null unique default encode(gen_random_bytes(6), 'hex'),
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now()
);

create table public.community_members (
  community_id uuid not null references public.communities (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'member' check (role in ('admin', 'member')),
  status text not null default 'active' check (status in ('pending', 'active')),
  joined_at timestamptz not null default now(),
  primary key (community_id, user_id)
);

-- Group 成员关系，含监护方向（对称 = monitored 与 watching 均 true，默认）
create table public.group_members (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'member' check (role in ('admin', 'member')),
  status text not null default 'active' check (status in ('pending', 'active')),
  monitored boolean not null default true, -- 该用户沉默时，其他人会被告警
  watching boolean not null default true,  -- 该用户会收到关于他人的告警
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

-- 守护人（代理）：guardian 可代 ward 配置、并优先接收 ward 的告警
create table public.guardianships (
  id uuid primary key default gen_random_uuid(),
  guardian_id uuid not null references auth.users (id) on delete cascade,
  ward_id uuid not null references auth.users (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'active', 'revoked')),
  created_at timestamptz not null default now(),
  unique (guardian_id, ward_id),
  check (guardian_id <> ward_id)
);

-- 紧急信息（G3）：默认仅本人与其守护人可见可改。
-- 注意：P4 将新增"告警升级时对授权响应者解锁"的读策略；此处先做归属级保护。
create table public.emergency_info (
  user_id uuid primary key references auth.users (id) on delete cascade,
  home_address text,
  medical_notes text,
  emergency_contact_name text,
  emergency_contact_phone text,
  updated_at timestamptz not null default now()
);

create index on public.groups (community_id);
create index on public.community_members (user_id);
create index on public.group_members (user_id);
create index on public.guardianships (ward_id);
create index on public.guardianships (guardian_id);

------------------------------------------------------------
-- 2. SECURITY DEFINER 辅助函数（private schema，绕过 RLS 以避免策略自递归）
------------------------------------------------------------

create or replace function private.is_group_member(_group_id uuid, _user uuid)
returns boolean language sql security definer set search_path = '' stable as $$
  select exists (
    select 1 from public.group_members gm
    where gm.group_id = _group_id and gm.user_id = _user and gm.status = 'active'
  );
$$;

create or replace function private.is_community_member(_community_id uuid, _user uuid)
returns boolean language sql security definer set search_path = '' stable as $$
  select exists (
    select 1 from public.community_members cm
    where cm.community_id = _community_id and cm.user_id = _user and cm.status = 'active'
  );
$$;

create or replace function private.shares_group_with(_other uuid, _user uuid)
returns boolean language sql security definer set search_path = '' stable as $$
  select exists (
    select 1
    from public.group_members a
    join public.group_members b on a.group_id = b.group_id
    where a.user_id = _user and b.user_id = _other
      and a.status = 'active' and b.status = 'active'
  );
$$;

-- guardian 是否为 ward 的活跃守护人
create or replace function private.is_guardian_of(_ward uuid, _guardian uuid)
returns boolean language sql security definer set search_path = '' stable as $$
  select exists (
    select 1 from public.guardianships g
    where g.ward_id = _ward and g.guardian_id = _guardian and g.status = 'active'
  );
$$;

-- 两用户之间是否存在任一方向的活跃守护关系
create or replace function private.guardian_pair(_a uuid, _b uuid)
returns boolean language sql security definer set search_path = '' stable as $$
  select private.is_guardian_of(_a, _b) or private.is_guardian_of(_b, _a);
$$;

-- 辅助函数仅供策略评估调用：收紧执行权限
revoke execute on all functions in schema private from public;
grant usage on schema private to authenticated;
grant execute on all functions in schema private to authenticated;

------------------------------------------------------------
-- 3. 触发器：新用户建档 + 创建者自动成为 admin 成员
------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', null));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.handle_new_community()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.community_members (community_id, user_id, role, status)
  values (new.id, new.created_by, 'admin', 'active')
  on conflict do nothing;
  return new;
end;
$$;

create trigger on_community_created
  after insert on public.communities
  for each row execute function public.handle_new_community();

create or replace function public.handle_new_group()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.group_members (group_id, user_id, role, status)
  values (new.id, new.created_by, 'admin', 'active')
  on conflict do nothing;
  return new;
end;
$$;

create trigger on_group_created
  after insert on public.groups
  for each row execute function public.handle_new_group();

------------------------------------------------------------
-- 4. 启用 RLS
------------------------------------------------------------
alter table public.profiles          enable row level security;
alter table public.communities       enable row level security;
alter table public.groups            enable row level security;
alter table public.community_members enable row level security;
alter table public.group_members     enable row level security;
alter table public.guardianships     enable row level security;
alter table public.emergency_info    enable row level security;

------------------------------------------------------------
-- 5. 策略
------------------------------------------------------------

-- profiles：本人 / 同组成员 / 守护关系对方可见；仅本人可写
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    (select auth.uid()) = id
    or private.shares_group_with(id, (select auth.uid()))
    or private.guardian_pair(id, (select auth.uid()))
  );

create policy profiles_insert on public.profiles
  for insert to authenticated
  with check ((select auth.uid()) = id);

create policy profiles_update on public.profiles
  for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- communities：成员可见；任意登录用户可创建（须设自己为 created_by）；admin 可改
create policy communities_select on public.communities
  for select to authenticated
  using (private.is_community_member(id, (select auth.uid())));

create policy communities_insert on public.communities
  for insert to authenticated
  with check ((select auth.uid()) = created_by);

create policy communities_update on public.communities
  for update to authenticated
  using (
    exists (
      select 1 from public.community_members cm
      where cm.community_id = id and cm.user_id = (select auth.uid())
        and cm.role = 'admin' and cm.status = 'active'
    )
  )
  with check (true);

-- groups：组成员或所属社区成员可见；创建者须为成员（社区组须先属于该社区）
create policy groups_select on public.groups
  for select to authenticated
  using (
    private.is_group_member(id, (select auth.uid()))
    or (community_id is not null and private.is_community_member(community_id, (select auth.uid())))
  );

create policy groups_insert on public.groups
  for insert to authenticated
  with check (
    (select auth.uid()) = created_by
    and (community_id is null or private.is_community_member(community_id, (select auth.uid())))
  );

create policy groups_update on public.groups
  for update to authenticated
  using (
    exists (
      select 1 from public.group_members gm
      where gm.group_id = id and gm.user_id = (select auth.uid())
        and gm.role = 'admin' and gm.status = 'active'
    )
  )
  with check (true);

-- community_members：同社区成员互相可见；本人可改/退出自己的成员行
create policy community_members_select on public.community_members
  for select to authenticated
  using (private.is_community_member(community_id, (select auth.uid())));

create policy community_members_update on public.community_members
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy community_members_delete on public.community_members
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- group_members：同组成员互相可见（满足"知情可见"）；本人可改监护方向/退出（满足"可撤销"）
create policy group_members_select on public.group_members
  for select to authenticated
  using (private.is_group_member(group_id, (select auth.uid())));

create policy group_members_update on public.group_members
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy group_members_delete on public.group_members
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- guardianships：当事双方可见；任一方可创建（guardian 发起邀请，或 ward 指定）；双方可改状态（接受/撤销）
create policy guardianships_select on public.guardianships
  for select to authenticated
  using (
    (select auth.uid()) = guardian_id or (select auth.uid()) = ward_id
  );

create policy guardianships_insert on public.guardianships
  for insert to authenticated
  with check (
    (select auth.uid()) = guardian_id or (select auth.uid()) = ward_id
  );

create policy guardianships_update on public.guardianships
  for update to authenticated
  using ((select auth.uid()) = guardian_id or (select auth.uid()) = ward_id)
  with check ((select auth.uid()) = guardian_id or (select auth.uid()) = ward_id);

create policy guardianships_delete on public.guardianships
  for delete to authenticated
  using ((select auth.uid()) = guardian_id or (select auth.uid()) = ward_id);

-- emergency_info：仅本人与其活跃守护人可见可写（P4 将追加"告警升级时对授权响应者解锁"读策略）
create policy emergency_info_select on public.emergency_info
  for select to authenticated
  using (
    (select auth.uid()) = user_id
    or private.is_guardian_of(user_id, (select auth.uid()))
  );

create policy emergency_info_insert on public.emergency_info
  for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    or private.is_guardian_of(user_id, (select auth.uid()))
  );

create policy emergency_info_update on public.emergency_info
  for update to authenticated
  using (
    (select auth.uid()) = user_id
    or private.is_guardian_of(user_id, (select auth.uid()))
  )
  with check (
    (select auth.uid()) = user_id
    or private.is_guardian_of(user_id, (select auth.uid()))
  );

------------------------------------------------------------
-- 6. 加入用的 RPC（SECURITY DEFINER：避免把"按邀请码查全表"暴露给前端，防枚举）
------------------------------------------------------------

create or replace function public.join_group_by_code(_code text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  _uid uuid := auth.uid();
  _g public.groups;
begin
  if _uid is null then
    raise exception 'not authenticated';
  end if;

  select * into _g from public.groups where invite_code = _code;
  if not found then
    raise exception 'invalid invite code';
  end if;

  insert into public.group_members (group_id, user_id, status)
  values (_g.id, _uid, 'active')
  on conflict (group_id, user_id) do nothing;

  -- 隶属社区的组：同时确保社区成员身份
  if _g.community_id is not null then
    insert into public.community_members (community_id, user_id, status)
    values (_g.community_id, _uid, 'active')
    on conflict (community_id, user_id) do nothing;
  end if;

  return _g.id;
end;
$$;

create or replace function public.join_community_by_code(_code text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  _uid uuid := auth.uid();
  _c public.communities;
begin
  if _uid is null then
    raise exception 'not authenticated';
  end if;

  select * into _c from public.communities where invite_code = _code;
  if not found then
    raise exception 'invalid invite code';
  end if;

  insert into public.community_members (community_id, user_id, status)
  values (_c.id, _uid, 'active')
  on conflict (community_id, user_id) do nothing;

  return _c.id;
end;
$$;

-- RPC 为公开端点：收紧执行权限到 authenticated（已含 auth.uid() 校验）
revoke execute on function public.join_group_by_code(text) from public, anon;
revoke execute on function public.join_community_by_code(text) from public, anon;
grant execute on function public.join_group_by_code(text) to authenticated;
grant execute on function public.join_community_by_code(text) to authenticated;
