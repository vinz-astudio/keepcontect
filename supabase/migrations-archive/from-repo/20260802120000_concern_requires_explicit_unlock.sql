-- 20260705180000_concern_real_alert.sql made a concern raise a REAL alert so the
-- subject's unlock prompt has something to hold onto, and deliberately kept
-- passive pings from clearing it: only an explicit pattern unlock may answer
-- "someone is asking whether you are alright".
--
-- That protection was expressed as a cause check inside
-- private.apply_liveness_side_effects (`cause in ('silence','dark_device')`), and
-- it holds only while a concern owns its own alert. send_concern also reuses an
-- already-open alert to avoid stacking — and in that branch the concern inherits
-- the reused alert's cause, and with it the passive auto-resolve it was supposed
-- to be exempt from.
--
-- Reproduced in production 2026-08-02:
--   11:11:00  silence alert raised
--   11:42:00  escalated to group
--   11:43:44.129  behavior ping kind='app' (the subject tapped the notification)
--   11:43:44.958  auto_resolved
-- A GM's concern was answered by the act of opening the app, 0.8 s later, with no
-- pattern drawn and nobody having confirmed anything.
--
-- The requirement belongs to the alert, not to its cause. A flag carries it
-- across the reuse branch, and the resolve gate reads the flag instead of
-- re-deriving intent from a cause that may predate the concern.
alter table public.alerts
  add column if not exists requires_explicit_unlock boolean not null default false;

comment on column public.alerts.requires_explicit_unlock is
  'Someone asked this subject to prove they are alright. Passive liveness may not clear it; only an explicit unlock may. Survives alert reuse, which a cause check cannot.';

-- Backfill: any still-open alert a concern is currently riding on.
update public.alerts a
set requires_explicit_unlock = true
where a.status = 'open'
  and (
    a.cause = 'concern'
    or exists (
      select 1 from public.notifications n
      where n.alert_id = a.id and n.kind = 'concern'
    )
  );

-- Parameter order matches the deployed signature exactly; Postgres refuses to
-- replace a function whose parameter names or order changed.
create or replace function private.apply_liveness_side_effects(
  _user_id uuid,
  _observed_at timestamptz,
  _received_at timestamptz
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
DECLARE
  _stale record;
  _triggered boolean := false;
BEGIN
  -- Update device_state:
  INSERT INTO public.device_state (user_id, status, last_heartbeat_at, updated_at)
  VALUES (_user_id, 'normal', _received_at, now())
  ON CONFLICT (user_id) DO UPDATE
    SET status = 'normal',
        last_heartbeat_at = greatest(device_state.last_heartbeat_at, excluded.last_heartbeat_at),
        updated_at = now();

  -- Resolve alerts:
  -- Any trigger/side effects must apply the live qualification above, and active alert resolution must require both received_at and observed_at >= alerts.opened_at.
  -- Note: The ADR's alert-created-at concept maps to alerts.opened_at (created_at search text)
  FOR _stale IN
    SELECT id, opened_at FROM public.alerts
    WHERE user_id = _user_id
      AND status = 'open'
      AND cause in ('silence', 'dark_device')
      -- Someone is waiting on an answer from this person; merely opening the app
      -- is not that answer. Reading the flag rather than the cause is what makes
      -- this survive send_concern reusing an existing silence alert.
      AND requires_explicit_unlock = false
      AND _received_at >= opened_at
      AND _observed_at >= opened_at
  LOOP
    UPDATE public.alerts
      SET status = 'resolved', resolved_at = _received_at, resolved_by = _user_id, updated_at = now()
      WHERE id = _stale.id;

    INSERT INTO public.alert_events (alert_id, actor_id, kind)
    VALUES (_stale.id, _user_id, 'auto_resolved');

    -- NOTIF-01: 保留该告警的通知历史,改为补发自动解除通知
    PERFORM private.notify_auto_resolved(_stale.id, _user_id);
    _triggered := true;
  END LOOP;

  -- Clear user self check-in nudges
  IF NOT (auth.uid() IS NOT NULL AND auth.uid() <> _user_id) THEN
    DELETE FROM public.notifications
      WHERE recipient_id = _user_id
        AND kind in ('self', 'concern');
  END IF;

  IF _triggered THEN
    PERFORM private.trigger_push_dispatch();
  END IF;
END;
$function$;

-- Both concern entry points now stamp the requirement onto whichever alert the
-- concern ends up attached to, created or reused.
create or replace function public.send_concern(_target uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare _uid uuid := auth.uid(); _name text; _aid uuid;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if _uid = _target then raise exception 'bad target'; end if;
  if not private.shares_group_with(_target, _uid) and not private.is_guardian_of(_target, _uid) then
    raise exception 'forbidden';
  end if;
  select coalesce(display_name, '') into _name from public.profiles where id = _uid;

  select id into _aid from public.alerts where user_id = _target and status = 'open' limit 1;
  if _aid is null then
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline, requires_explicit_unlock)
    values (_target, 'concern', 'self', now(), now() + interval '30 minutes', true)
    returning id into _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note)
    values (_aid, _uid, 'raised', 'concern');
  else
    update public.alerts set requires_explicit_unlock = true, updated_at = now()
    where id = _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note)
    values (_aid, _uid, 'raised', 'concern_on_open_alert');
  end if;

  insert into public.notifications (recipient_id, alert_id, kind, body, params)
  values (
    _target,
    _aid,
    'concern',
    coalesce(nullif(_name, ''), '有人') || ' 在关心你，请打开 App 完成解锁报平安。',
    jsonb_build_object('name', _name)
  );
  perform private.trigger_push_dispatch();
end;
$function$;

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

  select id into _aid from public.alerts where user_id = _target and status = 'open' limit 1;
  if _aid is null then
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline, requires_explicit_unlock)
    values (_target, 'concern', 'self', now(), now() + interval '30 minutes', true)
    returning id into _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note)
    values (_aid, _uid, 'raised', 'gm_concern');
  else
    update public.alerts set requires_explicit_unlock = true, updated_at = now()
    where id = _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note)
    values (_aid, _uid, 'raised', 'gm_concern_on_open_alert');
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
