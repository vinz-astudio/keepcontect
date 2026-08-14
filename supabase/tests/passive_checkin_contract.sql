-- ADR-0042 package 1: persisted user-owned passive check-in contract.
-- Structural RED comes first. Behavioural assertions are added after the
-- storage skeleton exists, before either RPC body is implemented.

BEGIN;

SELECT plan(68);

SELECT has_table('public', 'passive_checkin_accounts',
  'one account row owns engine mode and active pointers');
SELECT has_table('public', 'passive_checkin_contract_versions',
  'D N and sleep choice are immutable versioned contracts');
SELECT has_table('public', 'passive_monitoring_epochs',
  'monitoring epochs make settings and resolution boundaries explicit');
SELECT has_table('public', 'passive_checkin_windows',
  'server-owned UTC windows persist deterministic outcomes');
SELECT has_table('private', 'passive_alert_causal_windows',
  'alert causal windows are stored outside the client surface');

SELECT has_column('public', 'passive_checkin_accounts', 'engine_mode',
  'account engine mode is explicit');
SELECT has_column('public', 'passive_checkin_accounts', 'active_contract_version_id',
  'account points at its active immutable contract');
SELECT has_column('public', 'passive_checkin_accounts', 'active_epoch_id',
  'account points at its active monitoring epoch');

SELECT has_column('public', 'passive_checkin_contract_versions', 'interval_minutes',
  'contract persists user-owned D');
SELECT has_column('public', 'passive_checkin_contract_versions', 'consecutive_misses',
  'contract persists user-owned N');
SELECT has_column('public', 'passive_checkin_contract_versions', 'sleep_policy',
  'contract persists the required sleep choice');
SELECT has_column('public', 'passive_checkin_contract_versions', 'effective_at',
  'server acknowledgement time is persisted');

SELECT has_column('public', 'passive_monitoring_epochs', 'started_at',
  'epoch start is server-owned');
SELECT has_column('public', 'passive_monitoring_epochs', 'start_reason',
  'epoch boundary records why it exists');

SELECT has_column('public', 'passive_checkin_windows', 'window_start',
  'window has an inclusive start');
SELECT has_column('public', 'passive_checkin_windows', 'window_end',
  'window has an exclusive end');
SELECT has_column('public', 'passive_checkin_windows', 'arrival_deadline',
  'late positive evidence has an explicit allowance deadline');
SELECT has_column('public', 'passive_checkin_windows', 'outcome',
  'window outcome is persisted');

SELECT has_function(
  'public', 'set_passive_checkin_contract',
  ARRAY['integer','integer','text','time without time zone','time without time zone','text','text','text'],
  'one authenticated RPC changes the contract after validation'
);
SELECT has_function('public', 'my_passive_checkin_status', ARRAY[]::text[],
  'the subject has one summarized read RPC');

SELECT has_index('public', 'passive_monitoring_epochs',
  'passive_monitoring_epochs_one_active_per_user',
  'one account cannot have two active epochs');
SELECT has_index('public', 'passive_checkin_windows',
  'passive_checkin_windows_epoch_ordinal_uidx',
  'an epoch ordinal identifies exactly one window');

SELECT ok(
  (SELECT c.relrowsecurity
   FROM pg_class AS c
   WHERE c.oid = to_regclass('public.passive_checkin_accounts')) IS TRUE,
  'account contract storage has RLS enabled'
);
SELECT ok(
  (SELECT c.relrowsecurity
   FROM pg_class AS c
   WHERE c.oid = to_regclass('public.passive_checkin_windows')) IS TRUE,
  'window storage has RLS enabled'
);

