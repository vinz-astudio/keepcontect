alter table public.alerts
  add column if not exists requires_explicit_unlock boolean not null default false;

comment on column public.alerts.requires_explicit_unlock is
  'Someone asked this subject to prove they are alright. Passive liveness may not clear it; only an explicit unlock may. Survives alert reuse, which a cause check cannot.';

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
  INSERT INTO public.device_state (user_id, status, last_heartbeat_at, updated_at)
  VALUES (_user_id, 'normal', _received_at, now())
  ON CONFLICT (user_id) DO UPDATE
    SET status = 'normal',
        last_heartbeat_at = greatest(device_state.last_heartbeat_at, excluded.last_heartbeat_at),
        updated_at = now();

  FOR _stale IN
    SELECT id, opened_at FROM public.alerts
    WHERE user_id = _user_id
      AND status = 'open'
      AND cause in ('silence', 'dark_device')
      AND requires_explicit_unlock = false
      AND _received_at >= opened_at
      AND _observed_at >= opened_at
  LOOP
    UPDATE public.alerts
      SET status = 'resolved', resolved_at = _received_at, resolved_by = _user_id, updated_at = now()
      WHERE id = _stale.id;

    INSERT INTO public.alert_events (alert_id, actor_id, kind)
    VALUES (_stale.id, _user_id, 'auto_resolved');

    PERFORM private.notify_auto_resolved(_stale.id, _user_id);
    _triggered := true;
  END LOOP;

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