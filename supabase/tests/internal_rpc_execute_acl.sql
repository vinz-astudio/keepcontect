-- Verifies the ACL candidate for the three internal SECURITY DEFINER RPCs.
-- Run only after the candidate ACL statements have been applied to a test DB.
-- No allowed invocation is performed: prune and trigger have side effects, and
-- purge is tested with a nonexistent UUID only through a denied role.
BEGIN;

SELECT plan(21);

SELECT is(EXISTS (
  SELECT 1
  FROM pg_proc AS p
  CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) AS acl
  WHERE p.oid = 'public.purge_user_data(uuid)'::regprocedure
    AND acl.grantee = 0
    AND acl.privilege_type = 'EXECUTE'
), false,
  'PUBLIC cannot execute purge_user_data');
SELECT is(has_function_privilege('anon', 'public.purge_user_data(uuid)', 'EXECUTE'), false,
  'anon cannot execute purge_user_data');
SELECT is(has_function_privilege('authenticated', 'public.purge_user_data(uuid)', 'EXECUTE'), false,
  'authenticated cannot execute purge_user_data');
SELECT is(has_function_privilege('service_role', 'public.purge_user_data(uuid)', 'EXECUTE'), true,
  'service_role can execute purge_user_data');
SELECT is(has_function_privilege('postgres', 'public.purge_user_data(uuid)', 'EXECUTE'), true,
  'postgres can execute purge_user_data');

SELECT is(EXISTS (
  SELECT 1
  FROM pg_proc AS p
  CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) AS acl
  WHERE p.oid = 'public.prune_stale_clients()'::regprocedure
    AND acl.grantee = 0
    AND acl.privilege_type = 'EXECUTE'
), false,
  'PUBLIC cannot execute prune_stale_clients');
SELECT is(has_function_privilege('anon', 'public.prune_stale_clients()', 'EXECUTE'), false,
  'anon cannot execute prune_stale_clients');
SELECT is(has_function_privilege('authenticated', 'public.prune_stale_clients()', 'EXECUTE'), false,
  'authenticated cannot execute prune_stale_clients');
SELECT is(has_function_privilege('service_role', 'public.prune_stale_clients()', 'EXECUTE'), true,
  'service_role can execute prune_stale_clients');
SELECT is(has_function_privilege('postgres', 'public.prune_stale_clients()', 'EXECUTE'), true,
  'postgres can execute prune_stale_clients');

SELECT is(EXISTS (
  SELECT 1
  FROM pg_proc AS p
  CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) AS acl
  WHERE p.oid = 'public.trigger_weekly_routine_updates()'::regprocedure
    AND acl.grantee = 0
    AND acl.privilege_type = 'EXECUTE'
), false,
  'PUBLIC cannot execute trigger_weekly_routine_updates');
SELECT is(has_function_privilege('anon', 'public.trigger_weekly_routine_updates()', 'EXECUTE'), false,
  'anon cannot execute trigger_weekly_routine_updates');
SELECT is(has_function_privilege('authenticated', 'public.trigger_weekly_routine_updates()', 'EXECUTE'), false,
  'authenticated cannot execute trigger_weekly_routine_updates');
SELECT is(has_function_privilege('service_role', 'public.trigger_weekly_routine_updates()', 'EXECUTE'), true,
  'service_role can execute trigger_weekly_routine_updates');
SELECT is(has_function_privilege('postgres', 'public.trigger_weekly_routine_updates()', 'EXECUTE'), true,
  'postgres can execute trigger_weekly_routine_updates');

SET LOCAL ROLE anon;
SELECT throws_ok($$SELECT public.purge_user_data('00000000-0000-0000-0000-000000000000'::uuid)$$,
  '42501'::char(5), NULL, 'anon invocation of purge_user_data is denied');
SELECT throws_ok($$SELECT public.prune_stale_clients()$$,
  '42501'::char(5), NULL, 'anon invocation of prune_stale_clients is denied');
SELECT throws_ok($$SELECT public.trigger_weekly_routine_updates()$$,
  '42501'::char(5), NULL, 'anon invocation of trigger_weekly_routine_updates is denied');

SET LOCAL ROLE authenticated;
SELECT throws_ok($$SELECT public.purge_user_data('00000000-0000-0000-0000-000000000000'::uuid)$$,
  '42501'::char(5), NULL, 'authenticated invocation of purge_user_data is denied');
SELECT throws_ok($$SELECT public.prune_stale_clients()$$,
  '42501'::char(5), NULL, 'authenticated invocation of prune_stale_clients is denied');
SELECT throws_ok($$SELECT public.trigger_weekly_routine_updates()$$,
  '42501'::char(5), NULL, 'authenticated invocation of trigger_weekly_routine_updates is denied');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
