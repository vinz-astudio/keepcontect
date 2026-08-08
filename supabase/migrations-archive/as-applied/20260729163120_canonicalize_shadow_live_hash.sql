-- ADR-0028 compatibility repair: pg_get_functiondef() preserves the line
-- endings stored in prosrc. Windows replay therefore pinned the CRLF byte
-- representation while production stores the same function body with LF.
-- Treat only those two known representations as equivalent; all other live
-- definitions remain fail-closed.

CREATE FUNCTION private.shadow_live_definition_matches(
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
        AND hashes.lf_sha256 =
          '686116ef8f2df1d78f6d0d48ded8019555f283b098eeb5d354cfa1c14ebbcdca'
      )
  END
  FROM hashes
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.shadow_live_definition_matches(text,text)
FROM PUBLIC, anon, authenticated, service_role;

DO $$
DECLARE
  _definition text := replace(
    pg_get_functiondef(
      'private.run_adaptive_alert_shadow_cycle(uuid,timestamptz)'::regprocedure
    ),
    E'\r\n',
    E'\n'
  );
  _before text := replace(
    $fragment$
  IF _version.config #>> '{emergency,expected_live_definition_sha256}'
     <> encode(extensions.digest(pg_get_functiondef(
       'private.silence_threshold(uuid)'::regprocedure
     ), 'sha256'), 'hex') THEN
    RAISE EXCEPTION 'shadow_live_hash_mismatch';
  END IF;
$fragment$,
    E'\r\n',
    E'\n'
  );
  _after text := replace(
    $fragment$
  IF NOT private.shadow_live_definition_matches(
    _version.config #>> '{emergency,expected_live_definition_sha256}',
    pg_get_functiondef('private.silence_threshold(uuid)'::regprocedure)
  ) THEN
    RAISE EXCEPTION 'shadow_live_hash_mismatch';
  END IF;
$fragment$,
    E'\r\n',
    E'\n'
  );
BEGIN
  IF _definition IS NULL
     OR length(_definition) - length(replace(_definition, _before, ''))
        <> length(_before) THEN
    RAISE EXCEPTION 'shadow_live_hash_patch_source_mismatch';
  END IF;

  EXECUTE replace(_definition, _before, _after);
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.run_adaptive_alert_shadow_cycle(uuid,timestamptz)
FROM PUBLIC, anon, authenticated, service_role;

