-- 通知双语化：加 params(结构化参数)，文本由客户端按用户语言渲染；body 保留为旧客户端兜底。

alter table public.notifications
  add column params jsonb not null default '{}';

-- 重写通知派发：写入 params
create or replace function private.notify_stage(_alert_id uuid, _user uuid, _stage text)
returns void language plpgsql security definer set search_path = '' as $$
declare _name text; _p jsonb;
begin
  select coalesce(display_name, '') into _name from public.profiles where id = _user;
  _p := jsonb_build_object('name', _name);

  if _stage = 'self' then
    insert into public.notifications (recipient_id, alert_id, kind, body, params)
    values (_user, _alert_id, 'self', '检测到异常沉默，请打开 App 完成解锁报平安。', '{}'::jsonb);

  elsif _stage = 'group' then
    insert into public.notifications (recipient_id, alert_id, kind, body, params)
    select distinct s.r, _alert_id, 'group', _name || ' 出现异常沉默，请尽快联系确认其安全。', _p
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
    insert into public.notifications (recipient_id, alert_id, kind, body, params)
    select distinct y.user_id, _alert_id, 'community',
      '社区警示：' || _name || ' 长时间失联且其小组无人响应，请协助推动联系。', _p
    from public.community_members x
    join public.community_members y on x.community_id = y.community_id
    where x.user_id = _user and x.status = 'active'
      and y.status = 'active' and y.user_id <> _user;

  elsif _stage = 'terminal' then
    insert into public.notifications (recipient_id, alert_id, kind, body, params)
    select distinct s.r, _alert_id, 'terminal',
      '紧急：' || _name || ' 持续无响应。已为你解锁其地址与紧急联系人，请上门探视或协助报警。', _p
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

-- 重写 ack_alert：params 带 actor/target
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

  select coalesce(display_name, '') into _aname from public.profiles where id = _uid;
  select coalesce(display_name, '') into _tname from public.profiles where id = _target;
  insert into public.notifications (recipient_id, alert_id, kind, body, params)
  select distinct s.r, _alert_id, 'on_it', _aname || ' 正在跟进 ' || _tname || ' 的情况。',
    jsonb_build_object('actor', _aname, 'target', _tname)
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

-- 重写 resolve_alert：params 带 target
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

  select coalesce(display_name, '') into _tname from public.profiles where id = _target;
  insert into public.notifications (recipient_id, alert_id, kind, body, params)
  select distinct s.r, _alert_id, 'resolved', _tname || ' 已确认安全，告警解除。',
    jsonb_build_object('target', _tname)
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
