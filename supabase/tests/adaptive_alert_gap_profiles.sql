BEGIN;
SELECT plan(57);

INSERT INTO auth.users (id, email, aud, role) VALUES
  ('43000000-0000-0000-0000-000000000001', 'gap-main@example.invalid', 'authenticated', 'authenticated'),
  ('43000000-0000-0000-0000-000000000002', 'gap-missing@example.invalid', 'authenticated', 'authenticated'),
  ('43000000-0000-0000-0000-000000000003', 'gap-outage@example.invalid', 'authenticated', 'authenticated'),
  ('43000000-0000-0000-0000-000000000004', 'gap-prompt@example.invalid', 'authenticated', 'authenticated'),
  ('43000000-0000-0000-0000-000000000005', 'gap-sleep@example.invalid', 'authenticated', 'authenticated'),
  ('43000000-0000-0000-0000-000000000006', 'gap-coverage-transition@example.invalid', 'authenticated', 'authenticated'),
  ('43000000-0000-0000-0000-000000000007', 'gap-nearest-rank@example.invalid', 'authenticated', 'authenticated')
ON CONFLICT (id) DO NOTHING;

WITH config AS (
  SELECT '{"sessionization":{"gap_minutes":30,"per_user_day_gap_cap":1,"training_horizon_days":30,"intervention_window_minutes":30},"context":{"definition_version":"gap-test-v1","day_partition":"weekday_weekend","hour_bucket_minutes":60},"personal":{"min_samples":1,"min_support_dates":1,"min_span_days":1,"max_age_days":30,"confidence_formula_version":"support_ratio_v1"},"cohort":{"min_contributors":3,"min_support_dates":2,"max_age_days":30,"algorithm":"trimmed_mean","trim_fraction":0.1},"sensitivity_buffers_minutes":{"high":0,"balanced":45,"low":90},"candidate_bounds":{"floor_minutes":1,"ceiling_minutes":600},"sleep_compensation":{"max_start_delay_minutes":0,"max_wake_advance_minutes":0,"max_wake_delay_minutes":0,"max_update_minutes_per_day":0,"min_positive_nights":1,"lookback_nights":1,"min_late_events_per_night":1,"timezone_tolerance_minutes":0}}'::jsonb AS value
)
INSERT INTO public.alert_model_versions (id, name, status, config, config_sha256, evidence_version)
SELECT '43000000-0000-0000-0000-000000000010', 'gap-profile-test', 'replay', value,
  encode(extensions.digest(value::text, 'sha256'), 'hex'), 'canonical-v2'
FROM config;

WITH config AS (
  SELECT '{"sessionization":{"gap_minutes":30,"per_user_day_gap_cap":1,"training_horizon_days":30,"intervention_window_minutes":30},"context":{"definition_version":"gap-support-v1","day_partition":"all_days","hour_bucket_minutes":60},"personal":{"min_samples":2,"min_support_dates":2,"min_span_days":5,"max_age_days":2,"confidence_formula_version":"support_ratio_v1"},"cohort":{"min_contributors":3,"min_support_dates":2,"max_age_days":30,"algorithm":"trimmed_mean","trim_fraction":0.1},"sensitivity_buffers_minutes":{"high":0,"balanced":45,"low":90},"candidate_bounds":{"floor_minutes":1,"ceiling_minutes":600},"sleep_compensation":{"max_start_delay_minutes":0,"max_wake_advance_minutes":0,"max_wake_delay_minutes":0,"max_update_minutes_per_day":0,"min_positive_nights":1,"lookback_nights":1,"min_late_events_per_night":1,"timezone_tolerance_minutes":0}}'::jsonb AS value
)
INSERT INTO public.alert_model_versions (id, name, status, config, config_sha256, evidence_version)
SELECT '43000000-0000-0000-0000-000000000020', 'gap-support-test', 'replay', value,
  encode(extensions.digest(value::text, 'sha256'), 'hex'), 'canonical-v2'
FROM config;

