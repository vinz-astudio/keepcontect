-- pgTAP database-level test for monitoring direction alert scoping
BEGIN;

SELECT plan(9);

-- Setup test users
INSERT INTO auth.users (id, email, aud, role) VALUES
  ('91000000-0000-0000-0000-000000000001', 'target@example.invalid', 'authenticated', 'authenticated'),
  ('92000000-0000-0000-0000-000000000002', 'watchera@example.invalid', 'authenticated', 'authenticated'),
  ('93000000-0000-0000-0000-000000000003', 'watcherb@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, display_name) VALUES
  ('91000000-0000-0000-0000-000000000001', 'Target User'),
  ('92000000-0000-0000-0000-000000000002', 'Watcher A'),
  ('93000000-0000-0000-0000-000000000003', 'Watcher B')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

-- Setup Group A (monitored=true) and Group B (monitored=false)
INSERT INTO public.groups (id, created_by, name, activity_visibility) VALUES
  ('81000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000002', 'Group A', 'watchers_only'),
  ('82000000-0000-0000-0000-000000000002', '93000000-0000-0000-0000-000000000003', 'Group B', 'watchers_only')
ON CONFLICT (id) DO NOTHING;

-- Group A members
INSERT INTO public.group_members (group_id, user_id, role, status, monitored, watching) VALUES
  ('81000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000002', 'admin', 'active', true, true),
  ('81000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', 'member', 'active', true, true)
ON CONFLICT (group_id, user_id) DO UPDATE SET monitored = EXCLUDED.monitored, watching = EXCLUDED.watching;

-- Group B members (Target has monitored=false in Group B)
INSERT INTO public.group_members (group_id, user_id, role, status, monitored, watching) VALUES
  ('82000000-0000-0000-0000-000000000002', '93000000-0000-0000-0000-000000000003', 'admin', 'active', true, true),
  ('82000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000001', 'member', 'active', false, true)
ON CONFLICT (group_id, user_id) DO UPDATE SET monitored = EXCLUDED.monitored, watching = EXCLUDED.watching;

-- Open group-stage silence alert for Target
INSERT INTO public.alerts (id, user_id, cause, stage, status, opened_at) VALUES
  ('71000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', 'silence', 'group', 'open', now() - interval '1 hour')
ON CONFLICT (id) DO UPDATE SET stage = EXCLUDED.stage, status = EXCLUDED.status;

-- Dispatch stage notifications
SELECT private.notify_stage('71000000-0000-0000-0000-000000000001'::uuid, '91000000-0000-0000-0000-000000000001'::uuid, 'group');

--------------------------------------------------------------------------------
-- 1. Assert Group A (monitored=true): get_group_activity_view shows alerted=true and status='alert' for Target
--------------------------------------------------------------------------------
SET local role authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "92000000-0000-0000-0000-000000000002"}', true);

SELECT results_eq(
  $$
    SELECT (m->>'alerted')::boolean, m->>'status'
    FROM jsonb_array_elements(
      (public.get_group_activity_view('81000000-0000-0000-0000-000000000001'::uuid, 'group')->'members')
    ) m
    WHERE m->>'user_id' = '91000000-0000-0000-0000-000000000001'
  $$,
  $$ VALUES (true, 'alert'::text) $$,
  'Group A (monitored=true) activity view must expose alerted=true and status=alert'
);

--------------------------------------------------------------------------------
-- 2. Assert Group A (monitored=true): legacy get_group_activity shows alerted=true and status='alert' for Target
--------------------------------------------------------------------------------
SELECT results_eq(
  $$
    SELECT (m->>'alerted')::boolean, m->>'status'
    FROM jsonb_array_elements(
      (public.get_group_activity('81000000-0000-0000-0000-000000000001'::uuid)->'members')
    ) m
    WHERE m->>'user_id' = '91000000-0000-0000-0000-000000000001'
  $$,
  $$ VALUES (true, 'alert'::text) $$,
  'Group A (monitored=true) legacy activity RPC must expose alerted=true and status=alert'
);

