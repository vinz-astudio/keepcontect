BEGIN;
SELECT plan(17);

SELECT has_function('private','passive_surface_health_conditions',ARRAY['timestamp with time zone'],'condition derivation exists');
SELECT has_function('private','evaluate_passive_surface_health',ARRAY['timestamp with time zone'],'health interval writer exists');
SELECT ok(has_function_privilege('service_role','private.evaluate_passive_surface_health(timestamp with time zone)','EXECUTE')
  AND NOT has_function_privilege('authenticated','private.evaluate_passive_surface_health(timestamp with time zone)','EXECUTE'),'only service role may evaluate health');
SELECT ok(NOT has_table_privilege('authenticated','private.passive_surface_health_intervals','SELECT'),'health history is not client-readable');

-- The boundary. Health serves display and learner exclusion only; it may not
-- reach window state, the miss chain, alert creation or escalation.
SELECT ok(position('passive_surface_health' in pg_get_functiondef('private.process_passive_checkin_subject(uuid,timestamp with time zone)'::regprocedure))=0,
  'window derivation cannot read surface health');
SELECT ok(position('evaluate_passive_surface_health' in pg_get_functiondef('public.process_escalations()'::regprocedure))=0
  AND position('evaluate_passive_surface_health' in pg_get_functiondef('public.process_passive_checkins()'::regprocedure))=0,
  'health evaluation is not wired into the alert or window tick');

SELECT is((SELECT count(*)::integer FROM cron.job WHERE jobname='passive-surface-health-v1'),1,'health evaluation is scheduled');
SELECT ok((SELECT max_gap FROM private.scheduled_job_expectations WHERE job_name='passive-surface-health-v1') IS NOT NULL,
  'the schedule carries a staleness expectation');

INSERT INTO auth.users(id,email,aud,role) VALUES
 ('75000000-0000-4000-8000-000000000001','health-writer@example.invalid','authenticated','authenticated')
ON CONFLICT(id) DO NOTHING;
INSERT INTO public.profiles(id,display_name) VALUES
 ('75000000-0000-4000-8000-000000000001','Health Writer')
ON CONFLICT(id) DO NOTHING;

SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','75000000-0000-4000-8000-000000000001',true);
SELECT public.set_passive_checkin_contract(120,2,'none',NULL,NULL,NULL,'shadow','passive-checkin-v1');

CREATE TEMP TABLE health_fixture(android uuid, pwa uuid);
INSERT INTO health_fixture
SELECT (public.bind_passive_collector('health-android','android_native','android-passive-evidence-v1','0.7.1')->>'binding_id')::uuid,
       (public.bind_passive_collector('health-pwa','pwa_browser','pwa-interaction-v1','0.7.1')->>'binding_id')::uuid;

-- android_native cadence is 15 minutes, so silence is breached at last contact
-- plus 30 minutes. pwa_browser has no cadence and can never be silent.
UPDATE private.passive_collector_bindings SET last_contact_at='2026-08-16 00:00Z'
WHERE id IN (SELECT android FROM health_fixture UNION SELECT pwa FROM health_fixture);

SELECT lives_ok($$ SELECT private.evaluate_passive_surface_health('2026-08-16 00:31Z') $$,'evaluation runs');
SELECT is((SELECT started_at FROM private.passive_surface_health_intervals h JOIN health_fixture f ON f.android=h.binding_id
  WHERE h.reason='silent'),'2026-08-16 00:30Z'::timestamptz,
  'silent opens at the breached expectation, not when the evaluator noticed');
SELECT is((SELECT count(*)::integer FROM private.passive_surface_health_intervals h JOIN health_fixture f ON f.pwa=h.binding_id),0,
  'a surface with no scheduled contact never goes silent');

SELECT private.evaluate_passive_surface_health('2026-08-16 00:40Z');
SELECT is((SELECT count(*)::integer FROM private.passive_surface_health_intervals h JOIN health_fixture f ON f.android=h.binding_id
  WHERE h.reason='silent'),1,'a still-open outage is not opened twice');

UPDATE private.passive_collector_bindings SET last_contact_at='2026-08-16 00:45Z'
WHERE id=(SELECT android FROM health_fixture);
SELECT private.evaluate_passive_surface_health('2026-08-16 00:46Z');
SELECT is((SELECT ended_at FROM private.passive_surface_health_intervals h JOIN health_fixture f ON f.android=h.binding_id
  WHERE h.reason='silent'),'2026-08-16 00:45Z'::timestamptz,
  'the outage closes at the contact that cleared it');

-- Reasons are independent: the learner unions them, so a surface that is both
-- silent and permission-denied must carry both intervals at once.
UPDATE private.passive_collector_bindings
   SET permission_state='denied', health_reported_at='2026-08-16 01:00Z', last_contact_at='2026-08-16 00:45Z'
WHERE id=(SELECT android FROM health_fixture);
SELECT private.evaluate_passive_surface_health('2026-08-16 01:20Z');
SELECT is((SELECT started_at FROM private.passive_surface_health_intervals h JOIN health_fixture f ON f.android=h.binding_id
  WHERE h.reason='permission_denied'),'2026-08-16 01:00Z'::timestamptz,
  'permission loss opens at the moment the surface reported it');
SELECT is((SELECT count(*)::integer FROM private.passive_surface_health_intervals h JOIN health_fixture f ON f.android=h.binding_id
  WHERE h.ended_at IS NULL),2,'overlapping reasons are stored separately');

UPDATE private.passive_collector_bindings SET revoked_at='2026-08-16 02:00Z', revocation_reason='test'
WHERE id=(SELECT android FROM health_fixture);
SELECT private.evaluate_passive_surface_health('2026-08-16 02:10Z');
SELECT is((SELECT count(*)::integer FROM private.passive_surface_health_intervals h JOIN health_fixture f ON f.android=h.binding_id
  WHERE h.ended_at IS NULL),0,'revocation closes every open interval');
SELECT is((SELECT max(ended_at) FROM private.passive_surface_health_intervals h JOIN health_fixture f ON f.android=h.binding_id),
  '2026-08-16 02:00Z'::timestamptz,
  'a revoked surface stops accruing outage at revocation, not at now');

SELECT private.evaluate_passive_surface_health('2026-08-16 03:00Z');
SELECT is((SELECT count(*)::integer FROM private.passive_surface_health_intervals h JOIN health_fixture f ON f.android=h.binding_id
  WHERE h.ended_at IS NULL),0,'a revoked surface opens no new outage');

SELECT ok((private.evaluate_passive_surface_health('2026-08-16 03:05Z') ? 'opened')
  AND (private.evaluate_passive_surface_health('2026-08-16 03:05Z') ? 'closed'),'the evaluator reports what it changed');

SELECT * FROM finish();
ROLLBACK;
