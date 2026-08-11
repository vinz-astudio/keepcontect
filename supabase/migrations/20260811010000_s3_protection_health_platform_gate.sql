-- S3-D2 · Only claim protection is broken where we could have observed it.
--
-- Checked against production before writing this: of eleven accounts, exactly
-- two have ever produced a coverage interval. Coverage leases come only from
-- the Android passive collector today, so every account on iOS or the web is
-- permanently unobservable — not broken, unobservable.
--
-- Without this gate the first cycle would have sent exactly one notification,
-- to a person who is using the app normally. Their coverage stopped on
-- 2026-08-03 because they moved from the APK to the iOS app, and iOS emits no
-- leases at all. The message would have told an active user to open the app
-- and check their permissions and background activity, about a gap they cannot
-- close, because it is ours and not theirs.
--
-- ADR-0040 revision one already says it: a channel that cannot report its state
-- is `unknown`, and unknown is not the subject's failure. This applies that to
-- the prompt. Unobservable subjects stay `unknown` on their own card, which is
-- honest and visible, and nobody is pushed a chore they cannot do.
--
-- The gate reads the platform of the most recently seen client, not whether
-- that client reported recently. Recency would invert the feature: an app that
-- has been killed stops calling report_client too, so "reported lately" goes
-- false exactly when protection actually breaks. What the person is running is
-- stable; whether it has checked in is the thing being judged.

CREATE OR REPLACE FUNCTION private.coverage_capable_subject(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT coalesce((
    SELECT c.platform IN ('android-apk', 'tauri')
    FROM public.clients AS c
    WHERE c.user_id = _user_id
    ORDER BY c.last_seen_at DESC
    LIMIT 1
  ), false);
$function$;

COMMENT ON FUNCTION private.coverage_capable_subject(uuid) IS
  'Whether this person is currently running a client that can report coverage '
  'at all. Judged by which platform they last used, never by how recently it '
  'checked in — a killed app stops checking in, which is the case being judged.';

REVOKE ALL ON FUNCTION private.coverage_capable_subject(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.coverage_capable_subject(uuid) FROM anon, authenticated;

-- An incident means "the protection that was working has stopped". On a
-- platform that never could report, nothing stopped, so no incident opens and
-- no subscriber notice can follow from one.
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
  _skipped integer := 0;
  _failed integer := 0;
  _prompted jsonb;
  _dispatched jsonb;
BEGIN
  IF _grace IS NULL OR _grace < interval '0' THEN
    RAISE EXCEPTION 'run_protection_health_cycle: invalid grace';
  END IF;

  FOR _subject IN
    SELECT i.user_id FROM public.alert_observation_coverage_intervals AS i
    UNION
    SELECT h.user_id FROM public.protection_health_incidents AS h
    WHERE h.closed_at IS NULL
  LOOP
    BEGIN
      IF private.coverage_capable_subject(_subject) THEN
        PERFORM private.evaluate_protection_health(_subject);
        _evaluated := _evaluated + 1;
      ELSE
        -- Someone who moved to a channel that cannot report should not be left
        -- carrying an open incident from the channel they left.
        UPDATE public.protection_health_incidents
        SET closed_at = now(),
            recovered_at = now(),
            recovery_evidence = jsonb_build_object(
              'basis', 'subject moved to a channel that cannot report coverage',
              'closed_by', 'coverage_capable_subject'
            )
        WHERE user_id = _subject AND closed_at IS NULL;
        _skipped := _skipped + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      _failed := _failed + 1;
      INSERT INTO private.job_failures (job_name, subject_id, sqlstate, message, context)
      VALUES ('protection-health-cycle-v1', _subject, SQLSTATE, SQLERRM,
              'evaluate_protection_health');
    END;
  END LOOP;

  _prompted := private.prompt_protection_health_subjects();
  _dispatched := private.dispatch_special_attention_notices(_grace);

  RETURN jsonb_build_object(
    'evaluated', _evaluated,
    'skipped_unobservable', _skipped,
    'failed', _failed,
    'prompted', _prompted -> 'prompted',
    'notices_sent', _dispatched -> 'notices_sent',
    'grace', _grace
  );
END;
$function$;

REVOKE ALL ON FUNCTION private.run_protection_health_cycle(interval) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.run_protection_health_cycle(interval) FROM anon, authenticated;
