-- ADR-0028 narrow repair: make the operational subject-context producer use
-- the evaluator's complete-row provenance contract. Validation remains strict.

CREATE OR REPLACE FUNCTION private.capture_alert_shadow_subject_contexts(
  _version_id uuid,
  _captured_at timestamptz,
  _max_users integer
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET timezone = 'UTC'
AS $$
DECLARE
  _version public.alert_model_versions%ROWTYPE;
  _person record;
  _existing public.alert_judgment_subject_contexts%ROWTYPE;
  _population_count integer := 0;
  _replayable_count integer := 0;
  _unreplayable_count integer := 0;
  _reason text;
  _state text;
  _offset integer;
  _canonical_sensitivity text;
  _context_sha text;
  _existing_expected_sha text;
  _provenance jsonb;
BEGIN
  IF _version_id IS NULL OR _captured_at IS NULL
     OR _max_users IS NULL OR _max_users NOT BETWEEN 1 AND 10000 THEN
    RAISE EXCEPTION 'invalid shadow context capture arguments';
  END IF;

  SELECT v.* INTO _version
  FROM public.alert_model_versions AS v
  WHERE v.id = _version_id
    AND v.status = 'shadow'
    AND v.shadow_enabled_at IS NOT NULL
    AND v.shadow_enabled_at <= _captured_at;

  IF NOT FOUND
     OR _version.evidence_version <> 'canonical-v2'
     OR _version.config_sha256 <>
       encode(extensions.digest(_version.config::text, 'sha256'), 'hex') THEN
    RAISE EXCEPTION 'invalid shadow context version';
  END IF;

  FOR _person IN
    WITH population AS (
      SELECT DISTINCT ds.user_id
      FROM public.device_state AS ds
      WHERE EXISTS (
        SELECT 1
        FROM public.group_members AS gm
        WHERE gm.user_id = ds.user_id
          AND gm.status = 'active'
          AND gm.monitored
      )
    )
    SELECT
      p.user_id,
      coalesce(s.sensitivity, 'balanced') AS sensitivity,
      coalesce(s.timezone, 'UTC') AS timezone,
      coalesce(s.updated_at, _captured_at) AS settings_updated_at,
      coalesce(pr.routine_pattern, 'regular_9to5') AS routine_mode
    FROM population AS p
    LEFT JOIN public.user_settings AS s ON s.user_id = p.user_id
    LEFT JOIN public.profiles AS pr ON pr.id = p.user_id
    ORDER BY p.user_id
    LIMIT _max_users
  LOOP
    _population_count := _population_count + 1;
    _reason := NULL;
    _offset := 0;
    _canonical_sensitivity := CASE
      WHEN lower(trim(coalesce(_person.sensitivity, '')))
        IN ('high', 'sensitive') THEN 'high'
      WHEN lower(trim(coalesce(_person.sensitivity, '')))
        IN ('low', 'relaxed') THEN 'low'
      ELSE 'balanced'
    END;

    IF _person.settings_updated_at > _captured_at THEN
      _reason := 'future_source_timestamp';
    ELSIF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_timezone_names AS z
      WHERE z.name = _person.timezone
    ) THEN
      _reason := 'invalid_timezone';
    ELSE
      _offset := round(extract(epoch FROM (
        (_captured_at AT TIME ZONE _person.timezone)
        - (_captured_at AT TIME ZONE 'UTC')
      )) / 60)::integer;
    END IF;

    _state := CASE WHEN _reason IS NULL THEN 'replayable' ELSE 'unreplayable' END;
    _provenance := jsonb_build_object(
      'contract_version', 'shadow-subject-context-v1',
      'version_id', _version_id,
      'user_id', _person.user_id,
      'sensitivity', _person.sensitivity,
      'routine_mode', _person.routine_mode,
      'timezone', _person.timezone,
      'utc_offset_minutes', _offset,
      'settings_updated_at', _person.settings_updated_at,
      'config_sha256', _version.config_sha256,
      'evidence_version', _version.evidence_version,
      'state', _state,
      'reason', _reason
    );

    IF _reason IS NOT NULL THEN
      _context_sha := encode(
        extensions.digest(_provenance::text, 'sha256'), 'hex'
      );

      UPDATE public.alert_judgment_subject_contexts
      SET effective_to = _captured_at
      WHERE version_id = _version_id
        AND user_id = _person.user_id
        AND effective_to IS NULL
        AND effective_from < _captured_at;
    ELSE
      SELECT context.* INTO _existing
      FROM public.alert_judgment_subject_contexts AS context
      WHERE context.version_id = _version_id
        AND context.user_id = _person.user_id
        AND context.effective_to IS NULL
      ORDER BY context.effective_from DESC
      LIMIT 1;

      IF FOUND THEN
        _existing_expected_sha := encode(extensions.digest(jsonb_build_object(
          'version_id', _existing.version_id,
          'user_id', _existing.user_id,
          'effective_from_utc',
            to_char(_existing.effective_from AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
          'effective_to_utc', NULL,
          'raw_sensitivity', _existing.raw_sensitivity,
          'canonical_sensitivity', _existing.canonical_sensitivity,
          'routine_mode', _existing.routine_mode,
          'timezone', _existing.timezone,
          'utc_offset_minutes', _existing.utc_offset_minutes,
          'settings_updated_at_utc',
            to_char(_existing.settings_updated_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
          'settings_provenance', _existing.settings_provenance,
          'captured_at_utc',
            to_char(_existing.captured_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
          'config_sha256', _existing.config_sha256,
          'evidence_version', _existing.evidence_version
        )::text, 'sha256'), 'hex');
      ELSE
        _existing_expected_sha := NULL;
      END IF;

      IF FOUND
         AND _existing.subject_context_sha256 = _existing_expected_sha
         AND _existing.raw_sensitivity IS NOT DISTINCT FROM _person.sensitivity
         AND _existing.canonical_sensitivity = _canonical_sensitivity
         AND _existing.routine_mode = _person.routine_mode
         AND _existing.timezone = _person.timezone
         AND _existing.utc_offset_minutes = _offset
         AND _existing.settings_updated_at = _person.settings_updated_at
         AND _existing.settings_provenance = _provenance
         AND _existing.config_sha256 = _version.config_sha256
         AND _existing.evidence_version = _version.evidence_version THEN
        _context_sha := _existing.subject_context_sha256;
      ELSE
        _context_sha := encode(extensions.digest(jsonb_build_object(
          'version_id', _version_id,
          'user_id', _person.user_id,
          'effective_from_utc',
            to_char(_captured_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
          'effective_to_utc', NULL,
          'raw_sensitivity', _person.sensitivity,
          'canonical_sensitivity', _canonical_sensitivity,
          'routine_mode', _person.routine_mode,
          'timezone', _person.timezone,
          'utc_offset_minutes', _offset,
          'settings_updated_at_utc',
            to_char(_person.settings_updated_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
          'settings_provenance', _provenance,
          'captured_at_utc',
            to_char(_captured_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
          'config_sha256', _version.config_sha256,
          'evidence_version', _version.evidence_version
        )::text, 'sha256'), 'hex');

        UPDATE public.alert_judgment_subject_contexts
        SET effective_to = _captured_at
        WHERE version_id = _version_id
          AND user_id = _person.user_id
          AND effective_to IS NULL
          AND effective_from < _captured_at;

        INSERT INTO public.alert_judgment_subject_contexts (
          version_id, user_id, effective_from, raw_sensitivity,
          canonical_sensitivity, routine_mode, timezone, utc_offset_minutes,
          settings_updated_at, settings_provenance, captured_at,
          config_sha256, evidence_version, subject_context_sha256
        ) VALUES (
          _version_id, _person.user_id, _captured_at, _person.sensitivity,
          _canonical_sensitivity, _person.routine_mode, _person.timezone, _offset,
          _person.settings_updated_at, _provenance, _captured_at,
          _version.config_sha256, _version.evidence_version, _context_sha
        );
      END IF;
    END IF;

    INSERT INTO private.adaptive_alert_shadow_subject_context_state (
      version_id, user_id, context_state, unreplayable_reason,
      subject_context_sha256, captured_at
    ) VALUES (
      _version_id, _person.user_id, _state, _reason, _context_sha, _captured_at
    )
    ON CONFLICT (version_id, user_id) DO UPDATE SET
      context_state = excluded.context_state,
      unreplayable_reason = excluded.unreplayable_reason,
      subject_context_sha256 = excluded.subject_context_sha256,
      captured_at = excluded.captured_at;

    IF _reason IS NULL THEN
      _replayable_count := _replayable_count + 1;
    ELSE
      _unreplayable_count := _unreplayable_count + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'status', 'completed',
    'population_count', _population_count,
    'replayable_count', _replayable_count,
    'unreplayable_count', _unreplayable_count
  );
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.capture_alert_shadow_subject_contexts(uuid,timestamptz,integer)
FROM PUBLIC, anon, authenticated, service_role;

DO $$
DECLARE
  _runtime private.adaptive_alert_shadow_runtime_config%ROWTYPE;
BEGIN
  SELECT c.* INTO _runtime
  FROM private.adaptive_alert_shadow_runtime_config AS c
  WHERE c.singleton;

  IF FOUND AND _runtime.enabled AND _runtime.version_id IS NOT NULL THEN
    PERFORM private.capture_alert_shadow_subject_contexts(
      _runtime.version_id,
      clock_timestamp(),
      _runtime.max_population
    );
  END IF;
END;
$$;
