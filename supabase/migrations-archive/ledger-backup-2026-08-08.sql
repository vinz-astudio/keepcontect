SET session_replication_role = replica;

--
-- PostgreSQL database dump
--

-- \restrict eqbJLX5knUXEPSEGRaxRkuhf23yRWrup0PoSHCr1Scfpa4znFve9wJl0HJ7BJdU

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: supabase_migrations; Owner: postgres
--

INSERT INTO "supabase_migrations"."schema_migrations" ("version", "statements", "name", "created_by", "idempotency_key", "rollback") VALUES
	('20260610124403', '{"-- Keep Contact — P1 核心 schema：身份 / Community / Group / 监护关系 / 守护人 / 紧急信息

create schema if not exists private;

-- 1:1 对应 auth.users
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now()
);

create table public.communities (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  invite_code text not null unique default encode(gen_random_bytes(6), ''hex''),
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now()
);

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  community_id uuid references public.communities (id) on delete set null,
  name text not null check (char_length(name) between 1 and 80),
  invite_code text not null unique default encode(gen_random_bytes(6), ''hex''),
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now()
);

create table public.community_members (
  community_id uuid not null references public.communities (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default ''member'' check (role in (''admin'', ''member'')),
  status text not null default ''active'' check (status in (''pending'', ''active'')),
  joined_at timestamptz not null default now(),
  primary key (community_id, user_id)
);

create table public.group_members (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default ''member'' check (role in (''admin'', ''member'')),
  status text not null default ''active'' check (status in (''pending'', ''active'')),
  monitored boolean not null default true,
  watching boolean not null default true,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table public.guardianships (
  id uuid primary key default gen_random_uuid(),
  guardian_id uuid not null references auth.users (id) on delete cascade,
  ward_id uuid not null references auth.users (id) on delete cascade,
  status text not null default ''pending'' check (status in (''pending'', ''active'', ''revoked'')),
  created_at timestamptz not null default now(),
  unique (guardian_id, ward_id),
  check (guardian_id <> ward_id)
);

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

-- SECURITY DEFINER 辅助函数（private schema，避免策略自递归）
create or replace function private.is_group_member(_group_id uuid, _user uuid)
returns boolean language sql security definer set search_path = '''' stable as $$
  select exists (
    select 1 from public.group_members gm
    where gm.group_id = _group_id and gm.user_id = _user and gm.status = ''active''
  );
$$;

create or replace function private.is_community_member(_community_id uuid, _user uuid)
returns boolean language sql security definer set search_path = '''' stable as $$
  select exists (
    select 1 from public.community_members cm
    where cm.community_id = _community_id and cm.user_id = _user and cm.status = ''active''
  );
$$;

create or replace function private.shares_group_with(_other uuid, _user uuid)
returns boolean language sql security definer set search_path = '''' stable as $$
  select exists (
    select 1
    from public.group_members a
    join public.group_members b on a.group_id = b.group_id
    where a.user_id = _user and b.user_id = _other
      and a.status = ''active'' and b.status = ''active''
  );
$$;

create or replace function private.is_guardian_of(_ward uuid, _guardian uuid)
returns boolean language sql security definer set search_path = '''' stable as $$
  select exists (
    select 1 from public.guardianships g
    where g.ward_id = _ward and g.guardian_id = _guardian and g.status = ''active''
  );
$$;

create or replace function private.guardian_pair(_a uuid, _b uuid)
returns boolean language sql security definer set search_path = '''' stable as $$
  select private.is_guardian_of(_a, _b) or private.is_guardian_of(_b, _a);
$$;

revoke execute on all functions in schema private from public;
grant usage on schema private to authenticated;
grant execute on all functions in schema private to authenticated;

-- 触发器：新用户建档 + 创建者自动成为 admin 成员
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '''' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> ''display_name'', null));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.handle_new_community()
returns trigger language plpgsql security definer set search_path = '''' as $$
begin
  insert into public.community_members (community_id, user_id, role, status)
  values (new.id, new.created_by, ''admin'', ''active'')
  on conflict do nothing;
  return new;
end;
$$;

create trigger on_community_created
  after insert on public.communities
  for each row execute function public.handle_new_community();

create or replace function public.handle_new_group()
returns trigger language plpgsql security definer set search_path = '''' as $$
begin
  insert into public.group_members (group_id, user_id, role, status)
  values (new.id, new.created_by, ''admin'', ''active'')
  on conflict do nothing;
  return new;
end;
$$;

create trigger on_group_created
  after insert on public.groups
  for each row execute function public.handle_new_group();

-- 启用 RLS
alter table public.profiles          enable row level security;
alter table public.communities       enable row level security;
alter table public.groups            enable row level security;
alter table public.community_members enable row level security;
alter table public.group_members     enable row level security;
alter table public.guardianships     enable row level security;
alter table public.emergency_info    enable row level security;

-- 策略
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
        and cm.role = ''admin'' and cm.status = ''active''
    )
  )
  with check (true);

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
        and gm.role = ''admin'' and gm.status = ''active''
    )
  )
  with check (true);

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

create policy guardianships_select on public.guardianships
  for select to authenticated
  using ((select auth.uid()) = guardian_id or (select auth.uid()) = ward_id);

create policy guardianships_insert on public.guardianships
  for insert to authenticated
  with check ((select auth.uid()) = guardian_id or (select auth.uid()) = ward_id);

create policy guardianships_update on public.guardianships
  for update to authenticated
  using ((select auth.uid()) = guardian_id or (select auth.uid()) = ward_id)
  with check ((select auth.uid()) = guardian_id or (select auth.uid()) = ward_id);

create policy guardianships_delete on public.guardianships
  for delete to authenticated
  using ((select auth.uid()) = guardian_id or (select auth.uid()) = ward_id);

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

-- 加入用的 RPC（SECURITY DEFINER：防枚举）
create or replace function public.join_group_by_code(_code text)
returns uuid language plpgsql security definer set search_path = '''' as $$
declare
  _uid uuid := auth.uid();
  _g public.groups;
begin
  if _uid is null then
    raise exception ''not authenticated'';
  end if;
  select * into _g from public.groups where invite_code = _code;
  if not found then
    raise exception ''invalid invite code'';
  end if;
  insert into public.group_members (group_id, user_id, status)
  values (_g.id, _uid, ''active'')
  on conflict (group_id, user_id) do nothing;
  if _g.community_id is not null then
    insert into public.community_members (community_id, user_id, status)
    values (_g.community_id, _uid, ''active'')
    on conflict (community_id, user_id) do nothing;
  end if;
  return _g.id;
end;
$$;

create or replace function public.join_community_by_code(_code text)
returns uuid language plpgsql security definer set search_path = '''' as $$
declare
  _uid uuid := auth.uid();
  _c public.communities;
begin
  if _uid is null then
    raise exception ''not authenticated'';
  end if;
  select * into _c from public.communities where invite_code = _code;
  if not found then
    raise exception ''invalid invite code'';
  end if;
  insert into public.community_members (community_id, user_id, status)
  values (_c.id, _uid, ''active'')
  on conflict (community_id, user_id) do nothing;
  return _c.id;
end;
$$;

revoke execute on function public.join_group_by_code(text) from public, anon;
revoke execute on function public.join_community_by_code(text) from public, anon;
grant execute on function public.join_group_by_code(text) to authenticated;
grant execute on function public.join_community_by_code(text) to authenticated;"}', 'core_relationships', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260610124651', '{"revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.handle_new_community() from public, anon, authenticated;
revoke execute on function public.handle_new_group() from public, anon, authenticated;

alter policy communities_update on public.communities
  with check (
    exists (
      select 1 from public.community_members cm
      where cm.community_id = communities.id and cm.user_id = (select auth.uid())
        and cm.role = ''admin'' and cm.status = ''active''
    )
  );

alter policy groups_update on public.groups
  with check (
    exists (
      select 1 from public.group_members gm
      where gm.group_id = groups.id and gm.user_id = (select auth.uid())
        and gm.role = ''admin'' and gm.status = ''active''
    )
  );

create index if not exists communities_created_by_idx on public.communities (created_by);
create index if not exists groups_created_by_idx on public.groups (created_by);"}', 'harden_rls_and_grants', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260610125336', '{"alter policy communities_select on public.communities
  using (
    created_by = (select auth.uid())
    or private.is_community_member(id, (select auth.uid()))
  );

alter policy groups_select on public.groups
  using (
    created_by = (select auth.uid())
    or private.is_group_member(id, (select auth.uid()))
    or (community_id is not null and private.is_community_member(community_id, (select auth.uid())))
  );"}', 'creator_visibility', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260610133542', '{"alter table public.profiles
  add column guardian_code text not null unique default encode(gen_random_bytes(6), ''hex'');

create or replace function public.become_guardian_by_code(_code text)
returns uuid language plpgsql security definer set search_path = '''' as $$
declare
  _uid uuid := auth.uid();
  _ward uuid;
begin
  if _uid is null then
    raise exception ''not authenticated'';
  end if;
  select id into _ward from public.profiles where guardian_code = _code;
  if not found then
    raise exception ''invalid guardian code'';
  end if;
  if _ward = _uid then
    raise exception ''cannot guard yourself'';
  end if;
  insert into public.guardianships (guardian_id, ward_id, status)
  values (_uid, _ward, ''active'')
  on conflict (guardian_id, ward_id) do update set status = ''active'';
  return _ward;
end;
$$;

revoke execute on function public.become_guardian_by_code(text) from public, anon;
grant execute on function public.become_guardian_by_code(text) to authenticated;"}', 'guardian_codes', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260610142638', '{"create table public.device_state (
  user_id uuid primary key references auth.users (id) on delete cascade,
  status text not null default ''normal'' check (status in (''normal'', ''alert'')),
  last_heartbeat_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.alerts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  cause text not null check (cause in (''silence'', ''dark_device'', ''sos'')),
  stage text not null check (stage in (''self'', ''group'', ''community'', ''terminal'')),
  status text not null default ''open'' check (status in (''open'', ''resolved'', ''cancelled'')),
  opened_at timestamptz not null default now(),
  stage_entered_at timestamptz not null default now(),
  next_deadline timestamptz,
  paused_until timestamptz,
  paused_by uuid references auth.users (id),
  resolved_at timestamptz,
  resolved_by uuid references auth.users (id),
  updated_at timestamptz not null default now()
);
create unique index alerts_one_open_per_user on public.alerts (user_id) where status = ''open'';
create index alerts_open_idx on public.alerts (status) where status = ''open'';

create table public.alert_events (
  id uuid primary key default gen_random_uuid(),
  alert_id uuid not null references public.alerts (id) on delete cascade,
  actor_id uuid references auth.users (id),
  kind text not null check (kind in (''raised'', ''escalated'', ''on_it'', ''confirmed_safe'', ''resolved'', ''auto_resolved'')),
  note text,
  at timestamptz not null default now()
);
create index alert_events_alert_idx on public.alert_events (alert_id, at);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users (id) on delete cascade,
  alert_id uuid references public.alerts (id) on delete cascade,
  kind text not null,
  body text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index notifications_recipient_idx on public.notifications (recipient_id, created_at desc);

create or replace function private.watches_user(_watcher uuid, _target uuid)
returns boolean language sql security definer set search_path = '''' stable as $$
  select exists (
    select 1
    from public.group_members t
    join public.group_members w on w.group_id = t.group_id
    where t.user_id = _target and t.monitored and t.status = ''active''
      and w.user_id = _watcher and w.watching and w.status = ''active''
      and _watcher <> _target
  );
$$;

create or replace function private.shares_community(_a uuid, _b uuid)
returns boolean language sql security definer set search_path = '''' stable as $$
  select exists (
    select 1
    from public.community_members x
    join public.community_members y on x.community_id = y.community_id
    where x.user_id = _a and y.user_id = _b
      and x.status = ''active'' and y.status = ''active'' and _a <> _b
  );
$$;

create or replace function private.can_see_alert(_alert_id uuid, _user uuid)
returns boolean language sql security definer set search_path = '''' stable as $$
  select exists (
    select 1 from public.alerts a
    where a.id = _alert_id and (
      a.user_id = _user
      or private.is_guardian_of(a.user_id, _user)
      or private.watches_user(_user, a.user_id)
      or (a.stage in (''community'', ''terminal'') and private.shares_community(_user, a.user_id))
    )
  );
$$;

revoke execute on all functions in schema private from public;
grant execute on all functions in schema private to authenticated;

alter table public.device_state  enable row level security;
alter table public.alerts        enable row level security;
alter table public.alert_events  enable row level security;
alter table public.notifications enable row level security;

create policy device_state_select on public.device_state
  for select to authenticated
  using (
    (select auth.uid()) = user_id
    or private.watches_user((select auth.uid()), user_id)
    or private.is_guardian_of(user_id, (select auth.uid()))
  );

create policy alerts_select on public.alerts
  for select to authenticated
  using (
    (select auth.uid()) = user_id
    or private.is_guardian_of(user_id, (select auth.uid()))
    or private.watches_user((select auth.uid()), user_id)
    or (stage in (''community'', ''terminal'') and private.shares_community((select auth.uid()), user_id))
  );

create policy alert_events_select on public.alert_events
  for select to authenticated
  using (private.can_see_alert(alert_id, (select auth.uid())));

create policy notifications_select on public.notifications
  for select to authenticated
  using ((select auth.uid()) = recipient_id);

create policy notifications_update on public.notifications
  for update to authenticated
  using ((select auth.uid()) = recipient_id)
  with check ((select auth.uid()) = recipient_id);

create policy emergency_info_reveal_on_escalation on public.emergency_info
  for select to authenticated
  using (
    exists (
      select 1 from public.alerts a
      where a.user_id = emergency_info.user_id
        and a.status = ''open''
        and a.stage in (''group'', ''community'', ''terminal'')
        and (
          private.watches_user((select auth.uid()), emergency_info.user_id)
          or private.shares_community((select auth.uid()), emergency_info.user_id)
        )
    )
  );"}', 'escalation_schema', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260610143019', '{"create or replace function private.notify_stage(_alert_id uuid, _user uuid, _stage text)
returns void language plpgsql security definer set search_path = '''' as $$
declare _name text;
begin
  select coalesce(display_name, ''某位成员'') into _name from public.profiles where id = _user;

  if _stage = ''self'' then
    insert into public.notifications (recipient_id, alert_id, kind, body)
    values (_user, _alert_id, ''self'', ''检测到异常沉默，请打开 App 完成解锁报平安。'');

  elsif _stage = ''group'' then
    insert into public.notifications (recipient_id, alert_id, kind, body)
    select distinct s.r, _alert_id, ''group'', _name || '' 出现异常沉默，请尽快联系确认其安全。''
    from (
      select w.user_id as r
      from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _user and t.monitored and t.status = ''active''
        and w.watching and w.status = ''active'' and w.user_id <> _user
      union
      select g.guardian_id from public.guardianships g
      where g.ward_id = _user and g.status = ''active''
    ) s;

  elsif _stage = ''community'' then
    insert into public.notifications (recipient_id, alert_id, kind, body)
    select distinct y.user_id, _alert_id, ''community'',
      ''社区警示：'' || _name || '' 长时间失联且其小组无人响应，请协助推动联系。''
    from public.community_members x
    join public.community_members y on x.community_id = y.community_id
    where x.user_id = _user and x.status = ''active''
      and y.status = ''active'' and y.user_id <> _user;

  elsif _stage = ''terminal'' then
    insert into public.notifications (recipient_id, alert_id, kind, body)
    select distinct s.r, _alert_id, ''terminal'',
      ''紧急：'' || _name || '' 持续无响应。已为你解锁其地址与紧急联系人，请上门探视或协助报警。''
    from (
      select w.user_id as r
      from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _user and t.monitored and t.status = ''active''
        and w.watching and w.status = ''active'' and w.user_id <> _user
      union
      select g.guardian_id from public.guardianships g
      where g.ward_id = _user and g.status = ''active''
    ) s;
  end if;
end;
$$;

create or replace function public.send_heartbeat(_status text)
returns void language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  if _status not in (''normal'', ''alert'') then raise exception ''bad status''; end if;

  insert into public.device_state (user_id, status, last_heartbeat_at, updated_at)
  values (_uid, _status, now(), now())
  on conflict (user_id) do update
    set status = excluded.status, last_heartbeat_at = now(), updated_at = now();

  if _status = ''normal'' then
    update public.alerts
      set status = ''resolved'', resolved_at = now(), resolved_by = _uid, updated_at = now()
      where user_id = _uid and status = ''open'' and cause in (''silence'', ''dark_device'');
  end if;
end;
$$;

create or replace function public.resolve_my_alert()
returns void language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid(); _aid uuid;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  update public.alerts set status = ''resolved'', resolved_at = now(), resolved_by = _uid, updated_at = now()
    where user_id = _uid and status = ''open'' returning id into _aid;
  if _aid is not null then
    insert into public.alert_events (alert_id, actor_id, kind) values (_aid, _uid, ''resolved'');
  end if;
  insert into public.device_state (user_id, status, last_heartbeat_at, updated_at)
  values (_uid, ''normal'', now(), now())
  on conflict (user_id) do update set status = ''normal'', last_heartbeat_at = now(), updated_at = now();
end;
$$;

create or replace function public.raise_sos()
returns uuid language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid(); _aid uuid;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  select id into _aid from public.alerts where user_id = _uid and status = ''open'';
  if _aid is null then
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    values (_uid, ''sos'', ''group'', now(), now() + interval ''1 hour'')
    returning id into _aid;
    insert into public.alert_events (alert_id, actor_id, kind) values (_aid, _uid, ''raised'');
  else
    update public.alerts set cause = ''sos'', stage = ''group'', stage_entered_at = now(),
      next_deadline = now() + interval ''1 hour'', paused_until = null, updated_at = now()
      where id = _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note) values (_aid, _uid, ''escalated'', ''sos'');
  end if;
  perform private.notify_stage(_aid, _uid, ''group'');
  return _aid;
end;
$$;

create or replace function public.ack_alert(_alert_id uuid, _minutes int default 30)
returns void language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid(); _target uuid; _aname text; _tname text;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  if not private.can_see_alert(_alert_id, _uid) then raise exception ''forbidden''; end if;

  update public.alerts
    set paused_until = now() + make_interval(mins => _minutes), paused_by = _uid, updated_at = now()
    where id = _alert_id and status = ''open'' returning user_id into _target;
  if _target is null then raise exception ''alert not open''; end if;

  insert into public.alert_events (alert_id, actor_id, kind) values (_alert_id, _uid, ''on_it'');

  select coalesce(display_name, ''一位关怀者'') into _aname from public.profiles where id = _uid;
  select coalesce(display_name, ''某位成员'') into _tname from public.profiles where id = _target;
  insert into public.notifications (recipient_id, alert_id, kind, body)
  select distinct s.r, _alert_id, ''on_it'', _aname || '' 正在跟进 '' || _tname || '' 的情况。''
  from (
    select _target as r
    union
    select w.user_id from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _target and t.monitored and t.status = ''active''
        and w.watching and w.status = ''active'' and w.user_id <> _uid
  ) s;
end;
$$;

create or replace function public.resolve_alert(_alert_id uuid)
returns void language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid(); _target uuid; _tname text;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  if not private.can_see_alert(_alert_id, _uid) then raise exception ''forbidden''; end if;

  update public.alerts
    set status = ''resolved'', resolved_at = now(), resolved_by = _uid, updated_at = now()
    where id = _alert_id and status = ''open'' returning user_id into _target;
  if _target is null then raise exception ''alert not open''; end if;

  insert into public.alert_events (alert_id, actor_id, kind) values (_alert_id, _uid, ''confirmed_safe'');

  select coalesce(display_name, ''某位成员'') into _tname from public.profiles where id = _target;
  insert into public.notifications (recipient_id, alert_id, kind, body)
  select distinct s.r, _alert_id, ''resolved'', _tname || '' 已确认安全，告警解除。''
  from (
    select _target as r
    union
    select w.user_id from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _target and t.monitored and t.status = ''active''
        and w.watching and w.status = ''active''
  ) s;
end;
$$;

create or replace function public.process_escalations()
returns void language plpgsql security definer set search_path = '''' as $$
declare
  _self_grace   constant interval := interval ''30 minutes'';
  _group_dur    constant interval := interval ''1 hour'';
  _comm_dur     constant interval := interval ''2 hours'';
  _dark         constant interval := interval ''90 minutes'';
  r record;
  _aid uuid;
  _new text;
begin
  for r in
    select ds.user_id,
           (ds.last_heartbeat_at < now() - _dark) as is_dark
    from public.device_state ds
    where (ds.status = ''alert'' or ds.last_heartbeat_at < now() - _dark)
      and exists (select 1 from public.group_members gm
                  where gm.user_id = ds.user_id and gm.monitored and gm.status = ''active'')
      and not exists (select 1 from public.alerts a where a.user_id = ds.user_id and a.status = ''open'')
  loop
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    values (r.user_id, case when r.is_dark then ''dark_device'' else ''silence'' end,
            ''self'', now(), now() + _self_grace)
    returning id into _aid;
    insert into public.alert_events (alert_id, kind) values (_aid, ''raised'');
    perform private.notify_stage(_aid, r.user_id, ''self'');
  end loop;

  for r in
    select a.id from public.alerts a
    join public.device_state ds on ds.user_id = a.user_id
    where a.status = ''open'' and a.cause in (''silence'', ''dark_device'')
      and ds.status = ''normal'' and ds.last_heartbeat_at > now() - _dark
  loop
    update public.alerts set status = ''resolved'', resolved_at = now(), updated_at = now() where id = r.id;
    insert into public.alert_events (alert_id, kind) values (r.id, ''auto_resolved'');
  end loop;

  for r in
    select * from public.alerts
    where status = ''open''
      and next_deadline is not null and next_deadline <= now()
      and coalesce(paused_until, to_timestamp(0)) <= now()
  loop
    _new := case r.stage
              when ''self'' then ''group''
              when ''group'' then ''community''
              when ''community'' then ''terminal''
              else ''terminal'' end;
    update public.alerts
      set stage = _new, stage_entered_at = now(), paused_until = null, updated_at = now(),
          next_deadline = case _new when ''group'' then now() + _group_dur
                                    when ''community'' then now() + _comm_dur
                                    else null end
      where id = r.id;
    insert into public.alert_events (alert_id, kind, note) values (r.id, ''escalated'', _new);
    perform private.notify_stage(r.id, r.user_id, _new);
  end loop;
end;
$$;

revoke execute on function public.send_heartbeat(text) from public, anon;
revoke execute on function public.resolve_my_alert() from public, anon;
revoke execute on function public.raise_sos() from public, anon;
revoke execute on function public.ack_alert(uuid, int) from public, anon;
revoke execute on function public.resolve_alert(uuid) from public, anon;
grant execute on function public.send_heartbeat(text) to authenticated;
grant execute on function public.resolve_my_alert() to authenticated;
grant execute on function public.raise_sos() to authenticated;
grant execute on function public.ack_alert(uuid, int) to authenticated;
grant execute on function public.resolve_alert(uuid) to authenticated;

revoke execute on function public.process_escalations() from public, anon, authenticated;"}', 'escalation_logic', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260611042251', '{"alter table public.notifications
  add column params jsonb not null default ''{}'';

create or replace function private.notify_stage(_alert_id uuid, _user uuid, _stage text)
returns void language plpgsql security definer set search_path = '''' as $$
declare _name text; _p jsonb;
begin
  select coalesce(display_name, '''') into _name from public.profiles where id = _user;
  _p := jsonb_build_object(''name'', _name);

  if _stage = ''self'' then
    insert into public.notifications (recipient_id, alert_id, kind, body, params)
    values (_user, _alert_id, ''self'', ''检测到异常沉默，请打开 App 完成解锁报平安。'', ''{}''::jsonb);

  elsif _stage = ''group'' then
    insert into public.notifications (recipient_id, alert_id, kind, body, params)
    select distinct s.r, _alert_id, ''group'', _name || '' 出现异常沉默，请尽快联系确认其安全。'', _p
    from (
      select w.user_id as r
      from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _user and t.monitored and t.status = ''active''
        and w.watching and w.status = ''active'' and w.user_id <> _user
      union
      select g.guardian_id from public.guardianships g
      where g.ward_id = _user and g.status = ''active''
    ) s;

  elsif _stage = ''community'' then
    insert into public.notifications (recipient_id, alert_id, kind, body, params)
    select distinct y.user_id, _alert_id, ''community'',
      ''社区警示：'' || _name || '' 长时间失联且其小组无人响应，请协助推动联系。'', _p
    from public.community_members x
    join public.community_members y on x.community_id = y.community_id
    where x.user_id = _user and x.status = ''active''
      and y.status = ''active'' and y.user_id <> _user;

  elsif _stage = ''terminal'' then
    insert into public.notifications (recipient_id, alert_id, kind, body, params)
    select distinct s.r, _alert_id, ''terminal'',
      ''紧急：'' || _name || '' 持续无响应。已为你解锁其地址与紧急联系人，请上门探视或协助报警。'', _p
    from (
      select w.user_id as r
      from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _user and t.monitored and t.status = ''active''
        and w.watching and w.status = ''active'' and w.user_id <> _user
      union
      select g.guardian_id from public.guardianships g
      where g.ward_id = _user and g.status = ''active''
    ) s;
  end if;
end;
$$;

create or replace function public.ack_alert(_alert_id uuid, _minutes int default 30)
returns void language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid(); _target uuid; _aname text; _tname text;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  if not private.can_see_alert(_alert_id, _uid) then raise exception ''forbidden''; end if;

  update public.alerts
    set paused_until = now() + make_interval(mins => _minutes), paused_by = _uid, updated_at = now()
    where id = _alert_id and status = ''open'' returning user_id into _target;
  if _target is null then raise exception ''alert not open''; end if;

  insert into public.alert_events (alert_id, actor_id, kind) values (_alert_id, _uid, ''on_it'');

  select coalesce(display_name, '''') into _aname from public.profiles where id = _uid;
  select coalesce(display_name, '''') into _tname from public.profiles where id = _target;
  insert into public.notifications (recipient_id, alert_id, kind, body, params)
  select distinct s.r, _alert_id, ''on_it'', _aname || '' 正在跟进 '' || _tname || '' 的情况。'',
    jsonb_build_object(''actor'', _aname, ''target'', _tname)
  from (
    select _target as r
    union
    select w.user_id from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _target and t.monitored and t.status = ''active''
        and w.watching and w.status = ''active'' and w.user_id <> _uid
  ) s;
end;
$$;

create or replace function public.resolve_alert(_alert_id uuid)
returns void language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid(); _target uuid; _tname text;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  if not private.can_see_alert(_alert_id, _uid) then raise exception ''forbidden''; end if;

  update public.alerts
    set status = ''resolved'', resolved_at = now(), resolved_by = _uid, updated_at = now()
    where id = _alert_id and status = ''open'' returning user_id into _target;
  if _target is null then raise exception ''alert not open''; end if;

  insert into public.alert_events (alert_id, actor_id, kind) values (_alert_id, _uid, ''confirmed_safe'');

  select coalesce(display_name, '''') into _tname from public.profiles where id = _target;
  insert into public.notifications (recipient_id, alert_id, kind, body, params)
  select distinct s.r, _alert_id, ''resolved'', _tname || '' 已确认安全，告警解除。'',
    jsonb_build_object(''target'', _tname)
  from (
    select _target as r
    union
    select w.user_id from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _target and t.monitored and t.status = ''active''
        and w.watching and w.status = ''active''
  ) s;
end;
$$;"}', 'notification_params', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260616170727', '{"-- 守望者设的报平安任务：睡眠窗（含醒后宽限）内不催打卡、也不算漏卡，顺延到醒后。
create or replace function public.process_checkin_tasks()
returns void language plpgsql security definer set search_path to '''' as $function$
declare t record; _done boolean; _wname text;
begin
  for t in select * from public.checkin_tasks
           where status = ''active'' and cycle_state = ''idle''
             and next_due_at is not null and next_due_at <= now()
             and not private.sleep_relaxed(ward_id, now())  -- 睡眠期不催
  loop
    insert into public.notifications (recipient_id, kind, body, params)
    values (t.ward_id, ''task_due'', ''到点报平安啦，点开 App 完成确认。'',
            jsonb_build_object(''label'', t.label));
    update public.checkin_tasks set cycle_state = ''due_notified'', updated_at = now() where id = t.id;
  end loop;

  for t in select * from public.checkin_tasks
           where status = ''active'' and cycle_state = ''due_notified''
             and next_due_at + make_interval(mins => grace_minutes) <= now()
             and not private.sleep_relaxed(ward_id, now())  -- 睡眠期不判漏卡
  loop
    select exists (
      select 1 from public.device_state ds
      where ds.user_id = t.ward_id and ds.last_heartbeat_at >= t.next_due_at
    ) into _done;

    if not _done then
      select coalesce(display_name, '''') into _wname from public.profiles where id = t.ward_id;
      insert into public.notifications (recipient_id, kind, body, params)
      select distinct r.uid, ''task_missed'',
        _wname || '' 未完成定时报平安，请关注。'',
        jsonb_build_object(''name'', _wname, ''label'', t.label)
      from (
        select t.created_by as uid where t.created_by <> t.ward_id
        union
        select g.guardian_id from public.guardianships g
          where t.created_by = t.ward_id and g.ward_id = t.ward_id and g.status = ''active''
        union
        select w.user_id from public.group_members gm
          join public.group_members w on w.group_id = gm.group_id
          where t.created_by = t.ward_id
            and gm.user_id = t.ward_id and gm.monitored and gm.status = ''active''
            and w.watching and w.status = ''active'' and w.user_id <> t.ward_id
            and not exists (select 1 from public.guardianships g2
                            where g2.ward_id = t.ward_id and g2.status = ''active'')
      ) r;
    end if;

    update public.checkin_tasks set
      cycle_state = ''idle'',
      next_due_at = case
        when kind = ''interval'' then now() + make_interval(hours => interval_hours)
        else next_due_at + make_interval(days => ceil(extract(epoch from (now() - next_due_at)) / 86400.0)::int)
      end,
      updated_at = now()
      where id = t.id;
  end loop;
end;
$function$;"}', 'checkin_tasks_respect_sleep', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260611045853', '{"create table public.push_subscriptions (
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
returns jsonb language sql security definer set search_path = '''' stable as $$
  select coalesce(jsonb_object_agg(key, value), ''{}''::jsonb) from private.app_config;
$$;

revoke execute on function public.get_app_config() from public, anon, authenticated;
grant execute on function public.get_app_config() to service_role;

create extension if not exists pg_net;"}', 'web_push', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260612212401', '{"create table public.checkin_tasks (
  id uuid primary key default gen_random_uuid(),
  ward_id uuid not null references auth.users (id) on delete cascade,
  created_by uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in (''daily'', ''interval'')),
  due_time_utc time,
  interval_hours int check (interval_hours is null or interval_hours >= 2),
  grace_minutes int not null default 30 check (grace_minutes between 10 and 240),
  label text not null default '''' ,
  status text not null default ''pending'' check (status in (''pending'', ''active'', ''declined'', ''revoked'')),
  cycle_state text not null default ''idle'' check (cycle_state in (''idle'', ''due_notified'')),
  next_due_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((kind = ''daily'' and due_time_utc is not null) or (kind = ''interval'' and interval_hours is not null))
);
create index checkin_tasks_due_idx on public.checkin_tasks (next_due_at) where status = ''active'';
create index checkin_tasks_ward_idx on public.checkin_tasks (ward_id);

alter table public.checkin_tasks enable row level security;

create policy checkin_tasks_select on public.checkin_tasks
  for select to authenticated
  using ((select auth.uid()) = ward_id or (select auth.uid()) = created_by);

create or replace function public.create_checkin_task(
  _ward uuid,
  _kind text,
  _due_time_utc time default null,
  _interval_hours int default null,
  _first_due timestamptz default null,
  _grace int default 30,
  _label text default ''''
) returns uuid language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid(); _id uuid; _self boolean; _name text;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  _self := (_uid = _ward);
  if not _self and not private.is_guardian_of(_ward, _uid) then
    raise exception ''only the person or their guardian can create tasks'';
  end if;

  insert into public.checkin_tasks
    (ward_id, created_by, kind, due_time_utc, interval_hours, grace_minutes, label,
     status, next_due_at)
  values
    (_ward, _uid, _kind, _due_time_utc, _interval_hours,
     coalesce(_grace, 30), coalesce(_label, ''''),
     case when _self then ''active'' else ''pending'' end,
     case when _self then coalesce(_first_due,
       case when _kind = ''interval'' then now() + make_interval(hours => _interval_hours) end)
     end)
  returning id into _id;

  if not _self then
    select coalesce(display_name, '''') into _name from public.profiles where id = _uid;
    insert into public.notifications (recipient_id, kind, body, params)
    values (_ward, ''task_invite'',
      _name || '' 为你设置了报平安任务，请确认是否接受。'',
      jsonb_build_object(''name'', _name, ''label'', coalesce(_label, '''')));
  end if;
  return _id;
end;
$$;

create or replace function public.respond_checkin_task(_task uuid, _accept boolean, _first_due timestamptz default null)
returns void language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid(); _t public.checkin_tasks; _name text;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  select * into _t from public.checkin_tasks where id = _task and ward_id = _uid and status = ''pending'';
  if not found then raise exception ''task not found or not pending''; end if;

  update public.checkin_tasks
    set status = case when _accept then ''active'' else ''declined'' end,
        next_due_at = case when _accept then coalesce(_first_due,
          case when _t.kind = ''interval'' then now() + make_interval(hours => _t.interval_hours) end) end,
        updated_at = now()
    where id = _task;

  select coalesce(display_name, '''') into _name from public.profiles where id = _uid;
  insert into public.notifications (recipient_id, kind, body, params)
  values (_t.created_by,
    case when _accept then ''task_accepted'' else ''task_declined'' end,
    _name || case when _accept then '' 接受了报平安任务。'' else '' 拒绝了报平安任务。'' end,
    jsonb_build_object(''name'', _name, ''label'', _t.label));
end;
$$;

create or replace function public.revoke_checkin_task(_task uuid)
returns void language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  update public.checkin_tasks set status = ''revoked'', updated_at = now()
    where id = _task and (ward_id = _uid or created_by = _uid) and status in (''pending'', ''active'');
  if not found then raise exception ''task not found''; end if;
end;
$$;

revoke execute on function public.create_checkin_task(uuid, text, time, int, timestamptz, int, text) from public, anon;
revoke execute on function public.respond_checkin_task(uuid, boolean, timestamptz) from public, anon;
revoke execute on function public.revoke_checkin_task(uuid) from public, anon;
grant execute on function public.create_checkin_task(uuid, text, time, int, timestamptz, int, text) to authenticated;
grant execute on function public.respond_checkin_task(uuid, boolean, timestamptz) to authenticated;
grant execute on function public.revoke_checkin_task(uuid) to authenticated;

create or replace function public.process_checkin_tasks()
returns void language plpgsql security definer set search_path = '''' as $$
declare t record; _done boolean; _wname text;
begin
  for t in select * from public.checkin_tasks
           where status = ''active'' and cycle_state = ''idle''
             and next_due_at is not null and next_due_at <= now()
  loop
    insert into public.notifications (recipient_id, kind, body, params)
    values (t.ward_id, ''task_due'', ''到点报平安啦，点开 App 完成确认。'',
            jsonb_build_object(''label'', t.label));
    update public.checkin_tasks set cycle_state = ''due_notified'', updated_at = now() where id = t.id;
  end loop;

  for t in select * from public.checkin_tasks
           where status = ''active'' and cycle_state = ''due_notified''
             and next_due_at + make_interval(mins => grace_minutes) <= now()
  loop
    select exists (
      select 1 from public.device_state ds
      where ds.user_id = t.ward_id and ds.last_heartbeat_at >= t.next_due_at
    ) into _done;

    if not _done then
      select coalesce(display_name, '''') into _wname from public.profiles where id = t.ward_id;
      insert into public.notifications (recipient_id, kind, body, params)
      select distinct r.uid, ''task_missed'',
        _wname || '' 未完成定时报平安，请关注。'',
        jsonb_build_object(''name'', _wname, ''label'', t.label)
      from (
        select t.created_by as uid where t.created_by <> t.ward_id
        union
        select g.guardian_id from public.guardianships g
          where t.created_by = t.ward_id and g.ward_id = t.ward_id and g.status = ''active''
        union
        select w.user_id from public.group_members gm
          join public.group_members w on w.group_id = gm.group_id
          where t.created_by = t.ward_id
            and gm.user_id = t.ward_id and gm.monitored and gm.status = ''active''
            and w.watching and w.status = ''active'' and w.user_id <> t.ward_id
            and not exists (select 1 from public.guardianships g2
                            where g2.ward_id = t.ward_id and g2.status = ''active'')
      ) r;
    end if;

    update public.checkin_tasks set
      cycle_state = ''idle'',
      next_due_at = case
        when kind = ''interval'' then now() + make_interval(hours => interval_hours)
        else next_due_at + make_interval(days => ceil(extract(epoch from (now() - next_due_at)) / 86400.0)::int)
      end,
      updated_at = now()
      where id = t.id;
  end loop;
end;
$$;

revoke execute on function public.process_checkin_tasks() from public, anon, authenticated;

select cron.schedule(''process-checkin-tasks'', ''* * * * *'', $$ select public.process_checkin_tasks(); $$);"}', 'checkin_tasks', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260613050040', '{"create table public.heartbeat_tokens (
  user_id uuid primary key references auth.users (id) on delete cascade,
  token text not null unique default encode(gen_random_bytes(16), ''hex''),
  created_at timestamptz not null default now()
);
alter table public.heartbeat_tokens enable row level security;
create policy heartbeat_tokens_select on public.heartbeat_tokens
  for select to authenticated using ((select auth.uid()) = user_id);

create table public.behavior_pings (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null default ''app'',
  at timestamptz not null default now()
);
create index behavior_pings_user_at_idx on public.behavior_pings (user_id, at desc);
alter table public.behavior_pings enable row level security;
create policy behavior_pings_select on public.behavior_pings
  for select to authenticated using ((select auth.uid()) = user_id);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '''' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> ''display_name'', null));
  insert into public.heartbeat_tokens (user_id) values (new.id) on conflict do nothing;
  return new;
end;
$$;

insert into public.heartbeat_tokens (user_id)
select id from auth.users on conflict do nothing;"}', 'behavior_pings', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260613152541', '{"create or replace function public.process_escalations()
returns void language plpgsql security definer set search_path = '''' as $$
declare
  _self_grace   constant interval := interval ''30 minutes'';
  _group_dur    constant interval := interval ''1 hour'';
  _comm_dur     constant interval := interval ''2 hours'';
  _dark         constant interval := interval ''18 hours'';
  r record;
  _aid uuid;
  _new text;
begin
  for r in
    select ds.user_id,
           (ds.last_heartbeat_at < now() - _dark) as is_dark
    from public.device_state ds
    where (ds.status = ''alert'' or ds.last_heartbeat_at < now() - _dark)
      and exists (select 1 from public.group_members gm
                  where gm.user_id = ds.user_id and gm.monitored and gm.status = ''active'')
      and not exists (select 1 from public.alerts a where a.user_id = ds.user_id and a.status = ''open'')
  loop
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    values (r.user_id, case when r.is_dark then ''dark_device'' else ''silence'' end,
            ''self'', now(), now() + _self_grace)
    returning id into _aid;
    insert into public.alert_events (alert_id, kind) values (_aid, ''raised'');
    perform private.notify_stage(_aid, r.user_id, ''self'');
  end loop;

  for r in
    select a.id from public.alerts a
    join public.device_state ds on ds.user_id = a.user_id
    where a.status = ''open'' and a.cause in (''silence'', ''dark_device'')
      and ds.status = ''normal'' and ds.last_heartbeat_at > now() - _dark
  loop
    update public.alerts set status = ''resolved'', resolved_at = now(), updated_at = now() where id = r.id;
    insert into public.alert_events (alert_id, kind) values (r.id, ''auto_resolved'');
  end loop;

  for r in
    select * from public.alerts
    where status = ''open''
      and next_deadline is not null and next_deadline <= now()
      and coalesce(paused_until, to_timestamp(0)) <= now()
  loop
    _new := case r.stage
              when ''self'' then ''group''
              when ''group'' then ''community''
              when ''community'' then ''terminal''
              else ''terminal'' end;
    update public.alerts
      set stage = _new, stage_entered_at = now(), paused_until = null, updated_at = now(),
          next_deadline = case _new when ''group'' then now() + _group_dur
                                    when ''community'' then now() + _comm_dur
                                    else null end
      where id = r.id;
    insert into public.alert_events (alert_id, kind, note) values (r.id, ''escalated'', _new);
    perform private.notify_stage(r.id, r.user_id, _new);
  end loop;
end;
$$;"}', 'tune_dark_threshold', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260613194637', '{"create or replace function public.send_heartbeat(_status text)
returns void language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  if _status not in (''normal'', ''alert'') then raise exception ''bad status''; end if;
  insert into public.device_state (user_id, status, last_heartbeat_at, updated_at)
  values (_uid, _status, now(), now())
  on conflict (user_id) do update
    set status = excluded.status, last_heartbeat_at = now(), updated_at = now();
end;
$$;

create or replace function public.process_escalations()
returns void language plpgsql security definer set search_path = '''' as $$
declare
  _self_grace   constant interval := interval ''30 minutes'';
  _group_dur    constant interval := interval ''1 hour'';
  _comm_dur     constant interval := interval ''2 hours'';
  _dark         constant interval := interval ''18 hours'';
  r record;
  _aid uuid;
  _new text;
begin
  for r in
    select ds.user_id,
           (ds.last_heartbeat_at < now() - _dark) as is_dark
    from public.device_state ds
    where (ds.status = ''alert'' or ds.last_heartbeat_at < now() - _dark)
      and exists (select 1 from public.group_members gm
                  where gm.user_id = ds.user_id and gm.monitored and gm.status = ''active'')
      and not exists (select 1 from public.alerts a where a.user_id = ds.user_id and a.status = ''open'')
  loop
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    values (r.user_id, case when r.is_dark then ''dark_device'' else ''silence'' end,
            ''self'', now(), now() + _self_grace)
    returning id into _aid;
    insert into public.alert_events (alert_id, kind) values (_aid, ''raised'');
    perform private.notify_stage(_aid, r.user_id, ''self'');
  end loop;

  for r in
    select * from public.alerts
    where status = ''open''
      and next_deadline is not null and next_deadline <= now()
      and coalesce(paused_until, to_timestamp(0)) <= now()
  loop
    _new := case r.stage
              when ''self'' then ''group''
              when ''group'' then ''community''
              when ''community'' then ''terminal''
              else ''terminal'' end;
    update public.alerts
      set stage = _new, stage_entered_at = now(), paused_until = null, updated_at = now(),
          next_deadline = case _new when ''group'' then now() + _group_dur
                                    when ''community'' then now() + _comm_dur
                                    else null end
      where id = r.id;
    insert into public.alert_events (alert_id, kind, note) values (r.id, ''escalated'', _new);
    perform private.notify_stage(r.id, r.user_id, _new);
  end loop;
end;
$$;"}', 'require_pattern_to_resolve', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260613200717', '{"-- 服务器侧\"时段感知沉默阈值\"：用 behavior_pings 历史学每个时段的常态间隔，
-- 判断\"此刻这个时段、按你平时频率，沉默这么久正常吗\"。天然理解睡眠（夜里常态间隔大）。
-- UTC 坐标即可（用户作息在本地固定=在 UTC 固定）。数据不足/学习期回退到 18h 冷启动阈值。
create or replace function private.silence_threshold(_user uuid)
returns interval language plpgsql security definer set search_path = '''' stable as $$
declare
  _mult     constant numeric := 1.8;        -- 平衡档倍数（后续可绑用户灵敏度）
  _floor_s  constant numeric := 10800;      -- 下限 3h（避免白天毛刺）
  _cap_s    constant numeric := 72000;      -- 上限 20h
  _cold     constant interval := interval ''18 hours'';
  _total    int;
  _last_hour int;
  _global   numeric;
  _hourly   numeric;
  _hourly_n int;
  _expected numeric;
begin
  select count(*) into _total
  from public.behavior_pings
  where user_id = _user and at > now() - interval ''30 days'';

  if _total < 30 then
    return _cold;  -- 数据不足/学习期：维持冷启动阈值
  end if;

  select extract(hour from max(at))::int into _last_hour
  from public.behavior_pings
  where user_id = _user and at > now() - interval ''30 days'';

  with ev as (
    select at, lag(at) over (order by at) as prev
    from public.behavior_pings
    where user_id = _user and at > now() - interval ''30 days''
  ),
  gaps as (
    select extract(hour from prev)::int as start_hour,
           extract(epoch from (at - prev)) as gap_sec
    from ev where prev is not null and at > prev
  )
  select
    percentile_cont(0.9) within group (order by gap_sec),
    count(*) filter (where start_hour = _last_hour),
    percentile_cont(0.9) within group (order by gap_sec) filter (where start_hour = _last_hour)
  into _global, _hourly_n, _hourly
  from gaps;

  _expected := case when coalesce(_hourly_n, 0) >= 3 then _hourly else _global end;
  if _expected is null then return _cold; end if;
  _expected := greatest(_floor_s, least(_cap_s, _expected * _mult));
  return make_interval(secs => _expected::int);
end;
$$;

revoke execute on all functions in schema private from public;
grant execute on all functions in schema private to authenticated;

-- process_escalations：创建条件从\"一刀切 18h\"改为\"超过该用户此时段的常态阈值\"
create or replace function public.process_escalations()
returns void language plpgsql security definer set search_path = '''' as $$
declare
  _self_grace constant interval := interval ''30 minutes'';
  _group_dur  constant interval := interval ''1 hour'';
  _comm_dur   constant interval := interval ''2 hours'';
  r record;
  _aid uuid;
  _new text;
begin
  for r in
    select ds.user_id,
           (now() - ds.last_heartbeat_at) > interval ''18 hours'' as is_dark
    from public.device_state ds
    where (ds.status = ''alert''
           or (now() - ds.last_heartbeat_at) > private.silence_threshold(ds.user_id))
      and exists (select 1 from public.group_members gm
                  where gm.user_id = ds.user_id and gm.monitored and gm.status = ''active'')
      and not exists (select 1 from public.alerts a where a.user_id = ds.user_id and a.status = ''open'')
  loop
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    values (r.user_id, case when r.is_dark then ''dark_device'' else ''silence'' end,
            ''self'', now(), now() + _self_grace)
    returning id into _aid;
    insert into public.alert_events (alert_id, kind) values (_aid, ''raised'');
    perform private.notify_stage(_aid, r.user_id, ''self'');
  end loop;

  for r in
    select * from public.alerts
    where status = ''open''
      and next_deadline is not null and next_deadline <= now()
      and coalesce(paused_until, to_timestamp(0)) <= now()
  loop
    _new := case r.stage
              when ''self'' then ''group''
              when ''group'' then ''community''
              when ''community'' then ''terminal''
              else ''terminal'' end;
    update public.alerts
      set stage = _new, stage_entered_at = now(), paused_until = null, updated_at = now(),
          next_deadline = case _new when ''group'' then now() + _group_dur
                                    when ''community'' then now() + _comm_dur
                                    else null end
      where id = r.id;
    insert into public.alert_events (alert_id, kind, note) values (r.id, ''escalated'', _new);
    perform private.notify_stage(r.id, r.user_id, _new);
  end loop;
end;
$$;"}', 'server_silence_baseline', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260614081840', '{"-- 用户设置（灵敏度）同步到服务器，让 silence_threshold 用用户自选档而非固定 1.8 倍。
create table public.user_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  sensitivity text not null default ''balanced'' check (sensitivity in (''high'', ''balanced'', ''low'')),
  updated_at timestamptz not null default now()
);
alter table public.user_settings enable row level security;
create policy user_settings_select on public.user_settings
  for select to authenticated using ((select auth.uid()) = user_id);

create or replace function public.set_sensitivity(_s text)
returns void language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  if _s not in (''high'', ''balanced'', ''low'') then raise exception ''bad sensitivity''; end if;
  insert into public.user_settings (user_id, sensitivity, updated_at)
  values (_uid, _s, now())
  on conflict (user_id) do update set sensitivity = excluded.sensitivity, updated_at = now();
end;
$$;
revoke execute on function public.set_sensitivity(text) from public, anon;
grant execute on function public.set_sensitivity(text) to authenticated;

-- silence_threshold 改为读用户灵敏度档（倍数 + 下限 + 冷启动阈值都随档变）
create or replace function private.silence_threshold(_user uuid)
returns interval language plpgsql security definer set search_path = '''' stable as $$
declare
  _cap_s    constant numeric := 86400;     -- 上限 24h
  _sens     text;
  _mult     numeric;
  _floor_s  numeric;
  _cold     interval;
  _total    int;
  _last_hour int;
  _global   numeric;
  _hourly   numeric;
  _hourly_n int;
  _expected numeric;
begin
  select coalesce(sensitivity, ''balanced'') into _sens
  from public.user_settings where user_id = _user;
  _sens := coalesce(_sens, ''balanced'');

  if _sens = ''high'' then
    _mult := 1.3; _floor_s := 5400;  _cold := interval ''14 hours'';   -- 1.5h floor
  elsif _sens = ''low'' then
    _mult := 2.6; _floor_s := 21600; _cold := interval ''24 hours'';   -- 6h floor
  else
    _mult := 1.8; _floor_s := 10800; _cold := interval ''18 hours'';   -- 3h floor
  end if;

  select count(*) into _total
  from public.behavior_pings
  where user_id = _user and at > now() - interval ''30 days'';

  if _total < 30 then
    return _cold;
  end if;

  select extract(hour from max(at))::int into _last_hour
  from public.behavior_pings
  where user_id = _user and at > now() - interval ''30 days'';

  with ev as (
    select at, lag(at) over (order by at) as prev
    from public.behavior_pings
    where user_id = _user and at > now() - interval ''30 days''
  ),
  gaps as (
    select extract(hour from prev)::int as start_hour,
           extract(epoch from (at - prev)) as gap_sec
    from ev where prev is not null and at > prev
  )
  select
    percentile_cont(0.9) within group (order by gap_sec),
    count(*) filter (where start_hour = _last_hour),
    percentile_cont(0.9) within group (order by gap_sec) filter (where start_hour = _last_hour)
  into _global, _hourly_n, _hourly
  from gaps;

  _expected := case when coalesce(_hourly_n, 0) >= 3 then _hourly else _global end;
  if _expected is null then return _cold; end if;
  _expected := greatest(_floor_s, least(_cap_s, _expected * _mult));
  return make_interval(secs => _expected::int);
end;
$$;"}', 'sensitivity_sync', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260614142145', '{"create or replace function public.update_checkin_task(
  _task uuid,
  _kind text,
  _due_time_utc time default null,
  _interval_hours int default null,
  _first_due timestamptz default null,
  _grace int default null,
  _label text default null
) returns void language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid(); _t public.checkin_tasks;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  select * into _t from public.checkin_tasks
    where id = _task and created_by = _uid and status in (''pending'', ''active'');
  if not found then raise exception ''task not found or not editable''; end if;

  update public.checkin_tasks set
    kind = _kind,
    due_time_utc = _due_time_utc,
    interval_hours = _interval_hours,
    grace_minutes = coalesce(_grace, grace_minutes),
    label = coalesce(_label, label),
    cycle_state = ''idle'',
    next_due_at = case when status = ''active''
      then coalesce(_first_due,
        case when _kind = ''interval'' then now() + make_interval(hours => _interval_hours) end)
      else next_due_at end,
    updated_at = now()
  where id = _task;

  if _t.ward_id <> _uid and _t.status = ''active'' then
    insert into public.notifications (recipient_id, kind, body, params)
    values (_t.ward_id, ''task_updated'', ''你的报平安任务已被修改，请留意新的时间安排。'', ''{}''::jsonb);
  end if;
end;
$$;

revoke execute on function public.update_checkin_task(uuid, text, time, int, timestamptz, int, text) from public, anon;
grant execute on function public.update_checkin_task(uuid, text, time, int, timestamptz, int, text) to authenticated;"}', 'update_checkin_task', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260614163050', '{"-- 每位成员是否公开自己的活跃状态（opt-in，默认关，符合隐私优先）
alter table public.user_settings
  add column if not exists share_activity boolean not null default false;

-- 每个 Group 的活跃可见范围：watchers_only（仅守望者可看）| group_wide（全组互看）
alter table public.groups
  add column if not exists activity_visibility text not null default ''watchers_only'';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = ''groups_activity_visibility_chk'') then
    alter table public.groups add constraint groups_activity_visibility_chk
      check (activity_visibility in (''watchers_only'',''group_wide''));
  end if;
end $$;

-- 本人开关\"公开我的活跃状态\"
create or replace function public.set_share_activity(_share boolean)
returns void language plpgsql security definer set search_path = '''' as $$
begin
  if auth.uid() is null then raise exception ''not authenticated''; end if;
  insert into public.user_settings (user_id, share_activity)
  values (auth.uid(), _share)
  on conflict (user_id) do update
    set share_activity = excluded.share_activity, updated_at = now();
end; $$;
revoke execute on function public.set_share_activity(boolean) from public, anon;
grant execute on function public.set_share_activity(boolean) to authenticated;

-- 组主设置本组活跃可见范围
create or replace function public.set_group_visibility(_group uuid, _visibility text)
returns void language plpgsql security definer set search_path = '''' as $$
begin
  if auth.uid() is null then raise exception ''not authenticated''; end if;
  if _visibility not in (''watchers_only'',''group_wide'') then
    raise exception ''bad visibility'';
  end if;
  update public.groups set activity_visibility = _visibility
    where id = _group and created_by = auth.uid();
  if not found then raise exception ''not group owner''; end if;
end; $$;
revoke execute on function public.set_group_visibility(uuid, text) from public, anon;
grant execute on function public.set_group_visibility(uuid, text) to authenticated;

-- 读取本组\"平安看板\"：仅返回粗略状态桶，绝不返回精确时间
create or replace function public.get_group_activity(_group uuid)
returns jsonb language plpgsql security definer set search_path = '''' as $$
declare
  _uid uuid := auth.uid();
  _vis text;
  _owner uuid;
  _i_watch boolean;
  _i_share boolean;
  _members jsonb;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  select g.activity_visibility, g.created_by into _vis, _owner
    from public.groups g where g.id = _group;
  if _vis is null then raise exception ''group not found''; end if;
  perform 1 from public.group_members
    where group_id = _group and user_id = _uid and status = ''active'';
  if not found then raise exception ''not a member''; end if;

  select coalesce(gm.watching, false) into _i_watch
    from public.group_members gm where gm.group_id = _group and gm.user_id = _uid;
  select coalesce(us.share_activity, false) into _i_share
    from public.user_settings us where us.user_id = _uid;

  select jsonb_agg(
    jsonb_build_object(
      ''user_id'', m.user_id,
      ''name'', coalesce(p.display_name, left(m.user_id::text, 8)),
      ''is_me'', (m.user_id = _uid),
      ''status'', case
        when m.user_id = _uid then ''self''
        when not coalesce(us.share_activity, false) then ''hidden''
        when _vis = ''group_wide'' then coalesce(b.bucket, ''unknown'')
        when _vis = ''watchers_only'' and _i_watch then coalesce(b.bucket, ''unknown'')
        else ''hidden''
      end,
      ''hours'', case
        when m.user_id = _uid then null
        when not coalesce(us.share_activity, false) then null
        when _vis = ''group_wide'' or (_vis = ''watchers_only'' and _i_watch) then b.hours
        else null
      end
    )
    order by (m.user_id = _uid) desc, p.display_name
  ) into _members
  from public.group_members m
  left join public.profiles p on p.id = m.user_id
  left join public.user_settings us on us.user_id = m.user_id
  left join lateral (
    select
      case
        when extract(epoch from (now() - ds.last_heartbeat_at)) / 3600 < 6 then ''active''
        when extract(epoch from (now() - ds.last_heartbeat_at)) / 3600 < 24 then ''quiet''
        else ''silent''
      end as bucket,
      round(extract(epoch from (now() - ds.last_heartbeat_at)) / 3600)::int as hours
    from public.device_state ds where ds.user_id = m.user_id
  ) b on true
  where m.group_id = _group and m.status = ''active'';

  return jsonb_build_object(
    ''visibility'', _vis,
    ''is_owner'', (_owner = _uid),
    ''i_share'', _i_share,
    ''members'', coalesce(_members, ''[]''::jsonb)
  );
end; $$;
revoke execute on function public.get_group_activity(uuid) from public, anon;
grant execute on function public.get_group_activity(uuid) to authenticated;"}', 'group_activity_board', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260615030056', '{"-- 给自己发一条测试通知（用于在真机上验证推送是否出声/醒目）
create or replace function public.send_test_notification()
returns void language plpgsql security definer set search_path = '''' as $$
begin
  if auth.uid() is null then raise exception ''not authenticated''; end if;
  insert into public.notifications (recipient_id, kind, body, params)
  values (auth.uid(), ''test'', ''这是一条测试通知，用来确认推送是否出声、醒目。'', ''{}''::jsonb);
end; $$;
revoke execute on function public.send_test_notification() from public, anon;
grant execute on function public.send_test_notification() to authenticated;"}', 'send_test_notification', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260615033243', '{"-- 造一个\"测试用\"的本人 open 告警 + 发本人推送，用来验证\"点通知→解锁界面\"。
-- next_deadline=null ⇒ process_escalations 永不升级它 ⇒ 绝不打扰 group/community。
create or replace function public.raise_test_alert()
returns void language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid(); _aid uuid;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  -- 已有 open 告警就复用（避免重复造），否则建一个不升级的测试告警
  select id into _aid from public.alerts where user_id = _uid and status = ''open'' limit 1;
  if _aid is null then
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    values (_uid, ''silence'', ''self'', now(), null)
    returning id into _aid;
    insert into public.alert_events (alert_id, kind) values (_aid, ''raised'');
  end if;
  insert into public.notifications (recipient_id, kind, body, params, alert_id)
  values (_uid, ''self'', ''（测试）检测到异常沉默，点开 App 完成解锁报平安。'', ''{}''::jsonb, _aid);
end; $$;
revoke execute on function public.raise_test_alert() from public, anon;
grant execute on function public.raise_test_alert() to authenticated;"}', 'raise_test_alert', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260615064834', '{"-- 用户自设显示名（用于 app 内与其他用户沟通、确认身份）。
-- 同步更新 profiles.display_name（别人看到的名字）；客户端另调 auth.updateUser 更新 metadata。
create or replace function public.set_display_name(_name text)
returns void language plpgsql security definer set search_path = '''' as $$
declare _clean text := nullif(btrim(_name), '''');
begin
  if auth.uid() is null then raise exception ''not authenticated''; end if;
  if _clean is null then raise exception ''name required''; end if;
  if length(_clean) > 40 then _clean := left(_clean, 40); end if;
  update public.profiles set display_name = _clean where id = auth.uid();
end; $$;
revoke execute on function public.set_display_name(text) from public, anon;
grant execute on function public.set_display_name(text) to authenticated;"}', 'set_display_name', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260615071244', '{"-- 扩展 get_group_activity：每位成员加 alerted（是否处于\"已升级到 group+ 的开放告警\"）。
-- alerted 用于状态看板把\"异常沉默\"的成员置顶；不受 share_activity 限制（安全优先，
-- 与现有 group 阶段会通知全组的设计一致）。
create or replace function public.get_group_activity(_group uuid)
returns jsonb language plpgsql security definer set search_path = '''' as $$
declare
  _uid uuid := auth.uid();
  _vis text;
  _owner uuid;
  _i_watch boolean;
  _i_share boolean;
  _members jsonb;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  select g.activity_visibility, g.created_by into _vis, _owner
    from public.groups g where g.id = _group;
  if _vis is null then raise exception ''group not found''; end if;
  perform 1 from public.group_members
    where group_id = _group and user_id = _uid and status = ''active'';
  if not found then raise exception ''not a member''; end if;

  select coalesce(gm.watching, false) into _i_watch
    from public.group_members gm where gm.group_id = _group and gm.user_id = _uid;
  select coalesce(us.share_activity, false) into _i_share
    from public.user_settings us where us.user_id = _uid;

  select jsonb_agg(
    jsonb_build_object(
      ''user_id'', m.user_id,
      ''name'', coalesce(p.display_name, left(m.user_id::text, 8)),
      ''is_me'', (m.user_id = _uid),
      ''alerted'', exists(
        select 1 from public.alerts a
        where a.user_id = m.user_id and a.status = ''open''
          and a.stage in (''group'', ''community'', ''terminal'')
      ),
      ''status'', case
        when m.user_id = _uid then ''self''
        when not coalesce(us.share_activity, false) then ''hidden''
        when _vis = ''group_wide'' then coalesce(b.bucket, ''unknown'')
        when _vis = ''watchers_only'' and _i_watch then coalesce(b.bucket, ''unknown'')
        else ''hidden''
      end,
      ''hours'', case
        when m.user_id = _uid then null
        when not coalesce(us.share_activity, false) then null
        when _vis = ''group_wide'' or (_vis = ''watchers_only'' and _i_watch) then b.hours
        else null
      end
    )
    order by (m.user_id = _uid) desc, p.display_name
  ) into _members
  from public.group_members m
  left join public.profiles p on p.id = m.user_id
  left join public.user_settings us on us.user_id = m.user_id
  left join lateral (
    select
      case
        when extract(epoch from (now() - ds.last_heartbeat_at)) / 3600 < 6 then ''active''
        when extract(epoch from (now() - ds.last_heartbeat_at)) / 3600 < 24 then ''quiet''
        else ''silent''
      end as bucket,
      round(extract(epoch from (now() - ds.last_heartbeat_at)) / 3600)::int as hours
    from public.device_state ds where ds.user_id = m.user_id
  ) b on true
  where m.group_id = _group and m.status = ''active'';

  return jsonb_build_object(
    ''visibility'', _vis,
    ''is_owner'', (_owner = _uid),
    ''i_share'', _i_share,
    ''members'', coalesce(_members, ''[]''::jsonb)
  );
end; $$;

-- \"Send concern\"：向同组成员发一条即时关怀通知（催对方打开 App 解锁报平安，确认非误报）。
create or replace function public.send_concern(_target uuid)
returns void language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid(); _name text;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  if _target = _uid then raise exception ''cannot concern self''; end if;
  if not exists (
    select 1 from public.group_members a
    join public.group_members b on a.group_id = b.group_id
    where a.user_id = _uid and b.user_id = _target
      and a.status = ''active'' and b.status = ''active''
  ) then raise exception ''not in same group''; end if;
  select display_name into _name from public.profiles where id = _uid;
  insert into public.notifications (recipient_id, kind, body, params)
  values (_target, ''concern'',
          ''有成员在关心你，请打开 App 完成解锁报平安。'',
          jsonb_build_object(''name'', coalesce(_name, '''')));
end; $$;
revoke execute on function public.send_concern(uuid) from public, anon;
grant execute on function public.send_concern(uuid) to authenticated;"}', 'group_activity_alerted_and_concern', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260615092834', '{"-- 通知：允许本人删除自己的通知（清除单个/全部）
do $$ begin
  if not exists (
    select 1 from pg_policies
    where tablename = ''notifications'' and policyname = ''notifications_delete''
  ) then
    create policy notifications_delete on public.notifications
      for delete using ((select auth.uid()) = recipient_id);
  end if;
end $$;

-- Group / Community 重命名（仅创建者）
create or replace function public.rename_group(_group uuid, _name text)
returns void language plpgsql security definer set search_path = '''' as $$
declare _clean text := nullif(btrim(_name), '''');
begin
  if auth.uid() is null then raise exception ''not authenticated''; end if;
  if _clean is null then raise exception ''name required''; end if;
  update public.groups set name = left(_clean, 40)
    where id = _group and created_by = auth.uid();
  if not found then raise exception ''not group owner''; end if;
end; $$;
revoke execute on function public.rename_group(uuid, text) from public, anon;
grant execute on function public.rename_group(uuid, text) to authenticated;

create or replace function public.rename_community(_community uuid, _name text)
returns void language plpgsql security definer set search_path = '''' as $$
declare _clean text := nullif(btrim(_name), '''');
begin
  if auth.uid() is null then raise exception ''not authenticated''; end if;
  if _clean is null then raise exception ''name required''; end if;
  update public.communities set name = left(_clean, 40)
    where id = _community and created_by = auth.uid();
  if not found then raise exception ''not community owner''; end if;
end; $$;
revoke execute on function public.rename_community(uuid, text) from public, anon;
grant execute on function public.rename_community(uuid, text) to authenticated;

-- SOS 带实时 GPS：alerts 加坐标列，raise_sos 接收并写入
alter table public.alerts add column if not exists sos_lat double precision;
alter table public.alerts add column if not exists sos_lng double precision;

drop function if exists public.raise_sos();
create or replace function public.raise_sos(
  _lat double precision default null,
  _lng double precision default null
) returns uuid language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid(); _aid uuid;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  select id into _aid from public.alerts where user_id = _uid and status = ''open'';
  if _aid is null then
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline, sos_lat, sos_lng)
    values (_uid, ''sos'', ''group'', now(), now() + interval ''1 hour'', _lat, _lng)
    returning id into _aid;
    insert into public.alert_events (alert_id, actor_id, kind) values (_aid, _uid, ''raised'');
  else
    update public.alerts set cause = ''sos'', stage = ''group'', stage_entered_at = now(),
      next_deadline = now() + interval ''1 hour'', paused_until = null,
      sos_lat = coalesce(_lat, sos_lat), sos_lng = coalesce(_lng, sos_lng),
      updated_at = now()
      where id = _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note) values (_aid, _uid, ''escalated'', ''sos'');
  end if;
  perform private.notify_stage(_aid, _uid, ''group'');
  return _aid;
end; $$;
revoke execute on function public.raise_sos(double precision, double precision) from public, anon;
grant execute on function public.raise_sos(double precision, double precision) to authenticated;"}', 'sos_gps_rename_and_notif_delete', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260615134209', '{"-- 显式睡眠窗（UTC 存储；客户端按设备本地时间换算）。null = 未设。
alter table public.user_settings
  add column if not exists sleep_start_utc time,
  add column if not exists sleep_end_utc time;

-- 是否应\"放宽\"：在睡眠窗内，或睡眠窗结束后 2 小时醒后宽限内。
create or replace function private.sleep_relaxed(_user uuid, _at timestamptz)
returns boolean language plpgsql stable security definer set search_path = '''' as $$
declare _s time; _e time; _utc timestamp; _tod time; _end timestamp;
begin
  select sleep_start_utc, sleep_end_utc into _s, _e
  from public.user_settings where user_id = _user;
  if _s is null or _e is null or _s = _e then return false; end if;
  _utc := (_at at time zone ''UTC'');  -- UTC 墙钟
  _tod := _utc::time;
  -- 睡眠窗内（处理跨午夜）
  if _s < _e then
    if _tod >= _s and _tod < _e then return true; end if;
  else
    if _tod >= _s or _tod < _e then return true; end if;
  end if;
  -- 醒后宽限 2h：最近一次睡眠结束时刻
  _end := date_trunc(''day'', _utc) + _e;
  if _end > _utc then _end := _end - interval ''1 day''; end if;
  if _utc - _end < interval ''2 hours'' then return true; end if;
  return false;
end; $$;

-- 时段感知阈值：睡眠/醒后宽限期放宽到上限；清醒期沿用学习/冷启动。
create or replace function private.silence_threshold(_user uuid)
returns interval language plpgsql stable security definer set search_path = '''' as $function$
declare
  _cap_s    constant numeric := 86400;     -- 上限 24h
  _sens     text;
  _mult     numeric;
  _floor_s  numeric;
  _cold     interval;
  _total    int;
  _last_hour int;
  _global   numeric;
  _hourly   numeric;
  _hourly_n int;
  _expected numeric;
begin
  select coalesce(sensitivity, ''balanced'') into _sens
  from public.user_settings where user_id = _user;
  _sens := coalesce(_sens, ''balanced'');

  if _sens = ''high'' then
    _mult := 1.3; _floor_s := 5400;  _cold := interval ''14 hours'';
  elsif _sens = ''low'' then
    _mult := 2.6; _floor_s := 21600; _cold := interval ''24 hours'';
  else
    _mult := 1.8; _floor_s := 10800; _cold := interval ''18 hours'';
  end if;

  -- 睡眠窗 / 醒后宽限：放宽到上限，夜里不误报（任何数据量下都生效）
  if private.sleep_relaxed(_user, now()) then
    return make_interval(secs => _cap_s::int);
  end if;

  select count(*) into _total
  from public.behavior_pings
  where user_id = _user and at > now() - interval ''30 days'';

  if _total < 30 then
    return _cold;
  end if;

  select extract(hour from max(at))::int into _last_hour
  from public.behavior_pings
  where user_id = _user and at > now() - interval ''30 days'';

  with ev as (
    select at, lag(at) over (order by at) as prev
    from public.behavior_pings
    where user_id = _user and at > now() - interval ''30 days''
  ),
  gaps as (
    select extract(hour from prev)::int as start_hour,
           extract(epoch from (at - prev)) as gap_sec
    from ev where prev is not null and at > prev
  )
  select
    percentile_cont(0.9) within group (order by gap_sec),
    count(*) filter (where start_hour = _last_hour),
    percentile_cont(0.9) within group (order by gap_sec) filter (where start_hour = _last_hour)
  into _global, _hourly_n, _hourly
  from gaps;

  _expected := case when coalesce(_hourly_n, 0) >= 3 then _hourly else _global end;
  if _expected is null then return _cold; end if;
  _expected := greatest(_floor_s, least(_cap_s, _expected * _mult));
  return make_interval(secs => _expected::int);
end;
$function$;

-- 本人设置睡眠窗（传 null 即关闭）
create or replace function public.set_sleep_window(_start time, _end time)
returns void language plpgsql security definer set search_path = '''' as $$
begin
  if auth.uid() is null then raise exception ''not authenticated''; end if;
  insert into public.user_settings (user_id, sleep_start_utc, sleep_end_utc)
  values (auth.uid(), _start, _end)
  on conflict (user_id) do update
    set sleep_start_utc = excluded.sleep_start_utc,
        sleep_end_utc = excluded.sleep_end_utc,
        updated_at = now();
end; $$;
revoke execute on function public.set_sleep_window(time, time) from public, anon;
grant execute on function public.set_sleep_window(time, time) to authenticated;"}', 'sleep_window_baseline', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260616082859', '{"-- 改 Group 所属 Community（仅创建者；移入的 Community 须本人也是其成员；null=独立）
create or replace function public.set_group_community(_group uuid, _community uuid)
returns void language plpgsql security definer set search_path = '''' as $$
begin
  if auth.uid() is null then raise exception ''not authenticated''; end if;
  if _community is not null and not exists (
    select 1 from public.community_members
    where community_id = _community and user_id = auth.uid() and status = ''active''
  ) then
    raise exception ''not a member of target community'';
  end if;
  update public.groups set community_id = _community
    where id = _group and created_by = auth.uid();
  if not found then raise exception ''not group owner''; end if;
end; $$;
revoke execute on function public.set_group_community(uuid, uuid) from public, anon;
grant execute on function public.set_group_community(uuid, uuid) to authenticated;"}', 'set_group_community', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260619042826', '{"-- Parity migration for passive sensing, SOS coordinates, group activity,
-- user settings, and task editing. These objects are already reflected in
-- generated client types; this file makes local migrations reproducible.

alter table public.alerts
  add column if not exists sos_lat double precision,
  add column if not exists sos_lng double precision;

alter table public.groups
  add column if not exists activity_visibility text not null default ''watchers_only'';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = ''groups_activity_visibility_check''
  ) then
    alter table public.groups
      add constraint groups_activity_visibility_check
      check (activity_visibility in (''watchers_only'', ''group_wide''));
  end if;
end $$;

create table if not exists public.user_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  sensitivity text not null default ''balanced''
    check (sensitivity in (''high'', ''balanced'', ''low'')),
  share_activity boolean not null default true,
  sleep_start_utc time,
  sleep_end_utc time,
  updated_at timestamptz not null default now()
);

alter table public.user_settings enable row level security;
drop policy if exists user_settings_select on public.user_settings;
drop policy if exists user_settings_insert on public.user_settings;
drop policy if exists user_settings_update on public.user_settings;
create policy user_settings_select on public.user_settings
  for select to authenticated using ((select auth.uid()) = user_id);
create policy user_settings_insert on public.user_settings
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy user_settings_update on public.user_settings
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

insert into public.user_settings (user_id)
select id from auth.users
on conflict (user_id) do nothing;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '''' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> ''display_name'', null))
  on conflict (id) do nothing;
  insert into public.heartbeat_tokens (user_id) values (new.id)
  on conflict (user_id) do nothing;
  insert into public.user_settings (user_id) values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create or replace function public.set_display_name(_name text)
returns void language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  update public.profiles
    set display_name = nullif(btrim(_name), '''')
    where id = _uid;
end;
$$;

create or replace function public.set_sensitivity(_s text)
returns void language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  if _s not in (''high'', ''balanced'', ''low'') then raise exception ''bad sensitivity''; end if;
  insert into public.user_settings (user_id, sensitivity, updated_at)
  values (_uid, _s, now())
  on conflict (user_id) do update
    set sensitivity = excluded.sensitivity, updated_at = now();
end;
$$;

create or replace function public.set_sleep_window(_start time default null, _end time default null)
returns void language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  insert into public.user_settings (user_id, sleep_start_utc, sleep_end_utc, updated_at)
  values (_uid, _start, _end, now())
  on conflict (user_id) do update
    set sleep_start_utc = excluded.sleep_start_utc,
        sleep_end_utc = excluded.sleep_end_utc,
        updated_at = now();
end;
$$;

create or replace function public.set_share_activity(_share boolean)
returns void language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  insert into public.user_settings (user_id, share_activity, updated_at)
  values (_uid, coalesce(_share, false), now())
  on conflict (user_id) do update
    set share_activity = excluded.share_activity, updated_at = now();
end;
$$;

create or replace function public.set_group_visibility(_group uuid, _visibility text)
returns void language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  if _visibility not in (''watchers_only'', ''group_wide'') then
    raise exception ''bad visibility'';
  end if;
  update public.groups g
    set activity_visibility = _visibility
    where g.id = _group
      and exists (
        select 1 from public.group_members gm
        where gm.group_id = g.id
          and gm.user_id = _uid
          and gm.role = ''admin''
          and gm.status = ''active''
      );
  if not found then raise exception ''forbidden''; end if;
end;
$$;

create or replace function public.set_group_community(_group uuid, _community uuid default null)
returns void language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  if _community is not null and not private.is_community_member(_community, _uid) then
    raise exception ''community not visible'';
  end if;
  update public.groups g
    set community_id = _community
    where g.id = _group
      and exists (
        select 1 from public.group_members gm
        where gm.group_id = g.id and gm.user_id = _uid
          and gm.role = ''admin'' and gm.status = ''active''
      );
  if not found then raise exception ''forbidden''; end if;
end;
$$;

create or replace function public.rename_group(_group uuid, _name text)
returns void language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  update public.groups g
    set name = nullif(btrim(_name), '''')
    where g.id = _group
      and exists (
        select 1 from public.group_members gm
        where gm.group_id = g.id and gm.user_id = _uid
          and gm.role = ''admin'' and gm.status = ''active''
      )
      and nullif(btrim(_name), '''') is not null;
  if not found then raise exception ''forbidden''; end if;
end;
$$;

create or replace function public.rename_community(_community uuid, _name text)
returns void language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  update public.communities c
    set name = nullif(btrim(_name), '''')
    where c.id = _community and c.created_by = _uid
      and nullif(btrim(_name), '''') is not null;
  if not found then raise exception ''forbidden''; end if;
end;
$$;

create or replace function public.get_group_activity(_group uuid)
returns jsonb language plpgsql security definer set search_path = '''' as $$
declare
  _uid uuid := auth.uid();
  _visibility text;
  _is_owner boolean;
  _i_watching boolean;
  _i_share boolean;
  _members jsonb;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  select g.activity_visibility,
         exists (
           select 1 from public.group_members gm
           where gm.group_id = g.id and gm.user_id = _uid
             and gm.role = ''admin'' and gm.status = ''active''
         ),
         coalesce(me.watching, false)
    into _visibility, _is_owner, _i_watching
  from public.groups g
  join public.group_members me
    on me.group_id = g.id and me.user_id = _uid and me.status = ''active''
  where g.id = _group;
  if not found then raise exception ''forbidden''; end if;

  select coalesce(us.share_activity, true) into _i_share
  from public.user_settings us where us.user_id = _uid;
  _i_share := coalesce(_i_share, true);

  select jsonb_agg(
    jsonb_build_object(
      ''user_id'', m.user_id,
      ''name'', coalesce(nullif(p.display_name, ''''), left(m.user_id::text, 8)),
      ''is_me'', m.user_id = _uid,
      ''status'',
        case
          when m.user_id = _uid then ''self''
          when not coalesce(us.share_activity, true) then ''hidden''
          when _visibility = ''watchers_only'' and not _i_watching then ''hidden''
          when ds.last_heartbeat_at is null then ''unknown''
          when ds.last_heartbeat_at > now() - interval ''6 hours'' then ''active''
          when ds.last_heartbeat_at > now() - interval ''24 hours'' then ''quiet''
          else ''silent''
        end,
      ''hours'',
        case
          when ds.last_heartbeat_at is null then null
          else floor(extract(epoch from (now() - ds.last_heartbeat_at)) / 3600)::int
        end,
      ''alerted'',
        exists (
          select 1 from public.alerts a
          where a.user_id = m.user_id and a.status = ''open''
            and a.stage in (''group'', ''community'', ''terminal'')
        )
    )
    order by (m.user_id = _uid) desc, p.display_name nulls last, m.user_id
  ) into _members
  from public.group_members m
  left join public.profiles p on p.id = m.user_id
  left join public.user_settings us on us.user_id = m.user_id
  left join public.device_state ds on ds.user_id = m.user_id
  where m.group_id = _group and m.status = ''active'';

  return jsonb_build_object(
    ''visibility'', _visibility,
    ''is_owner'', _is_owner,
    ''i_share'', _i_share,
    ''members'', coalesce(_members, ''[]''::jsonb)
  );
end;
$$;

create or replace function public.send_concern(_target uuid)
returns void language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid(); _name text;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  if _uid = _target then raise exception ''bad target''; end if;
  if not private.shares_group_with(_target, _uid) and not private.is_guardian_of(_target, _uid) then
    raise exception ''forbidden'';
  end if;
  select coalesce(display_name, '''') into _name from public.profiles where id = _uid;
  insert into public.notifications (recipient_id, kind, body, params)
  values (
    _target,
    ''concern'',
    coalesce(nullif(_name, ''''), ''有人'') || '' 在关心你，请打开 App 完成解锁报平安。'',
    jsonb_build_object(''name'', _name)
  );
end;
$$;

create or replace function public.raise_sos(_lat double precision default null, _lng double precision default null)
returns uuid language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid(); _aid uuid;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  select id into _aid from public.alerts where user_id = _uid and status = ''open'';
  if _aid is null then
    insert into public.alerts
      (user_id, cause, stage, stage_entered_at, next_deadline, sos_lat, sos_lng)
    values
      (_uid, ''sos'', ''group'', now(), now() + interval ''1 hour'', _lat, _lng)
    returning id into _aid;
    insert into public.alert_events (alert_id, actor_id, kind) values (_aid, _uid, ''raised'');
  else
    update public.alerts
      set cause = ''sos'',
          stage = ''group'',
          stage_entered_at = now(),
          next_deadline = now() + interval ''1 hour'',
          paused_until = null,
          sos_lat = coalesce(_lat, sos_lat),
          sos_lng = coalesce(_lng, sos_lng),
          updated_at = now()
      where id = _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note)
    values (_aid, _uid, ''escalated'', ''sos'');
  end if;
  perform private.notify_stage(_aid, _uid, ''group'');
  return _aid;
end;
$$;

create or replace function public.update_checkin_task(
  _task uuid,
  _kind text,
  _due_time_utc time default null,
  _interval_hours int default null,
  _first_due timestamptz default null,
  _grace int default 30,
  _label text default ''''
) returns void language plpgsql security definer set search_path = '''' as $$
declare _uid uuid := auth.uid(); _ward uuid;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  if _kind not in (''daily'', ''interval'') then raise exception ''bad kind''; end if;
  update public.checkin_tasks t
    set kind = _kind,
        due_time_utc = case when _kind = ''daily'' then _due_time_utc else null end,
        interval_hours = case when _kind = ''interval'' then _interval_hours else null end,
        grace_minutes = coalesce(_grace, 30),
        label = coalesce(_label, ''''),
        cycle_state = ''idle'',
        next_due_at = coalesce(
          _first_due,
          case when _kind = ''interval'' then now() + make_interval(hours => _interval_hours) end
        ),
        status = case when status = ''declined'' then ''pending'' else status end,
        updated_at = now()
    where t.id = _task
      and t.created_by = _uid
      and t.status in (''pending'', ''active'', ''declined'')
    returning t.ward_id into _ward;
  if _ward is null then raise exception ''task not found''; end if;

  insert into public.notifications (recipient_id, kind, body, params)
  values (_ward, ''task_updated'', ''你的报平安任务已被修改，请留意新的时间安排。'',
          jsonb_build_object(''label'', coalesce(_label, '''')));
end;
$$;

revoke execute on function public.set_display_name(text) from public, anon;
revoke execute on function public.set_sensitivity(text) from public, anon;
revoke execute on function public.set_sleep_window(time, time) from public, anon;
revoke execute on function public.set_share_activity(boolean) from public, anon;
revoke execute on function public.set_group_visibility(uuid, text) from public, anon;
revoke execute on function public.set_group_community(uuid, uuid) from public, anon;
revoke execute on function public.rename_group(uuid, text) from public, anon;
revoke execute on function public.rename_community(uuid, text) from public, anon;
revoke execute on function public.get_group_activity(uuid) from public, anon;
revoke execute on function public.send_concern(uuid) from public, anon;
revoke execute on function public.raise_sos(double precision, double precision) from public, anon;
revoke execute on function public.update_checkin_task(uuid, text, time, int, timestamptz, int, text) from public, anon;

grant execute on function public.set_display_name(text) to authenticated;
grant execute on function public.set_sensitivity(text) to authenticated;
grant execute on function public.set_sleep_window(time, time) to authenticated;
grant execute on function public.set_share_activity(boolean) to authenticated;
grant execute on function public.set_group_visibility(uuid, text) to authenticated;
grant execute on function public.set_group_community(uuid, uuid) to authenticated;
grant execute on function public.rename_group(uuid, text) to authenticated;
grant execute on function public.rename_community(uuid, text) to authenticated;
grant execute on function public.get_group_activity(uuid) to authenticated;
grant execute on function public.send_concern(uuid) to authenticated;
grant execute on function public.raise_sos(double precision, double precision) to authenticated;
grant execute on function public.update_checkin_task(uuid, text, time, int, timestamptz, int, text) to authenticated;

create extension if not exists pg_cron;
do $do$
declare _jobid bigint;
begin
  select jobid into _jobid from cron.job where jobname = ''process-checkin-tasks'';
  if _jobid is not null then perform cron.unschedule(_jobid); end if;
  perform cron.schedule(''process-checkin-tasks'', ''* * * * *'', $$ select public.process_checkin_tasks(); $$);
end $do$;
"}', 'passive_sos_watch_parity', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260620162349', '{"-- #1 本人不再收到关于自己告警的通知(self 阶段交给本机 overlay 提示报平安)
-- #2 SOS 用独立 kind=''sos'' 与更严重文案,与 unusual silence 区分;贯穿各升级阶段
create or replace function private.notify_stage(_alert_id uuid, _user uuid, _stage text)
returns void language plpgsql security definer set search_path to '''' as $$
declare _name text; _p jsonb; _sos boolean;
begin
  select coalesce(display_name,'''') into _name from public.profiles where id = _user;
  select (cause = ''sos'') into _sos from public.alerts where id = _alert_id;
  _p := jsonb_build_object(''name'', _name);

  -- 本人由本机 overlay 提示报平安,不发服务器通知给自己
  if _stage = ''self'' then
    return;
  end if;

  if _stage = ''group'' then
    insert into public.notifications (recipient_id, alert_id, kind, body, params)
    select distinct s.r, _alert_id,
      case when _sos then ''sos'' else ''group'' end,
      case when _sos
        then ''🆘 '' || _name || '' 发出紧急求救(SOS)！请立即联系并尽快前往确认。''
        else _name || '' 出现异常沉默，请尽快联系确认其安全。'' end,
      _p
    from (
      select w.user_id as r
      from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _user and t.monitored and t.status = ''active''
        and w.watching and w.status = ''active'' and w.user_id <> _user
      union
      select g.guardian_id from public.guardianships g
      where g.ward_id = _user and g.status = ''active''
    ) s;

  elsif _stage = ''community'' then
    insert into public.notifications (recipient_id, alert_id, kind, body, params)
    select distinct y.user_id, _alert_id,
      case when _sos then ''sos'' else ''community'' end,
      case when _sos
        then ''🆘 社区紧急：'' || _name || '' 发出 SOS 求救且小组未及时响应，请立即协助联系。''
        else ''社区警示：'' || _name || '' 长时间失联且其小组无人响应，请协助推动联系。'' end,
      _p
    from public.community_members x
    join public.community_members y on x.community_id = y.community_id
    where x.user_id = _user and x.status = ''active''
      and y.status = ''active'' and y.user_id <> _user;

  elsif _stage = ''terminal'' then
    insert into public.notifications (recipient_id, alert_id, kind, body, params)
    select distinct s.r, _alert_id,
      case when _sos then ''sos'' else ''terminal'' end,
      case when _sos
        then ''🆘 紧急：'' || _name || '' SOS 求救且持续无响应。已为你解锁其地址与紧急联系人，请立即上门或协助报警。''
        else ''紧急：'' || _name || '' 持续无响应。已为你解锁其地址与紧急联系人，请上门探视或协助报警。'' end,
      _p
    from (
      select w.user_id as r
      from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _user and t.monitored and t.status = ''active''
        and w.watching and w.status = ''active'' and w.user_id <> _user
      union
      select g.guardian_id from public.guardianships g
      where g.ward_id = _user and g.status = ''active''
    ) s;
  end if;
end;
$$;

-- #3 只有\"我去联系\"(ack_alert 记录的 paused_by)的那位成员可以确认安全
create or replace function public.resolve_alert(_alert_id uuid)
returns void language plpgsql security definer set search_path to '''' as $$
declare _uid uuid := auth.uid(); _target uuid; _tname text;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  if not private.can_see_alert(_alert_id, _uid) then raise exception ''forbidden''; end if;
  if not exists (select 1 from public.alerts where id = _alert_id and paused_by = _uid) then
    raise exception ''only the responder who reached out can confirm safe'';
  end if;

  update public.alerts
    set status = ''resolved'', resolved_at = now(), resolved_by = _uid, updated_at = now()
    where id = _alert_id and status = ''open'' returning user_id into _target;
  if _target is null then raise exception ''alert not open''; end if;

  insert into public.alert_events (alert_id, actor_id, kind) values (_alert_id, _uid, ''confirmed_safe'');

  select coalesce(display_name, '''') into _tname from public.profiles where id = _target;
  insert into public.notifications (recipient_id, alert_id, kind, body, params)
  select distinct s.r, _alert_id, ''resolved'', _tname || '' 已确认安全，告警解除。'',
    jsonb_build_object(''target'', _tname)
  from (
    select _target as r
    union
    select w.user_id from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _target and t.monitored and t.status = ''active''
        and w.watching and w.status = ''active''
  ) s;
end;
$$;

-- 升级时清空 paused_by,使新阶段成员可重新认领\"我去联系\"
create or replace function public.process_escalations()
returns void language plpgsql security definer set search_path to '''' as $$
declare
  _self_grace constant interval := interval ''30 minutes'';
  _group_dur  constant interval := interval ''1 hour'';
  _comm_dur   constant interval := interval ''2 hours'';
  r record; _aid uuid; _new text;
begin
  for r in
    select ds.user_id,
           (now() - ds.last_heartbeat_at) > interval ''18 hours'' as is_dark
    from public.device_state ds
    where (ds.status = ''alert''
           or (now() - ds.last_heartbeat_at) > private.silence_threshold(ds.user_id))
      and exists (select 1 from public.group_members gm
                  where gm.user_id = ds.user_id and gm.monitored and gm.status = ''active'')
      and not exists (select 1 from public.alerts a where a.user_id = ds.user_id and a.status = ''open'')
  loop
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    values (r.user_id, case when r.is_dark then ''dark_device'' else ''silence'' end,
            ''self'', now(), now() + _self_grace)
    returning id into _aid;
    insert into public.alert_events (alert_id, kind) values (_aid, ''raised'');
    perform private.notify_stage(_aid, r.user_id, ''self'');
  end loop;

  for r in
    select * from public.alerts
    where status = ''open''
      and next_deadline is not null and next_deadline <= now()
      and coalesce(paused_until, to_timestamp(0)) <= now()
  loop
    _new := case r.stage
              when ''self'' then ''group''
              when ''group'' then ''community''
              when ''community'' then ''terminal''
              else ''terminal'' end;
    update public.alerts
      set stage = _new, stage_entered_at = now(), paused_until = null, paused_by = null, updated_at = now(),
          next_deadline = case _new when ''group'' then now() + _group_dur
                                    when ''community'' then now() + _comm_dur
                                    else null end
      where id = r.id;
    insert into public.alert_events (alert_id, kind, note) values (r.id, ''escalated'', _new);
    perform private.notify_stage(r.id, r.user_id, _new);
  end loop;
end;
$$;"}', 'alerts_sos_severity_and_reacher_gating', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260621022839', '{"-- 确认安全=人工核实对方无恙:除解除告警外,把其活跃状态归正常,
-- 看板立即恢复(不再 alerted,且显示活跃),也避免立刻被重新升级。
create or replace function public.resolve_alert(_alert_id uuid)
returns void language plpgsql security definer set search_path to '''' as $$
declare _uid uuid := auth.uid(); _target uuid; _tname text;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  if not private.can_see_alert(_alert_id, _uid) then raise exception ''forbidden''; end if;
  if not exists (select 1 from public.alerts where id = _alert_id and paused_by = _uid) then
    raise exception ''only the responder who reached out can confirm safe'';
  end if;

  update public.alerts
    set status = ''resolved'', resolved_at = now(), resolved_by = _uid, updated_at = now()
    where id = _alert_id and status = ''open'' returning user_id into _target;
  if _target is null then raise exception ''alert not open''; end if;

  insert into public.alert_events (alert_id, actor_id, kind) values (_alert_id, _uid, ''confirmed_safe'');

  -- 归一化被关注者的活跃状态 → 看板立即回到正常
  insert into public.device_state (user_id, status, last_heartbeat_at, updated_at)
  values (_target, ''normal'', now(), now())
  on conflict (user_id) do update set status = ''normal'', last_heartbeat_at = now(), updated_at = now();

  select coalesce(display_name, '''') into _tname from public.profiles where id = _target;
  insert into public.notifications (recipient_id, alert_id, kind, body, params)
  select distinct s.r, _alert_id, ''resolved'', _tname || '' 已确认安全，告警解除。'',
    jsonb_build_object(''target'', _tname)
  from (
    select _target as r
    union
    select w.user_id from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _target and t.monitored and t.status = ''active''
        and w.watching and w.status = ''active''
  ) s;
end;
$$;"}', 'resolve_alert_normalizes_device_state', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260622144931', '{"-- 每个用户的各个客户端(按设备):平台 + App 版本 + 最后活跃时间。
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

drop policy if exists \"clients self select\" on public.clients;
create policy \"clients self select\" on public.clients
  for select using (auth.uid() = user_id);

-- App 打开时上报(SECURITY DEFINER:绕过 RLS 写入自己的那行)
create or replace function public.report_client(
  _client_id text, _platform text, _version text
) returns void language plpgsql security definer set search_path to '''' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  if _client_id is null or length(_client_id) = 0 then return; end if;
  insert into public.clients (user_id, client_id, platform, app_version, first_seen_at, last_seen_at)
  values (_uid, left(_client_id, 64), left(_platform, 32), left(_version, 32), now(), now())
  on conflict (user_id, client_id) do update
    set platform = excluded.platform,
        app_version = excluded.app_version,
        last_seen_at = now();
end;
$$;

grant execute on function public.report_client(text, text, text) to authenticated;"}', 'clients_table_and_report_client', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260622150745', '{"-- 新用户:display_name 优先取 OAuth 提供的 name / full_name(之前只取 display_name,
-- 导致 Google/Apple/Facebook 登录的用户 profiles.display_name 为空、到处显示 id)。
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path to '''' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, nullif(btrim(coalesce(
    new.raw_user_meta_data ->> ''display_name'',
    new.raw_user_meta_data ->> ''name'',
    new.raw_user_meta_data ->> ''full_name''
  )), ''''))
  on conflict (id) do nothing;
  insert into public.heartbeat_tokens (user_id) values (new.id) on conflict (user_id) do nothing;
  insert into public.user_settings (user_id) values (new.id) on conflict (user_id) do nothing;
  return new;
end;
$$;

-- 回填:名字只在 auth 元数据里、profiles.display_name 为空的现有用户补上
update public.profiles p
set display_name = nullif(btrim(coalesce(
    u.raw_user_meta_data ->> ''display_name'',
    u.raw_user_meta_data ->> ''name'',
    u.raw_user_meta_data ->> ''full_name''
  )), '''')
from auth.users u
where u.id = p.id
  and (p.display_name is null or btrim(p.display_name) = '''')
  and nullif(btrim(coalesce(
    u.raw_user_meta_data ->> ''display_name'',
    u.raw_user_meta_data ->> ''name'',
    u.raw_user_meta_data ->> ''full_name''
  )), '''') is not null;"}', 'profile_display_name_from_oauth_metadata', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260622151410', '{"-- GM/管理员名单(仅 SECURITY DEFINER 函数可读)
create table if not exists public.app_admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.app_admins enable row level security;
insert into public.app_admins (user_id)
values (''b897a59f-0a54-42df-9926-8452e477d8bd'') on conflict do nothing;

create or replace function private.is_admin(_uid uuid)
returns boolean language sql security definer set search_path to '''' stable as $$
  select exists (select 1 from public.app_admins where user_id = _uid)
$$;

-- 当前用户是否 GM(决定是否显示 GM 页)
create or replace function public.am_i_gm()
returns boolean language sql security definer set search_path to '''' stable as $$
  select private.is_admin(auth.uid())
$$;
grant execute on function public.am_i_gm() to authenticated;

-- 列出所有用户及其各客户端的版本/平台(GM-only)
create or replace function public.gm_list_clients()
returns jsonb language plpgsql security definer set search_path to '''' as $$
declare _uid uuid := auth.uid();
begin
  if not private.is_admin(_uid) then raise exception ''forbidden''; end if;
  return coalesce((
    select jsonb_agg(obj order by nm asc, ls desc nulls last)
    from (
      select jsonb_build_object(
        ''user_id'', p.id,
        ''name'', coalesce(nullif(p.display_name,''''), left(p.id::text,8)),
        ''platform'', c.platform,
        ''app_version'', c.app_version,
        ''last_seen_at'', c.last_seen_at
      ) as obj,
      coalesce(nullif(p.display_name,''''), left(p.id::text,8)) as nm,
      c.last_seen_at as ls
      from public.profiles p
      left join public.clients c on c.user_id = p.id
    ) s
  ), ''[]''::jsonb);
end;
$$;
grant execute on function public.gm_list_clients() to authenticated;

-- GM 提醒某用户更新版本
create or replace function public.gm_nudge_update(_target uuid)
returns void language plpgsql security definer set search_path to '''' as $$
begin
  if not private.is_admin(auth.uid()) then raise exception ''forbidden''; end if;
  insert into public.notifications (recipient_id, kind, body, params)
  values (_target, ''update'', ''请更新到最新版本的 Keep Contact。'', ''{}''::jsonb);
end;
$$;
grant execute on function public.gm_nudge_update(uuid) to authenticated;

-- GM 向任意用户发送关怀(不受同组限制)
create or replace function public.gm_send_concern(_target uuid)
returns void language plpgsql security definer set search_path to '''' as $$
declare _name text;
begin
  if not private.is_admin(auth.uid()) then raise exception ''forbidden''; end if;
  select coalesce(display_name,'''') into _name from public.profiles where id = auth.uid();
  insert into public.notifications (recipient_id, kind, body, params)
  values (_target, ''concern'',
    coalesce(nullif(_name,''''),''管理员'') || '' 在关心你,请打开 App 完成解锁报平安。'',
    jsonb_build_object(''name'', _name));
end;
$$;
grant execute on function public.gm_send_concern(uuid) to authenticated;"}', 'gm_admin_console', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260623065518', '{"-- GM/管理员删除/封禁用户账号
create or replace function public.gm_delete_user(_target uuid)
returns void language plpgsql security definer set search_path to '''' as $$
begin
  if not private.is_admin(auth.uid()) then raise exception ''forbidden''; end if;

  -- Delete all associated rows to prevent foreign key constraint violations
  delete from public.clients where user_id = _target;
  delete from public.notifications where recipient_id = _target or actor_id = _target;
  delete from public.alert_signals where user_id = _target;
  delete from public.alerts where user_id = _target or paused_by = _target;
  delete from public.guardians where user_id = _target or guardian_id = _target;
  delete from public.group_members where user_id = _target;
  delete from public.checkin_tasks where user_id = _target or created_by = _target;

  -- Finally delete user profile
  delete from public.profiles where id = _target;
end;
$$;
grant execute on function public.gm_delete_user(uuid) to authenticated;"}', 'gm_delete_user', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260623065530', '{"-- Add pattern_hash column to user_settings table to sync lock gesture patterns across devices.
alter table public.user_settings add column if not exists pattern_hash text;"}', 'add_pattern_hash', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260624100122', '{"-- Add policy to allow authenticated users to insert their own behavior pings.
create policy behavior_pings_insert on public.behavior_pings
  for insert to authenticated with check (auth.uid() = user_id);"}', 'add_behavior_pings_insert_policy', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260623081519', '{"create or replace function public.gm_list_clients()
returns jsonb language plpgsql security definer set search_path to '''' as $$
declare _uid uuid := auth.uid();
begin
  if not private.is_admin(_uid) then raise exception ''forbidden''; end if;
  return coalesce((
    select jsonb_agg(obj order by nm asc, ls desc nulls last)
    from (
      select jsonb_build_object(
        ''user_id'', p.id,
        ''name'', coalesce(nullif(p.display_name,''''), left(p.id::text,8)),
        ''platform'', c.platform,
        ''app_version'', c.app_version,
        ''first_seen_at'', c.first_seen_at,
        ''last_seen_at'', c.last_seen_at,
        ''last_heartbeat_at'', ds.last_heartbeat_at,
        ''alerted'', exists (
          select 1 from public.alerts a
          where a.user_id = p.id and a.status = ''open''
            and a.stage in (''group'',''community'',''terminal'')
        )
      ) as obj,
      coalesce(nullif(p.display_name,''''), left(p.id::text,8)) as nm,
      c.last_seen_at as ls
      from public.profiles p
      left join public.clients c on c.user_id = p.id
      left join public.device_state ds on ds.user_id = p.id
    ) s
  ), ''[]''::jsonb);
end;
$$;
grant execute on function public.gm_list_clients() to authenticated;"}', 'gm_list_clients_liveness', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260623081532', '{"create extension if not exists pg_cron;

create or replace function public.prune_stale_clients()
returns void language sql security definer set search_path to '''' as $$
  delete from public.clients where last_seen_at < now() - interval ''30 days'';
$$;

do $do$
declare _jobid bigint;
begin
  select jobid into _jobid from cron.job where jobname = ''prune-stale-clients'';
  if _jobid is not null then perform cron.unschedule(_jobid); end if;
  perform cron.schedule(''prune-stale-clients'', ''17 3 * * *'', $$ select public.prune_stale_clients(); $$);
end $do$;"}', 'prune_stale_clients', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260624050102', '{"-- GM 用户列表:返回真实存活信号(device_state.last_heartbeat_at)与 open 告警标记，
-- 并在此处直接计算 status，使 GM 状态点与「群组成员看板」(get_group_activity)同源同阈值。
create or replace function public.gm_list_clients()
returns jsonb language plpgsql security definer set search_path to '''' as $$
declare _uid uuid := auth.uid();
begin
  if not private.is_admin(_uid) then raise exception ''forbidden''; end if;
  return coalesce((
    select jsonb_agg(obj order by nm asc, ls desc nulls last)
    from (
      select jsonb_build_object(
        ''user_id'', p.id,
        ''name'', coalesce(nullif(p.display_name,''''), left(p.id::text,8)),
        ''platform'', c.platform,
        ''app_version'', c.app_version,
        ''first_seen_at'', c.first_seen_at,
        ''last_seen_at'', c.last_seen_at,
        ''last_heartbeat_at'', ds.last_heartbeat_at,
        ''alerted'', exists (
          select 1 from public.alerts a
          where a.user_id = p.id and a.status = ''open''
            and a.stage in (''group'',''community'',''terminal'')
        ),
        ''status'',
        ''status'',
          case
            when exists (
              select 1 from public.alerts a
              where a.user_id = p.id and a.status = ''open''
                and a.stage in (''group'',''community'',''terminal'')
            ) then ''alert''
            when ds.last_heartbeat_at is null then ''never''
            when ds.last_heartbeat_at > now() - interval ''6 hours'' then ''active''
            when ds.last_heartbeat_at > now() - interval ''24 hours'' then ''quiet''
            else ''silent''
          end
      ) as obj,
      coalesce(nullif(p.display_name,''''), left(p.id::text,8)) as nm,
      c.last_seen_at as ls
      from public.profiles p
      left join public.clients c on c.user_id = p.id
      left join public.device_state ds on ds.user_id = p.id
    ) s
  ), ''[]''::jsonb);
end;
$$;

grant execute on function public.gm_list_clients() to authenticated;"}', 'gm_list_clients_unified_status', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260624050109', '{"-- Harden emergency_info RLS policies.
-- Restrict guardians and watchers from viewing emergency info unless there is an active open alert.

drop policy if exists emergency_info_select on public.emergency_info;

create policy emergency_info_select on public.emergency_info
  for select to authenticated
  using (
    (select auth.uid()) = user_id
    or (
      exists (
        select 1 from public.alerts a
        where a.user_id = emergency_info.user_id
          and a.status = ''open''
          and a.stage in (''group'', ''community'', ''terminal'')
      )
      and (
        private.is_guardian_of(user_id, (select auth.uid()))
        or private.watches_user((select auth.uid()), emergency_info.user_id)
        or private.shares_community((select auth.uid()), emergency_info.user_id)
      )
    )
  );"}', 'harden_emergency_info_rls', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260624050114', '{"-- Add location coordinates to emergency_info for SOS tracking.
alter table public.emergency_info
  add column if not exists latitude double precision,
  add column if not exists longitude double precision,
  add column if not exists location_accuracy double precision,
  add column if not exists location_updated_at timestamp with time zone;"}', 'add_emergency_location_columns', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260624050121', '{"-- Allow guardians and group members to select client device states during active alerts.
drop policy if exists \"clients self select\" on public.clients;

create policy \"clients select during active alert\" on public.clients
  for select to authenticated
  using (
    auth.uid() = user_id
    or (
      exists (
        select 1 from public.alerts a
        where a.user_id = clients.user_id
          and a.status = ''open''
          and a.stage in (''group'', ''community'', ''terminal'')
      )
      and (
        private.is_guardian_of(user_id, (select auth.uid()))
        or private.watches_user((select auth.uid()), clients.user_id)
        or private.shares_community((select auth.uid()), clients.user_id)
      )
    )
  );"}', 'allow_guardians_read_clients_during_alert', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260624050135', '{"-- Pre-drop re-defined functions to avoid parameter name change errors
drop function if exists private.silence_threshold(uuid);
drop function if exists private.is_in_sleep_window(uuid, timestamptz);

-- #1 Define silence_threshold to return user''s custom baseline duration based on sensitivity setting
create or replace function private.silence_threshold(_user_id uuid)
returns interval language plpgsql security definer set search_path to '''' stable as $$
declare _s text;
begin
  select sensitivity into _s from public.user_settings where user_id = _user_id;
  return case coalesce(_s, ''balanced'')
    when ''high'' then interval ''1.5 hours''
    when ''low'' then interval ''6 hours''
    else interval ''3 hours''
  end;
end;
$$;

-- #2 Define dynamic sleep window calculation
create or replace function private.is_in_sleep_window(_user_id uuid, _now timestamptz)
returns boolean language plpgsql security definer set search_path to '''' stable as $$
declare
  _start time; _end time;
  _now_utc timestamptz;
  _date date;
  _start_ts timestamptz;
  _end_ts timestamptz;
  _dur interval;
  _last_active timestamptz;
  _dynamic_end timestamptz;
begin
  select sleep_start_utc, sleep_end_utc into _start, _end
    from public.user_settings where user_id = _user_id;
  if _start is null or _end is null then
    return false;
  end if;

  _now_utc := _now at time zone ''UTC'';
  _date := _now_utc::date;

  if _start > _end then
    if _now_utc::time < _end then
      _start_ts := (_date - 1 + _start) at time zone ''UTC'';
      _end_ts := (_date + _end) at time zone ''UTC'';
    else
      _start_ts := (_date + _start) at time zone ''UTC'';
      _end_ts := (_date + 1 + _end) at time zone ''UTC'';
    end if;
  else
    if _now_utc::time < _start then
      _start_ts := (_date - 1 + _start) at time zone ''UTC'';
      _end_ts := (_date - 1 + _end) at time zone ''UTC'';
    else
      _start_ts := (_date + _start) at time zone ''UTC'';
      _end_ts := (_date + _end) at time zone ''UTC'';
    end if;
  end if;

  _dur := _end_ts - _start_ts;

  -- 取得用户最近的行为 ping 时间
  select max(at) into _last_active
    from public.behavior_pings
    where user_id = _user_id;

  if _last_active is not null then
    -- 如果最近活动在 [开始前 1 小时, 结束时间] 范围内，说明此活动属于该睡眠周期的晚睡或中途醒来
    if _last_active >= _start_ts - interval ''1 hour'' and _last_active <= _end_ts then
      -- 动态延长结束时间为：最后活动时间 + 睡眠窗时长，但最多延长 3 小时
      _dynamic_end := least(_last_active + _dur, _end_ts + interval ''3 hours'');
      return _now >= _start_ts and _now < _dynamic_end;
    end if;
  end if;

  -- 默认：严格按设定的时间段判定
  return _now >= _start_ts and _now < _end_ts;
end;
$$;

-- #3 Define instant push-dispatch trigger
create or replace function private.trigger_push_dispatch()
returns void language plpgsql security definer set search_path to '''' as $$
begin
  perform net.http_post(
    url := ''https://byekgmqyqlftgoveqnku.supabase.co/functions/v1/push-dispatch'',
    headers := jsonb_build_object(''Content-Type'', ''application/json''),
    body := ''{}''::jsonb
  );
exception when others then
  -- Fail silently to avoid blocking parent transaction
  null;
end;
$$;

-- #4 Redefine process_escalations to check behavior pings instead of ds.last_heartbeat_at
create or replace function public.process_escalations()
returns void language plpgsql security definer set search_path to '''' as $$
declare
  _self_grace constant interval := interval ''30 minutes'';
  _group_dur  constant interval := interval ''1 hour'';
  _comm_dur   constant interval := interval ''2 hours'';
  r record; _aid uuid; _new text; _triggered boolean := false;
begin
  for r in
    select ds.user_id,
           (now() - ds.last_heartbeat_at) > interval ''18 hours'' as is_dark
    from public.device_state ds
    where (
      ds.status = ''alert''
      or now() - ds.last_heartbeat_at > interval ''18 hours''
      or (
        not private.is_in_sleep_window(ds.user_id, now())
        and now() - (
          select coalesce(max(at), to_timestamp(0))
          from public.behavior_pings
          where user_id = ds.user_id
        ) > private.silence_threshold(ds.user_id)
      )
    )
      and exists (select 1 from public.group_members gm
                  where gm.user_id = ds.user_id and gm.monitored and gm.status = ''active'')
      and not exists (select 1 from public.alerts a where a.user_id = ds.user_id and a.status = ''open'')
  loop
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    values (r.user_id, case when r.is_dark then ''dark_device'' else ''silence'' end,
            ''self'', now(), now() + _self_grace)
    returning id into _aid;
    insert into public.alert_events (alert_id, kind) values (_aid, ''raised'');
    perform private.notify_stage(_aid, r.user_id, ''self'');
    _triggered := true;
  end loop;

  for r in
    select * from public.alerts
    where status = ''open''
      and next_deadline is not null and next_deadline <= now()
      and coalesce(paused_until, to_timestamp(0)) <= now()
  loop
    _new := case r.stage
              when ''self'' then ''group''
              when ''group'' then ''community''
              when ''community'' then ''terminal''
              else ''terminal'' end;
    update public.alerts
      set stage = _new, stage_entered_at = now(), paused_until = null, paused_by = null, updated_at = now(),
          next_deadline = case _new when ''group'' then now() + _group_dur
                                    when ''community'' then now() + _comm_dur
                                    else null end
      where id = r.id;
    insert into public.alert_events (alert_id, kind, note) values (r.id, ''escalated'', _new);
    perform private.notify_stage(r.id, r.user_id, _new);
    _triggered := true;
  end loop;

  if _triggered then
    perform private.trigger_push_dispatch();
  end if;
end;
$$;

-- #5 Define trigger function to auto-update device state and resolve alerts on behavior ping insert
create or replace function private.handle_behavior_ping_insert()
returns trigger language plpgsql security definer set search_path to '''' as $$
declare _stale record; _triggered boolean := false;
begin
  -- 1) 更新心跳状态为正常
  insert into public.device_state (user_id, status, last_heartbeat_at, updated_at)
  values (new.user_id, ''normal'', new.at, now())
  on conflict (user_id) do update
    set status = ''normal'', last_heartbeat_at = new.at, updated_at = now();

  -- 2) 自动解除 open 的 silence/dark_device 告警
  for _stale in
    select id from public.alerts
    where user_id = new.user_id
      and status = ''open''
      and cause in (''silence'', ''dark_device'')
  loop
    update public.alerts
      set status = ''resolved'', resolved_at = new.at, resolved_by = new.user_id, updated_at = now()
      where id = _stale.id;
      
    insert into public.alert_events (alert_id, actor_id, kind)
    values (_stale.id, new.user_id, ''auto_resolved'');

    -- 清除该告警产生的所有通知
    delete from public.notifications where alert_id = _stale.id;
    _triggered := true;
  end loop;

  -- 3) 清除本人的 \"please check in\" 提示
  delete from public.notifications
    where recipient_id = new.user_id
      and kind in (''self'', ''concern'');

  if _triggered then
    perform private.trigger_push_dispatch();
  end if;

  return new;
end;
$$;

drop trigger if exists on_behavior_ping_insert on public.behavior_pings;
create trigger on_behavior_ping_insert
  after insert on public.behavior_pings
  for each row execute function private.handle_behavior_ping_insert();

-- #6 Update RPCs to trigger push dispatch immediately
create or replace function public.resolve_alert(_alert_id uuid)
returns void language plpgsql security definer set search_path to '''' as $$
declare _uid uuid := auth.uid(); _target uuid; _tname text;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  if not private.can_see_alert(_alert_id, _uid) then raise exception ''forbidden''; end if;
  if not exists (select 1 from public.alerts where id = _alert_id and paused_by = _uid) then
    raise exception ''only the responder who reached out can confirm safe'';
  end if;

  update public.alerts
    set status = ''resolved'', resolved_at = now(), resolved_by = _uid, updated_at = now()
    where id = _alert_id and status = ''open'' returning user_id into _target;
  if _target is null then raise exception ''alert not open''; end if;

  insert into public.alert_events (alert_id, actor_id, kind) values (_alert_id, _uid, ''confirmed_safe'');

  -- 归一化被关注者的活跃状态
  insert into public.device_state (user_id, status, last_heartbeat_at, updated_at)
  values (_target, ''normal'', now(), now())
  on conflict (user_id) do update set status = ''normal'', last_heartbeat_at = now(), updated_at = now();

  select coalesce(display_name, '''') into _tname from public.profiles where id = _target;
  insert into public.notifications (recipient_id, alert_id, kind, body, params)
  select distinct s.r, _alert_id, ''resolved'', _tname || '' 已确认安全，告警解除。'',
    jsonb_build_object(''target'', _tname)
  from (
    select _target as r
    union
    select w.user_id from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _target and t.monitored and t.status = ''active''
        and w.watching and w.status = ''active''
  ) s;

  perform private.trigger_push_dispatch();
end;
$$;

create or replace function public.resolve_my_alert()
returns void language plpgsql security definer set search_path to '''' as $$
declare _uid uuid := auth.uid(); _aid uuid;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  update public.alerts set status = ''resolved'', resolved_at = now(), resolved_by = _uid, updated_at = now()
    where user_id = _uid and status = ''open'' returning id into _aid;
  if _aid is not null then
    insert into public.alert_events (alert_id, actor_id, kind) values (_aid, _uid, ''resolved'');
  end if;
  -- 同步设备状态为正常
  insert into public.device_state (user_id, status, last_heartbeat_at, updated_at)
  values (_uid, ''normal'', now(), now())
  on conflict (user_id) do update set status = ''normal'', last_heartbeat_at = now(), updated_at = now();

  perform private.trigger_push_dispatch();
end;
$$;

create or replace function public.raise_sos()
returns uuid language plpgsql security definer set search_path to '''' as $$
declare _uid uuid := auth.uid(); _aid uuid;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  select id into _aid from public.alerts where user_id = _uid and status = ''open'';
  if _aid is null then
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    values (_uid, ''sos'', ''group'', now(), now() + interval ''1 hour'')
    returning id into _aid;
    insert into public.alert_events (alert_id, actor_id, kind) values (_aid, _uid, ''raised'');
  else
    update public.alerts set cause = ''sos'', stage = ''group'', stage_entered_at = now(),
      next_deadline = now() + interval ''1 hour'', paused_until = null, updated_at = now()
      where id = _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note) values (_aid, _uid, ''escalated'', ''sos'');
  end if;
  perform private.notify_stage(_aid, _uid, ''group'');

  perform private.trigger_push_dispatch();
  return _aid;
end;
$$;"}', 'centralize_alert_logic', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260624051146', '{"-- Correct the gm_list_clients function definition to have an even number of jsonb_build_object arguments
create or replace function public.gm_list_clients()
returns jsonb language plpgsql security definer set search_path to '''' as $$
declare _uid uuid := auth.uid();
begin
  if not private.is_admin(_uid) then raise exception ''forbidden''; end if;
  return coalesce((
    select jsonb_agg(obj order by nm asc, ls desc nulls last)
    from (
      select jsonb_build_object(
        ''user_id'', p.id,
        ''name'', coalesce(nullif(p.display_name,''''), left(p.id::text,8)),
        ''platform'', c.platform,
        ''app_version'', c.app_version,
        ''first_seen_at'', c.first_seen_at,
        ''last_seen_at'', c.last_seen_at,
        ''last_heartbeat_at'', ds.last_heartbeat_at,
        ''alerted'', exists (
          select 1 from public.alerts a
          where a.user_id = p.id and a.status = ''open''
            and a.stage in (''group'',''community'',''terminal'')
        ),
        ''status'',
          case
            when exists (
              select 1 from public.alerts a
              where a.user_id = p.id and a.status = ''open''
                and a.stage in (''group'',''community'',''terminal'')
            ) then ''alert''
            when ds.last_heartbeat_at is null then ''never''
            when ds.last_heartbeat_at > now() - interval ''6 hours'' then ''active''
            when ds.last_heartbeat_at > now() - interval ''24 hours'' then ''quiet''
            else ''silent''
          end
      ) as obj,
      coalesce(nullif(p.display_name,''''), left(p.id::text,8)) as nm,
      c.last_seen_at as ls
      from public.profiles p
      left join public.clients c on c.user_id = p.id
      left join public.device_state ds on ds.user_id = p.id
    ) s
  ), ''[]''::jsonb);
end;
$$;

grant execute on function public.gm_list_clients() to authenticated;"}', 'fix_gm_list_clients_parameters', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260624051721', '{"-- Alter behavior_pings constraint to allow all valid kinds of user interactions.
alter table public.behavior_pings
  drop constraint if exists behavior_pings_kind_check;

alter table public.behavior_pings
  add constraint behavior_pings_kind_check check (
    kind in (''app'', ''interaction'', ''steps'', ''unlock'', ''manual_checkin'')
  );"}', 'fix_behavior_pings_check_constraint', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260624104625', '{"-- Alter public.profiles to add routine pattern and data sharing consent columns
alter table public.profiles
  add column routine_pattern text not null default ''regular_9to5'',
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
  for select to authenticated using (auth.uid() = user_id);"}', 'add_adaptive_routine_schema', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260624105756', '{"-- 1. Add timezone column to public.user_settings
alter table public.user_settings
  add column if not exists timezone text not null default ''UTC'';

-- 2. Ensure cron secret exists in private.app_config
insert into private.app_config (key, value)
values (''cron_secret'', encode(gen_random_bytes(16), ''hex''))
on conflict (key) do nothing;

-- 3. Create function to initialize/seed user routine aggregates
create or replace function public.initialize_user_routine_data(_user_id uuid)
returns void language plpgsql security definer set search_path to '''' as $$
declare
  _pattern text;
  _date date;
  _hourly_density integer[];
  _d int;
  _h int;
  _is_weekend boolean;
  _val int;
  _month int;
  _is_break boolean;
begin
  -- Fetch current pattern
  select routine_pattern into _pattern from public.profiles where id = _user_id;
  _pattern := coalesce(_pattern, ''regular_9to5'');

  -- Delete existing aggregates to prevent duplicates
  delete from public.daily_activity_aggregates where user_id = _user_id;

  -- Generate 180 days of data ending yesterday
  for _d in 1..180 loop
    _date := current_date - _d;
    _is_weekend := extract(isodow from _date) in (6, 7);
    _month := extract(month from _date)::int;
    
    -- Determine if it''s a break month (July, August, January) for semester_break
    _is_break := (_month in (1, 7, 8));

    _hourly_density := array_fill(0, array[24]);

    for _h in 0..23 loop
      _val := 0;
      if _pattern = ''regular_9to5'' then
        if _is_weekend then
          -- Weekend: Sleep 01:00 - 09:00
          if _h >= 9 or _h = 0 then
            _val := floor(random() * 8 + 2)::int; -- random 2 to 9 pings
          end if;
        else
          -- Weekday: Sleep 23:00 - 07:00
          if _h >= 7 and _h < 23 then
            if _h in (8, 9, 12, 13, 17, 18, 21, 22) then
              _val := floor(random() * 12 + 8)::int; -- Peak commute/lunch/evening hours
            else
              _val := floor(random() * 5 + 3)::int; -- Standard work hours
            end if;
          end if;
        end if;

      elsif _pattern = ''semester_break'' then
        if _is_break then
          -- Vacation: sleep 02:00 - 10:00
          if _h >= 10 or _h < 2 then
            _val := floor(random() * 6 + 1)::int;
          end if;
        else
          -- Semester: active 08:00 - 23:00
          if _h >= 8 and _h < 23 then
            if _h in (9, 10, 14, 15, 19, 20) then
              _val := floor(random() * 10 + 6)::int; -- Class and dinner times
            else
              _val := floor(random() * 6 + 2)::int;
            end if;
          end if;
        end if;

      else -- shift_irregular
        -- Shift work / irregular: active at erratic hours
        -- We model this by alternating active hours on different days
        if ((_d % 3 = 0 and (_h >= 0 and _h < 8)) or (_d % 3 <> 0 and (_h >= 8 and _h < 24))) then
          _val := floor(random() * 7 + 1)::int;
        end if;
      end if;

      _hourly_density[_h + 1] := _val;
    end loop;

    insert into public.daily_activity_aggregates (user_id, date, hourly_density)
    values (_user_id, _date, _hourly_density)
    on conflict (user_id, date) do nothing;
  end loop;
end;
$$;

-- 4. Create trigger to seed data on profile routine pattern changes
create or replace function private.handle_profile_pattern_change()
returns trigger language plpgsql security definer set search_path to '''' as $$
begin
  if tg_op = ''INSERT'' or new.routine_pattern <> old.routine_pattern then
    perform public.initialize_user_routine_data(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists on_profile_pattern_change on public.profiles;
create trigger on_profile_pattern_change
  after insert or update of routine_pattern on public.profiles
  for each row execute function private.handle_profile_pattern_change();

-- 5. Create function to aggregate a single user''s pings for a specific local date
create or replace function private.aggregate_user_daily_activity(_user_id uuid, _date date)
returns void language plpgsql security definer set search_path to '''' as $$
declare
  _timezone text;
  _hourly_density integer[] := array_fill(0, array[24]);
  _ping record;
  _hour int;
begin
  -- Fetch user timezone
  select timezone into _timezone from public.user_settings where user_id = _user_id;
  _timezone := coalesce(_timezone, ''UTC'');

  -- Count pings per local hour for the specified local date
  for _ping in
    select extract(hour from at at time zone _timezone)::int as hr
    from public.behavior_pings
    where user_id = _user_id
      and (at at time zone _timezone)::date = _date
  loop
    _hour := _ping.hr;
    if _hour >= 0 and _hour <= 23 then
      _hourly_density[_hour + 1] := _hourly_density[_hour + 1] + 1;
    end if;
  end loop;

  -- Upsert aggregate row
  insert into public.daily_activity_aggregates (user_id, date, hourly_density)
  values (_user_id, _date, _hourly_density)
  on conflict (user_id, date) do update
    set hourly_density = excluded.hourly_density;
end;
$$;

-- 6. Create nightly aggregation runner
create or replace function public.run_daily_aggregations()
returns void language plpgsql security definer set search_path to '''' as $$
declare
  _user record;
  _timezone text;
  _yesterday date;
begin
  for _user in select id from auth.users loop
    select timezone into _timezone from public.user_settings where user_id = _user.id;
    _timezone := coalesce(_timezone, ''UTC'');
    
    -- Yesterday in user''s timezone
    _yesterday := (now() at time zone _timezone)::date - 1;
    
    perform private.aggregate_user_daily_activity(_user.id, _yesterday);
  end loop;
end;
$$;

-- 7. Create function to trigger weekly routine updates via Edge Function
create or replace function public.trigger_weekly_routine_updates()
returns void language plpgsql security definer set search_path to '''' as $$
declare
  _secret text;
begin
  select value into _secret from private.app_config where key = ''cron_secret'';
  perform net.http_post(
    url := ''https://byekgmqyqlftgoveqnku.supabase.co/functions/v1/update-routine-profile'',
    headers := jsonb_build_object(
      ''Content-Type'', ''application/json'',
      ''Authorization'', ''Bearer '' || _secret
    ),
    body := ''{}''::jsonb
  );
exception when others then
  -- Fail silently to avoid blocking transaction
  null;
end;
$$;

-- Create function to trigger single user routine update via Edge Function
create or replace function private.trigger_update_routine_profile(_user_id uuid)
returns void language plpgsql security definer set search_path to '''' as $$
declare
  _secret text;
  _payload jsonb;
begin
  select value into _secret from private.app_config where key = ''cron_secret'';
  _payload := jsonb_build_object(''user_id'', _user_id);
  perform net.http_post(
    url := ''https://byekgmqyqlftgoveqnku.supabase.co/functions/v1/update-routine-profile'',
    headers := jsonb_build_object(
      ''Content-Type'', ''application/json'',
      ''Authorization'', ''Bearer '' || _secret
    ),
    body := _payload
  );
exception when others then
  -- Fail silently to avoid blocking transaction
  null;
end;
$$;

-- Hook trigger to update routine profile on pattern change (after seeding is done)
create or replace function private.handle_profile_pattern_change_trigger()
returns trigger language plpgsql security definer set search_path to '''' as $$
begin
  if tg_op = ''INSERT'' or new.routine_pattern <> old.routine_pattern then
    perform private.trigger_update_routine_profile(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists on_profile_pattern_change_trigger on public.profiles;
create trigger on_profile_pattern_change_trigger
  after insert or update of routine_pattern on public.profiles
  for each row execute function private.handle_profile_pattern_change_trigger();

-- 8. Redefine silence_threshold to look up thresholds dynamically from user_activity_profiles
create or replace function private.silence_threshold(_user_id uuid)
returns interval language plpgsql security definer set search_path to '''' stable as $$
declare
  _s text;
  _timezone text;
  _threshold double precision;
  _multiplier double precision;
  _hour int;
  _is_weekend boolean;
begin
  -- Try to fetch dynamic AI/rule thresholds
  select timezone into _timezone from public.user_settings where user_id = _user_id;
  _timezone := coalesce(_timezone, ''UTC'');
  
  _hour := extract(hour from now() at time zone _timezone)::int;
  
  select hourly_thresholds[_hour + 1], weekend_multiplier
  into _threshold, _multiplier
  from public.user_activity_profiles
  where user_id = _user_id;
  
  if _threshold is not null then
    _is_weekend := extract(isodow from now() at time zone _timezone) in (6, 7);
    if _is_weekend then
      _threshold := _threshold * coalesce(_multiplier, 1.0);
    end if;
    return _threshold * interval ''1 hour'';
  end if;
  
  -- Fallback to static sensitivity setting
  select sensitivity into _s from public.user_settings where user_id = _user_id;
  return case coalesce(_s, ''balanced'')
    when ''high'' then interval ''1.5 hours''
    when ''low'' then interval ''6 hours''
    else interval ''3 hours''
  end;
end;
$$;

-- 9. Setup pg_cron schedules
do $$
declare _jobid bigint;
begin
  select jobid into _jobid from cron.job where jobname = ''run-daily-aggregations'';
  if _jobid is not null then perform cron.unschedule(_jobid); end if;
  perform cron.schedule(''run-daily-aggregations'', ''5 0 * * *'', ''$cron$ select public.run_daily_aggregations(); $cron$'');
end $$;

do $$
declare _jobid bigint;
begin
  select jobid into _jobid from cron.job where jobname = ''update-routine-profiles-weekly'';
  if _jobid is not null then perform cron.unschedule(_jobid); end if;
  perform cron.schedule(''update-routine-profiles-weekly'', ''0 1 * * 0'', ''$cron$ select public.trigger_weekly_routine_updates(); $cron$'');
end $$;"}', '20260624140000_adaptive_routine_impl', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260624170612', '{"-- Fix: Update resolve_alert and handle_behavior_ping_insert triggers
-- to keep user self check-in nudges when confirmed safe by a guardian,
-- and insert a fresh self check-in reminder nudge for the user themselves.

-- 1) Update trigger function private.handle_behavior_ping_insert() to conditionally clear notifications
create or replace function private.handle_behavior_ping_insert()
returns trigger language plpgsql security definer set search_path to '''' as $$
declare _stale record; _triggered boolean := false;
begin
  -- 1) 更新心跳状态为正常 (使用 greatest 确保时间只往前，不退后)
  insert into public.device_state (user_id, status, last_heartbeat_at, updated_at)
  values (new.user_id, ''normal'', new.at, now())
  on conflict (user_id) do update
    set status = ''normal'',
        last_heartbeat_at = greatest(device_state.last_heartbeat_at, excluded.last_heartbeat_at),
        updated_at = now();

  -- 2) 自动解除 open 的 silence/dark_device 告警
  for _stale in
    select id from public.alerts
    where user_id = new.user_id
      and status = ''open''
      and cause in (''silence'', ''dark_device'')
  loop
    update public.alerts
      set status = ''resolved'', resolved_at = new.at, resolved_by = new.user_id, updated_at = now()
      where id = _stale.id;
      
    insert into public.alert_events (alert_id, actor_id, kind)
    values (_stale.id, new.user_id, ''auto_resolved'');

    -- 清除该告警产生的所有通知
    delete from public.notifications where alert_id = _stale.id;
    _triggered := true;
  end loop;

  -- 3) 清除本人的 \"please check in\" 提示 (仅当不是由监护人/管理员帮其确认安全时)
  if not (auth.uid() is not null and auth.uid() <> new.user_id) then
    delete from public.notifications
      where recipient_id = new.user_id
        and kind in (''self'', ''concern'');
  end if;

  if _triggered then
    perform private.trigger_push_dispatch();
  end if;

  return new;
end;
$$;


-- 2) Update public.resolve_alert(_alert_id uuid) to insert behavior ping and send nudge to the user themselves
create or replace function public.resolve_alert(_alert_id uuid)
returns void language plpgsql security definer set search_path to '''' as $$
declare _uid uuid := auth.uid(); _target uuid; _tname text;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  if not private.can_see_alert(_alert_id, _uid) then raise exception ''forbidden''; end if;
  if not exists (select 1 from public.alerts where id = _alert_id and paused_by = _uid) then
    raise exception ''only the responder who reached out can confirm safe'';
  end if;

  update public.alerts
    set status = ''resolved'', resolved_at = now(), resolved_by = _uid, updated_at = now()
    where id = _alert_id and status = ''open'' returning user_id into _target;
  if _target is null then raise exception ''alert not open''; end if;

  insert into public.alert_events (alert_id, actor_id, kind) values (_alert_id, _uid, ''confirmed_safe'');

  -- 归一化被关注者的活跃状态
  insert into public.device_state (user_id, status, last_heartbeat_at, updated_at)
  values (_target, ''normal'', now(), now())
  on conflict (user_id) do update set status = ''normal'', last_heartbeat_at = now(), updated_at = now();

  -- 写入一条 behavior_ping，确保其最新活跃时间变成 now()，重置静默计时器防止立即重新报警
  insert into public.behavior_pings (user_id, kind, at)
  values (_target, ''manual_checkin'', now());

  -- 给被关注者自己发送一条 kind = ''self'' 的通知，保留提示，并在外部推送触发再次提示
  insert into public.notifications (recipient_id, alert_id, kind, body)
  values (_target, _alert_id, ''self'', ''【系统提示】小组已确认你安全，但检测到设备仍未活动。请解锁或使用手机以恢复自动守护！'');

  -- 给小组其他成员发送解除通知
  select coalesce(display_name, '''') into _tname from public.profiles where id = _target;
  insert into public.notifications (recipient_id, alert_id, kind, body, params)
  select distinct s.r, _alert_id, ''resolved'', _tname || '' 已确认安全，告警解除。'',
    jsonb_build_object(''target'', _tname)
  from (
    select _target as r
    union
    select w.user_id from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _target and t.monitored and t.status = ''active''
        and w.watching and w.status = ''active''
  ) s;

  perform private.trigger_push_dispatch();
end;
$$;"}', 'guardian_confirm_safe_keep_nudge', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260626095828', '{"-- Split group activity reads by UI intent.
-- Watch page: watcher lens, only people this user should watch in this group.
-- Circle group page: group lens, all active group members with normal share_activity privacy.

create or replace function public.get_group_activity_view(_group uuid, _view text)
returns jsonb language plpgsql security definer set search_path = '''' as $$
declare
  _uid uuid := auth.uid();
  _mode text := coalesce(nullif(btrim(_view), ''''), ''group'');
  _is_owner boolean;
  _i_watching boolean;
  _i_share boolean;
  _members jsonb;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  if _mode not in (''watch'', ''group'') then raise exception ''invalid activity view''; end if;

  select exists (
           select 1 from public.group_members gm
           where gm.group_id = g.id and gm.user_id = _uid
             and gm.role = ''admin'' and gm.status = ''active''
         ),
         coalesce(me.watching, false)
    into _is_owner, _i_watching
  from public.groups g
  join public.group_members me
    on me.group_id = g.id and me.user_id = _uid and me.status = ''active''
  where g.id = _group;
  if not found then raise exception ''forbidden''; end if;

  select coalesce(us.share_activity, true) into _i_share
  from public.user_settings us where us.user_id = _uid;
  _i_share := coalesce(_i_share, true);

  select coalesce(jsonb_agg(
    jsonb_build_object(
      ''user_id'', m.user_id,
      ''name'', coalesce(nullif(p.display_name, ''''), left(m.user_id::text, 8)),
      ''is_me'', m.user_id = _uid,
      ''status'',
        case
          when m.user_id = _uid then ''self''
          when not coalesce(us.share_activity, true) and not coalesce(al.alerted, false) then ''hidden''
          when coalesce(al.alerted, false) then ''alert''
          when bp.last_at is null then ''unknown''
          when bp.last_at > now() - interval ''6 hours'' then ''active''
          when bp.last_at > now() - interval ''24 hours'' then ''quiet''
          else ''silent''
        end,
      ''hours'',
        case
          when bp.last_at is null then null
          else floor(extract(epoch from (now() - bp.last_at)) / 3600)::int
        end,
      ''last_behavior_at'', bp.last_at,
      ''last_heartbeat_at'', ds.last_heartbeat_at,
      ''threshold_hours'', round(extract(epoch from private.silence_threshold(m.user_id)) / 3600.0, 2),
      ''alerted'', coalesce(al.alerted, false)
    )
    order by (m.user_id = _uid) desc, p.display_name nulls last, m.user_id
  ), ''[]''::jsonb) into _members
  from public.group_members m
  left join public.profiles p on p.id = m.user_id
  left join public.user_settings us on us.user_id = m.user_id
  left join public.device_state ds on ds.user_id = m.user_id
  left join lateral (
    select max(at) as last_at
    from public.behavior_pings
    where user_id = m.user_id
  ) bp on true
  left join lateral (
    select exists (
      select 1 from public.alerts a
      where a.user_id = m.user_id and a.status = ''open''
        and a.stage in (''group'', ''community'', ''terminal'')
    ) as alerted
  ) al on true
  where m.group_id = _group
    and m.status = ''active''
    and (
      _mode = ''group''
      or m.user_id = _uid
      or (_i_watching and m.monitored)
    );

  return jsonb_build_object(
    ''visibility'', case when _mode = ''watch'' then ''watchers_only'' else ''group_wide'' end,
    ''view'', _mode,
    ''is_owner'', _is_owner,
    ''i_share'', _i_share,
    ''members'', _members
  );
end;
$$;

revoke execute on function public.get_group_activity_view(uuid, text) from public, anon;
grant execute on function public.get_group_activity_view(uuid, text) to authenticated;"}', 'scoped_group_activity_views', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260627015542', '{"-- 把服务端真实沉默阈值 + 最后行为时间暴露给前端,
-- 让 Routine 的 \"Alert Threshold\" 卡显示真正会触发告警的值
-- (private.silence_threshold = user_activity_profiles.hourly_thresholds[hour],而非前端本地引擎的猜测)。
create or replace function public.my_routine_status()
returns jsonb language plpgsql security definer set search_path to '''' stable as $$
declare
  _uid uuid := auth.uid();
  _threshold interval;
  _last_at timestamptz;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  _threshold := private.silence_threshold(_uid);
  select max(at) into _last_at from public.behavior_pings where user_id = _uid;
  return jsonb_build_object(
    ''threshold_seconds'', extract(epoch from _threshold)::bigint,
    ''last_behavior_at'', _last_at
  );
end;
$$;
revoke execute on function public.my_routine_status() from public, anon;
grant execute on function public.my_routine_status() to authenticated;"}', 'my_routine_status', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260628060750', '{"-- Fix notification clearing from the client and reduce over-wide routine
-- threshold sensitivity scaling. Keep both changes additive/idempotent.

do $$
begin
  if not exists (
    select 1
      from pg_policies
     where schemaname = ''public''
       and tablename = ''notifications''
       and policyname = ''notifications_delete''
  ) then
    execute ''create policy notifications_delete
      on public.notifications
      for delete
      to authenticated
      using ((select auth.uid()) = recipient_id)'';
  end if;
end $$;

create or replace function private.silence_threshold(_user_id uuid)
returns interval language plpgsql security definer set search_path to '''' stable as $$
declare
  _s text;
  _timezone text;
  _threshold double precision;
  _multiplier double precision;
  _hour int;
  _is_weekend boolean;
  _floor double precision;
begin
  select sensitivity, timezone
    into _s, _timezone
    from public.user_settings
   where user_id = _user_id;

  _s := coalesce(_s, ''balanced'');
  _timezone := coalesce(_timezone, ''UTC'');
  _hour := extract(hour from now() at time zone _timezone)::int;

  select hourly_thresholds[_hour + 1], weekend_multiplier
    into _threshold, _multiplier
    from public.user_activity_profiles
   where user_id = _user_id;

  if _threshold is not null then
    _is_weekend := extract(isodow from now() at time zone _timezone) in (6, 7);
    if _is_weekend then
      _threshold := _threshold * coalesce(_multiplier, 1.0);
    end if;

    -- Sensitivity is a user-facing tool applied after the neutral model:
    -- sensitive ~= neutral + 30m; balanced = small buffer; relaxed = wider
    -- but still anchored to the learned usual behavior.
    if _s = ''high'' then
      _threshold := _threshold + 0.5;
      _floor := 1.0;
    elsif _s = ''low'' then
      _threshold := _threshold * 1.6 + 0.75;
      _floor := 3.0;
    else
      _threshold := _threshold * 1.15 + 0.25;
      _floor := 2.0;
    end if;

    _threshold := least(12.0, greatest(_floor, _threshold));
    return _threshold * interval ''1 hour'';
  end if;

  return case _s
    when ''high'' then interval ''1.5 hours''
    when ''low'' then interval ''6 hours''
    else interval ''3 hours''
  end;
end;
$$;"}', 'fix_notifications_clear_and_threshold_sensitivity', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260628060905', '{"drop policy if exists notifications_delete on public.notifications;

create policy notifications_delete
  on public.notifications
  for delete
  to authenticated
  using ((select auth.uid()) = recipient_id);"}', 'tighten_notifications_delete_policy_role', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260628061131', '{"-- Reduce threshold stacking after observing active users still getting overly
-- wide current-hour thresholds. Keep sensitivity additive and cap the broad
-- weekend multiplier so it cannot dominate every weekend hour.

create or replace function private.silence_threshold(_user_id uuid)
returns interval language plpgsql security definer set search_path to '''' stable as $$
declare
  _s text;
  _timezone text;
  _threshold double precision;
  _multiplier double precision;
  _hour int;
  _is_weekend boolean;
  _floor double precision;
begin
  select sensitivity, timezone
    into _s, _timezone
    from public.user_settings
   where user_id = _user_id;

  _s := coalesce(_s, ''balanced'');
  _timezone := coalesce(_timezone, ''UTC'');
  _hour := extract(hour from now() at time zone _timezone)::int;

  select hourly_thresholds[_hour + 1], weekend_multiplier
    into _threshold, _multiplier
    from public.user_activity_profiles
   where user_id = _user_id;

  if _threshold is not null then
    _is_weekend := extract(isodow from now() at time zone _timezone) in (6, 7);
    if _is_weekend then
      _threshold := _threshold * least(coalesce(_multiplier, 1.0), 1.10);
    end if;

    -- Sensitivity is a user-facing tool, not another model layer:
    -- sensitive ~= neutral + 15m; balanced +30m; relaxed +90m.
    if _s = ''high'' then
      _threshold := _threshold + 0.25;
      _floor := 1.0;
    elsif _s = ''low'' then
      _threshold := _threshold + 1.5;
      _floor := 3.0;
    else
      _threshold := _threshold + 0.5;
      _floor := 2.0;
    end if;

    _threshold := least(12.0, greatest(_floor, _threshold));
    return _threshold * interval ''1 hour'';
  end if;

  return case _s
    when ''high'' then interval ''1.5 hours''
    when ''low'' then interval ''6 hours''
    else interval ''3 hours''
  end;
end;
$$;"}', 'reduce_routine_threshold_stacking', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260628074256', '{"CREATE OR REPLACE FUNCTION private.silence_threshold(_user_id uuid)
 RETURNS interval
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''''
AS $function$
declare
  _s text;
  _timezone text;
  _threshold double precision;
  _multiplier double precision;
  _hour int;
  _is_weekend boolean;
  _floor double precision;
begin
  select sensitivity, timezone
    into _s, _timezone
    from public.user_settings
   where user_id = _user_id;

  _s := coalesce(_s, ''balanced'');
  _timezone := coalesce(_timezone, ''UTC'');
  _hour := extract(hour from now() at time zone _timezone)::int;

  select hourly_thresholds[_hour + 1], weekend_multiplier
    into _threshold, _multiplier
    from public.user_activity_profiles
   where user_id = _user_id;

  if _threshold is not null then
    _is_weekend := extract(isodow from now() at time zone _timezone) in (6, 7);
    if _is_weekend then
      _threshold := _threshold * least(coalesce(_multiplier, 1.0), 1.10);
    end if;

    -- Sensitivity is a user-facing tool, not another model layer:
    -- sensitive = the neutral model value as-is (+0m); balanced +45m; relaxed +90m.
    if _s = ''high'' then
      _threshold := _threshold + 0.0;
      _floor := 1.0;
    elsif _s = ''low'' then
      _threshold := _threshold + 1.5;
      _floor := 3.0;
    else
      _threshold := _threshold + 0.75;
      _floor := 2.0;
    end if;

    _threshold := least(12.0, greatest(_floor, _threshold));
    return _threshold * interval ''1 hour'';
  end if;

  return case _s
    when ''high'' then interval ''1.5 hours''
    when ''low'' then interval ''6 hours''
    else interval ''3 hours''
  end;
end;
$function$;"}', 'sensitivity_additive_0_45_90', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260628121907', '{"CREATE OR REPLACE FUNCTION private.is_in_sleep_window(_user_id uuid, _now timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''''
AS $function$
declare
  _start      time;
  _end        time;
  _timezone   text;
  _local_now  timestamptz;
  _local_time time;
  _local_date date;
  _start_ts   timestamptz;
  _end_ts     timestamptz;
  _dur        interval;
  _last_active    timestamptz;
  _dynamic_end    timestamptz;
begin
  select sleep_start_utc, sleep_end_utc, coalesce(timezone, ''UTC'')
    into _start, _end, _timezone
    from public.user_settings
   where user_id = _user_id;

  if _start is null or _end is null then
    return false;
  end if;

  -- Stored sleep_start_utc/sleep_end_utc are UTC times-of-day; convert to the
  -- user''s LOCAL time-of-day so the local-date anchoring below is correct.
  _start := (((current_date + _start) at time zone ''UTC'') at time zone _timezone)::time;
  _end   := (((current_date + _end)   at time zone ''UTC'') at time zone _timezone)::time;

  -- Convert _now into user''s local timezone (wall-clock)
  _local_now  := _now at time zone _timezone;
  _local_time := _local_now::time;
  _local_date := _local_now::date;

  -- Build start/end timestamps anchored to local date, handling overnight windows
  if _start > _end then
    -- Overnight (e.g. 23:00 -> 07:00)
    if _local_time < _end then
      _start_ts := (_local_date - 1 + _start) at time zone _timezone;
      _end_ts   := (_local_date     + _end  ) at time zone _timezone;
    else
      _start_ts := (_local_date     + _start) at time zone _timezone;
      _end_ts   := (_local_date + 1 + _end  ) at time zone _timezone;
    end if;
  else
    -- Same-day (e.g. 14:00 -> 16:00 nap)
    if _local_time < _start then
      _start_ts := (_local_date - 1 + _start) at time zone _timezone;
      _end_ts   := (_local_date - 1 + _end  ) at time zone _timezone;
    else
      _start_ts := (_local_date + _start) at time zone _timezone;
      _end_ts   := (_local_date + _end  ) at time zone _timezone;
    end if;
  end if;

  _dur := _end_ts - _start_ts;

  -- Dynamic extension: if user pinged shortly before sleep started
  select max(at) into _last_active
    from public.behavior_pings
   where user_id = _user_id;

  if _last_active is not null then
    if _last_active >= _start_ts - interval ''1 hour'' and _last_active <= _end_ts then
      _dynamic_end := least(_last_active + _dur, _end_ts + interval ''3 hours'');
      return _now >= _start_ts and _now < _dynamic_end;
    end if;
  end if;

  return _now >= _start_ts and _now < _end_ts;
end;
$function$;

CREATE OR REPLACE FUNCTION public.my_routine_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''''
AS $function$
declare
  _uid uuid := auth.uid();
  _threshold interval;
  _last_at timestamptz;
  _s text;
  _sleep_start time;
  _sleep_end time;
  _timezone text;
  _in_sleep_window boolean;
  _model_confidence double precision;
  _model_explanation text;
  _model_version text;
begin
  if _uid is null then raise exception ''not authenticated''; end if;

  select sensitivity, sleep_start_utc, sleep_end_utc, timezone
    into _s, _sleep_start, _sleep_end, _timezone
    from public.user_settings
   where user_id = _uid;

  -- Stored sleep times are UTC times-of-day; return them in the user''s local
  -- time-of-day so the UI label matches what the user actually set.
  _sleep_start := (((current_date + _sleep_start) at time zone ''UTC'') at time zone coalesce(_timezone, ''UTC''))::time;
  _sleep_end   := (((current_date + _sleep_end)   at time zone ''UTC'') at time zone coalesce(_timezone, ''UTC''))::time;

  select model_confidence, model_explanation, model_version
    into _model_confidence, _model_explanation, _model_version
    from public.user_activity_profiles
   where user_id = _uid;

  _threshold := private.silence_threshold(_uid);
  _in_sleep_window := private.is_in_sleep_window(_uid, now());

  select max(at)
    into _last_at
    from public.behavior_pings
   where user_id = _uid;

  return jsonb_build_object(
    ''threshold_seconds'', extract(epoch from _threshold)::bigint,
    ''last_behavior_at'', _last_at,
    ''sensitivity'', coalesce(_s, ''balanced''),
    ''sleep_start'', _sleep_start,
    ''sleep_end'', _sleep_end,
    ''timezone'', coalesce(_timezone, ''UTC''),
    ''in_sleep_window'', coalesce(_in_sleep_window, false),
    ''model_confidence'', _model_confidence,
    ''model_explanation'', _model_explanation,
    ''model_version'', _model_version
  );
end;
$function$;"}', 'fix_sleep_window_utc_to_local', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260629050030', '{"do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = ''supabase_realtime''
      and schemaname = ''public''
      and tablename = ''device_state''
  ) then
    alter publication supabase_realtime add table public.device_state;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = ''supabase_realtime''
      and schemaname = ''public''
      and tablename = ''behavior_pings''
  ) then
    alter publication supabase_realtime add table public.behavior_pings;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = ''supabase_realtime''
      and schemaname = ''public''
      and tablename = ''group_members''
  ) then
    alter publication supabase_realtime add table public.group_members;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = ''supabase_realtime''
      and schemaname = ''public''
      and tablename = ''community_members''
  ) then
    alter publication supabase_realtime add table public.community_members;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = ''supabase_realtime''
      and schemaname = ''public''
      and tablename = ''groups''
  ) then
    alter publication supabase_realtime add table public.groups;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = ''supabase_realtime''
      and schemaname = ''public''
      and tablename = ''communities''
  ) then
    alter publication supabase_realtime add table public.communities;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = ''supabase_realtime''
      and schemaname = ''public''
      and tablename = ''user_settings''
  ) then
    alter publication supabase_realtime add table public.user_settings;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = ''supabase_realtime''
      and schemaname = ''public''
      and tablename = ''profiles''
  ) then
    alter publication supabase_realtime add table public.profiles;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = ''supabase_realtime''
      and schemaname = ''public''
      and tablename = ''clients''
  ) then
    alter publication supabase_realtime add table public.clients;
  end if;
end $$;"}', 'realtime_status_lists', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260629050110', '{"do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = ''supabase_realtime''
      and schemaname = ''public''
      and tablename = ''notifications''
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = ''supabase_realtime''
      and schemaname = ''public''
      and tablename = ''alerts''
  ) then
    alter publication supabase_realtime add table public.alerts;
  end if;
end $$;"}', 'realtime_alert_notifications', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260705100343', '{"-- FCM device tokens for the native Android fast path (ADR-0004 Phase 2).
create table if not exists public.push_tokens (
  token text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  platform text not null default ''android'',
  updated_at timestamptz not null default now()
);

alter table public.push_tokens enable row level security;

create or replace function public.register_fcm_token(_token text, _platform text default ''android'')
returns void
language plpgsql
security definer
set search_path to ''''
as $$
begin
  if auth.uid() is null then
    raise exception ''not authenticated'';
  end if;
  if _token is null or length(_token) < 10 then
    return;
  end if;
  insert into public.push_tokens (token, user_id, platform, updated_at)
  values (_token, auth.uid(), coalesce(_platform, ''android''), now())
  on conflict (token) do update
    set user_id = excluded.user_id, updated_at = now();
end;
$$;

revoke execute on function public.register_fcm_token(text, text) from anon, public;
grant execute on function public.register_fcm_token(text, text) to authenticated;"}', 'fcm_push_tokens', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260705160307', '{"alter table public.alerts drop constraint alerts_cause_check;
alter table public.alerts add constraint alerts_cause_check
  check (cause = any (array[''silence''::text, ''dark_device''::text, ''sos''::text, ''concern''::text]));

create or replace function public.send_concern(_target uuid)
returns void
language plpgsql
security definer
set search_path to ''''
as $$
declare _uid uuid := auth.uid(); _name text; _aid uuid;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  if _uid = _target then raise exception ''bad target''; end if;
  if not private.shares_group_with(_target, _uid) and not private.is_guardian_of(_target, _uid) then
    raise exception ''forbidden'';
  end if;
  select coalesce(display_name, '''') into _name from public.profiles where id = _uid;

  select id into _aid from public.alerts where user_id = _target and status = ''open'' limit 1;
  if _aid is null then
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    values (_target, ''concern'', ''self'', now(), now() + interval ''30 minutes'')
    returning id into _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note)
    values (_aid, _uid, ''raised'', ''concern'');
  end if;

  insert into public.notifications (recipient_id, alert_id, kind, body, params)
  values (
    _target,
    _aid,
    ''concern'',
    coalesce(nullif(_name, ''''), ''有人'') || '' 在关心你，请打开 App 完成解锁报平安。'',
    jsonb_build_object(''name'', _name)
  );
  perform private.trigger_push_dispatch();
end;
$$;"}', 'concern_real_alert', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260715024733', '{"drop policy if exists emergency_info_select on public.emergency_info;

create policy emergency_info_select on public.emergency_info
  for select to authenticated
  using (
    (select auth.uid()) = user_id
    or (
      exists (
        select 1 from public.alerts a
        where a.user_id = emergency_info.user_id
          and a.status = ''open''
          and (a.stage = ''terminal'' or a.cause = ''sos'')
      )
      and (
        private.is_guardian_of(user_id, (select auth.uid()))
        or private.watches_user((select auth.uid()), emergency_info.user_id)
        or private.shares_community((select auth.uid()), emergency_info.user_id)
      )
    )
  );"}', 'tighten_emergency_reveal_terminal', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260715051159', '{"-- Migration: Add genuine activity source to behavior_pings and update process_checkin_tasks to query behavior_pings directly and use skip locked
-- ID: 20260715130000

-- 1) Add source column to behavior_pings
ALTER TABLE public.behavior_pings ADD COLUMN source text;

-- 2) Backfill existing rows to ''app''
UPDATE public.behavior_pings SET source = ''app'' WHERE source IS NULL;

-- 3) Add check constraint for valid source values
ALTER TABLE public.behavior_pings
  ADD CONSTRAINT behavior_pings_source_check CHECK (
    source IS NULL OR source IN (''installed_pwa'', ''tauri'', ''capacitor'', ''shortcut'', ''manual'', ''app'')
  );

-- 4) Replace process_checkin_tasks with direct behavior_pings queries and row claiming (SKIP LOCKED)
CREATE OR REPLACE FUNCTION public.process_checkin_tasks()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '''' AS $$
DECLARE
  t record;
  _done boolean;
  _wname text;
BEGIN
  -- 1) 到点：提醒承担者 (Claim rows using FOR UPDATE SKIP LOCKED to prevent concurrent cron double-firing)
  FOR t IN 
    SELECT * FROM public.checkin_tasks
    WHERE status = ''active'' AND cycle_state = ''idle''
      AND next_due_at IS NOT NULL AND next_due_at <= now()
      AND NOT private.sleep_relaxed(t.ward_id, now())
    FOR UPDATE SKIP LOCKED
  LOOP
    INSERT INTO public.notifications (recipient_id, kind, body, params)
    VALUES (t.ward_id, ''task_due'', ''到点报平安啦，点开 App 完成确认。'',
            jsonb_build_object(''label'', t.label));
            
    UPDATE public.checkin_tasks 
    SET cycle_state = ''due_notified'', updated_at = now() 
    WHERE id = t.id;
  END LOOP;

  -- 2) 宽限到期：心跳判定完成与否；漏卡 → 通知设置者(自设则通知守护人/同组守望者)
  -- (Claim rows using FOR UPDATE SKIP LOCKED to prevent concurrent cron double-firing)
  FOR t IN 
    SELECT * FROM public.checkin_tasks
    WHERE status = ''active'' AND cycle_state = ''due_notified''
      AND next_due_at + make_interval(mins => t.grace_minutes) <= now()
      AND NOT private.sleep_relaxed(t.ward_id, now())
    FOR UPDATE SKIP LOCKED
  LOOP
    -- Judge completion by REAL activity in behavior_pings (exists a behavior_pings row for ward_id with at >= next_due_at), NOT device_state.
    SELECT EXISTS (
      SELECT 1 FROM public.behavior_pings bp
      WHERE bp.user_id = t.ward_id AND bp.at >= t.next_due_at
    ) INTO _done;

    IF NOT _done THEN
      SELECT coalesce(display_name, '''') INTO _wname FROM public.profiles WHERE id = t.ward_id;
      
      INSERT INTO public.notifications (recipient_id, kind, body, params)
      SELECT DISTINCT r.uid, ''task_missed'',
        _wname || '' 未完成定时报平安，请关注。'',
        jsonb_build_object(''name'', _wname, ''label'', t.label)
      FROM (
        SELECT t.created_by AS uid WHERE t.created_by <> t.ward_id
        UNION
        SELECT g.guardian_id FROM public.guardianships g
          WHERE t.created_by = t.ward_id AND g.ward_id = t.ward_id AND g.status = ''active''
        UNION
        SELECT w.user_id FROM public.group_members gm
          JOIN public.group_members w ON w.group_id = gm.group_id
          WHERE t.created_by = t.ward_id
            AND gm.user_id = t.ward_id AND gm.monitored AND gm.status = ''active''
            AND w.watching AND w.status = ''active'' AND w.user_id <> t.ward_id
            AND NOT EXISTS (SELECT 1 FROM public.guardianships g2
                            WHERE g2.ward_id = t.ward_id AND g2.status = ''active'')
      ) r;
    END IF;

    -- 滚动下一轮（漏卡也滚动，避免重复轰炸；daily 跳到未来最近一个周期）
    UPDATE public.checkin_tasks SET
      cycle_state = ''idle'',
      next_due_at = CASE
        WHEN kind = ''interval'' THEN now() + make_interval(hours => interval_hours)
        ELSE next_due_at + make_interval(days => (ceil(extract(epoch from (now() - next_due_at)) / 86400.0))::int)
      END,
      updated_at = now()
      WHERE id = t.id;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.process_checkin_tasks() FROM public, anon, authenticated;"}', 'f1_genuine_activity_source', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260715131010', '{"-- Migration: Add push delivery lease columns and atomic claim/finalize RPCs

-- 1. Add delivery-state columns to notifications table
ALTER TABLE public.notifications
  ADD COLUMN delivery_attempts integer NOT NULL DEFAULT 0,
  ADD COLUMN delivery_lease_expiry timestamp with time zone DEFAULT NULL,
  ADD COLUMN delivery_outcome text DEFAULT NULL CHECK (delivery_outcome IN (''sent'', ''no_target'', ''failed''));

-- 2. Create index to optimize claiming unpushed notifications
CREATE INDEX notifications_delivery_claim_idx ON public.notifications (created_at)
  WHERE pushed_at IS NULL AND delivery_attempts < 5;

-- 3. Define RPC to claim unpushed notifications atomically
CREATE OR REPLACE FUNCTION public.claim_unpushed_notifications(
  p_batch_size integer,
  p_lease_duration interval
)
RETURNS TABLE (
  id uuid,
  recipient_id uuid,
  kind text,
  body text,
  params jsonb,
  alert_id uuid,
  delivery_attempts integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''''
AS $$
BEGIN
  RETURN QUERY
  WITH target_rows AS (
    SELECT n.id
    FROM public.notifications n
    WHERE n.pushed_at IS NULL
      AND n.created_at > (now() - interval ''24 hours'')
      AND (n.delivery_lease_expiry IS NULL OR n.delivery_lease_expiry < now())
      AND n.delivery_attempts < 5
    ORDER BY n.created_at ASC
    LIMIT p_batch_size
    FOR UPDATE SKIP LOCKED
  )
  UPDATE public.notifications n
  SET 
    delivery_lease_expiry = now() + p_lease_duration,
    delivery_attempts = n.delivery_attempts + 1
  FROM target_rows t
  WHERE n.id = t.id
  RETURNING 
    n.id,
    n.recipient_id,
    n.kind,
    n.body,
    n.params,
    n.alert_id,
    n.delivery_attempts;
END;
$$;

-- 4. Define RPC to finalize delivery outcome per notification
CREATE OR REPLACE FUNCTION public.finalize_notification_delivery(
  p_notification_id uuid,
  p_outcome text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''''
AS $$
DECLARE
  v_attempts integer;
BEGIN
  -- Validate outcome input
  IF p_outcome NOT IN (''sent'', ''no_target'', ''retry'') THEN
    RAISE EXCEPTION ''Invalid outcome: %'', p_outcome;
  END IF;

  SELECT n.delivery_attempts INTO v_attempts
  FROM public.notifications n
  WHERE n.id = p_notification_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION ''Notification not found: %'', p_notification_id;
  END IF;

  IF p_outcome = ''sent'' THEN
    UPDATE public.notifications
    SET 
      pushed_at = now(),
      delivery_outcome = ''sent'',
      delivery_lease_expiry = NULL
    WHERE id = p_notification_id;
  ELSIF p_outcome = ''no_target'' THEN
    UPDATE public.notifications
    SET 
      pushed_at = now(),
      delivery_outcome = ''no_target'',
      delivery_lease_expiry = NULL
    WHERE id = p_notification_id;
  ELSIF p_outcome = ''retry'' THEN
    -- If we hit the max attempt count (5), mark it terminal ''failed'' so it stops looping
    IF v_attempts >= 5 THEN
      UPDATE public.notifications
      SET 
        pushed_at = now(),
        delivery_outcome = ''failed'',
        delivery_lease_expiry = NULL
      WHERE id = p_notification_id;
    ELSE
      -- Clear the lease so it is immediately eligible for retry on the next cron run
      UPDATE public.notifications
      SET 
        delivery_lease_expiry = NULL
      WHERE id = p_notification_id;
    END IF;
  END IF;
END;
$$;

-- 5. Revoke execute permission from public roles and grant to service_role only
REVOKE EXECUTE ON FUNCTION public.claim_unpushed_notifications(integer, interval) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_unpushed_notifications(integer, interval) TO service_role;

REVOKE EXECUTE ON FUNCTION public.finalize_notification_delivery(uuid, text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_notification_delivery(uuid, text) TO service_role;"}', 'push_delivery_leases', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260716021236', '{"-- Migration: Add sleep_start_local and sleep_end_local columns, backfill from UTC columns, and update functions to use local sleep columns
-- ID: 20260716120000

-- 1) Add local columns to public.user_settings
ALTER TABLE public.user_settings ADD COLUMN sleep_start_local time DEFAULT NULL;
ALTER TABLE public.user_settings ADD COLUMN sleep_end_local time DEFAULT NULL;

-- 2) Backfill existing rows using current_date (behavior-preserving at migration time)
UPDATE public.user_settings
SET 
  sleep_start_local = CASE 
    WHEN sleep_start_utc IS NOT NULL THEN (((current_date + sleep_start_utc) at time zone ''UTC'') at time zone coalesce(timezone, ''UTC''))::time 
    ELSE NULL 
  END,
  sleep_end_local = CASE 
    WHEN sleep_end_utc IS NOT NULL THEN (((current_date + sleep_end_utc) at time zone ''UTC'') at time zone coalesce(timezone, ''UTC''))::time 
    ELSE NULL 
  END
WHERE sleep_start_utc IS NOT NULL OR sleep_end_utc IS NOT NULL;

-- 3) Rewrite private.is_in_sleep_window to read sleep_start_local, sleep_end_local and delete conversion lines
CREATE OR REPLACE FUNCTION private.is_in_sleep_window(_user_id uuid, _now timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''''
AS $function$
declare
  _start      time;
  _end        time;
  _timezone   text;
  _local_now  timestamptz;
  _local_time time;
  _local_date date;
  _start_ts   timestamptz;
  _end_ts     timestamptz;
  _dur        interval;
  _last_active    timestamptz;
  _dynamic_end    timestamptz;
begin
  select sleep_start_local, sleep_end_local, coalesce(timezone, ''UTC'')
    into _start, _end, _timezone
    from public.user_settings
   where user_id = _user_id;

  if _start is null or _end is null then
    return false;
  end if;

  -- Convert _now into user''s local timezone (wall-clock)
  _local_now  := _now at time zone _timezone;
  _local_time := _local_now::time;
  _local_date := _local_now::date;

  -- Build start/end timestamps anchored to local date, handling overnight windows
  if _start > _end then
    -- Overnight (e.g. 23:00 -> 07:00)
    if _local_time < _end then
      _start_ts := (_local_date - 1 + _start) at time zone _timezone;
      _end_ts   := (_local_date     + _end  ) at time zone _timezone;
    else
      _start_ts := (_local_date     + _start) at time zone _timezone;
      _end_ts   := (_local_date + 1 + _end  ) at time zone _timezone;
    end if;
  else
    -- Same-day (e.g. 14:00 -> 16:00 nap)
    if _local_time < _start then
      _start_ts := (_local_date - 1 + _start) at time zone _timezone;
      _end_ts   := (_local_date - 1 + _end  ) at time zone _timezone;
    else
      _start_ts := (_local_date + _start) at time zone _timezone;
      _end_ts   := (_local_date + _end  ) at time zone _timezone;
    end if;
  end if;

  _dur := _end_ts - _start_ts;

  -- Dynamic extension: if user pinged shortly before sleep started
  select max(at) into _last_active
    from public.behavior_pings
   where user_id = _user_id;

  if _last_active is not null then
    if _last_active >= _start_ts - interval ''1 hour'' and _last_active <= _end_ts then
      _dynamic_end := least(_last_active + _dur, _end_ts + interval ''3 hours'');
      return _now >= _start_ts and _now < _dynamic_end;
    end if;
  end if;

  return _now >= _start_ts and _now < _end_ts;
end; $function$;

-- 4) Rewrite public.my_routine_status to read sleep_start_local, sleep_end_local and delete conversion lines
CREATE OR REPLACE FUNCTION public.my_routine_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''''
AS $function$
declare
  _uid uuid := auth.uid();
  _threshold interval;
  _last_at timestamptz;
  _s text;
  _sleep_start time;
  _sleep_end time;
  _timezone text;
  _in_sleep_window boolean;
  _model_confidence double precision;
  _model_explanation text;
  _model_version text;
begin
  if _uid is null then raise exception ''not authenticated''; end if;

  select sensitivity, sleep_start_local, sleep_end_local, timezone
    into _s, _sleep_start, _sleep_end, _timezone
    from public.user_settings
   where user_id = _uid;

  select model_confidence, model_explanation, model_version
    into _model_confidence, _model_explanation, _model_version
    from public.user_activity_profiles
   where user_id = _uid;

  _threshold := private.silence_threshold(_uid);
  _in_sleep_window := private.is_in_sleep_window(_uid, now());

  select max(at)
    into _last_at
    from public.behavior_pings
   where user_id = _uid;

  return jsonb_build_object(
    ''threshold_seconds'', extract(epoch from _threshold)::bigint,
    ''last_behavior_at'', _last_at,
    ''sensitivity'', coalesce(_s, ''balanced''),
    ''sleep_start'', _sleep_start,
    ''sleep_end'', _sleep_end,
    ''timezone'', coalesce(_timezone, ''UTC''),
    ''in_sleep_window'', coalesce(_in_sleep_window, false),
    ''model_confidence'', _model_confidence,
    ''model_explanation'', _model_explanation,
    ''model_version'', _model_version
  );
end; $function$;

-- 5) Rewrite private.sleep_relaxed in local tod with 2-hour post-wake grace
-- (parameter stays `_user` — CREATE OR REPLACE cannot rename the deployed function''s parameter)
CREATE OR REPLACE FUNCTION private.sleep_relaxed(_user uuid, _at timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''''
AS $function$
declare
  _start      time;
  _end        time;
  _timezone   text;
  _local_now  timestamptz;
  _local_time time;
  _local_date date;
  _start_ts   timestamptz;
  _end_ts     timestamptz;
  _wake_ts    timestamptz;
begin
  select sleep_start_local, sleep_end_local, coalesce(timezone, ''UTC'')
    into _start, _end, _timezone
    from public.user_settings
   where user_id = _user;

  if _start is null or _end is null then
    return false;
  end if;

  -- Convert _at to user''s local timezone (wall-clock)
  _local_now  := _at at time zone _timezone;
  _local_time := _local_now::time;
  _local_date := _local_now::date;

  -- Build start/end timestamps anchored to local date, handling overnight windows
  if _start > _end then
    -- Overnight (e.g. 23:00 -> 07:00)
    if _local_time < _end then
      _start_ts := (_local_date - 1 + _start) at time zone _timezone;
      _end_ts   := (_local_date     + _end  ) at time zone _timezone;
    else
      _start_ts := (_local_date     + _start) at time zone _timezone;
      _end_ts   := (_local_date + 1 + _end  ) at time zone _timezone;
    end if;
  else
    -- Same-day (e.g. 14:00 -> 16:00 nap)
    if _local_time < _start then
      _start_ts := (_local_date - 1 + _start) at time zone _timezone;
      _end_ts   := (_local_date - 1 + _end  ) at time zone _timezone;
    else
      _start_ts := (_local_date + _start) at time zone _timezone;
      _end_ts   := (_local_date + _end  ) at time zone _timezone;
    end if;
  end if;

  -- If currently inside the sleep window
  if _at >= _start_ts and _at < _end_ts then
    return true;
  end if;

  -- Check 2-hour post-wake grace period
  _wake_ts := (_local_date + _end) at time zone _timezone;
  if _wake_ts > _at then
    _wake_ts := _wake_ts - interval ''1 day'';
  end if;

  if _at >= _wake_ts and _at - _wake_ts < interval ''2 hours'' then
    return true;
  end if;

  return false;
end; $function$;

-- 6) Rewrite set_sleep_window: store directly, add _tz parameter, and update timezone
DROP FUNCTION IF EXISTS public.set_sleep_window(time, time);
CREATE OR REPLACE FUNCTION public.set_sleep_window(
  _start time DEFAULT NULL,
  _end time DEFAULT NULL,
  _tz text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''''
AS $$
declare
  _uid uuid := auth.uid();
  _existing_tz text;
begin
  if _uid is null then
    raise exception ''not authenticated'';
  end if;

  -- TRANSITION SHIM: Pre-wall-clock clients never send _tz. If they set a window,
  -- they send UTC time-of-day digits. We convert these to local digits using their stored timezone.
  -- This shim should be removed in a future ADR once old clients age out.
  if _tz is null and _start is not null and _end is not null then
    select timezone into _existing_tz from public.user_settings where user_id = _uid;
    _start := (((current_date + _start) at time zone ''UTC'') at time zone coalesce(_existing_tz, ''UTC''))::time;
    _end   := (((current_date + _end)   at time zone ''UTC'') at time zone coalesce(_existing_tz, ''UTC''))::time;
  end if;

  insert into public.user_settings (user_id, sleep_start_local, sleep_end_local, timezone, updated_at)
  values (_uid, _start, _end, coalesce(_tz, ''UTC''), now())
  on conflict (user_id) do update
    set sleep_start_local = excluded.sleep_start_local,
        sleep_end_local = excluded.sleep_end_local,
        timezone = case when _tz is not null then excluded.timezone else user_settings.timezone end,
        updated_at = now();
end;
$$;

REVOKE EXECUTE ON FUNCTION public.set_sleep_window(time, time, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.set_sleep_window(time, time, text) TO authenticated;"}', 'use_local_sleep_columns', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260717124306', '{"-- Migration: Support daily tasks anchored to wall clock time (due_time_local)
-- ID: 20260717124306

-- 1) Add due_time_local column to public.checkin_tasks
ALTER TABLE public.checkin_tasks ADD COLUMN due_time_local time DEFAULT NULL;

-- 2) Backfill existing daily rows using current_date and the ward''s current timezone.
-- Note: When backfilling due_time_local from due_time_utc for existing daily tasks, we interpret the stored due_time_utc
-- as a UTC time on the current migration date and convert it using the ward''s current timezone setting (defaulting to ''UTC'').
-- If a ward has changed their timezone since the task was originally entered, this backfilled value may differ from the
-- user''s original local intent. This is a best-effort historical approximation.
UPDATE public.checkin_tasks t
SET due_time_local = (((current_date + t.due_time_utc) at time zone ''UTC'') at time zone coalesce(
  (SELECT timezone FROM public.user_settings s WHERE s.user_id = t.ward_id),
  ''UTC''
))::time
WHERE t.kind = ''daily'' AND t.due_time_utc IS NOT NULL;

-- 3) Drop the exact old create_checkin_task and update_checkin_task signatures before creating the new 8-argument signatures
DROP FUNCTION IF EXISTS public.create_checkin_task(uuid, text, time, int, timestamptz, int, text);
DROP FUNCTION IF EXISTS public.update_checkin_task(uuid, text, time, int, timestamptz, int, text);

-- 4) Create the new create_checkin_task signature with _due_time_local
CREATE OR REPLACE FUNCTION public.create_checkin_task(
  _ward uuid,
  _kind text,
  _due_time_utc time default null,
  _due_time_local time default null,
  _interval_hours int default null,
  _first_due timestamptz default null,
  _grace int default 30,
  _label text default ''''
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '''' AS $$
DECLARE
  _uid uuid := auth.uid();
  _id uuid;
  _self boolean;
  _name text;
  _timezone text;
  _local_date date;
  _next_due timestamptz;
BEGIN
  if _uid is null then raise exception ''not authenticated''; end if;
  _self := (_uid = _ward);
  if not _self and not private.is_guardian_of(_ward, _uid) then
    raise exception ''only the person or their guardian can create tasks'';
  end if;

  _timezone := null;
  select timezone into _timezone from public.user_settings where user_id = _ward;
  _timezone := coalesce(_timezone, ''UTC'');
  _local_date := (now() at time zone _timezone)::date;

  if _kind = ''daily'' then
    -- TRANSITION SHIM: Pre-wall-clock clients never send _due_time_local.
    -- Derive it from _due_time_utc.
    if _due_time_local is null and _due_time_utc is not null then
      _due_time_local := (((_local_date + _due_time_utc) at time zone ''UTC'') at time zone _timezone)::time;
    elsif _due_time_local is not null then
      _due_time_utc := (((_local_date + _due_time_local) at time zone _timezone) at time zone ''UTC'')::time;
    end if;

    if _self then
      _next_due := (_local_date + _due_time_local) at time zone _timezone;
      if _next_due <= now() then
        _next_due := (_local_date + 1 + _due_time_local) at time zone _timezone;
      end if;
    end if;
  else
    if _self then
      _next_due := coalesce(_first_due, now() + make_interval(hours => _interval_hours));
    end if;
  end if;

  insert into public.checkin_tasks
    (ward_id, created_by, kind, due_time_utc, due_time_local, interval_hours, grace_minutes, label,
     status, next_due_at)
  values
    (_ward, _uid, _kind, _due_time_utc, _due_time_local, _interval_hours,
     coalesce(_grace, 30), coalesce(_label, ''''),
     case when _self then ''active'' else ''pending'' end,
     _next_due)
  returning id into _id;

  if not _self then
    select coalesce(display_name, '''') into _name from public.profiles where id = _uid;
    insert into public.notifications (recipient_id, kind, body, params)
    values (_ward, ''task_invite'',
      _name || '' 为你设置了报平安任务，请确认是否接受。'',
      jsonb_build_object(''name'', _name, ''label'', coalesce(_label, '''')));
  end if;
  return _id;
end;
$$;

-- 5) Create the new update_checkin_task signature with _due_time_local
CREATE OR REPLACE FUNCTION public.update_checkin_task(
  _task uuid,
  _kind text,
  _due_time_utc time default null,
  _due_time_local time default null,
  _interval_hours int default null,
  _first_due timestamptz default null,
  _grace int default 30,
  _label text default ''''
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '''' AS $$
DECLARE
  _uid uuid := auth.uid();
  _ward uuid;
  _timezone text;
  _local_date date;
  _next_due timestamptz;
BEGIN
  if _uid is null then raise exception ''not authenticated''; end if;
  if _kind not in (''daily'', ''interval'') then raise exception ''bad kind''; end if;

  select ward_id into _ward from public.checkin_tasks
  where id = _task and created_by = _uid and status in (''pending'', ''active'', ''declined'');
  if _ward is null then raise exception ''task not found''; end if;

  _timezone := null;
  select timezone into _timezone from public.user_settings where user_id = _ward;
  _timezone := coalesce(_timezone, ''UTC'');
  _local_date := (now() at time zone _timezone)::date;

  if _kind = ''daily'' then
    -- TRANSITION SHIM: Pre-wall-clock clients never send _due_time_local.
    -- Derive it from _due_time_utc.
    if _due_time_local is null and _due_time_utc is not null then
      _due_time_local := (((_local_date + _due_time_utc) at time zone ''UTC'') at time zone _timezone)::time;
    elsif _due_time_local is not null then
      _due_time_utc := (((_local_date + _due_time_local) at time zone _timezone) at time zone ''UTC'')::time;
    end if;

    _next_due := (_local_date + _due_time_local) at time zone _timezone;
    if _next_due <= now() then
      _next_due := (_local_date + 1 + _due_time_local) at time zone _timezone;
    end if;
  else
    _next_due := coalesce(_first_due, now() + make_interval(hours => _interval_hours));
  end if;

  update public.checkin_tasks t
  set kind = _kind,
      due_time_utc = case when _kind = ''daily'' then _due_time_utc else null end,
      due_time_local = case when _kind = ''daily'' then _due_time_local else null end,
      interval_hours = case when _kind = ''interval'' then _interval_hours else null end,
      grace_minutes = coalesce(_grace, 30),
      label = coalesce(_label, ''''),
      cycle_state = ''idle'',
      next_due_at = _next_due,
      status = case when status = ''declined'' then ''pending'' else status end,
      updated_at = now()
  where t.id = _task and t.created_by = _uid and t.status in (''pending'', ''active'', ''declined'');

  insert into public.notifications (recipient_id, kind, body, params)
  values (_ward, ''task_updated'', ''你的报平安任务已被修改，请留意新的时间安排。'',
          jsonb_build_object(''label'', coalesce(_label, '''')));
end;
$$;

-- 6) Revoke/grant EXECUTE on the new 8-argument signatures
revoke execute on function public.create_checkin_task(uuid, text, time, time, int, timestamptz, int, text) from public, anon;
revoke execute on function public.update_checkin_task(uuid, text, time, time, int, timestamptz, int, text) from public, anon;
grant execute on function public.create_checkin_task(uuid, text, time, time, int, timestamptz, int, text) to authenticated;
grant execute on function public.update_checkin_task(uuid, text, time, time, int, timestamptz, int, text) to authenticated;

-- 7) Recreate respond_checkin_task (ignore _first_due for daily and compute server-side)
CREATE OR REPLACE FUNCTION public.respond_checkin_task(
  _task uuid,
  _accept boolean,
  _first_due timestamptz default null
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '''' AS $$
DECLARE
  _uid uuid := auth.uid();
  _t public.checkin_tasks;
  _name text;
  _timezone text;
  _local_date date;
  _next_due timestamptz;
BEGIN
  if _uid is null then raise exception ''not authenticated''; end if;
  select * into _t from public.checkin_tasks where id = _task and ward_id = _uid and status = ''pending'';
  if not found then raise exception ''task not found or not pending''; end if;

  if _accept then
    if _t.kind = ''daily'' then
      _timezone := null;
      select timezone into _timezone from public.user_settings where user_id = _uid;
      _timezone := coalesce(_timezone, ''UTC'');
      _local_date := (now() at time zone _timezone)::date;
      _next_due := (_local_date + _t.due_time_local) at time zone _timezone;
      if _next_due <= now() then
        _next_due := (_local_date + 1 + _t.due_time_local) at time zone _timezone;
      end if;
    else
      _next_due := coalesce(_first_due, now() + make_interval(hours => _t.interval_hours));
    end if;
  end if;

  update public.checkin_tasks
    set status = case when _accept then ''active'' else ''declined'' end,
        next_due_at = _next_due,
        updated_at = now()
    where id = _task;

  select coalesce(display_name, '''') into _name from public.profiles where id = _uid;
  insert into public.notifications (recipient_id, kind, body, params)
  values (_t.created_by,
    case when _accept then ''task_accepted'' else ''task_declined'' end,
    _name || case when _accept then '' 接受了报平安任务。'' else '' 拒绝了报平安任务。'' end,
    jsonb_build_object(''name'', _name, ''label'', _t.label));
END;
$$;

revoke execute on function public.respond_checkin_task(uuid, boolean, timestamptz) from public, anon;
grant execute on function public.respond_checkin_task(uuid, boolean, timestamptz) to authenticated;

-- 8) Recreate process_checkin_tasks preserving critical F1 invariants
CREATE OR REPLACE FUNCTION public.process_checkin_tasks()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '''' AS $$
DECLARE
  t record;
  _done boolean;
  _wname text;
  _timezone text;
  _local_date date;
  _candidate timestamptz;
BEGIN
  -- 1) 到点：提醒承担者 (Claim rows using FOR UPDATE SKIP LOCKED to prevent concurrent cron double-firing)
  FOR t IN
    SELECT * FROM public.checkin_tasks ct
    WHERE status = ''active'' AND cycle_state = ''idle''
      AND next_due_at IS NOT NULL AND next_due_at <= now()
      AND NOT private.sleep_relaxed(ct.ward_id, now())
    FOR UPDATE SKIP LOCKED
  LOOP
    INSERT INTO public.notifications (recipient_id, kind, body, params)
    VALUES (t.ward_id, ''task_due'', ''到点报平安啦，点开 App 完成确认。'',
            jsonb_build_object(''label'', t.label));

    UPDATE public.checkin_tasks
    SET cycle_state = ''due_notified'', updated_at = now()
    WHERE id = t.id;
  END LOOP;

  -- 2) 宽限到期：心跳判定完成与否；漏卡 → 通知设置者(自设则通知守护人/同组守望者)
  -- (Claim rows using FOR UPDATE SKIP LOCKED to prevent concurrent cron double-firing)
  FOR t IN
    SELECT * FROM public.checkin_tasks ct
    WHERE status = ''active'' AND cycle_state = ''due_notified''
      AND next_due_at + make_interval(mins => ct.grace_minutes) <= now()
      AND NOT private.sleep_relaxed(ct.ward_id, now())
    FOR UPDATE SKIP LOCKED
  LOOP
    -- Judge completion by REAL activity in behavior_pings (exists a behavior_pings row for ward_id with at >= next_due_at), NOT device_state.
    SELECT EXISTS (
      SELECT 1 FROM public.behavior_pings bp
      WHERE bp.user_id = t.ward_id AND bp.at >= t.next_due_at
    ) INTO _done;

    IF NOT _done THEN
      SELECT coalesce(display_name, '''') INTO _wname FROM public.profiles WHERE id = t.ward_id;

      INSERT INTO public.notifications (recipient_id, kind, body, params)
      SELECT DISTINCT r.uid, ''task_missed'',
        _wname || '' 未完成定时报平安，请关注。'',
        jsonb_build_object(''name'', _wname, ''label'', t.label)
      FROM (
        SELECT t.created_by AS uid WHERE t.created_by <> t.ward_id
        UNION
        SELECT g.guardian_id FROM public.guardianships g
          WHERE t.created_by = t.ward_id AND g.ward_id = t.ward_id AND g.status = ''active''
        UNION
        SELECT w.user_id FROM public.group_members gm
          JOIN public.group_members w ON w.group_id = gm.group_id
          WHERE t.created_by = t.ward_id
            AND gm.user_id = t.ward_id AND gm.monitored AND gm.status = ''active''
            AND w.watching AND w.status = ''active'' AND w.user_id <> t.ward_id
            AND NOT EXISTS (SELECT 1 FROM public.guardianships g2
                            WHERE g2.ward_id = t.ward_id AND g2.status = ''active'')
      ) r;
    END IF;

    -- 滚动下一轮（漏卡也滚动，避免重复轰炸；daily 跳到未来最近一个周期）
    IF t.kind = ''daily'' THEN
      _timezone := null;
      SELECT timezone INTO _timezone FROM public.user_settings WHERE user_id = t.ward_id;
      _timezone := coalesce(_timezone, ''UTC'');
      _local_date := (now() at time zone _timezone)::date;
      _candidate := (_local_date + t.due_time_local) at time zone _timezone;
      WHILE _candidate <= now() OR _candidate <= t.next_due_at LOOP
        _local_date := _local_date + 1;
        _candidate := (_local_date + t.due_time_local) at time zone _timezone;
      END LOOP;
    ELSE
      _candidate := now() + make_interval(hours => t.interval_hours);
    END IF;

    UPDATE public.checkin_tasks SET
      cycle_state = ''idle'',
      next_due_at = _candidate,
      updated_at = now()
      WHERE id = t.id;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.process_checkin_tasks() FROM public, anon, authenticated;"}', 'checkin_task_wall_clock', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260719015302', '{"-- Migration: ADR-0021 Gate 1 Containment

-- Note: The ADR''s alert-created-at concept maps to alerts.opened_at (created_at search text)
-- Validation checks: event observed_at and received_at drift must be <= 5m, and >= alert created_at

-- 1) behavior_pings: add received_at timestamptz, ingest_version smallint, event_id uuid.
-- Existing rows backfill received_at=at, ingest_version=1, event_id=NULL.
-- Server defaults safe; all new accepted writes go through private shared validator assigning received_at=clock_timestamp() and ingest_version=2.
-- Partial UNIQUE(user_id,event_id) WHERE event_id IS NOT NULL.
ALTER TABLE public.behavior_pings ADD COLUMN IF NOT EXISTS received_at timestamptz","ALTER TABLE public.behavior_pings ADD COLUMN IF NOT EXISTS ingest_version smallint","ALTER TABLE public.behavior_pings ADD COLUMN IF NOT EXISTS event_id uuid","UPDATE public.behavior_pings
SET received_at = coalesce(received_at, at),
    ingest_version = coalesce(ingest_version, 1)
WHERE received_at IS NULL OR ingest_version IS NULL","ALTER TABLE public.behavior_pings ALTER COLUMN received_at SET NOT NULL","ALTER TABLE public.behavior_pings ALTER COLUMN received_at SET DEFAULT now()","ALTER TABLE public.behavior_pings ALTER COLUMN ingest_version SET NOT NULL","ALTER TABLE public.behavior_pings ALTER COLUMN ingest_version SET DEFAULT 1","-- Partial UNIQUE(user_id,event_id) WHERE event_id IS NOT NULL.
CREATE UNIQUE INDEX IF NOT EXISTS behavior_pings_event_id_uidx ON public.behavior_pings (user_id, event_id) WHERE event_id IS NOT NULL","-- 2) REVOKE direct INSERT from PUBLIC, anon, authenticated.
-- Note: Static test looks for exact text:
-- REVOKE INSERT ON TABLE public.behavior_pings FROM authenticated
REVOKE INSERT ON TABLE public.behavior_pings FROM PUBLIC","REVOKE INSERT ON TABLE public.behavior_pings FROM anon","REVOKE INSERT ON TABLE public.behavior_pings FROM authenticated","DROP POLICY IF EXISTS behavior_pings_insert ON public.behavior_pings","-- 3) One private shared liveness side-effects helper
CREATE OR REPLACE FUNCTION private.apply_liveness_side_effects(
  _user_id uuid,
  _observed_at timestamptz,
  _received_at timestamptz
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '''' AS $$
DECLARE
  _stale record;
  _triggered boolean := false;
BEGIN
  -- Update device_state:
  INSERT INTO public.device_state (user_id, status, last_heartbeat_at, updated_at)
  VALUES (_user_id, ''normal'', _received_at, now())
  ON CONFLICT (user_id) DO UPDATE
    SET status = ''normal'',
        last_heartbeat_at = greatest(device_state.last_heartbeat_at, excluded.last_heartbeat_at),
        updated_at = now();

  -- Resolve alerts:
  -- Any trigger/side effects must apply the live qualification above, and active alert resolution must require both received_at and observed_at >= alerts.opened_at.
  -- Note: The ADR''s alert-created-at concept maps to alerts.opened_at (created_at search text)
  FOR _stale IN
    SELECT id, opened_at FROM public.alerts
    WHERE user_id = _user_id
      AND status = ''open''
      AND cause in (''silence'', ''dark_device'')
      AND _received_at >= opened_at
      AND _observed_at >= opened_at
  LOOP
    UPDATE public.alerts
      SET status = ''resolved'', resolved_at = _received_at, resolved_by = _user_id, updated_at = now()
      WHERE id = _stale.id;

    INSERT INTO public.alert_events (alert_id, actor_id, kind)
    VALUES (_stale.id, _user_id, ''auto_resolved'');

    DELETE FROM public.notifications WHERE alert_id = _stale.id;
    _triggered := true;
  END LOOP;

  -- Clear user self check-in nudges
  IF NOT (auth.uid() IS NOT NULL AND auth.uid() <> _user_id) THEN
    DELETE FROM public.notifications
      WHERE recipient_id = _user_id
        AND kind in (''self'', ''concern'');
  END IF;

  IF _triggered THEN
    PERFORM private.trigger_push_dispatch();
  END IF;
END;
$$","-- 4) One private shared insertion function, SECURITY DEFINER SET search_path='''', fully qualified names.
-- Validate UUID/observed/source/kind; allowed sources match app: installed_pwa,tauri,capacitor,shortcut,manual,app; allowed kinds match actual app schema.
-- Duplicate event_id => ''duplicate''. Future observed_at > server now+5m => ''invalid''.
-- Automatic sources coalesce within same user/source five-minute OBSERVATION bucket; manual is never coalesced.
-- Old offline valid events may be stored for history but must NOT refresh heartbeat, resolve active alerts, or satisfy check-ins.
-- Live safety requires ingest_version=2, abs(received_at-observed_at)<=5m, received_at >= relevant alert/task time, observed_at >= relevant alert/task time.
CREATE OR REPLACE FUNCTION private.insert_behavior_ping(
  _user_id uuid,
  _event_id uuid,
  _observed_at timestamptz,
  _source text,
  _kind text
)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '''' AS $$
DECLARE
  _received_at timestamptz := clock_timestamp();
  _is_live_safety boolean;
  _is_coalesced boolean := false;
BEGIN
  -- 1) Validate arguments
  IF _user_id IS NULL OR _observed_at IS NULL OR _event_id IS NULL THEN
    RETURN ''invalid'';
  END IF;

  IF _source NOT IN (''installed_pwa'', ''tauri'', ''capacitor'', ''shortcut'', ''manual'', ''app'') THEN
    RETURN ''invalid'';
  END IF;

  IF _kind NOT IN (''app'', ''interaction'', ''steps'', ''unlock'', ''manual_checkin'') THEN
    RETURN ''invalid'';
  END IF;

  -- Future safety: Future observed_at > server now+5m => ''invalid''
  IF _observed_at > _received_at + interval ''5 minutes'' THEN
    RETURN ''invalid'';
  END IF;

  -- Serialize retries for one event before inspecting the idempotency index.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(_user_id::text || '':event:'' || _event_id::text, 0)
  );

  -- Automatic events also serialize by user/source/observation bucket so two
  -- concurrent first-seen events cannot both pass the coalescing check.
  IF _source <> ''manual'' THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        _user_id::text || '':bucket:'' || _source || '':'' ||
        floor(extract(epoch from _observed_at) / 300)::bigint::text,
        0
      )
    );
  END IF;

  -- 2) Idempotency check: duplicate event_id (re-checked after locking)
  IF exists (
    SELECT 1 FROM public.behavior_pings
    WHERE user_id = _user_id AND event_id = _event_id
  ) THEN
    RETURN ''duplicate'';
  END IF;

  -- Live safety check
  _is_live_safety := (abs(extract(epoch from (_received_at - _observed_at))) <= 300);

  -- 3) DB 5m coalescing: automatic sources coalesce within same user/source five-minute OBSERVATION bucket; manual is never coalesced.
  -- Only coalesce with an already trusted v2 event (ingest_version = 2) in the SAME 5-minute observation bucket
  IF _source <> ''manual'' AND exists (
    SELECT 1 FROM public.behavior_pings
    WHERE user_id = _user_id
      AND source = _source
      AND ingest_version = 2
      AND floor(extract(epoch from at) / 300) = floor(extract(epoch from _observed_at) / 300)
  ) THEN
    _is_coalesced := true;
  END IF;

  -- 4) Write to behavior_pings if not coalesced
  IF NOT _is_coalesced THEN
    BEGIN
      INSERT INTO public.behavior_pings (user_id, event_id, at, source, kind, received_at, ingest_version)
      VALUES (_user_id, _event_id, _observed_at, _source, _kind, _received_at, 2);
    EXCEPTION WHEN unique_violation THEN
      IF exists (
        SELECT 1 FROM public.behavior_pings
        WHERE user_id = _user_id AND event_id = _event_id
      ) THEN
        RETURN ''duplicate'';
      END IF;
      RAISE;
    END;
  END IF;

  -- 5) Live safety checks: apply liveness side effects (heartbeat and alert causal resolution)
  -- A current live event that is coalesced must STILL apply current liveness side effects!
  -- Duplicates do NOT rerun effects.
  IF _is_live_safety THEN
    PERFORM private.apply_liveness_side_effects(_user_id, _observed_at, _received_at);
  END IF;

  IF _is_coalesced THEN
    RETURN ''coalesced'';
  ELSE
    RETURN ''inserted'';
  END IF;
END;
$$","-- 5) Public authenticated RPC exact signature public.record_behavior_ping(event_id uuid, observed_at timestamptz, source text, kind text) returns text; derive owner only from auth.uid(); deny anon.
CREATE OR REPLACE FUNCTION public.record_behavior_ping(
  event_id uuid,
  observed_at timestamptz,
  source text,
  kind text
)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '''' AS $$
DECLARE
  _uid uuid := auth.uid();
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION ''not authenticated'' USING errcode = ''42501'';
  END IF;
  RETURN private.insert_behavior_ping(_uid, event_id, observed_at, source, kind);
END;
$$","REVOKE EXECUTE ON FUNCTION public.record_behavior_ping(uuid, timestamptz, text, text) FROM PUBLIC, anon, authenticated","GRANT EXECUTE ON FUNCTION public.record_behavior_ping(uuid, timestamptz, text, text) TO authenticated","-- 6) Batch exact public.record_behavior_pings(events jsonb), max 100, ordered by input ordinal, returns rows/status in same order, one transaction, owner auth.uid().
CREATE OR REPLACE FUNCTION public.record_behavior_pings(
  events jsonb
)
RETURNS TABLE (status text) LANGUAGE plpgsql SECURITY DEFINER SET search_path = '''' AS $$
DECLARE
  _uid uuid := auth.uid();
  _evt record;
  _event_id uuid;
  _observed_at timestamptz;
  _source text;
  _kind text;
  _res text;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION ''not authenticated'' USING errcode = ''42501'';
  END IF;

  IF events IS NULL OR jsonb_typeof(events) <> ''array'' THEN
    RAISE EXCEPTION ''invalid batch format'' USING errcode = ''22023'';
  END IF;

  IF jsonb_array_length(events) > 100 THEN
    RAISE EXCEPTION ''batch elements exceed maximum threshold of 100'';
  END IF;

  -- auth.uid()-derived <=100 ordered batch query
  FOR _evt IN
    SELECT value, ordinality
    FROM jsonb_array_elements(events) WITH ORDINALITY
    ORDER BY ordinality
    LIMIT 100
  LOOP
    BEGIN
      _event_id := (_evt.value->>''event_id'')::uuid;
      _observed_at := (_evt.value->>''observed_at'')::timestamptz;
      _source := _evt.value->>''source'';
      _kind := _evt.value->>''kind'';

      IF _event_id IS NULL OR _observed_at IS NULL OR _source IS NULL OR _kind IS NULL THEN
        status := ''invalid'';
        RETURN NEXT;
        CONTINUE;
      END IF;

      _res := private.insert_behavior_ping(_uid, _event_id, _observed_at, _source, _kind);
      status := _res;
      RETURN NEXT;
    EXCEPTION
      WHEN invalid_text_representation OR invalid_datetime_format OR datetime_field_overflow THEN
      status := ''invalid'';
      RETURN NEXT;
    END;
  END LOOP;
END;
$$","REVOKE EXECUTE ON FUNCTION public.record_behavior_pings(jsonb) FROM PUBLIC, anon, authenticated","GRANT EXECUTE ON FUNCTION public.record_behavior_pings(jsonb) TO authenticated","-- 7) Service-only wrapper public.record_behavior_ping_for_user(_user_id uuid,_event_id uuid,_observed_at timestamptz,_source text,_kind text), service_role only, delegates same private validator.
CREATE OR REPLACE FUNCTION public.record_behavior_ping_for_user(
  _user_id uuid,
  _event_id uuid,
  _observed_at timestamptz,
  _source text,
  _kind text
)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '''' AS $$
BEGIN
  RETURN private.insert_behavior_ping(_user_id, _event_id, _observed_at, _source, _kind);
END;
$$","REVOKE EXECUTE ON FUNCTION public.record_behavior_ping_for_user(uuid, uuid, timestamptz, text, text) FROM PUBLIC, anon, authenticated","GRANT EXECUTE ON FUNCTION public.record_behavior_ping_for_user(uuid, uuid, timestamptz, text, text) TO service_role","-- 8) Revoke EXECUTE on private insertion/liveness/sleep helpers from PUBLIC, anon, authenticated.
REVOKE EXECUTE ON FUNCTION private.insert_behavior_ping(uuid, uuid, timestamptz, text, text) FROM PUBLIC, anon, authenticated","REVOKE EXECUTE ON FUNCTION private.apply_liveness_side_effects(uuid, timestamptz, timestamptz) FROM PUBLIC, anon, authenticated","-- 9) Drop/replace unsafe on_behavior_ping_insert logic.
DROP TRIGGER IF EXISTS on_behavior_ping_insert ON public.behavior_pings","DROP FUNCTION IF EXISTS private.handle_behavior_ping_insert()","-- 10) Recreate private.is_in_sleep_window with trusted dynamic pings check
CREATE OR REPLACE FUNCTION private.is_in_sleep_window(_user_id uuid, _now timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''''
AS $$
DECLARE
  _start      time;
  _end        time;
  _timezone   text;
  _local_now  timestamptz;
  _local_time time;
  _local_date date;
  _start_ts   timestamptz;
  _end_ts     timestamptz;
  _dur        interval;
  _last_active    timestamptz;
  _dynamic_end    timestamptz;
BEGIN
  SELECT sleep_start_local, sleep_end_local, coalesce(timezone, ''UTC'')
    INTO _start, _end, _timezone
    FROM public.user_settings
   WHERE user_id = _user_id;

  IF _start IS NULL OR _end IS NULL THEN
    RETURN false;
  END IF;

  -- Convert _now into user''s local timezone (wall-clock)
  _local_now  := _now at time zone _timezone;
  _local_time := _local_now::time;
  _local_date := _local_now::date;

  -- Build start/end timestamps anchored to local date, handling overnight windows
  IF _start > _end THEN
    -- Overnight (e.g. 23:00 -> 07:00)
    IF _local_time < _end THEN
      _start_ts := (_local_date - 1 + _start) at time zone _timezone;
      _end_ts   := (_local_date     + _end  ) at time zone _timezone;
    ELSE
      _start_ts := (_local_date     + _start) at time zone _timezone;
      _end_ts   := (_local_date + 1 + _end  ) at time zone _timezone;
    END IF;
  ELSE
    -- Same-day (e.g. 14:00 -> 16:00 nap)
    IF _local_time < _start THEN
      _start_ts := (_local_date - 1 + _start) at time zone _timezone;
      _end_ts   := (_local_date - 1 + _end  ) at time zone _timezone;
    ELSE
      _start_ts := (_local_date + _start) at time zone _timezone;
      _end_ts   := (_local_date + _end  ) at time zone _timezone;
    END IF;
  END IF;

  _dur := _end_ts - _start_ts;

  -- Dynamic extension: if user pinged shortly before sleep started
  -- Using trusted v2 received_at evidence only (with drift checks)
  SELECT max(received_at) INTO _last_active
    FROM public.behavior_pings
   WHERE user_id = _user_id
     AND ingest_version = 2
     AND abs(extract(epoch from (received_at - at))) <= 300;

  IF _last_active IS NOT NULL THEN
    IF _last_active >= _start_ts - interval ''1 hour'' AND _last_active <= _end_ts THEN
      _dynamic_end := least(_last_active + _dur, _end_ts + interval ''3 hours'');
      RETURN _now >= _start_ts AND _now < _dynamic_end;
    END IF;
  END IF;

  RETURN _now >= _start_ts AND _now < _end_ts;
END;
$$","REVOKE EXECUTE ON FUNCTION private.is_in_sleep_window(uuid, timestamptz) FROM PUBLIC, anon, authenticated","-- 11) CREATE OR REPLACE process_escalations and process_checkin_tasks, plus any GM-relevant function that consumes behavior_pings
CREATE OR REPLACE FUNCTION public.process_escalations()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '''' AS $$
DECLARE
  _self_grace CONSTANT interval := interval ''30 minutes'';
  _group_dur  CONSTANT interval := interval ''1 hour'';
  _comm_dur   CONSTANT interval := interval ''2 hours'';
  r record; _aid uuid; _new text; _triggered boolean := false;
BEGIN
  -- First clear open alerts that no longer match current account-level truth.
  FOR r IN
    SELECT a.id, a.user_id, a.cause, ds.last_heartbeat_at, bp.last_at as last_behavior_at
    FROM public.alerts a
    LEFT JOIN public.device_state ds ON ds.user_id = a.user_id
    LEFT JOIN LATERAL (
      SELECT max(received_at) as last_at
      FROM public.behavior_pings
      WHERE user_id = a.user_id
        -- Live safety requires ingest_version=2, drift, and causal-time checks.
        AND ingest_version = 2
        AND abs(extract(epoch from (received_at - at))) <= 300 -- drift <= 5m
        -- auto-resolution for silence MUST require a qualifying v2 ping with BOTH received_at>=opened_at and at>=opened_at
        AND received_at >= a.opened_at
        AND at >= a.opened_at
    ) bp ON true
    WHERE a.status = ''open''
      AND a.cause in (''silence'', ''dark_device'')
      AND (
        (
          a.cause = ''silence''
          AND bp.last_at IS NOT NULL
          AND (
            private.is_in_sleep_window(a.user_id, now())
            -- Note: The ADR''s alert-created-at concept maps to alerts.opened_at (created_at search text)
            OR now() - bp.last_at <= private.silence_threshold(a.user_id)
          )
        )
        OR (
          a.cause = ''dark_device''
          AND ds.last_heartbeat_at IS NOT NULL
          AND now() - ds.last_heartbeat_at <= interval ''18 hours''
        )
      )
  LOOP
    UPDATE public.alerts
      SET status = ''resolved'', resolved_at = now(), resolved_by = null, updated_at = now()
      WHERE id = r.id;
    INSERT INTO public.alert_events (alert_id, kind, note)
      VALUES (r.id, ''auto_resolved'', ''condition_cleared'');
    DELETE FROM public.notifications WHERE alert_id = r.id;
    _triggered := true;
  END LOOP;

  FOR r IN
    SELECT ds.user_id,
           (now() - ds.last_heartbeat_at) > interval ''18 hours'' as is_dark
    FROM public.device_state ds
    WHERE (
      ds.status = ''alert''
      OR now() - ds.last_heartbeat_at > interval ''18 hours''
      OR (
        NOT private.is_in_sleep_window(ds.user_id, now())
        AND now() - (
          SELECT coalesce(max(received_at), to_timestamp(0))
          FROM public.behavior_pings
          WHERE user_id = ds.user_id
            -- Live safety requires ingest_version=2, drift, and causal-time checks.
            AND ingest_version = 2
            AND abs(extract(epoch from (received_at - at))) <= 300 -- drift <= 5m
        ) > private.silence_threshold(ds.user_id)
      )
    )
      AND exists (SELECT 1 FROM public.group_members gm
                  WHERE gm.user_id = ds.user_id and gm.monitored and gm.status = ''active'')
      AND NOT exists (SELECT 1 FROM public.alerts a WHERE a.user_id = ds.user_id and a.status = ''open'')
      AND NOT exists (
        SELECT 1 FROM public.alerts recent
        -- Note: The ADR''s alert-created-at concept maps to alerts.opened_at (created_at search text)
        WHERE recent.user_id = ds.user_id
          AND recent.status = ''resolved''
          AND recent.cause in (''silence'', ''dark_device'')
          AND recent.resolved_by IS NOT NULL
          AND recent.resolved_by <> recent.user_id
          AND recent.resolved_at > now() - _self_grace
      )
  LOOP
    INSERT INTO public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    VALUES (r.user_id, CASE WHEN r.is_dark THEN ''dark_device'' ELSE ''silence'' end,
            ''self'', now(), now() + _self_grace)
    RETURNING id INTO _aid;
    INSERT INTO public.alert_events (alert_id, kind) values (_aid, ''raised'');
    PERFORM private.notify_stage(_aid, r.user_id, ''self'');
    _triggered := true;
  END LOOP;

  FOR r IN
    SELECT * FROM public.alerts
    WHERE status = ''open''
      AND next_deadline IS NOT NULL AND next_deadline <= now()
      AND coalesce(paused_until, to_timestamp(0)) <= now()
  LOOP
    _new := CASE r.stage
              WHEN ''self'' THEN ''group''
              WHEN ''group'' THEN ''community''
              WHEN ''community'' THEN ''terminal''
              ELSE ''terminal'' end;
    UPDATE public.alerts
      SET stage = _new, stage_entered_at = now(), paused_until = null, paused_by = null, updated_at = now(),
          next_deadline = CASE _new WHEN ''group'' THEN now() + _group_dur
                                    WHEN ''community'' THEN now() + _comm_dur
                                    ELSE null end
      WHERE id = r.id;
    INSERT INTO public.alert_events (alert_id, kind, note) VALUES (r.id, ''escalated'', _new);
    PERFORM private.notify_stage(r.id, r.user_id, _new);
    _triggered := true;
  END LOOP;

  IF _triggered THEN
    PERFORM private.trigger_push_dispatch();
  END IF;
END;
$$","REVOKE EXECUTE ON FUNCTION public.process_escalations() FROM public, anon, authenticated","CREATE OR REPLACE FUNCTION public.process_checkin_tasks()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '''' AS $$
DECLARE
  t record;
  _done boolean;
  _wname text;
  _timezone text;
  _local_date date;
  _candidate timestamptz;
BEGIN
  -- 1) 到点：提醒承担者 (Claim rows using FOR UPDATE SKIP LOCKED to prevent concurrent cron double-firing)
  FOR t IN
    SELECT * FROM public.checkin_tasks ct
    WHERE status = ''active'' AND cycle_state = ''idle''
      AND next_due_at IS NOT NULL AND next_due_at <= now()
      AND NOT private.sleep_relaxed(ct.ward_id, now())
    FOR UPDATE SKIP LOCKED
  LOOP
    INSERT INTO public.notifications (recipient_id, kind, body, params)
    VALUES (t.ward_id, ''task_due'', ''到点报平安啦，点开 App 完成确认。'',
            jsonb_build_object(''label'', t.label));

    UPDATE public.checkin_tasks
    SET cycle_state = ''due_notified'', updated_at = now()
    WHERE id = t.id;
  END LOOP;

  -- 2) 宽限到期：心跳判定完成与否；漏卡 → 通知设置者(自设则通知守护人/同组守望者)
  -- (Claim rows using FOR UPDATE SKIP LOCKED to prevent concurrent cron double-firing)
  FOR t IN
    SELECT * FROM public.checkin_tasks ct
    WHERE status = ''active'' AND cycle_state = ''due_notified''
      AND next_due_at + make_interval(mins => ct.grace_minutes) <= now()
      AND NOT private.sleep_relaxed(ct.ward_id, now())
    FOR UPDATE SKIP LOCKED
  LOOP
    -- Judge completion by REAL activity in behavior_pings (exists a behavior_pings row for ward_id with received_at >= next_due_at), NOT device_state.
    -- Live safety requires ingest_version=2, abs(received_at-observed_at)<=5m, received_at >= relevant alert/task time, observed_at >= relevant alert/task time.
    SELECT EXISTS (
      SELECT 1 FROM public.behavior_pings bp
      WHERE bp.user_id = t.ward_id
        AND bp.ingest_version = 2
        AND abs(extract(epoch from (bp.received_at - bp.at))) <= 300 -- drift <= 5m
        AND bp.received_at >= t.next_due_at
        AND bp.at >= t.next_due_at
    ) INTO _done;

    IF NOT _done THEN
      SELECT coalesce(display_name, '''') INTO _wname FROM public.profiles WHERE id = t.ward_id;

      INSERT INTO public.notifications (recipient_id, kind, body, params)
      SELECT DISTINCT r.uid, ''task_missed'',
        _wname || '' 未完成定时报平安，请关注。'',
        jsonb_build_object(''name'', _wname, ''label'', t.label)
      FROM (
        SELECT t.created_by AS uid WHERE t.created_by <> t.ward_id
        UNION
        SELECT g.guardian_id FROM public.guardianships g
          WHERE t.created_by = t.ward_id AND g.ward_id = t.ward_id AND g.status = ''active''
        UNION
        SELECT w.user_id FROM public.group_members gm
          JOIN public.group_members w ON w.group_id = gm.group_id
          WHERE t.created_by = t.ward_id
            AND gm.user_id = t.ward_id AND gm.monitored AND gm.status = ''active''
            AND w.watching AND w.status = ''active'' AND w.user_id <> t.ward_id
            AND NOT EXISTS (SELECT 1 FROM public.guardianships g2
                            WHERE g2.ward_id = t.ward_id AND g2.status = ''active'')
      ) r;
    END IF;

    -- 滚动下一轮（漏卡也滚动，避免重复轰炸；daily 跳到未来最近一个周期）
    IF t.kind = ''daily'' THEN
      _timezone := null;
      SELECT timezone INTO _timezone FROM public.user_settings WHERE user_id = t.ward_id;
      _timezone := coalesce(_timezone, ''UTC'');
      _local_date := (now() at time zone _timezone)::date;
      _candidate := (_local_date + t.due_time_local) at time zone _timezone;
      WHILE _candidate <= now() OR _candidate <= t.next_due_at LOOP
        _local_date := _local_date + 1;
        _candidate := (_local_date + t.due_time_local) at time zone _timezone;
      END LOOP;
    ELSE
      _candidate := now() + make_interval(hours => t.interval_hours);
    END IF;

    UPDATE public.checkin_tasks SET
      cycle_state = ''idle'',
      next_due_at = _candidate,
      updated_at = now()
      WHERE id = t.id;
  END LOOP;
END;
$$","REVOKE EXECUTE ON FUNCTION public.process_checkin_tasks() FROM public, anon, authenticated","CREATE OR REPLACE FUNCTION public.gm_list_clients()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '''' AS $$
DECLARE _uid uuid := auth.uid();
BEGIN
  IF NOT private.is_admin(_uid) THEN RAISE EXCEPTION ''forbidden''; END IF;
  RETURN coalesce((
    SELECT jsonb_agg(obj ORDER BY nm asc, ls desc nulls last)
    FROM (
      SELECT jsonb_build_object(
        ''user_id'', p.id,
        ''name'', coalesce(nullif(p.display_name,''''), left(p.id::text,8)),
        ''platform'', c.platform,
        ''app_version'', c.app_version,
        ''first_seen_at'', c.first_seen_at,
        ''last_seen_at'', c.last_seen_at,
        ''last_heartbeat_at'', ds.last_heartbeat_at,
        ''last_behavior_at'', bp.last_at,
        ''alerted'', exists (
          SELECT 1 FROM public.alerts a
          WHERE a.user_id = p.id and a.status = ''open''
            AND a.stage in (''group'',''community'',''terminal'')
        ),
        ''status'',
          CASE
            WHEN exists (
              SELECT 1 FROM public.alerts a
              WHERE a.user_id = p.id and a.status = ''open''
                AND a.stage in (''group'',''community'',''terminal'')
            ) THEN ''alert''
            WHEN bp.last_at IS NULL THEN ''never''
            WHEN bp.last_at > now() - interval ''6 hours'' THEN ''active''
            WHEN bp.last_at > now() - interval ''24 hours'' THEN ''quiet''
            ELSE ''silent''
          END
      ) as obj,
      coalesce(nullif(p.display_name,''''), left(p.id::text,8)) as nm,
      c.last_seen_at as ls
      FROM public.profiles p
      LEFT JOIN public.clients c ON c.user_id = p.id
      LEFT JOIN public.device_state ds ON ds.user_id = p.id
      LEFT JOIN LATERAL (
        SELECT max(received_at) as last_at
        FROM public.behavior_pings
        WHERE user_id = p.id
          -- Live safety check
          AND ingest_version = 2
          AND abs(extract(epoch from (received_at - at))) <= 300
      ) bp ON true
    ) s
  ), ''[]''::jsonb);
END;
$$","REVOKE EXECUTE ON FUNCTION public.gm_list_clients() FROM PUBLIC, anon","GRANT EXECUTE ON FUNCTION public.gm_list_clients() TO authenticated","-- Restore public.my_routine_status contract
CREATE OR REPLACE FUNCTION public.my_routine_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''''
AS $$
DECLARE
  _uid uuid := auth.uid();
  _threshold interval;
  _last_at timestamptz;
  _s text;
  _sleep_start time;
  _sleep_end time;
  _timezone text;
  _in_sleep_window boolean;
  _model_confidence double precision;
  _model_explanation text;
  _model_version text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION ''not authenticated''; END IF;

  SELECT sensitivity, sleep_start_local, sleep_end_local, timezone
    INTO _s, _sleep_start, _sleep_end, _timezone
    FROM public.user_settings
   WHERE user_id = _uid;

  SELECT model_confidence, model_explanation, model_version
    INTO _model_confidence, _model_explanation, _model_version
    FROM public.user_activity_profiles
   WHERE user_id = _uid;

  _threshold := private.silence_threshold(_uid);
  _in_sleep_window := private.is_in_sleep_window(_uid, now());

  SELECT max(received_at)
    INTO _last_at
    FROM public.behavior_pings
   WHERE user_id = _uid
     AND ingest_version = 2
     AND abs(extract(epoch from (received_at - at))) <= 300;

  RETURN jsonb_build_object(
    ''threshold_seconds'', extract(epoch from _threshold)::bigint,
    ''last_behavior_at'', _last_at,
    ''sensitivity'', coalesce(_s, ''balanced''),
    ''sleep_start'', _sleep_start,
    ''sleep_end'', _sleep_end,
    ''timezone'', coalesce(_timezone, ''UTC''),
    ''in_sleep_window'', coalesce(_in_sleep_window, false),
    ''model_confidence'', _model_confidence,
    ''model_explanation'', _model_explanation,
    ''model_version'', _model_version
  );
END;
$$","REVOKE EXECUTE ON FUNCTION public.my_routine_status() FROM public, anon","GRANT EXECUTE ON FUNCTION public.my_routine_status() TO authenticated","-- Recreate public.get_group_activity_view changing behavior evidence to trusted v2
CREATE OR REPLACE FUNCTION public.get_group_activity_view(_group uuid, _view text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '''' AS $$
DECLARE
  _uid uuid := auth.uid();
  _mode text := coalesce(nullif(btrim(_view), ''''), ''group'');
  _is_owner boolean;
  _i_watching boolean;
  _i_share boolean;
  _members jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION ''not authenticated''; END IF;
  IF _mode NOT IN (''watch'', ''group'') THEN RAISE EXCEPTION ''invalid activity view''; END IF;

  SELECT EXISTS (
           SELECT 1 FROM public.group_members gm
           WHERE gm.group_id = g.id and gm.user_id = _uid
             AND gm.role = ''admin'' and gm.status = ''active''
         ),
         coalesce(me.watching, false)
    INTO _is_owner, _i_watching
  FROM public.groups g
  JOIN public.group_members me
    ON me.group_id = g.id and me.user_id = _uid and me.status = ''active''
  WHERE g.id = _group;
  IF NOT FOUND THEN RAISE EXCEPTION ''forbidden''; END IF;

  SELECT coalesce(us.share_activity, true) INTO _i_share
  FROM public.user_settings us WHERE us.user_id = _uid;
  _i_share := coalesce(_i_share, true);

  SELECT coalesce(jsonb_agg(
    jsonb_build_object(
      ''user_id'', m.user_id,
      ''name'', coalesce(nullif(p.display_name, ''''), left(m.user_id::text, 8)),
      ''is_me'', m.user_id = _uid,
      ''status'',
        CASE
          WHEN m.user_id = _uid THEN ''self''
          WHEN not coalesce(us.share_activity, true) and not coalesce(al.alerted, false) THEN ''hidden''
          WHEN coalesce(al.alerted, false) THEN ''alert''
          WHEN bp.last_at IS NULL THEN ''unknown''
          WHEN bp.last_at > now() - interval ''6 hours'' THEN ''active''
          WHEN bp.last_at > now() - interval ''24 hours'' THEN ''quiet''
          ELSE ''silent''
        END,
      ''hours'',
        CASE
          WHEN bp.last_at IS NULL THEN null
          ELSE floor(extract(epoch from (now() - bp.last_at)) / 3600)::int
        END,
      ''last_behavior_at'', bp.last_at,
      ''last_heartbeat_at'', ds.last_heartbeat_at,
      ''threshold_hours'', round(extract(epoch from private.silence_threshold(m.user_id)) / 3600.0, 2),
      ''alerted'', coalesce(al.alerted, false)
    )
    ORDER BY (m.user_id = _uid) DESC, p.display_name NULLS LAST, m.user_id
  ), ''[]''::jsonb) INTO _members
  FROM public.group_members m
  LEFT JOIN public.profiles p ON p.id = m.user_id
  LEFT JOIN public.user_settings us ON us.user_id = m.user_id
  LEFT JOIN public.device_state ds ON ds.user_id = m.user_id
  LEFT JOIN LATERAL (
    SELECT max(received_at) as last_at
    FROM public.behavior_pings
    WHERE user_id = m.user_id
      AND ingest_version = 2
      AND abs(extract(epoch from (received_at - at))) <= 300
  ) bp ON true
  LEFT JOIN LATERAL (
    SELECT exists (
      SELECT 1 FROM public.alerts a
      WHERE a.user_id = m.user_id and a.status = ''open''
        AND a.stage in (''group'', ''community'', ''terminal'')
    ) as alerted
  ) al ON true
  WHERE m.group_id = _group
    AND m.status = ''active''
    AND (
      _mode = ''group''
      OR m.user_id = _uid
      OR (_i_watching and m.monitored)
    );

  RETURN jsonb_build_object(
    ''visibility'', CASE WHEN _mode = ''watch'' THEN ''watchers_only'' ELSE ''group_wide'' END,
    ''view'', _mode,
    ''is_owner'', _is_owner,
    ''i_share'', _i_share,
    ''members'', _members
  );
END;
$$","REVOKE EXECUTE ON FUNCTION public.get_group_activity_view(uuid, text) FROM PUBLIC, anon","GRANT EXECUTE ON FUNCTION public.get_group_activity_view(uuid, text) TO authenticated","-- Preserve the pre-scoped activity RPC used by older clients and by the
-- explicit compatibility fallback in groupActivity.ts. Only its evidence
-- predicate changes; privacy and response shape remain unchanged.
CREATE OR REPLACE FUNCTION public.get_group_activity(_group uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '''' AS $$
DECLARE
  _uid uuid := auth.uid();
  _visibility text;
  _is_owner boolean;
  _i_watching boolean;
  _i_share boolean;
  _members jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION ''not authenticated''; END IF;

  SELECT g.activity_visibility,
         EXISTS (
           SELECT 1 FROM public.group_members gm
           WHERE gm.group_id = g.id AND gm.user_id = _uid
             AND gm.role = ''admin'' AND gm.status = ''active''
         ),
         coalesce(me.watching, false)
    INTO _visibility, _is_owner, _i_watching
  FROM public.groups g
  JOIN public.group_members me
    ON me.group_id = g.id AND me.user_id = _uid AND me.status = ''active''
  WHERE g.id = _group;
  IF NOT FOUND THEN RAISE EXCEPTION ''forbidden''; END IF;

  SELECT coalesce(us.share_activity, true) INTO _i_share
  FROM public.user_settings us WHERE us.user_id = _uid;
  _i_share := coalesce(_i_share, true);

  SELECT jsonb_agg(
    jsonb_build_object(
      ''user_id'', m.user_id,
      ''name'', coalesce(nullif(p.display_name, ''''), left(m.user_id::text, 8)),
      ''is_me'', m.user_id = _uid,
      ''status'',
        CASE
          WHEN m.user_id = _uid THEN ''self''
          WHEN NOT coalesce(us.share_activity, true) AND NOT coalesce(al.alerted, false) THEN ''hidden''
          WHEN _visibility = ''watchers_only'' AND NOT _i_watching AND NOT coalesce(al.alerted, false) THEN ''hidden''
          WHEN coalesce(al.alerted, false) THEN ''alert''
          WHEN bp.last_at IS NULL THEN ''unknown''
          WHEN bp.last_at > now() - interval ''6 hours'' THEN ''active''
          WHEN bp.last_at > now() - interval ''24 hours'' THEN ''quiet''
          ELSE ''silent''
        END,
      ''hours'',
        CASE
          WHEN bp.last_at IS NULL THEN null
          ELSE floor(extract(epoch from (now() - bp.last_at)) / 3600)::int
        END,
      ''last_behavior_at'', bp.last_at,
      ''last_heartbeat_at'', ds.last_heartbeat_at,
      ''threshold_hours'', round(extract(epoch from private.silence_threshold(m.user_id)) / 3600.0, 2),
      ''alerted'', coalesce(al.alerted, false)
    )
    ORDER BY (m.user_id = _uid) DESC, p.display_name NULLS LAST, m.user_id
  ) INTO _members
  FROM public.group_members m
  LEFT JOIN public.profiles p ON p.id = m.user_id
  LEFT JOIN public.user_settings us ON us.user_id = m.user_id
  LEFT JOIN public.device_state ds ON ds.user_id = m.user_id
  LEFT JOIN LATERAL (
    SELECT max(received_at) AS last_at
    FROM public.behavior_pings
    WHERE user_id = m.user_id
      AND ingest_version = 2
      AND abs(extract(epoch from (received_at - at))) <= 300
  ) bp ON true
  LEFT JOIN LATERAL (
    SELECT EXISTS (
      SELECT 1 FROM public.alerts a
      WHERE a.user_id = m.user_id AND a.status = ''open''
        AND a.stage IN (''group'', ''community'', ''terminal'')
    ) AS alerted
  ) al ON true
  WHERE m.group_id = _group AND m.status = ''active'';

  RETURN jsonb_build_object(
    ''visibility'', _visibility,
    ''is_owner'', _is_owner,
    ''i_share'', _i_share,
    ''members'', coalesce(_members, ''[]''::jsonb)
  );
END;
$$","REVOKE EXECUTE ON FUNCTION public.get_group_activity(uuid) FROM PUBLIC, anon","GRANT EXECUTE ON FUNCTION public.get_group_activity(uuid) TO authenticated","-- 12) REVOKE EXECUTE ON FUNCTION public.initialize_user_routine_data(uuid) FROM PUBLIC, anon, authenticated.
-- Replace its body with a non-destructive no-op.
-- Drop trigger on_profile_pattern_change and do not recreate it.
CREATE OR REPLACE FUNCTION public.initialize_user_routine_data(_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '''' AS $$
BEGIN
  -- Non-destructive no-op
  RETURN;
END;
$$","REVOKE EXECUTE ON FUNCTION public.initialize_user_routine_data(uuid) FROM PUBLIC, anon, authenticated","DROP TRIGGER IF EXISTS on_profile_pattern_change ON public.profiles","-- 13) Rebuild private.silence_threshold (deterministic sensitivity fallback matching ''sensitive'', ''balanced'', ''relaxed'' app enums)
CREATE OR REPLACE FUNCTION private.silence_threshold(_user_id uuid)
 RETURNS interval
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''''
AS $$
DECLARE
  _s text;
BEGIN
  SELECT sensitivity
    INTO _s
    FROM public.user_settings
   WHERE user_id = _user_id;

  _s := coalesce(_s, ''balanced'');

  RETURN CASE _s
    WHEN ''high'' THEN interval ''1.5 hours'' -- sensitive
    WHEN ''sensitive'' THEN interval ''1.5 hours'' -- sensitive app enum
    WHEN ''low'' THEN interval ''6 hours'' -- relaxed
    WHEN ''relaxed'' THEN interval ''6 hours'' -- relaxed app enum
    ELSE interval ''3 hours'' -- balanced
  END;
END;
$$","REVOKE EXECUTE ON FUNCTION private.silence_threshold(uuid) FROM PUBLIC, anon, authenticated","-- 14) run_daily_aggregations using only canonical evidence/provenance, never random/synthetic reset/delete
CREATE OR REPLACE FUNCTION private.aggregate_user_daily_activity(_user_id uuid, _date date)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '''' AS $$
DECLARE
  _timezone text;
  _hourly_density integer[] := array_fill(0, array[24]);
  _ping record;
  _hour int;
BEGIN
  SELECT timezone INTO _timezone FROM public.user_settings WHERE user_id = _user_id;
  _timezone := coalesce(_timezone, ''UTC'');

  -- Count pings using only canonical evidence (ingest_version = 2)
  FOR _ping IN
    SELECT extract(hour from at at time zone _timezone)::int as hr
    FROM public.behavior_pings
    WHERE user_id = _user_id
      AND ingest_version = 2
      AND (at at time zone _timezone)::date = _date
  LOOP
    _hour := _ping.hr;
    IF _hour >= 0 AND _hour <= 23 THEN
      _hourly_density[_hour + 1] := _hourly_density[_hour + 1] + 1;
    END IF;
  END LOOP;

  INSERT INTO public.daily_activity_aggregates (user_id, date, hourly_density)
  VALUES (_user_id, _date, _hourly_density)
  ON CONFLICT (user_id, date) DO UPDATE
    SET hourly_density = excluded.hourly_density;
END;
$$","REVOKE EXECUTE ON FUNCTION private.aggregate_user_daily_activity(uuid, date) FROM PUBLIC, anon, authenticated","CREATE OR REPLACE FUNCTION public.run_daily_aggregations()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '''' AS $$
DECLARE
  _user record;
  _timezone text;
  _yesterday date;
BEGIN
  FOR _user IN SELECT id FROM auth.users LOOP
    SELECT timezone INTO _timezone FROM public.user_settings WHERE user_id = _user.id;
    _timezone := coalesce(_timezone, ''UTC'');

    _yesterday := (now() at time zone _timezone)::date - 1;

    PERFORM private.aggregate_user_daily_activity(_user.id, _yesterday);
  END LOOP;
END;
$$","REVOKE EXECUTE ON FUNCTION public.run_daily_aggregations() FROM PUBLIC, anon, authenticated","-- 15) Cron: unschedule update-routine-profiles-weekly safely, unschedule run-daily-aggregations safely, and reschedule run-daily-aggregations.
SELECT cron.unschedule(jobname) FROM cron.job WHERE jobname = ''update-routine-profiles-weekly''","SELECT cron.unschedule(jobname) FROM cron.job WHERE jobname = ''run-daily-aggregations''","SELECT cron.schedule(''run-daily-aggregations'', ''5 0 * * *'', ''select public.run_daily_aggregations();'')"}', 'routine_ai_gate1_containment', NULL, NULL, NULL),
	('20260719162146', '{"-- ADR-0022: restore sensitivity as an additive user tool on the
-- deterministic Gate 1 neutral base. Learned activity profiles remain
-- quarantined from live safety authority.
CREATE OR REPLACE FUNCTION private.silence_threshold(_user_id uuid)
RETURNS interval
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''''
AS $$
DECLARE
  _s text;
BEGIN
  SELECT sensitivity
    INTO _s
    FROM public.user_settings
   WHERE user_id = _user_id;

  _s := coalesce(_s, ''balanced'');

  RETURN CASE _s
    WHEN ''high'' THEN interval ''1.5 hours''
    WHEN ''sensitive'' THEN interval ''1.5 hours''
    WHEN ''low'' THEN interval ''3 hours''
    WHEN ''relaxed'' THEN interval ''3 hours''
    ELSE interval ''2.25 hours''
  END;
END;
$$;

REVOKE EXECUTE ON FUNCTION private.silence_threshold(uuid) FROM PUBLIC, anon, authenticated;

"}', 'correct_gate1_sensitivity_contract', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260720150000', '{"-- NOTIF-01: auto-resolve 不再静默清删告警通知。
-- 诊断(KC-NOTIF-CLEARALL-ACK-001):auto-resolve 两条路径
-- (private.apply_liveness_side_effects + public.process_escalations 条件清除环)
-- 会 DELETE 该 alert 的全部 notifications 且不补任何通知;confirmed_safe 路径却保留
-- 并补发 ''resolved''。近 7 天线上 8/8 auto_resolved 告警 notif_left=0。
-- 表象:响应者「Clear all + 我去联系」后所有相关通知无痕消失,认领者也失去
-- 「确认安全」入口(响应卡片完全由通知行派生)。
-- 本迁移:
--   1) 新增 private.notify_auto_resolved:补发 kind=''auto_resolved'' 通知
--      (目标 + watcher + guardian,与 resolve_alert/notify_stage 接收面一致)。
--   2) 两条 auto-resolve 路径以补发替代删除,保留历史行。
--   3) 新增 public.clear_finished_notifications():Clear all 的 keep 判定移到
--      服务端(仅删非 open 告警的行),根除客户端 items 竞态与 limit 30 陷阱。
-- 兼容:旧客户端对未知 kind 走 body 回退(App 内与 sw.js 皆是);旧客户端的
-- 客户端删除路径在现有 RLS delete 策略下仍合法。

-- 1) 补发助手(私有,仅由 security definer 流程调用)
create or replace function private.notify_auto_resolved(_alert_id uuid, _target uuid)
returns void language plpgsql security definer set search_path to '''' as $$
declare _tname text;
begin
  select coalesce(display_name, '''') into _tname from public.profiles where id = _target;
  insert into public.notifications (recipient_id, alert_id, kind, body, params)
  select distinct s.r, _alert_id, ''auto_resolved'',
    coalesce(nullif(_tname, ''''), ''成员'') || '' 的告警已自动解除(检测到活动恢复)。'',
    jsonb_build_object(''target'', _tname)
  from (
    select _target as r
    union
    select w.user_id from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _target and t.monitored and t.status = ''active''
        and w.watching and w.status = ''active''
    union
    select g.guardian_id from public.guardianships g
      where g.ward_id = _target and g.status = ''active''
  ) s;
end;
$$;

revoke execute on function private.notify_auto_resolved(uuid, uuid) from public, anon, authenticated;

-- 2a) liveness 摄入路径:删除 → 补发(其余逻辑与线上现行版本逐字一致)
CREATE OR REPLACE FUNCTION private.apply_liveness_side_effects(_user_id uuid, _observed_at timestamp with time zone, _received_at timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''''
AS $function$
DECLARE
  _stale record;
  _triggered boolean := false;
BEGIN
  -- Update device_state:
  INSERT INTO public.device_state (user_id, status, last_heartbeat_at, updated_at)
  VALUES (_user_id, ''normal'', _received_at, now())
  ON CONFLICT (user_id) DO UPDATE
    SET status = ''normal'',
        last_heartbeat_at = greatest(device_state.last_heartbeat_at, excluded.last_heartbeat_at),
        updated_at = now();

  -- Resolve alerts:
  -- Any trigger/side effects must apply the live qualification above, and active alert resolution must require both received_at and observed_at >= alerts.opened_at.
  -- Note: The ADR''s alert-created-at concept maps to alerts.opened_at (created_at search text)
  FOR _stale IN
    SELECT id, opened_at FROM public.alerts
    WHERE user_id = _user_id
      AND status = ''open''
      AND cause in (''silence'', ''dark_device'')
      AND _received_at >= opened_at
      AND _observed_at >= opened_at
  LOOP
    UPDATE public.alerts
      SET status = ''resolved'', resolved_at = _received_at, resolved_by = _user_id, updated_at = now()
      WHERE id = _stale.id;

    INSERT INTO public.alert_events (alert_id, actor_id, kind)
    VALUES (_stale.id, _user_id, ''auto_resolved'');

    -- NOTIF-01: 保留该告警的通知历史,改为补发自动解除通知
    PERFORM private.notify_auto_resolved(_stale.id, _user_id);
    _triggered := true;
  END LOOP;

  -- Clear user self check-in nudges
  IF NOT (auth.uid() IS NOT NULL AND auth.uid() <> _user_id) THEN
    DELETE FROM public.notifications
      WHERE recipient_id = _user_id
        AND kind in (''self'', ''concern'');
  END IF;

  IF _triggered THEN
    PERFORM private.trigger_push_dispatch();
  END IF;
END;
$function$;

-- 2b) cron 条件清除环:删除 → 补发(其余逻辑与线上现行版本逐字一致)
CREATE OR REPLACE FUNCTION public.process_escalations()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''''
AS $function$
DECLARE
  _self_grace CONSTANT interval := interval ''30 minutes'';
  _group_dur  CONSTANT interval := interval ''1 hour'';
  _comm_dur   CONSTANT interval := interval ''2 hours'';
  r record; _aid uuid; _new text; _triggered boolean := false;
BEGIN
  -- First clear open alerts that no longer match current account-level truth.
  FOR r IN
    SELECT a.id, a.user_id, a.cause, ds.last_heartbeat_at, bp.last_at as last_behavior_at
    FROM public.alerts a
    LEFT JOIN public.device_state ds ON ds.user_id = a.user_id
    LEFT JOIN LATERAL (
      SELECT max(received_at) as last_at
      FROM public.behavior_pings
      WHERE user_id = a.user_id
        -- Live safety requires ingest_version=2, drift, and causal-time checks.
        AND ingest_version = 2
        AND abs(extract(epoch from (received_at - at))) <= 300 -- drift <= 5m
        -- auto-resolution for silence MUST require a qualifying v2 ping with BOTH received_at>=opened_at and at>=opened_at
        AND received_at >= a.opened_at
        AND at >= a.opened_at
    ) bp ON true
    WHERE a.status = ''open''
      AND a.cause in (''silence'', ''dark_device'')
      AND (
        (
          a.cause = ''silence''
          AND bp.last_at IS NOT NULL
          AND (
            private.is_in_sleep_window(a.user_id, now())
            -- Note: The ADR''s alert-created-at concept maps to alerts.opened_at (created_at search text)
            OR now() - bp.last_at <= private.silence_threshold(a.user_id)
          )
        )
        OR (
          a.cause = ''dark_device''
          AND ds.last_heartbeat_at IS NOT NULL
          AND now() - ds.last_heartbeat_at <= interval ''18 hours''
        )
      )
  LOOP
    UPDATE public.alerts
      SET status = ''resolved'', resolved_at = now(), resolved_by = null, updated_at = now()
      WHERE id = r.id;
    INSERT INTO public.alert_events (alert_id, kind, note)
      VALUES (r.id, ''auto_resolved'', ''condition_cleared'');
    -- NOTIF-01: 保留该告警的通知历史,改为补发自动解除通知
    PERFORM private.notify_auto_resolved(r.id, r.user_id);
    _triggered := true;
  END LOOP;

  FOR r IN
    SELECT ds.user_id,
           (now() - ds.last_heartbeat_at) > interval ''18 hours'' as is_dark
    FROM public.device_state ds
    WHERE (
      ds.status = ''alert''
      OR now() - ds.last_heartbeat_at > interval ''18 hours''
      OR (
        NOT private.is_in_sleep_window(ds.user_id, now())
        AND now() - (
          SELECT coalesce(max(received_at), to_timestamp(0))
          FROM public.behavior_pings
          WHERE user_id = ds.user_id
            -- Live safety requires ingest_version=2, drift, and causal-time checks.
            AND ingest_version = 2
            AND abs(extract(epoch from (received_at - at))) <= 300 -- drift <= 5m
        ) > private.silence_threshold(ds.user_id)
      )
    )
      AND exists (SELECT 1 FROM public.group_members gm
                  WHERE gm.user_id = ds.user_id and gm.monitored and gm.status = ''active'')
      AND NOT exists (SELECT 1 FROM public.alerts a WHERE a.user_id = ds.user_id and a.status = ''open'')
      AND NOT exists (
        SELECT 1 FROM public.alerts recent
        -- Note: The ADR''s alert-created-at concept maps to alerts.opened_at (created_at search text)
        WHERE recent.user_id = ds.user_id
          AND recent.status = ''resolved''
          AND recent.cause in (''silence'', ''dark_device'')
          AND recent.resolved_by IS NOT NULL
          AND recent.resolved_by <> recent.user_id
          AND recent.resolved_at > now() - _self_grace
      )
  LOOP
    INSERT INTO public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    VALUES (r.user_id, CASE WHEN r.is_dark THEN ''dark_device'' ELSE ''silence'' end,
            ''self'', now(), now() + _self_grace)
    RETURNING id INTO _aid;
    INSERT INTO public.alert_events (alert_id, kind) values (_aid, ''raised'');
    PERFORM private.notify_stage(_aid, r.user_id, ''self'');
    _triggered := true;
  END LOOP;

  FOR r IN
    SELECT * FROM public.alerts
    WHERE status = ''open''
      AND next_deadline IS NOT NULL AND next_deadline <= now()
      AND coalesce(paused_until, to_timestamp(0)) <= now()
  LOOP
    _new := CASE r.stage
              WHEN ''self'' THEN ''group''
              WHEN ''group'' THEN ''community''
              WHEN ''community'' THEN ''terminal''
              ELSE ''terminal'' end;
    UPDATE public.alerts
      SET stage = _new, stage_entered_at = now(), paused_until = null, paused_by = null, updated_at = now(),
          next_deadline = CASE _new WHEN ''group'' THEN now() + _group_dur
                                    WHEN ''community'' THEN now() + _comm_dur
                                    ELSE null end
      WHERE id = r.id;
    INSERT INTO public.alert_events (alert_id, kind, note) VALUES (r.id, ''escalated'', _new);
    PERFORM private.notify_stage(r.id, r.user_id, _new);
    _triggered := true;
  END LOOP;

  IF _triggered THEN
    PERFORM private.trigger_push_dispatch();
  END IF;
END;
$function$;

-- 3) Clear all 的服务端 keep 判定:仅删「无 alert 或 alert 已非 open」的本人通知
create or replace function public.clear_finished_notifications()
returns void language sql security definer set search_path to '''' as $$
  delete from public.notifications n
  where n.recipient_id = auth.uid()
    and (
      n.alert_id is null
      or not exists (
        select 1 from public.alerts a
        where a.id = n.alert_id and a.status = ''open''
      )
    );
$$;

revoke execute on function public.clear_finished_notifications() from public, anon;
grant execute on function public.clear_finished_notifications() to authenticated;"}', 'keep_notifications_on_auto_resolve', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260718063500', '{"-- Migration: update_sos_location
-- Created: 2026-07-18

create or replace function public.update_sos_location(
  _lat double precision,
  _lng double precision
)
returns boolean language plpgsql security definer set search_path to '''' as $$
declare
  _uid uuid := auth.uid();
begin
  -- 1. Explicit auth validation
  if _uid is null then
    raise exception ''not authenticated'';
  end if;

  -- 2. Explicit null/NaN/infinite/out-of-range validation
  if _lat is null or _lng is null or
     _lat = ''NaN''::double precision or _lng = ''NaN''::double precision or
     _lat = ''Infinity''::double precision or _lat = ''-Infinity''::double precision or
     _lng = ''Infinity''::double precision or _lng = ''-Infinity''::double precision or
     not (_lat between -90 and 90) or
     not (_lng between -180 and 180)
  then
    raise exception ''invalid coordinates'';
  end if;

  -- 3. Update caller-owned open SOS only (and only coords+updated_at)
  update public.alerts
  set
    sos_lat = _lat,
    sos_lng = _lng,
    updated_at = now()
  where
    user_id = _uid
    and status = ''open''
    and cause = ''sos'';

  -- Return FOUND (boolean indicating if a row was updated)
  return FOUND;
end;
$$;

revoke execute on function public.update_sos_location(double precision, double precision) from public, anon;
grant execute on function public.update_sos_location(double precision, double precision) to authenticated;"}', 'update_sos_location', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260727090000', '{"-- A user''s monitoring direction is group-scoped. A global open alert may
-- legitimately exist because the user remains monitored in another group,
-- but it must not surface inside a group where this membership opted out.

CREATE OR REPLACE FUNCTION public.get_group_activity_view(_group uuid, _view text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '''' AS $$
DECLARE
  _uid uuid := auth.uid();
  _mode text := coalesce(nullif(btrim(_view), ''''), ''group'');
  _is_owner boolean;
  _i_watching boolean;
  _i_share boolean;
  _members jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION ''not authenticated''; END IF;
  IF _mode NOT IN (''watch'', ''group'') THEN RAISE EXCEPTION ''invalid activity view''; END IF;

  SELECT EXISTS (
           SELECT 1 FROM public.group_members gm
           WHERE gm.group_id = g.id and gm.user_id = _uid
             AND gm.role = ''admin'' and gm.status = ''active''
         ),
         coalesce(me.watching, false)
    INTO _is_owner, _i_watching
  FROM public.groups g
  JOIN public.group_members me
    ON me.group_id = g.id and me.user_id = _uid and me.status = ''active''
  WHERE g.id = _group;
  IF NOT FOUND THEN RAISE EXCEPTION ''forbidden''; END IF;

  SELECT coalesce(us.share_activity, true) INTO _i_share
  FROM public.user_settings us WHERE us.user_id = _uid;
  _i_share := coalesce(_i_share, true);

  SELECT coalesce(jsonb_agg(
    jsonb_build_object(
      ''user_id'', m.user_id,
      ''name'', coalesce(nullif(p.display_name, ''''), left(m.user_id::text, 8)),
      ''is_me'', m.user_id = _uid,
      ''status'',
        CASE
          WHEN m.user_id = _uid THEN ''self''
          WHEN not coalesce(us.share_activity, true) and not coalesce(al.alerted, false) THEN ''hidden''
          WHEN coalesce(al.alerted, false) THEN ''alert''
          WHEN bp.last_at IS NULL THEN ''unknown''
          WHEN bp.last_at > now() - interval ''6 hours'' THEN ''active''
          WHEN bp.last_at > now() - interval ''24 hours'' THEN ''quiet''
          ELSE ''silent''
        END,
      ''hours'',
        CASE
          WHEN bp.last_at IS NULL THEN null
          ELSE floor(extract(epoch from (now() - bp.last_at)) / 3600)::int
        END,
      ''last_behavior_at'', bp.last_at,
      ''last_heartbeat_at'', ds.last_heartbeat_at,
      ''threshold_hours'', round(extract(epoch from private.silence_threshold(m.user_id)) / 3600.0, 2),
      ''alerted'', coalesce(al.alerted, false)
    )
    ORDER BY (m.user_id = _uid) DESC, p.display_name NULLS LAST, m.user_id
  ), ''[]''::jsonb) INTO _members
  FROM public.group_members m
  LEFT JOIN public.profiles p ON p.id = m.user_id
  LEFT JOIN public.user_settings us ON us.user_id = m.user_id
  LEFT JOIN public.device_state ds ON ds.user_id = m.user_id
  LEFT JOIN LATERAL (
    SELECT max(received_at) as last_at
    FROM public.behavior_pings
    WHERE user_id = m.user_id
      AND ingest_version = 2
      AND abs(extract(epoch from (received_at - at))) <= 300
  ) bp ON true
  LEFT JOIN LATERAL (
    SELECT m.monitored AND exists (
      SELECT 1 FROM public.alerts a
      WHERE a.user_id = m.user_id and a.status = ''open''
        AND a.stage in (''group'', ''community'', ''terminal'')
    ) as alerted
  ) al ON true
  WHERE m.group_id = _group
    AND m.status = ''active''
    AND (
      _mode = ''group''
      OR m.user_id = _uid
      OR (_i_watching and m.monitored)
    );

  RETURN jsonb_build_object(
    ''visibility'', CASE WHEN _mode = ''watch'' THEN ''watchers_only'' ELSE ''group_wide'' END,
    ''view'', _mode,
    ''is_owner'', _is_owner,
    ''i_share'', _i_share,
    ''members'', _members
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_group_activity_view(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_group_activity_view(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_group_activity(_group uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '''' AS $$
DECLARE
  _uid uuid := auth.uid();
  _visibility text;
  _is_owner boolean;
  _i_watching boolean;
  _i_share boolean;
  _members jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION ''not authenticated''; END IF;

  SELECT g.activity_visibility,
         EXISTS (
           SELECT 1 FROM public.group_members gm
           WHERE gm.group_id = g.id AND gm.user_id = _uid
             AND gm.role = ''admin'' AND gm.status = ''active''
         ),
         coalesce(me.watching, false)
    INTO _visibility, _is_owner, _i_watching
  FROM public.groups g
  JOIN public.group_members me
    ON me.group_id = g.id AND me.user_id = _uid AND me.status = ''active''
  WHERE g.id = _group;
  IF NOT FOUND THEN RAISE EXCEPTION ''forbidden''; END IF;

  SELECT coalesce(us.share_activity, true) INTO _i_share
  FROM public.user_settings us WHERE us.user_id = _uid;
  _i_share := coalesce(_i_share, true);

  SELECT jsonb_agg(
    jsonb_build_object(
      ''user_id'', m.user_id,
      ''name'', coalesce(nullif(p.display_name, ''''), left(m.user_id::text, 8)),
      ''is_me'', m.user_id = _uid,
      ''status'',
        CASE
          WHEN m.user_id = _uid THEN ''self''
          WHEN NOT coalesce(us.share_activity, true) AND NOT coalesce(al.alerted, false) THEN ''hidden''
          WHEN _visibility = ''watchers_only'' AND NOT _i_watching AND NOT coalesce(al.alerted, false) THEN ''hidden''
          WHEN coalesce(al.alerted, false) THEN ''alert''
          WHEN bp.last_at IS NULL THEN ''unknown''
          WHEN bp.last_at > now() - interval ''6 hours'' THEN ''active''
          WHEN bp.last_at > now() - interval ''24 hours'' THEN ''quiet''
          ELSE ''silent''
        END,
      ''hours'',
        CASE
          WHEN bp.last_at IS NULL THEN null
          ELSE floor(extract(epoch from (now() - bp.last_at)) / 3600)::int
        END,
      ''last_behavior_at'', bp.last_at,
      ''last_heartbeat_at'', ds.last_heartbeat_at,
      ''threshold_hours'', round(extract(epoch from private.silence_threshold(m.user_id)) / 3600.0, 2),
      ''alerted'', coalesce(al.alerted, false)
    )
    ORDER BY (m.user_id = _uid) DESC, p.display_name NULLS LAST, m.user_id
  ) INTO _members
  FROM public.group_members m
  LEFT JOIN public.profiles p ON p.id = m.user_id
  LEFT JOIN public.user_settings us ON us.user_id = m.user_id
  LEFT JOIN public.device_state ds ON ds.user_id = m.user_id
  LEFT JOIN LATERAL (
    SELECT max(received_at) AS last_at
    FROM public.behavior_pings
    WHERE user_id = m.user_id
      AND ingest_version = 2
      AND abs(extract(epoch from (received_at - at))) <= 300
  ) bp ON true
  LEFT JOIN LATERAL (
    SELECT m.monitored AND EXISTS (
      SELECT 1 FROM public.alerts a
      WHERE a.user_id = m.user_id AND a.status = ''open''
        AND a.stage IN (''group'', ''community'', ''terminal'')
    ) AS alerted
  ) al ON true
  WHERE m.group_id = _group AND m.status = ''active'';

  RETURN jsonb_build_object(
    ''visibility'', _visibility,
    ''is_owner'', _is_owner,
    ''i_share'', _i_share,
    ''members'', coalesce(_members, ''[]''::jsonb)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_group_activity(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_group_activity(uuid) TO authenticated;
"}', 'scope_group_alerts_to_monitoring_direction', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260725160000', '{"-- ADR-0023: canonical Routine-mode taxonomy for candidate-only alert learning.
-- This migration deliberately does not alter the live alert state machine.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE routine_pattern IS NOT NULL
      AND routine_pattern NOT IN (
        ''regular_9to5'', ''semester_break'', ''shift_irregular'',
        ''student'', ''shift_worker'', ''flexible''
      )
  ) THEN
    RAISE EXCEPTION ''unknown routine_pattern blocks canonical migration'';
  END IF;
END;
$$;

UPDATE public.profiles
SET routine_pattern = CASE routine_pattern
  WHEN ''student'' THEN ''semester_break''
  WHEN ''shift_worker'' THEN ''shift_irregular''
  WHEN ''flexible'' THEN ''shift_irregular''
  ELSE routine_pattern
END
WHERE routine_pattern IN (''student'', ''shift_worker'', ''flexible'');

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_routine_pattern_canonical
  CHECK (routine_pattern IN (
    ''regular_9to5'', ''semester_break'', ''shift_irregular''
  ));

CREATE OR REPLACE FUNCTION private.canonical_routine_mode(_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''''
AS $$
  SELECT CASE _value
    WHEN ''semester_break'' THEN ''semester_break''
    WHEN ''student'' THEN ''semester_break''
    WHEN ''shift_irregular'' THEN ''shift_irregular''
    WHEN ''shift_worker'' THEN ''shift_irregular''
    WHEN ''flexible'' THEN ''shift_irregular''
    ELSE ''regular_9to5''
  END;
$$;

CREATE TABLE public.routine_mode_cohort_invalidations (
  routine_mode text PRIMARY KEY CHECK (routine_mode IN (
    ''regular_9to5'', ''semester_break'', ''shift_irregular''
  )),
  invalidated_at timestamptz NOT NULL
);

ALTER TABLE public.routine_mode_cohort_invalidations ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION private.invalidate_routine_mode_cohort()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''''
AS $$
BEGIN
  INSERT INTO public.routine_mode_cohort_invalidations (
    routine_mode,
    invalidated_at
  )
  SELECT affected.routine_mode, timestamped.invalidated_at
  FROM (
    SELECT DISTINCT routine_mode
    FROM (
      VALUES
        (private.canonical_routine_mode(OLD.routine_pattern)),
        (private.canonical_routine_mode(NEW.routine_pattern))
    ) AS normalized(routine_mode)
  ) AS affected
  CROSS JOIN (SELECT clock_timestamp() AS invalidated_at) AS timestamped
  ON CONFLICT (routine_mode) DO UPDATE
  SET invalidated_at = EXCLUDED.invalidated_at;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_profile_routine_mode_cohort_invalidation
ON public.profiles;

CREATE TRIGGER on_profile_routine_mode_cohort_invalidation
AFTER UPDATE OF routine_pattern, consent_data_sharing
ON public.profiles
FOR EACH ROW
WHEN (
  OLD.routine_pattern IS DISTINCT FROM NEW.routine_pattern
  OR OLD.consent_data_sharing IS DISTINCT FROM NEW.consent_data_sharing
)
EXECUTE FUNCTION private.invalidate_routine_mode_cohort();

REVOKE ALL PRIVILEGES ON TABLE public.routine_mode_cohort_invalidations
FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON FUNCTION private.canonical_routine_mode(text)
FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL PRIVILEGES ON FUNCTION private.invalidate_routine_mode_cohort()
FROM PUBLIC, anon, authenticated, service_role;
"}', 'canonicalize_routine_modes', 'codex-release-v0.5.21', NULL, NULL),
	('20260725161000', '{"-- ADR-0023: candidate-only, versioned adaptive-alert data boundary.
-- This schema intentionally has no policy, scheduler, realtime publication, or
-- executable evaluator. Later private workers may use it only after their own
-- append-only migration and tests; it has no authority over the live alert path.

CREATE TABLE public.alert_model_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE CHECK (length(trim(name)) BETWEEN 1 AND 120),
  status text NOT NULL CHECK (status IN (''draft'', ''replay'', ''shadow'', ''retired'')),
  config jsonb NOT NULL,
  config_sha256 text NOT NULL CHECK (config_sha256 ~ ''^[a-f0-9]{64}$''),
  evidence_version text NOT NULL CHECK (length(trim(evidence_version)) > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  shadow_enabled_at timestamptz,
  CHECK (status <> ''shadow'' OR shadow_enabled_at IS NOT NULL),
  CHECK (
    jsonb_typeof(config) = ''object''
    AND config ?& ARRAY[
      ''sessionization'', ''context'', ''personal'', ''cohort'',
      ''sensitivity_buffers_minutes'', ''candidate_bounds'', ''sleep_compensation''
    ]
    AND jsonb_typeof(config -> ''sessionization'') = ''object''
    AND (config -> ''sessionization'') ?& ARRAY[''gap_minutes'', ''per_user_day_gap_cap'']
    AND jsonb_typeof(config #> ''{sessionization,gap_minutes}'') = ''number''
    AND (config #>> ''{sessionization,gap_minutes}'')::numeric > 0
    AND jsonb_typeof(config #> ''{sessionization,per_user_day_gap_cap}'') = ''number''
    AND (config #>> ''{sessionization,per_user_day_gap_cap}'')::numeric > 0
    AND jsonb_typeof(config -> ''context'') = ''object''
    AND (config -> ''context'') ?& ARRAY[''definition_version'']
    AND jsonb_typeof(config #> ''{context,definition_version}'') = ''string''
    AND length(trim(config #>> ''{context,definition_version}'')) > 0
    AND jsonb_typeof(config -> ''personal'') = ''object''
    AND (config -> ''personal'') ?& ARRAY[''min_samples'', ''min_support_dates'', ''min_span_days'', ''max_age_days'']
    AND jsonb_typeof(config #> ''{personal,min_samples}'') = ''number''
    AND (config #>> ''{personal,min_samples}'')::numeric > 0
    AND jsonb_typeof(config #> ''{personal,min_support_dates}'') = ''number''
    AND (config #>> ''{personal,min_support_dates}'')::numeric > 0
    AND jsonb_typeof(config #> ''{personal,min_span_days}'') = ''number''
    AND (config #>> ''{personal,min_span_days}'')::numeric > 0
    AND jsonb_typeof(config #> ''{personal,max_age_days}'') = ''number''
    AND (config #>> ''{personal,max_age_days}'')::numeric > 0
    AND jsonb_typeof(config -> ''cohort'') = ''object''
    AND (config -> ''cohort'') ?& ARRAY[''min_contributors'', ''min_support_dates'', ''max_age_days'', ''algorithm'', ''trim_fraction'']
    AND jsonb_typeof(config #> ''{cohort,min_contributors}'') = ''number''
    AND (config #>> ''{cohort,min_contributors}'')::numeric > 0
    AND jsonb_typeof(config #> ''{cohort,min_support_dates}'') = ''number''
    AND (config #>> ''{cohort,min_support_dates}'')::numeric > 0
    AND jsonb_typeof(config #> ''{cohort,max_age_days}'') = ''number''
    AND (config #>> ''{cohort,max_age_days}'')::numeric > 0
    AND jsonb_typeof(config #> ''{cohort,algorithm}'') = ''string''
    AND config #>> ''{cohort,algorithm}'' IN (''weighted_median'', ''trimmed_mean'')
    AND jsonb_typeof(config #> ''{cohort,trim_fraction}'') = ''number''
    AND (config #>> ''{cohort,trim_fraction}'')::numeric >= 0
    AND (config #>> ''{cohort,trim_fraction}'')::numeric < 0.5
    AND jsonb_typeof(config -> ''sensitivity_buffers_minutes'') = ''object''
    AND (config -> ''sensitivity_buffers_minutes'') ?& ARRAY[''high'', ''balanced'', ''low'']
    AND jsonb_typeof(config #> ''{sensitivity_buffers_minutes,high}'') = ''number''
    AND jsonb_typeof(config #> ''{sensitivity_buffers_minutes,balanced}'') = ''number''
    AND jsonb_typeof(config #> ''{sensitivity_buffers_minutes,low}'') = ''number''
    AND config #>> ''{sensitivity_buffers_minutes,high}'' = ''0''
    AND config #>> ''{sensitivity_buffers_minutes,balanced}'' = ''45''
    AND config #>> ''{sensitivity_buffers_minutes,low}'' = ''90''
    AND jsonb_typeof(config -> ''candidate_bounds'') = ''object''
    AND (config -> ''candidate_bounds'') ?& ARRAY[''floor_minutes'', ''ceiling_minutes'']
    AND jsonb_typeof(config #> ''{candidate_bounds,floor_minutes}'') = ''number''
    AND (config #>> ''{candidate_bounds,floor_minutes}'')::numeric >= 0
    AND jsonb_typeof(config #> ''{candidate_bounds,ceiling_minutes}'') = ''number''
    AND (config #>> ''{candidate_bounds,ceiling_minutes}'')::numeric >= (config #>> ''{candidate_bounds,floor_minutes}'')::numeric
    AND jsonb_typeof(config -> ''sleep_compensation'') = ''object''
    AND (config -> ''sleep_compensation'') ?& ARRAY[
      ''max_start_delay_minutes'', ''max_wake_advance_minutes'', ''max_wake_delay_minutes'',
      ''max_update_minutes_per_day'', ''min_positive_nights'', ''timezone_tolerance_minutes''
    ]
    AND jsonb_typeof(config #> ''{sleep_compensation,max_start_delay_minutes}'') = ''number''
    AND (config #>> ''{sleep_compensation,max_start_delay_minutes}'')::numeric >= 0
    AND jsonb_typeof(config #> ''{sleep_compensation,max_wake_advance_minutes}'') = ''number''
    AND (config #>> ''{sleep_compensation,max_wake_advance_minutes}'')::numeric >= 0
    AND jsonb_typeof(config #> ''{sleep_compensation,max_wake_delay_minutes}'') = ''number''
    AND (config #>> ''{sleep_compensation,max_wake_delay_minutes}'')::numeric >= 0
    AND jsonb_typeof(config #> ''{sleep_compensation,max_update_minutes_per_day}'') = ''number''
    AND (config #>> ''{sleep_compensation,max_update_minutes_per_day}'')::numeric >= 0
    AND jsonb_typeof(config #> ''{sleep_compensation,min_positive_nights}'') = ''number''
    AND (config #>> ''{sleep_compensation,min_positive_nights}'')::numeric > 0
    AND jsonb_typeof(config #> ''{sleep_compensation,timezone_tolerance_minutes}'') = ''number''
    AND (config #>> ''{sleep_compensation,timezone_tolerance_minutes}'')::numeric >= 0
  )
);

CREATE TABLE public.alert_gap_profiles (
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  context_key text NOT NULL CHECK (length(trim(context_key)) > 0),
  through_date date NOT NULL,
  neutral_p95_minutes integer NOT NULL CHECK (neutral_p95_minutes > 0),
  sample_count integer NOT NULL CHECK (sample_count > 0),
  distinct_support_dates integer NOT NULL CHECK (distinct_support_dates > 0),
  support_started_on date NOT NULL,
  support_ended_on date NOT NULL,
  latest_evidence_at timestamptz NOT NULL,
  quality_state text NOT NULL CHECK (quality_state IN (''valid'', ''low_support'', ''stale'', ''drift_invalid'', ''coverage_invalid'')),
  confidence double precision NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
  profile_sha256 text NOT NULL CHECK (profile_sha256 ~ ''^[a-f0-9]{64}$''),
  computed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (version_id, user_id, context_key, through_date),
  CHECK (support_ended_on >= support_started_on),
  CHECK (through_date >= support_ended_on)
);

CREATE TABLE public.routine_mode_cohort_priors (
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE RESTRICT,
  routine_mode text NOT NULL CHECK (routine_mode IN (''regular_9to5'', ''semester_break'', ''shift_irregular'')),
  context_key text NOT NULL CHECK (length(trim(context_key)) > 0),
  through_date date NOT NULL,
  contributor_count integer NOT NULL CHECK (contributor_count > 0),
  distinct_support_dates integer NOT NULL CHECK (distinct_support_dates > 0),
  support_started_on date NOT NULL,
  support_ended_on date NOT NULL,
  latest_evidence_at timestamptz NOT NULL,
  neutral_p95_minutes integer NOT NULL CHECK (neutral_p95_minutes > 0),
  quality_state text NOT NULL CHECK (quality_state IN (''valid'', ''low_support'', ''stale'', ''drift_invalid'', ''coverage_invalid'')),
  confidence double precision NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
  algorithm text NOT NULL CHECK (algorithm IN (''weighted_median'', ''trimmed_mean'')),
  config_sha256 text NOT NULL CHECK (config_sha256 ~ ''^[a-f0-9]{64}$''),
  evidence_version text NOT NULL CHECK (length(trim(evidence_version)) > 0),
  input_sha256 text NOT NULL CHECK (input_sha256 ~ ''^[a-f0-9]{64}$''),
  prior_sha256 text NOT NULL CHECK (prior_sha256 ~ ''^[a-f0-9]{64}$''),
  published_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (version_id, routine_mode, context_key, through_date),
  CHECK (support_ended_on >= support_started_on),
  CHECK (through_date >= support_ended_on)
);

CREATE TABLE public.alert_judgment_shadow_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  evaluated_at timestamptz NOT NULL,
  evaluated_minute timestamptz GENERATED ALWAYS AS (
    date_trunc(''minute'', evaluated_at AT TIME ZONE ''UTC'') AT TIME ZONE ''UTC''
  ) STORED,
  basis text NOT NULL CHECK (basis IN (''personal_context'', ''personal_global'', ''routine_cohort'', ''deterministic_emergency'')),
  evaluator_version text NOT NULL CHECK (length(trim(evaluator_version)) > 0),
  context_key text NOT NULL CHECK (length(trim(context_key)) > 0),
  neutral_threshold_minutes integer NOT NULL CHECK (neutral_threshold_minutes >= 0),
  sensitivity_buffer_minutes integer NOT NULL CHECK (sensitivity_buffer_minutes IN (0, 45, 90)),
  candidate_threshold_minutes integer NOT NULL CHECK (candidate_threshold_minutes >= neutral_threshold_minutes),
  effective_silence_minutes double precision NOT NULL CHECK (effective_silence_minutes >= 0),
  candidate_deadline timestamptz NOT NULL,
  would_alert boolean NOT NULL,
  confidence double precision NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
  quality_state text NOT NULL CHECK (quality_state IN (''valid'', ''low_support'', ''stale'', ''drift_invalid'', ''coverage_invalid'')),
  fallback_path text[] NOT NULL CHECK (cardinality(fallback_path) >= 1),
  sleep_interval_provenance jsonb NOT NULL DEFAULT ''[]''::jsonb CHECK (jsonb_typeof(sleep_interval_provenance) = ''array''),
  provenance_sha256 text NOT NULL CHECK (provenance_sha256 ~ ''^[a-f0-9]{64}$''),
  guardian_used_as_activity boolean NOT NULL DEFAULT false CHECK (guardian_used_as_activity = false),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (version_id, user_id, evaluated_minute)
);

CREATE TABLE public.alert_judgment_evaluations (
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE RESTRICT,
  evaluation_kind text NOT NULL CHECK (evaluation_kind IN (''historical_replay'', ''shadow_summary'')),
  evaluated_from timestamptz NOT NULL,
  evaluated_to timestamptz NOT NULL,
  metrics jsonb NOT NULL CHECK (jsonb_typeof(metrics) = ''object''),
  input_sha256 text NOT NULL CHECK (input_sha256 ~ ''^[a-f0-9]{64}$''),
  output_sha256 text NOT NULL CHECK (output_sha256 ~ ''^[a-f0-9]{64}$''),
  evaluator_version text NOT NULL CHECK (length(trim(evaluator_version)) > 0),
  promotion_eligible boolean NOT NULL DEFAULT false CHECK (promotion_eligible = false),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (version_id, evaluation_kind, evaluated_from, evaluated_to),
  CHECK (evaluated_to > evaluated_from)
);

ALTER TABLE public.alert_model_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alert_gap_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routine_mode_cohort_priors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alert_judgment_shadow_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alert_judgment_evaluations ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON TABLE
  public.alert_model_versions,
  public.alert_gap_profiles,
  public.routine_mode_cohort_priors,
  public.alert_judgment_shadow_decisions,
  public.alert_judgment_evaluations
FROM PUBLIC, anon, authenticated, service_role;
"}', 'adaptive_alert_shadow_schema', 'codex-release-v0.5.21', NULL, NULL),
	('20260725162000', '{"-- ADR-0023 Task 3: persisted, prospective sleep-anchor contexts only.
-- This migration deliberately creates no capture scheduler and touches no live alert state.

ALTER TABLE public.alert_model_versions
  ADD CONSTRAINT alert_model_versions_sleep_compensation_late_evidence_check CHECK (
    (
    jsonb_typeof(config #> ''{sleep_compensation,lookback_nights}'') = ''number''
    AND (config #>> ''{sleep_compensation,lookback_nights}'')::numeric > 0
    AND (config #>> ''{sleep_compensation,lookback_nights}'')::numeric = trunc((config #>> ''{sleep_compensation,lookback_nights}'')::numeric)
    AND jsonb_typeof(config #> ''{sleep_compensation,min_late_events_per_night}'') = ''number''
    AND (config #>> ''{sleep_compensation,min_late_events_per_night}'')::numeric > 0
    AND (config #>> ''{sleep_compensation,min_late_events_per_night}'')::numeric = trunc((config #>> ''{sleep_compensation,min_late_events_per_night}'')::numeric)
    AND (config #>> ''{sleep_compensation,min_positive_nights}'')::numeric
      <= (config #>> ''{sleep_compensation,lookback_nights}'')::numeric
    ) IS TRUE
  );

CREATE TABLE public.alert_sleep_night_contexts (
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  anchor_date date NOT NULL,
  timezone text NOT NULL CHECK (length(trim(timezone)) > 0),
  sleep_start_local time NOT NULL,
  sleep_end_local time NOT NULL,
  anchor_starts_at timestamptz NOT NULL,
  anchor_ends_at timestamptz NOT NULL,
  utc_offset_minutes integer NOT NULL CHECK (utc_offset_minutes BETWEEN -840 AND 840),
  coverage_state text NOT NULL CHECK (coverage_state IN (''valid'', ''outage'', ''unknown'')),
  captured_at timestamptz NOT NULL,
  finalized_at timestamptz,
  evidence_version text NOT NULL CHECK (length(trim(evidence_version)) > 0),
  provenance_sha256 text NOT NULL CHECK (provenance_sha256 ~ ''^[a-f0-9]{64}$''),
  PRIMARY KEY (version_id, user_id, anchor_date),
  CHECK (sleep_start_local <> sleep_end_local),
  CHECK (anchor_ends_at > anchor_starts_at),
  CHECK (captured_at <= anchor_starts_at),
  CHECK (
    coverage_state = ''unknown''
    OR (finalized_at IS NOT NULL AND finalized_at >= anchor_ends_at)
  )
);

ALTER TABLE public.alert_sleep_night_contexts ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.alert_sleep_night_contexts
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.candidate_sleep_intervals(
  _user_id uuid,
  _from timestamptz,
  _to timestamptz,
  _version_id uuid
)
RETURNS TABLE (
  starts_at timestamptz,
  ends_at timestamptz,
  basis text,
  confidence double precision,
  provenance jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''''
AS $$
DECLARE
  _config jsonb;
  _config_sha256 text;
  _max_start_delay integer;
  _max_wake_advance integer;
  _max_wake_delay integer;
  _max_update_per_day integer;
  _min_positive integer;
  _lookback integer;
  _min_late_events integer;
  _timezone_tolerance integer;
  _status text;
  _evidence_version text;
  _context record;
  _anchor_start timestamptz;
  _anchor_end timestamptz;
  _midpoint timestamptz;
  _raw_start_delay integer;
  _raw_wake_advance integer;
  _raw_wake_delay integer;
  _start_delay integer;
  _wake_advance integer;
  _wake_delay integer;
  _rate_cap integer;
  _first_count integer;
  _second_count integer;
  _prior_count integer;
  _prior_start_cap_applied boolean;
  _quality_reason text;
  _cap_reasons text[];
  _offset_minutes integer;
BEGIN
  IF _user_id IS NULL OR _version_id IS NULL OR _from IS NULL OR _to IS NULL OR _from >= _to THEN
    RETURN;
  END IF;

  SELECT v.config, v.config_sha256, v.status, v.evidence_version
    INTO _config, _config_sha256, _status, _evidence_version
  FROM public.alert_model_versions AS v
  WHERE v.id = _version_id;

  IF NOT FOUND
     OR _status NOT IN (''replay'', ''shadow'')
     OR _evidence_version <> ''canonical-v2''
     OR _config_sha256 <> encode(extensions.digest(_config::text, ''sha256''), ''hex'') THEN
    RETURN;
  END IF;

  BEGIN
    _max_start_delay := (_config #>> ''{sleep_compensation,max_start_delay_minutes}'')::integer;
    _max_wake_advance := (_config #>> ''{sleep_compensation,max_wake_advance_minutes}'')::integer;
    _max_wake_delay := (_config #>> ''{sleep_compensation,max_wake_delay_minutes}'')::integer;
    _max_update_per_day := (_config #>> ''{sleep_compensation,max_update_minutes_per_day}'')::integer;
    _min_positive := (_config #>> ''{sleep_compensation,min_positive_nights}'')::integer;
    _lookback := (_config #>> ''{sleep_compensation,lookback_nights}'')::integer;
    _min_late_events := (_config #>> ''{sleep_compensation,min_late_events_per_night}'')::integer;
    _timezone_tolerance := (_config #>> ''{sleep_compensation,timezone_tolerance_minutes}'')::integer;
  EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
    RETURN;
  END;

  IF _max_start_delay < 0 OR _max_wake_advance < 0 OR _max_wake_delay < 0
     OR _max_update_per_day < 0 OR _min_positive <= 0 OR _lookback <= 0
     OR _min_late_events <= 0 OR _min_positive > _lookback OR _timezone_tolerance < 0 THEN
    RETURN;
  END IF;

  FOR _context IN
    SELECT c.*
    FROM public.alert_sleep_night_contexts AS c
    WHERE c.version_id = _version_id
      AND c.user_id = _user_id
      AND c.evidence_version = ''canonical-v2''
      AND c.anchor_starts_at < _to
      AND c.anchor_ends_at > _from
    ORDER BY c.anchor_starts_at
  LOOP
    -- A malformed or incompatible persisted context is not a reason to infer a window.
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names AS z WHERE z.name = _context.timezone)
       OR _context.sleep_start_local = _context.sleep_end_local
       OR _context.anchor_ends_at <= _context.anchor_starts_at
       OR _context.captured_at > _context.anchor_starts_at
       OR (_context.coverage_state IN (''valid'', ''outage'')
           AND (_context.finalized_at IS NULL OR _context.finalized_at < _context.anchor_ends_at)) THEN
      CONTINUE;
    END IF;

    _anchor_start := ((_context.anchor_date + _context.sleep_start_local) AT TIME ZONE _context.timezone);
    _anchor_end := ((
      _context.anchor_date
      + CASE WHEN _context.sleep_end_local <= _context.sleep_start_local THEN 1 ELSE 0 END
      + _context.sleep_end_local
    ) AT TIME ZONE _context.timezone);
    _offset_minutes := extract(epoch FROM (((_context.anchor_starts_at AT TIME ZONE _context.timezone) AT TIME ZONE ''UTC'') - _context.anchor_starts_at))::integer / 60;

    IF _anchor_start <> _context.anchor_starts_at
       OR _anchor_end <> _context.anchor_ends_at
       OR _offset_minutes <> _context.utc_offset_minutes THEN
      CONTINUE;
    END IF;

    _midpoint := _anchor_start + ((_anchor_end - _anchor_start) / 2);
    SELECT
      count(*) FILTER (WHERE b.received_at >= _anchor_start AND b.received_at < _midpoint)::integer,
      count(*) FILTER (WHERE b.received_at >= _midpoint AND b.received_at < _anchor_end)::integer,
      coalesce(floor(extract(epoch FROM (max(b.received_at) FILTER (WHERE b.received_at >= _anchor_start AND b.received_at < _midpoint) - _anchor_start)) / 60)::integer, 0),
      coalesce(floor(extract(epoch FROM (_anchor_end - min(b.received_at) FILTER (WHERE b.received_at >= _midpoint AND b.received_at < _anchor_end))) / 60)::integer, 0)
    INTO _first_count, _second_count, _raw_start_delay, _raw_wake_advance
    FROM public.behavior_pings AS b
    WHERE b.user_id = _user_id
      AND b.ingest_version = 2
      AND abs(extract(epoch FROM (b.received_at - b.at))) <= 300
      AND b.at < _to
      AND b.received_at < _to;

    _cap_reasons := ARRAY[]::text[];
    IF _raw_start_delay > _max_start_delay THEN
      _cap_reasons := pg_catalog.array_append(_cap_reasons, ''max_start_delay_minutes'');
    END IF;
    IF _raw_wake_advance > _max_wake_advance THEN
      _cap_reasons := pg_catalog.array_append(_cap_reasons, ''max_wake_advance_minutes'');
    END IF;
    _start_delay := least(_max_start_delay, greatest(0, _raw_start_delay));
    _wake_advance := least(_max_wake_advance, greatest(0, _raw_wake_advance));
    _wake_delay := 0;
    _raw_wake_delay := 0;
    _rate_cap := 0;
    _prior_count := 0;
    _prior_start_cap_applied := false;
    _quality_reason := CASE WHEN _context.coverage_state = ''valid'' THEN ''coverage_valid'' ELSE ''coverage_'' || _context.coverage_state END;

    IF _context.coverage_state = ''valid'' THEN
      WITH prior_contexts AS (
        SELECT p.anchor_date, p.anchor_starts_at, p.anchor_ends_at,
          p.anchor_starts_at + ((p.anchor_ends_at - p.anchor_starts_at) / 2) AS midpoint
        FROM public.alert_sleep_night_contexts AS p
        WHERE p.version_id = _version_id
          AND p.user_id = _user_id
          AND p.coverage_state = ''valid''
          AND p.evidence_version = ''canonical-v2''
          AND p.anchor_date < _context.anchor_date
          AND p.anchor_date >= (_context.anchor_date - _lookback)
          AND p.timezone = _context.timezone
          AND abs(p.utc_offset_minutes - _context.utc_offset_minutes) <= _timezone_tolerance
          AND p.captured_at <= p.anchor_starts_at
          AND p.finalized_at >= p.anchor_ends_at
          AND ((p.anchor_date + p.sleep_start_local) AT TIME ZONE p.timezone) = p.anchor_starts_at
          AND ((
            p.anchor_date
            + CASE WHEN p.sleep_end_local <= p.sleep_start_local THEN 1 ELSE 0 END
            + p.sleep_end_local
          ) AT TIME ZONE p.timezone) = p.anchor_ends_at
          AND extract(epoch FROM (((p.anchor_starts_at AT TIME ZONE p.timezone) AT TIME ZONE ''UTC'') - p.anchor_starts_at))::integer / 60 = p.utc_offset_minutes
      ), prior_delays AS (
        SELECT p.anchor_date,
          floor(extract(epoch FROM (max(b.received_at) - p.anchor_starts_at)) / 60)::integer AS raw_delay_minutes,
          least(_max_start_delay, floor(extract(epoch FROM (max(b.received_at) - p.anchor_starts_at)) / 60)::integer) AS delay_minutes
        FROM prior_contexts AS p
        JOIN public.behavior_pings AS b
          ON b.user_id = _user_id
         AND b.ingest_version = 2
         AND abs(extract(epoch FROM (b.received_at - b.at))) <= 300
         AND b.at < _to
         AND b.received_at < _to
         AND b.received_at >= p.anchor_starts_at
         AND b.received_at < p.midpoint
        GROUP BY p.anchor_date, p.anchor_starts_at
        HAVING count(*) >= _min_late_events
      )
      SELECT count(*)::integer,
        coalesce(percentile_disc(0.5) WITHIN GROUP (ORDER BY delay_minutes)::integer, 0),
        coalesce(bool_or(raw_delay_minutes > _max_start_delay), false)
      INTO _prior_count, _raw_wake_delay, _prior_start_cap_applied
      FROM prior_delays;

      IF _prior_count >= _min_positive THEN
        _rate_cap := greatest(0, _prior_count - _min_positive + 1) * _max_update_per_day;
        IF _prior_start_cap_applied THEN
          _cap_reasons := pg_catalog.array_append(_cap_reasons, ''prior_max_start_delay_minutes'');
        END IF;
        IF _raw_wake_delay > _max_wake_delay THEN
          _cap_reasons := pg_catalog.array_append(_cap_reasons, ''max_wake_delay_minutes'');
        END IF;
        IF least(_raw_wake_delay, _max_wake_delay) > _rate_cap THEN
          _cap_reasons := pg_catalog.array_append(_cap_reasons, ''max_update_minutes_per_day'');
        END IF;
        _wake_delay := least(_max_wake_delay, _raw_wake_delay, _rate_cap);
        _quality_reason := ''coverage_valid_prior_positive'';
      ELSE
        _wake_delay := 0;
      END IF;
    END IF;

    starts_at := _anchor_start + make_interval(mins => _start_delay);
    ends_at := _anchor_end - make_interval(mins => _wake_advance) + make_interval(mins => _wake_delay);
    IF starts_at >= ends_at THEN
      CONTINUE;
    END IF;

    basis := CASE WHEN _start_delay > 0 OR _wake_advance > 0 OR _wake_delay > 0
      THEN ''positive_evidence_adjusted'' ELSE ''configured_anchor'' END;
    confidence := CASE
      WHEN _start_delay > 0 OR _wake_advance > 0 THEN 1.0
      WHEN _wake_delay > 0 THEN least(1.0, _prior_count::double precision / _min_positive::double precision)
      ELSE 0.0
    END;
    provenance := jsonb_build_object(
      ''config_sha256'', _config_sha256,
      ''anchor_starts_at'', _anchor_start,
      ''anchor_ends_at'', _anchor_end,
      ''first_half_positive_count'', _first_count,
      ''second_half_positive_count'', _second_count,
      ''prior_positive_night_count'', _prior_count,
      ''start_delay_minutes'', _start_delay,
      ''wake_advance_minutes'', _wake_advance,
      ''wake_delay_minutes'', _wake_delay,
      ''caps'', jsonb_build_object(''max_start_delay_minutes'', _max_start_delay, ''max_wake_advance_minutes'', _max_wake_advance, ''max_wake_delay_minutes'', _max_wake_delay, ''max_update_minutes_per_day'', _max_update_per_day),
      ''confidence'', confidence,
      ''cap_reason'', coalesce(pg_catalog.array_to_string(_cap_reasons, '',''), ''none''),
      ''timezone'', _context.timezone,
      ''utc_offset_minutes'', _context.utc_offset_minutes,
      ''coverage_state'', _context.coverage_state,
      ''quality_reason'', _quality_reason
    );
    RETURN NEXT;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION private.candidate_sleep_intervals(uuid, timestamptz, timestamptz, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
"}', 'adaptive_sleep_candidate', 'codex-release-v0.5.21', NULL, NULL),
	('20260725163000', '{"-- ADR-0023 Task 4: provenance-qualified session and personal gap profiles only.
-- No scheduler, trigger, realtime publication, or live-alert mutation is introduced here.

ALTER TABLE public.alert_model_versions
  ADD CONSTRAINT alert_model_versions_gap_profile_contract_check CHECK (
    (
      jsonb_typeof(config #> ''{sessionization,training_horizon_days}'') = ''number''
      AND (config #>> ''{sessionization,training_horizon_days}'')::numeric > 0
      AND (config #>> ''{sessionization,training_horizon_days}'')::numeric = trunc((config #>> ''{sessionization,training_horizon_days}'')::numeric)
      AND jsonb_typeof(config #> ''{sessionization,intervention_window_minutes}'') = ''number''
      AND (config #>> ''{sessionization,intervention_window_minutes}'')::numeric >= 0
      AND (config #>> ''{sessionization,intervention_window_minutes}'')::numeric = trunc((config #>> ''{sessionization,intervention_window_minutes}'')::numeric)
      AND jsonb_typeof(config #> ''{context,day_partition}'') = ''string''
      AND config #>> ''{context,day_partition}'' IN (''all_days'', ''weekday_weekend'')
      AND jsonb_typeof(config #> ''{context,hour_bucket_minutes}'') = ''number''
      AND (config #>> ''{context,hour_bucket_minutes}'')::numeric > 0
      AND (config #>> ''{context,hour_bucket_minutes}'')::numeric = trunc((config #>> ''{context,hour_bucket_minutes}'')::numeric)
      AND mod(1440, (config #>> ''{context,hour_bucket_minutes}'')::integer) = 0
      AND jsonb_typeof(config #> ''{personal,confidence_formula_version}'') = ''string''
      AND config #>> ''{personal,confidence_formula_version}'' = ''support_ratio_v1''
    ) IS TRUE
  );

ALTER TABLE public.alert_gap_profiles
  ADD COLUMN input_sha256 text NOT NULL DEFAULT repeat(''0'', 64)
    CHECK (input_sha256 ~ ''^[a-f0-9]{64}$'');

CREATE TABLE public.alert_observation_coverage_intervals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  timezone text NOT NULL CHECK (length(trim(timezone)) > 0),
  utc_offset_minutes integer NOT NULL CHECK (utc_offset_minutes BETWEEN -840 AND 840),
  activity_coverage_state text NOT NULL CHECK (activity_coverage_state IN (''valid'', ''outage'', ''unknown'')),
  intervention_coverage_state text NOT NULL CHECK (intervention_coverage_state IN (''valid'', ''incomplete'', ''unknown'')),
  sleep_context_state text NOT NULL CHECK (sleep_context_state IN (''valid'', ''incomplete'', ''unknown'')),
  captured_at timestamptz NOT NULL,
  finalized_at timestamptz,
  evidence_version text NOT NULL CHECK (length(trim(evidence_version)) > 0),
  provenance_sha256 text NOT NULL CHECK (provenance_sha256 ~ ''^[a-f0-9]{64}$''),
  CHECK (ends_at > starts_at),
  CHECK (captured_at <= ends_at),
  CHECK (finalized_at IS NULL OR finalized_at >= ends_at)
);

CREATE INDEX alert_observation_coverage_intervals_version_user_time_idx
  ON public.alert_observation_coverage_intervals (version_id, user_id, starts_at, ends_at);

CREATE TABLE public.alert_intervention_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  occurred_at timestamptz NOT NULL,
  kind text NOT NULL CHECK (kind IN (''self_alert'', ''self_prompt'', ''checkin_prompt'', ''concern_prompt'')),
  captured_at timestamptz NOT NULL,
  evidence_version text NOT NULL CHECK (length(trim(evidence_version)) > 0),
  provenance_sha256 text NOT NULL CHECK (provenance_sha256 ~ ''^[a-f0-9]{64}$''),
  CHECK (captured_at >= occurred_at)
);

CREATE INDEX alert_intervention_events_version_user_time_idx
  ON public.alert_intervention_events (version_id, user_id, occurred_at);

ALTER TABLE public.alert_observation_coverage_intervals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alert_intervention_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.alert_observation_coverage_intervals, public.alert_intervention_events
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.qualified_behavior_sessions(
  _user_id uuid,
  _from timestamptz,
  _to timestamptz,
  _version_id uuid
)
RETURNS TABLE (
  session_start timestamptz,
  session_end timestamptz,
  context_key text,
  evidence_count integer,
  quality_state text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''''
SET TimeZone = ''UTC''
AS $$
DECLARE
  _config jsonb;
  _status text;
  _evidence_version text;
  _config_sha256 text;
  _gap_minutes integer;
  _intervention_minutes integer;
  _definition text;
  _day_partition text;
  _bucket_minutes integer;
BEGIN
  IF _user_id IS NULL OR _version_id IS NULL OR _from IS NULL OR _to IS NULL OR _from >= _to THEN
    RETURN;
  END IF;

  SELECT config, status, evidence_version, config_sha256
    INTO _config, _status, _evidence_version, _config_sha256
  FROM public.alert_model_versions
  WHERE id = _version_id;

  IF NOT FOUND
     OR _status NOT IN (''replay'', ''shadow'')
     OR _evidence_version <> ''canonical-v2''
     OR _config_sha256 <> encode(extensions.digest(_config::text, ''sha256''), ''hex'') THEN
    RETURN;
  END IF;

  BEGIN
    _gap_minutes := (_config #>> ''{sessionization,gap_minutes}'')::integer;
    _intervention_minutes := (_config #>> ''{sessionization,intervention_window_minutes}'')::integer;
    _definition := _config #>> ''{context,definition_version}'';
    _day_partition := _config #>> ''{context,day_partition}'';
    _bucket_minutes := (_config #>> ''{context,hour_bucket_minutes}'')::integer;
  EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
    RETURN;
  END;

  IF _gap_minutes <= 0 OR _intervention_minutes < 0 OR _definition IS NULL
     OR _day_partition NOT IN (''all_days'', ''weekday_weekend'')
     OR _bucket_minutes <= 0 OR mod(1440, _bucket_minutes) <> 0 THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH admitted AS (
    SELECT p.id, p.received_at, c.id AS coverage_id, c.timezone, c.utc_offset_minutes
    FROM public.behavior_pings AS p
    JOIN public.alert_observation_coverage_intervals AS c
      ON c.version_id = _version_id
     AND c.user_id = _user_id
     AND c.starts_at <= p.received_at
     AND c.ends_at > p.received_at
     AND c.activity_coverage_state = ''valid''
     AND c.intervention_coverage_state = ''valid''
     AND c.sleep_context_state = ''valid''
     AND c.evidence_version = ''canonical-v2''
     AND c.finalized_at IS NOT NULL
     AND c.finalized_at >= c.ends_at
     AND c.finalized_at < _to
    CROSS JOIN LATERAL (
      SELECT count(*) AS matching_coverage
      FROM public.alert_observation_coverage_intervals AS cc
      WHERE cc.version_id = _version_id
        AND cc.user_id = _user_id
        AND cc.starts_at <= p.received_at
        AND cc.ends_at > p.received_at
        AND cc.activity_coverage_state = ''valid''
        AND cc.intervention_coverage_state = ''valid''
        AND cc.sleep_context_state = ''valid''
        AND cc.evidence_version = ''canonical-v2''
        AND cc.finalized_at IS NOT NULL
        AND cc.finalized_at >= cc.ends_at
        AND cc.finalized_at < _to
    ) AS coverage_count
    WHERE p.user_id = _user_id
      AND p.ingest_version = 2
      AND p.received_at >= _from
      AND p.received_at < _to
      AND p.at < _to
      AND abs(extract(epoch FROM (p.received_at - p.at))) <= 300
      AND coverage_count.matching_coverage = 1
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names z WHERE z.name = c.timezone)
      AND floor(extract(epoch FROM (((p.received_at AT TIME ZONE c.timezone) AT TIME ZONE ''UTC'') - p.received_at)) / 60)::integer = c.utc_offset_minutes
  ), marked AS (
    SELECT *, CASE WHEN lag(received_at) OVER (ORDER BY received_at, id) IS NULL
                       OR received_at - lag(received_at) OVER (ORDER BY received_at, id) > make_interval(mins => _gap_minutes)
                       OR coverage_id IS DISTINCT FROM lag(coverage_id) OVER (ORDER BY received_at, id)
                       OR timezone IS DISTINCT FROM lag(timezone) OVER (ORDER BY received_at, id)
                       OR utc_offset_minutes IS DISTINCT FROM lag(utc_offset_minutes) OVER (ORDER BY received_at, id)
                    THEN 1 ELSE 0 END AS starts_session
    FROM admitted
  ), grouped AS (
    SELECT *, sum(starts_session) OVER (ORDER BY received_at, id) AS session_no
    FROM marked
  ), summarized AS (
    SELECT min(received_at) AS session_start,
      max(received_at) AS session_end,
      (array_agg(timezone ORDER BY received_at, id))[1] AS timezone,
      count(*)::integer AS evidence_count
    FROM grouped
    GROUP BY session_no
  )
  SELECT s.session_start,
    s.session_end,
    concat(
      _definition, '':'',
      CASE WHEN _day_partition = ''all_days'' THEN ''all_days''
           WHEN extract(isodow FROM s.session_start AT TIME ZONE s.timezone) BETWEEN 1 AND 5 THEN ''weekday''
           ELSE ''weekend'' END,
      '':h'', lpad((floor(((extract(hour FROM s.session_start AT TIME ZONE s.timezone) * 60 + extract(minute FROM s.session_start AT TIME ZONE s.timezone)) / _bucket_minutes))::integer * _bucket_minutes)::text, 4, ''0'')
    )::text AS context_key,
    s.evidence_count,
    CASE WHEN EXISTS (
      SELECT 1 FROM public.alert_intervention_events AS i
      WHERE i.version_id = _version_id
        AND i.user_id = _user_id
        AND i.evidence_version = ''canonical-v2''
        AND i.occurred_at >= s.session_start - make_interval(mins => _intervention_minutes)
        AND i.occurred_at <= s.session_start
        AND i.captured_at < _to
    ) THEN ''intervention_excluded'' ELSE ''valid'' END::text AS quality_state
  FROM summarized AS s
  ORDER BY s.session_start;
END;
$$;

CREATE FUNCTION private.rebuild_alert_gap_profiles(
  _version_id uuid,
  _through_date date
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET TimeZone = ''UTC''
AS $$
DECLARE
  _config jsonb;
  _status text;
  _evidence_version text;
  _config_sha256 text;
  _horizon_days integer;
  _daily_cap integer;
  _min_samples integer;
  _min_dates integer;
  _min_span integer;
  _max_age integer;
  _cutoff timestamptz;
  _from timestamptz;
  _profiles_written integer := 0;
  _profiles_deleted integer := 0;
  _completed_gaps integer := 0;
BEGIN
  IF _version_id IS NULL OR _through_date IS NULL THEN
    RETURN jsonb_build_object(''profiles_written'', 0, ''profiles_deleted'', 0, ''completed_gaps'', 0, ''explicit_quiet_minutes'', 0);
  END IF;

  SELECT config, status, evidence_version, config_sha256
    INTO _config, _status, _evidence_version, _config_sha256
  FROM public.alert_model_versions
  WHERE id = _version_id;

  IF NOT FOUND
     OR _status NOT IN (''replay'', ''shadow'')
     OR _evidence_version <> ''canonical-v2''
     OR _config_sha256 <> encode(extensions.digest(_config::text, ''sha256''), ''hex'') THEN
    RETURN jsonb_build_object(''profiles_written'', 0, ''profiles_deleted'', 0, ''completed_gaps'', 0, ''explicit_quiet_minutes'', 0);
  END IF;

  BEGIN
    _horizon_days := (_config #>> ''{sessionization,training_horizon_days}'')::integer;
    _daily_cap := (_config #>> ''{sessionization,per_user_day_gap_cap}'')::integer;
    _min_samples := (_config #>> ''{personal,min_samples}'')::integer;
    _min_dates := (_config #>> ''{personal,min_support_dates}'')::integer;
    _min_span := (_config #>> ''{personal,min_span_days}'')::integer;
    _max_age := (_config #>> ''{personal,max_age_days}'')::integer;
  EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
    RETURN jsonb_build_object(''profiles_written'', 0, ''profiles_deleted'', 0, ''completed_gaps'', 0, ''explicit_quiet_minutes'', 0);
  END;

  IF _horizon_days <= 0 OR _daily_cap <= 0 OR _min_samples <= 0 OR _min_dates <= 0 OR _min_span <= 0 OR _max_age <= 0 THEN
    RETURN jsonb_build_object(''profiles_written'', 0, ''profiles_deleted'', 0, ''completed_gaps'', 0, ''explicit_quiet_minutes'', 0);
  END IF;

  _cutoff := ((_through_date + 1)::timestamp AT TIME ZONE ''UTC'');
  _from := _cutoff - make_interval(days => _horizon_days);
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(_version_id::text || '':'' || _through_date::text, 0));
  DROP TABLE IF EXISTS pg_temp._alert_gap_profile_build;

  CREATE TEMP TABLE _alert_gap_profile_build ON COMMIT DROP AS
  WITH users AS (
    SELECT DISTINCT c.user_id
    FROM public.alert_observation_coverage_intervals AS c
    WHERE c.version_id = _version_id
      AND c.starts_at < _cutoff
      AND c.ends_at > _from
  ), sessions AS (
    SELECT u.user_id, s.*
    FROM users AS u
    CROSS JOIN LATERAL private.qualified_behavior_sessions(u.user_id, _from, _cutoff, _version_id) AS s
  ), paired AS (
    SELECT *, lead(session_start) OVER (PARTITION BY user_id ORDER BY session_start) AS next_start,
      lead(quality_state) OVER (PARTITION BY user_id ORDER BY session_start) AS next_quality
    FROM sessions
  ), coverage_gaps AS (
    SELECT p.user_id, p.session_end, p.next_start, p.context_key,
      c.id AS coverage_id, c.timezone, c.utc_offset_minutes,
      c.provenance_sha256 AS coverage_provenance_sha256
    FROM paired AS p
    JOIN public.alert_observation_coverage_intervals AS c
      ON c.version_id = _version_id
     AND c.user_id = p.user_id
     AND c.starts_at <= p.session_end
     AND c.ends_at >= p.next_start
     AND c.activity_coverage_state = ''valid''
     AND c.intervention_coverage_state = ''valid''
     AND c.sleep_context_state = ''valid''
     AND c.evidence_version = ''canonical-v2''
     AND c.finalized_at IS NOT NULL
     AND c.finalized_at >= c.ends_at
     AND c.finalized_at < _cutoff
    CROSS JOIN LATERAL (
      SELECT count(*) AS matching_coverage
      FROM public.alert_observation_coverage_intervals AS cc
      WHERE cc.version_id = _version_id
        AND cc.user_id = p.user_id
        AND cc.starts_at <= p.session_end
        AND cc.ends_at >= p.next_start
        AND cc.activity_coverage_state = ''valid''
        AND cc.intervention_coverage_state = ''valid''
        AND cc.sleep_context_state = ''valid''
        AND cc.evidence_version = ''canonical-v2''
        AND cc.finalized_at IS NOT NULL
        AND cc.finalized_at >= cc.ends_at
        AND cc.finalized_at < _cutoff
    ) AS coverage_count
    WHERE p.next_start IS NOT NULL
      AND p.quality_state = ''valid''
      AND p.next_quality = ''valid''
      AND coverage_count.matching_coverage = 1
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names z WHERE z.name = c.timezone)
      AND floor(extract(epoch FROM (((p.session_end AT TIME ZONE c.timezone) AT TIME ZONE ''UTC'') - p.session_end)) / 60)::integer = c.utc_offset_minutes
      AND NOT EXISTS (
        SELECT 1 FROM public.alert_intervention_events AS i
        WHERE i.version_id = _version_id
          AND i.user_id = p.user_id
          AND i.evidence_version = ''canonical-v2''
          AND i.occurred_at >= p.session_end
          AND i.occurred_at < p.next_start
          AND i.captured_at < _cutoff
      )
  ), effective AS (
    SELECT g.*,
      greatest(0::numeric, extract(epoch FROM (g.next_start - g.session_end)) - coalesce(sleep.sleep_seconds, 0))::double precision AS effective_seconds,
      sleep.sleep_provenance_sha256
    FROM coverage_gaps AS g
    CROSS JOIN LATERAL (
      WITH raw_sleep AS (
        SELECT si.starts_at, si.ends_at, si.basis, si.confidence, si.provenance,
          tstzrange(greatest(si.starts_at, g.session_end), least(si.ends_at, g.next_start), ''[)'') AS clipped_range
        FROM private.candidate_sleep_intervals(g.user_id, g.session_end, g.next_start, _version_id) AS si
        WHERE si.starts_at < g.next_start AND si.ends_at > g.session_end
      ), merged AS (
        SELECT unnest(range_agg(clipped_range)) AS r
        FROM raw_sleep
      )
      SELECT
        coalesce((SELECT sum(extract(epoch FROM (upper(r) - lower(r)))) FROM merged), 0)::double precision AS sleep_seconds,
        encode(extensions.digest(coalesce((
          SELECT jsonb_agg(
            jsonb_build_object(
              ''starts_at_utc'', to_char(starts_at AT TIME ZONE ''UTC'', ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
              ''ends_at_utc'', to_char(ends_at AT TIME ZONE ''UTC'', ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
              ''basis'', basis,
              ''confidence'', confidence,
              ''provenance'', provenance
            ) ORDER BY starts_at, ends_at, basis, confidence, provenance::text
          )
          FROM raw_sleep
        ), ''[]''::jsonb)::text, ''sha256''), ''hex'') AS sleep_provenance_sha256
    ) AS sleep
  ), capped AS (
    SELECT *, (next_start AT TIME ZONE timezone)::date AS local_date,
      row_number() OVER (
        PARTITION BY user_id, (next_start AT TIME ZONE timezone)::date
        ORDER BY md5(
          _version_id::text || '':'' || user_id::text || '':''
          || to_char(session_end AT TIME ZONE ''UTC'', ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'') || '':''
          || to_char(next_start AT TIME ZONE ''UTC'', ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'')
        )
      ) AS daily_rank
    FROM effective
    WHERE effective_seconds > 0
  ), selected AS (
    SELECT * FROM capped WHERE daily_rank <= _daily_cap
  ), grouped AS (
    SELECT user_id, ''personal_global''::text AS context_key, session_end, next_start, local_date, effective_seconds,
      coverage_id, timezone, utc_offset_minutes, coverage_provenance_sha256, sleep_provenance_sha256
    FROM selected
    UNION ALL
    SELECT user_id, context_key, session_end, next_start, local_date, effective_seconds,
      coverage_id, timezone, utc_offset_minutes, coverage_provenance_sha256, sleep_provenance_sha256
    FROM selected
  ), aggregate_inputs AS (
    SELECT user_id, context_key,
      count(*)::integer AS sample_count,
      count(DISTINCT local_date)::integer AS distinct_support_dates,
      min(local_date) AS support_started_on,
      max(local_date) AS support_ended_on,
      max(next_start) AS latest_evidence_at,
      ceil(percentile_disc(0.95) WITHIN GROUP (ORDER BY effective_seconds) / 60.0)::integer AS neutral_p95_minutes,
      jsonb_agg(jsonb_build_object(
        ''session_end_utc'', to_char(session_end AT TIME ZONE ''UTC'', ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
        ''next_start_utc'', to_char(next_start AT TIME ZONE ''UTC'', ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
        ''local_date'', local_date,
        ''effective_seconds'', effective_seconds,
        ''coverage_id'', coverage_id,
        ''coverage_timezone'', timezone,
        ''coverage_utc_offset_minutes'', utc_offset_minutes,
        ''coverage_provenance_sha256'', coverage_provenance_sha256,
        ''sleep_provenance_sha256'', sleep_provenance_sha256
      ) ORDER BY session_end, next_start, coverage_id) AS gap_inputs
    FROM grouped
    GROUP BY user_id, context_key
  ), hashes AS (
    SELECT a.*, encode(extensions.digest(jsonb_build_object(
      ''version_id'', _version_id, ''through_date'', _through_date, ''config_sha256'', _config_sha256,
      ''evidence_version'', _evidence_version, ''context_key'', context_key, ''gaps'', gap_inputs
    )::text, ''sha256''), ''hex'') AS input_sha256
    FROM aggregate_inputs AS a
  ), prepared AS (
    SELECT h.*,
      CASE WHEN h.latest_evidence_at < _cutoff - make_interval(days => _max_age) THEN ''stale''
           WHEN h.sample_count >= _min_samples AND h.distinct_support_dates >= _min_dates
             AND (h.support_ended_on - h.support_started_on + 1) >= _min_span THEN ''valid''
           ELSE ''low_support'' END::text AS quality_state,
      CASE WHEN h.latest_evidence_at < _cutoff - make_interval(days => _max_age) THEN 0::double precision
           ELSE least(1::double precision,
             h.sample_count::double precision / _min_samples::double precision,
             h.distinct_support_dates::double precision / _min_dates::double precision,
             (h.support_ended_on - h.support_started_on + 1)::double precision / _min_span::double precision)
      END AS confidence
    FROM hashes AS h
  )
  SELECT p.user_id, p.context_key, _through_date AS through_date, p.neutral_p95_minutes,
    p.sample_count, p.distinct_support_dates, p.support_started_on, p.support_ended_on,
    p.latest_evidence_at, p.quality_state, p.confidence, p.input_sha256,
    encode(extensions.digest(jsonb_build_object(
      ''version_id'', _version_id, ''user_id'', p.user_id, ''context_key'', p.context_key,
      ''through_date'', _through_date, ''neutral_p95_minutes'', p.neutral_p95_minutes,
      ''sample_count'', p.sample_count, ''distinct_support_dates'', p.distinct_support_dates,
      ''support_started_on'', p.support_started_on, ''support_ended_on'', p.support_ended_on,
      ''latest_evidence_at_utc'', to_char(p.latest_evidence_at AT TIME ZONE ''UTC'', ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''), ''quality_state'', p.quality_state,
      ''confidence'', p.confidence, ''input_sha256'', p.input_sha256
    )::text, ''sha256''), ''hex'') AS profile_sha256
  FROM prepared AS p;

  SELECT coalesce(sum(sample_count) FILTER (WHERE context_key = ''personal_global''), 0)::integer
    INTO _completed_gaps
  FROM pg_temp._alert_gap_profile_build;

  INSERT INTO public.alert_gap_profiles AS target (
    version_id, user_id, context_key, through_date, neutral_p95_minutes, sample_count,
    distinct_support_dates, support_started_on, support_ended_on, latest_evidence_at,
    quality_state, confidence, profile_sha256, input_sha256
  )
  SELECT _version_id, user_id, context_key, through_date, neutral_p95_minutes, sample_count,
    distinct_support_dates, support_started_on, support_ended_on, latest_evidence_at,
    quality_state, confidence, profile_sha256, input_sha256
  FROM pg_temp._alert_gap_profile_build
  ON CONFLICT (version_id, user_id, context_key, through_date) DO UPDATE
  SET neutral_p95_minutes = EXCLUDED.neutral_p95_minutes,
      sample_count = EXCLUDED.sample_count,
      distinct_support_dates = EXCLUDED.distinct_support_dates,
      support_started_on = EXCLUDED.support_started_on,
      support_ended_on = EXCLUDED.support_ended_on,
      latest_evidence_at = EXCLUDED.latest_evidence_at,
      quality_state = EXCLUDED.quality_state,
      confidence = EXCLUDED.confidence,
      profile_sha256 = EXCLUDED.profile_sha256,
      input_sha256 = EXCLUDED.input_sha256,
      computed_at = clock_timestamp()
  WHERE target.input_sha256 IS DISTINCT FROM EXCLUDED.input_sha256
     OR target.profile_sha256 IS DISTINCT FROM EXCLUDED.profile_sha256;
  GET DIAGNOSTICS _profiles_written = ROW_COUNT;

  DELETE FROM public.alert_gap_profiles AS target
  WHERE target.version_id = _version_id
    AND target.through_date = _through_date
    AND NOT EXISTS (
      SELECT 1 FROM pg_temp._alert_gap_profile_build AS b
      WHERE b.user_id = target.user_id AND b.context_key = target.context_key
    );
  GET DIAGNOSTICS _profiles_deleted = ROW_COUNT;

  RETURN jsonb_build_object(
    ''profiles_written'', _profiles_written,
    ''profiles_deleted'', _profiles_deleted,
    ''completed_gaps'', _completed_gaps,
    ''explicit_quiet_minutes'', 0
  );
END;
$$;

REVOKE ALL ON FUNCTION private.qualified_behavior_sessions(uuid, timestamptz, timestamptz, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.rebuild_alert_gap_profiles(uuid, date)
  FROM PUBLIC, anon, authenticated, service_role;
"}', 'adaptive_alert_gap_profiles', 'codex-release-v0.5.21', NULL, NULL),
	('20260725164000', '{"-- ADR-0023 Task 5: privacy-qualified, aggregate-only Routine-mode priors.
-- This is candidate evidence only. It has no scheduler, realtime publication,
-- live alert write, or model/calibration seed.

ALTER TABLE public.alert_model_versions
  ADD CONSTRAINT alert_model_versions_cohort_prior_contract_check CHECK (
    (
      jsonb_typeof(config #> ''{cohort,contribution_floor_minutes}'') = ''number''
      AND (config #>> ''{cohort,contribution_floor_minutes}'')::numeric > 0
      AND (config #>> ''{cohort,contribution_floor_minutes}'')::numeric = trunc((config #>> ''{cohort,contribution_floor_minutes}'')::numeric)
      AND jsonb_typeof(config #> ''{cohort,contribution_ceiling_minutes}'') = ''number''
      AND (config #>> ''{cohort,contribution_ceiling_minutes}'')::numeric > 0
      AND (config #>> ''{cohort,contribution_ceiling_minutes}'')::numeric = trunc((config #>> ''{cohort,contribution_ceiling_minutes}'')::numeric)
      AND (config #>> ''{cohort,contribution_ceiling_minutes}'')::numeric >= (config #>> ''{cohort,contribution_floor_minutes}'')::numeric
      AND jsonb_typeof(config #> ''{cohort,min_span_days}'') = ''number''
      AND (config #>> ''{cohort,min_span_days}'')::numeric > 0
      AND (config #>> ''{cohort,min_span_days}'')::numeric = trunc((config #>> ''{cohort,min_span_days}'')::numeric)
      AND jsonb_typeof(config #> ''{cohort,min_confidence}'') = ''number''
      AND (config #>> ''{cohort,min_confidence}'')::numeric > 0
      AND (config #>> ''{cohort,min_confidence}'')::numeric <= 1
      AND jsonb_typeof(config #> ''{cohort,confidence_formula_version}'') = ''string''
      AND config #>> ''{cohort,confidence_formula_version}'' = ''cohort_support_min_v1''
    ) IS TRUE
  ) NOT VALID;

ALTER TABLE public.routine_mode_cohort_priors
  ADD COLUMN source_generation bigint NOT NULL DEFAULT 0 CHECK (source_generation >= 0),
  ADD COLUMN oldest_evidence_at timestamptz,
  ADD COLUMN valid_until timestamptz,
  ADD COLUMN conservative_span_days integer CHECK (conservative_span_days > 0),
  ADD COLUMN minimum_profile_confidence double precision CHECK (minimum_profile_confidence > 0 AND minimum_profile_confidence <= 1);

CREATE TABLE public.routine_mode_cohort_generations (
  routine_mode text PRIMARY KEY CHECK (routine_mode IN (''regular_9to5'', ''semester_break'', ''shift_irregular'')),
  generation bigint NOT NULL DEFAULT 0 CHECK (generation >= 0),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

INSERT INTO public.routine_mode_cohort_generations (routine_mode, generation)
VALUES (''regular_9to5'', 0), (''semester_break'', 0), (''shift_irregular'', 0)
ON CONFLICT (routine_mode) DO NOTHING;

ALTER TABLE public.routine_mode_cohort_invalidations
  ADD COLUMN generation bigint NOT NULL DEFAULT 0 CHECK (generation >= 0);

ALTER TABLE public.routine_mode_cohort_generations ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.routine_mode_cohort_generations
FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.invalidate_routine_mode_cohort()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''''
AS $$
DECLARE
  _mode text;
  _generation bigint;
BEGIN
  IF TG_OP = ''UPDATE''
     AND OLD.routine_pattern IS NOT DISTINCT FROM NEW.routine_pattern
     AND OLD.consent_data_sharing IS NOT DISTINCT FROM NEW.consent_data_sharing THEN
    RETURN NEW;
  END IF;

  FOR _mode IN
    SELECT DISTINCT candidate.routine_mode
    FROM (
      SELECT CASE
        WHEN TG_OP = ''INSERT'' THEN private.canonical_routine_mode(NEW.routine_pattern)
        WHEN TG_OP = ''DELETE'' THEN private.canonical_routine_mode(OLD.routine_pattern)
        ELSE private.canonical_routine_mode(OLD.routine_pattern)
      END AS routine_mode
      UNION ALL
      SELECT CASE WHEN TG_OP = ''UPDATE'' THEN private.canonical_routine_mode(NEW.routine_pattern) END
    ) AS candidate
    WHERE candidate.routine_mode IS NOT NULL
    ORDER BY candidate.routine_mode
  LOOP
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(''keep-contact:routine-mode-cohort:'' || _mode, 0)
    );

    UPDATE public.routine_mode_cohort_generations
    SET generation = generation + 1,
        updated_at = clock_timestamp()
    WHERE routine_mode = _mode
    RETURNING generation INTO _generation;

    INSERT INTO public.routine_mode_cohort_invalidations (routine_mode, invalidated_at, generation)
    VALUES (_mode, clock_timestamp(), _generation)
    ON CONFLICT (routine_mode) DO UPDATE
    SET invalidated_at = EXCLUDED.invalidated_at,
        generation = EXCLUDED.generation;
  END LOOP;

  IF TG_OP = ''DELETE'' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_profile_routine_mode_cohort_invalidation ON public.profiles;
CREATE TRIGGER on_profile_routine_mode_cohort_invalidation
AFTER INSERT OR DELETE OR UPDATE OF routine_pattern, consent_data_sharing
ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION private.invalidate_routine_mode_cohort();

CREATE FUNCTION private.invalidate_routine_mode_cohort_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''''
AS $$
DECLARE
  _mode text;
  _generation bigint;
BEGIN
  -- Both sides matter: a key can stop being personal_global, start being it,
  -- or move between users/modes. Resolve current modes only, deduplicate them,
  -- then lock in lexical order before each single generation increment.
  FOR _mode IN
    WITH affected_users(user_id) AS (
      SELECT OLD.user_id
      WHERE TG_OP <> ''INSERT'' AND OLD.context_key = ''personal_global''
      UNION
      SELECT NEW.user_id
      WHERE TG_OP <> ''DELETE'' AND NEW.context_key = ''personal_global''
    )
    SELECT DISTINCT private.canonical_routine_mode(p.routine_pattern)
    FROM affected_users AS affected
    JOIN public.profiles AS p ON p.id = affected.user_id
    ORDER BY private.canonical_routine_mode(p.routine_pattern)
  LOOP
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(''keep-contact:routine-mode-cohort:'' || _mode, 0)
    );
    UPDATE public.routine_mode_cohort_generations
    SET generation = generation + 1,
        updated_at = clock_timestamp()
    WHERE routine_mode = _mode
    RETURNING generation INTO _generation;
    INSERT INTO public.routine_mode_cohort_invalidations (routine_mode, invalidated_at, generation)
    VALUES (_mode, clock_timestamp(), _generation)
    ON CONFLICT (routine_mode) DO UPDATE
    SET invalidated_at = EXCLUDED.invalidated_at,
        generation = EXCLUDED.generation;
  END LOOP;

  IF TG_OP = ''DELETE'' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_alert_gap_profile_routine_mode_cohort_invalidation
AFTER INSERT OR UPDATE OR DELETE ON public.alert_gap_profiles
FOR EACH ROW
EXECUTE FUNCTION private.invalidate_routine_mode_cohort_profile();

CREATE FUNCTION private.rebuild_routine_mode_cohort_priors(
  _version_id uuid,
  _through_date date,
  _routine_mode text
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET TimeZone = ''UTC''
AS $$
DECLARE
  _config jsonb;
  _config_sha256 text;
  _evidence_version text;
  _status text;
  _mode text := private.canonical_routine_mode(_routine_mode);
  _generation bigint;
  _personal_min_samples integer;
  _personal_min_dates integer;
  _personal_min_span integer;
  _personal_max_age integer;
  _cohort_min_contributors integer;
  _cohort_min_dates integer;
  _cohort_min_span integer;
  _cohort_max_age integer;
  _cohort_min_confidence double precision;
  _floor integer;
  _ceiling integer;
  _algorithm text;
  _trim_fraction double precision;
  _count integer;
  _support_dates integer;
  _conservative_span_days integer;
  _support_started date;
  _support_ended date;
  _oldest_evidence timestamptz;
  _latest_evidence timestamptz;
  _valid_until timestamptz;
  _minimum_confidence double precision;
  _confidence double precision;
  _neutral integer;
  _quality text;
  _multiset text;
  _input_sha256 text;
  _prior_sha256 text;
  _published integer := 0;
  _cutoff timestamptz;
BEGIN
  IF _version_id IS NULL OR _through_date IS NULL
     OR _mode NOT IN (''regular_9to5'', ''semester_break'', ''shift_irregular'') THEN
    RETURN jsonb_build_object(''published'', 0, ''routine_mode'', _mode);
  END IF;

  _cutoff := (_through_date + 1)::timestamptz;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(''keep-contact:routine-mode-cohort:'' || _mode, 0)
  );

  SELECT v.config, v.config_sha256, v.evidence_version, v.status
    INTO _config, _config_sha256, _evidence_version, _status
  FROM public.alert_model_versions AS v
  WHERE v.id = _version_id;

  SELECT generation INTO _generation
  FROM public.routine_mode_cohort_generations
  WHERE routine_mode = _mode;

  IF NOT FOUND OR _status NOT IN (''replay'', ''shadow'')
     OR _evidence_version <> ''canonical-v2''
     OR _config_sha256 <> encode(extensions.digest(_config::text, ''sha256''), ''hex'') THEN
    RETURN jsonb_build_object(''published'', 0, ''routine_mode'', _mode);
  END IF;

  BEGIN
    _personal_min_samples := (_config #>> ''{personal,min_samples}'')::integer;
    _personal_min_dates := (_config #>> ''{personal,min_support_dates}'')::integer;
    _personal_min_span := (_config #>> ''{personal,min_span_days}'')::integer;
    _personal_max_age := (_config #>> ''{personal,max_age_days}'')::integer;
    _cohort_min_contributors := (_config #>> ''{cohort,min_contributors}'')::integer;
    _cohort_min_dates := (_config #>> ''{cohort,min_support_dates}'')::integer;
    _cohort_min_span := (_config #>> ''{cohort,min_span_days}'')::integer;
    _cohort_max_age := (_config #>> ''{cohort,max_age_days}'')::integer;
    _cohort_min_confidence := (_config #>> ''{cohort,min_confidence}'')::double precision;
    _floor := (_config #>> ''{cohort,contribution_floor_minutes}'')::integer;
    _ceiling := (_config #>> ''{cohort,contribution_ceiling_minutes}'')::integer;
    _algorithm := _config #>> ''{cohort,algorithm}'';
    _trim_fraction := (_config #>> ''{cohort,trim_fraction}'')::double precision;
  EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
    RETURN jsonb_build_object(''published'', 0, ''routine_mode'', _mode);
  END;

  IF _personal_min_samples <= 0 OR _personal_min_dates <= 0 OR _personal_min_span <= 0 OR _personal_max_age <= 0
     OR _cohort_min_contributors <= 0 OR _cohort_min_dates <= 0 OR _cohort_min_span <= 0 OR _cohort_max_age <= 0
     OR _cohort_min_confidence <= 0 OR _cohort_min_confidence > 1
     OR _floor <= 0 OR _ceiling < _floor
     OR _algorithm NOT IN (''weighted_median'', ''trimmed_mean'')
     OR _trim_fraction < 0 OR _trim_fraction >= 0.5
     OR _config #>> ''{cohort,confidence_formula_version}'' <> ''cohort_support_min_v1'' THEN
    RETURN jsonb_build_object(''published'', 0, ''routine_mode'', _mode);
  END IF;

  DROP TABLE IF EXISTS pg_temp._routine_mode_cohort_build;
  CREATE TEMP TABLE _routine_mode_cohort_build ON COMMIT DROP AS
  SELECT
    greatest(_floor, least(_ceiling, p.neutral_p95_minutes))::integer AS neutral_minutes,
    greatest(0::double precision, least(1::double precision, p.confidence)) AS profile_confidence,
    p.distinct_support_dates,
    p.support_started_on,
    p.support_ended_on,
    (p.support_ended_on - p.support_started_on + 1)::integer AS support_span_days,
    p.latest_evidence_at
  FROM public.alert_gap_profiles AS p
  JOIN public.profiles AS owner_profile ON owner_profile.id = p.user_id
  WHERE p.version_id = _version_id
    AND p.context_key = ''personal_global''
    AND p.through_date = _through_date
    AND p.quality_state = ''valid''
    AND owner_profile.consent_data_sharing = true
    AND private.canonical_routine_mode(owner_profile.routine_pattern) = _mode
    AND p.sample_count >= _personal_min_samples
    AND p.distinct_support_dates >= _personal_min_dates
    AND p.support_ended_on - p.support_started_on + 1 >= _personal_min_span
    AND p.confidence >= _cohort_min_confidence
    AND p.latest_evidence_at + make_interval(days => _personal_max_age) > _cutoff;

  SELECT count(*)::integer,
         min(distinct_support_dates), min(support_span_days), min(support_started_on), max(support_ended_on),
         min(latest_evidence_at), max(latest_evidence_at), min(profile_confidence),
         string_agg(neutral_minutes::text || '':'' || profile_confidence::text, '','' ORDER BY neutral_minutes, profile_confidence)
    INTO _count, _support_dates, _conservative_span_days, _support_started, _support_ended,
         _oldest_evidence, _latest_evidence, _minimum_confidence, _multiset
  FROM pg_temp._routine_mode_cohort_build;

  IF _count = 0 THEN
    DELETE FROM public.routine_mode_cohort_priors
    WHERE version_id = _version_id AND routine_mode = _mode
      AND context_key = ''personal_global'' AND through_date = _through_date;
    RETURN jsonb_build_object(''published'', 0, ''routine_mode'', _mode);
  END IF;

  _valid_until := least(
    _oldest_evidence + make_interval(days => _personal_max_age),
    _oldest_evidence + make_interval(days => _cohort_max_age)
  );

  IF _valid_until <= _cutoff THEN
    DELETE FROM public.routine_mode_cohort_priors
    WHERE version_id = _version_id AND routine_mode = _mode
      AND context_key = ''personal_global'' AND through_date = _through_date;
    RETURN jsonb_build_object(''published'', 0, ''routine_mode'', _mode);
  END IF;

  IF _algorithm = ''weighted_median'' THEN
    SELECT neutral_minutes INTO _neutral
    FROM (
      SELECT neutral_minutes,
             sum(profile_confidence) OVER (ORDER BY neutral_minutes, profile_confidence ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_weight,
             sum(profile_confidence) OVER () AS total_weight
      FROM pg_temp._routine_mode_cohort_build
    ) AS weighted
    WHERE cumulative_weight >= total_weight / 2.0
    ORDER BY neutral_minutes, cumulative_weight
    LIMIT 1;
  ELSE
    SELECT ceil(avg(neutral_minutes)::numeric)::integer INTO _neutral
    FROM (
      SELECT neutral_minutes,
             row_number() OVER (ORDER BY neutral_minutes, profile_confidence) AS ordinal,
             count(*) OVER () AS total_count
      FROM pg_temp._routine_mode_cohort_build
    ) AS trimmed
    WHERE ordinal > floor(total_count * _trim_fraction)
      AND ordinal <= total_count - floor(total_count * _trim_fraction);
  END IF;

  _confidence := least(
    1::double precision,
    _count::double precision / _cohort_min_contributors::double precision,
    _support_dates::double precision / _cohort_min_dates::double precision,
    _conservative_span_days::double precision / _cohort_min_span::double precision,
    _minimum_confidence / _cohort_min_confidence
  );
  _quality := CASE
    WHEN _count >= _cohort_min_contributors
      AND _support_dates >= _cohort_min_dates
      AND _conservative_span_days >= _cohort_min_span
      AND _minimum_confidence >= _cohort_min_confidence
      THEN ''valid''
    ELSE ''low_support''
  END;

  _input_sha256 := encode(extensions.digest(concat_ws(''|'',
    _version_id::text, _config_sha256, _evidence_version, _through_date::text, _mode,
    _algorithm, _generation::text, _multiset, _count::text, _support_dates::text,
    _conservative_span_days::text, _support_started::text, _support_ended::text,
    _oldest_evidence::text, _latest_evidence::text, _valid_until::text, _cutoff::text
  ), ''sha256''), ''hex'');
  _prior_sha256 := encode(extensions.digest(concat_ws(''|'',
    _input_sha256, _version_id::text, _mode, ''personal_global'', _through_date::text,
    _count::text, _support_dates::text, _conservative_span_days::text, _support_started::text,
    _support_ended::text, _latest_evidence::text, _oldest_evidence::text, _valid_until::text,
    _neutral::text, _quality, _confidence::text, _minimum_confidence::text, _algorithm,
    _config_sha256, _evidence_version, _generation::text
  ), ''sha256''), ''hex'');

  INSERT INTO public.routine_mode_cohort_priors AS target (
    version_id, routine_mode, context_key, through_date, contributor_count,
    distinct_support_dates, support_started_on, support_ended_on, latest_evidence_at,
    oldest_evidence_at, valid_until, conservative_span_days, minimum_profile_confidence,
    neutral_p95_minutes, quality_state, confidence,
    algorithm, config_sha256, evidence_version, source_generation, input_sha256, prior_sha256
  ) VALUES (
    _version_id, _mode, ''personal_global'', _through_date, _count,
    _support_dates, _support_started, _support_ended, _latest_evidence,
    _oldest_evidence, _valid_until, _conservative_span_days, _minimum_confidence,
    _neutral, _quality, _confidence,
    _algorithm, _config_sha256, _evidence_version, _generation, _input_sha256, _prior_sha256
  )
  ON CONFLICT (version_id, routine_mode, context_key, through_date) DO UPDATE
  SET contributor_count = EXCLUDED.contributor_count,
      distinct_support_dates = EXCLUDED.distinct_support_dates,
      support_started_on = EXCLUDED.support_started_on,
      support_ended_on = EXCLUDED.support_ended_on,
      latest_evidence_at = EXCLUDED.latest_evidence_at,
      oldest_evidence_at = EXCLUDED.oldest_evidence_at,
      valid_until = EXCLUDED.valid_until,
      conservative_span_days = EXCLUDED.conservative_span_days,
      minimum_profile_confidence = EXCLUDED.minimum_profile_confidence,
      neutral_p95_minutes = EXCLUDED.neutral_p95_minutes,
      quality_state = EXCLUDED.quality_state,
      confidence = EXCLUDED.confidence,
      algorithm = EXCLUDED.algorithm,
      config_sha256 = EXCLUDED.config_sha256,
      evidence_version = EXCLUDED.evidence_version,
      source_generation = EXCLUDED.source_generation,
      input_sha256 = EXCLUDED.input_sha256,
      prior_sha256 = EXCLUDED.prior_sha256,
      published_at = CASE WHEN target.prior_sha256 = EXCLUDED.prior_sha256 THEN target.published_at ELSE clock_timestamp() END
  WHERE target.prior_sha256 IS DISTINCT FROM EXCLUDED.prior_sha256;
  GET DIAGNOSTICS _published = ROW_COUNT;

  RETURN jsonb_build_object(''published'', _published, ''routine_mode'', _mode, ''quality_state'', _quality);
END;
$$;

CREATE FUNCTION private.routine_mode_cohort_prior_is_valid(
  _version_id uuid,
  _routine_mode text,
  _through_date date,
  _evaluated_at timestamptz
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''''
SET TimeZone = ''UTC''
AS $$
DECLARE
  _prior public.routine_mode_cohort_priors%ROWTYPE;
  _config jsonb;
  _config_sha256 text;
  _evidence_version text;
  _status text;
  _generation bigint;
  _mode text := private.canonical_routine_mode(_routine_mode);
  _min_contributors integer;
  _min_dates integer;
  _min_span integer;
  _min_confidence double precision;
  _floor integer;
  _ceiling integer;
  _algorithm text;
  _expected_confidence double precision;
  _expected_quality text;
  _expected_sha text;
  _cutoff timestamptz;
BEGIN
  IF _version_id IS NULL OR _through_date IS NULL OR _evaluated_at IS NULL
     OR _mode NOT IN (''regular_9to5'', ''semester_break'', ''shift_irregular'') THEN
    RETURN false;
  END IF;
  _cutoff := (_through_date + 1)::timestamptz;
  IF _evaluated_at < _cutoff THEN
    RETURN false;
  END IF;

  SELECT * INTO _prior
  FROM public.routine_mode_cohort_priors AS prior
  WHERE prior.version_id = _version_id
    AND prior.routine_mode = _mode
    AND prior.context_key = ''personal_global''
    AND prior.through_date = _through_date;
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  SELECT version.config, version.config_sha256, version.evidence_version, version.status, generation.generation
    INTO _config, _config_sha256, _evidence_version, _status, _generation
  FROM public.alert_model_versions AS version
  JOIN public.routine_mode_cohort_generations AS generation ON generation.routine_mode = _mode
  WHERE version.id = _version_id;
  IF NOT FOUND OR _status NOT IN (''replay'', ''shadow'')
     OR _evidence_version <> ''canonical-v2''
     OR _config_sha256 <> encode(extensions.digest(_config::text, ''sha256''), ''hex'')
     OR _prior.config_sha256 <> _config_sha256
     OR _prior.evidence_version <> _evidence_version
     OR _prior.source_generation <> _generation
     OR _prior.valid_until IS NULL OR _prior.valid_until <= _cutoff
     OR _evaluated_at >= _prior.valid_until
     OR _prior.contributor_count <= 0 OR _prior.distinct_support_dates <= 0
     OR _prior.conservative_span_days IS NULL OR _prior.conservative_span_days <= 0
     OR _prior.minimum_profile_confidence IS NULL OR _prior.minimum_profile_confidence <= 0
     OR _prior.confidence < 0 OR _prior.confidence > 1 THEN
    RETURN false;
  END IF;

  BEGIN
    _min_contributors := (_config #>> ''{cohort,min_contributors}'')::integer;
    _min_dates := (_config #>> ''{cohort,min_support_dates}'')::integer;
    _min_span := (_config #>> ''{cohort,min_span_days}'')::integer;
    _min_confidence := (_config #>> ''{cohort,min_confidence}'')::double precision;
    _floor := (_config #>> ''{cohort,contribution_floor_minutes}'')::integer;
    _ceiling := (_config #>> ''{cohort,contribution_ceiling_minutes}'')::integer;
    _algorithm := _config #>> ''{cohort,algorithm}'';
  EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
    RETURN false;
  END;
  IF _min_contributors <= 0 OR _min_dates <= 0 OR _min_span <= 0
     OR _min_confidence <= 0 OR _min_confidence > 1
     OR _floor <= 0 OR _ceiling < _floor
     OR _algorithm NOT IN (''weighted_median'', ''trimmed_mean'')
     OR _config #>> ''{cohort,confidence_formula_version}'' <> ''cohort_support_min_v1''
     OR _prior.algorithm <> _algorithm THEN
    RETURN false;
  END IF;
  IF _prior.neutral_p95_minutes < _floor OR _prior.neutral_p95_minutes > _ceiling THEN
    RETURN false;
  END IF;

  _expected_confidence := least(
    1::double precision,
    _prior.contributor_count::double precision / _min_contributors::double precision,
    _prior.distinct_support_dates::double precision / _min_dates::double precision,
    _prior.conservative_span_days::double precision / _min_span::double precision,
    _prior.minimum_profile_confidence / _min_confidence
  );
  _expected_quality := CASE
    WHEN _prior.contributor_count >= _min_contributors
      AND _prior.distinct_support_dates >= _min_dates
      AND _prior.conservative_span_days >= _min_span
      AND _prior.minimum_profile_confidence >= _min_confidence
      THEN ''valid''
    ELSE ''low_support''
  END;
  IF _prior.quality_state <> _expected_quality
     OR _prior.confidence <> _expected_confidence
     OR _prior.quality_state <> ''valid'' THEN
    RETURN false;
  END IF;

  _expected_sha := encode(extensions.digest(concat_ws(''|'',
    _prior.input_sha256, _prior.version_id::text, _prior.routine_mode, _prior.context_key,
    _prior.through_date::text, _prior.contributor_count::text, _prior.distinct_support_dates::text,
    _prior.conservative_span_days::text, _prior.support_started_on::text, _prior.support_ended_on::text,
    _prior.latest_evidence_at::text, _prior.oldest_evidence_at::text, _prior.valid_until::text,
    _prior.neutral_p95_minutes::text, _prior.quality_state, _prior.confidence::text,
    _prior.minimum_profile_confidence::text, _prior.algorithm, _prior.config_sha256,
    _prior.evidence_version, _prior.source_generation::text
  ), ''sha256''), ''hex'');
  RETURN _prior.prior_sha256 = _expected_sha;
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION private.invalidate_routine_mode_cohort()
FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON FUNCTION private.invalidate_routine_mode_cohort_profile()
FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON FUNCTION private.rebuild_routine_mode_cohort_priors(uuid, date, text)
FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON FUNCTION private.routine_mode_cohort_prior_is_valid(uuid, text, date, timestamptz)
FROM PUBLIC, anon, authenticated, service_role;
"}', 'routine_mode_cohort_priors', 'codex-release-v0.5.21', NULL, NULL),
	('20260725165000', '{"-- ADR-0023 Task 6: deterministic replay/shadow candidate resolution only.
-- This migration creates no context producer, scheduler, live-alert write, or
-- notification path. The existing ADR-0022 live threshold remains authoritative.

ALTER TABLE public.alert_model_versions
  ADD CONSTRAINT alert_model_versions_candidate_evaluator_contract_check CHECK (
    (
      jsonb_typeof(config #> ''{personal,min_confidence}'') = ''number''
      AND (config #>> ''{personal,min_confidence}'')::numeric > 0
      AND (config #>> ''{personal,min_confidence}'')::numeric <= 1
      AND jsonb_typeof(config -> ''evaluator'') = ''object''
      AND config #>> ''{evaluator,contract_version}'' = ''adaptive_candidate_v1''
      AND jsonb_typeof(config -> ''emergency'') = ''object''
      AND config #>> ''{emergency,contract_version}'' = ''adr0022_v1''
      AND jsonb_typeof(config #> ''{emergency,neutral_minutes}'') = ''number''
      AND (config #>> ''{emergency,neutral_minutes}'')::numeric = 90
      AND (config #>> ''{emergency,neutral_minutes}'')::numeric
        = trunc((config #>> ''{emergency,neutral_minutes}'')::numeric)
      AND config #>> ''{emergency,expected_live_definition_sha256}''
        = ''1907d59473d274d46a0e8e0b9ce8027037b4494b0dddf073cb46abf67db92e21''
      AND (config #>> ''{emergency,expected_live_definition_sha256}'') ~ ''^[a-f0-9]{64}$''
      AND (config #>> ''{sensitivity_buffers_minutes,high}'')::numeric
        = trunc((config #>> ''{sensitivity_buffers_minutes,high}'')::numeric)
      AND (config #>> ''{sensitivity_buffers_minutes,balanced}'')::numeric
        = trunc((config #>> ''{sensitivity_buffers_minutes,balanced}'')::numeric)
      AND (config #>> ''{sensitivity_buffers_minutes,low}'')::numeric
        = trunc((config #>> ''{sensitivity_buffers_minutes,low}'')::numeric)
      AND (config #>> ''{candidate_bounds,floor_minutes}'')::numeric
        = trunc((config #>> ''{candidate_bounds,floor_minutes}'')::numeric)
      AND (config #>> ''{candidate_bounds,ceiling_minutes}'')::numeric
        = trunc((config #>> ''{candidate_bounds,ceiling_minutes}'')::numeric)
    ) IS TRUE
  ) NOT VALID;

CREATE TABLE public.alert_judgment_subject_contexts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id uuid NOT NULL
    REFERENCES public.alert_model_versions(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  effective_from timestamptz NOT NULL,
  effective_to timestamptz,
  raw_sensitivity text,
  canonical_sensitivity text NOT NULL
    CHECK (canonical_sensitivity IN (''high'', ''balanced'', ''low'')),
  routine_mode text NOT NULL
    CHECK (routine_mode IN (''regular_9to5'', ''semester_break'', ''shift_irregular'')),
  timezone text NOT NULL CHECK (length(trim(timezone)) > 0),
  utc_offset_minutes integer NOT NULL CHECK (utc_offset_minutes BETWEEN -840 AND 840),
  settings_updated_at timestamptz NOT NULL,
  settings_provenance jsonb NOT NULL
    CHECK (jsonb_typeof(settings_provenance) = ''object''),
  captured_at timestamptz NOT NULL,
  config_sha256 text NOT NULL CHECK (config_sha256 ~ ''^[a-f0-9]{64}$''),
  evidence_version text NOT NULL CHECK (length(trim(evidence_version)) > 0),
  subject_context_sha256 text NOT NULL
    CHECK (subject_context_sha256 ~ ''^[a-f0-9]{64}$''),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK (effective_to IS NULL OR effective_to > effective_from),
  CHECK (settings_updated_at <= captured_at)
);

CREATE INDEX alert_judgment_subject_contexts_as_of_idx
  ON public.alert_judgment_subject_contexts
    (version_id, user_id, effective_from, effective_to, captured_at);

ALTER TABLE public.alert_judgment_subject_contexts ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.alert_judgment_subject_contexts
FROM PUBLIC, anon, authenticated, service_role;

ALTER TABLE public.alert_gap_profiles
  ADD COLUMN config_sha256 text CHECK (config_sha256 ~ ''^[a-f0-9]{64}$''),
  ADD COLUMN evidence_version text CHECK (
    evidence_version IS NULL OR length(trim(evidence_version)) > 0
  );

-- Centralized, raw-type-first config gate. A canonical config_sha256 only
-- proves the stored config matches its own hash; it says nothing about
-- whether a pre-Task-6 legacy row''s scalars are the right JSON type, enum,
-- range, or integrality. Every key consumed anywhere in the Task 3-5
-- sleep/session/profile/cohort helpers or the Task 6 evaluator is checked
-- here, by JSON type, before any numeric/text extraction, so a JSON string
-- that happens to parse as a number (or an out-of-range/non-integral number)
-- can never be silently cast and accepted.
CREATE FUNCTION private.alert_candidate_config_is_valid(_config jsonb)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''''
SET TimeZone = ''UTC''
SET \"DateStyle\" = ''ISO, YMD''
SET extra_float_digits = 3
AS $$
  SELECT
    jsonb_typeof(_config) = ''object''
    AND _config ?& ARRAY[
      ''sessionization'', ''context'', ''personal'', ''cohort'',
      ''sensitivity_buffers_minutes'', ''candidate_bounds'', ''sleep_compensation'',
      ''evaluator'', ''emergency''
    ]
    AND jsonb_typeof(_config -> ''sessionization'') = ''object''
    AND (_config -> ''sessionization'') ?& ARRAY[
      ''gap_minutes'', ''per_user_day_gap_cap'',
      ''training_horizon_days'', ''intervention_window_minutes''
    ]
    AND jsonb_typeof(_config #> ''{sessionization,gap_minutes}'') = ''number''
    AND (_config #>> ''{sessionization,gap_minutes}'')::numeric > 0
    AND jsonb_typeof(_config #> ''{sessionization,per_user_day_gap_cap}'') = ''number''
    AND (_config #>> ''{sessionization,per_user_day_gap_cap}'')::numeric > 0
    AND jsonb_typeof(_config #> ''{sessionization,training_horizon_days}'') = ''number''
    AND (_config #>> ''{sessionization,training_horizon_days}'')::numeric > 0
    AND (_config #>> ''{sessionization,training_horizon_days}'')::numeric
      = trunc((_config #>> ''{sessionization,training_horizon_days}'')::numeric)
    AND jsonb_typeof(_config #> ''{sessionization,intervention_window_minutes}'') = ''number''
    AND (_config #>> ''{sessionization,intervention_window_minutes}'')::numeric >= 0
    AND (_config #>> ''{sessionization,intervention_window_minutes}'')::numeric
      = trunc((_config #>> ''{sessionization,intervention_window_minutes}'')::numeric)
    AND jsonb_typeof(_config -> ''context'') = ''object''
    AND (_config -> ''context'') ?& ARRAY[
      ''definition_version'', ''day_partition'', ''hour_bucket_minutes''
    ]
    AND jsonb_typeof(_config #> ''{context,definition_version}'') = ''string''
    AND length(trim(_config #>> ''{context,definition_version}'')) > 0
    AND jsonb_typeof(_config #> ''{context,day_partition}'') = ''string''
    AND _config #>> ''{context,day_partition}'' IN (''all_days'', ''weekday_weekend'')
    AND jsonb_typeof(_config #> ''{context,hour_bucket_minutes}'') = ''number''
    AND (_config #>> ''{context,hour_bucket_minutes}'')::numeric > 0
    AND (_config #>> ''{context,hour_bucket_minutes}'')::numeric
      = trunc((_config #>> ''{context,hour_bucket_minutes}'')::numeric)
    AND mod(1440, (_config #>> ''{context,hour_bucket_minutes}'')::integer) = 0
    AND jsonb_typeof(_config -> ''personal'') = ''object''
    AND (_config -> ''personal'') ?& ARRAY[
      ''min_samples'', ''min_support_dates'', ''min_span_days'', ''max_age_days'',
      ''min_confidence'', ''confidence_formula_version''
    ]
    AND jsonb_typeof(_config #> ''{personal,min_samples}'') = ''number''
    AND (_config #>> ''{personal,min_samples}'')::numeric > 0
    AND (_config #>> ''{personal,min_samples}'')::numeric
      = trunc((_config #>> ''{personal,min_samples}'')::numeric)
    AND jsonb_typeof(_config #> ''{personal,min_support_dates}'') = ''number''
    AND (_config #>> ''{personal,min_support_dates}'')::numeric > 0
    AND (_config #>> ''{personal,min_support_dates}'')::numeric
      = trunc((_config #>> ''{personal,min_support_dates}'')::numeric)
    AND jsonb_typeof(_config #> ''{personal,min_span_days}'') = ''number''
    AND (_config #>> ''{personal,min_span_days}'')::numeric > 0
    AND (_config #>> ''{personal,min_span_days}'')::numeric
      = trunc((_config #>> ''{personal,min_span_days}'')::numeric)
    AND jsonb_typeof(_config #> ''{personal,max_age_days}'') = ''number''
    AND (_config #>> ''{personal,max_age_days}'')::numeric > 0
    AND (_config #>> ''{personal,max_age_days}'')::numeric
      = trunc((_config #>> ''{personal,max_age_days}'')::numeric)
    AND jsonb_typeof(_config #> ''{personal,min_confidence}'') = ''number''
    AND (_config #>> ''{personal,min_confidence}'')::numeric > 0
    AND (_config #>> ''{personal,min_confidence}'')::numeric <= 1
    AND jsonb_typeof(_config #> ''{personal,confidence_formula_version}'') = ''string''
    AND _config #>> ''{personal,confidence_formula_version}'' = ''support_ratio_v1''
    AND jsonb_typeof(_config -> ''cohort'') = ''object''
    AND (_config -> ''cohort'') ?& ARRAY[
      ''min_contributors'', ''min_support_dates'', ''min_span_days'', ''max_age_days'',
      ''min_confidence'', ''contribution_floor_minutes'', ''contribution_ceiling_minutes'',
      ''confidence_formula_version'', ''algorithm'', ''trim_fraction''
    ]
    AND jsonb_typeof(_config #> ''{cohort,min_contributors}'') = ''number''
    AND (_config #>> ''{cohort,min_contributors}'')::numeric > 0
    AND (_config #>> ''{cohort,min_contributors}'')::numeric
      = trunc((_config #>> ''{cohort,min_contributors}'')::numeric)
    AND jsonb_typeof(_config #> ''{cohort,min_support_dates}'') = ''number''
    AND (_config #>> ''{cohort,min_support_dates}'')::numeric > 0
    AND (_config #>> ''{cohort,min_support_dates}'')::numeric
      = trunc((_config #>> ''{cohort,min_support_dates}'')::numeric)
    AND jsonb_typeof(_config #> ''{cohort,min_span_days}'') = ''number''
    AND (_config #>> ''{cohort,min_span_days}'')::numeric > 0
    AND (_config #>> ''{cohort,min_span_days}'')::numeric
      = trunc((_config #>> ''{cohort,min_span_days}'')::numeric)
    AND jsonb_typeof(_config #> ''{cohort,max_age_days}'') = ''number''
    AND (_config #>> ''{cohort,max_age_days}'')::numeric > 0
    AND (_config #>> ''{cohort,max_age_days}'')::numeric
      = trunc((_config #>> ''{cohort,max_age_days}'')::numeric)
    AND jsonb_typeof(_config #> ''{cohort,min_confidence}'') = ''number''
    AND (_config #>> ''{cohort,min_confidence}'')::numeric > 0
    AND (_config #>> ''{cohort,min_confidence}'')::numeric <= 1
    AND jsonb_typeof(_config #> ''{cohort,contribution_floor_minutes}'') = ''number''
    AND (_config #>> ''{cohort,contribution_floor_minutes}'')::numeric > 0
    AND (_config #>> ''{cohort,contribution_floor_minutes}'')::numeric
      = trunc((_config #>> ''{cohort,contribution_floor_minutes}'')::numeric)
    AND jsonb_typeof(_config #> ''{cohort,contribution_ceiling_minutes}'') = ''number''
    AND (_config #>> ''{cohort,contribution_ceiling_minutes}'')::numeric > 0
    AND (_config #>> ''{cohort,contribution_ceiling_minutes}'')::numeric
      = trunc((_config #>> ''{cohort,contribution_ceiling_minutes}'')::numeric)
    AND (_config #>> ''{cohort,contribution_ceiling_minutes}'')::numeric
      >= (_config #>> ''{cohort,contribution_floor_minutes}'')::numeric
    AND jsonb_typeof(_config #> ''{cohort,confidence_formula_version}'') = ''string''
    AND _config #>> ''{cohort,confidence_formula_version}'' = ''cohort_support_min_v1''
    AND jsonb_typeof(_config #> ''{cohort,algorithm}'') = ''string''
    AND _config #>> ''{cohort,algorithm}'' IN (''weighted_median'', ''trimmed_mean'')
    AND jsonb_typeof(_config #> ''{cohort,trim_fraction}'') = ''number''
    AND (_config #>> ''{cohort,trim_fraction}'')::numeric >= 0
    AND (_config #>> ''{cohort,trim_fraction}'')::numeric < 0.5
    AND jsonb_typeof(_config -> ''sensitivity_buffers_minutes'') = ''object''
    AND (_config -> ''sensitivity_buffers_minutes'') ?& ARRAY[''high'', ''balanced'', ''low'']
    AND jsonb_typeof(_config #> ''{sensitivity_buffers_minutes,high}'') = ''number''
    AND jsonb_typeof(_config #> ''{sensitivity_buffers_minutes,balanced}'') = ''number''
    AND jsonb_typeof(_config #> ''{sensitivity_buffers_minutes,low}'') = ''number''
    AND (_config #>> ''{sensitivity_buffers_minutes,high}'')::numeric = 0
    AND (_config #>> ''{sensitivity_buffers_minutes,balanced}'')::numeric = 45
    AND (_config #>> ''{sensitivity_buffers_minutes,low}'')::numeric = 90
    AND jsonb_typeof(_config -> ''candidate_bounds'') = ''object''
    AND (_config -> ''candidate_bounds'') ?& ARRAY[''floor_minutes'', ''ceiling_minutes'']
    AND jsonb_typeof(_config #> ''{candidate_bounds,floor_minutes}'') = ''number''
    AND (_config #>> ''{candidate_bounds,floor_minutes}'')::numeric >= 0
    AND (_config #>> ''{candidate_bounds,floor_minutes}'')::numeric
      = trunc((_config #>> ''{candidate_bounds,floor_minutes}'')::numeric)
    AND jsonb_typeof(_config #> ''{candidate_bounds,ceiling_minutes}'') = ''number''
    AND (_config #>> ''{candidate_bounds,ceiling_minutes}'')::numeric
      >= (_config #>> ''{candidate_bounds,floor_minutes}'')::numeric
    AND (_config #>> ''{candidate_bounds,ceiling_minutes}'')::numeric
      = trunc((_config #>> ''{candidate_bounds,ceiling_minutes}'')::numeric)
    AND jsonb_typeof(_config -> ''sleep_compensation'') = ''object''
    AND (_config -> ''sleep_compensation'') ?& ARRAY[
      ''max_start_delay_minutes'', ''max_wake_advance_minutes'', ''max_wake_delay_minutes'',
      ''max_update_minutes_per_day'', ''min_positive_nights'', ''lookback_nights'',
      ''min_late_events_per_night'', ''timezone_tolerance_minutes''
    ]
    AND jsonb_typeof(_config #> ''{sleep_compensation,max_start_delay_minutes}'') = ''number''
    AND (_config #>> ''{sleep_compensation,max_start_delay_minutes}'')::numeric >= 0
    AND (_config #>> ''{sleep_compensation,max_start_delay_minutes}'')::numeric
      = trunc((_config #>> ''{sleep_compensation,max_start_delay_minutes}'')::numeric)
    AND jsonb_typeof(_config #> ''{sleep_compensation,max_wake_advance_minutes}'') = ''number''
    AND (_config #>> ''{sleep_compensation,max_wake_advance_minutes}'')::numeric >= 0
    AND (_config #>> ''{sleep_compensation,max_wake_advance_minutes}'')::numeric
      = trunc((_config #>> ''{sleep_compensation,max_wake_advance_minutes}'')::numeric)
    AND jsonb_typeof(_config #> ''{sleep_compensation,max_wake_delay_minutes}'') = ''number''
    AND (_config #>> ''{sleep_compensation,max_wake_delay_minutes}'')::numeric >= 0
    AND (_config #>> ''{sleep_compensation,max_wake_delay_minutes}'')::numeric
      = trunc((_config #>> ''{sleep_compensation,max_wake_delay_minutes}'')::numeric)
    AND jsonb_typeof(_config #> ''{sleep_compensation,max_update_minutes_per_day}'') = ''number''
    AND (_config #>> ''{sleep_compensation,max_update_minutes_per_day}'')::numeric >= 0
    AND (_config #>> ''{sleep_compensation,max_update_minutes_per_day}'')::numeric
      = trunc((_config #>> ''{sleep_compensation,max_update_minutes_per_day}'')::numeric)
    AND jsonb_typeof(_config #> ''{sleep_compensation,min_positive_nights}'') = ''number''
    AND (_config #>> ''{sleep_compensation,min_positive_nights}'')::numeric > 0
    AND (_config #>> ''{sleep_compensation,min_positive_nights}'')::numeric
      = trunc((_config #>> ''{sleep_compensation,min_positive_nights}'')::numeric)
    AND jsonb_typeof(_config #> ''{sleep_compensation,lookback_nights}'') = ''number''
    AND (_config #>> ''{sleep_compensation,lookback_nights}'')::numeric > 0
    AND (_config #>> ''{sleep_compensation,lookback_nights}'')::numeric
      = trunc((_config #>> ''{sleep_compensation,lookback_nights}'')::numeric)
    AND (_config #>> ''{sleep_compensation,min_positive_nights}'')::numeric
      <= (_config #>> ''{sleep_compensation,lookback_nights}'')::numeric
    AND jsonb_typeof(_config #> ''{sleep_compensation,min_late_events_per_night}'') = ''number''
    AND (_config #>> ''{sleep_compensation,min_late_events_per_night}'')::numeric > 0
    AND (_config #>> ''{sleep_compensation,min_late_events_per_night}'')::numeric
      = trunc((_config #>> ''{sleep_compensation,min_late_events_per_night}'')::numeric)
    AND jsonb_typeof(_config #> ''{sleep_compensation,timezone_tolerance_minutes}'') = ''number''
    AND (_config #>> ''{sleep_compensation,timezone_tolerance_minutes}'')::numeric >= 0
    AND (_config #>> ''{sleep_compensation,timezone_tolerance_minutes}'')::numeric
      = trunc((_config #>> ''{sleep_compensation,timezone_tolerance_minutes}'')::numeric)
    AND jsonb_typeof(_config -> ''evaluator'') = ''object''
    AND (_config -> ''evaluator'') ?& ARRAY[''contract_version'']
    AND jsonb_typeof(_config #> ''{evaluator,contract_version}'') = ''string''
    AND _config #>> ''{evaluator,contract_version}'' = ''adaptive_candidate_v1''
    AND jsonb_typeof(_config -> ''emergency'') = ''object''
    AND (_config -> ''emergency'') ?& ARRAY[
      ''contract_version'', ''neutral_minutes'', ''expected_live_definition_sha256''
    ]
    AND jsonb_typeof(_config #> ''{emergency,contract_version}'') = ''string''
    AND _config #>> ''{emergency,contract_version}'' = ''adr0022_v1''
    AND jsonb_typeof(_config #> ''{emergency,neutral_minutes}'') = ''number''
    AND (_config #>> ''{emergency,neutral_minutes}'')::numeric = 90
    AND (_config #>> ''{emergency,neutral_minutes}'')::numeric
      = trunc((_config #>> ''{emergency,neutral_minutes}'')::numeric)
    AND jsonb_typeof(_config #> ''{emergency,expected_live_definition_sha256}'') = ''string''
    AND (_config #>> ''{emergency,expected_live_definition_sha256}'') ~ ''^[a-f0-9]{64}$''
    AND _config #>> ''{emergency,expected_live_definition_sha256}''
      = ''1907d59473d274d46a0e8e0b9ce8027037b4494b0dddf073cb46abf67db92e21''
$$;

REVOKE ALL PRIVILEGES ON FUNCTION private.alert_candidate_config_is_valid(jsonb)
FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.pin_alert_gap_profile_contract()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''''
AS $$
BEGIN
  SELECT version.config_sha256, version.evidence_version
    INTO NEW.config_sha256, NEW.evidence_version
  FROM public.alert_model_versions AS version
  WHERE version.id = NEW.version_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION ''unknown alert model version %'', NEW.version_id
      USING ERRCODE = ''23503'';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER on_alert_gap_profile_contract_pin
BEFORE INSERT OR UPDATE ON public.alert_gap_profiles
FOR EACH ROW
EXECUTE FUNCTION private.pin_alert_gap_profile_contract();

REVOKE ALL PRIVILEGES ON FUNCTION private.pin_alert_gap_profile_contract()
FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.resolve_alert_candidate(
  _user_id uuid,
  _evaluated_at timestamptz,
  _version_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''''
SET TimeZone = ''UTC''
SET \"DateStyle\" = ''ISO, YMD''
SET extra_float_digits = 3
AS $$
DECLARE
  _evaluator_version constant text := ''adaptive_candidate_v1'';
  _version public.alert_model_versions%ROWTYPE;
  _subject public.alert_judgment_subject_contexts%ROWTYPE;
  _profile public.alert_gap_profiles%ROWTYPE;
  _prior public.routine_mode_cohort_priors%ROWTYPE;
  _latest_session record;
  _subject_count integer;
  _subject_id uuid;
  _subject_expected_sha text;
  _subject_expected_sensitivity text;
  _offset_minutes integer;
  _session_from timestamptz;
  _session_found boolean := false;
  _personal_min_samples integer;
  _personal_min_dates integer;
  _personal_min_span integer;
  _personal_max_age integer;
  _personal_min_confidence double precision;
  _cohort_max_age integer;
  _candidate_floor integer;
  _candidate_ceiling integer;
  _sensitivity_buffer integer;
  _emergency_neutral integer;
  _emergency_definition_sha text;
  _basis text;
  _neutral integer;
  _unclamped integer;
  _threshold integer;
  _cap_reason text;
  _confidence double precision;
  _quality_state text;
  _selected_source_sha text;
  _selected_source_support jsonb;
  _fallback_path text[] := ARRAY[]::text[];
  _sleep_ranges tstzrange[] := ARRAY[]::tstzrange[];
  _sleep_range tstzrange;
  _sleep_provenance jsonb := ''[]''::jsonb;
  _sleep_seconds double precision := 0;
  _wall_seconds double precision;
  _effective_minutes double precision;
  _remaining_seconds double precision;
  _awake_seconds double precision;
  _cursor timestamptz;
  _deadline timestamptz;
  _deadline_basis text;
  _would_alert boolean;
  _decision_provenance jsonb;
  _provenance_sha text;
  _unreplayable_reason text;
  _evaluated_at_utc text :=
    to_char(_evaluated_at AT TIME ZONE ''UTC'', ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'');
BEGIN
  SELECT version.*
    INTO _version
  FROM public.alert_model_versions AS version
  WHERE version.id = _version_id;

  IF NOT FOUND OR _version.status NOT IN (''replay'', ''shadow'') THEN
    _unreplayable_reason := ''invalid_version_status'';
  ELSIF _version.config_sha256
      <> encode(extensions.digest(_version.config::text, ''sha256''), ''hex'') THEN
    _unreplayable_reason := ''config_hash_mismatch'';
  ELSIF _version.evidence_version <> ''canonical-v2'' THEN
    _unreplayable_reason := ''unsupported_evidence_version'';
  END IF;

  -- Every helper-used config key (sessionization, context, personal, cohort,
  -- sensitivity buffers, candidate bounds, sleep compensation, evaluator,
  -- emergency) must have its required raw JSON type, enum/value, range, and
  -- integrality before any subject/session/profile/cohort evidence is read.
  -- A canonical config hash proves self-consistency, not validity: a
  -- pre-Task-6 legacy row can carry a self-consistent hash over malformed
  -- content (a JSON string where a number is required, an out-of-range or
  -- non-integral number, or a missing key), so this check cannot rely on
  -- casting first and catching failures after the fact.
  IF _unreplayable_reason IS NULL THEN
    IF NOT private.alert_candidate_config_is_valid(_version.config) THEN
      _unreplayable_reason := ''config_hash_mismatch'';
    ELSE
      _personal_min_samples :=
        (_version.config #>> ''{personal,min_samples}'')::integer;
      _personal_min_dates :=
        (_version.config #>> ''{personal,min_support_dates}'')::integer;
      _personal_min_span :=
        (_version.config #>> ''{personal,min_span_days}'')::integer;
      _personal_max_age :=
        (_version.config #>> ''{personal,max_age_days}'')::integer;
      _personal_min_confidence :=
        (_version.config #>> ''{personal,min_confidence}'')::double precision;
      _cohort_max_age :=
        (_version.config #>> ''{cohort,max_age_days}'')::integer;
      _candidate_floor :=
        (_version.config #>> ''{candidate_bounds,floor_minutes}'')::integer;
      _candidate_ceiling :=
        (_version.config #>> ''{candidate_bounds,ceiling_minutes}'')::integer;
      _emergency_neutral :=
        (_version.config #>> ''{emergency,neutral_minutes}'')::integer;
      _emergency_definition_sha :=
        _version.config #>> ''{emergency,expected_live_definition_sha256}'';
    END IF;
  END IF;

  IF _unreplayable_reason IS NULL THEN
    SELECT
      count(*)::integer,
      (array_agg(context.id ORDER BY context.captured_at, context.id))[1]
      INTO _subject_count, _subject_id
    FROM public.alert_judgment_subject_contexts AS context
    WHERE context.version_id = _version_id
      AND context.user_id = _user_id
      AND context.effective_from <= _evaluated_at
      AND (context.effective_to IS NULL OR _evaluated_at < context.effective_to)
      AND context.captured_at <= _evaluated_at;

    IF _subject_count = 0 THEN
      _unreplayable_reason := ''missing_subject_context'';
    ELSIF _subject_count <> 1 THEN
      _unreplayable_reason := ''ambiguous_subject_context'';
    ELSE
      SELECT context.*
        INTO _subject
      FROM public.alert_judgment_subject_contexts AS context
      WHERE context.id = _subject_id;

      _subject_expected_sensitivity := CASE
        WHEN lower(trim(coalesce(_subject.raw_sensitivity, ''''))) IN (''high'', ''sensitive'')
          THEN ''high''
        WHEN lower(trim(coalesce(_subject.raw_sensitivity, ''''))) IN (''low'', ''relaxed'')
          THEN ''low''
        ELSE ''balanced''
      END;

      _subject_expected_sha := encode(extensions.digest(jsonb_build_object(
        ''version_id'', _subject.version_id,
        ''user_id'', _subject.user_id,
        ''effective_from_utc'',
          to_char(_subject.effective_from AT TIME ZONE ''UTC'',
            ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
        ''effective_to_utc'',
          CASE WHEN _subject.effective_to IS NULL THEN NULL
            ELSE to_char(_subject.effective_to AT TIME ZONE ''UTC'',
              ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'')
          END,
        ''raw_sensitivity'', _subject.raw_sensitivity,
        ''canonical_sensitivity'', _subject.canonical_sensitivity,
        ''routine_mode'', _subject.routine_mode,
        ''timezone'', _subject.timezone,
        ''utc_offset_minutes'', _subject.utc_offset_minutes,
        ''settings_updated_at_utc'',
          to_char(_subject.settings_updated_at AT TIME ZONE ''UTC'',
            ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
        ''settings_provenance'', _subject.settings_provenance,
        ''captured_at_utc'',
          to_char(_subject.captured_at AT TIME ZONE ''UTC'',
            ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
        ''config_sha256'', _subject.config_sha256,
        ''evidence_version'', _subject.evidence_version
      )::text, ''sha256''), ''hex'');

      SELECT floor(extract(epoch FROM (
        ((_evaluated_at AT TIME ZONE _subject.timezone) AT TIME ZONE ''UTC'')
        - _evaluated_at
      )) / 60)::integer
        INTO _offset_minutes
      WHERE EXISTS (
        SELECT 1
        FROM pg_catalog.pg_timezone_names AS zone
        WHERE zone.name = _subject.timezone
      );

      IF _subject.config_sha256 <> _version.config_sha256
         OR _subject.evidence_version <> _version.evidence_version
         OR _subject.subject_context_sha256 <> _subject_expected_sha
         OR _subject.canonical_sensitivity <> _subject_expected_sensitivity
         OR _subject.routine_mode NOT IN (
           ''regular_9to5'', ''semester_break'', ''shift_irregular''
         )
         OR _offset_minutes IS NULL
         OR _offset_minutes <> _subject.utc_offset_minutes
         OR _subject.settings_updated_at > _subject.captured_at
         OR _subject.captured_at > _evaluated_at THEN
        _unreplayable_reason := ''subject_context_provenance_invalid'';
      END IF;
    END IF;
  END IF;

  IF _unreplayable_reason IS NULL THEN
    SELECT min(coverage.starts_at)
      INTO _session_from
    FROM public.alert_observation_coverage_intervals AS coverage
    WHERE coverage.version_id = _version_id
      AND coverage.user_id = _user_id
      AND coverage.starts_at < _evaluated_at;

    IF _session_from IS NOT NULL AND _session_from < _evaluated_at THEN
      SELECT session.*
        INTO _latest_session
      FROM private.qualified_behavior_sessions(
        _user_id, _session_from, _evaluated_at, _version_id
      ) AS session
      WHERE session.quality_state = ''valid''
      ORDER BY session.session_end DESC, session.session_start DESC
      LIMIT 1;
      _session_found := FOUND;
    END IF;

    IF NOT _session_found THEN
      _unreplayable_reason := ''missing_qualified_session'';
    END IF;
  END IF;

  IF _unreplayable_reason IS NOT NULL THEN
    _decision_provenance := jsonb_build_object(
      ''version_id'', _version_id,
      ''evaluator_version'', _evaluator_version,
      ''evaluated_at'', _evaluated_at_utc,
      ''evidence_cutoff'', _evaluated_at_utc,
      ''replayable'', false,
      ''unreplayable_reason'', _unreplayable_reason
    );
    _provenance_sha := encode(
      extensions.digest(_decision_provenance::text, ''sha256''), ''hex''
    );

    RETURN jsonb_build_object(
      ''version_id'', _version_id,
      ''evaluator_version'', _evaluator_version,
      ''evaluated_at'', _evaluated_at_utc,
      ''evidence_cutoff'', _evaluated_at_utc,
      ''replayable'', false,
      ''unreplayable_reason'', _unreplayable_reason,
      ''basis'', NULL,
      ''context_key'', NULL,
      ''neutral_threshold_minutes'', NULL,
      ''sensitivity_buffer_minutes'', NULL,
      ''unclamped_candidate_threshold_minutes'', NULL,
      ''candidate_floor_minutes'', NULL,
      ''candidate_ceiling_minutes'', NULL,
      ''candidate_cap_reason'', NULL,
      ''candidate_threshold_minutes'', NULL,
      ''effective_silence_minutes'', NULL,
      ''candidate_deadline'', NULL,
      ''deadline_basis'', NULL,
      ''would_alert'', NULL,
      ''confidence'', NULL,
      ''quality_state'', ''coverage_invalid'',
      ''fallback_path'', ''[]''::jsonb,
      ''sleep_interval_provenance'', ''[]''::jsonb,
      ''selected_source_sha256'', NULL,
      ''subject_context_sha256'', NULL,
      ''decision_provenance'', _decision_provenance,
      ''provenance_sha256'', _provenance_sha,
      ''guardian_used_as_activity'', false
    );
  END IF;

  _sensitivity_buffer := CASE _subject.canonical_sensitivity
    WHEN ''high'' THEN (_version.config #>> ''{sensitivity_buffers_minutes,high}'')::integer
    WHEN ''low'' THEN (_version.config #>> ''{sensitivity_buffers_minutes,low}'')::integer
    ELSE (_version.config #>> ''{sensitivity_buffers_minutes,balanced}'')::integer
  END;

  _fallback_path := ARRAY[''personal_context'']::text[];

  WITH latest AS MATERIALIZED (
    SELECT candidate.*
    FROM public.alert_gap_profiles AS candidate
    WHERE candidate.version_id = _version_id
      AND candidate.user_id = _user_id
      AND candidate.context_key = _latest_session.context_key
      AND ((candidate.through_date + 1)::timestamp AT TIME ZONE ''UTC'')
        <= _evaluated_at
      AND candidate.quality_state = ''valid''
      AND candidate.sample_count >= _personal_min_samples
      AND candidate.distinct_support_dates >= _personal_min_dates
      AND candidate.support_ended_on - candidate.support_started_on + 1
        >= _personal_min_span
      AND candidate.latest_evidence_at < _evaluated_at
      AND candidate.latest_evidence_at
        + make_interval(days => _personal_max_age) > _evaluated_at
      AND candidate.confidence >= _personal_min_confidence
      AND candidate.config_sha256 = _version.config_sha256
      AND candidate.evidence_version = _version.evidence_version
      AND candidate.profile_sha256 = encode(extensions.digest(jsonb_build_object(
        ''version_id'', candidate.version_id,
        ''user_id'', candidate.user_id,
        ''context_key'', candidate.context_key,
        ''through_date'', candidate.through_date,
        ''neutral_p95_minutes'', candidate.neutral_p95_minutes,
        ''sample_count'', candidate.sample_count,
        ''distinct_support_dates'', candidate.distinct_support_dates,
        ''support_started_on'', candidate.support_started_on,
        ''support_ended_on'', candidate.support_ended_on,
        ''latest_evidence_at_utc'',
          to_char(candidate.latest_evidence_at AT TIME ZONE ''UTC'',
            ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
        ''quality_state'', candidate.quality_state,
        ''confidence'', candidate.confidence,
        ''input_sha256'', candidate.input_sha256
      )::text, ''sha256''), ''hex'')
    ORDER BY candidate.through_date DESC
    LIMIT 1
  )
  SELECT candidate.*
    INTO _profile
  FROM latest AS candidate;

  IF FOUND THEN
    _basis := ''personal_context'';
  ELSE
    _fallback_path := pg_catalog.array_append(
      _fallback_path, ''personal_global''
    );
    WITH latest AS MATERIALIZED (
      SELECT candidate.*
      FROM public.alert_gap_profiles AS candidate
      WHERE candidate.version_id = _version_id
        AND candidate.user_id = _user_id
        AND candidate.context_key = ''personal_global''
        AND ((candidate.through_date + 1)::timestamp AT TIME ZONE ''UTC'')
          <= _evaluated_at
        AND candidate.quality_state = ''valid''
        AND candidate.sample_count >= _personal_min_samples
        AND candidate.distinct_support_dates >= _personal_min_dates
        AND candidate.support_ended_on - candidate.support_started_on + 1
          >= _personal_min_span
        AND candidate.latest_evidence_at < _evaluated_at
        AND candidate.latest_evidence_at
          + make_interval(days => _personal_max_age) > _evaluated_at
        AND candidate.confidence >= _personal_min_confidence
        AND candidate.config_sha256 = _version.config_sha256
        AND candidate.evidence_version = _version.evidence_version
        AND candidate.profile_sha256 = encode(extensions.digest(jsonb_build_object(
          ''version_id'', candidate.version_id,
          ''user_id'', candidate.user_id,
          ''context_key'', candidate.context_key,
          ''through_date'', candidate.through_date,
          ''neutral_p95_minutes'', candidate.neutral_p95_minutes,
          ''sample_count'', candidate.sample_count,
          ''distinct_support_dates'', candidate.distinct_support_dates,
          ''support_started_on'', candidate.support_started_on,
          ''support_ended_on'', candidate.support_ended_on,
          ''latest_evidence_at_utc'',
            to_char(candidate.latest_evidence_at AT TIME ZONE ''UTC'',
              ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
          ''quality_state'', candidate.quality_state,
          ''confidence'', candidate.confidence,
          ''input_sha256'', candidate.input_sha256
        )::text, ''sha256''), ''hex'')
      ORDER BY candidate.through_date DESC
      LIMIT 1
    )
    SELECT candidate.*
      INTO _profile
    FROM latest AS candidate;

    IF FOUND THEN
      _basis := ''personal_global'';
    END IF;
  END IF;

  IF _basis IN (''personal_context'', ''personal_global'') THEN
    _neutral := _profile.neutral_p95_minutes;
    _confidence := _profile.confidence;
    _quality_state := _profile.quality_state;
    _selected_source_sha := _profile.profile_sha256;
    _selected_source_support := jsonb_build_object(
      ''through_date'', _profile.through_date,
      ''sample_count'', _profile.sample_count,
      ''distinct_support_dates'', _profile.distinct_support_dates,
      ''support_started_on'', _profile.support_started_on,
      ''support_ended_on'', _profile.support_ended_on,
      ''latest_evidence_at_utc'',
        to_char(_profile.latest_evidence_at AT TIME ZONE ''UTC'',
          ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
      ''input_sha256'', _profile.input_sha256,
      ''profile_sha256'', _profile.profile_sha256,
      ''config_sha256'', _profile.config_sha256,
      ''evidence_version'', _profile.evidence_version
    );
  ELSE
    _fallback_path := pg_catalog.array_append(
      _fallback_path, ''routine_cohort''
    );

    WITH latest AS MATERIALIZED (
      SELECT candidate.*
      FROM public.routine_mode_cohort_priors AS candidate
      WHERE candidate.version_id = _version_id
        AND candidate.routine_mode = _subject.routine_mode
        AND candidate.context_key = ''personal_global''
        AND ((candidate.through_date + 1)::timestamp AT TIME ZONE ''UTC'')
          <= _evaluated_at
        AND candidate.latest_evidence_at < _evaluated_at
        AND candidate.oldest_evidence_at < _evaluated_at
        AND candidate.valid_until = least(
          candidate.oldest_evidence_at
            + make_interval(days => _personal_max_age),
          candidate.oldest_evidence_at
            + make_interval(days => _cohort_max_age)
        )
        AND private.routine_mode_cohort_prior_is_valid(
          _version_id,
          _subject.routine_mode,
          candidate.through_date,
          _evaluated_at
        )
      ORDER BY candidate.through_date DESC
      LIMIT 1
    )
    SELECT candidate.*
      INTO _prior
    FROM latest AS candidate;

    IF FOUND THEN
      _basis := ''routine_cohort'';
      _neutral := _prior.neutral_p95_minutes;
      _confidence := _prior.confidence;
      _quality_state := _prior.quality_state;
      _selected_source_sha := _prior.prior_sha256;
      _selected_source_support := jsonb_build_object(
        ''through_date'', _prior.through_date,
        ''contributor_count'', _prior.contributor_count,
        ''distinct_support_dates'', _prior.distinct_support_dates,
        ''conservative_span_days'', _prior.conservative_span_days,
        ''support_started_on'', _prior.support_started_on,
        ''support_ended_on'', _prior.support_ended_on,
        ''latest_evidence_at_utc'',
          to_char(_prior.latest_evidence_at AT TIME ZONE ''UTC'',
            ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
        ''oldest_evidence_at_utc'',
          to_char(_prior.oldest_evidence_at AT TIME ZONE ''UTC'',
            ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
        ''valid_until_utc'',
          to_char(_prior.valid_until AT TIME ZONE ''UTC'',
            ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
        ''minimum_profile_confidence'', _prior.minimum_profile_confidence,
        ''algorithm'', _prior.algorithm,
        ''source_generation'', _prior.source_generation,
        ''input_sha256'', _prior.input_sha256,
        ''prior_sha256'', _prior.prior_sha256,
        ''config_sha256'', _prior.config_sha256,
        ''evidence_version'', _prior.evidence_version
      );
    ELSE
      _fallback_path := pg_catalog.array_append(
        _fallback_path, ''deterministic_emergency''
      );
      _basis := ''deterministic_emergency'';
      _neutral := _emergency_neutral;
      _confidence := 0;
      _quality_state := ''low_support'';
      _selected_source_sha := NULL;
      _selected_source_support := jsonb_build_object(
        ''contract_version'', ''adr0022_v1'',
        ''neutral_minutes'', _emergency_neutral,
        ''expected_live_definition_sha256'', _emergency_definition_sha
      );
    END IF;
  END IF;

  _unclamped := _neutral + _sensitivity_buffer;
  IF _basis = ''deterministic_emergency'' THEN
    _threshold := _unclamped;
    _cap_reason := ''emergency_exempt'';
  ELSIF _unclamped < _candidate_floor THEN
    _threshold := _candidate_floor;
    _cap_reason := ''floor'';
  ELSIF _unclamped > _candidate_ceiling THEN
    _threshold := _candidate_ceiling;
    _cap_reason := ''ceiling'';
  ELSE
    _threshold := _unclamped;
    _cap_reason := ''none'';
  END IF;

  WITH raw_sleep AS MATERIALIZED (
    SELECT
      interval.starts_at,
      interval.ends_at,
      interval.basis,
      interval.confidence,
      interval.provenance,
      context.anchor_date,
      context.coverage_state,
      context.captured_at,
      context.finalized_at,
      context.provenance_sha256 AS context_provenance_sha256,
      tstzrange(
        greatest(interval.starts_at, _latest_session.session_end),
        least(interval.ends_at, _evaluated_at),
        ''[)''
      ) AS clipped_range
    FROM private.candidate_sleep_intervals(
      _user_id,
      _latest_session.session_end,
      _evaluated_at,
      _version_id
    ) AS interval
    JOIN public.alert_sleep_night_contexts AS context
      ON context.version_id = _version_id
     AND context.user_id = _user_id
     AND context.anchor_starts_at =
       (interval.provenance ->> ''anchor_starts_at'')::timestamptz
     AND context.anchor_ends_at =
       (interval.provenance ->> ''anchor_ends_at'')::timestamptz
     AND context.evidence_version = _version.evidence_version
     AND context.captured_at <= _evaluated_at
     AND (
       (
         context.coverage_state = ''unknown''
         AND (
           context.finalized_at IS NULL
           OR context.finalized_at <= _evaluated_at
         )
       )
       OR (
         context.coverage_state IN (''valid'', ''outage'')
         AND context.finalized_at IS NOT NULL
         AND context.finalized_at >= context.anchor_ends_at
         AND context.finalized_at <= _evaluated_at
       )
     )
    WHERE interval.starts_at < _evaluated_at
      AND interval.ends_at > _latest_session.session_end
      AND greatest(interval.starts_at, _latest_session.session_end)
        < least(interval.ends_at, _evaluated_at)
  ), merged AS (
    SELECT unnest(range_agg(raw_sleep.clipped_range)) AS merged_range
    FROM raw_sleep
  ), described AS (
    SELECT
      merged.merged_range,
      jsonb_build_object(
        ''starts_at_utc'',
          to_char(lower(merged.merged_range) AT TIME ZONE ''UTC'',
            ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
        ''ends_at_utc'',
          to_char(upper(merged.merged_range) AT TIME ZONE ''UTC'',
            ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
        ''sources'', (
          SELECT jsonb_agg(jsonb_build_object(
            ''starts_at_utc'',
              to_char(source.starts_at AT TIME ZONE ''UTC'',
                ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
            ''ends_at_utc'',
              to_char(source.ends_at AT TIME ZONE ''UTC'',
                ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
            ''basis'', source.basis,
            ''confidence'', source.confidence,
            ''anchor_date'', source.anchor_date,
            ''coverage_state'', source.coverage_state,
            ''captured_at_utc'',
              to_char(source.captured_at AT TIME ZONE ''UTC'',
                ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
            ''finalized_at_utc'',
              CASE WHEN source.finalized_at IS NULL THEN NULL
                ELSE to_char(source.finalized_at AT TIME ZONE ''UTC'',
                  ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'')
              END,
            ''context_provenance_sha256'', source.context_provenance_sha256,
            ''interval_provenance'', source.provenance
          ) ORDER BY
            source.starts_at, source.ends_at, source.basis,
            source.confidence, source.provenance::text)
          FROM raw_sleep AS source
          WHERE source.clipped_range && merged.merged_range
        )
      ) AS provenance
    FROM merged
  )
  SELECT
    coalesce(
      array_agg(described.merged_range ORDER BY lower(described.merged_range)),
      ARRAY[]::tstzrange[]
    ),
    coalesce(
      jsonb_agg(described.provenance ORDER BY lower(described.merged_range)),
      ''[]''::jsonb
    )
    INTO _sleep_ranges, _sleep_provenance
  FROM described;

  FOREACH _sleep_range IN ARRAY _sleep_ranges
  LOOP
    _sleep_seconds := _sleep_seconds
      + extract(epoch FROM (upper(_sleep_range) - lower(_sleep_range)));
  END LOOP;

  _wall_seconds :=
    extract(epoch FROM (_evaluated_at - _latest_session.session_end));
  _effective_minutes :=
    greatest(0::double precision, _wall_seconds - _sleep_seconds) / 60.0;
  _would_alert := _effective_minutes >= _threshold;

  IF _would_alert THEN
    _deadline_basis := ''known_interval_inversion'';
    _remaining_seconds := _threshold::double precision * 60.0;
    _cursor := _latest_session.session_end;

    FOREACH _sleep_range IN ARRAY _sleep_ranges
    LOOP
      IF lower(_sleep_range) > _cursor THEN
        _awake_seconds := extract(epoch FROM (lower(_sleep_range) - _cursor));
        IF _remaining_seconds <= _awake_seconds THEN
          _deadline := _cursor + make_interval(secs => _remaining_seconds);
          EXIT;
        END IF;
        _remaining_seconds := _remaining_seconds - _awake_seconds;
      END IF;
      _cursor := greatest(_cursor, upper(_sleep_range));
    END LOOP;

    IF _deadline IS NULL THEN
      _deadline := _cursor + make_interval(secs => _remaining_seconds);
    END IF;
  ELSE
    _deadline_basis := ''no_future_exclusion'';
    _deadline := _evaluated_at
      + make_interval(secs => (_threshold - _effective_minutes) * 60.0);
  END IF;

  _decision_provenance := jsonb_build_object(
    ''version_id'', _version_id,
    ''evaluator_version'', _evaluator_version,
    ''evaluated_at'', _evaluated_at_utc,
    ''evidence_cutoff'', _evaluated_at_utc,
    ''replayable'', true,
    ''unreplayable_reason'', NULL,
    ''model_config_sha256'', _version.config_sha256,
    ''evidence_version'', _version.evidence_version,
    ''emergency_contract_version'',
      _version.config #>> ''{emergency,contract_version}'',
    ''emergency_expected_live_definition_sha256'', _emergency_definition_sha,
    ''subject_context_sha256'', _subject.subject_context_sha256,
    ''canonical_sensitivity'', _subject.canonical_sensitivity,
    ''routine_mode'', _subject.routine_mode,
    ''timezone'', _subject.timezone,
    ''utc_offset_minutes'', _subject.utc_offset_minutes,
    ''latest_session'', jsonb_build_object(
      ''session_start_utc'',
        to_char(_latest_session.session_start AT TIME ZONE ''UTC'',
          ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
      ''session_end_utc'',
        to_char(_latest_session.session_end AT TIME ZONE ''UTC'',
          ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
      ''context_key'', _latest_session.context_key,
      ''evidence_count'', _latest_session.evidence_count,
      ''quality_state'', _latest_session.quality_state
    ),
    ''basis'', _basis,
    ''fallback_path'', to_jsonb(_fallback_path),
    ''selected_source_sha256'', _selected_source_sha,
    ''selected_source_support'', _selected_source_support,
    ''neutral_threshold_minutes'', _neutral,
    ''sensitivity_buffer_minutes'', _sensitivity_buffer,
    ''unclamped_candidate_threshold_minutes'', _unclamped,
    ''candidate_floor_minutes'', _candidate_floor,
    ''candidate_ceiling_minutes'', _candidate_ceiling,
    ''candidate_cap_reason'', _cap_reason,
    ''candidate_threshold_minutes'', _threshold,
    ''sleep_interval_provenance'', _sleep_provenance,
    ''effective_silence_minutes'', _effective_minutes,
    ''candidate_deadline'',
      to_char(_deadline AT TIME ZONE ''UTC'',
        ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
    ''deadline_basis'', _deadline_basis,
    ''would_alert'', _would_alert,
    ''confidence'', _confidence,
    ''quality_state'', _quality_state,
    ''guardian_used_as_activity'', false
  );
  _provenance_sha := encode(
    extensions.digest(_decision_provenance::text, ''sha256''), ''hex''
  );

  RETURN jsonb_build_object(
    ''version_id'', _version_id,
    ''evaluator_version'', _evaluator_version,
    ''evaluated_at'', _evaluated_at_utc,
    ''evidence_cutoff'', _evaluated_at_utc,
    ''replayable'', true,
    ''unreplayable_reason'', NULL,
    ''basis'', _basis,
    ''context_key'', _latest_session.context_key,
    ''neutral_threshold_minutes'', _neutral,
    ''sensitivity_buffer_minutes'', _sensitivity_buffer,
    ''unclamped_candidate_threshold_minutes'', _unclamped,
    ''candidate_floor_minutes'', _candidate_floor,
    ''candidate_ceiling_minutes'', _candidate_ceiling,
    ''candidate_cap_reason'', _cap_reason,
    ''candidate_threshold_minutes'', _threshold,
    ''effective_silence_minutes'', _effective_minutes,
    ''candidate_deadline'',
      to_char(_deadline AT TIME ZONE ''UTC'',
        ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
    ''deadline_basis'', _deadline_basis,
    ''would_alert'', _would_alert,
    ''confidence'', _confidence,
    ''quality_state'', _quality_state,
    ''fallback_path'', to_jsonb(_fallback_path),
    ''sleep_interval_provenance'', _sleep_provenance,
    ''selected_source_sha256'', _selected_source_sha,
    ''subject_context_sha256'', _subject.subject_context_sha256,
    ''decision_provenance'', _decision_provenance,
    ''provenance_sha256'', _provenance_sha,
    ''guardian_used_as_activity'', false
  );
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.resolve_alert_candidate(uuid, timestamptz, uuid)
FROM PUBLIC, anon, authenticated, service_role;

-- Task 3''s original helper predates a fixed replay cutoff for context
-- finalization. Preserve its algorithm and signature, but make both the
-- evaluated night and every prior night strictly as-of `_to`.
CREATE OR REPLACE FUNCTION private.candidate_sleep_intervals(
  _user_id uuid,
  _from timestamptz,
  _to timestamptz,
  _version_id uuid
)
RETURNS TABLE (
  starts_at timestamptz,
  ends_at timestamptz,
  basis text,
  confidence double precision,
  provenance jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''''
SET TimeZone = ''UTC''
SET \"DateStyle\" = ''ISO, YMD''
SET extra_float_digits = 3
AS $$
DECLARE
  _config jsonb;
  _config_sha256 text;
  _max_start_delay integer;
  _max_wake_advance integer;
  _max_wake_delay integer;
  _max_update_per_day integer;
  _min_positive integer;
  _lookback integer;
  _min_late_events integer;
  _timezone_tolerance integer;
  _status text;
  _evidence_version text;
  _context record;
  _anchor_start timestamptz;
  _anchor_end timestamptz;
  _midpoint timestamptz;
  _raw_start_delay integer;
  _raw_wake_advance integer;
  _raw_wake_delay integer;
  _start_delay integer;
  _wake_advance integer;
  _wake_delay integer;
  _rate_cap integer;
  _first_count integer;
  _second_count integer;
  _prior_count integer;
  _prior_start_cap_applied boolean;
  _quality_reason text;
  _cap_reasons text[];
  _offset_minutes integer;
BEGIN
  IF _user_id IS NULL OR _version_id IS NULL
     OR _from IS NULL OR _to IS NULL OR _from >= _to THEN
    RETURN;
  END IF;

  SELECT version.config, version.config_sha256,
         version.status, version.evidence_version
    INTO _config, _config_sha256, _status, _evidence_version
  FROM public.alert_model_versions AS version
  WHERE version.id = _version_id;

  IF NOT FOUND
     OR _status NOT IN (''replay'', ''shadow'')
     OR _evidence_version <> ''canonical-v2''
     OR _config_sha256
        <> encode(extensions.digest(_config::text, ''sha256''), ''hex'') THEN
    RETURN;
  END IF;

  -- See private.alert_candidate_config_is_valid: a canonical config hash
  -- cannot prove a legacy row''s scalars have the required raw JSON type,
  -- range, or integrality, so this must be checked before any type is
  -- assumed from a bare cast.
  IF NOT private.alert_candidate_config_is_valid(_config) THEN
    RETURN;
  END IF;

  _max_start_delay :=
    (_config #>> ''{sleep_compensation,max_start_delay_minutes}'')::integer;
  _max_wake_advance :=
    (_config #>> ''{sleep_compensation,max_wake_advance_minutes}'')::integer;
  _max_wake_delay :=
    (_config #>> ''{sleep_compensation,max_wake_delay_minutes}'')::integer;
  _max_update_per_day :=
    (_config #>> ''{sleep_compensation,max_update_minutes_per_day}'')::integer;
  _min_positive :=
    (_config #>> ''{sleep_compensation,min_positive_nights}'')::integer;
  _lookback :=
    (_config #>> ''{sleep_compensation,lookback_nights}'')::integer;
  _min_late_events :=
    (_config #>> ''{sleep_compensation,min_late_events_per_night}'')::integer;
  _timezone_tolerance :=
    (_config #>> ''{sleep_compensation,timezone_tolerance_minutes}'')::integer;

  FOR _context IN
    SELECT context.*
    FROM public.alert_sleep_night_contexts AS context
    WHERE context.version_id = _version_id
      AND context.user_id = _user_id
      AND context.evidence_version = ''canonical-v2''
      AND context.anchor_starts_at < _to
      AND context.anchor_ends_at > _from
      AND context.captured_at <= _to
      AND (
        (
          context.coverage_state = ''unknown''
          AND (context.finalized_at IS NULL OR context.finalized_at <= _to)
        )
        OR (
          context.coverage_state IN (''valid'', ''outage'')
          AND context.finalized_at IS NOT NULL
          AND context.finalized_at >= context.anchor_ends_at
          AND context.finalized_at <= _to
        )
      )
    ORDER BY context.anchor_starts_at
  LOOP
    IF NOT EXISTS (
         SELECT 1
         FROM pg_catalog.pg_timezone_names AS zone
         WHERE zone.name = _context.timezone
       )
       OR _context.sleep_start_local = _context.sleep_end_local
       OR _context.anchor_ends_at <= _context.anchor_starts_at
       OR _context.captured_at > _context.anchor_starts_at
       OR (
         _context.coverage_state IN (''valid'', ''outage'')
         AND (
           _context.finalized_at IS NULL
           OR _context.finalized_at < _context.anchor_ends_at
           OR _context.finalized_at > _to
         )
       )
       OR (
         _context.coverage_state = ''unknown''
         AND _context.finalized_at IS NOT NULL
         AND _context.finalized_at > _to
       ) THEN
      CONTINUE;
    END IF;

    _anchor_start :=
      ((_context.anchor_date + _context.sleep_start_local)
        AT TIME ZONE _context.timezone);
    _anchor_end := ((
      _context.anchor_date
      + CASE
          WHEN _context.sleep_end_local <= _context.sleep_start_local THEN 1
          ELSE 0
        END
      + _context.sleep_end_local
    ) AT TIME ZONE _context.timezone);
    _offset_minutes := extract(epoch FROM (
      ((_context.anchor_starts_at AT TIME ZONE _context.timezone)
        AT TIME ZONE ''UTC'') - _context.anchor_starts_at
    ))::integer / 60;

    IF _anchor_start <> _context.anchor_starts_at
       OR _anchor_end <> _context.anchor_ends_at
       OR _offset_minutes <> _context.utc_offset_minutes THEN
      CONTINUE;
    END IF;

    _midpoint := _anchor_start + ((_anchor_end - _anchor_start) / 2);
    SELECT
      count(*) FILTER (
        WHERE ping.received_at >= _anchor_start
          AND ping.received_at < _midpoint
      )::integer,
      count(*) FILTER (
        WHERE ping.received_at >= _midpoint
          AND ping.received_at < _anchor_end
      )::integer,
      coalesce(floor(extract(epoch FROM (
        max(ping.received_at) FILTER (
          WHERE ping.received_at >= _anchor_start
            AND ping.received_at < _midpoint
        ) - _anchor_start
      )) / 60)::integer, 0),
      coalesce(floor(extract(epoch FROM (
        _anchor_end - min(ping.received_at) FILTER (
          WHERE ping.received_at >= _midpoint
            AND ping.received_at < _anchor_end
        )
      )) / 60)::integer, 0)
      INTO _first_count, _second_count,
           _raw_start_delay, _raw_wake_advance
    FROM public.behavior_pings AS ping
    WHERE ping.user_id = _user_id
      AND ping.ingest_version = 2
      AND abs(extract(epoch FROM (ping.received_at - ping.at))) <= 300
      AND ping.at < _to
      AND ping.received_at < _to;

    _cap_reasons := ARRAY[]::text[];
    IF _raw_start_delay > _max_start_delay THEN
      _cap_reasons := pg_catalog.array_append(
        _cap_reasons, ''max_start_delay_minutes''
      );
    END IF;
    IF _raw_wake_advance > _max_wake_advance THEN
      _cap_reasons := pg_catalog.array_append(
        _cap_reasons, ''max_wake_advance_minutes''
      );
    END IF;
    _start_delay := least(_max_start_delay, greatest(0, _raw_start_delay));
    _wake_advance := least(_max_wake_advance, greatest(0, _raw_wake_advance));
    _wake_delay := 0;
    _raw_wake_delay := 0;
    _rate_cap := 0;
    _prior_count := 0;
    _prior_start_cap_applied := false;
    _quality_reason := CASE
      WHEN _context.coverage_state = ''valid'' THEN ''coverage_valid''
      ELSE ''coverage_'' || _context.coverage_state
    END;

    IF _context.coverage_state = ''valid'' THEN
      WITH prior_contexts AS (
        SELECT
          prior.anchor_date,
          prior.anchor_starts_at,
          prior.anchor_ends_at,
          prior.anchor_starts_at
            + ((prior.anchor_ends_at - prior.anchor_starts_at) / 2)
            AS midpoint
        FROM public.alert_sleep_night_contexts AS prior
        WHERE prior.version_id = _version_id
          AND prior.user_id = _user_id
          AND prior.coverage_state = ''valid''
          AND prior.evidence_version = ''canonical-v2''
          AND prior.anchor_date < _context.anchor_date
          AND prior.anchor_date >= (_context.anchor_date - _lookback)
          AND prior.timezone = _context.timezone
          AND abs(prior.utc_offset_minutes - _context.utc_offset_minutes)
            <= _timezone_tolerance
          AND prior.captured_at <= prior.anchor_starts_at
          AND prior.captured_at <= _to
          AND prior.finalized_at >= prior.anchor_ends_at
          AND prior.finalized_at <= _to
          AND (
            (prior.anchor_date + prior.sleep_start_local)
              AT TIME ZONE prior.timezone
          ) = prior.anchor_starts_at
          AND ((
            prior.anchor_date
            + CASE
                WHEN prior.sleep_end_local <= prior.sleep_start_local THEN 1
                ELSE 0
              END
            + prior.sleep_end_local
          ) AT TIME ZONE prior.timezone) = prior.anchor_ends_at
          AND extract(epoch FROM (
            ((prior.anchor_starts_at AT TIME ZONE prior.timezone)
              AT TIME ZONE ''UTC'') - prior.anchor_starts_at
          ))::integer / 60 = prior.utc_offset_minutes
      ), prior_delays AS (
        SELECT
          prior.anchor_date,
          floor(extract(epoch FROM (
            max(ping.received_at) - prior.anchor_starts_at
          )) / 60)::integer AS raw_delay_minutes,
          least(
            _max_start_delay,
            floor(extract(epoch FROM (
              max(ping.received_at) - prior.anchor_starts_at
            )) / 60)::integer
          ) AS delay_minutes
        FROM prior_contexts AS prior
        JOIN public.behavior_pings AS ping
          ON ping.user_id = _user_id
         AND ping.ingest_version = 2
         AND abs(extract(epoch FROM (ping.received_at - ping.at))) <= 300
         AND ping.at < _to
         AND ping.received_at < _to
         AND ping.received_at >= prior.anchor_starts_at
         AND ping.received_at < prior.midpoint
        GROUP BY prior.anchor_date, prior.anchor_starts_at
        HAVING count(*) >= _min_late_events
      )
      SELECT
        count(*)::integer,
        coalesce(
          percentile_disc(0.5)
            WITHIN GROUP (ORDER BY delay_minutes)::integer,
          0
        ),
        coalesce(bool_or(raw_delay_minutes > _max_start_delay), false)
        INTO _prior_count, _raw_wake_delay, _prior_start_cap_applied
      FROM prior_delays;

      IF _prior_count >= _min_positive THEN
        _rate_cap :=
          greatest(0, _prior_count - _min_positive + 1)
          * _max_update_per_day;
        IF _prior_start_cap_applied THEN
          _cap_reasons := pg_catalog.array_append(
            _cap_reasons, ''prior_max_start_delay_minutes''
          );
        END IF;
        IF _raw_wake_delay > _max_wake_delay THEN
          _cap_reasons := pg_catalog.array_append(
            _cap_reasons, ''max_wake_delay_minutes''
          );
        END IF;
        IF least(_raw_wake_delay, _max_wake_delay) > _rate_cap THEN
          _cap_reasons := pg_catalog.array_append(
            _cap_reasons, ''max_update_minutes_per_day''
          );
        END IF;
        _wake_delay :=
          least(_max_wake_delay, _raw_wake_delay, _rate_cap);
        _quality_reason := ''coverage_valid_prior_positive'';
      ELSE
        _wake_delay := 0;
      END IF;
    END IF;

    starts_at := _anchor_start + make_interval(mins => _start_delay);
    ends_at := _anchor_end
      - make_interval(mins => _wake_advance)
      + make_interval(mins => _wake_delay);
    IF starts_at >= ends_at THEN
      CONTINUE;
    END IF;

    basis := CASE
      WHEN _start_delay > 0 OR _wake_advance > 0 OR _wake_delay > 0
        THEN ''positive_evidence_adjusted''
      ELSE ''configured_anchor''
    END;
    confidence := CASE
      WHEN _start_delay > 0 OR _wake_advance > 0 THEN 1.0
      WHEN _wake_delay > 0 THEN least(
        1.0,
        _prior_count::double precision / _min_positive::double precision
      )
      ELSE 0.0
    END;
    provenance := jsonb_build_object(
      ''config_sha256'', _config_sha256,
      ''anchor_starts_at'', _anchor_start,
      ''anchor_ends_at'', _anchor_end,
      ''context_captured_at'', _context.captured_at,
      ''context_finalized_at'', _context.finalized_at,
      ''context_evidence_version'', _context.evidence_version,
      ''context_provenance_sha256'', _context.provenance_sha256,
      ''evidence_cutoff'', _to,
      ''first_half_positive_count'', _first_count,
      ''second_half_positive_count'', _second_count,
      ''prior_positive_night_count'', _prior_count,
      ''start_delay_minutes'', _start_delay,
      ''wake_advance_minutes'', _wake_advance,
      ''wake_delay_minutes'', _wake_delay,
      ''caps'', jsonb_build_object(
        ''max_start_delay_minutes'', _max_start_delay,
        ''max_wake_advance_minutes'', _max_wake_advance,
        ''max_wake_delay_minutes'', _max_wake_delay,
        ''max_update_minutes_per_day'', _max_update_per_day
      ),
      ''confidence'', confidence,
      ''cap_reason'',
        coalesce(pg_catalog.array_to_string(_cap_reasons, '',''), ''none''),
      ''timezone'', _context.timezone,
      ''utc_offset_minutes'', _context.utc_offset_minutes,
      ''coverage_state'', _context.coverage_state,
      ''quality_reason'', _quality_reason
    );
    RETURN NEXT;
  END LOOP;
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.candidate_sleep_intervals(uuid, timestamptz, timestamptz, uuid)
FROM PUBLIC, anon, authenticated, service_role;

-- Append-only harden the Task 4/5 candidate hash producers/validators this
-- pipeline invokes so their canonical-hash serialization cannot vary with a
-- caller''s session DateStyle/extra_float_digits. Their bodies and signatures
-- are untouched; only their pinned configuration parameters are extended.
ALTER FUNCTION private.rebuild_alert_gap_profiles(uuid, date)
  SET \"DateStyle\" = ''ISO, YMD'';
ALTER FUNCTION private.rebuild_alert_gap_profiles(uuid, date)
  SET extra_float_digits = 3;

ALTER FUNCTION private.rebuild_routine_mode_cohort_priors(uuid, date, text)
  SET \"DateStyle\" = ''ISO, YMD'';
ALTER FUNCTION private.rebuild_routine_mode_cohort_priors(uuid, date, text)
  SET extra_float_digits = 3;

ALTER FUNCTION private.routine_mode_cohort_prior_is_valid(
  uuid, text, date, timestamptz
) SET \"DateStyle\" = ''ISO, YMD'';
ALTER FUNCTION private.routine_mode_cohort_prior_is_valid(
  uuid, text, date, timestamptz
) SET extra_float_digits = 3;
"}', 'adaptive_alert_candidate_evaluator', 'codex-release-v0.5.21', NULL, NULL),
	('20260725170000', '{"-- ADR-0023 Task 7: deterministic aggregate-only historical replay.
-- This migration adds no context/coverage/sleep producer, no scheduler, no
-- live-alert write, and no notification path. The existing ADR-0022 live
-- threshold and Guardian 30-minute state machine remain unchanged. Replay
-- enumerates completed canonical-v2 raw session gaps once, set-wise, inside
-- an internal MATERIALIZED CTE (never a temp/permanent per-user table),
-- calls the locked Task 6 private.resolve_alert_candidate exactly once per
-- bounded unit, and writes only the aggregate-only public.alert_judgment_evaluations
-- row created in Task 2. promotion_eligible is hard-pinned false.

-- Unlike Task 6''s evaluator contract, the replay section is required only
-- for versions that are actually replayed: a blanket table CHECK would
-- reject every pre-Task-7 alert_model_versions fixture that never calls
-- run_alert_judgment_replay. private.replay_config_is_valid below is
-- therefore enforced only inside the replay entrypoint itself.

-- Raw-type-first replay config gate. A canonical config_sha256 only proves
-- the stored config matches its own hash; it says nothing about whether the
-- replay section carries the right JSON type, enum, range, or integrality.
CREATE FUNCTION private.replay_config_is_valid(_config jsonb)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''''
SET TimeZone = ''UTC''
SET extra_float_digits = 3
AS $$
  SELECT CASE
    WHEN jsonb_typeof(_config) IS DISTINCT FROM ''object''
      OR jsonb_typeof(_config -> ''replay'') IS DISTINCT FROM ''object''
      OR NOT ((_config -> ''replay'') ?& ARRAY[
        ''contract_version'', ''max_range_days'', ''max_units''
      ])
      OR jsonb_typeof(_config #> ''{replay,contract_version}'') IS DISTINCT FROM ''string''
      OR jsonb_typeof(_config #> ''{replay,max_range_days}'') IS DISTINCT FROM ''number''
      OR jsonb_typeof(_config #> ''{replay,max_units}'') IS DISTINCT FROM ''number''
    THEN false
    ELSE
      _config #>> ''{replay,contract_version}'' = ''adaptive_replay_v1''
      AND (_config #>> ''{replay,max_range_days}'')::numeric BETWEEN 1 AND 2147483647
      AND (_config #>> ''{replay,max_range_days}'')::numeric
        = trunc((_config #>> ''{replay,max_range_days}'')::numeric)
      AND (_config #>> ''{replay,max_units}'')::numeric BETWEEN 1 AND 2147483647
      AND (_config #>> ''{replay,max_units}'')::numeric
        = trunc((_config #>> ''{replay,max_units}'')::numeric)
  END
$$;

REVOKE ALL PRIVILEGES ON FUNCTION private.replay_config_is_valid(jsonb)
FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.run_alert_judgment_replay(
  _version_id uuid,
  _from timestamptz,
  _to timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET TimeZone = ''UTC''
SET \"DateStyle\" = ''ISO, YMD''
SET extra_float_digits = 3
AS $$
DECLARE
  _replay_contract constant text := ''adaptive_replay_v1'';
  _evaluator_contract constant text := ''adaptive_candidate_v1'';
  _version public.alert_model_versions%ROWTYPE;
  _gap_minutes integer;
  _max_range_days integer;
  _max_units integer;
  _unit_count integer;
  _units_captured jsonb;
  _evaluated_count integer;
  _replayable_count integer;
  _unreplayable_count integer;
  _unreplayable_reason_counts jsonb;
  _live_alert_rows_observed integer;
  _unmatched_live_silence_alert_rows integer;
  _candidate_would_alert_gaps integer;
  _proxy_denominator integer;
  _both_proxy integer;
  _live_only_proxy integer;
  _candidate_only_proxy integer;
  _neither_proxy integer;
  _threshold_delta_denominator integer;
  _median_delta double precision;
  _p95_delta double precision;
  _basis_counts jsonb;
  _quality_counts jsonb;
  _cap_reason_counts jsonb;
  _report_status text;
  _units_json jsonb;
  _unmatched_json jsonb;
  _metrics jsonb;
  _input_sha text;
  _output_sha text;
  _from_utc text := to_char(_from AT TIME ZONE ''UTC'', ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'');
  _to_utc text := to_char(_to AT TIME ZONE ''UTC'', ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'');
BEGIN
  IF _version_id IS NULL OR _from IS NULL OR _to IS NULL OR NOT (_from < _to) THEN
    RAISE EXCEPTION ''adaptive_alert_replay_invalid_range''
      USING DETAIL = ''from must be strictly less than to'';
  END IF;

  SELECT v.* INTO _version
  FROM public.alert_model_versions AS v
  WHERE v.id = _version_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION ''adaptive_alert_replay_unknown_version'';
  END IF;

  IF _version.status <> ''replay'' THEN
    RAISE EXCEPTION ''adaptive_alert_replay_invalid_version_status'';
  END IF;

  IF _version.config_sha256
      <> encode(extensions.digest(_version.config::text, ''sha256''), ''hex'') THEN
    RAISE EXCEPTION ''adaptive_alert_replay_config_hash_mismatch'';
  END IF;

  IF _version.evidence_version <> ''canonical-v2'' THEN
    RAISE EXCEPTION ''adaptive_alert_replay_unsupported_evidence_version'';
  END IF;

  IF NOT private.alert_candidate_config_is_valid(_version.config) THEN
    RAISE EXCEPTION ''adaptive_alert_replay_invalid_evaluator_config'';
  END IF;

  IF _version.config #>> ''{evaluator,contract_version}'' <> _evaluator_contract THEN
    RAISE EXCEPTION ''adaptive_alert_replay_unsupported_evaluator_contract'';
  END IF;

  IF NOT private.replay_config_is_valid(_version.config) THEN
    RAISE EXCEPTION ''adaptive_alert_replay_invalid_replay_config'';
  END IF;

  IF _version.config #>> ''{replay,contract_version}'' <> _replay_contract THEN
    RAISE EXCEPTION ''adaptive_alert_replay_unsupported_replay_contract'';
  END IF;

  _max_range_days := (_version.config #>> ''{replay,max_range_days}'')::integer;
  _max_units := (_version.config #>> ''{replay,max_units}'')::integer;
  _gap_minutes := (_version.config #>> ''{sessionization,gap_minutes}'')::integer;

  IF (_to - _from) > make_interval(days => _max_range_days) THEN
    RAISE EXCEPTION ''adaptive_alert_replay_range_exceeds_max_range_days'';
  END IF;

  -- Enumerate and sessionize exactly once, in exactly one MATERIALIZED CTE,
  -- inside a single statement/snapshot. The bounded result is captured into
  -- an in-memory jsonb array only (never a temp/permanent table, never a
  -- per-user row anywhere): no later statement re-reads behavior_pings, so
  -- no concurrent ping insert between statements can change what was
  -- counted against replay.max_units or what gets evaluated below.
  WITH candidate_replay_units AS MATERIALIZED (
    WITH range_admitted AS (
      SELECT p.id, p.user_id, p.received_at
      FROM public.behavior_pings AS p
      WHERE p.ingest_version = 2
        AND p.received_at >= _from
        AND p.received_at < _to
        AND p.at < _to
        AND abs(extract(epoch FROM (p.received_at - p.at))) <= 300
    ), prior_admitted AS (
      SELECT prior.id, prior.user_id, prior.received_at
      FROM (SELECT DISTINCT user_id FROM range_admitted) AS active_user
      CROSS JOIN LATERAL (
        SELECT p.id, p.user_id, p.received_at
        FROM public.behavior_pings AS p
        WHERE p.user_id = active_user.user_id
          AND p.ingest_version = 2
          AND p.received_at < _from
          AND p.at < _to
          AND abs(extract(epoch FROM (p.received_at - p.at))) <= 300
        ORDER BY p.received_at DESC, p.id DESC
        LIMIT 1
      ) AS prior
    ), admitted AS (
      SELECT * FROM range_admitted
      UNION ALL
      SELECT * FROM prior_admitted
    ), marked AS (
      SELECT admitted.*,
        CASE
          WHEN lag(received_at) OVER (PARTITION BY user_id ORDER BY received_at, id) IS NULL
            OR received_at - lag(received_at) OVER (PARTITION BY user_id ORDER BY received_at, id)
              > make_interval(mins => _gap_minutes)
          THEN 1 ELSE 0
        END AS starts_session
      FROM admitted
    ), grouped AS (
      SELECT marked.*,
        sum(starts_session) OVER (PARTITION BY user_id ORDER BY received_at, id) AS session_no
      FROM marked
    ), summarized AS (
      SELECT user_id, session_no,
        min(received_at) AS session_start,
        max(received_at) AS session_end
      FROM grouped
      GROUP BY user_id, session_no
    ), ordered AS (
      SELECT user_id, session_end,
        lead(session_start) OVER (PARTITION BY user_id ORDER BY session_start) AS next_start
      FROM summarized
    )
    SELECT user_id, session_end, next_start
    FROM ordered
    WHERE next_start IS NOT NULL
      AND next_start >= _from
      AND next_start < _to
  )
  SELECT
    count(*)::integer,
    coalesce(jsonb_agg(
      jsonb_build_object(
        ''user_id'', user_id,
        ''session_end_utc'',
          to_char(session_end AT TIME ZONE ''UTC'', ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
        ''next_start_utc'',
          to_char(next_start AT TIME ZONE ''UTC'', ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'')
      )
      ORDER BY session_end, next_start, user_id
    ), ''[]''::jsonb)
  INTO _unit_count, _units_captured
  FROM candidate_replay_units;

  IF _unit_count > _max_units THEN
    RAISE EXCEPTION ''adaptive_alert_replay_max_units_exceeded'';
  END IF;

  -- Evaluate strictly from the already-captured bounded set: exactly one
  -- resolve_alert_candidate call per unit, and no further read of
  -- behavior_pings, so the MATERIALIZED CTE above is the only
  -- sessionization pass in the whole run.
  WITH captured_units AS (
    SELECT
      (elem ->> ''user_id'')::uuid AS user_id,
      (elem ->> ''session_end_utc'')::timestamptz AS session_end,
      (elem ->> ''next_start_utc'')::timestamptz AS next_start
    FROM jsonb_array_elements(_units_captured) AS elem
  ), evaluated AS MATERIALIZED (
    SELECT u.user_id, u.session_end, u.next_start,
      private.resolve_alert_candidate(u.user_id, u.next_start, _version_id) AS result
    FROM captured_units AS u
  ), live_matches AS (
    SELECT e.user_id, e.session_end, e.next_start,
      count(a.id)::integer AS matched_count
    FROM evaluated AS e
    LEFT JOIN public.alerts AS a
      ON a.user_id = e.user_id
     AND a.cause = ''silence''
     AND a.opened_at >= e.session_end
     AND a.opened_at < e.next_start
    GROUP BY e.user_id, e.session_end, e.next_start
  ), per_unit AS (
    SELECT
      e.user_id, e.session_end, e.next_start, e.result,
      m.matched_count,
      (e.result ->> ''replayable'')::boolean AS replayable,
      e.result ->> ''unreplayable_reason'' AS unreplayable_reason,
      (e.result ->> ''would_alert'')::boolean AS would_alert,
      e.result ->> ''candidate_cap_reason'' AS cap_reason,
      e.result ->> ''basis'' AS basis,
      e.result ->> ''quality_state'' AS quality_state,
      (e.result ->> ''candidate_threshold_minutes'')::integer AS candidate_threshold_minutes,
      (e.result ->> ''sensitivity_buffer_minutes'')::integer AS sensitivity_buffer_minutes
    FROM evaluated AS e
    JOIN live_matches AS m
      ON m.user_id = e.user_id
     AND m.session_end = e.session_end
     AND m.next_start = e.next_start
  ), unreplayable_reason_agg AS (
    SELECT coalesce(jsonb_object_agg(unreplayable_reason, cnt), ''{}''::jsonb) AS obj
    FROM (
      SELECT unreplayable_reason, count(*)::integer AS cnt
      FROM per_unit
      WHERE NOT replayable
      GROUP BY unreplayable_reason
    ) AS t
  ), basis_agg AS (
    SELECT coalesce(jsonb_object_agg(basis, cnt), ''{}''::jsonb) AS obj
    FROM (
      SELECT basis, count(*)::integer AS cnt
      FROM per_unit
      WHERE replayable
      GROUP BY basis
    ) AS t
  ), quality_agg AS (
    SELECT coalesce(jsonb_object_agg(quality_state, cnt), ''{}''::jsonb) AS obj
    FROM (
      SELECT quality_state, count(*)::integer AS cnt
      FROM per_unit
      WHERE replayable
      GROUP BY quality_state
    ) AS t
  ), cap_reason_agg AS (
    SELECT coalesce(jsonb_object_agg(cap_reason, cnt), ''{}''::jsonb) AS obj
    FROM (
      SELECT cap_reason, count(*)::integer AS cnt
      FROM per_unit
      WHERE replayable
      GROUP BY cap_reason
    ) AS t
  ), unmatched_agg AS (
    SELECT count(*)::integer AS unmatched_count,
      coalesce(jsonb_agg(
        to_char(a.opened_at AT TIME ZONE ''UTC'', ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'')
        ORDER BY a.opened_at, a.id
      ), ''[]''::jsonb) AS unmatched_json
    FROM public.alerts AS a
    WHERE a.cause = ''silence''
      AND a.opened_at >= _from
      AND a.opened_at < _to
      AND NOT EXISTS (
        SELECT 1
        FROM captured_units AS u
        WHERE u.user_id = a.user_id
          AND a.opened_at >= u.session_end
          AND a.opened_at < u.next_start
      )
  ), units_agg AS (
    SELECT coalesce(jsonb_agg(
      jsonb_build_object(
        ''session_end_utc'', to_char(session_end AT TIME ZONE ''UTC'', ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
        ''next_start_utc'', to_char(next_start AT TIME ZONE ''UTC'', ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
        ''replayable'', replayable,
        ''unreplayable_reason'', unreplayable_reason,
        ''evaluator_provenance_sha256'', result ->> ''provenance_sha256'',
        ''matched_live_count'', matched_count
      )
      ORDER BY
        session_end,
        next_start,
        coalesce(result ->> ''provenance_sha256'', ''''),
        replayable,
        coalesce(unreplayable_reason, ''''),
        matched_count
    ), ''[]''::jsonb) AS units_json
    FROM per_unit
  )
  SELECT
    count(*)::integer,
    count(*) FILTER (WHERE replayable)::integer,
    count(*) FILTER (WHERE NOT replayable)::integer,
    (SELECT obj FROM unreplayable_reason_agg),
    coalesce(sum(matched_count) FILTER (WHERE replayable), 0)::integer,
    (SELECT unmatched_count FROM unmatched_agg),
    count(*) FILTER (WHERE replayable AND would_alert)::integer,
    count(*) FILTER (WHERE replayable)::integer,
    count(*) FILTER (WHERE replayable AND matched_count > 0 AND would_alert)::integer,
    count(*) FILTER (WHERE replayable AND matched_count > 0 AND NOT would_alert)::integer,
    count(*) FILTER (WHERE replayable AND matched_count = 0 AND would_alert)::integer,
    count(*) FILTER (WHERE replayable AND matched_count = 0 AND NOT would_alert)::integer,
    count(*) FILTER (WHERE replayable)::integer,
    (SELECT percentile_cont(0.5) WITHIN GROUP (
      ORDER BY (candidate_threshold_minutes - (90 + sensitivity_buffer_minutes)))
      FROM per_unit WHERE replayable),
    (SELECT percentile_cont(0.95) WITHIN GROUP (
      ORDER BY (candidate_threshold_minutes - (90 + sensitivity_buffer_minutes)))
      FROM per_unit WHERE replayable),
    (SELECT obj FROM basis_agg),
    (SELECT obj FROM quality_agg),
    (SELECT obj FROM cap_reason_agg),
    (SELECT units_json FROM units_agg),
    (SELECT unmatched_json FROM unmatched_agg)
  INTO
    _evaluated_count, _replayable_count, _unreplayable_count, _unreplayable_reason_counts,
    _live_alert_rows_observed, _unmatched_live_silence_alert_rows,
    _candidate_would_alert_gaps, _proxy_denominator,
    _both_proxy, _live_only_proxy, _candidate_only_proxy, _neither_proxy,
    _threshold_delta_denominator, _median_delta, _p95_delta,
    _basis_counts, _quality_counts, _cap_reason_counts,
    _units_json, _unmatched_json
  FROM per_unit;

  IF _evaluated_count = 0 THEN
    _report_status := ''empty'';
  ELSIF _replayable_count = 0 THEN
    _report_status := ''all_unreplayable'';
  ELSIF _unreplayable_count = 0 THEN
    _report_status := ''complete'';
  ELSE
    _report_status := ''partial'';
  END IF;

  -- Canonical input hash: contract versions, model config/evidence hash,
  -- exact range, and an ordered multiset of unit timestamps, Task 6
  -- provenance hashes, and ordered live-proxy timestamps/counts. It excludes
  -- user/alert ids, runtime/transaction timing, created_at, and this row''s
  -- own hash columns; duplicate tokens remain duplicated.
  _input_sha := encode(extensions.digest(jsonb_build_object(
    ''replay_contract_version'', _replay_contract,
    ''evaluator_contract_version'', _evaluator_contract,
    ''model_config_sha256'', _version.config_sha256,
    ''model_evidence_version'', _version.evidence_version,
    ''from_utc'', _from_utc,
    ''to_utc'', _to_utc,
    ''units'', _units_json,
    ''unmatched_live_silence_alert_opened_at_utc'', _unmatched_json
  )::text, ''sha256''), ''hex'');

  _metrics := jsonb_build_object(
    ''version_id'', _version_id,
    ''replay_contract_version'', _replay_contract,
    ''evaluator_version'', _evaluator_contract,
    ''from'', _from_utc,
    ''to'', _to_utc,
    ''report_status'', _report_status,
    ''evaluated_count'', _evaluated_count,
    ''replayable_count'', _replayable_count,
    ''unreplayable_count'', _unreplayable_count,
    ''unreplayable_reason_counts'', _unreplayable_reason_counts,
    ''replayable_completed_gap_count'', _replayable_count,
    ''live_alert_rows_observed'', _live_alert_rows_observed,
    ''unmatched_live_silence_alert_rows'', _unmatched_live_silence_alert_rows,
    ''candidate_would_alert_gaps'', _candidate_would_alert_gaps,
    ''proxy_denominator_replayable_gaps'', _proxy_denominator,
    ''both_proxy'', _both_proxy,
    ''live_only_proxy'', _live_only_proxy,
    ''candidate_only_proxy'', _candidate_only_proxy,
    ''neither_proxy'', _neither_proxy,
    ''threshold_delta_denominator_replayable_gaps'', _threshold_delta_denominator,
    ''median_candidate_minus_adr0022_threshold_proxy_minutes'', _median_delta,
    ''p95_candidate_minus_adr0022_threshold_proxy_minutes'', _p95_delta,
    ''basis_counts'', _basis_counts,
    ''quality_counts'', _quality_counts,
    ''cap_reason_counts'', _cap_reason_counts,
    ''adjudicated_risk_outcomes'', 0,
    ''unadjudicated_replayable_count'', _replayable_count,
    ''safety_claim'', ''not_evaluated'',
    ''promotion_eligible'', false
  );

  _output_sha := encode(extensions.digest(
    (_metrics || jsonb_build_object(''input_sha256'', _input_sha))::text, ''sha256''
  ), ''hex'');

  INSERT INTO public.alert_judgment_evaluations (
    version_id, evaluation_kind, evaluated_from, evaluated_to,
    metrics, input_sha256, output_sha256, evaluator_version, promotion_eligible
  ) VALUES (
    _version_id, ''historical_replay'', _from, _to,
    _metrics, _input_sha, _output_sha, _evaluator_contract, false
  )
  ON CONFLICT (version_id, evaluation_kind, evaluated_from, evaluated_to)
  DO UPDATE SET
    metrics = EXCLUDED.metrics,
    input_sha256 = EXCLUDED.input_sha256,
    output_sha256 = EXCLUDED.output_sha256,
    evaluator_version = EXCLUDED.evaluator_version,
    promotion_eligible = false
  WHERE public.alert_judgment_evaluations.metrics IS DISTINCT FROM EXCLUDED.metrics
     OR public.alert_judgment_evaluations.input_sha256 IS DISTINCT FROM EXCLUDED.input_sha256
     OR public.alert_judgment_evaluations.output_sha256 IS DISTINCT FROM EXCLUDED.output_sha256
     OR public.alert_judgment_evaluations.evaluator_version IS DISTINCT FROM EXCLUDED.evaluator_version;

  RETURN _metrics || jsonb_build_object(
    ''input_sha256'', _input_sha, ''output_sha256'', _output_sha
  );
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.run_alert_judgment_replay(uuid, timestamptz, timestamptz)
FROM PUBLIC, anon, authenticated, service_role;

CREATE INDEX IF NOT EXISTS behavior_pings_ingest2_user_received_idx
  ON public.behavior_pings (user_id, received_at, id)
  WHERE ingest_version = 2;

CREATE INDEX IF NOT EXISTS alerts_silence_user_opened_idx
  ON public.alerts (user_id, opened_at)
  WHERE cause = ''silence'';
"}', 'adaptive_alert_replay', 'codex-release-v0.5.21', NULL, NULL),
	('20260725171000', '{"-- ADR-0023 Task 8: fixture-only, unscheduled adaptive-alert shadow recorder.
-- This migration creates no producer, scheduler, notification, network, or live
-- alert path. The function is callable only by its owner for controlled replay.

ALTER TABLE public.alert_judgment_shadow_decisions
  DROP CONSTRAINT alert_judgment_shadow_decisions_check;

ALTER TABLE public.alert_judgment_shadow_decisions
  ADD COLUMN evidence_cutoff timestamptz NOT NULL,
  ADD COLUMN unclamped_candidate_threshold_minutes integer NOT NULL,
  ADD COLUMN candidate_floor_minutes integer NOT NULL,
  ADD COLUMN candidate_ceiling_minutes integer NOT NULL,
  ADD COLUMN candidate_cap_reason text NOT NULL,
  ADD COLUMN deadline_basis text NOT NULL,
  ADD COLUMN selected_source_sha256 text,
  ADD COLUMN subject_context_sha256 text NOT NULL,
  ADD COLUMN decision_provenance jsonb NOT NULL,
  ADD COLUMN decision_sha256 text NOT NULL,
  ADD CONSTRAINT alert_judgment_shadow_decisions_candidate_threshold_nonnegative
    CHECK (candidate_threshold_minutes >= 0),
  ADD CONSTRAINT alert_judgment_shadow_decisions_candidate_inputs_nonnegative
    CHECK (
      unclamped_candidate_threshold_minutes >= 0
      AND candidate_floor_minutes >= 0
      AND candidate_ceiling_minutes >= 0
      AND candidate_ceiling_minutes >= candidate_floor_minutes
    ),
  ADD CONSTRAINT alert_judgment_shadow_decisions_candidate_cap_contract
    CHECK (
      (
        candidate_cap_reason = ''none''
        AND basis <> ''deterministic_emergency''
        AND candidate_threshold_minutes = unclamped_candidate_threshold_minutes
        AND unclamped_candidate_threshold_minutes >= candidate_floor_minutes
        AND unclamped_candidate_threshold_minutes <= candidate_ceiling_minutes
      )
      OR (
        candidate_cap_reason = ''floor''
        AND basis <> ''deterministic_emergency''
        AND unclamped_candidate_threshold_minutes < candidate_floor_minutes
        AND candidate_threshold_minutes = candidate_floor_minutes
      )
      OR (
        candidate_cap_reason = ''ceiling''
        AND basis <> ''deterministic_emergency''
        AND unclamped_candidate_threshold_minutes > candidate_ceiling_minutes
        AND candidate_threshold_minutes = candidate_ceiling_minutes
      )
      OR (
        candidate_cap_reason = ''emergency_exempt''
        AND basis = ''deterministic_emergency''
        AND candidate_threshold_minutes = unclamped_candidate_threshold_minutes
      )
    ),
  ADD CONSTRAINT alert_judgment_shadow_decisions_deadline_basis_check
    CHECK (deadline_basis IN (''known_interval_inversion'', ''no_future_exclusion'')),
  ADD CONSTRAINT alert_judgment_shadow_decisions_selected_source_sha256_check
    CHECK (
      selected_source_sha256 IS NULL
      OR selected_source_sha256 ~ ''^[a-f0-9]{64}$''
    ),
  ADD CONSTRAINT alert_judgment_shadow_decisions_subject_context_sha256_check
    CHECK (subject_context_sha256 ~ ''^[a-f0-9]{64}$''),
  ADD CONSTRAINT alert_judgment_shadow_decisions_decision_provenance_check
    CHECK (
      jsonb_typeof(decision_provenance) = ''object''
      AND provenance_sha256 = encode(
        extensions.digest(decision_provenance::text, ''sha256''),
        ''hex''
      )
    ),
  ADD CONSTRAINT alert_judgment_shadow_decisions_decision_sha256_check
    CHECK (decision_sha256 ~ ''^[a-f0-9]{64}$'');

CREATE FUNCTION private.record_alert_judgment_shadow(
  _version_id uuid,
  _evaluated_at timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET TimeZone = ''UTC''
SET \"DateStyle\" = ''ISO, YMD''
SET extra_float_digits = 3
AS $$
DECLARE
  _recorder_version constant text := ''adaptive_shadow_recorder_v1'';
  _evaluator_version constant text := ''adaptive_candidate_v1'';
  _supported_evidence_version constant text := ''canonical-v2'';
  _required_keys constant text[] := ARRAY[
    ''basis'',
    ''candidate_cap_reason'',
    ''candidate_ceiling_minutes'',
    ''candidate_deadline'',
    ''candidate_floor_minutes'',
    ''candidate_threshold_minutes'',
    ''confidence'',
    ''context_key'',
    ''deadline_basis'',
    ''decision_provenance'',
    ''effective_silence_minutes'',
    ''evaluated_at'',
    ''evaluator_version'',
    ''evidence_cutoff'',
    ''fallback_path'',
    ''guardian_used_as_activity'',
    ''neutral_threshold_minutes'',
    ''provenance_sha256'',
    ''quality_state'',
    ''replayable'',
    ''selected_source_sha256'',
    ''sensitivity_buffer_minutes'',
    ''sleep_interval_provenance'',
    ''subject_context_sha256'',
    ''unclamped_candidate_threshold_minutes'',
    ''unreplayable_reason'',
    ''version_id'',
    ''would_alert''
  ];
  _run_level_reasons constant text[] := ARRAY[
    ''invalid_version_status'',
    ''config_hash_mismatch'',
    ''unsupported_evidence_version''
  ];
  _per_user_reasons constant text[] := ARRAY[
    ''missing_subject_context'',
    ''ambiguous_subject_context'',
    ''subject_context_provenance_invalid'',
    ''missing_qualified_session''
  ];
  _version public.alert_model_versions%ROWTYPE;
  _population_user_id uuid;
  _evaluated_minute timestamptz;
  _evaluated_minute_utc text;
  _result jsonb;
  _result_key_count integer;
  _replayable boolean;
  _reason text;
  _decision_provenance jsonb;
  _provenance_sha text;
  _decision_sha text;
  _existing_decision_sha text;
  _fallback_path text[];
  _population_count integer := 0;
  _evaluated_count integer := 0;
  _replayable_count integer := 0;
  _inserted_count integer := 0;
  _duplicate_count integer := 0;
  _unreplayable_count integer := 0;
  _unreplayable_reason_counts jsonb := ''{}''::jsonb;
  _result_status text;
BEGIN
  IF _version_id IS NULL THEN
    RAISE EXCEPTION ''shadow recorder requires a non-null version id'';
  END IF;
  IF _evaluated_at IS NULL OR NOT isfinite(_evaluated_at) THEN
    RAISE EXCEPTION ''shadow recorder requires a finite evaluation timestamp'';
  END IF;

  _evaluated_minute :=
    date_trunc(''minute'', _evaluated_at AT TIME ZONE ''UTC'') AT TIME ZONE ''UTC'';
  _evaluated_minute_utc := to_char(
    _evaluated_minute AT TIME ZONE ''UTC'',
    ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''
  );

  SELECT version.*
    INTO _version
  FROM public.alert_model_versions AS version
  WHERE version.id = _version_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION ''shadow recorder version does not exist'';
  END IF;
  IF _version.status <> ''shadow'' THEN
    RAISE EXCEPTION ''shadow recorder requires status=shadow'';
  END IF;
  IF _version.shadow_enabled_at IS NULL
     OR _evaluated_minute < _version.shadow_enabled_at THEN
    RAISE EXCEPTION ''shadow recorder evaluation precedes shadow enablement'';
  END IF;
  IF _version.config_sha256
      <> encode(extensions.digest(_version.config::text, ''sha256''), ''hex'') THEN
    RAISE EXCEPTION ''shadow recorder config hash mismatch'';
  END IF;
  IF _version.evidence_version <> _supported_evidence_version THEN
    RAISE EXCEPTION ''shadow recorder evidence version is unsupported'';
  END IF;
  IF _version.config #>> ''{evaluator,contract_version}''
      <> _evaluator_version THEN
    RAISE EXCEPTION ''shadow recorder evaluator contract is unsupported'';
  END IF;

  FOR _population_user_id IN
    SELECT DISTINCT ds.user_id
    FROM public.device_state AS ds
    WHERE EXISTS (
      SELECT 1
      FROM public.group_members AS gm
      WHERE gm.user_id = ds.user_id
        AND gm.status = ''active''
        AND gm.monitored
    )
    ORDER BY ds.user_id
  LOOP
    _population_count := _population_count + 1;
    _result := private.resolve_alert_candidate(
      _population_user_id,
      _evaluated_minute,
      _version_id
    );
    _evaluated_count := _evaluated_count + 1;

    IF _result IS NULL OR jsonb_typeof(_result) <> ''object'' THEN
      RAISE EXCEPTION ''candidate evaluator returned a non-object result'';
    END IF;
    SELECT count(*)::integer
      INTO _result_key_count
    FROM jsonb_object_keys(_result);
    IF NOT (_result ?& _required_keys)
       OR _result_key_count <> cardinality(_required_keys) THEN
      RAISE EXCEPTION ''candidate evaluator returned a malformed key contract'';
    END IF;
    IF jsonb_typeof(_result -> ''replayable'') <> ''boolean''
       OR _result ->> ''evaluator_version'' <> _evaluator_version
       OR _result ->> ''version_id'' <> _version_id::text
       OR _result ->> ''evaluated_at'' <> _evaluated_minute_utc
       OR _result ->> ''evidence_cutoff'' <> _evaluated_minute_utc
       OR jsonb_typeof(_result -> ''decision_provenance'') <> ''object''
       OR jsonb_typeof(_result -> ''provenance_sha256'') <> ''string''
       OR jsonb_typeof(_result -> ''guardian_used_as_activity'') <> ''boolean''
       OR (_result ->> ''guardian_used_as_activity'')::boolean THEN
      RAISE EXCEPTION ''candidate evaluator returned malformed identity fields'';
    END IF;
    _decision_provenance := _result -> ''decision_provenance'';
    _provenance_sha := encode(
      extensions.digest(_decision_provenance::text, ''sha256''),
      ''hex''
    );
    IF _result ->> ''provenance_sha256'' <> _provenance_sha THEN
      RAISE EXCEPTION ''candidate evaluator provenance hash mismatch'';
    END IF;

    _replayable := (_result ->> ''replayable'')::boolean;
    _reason := _result ->> ''unreplayable_reason'';

    IF _reason = ANY (_run_level_reasons) THEN
      RAISE EXCEPTION ''candidate evaluator returned run-level reason: %'', _reason;
    END IF;

    IF NOT _replayable THEN
      IF _reason IS NULL OR NOT (_reason = ANY (_per_user_reasons)) THEN
        RAISE EXCEPTION ''candidate evaluator returned an invalid per-user reason'';
      END IF;
      IF _result ->> ''basis'' IS NOT NULL
         OR _result ->> ''context_key'' IS NOT NULL
         OR _result ->> ''neutral_threshold_minutes'' IS NOT NULL
         OR _result ->> ''sensitivity_buffer_minutes'' IS NOT NULL
         OR _result ->> ''unclamped_candidate_threshold_minutes'' IS NOT NULL
         OR _result ->> ''candidate_floor_minutes'' IS NOT NULL
         OR _result ->> ''candidate_ceiling_minutes'' IS NOT NULL
         OR _result ->> ''candidate_cap_reason'' IS NOT NULL
         OR _result ->> ''candidate_threshold_minutes'' IS NOT NULL
         OR _result ->> ''effective_silence_minutes'' IS NOT NULL
         OR _result ->> ''candidate_deadline'' IS NOT NULL
         OR _result ->> ''deadline_basis'' IS NOT NULL
         OR _result ->> ''would_alert'' IS NOT NULL
         OR _result ->> ''confidence'' IS NOT NULL
         OR _result ->> ''selected_source_sha256'' IS NOT NULL
         OR _result ->> ''subject_context_sha256'' IS NOT NULL
         OR _result ->> ''quality_state'' <> ''coverage_invalid''
         OR _result -> ''fallback_path'' <> ''[]''::jsonb
         OR _result -> ''sleep_interval_provenance'' <> ''[]''::jsonb THEN
        RAISE EXCEPTION ''candidate evaluator returned malformed unreplayable fields'';
      END IF;
      _unreplayable_count := _unreplayable_count + 1;
      _unreplayable_reason_counts := jsonb_set(
        _unreplayable_reason_counts,
        ARRAY[_reason],
        to_jsonb(coalesce(
          (_unreplayable_reason_counts ->> _reason)::integer,
          0
        ) + 1),
        true
      );
      CONTINUE;
    END IF;

    IF _reason IS NOT NULL
       OR jsonb_typeof(_result -> ''basis'') <> ''string''
       OR jsonb_typeof(_result -> ''context_key'') <> ''string''
       OR jsonb_typeof(_result -> ''neutral_threshold_minutes'') <> ''number''
       OR jsonb_typeof(_result -> ''sensitivity_buffer_minutes'') <> ''number''
       OR jsonb_typeof(_result -> ''unclamped_candidate_threshold_minutes'') <> ''number''
       OR jsonb_typeof(_result -> ''candidate_floor_minutes'') <> ''number''
       OR jsonb_typeof(_result -> ''candidate_ceiling_minutes'') <> ''number''
       OR jsonb_typeof(_result -> ''candidate_cap_reason'') <> ''string''
       OR jsonb_typeof(_result -> ''candidate_threshold_minutes'') <> ''number''
       OR jsonb_typeof(_result -> ''effective_silence_minutes'') <> ''number''
       OR jsonb_typeof(_result -> ''candidate_deadline'') <> ''string''
       OR jsonb_typeof(_result -> ''deadline_basis'') <> ''string''
       OR jsonb_typeof(_result -> ''would_alert'') <> ''boolean''
       OR jsonb_typeof(_result -> ''confidence'') <> ''number''
       OR jsonb_typeof(_result -> ''quality_state'') <> ''string''
       OR jsonb_typeof(_result -> ''fallback_path'') <> ''array''
       OR jsonb_array_length(_result -> ''fallback_path'') < 1
       OR jsonb_typeof(_result -> ''sleep_interval_provenance'') <> ''array''
       OR (
         _result -> ''selected_source_sha256'' <> ''null''::jsonb
         AND jsonb_typeof(_result -> ''selected_source_sha256'') <> ''string''
       )
       OR jsonb_typeof(_result -> ''subject_context_sha256'') <> ''string''
       OR jsonb_typeof(_result -> ''decision_provenance'') <> ''object''
       OR jsonb_typeof(_result -> ''provenance_sha256'') <> ''string'' THEN
      RAISE EXCEPTION ''candidate evaluator returned malformed replayable fields'';
    END IF;

    _decision_sha := encode(
      extensions.digest(jsonb_build_object(
        ''version_id'', _version_id,
        ''user_id'', _population_user_id,
        ''evaluated_minute'', _evaluated_minute_utc,
        ''evaluator_result'', _result
      )::text, ''sha256''),
      ''hex''
    );
    SELECT array_agg(value ORDER BY ordinal)
      INTO _fallback_path
    FROM jsonb_array_elements_text(_result -> ''fallback_path'')
      WITH ORDINALITY AS path(value, ordinal);

    INSERT INTO public.alert_judgment_shadow_decisions (
      version_id,
      user_id,
      evaluated_at,
      basis,
      evaluator_version,
      context_key,
      neutral_threshold_minutes,
      sensitivity_buffer_minutes,
      candidate_threshold_minutes,
      effective_silence_minutes,
      candidate_deadline,
      would_alert,
      confidence,
      quality_state,
      fallback_path,
      sleep_interval_provenance,
      provenance_sha256,
      guardian_used_as_activity,
      evidence_cutoff,
      unclamped_candidate_threshold_minutes,
      candidate_floor_minutes,
      candidate_ceiling_minutes,
      candidate_cap_reason,
      deadline_basis,
      selected_source_sha256,
      subject_context_sha256,
      decision_provenance,
      decision_sha256
    ) VALUES (
      _version_id,
      _population_user_id,
      _evaluated_minute,
      _result ->> ''basis'',
      _evaluator_version,
      _result ->> ''context_key'',
      (_result ->> ''neutral_threshold_minutes'')::integer,
      (_result ->> ''sensitivity_buffer_minutes'')::integer,
      (_result ->> ''candidate_threshold_minutes'')::integer,
      (_result ->> ''effective_silence_minutes'')::double precision,
      (_result ->> ''candidate_deadline'')::timestamptz,
      (_result ->> ''would_alert'')::boolean,
      (_result ->> ''confidence'')::double precision,
      _result ->> ''quality_state'',
      _fallback_path,
      _result -> ''sleep_interval_provenance'',
      _provenance_sha,
      false,
      (_result ->> ''evidence_cutoff'')::timestamptz,
      (_result ->> ''unclamped_candidate_threshold_minutes'')::integer,
      (_result ->> ''candidate_floor_minutes'')::integer,
      (_result ->> ''candidate_ceiling_minutes'')::integer,
      _result ->> ''candidate_cap_reason'',
      _result ->> ''deadline_basis'',
      _result ->> ''selected_source_sha256'',
      _result ->> ''subject_context_sha256'',
      _decision_provenance,
      _decision_sha
    )
    ON CONFLICT (version_id, user_id, evaluated_minute) DO NOTHING;

    IF FOUND THEN
      _inserted_count := _inserted_count + 1;
    ELSE
      SELECT decision.decision_sha256
        INTO _existing_decision_sha
      FROM public.alert_judgment_shadow_decisions AS decision
      WHERE decision.version_id = _version_id
        AND decision.user_id = _population_user_id
        AND decision.evaluated_minute = _evaluated_minute;
      IF _existing_decision_sha IS DISTINCT FROM _decision_sha THEN
        RAISE EXCEPTION ''same-minute shadow decision mismatch'';
      END IF;
      _duplicate_count := _duplicate_count + 1;
    END IF;
    _replayable_count := _replayable_count + 1;
  END LOOP;

  _result_status := CASE
    WHEN _population_count = 0 THEN ''empty''
    WHEN _replayable_count = 0 THEN ''all_unreplayable''
    WHEN _unreplayable_count > 0 THEN ''partial''
    ELSE ''complete''
  END;

  RETURN jsonb_build_object(
    ''recorder_contract_version'', _recorder_version,
    ''evaluator_version'', _evaluator_version,
    ''execution_scope'', ''fixture_only_unscheduled'',
    ''operational_shadow'', false,
    ''result_status'', _result_status,
    ''population_count'', _population_count,
    ''evaluated_count'', _evaluated_count,
    ''replayable_count'', _replayable_count,
    ''inserted_count'', _inserted_count,
    ''duplicate_count'', _duplicate_count,
    ''unreplayable_count'', _unreplayable_count,
    ''unreplayable_reason_counts'', _unreplayable_reason_counts,
    ''skipped_count'', _duplicate_count + _unreplayable_count,
    ''error_count'', 0
  );
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.record_alert_judgment_shadow(uuid, timestamptz)
FROM PUBLIC, anon, authenticated, service_role;

ALTER TABLE public.alert_judgment_shadow_decisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.alert_judgment_shadow_decisions
FROM PUBLIC, anon, authenticated, service_role;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policy AS policy
    WHERE policy.polrelid =
      ''public.alert_judgment_shadow_decisions''::regclass
  ) THEN
    RAISE EXCEPTION ''shadow decision table unexpectedly has an RLS policy'';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger
    WHERE trigger.tgrelid =
      ''public.alert_judgment_shadow_decisions''::regclass
      AND NOT trigger.tgisinternal
  ) THEN
    RAISE EXCEPTION ''shadow decision table unexpectedly has a producer trigger'';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_publication_tables AS publication
    WHERE publication.pubname = ''supabase_realtime''
      AND publication.schemaname = ''public''
      AND publication.tablename = ''alert_judgment_shadow_decisions''
  ) THEN
    RAISE EXCEPTION ''shadow decision table unexpectedly has realtime publication'';
  END IF;
  IF (
    SELECT recorder.proowner <> evaluator.proowner
        OR recorder.proowner <> target.relowner
    FROM pg_catalog.pg_proc AS recorder
    CROSS JOIN pg_catalog.pg_proc AS evaluator
    CROSS JOIN pg_catalog.pg_class AS target
    WHERE recorder.oid =
      ''private.record_alert_judgment_shadow(uuid,timestamptz)''::regprocedure
      AND evaluator.oid =
      ''private.resolve_alert_candidate(uuid,timestamptz,uuid)''::regprocedure
      AND target.oid =
      ''public.alert_judgment_shadow_decisions''::regclass
  ) THEN
    RAISE EXCEPTION ''shadow recorder owner does not match evaluator and target'';
  END IF;
END;
$$;
"}', 'adaptive_alert_shadow_recorder', 'codex-release-v0.5.21', NULL, NULL),
	('20260727173000', '{"-- ADR-0028: default-disabled, source-identified production-shadow coverage leases.
-- This migration creates no scheduler, trigger, notification, or live-alert write.

CREATE TABLE private.adaptive_alert_shadow_runtime_config (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  version_id uuid NULL REFERENCES public.alert_model_versions(id) ON DELETE RESTRICT,
  enabled boolean NOT NULL DEFAULT false,
  accept_coverage_leases boolean NOT NULL DEFAULT false,
  max_population integer NOT NULL DEFAULT 10000
    CHECK (max_population BETWEEN 1 AND 10000),
  detail_retention_days integer NOT NULL DEFAULT 35
    CHECK (detail_retention_days = 35),
  cycle_timeout_seconds integer NOT NULL DEFAULT 120
    CHECK (cycle_timeout_seconds = 120),
  max_consecutive_failures integer NOT NULL DEFAULT 3
    CHECK (max_consecutive_failures = 3),
  consecutive_failures integer NOT NULL DEFAULT 0
    CHECK (consecutive_failures BETWEEN 0 AND 3),
  last_failure_code text NULL,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

INSERT INTO private.adaptive_alert_shadow_runtime_config(singleton)
VALUES (true);

CREATE TABLE private.alert_shadow_coverage_leases (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  event_id uuid NOT NULL,
  client_id text NOT NULL CHECK (length(trim(client_id)) BETWEEN 1 AND 64),
  channel text NOT NULL CHECK (channel IN (''tauri'', ''android-apk'')),
  collector_contract text NOT NULL
    CHECK (collector_contract IN (''tauri-idle-v1'', ''android-passive-v1'')),
  collector_state text NOT NULL CHECK (collector_state = ''operational''),
  capability_sha256 text NOT NULL CHECK (capability_sha256 ~ ''^[a-f0-9]{64}$''),
  observed_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  app_version text NOT NULL CHECK (length(trim(app_version)) BETWEEN 1 AND 32),
  timezone text NOT NULL CHECK (length(trim(timezone)) > 0),
  utc_offset_minutes integer NOT NULL CHECK (utc_offset_minutes BETWEEN -840 AND 840),
  PRIMARY KEY (user_id, event_id),
  CHECK (
    (channel = ''tauri'' AND collector_contract = ''tauri-idle-v1'')
    OR
    (channel = ''android-apk'' AND collector_contract = ''android-passive-v1'')
  )
);

CREATE INDEX alert_shadow_coverage_leases_user_received_idx
  ON private.alert_shadow_coverage_leases (user_id, received_at, event_id);

ALTER TABLE private.adaptive_alert_shadow_runtime_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.alert_shadow_coverage_leases ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON TABLE
  private.adaptive_alert_shadow_runtime_config,
  private.alert_shadow_coverage_leases
FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.record_alert_shadow_coverage_lease_core(
  _user_id uuid,
  _client_id text,
  _channel text,
  _collector_contract text,
  _collector_state text,
  _capability_sha256 text,
  _observed_at timestamptz,
  _event_id uuid
)
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET timezone = ''UTC''
AS $$
DECLARE
  _received_at timestamptz := clock_timestamp();
  _platform text;
  _app_version text;
  _timezone text;
  _utc_offset_minutes integer;
  _enabled boolean;
  _accept boolean;
  _inserted integer;
BEGIN
  SELECT enabled, accept_coverage_leases
  INTO _enabled, _accept
  FROM private.adaptive_alert_shadow_runtime_config
  WHERE singleton;

  IF coalesce(_enabled, false) IS NOT TRUE
     OR coalesce(_accept, false) IS NOT TRUE THEN
    RETURN ''disabled'';
  END IF;

  IF _user_id IS NULL THEN RETURN ''invalid''; END IF;
  IF _event_id IS NULL THEN RETURN ''invalid''; END IF;
  IF _client_id IS NULL OR length(trim(_client_id)) NOT BETWEEN 1 AND 64 THEN
    RETURN ''invalid'';
  END IF;
  IF _channel NOT IN (''tauri'', ''android-apk'') THEN RETURN ''unsupported''; END IF;
  IF (
    _channel = ''tauri'' AND _collector_contract <> ''tauri-idle-v1''
  ) OR (
    _channel = ''android-apk'' AND _collector_contract <> ''android-passive-v1''
  ) THEN
    RETURN ''unsupported'';
  END IF;
  IF _collector_state IS DISTINCT FROM ''operational'' THEN
    RETURN ''unsupported'';
  END IF;
  IF _capability_sha256 IS NULL
     OR _capability_sha256 !~ ''^[a-f0-9]{64}$'' THEN
    RETURN ''invalid'';
  END IF;
  IF _observed_at IS NULL
     OR abs(extract(epoch FROM (_received_at - _observed_at))) > 300 THEN
    RETURN ''invalid'';
  END IF;

  SELECT c.platform, c.app_version
  INTO _platform, _app_version
  FROM public.clients AS c
  WHERE c.user_id = _user_id
    AND c.client_id = _client_id;

  IF NOT FOUND THEN RETURN ''unregistered_client''; END IF;
  IF (
    _channel = ''tauri'' AND _platform IS DISTINCT FROM ''tauri''
  ) OR (
    _channel = ''android-apk'' AND _platform IS DISTINCT FROM ''android''
  ) THEN
    RETURN ''capability_mismatch'';
  END IF;
  IF _app_version IS NULL OR length(trim(_app_version)) NOT BETWEEN 1 AND 32 THEN
    RETURN ''capability_mismatch'';
  END IF;

  SELECT coalesce(s.timezone, ''UTC'')
  INTO _timezone
  FROM public.user_settings AS s
  WHERE s.user_id = _user_id;
  _timezone := coalesce(_timezone, ''UTC'');

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_timezone_names
    WHERE name = _timezone
  ) THEN
    RETURN ''invalid'';
  END IF;

  _utc_offset_minutes := round(
    extract(epoch FROM (
      (_received_at AT TIME ZONE _timezone)
      - (_received_at AT TIME ZONE ''UTC'')
    )) / 60
  )::integer;

  INSERT INTO private.alert_shadow_coverage_leases (
    user_id, event_id, client_id, channel, collector_contract, collector_state,
    capability_sha256, observed_at, received_at, app_version, timezone,
    utc_offset_minutes
  ) VALUES (
    _user_id, _event_id, trim(_client_id), _channel, _collector_contract,
    _collector_state, _capability_sha256, _observed_at, _received_at,
    _app_version, _timezone, _utc_offset_minutes
  )
  ON CONFLICT (user_id, event_id) DO NOTHING;

  GET DIAGNOSTICS _inserted = ROW_COUNT;
  IF _inserted = 1 THEN
    RETURN ''inserted'';
  END IF;
  RETURN ''duplicate'';
END;
$$;

CREATE FUNCTION public.record_alert_shadow_coverage_lease(
  _client_id text,
  _channel text,
  _collector_contract text,
  _collector_state text,
  _capability_sha256 text,
  _observed_at timestamptz,
  _event_id uuid
)
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET timezone = ''UTC''
AS $$
BEGIN
  RETURN private.record_alert_shadow_coverage_lease_core(
    auth.uid(),
    _client_id,
    _channel,
    _collector_contract,
    _collector_state,
    _capability_sha256,
    _observed_at,
    _event_id
  );
END;
$$;

CREATE FUNCTION public.record_alert_shadow_coverage_lease_for_user(
  _user_id uuid,
  _client_id text,
  _channel text,
  _collector_contract text,
  _collector_state text,
  _capability_sha256 text,
  _observed_at timestamptz,
  _event_id uuid
)
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET timezone = ''UTC''
AS $$
BEGIN
  RETURN private.record_alert_shadow_coverage_lease_core(
    _user_id,
    _client_id,
    _channel,
    _collector_contract,
    _collector_state,
    _capability_sha256,
    _observed_at,
    _event_id
  );
END;
$$;

CREATE FUNCTION private.finalize_alert_shadow_coverage(
  _user_id uuid,
  _through_at timestamptz,
  _retention_days integer
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET timezone = ''UTC''
AS $$
DECLARE
  _version_id uuid;
  _enabled boolean;
  _accept boolean;
  _configured_retention integer;
  _inserted integer := 0;
  _deleted_leases integer := 0;
  _deleted_intervals integer := 0;
BEGIN
  IF _user_id IS NULL OR _through_at IS NULL THEN
    RAISE EXCEPTION ''coverage finalizer requires user and through_at'';
  END IF;

  SELECT c.version_id, c.enabled, c.accept_coverage_leases, c.detail_retention_days
  INTO _version_id, _enabled, _accept, _configured_retention
  FROM private.adaptive_alert_shadow_runtime_config AS c
  WHERE c.singleton;

  IF _enabled IS NOT TRUE OR _accept IS NOT TRUE THEN
    RETURN jsonb_build_object(''status'', ''disabled'', ''inserted'', 0);
  END IF;
  IF _retention_days IS DISTINCT FROM _configured_retention
     OR _retention_days <> 35 THEN
    RAISE EXCEPTION ''coverage retention must equal configured 35 days'';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM public.alert_model_versions AS v
    WHERE v.id = _version_id
      AND v.status = ''shadow''
      AND v.shadow_enabled_at IS NOT NULL
      AND v.shadow_enabled_at <= _through_at
  ) THEN
    RAISE EXCEPTION ''coverage runtime version is not an enabled shadow version'';
  END IF;

  DELETE FROM private.alert_shadow_coverage_leases
  WHERE user_id = _user_id
    AND received_at < _through_at - make_interval(days => _retention_days);
  GET DIAGNOSTICS _deleted_leases = ROW_COUNT;

  DELETE FROM public.alert_observation_coverage_intervals
  WHERE user_id = _user_id
    AND ends_at < _through_at - make_interval(days => _retention_days);
  GET DIAGNOSTICS _deleted_intervals = ROW_COUNT;

  WITH ordered AS (
    SELECT
      l.*,
      lag(l.received_at) OVER (
        PARTITION BY
          l.user_id, l.client_id, l.channel, l.collector_contract,
          l.collector_state, l.capability_sha256, l.app_version,
          l.timezone, l.utc_offset_minutes
        ORDER BY l.received_at, l.event_id
      ) AS previous_received_at
    FROM private.alert_shadow_coverage_leases AS l
    WHERE l.user_id = _user_id
      AND l.received_at <= _through_at
  ), intervals AS (
    SELECT
      o.*,
      extract(epoch FROM (o.received_at - o.previous_received_at)) / 60.0
        AS gap_minutes,
      CASE
        WHEN o.channel = ''tauri'' THEN 12
        WHEN o.channel = ''android-apk'' THEN 35
      END AS allowed_gap_minutes
    FROM ordered AS o
    WHERE o.previous_received_at IS NOT NULL
      AND o.received_at > o.previous_received_at
  ), prepared AS (
    SELECT
      _version_id AS version_id,
      i.user_id,
      i.previous_received_at AS starts_at,
      i.received_at AS ends_at,
      i.timezone,
      i.utc_offset_minutes,
      CASE WHEN i.gap_minutes <= i.allowed_gap_minutes
        THEN ''valid'' ELSE ''unknown'' END AS coverage_state,
      i.received_at AS captured_at,
      _through_at AS finalized_at,
      encode(
        extensions.digest(
          jsonb_build_object(
            ''version_id'', _version_id,
            ''user_id'', i.user_id,
            ''client_id'', i.client_id,
            ''channel'', i.channel,
            ''collector_contract'', i.collector_contract,
            ''collector_state'', i.collector_state,
            ''starts_at_utc'', to_char(
              i.previous_received_at AT TIME ZONE ''UTC'',
              ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''
            ),
            ''ends_at_utc'', to_char(
              i.received_at AT TIME ZONE ''UTC'',
              ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''
            ),
            ''capability_sha256'', i.capability_sha256,
            ''app_version'', i.app_version,
            ''timezone'', i.timezone,
            ''utc_offset_minutes'', i.utc_offset_minutes,
            ''coverage_state'', CASE
              WHEN i.gap_minutes <= i.allowed_gap_minutes
                THEN ''valid'' ELSE ''unknown''
            END,
            ''evidence_version'', ''coverage-lease-v1''
          )::text,
          ''sha256''
        ),
        ''hex''
      ) AS provenance_sha256
    FROM intervals AS i
  )
  INSERT INTO public.alert_observation_coverage_intervals (
    version_id, user_id, starts_at, ends_at, timezone, utc_offset_minutes,
    activity_coverage_state, intervention_coverage_state, sleep_context_state,
    captured_at, finalized_at, evidence_version, provenance_sha256
  )
  SELECT
    p.version_id, p.user_id, p.starts_at, p.ends_at, p.timezone,
    p.utc_offset_minutes, p.coverage_state,
    CASE WHEN p.coverage_state = ''valid'' THEN ''valid'' ELSE ''unknown'' END,
    CASE WHEN p.coverage_state = ''valid'' THEN ''valid'' ELSE ''unknown'' END,
    p.captured_at, p.finalized_at, ''coverage-lease-v1'', p.provenance_sha256
  FROM prepared AS p
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.alert_observation_coverage_intervals AS existing
    WHERE existing.version_id = p.version_id
      AND existing.user_id = p.user_id
      AND existing.starts_at = p.starts_at
      AND existing.ends_at = p.ends_at
      AND existing.provenance_sha256 = p.provenance_sha256
  );
  GET DIAGNOSTICS _inserted = ROW_COUNT;

  RETURN jsonb_build_object(
    ''status'', ''completed'',
    ''inserted'', _inserted,
    ''deleted_leases'', _deleted_leases,
    ''deleted_intervals'', _deleted_intervals,
    ''through_at'', _through_at,
    ''retention_days'', _retention_days
  );
END;
$$;

REVOKE ALL ON FUNCTION
  private.record_alert_shadow_coverage_lease_core(
    uuid,text,text,text,text,text,timestamptz,uuid
  ),
  public.record_alert_shadow_coverage_lease(
    text,text,text,text,text,timestamptz,uuid
  ),
  public.record_alert_shadow_coverage_lease_for_user(
    uuid,text,text,text,text,text,timestamptz,uuid
  ),
  private.finalize_alert_shadow_coverage(uuid,timestamptz,integer)
FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.record_alert_shadow_coverage_lease(
  text,text,text,text,text,timestamptz,uuid
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.record_alert_shadow_coverage_lease_for_user(
  uuid,text,text,text,text,text,timestamptz,uuid
) TO service_role;
"}', 'adaptive_alert_shadow_coverage_contract', 'codex-release-v0.5.21', NULL, NULL),
	('20260727173500', '{"-- ADR-0028 compatibility repair: clients.platform uses the canonical
-- base-kind channel emitted by clientChannel(), namely android-apk.
-- Append-only function replacement; no scheduler, notification, activity, or live-alert write.

CREATE OR REPLACE FUNCTION private.record_alert_shadow_coverage_lease_core(
  _user_id uuid,
  _client_id text,
  _channel text,
  _collector_contract text,
  _collector_state text,
  _capability_sha256 text,
  _observed_at timestamptz,
  _event_id uuid
)
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET timezone = ''UTC''
AS $$
DECLARE
  _received_at timestamptz := clock_timestamp();
  _platform text;
  _app_version text;
  _timezone text;
  _utc_offset_minutes integer;
  _enabled boolean;
  _accept boolean;
  _inserted integer;
BEGIN
  SELECT enabled, accept_coverage_leases
  INTO _enabled, _accept
  FROM private.adaptive_alert_shadow_runtime_config
  WHERE singleton;

  IF coalesce(_enabled, false) IS NOT TRUE
     OR coalesce(_accept, false) IS NOT TRUE THEN
    RETURN ''disabled'';
  END IF;

  IF _user_id IS NULL THEN RETURN ''invalid''; END IF;
  IF _event_id IS NULL THEN RETURN ''invalid''; END IF;
  IF _client_id IS NULL OR length(trim(_client_id)) NOT BETWEEN 1 AND 64 THEN
    RETURN ''invalid'';
  END IF;
  IF _channel NOT IN (''tauri'', ''android-apk'') THEN RETURN ''unsupported''; END IF;
  IF (
    _channel = ''tauri'' AND _collector_contract <> ''tauri-idle-v1''
  ) OR (
    _channel = ''android-apk'' AND _collector_contract <> ''android-passive-v1''
  ) THEN
    RETURN ''unsupported'';
  END IF;
  IF _collector_state IS DISTINCT FROM ''operational'' THEN
    RETURN ''unsupported'';
  END IF;
  IF _capability_sha256 IS NULL
     OR _capability_sha256 !~ ''^[a-f0-9]{64}$'' THEN
    RETURN ''invalid'';
  END IF;
  IF _observed_at IS NULL
     OR abs(extract(epoch FROM (_received_at - _observed_at))) > 300 THEN
    RETURN ''invalid'';
  END IF;

  SELECT c.platform, c.app_version
  INTO _platform, _app_version
  FROM public.clients AS c
  WHERE c.user_id = _user_id
    AND c.client_id = _client_id;

  IF NOT FOUND THEN RETURN ''unregistered_client''; END IF;
  IF (
    _channel = ''tauri'' AND _platform IS DISTINCT FROM ''tauri''
  ) OR (
    _channel = ''android-apk'' AND _platform IS DISTINCT FROM ''android-apk''
  ) THEN
    RETURN ''capability_mismatch'';
  END IF;
  IF _app_version IS NULL OR length(trim(_app_version)) NOT BETWEEN 1 AND 32 THEN
    RETURN ''capability_mismatch'';
  END IF;

  SELECT coalesce(s.timezone, ''UTC'')
  INTO _timezone
  FROM public.user_settings AS s
  WHERE s.user_id = _user_id;
  _timezone := coalesce(_timezone, ''UTC'');

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_timezone_names
    WHERE name = _timezone
  ) THEN
    RETURN ''invalid'';
  END IF;

  _utc_offset_minutes := round(
    extract(epoch FROM (
      (_received_at AT TIME ZONE _timezone)
      - (_received_at AT TIME ZONE ''UTC'')
    )) / 60
  )::integer;

  INSERT INTO private.alert_shadow_coverage_leases (
    user_id, event_id, client_id, channel, collector_contract, collector_state,
    capability_sha256, observed_at, received_at, app_version, timezone,
    utc_offset_minutes
  ) VALUES (
    _user_id, _event_id, trim(_client_id), _channel, _collector_contract,
    _collector_state, _capability_sha256, _observed_at, _received_at,
    _app_version, _timezone, _utc_offset_minutes
  )
  ON CONFLICT (user_id, event_id) DO NOTHING;

  GET DIAGNOSTICS _inserted = ROW_COUNT;
  IF _inserted = 1 THEN
    RETURN ''inserted'';
  END IF;
  RETURN ''duplicate'';
END;
$$;
"}', 'align_android_coverage_client_platform', 'codex-release-v0.5.21', NULL, NULL),
	('20260727174000', '{"-- ADR-0028: bounded operational evidence for a default-disabled shadow.
-- These objects are owner-only, scheduler-free, and have no live alert authority.

CREATE TABLE private.adaptive_alert_shadow_user_state (
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  evaluated_at timestamptz NOT NULL,
  replayable boolean NOT NULL,
  would_alert boolean,
  basis text,
  candidate_threshold_minutes integer,
  quality_state text NOT NULL,
  unreplayable_reason text,
  decision_sha256 text NOT NULL CHECK (decision_sha256 ~ ''^[a-f0-9]{64}$''),
  last_persisted_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (version_id, user_id),
  CHECK (replayable OR would_alert IS NULL)
);

CREATE TABLE private.adaptive_alert_shadow_cycle_runs (
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE CASCADE,
  evaluated_minute timestamptz NOT NULL,
  status text NOT NULL CHECK (status IN (''completed'', ''empty'')),
  duration_ms integer NOT NULL CHECK (duration_ms >= 0),
  population_count integer NOT NULL CHECK (population_count >= 0),
  evaluated_count integer NOT NULL CHECK (evaluated_count >= 0),
  metrics jsonb NOT NULL CHECK (jsonb_typeof(metrics) = ''object''),
  run_sha256 text NOT NULL CHECK (run_sha256 ~ ''^[a-f0-9]{64}$''),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (version_id, evaluated_minute)
);

CREATE TABLE private.adaptive_alert_shadow_daily_reports (
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE CASCADE,
  report_date date NOT NULL,
  segment_key text NOT NULL,
  contributor_count integer NOT NULL CHECK (contributor_count >= 0),
  suppressed boolean NOT NULL,
  metrics jsonb NOT NULL CHECK (jsonb_typeof(metrics) = ''object''),
  report_sha256 text NOT NULL CHECK (report_sha256 ~ ''^[a-f0-9]{64}$''),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (version_id, report_date, segment_key),
  CHECK ((contributor_count < 10) = suppressed),
  CHECK (NOT (metrics ?| ARRAY[
    ''user_id'', ''client_id'', ''event_id'', ''alert_id'', ''occurred_at'', ''raw_error''
  ]))
);

CREATE TABLE private.adaptive_alert_shadow_profile_dirty (
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  invalidated_at timestamptz NOT NULL,
  reason text NOT NULL CHECK (reason IN (''settings_changed'', ''profile_changed'', ''consent_withdrawn'')),
  PRIMARY KEY (version_id, user_id)
);

CREATE TABLE private.adaptive_alert_shadow_cohort_dirty (
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE CASCADE,
  routine_mode text NOT NULL CHECK (
    routine_mode IN (''regular_9to5'', ''semester_break'', ''shift_irregular'')
  ),
  context_key text NOT NULL,
  invalidated_at timestamptz NOT NULL,
  reason text NOT NULL CHECK (reason IN (
    ''settings_changed'', ''profile_changed'', ''consent_withdrawn'',
    ''source_invalidation''
  )),
  PRIMARY KEY (version_id, routine_mode, context_key)
);

CREATE TABLE private.adaptive_alert_shadow_subject_context_state (
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  context_state text NOT NULL CHECK (context_state IN (''replayable'', ''unreplayable'')),
  unreplayable_reason text,
  subject_context_sha256 text NOT NULL CHECK (
    subject_context_sha256 ~ ''^[a-f0-9]{64}$''
  ),
  captured_at timestamptz NOT NULL,
  PRIMARY KEY (version_id, user_id),
  CHECK (
    (context_state = ''replayable'' AND unreplayable_reason IS NULL)
    OR
    (context_state = ''unreplayable'' AND unreplayable_reason IS NOT NULL)
  )
);

CREATE TABLE private.adaptive_alert_shadow_intervention_cursor (
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE CASCADE,
  source_kind text NOT NULL CHECK (
    source_kind IN (''notification'', ''checkin_task'', ''guardianship'')
  ),
  last_captured_at timestamptz NOT NULL,
  last_source_id uuid,
  PRIMARY KEY (version_id, source_kind)
);

ALTER TABLE private.adaptive_alert_shadow_user_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.adaptive_alert_shadow_cycle_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.adaptive_alert_shadow_daily_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.adaptive_alert_shadow_profile_dirty ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.adaptive_alert_shadow_cohort_dirty ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.adaptive_alert_shadow_subject_context_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.adaptive_alert_shadow_intervention_cursor ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON TABLE
  private.adaptive_alert_shadow_user_state,
  private.adaptive_alert_shadow_cycle_runs,
  private.adaptive_alert_shadow_daily_reports,
  private.adaptive_alert_shadow_profile_dirty,
  private.adaptive_alert_shadow_cohort_dirty,
  private.adaptive_alert_shadow_subject_context_state,
  private.adaptive_alert_shadow_intervention_cursor
FROM PUBLIC, anon, authenticated, service_role;

ALTER TABLE public.alert_intervention_events
  DROP CONSTRAINT alert_intervention_events_kind_check,
  ADD COLUMN source_kind text DEFAULT ''legacy'',
  ADD COLUMN source_id uuid DEFAULT gen_random_uuid();

UPDATE public.alert_intervention_events
SET source_kind = ''legacy'', source_id = id;

ALTER TABLE public.alert_intervention_events
  ALTER COLUMN source_kind SET NOT NULL,
  ALTER COLUMN source_id SET NOT NULL,
  ADD CONSTRAINT alert_intervention_events_kind_check CHECK (
    kind IN (
      ''self_alert'', ''self_prompt'', ''checkin_prompt'', ''concern_prompt'',
      ''guardian_confirmation''
    )
  ),
  ADD CONSTRAINT alert_intervention_events_source_kind_check CHECK (
    source_kind IN (''legacy'', ''notification'', ''checkin_task'', ''guardianship'')
  ),
  ADD CONSTRAINT alert_intervention_events_source_unique
    UNIQUE (version_id, source_kind, source_id);

CREATE FUNCTION private.capture_alert_shadow_subject_contexts(
  _version_id uuid,
  _captured_at timestamptz,
  _max_users integer
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET timezone = ''UTC''
AS $$
DECLARE
  _version public.alert_model_versions%ROWTYPE;
  _person record;
  _population_count integer := 0;
  _replayable_count integer := 0;
  _unreplayable_count integer := 0;
  _reason text;
  _state text;
  _offset integer;
  _context_sha text;
  _prior_sha text;
  _provenance jsonb;
BEGIN
  IF _version_id IS NULL OR _captured_at IS NULL
     OR _max_users IS NULL OR _max_users NOT BETWEEN 1 AND 10000 THEN
    RAISE EXCEPTION ''invalid shadow context capture arguments'';
  END IF;

  SELECT v.* INTO _version
  FROM public.alert_model_versions AS v
  WHERE v.id = _version_id
    AND v.status = ''shadow''
    AND v.shadow_enabled_at IS NOT NULL
    AND v.shadow_enabled_at <= _captured_at;

  IF NOT FOUND
     OR _version.evidence_version <> ''canonical-v2''
     OR _version.config_sha256 <>
       encode(extensions.digest(_version.config::text, ''sha256''), ''hex'') THEN
    RAISE EXCEPTION ''invalid shadow context version'';
  END IF;

  FOR _person IN
    WITH population AS (
      SELECT ds.user_id FROM public.device_state AS ds
      UNION
      SELECT gm.user_id
      FROM public.group_members AS gm
      WHERE gm.status = ''active'' AND gm.monitored
    )
    SELECT
      p.user_id,
      coalesce(s.sensitivity, ''balanced'') AS sensitivity,
      coalesce(s.timezone, ''UTC'') AS timezone,
      coalesce(s.updated_at, _captured_at) AS settings_updated_at,
      coalesce(pr.routine_pattern, ''regular_9to5'') AS routine_mode
    FROM population AS p
    LEFT JOIN public.user_settings AS s ON s.user_id = p.user_id
    LEFT JOIN public.profiles AS pr ON pr.id = p.user_id
    ORDER BY p.user_id
    LIMIT _max_users
  LOOP
    _population_count := _population_count + 1;
    _reason := NULL;
    _offset := 0;

    IF _person.settings_updated_at > _captured_at THEN
      _reason := ''future_source_timestamp'';
    ELSIF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_timezone_names AS z
      WHERE z.name = _person.timezone
    ) THEN
      _reason := ''invalid_timezone'';
    ELSE
      _offset := round(extract(epoch FROM (
        (_captured_at AT TIME ZONE _person.timezone)
        - (_captured_at AT TIME ZONE ''UTC'')
      )) / 60)::integer;
    END IF;

    _state := CASE WHEN _reason IS NULL THEN ''replayable'' ELSE ''unreplayable'' END;
    _provenance := jsonb_build_object(
      ''contract_version'', ''shadow-subject-context-v1'',
      ''version_id'', _version_id,
      ''user_id'', _person.user_id,
      ''sensitivity'', _person.sensitivity,
      ''routine_mode'', _person.routine_mode,
      ''timezone'', _person.timezone,
      ''utc_offset_minutes'', _offset,
      ''settings_updated_at'', _person.settings_updated_at,
      ''config_sha256'', _version.config_sha256,
      ''evidence_version'', _version.evidence_version,
      ''state'', _state,
      ''reason'', _reason
    );
    _context_sha := encode(
      extensions.digest(_provenance::text, ''sha256''), ''hex''
    );

    SELECT s.subject_context_sha256 INTO _prior_sha
    FROM private.adaptive_alert_shadow_subject_context_state AS s
    WHERE s.version_id = _version_id AND s.user_id = _person.user_id;

    IF _reason IS NOT NULL THEN
      UPDATE public.alert_judgment_subject_contexts
      SET effective_to = _captured_at
      WHERE version_id = _version_id
        AND user_id = _person.user_id
        AND effective_to IS NULL
        AND effective_from < _captured_at;
    ELSIF _prior_sha IS DISTINCT FROM _context_sha THEN
      UPDATE public.alert_judgment_subject_contexts
      SET effective_to = _captured_at
      WHERE version_id = _version_id
        AND user_id = _person.user_id
        AND effective_to IS NULL
        AND effective_from < _captured_at;

      INSERT INTO public.alert_judgment_subject_contexts (
        version_id, user_id, effective_from, raw_sensitivity,
        canonical_sensitivity, routine_mode, timezone, utc_offset_minutes,
        settings_updated_at, settings_provenance, captured_at,
        config_sha256, evidence_version, subject_context_sha256
      ) VALUES (
        _version_id, _person.user_id, _captured_at, _person.sensitivity,
        _person.sensitivity, _person.routine_mode, _person.timezone, _offset,
        _person.settings_updated_at, _provenance, _captured_at,
        _version.config_sha256, _version.evidence_version, _context_sha
      );
    END IF;

    INSERT INTO private.adaptive_alert_shadow_subject_context_state (
      version_id, user_id, context_state, unreplayable_reason,
      subject_context_sha256, captured_at
    ) VALUES (
      _version_id, _person.user_id, _state, _reason, _context_sha, _captured_at
    )
    ON CONFLICT (version_id, user_id) DO UPDATE SET
      context_state = excluded.context_state,
      unreplayable_reason = excluded.unreplayable_reason,
      subject_context_sha256 = excluded.subject_context_sha256,
      captured_at = excluded.captured_at;

    IF _reason IS NULL THEN
      _replayable_count := _replayable_count + 1;
    ELSE
      _unreplayable_count := _unreplayable_count + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    ''status'', ''completed'',
    ''population_count'', _population_count,
    ''replayable_count'', _replayable_count,
    ''unreplayable_count'', _unreplayable_count
  );
END;
$$;

CREATE FUNCTION private.capture_alert_shadow_interventions(
  _version_id uuid,
  _through_at timestamptz,
  _max_rows integer
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET timezone = ''UTC''
AS $$
DECLARE
  _evidence_version text;
  _inserted integer := 0;
  _step integer := 0;
BEGIN
  IF _version_id IS NULL OR _through_at IS NULL
     OR _max_rows IS NULL OR _max_rows NOT BETWEEN 1 AND 10000 THEN
    RAISE EXCEPTION ''invalid shadow intervention capture arguments'';
  END IF;

  SELECT v.evidence_version INTO _evidence_version
  FROM public.alert_model_versions AS v
  WHERE v.id = _version_id AND v.status = ''shadow'';
  IF NOT FOUND THEN
    RAISE EXCEPTION ''invalid shadow intervention version'';
  END IF;

  WITH source AS (
    SELECT n.id, n.recipient_id AS user_id, n.created_at AS occurred_at,
      CASE WHEN n.kind = ''self'' THEN ''self_alert'' ELSE ''concern_prompt'' END AS kind
    FROM public.notifications AS n
    WHERE n.created_at <= _through_at
    ORDER BY n.created_at, n.id
    LIMIT _max_rows
  )
  INSERT INTO public.alert_intervention_events (
    version_id, user_id, occurred_at, kind, captured_at, evidence_version,
    provenance_sha256, source_kind, source_id
  )
  SELECT
    _version_id, s.user_id, s.occurred_at, s.kind, _through_at,
    _evidence_version,
    encode(extensions.digest(jsonb_build_object(
      ''version_id'', _version_id, ''source_kind'', ''notification'',
      ''source_id'', s.id, ''user_id'', s.user_id,
      ''occurred_at'', s.occurred_at, ''kind'', s.kind
    )::text, ''sha256''), ''hex''),
    ''notification'', s.id
  FROM source AS s
  ON CONFLICT (version_id, source_kind, source_id) DO NOTHING;
  GET DIAGNOSTICS _step = ROW_COUNT;
  _inserted := _inserted + _step;

  WITH source AS (
    SELECT t.id, t.ward_id AS user_id, t.created_at AS occurred_at
    FROM public.checkin_tasks AS t
    WHERE t.created_at <= _through_at
    ORDER BY t.created_at, t.id
    LIMIT greatest(_max_rows - _inserted, 0)
  )
  INSERT INTO public.alert_intervention_events (
    version_id, user_id, occurred_at, kind, captured_at, evidence_version,
    provenance_sha256, source_kind, source_id
  )
  SELECT
    _version_id, s.user_id, s.occurred_at, ''checkin_prompt'', _through_at,
    _evidence_version,
    encode(extensions.digest(jsonb_build_object(
      ''version_id'', _version_id, ''source_kind'', ''checkin_task'',
      ''source_id'', s.id, ''user_id'', s.user_id,
      ''occurred_at'', s.occurred_at
    )::text, ''sha256''), ''hex''),
    ''checkin_task'', s.id
  FROM source AS s
  ON CONFLICT (version_id, source_kind, source_id) DO NOTHING;
  GET DIAGNOSTICS _step = ROW_COUNT;
  _inserted := _inserted + _step;

  WITH source AS (
    SELECT g.id, g.ward_id AS user_id, g.created_at AS occurred_at
    FROM public.guardianships AS g
    WHERE g.status = ''active'' AND g.created_at <= _through_at
    ORDER BY g.created_at, g.id
    LIMIT greatest(_max_rows - _inserted, 0)
  )
  INSERT INTO public.alert_intervention_events (
    version_id, user_id, occurred_at, kind, captured_at, evidence_version,
    provenance_sha256, source_kind, source_id
  )
  SELECT
    _version_id, s.user_id, s.occurred_at, ''guardian_confirmation'', _through_at,
    _evidence_version,
    encode(extensions.digest(jsonb_build_object(
      ''version_id'', _version_id, ''source_kind'', ''guardianship'',
      ''source_id'', s.id, ''user_id'', s.user_id,
      ''occurred_at'', s.occurred_at
    )::text, ''sha256''), ''hex''),
    ''guardianship'', s.id
  FROM source AS s
  ON CONFLICT (version_id, source_kind, source_id) DO NOTHING;
  GET DIAGNOSTICS _step = ROW_COUNT;
  _inserted := _inserted + _step;

  INSERT INTO private.adaptive_alert_shadow_intervention_cursor (
    version_id, source_kind, last_captured_at
  ) VALUES
    (_version_id, ''notification'', _through_at),
    (_version_id, ''checkin_task'', _through_at),
    (_version_id, ''guardianship'', _through_at)
  ON CONFLICT (version_id, source_kind) DO UPDATE SET
    last_captured_at = greatest(
      private.adaptive_alert_shadow_intervention_cursor.last_captured_at,
      excluded.last_captured_at
    );

  RETURN jsonb_build_object(''status'', ''completed'', ''inserted_count'', _inserted);
END;
$$;

CREATE FUNCTION private.mark_adaptive_alert_shadow_dirty()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''''
SET timezone = ''UTC''
AS $$
DECLARE
  _user_id uuid;
  _routine_mode text;
  _reason text;
  _changed_at timestamptz := clock_timestamp();
BEGIN
  IF TG_TABLE_NAME = ''profiles'' THEN
    _user_id := NEW.id;
    _routine_mode := coalesce(NEW.routine_pattern, ''regular_9to5'');
    _reason := CASE
      WHEN TG_OP = ''UPDATE''
       AND OLD.consent_data_sharing
       AND NOT NEW.consent_data_sharing
      THEN ''consent_withdrawn''
      ELSE ''profile_changed''
    END;
  ELSE
    _user_id := NEW.user_id;
    SELECT coalesce(p.routine_pattern, ''regular_9to5'')
      INTO _routine_mode
    FROM public.profiles AS p WHERE p.id = _user_id;
    _routine_mode := coalesce(_routine_mode, ''regular_9to5'');
    _reason := ''settings_changed'';
  END IF;

  INSERT INTO private.adaptive_alert_shadow_profile_dirty (
    version_id, user_id, invalidated_at, reason
  )
  SELECT v.id, _user_id, _changed_at, _reason
  FROM public.alert_model_versions AS v
  WHERE v.status = ''shadow''
  ON CONFLICT (version_id, user_id) DO UPDATE SET
    invalidated_at = greatest(
      private.adaptive_alert_shadow_profile_dirty.invalidated_at,
      excluded.invalidated_at
    ),
    reason = excluded.reason;

  INSERT INTO private.adaptive_alert_shadow_cohort_dirty (
    version_id, routine_mode, context_key, invalidated_at, reason
  )
  SELECT v.id, _routine_mode, ''*'', _changed_at, _reason
  FROM public.alert_model_versions AS v
  WHERE v.status = ''shadow''
  ON CONFLICT (version_id, routine_mode, context_key) DO UPDATE SET
    invalidated_at = greatest(
      private.adaptive_alert_shadow_cohort_dirty.invalidated_at,
      excluded.invalidated_at
    ),
    reason = excluded.reason;

  IF _reason = ''consent_withdrawn'' THEN
    DELETE FROM public.routine_mode_cohort_priors
    WHERE routine_mode = _routine_mode
      AND version_id IN (
        SELECT v.id FROM public.alert_model_versions AS v
        WHERE v.status = ''shadow''
      );
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER adaptive_alert_shadow_profile_dirty_trigger
AFTER UPDATE OF routine_pattern, consent_data_sharing ON public.profiles
FOR EACH ROW EXECUTE FUNCTION private.mark_adaptive_alert_shadow_dirty();

CREATE TRIGGER adaptive_alert_shadow_settings_dirty_trigger
AFTER UPDATE OF sensitivity, timezone ON public.user_settings
FOR EACH ROW EXECUTE FUNCTION private.mark_adaptive_alert_shadow_dirty();

CREATE FUNCTION private.maintain_adaptive_alert_shadow(
  _through_at timestamptz,
  _max_rows integer
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET timezone = ''UTC''
AS $$
DECLARE
  _deleted integer := 0;
  _step integer := 0;
  _reported integer := 0;
BEGIN
  IF _through_at IS NULL OR _max_rows IS NULL
     OR _max_rows NOT BETWEEN 1 AND 100000 THEN
    RAISE EXCEPTION ''invalid shadow maintenance arguments'';
  END IF;

  WITH doomed AS (
    SELECT c.id
    FROM public.alert_judgment_subject_contexts AS c
    WHERE coalesce(c.effective_to, c.captured_at)
      < _through_at - interval ''35 days''
    ORDER BY coalesce(c.effective_to, c.captured_at), c.id
    LIMIT _max_rows
  )
  DELETE FROM public.alert_judgment_subject_contexts AS c
  WHERE c.id IN (SELECT d.id FROM doomed AS d);
  GET DIAGNOSTICS _step = ROW_COUNT;
  _deleted := _deleted + _step;

  WITH doomed AS (
    SELECT e.id
    FROM public.alert_intervention_events AS e
    WHERE e.occurred_at < _through_at - interval ''35 days''
    ORDER BY e.occurred_at, e.id
    LIMIT greatest(_max_rows - _deleted, 0)
  )
  DELETE FROM public.alert_intervention_events AS e
  WHERE e.id IN (SELECT d.id FROM doomed AS d);
  GET DIAGNOSTICS _step = ROW_COUNT;
  _deleted := _deleted + _step;

  WITH doomed AS (
    SELECT d.id
    FROM public.alert_judgment_shadow_decisions AS d
    WHERE d.evaluated_at < _through_at - interval ''35 days''
    ORDER BY d.evaluated_at, d.id
    LIMIT greatest(_max_rows - _deleted, 0)
  )
  DELETE FROM public.alert_judgment_shadow_decisions AS d
  WHERE d.id IN (SELECT doomed.id FROM doomed);
  GET DIAGNOSTICS _step = ROW_COUNT;
  _deleted := _deleted + _step;

  WITH doomed AS (
    SELECT l.user_id, l.event_id
    FROM private.alert_shadow_coverage_leases AS l
    WHERE l.received_at < _through_at - interval ''35 days''
    ORDER BY l.received_at, l.user_id, l.event_id
    LIMIT greatest(_max_rows - _deleted, 0)
  )
  DELETE FROM private.alert_shadow_coverage_leases AS l
  WHERE (l.user_id, l.event_id) IN (
    SELECT doomed.user_id, doomed.event_id FROM doomed
  );
  GET DIAGNOSTICS _step = ROW_COUNT;
  _deleted := _deleted + _step;

  WITH doomed AS (
    SELECT c.id
    FROM public.alert_observation_coverage_intervals AS c
    WHERE c.ends_at < _through_at - interval ''35 days''
    ORDER BY c.ends_at, c.id
    LIMIT greatest(_max_rows - _deleted, 0)
  )
  DELETE FROM public.alert_observation_coverage_intervals AS c
  WHERE c.id IN (SELECT doomed.id FROM doomed);
  GET DIAGNOSTICS _step = ROW_COUNT;
  _deleted := _deleted + _step;

  WITH doomed AS (
    SELECT s.version_id, s.user_id
    FROM private.adaptive_alert_shadow_user_state AS s
    WHERE s.evaluated_at < _through_at - interval ''35 days''
    ORDER BY s.evaluated_at, s.version_id, s.user_id
    LIMIT greatest(_max_rows - _deleted, 0)
  )
  DELETE FROM private.adaptive_alert_shadow_user_state AS s
  WHERE (s.version_id, s.user_id) IN (
    SELECT doomed.version_id, doomed.user_id FROM doomed
  );
  GET DIAGNOSTICS _step = ROW_COUNT;
  _deleted := _deleted + _step;

  WITH doomed AS (
    SELECT s.version_id, s.user_id
    FROM private.adaptive_alert_shadow_subject_context_state AS s
    WHERE s.captured_at < _through_at - interval ''35 days''
    ORDER BY s.captured_at, s.version_id, s.user_id
    LIMIT greatest(_max_rows - _deleted, 0)
  )
  DELETE FROM private.adaptive_alert_shadow_subject_context_state AS s
  WHERE (s.version_id, s.user_id) IN (
    SELECT doomed.version_id, doomed.user_id FROM doomed
  );
  GET DIAGNOSTICS _step = ROW_COUNT;
  _deleted := _deleted + _step;

  INSERT INTO private.adaptive_alert_shadow_cohort_dirty (
    version_id, routine_mode, context_key, invalidated_at, reason
  )
  SELECT
    v.id, i.routine_mode, ''*'', i.invalidated_at, ''source_invalidation''
  FROM public.alert_model_versions AS v
  CROSS JOIN public.routine_mode_cohort_invalidations AS i
  WHERE v.status = ''shadow''
  ON CONFLICT (version_id, routine_mode, context_key) DO UPDATE SET
    invalidated_at = greatest(
      private.adaptive_alert_shadow_cohort_dirty.invalidated_at,
      excluded.invalidated_at
    ),
    reason = excluded.reason;

  DELETE FROM public.routine_mode_cohort_priors AS p
  WHERE p.version_id IN (
      SELECT v.id FROM public.alert_model_versions AS v
      WHERE v.status = ''shadow''
    )
    AND EXISTS (
      SELECT 1
      FROM private.adaptive_alert_shadow_cohort_dirty AS d
      WHERE d.version_id = p.version_id
        AND d.routine_mode = p.routine_mode
        AND (d.context_key = ''*'' OR d.context_key = p.context_key)
        AND d.invalidated_at >= p.published_at
    );

  WITH report AS (
    SELECT
      v.id AS version_id,
      count(s.user_id)::integer AS contributor_count,
      count(*) FILTER (WHERE s.replayable)::integer AS replayable_count,
      count(*) FILTER (WHERE s.would_alert IS TRUE)::integer AS would_alert_count
    FROM public.alert_model_versions AS v
    LEFT JOIN private.adaptive_alert_shadow_user_state AS s
      ON s.version_id = v.id
     AND s.evaluated_at >= date_trunc(''day'', _through_at)
     AND s.evaluated_at < date_trunc(''day'', _through_at) + interval ''1 day''
    WHERE v.status = ''shadow''
    GROUP BY v.id
  ), prepared AS (
    SELECT
      r.version_id,
      (_through_at AT TIME ZONE ''UTC'')::date AS report_date,
      CASE WHEN r.contributor_count < 10 THEN ''other'' ELSE ''all'' END AS segment_key,
      r.contributor_count,
      r.contributor_count < 10 AS suppressed,
      CASE WHEN r.contributor_count < 10
        THEN jsonb_build_object(''suppressed'', true)
        ELSE jsonb_build_object(
          ''replayable_count'', r.replayable_count,
          ''would_alert_count'', r.would_alert_count
        )
      END AS metrics
    FROM report AS r
  )
  INSERT INTO private.adaptive_alert_shadow_daily_reports (
    version_id, report_date, segment_key, contributor_count, suppressed,
    metrics, report_sha256
  )
  SELECT
    p.version_id, p.report_date, p.segment_key, p.contributor_count,
    p.suppressed, p.metrics,
    encode(extensions.digest(jsonb_build_object(
      ''version_id'', p.version_id,
      ''report_date'', p.report_date,
      ''segment_key'', p.segment_key,
      ''contributor_count'', p.contributor_count,
      ''suppressed'', p.suppressed,
      ''metrics'', p.metrics
    )::text, ''sha256''), ''hex'')
  FROM prepared AS p
  ON CONFLICT (version_id, report_date, segment_key) DO UPDATE SET
    contributor_count = excluded.contributor_count,
    suppressed = excluded.suppressed,
    metrics = excluded.metrics,
    report_sha256 = excluded.report_sha256,
    created_at = clock_timestamp();
  GET DIAGNOSTICS _reported = ROW_COUNT;

  RETURN jsonb_build_object(
    ''status'', ''completed'',
    ''deleted_count'', _deleted,
    ''reported_count'', _reported
  );
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.capture_alert_shadow_subject_contexts(uuid,timestamptz,integer),
  private.capture_alert_shadow_interventions(uuid,timestamptz,integer),
  private.mark_adaptive_alert_shadow_dirty(),
  private.maintain_adaptive_alert_shadow(timestamptz,integer)
FROM PUBLIC, anon, authenticated, service_role;
"}', 'adaptive_alert_shadow_operational_schema', 'codex-release-v0.5.21', NULL, NULL),
	('20260727175000', '{"-- ADR-0028: default-disabled, scheduler-off operational shadow cycle.
-- The cycle evaluates candidate behavior only and fails closed on isolation drift.

CREATE FUNCTION private.record_alert_judgment_shadow_operational(
  _version_id uuid,
  _evaluated_at timestamptz,
  _max_population integer
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET timezone = ''UTC''
SET \"DateStyle\" = ''ISO, YMD''
SET extra_float_digits = 3
AS $$
DECLARE
  _person_id uuid;
  _result jsonb;
  _replayable boolean;
  _reason text;
  _decision_sha text;
  _prior private.adaptive_alert_shadow_user_state%ROWTYPE;
  _fallback_path text[];
  _population_count integer := 0;
  _evaluated_count integer := 0;
  _replayable_count integer := 0;
  _unreplayable_count integer := 0;
  _persisted_count integer := 0;
  _detail_count integer;
  _should_persist boolean;
  _minute timestamptz;
  _provenance_sha text;
  _result_key_count integer;
  _minute_utc text;
  _required_keys constant text[] := ARRAY[
    ''basis'', ''candidate_cap_reason'', ''candidate_ceiling_minutes'',
    ''candidate_deadline'', ''candidate_floor_minutes'',
    ''candidate_threshold_minutes'', ''confidence'', ''context_key'',
    ''deadline_basis'', ''decision_provenance'', ''effective_silence_minutes'',
    ''evaluated_at'', ''evaluator_version'', ''evidence_cutoff'', ''fallback_path'',
    ''guardian_used_as_activity'', ''neutral_threshold_minutes'',
    ''provenance_sha256'', ''quality_state'', ''replayable'',
    ''selected_source_sha256'', ''sensitivity_buffer_minutes'',
    ''sleep_interval_provenance'', ''subject_context_sha256'',
    ''unclamped_candidate_threshold_minutes'', ''unreplayable_reason'',
    ''version_id'', ''would_alert''
  ];
BEGIN
  IF _version_id IS NULL OR _evaluated_at IS NULL
     OR _max_population IS NULL OR _max_population NOT BETWEEN 1 AND 10000 THEN
    RAISE EXCEPTION ''invalid operational shadow recorder arguments'';
  END IF;
  _minute := date_trunc(''minute'', _evaluated_at AT TIME ZONE ''UTC'')
    AT TIME ZONE ''UTC'';
  _minute_utc := to_char(
    _minute AT TIME ZONE ''UTC'', ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''
  );

  FOR _person_id IN
    WITH population AS (
      SELECT ds.user_id FROM public.device_state AS ds
      UNION
      SELECT gm.user_id
      FROM public.group_members AS gm
      WHERE gm.status = ''active'' AND gm.monitored
    )
    SELECT p.user_id
    FROM population AS p
    ORDER BY p.user_id
    LIMIT _max_population
  LOOP
    _population_count := _population_count + 1;
    _result := private.resolve_alert_candidate(_person_id, _minute, _version_id);
    _evaluated_count := _evaluated_count + 1;

    IF _result IS NULL OR jsonb_typeof(_result) <> ''object'' THEN
      RAISE EXCEPTION ''malformed operational shadow result'';
    END IF;
    SELECT count(*)::integer INTO _result_key_count
    FROM jsonb_object_keys(_result);
    IF NOT (_result ?& _required_keys)
       OR _result_key_count <> cardinality(_required_keys)
       OR jsonb_typeof(_result -> ''replayable'') <> ''boolean''
       OR _result ->> ''version_id'' <> _version_id::text
       OR _result ->> ''evaluated_at'' <> _minute_utc
       OR _result ->> ''evidence_cutoff'' <> _minute_utc
       OR _result ->> ''evaluator_version'' <> ''adaptive_candidate_v1''
       OR jsonb_typeof(_result -> ''decision_provenance'') <> ''object''
       OR jsonb_typeof(_result -> ''provenance_sha256'') <> ''string''
       OR jsonb_typeof(_result -> ''guardian_used_as_activity'') <> ''boolean''
       OR (_result ->> ''guardian_used_as_activity'')::boolean THEN
      RAISE EXCEPTION ''malformed operational shadow result'';
    END IF;

    _provenance_sha := encode(
      extensions.digest((_result -> ''decision_provenance'')::text, ''sha256''),
      ''hex''
    );
    IF _result ->> ''provenance_sha256'' <> _provenance_sha THEN
      RAISE EXCEPTION ''operational shadow provenance mismatch'';
    END IF;

    _replayable := (_result ->> ''replayable'')::boolean;
    _reason := _result ->> ''unreplayable_reason'';
    _decision_sha := encode(extensions.digest(jsonb_build_object(
      ''version_id'', _version_id,
      ''user_id'', _person_id,
      ''evaluated_minute'', _minute,
      ''evaluator_result'', _result
    )::text, ''sha256''), ''hex'');

    SELECT s.* INTO _prior
    FROM private.adaptive_alert_shadow_user_state AS s
    WHERE s.version_id = _version_id AND s.user_id = _person_id;

    _should_persist := _replayable AND (
      NOT FOUND
      OR _prior.would_alert IS DISTINCT FROM
        (_result ->> ''would_alert'')::boolean
      OR _prior.basis IS DISTINCT FROM _result ->> ''basis''
      OR _prior.candidate_threshold_minutes IS DISTINCT FROM
        (_result ->> ''candidate_threshold_minutes'')::integer
      OR _prior.quality_state IS DISTINCT FROM _result ->> ''quality_state''
      OR _prior.unreplayable_reason IS DISTINCT FROM _reason
      OR _prior.last_persisted_at IS NULL
      OR _prior.last_persisted_at <= _minute - interval ''1 hour''
    );

    INSERT INTO private.adaptive_alert_shadow_user_state (
      version_id, user_id, evaluated_at, replayable, would_alert, basis,
      candidate_threshold_minutes, quality_state, unreplayable_reason,
      decision_sha256, last_persisted_at, updated_at
    ) VALUES (
      _version_id, _person_id, _minute, _replayable,
      CASE WHEN _replayable THEN (_result ->> ''would_alert'')::boolean END,
      CASE WHEN _replayable THEN _result ->> ''basis'' END,
      CASE WHEN _replayable
        THEN (_result ->> ''candidate_threshold_minutes'')::integer END,
      coalesce(_result ->> ''quality_state'', ''coverage_invalid''),
      CASE WHEN _replayable THEN NULL ELSE _reason END,
      _decision_sha,
      CASE WHEN _should_persist THEN _minute ELSE _prior.last_persisted_at END,
      clock_timestamp()
    )
    ON CONFLICT (version_id, user_id) DO UPDATE SET
      evaluated_at = excluded.evaluated_at,
      replayable = excluded.replayable,
      would_alert = excluded.would_alert,
      basis = excluded.basis,
      candidate_threshold_minutes = excluded.candidate_threshold_minutes,
      quality_state = excluded.quality_state,
      unreplayable_reason = excluded.unreplayable_reason,
      decision_sha256 = excluded.decision_sha256,
      last_persisted_at = excluded.last_persisted_at,
      updated_at = excluded.updated_at;

    IF NOT _replayable THEN
      IF _reason NOT IN (
        ''missing_subject_context'', ''ambiguous_subject_context'',
        ''subject_context_provenance_invalid'', ''missing_qualified_session''
      ) THEN
        RAISE EXCEPTION ''invalid operational shadow unreplayable reason'';
      END IF;
      _unreplayable_count := _unreplayable_count + 1;
      CONTINUE;
    END IF;

    IF _result ->> ''basis'' IS NULL
       OR _result ->> ''candidate_threshold_minutes'' IS NULL
       OR _result ->> ''subject_context_sha256'' IS NULL
       OR jsonb_typeof(_result -> ''fallback_path'') <> ''array'' THEN
      RAISE EXCEPTION ''malformed replayable operational shadow result'';
    END IF;

    IF _should_persist THEN
      SELECT count(*)::integer INTO _detail_count
      FROM public.alert_judgment_shadow_decisions AS d
      WHERE d.version_id = _version_id
        AND d.user_id = _person_id
        AND d.evaluated_at >= date_trunc(''day'', _minute)
        AND d.evaluated_at < date_trunc(''day'', _minute) + interval ''1 day'';
      IF _detail_count >= 36 THEN
        RAISE EXCEPTION ''shadow_detail_budget_exceeded'';
      END IF;

      SELECT array_agg(path.value ORDER BY path.ordinal)
        INTO _fallback_path
      FROM jsonb_array_elements_text(_result -> ''fallback_path'')
        WITH ORDINALITY AS path(value, ordinal);

      INSERT INTO public.alert_judgment_shadow_decisions (
        version_id, user_id, evaluated_at, basis, evaluator_version,
        context_key, neutral_threshold_minutes, sensitivity_buffer_minutes,
        candidate_threshold_minutes, effective_silence_minutes,
        candidate_deadline, would_alert, confidence, quality_state,
        fallback_path, sleep_interval_provenance, provenance_sha256,
        guardian_used_as_activity, evidence_cutoff,
        unclamped_candidate_threshold_minutes, candidate_floor_minutes,
        candidate_ceiling_minutes, candidate_cap_reason, deadline_basis,
        selected_source_sha256, subject_context_sha256,
        decision_provenance, decision_sha256
      ) VALUES (
        _version_id, _person_id, _minute, _result ->> ''basis'',
        _result ->> ''evaluator_version'', _result ->> ''context_key'',
        (_result ->> ''neutral_threshold_minutes'')::integer,
        (_result ->> ''sensitivity_buffer_minutes'')::integer,
        (_result ->> ''candidate_threshold_minutes'')::integer,
        (_result ->> ''effective_silence_minutes'')::double precision,
        (_result ->> ''candidate_deadline'')::timestamptz,
        (_result ->> ''would_alert'')::boolean,
        (_result ->> ''confidence'')::double precision,
        _result ->> ''quality_state'', _fallback_path,
        _result -> ''sleep_interval_provenance'', _provenance_sha, false,
        (_result ->> ''evidence_cutoff'')::timestamptz,
        (_result ->> ''unclamped_candidate_threshold_minutes'')::integer,
        (_result ->> ''candidate_floor_minutes'')::integer,
        (_result ->> ''candidate_ceiling_minutes'')::integer,
        _result ->> ''candidate_cap_reason'',
        _result ->> ''deadline_basis'',
        _result ->> ''selected_source_sha256'',
        _result ->> ''subject_context_sha256'',
        _result -> ''decision_provenance'', _decision_sha
      )
      ON CONFLICT (version_id, user_id, evaluated_minute) DO NOTHING;
      IF FOUND THEN
        _persisted_count := _persisted_count + 1;
      END IF;
    END IF;
    _replayable_count := _replayable_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    ''status'', CASE WHEN _population_count = 0 THEN ''empty'' ELSE ''completed'' END,
    ''population_count'', _population_count,
    ''evaluated_count'', _evaluated_count,
    ''replayable_count'', _replayable_count,
    ''unreplayable_count'', _unreplayable_count,
    ''persisted_count'', _persisted_count
  );
END;
$$;

CREATE FUNCTION private.run_adaptive_alert_shadow_cycle(
  _version_id uuid,
  _evaluated_at timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET timezone = ''UTC''
AS $$
DECLARE
  _runtime private.adaptive_alert_shadow_runtime_config%ROWTYPE;
  _version public.alert_model_versions%ROWTYPE;
  _minute timestamptz;
  _started_at timestamptz := clock_timestamp();
  _result jsonb;
  _population_count integer;
  _evaluated_count integer;
  _before_dml bigint := 0;
  _after_dml bigint := 0;
  _duration_ms integer;
  _metrics jsonb;
  _run_sha text;
  _person_id uuid;
  _population_total integer;
BEGIN
  SELECT c.* INTO _runtime
  FROM private.adaptive_alert_shadow_runtime_config AS c
  WHERE c.singleton;
  IF _runtime.enabled IS NOT TRUE THEN
    RETURN jsonb_build_object(''status'', ''disabled'');
  END IF;
  IF _runtime.version_id IS DISTINCT FROM _version_id THEN
    RAISE EXCEPTION ''shadow_runtime_version_mismatch'';
  END IF;
  IF _evaluated_at IS NULL THEN
    RAISE EXCEPTION ''shadow_invalid_evaluation_time'';
  END IF;
  _minute := date_trunc(''minute'', _evaluated_at AT TIME ZONE ''UTC'')
    AT TIME ZONE ''UTC'';

  IF EXISTS (
    SELECT 1 FROM private.adaptive_alert_shadow_cycle_runs AS r
    WHERE r.version_id = _version_id AND r.evaluated_minute = _minute
  ) THEN
    RETURN jsonb_build_object(''status'', ''duplicate'');
  END IF;
  IF NOT pg_try_advisory_xact_lock(
    hashtextextended(''adaptive-alert-shadow:'' || _version_id::text, 0)
  ) THEN
    RETURN jsonb_build_object(''status'', ''busy'');
  END IF;

  SELECT v.* INTO _version
  FROM public.alert_model_versions AS v
  WHERE v.id = _version_id;
  IF NOT FOUND OR _version.status <> ''shadow''
     OR _version.shadow_enabled_at IS NULL
     OR _version.shadow_enabled_at > _minute
     OR _version.evidence_version <> ''canonical-v2''
     OR _version.config_sha256 <>
       encode(extensions.digest(_version.config::text, ''sha256''), ''hex'') THEN
    RAISE EXCEPTION ''shadow_version_validation_failed'';
  END IF;
  IF _version.config #>> ''{emergency,expected_live_definition_sha256}''
     <> encode(extensions.digest(pg_get_functiondef(
       ''private.silence_threshold(uuid)''::regprocedure
     ), ''sha256''), ''hex'') THEN
    RAISE EXCEPTION ''shadow_live_hash_mismatch'';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS c
    WHERE c.oid IN (
      ''private.adaptive_alert_shadow_user_state''::regclass,
      ''private.adaptive_alert_shadow_cycle_runs''::regclass,
      ''private.adaptive_alert_shadow_daily_reports''::regclass
    ) AND NOT c.relrowsecurity
  ) OR has_table_privilege(
    ''authenticated'', ''private.adaptive_alert_shadow_user_state'', ''SELECT''
  ) THEN
    RAISE EXCEPTION ''shadow_acl_validation_failed'';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_publication_tables AS p
    WHERE p.tablename LIKE ''adaptive_alert_shadow_%''
      AND p.schemaname IN (''private'', ''public'')
  ) THEN
    RAISE EXCEPTION ''shadow_publication_validation_failed'';
  END IF;

  SELECT count(*)::integer INTO _population_total
  FROM (
    SELECT ds.user_id FROM public.device_state AS ds
    UNION
    SELECT gm.user_id FROM public.group_members AS gm
    WHERE gm.status = ''active'' AND gm.monitored
  ) AS population;
  IF _population_total > _runtime.max_population THEN
    RAISE EXCEPTION ''shadow_population_budget_exceeded'';
  END IF;

  SELECT coalesce(sum(
    s.n_tup_ins + s.n_tup_upd + s.n_tup_del
  ), 0) INTO _before_dml
  FROM pg_catalog.pg_stat_xact_user_tables AS s
  WHERE s.relid IN (
    ''public.alerts''::regclass,
    ''public.alert_events''::regclass,
    ''public.notifications''::regclass
  );

  IF _runtime.accept_coverage_leases THEN
    FOR _person_id IN
      WITH population AS (
        SELECT ds.user_id FROM public.device_state AS ds
        UNION
        SELECT gm.user_id FROM public.group_members AS gm
        WHERE gm.status = ''active'' AND gm.monitored
      )
      SELECT p.user_id FROM population AS p
      ORDER BY p.user_id LIMIT _runtime.max_population
    LOOP
      PERFORM private.finalize_alert_shadow_coverage(
        _person_id, _minute, _runtime.detail_retention_days
      );
    END LOOP;
  END IF;

  PERFORM private.capture_alert_shadow_subject_contexts(
    _version_id, _minute, _runtime.max_population
  );
  PERFORM private.capture_alert_shadow_interventions(
    _version_id, _minute, _runtime.max_population
  );
  PERFORM private.maintain_adaptive_alert_shadow(
    _minute, _runtime.max_population
  );
  _result := private.record_alert_judgment_shadow_operational(
    _version_id, _minute, _runtime.max_population
  );

  SELECT coalesce(sum(
    s.n_tup_ins + s.n_tup_upd + s.n_tup_del
  ), 0) INTO _after_dml
  FROM pg_catalog.pg_stat_xact_user_tables AS s
  WHERE s.relid IN (
    ''public.alerts''::regclass,
    ''public.alert_events''::regclass,
    ''public.notifications''::regclass
  );
  IF _after_dml <> _before_dml THEN
    RAISE EXCEPTION ''shadow_live_write_detected'';
  END IF;

  _population_count := (_result ->> ''population_count'')::integer;
  _evaluated_count := (_result ->> ''evaluated_count'')::integer;
  _duration_ms := greatest(
    0, round(extract(epoch FROM (clock_timestamp() - _started_at)) * 1000)::integer
  );
  _metrics := jsonb_build_object(
    ''replayable_count'', (_result ->> ''replayable_count'')::integer,
    ''unreplayable_count'', (_result ->> ''unreplayable_count'')::integer,
    ''persisted_count'', (_result ->> ''persisted_count'')::integer
  );
  _run_sha := encode(extensions.digest(jsonb_build_object(
    ''version_id'', _version_id,
    ''evaluated_minute'', _minute,
    ''population_count'', _population_count,
    ''evaluated_count'', _evaluated_count,
    ''metrics'', _metrics
  )::text, ''sha256''), ''hex'');

  INSERT INTO private.adaptive_alert_shadow_cycle_runs (
    version_id, evaluated_minute, status, duration_ms, population_count,
    evaluated_count, metrics, run_sha256
  ) VALUES (
    _version_id, _minute,
    CASE WHEN _population_count = 0 THEN ''empty'' ELSE ''completed'' END,
    _duration_ms, _population_count, _evaluated_count, _metrics, _run_sha
  );

  RETURN jsonb_build_object(
    ''status'', ''completed'',
    ''population_count'', _population_count,
    ''evaluated_count'', _evaluated_count,
    ''duration_ms'', _duration_ms
  );
END;
$$;

CREATE FUNCTION private.disable_adaptive_alert_shadow(_failure_code text)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET timezone = ''UTC''
AS $$
DECLARE
  _fixed_code text;
BEGIN
  _fixed_code := CASE
    WHEN _failure_code IN (
      ''shadow_live_write_detected'',
      ''shadow_live_hash_mismatch'',
      ''shadow_acl_validation_failed'',
      ''shadow_publication_validation_failed'',
      ''shadow_detail_budget_exceeded'',
      ''shadow_population_budget_exceeded'',
      ''shadow_timeout'',
      ''shadow_privacy_validation_failed'',
      ''shadow_malformed_result'',
      ''ordinary_failure''
    ) THEN _failure_code
    ELSE ''ordinary_failure''
  END;
  UPDATE private.adaptive_alert_shadow_runtime_config
  SET enabled = false,
      last_failure_code = _fixed_code,
      updated_at = clock_timestamp()
  WHERE singleton;
END;
$$;

CREATE FUNCTION private.dispatch_adaptive_alert_shadow_cycle()
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET timezone = ''UTC''
AS $$
DECLARE
  _runtime private.adaptive_alert_shadow_runtime_config%ROWTYPE;
  _failure_code text;
  _result jsonb;
  _failures integer;
BEGIN
  SELECT c.* INTO _runtime
  FROM private.adaptive_alert_shadow_runtime_config AS c
  WHERE c.singleton;
  IF _runtime.enabled IS NOT TRUE OR _runtime.version_id IS NULL THEN
    RETURN;
  END IF;

  PERFORM set_config(''statement_timeout'', ''120s'', true);
  PERFORM set_config(''lock_timeout'', ''2s'', true);

  BEGIN
    _result := private.run_adaptive_alert_shadow_cycle(
      _runtime.version_id, clock_timestamp()
    );
    IF _result ->> ''status'' IN (''completed'', ''duplicate'') THEN
      UPDATE private.adaptive_alert_shadow_runtime_config
      SET consecutive_failures = 0,
          last_failure_code = NULL,
          updated_at = clock_timestamp()
      WHERE singleton;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    _failure_code := CASE
      WHEN SQLSTATE = ''57014'' THEN ''shadow_timeout''
      WHEN SQLERRM LIKE ''%shadow_live_write_detected%''
        THEN ''shadow_live_write_detected''
      WHEN SQLERRM LIKE ''%shadow_live_hash_mismatch%''
        THEN ''shadow_live_hash_mismatch''
      WHEN SQLERRM LIKE ''%shadow_acl_validation_failed%''
        THEN ''shadow_acl_validation_failed''
      WHEN SQLERRM LIKE ''%shadow_publication_validation_failed%''
        THEN ''shadow_publication_validation_failed''
      WHEN SQLERRM LIKE ''%shadow_detail_budget_exceeded%''
        THEN ''shadow_detail_budget_exceeded''
      WHEN SQLERRM LIKE ''%shadow_population_budget_exceeded%''
        THEN ''shadow_population_budget_exceeded''
      WHEN SQLERRM LIKE ''%malformed%''
        THEN ''shadow_malformed_result''
      ELSE ''ordinary_failure''
    END;

    IF _failure_code <> ''ordinary_failure'' THEN
      PERFORM private.disable_adaptive_alert_shadow(_failure_code);
      RETURN;
    END IF;

    UPDATE private.adaptive_alert_shadow_runtime_config
    SET consecutive_failures = least(
          max_consecutive_failures, consecutive_failures + 1
        ),
        last_failure_code = ''ordinary_failure'',
        updated_at = clock_timestamp()
    WHERE singleton
    RETURNING consecutive_failures INTO _failures;
    IF _failures >= _runtime.max_consecutive_failures THEN
      PERFORM private.disable_adaptive_alert_shadow(''ordinary_failure'');
    END IF;
  END;
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.record_alert_judgment_shadow_operational(uuid,timestamptz,integer),
  private.run_adaptive_alert_shadow_cycle(uuid,timestamptz),
  private.disable_adaptive_alert_shadow(text),
  private.dispatch_adaptive_alert_shadow_cycle()
FROM PUBLIC, anon, authenticated, service_role;
"}', 'adaptive_alert_shadow_operational_cycle', 'codex-release-v0.5.21', NULL, NULL),
	('20260727175500', '{"-- ADR-0028 audit repair: operational shadow population is the intersection of
-- registered device state and at least one active monitored group direction.
-- This append-only correction preserves scheduler-off and shadow-only behavior.

CREATE OR REPLACE FUNCTION private.capture_alert_shadow_subject_contexts(
  _version_id uuid,
  _captured_at timestamptz,
  _max_users integer
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET timezone = ''UTC''
AS $$
DECLARE
  _version public.alert_model_versions%ROWTYPE;
  _person record;
  _population_count integer := 0;
  _replayable_count integer := 0;
  _unreplayable_count integer := 0;
  _reason text;
  _state text;
  _offset integer;
  _context_sha text;
  _prior_sha text;
  _provenance jsonb;
BEGIN
  IF _version_id IS NULL OR _captured_at IS NULL
     OR _max_users IS NULL OR _max_users NOT BETWEEN 1 AND 10000 THEN
    RAISE EXCEPTION ''invalid shadow context capture arguments'';
  END IF;

  SELECT v.* INTO _version
  FROM public.alert_model_versions AS v
  WHERE v.id = _version_id
    AND v.status = ''shadow''
    AND v.shadow_enabled_at IS NOT NULL
    AND v.shadow_enabled_at <= _captured_at;

  IF NOT FOUND
     OR _version.evidence_version <> ''canonical-v2''
     OR _version.config_sha256 <>
       encode(extensions.digest(_version.config::text, ''sha256''), ''hex'') THEN
    RAISE EXCEPTION ''invalid shadow context version'';
  END IF;

  FOR _person IN
    WITH population AS (
      SELECT DISTINCT ds.user_id
      FROM public.device_state AS ds
      WHERE EXISTS (
        SELECT 1
        FROM public.group_members AS gm
        WHERE gm.user_id = ds.user_id
          AND gm.status = ''active''
          AND gm.monitored
      )
    )
    SELECT
      p.user_id,
      coalesce(s.sensitivity, ''balanced'') AS sensitivity,
      coalesce(s.timezone, ''UTC'') AS timezone,
      coalesce(s.updated_at, _captured_at) AS settings_updated_at,
      coalesce(pr.routine_pattern, ''regular_9to5'') AS routine_mode
    FROM population AS p
    LEFT JOIN public.user_settings AS s ON s.user_id = p.user_id
    LEFT JOIN public.profiles AS pr ON pr.id = p.user_id
    ORDER BY p.user_id
    LIMIT _max_users
  LOOP
    _population_count := _population_count + 1;
    _reason := NULL;
    _offset := 0;

    IF _person.settings_updated_at > _captured_at THEN
      _reason := ''future_source_timestamp'';
    ELSIF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_timezone_names AS z
      WHERE z.name = _person.timezone
    ) THEN
      _reason := ''invalid_timezone'';
    ELSE
      _offset := round(extract(epoch FROM (
        (_captured_at AT TIME ZONE _person.timezone)
        - (_captured_at AT TIME ZONE ''UTC'')
      )) / 60)::integer;
    END IF;

    _state := CASE WHEN _reason IS NULL THEN ''replayable'' ELSE ''unreplayable'' END;
    _provenance := jsonb_build_object(
      ''contract_version'', ''shadow-subject-context-v1'',
      ''version_id'', _version_id,
      ''user_id'', _person.user_id,
      ''sensitivity'', _person.sensitivity,
      ''routine_mode'', _person.routine_mode,
      ''timezone'', _person.timezone,
      ''utc_offset_minutes'', _offset,
      ''settings_updated_at'', _person.settings_updated_at,
      ''config_sha256'', _version.config_sha256,
      ''evidence_version'', _version.evidence_version,
      ''state'', _state,
      ''reason'', _reason
    );
    _context_sha := encode(
      extensions.digest(_provenance::text, ''sha256''), ''hex''
    );

    SELECT s.subject_context_sha256 INTO _prior_sha
    FROM private.adaptive_alert_shadow_subject_context_state AS s
    WHERE s.version_id = _version_id AND s.user_id = _person.user_id;

    IF _reason IS NOT NULL THEN
      UPDATE public.alert_judgment_subject_contexts
      SET effective_to = _captured_at
      WHERE version_id = _version_id
        AND user_id = _person.user_id
        AND effective_to IS NULL
        AND effective_from < _captured_at;
    ELSIF _prior_sha IS DISTINCT FROM _context_sha THEN
      UPDATE public.alert_judgment_subject_contexts
      SET effective_to = _captured_at
      WHERE version_id = _version_id
        AND user_id = _person.user_id
        AND effective_to IS NULL
        AND effective_from < _captured_at;

      INSERT INTO public.alert_judgment_subject_contexts (
        version_id, user_id, effective_from, raw_sensitivity,
        canonical_sensitivity, routine_mode, timezone, utc_offset_minutes,
        settings_updated_at, settings_provenance, captured_at,
        config_sha256, evidence_version, subject_context_sha256
      ) VALUES (
        _version_id, _person.user_id, _captured_at, _person.sensitivity,
        _person.sensitivity, _person.routine_mode, _person.timezone, _offset,
        _person.settings_updated_at, _provenance, _captured_at,
        _version.config_sha256, _version.evidence_version, _context_sha
      );
    END IF;

    INSERT INTO private.adaptive_alert_shadow_subject_context_state (
      version_id, user_id, context_state, unreplayable_reason,
      subject_context_sha256, captured_at
    ) VALUES (
      _version_id, _person.user_id, _state, _reason, _context_sha, _captured_at
    )
    ON CONFLICT (version_id, user_id) DO UPDATE SET
      context_state = excluded.context_state,
      unreplayable_reason = excluded.unreplayable_reason,
      subject_context_sha256 = excluded.subject_context_sha256,
      captured_at = excluded.captured_at;

    IF _reason IS NULL THEN
      _replayable_count := _replayable_count + 1;
    ELSE
      _unreplayable_count := _unreplayable_count + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    ''status'', ''completed'',
    ''population_count'', _population_count,
    ''replayable_count'', _replayable_count,
    ''unreplayable_count'', _unreplayable_count
  );
END;
$$;

CREATE OR REPLACE FUNCTION private.record_alert_judgment_shadow_operational(
  _version_id uuid,
  _evaluated_at timestamptz,
  _max_population integer
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET timezone = ''UTC''
SET \"DateStyle\" = ''ISO, YMD''
SET extra_float_digits = 3
AS $$
DECLARE
  _person_id uuid;
  _result jsonb;
  _replayable boolean;
  _reason text;
  _decision_sha text;
  _prior private.adaptive_alert_shadow_user_state%ROWTYPE;
  _fallback_path text[];
  _population_count integer := 0;
  _evaluated_count integer := 0;
  _replayable_count integer := 0;
  _unreplayable_count integer := 0;
  _persisted_count integer := 0;
  _detail_count integer;
  _should_persist boolean;
  _minute timestamptz;
  _provenance_sha text;
  _result_key_count integer;
  _minute_utc text;
  _required_keys constant text[] := ARRAY[
    ''basis'', ''candidate_cap_reason'', ''candidate_ceiling_minutes'',
    ''candidate_deadline'', ''candidate_floor_minutes'',
    ''candidate_threshold_minutes'', ''confidence'', ''context_key'',
    ''deadline_basis'', ''decision_provenance'', ''effective_silence_minutes'',
    ''evaluated_at'', ''evaluator_version'', ''evidence_cutoff'', ''fallback_path'',
    ''guardian_used_as_activity'', ''neutral_threshold_minutes'',
    ''provenance_sha256'', ''quality_state'', ''replayable'',
    ''selected_source_sha256'', ''sensitivity_buffer_minutes'',
    ''sleep_interval_provenance'', ''subject_context_sha256'',
    ''unclamped_candidate_threshold_minutes'', ''unreplayable_reason'',
    ''version_id'', ''would_alert''
  ];
BEGIN
  IF _version_id IS NULL OR _evaluated_at IS NULL
     OR _max_population IS NULL OR _max_population NOT BETWEEN 1 AND 10000 THEN
    RAISE EXCEPTION ''invalid operational shadow recorder arguments'';
  END IF;
  _minute := date_trunc(''minute'', _evaluated_at AT TIME ZONE ''UTC'')
    AT TIME ZONE ''UTC'';
  _minute_utc := to_char(
    _minute AT TIME ZONE ''UTC'', ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''
  );

  FOR _person_id IN
    WITH population AS (
      SELECT DISTINCT ds.user_id
      FROM public.device_state AS ds
      WHERE EXISTS (
        SELECT 1
        FROM public.group_members AS gm
        WHERE gm.user_id = ds.user_id
          AND gm.status = ''active''
          AND gm.monitored
      )
    )
    SELECT p.user_id
    FROM population AS p
    ORDER BY p.user_id
    LIMIT _max_population
  LOOP
    _population_count := _population_count + 1;
    _result := private.resolve_alert_candidate(_person_id, _minute, _version_id);
    _evaluated_count := _evaluated_count + 1;

    IF _result IS NULL OR jsonb_typeof(_result) <> ''object'' THEN
      RAISE EXCEPTION ''malformed operational shadow result'';
    END IF;
    SELECT count(*)::integer INTO _result_key_count
    FROM jsonb_object_keys(_result);
    IF NOT (_result ?& _required_keys)
       OR _result_key_count <> cardinality(_required_keys)
       OR jsonb_typeof(_result -> ''replayable'') <> ''boolean''
       OR _result ->> ''version_id'' <> _version_id::text
       OR _result ->> ''evaluated_at'' <> _minute_utc
       OR _result ->> ''evidence_cutoff'' <> _minute_utc
       OR _result ->> ''evaluator_version'' <> ''adaptive_candidate_v1''
       OR jsonb_typeof(_result -> ''decision_provenance'') <> ''object''
       OR jsonb_typeof(_result -> ''provenance_sha256'') <> ''string''
       OR jsonb_typeof(_result -> ''guardian_used_as_activity'') <> ''boolean''
       OR (_result ->> ''guardian_used_as_activity'')::boolean THEN
      RAISE EXCEPTION ''malformed operational shadow result'';
    END IF;

    _provenance_sha := encode(
      extensions.digest((_result -> ''decision_provenance'')::text, ''sha256''),
      ''hex''
    );
    IF _result ->> ''provenance_sha256'' <> _provenance_sha THEN
      RAISE EXCEPTION ''operational shadow provenance mismatch'';
    END IF;

    _replayable := (_result ->> ''replayable'')::boolean;
    _reason := _result ->> ''unreplayable_reason'';
    _decision_sha := encode(extensions.digest(jsonb_build_object(
      ''version_id'', _version_id,
      ''user_id'', _person_id,
      ''evaluated_minute'', _minute,
      ''evaluator_result'', _result
    )::text, ''sha256''), ''hex'');

    SELECT s.* INTO _prior
    FROM private.adaptive_alert_shadow_user_state AS s
    WHERE s.version_id = _version_id AND s.user_id = _person_id;

    _should_persist := _replayable AND (
      NOT FOUND
      OR _prior.would_alert IS DISTINCT FROM
        (_result ->> ''would_alert'')::boolean
      OR _prior.basis IS DISTINCT FROM _result ->> ''basis''
      OR _prior.candidate_threshold_minutes IS DISTINCT FROM
        (_result ->> ''candidate_threshold_minutes'')::integer
      OR _prior.quality_state IS DISTINCT FROM _result ->> ''quality_state''
      OR _prior.unreplayable_reason IS DISTINCT FROM _reason
      OR _prior.last_persisted_at IS NULL
      OR _prior.last_persisted_at <= _minute - interval ''1 hour''
    );

    INSERT INTO private.adaptive_alert_shadow_user_state (
      version_id, user_id, evaluated_at, replayable, would_alert, basis,
      candidate_threshold_minutes, quality_state, unreplayable_reason,
      decision_sha256, last_persisted_at, updated_at
    ) VALUES (
      _version_id, _person_id, _minute, _replayable,
      CASE WHEN _replayable THEN (_result ->> ''would_alert'')::boolean END,
      CASE WHEN _replayable THEN _result ->> ''basis'' END,
      CASE WHEN _replayable
        THEN (_result ->> ''candidate_threshold_minutes'')::integer END,
      coalesce(_result ->> ''quality_state'', ''coverage_invalid''),
      CASE WHEN _replayable THEN NULL ELSE _reason END,
      _decision_sha,
      CASE WHEN _should_persist THEN _minute ELSE _prior.last_persisted_at END,
      clock_timestamp()
    )
    ON CONFLICT (version_id, user_id) DO UPDATE SET
      evaluated_at = excluded.evaluated_at,
      replayable = excluded.replayable,
      would_alert = excluded.would_alert,
      basis = excluded.basis,
      candidate_threshold_minutes = excluded.candidate_threshold_minutes,
      quality_state = excluded.quality_state,
      unreplayable_reason = excluded.unreplayable_reason,
      decision_sha256 = excluded.decision_sha256,
      last_persisted_at = excluded.last_persisted_at,
      updated_at = excluded.updated_at;

    IF NOT _replayable THEN
      IF _reason NOT IN (
        ''missing_subject_context'', ''ambiguous_subject_context'',
        ''subject_context_provenance_invalid'', ''missing_qualified_session''
      ) THEN
        RAISE EXCEPTION ''invalid operational shadow unreplayable reason'';
      END IF;
      _unreplayable_count := _unreplayable_count + 1;
      CONTINUE;
    END IF;

    IF _result ->> ''basis'' IS NULL
       OR _result ->> ''candidate_threshold_minutes'' IS NULL
       OR _result ->> ''subject_context_sha256'' IS NULL
       OR jsonb_typeof(_result -> ''fallback_path'') <> ''array'' THEN
      RAISE EXCEPTION ''malformed replayable operational shadow result'';
    END IF;

    IF _should_persist THEN
      SELECT count(*)::integer INTO _detail_count
      FROM public.alert_judgment_shadow_decisions AS d
      WHERE d.version_id = _version_id
        AND d.user_id = _person_id
        AND d.evaluated_at >= date_trunc(''day'', _minute)
        AND d.evaluated_at < date_trunc(''day'', _minute) + interval ''1 day'';
      IF _detail_count >= 36 THEN
        RAISE EXCEPTION ''shadow_detail_budget_exceeded'';
      END IF;

      SELECT array_agg(path.value ORDER BY path.ordinal)
        INTO _fallback_path
      FROM jsonb_array_elements_text(_result -> ''fallback_path'')
        WITH ORDINALITY AS path(value, ordinal);

      INSERT INTO public.alert_judgment_shadow_decisions (
        version_id, user_id, evaluated_at, basis, evaluator_version,
        context_key, neutral_threshold_minutes, sensitivity_buffer_minutes,
        candidate_threshold_minutes, effective_silence_minutes,
        candidate_deadline, would_alert, confidence, quality_state,
        fallback_path, sleep_interval_provenance, provenance_sha256,
        guardian_used_as_activity, evidence_cutoff,
        unclamped_candidate_threshold_minutes, candidate_floor_minutes,
        candidate_ceiling_minutes, candidate_cap_reason, deadline_basis,
        selected_source_sha256, subject_context_sha256,
        decision_provenance, decision_sha256
      ) VALUES (
        _version_id, _person_id, _minute, _result ->> ''basis'',
        _result ->> ''evaluator_version'', _result ->> ''context_key'',
        (_result ->> ''neutral_threshold_minutes'')::integer,
        (_result ->> ''sensitivity_buffer_minutes'')::integer,
        (_result ->> ''candidate_threshold_minutes'')::integer,
        (_result ->> ''effective_silence_minutes'')::double precision,
        (_result ->> ''candidate_deadline'')::timestamptz,
        (_result ->> ''would_alert'')::boolean,
        (_result ->> ''confidence'')::double precision,
        _result ->> ''quality_state'', _fallback_path,
        _result -> ''sleep_interval_provenance'', _provenance_sha, false,
        (_result ->> ''evidence_cutoff'')::timestamptz,
        (_result ->> ''unclamped_candidate_threshold_minutes'')::integer,
        (_result ->> ''candidate_floor_minutes'')::integer,
        (_result ->> ''candidate_ceiling_minutes'')::integer,
        _result ->> ''candidate_cap_reason'',
        _result ->> ''deadline_basis'',
        _result ->> ''selected_source_sha256'',
        _result ->> ''subject_context_sha256'',
        _result -> ''decision_provenance'', _decision_sha
      )
      ON CONFLICT (version_id, user_id, evaluated_minute) DO NOTHING;
      IF FOUND THEN
        _persisted_count := _persisted_count + 1;
      END IF;
    END IF;
    _replayable_count := _replayable_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    ''status'', CASE WHEN _population_count = 0 THEN ''empty'' ELSE ''completed'' END,
    ''population_count'', _population_count,
    ''evaluated_count'', _evaluated_count,
    ''replayable_count'', _replayable_count,
    ''unreplayable_count'', _unreplayable_count,
    ''persisted_count'', _persisted_count
  );
END;
$$;

CREATE OR REPLACE FUNCTION private.run_adaptive_alert_shadow_cycle(
  _version_id uuid,
  _evaluated_at timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET timezone = ''UTC''
AS $$
DECLARE
  _runtime private.adaptive_alert_shadow_runtime_config%ROWTYPE;
  _version public.alert_model_versions%ROWTYPE;
  _minute timestamptz;
  _started_at timestamptz := clock_timestamp();
  _result jsonb;
  _population_count integer;
  _evaluated_count integer;
  _before_dml bigint := 0;
  _after_dml bigint := 0;
  _duration_ms integer;
  _metrics jsonb;
  _run_sha text;
  _person_id uuid;
  _population_total integer;
BEGIN
  SELECT c.* INTO _runtime
  FROM private.adaptive_alert_shadow_runtime_config AS c
  WHERE c.singleton;
  IF _runtime.enabled IS NOT TRUE THEN
    RETURN jsonb_build_object(''status'', ''disabled'');
  END IF;
  IF _runtime.version_id IS DISTINCT FROM _version_id THEN
    RAISE EXCEPTION ''shadow_runtime_version_mismatch'';
  END IF;
  IF _evaluated_at IS NULL THEN
    RAISE EXCEPTION ''shadow_invalid_evaluation_time'';
  END IF;
  _minute := date_trunc(''minute'', _evaluated_at AT TIME ZONE ''UTC'')
    AT TIME ZONE ''UTC'';

  IF EXISTS (
    SELECT 1 FROM private.adaptive_alert_shadow_cycle_runs AS r
    WHERE r.version_id = _version_id AND r.evaluated_minute = _minute
  ) THEN
    RETURN jsonb_build_object(''status'', ''duplicate'');
  END IF;
  IF NOT pg_try_advisory_xact_lock(
    hashtextextended(''adaptive-alert-shadow:'' || _version_id::text, 0)
  ) THEN
    RETURN jsonb_build_object(''status'', ''busy'');
  END IF;

  SELECT v.* INTO _version
  FROM public.alert_model_versions AS v
  WHERE v.id = _version_id;
  IF NOT FOUND OR _version.status <> ''shadow''
     OR _version.shadow_enabled_at IS NULL
     OR _version.shadow_enabled_at > _minute
     OR _version.evidence_version <> ''canonical-v2''
     OR _version.config_sha256 <>
       encode(extensions.digest(_version.config::text, ''sha256''), ''hex'') THEN
    RAISE EXCEPTION ''shadow_version_validation_failed'';
  END IF;
  IF _version.config #>> ''{emergency,expected_live_definition_sha256}''
     <> encode(extensions.digest(pg_get_functiondef(
       ''private.silence_threshold(uuid)''::regprocedure
     ), ''sha256''), ''hex'') THEN
    RAISE EXCEPTION ''shadow_live_hash_mismatch'';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS c
    WHERE c.oid IN (
      ''private.adaptive_alert_shadow_user_state''::regclass,
      ''private.adaptive_alert_shadow_cycle_runs''::regclass,
      ''private.adaptive_alert_shadow_daily_reports''::regclass
    ) AND NOT c.relrowsecurity
  ) OR has_table_privilege(
    ''authenticated'', ''private.adaptive_alert_shadow_user_state'', ''SELECT''
  ) THEN
    RAISE EXCEPTION ''shadow_acl_validation_failed'';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_publication_tables AS p
    WHERE p.tablename LIKE ''adaptive_alert_shadow_%''
      AND p.schemaname IN (''private'', ''public'')
  ) THEN
    RAISE EXCEPTION ''shadow_publication_validation_failed'';
  END IF;

  SELECT count(*)::integer INTO _population_total
  FROM (
    SELECT DISTINCT ds.user_id
    FROM public.device_state AS ds
    WHERE EXISTS (
      SELECT 1
      FROM public.group_members AS gm
      WHERE gm.user_id = ds.user_id
        AND gm.status = ''active''
        AND gm.monitored
    )
  ) AS population;
  IF _population_total > _runtime.max_population THEN
    RAISE EXCEPTION ''shadow_population_budget_exceeded'';
  END IF;

  SELECT coalesce(sum(
    s.n_tup_ins + s.n_tup_upd + s.n_tup_del
  ), 0) INTO _before_dml
  FROM pg_catalog.pg_stat_xact_user_tables AS s
  WHERE s.relid IN (
    ''public.alerts''::regclass,
    ''public.alert_events''::regclass,
    ''public.notifications''::regclass
  );

  IF _runtime.accept_coverage_leases THEN
    FOR _person_id IN
      WITH population AS (
        SELECT DISTINCT ds.user_id
        FROM public.device_state AS ds
        WHERE EXISTS (
          SELECT 1
          FROM public.group_members AS gm
          WHERE gm.user_id = ds.user_id
            AND gm.status = ''active''
            AND gm.monitored
        )
      )
      SELECT p.user_id FROM population AS p
      ORDER BY p.user_id LIMIT _runtime.max_population
    LOOP
      PERFORM private.finalize_alert_shadow_coverage(
        _person_id, _minute, _runtime.detail_retention_days
      );
    END LOOP;
  END IF;

  PERFORM private.capture_alert_shadow_subject_contexts(
    _version_id, _minute, _runtime.max_population
  );
  PERFORM private.capture_alert_shadow_interventions(
    _version_id, _minute, _runtime.max_population
  );
  PERFORM private.maintain_adaptive_alert_shadow(
    _minute, _runtime.max_population
  );
  _result := private.record_alert_judgment_shadow_operational(
    _version_id, _minute, _runtime.max_population
  );

  SELECT coalesce(sum(
    s.n_tup_ins + s.n_tup_upd + s.n_tup_del
  ), 0) INTO _after_dml
  FROM pg_catalog.pg_stat_xact_user_tables AS s
  WHERE s.relid IN (
    ''public.alerts''::regclass,
    ''public.alert_events''::regclass,
    ''public.notifications''::regclass
  );
  IF _after_dml <> _before_dml THEN
    RAISE EXCEPTION ''shadow_live_write_detected'';
  END IF;

  _population_count := (_result ->> ''population_count'')::integer;
  _evaluated_count := (_result ->> ''evaluated_count'')::integer;
  _duration_ms := greatest(
    0, round(extract(epoch FROM (clock_timestamp() - _started_at)) * 1000)::integer
  );
  _metrics := jsonb_build_object(
    ''replayable_count'', (_result ->> ''replayable_count'')::integer,
    ''unreplayable_count'', (_result ->> ''unreplayable_count'')::integer,
    ''persisted_count'', (_result ->> ''persisted_count'')::integer
  );
  _run_sha := encode(extensions.digest(jsonb_build_object(
    ''version_id'', _version_id,
    ''evaluated_minute'', _minute,
    ''population_count'', _population_count,
    ''evaluated_count'', _evaluated_count,
    ''metrics'', _metrics
  )::text, ''sha256''), ''hex'');

  INSERT INTO private.adaptive_alert_shadow_cycle_runs (
    version_id, evaluated_minute, status, duration_ms, population_count,
    evaluated_count, metrics, run_sha256
  ) VALUES (
    _version_id, _minute,
    CASE WHEN _population_count = 0 THEN ''empty'' ELSE ''completed'' END,
    _duration_ms, _population_count, _evaluated_count, _metrics, _run_sha
  );

  RETURN jsonb_build_object(
    ''status'', ''completed'',
    ''population_count'', _population_count,
    ''evaluated_count'', _evaluated_count,
    ''duration_ms'', _duration_ms
  );
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.capture_alert_shadow_subject_contexts(uuid,timestamptz,integer),
  private.record_alert_judgment_shadow_operational(uuid,timestamptz,integer),
  private.run_adaptive_alert_shadow_cycle(uuid,timestamptz)
FROM PUBLIC, anon, authenticated, service_role;
"}', 'scope_adaptive_shadow_population', 'codex-release-v0.5.21', NULL, NULL),
	('20260729110301', '{"-- ADR-0029 P5: surface REAL learning evidence through my_routine_status.
-- Additive, read-only. Does not touch private.silence_threshold and grants the
-- learned pipeline no live alert authority (ADR-0022 remains sole live authority).

CREATE OR REPLACE FUNCTION public.my_routine_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''''
AS $$
DECLARE
  _uid uuid := auth.uid();
  _threshold interval;
  _last_at timestamptz;
  _s text;
  _sleep_start time;
  _sleep_end time;
  _timezone text;
  _in_sleep_window boolean;
  _model_confidence double precision;
  _model_explanation text;
  _model_version text;
  _version_id uuid;
  _learning_active boolean := false;
  _min_support_dates integer;
  _sample_count integer;
  _support_days integer;
  _quality_state text;
  _confidence double precision;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION ''not authenticated''; END IF;

  SELECT sensitivity, sleep_start_local, sleep_end_local, timezone
    INTO _s, _sleep_start, _sleep_end, _timezone
    FROM public.user_settings
   WHERE user_id = _uid;

  SELECT model_confidence, model_explanation, model_version
    INTO _model_confidence, _model_explanation, _model_version
    FROM public.user_activity_profiles
   WHERE user_id = _uid;

  _threshold := private.silence_threshold(_uid);
  _in_sleep_window := private.is_in_sleep_window(_uid, now());

  SELECT max(received_at)
    INTO _last_at
    FROM public.behavior_pings
   WHERE user_id = _uid
     AND ingest_version = 2
     AND abs(extract(epoch from (received_at - at))) <= 300;

  SELECT c.version_id
    INTO _version_id
    FROM private.adaptive_alert_shadow_runtime_config AS c
   WHERE c.singleton
     AND c.enabled
     AND c.version_id IS NOT NULL;

  IF _version_id IS NOT NULL THEN
    SELECT (v.config #>> ''{personal,min_support_dates}'')::integer
      INTO _min_support_dates
      FROM public.alert_model_versions AS v
     WHERE v.id = _version_id
       AND v.status = ''shadow'';

    _learning_active := _min_support_dates IS NOT NULL;

    SELECT gp.sample_count, gp.distinct_support_dates, gp.quality_state, gp.confidence
      INTO _sample_count, _support_days, _quality_state, _confidence
      FROM public.alert_gap_profiles AS gp
     WHERE gp.version_id = _version_id
       AND gp.user_id = _uid
       AND gp.context_key = ''personal_global''
     ORDER BY gp.through_date DESC
     LIMIT 1;
  END IF;

  RETURN jsonb_build_object(
    ''threshold_seconds'', extract(epoch from _threshold)::bigint,
    ''last_behavior_at'', _last_at,
    ''sensitivity'', coalesce(_s, ''balanced''),
    ''sleep_start'', _sleep_start,
    ''sleep_end'', _sleep_end,
    ''timezone'', coalesce(_timezone, ''UTC''),
    ''in_sleep_window'', coalesce(_in_sleep_window, false),
    ''model_confidence'', _model_confidence,
    ''model_explanation'', _model_explanation,
    ''model_version'', _model_version,
    ''learning_active'', _learning_active,
    ''evidence_sample_count'', _sample_count,
    ''evidence_support_days'', _support_days,
    ''evidence_min_support_days'', _min_support_dates,
    ''evidence_quality_state'', _quality_state,
    ''evidence_confidence'', _confidence
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.my_routine_status() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.my_routine_status() TO authenticated;"}', 'routine_status_real_learning_evidence', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260729161625', '{"-- GM Mute: allow GM to temporarily suppress alerts for specific users.
-- Adds gm_mutes table, mute/unmute RPCs, modifies process_escalations + gm_list_clients.

-- 1) gm_mutes table
CREATE TABLE IF NOT EXISTS public.gm_mutes (
  user_id     uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  muted_by    uuid NOT NULL REFERENCES auth.users(id),
  muted_at    timestamptz NOT NULL DEFAULT now(),
  muted_until timestamptz,          -- null = indefinite until manual unmute
  reason      text NOT NULL DEFAULT ''''
);
ALTER TABLE public.gm_mutes ENABLE ROW LEVEL SECURITY;
-- No direct RLS policies — all access via SECURITY DEFINER RPCs.

-- 2) RPC: mute a user (GM-only)
CREATE OR REPLACE FUNCTION public.gm_mute_user(
  _target uuid,
  _until  timestamptz DEFAULT NULL,
  _reason text DEFAULT ''''
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '''' AS $$
BEGIN
  IF NOT private.is_admin(auth.uid()) THEN RAISE EXCEPTION ''forbidden''; END IF;
  INSERT INTO public.gm_mutes (user_id, muted_by, muted_at, muted_until, reason)
  VALUES (_target, auth.uid(), now(), _until, _reason)
  ON CONFLICT (user_id) DO UPDATE
    SET muted_by = auth.uid(), muted_at = now(), muted_until = _until, reason = _reason;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.gm_mute_user(uuid, timestamptz, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gm_mute_user(uuid, timestamptz, text) TO authenticated;

-- 3) RPC: unmute a user (GM-only)
CREATE OR REPLACE FUNCTION public.gm_unmute_user(_target uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '''' AS $$
BEGIN
  IF NOT private.is_admin(auth.uid()) THEN RAISE EXCEPTION ''forbidden''; END IF;
  DELETE FROM public.gm_mutes WHERE user_id = _target;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.gm_unmute_user(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gm_unmute_user(uuid) TO authenticated;

-- 4) Modify process_escalations: skip muted users when raising NEW alerts.
--    Existing open alerts are NOT affected (they continue to escalate normally).
CREATE OR REPLACE FUNCTION public.process_escalations()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''''
AS $function$
DECLARE
  _self_grace CONSTANT interval := interval ''30 minutes'';
  _group_dur  CONSTANT interval := interval ''1 hour'';
  _comm_dur   CONSTANT interval := interval ''2 hours'';
  r record; _aid uuid; _new text; _triggered boolean := false;
BEGIN
  -- First clear open alerts that no longer match current account-level truth.
  FOR r IN
    SELECT a.id, a.user_id, a.cause, ds.last_heartbeat_at, bp.last_at as last_behavior_at
    FROM public.alerts a
    LEFT JOIN public.device_state ds ON ds.user_id = a.user_id
    LEFT JOIN LATERAL (
      SELECT max(received_at) as last_at
      FROM public.behavior_pings
      WHERE user_id = a.user_id
        AND ingest_version = 2
        AND abs(extract(epoch from (received_at - at))) <= 300
        AND received_at >= a.opened_at
        AND at >= a.opened_at
    ) bp ON true
    WHERE a.status = ''open''
      AND a.cause in (''silence'', ''dark_device'')
      AND (
        (
          a.cause = ''silence''
          AND bp.last_at IS NOT NULL
          AND (
            private.is_in_sleep_window(a.user_id, now())
            OR now() - bp.last_at <= private.silence_threshold(a.user_id)
          )
        )
        OR (
          a.cause = ''dark_device''
          AND ds.last_heartbeat_at IS NOT NULL
          AND now() - ds.last_heartbeat_at <= interval ''18 hours''
        )
      )
  LOOP
    UPDATE public.alerts
      SET status = ''resolved'', resolved_at = now(), resolved_by = null, updated_at = now()
      WHERE id = r.id;
    INSERT INTO public.alert_events (alert_id, kind, note)
      VALUES (r.id, ''auto_resolved'', ''condition_cleared'');
    PERFORM private.notify_auto_resolved(r.id, r.user_id);
    _triggered := true;
  END LOOP;

  FOR r IN
    SELECT ds.user_id,
           (now() - ds.last_heartbeat_at) > interval ''18 hours'' as is_dark
    FROM public.device_state ds
    WHERE (
      ds.status = ''alert''
      OR now() - ds.last_heartbeat_at > interval ''18 hours''
      OR (
        NOT private.is_in_sleep_window(ds.user_id, now())
        AND now() - (
          SELECT coalesce(max(received_at), to_timestamp(0))
          FROM public.behavior_pings
          WHERE user_id = ds.user_id
            AND ingest_version = 2
            AND abs(extract(epoch from (received_at - at))) <= 300
        ) > private.silence_threshold(ds.user_id)
      )
    )
      AND exists (SELECT 1 FROM public.group_members gm
                  WHERE gm.user_id = ds.user_id and gm.monitored and gm.status = ''active'')
      AND NOT exists (SELECT 1 FROM public.alerts a WHERE a.user_id = ds.user_id and a.status = ''open'')
      AND NOT exists (
        SELECT 1 FROM public.alerts recent
        WHERE recent.user_id = ds.user_id
          AND recent.status = ''resolved''
          AND recent.cause in (''silence'', ''dark_device'')
          AND recent.resolved_by IS NOT NULL
          AND recent.resolved_by <> recent.user_id
          AND recent.resolved_at > now() - _self_grace
      )
      -- GM Mute: skip users who are currently muted
      AND NOT exists (
        SELECT 1 FROM public.gm_mutes m
        WHERE m.user_id = ds.user_id
          AND (m.muted_until IS NULL OR m.muted_until > now())
      )
  LOOP
    INSERT INTO public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    VALUES (r.user_id, CASE WHEN r.is_dark THEN ''dark_device'' ELSE ''silence'' end,
            ''self'', now(), now() + _self_grace)
    RETURNING id INTO _aid;
    INSERT INTO public.alert_events (alert_id, kind) values (_aid, ''raised'');
    PERFORM private.notify_stage(_aid, r.user_id, ''self'');
    _triggered := true;
  END LOOP;

  FOR r IN
    SELECT * FROM public.alerts
    WHERE status = ''open''
      AND next_deadline IS NOT NULL AND next_deadline <= now()
      AND coalesce(paused_until, to_timestamp(0)) <= now()
  LOOP
    _new := CASE r.stage
              WHEN ''self'' THEN ''group''
              WHEN ''group'' THEN ''community''
              WHEN ''community'' THEN ''terminal''
              ELSE ''terminal'' end;
    UPDATE public.alerts
      SET stage = _new, stage_entered_at = now(), paused_until = null, paused_by = null, updated_at = now(),
          next_deadline = CASE _new WHEN ''group'' THEN now() + _group_dur
                                    WHEN ''community'' THEN now() + _comm_dur
                                    ELSE null end
      WHERE id = r.id;
    INSERT INTO public.alert_events (alert_id, kind, note) VALUES (r.id, ''escalated'', _new);
    PERFORM private.notify_stage(r.id, r.user_id, _new);
    _triggered := true;
  END LOOP;

  IF _triggered THEN
    PERFORM private.trigger_push_dispatch();
  END IF;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.process_escalations() FROM public, anon, authenticated;

-- 5) Modify gm_list_clients: expose muted_until field
CREATE OR REPLACE FUNCTION public.gm_list_clients()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '''' AS $$
DECLARE _uid uuid := auth.uid();
BEGIN
  IF NOT private.is_admin(_uid) THEN RAISE EXCEPTION ''forbidden''; END IF;
  RETURN coalesce((
    SELECT jsonb_agg(obj ORDER BY nm asc, ls desc nulls last)
    FROM (
      SELECT jsonb_build_object(
        ''user_id'', p.id,
        ''name'', coalesce(nullif(p.display_name,''''), left(p.id::text,8)),
        ''platform'', c.platform,
        ''app_version'', c.app_version,
        ''first_seen_at'', c.first_seen_at,
        ''last_seen_at'', c.last_seen_at,
        ''last_heartbeat_at'', ds.last_heartbeat_at,
        ''last_behavior_at'', bp.last_at,
        ''alerted'', exists (
          SELECT 1 FROM public.alerts a
          WHERE a.user_id = p.id and a.status = ''open''
            AND a.stage in (''group'',''community'',''terminal'')
        ),
        ''status'',
          CASE
            WHEN exists (
              SELECT 1 FROM public.alerts a
              WHERE a.user_id = p.id and a.status = ''open''
                AND a.stage in (''group'',''community'',''terminal'')
            ) THEN ''alert''
            WHEN bp.last_at IS NULL THEN ''never''
            WHEN bp.last_at > now() - interval ''6 hours'' THEN ''active''
            WHEN bp.last_at > now() - interval ''24 hours'' THEN ''quiet''
            ELSE ''silent''
          END,
        ''muted_until'',
          CASE
            WHEN mu.user_id IS NOT NULL
              AND (mu.muted_until IS NULL OR mu.muted_until > now())
            THEN coalesce(mu.muted_until::text, ''indefinite'')
            ELSE null
          END
      ) as obj,
      coalesce(nullif(p.display_name,''''), left(p.id::text,8)) as nm,
      c.last_seen_at as ls
      FROM public.profiles p
      LEFT JOIN public.clients c ON c.user_id = p.id
      LEFT JOIN public.device_state ds ON ds.user_id = p.id
      LEFT JOIN LATERAL (
        SELECT max(received_at) as last_at
        FROM public.behavior_pings
        WHERE user_id = p.id
          AND ingest_version = 2
          AND abs(extract(epoch from (received_at - at))) <= 300
      ) bp ON true
      LEFT JOIN public.gm_mutes mu ON mu.user_id = p.id
    ) s
  ), ''[]''::jsonb);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.gm_list_clients() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gm_list_clients() TO authenticated;

"}', 'gm_mute_user', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260729163120', '{"-- ADR-0028 compatibility repair: pg_get_functiondef() preserves the line
-- endings stored in prosrc. Windows replay therefore pinned the CRLF byte
-- representation while production stores the same function body with LF.
-- Treat only those two known representations as equivalent; all other live
-- definitions remain fail-closed.

CREATE FUNCTION private.shadow_live_definition_matches(
  _expected_sha256 text,
  _actual_definition text
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''''
AS $$
  WITH hashes AS (
    SELECT
      encode(
        extensions.digest(_actual_definition, ''sha256''),
        ''hex''
      ) AS raw_sha256,
      encode(
        extensions.digest(
          replace(_actual_definition, E''\\r\\n'', E''\\n''),
          ''sha256''
        ),
        ''hex''
      ) AS lf_sha256
  )
  SELECT CASE
    WHEN _expected_sha256 !~ ''^[a-f0-9]{64}$''
      OR _actual_definition IS NULL
      THEN false
    ELSE
      _expected_sha256 IN (hashes.raw_sha256, hashes.lf_sha256)
      OR (
        _expected_sha256 =
          ''1907d59473d274d46a0e8e0b9ce8027037b4494b0dddf073cb46abf67db92e21''
        AND hashes.lf_sha256 =
          ''686116ef8f2df1d78f6d0d48ded8019555f283b098eeb5d354cfa1c14ebbcdca''
      )
  END
  FROM hashes
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.shadow_live_definition_matches(text,text)
FROM PUBLIC, anon, authenticated, service_role;

DO $$
DECLARE
  _definition text := replace(
    pg_get_functiondef(
      ''private.run_adaptive_alert_shadow_cycle(uuid,timestamptz)''::regprocedure
    ),
    E''\\r\\n'',
    E''\\n''
  );
  _before text := replace(
    $fragment$
  IF _version.config #>> ''{emergency,expected_live_definition_sha256}''
     <> encode(extensions.digest(pg_get_functiondef(
       ''private.silence_threshold(uuid)''::regprocedure
     ), ''sha256''), ''hex'') THEN
    RAISE EXCEPTION ''shadow_live_hash_mismatch'';
  END IF;
$fragment$,
    E''\\r\\n'',
    E''\\n''
  );
  _after text := replace(
    $fragment$
  IF NOT private.shadow_live_definition_matches(
    _version.config #>> ''{emergency,expected_live_definition_sha256}'',
    pg_get_functiondef(''private.silence_threshold(uuid)''::regprocedure)
  ) THEN
    RAISE EXCEPTION ''shadow_live_hash_mismatch'';
  END IF;
$fragment$,
    E''\\r\\n'',
    E''\\n''
  );
BEGIN
  IF _definition IS NULL
     OR length(_definition) - length(replace(_definition, _before, ''''))
        <> length(_before) THEN
    RAISE EXCEPTION ''shadow_live_hash_patch_source_mismatch'';
  END IF;

  EXECUTE replace(_definition, _before, _after);
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.run_adaptive_alert_shadow_cycle(uuid,timestamptz)
FROM PUBLIC, anon, authenticated, service_role;

"}', 'canonicalize_shadow_live_hash', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260729163157', '{"-- ADR-0029 P3: preserve every distinct validated behavior event.
--
-- event_id remains the idempotency key. The former user/source/five-minute
-- observation-bucket merge reduced write volume but discarded valid evidence
-- and gave v1/v2 different sampling units. Client collectors own emission-rate
-- control; the shared validator continues to own safety and provenance checks.

CREATE OR REPLACE FUNCTION private.insert_behavior_ping(
  _user_id uuid,
  _event_id uuid,
  _observed_at timestamptz,
  _source text,
  _kind text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''''
AS $$
DECLARE
  _received_at timestamptz := clock_timestamp();
  _is_live_safety boolean;
BEGIN
  IF _user_id IS NULL OR _observed_at IS NULL OR _event_id IS NULL THEN
    RETURN ''invalid'';
  END IF;

  IF _source NOT IN (
    ''installed_pwa'',
    ''tauri'',
    ''capacitor'',
    ''shortcut'',
    ''manual'',
    ''app''
  ) THEN
    RETURN ''invalid'';
  END IF;

  IF _kind NOT IN (
    ''app'',
    ''interaction'',
    ''steps'',
    ''unlock'',
    ''manual_checkin''
  ) THEN
    RETURN ''invalid'';
  END IF;

  IF _observed_at > _received_at + interval ''5 minutes'' THEN
    RETURN ''invalid'';
  END IF;

  -- Serialize retries for one event before inspecting the idempotency index.
  -- Distinct events intentionally do not serialize by time bucket.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      _user_id::text || '':event:'' || _event_id::text,
      0
    )
  );

  IF EXISTS (
    SELECT 1
    FROM public.behavior_pings
    WHERE user_id = _user_id
      AND event_id = _event_id
  ) THEN
    RETURN ''duplicate'';
  END IF;

  _is_live_safety := (
    abs(extract(epoch FROM (_received_at - _observed_at))) <= 300
  );

  BEGIN
    INSERT INTO public.behavior_pings (
      user_id,
      event_id,
      at,
      source,
      kind,
      received_at,
      ingest_version
    )
    VALUES (
      _user_id,
      _event_id,
      _observed_at,
      _source,
      _kind,
      _received_at,
      2
    );
  EXCEPTION WHEN unique_violation THEN
    IF EXISTS (
      SELECT 1
      FROM public.behavior_pings
      WHERE user_id = _user_id
        AND event_id = _event_id
    ) THEN
      RETURN ''duplicate'';
    END IF;
    RAISE;
  END;

  IF _is_live_safety THEN
    PERFORM private.apply_liveness_side_effects(
      _user_id,
      _observed_at,
      _received_at
    );
  END IF;

  RETURN ''inserted'';
END;
$$;

REVOKE EXECUTE ON FUNCTION private.insert_behavior_ping(
  uuid,
  uuid,
  timestamptz,
  text,
  text
) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION private.insert_behavior_ping(
  uuid,
  uuid,
  timestamptz,
  text,
  text
) IS
  ''ADR-0029 P3 shared validator: one row per distinct event_id; no time-bucket coalescing.'';

"}', 'remove_behavior_ping_coalescing', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260729163209', '{"-- ADR-0029 P1: admit legacy ingest-version 1 history to shadow/replay
-- profile training through an explicit, auditable sessionized evidence source.
-- Historical rows remain training-only: no trigger, scheduler, source rewrite,
-- realtime side effect, alert resolution, or heartbeat mutation is introduced.

ALTER TABLE public.alert_model_versions
  ADD CONSTRAINT alert_model_versions_historical_v1_policy_check CHECK (
    (
      config #> ''{sessionization,historical_v1_policy}'' IS NULL
      OR (
        jsonb_typeof(
          config #> ''{sessionization,historical_v1_policy}''
        ) = ''string''
        AND config #>> ''{sessionization,historical_v1_policy}'' IN (
          ''disabled'',
          ''sessionized_training_only_v1''
        )
      )
    ) IS TRUE
  );

CREATE FUNCTION private.normalized_behavior_training_sessions(
  _user_id uuid,
  _from timestamptz,
  _to timestamptz,
  _version_id uuid
)
RETURNS TABLE (
  session_start timestamptz,
  session_end timestamptz,
  context_key text,
  evidence_count integer,
  source_ingest_version smallint,
  training_provenance text,
  provenance_sha256 text,
  quality_state text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''''
SET TimeZone = ''UTC''
AS $$
DECLARE
  _config jsonb;
  _status text;
  _evidence_version text;
  _config_sha256 text;
  _gap_minutes integer;
  _historical_v1_policy text;
BEGIN
  IF _user_id IS NULL
     OR _version_id IS NULL
     OR _from IS NULL
     OR _to IS NULL
     OR _from >= _to THEN
    RETURN;
  END IF;

  SELECT config, status, evidence_version, config_sha256
    INTO _config, _status, _evidence_version, _config_sha256
  FROM public.alert_model_versions
  WHERE id = _version_id;

  IF NOT FOUND
     OR _status NOT IN (''replay'', ''shadow'')
     OR _evidence_version <> ''canonical-v2''
     OR _config_sha256
       <> encode(extensions.digest(_config::text, ''sha256''), ''hex'') THEN
    RETURN;
  END IF;

  BEGIN
    _gap_minutes :=
      (_config #>> ''{sessionization,gap_minutes}'')::integer;
    _historical_v1_policy := coalesce(
      _config #>> ''{sessionization,historical_v1_policy}'',
      ''disabled''
    );
  EXCEPTION
    WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      RETURN;
  END;

  IF _gap_minutes <= 0
     OR _historical_v1_policy NOT IN (
       ''disabled'',
       ''sessionized_training_only_v1''
     ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH canonical AS (
    SELECT
      s.session_start,
      s.session_end,
      s.context_key,
      s.evidence_count,
      2::smallint AS source_ingest_version,
      ''canonical_v2''::text AS training_provenance,
      encode(
        extensions.digest(
          jsonb_build_object(
            ''version_id'', _version_id,
            ''config_sha256'', _config_sha256,
            ''source_ingest_version'', 2,
            ''training_provenance'', ''canonical_v2'',
            ''session_start_utc'',
              to_char(
                s.session_start AT TIME ZONE ''UTC'',
                ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''
              ),
            ''session_end_utc'',
              to_char(
                s.session_end AT TIME ZONE ''UTC'',
                ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''
              ),
            ''context_key'', s.context_key,
            ''evidence_count'', s.evidence_count,
            ''quality_state'', s.quality_state
          )::text,
          ''sha256''
        ),
        ''hex''
      ) AS provenance_sha256,
      s.quality_state
    FROM private.qualified_behavior_sessions(
      _user_id,
      _from,
      _to,
      _version_id
    ) AS s
  ),
  historical_admitted AS (
    SELECT
      p.id,
      p.at,
      p.kind,
      p.source,
      p.received_at,
      p.event_id,
      p.ingest_version
    FROM public.behavior_pings AS p
    WHERE _historical_v1_policy = ''sessionized_training_only_v1''
      AND p.user_id = _user_id
      AND p.ingest_version = 1
      AND p.at >= _from
      AND p.at < _to
  ),
  historical_marked AS (
    SELECT
      a.*,
      CASE
        WHEN lag(a.at) OVER (ORDER BY a.at, a.id) IS NULL
          OR a.at - lag(a.at) OVER (ORDER BY a.at, a.id)
            > make_interval(mins => _gap_minutes)
          THEN 1
        ELSE 0
      END AS starts_session
    FROM historical_admitted AS a
  ),
  historical_grouped AS (
    SELECT
      m.*,
      sum(m.starts_session) OVER (ORDER BY m.at, m.id) AS session_no
    FROM historical_marked AS m
  ),
  historical_summarized AS (
    SELECT
      min(g.at) AS session_start,
      max(g.at) AS session_end,
      count(*)::integer AS evidence_count,
      jsonb_agg(
        jsonb_build_object(
          ''id'', g.id,
          ''at_utc'',
            to_char(
              g.at AT TIME ZONE ''UTC'',
              ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''
            ),
          ''kind'', g.kind,
          ''source'', g.source,
          ''received_at_utc'',
            to_char(
              g.received_at AT TIME ZONE ''UTC'',
              ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''
            ),
          ''event_id'', g.event_id,
          ''ingest_version'', g.ingest_version
        )
        ORDER BY g.at, g.id
      ) AS source_rows
    FROM historical_grouped AS g
    GROUP BY g.session_no
  ),
  historical AS (
    SELECT
      s.session_start,
      s.session_end,
      NULL::text AS context_key,
      s.evidence_count,
      1::smallint AS source_ingest_version,
      ''historical_v1_training_only''::text AS training_provenance,
      encode(
        extensions.digest(
          jsonb_build_object(
            ''version_id'', _version_id,
            ''config_sha256'', _config_sha256,
            ''source_ingest_version'', 1,
            ''training_provenance'', ''historical_v1_training_only'',
            ''source_rows'', s.source_rows
          )::text,
          ''sha256''
        ),
        ''hex''
      ) AS provenance_sha256,
      ''valid''::text AS quality_state
    FROM historical_summarized AS s
  )
  SELECT * FROM canonical
  UNION ALL
  SELECT * FROM historical
  ORDER BY session_start, source_ingest_version;
END;
$$;

CREATE OR REPLACE FUNCTION private.rebuild_alert_gap_profiles(
  _version_id uuid,
  _through_date date
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET TimeZone = ''UTC''
AS $$
DECLARE
  _config jsonb;
  _status text;
  _evidence_version text;
  _config_sha256 text;
  _historical_v1_policy text;
  _horizon_days integer;
  _daily_cap integer;
  _min_samples integer;
  _min_dates integer;
  _min_span integer;
  _max_age integer;
  _cutoff timestamptz;
  _from timestamptz;
  _profiles_written integer := 0;
  _profiles_deleted integer := 0;
  _completed_gaps integer := 0;
BEGIN
  IF _version_id IS NULL OR _through_date IS NULL THEN
    RETURN jsonb_build_object(
      ''profiles_written'', 0,
      ''profiles_deleted'', 0,
      ''completed_gaps'', 0,
      ''explicit_quiet_minutes'', 0
    );
  END IF;

  SELECT config, status, evidence_version, config_sha256
    INTO _config, _status, _evidence_version, _config_sha256
  FROM public.alert_model_versions
  WHERE id = _version_id;

  IF NOT FOUND
     OR _status NOT IN (''replay'', ''shadow'')
     OR _evidence_version <> ''canonical-v2''
     OR _config_sha256
       <> encode(extensions.digest(_config::text, ''sha256''), ''hex'') THEN
    RETURN jsonb_build_object(
      ''profiles_written'', 0,
      ''profiles_deleted'', 0,
      ''completed_gaps'', 0,
      ''explicit_quiet_minutes'', 0
    );
  END IF;

  BEGIN
    _historical_v1_policy := coalesce(
      _config #>> ''{sessionization,historical_v1_policy}'',
      ''disabled''
    );
    _horizon_days :=
      (_config #>> ''{sessionization,training_horizon_days}'')::integer;
    _daily_cap :=
      (_config #>> ''{sessionization,per_user_day_gap_cap}'')::integer;
    _min_samples := (_config #>> ''{personal,min_samples}'')::integer;
    _min_dates := (_config #>> ''{personal,min_support_dates}'')::integer;
    _min_span := (_config #>> ''{personal,min_span_days}'')::integer;
    _max_age := (_config #>> ''{personal,max_age_days}'')::integer;
  EXCEPTION
    WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      RETURN jsonb_build_object(
        ''profiles_written'', 0,
        ''profiles_deleted'', 0,
        ''completed_gaps'', 0,
        ''explicit_quiet_minutes'', 0
      );
  END;

  IF _historical_v1_policy NOT IN (
       ''disabled'',
       ''sessionized_training_only_v1''
     )
     OR _horizon_days <= 0
     OR _daily_cap <= 0
     OR _min_samples <= 0
     OR _min_dates <= 0
     OR _min_span <= 0
     OR _max_age <= 0 THEN
    RETURN jsonb_build_object(
      ''profiles_written'', 0,
      ''profiles_deleted'', 0,
      ''completed_gaps'', 0,
      ''explicit_quiet_minutes'', 0
    );
  END IF;

  _cutoff := ((_through_date + 1)::timestamp AT TIME ZONE ''UTC'');
  _from := _cutoff - make_interval(days => _horizon_days);

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      _version_id::text || '':'' || _through_date::text,
      0
    )
  );

  DROP TABLE IF EXISTS pg_temp._alert_gap_profile_build;

  CREATE TEMP TABLE _alert_gap_profile_build ON COMMIT DROP AS
  WITH users AS (
    SELECT DISTINCT c.user_id
    FROM public.alert_observation_coverage_intervals AS c
    WHERE c.version_id = _version_id
      AND c.starts_at < _cutoff
      AND c.ends_at > _from
    UNION
    SELECT DISTINCT p.user_id
    FROM public.behavior_pings AS p
    WHERE _historical_v1_policy = ''sessionized_training_only_v1''
      AND p.ingest_version = 1
      AND p.at >= _from
      AND p.at < _cutoff
  ),
  sessions AS (
    SELECT
      u.user_id,
      s.*
    FROM users AS u
    CROSS JOIN LATERAL private.normalized_behavior_training_sessions(
      u.user_id,
      _from,
      _cutoff,
      _version_id
    ) AS s
  ),
  paired AS (
    SELECT
      s.*,
      lead(s.session_start) OVER (
        PARTITION BY
          s.user_id,
          s.source_ingest_version,
          s.training_provenance
        ORDER BY s.session_start
      ) AS next_start,
      lead(s.quality_state) OVER (
        PARTITION BY
          s.user_id,
          s.source_ingest_version,
          s.training_provenance
        ORDER BY s.session_start
      ) AS next_quality,
      lead(s.provenance_sha256) OVER (
        PARTITION BY
          s.user_id,
          s.source_ingest_version,
          s.training_provenance
        ORDER BY s.session_start
      ) AS next_session_provenance_sha256
    FROM sessions AS s
  ),
  coverage_gaps AS (
    SELECT
      p.user_id,
      p.session_end,
      p.next_start,
      p.context_key,
      c.id AS coverage_id,
      c.timezone,
      c.utc_offset_minutes,
      c.provenance_sha256 AS coverage_provenance_sha256,
      p.source_ingest_version,
      p.training_provenance,
      p.provenance_sha256 AS session_provenance_sha256,
      p.next_session_provenance_sha256
    FROM paired AS p
    JOIN public.alert_observation_coverage_intervals AS c
      ON c.version_id = _version_id
     AND c.user_id = p.user_id
     AND c.starts_at <= p.session_end
     AND c.ends_at >= p.next_start
     AND c.activity_coverage_state = ''valid''
     AND c.intervention_coverage_state = ''valid''
     AND c.sleep_context_state = ''valid''
     AND c.evidence_version = ''canonical-v2''
     AND c.finalized_at IS NOT NULL
     AND c.finalized_at >= c.ends_at
     AND c.finalized_at < _cutoff
    CROSS JOIN LATERAL (
      SELECT count(*) AS matching_coverage
      FROM public.alert_observation_coverage_intervals AS cc
      WHERE cc.version_id = _version_id
        AND cc.user_id = p.user_id
        AND cc.starts_at <= p.session_end
        AND cc.ends_at >= p.next_start
        AND cc.activity_coverage_state = ''valid''
        AND cc.intervention_coverage_state = ''valid''
        AND cc.sleep_context_state = ''valid''
        AND cc.evidence_version = ''canonical-v2''
        AND cc.finalized_at IS NOT NULL
        AND cc.finalized_at >= cc.ends_at
        AND cc.finalized_at < _cutoff
    ) AS coverage_count
    WHERE p.source_ingest_version = 2
      AND p.next_start IS NOT NULL
      AND p.quality_state = ''valid''
      AND p.next_quality = ''valid''
      AND coverage_count.matching_coverage = 1
      AND EXISTS (
        SELECT 1
        FROM pg_catalog.pg_timezone_names z
        WHERE z.name = c.timezone
      )
      AND floor(
        extract(
          epoch FROM (
            (
              (p.session_end AT TIME ZONE c.timezone)
              AT TIME ZONE ''UTC''
            ) - p.session_end
          )
        ) / 60
      )::integer = c.utc_offset_minutes
      AND NOT EXISTS (
        SELECT 1
        FROM public.alert_intervention_events AS i
        WHERE i.version_id = _version_id
          AND i.user_id = p.user_id
          AND i.evidence_version = ''canonical-v2''
          AND i.occurred_at >= p.session_end
          AND i.occurred_at < p.next_start
          AND i.captured_at < _cutoff
      )
  ),
  canonical_effective AS (
    SELECT
      g.*,
      greatest(
        0::numeric,
        extract(epoch FROM (g.next_start - g.session_end))
          - coalesce(sleep.sleep_seconds, 0)
      )::double precision AS effective_seconds,
      sleep.sleep_provenance_sha256
    FROM coverage_gaps AS g
    CROSS JOIN LATERAL (
      WITH raw_sleep AS (
        SELECT
          si.starts_at,
          si.ends_at,
          si.basis,
          si.confidence,
          si.provenance,
          tstzrange(
            greatest(si.starts_at, g.session_end),
            least(si.ends_at, g.next_start),
            ''[)''
          ) AS clipped_range
        FROM private.candidate_sleep_intervals(
          g.user_id,
          g.session_end,
          g.next_start,
          _version_id
        ) AS si
        WHERE si.starts_at < g.next_start
          AND si.ends_at > g.session_end
      ),
      merged AS (
        SELECT unnest(range_agg(clipped_range)) AS r
        FROM raw_sleep
      )
      SELECT
        coalesce(
          (
            SELECT sum(extract(epoch FROM (upper(r) - lower(r))))
            FROM merged
          ),
          0
        )::double precision AS sleep_seconds,
        encode(
          extensions.digest(
            coalesce(
              (
                SELECT jsonb_agg(
                  jsonb_build_object(
                    ''starts_at_utc'',
                      to_char(
                        starts_at AT TIME ZONE ''UTC'',
                        ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''
                      ),
                    ''ends_at_utc'',
                      to_char(
                        ends_at AT TIME ZONE ''UTC'',
                        ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''
                      ),
                    ''basis'', basis,
                    ''confidence'', confidence,
                    ''provenance'', provenance
                  )
                  ORDER BY
                    starts_at,
                    ends_at,
                    basis,
                    confidence,
                    provenance::text
                )
                FROM raw_sleep
              ),
              ''[]''::jsonb
            )::text,
            ''sha256''
          ),
          ''hex''
        ) AS sleep_provenance_sha256
    ) AS sleep
  ),
  historical_effective AS (
    SELECT
      p.user_id,
      p.session_end,
      p.next_start,
      p.context_key,
      NULL::uuid AS coverage_id,
      ''UTC''::text AS timezone,
      0::integer AS utc_offset_minutes,
      NULL::text AS coverage_provenance_sha256,
      p.source_ingest_version,
      p.training_provenance,
      p.provenance_sha256 AS session_provenance_sha256,
      p.next_session_provenance_sha256,
      extract(
        epoch FROM (p.next_start - p.session_end)
      )::double precision AS effective_seconds,
      NULL::text AS sleep_provenance_sha256
    FROM paired AS p
    WHERE p.source_ingest_version = 1
      AND p.training_provenance = ''historical_v1_training_only''
      AND p.next_start IS NOT NULL
      AND p.quality_state = ''valid''
      AND p.next_quality = ''valid''
  ),
  effective AS (
    SELECT * FROM canonical_effective
    UNION ALL
    SELECT * FROM historical_effective
  ),
  capped AS (
    SELECT
      e.*,
      (e.next_start AT TIME ZONE e.timezone)::date AS local_date,
      row_number() OVER (
        PARTITION BY
          e.user_id,
          (e.next_start AT TIME ZONE e.timezone)::date
        ORDER BY md5(
          _version_id::text || '':'' || e.user_id::text || '':''
          || to_char(
            e.session_end AT TIME ZONE ''UTC'',
            ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''
          ) || '':''
          || to_char(
            e.next_start AT TIME ZONE ''UTC'',
            ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''
          )
        )
      ) AS daily_rank
    FROM effective AS e
    WHERE e.effective_seconds > 0
  ),
  selected AS (
    SELECT *
    FROM capped
    WHERE daily_rank <= _daily_cap
  ),
  grouped AS (
    SELECT
      user_id,
      ''personal_global''::text AS context_key,
      session_end,
      next_start,
      local_date,
      effective_seconds,
      coverage_id,
      timezone,
      utc_offset_minutes,
      coverage_provenance_sha256,
      sleep_provenance_sha256,
      source_ingest_version,
      training_provenance,
      session_provenance_sha256,
      next_session_provenance_sha256
    FROM selected
    UNION ALL
    SELECT
      user_id,
      context_key,
      session_end,
      next_start,
      local_date,
      effective_seconds,
      coverage_id,
      timezone,
      utc_offset_minutes,
      coverage_provenance_sha256,
      sleep_provenance_sha256,
      source_ingest_version,
      training_provenance,
      session_provenance_sha256,
      next_session_provenance_sha256
    FROM selected
    WHERE context_key IS NOT NULL
  ),
  aggregate_inputs AS (
    SELECT
      user_id,
      context_key,
      count(*)::integer AS sample_count,
      count(DISTINCT local_date)::integer AS distinct_support_dates,
      min(local_date) AS support_started_on,
      max(local_date) AS support_ended_on,
      max(next_start) AS latest_evidence_at,
      ceil(
        percentile_disc(0.95)
          WITHIN GROUP (ORDER BY effective_seconds) / 60.0
      )::integer AS neutral_p95_minutes,
      jsonb_agg(
        jsonb_build_object(
          ''session_end_utc'',
            to_char(
              session_end AT TIME ZONE ''UTC'',
              ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''
            ),
          ''next_start_utc'',
            to_char(
              next_start AT TIME ZONE ''UTC'',
              ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''
            ),
          ''local_date'', local_date,
          ''effective_seconds'', effective_seconds,
          ''coverage_id'', coverage_id,
          ''coverage_timezone'', timezone,
          ''coverage_utc_offset_minutes'', utc_offset_minutes,
          ''coverage_provenance_sha256'', coverage_provenance_sha256,
          ''sleep_provenance_sha256'', sleep_provenance_sha256,
          ''source_ingest_version'', source_ingest_version,
          ''training_provenance'', training_provenance,
          ''session_provenance_sha256'', session_provenance_sha256,
          ''next_session_provenance_sha256'',
            next_session_provenance_sha256
        )
        ORDER BY
          session_end,
          next_start,
          source_ingest_version,
          session_provenance_sha256
      ) AS gap_inputs
    FROM grouped
    GROUP BY user_id, context_key
  ),
  hashes AS (
    SELECT
      a.*,
      encode(
        extensions.digest(
          jsonb_build_object(
            ''version_id'', _version_id,
            ''through_date'', _through_date,
            ''config_sha256'', _config_sha256,
            ''evidence_version'', _evidence_version,
            ''context_key'', context_key,
            ''gaps'', gap_inputs
          )::text,
          ''sha256''
        ),
        ''hex''
      ) AS input_sha256
    FROM aggregate_inputs AS a
  ),
  prepared AS (
    SELECT
      h.*,
      CASE
        WHEN h.latest_evidence_at
          < _cutoff - make_interval(days => _max_age)
          THEN ''stale''
        WHEN h.sample_count >= _min_samples
          AND h.distinct_support_dates >= _min_dates
          AND (
            h.support_ended_on - h.support_started_on + 1
          ) >= _min_span
          THEN ''valid''
        ELSE ''low_support''
      END::text AS quality_state,
      CASE
        WHEN h.latest_evidence_at
          < _cutoff - make_interval(days => _max_age)
          THEN 0::double precision
        ELSE least(
          1::double precision,
          h.sample_count::double precision
            / _min_samples::double precision,
          h.distinct_support_dates::double precision
            / _min_dates::double precision,
          (h.support_ended_on - h.support_started_on + 1)::double precision
            / _min_span::double precision
        )
      END AS confidence
    FROM hashes AS h
  )
  SELECT
    p.user_id,
    p.context_key,
    _through_date AS through_date,
    p.neutral_p95_minutes,
    p.sample_count,
    p.distinct_support_dates,
    p.support_started_on,
    p.support_ended_on,
    p.latest_evidence_at,
    p.quality_state,
    p.confidence,
    p.input_sha256,
    encode(
      extensions.digest(
        jsonb_build_object(
          ''version_id'', _version_id,
          ''user_id'', p.user_id,
          ''context_key'', p.context_key,
          ''through_date'', _through_date,
          ''neutral_p95_minutes'', p.neutral_p95_minutes,
          ''sample_count'', p.sample_count,
          ''distinct_support_dates'', p.distinct_support_dates,
          ''support_started_on'', p.support_started_on,
          ''support_ended_on'', p.support_ended_on,
          ''latest_evidence_at_utc'',
            to_char(
              p.latest_evidence_at AT TIME ZONE ''UTC'',
              ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''
            ),
          ''quality_state'', p.quality_state,
          ''confidence'', p.confidence,
          ''input_sha256'', p.input_sha256
        )::text,
        ''sha256''
      ),
      ''hex''
    ) AS profile_sha256
  FROM prepared AS p;

  SELECT coalesce(
    sum(sample_count) FILTER (WHERE context_key = ''personal_global''),
    0
  )::integer
    INTO _completed_gaps
  FROM pg_temp._alert_gap_profile_build;

  INSERT INTO public.alert_gap_profiles AS target (
    version_id,
    user_id,
    context_key,
    through_date,
    neutral_p95_minutes,
    sample_count,
    distinct_support_dates,
    support_started_on,
    support_ended_on,
    latest_evidence_at,
    quality_state,
    confidence,
    profile_sha256,
    input_sha256
  )
  SELECT
    _version_id,
    user_id,
    context_key,
    through_date,
    neutral_p95_minutes,
    sample_count,
    distinct_support_dates,
    support_started_on,
    support_ended_on,
    latest_evidence_at,
    quality_state,
    confidence,
    profile_sha256,
    input_sha256
  FROM pg_temp._alert_gap_profile_build
  ON CONFLICT (
    version_id,
    user_id,
    context_key,
    through_date
  ) DO UPDATE
  SET
    neutral_p95_minutes = EXCLUDED.neutral_p95_minutes,
    sample_count = EXCLUDED.sample_count,
    distinct_support_dates = EXCLUDED.distinct_support_dates,
    support_started_on = EXCLUDED.support_started_on,
    support_ended_on = EXCLUDED.support_ended_on,
    latest_evidence_at = EXCLUDED.latest_evidence_at,
    quality_state = EXCLUDED.quality_state,
    confidence = EXCLUDED.confidence,
    profile_sha256 = EXCLUDED.profile_sha256,
    input_sha256 = EXCLUDED.input_sha256,
    computed_at = clock_timestamp()
  WHERE target.input_sha256 IS DISTINCT FROM EXCLUDED.input_sha256
     OR target.profile_sha256 IS DISTINCT FROM EXCLUDED.profile_sha256;

  GET DIAGNOSTICS _profiles_written = ROW_COUNT;

  DELETE FROM public.alert_gap_profiles AS target
  WHERE target.version_id = _version_id
    AND target.through_date = _through_date
    AND NOT EXISTS (
      SELECT 1
      FROM pg_temp._alert_gap_profile_build AS b
      WHERE b.user_id = target.user_id
        AND b.context_key = target.context_key
    );

  GET DIAGNOSTICS _profiles_deleted = ROW_COUNT;

  RETURN jsonb_build_object(
    ''profiles_written'', _profiles_written,
    ''profiles_deleted'', _profiles_deleted,
    ''completed_gaps'', _completed_gaps,
    ''explicit_quiet_minutes'', 0
  );
END;
$$;

REVOKE ALL ON FUNCTION private.normalized_behavior_training_sessions(
  uuid,
  timestamptz,
  timestamptz,
  uuid
) FROM PUBLIC, anon, authenticated, service_role;

"}', 'adr0029_p1_sessionized_v1_training', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260729175359', '{"-- ADR-0028 Phase 2 + ADR-0029 P1 production activation.
-- Start shadow profiles from retained sessionized v1 history and extend them
-- with canonical-v2 evidence. Live alert authority remains unchanged.

CREATE FUNCTION private.dispatch_adaptive_alert_shadow_maintenance()
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET TimeZone = ''UTC''
AS $$
DECLARE
  _runtime private.adaptive_alert_shadow_runtime_config%ROWTYPE;
  _version public.alert_model_versions%ROWTYPE;
  _through_at timestamptz := clock_timestamp();
  _through_date date;
  _before_dml bigint := 0;
  _after_dml bigint := 0;
  _failure_code text;
  _failures integer;
BEGIN
  SELECT runtime.* INTO _runtime
  FROM private.adaptive_alert_shadow_runtime_config AS runtime
  WHERE runtime.singleton;

  IF _runtime.enabled IS NOT TRUE OR _runtime.version_id IS NULL THEN
    RETURN;
  END IF;

  PERFORM set_config(''statement_timeout'', ''120s'', true);
  PERFORM set_config(''lock_timeout'', ''2s'', true);
  _through_date := (_through_at AT TIME ZONE ''UTC'')::date;

  BEGIN
    SELECT version.* INTO _version
    FROM public.alert_model_versions AS version
    WHERE version.id = _runtime.version_id;

    IF NOT FOUND
       OR _version.status <> ''shadow''
       OR _version.shadow_enabled_at IS NULL
       OR _version.evidence_version <> ''canonical-v2''
       OR _version.config_sha256 <> encode(
         extensions.digest(_version.config::text, ''sha256''), ''hex''
       ) THEN
      RAISE EXCEPTION ''shadow_version_validation_failed'';
    END IF;

    IF _version.config #>> ''{sessionization,historical_v1_policy}''
       <> ''sessionized_training_only_v1'' THEN
      RAISE EXCEPTION ''shadow_history_policy_validation_failed'';
    END IF;

    IF NOT private.shadow_live_definition_matches(
      _version.config #>> ''{emergency,expected_live_definition_sha256}'',
      pg_get_functiondef(''private.silence_threshold(uuid)''::regprocedure)
    ) THEN
      RAISE EXCEPTION ''shadow_live_hash_mismatch'';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_catalog.pg_class AS relation
      WHERE relation.oid IN (
        ''public.alert_gap_profiles''::regclass,
        ''public.routine_mode_cohort_priors''::regclass,
        ''private.adaptive_alert_shadow_daily_reports''::regclass
      )
        AND NOT relation.relrowsecurity
    )
    OR has_table_privilege(''authenticated'',''public.alert_gap_profiles'',''SELECT'')
    OR EXISTS (
      SELECT 1
      FROM pg_catalog.pg_publication_tables AS publication
      WHERE publication.schemaname IN (''private'', ''public'')
        AND publication.tablename IN (
          ''alert_gap_profiles'',
          ''routine_mode_cohort_priors'',
          ''adaptive_alert_shadow_daily_reports''
        )
    ) THEN
      RAISE EXCEPTION ''shadow_acl_validation_failed'';
    END IF;

    SELECT coalesce(sum(stats.n_tup_ins + stats.n_tup_upd + stats.n_tup_del),0)
      INTO _before_dml
    FROM pg_catalog.pg_stat_xact_user_tables AS stats
    WHERE stats.relid IN (
      ''public.alerts''::regclass,
      ''public.alert_events''::regclass,
      ''public.notifications''::regclass
    );

    PERFORM private.rebuild_alert_gap_profiles(_runtime.version_id,_through_date);
    PERFORM private.rebuild_routine_mode_cohort_priors(_runtime.version_id,_through_date,''regular_9to5'');
    PERFORM private.rebuild_routine_mode_cohort_priors(_runtime.version_id,_through_date,''semester_break'');
    PERFORM private.rebuild_routine_mode_cohort_priors(_runtime.version_id,_through_date,''shift_irregular'');
    PERFORM private.maintain_adaptive_alert_shadow(_through_at,_runtime.max_population);

    SELECT coalesce(sum(stats.n_tup_ins + stats.n_tup_upd + stats.n_tup_del),0)
      INTO _after_dml
    FROM pg_catalog.pg_stat_xact_user_tables AS stats
    WHERE stats.relid IN (
      ''public.alerts''::regclass,
      ''public.alert_events''::regclass,
      ''public.notifications''::regclass
    );

    IF _after_dml <> _before_dml THEN
      RAISE EXCEPTION ''shadow_live_write_detected'';
    END IF;

    UPDATE private.adaptive_alert_shadow_runtime_config
    SET consecutive_failures = 0,
        last_failure_code = NULL,
        updated_at = clock_timestamp()
    WHERE singleton;
  EXCEPTION WHEN OTHERS THEN
    _failure_code := CASE
      WHEN SQLSTATE = ''57014'' THEN ''shadow_timeout''
      WHEN SQLERRM LIKE ''%shadow_live_write_detected%'' THEN ''shadow_live_write_detected''
      WHEN SQLERRM LIKE ''%shadow_live_hash_mismatch%'' THEN ''shadow_live_hash_mismatch''
      WHEN SQLERRM LIKE ''%shadow_acl_validation_failed%'' THEN ''shadow_acl_validation_failed''
      WHEN SQLERRM LIKE ''%shadow_history_policy_validation_failed%'' THEN ''shadow_malformed_result''
      WHEN SQLERRM LIKE ''%shadow_version_validation_failed%'' THEN ''shadow_malformed_result''
      ELSE ''ordinary_failure''
    END;

    IF _failure_code <> ''ordinary_failure'' THEN
      PERFORM private.disable_adaptive_alert_shadow(_failure_code);
      RETURN;
    END IF;

    UPDATE private.adaptive_alert_shadow_runtime_config
    SET consecutive_failures = least(max_consecutive_failures,consecutive_failures + 1),
        last_failure_code = ''ordinary_failure'',
        updated_at = clock_timestamp()
    WHERE singleton
    RETURNING consecutive_failures INTO _failures;

    IF _failures >= _runtime.max_consecutive_failures THEN
      PERFORM private.disable_adaptive_alert_shadow(''ordinary_failure'');
    END IF;
  END;
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.dispatch_adaptive_alert_shadow_maintenance()
FROM PUBLIC, anon, authenticated, service_role;

DO $activation$
DECLARE
  _config jsonb := ''{
    \"sessionization\": {
      \"gap_minutes\": 30,
      \"per_user_day_gap_cap\": 8,
      \"training_horizon_days\": 30,
      \"intervention_window_minutes\": 30,
      \"historical_v1_policy\": \"sessionized_training_only_v1\"
    },
    \"context\": {
      \"definition_version\": \"kc-shadow-prod-v1\",
      \"day_partition\": \"all_days\",
      \"hour_bucket_minutes\": 60
    },
    \"personal\": {
      \"min_samples\": 20,
      \"min_support_dates\": 7,
      \"min_span_days\": 14,
      \"max_age_days\": 30,
      \"min_confidence\": 0.7,
      \"confidence_formula_version\": \"support_ratio_v1\"
    },
    \"cohort\": {
      \"min_contributors\": 5,
      \"min_support_dates\": 7,
      \"min_span_days\": 14,
      \"max_age_days\": 30,
      \"min_confidence\": 0.5,
      \"contribution_floor_minutes\": 30,
      \"contribution_ceiling_minutes\": 600,
      \"confidence_formula_version\": \"cohort_support_min_v1\",
      \"algorithm\": \"weighted_median\",
      \"trim_fraction\": 0
    },
    \"sensitivity_buffers_minutes\": {\"high\": 0,\"balanced\": 45,\"low\": 90},
    \"candidate_bounds\": {\"floor_minutes\": 90,\"ceiling_minutes\": 600},
    \"sleep_compensation\": {
      \"max_start_delay_minutes\": 45,
      \"max_wake_advance_minutes\": 45,
      \"max_wake_delay_minutes\": 90,
      \"max_update_minutes_per_day\": 30,
      \"min_positive_nights\": 3,
      \"lookback_nights\": 7,
      \"min_late_events_per_night\": 2,
      \"timezone_tolerance_minutes\": 0
    },
    \"evaluator\": {\"contract_version\": \"adaptive_candidate_v1\"},
    \"emergency\": {
      \"contract_version\": \"adr0022_v1\",
      \"neutral_minutes\": 90,
      \"expected_live_definition_sha256\": \"1907d59473d274d46a0e8e0b9ce8027037b4494b0dddf073cb46abf67db92e21\"
    }
  }''::jsonb;
  _version_id uuid;
  _old_version_id uuid;
  _activation_minute timestamptz;
  _job_id bigint;
  _cycle_result jsonb;
BEGIN
  _activation_minute := date_trunc(''minute'',clock_timestamp() AT TIME ZONE ''UTC'') AT TIME ZONE ''UTC'';

  IF NOT private.shadow_live_definition_matches(
    _config #>> ''{emergency,expected_live_definition_sha256}'',
    pg_get_functiondef(''private.silence_threshold(uuid)''::regprocedure)
  ) THEN
    RAISE EXCEPTION ''shadow_live_hash_mismatch'';
  END IF;

  SELECT runtime.version_id INTO _old_version_id
  FROM private.adaptive_alert_shadow_runtime_config AS runtime
  WHERE runtime.singleton;

  INSERT INTO public.alert_model_versions (
    name,status,config,config_sha256,evidence_version,shadow_enabled_at
  ) VALUES (
    ''kc-shadow-prod-v2-history-seeded'',
    ''shadow'',
    _config,
    encode(extensions.digest(_config::text,''sha256''),''hex''),
    ''canonical-v2'',
    _activation_minute
  ) RETURNING id INTO _version_id;

  UPDATE private.adaptive_alert_shadow_runtime_config
  SET version_id = _version_id,
      enabled = true,
      accept_coverage_leases = true,
      consecutive_failures = 0,
      last_failure_code = NULL,
      updated_at = clock_timestamp()
  WHERE singleton;

  UPDATE public.alert_model_versions
  SET status = ''retired''
  WHERE id = _old_version_id
    AND id <> _version_id
    AND status = ''shadow'';

  PERFORM private.rebuild_alert_gap_profiles(
    _version_id,(_activation_minute AT TIME ZONE ''UTC'')::date
  );
  PERFORM private.rebuild_routine_mode_cohort_priors(
    _version_id,(_activation_minute AT TIME ZONE ''UTC'')::date,''regular_9to5''
  );
  PERFORM private.rebuild_routine_mode_cohort_priors(
    _version_id,(_activation_minute AT TIME ZONE ''UTC'')::date,''semester_break''
  );
  PERFORM private.rebuild_routine_mode_cohort_priors(
    _version_id,(_activation_minute AT TIME ZONE ''UTC'')::date,''shift_irregular''
  );

  _cycle_result := private.run_adaptive_alert_shadow_cycle(_version_id,_activation_minute);
  IF _cycle_result ->> ''status'' <> ''completed'' THEN
    RAISE EXCEPTION ''shadow_initial_cycle_failed'';
  END IF;

  FOR _job_id IN
    SELECT job.jobid FROM cron.job AS job
    WHERE job.jobname IN (
      ''adaptive-alert-shadow-cycle-v1'',
      ''adaptive-alert-shadow-maintenance-v1''
    )
  LOOP
    PERFORM cron.unschedule(_job_id);
  END LOOP;

  PERFORM cron.schedule(
    ''adaptive-alert-shadow-cycle-v1'',
    ''*/5 * * * *'',
    ''select private.dispatch_adaptive_alert_shadow_cycle();''
  );
  PERFORM cron.schedule(
    ''adaptive-alert-shadow-maintenance-v1'',
    ''17 2 * * *'',
    ''select private.dispatch_adaptive_alert_shadow_maintenance();''
  );

  IF (SELECT count(*) FROM cron.job AS job WHERE job.jobname IN (
    ''adaptive-alert-shadow-cycle-v1'',''adaptive-alert-shadow-maintenance-v1''
  )) <> 2 THEN
    RAISE EXCEPTION ''shadow_scheduler_activation_failed'';
  END IF;

  IF (SELECT count(*) FROM cron.job) > 8 THEN
    RAISE EXCEPTION ''shadow_scheduler_concurrency_budget_exceeded'';
  END IF;
END;
$activation$;"}', 'activate_history_seeded_adaptive_shadow', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260729180524', '{"-- ADR-0028 narrow repair: make the operational subject-context producer use
-- the evaluator''s complete-row provenance contract. Validation remains strict.

CREATE OR REPLACE FUNCTION private.capture_alert_shadow_subject_contexts(
  _version_id uuid,
  _captured_at timestamptz,
  _max_users integer
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET timezone = ''UTC''
AS $$
DECLARE
  _version public.alert_model_versions%ROWTYPE;
  _person record;
  _existing public.alert_judgment_subject_contexts%ROWTYPE;
  _population_count integer := 0;
  _replayable_count integer := 0;
  _unreplayable_count integer := 0;
  _reason text;
  _state text;
  _offset integer;
  _canonical_sensitivity text;
  _context_sha text;
  _existing_expected_sha text;
  _provenance jsonb;
BEGIN
  IF _version_id IS NULL OR _captured_at IS NULL
     OR _max_users IS NULL OR _max_users NOT BETWEEN 1 AND 10000 THEN
    RAISE EXCEPTION ''invalid shadow context capture arguments'';
  END IF;

  SELECT v.* INTO _version
  FROM public.alert_model_versions AS v
  WHERE v.id = _version_id
    AND v.status = ''shadow''
    AND v.shadow_enabled_at IS NOT NULL
    AND v.shadow_enabled_at <= _captured_at;

  IF NOT FOUND
     OR _version.evidence_version <> ''canonical-v2''
     OR _version.config_sha256 <>
       encode(extensions.digest(_version.config::text, ''sha256''), ''hex'') THEN
    RAISE EXCEPTION ''invalid shadow context version'';
  END IF;

  FOR _person IN
    WITH population AS (
      SELECT DISTINCT ds.user_id
      FROM public.device_state AS ds
      WHERE EXISTS (
        SELECT 1
        FROM public.group_members AS gm
        WHERE gm.user_id = ds.user_id
          AND gm.status = ''active''
          AND gm.monitored
      )
    )
    SELECT
      p.user_id,
      coalesce(s.sensitivity, ''balanced'') AS sensitivity,
      coalesce(s.timezone, ''UTC'') AS timezone,
      coalesce(s.updated_at, _captured_at) AS settings_updated_at,
      coalesce(pr.routine_pattern, ''regular_9to5'') AS routine_mode
    FROM population AS p
    LEFT JOIN public.user_settings AS s ON s.user_id = p.user_id
    LEFT JOIN public.profiles AS pr ON pr.id = p.user_id
    ORDER BY p.user_id
    LIMIT _max_users
  LOOP
    _population_count := _population_count + 1;
    _reason := NULL;
    _offset := 0;
    _canonical_sensitivity := CASE
      WHEN lower(trim(coalesce(_person.sensitivity, '''')))
        IN (''high'', ''sensitive'') THEN ''high''
      WHEN lower(trim(coalesce(_person.sensitivity, '''')))
        IN (''low'', ''relaxed'') THEN ''low''
      ELSE ''balanced''
    END;

    IF _person.settings_updated_at > _captured_at THEN
      _reason := ''future_source_timestamp'';
    ELSIF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_timezone_names AS z
      WHERE z.name = _person.timezone
    ) THEN
      _reason := ''invalid_timezone'';
    ELSE
      _offset := round(extract(epoch FROM (
        (_captured_at AT TIME ZONE _person.timezone)
        - (_captured_at AT TIME ZONE ''UTC'')
      )) / 60)::integer;
    END IF;

    _state := CASE WHEN _reason IS NULL THEN ''replayable'' ELSE ''unreplayable'' END;
    _provenance := jsonb_build_object(
      ''contract_version'', ''shadow-subject-context-v1'',
      ''version_id'', _version_id,
      ''user_id'', _person.user_id,
      ''sensitivity'', _person.sensitivity,
      ''routine_mode'', _person.routine_mode,
      ''timezone'', _person.timezone,
      ''utc_offset_minutes'', _offset,
      ''settings_updated_at'', _person.settings_updated_at,
      ''config_sha256'', _version.config_sha256,
      ''evidence_version'', _version.evidence_version,
      ''state'', _state,
      ''reason'', _reason
    );

    IF _reason IS NOT NULL THEN
      _context_sha := encode(
        extensions.digest(_provenance::text, ''sha256''), ''hex''
      );

      UPDATE public.alert_judgment_subject_contexts
      SET effective_to = _captured_at
      WHERE version_id = _version_id
        AND user_id = _person.user_id
        AND effective_to IS NULL
        AND effective_from < _captured_at;
    ELSE
      SELECT context.* INTO _existing
      FROM public.alert_judgment_subject_contexts AS context
      WHERE context.version_id = _version_id
        AND context.user_id = _person.user_id
        AND context.effective_to IS NULL
      ORDER BY context.effective_from DESC
      LIMIT 1;

      IF FOUND THEN
        _existing_expected_sha := encode(extensions.digest(jsonb_build_object(
          ''version_id'', _existing.version_id,
          ''user_id'', _existing.user_id,
          ''effective_from_utc'',
            to_char(_existing.effective_from AT TIME ZONE ''UTC'',
              ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
          ''effective_to_utc'', NULL,
          ''raw_sensitivity'', _existing.raw_sensitivity,
          ''canonical_sensitivity'', _existing.canonical_sensitivity,
          ''routine_mode'', _existing.routine_mode,
          ''timezone'', _existing.timezone,
          ''utc_offset_minutes'', _existing.utc_offset_minutes,
          ''settings_updated_at_utc'',
            to_char(_existing.settings_updated_at AT TIME ZONE ''UTC'',
              ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
          ''settings_provenance'', _existing.settings_provenance,
          ''captured_at_utc'',
            to_char(_existing.captured_at AT TIME ZONE ''UTC'',
              ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
          ''config_sha256'', _existing.config_sha256,
          ''evidence_version'', _existing.evidence_version
        )::text, ''sha256''), ''hex'');
      ELSE
        _existing_expected_sha := NULL;
      END IF;

      IF FOUND
         AND _existing.subject_context_sha256 = _existing_expected_sha
         AND _existing.raw_sensitivity IS NOT DISTINCT FROM _person.sensitivity
         AND _existing.canonical_sensitivity = _canonical_sensitivity
         AND _existing.routine_mode = _person.routine_mode
         AND _existing.timezone = _person.timezone
         AND _existing.utc_offset_minutes = _offset
         AND _existing.settings_updated_at = _person.settings_updated_at
         AND _existing.settings_provenance = _provenance
         AND _existing.config_sha256 = _version.config_sha256
         AND _existing.evidence_version = _version.evidence_version THEN
        _context_sha := _existing.subject_context_sha256;
      ELSE
        _context_sha := encode(extensions.digest(jsonb_build_object(
          ''version_id'', _version_id,
          ''user_id'', _person.user_id,
          ''effective_from_utc'',
            to_char(_captured_at AT TIME ZONE ''UTC'',
              ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
          ''effective_to_utc'', NULL,
          ''raw_sensitivity'', _person.sensitivity,
          ''canonical_sensitivity'', _canonical_sensitivity,
          ''routine_mode'', _person.routine_mode,
          ''timezone'', _person.timezone,
          ''utc_offset_minutes'', _offset,
          ''settings_updated_at_utc'',
            to_char(_person.settings_updated_at AT TIME ZONE ''UTC'',
              ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
          ''settings_provenance'', _provenance,
          ''captured_at_utc'',
            to_char(_captured_at AT TIME ZONE ''UTC'',
              ''YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"''),
          ''config_sha256'', _version.config_sha256,
          ''evidence_version'', _version.evidence_version
        )::text, ''sha256''), ''hex'');

        UPDATE public.alert_judgment_subject_contexts
        SET effective_to = _captured_at
        WHERE version_id = _version_id
          AND user_id = _person.user_id
          AND effective_to IS NULL
          AND effective_from < _captured_at;

        INSERT INTO public.alert_judgment_subject_contexts (
          version_id, user_id, effective_from, raw_sensitivity,
          canonical_sensitivity, routine_mode, timezone, utc_offset_minutes,
          settings_updated_at, settings_provenance, captured_at,
          config_sha256, evidence_version, subject_context_sha256
        ) VALUES (
          _version_id, _person.user_id, _captured_at, _person.sensitivity,
          _canonical_sensitivity, _person.routine_mode, _person.timezone, _offset,
          _person.settings_updated_at, _provenance, _captured_at,
          _version.config_sha256, _version.evidence_version, _context_sha
        );
      END IF;
    END IF;

    INSERT INTO private.adaptive_alert_shadow_subject_context_state (
      version_id, user_id, context_state, unreplayable_reason,
      subject_context_sha256, captured_at
    ) VALUES (
      _version_id, _person.user_id, _state, _reason, _context_sha, _captured_at
    )
    ON CONFLICT (version_id, user_id) DO UPDATE SET
      context_state = excluded.context_state,
      unreplayable_reason = excluded.unreplayable_reason,
      subject_context_sha256 = excluded.subject_context_sha256,
      captured_at = excluded.captured_at;

    IF _reason IS NULL THEN
      _replayable_count := _replayable_count + 1;
    ELSE
      _unreplayable_count := _unreplayable_count + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    ''status'', ''completed'',
    ''population_count'', _population_count,
    ''replayable_count'', _replayable_count,
    ''unreplayable_count'', _unreplayable_count
  );
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.capture_alert_shadow_subject_contexts(uuid,timestamptz,integer)
FROM PUBLIC, anon, authenticated, service_role;

DO $$
DECLARE
  _runtime private.adaptive_alert_shadow_runtime_config%ROWTYPE;
BEGIN
  SELECT c.* INTO _runtime
  FROM private.adaptive_alert_shadow_runtime_config AS c
  WHERE c.singleton;

  IF FOUND AND _runtime.enabled AND _runtime.version_id IS NOT NULL THEN
    PERFORM private.capture_alert_shadow_subject_contexts(
      _runtime.version_id,
      clock_timestamp(),
      _runtime.max_population
    );
  END IF;
END;
$$;"}', 'fix_shadow_subject_context_provenance', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260729184648', '{"-- Human-authorized live correction:
-- 1. A valid retained personal profile is the starting live threshold.
-- 2. New canonical-v2 sessions may only extend that starting point until a
--    newer rebuilt profile absorbs/replaces them.
-- 3. The fixed sensitivity template remains a floor, never a ceiling.
-- 4. Configured sleep and the two-hour post-wake grace gate every silence path.

CREATE OR REPLACE FUNCTION private.silence_threshold(_user_id uuid)
RETURNS interval
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''''
SET TimeZone = ''UTC''
AS $$
DECLARE
  _s text;
  _fixed_minutes integer;
  _version_id uuid;
  _config jsonb;
  _config_sha256 text;
  _evidence_version text;
  _gap_minutes integer;
  _horizon_days integer;
  _max_age_days integer;
  _buffer_minutes integer;
  _ceiling_minutes integer;
  _profile_minutes integer;
  _profile_latest_at timestamptz;
  _new_p95_minutes integer;
  _personal_minutes integer;
BEGIN
  SELECT sensitivity
    INTO _s
  FROM public.user_settings
  WHERE user_id = _user_id;

  _s := coalesce(_s, ''balanced'');
  _fixed_minutes := CASE _s
    WHEN ''high'' THEN 90
    WHEN ''sensitive'' THEN 90
    WHEN ''low'' THEN 180
    WHEN ''relaxed'' THEN 180
    ELSE 135
  END;

  SELECT
    runtime.version_id,
    version.config,
    version.config_sha256,
    version.evidence_version
  INTO
    _version_id,
    _config,
    _config_sha256,
    _evidence_version
  FROM private.adaptive_alert_shadow_runtime_config AS runtime
  JOIN public.alert_model_versions AS version
    ON version.id = runtime.version_id
  WHERE runtime.singleton
    AND runtime.enabled
    AND version.status = ''shadow''
    AND version.shadow_enabled_at IS NOT NULL
    AND version.evidence_version = ''canonical-v2''
    AND version.config_sha256
      = encode(extensions.digest(version.config::text, ''sha256''), ''hex'')
    AND private.alert_candidate_config_is_valid(version.config);

  IF _version_id IS NULL THEN
    RETURN make_interval(mins => _fixed_minutes);
  END IF;

  BEGIN
    _gap_minutes :=
      (_config #>> ''{sessionization,gap_minutes}'')::integer;
    _horizon_days :=
      (_config #>> ''{sessionization,training_horizon_days}'')::integer;
    _max_age_days :=
      (_config #>> ''{personal,max_age_days}'')::integer;
    _buffer_minutes := CASE _s
      WHEN ''high'' THEN
        (_config #>> ''{sensitivity_buffers_minutes,high}'')::integer
      WHEN ''sensitive'' THEN
        (_config #>> ''{sensitivity_buffers_minutes,high}'')::integer
      WHEN ''low'' THEN
        (_config #>> ''{sensitivity_buffers_minutes,low}'')::integer
      WHEN ''relaxed'' THEN
        (_config #>> ''{sensitivity_buffers_minutes,low}'')::integer
      ELSE
        (_config #>> ''{sensitivity_buffers_minutes,balanced}'')::integer
    END;
    _ceiling_minutes :=
      (_config #>> ''{candidate_bounds,ceiling_minutes}'')::integer;
  EXCEPTION
    WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      RETURN make_interval(mins => _fixed_minutes);
  END;

  SELECT
    profile.neutral_p95_minutes,
    profile.latest_evidence_at
  INTO
    _profile_minutes,
    _profile_latest_at
  FROM public.alert_gap_profiles AS profile
  WHERE profile.version_id = _version_id
    AND profile.user_id = _user_id
    AND profile.context_key = ''personal_global''
    AND profile.quality_state = ''valid''
    AND profile.config_sha256 = _config_sha256
    AND profile.evidence_version = _evidence_version
    AND profile.latest_evidence_at
      >= now() - make_interval(days => _max_age_days)
  ORDER BY profile.through_date DESC, profile.computed_at DESC
  LIMIT 1;

  IF _profile_minutes IS NULL THEN
    RETURN make_interval(mins => _fixed_minutes);
  END IF;

  -- This is training-only extension evidence. It reads canonical rows after
  -- the selected profile''s evidence boundary, but does not claim coverage,
  -- refresh heartbeat, resolve alerts, or mutate a profile. Once a newer
  -- profile advances latest_evidence_at, the same rows leave this extension.
  WITH admitted AS (
    SELECT ping.id, ping.received_at
    FROM public.behavior_pings AS ping
    WHERE ping.user_id = _user_id
      AND ping.ingest_version = 2
      AND ping.received_at >= greatest(
        _profile_latest_at,
        now() - make_interval(days => _horizon_days)
      )
      AND ping.received_at <= now()
      AND ping.at <= now()
      AND abs(extract(epoch FROM (ping.received_at - ping.at))) <= 300
  ),
  marked AS (
    SELECT
      admitted.*,
      CASE
        WHEN lag(received_at) OVER (ORDER BY received_at, id) IS NULL
          OR received_at
            - lag(received_at) OVER (ORDER BY received_at, id)
              > make_interval(mins => _gap_minutes)
          THEN 1
        ELSE 0
      END AS starts_session
    FROM admitted
  ),
  grouped AS (
    SELECT
      marked.*,
      sum(starts_session) OVER (ORDER BY received_at, id) AS session_no
    FROM marked
  ),
  sessions AS (
    SELECT
      min(received_at) AS session_start,
      max(received_at) AS session_end
    FROM grouped
    GROUP BY session_no
  ),
  paired AS (
    SELECT
      session_end,
      lead(session_start) OVER (ORDER BY session_start) AS next_start
    FROM sessions
  )
  SELECT ceil(
    percentile_disc(0.95) WITHIN GROUP (
      ORDER BY extract(epoch FROM (next_start - session_end)) / 60.0
    )
  )::integer
  INTO _new_p95_minutes
  FROM paired
  WHERE next_start IS NOT NULL;

  _personal_minutes := greatest(
    _profile_minutes,
    coalesce(_new_p95_minutes, _profile_minutes)
  ) + _buffer_minutes;

  RETURN make_interval(
    mins => greatest(
      _fixed_minutes,
      least(_ceiling_minutes, _personal_minutes)
    )
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION private.silence_threshold(uuid)
FROM PUBLIC, anon, authenticated, service_role;

-- Existing shadow versions pin the pre-promotion ADR-0022 definition. Preserve
-- that immutable model config and explicitly recognize this one
-- human-authorized successor definition; every unrelated hash stays closed.
CREATE OR REPLACE FUNCTION private.shadow_live_definition_matches(
  _expected_sha256 text,
  _actual_definition text
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''''
AS $$
  WITH hashes AS (
    SELECT
      encode(
        extensions.digest(_actual_definition, ''sha256''),
        ''hex''
      ) AS raw_sha256,
      encode(
        extensions.digest(
          replace(_actual_definition, E''\\r\\n'', E''\\n''),
          ''sha256''
        ),
        ''hex''
      ) AS lf_sha256
  )
  SELECT CASE
    WHEN _expected_sha256 !~ ''^[a-f0-9]{64}$''
      OR _actual_definition IS NULL
      THEN false
    ELSE
      _expected_sha256 IN (hashes.raw_sha256, hashes.lf_sha256)
      OR (
        _expected_sha256 =
          ''1907d59473d274d46a0e8e0b9ce8027037b4494b0dddf073cb46abf67db92e21''
        AND hashes.lf_sha256 IN (
          ''686116ef8f2df1d78f6d0d48ded8019555f283b098eeb5d354cfa1c14ebbcdca'',
          ''6be4ed54feff52428cf1d86210126bd9362953201fc5ac8b9e885abd586092ce''
        )
      )
  END
  FROM hashes
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.shadow_live_definition_matches(text,text)
FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.process_escalations()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''''
AS $function$
DECLARE
  _self_grace CONSTANT interval := interval ''30 minutes'';
  _group_dur  CONSTANT interval := interval ''1 hour'';
  _comm_dur   CONSTANT interval := interval ''2 hours'';
  r record;
  _aid uuid;
  _new text;
  _triggered boolean := false;
BEGIN
  -- Sleep/post-wake grace clears silence alerts even without a newer ping.
  FOR r IN
    SELECT
      a.id,
      a.user_id,
      a.cause,
      ds.last_heartbeat_at,
      bp.last_at AS last_behavior_at
    FROM public.alerts AS a
    LEFT JOIN public.device_state AS ds ON ds.user_id = a.user_id
    LEFT JOIN LATERAL (
      SELECT max(received_at) AS last_at
      FROM public.behavior_pings
      WHERE user_id = a.user_id
        AND ingest_version = 2
        AND abs(extract(epoch FROM (received_at - at))) <= 300
        AND received_at >= a.opened_at
        AND at >= a.opened_at
    ) AS bp ON true
    WHERE a.status = ''open''
      AND a.cause IN (''silence'', ''dark_device'')
      AND (
        (
          a.cause = ''silence''
          AND (
            private.sleep_relaxed(a.user_id, now())
            OR (
              bp.last_at IS NOT NULL
              AND now() - bp.last_at
                <= private.silence_threshold(a.user_id)
            )
          )
        )
        OR (
          a.cause = ''dark_device''
          AND ds.last_heartbeat_at IS NOT NULL
          AND now() - ds.last_heartbeat_at <= interval ''18 hours''
        )
      )
  LOOP
    UPDATE public.alerts
    SET status = ''resolved'',
        resolved_at = now(),
        resolved_by = NULL,
        updated_at = now()
    WHERE id = r.id;

    INSERT INTO public.alert_events (alert_id, kind, note)
    VALUES (r.id, ''auto_resolved'', ''condition_cleared'');

    PERFORM private.notify_auto_resolved(r.id, r.user_id);
    _triggered := true;
  END LOOP;

  -- device_state.status is descriptive state, not an independent authority to
  -- bypass the canonical silence calculation or sleep grace.
  FOR r IN
    SELECT
      ds.user_id,
      (now() - ds.last_heartbeat_at) > interval ''18 hours'' AS is_dark
    FROM public.device_state AS ds
    WHERE (
      now() - ds.last_heartbeat_at > interval ''18 hours''
      OR (
        NOT private.sleep_relaxed(ds.user_id, now())
        AND now() - (
          SELECT coalesce(max(received_at), to_timestamp(0))
          FROM public.behavior_pings
          WHERE user_id = ds.user_id
            AND ingest_version = 2
            AND abs(extract(epoch FROM (received_at - at))) <= 300
        ) > private.silence_threshold(ds.user_id)
      )
    )
      AND EXISTS (
        SELECT 1
        FROM public.group_members AS gm
        WHERE gm.user_id = ds.user_id
          AND gm.monitored
          AND gm.status = ''active''
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.alerts AS a
        WHERE a.user_id = ds.user_id
          AND a.status = ''open''
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.alerts AS recent
        WHERE recent.user_id = ds.user_id
          AND recent.status = ''resolved''
          AND recent.cause IN (''silence'', ''dark_device'')
          AND recent.resolved_by IS NOT NULL
          AND recent.resolved_by <> recent.user_id
          AND recent.resolved_at > now() - _self_grace
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.gm_mutes AS mute
        WHERE mute.user_id = ds.user_id
          AND (mute.muted_until IS NULL OR mute.muted_until > now())
      )
  LOOP
    INSERT INTO public.alerts (
      user_id, cause, stage, stage_entered_at, next_deadline
    )
    VALUES (
      r.user_id,
      CASE WHEN r.is_dark THEN ''dark_device'' ELSE ''silence'' END,
      ''self'',
      now(),
      now() + _self_grace
    )
    RETURNING id INTO _aid;

    INSERT INTO public.alert_events (alert_id, kind)
    VALUES (_aid, ''raised'');

    PERFORM private.notify_stage(_aid, r.user_id, ''self'');
    _triggered := true;
  END LOOP;

  FOR r IN
    SELECT *
    FROM public.alerts
    WHERE status = ''open''
      AND next_deadline IS NOT NULL
      AND next_deadline <= now()
      AND coalesce(paused_until, to_timestamp(0)) <= now()
  LOOP
    _new := CASE r.stage
      WHEN ''self'' THEN ''group''
      WHEN ''group'' THEN ''community''
      WHEN ''community'' THEN ''terminal''
      ELSE ''terminal''
    END;

    UPDATE public.alerts
    SET stage = _new,
        stage_entered_at = now(),
        paused_until = NULL,
        paused_by = NULL,
        updated_at = now(),
        next_deadline = CASE _new
          WHEN ''group'' THEN now() + _group_dur
          WHEN ''community'' THEN now() + _comm_dur
          ELSE NULL
        END
    WHERE id = r.id;

    INSERT INTO public.alert_events (alert_id, kind, note)
    VALUES (r.id, ''escalated'', _new);

    PERFORM private.notify_stage(r.id, r.user_id, _new);
    _triggered := true;
  END LOOP;

  IF _triggered THEN
    PERFORM private.trigger_push_dispatch();
  END IF;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.process_escalations()
FROM PUBLIC, anon, authenticated;

"}', 'use_history_seeded_live_threshold_and_sleep_grace', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260801083106', '{"alter table public.notifications drop constraint notifications_delivery_outcome_check;
alter table public.notifications add constraint notifications_delivery_outcome_check
  check (delivery_outcome = any (array[''sent''::text, ''no_target''::text, ''failed''::text, ''native_missed''::text]));

create or replace function public.finalize_notification_delivery(
  p_notification_id uuid,
  p_outcome text
)
returns void
language plpgsql
security definer
set search_path to ''''
as $function$
DECLARE
  v_attempts integer;
BEGIN
  IF p_outcome NOT IN (''sent'', ''no_target'', ''retry'', ''native_missed'') THEN
    RAISE EXCEPTION ''Invalid outcome: %'', p_outcome;
  END IF;

  SELECT n.delivery_attempts INTO v_attempts
  FROM public.notifications n
  WHERE n.id = p_notification_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION ''Notification not found: %'', p_notification_id;
  END IF;

  IF p_outcome = ''sent'' THEN
    UPDATE public.notifications
    SET
      pushed_at = now(),
      delivery_outcome = ''sent'',
      delivery_lease_expiry = NULL
    WHERE id = p_notification_id;
  ELSIF p_outcome = ''no_target'' THEN
    UPDATE public.notifications
    SET
      pushed_at = now(),
      delivery_outcome = ''no_target'',
      delivery_lease_expiry = NULL
    WHERE id = p_notification_id;
  ELSIF p_outcome = ''native_missed'' THEN
    UPDATE public.notifications
    SET
      pushed_at = now(),
      delivery_outcome = ''native_missed'',
      delivery_lease_expiry = NULL
    WHERE id = p_notification_id;
  ELSIF p_outcome = ''retry'' THEN
    IF v_attempts >= 5 THEN
      UPDATE public.notifications
      SET
        pushed_at = now(),
        delivery_outcome = ''failed'',
        delivery_lease_expiry = NULL
      WHERE id = p_notification_id;
    ELSE
      UPDATE public.notifications
      SET
        delivery_lease_expiry = NULL
      WHERE id = p_notification_id;
    END IF;
  END IF;
END;
$function$;"}', 'delivery_outcome_native_missed', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260801201728', '{"create or replace function public.gm_send_concern(_target uuid)
returns void
language plpgsql
security definer
set search_path to ''''
as $function$
declare _uid uuid := auth.uid(); _name text; _aid uuid;
begin
  if not private.is_admin(_uid) then raise exception ''forbidden''; end if;
  select coalesce(display_name, '''') into _name from public.profiles where id = _uid;

  select id into _aid from public.alerts where user_id = _target and status = ''open'' limit 1;
  if _aid is null then
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    values (_target, ''concern'', ''self'', now(), now() + interval ''30 minutes'')
    returning id into _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note)
    values (_aid, _uid, ''raised'', ''gm_concern'');
  end if;

  insert into public.notifications (recipient_id, alert_id, kind, body, params)
  values (
    _target,
    _aid,
    ''concern'',
    coalesce(nullif(_name, ''''), ''管理员'') || '' 在关心你，请打开 App 完成解锁报平安。'',
    jsonb_build_object(''name'', _name)
  );
  perform private.trigger_push_dispatch();
end;
$function$;"}', 'gm_send_concern_real_alert', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260802115211', '{"alter table public.alerts
  add column if not exists requires_explicit_unlock boolean not null default false;

comment on column public.alerts.requires_explicit_unlock is
  ''Someone asked this subject to prove they are alright. Passive liveness may not clear it; only an explicit unlock may. Survives alert reuse, which a cause check cannot.'';

update public.alerts a
set requires_explicit_unlock = true
where a.status = ''open''
  and (
    a.cause = ''concern''
    or exists (
      select 1 from public.notifications n
      where n.alert_id = a.id and n.kind = ''concern''
    )
  );

create or replace function private.apply_liveness_side_effects(
  _user_id uuid,
  _observed_at timestamptz,
  _received_at timestamptz
)
returns void
language plpgsql
security definer
set search_path to ''''
as $function$
DECLARE
  _stale record;
  _triggered boolean := false;
BEGIN
  INSERT INTO public.device_state (user_id, status, last_heartbeat_at, updated_at)
  VALUES (_user_id, ''normal'', _received_at, now())
  ON CONFLICT (user_id) DO UPDATE
    SET status = ''normal'',
        last_heartbeat_at = greatest(device_state.last_heartbeat_at, excluded.last_heartbeat_at),
        updated_at = now();

  FOR _stale IN
    SELECT id, opened_at FROM public.alerts
    WHERE user_id = _user_id
      AND status = ''open''
      AND cause in (''silence'', ''dark_device'')
      AND requires_explicit_unlock = false
      AND _received_at >= opened_at
      AND _observed_at >= opened_at
  LOOP
    UPDATE public.alerts
      SET status = ''resolved'', resolved_at = _received_at, resolved_by = _user_id, updated_at = now()
      WHERE id = _stale.id;

    INSERT INTO public.alert_events (alert_id, actor_id, kind)
    VALUES (_stale.id, _user_id, ''auto_resolved'');

    PERFORM private.notify_auto_resolved(_stale.id, _user_id);
    _triggered := true;
  END LOOP;

  IF NOT (auth.uid() IS NOT NULL AND auth.uid() <> _user_id) THEN
    DELETE FROM public.notifications
      WHERE recipient_id = _user_id
        AND kind in (''self'', ''concern'');
  END IF;

  IF _triggered THEN
    PERFORM private.trigger_push_dispatch();
  END IF;
END;
$function$;

create or replace function public.send_concern(_target uuid)
returns void
language plpgsql
security definer
set search_path to ''''
as $function$
declare _uid uuid := auth.uid(); _name text; _aid uuid;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  if _uid = _target then raise exception ''bad target''; end if;
  if not private.shares_group_with(_target, _uid) and not private.is_guardian_of(_target, _uid) then
    raise exception ''forbidden'';
  end if;
  select coalesce(display_name, '''') into _name from public.profiles where id = _uid;

  select id into _aid from public.alerts where user_id = _target and status = ''open'' limit 1;
  if _aid is null then
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline, requires_explicit_unlock)
    values (_target, ''concern'', ''self'', now(), now() + interval ''30 minutes'', true)
    returning id into _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note)
    values (_aid, _uid, ''raised'', ''concern'');
  else
    update public.alerts set requires_explicit_unlock = true, updated_at = now()
    where id = _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note)
    values (_aid, _uid, ''raised'', ''concern_on_open_alert'');
  end if;

  insert into public.notifications (recipient_id, alert_id, kind, body, params)
  values (
    _target,
    _aid,
    ''concern'',
    coalesce(nullif(_name, ''''), ''有人'') || '' 在关心你，请打开 App 完成解锁报平安。'',
    jsonb_build_object(''name'', _name)
  );
  perform private.trigger_push_dispatch();
end;
$function$;

create or replace function public.gm_send_concern(_target uuid)
returns void
language plpgsql
security definer
set search_path to ''''
as $function$
declare _uid uuid := auth.uid(); _name text; _aid uuid;
begin
  if not private.is_admin(_uid) then raise exception ''forbidden''; end if;
  select coalesce(display_name, '''') into _name from public.profiles where id = _uid;

  select id into _aid from public.alerts where user_id = _target and status = ''open'' limit 1;
  if _aid is null then
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline, requires_explicit_unlock)
    values (_target, ''concern'', ''self'', now(), now() + interval ''30 minutes'', true)
    returning id into _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note)
    values (_aid, _uid, ''raised'', ''gm_concern'');
  else
    update public.alerts set requires_explicit_unlock = true, updated_at = now()
    where id = _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note)
    values (_aid, _uid, ''raised'', ''gm_concern_on_open_alert'');
  end if;

  insert into public.notifications (recipient_id, alert_id, kind, body, params)
  values (
    _target,
    _aid,
    ''concern'',
    coalesce(nullif(_name, ''''), ''管理员'') || '' 在关心你，请打开 App 完成解锁报平安。'',
    jsonb_build_object(''name'', _name)
  );
  perform private.trigger_push_dispatch();
end;
$function$;"}', 'concern_requires_explicit_unlock', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260802124556', '{"create or replace function private.apply_liveness_side_effects(
  _user_id uuid,
  _observed_at timestamptz,
  _received_at timestamptz
)
returns void
language plpgsql
security definer
set search_path to ''''
as $function$
BEGIN
  INSERT INTO public.device_state (user_id, status, last_heartbeat_at, updated_at)
  VALUES (_user_id, ''normal'', _received_at, now())
  ON CONFLICT (user_id) DO UPDATE
    SET status = ''normal'',
        last_heartbeat_at = greatest(device_state.last_heartbeat_at, excluded.last_heartbeat_at),
        updated_at = now();

  IF NOT (auth.uid() IS NOT NULL AND auth.uid() <> _user_id)
     AND NOT EXISTS (
       SELECT 1 FROM public.alerts
       WHERE user_id = _user_id AND status = ''open''
     ) THEN
    DELETE FROM public.notifications
      WHERE recipient_id = _user_id
        AND kind in (''self'', ''concern'');
  END IF;
END;
$function$;

create or replace function public.resolve_my_alert()
returns void
language plpgsql
security definer
set search_path to ''''
as $function$
declare _uid uuid := auth.uid(); _aid uuid;
begin
  if _uid is null then raise exception ''not authenticated''; end if;
  update public.alerts set status = ''resolved'', resolved_at = now(), resolved_by = _uid, updated_at = now()
    where user_id = _uid and status = ''open'' returning id into _aid;
  if _aid is not null then
    insert into public.alert_events (alert_id, actor_id, kind) values (_aid, _uid, ''resolved'');
  end if;

  insert into public.behavior_pings (user_id, kind, at)
  values (_uid, ''manual_checkin'', now());

  delete from public.notifications
    where recipient_id = _uid and kind in (''self'', ''concern'');

  perform private.trigger_push_dispatch();
end;
$function$;"}', 'activity_never_answers_an_alert', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260802134424', '{"-- ADR-0035 step 1: account-level liveness gap profile.
--
-- What this is
--   The routine-learning root, rebuilt as ADR-0035 requires: one account, one
--   event stream across every device it is signed in on, sleep subtracted,
--   p95 taken, then shrunk toward the account''s preset cohort by n/(n+k).
--   No coverage lease. No observation attestation. No outlier ceiling.
--
-- What this is NOT
--   Nothing here is wired to anything. private.silence_threshold still reads
--   public.alert_gap_profiles exactly as before, no cron job runs this, and no
--   live alert, notification, device_state, or behavior_ping row is touched.
--   ADR-0035 step 2 (shadow parallel comparison), step 3 (calibrating k against
--   production and handing the number to the human), and step 4 (switching the
--   threshold source) are separate, separately governed changes.
--
-- Two design points that are easy to get wrong later:
--
--   1. The learning stream must equal the detection stream. The live detector
--      sees `ingest_version = 2 AND abs(received_at - at) <= 300`, measured on
--      received_at. If learning admitted a wider stream than detection can see,
--      every learned gap would be shorter than the gap detection actually
--      observes, and the threshold would come out systematically too tight.
--      \"Wide intake\" in ADR-0035 means dropping the coverage lease, not
--      redefining what counts as a ping.
--
--   2. Sleep is subtracted, never allowed to inflate. An overnight gap is not
--      evidence of a slow rhythm. Overlap with the account''s configured sleep
--      window comes off each gap before the percentile is taken. The 2-hour
--      post-wake grace in private.sleep_relaxed is deliberately NOT subtracted
--      here: that grace suppresses alerting, it is not evidence about routine.

-- 1) Sleep-window overlap for an arbitrary interval, in minutes.
--    Recurring nightly window resolved in the account''s own timezone, so DST
--    shifts are handled by the calendar rather than by arithmetic.
CREATE FUNCTION private.account_gap_sleep_minutes(
  _user_id uuid,
  _from timestamptz,
  _to timestamptz
)
RETURNS double precision
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''''
AS $$
DECLARE
  _start time;
  _end time;
  _timezone text;
  _overlap double precision;
BEGIN
  IF _user_id IS NULL OR _from IS NULL OR _to IS NULL OR _to <= _from THEN
    RETURN 0;
  END IF;

  SELECT s.sleep_start_local, s.sleep_end_local, coalesce(s.timezone, ''UTC'')
    INTO _start, _end, _timezone
  FROM public.user_settings AS s
  WHERE s.user_id = _user_id;

  IF _start IS NULL OR _end IS NULL OR _start = _end THEN
    RETURN 0;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_timezone_names AS z WHERE z.name = _timezone
  ) THEN
    RETURN 0;
  END IF;

  SELECT coalesce(sum(
    greatest(
      0,
      extract(epoch FROM (
        least(_to, night.ends_at) - greatest(_from, night.starts_at)
      ))
    ) / 60.0
  ), 0)
    INTO _overlap
  FROM (
    SELECT
      ((day.d + _start) AT TIME ZONE _timezone) AS starts_at,
      ((
        day.d
        + CASE WHEN _end <= _start THEN 1 ELSE 0 END
        + _end
      ) AT TIME ZONE _timezone) AS ends_at
    FROM (
      SELECT generate.value::date AS d
      FROM pg_catalog.generate_series(
        ((_from AT TIME ZONE _timezone)::date - 1)::timestamp,
        ((_to AT TIME ZONE _timezone)::date + 1)::timestamp,
        interval ''1 day''
      ) AS generate(value)
    ) AS day
  ) AS night;

  RETURN _overlap;
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.account_gap_sleep_minutes(uuid, timestamptz, timestamptz)
FROM PUBLIC, anon, authenticated, service_role;

-- 2) The profile table.
--    The primary key carries the parameters, so step 3 can sweep k without
--    destroying the previous run''s rows and without a second table.
CREATE TABLE public.account_gap_profiles (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  through_date date NOT NULL,
  lookback_days integer NOT NULL CHECK (lookback_days > 0),
  shrinkage_k integer NOT NULL CHECK (shrinkage_k >= 0),
  percentile numeric(4, 3) NOT NULL CHECK (percentile > 0 AND percentile < 1),

  computed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  window_starts_at timestamptz NOT NULL,
  window_ends_at timestamptz NOT NULL,

  event_count integer NOT NULL CHECK (event_count >= 0),
  gap_count integer NOT NULL CHECK (gap_count >= 0),
  distinct_event_days integer NOT NULL CHECK (distinct_event_days >= 0),
  first_event_at timestamptz,
  last_event_at timestamptz,

  sleep_window_applied boolean NOT NULL,
  sleep_minutes_removed double precision NOT NULL DEFAULT 0
    CHECK (sleep_minutes_removed >= 0),

  -- Neutral values: no sensitivity buffer, no floor, no ceiling. Whatever
  -- assembles a threshold from this row owns those, not this table.
  personal_p50_minutes integer CHECK (personal_p50_minutes >= 0),
  personal_pctl_minutes integer CHECK (personal_pctl_minutes >= 0),
  personal_max_minutes integer CHECK (personal_max_minutes >= 0),

  cohort_key text NOT NULL,
  cohort_pctl_minutes integer NOT NULL CHECK (cohort_pctl_minutes >= 0),
  cohort_contributor_count integer NOT NULL CHECK (cohort_contributor_count >= 0),
  cohort_source text NOT NULL CHECK (cohort_source IN (''cohort'', ''fallback'')),

  blend_weight double precision NOT NULL
    CHECK (blend_weight >= 0 AND blend_weight <= 1),
  blended_pctl_minutes integer NOT NULL CHECK (blended_pctl_minutes >= 0),

  -- Diagnostic, not a filter. A gap that overlaps an open alert is a gap the
  -- system already called abnormal; letting it teach the model that the account
  -- is \"slow\" is a feedback loop. ADR-0035 chose wide intake, so these gaps are
  -- admitted -- but they are counted so step 3 can measure what that costs.
  gaps_overlapping_open_alert integer NOT NULL DEFAULT 0
    CHECK (gaps_overlapping_open_alert >= 0),

  PRIMARY KEY (user_id, through_date, lookback_days, shrinkage_k, percentile),
  CHECK (window_ends_at > window_starts_at),
  CHECK ((gap_count = 0) = (personal_pctl_minutes IS NULL))
);

ALTER TABLE public.account_gap_profiles ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.account_gap_profiles
FROM PUBLIC, anon, authenticated, service_role;

CREATE INDEX account_gap_profiles_through_date_idx
  ON public.account_gap_profiles (through_date DESC, user_id);

-- 3) The rebuild.
CREATE FUNCTION private.rebuild_account_gap_profiles(
  _through_date date DEFAULT NULL,
  _lookback_days integer DEFAULT 30,
  _shrinkage_k integer DEFAULT 50,
  _percentile numeric DEFAULT 0.95,
  _cohort_min_gaps integer DEFAULT 30,
  _cohort_min_contributors integer DEFAULT 2,
  _cohort_fallback_minutes integer DEFAULT 90,
  _cohort_requires_consent boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET TimeZone = ''UTC''
AS $$
DECLARE
  _date date := coalesce(_through_date, (now() AT TIME ZONE ''UTC'')::date);
  _window_ends timestamptz;
  _window_starts timestamptz;
  _written integer := 0;
BEGIN
  IF _lookback_days IS NULL OR _lookback_days <= 0
     OR _shrinkage_k IS NULL OR _shrinkage_k < 0
     OR _percentile IS NULL OR _percentile <= 0 OR _percentile >= 1
     OR _cohort_min_gaps IS NULL OR _cohort_min_gaps < 0
     OR _cohort_min_contributors IS NULL OR _cohort_min_contributors < 1
     OR _cohort_fallback_minutes IS NULL OR _cohort_fallback_minutes < 0 THEN
    RAISE EXCEPTION ''rebuild_account_gap_profiles: invalid parameters'';
  END IF;

  _window_ends := (_date + 1)::timestamptz;
  _window_starts := _window_ends - pg_catalog.make_interval(days => _lookback_days);

  WITH events AS (
    -- One account, every device, deduplicated to the minute so that a device
    -- that reports twice in the same minute does not buy the account extra
    -- apparent evidence (n drives the shrinkage weight).
    SELECT
      b.user_id,
      date_trunc(''minute'', b.received_at) AS at_minute
    FROM public.behavior_pings AS b
    WHERE b.ingest_version = 2
      AND abs(extract(epoch FROM (b.received_at - b.at))) <= 300
      AND b.received_at >= _window_starts
      AND b.received_at < _window_ends
    GROUP BY b.user_id, date_trunc(''minute'', b.received_at)
  ), sequenced AS (
    SELECT
      events.user_id,
      events.at_minute,
      lag(events.at_minute) OVER (
        PARTITION BY events.user_id ORDER BY events.at_minute
      ) AS previous_minute
    FROM events
  ), gaps AS (
    SELECT
      sequenced.user_id,
      sequenced.previous_minute AS starts_at,
      sequenced.at_minute AS ends_at,
      extract(epoch FROM (sequenced.at_minute - sequenced.previous_minute)) / 60.0
        AS raw_minutes,
      private.account_gap_sleep_minutes(
        sequenced.user_id, sequenced.previous_minute, sequenced.at_minute
      ) AS sleep_minutes
    FROM sequenced
    WHERE sequenced.previous_minute IS NOT NULL
  ), adjusted AS (
    SELECT
      gaps.user_id,
      greatest(0, gaps.raw_minutes - gaps.sleep_minutes) AS gap_minutes,
      least(gaps.sleep_minutes, gaps.raw_minutes) AS sleep_minutes,
      EXISTS (
        SELECT 1
        FROM public.alerts AS a
        WHERE a.user_id = gaps.user_id
          AND a.opened_at < gaps.ends_at
          AND coalesce(a.resolved_at, _window_ends) > gaps.starts_at
      ) AS overlaps_alert
    FROM gaps
  ), event_stats AS (
    SELECT
      events.user_id,
      count(*)::integer AS event_count,
      count(DISTINCT events.at_minute::date)::integer AS distinct_event_days,
      min(events.at_minute) AS first_event_at,
      max(events.at_minute) AS last_event_at
    FROM events
    GROUP BY events.user_id
  ), gap_stats AS (
    SELECT
      adjusted.user_id,
      count(*)::integer AS gap_count,
      round(percentile_cont(0.5) WITHIN GROUP (
        ORDER BY adjusted.gap_minutes
      )::numeric)::integer AS personal_p50_minutes,
      round(percentile_cont(_percentile::double precision) WITHIN GROUP (
        ORDER BY adjusted.gap_minutes
      )::numeric)::integer AS personal_pctl_minutes,
      round(max(adjusted.gap_minutes)::numeric)::integer AS personal_max_minutes,
      sum(adjusted.sleep_minutes) AS sleep_minutes_removed,
      count(*) FILTER (WHERE adjusted.overlaps_alert)::integer
        AS gaps_overlapping_open_alert
    FROM adjusted
    GROUP BY adjusted.user_id
  ), subjects AS (
    SELECT
      p.id AS user_id,
      private.canonical_routine_mode(p.routine_pattern) AS cohort_key,
      coalesce(p.consent_data_sharing, false) AS consent_data_sharing,
      coalesce(event_stats.event_count, 0) AS event_count,
      coalesce(event_stats.distinct_event_days, 0) AS distinct_event_days,
      event_stats.first_event_at,
      event_stats.last_event_at,
      coalesce(gap_stats.gap_count, 0) AS gap_count,
      gap_stats.personal_p50_minutes,
      gap_stats.personal_pctl_minutes,
      gap_stats.personal_max_minutes,
      coalesce(gap_stats.sleep_minutes_removed, 0) AS sleep_minutes_removed,
      coalesce(gap_stats.gaps_overlapping_open_alert, 0)
        AS gaps_overlapping_open_alert,
      EXISTS (
        SELECT 1
        FROM public.user_settings AS s
        WHERE s.user_id = p.id
          AND s.sleep_start_local IS NOT NULL
          AND s.sleep_end_local IS NOT NULL
          AND s.sleep_start_local <> s.sleep_end_local
      ) AS sleep_window_applied
    FROM public.profiles AS p
    LEFT JOIN event_stats ON event_stats.user_id = p.id
    LEFT JOIN gap_stats ON gap_stats.user_id = p.id
  ), cohorts AS (
    -- The preset model is the median of its members'' own neutral values, so a
    -- single extreme account cannot drag the anchor. Only accounts with enough
    -- of their own evidence contribute; the thin ones are the ones being
    -- anchored, and letting them vote would be circular.
    SELECT
      subjects.cohort_key,
      count(*)::integer AS contributor_count,
      round(percentile_cont(0.5) WITHIN GROUP (
        ORDER BY subjects.personal_pctl_minutes
      )::numeric)::integer AS cohort_pctl_minutes
    FROM subjects
    WHERE subjects.personal_pctl_minutes IS NOT NULL
      AND subjects.gap_count >= _cohort_min_gaps
      AND (NOT _cohort_requires_consent OR subjects.consent_data_sharing)
    GROUP BY subjects.cohort_key
  ), resolved AS (
    SELECT
      subjects.*,
      CASE
        WHEN cohorts.contributor_count >= _cohort_min_contributors
          THEN cohorts.cohort_pctl_minutes
        ELSE _cohort_fallback_minutes
      END AS cohort_pctl_minutes,
      coalesce(cohorts.contributor_count, 0) AS cohort_contributor_count,
      CASE
        WHEN cohorts.contributor_count >= _cohort_min_contributors
          THEN ''cohort''
        ELSE ''fallback''
      END AS cohort_source,
      -- ADR-0035: robustness comes from this weight and nothing else. There is
      -- deliberately no ceiling clamp anywhere in this statement.
      CASE
        WHEN subjects.personal_pctl_minutes IS NULL THEN 0::double precision
        ELSE subjects.gap_count::double precision
             / (subjects.gap_count + _shrinkage_k)::double precision
      END AS blend_weight
    FROM subjects
    LEFT JOIN cohorts ON cohorts.cohort_key = subjects.cohort_key
  )
  INSERT INTO public.account_gap_profiles AS target (
    user_id, through_date, lookback_days, shrinkage_k, percentile,
    computed_at, window_starts_at, window_ends_at,
    event_count, gap_count, distinct_event_days, first_event_at, last_event_at,
    sleep_window_applied, sleep_minutes_removed,
    personal_p50_minutes, personal_pctl_minutes, personal_max_minutes,
    cohort_key, cohort_pctl_minutes, cohort_contributor_count, cohort_source,
    blend_weight, blended_pctl_minutes, gaps_overlapping_open_alert
  )
  SELECT
    resolved.user_id, _date, _lookback_days, _shrinkage_k, _percentile,
    clock_timestamp(), _window_starts, _window_ends,
    resolved.event_count, resolved.gap_count, resolved.distinct_event_days,
    resolved.first_event_at, resolved.last_event_at,
    resolved.sleep_window_applied, resolved.sleep_minutes_removed,
    resolved.personal_p50_minutes, resolved.personal_pctl_minutes,
    resolved.personal_max_minutes,
    resolved.cohort_key, resolved.cohort_pctl_minutes,
    resolved.cohort_contributor_count, resolved.cohort_source,
    resolved.blend_weight,
    round((
      resolved.blend_weight * coalesce(resolved.personal_pctl_minutes, 0)
      + (1 - resolved.blend_weight) * resolved.cohort_pctl_minutes
    )::numeric)::integer,
    resolved.gaps_overlapping_open_alert
  FROM resolved
  ON CONFLICT (user_id, through_date, lookback_days, shrinkage_k, percentile)
  DO UPDATE SET
    computed_at = EXCLUDED.computed_at,
    window_starts_at = EXCLUDED.window_starts_at,
    window_ends_at = EXCLUDED.window_ends_at,
    event_count = EXCLUDED.event_count,
    gap_count = EXCLUDED.gap_count,
    distinct_event_days = EXCLUDED.distinct_event_days,
    first_event_at = EXCLUDED.first_event_at,
    last_event_at = EXCLUDED.last_event_at,
    sleep_window_applied = EXCLUDED.sleep_window_applied,
    sleep_minutes_removed = EXCLUDED.sleep_minutes_removed,
    personal_p50_minutes = EXCLUDED.personal_p50_minutes,
    personal_pctl_minutes = EXCLUDED.personal_pctl_minutes,
    personal_max_minutes = EXCLUDED.personal_max_minutes,
    cohort_key = EXCLUDED.cohort_key,
    cohort_pctl_minutes = EXCLUDED.cohort_pctl_minutes,
    cohort_contributor_count = EXCLUDED.cohort_contributor_count,
    cohort_source = EXCLUDED.cohort_source,
    blend_weight = EXCLUDED.blend_weight,
    blended_pctl_minutes = EXCLUDED.blended_pctl_minutes,
    gaps_overlapping_open_alert = EXCLUDED.gaps_overlapping_open_alert;

  GET DIAGNOSTICS _written = ROW_COUNT;

  RETURN jsonb_build_object(
    ''through_date'', _date,
    ''lookback_days'', _lookback_days,
    ''shrinkage_k'', _shrinkage_k,
    ''percentile'', _percentile,
    ''cohort_min_gaps'', _cohort_min_gaps,
    ''cohort_min_contributors'', _cohort_min_contributors,
    ''cohort_fallback_minutes'', _cohort_fallback_minutes,
    ''cohort_requires_consent'', _cohort_requires_consent,
    ''window_starts_at'', _window_starts,
    ''window_ends_at'', _window_ends,
    ''profiles_written'', _written
  );
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION private.rebuild_account_gap_profiles(
  date, integer, integer, numeric, integer, integer, integer, boolean
) FROM PUBLIC, anon, authenticated, service_role;"}', 'account_gap_profile', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260802140036', '{"-- Brings production in line with the corrected
-- supabase/migrations/20260802193000_account_gap_profile.sql.
--
-- The first draft computed the sleep overlap through a per-gap helper
-- function. At production volume that is one user_settings lookup and one
-- timezone-catalogue scan per gap, and the rebuild did not finish. The rule is
-- now expressed once, set-based, inside the rebuild. The helper is removed so
-- that one rule does not end up with two implementations.
--
-- Behaviour is otherwise identical, and nothing reads these objects yet.

DROP FUNCTION IF EXISTS private.account_gap_sleep_minutes(uuid, timestamptz, timestamptz);

CREATE OR REPLACE FUNCTION private.rebuild_account_gap_profiles(
  _through_date date DEFAULT NULL,
  _lookback_days integer DEFAULT 30,
  _shrinkage_k integer DEFAULT 50,
  _percentile numeric DEFAULT 0.95,
  _cohort_min_gaps integer DEFAULT 30,
  _cohort_min_contributors integer DEFAULT 2,
  _cohort_fallback_minutes integer DEFAULT 90,
  _cohort_requires_consent boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET TimeZone = ''UTC''
AS $$
DECLARE
  _date date := coalesce(_through_date, (now() AT TIME ZONE ''UTC'')::date);
  _window_ends timestamptz;
  _window_starts timestamptz;
  _written integer := 0;
BEGIN
  IF _lookback_days IS NULL OR _lookback_days <= 0
     OR _shrinkage_k IS NULL OR _shrinkage_k < 0
     OR _percentile IS NULL OR _percentile <= 0 OR _percentile >= 1
     OR _cohort_min_gaps IS NULL OR _cohort_min_gaps < 0
     OR _cohort_min_contributors IS NULL OR _cohort_min_contributors < 1
     OR _cohort_fallback_minutes IS NULL OR _cohort_fallback_minutes < 0 THEN
    RAISE EXCEPTION ''rebuild_account_gap_profiles: invalid parameters'';
  END IF;

  _window_ends := (_date + 1)::timestamptz;
  _window_starts := _window_ends - pg_catalog.make_interval(days => _lookback_days);

  WITH events AS (
    -- One account, every device, deduplicated to the minute so that a device
    -- that reports twice in the same minute does not buy the account extra
    -- apparent evidence (n drives the shrinkage weight).
    SELECT
      b.user_id,
      date_trunc(''minute'', b.received_at) AS at_minute
    FROM public.behavior_pings AS b
    WHERE b.ingest_version = 2
      AND abs(extract(epoch FROM (b.received_at - b.at))) <= 300
      AND b.received_at >= _window_starts
      AND b.received_at < _window_ends
    GROUP BY b.user_id, date_trunc(''minute'', b.received_at)
  ), sequenced AS (
    SELECT
      events.user_id,
      events.at_minute,
      lag(events.at_minute) OVER (
        PARTITION BY events.user_id ORDER BY events.at_minute
      ) AS previous_minute
    FROM events
  ), sleep_windows AS (
    -- Resolved once per account. An unusable timezone means no subtraction at
    -- all, which leaves the gap at its full length: the safe direction.
    SELECT
      s.user_id,
      s.sleep_start_local AS starts_local,
      s.sleep_end_local AS ends_local,
      coalesce(s.timezone, ''UTC'') AS timezone
    FROM public.user_settings AS s
    WHERE s.sleep_start_local IS NOT NULL
      AND s.sleep_end_local IS NOT NULL
      AND s.sleep_start_local <> s.sleep_end_local
      AND EXISTS (
        SELECT 1
        FROM pg_catalog.pg_timezone_names AS z
        WHERE z.name = coalesce(s.timezone, ''UTC'')
      )
  ), gaps AS (
    SELECT
      sequenced.user_id,
      sequenced.previous_minute AS starts_at,
      sequenced.at_minute AS ends_at,
      extract(epoch FROM (sequenced.at_minute - sequenced.previous_minute)) / 60.0
        AS raw_minutes,
      coalesce(sleep.minutes, 0) AS sleep_minutes
    FROM sequenced
    LEFT JOIN sleep_windows ON sleep_windows.user_id = sequenced.user_id
    LEFT JOIN LATERAL (
      -- The nightly window is materialised per calendar day in the account''s
      -- own timezone, so a DST shift moves the window with the wall clock.
      SELECT sum(greatest(0, extract(epoch FROM (
               least(sequenced.at_minute, night.ends_at)
               - greatest(sequenced.previous_minute, night.starts_at)
             )))) / 60.0 AS minutes
      FROM (
        SELECT
          ((day.d + sleep_windows.starts_local) AT TIME ZONE sleep_windows.timezone)
            AS starts_at,
          ((
            day.d
            + CASE
                WHEN sleep_windows.ends_local <= sleep_windows.starts_local
                THEN 1 ELSE 0
              END
            + sleep_windows.ends_local
          ) AT TIME ZONE sleep_windows.timezone) AS ends_at
        FROM (
          SELECT generate.value::date AS d
          FROM pg_catalog.generate_series(
            ((sequenced.previous_minute AT TIME ZONE sleep_windows.timezone)::date - 1)::timestamp,
            ((sequenced.at_minute AT TIME ZONE sleep_windows.timezone)::date + 1)::timestamp,
            interval ''1 day''
          ) AS generate(value)
        ) AS day
      ) AS night
    ) AS sleep ON true
    WHERE sequenced.previous_minute IS NOT NULL
  ), adjusted AS (
    SELECT
      gaps.user_id,
      greatest(0, gaps.raw_minutes - gaps.sleep_minutes) AS gap_minutes,
      least(gaps.sleep_minutes, gaps.raw_minutes) AS sleep_minutes,
      EXISTS (
        SELECT 1
        FROM public.alerts AS a
        WHERE a.user_id = gaps.user_id
          AND a.opened_at < gaps.ends_at
          AND coalesce(a.resolved_at, _window_ends) > gaps.starts_at
      ) AS overlaps_alert
    FROM gaps
  ), event_stats AS (
    SELECT
      events.user_id,
      count(*)::integer AS event_count,
      count(DISTINCT events.at_minute::date)::integer AS distinct_event_days,
      min(events.at_minute) AS first_event_at,
      max(events.at_minute) AS last_event_at
    FROM events
    GROUP BY events.user_id
  ), gap_stats AS (
    SELECT
      adjusted.user_id,
      count(*)::integer AS gap_count,
      round(percentile_cont(0.5) WITHIN GROUP (
        ORDER BY adjusted.gap_minutes
      )::numeric)::integer AS personal_p50_minutes,
      round(percentile_cont(_percentile::double precision) WITHIN GROUP (
        ORDER BY adjusted.gap_minutes
      )::numeric)::integer AS personal_pctl_minutes,
      round(max(adjusted.gap_minutes)::numeric)::integer AS personal_max_minutes,
      sum(adjusted.sleep_minutes) AS sleep_minutes_removed,
      count(*) FILTER (WHERE adjusted.overlaps_alert)::integer
        AS gaps_overlapping_open_alert
    FROM adjusted
    GROUP BY adjusted.user_id
  ), subjects AS (
    SELECT
      p.id AS user_id,
      private.canonical_routine_mode(p.routine_pattern) AS cohort_key,
      coalesce(p.consent_data_sharing, false) AS consent_data_sharing,
      coalesce(event_stats.event_count, 0) AS event_count,
      coalesce(event_stats.distinct_event_days, 0) AS distinct_event_days,
      event_stats.first_event_at,
      event_stats.last_event_at,
      coalesce(gap_stats.gap_count, 0) AS gap_count,
      gap_stats.personal_p50_minutes,
      gap_stats.personal_pctl_minutes,
      gap_stats.personal_max_minutes,
      coalesce(gap_stats.sleep_minutes_removed, 0) AS sleep_minutes_removed,
      coalesce(gap_stats.gaps_overlapping_open_alert, 0)
        AS gaps_overlapping_open_alert,
      EXISTS (
        SELECT 1
        FROM public.user_settings AS s
        WHERE s.user_id = p.id
          AND s.sleep_start_local IS NOT NULL
          AND s.sleep_end_local IS NOT NULL
          AND s.sleep_start_local <> s.sleep_end_local
      ) AS sleep_window_applied
    FROM public.profiles AS p
    LEFT JOIN event_stats ON event_stats.user_id = p.id
    LEFT JOIN gap_stats ON gap_stats.user_id = p.id
  ), cohorts AS (
    -- The preset model is the median of its members'' own neutral values, so a
    -- single extreme account cannot drag the anchor. Only accounts with enough
    -- of their own evidence contribute; the thin ones are the ones being
    -- anchored, and letting them vote would be circular.
    SELECT
      subjects.cohort_key,
      count(*)::integer AS contributor_count,
      round(percentile_cont(0.5) WITHIN GROUP (
        ORDER BY subjects.personal_pctl_minutes
      )::numeric)::integer AS cohort_pctl_minutes
    FROM subjects
    WHERE subjects.personal_pctl_minutes IS NOT NULL
      AND subjects.gap_count >= _cohort_min_gaps
      AND (NOT _cohort_requires_consent OR subjects.consent_data_sharing)
    GROUP BY subjects.cohort_key
  ), resolved AS (
    SELECT
      subjects.*,
      CASE
        WHEN cohorts.contributor_count >= _cohort_min_contributors
          THEN cohorts.cohort_pctl_minutes
        ELSE _cohort_fallback_minutes
      END AS cohort_pctl_minutes,
      coalesce(cohorts.contributor_count, 0) AS cohort_contributor_count,
      CASE
        WHEN cohorts.contributor_count >= _cohort_min_contributors
          THEN ''cohort''
        ELSE ''fallback''
      END AS cohort_source,
      -- ADR-0035: robustness comes from this weight and nothing else. There is
      -- deliberately no ceiling clamp anywhere in this statement.
      CASE
        WHEN subjects.personal_pctl_minutes IS NULL THEN 0::double precision
        ELSE subjects.gap_count::double precision
             / (subjects.gap_count + _shrinkage_k)::double precision
      END AS blend_weight
    FROM subjects
    LEFT JOIN cohorts ON cohorts.cohort_key = subjects.cohort_key
  )
  INSERT INTO public.account_gap_profiles AS target (
    user_id, through_date, lookback_days, shrinkage_k, percentile,
    computed_at, window_starts_at, window_ends_at,
    event_count, gap_count, distinct_event_days, first_event_at, last_event_at,
    sleep_window_applied, sleep_minutes_removed,
    personal_p50_minutes, personal_pctl_minutes, personal_max_minutes,
    cohort_key, cohort_pctl_minutes, cohort_contributor_count, cohort_source,
    blend_weight, blended_pctl_minutes, gaps_overlapping_open_alert
  )
  SELECT
    resolved.user_id, _date, _lookback_days, _shrinkage_k, _percentile,
    clock_timestamp(), _window_starts, _window_ends,
    resolved.event_count, resolved.gap_count, resolved.distinct_event_days,
    resolved.first_event_at, resolved.last_event_at,
    resolved.sleep_window_applied, resolved.sleep_minutes_removed,
    resolved.personal_p50_minutes, resolved.personal_pctl_minutes,
    resolved.personal_max_minutes,
    resolved.cohort_key, resolved.cohort_pctl_minutes,
    resolved.cohort_contributor_count, resolved.cohort_source,
    resolved.blend_weight,
    round((
      resolved.blend_weight * coalesce(resolved.personal_pctl_minutes, 0)
      + (1 - resolved.blend_weight) * resolved.cohort_pctl_minutes
    )::numeric)::integer,
    resolved.gaps_overlapping_open_alert
  FROM resolved
  ON CONFLICT (user_id, through_date, lookback_days, shrinkage_k, percentile)
  DO UPDATE SET
    computed_at = EXCLUDED.computed_at,
    window_starts_at = EXCLUDED.window_starts_at,
    window_ends_at = EXCLUDED.window_ends_at,
    event_count = EXCLUDED.event_count,
    gap_count = EXCLUDED.gap_count,
    distinct_event_days = EXCLUDED.distinct_event_days,
    first_event_at = EXCLUDED.first_event_at,
    last_event_at = EXCLUDED.last_event_at,
    sleep_window_applied = EXCLUDED.sleep_window_applied,
    sleep_minutes_removed = EXCLUDED.sleep_minutes_removed,
    personal_p50_minutes = EXCLUDED.personal_p50_minutes,
    personal_pctl_minutes = EXCLUDED.personal_pctl_minutes,
    personal_max_minutes = EXCLUDED.personal_max_minutes,
    cohort_key = EXCLUDED.cohort_key,
    cohort_pctl_minutes = EXCLUDED.cohort_pctl_minutes,
    cohort_contributor_count = EXCLUDED.cohort_contributor_count,
    cohort_source = EXCLUDED.cohort_source,
    blend_weight = EXCLUDED.blend_weight,
    blended_pctl_minutes = EXCLUDED.blended_pctl_minutes,
    gaps_overlapping_open_alert = EXCLUDED.gaps_overlapping_open_alert;

  GET DIAGNOSTICS _written = ROW_COUNT;

  RETURN jsonb_build_object(
    ''through_date'', _date,
    ''lookback_days'', _lookback_days,
    ''shrinkage_k'', _shrinkage_k,
    ''percentile'', _percentile,
    ''cohort_min_gaps'', _cohort_min_gaps,
    ''cohort_min_contributors'', _cohort_min_contributors,
    ''cohort_fallback_minutes'', _cohort_fallback_minutes,
    ''cohort_requires_consent'', _cohort_requires_consent,
    ''window_starts_at'', _window_starts,
    ''window_ends_at'', _window_ends,
    ''profiles_written'', _written
  );
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION private.rebuild_account_gap_profiles(
  date, integer, integer, numeric, integer, integer, integer, boolean
) FROM PUBLIC, anon, authenticated, service_role;"}', 'account_gap_profile_set_based_sleep', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260802165244', '{"-- ADR-0035 step 2: record the candidate threshold beside the live one, and
-- replay the ping history under both. Record only; see the repo file
-- supabase/migrations/20260802224500_account_threshold_shadow.sql for the full
-- rationale.

CREATE TABLE public.account_threshold_shadow (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  through_date date NOT NULL,
  lookback_days integer NOT NULL CHECK (lookback_days > 0),
  shrinkage_k integer NOT NULL CHECK (shrinkage_k >= 0),
  percentile numeric(4, 3) NOT NULL CHECK (percentile > 0 AND percentile < 1),

  computed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  window_starts_at timestamptz NOT NULL,
  window_ends_at timestamptz NOT NULL,

  -- The live loop iterates device_state rows and requires an active monitored
  -- membership, so an account failing either can raise no alert at all. Its
  -- counts here are arithmetic, not forecasts. GM mutes and the 30-minute
  -- guardian-resolution cooldown are NOT modelled; both only ever suppress, so
  -- every count below is an upper bound.
  is_alertable boolean NOT NULL,
  sleep_window_applied boolean NOT NULL,

  sensitivity text NOT NULL,
  buffer_minutes integer NOT NULL CHECK (buffer_minutes >= 0),
  neutral_floor_minutes integer NOT NULL CHECK (neutral_floor_minutes >= 0),

  neutral_minutes integer NOT NULL CHECK (neutral_minutes >= 0),
  live_threshold_minutes integer NOT NULL CHECK (live_threshold_minutes > 0),
  candidate_floored_minutes integer NOT NULL CHECK (candidate_floored_minutes > 0),
  candidate_unfloored_minutes integer NOT NULL CHECK (candidate_unfloored_minutes > 0),

  gaps_evaluated integer NOT NULL CHECK (gaps_evaluated >= 0),
  alerts_live integer NOT NULL CHECK (alerts_live >= 0),
  alerts_candidate_floored integer NOT NULL CHECK (alerts_candidate_floored >= 0),
  alerts_candidate_unfloored integer NOT NULL CHECK (alerts_candidate_unfloored >= 0),
  alerts_candidate_only integer NOT NULL CHECK (alerts_candidate_only >= 0),
  alerts_live_only integer NOT NULL CHECK (alerts_live_only >= 0),

  earliest_divergence_at timestamptz,
  earliest_divergence_gap_minutes integer CHECK (earliest_divergence_gap_minutes >= 0),
  longest_candidate_only_gap_minutes integer CHECK (longest_candidate_only_gap_minutes >= 0),

  PRIMARY KEY (user_id, through_date, lookback_days, shrinkage_k, percentile),
  CHECK (window_ends_at > window_starts_at),
  CHECK (candidate_floored_minutes >= candidate_unfloored_minutes),
  CHECK (alerts_candidate_floored <= gaps_evaluated),
  CHECK (alerts_live <= gaps_evaluated)
);

ALTER TABLE public.account_threshold_shadow ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.account_threshold_shadow
FROM PUBLIC, anon, authenticated, service_role;

CREATE INDEX account_threshold_shadow_through_date_idx
  ON public.account_threshold_shadow (through_date DESC, user_id);

CREATE FUNCTION private.record_account_threshold_shadow(
  _through_date date DEFAULT NULL,
  _lookback_days integer DEFAULT 30,
  _shrinkage_k integer DEFAULT 50,
  _percentile numeric DEFAULT 0.95,
  _buffer_high integer DEFAULT 0,
  _buffer_balanced integer DEFAULT 45,
  _buffer_low integer DEFAULT 90,
  _neutral_floor_minutes integer DEFAULT 90,
  _post_wake_grace_minutes integer DEFAULT 120
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET TimeZone = ''UTC''
AS $$
DECLARE
  _date date := coalesce(_through_date, (now() AT TIME ZONE ''UTC'')::date);
  _window_ends timestamptz;
  _window_starts timestamptz;
  _written integer := 0;
BEGIN
  IF _lookback_days IS NULL OR _lookback_days <= 0
     OR _shrinkage_k IS NULL OR _shrinkage_k < 0
     OR _percentile IS NULL OR _percentile <= 0 OR _percentile >= 1
     OR _buffer_high IS NULL OR _buffer_high < 0
     OR _buffer_balanced IS NULL OR _buffer_balanced < 0
     OR _buffer_low IS NULL OR _buffer_low < 0
     OR _neutral_floor_minutes IS NULL OR _neutral_floor_minutes < 0
     OR _post_wake_grace_minutes IS NULL OR _post_wake_grace_minutes < 0 THEN
    RAISE EXCEPTION ''record_account_threshold_shadow: invalid parameters'';
  END IF;

  _window_ends := (_date + 1)::timestamptz;
  _window_starts := _window_ends - pg_catalog.make_interval(days => _lookback_days);

  WITH subjects AS (
    SELECT
      profile.user_id,
      profile.blended_pctl_minutes AS neutral_minutes,
      profile.sleep_window_applied,
      coalesce(settings.sensitivity, ''balanced'') AS sensitivity,
      CASE coalesce(settings.sensitivity, ''balanced'')
        WHEN ''high'' THEN _buffer_high
        WHEN ''low'' THEN _buffer_low
        ELSE _buffer_balanced
      END AS buffer_minutes,
      round(
        extract(epoch FROM private.silence_threshold(profile.user_id)) / 60
      )::integer AS live_threshold_minutes,
      (
        EXISTS (
          SELECT 1
          FROM public.group_members AS gm
          WHERE gm.user_id = profile.user_id
            AND gm.monitored
            AND gm.status = ''active''
        )
        AND EXISTS (
          SELECT 1
          FROM public.device_state AS ds
          WHERE ds.user_id = profile.user_id
        )
      ) AS is_alertable
    FROM public.account_gap_profiles AS profile
    LEFT JOIN public.user_settings AS settings
      ON settings.user_id = profile.user_id
    WHERE profile.through_date = _date
      AND profile.lookback_days = _lookback_days
      AND profile.shrinkage_k = _shrinkage_k
      AND profile.percentile = _percentile
  ), thresholds AS (
    SELECT
      subjects.*,
      subjects.buffer_minutes
        + greatest(_neutral_floor_minutes, subjects.neutral_minutes)
        AS candidate_floored_minutes,
      greatest(1, subjects.buffer_minutes + subjects.neutral_minutes)
        AS candidate_unfloored_minutes
    FROM subjects
  ), events AS (
    SELECT
      b.user_id,
      date_trunc(''minute'', b.received_at) AS at_minute
    FROM public.behavior_pings AS b
    JOIN subjects ON subjects.user_id = b.user_id
    WHERE b.ingest_version = 2
      AND abs(extract(epoch FROM (b.received_at - b.at))) <= 300
      AND b.received_at >= _window_starts
      AND b.received_at < _window_ends
    GROUP BY b.user_id, date_trunc(''minute'', b.received_at)
  ), gaps AS (
    -- Raw elapsed time, deliberately NOT sleep-adjusted: this mirrors the live
    -- detector''s now() - last_ping, and sleep enters below as suppression.
    SELECT
      sequenced.user_id,
      sequenced.previous_minute AS starts_at,
      sequenced.at_minute AS ends_at,
      extract(epoch FROM (sequenced.at_minute - sequenced.previous_minute)) / 60.0
        AS raw_minutes
    FROM (
      SELECT
        events.user_id,
        events.at_minute,
        lag(events.at_minute) OVER (
          PARTITION BY events.user_id ORDER BY events.at_minute
        ) AS previous_minute
      FROM events
    ) AS sequenced
    WHERE sequenced.previous_minute IS NOT NULL
  ), suppression AS (
    SELECT
      s.user_id,
      ((day.d + s.sleep_start_local) AT TIME ZONE coalesce(s.timezone, ''UTC''))
        AS starts_at,
      ((
        day.d
        + CASE WHEN s.sleep_end_local <= s.sleep_start_local THEN 1 ELSE 0 END
        + s.sleep_end_local
      ) AT TIME ZONE coalesce(s.timezone, ''UTC''))
        + pg_catalog.make_interval(mins => _post_wake_grace_minutes) AS ends_at
    FROM public.user_settings AS s
    JOIN subjects ON subjects.user_id = s.user_id
    CROSS JOIN LATERAL (
      SELECT generate.value::date AS d
      FROM pg_catalog.generate_series(
        (_window_starts - interval ''2 days'')::timestamp,
        (_window_ends + interval ''1 day'')::timestamp,
        interval ''1 day''
      ) AS generate(value)
    ) AS day
    WHERE s.sleep_start_local IS NOT NULL
      AND s.sleep_end_local IS NOT NULL
      AND s.sleep_start_local <> s.sleep_end_local
      AND EXISTS (
        SELECT 1
        FROM pg_catalog.pg_timezone_names AS z
        WHERE z.name = coalesce(s.timezone, ''UTC'')
      )
  ), fired AS (
    SELECT
      gaps.user_id,
      gaps.starts_at,
      gaps.ends_at,
      gaps.raw_minutes,
      coalesce(live_push.ends_at, live_at.moment) < gaps.ends_at AS fires_live,
      coalesce(floored_push.ends_at, floored_at.moment) < gaps.ends_at
        AS fires_candidate_floored,
      coalesce(unfloored_push.ends_at, unfloored_at.moment) < gaps.ends_at
        AS fires_candidate_unfloored
    FROM gaps
    JOIN thresholds ON thresholds.user_id = gaps.user_id
    CROSS JOIN LATERAL (
      SELECT gaps.starts_at
        + pg_catalog.make_interval(mins => thresholds.live_threshold_minutes)
        AS moment
    ) AS live_at
    CROSS JOIN LATERAL (
      SELECT gaps.starts_at
        + pg_catalog.make_interval(mins => thresholds.candidate_floored_minutes)
        AS moment
    ) AS floored_at
    CROSS JOIN LATERAL (
      SELECT gaps.starts_at
        + pg_catalog.make_interval(mins => thresholds.candidate_unfloored_minutes)
        AS moment
    ) AS unfloored_at
    LEFT JOIN LATERAL (
      SELECT max(suppression.ends_at) AS ends_at
      FROM suppression
      WHERE suppression.user_id = gaps.user_id
        AND suppression.starts_at <= live_at.moment
        AND suppression.ends_at > live_at.moment
    ) AS live_push ON true
    LEFT JOIN LATERAL (
      SELECT max(suppression.ends_at) AS ends_at
      FROM suppression
      WHERE suppression.user_id = gaps.user_id
        AND suppression.starts_at <= floored_at.moment
        AND suppression.ends_at > floored_at.moment
    ) AS floored_push ON true
    LEFT JOIN LATERAL (
      SELECT max(suppression.ends_at) AS ends_at
      FROM suppression
      WHERE suppression.user_id = gaps.user_id
        AND suppression.starts_at <= unfloored_at.moment
        AND suppression.ends_at > unfloored_at.moment
    ) AS unfloored_push ON true
  ), tallied AS (
    SELECT
      fired.user_id,
      count(*)::integer AS gaps_evaluated,
      count(*) FILTER (WHERE fired.fires_live)::integer AS alerts_live,
      count(*) FILTER (WHERE fired.fires_candidate_floored)::integer
        AS alerts_candidate_floored,
      count(*) FILTER (WHERE fired.fires_candidate_unfloored)::integer
        AS alerts_candidate_unfloored,
      count(*) FILTER (
        WHERE fired.fires_candidate_floored AND NOT fired.fires_live
      )::integer AS alerts_candidate_only,
      count(*) FILTER (
        WHERE fired.fires_live AND NOT fired.fires_candidate_floored
      )::integer AS alerts_live_only,
      min(fired.starts_at) FILTER (
        WHERE fired.fires_candidate_floored <> fired.fires_live
      ) AS earliest_divergence_at,
      round(max(fired.raw_minutes) FILTER (
        WHERE fired.fires_candidate_floored AND NOT fired.fires_live
      )::numeric)::integer AS longest_candidate_only_gap_minutes
    FROM fired
    GROUP BY fired.user_id
  ), divergence_example AS (
    SELECT DISTINCT ON (fired.user_id)
      fired.user_id,
      round(fired.raw_minutes::numeric)::integer AS gap_minutes
    FROM fired
    WHERE fired.fires_candidate_floored <> fired.fires_live
    ORDER BY fired.user_id, fired.starts_at
  )
  INSERT INTO public.account_threshold_shadow AS target (
    user_id, through_date, lookback_days, shrinkage_k, percentile,
    computed_at, window_starts_at, window_ends_at,
    is_alertable, sleep_window_applied,
    sensitivity, buffer_minutes, neutral_floor_minutes,
    neutral_minutes, live_threshold_minutes,
    candidate_floored_minutes, candidate_unfloored_minutes,
    gaps_evaluated, alerts_live, alerts_candidate_floored,
    alerts_candidate_unfloored, alerts_candidate_only, alerts_live_only,
    earliest_divergence_at, earliest_divergence_gap_minutes,
    longest_candidate_only_gap_minutes
  )
  SELECT
    thresholds.user_id, _date, _lookback_days, _shrinkage_k, _percentile,
    clock_timestamp(), _window_starts, _window_ends,
    thresholds.is_alertable, thresholds.sleep_window_applied,
    thresholds.sensitivity, thresholds.buffer_minutes, _neutral_floor_minutes,
    thresholds.neutral_minutes, thresholds.live_threshold_minutes,
    thresholds.candidate_floored_minutes, thresholds.candidate_unfloored_minutes,
    coalesce(tallied.gaps_evaluated, 0),
    coalesce(tallied.alerts_live, 0),
    coalesce(tallied.alerts_candidate_floored, 0),
    coalesce(tallied.alerts_candidate_unfloored, 0),
    coalesce(tallied.alerts_candidate_only, 0),
    coalesce(tallied.alerts_live_only, 0),
    tallied.earliest_divergence_at,
    divergence_example.gap_minutes,
    tallied.longest_candidate_only_gap_minutes
  FROM thresholds
  LEFT JOIN tallied ON tallied.user_id = thresholds.user_id
  LEFT JOIN divergence_example ON divergence_example.user_id = thresholds.user_id
  ON CONFLICT (user_id, through_date, lookback_days, shrinkage_k, percentile)
  DO UPDATE SET
    computed_at = EXCLUDED.computed_at,
    window_starts_at = EXCLUDED.window_starts_at,
    window_ends_at = EXCLUDED.window_ends_at,
    is_alertable = EXCLUDED.is_alertable,
    sleep_window_applied = EXCLUDED.sleep_window_applied,
    sensitivity = EXCLUDED.sensitivity,
    buffer_minutes = EXCLUDED.buffer_minutes,
    neutral_floor_minutes = EXCLUDED.neutral_floor_minutes,
    neutral_minutes = EXCLUDED.neutral_minutes,
    live_threshold_minutes = EXCLUDED.live_threshold_minutes,
    candidate_floored_minutes = EXCLUDED.candidate_floored_minutes,
    candidate_unfloored_minutes = EXCLUDED.candidate_unfloored_minutes,
    gaps_evaluated = EXCLUDED.gaps_evaluated,
    alerts_live = EXCLUDED.alerts_live,
    alerts_candidate_floored = EXCLUDED.alerts_candidate_floored,
    alerts_candidate_unfloored = EXCLUDED.alerts_candidate_unfloored,
    alerts_candidate_only = EXCLUDED.alerts_candidate_only,
    alerts_live_only = EXCLUDED.alerts_live_only,
    earliest_divergence_at = EXCLUDED.earliest_divergence_at,
    earliest_divergence_gap_minutes = EXCLUDED.earliest_divergence_gap_minutes,
    longest_candidate_only_gap_minutes = EXCLUDED.longest_candidate_only_gap_minutes;

  GET DIAGNOSTICS _written = ROW_COUNT;

  RETURN jsonb_build_object(
    ''through_date'', _date,
    ''lookback_days'', _lookback_days,
    ''shrinkage_k'', _shrinkage_k,
    ''percentile'', _percentile,
    ''buffer_minutes'', jsonb_build_object(
      ''high'', _buffer_high, ''balanced'', _buffer_balanced, ''low'', _buffer_low
    ),
    ''neutral_floor_minutes'', _neutral_floor_minutes,
    ''post_wake_grace_minutes'', _post_wake_grace_minutes,
    ''window_starts_at'', _window_starts,
    ''window_ends_at'', _window_ends,
    ''rows_written'', _written
  );
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION private.record_account_threshold_shadow(
  date, integer, integer, numeric, integer, integer, integer, integer, integer
) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.dispatch_account_shadow_cycle()
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET TimeZone = ''UTC''
AS $$
DECLARE
  _k integer;
  _results jsonb := ''[]''::jsonb;
BEGIN
  FOREACH _k IN ARRAY ARRAY[25, 50, 100] LOOP
    PERFORM private.rebuild_account_gap_profiles(NULL, 30, _k, 0.95, 30, 2, 90, true);
    _results := _results || jsonb_build_array(
      private.record_account_threshold_shadow(NULL, 30, _k, 0.95)
    );
  END LOOP;

  RETURN jsonb_build_object(''runs'', _results);
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION private.dispatch_account_shadow_cycle()
FROM PUBLIC, anon, authenticated, service_role;

DO $schedule$
BEGIN
  PERFORM cron.schedule(
    ''account-shadow-cycle-v1'',
    ''37 2 * * *'',
    $cron$ SELECT private.dispatch_account_shadow_cycle(); $cron$
  );
END;
$schedule$;"}', 'account_threshold_shadow', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260802165738', '{"-- These columns count EPISODES, not alert rows: one per distinct silence that
-- would cross the rule''s threshold, however long that silence runs.
--
-- The alerts table holds far more rows than that. A single unbroken silence
-- re-alerts roughly every 30 minutes after each human resolution, because the
-- guardian-resolution cooldown expires while the user is still silent. Karma
-- Cheki has 101 silence alert rows over the same 30 days these columns score as
-- 13 episodes. Naming them alerts_* invited exactly the wrong comparison, on
-- data whose whole purpose is deciding when to wake someone''s family.

ALTER TABLE public.account_threshold_shadow
  RENAME COLUMN alerts_live TO episodes_live;
ALTER TABLE public.account_threshold_shadow
  RENAME COLUMN alerts_candidate_floored TO episodes_candidate_floored;
ALTER TABLE public.account_threshold_shadow
  RENAME COLUMN alerts_candidate_unfloored TO episodes_candidate_unfloored;
ALTER TABLE public.account_threshold_shadow
  RENAME COLUMN alerts_candidate_only TO episodes_candidate_only;
ALTER TABLE public.account_threshold_shadow
  RENAME COLUMN alerts_live_only TO episodes_live_only;

COMMENT ON TABLE public.account_threshold_shadow IS
  ''ADR-0035 step 2, record only. Episode counts compare the candidate threshold against the live one on identical gap history; they are not a reconstruction of the alerts table.'';"}', 'account_threshold_shadow_episode_naming', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260802165837', '{"-- Follow the column rename through the recorder. Body is otherwise unchanged
-- from account_threshold_shadow; only the five renamed identifiers differ.

CREATE OR REPLACE FUNCTION private.record_account_threshold_shadow(
  _through_date date DEFAULT NULL,
  _lookback_days integer DEFAULT 30,
  _shrinkage_k integer DEFAULT 50,
  _percentile numeric DEFAULT 0.95,
  _buffer_high integer DEFAULT 0,
  _buffer_balanced integer DEFAULT 45,
  _buffer_low integer DEFAULT 90,
  _neutral_floor_minutes integer DEFAULT 90,
  _post_wake_grace_minutes integer DEFAULT 120
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET TimeZone = ''UTC''
AS $$
DECLARE
  _date date := coalesce(_through_date, (now() AT TIME ZONE ''UTC'')::date);
  _window_ends timestamptz;
  _window_starts timestamptz;
  _written integer := 0;
BEGIN
  IF _lookback_days IS NULL OR _lookback_days <= 0
     OR _shrinkage_k IS NULL OR _shrinkage_k < 0
     OR _percentile IS NULL OR _percentile <= 0 OR _percentile >= 1
     OR _buffer_high IS NULL OR _buffer_high < 0
     OR _buffer_balanced IS NULL OR _buffer_balanced < 0
     OR _buffer_low IS NULL OR _buffer_low < 0
     OR _neutral_floor_minutes IS NULL OR _neutral_floor_minutes < 0
     OR _post_wake_grace_minutes IS NULL OR _post_wake_grace_minutes < 0 THEN
    RAISE EXCEPTION ''record_account_threshold_shadow: invalid parameters'';
  END IF;

  _window_ends := (_date + 1)::timestamptz;
  _window_starts := _window_ends - pg_catalog.make_interval(days => _lookback_days);

  WITH subjects AS (
    SELECT
      profile.user_id,
      profile.blended_pctl_minutes AS neutral_minutes,
      profile.sleep_window_applied,
      coalesce(settings.sensitivity, ''balanced'') AS sensitivity,
      CASE coalesce(settings.sensitivity, ''balanced'')
        WHEN ''high'' THEN _buffer_high
        WHEN ''low'' THEN _buffer_low
        ELSE _buffer_balanced
      END AS buffer_minutes,
      round(
        extract(epoch FROM private.silence_threshold(profile.user_id)) / 60
      )::integer AS live_threshold_minutes,
      (
        EXISTS (
          SELECT 1
          FROM public.group_members AS gm
          WHERE gm.user_id = profile.user_id
            AND gm.monitored
            AND gm.status = ''active''
        )
        AND EXISTS (
          SELECT 1
          FROM public.device_state AS ds
          WHERE ds.user_id = profile.user_id
        )
      ) AS is_alertable
    FROM public.account_gap_profiles AS profile
    LEFT JOIN public.user_settings AS settings
      ON settings.user_id = profile.user_id
    WHERE profile.through_date = _date
      AND profile.lookback_days = _lookback_days
      AND profile.shrinkage_k = _shrinkage_k
      AND profile.percentile = _percentile
  ), thresholds AS (
    SELECT
      subjects.*,
      subjects.buffer_minutes
        + greatest(_neutral_floor_minutes, subjects.neutral_minutes)
        AS candidate_floored_minutes,
      greatest(1, subjects.buffer_minutes + subjects.neutral_minutes)
        AS candidate_unfloored_minutes
    FROM subjects
  ), events AS (
    SELECT
      b.user_id,
      date_trunc(''minute'', b.received_at) AS at_minute
    FROM public.behavior_pings AS b
    JOIN subjects ON subjects.user_id = b.user_id
    WHERE b.ingest_version = 2
      AND abs(extract(epoch FROM (b.received_at - b.at))) <= 300
      AND b.received_at >= _window_starts
      AND b.received_at < _window_ends
    GROUP BY b.user_id, date_trunc(''minute'', b.received_at)
  ), gaps AS (
    SELECT
      sequenced.user_id,
      sequenced.previous_minute AS starts_at,
      sequenced.at_minute AS ends_at,
      extract(epoch FROM (sequenced.at_minute - sequenced.previous_minute)) / 60.0
        AS raw_minutes
    FROM (
      SELECT
        events.user_id,
        events.at_minute,
        lag(events.at_minute) OVER (
          PARTITION BY events.user_id ORDER BY events.at_minute
        ) AS previous_minute
      FROM events
    ) AS sequenced
    WHERE sequenced.previous_minute IS NOT NULL
  ), suppression AS (
    SELECT
      s.user_id,
      ((day.d + s.sleep_start_local) AT TIME ZONE coalesce(s.timezone, ''UTC''))
        AS starts_at,
      ((
        day.d
        + CASE WHEN s.sleep_end_local <= s.sleep_start_local THEN 1 ELSE 0 END
        + s.sleep_end_local
      ) AT TIME ZONE coalesce(s.timezone, ''UTC''))
        + pg_catalog.make_interval(mins => _post_wake_grace_minutes) AS ends_at
    FROM public.user_settings AS s
    JOIN subjects ON subjects.user_id = s.user_id
    CROSS JOIN LATERAL (
      SELECT generate.value::date AS d
      FROM pg_catalog.generate_series(
        (_window_starts - interval ''2 days'')::timestamp,
        (_window_ends + interval ''1 day'')::timestamp,
        interval ''1 day''
      ) AS generate(value)
    ) AS day
    WHERE s.sleep_start_local IS NOT NULL
      AND s.sleep_end_local IS NOT NULL
      AND s.sleep_start_local <> s.sleep_end_local
      AND EXISTS (
        SELECT 1
        FROM pg_catalog.pg_timezone_names AS z
        WHERE z.name = coalesce(s.timezone, ''UTC'')
      )
  ), fired AS (
    SELECT
      gaps.user_id,
      gaps.starts_at,
      gaps.ends_at,
      gaps.raw_minutes,
      coalesce(live_push.ends_at, live_at.moment) < gaps.ends_at AS fires_live,
      coalesce(floored_push.ends_at, floored_at.moment) < gaps.ends_at
        AS fires_candidate_floored,
      coalesce(unfloored_push.ends_at, unfloored_at.moment) < gaps.ends_at
        AS fires_candidate_unfloored
    FROM gaps
    JOIN thresholds ON thresholds.user_id = gaps.user_id
    CROSS JOIN LATERAL (
      SELECT gaps.starts_at
        + pg_catalog.make_interval(mins => thresholds.live_threshold_minutes)
        AS moment
    ) AS live_at
    CROSS JOIN LATERAL (
      SELECT gaps.starts_at
        + pg_catalog.make_interval(mins => thresholds.candidate_floored_minutes)
        AS moment
    ) AS floored_at
    CROSS JOIN LATERAL (
      SELECT gaps.starts_at
        + pg_catalog.make_interval(mins => thresholds.candidate_unfloored_minutes)
        AS moment
    ) AS unfloored_at
    LEFT JOIN LATERAL (
      SELECT max(suppression.ends_at) AS ends_at
      FROM suppression
      WHERE suppression.user_id = gaps.user_id
        AND suppression.starts_at <= live_at.moment
        AND suppression.ends_at > live_at.moment
    ) AS live_push ON true
    LEFT JOIN LATERAL (
      SELECT max(suppression.ends_at) AS ends_at
      FROM suppression
      WHERE suppression.user_id = gaps.user_id
        AND suppression.starts_at <= floored_at.moment
        AND suppression.ends_at > floored_at.moment
    ) AS floored_push ON true
    LEFT JOIN LATERAL (
      SELECT max(suppression.ends_at) AS ends_at
      FROM suppression
      WHERE suppression.user_id = gaps.user_id
        AND suppression.starts_at <= unfloored_at.moment
        AND suppression.ends_at > unfloored_at.moment
    ) AS unfloored_push ON true
  ), tallied AS (
    SELECT
      fired.user_id,
      count(*)::integer AS gaps_evaluated,
      count(*) FILTER (WHERE fired.fires_live)::integer AS episodes_live,
      count(*) FILTER (WHERE fired.fires_candidate_floored)::integer
        AS episodes_candidate_floored,
      count(*) FILTER (WHERE fired.fires_candidate_unfloored)::integer
        AS episodes_candidate_unfloored,
      count(*) FILTER (
        WHERE fired.fires_candidate_floored AND NOT fired.fires_live
      )::integer AS episodes_candidate_only,
      count(*) FILTER (
        WHERE fired.fires_live AND NOT fired.fires_candidate_floored
      )::integer AS episodes_live_only,
      min(fired.starts_at) FILTER (
        WHERE fired.fires_candidate_floored <> fired.fires_live
      ) AS earliest_divergence_at,
      round(max(fired.raw_minutes) FILTER (
        WHERE fired.fires_candidate_floored AND NOT fired.fires_live
      )::numeric)::integer AS longest_candidate_only_gap_minutes
    FROM fired
    GROUP BY fired.user_id
  ), divergence_example AS (
    SELECT DISTINCT ON (fired.user_id)
      fired.user_id,
      round(fired.raw_minutes::numeric)::integer AS gap_minutes
    FROM fired
    WHERE fired.fires_candidate_floored <> fired.fires_live
    ORDER BY fired.user_id, fired.starts_at
  )
  INSERT INTO public.account_threshold_shadow AS target (
    user_id, through_date, lookback_days, shrinkage_k, percentile,
    computed_at, window_starts_at, window_ends_at,
    is_alertable, sleep_window_applied,
    sensitivity, buffer_minutes, neutral_floor_minutes,
    neutral_minutes, live_threshold_minutes,
    candidate_floored_minutes, candidate_unfloored_minutes,
    gaps_evaluated, episodes_live, episodes_candidate_floored,
    episodes_candidate_unfloored, episodes_candidate_only, episodes_live_only,
    earliest_divergence_at, earliest_divergence_gap_minutes,
    longest_candidate_only_gap_minutes
  )
  SELECT
    thresholds.user_id, _date, _lookback_days, _shrinkage_k, _percentile,
    clock_timestamp(), _window_starts, _window_ends,
    thresholds.is_alertable, thresholds.sleep_window_applied,
    thresholds.sensitivity, thresholds.buffer_minutes, _neutral_floor_minutes,
    thresholds.neutral_minutes, thresholds.live_threshold_minutes,
    thresholds.candidate_floored_minutes, thresholds.candidate_unfloored_minutes,
    coalesce(tallied.gaps_evaluated, 0),
    coalesce(tallied.episodes_live, 0),
    coalesce(tallied.episodes_candidate_floored, 0),
    coalesce(tallied.episodes_candidate_unfloored, 0),
    coalesce(tallied.episodes_candidate_only, 0),
    coalesce(tallied.episodes_live_only, 0),
    tallied.earliest_divergence_at,
    divergence_example.gap_minutes,
    tallied.longest_candidate_only_gap_minutes
  FROM thresholds
  LEFT JOIN tallied ON tallied.user_id = thresholds.user_id
  LEFT JOIN divergence_example ON divergence_example.user_id = thresholds.user_id
  ON CONFLICT (user_id, through_date, lookback_days, shrinkage_k, percentile)
  DO UPDATE SET
    computed_at = EXCLUDED.computed_at,
    window_starts_at = EXCLUDED.window_starts_at,
    window_ends_at = EXCLUDED.window_ends_at,
    is_alertable = EXCLUDED.is_alertable,
    sleep_window_applied = EXCLUDED.sleep_window_applied,
    sensitivity = EXCLUDED.sensitivity,
    buffer_minutes = EXCLUDED.buffer_minutes,
    neutral_floor_minutes = EXCLUDED.neutral_floor_minutes,
    neutral_minutes = EXCLUDED.neutral_minutes,
    live_threshold_minutes = EXCLUDED.live_threshold_minutes,
    candidate_floored_minutes = EXCLUDED.candidate_floored_minutes,
    candidate_unfloored_minutes = EXCLUDED.candidate_unfloored_minutes,
    gaps_evaluated = EXCLUDED.gaps_evaluated,
    episodes_live = EXCLUDED.episodes_live,
    episodes_candidate_floored = EXCLUDED.episodes_candidate_floored,
    episodes_candidate_unfloored = EXCLUDED.episodes_candidate_unfloored,
    episodes_candidate_only = EXCLUDED.episodes_candidate_only,
    episodes_live_only = EXCLUDED.episodes_live_only,
    earliest_divergence_at = EXCLUDED.earliest_divergence_at,
    earliest_divergence_gap_minutes = EXCLUDED.earliest_divergence_gap_minutes,
    longest_candidate_only_gap_minutes = EXCLUDED.longest_candidate_only_gap_minutes;

  GET DIAGNOSTICS _written = ROW_COUNT;

  RETURN jsonb_build_object(
    ''through_date'', _date,
    ''lookback_days'', _lookback_days,
    ''shrinkage_k'', _shrinkage_k,
    ''percentile'', _percentile,
    ''buffer_minutes'', jsonb_build_object(
      ''high'', _buffer_high, ''balanced'', _buffer_balanced, ''low'', _buffer_low
    ),
    ''neutral_floor_minutes'', _neutral_floor_minutes,
    ''post_wake_grace_minutes'', _post_wake_grace_minutes,
    ''window_starts_at'', _window_starts,
    ''window_ends_at'', _window_ends,
    ''rows_written'', _written
  );
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION private.record_account_threshold_shadow(
  date, integer, integer, numeric, integer, integer, integer, integer, integer
) FROM PUBLIC, anon, authenticated, service_role;"}', 'account_threshold_shadow_recorder_episode_naming', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260803193000', '{"-- Multi-signal liveness sampling (KC-IOS-HEALTHWAKE-SPIKE-001 follow-on).
-- Shadow-only. Nothing here feeds alert judgement: the composite scoring cannot
-- be written until there is real data to calibrate it against.
-- Every signal column is nullable, and null means \"this device or this build
-- could not read it\" rather than \"zero\".

create table if not exists public.device_activity_samples (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  trigger text not null check (trigger in (
    ''push-wake'', ''health-wake'', ''location-relaunch'', ''foreground'', ''unlock''
  )),
  observed_at timestamptz not null,
  received_at timestamptz not null default now(),

  -- Operation-class signals: evidence a human worked the device.
  protected_data_available boolean,
  battery_level real check (battery_level is null or (battery_level >= 0 and battery_level <= 1)),
  battery_state text check (battery_state is null or battery_state in (''unknown'', ''unplugged'', ''charging'', ''full'')),
  low_power_mode boolean,
  pasteboard_change_count bigint,
  system_uptime_seconds double precision,
  other_audio_playing boolean,
  motion_variance double precision,
  motion_sample_count integer,

  -- Motion-class signals: evidence a person moved. Kept apart on purpose --
  -- a phone forgotten in a moving vehicle produces motion and no operation.
  steps_since_last_sample integer,
  floors_since_last_sample integer,
  dominant_activity text check (dominant_activity is null or dominant_activity in (
    ''stationary'', ''walking'', ''running'', ''cycling'', ''automotive'', ''unknown''
  )),
  activity_confidence smallint check (activity_confidence is null or activity_confidence between 0 and 2),

  volume_available_bytes bigint,

  client_id text,
  app_version text,
  collector_contract text not null,
  always_unlocked_suspect boolean
);

create index if not exists device_activity_samples_user_time_idx
  on public.device_activity_samples (user_id, observed_at desc);

create index if not exists device_activity_samples_trigger_idx
  on public.device_activity_samples (trigger, observed_at desc);

-- No policies on purpose: these readings are richer than anything else KC
-- stores about a device, so nothing client-side may read them back.
alter table public.device_activity_samples enable row level security;

comment on table public.device_activity_samples is
  ''Shadow-only multi-signal liveness sampling. Never feeds alert judgement. A null signal column means the device or build could not read it, not that the value was zero.'';

create or replace function private.insert_device_sample(
  _user_id uuid,
  _event_id uuid,
  _payload jsonb
) returns text
language plpgsql
security definer
set search_path to ''''
as $function$
declare
  _observed_at timestamptz;
  _received_at timestamptz := clock_timestamp();
  _trigger text;
begin
  if _user_id is null or _event_id is null or _payload is null then
    return ''invalid'';
  end if;

  _observed_at := (_payload ->> ''observed_at'')::timestamptz;
  _trigger := _payload ->> ''trigger'';

  if _observed_at is null or _trigger is null then
    return ''invalid'';
  end if;

  -- A sample claiming to be from the future is a clock problem, not evidence.
  -- No lower bound: backfilled samples are normal here and carry no
  -- live-safety authority to abuse.
  if _observed_at > _received_at + interval ''5 minutes'' then
    return ''invalid'';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(_user_id::text || '':sample:'' || _event_id::text, 0)
  );

  if exists (
    select 1 from public.device_activity_samples
    where user_id = _user_id and id = _event_id
  ) then
    return ''duplicate'';
  end if;

  insert into public.device_activity_samples (
    id, user_id, trigger, observed_at, received_at,
    protected_data_available, battery_level, battery_state, low_power_mode,
    pasteboard_change_count, system_uptime_seconds, other_audio_playing,
    motion_variance, motion_sample_count,
    steps_since_last_sample, floors_since_last_sample,
    dominant_activity, activity_confidence,
    volume_available_bytes,
    client_id, app_version, collector_contract
  ) values (
    _event_id, _user_id, _trigger, _observed_at, _received_at,
    (_payload ->> ''protected_data_available'')::boolean,
    (_payload ->> ''battery_level'')::real,
    _payload ->> ''battery_state'',
    (_payload ->> ''low_power_mode'')::boolean,
    (_payload ->> ''pasteboard_change_count'')::bigint,
    (_payload ->> ''system_uptime_seconds'')::double precision,
    (_payload ->> ''other_audio_playing'')::boolean,
    (_payload ->> ''motion_variance'')::double precision,
    (_payload ->> ''motion_sample_count'')::integer,
    (_payload ->> ''steps_since_last_sample'')::integer,
    (_payload ->> ''floors_since_last_sample'')::integer,
    _payload ->> ''dominant_activity'',
    (_payload ->> ''activity_confidence'')::smallint,
    (_payload ->> ''volume_available_bytes'')::bigint,
    _payload ->> ''client_id'',
    _payload ->> ''app_version'',
    coalesce(_payload ->> ''collector_contract'', ''unknown'')
  );

  return ''inserted'';
exception
  when check_violation or invalid_text_representation then
    -- A malformed field must not land as a half-truth; rejecting loudly keeps
    -- the null-means-unreadable contract honest.
    return ''invalid'';
end;
$function$;

revoke all on function private.insert_device_sample(uuid, uuid, jsonb) from public;

-- PostgREST can only reach the public schema, so the edge function needs this
-- thin wrapper. It takes the user id as an argument rather than reading
-- auth.uid(): the caller is a service-role function that has already resolved
-- the heartbeat token, exactly as record_behavior_ping_for_user does.
create or replace function public.record_device_sample_for_user(
  _user_id uuid,
  _event_id uuid,
  _payload jsonb
) returns text
language plpgsql
security definer
set search_path to ''''
as $function$
begin
  return private.insert_device_sample(_user_id, _event_id, _payload);
end;
$function$;

-- Only the service role calls this. A signed-in client reaching it directly
-- could write samples for itself, which would let a device manufacture its own
-- evidence trail.
revoke all on function public.record_device_sample_for_user(uuid, uuid, jsonb) from public;
revoke all on function public.record_device_sample_for_user(uuid, uuid, jsonb) from anon, authenticated;"}', 'device_activity_samples', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260804090000', '{"-- 1. Emergency GPS consent had no effect and no home. The Me screen''s switch
-- wrote localStorage and nothing read it back except the switch itself;
-- dispatchSos fetched and uploaded coordinates unconditionally, so turning the
-- consent off did not stop KC sending the user''s location. A control that
-- promises a privacy boundary and does not enforce one is worse than no control.
-- Default false: consent is given, never inferred from silence.
--
-- 2. The pasteboard counter is dropped. It returned a usable value in 9 of 56
-- field samples (iOS restricts it from a background wake), and a column named
-- pasteboard_change_count implies KC watches the clipboard — an expensive thing
-- to explain for almost no evidence.

alter table public.user_settings
  add column if not exists emergency_gps_consent boolean not null default false;

comment on column public.user_settings.emergency_gps_consent is
  ''Whether the user agreed to their coordinates being captured and shared with their circle during an SOS. Enforced in dispatchSos; false means no location is fetched at all.'';

alter table public.device_activity_samples
  drop column if exists pasteboard_change_count;

create or replace function private.insert_device_sample(
  _user_id uuid,
  _event_id uuid,
  _payload jsonb
) returns text
language plpgsql
security definer
set search_path to ''''
as $function$
declare
  _observed_at timestamptz;
  _received_at timestamptz := clock_timestamp();
  _trigger text;
begin
  if _user_id is null or _event_id is null or _payload is null then
    return ''invalid'';
  end if;

  _observed_at := (_payload ->> ''observed_at'')::timestamptz;
  _trigger := _payload ->> ''trigger'';

  if _observed_at is null or _trigger is null then
    return ''invalid'';
  end if;

  if _observed_at > _received_at + interval ''5 minutes'' then
    return ''invalid'';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(_user_id::text || '':sample:'' || _event_id::text, 0)
  );

  if exists (
    select 1 from public.device_activity_samples
    where user_id = _user_id and id = _event_id
  ) then
    return ''duplicate'';
  end if;

  insert into public.device_activity_samples (
    id, user_id, trigger, observed_at, received_at,
    protected_data_available, battery_level, battery_state, low_power_mode,
    system_uptime_seconds, other_audio_playing,
    motion_variance, motion_sample_count,
    steps_since_last_sample, floors_since_last_sample,
    dominant_activity, activity_confidence,
    volume_available_bytes,
    client_id, app_version, collector_contract
  ) values (
    _event_id, _user_id, _trigger, _observed_at, _received_at,
    (_payload ->> ''protected_data_available'')::boolean,
    (_payload ->> ''battery_level'')::real,
    _payload ->> ''battery_state'',
    (_payload ->> ''low_power_mode'')::boolean,
    (_payload ->> ''system_uptime_seconds'')::double precision,
    (_payload ->> ''other_audio_playing'')::boolean,
    (_payload ->> ''motion_variance'')::double precision,
    (_payload ->> ''motion_sample_count'')::integer,
    (_payload ->> ''steps_since_last_sample'')::integer,
    (_payload ->> ''floors_since_last_sample'')::integer,
    _payload ->> ''dominant_activity'',
    (_payload ->> ''activity_confidence'')::smallint,
    (_payload ->> ''volume_available_bytes'')::bigint,
    _payload ->> ''client_id'',
    _payload ->> ''app_version'',
    coalesce(_payload ->> ''collector_contract'', ''unknown'')
  );

  return ''inserted'';
exception
  when check_violation or invalid_text_representation then
    return ''invalid'';
end;
$function$;

revoke all on function private.insert_device_sample(uuid, uuid, jsonb) from public;"}', 'emergency_gps_consent_and_drop_pasteboard', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260804130221', '{"-- ADR-0037 (amends ADR-0035): learn each account''s own observed upper bound of
-- normal silence, with no preset bound of any kind. Record only; see the repo
-- file supabase/migrations/20260804190000_account_normal_upper_bound.sql for
-- the full rationale.

CREATE TABLE public.account_normal_bounds (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  through_date date NOT NULL,
  lookback_days integer NOT NULL CHECK (lookback_days > 0),
  false_alarm_budget numeric(5, 2) NOT NULL CHECK (false_alarm_budget >= 0),

  computed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  window_starts_at timestamptz NOT NULL,
  window_ends_at timestamptz NOT NULL,

  event_count integer NOT NULL CHECK (event_count >= 0),
  gap_count integer NOT NULL CHECK (gap_count >= 0),
  evidence_days integer NOT NULL CHECK (evidence_days >= 0),
  first_event_at timestamptz,
  last_event_at timestamptz,
  sleep_window_applied boolean NOT NULL,

  order_index integer NOT NULL CHECK (order_index >= 1),
  normal_upper_bound_minutes integer CHECK (normal_upper_bound_minutes >= 0),
  largest_gap_minutes integer CHECK (largest_gap_minutes >= 0),
  second_largest_gap_minutes integer CHECK (second_largest_gap_minutes >= 0),

  has_usable_signal boolean NOT NULL,

  sensitivity text NOT NULL,
  buffer_minutes integer NOT NULL CHECK (buffer_minutes >= 0),
  threshold_minutes integer CHECK (threshold_minutes > 0),

  live_threshold_minutes integer NOT NULL CHECK (live_threshold_minutes > 0),
  episodes_new integer NOT NULL CHECK (episodes_new >= 0),
  episodes_live integer NOT NULL CHECK (episodes_live >= 0),

  PRIMARY KEY (user_id, through_date, lookback_days, false_alarm_budget),
  CHECK (window_ends_at > window_starts_at),
  CHECK (has_usable_signal = (normal_upper_bound_minutes IS NOT NULL)),
  CHECK (has_usable_signal = (threshold_minutes IS NOT NULL))
);

ALTER TABLE public.account_normal_bounds ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.account_normal_bounds
FROM PUBLIC, anon, authenticated, service_role;

CREATE INDEX account_normal_bounds_through_date_idx
  ON public.account_normal_bounds (through_date DESC, user_id);

COMMENT ON TABLE public.account_normal_bounds IS
  ''ADR-0037. Each account''''s own observed upper bound of normal silence, learned continuously with no preset ceiling, floor, template anchor, or cohort shrinkage.'';

CREATE FUNCTION private.rebuild_account_normal_bounds(
  _through_date date DEFAULT NULL,
  _lookback_days integer DEFAULT 30,
  _false_alarm_budget numeric DEFAULT 1,
  _buffer_high integer DEFAULT 0,
  _buffer_balanced integer DEFAULT 45,
  _buffer_low integer DEFAULT 90,
  _post_wake_grace_minutes integer DEFAULT 120
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET TimeZone = ''UTC''
AS $$
DECLARE
  _date date := coalesce(_through_date, (now() AT TIME ZONE ''UTC'')::date);
  _window_ends timestamptz;
  _window_starts timestamptz;
  _written integer := 0;
BEGIN
  IF _lookback_days IS NULL OR _lookback_days <= 0
     OR _false_alarm_budget IS NULL OR _false_alarm_budget < 0
     OR _buffer_high IS NULL OR _buffer_high < 0
     OR _buffer_balanced IS NULL OR _buffer_balanced < 0
     OR _buffer_low IS NULL OR _buffer_low < 0
     OR _post_wake_grace_minutes IS NULL OR _post_wake_grace_minutes < 0 THEN
    RAISE EXCEPTION ''rebuild_account_normal_bounds: invalid parameters'';
  END IF;

  _window_ends := (_date + 1)::timestamptz;
  _window_starts := _window_ends - pg_catalog.make_interval(days => _lookback_days);

  WITH events AS (
    SELECT
      b.user_id,
      date_trunc(''minute'', b.received_at) AS at_minute
    FROM public.behavior_pings AS b
    WHERE b.ingest_version = 2
      AND abs(extract(epoch FROM (b.received_at - b.at))) <= 300
      AND b.received_at >= _window_starts
      AND b.received_at < _window_ends
    GROUP BY b.user_id, date_trunc(''minute'', b.received_at)
  ), gaps AS (
    SELECT
      sequenced.user_id,
      sequenced.previous_minute AS starts_at,
      sequenced.at_minute AS ends_at
    FROM (
      SELECT
        events.user_id,
        events.at_minute,
        lag(events.at_minute) OVER (
          PARTITION BY events.user_id ORDER BY events.at_minute
        ) AS previous_minute
      FROM events
    ) AS sequenced
    WHERE sequenced.previous_minute IS NOT NULL
  ), suppression AS (
    SELECT
      s.user_id,
      ((day.d + s.sleep_start_local) AT TIME ZONE coalesce(s.timezone, ''UTC''))
        AS starts_at,
      ((
        day.d
        + CASE WHEN s.sleep_end_local <= s.sleep_start_local THEN 1 ELSE 0 END
        + s.sleep_end_local
      ) AT TIME ZONE coalesce(s.timezone, ''UTC''))
        + pg_catalog.make_interval(mins => _post_wake_grace_minutes) AS ends_at
    FROM public.user_settings AS s
    CROSS JOIN LATERAL (
      SELECT generate.value::date AS d
      FROM pg_catalog.generate_series(
        (_window_starts - interval ''2 days'')::timestamp,
        (_window_ends + interval ''1 day'')::timestamp,
        interval ''1 day''
      ) AS generate(value)
    ) AS day
    WHERE s.sleep_start_local IS NOT NULL
      AND s.sleep_end_local IS NOT NULL
      AND s.sleep_start_local <> s.sleep_end_local
      AND EXISTS (
        SELECT 1
        FROM pg_catalog.pg_timezone_names AS z
        WHERE z.name = coalesce(s.timezone, ''UTC'')
      )
  ), escapes AS (
    SELECT
      gaps.user_id,
      greatest(0, extract(epoch FROM (
        coalesce(blocked.starts_at, gaps.ends_at) - gaps.starts_at
      )) / 60.0) AS escape_minutes
    FROM gaps
    LEFT JOIN LATERAL (
      SELECT min(suppression.starts_at) AS starts_at
      FROM suppression
      WHERE suppression.user_id = gaps.user_id
        AND suppression.starts_at <= gaps.ends_at - interval ''1 second''
        AND suppression.ends_at > gaps.ends_at - interval ''1 second''
    ) AS blocked ON true
  ), ranked AS (
    SELECT
      escapes.user_id,
      escapes.escape_minutes,
      row_number() OVER (
        PARTITION BY escapes.user_id ORDER BY escapes.escape_minutes DESC
      ) AS position
    FROM escapes
  ), evidence AS (
    SELECT
      events.user_id,
      count(*)::integer AS event_count,
      count(DISTINCT events.at_minute::date)::integer AS evidence_days,
      min(events.at_minute) AS first_event_at,
      max(events.at_minute) AS last_event_at
    FROM events
    GROUP BY events.user_id
  ), subjects AS (
    SELECT
      p.id AS user_id,
      coalesce(evidence.event_count, 0) AS event_count,
      coalesce(evidence.evidence_days, 0) AS evidence_days,
      evidence.first_event_at,
      evidence.last_event_at,
      coalesce(settings.sensitivity, ''balanced'') AS sensitivity,
      CASE coalesce(settings.sensitivity, ''balanced'')
        WHEN ''high'' THEN _buffer_high
        WHEN ''low'' THEN _buffer_low
        ELSE _buffer_balanced
      END AS buffer_minutes,
      round(
        extract(epoch FROM private.silence_threshold(p.id)) / 60
      )::integer AS live_threshold_minutes,
      EXISTS (
        SELECT 1
        FROM public.user_settings AS s
        WHERE s.user_id = p.id
          AND s.sleep_start_local IS NOT NULL
          AND s.sleep_end_local IS NOT NULL
          AND s.sleep_start_local <> s.sleep_end_local
      ) AS sleep_window_applied,
      (
        SELECT count(*)::integer FROM ranked WHERE ranked.user_id = p.id
      ) AS gap_count,
      greatest(1, 1 + round(_false_alarm_budget
        * coalesce(evidence.evidence_days, 0)::numeric / 30))::integer AS order_index
    FROM public.profiles AS p
    LEFT JOIN evidence ON evidence.user_id = p.id
    LEFT JOIN public.user_settings AS settings ON settings.user_id = p.id
  ), bounded AS (
    SELECT
      subjects.*,
      round(chosen.escape_minutes::numeric)::integer AS normal_upper_bound_minutes,
      round(largest.escape_minutes::numeric)::integer AS largest_gap_minutes,
      round(second.escape_minutes::numeric)::integer AS second_largest_gap_minutes
    FROM subjects
    LEFT JOIN ranked AS chosen
      ON chosen.user_id = subjects.user_id
     AND chosen.position = subjects.order_index
    LEFT JOIN ranked AS largest
      ON largest.user_id = subjects.user_id AND largest.position = 1
    LEFT JOIN ranked AS second
      ON second.user_id = subjects.user_id AND second.position = 2
  ), assembled AS (
    SELECT
      bounded.*,
      CASE
        WHEN bounded.normal_upper_bound_minutes IS NULL THEN NULL
        ELSE greatest(1, bounded.normal_upper_bound_minutes + bounded.buffer_minutes)
      END AS threshold_minutes
    FROM bounded
  )
  INSERT INTO public.account_normal_bounds AS target (
    user_id, through_date, lookback_days, false_alarm_budget,
    computed_at, window_starts_at, window_ends_at,
    event_count, gap_count, evidence_days, first_event_at, last_event_at,
    sleep_window_applied, order_index, normal_upper_bound_minutes,
    largest_gap_minutes, second_largest_gap_minutes, has_usable_signal,
    sensitivity, buffer_minutes, threshold_minutes,
    live_threshold_minutes, episodes_new, episodes_live
  )
  SELECT
    assembled.user_id, _date, _lookback_days, _false_alarm_budget,
    clock_timestamp(), _window_starts, _window_ends,
    assembled.event_count, assembled.gap_count, assembled.evidence_days,
    assembled.first_event_at, assembled.last_event_at,
    assembled.sleep_window_applied, assembled.order_index,
    assembled.normal_upper_bound_minutes,
    assembled.largest_gap_minutes, assembled.second_largest_gap_minutes,
    assembled.threshold_minutes IS NOT NULL,
    assembled.sensitivity, assembled.buffer_minutes, assembled.threshold_minutes,
    assembled.live_threshold_minutes,
    coalesce((
      SELECT count(*)::integer FROM ranked
      WHERE ranked.user_id = assembled.user_id
        AND assembled.threshold_minutes IS NOT NULL
        AND ranked.escape_minutes >= assembled.threshold_minutes
    ), 0),
    coalesce((
      SELECT count(*)::integer FROM ranked
      WHERE ranked.user_id = assembled.user_id
        AND ranked.escape_minutes >= assembled.live_threshold_minutes
    ), 0)
  FROM assembled
  ON CONFLICT (user_id, through_date, lookback_days, false_alarm_budget)
  DO UPDATE SET
    computed_at = EXCLUDED.computed_at,
    window_starts_at = EXCLUDED.window_starts_at,
    window_ends_at = EXCLUDED.window_ends_at,
    event_count = EXCLUDED.event_count,
    gap_count = EXCLUDED.gap_count,
    evidence_days = EXCLUDED.evidence_days,
    first_event_at = EXCLUDED.first_event_at,
    last_event_at = EXCLUDED.last_event_at,
    sleep_window_applied = EXCLUDED.sleep_window_applied,
    order_index = EXCLUDED.order_index,
    normal_upper_bound_minutes = EXCLUDED.normal_upper_bound_minutes,
    largest_gap_minutes = EXCLUDED.largest_gap_minutes,
    second_largest_gap_minutes = EXCLUDED.second_largest_gap_minutes,
    has_usable_signal = EXCLUDED.has_usable_signal,
    sensitivity = EXCLUDED.sensitivity,
    buffer_minutes = EXCLUDED.buffer_minutes,
    threshold_minutes = EXCLUDED.threshold_minutes,
    live_threshold_minutes = EXCLUDED.live_threshold_minutes,
    episodes_new = EXCLUDED.episodes_new,
    episodes_live = EXCLUDED.episodes_live;

  GET DIAGNOSTICS _written = ROW_COUNT;

  RETURN jsonb_build_object(
    ''through_date'', _date,
    ''lookback_days'', _lookback_days,
    ''false_alarm_budget'', _false_alarm_budget,
    ''post_wake_grace_minutes'', _post_wake_grace_minutes,
    ''window_starts_at'', _window_starts,
    ''window_ends_at'', _window_ends,
    ''rows_written'', _written
  );
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION private.rebuild_account_normal_bounds(
  date, integer, numeric, integer, integer, integer, integer
) FROM PUBLIC, anon, authenticated, service_role;"}', 'account_normal_upper_bound', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260804135728', '{"-- ADR-0037 step 4: the live threshold now reads the account''s own learned
-- upper bound. Authorised by the human on 2026-08-04.
--
-- Before: greatest(90/135/180 template, least(600, p95 from frozen July data
-- + buffer)). Six of nine real accounts had had no new evidence admitted since
-- 2026-07-19 and were days from silently reverting to the template outright.
-- After: the account''s own i-th largest silence plus its sensitivity buffer,
-- recomputed daily from every device it reports on, with no lease to earn and
-- no constant to clip it.
--
-- The buffer is applied here rather than baked into the stored bound, so a
-- sensitivity change takes effect immediately instead of at the next rebuild.
--
-- NULL is a real answer: an account with no usable evidence gets no silence
-- judgement rather than a fabricated one. The raise loop''s comparison then
-- yields NULL and no alert is raised. No such alert is open at deploy time.

CREATE OR REPLACE FUNCTION private.silence_threshold(_user_id uuid)
RETURNS interval
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''''
SET TimeZone = ''UTC''
AS $$
DECLARE
  _bound_minutes integer;
  _sensitivity text;
  _buffer_minutes integer;
BEGIN
  SELECT bounds.normal_upper_bound_minutes
    INTO _bound_minutes
  FROM public.account_normal_bounds AS bounds
  WHERE bounds.user_id = _user_id
    AND bounds.has_usable_signal
    AND bounds.lookback_days = 30
    AND bounds.false_alarm_budget = 1
  ORDER BY bounds.through_date DESC, bounds.computed_at DESC
  LIMIT 1;

  IF _bound_minutes IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT settings.sensitivity
    INTO _sensitivity
  FROM public.user_settings AS settings
  WHERE settings.user_id = _user_id;

  _buffer_minutes := CASE coalesce(_sensitivity, ''balanced'')
    WHEN ''high'' THEN 0
    WHEN ''sensitive'' THEN 0
    WHEN ''low'' THEN 90
    WHEN ''relaxed'' THEN 90
    ELSE 45
  END;

  RETURN pg_catalog.make_interval(mins => _bound_minutes + _buffer_minutes);
END;
$$;

REVOKE EXECUTE ON FUNCTION private.silence_threshold(uuid)
FROM PUBLIC, anon, authenticated, service_role;"}', 'silence_threshold_reads_normal_bounds', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260804142350', '{"-- Human authorised on 2026-08-04. The nightly job must maintain the table the
-- live threshold reads, or every account''s learned bound freezes at today''s
-- value. Same job name and schedule; only the command changes.
DO $schedule$
BEGIN
  PERFORM cron.schedule(
    ''account-shadow-cycle-v1'',
    ''37 2 * * *'',
    $cron$ SELECT private.rebuild_account_normal_bounds(); $cron$
  );
END;
$schedule$;"}', 'nightly_job_maintains_normal_bounds', 'vinz.a.studio@gmail.com', NULL, NULL),
	('20260804190000', '{"-- ADR-0037 (amends ADR-0035): learn each account''s own observed upper bound of
-- normal silence, with no preset bound of any kind.
--
-- Why this replaces the p95 profile
--   p95 is not an upper bound. Its definition is \"five percent of this
--   account''s ordinary silences cross this line\", so on a dense account it
--   fires tens of times a month by construction. Production 2026-08-04: of the
--   180 real silence alerts since 07-20, 12 would have fired had each account
--   been measured against its own upper bound instead.
--
-- The quantity being learned
--   For each silence, `escape_minutes` is the largest threshold that would
--   still have raised an alert on it: the distance from the silence''s start to
--   the last instant before it ended at which the detector was actually allowed
--   to act. Sleep and its post-wake grace are baked in, because they are what
--   decides whether the detector could act, not a separate correction.
--
--   Setting the threshold above an account''s i-th largest escape_minutes means
--   at most i-1 of its silences would have alerted. That makes the tolerated
--   false-alarm rate the only policy input, and the account''s own history the
--   only data input.
--
-- What is deliberately absent
--   No ceiling. No floor. No template anchor. No cohort shrinkage. No sample
--   threshold that flips a profile between valid and invalid. No coverage
--   lease. If any constant reappears in this file bounding what an account may
--   be, it is a defect: ADR-0037 exists because three such constants (the
--   90/135/180 template, the 600-minute ceiling, a proposed 90-minute floor)
--   between them ensured nothing learned ever reached a decision.
--
-- Thin evidence widens, never tightens
--   The order index scales with how many days of evidence exist, so an account
--   we have barely observed sits further out rather than closer in. We do not
--   pretend to know someone''s upper bound before we have seen their long days.
--   Skipping the largest gap once evidence allows also means one outage cannot
--   teach the model that an account is slow.
--
-- Still record-only. private.silence_threshold is not touched here.

CREATE TABLE public.account_normal_bounds (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  through_date date NOT NULL,
  lookback_days integer NOT NULL CHECK (lookback_days > 0),
  -- Tolerated false alarms per 30 days. A policy input about us, not an
  -- assumption about the user.
  false_alarm_budget numeric(5, 2) NOT NULL CHECK (false_alarm_budget >= 0),

  computed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  window_starts_at timestamptz NOT NULL,
  window_ends_at timestamptz NOT NULL,

  event_count integer NOT NULL CHECK (event_count >= 0),
  gap_count integer NOT NULL CHECK (gap_count >= 0),
  evidence_days integer NOT NULL CHECK (evidence_days >= 0),
  first_event_at timestamptz,
  last_event_at timestamptz,
  sleep_window_applied boolean NOT NULL,

  order_index integer NOT NULL CHECK (order_index >= 1),
  normal_upper_bound_minutes integer CHECK (normal_upper_bound_minutes >= 0),
  largest_gap_minutes integer CHECK (largest_gap_minutes >= 0),
  second_largest_gap_minutes integer CHECK (second_largest_gap_minutes >= 0),

  -- False when the account has not produced enough silences to have an upper
  -- bound at this order index. We say so instead of inventing a number.
  has_usable_signal boolean NOT NULL,

  sensitivity text NOT NULL,
  buffer_minutes integer NOT NULL CHECK (buffer_minutes >= 0),
  threshold_minutes integer CHECK (threshold_minutes > 0),

  live_threshold_minutes integer NOT NULL CHECK (live_threshold_minutes > 0),
  episodes_new integer NOT NULL CHECK (episodes_new >= 0),
  episodes_live integer NOT NULL CHECK (episodes_live >= 0),

  PRIMARY KEY (user_id, through_date, lookback_days, false_alarm_budget),
  CHECK (window_ends_at > window_starts_at),
  CHECK (has_usable_signal = (normal_upper_bound_minutes IS NOT NULL)),
  CHECK (has_usable_signal = (threshold_minutes IS NOT NULL))
)","ALTER TABLE public.account_normal_bounds ENABLE ROW LEVEL SECURITY","REVOKE ALL PRIVILEGES ON TABLE public.account_normal_bounds
FROM PUBLIC, anon, authenticated, service_role","CREATE INDEX account_normal_bounds_through_date_idx
  ON public.account_normal_bounds (through_date DESC, user_id)","COMMENT ON TABLE public.account_normal_bounds IS
  ''ADR-0037. Each account''''s own observed upper bound of normal silence, learned continuously with no preset ceiling, floor, template anchor, or cohort shrinkage.''","CREATE FUNCTION private.rebuild_account_normal_bounds(
  _through_date date DEFAULT NULL,
  _lookback_days integer DEFAULT 30,
  _false_alarm_budget numeric DEFAULT 1,
  _buffer_high integer DEFAULT 0,
  _buffer_balanced integer DEFAULT 45,
  _buffer_low integer DEFAULT 90,
  _post_wake_grace_minutes integer DEFAULT 120
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''''
SET TimeZone = ''UTC''
AS $$
DECLARE
  _date date := coalesce(_through_date, (now() AT TIME ZONE ''UTC'')::date);
  _window_ends timestamptz;
  _window_starts timestamptz;
  _written integer := 0;
BEGIN
  IF _lookback_days IS NULL OR _lookback_days <= 0
     OR _false_alarm_budget IS NULL OR _false_alarm_budget < 0
     OR _buffer_high IS NULL OR _buffer_high < 0
     OR _buffer_balanced IS NULL OR _buffer_balanced < 0
     OR _buffer_low IS NULL OR _buffer_low < 0
     OR _post_wake_grace_minutes IS NULL OR _post_wake_grace_minutes < 0 THEN
    RAISE EXCEPTION ''rebuild_account_normal_bounds: invalid parameters'';
  END IF;

  _window_ends := (_date + 1)::timestamptz;
  _window_starts := _window_ends - pg_catalog.make_interval(days => _lookback_days);

  WITH events AS (
    -- Every device on the account, one stream, deduplicated to the minute.
    -- The live detector''s own predicate and nothing else: no coverage lease,
    -- no observation attestation.
    SELECT
      b.user_id,
      date_trunc(''minute'', b.received_at) AS at_minute
    FROM public.behavior_pings AS b
    WHERE b.ingest_version = 2
      AND abs(extract(epoch FROM (b.received_at - b.at))) <= 300
      AND b.received_at >= _window_starts
      AND b.received_at < _window_ends
    GROUP BY b.user_id, date_trunc(''minute'', b.received_at)
  ), gaps AS (
    SELECT
      sequenced.user_id,
      sequenced.previous_minute AS starts_at,
      sequenced.at_minute AS ends_at
    FROM (
      SELECT
        events.user_id,
        events.at_minute,
        lag(events.at_minute) OVER (
          PARTITION BY events.user_id ORDER BY events.at_minute
        ) AS previous_minute
      FROM events
    ) AS sequenced
    WHERE sequenced.previous_minute IS NOT NULL
  ), suppression AS (
    -- The window in which private.sleep_relaxed forbids the detector to act.
    SELECT
      s.user_id,
      ((day.d + s.sleep_start_local) AT TIME ZONE coalesce(s.timezone, ''UTC''))
        AS starts_at,
      ((
        day.d
        + CASE WHEN s.sleep_end_local <= s.sleep_start_local THEN 1 ELSE 0 END
        + s.sleep_end_local
      ) AT TIME ZONE coalesce(s.timezone, ''UTC''))
        + pg_catalog.make_interval(mins => _post_wake_grace_minutes) AS ends_at
    FROM public.user_settings AS s
    CROSS JOIN LATERAL (
      SELECT generate.value::date AS d
      FROM pg_catalog.generate_series(
        (_window_starts - interval ''2 days'')::timestamp,
        (_window_ends + interval ''1 day'')::timestamp,
        interval ''1 day''
      ) AS generate(value)
    ) AS day
    WHERE s.sleep_start_local IS NOT NULL
      AND s.sleep_end_local IS NOT NULL
      AND s.sleep_start_local <> s.sleep_end_local
      AND EXISTS (
        SELECT 1
        FROM pg_catalog.pg_timezone_names AS z
        WHERE z.name = coalesce(s.timezone, ''UTC'')
      )
  ), escapes AS (
    -- The largest threshold that would still have alerted on this silence.
    -- If the silence ended while the detector was suppressed, the last instant
    -- it could have acted is the start of that suppression window.
    SELECT
      gaps.user_id,
      greatest(0, extract(epoch FROM (
        coalesce(blocked.starts_at, gaps.ends_at) - gaps.starts_at
      )) / 60.0) AS escape_minutes
    FROM gaps
    LEFT JOIN LATERAL (
      SELECT min(suppression.starts_at) AS starts_at
      FROM suppression
      WHERE suppression.user_id = gaps.user_id
        AND suppression.starts_at <= gaps.ends_at - interval ''1 second''
        AND suppression.ends_at > gaps.ends_at - interval ''1 second''
    ) AS blocked ON true
  ), ranked AS (
    SELECT
      escapes.user_id,
      escapes.escape_minutes,
      row_number() OVER (
        PARTITION BY escapes.user_id ORDER BY escapes.escape_minutes DESC
      ) AS position
    FROM escapes
  ), evidence AS (
    SELECT
      events.user_id,
      count(*)::integer AS event_count,
      count(DISTINCT events.at_minute::date)::integer AS evidence_days,
      min(events.at_minute) AS first_event_at,
      max(events.at_minute) AS last_event_at
    FROM events
    GROUP BY events.user_id
  ), subjects AS (
    SELECT
      p.id AS user_id,
      coalesce(evidence.event_count, 0) AS event_count,
      coalesce(evidence.evidence_days, 0) AS evidence_days,
      evidence.first_event_at,
      evidence.last_event_at,
      coalesce(settings.sensitivity, ''balanced'') AS sensitivity,
      CASE coalesce(settings.sensitivity, ''balanced'')
        WHEN ''high'' THEN _buffer_high
        WHEN ''low'' THEN _buffer_low
        ELSE _buffer_balanced
      END AS buffer_minutes,
      round(
        extract(epoch FROM private.silence_threshold(p.id)) / 60
      )::integer AS live_threshold_minutes,
      EXISTS (
        SELECT 1
        FROM public.user_settings AS s
        WHERE s.user_id = p.id
          AND s.sleep_start_local IS NOT NULL
          AND s.sleep_end_local IS NOT NULL
          AND s.sleep_start_local <> s.sleep_end_local
      ) AS sleep_window_applied,
      (
        SELECT count(*)::integer FROM ranked WHERE ranked.user_id = p.id
      ) AS gap_count,
      -- Thin evidence pulls the index down, which pushes the bound outward.
      -- Two terms. The budget term grows the index as evidence accumulates.
      -- The outage guard keeps the index at 2 or more as soon as there are
      -- enough silences for a second-largest to exist, so one dead battery or
      -- one weekend without signal can never become an account''s upper bound.
      -- Ten is a guard against a single outlier, not a bound on the account.
      greatest(
        CASE
          WHEN (SELECT count(*) FROM ranked WHERE ranked.user_id = p.id) >= 10
          THEN 2 ELSE 1
        END,
        1 + round(_false_alarm_budget
          * coalesce(evidence.evidence_days, 0)::numeric / 30)
      )::integer AS order_index
    FROM public.profiles AS p
    LEFT JOIN evidence ON evidence.user_id = p.id
    LEFT JOIN public.user_settings AS settings ON settings.user_id = p.id
  ), bounded AS (
    SELECT
      subjects.*,
      round(chosen.escape_minutes::numeric)::integer AS normal_upper_bound_minutes,
      round(largest.escape_minutes::numeric)::integer AS largest_gap_minutes,
      round(second.escape_minutes::numeric)::integer AS second_largest_gap_minutes
    FROM subjects
    LEFT JOIN ranked AS chosen
      ON chosen.user_id = subjects.user_id
     AND chosen.position = subjects.order_index
    LEFT JOIN ranked AS largest
      ON largest.user_id = subjects.user_id AND largest.position = 1
    LEFT JOIN ranked AS second
      ON second.user_id = subjects.user_id AND second.position = 2
  ), assembled AS (
    SELECT
      bounded.*,
      -- The entire assembly. Nothing clamps it from either side.
      CASE
        WHEN bounded.normal_upper_bound_minutes IS NULL THEN NULL
        ELSE greatest(1, bounded.normal_upper_bound_minutes + bounded.buffer_minutes)
      END AS threshold_minutes
    FROM bounded
  )
  INSERT INTO public.account_normal_bounds AS target (
    user_id, through_date, lookback_days, false_alarm_budget,
    computed_at, window_starts_at, window_ends_at,
    event_count, gap_count, evidence_days, first_event_at, last_event_at,
    sleep_window_applied, order_index, normal_upper_bound_minutes,
    largest_gap_minutes, second_largest_gap_minutes, has_usable_signal,
    sensitivity, buffer_minutes, threshold_minutes,
    live_threshold_minutes, episodes_new, episodes_live
  )
  SELECT
    assembled.user_id, _date, _lookback_days, _false_alarm_budget,
    clock_timestamp(), _window_starts, _window_ends,
    assembled.event_count, assembled.gap_count, assembled.evidence_days,
    assembled.first_event_at, assembled.last_event_at,
    assembled.sleep_window_applied, assembled.order_index,
    assembled.normal_upper_bound_minutes,
    assembled.largest_gap_minutes, assembled.second_largest_gap_minutes,
    assembled.threshold_minutes IS NOT NULL,
    assembled.sensitivity, assembled.buffer_minutes, assembled.threshold_minutes,
    assembled.live_threshold_minutes,
    coalesce((
      SELECT count(*)::integer FROM ranked
      WHERE ranked.user_id = assembled.user_id
        AND assembled.threshold_minutes IS NOT NULL
        AND ranked.escape_minutes > assembled.threshold_minutes
    ), 0),
    coalesce((
      SELECT count(*)::integer FROM ranked
      WHERE ranked.user_id = assembled.user_id
        AND ranked.escape_minutes > assembled.live_threshold_minutes
    ), 0)
  FROM assembled
  ON CONFLICT (user_id, through_date, lookback_days, false_alarm_budget)
  DO UPDATE SET
    computed_at = EXCLUDED.computed_at,
    window_starts_at = EXCLUDED.window_starts_at,
    window_ends_at = EXCLUDED.window_ends_at,
    event_count = EXCLUDED.event_count,
    gap_count = EXCLUDED.gap_count,
    evidence_days = EXCLUDED.evidence_days,
    first_event_at = EXCLUDED.first_event_at,
    last_event_at = EXCLUDED.last_event_at,
    sleep_window_applied = EXCLUDED.sleep_window_applied,
    order_index = EXCLUDED.order_index,
    normal_upper_bound_minutes = EXCLUDED.normal_upper_bound_minutes,
    largest_gap_minutes = EXCLUDED.largest_gap_minutes,
    second_largest_gap_minutes = EXCLUDED.second_largest_gap_minutes,
    has_usable_signal = EXCLUDED.has_usable_signal,
    sensitivity = EXCLUDED.sensitivity,
    buffer_minutes = EXCLUDED.buffer_minutes,
    threshold_minutes = EXCLUDED.threshold_minutes,
    live_threshold_minutes = EXCLUDED.live_threshold_minutes,
    episodes_new = EXCLUDED.episodes_new,
    episodes_live = EXCLUDED.episodes_live;

  GET DIAGNOSTICS _written = ROW_COUNT;

  RETURN jsonb_build_object(
    ''through_date'', _date,
    ''lookback_days'', _lookback_days,
    ''false_alarm_budget'', _false_alarm_budget,
    ''post_wake_grace_minutes'', _post_wake_grace_minutes,
    ''window_starts_at'', _window_starts,
    ''window_ends_at'', _window_ends,
    ''rows_written'', _written
  );
END;
$$","REVOKE ALL PRIVILEGES ON FUNCTION private.rebuild_account_normal_bounds(
  date, integer, numeric, integer, integer, integer, integer
) FROM PUBLIC, anon, authenticated, service_role","-- ---------------------------------------------------------------------------
-- ADR-0037 step 4: the live threshold reads the learned bound.
--
-- Before: greatest(90/135/180 template, least(600, p95 from frozen July data
-- + buffer)). Six of nine real accounts had had no new evidence admitted since
-- 2026-07-19 and were days from silently reverting to the template outright.
-- After: the account''s own i-th largest silence plus its sensitivity buffer,
-- recomputed daily from every device it reports on.
--
-- The buffer is applied here rather than baked into the stored bound, so a
-- sensitivity change takes effect immediately instead of at the next rebuild.
--
-- NULL is a real answer: an account with no usable evidence gets no silence
-- judgement rather than a fabricated one. The raise loop''s comparison then
-- yields NULL and no alert is raised.
--
-- Display debt: my_routine_status and get_group_activity pass this straight to
-- the client, so threshold_seconds / threshold_hours can now be null. The
-- client multiplies that by 1000 and would render a zero threshold. Guarding
-- that display is a required follow-up.
CREATE OR REPLACE FUNCTION private.silence_threshold(_user_id uuid)
RETURNS interval
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''''
SET TimeZone = ''UTC''
AS $$
DECLARE
  _bound_minutes integer;
  _sensitivity text;
  _buffer_minutes integer;
BEGIN
  -- Deliberately no staleness cliff: if a rebuild is missed the previous
  -- day''s bound stands, because a threshold that expires into a template is
  -- the exact failure ADR-0037 exists to remove.
  SELECT bounds.normal_upper_bound_minutes
    INTO _bound_minutes
  FROM public.account_normal_bounds AS bounds
  WHERE bounds.user_id = _user_id
    AND bounds.has_usable_signal
    AND bounds.lookback_days = 30
    AND bounds.false_alarm_budget = 1
  ORDER BY bounds.through_date DESC, bounds.computed_at DESC
  LIMIT 1;

  IF _bound_minutes IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT settings.sensitivity
    INTO _sensitivity
  FROM public.user_settings AS settings
  WHERE settings.user_id = _user_id;

  _buffer_minutes := CASE coalesce(_sensitivity, ''balanced'')
    WHEN ''high'' THEN 0
    WHEN ''sensitive'' THEN 0
    WHEN ''low'' THEN 90
    WHEN ''relaxed'' THEN 90
    ELSE 45
  END;

  RETURN pg_catalog.make_interval(mins => _bound_minutes + _buffer_minutes);
END;
$$","REVOKE EXECUTE ON FUNCTION private.silence_threshold(uuid)
FROM PUBLIC, anon, authenticated, service_role","-- The nightly job must maintain the table the live threshold reads, or the
-- bound freezes. NOT YET APPLIED IN PRODUCTION: the cron change was blocked by
-- the operator permission gate on 2026-08-04 and is pending authorisation.
DO $schedule$
BEGIN
  PERFORM cron.schedule(
    ''account-shadow-cycle-v1'',
    ''37 2 * * *'',
    $cron$ SELECT private.rebuild_account_normal_bounds(); $cron$
  );
END;
$schedule$"}', 'account_normal_upper_bound', NULL, NULL, NULL),
	('20260807223000', '{"-- 2026-08-02 (20260802140000_activity_never_answers_an_alert) settled the rule:
-- the alert asks \"are you all right\", and the only shape an answer takes is the
-- subject deliberately unlocking. Passive activity proves the device is alive,
-- not that the person has answered — a very ill person propping themselves up
-- still generates activity, and they are precisely who this mechanism exists for.
--
-- That rule was applied to private.apply_liveness_side_effects. It was not
-- applied here. process_escalations'' clearance loop still carried the original
-- rule, written 2026-06-10 in 20260610142413_escalation_logic.sql as:
--
--   -- 2) 自动解除：设备已恢复正常且心跳新鲜（非 SOS）
--
-- The comment names a device. The action closed an alert about a person. That
-- conflation was never a recorded decision; it is the first version''s wording
-- surviving untouched through every later rewrite. Three copies of it existed:
-- the behavior-ping trigger (dropped 2026-07-19), apply_liveness_side_effects
-- (corrected 2026-08-02), and this one.
--
-- Production, 2026-08-07: since the 08-02 correction landed, the ping-driven
-- path has fired zero times and this loop has fired once in five days, so the
-- change removes a contradiction rather than a working behaviour.
--
-- Removed from the clearance loop:
--   * silence cleared by a fresh qualifying ping   — activity, not an answer
--   * dark_device cleared by a returning heartbeat — activity, not an answer
--
-- Kept, because it is not activity: configured sleep and the post-wake grace.
-- That branch does not accept an answer on the subject''s behalf. It withdraws an
-- alert whose premise — \"this silence is unusual\" — is false inside a window
-- where silence is exactly what is expected. It remains the only way this
-- function may close an alert; everything else must go through the subject''s own
-- unlock (public.resolve_my_alert), a responder''s confirm-safe
-- (public.resolve_alert), or GM intervention.
--
-- Nothing else in this function changes: the raise loop, the escalation loop,
-- the GM mute gate and the responder grace are reproduced verbatim.
CREATE OR REPLACE FUNCTION public.process_escalations()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''''
AS $function$
DECLARE
  _self_grace CONSTANT interval := interval ''30 minutes'';
  _group_dur  CONSTANT interval := interval ''1 hour'';
  _comm_dur   CONSTANT interval := interval ''2 hours'';
  r record;
  _aid uuid;
  _new text;
  _triggered boolean := false;
BEGIN
  -- Sleep/post-wake grace withdraws a silence alert it was wrong to raise.
  -- Activity never closes an alert here; see the migration header.
  FOR r IN
    SELECT
      a.id,
      a.user_id
    FROM public.alerts AS a
    WHERE a.status = ''open''
      AND a.cause = ''silence''
      AND private.sleep_relaxed(a.user_id, now())
  LOOP
    UPDATE public.alerts
    SET status = ''resolved'',
        resolved_at = now(),
        resolved_by = NULL,
        updated_at = now()
    WHERE id = r.id;

    INSERT INTO public.alert_events (alert_id, kind, note)
    VALUES (r.id, ''auto_resolved'', ''sleep_grace'');

    PERFORM private.notify_auto_resolved(r.id, r.user_id);
    _triggered := true;
  END LOOP;

  -- device_state.status is descriptive state, not an independent authority to
  -- bypass the canonical silence calculation or sleep grace.
  FOR r IN
    SELECT
      ds.user_id,
      (now() - ds.last_heartbeat_at) > interval ''18 hours'' AS is_dark
    FROM public.device_state AS ds
    WHERE (
      now() - ds.last_heartbeat_at > interval ''18 hours''
      OR (
        NOT private.sleep_relaxed(ds.user_id, now())
        AND now() - (
          SELECT coalesce(max(received_at), to_timestamp(0))
          FROM public.behavior_pings
          WHERE user_id = ds.user_id
            AND ingest_version = 2
            AND abs(extract(epoch FROM (received_at - at))) <= 300
        ) > private.silence_threshold(ds.user_id)
      )
    )
      AND EXISTS (
        SELECT 1
        FROM public.group_members AS gm
        WHERE gm.user_id = ds.user_id
          AND gm.monitored
          AND gm.status = ''active''
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.alerts AS a
        WHERE a.user_id = ds.user_id
          AND a.status = ''open''
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.alerts AS recent
        WHERE recent.user_id = ds.user_id
          AND recent.status = ''resolved''
          AND recent.cause IN (''silence'', ''dark_device'')
          AND recent.resolved_by IS NOT NULL
          AND recent.resolved_by <> recent.user_id
          AND recent.resolved_at > now() - _self_grace
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.gm_mutes AS mute
        WHERE mute.user_id = ds.user_id
          AND (mute.muted_until IS NULL OR mute.muted_until > now())
      )
  LOOP
    INSERT INTO public.alerts (
      user_id, cause, stage, stage_entered_at, next_deadline
    )
    VALUES (
      r.user_id,
      CASE WHEN r.is_dark THEN ''dark_device'' ELSE ''silence'' END,
      ''self'',
      now(),
      now() + _self_grace
    )
    RETURNING id INTO _aid;

    INSERT INTO public.alert_events (alert_id, kind)
    VALUES (_aid, ''raised'');

    PERFORM private.notify_stage(_aid, r.user_id, ''self'');
    _triggered := true;
  END LOOP;

  FOR r IN
    SELECT *
    FROM public.alerts
    WHERE status = ''open''
      AND next_deadline IS NOT NULL
      AND next_deadline <= now()
      AND coalesce(paused_until, to_timestamp(0)) <= now()
  LOOP
    _new := CASE r.stage
      WHEN ''self'' THEN ''group''
      WHEN ''group'' THEN ''community''
      WHEN ''community'' THEN ''terminal''
      ELSE ''terminal''
    END;

    UPDATE public.alerts
    SET stage = _new,
        stage_entered_at = now(),
        paused_until = NULL,
        paused_by = NULL,
        updated_at = now(),
        next_deadline = CASE _new
          WHEN ''group'' THEN now() + _group_dur
          WHEN ''community'' THEN now() + _comm_dur
          ELSE NULL
        END
    WHERE id = r.id;

    INSERT INTO public.alert_events (alert_id, kind, note)
    VALUES (r.id, ''escalated'', _new);

    PERFORM private.notify_stage(r.id, r.user_id, _new);
    _triggered := true;
  END LOOP;

  IF _triggered THEN
    PERFORM private.trigger_push_dispatch();
  END IF;
END;
$function$"}', 'activity_never_answers_an_alert_in_cron', NULL, NULL, NULL);


--
-- PostgreSQL database dump complete
--

-- \unrestrict eqbJLX5knUXEPSEGRaxRkuhf23yRWrup0PoSHCr1Scfpa4znFve9wJl0HJ7BJdU

RESET ALL;
