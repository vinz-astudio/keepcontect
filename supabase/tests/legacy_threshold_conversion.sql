-- A threshold the settings screen cannot display becomes the same total
-- expressed as a number of checks it can.
BEGIN;
SELECT plan(15);

SELECT has_function('private','split_legacy_threshold',ARRAY['integer'],'the split is a function, not inline in a DO block');
SELECT has_function('private','convert_legacy_checkin_contract',ARRAY['uuid'],'the conversion the migration ran is re-runnable and testable');
SELECT ok(NOT has_function_privilege('authenticated','private.convert_legacy_checkin_contract(uuid)','EXECUTE'),
  'a subject cannot rewrite their own contract through the converter');

-- The three shapes actually held in production on 2026-08-21.
SELECT is((SELECT checks||'x'||interval_minutes FROM private.split_legacy_threshold(480)),
  '2x240','eight hours becomes two checks of four hours');
SELECT is((SELECT checks||'x'||interval_minutes FROM private.split_legacy_threshold(720)),
  '2x360','twelve hours becomes two checks of six hours');
SELECT is((SELECT checks||'x'||interval_minutes FROM private.split_legacy_threshold(1440)),
  '4x360','twenty-four hours becomes four checks of six hours');
SELECT is((SELECT checks||'x'||interval_minutes FROM private.split_legacy_threshold(120)),
  '1x120','a threshold the screen can already show is left alone');

-- The property that matters: the subject chose a total, and the total is what
-- must survive. Shortening it would contact the group sooner than they asked.
SELECT ok((SELECT bool_and(checks * interval_minutes = t)
  FROM (SELECT t, (private.split_legacy_threshold(t)).* FROM (VALUES(480),(720),(1440)) v(t)) live),
  'each live account keeps exactly the total it chose');
SELECT ok((SELECT bool_and(checks * interval_minutes >= t)
  FROM (SELECT t, (private.split_legacy_threshold(t)).* FROM generate_series(390, 2880, 30) AS t) every),
  'no split anywhere in the column range ever shortens the total');
SELECT ok((SELECT bool_and(interval_minutes BETWEEN 90 AND 360 AND interval_minutes % 30 = 0
    AND checks BETWEEN 2 AND 8)
  FROM (SELECT (private.split_legacy_threshold(t)).* FROM generate_series(390, 2880, 30) AS t) every),
  'every legacy threshold splits into something the screen can display and edit');

-- ---------------------------------------------------------------------------
-- End to end, on an account shaped like the ones in production
-- ---------------------------------------------------------------------------

INSERT INTO auth.users(id,email,aud,role) VALUES
 ('7d000000-0000-4000-8000-000000000001','legacy-24h@example.invalid','authenticated','authenticated')
ON CONFLICT(id) DO NOTHING;
INSERT INTO public.profiles(id,display_name) VALUES
 ('7d000000-0000-4000-8000-000000000001','Legacy 24h')
ON CONFLICT(id) DO NOTHING;

SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','7d000000-0000-4000-8000-000000000001',true);
-- The grid RPC caps at 360, so it cannot produce the shape production actually
-- holds. The daily-checkin RPC is the path those contracts came in through.
SELECT public.set_daily_checkin_contract(540,1440,120,'Asia/Thimphu','shadow','daily-checkin-v1',2);
UPDATE public.passive_checkin_accounts SET engine_mode='passive_checkin'
WHERE user_id='7d000000-0000-4000-8000-000000000001';
-- Production also carries the hardcoded single miss from before 20260821010000,
-- but a contract version cannot be edited in place — the table is immutable by
-- trigger. That immutability is exactly why the conversion writes a NEW version
-- rather than rewriting the old one, and the split reads only the interval.

SELECT is(
  (private.convert_legacy_checkin_contract('7d000000-0000-4000-8000-000000000001')->>'status'),
  'converted','a pre-screen account is converted');
SELECT is((SELECT c.interval_minutes||'x'||c.consecutive_misses
  FROM public.passive_checkin_accounts a
  JOIN public.passive_checkin_contract_versions c ON c.id=a.active_contract_version_id
  WHERE a.user_id='7d000000-0000-4000-8000-000000000001'),
  '360x4','the live contract now reads four checks of six hours');
SELECT is((SELECT count(*)::integer FROM public.passive_monitoring_epochs
  WHERE user_id='7d000000-0000-4000-8000-000000000001' AND ended_at IS NULL),
  1,'exactly one epoch is left running');

-- Re-basing from the conversion is what stops somebody waking up already part
-- way through a chain of checks they never had a chance to answer.
SELECT ok((SELECT (private.passive_miss_chain(a.active_epoch_id)) = 0
  FROM public.passive_checkin_accounts a
  WHERE a.user_id='7d000000-0000-4000-8000-000000000001'),
  'nobody starts the new contract already owing missed checks');
SELECT is(
  (private.convert_legacy_checkin_contract('7d000000-0000-4000-8000-000000000001')->>'status'),
  'skipped','running the conversion twice does not convert twice');

SELECT * FROM finish();
ROLLBACK;
