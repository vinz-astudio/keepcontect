-- GM alert mute is a narrow, explicit live-authority exception.
BEGIN;

SELECT plan(14);

INSERT INTO auth.users (id, email, aud, role) VALUES
  ('30000000-0000-4000-8000-000000000001', 'gm-mute-admin@example.invalid', 'authenticated', 'authenticated'),
  ('30000000-0000-4000-8000-000000000002', 'gm-mute-member@example.invalid', 'authenticated', 'authenticated'),
  ('30000000-0000-4000-8000-000000000003', 'gm-mute-active@example.invalid', 'authenticated', 'authenticated'),
  ('30000000-0000-4000-8000-000000000004', 'gm-mute-expired@example.invalid', 'authenticated', 'authenticated'),
  ('30000000-0000-4000-8000-000000000005', 'gm-mute-existing@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, display_name) VALUES
  ('30000000-0000-4000-8000-000000000001', 'GM mute admin'),
  ('30000000-0000-4000-8000-000000000002', 'GM mute member'),
  ('30000000-0000-4000-8000-000000000003', 'GM mute active target'),
  ('30000000-0000-4000-8000-000000000004', 'GM mute expired target'),
  ('30000000-0000-4000-8000-000000000005', 'GM mute existing alert target')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

INSERT INTO public.app_admins (user_id)
VALUES ('30000000-0000-4000-8000-000000000001')
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO public.groups (id, created_by, name)
VALUES (
  '30000000-0000-4000-8000-000000000010',
  '30000000-0000-4000-8000-000000000001',
  'GM mute authority test'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.group_members (group_id, user_id, role, status, monitored, watching) VALUES
  ('30000000-0000-4000-8000-000000000010', '30000000-0000-4000-8000-000000000001', 'admin', 'active', true, true),
  ('30000000-0000-4000-8000-000000000010', '30000000-0000-4000-8000-000000000003', 'member', 'active', true, true),
  ('30000000-0000-4000-8000-000000000010', '30000000-0000-4000-8000-000000000004', 'member', 'active', true, true),
  ('30000000-0000-4000-8000-000000000010', '30000000-0000-4000-8000-000000000005', 'member', 'active', true, true)
ON CONFLICT (group_id, user_id) DO UPDATE
SET monitored = EXCLUDED.monitored, watching = EXCLUDED.watching, status = EXCLUDED.status;

INSERT INTO public.device_state (user_id, status, last_heartbeat_at) VALUES
  ('30000000-0000-4000-8000-000000000003', 'normal', now() - interval '2 days'),
  ('30000000-0000-4000-8000-000000000004', 'normal', now() - interval '2 days'),
  ('30000000-0000-4000-8000-000000000005', 'normal', now() - interval '2 days')
ON CONFLICT (user_id) DO UPDATE
SET status = EXCLUDED.status, last_heartbeat_at = EXCLUDED.last_heartbeat_at;

-- Keep the existing-alert target muted before any process_escalations() call,
-- so earlier test phases cannot create its alert implicitly.
INSERT INTO public.gm_mutes (user_id, muted_by, muted_until, reason)
VALUES (
  '30000000-0000-4000-8000-000000000005',
  '30000000-0000-4000-8000-000000000001',
  now() + interval '1 day',
  'existing alert must continue'
)
ON CONFLICT (user_id) DO UPDATE
SET muted_by = EXCLUDED.muted_by, muted_until = EXCLUDED.muted_until, reason = EXCLUDED.reason;

SELECT is(
  has_function_privilege('anon', 'public.gm_mute_user(uuid,timestamptz,text)', 'EXECUTE'),
  false,
  'anonymous callers cannot execute GM mute'
);

SELECT is(
  has_function_privilege('anon', 'public.gm_unmute_user(uuid)', 'EXECUTE'),
  false,
  'anonymous callers cannot execute GM unmute'
);

SELECT is(
  has_function_privilege('authenticated', 'public.gm_mute_user(uuid,timestamptz,text)', 'EXECUTE'),
  true,
  'authenticated callers may reach the GM-gated mute RPC'
);

SELECT is(
  has_table_privilege('authenticated', 'public.gm_mutes', 'SELECT'),
  false,
  'authenticated callers cannot read the GM mute table directly'
);

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-4000-8000-000000000002"}',
  true
);

SELECT throws_ok(
  $$SELECT public.gm_mute_user('30000000-0000-4000-8000-000000000003', NULL, 'not an admin')$$,
  'P0001'::char(5),
  'forbidden',
  'a non-GM authenticated user cannot mute another user'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-4000-8000-000000000001"}',
  true
);

SELECT lives_ok(
  $$SELECT public.gm_mute_user('30000000-0000-4000-8000-000000000003', NULL, 'temporary false-positive suppression')$$,
  'a GM can create an indefinite mute with a reason'
);

RESET ROLE;

SELECT results_eq(
  $$
    SELECT muted_by, muted_until IS NULL, reason
    FROM public.gm_mutes
    WHERE user_id = '30000000-0000-4000-8000-000000000003'
  $$,
  $$
    VALUES (
      '30000000-0000-4000-8000-000000000001'::uuid,
      true,
      'temporary false-positive suppression'::text
    )
  $$,
  'the active mute retains its GM actor, indefinite window, and reason'
);

SELECT public.process_escalations();

SELECT is(
  (
    SELECT count(*)::integer
    FROM public.alerts
    WHERE user_id = '30000000-0000-4000-8000-000000000003'
      AND status = 'open'
  ),
  0,
  'an active mute suppresses creation of a new silence or dark-device alert'
);

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"30000000-0000-4000-8000-000000000001"}',
  true
);

