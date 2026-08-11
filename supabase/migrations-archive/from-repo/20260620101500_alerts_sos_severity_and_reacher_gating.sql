-- #1 本人不再收到关于自己告警的通知(self 阶段交给本机 overlay 提示报平安)
-- #2 SOS 用独立 kind='sos' 与更严重文案,与 unusual silence 区分;贯穿各升级阶段
create or replace function private.notify_stage(_alert_id uuid, _user uuid, _stage text)
returns void language plpgsql security definer set search_path to '' as $$
declare _name text; _p jsonb; _sos boolean;
begin
  select coalesce(display_name,'') into _name from public.profiles where id = _user;
  select (cause = 'sos') into _sos from public.alerts where id = _alert_id;
  _p := jsonb_build_object('name', _name);

  -- 本人由本机 overlay 提示报平安,不发服务器通知给自己
  if _stage = 'self' then
    return;
  end if;

  if _stage = 'group' then
    insert into public.notifications (recipient_id, alert_id, kind, body, params)
    select distinct s.r, _alert_id,
      case when _sos then 'sos' else 'group' end,
      case when _sos
        then '🆘 ' || _name || ' 发出紧急求救(SOS)！请立即联系并尽快前往确认。'
        else _name || ' 出现异常沉默，请尽快联系确认其安全。' end,
      _p
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
    select distinct y.user_id, _alert_id,
      case when _sos then 'sos' else 'community' end,
      case when _sos
        then '🆘 社区紧急：' || _name || ' 发出 SOS 求救且小组未及时响应，请立即协助联系。'
        else '社区警示：' || _name || ' 长时间失联且其小组无人响应，请协助推动联系。' end,
      _p
    from public.community_members x
    join public.community_members y on x.community_id = y.community_id
    where x.user_id = _user and x.status = 'active'
      and y.status = 'active' and y.user_id <> _user;

  elsif _stage = 'terminal' then
    insert into public.notifications (recipient_id, alert_id, kind, body, params)
    select distinct s.r, _alert_id,
      case when _sos then 'sos' else 'terminal' end,
      case when _sos
        then '🆘 紧急：' || _name || ' SOS 求救且持续无响应。已为你解锁其地址与紧急联系人，请立即上门或协助报警。'
        else '紧急：' || _name || ' 持续无响应。已为你解锁其地址与紧急联系人，请上门探视或协助报警。' end,
      _p
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

-- #3 只有"我去联系"(ack_alert 记录的 paused_by)的那位成员可以确认安全
create or replace function public.resolve_alert(_alert_id uuid)
returns void language plpgsql security definer set search_path to '' as $$
declare _uid uuid := auth.uid(); _target uuid; _tname text;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if not private.can_see_alert(_alert_id, _uid) then raise exception 'forbidden'; end if;
  if not exists (select 1 from public.alerts where id = _alert_id and paused_by = _uid) then
    raise exception 'only the responder who reached out can confirm safe';
  end if;

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

-- 升级时清空 paused_by,使新阶段成员可重新认领"我去联系"
create or replace function public.process_escalations()
returns void language plpgsql security definer set search_path to '' as $$
declare
  _self_grace constant interval := interval '30 minutes';
  _group_dur  constant interval := interval '1 hour';
  _comm_dur   constant interval := interval '2 hours';
  r record; _aid uuid; _new text;
begin
  for r in
    select ds.user_id,
           (now() - ds.last_heartbeat_at) > interval '18 hours' as is_dark
    from public.device_state ds
    where (ds.status = 'alert'
           or (now() - ds.last_heartbeat_at) > private.silence_threshold(ds.user_id))
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
      set stage = _new, stage_entered_at = now(), paused_until = null, paused_by = null, updated_at = now(),
          next_deadline = case _new when 'group' then now() + _group_dur
                                    when 'community' then now() + _comm_dur
                                    else null end
      where id = r.id;
    insert into public.alert_events (alert_id, kind, note) values (r.id, 'escalated', _new);
    perform private.notify_stage(r.id, r.user_id, _new);
  end loop;
end;
$$;
