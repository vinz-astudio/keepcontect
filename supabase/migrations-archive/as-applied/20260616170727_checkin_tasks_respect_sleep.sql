-- 守望者设的报平安任务：睡眠窗（含醒后宽限）内不催打卡、也不算漏卡，顺延到醒后。
create or replace function public.process_checkin_tasks()
returns void language plpgsql security definer set search_path to '' as $function$
declare t record; _done boolean; _wname text;
begin
  for t in select * from public.checkin_tasks
           where status = 'active' and cycle_state = 'idle'
             and next_due_at is not null and next_due_at <= now()
             and not private.sleep_relaxed(ward_id, now())  -- 睡眠期不催
  loop
    insert into public.notifications (recipient_id, kind, body, params)
    values (t.ward_id, 'task_due', '到点报平安啦，点开 App 完成确认。',
            jsonb_build_object('label', t.label));
    update public.checkin_tasks set cycle_state = 'due_notified', updated_at = now() where id = t.id;
  end loop;

  for t in select * from public.checkin_tasks
           where status = 'active' and cycle_state = 'due_notified'
             and next_due_at + make_interval(mins => grace_minutes) <= now()
             and not private.sleep_relaxed(ward_id, now())  -- 睡眠期不判漏卡
  loop
    select exists (
      select 1 from public.device_state ds
      where ds.user_id = t.ward_id and ds.last_heartbeat_at >= t.next_due_at
    ) into _done;

    if not _done then
      select coalesce(display_name, '') into _wname from public.profiles where id = t.ward_id;
      insert into public.notifications (recipient_id, kind, body, params)
      select distinct r.uid, 'task_missed',
        _wname || ' 未完成定时报平安，请关注。',
        jsonb_build_object('name', _wname, 'label', t.label)
      from (
        select t.created_by as uid where t.created_by <> t.ward_id
        union
        select g.guardian_id from public.guardianships g
          where t.created_by = t.ward_id and g.ward_id = t.ward_id and g.status = 'active'
        union
        select w.user_id from public.group_members gm
          join public.group_members w on w.group_id = gm.group_id
          where t.created_by = t.ward_id
            and gm.user_id = t.ward_id and gm.monitored and gm.status = 'active'
            and w.watching and w.status = 'active' and w.user_id <> t.ward_id
            and not exists (select 1 from public.guardianships g2
                            where g2.ward_id = t.ward_id and g2.status = 'active')
      ) r;
    end if;

    update public.checkin_tasks set
      cycle_state = 'idle',
      next_due_at = case
        when kind = 'interval' then now() + make_interval(hours => interval_hours)
        else next_due_at + make_interval(days => ceil(extract(epoch from (now() - next_due_at)) / 86400.0)::int)
      end,
      updated_at = now()
      where id = t.id;
  end loop;
end;
$function$;