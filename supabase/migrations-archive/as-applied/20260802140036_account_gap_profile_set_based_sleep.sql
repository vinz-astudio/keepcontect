-- Brings production in line with the corrected
-- supabase/migrations/20260802193000_account_gap_profile.sql.
--
-- The first draft computed the sleep overlap through a per-gap helper
-- function. At production volume that is one user_settings lookup and one
-- timezone-catalogue scan per gap, and the rebuild did not finish. The rule is
-- now expressed once, set-based, inside the rebuild. The helper is removed so
-- that one rule does not end up with two implementations.
--
-- Behaviour is otherwise identical, and nothing reads these objects yet.

DROP FUNCTION IF EXISTS private.account_gap_sleep_minutes(uuid, timestamptz, timestamptz);

CREATE OR REPLACE FUNCTION private.rebuild_account_gap_profiles(
  _through_date date DEFAULT NULL,
  _lookback_days integer DEFAULT 30,
  _shrinkage_k integer DEFAULT 50,
  _percentile numeric DEFAULT 0.95,
  _cohort_min_gaps integer DEFAULT 30,
  _cohort_min_contributors integer DEFAULT 2,
  _cohort_fallback_minutes integer DEFAULT 90,
  _cohort_requires_consent boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET TimeZone = 'UTC'
AS $$
DECLARE
  _date date := coalesce(_through_date, (now() AT TIME ZONE 'UTC')::date);
  _window_ends timestamptz;
  _window_starts timestamptz;
  _written integer := 0;
BEGIN
  IF _lookback_days IS NULL OR _lookback_days <= 0
     OR _shrinkage_k IS NULL OR _shrinkage_k < 0
     OR _percentile IS NULL OR _percentile <= 0 OR _percentile >= 1
     OR _cohort_min_gaps IS NULL OR _cohort_min_gaps < 0
     OR _cohort_min_contributors IS NULL OR _cohort_min_contributors < 1
     OR _cohort_fallback_minutes IS NULL OR _cohort_fallback_minutes < 0 THEN
    RAISE EXCEPTION 'rebuild_account_gap_profiles: invalid parameters';
  END IF;

  _window_ends := (_date + 1)::timestamptz;
  _window_starts := _window_ends - pg_catalog.make_interval(days => _lookback_days);

  WITH events AS (
    -- One account, every device, deduplicated to the minute so that a device
    -- that reports twice in the same minute does not buy the account extra
    -- apparent evidence (n drives the shrinkage weight).
    SELECT
      b.user_id,
      date_trunc('minute', b.received_at) AS at_minute
    FROM public.behavior_pings AS b
    WHERE b.ingest_version = 2
      AND abs(extract(epoch FROM (b.received_at - b.at))) <= 300
      AND b.received_at >= _window_starts
      AND b.received_at < _window_ends
    GROUP BY b.user_id, date_trunc('minute', b.received_at)
  ), sequenced AS (
    SELECT
      events.user_id,
      events.at_minute,
      lag(events.at_minute) OVER (
        PARTITION BY events.user_id ORDER BY events.at_minute
      ) AS previous_minute
    FROM events
  ), sleep_windows AS (
    -- Resolved once per account. An unusable timezone means no subtraction at
    -- all, which leaves the gap at its full length: the safe direction.
    SELECT
      s.user_id,
      s.sleep_start_local AS starts_local,
      s.sleep_end_local AS ends_local,
      coalesce(s.timezone, 'UTC') AS timezone
    FROM public.user_settings AS s
    WHERE s.sleep_start_local IS NOT NULL
      AND s.sleep_end_local IS NOT NULL
      AND s.sleep_start_local <> s.sleep_end_local
      AND EXISTS (
        SELECT 1
        FROM pg_catalog.pg_timezone_names AS z
        WHERE z.name = coalesce(s.timezone, 'UTC')
      )
  ), gaps AS (
    SELECT
      sequenced.user_id,
      sequenced.previous_minute AS starts_at,
      sequenced.at_minute AS ends_at,
      extract(epoch FROM (sequenced.at_minute - sequenced.previous_minute)) / 60.0
        AS raw_minutes,
      coalesce(sleep.minutes, 0) AS sleep_minutes
    FROM sequenced
    LEFT JOIN sleep_windows ON sleep_windows.user_id = sequenced.user_id
    LEFT JOIN LATERAL (
      -- The nightly window is materialised per calendar day in the account's
      -- own timezone, so a DST shift moves the window with the wall clock.
      SELECT sum(greatest(0, extract(epoch FROM (
               least(sequenced.at_minute, night.ends_at)
               - greatest(sequenced.previous_minute, night.starts_at)
             )))) / 60.0 AS minutes
      FROM (
        SELECT
          ((day.d + sleep_windows.starts_local) AT TIME ZONE sleep_windows.timezone)
            AS starts_at,
          ((
            day.d
            + CASE
                WHEN sleep_windows.ends_local <= sleep_windows.starts_local
                THEN 1 ELSE 0
              END
            + sleep_windows.ends_local
          ) AT TIME ZONE sleep_windows.timezone) AS ends_at
        FROM (
          SELECT generate.value::date AS d
          FROM pg_catalog.generate_series(
            ((sequenced.previous_minute AT TIME ZONE sleep_windows.timezone)::date - 1)::timestamp,
            ((sequenced.at_minute AT TIME ZONE sleep_windows.timezone)::date + 1)::timestamp,
            interval '1 day'
          ) AS generate(value)
        ) AS day
      ) AS night
    ) AS sleep ON true
    WHERE sequenced.previous_minute IS NOT NULL
  ), adjusted AS (
    SELECT
      gaps.user_id,
      greatest(0, gaps.raw_minutes - gaps.sleep_minutes) AS gap_minutes,
      least(gaps.sleep_minutes, gaps.raw_minutes) AS sleep_minutes,
      EXISTS (
        SELECT 1
        FROM public.alerts AS a
        WHERE a.user_id = gaps.user_id
          AND a.opened_at < gaps.ends_at
          AND coalesce(a.resolved_at, _window_ends) > gaps.starts_at
      ) AS overlaps_alert
    FROM gaps
  ), event_stats AS (
    SELECT
      events.user_id,
      count(*)::integer AS event_count,
      count(DISTINCT events.at_minute::date)::integer AS distinct_event_days,
      min(events.at_minute) AS first_event_at,
      max(events.at_minute) AS last_event_at
    FROM events
    GROUP BY events.user_id
  ), gap_stats AS (
    SELECT
      adjusted.user_id,
      count(*)::integer AS gap_count,
      round(percentile_cont(0.5) WITHIN GROUP (
        ORDER BY adjusted.gap_minutes
      )::numeric)::integer AS personal_p50_minutes,
      round(percentile_cont(_percentile::double precision) WITHIN GROUP (
        ORDER BY adjusted.gap_minutes
      )::numeric)::integer AS personal_pctl_minutes,
      round(max(adjusted.gap_minutes)::numeric)::integer AS personal_max_minutes,
      sum(adjusted.sleep_minutes) AS sleep_minutes_removed,
      count(*) FILTER (WHERE adjusted.overlaps_alert)::integer
        AS gaps_overlapping_open_alert
    FROM adjusted
    GROUP BY adjusted.user_id
  ), subjects AS (
    SELECT
      p.id AS user_id,
      private.canonical_routine_mode(p.routine_pattern) AS cohort_key,
      coalesce(p.consent_data_sharing, false) AS consent_data_sharing,
      coalesce(event_stats.event_count, 0) AS event_count,
      coalesce(event_stats.distinct_event_days, 0) AS distinct_event_days,
      event_stats.first_event_at,
      event_stats.last_event_at,
      coalesce(gap_stats.gap_count, 0) AS gap_count,
      gap_stats.personal_p50_minutes,
      gap_stats.personal_pctl_minutes,
      gap_stats.personal_max_minutes,
      coalesce(gap_stats.sleep_minutes_removed, 0) AS sleep_minutes_removed,
      coalesce(gap_stats.gaps_overlapping_open_alert, 0)
        AS gaps_overlapping_open_alert,
      EXISTS (
        SELECT 1
        FROM public.user_settings AS s
        WHERE s.user_id = p.id
          AND s.sleep_start_local IS NOT NULL
          AND s.sleep_end_local IS NOT NULL
          AND s.sleep_start_local <> s.sleep_end_local
      ) AS sleep_window_applied
    FROM public.profiles AS p
    LEFT JOIN event_stats ON event_stats.user_id = p.id
    LEFT JOIN gap_stats ON gap_stats.user_id = p.id
  ), cohorts AS (
    -- The preset model is the median of its members' own neutral values, so a
    -- single extreme account cannot drag the anchor. Only accounts with enough
    -- of their own evidence contribute; the thin ones are the ones being
    -- anchored, and letting them vote would be circular.
    SELECT
      subjects.cohort_key,
      count(*)::integer AS contributor_count,
      round(percentile_cont(0.5) WITHIN GROUP (
        ORDER BY subjects.personal_pctl_minutes
      )::numeric)::integer AS cohort_pctl_minutes
    FROM subjects
    WHERE subjects.personal_pctl_minutes IS NOT NULL
      AND subjects.gap_count >= _cohort_min_gaps
      AND (NOT _cohort_requires_consent OR subjects.consent_data_sharing)
    GROUP BY subjects.cohort_key
  ), resolved AS (
    SELECT
      subjects.*,
      CASE
        WHEN cohorts.contributor_count >= _cohort_min_contributors
          THEN cohorts.cohort_pctl_minutes
        ELSE _cohort_fallback_minutes
      END AS cohort_pctl_minutes,
      coalesce(cohorts.contributor_count, 0) AS cohort_contributor_count,
      CASE
        WHEN cohorts.contributor_count >= _cohort_min_contributors
          THEN 'cohort'
        ELSE 'fallback'
      END AS cohort_source,
      -- ADR-0035: robustness comes from this weight and nothing else. There is
      -- deliberately no ceiling clamp anywhere in this statement.
      CASE
        WHEN subjects.personal_pctl_minutes IS NULL THEN 0::double precision
        ELSE subjects.gap_count::double precision
             / (subjects.gap_count + _shrinkage_k)::double precision
      END AS blend_weight
    FROM subjects
    LEFT JOIN cohorts ON cohorts.cohort_key = subjects.cohort_key
  )
  INSERT INTO public.account_gap_profiles AS target (
    user_id, through_date, lookback_days, shrinkage_k, percentile,
    computed_at, window_starts_at, window_ends_at,
    event_count, gap_count, distinct_event_days, first_event_at, last_event_at,
    sleep_window_applied, sleep_minutes_removed,
    personal_p50_minutes, personal_pctl_minutes, personal_max_minutes,
    cohort_key, cohort_pctl_minutes, cohort_contributor_count, cohort_source,
    blend_weight, blended_pctl_minutes, gaps_overlapping_open_alert
  )
  SELECT
    resolved.user_id, _date, _lookback_days, _shrinkage_k, _percentile,
    clock_timestamp(), _window_starts, _window_ends,
    resolved.event_count, resolved.gap_count, resolved.distinct_event_days,
    resolved.first_event_at, resolved.last_event_at,
    resolved.sleep_window_applied, resolved.sleep_minutes_removed,
    resolved.personal_p50_minutes, resolved.personal_pctl_minutes,
    resolved.personal_max_minutes,
    resolved.cohort_key, resolved.cohort_pctl_minutes,
    resolved.cohort_contributor_count, resolved.cohort_source,
    resolved.blend_weight,
    round((
      resolved.blend_weight * coalesce(resolved.personal_pctl_minutes, 0)
      + (1 - resolved.blend_weight) * resolved.cohort_pctl_minutes
    )::numeric)::integer,
    resolved.gaps_overlapping_open_alert
  FROM resolved
  ON CONFLICT (user_id, through_date, lookback_days, shrinkage_k, percentile)
  DO UPDATE SET
    computed_at = EXCLUDED.computed_at,
    window_starts_at = EXCLUDED.window_starts_at,
    window_ends_at = EXCLUDED.window_ends_at,
    event_count = EXCLUDED.event_count,
    gap_count = EXCLUDED.gap_count,
    distinct_event_days = EXCLUDED.distinct_event_days,
    first_event_at = EXCLUDED.first_event_at,
    last_event_at = EXCLUDED.last_event_at,
    sleep_window_applied = EXCLUDED.sleep_window_applied,
    sleep_minutes_removed = EXCLUDED.sleep_minutes_removed,
    personal_p50_minutes = EXCLUDED.personal_p50_minutes,
    personal_pctl_minutes = EXCLUDED.personal_pctl_minutes,
    personal_max_minutes = EXCLUDED.personal_max_minutes,
    cohort_key = EXCLUDED.cohort_key,
    cohort_pctl_minutes = EXCLUDED.cohort_pctl_minutes,
    cohort_contributor_count = EXCLUDED.cohort_contributor_count,
    cohort_source = EXCLUDED.cohort_source,
    blend_weight = EXCLUDED.blend_weight,
    blended_pctl_minutes = EXCLUDED.blended_pctl_minutes,
    gaps_overlapping_open_alert = EXCLUDED.gaps_overlapping_open_alert;

  GET DIAGNOSTICS _written = ROW_COUNT;

  RETURN jsonb_build_object(
    'through_date', _date,
    'lookback_days', _lookback_days,
    'shrinkage_k', _shrinkage_k,
    'percentile', _percentile,
    'cohort_min_gaps', _cohort_min_gaps,
    'cohort_min_contributors', _cohort_min_contributors,
    'cohort_fallback_minutes', _cohort_fallback_minutes,
    'cohort_requires_consent', _cohort_requires_consent,
    'window_starts_at', _window_starts,
    'window_ends_at', _window_ends,
    'profiles_written', _written
  );
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION private.rebuild_account_gap_profiles(
  date, integer, integer, numeric, integer, integer, integer, boolean
) FROM PUBLIC, anon, authenticated, service_role;