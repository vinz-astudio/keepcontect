-- Migration: Support daily tasks anchored to wall clock time (due_time_local)
-- ID: 20260717124306

-- 1) Add due_time_local column to public.checkin_tasks
ALTER TABLE public.checkin_tasks ADD COLUMN due_time_local time DEFAULT NULL;

-- 2) Backfill existing daily rows using current_date and the ward's current timezone.
-- Note: When backfilling due_time_local from due_time_utc for existing daily tasks, we interpret the stored due_time_utc
-- as a UTC time on the current migration date and convert it using the ward's current timezone setting (defaulting to 'UTC').
-- If a ward has changed their timezone since the task was originally entered, this backfilled value may differ from the
-- user's original local intent. This is a best-effort historical approximation.
UPDATE public.checkin_tasks t
SET due_time_local = (((current_date + t.due_time_utc) at time zone 'UTC') at time zone coalesce(
  (SELECT timezone FROM public.user_settings s WHERE s.user_id = t.ward_id),
  'UTC'
))::time
WHERE t.kind = 'daily' AND t.due_time_utc IS NOT NULL;

-- 3) Drop the exact old create_checkin_task and update_checkin_task signatures before creating the new 8-argument signatures
DROP FUNCTION IF EXISTS public.create_checkin_task(uuid, text, time, int, timestamptz, int, text);
DROP FUNCTION IF EXISTS public.update_checkin_task(uuid, text, time, int, timestamptz, int, text);

-- 4) Create the new create_checkin_task signature with _due_time_local
CREATE OR REPLACE FUNCTION public.create_checkin_task(
  _ward uuid,
  _kind text,
  _due_time_utc time default null,
  _due_time_local time default null,
  _interval_hours int default null,
  _first_due timestamptz default null,
  _grace int default 30,
  _label text default ''
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  _uid uuid := auth.uid();
  _id uuid;
  _self boolean;
  _name text;
  _timezone text;
  _local_date date;
  _next_due timestamptz;
BEGIN
  if _uid is null then raise exception 'not authenticated'; end if;
  _self := (_uid = _ward);
  if not _self and not private.is_guardian_of(_ward, _uid) then
    raise exception 'only the person or their guardian can create tasks';
  end if;

  _timezone := null;
  select timezone into _timezone from public.user_settings where user_id = _ward;
  _timezone := coalesce(_timezone, 'UTC');
  _local_date := (now() at time zone _timezone)::date;

  if _kind = 'daily' then
    -- TRANSITION SHIM: Pre-wall-clock clients never send _due_time_local.
    -- Derive it from _due_time_utc.
    if _due_time_local is null and _due_time_utc is not null then
      _due_time_local := (((_local_date + _due_time_utc) at time zone 'UTC') at time zone _timezone)::time;
    elsif _due_time_local is not null then
      _due_time_utc := (((_local_date + _due_time_local) at time zone _timezone) at time zone 'UTC')::time;
    end if;

    if _self then
      _next_due := (_local_date + _due_time_local) at time zone _timezone;
      if _next_due <= now() then
        _next_due := (_local_date + 1 + _due_time_local) at time zone _timezone;
      end if;
    end if;
  else
    if _self then
      _next_due := coalesce(_first_due, now() + make_interval(hours => _interval_hours));
    end if;
  end if;

  insert into public.checkin_tasks
    (ward_id, created_by, kind, due_time_utc, due_time_local, interval_hours, grace_minutes, label,
     status, next_due_at)
  values
    (_ward, _uid, _kind, _due_time_utc, _due_time_local, _interval_hours,
     coalesce(_grace, 30), coalesce(_label, ''),
     case when _self then 'active' else 'pending' end,
     _next_due)
  returning id into _id;

  if not _self then
    select coalesce(display_name, '') into _name from public.profiles where id = _uid;
    insert into public.notifications (recipient_id, kind, body, params)
    values (_ward, 'task_invite',
      _name || ' 为你设置了报平安任务，请确认是否接受。',
      jsonb_build_object('name', _name, 'label', coalesce(_label, '')));
  end if;
  return _id;
end;
$$;

-- 5) Create the new update_checkin_task signature with _due_time_local
CREATE OR REPLACE FUNCTION public.update_checkin_task(
  _task uuid,
  _kind text,
  _due_time_utc time default null,
  _due_time_local time default null,
  _interval_hours int default null,
  _first_due timestamptz default null,
  _grace int default 30,
  _label text default ''
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  _uid uuid := auth.uid();
  _ward uuid;
  _timezone text;
  _local_date date;
  _next_due timestamptz;
BEGIN
  if _uid is null then raise exception 'not authenticated'; end if;
  if _kind not in ('daily', 'interval') then raise exception 'bad kind'; end if;

  select ward_id into _ward from public.checkin_tasks
  where id = _task and created_by = _uid and status in ('pending', 'active', 'declined');
  if _ward is null then raise exception 'task not found'; end if;

  _timezone := null;
  select timezone into _timezone from public.user_settings where user_id = _ward;
  _timezone := coalesce(_timezone, 'UTC');
  _local_date := (now() at time zone _timezone)::date;

  if _kind = 'daily' then
    -- TRANSITION SHIM: Pre-wall-clock clients never send _due_time_local.
    -- Derive it from _due_time_utc.
    if _due_time_local is null and _due_time_utc is not null then
      _due_time_local := (((_local_date + _due_time_utc) at time zone 'UTC') at time zone _timezone)::time;
    elsif _due_time_local is not null then
      _due_time_utc := (((_local_date + _due_time_local) at time zone _timezone) at time zone 'UTC')::time;
    end if;

    _next_due := (_local_date + _due_time_local) at time zone _timezone;
    if _next_due <= now() then
      _next_due := (_local_date + 1 + _due_time_local) at time zone _timezone;
    end if;
  else
    _next_due := coalesce(_first_due, now() + make_interval(hours => _interval_hours));
  end if;

  update public.checkin_tasks t
  set kind = _kind,
      due_time_utc = case when _kind = 'daily' then _due_time_utc else null end,
      due_time_local = case when _kind = 'daily' then _due_time_local else null end,
      interval_hours = case when _kind = 'interval' then _interval_hours else null end,
      grace_minutes = coalesce(_grace, 30),
      label = coalesce(_label, ''),
      cycle_state = 'idle',
      next_due_at = _next_due,
      status = case when status = 'declined' then 'pending' else status end,
      updated_at = now()
  where t.id = _task and t.created_by = _uid and t.status in ('pending', 'active', 'declined');

  insert into public.notifications (recipient_id, kind, body, params)
  values (_ward, 'task_updated', '你的报平安任务已被修改，请留意新的时间安排。',
          jsonb_build_object('label', coalesce(_label, '')));
end;
$$;

-- 6) Revoke/grant EXECUTE on the new 8-argument signatures
revoke execute on function public.create_checkin_task(uuid, text, time, time, int, timestamptz, int, text) from public, anon;
revoke execute on function public.update_checkin_task(uuid, text, time, time, int, timestamptz, int, text) from public, anon;
grant execute on function public.create_checkin_task(uuid, text, time, time, int, timestamptz, int, text) to authenticated;
grant execute on function public.update_checkin_task(uuid, text, time, time, int, timestamptz, int, text) to authenticated;

