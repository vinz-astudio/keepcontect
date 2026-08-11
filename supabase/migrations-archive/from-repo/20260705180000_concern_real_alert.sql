-- Concern was a dead end: send_concern only inserted a notification, so the
-- recipient's unlock overlay (optimistically shown from the notification tap)
-- found no open alert and dismissed itself — and the very act of opening the
-- app fired a behavior ping whose trigger deleted the concern notification.
-- The sender also never got a "confirmed safe" reply.
--
-- Fix: a concern now creates a REAL alert (cause 'concern'). Passive pings do
-- NOT auto-resolve it (handle_behavior_ping_insert only clears silence/
-- dark_device), so only an explicit pattern unlock (resolve_my_alert) clears
-- it — which also notifies watchers via the existing resolve flow. If the
-- target doesn't confirm within 30 minutes, the existing escalation chain
-- (self -> group -> ...) takes over.
alter table public.alerts drop constraint alerts_cause_check;
alter table public.alerts add constraint alerts_cause_check
  check (cause = any (array['silence'::text, 'dark_device'::text, 'sos'::text, 'concern'::text]));

create or replace function public.send_concern(_target uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare _uid uuid := auth.uid(); _name text; _aid uuid;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if _uid = _target then raise exception 'bad target'; end if;
  if not private.shares_group_with(_target, _uid) and not private.is_guardian_of(_target, _uid) then
    raise exception 'forbidden';
  end if;
  select coalesce(display_name, '') into _name from public.profiles where id = _uid;

  -- 真告警:让对方的解锁界面持续存在,直到本人解锁(被动 ping 不会解除 concern)。
  -- 若对方已有 open 告警(任何 cause)则复用,避免叠加。
  select id into _aid from public.alerts where user_id = _target and status = 'open' limit 1;
  if _aid is null then
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    values (_target, 'concern', 'self', now(), now() + interval '30 minutes')
    returning id into _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note)
    values (_aid, _uid, 'raised', 'concern');
  end if;

  insert into public.notifications (recipient_id, alert_id, kind, body, params)
  values (
    _target,
    _aid,
    'concern',
    coalesce(nullif(_name, ''), '有人') || ' 在关心你，请打开 App 完成解锁报平安。',
    jsonb_build_object('name', _name)
  );
  -- 不等每分钟的 cron,立即推送(Web Push + FCM tickle)。
  perform private.trigger_push_dispatch();
end;
$$;
