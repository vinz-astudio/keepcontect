BEGIN;

SELECT plan(8);

CREATE TEMP TABLE s1_contract_defs AS
SELECT
  pg_get_functiondef(
    'private.rebuild_account_normal_bounds(date,integer,numeric,integer,integer,integer,integer)'::regprocedure
  ) AS learning_def,
  coalesce((
    SELECT pg_get_functiondef(p.oid)
    FROM pg_proc AS p
    JOIN pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'my_protection_health'
      AND p.pronargs = 0
    LIMIT 1
  ), '') AS health_def;

SELECT ok(
  length((SELECT learning_def FROM s1_contract_defs)) > 0,
  'precondition: current normal-bound worker is inspectable'
);

SELECT matches(
  (SELECT learning_def FROM s1_contract_defs),
  'alert_observation_coverage_intervals',
  'ADR0039-LEARN-01 normal bounds require coverage intervals'
);

SELECT ok(
  (SELECT learning_def FROM s1_contract_defs) ~* 'manual_checkin'
  AND (SELECT learning_def FROM s1_contract_defs) ~* 'guardian'
  AND (SELECT learning_def FROM s1_contract_defs) ~* 'shortcut'
  AND (SELECT learning_def FROM s1_contract_defs) ~* 'replay',
  'ADR0039-LEARN-02 learning explicitly excludes manual, Guardian, Shortcut, and replay evidence'
);

SELECT ok(
  (SELECT learning_def FROM s1_contract_defs) ~* 'count\s*\(\s*distinct[^)]*(date|day)'
  AND (SELECT learning_def FROM s1_contract_defs) ~* '(independent|comparable)'
  AND (SELECT learning_def FROM s1_contract_defs) ~* '(exceptional|long)[^;]*(gap|silence)',
  'ADR0039-LEARN-03 exceptional long gaps require two independent comparable dates'
);

-- ADR0039-LEARN-04 is NOT satisfied, and this assertion records that on purpose.
--
-- The coverage-gated implementation (S3-C2) shipped on 2026-08-10 and was
-- reverted the same day: it derived coverage from activity signals, so it only
-- counted itself as watching while the person was busy, and concluded that
-- normal quiet lasts fourteen minutes. Reverted by
-- 20260810040000_s3_revert_coverage_valid_learning.sql.
--
-- Asserting the requirement here would leave a red test standing in for a
-- decision that has already been made; asserting nothing would let a green
-- suite imply the gate is live. So we assert the gate's ABSENCE: green means
-- "we know learning is ungated", and the moment someone re-adds gating this
-- goes red -- flipping it back is the deliberate review step that gate
-- deserves. Rebuild conditions: ADR-0040 revision one (watcher heartbeat,
-- four coverage states).
SELECT ok(
  (SELECT learning_def FROM s1_contract_defs) !~* 'activity_coverage_state'
  AND (SELECT learning_def FROM s1_contract_defs) !~* 'intervention_coverage_state',
  'ADR0039-LEARN-04 WITHDRAWN: learning is ungated by coverage until ADR-0040 rev.1 is built'
);

SELECT has_function(
  'public', 'my_protection_health', ARRAY[]::text[],
  'ADR0039-HEALTH-01 server exposes protection health'
);

SELECT ok(
  (SELECT health_def FROM s1_contract_defs) ~* '''ready'''
  AND (SELECT health_def FROM s1_contract_defs) ~* '''limited'''
  AND (SELECT health_def FROM s1_contract_defs) ~* '''unknown'''
  AND (SELECT health_def FROM s1_contract_defs) ~* 'incident'
  AND (SELECT health_def FROM s1_contract_defs) ~* 'recover',
  'ADR0039-HEALTH-02 health exposes ready limited unknown plus incident and recovery evidence'
);

SELECT ok(
  length((SELECT health_def FROM s1_contract_defs)) > 0
  AND (SELECT health_def FROM s1_contract_defs) ~* '(acknowledg|prompt)[^;]*(separate|recover)'
  AND (SELECT health_def FROM s1_contract_defs) !~* 'insert\s+into\s+public\.alerts',
  'ADR0039-HEALTH-03 acknowledgement is not recovery and an outage cannot create a personal alert'
);

SELECT * FROM finish();
ROLLBACK;
