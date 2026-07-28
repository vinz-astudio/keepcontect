-- ADR-0028 compatibility repair: clients.platform uses the canonical
-- base-kind channel emitted by clientChannel(), namely android-apk.
-- Append-only function replacement; no scheduler, notification, activity, or live-alert write.

CREATE OR REPLACE FUNCTION private.record_alert_shadow_coverage_lease_core(
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
    _channel = 'android-apk' AND _platform IS DISTINCT FROM 'android-apk'
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
