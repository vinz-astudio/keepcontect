-- ADR-0037 (amends ADR-0035): learn each account's own observed upper bound of
-- normal silence, with no preset bound of any kind. Record only; see the repo
-- file supabase/migrations/20260804190000_account_normal_upper_bound.sql for
-- the full rationale.

CREATE TABLE public.account_normal_bounds (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  through_date date NOT NULL,
  lookback_days integer NOT NULL CHECK (lookback_days > 0),
  false_alarm_budget numeric(5, 2) NOT NULL CHECK (false_alarm_budget >= 0),

  computed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  window_starts_at timestamptz NOT NULL,
  window_ends_at timestamptz NOT NULL,

  event_count integer NOT NULL CHECK (event_count >= 0),
  gap_count integer NOT NULL CHECK (gap_count >= 0),
  evidence_days integer NOT NULL CHECK (evidence_days >= 0),
  first_event_at timestamptz,
  last_event_at timestamptz,
  sleep_window_applied boolean NOT NULL,

  order_index integer NOT NULL CHECK (order_index >= 1),
  normal_upper_bound_minutes integer CHECK (normal_upper_bound_minutes >= 0),
  largest_gap_minutes integer CHECK (largest_gap_minutes >= 0),
  second_largest_gap_minutes integer CHECK (second_largest_gap_minutes >= 0),

  has_usable_signal boolean NOT NULL,

  sensitivity text NOT NULL,
  buffer_minutes integer NOT NULL CHECK (buffer_minutes >= 0),
  threshold_minutes integer CHECK (threshold_minutes > 0),

  live_threshold_minutes integer NOT NULL CHECK (live_threshold_minutes > 0),
  episodes_new integer NOT NULL CHECK (episodes_new >= 0),
  episodes_live integer NOT NULL CHECK (episodes_live >= 0),

  PRIMARY KEY (user_id, through_date, lookback_days, false_alarm_budget),
  CHECK (window_ends_at > window_starts_at),
  CHECK (has_usable_signal = (normal_upper_bound_minutes IS NOT NULL)),
  CHECK (has_usable_signal = (threshold_minutes IS NOT NULL))
);

ALTER TABLE public.account_normal_bounds ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.account_normal_bounds
FROM PUBLIC, anon, authenticated, service_role;

CREATE INDEX account_normal_bounds_through_date_idx
  ON public.account_normal_bounds (through_date DESC, user_id);

COMMENT ON TABLE public.account_normal_bounds IS
  'ADR-0037. Each account''s own observed upper bound of normal silence, learned continuously with no preset ceiling, floor, template anchor, or cohort shrinkage.';

