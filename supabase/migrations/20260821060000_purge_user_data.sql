-- Migration: Add ios_url column to app_versions, adjust passive_checkin_contract_versions FK, and create atomic purge_user_data procedure
ALTER TABLE public.app_versions ADD COLUMN IF NOT EXISTS ios_url text;

-- Allow passive_checkin_contract_versions to cascade on auth user deletion without violating immutability update triggers
ALTER TABLE public.passive_checkin_contract_versions
  DROP CONSTRAINT IF EXISTS passive_checkin_contract_versions_created_by_fkey,
  ADD CONSTRAINT passive_checkin_contract_versions_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE OR REPLACE FUNCTION public.purge_user_data(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  owned_group_ids uuid[];
  owned_community_ids uuid[];
BEGIN
  -- 1. Unlink foreign keys where target_user_id is an actor/resolver/muter on other users' records
  UPDATE public.alerts SET paused_by = NULL WHERE paused_by = target_user_id;
  UPDATE public.alerts SET resolved_by = NULL WHERE resolved_by = target_user_id;
  DELETE FROM public.gm_mutes WHERE user_id = target_user_id OR muted_by = target_user_id;
  DELETE FROM public.alert_events WHERE actor_id = target_user_id;

  -- 2. Clear private passive evidence, runtime, failure and shadow tables
  DELETE FROM private.job_failures WHERE subject_id = target_user_id;
  DELETE FROM private.passive_alert_causal_windows
    WHERE alert_id IN (SELECT id FROM public.alerts WHERE user_id = target_user_id)
       OR window_id IN (SELECT id FROM public.passive_checkin_windows WHERE user_id = target_user_id);
  DELETE FROM private.passive_window_transitions WHERE user_id = target_user_id;
  DELETE FROM private.passive_evidence_events WHERE user_id = target_user_id;
  DELETE FROM private.passive_evidence_incidents WHERE user_id = target_user_id;
  DELETE FROM private.passive_surface_health_intervals WHERE user_id = target_user_id;
  DELETE FROM private.passive_collector_bindings WHERE user_id = target_user_id;
  DELETE FROM private.passive_shadow_candidates WHERE user_id = target_user_id;
  DELETE FROM public.passive_checkin_recommendations WHERE user_id = target_user_id;

  -- 3. Clear passive checkin accounts & windows FK pointers before deleting contract versions
  UPDATE public.passive_checkin_accounts
    SET active_contract_version_id = NULL, active_epoch_id = NULL
    WHERE user_id = target_user_id;
  DELETE FROM public.passive_checkin_windows WHERE user_id = target_user_id;
  DELETE FROM public.passive_monitoring_epochs WHERE user_id = target_user_id;
  DELETE FROM public.passive_checkin_contract_versions WHERE user_id = target_user_id;
  DELETE FROM public.passive_checkin_accounts WHERE user_id = target_user_id;

  -- 4. Clear relationships, special attention, and memberships
  DELETE FROM public.special_attention_notices
    WHERE subscriber_id = target_user_id
       OR incident_id IN (SELECT id FROM public.protection_health_incidents WHERE user_id = target_user_id);
  DELETE FROM public.special_attention_subscriptions WHERE subscriber_id = target_user_id OR subject_id = target_user_id;
  DELETE FROM public.guardianships WHERE ward_id = target_user_id OR guardian_id = target_user_id;
  DELETE FROM public.group_members WHERE user_id = target_user_id;
  DELETE FROM public.community_members WHERE user_id = target_user_id;

  -- 5. Cascade-delete user-owned groups and communities
  SELECT COALESCE(array_agg(id), '{}') INTO owned_group_ids FROM public.groups WHERE created_by = target_user_id;
  IF array_length(owned_group_ids, 1) > 0 THEN
    DELETE FROM public.group_members WHERE group_id = ANY(owned_group_ids);
    DELETE FROM public.groups WHERE id = ANY(owned_group_ids);
  END IF;

  SELECT COALESCE(array_agg(id), '{}') INTO owned_community_ids FROM public.communities WHERE created_by = target_user_id;
  IF array_length(owned_community_ids, 1) > 0 THEN
    DELETE FROM public.community_members WHERE community_id = ANY(owned_community_ids);
    DELETE FROM public.communities WHERE id = ANY(owned_community_ids);
  END IF;

  -- 6. Delete checkin tasks, protection health, notifications (inbox + outbound mentions), clients, push tokens, admins
  DELETE FROM public.app_admins WHERE user_id = target_user_id;
  DELETE FROM public.protection_health_incidents WHERE user_id = target_user_id;
  DELETE FROM public.checkin_tasks WHERE ward_id = target_user_id OR created_by = target_user_id;
  DELETE FROM public.notifications WHERE recipient_id = target_user_id OR (params->>'subject_id')::text = target_user_id::text;
  DELETE FROM public.clients WHERE user_id = target_user_id;
  DELETE FROM public.heartbeat_tokens WHERE user_id = target_user_id;
  DELETE FROM public.push_tokens WHERE user_id = target_user_id;
  DELETE FROM public.push_subscriptions WHERE user_id = target_user_id;

  -- 7. Delete telemetry, sensor pings, adaptive baselines, daily aggregates, shadow state
  DELETE FROM private.alert_shadow_coverage_leases WHERE user_id = target_user_id;
  DELETE FROM private.adaptive_alert_shadow_profile_dirty WHERE user_id = target_user_id;
  DELETE FROM private.adaptive_alert_shadow_subject_context_state WHERE user_id = target_user_id;
  DELETE FROM private.adaptive_alert_shadow_user_state WHERE user_id = target_user_id;
  DELETE FROM public.behavior_pings WHERE user_id = target_user_id;
  DELETE FROM public.device_activity_samples WHERE user_id = target_user_id;
  DELETE FROM public.daily_activity_aggregates WHERE user_id = target_user_id;
  DELETE FROM public.account_gap_profiles WHERE user_id = target_user_id;
  DELETE FROM public.account_normal_bounds WHERE user_id = target_user_id;
  DELETE FROM public.account_threshold_shadow WHERE user_id = target_user_id;
  DELETE FROM public.alert_gap_profiles WHERE user_id = target_user_id;
  DELETE FROM public.alert_intervention_events WHERE user_id = target_user_id;
  DELETE FROM public.alert_judgment_shadow_decisions WHERE user_id = target_user_id;
  DELETE FROM public.alert_judgment_subject_contexts WHERE user_id = target_user_id;
  DELETE FROM public.alert_observation_coverage_intervals WHERE user_id = target_user_id;
  DELETE FROM public.alert_sleep_night_contexts WHERE user_id = target_user_id;

  -- 8. Delete user's own alerts, emergency info, device state, settings, profile
  DELETE FROM public.alerts WHERE user_id = target_user_id;
  DELETE FROM public.emergency_info WHERE user_id = target_user_id;
  DELETE FROM public.device_state WHERE user_id = target_user_id;
  DELETE FROM public.user_activity_profiles WHERE user_id = target_user_id;
  DELETE FROM public.user_settings WHERE user_id = target_user_id;
  DELETE FROM public.profiles WHERE id = target_user_id;
END;
$$;

ALTER FUNCTION public.purge_user_data(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.purge_user_data(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.purge_user_data(uuid) TO service_role;
