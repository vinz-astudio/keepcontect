-- ADR-0023 Task 4: provenance-qualified session and personal gap profiles only.
-- No scheduler, trigger, realtime publication, or live-alert mutation is introduced here.

ALTER TABLE public.alert_model_versions
  ADD CONSTRAINT alert_model_versions_gap_profile_contract_check CHECK (
    (
      jsonb_typeof(config #> '{sessionization,training_horizon_days}') = 'number'
      AND (config #>> '{sessionization,training_horizon_days}')::numeric > 0
      AND (config #>> '{sessionization,training_horizon_days}')::numeric = trunc((config #>> '{sessionization,training_horizon_days}')::numeric)
      AND jsonb_typeof(config #> '{sessionization,intervention_window_minutes}') = 'number'
      AND (config #>> '{sessionization,intervention_window_minutes}')::numeric >= 0
      AND (config #>> '{sessionization,intervention_window_minutes}')::numeric = trunc((config #>> '{sessionization,intervention_window_minutes}')::numeric)
      AND jsonb_typeof(config #> '{context,day_partition}') = 'string'
      AND config #>> '{context,day_partition}' IN ('all_days', 'weekday_weekend')
      AND jsonb_typeof(config #> '{context,hour_bucket_minutes}') = 'number'
      AND (config #>> '{context,hour_bucket_minutes}')::numeric > 0
      AND (config #>> '{context,hour_bucket_minutes}')::numeric = trunc((config #>> '{context,hour_bucket_minutes}')::numeric)
      AND mod(1440, (config #>> '{context,hour_bucket_minutes}')::integer) = 0
      AND jsonb_typeof(config #> '{personal,confidence_formula_version}') = 'string'
      AND config #>> '{personal,confidence_formula_version}' = 'support_ratio_v1'
    ) IS TRUE
  );

ALTER TABLE public.alert_gap_profiles
  ADD COLUMN input_sha256 text NOT NULL DEFAULT repeat('0', 64)
    CHECK (input_sha256 ~ '^[a-f0-9]{64}$');

CREATE TABLE public.alert_observation_coverage_intervals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  timezone text NOT NULL CHECK (length(trim(timezone)) > 0),
  utc_offset_minutes integer NOT NULL CHECK (utc_offset_minutes BETWEEN -840 AND 840),
  activity_coverage_state text NOT NULL CHECK (activity_coverage_state IN ('valid', 'outage', 'unknown')),
  intervention_coverage_state text NOT NULL CHECK (intervention_coverage_state IN ('valid', 'incomplete', 'unknown')),
  sleep_context_state text NOT NULL CHECK (sleep_context_state IN ('valid', 'incomplete', 'unknown')),
  captured_at timestamptz NOT NULL,
  finalized_at timestamptz,
  evidence_version text NOT NULL CHECK (length(trim(evidence_version)) > 0),
  provenance_sha256 text NOT NULL CHECK (provenance_sha256 ~ '^[a-f0-9]{64}$'),
  CHECK (ends_at > starts_at),
  CHECK (captured_at <= ends_at),
  CHECK (finalized_at IS NULL OR finalized_at >= ends_at)
);

CREATE INDEX alert_observation_coverage_intervals_version_user_time_idx
  ON public.alert_observation_coverage_intervals (version_id, user_id, starts_at, ends_at);

CREATE TABLE public.alert_intervention_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  occurred_at timestamptz NOT NULL,
  kind text NOT NULL CHECK (kind IN ('self_alert', 'self_prompt', 'checkin_prompt', 'concern_prompt')),
  captured_at timestamptz NOT NULL,
  evidence_version text NOT NULL CHECK (length(trim(evidence_version)) > 0),
  provenance_sha256 text NOT NULL CHECK (provenance_sha256 ~ '^[a-f0-9]{64}$'),
  CHECK (captured_at >= occurred_at)
);

CREATE INDEX alert_intervention_events_version_user_time_idx
  ON public.alert_intervention_events (version_id, user_id, occurred_at);

ALTER TABLE public.alert_observation_coverage_intervals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alert_intervention_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.alert_observation_coverage_intervals, public.alert_intervention_events
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.qualified_behavior_sessions(
  _user_id uuid,
  _from timestamptz,
  _to timestamptz,
  _version_id uuid
)
RETURNS TABLE (
  session_start timestamptz,
  session_end timestamptz,
  context_key text,
  evidence_count integer,
  quality_state text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _config jsonb;
  _status text;
  _evidence_version text;
  _config_sha256 text;
  _gap_minutes integer;
  _intervention_minutes integer;
  _definition text;
  _day_partition text;
  _bucket_minutes integer;
BEGIN
  IF _user_id IS NULL OR _version_id IS NULL OR _from IS NULL OR _to IS NULL OR _from >= _to THEN
    RETURN;
  END IF;

  SELECT config, status, evidence_version, config_sha256
    INTO _config, _status, _evidence_version, _config_sha256
  FROM public.alert_model_versions
  WHERE id = _version_id;

  IF NOT FOUND
     OR _status NOT IN ('replay', 'shadow')
     OR _evidence_version <> 'canonical-v2'
     OR _config_sha256 <> encode(extensions.digest(_config::text, 'sha256'), 'hex') THEN
    RETURN;
  END IF;

  BEGIN
    _gap_minutes := (_config #>> '{sessionization,gap_minutes}')::integer;
    _intervention_minutes := (_config #>> '{sessionization,intervention_window_minutes}')::integer;
    _definition := _config #>> '{context,definition_version}';
    _day_partition := _config #>> '{context,day_partition}';
    _bucket_minutes := (_config #>> '{context,hour_bucket_minutes}')::integer;
  EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
    RETURN;
  END;

  IF _gap_minutes <= 0 OR _intervention_minutes < 0 OR _definition IS NULL
     OR _day_partition NOT IN ('all_days', 'weekday_weekend')
     OR _bucket_minutes <= 0 OR mod(1440, _bucket_minutes) <> 0 THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH admitted AS (
    SELECT p.id, p.received_at, c.id AS coverage_id, c.timezone, c.utc_offset_minutes
    FROM public.behavior_pings AS p
    JOIN public.alert_observation_coverage_intervals AS c
      ON c.version_id = _version_id
     AND c.user_id = _user_id
     AND c.starts_at <= p.received_at
     AND c.ends_at > p.received_at
     AND c.activity_coverage_state = 'valid'
     AND c.intervention_coverage_state = 'valid'
     AND c.sleep_context_state = 'valid'
     AND c.evidence_version = 'canonical-v2'
     AND c.finalized_at IS NOT NULL
     AND c.finalized_at >= c.ends_at
     AND c.finalized_at < _to
    CROSS JOIN LATERAL (
      SELECT count(*) AS matching_coverage
      FROM public.alert_observation_coverage_intervals AS cc
      WHERE cc.version_id = _version_id
        AND cc.user_id = _user_id
        AND cc.starts_at <= p.received_at
        AND cc.ends_at > p.received_at
        AND cc.activity_coverage_state = 'valid'
        AND cc.intervention_coverage_state = 'valid'
        AND cc.sleep_context_state = 'valid'
        AND cc.evidence_version = 'canonical-v2'
        AND cc.finalized_at IS NOT NULL
        AND cc.finalized_at >= cc.ends_at
        AND cc.finalized_at < _to
    ) AS coverage_count
    WHERE p.user_id = _user_id
      AND p.ingest_version = 2
      AND p.received_at >= _from
      AND p.received_at < _to
      AND p.at < _to
      AND abs(extract(epoch FROM (p.received_at - p.at))) <= 300
      AND coverage_count.matching_coverage = 1
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names z WHERE z.name = c.timezone)
      AND floor(extract(epoch FROM (((p.received_at AT TIME ZONE c.timezone) AT TIME ZONE 'UTC') - p.received_at)) / 60)::integer = c.utc_offset_minutes
  ), marked AS (
    SELECT *, CASE WHEN lag(received_at) OVER (ORDER BY received_at, id) IS NULL
                       OR received_at - lag(received_at) OVER (ORDER BY received_at, id) > make_interval(mins => _gap_minutes)
                       OR coverage_id IS DISTINCT FROM lag(coverage_id) OVER (ORDER BY received_at, id)
                       OR timezone IS DISTINCT FROM lag(timezone) OVER (ORDER BY received_at, id)
                       OR utc_offset_minutes IS DISTINCT FROM lag(utc_offset_minutes) OVER (ORDER BY received_at, id)
                    THEN 1 ELSE 0 END AS starts_session
    FROM admitted
  ), grouped AS (
    SELECT *, sum(starts_session) OVER (ORDER BY received_at, id) AS session_no
    FROM marked
  ), summarized AS (
    SELECT min(received_at) AS session_start,
      max(received_at) AS session_end,
      (array_agg(timezone ORDER BY received_at, id))[1] AS timezone,
      count(*)::integer AS evidence_count
    FROM grouped
    GROUP BY session_no
  )
  SELECT s.session_start,
    s.session_end,
    concat(
      _definition, ':',
      CASE WHEN _day_partition = 'all_days' THEN 'all_days'
           WHEN extract(isodow FROM s.session_start AT TIME ZONE s.timezone) BETWEEN 1 AND 5 THEN 'weekday'
           ELSE 'weekend' END,
      ':h', lpad((floor(((extract(hour FROM s.session_start AT TIME ZONE s.timezone) * 60 + extract(minute FROM s.session_start AT TIME ZONE s.timezone)) / _bucket_minutes))::integer * _bucket_minutes)::text, 4, '0')
    )::text AS context_key,
    s.evidence_count,
    CASE WHEN EXISTS (
      SELECT 1 FROM public.alert_intervention_events AS i
      WHERE i.version_id = _version_id
        AND i.user_id = _user_id
        AND i.evidence_version = 'canonical-v2'
        AND i.occurred_at >= s.session_start - make_interval(mins => _intervention_minutes)
        AND i.occurred_at <= s.session_start
        AND i.captured_at < _to
    ) THEN 'intervention_excluded' ELSE 'valid' END::text AS quality_state
  FROM summarized AS s
  ORDER BY s.session_start;
END;
$$;

CREATE FUNCTION private.rebuild_alert_gap_profiles(
  _version_id uuid,
  _through_date date
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _config jsonb;
  _status text;
  _evidence_version text;
  _config_sha256 text;
  _horizon_days integer;
  _daily_cap integer;
  _min_samples integer;
  _min_dates integer;
  _min_span integer;
  _max_age integer;
  _cutoff timestamptz;
  _from timestamptz;
  _profiles_written integer := 0;
  _profiles_deleted integer := 0;
  _completed_gaps integer := 0;
BEGIN
  IF _version_id IS NULL OR _through_date IS NULL THEN
    RETURN jsonb_build_object('profiles_written', 0, 'profiles_deleted', 0, 'completed_gaps', 0, 'explicit_quiet_minutes', 0);
  END IF;

  SELECT config, status, evidence_version, config_sha256
    INTO _config, _status, _evidence_version, _config_sha256
  FROM public.alert_model_versions
  WHERE id = _version_id;

  IF NOT FOUND
     OR _status NOT IN ('replay', 'shadow')
     OR _evidence_version <> 'canonical-v2'
     OR _config_sha256 <> encode(extensions.digest(_config::text, 'sha256'), 'hex') THEN
    RETURN jsonb_build_object('profiles_written', 0, 'profiles_deleted', 0, 'completed_gaps', 0, 'explicit_quiet_minutes', 0);
  END IF;

  BEGIN
    _horizon_days := (_config #>> '{sessionization,training_horizon_days}')::integer;
    _daily_cap := (_config #>> '{sessionization,per_user_day_gap_cap}')::integer;
    _min_samples := (_config #>> '{personal,min_samples}')::integer;
    _min_dates := (_config #>> '{personal,min_support_dates}')::integer;
    _min_span := (_config #>> '{personal,min_span_days}')::integer;
    _max_age := (_config #>> '{personal,max_age_days}')::integer;
  EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
    RETURN jsonb_build_object('profiles_written', 0, 'profiles_deleted', 0, 'completed_gaps', 0, 'explicit_quiet_minutes', 0);
  END;

  IF _horizon_days <= 0 OR _daily_cap <= 0 OR _min_samples <= 0 OR _min_dates <= 0 OR _min_span <= 0 OR _max_age <= 0 THEN
    RETURN jsonb_build_object('profiles_written', 0, 'profiles_deleted', 0, 'completed_gaps', 0, 'explicit_quiet_minutes', 0);
  END IF;

  _cutoff := ((_through_date + 1)::timestamp AT TIME ZONE 'UTC');
  _from := _cutoff - make_interval(days => _horizon_days);
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(_version_id::text || ':' || _through_date::text, 0));
  DROP TABLE IF EXISTS pg_temp._alert_gap_profile_build;

  CREATE TEMP TABLE _alert_gap_profile_build ON COMMIT DROP AS
  WITH users AS (
    SELECT DISTINCT c.user_id
    FROM public.alert_observation_coverage_intervals AS c
    WHERE c.version_id = _version_id
      AND c.starts_at < _cutoff
      AND c.ends_at > _from
  ), sessions AS (
    SELECT u.user_id, s.*
    FROM users AS u
    CROSS JOIN LATERAL private.qualified_behavior_sessions(u.user_id, _from, _cutoff, _version_id) AS s
  ), paired AS (
    SELECT *, lead(session_start) OVER (PARTITION BY user_id ORDER BY session_start) AS next_start,
      lead(quality_state) OVER (PARTITION BY user_id ORDER BY session_start) AS next_quality
    FROM sessions
  ), coverage_gaps AS (
    SELECT p.user_id, p.session_end, p.next_start, p.context_key,
      c.timezone, c.utc_offset_minutes
    FROM paired AS p
    JOIN public.alert_observation_coverage_intervals AS c
      ON c.version_id = _version_id
     AND c.user_id = p.user_id
     AND c.starts_at <= p.session_end
     AND c.ends_at >= p.next_start
     AND c.activity_coverage_state = 'valid'
     AND c.intervention_coverage_state = 'valid'
     AND c.sleep_context_state = 'valid'
     AND c.evidence_version = 'canonical-v2'
     AND c.finalized_at IS NOT NULL
     AND c.finalized_at >= c.ends_at
     AND c.finalized_at < _cutoff
    CROSS JOIN LATERAL (
      SELECT count(*) AS matching_coverage
      FROM public.alert_observation_coverage_intervals AS cc
      WHERE cc.version_id = _version_id
        AND cc.user_id = p.user_id
        AND cc.starts_at <= p.session_end
        AND cc.ends_at >= p.next_start
        AND cc.activity_coverage_state = 'valid'
        AND cc.intervention_coverage_state = 'valid'
        AND cc.sleep_context_state = 'valid'
        AND cc.evidence_version = 'canonical-v2'
        AND cc.finalized_at IS NOT NULL
        AND cc.finalized_at >= cc.ends_at
        AND cc.finalized_at < _cutoff
    ) AS coverage_count
    WHERE p.next_start IS NOT NULL
      AND p.quality_state = 'valid'
      AND p.next_quality = 'valid'
      AND coverage_count.matching_coverage = 1
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names z WHERE z.name = c.timezone)
      AND floor(extract(epoch FROM (((p.session_end AT TIME ZONE c.timezone) AT TIME ZONE 'UTC') - p.session_end)) / 60)::integer = c.utc_offset_minutes
      AND NOT EXISTS (
        SELECT 1 FROM public.alert_intervention_events AS i
        WHERE i.version_id = _version_id
          AND i.user_id = p.user_id
          AND i.evidence_version = 'canonical-v2'
          AND i.occurred_at >= p.session_end
          AND i.occurred_at < p.next_start
          AND i.captured_at < _cutoff
      )
  ), effective AS (
    SELECT g.*,
      greatest(0::numeric, extract(epoch FROM (g.next_start - g.session_end)) - coalesce(sleep.sleep_seconds, 0))::double precision AS effective_seconds
    FROM coverage_gaps AS g
    CROSS JOIN LATERAL (
      SELECT coalesce(sum(extract(epoch FROM (upper(r) - lower(r)))), 0)::double precision AS sleep_seconds
      FROM (
        SELECT unnest(range_agg(tstzrange(greatest(si.starts_at, g.session_end), least(si.ends_at, g.next_start), '[)'))) AS r
        FROM private.candidate_sleep_intervals(g.user_id, g.session_end, g.next_start, _version_id) AS si
        WHERE si.starts_at < g.next_start AND si.ends_at > g.session_end
      ) AS merged
    ) AS sleep
  ), capped AS (
    SELECT *, (next_start AT TIME ZONE timezone)::date AS local_date,
      row_number() OVER (
        PARTITION BY user_id, (next_start AT TIME ZONE timezone)::date
        ORDER BY md5(_version_id::text || ':' || user_id::text || ':' || session_end::text || ':' || next_start::text)
      ) AS daily_rank
    FROM effective
    WHERE effective_seconds > 0
  ), selected AS (
    SELECT * FROM capped WHERE daily_rank <= _daily_cap
  ), grouped AS (
    SELECT user_id, 'personal_global'::text AS context_key, session_end, next_start, local_date, effective_seconds
    FROM selected
    UNION ALL
    SELECT user_id, context_key, session_end, next_start, local_date, effective_seconds
    FROM selected
  ), aggregate_inputs AS (
    SELECT user_id, context_key,
      count(*)::integer AS sample_count,
      count(DISTINCT local_date)::integer AS distinct_support_dates,
      min(local_date) AS support_started_on,
      max(local_date) AS support_ended_on,
      max(next_start) AS latest_evidence_at,
      ceil(percentile_disc(0.95) WITHIN GROUP (ORDER BY effective_seconds) / 60.0)::integer AS neutral_p95_minutes,
      jsonb_agg(jsonb_build_object('session_end', session_end, 'next_start', next_start, 'local_date', local_date, 'effective_seconds', effective_seconds) ORDER BY session_end, next_start) AS gap_inputs
    FROM grouped
    GROUP BY user_id, context_key
  ), hashes AS (
    SELECT a.*, encode(extensions.digest(jsonb_build_object(
      'version_id', _version_id, 'through_date', _through_date, 'config_sha256', _config_sha256,
      'evidence_version', _evidence_version, 'context_key', context_key, 'gaps', gap_inputs
    )::text, 'sha256'), 'hex') AS input_sha256
    FROM aggregate_inputs AS a
  ), prepared AS (
    SELECT h.*,
      CASE WHEN h.latest_evidence_at < _cutoff - make_interval(days => _max_age) THEN 'stale'
           WHEN h.sample_count >= _min_samples AND h.distinct_support_dates >= _min_dates
             AND (h.support_ended_on - h.support_started_on + 1) >= _min_span THEN 'valid'
           ELSE 'low_support' END::text AS quality_state,
      CASE WHEN h.latest_evidence_at < _cutoff - make_interval(days => _max_age) THEN 0::double precision
           ELSE least(1::double precision,
             h.sample_count::double precision / _min_samples::double precision,
             h.distinct_support_dates::double precision / _min_dates::double precision,
             (h.support_ended_on - h.support_started_on + 1)::double precision / _min_span::double precision)
      END AS confidence
    FROM hashes AS h
  )
  SELECT p.user_id, p.context_key, _through_date AS through_date, p.neutral_p95_minutes,
    p.sample_count, p.distinct_support_dates, p.support_started_on, p.support_ended_on,
    p.latest_evidence_at, p.quality_state, p.confidence, p.input_sha256,
    encode(extensions.digest(jsonb_build_object(
      'version_id', _version_id, 'user_id', p.user_id, 'context_key', p.context_key,
      'through_date', _through_date, 'neutral_p95_minutes', p.neutral_p95_minutes,
      'sample_count', p.sample_count, 'distinct_support_dates', p.distinct_support_dates,
      'support_started_on', p.support_started_on, 'support_ended_on', p.support_ended_on,
      'latest_evidence_at', p.latest_evidence_at, 'quality_state', p.quality_state,
      'confidence', p.confidence, 'input_sha256', p.input_sha256
    )::text, 'sha256'), 'hex') AS profile_sha256
  FROM prepared AS p;

  SELECT coalesce(sum(sample_count) FILTER (WHERE context_key = 'personal_global'), 0)::integer
    INTO _completed_gaps
  FROM pg_temp._alert_gap_profile_build;

  INSERT INTO public.alert_gap_profiles AS target (
    version_id, user_id, context_key, through_date, neutral_p95_minutes, sample_count,
    distinct_support_dates, support_started_on, support_ended_on, latest_evidence_at,
    quality_state, confidence, profile_sha256, input_sha256
  )
  SELECT _version_id, user_id, context_key, through_date, neutral_p95_minutes, sample_count,
    distinct_support_dates, support_started_on, support_ended_on, latest_evidence_at,
    quality_state, confidence, profile_sha256, input_sha256
  FROM pg_temp._alert_gap_profile_build
  ON CONFLICT (version_id, user_id, context_key, through_date) DO UPDATE
  SET neutral_p95_minutes = EXCLUDED.neutral_p95_minutes,
      sample_count = EXCLUDED.sample_count,
      distinct_support_dates = EXCLUDED.distinct_support_dates,
      support_started_on = EXCLUDED.support_started_on,
      support_ended_on = EXCLUDED.support_ended_on,
      latest_evidence_at = EXCLUDED.latest_evidence_at,
      quality_state = EXCLUDED.quality_state,
      confidence = EXCLUDED.confidence,
      profile_sha256 = EXCLUDED.profile_sha256,
      input_sha256 = EXCLUDED.input_sha256
  WHERE target.input_sha256 IS DISTINCT FROM EXCLUDED.input_sha256
     OR target.profile_sha256 IS DISTINCT FROM EXCLUDED.profile_sha256;
  GET DIAGNOSTICS _profiles_written = ROW_COUNT;

  DELETE FROM public.alert_gap_profiles AS target
  WHERE target.version_id = _version_id
    AND target.through_date = _through_date
    AND NOT EXISTS (
      SELECT 1 FROM pg_temp._alert_gap_profile_build AS b
      WHERE b.user_id = target.user_id AND b.context_key = target.context_key
    );
  GET DIAGNOSTICS _profiles_deleted = ROW_COUNT;

  RETURN jsonb_build_object(
    'profiles_written', _profiles_written,
    'profiles_deleted', _profiles_deleted,
    'completed_gaps', _completed_gaps,
    'explicit_quiet_minutes', 0
  );
END;
$$;

REVOKE ALL ON FUNCTION private.qualified_behavior_sessions(uuid, timestamptz, timestamptz, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.rebuild_alert_gap_profiles(uuid, date)
  FROM PUBLIC, anon, authenticated, service_role;
