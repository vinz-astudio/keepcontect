-- delivery_outcome could not distinguish "reached the user's phone" from "a
-- browser subscription accepted the push". Notification fc6660a7 (a concern
-- sent 2026-08-01) was stamped 'sent' while the recipient's APK — the only
-- device they were carrying — had no FCM token at all and was never woken.
-- That masking is why a dead Android wake channel survived 26 days unnoticed.
--
-- 'native_missed' names the case exactly: the recipient has a native install
-- that reported in recently, but it holds no push token, so nothing can wake
-- it. It is terminal — a retry cannot conjure a token — and it is the value to
-- alarm on:
--   select count(*) from public.notifications
--   where delivery_outcome = 'native_missed' and created_at > now() - interval '1 day';
alter table public.notifications drop constraint notifications_delivery_outcome_check;
alter table public.notifications add constraint notifications_delivery_outcome_check
  check (delivery_outcome = any (array['sent'::text, 'no_target'::text, 'failed'::text, 'native_missed'::text]));

create or replace function public.finalize_notification_delivery(
  p_notification_id uuid,
  p_outcome text
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
DECLARE
  v_attempts integer;
BEGIN
  -- Validate outcome input
  IF p_outcome NOT IN ('sent', 'no_target', 'retry', 'native_missed') THEN
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
  ELSIF p_outcome = 'native_missed' THEN
    -- Terminal like 'no_target': stamped so the claim loop lets it go, but
    -- recorded under its own name so the gap stays visible in the data.
    UPDATE public.notifications
    SET
      pushed_at = now(),
      delivery_outcome = 'native_missed',
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
$function$;
