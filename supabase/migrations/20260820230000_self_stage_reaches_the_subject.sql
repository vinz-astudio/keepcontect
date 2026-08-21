-- The self stage must actually reach the subject.
--
-- `notify_stage` is a dispatcher: alerts that came from passive check-in get the
-- "lost contact" copy, everything else is delegated to
-- `notify_stage_before_passive_checkin`. Both paths returned early for the self
-- stage, on the grounds that a local overlay prompts the subject. That overlay
-- only appears while the app is awake, which is exactly when the person does not
-- need asking. Measured over 30 days: of 43 silence alerts opening at the self
-- stage, 16 produced any notification row addressed to the subject; of 12
-- `concern` self-stage alerts, none did.
--
-- This is not a missed prompt. The escalation design rests on "KC asks you first,
-- and only your silence reaches your group". If the ask never lands, the chance to
-- intercept is fictional and every escalation is effectively unconditional.
--
-- Only the self branch changes. Group, community and terminal copy, the passive
-- routing and the legacy delegation are all left exactly as they were.

CREATE OR REPLACE FUNCTION private.notify_stage(_alert_id uuid,_user uuid,_stage text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _name text; _params jsonb;
BEGIN
  IF NOT EXISTS(SELECT 1 FROM private.passive_alert_causal_windows WHERE alert_id=_alert_id) THEN
    PERFORM private.notify_stage_before_passive_checkin(_alert_id,_user,_stage);
    RETURN;
  END IF;
  -- 本人这一层。原来直接 return,理由是本机 overlay 会提示 —— 但 overlay 只在 App
  -- 醒着时出现,而那正是不需要问他的时候。30 天里 43 次 self 阶段只有 16 次给本人
  -- 留下任何通知记录。整条升级链的第一步「先问本人」必须真的送达。
  IF _stage='self' THEN
    SELECT coalesce(display_name,'') INTO _name FROM public.profiles WHERE id=_user;
    INSERT INTO public.notifications(recipient_id,alert_id,kind,body,params)
    VALUES (_user,_alert_id,'self',
      'KC 有一阵子没有确认到您的活动了。您还好吗?点开报个平安,就不会通知任何人。',
      jsonb_build_object('name',_name,'cause','passive_checkin_lost_contact'));
    RETURN;
  END IF;
  SELECT coalesce(display_name,'') INTO _name FROM public.profiles WHERE id=_user;
  _params:=jsonb_build_object('name',_name,'cause','passive_checkin_lost_contact');
  IF _stage='group' THEN
    INSERT INTO public.notifications(recipient_id,alert_id,kind,body,params)
    SELECT DISTINCT recipient,_alert_id,'group',_name||' 与 KC 失去联系，请尝试联系本人确认。',_params
    FROM (
      SELECT watcher.user_id AS recipient FROM public.group_members subject
      JOIN public.group_members watcher ON watcher.group_id=subject.group_id
      WHERE subject.user_id=_user AND subject.monitored AND subject.status='active'
        AND watcher.watching AND watcher.status='active' AND watcher.user_id<>_user
      UNION SELECT guardian_id FROM public.guardianships
      WHERE ward_id=_user AND status='active'
    ) recipients;
  ELSIF _stage='community' THEN
    INSERT INTO public.notifications(recipient_id,alert_id,kind,body,params)
    SELECT DISTINCT member.user_id,_alert_id,'community',
      'KC 与 '||_name||' 持续失去联系且小组尚未响应，请协助联系。',_params
    FROM public.community_members subject
    JOIN public.community_members member ON member.community_id=subject.community_id
    WHERE subject.user_id=_user AND subject.status='active'
      AND member.status='active' AND member.user_id<>_user;
  ELSIF _stage='terminal' THEN
    INSERT INTO public.notifications(recipient_id,alert_id,kind,body,params)
    SELECT DISTINCT recipient,_alert_id,'terminal',
      'KC 与 '||_name||' 持续失去联系，请上门探视或协助联系。',_params
    FROM (
      SELECT watcher.user_id AS recipient FROM public.group_members subject
      JOIN public.group_members watcher ON watcher.group_id=subject.group_id
      WHERE subject.user_id=_user AND subject.monitored AND subject.status='active'
        AND watcher.watching AND watcher.status='active' AND watcher.user_id<>_user
      UNION SELECT guardian_id FROM public.guardianships
      WHERE ward_id=_user AND status='active'
    ) recipients;
  END IF;
END;
$$;

-- The legacy path serves every alert that did not come from passive check-in
-- (silence, dark_device, concern). Its self branch returned early for the same
-- reason and needs the same fix. Everything else in it is untouched.
CREATE OR REPLACE FUNCTION private.notify_stage_before_passive_checkin(
  _alert_id uuid, _user uuid, _stage text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
declare _name text; _p jsonb; _sos boolean;
begin
  select coalesce(display_name,'') into _name from public.profiles where id = _user;
  select (cause = 'sos') into _sos from public.alerts where id = _alert_id;
  _p := jsonb_build_object('name', _name);

  -- SOS 是本人自己按的,再问一次「您还好吗」没有意义。
  if _stage = 'self' then
    if not _sos then
      insert into public.notifications (recipient_id, alert_id, kind, body, params)
      values (_user, _alert_id, 'self',
        'KC 有一阵子没有确认到您的活动了。您还好吗?点开报个平安,就不会通知任何人。', _p);
    end if;
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
