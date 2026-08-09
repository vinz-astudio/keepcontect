-- NOTIF-01: auto-resolve 不再静默清删告警通知。
-- 诊断(KC-NOTIF-CLEARALL-ACK-001):auto-resolve 两条路径
-- (private.apply_liveness_side_effects + public.process_escalations 条件清除环)
-- 会 DELETE 该 alert 的全部 notifications 且不补任何通知;confirmed_safe 路径却保留
-- 并补发 'resolved'。近 7 天线上 8/8 auto_resolved 告警 notif_left=0。
-- 表象:响应者「Clear all + 我去联系」后所有相关通知无痕消失,认领者也失去
-- 「确认安全」入口(响应卡片完全由通知行派生)。
-- 本迁移:
--   1) 新增 private.notify_auto_resolved:补发 kind='auto_resolved' 通知
--      (目标 + watcher + guardian,与 resolve_alert/notify_stage 接收面一致)。
--   2) 两条 auto-resolve 路径以补发替代删除,保留历史行。
--   3) 新增 public.clear_finished_notifications():Clear all 的 keep 判定移到
--      服务端(仅删非 open 告警的行),根除客户端 items 竞态与 limit 30 陷阱。
-- 兼容:旧客户端对未知 kind 走 body 回退(App 内与 sw.js 皆是);旧客户端的
-- 客户端删除路径在现有 RLS delete 策略下仍合法。

-- 1) 补发助手(私有,仅由 security definer 流程调用)
create or replace function private.notify_auto_resolved(_alert_id uuid, _target uuid)
returns void language plpgsql security definer set search_path to '' as $$
declare _tname text;
begin
  select coalesce(display_name, '') into _tname from public.profiles where id = _target;
  insert into public.notifications (recipient_id, alert_id, kind, body, params)
  select distinct s.r, _alert_id, 'auto_resolved',
    coalesce(nullif(_tname, ''), '成员') || ' 的告警已自动解除(检测到活动恢复)。',
    jsonb_build_object('target', _tname)
  from (
    select _target as r
    union
    select w.user_id from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _target and t.monitored and t.status = 'active'
        and w.watching and w.status = 'active'
    union
    select g.guardian_id from public.guardianships g
      where g.ward_id = _target and g.status = 'active'
  ) s;
end;
$$;

revoke execute on function private.notify_auto_resolved(uuid, uuid) from public, anon, authenticated;

-- 2a) liveness 摄入路径:删除 → 补发(其余逻辑与线上现行版本逐字一致)
CREATE OR REPLACE FUNCTION private.apply_liveness_side_effects(_user_id uuid, _observed_at timestamp with time zone, _received_at timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

-- 2b) cron 条件清除环:删除 → 补发(其余逻辑与线上现行版本逐字一致)
CREATE OR REPLACE FUNCTION public.process_escalations()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  _self_grace CONSTANT interval := interval '30 minutes';
  _group_dur  CONSTANT interval := interval '1 hour';
  _comm_dur   CONSTANT interval := interval '2 hours';
  r record; _aid uuid; _new text; _triggered boolean := false;
