-- A watchdog that only works when everything is fine is not a watchdog.
-- These tests inject each of the three failure shapes and check the verdict.

BEGIN;

SELECT plan(9);

SELECT has_function('private', 'scheduled_job_health', 'the health view exists');
SELECT has_function('public', 'gm_scheduled_job_health', 'and a GM-visible wrapper exists');

-- Every job the baseline schedules is covered by an expectation, otherwise a
-- job could stop running entirely and still be reported healthy.
SELECT is(
  (SELECT count(*)::int FROM cron.job j
    WHERE NOT EXISTS (
      SELECT 1 FROM private.scheduled_job_expectations e WHERE e.job_name = j.jobname)
      AND j.jobname NOT IN ('scheduled-job-health','iso-test-never-runs')),
  0,
  'every scheduled job has a staleness expectation'
);

-- The job whose silent failure prompted all of this must be covered.
SELECT is(
  (SELECT max_gap FROM private.scheduled_job_expectations
    WHERE job_name = 'account-shadow-cycle-v1'),
  interval '36 hours',
  'the nightly rebuild that failed unnoticed for four nights is covered'
);

-- Shape 1: it never ran, or stopped running.
--
-- The verdict must be false, not unknown. The reporter selects WHERE NOT
-- healthy, and NULL is not NOT-true - so a NULL verdict would make "this job
-- has never run at all" the single case the watchdog stayed silent about.
-- That is the shape of the outage that prompted this whole change, so it is
-- the one the test pins hardest.
--
-- A job scheduled inside this transaction has provably never run. Asserting
-- against a real job instead would depend on whether the local pg_cron happened
-- to fire between the database reset and this line, which is a coin flip that
-- passes alone and fails in a suite.
SELECT cron.schedule('iso-test-never-runs', '0 0 1 1 *', 'select 1');

INSERT INTO private.scheduled_job_expectations (job_name, max_gap, matters_because)
VALUES ('iso-test-never-runs', interval '10 minutes', 'fixture');

SELECT is(
  (SELECT healthy FROM private.scheduled_job_health() WHERE job_name = 'iso-test-never-runs'),
  false,
  'a job that has never succeeded is unhealthy, not unknown'
);

SELECT is(
  (SELECT count(*)::int FROM private.scheduled_job_health() WHERE healthy IS NULL),
  0,
  'no job ever gets an unknown verdict, because the reporter would drop it'
);

SELECT matches(
  (SELECT problem FROM private.scheduled_job_health() WHERE job_name = 'iso-test-never-runs'),
  'no successful run',
  'and the problem says which way it is broken'
);

-- Shape 2: it ran, but quietly skipped subjects. This is the case that
-- per-subject isolation creates and that would otherwise be invisible - the
-- job reports success while silently doing less than its job.
INSERT INTO private.job_failures (job_name, subject_id, sqlstate, message)
VALUES ('run-daily-aggregations', gen_random_uuid(), '23502', 'null value somewhere');

SELECT is(
  (SELECT subjects_skipped FROM private.scheduled_job_health() WHERE job_name = 'run-daily-aggregations'),
  1,
  'a skipped subject is counted against the job that skipped it'
);

SELECT ok(
  NOT (SELECT healthy FROM private.scheduled_job_health() WHERE job_name = 'run-daily-aggregations'),
  'and makes the job unhealthy even though the run itself did not raise'
);

SELECT * FROM finish();

ROLLBACK;
