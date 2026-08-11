-- ADR-0037 (amends ADR-0035): learn each account's own observed upper bound of
-- normal silence, with no preset bound of any kind.
--
-- Why this replaces the p95 profile
--   p95 is not an upper bound. Its definition is "five percent of this
--   account's ordinary silences cross this line", so on a dense account it
--   fires tens of times a month by construction. Production 2026-08-04: of the
--   180 real silence alerts since 07-20, 12 would have fired had each account
--   been measured against its own upper bound instead.
--
-- The quantity being learned
--   For each silence, `escape_minutes` is the largest threshold that would
--   still have raised an alert on it: the distance from the silence's start to
--   the last instant before it ended at which the detector was actually allowed
--   to act. Sleep and its post-wake grace are baked in, because they are what
--   decides whether the detector could act, not a separate correction.
--
--   Setting the threshold above an account's i-th largest escape_minutes means
--   at most i-1 of its silences would have alerted. That makes the tolerated
--   false-alarm rate the only policy input, and the account's own history the
--   only data input.
--
-- What is deliberately absent
--   No ceiling. No floor. No template anchor. No cohort shrinkage. No sample
--   threshold that flips a profile between valid and invalid. No coverage
--   lease. If any constant reappears in this file bounding what an account may
--   be, it is a defect: ADR-0037 exists because three such constants (the
--   90/135/180 template, the 600-minute ceiling, a proposed 90-minute floor)
--   between them ensured nothing learned ever reached a decision.
--
-- Thin evidence widens, never tightens
--   The order index scales with how many days of evidence exist, so an account
--   we have barely observed sits further out rather than closer in. We do not
--   pretend to know someone's upper bound before we have seen their long days.
--   Skipping the largest gap once evidence allows also means one outage cannot
--   teach the model that an account is slow.
--
-- Still record-only. private.silence_threshold is not touched here.

CREATE TABLE public.account_normal_bounds (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  through_date date NOT NULL,
  lookback_days integer NOT NULL CHECK (lookback_days > 0),
  -- Tolerated false alarms per 30 days. A policy input about us, not an
  -- assumption about the user.
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

  -- False when the account has not produced enough silences to have an upper
  -- bound at this order index. We say so instead of inventing a number.
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
    -- Every device on the account, one stream, deduplicated to the minute.
    -- The live detector's own predicate and nothing else: no coverage lease,
    -- no observation attestation.
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
    -- The window in which private.sleep_relaxed forbids the detector to act.
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
    -- The largest threshold that would still have alerted on this silence.
    -- If the silence ended while the detector was suppressed, the last instant
    -- it could have acted is the start of that suppression window.
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
      -- Thin evidence pulls the index down, which pushes the bound outward.
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
      -- The entire assembly. Nothing clamps it from either side.
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
        AND ranked.escape_minutes > assembled.threshold_minutes
    ), 0),
    coalesce((
      SELECT count(*)::integer FROM ranked
      WHERE ranked.user_id = assembled.user_id
        AND ranked.escape_minutes > assembled.live_threshold_minutes
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

-- ---------------------------------------------------------------------------
-- ADR-0037 step 4: the live threshold reads the learned bound.
--
-- Before: greatest(90/135/180 template, least(600, p95 from frozen July data
-- + buffer)). Six of nine real accounts had had no new evidence admitted since
-- 2026-07-19 and were days from silently reverting to the template outright.
-- After: the account's own i-th largest silence plus its sensitivity buffer,
-- recomputed daily from every device it reports on.
--
-- The buffer is applied here rather than baked into the stored bound, so a
-- sensitivity change takes effect immediately instead of at the next rebuild.
--
-- NULL is a real answer: an account with no usable evidence gets no silence
-- judgement rather than a fabricated one. The raise loop's comparison then
-- yields NULL and no alert is raised.
--
-- Display debt: my_routine_status and get_group_activity pass this straight to
-- the client, so threshold_seconds / threshold_hours can now be null. The
-- client multiplies that by 1000 and would render a zero threshold. Guarding
-- that display is a required follow-up.
CREATE OR REPLACE FUNCTION private.silence_threshold(_user_id uuid)
RETURNS interval
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
SET TimeZone = 'UTC'
AS $$
DECLARE
  _bound_minutes integer;
  _sensitivity text;
  _buffer_minutes integer;
BEGIN
  -- Deliberately no staleness cliff: if a rebuild is missed the previous
  -- day's bound stands, because a threshold that expires into a template is
  -- the exact failure ADR-0037 exists to remove.
  SELECT bounds.normal_upper_bound_minutes
    INTO _bound_minutes
  FROM public.account_normal_bounds AS bounds
  WHERE bounds.user_id = _user_id
    AND bounds.has_usable_signal
    AND bounds.lookback_days = 30
    AND bounds.false_alarm_budget = 1
  ORDER BY bounds.through_date DESC, bounds.computed_at DESC
  LIMIT 1;

  IF _bound_minutes IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT settings.sensitivity
    INTO _sensitivity
  FROM public.user_settings AS settings
  WHERE settings.user_id = _user_id;

  _buffer_minutes := CASE coalesce(_sensitivity, 'balanced')
    WHEN 'high' THEN 0
    WHEN 'sensitive' THEN 0
    WHEN 'low' THEN 90
    WHEN 'relaxed' THEN 90
    ELSE 45
  END;

  RETURN pg_catalog.make_interval(mins => _bound_minutes + _buffer_minutes);
END;
$$;

REVOKE EXECUTE ON FUNCTION private.silence_threshold(uuid)
FROM PUBLIC, anon, authenticated, service_role;

-- The nightly job must maintain the table the live threshold reads, or the
-- bound freezes. NOT YET APPLIED IN PRODUCTION: the cron change was blocked by
-- the operator permission gate on 2026-08-04 and is pending authorisation.
DO $schedule$
BEGIN
  PERFORM cron.schedule(
    'account-shadow-cycle-v1',
    '37 2 * * *',
    $cron$ SELECT private.rebuild_account_normal_bounds(); $cron$
  );
END;
$schedule$;
