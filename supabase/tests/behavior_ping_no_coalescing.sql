-- ADR-0029 P3: distinct validated events are evidence, not duplicates.
BEGIN;

SELECT plan(6);

INSERT INTO auth.users (id, email, aud, role)
VALUES (
  '29000000-0000-4000-8000-000000000000',
  'adr29-p3@example.invalid',
  'authenticated',
  'authenticated'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.device_state (user_id, last_heartbeat_at)
VALUES (
  '29000000-0000-4000-8000-000000000000',
  now() - interval '2 hours'
)
ON CONFLICT (user_id) DO UPDATE
SET last_heartbeat_at = EXCLUDED.last_heartbeat_at;

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"29000000-0000-4000-8000-000000000000"}',
  true
);

SELECT results_eq(
  $$
    SELECT public.record_behavior_ping(
      '29000000-0000-4000-8000-000000000001'::uuid,
      date_trunc('minute', now()) + interval '1 second',
      'installed_pwa',
      'interaction'
    )
  $$,
  $$ VALUES ('inserted'::text) $$,
  'first automatic event is inserted'
);

SELECT results_eq(
  $$
    SELECT public.record_behavior_ping(
      '29000000-0000-4000-8000-000000000002'::uuid,
      date_trunc('minute', now()) + interval '2 seconds',
      'installed_pwa',
      'interaction'
    )
  $$,
  $$ VALUES ('inserted'::text) $$,
  'a distinct automatic event in the same five-minute bucket is also inserted'
);

SET LOCAL ROLE service_role;
SELECT results_eq(
  $$
    SELECT count(*)::integer
    FROM public.behavior_pings
    WHERE user_id = '29000000-0000-4000-8000-000000000000'::uuid
      AND event_id IN (
        '29000000-0000-4000-8000-000000000001'::uuid,
        '29000000-0000-4000-8000-000000000002'::uuid
      )
  $$,
  $$ VALUES (2) $$,
  'both distinct same-bucket events persist as evidence'
);

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"29000000-0000-4000-8000-000000000000"}',
  true
);

SELECT results_eq(
  $$
    SELECT public.record_behavior_ping(
      '29000000-0000-4000-8000-000000000001'::uuid,
      date_trunc('minute', now()) + interval '1 second',
      'installed_pwa',
      'interaction'
    )
  $$,
  $$ VALUES ('duplicate'::text) $$,
  'retrying the same event_id remains idempotent'
);

SET LOCAL ROLE service_role;
SELECT results_eq(
  $$
    SELECT count(*)::integer
    FROM public.behavior_pings
    WHERE user_id = '29000000-0000-4000-8000-000000000000'::uuid
      AND event_id = '29000000-0000-4000-8000-000000000001'::uuid
  $$,
  $$ VALUES (1) $$,
  'duplicate retry does not create another row'
);

SELECT results_eq(
  $$
    SELECT count(*)::integer
    FROM public.behavior_pings
    WHERE user_id = '29000000-0000-4000-8000-000000000000'::uuid
      AND event_id IN (
        '29000000-0000-4000-8000-000000000001'::uuid,
        '29000000-0000-4000-8000-000000000002'::uuid
      )
      AND ingest_version = 2
      AND received_at IS NOT NULL
      AND at IN (
        date_trunc('minute', now()) + interval '1 second',
        date_trunc('minute', now()) + interval '2 seconds'
      )
  $$,
  $$ VALUES (2) $$,
  'both stored events retain v2 provenance and their observed timestamps'
);

SELECT * FROM finish();
ROLLBACK;
