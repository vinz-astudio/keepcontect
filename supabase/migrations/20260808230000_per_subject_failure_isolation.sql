-- One account with no evidence stopped every account's nightly recalculation
-- for four nights, and nothing said so.
--
-- private.rebuild_account_normal_bounds failed on 2026-08-05, -06, -07 and -08
-- with:
--   null value in column "live_threshold_minutes" of relation
--   "account_normal_bounds" violates not-null constraint
--
-- Two separate defects produced that, and only one of them is about a column.
--
-- 1. live_threshold_minutes and episodes_live are left over from the ADR-0037
--    parallel run, when the new bound was computed beside the old threshold so
--    the two could be compared. The old threshold retired on 2026-08-04 when
--    20260804135728 pointed private.silence_threshold at account_normal_bounds.
--    From that moment the "live" column asked private.silence_threshold what it
--    thought - and private.silence_threshold reads the very table being
--    rebuilt. The comparison had become the table against itself, so
--    episodes_live has been meaningless since the switch, and for an account
--    with no usable signal silence_threshold correctly answers NULL, which the
--    NOT NULL constraint then rejected. The column contradicted ADR-0037's
--    "no evidence, no invented threshold" directly. Both columns are dropped
--    rather than made nullable: they measure a comparison that no longer
--    exists. account_threshold_shadow keeps its own same-named columns, which
--    are still a real shadow and are untouched here.
--
-- 2. The rebuild was a single INSERT ... SELECT covering every account, so
--    Postgres aborted the whole statement on one bad row. That is the defect
--    that matters: fixing only the column would leave the next unforeseen
--    per-account condition free to zero out everybody again. A per-account
--    calculation must degrade per account - if one person cannot be computed,
--    that person gets recorded as uncomputable and everyone else still gets
--    their number.
--
-- The same all-or-nothing shape exists in the other scheduled functions. This
-- migration also isolates run_daily_aggregations. process_escalations and
-- process_checkin_tasks carry it too and are handled separately, because they
-- are the live alert path and their change belongs with its own tests.
--
-- private.apply_liveness_side_effects was checked and is not in this class: it
-- takes a single _user_id, and its caller private.insert_behavior_ping already
-- has an exception handler.

-- 1. Where a skipped subject is recorded ------------------------------------
-- Without this the isolation would be worse than the crash: work would be
-- quietly dropped per account with nothing to show for it. A caught failure
-- must leave a trace, or "keep going" is just a slower way to fail silently.

create table if not exists private.job_failures (
  id           bigint generated always as identity primary key,
  job_name     text        not null,
  subject_id   uuid,
  failed_at    timestamptz not null default now(),
  sqlstate     text,
  message      text,
  context      text
);

create index if not exists job_failures_job_time_idx
  on private.job_failures (job_name, failed_at desc);

create index if not exists job_failures_subject_idx
  on private.job_failures (subject_id, failed_at desc)
  where subject_id is not null;

alter table private.job_failures enable row level security;

-- No policy is created on purpose. The private schema is not exposed through
-- PostgREST and nothing outside SECURITY DEFINER functions may read this.

comment on table private.job_failures is
  'One row per subject a scheduled job could not process. Written from the exception handler of an isolated loop so that skipping a subject is visible instead of silent.';

-- 2. Drop the vestigial comparison columns ----------------------------------
-- Verified before dropping: only private.rebuild_account_normal_bounds reads
-- them on this table, no client or test code references them, and
-- public.account_threshold_shadow's identically named columns are a different
-- table and stay.

alter table public.account_normal_bounds
  drop column if exists live_threshold_minutes,
  drop column if exists episodes_live;

-- 3. The nightly rebuild, isolated per account ------------------------------
-- The expensive part - reading every qualifying ping in the window and ranking
-- each account's silences - still runs once as a set, because doing it per
-- account would read the same table eleven times. Only the write is per
-- account, which is where a single bad row could previously take out the run.

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
    LEFT JOIN ranked AS chosen
      ON chosen.user_id = subjects.user_id
     AND chosen.position = subjects.order_index
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
        -- ADR-0037: an account with no evidence gets a recorded absence, not an
        -- invented number. threshold_minutes stays NULL and this flag says why.
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

-- 4. Daily aggregation, isolated per account --------------------------------
-- Same shape, smaller blast radius: one account whose aggregation raises would
-- previously stop every later account in the loop from being aggregated at all.

CREATE OR REPLACE FUNCTION public.run_daily_aggregations()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  _user record;
  _timezone text;
  _yesterday date;
BEGIN
  FOR _user IN SELECT id FROM auth.users LOOP
    BEGIN
      SELECT timezone INTO _timezone FROM public.user_settings WHERE user_id = _user.id;
      _timezone := coalesce(_timezone, 'UTC');

      _yesterday := (now() at time zone _timezone)::date - 1;

      PERFORM private.aggregate_user_daily_activity(_user.id, _yesterday);
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO private.job_failures (job_name, subject_id, sqlstate, message, context)
      VALUES ('run_daily_aggregations', _user.id, SQLSTATE, SQLERRM,
              format('timezone=%s', coalesce(_timezone, 'UTC')));
    END;
  END LOOP;
END;
$function$;
