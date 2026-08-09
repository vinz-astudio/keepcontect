-- ADR-0029 P3: preserve every distinct validated behavior event.
--
-- event_id remains the idempotency key. The former user/source/five-minute
-- observation-bucket merge reduced write volume but discarded valid evidence
-- and gave v1/v2 different sampling units. Client collectors own emission-rate
-- control; the shared validator continues to own safety and provenance checks.

CREATE OR REPLACE FUNCTION private.insert_behavior_ping(
  _user_id uuid,
  _event_id uuid,
  _observed_at timestamptz,
  _source text,
  _kind text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _received_at timestamptz := clock_timestamp();
  _is_live_safety boolean;
BEGIN
  IF _user_id IS NULL OR _observed_at IS NULL OR _event_id IS NULL THEN
    RETURN 'invalid';
  END IF;

  IF _source NOT IN (
    'installed_pwa',
    'tauri',
    'capacitor',
    'shortcut',
    'manual',
    'app'
  ) THEN
    RETURN 'invalid';
  END IF;

  IF _kind NOT IN (
    'app',
    'interaction',
    'steps',
    'unlock',
    'manual_checkin'
  ) THEN
    RETURN 'invalid';
  END IF;

  IF _observed_at > _received_at + interval '5 minutes' THEN
    RETURN 'invalid';
  END IF;

  -- Serialize retries for one event before inspecting the idempotency index.
  -- Distinct events intentionally do not serialize by time bucket.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      _user_id::text || ':event:' || _event_id::text,
      0
    )
  );

  IF EXISTS (
    SELECT 1
    FROM public.behavior_pings
    WHERE user_id = _user_id
      AND event_id = _event_id
  ) THEN
    RETURN 'duplicate';
  END IF;

  _is_live_safety := (
    abs(extract(epoch FROM (_received_at - _observed_at))) <= 300
  );

  BEGIN
    INSERT INTO public.behavior_pings (
      user_id,
      event_id,
      at,
      source,
      kind,
      received_at,
      ingest_version
    )
    VALUES (
      _user_id,
      _event_id,
      _observed_at,
      _source,
      _kind,
      _received_at,
      2
    );
  EXCEPTION WHEN unique_violation THEN
    IF EXISTS (
      SELECT 1
      FROM public.behavior_pings
      WHERE user_id = _user_id
        AND event_id = _event_id
    ) THEN
      RETURN 'duplicate';
    END IF;
    RAISE;
  END;

  IF _is_live_safety THEN
    PERFORM private.apply_liveness_side_effects(
      _user_id,
      _observed_at,
      _received_at
    );
  END IF;

  RETURN 'inserted';
END;
$$;

REVOKE EXECUTE ON FUNCTION private.insert_behavior_ping(
  uuid,
  uuid,
  timestamptz,
  text,
  text
) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION private.insert_behavior_ping(
  uuid,
  uuid,
  timestamptz,
  text,
  text
) IS
  'ADR-0029 P3 shared validator: one row per distinct event_id; no time-bucket coalescing.';

