BEGIN;

SELECT plan(11);

CREATE TEMP TABLE s1_public_function_defs AS
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args, pg_get_functiondef(p.oid) AS definition
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname = 'public';

SELECT has_table(
  'public', 'special_attention_subscriptions',
  'ADR0039-SPECIAL-01 private Special Attention subscription exists'
);

SELECT has_function(
  'public', 'set_special_attention', ARRAY['uuid', 'boolean'],
  'ADR0039-SPECIAL-02 subscription has explicit default-off setter'
);

SELECT ok(
  coalesce((
    SELECT c.relrowsecurity
      AND NOT has_table_privilege('authenticated', c.oid, 'SELECT')
    FROM pg_class AS c
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'special_attention_subscriptions'
  ), false),
  'ADR0039-SPECIAL-03 subscriber identity is private to owner and service path'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM s1_public_function_defs
    WHERE proname = 'set_special_attention'
      AND definition !~* '(insert|update|delete)[^;]*(alerts|emergency_info|checkin_tasks|guardianships)'
  ),
  'ADR0039-SPECIAL-04 subscription grants no alert, emergency, task, or Guardian authority'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM s1_public_function_defs
    WHERE proname ~ 'special_attention'
      AND definition ~* 'status\s*=\s*''active'''
      AND definition ~* '(revoked|inactive)'
  ),
  'ADR0039-SPECIAL-05 only active relationships are notification-eligible'
);

SELECT ok(
  NOT has_table_privilege('authenticated', 'public.behavior_pings', 'INSERT'),
  'ADR0039-GUARDIAN-01 Guardian cannot insert Ward activity through Data API'
);

SELECT ok(
  (SELECT pg_get_constraintdef(c.oid)
   FROM pg_constraint AS c
   WHERE c.conrelid = 'public.guardianships'::regclass
     AND c.contype = 'c'
     AND pg_get_constraintdef(c.oid) ~ 'status'
   LIMIT 1) ~* 'pending'
  AND (SELECT pg_get_constraintdef(c.oid)
       FROM pg_constraint AS c
       WHERE c.conrelid = 'public.guardianships'::regclass
         AND c.contype = 'c'
         AND pg_get_constraintdef(c.oid) ~ 'status'
       LIMIT 1) ~* 'active'
  AND (SELECT pg_get_constraintdef(c.oid)
       FROM pg_constraint AS c
       WHERE c.conrelid = 'public.guardianships'::regclass
         AND c.contype = 'c'
         AND pg_get_constraintdef(c.oid) ~ 'status'
       LIMIT 1) ~* 'revoked',
  'ADR0039-GUARDIAN-02 guardianship supports pending active and revoked states'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'guardianships'
      AND cmd = 'SELECT'
      AND qual ~ 'guardian_id'
      AND qual ~ 'ward_id'
  ),
  'ADR0039-GUARDIAN-03 active relationship record is visible to both parties'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM s1_public_function_defs
    WHERE definition ~* 'is_guardian_of'
      AND definition ~* '(auth\.users|password|credential|delete[^;]*(account|profile))'
  ),
  'ADR0039-GUARDIAN-04 Guardian cannot alter Ward credentials consent or account deletion'
);

SELECT ok(
  pg_get_functiondef('public.resolve_alert(uuid)'::regprocedure) !~* '(insert|update)[^;]*behavior_pings',
  'ADR0039-GUARDIAN-05 external confirmation cannot create Ward behavior evidence'
);

SELECT ok(
  EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'alerts'
          AND cmd = 'SELECT' AND qual ~ 'is_guardian_of')
  AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'device_state'
              AND cmd = 'SELECT' AND qual ~ 'is_guardian_of')
  AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'emergency_info'
              AND cmd = 'SELECT' AND qual ~ 'is_guardian_of')
  AND EXISTS (SELECT 1 FROM s1_public_function_defs WHERE proname = 'create_checkin_task'
              AND definition ~* 'is_guardian_of'),
  'ADR0039-GUARDIAN-06 active Guardian has comprehensive alert device emergency and care-task scope'
);

SELECT * FROM finish();
ROLLBACK;
