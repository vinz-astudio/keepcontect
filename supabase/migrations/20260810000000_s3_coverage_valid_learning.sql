-- S3-C2 · Coverage-valid learning for the account normal bound (ADR-0039).
--
-- Why this exists
-- ---------------
-- The learned upper bound is supposed to be *this person's own normal silence*.
-- The previous worker learned from every gap between pings. That means a
-- stretch where the phone was asleep, the permission was revoked, the network
-- was down, the collector had stopped, or the signal came from somebody else's
-- hand all counted as "normal quiet". Each such stretch widens the very
-- threshold that is supposed to notice when this person goes missing.
--
-- Run long enough, that is a person being trained into never being missed. The
-- system would be spending evidence it never had.
--
-- Four gates, each with a nameable reason so a skipped sample can be explained:
--
--   1. Coverage      — the gap must lie entirely inside an observation interval
--                      whose activity, intervention and sleep-context states are
--                      all 'valid'. Partial overlap does not partially count.
--   2. Source        — manual check-in, Shortcut, Guardian action and replayed
--                      history may never train. They prove somebody acted, or
--                      that history was re-imported; never that this person was
--                      observably living an ordinary day.
--   3. Repeat        — an exceptional long gap may only set the bound when at
--                      least two independent comparable dates support it. A
--                      single extreme never rewrites normal.
--   4. Outcome       — with nothing qualifying, the row records an absence:
--                      has_usable_signal false and a NULL bound. Never a
--                      template, never a zero.
--
-- Note on activation: coverage intervals are produced by the adaptive shadow
-- line, which ADR-0038 leaves default-off. On an environment where coverage
-- collection has never been enabled there are no intervals, so this worker
-- correctly learns nothing and every account keeps a NULL bound. That is the
-- accepted outcome — no healthy coverage means Unknown, and Unknown does not
-- train — not a defect to engineer around.
--
-- Append-only: no historical migration is edited. Sensitivity buffers, the
-- false-alarm budget, the sleep suppression window and the per-subject failure
-- isolation loop are all unchanged.

