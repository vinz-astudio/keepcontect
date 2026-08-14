-- ADR-0042 package 2: binding, credential, ingest and privacy contract.
BEGIN;
SELECT plan(47);

SELECT has_table('private','passive_surface_registry','surface types are closed server data');
SELECT has_table('private','passive_collector_bindings','collector bindings are private');
SELECT has_table('private','passive_evidence_events','normalized evidence is private');
SELECT has_table('private','passive_evidence_incidents','conflicts have a privacy-minimized audit');
SELECT has_table('private','passive_surface_health_intervals','health history is separate');
SELECT is((SELECT count(*)::integer FROM private.passive_surface_registry),6,'registry has exactly six accepted surfaces');
SELECT set_eq(
  $$ SELECT surface_type FROM private.passive_surface_registry $$,
  ARRAY['tauri_native','tauri_native_linux','android_native','ios_native','pwa_browser','shortcut'],
  'registry names match revision 10 exactly'
);
SELECT is((SELECT extract(epoch FROM arrival_allowance)::integer/60 FROM private.passive_surface_registry WHERE surface_type='android_native'),35,'Android allowance is 35 minutes');
SELECT is((SELECT extract(epoch FROM arrival_allowance)::integer/60 FROM private.passive_surface_registry WHERE surface_type='ios_native'),90,'iOS allowance is 90 minutes');
SELECT ok((SELECT expected_contact_cadence IS NULL FROM private.passive_surface_registry WHERE surface_type='pwa_browser'),'PWA silence is not a health signal');

SELECT has_function('public','bind_passive_collector',ARRAY['text','text','text','text'],'authenticated binding returns one credential');
SELECT has_function('public','revoke_passive_collector',ARRAY['uuid'],'binding is explicitly revocable');
SELECT has_function('public','record_passive_evidence_with_credential',ARRAY['uuid','text','uuid','bigint','timestamp with time zone','text','text','text','jsonb','timestamp with time zone','timestamp with time zone','boolean'],'native transport has a credential validator');
SELECT has_function('public','record_authenticated_passive_evidence',ARRAY['uuid','uuid','bigint','timestamp with time zone','text','text','text','jsonb'],'foreground transport shares the validator');
SELECT has_function('private','prune_passive_checkin_data',ARRAY[]::text[],'retention cleanup is callable but unscheduled');

SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='private.passive_collector_bindings'::regclass),'binding table has RLS');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='private.passive_evidence_events'::regclass),'evidence table has RLS');
SELECT ok(NOT has_table_privilege('anon','private.passive_evidence_events','SELECT') AND NOT has_table_privilege('authenticated','private.passive_evidence_events','SELECT'),'raw evidence has no client read grant');
SELECT ok(NOT has_table_privilege('service_role','private.passive_evidence_events','SELECT'),'service role uses validator functions, not raw table grants');
SELECT ok(NOT EXISTS (
  SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='private'
    AND tablename IN ('passive_collector_bindings','passive_evidence_events','passive_evidence_incidents','passive_surface_health_intervals')
),'raw passive tables are absent from Realtime');

INSERT INTO auth.users(id,email,aud,role) VALUES
 ('72000000-0000-4000-8000-000000000001','passive-evidence-a@example.invalid','authenticated','authenticated'),
 ('72000000-0000-4000-8000-000000000002','passive-evidence-b@example.invalid','authenticated','authenticated')
ON CONFLICT(id) DO NOTHING;
INSERT INTO public.profiles(id,display_name) VALUES
 ('72000000-0000-4000-8000-000000000001','Evidence A'),
 ('72000000-0000-4000-8000-000000000002','Evidence B')
ON CONFLICT(id) DO NOTHING;

SELECT set_config('request.jwt.claim.sub','72000000-0000-4000-8000-000000000001',true);
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT public.set_passive_checkin_contract(60,3,'none',NULL,NULL,NULL,'shadow','passive-checkin-v1');
UPDATE public.passive_monitoring_epochs SET started_at=clock_timestamp()-interval '1 hour'
WHERE user_id='72000000-0000-4000-8000-000000000001' AND ended_at IS NULL;
UPDATE public.passive_checkin_windows
SET window_start=clock_timestamp()-interval '1 hour',window_end=clock_timestamp(),arrival_deadline=clock_timestamp()
WHERE user_id='72000000-0000-4000-8000-000000000001';

