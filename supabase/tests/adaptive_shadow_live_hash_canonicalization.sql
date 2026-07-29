-- ADR-0028: live-definition identity must not depend on CRLF/LF storage.
BEGIN;
SELECT plan(5);

SELECT has_function(
  'private',
  'shadow_live_definition_matches',
  ARRAY['text', 'text'],
  'shadow live-definition matcher exists'
);

SELECT lives_ok(
  $test$
  DO $body$
  DECLARE
    _definition text := replace(
      pg_get_functiondef('private.silence_threshold(uuid)'::regprocedure),
      E'\r\n',
      E'\n'
    );
  BEGIN
    IF private.shadow_live_definition_matches(
      '1907d59473d274d46a0e8e0b9ce8027037b4494b0dddf073cb46abf67db92e21',
      _definition
    ) IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'LF production representation was rejected';
    END IF;
  END;
  $body$;
  $test$,
  'legacy CRLF model pin accepts the identical LF production definition'
);

SELECT lives_ok(
  $test$
  DO $body$
  BEGIN
    IF private.shadow_live_definition_matches(
      '1907d59473d274d46a0e8e0b9ce8027037b4494b0dddf073cb46abf67db92e21',
      pg_get_functiondef('private.silence_threshold(uuid)'::regprocedure)
        || E'\n-- tampered'
    ) IS DISTINCT FROM false THEN
      RAISE EXCEPTION 'tampered definition was accepted';
    END IF;
  END;
  $body$;
  $test$,
  'unknown live definition remains fail-closed'
);

SELECT ok(
  pg_get_functiondef(
    'private.run_adaptive_alert_shadow_cycle(uuid,timestamptz)'::regprocedure
  ) ~ 'shadow_live_definition_matches',
  'operational cycle uses the canonical matcher'
);

SELECT is(
  encode(
    extensions.digest(
      replace(
        pg_get_functiondef('private.silence_threshold(uuid)'::regprocedure),
        E'\r\n',
        E'\n'
      ),
      'sha256'
    ),
    'hex'
  ),
  '6be4ed54feff52428cf1d86210126bd9362953201fc5ac8b9e885abd586092ce',
  'normalized live threshold matches the authorized history-seeded definition'
);

SELECT * FROM finish();
ROLLBACK;
