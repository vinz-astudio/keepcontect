-- ADR-0023: candidate-only, versioned adaptive-alert data boundary.
-- This schema intentionally has no policy, scheduler, realtime publication, or
-- executable evaluator. Later private workers may use it only after their own
-- append-only migration and tests; it has no authority over the live alert path.

CREATE TABLE public.alert_model_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE CHECK (length(trim(name)) BETWEEN 1 AND 120),
  status text NOT NULL CHECK (status IN ('draft', 'replay', 'shadow', 'retired')),
  config jsonb NOT NULL,
  config_sha256 text NOT NULL CHECK (config_sha256 ~ '^[a-f0-9]{64}$'),
  evidence_version text NOT NULL CHECK (length(trim(evidence_version)) > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  shadow_enabled_at timestamptz,
  CHECK (status <> 'shadow' OR shadow_enabled_at IS NOT NULL),
  CHECK (
    jsonb_typeof(config) = 'object'
    AND config ?& ARRAY[
      'sessionization', 'context', 'personal', 'cohort',
      'sensitivity_buffers_minutes', 'candidate_bounds', 'sleep_compensation'
    ]
    AND jsonb_typeof(config -> 'sessionization') = 'object'
    AND (config -> 'sessionization') ?& ARRAY['gap_minutes', 'per_user_day_gap_cap']
    AND jsonb_typeof(config #> '{sessionization,gap_minutes}') = 'number'
    AND (config #>> '{sessionization,gap_minutes}')::numeric > 0
    AND jsonb_typeof(config #> '{sessionization,per_user_day_gap_cap}') = 'number'
    AND (config #>> '{sessionization,per_user_day_gap_cap}')::numeric > 0
    AND jsonb_typeof(config -> 'context') = 'object'
    AND (config -> 'context') ?& ARRAY['definition_version']
    AND jsonb_typeof(config #> '{context,definition_version}') = 'string'
    AND length(trim(config #>> '{context,definition_version}')) > 0
    AND jsonb_typeof(config -> 'personal') = 'object'
    AND (config -> 'personal') ?& ARRAY['min_samples', 'min_support_dates', 'min_span_days', 'max_age_days']
    AND jsonb_typeof(config #> '{personal,min_samples}') = 'number'
    AND (config #>> '{personal,min_samples}')::numeric > 0
    AND jsonb_typeof(config #> '{personal,min_support_dates}') = 'number'
    AND (config #>> '{personal,min_support_dates}')::numeric > 0
    AND jsonb_typeof(config #> '{personal,min_span_days}') = 'number'
    AND (config #>> '{personal,min_span_days}')::numeric > 0
    AND jsonb_typeof(config #> '{personal,max_age_days}') = 'number'
    AND (config #>> '{personal,max_age_days}')::numeric > 0
    AND jsonb_typeof(config -> 'cohort') = 'object'
    AND (config -> 'cohort') ?& ARRAY['min_contributors', 'min_support_dates', 'max_age_days', 'algorithm', 'trim_fraction']
    AND jsonb_typeof(config #> '{cohort,min_contributors}') = 'number'
    AND (config #>> '{cohort,min_contributors}')::numeric > 0
    AND jsonb_typeof(config #> '{cohort,min_support_dates}') = 'number'
    AND (config #>> '{cohort,min_support_dates}')::numeric > 0
    AND jsonb_typeof(config #> '{cohort,max_age_days}') = 'number'
    AND (config #>> '{cohort,max_age_days}')::numeric > 0
    AND jsonb_typeof(config #> '{cohort,algorithm}') = 'string'
    AND config #>> '{cohort,algorithm}' IN ('weighted_median', 'trimmed_mean')
    AND jsonb_typeof(config #> '{cohort,trim_fraction}') = 'number'
    AND (config #>> '{cohort,trim_fraction}')::numeric >= 0
    AND (config #>> '{cohort,trim_fraction}')::numeric < 0.5
    AND jsonb_typeof(config -> 'sensitivity_buffers_minutes') = 'object'
    AND (config -> 'sensitivity_buffers_minutes') ?& ARRAY['high', 'balanced', 'low']
    AND jsonb_typeof(config #> '{sensitivity_buffers_minutes,high}') = 'number'
    AND jsonb_typeof(config #> '{sensitivity_buffers_minutes,balanced}') = 'number'
    AND jsonb_typeof(config #> '{sensitivity_buffers_minutes,low}') = 'number'
    AND config #>> '{sensitivity_buffers_minutes,high}' = '0'
    AND config #>> '{sensitivity_buffers_minutes,balanced}' = '45'
    AND config #>> '{sensitivity_buffers_minutes,low}' = '90'
    AND jsonb_typeof(config -> 'candidate_bounds') = 'object'
    AND (config -> 'candidate_bounds') ?& ARRAY['floor_minutes', 'ceiling_minutes']
    AND jsonb_typeof(config #> '{candidate_bounds,floor_minutes}') = 'number'
    AND (config #>> '{candidate_bounds,floor_minutes}')::numeric >= 0
    AND jsonb_typeof(config #> '{candidate_bounds,ceiling_minutes}') = 'number'
    AND (config #>> '{candidate_bounds,ceiling_minutes}')::numeric >= (config #>> '{candidate_bounds,floor_minutes}')::numeric
    AND jsonb_typeof(config -> 'sleep_compensation') = 'object'
    AND (config -> 'sleep_compensation') ?& ARRAY[
      'max_start_delay_minutes', 'max_wake_advance_minutes', 'max_wake_delay_minutes',
      'max_update_minutes_per_day', 'min_positive_nights', 'timezone_tolerance_minutes'
    ]
    AND jsonb_typeof(config #> '{sleep_compensation,max_start_delay_minutes}') = 'number'
    AND (config #>> '{sleep_compensation,max_start_delay_minutes}')::numeric >= 0
    AND jsonb_typeof(config #> '{sleep_compensation,max_wake_advance_minutes}') = 'number'
    AND (config #>> '{sleep_compensation,max_wake_advance_minutes}')::numeric >= 0
    AND jsonb_typeof(config #> '{sleep_compensation,max_wake_delay_minutes}') = 'number'
    AND (config #>> '{sleep_compensation,max_wake_delay_minutes}')::numeric >= 0
    AND jsonb_typeof(config #> '{sleep_compensation,max_update_minutes_per_day}') = 'number'
    AND (config #>> '{sleep_compensation,max_update_minutes_per_day}')::numeric >= 0
    AND jsonb_typeof(config #> '{sleep_compensation,min_positive_nights}') = 'number'
    AND (config #>> '{sleep_compensation,min_positive_nights}')::numeric > 0
    AND jsonb_typeof(config #> '{sleep_compensation,timezone_tolerance_minutes}') = 'number'
    AND (config #>> '{sleep_compensation,timezone_tolerance_minutes}')::numeric >= 0
  )
);

CREATE TABLE public.alert_gap_profiles (
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  context_key text NOT NULL CHECK (length(trim(context_key)) > 0),
  through_date date NOT NULL,
  neutral_p95_minutes integer NOT NULL CHECK (neutral_p95_minutes > 0),
  sample_count integer NOT NULL CHECK (sample_count > 0),
  distinct_support_dates integer NOT NULL CHECK (distinct_support_dates > 0),
  support_started_on date NOT NULL,
  support_ended_on date NOT NULL,
  latest_evidence_at timestamptz NOT NULL,
  quality_state text NOT NULL CHECK (quality_state IN ('valid', 'low_support', 'stale', 'drift_invalid', 'coverage_invalid')),
  confidence double precision NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
  profile_sha256 text NOT NULL CHECK (profile_sha256 ~ '^[a-f0-9]{64}$'),
  computed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (version_id, user_id, context_key, through_date),
  CHECK (support_ended_on >= support_started_on),
  CHECK (through_date >= support_ended_on)
);

CREATE TABLE public.routine_mode_cohort_priors (
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE RESTRICT,
  routine_mode text NOT NULL CHECK (routine_mode IN ('regular_9to5', 'semester_break', 'shift_irregular')),
  context_key text NOT NULL CHECK (length(trim(context_key)) > 0),
  through_date date NOT NULL,
  contributor_count integer NOT NULL CHECK (contributor_count > 0),
  distinct_support_dates integer NOT NULL CHECK (distinct_support_dates > 0),
  support_started_on date NOT NULL,
  support_ended_on date NOT NULL,
  latest_evidence_at timestamptz NOT NULL,
  neutral_p95_minutes integer NOT NULL CHECK (neutral_p95_minutes > 0),
  quality_state text NOT NULL CHECK (quality_state IN ('valid', 'low_support', 'stale', 'drift_invalid', 'coverage_invalid')),
  confidence double precision NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
  algorithm text NOT NULL CHECK (algorithm IN ('weighted_median', 'trimmed_mean')),
  config_sha256 text NOT NULL CHECK (config_sha256 ~ '^[a-f0-9]{64}$'),
  evidence_version text NOT NULL CHECK (length(trim(evidence_version)) > 0),
  input_sha256 text NOT NULL CHECK (input_sha256 ~ '^[a-f0-9]{64}$'),
  prior_sha256 text NOT NULL CHECK (prior_sha256 ~ '^[a-f0-9]{64}$'),
  published_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (version_id, routine_mode, context_key, through_date),
  CHECK (support_ended_on >= support_started_on),
  CHECK (through_date >= support_ended_on)
);

CREATE TABLE public.alert_judgment_shadow_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  evaluated_at timestamptz NOT NULL,
  evaluated_minute timestamptz GENERATED ALWAYS AS (
    date_trunc('minute', evaluated_at AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'
  ) STORED,
  basis text NOT NULL CHECK (basis IN ('personal_context', 'personal_global', 'routine_cohort', 'deterministic_emergency')),
  evaluator_version text NOT NULL CHECK (length(trim(evaluator_version)) > 0),
  context_key text NOT NULL CHECK (length(trim(context_key)) > 0),
  neutral_threshold_minutes integer NOT NULL CHECK (neutral_threshold_minutes >= 0),
  sensitivity_buffer_minutes integer NOT NULL CHECK (sensitivity_buffer_minutes IN (0, 45, 90)),
  candidate_threshold_minutes integer NOT NULL CHECK (candidate_threshold_minutes >= neutral_threshold_minutes),
  effective_silence_minutes double precision NOT NULL CHECK (effective_silence_minutes >= 0),
  candidate_deadline timestamptz NOT NULL,
  would_alert boolean NOT NULL,
  confidence double precision NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
  quality_state text NOT NULL CHECK (quality_state IN ('valid', 'low_support', 'stale', 'drift_invalid', 'coverage_invalid')),
  fallback_path text[] NOT NULL CHECK (cardinality(fallback_path) >= 1),
  sleep_interval_provenance jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(sleep_interval_provenance) = 'array'),
  provenance_sha256 text NOT NULL CHECK (provenance_sha256 ~ '^[a-f0-9]{64}$'),
  guardian_used_as_activity boolean NOT NULL DEFAULT false CHECK (guardian_used_as_activity = false),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (version_id, user_id, evaluated_minute)
);

CREATE TABLE public.alert_judgment_evaluations (
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE RESTRICT,
  evaluation_kind text NOT NULL CHECK (evaluation_kind IN ('historical_replay', 'shadow_summary')),
  evaluated_from timestamptz NOT NULL,
  evaluated_to timestamptz NOT NULL,
  metrics jsonb NOT NULL CHECK (jsonb_typeof(metrics) = 'object'),
  input_sha256 text NOT NULL CHECK (input_sha256 ~ '^[a-f0-9]{64}$'),
  output_sha256 text NOT NULL CHECK (output_sha256 ~ '^[a-f0-9]{64}$'),
  evaluator_version text NOT NULL CHECK (length(trim(evaluator_version)) > 0),
  promotion_eligible boolean NOT NULL DEFAULT false CHECK (promotion_eligible = false),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (version_id, evaluation_kind, evaluated_from, evaluated_to),
  CHECK (evaluated_to > evaluated_from)
);

ALTER TABLE public.alert_model_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alert_gap_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routine_mode_cohort_priors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alert_judgment_shadow_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alert_judgment_evaluations ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON TABLE
  public.alert_model_versions,
  public.alert_gap_profiles,
  public.routine_mode_cohort_priors,
  public.alert_judgment_shadow_decisions,
  public.alert_judgment_evaluations
FROM PUBLIC, anon, authenticated, service_role;
