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

SELECT ok(
  (SELECT learning_def FROM s1_contract_defs) ~* 'activity_coverage_state'
  AND (SELECT learning_def FROM s1_contract_defs) ~* 'intervention_coverage_state'
  AND (SELECT learning_def FROM s1_contract_defs) ~* 'sleep_context_state'
  AND (SELECT learning_def FROM s1_contract_defs) ~* '''valid''',
  'ADR0039-LEARN-04 only coverage-valid evidence may mutate learned bounds'
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
