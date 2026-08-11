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
BEGIN
  INSERT INTO public.device_state (user_id, status, last_heartbeat_at, updated_at)
  VALUES (_user_id, 'normal', _received_at, now())
  ON CONFLICT (user_id) DO UPDATE
    SET status = 'normal',
        last_heartbeat_at = greatest(device_state.last_heartbeat_at, excluded.last_heartbeat_at),
        updated_at = now();

  IF NOT (auth.uid() IS NOT NULL AND auth.uid() <> _user_id)
     AND NOT EXISTS (
       SELECT 1 FROM public.alerts
       WHERE user_id = _user_id AND status = 'open'
     ) THEN
    DELETE FROM public.notifications
      WHERE recipient_id = _user_id
        AND kind in ('self', 'concern');
  END IF;
END;
$function$;

create or replace function public.resolve_my_alert()
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare _uid uuid := auth.uid(); _aid uuid;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  update public.alerts set status = 'resolved', resolved_at = now(), resolved_by = _uid, updated_at = now()
    where user_id = _uid and status = 'open' returning id into _aid;
  if _aid is not null then
    insert into public.alert_events (alert_id, actor_id, kind) values (_aid, _uid, 'resolved');
  end if;

  insert into public.behavior_pings (user_id, kind, at)
  values (_uid, 'manual_checkin', now());

  delete from public.notifications
    where recipient_id = _uid and kind in ('self', 'concern');

  perform private.trigger_push_dispatch();
end;
$function$;