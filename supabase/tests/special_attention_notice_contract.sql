-- ADR-0039 · Telling somebody that a person's protection broke, without turning
-- it into a false alarm about the person.
BEGIN;

SELECT plan(10);

INSERT INTO auth.users (id, email, aud, role) VALUES
  ('57000000-0000-4000-8000-000000000001', 'notice-subject@example.invalid', 'authenticated', 'authenticated'),
  ('57000000-0000-4000-8000-000000000002', 'notice-watcher@example.invalid', 'authenticated', 'authenticated'),
  ('57000000-0000-4000-8000-000000000003', 'notice-lapsed@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, display_name) VALUES
  ('57000000-0000-4000-8000-000000000001', 'Notice subject'),
  ('57000000-0000-4000-8000-000000000002', 'Notice watcher'),
  ('57000000-0000-4000-8000-000000000003', 'Notice lapsed watcher')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

INSERT INTO public.groups (id, name, created_by)
VALUES ('57000000-0000-4000-8000-000000000010', 'notice-fixture',
        '57000000-0000-4000-8000-000000000001');

INSERT INTO public.group_members (group_id, user_id, role, status, monitored, watching) VALUES
  ('57000000-0000-4000-8000-000000000010', '57000000-0000-4000-8000-000000000001', 'member', 'active', true, false),
  ('57000000-0000-4000-8000-000000000010', '57000000-0000-4000-8000-000000000002', 'member', 'active', false, true),
  ('57000000-0000-4000-8000-000000000010', '57000000-0000-4000-8000-000000000003', 'member', 'active', false, true)
ON CONFLICT (group_id, user_id) DO UPDATE SET status = EXCLUDED.status;

-- Both watchers opt in privately.
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', '57000000-0000-4000-8000-000000000002', true);
SELECT public.set_special_attention('57000000-0000-4000-8000-000000000001', true);
SELECT set_config('request.jwt.claim.sub', '57000000-0000-4000-8000-000000000003', true);
SELECT public.set_special_attention('57000000-0000-4000-8000-000000000001', true);
RESET ROLE;

-- The subject's protection breaks.
INSERT INTO public.protection_health_incidents (id, user_id, cause, opened_at)
VALUES (
  '57200000-0000-4000-8000-000000000001',
  '57000000-0000-4000-8000-000000000001',
  'coverage_gap',
  now() - interval '6 hours'
);

-- 1: nobody hears anything before the subject has been told.
SELECT is(
  (SELECT private.dispatch_special_attention_notices(interval '2 hours')
     ->> 'notices_sent'),
  '0',
  'no watcher learns of an interruption before the person it concerns has been told'
);

-- 2: still nothing during the health grace. A blip is not news.
SELECT private.mark_protection_health_prompted('57000000-0000-4000-8000-000000000001');

SELECT is(
  (SELECT private.dispatch_special_attention_notices(interval '2 hours')
     ->> 'notices_sent'),
  '0',
  'a brief interruption never reaches anybody else'
);

-- 3..5: once the grace has passed, each eligible watcher hears once.
RESET ROLE;
UPDATE public.protection_health_incidents
SET prompted_at = now() - interval '3 hours'
WHERE id = '57200000-0000-4000-8000-000000000001';

SELECT is(
  (SELECT private.dispatch_special_attention_notices(interval '2 hours')
     ->> 'notices_sent'),
  '2',
  'after the subject is told and the grace passes, both watchers are notified'
);

SELECT is(
  (SELECT private.dispatch_special_attention_notices(interval '2 hours')
     ->> 'notices_sent'),
  '0',
  'a flapping collector cannot notify the same people twice for one incident'
);

SELECT is(
  (SELECT count(*)::integer FROM public.notifications
   WHERE recipient_id = '57000000-0000-4000-8000-000000000002'
     AND kind = 'coverage_interrupted'),
  1,
  'exactly one notice reached the watcher'
);

-- 6..7: the words, and what they refuse to claim.
SELECT ok(
  (SELECT body LIKE '%覆盖中断%' AND body LIKE '%不代表%'
   FROM public.notifications
   WHERE recipient_id = '57000000-0000-4000-8000-000000000002'
     AND kind = 'coverage_interrupted'),
  'the notice names a coverage interruption and says plainly that it does not mean danger'
);

SELECT ok(
  (SELECT (params ->> 'means_danger') = 'false'
   FROM public.notifications
   WHERE recipient_id = '57000000-0000-4000-8000-000000000002'
     AND kind = 'coverage_interrupted'),
  'the denial is machine-readable too, so no client can render it as an emergency'
);

-- 8: it is a notice, not an alarm about the person.
SELECT is(
  (SELECT count(*)::integer FROM public.alerts
   WHERE user_id = '57000000-0000-4000-8000-000000000001'),
  0,
  'telling somebody about an outage never creates a personal alert'
);

-- 9: eligibility is checked at send time, not at subscribe time.
UPDATE public.group_members
SET status = 'pending'
WHERE group_id = '57000000-0000-4000-8000-000000000010'
  AND user_id = '57000000-0000-4000-8000-000000000003';

-- The first incident recovers, and later the coverage breaks again. One open
-- incident per person is enforced by the schema, so a second break is a second
-- incident only after the first one closed.
UPDATE public.protection_health_incidents
SET closed_at = now() - interval '4 hours',
    recovered_at = now() - interval '4 hours',
    recovery_evidence = jsonb_build_object('basis', 'fixture recovery')
WHERE id = '57200000-0000-4000-8000-000000000001';

INSERT INTO public.protection_health_incidents (id, user_id, cause, opened_at, prompted_at)
VALUES (
  '57200000-0000-4000-8000-000000000002',
  '57000000-0000-4000-8000-000000000001',
  'coverage_gap',
  now() - interval '6 hours',
  now() - interval '3 hours'
);

SELECT is(
  (SELECT private.dispatch_special_attention_notices(interval '2 hours')
     ->> 'notices_sent'),
  '1',
  'a watcher whose relationship has lapsed is no longer notified'
);

-- 10: dispatch is a server concern.
SELECT ok(
  NOT has_function_privilege(
    'authenticated', 'private.dispatch_special_attention_notices(interval)', 'EXECUTE'
  ),
  'no client can trigger notices to other people'
);

SELECT * FROM finish();
ROLLBACK;