INSERT INTO public.alert_observation_coverage_intervals (
  version_id, user_id, starts_at, ends_at, timezone, utc_offset_minutes,
  activity_coverage_state, intervention_coverage_state, sleep_context_state,
  captured_at, finalized_at, evidence_version, provenance_sha256
) VALUES
  ('43000000-0000-0000-0000-000000000010', '43000000-0000-0000-0000-000000000001', '2026-01-01 00:00+00', '2026-01-05 23:59+00', 'UTC', 0, 'valid', 'valid', 'valid', '2025-12-31 23:00+00', '2026-01-05 23:59+00', 'canonical-v2', repeat('a', 64)),
  ('43000000-0000-0000-0000-000000000010', '43000000-0000-0000-0000-000000000003', '2026-01-01 00:00+00', '2026-01-02 00:00+00', 'UTC', 0, 'outage', 'valid', 'valid', '2025-12-31 23:00+00', '2026-01-02 00:00+00', 'canonical-v2', repeat('b', 64)),
  ('43000000-0000-0000-0000-000000000010', '43000000-0000-0000-0000-000000000004', '2026-01-01 00:00+00', '2026-01-02 00:00+00', 'UTC', 0, 'valid', 'valid', 'valid', '2025-12-31 23:00+00', '2026-01-02 00:00+00', 'canonical-v2', repeat('c', 64)),
  ('43000000-0000-0000-0000-000000000010', '43000000-0000-0000-0000-000000000005', '2026-02-01 20:00+00', '2026-02-02 05:00+00', 'UTC', 0, 'valid', 'valid', 'valid', '2026-02-01 19:00+00', '2026-02-02 05:00+00', 'canonical-v2', repeat('d', 64)),
  ('43000000-0000-0000-0000-000000000010', '43000000-0000-0000-0000-000000000006', '2026-01-01 00:00+00', '2026-01-01 02:03+00', 'UTC', 0, 'valid', 'valid', 'valid', '2025-12-31 23:00+00', '2026-01-02 06:00+00', 'canonical-v2', repeat('5', 64)),
  ('43000000-0000-0000-0000-000000000010', '43000000-0000-0000-0000-000000000006', '2026-01-01 02:03+00', '2026-01-01 06:00+00', 'UTC', 0, 'valid', 'valid', 'valid', '2025-12-31 23:00+00', '2026-01-02 06:00+00', 'canonical-v2', repeat('6', 64)),
  ('43000000-0000-0000-0000-000000000020', '43000000-0000-0000-0000-000000000001', '2026-01-01 00:00+00', '2026-01-01 05:00+00', 'UTC', 0, 'valid', 'valid', 'valid', '2025-12-31 23:00+00', '2026-01-01 05:00+00', 'canonical-v2', repeat('7', 64)),
  ('43000000-0000-0000-0000-000000000020', '43000000-0000-0000-0000-000000000007', '2026-01-01 00:00+00', '2026-01-05 23:59+00', 'UTC', 0, 'valid', 'valid', 'valid', '2025-12-31 23:00+00', '2026-01-05 23:59+00', 'canonical-v2', repeat('8', 64));

