-- 2026-08-02 (20260802140000_activity_never_answers_an_alert) settled the rule:
-- the alert asks "are you all right", and the only shape an answer takes is the
-- subject deliberately unlocking. Passive activity proves the device is alive,
-- not that the person has answered — a very ill person propping themselves up
-- still generates activity, and they are precisely who this mechanism exists for.
--
-- That rule was applied to private.apply_liveness_side_effects. It was not
-- applied here. process_escalations' clearance loop still carried the original
-- rule, written 2026-06-10 in 20260610142413_escalation_logic.sql as:
--
--   -- 2) 自动解除：设备已恢复正常且心跳新鲜（非 SOS）
--
-- The comment names a device. The action closed an alert about a person. That
-- conflation was never a recorded decision; it is the first version's wording
-- surviving untouched through every later rewrite. Three copies of it existed:
-- the behavior-ping trigger (dropped 2026-07-19), apply_liveness_side_effects
-- (corrected 2026-08-02), and this one.
--
-- Production, 2026-08-07: since the 08-02 correction landed, the ping-driven
-- path has fired zero times and this loop has fired once in five days, so the
-- change removes a contradiction rather than a working behaviour.
--
-- Removed from the clearance loop:
--   * silence cleared by a fresh qualifying ping   — activity, not an answer
--   * dark_device cleared by a returning heartbeat — activity, not an answer
--
-- Kept, because it is not activity: configured sleep and the post-wake grace.
-- That branch does not accept an answer on the subject's behalf. It withdraws an
-- alert whose premise — "this silence is unusual" — is false inside a window
-- where silence is exactly what is expected. It remains the only way this
-- function may close an alert; everything else must go through the subject's own
-- unlock (public.resolve_my_alert), a responder's confirm-safe
-- (public.resolve_alert), or GM intervention.
--
-- Nothing else in this function changes: the raise loop, the escalation loop,
-- the GM mute gate and the responder grace are reproduced verbatim.
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
  r record;
  _aid uuid;
  _new text;
  _triggered boolean := false;
BEGIN
  -- Sleep/post-wake grace withdraws a silence alert it was wrong to raise.
  -- Activity never closes an alert here; see the migration header.
  FOR r IN
    SELECT
      a.id,
      a.user_id
    FROM public.alerts AS a
    WHERE a.status = 'open'
      AND a.cause = 'silence'
      AND private.sleep_relaxed(a.user_id, now())
  LOOP
    UPDATE public.alerts
    SET status = 'resolved',
        resolved_at = now(),
        resolved_by = NULL,
        updated_at = now()
    WHERE id = r.id;

    INSERT INTO public.alert_events (alert_id, kind, note)
    VALUES (r.id, 'auto_resolved', 'sleep_grace');

    PERFORM private.notify_auto_resolved(r.id, r.user_id);
    _triggered := true;
  END LOOP;

  -- device_state.status is descriptive state, not an independent authority to
  -- bypass the canonical silence calculation or sleep grace.
  FOR r IN
    SELECT
      ds.user_id,
      (now() - ds.last_heartbeat_at) > interval '18 hours' AS is_dark
    FROM public.device_state AS ds
    WHERE (
      now() - ds.last_heartbeat_at > interval '18 hours'
      OR (
        NOT private.sleep_relaxed(ds.user_id, now())
        AND now() - (
          SELECT coalesce(max(received_at), to_timestamp(0))
          FROM public.behavior_pings
          WHERE user_id = ds.user_id
            AND ingest_version = 2
            AND abs(extract(epoch FROM (received_at - at))) <= 300
        ) > private.silence_threshold(ds.user_id)
      )
    )
      AND EXISTS (
        SELECT 1
        FROM public.group_members AS gm
        WHERE gm.user_id = ds.user_id
          AND gm.monitored
          AND gm.status = 'active'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.alerts AS a
        WHERE a.user_id = ds.user_id
          AND a.status = 'open'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.alerts AS recent
        WHERE recent.user_id = ds.user_id
          AND recent.status = 'resolved'
          AND recent.cause IN ('silence', 'dark_device')
          AND recent.resolved_by IS NOT NULL
          AND recent.resolved_by <> recent.user_id
          AND recent.resolved_at > now() - _self_grace
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.gm_mutes AS mute
        WHERE mute.user_id = ds.user_id
          AND (mute.muted_until IS NULL OR mute.muted_until > now())
      )
  LOOP
    INSERT INTO public.alerts (
      user_id, cause, stage, stage_entered_at, next_deadline
    )
    VALUES (
      r.user_id,
      CASE WHEN r.is_dark THEN 'dark_device' ELSE 'silence' END,
      'self',
      now(),
      now() + _self_grace
    )
    RETURNING id INTO _aid;

    INSERT INTO public.alert_events (alert_id, kind)
    VALUES (_aid, 'raised');

    PERFORM private.notify_stage(_aid, r.user_id, 'self');
    _triggered := true;
  END LOOP;

  FOR r IN
    SELECT *
    FROM public.alerts
    WHERE status = 'open'
      AND next_deadline IS NOT NULL
      AND next_deadline <= now()
      AND coalesce(paused_until, to_timestamp(0)) <= now()
  LOOP
    _new := CASE r.stage
      WHEN 'self' THEN 'group'
      WHEN 'group' THEN 'community'
      WHEN 'community' THEN 'terminal'
      ELSE 'terminal'
    END;

    UPDATE public.alerts
    SET stage = _new,
        stage_entered_at = now(),
        paused_until = NULL,
        paused_by = NULL,
        updated_at = now(),
        next_deadline = CASE _new
          WHEN 'group' THEN now() + _group_dur
          WHEN 'community' THEN now() + _comm_dur
          ELSE NULL
        END
    WHERE id = r.id;

    INSERT INTO public.alert_events (alert_id, kind, note)
    VALUES (r.id, 'escalated', _new);

    PERFORM private.notify_stage(r.id, r.user_id, _new);
    _triggered := true;
  END LOOP;

  IF _triggered THEN
    PERFORM private.trigger_push_dispatch();
  END IF;
END;
$function$;
