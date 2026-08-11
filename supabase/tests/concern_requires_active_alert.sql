-- ADR-0039: Concern strengthens an existing active alert. It never creates one,
-- never counts as activity evidence, and never resolves one.
BEGIN;

SELECT plan(12);

INSERT INTO auth.users (id, email, aud, role) VALUES
  ('52000000-0000-4000-8000-000000000001', 'concern-guardian@example.invalid', 'authenticated', 'authenticated'),
  ('52000000-0000-4000-8000-000000000002', 'concern-ward@example.invalid', 'authenticated', 'authenticated'),
  ('52000000-0000-4000-8000-000000000003', 'concern-admin@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, display_name) VALUES
  ('52000000-0000-4000-8000-000000000001', 'Concern guardian'),
  ('52000000-0000-4000-8000-000000000002', 'Concern ward'),
  ('52000000-0000-4000-8000-000000000003', 'Concern admin')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

INSERT INTO public.guardianships (guardian_id, ward_id, status)
VALUES (
  '52000000-0000-4000-8000-000000000001',
  '52000000-0000-4000-8000-000000000002',
  'active'
)
ON CONFLICT (guardian_id, ward_id) DO UPDATE SET status = 'active';

INSERT INTO public.app_admins (user_id)
VALUES ('52000000-0000-4000-8000-000000000003')
ON CONFLICT (user_id) DO NOTHING;

SELECT set_config('request.jwt.claim.sub', '52000000-0000-4000-8000-000000000001', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);

-- 1..3: with no active alert, an authorised sender is refused and leaves no trace.
SELECT throws_ok(
  $$ SELECT public.send_concern('52000000-0000-4000-8000-000000000002') $$,
  'P0001',
  'active alert required',
  'an authorised member cannot send Concern without an active alert'
);

SELECT is(
  (SELECT count(*)::integer FROM public.alerts
   WHERE user_id = '52000000-0000-4000-8000-000000000002'),
  0,
  'a refused Concern creates no alert row at all'
);

SELECT is(
  (SELECT count(*)::integer FROM public.notifications
   WHERE recipient_id = '52000000-0000-4000-8000-000000000002'),
  0,
  'a refused Concern notifies nobody'
);

-- 4: an admin is refused on the same grounds; admin authority is not alert authority.
SELECT set_config('request.jwt.claim.sub', '52000000-0000-4000-8000-000000000003', true);

SELECT throws_ok(
  $$ SELECT public.gm_send_concern('52000000-0000-4000-8000-000000000002') $$,
  'P0001',
  'active alert required',
  'an admin cannot send Concern without an active alert'
);

-- Now give the ward a real open alert, raised by the ordinary silence path.
RESET ROLE;
INSERT INTO public.alerts (
  id, user_id, cause, stage, status, opened_at, stage_entered_at, next_deadline
) VALUES (
  '52000000-0000-4000-8000-000000000030',
  '52000000-0000-4000-8000-000000000002',
  'silence', 'self', 'open',
  now() - interval '40 minutes',
  now() - interval '40 minutes',
  now() + interval '20 minutes'
);

SELECT set_config('request.jwt.claim.sub', '52000000-0000-4000-8000-000000000001', true);

SELECT lives_ok(
  $$ SELECT public.send_concern('52000000-0000-4000-8000-000000000002') $$,
  'Concern is accepted while an alert is open'
);

-- 6..12: the accepted path strengthens the alert without inventing anything.
SELECT is(
  (SELECT count(*)::integer FROM public.alerts
   WHERE user_id = '52000000-0000-4000-8000-000000000002'),
  1,
  'an accepted Concern still creates no second alert'
);

SELECT is(
  (SELECT status FROM public.alerts
   WHERE id = '52000000-0000-4000-8000-000000000030'),
  'open',
  'Concern never resolves the alert it is attached to'
);

SELECT ok(
  (SELECT requires_explicit_unlock FROM public.alerts
   WHERE id = '52000000-0000-4000-8000-000000000030'),
  'Concern strengthens the requirement for an explicit personal unlock'
);

SELECT is(
  (SELECT count(*)::integer FROM public.notifications
   WHERE recipient_id = '52000000-0000-4000-8000-000000000002'
     AND kind = 'concern'
     AND alert_id = '52000000-0000-4000-8000-000000000030'),
  1,
  'the subject is notified once, against the existing alert'
);

SELECT is(
  (SELECT count(*)::integer FROM public.behavior_pings
   WHERE user_id = '52000000-0000-4000-8000-000000000002'),
  0,
  'Concern is not activity evidence for the subject'
);

SELECT is(
  (SELECT count(*)::integer FROM public.alert_events
   WHERE alert_id = '52000000-0000-4000-8000-000000000030'
     AND note = 'concern_on_open_alert'),
  1,
  'the concern is recorded against the existing alert, not as a new raise'
);

-- 12: the admin path behaves identically once an alert exists.
SELECT set_config('request.jwt.claim.sub', '52000000-0000-4000-8000-000000000003', true);

SELECT lives_ok(
  $$ SELECT public.gm_send_concern('52000000-0000-4000-8000-000000000002') $$,
  'admin Concern is accepted while an alert is open'
);

SELECT * FROM finish();
ROLLBACK;
