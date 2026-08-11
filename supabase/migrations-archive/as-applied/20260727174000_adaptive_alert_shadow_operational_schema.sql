-- ADR-0028: bounded operational evidence for a default-disabled shadow.
-- These objects are owner-only, scheduler-free, and have no live alert authority.

CREATE TABLE private.adaptive_alert_shadow_user_state (
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  evaluated_at timestamptz NOT NULL,
  replayable boolean NOT NULL,
  would_alert boolean,
  basis text,
  candidate_threshold_minutes integer,
  quality_state text NOT NULL,
  unreplayable_reason text,
  decision_sha256 text NOT NULL CHECK (decision_sha256 ~ '^[a-f0-9]{64}$'),
  last_persisted_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (version_id, user_id),
  CHECK (replayable OR would_alert IS NULL)
);

CREATE TABLE private.adaptive_alert_shadow_cycle_runs (
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE CASCADE,
  evaluated_minute timestamptz NOT NULL,
  status text NOT NULL CHECK (status IN ('completed', 'empty')),
  duration_ms integer NOT NULL CHECK (duration_ms >= 0),
  population_count integer NOT NULL CHECK (population_count >= 0),
  evaluated_count integer NOT NULL CHECK (evaluated_count >= 0),
  metrics jsonb NOT NULL CHECK (jsonb_typeof(metrics) = 'object'),
  run_sha256 text NOT NULL CHECK (run_sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (version_id, evaluated_minute)
);

CREATE TABLE private.adaptive_alert_shadow_daily_reports (
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE CASCADE,
  report_date date NOT NULL,
  segment_key text NOT NULL,
  contributor_count integer NOT NULL CHECK (contributor_count >= 0),
  suppressed boolean NOT NULL,
  metrics jsonb NOT NULL CHECK (jsonb_typeof(metrics) = 'object'),
  report_sha256 text NOT NULL CHECK (report_sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (version_id, report_date, segment_key),
  CHECK ((contributor_count < 10) = suppressed),
  CHECK (NOT (metrics ?| ARRAY[
    'user_id', 'client_id', 'event_id', 'alert_id', 'occurred_at', 'raw_error'
  ]))
);

CREATE TABLE private.adaptive_alert_shadow_profile_dirty (
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  invalidated_at timestamptz NOT NULL,
  reason text NOT NULL CHECK (reason IN ('settings_changed', 'profile_changed', 'consent_withdrawn')),
  PRIMARY KEY (version_id, user_id)
);

CREATE TABLE private.adaptive_alert_shadow_cohort_dirty (
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE CASCADE,
  routine_mode text NOT NULL CHECK (
    routine_mode IN ('regular_9to5', 'semester_break', 'shift_irregular')
  ),
  context_key text NOT NULL,
  invalidated_at timestamptz NOT NULL,
  reason text NOT NULL CHECK (reason IN (
    'settings_changed', 'profile_changed', 'consent_withdrawn',
    'source_invalidation'
  )),
  PRIMARY KEY (version_id, routine_mode, context_key)
);

CREATE TABLE private.adaptive_alert_shadow_subject_context_state (
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  context_state text NOT NULL CHECK (context_state IN ('replayable', 'unreplayable')),
  unreplayable_reason text,
  subject_context_sha256 text NOT NULL CHECK (
    subject_context_sha256 ~ '^[a-f0-9]{64}$'
  ),
  captured_at timestamptz NOT NULL,
  PRIMARY KEY (version_id, user_id),
  CHECK (
    (context_state = 'replayable' AND unreplayable_reason IS NULL)
    OR
    (context_state = 'unreplayable' AND unreplayable_reason IS NOT NULL)
  )
);

CREATE TABLE private.adaptive_alert_shadow_intervention_cursor (
  version_id uuid NOT NULL REFERENCES public.alert_model_versions(id) ON DELETE CASCADE,
  source_kind text NOT NULL CHECK (
    source_kind IN ('notification', 'checkin_task', 'guardianship')
  ),
  last_captured_at timestamptz NOT NULL,
  last_source_id uuid,
  PRIMARY KEY (version_id, source_kind)
);

ALTER TABLE private.adaptive_alert_shadow_user_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.adaptive_alert_shadow_cycle_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.adaptive_alert_shadow_daily_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.adaptive_alert_shadow_profile_dirty ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.adaptive_alert_shadow_cohort_dirty ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.adaptive_alert_shadow_subject_context_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.adaptive_alert_shadow_intervention_cursor ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON TABLE
  private.adaptive_alert_shadow_user_state,
  private.adaptive_alert_shadow_cycle_runs,
  private.adaptive_alert_shadow_daily_reports,
  private.adaptive_alert_shadow_profile_dirty,
  private.adaptive_alert_shadow_cohort_dirty,
  private.adaptive_alert_shadow_subject_context_state,
  private.adaptive_alert_shadow_intervention_cursor
FROM PUBLIC, anon, authenticated, service_role;

ALTER TABLE public.alert_intervention_events
  DROP CONSTRAINT alert_intervention_events_kind_check,
  ADD COLUMN source_kind text DEFAULT 'legacy',
  ADD COLUMN source_id uuid DEFAULT gen_random_uuid();

UPDATE public.alert_intervention_events
SET source_kind = 'legacy', source_id = id;

ALTER TABLE public.alert_intervention_events
  ALTER COLUMN source_kind SET NOT NULL,
  ALTER COLUMN source_id SET NOT NULL,
  ADD CONSTRAINT alert_intervention_events_kind_check CHECK (
    kind IN (
      'self_alert', 'self_prompt', 'checkin_prompt', 'concern_prompt',
      'guardian_confirmation'
    )
  ),
  ADD CONSTRAINT alert_intervention_events_source_kind_check CHECK (
    source_kind IN ('legacy', 'notification', 'checkin_task', 'guardianship')
  ),
  ADD CONSTRAINT alert_intervention_events_source_unique
    UNIQUE (version_id, source_kind, source_id);

CREATE FUNCTION private.capture_alert_shadow_subject_contexts(
  _version_id uuid,
  _captured_at timestamptz,
  _max_users integer
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET timezone = 'UTC'
AS $$
DECLARE
  _version public.alert_model_versions%ROWTYPE;
  _person record;
  _population_count integer := 0;
  _replayable_count integer := 0;
  _unreplayable_count integer := 0;
  _reason text;
  _state text;
  _offset integer;
  _context_sha text;
  _prior_sha text;
  _provenance jsonb;
BEGIN
  IF _version_id IS NULL OR _captured_at IS NULL
     OR _max_users IS NULL OR _max_users NOT BETWEEN 1 AND 10000 THEN
    RAISE EXCEPTION 'invalid shadow context capture arguments';
  END IF;

  SELECT v.* INTO _version
  FROM public.alert_model_versions AS v
  WHERE v.id = _version_id
    AND v.status = 'shadow'
    AND v.shadow_enabled_at IS NOT NULL
    AND v.shadow_enabled_at <= _captured_at;

  IF NOT FOUND
     OR _version.evidence_version <> 'canonical-v2'
     OR _version.config_sha256 <>
       encode(extensions.digest(_version.config::text, 'sha256'), 'hex') THEN
    RAISE EXCEPTION 'invalid shadow context version';
  END IF;

  FOR _person IN
    WITH population AS (
      SELECT ds.user_id FROM public.device_state AS ds
      UNION
      SELECT gm.user_id
      FROM public.group_members AS gm
      WHERE gm.status = 'active' AND gm.monitored
    )
    SELECT
      p.user_id,
      coalesce(s.sensitivity, 'balanced') AS sensitivity,
      coalesce(s.timezone, 'UTC') AS timezone,
      coalesce(s.updated_at, _captured_at) AS settings_updated_at,
      coalesce(pr.routine_pattern, 'regular_9to5') AS routine_mode
    FROM population AS p
    LEFT JOIN public.user_settings AS s ON s.user_id = p.user_id
    LEFT JOIN public.profiles AS pr ON pr.id = p.user_id
    ORDER BY p.user_id
    LIMIT _max_users
  LOOP
    _population_count := _population_count + 1;
    _reason := NULL;
    _offset := 0;

    IF _person.settings_updated_at > _captured_at THEN
      _reason := 'future_source_timestamp';
    ELSIF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_timezone_names AS z
      WHERE z.name = _person.timezone
    ) THEN
      _reason := 'invalid_timezone';
    ELSE
      _offset := round(extract(epoch FROM (
        (_captured_at AT TIME ZONE _person.timezone)
        - (_captured_at AT TIME ZONE 'UTC')
      )) / 60)::integer;
    END IF;

    _state := CASE WHEN _reason IS NULL THEN 'replayable' ELSE 'unreplayable' END;
    _provenance := jsonb_build_object(
      'contract_version', 'shadow-subject-context-v1',
      'version_id', _version_id,
      'user_id', _person.user_id,
      'sensitivity', _person.sensitivity,
      'routine_mode', _person.routine_mode,
      'timezone', _person.timezone,
      'utc_offset_minutes', _offset,
      'settings_updated_at', _person.settings_updated_at,
      'config_sha256', _version.config_sha256,
      'evidence_version', _version.evidence_version,
      'state', _state,
      'reason', _reason
    );
    _context_sha := encode(
      extensions.digest(_provenance::text, 'sha256'), 'hex'
    );

    SELECT s.subject_context_sha256 INTO _prior_sha
    FROM private.adaptive_alert_shadow_subject_context_state AS s
    WHERE s.version_id = _version_id AND s.user_id = _person.user_id;

    IF _reason IS NOT NULL THEN
      UPDATE public.alert_judgment_subject_contexts
      SET effective_to = _captured_at
      WHERE version_id = _version_id
        AND user_id = _person.user_id
        AND effective_to IS NULL
        AND effective_from < _captured_at;
    ELSIF _prior_sha IS DISTINCT FROM _context_sha THEN
      UPDATE public.alert_judgment_subject_contexts
      SET effective_to = _captured_at
      WHERE version_id = _version_id
        AND user_id = _person.user_id
        AND effective_to IS NULL
        AND effective_from < _captured_at;

      INSERT INTO public.alert_judgment_subject_contexts (
        version_id, user_id, effective_from, raw_sensitivity,
        canonical_sensitivity, routine_mode, timezone, utc_offset_minutes,
        settings_updated_at, settings_provenance, captured_at,
        config_sha256, evidence_version, subject_context_sha256
      ) VALUES (
        _version_id, _person.user_id, _captured_at, _person.sensitivity,
        _person.sensitivity, _person.routine_mode, _person.timezone, _offset,
        _person.settings_updated_at, _provenance, _captured_at,
        _version.config_sha256, _version.evidence_version, _context_sha
      );
    END IF;

    INSERT INTO private.adaptive_alert_shadow_subject_context_state (
      version_id, user_id, context_state, unreplayable_reason,
      subject_context_sha256, captured_at
    ) VALUES (
      _version_id, _person.user_id, _state, _reason, _context_sha, _captured_at
    )
    ON CONFLICT (version_id, user_id) DO UPDATE SET
      context_state = excluded.context_state,
      unreplayable_reason = excluded.unreplayable_reason,
      subject_context_sha256 = excluded.subject_context_sha256,
      captured_at = excluded.captured_at;

    IF _reason IS NULL THEN
      _replayable_count := _replayable_count + 1;
    ELSE
      _unreplayable_count := _unreplayable_count + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'status', 'completed',
    'population_count', _population_count,
    'replayable_count', _replayable_count,
    'unreplayable_count', _unreplayable_count
  );
END;
$$;

CREATE FUNCTION private.capture_alert_shadow_interventions(
  _version_id uuid,
  _through_at timestamptz,
  _max_rows integer
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET timezone = 'UTC'
AS $$
DECLARE
  _evidence_version text;
  _inserted integer := 0;
  _step integer := 0;
BEGIN
  IF _version_id IS NULL OR _through_at IS NULL
     OR _max_rows IS NULL OR _max_rows NOT BETWEEN 1 AND 10000 THEN
    RAISE EXCEPTION 'invalid shadow intervention capture arguments';
  END IF;

  SELECT v.evidence_version INTO _evidence_version
  FROM public.alert_model_versions AS v
  WHERE v.id = _version_id AND v.status = 'shadow';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid shadow intervention version';
  END IF;

  WITH source AS (
    SELECT n.id, n.recipient_id AS user_id, n.created_at AS occurred_at,
      CASE WHEN n.kind = 'self' THEN 'self_alert' ELSE 'concern_prompt' END AS kind
    FROM public.notifications AS n
    WHERE n.created_at <= _through_at
    ORDER BY n.created_at, n.id
    LIMIT _max_rows
  )
  INSERT INTO public.alert_intervention_events (
    version_id, user_id, occurred_at, kind, captured_at, evidence_version,
    provenance_sha256, source_kind, source_id
  )
  SELECT
    _version_id, s.user_id, s.occurred_at, s.kind, _through_at,
    _evidence_version,
    encode(extensions.digest(jsonb_build_object(
      'version_id', _version_id, 'source_kind', 'notification',
      'source_id', s.id, 'user_id', s.user_id,
      'occurred_at', s.occurred_at, 'kind', s.kind
    )::text, 'sha256'), 'hex'),
    'notification', s.id
  FROM source AS s
  ON CONFLICT (version_id, source_kind, source_id) DO NOTHING;
  GET DIAGNOSTICS _step = ROW_COUNT;
  _inserted := _inserted + _step;

  WITH source AS (
    SELECT t.id, t.ward_id AS user_id, t.created_at AS occurred_at
    FROM public.checkin_tasks AS t
    WHERE t.created_at <= _through_at
    ORDER BY t.created_at, t.id
    LIMIT greatest(_max_rows - _inserted, 0)
  )
  INSERT INTO public.alert_intervention_events (
    version_id, user_id, occurred_at, kind, captured_at, evidence_version,
    provenance_sha256, source_kind, source_id
  )
  SELECT
    _version_id, s.user_id, s.occurred_at, 'checkin_prompt', _through_at,
    _evidence_version,
    encode(extensions.digest(jsonb_build_object(
      'version_id', _version_id, 'source_kind', 'checkin_task',
      'source_id', s.id, 'user_id', s.user_id,
      'occurred_at', s.occurred_at
    )::text, 'sha256'), 'hex'),
    'checkin_task', s.id
  FROM source AS s
  ON CONFLICT (version_id, source_kind, source_id) DO NOTHING;
  GET DIAGNOSTICS _step = ROW_COUNT;
  _inserted := _inserted + _step;

  WITH source AS (
    SELECT g.id, g.ward_id AS user_id, g.created_at AS occurred_at
    FROM public.guardianships AS g
    WHERE g.status = 'active' AND g.created_at <= _through_at
    ORDER BY g.created_at, g.id
    LIMIT greatest(_max_rows - _inserted, 0)
  )
  INSERT INTO public.alert_intervention_events (
    version_id, user_id, occurred_at, kind, captured_at, evidence_version,
    provenance_sha256, source_kind, source_id
  )
  SELECT
    _version_id, s.user_id, s.occurred_at, 'guardian_confirmation', _through_at,
    _evidence_version,
    encode(extensions.digest(jsonb_build_object(
      'version_id', _version_id, 'source_kind', 'guardianship',
      'source_id', s.id, 'user_id', s.user_id,
      'occurred_at', s.occurred_at
    )::text, 'sha256'), 'hex'),
    'guardianship', s.id
  FROM source AS s
  ON CONFLICT (version_id, source_kind, source_id) DO NOTHING;
  GET DIAGNOSTICS _step = ROW_COUNT;
  _inserted := _inserted + _step;

  INSERT INTO private.adaptive_alert_shadow_intervention_cursor (
    version_id, source_kind, last_captured_at
  ) VALUES
    (_version_id, 'notification', _through_at),
    (_version_id, 'checkin_task', _through_at),
    (_version_id, 'guardianship', _through_at)
  ON CONFLICT (version_id, source_kind) DO UPDATE SET
    last_captured_at = greatest(
      private.adaptive_alert_shadow_intervention_cursor.last_captured_at,
      excluded.last_captured_at
    );

  RETURN jsonb_build_object('status', 'completed', 'inserted_count', _inserted);
END;
$$;

CREATE FUNCTION private.mark_adaptive_alert_shadow_dirty()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET timezone = 'UTC'
AS $$
DECLARE
  _user_id uuid;
  _routine_mode text;
  _reason text;
  _changed_at timestamptz := clock_timestamp();
BEGIN
  IF TG_TABLE_NAME = 'profiles' THEN
    _user_id := NEW.id;
    _routine_mode := coalesce(NEW.routine_pattern, 'regular_9to5');
    _reason := CASE
      WHEN TG_OP = 'UPDATE'
       AND OLD.consent_data_sharing
       AND NOT NEW.consent_data_sharing
      THEN 'consent_withdrawn'
      ELSE 'profile_changed'
    END;
  ELSE
    _user_id := NEW.user_id;
    SELECT coalesce(p.routine_pattern, 'regular_9to5')
      INTO _routine_mode
    FROM public.profiles AS p WHERE p.id = _user_id;
    _routine_mode := coalesce(_routine_mode, 'regular_9to5');
    _reason := 'settings_changed';
  END IF;

  INSERT INTO private.adaptive_alert_shadow_profile_dirty (
    version_id, user_id, invalidated_at, reason
  )
  SELECT v.id, _user_id, _changed_at, _reason
  FROM public.alert_model_versions AS v
  WHERE v.status = 'shadow'
  ON CONFLICT (version_id, user_id) DO UPDATE SET
    invalidated_at = greatest(
      private.adaptive_alert_shadow_profile_dirty.invalidated_at,
      excluded.invalidated_at
    ),
    reason = excluded.reason;

  INSERT INTO private.adaptive_alert_shadow_cohort_dirty (
    version_id, routine_mode, context_key, invalidated_at, reason
  )
  SELECT v.id, _routine_mode, '*', _changed_at, _reason
  FROM public.alert_model_versions AS v
  WHERE v.status = 'shadow'
  ON CONFLICT (version_id, routine_mode, context_key) DO UPDATE SET
    invalidated_at = greatest(
      private.adaptive_alert_shadow_cohort_dirty.invalidated_at,
      excluded.invalidated_at
    ),
    reason = excluded.reason;

  IF _reason = 'consent_withdrawn' THEN
    DELETE FROM public.routine_mode_cohort_priors
    WHERE routine_mode = _routine_mode
      AND version_id IN (
        SELECT v.id FROM public.alert_model_versions AS v
        WHERE v.status = 'shadow'
      );
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER adaptive_alert_shadow_profile_dirty_trigger
AFTER UPDATE OF routine_pattern, consent_data_sharing ON public.profiles
FOR EACH ROW EXECUTE FUNCTION private.mark_adaptive_alert_shadow_dirty();

CREATE TRIGGER adaptive_alert_shadow_settings_dirty_trigger
AFTER UPDATE OF sensitivity, timezone ON public.user_settings
FOR EACH ROW EXECUTE FUNCTION private.mark_adaptive_alert_shadow_dirty();

CREATE FUNCTION private.maintain_adaptive_alert_shadow(
  _through_at timestamptz,
  _max_rows integer
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET timezone = 'UTC'
AS $$
DECLARE
  _deleted integer := 0;
  _step integer := 0;
  _reported integer := 0;
BEGIN
  IF _through_at IS NULL OR _max_rows IS NULL
     OR _max_rows NOT BETWEEN 1 AND 100000 THEN
    RAISE EXCEPTION 'invalid shadow maintenance arguments';
  END IF;

  WITH doomed AS (
    SELECT c.id
    FROM public.alert_judgment_subject_contexts AS c
    WHERE coalesce(c.effective_to, c.captured_at)
      < _through_at - interval '35 days'
    ORDER BY coalesce(c.effective_to, c.captured_at), c.id
    LIMIT _max_rows
  )
  DELETE FROM public.alert_judgment_subject_contexts AS c
  WHERE c.id IN (SELECT d.id FROM doomed AS d);
  GET DIAGNOSTICS _step = ROW_COUNT;
  _deleted := _deleted + _step;

  WITH doomed AS (
    SELECT e.id
    FROM public.alert_intervention_events AS e
    WHERE e.occurred_at < _through_at - interval '35 days'
    ORDER BY e.occurred_at, e.id
    LIMIT greatest(_max_rows - _deleted, 0)
  )
  DELETE FROM public.alert_intervention_events AS e
  WHERE e.id IN (SELECT d.id FROM doomed AS d);
  GET DIAGNOSTICS _step = ROW_COUNT;
  _deleted := _deleted + _step;

  WITH doomed AS (
    SELECT d.id
    FROM public.alert_judgment_shadow_decisions AS d
    WHERE d.evaluated_at < _through_at - interval '35 days'
    ORDER BY d.evaluated_at, d.id
    LIMIT greatest(_max_rows - _deleted, 0)
  )
  DELETE FROM public.alert_judgment_shadow_decisions AS d
  WHERE d.id IN (SELECT doomed.id FROM doomed);
  GET DIAGNOSTICS _step = ROW_COUNT;
  _deleted := _deleted + _step;

  WITH doomed AS (
    SELECT l.user_id, l.event_id
    FROM private.alert_shadow_coverage_leases AS l
    WHERE l.received_at < _through_at - interval '35 days'
    ORDER BY l.received_at, l.user_id, l.event_id
    LIMIT greatest(_max_rows - _deleted, 0)
  )
  DELETE FROM private.alert_shadow_coverage_leases AS l
  WHERE (l.user_id, l.event_id) IN (
    SELECT doomed.user_id, doomed.event_id FROM doomed
  );
  GET DIAGNOSTICS _step = ROW_COUNT;
  _deleted := _deleted + _step;

  WITH doomed AS (
    SELECT c.id
    FROM public.alert_observation_coverage_intervals AS c
    WHERE c.ends_at < _through_at - interval '35 days'
    ORDER BY c.ends_at, c.id
    LIMIT greatest(_max_rows - _deleted, 0)
  )
  DELETE FROM public.alert_observation_coverage_intervals AS c
  WHERE c.id IN (SELECT doomed.id FROM doomed);
  GET DIAGNOSTICS _step = ROW_COUNT;
  _deleted := _deleted + _step;

  WITH doomed AS (
    SELECT s.version_id, s.user_id
    FROM private.adaptive_alert_shadow_user_state AS s
    WHERE s.evaluated_at < _through_at - interval '35 days'
    ORDER BY s.evaluated_at, s.version_id, s.user_id
    LIMIT greatest(_max_rows - _deleted, 0)
  )
  DELETE FROM private.adaptive_alert_shadow_user_state AS s
  WHERE (s.version_id, s.user_id) IN (
    SELECT doomed.version_id, doomed.user_id FROM doomed
  );
  GET DIAGNOSTICS _step = ROW_COUNT;
  _deleted := _deleted + _step;

  WITH doomed AS (
    SELECT s.version_id, s.user_id
    FROM private.adaptive_alert_shadow_subject_context_state AS s
    WHERE s.captured_at < _through_at - interval '35 days'
    ORDER BY s.captured_at, s.version_id, s.user_id
    LIMIT greatest(_max_rows - _deleted, 0)
  )
  DELETE FROM private.adaptive_alert_shadow_subject_context_state AS s
  WHERE (s.version_id, s.user_id) IN (
    SELECT doomed.version_id, doomed.user_id FROM doomed
  );
  GET DIAGNOSTICS _step = ROW_COUNT;
  _deleted := _deleted + _step;

  INSERT INTO private.adaptive_alert_shadow_cohort_dirty (
    version_id, routine_mode, context_key, invalidated_at, reason
  )
  SELECT
    v.id, i.routine_mode, '*', i.invalidated_at, 'source_invalidation'
  FROM public.alert_model_versions AS v
  CROSS JOIN public.routine_mode_cohort_invalidations AS i
  WHERE v.status = 'shadow'
  ON CONFLICT (version_id, routine_mode, context_key) DO UPDATE SET
    invalidated_at = greatest(
      private.adaptive_alert_shadow_cohort_dirty.invalidated_at,
      excluded.invalidated_at
    ),
    reason = excluded.reason;

  DELETE FROM public.routine_mode_cohort_priors AS p
  WHERE p.version_id IN (
      SELECT v.id FROM public.alert_model_versions AS v
      WHERE v.status = 'shadow'
    )
    AND EXISTS (
      SELECT 1
      FROM private.adaptive_alert_shadow_cohort_dirty AS d
      WHERE d.version_id = p.version_id
        AND d.routine_mode = p.routine_mode
        AND (d.context_key = '*' OR d.context_key = p.context_key)
        AND d.invalidated_at >= p.published_at
    );

  WITH report AS (
    SELECT
      v.id AS version_id,
      count(s.user_id)::integer AS contributor_count,
      count(*) FILTER (WHERE s.replayable)::integer AS replayable_count,
      count(*) FILTER (WHERE s.would_alert IS TRUE)::integer AS would_alert_count
    FROM public.alert_model_versions AS v
    LEFT JOIN private.adaptive_alert_shadow_user_state AS s
      ON s.version_id = v.id
     AND s.evaluated_at >= date_trunc('day', _through_at)
     AND s.evaluated_at < date_trunc('day', _through_at) + interval '1 day'
    WHERE v.status = 'shadow'
    GROUP BY v.id
  ), prepared AS (
    SELECT
      r.version_id,
      (_through_at AT TIME ZONE 'UTC')::date AS report_date,
      CASE WHEN r.contributor_count < 10 THEN 'other' ELSE 'all' END AS segment_key,
      r.contributor_count,
      r.contributor_count < 10 AS suppressed,
      CASE WHEN r.contributor_count < 10
        THEN jsonb_build_object('suppressed', true)
        ELSE jsonb_build_object(
          'replayable_count', r.replayable_count,
          'would_alert_count', r.would_alert_count
        )
      END AS metrics
    FROM report AS r
  )
  INSERT INTO private.adaptive_alert_shadow_daily_reports (
    version_id, report_date, segment_key, contributor_count, suppressed,
    metrics, report_sha256
  )
  SELECT
    p.version_id, p.report_date, p.segment_key, p.contributor_count,
    p.suppressed, p.metrics,
    encode(extensions.digest(jsonb_build_object(
      'version_id', p.version_id,
      'report_date', p.report_date,
      'segment_key', p.segment_key,
      'contributor_count', p.contributor_count,
      'suppressed', p.suppressed,
      'metrics', p.metrics
    )::text, 'sha256'), 'hex')
  FROM prepared AS p
  ON CONFLICT (version_id, report_date, segment_key) DO UPDATE SET
    contributor_count = excluded.contributor_count,
    suppressed = excluded.suppressed,
    metrics = excluded.metrics,
    report_sha256 = excluded.report_sha256,
    created_at = clock_timestamp();
  GET DIAGNOSTICS _reported = ROW_COUNT;

  RETURN jsonb_build_object(
    'status', 'completed',
    'deleted_count', _deleted,
    'reported_count', _reported
  );
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.capture_alert_shadow_subject_contexts(uuid,timestamptz,integer),
  private.capture_alert_shadow_interventions(uuid,timestamptz,integer),
  private.mark_adaptive_alert_shadow_dirty(),
  private.maintain_adaptive_alert_shadow(timestamptz,integer)
FROM PUBLIC, anon, authenticated, service_role;
