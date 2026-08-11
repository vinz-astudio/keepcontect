-- ADR-0023 Task 7: deterministic aggregate-only historical replay.
-- This migration adds no context/coverage/sleep producer, no scheduler, no
-- live-alert write, and no notification path. The existing ADR-0022 live
-- threshold and Guardian 30-minute state machine remain unchanged. Replay
-- enumerates completed canonical-v2 raw session gaps once, set-wise, inside
-- an internal MATERIALIZED CTE (never a temp/permanent per-user table),
-- calls the locked Task 6 private.resolve_alert_candidate exactly once per
-- bounded unit, and writes only the aggregate-only public.alert_judgment_evaluations
-- row created in Task 2. promotion_eligible is hard-pinned false.

-- Unlike Task 6's evaluator contract, the replay section is required only
-- for versions that are actually replayed: a blanket table CHECK would
-- reject every pre-Task-7 alert_model_versions fixture that never calls
-- run_alert_judgment_replay. private.replay_config_is_valid below is
-- therefore enforced only inside the replay entrypoint itself.

-- Raw-type-first replay config gate. A canonical config_sha256 only proves
-- the stored config matches its own hash; it says nothing about whether the
-- replay section carries the right JSON type, enum, range, or integrality.
CREATE FUNCTION private.replay_config_is_valid(_config jsonb)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
SET TimeZone = 'UTC'
SET extra_float_digits = 3
AS $$
  SELECT CASE
    WHEN jsonb_typeof(_config) IS DISTINCT FROM 'object'
      OR jsonb_typeof(_config -> 'replay') IS DISTINCT FROM 'object'
      OR NOT ((_config -> 'replay') ?& ARRAY[
        'contract_version', 'max_range_days', 'max_units'
      ])
      OR jsonb_typeof(_config #> '{replay,contract_version}') IS DISTINCT FROM 'string'
      OR jsonb_typeof(_config #> '{replay,max_range_days}') IS DISTINCT FROM 'number'
      OR jsonb_typeof(_config #> '{replay,max_units}') IS DISTINCT FROM 'number'
    THEN false
    ELSE
      _config #>> '{replay,contract_version}' = 'adaptive_replay_v1'
      AND (_config #>> '{replay,max_range_days}')::numeric BETWEEN 1 AND 2147483647
      AND (_config #>> '{replay,max_range_days}')::numeric
        = trunc((_config #>> '{replay,max_range_days}')::numeric)
      AND (_config #>> '{replay,max_units}')::numeric BETWEEN 1 AND 2147483647
      AND (_config #>> '{replay,max_units}')::numeric
        = trunc((_config #>> '{replay,max_units}')::numeric)
  END
$$;

REVOKE ALL PRIVILEGES ON FUNCTION private.replay_config_is_valid(jsonb)
FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.run_alert_judgment_replay(
  _version_id uuid,
  _from timestamptz,
  _to timestamptz
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
  _replay_contract constant text := 'adaptive_replay_v1';
  _evaluator_contract constant text := 'adaptive_candidate_v1';
  _version public.alert_model_versions%ROWTYPE;
  _gap_minutes integer;
  _max_range_days integer;
  _max_units integer;
  _unit_count integer;
  _units_captured jsonb;
  _evaluated_count integer;
  _replayable_count integer;
  _unreplayable_count integer;
  _unreplayable_reason_counts jsonb;
  _live_alert_rows_observed integer;
  _unmatched_live_silence_alert_rows integer;
  _candidate_would_alert_gaps integer;
  _proxy_denominator integer;
  _both_proxy integer;
  _live_only_proxy integer;
  _candidate_only_proxy integer;
  _neither_proxy integer;
  _threshold_delta_denominator integer;
  _median_delta double precision;
  _p95_delta double precision;
  _basis_counts jsonb;
  _quality_counts jsonb;
  _cap_reason_counts jsonb;
  _report_status text;
  _units_json jsonb;
  _unmatched_json jsonb;
  _metrics jsonb;
  _input_sha text;
  _output_sha text;
  _from_utc text := to_char(_from AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
  _to_utc text := to_char(_to AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
BEGIN
  IF _version_id IS NULL OR _from IS NULL OR _to IS NULL OR NOT (_from < _to) THEN
    RAISE EXCEPTION 'adaptive_alert_replay_invalid_range'
      USING DETAIL = 'from must be strictly less than to';
  END IF;

  SELECT v.* INTO _version
  FROM public.alert_model_versions AS v
  WHERE v.id = _version_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'adaptive_alert_replay_unknown_version';
  END IF;

  IF _version.status <> 'replay' THEN
    RAISE EXCEPTION 'adaptive_alert_replay_invalid_version_status';
  END IF;

  IF _version.config_sha256
      <> encode(extensions.digest(_version.config::text, 'sha256'), 'hex') THEN
    RAISE EXCEPTION 'adaptive_alert_replay_config_hash_mismatch';
  END IF;

  IF _version.evidence_version <> 'canonical-v2' THEN
    RAISE EXCEPTION 'adaptive_alert_replay_unsupported_evidence_version';
  END IF;

  IF NOT private.alert_candidate_config_is_valid(_version.config) THEN
    RAISE EXCEPTION 'adaptive_alert_replay_invalid_evaluator_config';
  END IF;

  IF _version.config #>> '{evaluator,contract_version}' <> _evaluator_contract THEN
    RAISE EXCEPTION 'adaptive_alert_replay_unsupported_evaluator_contract';
  END IF;

  IF NOT private.replay_config_is_valid(_version.config) THEN
    RAISE EXCEPTION 'adaptive_alert_replay_invalid_replay_config';
  END IF;

  IF _version.config #>> '{replay,contract_version}' <> _replay_contract THEN
    RAISE EXCEPTION 'adaptive_alert_replay_unsupported_replay_contract';
  END IF;

  _max_range_days := (_version.config #>> '{replay,max_range_days}')::integer;
  _max_units := (_version.config #>> '{replay,max_units}')::integer;
  _gap_minutes := (_version.config #>> '{sessionization,gap_minutes}')::integer;

  IF (_to - _from) > make_interval(days => _max_range_days) THEN
    RAISE EXCEPTION 'adaptive_alert_replay_range_exceeds_max_range_days';
  END IF;

  -- Enumerate and sessionize exactly once, in exactly one MATERIALIZED CTE,
  -- inside a single statement/snapshot. The bounded result is captured into
  -- an in-memory jsonb array only (never a temp/permanent table, never a
  -- per-user row anywhere): no later statement re-reads behavior_pings, so
  -- no concurrent ping insert between statements can change what was
  -- counted against replay.max_units or what gets evaluated below.
  WITH candidate_replay_units AS MATERIALIZED (
    WITH range_admitted AS (
      SELECT p.id, p.user_id, p.received_at
      FROM public.behavior_pings AS p
      WHERE p.ingest_version = 2
        AND p.received_at >= _from
        AND p.received_at < _to
        AND p.at < _to
        AND abs(extract(epoch FROM (p.received_at - p.at))) <= 300
    ), prior_admitted AS (
      SELECT prior.id, prior.user_id, prior.received_at
      FROM (SELECT DISTINCT user_id FROM range_admitted) AS active_user
      CROSS JOIN LATERAL (
        SELECT p.id, p.user_id, p.received_at
        FROM public.behavior_pings AS p
        WHERE p.user_id = active_user.user_id
          AND p.ingest_version = 2
          AND p.received_at < _from
          AND p.at < _to
          AND abs(extract(epoch FROM (p.received_at - p.at))) <= 300
        ORDER BY p.received_at DESC, p.id DESC
        LIMIT 1
      ) AS prior
    ), admitted AS (
      SELECT * FROM range_admitted
      UNION ALL
      SELECT * FROM prior_admitted
    ), marked AS (
      SELECT admitted.*,
        CASE
          WHEN lag(received_at) OVER (PARTITION BY user_id ORDER BY received_at, id) IS NULL
            OR received_at - lag(received_at) OVER (PARTITION BY user_id ORDER BY received_at, id)
              > make_interval(mins => _gap_minutes)
          THEN 1 ELSE 0
        END AS starts_session
      FROM admitted
    ), grouped AS (
      SELECT marked.*,
        sum(starts_session) OVER (PARTITION BY user_id ORDER BY received_at, id) AS session_no
      FROM marked
    ), summarized AS (
      SELECT user_id, session_no,
        min(received_at) AS session_start,
        max(received_at) AS session_end
      FROM grouped
      GROUP BY user_id, session_no
    ), ordered AS (
      SELECT user_id, session_end,
        lead(session_start) OVER (PARTITION BY user_id ORDER BY session_start) AS next_start
      FROM summarized
    )
    SELECT user_id, session_end, next_start
    FROM ordered
    WHERE next_start IS NOT NULL
      AND next_start >= _from
      AND next_start < _to
  )
  SELECT
    count(*)::integer,
    coalesce(jsonb_agg(
      jsonb_build_object(
        'user_id', user_id,
        'session_end_utc',
          to_char(session_end AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'next_start_utc',
          to_char(next_start AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
      )
      ORDER BY session_end, next_start, user_id
    ), '[]'::jsonb)
  INTO _unit_count, _units_captured
  FROM candidate_replay_units;

  IF _unit_count > _max_units THEN
    RAISE EXCEPTION 'adaptive_alert_replay_max_units_exceeded';
  END IF;

  -- Evaluate strictly from the already-captured bounded set: exactly one
  -- resolve_alert_candidate call per unit, and no further read of
  -- behavior_pings, so the MATERIALIZED CTE above is the only
  -- sessionization pass in the whole run.
  WITH captured_units AS (
    SELECT
      (elem ->> 'user_id')::uuid AS user_id,
      (elem ->> 'session_end_utc')::timestamptz AS session_end,
      (elem ->> 'next_start_utc')::timestamptz AS next_start
    FROM jsonb_array_elements(_units_captured) AS elem
  ), evaluated AS MATERIALIZED (
    SELECT u.user_id, u.session_end, u.next_start,
      private.resolve_alert_candidate(u.user_id, u.next_start, _version_id) AS result
    FROM captured_units AS u
  ), live_matches AS (
    SELECT e.user_id, e.session_end, e.next_start,
      count(a.id)::integer AS matched_count
    FROM evaluated AS e
    LEFT JOIN public.alerts AS a
      ON a.user_id = e.user_id
     AND a.cause = 'silence'
     AND a.opened_at >= e.session_end
     AND a.opened_at < e.next_start
    GROUP BY e.user_id, e.session_end, e.next_start
  ), per_unit AS (
    SELECT
      e.user_id, e.session_end, e.next_start, e.result,
      m.matched_count,
      (e.result ->> 'replayable')::boolean AS replayable,
      e.result ->> 'unreplayable_reason' AS unreplayable_reason,
      (e.result ->> 'would_alert')::boolean AS would_alert,
      e.result ->> 'candidate_cap_reason' AS cap_reason,
      e.result ->> 'basis' AS basis,
      e.result ->> 'quality_state' AS quality_state,
      (e.result ->> 'candidate_threshold_minutes')::integer AS candidate_threshold_minutes,
      (e.result ->> 'sensitivity_buffer_minutes')::integer AS sensitivity_buffer_minutes
    FROM evaluated AS e
    JOIN live_matches AS m
      ON m.user_id = e.user_id
     AND m.session_end = e.session_end
     AND m.next_start = e.next_start
  ), unreplayable_reason_agg AS (
    SELECT coalesce(jsonb_object_agg(unreplayable_reason, cnt), '{}'::jsonb) AS obj
    FROM (
      SELECT unreplayable_reason, count(*)::integer AS cnt
      FROM per_unit
      WHERE NOT replayable
      GROUP BY unreplayable_reason
    ) AS t
  ), basis_agg AS (
    SELECT coalesce(jsonb_object_agg(basis, cnt), '{}'::jsonb) AS obj
    FROM (
      SELECT basis, count(*)::integer AS cnt
      FROM per_unit
      WHERE replayable
      GROUP BY basis
    ) AS t
  ), quality_agg AS (
    SELECT coalesce(jsonb_object_agg(quality_state, cnt), '{}'::jsonb) AS obj
    FROM (
      SELECT quality_state, count(*)::integer AS cnt
      FROM per_unit
      WHERE replayable
      GROUP BY quality_state
    ) AS t
  ), cap_reason_agg AS (
    SELECT coalesce(jsonb_object_agg(cap_reason, cnt), '{}'::jsonb) AS obj
    FROM (
      SELECT cap_reason, count(*)::integer AS cnt
      FROM per_unit
      WHERE replayable
      GROUP BY cap_reason
    ) AS t
  ), unmatched_agg AS (
    SELECT count(*)::integer AS unmatched_count,
      coalesce(jsonb_agg(
        to_char(a.opened_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
        ORDER BY a.opened_at, a.id
      ), '[]'::jsonb) AS unmatched_json
    FROM public.alerts AS a
    WHERE a.cause = 'silence'
      AND a.opened_at >= _from
      AND a.opened_at < _to
      AND NOT EXISTS (
        SELECT 1
        FROM captured_units AS u
        WHERE u.user_id = a.user_id
          AND a.opened_at >= u.session_end
          AND a.opened_at < u.next_start
      )
  ), units_agg AS (
    SELECT coalesce(jsonb_agg(
      jsonb_build_object(
        'session_end_utc', to_char(session_end AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'next_start_utc', to_char(next_start AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'replayable', replayable,
        'unreplayable_reason', unreplayable_reason,
        'evaluator_provenance_sha256', result ->> 'provenance_sha256',
        'matched_live_count', matched_count
      )
      ORDER BY
        session_end,
        next_start,
        coalesce(result ->> 'provenance_sha256', ''),
        replayable,
        coalesce(unreplayable_reason, ''),
        matched_count
    ), '[]'::jsonb) AS units_json
    FROM per_unit
  )
  SELECT
    count(*)::integer,
    count(*) FILTER (WHERE replayable)::integer,
    count(*) FILTER (WHERE NOT replayable)::integer,
    (SELECT obj FROM unreplayable_reason_agg),
    coalesce(sum(matched_count) FILTER (WHERE replayable), 0)::integer,
    (SELECT unmatched_count FROM unmatched_agg),
    count(*) FILTER (WHERE replayable AND would_alert)::integer,
    count(*) FILTER (WHERE replayable)::integer,
    count(*) FILTER (WHERE replayable AND matched_count > 0 AND would_alert)::integer,
    count(*) FILTER (WHERE replayable AND matched_count > 0 AND NOT would_alert)::integer,
    count(*) FILTER (WHERE replayable AND matched_count = 0 AND would_alert)::integer,
    count(*) FILTER (WHERE replayable AND matched_count = 0 AND NOT would_alert)::integer,
    count(*) FILTER (WHERE replayable)::integer,
    (SELECT percentile_cont(0.5) WITHIN GROUP (
      ORDER BY (candidate_threshold_minutes - (90 + sensitivity_buffer_minutes)))
      FROM per_unit WHERE replayable),
    (SELECT percentile_cont(0.95) WITHIN GROUP (
      ORDER BY (candidate_threshold_minutes - (90 + sensitivity_buffer_minutes)))
      FROM per_unit WHERE replayable),
    (SELECT obj FROM basis_agg),
    (SELECT obj FROM quality_agg),
    (SELECT obj FROM cap_reason_agg),
    (SELECT units_json FROM units_agg),
    (SELECT unmatched_json FROM unmatched_agg)
  INTO
    _evaluated_count, _replayable_count, _unreplayable_count, _unreplayable_reason_counts,
    _live_alert_rows_observed, _unmatched_live_silence_alert_rows,
    _candidate_would_alert_gaps, _proxy_denominator,
    _both_proxy, _live_only_proxy, _candidate_only_proxy, _neither_proxy,
    _threshold_delta_denominator, _median_delta, _p95_delta,
    _basis_counts, _quality_counts, _cap_reason_counts,
    _units_json, _unmatched_json
  FROM per_unit;

  IF _evaluated_count = 0 THEN
    _report_status := 'empty';
  ELSIF _replayable_count = 0 THEN
    _report_status := 'all_unreplayable';
  ELSIF _unreplayable_count = 0 THEN
    _report_status := 'complete';
  ELSE
    _report_status := 'partial';
  END IF;

  -- Canonical input hash: contract versions, model config/evidence hash,
  -- exact range, and an ordered multiset of unit timestamps, Task 6
  -- provenance hashes, and ordered live-proxy timestamps/counts. It excludes
  -- user/alert ids, runtime/transaction timing, created_at, and this row's
  -- own hash columns; duplicate tokens remain duplicated.
  _input_sha := encode(extensions.digest(jsonb_build_object(
    'replay_contract_version', _replay_contract,
    'evaluator_contract_version', _evaluator_contract,
    'model_config_sha256', _version.config_sha256,
    'model_evidence_version', _version.evidence_version,
    'from_utc', _from_utc,
    'to_utc', _to_utc,
    'units', _units_json,
    'unmatched_live_silence_alert_opened_at_utc', _unmatched_json
  )::text, 'sha256'), 'hex');

  _metrics := jsonb_build_object(
    'version_id', _version_id,
    'replay_contract_version', _replay_contract,
    'evaluator_version', _evaluator_contract,
    'from', _from_utc,
    'to', _to_utc,
    'report_status', _report_status,
    'evaluated_count', _evaluated_count,
    'replayable_count', _replayable_count,
    'unreplayable_count', _unreplayable_count,
    'unreplayable_reason_counts', _unreplayable_reason_counts,
    'replayable_completed_gap_count', _replayable_count,
    'live_alert_rows_observed', _live_alert_rows_observed,
    'unmatched_live_silence_alert_rows', _unmatched_live_silence_alert_rows,
    'candidate_would_alert_gaps', _candidate_would_alert_gaps,
    'proxy_denominator_replayable_gaps', _proxy_denominator,
    'both_proxy', _both_proxy,
    'live_only_proxy', _live_only_proxy,
    'candidate_only_proxy', _candidate_only_proxy,
    'neither_proxy', _neither_proxy,
    'threshold_delta_denominator_replayable_gaps', _threshold_delta_denominator,
    'median_candidate_minus_adr0022_threshold_proxy_minutes', _median_delta,
    'p95_candidate_minus_adr0022_threshold_proxy_minutes', _p95_delta,
    'basis_counts', _basis_counts,
    'quality_counts', _quality_counts,
    'cap_reason_counts', _cap_reason_counts,
    'adjudicated_risk_outcomes', 0,
    'unadjudicated_replayable_count', _replayable_count,
    'safety_claim', 'not_evaluated',
    'promotion_eligible', false
  );

  _output_sha := encode(extensions.digest(
    (_metrics || jsonb_build_object('input_sha256', _input_sha))::text, 'sha256'
  ), 'hex');

  INSERT INTO public.alert_judgment_evaluations (
    version_id, evaluation_kind, evaluated_from, evaluated_to,
    metrics, input_sha256, output_sha256, evaluator_version, promotion_eligible
  ) VALUES (
    _version_id, 'historical_replay', _from, _to,
    _metrics, _input_sha, _output_sha, _evaluator_contract, false
  )
  ON CONFLICT (version_id, evaluation_kind, evaluated_from, evaluated_to)
  DO UPDATE SET
    metrics = EXCLUDED.metrics,
    input_sha256 = EXCLUDED.input_sha256,
    output_sha256 = EXCLUDED.output_sha256,
    evaluator_version = EXCLUDED.evaluator_version,
    promotion_eligible = false
  WHERE public.alert_judgment_evaluations.metrics IS DISTINCT FROM EXCLUDED.metrics
     OR public.alert_judgment_evaluations.input_sha256 IS DISTINCT FROM EXCLUDED.input_sha256
     OR public.alert_judgment_evaluations.output_sha256 IS DISTINCT FROM EXCLUDED.output_sha256
     OR public.alert_judgment_evaluations.evaluator_version IS DISTINCT FROM EXCLUDED.evaluator_version;

  RETURN _metrics || jsonb_build_object(
    'input_sha256', _input_sha, 'output_sha256', _output_sha
  );
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.run_alert_judgment_replay(uuid, timestamptz, timestamptz)
FROM PUBLIC, anon, authenticated, service_role;

CREATE INDEX IF NOT EXISTS behavior_pings_ingest2_user_received_idx
  ON public.behavior_pings (user_id, received_at, id)
  WHERE ingest_version = 2;

CREATE INDEX IF NOT EXISTS alerts_silence_user_opened_idx
  ON public.alerts (user_id, opened_at)
  WHERE cause = 'silence';
