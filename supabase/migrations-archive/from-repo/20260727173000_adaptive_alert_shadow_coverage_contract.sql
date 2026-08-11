-- ADR-0028: default-disabled, source-identified production-shadow coverage leases.
-- This migration creates no scheduler, trigger, notification, or live-alert write.

CREATE TABLE private.adaptive_alert_shadow_runtime_config (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  version_id uuid NULL REFERENCES public.alert_model_versions(id) ON DELETE RESTRICT,
  enabled boolean NOT NULL DEFAULT false,
  accept_coverage_leases boolean NOT NULL DEFAULT false,
  max_population integer NOT NULL DEFAULT 10000
    CHECK (max_population BETWEEN 1 AND 10000),
  detail_retention_days integer NOT NULL DEFAULT 35
    CHECK (detail_retention_days = 35),
  cycle_timeout_seconds integer NOT NULL DEFAULT 120
    CHECK (cycle_timeout_seconds = 120),
  max_consecutive_failures integer NOT NULL DEFAULT 3
    CHECK (max_consecutive_failures = 3),
  consecutive_failures integer NOT NULL DEFAULT 0
    CHECK (consecutive_failures BETWEEN 0 AND 3),
  last_failure_code text NULL,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

INSERT INTO private.adaptive_alert_shadow_runtime_config(singleton)
VALUES (true);

CREATE TABLE private.alert_shadow_coverage_leases (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  event_id uuid NOT NULL,
  client_id text NOT NULL CHECK (length(trim(client_id)) BETWEEN 1 AND 64),
  channel text NOT NULL CHECK (channel IN ('tauri', 'android-apk')),
  collector_contract text NOT NULL
    CHECK (collector_contract IN ('tauri-idle-v1', 'android-passive-v1')),
  collector_state text NOT NULL CHECK (collector_state = 'operational'),
  capability_sha256 text NOT NULL CHECK (capability_sha256 ~ '^[a-f0-9]{64}$'),
  observed_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  app_version text NOT NULL CHECK (length(trim(app_version)) BETWEEN 1 AND 32),
  timezone text NOT NULL CHECK (length(trim(timezone)) > 0),
  utc_offset_minutes integer NOT NULL CHECK (utc_offset_minutes BETWEEN -840 AND 840),
  PRIMARY KEY (user_id, event_id),
  CHECK (
    (channel = 'tauri' AND collector_contract = 'tauri-idle-v1')
    OR
    (channel = 'android-apk' AND collector_contract = 'android-passive-v1')
  )
);

CREATE INDEX alert_shadow_coverage_leases_user_received_idx
  ON private.alert_shadow_coverage_leases (user_id, received_at, event_id);

ALTER TABLE private.adaptive_alert_shadow_runtime_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.alert_shadow_coverage_leases ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON TABLE
  private.adaptive_alert_shadow_runtime_config,
  private.alert_shadow_coverage_leases
FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.record_alert_shadow_coverage_lease_core(
  _user_id uuid,
  _client_id text,
  _channel text,
  _collector_contract text,
  _collector_state text,
  _capability_sha256 text,
  _observed_at timestamptz,
  _event_id uuid
)
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET timezone = 'UTC'
AS $$
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
  IF _channel NOT IN ('tauri', 'android-apk') THEN RETURN 'unsupported'; END IF;
  IF (
    _channel = 'tauri' AND _collector_contract <> 'tauri-idle-v1'
  ) OR (
    _channel = 'android-apk' AND _collector_contract <> 'android-passive-v1'
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
    _channel = 'android-apk' AND _platform IS DISTINCT FROM 'android'
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
$$;

CREATE FUNCTION public.record_alert_shadow_coverage_lease(
  _client_id text,
  _channel text,
  _collector_contract text,
  _collector_state text,
  _capability_sha256 text,
  _observed_at timestamptz,
  _event_id uuid
)
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET timezone = 'UTC'
AS $$
BEGIN
  RETURN private.record_alert_shadow_coverage_lease_core(
    auth.uid(),
    _client_id,
    _channel,
    _collector_contract,
    _collector_state,
    _capability_sha256,
    _observed_at,
    _event_id
  );
END;
$$;

CREATE FUNCTION public.record_alert_shadow_coverage_lease_for_user(
  _user_id uuid,
  _client_id text,
  _channel text,
  _collector_contract text,
  _collector_state text,
  _capability_sha256 text,
  _observed_at timestamptz,
  _event_id uuid
)
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET timezone = 'UTC'
AS $$
BEGIN
  RETURN private.record_alert_shadow_coverage_lease_core(
    _user_id,
    _client_id,
    _channel,
    _collector_contract,
    _collector_state,
    _capability_sha256,
    _observed_at,
    _event_id
  );
END;
$$;

CREATE FUNCTION private.finalize_alert_shadow_coverage(
  _user_id uuid,
  _through_at timestamptz,
  _retention_days integer
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET timezone = 'UTC'
AS $$
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
$$;

REVOKE ALL ON FUNCTION
  private.record_alert_shadow_coverage_lease_core(
    uuid,text,text,text,text,text,timestamptz,uuid
  ),
  public.record_alert_shadow_coverage_lease(
    text,text,text,text,text,timestamptz,uuid
  ),
  public.record_alert_shadow_coverage_lease_for_user(
    uuid,text,text,text,text,text,timestamptz,uuid
  ),
  private.finalize_alert_shadow_coverage(uuid,timestamptz,integer)
FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.record_alert_shadow_coverage_lease(
  text,text,text,text,text,timestamptz,uuid
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.record_alert_shadow_coverage_lease_for_user(
  uuid,text,text,text,text,text,timestamptz,uuid
) TO service_role;
