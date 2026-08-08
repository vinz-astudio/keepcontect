-- Human authorised on 2026-08-04. The nightly job must maintain the table the
-- live threshold reads, or every account's learned bound freezes at today's
-- value. Same job name and schedule; only the command changes.
DO $schedule$
BEGIN
  PERFORM cron.schedule(
    'account-shadow-cycle-v1',
    '37 2 * * *',
    $cron$ SELECT private.rebuild_account_normal_bounds(); $cron$
  );
END;
$schedule$;