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
    UPDATE public.notifications
    SET
      pushed_at = now(),
      delivery_outcome = 'native_missed',
      delivery_lease_expiry = NULL
    WHERE id = p_notification_id;
  ELSIF p_outcome = 'retry' THEN
    IF v_attempts >= 5 THEN
      UPDATE public.notifications
      SET
        pushed_at = now(),
        delivery_outcome = 'failed',
        delivery_lease_expiry = NULL
      WHERE id = p_notification_id;
    ELSE
      UPDATE public.notifications
      SET
        delivery_lease_expiry = NULL
      WHERE id = p_notification_id;
    END IF;
  END IF;
END;
$function$;