SELECT throws_ok(
 $$ SELECT public.bind_passive_collector('bad-surface','installed_pwa','pwa-interaction-v1','0.7.0') $$,
 '22023',NULL,'the plan typo installed_pwa cannot bind'
);
CREATE TEMP TABLE evidence_fixture(binding_id uuid,credential text);
CREATE TEMP TABLE evidence_time(observed_at timestamptz);
INSERT INTO evidence_time VALUES (clock_timestamp()-interval '1 minute');
INSERT INTO evidence_fixture
SELECT (result->>'binding_id')::uuid,result->>'credential'
FROM (SELECT public.bind_passive_collector(
 'android-install-a','android_native','android-passive-evidence-v1','0.7.0'
) AS result) bound;
SELECT ok((SELECT length(credential)=64 FROM evidence_fixture),'bind returns a high-entropy credential once');
SELECT isnt(
 (SELECT credential_sha256 FROM private.passive_collector_bindings WHERE id=(SELECT binding_id FROM evidence_fixture)),
 (SELECT credential FROM evidence_fixture),
 'only the credential digest is stored'
);
SELECT is(
 (SELECT extract(epoch FROM (arrival_deadline-window_end))::integer/60 FROM public.passive_checkin_windows
  WHERE user_id='72000000-0000-4000-8000-000000000001'),
 35,'binding updates the pending arrival allowance'
);
SELECT is(public.record_authenticated_passive_evidence(
 (SELECT binding_id FROM evidence_fixture),'72000000-0000-4000-8000-000000000120',0,clock_timestamp(),
 'direct_device_use','passive-qualification-v1',NULL,'{"interaction":true}'
),'invalid','authenticated foreground RPC cannot impersonate a native collector');
CREATE TEMP TABLE pwa_fixture(binding_id uuid);
INSERT INTO pwa_fixture
SELECT (public.bind_passive_collector(
 'pwa-profile-a','pwa_browser','pwa-interaction-v1','0.7.0'
)->>'binding_id')::uuid;
SELECT is(public.record_authenticated_passive_evidence(
 (SELECT binding_id FROM pwa_fixture),'72000000-0000-4000-8000-000000000121',0,clock_timestamp(),
 'direct_device_use','passive-qualification-v1',NULL,'{"interaction":true}'
),'inserted','authenticated PWA evidence reaches the shared validator');

SELECT set_config('request.jwt.claim.sub','72000000-0000-4000-8000-000000000002',true);
SELECT public.set_passive_checkin_contract(60,3,'none',NULL,NULL,NULL,'shadow','passive-checkin-v1');
SELECT throws_ok(
 $$ SELECT public.bind_passive_collector('android-install-a','android_native','android-passive-evidence-v1','0.7.0') $$,
 '23505',NULL,'one installation cannot bind two accounts'
);
SELECT set_config('request.jwt.claim.sub','72000000-0000-4000-8000-000000000001',true);

SELECT is(public.record_passive_evidence_with_credential(
 (SELECT binding_id FROM evidence_fixture),(SELECT credential FROM evidence_fixture),
 '72000000-0000-4000-8000-000000000101',7,(SELECT observed_at FROM evidence_time),
 'direct_device_use','passive-qualification-v1','unlock-1','{"interaction":true}',NULL,NULL,false
),'inserted','qualified current evidence is inserted');
SELECT is((SELECT count(*)::integer FROM private.passive_evidence_events WHERE user_id='72000000-0000-4000-8000-000000000001'),2,'each qualified assertion stores one normalized event');
SELECT ok(EXISTS(SELECT 1 FROM public.passive_checkin_windows WHERE user_id='72000000-0000-4000-8000-000000000001' AND outcome='checked_in'),'qualified evidence checks in its window');
SELECT is(public.record_passive_evidence_with_credential(
 (SELECT binding_id FROM evidence_fixture),(SELECT credential FROM evidence_fixture),
 '72000000-0000-4000-8000-000000000101',7,(SELECT observed_at FROM evidence_time),
 'direct_device_use','passive-qualification-v1','unlock-1','{"interaction":true}',NULL,NULL,false
),'duplicate','identical retry is idempotent');

