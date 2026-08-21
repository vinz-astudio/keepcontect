-- A notification nobody can receive is a protection failure, not a no-op.
--
-- `delivery_outcome = 'no_target'` means the row was written and then had nowhere
-- to go: the recipient holds no push token and no web subscription. Historically
-- that has happened 1141 times, and three accounts account for almost all of it
-- (419, 406 and 318 rows) — every one of them with zero tokens and zero
-- subscriptions. Those people are listed as responders in someone's circle while
-- being structurally unreachable, and nothing anywhere said so.
--
-- The existing protection-health machinery already models exactly this shape: a
-- period during which guardianship of an account was known to be degraded, told
-- to the subject once, where acknowledgement is not recovery. `permission_lost`
-- is the right cause — a missing push target is the notification permission
-- never granted, or revoked.

CREATE OR REPLACE FUNCTION private.record_undeliverable_notice()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
  IF NEW.delivery_outcome IS DISTINCT FROM 'no_target' THEN
    RETURN NEW;
  END IF;
  IF OLD.delivery_outcome IS NOT DISTINCT FROM NEW.delivery_outcome THEN
    RETURN NEW;
  END IF;

  -- `protection_health_one_open_per_user` 是按 user 唯一的,不分 cause。只检查
  -- 同 cause 会在这个人已经有另一种原因的打开事件时撞上唯一约束 —— 而这个触发器
  -- 挂在通知投递的写入上,一撞就会让投递本身失败。所以要检查任何打开事件。
  INSERT INTO public.protection_health_incidents (user_id, cause)
  SELECT NEW.recipient_id, 'permission_lost'
  WHERE NOT EXISTS (
    SELECT 1 FROM public.protection_health_incidents AS open_incident
    WHERE open_incident.user_id = NEW.recipient_id
      AND open_incident.closed_at IS NULL
  )
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.record_undeliverable_notice() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS notifications_undeliverable_health ON public.notifications;
CREATE TRIGGER notifications_undeliverable_health
AFTER UPDATE OF delivery_outcome ON public.notifications
FOR EACH ROW
EXECUTE FUNCTION private.record_undeliverable_notice();
