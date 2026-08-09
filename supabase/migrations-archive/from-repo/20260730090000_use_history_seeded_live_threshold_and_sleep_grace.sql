-- Human-authorized live correction:
-- 1. A valid retained personal profile is the starting live threshold.
-- 2. New canonical-v2 sessions may only extend that starting point until a
--    newer rebuilt profile absorbs/replaces them.
-- 3. The fixed sensitivity template remains a floor, never a ceiling.
-- 4. Configured sleep and the two-hour post-wake grace gate every silence path.

CREATE OR REPLACE FUNCTION private.silence_threshold(_user_id uuid)
RETURNS interval
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
SET TimeZone = 'UTC'
AS $$
DECLARE
  _s text;
  _fixed_minutes integer;
  _version_id uuid;
  _config jsonb;
  _config_sha256 text;
  _evidence_version text;
  _gap_minutes integer;
  _horizon_days integer;
  _max_age_days integer;
  _buffer_minutes integer;
  _ceiling_minutes integer;
  _profile_minutes integer;
  _profile_latest_at timestamptz;
  _new_p95_minutes integer;
  _personal_minutes integer;
BEGIN
  SELECT sensitivity
    INTO _s
  FROM public.user_settings
  WHERE user_id = _user_id;

  _s := coalesce(_s, 'balanced');
  _fixed_minutes := CASE _s
    WHEN 'high' THEN 90
    WHEN 'sensitive' THEN 90
    WHEN 'low' THEN 180
    WHEN 'relaxed' THEN 180
    ELSE 135
  END;

  SELECT
    runtime.version_id,
    version.config,
    version.config_sha256,
    version.evidence_version
  INTO
    _version_id,
    _config,
    _config_sha256,
    _evidence_version
  FROM private.adaptive_alert_shadow_runtime_config AS runtime
  JOIN public.alert_model_versions AS version
    ON version.id = runtime.version_id
  WHERE runtime.singleton
    AND runtime.enabled
    AND version.status = 'shadow'
    AND version.shadow_enabled_at IS NOT NULL
    AND version.evidence_version = 'canonical-v2'
    AND version.config_sha256
      = encode(extensions.digest(version.config::text, 'sha256'), 'hex')
    AND private.alert_candidate_config_is_valid(version.config);

  IF _version_id IS NULL THEN
    RETURN make_interval(mins => _fixed_minutes);
  END IF;

  BEGIN
    _gap_minutes :=
      (_config #>> '{sessionization,gap_minutes}')::integer;
    _horizon_days :=
      (_config #>> '{sessionization,training_horizon_days}')::integer;
    _max_age_days :=
      (_config #>> '{personal,max_age_days}')::integer;
    _buffer_minutes := CASE _s
      WHEN 'high' THEN
        (_config #>> '{sensitivity_buffers_minutes,high}')::integer
      WHEN 'sensitive' THEN
        (_config #>> '{sensitivity_buffers_minutes,high}')::integer
      WHEN 'low' THEN
        (_config #>> '{sensitivity_buffers_minutes,low}')::integer
      WHEN 'relaxed' THEN
        (_config #>> '{sensitivity_buffers_minutes,low}')::integer
      ELSE
        (_config #>> '{sensitivity_buffers_minutes,balanced}')::integer
    END;
    _ceiling_minutes :=
      (_config #>> '{candidate_bounds,ceiling_minutes}')::integer;
  EXCEPTION
    WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      RETURN make_interval(mins => _fixed_minutes);
  END;

  SELECT
    profile.neutral_p95_minutes,
    profile.latest_evidence_at
  INTO
    _profile_minutes,
    _profile_latest_at
  FROM public.alert_gap_profiles AS profile
  WHERE profile.version_id = _version_id
    AND profile.user_id = _user_id
    AND profile.context_key = 'personal_global'
    AND profile.quality_state = 'valid'
    AND profile.config_sha256 = _config_sha256
    AND profile.evidence_version = _evidence_version
    AND profile.latest_evidence_at
      >= now() - make_interval(days => _max_age_days)
  ORDER BY profile.through_date DESC, profile.computed_at DESC
  LIMIT 1;

  IF _profile_minutes IS NULL THEN
    RETURN make_interval(mins => _fixed_minutes);
  END IF;

  -- This is training-only extension evidence. It reads canonical rows after
  -- the selected profile's evidence boundary, but does not claim coverage,
  -- refresh heartbeat, resolve alerts, or mutate a profile. Once a newer
  -- profile advances latest_evidence_at, the same rows leave this extension.
  WITH admitted AS (
    SELECT ping.id, ping.received_at
    FROM public.behavior_pings AS ping
    WHERE ping.user_id = _user_id
      AND ping.ingest_version = 2
      AND ping.received_at >= greatest(
        _profile_latest_at,
        now() - make_interval(days => _horizon_days)
      )
      AND ping.received_at <= now()
      AND ping.at <= now()
      AND abs(extract(epoch FROM (ping.received_at - ping.at))) <= 300
  ),
  marked AS (
    SELECT
      admitted.*,
      CASE
        WHEN lag(received_at) OVER (ORDER BY received_at, id) IS NULL
          OR received_at
            - lag(received_at) OVER (ORDER BY received_at, id)
              > make_interval(mins => _gap_minutes)
          THEN 1
        ELSE 0
      END AS starts_session
    FROM admitted
  ),
  grouped AS (
    SELECT
      marked.*,
      sum(starts_session) OVER (ORDER BY received_at, id) AS session_no
    FROM marked
  ),
  sessions AS (
    SELECT
      min(received_at) AS session_start,
      max(received_at) AS session_end
    FROM grouped
    GROUP BY session_no
  ),
  paired AS (
    SELECT
      session_end,
      lead(session_start) OVER (ORDER BY session_start) AS next_start
    FROM sessions
  )
  SELECT ceil(
    percentile_disc(0.95) WITHIN GROUP (
      ORDER BY extract(epoch FROM (next_start - session_end)) / 60.0
    )
  )::integer
  INTO _new_p95_minutes
  FROM paired
  WHERE next_start IS NOT NULL;

  _personal_minutes := greatest(
    _profile_minutes,
    coalesce(_new_p95_minutes, _profile_minutes)
  ) + _buffer_minutes;

  RETURN make_interval(
    mins => greatest(
      _fixed_minutes,
      least(_ceiling_minutes, _personal_minutes)
    )
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION private.silence_threshold(uuid)
FROM PUBLIC, anon, authenticated, service_role;

-- Existing shadow versions pin the pre-promotion ADR-0022 definition. Preserve
-- that immutable model config and explicitly recognize this one
-- human-authorized successor definition; every unrelated hash stays closed.
CREATE OR REPLACE FUNCTION private.shadow_live_definition_matches(
  _expected_sha256 text,
  _actual_definition text
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH hashes AS (
    SELECT
      encode(
        extensions.digest(_actual_definition, 'sha256'),
        'hex'
      ) AS raw_sha256,
      encode(
        extensions.digest(
          replace(_actual_definition, E'\r\n', E'\n'),
          'sha256'
        ),
        'hex'
      ) AS lf_sha256
  )
  SELECT CASE
    WHEN _expected_sha256 !~ '^[a-f0-9]{64}$'
      OR _actual_definition IS NULL
      THEN false
    ELSE
      _expected_sha256 IN (hashes.raw_sha256, hashes.lf_sha256)
      OR (
        _expected_sha256 =
          '1907d59473d274d46a0e8e0b9ce8027037b4494b0dddf073cb46abf67db92e21'
        AND hashes.lf_sha256 IN (
          '686116ef8f2df1d78f6d0d48ded8019555f283b098eeb5d354cfa1c14ebbcdca',
          '6be4ed54feff52428cf1d86210126bd9362953201fc5ac8b9e885abd586092ce'
        )
      )
  END
  FROM hashes
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.shadow_live_definition_matches(text,text)
FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.process_escalations()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  _self_grace CONSTANT interval := interval '30 minutes';
  _group_dur  CONSTANT interval := interval '1 hour';
  _comm_dur   CONSTANT interval := interval '2 hours';
  r record;
  _aid uuid;
  _new text;
  _triggered boolean := false;
BEGIN
  -- Sleep/post-wake grace clears silence alerts even without a newer ping.
  FOR r IN
    SELECT
      a.id,
      a.user_id,
      a.cause,
      ds.last_heartbeat_at,
      bp.last_at AS last_behavior_at
    FROM public.alerts AS a
    LEFT JOIN public.device_state AS ds ON ds.user_id = a.user_id
    LEFT JOIN LATERAL (
      SELECT max(received_at) AS last_at
      FROM public.behavior_pings
      WHERE user_id = a.user_id
        AND ingest_version = 2
        AND abs(extract(epoch FROM (received_at - at))) <= 300
        AND received_at >= a.opened_at
        AND at >= a.opened_at
    ) AS bp ON true
    WHERE a.status = 'open'
      AND a.cause IN ('silence', 'dark_device')
      AND (
        (
          a.cause = 'silence'
          AND (
            private.sleep_relaxed(a.user_id, now())
            OR (
              bp.last_at IS NOT NULL
              AND now() - bp.last_at
                <= private.silence_threshold(a.user_id)
            )
          )
        )
        OR (
          a.cause = 'dark_device'
          AND ds.last_heartbeat_at IS NOT NULL
          AND now() - ds.last_heartbeat_at <= interval '18 hours'
        )
      )
  LOOP
    UPDATE public.alerts
    SET status = 'resolved',
        resolved_at = now(),
        resolved_by = NULL,
        updated_at = now()
    WHERE id = r.id;

    INSERT INTO public.alert_events (alert_id, kind, note)
    VALUES (r.id, 'auto_resolved', 'condition_cleared');

    PERFORM private.notify_auto_resolved(r.id, r.user_id);
    _triggered := true;
  END LOOP;

  -- device_state.status is descriptive state, not an independent authority to
  -- bypass the canonical silence calculation or sleep grace.
  FOR r IN
    SELECT
      ds.user_id,
      (now() - ds.last_heartbeat_at) > interval '18 hours' AS is_dark
    FROM public.device_state AS ds
    WHERE (
      now() - ds.last_heartbeat_at > interval '18 hours'
      OR (
        NOT private.sleep_relaxed(ds.user_id, now())
        AND now() - (
          SELECT coalesce(max(received_at), to_timestamp(0))
          FROM public.behavior_pings
          WHERE user_id = ds.user_id
            AND ingest_version = 2
            AND abs(extract(epoch FROM (received_at - at))) <= 300
        ) > private.silence_threshold(ds.user_id)
      )
    )
      AND EXISTS (
        SELECT 1
        FROM public.group_members AS gm
        WHERE gm.user_id = ds.user_id
          AND gm.monitored
          AND gm.status = 'active'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.alerts AS a
        WHERE a.user_id = ds.user_id
          AND a.status = 'open'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.alerts AS recent
        WHERE recent.user_id = ds.user_id
          AND recent.status = 'resolved'
          AND recent.cause IN ('silence', 'dark_device')
          AND recent.resolved_by IS NOT NULL
          AND recent.resolved_by <> recent.user_id
          AND recent.resolved_at > now() - _self_grace
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.gm_mutes AS mute
        WHERE mute.user_id = ds.user_id
          AND (mute.muted_until IS NULL OR mute.muted_until > now())
      )
  LOOP
    INSERT INTO public.alerts (
      user_id, cause, stage, stage_entered_at, next_deadline
    )
    VALUES (
      r.user_id,
      CASE WHEN r.is_dark THEN 'dark_device' ELSE 'silence' END,
      'self',
      now(),
      now() + _self_grace
    )
    RETURNING id INTO _aid;

    INSERT INTO public.alert_events (alert_id, kind)
    VALUES (_aid, 'raised');

    PERFORM private.notify_stage(_aid, r.user_id, 'self');
    _triggered := true;
  END LOOP;

  FOR r IN
    SELECT *
    FROM public.alerts
    WHERE status = 'open'
      AND next_deadline IS NOT NULL
      AND next_deadline <= now()
      AND coalesce(paused_until, to_timestamp(0)) <= now()
  LOOP
    _new := CASE r.stage
      WHEN 'self' THEN 'group'
      WHEN 'group' THEN 'community'
      WHEN 'community' THEN 'terminal'
      ELSE 'terminal'
    END;

    UPDATE public.alerts
    SET stage = _new,
        stage_entered_at = now(),
        paused_until = NULL,
        paused_by = NULL,
        updated_at = now(),
        next_deadline = CASE _new
          WHEN 'group' THEN now() + _group_dur
          WHEN 'community' THEN now() + _comm_dur
          ELSE NULL
        END
    WHERE id = r.id;

    INSERT INTO public.alert_events (alert_id, kind, note)
    VALUES (r.id, 'escalated', _new);

    PERFORM private.notify_stage(r.id, r.user_id, _new);
    _triggered := true;
  END LOOP;

  IF _triggered THEN
    PERFORM private.trigger_push_dispatch();
  END IF;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.process_escalations()
FROM PUBLIC, anon, authenticated;