-- 7) Recreate respond_checkin_task (ignore _first_due for daily and compute server-side)
CREATE OR REPLACE FUNCTION public.respond_checkin_task(
  _task uuid,
  _accept boolean,
  _first_due timestamptz default null
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  _uid uuid := auth.uid();
  _t public.checkin_tasks;
  _name text;
  _timezone text;
  _local_date date;
  _next_due timestamptz;
BEGIN
  if _uid is null then raise exception 'not authenticated'; end if;
  select * into _t from public.checkin_tasks where id = _task and ward_id = _uid and status = 'pending';
  if not found then raise exception 'task not found or not pending'; end if;

  if _accept then
    if _t.kind = 'daily' then
      _timezone := null;
      select timezone into _timezone from public.user_settings where user_id = _uid;
      _timezone := coalesce(_timezone, 'UTC');
      _local_date := (now() at time zone _timezone)::date;
      _next_due := (_local_date + _t.due_time_local) at time zone _timezone;
      if _next_due <= now() then
        _next_due := (_local_date + 1 + _t.due_time_local) at time zone _timezone;
      end if;
    else
      _next_due := coalesce(_first_due, now() + make_interval(hours => _t.interval_hours));
    end if;
  end if;

  update public.checkin_tasks
    set status = case when _accept then 'active' else 'declined' end,
        next_due_at = _next_due,
        updated_at = now()
    where id = _task;

  select coalesce(display_name, '') into _name from public.profiles where id = _uid;
  insert into public.notifications (recipient_id, kind, body, params)
  values (_t.created_by,
    case when _accept then 'task_accepted' else 'task_declined' end,
    _name || case when _accept then ' 接受了报平安任务。' else ' 拒绝了报平安任务。' end,
    jsonb_build_object('name', _name, 'label', _t.label));
END;
$$;

revoke execute on function public.respond_checkin_task(uuid, boolean, timestamptz) from public, anon;
grant execute on function public.respond_checkin_task(uuid, boolean, timestamptz) to authenticated;

-- 8) Recreate process_checkin_tasks preserving critical F1 invariants
CREATE OR REPLACE FUNCTION public.process_checkin_tasks()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  t record;
  _done boolean;
  _wname text;
  _timezone text;
  _local_date date;
  _candidate timestamptz;
