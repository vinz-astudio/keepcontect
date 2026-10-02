// Local replay only; never applied to production.
//
// The repository migrations do not reproduce the production ACLs: production
// keeps revokes that were applied outside the migration ledger (ADR-0027, S2
// ACL repair). A fresh replay therefore leaves these routines and tables more
// open than production, so ACL assertions in supabase/tests fail locally while
// production is correct (Keep Contact Memory M2).
//
// This module holds a REVOKE-ONLY snapshot of production for the `public` and
// `private` schemas. It never grants anything, so it cannot hide a missing
// grant, and it cannot re-grant something a newer migration revoked. It only
// removes access that production does not have. Functions and tables that are
// absent from a replay are skipped.
//
// Captured 2026-10-02 from the production project by read-only catalog
// queries (pg_proc.proacl / pg_class.relacl, anon and authenticated only).
// Refresh by re-running the same queries when production ACLs change; a stale
// snapshot can only make the replay stricter, never looser.

export const PRODUCTION_ACL_CAPTURED_ON = '2026-10-02';

// "<schema>.<name>(<argument types>)|<PUBLIC><anon><authenticated>" where each
// flag says whether EXECUTE is held in production (1) or not (0). Routines held
// by all three ("111") change nothing and are omitted.
const FUNCTION_ACL_LINES = `
private.aggregate_user_daily_activity(uuid, date)|000
private.alert_candidate_config_is_valid(jsonb)|000
private.apply_liveness_side_effects(uuid, timestamp with time zone, timestamp with time zone)|000
private.can_see_alert(uuid, uuid)|001
private.candidate_sleep_intervals(uuid, timestamp with time zone, timestamp with time zone, uuid)|000
private.canonical_routine_mode(text)|000
private.capture_alert_shadow_interventions(uuid, timestamp with time zone, integer)|000
private.capture_alert_shadow_subject_contexts(uuid, timestamp with time zone, integer)|000
private.capture_passive_shadow_candidate()|000
private.capture_passive_window_transition()|000
private.confirm_subject_safety(uuid, integer[])|000
private.convert_legacy_checkin_contract(uuid)|000
private.coverage_capable_subject(uuid)|000
private.disable_adaptive_alert_shadow(text)|000
private.dispatch_account_shadow_cycle()|000
private.dispatch_adaptive_alert_shadow_cycle()|000
private.dispatch_adaptive_alert_shadow_maintenance()|000
private.dispatch_special_attention_notices(interval)|000
private.enforce_passive_global_kill_switch()|000
private.evaluate_passive_surface_health(timestamp with time zone)|000
private.evaluate_protection_health(uuid)|000
private.finalize_alert_shadow_coverage(uuid, timestamp with time zone, integer)|000
private.guardian_pair(uuid, uuid)|001
private.guardian_requires_pattern(uuid)|000
private.handle_profile_pattern_change()|100
private.insert_behavior_ping(uuid, uuid, timestamp with time zone, text, text)|000
private.insert_device_sample(uuid, uuid, jsonb)|000
private.invalidate_routine_mode_cohort()|000
private.invalidate_routine_mode_cohort_profile()|000
private.is_admin(uuid)|100
private.is_community_admin(uuid, uuid)|001
private.is_community_member(uuid, uuid)|001
private.is_group_admin(uuid, uuid)|001
private.is_group_member(uuid, uuid)|001
private.is_guardian_of(uuid, uuid)|001
private.is_in_sleep_window(uuid, timestamp with time zone)|000
private.maintain_adaptive_alert_shadow(timestamp with time zone, integer)|000
private.mark_adaptive_alert_shadow_dirty()|000
private.mark_protection_health_prompted(uuid)|000
private.maybe_open_passive_checkin_alert(uuid, uuid, uuid, timestamp with time zone)|000
private.normalized_behavior_training_sessions(uuid, timestamp with time zone, timestamp with time zone, uuid)|000
private.notify_auto_resolved(uuid, uuid)|000
private.notify_stage(uuid, uuid, text)|000
private.notify_stage_before_passive_checkin(uuid, uuid, text)|001
private.passive_arrival_allowance(uuid)|100
private.passive_awake_deadline(uuid, timestamp with time zone, integer)|000
private.passive_checkin_shadow_report(timestamp with time zone, timestamp with time zone)|000
private.passive_collector_health_summary(uuid, timestamp with time zone)|000
private.passive_expected_contract(text)|100
private.passive_last_local_time(integer, text, timestamp with time zone)|100
private.passive_miss_chain(uuid)|000
private.passive_miss_kind(uuid, timestamp with time zone, timestamp with time zone)|000
private.passive_payload_sha256(uuid, uuid, bigint, timestamp with time zone, text, text, text, jsonb, timestamp with time zone, timestamp with time zone, boolean)|100
private.passive_sleep_relaxed(uuid, uuid, timestamp with time zone)|000
private.passive_surface_health_conditions(timestamp with time zone)|000
private.passive_window_arrival_allowance(uuid, timestamp with time zone, timestamp with time zone)|000
private.pin_alert_gap_profile_contract()|000
private.process_passive_checkin_subject(uuid, timestamp with time zone)|000
private.promote_device_samples_to_liveness(interval, integer)|000
private.prompt_protection_health_subjects()|000
private.prune_passive_checkin_data()|000
private.prune_passive_knock_attempts()|000
private.qualified_behavior_sessions(uuid, timestamp with time zone, timestamp with time zone, uuid)|000
private.rebuild_account_gap_profiles(date, integer, integer, numeric, integer, integer, integer, boolean)|000
private.rebuild_account_normal_bounds(date, integer, numeric, integer, integer, integer, integer)|000
private.rebuild_alert_gap_profiles(uuid, date)|000
private.rebuild_passive_checkin_recommendation(uuid, timestamp with time zone)|000
private.rebuild_routine_mode_cohort_priors(uuid, date, text)|000
private.record_account_threshold_shadow(date, integer, integer, numeric, integer, integer, integer, integer, integer)|000
private.record_alert_judgment_shadow(uuid, timestamp with time zone)|000
private.record_alert_judgment_shadow_operational(uuid, timestamp with time zone, integer)|000
private.record_alert_shadow_coverage_lease_core(uuid, text, text, text, text, text, timestamp with time zone, uuid)|000
private.record_passive_evidence(uuid, uuid, text, boolean, uuid, bigint, timestamp with time zone, text, text, text, jsonb, timestamp with time zone, timestamp with time zone, boolean)|100
private.record_undeliverable_notice()|000
private.refresh_revoked_guardian_pattern()|000
private.reject_passive_contract_version_mutation()|000
private.reject_passive_evidence_mutation()|100
private.reject_passive_observability_mutation()|000
private.reject_passive_recommendation_mutation()|000
private.reject_passive_snapshot_mutation()|000
private.replay_config_is_valid(jsonb)|000
private.report_unhealthy_jobs()|100
private.resolve_activity_alerts(uuid)|000
private.resolve_alert_candidate(uuid, timestamp with time zone, uuid)|000
private.restart_passive_epoch_after_resolution()|000
private.routine_mode_cohort_prior_is_valid(uuid, text, date, timestamp with time zone)|000
private.run_adaptive_alert_shadow_cycle(uuid, timestamp with time zone)|000
private.run_alert_judgment_replay(uuid, timestamp with time zone, timestamp with time zone)|000
private.run_protection_health_cycle(interval)|000
private.scheduled_job_health()|100
private.set_alert_pattern_policy()|000
private.set_passive_checkin_global_kill_switch(boolean, text)|000
private.shadow_live_definition_matches(text, text)|000
private.shares_community(uuid, uuid)|001
private.shares_group_with(uuid, uuid)|001
private.silence_threshold(uuid)|000
private.sleep_relaxed(uuid, timestamp with time zone)|100
private.split_legacy_threshold(integer)|000
private.trigger_push_dispatch()|100
private.trigger_update_routine_profile(uuid)|100
private.watches_user(uuid, uuid)|001
public.ack_alert(uuid, integer)|001
public.acknowledge_notification_safe(uuid, uuid, integer[])|001
public.acknowledge_protection_health()|011
public.acknowledge_safe(uuid)|001
public.acknowledge_safe_with_pattern(uuid, integer[])|001
public.become_guardian_by_code(text)|001
public.bind_passive_collector(text, text, text, text)|001
public.claim_unpushed_notifications(integer, interval)|000
public.clear_finished_notifications()|001
public.create_checkin_task(uuid, text, time without time zone, time without time zone, integer, timestamp with time zone, integer, text)|001
public.create_push_binding(uuid, uuid, bigint, text)|001
public.finalize_notification_delivery(uuid, text)|000
public.get_app_config()|000
public.get_group_activity(uuid)|001
public.get_group_activity_view(uuid, text)|001
public.gm_list_clients()|001
public.gm_mute_user(uuid, timestamp with time zone, text)|001
public.gm_scheduled_job_health()|001
public.gm_unmute_user(uuid)|001
public.handle_new_community()|000
public.handle_new_group()|000
public.handle_new_user()|000
public.initialize_user_routine_data(uuid)|000
public.join_community_by_code(text)|001
public.join_group_by_code(text)|001
public.my_daily_checkin()|001
public.my_guardian_pattern_requirements()|001
public.my_passive_checkin_recommendation()|001
public.my_passive_checkin_status()|001
public.my_passive_collector_health()|001
public.my_passive_window_state()|001
public.my_protection_health()|011
public.my_routine_status()|001
public.my_special_attention()|011
public.passive_knock_targets()|000
public.process_checkin_tasks()|000
public.process_escalations()|000
public.process_passive_checkins()|000
public.prune_stale_clients()|000
public.purge_user_data(uuid)|000
public.raise_sos(double precision, double precision)|001
public.raise_test_alert()|001
public.record_alert_shadow_coverage_lease(text, text, text, text, text, timestamp with time zone, uuid)|001
public.record_alert_shadow_coverage_lease_for_user(uuid, text, text, text, text, text, timestamp with time zone, uuid)|000
public.record_authenticated_passive_evidence(uuid, uuid, bigint, timestamp with time zone, text, text, text, jsonb)|001
public.record_behavior_ping(uuid, timestamp with time zone, text, text)|001
public.record_behavior_ping_for_user(uuid, uuid, timestamp with time zone, text, text)|000
public.record_behavior_pings(jsonb)|001
public.record_device_sample_for_user(uuid, uuid, jsonb)|000
public.record_last_active_backfill(uuid, timestamp with time zone, text)|000
public.record_owned_behavior_ping(uuid, uuid, timestamp with time zone, text, text)|001
public.record_owned_behavior_pings(uuid, jsonb)|001
public.record_passive_evidence_with_credential(uuid, text, uuid, bigint, timestamp with time zone, text, text, text, jsonb, timestamp with time zone, timestamp with time zone, boolean)|000
public.record_passive_knock(uuid, uuid, integer)|000
public.record_shortcut_passive_evidence(uuid, text, uuid)|000
public.register_fcm_token(text, text)|001
public.register_push_token(uuid, text, text)|001
public.rename_community(uuid, text)|001
public.rename_group(uuid, text)|001
public.resolve_alert(uuid)|001
public.resolve_my_alert()|001
public.respond_checkin_task(uuid, boolean, timestamp with time zone)|001
public.resume_passive_collector(uuid, text)|001
public.revoke_checkin_task(uuid)|001
public.revoke_passive_collector(uuid)|001
public.revoke_push_binding(uuid, text, text)|011
public.run_daily_aggregations()|000
public.send_concern(uuid)|001
public.send_heartbeat(text)|001
public.send_test_notification()|001
public.set_activity_detail_level(text)|001
public.set_daily_checkin_contract(integer, integer, integer, text, text, text, integer)|001
public.set_display_name(text)|001
public.set_group_community(uuid, uuid)|001
public.set_group_visibility(uuid, text)|001
public.set_guardian_pattern_requirement(uuid, boolean)|001
public.set_monitoring_direction(uuid, boolean, boolean)|001
public.set_passive_checkin_contract(integer, integer, text, time without time zone, time without time zone, text, text, text)|001
public.set_sensitivity(text)|001
public.set_share_activity(boolean)|001
public.set_sleep_window(time without time zone, time without time zone, text)|001
public.set_special_attention(uuid, boolean)|011
public.special_attention_recipients(uuid)|000
public.trigger_weekly_routine_updates()|000
public.update_checkin_task(uuid, text, time without time zone, time without time zone, integer, timestamp with time zone, integer, text)|001
public.update_sos_location(double precision, double precision)|001
`;

