-- ADR-0039 / S2: private operational state stays RPC-only.
revoke all privileges on table
  public.account_gap_profiles,
  public.account_normal_bounds,
  public.account_threshold_shadow,
  public.alert_gap_profiles,
  public.alert_intervention_events,
  public.alert_judgment_evaluations,
  public.alert_judgment_shadow_decisions,
  public.alert_judgment_subject_contexts,
  public.alert_model_versions,
  public.alert_observation_coverage_intervals,
  public.alert_sleep_night_contexts,
  public.routine_mode_cohort_generations,
  public.routine_mode_cohort_invalidations,
  public.routine_mode_cohort_priors,
  public.gm_mutes
from public, anon, authenticated, service_role;
