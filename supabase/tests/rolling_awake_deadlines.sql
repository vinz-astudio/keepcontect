-- The engine keeps the two promises the Routine screen makes:
--   the deadline rolls forward every time the subject is seen, and
--   sleep hours do not consume the threshold.
BEGIN;
SELECT plan(21);

SELECT has_function('private','passive_awake_deadline',
  ARRAY['uuid','timestamp with time zone','integer'],'awake-time arithmetic is a named function');
SELECT has_function('private','passive_miss_chain',ARRAY['uuid'],'the miss chain is one definition, not four copies');
SELECT ok(NOT has_function_privilege('authenticated',
  'private.passive_awake_deadline(uuid,timestamp with time zone,integer)','EXECUTE'),
  'awake arithmetic is server-side only');

INSERT INTO auth.users(id,email,aud,role) VALUES
 ('7a000000-0000-4000-8000-000000000001','roll-clock@example.invalid','authenticated','authenticated'),
 ('7a000000-0000-4000-8000-000000000002','roll-report@example.invalid','authenticated','authenticated'),
 ('7a000000-0000-4000-8000-000000000003','roll-night@example.invalid','authenticated','authenticated')
ON CONFLICT(id) DO NOTHING;
INSERT INTO public.profiles(id,display_name) VALUES
 ('7a000000-0000-4000-8000-000000000001','Roll Clock'),
 ('7a000000-0000-4000-8000-000000000002','Roll Report'),
 ('7a000000-0000-4000-8000-000000000003','Roll Night')