BEGIN
  -- First clear open alerts that no longer match current account-level truth.
  FOR r IN
    SELECT a.id, a.user_id, a.cause, ds.last_heartbeat_at, bp.last_at as last_behavior_at
    FROM public.alerts a
    LEFT JOIN public.device_state ds ON ds.user_id = a.user_id
    LEFT JOIN LATERAL (
      SELECT max(received_at) as last_at
      FROM public.behavior_pings
      WHERE user_id = a.user_id
        -- Live safety requires ingest_version=2, drift, and causal-time checks.
        AND ingest_version = 2
        AND abs(extract(epoch from (received_at - at))) <= 300 -- drift <= 5m
        -- auto-resolution for silence MUST require a qualifying v2 ping with BOTH received_at>=opened_at and at>=opened_at
        AND received_at >= a.opened_at
        AND at >= a.opened_at
    ) bp ON true
    WHERE a.status = 'open'
      AND a.cause in ('silence', 'dark_device')
      AND (
        (
          a.cause = 'silence'
          AND bp.last_at IS NOT NULL
          AND (
            private.is_in_sleep_window(a.user_id, now())
            -- Note: The ADR's alert-created-at concept maps to alerts.opened_at (created_at search text)
            OR now() - bp.last_at <= private.silence_threshold(a.user_id)
          )
        )
        OR (
          a.cause = 'dark_device'
          AND ds.last_heartbeat_at IS NOT NULL
          AND now() - ds.last_heartbeat_at <= interval '18 hours'
        )
      )
  LOOP
    UPDATE public.alerts
      SET status = 'resolved', resolved_at = now(), resolved_by = null, updated_at = now()
      WHERE id = r.id;
    INSERT INTO public.alert_events (alert_id, kind, note)
      VALUES (r.id, 'auto_resolved', 'condition_cleared');
    -- NOTIF-01: 保留该告警的通知历史,改为补发自动解除通知
    PERFORM private.notify_auto_resolved(r.id, r.user_id);
    _triggered := true;
  END LOOP;

  FOR r IN
    SELECT ds.user_id,
           (now() - ds.last_heartbeat_at) > interval '18 hours' as is_dark
    FROM public.device_state ds
    WHERE (
      ds.status = 'alert'
      OR now() - ds.last_heartbeat_at > interval '18 hours'
      OR (
        NOT private.is_in_sleep_window(ds.user_id, now())
        AND now() - (
          SELECT coalesce(max(received_at), to_timestamp(0))
          FROM public.behavior_pings
          WHERE user_id = ds.user_id
            -- Live safety requires ingest_version=2, drift, and causal-time checks.
            AND ingest_version = 2
            AND abs(extract(epoch from (received_at - at))) <= 300 -- drift <= 5m
        ) > private.silence_threshold(ds.user_id)
      )
    )
      AND exists (SELECT 1 FROM public.group_members gm
                  WHERE gm.user_id = ds.user_id and gm.monitored and gm.status = 'active')
      AND NOT exists (SELECT 1 FROM public.alerts a WHERE a.user_id = ds.user_id and a.status = 'open')
      AND NOT exists (
        SELECT 1 FROM public.alerts recent
        -- Note: The ADR's alert-created-at concept maps to alerts.opened_at (created_at search text)
        WHERE recent.user_id = ds.user_id
          AND recent.status = 'resolved'
          AND recent.cause in ('silence', 'dark_device')
          AND recent.resolved_by IS NOT NULL
          AND recent.resolved_by <> recent.user_id
          AND recent.resolved_at > now() - _self_grace
      )
  LOOP
    INSERT INTO public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    VALUES (r.user_id, CASE WHEN r.is_dark THEN 'dark_device' ELSE 'silence' end,
            'self', now(), now() + _self_grace)
    RETURNING id INTO _aid;
    INSERT INTO public.alert_events (alert_id, kind) values (_aid, 'raised');
    PERFORM private.notify_stage(_aid, r.user_id, 'self');
    _triggered := true;
  END LOOP;

  FOR r IN
    SELECT * FROM public.alerts
    WHERE status = 'open'
      AND next_deadline IS NOT NULL AND next_deadline <= now()
      AND coalesce(paused_until, to_timestamp(0)) <= now()
  LOOP
    _new := CASE r.stage
              WHEN 'self' THEN 'group'
              WHEN 'group' THEN 'community'
              WHEN 'community' THEN 'terminal'
              ELSE 'terminal' end;
    UPDATE public.alerts
      SET stage = _new, stage_entered_at = now(), paused_until = null, paused_by = null, updated_at = now(),
          next_deadline = CASE _new WHEN 'group' THEN now() + _group_dur
                                    WHEN 'community' THEN now() + _comm_dur
                                    ELSE null end
      WHERE id = r.id;
    INSERT INTO public.alert_events (alert_id, kind, note) VALUES (r.id, 'escalated', _new);
    PERFORM private.notify_stage(r.id, r.user_id, _new);
    _triggered := true;
  END LOOP;

  IF _triggered THEN
    PERFORM private.trigger_push_dispatch();
  END IF;
END;
$function$;

-- 3) Clear all 的服务端 keep 判定:仅删「无 alert 或 alert 已非 open」的本人通知
create or replace function public.clear_finished_notifications()
returns void language sql security definer set search_path to '' as $$
  delete from public.notifications n
  where n.recipient_id = auth.uid()
    and (
      n.alert_id is null
      or not exists (
        select 1 from public.alerts a
        where a.id = n.alert_id and a.status = 'open'
      )
    );
$$;

revoke execute on function public.clear_finished_notifications() from public, anon;
grant execute on function public.clear_finished_notifications() to authenticated;
