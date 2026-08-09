-- P3/P4 升级引擎 schema：心跳/设备状态、告警、告警事件、站内通知 + 可见性辅助 + RLS。
-- 隐私：device_state 只存衍生状态(normal/alert)+ 心跳时间戳，不含行为数据。

------------------------------------------------------------
-- 表
------------------------------------------------------------

-- 设备状态：心跳信标落点（G1）。status 为设备端自判结论。
create table public.device_state (
  user_id uuid primary key references auth.users (id) on delete cascade,
  status text not null default 'normal' check (status in ('normal', 'alert')),
  last_heartbeat_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 告警：每用户至多一条 open。stage 为服务器权威升级阶段。
create table public.alerts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  cause text not null check (cause in ('silence', 'dark_device', 'sos')),
  stage text not null check (stage in ('self', 'group', 'community', 'terminal')),
  status text not null default 'open' check (status in ('open', 'resolved', 'cancelled')),
  opened_at timestamptz not null default now(),
  stage_entered_at timestamptz not null default now(),
  next_deadline timestamptz,           -- 当前阶段升级时刻（terminal 为 null）
  paused_until timestamptz,            -- 两段式"我去联系"暂停到期
  paused_by uuid references auth.users (id),
  resolved_at timestamptz,
  resolved_by uuid references auth.users (id),
  updated_at timestamptz not null default now()
);
create unique index alerts_one_open_per_user on public.alerts (user_id) where status = 'open';
create index alerts_open_idx on public.alerts (status) where status = 'open';

create table public.alert_events (
  id uuid primary key default gen_random_uuid(),
  alert_id uuid not null references public.alerts (id) on delete cascade,
  actor_id uuid references auth.users (id),
  kind text not null check (kind in ('raised', 'escalated', 'on_it', 'confirmed_safe', 'resolved', 'auto_resolved')),
  note text,
  at timestamptz not null default now()
);
create index alert_events_alert_idx on public.alert_events (alert_id, at);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users (id) on delete cascade,
  alert_id uuid references public.alerts (id) on delete cascade,
  kind text not null,                  -- 'self' | 'group' | 'community' | 'terminal' | 'on_it' | 'resolved'
  body text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index notifications_recipient_idx on public.notifications (recipient_id, created_at desc);

------------------------------------------------------------
-- 可见性辅助函数（private, SECURITY DEFINER）
------------------------------------------------------------

-- _watcher 是否在守望 _target（同组、target 被守望、watcher 守望他人）
create or replace function private.watches_user(_watcher uuid, _target uuid)
returns boolean language sql security definer set search_path = '' stable as $$
  select exists (
    select 1
    from public.group_members t
    join public.group_members w on w.group_id = t.group_id
    where t.user_id = _target and t.monitored and t.status = 'active'
      and w.user_id = _watcher and w.watching and w.status = 'active'
      and _watcher <> _target
  );
$$;

-- 两用户是否共享某 Community
create or replace function private.shares_community(_a uuid, _b uuid)
returns boolean language sql security definer set search_path = '' stable as $$
  select exists (
    select 1
    from public.community_members x
    join public.community_members y on x.community_id = y.community_id
    where x.user_id = _a and y.user_id = _b
      and x.status = 'active' and y.status = 'active' and _a <> _b
  );
$$;

-- 请求者能否看到某告警（owner / 守护人 / 守望者 / community+terminal 阶段的社区同侪）
create or replace function private.can_see_alert(_alert_id uuid, _user uuid)
returns boolean language sql security definer set search_path = '' stable as $$
  select exists (
    select 1 from public.alerts a
    where a.id = _alert_id and (
      a.user_id = _user
      or private.is_guardian_of(a.user_id, _user)
      or private.watches_user(_user, a.user_id)
      or (a.stage in ('community', 'terminal') and private.shares_community(_user, a.user_id))
    )
  );
$$;

revoke execute on all functions in schema private from public;
grant execute on all functions in schema private to authenticated;

------------------------------------------------------------
-- RLS
------------------------------------------------------------
alter table public.device_state  enable row level security;
alter table public.alerts        enable row level security;
alter table public.alert_events  enable row level security;
alter table public.notifications enable row level security;

-- device_state：本人 / 守望者 / 守护人可读。写入仅经 SECURITY DEFINER RPC（无 user 写策略）。
create policy device_state_select on public.device_state
  for select to authenticated
  using (
    (select auth.uid()) = user_id
    or private.watches_user((select auth.uid()), user_id)
    or private.is_guardian_of(user_id, (select auth.uid()))
  );

-- alerts：可见性同 can_see_alert（内联，避免子查询递归）。写入仅经 RPC/cron。
create policy alerts_select on public.alerts
  for select to authenticated
  using (
    (select auth.uid()) = user_id
    or private.is_guardian_of(user_id, (select auth.uid()))
    or private.watches_user((select auth.uid()), user_id)
    or (stage in ('community', 'terminal') and private.shares_community((select auth.uid()), user_id))
  );

create policy alert_events_select on public.alert_events
  for select to authenticated
  using (private.can_see_alert(alert_id, (select auth.uid())));

-- notifications：仅收件人可读 / 标记已读
create policy notifications_select on public.notifications
  for select to authenticated
  using ((select auth.uid()) = recipient_id);

create policy notifications_update on public.notifications
  for update to authenticated
  using ((select auth.uid()) = recipient_id)
  with check ((select auth.uid()) = recipient_id);

------------------------------------------------------------
-- G3：告警升级到 group+ 时，向授权响应者解锁被守护者的紧急信息
------------------------------------------------------------
create policy emergency_info_reveal_on_escalation on public.emergency_info
  for select to authenticated
  using (
    exists (
      select 1 from public.alerts a
      where a.user_id = emergency_info.user_id
        and a.status = 'open'
        and a.stage in ('group', 'community', 'terminal')
        and (
          private.watches_user((select auth.uid()), emergency_info.user_id)
          or private.shares_community((select auth.uid()), emergency_info.user_id)
        )
    )
  );
