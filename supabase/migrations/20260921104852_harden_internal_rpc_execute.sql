-- Restrict internal RPCs to trusted server/scheduler callers. Production apply requires approval.
-- Preserve function definitions, owners, default privileges, and cron schedules.
BEGIN;

REVOKE EXECUTE ON FUNCTION public.purge_user_data(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.purge_user_data(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.purge_user_data(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.purge_user_data(uuid) TO service_role;

REVOKE EXECUTE ON FUNCTION public.prune_stale_clients() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.prune_stale_clients() FROM anon;
REVOKE EXECUTE ON FUNCTION public.prune_stale_clients() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.prune_stale_clients() TO service_role;

REVOKE EXECUTE ON FUNCTION public.trigger_weekly_routine_updates() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trigger_weekly_routine_updates() FROM anon;
REVOKE EXECUTE ON FUNCTION public.trigger_weekly_routine_updates() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.trigger_weekly_routine_updates() TO service_role;

COMMIT;

