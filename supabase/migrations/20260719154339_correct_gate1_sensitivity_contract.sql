-- ADR-0022: restore sensitivity as an additive user tool on the
-- deterministic Gate 1 neutral base. Learned activity profiles remain
-- quarantined from live safety authority.
CREATE OR REPLACE FUNCTION private.silence_threshold(_user_id uuid)
RETURNS interval
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _s text;
BEGIN
  SELECT sensitivity
    INTO _s
    FROM public.user_settings
   WHERE user_id = _user_id;

  _s := coalesce(_s, 'balanced');

  RETURN CASE _s
    WHEN 'high' THEN interval '1.5 hours'
    WHEN 'sensitive' THEN interval '1.5 hours'
    WHEN 'low' THEN interval '3 hours'
    WHEN 'relaxed' THEN interval '3 hours'
    ELSE interval '2.25 hours'
  END;
END;
$$;

REVOKE EXECUTE ON FUNCTION private.silence_threshold(uuid) FROM PUBLIC, anon, authenticated;
