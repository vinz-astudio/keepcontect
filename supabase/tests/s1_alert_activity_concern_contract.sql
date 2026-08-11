BEGIN;

SELECT plan(11);

INSERT INTO auth.users (id, email, aud, role) VALUES
  ('51000000-0000-4000-8000-000000000001', 's1-guardian@example.invalid', 'authenticated', 'authenticated'),
  ('51000000-0000-4000-8000-000000000002', 's1-ward@example.invalid', 'authenticated', 'authenticated'),
  ('51000000-0000-4000-8000-000000000003', 's1-admin@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, display_name) VALUES
  ('51000000-0000-4000-8000-000000000001', 'S1 Guardian'),
  ('51000000-0000-4000-8000-000000000002', 'S1 Ward'),
  ('51000000-0000-4000-8000-000000000003', 'S1 Admin')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

INSERT INTO public.guardianships (id, guardian_id, ward_id, status) VALUES
  ('51000000-0000-4000-8000-000000000010',
   '51000000-0000-4000-8000-000000000001',
   '51000000-0000-4000-8000-000000000002', 'active')
ON CONFLICT (guardian_id, ward_id) DO UPDATE SET status = 'active';

INSERT INTO public.app_admins (user_id)
VALUES ('51000000-0000-4000-8000-000000000003')
ON CONFLICT (user_id) DO NOTHING;

SELECT ok(
  private.is_guardian_of(
    '51000000-0000-4000-8000-000000000002',
    '51000000-0000-4000-8000-000000000001'
  ),
  'precondition: active Guardian may contact Ward'
);

SELECT set_config('request.jwt.claim.sub', '51000000-0000-4000-8000-000000000001', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);

SELECT throws_ok(
  $$ SELECT public.send_concern('51000000-0000-4000-8000-000000000002') $$,
  'P0001',
  'active alert required',
  'ADR0039-CONCERN-01 Concern cannot create an alert'
);

SELECT is(
  (SELECT count(*)::integer FROM public.alerts
   WHERE user_id = '51000000-0000-4000-8000-000000000002' AND status = 'open'),
  0,
  'rejected Concern leaves the open-alert count unchanged'
);

DELETE FROM public.notifications WHERE recipient_id = '51000000-0000-4000-8000-000000000002';
DELETE FROM public.alert_events WHERE alert_id IN (
  SELECT id FROM public.alerts WHERE user_id = '51000000-0000-4000-8000-000000000002'
);
DELETE FROM public.alerts WHERE user_id = '51000000-0000-4000-8000-000000000002';

SELECT set_config('request.jwt.claim.sub', '51000000-0000-4000-8000-000000000003', true);

SELECT throws_ok(
  $$ SELECT public.gm_send_concern('51000000-0000-4000-8000-000000000002') $$,
  'P0001',
  'active alert required',
  'ADR0039-CONCERN-02 GM Concern cannot create an alert'
);

SELECT is(
  (SELECT count(*)::integer FROM public.alerts
   WHERE user_id = '51000000-0000-4000-8000-000000000002' AND status = 'open'),
  0,
  'rejected GM Concern leaves the open-alert count unchanged'
);

DELETE FROM public.notifications WHERE recipient_id = '51000000-0000-4000-8000-000000000002';
DELETE FROM public.alert_events WHERE alert_id IN (
  SELECT id FROM public.alerts WHERE user_id = '51000000-0000-4000-8000-000000000002'
);
DELETE FROM public.alerts WHERE user_id = '51000000-0000-4000-8000-000000000002';

INSERT INTO public.alerts (
  id, user_id, cause, status, stage, opened_at, stage_entered_at, next_deadline
) VALUES (
  '51000000-0000-4000-8000-0000000000a1',
  '51000000-0000-4000-8000-000000000002',
  'silence', 'open', 'group', now() - interval '20 minutes',
  now() - interval '20 minutes', now() + interval '30 minutes'
);

SELECT set_config('request.jwt.claim.sub', '51000000-0000-4000-8000-000000000001', true);
SELECT lives_ok(
  $$ SELECT public.send_concern('51000000-0000-4000-8000-000000000002') $$,
  'precondition: Concern attaches when an active alert exists'
);

SELECT ok(
  (SELECT count(*) = 1
          AND bool_and(id = '51000000-0000-4000-8000-0000000000a1'::uuid)
          AND bool_and(status = 'open')
   FROM public.alerts
   WHERE user_id = '51000000-0000-4000-8000-000000000002'),
  'ADR0039-CONCERN-03 Concern preserves the active alert identity and status'
);

SELECT ok(
  (SELECT count(*) = 1 FROM public.notifications
   WHERE recipient_id = '51000000-0000-4000-8000-000000000002'
     AND alert_id = '51000000-0000-4000-8000-0000000000a1'
     AND kind = 'concern')
  AND NOT EXISTS (
    SELECT 1 FROM public.behavior_pings
    WHERE user_id = '51000000-0000-4000-8000-000000000002'
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.alert_events
    WHERE alert_id = '51000000-0000-4000-8000-0000000000a1'
      AND kind IN ('resolved', 'auto_resolved', 'confirmed_safe')
  ),
  'ADR0039-CONCERN-04 Concern is alert-bound notification only, never activity or confirmation'
);

UPDATE public.alerts
SET paused_by = '51000000-0000-4000-8000-000000000001',
    paused_until = now() + interval '10 minutes'
WHERE id = '51000000-0000-4000-8000-0000000000a1';

SELECT lives_ok(
  $$ SELECT public.resolve_alert('51000000-0000-4000-8000-0000000000a1') $$,
  'precondition: assigned Guardian may confirm Ward safe'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.alert_events
    WHERE alert_id = '51000000-0000-4000-8000-0000000000a1'
      AND actor_id = '51000000-0000-4000-8000-000000000001'
      AND kind = 'confirmed_safe'
  ),
  'ADR0039-GUARDIAN-CONFIRM-01 confirmation records Guardian actor and confirmed_safe provenance'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.behavior_pings
    WHERE user_id = '51000000-0000-4000-8000-000000000002'
      AND kind = 'manual_checkin'
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.behavior_pings
    WHERE user_id = '51000000-0000-4000-8000-000000000002'
  ),
  'ADR0039-GUARDIAN-CONFIRM-02 external confirmation never becomes Ward activity evidence'
);

SELECT * FROM finish();
ROLLBACK;
