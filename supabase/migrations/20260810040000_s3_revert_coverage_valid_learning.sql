-- ADR-0040 修订一 · Revert S3-C2 (coverage-valid learning).
--
-- 20260810000000_s3_coverage_valid_learning.sql 只让「被合格覆盖区间完整包含」的
-- 静默参与学习。部署后 2026-08-10 立刻误报:覆盖是从**活动信号**推导的,而活动只在
-- 用户动手机时出现,于是系统只在人活跃时才算自己「在看」,学到的安静全是短的。
-- 一个账户当月覆盖率 7.6%、合格 gap 仅 14 个、最长 15 分钟 —— 阈值被压到 14 分钟,
-- process_escalations 一分钟内就开了 silence 告警(stage=self,0 通知 0 推送)。
--
-- 生产已于 2026-08-10 手工还原并从 ledger 移除该条;本迁移把同一还原写进仓库,
-- 使「重放全部迁移」得到的库与生产一致 —— 否则下一次 db push 会让 C2 自己回来。
--
-- 函数体逐字取自 20260808230000_per_subject_failure_isolation.sql,不做任何改动。
-- C2 的四道闸门本身没有被否定,被否定的是它的覆盖来源;重建条件见
-- Brain 的 ADR-0040 修订一(守望者心跳 + 四态覆盖)。

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