-- Five events are one session; the four-hour quiet period is one completed gap.
INSERT INTO public.behavior_pings (user_id, kind, at, received_at, ingest_version) VALUES
  ('43000000-0000-0000-0000-000000000001', 'app', '2026-01-01 00:00+00', '2026-01-01 00:00+00', 2),
  ('43000000-0000-0000-0000-000000000001', 'app', '2026-01-01 00:05+00', '2026-01-01 00:05+00', 2),
  ('43000000-0000-0000-0000-000000000001', 'app', '2026-01-01 00:10+00', '2026-01-01 00:10+00', 2),
  ('43000000-0000-0000-0000-000000000001', 'app', '2026-01-01 00:15+00', '2026-01-01 00:15+00', 2),
  ('43000000-0000-0000-0000-000000000001', 'app', '2026-01-01 00:20+00', '2026-01-01 00:20+00', 2),
  ('43000000-0000-0000-0000-000000000001', 'app', '2026-01-01 04:20+00', '2026-01-01 04:20+00', 2),
  ('43000000-0000-0000-0000-000000000001', 'app', '2026-01-01 04:30+00', '2026-01-01 04:30+00', 2),
  ('43000000-0000-0000-0000-000000000001', 'app', '2026-01-04 00:00+00', '2026-01-04 00:06+00', 2),
  ('43000000-0000-0000-0000-000000000001', 'app', '2026-01-06 00:00+00', '2026-01-06 00:00+00', 2),
  ('43000000-0000-0000-0000-000000000002', 'app', '2026-01-01 00:00+00', '2026-01-01 00:00+00', 2),
  ('43000000-0000-0000-0000-000000000003', 'app', '2026-01-01 00:00+00', '2026-01-01 00:00+00', 2),
  ('43000000-0000-0000-0000-000000000003', 'app', '2026-01-01 04:00+00', '2026-01-01 04:00+00', 2),
  ('43000000-0000-0000-0000-000000000004', 'app', '2026-01-01 00:00+00', '2026-01-01 00:00+00', 2),
  ('43000000-0000-0000-0000-000000000004', 'app', '2026-01-01 01:00+00', '2026-01-01 01:00+00', 2),
  ('43000000-0000-0000-0000-000000000005', 'app', '2026-02-01 21:00+00', '2026-02-01 21:00+00', 2),
  ('43000000-0000-0000-0000-000000000005', 'app', '2026-02-02 04:00+00', '2026-02-02 04:00+00', 2),
  ('43000000-0000-0000-0000-000000000006', 'app', '2026-01-01 00:00+00', '2026-01-01 00:00+00', 2),
  ('43000000-0000-0000-0000-000000000006', 'app', '2026-01-01 02:00+00', '2026-01-01 02:00+00', 2),
  ('43000000-0000-0000-0000-000000000006', 'app', '2026-01-01 02:05+00', '2026-01-01 02:05+00', 2),
  ('43000000-0000-0000-0000-000000000006', 'app', '2026-01-01 04:05+00', '2026-01-01 04:05+00', 2),
  ('43000000-0000-0000-0000-000000000007', 'app', '2026-01-01 00:00+00', '2026-01-01 00:00+00', 2),
  ('43000000-0000-0000-0000-000000000007', 'app', '2026-01-01 01:00+00', '2026-01-01 01:00+00', 2),
  ('43000000-0000-0000-0000-000000000007', 'app', '2026-01-02 00:00+00', '2026-01-02 00:00+00', 2),
  ('43000000-0000-0000-0000-000000000007', 'app', '2026-01-02 02:00+00', '2026-01-02 02:00+00', 2),
  ('43000000-0000-0000-0000-000000000007', 'app', '2026-01-03 00:00+00', '2026-01-03 00:00+00', 2),
  ('43000000-0000-0000-0000-000000000007', 'app', '2026-01-03 03:00+00', '2026-01-03 03:00+00', 2),
  ('43000000-0000-0000-0000-000000000007', 'app', '2026-01-04 00:00+00', '2026-01-04 00:00+00', 2),
  ('43000000-0000-0000-0000-000000000007', 'app', '2026-01-04 04:00+00', '2026-01-04 04:00+00', 2),
  ('43000000-0000-0000-0000-000000000007', 'app', '2026-01-05 00:00+00', '2026-01-05 00:00+00', 2),
  ('43000000-0000-0000-0000-000000000007', 'app', '2026-01-05 05:00+00', '2026-01-05 05:00+00', 2);

INSERT INTO public.alert_intervention_events (version_id, user_id, occurred_at, kind, captured_at, evidence_version, provenance_sha256)
VALUES
  ('43000000-0000-0000-0000-000000000010', '43000000-0000-0000-0000-000000000004', '2026-01-01 00:45+00', 'self_prompt', '2026-01-01 00:45+00', 'canonical-v2', repeat('e', 64)),
  ('43000000-0000-0000-0000-000000000020', '43000000-0000-0000-0000-000000000007', '2026-01-01 12:00+00', 'self_alert', '2026-01-01 12:00+00', 'canonical-v2', repeat('9', 64)),
  ('43000000-0000-0000-0000-000000000020', '43000000-0000-0000-0000-000000000007', '2026-01-02 12:00+00', 'self_alert', '2026-01-02 12:00+00', 'canonical-v2', repeat('a', 64)),
  ('43000000-0000-0000-0000-000000000020', '43000000-0000-0000-0000-000000000007', '2026-01-03 12:00+00', 'self_alert', '2026-01-03 12:00+00', 'canonical-v2', repeat('b', 64)),
  ('43000000-0000-0000-0000-000000000020', '43000000-0000-0000-0000-000000000007', '2026-01-04 12:00+00', 'self_alert', '2026-01-04 12:00+00', 'canonical-v2', repeat('c', 64));

INSERT INTO public.alert_sleep_night_contexts (version_id, user_id, anchor_date, timezone, sleep_start_local, sleep_end_local, anchor_starts_at, anchor_ends_at, utc_offset_minutes, coverage_state, captured_at, finalized_at, evidence_version, provenance_sha256) VALUES
  ('43000000-0000-0000-0000-000000000010', '43000000-0000-0000-0000-000000000005', '2026-02-01', 'UTC', '22:00', '02:00', '2026-02-01 22:00+00', '2026-02-02 02:00+00', 0, 'valid', '2026-02-01 20:00+00', '2026-02-02 02:00+00', 'canonical-v2', repeat('f', 64)),
  ('43000000-0000-0000-0000-000000000010', '43000000-0000-0000-0000-000000000005', '2026-02-02', 'UTC', '00:00', '03:00', '2026-02-02 00:00+00', '2026-02-02 03:00+00', 0, 'valid', '2026-02-01 20:00+00', '2026-02-02 03:00+00', 'canonical-v2', repeat('0', 64));

