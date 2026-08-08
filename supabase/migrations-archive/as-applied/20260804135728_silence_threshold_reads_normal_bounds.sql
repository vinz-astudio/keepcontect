-- ADR-0037 step 4: the live threshold now reads the account's own learned
-- upper bound. Authorised by the human on 2026-08-04.
--
-- Before: greatest(90/135/180 template, least(600, p95 from frozen July data
-- + buffer)). Six of nine real accounts had had no new evidence admitted since
-- 2026-07-19 and were days from silently reverting to the template outright.
-- After: the account's own i-th largest silence plus its sensitivity buffer,
-- recomputed daily from every device it reports on, with no lease to earn and
-- no constant to clip it.
--
-- The buffer is applied here rather than baked into the stored bound, so a
-- sensitivity change takes effect immediately instead of at the next rebuild.
--
-- NULL is a real answer: an account with no usable evidence gets no silence
-- judgement rather than a fabricated one. The raise loop's comparison then
-- yields NULL and no alert is raised. No such alert is open at deploy time.

CREATE OR REPLACE FUNCTION private.silence_threshold(_user_id uuid)
RETURNS interval
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
SET TimeZone = 'UTC'
AS $$
DECLARE
  _bound_minutes integer;
  _sensitivity text;
  _buffer_minutes integer;
BEGIN
  SELECT bounds.normal_upper_bound_minutes
    INTO _bound_minutes
  FROM public.account_normal_bounds AS bounds
  WHERE bounds.user_id = _user_id
    AND bounds.has_usable_signal
    AND bounds.lookback_days = 30
    AND bounds.false_alarm_budget = 1
  ORDER BY bounds.through_date DESC, bounds.computed_at DESC
  LIMIT 1;

  IF _bound_minutes IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT settings.sensitivity
    INTO _sensitivity
  FROM public.user_settings AS settings
  WHERE settings.user_id = _user_id;

  _buffer_minutes := CASE coalesce(_sensitivity, 'balanced')
    WHEN 'high' THEN 0
    WHEN 'sensitive' THEN 0
    WHEN 'low' THEN 90
    WHEN 'relaxed' THEN 90
    ELSE 45
  END;

  RETURN pg_catalog.make_interval(mins => _bound_minutes + _buffer_minutes);
END;
$$;

REVOKE EXECUTE ON FUNCTION private.silence_threshold(uuid)
FROM PUBLIC, anon, authenticated, service_role;