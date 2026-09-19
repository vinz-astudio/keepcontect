BEGIN;
SELECT plan(16);
INSERT INTO auth.users(id,email,aud,role) VALUES
 ('79000000-0000-4000-8000-000000000001','shortcut-a@example.invalid','authenticated','authenticated');
SELECT set_config('request.jwt.claim.sub','79000000-0000-4000-8000-000000000001',true);
SELECT public.set_passive_checkin_contract(60,3,'none',NULL,NULL,NULL,'shadow','passive-checkin-v1');
CREATE TEMP TABLE shortcut_fixture AS SELECT result->>'binding_id' AS binding_id,result->>'credential' AS credential
FROM (SELECT public.bind_passive_collector('shortcut-test','shortcut','shortcut-app-open-v1','0.7.6') AS result) b;
CREATE TEMP TABLE native_fixture AS SELECT result->>'binding_id' AS binding_id,result->>'credential' AS credential
FROM (SELECT public.bind_passive_collector('native-test','ios_native','ios-passive-evidence-v1','0.7.6') AS result) b;
SELECT has_function('public','record_shortcut_passive_evidence',ARRAY['uuid','text','uuid'],'scoped Shortcut RPC exists');
SELECT ok(NOT has_function_privilege('anon','public.record_shortcut_passive_evidence(uuid,text,uuid)','EXECUTE'),'anonymous role cannot invoke transport');
SELECT ok(NOT has_function_privilege('authenticated','public.record_shortcut_passive_evidence(uuid,text,uuid)','EXECUTE'),'signed-in role cannot bypass transport');
SELECT ok(has_function_privilege('service_role','public.record_shortcut_passive_evidence(uuid,text,uuid)','EXECUTE'),'service transport may invoke');
SELECT is(public.record_shortcut_passive_evidence((SELECT binding_id::uuid FROM shortcut_fixture),'wrong-credential','79000000-0000-4000-8000-000000000011'),'credential_mismatch','invalid credential cannot create activity');
SELECT is(public.record_shortcut_passive_evidence((SELECT binding_id::uuid FROM native_fixture),(SELECT credential FROM native_fixture),'79000000-0000-4000-8000-000000000012'),'invalid','native credential cannot impersonate a Shortcut');
SELECT is(public.record_shortcut_passive_evidence((SELECT binding_id::uuid FROM shortcut_fixture),(SELECT credential FROM shortcut_fixture),'79000000-0000-4000-8000-000000000013'),'inserted','qualified Shortcut reaches normalized evidence');
SELECT is((SELECT count(*)::integer FROM private.passive_evidence_events WHERE event_id='79000000-0000-4000-8000-000000000013'),1,'one normalized event is stored');
SELECT is((SELECT user_id FROM private.passive_evidence_events WHERE event_id='79000000-0000-4000-8000-000000000013'),'79000000-0000-4000-8000-000000000001'::uuid,'owner comes only from the credential binding');
SELECT is((SELECT qualification_facts FROM private.passive_evidence_events WHERE event_id='79000000-0000-4000-8000-000000000013'),'{"interaction":true}'::jsonb,'the transport supplies only the qualified app-open fact');
SELECT is(public.record_shortcut_passive_evidence((SELECT binding_id::uuid FROM shortcut_fixture),'wrong-credential','79000000-0000-4000-8000-000000000013'),'credential_mismatch','idempotency never bypasses authentication');
SELECT is(public.record_shortcut_passive_evidence((SELECT binding_id::uuid FROM shortcut_fixture),(SELECT credential FROM shortcut_fixture),'79000000-0000-4000-8000-000000000013'),'duplicate','same event retry preserves its original time and sequence');
SELECT is(public.record_shortcut_passive_evidence((SELECT binding_id::uuid FROM shortcut_fixture),(SELECT credential FROM shortcut_fixture),'79000000-0000-4000-8000-000000000014'),'inserted','next invocation allocates its sequence under the binding lock');
SELECT is((SELECT count(DISTINCT collector_sequence)::integer FROM private.passive_evidence_events WHERE binding_id=(SELECT binding_id::uuid FROM shortcut_fixture)),2,'distinct events have distinct sequences');
SELECT public.revoke_passive_collector((SELECT binding_id::uuid FROM shortcut_fixture));
SELECT is(public.record_shortcut_passive_evidence((SELECT binding_id::uuid FROM shortcut_fixture),(SELECT credential FROM shortcut_fixture),'79000000-0000-4000-8000-000000000015'),'revoked','revoked copied URL cannot record activity');
SELECT is(public.record_shortcut_passive_evidence((SELECT binding_id::uuid FROM shortcut_fixture),(SELECT credential FROM shortcut_fixture),'79000000-0000-4000-8000-000000000013'),'revoked','idempotency never bypasses revocation');
SELECT * FROM finish();
ROLLBACK;