SELECT has_table('public', 'alert_observation_coverage_intervals', 'coverage candidate metadata exists');
SELECT has_table('public', 'alert_intervention_events', 'intervention candidate metadata exists');
SELECT has_column('public', 'alert_gap_profiles', 'input_sha256', 'profiles bind a deterministic input hash');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.alert_model_versions'::regclass AND conname='alert_model_versions_gap_profile_contract_check'), 'model requires Task 4 config fields');
SELECT throws_ok($$ INSERT INTO public.alert_observation_coverage_intervals (version_id, user_id, starts_at, ends_at, timezone, utc_offset_minutes, activity_coverage_state, intervention_coverage_state, sleep_context_state, captured_at, finalized_at, evidence_version, provenance_sha256) VALUES ('43000000-0000-0000-0000-000000000010','43000000-0000-0000-0000-000000000001','2026-01-02 00:00+00','2026-01-01 00:00+00','UTC',0,'valid','valid','valid','2025-12-31 00:00+00','2026-01-02 00:00+00','canonical-v2',repeat('1',64)) $$, '23514'::char(5), NULL, 'coverage interval cannot end before it starts');
SELECT throws_ok($$ INSERT INTO public.alert_model_versions (name,status,config,config_sha256,evidence_version) VALUES ('gap-config-missing','draft','{"sessionization":{"gap_minutes":1,"per_user_day_gap_cap":1},"context":{"definition_version":"x"},"personal":{"min_samples":1,"min_support_dates":1,"min_span_days":1,"max_age_days":1},"cohort":{"min_contributors":1,"min_support_dates":1,"max_age_days":1,"algorithm":"trimmed_mean","trim_fraction":0},"sensitivity_buffers_minutes":{"high":0,"balanced":45,"low":90},"candidate_bounds":{"floor_minutes":1,"ceiling_minutes":2},"sleep_compensation":{"max_start_delay_minutes":0,"max_wake_advance_minutes":0,"max_wake_delay_minutes":0,"max_update_minutes_per_day":0,"min_positive_nights":1,"lookback_nights":1,"min_late_events_per_night":1,"timezone_tolerance_minutes":0}}'::jsonb,repeat('2',64),'canonical-v2') $$, '23514'::char(5), NULL, 'missing Task 4 config fields are rejected');

SELECT is((SELECT count(*)::integer FROM private.qualified_behavior_sessions('43000000-0000-0000-0000-000000000001','2026-01-01 00:00+00','2026-01-06 00:00+00','43000000-0000-0000-0000-000000000010')), 2, 'five-event burst is one session and future event is isolated by exclusive cutoff');
SELECT is((SELECT count(*)::integer FROM private.qualified_behavior_sessions('43000000-0000-0000-0000-000000000006','2026-01-01 00:00+00','2026-01-03 00:00+00','43000000-0000-0000-0000-000000000010') ), 4, 'coverage identity transition creates a new session even inside the session gap');
SELECT results_eq($$ SELECT session_start, session_end, evidence_count FROM private.qualified_behavior_sessions('43000000-0000-0000-0000-000000000001','2026-01-01 00:00+00','2026-01-06 00:00+00','43000000-0000-0000-0000-000000000010') ORDER BY session_start LIMIT 2 $$, $$ VALUES ('2026-01-01 00:00+00'::timestamptz,'2026-01-01 00:20+00'::timestamptz,5),('2026-01-01 04:20+00'::timestamptz,'2026-01-01 04:30+00'::timestamptz,2) $$, 'raw within-session heartbeat gaps never become training sessions');
SELECT is_empty($$ SELECT * FROM private.qualified_behavior_sessions('43000000-0000-0000-0000-000000000002','2026-01-01 00:00+00','2026-01-03 00:00+00','43000000-0000-0000-0000-000000000010') $$, 'missing coverage never becomes training evidence');
SELECT is_empty($$ SELECT * FROM private.qualified_behavior_sessions('43000000-0000-0000-0000-000000000003','2026-01-01 00:00+00','2026-01-03 00:00+00','43000000-0000-0000-0000-000000000010') $$, 'outage coverage never becomes training evidence');
SELECT is((SELECT quality_state FROM private.qualified_behavior_sessions('43000000-0000-0000-0000-000000000004','2026-01-01 00:00+00','2026-01-03 00:00+00','43000000-0000-0000-0000-000000000010') ORDER BY session_start DESC LIMIT 1), 'intervention_excluded', 'prompt-induced response is marked intervention excluded');
SELECT is((SELECT count(*)::integer FROM private.qualified_behavior_sessions('43000000-0000-0000-0000-000000000001','2026-01-01 00:00+00','2026-01-06 00:00+00','43000000-0000-0000-0000-000000000010') WHERE session_start = '2026-01-04 00:06+00'), 0, 'event with more than five minute clock drift is rejected');

