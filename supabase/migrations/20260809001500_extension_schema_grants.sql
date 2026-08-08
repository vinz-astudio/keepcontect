-- The baseline dumped public and private, which is where our own objects live,
-- but the extensions put their objects in schemas of their own - cron, net,
-- extensions - and the grants on those schemas came with them. A dump scoped to
-- our two schemas carries none of that.
--
-- Found by the test suite rather than by a schema diff: routine_safety aborted
-- at line 294 with "permission denied for schema cron". A diff compares the two
-- schemas it was asked about and says nothing about a third, so a database
-- rebuilt from the baseline alone looked correct and could not read its own
-- scheduled jobs.
--
-- On production every one of these is already true and this migration changes
-- nothing; it exists so that a database built from scratch matches.

-- pg_cron. Production grants postgres USAGE with grant option. Without it,
-- nothing outside supabase_admin can read cron.job or cron.job_run_details -
-- which is what private.scheduled_job_health() reads, so the watchdog itself
-- would be blind in a rebuilt database.
-- Granted without WITH GRANT OPTION. Production's copy carries it because
-- supabase_admin was the grantor there; locally this file runs as postgres, and
-- Postgres refuses to let a role hand grant options back to its own grantor.
-- The usage itself is what matters and is identical either way.
grant usage on schema cron to postgres;

-- Production also lets PUBLIC read the two cron tables
-- (cron.job carries =r/supabase_admin, cron.job_run_details carries =rd).
-- Anything running as service_role - which is what the test suite switches to,
-- and what an Edge Function runs as - can therefore see which jobs exist and
-- whether they ran. Without this a rebuilt database denies that read, which is
-- how routine_safety aborted at line 294.
grant usage on schema cron to public;
grant select on cron.job to public;
grant select, delete on cron.job_run_details to public;

-- pg_net. The Edge Function dispatch jobs call net.http_post.
grant usage on schema net to postgres, anon, authenticated, service_role;

-- The extensions schema holds uuid-ossp, pgcrypto and pg_stat_statements.
grant usage on schema extensions to anon, authenticated, service_role;
