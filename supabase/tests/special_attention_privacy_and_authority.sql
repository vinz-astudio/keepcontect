-- ADR-0039: Special Attention is a private, default-off notification preference
-- that grants no data visibility and no operational authority.
BEGIN;

SELECT plan(13);

INSERT INTO auth.users (id, email, aud, role) VALUES
  ('53000000-0000-4000-8000-000000000001', 'sa-watcher@example.invalid', 'authenticated', 'authenticated'),
  ('53000000-0000-4000-8000-000000000002', 'sa-subject@example.invalid', 'authenticated', 'authenticated'),
  ('53000000-0000-4000-8000-000000000003', 'sa-stranger@example.invalid', 'authenticated', 'authenticated'),
  ('53000000-0000-4000-8000-000000000004', 'sa-guardian@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, display_name) VALUES
  ('53000000-0000-4000-8000-000000000001', 'SA watcher'),
  ('53000000-0000-4000-8000-000000000002', 'SA subject'),
  ('53000000-0000-4000-8000-000000000003', 'SA stranger'),
  ('53000000-0000-4000-8000-000000000004', 'SA guardian')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

INSERT INTO public.groups (id, name, created_by)
VALUES (
  '53000000-0000-4000-8000-000000000010',
  'special-attention-fixture',
  '53000000-0000-4000-8000-000000000001'
);

INSERT INTO public.group_members (group_id, user_id, role, status, monitored, watching) VALUES
  ('53000000-0000-4000-8000-000000000010', '53000000-0000-4000-8000-000000000001', 'member', 'active', false, true),
  ('53000000-0000-4000-8000-000000000010', '53000000-0000-4000-8000-000000000002', 'member', 'active', true, false)
ON CONFLICT (group_id, user_id) DO UPDATE
SET status = EXCLUDED.status, monitored = EXCLUDED.monitored, watching = EXCLUDED.watching;

INSERT INTO public.guardianships (guardian_id, ward_id, status)
VALUES (
  '53000000-0000-4000-8000-000000000004',
  '53000000-0000-4000-8000-000000000002',
  'active'
)
ON CONFLICT (guardian_id, ward_id) DO UPDATE SET status = 'active';

SELECT set_config('request.jwt.claim.sub', '53000000-0000-4000-8000-000000000001', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);

-- 1: off by default. Nothing is subscribed until somebody says so.
SELECT is(
  (SELECT count(*)::integer FROM public.my_special_attention()),
  0,
  'Special Attention is off by default'
);

-- 2: self-subscription is meaningless and refused.
SELECT throws_ok(
  $$ SELECT public.set_special_attention('53000000-0000-4000-8000-000000000001', true) $$,
  'P0001',
  'bad target',
  'a person cannot put Special Attention on themselves'
);

-- 3: an active group relationship is the entry ticket.
SELECT lives_ok(
  $$ SELECT public.set_special_attention('53000000-0000-4000-8000-000000000002', true) $$,
  'an active group member may subscribe'
);

SELECT is(
  (SELECT count(*)::integer FROM public.my_special_attention()
   WHERE subject_id = '53000000-0000-4000-8000-000000000002'),
  1,
  'the subscription is visible to its owner'
);

-- 5: enabling twice is idempotent, not a second subscription.
SELECT is(
  (SELECT count(*)::integer FROM public.special_attention_subscriptions
   WHERE subscriber_id = '53000000-0000-4000-8000-000000000001'),
  1,
  'repeating the request does not duplicate the subscription'
);

-- 6: the preference is powerless. Nothing else in the world changed.
SELECT is(
  (SELECT count(*)::integer FROM public.alerts
   WHERE user_id = '53000000-0000-4000-8000-000000000002')
  + (SELECT count(*)::integer FROM public.notifications
     WHERE recipient_id = '53000000-0000-4000-8000-000000000001')
  + (SELECT count(*)::integer FROM public.checkin_tasks
     WHERE ward_id = '53000000-0000-4000-8000-000000000002'),
  0,
  'subscribing creates no alert, no notification and no care task'
);

-- 7: a stranger has no relationship, so no entry ticket.
SELECT set_config('request.jwt.claim.sub', '53000000-0000-4000-8000-000000000003', true);

SELECT throws_ok(
  $$ SELECT public.set_special_attention('53000000-0000-4000-8000-000000000002', true) $$,
  'P0001',
  'relationship not active',
  'someone with no active relationship cannot subscribe'
);

-- 8: privacy. The subject cannot learn who is watching out for them.
SELECT set_config('request.jwt.claim.sub', '53000000-0000-4000-8000-000000000002', true);

SELECT is(
  (SELECT count(*)::integer FROM public.my_special_attention()),
  0,
  'the subject sees nothing about who subscribed to them'
);

SELECT ok(
  NOT has_function_privilege(
    'authenticated', 'public.special_attention_recipients(uuid)', 'EXECUTE'
  ),
  'no client can enumerate who is watching out for a given person'
);

-- 10..11: eligibility follows the relationship, and withdrawal always works.
RESET ROLE;

SELECT is(
  (SELECT count(*)::integer FROM public.special_attention_recipients(
     '53000000-0000-4000-8000-000000000002')),
  1,
  'an active relationship makes the subscriber notification-eligible'
);

UPDATE public.group_members
SET status = 'pending'
WHERE group_id = '53000000-0000-4000-8000-000000000010'
  AND user_id = '53000000-0000-4000-8000-000000000001';

SELECT is(
  (SELECT count(*)::integer FROM public.special_attention_recipients(
     '53000000-0000-4000-8000-000000000002')),
  0,
  'a relationship that stops being active stops producing notices'
);

SELECT is(
  (SELECT count(*)::integer FROM public.special_attention_subscriptions
   WHERE subscriber_id = '53000000-0000-4000-8000-000000000001'),
  1,
  'the person keeps their own preference; it is suspended, not deleted behind their back'
);

-- 13: withdrawal never requires an active relationship.
SELECT set_config('request.jwt.claim.sub', '53000000-0000-4000-8000-000000000001', true);

SELECT lives_ok(
  $$ SELECT public.set_special_attention('53000000-0000-4000-8000-000000000002', false) $$,
  'anyone can always withdraw, even after the relationship lapsed'
);

SELECT * FROM finish();
ROLLBACK;
