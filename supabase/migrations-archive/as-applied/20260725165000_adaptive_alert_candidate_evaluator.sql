-- ADR-0023 Task 6: deterministic replay/shadow candidate resolution only.
-- This migration creates no context producer, scheduler, live-alert write, or
-- notification path. The existing ADR-0022 live threshold remains authoritative.

ALTER TABLE public.alert_model_versions
  ADD CONSTRAINT alert_model_versions_candidate_evaluator_contract_check CHECK (
    (
      jsonb_typeof(config #> '{personal,min_confidence}') = 'number'
      AND (config #>> '{personal,min_confidence}')::numeric > 0
      AND (config #>> '{personal,min_confidence}')::numeric <= 1
      AND jsonb_typeof(config -> 'evaluator') = 'object'
      AND config #>> '{evaluator,contract_version}' = 'adaptive_candidate_v1'
      AND jsonb_typeof(config -> 'emergency') = 'object'
      AND config #>> '{emergency,contract_version}' = 'adr0022_v1'
      AND jsonb_typeof(config #> '{emergency,neutral_minutes}') = 'number'
      AND (config #>> '{emergency,neutral_minutes}')::numeric = 90
      AND (config #>> '{emergency,neutral_minutes}')::numeric
        = trunc((config #>> '{emergency,neutral_minutes}')::numeric)
      AND config #>> '{emergency,expected_live_definition_sha256}'
        = '1907d59473d274d46a0e8e0b9ce8027037b4494b0dddf073cb46abf67db92e21'
      AND (config #>> '{emergency,expected_live_definition_sha256}') ~ '^[a-f0-9]{64}$'
      AND (config #>> '{sensitivity_buffers_minutes,high}')::numeric
        = trunc((config #>> '{sensitivity_buffers_minutes,high}')::numeric)
      AND (config #>> '{sensitivity_buffers_minutes,balanced}')::numeric
        = trunc((config #>> '{sensitivity_buffers_minutes,balanced}')::numeric)
      AND (config #>> '{sensitivity_buffers_minutes,low}')::numeric
        = trunc((config #>> '{sensitivity_buffers_minutes,low}')::numeric)
      AND (config #>> '{candidate_bounds,floor_minutes}')::numeric
        = trunc((config #>> '{candidate_bounds,floor_minutes}')::numeric)
      AND (config #>> '{candidate_bounds,ceiling_minutes}')::numeric
        = trunc((config #>> '{candidate_bounds,ceiling_minutes}')::numeric)
    ) IS TRUE
  ) NOT VALID;

CREATE TABLE public.alert_judgment_subject_contexts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id uuid NOT NULL
    REFERENCES public.alert_model_versions(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  effective_from timestamptz NOT NULL,
  effective_to timestamptz,
  raw_sensitivity text,
  canonical_sensitivity text NOT NULL
    CHECK (canonical_sensitivity IN ('high', 'balanced', 'low')),
  routine_mode text NOT NULL
    CHECK (routine_mode IN ('regular_9to5', 'semester_break', 'shift_irregular')),
  timezone text NOT NULL CHECK (length(trim(timezone)) > 0),
  utc_offset_minutes integer NOT NULL CHECK (utc_offset_minutes BETWEEN -840 AND 840),
  settings_updated_at timestamptz NOT NULL,
  settings_provenance jsonb NOT NULL
    CHECK (jsonb_typeof(settings_provenance) = 'object'),
  captured_at timestamptz NOT NULL,
  config_sha256 text NOT NULL CHECK (config_sha256 ~ '^[a-f0-9]{64}$'),
  evidence_version text NOT NULL CHECK (length(trim(evidence_version)) > 0),
  subject_context_sha256 text NOT NULL
    CHECK (subject_context_sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK (effective_to IS NULL OR effective_to > effective_from),
  CHECK (settings_updated_at <= captured_at)
);

CREATE INDEX alert_judgment_subject_contexts_as_of_idx
  ON public.alert_judgment_subject_contexts
    (version_id, user_id, effective_from, effective_to, captured_at);

ALTER TABLE public.alert_judgment_subject_contexts ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.alert_judgment_subject_contexts
FROM PUBLIC, anon, authenticated, service_role;

ALTER TABLE public.alert_gap_profiles
  ADD COLUMN config_sha256 text CHECK (config_sha256 ~ '^[a-f0-9]{64}$'),
  ADD COLUMN evidence_version text CHECK (
    evidence_version IS NULL OR length(trim(evidence_version)) > 0
  );

-- Centralized, raw-type-first config gate. A canonical config_sha256 only
-- proves the stored config matches its own hash; it says nothing about
-- whether a pre-Task-6 legacy row's scalars are the right JSON type, enum,
-- range, or integrality. Every key consumed anywhere in the Task 3-5
-- sleep/session/profile/cohort helpers or the Task 6 evaluator is checked
-- here, by JSON type, before any numeric/text extraction, so a JSON string
-- that happens to parse as a number (or an out-of-range/non-integral number)
-- can never be silently cast and accepted.
CREATE FUNCTION private.alert_candidate_config_is_valid(_config jsonb)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
SET TimeZone = 'UTC'
SET "DateStyle" = 'ISO, YMD'
SET extra_float_digits = 3
AS $$
  SELECT
    jsonb_typeof(_config) = 'object'
    AND _config ?& ARRAY[
      'sessionization', 'context', 'personal', 'cohort',
      'sensitivity_buffers_minutes', 'candidate_bounds', 'sleep_compensation',
      'evaluator', 'emergency'
    ]
    AND jsonb_typeof(_config -> 'sessionization') = 'object'
    AND (_config -> 'sessionization') ?& ARRAY[
      'gap_minutes', 'per_user_day_gap_cap',
      'training_horizon_days', 'intervention_window_minutes'
    ]
    AND jsonb_typeof(_config #> '{sessionization,gap_minutes}') = 'number'
    AND (_config #>> '{sessionization,gap_minutes}')::numeric > 0
    AND jsonb_typeof(_config #> '{sessionization,per_user_day_gap_cap}') = 'number'
    AND (_config #>> '{sessionization,per_user_day_gap_cap}')::numeric > 0
    AND jsonb_typeof(_config #> '{sessionization,training_horizon_days}') = 'number'
    AND (_config #>> '{sessionization,training_horizon_days}')::numeric > 0
    AND (_config #>> '{sessionization,training_horizon_days}')::numeric
      = trunc((_config #>> '{sessionization,training_horizon_days}')::numeric)
    AND jsonb_typeof(_config #> '{sessionization,intervention_window_minutes}') = 'number'
    AND (_config #>> '{sessionization,intervention_window_minutes}')::numeric >= 0
    AND (_config #>> '{sessionization,intervention_window_minutes}')::numeric
      = trunc((_config #>> '{sessionization,intervention_window_minutes}')::numeric)
    AND jsonb_typeof(_config -> 'context') = 'object'
    AND (_config -> 'context') ?& ARRAY[
      'definition_version', 'day_partition', 'hour_bucket_minutes'
    ]
    AND jsonb_typeof(_config #> '{context,definition_version}') = 'string'
    AND length(trim(_config #>> '{context,definition_version}')) > 0
    AND jsonb_typeof(_config #> '{context,day_partition}') = 'string'
    AND _config #>> '{context,day_partition}' IN ('all_days', 'weekday_weekend')
    AND jsonb_typeof(_config #> '{context,hour_bucket_minutes}') = 'number'
    AND (_config #>> '{context,hour_bucket_minutes}')::numeric > 0
    AND (_config #>> '{context,hour_bucket_minutes}')::numeric
      = trunc((_config #>> '{context,hour_bucket_minutes}')::numeric)
    AND mod(1440, (_config #>> '{context,hour_bucket_minutes}')::integer) = 0
    AND jsonb_typeof(_config -> 'personal') = 'object'
    AND (_config -> 'personal') ?& ARRAY[
      'min_samples', 'min_support_dates', 'min_span_days', 'max_age_days',
      'min_confidence', 'confidence_formula_version'
    ]
    AND jsonb_typeof(_config #> '{personal,min_samples}') = 'number'
    AND (_config #>> '{personal,min_samples}')::numeric > 0
    AND (_config #>> '{personal,min_samples}')::numeric
      = trunc((_config #>> '{personal,min_samples}')::numeric)
    AND jsonb_typeof(_config #> '{personal,min_support_dates}') = 'number'
    AND (_config #>> '{personal,min_support_dates}')::numeric > 0
    AND (_config #>> '{personal,min_support_dates}')::numeric
      = trunc((_config #>> '{personal,min_support_dates}')::numeric)
    AND jsonb_typeof(_config #> '{personal,min_span_days}') = 'number'
    AND (_config #>> '{personal,min_span_days}')::numeric > 0
    AND (_config #>> '{personal,min_span_days}')::numeric
      = trunc((_config #>> '{personal,min_span_days}')::numeric)
    AND jsonb_typeof(_config #> '{personal,max_age_days}') = 'number'
    AND (_config #>> '{personal,max_age_days}')::numeric > 0
    AND (_config #>> '{personal,max_age_days}')::numeric
      = trunc((_config #>> '{personal,max_age_days}')::numeric)
    AND jsonb_typeof(_config #> '{personal,min_confidence}') = 'number'
    AND (_config #>> '{personal,min_confidence}')::numeric > 0
    AND (_config #>> '{personal,min_confidence}')::numeric <= 1
    AND jsonb_typeof(_config #> '{personal,confidence_formula_version}') = 'string'
    AND _config #>> '{personal,confidence_formula_version}' = 'support_ratio_v1'
    AND jsonb_typeof(_config -> 'cohort') = 'object'
    AND (_config -> 'cohort') ?& ARRAY[
      'min_contributors', 'min_support_dates', 'min_span_days', 'max_age_days',
      'min_confidence', 'contribution_floor_minutes', 'contribution_ceiling_minutes',
      'confidence_formula_version', 'algorithm', 'trim_fraction'
    ]
    AND jsonb_typeof(_config #> '{cohort,min_contributors}') = 'number'
    AND (_config #>> '{cohort,min_contributors}')::numeric > 0
    AND (_config #>> '{cohort,min_contributors}')::numeric
      = trunc((_config #>> '{cohort,min_contributors}')::numeric)
    AND jsonb_typeof(_config #> '{cohort,min_support_dates}') = 'number'
    AND (_config #>> '{cohort,min_support_dates}')::numeric > 0
    AND (_config #>> '{cohort,min_support_dates}')::numeric
      = trunc((_config #>> '{cohort,min_support_dates}')::numeric)
    AND jsonb_typeof(_config #> '{cohort,min_span_days}') = 'number'
    AND (_config #>> '{cohort,min_span_days}')::numeric > 0
    AND (_config #>> '{cohort,min_span_days}')::numeric
      = trunc((_config #>> '{cohort,min_span_days}')::numeric)
    AND jsonb_typeof(_config #> '{cohort,max_age_days}') = 'number'
    AND (_config #>> '{cohort,max_age_days}')::numeric > 0
    AND (_config #>> '{cohort,max_age_days}')::numeric
      = trunc((_config #>> '{cohort,max_age_days}')::numeric)
    AND jsonb_typeof(_config #> '{cohort,min_confidence}') = 'number'
    AND (_config #>> '{cohort,min_confidence}')::numeric > 0
    AND (_config #>> '{cohort,min_confidence}')::numeric <= 1
    AND jsonb_typeof(_config #> '{cohort,contribution_floor_minutes}') = 'number'
    AND (_config #>> '{cohort,contribution_floor_minutes}')::numeric > 0
    AND (_config #>> '{cohort,contribution_floor_minutes}')::numeric
      = trunc((_config #>> '{cohort,contribution_floor_minutes}')::numeric)
    AND jsonb_typeof(_config #> '{cohort,contribution_ceiling_minutes}') = 'number'
    AND (_config #>> '{cohort,contribution_ceiling_minutes}')::numeric > 0
    AND (_config #>> '{cohort,contribution_ceiling_minutes}')::numeric
      = trunc((_config #>> '{cohort,contribution_ceiling_minutes}')::numeric)
    AND (_config #>> '{cohort,contribution_ceiling_minutes}')::numeric
      >= (_config #>> '{cohort,contribution_floor_minutes}')::numeric
    AND jsonb_typeof(_config #> '{cohort,confidence_formula_version}') = 'string'
    AND _config #>> '{cohort,confidence_formula_version}' = 'cohort_support_min_v1'
    AND jsonb_typeof(_config #> '{cohort,algorithm}') = 'string'
    AND _config #>> '{cohort,algorithm}' IN ('weighted_median', 'trimmed_mean')
    AND jsonb_typeof(_config #> '{cohort,trim_fraction}') = 'number'
    AND (_config #>> '{cohort,trim_fraction}')::numeric >= 0
    AND (_config #>> '{cohort,trim_fraction}')::numeric < 0.5
    AND jsonb_typeof(_config -> 'sensitivity_buffers_minutes') = 'object'
    AND (_config -> 'sensitivity_buffers_minutes') ?& ARRAY['high', 'balanced', 'low']
    AND jsonb_typeof(_config #> '{sensitivity_buffers_minutes,high}') = 'number'
    AND jsonb_typeof(_config #> '{sensitivity_buffers_minutes,balanced}') = 'number'
    AND jsonb_typeof(_config #> '{sensitivity_buffers_minutes,low}') = 'number'
    AND (_config #>> '{sensitivity_buffers_minutes,high}')::numeric = 0
    AND (_config #>> '{sensitivity_buffers_minutes,balanced}')::numeric = 45
    AND (_config #>> '{sensitivity_buffers_minutes,low}')::numeric = 90
    AND jsonb_typeof(_config -> 'candidate_bounds') = 'object'
    AND (_config -> 'candidate_bounds') ?& ARRAY['floor_minutes', 'ceiling_minutes']
    AND jsonb_typeof(_config #> '{candidate_bounds,floor_minutes}') = 'number'
    AND (_config #>> '{candidate_bounds,floor_minutes}')::numeric >= 0
    AND (_config #>> '{candidate_bounds,floor_minutes}')::numeric
      = trunc((_config #>> '{candidate_bounds,floor_minutes}')::numeric)
    AND jsonb_typeof(_config #> '{candidate_bounds,ceiling_minutes}') = 'number'
    AND (_config #>> '{candidate_bounds,ceiling_minutes}')::numeric
      >= (_config #>> '{candidate_bounds,floor_minutes}')::numeric
    AND (_config #>> '{candidate_bounds,ceiling_minutes}')::numeric
      = trunc((_config #>> '{candidate_bounds,ceiling_minutes}')::numeric)
    AND jsonb_typeof(_config -> 'sleep_compensation') = 'object'
    AND (_config -> 'sleep_compensation') ?& ARRAY[
      'max_start_delay_minutes', 'max_wake_advance_minutes', 'max_wake_delay_minutes',
      'max_update_minutes_per_day', 'min_positive_nights', 'lookback_nights',
      'min_late_events_per_night', 'timezone_tolerance_minutes'
    ]
    AND jsonb_typeof(_config #> '{sleep_compensation,max_start_delay_minutes}') = 'number'
    AND (_config #>> '{sleep_compensation,max_start_delay_minutes}')::numeric >= 0
    AND (_config #>> '{sleep_compensation,max_start_delay_minutes}')::numeric
      = trunc((_config #>> '{sleep_compensation,max_start_delay_minutes}')::numeric)
    AND jsonb_typeof(_config #> '{sleep_compensation,max_wake_advance_minutes}') = 'number'
    AND (_config #>> '{sleep_compensation,max_wake_advance_minutes}')::numeric >= 0
    AND (_config #>> '{sleep_compensation,max_wake_advance_minutes}')::numeric
      = trunc((_config #>> '{sleep_compensation,max_wake_advance_minutes}')::numeric)
    AND jsonb_typeof(_config #> '{sleep_compensation,max_wake_delay_minutes}') = 'number'
    AND (_config #>> '{sleep_compensation,max_wake_delay_minutes}')::numeric >= 0
    AND (_config #>> '{sleep_compensation,max_wake_delay_minutes}')::numeric
      = trunc((_config #>> '{sleep_compensation,max_wake_delay_minutes}')::numeric)
    AND jsonb_typeof(_config #> '{sleep_compensation,max_update_minutes_per_day}') = 'number'
    AND (_config #>> '{sleep_compensation,max_update_minutes_per_day}')::numeric >= 0
    AND (_config #>> '{sleep_compensation,max_update_minutes_per_day}')::numeric
      = trunc((_config #>> '{sleep_compensation,max_update_minutes_per_day}')::numeric)
    AND jsonb_typeof(_config #> '{sleep_compensation,min_positive_nights}') = 'number'
    AND (_config #>> '{sleep_compensation,min_positive_nights}')::numeric > 0
    AND (_config #>> '{sleep_compensation,min_positive_nights}')::numeric
      = trunc((_config #>> '{sleep_compensation,min_positive_nights}')::numeric)
    AND jsonb_typeof(_config #> '{sleep_compensation,lookback_nights}') = 'number'
    AND (_config #>> '{sleep_compensation,lookback_nights}')::numeric > 0
    AND (_config #>> '{sleep_compensation,lookback_nights}')::numeric
      = trunc((_config #>> '{sleep_compensation,lookback_nights}')::numeric)
    AND (_config #>> '{sleep_compensation,min_positive_nights}')::numeric
      <= (_config #>> '{sleep_compensation,lookback_nights}')::numeric
    AND jsonb_typeof(_config #> '{sleep_compensation,min_late_events_per_night}') = 'number'
    AND (_config #>> '{sleep_compensation,min_late_events_per_night}')::numeric > 0
    AND (_config #>> '{sleep_compensation,min_late_events_per_night}')::numeric
      = trunc((_config #>> '{sleep_compensation,min_late_events_per_night}')::numeric)
    AND jsonb_typeof(_config #> '{sleep_compensation,timezone_tolerance_minutes}') = 'number'
    AND (_config #>> '{sleep_compensation,timezone_tolerance_minutes}')::numeric >= 0
    AND (_config #>> '{sleep_compensation,timezone_tolerance_minutes}')::numeric
      = trunc((_config #>> '{sleep_compensation,timezone_tolerance_minutes}')::numeric)
    AND jsonb_typeof(_config -> 'evaluator') = 'object'
    AND (_config -> 'evaluator') ?& ARRAY['contract_version']
    AND jsonb_typeof(_config #> '{evaluator,contract_version}') = 'string'
    AND _config #>> '{evaluator,contract_version}' = 'adaptive_candidate_v1'
    AND jsonb_typeof(_config -> 'emergency') = 'object'
    AND (_config -> 'emergency') ?& ARRAY[
      'contract_version', 'neutral_minutes', 'expected_live_definition_sha256'
    ]
    AND jsonb_typeof(_config #> '{emergency,contract_version}') = 'string'
    AND _config #>> '{emergency,contract_version}' = 'adr0022_v1'
    AND jsonb_typeof(_config #> '{emergency,neutral_minutes}') = 'number'
    AND (_config #>> '{emergency,neutral_minutes}')::numeric = 90
    AND (_config #>> '{emergency,neutral_minutes}')::numeric
      = trunc((_config #>> '{emergency,neutral_minutes}')::numeric)
    AND jsonb_typeof(_config #> '{emergency,expected_live_definition_sha256}') = 'string'
    AND (_config #>> '{emergency,expected_live_definition_sha256}') ~ '^[a-f0-9]{64}$'
    AND _config #>> '{emergency,expected_live_definition_sha256}'
      = '1907d59473d274d46a0e8e0b9ce8027037b4494b0dddf073cb46abf67db92e21'
$$;

REVOKE ALL PRIVILEGES ON FUNCTION private.alert_candidate_config_is_valid(jsonb)
FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.pin_alert_gap_profile_contract()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  SELECT version.config_sha256, version.evidence_version
    INTO NEW.config_sha256, NEW.evidence_version
  FROM public.alert_model_versions AS version
  WHERE version.id = NEW.version_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'unknown alert model version %', NEW.version_id
      USING ERRCODE = '23503';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER on_alert_gap_profile_contract_pin
BEFORE INSERT OR UPDATE ON public.alert_gap_profiles
FOR EACH ROW
EXECUTE FUNCTION private.pin_alert_gap_profile_contract();

REVOKE ALL PRIVILEGES ON FUNCTION private.pin_alert_gap_profile_contract()
FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.resolve_alert_candidate(
  _user_id uuid,
  _evaluated_at timestamptz,
  _version_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
SET TimeZone = 'UTC'
SET "DateStyle" = 'ISO, YMD'
SET extra_float_digits = 3
AS $$
DECLARE
  _evaluator_version constant text := 'adaptive_candidate_v1';
  _version public.alert_model_versions%ROWTYPE;
  _subject public.alert_judgment_subject_contexts%ROWTYPE;
  _profile public.alert_gap_profiles%ROWTYPE;
  _prior public.routine_mode_cohort_priors%ROWTYPE;
  _latest_session record;
  _subject_count integer;
  _subject_id uuid;
  _subject_expected_sha text;
  _subject_expected_sensitivity text;
  _offset_minutes integer;
  _session_from timestamptz;
  _session_found boolean := false;
  _personal_min_samples integer;
  _personal_min_dates integer;
  _personal_min_span integer;
  _personal_max_age integer;
  _personal_min_confidence double precision;
  _cohort_max_age integer;
  _candidate_floor integer;
  _candidate_ceiling integer;
  _sensitivity_buffer integer;
  _emergency_neutral integer;
  _emergency_definition_sha text;
  _basis text;
  _neutral integer;
  _unclamped integer;
  _threshold integer;
  _cap_reason text;
  _confidence double precision;
  _quality_state text;
  _selected_source_sha text;
  _selected_source_support jsonb;
  _fallback_path text[] := ARRAY[]::text[];
  _sleep_ranges tstzrange[] := ARRAY[]::tstzrange[];
  _sleep_range tstzrange;
  _sleep_provenance jsonb := '[]'::jsonb;
  _sleep_seconds double precision := 0;
  _wall_seconds double precision;
  _effective_minutes double precision;
  _remaining_seconds double precision;
  _awake_seconds double precision;
  _cursor timestamptz;
  _deadline timestamptz;
  _deadline_basis text;
  _would_alert boolean;
  _decision_provenance jsonb;
  _provenance_sha text;
  _unreplayable_reason text;
  _evaluated_at_utc text :=
    to_char(_evaluated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
BEGIN
  SELECT version.*
    INTO _version
  FROM public.alert_model_versions AS version
  WHERE version.id = _version_id;

  IF NOT FOUND OR _version.status NOT IN ('replay', 'shadow') THEN
    _unreplayable_reason := 'invalid_version_status';
  ELSIF _version.config_sha256
      <> encode(extensions.digest(_version.config::text, 'sha256'), 'hex') THEN
    _unreplayable_reason := 'config_hash_mismatch';
  ELSIF _version.evidence_version <> 'canonical-v2' THEN
    _unreplayable_reason := 'unsupported_evidence_version';
  END IF;

  -- Every helper-used config key (sessionization, context, personal, cohort,
  -- sensitivity buffers, candidate bounds, sleep compensation, evaluator,
  -- emergency) must have its required raw JSON type, enum/value, range, and
  -- integrality before any subject/session/profile/cohort evidence is read.
  -- A canonical config hash proves self-consistency, not validity: a
  -- pre-Task-6 legacy row can carry a self-consistent hash over malformed
  -- content (a JSON string where a number is required, an out-of-range or
  -- non-integral number, or a missing key), so this check cannot rely on
  -- casting first and catching failures after the fact.
  IF _unreplayable_reason IS NULL THEN
    IF NOT private.alert_candidate_config_is_valid(_version.config) THEN
      _unreplayable_reason := 'config_hash_mismatch';
    ELSE
      _personal_min_samples :=
        (_version.config #>> '{personal,min_samples}')::integer;
      _personal_min_dates :=
        (_version.config #>> '{personal,min_support_dates}')::integer;
      _personal_min_span :=
        (_version.config #>> '{personal,min_span_days}')::integer;
      _personal_max_age :=
        (_version.config #>> '{personal,max_age_days}')::integer;
      _personal_min_confidence :=
        (_version.config #>> '{personal,min_confidence}')::double precision;
      _cohort_max_age :=
        (_version.config #>> '{cohort,max_age_days}')::integer;
      _candidate_floor :=
        (_version.config #>> '{candidate_bounds,floor_minutes}')::integer;
      _candidate_ceiling :=
        (_version.config #>> '{candidate_bounds,ceiling_minutes}')::integer;
      _emergency_neutral :=
        (_version.config #>> '{emergency,neutral_minutes}')::integer;
      _emergency_definition_sha :=
        _version.config #>> '{emergency,expected_live_definition_sha256}';
    END IF;
  END IF;

  IF _unreplayable_reason IS NULL THEN
    SELECT
      count(*)::integer,
      (array_agg(context.id ORDER BY context.captured_at, context.id))[1]
      INTO _subject_count, _subject_id
    FROM public.alert_judgment_subject_contexts AS context
    WHERE context.version_id = _version_id
      AND context.user_id = _user_id
      AND context.effective_from <= _evaluated_at
      AND (context.effective_to IS NULL OR _evaluated_at < context.effective_to)
      AND context.captured_at <= _evaluated_at;

    IF _subject_count = 0 THEN
      _unreplayable_reason := 'missing_subject_context';
    ELSIF _subject_count <> 1 THEN
      _unreplayable_reason := 'ambiguous_subject_context';
    ELSE
      SELECT context.*
        INTO _subject
      FROM public.alert_judgment_subject_contexts AS context
      WHERE context.id = _subject_id;

      _subject_expected_sensitivity := CASE
        WHEN lower(trim(coalesce(_subject.raw_sensitivity, ''))) IN ('high', 'sensitive')
          THEN 'high'
        WHEN lower(trim(coalesce(_subject.raw_sensitivity, ''))) IN ('low', 'relaxed')
          THEN 'low'
        ELSE 'balanced'
      END;

      _subject_expected_sha := encode(extensions.digest(jsonb_build_object(
        'version_id', _subject.version_id,
        'user_id', _subject.user_id,
        'effective_from_utc',
          to_char(_subject.effective_from AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'effective_to_utc',
          CASE WHEN _subject.effective_to IS NULL THEN NULL
            ELSE to_char(_subject.effective_to AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
          END,
        'raw_sensitivity', _subject.raw_sensitivity,
        'canonical_sensitivity', _subject.canonical_sensitivity,
        'routine_mode', _subject.routine_mode,
        'timezone', _subject.timezone,
        'utc_offset_minutes', _subject.utc_offset_minutes,
        'settings_updated_at_utc',
          to_char(_subject.settings_updated_at AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'settings_provenance', _subject.settings_provenance,
        'captured_at_utc',
          to_char(_subject.captured_at AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'config_sha256', _subject.config_sha256,
        'evidence_version', _subject.evidence_version
      )::text, 'sha256'), 'hex');

      SELECT floor(extract(epoch FROM (
        ((_evaluated_at AT TIME ZONE _subject.timezone) AT TIME ZONE 'UTC')
        - _evaluated_at
      )) / 60)::integer
        INTO _offset_minutes
      WHERE EXISTS (
        SELECT 1
        FROM pg_catalog.pg_timezone_names AS zone
        WHERE zone.name = _subject.timezone
      );

      IF _subject.config_sha256 <> _version.config_sha256
         OR _subject.evidence_version <> _version.evidence_version
         OR _subject.subject_context_sha256 <> _subject_expected_sha
         OR _subject.canonical_sensitivity <> _subject_expected_sensitivity
         OR _subject.routine_mode NOT IN (
           'regular_9to5', 'semester_break', 'shift_irregular'
         )
         OR _offset_minutes IS NULL
         OR _offset_minutes <> _subject.utc_offset_minutes
         OR _subject.settings_updated_at > _subject.captured_at
         OR _subject.captured_at > _evaluated_at THEN
        _unreplayable_reason := 'subject_context_provenance_invalid';
      END IF;
    END IF;
  END IF;

  IF _unreplayable_reason IS NULL THEN
    SELECT min(coverage.starts_at)
      INTO _session_from
    FROM public.alert_observation_coverage_intervals AS coverage
    WHERE coverage.version_id = _version_id
      AND coverage.user_id = _user_id
      AND coverage.starts_at < _evaluated_at;

    IF _session_from IS NOT NULL AND _session_from < _evaluated_at THEN
      SELECT session.*
        INTO _latest_session
      FROM private.qualified_behavior_sessions(
        _user_id, _session_from, _evaluated_at, _version_id
      ) AS session
      WHERE session.quality_state = 'valid'
      ORDER BY session.session_end DESC, session.session_start DESC
      LIMIT 1;
      _session_found := FOUND;
    END IF;

    IF NOT _session_found THEN
      _unreplayable_reason := 'missing_qualified_session';
    END IF;
  END IF;

  IF _unreplayable_reason IS NOT NULL THEN
    _decision_provenance := jsonb_build_object(
      'version_id', _version_id,
      'evaluator_version', _evaluator_version,
      'evaluated_at', _evaluated_at_utc,
      'evidence_cutoff', _evaluated_at_utc,
      'replayable', false,
      'unreplayable_reason', _unreplayable_reason
    );
    _provenance_sha := encode(
      extensions.digest(_decision_provenance::text, 'sha256'), 'hex'
    );

    RETURN jsonb_build_object(
      'version_id', _version_id,
      'evaluator_version', _evaluator_version,
      'evaluated_at', _evaluated_at_utc,
      'evidence_cutoff', _evaluated_at_utc,
      'replayable', false,
      'unreplayable_reason', _unreplayable_reason,
      'basis', NULL,
      'context_key', NULL,
      'neutral_threshold_minutes', NULL,
      'sensitivity_buffer_minutes', NULL,
      'unclamped_candidate_threshold_minutes', NULL,
      'candidate_floor_minutes', NULL,
      'candidate_ceiling_minutes', NULL,
      'candidate_cap_reason', NULL,
      'candidate_threshold_minutes', NULL,
      'effective_silence_minutes', NULL,
      'candidate_deadline', NULL,
      'deadline_basis', NULL,
      'would_alert', NULL,
      'confidence', NULL,
      'quality_state', 'coverage_invalid',
      'fallback_path', '[]'::jsonb,
      'sleep_interval_provenance', '[]'::jsonb,
      'selected_source_sha256', NULL,
      'subject_context_sha256', NULL,
      'decision_provenance', _decision_provenance,
      'provenance_sha256', _provenance_sha,
      'guardian_used_as_activity', false
    );
  END IF;

  _sensitivity_buffer := CASE _subject.canonical_sensitivity
    WHEN 'high' THEN (_version.config #>> '{sensitivity_buffers_minutes,high}')::integer
    WHEN 'low' THEN (_version.config #>> '{sensitivity_buffers_minutes,low}')::integer
    ELSE (_version.config #>> '{sensitivity_buffers_minutes,balanced}')::integer
  END;

  _fallback_path := ARRAY['personal_context']::text[];

  WITH latest AS MATERIALIZED (
    SELECT candidate.*
    FROM public.alert_gap_profiles AS candidate
    WHERE candidate.version_id = _version_id
      AND candidate.user_id = _user_id
      AND candidate.context_key = _latest_session.context_key
      AND ((candidate.through_date + 1)::timestamp AT TIME ZONE 'UTC')
        <= _evaluated_at
      AND candidate.quality_state = 'valid'
      AND candidate.sample_count >= _personal_min_samples
      AND candidate.distinct_support_dates >= _personal_min_dates
      AND candidate.support_ended_on - candidate.support_started_on + 1
        >= _personal_min_span
      AND candidate.latest_evidence_at < _evaluated_at
      AND candidate.latest_evidence_at
        + make_interval(days => _personal_max_age) > _evaluated_at
      AND candidate.confidence >= _personal_min_confidence
      AND candidate.config_sha256 = _version.config_sha256
      AND candidate.evidence_version = _version.evidence_version
      AND candidate.profile_sha256 = encode(extensions.digest(jsonb_build_object(
        'version_id', candidate.version_id,
        'user_id', candidate.user_id,
        'context_key', candidate.context_key,
        'through_date', candidate.through_date,
        'neutral_p95_minutes', candidate.neutral_p95_minutes,
        'sample_count', candidate.sample_count,
        'distinct_support_dates', candidate.distinct_support_dates,
        'support_started_on', candidate.support_started_on,
        'support_ended_on', candidate.support_ended_on,
        'latest_evidence_at_utc',
          to_char(candidate.latest_evidence_at AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'quality_state', candidate.quality_state,
        'confidence', candidate.confidence,
        'input_sha256', candidate.input_sha256
      )::text, 'sha256'), 'hex')
    ORDER BY candidate.through_date DESC
    LIMIT 1
  )
  SELECT candidate.*
    INTO _profile
  FROM latest AS candidate;

  IF FOUND THEN
    _basis := 'personal_context';
  ELSE
    _fallback_path := pg_catalog.array_append(
      _fallback_path, 'personal_global'
    );
    WITH latest AS MATERIALIZED (
      SELECT candidate.*
      FROM public.alert_gap_profiles AS candidate
      WHERE candidate.version_id = _version_id
        AND candidate.user_id = _user_id
        AND candidate.context_key = 'personal_global'
        AND ((candidate.through_date + 1)::timestamp AT TIME ZONE 'UTC')
          <= _evaluated_at
        AND candidate.quality_state = 'valid'
        AND candidate.sample_count >= _personal_min_samples
        AND candidate.distinct_support_dates >= _personal_min_dates
        AND candidate.support_ended_on - candidate.support_started_on + 1
          >= _personal_min_span
        AND candidate.latest_evidence_at < _evaluated_at
        AND candidate.latest_evidence_at
          + make_interval(days => _personal_max_age) > _evaluated_at
        AND candidate.confidence >= _personal_min_confidence
        AND candidate.config_sha256 = _version.config_sha256
        AND candidate.evidence_version = _version.evidence_version
        AND candidate.profile_sha256 = encode(extensions.digest(jsonb_build_object(
          'version_id', candidate.version_id,
          'user_id', candidate.user_id,
          'context_key', candidate.context_key,
          'through_date', candidate.through_date,
          'neutral_p95_minutes', candidate.neutral_p95_minutes,
          'sample_count', candidate.sample_count,
          'distinct_support_dates', candidate.distinct_support_dates,
          'support_started_on', candidate.support_started_on,
          'support_ended_on', candidate.support_ended_on,
          'latest_evidence_at_utc',
            to_char(candidate.latest_evidence_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
          'quality_state', candidate.quality_state,
          'confidence', candidate.confidence,
          'input_sha256', candidate.input_sha256
        )::text, 'sha256'), 'hex')
      ORDER BY candidate.through_date DESC
      LIMIT 1
    )
    SELECT candidate.*
      INTO _profile
    FROM latest AS candidate;

    IF FOUND THEN
      _basis := 'personal_global';
    END IF;
  END IF;

  IF _basis IN ('personal_context', 'personal_global') THEN
    _neutral := _profile.neutral_p95_minutes;
    _confidence := _profile.confidence;
    _quality_state := _profile.quality_state;
    _selected_source_sha := _profile.profile_sha256;
    _selected_source_support := jsonb_build_object(
      'through_date', _profile.through_date,
      'sample_count', _profile.sample_count,
      'distinct_support_dates', _profile.distinct_support_dates,
      'support_started_on', _profile.support_started_on,
      'support_ended_on', _profile.support_ended_on,
      'latest_evidence_at_utc',
        to_char(_profile.latest_evidence_at AT TIME ZONE 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'input_sha256', _profile.input_sha256,
      'profile_sha256', _profile.profile_sha256,
      'config_sha256', _profile.config_sha256,
      'evidence_version', _profile.evidence_version
    );
  ELSE
    _fallback_path := pg_catalog.array_append(
      _fallback_path, 'routine_cohort'
    );

    WITH latest AS MATERIALIZED (
      SELECT candidate.*
      FROM public.routine_mode_cohort_priors AS candidate
      WHERE candidate.version_id = _version_id
        AND candidate.routine_mode = _subject.routine_mode
        AND candidate.context_key = 'personal_global'
        AND ((candidate.through_date + 1)::timestamp AT TIME ZONE 'UTC')
          <= _evaluated_at
        AND candidate.latest_evidence_at < _evaluated_at
        AND candidate.oldest_evidence_at < _evaluated_at
        AND candidate.valid_until = least(
          candidate.oldest_evidence_at
            + make_interval(days => _personal_max_age),
          candidate.oldest_evidence_at
            + make_interval(days => _cohort_max_age)
        )
        AND private.routine_mode_cohort_prior_is_valid(
          _version_id,
          _subject.routine_mode,
          candidate.through_date,
          _evaluated_at
        )
      ORDER BY candidate.through_date DESC
      LIMIT 1
    )
    SELECT candidate.*
      INTO _prior
    FROM latest AS candidate;

    IF FOUND THEN
      _basis := 'routine_cohort';
      _neutral := _prior.neutral_p95_minutes;
      _confidence := _prior.confidence;
      _quality_state := _prior.quality_state;
      _selected_source_sha := _prior.prior_sha256;
      _selected_source_support := jsonb_build_object(
        'through_date', _prior.through_date,
        'contributor_count', _prior.contributor_count,
        'distinct_support_dates', _prior.distinct_support_dates,
        'conservative_span_days', _prior.conservative_span_days,
        'support_started_on', _prior.support_started_on,
        'support_ended_on', _prior.support_ended_on,
        'latest_evidence_at_utc',
          to_char(_prior.latest_evidence_at AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'oldest_evidence_at_utc',
          to_char(_prior.oldest_evidence_at AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'valid_until_utc',
          to_char(_prior.valid_until AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'minimum_profile_confidence', _prior.minimum_profile_confidence,
        'algorithm', _prior.algorithm,
        'source_generation', _prior.source_generation,
        'input_sha256', _prior.input_sha256,
        'prior_sha256', _prior.prior_sha256,
        'config_sha256', _prior.config_sha256,
        'evidence_version', _prior.evidence_version
      );
    ELSE
      _fallback_path := pg_catalog.array_append(
        _fallback_path, 'deterministic_emergency'
      );
      _basis := 'deterministic_emergency';
      _neutral := _emergency_neutral;
      _confidence := 0;
      _quality_state := 'low_support';
      _selected_source_sha := NULL;
      _selected_source_support := jsonb_build_object(
        'contract_version', 'adr0022_v1',
        'neutral_minutes', _emergency_neutral,
        'expected_live_definition_sha256', _emergency_definition_sha
      );
    END IF;
  END IF;

  _unclamped := _neutral + _sensitivity_buffer;
  IF _basis = 'deterministic_emergency' THEN
    _threshold := _unclamped;
    _cap_reason := 'emergency_exempt';
  ELSIF _unclamped < _candidate_floor THEN
    _threshold := _candidate_floor;
    _cap_reason := 'floor';
  ELSIF _unclamped > _candidate_ceiling THEN
    _threshold := _candidate_ceiling;
    _cap_reason := 'ceiling';
  ELSE
    _threshold := _unclamped;
    _cap_reason := 'none';
  END IF;

  WITH raw_sleep AS MATERIALIZED (
    SELECT
      interval.starts_at,
      interval.ends_at,
      interval.basis,
      interval.confidence,
      interval.provenance,
      context.anchor_date,
      context.coverage_state,
      context.captured_at,
      context.finalized_at,
      context.provenance_sha256 AS context_provenance_sha256,
      tstzrange(
        greatest(interval.starts_at, _latest_session.session_end),
        least(interval.ends_at, _evaluated_at),
        '[)'
      ) AS clipped_range
    FROM private.candidate_sleep_intervals(
      _user_id,
      _latest_session.session_end,
      _evaluated_at,
      _version_id
    ) AS interval
    JOIN public.alert_sleep_night_contexts AS context
      ON context.version_id = _version_id
     AND context.user_id = _user_id
     AND context.anchor_starts_at =
       (interval.provenance ->> 'anchor_starts_at')::timestamptz
     AND context.anchor_ends_at =
       (interval.provenance ->> 'anchor_ends_at')::timestamptz
     AND context.evidence_version = _version.evidence_version
     AND context.captured_at <= _evaluated_at
     AND (
       (
         context.coverage_state = 'unknown'
         AND (
           context.finalized_at IS NULL
           OR context.finalized_at <= _evaluated_at
         )
       )
       OR (
         context.coverage_state IN ('valid', 'outage')
         AND context.finalized_at IS NOT NULL
         AND context.finalized_at >= context.anchor_ends_at
         AND context.finalized_at <= _evaluated_at
       )
     )
    WHERE interval.starts_at < _evaluated_at
      AND interval.ends_at > _latest_session.session_end
      AND greatest(interval.starts_at, _latest_session.session_end)
        < least(interval.ends_at, _evaluated_at)
  ), merged AS (
    SELECT unnest(range_agg(raw_sleep.clipped_range)) AS merged_range
    FROM raw_sleep
  ), described AS (
    SELECT
      merged.merged_range,
      jsonb_build_object(
        'starts_at_utc',
          to_char(lower(merged.merged_range) AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'ends_at_utc',
          to_char(upper(merged.merged_range) AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'sources', (
          SELECT jsonb_agg(jsonb_build_object(
            'starts_at_utc',
              to_char(source.starts_at AT TIME ZONE 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
            'ends_at_utc',
              to_char(source.ends_at AT TIME ZONE 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
            'basis', source.basis,
            'confidence', source.confidence,
            'anchor_date', source.anchor_date,
            'coverage_state', source.coverage_state,
            'captured_at_utc',
              to_char(source.captured_at AT TIME ZONE 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
            'finalized_at_utc',
              CASE WHEN source.finalized_at IS NULL THEN NULL
                ELSE to_char(source.finalized_at AT TIME ZONE 'UTC',
                  'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
              END,
            'context_provenance_sha256', source.context_provenance_sha256,
            'interval_provenance', source.provenance
          ) ORDER BY
            source.starts_at, source.ends_at, source.basis,
            source.confidence, source.provenance::text)
          FROM raw_sleep AS source
          WHERE source.clipped_range && merged.merged_range
        )
      ) AS provenance
    FROM merged
  )
  SELECT
    coalesce(
      array_agg(described.merged_range ORDER BY lower(described.merged_range)),
      ARRAY[]::tstzrange[]
    ),
    coalesce(
      jsonb_agg(described.provenance ORDER BY lower(described.merged_range)),
      '[]'::jsonb
    )
    INTO _sleep_ranges, _sleep_provenance
  FROM described;

  FOREACH _sleep_range IN ARRAY _sleep_ranges
  LOOP
    _sleep_seconds := _sleep_seconds
      + extract(epoch FROM (upper(_sleep_range) - lower(_sleep_range)));
  END LOOP;

  _wall_seconds :=
    extract(epoch FROM (_evaluated_at - _latest_session.session_end));
  _effective_minutes :=
    greatest(0::double precision, _wall_seconds - _sleep_seconds) / 60.0;
  _would_alert := _effective_minutes >= _threshold;

  IF _would_alert THEN
    _deadline_basis := 'known_interval_inversion';
    _remaining_seconds := _threshold::double precision * 60.0;
    _cursor := _latest_session.session_end;

    FOREACH _sleep_range IN ARRAY _sleep_ranges
    LOOP
      IF lower(_sleep_range) > _cursor THEN
        _awake_seconds := extract(epoch FROM (lower(_sleep_range) - _cursor));
        IF _remaining_seconds <= _awake_seconds THEN
          _deadline := _cursor + make_interval(secs => _remaining_seconds);
          EXIT;
        END IF;
        _remaining_seconds := _remaining_seconds - _awake_seconds;
      END IF;
      _cursor := greatest(_cursor, upper(_sleep_range));
    END LOOP;

    IF _deadline IS NULL THEN
      _deadline := _cursor + make_interval(secs => _remaining_seconds);
    END IF;
  ELSE
    _deadline_basis := 'no_future_exclusion';
    _deadline := _evaluated_at
      + make_interval(secs => (_threshold - _effective_minutes) * 60.0);
  END IF;

  _decision_provenance := jsonb_build_object(
    'version_id', _version_id,
    'evaluator_version', _evaluator_version,
    'evaluated_at', _evaluated_at_utc,
    'evidence_cutoff', _evaluated_at_utc,
    'replayable', true,
    'unreplayable_reason', NULL,
    'model_config_sha256', _version.config_sha256,
    'evidence_version', _version.evidence_version,
    'emergency_contract_version',
      _version.config #>> '{emergency,contract_version}',
    'emergency_expected_live_definition_sha256', _emergency_definition_sha,
    'subject_context_sha256', _subject.subject_context_sha256,
    'canonical_sensitivity', _subject.canonical_sensitivity,
    'routine_mode', _subject.routine_mode,
    'timezone', _subject.timezone,
    'utc_offset_minutes', _subject.utc_offset_minutes,
    'latest_session', jsonb_build_object(
      'session_start_utc',
        to_char(_latest_session.session_start AT TIME ZONE 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'session_end_utc',
        to_char(_latest_session.session_end AT TIME ZONE 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'context_key', _latest_session.context_key,
      'evidence_count', _latest_session.evidence_count,
      'quality_state', _latest_session.quality_state
    ),
    'basis', _basis,
    'fallback_path', to_jsonb(_fallback_path),
    'selected_source_sha256', _selected_source_sha,
    'selected_source_support', _selected_source_support,
    'neutral_threshold_minutes', _neutral,
    'sensitivity_buffer_minutes', _sensitivity_buffer,
    'unclamped_candidate_threshold_minutes', _unclamped,
    'candidate_floor_minutes', _candidate_floor,
    'candidate_ceiling_minutes', _candidate_ceiling,
    'candidate_cap_reason', _cap_reason,
    'candidate_threshold_minutes', _threshold,
    'sleep_interval_provenance', _sleep_provenance,
    'effective_silence_minutes', _effective_minutes,
    'candidate_deadline',
      to_char(_deadline AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'deadline_basis', _deadline_basis,
    'would_alert', _would_alert,
    'confidence', _confidence,
    'quality_state', _quality_state,
    'guardian_used_as_activity', false
  );
  _provenance_sha := encode(
    extensions.digest(_decision_provenance::text, 'sha256'), 'hex'
  );

  RETURN jsonb_build_object(
    'version_id', _version_id,
    'evaluator_version', _evaluator_version,
    'evaluated_at', _evaluated_at_utc,
    'evidence_cutoff', _evaluated_at_utc,
    'replayable', true,
    'unreplayable_reason', NULL,
    'basis', _basis,
    'context_key', _latest_session.context_key,
    'neutral_threshold_minutes', _neutral,
    'sensitivity_buffer_minutes', _sensitivity_buffer,
    'unclamped_candidate_threshold_minutes', _unclamped,
    'candidate_floor_minutes', _candidate_floor,
    'candidate_ceiling_minutes', _candidate_ceiling,
    'candidate_cap_reason', _cap_reason,
    'candidate_threshold_minutes', _threshold,
    'effective_silence_minutes', _effective_minutes,
    'candidate_deadline',
      to_char(_deadline AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'deadline_basis', _deadline_basis,
    'would_alert', _would_alert,
    'confidence', _confidence,
    'quality_state', _quality_state,
    'fallback_path', to_jsonb(_fallback_path),
    'sleep_interval_provenance', _sleep_provenance,
    'selected_source_sha256', _selected_source_sha,
    'subject_context_sha256', _subject.subject_context_sha256,
    'decision_provenance', _decision_provenance,
    'provenance_sha256', _provenance_sha,
    'guardian_used_as_activity', false
  );
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.resolve_alert_candidate(uuid, timestamptz, uuid)
FROM PUBLIC, anon, authenticated, service_role;

-- Task 3's original helper predates a fixed replay cutoff for context
-- finalization. Preserve its algorithm and signature, but make both the
-- evaluated night and every prior night strictly as-of `_to`.
CREATE OR REPLACE FUNCTION private.candidate_sleep_intervals(
  _user_id uuid,
  _from timestamptz,
  _to timestamptz,
  _version_id uuid
)
RETURNS TABLE (
  starts_at timestamptz,
  ends_at timestamptz,
  basis text,
  confidence double precision,
  provenance jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
SET TimeZone = 'UTC'
SET "DateStyle" = 'ISO, YMD'
SET extra_float_digits = 3
AS $$
DECLARE
  _config jsonb;
  _config_sha256 text;
  _max_start_delay integer;
  _max_wake_advance integer;
  _max_wake_delay integer;
  _max_update_per_day integer;
  _min_positive integer;
  _lookback integer;
  _min_late_events integer;
  _timezone_tolerance integer;
  _status text;
  _evidence_version text;
  _context record;
  _anchor_start timestamptz;
  _anchor_end timestamptz;
  _midpoint timestamptz;
  _raw_start_delay integer;
  _raw_wake_advance integer;
  _raw_wake_delay integer;
  _start_delay integer;
  _wake_advance integer;
  _wake_delay integer;
  _rate_cap integer;
  _first_count integer;
  _second_count integer;
  _prior_count integer;
  _prior_start_cap_applied boolean;
  _quality_reason text;
  _cap_reasons text[];
  _offset_minutes integer;
BEGIN
  IF _user_id IS NULL OR _version_id IS NULL
     OR _from IS NULL OR _to IS NULL OR _from >= _to THEN
    RETURN;
  END IF;

  SELECT version.config, version.config_sha256,
         version.status, version.evidence_version
    INTO _config, _config_sha256, _status, _evidence_version
  FROM public.alert_model_versions AS version
  WHERE version.id = _version_id;

  IF NOT FOUND
     OR _status NOT IN ('replay', 'shadow')
     OR _evidence_version <> 'canonical-v2'
     OR _config_sha256
        <> encode(extensions.digest(_config::text, 'sha256'), 'hex') THEN
    RETURN;
  END IF;

  -- See private.alert_candidate_config_is_valid: a canonical config hash
  -- cannot prove a legacy row's scalars have the required raw JSON type,
  -- range, or integrality, so this must be checked before any type is
  -- assumed from a bare cast.
  IF NOT private.alert_candidate_config_is_valid(_config) THEN
    RETURN;
  END IF;

  _max_start_delay :=
    (_config #>> '{sleep_compensation,max_start_delay_minutes}')::integer;
  _max_wake_advance :=
    (_config #>> '{sleep_compensation,max_wake_advance_minutes}')::integer;
  _max_wake_delay :=
    (_config #>> '{sleep_compensation,max_wake_delay_minutes}')::integer;
  _max_update_per_day :=
    (_config #>> '{sleep_compensation,max_update_minutes_per_day}')::integer;
  _min_positive :=
    (_config #>> '{sleep_compensation,min_positive_nights}')::integer;
  _lookback :=
    (_config #>> '{sleep_compensation,lookback_nights}')::integer;
  _min_late_events :=
    (_config #>> '{sleep_compensation,min_late_events_per_night}')::integer;
  _timezone_tolerance :=
    (_config #>> '{sleep_compensation,timezone_tolerance_minutes}')::integer;

  FOR _context IN
    SELECT context.*
    FROM public.alert_sleep_night_contexts AS context
    WHERE context.version_id = _version_id
      AND context.user_id = _user_id
      AND context.evidence_version = 'canonical-v2'
      AND context.anchor_starts_at < _to
      AND context.anchor_ends_at > _from
      AND context.captured_at <= _to
      AND (
        (
          context.coverage_state = 'unknown'
          AND (context.finalized_at IS NULL OR context.finalized_at <= _to)
        )
        OR (
          context.coverage_state IN ('valid', 'outage')
          AND context.finalized_at IS NOT NULL
          AND context.finalized_at >= context.anchor_ends_at
          AND context.finalized_at <= _to
        )
      )
    ORDER BY context.anchor_starts_at
  LOOP
    IF NOT EXISTS (
         SELECT 1
         FROM pg_catalog.pg_timezone_names AS zone
         WHERE zone.name = _context.timezone
       )
       OR _context.sleep_start_local = _context.sleep_end_local
       OR _context.anchor_ends_at <= _context.anchor_starts_at
       OR _context.captured_at > _context.anchor_starts_at
       OR (
         _context.coverage_state IN ('valid', 'outage')
         AND (
           _context.finalized_at IS NULL
           OR _context.finalized_at < _context.anchor_ends_at
           OR _context.finalized_at > _to
         )
       )
       OR (
         _context.coverage_state = 'unknown'
         AND _context.finalized_at IS NOT NULL
         AND _context.finalized_at > _to
       ) THEN
      CONTINUE;
    END IF;

    _anchor_start :=
      ((_context.anchor_date + _context.sleep_start_local)
        AT TIME ZONE _context.timezone);
    _anchor_end := ((
      _context.anchor_date
      + CASE
          WHEN _context.sleep_end_local <= _context.sleep_start_local THEN 1
          ELSE 0
        END
      + _context.sleep_end_local
    ) AT TIME ZONE _context.timezone);
    _offset_minutes := extract(epoch FROM (
      ((_context.anchor_starts_at AT TIME ZONE _context.timezone)
        AT TIME ZONE 'UTC') - _context.anchor_starts_at
    ))::integer / 60;

    IF _anchor_start <> _context.anchor_starts_at
       OR _anchor_end <> _context.anchor_ends_at
       OR _offset_minutes <> _context.utc_offset_minutes THEN
      CONTINUE;
    END IF;

    _midpoint := _anchor_start + ((_anchor_end - _anchor_start) / 2);
    SELECT
      count(*) FILTER (
        WHERE ping.received_at >= _anchor_start
          AND ping.received_at < _midpoint
      )::integer,
      count(*) FILTER (
        WHERE ping.received_at >= _midpoint
          AND ping.received_at < _anchor_end
      )::integer,
      coalesce(floor(extract(epoch FROM (
        max(ping.received_at) FILTER (
          WHERE ping.received_at >= _anchor_start
            AND ping.received_at < _midpoint
        ) - _anchor_start
      )) / 60)::integer, 0),
      coalesce(floor(extract(epoch FROM (
        _anchor_end - min(ping.received_at) FILTER (
          WHERE ping.received_at >= _midpoint
            AND ping.received_at < _anchor_end
        )
      )) / 60)::integer, 0)
      INTO _first_count, _second_count,
           _raw_start_delay, _raw_wake_advance
    FROM public.behavior_pings AS ping
    WHERE ping.user_id = _user_id
      AND ping.ingest_version = 2
      AND abs(extract(epoch FROM (ping.received_at - ping.at))) <= 300
      AND ping.at < _to
      AND ping.received_at < _to;

    _cap_reasons := ARRAY[]::text[];
    IF _raw_start_delay > _max_start_delay THEN
      _cap_reasons := pg_catalog.array_append(
        _cap_reasons, 'max_start_delay_minutes'
      );
    END IF;
    IF _raw_wake_advance > _max_wake_advance THEN
      _cap_reasons := pg_catalog.array_append(
        _cap_reasons, 'max_wake_advance_minutes'
      );
    END IF;
    _start_delay := least(_max_start_delay, greatest(0, _raw_start_delay));
    _wake_advance := least(_max_wake_advance, greatest(0, _raw_wake_advance));
    _wake_delay := 0;
    _raw_wake_delay := 0;
    _rate_cap := 0;
    _prior_count := 0;
    _prior_start_cap_applied := false;
    _quality_reason := CASE
      WHEN _context.coverage_state = 'valid' THEN 'coverage_valid'
      ELSE 'coverage_' || _context.coverage_state
    END;

    IF _context.coverage_state = 'valid' THEN
      WITH prior_contexts AS (
        SELECT
          prior.anchor_date,
          prior.anchor_starts_at,
          prior.anchor_ends_at,
          prior.anchor_starts_at
            + ((prior.anchor_ends_at - prior.anchor_starts_at) / 2)
            AS midpoint
        FROM public.alert_sleep_night_contexts AS prior
        WHERE prior.version_id = _version_id
          AND prior.user_id = _user_id
          AND prior.coverage_state = 'valid'
          AND prior.evidence_version = 'canonical-v2'
          AND prior.anchor_date < _context.anchor_date
          AND prior.anchor_date >= (_context.anchor_date - _lookback)
          AND prior.timezone = _context.timezone
          AND abs(prior.utc_offset_minutes - _context.utc_offset_minutes)
            <= _timezone_tolerance
          AND prior.captured_at <= prior.anchor_starts_at
          AND prior.captured_at <= _to
          AND prior.finalized_at >= prior.anchor_ends_at
          AND prior.finalized_at <= _to
          AND (
            (prior.anchor_date + prior.sleep_start_local)
              AT TIME ZONE prior.timezone
          ) = prior.anchor_starts_at
          AND ((
            prior.anchor_date
            + CASE
                WHEN prior.sleep_end_local <= prior.sleep_start_local THEN 1
                ELSE 0
              END
            + prior.sleep_end_local
          ) AT TIME ZONE prior.timezone) = prior.anchor_ends_at
          AND extract(epoch FROM (
            ((prior.anchor_starts_at AT TIME ZONE prior.timezone)
              AT TIME ZONE 'UTC') - prior.anchor_starts_at
          ))::integer / 60 = prior.utc_offset_minutes
      ), prior_delays AS (
        SELECT
          prior.anchor_date,
          floor(extract(epoch FROM (
            max(ping.received_at) - prior.anchor_starts_at
          )) / 60)::integer AS raw_delay_minutes,
          least(
            _max_start_delay,
            floor(extract(epoch FROM (
              max(ping.received_at) - prior.anchor_starts_at
            )) / 60)::integer
          ) AS delay_minutes
        FROM prior_contexts AS prior
        JOIN public.behavior_pings AS ping
          ON ping.user_id = _user_id
         AND ping.ingest_version = 2
         AND abs(extract(epoch FROM (ping.received_at - ping.at))) <= 300
         AND ping.at < _to
         AND ping.received_at < _to
         AND ping.received_at >= prior.anchor_starts_at
         AND ping.received_at < prior.midpoint
        GROUP BY prior.anchor_date, prior.anchor_starts_at
        HAVING count(*) >= _min_late_events
      )
      SELECT
        count(*)::integer,
        coalesce(
          percentile_disc(0.5)
            WITHIN GROUP (ORDER BY delay_minutes)::integer,
          0
        ),
        coalesce(bool_or(raw_delay_minutes > _max_start_delay), false)
        INTO _prior_count, _raw_wake_delay, _prior_start_cap_applied
      FROM prior_delays;

      IF _prior_count >= _min_positive THEN
        _rate_cap :=
          greatest(0, _prior_count - _min_positive + 1)
          * _max_update_per_day;
        IF _prior_start_cap_applied THEN
          _cap_reasons := pg_catalog.array_append(
            _cap_reasons, 'prior_max_start_delay_minutes'
          );
        END IF;
        IF _raw_wake_delay > _max_wake_delay THEN
          _cap_reasons := pg_catalog.array_append(
            _cap_reasons, 'max_wake_delay_minutes'
          );
        END IF;
        IF least(_raw_wake_delay, _max_wake_delay) > _rate_cap THEN
          _cap_reasons := pg_catalog.array_append(
            _cap_reasons, 'max_update_minutes_per_day'
          );
        END IF;
        _wake_delay :=
          least(_max_wake_delay, _raw_wake_delay, _rate_cap);
        _quality_reason := 'coverage_valid_prior_positive';
      ELSE
        _wake_delay := 0;
      END IF;
    END IF;

    starts_at := _anchor_start + make_interval(mins => _start_delay);
    ends_at := _anchor_end
      - make_interval(mins => _wake_advance)
      + make_interval(mins => _wake_delay);
    IF starts_at >= ends_at THEN
      CONTINUE;
    END IF;

    basis := CASE
      WHEN _start_delay > 0 OR _wake_advance > 0 OR _wake_delay > 0
        THEN 'positive_evidence_adjusted'
      ELSE 'configured_anchor'
    END;
    confidence := CASE
      WHEN _start_delay > 0 OR _wake_advance > 0 THEN 1.0
      WHEN _wake_delay > 0 THEN least(
        1.0,
        _prior_count::double precision / _min_positive::double precision
      )
      ELSE 0.0
    END;
    provenance := jsonb_build_object(
      'config_sha256', _config_sha256,
      'anchor_starts_at', _anchor_start,
      'anchor_ends_at', _anchor_end,
      'context_captured_at', _context.captured_at,
      'context_finalized_at', _context.finalized_at,
      'context_evidence_version', _context.evidence_version,
      'context_provenance_sha256', _context.provenance_sha256,
      'evidence_cutoff', _to,
      'first_half_positive_count', _first_count,
      'second_half_positive_count', _second_count,
      'prior_positive_night_count', _prior_count,
      'start_delay_minutes', _start_delay,
      'wake_advance_minutes', _wake_advance,
      'wake_delay_minutes', _wake_delay,
      'caps', jsonb_build_object(
        'max_start_delay_minutes', _max_start_delay,
        'max_wake_advance_minutes', _max_wake_advance,
        'max_wake_delay_minutes', _max_wake_delay,
        'max_update_minutes_per_day', _max_update_per_day
      ),
      'confidence', confidence,
      'cap_reason',
        coalesce(pg_catalog.array_to_string(_cap_reasons, ','), 'none'),
      'timezone', _context.timezone,
      'utc_offset_minutes', _context.utc_offset_minutes,
      'coverage_state', _context.coverage_state,
      'quality_reason', _quality_reason
    );
    RETURN NEXT;
  END LOOP;
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.candidate_sleep_intervals(uuid, timestamptz, timestamptz, uuid)
FROM PUBLIC, anon, authenticated, service_role;

-- Append-only harden the Task 4/5 candidate hash producers/validators this
-- pipeline invokes so their canonical-hash serialization cannot vary with a
-- caller's session DateStyle/extra_float_digits. Their bodies and signatures
-- are untouched; only their pinned configuration parameters are extended.
ALTER FUNCTION private.rebuild_alert_gap_profiles(uuid, date)
  SET "DateStyle" = 'ISO, YMD';
ALTER FUNCTION private.rebuild_alert_gap_profiles(uuid, date)
  SET extra_float_digits = 3;

ALTER FUNCTION private.rebuild_routine_mode_cohort_priors(uuid, date, text)
  SET "DateStyle" = 'ISO, YMD';
ALTER FUNCTION private.rebuild_routine_mode_cohort_priors(uuid, date, text)
  SET extra_float_digits = 3;

ALTER FUNCTION private.routine_mode_cohort_prior_is_valid(
  uuid, text, date, timestamptz
) SET "DateStyle" = 'ISO, YMD';
ALTER FUNCTION private.routine_mode_cohort_prior_is_valid(
  uuid, text, date, timestamptz
) SET extra_float_digits = 3;
