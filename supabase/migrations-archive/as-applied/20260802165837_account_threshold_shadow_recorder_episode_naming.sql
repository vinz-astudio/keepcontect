-- Follow the column rename through the recorder. Body is otherwise unchanged
-- from account_threshold_shadow; only the five renamed identifiers differ.

CREATE OR REPLACE FUNCTION private.record_account_threshold_shadow(
  _through_date date DEFAULT NULL,
  _lookback_days integer DEFAULT 30,
  _shrinkage_k integer DEFAULT 50,
  _percentile numeric DEFAULT 0.95,
  _buffer_high integer DEFAULT 0,
  _buffer_balanced integer DEFAULT 45,
  _buffer_low integer DEFAULT 90,
  _neutral_floor_minutes integer DEFAULT 90,
  _post_wake_grace_minutes integer DEFAULT 120
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
     OR _buffer_high IS NULL OR _buffer_high < 0
     OR _buffer_balanced IS NULL OR _buffer_balanced < 0
     OR _buffer_low IS NULL OR _buffer_low < 0
     OR _neutral_floor_minutes IS NULL OR _neutral_floor_minutes < 0
     OR _post_wake_grace_minutes IS NULL OR _post_wake_grace_minutes < 0 THEN
    RAISE EXCEPTION 'record_account_threshold_shadow: invalid parameters';
  END IF;

  _window_ends := (_date + 1)::timestamptz;
  _window_starts := _window_ends - pg_catalog.make_interval(days => _lookback_days);

  WITH subjects AS (
    SELECT
      profile.user_id,
      profile.blended_pctl_minutes AS neutral_minutes,
      profile.sleep_window_applied,
      coalesce(settings.sensitivity, 'balanced') AS sensitivity,
      CASE coalesce(settings.sensitivity, 'balanced')
        WHEN 'high' THEN _buffer_high
        WHEN 'low' THEN _buffer_low
        ELSE _buffer_balanced
      END AS buffer_minutes,
      round(
        extract(epoch FROM private.silence_threshold(profile.user_id)) / 60
      )::integer AS live_threshold_minutes,
      (
        EXISTS (
          SELECT 1
          FROM public.group_members AS gm
          WHERE gm.user_id = profile.user_id
            AND gm.monitored
            AND gm.status = 'active'
        )
        AND EXISTS (
          SELECT 1
          FROM public.device_state AS ds
          WHERE ds.user_id = profile.user_id
        )
      ) AS is_alertable
    FROM public.account_gap_profiles AS profile
    LEFT JOIN public.user_settings AS settings
      ON settings.user_id = profile.user_id
    WHERE profile.through_date = _date
      AND profile.lookback_days = _lookback_days
      AND profile.shrinkage_k = _shrinkage_k
      AND profile.percentile = _percentile
  ), thresholds AS (
    SELECT
      subjects.*,
      subjects.buffer_minutes
        + greatest(_neutral_floor_minutes, subjects.neutral_minutes)
        AS candidate_floored_minutes,
      greatest(1, subjects.buffer_minutes + subjects.neutral_minutes)
        AS candidate_unfloored_minutes
    FROM subjects
  ), events AS (
    SELECT
      b.user_id,
      date_trunc('minute', b.received_at) AS at_minute
    FROM public.behavior_pings AS b
    JOIN subjects ON subjects.user_id = b.user_id
    WHERE b.ingest_version = 2
      AND abs(extract(epoch FROM (b.received_at - b.at))) <= 300
      AND b.received_at >= _window_starts
      AND b.received_at < _window_ends
    GROUP BY b.user_id, date_trunc('minute', b.received_at)
  ), gaps AS (
    SELECT
      sequenced.user_id,
      sequenced.previous_minute AS starts_at,
      sequenced.at_minute AS ends_at,
      extract(epoch FROM (sequenced.at_minute - sequenced.previous_minute)) / 60.0
        AS raw_minutes
    FROM (
      SELECT
        events.user_id,
        events.at_minute,
        lag(events.at_minute) OVER (
          PARTITION BY events.user_id ORDER BY events.at_minute
        ) AS previous_minute
      FROM events
    ) AS sequenced
    WHERE sequenced.previous_minute IS NOT NULL
  ), suppression AS (
    SELECT
      s.user_id,
      ((day.d + s.sleep_start_local) AT TIME ZONE coalesce(s.timezone, 'UTC'))
        AS starts_at,
      ((
        day.d
        + CASE WHEN s.sleep_end_local <= s.sleep_start_local THEN 1 ELSE 0 END
        + s.sleep_end_local
      ) AT TIME ZONE coalesce(s.timezone, 'UTC'))
        + pg_catalog.make_interval(mins => _post_wake_grace_minutes) AS ends_at
    FROM public.user_settings AS s
    JOIN subjects ON subjects.user_id = s.user_id
    CROSS JOIN LATERAL (
      SELECT generate.value::date AS d
      FROM pg_catalog.generate_series(
        (_window_starts - interval '2 days')::timestamp,
        (_window_ends + interval '1 day')::timestamp,
        interval '1 day'
      ) AS generate(value)
    ) AS day
    WHERE s.sleep_start_local IS NOT NULL
      AND s.sleep_end_local IS NOT NULL
      AND s.sleep_start_local <> s.sleep_end_local
      AND EXISTS (
        SELECT 1
        FROM pg_catalog.pg_timezone_names AS z
        WHERE z.name = coalesce(s.timezone, 'UTC')
      )
  ), fired AS (
    SELECT
      gaps.user_id,
      gaps.starts_at,
      gaps.ends_at,
      gaps.raw_minutes,
      coalesce(live_push.ends_at, live_at.moment) < gaps.ends_at AS fires_live,
      coalesce(floored_push.ends_at, floored_at.moment) < gaps.ends_at
        AS fires_candidate_floored,
      coalesce(unfloored_push.ends_at, unfloored_at.moment) < gaps.ends_at
        AS fires_candidate_unfloored
    FROM gaps
    JOIN thresholds ON thresholds.user_id = gaps.user_id
    CROSS JOIN LATERAL (
      SELECT gaps.starts_at
        + pg_catalog.make_interval(mins => thresholds.live_threshold_minutes)
        AS moment
    ) AS live_at
    CROSS JOIN LATERAL (
      SELECT gaps.starts_at
        + pg_catalog.make_interval(mins => thresholds.candidate_floored_minutes)
        AS moment
    ) AS floored_at
    CROSS JOIN LATERAL (
      SELECT gaps.starts_at
        + pg_catalog.make_interval(mins => thresholds.candidate_unfloored_minutes)
        AS moment
    ) AS unfloored_at
    LEFT JOIN LATERAL (
      SELECT max(suppression.ends_at) AS ends_at
      FROM suppression
      WHERE suppression.user_id = gaps.user_id
        AND suppression.starts_at <= live_at.moment
        AND suppression.ends_at > live_at.moment
    ) AS live_push ON true
    LEFT JOIN LATERAL (
      SELECT max(suppression.ends_at) AS ends_at
      FROM suppression
      WHERE suppression.user_id = gaps.user_id
        AND suppression.starts_at <= floored_at.moment
        AND suppression.ends_at > floored_at.moment
    ) AS floored_push ON true
    LEFT JOIN LATERAL (
      SELECT max(suppression.ends_at) AS ends_at
      FROM suppression
      WHERE suppression.user_id = gaps.user_id
        AND suppression.starts_at <= unfloored_at.moment
        AND suppression.ends_at > unfloored_at.moment
    ) AS unfloored_push ON true
  ), tallied AS (
    SELECT
      fired.user_id,
      count(*)::integer AS gaps_evaluated,
      count(*) FILTER (WHERE fired.fires_live)::integer AS episodes_live,
      count(*) FILTER (WHERE fired.fires_candidate_floored)::integer
        AS episodes_candidate_floored,
      count(*) FILTER (WHERE fired.fires_candidate_unfloored)::integer
        AS episodes_candidate_unfloored,
      count(*) FILTER (
        WHERE fired.fires_candidate_floored AND NOT fired.fires_live
      )::integer AS episodes_candidate_only,
      count(*) FILTER (
        WHERE fired.fires_live AND NOT fired.fires_candidate_floored
      )::integer AS episodes_live_only,
      min(fired.starts_at) FILTER (
        WHERE fired.fires_candidate_floored <> fired.fires_live
      ) AS earliest_divergence_at,
      round(max(fired.raw_minutes) FILTER (
        WHERE fired.fires_candidate_floored AND NOT fired.fires_live
      )::numeric)::integer AS longest_candidate_only_gap_minutes
    FROM fired
    GROUP BY fired.user_id
  ), divergence_example AS (
    SELECT DISTINCT ON (fired.user_id)
      fired.user_id,
      round(fired.raw_minutes::numeric)::integer AS gap_minutes
    FROM fired
    WHERE fired.fires_candidate_floored <> fired.fires_live
    ORDER BY fired.user_id, fired.starts_at
  )
  INSERT INTO public.account_threshold_shadow AS target (
    user_id, through_date, lookback_days, shrinkage_k, percentile,
    computed_at, window_starts_at, window_ends_at,
    is_alertable, sleep_window_applied,
    sensitivity, buffer_minutes, neutral_floor_minutes,
    neutral_minutes, live_threshold_minutes,
    candidate_floored_minutes, candidate_unfloored_minutes,
    gaps_evaluated, episodes_live, episodes_candidate_floored,
    episodes_candidate_unfloored, episodes_candidate_only, episodes_live_only,
    earliest_divergence_at, earliest_divergence_gap_minutes,
    longest_candidate_only_gap_minutes
  )
  SELECT
    thresholds.user_id, _date, _lookback_days, _shrinkage_k, _percentile,
    clock_timestamp(), _window_starts, _window_ends,
    thresholds.is_alertable, thresholds.sleep_window_applied,
    thresholds.sensitivity, thresholds.buffer_minutes, _neutral_floor_minutes,
    thresholds.neutral_minutes, thresholds.live_threshold_minutes,
    thresholds.candidate_floored_minutes, thresholds.candidate_unfloored_minutes,
    coalesce(tallied.gaps_evaluated, 0),
    coalesce(tallied.episodes_live, 0),
    coalesce(tallied.episodes_candidate_floored, 0),
    coalesce(tallied.episodes_candidate_unfloored, 0),
    coalesce(tallied.episodes_candidate_only, 0),
    coalesce(tallied.episodes_live_only, 0),
    tallied.earliest_divergence_at,
    divergence_example.gap_minutes,
    tallied.longest_candidate_only_gap_minutes
  FROM thresholds
  LEFT JOIN tallied ON tallied.user_id = thresholds.user_id
  LEFT JOIN divergence_example ON divergence_example.user_id = thresholds.user_id
  ON CONFLICT (user_id, through_date, lookback_days, shrinkage_k, percentile)
  DO UPDATE SET
    computed_at = EXCLUDED.computed_at,
    window_starts_at = EXCLUDED.window_starts_at,
    window_ends_at = EXCLUDED.window_ends_at,
    is_alertable = EXCLUDED.is_alertable,
    sleep_window_applied = EXCLUDED.sleep_window_applied,
    sensitivity = EXCLUDED.sensitivity,
    buffer_minutes = EXCLUDED.buffer_minutes,
    neutral_floor_minutes = EXCLUDED.neutral_floor_minutes,
    neutral_minutes = EXCLUDED.neutral_minutes,
    live_threshold_minutes = EXCLUDED.live_threshold_minutes,
    candidate_floored_minutes = EXCLUDED.candidate_floored_minutes,
    candidate_unfloored_minutes = EXCLUDED.candidate_unfloored_minutes,
    gaps_evaluated = EXCLUDED.gaps_evaluated,
    episodes_live = EXCLUDED.episodes_live,
    episodes_candidate_floored = EXCLUDED.episodes_candidate_floored,
    episodes_candidate_unfloored = EXCLUDED.episodes_candidate_unfloored,
    episodes_candidate_only = EXCLUDED.episodes_candidate_only,
    episodes_live_only = EXCLUDED.episodes_live_only,
    earliest_divergence_at = EXCLUDED.earliest_divergence_at,
    earliest_divergence_gap_minutes = EXCLUDED.earliest_divergence_gap_minutes,
    longest_candidate_only_gap_minutes = EXCLUDED.longest_candidate_only_gap_minutes;

  GET DIAGNOSTICS _written = ROW_COUNT;

  RETURN jsonb_build_object(
    'through_date', _date,
    'lookback_days', _lookback_days,
    'shrinkage_k', _shrinkage_k,
    'percentile', _percentile,
    'buffer_minutes', jsonb_build_object(
      'high', _buffer_high, 'balanced', _buffer_balanced, 'low', _buffer_low
    ),
    'neutral_floor_minutes', _neutral_floor_minutes,
    'post_wake_grace_minutes', _post_wake_grace_minutes,
    'window_starts_at', _window_starts,
    'window_ends_at', _window_ends,
    'rows_written', _written
  );
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION private.record_account_threshold_shadow(
  date, integer, integer, numeric, integer, integer, integer, integer, integer
) FROM PUBLIC, anon, authenticated, service_role;