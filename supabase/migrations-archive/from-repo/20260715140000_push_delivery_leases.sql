-- Migration: Add push delivery lease columns and atomic claim/finalize RPCs

-- 1. Add delivery-state columns to notifications table
ALTER TABLE public.notifications
  ADD COLUMN delivery_attempts integer NOT NULL DEFAULT 0,
  ADD COLUMN delivery_lease_expiry timestamp with time zone DEFAULT NULL,
  ADD COLUMN delivery_outcome text DEFAULT NULL CHECK (delivery_outcome IN ('sent', 'no_target', 'failed'));

-- 2. Create index to optimize claiming unpushed notifications
CREATE INDEX notifications_delivery_claim_idx ON public.notifications (created_at)
  WHERE pushed_at IS NULL AND delivery_attempts < 5;

-- 3. Define RPC to claim unpushed notifications atomically
CREATE OR REPLACE FUNCTION public.claim_unpushed_notifications(
  p_batch_size integer,
  p_lease_duration interval
)
RETURNS TABLE (
  id uuid,
  recipient_id uuid,
  kind text,
  body text,
  params jsonb,
  alert_id uuid,
  delivery_attempts integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY
  WITH target_rows AS (
    SELECT n.id
    FROM public.notifications n
    WHERE n.pushed_at IS NULL
      AND n.created_at > (now() - interval '24 hours')
      AND (n.delivery_lease_expiry IS NULL OR n.delivery_lease_expiry < now())
      AND n.delivery_attempts < 5
    ORDER BY n.created_at ASC
    LIMIT p_batch_size
    FOR UPDATE SKIP LOCKED
  )
  UPDATE public.notifications n
  SET 
    delivery_lease_expiry = now() + p_lease_duration,
    delivery_attempts = n.delivery_attempts + 1
  FROM target_rows t
  WHERE n.id = t.id
  RETURNING 
    n.id,
    n.recipient_id,
    n.kind,
    n.body,
    n.params,
    n.alert_id,
    n.delivery_attempts;
END;
$$;

-- 4. Define RPC to finalize delivery outcome per notification
CREATE OR REPLACE FUNCTION public.finalize_notification_delivery(
  p_notification_id uuid,
  p_outcome text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_attempts integer;
BEGIN
  -- Validate outcome input
  IF p_outcome NOT IN ('sent', 'no_target', 'retry') THEN
    RAISE EXCEPTION 'Invalid outcome: %', p_outcome;
  END IF;

  SELECT n.delivery_attempts INTO v_attempts
  FROM public.notifications n
  WHERE n.id = p_notification_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Notification not found: %', p_notification_id;
  END IF;

  IF p_outcome = 'sent' THEN
    UPDATE public.notifications
    SET 
      pushed_at = now(),
      delivery_outcome = 'sent',
      delivery_lease_expiry = NULL
    WHERE id = p_notification_id;
  ELSIF p_outcome = 'no_target' THEN
    UPDATE public.notifications
    SET 
      pushed_at = now(),
      delivery_outcome = 'no_target',
      delivery_lease_expiry = NULL
    WHERE id = p_notification_id;
  ELSIF p_outcome = 'retry' THEN
    -- If we hit the max attempt count (5), mark it terminal 'failed' so it stops looping
    IF v_attempts >= 5 THEN
      UPDATE public.notifications
      SET 
        pushed_at = now(),
        delivery_outcome = 'failed',
        delivery_lease_expiry = NULL
      WHERE id = p_notification_id;
    ELSE
      -- Clear the lease so it is immediately eligible for retry on the next cron run
      UPDATE public.notifications
      SET 
        delivery_lease_expiry = NULL
      WHERE id = p_notification_id;
    END IF;
  END IF;
END;
$$;

-- 5. Revoke execute permission from public roles and grant to service_role only
REVOKE EXECUTE ON FUNCTION public.claim_unpushed_notifications(integer, interval) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_unpushed_notifications(integer, interval) TO service_role;

REVOKE EXECUTE ON FUNCTION public.finalize_notification_delivery(uuid, text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_notification_delivery(uuid, text) TO service_role;
