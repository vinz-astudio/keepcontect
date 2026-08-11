-- 定时报平安任务（PWA 形态的"习惯锚定打卡"）：
-- · 自设（晨间闹钟式）：创建即生效
-- · 守护人代设：须被守护者**接受**才生效（知情可控，防无故被追踪），接受/拒绝结果通知设置者
-- · cron 每分钟：到点推送提醒承担者；宽限期内无心跳 → 通知设置者(自设则通知其守护人/同组守望者) → 滚动下一轮

create table public.checkin_tasks (
  id uuid primary key default gen_random_uuid(),
  ward_id uuid not null references auth.users (id) on delete cascade,      -- 任务承担者
  created_by uuid not null references auth.users (id) on delete cascade,   -- 设置者(本人或其守护人)
  kind text not null check (kind in ('daily', 'interval')),
  due_time_utc time,        -- daily：每天的 UTC 时刻
  interval_hours int check (interval_hours is null or interval_hours >= 2), -- interval：至少 2 小时，防滥用
  grace_minutes int not null default 30 check (grace_minutes between 10 and 240),
  label text not null default '' ,
  status text not null default 'pending' check (status in ('pending', 'active', 'declined', 'revoked')),
  cycle_state text not null default 'idle' check (cycle_state in ('idle', 'due_notified')),
  next_due_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((kind = 'daily' and due_time_utc is not null) or (kind = 'interval' and interval_hours is not null))
);
create index checkin_tasks_due_idx on public.checkin_tasks (next_due_at) where status = 'active';
create index checkin_tasks_ward_idx on public.checkin_tasks (ward_id);

alter table public.checkin_tasks enable row level security;

-- 当事双方可见；写入仅经 RPC
create policy checkin_tasks_select on public.checkin_tasks
  for select to authenticated
  using ((select auth.uid()) = ward_id or (select auth.uid()) = created_by);

------------------------------------------------------------
-- RPC：创建（本人自设=直接 active；守护人代设=pending 并通知被守护者确认）
------------------------------------------------------------
create or replace function public.create_checkin_task(
  _ward uuid,
  _kind text,
  _due_time_utc time default null,
  _interval_hours int default null,
  _first_due timestamptz default null,
  _grace int default 30,
  _label text default ''
) returns uuid language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid(); _id uuid; _self boolean; _name text;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  _self := (_uid = _ward);
  if not _self and not private.is_guardian_of(_ward, _uid) then
    raise exception 'only the person or their guardian can create tasks';
  end if;

  insert into public.checkin_tasks
    (ward_id, created_by, kind, due_time_utc, interval_hours, grace_minutes, label,
     status, next_due_at)
  values
    (_ward, _uid, _kind, _due_time_utc, _interval_hours,
     coalesce(_grace, 30), coalesce(_label, ''),
     case when _self then 'active' else 'pending' end,
     case when _self then coalesce(_first_due,
       case when _kind = 'interval' then now() + make_interval(hours => _interval_hours) end)
     end)
  returning id into _id;

  -- 守护人代设：通知被守护者有任务待确认
  if not _self then
    select coalesce(display_name, '') into _name from public.profiles where id = _uid;
    insert into public.notifications (recipient_id, kind, body, params)
    values (_ward, 'task_invite',
      _name || ' 为你设置了报平安任务，请确认是否接受。',
      jsonb_build_object('name', _name, 'label', coalesce(_label, '')));
  end if;
  return _id;
end;
$$;

------------------------------------------------------------
-- RPC：被守护者接受/拒绝（consent），结果通知设置者
------------------------------------------------------------
create or replace function public.respond_checkin_task(_task uuid, _accept boolean, _first_due timestamptz default null)
returns void language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid(); _t public.checkin_tasks; _name text;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  select * into _t from public.checkin_tasks where id = _task and ward_id = _uid and status = 'pending';
  if not found then raise exception 'task not found or not pending'; end if;

  update public.checkin_tasks
    set status = case when _accept then 'active' else 'declined' end,
        next_due_at = case when _accept then coalesce(_first_due,
          case when _t.kind = 'interval' then now() + make_interval(hours => _t.interval_hours) end) end,
        updated_at = now()
    where id = _task;

  -- 接受与否都让设置者知情
  select coalesce(display_name, '') into _name from public.profiles where id = _uid;
  insert into public.notifications (recipient_id, kind, body, params)
  values (_t.created_by,
    case when _accept then 'task_accepted' else 'task_declined' end,
    _name || case when _accept then ' 接受了报平安任务。' else ' 拒绝了报平安任务。' end,
    jsonb_build_object('name', _name, 'label', _t.label));