// "<schema>.<relation>|<anon privileges>|<authenticated privileges>" using the
// ACL letters held in production: a INSERT, r SELECT, w UPDATE, d DELETE,
// D TRUNCATE, x REFERENCES, t TRIGGER. Relations where both roles hold every
// privilege change nothing and are omitted.
const TABLE_ACL_LINES = `
private.adaptive_alert_shadow_cohort_dirty||
private.adaptive_alert_shadow_cycle_runs||
private.adaptive_alert_shadow_daily_reports||
private.adaptive_alert_shadow_intervention_cursor||
private.adaptive_alert_shadow_profile_dirty||
private.adaptive_alert_shadow_runtime_config||
private.adaptive_alert_shadow_subject_context_state||
private.adaptive_alert_shadow_user_state||
private.alert_shadow_coverage_leases||
private.app_config||
private.guardian_pattern_requirements||
private.job_failures||
private.passive_alert_causal_windows||
private.passive_checkin_runtime_control||
private.passive_collector_bindings||
private.passive_evidence_events||
private.passive_evidence_incidents||
private.passive_knock_attempts||
private.passive_shadow_candidates||
private.passive_surface_health_intervals||
private.passive_surface_registry||
private.passive_window_transitions||
private.push_bindings||
private.push_installations||
private.scheduled_job_expectations||
public.account_gap_profiles||
public.account_normal_bounds||
public.account_threshold_shadow||
public.alert_gap_profiles||
public.alert_intervention_events||
public.alert_judgment_evaluations||
public.alert_judgment_shadow_decisions||
public.alert_judgment_subject_contexts||
public.alert_model_versions||
public.alert_observation_coverage_intervals||
public.alert_sleep_night_contexts||
public.behavior_pings|dxrtDw|dxrtDw
public.gm_mutes||
public.passive_checkin_accounts||
public.passive_checkin_contract_versions||
public.passive_checkin_recommendations||
public.passive_checkin_windows||
public.passive_monitoring_epochs||
public.protection_health_incidents||
public.routine_mode_cohort_generations||
public.routine_mode_cohort_invalidations||
public.routine_mode_cohort_priors||
public.special_attention_notices||
public.special_attention_subscriptions||
`;

