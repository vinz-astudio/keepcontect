-- S3-C3 · Authoritative protection health (ADR-0039).
--
-- Why this exists
-- ---------------
-- Staying quiet while blind is this product's most expensive failure, because
-- quiet is exactly what the app looks like when everything is fine. After C2,
-- an account whose coverage broke learns no bound and therefore receives no
-- silence alert. Without this package that account would be silently
-- unprotected, with nothing on screen to say so, while the person and their
-- circle went on believing somebody was watching.
--
--   healthy   = quiet
--   known bad = visible
--   unknown  != safe
--
-- Three rules the rest of the product leans on:
--
--   * Ready requires positive evidence. No recent valid coverage means
--     'unknown', never 'ready'. Silence is not health.
--   * Acknowledgement is separate from recovery. Dismissing the prompt stops
--     the re-prompting and nothing else; only fresh continuous valid coverage
--     restores 'ready'.
--   * A technical outage never becomes a personal alert. Nothing in this file
--     writes an alert row. Manufacturing a personal emergency out of a dead
--     collector is the false positive that costs a group its willingness to
--     answer the next real one.
--
-- Append-only: no historical migration is edited.

CREATE TABLE IF NOT EXISTS public.protection_health_incidents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  opened_at timestamptz NOT NULL DEFAULT now(),
  closed_at timestamptz,
  cause text NOT NULL,
  -- When the subject was told, once. Re-prompting for the same incident is
  -- nagging, not information.
  prompted_at timestamptz,
  -- Acknowledgement is separate from recovery: this field silences the prompt
  -- and never changes the state.
  acknowledged_at timestamptz,
  recovered_at timestamptz,
  recovery_evidence jsonb,
  CONSTRAINT protection_health_cause_check CHECK (
    cause IN ('coverage_gap', 'permission_lost', 'collector_stopped', 'unknown')
  ),
  CONSTRAINT protection_health_close_check CHECK (
    closed_at IS NULL OR closed_at >= opened_at
  ),
  -- An incident may only be recorded as recovered together with the evidence
  -- that recovered it. A bare timestamp would let "it seems fine now" masquerade
  -- as proof.
  CONSTRAINT protection_health_recovery_check CHECK (
    (recovered_at IS NULL) = (recovery_evidence IS NULL)
  )
);

COMMENT ON TABLE public.protection_health_incidents IS
  'ADR-0039 protection health. One row per period during which guardianship of an account was known to be degraded. Acknowledgement is not recovery.';

CREATE UNIQUE INDEX IF NOT EXISTS protection_health_one_open_per_user
  ON public.protection_health_incidents (user_id)
  WHERE closed_at IS NULL;

ALTER TABLE public.protection_health_incidents ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.protection_health_incidents FROM PUBLIC;
REVOKE ALL ON TABLE public.protection_health_incidents FROM anon;
REVOKE ALL ON TABLE public.protection_health_incidents FROM authenticated;

