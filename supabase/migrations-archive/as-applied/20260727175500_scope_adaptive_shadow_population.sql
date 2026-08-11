-- ADR-0028 audit repair: operational shadow population is the intersection of
-- registered device state and at least one active monitored group direction.
-- This append-only correction preserves scheduler-off and shadow-only behavior.

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
  _population_count integer := 0;
  _replayable_count integer := 0;
  _unreplayable_count integer := 0;
  _reason text;
  _state text;
  _offset integer;
  _context_sha text;
  _prior_sha text;
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
    _context_sha := encode(
      extensions.digest(_provenance::text, 'sha256'), 'hex'
    );

    SELECT s.subject_context_sha256 INTO _prior_sha
    FROM private.adaptive_alert_shadow_subject_context_state AS s
    WHERE s.version_id = _version_id AND s.user_id = _person.user_id;

    IF _reason IS NOT NULL THEN
      UPDATE public.alert_judgment_subject_contexts
      SET effective_to = _captured_at
      WHERE version_id = _version_id
        AND user_id = _person.user_id
        AND effective_to IS NULL
        AND effective_from < _captured_at;
    ELSIF _prior_sha IS DISTINCT FROM _context_sha THEN
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
        _person.sensitivity, _person.routine_mode, _person.timezone, _offset,
        _person.settings_updated_at, _provenance, _captured_at,
        _version.config_sha256, _version.evidence_version, _context_sha
      );
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