CREATE TEMP TABLE before_live AS SELECT (SELECT coalesce(md5(string_agg(to_jsonb(a)::text, ',' ORDER BY a.id)), '') FROM public.alerts a) AS alerts_hash, (SELECT coalesce(md5(string_agg(to_jsonb(n)::text, ',' ORDER BY n.id)), '') FROM public.notifications n) AS notifications_hash, (SELECT coalesce(md5(string_agg(to_jsonb(b)::text, ',' ORDER BY b.id)), '') FROM public.behavior_pings b) AS pings_hash;
SELECT ok((private.rebuild_alert_gap_profiles('43000000-0000-0000-0000-000000000010', '2026-01-05') ->> 'completed_gaps')::integer >= 1, 'rebuild returns only aggregate completed-gap counts');
SELECT is((SELECT sample_count FROM public.alert_gap_profiles WHERE version_id='43000000-0000-0000-0000-000000000010' AND user_id='43000000-0000-0000-0000-000000000001' AND context_key='personal_global' AND through_date='2026-01-05'), 1, 'stable hash daily cap avoids earliest or longest raw-gap bias');
SELECT is((SELECT neutral_p95_minutes FROM public.alert_gap_profiles WHERE version_id='43000000-0000-0000-0000-000000000010' AND user_id='43000000-0000-0000-0000-000000000001' AND context_key='personal_global' AND through_date='2026-01-05'), 240, 'nearest-rank p95 uses completed four-hour gap');
SELECT ok((private.rebuild_alert_gap_profiles('43000000-0000-0000-0000-000000000010', '2026-01-02') ->> 'completed_gaps')::integer >= 1, 'daily-cap fixture rebuilds qualified gaps');
SELECT is((SELECT sample_count FROM public.alert_gap_profiles WHERE version_id='43000000-0000-0000-0000-000000000010' AND user_id='43000000-0000-0000-0000-000000000006' AND context_key='personal_global' AND through_date='2026-01-02'), 1, 'stable hash daily cap retains only one of multiple same-day qualified gaps');
SELECT ok(EXISTS (SELECT 1 FROM public.alert_gap_profiles WHERE version_id='43000000-0000-0000-0000-000000000010' AND user_id='43000000-0000-0000-0000-000000000001' AND context_key <> 'personal_global' AND quality_state='valid' AND confidence=1), 'global and comparable-context profiles include quality and confidence');
SELECT is_empty($$ SELECT * FROM public.alert_gap_profiles WHERE version_id='43000000-0000-0000-0000-000000000010' AND user_id='43000000-0000-0000-0000-000000000002' $$, 'right-censored final absence is never learned');
SELECT is_empty($$ SELECT * FROM public.alert_gap_profiles WHERE version_id='43000000-0000-0000-0000-000000000010' AND user_id='43000000-0000-0000-0000-000000000004' $$, 'intervention response and its gap do not train a profile');
SELECT ok((private.rebuild_alert_gap_profiles('43000000-0000-0000-0000-000000000010', '2026-02-03') ->> 'completed_gaps')::integer >= 1, 'sleep fixture rebuilds from qualified completed gap');
SELECT is((SELECT neutral_p95_minutes FROM public.alert_gap_profiles WHERE version_id='43000000-0000-0000-0000-000000000010' AND user_id='43000000-0000-0000-0000-000000000005' AND context_key='personal_global' AND through_date='2026-02-03'), 120, 'overlapping candidate sleep intervals are unioned before subtraction');
CREATE TEMP TABLE sleep_provenance_before AS SELECT input_sha256, profile_sha256, computed_at, neutral_p95_minutes FROM public.alert_gap_profiles WHERE version_id='43000000-0000-0000-0000-000000000010' AND user_id='43000000-0000-0000-0000-000000000005' AND context_key='personal_global' AND through_date='2026-02-03';
UPDATE public.alert_sleep_night_contexts SET coverage_state='unknown' WHERE version_id='43000000-0000-0000-0000-000000000010' AND user_id='43000000-0000-0000-0000-000000000005' AND anchor_date='2026-02-01';
SELECT ok((private.rebuild_alert_gap_profiles('43000000-0000-0000-0000-000000000010', '2026-02-03') ->> 'profiles_written')::integer >= 2, 'changed candidate-sleep provenance rewrites affected global and context profiles');
SELECT ok((SELECT p.input_sha256 <> b.input_sha256 AND p.profile_sha256 <> b.profile_sha256 AND p.computed_at > b.computed_at AND p.neutral_p95_minutes=b.neutral_p95_minutes FROM public.alert_gap_profiles p CROSS JOIN sleep_provenance_before b WHERE p.version_id='43000000-0000-0000-0000-000000000010' AND p.user_id='43000000-0000-0000-0000-000000000005' AND p.context_key='personal_global' AND p.through_date='2026-02-03'), 'sleep provenance changes hashes and computed time without changing the effective p95');
SELECT is((SELECT (private.rebuild_alert_gap_profiles('43000000-0000-0000-0000-000000000010', '2026-01-05') ->> 'explicit_quiet_minutes')::integer), 0, 'unsupported browser or mutable quiet state is never deducted');
CREATE TEMP TABLE profile_before AS SELECT profile_sha256, input_sha256, computed_at FROM public.alert_gap_profiles WHERE version_id='43000000-0000-0000-0000-000000000010' AND user_id='43000000-0000-0000-0000-000000000001' AND context_key='personal_global' AND through_date='2026-01-05';
SELECT ok((private.rebuild_alert_gap_profiles('43000000-0000-0000-0000-000000000010', '2026-01-05') ->> 'profiles_written')::integer >= 0, 'identical rebuild is idempotent');
SELECT results_eq($$ SELECT * FROM profile_before EXCEPT SELECT profile_sha256, input_sha256, computed_at FROM public.alert_gap_profiles WHERE version_id='43000000-0000-0000-0000-000000000010' AND user_id='43000000-0000-0000-0000-000000000001' AND context_key='personal_global' AND through_date='2026-01-05' $$, $$ SELECT * FROM profile_before WHERE false $$, 'identical input preserves profile hashes and computed time');

