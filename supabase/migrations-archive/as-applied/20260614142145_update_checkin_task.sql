create or replace function public.update_checkin_task(
  _task uuid,
  _kind text,
  _due_time_utc time default null,
  _interval_hours int default null,
  _first_due timestamptz default null,
  _grace int default null,
  _label text default null
) returns void language plpgsql security definer set search_path = '' as $$
declare _uid uuid := auth.uid(); _t public.checkin_tasks;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  select * into _t from public.checkin_tasks
    where id = _task and created_by = _uid and status in ('pending', 'active');
  if not found then raise exception 'task not found or not editable'; end if;

  update public.checkin_tasks set
    kind = _kind,
    due_time_utc = _due_time_utc,
    interval_hours = _interval_hours,
    grace_minutes = coalesce(_grace, grace_minutes),
    label = coalesce(_label, label),
    cycle_state = 'idle',
    next_due_at = case when status = 'active'
      then coalesce(_first_due,
        case when _kind = 'interval' then now() + make_interval(hours => _interval_hours) end)
      else next_due_at end,
    updated_at = now()
  where id = _task;

  if _t.ward_id <> _uid and _t.status = 'active' then
    insert into public.notifications (recipient_id, kind, body, params)
    values (_t.ward_id, 'task_updated', '你的报平安任务已被修改，请留意新的时间安排。', '{}'::jsonb);
  end if;
end;
$$;

revoke execute on function public.update_checkin_task(uuid, text, time, int, timestamptz, int, text) from public, anon;
grant execute on function public.update_checkin_task(uuid, text, time, int, timestamptz, int, text) to authenticated;