--------------------------------------------------------------------------------
-- 3. Assert Group A watch view includes Target
--------------------------------------------------------------------------------
SELECT ok(
  EXISTS (
    SELECT 1
    FROM jsonb_array_elements(
      (public.get_group_activity_view('81000000-0000-0000-0000-000000000001'::uuid, 'watch')->'members')
    ) m
    WHERE m->>'user_id' = '91000000-0000-0000-0000-000000000001'
  ),
  'Group A watch view must include target user'
);

--------------------------------------------------------------------------------
-- 4. Assert Group B (monitored=false): get_group_activity_view shows alerted=false and status<>'alert' for Target
--------------------------------------------------------------------------------
SELECT set_config('request.jwt.claims', '{"sub": "93000000-0000-0000-0000-000000000003"}', true);

SELECT results_eq(
  $$
    SELECT (m->>'alerted')::boolean, m->>'status' <> 'alert'
    FROM jsonb_array_elements(
      (public.get_group_activity_view('82000000-0000-0000-0000-000000000002'::uuid, 'group')->'members')
    ) m
    WHERE m->>'user_id' = '91000000-0000-0000-0000-000000000001'
  $$,
  $$ VALUES (false, true) $$,
  'Group B (monitored=false) activity view must expose alerted=false and status not alert'
);

--------------------------------------------------------------------------------
-- 5. Assert Group B (monitored=false): legacy get_group_activity shows alerted=false and status<>'alert' for Target
--------------------------------------------------------------------------------
SELECT results_eq(
  $$
    SELECT (m->>'alerted')::boolean, m->>'status' <> 'alert'
    FROM jsonb_array_elements(
      (public.get_group_activity('82000000-0000-0000-0000-000000000002'::uuid)->'members')
    ) m
    WHERE m->>'user_id' = '91000000-0000-0000-0000-000000000001'
  $$,
  $$ VALUES (false, true) $$,
  'Group B (monitored=false) legacy activity RPC must expose alerted=false and status not alert'
);

--------------------------------------------------------------------------------
-- 6. Assert Group B watch view excludes Target
--------------------------------------------------------------------------------
SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(
      (public.get_group_activity_view('82000000-0000-0000-0000-000000000002'::uuid, 'watch')->'members')
    ) m
    WHERE m->>'user_id' = '91000000-0000-0000-0000-000000000001'
  ),
  'Group B watch view must exclude opted-out target user'
);

--------------------------------------------------------------------------------
-- 7. Assert notifications recipient boundary (Watcher A received notif, Watcher B did not)
--------------------------------------------------------------------------------
SET local role service_role;

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.notifications
    WHERE alert_id = '71000000-0000-0000-0000-000000000001'::uuid
      AND recipient_id = '92000000-0000-0000-0000-000000000002'::uuid
  ),
  'Stage notifications must be sent to Watcher A in enabled Group A'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.notifications
    WHERE alert_id = '71000000-0000-0000-0000-000000000001'::uuid
      AND recipient_id = '93000000-0000-0000-0000-000000000003'::uuid
  ),
  'Stage notifications must not be sent to Watcher B in opted-out Group B'
);

--------------------------------------------------------------------------------
-- 8. Additional assertion: get_group_activity_view status in Group B is 'unknown' (since no behavior pings)
--------------------------------------------------------------------------------
SET local role authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "93000000-0000-0000-0000-000000000003"}', true);

SELECT results_eq(
  $$
    SELECT m->>'status'
    FROM jsonb_array_elements(
      (public.get_group_activity_view('82000000-0000-0000-0000-000000000002'::uuid, 'group')->'members')
    ) m
    WHERE m->>'user_id' = '91000000-0000-0000-0000-000000000001'
  $$,
  $$ VALUES ('unknown'::text) $$,
  'Group B (monitored=false) activity view exposes un-alerted status unknown'
);

SELECT * FROM finish();
ROLLBACK;