BEGIN
  -- 1) 到点：提醒承担者 (Claim rows using FOR UPDATE SKIP LOCKED to prevent concurrent cron double-firing)
  FOR t IN
    SELECT * FROM public.checkin_tasks ct
    WHERE status = 'active' AND cycle_state = 'idle'
      AND next_due_at IS NOT NULL AND next_due_at <= now()
      AND NOT private.sleep_relaxed(ct.ward_id, now())
    FOR UPDATE SKIP LOCKED
  LOOP
    INSERT INTO public.notifications (recipient_id, kind, body, params)
    VALUES (t.ward_id, 'task_due', '到点报平安啦，点开 App 完成确认。',
            jsonb_build_object('label', t.label));

    UPDATE public.checkin_tasks
    SET cycle_state = 'due_notified', updated_at = now()
    WHERE id = t.id;
  END LOOP;

  -- 2) 宽限到期：心跳判定完成与否；漏卡 → 通知设置者(自设则通知守护人/同组守望者)
  -- (Claim rows using FOR UPDATE SKIP LOCKED to prevent concurrent cron double-firing)
  FOR t IN
    SELECT * FROM public.checkin_tasks ct
    WHERE status = 'active' AND cycle_state = 'due_notified'
      AND next_due_at + make_interval(mins => ct.grace_minutes) <= now()
      AND NOT private.sleep_relaxed(ct.ward_id, now())
    FOR UPDATE SKIP LOCKED
  LOOP
    -- Judge completion by REAL activity in behavior_pings (exists a behavior_pings row for ward_id with at >= next_due_at), NOT device_state.
    SELECT EXISTS (
      SELECT 1 FROM public.behavior_pings bp
      WHERE bp.user_id = t.ward_id AND bp.at >= t.next_due_at
    ) INTO _done;

    IF NOT _done THEN
      SELECT coalesce(display_name, '') INTO _wname FROM public.profiles WHERE id = t.ward_id;

      INSERT INTO public.notifications (recipient_id, kind, body, params)
      SELECT DISTINCT r.uid, 'task_missed',
        _wname || ' 未完成定时报平安，请关注。',
        jsonb_build_object('name', _wname, 'label', t.label)
      FROM (
        SELECT t.created_by AS uid WHERE t.created_by <> t.ward_id
        UNION
        SELECT g.guardian_id FROM public.guardianships g
          WHERE t.created_by = t.ward_id AND g.ward_id = t.ward_id AND g.status = 'active'
        UNION
        SELECT w.user_id FROM public.group_members gm
          JOIN public.group_members w ON w.group_id = gm.group_id
          WHERE t.created_by = t.ward_id
            AND gm.user_id = t.ward_id AND gm.monitored AND gm.status = 'active'
            AND w.watching AND w.status = 'active' AND w.user_id <> t.ward_id
            AND NOT EXISTS (SELECT 1 FROM public.guardianships g2
                            WHERE g2.ward_id = t.ward_id AND g2.status = 'active')
      ) r;
    END IF;

    -- 滚动下一轮（漏卡也滚动，避免重复轰炸；daily 跳到未来最近一个周期）
    IF t.kind = 'daily' THEN
      _timezone := null;
      SELECT timezone INTO _timezone FROM public.user_settings WHERE user_id = t.ward_id;
      _timezone := coalesce(_timezone, 'UTC');
      _local_date := (now() at time zone _timezone)::date;
      _candidate := (_local_date + t.due_time_local) at time zone _timezone;
      WHILE _candidate <= now() OR _candidate <= t.next_due_at LOOP
        _local_date := _local_date + 1;
        _candidate := (_local_date + t.due_time_local) at time zone _timezone;
      END LOOP;
    ELSE
      _candidate := now() + make_interval(hours => t.interval_hours);
    END IF;

    UPDATE public.checkin_tasks SET
      cycle_state = 'idle',
      next_due_at = _candidate,
      updated_at = now()
      WHERE id = t.id;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.process_checkin_tasks() FROM public, anon, authenticated;
