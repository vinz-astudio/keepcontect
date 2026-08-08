-- The nightly rebuild failed four nights running and nothing said so. It was
-- found by accident while investigating something else.
--
-- That is the same failure this product exists to prevent, turned inward: Keep
-- Contact's whole premise is that silence needs to be noticed, and its own
-- scheduled work went silent for four nights unnoticed. Isolating failures per
-- subject (20260808230000) stops one account taking down the rest, but on its
-- own it makes the problem quieter, not louder - a skipped account leaves a row
-- that nobody reads. Detection has to exist for isolation to be an improvement.
--
-- Three things can go wrong with a scheduled job and all three were invisible:
--   its last run raised            - cron.job_run_details.status = 'failed'
--   it stopped running at all      - no run within a multiple of its interval
--   it ran but skipped subjects    - rows in private.job_failures
--
-- Health is derived, never stored, so it cannot itself go stale.

-- Expected interval per job, so "stale" means something specific rather than a
-- guessed constant. Anything not listed is checked for failure only.
create table if not exists private.scheduled_job_expectations (
  job_name          text primary key,
  max_gap           interval not null,
  matters_because   text not null
);

insert into private.scheduled_job_expectations (job_name, max_gap, matters_because) values
  ('process-escalations',                  interval '10 minutes', 'The alert engine. If it stops, nobody is ever told that anybody has gone silent.'),
  ('process-checkin-tasks',                interval '10 minutes', 'Scheduled check-ins stop being asked for and stop being judged missed.'),
  ('push-dispatch',                        interval '10 minutes', 'Alerts are raised but never reach a phone.'),
  ('passive-poll',                         interval '45 minutes', 'Devices stop being asked for liveness, so silence becomes indistinguishable from not looking.'),
  ('account-shadow-cycle-v1',              interval '36 hours',   'Every account''s silence threshold freezes at whatever it last was. This is the job that failed unnoticed from 2026-08-05 to 2026-08-08.'),
  ('run-daily-aggregations',               interval '36 hours',   'Daily activity history stops being summarised.'),
  ('prune-stale-clients',                  interval '36 hours',   'Dead devices keep counting as reachable.'),
  ('adaptive-alert-shadow-cycle-v1',       interval '30 minutes', 'Shadow evaluation only. No live safety impact.'),
  ('adaptive-alert-shadow-maintenance-v1', interval '36 hours',   'Shadow maintenance only. No live safety impact.')
on conflict (job_name) do update
  set max_gap = excluded.max_gap,
      matters_because = excluded.matters_because;

alter table private.scheduled_job_expectations enable row level security;

-- Returns one row per scheduled job with a plain verdict. Reading it is cheap
-- and it has no side effects, so it is safe to call from anywhere.
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
  with runs as (
    select
      j.jobname,
      max(d.start_time)                                          as last_run_at,
      max(d.start_time) filter (where d.status = 'succeeded')     as last_success_at,
      (
        select count(*)::integer
        from cron.job_run_details AS recent
        where recent.jobid = j.jobid
          and recent.start_time > coalesce(
                (select max(ok.start_time) from cron.job_run_details AS ok
                  where ok.jobid = j.jobid and ok.status = 'succeeded'),
                '-infinity'::timestamptz)
          and recent.status = 'failed'
      )                                                          as consecutive_fails
    from cron.job AS j
    left join cron.job_run_details AS d on d.jobid = j.jobid
    group by j.jobid, j.jobname
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

comment on function private.scheduled_job_health() is
  'Derived health of every pg_cron job: did it fail, did it stop running, did it skip subjects. Nothing is stored, so this view cannot itself go stale.';

-- GM-visible. Same admin gate the rest of the console uses.
create or replace function public.gm_scheduled_job_health()
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
language plpgsql
security definer
set search_path to ''
as $function$
BEGIN
  IF NOT private.is_admin(auth.uid()) THEN RAISE EXCEPTION 'forbidden'; END IF;
  RETURN QUERY SELECT * FROM private.scheduled_job_health();
END;
$function$;

revoke all on function public.gm_scheduled_job_health() from public, anon;
grant execute on function public.gm_scheduled_job_health() to authenticated;

-- Push it at somebody rather than waiting to be asked.
--
-- One notification per job per unhealthy stretch: re-notifying every half hour
-- would train the reader to ignore it, which is the same failure as not
-- notifying at all. A job that recovers and breaks again notifies again,
-- because the gap in between clears the guard.
create or replace function private.report_unhealthy_jobs()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
DECLARE
  _job record;
  _admin record;
  _sent integer := 0;
BEGIN
  FOR _job IN SELECT * FROM private.scheduled_job_health() WHERE NOT healthy LOOP
    BEGIN
      -- Already told them about this one and it has not recovered since.
      CONTINUE WHEN EXISTS (
        SELECT 1 FROM public.notifications AS n
        WHERE n.kind = 'system_health'
          AND n.params->>'job_name' = _job.job_name
          AND n.created_at > coalesce(_job.last_success_at, '-infinity'::timestamptz)
      );

      FOR _admin IN SELECT user_id FROM public.app_admins LOOP
        INSERT INTO public.notifications (recipient_id, kind, body, params)
        VALUES (
          _admin.user_id,
          'system_health',
          format('定时任务 %s 异常：%s', _job.job_name, _job.problem),
          jsonb_build_object(
            'job_name', _job.job_name,
            'problem', _job.problem,
            'matters_because', _job.matters_because,
            'last_success_at', _job.last_success_at
          )
        );
        _sent := _sent + 1;
      END LOOP;
    EXCEPTION WHEN OTHERS THEN
      -- The watchdog must never be the thing that breaks the run.
      INSERT INTO private.job_failures (job_name, sqlstate, message, context)
      VALUES ('report_unhealthy_jobs', SQLSTATE, SQLERRM, _job.job_name);
    END;
  END LOOP;

  RETURN _sent;
END;
$function$;

select cron.schedule(
  'scheduled-job-health',
  '*/30 * * * *',
  $job$select private.report_unhealthy_jobs();$job$
);
