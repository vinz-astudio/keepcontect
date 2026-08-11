-- S3-C4 · The Special Attention coverage-interruption notice (ADR-0039).
--
-- Why this exists
-- ---------------
-- Somebody quietly agreed to look out for one particular person. When that
-- person's protection breaks, they are the only ones positioned to check on
-- them. But telling them badly is worse than not telling them:
--
--   * The subject hears first. Nobody learns that someone's phone stopped
--     reporting before that person has been told themselves.
--   * A health grace passes after that prompt. A collector that blinks for two
--     minutes is not news; sending it anyway teaches people to ignore the next
--     one, which is the only thing that would have mattered.
--   * Exactly one notice per subscriber per incident. A flapping collector must
--     not be able to spam anybody, so the uniqueness key does the enforcing
--     rather than a hopeful WHERE clause.
--   * The words say what actually happened: coverage was interrupted, and that
--     is not the same as the person being in danger. Overstating it once costs
--     the response willingness that a real emergency depends on.
--
-- The notice grants nothing. It creates no alert, adds no visibility, and gives
-- the subscriber no authority they did not already have.
--
-- Append-only: no historical migration is edited.

CREATE TABLE IF NOT EXISTS public.special_attention_notices (
  incident_id uuid NOT NULL
    REFERENCES public.protection_health_incidents (id) ON DELETE CASCADE,
  subscriber_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  notified_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (incident_id, subscriber_id)
);

COMMENT ON TABLE public.special_attention_notices IS
  'ADR-0039 one notice per subscriber per protection health incident. The primary key is the anti-spam guarantee.';

ALTER TABLE public.special_attention_notices ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.special_attention_notices FROM PUBLIC;
REVOKE ALL ON TABLE public.special_attention_notices FROM anon;
REVOKE ALL ON TABLE public.special_attention_notices FROM authenticated;

CREATE OR REPLACE FUNCTION private.dispatch_special_attention_notices(
  _grace interval DEFAULT interval '2 hours'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
SET "TimeZone" TO 'UTC'
AS $function$
DECLARE
  _sent integer := 0;
  _row record;
BEGIN
  IF _grace IS NULL OR _grace < interval '0' THEN
    RAISE EXCEPTION 'dispatch_special_attention_notices: invalid grace';
  END IF;

  FOR _row IN
    SELECT h.id AS incident_id, h.user_id AS subject_id, r.subscriber_id
    FROM public.protection_health_incidents AS h
    -- The subject hears first, and only then does the clock start.
    JOIN LATERAL public.special_attention_recipients(h.user_id) AS r ON true
    WHERE h.closed_at IS NULL
      AND h.recovered_at IS NULL
      AND h.prompted_at IS NOT NULL
      AND h.prompted_at <= now() - _grace
      AND NOT EXISTS (
        SELECT 1
        FROM public.special_attention_notices AS n
        WHERE n.incident_id = h.id
          AND n.subscriber_id = r.subscriber_id
      )
  LOOP
    BEGIN
      INSERT INTO public.special_attention_notices (incident_id, subscriber_id)
      VALUES (_row.incident_id, _row.subscriber_id);

      INSERT INTO public.notifications (recipient_id, alert_id, kind, body, params)
      VALUES (
        _row.subscriber_id,
        NULL,
        'coverage_interrupted',
        '你特别关注的人，设备或 App 的守护覆盖中断了，这不代表对方遇险。',
        jsonb_build_object(
          'i18n_key', 'special.notice',
          'subject_id', _row.subject_id,
          'incident_id', _row.incident_id,
          'means_danger', false
        )
      );

      _sent := _sent + 1;
    EXCEPTION WHEN unique_violation THEN
      -- Another cycle got there first. One notice per incident stands.
      NULL;
    END;
  END LOOP;

  RETURN jsonb_build_object('notices_sent', _sent, 'grace', _grace);
END;
$function$;

REVOKE ALL ON FUNCTION private.dispatch_special_attention_notices(interval) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.dispatch_special_attention_notices(interval)
  FROM anon, authenticated;
