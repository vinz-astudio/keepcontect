-- Migration: Add genuine activity source to behavior_pings and update process_checkin_tasks to query behavior_pings directly and use skip locked
-- ID: 20260715130000

-- 1) Add source column to behavior_pings
ALTER TABLE public.behavior_pings ADD COLUMN source text;

-- 2) Backfill existing rows to 'app'
UPDATE public.behavior_pings SET source = 'app' WHERE source IS NULL;

-- 3) Add check constraint for valid source values
ALTER TABLE public.behavior_pings
  ADD CONSTRAINT behavior_pings_source_check CHECK (
    source IS NULL OR source IN ('installed_pwa', 'tauri', 'capacitor', 'shortcut', 'manual', 'app')
  );

-- 4) Replace process_checkin_tasks with direct behavior_pings queries and row claiming (SKIP LOCKED)
CREATE OR REPLACE FUNCTION public.process_checkin_tasks()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  t record;
  _done boolean;
  _wname text;
BEGIN
  -- 1) 到点：提醒承担者 (Claim rows using FOR UPDATE SKIP LOCKED to prevent concurrent cron double-firing)
  FOR t IN 
    SELECT * FROM public.checkin_tasks
    WHERE status = 'active' AND cycle_state = 'idle'
      AND next_due_at IS NOT NULL AND next_due_at <= now()
      AND NOT private.sleep_relaxed(t.ward_id, now())
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
    SELECT * FROM public.checkin_tasks
    WHERE status = 'active' AND cycle_state = 'due_notified'
      AND next_due_at + make_interval(mins => t.grace_minutes) <= now()
      AND NOT private.sleep_relaxed(t.ward_id, now())
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
    UPDATE public.checkin_tasks SET
      cycle_state = 'idle',
      next_due_at = CASE
        WHEN kind = 'interval' THEN now() + make_interval(hours => interval_hours)
        ELSE next_due_at + make_interval(days => (ceil(extract(epoch from (now() - next_due_at)) / 86400.0))::int)
      END,
      updated_at = now()
      WHERE id = t.id;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.process_checkin_tasks() FROM public, anon, authenticated;
