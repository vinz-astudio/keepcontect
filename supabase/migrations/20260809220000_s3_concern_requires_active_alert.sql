-- S3-A · Concern is active-alert-only (ADR-0039).
--
-- Why this exists
-- ---------------
-- Both Concern paths used to insert a fresh alert with cause='concern' whenever
-- the target had no open alert. That let any authorised group member, and any
-- admin, manufacture an alert on another person. An alert is the app's only way
-- to say "this person is actually unaccounted for"; once concern can mint one,
-- alerts stop correlating with real silence and the people who receive them
-- learn to ignore them. The cost is paid later, by the person whose real alert
-- nobody answers.
--
-- ADR-0039: Concern may only be sent when the target already has an active
-- alert. It strengthens the need for an explicit personal response. It never
-- creates an alert, never counts as activity evidence, and never resolves one.
--
-- Eligibility is enforced here, on the server. Hiding the button is a courtesy,
-- not the contract: an old client, a replayed request or a direct RPC call must
-- all be refused the same way.
--
-- Append-only: no historical migration is edited. Authorisation, RLS and the
-- existing open-alert behaviour are unchanged.

CREATE OR REPLACE FUNCTION public.send_concern(_target uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare _uid uuid := auth.uid(); _name text; _aid uuid;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if _uid = _target then raise exception 'bad target'; end if;
  if not private.shares_group_with(_target, _uid) and not private.is_guardian_of(_target, _uid) then
    raise exception 'forbidden';
  end if;

  select id into _aid from public.alerts where user_id = _target and status = 'open' limit 1;
  if _aid is null then
    -- ADR-0039: Concern never creates an alert.
    raise exception 'active alert required';
  end if;

  select coalesce(display_name, '') into _name from public.profiles where id = _uid;

  update public.alerts set requires_explicit_unlock = true, updated_at = now()
  where id = _aid;
  insert into public.alert_events (alert_id, actor_id, kind, note)
  values (_aid, _uid, 'raised', 'concern_on_open_alert');

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

CREATE OR REPLACE FUNCTION public.gm_send_concern(_target uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare _uid uuid := auth.uid(); _name text; _aid uuid;
begin
  if not private.is_admin(_uid) then raise exception 'forbidden'; end if;

  select id into _aid from public.alerts where user_id = _target and status = 'open' limit 1;
  if _aid is null then
    -- ADR-0039: admin authority does not include manufacturing an alert.
    raise exception 'active alert required';
  end if;

  select coalesce(display_name, '') into _name from public.profiles where id = _uid;

  update public.alerts set requires_explicit_unlock = true, updated_at = now()
  where id = _aid;
  insert into public.alert_events (alert_id, actor_id, kind, note)
  values (_aid, _uid, 'raised', 'gm_concern_on_open_alert');

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
