-- P3/P4 升级引擎逻辑：通知派发 + 心跳/SOS/两段式确认 RPC + 服务器权威升级 cron。

------------------------------------------------------------
-- 通知派发（private）：按阶段向对应人群写站内通知
------------------------------------------------------------
create or replace function private.notify_stage(_alert_id uuid, _user uuid, _stage text)
returns void language plpgsql security definer set search_path = '' as $$
declare _name text;
begin
  select coalesce(display_name, '某位成员') into _name from public.profiles where id = _user;

  if _stage = 'self' then
    insert into public.notifications (recipient_id, alert_id, kind, body)
    values (_user, _alert_id, 'self', '检测到异常沉默，请打开 App 完成解锁报平安。');

  elsif _stage = 'group' then
    insert into public.notifications (recipient_id, alert_id, kind, body)
    select distinct s.r, _alert_id, 'group', _name || ' 出现异常沉默，请尽快联系确认其安全。'
    from (
      select w.user_id as r
      from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _user and t.monitored and t.status = 'active'
        and w.watching and w.status = 'active' and w.user_id <> _user
      union
      select g.guardian_id from public.guardianships g
      where g.ward_id = _user and g.status = 'active'
    ) s;

  elsif _stage = 'community' then
    insert into public.notifications (recipient_id, alert_id, kind, body)
    select distinct y.user_id, _alert_id, 'community',
      '社区警示：' || _name || ' 长时间失联且其小组无人响应，请协助推动联系。'
    from public.community_members x
    join public.community_members y on x.community_id = y.community_id
    where x.user_id = _user and x.status = 'active'
      and y.status = 'active' and y.user_id <> _user;

  elsif _stage = 'terminal' then
    insert into public.notifications (recipient_id, alert_id, kind, body)
    select distinct s.r, _alert_id, 'terminal',
      '紧急：' || _name || ' 持续无响应。已为你解锁其地址与紧急联系人，请上门探视或协助报警。'
    from (
      select w.user_id as r
      from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _user and t.monitored and t.status = 'active'
        and w.watching and w.status = 'active' and w.user_id <> _user
      union
      select g.guardian_id from public.guardianships g
      where g.ward_id = _user and g.status = 'active'
    ) s;
  end if;
end;
$$;

------------------------------------------------------------
-- 设备心跳（G1 设备侧落点）
------------------------------------------------------------
create or replace function public.send_heartbeat(_status text)
returns void language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if _status not in ('normal', 'alert') then raise exception 'bad status'; end if;

  insert into public.device_state (user_id, status, last_heartbeat_at, updated_at)
  values (_uid, _status, now(), now())
  on conflict (user_id) do update
    set status = excluded.status, last_heartbeat_at = now(), updated_at = now();

  -- 设备自报恢复正常 → 自动解除自身因沉默/暗设备产生的告警
  if _status = 'normal' then
    update public.alerts
      set status = 'resolved', resolved_at = now(), resolved_by = _uid, updated_at = now()
      where user_id = _uid and status = 'open' and cause in ('silence', 'dark_device');
  end if;
end;
$$;

-- 本人 pattern 解锁成功后自解除（防逞强：解不开则此 RPC 不会被调用，cron 照常升级）
create or replace function public.resolve_my_alert()
returns void language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid(); _aid uuid;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  update public.alerts set status = 'resolved', resolved_at = now(), resolved_by = _uid, updated_at = now()
    where user_id = _uid and status = 'open' returning id into _aid;
  if _aid is not null then
    insert into public.alert_events (alert_id, actor_id, kind) values (_aid, _uid, 'resolved');
  end if;
  -- 同步设备状态为正常
  insert into public.device_state (user_id, status, last_heartbeat_at, updated_at)
  values (_uid, 'normal', now(), now())
  on conflict (user_id) do update set status = 'normal', last_heartbeat_at = now(), updated_at = now();
end;
$$;

------------------------------------------------------------
-- SOS：立即拉到 group 阶段并通知（跳过 self）
------------------------------------------------------------
create or replace function public.raise_sos()
returns uuid language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid(); _aid uuid;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  select id into _aid from public.alerts where user_id = _uid and status = 'open';
  if _aid is null then
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    values (_uid, 'sos', 'group', now(), now() + interval '1 hour')
    returning id into _aid;
    insert into public.alert_events (alert_id, actor_id, kind) values (_aid, _uid, 'raised');
  else
    update public.alerts set cause = 'sos', stage = 'group', stage_entered_at = now(),
      next_deadline = now() + interval '1 hour', paused_until = null, updated_at = now()
      where id = _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note) values (_aid, _uid, 'escalated', 'sos');
  end if;
  perform private.notify_stage(_aid, _uid, 'group');
  return _aid;
end;
$$;

