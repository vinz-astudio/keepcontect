-- ADR-0023 Task 3: persisted, prospective sleep-anchor contexts only.
-- This migration deliberately creates no capture scheduler and touches no live alert state.

ALTER TABLE public.alert_model_versions
  ADD CONSTRAINT alert_model_versions_sleep_compensation_late_evidence_check CHECK (
    (
    jsonb_typeof(config #> '{sleep_compensation,lookback_nights}') = 'number'
    AND (config #>> '{sleep_compensation,lookback_nights}')::numeric > 0
    AND (config #>> '{sleep_compensation,lookback_nights}')::numeric = trunc((config #>> '{sleep_compensation,lookback_nights}')::numeric)
    AND jsonb_typeof(config #> '{sleep_compensation,min_late_events_per_night}') = 'number'
    AND (config #>> '{sleep_compensation,min_late_events_per_night}')::numeric > 0
    AND (config #>> '{sleep_compensation,min_late_events_per_night}')::numeric = trunc((config #>> '{sleep_compensation,min_late_events_per_night}')::numeric)
    AND (config #>> '{sleep_compensation,min_positive_nights}')::numeric
      <= (config #>> '{sleep_compensation,lookback_nights}')::numeric
    ) IS TRUE
  );

CREATE TABLE public.alert_sleep_night_contexts (
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  anchor_date date NOT NULL,
  timezone text NOT NULL CHECK (length(trim(timezone)) > 0),
  sleep_start_local time NOT NULL,
  sleep_end_local time NOT NULL,
  anchor_starts_at timestamptz NOT NULL,
  anchor_ends_at timestamptz NOT NULL,
  utc_offset_minutes integer NOT NULL CHECK (utc_offset_minutes BETWEEN -840 AND 840),
  coverage_state text NOT NULL CHECK (coverage_state IN ('valid', 'outage', 'unknown')),
  captured_at timestamptz NOT NULL,
  finalized_at timestamptz,
  evidence_version text NOT NULL CHECK (length(trim(evidence_version)) > 0),
  provenance_sha256 text NOT NULL CHECK (provenance_sha256 ~ '^[a-f0-9]{64}$'),
  PRIMARY KEY (version_id, user_id, anchor_date),
  CHECK (sleep_start_local <> sleep_end_local),
  CHECK (anchor_ends_at > anchor_starts_at),
  CHECK (captured_at <= anchor_starts_at),
  CHECK (
    coverage_state = 'unknown'
    OR (finalized_at IS NOT NULL AND finalized_at >= anchor_ends_at)
  )
);

ALTER TABLE public.alert_sleep_night_contexts ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.alert_sleep_night_contexts
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.candidate_sleep_intervals(
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
  IF _user_id IS NULL OR _version_id IS NULL OR _from IS NULL OR _to IS NULL OR _from >= _to THEN
    RETURN;
  END IF;

  SELECT v.config, v.config_sha256, v.status, v.evidence_version
    INTO _config, _config_sha256, _status, _evidence_version
  FROM public.alert_model_versions AS v
  WHERE v.id = _version_id;

  IF NOT FOUND
     OR _status NOT IN ('replay', 'shadow')
     OR _evidence_version <> 'canonical-v2'
     OR _config_sha256 <> encode(extensions.digest(_config::text, 'sha256'), 'hex') THEN
    RETURN;
  END IF;

  BEGIN
    _max_start_delay := (_config #>> '{sleep_compensation,max_start_delay_minutes}')::integer;
    _max_wake_advance := (_config #>> '{sleep_compensation,max_wake_advance_minutes}')::integer;
    _max_wake_delay := (_config #>> '{sleep_compensation,max_wake_delay_minutes}')::integer;
    _max_update_per_day := (_config #>> '{sleep_compensation,max_update_minutes_per_day}')::integer;
    _min_positive := (_config #>> '{sleep_compensation,min_positive_nights}')::integer;
    _lookback := (_config #>> '{sleep_compensation,lookback_nights}')::integer;
    _min_late_events := (_config #>> '{sleep_compensation,min_late_events_per_night}')::integer;
    _timezone_tolerance := (_config #>> '{sleep_compensation,timezone_tolerance_minutes}')::integer;
  EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
    RETURN;
  END;

  IF _max_start_delay < 0 OR _max_wake_advance < 0 OR _max_wake_delay < 0
     OR _max_update_per_day < 0 OR _min_positive <= 0 OR _lookback <= 0
     OR _min_late_events <= 0 OR _min_positive > _lookback OR _timezone_tolerance < 0 THEN
    RETURN;
  END IF;

  FOR _context IN
    SELECT c.*
    FROM public.alert_sleep_night_contexts AS c
    WHERE c.version_id = _version_id
      AND c.user_id = _user_id
      AND c.evidence_version = 'canonical-v2'
      AND c.anchor_starts_at < _to
      AND c.anchor_ends_at > _from
    ORDER BY c.anchor_starts_at
  LOOP
    -- A malformed or incompatible persisted context is not a reason to infer a window.
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names AS z WHERE z.name = _context.timezone)
       OR _context.sleep_start_local = _context.sleep_end_local
       OR _context.anchor_ends_at <= _context.anchor_starts_at
       OR _context.captured_at > _context.anchor_starts_at
       OR (_context.coverage_state IN ('valid', 'outage')
           AND (_context.finalized_at IS NULL OR _context.finalized_at < _context.anchor_ends_at)) THEN
      CONTINUE;
    END IF;

    _anchor_start := ((_context.anchor_date + _context.sleep_start_local) AT TIME ZONE _context.timezone);
    _anchor_end := ((
      _context.anchor_date
      + CASE WHEN _context.sleep_end_local <= _context.sleep_start_local THEN 1 ELSE 0 END
      + _context.sleep_end_local
    ) AT TIME ZONE _context.timezone);
    _offset_minutes := extract(epoch FROM (((_context.anchor_starts_at AT TIME ZONE _context.timezone) AT TIME ZONE 'UTC') - _context.anchor_starts_at))::integer / 60;

    IF _anchor_start <> _context.anchor_starts_at
       OR _anchor_end <> _context.anchor_ends_at
       OR _offset_minutes <> _context.utc_offset_minutes THEN
      CONTINUE;
    END IF;

    _midpoint := _anchor_start + ((_anchor_end - _anchor_start) / 2);
    SELECT
      count(*) FILTER (WHERE b.received_at >= _anchor_start AND b.received_at < _midpoint)::integer,
      count(*) FILTER (WHERE b.received_at >= _midpoint AND b.received_at < _anchor_end)::integer,
      coalesce(floor(extract(epoch FROM (max(b.received_at) FILTER (WHERE b.received_at >= _anchor_start AND b.received_at < _midpoint) - _anchor_start)) / 60)::integer, 0),
      coalesce(floor(extract(epoch FROM (_anchor_end - min(b.received_at) FILTER (WHERE b.received_at >= _midpoint AND b.received_at < _anchor_end))) / 60)::integer, 0)
    INTO _first_count, _second_count, _raw_start_delay, _raw_wake_advance
    FROM public.behavior_pings AS b
    WHERE b.user_id = _user_id
      AND b.ingest_version = 2
      AND abs(extract(epoch FROM (b.received_at - b.at))) <= 300
      AND b.at < _to
      AND b.received_at < _to;

    _cap_reasons := ARRAY[]::text[];
    IF _raw_start_delay > _max_start_delay THEN
      _cap_reasons := pg_catalog.array_append(_cap_reasons, 'max_start_delay_minutes');
    END IF;
    IF _raw_wake_advance > _max_wake_advance THEN
      _cap_reasons := pg_catalog.array_append(_cap_reasons, 'max_wake_advance_minutes');
    END IF;
    _start_delay := least(_max_start_delay, greatest(0, _raw_start_delay));
    _wake_advance := least(_max_wake_advance, greatest(0, _raw_wake_advance));
    _wake_delay := 0;
    _raw_wake_delay := 0;
    _rate_cap := 0;
    _prior_count := 0;
    _prior_start_cap_applied := false;
    _quality_reason := CASE WHEN _context.coverage_state = 'valid' THEN 'coverage_valid' ELSE 'coverage_' || _context.coverage_state END;

    IF _context.coverage_state = 'valid' THEN
      WITH prior_contexts AS (
        SELECT p.anchor_date, p.anchor_starts_at, p.anchor_ends_at,
          p.anchor_starts_at + ((p.anchor_ends_at - p.anchor_starts_at) / 2) AS midpoint
        FROM public.alert_sleep_night_contexts AS p
        WHERE p.version_id = _version_id
          AND p.user_id = _user_id
          AND p.coverage_state = 'valid'
          AND p.evidence_version = 'canonical-v2'
          AND p.anchor_date < _context.anchor_date
          AND p.anchor_date >= (_context.anchor_date - _lookback)
          AND p.timezone = _context.timezone
          AND abs(p.utc_offset_minutes - _context.utc_offset_minutes) <= _timezone_tolerance
          AND p.captured_at <= p.anchor_starts_at
          AND p.finalized_at >= p.anchor_ends_at
          AND ((p.anchor_date + p.sleep_start_local) AT TIME ZONE p.timezone) = p.anchor_starts_at
          AND ((
            p.anchor_date
            + CASE WHEN p.sleep_end_local <= p.sleep_start_local THEN 1 ELSE 0 END
            + p.sleep_end_local
          ) AT TIME ZONE p.timezone) = p.anchor_ends_at
          AND extract(epoch FROM (((p.anchor_starts_at AT TIME ZONE p.timezone) AT TIME ZONE 'UTC') - p.anchor_starts_at))::integer / 60 = p.utc_offset_minutes
      ), prior_delays AS (
        SELECT p.anchor_date,
          floor(extract(epoch FROM (max(b.received_at) - p.anchor_starts_at)) / 60)::integer AS raw_delay_minutes,
          least(_max_start_delay, floor(extract(epoch FROM (max(b.received_at) - p.anchor_starts_at)) / 60)::integer) AS delay_minutes
        FROM prior_contexts AS p
        JOIN public.behavior_pings AS b
          ON b.user_id = _user_id
         AND b.ingest_version = 2
         AND abs(extract(epoch FROM (b.received_at - b.at))) <= 300
         AND b.at < _to
         AND b.received_at < _to
         AND b.received_at >= p.anchor_starts_at
         AND b.received_at < p.midpoint
        GROUP BY p.anchor_date, p.anchor_starts_at
        HAVING count(*) >= _min_late_events
      )
      SELECT count(*)::integer,
        coalesce(percentile_disc(0.5) WITHIN GROUP (ORDER BY delay_minutes)::integer, 0),
        coalesce(bool_or(raw_delay_minutes > _max_start_delay), false)
      INTO _prior_count, _raw_wake_delay, _prior_start_cap_applied
      FROM prior_delays;

      IF _prior_count >= _min_positive THEN
        _rate_cap := greatest(0, _prior_count - _min_positive + 1) * _max_update_per_day;
        IF _prior_start_cap_applied THEN
          _cap_reasons := pg_catalog.array_append(_cap_reasons, 'prior_max_start_delay_minutes');
        END IF;
        IF _raw_wake_delay > _max_wake_delay THEN
          _cap_reasons := pg_catalog.array_append(_cap_reasons, 'max_wake_delay_minutes');
        END IF;
        IF least(_raw_wake_delay, _max_wake_delay) > _rate_cap THEN
          _cap_reasons := pg_catalog.array_append(_cap_reasons, 'max_update_minutes_per_day');
        END IF;
        _wake_delay := least(_max_wake_delay, _raw_wake_delay, _rate_cap);
        _quality_reason := 'coverage_valid_prior_positive';
      ELSE
        _wake_delay := 0;
      END IF;
    END IF;

    starts_at := _anchor_start + make_interval(mins => _start_delay);
    ends_at := _anchor_end - make_interval(mins => _wake_advance) + make_interval(mins => _wake_delay);
    IF starts_at >= ends_at THEN
      CONTINUE;
    END IF;

    basis := CASE WHEN _start_delay > 0 OR _wake_advance > 0 OR _wake_delay > 0
      THEN 'positive_evidence_adjusted' ELSE 'configured_anchor' END;
    confidence := CASE
      WHEN _start_delay > 0 OR _wake_advance > 0 THEN 1.0
      WHEN _wake_delay > 0 THEN least(1.0, _prior_count::double precision / _min_positive::double precision)
      ELSE 0.0
    END;
    provenance := jsonb_build_object(
      'config_sha256', _config_sha256,
      'anchor_starts_at', _anchor_start,
      'anchor_ends_at', _anchor_end,
      'first_half_positive_count', _first_count,
      'second_half_positive_count', _second_count,
      'prior_positive_night_count', _prior_count,
      'start_delay_minutes', _start_delay,
      'wake_advance_minutes', _wake_advance,
      'wake_delay_minutes', _wake_delay,
      'caps', jsonb_build_object('max_start_delay_minutes', _max_start_delay, 'max_wake_advance_minutes', _max_wake_advance, 'max_wake_delay_minutes', _max_wake_delay, 'max_update_minutes_per_day', _max_update_per_day),
      'confidence', confidence,
      'cap_reason', coalesce(pg_catalog.array_to_string(_cap_reasons, ','), 'none'),
      'timezone', _context.timezone,
      'utc_offset_minutes', _context.utc_offset_minutes,
      'coverage_state', _context.coverage_state,
      'quality_reason', _quality_reason
    );
    RETURN NEXT;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION private.candidate_sleep_intervals(uuid, timestamptz, timestamptz, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
