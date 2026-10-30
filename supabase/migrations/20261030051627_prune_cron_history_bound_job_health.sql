-- Production stopped answering on 2026-10-30 at about 04:00 UTC and stayed down
-- for 45 minutes. The instance is a 0.5 GB Nano. Two thirds of its 295 MB of data
-- was one table, cron.job_run_details: 782,000 rows back to 2026-06-10, never
-- pruned, with a single index on runid.
--
-- private.scheduled_job_health() read that table about forty times per call: once
-- in the join, and twice more per job in correlated subqueries. The
-- scheduled-job-health job calls it every 30 minutes, and every call was
-- cancelled by the statement timeout after about two minutes (the last twelve in
-- a row), each time pulling a table bigger than the cache through the cache. The
-- watchdog never finished, so it never reported anything. The 04:00 run lasted
-- 191 s and was the only long job running when the instance stopped answering.
-- That makes it the strongest candidate for the cause, not a proven one.
--
-- Two changes, so that neither half can bring the problem back alone:
--   1. The history is pruned daily to 7 days.
--   2. The health check reads that same 7 days once, instead of the whole table
--      forty times. The longest expectation is 36 hours, so nothing it judges
--      lives outside the window. Keep the two 7-day figures equal: a shorter
--      prune would blind the check to older runs, a longer one just wastes rows.

create or replace function private.scheduled_job_health()
returns table (
  job_name          text,
  healthy           boolean,
  problem           text,
  last_run_at       timestamptz,
  last_success_at   timestamptz,
  consecutive_fails integer,
  subjects_skipped  integer,
  matters_because   text
)
language sql
security definer
set search_path to ''
stable
as $function$
  -- Referenced more than once, so Postgres materialises it: one pass over the
  -- history, however many jobs there are. Matches the 7-day prune below.
  with recent as (
    select d.jobid, d.start_time, d.status
    from cron.job_run_details AS d
    where d.start_time > now() - interval '7 days'
  ), per_job as (
    select
      r.jobid,
      max(r.start_time)                                          as last_run_at,
      max(r.start_time) filter (where r.status = 'succeeded')     as last_success_at
    from recent AS r
    group by r.jobid
  ), runs as (
    select
      j.jobname,
      p.last_run_at,
      p.last_success_at,
      (
        select count(*)::integer
        from recent AS r
        where r.jobid = j.jobid
          and r.start_time > coalesce(p.last_success_at, '-infinity'::timestamptz)
          and r.status = 'failed'
      )                                                          as consecutive_fails
    from cron.job AS j
    left join per_job AS p on p.jobid = j.jobid
  ), skipped as (
    select f.job_name, count(*)::integer as n
    from private.job_failures AS f
    where f.failed_at > now() - interval '48 hours'
    group by f.job_name
  )
  select
    runs.jobname,
    -- coalesce to false, not to NULL. A job that has never succeeded has a
    -- NULL last_success_at, and an unknown verdict would be dropped by the
    -- reporter's WHERE NOT healthy - so the one case where a job never ran at
    -- all would be the one case the watchdog stayed quiet about.
    coalesce(
      runs.consecutive_fails = 0
      and coalesce(skipped.n, 0) = 0
      and (expect.max_gap is null
           or runs.last_success_at > now() - expect.max_gap)
    , false)                                                       as healthy,
    case
      when runs.consecutive_fails > 0
        then format('last %s run(s) failed', runs.consecutive_fails)
      when expect.max_gap is not null
       and (runs.last_success_at is null
            or runs.last_success_at <= now() - expect.max_gap)
        then format('no successful run since %s, expected every %s',
                    coalesce(runs.last_success_at::text, 'ever'), expect.max_gap)
      when coalesce(skipped.n, 0) > 0
        then format('%s subject(s) skipped in the last 48 hours', skipped.n)
      else null
    end                                                            as problem,
    runs.last_run_at,
    runs.last_success_at,
    runs.consecutive_fails,
    coalesce(skipped.n, 0),
    coalesce(expect.matters_because, 'No expectation recorded; checked for outright failure only.')
  from runs
  left join private.scheduled_job_expectations AS expect on expect.job_name = runs.jobname
  left join skipped on skipped.job_name = runs.jobname
  order by runs.jobname;
$function$;

-- Daily, off the minute that every other job fires on. The delete has no index to
-- use, which is fine: after the first run the table is a week long.
select cron.schedule(
  'prune-cron-run-details',
  '47 3 * * *',
  $job$delete from cron.job_run_details where start_time < now() - interval '7 days'$job$
);

-- Without this the job would be the one scheduled thing the watchdog could not
-- see stop.
insert into private.scheduled_job_expectations (job_name, max_gap, matters_because) values
  ('prune-cron-run-details', interval '36 hours',
   'The job history grows without bound and the watchdog reads it. If pruning stops, the watchdog slows back toward the timeout it hit on 2026-10-30.')
on conflict (job_name) do update
  set max_gap = excluded.max_gap,
      matters_because = excluded.matters_because;
