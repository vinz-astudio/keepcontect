-- S3-E · Let iOS report coverage, because it has been able to all along.
--
-- The claim that iOS "cannot report coverage" was wrong. iOS already carries
-- two independent wake mechanisms, both live in production:
--
--   * silent push - the passive-poll job knocks every 15 minutes and iOS
--     launches the app in the background to answer
--   * HealthKit background delivery - the one documented mechanism that
--     relaunches a force-quit app, and unlike DeviceActivity/FamilyControls it
--     needs no entitlement approval from Apple
--
-- Measured over seven days on the two accounts running the iOS build, the gap
-- between consecutive wake reports is:
--
--              median    p90     p95    within 35 min
--   iOS A        15.0   40.4    88.6           89.0%
--   iOS B        15.1   75.7   186.9           75.1%
--   Android      15.4   18.3    18.9           99.2%
--
-- iOS reaches the same median cadence as Android with a much heavier tail.
-- That is the honest shape of a best-effort channel, and the interval builder
-- already handles it: a gap wider than the allowance becomes an `unknown`
-- interval rather than a `valid` one, so sparse evidence cannot masquerade as
-- continuous observation. That masquerade is what made S3-C2 raise a false
-- alarm, so the allowance is deliberately tight rather than flattering.
--
-- 35 minutes for iOS is not borrowed from Android by coincidence: both report
-- on a 15-minute cadence, so 35 minutes allows about two missed beats and no
-- more. At that allowance 75-89% of observed iOS gaps count as valid coverage
-- and every longer one is honestly unknown.
--
-- Nothing here changes Android or Tauri behaviour.

CREATE OR REPLACE FUNCTION private.record_alert_shadow_coverage_lease_core(_user_id uuid, _client_id text, _channel text, _collector_contract text, _collector_state text, _capability_sha256 text, _observed_at timestamp with time zone, _event_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET "TimeZone" TO 'UTC'
AS $function$
DECLARE
  _received_at timestamptz := clock_timestamp();
  _platform text;
  _app_version text;
  _timezone text;
  _utc_offset_minutes integer;
  _enabled boolean;
  _accept boolean;
  _inserted integer;
BEGIN
  SELECT enabled, accept_coverage_leases
  INTO _enabled, _accept
  FROM private.adaptive_alert_shadow_runtime_config
  WHERE singleton;

  IF coalesce(_enabled, false) IS NOT TRUE
     OR coalesce(_accept, false) IS NOT TRUE THEN
    RETURN 'disabled';
  END IF;

  IF _user_id IS NULL THEN RETURN 'invalid'; END IF;
  IF _event_id IS NULL THEN RETURN 'invalid'; END IF;
  IF _client_id IS NULL OR length(trim(_client_id)) NOT BETWEEN 1 AND 64 THEN
    RETURN 'invalid';
  END IF;
  IF _channel NOT IN ('tauri', 'android-apk', 'ios-app') THEN RETURN 'unsupported'; END IF;
  IF (
    _channel = 'tauri' AND _collector_contract <> 'tauri-idle-v1'
  ) OR (
    _channel = 'android-apk' AND _collector_contract <> 'android-passive-v1'
  ) OR (
    _channel = 'ios-app' AND _collector_contract <> 'ios-wake-v1'
  ) THEN
    RETURN 'unsupported';
  END IF;
  IF _collector_state IS DISTINCT FROM 'operational' THEN
    RETURN 'unsupported';
  END IF;
  IF _capability_sha256 IS NULL
     OR _capability_sha256 !~ '^[a-f0-9]{64}$' THEN
    RETURN 'invalid';
  END IF;
  IF _observed_at IS NULL
     OR abs(extract(epoch FROM (_received_at - _observed_at))) > 300 THEN
    RETURN 'invalid';
  END IF;

  SELECT c.platform, c.app_version
  INTO _platform, _app_version
  FROM public.clients AS c
  WHERE c.user_id = _user_id
    AND c.client_id = _client_id;

  IF NOT FOUND THEN RETURN 'unregistered_client'; END IF;
  IF (
    _channel = 'tauri' AND _platform IS DISTINCT FROM 'tauri'
  ) OR (
    _channel = 'android-apk' AND _platform IS DISTINCT FROM 'android-apk'
  ) OR (
    _channel = 'ios-app' AND _platform IS DISTINCT FROM 'ios-app'
  ) THEN
    RETURN 'capability_mismatch';
  END IF;
  IF _app_version IS NULL OR length(trim(_app_version)) NOT BETWEEN 1 AND 32 THEN
    RETURN 'capability_mismatch';
  END IF;

  SELECT coalesce(s.timezone, 'UTC')
  INTO _timezone
  FROM public.user_settings AS s
  WHERE s.user_id = _user_id;
  _timezone := coalesce(_timezone, 'UTC');

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_timezone_names
    WHERE name = _timezone
  ) THEN
    RETURN 'invalid';
  END IF;

  _utc_offset_minutes := round(
    extract(epoch FROM (
      (_received_at AT TIME ZONE _timezone)
      - (_received_at AT TIME ZONE 'UTC')
    )) / 60
  )::integer;

  INSERT INTO private.alert_shadow_coverage_leases (
    user_id, event_id, client_id, channel, collector_contract, collector_state,
    capability_sha256, observed_at, received_at, app_version, timezone,
    utc_offset_minutes
  ) VALUES (
    _user_id, _event_id, trim(_client_id), _channel, _collector_contract,
    _collector_state, _capability_sha256, _observed_at, _received_at,
    _app_version, _timezone, _utc_offset_minutes
  )
  ON CONFLICT (user_id, event_id) DO NOTHING;

  GET DIAGNOSTICS _inserted = ROW_COUNT;
  IF _inserted = 1 THEN
    RETURN 'inserted';
  END IF;
  RETURN 'duplicate';