CREATE TEMP TABLE utc_profile_before AS SELECT profile_sha256, input_sha256, computed_at FROM public.alert_gap_profiles WHERE version_id='43000000-0000-0000-0000-000000000010' AND user_id='43000000-0000-0000-0000-000000000001' AND context_key='personal_global' AND through_date='2026-01-05';
SET LOCAL TIME ZONE 'Asia/Tokyo';
SELECT is((private.rebuild_alert_gap_profiles('43000000-0000-0000-0000-000000000010', '2026-01-05') ->> 'profiles_written')::integer, 0, 'caller timezone cannot change deterministic daily selection or hashes');
SELECT results_eq($$ SELECT * FROM utc_profile_before EXCEPT SELECT profile_sha256, input_sha256, computed_at FROM public.alert_gap_profiles WHERE version_id='43000000-0000-0000-0000-000000000010' AND user_id='43000000-0000-0000-0000-000000000001' AND context_key='personal_global' AND through_date='2026-01-05' $$, $$ SELECT * FROM utc_profile_before WHERE false $$, 'UTC and Asia/Tokyo callers preserve identical hashes and computed time');
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE coverage_provenance_before AS SELECT profile_sha256, input_sha256, computed_at FROM public.alert_gap_profiles WHERE version_id='43000000-0000-0000-0000-000000000010' AND user_id='43000000-0000-0000-0000-000000000001' AND context_key='personal_global' AND through_date='2026-01-05';
UPDATE public.alert_observation_coverage_intervals SET provenance_sha256=repeat('f',64) WHERE version_id='43000000-0000-0000-0000-000000000010' AND user_id='43000000-0000-0000-0000-000000000001';
SELECT ok((private.rebuild_alert_gap_profiles('43000000-0000-0000-0000-000000000010', '2026-01-05') ->> 'profiles_written')::integer >= 2, 'changed qualifying coverage provenance rewrites affected profiles');
SELECT ok((SELECT p.input_sha256 <> b.input_sha256 AND p.profile_sha256 <> b.profile_sha256 AND p.computed_at > b.computed_at FROM public.alert_gap_profiles p CROSS JOIN coverage_provenance_before b WHERE p.version_id='43000000-0000-0000-0000-000000000010' AND p.user_id='43000000-0000-0000-0000-000000000001' AND p.context_key='personal_global' AND p.through_date='2026-01-05'), 'coverage provenance is bound into input/profile hashes and refreshes computed time');

