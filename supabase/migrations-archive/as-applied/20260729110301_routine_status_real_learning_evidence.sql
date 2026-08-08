-- ADR-0029 P5: surface REAL learning evidence through my_routine_status.
-- Additive, read-only. Does not touch private.silence_threshold and grants the
-- learned pipeline no live alert authority (ADR-0022 remains sole live authority).

CREATE OR REPLACE FUNCTION public.my_routine_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $$
DECLARE
  _uid uuid := auth.uid();
  _threshold interval;
  _last_at timestamptz;
  _s text;
  _sleep_start time;
  _sleep_end time;
  _timezone text;
  _in_sleep_window boolean;
  _model_confidence double precision;
  _model_explanation text;
  _model_version text;
  _version_id uuid;
  _learning_active boolean := false;
  _min_support_dates integer;
  _sample_count integer;
  _support_days integer;
  _quality_state text;
  _confidence double precision;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT sensitivity, sleep_start_local, sleep_end_local, timezone
    INTO _s, _sleep_start, _sleep_end, _timezone
    FROM public.user_settings
   WHERE user_id = _uid;

  SELECT model_confidence, model_explanation, model_version
    INTO _model_confidence, _model_explanation, _model_version
    FROM public.user_activity_profiles
   WHERE user_id = _uid;

  _threshold := private.silence_threshold(_uid);
  _in_sleep_window := private.is_in_sleep_window(_uid, now());

  SELECT max(received_at)
    INTO _last_at
    FROM public.behavior_pings
   WHERE user_id = _uid
     AND ingest_version = 2
     AND abs(extract(epoch from (received_at - at))) <= 300;

  SELECT c.version_id
    INTO _version_id
    FROM private.adaptive_alert_shadow_runtime_config AS c
   WHERE c.singleton
     AND c.enabled
     AND c.version_id IS NOT NULL;

  IF _version_id IS NOT NULL THEN
    SELECT (v.config #>> '{personal,min_support_dates}')::integer
      INTO _min_support_dates
      FROM public.alert_model_versions AS v
     WHERE v.id = _version_id
       AND v.status = 'shadow';

    _learning_active := _min_support_dates IS NOT NULL;

    SELECT gp.sample_count, gp.distinct_support_dates, gp.quality_state, gp.confidence
      INTO _sample_count, _support_days, _quality_state, _confidence
      FROM public.alert_gap_profiles AS gp
     WHERE gp.version_id = _version_id
       AND gp.user_id = _uid
       AND gp.context_key = 'personal_global'
     ORDER BY gp.through_date DESC
     LIMIT 1;
  END IF;

  RETURN jsonb_build_object(
    'threshold_seconds', extract(epoch from _threshold)::bigint,
    'last_behavior_at', _last_at,
    'sensitivity', coalesce(_s, 'balanced'),
    'sleep_start', _sleep_start,
    'sleep_end', _sleep_end,
    'timezone', coalesce(_timezone, 'UTC'),
    'in_sleep_window', coalesce(_in_sleep_window, false),
    'model_confidence', _model_confidence,
    'model_explanation', _model_explanation,
    'model_version', _model_version,
    'learning_active', _learning_active,
    'evidence_sample_count', _sample_count,
    'evidence_support_days', _support_days,
    'evidence_min_support_days', _min_support_dates,
    'evidence_quality_state', _quality_state,
    'evidence_confidence', _confidence
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.my_routine_status() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.my_routine_status() TO authenticated;