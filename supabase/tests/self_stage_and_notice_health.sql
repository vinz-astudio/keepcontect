-- The first step of every escalation is "KC asks you". These assertions defend
-- that it actually happens, and that a notification nobody can receive is
-- recorded as a protection failure rather than dropped.
BEGIN;

SELECT plan(8);

INSERT INTO auth.users (id, email, aud, role) VALUES
  ('7a000000-0000-4000-8000-000000000001', 'self-a@example.invalid', 'authenticated', 'authenticated'),
  ('7a000000-0000-4000-8000-000000000002', 'self-b@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, display_name) VALUES
  ('7a000000-0000-4000-8000-000000000001', 'Self A'),
  ('7a000000-0000-4000-8000-000000000002', 'Self B')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

-- 非 SOS 的 self 阶段:本人必须收到一条属于自己的通知。
INSERT INTO public.alerts (id, user_id, cause, stage, status, opened_at)
VALUES ('7a000000-0000-4000-8000-0000000000a1',
        '7a000000-0000-4000-8000-000000000001', 'silence', 'self', 'open', now());

SELECT private.notify_stage('7a000000-0000-4000-8000-0000000000a1',
                            '7a000000-0000-4000-8000-000000000001', 'self');

SELECT is(
  (SELECT count(*)::integer FROM public.notifications
   WHERE alert_id='7a000000-0000-4000-8000-0000000000a1'
     AND recipient_id='7a000000-0000-4000-8000-000000000001'
     AND kind='self'),
  1, 'a non-SOS self stage writes one notice addressed to the subject');

SELECT ok(
  (SELECT count(*)::integer FROM public.notifications
   WHERE alert_id='7a000000-0000-4000-8000-0000000000a1'
     AND recipient_id<>'7a000000-0000-4000-8000-000000000001') = 0,
  'the self stage tells nobody but the subject');

-- SOS 是本人自己按的,再问一次没有意义。
INSERT INTO public.alerts (id, user_id, cause, stage, status, opened_at)
VALUES ('7a000000-0000-4000-8000-0000000000a2',
        '7a000000-0000-4000-8000-000000000002', 'sos', 'self', 'open', now());

SELECT private.notify_stage('7a000000-0000-4000-8000-0000000000a2',
                            '7a000000-0000-4000-8000-000000000002', 'self');

SELECT is(
  (SELECT count(*)::integer FROM public.notifications
   WHERE alert_id='7a000000-0000-4000-8000-0000000000a2'), 0,
  'an SOS self stage does not ask the person who just pressed it');

-- 群组措辞不能因为这次改动退回旧版本。
SELECT ok(position('失去联系' in pg_get_functiondef('private.notify_stage(uuid,uuid,text)'::regprocedure))>0,
  'the passive routing and its lost-contact copy survive the self-stage change');
SELECT ok(position('notify_stage_before_passive_checkin' in pg_get_functiondef('private.notify_stage(uuid,uuid,text)'::regprocedure))>0,
  'non-passive alerts are still delegated to the legacy path');

-- 送不出去的通知是保护能力受损,不是无事发生。
INSERT INTO public.notifications (id, recipient_id, alert_id, kind, body)
VALUES ('7a000000-0000-4000-8000-0000000000b1',
        '7a000000-0000-4000-8000-000000000002',
        '7a000000-0000-4000-8000-0000000000a2', 'group', 'test')
ON CONFLICT (id) DO NOTHING;

UPDATE public.notifications SET delivery_outcome='no_target'
WHERE id='7a000000-0000-4000-8000-0000000000b1';

SELECT is(
  (SELECT count(*)::integer FROM public.protection_health_incidents
   WHERE user_id='7a000000-0000-4000-8000-000000000002' AND closed_at IS NULL),
  1, 'an undeliverable notice opens one health incident');

-- 唯一索引是按 user 的,不分 cause。第二次不能再插,也不能报错。
INSERT INTO public.notifications (id, recipient_id, alert_id, kind, body)
VALUES ('7a000000-0000-4000-8000-0000000000b2',
        '7a000000-0000-4000-8000-000000000002',
        '7a000000-0000-4000-8000-0000000000a2', 'group', 'test2')
ON CONFLICT (id) DO NOTHING;

UPDATE public.notifications SET delivery_outcome='no_target'
WHERE id='7a000000-0000-4000-8000-0000000000b2';

SELECT is(
  (SELECT count(*)::integer FROM public.protection_health_incidents
   WHERE user_id='7a000000-0000-4000-8000-000000000002' AND closed_at IS NULL),
  1, 'a second undeliverable notice does not open a second incident');

-- 成功送达的通知不该开事件。
INSERT INTO public.notifications (id, recipient_id, alert_id, kind, body)
VALUES ('7a000000-0000-4000-8000-0000000000b3',
        '7a000000-0000-4000-8000-000000000001',
        '7a000000-0000-4000-8000-0000000000a1', 'group', 'test3')
ON CONFLICT (id) DO NOTHING;

UPDATE public.notifications SET delivery_outcome='sent'
WHERE id='7a000000-0000-4000-8000-0000000000b3';

SELECT is(
  (SELECT count(*)::integer FROM public.protection_health_incidents
   WHERE user_id='7a000000-0000-4000-8000-000000000001'),
  0, 'a delivered notice opens nothing');

SELECT * FROM finish();
ROLLBACK;
