-- Fix inflated silence threshold caused by the extension CTE.
--
-- Root cause: the inline extension CTE in silence_threshold computes
-- inter-session gap p95 from raw v2 pings WITHOUT sleep compensation,
-- then takes greatest() against the properly sleep-compensated profile.
-- Because raw overnight gaps are always >= sleep-compensated gaps, the
-- extension path systematically overrides the profile upward, making
-- the profile's candidate_sleep_intervals subtraction ineffective.
--
-- Fix: remove the extension CTE entirely. The profile is rebuilt daily
-- by dispatch_adaptive_alert_shadow_maintenance (02:17 UTC) and the
-- shadow cycle runs every 5 minutes — a maximum 24h staleness is
-- far preferable to a systematically inflated threshold.
--
-- Boundary: only silence_threshold and shadow_live_definition_matches
-- are replaced. No alert, notification, or escalation table is mutated.

CREATE OR REPLACE FUNCTION private.silence_threshold(_user_id uuid)
RETURNS interval
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
SET TimeZone = 'UTC'
AS $$
DECLARE
  _s text;
  _fixed_minutes integer;
  _version_id uuid;
  _config jsonb;
  _config_sha256 text;
  _evidence_version text;
  _max_age_days integer;
  _buffer_minutes integer;
  _ceiling_minutes integer;
  _profile_minutes integer;
  _personal_minutes integer;
BEGIN
  SELECT sensitivity
    INTO _s
  FROM public.user_settings
  WHERE user_id = _user_id;

  _s := coalesce(_s, 'balanced');
  _fixed_minutes := CASE _s
    WHEN 'high' THEN 90
    WHEN 'sensitive' THEN 90
    WHEN 'low' THEN 180
    WHEN 'relaxed' THEN 180
    ELSE 135
  END;

  SELECT
    runtime.version_id,
    version.config,
    version.config_sha256,
    version.evidence_version
  INTO
    _version_id,
    _config,
    _config_sha256,
    _evidence_version
  FROM private.adaptive_alert_shadow_runtime_config AS runtime
  JOIN public.alert_model_versions AS version
    ON version.id = runtime.version_id
  WHERE runtime.singleton
    AND runtime.enabled
    AND version.status = 'shadow'
    AND version.shadow_enabled_at IS NOT NULL
    AND version.evidence_version = 'canonical-v2'
    AND version.config_sha256
      = encode(extensions.digest(version.config::text, 'sha256'), 'hex')
    AND private.alert_candidate_config_is_valid(version.config);

  IF _version_id IS NULL THEN
    RETURN make_interval(mins => _fixed_minutes);
  END IF;

  BEGIN
    _max_age_days :=
      (_config #>> '{personal,max_age_days}')::integer;
    _buffer_minutes := CASE _s
      WHEN 'high' THEN
        (_config #>> '{sensitivity_buffers_minutes,high}')::integer
      WHEN 'sensitive' THEN
        (_config #>> '{sensitivity_buffers_minutes,high}')::integer
      WHEN 'low' THEN
        (_config #>> '{sensitivity_buffers_minutes,low}')::integer
      WHEN 'relaxed' THEN
        (_config #>> '{sensitivity_buffers_minutes,low}')::integer
      ELSE
        (_config #>> '{sensitivity_buffers_minutes,balanced}')::integer
    END;
    _ceiling_minutes :=
      (_config #>> '{candidate_bounds,ceiling_minutes}')::integer;
  EXCEPTION
    WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      RETURN make_interval(mins => _fixed_minutes);
  END;

  SELECT
    profile.neutral_p95_minutes
  INTO
    _profile_minutes
  FROM public.alert_gap_profiles AS profile
  WHERE profile.version_id = _version_id
    AND profile.user_id = _user_id
    AND profile.context_key = 'personal_global'
    AND profile.quality_state = 'valid'
    AND profile.config_sha256 = _config_sha256
    AND profile.evidence_version = _evidence_version
    AND profile.latest_evidence_at
      >= now() - make_interval(days => _max_age_days)
  ORDER BY profile.through_date DESC, profile.computed_at DESC
  LIMIT 1;

  IF _profile_minutes IS NULL THEN
    RETURN make_interval(mins => _fixed_minutes);
  END IF;

  _personal_minutes := _profile_minutes + _buffer_minutes;

  RETURN make_interval(
    mins => greatest(
      _fixed_minutes,
      least(_ceiling_minutes, _personal_minutes)
    )
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION private.silence_threshold(uuid)
FROM PUBLIC, anon, authenticated, service_role;

-- Update shadow_live_definition_matches to accept the new hash.
-- We compute the hash of the newly replaced silence_threshold at migration
-- time so the shadow safety check remains satisfied.
DO $register_hash$
DECLARE
  _new_lf_sha256 text;
BEGIN
  _new_lf_sha256 := encode(
    extensions.digest(
      replace(
        pg_get_functiondef(
          'private.silence_threshold(uuid)'::regprocedure
        ),
        E'\r\n',
        E'\n'
      ),
      'sha256'
    ),
    'hex'
  );

  EXECUTE format($fn$
    CREATE OR REPLACE FUNCTION private.shadow_live_definition_matches(
      _expected_sha256 text,
      _actual_definition text
    )
    RETURNS boolean
    LANGUAGE sql
    IMMUTABLE
    SECURITY DEFINER
    SET search_path = ''
    AS $$
      WITH hashes AS (
        SELECT
          encode(
            extensions.digest(_actual_definition, 'sha256'),
            'hex'
          ) AS raw_sha256,
          encode(
            extensions.digest(
              replace(_actual_definition, E'\r\n', E'\n'),
              'sha256'
            ),
            'hex'
          ) AS lf_sha256
      )
      SELECT CASE
        WHEN _expected_sha256 !~ '^[a-f0-9]{64}$'
          OR _actual_definition IS NULL
          THEN false
        ELSE
          _expected_sha256 IN (hashes.raw_sha256, hashes.lf_sha256)
          OR (
            _expected_sha256 =
              '1907d59473d274d46a0e8e0b9ce8027037b4494b0dddf073cb46abf67db92e21'
            AND hashes.lf_sha256 IN (
              '686116ef8f2df1d78f6d0d48ded8019555f283b098eeb5d354cfa1c14ebbcdca',
              '6be4ed54feff52428cf1d86210126bd9362953201fc5ac8b9e885abd586092ce',
              %L
            )
          )
      END
      FROM hashes
    $$
  $fn$, _new_lf_sha256);
END;
$register_hash$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.shadow_live_definition_matches(text,text)
FROM PUBLIC, anon, authenticated, service_role;
