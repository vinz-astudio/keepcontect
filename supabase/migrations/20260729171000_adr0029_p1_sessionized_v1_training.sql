-- ADR-0029 P1: admit legacy ingest-version 1 history to shadow/replay
-- profile training through an explicit, auditable sessionized evidence source.
-- Historical rows remain training-only: no trigger, scheduler, source rewrite,
-- realtime side effect, alert resolution, or heartbeat mutation is introduced.

ALTER TABLE public.alert_model_versions
  ADD CONSTRAINT alert_model_versions_historical_v1_policy_check CHECK (
    (
      config #> '{sessionization,historical_v1_policy}' IS NULL
      OR (
        jsonb_typeof(
          config #> '{sessionization,historical_v1_policy}'
        ) = 'string'
        AND config #>> '{sessionization,historical_v1_policy}' IN (
          'disabled',
          'sessionized_training_only_v1'
        )
      )
    ) IS TRUE
  );

CREATE FUNCTION private.normalized_behavior_training_sessions(
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
  source_ingest_version smallint,
  training_provenance text,
  provenance_sha256 text,
  quality_state text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
SET TimeZone = 'UTC'
AS $$
DECLARE
  _config jsonb;
  _status text;
  _evidence_version text;
  _config_sha256 text;
  _gap_minutes integer;
  _historical_v1_policy text;
BEGIN
  IF _user_id IS NULL
     OR _version_id IS NULL
     OR _from IS NULL
     OR _to IS NULL
     OR _from >= _to THEN
    RETURN;
  END IF;

  SELECT config, status, evidence_version, config_sha256
    INTO _config, _status, _evidence_version, _config_sha256
  FROM public.alert_model_versions
  WHERE id = _version_id;

  IF NOT FOUND
     OR _status NOT IN ('replay', 'shadow')
     OR _evidence_version <> 'canonical-v2'
     OR _config_sha256
       <> encode(extensions.digest(_config::text, 'sha256'), 'hex') THEN
    RETURN;
  END IF;

  BEGIN
    _gap_minutes :=
      (_config #>> '{sessionization,gap_minutes}')::integer;
    _historical_v1_policy := coalesce(
      _config #>> '{sessionization,historical_v1_policy}',
      'disabled'
    );
  EXCEPTION
    WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      RETURN;
  END;

  IF _gap_minutes <= 0
     OR _historical_v1_policy NOT IN (
       'disabled',
       'sessionized_training_only_v1'
     ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH canonical AS (
    SELECT
      s.session_start,
      s.session_end,
      s.context_key,
      s.evidence_count,
      2::smallint AS source_ingest_version,
      'canonical_v2'::text AS training_provenance,
      encode(
        extensions.digest(
          jsonb_build_object(
            'version_id', _version_id,
            'config_sha256', _config_sha256,
            'source_ingest_version', 2,
            'training_provenance', 'canonical_v2',
            'session_start_utc',
              to_char(
                s.session_start AT TIME ZONE 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
              ),
            'session_end_utc',
              to_char(
                s.session_end AT TIME ZONE 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
              ),
            'context_key', s.context_key,
            'evidence_count', s.evidence_count,
            'quality_state', s.quality_state
          )::text,
          'sha256'
        ),
        'hex'
      ) AS provenance_sha256,
      s.quality_state
    FROM private.qualified_behavior_sessions(
      _user_id,
      _from,
      _to,
      _version_id
    ) AS s
  ),
  historical_admitted AS (
    SELECT
      p.id,
      p.at,
      p.kind,
      p.source,
      p.received_at,
      p.event_id,
      p.ingest_version
    FROM public.behavior_pings AS p
    WHERE _historical_v1_policy = 'sessionized_training_only_v1'
      AND p.user_id = _user_id
      AND p.ingest_version = 1
      AND p.at >= _from
      AND p.at < _to
  ),
  historical_marked AS (
    SELECT
      a.*,
      CASE
        WHEN lag(a.at) OVER (ORDER BY a.at, a.id) IS NULL
          OR a.at - lag(a.at) OVER (ORDER BY a.at, a.id)
            > make_interval(mins => _gap_minutes)
          THEN 1
        ELSE 0
      END AS starts_session
    FROM historical_admitted AS a
  ),
  historical_grouped AS (
    SELECT
      m.*,
      sum(m.starts_session) OVER (ORDER BY m.at, m.id) AS session_no
    FROM historical_marked AS m
  ),
  historical_summarized AS (
    SELECT
      min(g.at) AS session_start,
      max(g.at) AS session_end,
      count(*)::integer AS evidence_count,
      jsonb_agg(
        jsonb_build_object(
          'id', g.id,
          'at_utc',
            to_char(
              g.at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
          'kind', g.kind,
          'source', g.source,
          'received_at_utc',
            to_char(
              g.received_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
          'event_id', g.event_id,
          'ingest_version', g.ingest_version
        )
        ORDER BY g.at, g.id
      ) AS source_rows
    FROM historical_grouped AS g
    GROUP BY g.session_no
  ),
  historical AS (
    SELECT
      s.session_start,
      s.session_end,
      NULL::text AS context_key,
      s.evidence_count,
      1::smallint AS source_ingest_version,
      'historical_v1_training_only'::text AS training_provenance,
      encode(
        extensions.digest(
          jsonb_build_object(
            'version_id', _version_id,
            'config_sha256', _config_sha256,
            'source_ingest_version', 1,
            'training_provenance', 'historical_v1_training_only',
            'source_rows', s.source_rows
          )::text,
          'sha256'
        ),
        'hex'
      ) AS provenance_sha256,
      'valid'::text AS quality_state
    FROM historical_summarized AS s
  )
  SELECT * FROM canonical
  UNION ALL
  SELECT * FROM historical
  ORDER BY session_start, source_ingest_version;
END;
$$;

CREATE OR REPLACE FUNCTION private.rebuild_alert_gap_profiles(
  _version_id uuid,
  _through_date date
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
  _status text;
  _evidence_version text;
  _config_sha256 text;
  _historical_v1_policy text;
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
    RETURN jsonb_build_object(
      'profiles_written', 0,
      'profiles_deleted', 0,
      'completed_gaps', 0,
      'explicit_quiet_minutes', 0
    );
  END IF;

  SELECT config, status, evidence_version, config_sha256
    INTO _config, _status, _evidence_version, _config_sha256
  FROM public.alert_model_versions
  WHERE id = _version_id;

  IF NOT FOUND
     OR _status NOT IN ('replay', 'shadow')
     OR _evidence_version <> 'canonical-v2'
     OR _config_sha256
       <> encode(extensions.digest(_config::text, 'sha256'), 'hex') THEN
    RETURN jsonb_build_object(
      'profiles_written', 0,
      'profiles_deleted', 0,
      'completed_gaps', 0,
      'explicit_quiet_minutes', 0
    );
  END IF;

  BEGIN
    _historical_v1_policy := coalesce(
      _config #>> '{sessionization,historical_v1_policy}',
      'disabled'
    );
    _horizon_days :=
      (_config #>> '{sessionization,training_horizon_days}')::integer;
    _daily_cap :=
      (_config #>> '{sessionization,per_user_day_gap_cap}')::integer;
    _min_samples := (_config #>> '{personal,min_samples}')::integer;
    _min_dates := (_config #>> '{personal,min_support_dates}')::integer;
    _min_span := (_config #>> '{personal,min_span_days}')::integer;
    _max_age := (_config #>> '{personal,max_age_days}')::integer;
  EXCEPTION
    WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      RETURN jsonb_build_object(
        'profiles_written', 0,
        'profiles_deleted', 0,
        'completed_gaps', 0,
        'explicit_quiet_minutes', 0
      );
  END;

  IF _historical_v1_policy NOT IN (
       'disabled',
       'sessionized_training_only_v1'
     )
     OR _horizon_days <= 0
     OR _daily_cap <= 0
     OR _min_samples <= 0
     OR _min_dates <= 0
     OR _min_span <= 0
     OR _max_age <= 0 THEN
    RETURN jsonb_build_object(
      'profiles_written', 0,
      'profiles_deleted', 0,
      'completed_gaps', 0,
      'explicit_quiet_minutes', 0
    );
  END IF;

  _cutoff := ((_through_date + 1)::timestamp AT TIME ZONE 'UTC');
  _from := _cutoff - make_interval(days => _horizon_days);

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      _version_id::text || ':' || _through_date::text,
      0
    )
  );

  DROP TABLE IF EXISTS pg_temp._alert_gap_profile_build;

  CREATE TEMP TABLE _alert_gap_profile_build ON COMMIT DROP AS
  WITH users AS (
    SELECT DISTINCT c.user_id
    FROM public.alert_observation_coverage_intervals AS c
    WHERE c.version_id = _version_id
      AND c.starts_at < _cutoff
      AND c.ends_at > _from
    UNION
    SELECT DISTINCT p.user_id
    FROM public.behavior_pings AS p
    WHERE _historical_v1_policy = 'sessionized_training_only_v1'
      AND p.ingest_version = 1
      AND p.at >= _from
      AND p.at < _cutoff
  ),
  sessions AS (
    SELECT
      u.user_id,
      s.*
    FROM users AS u
    CROSS JOIN LATERAL private.normalized_behavior_training_sessions(
      u.user_id,
      _from,
      _cutoff,
      _version_id
    ) AS s
  ),
  paired AS (
    SELECT
      s.*,
      lead(s.session_start) OVER (
        PARTITION BY
          s.user_id,
          s.source_ingest_version,
          s.training_provenance
        ORDER BY s.session_start
      ) AS next_start,
      lead(s.quality_state) OVER (
        PARTITION BY
          s.user_id,
          s.source_ingest_version,
          s.training_provenance
        ORDER BY s.session_start
      ) AS next_quality,
      lead(s.provenance_sha256) OVER (
        PARTITION BY
          s.user_id,
          s.source_ingest_version,
          s.training_provenance
        ORDER BY s.session_start
      ) AS next_session_provenance_sha256
    FROM sessions AS s
  ),
  coverage_gaps AS (
    SELECT
      p.user_id,
      p.session_end,
      p.next_start,
      p.context_key,
      c.id AS coverage_id,
      c.timezone,
      c.utc_offset_minutes,
      c.provenance_sha256 AS coverage_provenance_sha256,
      p.source_ingest_version,
      p.training_provenance,
      p.provenance_sha256 AS session_provenance_sha256,
      p.next_session_provenance_sha256
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
    WHERE p.source_ingest_version = 2
      AND p.next_start IS NOT NULL
      AND p.quality_state = 'valid'
      AND p.next_quality = 'valid'
      AND coverage_count.matching_coverage = 1
      AND EXISTS (
        SELECT 1
        FROM pg_catalog.pg_timezone_names z
        WHERE z.name = c.timezone
      )
      AND floor(
        extract(
          epoch FROM (
            (
              (p.session_end AT TIME ZONE c.timezone)
              AT TIME ZONE 'UTC'
            ) - p.session_end
          )
        ) / 60
      )::integer = c.utc_offset_minutes
      AND NOT EXISTS (
        SELECT 1
        FROM public.alert_intervention_events AS i
        WHERE i.version_id = _version_id
          AND i.user_id = p.user_id
          AND i.evidence_version = 'canonical-v2'
          AND i.occurred_at >= p.session_end
          AND i.occurred_at < p.next_start
          AND i.captured_at < _cutoff
      )
  ),
  canonical_effective AS (
    SELECT
      g.*,
      greatest(
        0::numeric,
        extract(epoch FROM (g.next_start - g.session_end))
          - coalesce(sleep.sleep_seconds, 0)
      )::double precision AS effective_seconds,
      sleep.sleep_provenance_sha256
    FROM coverage_gaps AS g
    CROSS JOIN LATERAL (
      WITH raw_sleep AS (
        SELECT
          si.starts_at,
          si.ends_at,
          si.basis,
          si.confidence,
          si.provenance,
          tstzrange(
            greatest(si.starts_at, g.session_end),
            least(si.ends_at, g.next_start),
            '[)'
          ) AS clipped_range
        FROM private.candidate_sleep_intervals(
          g.user_id,
          g.session_end,
          g.next_start,
          _version_id
        ) AS si
        WHERE si.starts_at < g.next_start
          AND si.ends_at > g.session_end
      ),
      merged AS (
        SELECT unnest(range_agg(clipped_range)) AS r
        FROM raw_sleep
      )
      SELECT
        coalesce(
          (
            SELECT sum(extract(epoch FROM (upper(r) - lower(r))))
            FROM merged
          ),
          0
        )::double precision AS sleep_seconds,
        encode(
          extensions.digest(
            coalesce(
              (
                SELECT jsonb_agg(
                  jsonb_build_object(
                    'starts_at_utc',
                      to_char(
                        starts_at AT TIME ZONE 'UTC',
                        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
                      ),
                    'ends_at_utc',
                      to_char(
                        ends_at AT TIME ZONE 'UTC',
                        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
                      ),
                    'basis', basis,
                    'confidence', confidence,
                    'provenance', provenance
                  )
                  ORDER BY
                    starts_at,
                    ends_at,
                    basis,
                    confidence,
                    provenance::text
                )
                FROM raw_sleep
              ),
              '[]'::jsonb
            )::text,
            'sha256'
          ),
          'hex'
        ) AS sleep_provenance_sha256
    ) AS sleep
  ),
  historical_effective AS (
    SELECT
      p.user_id,
      p.session_end,
      p.next_start,
      p.context_key,
      NULL::uuid AS coverage_id,
      'UTC'::text AS timezone,
      0::integer AS utc_offset_minutes,
      NULL::text AS coverage_provenance_sha256,
      p.source_ingest_version,
      p.training_provenance,
      p.provenance_sha256 AS session_provenance_sha256,
      p.next_session_provenance_sha256,
      extract(
        epoch FROM (p.next_start - p.session_end)
      )::double precision AS effective_seconds,
      NULL::text AS sleep_provenance_sha256
    FROM paired AS p
    WHERE p.source_ingest_version = 1
      AND p.training_provenance = 'historical_v1_training_only'
      AND p.next_start IS NOT NULL
      AND p.quality_state = 'valid'
      AND p.next_quality = 'valid'
  ),
  effective AS (
    SELECT * FROM canonical_effective
    UNION ALL
    SELECT * FROM historical_effective
  ),
  capped AS (
    SELECT
      e.*,
      (e.next_start AT TIME ZONE e.timezone)::date AS local_date,
      row_number() OVER (
        PARTITION BY
          e.user_id,
          (e.next_start AT TIME ZONE e.timezone)::date
        ORDER BY md5(
          _version_id::text || ':' || e.user_id::text || ':'
          || to_char(
            e.session_end AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
          ) || ':'
          || to_char(
            e.next_start AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
          )
        )
      ) AS daily_rank
    FROM effective AS e
    WHERE e.effective_seconds > 0
  ),
  selected AS (
    SELECT *
    FROM capped
    WHERE daily_rank <= _daily_cap
  ),
  grouped AS (
    SELECT
      user_id,
      'personal_global'::text AS context_key,
      session_end,
      next_start,
      local_date,
      effective_seconds,
      coverage_id,
      timezone,
      utc_offset_minutes,
      coverage_provenance_sha256,
      sleep_provenance_sha256,
      source_ingest_version,
      training_provenance,
      session_provenance_sha256,
      next_session_provenance_sha256
    FROM selected
    UNION ALL
    SELECT
      user_id,
      context_key,
      session_end,
      next_start,
      local_date,
      effective_seconds,
      coverage_id,
      timezone,
      utc_offset_minutes,
      coverage_provenance_sha256,
      sleep_provenance_sha256,
      source_ingest_version,
      training_provenance,
      session_provenance_sha256,
      next_session_provenance_sha256
    FROM selected
    WHERE context_key IS NOT NULL
  ),
  aggregate_inputs AS (
    SELECT
      user_id,
      context_key,
      count(*)::integer AS sample_count,
      count(DISTINCT local_date)::integer AS distinct_support_dates,
      min(local_date) AS support_started_on,
      max(local_date) AS support_ended_on,
      max(next_start) AS latest_evidence_at,
      ceil(
        percentile_disc(0.95)
          WITHIN GROUP (ORDER BY effective_seconds) / 60.0
      )::integer AS neutral_p95_minutes,
      jsonb_agg(
        jsonb_build_object(
          'session_end_utc',
            to_char(
              session_end AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
          'next_start_utc',
            to_char(
              next_start AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
          'local_date', local_date,
          'effective_seconds', effective_seconds,
          'coverage_id', coverage_id,
          'coverage_timezone', timezone,
          'coverage_utc_offset_minutes', utc_offset_minutes,
          'coverage_provenance_sha256', coverage_provenance_sha256,
          'sleep_provenance_sha256', sleep_provenance_sha256,
          'source_ingest_version', source_ingest_version,
          'training_provenance', training_provenance,
          'session_provenance_sha256', session_provenance_sha256,
          'next_session_provenance_sha256',
            next_session_provenance_sha256
        )
        ORDER BY
          session_end,
          next_start,
          source_ingest_version,
          session_provenance_sha256
      ) AS gap_inputs
    FROM grouped
    GROUP BY user_id, context_key
  ),
  hashes AS (
    SELECT
      a.*,
      encode(
        extensions.digest(
          jsonb_build_object(
            'version_id', _version_id,
            'through_date', _through_date,
            'config_sha256', _config_sha256,
            'evidence_version', _evidence_version,
            'context_key', context_key,
            'gaps', gap_inputs
          )::text,
          'sha256'
        ),
        'hex'
      ) AS input_sha256
    FROM aggregate_inputs AS a
  ),
  prepared AS (
    SELECT
      h.*,
      CASE
        WHEN h.latest_evidence_at
          < _cutoff - make_interval(days => _max_age)
          THEN 'stale'
        WHEN h.sample_count >= _min_samples
          AND h.distinct_support_dates >= _min_dates
          AND (
            h.support_ended_on - h.support_started_on + 1
          ) >= _min_span
          THEN 'valid'
        ELSE 'low_support'
      END::text AS quality_state,
      CASE
        WHEN h.latest_evidence_at
          < _cutoff - make_interval(days => _max_age)
          THEN 0::double precision
        ELSE least(
          1::double precision,
          h.sample_count::double precision
            / _min_samples::double precision,
          h.distinct_support_dates::double precision
            / _min_dates::double precision,
          (h.support_ended_on - h.support_started_on + 1)::double precision
            / _min_span::double precision
        )
      END AS confidence
    FROM hashes AS h
  )
  SELECT
    p.user_id,
    p.context_key,
    _through_date AS through_date,
    p.neutral_p95_minutes,
    p.sample_count,
    p.distinct_support_dates,
    p.support_started_on,
    p.support_ended_on,
    p.latest_evidence_at,
    p.quality_state,
    p.confidence,
    p.input_sha256,
    encode(
      extensions.digest(
        jsonb_build_object(
          'version_id', _version_id,
          'user_id', p.user_id,
          'context_key', p.context_key,
          'through_date', _through_date,
          'neutral_p95_minutes', p.neutral_p95_minutes,
          'sample_count', p.sample_count,
          'distinct_support_dates', p.distinct_support_dates,
          'support_started_on', p.support_started_on,
          'support_ended_on', p.support_ended_on,
          'latest_evidence_at_utc',
            to_char(
              p.latest_evidence_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
          'quality_state', p.quality_state,
          'confidence', p.confidence,
          'input_sha256', p.input_sha256
        )::text,
        'sha256'
      ),
      'hex'
    ) AS profile_sha256
  FROM prepared AS p;

  SELECT coalesce(
    sum(sample_count) FILTER (WHERE context_key = 'personal_global'),
    0
  )::integer
    INTO _completed_gaps
  FROM pg_temp._alert_gap_profile_build;

  INSERT INTO public.alert_gap_profiles AS target (
    version_id,
    user_id,
    context_key,
    through_date,
    neutral_p95_minutes,
    sample_count,
    distinct_support_dates,
    support_started_on,
    support_ended_on,
    latest_evidence_at,
    quality_state,
    confidence,
    profile_sha256,
    input_sha256
  )
  SELECT
    _version_id,
    user_id,
    context_key,
    through_date,
    neutral_p95_minutes,
    sample_count,
    distinct_support_dates,
    support_started_on,
    support_ended_on,
    latest_evidence_at,
    quality_state,
    confidence,
    profile_sha256,
    input_sha256
  FROM pg_temp._alert_gap_profile_build
  ON CONFLICT (
    version_id,
    user_id,
    context_key,
    through_date
  ) DO UPDATE
  SET
    neutral_p95_minutes = EXCLUDED.neutral_p95_minutes,
    sample_count = EXCLUDED.sample_count,
    distinct_support_dates = EXCLUDED.distinct_support_dates,
    support_started_on = EXCLUDED.support_started_on,
    support_ended_on = EXCLUDED.support_ended_on,
    latest_evidence_at = EXCLUDED.latest_evidence_at,
    quality_state = EXCLUDED.quality_state,
    confidence = EXCLUDED.confidence,
    profile_sha256 = EXCLUDED.profile_sha256,
    input_sha256 = EXCLUDED.input_sha256,
    computed_at = clock_timestamp()
  WHERE target.input_sha256 IS DISTINCT FROM EXCLUDED.input_sha256
     OR target.profile_sha256 IS DISTINCT FROM EXCLUDED.profile_sha256;

  GET DIAGNOSTICS _profiles_written = ROW_COUNT;

  DELETE FROM public.alert_gap_profiles AS target
  WHERE target.version_id = _version_id
    AND target.through_date = _through_date
    AND NOT EXISTS (
      SELECT 1
      FROM pg_temp._alert_gap_profile_build AS b
      WHERE b.user_id = target.user_id
        AND b.context_key = target.context_key
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

REVOKE ALL ON FUNCTION private.normalized_behavior_training_sessions(
  uuid,
  timestamptz,
  timestamptz,
  uuid
) FROM PUBLIC, anon, authenticated, service_role;