INSERT INTO public.alert_gap_profiles (version_id,user_id,context_key,through_date,neutral_p95_minutes,sample_count,distinct_support_dates,support_started_on,support_ended_on,latest_evidence_at,quality_state,confidence,profile_sha256,input_sha256)
VALUES ('43000000-0000-0000-0000-000000000010','43000000-0000-0000-0000-000000000002','orphan-context','2026-01-05',60,1,1,'2026-01-01','2026-01-01','2026-01-01 01:00+00','low_support',0.1,repeat('d',64),repeat('e',64));
SELECT is((private.rebuild_alert_gap_profiles('43000000-0000-0000-0000-000000000010', '2026-01-05') ->> 'profiles_deleted')::integer, 1, 'rebuild deletes exactly the stale key no longer produced');
SELECT is_empty($$ SELECT * FROM public.alert_gap_profiles WHERE version_id='43000000-0000-0000-0000-000000000010' AND user_id='43000000-0000-0000-0000-000000000002' AND context_key='orphan-context' AND through_date='2026-01-05' $$, 'stale unproduced profile key is removed');

SELECT ok((private.rebuild_alert_gap_profiles('43000000-0000-0000-0000-000000000020', '2026-01-05') ->> 'completed_gaps')::integer >= 5, 'multi-sample fixture rebuilds five completed effective gaps');
SELECT results_eq($$ SELECT neutral_p95_minutes,sample_count,distinct_support_dates,support_started_on,support_ended_on,quality_state,confidence FROM public.alert_gap_profiles WHERE version_id='43000000-0000-0000-0000-000000000020' AND user_id='43000000-0000-0000-0000-000000000007' AND context_key='personal_global' AND through_date='2026-01-05' $$, $$ VALUES (300,5,5,'2026-01-01'::date,'2026-01-05'::date,'valid'::text,1::double precision) $$, 'nearest-rank p95 selects the fifth ordered sample and valid full-support profile');
SELECT ok((private.rebuild_alert_gap_profiles('43000000-0000-0000-0000-000000000020', '2026-01-01') ->> 'completed_gaps')::integer >= 1, 'low-support fixture rebuilds one completed gap');
SELECT results_eq($$ SELECT sample_count,distinct_support_dates,support_started_on,support_ended_on,quality_state,round(confidence::numeric,3) FROM public.alert_gap_profiles WHERE version_id='43000000-0000-0000-0000-000000000020' AND user_id='43000000-0000-0000-0000-000000000001' AND context_key='personal_global' AND through_date='2026-01-01' $$, $$ VALUES (1,1,'2026-01-01'::date,'2026-01-01'::date,'low_support'::text,0.200::numeric) $$, 'sample/date/span gates yield deterministic support-ratio confidence');
SELECT ok((private.rebuild_alert_gap_profiles('43000000-0000-0000-0000-000000000020', '2026-01-10') ->> 'completed_gaps')::integer >= 1, 'stale fixture remains a completed historical gap');
SELECT results_eq($$ SELECT quality_state,confidence FROM public.alert_gap_profiles WHERE version_id='43000000-0000-0000-0000-000000000020' AND user_id='43000000-0000-0000-0000-000000000001' AND context_key='personal_global' AND through_date='2026-01-10' $$, $$ VALUES ('stale'::text,0::double precision) $$, 'freshness gate marks stale evidence and zeros confidence');

SELECT results_eq($$ SELECT * FROM before_live EXCEPT SELECT (SELECT coalesce(md5(string_agg(to_jsonb(a)::text, ',' ORDER BY a.id)), '') FROM public.alerts a), (SELECT coalesce(md5(string_agg(to_jsonb(n)::text, ',' ORDER BY n.id)), '') FROM public.notifications n), (SELECT coalesce(md5(string_agg(to_jsonb(b)::text, ',' ORDER BY b.id)), '') FROM public.behavior_pings b) $$, $$ SELECT * FROM before_live WHERE false $$, 'candidate rebuild leaves live full-row hashes unchanged');

