-- ADR-0023 Task 8: fixture-only, unscheduled adaptive-alert shadow recorder.
-- This migration creates no producer, scheduler, notification, network, or live
-- alert path. The function is callable only by its owner for controlled replay.

ALTER TABLE public.alert_judgment_shadow_decisions
  DROP CONSTRAINT alert_judgment_shadow_decisions_check;

ALTER TABLE public.alert_judgment_shadow_decisions
  ADD COLUMN evidence_cutoff timestamptz NOT NULL,
  ADD COLUMN unclamped_candidate_threshold_minutes integer NOT NULL,
  ADD COLUMN candidate_floor_minutes integer NOT NULL,
  ADD COLUMN candidate_ceiling_minutes integer NOT NULL,
  ADD COLUMN candidate_cap_reason text NOT NULL,
  ADD COLUMN deadline_basis text NOT NULL,
  ADD COLUMN selected_source_sha256 text,
  ADD COLUMN subject_context_sha256 text NOT NULL,
  ADD COLUMN decision_provenance jsonb NOT NULL,
  ADD COLUMN decision_sha256 text NOT NULL,
  ADD CONSTRAINT alert_judgment_shadow_decisions_candidate_threshold_nonnegative
    CHECK (candidate_threshold_minutes >= 0),
  ADD CONSTRAINT alert_judgment_shadow_decisions_candidate_inputs_nonnegative
    CHECK (
      unclamped_candidate_threshold_minutes >= 0
      AND candidate_floor_minutes >= 0
      AND candidate_ceiling_minutes >= 0
      AND candidate_ceiling_minutes >= candidate_floor_minutes
    ),
  ADD CONSTRAINT alert_judgment_shadow_decisions_candidate_cap_contract
    CHECK (
      (
        candidate_cap_reason = 'none'
        AND basis <> 'deterministic_emergency'
        AND candidate_threshold_minutes = unclamped_candidate_threshold_minutes
        AND unclamped_candidate_threshold_minutes >= candidate_floor_minutes
        AND unclamped_candidate_threshold_minutes <= candidate_ceiling_minutes
      )
      OR (
        candidate_cap_reason = 'floor'
        AND basis <> 'deterministic_emergency'
        AND unclamped_candidate_threshold_minutes < candidate_floor_minutes
        AND candidate_threshold_minutes = candidate_floor_minutes
      )
      OR (
        candidate_cap_reason = 'ceiling'
        AND basis <> 'deterministic_emergency'
        AND unclamped_candidate_threshold_minutes > candidate_ceiling_minutes
        AND candidate_threshold_minutes = candidate_ceiling_minutes
      )
      OR (
        candidate_cap_reason = 'emergency_exempt'
        AND basis = 'deterministic_emergency'
        AND candidate_threshold_minutes = unclamped_candidate_threshold_minutes
      )
    ),
  ADD CONSTRAINT alert_judgment_shadow_decisions_deadline_basis_check
    CHECK (deadline_basis IN ('known_interval_inversion', 'no_future_exclusion')),
  ADD CONSTRAINT alert_judgment_shadow_decisions_selected_source_sha256_check
    CHECK (
      selected_source_sha256 IS NULL
      OR selected_source_sha256 ~ '^[a-f0-9]{64}$'
    ),
  ADD CONSTRAINT alert_judgment_shadow_decisions_subject_context_sha256_check
    CHECK (subject_context_sha256 ~ '^[a-f0-9]{64}$'),
  ADD CONSTRAINT alert_judgment_shadow_decisions_decision_provenance_check
    CHECK (
      jsonb_typeof(decision_provenance) = 'object'
      AND provenance_sha256 = encode(
        extensions.digest(decision_provenance::text, 'sha256'),
        'hex'
      )
    ),
  ADD CONSTRAINT alert_judgment_shadow_decisions_decision_sha256_check
    CHECK (decision_sha256 ~ '^[a-f0-9]{64}$');