SELECT lives_ok(
  $$SELECT public.gm_unmute_user('30000000-0000-4000-8000-000000000003')$$,
  'a GM can explicitly remove an active mute'
);

RESET ROLE;
SELECT public.process_escalations();

SELECT is(
  (
    SELECT count(*)::integer
    FROM public.alerts
    WHERE user_id = '30000000-0000-4000-8000-000000000003'
      AND status = 'open'
      AND cause IN ('silence', 'dark_device')
  ),
  1,
  'unmuting restores normal new-alert creation'
);

INSERT INTO public.gm_mutes (user_id, muted_by, muted_until, reason)
VALUES (
  '30000000-0000-4000-8000-000000000004',
  '30000000-0000-4000-8000-000000000001',
  now() - interval '1 minute',
  'expired mute'
)
ON CONFLICT (user_id) DO UPDATE
SET muted_by = EXCLUDED.muted_by, muted_until = EXCLUDED.muted_until, reason = EXCLUDED.reason;

SELECT public.process_escalations();

SELECT is(
  (
    SELECT count(*)::integer
    FROM public.alerts
    WHERE user_id = '30000000-0000-4000-8000-000000000004'
      AND status = 'open'
      AND cause IN ('silence', 'dark_device')
  ),
  1,
  'an expired mute does not suppress a new alert'
);

INSERT INTO public.gm_mutes (user_id, muted_by, muted_until, reason)
VALUES (
  '30000000-0000-4000-8000-000000000005',
  '30000000-0000-4000-8000-000000000001',
  now() + interval '1 day',
  'existing alert must continue'
)
ON CONFLICT (user_id) DO UPDATE
SET muted_by = EXCLUDED.muted_by, muted_until = EXCLUDED.muted_until, reason = EXCLUDED.reason;

INSERT INTO public.alerts (
  id,
  user_id,
  cause,
  stage,
  status,
  opened_at,
  stage_entered_at,
  next_deadline
)
VALUES (
  '30000000-0000-4000-8000-000000000020',
  '30000000-0000-4000-8000-000000000005',
  'dark_device',
  'self',
  'open',
  now() - interval '1 hour',
  now() - interval '1 hour',
  now() - interval '1 minute'
)
ON CONFLICT (id) DO UPDATE
SET stage = 'self', status = 'open', next_deadline = now() - interval '1 minute';

SELECT public.process_escalations();

SELECT is(
  (
    SELECT stage
    FROM public.alerts
    WHERE id = '30000000-0000-4000-8000-000000000020'
  ),
  'group',
  'muting does not pause or stop escalation of an existing open alert'
);

-- ADR-0037/ADR-0039 retired the history-seeded threshold authority. The pin below
-- still fails closed on any silent change to the live threshold source, but it now
-- pins the accepted account_normal_bounds definition instead of the retired one.
SELECT is(
  encode(
    extensions.digest(
      replace(
        pg_get_functiondef('private.silence_threshold(uuid)'::regprocedure),
        E'\r\n',
        E'\n'
      ),
      'sha256'
    ),
    'hex'
  ),
  'c3efc6cc664dc334166a034651ff584d4c7766d80775c3fe3bc012eb97a9b150',
  'GM mute keeps the authorized account-bound silence threshold'
);

SELECT ok(
  strpos(
    pg_get_functiondef('private.silence_threshold(uuid)'::regprocedure),
    'account_normal_bounds'
  ) > 0
  AND strpos(
    pg_get_functiondef('private.silence_threshold(uuid)'::regprocedure),
    'user_activity_profiles'
  ) = 0,
  'live threshold authority is account_normal_bounds, not the retired history-seeded profile'
);

SELECT * FROM finish();
ROLLBACK;
