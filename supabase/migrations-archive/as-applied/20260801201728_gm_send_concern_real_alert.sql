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