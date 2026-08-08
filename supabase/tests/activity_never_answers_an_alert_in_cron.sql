-- process_escalations must not close an open alert because the subject was
-- active. Sleep grace remains the one clearance it is allowed to apply.
BEGIN;

SELECT plan(7);

INSERT INTO auth.users (id, email, aud, role) VALUES
  ('40810000-0000-4000-8000-000000000001', 'cron-ping@example.invalid', 'authenticated', 'authenticated'),
  ('40810000-0000-4000-8000-000000000002', 'cron-dark@example.invalid', 'authenticated', 'authenticated'),
  ('40810000-0000-4000-8000-000000000003', 'cron-sleep@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, display_name) VALUES
  ('40810000-0000-4000-8000-000000000001', 'Active but unanswered'),
  ('40810000-0000-4000-8000-000000000002', 'Device came back'),
  ('40810000-0000-4000-8000-000000000003', 'Asleep')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

-- Muted so the raise loop cannot invent extra alerts mid-test; the clearance
-- loop under test ignores mutes, which is exactly what we want to observe.
INSERT INTO public.gm_mutes (user_id, muted_by, muted_until, reason)
SELECT u, '40810000-0000-4000-8000-000000000001', now() + interval '1 day', 'test isolation'
FROM unnest(ARRAY[
  '40810000-0000-4000-8000-000000000001',
  '40810000-0000-4000-8000-000000000002',
  '40810000-0000-4000-8000-000000000003'
]::uuid[]) AS u
ON CONFLICT (user_id) DO UPDATE SET muted_until = EXCLUDED.muted_until;

INSERT INTO public.device_state (user_id, status, last_heartbeat_at) VALUES
  ('40810000-0000-4000-8000-000000000001', 'normal', now()),
  -- The dark device has reported in again: under the old rule this alone closed
  -- the alert.
  ('40810000-0000-4000-8000-000000000002', 'normal', now()),
  ('40810000-0000-4000-8000-000000000003', 'normal', now() - interval '3 hours')
ON CONFLICT (user_id) DO UPDATE
SET status = EXCLUDED.status, last_heartbeat_at = EXCLUDED.last_heartbeat_at;

INSERT INTO public.alerts (id, user_id, cause, status, stage, opened_at, stage_entered_at, next_deadline) VALUES
  ('40810000-0000-4000-8000-0000000000a1', '40810000-0000-4000-8000-000000000001',
   'silence', 'open', 'self', now() - interval '40 minutes', now() - interval '40 minutes', now() + interval '1 hour'),
  ('40810000-0000-4000-8000-0000000000a2', '40810000-0000-4000-8000-000000000002',
   'dark_device', 'open', 'self', now() - interval '40 minutes', now() - interval '40 minutes', now() + interval '1 hour'),
  ('40810000-0000-4000-8000-0000000000a3', '40810000-0000-4000-8000-000000000003',
   'silence', 'open', 'self', now() - interval '40 minutes', now() - interval '40 minutes', now() + interval '1 hour');

-- A qualifying v2 ping after the alert opened: activity, and under the rule
-- written on 2026-06-10 this closed the alert on the next cron tick.
INSERT INTO public.behavior_pings (user_id, kind, at, received_at, ingest_version) VALUES
  ('40810000-0000-4000-8000-000000000001', 'app', now() - interval '1 minute', now() - interval '1 minute', 2);

-- Put the sleeper inside a configured sleep window covering "now".
INSERT INTO public.user_settings (user_id, sleep_start_local, sleep_end_local, timezone)
VALUES ('40810000-0000-4000-8000-000000000003', '00:00', '23:59', 'UTC')
ON CONFLICT (user_id) DO UPDATE
SET sleep_start_local = EXCLUDED.sleep_start_local,
    sleep_end_local = EXCLUDED.sleep_end_local,
    timezone = EXCLUDED.timezone;

SELECT ok(
  private.sleep_relaxed('40810000-0000-4000-8000-000000000003', now()),
  'precondition: the sleeper is inside their configured quiet window'
);

SELECT public.process_escalations();

SELECT is(
  (SELECT status FROM public.alerts WHERE id = '40810000-0000-4000-8000-0000000000a1'),
  'open',
  'a fresh qualifying ping does not close an open silence alert - activity is not an answer'
);

SELECT is(
  (SELECT status FROM public.alerts WHERE id = '40810000-0000-4000-8000-0000000000a2'),
  'open',
  'a dark device reporting in again does not close its open alert'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM public.alert_events
    WHERE alert_id IN (
      '40810000-0000-4000-8000-0000000000a1',
      '40810000-0000-4000-8000-0000000000a2'
    )
      AND kind = 'auto_resolved'
  ),
  0,
  'neither activity case emits an auto_resolved event'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM public.notifications
    WHERE alert_id IN (
      '40810000-0000-4000-8000-0000000000a1',
      '40810000-0000-4000-8000-0000000000a2'
    )
      AND kind = 'auto_resolved'
  ),
  0,
  'and no auto_resolved notification is broadcast to watchers for them'
);

SELECT is(
  (SELECT status FROM public.alerts WHERE id = '40810000-0000-4000-8000-0000000000a3'),
  'resolved',
  'sleep grace still withdraws a silence alert raised against an expected quiet window'
);

SELECT is(
  (
    SELECT note
    FROM public.alert_events
    WHERE alert_id = '40810000-0000-4000-8000-0000000000a3' AND kind = 'auto_resolved'
  ),
  'sleep_grace',
  'the surviving clearance names itself, so the ping-driven path cannot hide behind it in the record'
);

SELECT * FROM finish();

ROLLBACK;