END;
$function$;

CREATE OR REPLACE FUNCTION private.finalize_alert_shadow_coverage(_user_id uuid, _through_at timestamp with time zone, _retention_days integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET "TimeZone" TO 'UTC'
AS $function$
DECLARE
  _version_id uuid;
  _enabled boolean;
  _accept boolean;
  _configured_retention integer;
  _inserted integer := 0;
  _deleted_leases integer := 0;
  _deleted_intervals integer := 0;
BEGIN
  IF _user_id IS NULL OR _through_at IS NULL THEN
    RAISE EXCEPTION 'coverage finalizer requires user and through_at';
  END IF;

  SELECT c.version_id, c.enabled, c.accept_coverage_leases, c.detail_retention_days
  INTO _version_id, _enabled, _accept, _configured_retention
  FROM private.adaptive_alert_shadow_runtime_config AS c
  WHERE c.singleton;

  IF _enabled IS NOT TRUE OR _accept IS NOT TRUE THEN
    RETURN jsonb_build_object('status', 'disabled', 'inserted', 0);
  END IF;
  IF _retention_days IS DISTINCT FROM _configured_retention
     OR _retention_days <> 35 THEN
    RAISE EXCEPTION 'coverage retention must equal configured 35 days';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM public.alert_model_versions AS v
    WHERE v.id = _version_id
      AND v.status = 'shadow'
      AND v.shadow_enabled_at IS NOT NULL
      AND v.shadow_enabled_at <= _through_at
  ) THEN
    RAISE EXCEPTION 'coverage runtime version is not an enabled shadow version';
  END IF;

  DELETE FROM private.alert_shadow_coverage_leases
  WHERE user_id = _user_id
    AND received_at < _through_at - make_interval(days => _retention_days);
  GET DIAGNOSTICS _deleted_leases = ROW_COUNT;

  DELETE FROM public.alert_observation_coverage_intervals
  WHERE user_id = _user_id
    AND ends_at < _through_at - make_interval(days => _retention_days);
  GET DIAGNOSTICS _deleted_intervals = ROW_COUNT;

  WITH ordered AS (
    SELECT
      l.*,
      lag(l.received_at) OVER (
        PARTITION BY
          l.user_id, l.client_id, l.channel, l.collector_contract,
          l.collector_state, l.capability_sha256, l.app_version,
          l.timezone, l.utc_offset_minutes
        ORDER BY l.received_at, l.event_id
      ) AS previous_received_at
    FROM private.alert_shadow_coverage_leases AS l
    WHERE l.user_id = _user_id
      AND l.received_at <= _through_at
  ), intervals AS (
    SELECT
      o.*,
      extract(epoch FROM (o.received_at - o.previous_received_at)) / 60.0
        AS gap_minutes,
      CASE
        WHEN o.channel = 'tauri' THEN 12
        WHEN o.channel = 'android-apk' THEN 35
        WHEN o.channel = 'ios-app' THEN 35
      END AS allowed_gap_minutes
    FROM ordered AS o
    WHERE o.previous_received_at IS NOT NULL
      AND o.received_at > o.previous_received_at
  ), prepared AS (
    SELECT
      _version_id AS version_id,
      i.user_id,
      i.previous_received_at AS starts_at,
      i.received_at AS ends_at,
      i.timezone,
      i.utc_offset_minutes,
      CASE WHEN i.gap_minutes <= i.allowed_gap_minutes
        THEN 'valid' ELSE 'unknown' END AS coverage_state,
      i.received_at AS captured_at,
      _through_at AS finalized_at,
      encode(
        extensions.digest(
          jsonb_build_object(
            'version_id', _version_id,
            'user_id', i.user_id,
            'client_id', i.client_id,
            'channel', i.channel,
            'collector_contract', i.collector_contract,
            'collector_state', i.collector_state,
            'starts_at_utc', to_char(
              i.previous_received_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
            'ends_at_utc', to_char(
              i.received_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
            'capability_sha256', i.capability_sha256,
            'app_version', i.app_version,
            'timezone', i.timezone,
            'utc_offset_minutes', i.utc_offset_minutes,
            'coverage_state', CASE
              WHEN i.gap_minutes <= i.allowed_gap_minutes
                THEN 'valid' ELSE 'unknown'
            END,
            'evidence_version', 'coverage-lease-v1'
          )::text,
          'sha256'
        ),
        'hex'
      ) AS provenance_sha256
    FROM intervals AS i
  )
  INSERT INTO public.alert_observation_coverage_intervals (
    version_id, user_id, starts_at, ends_at, timezone, utc_offset_minutes,
    activity_coverage_state, intervention_coverage_state, sleep_context_state,
    captured_at, finalized_at, evidence_version, provenance_sha256
  )
  SELECT
    p.version_id, p.user_id, p.starts_at, p.ends_at, p.timezone,
    p.utc_offset_minutes, p.coverage_state,
    CASE WHEN p.coverage_state = 'valid' THEN 'valid' ELSE 'unknown' END,
    CASE WHEN p.coverage_state = 'valid' THEN 'valid' ELSE 'unknown' END,
    p.captured_at, p.finalized_at, 'coverage-lease-v1', p.provenance_sha256
  FROM prepared AS p
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.alert_observation_coverage_intervals AS existing
    WHERE existing.version_id = p.version_id
      AND existing.user_id = p.user_id
      AND existing.starts_at = p.starts_at
      AND existing.ends_at = p.ends_at
      AND existing.provenance_sha256 = p.provenance_sha256
  );
  GET DIAGNOSTICS _inserted = ROW_COUNT;

  RETURN jsonb_build_object(
    'status', 'completed',
    'inserted', _inserted,
    'deleted_leases', _deleted_leases,
    'deleted_intervals', _deleted_intervals,
    'through_at', _through_at,
    'retention_days', _retention_days
  );
END;
$function$;

-- iOS can now report, so it joins the platforms whose silence is meaningful.
-- Until the iOS build carrying the reporter is actually installed, an iOS user
-- produces no leases and therefore no valid coverage, which reads as `unknown`
-- on their own card and prompts nobody. That is the correct reading of a
-- capable platform that has not spoken yet.
CREATE OR REPLACE FUNCTION private.coverage_capable_subject(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT coalesce((
    SELECT c.platform IN ('android-apk', 'tauri', 'ios-app')
    FROM public.clients AS c
    WHERE c.user_id = _user_id
    ORDER BY c.last_seen_at DESC
    LIMIT 1
  ), false);
$function$;

REVOKE ALL ON FUNCTION private.coverage_capable_subject(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.coverage_capable_subject(uuid) FROM anon, authenticated;

-- The table carries its own guards, and they are the authority: the function
-- above can be replaced by a later migration, the constraints cannot be
-- bypassed at all. Widening them together keeps "what the collector may claim"
-- stated once in SQL rather than twice with a chance to drift.
ALTER TABLE private.alert_shadow_coverage_leases
  DROP CONSTRAINT IF EXISTS alert_shadow_coverage_leases_channel_check,
  DROP CONSTRAINT IF EXISTS alert_shadow_coverage_leases_collector_contract_check,
  DROP CONSTRAINT IF EXISTS alert_shadow_coverage_leases_check;

ALTER TABLE private.alert_shadow_coverage_leases
  ADD CONSTRAINT alert_shadow_coverage_leases_channel_check
    CHECK (channel = ANY (ARRAY['tauri', 'android-apk', 'ios-app'])),
  ADD CONSTRAINT alert_shadow_coverage_leases_collector_contract_check
    CHECK (collector_contract = ANY (ARRAY['tauri-idle-v1', 'android-passive-v1', 'ios-wake-v1'])),
  ADD CONSTRAINT alert_shadow_coverage_leases_check
    CHECK (
      (channel = 'tauri' AND collector_contract = 'tauri-idle-v1')
      OR (channel = 'android-apk' AND collector_contract = 'android-passive-v1')
      OR (channel = 'ios-app' AND collector_contract = 'ios-wake-v1')
    );
