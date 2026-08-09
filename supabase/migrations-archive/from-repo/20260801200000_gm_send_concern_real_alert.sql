-- 20260705180000_concern_real_alert.sql turned a member's concern into a REAL
-- alert, because a bare notification was a dead end: the recipient's unlock
-- overlay found no open alert and dismissed itself, and the very act of opening
-- the app fired a behavior ping whose side effects delete every 'self' and
-- 'concern' notification for that user (private.apply_liveness_side_effects).
--
-- That fix only ever reached public.send_concern. public.gm_send_concern — the
-- path the GM console uses — was left in its 20260623090000 shape and still
-- inserts a notification with no alert_id at all. Reproduced 2026-08-01: a GM
-- concern reached the device's lock screen, but tapping it opened an app with
-- no open alert, so no unlock prompt appeared, and the notification was deleted
-- by the ping that opening the app produced. The GM could not have been told
-- the target was safe, and the target was never asked.
--
-- Bring the GM path to parity: reuse an open alert or raise a real one, attach
-- the notification to it, and dispatch immediately instead of waiting for cron.
create or replace function public.gm_send_concern(_target uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare _uid uuid := auth.uid(); _name text; _aid uuid;
begin
  if not private.is_admin(_uid) then raise exception 'forbidden'; end if;
  select coalesce(display_name, '') into _name from public.profiles where id = _uid;

  -- 真告警：让对方的解锁界面持续存在，直到本人解锁(被动 ping 不会解除 concern)。
  -- 若对方已有 open 告警(任何 cause)则复用，避免叠加。
  select id into _aid from public.alerts where user_id = _target and status = 'open' limit 1;
  if _aid is null then
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    values (_target, 'concern', 'self', now(), now() + interval '30 minutes')
    returning id into _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note)
    values (_aid, _uid, 'raised', 'gm_concern');
  end if;

  insert into public.notifications (recipient_id, alert_id, kind, body, params)
  values (
    _target,
    _aid,
    'concern',
    coalesce(nullif(_name, ''), '管理员') || ' 在关心你，请打开 App 完成解锁报平安。',
    jsonb_build_object('name', _name)
  );
  perform private.trigger_push_dispatch();
end;
$function$;