CREATE FUNCTION private.rebuild_account_normal_bounds(
  _through_date date DEFAULT NULL,
  _lookback_days integer DEFAULT 30,
  _false_alarm_budget numeric DEFAULT 1,
  _buffer_high integer DEFAULT 0,
  _buffer_balanced integer DEFAULT 45,
  _buffer_low integer DEFAULT 90,
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
     OR _false_alarm_budget IS NULL OR _false_alarm_budget < 0
     OR _buffer_high IS NULL OR _buffer_high < 0
     OR _buffer_balanced IS NULL OR _buffer_balanced < 0
     OR _buffer_low IS NULL OR _buffer_low < 0
     OR _post_wake_grace_minutes IS NULL OR _post_wake_grace_minutes < 0 THEN
    RAISE EXCEPTION 'rebuild_account_normal_bounds: invalid parameters';
  END IF;

  _window_ends := (_date + 1)::timestamptz;
  _window_starts := _window_ends - pg_catalog.make_interval(days => _lookback_days);

  WITH events AS (
    SELECT
      b.user_id,
      date_trunc('minute', b.received_at) AS at_minute
    FROM public.behavior_pings AS b
    WHERE b.ingest_version = 2
      AND abs(extract(epoch FROM (b.received_at - b.at))) <= 300
      AND b.received_at >= _window_starts
      AND b.received_at < _window_ends
    GROUP BY b.user_id, date_trunc('minute', b.received_at)
  ), gaps AS (
    SELECT
      sequenced.user_id,
      sequenced.previous_minute AS starts_at,
      sequenced.at_minute AS ends_at
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
  ), escapes AS (
    SELECT
      gaps.user_id,
      greatest(0, extract(epoch FROM (
        coalesce(blocked.starts_at, gaps.ends_at) - gaps.starts_at
      )) / 60.0) AS escape_minutes
    FROM gaps
    LEFT JOIN LATERAL (
      SELECT min(suppression.starts_at) AS starts_at
      FROM suppression
      WHERE suppression.user_id = gaps.user_id
        AND suppression.starts_at <= gaps.ends_at - interval '1 second'
        AND suppression.ends_at > gaps.ends_at - interval '1 second'
    ) AS blocked ON true
  ), ranked AS (
    SELECT
      escapes.user_id,
      escapes.escape_minutes,
      row_number() OVER (
        PARTITION BY escapes.user_id ORDER BY escapes.escape_minutes DESC
      ) AS position
    FROM escapes
  ), evidence AS (
    SELECT
      events.user_id,
      count(*)::integer AS event_count,
      count(DISTINCT events.at_minute::date)::integer AS evidence_days,
      min(events.at_minute) AS first_event_at,
      max(events.at_minute) AS last_event_at
    FROM events
    GROUP BY events.user_id
  ), subjects AS (
    SELECT
      p.id AS user_id,
      coalesce(evidence.event_count, 0) AS event_count,
      coalesce(evidence.evidence_days, 0) AS evidence_days,
      evidence.first_event_at,
      evidence.last_event_at,
      coalesce(settings.sensitivity, 'balanced') AS sensitivity,
      CASE coalesce(settings.sensitivity, 'balanced')
        WHEN 'high' THEN _buffer_high
        WHEN 'low' THEN _buffer_low
        ELSE _buffer_balanced
      END AS buffer_minutes,
      round(
        extract(epoch FROM private.silence_threshold(p.id)) / 60
      )::integer AS live_threshold_minutes,
      EXISTS (
        SELECT 1
        FROM public.user_settings AS s
        WHERE s.user_id = p.id
          AND s.sleep_start_local IS NOT NULL
          AND s.sleep_end_local IS NOT NULL
          AND s.sleep_start_local <> s.sleep_end_local
      ) AS sleep_window_applied,
      (
        SELECT count(*)::integer FROM ranked WHERE ranked.user_id = p.id
      ) AS gap_count,
      greatest(1, 1 + round(_false_alarm_budget
        * coalesce(evidence.evidence_days, 0)::numeric / 30))::integer AS order_index
    FROM public.profiles AS p
    LEFT JOIN evidence ON evidence.user_id = p.id
    LEFT JOIN public.user_settings AS settings ON settings.user_id = p.id
  ), bounded AS (
    SELECT
      subjects.*,
      round(chosen.escape_minutes::numeric)::integer AS normal_upper_bound_minutes,
      round(largest.escape_minutes::numeric)::integer AS largest_gap_minutes,
      round(second.escape_minutes::numeric)::integer AS second_largest_gap_minutes
    FROM subjects
    LEFT JOIN ranked AS chosen
      ON chosen.user_id = subjects.user_id
     AND chosen.position = subjects.order_index
    LEFT JOIN ranked AS largest
      ON largest.user_id = subjects.user_id AND largest.position = 1
    LEFT JOIN ranked AS second
      ON second.user_id = subjects.user_id AND second.position = 2
  ), assembled AS (
    SELECT
      bounded.*,
      CASE
        WHEN bounded.normal_upper_bound_minutes IS NULL THEN NULL
        ELSE greatest(1, bounded.normal_upper_bound_minutes + bounded.buffer_minutes)
      END AS threshold_minutes
    FROM bounded
  )
  INSERT INTO public.account_normal_bounds AS target (
    user_id, through_date, lookback_days, false_alarm_budget,
    computed_at, window_starts_at, window_ends_at,
    event_count, gap_count, evidence_days, first_event_at, last_event_at,
    sleep_window_applied, order_index, normal_upper_bound_minutes,
    largest_gap_minutes, second_largest_gap_minutes, has_usable_signal,
    sensitivity, buffer_minutes, threshold_minutes,
    live_threshold_minutes, episodes_new, episodes_live
  )
  SELECT
    assembled.user_id, _date, _lookback_days, _false_alarm_budget,
    clock_timestamp(), _window_starts, _window_ends,
    assembled.event_count, assembled.gap_count, assembled.evidence_days,
    assembled.first_event_at, assembled.last_event_at,
    assembled.sleep_window_applied, assembled.order_index,
    assembled.normal_upper_bound_minutes,
    assembled.largest_gap_minutes, assembled.second_largest_gap_minutes,
    assembled.threshold_minutes IS NOT NULL,
    assembled.sensitivity, assembled.buffer_minutes, assembled.threshold_minutes,
    assembled.live_threshold_minutes,
    coalesce((
      SELECT count(*)::integer FROM ranked
      WHERE ranked.user_id = assembled.user_id
        AND assembled.threshold_minutes IS NOT NULL
        AND ranked.escape_minutes >= assembled.threshold_minutes
    ), 0),
    coalesce((
      SELECT count(*)::integer FROM ranked
      WHERE ranked.user_id = assembled.user_id
        AND ranked.escape_minutes >= assembled.live_threshold_minutes
    ), 0)
  FROM assembled
  ON CONFLICT (user_id, through_date, lookback_days, false_alarm_budget)
  DO UPDATE SET
    computed_at = EXCLUDED.computed_at,
    window_starts_at = EXCLUDED.window_starts_at,
    window_ends_at = EXCLUDED.window_ends_at,
    event_count = EXCLUDED.event_count,
    gap_count = EXCLUDED.gap_count,
    evidence_days = EXCLUDED.evidence_days,
    first_event_at = EXCLUDED.first_event_at,
    last_event_at = EXCLUDED.last_event_at,
    sleep_window_applied = EXCLUDED.sleep_window_applied,
    order_index = EXCLUDED.order_index,
    normal_upper_bound_minutes = EXCLUDED.normal_upper_bound_minutes,
    largest_gap_minutes = EXCLUDED.largest_gap_minutes,
    second_largest_gap_minutes = EXCLUDED.second_largest_gap_minutes,
    has_usable_signal = EXCLUDED.has_usable_signal,
    sensitivity = EXCLUDED.sensitivity,
    buffer_minutes = EXCLUDED.buffer_minutes,
    threshold_minutes = EXCLUDED.threshold_minutes,
    live_threshold_minutes = EXCLUDED.live_threshold_minutes,
    episodes_new = EXCLUDED.episodes_new,
    episodes_live = EXCLUDED.episodes_live;

  GET DIAGNOSTICS _written = ROW_COUNT;

  RETURN jsonb_build_object(
    'through_date', _date,
    'lookback_days', _lookback_days,
    'false_alarm_budget', _false_alarm_budget,
    'post_wake_grace_minutes', _post_wake_grace_minutes,
    'window_starts_at', _window_starts,
    'window_ends_at', _window_ends,
    'rows_written', _written
  );
END;
$$;

REVOKE ALL PRIVILEGES ON FUNCTION private.rebuild_account_normal_bounds(
  date, integer, numeric, integer, integer, integer, integer
) FROM PUBLIC, anon, authenticated, service_role;