CREATE OR REPLACE FUNCTION private.record_alert_judgment_shadow_operational(
  _version_id uuid,
  _evaluated_at timestamptz,
  _max_population integer
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET timezone = 'UTC'
SET "DateStyle" = 'ISO, YMD'
SET extra_float_digits = 3
AS $$
DECLARE
  _person_id uuid;
  _result jsonb;
  _replayable boolean;
  _reason text;
  _decision_sha text;
  _prior private.adaptive_alert_shadow_user_state%ROWTYPE;
  _fallback_path text[];
  _population_count integer := 0;
  _evaluated_count integer := 0;
  _replayable_count integer := 0;
  _unreplayable_count integer := 0;
  _persisted_count integer := 0;
  _detail_count integer;
  _should_persist boolean;
  _minute timestamptz;
  _provenance_sha text;
  _result_key_count integer;
  _minute_utc text;
  _required_keys constant text[] := ARRAY[
    'basis', 'candidate_cap_reason', 'candidate_ceiling_minutes',
    'candidate_deadline', 'candidate_floor_minutes',
    'candidate_threshold_minutes', 'confidence', 'context_key',
    'deadline_basis', 'decision_provenance', 'effective_silence_minutes',
    'evaluated_at', 'evaluator_version', 'evidence_cutoff', 'fallback_path',
    'guardian_used_as_activity', 'neutral_threshold_minutes',
    'provenance_sha256', 'quality_state', 'replayable',
    'selected_source_sha256', 'sensitivity_buffer_minutes',
    'sleep_interval_provenance', 'subject_context_sha256',
    'unclamped_candidate_threshold_minutes', 'unreplayable_reason',
    'version_id', 'would_alert'
  ];
BEGIN
  IF _version_id IS NULL OR _evaluated_at IS NULL
     OR _max_population IS NULL OR _max_population NOT BETWEEN 1 AND 10000 THEN
    RAISE EXCEPTION 'invalid operational shadow recorder arguments';
  END IF;
  _minute := date_trunc('minute', _evaluated_at AT TIME ZONE 'UTC')
    AT TIME ZONE 'UTC';
  _minute_utc := to_char(
    _minute AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
  );

  FOR _person_id IN
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
    SELECT p.user_id
    FROM population AS p
    ORDER BY p.user_id
    LIMIT _max_population
  LOOP
    _population_count := _population_count + 1;
    _result := private.resolve_alert_candidate(_person_id, _minute, _version_id);
    _evaluated_count := _evaluated_count + 1;

    IF _result IS NULL OR jsonb_typeof(_result) <> 'object' THEN
      RAISE EXCEPTION 'malformed operational shadow result';
    END IF;
    SELECT count(*)::integer INTO _result_key_count
    FROM jsonb_object_keys(_result);
    IF NOT (_result ?& _required_keys)
       OR _result_key_count <> cardinality(_required_keys)
       OR jsonb_typeof(_result -> 'replayable') <> 'boolean'
       OR _result ->> 'version_id' <> _version_id::text
       OR _result ->> 'evaluated_at' <> _minute_utc
       OR _result ->> 'evidence_cutoff' <> _minute_utc
       OR _result ->> 'evaluator_version' <> 'adaptive_candidate_v1'
       OR jsonb_typeof(_result -> 'decision_provenance') <> 'object'
       OR jsonb_typeof(_result -> 'provenance_sha256') <> 'string'
       OR jsonb_typeof(_result -> 'guardian_used_as_activity') <> 'boolean'
       OR (_result ->> 'guardian_used_as_activity')::boolean THEN
      RAISE EXCEPTION 'malformed operational shadow result';
    END IF;

    _provenance_sha := encode(
      extensions.digest((_result -> 'decision_provenance')::text, 'sha256'),
      'hex'
    );
    IF _result ->> 'provenance_sha256' <> _provenance_sha THEN
      RAISE EXCEPTION 'operational shadow provenance mismatch';
    END IF;

    _replayable := (_result ->> 'replayable')::boolean;
    _reason := _result ->> 'unreplayable_reason';
    _decision_sha := encode(extensions.digest(jsonb_build_object(
      'version_id', _version_id,
      'user_id', _person_id,
      'evaluated_minute', _minute,
      'evaluator_result', _result
    )::text, 'sha256'), 'hex');

    SELECT s.* INTO _prior
    FROM private.adaptive_alert_shadow_user_state AS s
    WHERE s.version_id = _version_id AND s.user_id = _person_id;

    _should_persist := _replayable AND (
      NOT FOUND
      OR _prior.would_alert IS DISTINCT FROM
        (_result ->> 'would_alert')::boolean
      OR _prior.basis IS DISTINCT FROM _result ->> 'basis'
      OR _prior.candidate_threshold_minutes IS DISTINCT FROM
        (_result ->> 'candidate_threshold_minutes')::integer
      OR _prior.quality_state IS DISTINCT FROM _result ->> 'quality_state'
      OR _prior.unreplayable_reason IS DISTINCT FROM _reason
      OR _prior.last_persisted_at IS NULL
      OR _prior.last_persisted_at <= _minute - interval '1 hour'
    );

    INSERT INTO private.adaptive_alert_shadow_user_state (
      version_id, user_id, evaluated_at, replayable, would_alert, basis,
      candidate_threshold_minutes, quality_state, unreplayable_reason,
      decision_sha256, last_persisted_at, updated_at
    ) VALUES (
      _version_id, _person_id, _minute, _replayable,
      CASE WHEN _replayable THEN (_result ->> 'would_alert')::boolean END,
      CASE WHEN _replayable THEN _result ->> 'basis' END,
      CASE WHEN _replayable
        THEN (_result ->> 'candidate_threshold_minutes')::integer END,
      coalesce(_result ->> 'quality_state', 'coverage_invalid'),
      CASE WHEN _replayable THEN NULL ELSE _reason END,
      _decision_sha,
      CASE WHEN _should_persist THEN _minute ELSE _prior.last_persisted_at END,
      clock_timestamp()
    )
    ON CONFLICT (version_id, user_id) DO UPDATE SET
      evaluated_at = excluded.evaluated_at,
      replayable = excluded.replayable,
      would_alert = excluded.would_alert,
      basis = excluded.basis,
      candidate_threshold_minutes = excluded.candidate_threshold_minutes,
      quality_state = excluded.quality_state,
      unreplayable_reason = excluded.unreplayable_reason,
      decision_sha256 = excluded.decision_sha256,
      last_persisted_at = excluded.last_persisted_at,
      updated_at = excluded.updated_at;

    IF NOT _replayable THEN
      IF _reason NOT IN (
        'missing_subject_context', 'ambiguous_subject_context',
        'subject_context_provenance_invalid', 'missing_qualified_session'
      ) THEN
        RAISE EXCEPTION 'invalid operational shadow unreplayable reason';
      END IF;
      _unreplayable_count := _unreplayable_count + 1;
      CONTINUE;
    END IF;

    IF _result ->> 'basis' IS NULL
       OR _result ->> 'candidate_threshold_minutes' IS NULL
       OR _result ->> 'subject_context_sha256' IS NULL
       OR jsonb_typeof(_result -> 'fallback_path') <> 'array' THEN
      RAISE EXCEPTION 'malformed replayable operational shadow result';
    END IF;

    IF _should_persist THEN
      SELECT count(*)::integer INTO _detail_count
      FROM public.alert_judgment_shadow_decisions AS d
      WHERE d.version_id = _version_id
        AND d.user_id = _person_id
        AND d.evaluated_at >= date_trunc('day', _minute)
        AND d.evaluated_at < date_trunc('day', _minute) + interval '1 day';
      IF _detail_count >= 36 THEN
        RAISE EXCEPTION 'shadow_detail_budget_exceeded';
      END IF;

      SELECT array_agg(path.value ORDER BY path.ordinal)
        INTO _fallback_path
      FROM jsonb_array_elements_text(_result -> 'fallback_path')
        WITH ORDINALITY AS path(value, ordinal);

      INSERT INTO public.alert_judgment_shadow_decisions (
        version_id, user_id, evaluated_at, basis, evaluator_version,
        context_key, neutral_threshold_minutes, sensitivity_buffer_minutes,
        candidate_threshold_minutes, effective_silence_minutes,
        candidate_deadline, would_alert, confidence, quality_state,
        fallback_path, sleep_interval_provenance, provenance_sha256,
        guardian_used_as_activity, evidence_cutoff,
        unclamped_candidate_threshold_minutes, candidate_floor_minutes,
        candidate_ceiling_minutes, candidate_cap_reason, deadline_basis,
        selected_source_sha256, subject_context_sha256,
        decision_provenance, decision_sha256
      ) VALUES (
        _version_id, _person_id, _minute, _result ->> 'basis',
        _result ->> 'evaluator_version', _result ->> 'context_key',
        (_result ->> 'neutral_threshold_minutes')::integer,
        (_result ->> 'sensitivity_buffer_minutes')::integer,
        (_result ->> 'candidate_threshold_minutes')::integer,
        (_result ->> 'effective_silence_minutes')::double precision,
        (_result ->> 'candidate_deadline')::timestamptz,
        (_result ->> 'would_alert')::boolean,
        (_result ->> 'confidence')::double precision,
        _result ->> 'quality_state', _fallback_path,
        _result -> 'sleep_interval_provenance', _provenance_sha, false,
        (_result ->> 'evidence_cutoff')::timestamptz,
        (_result ->> 'unclamped_candidate_threshold_minutes')::integer,
        (_result ->> 'candidate_floor_minutes')::integer,
        (_result ->> 'candidate_ceiling_minutes')::integer,
        _result ->> 'candidate_cap_reason',
        _result ->> 'deadline_basis',
        _result ->> 'selected_source_sha256',
        _result ->> 'subject_context_sha256',
        _result -> 'decision_provenance', _decision_sha
      )
      ON CONFLICT (version_id, user_id, evaluated_minute) DO NOTHING;
      IF FOUND THEN
        _persisted_count := _persisted_count + 1;
      END IF;
    END IF;
    _replayable_count := _replayable_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'status', CASE WHEN _population_count = 0 THEN 'empty' ELSE 'completed' END,
    'population_count', _population_count,
    'evaluated_count', _evaluated_count,
    'replayable_count', _replayable_count,
    'unreplayable_count', _unreplayable_count,
    'persisted_count', _persisted_count
  );