ON CONFLICT(id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Awake-time arithmetic
-- ---------------------------------------------------------------------------

INSERT INTO public.user_settings(user_id,sleep_start_local,sleep_end_local,timezone)
VALUES ('7a000000-0000-4000-8000-000000000001','23:00','07:00','UTC')
ON CONFLICT(user_id) DO UPDATE
SET sleep_start_local='23:00',sleep_end_local='07:00',timezone='UTC';

SELECT is(private.passive_awake_deadline('7a000000-0000-4000-8000-000000000001','2030-03-01 10:00Z',120),
  '2030-03-01 12:00Z'::timestamptz,'a threshold clear of bedtime is plain clock time');
SELECT is(private.passive_awake_deadline('7a000000-0000-4000-8000-000000000001','2030-03-01 22:00Z',120),
  '2030-03-02 08:00Z'::timestamptz,'a threshold that reaches bedtime resumes after waking');
SELECT is(private.passive_awake_deadline('7a000000-0000-4000-8000-000000000001','2030-03-02 02:00Z',120),
  '2030-03-02 09:00Z'::timestamptz,'a threshold that starts mid-sleep costs nothing until waking');
SELECT is(private.passive_awake_deadline('7a000000-0000-4000-8000-000000000001','2030-03-01 22:00Z',2400),
  '2030-03-04 14:00Z'::timestamptz,'forty awake hours span three nights, not two');

UPDATE public.user_settings SET sleep_start_local=NULL,sleep_end_local=NULL
WHERE user_id='7a000000-0000-4000-8000-000000000001';
SELECT is(private.passive_awake_deadline('7a000000-0000-4000-8000-000000000001','2030-03-01 22:00Z',120),
  '2030-03-02 00:00Z'::timestamptz,'no sleep hours configured means no correction');

-- ---------------------------------------------------------------------------
-- Rolling: being seen moves the deadline
-- ---------------------------------------------------------------------------

SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','7a000000-0000-4000-8000-000000000002',true);
SELECT public.set_passive_checkin_contract(60,2,'none',NULL,NULL,NULL,'shadow','passive-checkin-v1');
UPDATE public.passive_checkin_accounts SET engine_mode='passive_checkin'
WHERE user_id='7a000000-0000-4000-8000-000000000002';

-- A window whose scheduled end is already half an hour in the past. Under the old
-- grid this window was doomed: nothing was observed between its start and its end.
UPDATE public.passive_monitoring_epochs SET started_at=clock_timestamp()-interval '90 minutes'
WHERE user_id='7a000000-0000-4000-8000-000000000002' AND ended_at IS NULL;
UPDATE public.passive_checkin_windows
SET window_start=clock_timestamp()-interval '90 minutes',
    window_end=clock_timestamp()-interval '30 minutes',
    arrival_deadline=clock_timestamp()-interval '30 minutes'
WHERE user_id='7a000000-0000-4000-8000-000000000002';

CREATE TEMP TABLE roll_binding(id uuid);
INSERT INTO roll_binding SELECT (public.bind_passive_collector(
  'roll-pwa','pwa_browser','pwa-interaction-v1','0.7.0')->>'binding_id')::uuid;
CREATE TEMP TABLE roll_seen(at timestamptz);
INSERT INTO roll_seen VALUES (clock_timestamp());
SELECT is(public.record_authenticated_passive_evidence((SELECT id FROM roll_binding),
  '7a000000-0000-4000-8000-000000000201',0,(SELECT at FROM roll_seen),
  'direct_device_use','passive-qualification-v1',NULL,'{"interaction":true}'),
  'inserted','a report arriving after the scheduled end is still accepted');

SELECT is((private.process_passive_checkin_subject('7a000000-0000-4000-8000-000000000002',
  (SELECT at FROM roll_seen))->>'consecutive_misses')::integer,0,
  'a report inside the threshold rescues a deadline the grid would have failed');
SELECT ok((SELECT window_end >= (SELECT at FROM roll_seen)+interval '59 minutes'
  FROM public.passive_checkin_windows
  WHERE user_id='7a000000-0000-4000-8000-000000000002' AND outcome='pending'),
  'the deadline moves to one full threshold after the report');
SELECT ok((SELECT abs(extract(epoch FROM (
    (public.my_daily_checkin()->>'next_deadline_at')::timestamptz
    - ((SELECT at FROM roll_seen)+interval '60 minutes')))) < 2),
  'the screen is handed the same deadline the engine will judge against');

-- One full threshold later, with nothing new observed.
SELECT is((private.process_passive_checkin_subject('7a000000-0000-4000-8000-000000000002',
  (SELECT at FROM roll_seen)+interval '70 minutes')->>'consecutive_misses')::integer,1,
  'one threshold of silence after the report elapses exactly once');
SELECT ok((SELECT window_end=(SELECT at FROM roll_seen) FROM public.passive_checkin_windows
  WHERE user_id='7a000000-0000-4000-8000-000000000002' AND outcome='checked_in'),
  'the met window is cut at the report, so the next threshold is measured from it');

-- ---------------------------------------------------------------------------
-- Awake: a night of silence is not evidence of anything
-- ---------------------------------------------------------------------------

SELECT set_config('request.jwt.claim.sub','7a000000-0000-4000-8000-000000000003',true);
INSERT INTO public.user_settings(user_id,sleep_start_local,sleep_end_local,timezone)
VALUES ('7a000000-0000-4000-8000-000000000003','23:00','07:00','UTC')
ON CONFLICT(user_id) DO UPDATE
SET sleep_start_local='23:00',sleep_end_local='07:00',timezone='UTC';
SELECT public.set_passive_checkin_contract(120,2,'none',NULL,NULL,NULL,'shadow','passive-checkin-v1');
UPDATE public.passive_checkin_accounts SET engine_mode='passive_checkin'
WHERE user_id='7a000000-0000-4000-8000-000000000003';
UPDATE public.passive_monitoring_epochs SET started_at='2030-05-01 22:00Z'
WHERE user_id='7a000000-0000-4000-8000-000000000003' AND ended_at IS NULL;
DELETE FROM public.passive_checkin_windows WHERE user_id='7a000000-0000-4000-8000-000000000003';

-- Nine and a half hours of wall clock, of which eight are sleep. The grid scored
-- this as four misses and a group notification on a working phone.
SELECT is((private.process_passive_checkin_subject('7a000000-0000-4000-8000-000000000003',
  '2030-05-02 07:30Z')->>'consecutive_misses')::integer,0,
  'a night of silence does not consume the threshold');
SELECT is((private.process_passive_checkin_subject('7a000000-0000-4000-8000-000000000003',
  '2030-05-02 08:01Z')->>'consecutive_misses')::integer,1,
  'the first deadline lands two awake hours after waking');
SELECT is((SELECT count(*)::integer FROM public.alerts
  WHERE user_id='7a000000-0000-4000-8000-000000000003'),0,
  'one elapsed deadline never reaches anybody');
SELECT is((private.process_passive_checkin_subject('7a000000-0000-4000-8000-000000000003',
  '2030-05-02 10:01Z')->>'consecutive_misses')::integer,2,
  'the second deadline is two more awake hours, not two more clock hours');
SELECT is((SELECT count(*)::integer FROM public.alerts
  WHERE user_id='7a000000-0000-4000-8000-000000000003' AND status='open'),1,
  'the configured chain of elapsed deadlines opens exactly one alert');

-- ---------------------------------------------------------------------------
-- A legacy epoch must not be able to strand itself
-- ---------------------------------------------------------------------------

-- The grid engine left accounts with several pending windows at once, because
-- ingest could open one ahead of the evaluator. If one of them sits where the
-- rolling chain wants to put its next window, a careless insert raises a unique
-- violation — on every pass, forever, and the subject is never judged again while
-- the job log fills up where nobody is looking. Silent permanent loss of the
-- protection itself is the worst failure this system has.
INSERT INTO auth.users(id,email,aud,role) VALUES
 ('7a000000-0000-4000-8000-000000000004','roll-legacy@example.invalid','authenticated','authenticated')
ON CONFLICT(id) DO NOTHING;
INSERT INTO public.profiles(id,display_name) VALUES
 ('7a000000-0000-4000-8000-000000000004','Roll Legacy')
ON CONFLICT(id) DO NOTHING;
SELECT set_config('request.jwt.claim.sub','7a000000-0000-4000-8000-000000000004',true);
SELECT public.set_passive_checkin_contract(60,2,'none',NULL,NULL,NULL,'shadow','passive-checkin-v1');
UPDATE public.passive_monitoring_epochs SET started_at='2030-06-01 00:00Z'
WHERE user_id='7a000000-0000-4000-8000-000000000004' AND ended_at IS NULL;
DELETE FROM public.passive_checkin_windows WHERE user_id='7a000000-0000-4000-8000-000000000004';
-- Two pending windows, a gap in the ordinals, and the higher one sitting exactly
-- where the chain's next window would start.
INSERT INTO public.passive_checkin_windows(
  user_id,epoch_id,contract_version_id,ordinal,window_start,window_end,arrival_deadline)
SELECT '7a000000-0000-4000-8000-000000000004',
  account.active_epoch_id,account.active_contract_version_id,fixture.ord,fixture.opened,fixture.closed,fixture.closed
FROM public.passive_checkin_accounts AS account, (VALUES
  (0,'2030-06-01 00:00Z'::timestamptz,'2030-06-01 01:00Z'::timestamptz),
  (5,'2030-06-01 01:00Z'::timestamptz,'2030-06-01 02:00Z'::timestamptz)
) AS fixture(ord,opened,closed)
WHERE account.user_id='7a000000-0000-4000-8000-000000000004';

SELECT lives_ok(
  $$ SELECT private.process_passive_checkin_subject(
    '7a000000-0000-4000-8000-000000000004','2030-06-01 03:00Z') $$,
  'a legacy epoch with colliding pending windows is still evaluated');
SELECT is((SELECT count(*)::integer FROM public.passive_checkin_windows
  WHERE user_id='7a000000-0000-4000-8000-000000000004' AND outcome='pending'),1,
  'an evaluated epoch is left with exactly one live window');

SELECT * FROM finish();
ROLLBACK;
