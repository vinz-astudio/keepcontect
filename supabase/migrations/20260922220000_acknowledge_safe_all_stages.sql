-- ---------------------------------------------------------------------------
-- Fix public.acknowledge_safe to allow authenticated users to resolve open
-- alerts regardless of escalation stage (self, group, community, terminal).
-- Also resolves Chunwei's stalled alert that escalated past self stage.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.acknowledge_safe(_alert_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  _uid uuid := auth.uid();
  _target_alert_id uuid;
  _cleared boolean := false;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000';
  END IF;

  IF _alert_id IS NOT NULL THEN
    SELECT id INTO _target_alert_id
    FROM public.alerts
    WHERE id = _alert_id AND user_id = _uid AND status = 'open';
  ELSE
    SELECT id INTO _target_alert_id
    FROM public.alerts
    WHERE user_id = _uid AND status = 'open'
    ORDER BY (stage = 'self') DESC, stage_entered_at DESC
    LIMIT 1;
  END IF;

  IF _target_alert_id IS NOT NULL THEN
    UPDATE public.alerts
    SET status = 'resolved',
        resolved_at = clock_timestamp(),
        resolved_by = _uid,
        updated_at = clock_timestamp()
    WHERE id = _target_alert_id;

    INSERT INTO public.alert_events (alert_id, actor_id, kind, note)
    VALUES (_target_alert_id, _uid, 'resolved', 'self_acknowledged');

    _cleared := true;
  END IF;

  -- Record manual checkin behavior ping to refresh liveness
  BEGIN
    PERFORM private.insert_behavior_ping(_uid, extensions.gen_random_uuid(), clock_timestamp(), 'manual', 'manual_checkin');
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  -- Clean up active self/concern notifications for this user
  DELETE FROM public.notifications
  WHERE recipient_id = _uid AND kind in ('self', 'concern');

  -- Close any missed windows for this user and finalize
  BEGIN
    UPDATE public.passive_checkin_windows
    SET outcome = 'checked_in', finalized_at = clock_timestamp()
    WHERE user_id = _uid AND outcome = 'missed';
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  PERFORM private.trigger_push_dispatch();

  RETURN jsonb_build_object('ok', true, 'cleared_alert', _cleared);
END;
$$;

REVOKE ALL ON FUNCTION public.acknowledge_safe(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.acknowledge_safe(uuid) TO authenticated, service_role;

-- Resolve Chunwei's stalled alert
UPDATE public.alerts
SET status = 'resolved',
    resolved_at = clock_timestamp(),
    resolved_by = user_id,
    updated_at = clock_timestamp()
WHERE id = 'd521905f-041c-442b-b8b5-47adf38faa48' AND status = 'open';

INSERT INTO public.alert_events (alert_id, actor_id, kind, note)
SELECT 'd521905f-041c-442b-b8b5-47adf38faa48', 'f1718b26-f327-4a07-9d10-c8027f419b40', 'resolved', 'self_acknowledged'
WHERE EXISTS (
  SELECT 1 FROM public.alerts WHERE id = 'd521905f-041c-442b-b8b5-47adf38faa48' AND status = 'resolved'
)
AND NOT EXISTS (
  SELECT 1 FROM public.alert_events WHERE alert_id = 'd521905f-041c-442b-b8b5-47adf38faa48' AND kind = 'resolved'
);

DELETE FROM public.notifications
WHERE recipient_id = 'f1718b26-f327-4a07-9d10-c8027f419b40' AND kind in ('self', 'concern');
