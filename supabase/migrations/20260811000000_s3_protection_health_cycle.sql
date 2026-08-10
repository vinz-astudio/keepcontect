-- S3-D · Connect the protection-health chain to something that runs it.
--
-- 20260810010000 built private.evaluate_protection_health, and 20260810020000
-- built private.dispatch_special_attention_notices. Both were correct and
-- tested. Neither was ever called: no cron job, no function, no edge function
-- referenced them. In production that left
--
--   protection_health_incidents  0 rows
--   special_attention_notices    0 rows
--
-- while coverage intervals kept arriving normally. my_protection_health
-- survives that because it derives ready/unknown straight from coverage, so
-- the card was never wrong — but it could never reach `limited`, and Special
-- Attention was inert end to end: a subscriber could switch it on and no
-- notice could ever be produced, because the dispatcher requires an incident
-- with prompted_at set and nothing opened incidents or set prompted_at.
--
-- Who prompts the subject matters, and it cannot be the client. The failure
-- this feature exists to catch is "the app is no longer watching" — precisely
-- the state in which the app cannot render a card, so a client-set prompted_at
-- deadlocks on its own main case. ADR-0040 revision one already settled the
-- direction: when the watcher is not reporting, the server reaches for the
-- subject. So the prompt is a notification the server writes, and prompted_at
-- is the moment it did.
--
-- Order inside one cycle is deliberate: evaluate, then prompt, then dispatch.
-- Dispatch reads prompted_at from an earlier cycle, never the one just set,
-- because the grace period is the subject's chance to fix it themselves before
-- anyone else is told.

CREATE OR REPLACE FUNCTION private.prompt_protection_health_subjects()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
SET "TimeZone" TO 'UTC'
AS $function$
DECLARE
  _prompted integer := 0;
  _row record;
BEGIN
  FOR _row IN
    SELECT h.id, h.user_id
    FROM public.protection_health_incidents AS h
    WHERE h.closed_at IS NULL
      AND h.recovered_at IS NULL
      AND h.prompted_at IS NULL
  LOOP
    -- The subject is told about their own protection, never about themselves.
    -- means_danger = false keeps this out of every emergency path on the
    -- client, the same machine-readable flag the subscriber notice carries.
    INSERT INTO public.notifications (recipient_id, alert_id, kind, body, params)
    VALUES (
      _row.user_id,
      NULL,
      'protection_limited',
      '守护可能没有在正常运作。请打开 App 检查权限与后台运行,这不代表你出了事。',
      jsonb_build_object(
        'i18n_key', 'notif.protection_limited',
        'incident_id', _row.id,
        'means_danger', false
      )
    );

    UPDATE public.protection_health_incidents
    SET prompted_at = now()
    WHERE id = _row.id;

    _prompted := _prompted + 1;
  END LOOP;

  RETURN jsonb_build_object('prompted', _prompted);
END;
$function$;

COMMENT ON FUNCTION private.prompt_protection_health_subjects() IS
  'ADR-0039/0040: the server prompts the subject, because an app that has '
  'stopped watching cannot prompt them itself.';

CREATE OR REPLACE FUNCTION private.run_protection_health_cycle(
  _grace interval DEFAULT interval '2 hours'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
SET "TimeZone" TO 'UTC'
AS $function$
DECLARE
  _subject uuid;
  _evaluated integer := 0;
  _failed integer := 0;
  _result jsonb;
  _prompted jsonb;
  _dispatched jsonb;
BEGIN
  IF _grace IS NULL OR _grace < interval '0' THEN
    RAISE EXCEPTION 'run_protection_health_cycle: invalid grace';
  END IF;

  -- Evaluate anyone this feature can say anything about: people who have ever
  -- produced coverage, plus anyone already carrying an open incident so their
  -- recovery is still noticed after their intervals age out.
  FOR _subject IN
    SELECT i.user_id FROM public.alert_observation_coverage_intervals AS i
    UNION
    SELECT h.user_id FROM public.protection_health_incidents AS h
    WHERE h.closed_at IS NULL
  LOOP
    -- Per-subject isolation, for the same reason the alert path has it: one
    -- unevaluable account must not stop everyone else from being evaluated.
    BEGIN
      PERFORM private.evaluate_protection_health(_subject);
      _evaluated := _evaluated + 1;
    EXCEPTION WHEN OTHERS THEN
      _failed := _failed + 1;
      INSERT INTO private.job_failures (job_name, subject_id, sqlstate, message, context)
      VALUES ('protection-health-cycle-v1', _subject, SQLSTATE, SQLERRM,
              'evaluate_protection_health');
    END;
  END LOOP;

  _prompted := private.prompt_protection_health_subjects();
  _dispatched := private.dispatch_special_attention_notices(_grace);

  _result := jsonb_build_object(
    'evaluated', _evaluated,
    'failed', _failed,
    'prompted', _prompted -> 'prompted',
    'notices_sent', _dispatched -> 'notices_sent',
    'grace', _grace
  );

  RETURN _result;
END;
$function$;

COMMENT ON FUNCTION private.run_protection_health_cycle(interval) IS
  'Evaluate every coverage subject, prompt newly limited ones, then notify '
  'their special-attention subscribers once the grace period has passed.';

REVOKE ALL ON FUNCTION private.prompt_protection_health_subjects() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.prompt_protection_health_subjects() FROM anon, authenticated;
REVOKE ALL ON FUNCTION private.run_protection_health_cycle(interval) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.run_protection_health_cycle(interval) FROM anon, authenticated;

-- Every half hour. The 26-hour staleness window means nothing here is urgent,
-- and a half-hourly cycle keeps the subject's prompt close to the moment their
-- coverage actually lapsed without polling the table pointlessly.
SELECT cron.unschedule('protection-health-cycle-v1')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'protection-health-cycle-v1');

SELECT cron.schedule(
  'protection-health-cycle-v1',
  '*/30 * * * *',
  $job$select private.run_protection_health_cycle();$job$
);

-- A job with no staleness expectation can stop running and still be reported
-- healthy, which is the exact failure this whole feature exists to surface.
-- scheduled_job_health.sql asserts every job has one; registering it here keeps
-- that assertion honest rather than making it step around a new exception.
INSERT INTO private.scheduled_job_expectations (job_name, max_gap, matters_because)
VALUES (
  'protection-health-cycle-v1',
  interval '2 hours',
  'Nobody is told their protection stopped working, and no watcher is told either. '
  'The feature does not fail loudly if this job stops — it goes quiet, which is '
  'indistinguishable from everyone being fine.'
)
ON CONFLICT (job_name) DO UPDATE
  SET max_gap = EXCLUDED.max_gap,
      matters_because = EXCLUDED.matters_because;