CREATE OR REPLACE FUNCTION private.rebuild_account_normal_bounds(
  _through_date date DEFAULT NULL::date,
  _lookback_days integer DEFAULT 30,
  _false_alarm_budget numeric DEFAULT 1,
  _buffer_high integer DEFAULT 0,
  _buffer_balanced integer DEFAULT 45,
  _buffer_low integer DEFAULT 90,
  _post_wake_grace_minutes integer DEFAULT 120
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
SET "TimeZone" TO 'UTC'
AS $function$
DECLARE
  _date date := coalesce(_through_date, (now() AT TIME ZONE 'UTC')::date);
  _window_ends timestamptz;
  _window_starts timestamptz;
  _written integer := 0;
  _skipped integer := 0;
  _subject record;
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

  CREATE TEMP TABLE _assembled ON COMMIT DROP AS
  WITH events AS (
    SELECT
      b.user_id,
      date_trunc('minute', b.received_at) AS at_minute
    FROM public.behavior_pings AS b
    WHERE b.ingest_version = 2
      -- Gate 2, replay: a re-imported or replayed history arrives long after
      -- the moment it claims to describe. Only evidence the server watched
      -- arrive live may train.
      AND abs(extract(epoch FROM (b.received_at - b.at))) <= 300
      -- Gate 2, foreign origin: a manual check-in is a person answering a
      -- prompt, a Shortcut is an automation, and a Guardian acting on someone's
      -- behalf is an external confirmation. None of them is evidence that this
      -- person was observably living an ordinary day, so none may train.
      AND b.kind <> 'manual_checkin'
      AND (b.source IS NULL OR b.source NOT IN ('shortcut', 'manual'))
      AND b.received_at >= _window_starts
      AND b.received_at < _window_ends
    GROUP BY b.user_id, date_trunc('minute', b.received_at)
  ), coverage AS (
    -- Gate 1: only stretches we could actually observe. All three axes must be
    -- 'valid' — a collector that ran but could not reach the person is not
    -- coverage, and neither is one whose sleep context was untrustworthy.
    SELECT
      i.user_id,
      i.starts_at,
      i.ends_at
    FROM public.alert_observation_coverage_intervals AS i
    WHERE i.activity_coverage_state = 'valid'
      AND i.intervention_coverage_state = 'valid'
      AND i.sleep_context_state = 'valid'
      AND i.ends_at > _window_starts
      AND i.starts_at < _window_ends
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
      -- Containment, not overlap. Half a gap inside coverage tells us nothing
      -- about the other half, and the other half is exactly where the person
      -- could have been missed.
      AND EXISTS (
        SELECT 1
        FROM coverage AS c
        WHERE c.user_id = sequenced.user_id
          AND c.starts_at <= sequenced.previous_minute
          AND c.ends_at >= sequenced.at_minute
      )
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
      )) / 60.0) AS escape_minutes,
      -- Independence is judged on the subject's own calendar. One long night
      -- must not be splittable into two samples by crossing UTC midnight.
      ((gaps.ends_at AT TIME ZONE coalesce(zone.timezone, 'UTC'))::date)
        AS observation_date
    FROM gaps
    LEFT JOIN public.user_settings AS zone ON zone.user_id = gaps.user_id
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
      escapes.observation_date,
      row_number() OVER (
        PARTITION BY escapes.user_id ORDER BY escapes.escape_minutes DESC
      ) AS position
    FROM escapes
  ), supported AS (
    -- Gate 3. A candidate is exceptional when it towers over the rest of this
    -- account's own silences — measured against the other gaps, not including
    -- itself, so one outlier cannot certify itself as typical. An exceptional
    -- long silence may only become the normal bound when at least two
    -- independent comparable dates carry a similar coverage-valid gap; one dead
    -- battery or one unusual weekend is not a new normal.
    --
    -- With no other gap to compare against there is no distribution and nothing
    -- can be called exceptional: a lone observed silence is simply the only
    -- thing we have seen, and it is used as-is.
    SELECT
      r.user_id,
      r.position,
      r.escape_minutes,
      (
        other.median_minutes IS NOT NULL
        AND r.escape_minutes > 2 * other.median_minutes
        AND r.escape_minutes > 0
      ) AS is_exceptional,
      (
        SELECT count(DISTINCT peer.observation_date)
        FROM ranked AS peer
        WHERE peer.user_id = r.user_id
          AND peer.escape_minutes >= r.escape_minutes * 0.8
      ) AS comparable_dates
    FROM ranked AS r
    CROSS JOIN LATERAL (
      SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY o.escape_minutes)
        AS median_minutes
      FROM ranked AS o
      WHERE o.user_id = r.user_id
        AND o.position <> r.position
    ) AS other
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
      -- Two terms. The budget term grows the index as evidence accumulates.
      -- The outage guard keeps the index at 2 or more as soon as there are
      -- enough silences for a second-largest to exist, so one dead battery or
      -- one weekend without signal can never become an account's upper bound.
      -- Ten is a guard against a single outlier, not a bound on the account.
      greatest(
        CASE
          WHEN (SELECT count(*) FROM ranked WHERE ranked.user_id = p.id) >= 10
          THEN 2 ELSE 1
        END,
        1 + round(_false_alarm_budget
          * coalesce(evidence.evidence_days, 0)::numeric / 30)
      )::integer AS order_index
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
    -- Start at the account's order index and walk toward smaller values until
    -- a candidate is either ordinary or carries its repeat evidence. Failing
    -- the repeat gate can only make the bound smaller, never larger, so a
    -- missing second date can never widen anyone's threshold.
    LEFT JOIN LATERAL (
      SELECT s.escape_minutes
      FROM supported AS s
      WHERE s.user_id = subjects.user_id
        AND s.position >= subjects.order_index
        AND (s.is_exceptional IS NOT TRUE OR s.comparable_dates >= 2)
      ORDER BY s.position
      LIMIT 1
    ) AS chosen ON true
    LEFT JOIN ranked AS largest
      ON largest.user_id = subjects.user_id AND largest.position = 1
    LEFT JOIN ranked AS second
      ON second.user_id = subjects.user_id AND second.position = 2
  )
  SELECT
    bounded.*,
    CASE
      WHEN bounded.normal_upper_bound_minutes IS NULL THEN NULL
      ELSE greatest(1, bounded.normal_upper_bound_minutes + bounded.buffer_minutes)
    END AS threshold_minutes,
    coalesce((
      SELECT count(*)::integer FROM ranked
      WHERE ranked.user_id = bounded.user_id
        AND bounded.normal_upper_bound_minutes IS NOT NULL
        AND ranked.escape_minutes >
            greatest(1, bounded.normal_upper_bound_minutes + bounded.buffer_minutes)
    ), 0) AS episodes_new
  FROM bounded;

  -- One account at a time from here. A subject that cannot be written is
  -- recorded as skipped and the loop continues; it can no longer take the
  -- other accounts down with it.
  FOR _subject IN SELECT * FROM _assembled LOOP
    BEGIN
      INSERT INTO public.account_normal_bounds AS target (
        user_id, through_date, lookback_days, false_alarm_budget,
        computed_at, window_starts_at, window_ends_at,
        event_count, gap_count, evidence_days, first_event_at, last_event_at,
        sleep_window_applied, order_index, normal_upper_bound_minutes,
        largest_gap_minutes, second_largest_gap_minutes, has_usable_signal,
        sensitivity, buffer_minutes, threshold_minutes, episodes_new
      )
      VALUES (
        _subject.user_id, _date, _lookback_days, _false_alarm_budget,
        clock_timestamp(), _window_starts, _window_ends,
        _subject.event_count, _subject.gap_count, _subject.evidence_days,
        _subject.first_event_at, _subject.last_event_at,
        _subject.sleep_window_applied, _subject.order_index,
        _subject.normal_upper_bound_minutes,
        _subject.largest_gap_minutes, _subject.second_largest_gap_minutes,
        -- Gate 4. ADR-0037: an account with no qualifying evidence gets a
        -- recorded absence, not an invented number. threshold_minutes stays
        -- NULL and this flag says why.
        _subject.threshold_minutes IS NOT NULL,
        _subject.sensitivity, _subject.buffer_minutes, _subject.threshold_minutes,
        _subject.episodes_new
      )
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
        episodes_new = EXCLUDED.episodes_new;

      _written := _written + 1;
    EXCEPTION WHEN OTHERS THEN
      _skipped := _skipped + 1;
      INSERT INTO private.job_failures (job_name, subject_id, sqlstate, message, context)
      VALUES ('rebuild_account_normal_bounds', _subject.user_id, SQLSTATE, SQLERRM,
              format('through_date=%s lookback_days=%s', _date, _lookback_days));
    END;
  END LOOP;

  DROP TABLE IF EXISTS _assembled;

  RETURN jsonb_build_object(
    'through_date', _date,
    'lookback_days', _lookback_days,
    'false_alarm_budget', _false_alarm_budget,
    'post_wake_grace_minutes', _post_wake_grace_minutes,
    'window_starts_at', _window_starts,
    'window_ends_at', _window_ends,
    'rows_written', _written,
    'subjects_skipped', _skipped
  );
END;
$function$;
