BEGIN;

SELECT plan(6);

INSERT INTO auth.users (id, email, aud, role)
VALUES (
  '29300000-0000-4000-8000-000000000001',
  'subject-provenance@example.invalid',
  'authenticated',
  'authenticated'
)
ON CONFLICT (id) DO NOTHING;

UPDATE public.user_settings
SET sensitivity = 'balanced',
    timezone = 'UTC',
    updated_at = clock_timestamp() - interval '1 minute'
WHERE user_id = '29300000-0000-4000-8000-000000000001';

INSERT INTO public.device_state (user_id)
VALUES ('29300000-0000-4000-8000-000000000001')
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO public.groups (id, name, created_by)
VALUES (
  '29300000-0000-4000-8000-000000000010',
  'subject-provenance-fixture',
  '29300000-0000-4000-8000-000000000001'
);

UPDATE public.group_members
SET monitored = true,
    watching = true,
    status = 'active'
WHERE group_id = '29300000-0000-4000-8000-000000000010'
  AND user_id = '29300000-0000-4000-8000-000000000001';

CREATE TEMP TABLE subject_provenance_active AS
SELECT
  runtime.version_id,
  date_trunc(
    'minute',
    clock_timestamp() AT TIME ZONE 'UTC'
  ) AT TIME ZONE 'UTC' AS captured_at,
  runtime.max_population
FROM private.adaptive_alert_shadow_runtime_config AS runtime
WHERE runtime.singleton;

CREATE TEMP TABLE subject_provenance_live_before AS
SELECT
  (SELECT count(*)::bigint FROM public.alerts) AS alerts_count,
  (SELECT count(*)::bigint FROM public.alert_events) AS alert_events_count,
  (SELECT count(*)::bigint FROM public.notifications) AS notifications_count,
  encode(
    extensions.digest(
      pg_get_functiondef(
        'private.silence_threshold(uuid)'::regprocedure
      ),
      'sha256'
    ),
    'hex'
  ) AS live_threshold_hash;

SELECT lives_ok(
  $$
    SELECT private.capture_alert_shadow_subject_contexts(
      version_id,
      captured_at,
      max_population
    )
    FROM subject_provenance_active
  $$,
  'operational producer captures a monitored subject context'
);

SELECT is(
  (
    SELECT context.subject_context_sha256
    FROM public.alert_judgment_subject_contexts AS context
    CROSS JOIN subject_provenance_active AS active
    WHERE context.version_id = active.version_id
      AND context.user_id =
        '29300000-0000-4000-8000-000000000001'
      AND context.effective_to IS NULL
  ),
  (
    SELECT encode(
      extensions.digest(
        jsonb_build_object(
          'version_id', context.version_id,
          'user_id', context.user_id,
          'effective_from_utc',
            to_char(
              context.effective_from AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
          'effective_to_utc', NULL,
          'raw_sensitivity', context.raw_sensitivity,
          'canonical_sensitivity', context.canonical_sensitivity,
          'routine_mode', context.routine_mode,
          'timezone', context.timezone,
          'utc_offset_minutes', context.utc_offset_minutes,
          'settings_updated_at_utc',
            to_char(
              context.settings_updated_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
          'settings_provenance', context.settings_provenance,
          'captured_at_utc',
            to_char(
              context.captured_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
          'config_sha256', context.config_sha256,
          'evidence_version', context.evidence_version
        )::text,
        'sha256'
      ),
      'hex'
    )
    FROM public.alert_judgment_subject_contexts AS context
    CROSS JOIN subject_provenance_active AS active
    WHERE context.version_id = active.version_id
      AND context.user_id =
        '29300000-0000-4000-8000-000000000001'
      AND context.effective_to IS NULL
  ),
  'producer stores the exact complete-row hash recomputed by the evaluator'
);

SELECT is(
  (
    SELECT private.resolve_alert_candidate(
      '29300000-0000-4000-8000-000000000001',
      captured_at,
      version_id
    ) ->> 'unreplayable_reason'
    FROM subject_provenance_active
  ),
  'missing_qualified_session',
  'valid subject provenance advances evaluation to the next legitimate evidence gate'
);

SELECT is(
  (
    SELECT canonical_sensitivity
    FROM public.alert_judgment_subject_contexts AS context
    CROSS JOIN subject_provenance_active AS active
    WHERE context.version_id = active.version_id
      AND context.user_id =
        '29300000-0000-4000-8000-000000000001'
      AND context.effective_to IS NULL
  ),
  'balanced',
  'producer persists the evaluator canonical sensitivity'
);

SELECT results_eq(
  $$
    SELECT * FROM subject_provenance_live_before
    EXCEPT
    SELECT
      (SELECT count(*)::bigint FROM public.alerts),
      (SELECT count(*)::bigint FROM public.alert_events),
      (SELECT count(*)::bigint FROM public.notifications),
      live_threshold_hash
    FROM subject_provenance_live_before
  $$,
  $$
    SELECT * FROM subject_provenance_live_before WHERE false
  $$,
  'context recapture does not mutate live alert tables'
);

SELECT is(
  encode(
    extensions.digest(
      pg_get_functiondef(
        'private.silence_threshold(uuid)'::regprocedure
      ),
      'sha256'
    ),
    'hex'
  ),
  (
    SELECT live_threshold_hash FROM subject_provenance_live_before
  ),
  'context repair leaves the live threshold function unchanged'
);

SELECT * FROM finish();
ROLLBACK;