const ALL_TABLE_PRIVILEGES = Object.freeze([
  ['a', 'INSERT'],
  ['r', 'SELECT'],
  ['w', 'UPDATE'],
  ['d', 'DELETE'],
  ['D', 'TRUNCATE'],
  ['x', 'REFERENCES'],
  ['t', 'TRIGGER'],
]);

const sqlString = (value) => `'${value.replaceAll("'", "''")}'`;
const dataLines = (block) => block.split('\n').map((line) => line.trim()).filter(Boolean);

export function parseFunctionAcl() {
  return dataLines(FUNCTION_ACL_LINES).map((line) => {
    const [signature, flags] = line.split('|');
    if (!signature || !/^[01]{3}$/.test(flags ?? '')) {
      throw new Error(`Malformed production function ACL line: ${line}`);
    }
    return {
      signature,
      publicExecute: flags[0] === '1',
      anonExecute: flags[1] === '1',
      authenticatedExecute: flags[2] === '1',
    };
  });
}

export function parseTableAcl() {
  return dataLines(TABLE_ACL_LINES).map((line) => {
    const [relation, anon, authenticated] = line.split('|');
    if (!relation || anon === undefined || authenticated === undefined) {
      throw new Error(`Malformed production table ACL line: ${line}`);
    }
    for (const letters of [anon, authenticated]) {
      if ([...letters].some((letter) => !ALL_TABLE_PRIVILEGES.some(([code]) => code === letter))) {
        throw new Error(`Unknown table privilege letter in: ${line}`);
      }
    }
    return { relation, anon, authenticated };
  });
}

