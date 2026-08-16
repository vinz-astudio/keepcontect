-- ADR-0042 package 8b: the missing writer for private.passive_surface_health_intervals.
--
-- The table, its retention rule and the learner's exclusion clause all shipped
-- in packages 6 and 7. Nothing in production ever inserted a row: the only
-- INSERT statements in the repository are pgTAP fixtures. Verified on the
-- production project 2026-08-16 — zero rows, ever.
--
-- That is not a cosmetic gap. private.rebuild_passive_checkin_recommendation
-- excludes a training episode when it overlaps a health interval. With the
-- table permanently empty the exclusion can never fire, so the learner would
-- train a collector outage as the person's normal quiet. That is the ADR-0037
-- defect this whole feature exists to correct, reintroduced through an
-- unwritten producer rather than through a wrong rule.
--
-- Boundary. Surface health must not be an input to window state, the miss
-- chain, alert creation or escalation (spec KC-PASSIVE-CHECKIN-SPEC-001,
-- "The boundary"; asserted mechanically by supabase/tests/passive_window_engine.sql
-- against process_passive_checkin_subject). The evaluator is therefore its own
-- scheduled job and is deliberately NOT called from process_passive_checkins
-- or process_escalations.

-- Serves the open-interval lookup the evaluator does on every pass.
CREATE UNIQUE INDEX IF NOT EXISTS passive_surface_health_open_idx
ON private.passive_surface_health_intervals (binding_id, reason)
WHERE ended_at IS NULL;

-- Serves the learner's overlap scan.
CREATE INDEX IF NOT EXISTS passive_surface_health_user_span_idx
ON private.passive_surface_health_intervals (user_id, started_at DESC);

-- Per bound surface, one row per reason, with the instant the condition was
-- breached and the instant it was cleared.
--
-- Reasons are evaluated independently rather than by priority. The display
-- summary (private.passive_collector_health_summary) picks a single reason to
-- show the user; the learner unions overlapping intervals, so a surface that is
-- both silent and degraded must produce both.
--
-- `opens_at` is the moment the expectation was actually breached, never the
-- moment this evaluator noticed. For `silent` that is last contact plus twice
-- the registry cadence, so a five-minute evaluation cadence cannot shorten a
-- recorded outage.
--
-- A revoked binding closes its open intervals at revoked_at and can open no new
-- one: the surface is gone, and extending its outage to now would exclude
-- training data for a device the account no longer has.
CREATE FUNCTION private.passive_surface_health_conditions(_now timestamptz)
RETURNS TABLE(
  user_id uuid,
  binding_id uuid,
  reason text,
  unhealthy boolean,
  opens_at timestamptz,
  closes_at timestamptz
)
LANGUAGE sql STABLE SET search_path TO '' AS $$
  SELECT b.user_id, b.id, c.reason, c.unhealthy, c.opens_at, c.closes_at
  FROM private.passive_collector_bindings b
  JOIN private.passive_surface_registry r USING (surface_type)
  JOIN public.passive_checkin_accounts a ON a.user_id = b.user_id
  CROSS JOIN LATERAL (VALUES
    -- A surface whose registry cadence is NULL was never expected to contact on
    -- a schedule, so its silence is not a health signal and it can never be
    -- silent. Only permission and capability reasons apply to it.
    ('silent',
      b.revoked_at IS NULL
        AND r.expected_contact_cadence IS NOT NULL
        AND _now - coalesce(b.last_contact_at, b.bound_at) > r.expected_contact_cadence * 2,
      coalesce(b.last_contact_at, b.bound_at) + r.expected_contact_cadence * 2,
      coalesce(b.revoked_at, b.last_contact_at, _now)),
    ('permission_denied',
      b.revoked_at IS NULL AND b.permission_state = 'denied',
      coalesce(b.health_reported_at, b.bound_at),
      coalesce(b.revoked_at, b.health_reported_at, _now)),
    ('permission_revoked',
      b.revoked_at IS NULL AND b.permission_state = 'revoked',
      coalesce(b.health_reported_at, b.bound_at),
      coalesce(b.revoked_at, b.health_reported_at, _now)),
    ('capability_unsupported',
      b.revoked_at IS NULL AND b.capability_state = 'unsupported',
      coalesce(b.health_reported_at, b.bound_at),
      coalesce(b.revoked_at, b.health_reported_at, _now)),
    ('capability_degraded',
      b.revoked_at IS NULL AND b.capability_state = 'degraded',
      coalesce(b.health_reported_at, b.bound_at),
      coalesce(b.revoked_at, b.health_reported_at, _now))
  ) AS c(reason, unhealthy, opens_at, closes_at)