SELECT is(public.record_passive_evidence_with_credential(
 (SELECT binding_id FROM evidence_fixture),(SELECT credential FROM evidence_fixture),
 '72000000-0000-4000-8000-000000000101',7,clock_timestamp()-interval '2 minutes',
 'direct_device_use','passive-qualification-v1','changed','{"interaction":true}',NULL,NULL,false
),'conflict','same event id with changed payload conflicts');
SELECT is((SELECT count(*)::integer FROM private.passive_evidence_incidents WHERE reason='event_conflict'),1,'event conflict is audited without raw payload');
SELECT is(public.record_passive_evidence_with_credential(
 (SELECT binding_id FROM evidence_fixture),(SELECT credential FROM evidence_fixture),
 '72000000-0000-4000-8000-000000000102',7,clock_timestamp()-interval '1 minute',
 'direct_device_use','passive-qualification-v1','other','{"interaction":true}',NULL,NULL,false
),'conflict','reused sequence with a different event conflicts');
SELECT is(public.record_passive_evidence_with_credential(
 (SELECT binding_id FROM evidence_fixture),(SELECT credential FROM evidence_fixture),
 '72000000-0000-4000-8000-000000000103',5,clock_timestamp()-interval '1 minute',
 'direct_device_use','passive-qualification-v1','offline','{"interaction":true}',NULL,NULL,false
),'inserted','unused out-of-order sequence is accepted for offline history');
SELECT is(public.record_passive_evidence_with_credential(
 (SELECT binding_id FROM evidence_fixture),'wrong-credential-that-is-long-enough-0000000000000000',
 '72000000-0000-4000-8000-000000000104',8,clock_timestamp(),
 'direct_device_use','passive-qualification-v1',NULL,'{"interaction":true}',NULL,NULL,false
),'credential_mismatch','wrong credential fails closed');
SELECT is(public.record_passive_evidence_with_credential(
 (SELECT binding_id FROM evidence_fixture),(SELECT credential FROM evidence_fixture),
 '72000000-0000-4000-8000-000000000105',9,clock_timestamp()+interval '6 minutes',
 'direct_device_use','passive-qualification-v1',NULL,'{"interaction":true}',NULL,NULL,false
),'invalid','future evidence over five minutes is rejected');
SELECT is(public.record_passive_evidence_with_credential(
 (SELECT binding_id FROM evidence_fixture),(SELECT credential FROM evidence_fixture),
 '72000000-0000-4000-8000-000000000106',10,clock_timestamp()-interval '8 days',
 'direct_device_use','passive-qualification-v1',NULL,'{"interaction":true}',clock_timestamp()-interval '9 days',clock_timestamp()-interval '7 days',true
),'invalid','evidence older than seven days is rejected');
SELECT is(public.record_passive_evidence_with_credential(
 (SELECT binding_id FROM evidence_fixture),(SELECT credential FROM evidence_fixture),
 '72000000-0000-4000-8000-000000000107',11,clock_timestamp()-interval '10 minutes',
 'direct_device_use','passive-qualification-v1',NULL,'{"interaction":true}',NULL,NULL,false
),'invalid','historical evidence without successful query bounds is rejected');
SELECT is(public.record_passive_evidence_with_credential(
 (SELECT binding_id FROM evidence_fixture),(SELECT credential FROM evidence_fixture),
 '72000000-0000-4000-8000-000000000108',12,clock_timestamp()-interval '10 minutes',
 'direct_device_use','passive-qualification-v1',NULL,'{"interaction":true}',clock_timestamp()-interval '20 minutes',clock_timestamp()-interval '5 minutes',true
),'inserted','supported bounded positive history is accepted at occurrence time');
SELECT is((SELECT count(*)::integer FROM public.alerts WHERE user_id='72000000-0000-4000-8000-000000000001'),0,'evidence ingest never creates or resolves an alert');

SELECT set_config('request.jwt.claim.sub','72000000-0000-4000-8000-000000000002',true);
SELECT is(public.record_authenticated_passive_evidence(
 (SELECT binding_id FROM evidence_fixture),'72000000-0000-4000-8000-000000000109',13,clock_timestamp(),
 'direct_device_use','passive-qualification-v1',NULL,'{"interaction":true}'
),'unregistered_binding','authenticated foreground path cannot cross accounts');
SELECT set_config('request.jwt.claim.sub','72000000-0000-4000-8000-000000000001',true);
SELECT ok(public.revoke_passive_collector((SELECT binding_id FROM evidence_fixture)),'owner can revoke the binding');
SELECT is(public.record_passive_evidence_with_credential(
 (SELECT binding_id FROM evidence_fixture),(SELECT credential FROM evidence_fixture),
 '72000000-0000-4000-8000-000000000110',14,clock_timestamp(),
 'direct_device_use','passive-qualification-v1',NULL,'{"interaction":true}',NULL,NULL,false
),'revoked','revoked credential cannot upload queued evidence');

INSERT INTO private.passive_evidence_incidents(user_id,binding_id,reason,received_at)
VALUES (
 '72000000-0000-4000-8000-000000000001',(SELECT binding_id FROM evidence_fixture),
 'credential_mismatch',clock_timestamp()-interval '36 days'
);
SELECT ok((private.prune_passive_checkin_data()->>'incidents')::integer >= 1,'cleanup removes raw ingest audit after 35 days');
SELECT ok((SELECT count(*) FROM private.passive_evidence_events) >= 1,'cleanup preserves evidence still inside 35 days');
SELECT is((SELECT count(*)::integer FROM cron.job WHERE command ILIKE '%prune_passive_checkin_data%'),0,'package 2 does not schedule production cleanup');

SELECT * FROM finish();
ROLLBACK;