export const PRODUCTION_ACL_FIXTURE_FILENAME =
  '20991231235958_local_replay_production_acl.sql';

export function buildProductionAclFixtureSql() {
  const functionValues = parseFunctionAcl()
    .map((row) => `    (${sqlString(row.signature)}, ${row.publicExecute}, ${row.anonExecute}, ${row.authenticatedExecute})`)
    .join(',\n');
  const tableValues = parseTableAcl()
    .map((row) => `    (${sqlString(row.relation)}, ${sqlString(row.anon)}, ${sqlString(row.authenticated)})`)
    .join(',\n');
  const privilegeValues = ALL_TABLE_PRIVILEGES
    .map(([code, name]) => `(${sqlString(code)}, ${sqlString(name)})`)
    .join(', ');

  return `-- Local replay only; never production. Revoke-only snapshot of production ACLs
-- captured ${PRODUCTION_ACL_CAPTURED_ON} (see scripts/local-replay-production-acl.mjs).
-- Runs after all source migrations and before the pgTAP inspection grants.
-- It never grants. Routines and relations missing from a replay are skipped.
DO $replay_acl$
DECLARE
  f record;
  t record;
  p record;
  who text;
  held text;
BEGIN
  FOR f IN SELECT * FROM (VALUES
${functionValues}
  ) AS v(signature, public_execute, anon_execute, authenticated_execute)
  LOOP
    CONTINUE WHEN to_regprocedure(f.signature) IS NULL;
    IF NOT f.public_execute THEN
      EXECUTE format('REVOKE EXECUTE ON ROUTINE %s FROM PUBLIC', to_regprocedure(f.signature));
    END IF;
    IF NOT f.anon_execute THEN
      EXECUTE format('REVOKE EXECUTE ON ROUTINE %s FROM anon', to_regprocedure(f.signature));
    END IF;
    IF NOT f.authenticated_execute THEN
      EXECUTE format('REVOKE EXECUTE ON ROUTINE %s FROM authenticated', to_regprocedure(f.signature));
    END IF;
  END LOOP;

  FOR t IN SELECT * FROM (VALUES
${tableValues}
  ) AS v(relation, anon_held, authenticated_held)
  LOOP
    CONTINUE WHEN to_regclass(t.relation) IS NULL;
    FOREACH who IN ARRAY ARRAY['anon', 'authenticated'] LOOP
      held := CASE who WHEN 'anon' THEN t.anon_held ELSE t.authenticated_held END;
      FOR p IN SELECT * FROM (VALUES ${privilegeValues}) AS q(code, name) LOOP
        IF position(p.code IN held) = 0 THEN
          EXECUTE format('REVOKE %s ON TABLE %s FROM %I', p.name, to_regclass(t.relation), who);
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;
END
$replay_acl$;
`;
}