END;
$$;

CREATE OR REPLACE FUNCTION private.run_adaptive_alert_shadow_cycle(
  _version_id uuid,
  _evaluated_at timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET timezone = 'UTC'
AS $$
DECLARE
  _runtime private.adaptive_alert_shadow_runtime_config%ROWTYPE;
  _version public.alert_model_versions%ROWTYPE;
  _minute timestamptz;
  _started_at timestamptz := clock_timestamp();
  _result jsonb;
  _population_count integer;
  _evaluated_count integer;
  _before_dml bigint := 0;
  _after_dml bigint := 0;
  _duration_ms integer;
  _metrics jsonb;
  _run_sha text;
  _person_id uuid;
  _population_total integer;
BEGIN
  SELECT c.* INTO _runtime
  FROM private.adaptive_alert_shadow_runtime_config AS c
  WHERE c.singleton;
  IF _runtime.enabled IS NOT TRUE THEN
    RETURN jsonb_build_object('status', 'disabled');
  END IF;
  IF _runtime.version_id IS DISTINCT FROM _version_id THEN
    RAISE EXCEPTION 'shadow_runtime_version_mismatch';
  END IF;
  IF _evaluated_at IS NULL THEN
    RAISE EXCEPTION 'shadow_invalid_evaluation_time';
  END IF;
  _minute := date_trunc('minute', _evaluated_at AT TIME ZONE 'UTC')
    AT TIME ZONE 'UTC';

  IF EXISTS (
    SELECT 1 FROM private.adaptive_alert_shadow_cycle_runs AS r
    WHERE r.version_id = _version_id AND r.evaluated_minute = _minute
  ) THEN
    RETURN jsonb_build_object('status', 'duplicate');
  END IF;
  IF NOT pg_try_advisory_xact_lock(
    hashtextextended('adaptive-alert-shadow:' || _version_id::text, 0)
  ) THEN
    RETURN jsonb_build_object('status', 'busy');
  END IF;

  SELECT v.* INTO _version
  FROM public.alert_model_versions AS v
  WHERE v.id = _version_id;
  IF NOT FOUND OR _version.status <> 'shadow'
     OR _version.shadow_enabled_at IS NULL
     OR _version.shadow_enabled_at > _minute
     OR _version.evidence_version <> 'canonical-v2'
     OR _version.config_sha256 <>
       encode(extensions.digest(_version.config::text, 'sha256'), 'hex') THEN
    RAISE EXCEPTION 'shadow_version_validation_failed';
  END IF;
  IF _version.config #>> '{emergency,expected_live_definition_sha256}'
     <> encode(extensions.digest(pg_get_functiondef(
       'private.silence_threshold(uuid)'::regprocedure
     ), 'sha256'), 'hex') THEN
    RAISE EXCEPTION 'shadow_live_hash_mismatch';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS c
    WHERE c.oid IN (
      'private.adaptive_alert_shadow_user_state'::regclass,
      'private.adaptive_alert_shadow_cycle_runs'::regclass,
      'private.adaptive_alert_shadow_daily_reports'::regclass
    ) AND NOT c.relrowsecurity
  ) OR has_table_privilege(
    'authenticated', 'private.adaptive_alert_shadow_user_state', 'SELECT'
  ) THEN
    RAISE EXCEPTION 'shadow_acl_validation_failed';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_publication_tables AS p
    WHERE p.tablename LIKE 'adaptive_alert_shadow_%'
      AND p.schemaname IN ('private', 'public')
  ) THEN
    RAISE EXCEPTION 'shadow_publication_validation_failed';
  END IF;

  SELECT count(*)::integer INTO _population_total
  FROM (
    SELECT DISTINCT ds.user_id
    FROM public.device_state AS ds
    WHERE EXISTS (
      SELECT 1
      FROM public.group_members AS gm
      WHERE gm.user_id = ds.user_id
        AND gm.status = 'active'
        AND gm.monitored
    )
  ) AS population;
  IF _population_total > _runtime.max_population THEN
    RAISE EXCEPTION 'shadow_population_budget_exceeded';
  END IF;

  SELECT coalesce(sum(
    s.n_tup_ins + s.n_tup_upd + s.n_tup_del
  ), 0) INTO _before_dml
  FROM pg_catalog.pg_stat_xact_user_tables AS s
  WHERE s.relid IN (
    'public.alerts'::regclass,
    'public.alert_events'::regclass,
    'public.notifications'::regclass
  );

  IF _runtime.accept_coverage_leases THEN
    FOR _person_id IN
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
      SELECT p.user_id FROM population AS p
      ORDER BY p.user_id LIMIT _runtime.max_population
    LOOP
      PERFORM private.finalize_alert_shadow_coverage(
        _person_id, _minute, _runtime.detail_retention_days
      );
    END LOOP;
  END IF;

  PERFORM private.capture_alert_shadow_subject_contexts(
    _version_id, _minute, _runtime.max_population
  );
  PERFORM private.capture_alert_shadow_interventions(
    _version_id, _minute, _runtime.max_population
  );
  PERFORM private.maintain_adaptive_alert_shadow(
    _minute, _runtime.max_population
  );
  _result := private.record_alert_judgment_shadow_operational(
    _version_id, _minute, _runtime.max_population
  );

  SELECT coalesce(sum(
    s.n_tup_ins + s.n_tup_upd + s.n_tup_del
  ), 0) INTO _after_dml
  FROM pg_catalog.pg_stat_xact_user_tables AS s
  WHERE s.relid IN (
    'public.alerts'::regclass,
    'public.alert_events'::regclass,
    'public.notifications'::regclass
  );
  IF _after_dml <> _before_dml THEN
    RAISE EXCEPTION 'shadow_live_write_detected';
  END IF;

  _population_count := (_result ->> 'population_count')::integer;
  _evaluated_count := (_result ->> 'evaluated_count')::integer;
  _duration_ms := greatest(
    0, round(extract(epoch FROM (clock_timestamp() - _started_at)) * 1000)::integer
  );
  _metrics := jsonb_build_object(
    'replayable_count', (_result ->> 'replayable_count')::integer,
    'unreplayable_count', (_result ->> 'unreplayable_count')::integer,
    'persisted_count', (_result ->> 'persisted_count')::integer
  );
  _run_sha := encode(extensions.digest(jsonb_build_object(
    'version_id', _version_id,
    'evaluated_minute', _minute,
    'population_count', _population_count,
    'evaluated_count', _evaluated_count,
    'metrics', _metrics
  )::text, 'sha256'), 'hex');

  INSERT INTO private.adaptive_alert_shadow_cycle_runs (
    version_id, evaluated_minute, status, duration_ms, population_count,
    evaluated_count, metrics, run_sha256
  ) VALUES (
    _version_id, _minute,
    CASE WHEN _population_count = 0 THEN 'empty' ELSE 'completed' END,
    _duration_ms, _population_count, _evaluated_count, _metrics, _run_sha
  );

  RETURN jsonb_build_object(
    'status', 'completed',
    'population_count', _population_count,
    'evaluated_count', _evaluated_count,
    'duration_ms', _duration_ms
  );
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.capture_alert_shadow_subject_contexts(uuid,timestamptz,integer),
  private.record_alert_judgment_shadow_operational(uuid,timestamptz,integer),
  private.run_adaptive_alert_shadow_cycle(uuid,timestamptz)
FROM PUBLIC, anon, authenticated, service_role;
