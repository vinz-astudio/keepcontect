-- GM silence cause must follow the collector evidence used by current native
-- clients. Android and iOS 0.6.0 can keep producing qualified observation
-- coverage while the legacy device heartbeat remains stale, so heartbeat alone
-- can falsely label a healthy collector as `device_dark`.
--
-- A recent valid activity-coverage interval is the strongest available evidence
-- that the device is still observable. When it exists, an old activity ping is
-- person quiet, not device dark. The 26-hour freshness window matches the
-- protection-health coverage contract and tolerates the daily finalization
-- boundary. Heartbeat remains the compatibility fallback for clients that have
-- not produced coverage metadata yet.

CREATE INDEX IF NOT EXISTS alert_observation_coverage_valid_user_end_idx
ON public.alert_observation_coverage_intervals (user_id, ends_at DESC)
WHERE activity_coverage_state = 'valid';

CREATE OR REPLACE FUNCTION public.gm_list_clients()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE _uid uuid := auth.uid();
BEGIN
  IF NOT private.is_admin(_uid) THEN RAISE EXCEPTION 'forbidden'; END IF;
  RETURN coalesce((
    SELECT jsonb_agg(obj ORDER BY nm asc, ls desc nulls last)
    FROM (
      SELECT jsonb_build_object(
        'user_id', p.id,
        'name', coalesce(nullif(p.display_name,''), left(p.id::text,8)),
        'platform', c.platform,
        'app_version', c.app_version,
        'first_seen_at', c.first_seen_at,
        'last_seen_at', c.last_seen_at,
        'last_heartbeat_at', ds.last_heartbeat_at,
        'last_behavior_at', bp.last_at,
        'alerted', al.stage IS NOT NULL,
        'alert_cause', al.cause,
        'alert_stage', al.stage,
        'alert_opened_at', al.opened_at,
        'status',
          CASE
            WHEN al.stage IS NOT NULL THEN 'alert'
            WHEN bp.last_at IS NULL THEN 'never'
            WHEN bp.last_at > now() - interval '6 hours' THEN 'active'
            WHEN bp.last_at > now() - interval '24 hours' THEN 'quiet'
            ELSE 'silent'
          END,
        'silence_kind',
          CASE
            WHEN bp.last_at IS NOT NULL AND bp.last_at > now() - interval '6 hours'
              THEN NULL
            -- Qualified coverage is the primary collector-health signal. It
            -- deliberately outranks the legacy heartbeat used by older builds.
            WHEN coverage.has_recent_valid IS TRUE THEN 'person_quiet'
            WHEN ds.last_heartbeat_at IS NULL THEN 'unknown'
            WHEN ds.last_heartbeat_at > now() - interval '1 hour'
              THEN 'person_quiet'
            ELSE 'device_dark'
          END,
        'threshold_minutes',
          round(extract(epoch FROM private.silence_threshold(p.id)) / 60)::integer,
        'threshold_basis', CASE WHEN nb.user_id IS NULL THEN NULL ELSE jsonb_build_object(
          'has_usable_signal', nb.has_usable_signal,
          'through_date', nb.through_date,
          'computed_at', nb.computed_at,
          'sensitivity', nb.sensitivity,
          'buffer_minutes', nb.buffer_minutes,
          'normal_upper_bound_minutes', nb.normal_upper_bound_minutes,
          'largest_gap_minutes', nb.largest_gap_minutes,
          'gap_count', nb.gap_count,
          'evidence_days', nb.evidence_days,
          'sleep_window_applied', nb.sleep_window_applied
        ) END,
        'muted_until',
          CASE
            WHEN mu.user_id IS NOT NULL
              AND (mu.muted_until IS NULL OR mu.muted_until > now())
            THEN coalesce(mu.muted_until::text, 'indefinite')
            ELSE null
          END
      ) as obj,
      coalesce(nullif(p.display_name,''), left(p.id::text,8)) as nm,
      c.last_seen_at as ls
      FROM public.profiles p
      LEFT JOIN public.clients c ON c.user_id = p.id
      LEFT JOIN public.device_state ds ON ds.user_id = p.id
      LEFT JOIN LATERAL (
        SELECT max(received_at) as last_at
        FROM public.behavior_pings
        WHERE user_id = p.id
          AND ingest_version = 2
          AND abs(extract(epoch from (received_at - at))) <= 300
      ) bp ON true
      LEFT JOIN LATERAL (
        SELECT true AS has_recent_valid
        FROM public.alert_observation_coverage_intervals cov
        WHERE cov.user_id = p.id
          AND cov.activity_coverage_state = 'valid'
          AND cov.ends_at > now() - interval '26 hours'
        ORDER BY cov.ends_at DESC
        LIMIT 1
      ) coverage ON true
      LEFT JOIN LATERAL (
        SELECT a.cause, a.stage, a.opened_at
        FROM public.alerts a
        WHERE a.user_id = p.id
          AND a.status = 'open'
          AND a.stage in ('group','community','terminal')
        ORDER BY a.opened_at DESC
        LIMIT 1
      ) al ON true
      LEFT JOIN LATERAL (
        SELECT b.*
        FROM public.account_normal_bounds b
        WHERE b.user_id = p.id
        ORDER BY b.through_date DESC, b.computed_at DESC
        LIMIT 1
      ) nb ON true
      LEFT JOIN public.gm_mutes mu ON mu.user_id = p.id
    ) s
  ), '[]'::jsonb);
END;
$function$;
