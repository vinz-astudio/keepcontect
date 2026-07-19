-- pgTAP database-level routine safety and security tests
BEGIN;

SELECT plan(35);

-- Setup test users with typical columns to avoid constraints
INSERT INTO auth.users (id, email, aud, role) VALUES
  ('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'usera@example.com', 'authenticated', 'authenticated'),
  ('b0eebc99-9c0b-4ef8-bb6d-6bb9bd380b22', 'userb@example.com', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

-- Setup baseline device_state and alerts for User A
INSERT INTO public.device_state (user_id, last_heartbeat_at)
VALUES ('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', now() - interval '2 hours')
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO public.alerts (user_id, status, opened_at, cause, stage)
VALUES ('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'open', now() - interval '1 hour', 'silence', 'self')
ON CONFLICT DO NOTHING;

-- Setup check-in task for User A (created by User B)
INSERT INTO public.checkin_tasks (ward_id, status, cycle_state, next_due_at, grace_minutes, kind, interval_hours, created_by)
VALUES (
  'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
  'active',
  'due_notified',
  now() - interval '3 hours',
  30,
  'interval',
  4,
  'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380b22'
)
ON CONFLICT DO NOTHING;

-- 1. Test anon role: direct INSERT on behavior_pings is denied (throws 42501)
SET local role anon;
SELECT throws_ok(
    $$ INSERT INTO public.behavior_pings (user_id, kind, source) VALUES ('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'app', 'installed_pwa') $$,
    '42501'::char(5),
    NULL,
    'Anonymous users must be blocked from direct insert into behavior_pings'
);

-- 2. Test anon role: RPC record_behavior_ping is denied (throws 42501)
SELECT throws_ok(
    $$ SELECT public.record_behavior_ping('c0eebc99-9c0b-4ef8-bb6d-6bb9bd380c33'::uuid, now(), 'installed_pwa', 'app') $$,
    '42501'::char(5),
    NULL,
    'Anonymous users must be blocked from calling public.record_behavior_ping'
);

-- 3. Test anon role: RPC record_behavior_pings is denied (throws 42501)
SELECT throws_ok(
    $$ SELECT public.record_behavior_pings('[{"kind":"app"}]'::jsonb) $$,
    '42501'::char(5),
    NULL,
    'Anonymous users must be blocked from calling public.record_behavior_pings'
);

-- 4. Test user A role: direct INSERT must be denied to authenticated users (throws 42501)
SET local role authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11"}', true);
SELECT throws_ok(
    $$ INSERT INTO public.behavior_pings (user_id, kind, source) VALUES ('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'app', 'installed_pwa') $$,
    '42501'::char(5),
    NULL,
    'Direct INSERT to behavior_pings must be revoked for authenticated users'
);

SELECT throws_ok(
    $$ SELECT public.record_behavior_ping_for_user('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'::uuid, '11000000-0000-0000-0000-000000000001'::uuid, now(), 'installed_pwa', 'app') $$,
    '42501'::char(5),
    NULL,
    'Authenticated users must be blocked from the service-only ping RPC'
);

SET local role anon;
SELECT throws_ok(
    $$ SELECT public.record_behavior_ping_for_user('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'::uuid, '11000000-0000-0000-0000-000000000002'::uuid, now(), 'installed_pwa', 'app') $$,
    '42501'::char(5),
    NULL,
    'Anonymous users must be blocked from the service-only ping RPC'
);

-- 5. Check RPC Signature: record_behavior_ping must have parameters matching (event_id, observed_at, source, kind)
SET local role service_role;
SELECT has_function(
    'public',
    'record_behavior_ping',
    ARRAY['uuid', 'timestamptz', 'text', 'text'],
    'public.record_behavior_ping signature must be record_behavior_ping(event_id uuid, observed_at timestamptz, source text, kind text)'
);

-- 6. Check RPC Signature: record_behavior_pings must have parameter matching (events jsonb)
SELECT has_function(
    'public',
    'record_behavior_pings',
    ARRAY['jsonb'],
    'public.record_behavior_pings signature must be record_behavior_pings(events jsonb)'
);

SELECT results_eq(
    $$ SELECT public.record_behavior_ping_for_user('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'::uuid, '11000000-0000-0000-0000-000000000003'::uuid, now(), 'manual', 'manual_checkin') $$,
    $$ VALUES ('inserted'::text) $$,
    'Service role must be able to record a validated ping for its resolved user'
);

-- 7. Test User A RPC: executing record_behavior_ping succeeds and returns 'inserted'
SET local role authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11"}', true);
SELECT results_eq(
    $$ SELECT public.record_behavior_ping('e0eebc99-9c0b-4ef8-bb6d-6bb9bd380e55'::uuid, now(), 'installed_pwa', 'app') $$,
    $$ VALUES ('inserted'::text) $$,
    'record_behavior_ping must run successfully and return status inserted'
);

-- 8. Verify User A Row is created with server-assigned received_at and ingest_version = 2
SET local role service_role;
SELECT results_eq(
    $$ SELECT user_id, ingest_version::int, received_at IS NOT NULL FROM public.behavior_pings WHERE event_id = 'e0eebc99-9c0b-4ef8-bb6d-6bb9bd380e55'::uuid $$,
    $$ VALUES ('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'::uuid, 2, true) $$,
    'behavior_pings record must have ingest_version=2 and server-assigned received_at'
);

-- 9. Idempotency test: duplicate event call returns 'duplicate' status
SET local role authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11"}', true);
SELECT results_eq(
    $$ SELECT public.record_behavior_ping('e0eebc99-9c0b-4ef8-bb6d-6bb9bd380e55'::uuid, now(), 'installed_pwa', 'app') $$,
    $$ VALUES ('duplicate'::text) $$,
    'Duplicate event_id call must return duplicate status'
);

-- 10. Idempotency count test: duplicate call does not insert any new rows (count remains one)
SET local role service_role;
SELECT results_eq(
    $$ SELECT count(*)::int FROM public.behavior_pings WHERE event_id = 'e0eebc99-9c0b-4ef8-bb6d-6bb9bd380e55'::uuid $$,
    $$ VALUES (1) $$,
    'Duplicate event ID insertion must keep total count at exactly 1'
);

-- 11. Partition Isolation: User B select query must not see User A records
SET local role authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "b0eebc99-9c0b-4ef8-bb6d-6bb9bd380b22"}', true);
SELECT is_empty(
    $$ SELECT * FROM public.behavior_pings WHERE user_id = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11' $$,
    'User B must be unable to read User A behavior pings'
);

-- 12. Test service role: service_role can verify overall count
SET local role service_role;
SELECT lives_ok(
    $$ SELECT count(*) FROM public.behavior_pings $$,
    'Service role must have permission to read all behavior pings counts'
);

-- Reset the live-event fixture from tests 7-10 before testing offline safety.
-- Otherwise that real v2 event has already refreshed the heartbeat, resolved
-- the alert, satisfied the check-in, and occupied the current coalescing bucket.
RESET ROLE;
DELETE FROM public.behavior_pings
WHERE user_id = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
UPDATE public.device_state
SET last_heartbeat_at = now() - interval '2 hours'
WHERE user_id = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
UPDATE public.alerts
SET status = 'open', resolved_at = NULL, resolved_by = NULL
WHERE user_id = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';

-- 13. Test offline safety: call old offline v2 event observed 2 hours ago (before alert created 1 hour ago)
-- Verify device_state.last_heartbeat_at is unchanged (still 2 hours ago)
SET local role authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11"}', true);
SELECT public.record_behavior_ping('f0eebc99-9c0b-4ef8-bb6d-6bb9bd380f66'::uuid, now() - interval '2 hours', 'installed_pwa', 'app');

SET local role service_role;
SELECT results_eq(
    $$ SELECT last_heartbeat_at <= now() - interval '1.5 hours' FROM public.device_state WHERE user_id = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11' $$,
    $$ VALUES (true) $$,
    'Offline event observed before alert creation must not refresh last_heartbeat_at'
);

-- 14. Test offline safety: check that the active silence alert remains open
SELECT results_eq(
    $$ SELECT status FROM public.alerts WHERE user_id = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11' ORDER BY opened_at DESC LIMIT 1 $$,
    $$ VALUES ('open'::text) $$,
    'Offline event observed before alert creation must keep alert open'
);

SET local role authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11"}', true);
SELECT ok(
    (public.my_routine_status() ->> 'last_behavior_at') IS NULL,
    'Offline event outside live drift must not appear current in my_routine_status'
);

-- 15. Test offline safety: run process_checkin_tasks
RESET ROLE;
SELECT lives_ok(
    $$ SELECT public.process_checkin_tasks() $$,
    'Running process_checkin_tasks after old offline event succeeds'
);

-- 16. Test offline safety: assert that task_missed notification exists for User B (creator of the task)
SELECT ok(
    EXISTS (SELECT 1 FROM public.notifications WHERE recipient_id = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380b22' AND kind = 'task_missed'),
    'A task_missed notification must exist for User B (task creator) because User A offline upload did not satisfy the task due/grace constraints'
);

-- 17. Test future safety: future ping (>5m drift) returns 'invalid' status
SET local role authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11"}', true);
SELECT results_eq(
    $$ SELECT public.record_behavior_ping('d0eebc99-9c0b-4ef8-bb6d-6bb9bd380d44'::uuid, now() + interval '10 minutes', 'installed_pwa', 'app') $$,
    $$ VALUES ('invalid'::text) $$,
    'Future event > 5m drift must return invalid status'
);

-- 18. Test future safety: heartbeat remains unchanged
SET local role service_role;
SELECT results_eq(
    $$ SELECT last_heartbeat_at <= now() - interval '1.5 hours' FROM public.device_state WHERE user_id = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11' $$,
    $$ VALUES (true) $$,
    'Future event > 5m drift must not update device_state last_heartbeat_at'
);

-- 19. Batch Ingestion: record_behavior_pings processes valid events, dynamic building array, asserting ordinal order
SET local role authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11"}', true);
SELECT results_eq(
    $$
      SELECT status FROM public.record_behavior_pings(
        jsonb_build_array(
          jsonb_build_object('event_id', '00000000-0000-0000-0000-000000000001'::uuid, 'observed_at', now(), 'source', 'installed_pwa', 'kind', 'app'),
          jsonb_build_object('event_id', '00000000-0000-0000-0000-000000000002'::uuid, 'observed_at', now() + interval '1 second', 'source', 'tauri', 'kind', 'app')
        )
      )
    $$,
    $$ VALUES ('inserted'::text), ('inserted'::text) $$,
    'Batch ingestion RPC must ingest multiple valid events and return statuses in dynamic input ordinal order'
);

SET local role service_role;
SELECT results_eq(
    $$ SELECT status FROM public.alerts WHERE user_id = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11' ORDER BY opened_at DESC LIMIT 1 $$,
    $$ VALUES ('resolved'::text) $$,
    'A genuinely live batch event observed and received after opened_at must resolve the alert'
);

-- 20. Ingestion bounds: record_behavior_pings with >100 elements throws (limit exceeded)
SET local role authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11"}', true);
SELECT throws_like(
    $$
      SELECT public.record_behavior_pings(
        (SELECT jsonb_agg(jsonb_build_object('event_id', gen_random_uuid(), 'observed_at', now(), 'source', 'installed_pwa', 'kind', 'app'))
         FROM generate_series(1, 101))
      )
    $$,
    '%batch elements exceed maximum%',
    'Batch elements exceed maximum threshold of 100'
);

SELECT results_eq(
    $$
      SELECT status FROM public.record_behavior_pings(
        jsonb_build_array(
          jsonb_build_object('event_id', '22000000-0000-0000-0000-000000000001', 'observed_at', now(), 'source', 'manual', 'kind', 'manual_checkin'),
          jsonb_build_object('event_id', '22000000-0000-0000-0000-000000000002', 'observed_at', 'not-a-timestamp', 'source', 'manual', 'kind', 'manual_checkin'),
          jsonb_build_object('event_id', '22000000-0000-0000-0000-000000000003', 'observed_at', now(), 'source', 'manual', 'kind', 'manual_checkin')
        )
      )
    $$,
    $$ VALUES ('inserted'::text), ('invalid'::text), ('inserted'::text) $$,
    'Malformed batch input must stay in ordinal position as invalid while valid neighbors succeed'
);

-- 21. Initializer access control: public.initialize_user_routine_data execution throws 42501 for authenticated users
SET local role authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11"}', true);
SELECT throws_ok(
    $$ SELECT public.initialize_user_routine_data('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'::uuid) $$,
    '42501'::char(5),
    NULL,
    'Authenticated users must be denied execution on public.initialize_user_routine_data'
);

-- 22. Cron schedule configuration: asserts command is exactly select public.run_daily_aggregations();
SET local role service_role;
SELECT results_eq(
    $$ SELECT trim(both ' ' from command) FROM cron.job WHERE jobname = 'run-daily-aggregations' $$,
    $$ VALUES ('select public.run_daily_aggregations();'::text) $$,
    'Weekly daily aggregates cron job command must match select public.run_daily_aggregations();'
);

-- 23. Cron execution safety: executing the aggregation command succeeds
RESET ROLE;
SELECT lives_ok(
    $$ select public.run_daily_aggregations(); $$,
    'Executing daily aggregations RPC directly succeeds'
);

-- ADR-0022: sensitivity remains an additive user tool on the deterministic
-- 1.5h Gate 1 base. Learned profiles stay quarantined from live safety.
RESET ROLE;
UPDATE public.user_settings
SET sensitivity = 'high'
WHERE user_id = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
SELECT results_eq(
    $$ SELECT round(extract(epoch from private.silence_threshold('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11')) / 3600.0, 2) $$,
    $$ VALUES (1.50::numeric) $$,
    'High sensitivity must equal the 1.5h neutral base plus 0 minutes'
);

UPDATE public.user_settings
SET sensitivity = 'balanced'
WHERE user_id = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
SELECT results_eq(
    $$ SELECT round(extract(epoch from private.silence_threshold('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11')) / 3600.0, 2) $$,
    $$ VALUES (2.25::numeric) $$,
    'Balanced sensitivity must equal the 1.5h neutral base plus 45 minutes'
);

UPDATE public.user_settings
SET sensitivity = 'low'
WHERE user_id = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
SELECT results_eq(
    $$ SELECT round(extract(epoch from private.silence_threshold('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11')) / 3600.0, 2) $$,
    $$ VALUES (3.00::numeric) $$,
    'Low sensitivity must equal the 1.5h neutral base plus 90 minutes'
);

INSERT INTO public.user_activity_profiles (user_id, hourly_thresholds, weekend_multiplier)
VALUES (
  'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
  array_fill(12.0::double precision, ARRAY[24]),
  5.0
)
ON CONFLICT (user_id) DO UPDATE
SET hourly_thresholds = excluded.hourly_thresholds,
    weekend_multiplier = excluded.weekend_multiplier;
SELECT results_eq(
    $$ SELECT round(extract(epoch from private.silence_threshold('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11')) / 3600.0, 2) $$,
    $$ VALUES (3.00::numeric) $$,
    'Learned profile thresholds and multipliers must not widen the live Gate 1 threshold'
);

SELECT ok(
    NOT has_function_privilege('authenticated', 'private.silence_threshold(uuid)', 'EXECUTE'),
    'Authenticated users must not execute the private threshold function directly'
);

SET local role authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11"}', true);
SELECT results_eq(
    $$ SELECT (public.my_routine_status() ->> 'threshold_seconds')::bigint $$,
    $$ VALUES (10800::bigint) $$,
    'Routine server-truth RPC must expose the same corrected low threshold'
);

SELECT * FROM finish();
ROLLBACK;