end;
$$;

------------------------------------------------------------
-- RPC：撤销（设置者或承担者都可——知情可控）
------------------------------------------------------------
create or replace function public.revoke_checkin_task(_task uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  update public.checkin_tasks set status = 'revoked', updated_at = now()
    where id = _task and (ward_id = _uid or created_by = _uid) and status in ('pending', 'active');
  if not found then raise exception 'task not found'; end if;
end;
$$;

revoke execute on function public.create_checkin_task(uuid, text, time, int, timestamptz, int, text) from public, anon;
revoke execute on function public.respond_checkin_task(uuid, boolean, timestamptz) from public, anon;
revoke execute on function public.revoke_checkin_task(uuid) from public, anon;
grant execute on function public.create_checkin_task(uuid, text, time, int, timestamptz, int, text) to authenticated;
grant execute on function public.respond_checkin_task(uuid, boolean, timestamptz) to authenticated;
grant execute on function public.revoke_checkin_task(uuid) to authenticated;

------------------------------------------------------------
-- cron：到点提醒 → 宽限检查 → 漏卡通知 → 滚动下一轮
------------------------------------------------------------
create or replace function public.process_checkin_tasks()
returns void language plpgsql security definer set search_path = '' as $$
declare t record; _done boolean; _wname text;
begin
  -- 1) 到点：提醒承担者
  for t in select * from public.checkin_tasks
           where status = 'active' and cycle_state = 'idle'
             and next_due_at is not null and next_due_at <= now()
  loop
    insert into public.notifications (recipient_id, kind, body, params)
    values (t.ward_id, 'task_due', '到点报平安啦，点开 App 完成确认。',
            jsonb_build_object('label', t.label));
    update public.checkin_tasks set cycle_state = 'due_notified', updated_at = now() where id = t.id;
  end loop;

  -- 2) 宽限到期：心跳判定完成与否；漏卡 → 通知设置者(自设则通知守护人/同组守望者)
  for t in select * from public.checkin_tasks
           where status = 'active' and cycle_state = 'due_notified'
             and next_due_at + make_interval(mins => t.grace_minutes) <= now()
  loop
    select exists (
      select 1 from public.device_state ds
      where ds.user_id = t.ward_id and ds.last_heartbeat_at >= t.next_due_at
    ) into _done;

    if not _done then
      select coalesce(display_name, '') into _wname from public.profiles where id = t.ward_id;
      insert into public.notifications (recipient_id, kind, body, params)
      select distinct r.uid, 'task_missed',
        _wname || ' 未完成定时报平安，请关注。',
        jsonb_build_object('name', _wname, 'label', t.label)
      from (
        select t.created_by as uid where t.created_by <> t.ward_id
        union
        select g.guardian_id from public.guardianships g
          where t.created_by = t.ward_id and g.ward_id = t.ward_id and g.status = 'active'
        union
        select w.user_id from public.group_members gm
          join public.group_members w on w.group_id = gm.group_id
          where t.created_by = t.ward_id
            and gm.user_id = t.ward_id and gm.monitored and gm.status = 'active'
            and w.watching and w.status = 'active' and w.user_id <> t.ward_id
            and not exists (select 1 from public.guardianships g2
                            where g2.ward_id = t.ward_id and g2.status = 'active')
      ) r;
    end if;

    -- 滚动下一轮（漏卡也滚动，避免重复轰炸；daily 跳到未来最近一个周期）
    update public.checkin_tasks set
      cycle_state = 'idle',
      next_due_at = case
        when kind = 'interval' then now() + make_interval(hours => interval_hours)
        else next_due_at + make_interval(days => ceil(extract(epoch from (now() - next_due_at)) / 86400.0)::int)
      end,
      updated_at = now()
      where id = t.id;
  end loop;
end;
$$;

revoke execute on function public.process_checkin_tasks() from public, anon, authenticated;