INSERT INTO auth.users (id, email, aud, role) VALUES
  ('71000000-0000-4000-8000-000000000001', 'passive-contract-a@example.invalid', 'authenticated', 'authenticated'),
  ('71000000-0000-4000-8000-000000000002', 'passive-contract-b@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, display_name) VALUES
  ('71000000-0000-4000-8000-000000000001', 'Passive contract A'),
  ('71000000-0000-4000-8000-000000000002', 'Passive contract B')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

CREATE TEMP TABLE passive_contract_results (
  label text PRIMARY KEY,
  payload jsonb NOT NULL
);

SELECT set_config('request.jwt.claim.sub',
  '71000000-0000-4000-8000-000000000002', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);

SELECT is(
  public.my_passive_checkin_status() ->> 'engine_mode',
  'legacy',
  'an existing account with no passive row stays legacy'
);
SELECT ok(
  (public.my_passive_checkin_status() -> 'contract') = 'null'::jsonb,
  'legacy status invents no contract'
);

SELECT set_config('request.jwt.claim.sub', '', true);
SELECT throws_ok(
  $$ SELECT public.my_passive_checkin_status() $$,
  '28000', NULL,
  'status requires an authenticated subject'
);
SELECT throws_ok(
  $$ SELECT public.set_passive_checkin_contract(60, 3, 'none', NULL, NULL, NULL, 'shadow', 'passive-checkin-v1') $$,
  '28000', NULL,
  'contract changes require an authenticated subject'
);

SELECT set_config('request.jwt.claim.sub',
  '71000000-0000-4000-8000-000000000001', true);

SELECT throws_ok(
  $$ SELECT public.set_passive_checkin_contract(19, 3, 'none', NULL, NULL, NULL, 'shadow', 'passive-checkin-v1') $$,
  '22023', NULL, 'D below 20 minutes is rejected'
);
SELECT throws_ok(
  $$ SELECT public.set_passive_checkin_contract(361, 3, 'none', NULL, NULL, NULL, 'shadow', 'passive-checkin-v1') $$,
  '22023', NULL, 'D above 360 minutes is rejected'
);
SELECT throws_ok(
  $$ SELECT public.set_passive_checkin_contract(60, 0, 'none', NULL, NULL, NULL, 'shadow', 'passive-checkin-v1') $$,
  '22023', NULL, 'N below one is rejected'
);
SELECT throws_ok(
  $$ SELECT public.set_passive_checkin_contract(60, 1000001, 'none', NULL, NULL, NULL, 'shadow', 'passive-checkin-v1') $$,
  '22023', NULL, 'N above one million is rejected'
);
SELECT throws_ok(
  $$ SELECT public.set_passive_checkin_contract(60, 3, 'later', NULL, NULL, NULL, 'shadow', 'passive-checkin-v1') $$,
  '22023', NULL, 'a missing explicit sleep-policy choice is rejected'
);
SELECT throws_ok(
  $$ SELECT public.set_passive_checkin_contract(60, 3, 'configured', NULL, '07:00', 'Asia/Dhaka', 'shadow', 'passive-checkin-v1') $$,
  '22023', NULL, 'configured sleep requires both local bounds'
);
SELECT throws_ok(
  $$ SELECT public.set_passive_checkin_contract(60, 3, 'configured', '23:00', '23:00', 'Asia/Dhaka', 'shadow', 'passive-checkin-v1') $$,
  '22023', NULL, 'configured sleep cannot have identical bounds'
);
SELECT throws_ok(
  $$ SELECT public.set_passive_checkin_contract(60, 3, 'configured', '23:00', '07:00', 'Mars/Olympus', 'shadow', 'passive-checkin-v1') $$,
  '22023', NULL, 'configured sleep requires a real IANA timezone'
);
SELECT throws_ok(
  $$ SELECT public.set_passive_checkin_contract(60, 3, 'none', NULL, NULL, NULL, 'shadow', 'old-client-v0') $$,
  '22023', NULL, 'an old client cannot edit passive settings'
);
SELECT throws_ok(
  $$ SELECT public.set_passive_checkin_contract(60, 3, 'none', NULL, NULL, NULL, 'passive_checkin', 'passive-checkin-v1') $$,
  '0A000', NULL, 'package 1 cannot activate live passive authority before capability gates exist'
);

SELECT lives_ok(
  $$
    INSERT INTO passive_contract_results(label, payload)
    VALUES (
      'first',
      public.set_passive_checkin_contract(
        60, 3, 'none', NULL, NULL, NULL, 'shadow', 'passive-checkin-v1'
      )
    )
  $$,
  'a valid no-sleep shadow contract is server-acknowledged'
);
SELECT is(
  (SELECT payload ->> 'engine_mode' FROM passive_contract_results WHERE label = 'first'),
  'shadow', 'the acknowledged mode is shadow'
);
SELECT is(
  (SELECT (payload #>> '{contract,interval_minutes}')::integer
   FROM passive_contract_results WHERE label = 'first'),
  60, 'the acknowledgement echoes active D'
);
SELECT is(
  (SELECT (payload #>> '{contract,nominal_h_minutes}')::bigint
   FROM passive_contract_results WHERE label = 'first'),
  180::bigint, 'the acknowledgement exposes H = D times N'
);
SELECT is(
  (SELECT count(*)::integer FROM public.passive_checkin_contract_versions
   WHERE user_id = '71000000-0000-4000-8000-000000000001'),
  1, 'first save creates exactly one immutable version'
);
SELECT is(
  (SELECT count(*)::integer FROM public.passive_monitoring_epochs
   WHERE user_id = '71000000-0000-4000-8000-000000000001'
     AND ended_at IS NULL),
  1, 'first save creates exactly one active epoch'
);
SELECT is(
  (SELECT extract(epoch FROM (window_end - window_start))::integer / 60
   FROM public.passive_checkin_windows
   WHERE user_id = '71000000-0000-4000-8000-000000000001'),
  60, 'first window duration is exactly D in UTC'
);
SELECT ok(
  (SELECT arrival_deadline = window_end
   FROM public.passive_checkin_windows
   WHERE user_id = '71000000-0000-4000-8000-000000000001'),
  'before package 2 binds surfaces the arrival allowance is explicitly zero'
);
SELECT ok(
  (SELECT abs(extract(epoch FROM (v.effective_at - w.window_start))) < 0.001
   FROM public.passive_checkin_contract_versions AS v
   JOIN public.passive_checkin_windows AS w ON w.contract_version_id = v.id
   WHERE v.user_id = '71000000-0000-4000-8000-000000000001'),
  'the server effective time is the epoch and first-window boundary'
);

SELECT ok(
  NOT has_table_privilege('authenticated', 'public.passive_checkin_accounts', 'SELECT')
  AND NOT has_table_privilege('authenticated', 'public.passive_checkin_contract_versions', 'SELECT')
  AND NOT has_table_privilege('authenticated', 'public.passive_monitoring_epochs', 'SELECT')
  AND NOT has_table_privilege('authenticated', 'public.passive_checkin_windows', 'SELECT')
  AND NOT has_table_privilege('anon', 'public.passive_checkin_accounts', 'SELECT'),
  'contract storage is RPC-only for client roles'
);
SELECT ok(
  has_function_privilege(
    'authenticated',
    'public.set_passive_checkin_contract(integer,integer,text,time without time zone,time without time zone,text,text,text)',
    'EXECUTE'
  )
  AND has_function_privilege('authenticated', 'public.my_passive_checkin_status()', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'public.my_passive_checkin_status()', 'EXECUTE'),
  'only authenticated callers retain the two public RPC paths'
);
SELECT throws_ok(
  $$
    UPDATE public.passive_checkin_contract_versions
    SET interval_minutes = 20
    WHERE user_id = '71000000-0000-4000-8000-000000000001'
  $$,
  '55000', NULL, 'an accepted contract version cannot be rewritten'
);

SELECT lives_ok(
  $$
    INSERT INTO passive_contract_results(label, payload)
    VALUES (
      'second',
      public.set_passive_checkin_contract(
        30, 2, 'configured', '23:00', '07:00', 'Asia/Dhaka',
        'shadow', 'passive-checkin-v1'
      )
    )
  $$,
  'a second acknowledged contract creates a clean epoch boundary'
);
SELECT is(
  (SELECT (payload #>> '{contract,version_number}')::bigint
   FROM passive_contract_results WHERE label = 'second'),
  2::bigint, 'the second acknowledgement names version two'
);
SELECT is(
  (SELECT count(*)::integer FROM public.passive_checkin_contract_versions
   WHERE user_id = '71000000-0000-4000-8000-000000000001'),
  2, 'the prior version is preserved beside the new version'
);
SELECT is(
  (SELECT count(*)::integer FROM public.passive_monitoring_epochs
   WHERE user_id = '71000000-0000-4000-8000-000000000001'
     AND ended_at IS NOT NULL),
  1, 'the old epoch is closed exactly once'
);
SELECT is(
  (SELECT count(*)::integer FROM public.passive_checkin_windows
   WHERE user_id = '71000000-0000-4000-8000-000000000001'
     AND outcome = 'superseded'),
  1, 'the partial old window is superseded rather than counted'
);
SELECT is(
  (SELECT count(*)::integer FROM public.passive_monitoring_epochs
   WHERE user_id = '71000000-0000-4000-8000-000000000001'
     AND ended_at IS NULL),
  1, 'exactly one new epoch remains active'
);
SELECT is(
  (SELECT extract(epoch FROM (window_end - window_start))::integer / 60
   FROM public.passive_checkin_windows
   WHERE user_id = '71000000-0000-4000-8000-000000000001'
     AND outcome = 'pending'),
  30, 'the new first window uses the new D'
);
SELECT is(
  (SELECT ordinal FROM public.passive_checkin_windows
   WHERE user_id = '71000000-0000-4000-8000-000000000001'
     AND outcome = 'pending'),
  0::bigint, 'the new epoch restarts window ordinal zero'
);
SELECT is(
  public.my_passive_checkin_status() ->> 'engine_mode',
  'shadow', 'the owner reads the active engine mode'
);
SELECT is(
  (public.my_passive_checkin_status() #>> '{contract,interval_minutes}')::integer,
  30, 'the owner reads only the active contract summary'
);
SELECT is(
  (SELECT sleep_policy FROM public.passive_checkin_contract_versions
   WHERE user_id = '71000000-0000-4000-8000-000000000001'
   ORDER BY version_number DESC LIMIT 1),
  'configured', 'the explicit sleep choice is in the active immutable snapshot'
);
SELECT is(
  (SELECT timezone FROM public.passive_checkin_contract_versions
   WHERE user_id = '71000000-0000-4000-8000-000000000001'
   ORDER BY version_number DESC LIMIT 1),
  'Asia/Dhaka', 'the configured sleep snapshot keeps its IANA timezone'
);
SELECT is(
  (SELECT interval_minutes FROM public.passive_checkin_contract_versions
   WHERE user_id = '71000000-0000-4000-8000-000000000001'
     AND version_number = 1),
  60, 'creating version two did not rewrite version one'
);
SELECT ok(
  (SELECT a.active_contract_version_id = v.id
   FROM public.passive_checkin_accounts AS a
   JOIN public.passive_checkin_contract_versions AS v
     ON v.user_id = a.user_id AND v.version_number = 2
   WHERE a.user_id = '71000000-0000-4000-8000-000000000001'),
  'the account pointer advances only to the acknowledged version'
);

SELECT set_config('request.jwt.claim.sub',
  '71000000-0000-4000-8000-000000000002', true);
SELECT is(
  public.my_passive_checkin_status() ->> 'engine_mode',
  'legacy', 'another account remains legacy after account A opts into shadow'
);
SELECT ok(
  (public.my_passive_checkin_status() -> 'contract') = 'null'::jsonb,
  'another account cannot read account A contract IDs or settings'
);
SELECT is(
  (SELECT count(*)::integer FROM public.passive_checkin_accounts
   WHERE user_id = '71000000-0000-4000-8000-000000000002'),
  0, 'a read does not silently migrate an existing account'
);
SELECT is(
  (SELECT engine_mode FROM public.passive_checkin_accounts
   WHERE user_id = '71000000-0000-4000-8000-000000000001'),
  'shadow', 'only the explicitly saved account leaves legacy mode'
);

SELECT * FROM finish();
ROLLBACK;
