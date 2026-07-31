-- Leaving a group must work, and membership write access must stop at the
-- boundary of the group the acting user actually administers.
BEGIN;

SELECT plan(8);

INSERT INTO auth.users (id, email, aud, role) VALUES
  ('40000000-0000-4000-8000-000000000001', 'rls-owner@example.invalid', 'authenticated', 'authenticated'),
  ('40000000-0000-4000-8000-000000000002', 'rls-member@example.invalid', 'authenticated', 'authenticated'),
  ('40000000-0000-4000-8000-000000000003', 'rls-outsider-admin@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, display_name) VALUES
  ('40000000-0000-4000-8000-000000000001', 'RLS owner'),
  ('40000000-0000-4000-8000-000000000002', 'RLS member'),
  ('40000000-0000-4000-8000-000000000003', 'RLS outsider admin')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

-- Group A: owner is admin, member belongs to it.
-- Group B: a completely separate group the outsider administers. Before this
-- repair, being an admin of B was enough to write rows in A.
INSERT INTO public.groups (id, created_by, name) VALUES
  ('40000000-0000-4000-8000-000000000010', '40000000-0000-4000-8000-000000000001', 'RLS group A'),
  ('40000000-0000-4000-8000-000000000011', '40000000-0000-4000-8000-000000000003', 'RLS group B')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.group_members (group_id, user_id, role, status) VALUES
  ('40000000-0000-4000-8000-000000000010', '40000000-0000-4000-8000-000000000001', 'admin',  'active'),
  ('40000000-0000-4000-8000-000000000010', '40000000-0000-4000-8000-000000000002', 'member', 'active'),
  ('40000000-0000-4000-8000-000000000011', '40000000-0000-4000-8000-000000000003', 'admin',  'active')
ON CONFLICT DO NOTHING;

------------------------------------------------------------
-- Helper semantics
------------------------------------------------------------

SELECT ok(
  private.is_group_admin(
    '40000000-0000-4000-8000-000000000010',
    '40000000-0000-4000-8000-000000000001'
  ),
  'owner is recognised as admin of their own group'
);

SELECT ok(
  NOT private.is_group_admin(
    '40000000-0000-4000-8000-000000000010',
    '40000000-0000-4000-8000-000000000003'
  ),
  'admin of another group is not an admin of this one'
);

------------------------------------------------------------
-- A member can leave. This is the case that returned 42P17.
------------------------------------------------------------

SET LOCAL role authenticated;
SET LOCAL request.jwt.claims = '{"sub":"40000000-0000-4000-8000-000000000002","role":"authenticated"}';

SELECT lives_ok(
  $$ DELETE FROM public.group_members
     WHERE group_id = '40000000-0000-4000-8000-000000000010'
       AND user_id  = '40000000-0000-4000-8000-000000000002' $$,
  'leaving a group no longer raises infinite recursion'
);

RESET role;

SELECT is(
  (SELECT count(*)::int FROM public.group_members
    WHERE group_id = '40000000-0000-4000-8000-000000000010'
      AND user_id  = '40000000-0000-4000-8000-000000000002'),
  0,
  'the membership row is actually gone'
);

------------------------------------------------------------
-- An outsider who administers a different group must not reach into this one.
------------------------------------------------------------

SET LOCAL role authenticated;
SET LOCAL request.jwt.claims = '{"sub":"40000000-0000-4000-8000-000000000003","role":"authenticated"}';

DELETE FROM public.group_members
WHERE group_id = '40000000-0000-4000-8000-000000000010'
  AND user_id  = '40000000-0000-4000-8000-000000000001';

RESET role;

SELECT is(
  (SELECT count(*)::int FROM public.group_members
    WHERE group_id = '40000000-0000-4000-8000-000000000010'
      AND user_id  = '40000000-0000-4000-8000-000000000001'),
  1,
  'an admin of an unrelated group cannot remove a member here'
);

------------------------------------------------------------
-- An admin of this group still can, which is the behaviour 20260624180000
-- intended to add.
------------------------------------------------------------

INSERT INTO public.group_members (group_id, user_id, role, status)
VALUES ('40000000-0000-4000-8000-000000000010', '40000000-0000-4000-8000-000000000002', 'member', 'active')
ON CONFLICT DO NOTHING;

SET LOCAL role authenticated;
SET LOCAL request.jwt.claims = '{"sub":"40000000-0000-4000-8000-000000000001","role":"authenticated"}';

SELECT lives_ok(
  $$ DELETE FROM public.group_members
     WHERE group_id = '40000000-0000-4000-8000-000000000010'
       AND user_id  = '40000000-0000-4000-8000-000000000002' $$,
  'an admin of this group can remove one of its members'
);

RESET role;

SELECT is(
  (SELECT count(*)::int FROM public.group_members
    WHERE group_id = '40000000-0000-4000-8000-000000000010'
      AND user_id  = '40000000-0000-4000-8000-000000000002'),
  0,
  'the admin removal took effect'
);

------------------------------------------------------------
-- No policy on these tables may query its own table again.
------------------------------------------------------------

SELECT is(
  (SELECT count(*)::int
     FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('group_members', 'community_members')
      -- pg_policies renders the normalised expression with an uppercase FROM,
      -- so this match has to be case-insensitive.
      AND (coalesce(qual, '') ILIKE ('%from ' || tablename || '%')
        OR coalesce(with_check, '') ILIKE ('%from ' || tablename || '%'))),
  0,
  'membership policies no longer reference their own table'
);

SELECT * FROM finish();
ROLLBACK;
