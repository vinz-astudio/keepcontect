-- ADR-0023 Task 5: privacy-qualified, aggregate-only Routine-mode priors.
-- This is candidate evidence only. It has no scheduler, realtime publication,
-- live alert write, or model/calibration seed.

ALTER TABLE public.alert_model_versions
  ADD CONSTRAINT alert_model_versions_cohort_prior_contract_check CHECK (
    (
      jsonb_typeof(config #> '{cohort,contribution_floor_minutes}') = 'number'
      AND (config #>> '{cohort,contribution_floor_minutes}')::numeric > 0
      AND (config #>> '{cohort,contribution_floor_minutes}')::numeric = trunc((config #>> '{cohort,contribution_floor_minutes}')::numeric)
      AND jsonb_typeof(config #> '{cohort,contribution_ceiling_minutes}') = 'number'
      AND (config #>> '{cohort,contribution_ceiling_minutes}')::numeric > 0
      AND (config #>> '{cohort,contribution_ceiling_minutes}')::numeric = trunc((config #>> '{cohort,contribution_ceiling_minutes}')::numeric)
      AND (config #>> '{cohort,contribution_ceiling_minutes}')::numeric >= (config #>> '{cohort,contribution_floor_minutes}')::numeric
      AND jsonb_typeof(config #> '{cohort,min_span_days}') = 'number'
      AND (config #>> '{cohort,min_span_days}')::numeric > 0
      AND (config #>> '{cohort,min_span_days}')::numeric = trunc((config #>> '{cohort,min_span_days}')::numeric)
      AND jsonb_typeof(config #> '{cohort,min_confidence}') = 'number'
      AND (config #>> '{cohort,min_confidence}')::numeric > 0
      AND (config #>> '{cohort,min_confidence}')::numeric <= 1
      AND jsonb_typeof(config #> '{cohort,confidence_formula_version}') = 'string'
      AND config #>> '{cohort,confidence_formula_version}' = 'cohort_support_min_v1'
    ) IS TRUE
  ) NOT VALID;

ALTER TABLE public.routine_mode_cohort_priors
  ADD COLUMN source_generation bigint NOT NULL DEFAULT 0 CHECK (source_generation >= 0),
  ADD COLUMN oldest_evidence_at timestamptz,
  ADD COLUMN valid_until timestamptz,
  ADD COLUMN conservative_span_days integer CHECK (conservative_span_days > 0),
  ADD COLUMN minimum_profile_confidence double precision CHECK (minimum_profile_confidence > 0 AND minimum_profile_confidence <= 1);

CREATE TABLE public.routine_mode_cohort_generations (
  routine_mode text PRIMARY KEY CHECK (routine_mode IN ('regular_9to5', 'semester_break', 'shift_irregular')),
  generation bigint NOT NULL DEFAULT 0 CHECK (generation >= 0),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

INSERT INTO public.routine_mode_cohort_generations (routine_mode, generation)
VALUES ('regular_9to5', 0), ('semester_break', 0), ('shift_irregular', 0)
ON CONFLICT (routine_mode) DO NOTHING;

ALTER TABLE public.routine_mode_cohort_invalidations
  ADD COLUMN generation bigint NOT NULL DEFAULT 0 CHECK (generation >= 0);

ALTER TABLE public.routine_mode_cohort_generations ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.routine_mode_cohort_generations
FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.invalidate_routine_mode_cohort()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _mode text;
  _generation bigint;
BEGIN
  IF TG_OP = 'UPDATE'
     AND OLD.routine_pattern IS NOT DISTINCT FROM NEW.routine_pattern
     AND OLD.consent_data_sharing IS NOT DISTINCT FROM NEW.consent_data_sharing THEN
    RETURN NEW;
  END IF;

  FOR _mode IN
    SELECT DISTINCT candidate.routine_mode
    FROM (
      SELECT CASE
        WHEN TG_OP = 'INSERT' THEN private.canonical_routine_mode(NEW.routine_pattern)
        WHEN TG_OP = 'DELETE' THEN private.canonical_routine_mode(OLD.routine_pattern)
        ELSE private.canonical_routine_mode(OLD.routine_pattern)
      END AS routine_mode
      UNION ALL
      SELECT CASE WHEN TG_OP = 'UPDATE' THEN private.canonical_routine_mode(NEW.routine_pattern) END
    ) AS candidate
    WHERE candidate.routine_mode IS NOT NULL
    ORDER BY candidate.routine_mode
  LOOP
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('keep-contact:routine-mode-cohort:' || _mode, 0)
    );

    UPDATE public.routine_mode_cohort_generations
    SET generation = generation + 1,
        updated_at = clock_timestamp()
    WHERE routine_mode = _mode
    RETURNING generation INTO _generation;

    INSERT INTO public.routine_mode_cohort_invalidations (routine_mode, invalidated_at, generation)
    VALUES (_mode, clock_timestamp(), _generation)
    ON CONFLICT (routine_mode) DO UPDATE
    SET invalidated_at = EXCLUDED.invalidated_at,
        generation = EXCLUDED.generation;
  END LOOP;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_profile_routine_mode_cohort_invalidation ON public.profiles;
CREATE TRIGGER on_profile_routine_mode_cohort_invalidation
AFTER INSERT OR DELETE OR UPDATE OF routine_pattern, consent_data_sharing
ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION private.invalidate_routine_mode_cohort();

CREATE FUNCTION private.invalidate_routine_mode_cohort_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _mode text;
  _generation bigint;
BEGIN
  -- Both sides matter: a key can stop being personal_global, start being it,
  -- or move between users/modes. Resolve current modes only, deduplicate them,
  -- then lock in lexical order before each single generation increment.
  FOR _mode IN
    WITH affected_users(user_id) AS (
      SELECT OLD.user_id
      WHERE TG_OP <> 'INSERT' AND OLD.context_key = 'personal_global'
      UNION
      SELECT NEW.user_id
      WHERE TG_OP <> 'DELETE' AND NEW.context_key = 'personal_global'
    )
    SELECT DISTINCT private.canonical_routine_mode(p.routine_pattern)
    FROM affected_users AS affected
    JOIN public.profiles AS p ON p.id = affected.user_id
    ORDER BY private.canonical_routine_mode(p.routine_pattern)
  LOOP
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('keep-contact:routine-mode-cohort:' || _mode, 0)
    );
    UPDATE public.routine_mode_cohort_generations
    SET generation = generation + 1,
        updated_at = clock_timestamp()
    WHERE routine_mode = _mode
    RETURNING generation INTO _generation;
    INSERT INTO public.routine_mode_cohort_invalidations (routine_mode, invalidated_at, generation)
    VALUES (_mode, clock_timestamp(), _generation)
    ON CONFLICT (routine_mode) DO UPDATE
    SET invalidated_at = EXCLUDED.invalidated_at,
        generation = EXCLUDED.generation;
  END LOOP;

  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_alert_gap_profile_routine_mode_cohort_invalidation
AFTER INSERT OR UPDATE OR DELETE ON public.alert_gap_profiles
FOR EACH ROW
EXECUTE FUNCTION private.invalidate_routine_mode_cohort_profile();

CREATE FUNCTION private.rebuild_routine_mode_cohort_priors(
  _version_id uuid,
  _through_date date,
  _routine_mode text
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET TimeZone = 'UTC'
AS $$
DECLARE
  _config jsonb;
  _config_sha256 text;
  _evidence_version text;
  _status text;
  _mode text := private.canonical_routine_mode(_routine_mode);
  _generation bigint;
  _personal_min_samples integer;
  _personal_min_dates integer;
  _personal_min_span integer;
  _personal_max_age integer;
  _cohort_min_contributors integer;
  _cohort_min_dates integer;
  _cohort_min_span integer;
  _cohort_max_age integer;
  _cohort_min_confidence double precision;
  _floor integer;
  _ceiling integer;
  _algorithm text;
  _trim_fraction double precision;
  _count integer;
  _support_dates integer;
  _conservative_span_days integer;
  _support_started date;
  _support_ended date;
  _oldest_evidence timestamptz;
  _latest_evidence timestamptz;
  _valid_until timestamptz;
  _minimum_confidence double precision;
  _confidence double precision;
  _neutral integer;
  _quality text;
  _multiset text;
  _input_sha256 text;
  _prior_sha256 text;
  _published integer := 0;
  _cutoff timestamptz;
BEGIN
  IF _version_id IS NULL OR _through_date IS NULL
     OR _mode NOT IN ('regular_9to5', 'semester_break', 'shift_irregular') THEN
    RETURN jsonb_build_object('published', 0, 'routine_mode', _mode);
  END IF;

  _cutoff := (_through_date + 1)::timestamptz;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('keep-contact:routine-mode-cohort:' || _mode, 0)
  );

  SELECT v.config, v.config_sha256, v.evidence_version, v.status
    INTO _config, _config_sha256, _evidence_version, _status
  FROM public.alert_model_versions AS v
  WHERE v.id = _version_id;

  SELECT generation INTO _generation
  FROM public.routine_mode_cohort_generations
  WHERE routine_mode = _mode;

  IF NOT FOUND OR _status NOT IN ('replay', 'shadow')
     OR _evidence_version <> 'canonical-v2'
     OR _config_sha256 <> encode(extensions.digest(_config::text, 'sha256'), 'hex') THEN
    RETURN jsonb_build_object('published', 0, 'routine_mode', _mode);
  END IF;

  BEGIN
    _personal_min_samples := (_config #>> '{personal,min_samples}')::integer;
    _personal_min_dates := (_config #>> '{personal,min_support_dates}')::integer;
    _personal_min_span := (_config #>> '{personal,min_span_days}')::integer;
    _personal_max_age := (_config #>> '{personal,max_age_days}')::integer;
    _cohort_min_contributors := (_config #>> '{cohort,min_contributors}')::integer;
    _cohort_min_dates := (_config #>> '{cohort,min_support_dates}')::integer;
    _cohort_min_span := (_config #>> '{cohort,min_span_days}')::integer;
    _cohort_max_age := (_config #>> '{cohort,max_age_days}')::integer;
    _cohort_min_confidence := (_config #>> '{cohort,min_confidence}')::double precision;
    _floor := (_config #>> '{cohort,contribution_floor_minutes}')::integer;
    _ceiling := (_config #>> '{cohort,contribution_ceiling_minutes}')::integer;
    _algorithm := _config #>> '{cohort,algorithm}';
    _trim_fraction := (_config #>> '{cohort,trim_fraction}')::double precision;
  EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
    RETURN jsonb_build_object('published', 0, 'routine_mode', _mode);
  END;

  IF _personal_min_samples <= 0 OR _personal_min_dates <= 0 OR _personal_min_span <= 0 OR _personal_max_age <= 0
     OR _cohort_min_contributors <= 0 OR _cohort_min_dates <= 0 OR _cohort_min_span <= 0 OR _cohort_max_age <= 0
     OR _cohort_min_confidence <= 0 OR _cohort_min_confidence > 1
     OR _floor <= 0 OR _ceiling < _floor
     OR _algorithm NOT IN ('weighted_median', 'trimmed_mean')
     OR _trim_fraction < 0 OR _trim_fraction >= 0.5
     OR _config #>> '{cohort,confidence_formula_version}' <> 'cohort_support_min_v1' THEN
    RETURN jsonb_build_object('published', 0, 'routine_mode', _mode);
  END IF;

  DROP TABLE IF EXISTS pg_temp._routine_mode_cohort_build;
  CREATE TEMP TABLE _routine_mode_cohort_build ON COMMIT DROP AS
  SELECT
    greatest(_floor, least(_ceiling, p.neutral_p95_minutes))::integer AS neutral_minutes,
    greatest(0::double precision, least(1::double precision, p.confidence)) AS profile_confidence,
    p.distinct_support_dates,
    p.support_started_on,
    p.support_ended_on,
    (p.support_ended_on - p.support_started_on + 1)::integer AS support_span_days,
    p.latest_evidence_at
  FROM public.alert_gap_profiles AS p
  JOIN public.profiles AS owner_profile ON owner_profile.id = p.user_id
  WHERE p.version_id = _version_id
    AND p.context_key = 'personal_global'
    AND p.through_date = _through_date
    AND p.quality_state = 'valid'
    AND owner_profile.consent_data_sharing = true
    AND private.canonical_routine_mode(owner_profile.routine_pattern) = _mode
    AND p.sample_count >= _personal_min_samples
    AND p.distinct_support_dates >= _personal_min_dates
    AND p.support_ended_on - p.support_started_on + 1 >= _personal_min_span
    AND p.confidence >= _cohort_min_confidence
    AND p.latest_evidence_at + make_interval(days => _personal_max_age) > _cutoff;

  SELECT count(*)::integer,
         min(distinct_support_dates), min(support_span_days), min(support_started_on), max(support_ended_on),
         min(latest_evidence_at), max(latest_evidence_at), min(profile_confidence),
         string_agg(neutral_minutes::text || ':' || profile_confidence::text, ',' ORDER BY neutral_minutes, profile_confidence)
    INTO _count, _support_dates, _conservative_span_days, _support_started, _support_ended,
         _oldest_evidence, _latest_evidence, _minimum_confidence, _multiset
  FROM pg_temp._routine_mode_cohort_build;

  IF _count = 0 THEN
    DELETE FROM public.routine_mode_cohort_priors
    WHERE version_id = _version_id AND routine_mode = _mode
      AND context_key = 'personal_global' AND through_date = _through_date;
    RETURN jsonb_build_object('published', 0, 'routine_mode', _mode);
  END IF;

  _valid_until := least(
    _oldest_evidence + make_interval(days => _personal_max_age),
    _oldest_evidence + make_interval(days => _cohort_max_age)
  );

  IF _valid_until <= _cutoff THEN
    DELETE FROM public.routine_mode_cohort_priors
    WHERE version_id = _version_id AND routine_mode = _mode
      AND context_key = 'personal_global' AND through_date = _through_date;
    RETURN jsonb_build_object('published', 0, 'routine_mode', _mode);
  END IF;

  IF _algorithm = 'weighted_median' THEN
    SELECT neutral_minutes INTO _neutral
    FROM (
      SELECT neutral_minutes,
             sum(profile_confidence) OVER (ORDER BY neutral_minutes, profile_confidence ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_weight,
             sum(profile_confidence) OVER () AS total_weight
      FROM pg_temp._routine_mode_cohort_build
    ) AS weighted
    WHERE cumulative_weight >= total_weight / 2.0
    ORDER BY neutral_minutes, cumulative_weight
    LIMIT 1;
  ELSE
    SELECT ceil(avg(neutral_minutes)::numeric)::integer INTO _neutral
    FROM (
      SELECT neutral_minutes,
             row_number() OVER (ORDER BY neutral_minutes, profile_confidence) AS ordinal,
             count(*) OVER () AS total_count
      FROM pg_temp._routine_mode_cohort_build
    ) AS trimmed
    WHERE ordinal > floor(total_count * _trim_fraction)
      AND ordinal <= total_count - floor(total_count * _trim_fraction);
  END IF;

  _confidence := least(
    1::double precision,
    _count::double precision / _cohort_min_contributors::double precision,
    _support_dates::double precision / _cohort_min_dates::double precision,
    _conservative_span_days::double precision / _cohort_min_span::double precision,
    _minimum_confidence / _cohort_min_confidence
  );
  _quality := CASE
    WHEN _count >= _cohort_min_contributors
      AND _support_dates >= _cohort_min_dates
      AND _conservative_span_days >= _cohort_min_span
      AND _minimum_confidence >= _cohort_min_confidence
      THEN 'valid'
    ELSE 'low_support'
  END;

  _input_sha256 := encode(extensions.digest(concat_ws('|',
    _version_id::text, _config_sha256, _evidence_version, _through_date::text, _mode,
    _algorithm, _generation::text, _multiset, _count::text, _support_dates::text,
    _conservative_span_days::text, _support_started::text, _support_ended::text,
    _oldest_evidence::text, _latest_evidence::text, _valid_until::text, _cutoff::text
  ), 'sha256'), 'hex');
  _prior_sha256 := encode(extensions.digest(concat_ws('|',
    _input_sha256, _version_id::text, _mode, 'personal_global', _through_date::text,
    _count::text, _support_dates::text, _conservative_span_days::text, _support_started::text,
    _support_ended::text, _latest_evidence::text, _oldest_evidence::text, _valid_until::text,
    _neutral::text, _quality, _confidence::text, _minimum_confidence::text, _algorithm,
    _config_sha256, _evidence_version, _generation::text
  ), 'sha256'), 'hex');

  INSERT INTO public.routine_mode_cohort_priors AS target (
    version_id, routine_mode, context_key, through_date, contributor_count,
    distinct_support_dates, support_started_on, support_ended_on, latest_evidence_at,
    oldest_evidence_at, valid_until, conservative_span_days, minimum_profile_confidence,
    neutral_p95_minutes, quality_state, confidence,
    algorithm, config_sha256, evidence_version, source_generation, input_sha256, prior_sha256
  ) VALUES (
    _version_id, _mode, 'personal_global', _through_date, _count,
    _support_dates, _support_started, _support_ended, _latest_evidence,
    _oldest_evidence, _valid_until, _conservative_span_days, _minimum_confidence,
    _neutral, _quality, _confidence,
    _algorithm, _config_sha256, _evidence_version, _generation, _input_sha256, _prior_sha256
  )
  ON CONFLICT (version_id, routine_mode, context_key, through_date) DO UPDATE
  SET contributor_count = EXCLUDED.contributor_count,
      distinct_support_dates = EXCLUDED.distinct_support_dates,
      support_started_on = EXCLUDED.support_started_on,
      support_ended_on = EXCLUDED.support_ended_on,
      latest_evidence_at = EXCLUDED.latest_evidence_at,
      oldest_evidence_at = EXCLUDED.oldest_evidence_at,
      valid_until = EXCLUDED.valid_until,
      conservative_span_days = EXCLUDED.conservative_span_days,
      minimum_profile_confidence = EXCLUDED.minimum_profile_confidence,
      neutral_p95_minutes = EXCLUDED.neutral_p95_minutes,
      quality_state = EXCLUDED.quality_state,
      confidence = EXCLUDED.confidence,
      algorithm = EXCLUDED.algorithm,
      config_sha256 = EXCLUDED.config_sha256,
      evidence_version = EXCLUDED.evidence_version,
      source_generation = EXCLUDED.source_generation,
      input_sha256 = EXCLUDED.input_sha256,
      prior_sha256 = EXCLUDED.prior_sha256,
      published_at = CASE WHEN target.prior_sha256 = EXCLUDED.prior_sha256 THEN target.published_at ELSE clock_timestamp() END
  WHERE target.prior_sha256 IS DISTINCT FROM EXCLUDED.prior_sha256;
  GET DIAGNOSTICS _published = ROW_COUNT;

  RETURN jsonb_build_object('published', _published, 'routine_mode', _mode, 'quality_state', _quality);
END;
$$;

CREATE FUNCTION private.routine_mode_cohort_prior_is_valid(
  _version_id uuid,
  _routine_mode text,
  _through_date date,
  _evaluated_at timestamptz
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
SET TimeZone = 'UTC'
AS $$
DECLARE
  _prior public.routine_mode_cohort_priors%ROWTYPE;
  _config jsonb;
  _config_sha256 text;
  _evidence_version text;
  _status text;
  _generation bigint;
  _mode text := private.canonical_routine_mode(_routine_mode);
  _min_contributors integer;
  _min_dates integer;
  _min_span integer;
  _min_confidence double precision;
  _floor integer;
  _ceiling integer;
  _algorithm text;
  _expected_confidence double precision;
  _expected_quality text;
  _expected_sha text;
  _cutoff timestamptz;
BEGIN
  IF _version_id IS NULL OR _through_date IS NULL OR _evaluated_at IS NULL
     OR _mode NOT IN ('regular_9to5', 'semester_break', 'shift_irregular') THEN
    RETURN false;
  END IF;
  _cutoff := (_through_date + 1)::timestamptz;
  IF _evaluated_at < _cutoff THEN
    RETURN false;
  END IF;

  SELECT * INTO _prior
  FROM public.routine_mode_cohort_priors AS prior
  WHERE prior.version_id = _version_id
    AND prior.routine_mode = _mode
    AND prior.context_key = 'personal_global'
    AND prior.through_date = _through_date;
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  SELECT version.config, version.config_sha256, version.evidence_version, version.status, generation.generation
    INTO _config, _config_sha256, _evidence_version, _status, _generation
  FROM public.alert_model_versions AS version
  JOIN public.routine_mode_cohort_generations AS generation ON generation.routine_mode = _mode
  WHERE version.id = _version_id;
  IF NOT FOUND OR _status NOT IN ('replay', 'shadow')
     OR _evidence_version <> 'canonical-v2'
     OR _config_sha256 <> encode(extensions.digest(_config::text, 'sha256'), 'hex')
     OR _prior.config_sha256 <> _config_sha256
     OR _prior.evidence_version <> _evidence_version
     OR _prior.source_generation <> _generation
     OR _prior.valid_until IS NULL OR _prior.valid_until <= _cutoff
     OR _evaluated_at >= _prior.valid_until
     OR _prior.contributor_count <= 0 OR _prior.distinct_support_dates <= 0
     OR _prior.conservative_span_days IS NULL OR _prior.conservative_span_days <= 0
     OR _prior.minimum_profile_confidence IS NULL OR _prior.minimum_profile_confidence <= 0
     OR _prior.confidence < 0 OR _prior.confidence > 1 THEN
    RETURN false;
  END IF;

  BEGIN
    _min_contributors := (_config #>> '{cohort,min_contributors}')::integer;
    _min_dates := (_config #>> '{cohort,min_support_dates}')::integer;
    _min_span := (_config #>> '{cohort,min_span_days}')::integer;
    _min_confidence := (_config #>> '{cohort,min_confidence}')::double precision;
    _floor := (_config #>> '{cohort,contribution_floor_minutes}')::integer;
    _ceiling := (_config #>> '{cohort,contribution_ceiling_minutes}')::integer;
    _algorithm := _config #>> '{cohort,algorithm}';
  EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
    RETURN false;
  END;
  IF _min_contributors <= 0 OR _min_dates <= 0 OR _min_span <= 0
     OR _min_confidence <= 0 OR _min_confidence > 1
     OR _floor <= 0 OR _ceiling < _floor
     OR _algorithm NOT IN ('weighted_median', 'trimmed_mean')
     OR _config #>> '{cohort,confidence_formula_version}' <> 'cohort_support_min_v1'
     OR _prior.algorithm <> _algorithm THEN
    RETURN false;
  END IF;
  IF _prior.neutral_p95_minutes < _floor OR _prior.neutral_p95_minutes > _ceiling THEN
    RETURN false;
  END IF;

  _expected_confidence := least(
    1::double precision,
    _prior.contributor_count::double precision / _min_contributors::double precision,
    _prior.distinct_support_dates::double precision / _min_dates::double precision,
    _prior.conservative_span_days::double precision / _min_span::double precision,
    _prior.minimum_profile_confidence / _min_confidence
  );
  _expected_quality := CASE
    WHEN _prior.contributor_count >= _min_contributors
      AND _prior.distinct_support_dates >= _min_dates
      AND _prior.conservative_span_days >= _min_span
      AND _prior.minimum_profile_confidence >= _min_confidence
      THEN 'valid'
    ELSE 'low_support'
  END;
  IF _prior.quality_state <> _expected_quality
     OR _prior.confidence <> _expected_confidence
     OR _prior.quality_state <> 'valid' THEN
    RETURN false;
  END IF;

  _expected_sha := encode(extensions.digest(concat_ws('|',
    _prior.input_sha256, _prior.version_id::text, _prior.routine_mode, _prior.context_key,
    _prior.through_date::text, _prior.contributor_count::text, _prior.distinct_support_dates::text,
    _prior.conservative_span_days::text, _prior.support_started_on::text, _prior.support_ended_on::text,
    _prior.latest_evidence_at::text, _prior.oldest_evidence_at::text, _prior.valid_until::text,
    _prior.neutral_p95_minutes::text, _prior.quality_state, _prior.confidence::text,
    _prior.minimum_profile_confidence::text, _prior.algorithm, _prior.config_sha256,
    _prior.evidence_version, _prior.source_generation::text
  ), 'sha256'), 'hex');
  RETURN _prior.prior_sha256 = _expected_sha;
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION private.invalidate_routine_mode_cohort()
FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON FUNCTION private.invalidate_routine_mode_cohort_profile()
FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON FUNCTION private.rebuild_routine_mode_cohort_priors(uuid, date, text)
FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON FUNCTION private.routine_mode_cohort_prior_is_valid(uuid, text, date, timestamptz)
FROM PUBLIC, anon, authenticated, service_role;
