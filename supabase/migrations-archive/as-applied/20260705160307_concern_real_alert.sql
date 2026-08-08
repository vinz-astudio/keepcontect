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
  perform private.trigger_push_dispatch();
end;
$$;