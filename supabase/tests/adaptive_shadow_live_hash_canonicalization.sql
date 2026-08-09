-- ADR-0028: live-definition identity must not depend on CRLF/LF storage.
BEGIN;
SELECT plan(6);

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
      'c3efc6cc664dc334166a034651ff584d4c7766d80775c3fe3bc012eb97a9b150',
      _definition
    ) IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'LF production representation was rejected';
    END IF;
  END;
  $body$;
  $test$,
  'authorized pin accepts the identical LF production definition'
);

SELECT lives_ok(
  $test$
  DO $body$
  BEGIN
    IF private.shadow_live_definition_matches(
      'c3efc6cc664dc334166a034651ff584d4c7766d80775c3fe3bc012eb97a9b150',
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
  'c3efc6cc664dc334166a034651ff584d4c7766d80775c3fe3bc012eb97a9b150',
  'normalized live threshold matches the authorized account-bound definition'
);

-- The 2026-08-04 ADR-0037 rewrite of private.silence_threshold shipped without
-- re-authorizing the shadow config pin, so the evaluator fail-closed on every
-- run. This guard makes that drift impossible to repeat silently: the config
-- authority must always name the current live definition.
SELECT ok(
  strpos(
    pg_get_functiondef('private.alert_candidate_config_is_valid(jsonb)'::regprocedure),
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
    )
  ) > 0,
  'authorized config pin tracks the current live threshold definition'
);

SELECT * FROM finish();
ROLLBACK;
