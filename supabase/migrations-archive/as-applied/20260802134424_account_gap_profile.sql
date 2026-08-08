-- ADR-0035 step 1: account-level liveness gap profile.
--
-- What this is
--   The routine-learning root, rebuilt as ADR-0035 requires: one account, one
--   event stream across every device it is signed in on, sleep subtracted,
--   p95 taken, then shrunk toward the account's preset cohort by n/(n+k).
--   No coverage lease. No observation attestation. No outlier ceiling.
--
-- What this is NOT
--   Nothing here is wired to anything. private.silence_threshold still reads
--   public.alert_gap_profiles exactly as before, no cron job runs this, and no
--   live alert, notification, device_state, or behavior_ping row is touched.
--   ADR-0035 step 2 (shadow parallel comparison), step 3 (calibrating k against
--   production and handing the number to the human), and step 4 (switching the
--   threshold source) are separate, separately governed changes.
--
-- Two design points that are easy to get wrong later:
--
--   1. The learning stream must equal the detection stream. The live detector
--      sees `ingest_version = 2 AND abs(received_at - at) <= 300`, measured on
--      received_at. If learning admitted a wider stream than detection can see,
--      every learned gap would be shorter than the gap detection actually
--      observes, and the threshold would come out systematically too tight.
--      "Wide intake" in ADR-0035 means dropping the coverage lease, not
--      redefining what counts as a ping.
--
--   2. Sleep is subtracted, never allowed to inflate. An overnight gap is not
--      evidence of a slow rhythm. Overlap with the account's configured sleep
--      window comes off each gap before the percentile is taken. The 2-hour
--      post-wake grace in private.sleep_relaxed is deliberately NOT subtracted
--      here: that grace suppresses alerting, it is not evidence about routine.

-- 1) Sleep-window overlap for an arbitrary interval, in minutes.
--    Recurring nightly window resolved in the account's own timezone, so DST
--    shifts are handled by the calendar rather than by arithmetic.
CREATE FUNCTION private.account_gap_sleep_minutes(
  _user_id uuid,
  _from timestamptz,
  _to timestamptz
)
RETURNS double precision
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _start time;
  _end time;
  _timezone text;
  _overlap double precision;
BEGIN
  IF _user_id IS NULL OR _from IS NULL OR _to IS NULL OR _to <= _from THEN
    RETURN 0;
  END IF;

  SELECT s.sleep_start_local, s.sleep_end_local, coalesce(s.timezone, 'UTC')
    INTO _start, _end, _timezone
  FROM public.user_settings AS s
  WHERE s.user_id = _user_id;

  IF _start IS NULL OR _end IS NULL OR _start = _end THEN
    RETURN 0;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_timezone_names AS z WHERE z.name = _timezone
  ) THEN
    RETURN 0;
  END IF;

  SELECT coalesce(sum(
    greatest(
      0,
      extract(epoch FROM (
        least(_to, night.ends_at) - greatest(_from, night.starts_at)
      ))
    ) / 60.0
  ), 0)
    INTO _overlap
  FROM (
    SELECT
      ((day.d + _start) AT TIME ZONE _timezone) AS starts_at,
      ((
        day.d
        + CASE WHEN _end <= _start THEN 1 ELSE 0 END
        + _end
      ) AT TIME ZONE _timezone) AS ends_at
    FROM (
      SELECT generate.value::date AS d
      FROM pg_catalog.generate_series(
        ((_from AT TIME ZONE _timezone)::date - 1)::timestamp,
        ((_to AT TIME ZONE _timezone)::date + 1)::timestamp,
        interval '1 day'
      ) AS generate(value)
    ) AS day
  ) AS night;

  RETURN _overlap;
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION
  private.account_gap_sleep_minutes(uuid, timestamptz, timestamptz)
FROM PUBLIC, anon, authenticated, service_role;

-- 2) The profile table.
--    The primary key carries the parameters, so step 3 can sweep k without
--    destroying the previous run's rows and without a second table.
CREATE TABLE public.account_gap_profiles (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  through_date date NOT NULL,
  lookback_days integer NOT NULL CHECK (lookback_days > 0),
  shrinkage_k integer NOT NULL CHECK (shrinkage_k >= 0),
  percentile numeric(4, 3) NOT NULL CHECK (percentile > 0 AND percentile < 1),

  computed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  window_starts_at timestamptz NOT NULL,
  window_ends_at timestamptz NOT NULL,

  event_count integer NOT NULL CHECK (event_count >= 0),
  gap_count integer NOT NULL CHECK (gap_count >= 0),
  distinct_event_days integer NOT NULL CHECK (distinct_event_days >= 0),
  first_event_at timestamptz,
  last_event_at timestamptz,

  sleep_window_applied boolean NOT NULL,
  sleep_minutes_removed double precision NOT NULL DEFAULT 0
    CHECK (sleep_minutes_removed >= 0),

  -- Neutral values: no sensitivity buffer, no floor, no ceiling. Whatever
  -- assembles a threshold from this row owns those, not this table.
  personal_p50_minutes integer CHECK (personal_p50_minutes >= 0),
  personal_pctl_minutes integer CHECK (personal_pctl_minutes >= 0),
  personal_max_minutes integer CHECK (personal_max_minutes >= 0),

  cohort_key text NOT NULL,
  cohort_pctl_minutes integer NOT NULL CHECK (cohort_pctl_minutes >= 0),
  cohort_contributor_count integer NOT NULL CHECK (cohort_contributor_count >= 0),
  cohort_source text NOT NULL CHECK (cohort_source IN ('cohort', 'fallback')),

  blend_weight double precision NOT NULL
    CHECK (blend_weight >= 0 AND blend_weight <= 1),
  blended_pctl_minutes integer NOT NULL CHECK (blended_pctl_minutes >= 0),

  -- Diagnostic, not a filter. A gap that overlaps an open alert is a gap the
  -- system already called abnormal; letting it teach the model that the account
  -- is "slow" is a feedback loop. ADR-0035 chose wide intake, so these gaps are
  -- admitted -- but they are counted so step 3 can measure what that costs.
  gaps_overlapping_open_alert integer NOT NULL DEFAULT 0
    CHECK (gaps_overlapping_open_alert >= 0),

  PRIMARY KEY (user_id, through_date, lookback_days, shrinkage_k, percentile),
  CHECK (window_ends_at > window_starts_at),
  CHECK ((gap_count = 0) = (personal_pctl_minutes IS NULL))
);

ALTER TABLE public.account_gap_profiles ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.account_gap_profiles
FROM PUBLIC, anon, authenticated, service_role;

CREATE INDEX account_gap_profiles_through_date_idx
  ON public.account_gap_profiles (through_date DESC, user_id);

-- 3) The rebuild.
CREATE FUNCTION private.rebuild_account_gap_profiles(
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
  ), gaps AS (
    SELECT
      sequenced.user_id,
      sequenced.previous_minute AS starts_at,
      sequenced.at_minute AS ends_at,
      extract(epoch FROM (sequenced.at_minute - sequenced.previous_minute)) / 60.0
        AS raw_minutes,
      private.account_gap_sleep_minutes(
        sequenced.user_id, sequenced.previous_minute, sequenced.at_minute
      ) AS sleep_minutes
    FROM sequenced
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