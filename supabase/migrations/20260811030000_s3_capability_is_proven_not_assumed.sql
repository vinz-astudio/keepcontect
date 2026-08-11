-- S3-F · A platform is capable when it has proven it, not when we assume it.
--
-- The previous gate asked which platform someone is currently running and
-- treated `ios-app` as capable the moment iOS gained a collector. That is true
-- of the code and false of the installs: the build carrying the reporter has
-- not shipped yet, so an iOS user on 0.5.x reports nothing, looks stale, and
-- would be told to go and fix their permissions — the exact wrong-blame this
-- gate was added to prevent, arriving one step later by a different route.
--
-- Checked against production while writing this: the account on `ios-app` had
-- last valid coverage 175 hours ago, so it would have been prompted.
--
-- Version bookkeeping would fix it and then rot — every future platform and
-- every backport becomes another number to remember. So capability is proven
-- by evidence instead: this person has produced at least one lease from the
-- channel they are on now. An install that can report says so within minutes
-- of first launch, and one that cannot never claims it can.
--
-- It is also self-correcting for the two platforms still unshipped. Tauri and
-- iOS become judgeable the moment their builds actually land on a device, with
-- no migration, no flag, and nobody trusted in advance.

CREATE OR REPLACE FUNCTION private.coverage_capable_subject(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH current_platform AS (
    SELECT c.platform
    FROM public.clients AS c
    WHERE c.user_id = _user_id
    ORDER BY c.last_seen_at DESC
    LIMIT 1
  )
  SELECT EXISTS (
    SELECT 1
    FROM current_platform AS p
    JOIN private.alert_shadow_coverage_leases AS l
      ON l.user_id = _user_id
     AND l.channel = p.platform
    WHERE p.platform IN ('android-apk', 'tauri', 'ios-app')
  );
$function$;

COMMENT ON FUNCTION private.coverage_capable_subject(uuid) IS
  'Whether this person is on a channel that has actually reported coverage for '
  'them at least once. Proven, not assumed: an install that cannot report must '
  'never be told its silence is a fault of the person holding it.';

REVOKE ALL ON FUNCTION private.coverage_capable_subject(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.coverage_capable_subject(uuid) FROM anon, authenticated;