$$;

COMMENT ON FUNCTION private.passive_surface_health_conditions(timestamptz) IS
  'Per bound surface and reason: is the surface unhealthy now, when was the '
  'condition breached, and when was it cleared. Pure derivation, no writes.';

CREATE FUNCTION private.evaluate_passive_surface_health(_now timestamptz DEFAULT clock_timestamp())
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _opened integer := 0; _closed integer := 0;
BEGIN
  -- Close first. A surface that recovered inside this pass must not be counted
  -- as still open when the insert below tests for an existing open interval.
  WITH cond AS (SELECT * FROM private.passive_surface_health_conditions(_now)),
  shut AS (
    UPDATE private.passive_surface_health_intervals h
       SET ended_at = greatest(h.started_at, c.closes_at)
      FROM cond c
     WHERE h.binding_id = c.binding_id
       AND h.reason = c.reason
       AND h.ended_at IS NULL
       AND NOT c.unhealthy
    RETURNING 1
  )
  SELECT count(*)::integer INTO _closed FROM shut;

  WITH cond AS (SELECT * FROM private.passive_surface_health_conditions(_now)),
  born AS (
    INSERT INTO private.passive_surface_health_intervals (user_id, binding_id, started_at, reason)
    SELECT c.user_id, c.binding_id, least(c.opens_at, _now), c.reason
      FROM cond c
     WHERE c.unhealthy
       AND NOT EXISTS (
         SELECT 1 FROM private.passive_surface_health_intervals h
          WHERE h.binding_id = c.binding_id
            AND h.reason = c.reason
            AND h.ended_at IS NULL)
    RETURNING 1
  )
  SELECT count(*)::integer INTO _opened FROM born;

  RETURN jsonb_build_object('opened', _opened, 'closed', _closed, 'evaluated_at', _now);
EXCEPTION WHEN OTHERS THEN
  -- A health evaluator that throws must not take the scheduler down with it:
  -- health gates nothing, so failing loudly here would be worse than failing
  -- into the job-failure ledger the health cycle already watches.
  INSERT INTO private.job_failures (job_name, sqlstate, message)
  VALUES ('evaluate_passive_surface_health', SQLSTATE, SQLERRM);
  RETURN jsonb_build_object('error', SQLERRM, 'evaluated_at', _now);
END;
$$;

COMMENT ON FUNCTION private.evaluate_passive_surface_health(timestamptz) IS
  'Opens and closes collector health intervals. Display and learner exclusion '
  'only. Holds no window, miss-chain, alert or escalation authority.';

REVOKE ALL ON FUNCTION private.passive_surface_health_conditions(timestamptz)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.evaluate_passive_surface_health(timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.evaluate_passive_surface_health(timestamptz) TO service_role;

-- Every five minutes. The tightest registry cadence is tauri_native's five
-- minutes, so a surface can become silent ten minutes after its last contact;
-- evaluating at the same rate keeps the display within one cadence of the truth.
-- Recording accuracy does not depend on this rate: started_at is the breach
-- instant, not the observation instant.
SELECT cron.unschedule('passive-surface-health-v1')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'passive-surface-health-v1');

SELECT cron.schedule(
  'passive-surface-health-v1',
  '*/5 * * * *',
  $job$select private.evaluate_passive_surface_health();$job$
);

INSERT INTO private.scheduled_job_expectations (job_name, max_gap, matters_because)
VALUES (
  'passive-surface-health-v1',
  interval '30 minutes',
  'Collector outages stop being recorded, so the learner silently trains them '
  'as the person''s normal quiet and recommends a longer interval than the '
  'person actually earns. It fails invisibly: recommendations keep appearing, '
  'they are just wrong in the direction that delays every alert.'
)
ON CONFLICT (job_name) DO UPDATE
  SET max_gap = EXCLUDED.max_gap,
      matters_because = EXCLUDED.matters_because;