-- The authoritative answer to "is anyone actually watching over me right now?".
-- Owner-scoped: a caller can only ever ask about themselves.
CREATE OR REPLACE FUNCTION public.my_protection_health()
RETURNS TABLE (
  state text,
  since timestamptz,
  cause text,
  prompted_at timestamptz,
  acknowledged_at timestamptz,
  recovery_required text,
  last_valid_coverage_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
SET "TimeZone" TO 'UTC'
AS $function$
DECLARE
  -- One daily coverage cycle plus room for a late finalizer. Beyond this we do
  -- not claim to know anything current about the account.
  _stale_after constant interval := interval '26 hours';
  _uid uuid := auth.uid();
  _incident record;
  _last_valid timestamptz;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT max(i.ends_at) INTO _last_valid
  FROM public.alert_observation_coverage_intervals AS i
  WHERE i.user_id = _uid
    AND i.activity_coverage_state = 'valid'
    AND i.intervention_coverage_state = 'valid'
    AND i.sleep_context_state = 'valid';

  SELECT * INTO _incident
  FROM public.protection_health_incidents AS h
  WHERE h.user_id = _uid
    AND h.closed_at IS NULL
  ORDER BY h.opened_at DESC
  LIMIT 1;

  IF FOUND THEN
    -- Limited. Acknowledgement is separate from recovery, so an acknowledged
    -- incident is still limited; only new continuous valid coverage recovers it.
    RETURN QUERY SELECT
      'limited'::text,
      _incident.opened_at,
      _incident.cause,
      _incident.prompted_at,
      _incident.acknowledged_at,
      'continuous valid coverage from a trusted collector'::text,
      _last_valid;
    RETURN;
  END IF;

  IF _last_valid IS NULL OR _last_valid < now() - _stale_after THEN
    -- Unknown is not safe and not unsafe. We simply have no current evidence
    -- that anyone was watching, and we say so rather than letting the absence
    -- of bad news read as good news.
    RETURN QUERY SELECT
      'unknown'::text,
      _last_valid,
      'coverage_gap'::text,
      NULL::timestamptz,
      NULL::timestamptz,
      'continuous valid coverage from a trusted collector'::text,
      _last_valid;
    RETURN;
  END IF;

  RETURN QUERY SELECT
    'ready'::text,
    _last_valid,
    NULL::text,
    NULL::timestamptz,
    NULL::timestamptz,
    NULL::text,
    _last_valid;
END;
$function$;

-- Dismissing the prompt. This is the only thing a person can do to an incident,
-- and all it does is stop the re-prompting: acknowledgement is separate from
-- recovery and never restores 'ready'.
CREATE OR REPLACE FUNCTION public.acknowledge_protection_health()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;

  update public.protection_health_incidents
  set acknowledged_at = coalesce(acknowledged_at, now())
  where user_id = _uid and closed_at is null;
end;
$function$;

-- Server-side incident maintenance. Opens an incident when coverage has gone
-- stale, and closes one only on genuinely fresh continuous valid coverage,
-- recording what recovered it. It writes no alert: an outage is an outage.
CREATE OR REPLACE FUNCTION private.evaluate_protection_health(_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
SET "TimeZone" TO 'UTC'
AS $function$
DECLARE
  _stale_after constant interval := interval '26 hours';
  _last_valid timestamptz;
  _open_id uuid;
  _action text := 'none';
BEGIN
  IF _user_id IS NULL THEN
    RAISE EXCEPTION 'evaluate_protection_health requires a subject';
  END IF;

  SELECT max(i.ends_at) INTO _last_valid
  FROM public.alert_observation_coverage_intervals AS i
  WHERE i.user_id = _user_id
    AND i.activity_coverage_state = 'valid'
    AND i.intervention_coverage_state = 'valid'
    AND i.sleep_context_state = 'valid';

  SELECT h.id INTO _open_id
  FROM public.protection_health_incidents AS h
  WHERE h.user_id = _user_id AND h.closed_at IS NULL
  LIMIT 1;

  IF _last_valid IS NOT NULL AND _last_valid >= now() - _stale_after THEN
    IF _open_id IS NOT NULL THEN
      UPDATE public.protection_health_incidents
      SET closed_at = now(),
          recovered_at = now(),
          recovery_evidence = jsonb_build_object(
            'last_valid_coverage_at', _last_valid,
            'basis', 'continuous valid coverage from a trusted collector'
          )
      WHERE id = _open_id;
      _action := 'recovered';
    END IF;
  ELSIF _open_id IS NULL THEN
    INSERT INTO public.protection_health_incidents (user_id, cause)
    VALUES (_user_id, 'coverage_gap');
    _action := 'opened';
  END IF;

  RETURN jsonb_build_object('user_id', _user_id, 'action', _action,
                            'last_valid_coverage_at', _last_valid);
END;
$function$;

-- Marks that the subject has been told, once, about this incident.
CREATE OR REPLACE FUNCTION private.mark_protection_health_prompted(_user_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO ''
AS $function$
  UPDATE public.protection_health_incidents
  SET prompted_at = coalesce(prompted_at, now())
  WHERE user_id = _user_id AND closed_at IS NULL;
$function$;

REVOKE ALL ON FUNCTION public.my_protection_health() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.acknowledge_protection_health() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.evaluate_protection_health(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.mark_protection_health_prompted(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.evaluate_protection_health(uuid) FROM anon, authenticated;
REVOKE ALL ON FUNCTION private.mark_protection_health_prompted(uuid) FROM anon, authenticated;

GRANT EXECUTE ON FUNCTION public.my_protection_health() TO authenticated;
GRANT EXECUTE ON FUNCTION public.acknowledge_protection_health() TO authenticated;