CREATE FUNCTION private.record_alert_judgment_shadow(
  _version_id uuid,
  _evaluated_at timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET TimeZone = 'UTC'
SET "DateStyle" = 'ISO, YMD'
SET extra_float_digits = 3
AS $$
DECLARE
  _recorder_version constant text := 'adaptive_shadow_recorder_v1';
  _evaluator_version constant text := 'adaptive_candidate_v1';
  _supported_evidence_version constant text := 'canonical-v2';
  _required_keys constant text[] := ARRAY[
    'basis',
    'candidate_cap_reason',
    'candidate_ceiling_minutes',
    'candidate_deadline',
    'candidate_floor_minutes',
    'candidate_threshold_minutes',
    'confidence',
    'context_key',
    'deadline_basis',
    'decision_provenance',
    'effective_silence_minutes',
    'evaluated_at',
    'evaluator_version',
    'evidence_cutoff',
    'fallback_path',
    'guardian_used_as_activity',
    'neutral_threshold_minutes',
    'provenance_sha256',
    'quality_state',
    'replayable',
    'selected_source_sha256',
    'sensitivity_buffer_minutes',
    'sleep_interval_provenance',
    'subject_context_sha256',
    'unclamped_candidate_threshold_minutes',
    'unreplayable_reason',
    'version_id',
    'would_alert'
  ];
  _run_level_reasons constant text[] := ARRAY[
    'invalid_version_status',
    'config_hash_mismatch',
    'unsupported_evidence_version'
  ];
  _per_user_reasons constant text[] := ARRAY[
    'missing_subject_context',
    'ambiguous_subject_context',
    'subject_context_provenance_invalid',
    'missing_qualified_session'
  ];
  _version public.alert_model_versions%ROWTYPE;
  _population_user_id uuid;
  _evaluated_minute timestamptz;
  _evaluated_minute_utc text;
  _result jsonb;
  _result_key_count integer;
  _replayable boolean;
  _reason text;
  _decision_provenance jsonb;
  _provenance_sha text;
  _decision_sha text;
  _existing_decision_sha text;
  _fallback_path text[];
  _population_count integer := 0;
  _evaluated_count integer := 0;
  _replayable_count integer := 0;
  _inserted_count integer := 0;
  _duplicate_count integer := 0;
  _unreplayable_count integer := 0;
  _unreplayable_reason_counts jsonb := '{}'::jsonb;
  _result_status text;
BEGIN
  IF _version_id IS NULL THEN
    RAISE EXCEPTION 'shadow recorder requires a non-null version id';
  END IF;
  IF _evaluated_at IS NULL OR NOT isfinite(_evaluated_at) THEN
    RAISE EXCEPTION 'shadow recorder requires a finite evaluation timestamp';
  END IF;

  _evaluated_minute :=
    date_trunc('minute', _evaluated_at AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  _evaluated_minute_utc := to_char(
    _evaluated_minute AT TIME ZONE 'UTC',
    'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
  );

  SELECT version.*
    INTO _version
  FROM public.alert_model_versions AS version
  WHERE version.id = _version_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'shadow recorder version does not exist';
  END IF;
  IF _version.status <> 'shadow' THEN
    RAISE EXCEPTION 'shadow recorder requires status=shadow';
  END IF;
  IF _version.shadow_enabled_at IS NULL
     OR _evaluated_minute < _version.shadow_enabled_at THEN
    RAISE EXCEPTION 'shadow recorder evaluation precedes shadow enablement';
  END IF;
  IF _version.config_sha256
      <> encode(extensions.digest(_version.config::text, 'sha256'), 'hex') THEN
    RAISE EXCEPTION 'shadow recorder config hash mismatch';
  END IF;
  IF _version.evidence_version <> _supported_evidence_version THEN
    RAISE EXCEPTION 'shadow recorder evidence version is unsupported';
  END IF;
  IF _version.config #>> '{evaluator,contract_version}'
      <> _evaluator_version THEN
    RAISE EXCEPTION 'shadow recorder evaluator contract is unsupported';
  END IF;

  FOR _population_user_id IN
    SELECT DISTINCT ds.user_id
    FROM public.device_state AS ds
    WHERE EXISTS (
      SELECT 1
      FROM public.group_members AS gm
      WHERE gm.user_id = ds.user_id
        AND gm.status = 'active'
        AND gm.monitored
    )
    ORDER BY ds.user_id
  LOOP
    _population_count := _population_count + 1;
    _result := private.resolve_alert_candidate(
      _population_user_id,
      _evaluated_minute,
      _version_id
    );
    _evaluated_count := _evaluated_count + 1;

    IF _result IS NULL OR jsonb_typeof(_result) <> 'object' THEN
      RAISE EXCEPTION 'candidate evaluator returned a non-object result';
    END IF;
    SELECT count(*)::integer
      INTO _result_key_count
    FROM jsonb_object_keys(_result);
    IF NOT (_result ?& _required_keys)
       OR _result_key_count <> cardinality(_required_keys) THEN
      RAISE EXCEPTION 'candidate evaluator returned a malformed key contract';
    END IF;
    IF jsonb_typeof(_result -> 'replayable') <> 'boolean'
       OR _result ->> 'evaluator_version' <> _evaluator_version
       OR _result ->> 'version_id' <> _version_id::text
       OR _result ->> 'evaluated_at' <> _evaluated_minute_utc
       OR _result ->> 'evidence_cutoff' <> _evaluated_minute_utc
       OR jsonb_typeof(_result -> 'decision_provenance') <> 'object'
       OR jsonb_typeof(_result -> 'provenance_sha256') <> 'string'
       OR jsonb_typeof(_result -> 'guardian_used_as_activity') <> 'boolean'
       OR (_result ->> 'guardian_used_as_activity')::boolean THEN
      RAISE EXCEPTION 'candidate evaluator returned malformed identity fields';
    END IF;
    _decision_provenance := _result -> 'decision_provenance';
    _provenance_sha := encode(
      extensions.digest(_decision_provenance::text, 'sha256'),
      'hex'
    );
    IF _result ->> 'provenance_sha256' <> _provenance_sha THEN
      RAISE EXCEPTION 'candidate evaluator provenance hash mismatch';
    END IF;

    _replayable := (_result ->> 'replayable')::boolean;
    _reason := _result ->> 'unreplayable_reason';

    IF _reason = ANY (_run_level_reasons) THEN
      RAISE EXCEPTION 'candidate evaluator returned run-level reason: %', _reason;
    END IF;

    IF NOT _replayable THEN
      IF _reason IS NULL OR NOT (_reason = ANY (_per_user_reasons)) THEN
        RAISE EXCEPTION 'candidate evaluator returned an invalid per-user reason';
      END IF;
      IF _result ->> 'basis' IS NOT NULL
         OR _result ->> 'context_key' IS NOT NULL
         OR _result ->> 'neutral_threshold_minutes' IS NOT NULL
         OR _result ->> 'sensitivity_buffer_minutes' IS NOT NULL
         OR _result ->> 'unclamped_candidate_threshold_minutes' IS NOT NULL
         OR _result ->> 'candidate_floor_minutes' IS NOT NULL
         OR _result ->> 'candidate_ceiling_minutes' IS NOT NULL
         OR _result ->> 'candidate_cap_reason' IS NOT NULL
         OR _result ->> 'candidate_threshold_minutes' IS NOT NULL
         OR _result ->> 'effective_silence_minutes' IS NOT NULL
         OR _result ->> 'candidate_deadline' IS NOT NULL
         OR _result ->> 'deadline_basis' IS NOT NULL
         OR _result ->> 'would_alert' IS NOT NULL
         OR _result ->> 'confidence' IS NOT NULL
         OR _result ->> 'selected_source_sha256' IS NOT NULL
         OR _result ->> 'subject_context_sha256' IS NOT NULL
         OR _result ->> 'quality_state' <> 'coverage_invalid'
         OR _result -> 'fallback_path' <> '[]'::jsonb
         OR _result -> 'sleep_interval_provenance' <> '[]'::jsonb THEN
        RAISE EXCEPTION 'candidate evaluator returned malformed unreplayable fields';
      END IF;
      _unreplayable_count := _unreplayable_count + 1;
      _unreplayable_reason_counts := jsonb_set(
        _unreplayable_reason_counts,
        ARRAY[_reason],
        to_jsonb(coalesce(
          (_unreplayable_reason_counts ->> _reason)::integer,
          0
        ) + 1),
        true
      );
      CONTINUE;
    END IF;

    IF _reason IS NOT NULL
       OR jsonb_typeof(_result -> 'basis') <> 'string'
       OR jsonb_typeof(_result -> 'context_key') <> 'string'
       OR jsonb_typeof(_result -> 'neutral_threshold_minutes') <> 'number'
       OR jsonb_typeof(_result -> 'sensitivity_buffer_minutes') <> 'number'
       OR jsonb_typeof(_result -> 'unclamped_candidate_threshold_minutes') <> 'number'
       OR jsonb_typeof(_result -> 'candidate_floor_minutes') <> 'number'
       OR jsonb_typeof(_result -> 'candidate_ceiling_minutes') <> 'number'
       OR jsonb_typeof(_result -> 'candidate_cap_reason') <> 'string'
       OR jsonb_typeof(_result -> 'candidate_threshold_minutes') <> 'number'
       OR jsonb_typeof(_result -> 'effective_silence_minutes') <> 'number'
       OR jsonb_typeof(_result -> 'candidate_deadline') <> 'string'
       OR jsonb_typeof(_result -> 'deadline_basis') <> 'string'
       OR jsonb_typeof(_result -> 'would_alert') <> 'boolean'
       OR jsonb_typeof(_result -> 'confidence') <> 'number'
       OR jsonb_typeof(_result -> 'quality_state') <> 'string'
       OR jsonb_typeof(_result -> 'fallback_path') <> 'array'
       OR jsonb_array_length(_result -> 'fallback_path') < 1
       OR jsonb_typeof(_result -> 'sleep_interval_provenance') <> 'array'
       OR (
         _result -> 'selected_source_sha256' <> 'null'::jsonb
         AND jsonb_typeof(_result -> 'selected_source_sha256') <> 'string'
       )
       OR jsonb_typeof(_result -> 'subject_context_sha256') <> 'string'
       OR jsonb_typeof(_result -> 'decision_provenance') <> 'object'
       OR jsonb_typeof(_result -> 'provenance_sha256') <> 'string' THEN
      RAISE EXCEPTION 'candidate evaluator returned malformed replayable fields';
    END IF;

    _decision_sha := encode(
      extensions.digest(jsonb_build_object(
        'version_id', _version_id,
        'user_id', _population_user_id,
        'evaluated_minute', _evaluated_minute_utc,
        'evaluator_result', _result
      )::text, 'sha256'),
      'hex'
    );
    SELECT array_agg(value ORDER BY ordinal)
      INTO _fallback_path
    FROM jsonb_array_elements_text(_result -> 'fallback_path')
      WITH ORDINALITY AS path(value, ordinal);

    INSERT INTO public.alert_judgment_shadow_decisions (
      version_id,
      user_id,
      evaluated_at,
      basis,
      evaluator_version,
      context_key,
      neutral_threshold_minutes,
      sensitivity_buffer_minutes,
      candidate_threshold_minutes,
      effective_silence_minutes,
      candidate_deadline,
      would_alert,
      confidence,
      quality_state,
      fallback_path,
      sleep_interval_provenance,
      provenance_sha256,
      guardian_used_as_activity,
      evidence_cutoff,
      unclamped_candidate_threshold_minutes,
      candidate_floor_minutes,
      candidate_ceiling_minutes,
      candidate_cap_reason,
      deadline_basis,
      selected_source_sha256,
      subject_context_sha256,
      decision_provenance,
      decision_sha256
    ) VALUES (
      _version_id,
      _population_user_id,
      _evaluated_minute,
      _result ->> 'basis',
      _evaluator_version,
      _result ->> 'context_key',
      (_result ->> 'neutral_threshold_minutes')::integer,
      (_result ->> 'sensitivity_buffer_minutes')::integer,
      (_result ->> 'candidate_threshold_minutes')::integer,
      (_result ->> 'effective_silence_minutes')::double precision,
      (_result ->> 'candidate_deadline')::timestamptz,
      (_result ->> 'would_alert')::boolean,
      (_result ->> 'confidence')::double precision,
      _result ->> 'quality_state',
      _fallback_path,
      _result -> 'sleep_interval_provenance',
      _provenance_sha,
      false,
      (_result ->> 'evidence_cutoff')::timestamptz,
      (_result ->> 'unclamped_candidate_threshold_minutes')::integer,
      (_result ->> 'candidate_floor_minutes')::integer,
      (_result ->> 'candidate_ceiling_minutes')::integer,
      _result ->> 'candidate_cap_reason',
      _result ->> 'deadline_basis',
      _result ->> 'selected_source_sha256',
      _result ->> 'subject_context_sha256',
      _decision_provenance,
      _decision_sha
    )
    ON CONFLICT (version_id, user_id, evaluated_minute) DO NOTHING;

    IF FOUND THEN
      _inserted_count := _inserted_count + 1;
    ELSE
      SELECT decision.decision_sha256
        INTO _existing_decision_sha
      FROM public.alert_judgment_shadow_decisions AS decision
      WHERE decision.version_id = _version_id
        AND decision.user_id = _population_user_id
        AND decision.evaluated_minute = _evaluated_minute;
      IF _existing_decision_sha IS DISTINCT FROM _decision_sha THEN
        RAISE EXCEPTION 'same-minute shadow decision mismatch';
      END IF;
      _duplicate_count := _duplicate_count + 1;
    END IF;
    _replayable_count := _replayable_count + 1;
  END LOOP;

  _result_status := CASE
    WHEN _population_count = 0 THEN 'empty'
    WHEN _replayable_count = 0 THEN 'all_unreplayable'
    WHEN _unreplayable_count > 0 THEN 'partial'
    ELSE 'complete'
  END;

  RETURN jsonb_build_object(
    'recorder_contract_version', _recorder_version,
    'evaluator_version', _evaluator_version,
    'execution_scope', 'fixture_only_unscheduled',
    'operational_shadow', false,
    'result_status', _result_status,
    'population_count', _population_count,
    'evaluated_count', _evaluated_count,
    'replayable_count', _replayable_count,
    'inserted_count', _inserted_count,
    'duplicate_count', _duplicate_count,
    'unreplayable_count', _unreplayable_count,
    'unreplayable_reason_counts', _unreplayable_reason_counts,
    'skipped_count', _duplicate_count + _unreplayable_count,
    'error_count', 0
  );
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.record_alert_judgment_shadow(uuid, timestamptz)
FROM PUBLIC, anon, authenticated, service_role;

ALTER TABLE public.alert_judgment_shadow_decisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.alert_judgment_shadow_decisions
FROM PUBLIC, anon, authenticated, service_role;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policy AS policy
    WHERE policy.polrelid =
      'public.alert_judgment_shadow_decisions'::regclass
  ) THEN
    RAISE EXCEPTION 'shadow decision table unexpectedly has an RLS policy';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger
    WHERE trigger.tgrelid =
      'public.alert_judgment_shadow_decisions'::regclass
      AND NOT trigger.tgisinternal
  ) THEN
    RAISE EXCEPTION 'shadow decision table unexpectedly has a producer trigger';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_publication_tables AS publication
    WHERE publication.pubname = 'supabase_realtime'
      AND publication.schemaname = 'public'
      AND publication.tablename = 'alert_judgment_shadow_decisions'
  ) THEN
    RAISE EXCEPTION 'shadow decision table unexpectedly has realtime publication';
  END IF;
  IF (
    SELECT recorder.proowner <> evaluator.proowner
        OR recorder.proowner <> target.relowner
    FROM pg_catalog.pg_proc AS recorder
    CROSS JOIN pg_catalog.pg_proc AS evaluator
    CROSS JOIN pg_catalog.pg_class AS target
    WHERE recorder.oid =
      'private.record_alert_judgment_shadow(uuid,timestamptz)'::regprocedure
      AND evaluator.oid =
      'private.resolve_alert_candidate(uuid,timestamptz,uuid)'::regprocedure
      AND target.oid =
      'public.alert_judgment_shadow_decisions'::regclass
  ) THEN
    RAISE EXCEPTION 'shadow recorder owner does not match evaluator and target';
  END IF;
END;
$$;