------------------------------------------------------------
-- 两段式确认：「我去联系」暂停 / 「已确认安全」解除
------------------------------------------------------------
create or replace function public.ack_alert(_alert_id uuid, _minutes int default 30)
returns void language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid(); _target uuid; _aname text; _tname text;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if not private.can_see_alert(_alert_id, _uid) then raise exception 'forbidden'; end if;

  update public.alerts
    set paused_until = now() + make_interval(mins => _minutes), paused_by = _uid, updated_at = now()
    where id = _alert_id and status = 'open' returning user_id into _target;
  if _target is null then raise exception 'alert not open'; end if;

  insert into public.alert_events (alert_id, actor_id, kind) values (_alert_id, _uid, 'on_it');

  select coalesce(display_name, '一位关怀者') into _aname from public.profiles where id = _uid;
  select coalesce(display_name, '某位成员') into _tname from public.profiles where id = _target;
  -- 通知被守护者本人 + 其它响应者：有人正在跟进
  insert into public.notifications (recipient_id, alert_id, kind, body)
  select distinct s.r, _alert_id, 'on_it', _aname || ' 正在跟进 ' || _tname || ' 的情况。'
  from (
    select _target as r
    union
    select w.user_id from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _target and t.monitored and t.status = 'active'
        and w.watching and w.status = 'active' and w.user_id <> _uid
  ) s;
end;
$$;

create or replace function public.resolve_alert(_alert_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid(); _target uuid; _tname text;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if not private.can_see_alert(_alert_id, _uid) then raise exception 'forbidden'; end if;

  update public.alerts
    set status = 'resolved', resolved_at = now(), resolved_by = _uid, updated_at = now()
    where id = _alert_id and status = 'open' returning user_id into _target;
  if _target is null then raise exception 'alert not open'; end if;

  insert into public.alert_events (alert_id, actor_id, kind) values (_alert_id, _uid, 'confirmed_safe');

  select coalesce(display_name, '某位成员') into _tname from public.profiles where id = _target;
  insert into public.notifications (recipient_id, alert_id, kind, body)
  select distinct s.r, _alert_id, 'resolved', _tname || ' 已确认安全，告警解除。'
  from (
    select _target as r
    union
    select w.user_id from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _target and t.monitored and t.status = 'active'
        and w.watching and w.status = 'active'
  ) s;
end;
$$;

------------------------------------------------------------
-- 服务器权威升级（cron 每分钟跑）：创建 / 自动解除 / 推进阶段
------------------------------------------------------------
create or replace function public.process_escalations()
returns void language plpgsql security definer set search_path = '' as $$
declare
  _self_grace   constant interval := interval '30 minutes';
  _group_dur    constant interval := interval '1 hour';
  _comm_dur     constant interval := interval '2 hours';
  _dark         constant interval := interval '90 minutes';
  r record;
  _aid uuid;
  _new text;
begin
  -- 1) 由 device_state 生成新告警（被监护者：status=alert 或 心跳中断超阈值=暗设备）
  for r in
    select ds.user_id,
           (ds.last_heartbeat_at < now() - _dark) as is_dark
    from public.device_state ds
    where (ds.status = 'alert' or ds.last_heartbeat_at < now() - _dark)
      and exists (select 1 from public.group_members gm
                  where gm.user_id = ds.user_id and gm.monitored and gm.status = 'active')
      and not exists (select 1 from public.alerts a where a.user_id = ds.user_id and a.status = 'open')
  loop
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    values (r.user_id, case when r.is_dark then 'dark_device' else 'silence' end,
            'self', now(), now() + _self_grace)
    returning id into _aid;
    insert into public.alert_events (alert_id, kind) values (_aid, 'raised');
    perform private.notify_stage(_aid, r.user_id, 'self');
  end loop;

  -- 2) 自动解除：设备已恢复正常且心跳新鲜（非 SOS）
  for r in
    select a.id from public.alerts a
    join public.device_state ds on ds.user_id = a.user_id
    where a.status = 'open' and a.cause in ('silence', 'dark_device')
      and ds.status = 'normal' and ds.last_heartbeat_at > now() - _dark
  loop
    update public.alerts set status = 'resolved', resolved_at = now(), updated_at = now() where id = r.id;
    insert into public.alert_events (alert_id, kind) values (r.id, 'auto_resolved');
  end loop;

  -- 3) 推进到期且未暂停的告警
  for r in
    select * from public.alerts
    where status = 'open'
      and next_deadline is not null and next_deadline <= now()
      and coalesce(paused_until, to_timestamp(0)) <= now()
  loop
    _new := case r.stage
              when 'self' then 'group'
              when 'group' then 'community'
              when 'community' then 'terminal'
              else 'terminal' end;
    update public.alerts
      set stage = _new, stage_entered_at = now(), paused_until = null, updated_at = now(),
          next_deadline = case _new when 'group' then now() + _group_dur
                                    when 'community' then now() + _comm_dur
                                    else null end
      where id = r.id;
    insert into public.alert_events (alert_id, kind, note) values (r.id, 'escalated', _new);
    perform private.notify_stage(r.id, r.user_id, _new);
  end loop;
end;
$$;

------------------------------------------------------------
-- 权限：用户 RPC 仅 authenticated；内部函数与 cron 函数不暴露
------------------------------------------------------------
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

revoke execute on function public.process_escalations() from public, anon, authenticated;

------------------------------------------------------------
-- 定时：每分钟跑一次升级引擎（pg_cron）
------------------------------------------------------------
create extension if not exists pg_cron;
select cron.schedule('process-escalations', '* * * * *', $$ select public.process_escalations(); $$);