SELECT ok((SELECT p.prosecdef AND p.provolatile = 's' AND r.rolname=current_user FROM pg_proc p JOIN pg_roles r ON r.oid=p.proowner WHERE p.oid='private.qualified_behavior_sessions(uuid,timestamptz,timestamptz,uuid)'::regprocedure), 'qualified sessions are owner-only stable security definer');
SELECT ok((SELECT p.prosecdef AND p.provolatile = 'v' AND r.rolname=current_user FROM pg_proc p JOIN pg_roles r ON r.oid=p.proowner WHERE p.oid='private.rebuild_alert_gap_profiles(uuid,date)'::regprocedure), 'rebuild is owner-only volatile security definer');
SELECT ok((SELECT proconfig @> ARRAY['search_path=""','TimeZone=UTC'] FROM pg_proc WHERE oid='private.qualified_behavior_sessions(uuid,timestamptz,timestamptz,uuid)'::regprocedure), 'sessions pin empty search path and UTC timezone');
SELECT ok((SELECT proconfig @> ARRAY['search_path=""','TimeZone=UTC'] FROM pg_proc WHERE oid='private.rebuild_alert_gap_profiles(uuid,date)'::regprocedure), 'rebuild pins empty search path and UTC timezone');
SELECT throws_ok($$ SET LOCAL ROLE anon; SELECT * FROM public.alert_observation_coverage_intervals $$, '42501'::char(5), NULL, 'anon cannot read coverage metadata');
SELECT throws_ok($$ SET LOCAL ROLE authenticated; SELECT * FROM private.qualified_behavior_sessions('43000000-0000-0000-0000-000000000001','2026-01-01 00:00+00','2026-01-02 00:00+00','43000000-0000-0000-0000-000000000010') $$, '42501'::char(5), NULL, 'authenticated cannot execute session worker');
SELECT throws_ok($$ SET LOCAL ROLE service_role; SELECT private.rebuild_alert_gap_profiles('43000000-0000-0000-0000-000000000010','2026-01-05') $$, '42501'::char(5), NULL, 'service role cannot execute profile worker');
SELECT ok((SELECT count(*)=2 AND bool_and(relrowsecurity) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname IN ('alert_observation_coverage_intervals','alert_intervention_events')), 'candidate metadata has RLS');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid WHERE c.relname IN ('alert_observation_coverage_intervals','alert_intervention_events')), 'candidate metadata exposes no policy');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid IN ('public.alert_observation_coverage_intervals'::regclass,'public.alert_intervention_events'::regclass) AND NOT t.tgisinternal), 'candidate metadata has no trigger');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename IN ('alert_observation_coverage_intervals','alert_intervention_events')), 'candidate metadata is not realtime');
SELECT ok(NOT EXISTS (SELECT 1 FROM cron.job WHERE lower(command) ~ '(gap_profile|qualified_behavior)' OR lower(jobname) ~ '(gap_profile|qualified_behavior)'), 'gap profiles schedule no cron');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_constraint fk JOIN pg_class child ON child.oid=fk.conrelid JOIN pg_class parent ON parent.oid=fk.confrelid WHERE fk.contype='f' AND child.relname IN ('alert_observation_coverage_intervals','alert_intervention_events') AND parent.relname IN ('alerts','alert_events','notifications')), 'candidate metadata has no live alert foreign key');
SELECT results_eq($$
  WITH roles(role_name) AS (VALUES ('anon'::text),('authenticated'::text),('service_role'::text)), tables(table_name) AS (VALUES ('alert_observation_coverage_intervals'::text),('alert_intervention_events'::text)), actions(privilege_name) AS (VALUES ('DELETE'::text),('INSERT'::text),('MAINTAIN'::text),('REFERENCES'::text),('SELECT'::text),('TRIGGER'::text),('TRUNCATE'::text),('UPDATE'::text))
  SELECT role_name, table_name, string_agg(privilege_name, ',' ORDER BY privilege_name) FILTER (WHERE has_table_privilege(role_name, format('public.%I',table_name), privilege_name))
  FROM roles CROSS JOIN tables CROSS JOIN actions GROUP BY role_name, table_name ORDER BY role_name, table_name
$$, $$ SELECT role_name, table_name, NULL::text FROM (VALUES ('anon'::text),('authenticated'::text),('service_role'::text)) r(role_name) CROSS JOIN (VALUES ('alert_observation_coverage_intervals'::text),('alert_intervention_events'::text)) t(table_name) ORDER BY role_name, table_name $$, 'all eight actions are denied to every Data API role');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r',c.relowner))) a WHERE n.nspname='public' AND c.relname IN ('alert_observation_coverage_intervals','alert_intervention_events') AND a.grantee=0), 'PUBLIC has no candidate metadata table privilege');
SELECT ok(NOT EXISTS (SELECT 1 FROM information_schema.column_privileges WHERE table_schema='public' AND table_name IN ('alert_observation_coverage_intervals','alert_intervention_events') AND grantee IN ('PUBLIC','anon','authenticated','service_role')), 'candidate metadata has no Data API or PUBLIC column privilege');

SELECT * FROM finish();
ROLLBACK;
