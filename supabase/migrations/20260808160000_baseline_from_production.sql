-- Keep Contact database baseline, taken from production byekgmqyqlftgoveqnku
-- on 2026-08-08 under ADR-0038.
--
-- Why this file exists: migrations had historically been applied through the
-- Supabase dashboard and MCP apply_migration, each of which mints a fresh
-- timestamp instead of using the file's own version. The same work ended up
-- recorded under two ids, and work applied without a file was recorded under an
-- id the repository never knew. supabase db push became unusable in both
-- directions, and 18 applied migrations had no file at all - so the migration
-- directory could not rebuild production no matter how the ledger was repaired.
--
-- Rather than reconcile two incomplete records, production itself became the
-- starting point. Everything before this file is history, not a build path:
--   supabase/migrations-archive/as-applied/  the SQL that actually ran, recovered
--                                            from the ledger and verified against
--                                            md5 computed by the database
--                                            (fingerprint f4a7ca762ab1017e565bd827db8a8628)
--   supabase/migrations-archive/from-repo/   the 99 files as the repository held them
--   supabase/migrations-archive/ledger-backup-2026-08-08.sql
--                                            the full pre-reset ledger, 103 rows
--
-- From here on every database change is a file in supabase/migrations applied
-- with supabase db push. The dashboard and MCP apply_migration are no longer an
-- accepted route: they are what caused this.
--
-- EDIT THIS FILE WITH CARE. The dumped section carries CRLF inside function
-- bodies because that is how production stores them. An editor that normalises
-- line endings will silently make all 111 functions differ from production, and
-- nothing will fail - supabase db diff --linked is the only thing that notices.
--
-- Assembled from four parts, because a schema dump alone is not the database:
--   1. extensions, in the schemas production actually uses
--   2. pg_dump --schema-only for public and private
--   3. realtime publication membership and the pg_cron jobs, which are rows
--      rather than schema and which no dump carries
--   4. the privileges production took back, which a dump cannot express because
--      it records grants and never revokes

-- 1. Extensions ------------------------------------------------------------
-- Schemas below are the ones production actually uses, confirmed against
-- pg_extension. pg_net sits in public and pg_cron in pg_catalog rather than in
-- extensions. supabase_vault is provisioned by the platform and is not declared
-- here.

create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_stat_statements with schema extensions;
create extension if not exists pg_net with schema public;
create extension if not exists pg_cron with schema pg_catalog;

-- 2. Schema ----------------------------------------------------------------
-- Verbatim bytes from: supabase db dump --linked --schema public,private

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE SCHEMA IF NOT EXISTS "private";


ALTER SCHEMA "private" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."aggregate_user_daily_activity"("_user_id" "uuid", "_date" "date") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  _timezone text;
  _hourly_density integer[] := array_fill(0, array[24]);
  _ping record;
  _hour int;
BEGIN
  SELECT timezone INTO _timezone FROM public.user_settings WHERE user_id = _user_id;
  _timezone := coalesce(_timezone, 'UTC');

  -- Count pings using only canonical evidence (ingest_version = 2)
  FOR _ping IN
    SELECT extract(hour from at at time zone _timezone)::int as hr
    FROM public.behavior_pings
    WHERE user_id = _user_id
      AND ingest_version = 2
      AND (at at time zone _timezone)::date = _date
  LOOP
    _hour := _ping.hr;
    IF _hour >= 0 AND _hour <= 23 THEN
      _hourly_density[_hour + 1] := _hourly_density[_hour + 1] + 1;
    END IF;
  END LOOP;

  INSERT INTO public.daily_activity_aggregates (user_id, date, hourly_density)
  VALUES (_user_id, _date, _hourly_density)
  ON CONFLICT (user_id, date) DO UPDATE
    SET hourly_density = excluded.hourly_density;
END;
$$;


ALTER FUNCTION "private"."aggregate_user_daily_activity"("_user_id" "uuid", "_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."alert_candidate_config_is_valid"("_config" "jsonb") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    SET "DateStyle" TO 'ISO, YMD'
    SET "extra_float_digits" TO '3'
    AS $_$
  SELECT
    jsonb_typeof(_config) = 'object'
    AND _config ?& ARRAY[
      'sessionization', 'context', 'personal', 'cohort',
      'sensitivity_buffers_minutes', 'candidate_bounds', 'sleep_compensation',
      'evaluator', 'emergency'
    ]
    AND jsonb_typeof(_config -> 'sessionization') = 'object'
    AND (_config -> 'sessionization') ?& ARRAY[
      'gap_minutes', 'per_user_day_gap_cap',
      'training_horizon_days', 'intervention_window_minutes'
    ]
    AND jsonb_typeof(_config #> '{sessionization,gap_minutes}') = 'number'
    AND (_config #>> '{sessionization,gap_minutes}')::numeric > 0
    AND jsonb_typeof(_config #> '{sessionization,per_user_day_gap_cap}') = 'number'
    AND (_config #>> '{sessionization,per_user_day_gap_cap}')::numeric > 0
    AND jsonb_typeof(_config #> '{sessionization,training_horizon_days}') = 'number'
    AND (_config #>> '{sessionization,training_horizon_days}')::numeric > 0
    AND (_config #>> '{sessionization,training_horizon_days}')::numeric
      = trunc((_config #>> '{sessionization,training_horizon_days}')::numeric)
    AND jsonb_typeof(_config #> '{sessionization,intervention_window_minutes}') = 'number'
    AND (_config #>> '{sessionization,intervention_window_minutes}')::numeric >= 0
    AND (_config #>> '{sessionization,intervention_window_minutes}')::numeric
      = trunc((_config #>> '{sessionization,intervention_window_minutes}')::numeric)
    AND jsonb_typeof(_config -> 'context') = 'object'
    AND (_config -> 'context') ?& ARRAY[
      'definition_version', 'day_partition', 'hour_bucket_minutes'
    ]
    AND jsonb_typeof(_config #> '{context,definition_version}') = 'string'
    AND length(trim(_config #>> '{context,definition_version}')) > 0
    AND jsonb_typeof(_config #> '{context,day_partition}') = 'string'
    AND _config #>> '{context,day_partition}' IN ('all_days', 'weekday_weekend')
    AND jsonb_typeof(_config #> '{context,hour_bucket_minutes}') = 'number'
    AND (_config #>> '{context,hour_bucket_minutes}')::numeric > 0
    AND (_config #>> '{context,hour_bucket_minutes}')::numeric
      = trunc((_config #>> '{context,hour_bucket_minutes}')::numeric)
    AND mod(1440, (_config #>> '{context,hour_bucket_minutes}')::integer) = 0
    AND jsonb_typeof(_config -> 'personal') = 'object'
    AND (_config -> 'personal') ?& ARRAY[
      'min_samples', 'min_support_dates', 'min_span_days', 'max_age_days',
      'min_confidence', 'confidence_formula_version'
    ]
    AND jsonb_typeof(_config #> '{personal,min_samples}') = 'number'
    AND (_config #>> '{personal,min_samples}')::numeric > 0
    AND (_config #>> '{personal,min_samples}')::numeric
      = trunc((_config #>> '{personal,min_samples}')::numeric)
    AND jsonb_typeof(_config #> '{personal,min_support_dates}') = 'number'
    AND (_config #>> '{personal,min_support_dates}')::numeric > 0
    AND (_config #>> '{personal,min_support_dates}')::numeric
      = trunc((_config #>> '{personal,min_support_dates}')::numeric)
    AND jsonb_typeof(_config #> '{personal,min_span_days}') = 'number'
    AND (_config #>> '{personal,min_span_days}')::numeric > 0
    AND (_config #>> '{personal,min_span_days}')::numeric
      = trunc((_config #>> '{personal,min_span_days}')::numeric)
    AND jsonb_typeof(_config #> '{personal,max_age_days}') = 'number'
    AND (_config #>> '{personal,max_age_days}')::numeric > 0
    AND (_config #>> '{personal,max_age_days}')::numeric
      = trunc((_config #>> '{personal,max_age_days}')::numeric)
    AND jsonb_typeof(_config #> '{personal,min_confidence}') = 'number'
    AND (_config #>> '{personal,min_confidence}')::numeric > 0
    AND (_config #>> '{personal,min_confidence}')::numeric <= 1
    AND jsonb_typeof(_config #> '{personal,confidence_formula_version}') = 'string'
    AND _config #>> '{personal,confidence_formula_version}' = 'support_ratio_v1'
    AND jsonb_typeof(_config -> 'cohort') = 'object'
    AND (_config -> 'cohort') ?& ARRAY[
      'min_contributors', 'min_support_dates', 'min_span_days', 'max_age_days',
      'min_confidence', 'contribution_floor_minutes', 'contribution_ceiling_minutes',
      'confidence_formula_version', 'algorithm', 'trim_fraction'
    ]
    AND jsonb_typeof(_config #> '{cohort,min_contributors}') = 'number'
    AND (_config #>> '{cohort,min_contributors}')::numeric > 0
    AND (_config #>> '{cohort,min_contributors}')::numeric
      = trunc((_config #>> '{cohort,min_contributors}')::numeric)
    AND jsonb_typeof(_config #> '{cohort,min_support_dates}') = 'number'
    AND (_config #>> '{cohort,min_support_dates}')::numeric > 0
    AND (_config #>> '{cohort,min_support_dates}')::numeric
      = trunc((_config #>> '{cohort,min_support_dates}')::numeric)
    AND jsonb_typeof(_config #> '{cohort,min_span_days}') = 'number'
    AND (_config #>> '{cohort,min_span_days}')::numeric > 0
    AND (_config #>> '{cohort,min_span_days}')::numeric
      = trunc((_config #>> '{cohort,min_span_days}')::numeric)
    AND jsonb_typeof(_config #> '{cohort,max_age_days}') = 'number'
    AND (_config #>> '{cohort,max_age_days}')::numeric > 0
    AND (_config #>> '{cohort,max_age_days}')::numeric
      = trunc((_config #>> '{cohort,max_age_days}')::numeric)
    AND jsonb_typeof(_config #> '{cohort,min_confidence}') = 'number'
    AND (_config #>> '{cohort,min_confidence}')::numeric > 0
    AND (_config #>> '{cohort,min_confidence}')::numeric <= 1
    AND jsonb_typeof(_config #> '{cohort,contribution_floor_minutes}') = 'number'
    AND (_config #>> '{cohort,contribution_floor_minutes}')::numeric > 0
    AND (_config #>> '{cohort,contribution_floor_minutes}')::numeric
      = trunc((_config #>> '{cohort,contribution_floor_minutes}')::numeric)
    AND jsonb_typeof(_config #> '{cohort,contribution_ceiling_minutes}') = 'number'
    AND (_config #>> '{cohort,contribution_ceiling_minutes}')::numeric > 0
    AND (_config #>> '{cohort,contribution_ceiling_minutes}')::numeric
      = trunc((_config #>> '{cohort,contribution_ceiling_minutes}')::numeric)
    AND (_config #>> '{cohort,contribution_ceiling_minutes}')::numeric
      >= (_config #>> '{cohort,contribution_floor_minutes}')::numeric
    AND jsonb_typeof(_config #> '{cohort,confidence_formula_version}') = 'string'
    AND _config #>> '{cohort,confidence_formula_version}' = 'cohort_support_min_v1'
    AND jsonb_typeof(_config #> '{cohort,algorithm}') = 'string'
    AND _config #>> '{cohort,algorithm}' IN ('weighted_median', 'trimmed_mean')
    AND jsonb_typeof(_config #> '{cohort,trim_fraction}') = 'number'
    AND (_config #>> '{cohort,trim_fraction}')::numeric >= 0
    AND (_config #>> '{cohort,trim_fraction}')::numeric < 0.5
    AND jsonb_typeof(_config -> 'sensitivity_buffers_minutes') = 'object'
    AND (_config -> 'sensitivity_buffers_minutes') ?& ARRAY['high', 'balanced', 'low']
    AND jsonb_typeof(_config #> '{sensitivity_buffers_minutes,high}') = 'number'
    AND jsonb_typeof(_config #> '{sensitivity_buffers_minutes,balanced}') = 'number'
    AND jsonb_typeof(_config #> '{sensitivity_buffers_minutes,low}') = 'number'
    AND (_config #>> '{sensitivity_buffers_minutes,high}')::numeric = 0
    AND (_config #>> '{sensitivity_buffers_minutes,balanced}')::numeric = 45
    AND (_config #>> '{sensitivity_buffers_minutes,low}')::numeric = 90
    AND jsonb_typeof(_config -> 'candidate_bounds') = 'object'
    AND (_config -> 'candidate_bounds') ?& ARRAY['floor_minutes', 'ceiling_minutes']
    AND jsonb_typeof(_config #> '{candidate_bounds,floor_minutes}') = 'number'
    AND (_config #>> '{candidate_bounds,floor_minutes}')::numeric >= 0
    AND (_config #>> '{candidate_bounds,floor_minutes}')::numeric
      = trunc((_config #>> '{candidate_bounds,floor_minutes}')::numeric)
    AND jsonb_typeof(_config #> '{candidate_bounds,ceiling_minutes}') = 'number'
    AND (_config #>> '{candidate_bounds,ceiling_minutes}')::numeric
      >= (_config #>> '{candidate_bounds,floor_minutes}')::numeric
    AND (_config #>> '{candidate_bounds,ceiling_minutes}')::numeric
      = trunc((_config #>> '{candidate_bounds,ceiling_minutes}')::numeric)
    AND jsonb_typeof(_config -> 'sleep_compensation') = 'object'
    AND (_config -> 'sleep_compensation') ?& ARRAY[
      'max_start_delay_minutes', 'max_wake_advance_minutes', 'max_wake_delay_minutes',
      'max_update_minutes_per_day', 'min_positive_nights', 'lookback_nights',
      'min_late_events_per_night', 'timezone_tolerance_minutes'
    ]
    AND jsonb_typeof(_config #> '{sleep_compensation,max_start_delay_minutes}') = 'number'
    AND (_config #>> '{sleep_compensation,max_start_delay_minutes}')::numeric >= 0
    AND (_config #>> '{sleep_compensation,max_start_delay_minutes}')::numeric
      = trunc((_config #>> '{sleep_compensation,max_start_delay_minutes}')::numeric)
    AND jsonb_typeof(_config #> '{sleep_compensation,max_wake_advance_minutes}') = 'number'
    AND (_config #>> '{sleep_compensation,max_wake_advance_minutes}')::numeric >= 0
    AND (_config #>> '{sleep_compensation,max_wake_advance_minutes}')::numeric
      = trunc((_config #>> '{sleep_compensation,max_wake_advance_minutes}')::numeric)
    AND jsonb_typeof(_config #> '{sleep_compensation,max_wake_delay_minutes}') = 'number'
    AND (_config #>> '{sleep_compensation,max_wake_delay_minutes}')::numeric >= 0
    AND (_config #>> '{sleep_compensation,max_wake_delay_minutes}')::numeric
      = trunc((_config #>> '{sleep_compensation,max_wake_delay_minutes}')::numeric)
    AND jsonb_typeof(_config #> '{sleep_compensation,max_update_minutes_per_day}') = 'number'
    AND (_config #>> '{sleep_compensation,max_update_minutes_per_day}')::numeric >= 0
    AND (_config #>> '{sleep_compensation,max_update_minutes_per_day}')::numeric
      = trunc((_config #>> '{sleep_compensation,max_update_minutes_per_day}')::numeric)
    AND jsonb_typeof(_config #> '{sleep_compensation,min_positive_nights}') = 'number'
    AND (_config #>> '{sleep_compensation,min_positive_nights}')::numeric > 0
    AND (_config #>> '{sleep_compensation,min_positive_nights}')::numeric
      = trunc((_config #>> '{sleep_compensation,min_positive_nights}')::numeric)
    AND jsonb_typeof(_config #> '{sleep_compensation,lookback_nights}') = 'number'
    AND (_config #>> '{sleep_compensation,lookback_nights}')::numeric > 0
    AND (_config #>> '{sleep_compensation,lookback_nights}')::numeric
      = trunc((_config #>> '{sleep_compensation,lookback_nights}')::numeric)
    AND (_config #>> '{sleep_compensation,min_positive_nights}')::numeric
      <= (_config #>> '{sleep_compensation,lookback_nights}')::numeric
    AND jsonb_typeof(_config #> '{sleep_compensation,min_late_events_per_night}') = 'number'
    AND (_config #>> '{sleep_compensation,min_late_events_per_night}')::numeric > 0
    AND (_config #>> '{sleep_compensation,min_late_events_per_night}')::numeric
      = trunc((_config #>> '{sleep_compensation,min_late_events_per_night}')::numeric)
    AND jsonb_typeof(_config #> '{sleep_compensation,timezone_tolerance_minutes}') = 'number'
    AND (_config #>> '{sleep_compensation,timezone_tolerance_minutes}')::numeric >= 0
    AND (_config #>> '{sleep_compensation,timezone_tolerance_minutes}')::numeric
      = trunc((_config #>> '{sleep_compensation,timezone_tolerance_minutes}')::numeric)
    AND jsonb_typeof(_config -> 'evaluator') = 'object'
    AND (_config -> 'evaluator') ?& ARRAY['contract_version']
    AND jsonb_typeof(_config #> '{evaluator,contract_version}') = 'string'
    AND _config #>> '{evaluator,contract_version}' = 'adaptive_candidate_v1'
    AND jsonb_typeof(_config -> 'emergency') = 'object'
    AND (_config -> 'emergency') ?& ARRAY[
      'contract_version', 'neutral_minutes', 'expected_live_definition_sha256'
    ]
    AND jsonb_typeof(_config #> '{emergency,contract_version}') = 'string'
    AND _config #>> '{emergency,contract_version}' = 'adr0022_v1'
    AND jsonb_typeof(_config #> '{emergency,neutral_minutes}') = 'number'
    AND (_config #>> '{emergency,neutral_minutes}')::numeric = 90
    AND (_config #>> '{emergency,neutral_minutes}')::numeric
      = trunc((_config #>> '{emergency,neutral_minutes}')::numeric)
    AND jsonb_typeof(_config #> '{emergency,expected_live_definition_sha256}') = 'string'
    AND (_config #>> '{emergency,expected_live_definition_sha256}') ~ '^[a-f0-9]{64}$'
    AND _config #>> '{emergency,expected_live_definition_sha256}'
      = '1907d59473d274d46a0e8e0b9ce8027037b4494b0dddf073cb46abf67db92e21'
$_$;


ALTER FUNCTION "private"."alert_candidate_config_is_valid"("_config" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."apply_liveness_side_effects"("_user_id" "uuid", "_observed_at" timestamp with time zone, "_received_at" timestamp with time zone) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
BEGIN
  INSERT INTO public.device_state (user_id, status, last_heartbeat_at, updated_at)
  VALUES (_user_id, 'normal', _received_at, now())
  ON CONFLICT (user_id) DO UPDATE
    SET status = 'normal',
        last_heartbeat_at = greatest(device_state.last_heartbeat_at, excluded.last_heartbeat_at),
        updated_at = now();

  IF NOT (auth.uid() IS NOT NULL AND auth.uid() <> _user_id)
     AND NOT EXISTS (
       SELECT 1 FROM public.alerts
       WHERE user_id = _user_id AND status = 'open'
     ) THEN
    DELETE FROM public.notifications
      WHERE recipient_id = _user_id
        AND kind in ('self', 'concern');
  END IF;
END;
$$;


ALTER FUNCTION "private"."apply_liveness_side_effects"("_user_id" "uuid", "_observed_at" timestamp with time zone, "_received_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."can_see_alert"("_alert_id" "uuid", "_user" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1 from public.alerts a
    where a.id = _alert_id and (
      a.user_id = _user
      or private.is_guardian_of(a.user_id, _user)
      or private.watches_user(_user, a.user_id)
      or (a.stage in ('community', 'terminal') and private.shares_community(_user, a.user_id))
    )
  );
$$;


ALTER FUNCTION "private"."can_see_alert"("_alert_id" "uuid", "_user" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."candidate_sleep_intervals"("_user_id" "uuid", "_from" timestamp with time zone, "_to" timestamp with time zone, "_version_id" "uuid") RETURNS TABLE("starts_at" timestamp with time zone, "ends_at" timestamp with time zone, "basis" "text", "confidence" double precision, "provenance" "jsonb")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    SET "DateStyle" TO 'ISO, YMD'
    SET "extra_float_digits" TO '3'
    AS $$
DECLARE
  _config jsonb;
  _config_sha256 text;
  _max_start_delay integer;
  _max_wake_advance integer;
  _max_wake_delay integer;
  _max_update_per_day integer;
  _min_positive integer;
  _lookback integer;
  _min_late_events integer;
  _timezone_tolerance integer;
  _status text;
  _evidence_version text;
  _context record;
  _anchor_start timestamptz;
  _anchor_end timestamptz;
  _midpoint timestamptz;
  _raw_start_delay integer;
  _raw_wake_advance integer;
  _raw_wake_delay integer;
  _start_delay integer;
  _wake_advance integer;
  _wake_delay integer;
  _rate_cap integer;
  _first_count integer;
  _second_count integer;
  _prior_count integer;
  _prior_start_cap_applied boolean;
  _quality_reason text;
  _cap_reasons text[];
  _offset_minutes integer;
BEGIN
  IF _user_id IS NULL OR _version_id IS NULL
     OR _from IS NULL OR _to IS NULL OR _from >= _to THEN
    RETURN;
  END IF;

  SELECT version.config, version.config_sha256,
         version.status, version.evidence_version
    INTO _config, _config_sha256, _status, _evidence_version
  FROM public.alert_model_versions AS version
  WHERE version.id = _version_id;

  IF NOT FOUND
     OR _status NOT IN ('replay', 'shadow')
     OR _evidence_version <> 'canonical-v2'
     OR _config_sha256
        <> encode(extensions.digest(_config::text, 'sha256'), 'hex') THEN
    RETURN;
  END IF;

  -- See private.alert_candidate_config_is_valid: a canonical config hash
  -- cannot prove a legacy row's scalars have the required raw JSON type,
  -- range, or integrality, so this must be checked before any type is
  -- assumed from a bare cast.
  IF NOT private.alert_candidate_config_is_valid(_config) THEN
    RETURN;
  END IF;

  _max_start_delay :=
    (_config #>> '{sleep_compensation,max_start_delay_minutes}')::integer;
  _max_wake_advance :=
    (_config #>> '{sleep_compensation,max_wake_advance_minutes}')::integer;
  _max_wake_delay :=
    (_config #>> '{sleep_compensation,max_wake_delay_minutes}')::integer;
  _max_update_per_day :=
    (_config #>> '{sleep_compensation,max_update_minutes_per_day}')::integer;
  _min_positive :=
    (_config #>> '{sleep_compensation,min_positive_nights}')::integer;
  _lookback :=
    (_config #>> '{sleep_compensation,lookback_nights}')::integer;
  _min_late_events :=
    (_config #>> '{sleep_compensation,min_late_events_per_night}')::integer;
  _timezone_tolerance :=
    (_config #>> '{sleep_compensation,timezone_tolerance_minutes}')::integer;

  FOR _context IN
    SELECT context.*
    FROM public.alert_sleep_night_contexts AS context
    WHERE context.version_id = _version_id
      AND context.user_id = _user_id
      AND context.evidence_version = 'canonical-v2'
      AND context.anchor_starts_at < _to
      AND context.anchor_ends_at > _from
      AND context.captured_at <= _to
      AND (
        (
          context.coverage_state = 'unknown'
          AND (context.finalized_at IS NULL OR context.finalized_at <= _to)
        )
        OR (
          context.coverage_state IN ('valid', 'outage')
          AND context.finalized_at IS NOT NULL
          AND context.finalized_at >= context.anchor_ends_at
          AND context.finalized_at <= _to
        )
      )
    ORDER BY context.anchor_starts_at
  LOOP
    IF NOT EXISTS (
         SELECT 1
         FROM pg_catalog.pg_timezone_names AS zone
         WHERE zone.name = _context.timezone
       )
       OR _context.sleep_start_local = _context.sleep_end_local
       OR _context.anchor_ends_at <= _context.anchor_starts_at
       OR _context.captured_at > _context.anchor_starts_at
       OR (
         _context.coverage_state IN ('valid', 'outage')
         AND (
           _context.finalized_at IS NULL
           OR _context.finalized_at < _context.anchor_ends_at
           OR _context.finalized_at > _to
         )
       )
       OR (
         _context.coverage_state = 'unknown'
         AND _context.finalized_at IS NOT NULL
         AND _context.finalized_at > _to
       ) THEN
      CONTINUE;
    END IF;

    _anchor_start :=
      ((_context.anchor_date + _context.sleep_start_local)
        AT TIME ZONE _context.timezone);
    _anchor_end := ((
      _context.anchor_date
      + CASE
          WHEN _context.sleep_end_local <= _context.sleep_start_local THEN 1
          ELSE 0
        END
      + _context.sleep_end_local
    ) AT TIME ZONE _context.timezone);
    _offset_minutes := extract(epoch FROM (
      ((_context.anchor_starts_at AT TIME ZONE _context.timezone)
        AT TIME ZONE 'UTC') - _context.anchor_starts_at
    ))::integer / 60;

    IF _anchor_start <> _context.anchor_starts_at
       OR _anchor_end <> _context.anchor_ends_at
       OR _offset_minutes <> _context.utc_offset_minutes THEN
      CONTINUE;
    END IF;

    _midpoint := _anchor_start + ((_anchor_end - _anchor_start) / 2);
    SELECT
      count(*) FILTER (
        WHERE ping.received_at >= _anchor_start
          AND ping.received_at < _midpoint
      )::integer,
      count(*) FILTER (
        WHERE ping.received_at >= _midpoint
          AND ping.received_at < _anchor_end
      )::integer,
      coalesce(floor(extract(epoch FROM (
        max(ping.received_at) FILTER (
          WHERE ping.received_at >= _anchor_start
            AND ping.received_at < _midpoint
        ) - _anchor_start
      )) / 60)::integer, 0),
      coalesce(floor(extract(epoch FROM (
        _anchor_end - min(ping.received_at) FILTER (
          WHERE ping.received_at >= _midpoint
            AND ping.received_at < _anchor_end
        )
      )) / 60)::integer, 0)
      INTO _first_count, _second_count,
           _raw_start_delay, _raw_wake_advance
    FROM public.behavior_pings AS ping
    WHERE ping.user_id = _user_id
      AND ping.ingest_version = 2
      AND abs(extract(epoch FROM (ping.received_at - ping.at))) <= 300
      AND ping.at < _to
      AND ping.received_at < _to;

    _cap_reasons := ARRAY[]::text[];
    IF _raw_start_delay > _max_start_delay THEN
      _cap_reasons := pg_catalog.array_append(
        _cap_reasons, 'max_start_delay_minutes'
      );
    END IF;
    IF _raw_wake_advance > _max_wake_advance THEN
      _cap_reasons := pg_catalog.array_append(
        _cap_reasons, 'max_wake_advance_minutes'
      );
    END IF;
    _start_delay := least(_max_start_delay, greatest(0, _raw_start_delay));
    _wake_advance := least(_max_wake_advance, greatest(0, _raw_wake_advance));
    _wake_delay := 0;
    _raw_wake_delay := 0;
    _rate_cap := 0;
    _prior_count := 0;
    _prior_start_cap_applied := false;
    _quality_reason := CASE
      WHEN _context.coverage_state = 'valid' THEN 'coverage_valid'
      ELSE 'coverage_' || _context.coverage_state
    END;

    IF _context.coverage_state = 'valid' THEN
      WITH prior_contexts AS (
        SELECT
          prior.anchor_date,
          prior.anchor_starts_at,
          prior.anchor_ends_at,
          prior.anchor_starts_at
            + ((prior.anchor_ends_at - prior.anchor_starts_at) / 2)
            AS midpoint
        FROM public.alert_sleep_night_contexts AS prior
        WHERE prior.version_id = _version_id
          AND prior.user_id = _user_id
          AND prior.coverage_state = 'valid'
          AND prior.evidence_version = 'canonical-v2'
          AND prior.anchor_date < _context.anchor_date
          AND prior.anchor_date >= (_context.anchor_date - _lookback)
          AND prior.timezone = _context.timezone
          AND abs(prior.utc_offset_minutes - _context.utc_offset_minutes)
            <= _timezone_tolerance
          AND prior.captured_at <= prior.anchor_starts_at
          AND prior.captured_at <= _to
          AND prior.finalized_at >= prior.anchor_ends_at
          AND prior.finalized_at <= _to
          AND (
            (prior.anchor_date + prior.sleep_start_local)
              AT TIME ZONE prior.timezone
          ) = prior.anchor_starts_at
          AND ((
            prior.anchor_date
            + CASE
                WHEN prior.sleep_end_local <= prior.sleep_start_local THEN 1
                ELSE 0
              END
            + prior.sleep_end_local
          ) AT TIME ZONE prior.timezone) = prior.anchor_ends_at
          AND extract(epoch FROM (
            ((prior.anchor_starts_at AT TIME ZONE prior.timezone)
              AT TIME ZONE 'UTC') - prior.anchor_starts_at
          ))::integer / 60 = prior.utc_offset_minutes
      ), prior_delays AS (
        SELECT
          prior.anchor_date,
          floor(extract(epoch FROM (
            max(ping.received_at) - prior.anchor_starts_at
          )) / 60)::integer AS raw_delay_minutes,
          least(
            _max_start_delay,
            floor(extract(epoch FROM (
              max(ping.received_at) - prior.anchor_starts_at
            )) / 60)::integer
          ) AS delay_minutes
        FROM prior_contexts AS prior
        JOIN public.behavior_pings AS ping
          ON ping.user_id = _user_id
         AND ping.ingest_version = 2
         AND abs(extract(epoch FROM (ping.received_at - ping.at))) <= 300
         AND ping.at < _to
         AND ping.received_at < _to
         AND ping.received_at >= prior.anchor_starts_at
         AND ping.received_at < prior.midpoint
        GROUP BY prior.anchor_date, prior.anchor_starts_at
        HAVING count(*) >= _min_late_events
      )
      SELECT
        count(*)::integer,
        coalesce(
          percentile_disc(0.5)
            WITHIN GROUP (ORDER BY delay_minutes)::integer,
          0
        ),
        coalesce(bool_or(raw_delay_minutes > _max_start_delay), false)
        INTO _prior_count, _raw_wake_delay, _prior_start_cap_applied
      FROM prior_delays;

      IF _prior_count >= _min_positive THEN
        _rate_cap :=
          greatest(0, _prior_count - _min_positive + 1)
          * _max_update_per_day;
        IF _prior_start_cap_applied THEN
          _cap_reasons := pg_catalog.array_append(
            _cap_reasons, 'prior_max_start_delay_minutes'
          );
        END IF;
        IF _raw_wake_delay > _max_wake_delay THEN
          _cap_reasons := pg_catalog.array_append(
            _cap_reasons, 'max_wake_delay_minutes'
          );
        END IF;
        IF least(_raw_wake_delay, _max_wake_delay) > _rate_cap THEN
          _cap_reasons := pg_catalog.array_append(
            _cap_reasons, 'max_update_minutes_per_day'
          );
        END IF;
        _wake_delay :=
          least(_max_wake_delay, _raw_wake_delay, _rate_cap);
        _quality_reason := 'coverage_valid_prior_positive';
      ELSE
        _wake_delay := 0;
      END IF;
    END IF;

    starts_at := _anchor_start + make_interval(mins => _start_delay);
    ends_at := _anchor_end
      - make_interval(mins => _wake_advance)
      + make_interval(mins => _wake_delay);
    IF starts_at >= ends_at THEN
      CONTINUE;
    END IF;

    basis := CASE
      WHEN _start_delay > 0 OR _wake_advance > 0 OR _wake_delay > 0
        THEN 'positive_evidence_adjusted'
      ELSE 'configured_anchor'
    END;
    confidence := CASE
      WHEN _start_delay > 0 OR _wake_advance > 0 THEN 1.0
      WHEN _wake_delay > 0 THEN least(
        1.0,
        _prior_count::double precision / _min_positive::double precision
      )
      ELSE 0.0
    END;
    provenance := jsonb_build_object(
      'config_sha256', _config_sha256,
      'anchor_starts_at', _anchor_start,
      'anchor_ends_at', _anchor_end,
      'context_captured_at', _context.captured_at,
      'context_finalized_at', _context.finalized_at,
      'context_evidence_version', _context.evidence_version,
      'context_provenance_sha256', _context.provenance_sha256,
      'evidence_cutoff', _to,
      'first_half_positive_count', _first_count,
      'second_half_positive_count', _second_count,
      'prior_positive_night_count', _prior_count,
      'start_delay_minutes', _start_delay,
      'wake_advance_minutes', _wake_advance,
      'wake_delay_minutes', _wake_delay,
      'caps', jsonb_build_object(
        'max_start_delay_minutes', _max_start_delay,
        'max_wake_advance_minutes', _max_wake_advance,
        'max_wake_delay_minutes', _max_wake_delay,
        'max_update_minutes_per_day', _max_update_per_day
      ),
      'confidence', confidence,
      'cap_reason',
        coalesce(pg_catalog.array_to_string(_cap_reasons, ','), 'none'),
      'timezone', _context.timezone,
      'utc_offset_minutes', _context.utc_offset_minutes,
      'coverage_state', _context.coverage_state,
      'quality_reason', _quality_reason
    );
    RETURN NEXT;
  END LOOP;
END;
$$;


ALTER FUNCTION "private"."candidate_sleep_intervals"("_user_id" "uuid", "_from" timestamp with time zone, "_to" timestamp with time zone, "_version_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."canonical_routine_mode"("_value" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
  SELECT CASE _value
    WHEN 'semester_break' THEN 'semester_break'
    WHEN 'student' THEN 'semester_break'
    WHEN 'shift_irregular' THEN 'shift_irregular'
    WHEN 'shift_worker' THEN 'shift_irregular'
    WHEN 'flexible' THEN 'shift_irregular'
    ELSE 'regular_9to5'
  END;
$$;


ALTER FUNCTION "private"."canonical_routine_mode"("_value" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."capture_alert_shadow_interventions"("_version_id" "uuid", "_through_at" timestamp with time zone, "_max_rows" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    AS $$
DECLARE
  _evidence_version text;
  _inserted integer := 0;
  _step integer := 0;
BEGIN
  IF _version_id IS NULL OR _through_at IS NULL
     OR _max_rows IS NULL OR _max_rows NOT BETWEEN 1 AND 10000 THEN
    RAISE EXCEPTION 'invalid shadow intervention capture arguments';
  END IF;

  SELECT v.evidence_version INTO _evidence_version
  FROM public.alert_model_versions AS v
  WHERE v.id = _version_id AND v.status = 'shadow';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid shadow intervention version';
  END IF;

  WITH source AS (
    SELECT n.id, n.recipient_id AS user_id, n.created_at AS occurred_at,
      CASE WHEN n.kind = 'self' THEN 'self_alert' ELSE 'concern_prompt' END AS kind
    FROM public.notifications AS n
    WHERE n.created_at <= _through_at
    ORDER BY n.created_at, n.id
    LIMIT _max_rows
  )
  INSERT INTO public.alert_intervention_events (
    version_id, user_id, occurred_at, kind, captured_at, evidence_version,
    provenance_sha256, source_kind, source_id
  )
  SELECT
    _version_id, s.user_id, s.occurred_at, s.kind, _through_at,
    _evidence_version,
    encode(extensions.digest(jsonb_build_object(
      'version_id', _version_id, 'source_kind', 'notification',
      'source_id', s.id, 'user_id', s.user_id,
      'occurred_at', s.occurred_at, 'kind', s.kind
    )::text, 'sha256'), 'hex'),
    'notification', s.id
  FROM source AS s
  ON CONFLICT (version_id, source_kind, source_id) DO NOTHING;
  GET DIAGNOSTICS _step = ROW_COUNT;
  _inserted := _inserted + _step;

  WITH source AS (
    SELECT t.id, t.ward_id AS user_id, t.created_at AS occurred_at
    FROM public.checkin_tasks AS t
    WHERE t.created_at <= _through_at
    ORDER BY t.created_at, t.id
    LIMIT greatest(_max_rows - _inserted, 0)
  )
  INSERT INTO public.alert_intervention_events (
    version_id, user_id, occurred_at, kind, captured_at, evidence_version,
    provenance_sha256, source_kind, source_id
  )
  SELECT
    _version_id, s.user_id, s.occurred_at, 'checkin_prompt', _through_at,
    _evidence_version,
    encode(extensions.digest(jsonb_build_object(
      'version_id', _version_id, 'source_kind', 'checkin_task',
      'source_id', s.id, 'user_id', s.user_id,
      'occurred_at', s.occurred_at
    )::text, 'sha256'), 'hex'),
    'checkin_task', s.id
  FROM source AS s
  ON CONFLICT (version_id, source_kind, source_id) DO NOTHING;
  GET DIAGNOSTICS _step = ROW_COUNT;
  _inserted := _inserted + _step;

  WITH source AS (
    SELECT g.id, g.ward_id AS user_id, g.created_at AS occurred_at
    FROM public.guardianships AS g
    WHERE g.status = 'active' AND g.created_at <= _through_at
    ORDER BY g.created_at, g.id
    LIMIT greatest(_max_rows - _inserted, 0)
  )
  INSERT INTO public.alert_intervention_events (
    version_id, user_id, occurred_at, kind, captured_at, evidence_version,
    provenance_sha256, source_kind, source_id
  )
  SELECT
    _version_id, s.user_id, s.occurred_at, 'guardian_confirmation', _through_at,
    _evidence_version,
    encode(extensions.digest(jsonb_build_object(
      'version_id', _version_id, 'source_kind', 'guardianship',
      'source_id', s.id, 'user_id', s.user_id,
      'occurred_at', s.occurred_at
    )::text, 'sha256'), 'hex'),
    'guardianship', s.id
  FROM source AS s
  ON CONFLICT (version_id, source_kind, source_id) DO NOTHING;
  GET DIAGNOSTICS _step = ROW_COUNT;
  _inserted := _inserted + _step;

  INSERT INTO private.adaptive_alert_shadow_intervention_cursor (
    version_id, source_kind, last_captured_at
  ) VALUES
    (_version_id, 'notification', _through_at),
    (_version_id, 'checkin_task', _through_at),
    (_version_id, 'guardianship', _through_at)
  ON CONFLICT (version_id, source_kind) DO UPDATE SET
    last_captured_at = greatest(
      private.adaptive_alert_shadow_intervention_cursor.last_captured_at,
      excluded.last_captured_at
    );

  RETURN jsonb_build_object('status', 'completed', 'inserted_count', _inserted);
END;
$$;


ALTER FUNCTION "private"."capture_alert_shadow_interventions"("_version_id" "uuid", "_through_at" timestamp with time zone, "_max_rows" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."capture_alert_shadow_subject_contexts"("_version_id" "uuid", "_captured_at" timestamp with time zone, "_max_users" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    AS $$
DECLARE
  _version public.alert_model_versions%ROWTYPE;
  _person record;
  _existing public.alert_judgment_subject_contexts%ROWTYPE;
  _population_count integer := 0;
  _replayable_count integer := 0;
  _unreplayable_count integer := 0;
  _reason text;
  _state text;
  _offset integer;
  _canonical_sensitivity text;
  _context_sha text;
  _existing_expected_sha text;
  _provenance jsonb;
BEGIN
  IF _version_id IS NULL OR _captured_at IS NULL
     OR _max_users IS NULL OR _max_users NOT BETWEEN 1 AND 10000 THEN
    RAISE EXCEPTION 'invalid shadow context capture arguments';
  END IF;

  SELECT v.* INTO _version
  FROM public.alert_model_versions AS v
  WHERE v.id = _version_id
    AND v.status = 'shadow'
    AND v.shadow_enabled_at IS NOT NULL
    AND v.shadow_enabled_at <= _captured_at;

  IF NOT FOUND
     OR _version.evidence_version <> 'canonical-v2'
     OR _version.config_sha256 <>
       encode(extensions.digest(_version.config::text, 'sha256'), 'hex') THEN
    RAISE EXCEPTION 'invalid shadow context version';
  END IF;

  FOR _person IN
    WITH population AS (
      SELECT DISTINCT ds.user_id
      FROM public.device_state AS ds
      WHERE EXISTS (
        SELECT 1
        FROM public.group_members AS gm
        WHERE gm.user_id = ds.user_id
          AND gm.status = 'active'
          AND gm.monitored
      )
    )
    SELECT
      p.user_id,
      coalesce(s.sensitivity, 'balanced') AS sensitivity,
      coalesce(s.timezone, 'UTC') AS timezone,
      coalesce(s.updated_at, _captured_at) AS settings_updated_at,
      coalesce(pr.routine_pattern, 'regular_9to5') AS routine_mode
    FROM population AS p
    LEFT JOIN public.user_settings AS s ON s.user_id = p.user_id
    LEFT JOIN public.profiles AS pr ON pr.id = p.user_id
    ORDER BY p.user_id
    LIMIT _max_users
  LOOP
    _population_count := _population_count + 1;
    _reason := NULL;
    _offset := 0;
    _canonical_sensitivity := CASE
      WHEN lower(trim(coalesce(_person.sensitivity, '')))
        IN ('high', 'sensitive') THEN 'high'
      WHEN lower(trim(coalesce(_person.sensitivity, '')))
        IN ('low', 'relaxed') THEN 'low'
      ELSE 'balanced'
    END;

    IF _person.settings_updated_at > _captured_at THEN
      _reason := 'future_source_timestamp';
    ELSIF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_timezone_names AS z
      WHERE z.name = _person.timezone
    ) THEN
      _reason := 'invalid_timezone';
    ELSE
      _offset := round(extract(epoch FROM (
        (_captured_at AT TIME ZONE _person.timezone)
        - (_captured_at AT TIME ZONE 'UTC')
      )) / 60)::integer;
    END IF;

    _state := CASE WHEN _reason IS NULL THEN 'replayable' ELSE 'unreplayable' END;
    _provenance := jsonb_build_object(
      'contract_version', 'shadow-subject-context-v1',
      'version_id', _version_id,
      'user_id', _person.user_id,
      'sensitivity', _person.sensitivity,
      'routine_mode', _person.routine_mode,
      'timezone', _person.timezone,
      'utc_offset_minutes', _offset,
      'settings_updated_at', _person.settings_updated_at,
      'config_sha256', _version.config_sha256,
      'evidence_version', _version.evidence_version,
      'state', _state,
      'reason', _reason
    );

    IF _reason IS NOT NULL THEN
      _context_sha := encode(
        extensions.digest(_provenance::text, 'sha256'), 'hex'
      );

      UPDATE public.alert_judgment_subject_contexts
      SET effective_to = _captured_at
      WHERE version_id = _version_id
        AND user_id = _person.user_id
        AND effective_to IS NULL
        AND effective_from < _captured_at;
    ELSE
      SELECT context.* INTO _existing
      FROM public.alert_judgment_subject_contexts AS context
      WHERE context.version_id = _version_id
        AND context.user_id = _person.user_id
        AND context.effective_to IS NULL
      ORDER BY context.effective_from DESC
      LIMIT 1;

      IF FOUND THEN
        _existing_expected_sha := encode(extensions.digest(jsonb_build_object(
          'version_id', _existing.version_id,
          'user_id', _existing.user_id,
          'effective_from_utc',
            to_char(_existing.effective_from AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
          'effective_to_utc', NULL,
          'raw_sensitivity', _existing.raw_sensitivity,
          'canonical_sensitivity', _existing.canonical_sensitivity,
          'routine_mode', _existing.routine_mode,
          'timezone', _existing.timezone,
          'utc_offset_minutes', _existing.utc_offset_minutes,
          'settings_updated_at_utc',
            to_char(_existing.settings_updated_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
          'settings_provenance', _existing.settings_provenance,
          'captured_at_utc',
            to_char(_existing.captured_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
          'config_sha256', _existing.config_sha256,
          'evidence_version', _existing.evidence_version
        )::text, 'sha256'), 'hex');
      ELSE
        _existing_expected_sha := NULL;
      END IF;

      IF FOUND
         AND _existing.subject_context_sha256 = _existing_expected_sha
         AND _existing.raw_sensitivity IS NOT DISTINCT FROM _person.sensitivity
         AND _existing.canonical_sensitivity = _canonical_sensitivity
         AND _existing.routine_mode = _person.routine_mode
         AND _existing.timezone = _person.timezone
         AND _existing.utc_offset_minutes = _offset
         AND _existing.settings_updated_at = _person.settings_updated_at
         AND _existing.settings_provenance = _provenance
         AND _existing.config_sha256 = _version.config_sha256
         AND _existing.evidence_version = _version.evidence_version THEN
        _context_sha := _existing.subject_context_sha256;
      ELSE
        _context_sha := encode(extensions.digest(jsonb_build_object(
          'version_id', _version_id,
          'user_id', _person.user_id,
          'effective_from_utc',
            to_char(_captured_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
          'effective_to_utc', NULL,
          'raw_sensitivity', _person.sensitivity,
          'canonical_sensitivity', _canonical_sensitivity,
          'routine_mode', _person.routine_mode,
          'timezone', _person.timezone,
          'utc_offset_minutes', _offset,
          'settings_updated_at_utc',
            to_char(_person.settings_updated_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
          'settings_provenance', _provenance,
          'captured_at_utc',
            to_char(_captured_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
          'config_sha256', _version.config_sha256,
          'evidence_version', _version.evidence_version
        )::text, 'sha256'), 'hex');

        UPDATE public.alert_judgment_subject_contexts
        SET effective_to = _captured_at
        WHERE version_id = _version_id
          AND user_id = _person.user_id
          AND effective_to IS NULL
          AND effective_from < _captured_at;

        INSERT INTO public.alert_judgment_subject_contexts (
          version_id, user_id, effective_from, raw_sensitivity,
          canonical_sensitivity, routine_mode, timezone, utc_offset_minutes,
          settings_updated_at, settings_provenance, captured_at,
          config_sha256, evidence_version, subject_context_sha256
        ) VALUES (
          _version_id, _person.user_id, _captured_at, _person.sensitivity,
          _canonical_sensitivity, _person.routine_mode, _person.timezone, _offset,
          _person.settings_updated_at, _provenance, _captured_at,
          _version.config_sha256, _version.evidence_version, _context_sha
        );
      END IF;
    END IF;

    INSERT INTO private.adaptive_alert_shadow_subject_context_state (
      version_id, user_id, context_state, unreplayable_reason,
      subject_context_sha256, captured_at
    ) VALUES (
      _version_id, _person.user_id, _state, _reason, _context_sha, _captured_at
    )
    ON CONFLICT (version_id, user_id) DO UPDATE SET
      context_state = excluded.context_state,
      unreplayable_reason = excluded.unreplayable_reason,
      subject_context_sha256 = excluded.subject_context_sha256,
      captured_at = excluded.captured_at;

    IF _reason IS NULL THEN
      _replayable_count := _replayable_count + 1;
    ELSE
      _unreplayable_count := _unreplayable_count + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'status', 'completed',
    'population_count', _population_count,
    'replayable_count', _replayable_count,
    'unreplayable_count', _unreplayable_count
  );
END;
$$;


ALTER FUNCTION "private"."capture_alert_shadow_subject_contexts"("_version_id" "uuid", "_captured_at" timestamp with time zone, "_max_users" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."disable_adaptive_alert_shadow"("_failure_code" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    AS $$
DECLARE
  _fixed_code text;
BEGIN
  _fixed_code := CASE
    WHEN _failure_code IN (
      'shadow_live_write_detected',
      'shadow_live_hash_mismatch',
      'shadow_acl_validation_failed',
      'shadow_publication_validation_failed',
      'shadow_detail_budget_exceeded',
      'shadow_population_budget_exceeded',
      'shadow_timeout',
      'shadow_privacy_validation_failed',
      'shadow_malformed_result',
      'ordinary_failure'
    ) THEN _failure_code
    ELSE 'ordinary_failure'
  END;
  UPDATE private.adaptive_alert_shadow_runtime_config
  SET enabled = false,
      last_failure_code = _fixed_code,
      updated_at = clock_timestamp()
  WHERE singleton;
END;
$$;


ALTER FUNCTION "private"."disable_adaptive_alert_shadow"("_failure_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."dispatch_account_shadow_cycle"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    AS $$
DECLARE
  _k integer;
  _results jsonb := '[]'::jsonb;
BEGIN
  FOREACH _k IN ARRAY ARRAY[25, 50, 100] LOOP
    PERFORM private.rebuild_account_gap_profiles(NULL, 30, _k, 0.95, 30, 2, 90, true);
    _results := _results || jsonb_build_array(
      private.record_account_threshold_shadow(NULL, 30, _k, 0.95)
    );
  END LOOP;

  RETURN jsonb_build_object('runs', _results);
END;
$$;


ALTER FUNCTION "private"."dispatch_account_shadow_cycle"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."dispatch_adaptive_alert_shadow_cycle"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    AS $$
DECLARE
  _runtime private.adaptive_alert_shadow_runtime_config%ROWTYPE;
  _failure_code text;
  _result jsonb;
  _failures integer;
BEGIN
  SELECT c.* INTO _runtime
  FROM private.adaptive_alert_shadow_runtime_config AS c
  WHERE c.singleton;
  IF _runtime.enabled IS NOT TRUE OR _runtime.version_id IS NULL THEN
    RETURN;
  END IF;

  PERFORM set_config('statement_timeout', '120s', true);
  PERFORM set_config('lock_timeout', '2s', true);

  BEGIN
    _result := private.run_adaptive_alert_shadow_cycle(
      _runtime.version_id, clock_timestamp()
    );
    IF _result ->> 'status' IN ('completed', 'duplicate') THEN
      UPDATE private.adaptive_alert_shadow_runtime_config
      SET consecutive_failures = 0,
          last_failure_code = NULL,
          updated_at = clock_timestamp()
      WHERE singleton;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    _failure_code := CASE
      WHEN SQLSTATE = '57014' THEN 'shadow_timeout'
      WHEN SQLERRM LIKE '%shadow_live_write_detected%'
        THEN 'shadow_live_write_detected'
      WHEN SQLERRM LIKE '%shadow_live_hash_mismatch%'
        THEN 'shadow_live_hash_mismatch'
      WHEN SQLERRM LIKE '%shadow_acl_validation_failed%'
        THEN 'shadow_acl_validation_failed'
      WHEN SQLERRM LIKE '%shadow_publication_validation_failed%'
        THEN 'shadow_publication_validation_failed'
      WHEN SQLERRM LIKE '%shadow_detail_budget_exceeded%'
        THEN 'shadow_detail_budget_exceeded'
      WHEN SQLERRM LIKE '%shadow_population_budget_exceeded%'
        THEN 'shadow_population_budget_exceeded'
      WHEN SQLERRM LIKE '%malformed%'
        THEN 'shadow_malformed_result'
      ELSE 'ordinary_failure'
    END;

    IF _failure_code <> 'ordinary_failure' THEN
      PERFORM private.disable_adaptive_alert_shadow(_failure_code);
      RETURN;
    END IF;

    UPDATE private.adaptive_alert_shadow_runtime_config
    SET consecutive_failures = least(
          max_consecutive_failures, consecutive_failures + 1
        ),
        last_failure_code = 'ordinary_failure',
        updated_at = clock_timestamp()
    WHERE singleton
    RETURNING consecutive_failures INTO _failures;
    IF _failures >= _runtime.max_consecutive_failures THEN
      PERFORM private.disable_adaptive_alert_shadow('ordinary_failure');
    END IF;
  END;
END;
$$;


ALTER FUNCTION "private"."dispatch_adaptive_alert_shadow_cycle"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."dispatch_adaptive_alert_shadow_maintenance"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    AS $$
DECLARE
  _runtime private.adaptive_alert_shadow_runtime_config%ROWTYPE;
  _version public.alert_model_versions%ROWTYPE;
  _through_at timestamptz := clock_timestamp();
  _through_date date;
  _before_dml bigint := 0;
  _after_dml bigint := 0;
  _failure_code text;
  _failures integer;
BEGIN
  SELECT runtime.* INTO _runtime
  FROM private.adaptive_alert_shadow_runtime_config AS runtime
  WHERE runtime.singleton;

  IF _runtime.enabled IS NOT TRUE OR _runtime.version_id IS NULL THEN
    RETURN;
  END IF;

  PERFORM set_config('statement_timeout', '120s', true);
  PERFORM set_config('lock_timeout', '2s', true);
  _through_date := (_through_at AT TIME ZONE 'UTC')::date;

  BEGIN
    SELECT version.* INTO _version
    FROM public.alert_model_versions AS version
    WHERE version.id = _runtime.version_id;

    IF NOT FOUND
       OR _version.status <> 'shadow'
       OR _version.shadow_enabled_at IS NULL
       OR _version.evidence_version <> 'canonical-v2'
       OR _version.config_sha256 <> encode(
         extensions.digest(_version.config::text, 'sha256'), 'hex'
       ) THEN
      RAISE EXCEPTION 'shadow_version_validation_failed';
    END IF;

    IF _version.config #>> '{sessionization,historical_v1_policy}'
       <> 'sessionized_training_only_v1' THEN
      RAISE EXCEPTION 'shadow_history_policy_validation_failed';
    END IF;

    IF NOT private.shadow_live_definition_matches(
      _version.config #>> '{emergency,expected_live_definition_sha256}',
      pg_get_functiondef('private.silence_threshold(uuid)'::regprocedure)
    ) THEN
      RAISE EXCEPTION 'shadow_live_hash_mismatch';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_catalog.pg_class AS relation
      WHERE relation.oid IN (
        'public.alert_gap_profiles'::regclass,
        'public.routine_mode_cohort_priors'::regclass,
        'private.adaptive_alert_shadow_daily_reports'::regclass
      )
        AND NOT relation.relrowsecurity
    )
    OR has_table_privilege('authenticated','public.alert_gap_profiles','SELECT')
    OR EXISTS (
      SELECT 1
      FROM pg_catalog.pg_publication_tables AS publication
      WHERE publication.schemaname IN ('private', 'public')
        AND publication.tablename IN (
          'alert_gap_profiles',
          'routine_mode_cohort_priors',
          'adaptive_alert_shadow_daily_reports'
        )
    ) THEN
      RAISE EXCEPTION 'shadow_acl_validation_failed';
    END IF;

    SELECT coalesce(sum(stats.n_tup_ins + stats.n_tup_upd + stats.n_tup_del),0)
      INTO _before_dml
    FROM pg_catalog.pg_stat_xact_user_tables AS stats
    WHERE stats.relid IN (
      'public.alerts'::regclass,
      'public.alert_events'::regclass,
      'public.notifications'::regclass
    );

    PERFORM private.rebuild_alert_gap_profiles(_runtime.version_id,_through_date);
    PERFORM private.rebuild_routine_mode_cohort_priors(_runtime.version_id,_through_date,'regular_9to5');
    PERFORM private.rebuild_routine_mode_cohort_priors(_runtime.version_id,_through_date,'semester_break');
    PERFORM private.rebuild_routine_mode_cohort_priors(_runtime.version_id,_through_date,'shift_irregular');
    PERFORM private.maintain_adaptive_alert_shadow(_through_at,_runtime.max_population);

    SELECT coalesce(sum(stats.n_tup_ins + stats.n_tup_upd + stats.n_tup_del),0)
      INTO _after_dml
    FROM pg_catalog.pg_stat_xact_user_tables AS stats
    WHERE stats.relid IN (
      'public.alerts'::regclass,
      'public.alert_events'::regclass,
      'public.notifications'::regclass
    );

    IF _after_dml <> _before_dml THEN
      RAISE EXCEPTION 'shadow_live_write_detected';
    END IF;

    UPDATE private.adaptive_alert_shadow_runtime_config
    SET consecutive_failures = 0,
        last_failure_code = NULL,
        updated_at = clock_timestamp()
    WHERE singleton;
  EXCEPTION WHEN OTHERS THEN
    _failure_code := CASE
      WHEN SQLSTATE = '57014' THEN 'shadow_timeout'
      WHEN SQLERRM LIKE '%shadow_live_write_detected%' THEN 'shadow_live_write_detected'
      WHEN SQLERRM LIKE '%shadow_live_hash_mismatch%' THEN 'shadow_live_hash_mismatch'
      WHEN SQLERRM LIKE '%shadow_acl_validation_failed%' THEN 'shadow_acl_validation_failed'
      WHEN SQLERRM LIKE '%shadow_history_policy_validation_failed%' THEN 'shadow_malformed_result'
      WHEN SQLERRM LIKE '%shadow_version_validation_failed%' THEN 'shadow_malformed_result'
      ELSE 'ordinary_failure'
    END;

    IF _failure_code <> 'ordinary_failure' THEN
      PERFORM private.disable_adaptive_alert_shadow(_failure_code);
      RETURN;
    END IF;

    UPDATE private.adaptive_alert_shadow_runtime_config
    SET consecutive_failures = least(max_consecutive_failures,consecutive_failures + 1),
        last_failure_code = 'ordinary_failure',
        updated_at = clock_timestamp()
    WHERE singleton
    RETURNING consecutive_failures INTO _failures;

    IF _failures >= _runtime.max_consecutive_failures THEN
      PERFORM private.disable_adaptive_alert_shadow('ordinary_failure');
    END IF;
  END;
END;
$$;


ALTER FUNCTION "private"."dispatch_adaptive_alert_shadow_maintenance"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."finalize_alert_shadow_coverage"("_user_id" "uuid", "_through_at" timestamp with time zone, "_retention_days" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    AS $$
DECLARE
  _version_id uuid;
  _enabled boolean;
  _accept boolean;
  _configured_retention integer;
  _inserted integer := 0;
  _deleted_leases integer := 0;
  _deleted_intervals integer := 0;
BEGIN
  IF _user_id IS NULL OR _through_at IS NULL THEN
    RAISE EXCEPTION 'coverage finalizer requires user and through_at';
  END IF;

  SELECT c.version_id, c.enabled, c.accept_coverage_leases, c.detail_retention_days
  INTO _version_id, _enabled, _accept, _configured_retention
  FROM private.adaptive_alert_shadow_runtime_config AS c
  WHERE c.singleton;

  IF _enabled IS NOT TRUE OR _accept IS NOT TRUE THEN
    RETURN jsonb_build_object('status', 'disabled', 'inserted', 0);
  END IF;
  IF _retention_days IS DISTINCT FROM _configured_retention
     OR _retention_days <> 35 THEN
    RAISE EXCEPTION 'coverage retention must equal configured 35 days';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM public.alert_model_versions AS v
    WHERE v.id = _version_id
      AND v.status = 'shadow'
      AND v.shadow_enabled_at IS NOT NULL
      AND v.shadow_enabled_at <= _through_at
  ) THEN
    RAISE EXCEPTION 'coverage runtime version is not an enabled shadow version';
  END IF;

  DELETE FROM private.alert_shadow_coverage_leases
  WHERE user_id = _user_id
    AND received_at < _through_at - make_interval(days => _retention_days);
  GET DIAGNOSTICS _deleted_leases = ROW_COUNT;

  DELETE FROM public.alert_observation_coverage_intervals
  WHERE user_id = _user_id
    AND ends_at < _through_at - make_interval(days => _retention_days);
  GET DIAGNOSTICS _deleted_intervals = ROW_COUNT;

  WITH ordered AS (
    SELECT
      l.*,
      lag(l.received_at) OVER (
        PARTITION BY
          l.user_id, l.client_id, l.channel, l.collector_contract,
          l.collector_state, l.capability_sha256, l.app_version,
          l.timezone, l.utc_offset_minutes
        ORDER BY l.received_at, l.event_id
      ) AS previous_received_at
    FROM private.alert_shadow_coverage_leases AS l
    WHERE l.user_id = _user_id
      AND l.received_at <= _through_at
  ), intervals AS (
    SELECT
      o.*,
      extract(epoch FROM (o.received_at - o.previous_received_at)) / 60.0
        AS gap_minutes,
      CASE
        WHEN o.channel = 'tauri' THEN 12
        WHEN o.channel = 'android-apk' THEN 35
      END AS allowed_gap_minutes
    FROM ordered AS o
    WHERE o.previous_received_at IS NOT NULL
      AND o.received_at > o.previous_received_at
  ), prepared AS (
    SELECT
      _version_id AS version_id,
      i.user_id,
      i.previous_received_at AS starts_at,
      i.received_at AS ends_at,
      i.timezone,
      i.utc_offset_minutes,
      CASE WHEN i.gap_minutes <= i.allowed_gap_minutes
        THEN 'valid' ELSE 'unknown' END AS coverage_state,
      i.received_at AS captured_at,
      _through_at AS finalized_at,
      encode(
        extensions.digest(
          jsonb_build_object(
            'version_id', _version_id,
            'user_id', i.user_id,
            'client_id', i.client_id,
            'channel', i.channel,
            'collector_contract', i.collector_contract,
            'collector_state', i.collector_state,
            'starts_at_utc', to_char(
              i.previous_received_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
            'ends_at_utc', to_char(
              i.received_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
            'capability_sha256', i.capability_sha256,
            'app_version', i.app_version,
            'timezone', i.timezone,
            'utc_offset_minutes', i.utc_offset_minutes,
            'coverage_state', CASE
              WHEN i.gap_minutes <= i.allowed_gap_minutes
                THEN 'valid' ELSE 'unknown'
            END,
            'evidence_version', 'coverage-lease-v1'
          )::text,
          'sha256'
        ),
        'hex'
      ) AS provenance_sha256
    FROM intervals AS i
  )
  INSERT INTO public.alert_observation_coverage_intervals (
    version_id, user_id, starts_at, ends_at, timezone, utc_offset_minutes,
    activity_coverage_state, intervention_coverage_state, sleep_context_state,
    captured_at, finalized_at, evidence_version, provenance_sha256
  )
  SELECT
    p.version_id, p.user_id, p.starts_at, p.ends_at, p.timezone,
    p.utc_offset_minutes, p.coverage_state,
    CASE WHEN p.coverage_state = 'valid' THEN 'valid' ELSE 'unknown' END,
    CASE WHEN p.coverage_state = 'valid' THEN 'valid' ELSE 'unknown' END,
    p.captured_at, p.finalized_at, 'coverage-lease-v1', p.provenance_sha256
  FROM prepared AS p
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.alert_observation_coverage_intervals AS existing
    WHERE existing.version_id = p.version_id
      AND existing.user_id = p.user_id
      AND existing.starts_at = p.starts_at
      AND existing.ends_at = p.ends_at
      AND existing.provenance_sha256 = p.provenance_sha256
  );
  GET DIAGNOSTICS _inserted = ROW_COUNT;

  RETURN jsonb_build_object(
    'status', 'completed',
    'inserted', _inserted,
    'deleted_leases', _deleted_leases,
    'deleted_intervals', _deleted_intervals,
    'through_at', _through_at,
    'retention_days', _retention_days
  );
END;
$$;


ALTER FUNCTION "private"."finalize_alert_shadow_coverage"("_user_id" "uuid", "_through_at" timestamp with time zone, "_retention_days" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."guardian_pair"("_a" "uuid", "_b" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select private.is_guardian_of(_a, _b) or private.is_guardian_of(_b, _a);
$$;


ALTER FUNCTION "private"."guardian_pair"("_a" "uuid", "_b" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."handle_profile_pattern_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if tg_op = 'INSERT' or new.routine_pattern <> old.routine_pattern then
    -- 1) Seed the aggregates data
    perform public.initialize_user_routine_data(new.id);
    -- 2) Call Edge Function to analyze routine pattern
    perform private.trigger_update_routine_profile(new.id);
  end if;
  return new;
end;
$$;


ALTER FUNCTION "private"."handle_profile_pattern_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."insert_behavior_ping"("_user_id" "uuid", "_event_id" "uuid", "_observed_at" timestamp with time zone, "_source" "text", "_kind" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  _received_at timestamptz := clock_timestamp();
  _is_live_safety boolean;
BEGIN
  IF _user_id IS NULL OR _observed_at IS NULL OR _event_id IS NULL THEN
    RETURN 'invalid';
  END IF;

  IF _source NOT IN (
    'installed_pwa',
    'tauri',
    'capacitor',
    'shortcut',
    'manual',
    'app'
  ) THEN
    RETURN 'invalid';
  END IF;

  IF _kind NOT IN (
    'app',
    'interaction',
    'steps',
    'unlock',
    'manual_checkin'
  ) THEN
    RETURN 'invalid';
  END IF;

  IF _observed_at > _received_at + interval '5 minutes' THEN
    RETURN 'invalid';
  END IF;

  -- Serialize retries for one event before inspecting the idempotency index.
  -- Distinct events intentionally do not serialize by time bucket.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      _user_id::text || ':event:' || _event_id::text,
      0
    )
  );

  IF EXISTS (
    SELECT 1
    FROM public.behavior_pings
    WHERE user_id = _user_id
      AND event_id = _event_id
  ) THEN
    RETURN 'duplicate';
  END IF;

  _is_live_safety := (
    abs(extract(epoch FROM (_received_at - _observed_at))) <= 300
  );

  BEGIN
    INSERT INTO public.behavior_pings (
      user_id,
      event_id,
      at,
      source,
      kind,
      received_at,
      ingest_version
    )
    VALUES (
      _user_id,
      _event_id,
      _observed_at,
      _source,
      _kind,
      _received_at,
      2
    );
  EXCEPTION WHEN unique_violation THEN
    IF EXISTS (
      SELECT 1
      FROM public.behavior_pings
      WHERE user_id = _user_id
        AND event_id = _event_id
    ) THEN
      RETURN 'duplicate';
    END IF;
    RAISE;
  END;

  IF _is_live_safety THEN
    PERFORM private.apply_liveness_side_effects(
      _user_id,
      _observed_at,
      _received_at
    );
  END IF;

  RETURN 'inserted';
END;
$$;


ALTER FUNCTION "private"."insert_behavior_ping"("_user_id" "uuid", "_event_id" "uuid", "_observed_at" timestamp with time zone, "_source" "text", "_kind" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "private"."insert_behavior_ping"("_user_id" "uuid", "_event_id" "uuid", "_observed_at" timestamp with time zone, "_source" "text", "_kind" "text") IS 'ADR-0029 P3 shared validator: one row per distinct event_id; no time-bucket coalescing.';



CREATE OR REPLACE FUNCTION "private"."insert_device_sample"("_user_id" "uuid", "_event_id" "uuid", "_payload" "jsonb") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  _observed_at timestamptz;
  _received_at timestamptz := clock_timestamp();
  _trigger text;
begin
  if _user_id is null or _event_id is null or _payload is null then
    return 'invalid';
  end if;

  _observed_at := (_payload ->> 'observed_at')::timestamptz;
  _trigger := _payload ->> 'trigger';

  if _observed_at is null or _trigger is null then
    return 'invalid';
  end if;

  if _observed_at > _received_at + interval '5 minutes' then
    return 'invalid';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(_user_id::text || ':sample:' || _event_id::text, 0)
  );

  if exists (
    select 1 from public.device_activity_samples
    where user_id = _user_id and id = _event_id
  ) then
    return 'duplicate';
  end if;

  insert into public.device_activity_samples (
    id, user_id, trigger, observed_at, received_at,
    protected_data_available, battery_level, battery_state, low_power_mode,
    system_uptime_seconds, other_audio_playing,
    motion_variance, motion_sample_count,
    steps_since_last_sample, floors_since_last_sample,
    dominant_activity, activity_confidence,
    volume_available_bytes,
    client_id, app_version, collector_contract
  ) values (
    _event_id, _user_id, _trigger, _observed_at, _received_at,
    (_payload ->> 'protected_data_available')::boolean,
    (_payload ->> 'battery_level')::real,
    _payload ->> 'battery_state',
    (_payload ->> 'low_power_mode')::boolean,
    (_payload ->> 'system_uptime_seconds')::double precision,
    (_payload ->> 'other_audio_playing')::boolean,
    (_payload ->> 'motion_variance')::double precision,
    (_payload ->> 'motion_sample_count')::integer,
    (_payload ->> 'steps_since_last_sample')::integer,
    (_payload ->> 'floors_since_last_sample')::integer,
    _payload ->> 'dominant_activity',
    (_payload ->> 'activity_confidence')::smallint,
    (_payload ->> 'volume_available_bytes')::bigint,
    _payload ->> 'client_id',
    _payload ->> 'app_version',
    coalesce(_payload ->> 'collector_contract', 'unknown')
  );

  return 'inserted';
exception
  when check_violation or invalid_text_representation then
    return 'invalid';
end;
$$;


ALTER FUNCTION "private"."insert_device_sample"("_user_id" "uuid", "_event_id" "uuid", "_payload" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."invalidate_routine_mode_cohort"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  _mode text;
  _generation bigint;
BEGIN
  IF TG_OP = 'UPDATE'
     AND OLD.routine_pattern IS NOT DISTINCT FROM NEW.routine_pattern
     AND OLD.consent_data_sharing IS NOT DISTINCT FROM NEW.consent_data_sharing THEN
    RETURN NEW;
  END IF;

  FOR _mode IN
    SELECT DISTINCT candidate.routine_mode
    FROM (
      SELECT CASE
        WHEN TG_OP = 'INSERT' THEN private.canonical_routine_mode(NEW.routine_pattern)
        WHEN TG_OP = 'DELETE' THEN private.canonical_routine_mode(OLD.routine_pattern)
        ELSE private.canonical_routine_mode(OLD.routine_pattern)
      END AS routine_mode
      UNION ALL
      SELECT CASE WHEN TG_OP = 'UPDATE' THEN private.canonical_routine_mode(NEW.routine_pattern) END
    ) AS candidate
    WHERE candidate.routine_mode IS NOT NULL
    ORDER BY candidate.routine_mode
  LOOP
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('keep-contact:routine-mode-cohort:' || _mode, 0)
    );

    UPDATE public.routine_mode_cohort_generations
    SET generation = generation + 1,
        updated_at = clock_timestamp()
    WHERE routine_mode = _mode
    RETURNING generation INTO _generation;

    INSERT INTO public.routine_mode_cohort_invalidations (routine_mode, invalidated_at, generation)
    VALUES (_mode, clock_timestamp(), _generation)
    ON CONFLICT (routine_mode) DO UPDATE
    SET invalidated_at = EXCLUDED.invalidated_at,
        generation = EXCLUDED.generation;
  END LOOP;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "private"."invalidate_routine_mode_cohort"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."invalidate_routine_mode_cohort_profile"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  _mode text;
  _generation bigint;
BEGIN
  -- Both sides matter: a key can stop being personal_global, start being it,
  -- or move between users/modes. Resolve current modes only, deduplicate them,
  -- then lock in lexical order before each single generation increment.
  FOR _mode IN
    WITH affected_users(user_id) AS (
      SELECT OLD.user_id
      WHERE TG_OP <> 'INSERT' AND OLD.context_key = 'personal_global'
      UNION
      SELECT NEW.user_id
      WHERE TG_OP <> 'DELETE' AND NEW.context_key = 'personal_global'
    )
    SELECT DISTINCT private.canonical_routine_mode(p.routine_pattern)
    FROM affected_users AS affected
    JOIN public.profiles AS p ON p.id = affected.user_id
    ORDER BY private.canonical_routine_mode(p.routine_pattern)
  LOOP
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('keep-contact:routine-mode-cohort:' || _mode, 0)
    );
    UPDATE public.routine_mode_cohort_generations
    SET generation = generation + 1,
        updated_at = clock_timestamp()
    WHERE routine_mode = _mode
    RETURNING generation INTO _generation;
    INSERT INTO public.routine_mode_cohort_invalidations (routine_mode, invalidated_at, generation)
    VALUES (_mode, clock_timestamp(), _generation)
    ON CONFLICT (routine_mode) DO UPDATE
    SET invalidated_at = EXCLUDED.invalidated_at,
        generation = EXCLUDED.generation;
  END LOOP;

  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "private"."invalidate_routine_mode_cohort_profile"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."is_admin"("_uid" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (select 1 from public.app_admins where user_id = _uid)
$$;


ALTER FUNCTION "private"."is_admin"("_uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."is_community_admin"("_community_id" "uuid", "_user" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1 from public.community_members cm
    where cm.community_id = _community_id
      and cm.user_id = _user
      and cm.role = 'admin'
      and cm.status = 'active'
  );
$$;


ALTER FUNCTION "private"."is_community_admin"("_community_id" "uuid", "_user" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."is_community_member"("_community_id" "uuid", "_user" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1 from public.community_members cm
    where cm.community_id = _community_id and cm.user_id = _user and cm.status = 'active'
  );
$$;


ALTER FUNCTION "private"."is_community_member"("_community_id" "uuid", "_user" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."is_group_admin"("_group_id" "uuid", "_user" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1 from public.group_members gm
    where gm.group_id = _group_id
      and gm.user_id = _user
      and gm.role = 'admin'
      and gm.status = 'active'
  );
$$;


ALTER FUNCTION "private"."is_group_admin"("_group_id" "uuid", "_user" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."is_group_member"("_group_id" "uuid", "_user" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1 from public.group_members gm
    where gm.group_id = _group_id and gm.user_id = _user and gm.status = 'active'
  );
$$;


ALTER FUNCTION "private"."is_group_member"("_group_id" "uuid", "_user" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."is_guardian_of"("_ward" "uuid", "_guardian" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1 from public.guardianships g
    where g.ward_id = _ward and g.guardian_id = _guardian and g.status = 'active'
  );
$$;


ALTER FUNCTION "private"."is_guardian_of"("_ward" "uuid", "_guardian" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."is_in_sleep_window"("_user_id" "uuid", "_now" timestamp with time zone) RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  _start      time;
  _end        time;
  _timezone   text;
  _local_now  timestamptz;
  _local_time time;
  _local_date date;
  _start_ts   timestamptz;
  _end_ts     timestamptz;
  _dur        interval;
  _last_active    timestamptz;
  _dynamic_end    timestamptz;
BEGIN
  SELECT sleep_start_local, sleep_end_local, coalesce(timezone, 'UTC')
    INTO _start, _end, _timezone
    FROM public.user_settings
   WHERE user_id = _user_id;

  IF _start IS NULL OR _end IS NULL THEN
    RETURN false;
  END IF;

  -- Convert _now into user's local timezone (wall-clock)
  _local_now  := _now at time zone _timezone;
  _local_time := _local_now::time;
  _local_date := _local_now::date;

  -- Build start/end timestamps anchored to local date, handling overnight windows
  IF _start > _end THEN
    -- Overnight (e.g. 23:00 -> 07:00)
    IF _local_time < _end THEN
      _start_ts := (_local_date - 1 + _start) at time zone _timezone;
      _end_ts   := (_local_date     + _end  ) at time zone _timezone;
    ELSE
      _start_ts := (_local_date     + _start) at time zone _timezone;
      _end_ts   := (_local_date + 1 + _end  ) at time zone _timezone;
    END IF;
  ELSE
    -- Same-day (e.g. 14:00 -> 16:00 nap)
    IF _local_time < _start THEN
      _start_ts := (_local_date - 1 + _start) at time zone _timezone;
      _end_ts   := (_local_date - 1 + _end  ) at time zone _timezone;
    ELSE
      _start_ts := (_local_date + _start) at time zone _timezone;
      _end_ts   := (_local_date + _end  ) at time zone _timezone;
    END IF;
  END IF;

  _dur := _end_ts - _start_ts;

  -- Dynamic extension: if user pinged shortly before sleep started
  -- Using trusted v2 received_at evidence only (with drift checks)
  SELECT max(received_at) INTO _last_active
    FROM public.behavior_pings
   WHERE user_id = _user_id
     AND ingest_version = 2
     AND abs(extract(epoch from (received_at - at))) <= 300;

  IF _last_active IS NOT NULL THEN
    IF _last_active >= _start_ts - interval '1 hour' AND _last_active <= _end_ts THEN
      _dynamic_end := least(_last_active + _dur, _end_ts + interval '3 hours');
      RETURN _now >= _start_ts AND _now < _dynamic_end;
    END IF;
  END IF;

  RETURN _now >= _start_ts AND _now < _end_ts;
END;
$$;


ALTER FUNCTION "private"."is_in_sleep_window"("_user_id" "uuid", "_now" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."maintain_adaptive_alert_shadow"("_through_at" timestamp with time zone, "_max_rows" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    AS $$
DECLARE
  _deleted integer := 0;
  _step integer := 0;
  _reported integer := 0;
BEGIN
  IF _through_at IS NULL OR _max_rows IS NULL
     OR _max_rows NOT BETWEEN 1 AND 100000 THEN
    RAISE EXCEPTION 'invalid shadow maintenance arguments';
  END IF;

  WITH doomed AS (
    SELECT c.id
    FROM public.alert_judgment_subject_contexts AS c
    WHERE coalesce(c.effective_to, c.captured_at)
      < _through_at - interval '35 days'
    ORDER BY coalesce(c.effective_to, c.captured_at), c.id
    LIMIT _max_rows
  )
  DELETE FROM public.alert_judgment_subject_contexts AS c
  WHERE c.id IN (SELECT d.id FROM doomed AS d);
  GET DIAGNOSTICS _step = ROW_COUNT;
  _deleted := _deleted + _step;

  WITH doomed AS (
    SELECT e.id
    FROM public.alert_intervention_events AS e
    WHERE e.occurred_at < _through_at - interval '35 days'
    ORDER BY e.occurred_at, e.id
    LIMIT greatest(_max_rows - _deleted, 0)
  )
  DELETE FROM public.alert_intervention_events AS e
  WHERE e.id IN (SELECT d.id FROM doomed AS d);
  GET DIAGNOSTICS _step = ROW_COUNT;
  _deleted := _deleted + _step;

  WITH doomed AS (
    SELECT d.id
    FROM public.alert_judgment_shadow_decisions AS d
    WHERE d.evaluated_at < _through_at - interval '35 days'
    ORDER BY d.evaluated_at, d.id
    LIMIT greatest(_max_rows - _deleted, 0)
  )
  DELETE FROM public.alert_judgment_shadow_decisions AS d
  WHERE d.id IN (SELECT doomed.id FROM doomed);
  GET DIAGNOSTICS _step = ROW_COUNT;
  _deleted := _deleted + _step;

  WITH doomed AS (
    SELECT l.user_id, l.event_id
    FROM private.alert_shadow_coverage_leases AS l
    WHERE l.received_at < _through_at - interval '35 days'
    ORDER BY l.received_at, l.user_id, l.event_id
    LIMIT greatest(_max_rows - _deleted, 0)
  )
  DELETE FROM private.alert_shadow_coverage_leases AS l
  WHERE (l.user_id, l.event_id) IN (
    SELECT doomed.user_id, doomed.event_id FROM doomed
  );
  GET DIAGNOSTICS _step = ROW_COUNT;
  _deleted := _deleted + _step;

  WITH doomed AS (
    SELECT c.id
    FROM public.alert_observation_coverage_intervals AS c
    WHERE c.ends_at < _through_at - interval '35 days'
    ORDER BY c.ends_at, c.id
    LIMIT greatest(_max_rows - _deleted, 0)
  )
  DELETE FROM public.alert_observation_coverage_intervals AS c
  WHERE c.id IN (SELECT doomed.id FROM doomed);
  GET DIAGNOSTICS _step = ROW_COUNT;
  _deleted := _deleted + _step;

  WITH doomed AS (
    SELECT s.version_id, s.user_id
    FROM private.adaptive_alert_shadow_user_state AS s
    WHERE s.evaluated_at < _through_at - interval '35 days'
    ORDER BY s.evaluated_at, s.version_id, s.user_id
    LIMIT greatest(_max_rows - _deleted, 0)
  )
  DELETE FROM private.adaptive_alert_shadow_user_state AS s
  WHERE (s.version_id, s.user_id) IN (
    SELECT doomed.version_id, doomed.user_id FROM doomed
  );
  GET DIAGNOSTICS _step = ROW_COUNT;
  _deleted := _deleted + _step;

  WITH doomed AS (
    SELECT s.version_id, s.user_id
    FROM private.adaptive_alert_shadow_subject_context_state AS s
    WHERE s.captured_at < _through_at - interval '35 days'
    ORDER BY s.captured_at, s.version_id, s.user_id
    LIMIT greatest(_max_rows - _deleted, 0)
  )
  DELETE FROM private.adaptive_alert_shadow_subject_context_state AS s
  WHERE (s.version_id, s.user_id) IN (
    SELECT doomed.version_id, doomed.user_id FROM doomed
  );
  GET DIAGNOSTICS _step = ROW_COUNT;
  _deleted := _deleted + _step;

  INSERT INTO private.adaptive_alert_shadow_cohort_dirty (
    version_id, routine_mode, context_key, invalidated_at, reason
  )
  SELECT
    v.id, i.routine_mode, '*', i.invalidated_at, 'source_invalidation'
  FROM public.alert_model_versions AS v
  CROSS JOIN public.routine_mode_cohort_invalidations AS i
  WHERE v.status = 'shadow'
  ON CONFLICT (version_id, routine_mode, context_key) DO UPDATE SET
    invalidated_at = greatest(
      private.adaptive_alert_shadow_cohort_dirty.invalidated_at,
      excluded.invalidated_at
    ),
    reason = excluded.reason;

  DELETE FROM public.routine_mode_cohort_priors AS p
  WHERE p.version_id IN (
      SELECT v.id FROM public.alert_model_versions AS v
      WHERE v.status = 'shadow'
    )
    AND EXISTS (
      SELECT 1
      FROM private.adaptive_alert_shadow_cohort_dirty AS d
      WHERE d.version_id = p.version_id
        AND d.routine_mode = p.routine_mode
        AND (d.context_key = '*' OR d.context_key = p.context_key)
        AND d.invalidated_at >= p.published_at
    );

  WITH report AS (
    SELECT
      v.id AS version_id,
      count(s.user_id)::integer AS contributor_count,
      count(*) FILTER (WHERE s.replayable)::integer AS replayable_count,
      count(*) FILTER (WHERE s.would_alert IS TRUE)::integer AS would_alert_count
    FROM public.alert_model_versions AS v
    LEFT JOIN private.adaptive_alert_shadow_user_state AS s
      ON s.version_id = v.id
     AND s.evaluated_at >= date_trunc('day', _through_at)
     AND s.evaluated_at < date_trunc('day', _through_at) + interval '1 day'
    WHERE v.status = 'shadow'
    GROUP BY v.id
  ), prepared AS (
    SELECT
      r.version_id,
      (_through_at AT TIME ZONE 'UTC')::date AS report_date,
      CASE WHEN r.contributor_count < 10 THEN 'other' ELSE 'all' END AS segment_key,
      r.contributor_count,
      r.contributor_count < 10 AS suppressed,
      CASE WHEN r.contributor_count < 10
        THEN jsonb_build_object('suppressed', true)
        ELSE jsonb_build_object(
          'replayable_count', r.replayable_count,
          'would_alert_count', r.would_alert_count
        )
      END AS metrics
    FROM report AS r
  )
  INSERT INTO private.adaptive_alert_shadow_daily_reports (
    version_id, report_date, segment_key, contributor_count, suppressed,
    metrics, report_sha256
  )
  SELECT
    p.version_id, p.report_date, p.segment_key, p.contributor_count,
    p.suppressed, p.metrics,
    encode(extensions.digest(jsonb_build_object(
      'version_id', p.version_id,
      'report_date', p.report_date,
      'segment_key', p.segment_key,
      'contributor_count', p.contributor_count,
      'suppressed', p.suppressed,
      'metrics', p.metrics
    )::text, 'sha256'), 'hex')
  FROM prepared AS p
  ON CONFLICT (version_id, report_date, segment_key) DO UPDATE SET
    contributor_count = excluded.contributor_count,
    suppressed = excluded.suppressed,
    metrics = excluded.metrics,
    report_sha256 = excluded.report_sha256,
    created_at = clock_timestamp();
  GET DIAGNOSTICS _reported = ROW_COUNT;

  RETURN jsonb_build_object(
    'status', 'completed',
    'deleted_count', _deleted,
    'reported_count', _reported
  );
END;
$$;


ALTER FUNCTION "private"."maintain_adaptive_alert_shadow"("_through_at" timestamp with time zone, "_max_rows" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."mark_adaptive_alert_shadow_dirty"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    AS $$
DECLARE
  _user_id uuid;
  _routine_mode text;
  _reason text;
  _changed_at timestamptz := clock_timestamp();
BEGIN
  IF TG_TABLE_NAME = 'profiles' THEN
    _user_id := NEW.id;
    _routine_mode := coalesce(NEW.routine_pattern, 'regular_9to5');
    _reason := CASE
      WHEN TG_OP = 'UPDATE'
       AND OLD.consent_data_sharing
       AND NOT NEW.consent_data_sharing
      THEN 'consent_withdrawn'
      ELSE 'profile_changed'
    END;
  ELSE
    _user_id := NEW.user_id;
    SELECT coalesce(p.routine_pattern, 'regular_9to5')
      INTO _routine_mode
    FROM public.profiles AS p WHERE p.id = _user_id;
    _routine_mode := coalesce(_routine_mode, 'regular_9to5');
    _reason := 'settings_changed';
  END IF;

  INSERT INTO private.adaptive_alert_shadow_profile_dirty (
    version_id, user_id, invalidated_at, reason
  )
  SELECT v.id, _user_id, _changed_at, _reason
  FROM public.alert_model_versions AS v
  WHERE v.status = 'shadow'
  ON CONFLICT (version_id, user_id) DO UPDATE SET
    invalidated_at = greatest(
      private.adaptive_alert_shadow_profile_dirty.invalidated_at,
      excluded.invalidated_at
    ),
    reason = excluded.reason;

  INSERT INTO private.adaptive_alert_shadow_cohort_dirty (
    version_id, routine_mode, context_key, invalidated_at, reason
  )
  SELECT v.id, _routine_mode, '*', _changed_at, _reason
  FROM public.alert_model_versions AS v
  WHERE v.status = 'shadow'
  ON CONFLICT (version_id, routine_mode, context_key) DO UPDATE SET
    invalidated_at = greatest(
      private.adaptive_alert_shadow_cohort_dirty.invalidated_at,
      excluded.invalidated_at
    ),
    reason = excluded.reason;

  IF _reason = 'consent_withdrawn' THEN
    DELETE FROM public.routine_mode_cohort_priors
    WHERE routine_mode = _routine_mode
      AND version_id IN (
        SELECT v.id FROM public.alert_model_versions AS v
        WHERE v.status = 'shadow'
      );
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "private"."mark_adaptive_alert_shadow_dirty"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."normalized_behavior_training_sessions"("_user_id" "uuid", "_from" timestamp with time zone, "_to" timestamp with time zone, "_version_id" "uuid") RETURNS TABLE("session_start" timestamp with time zone, "session_end" timestamp with time zone, "context_key" "text", "evidence_count" integer, "source_ingest_version" smallint, "training_provenance" "text", "provenance_sha256" "text", "quality_state" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    AS $$
DECLARE
  _config jsonb;
  _status text;
  _evidence_version text;
  _config_sha256 text;
  _gap_minutes integer;
  _historical_v1_policy text;
BEGIN
  IF _user_id IS NULL
     OR _version_id IS NULL
     OR _from IS NULL
     OR _to IS NULL
     OR _from >= _to THEN
    RETURN;
  END IF;

  SELECT config, status, evidence_version, config_sha256
    INTO _config, _status, _evidence_version, _config_sha256
  FROM public.alert_model_versions
  WHERE id = _version_id;

  IF NOT FOUND
     OR _status NOT IN ('replay', 'shadow')
     OR _evidence_version <> 'canonical-v2'
     OR _config_sha256
       <> encode(extensions.digest(_config::text, 'sha256'), 'hex') THEN
    RETURN;
  END IF;

  BEGIN
    _gap_minutes :=
      (_config #>> '{sessionization,gap_minutes}')::integer;
    _historical_v1_policy := coalesce(
      _config #>> '{sessionization,historical_v1_policy}',
      'disabled'
    );
  EXCEPTION
    WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      RETURN;
  END;

  IF _gap_minutes <= 0
     OR _historical_v1_policy NOT IN (
       'disabled',
       'sessionized_training_only_v1'
     ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH canonical AS (
    SELECT
      s.session_start,
      s.session_end,
      s.context_key,
      s.evidence_count,
      2::smallint AS source_ingest_version,
      'canonical_v2'::text AS training_provenance,
      encode(
        extensions.digest(
          jsonb_build_object(
            'version_id', _version_id,
            'config_sha256', _config_sha256,
            'source_ingest_version', 2,
            'training_provenance', 'canonical_v2',
            'session_start_utc',
              to_char(
                s.session_start AT TIME ZONE 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
              ),
            'session_end_utc',
              to_char(
                s.session_end AT TIME ZONE 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
              ),
            'context_key', s.context_key,
            'evidence_count', s.evidence_count,
            'quality_state', s.quality_state
          )::text,
          'sha256'
        ),
        'hex'
      ) AS provenance_sha256,
      s.quality_state
    FROM private.qualified_behavior_sessions(
      _user_id,
      _from,
      _to,
      _version_id
    ) AS s
  ),
  historical_admitted AS (
    SELECT
      p.id,
      p.at,
      p.kind,
      p.source,
      p.received_at,
      p.event_id,
      p.ingest_version
    FROM public.behavior_pings AS p
    WHERE _historical_v1_policy = 'sessionized_training_only_v1'
      AND p.user_id = _user_id
      AND p.ingest_version = 1
      AND p.at >= _from
      AND p.at < _to
  ),
  historical_marked AS (
    SELECT
      a.*,
      CASE
        WHEN lag(a.at) OVER (ORDER BY a.at, a.id) IS NULL
          OR a.at - lag(a.at) OVER (ORDER BY a.at, a.id)
            > make_interval(mins => _gap_minutes)
          THEN 1
        ELSE 0
      END AS starts_session
    FROM historical_admitted AS a
  ),
  historical_grouped AS (
    SELECT
      m.*,
      sum(m.starts_session) OVER (ORDER BY m.at, m.id) AS session_no
    FROM historical_marked AS m
  ),
  historical_summarized AS (
    SELECT
      min(g.at) AS session_start,
      max(g.at) AS session_end,
      count(*)::integer AS evidence_count,
      jsonb_agg(
        jsonb_build_object(
          'id', g.id,
          'at_utc',
            to_char(
              g.at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
          'kind', g.kind,
          'source', g.source,
          'received_at_utc',
            to_char(
              g.received_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
          'event_id', g.event_id,
          'ingest_version', g.ingest_version
        )
        ORDER BY g.at, g.id
      ) AS source_rows
    FROM historical_grouped AS g
    GROUP BY g.session_no
  ),
  historical AS (
    SELECT
      s.session_start,
      s.session_end,
      NULL::text AS context_key,
      s.evidence_count,
      1::smallint AS source_ingest_version,
      'historical_v1_training_only'::text AS training_provenance,
      encode(
        extensions.digest(
          jsonb_build_object(
            'version_id', _version_id,
            'config_sha256', _config_sha256,
            'source_ingest_version', 1,
            'training_provenance', 'historical_v1_training_only',
            'source_rows', s.source_rows
          )::text,
          'sha256'
        ),
        'hex'
      ) AS provenance_sha256,
      'valid'::text AS quality_state
    FROM historical_summarized AS s
  )
  SELECT * FROM canonical
  UNION ALL
  SELECT * FROM historical
  ORDER BY session_start, source_ingest_version;
END;
$$;


ALTER FUNCTION "private"."normalized_behavior_training_sessions"("_user_id" "uuid", "_from" timestamp with time zone, "_to" timestamp with time zone, "_version_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."notify_auto_resolved"("_alert_id" "uuid", "_target" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare _tname text;
begin
  select coalesce(display_name, '') into _tname from public.profiles where id = _target;
  insert into public.notifications (recipient_id, alert_id, kind, body, params)
  select distinct s.r, _alert_id, 'auto_resolved',
    coalesce(nullif(_tname, ''), '成员') || ' 的告警已自动解除(检测到活动恢复)。',
    jsonb_build_object('target', _tname)
  from (
    select _target as r
    union
    select w.user_id from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _target and t.monitored and t.status = 'active'
        and w.watching and w.status = 'active'
    union
    select g.guardian_id from public.guardianships g
      where g.ward_id = _target and g.status = 'active'
  ) s;
end;
$$;


ALTER FUNCTION "private"."notify_auto_resolved"("_alert_id" "uuid", "_target" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."notify_stage"("_alert_id" "uuid", "_user" "uuid", "_stage" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare _name text; _p jsonb; _sos boolean;
begin
  select coalesce(display_name,'') into _name from public.profiles where id = _user;
  select (cause = 'sos') into _sos from public.alerts where id = _alert_id;
  _p := jsonb_build_object('name', _name);

  -- 本人由本机 overlay 提示报平安,不发服务器通知给自己
  if _stage = 'self' then
    return;
  end if;

  if _stage = 'group' then
    insert into public.notifications (recipient_id, alert_id, kind, body, params)
    select distinct s.r, _alert_id,
      case when _sos then 'sos' else 'group' end,
      case when _sos
        then '🆘 ' || _name || ' 发出紧急求救(SOS)！请立即联系并尽快前往确认。'
        else _name || ' 出现异常沉默，请尽快联系确认其安全。' end,
      _p
    from (
      select w.user_id as r
      from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _user and t.monitored and t.status = 'active'
        and w.watching and w.status = 'active' and w.user_id <> _user
      union
      select g.guardian_id from public.guardianships g
      where g.ward_id = _user and g.status = 'active'
    ) s;

  elsif _stage = 'community' then
    insert into public.notifications (recipient_id, alert_id, kind, body, params)
    select distinct y.user_id, _alert_id,
      case when _sos then 'sos' else 'community' end,
      case when _sos
        then '🆘 社区紧急：' || _name || ' 发出 SOS 求救且小组未及时响应，请立即协助联系。'
        else '社区警示：' || _name || ' 长时间失联且其小组无人响应，请协助推动联系。' end,
      _p
    from public.community_members x
    join public.community_members y on x.community_id = y.community_id
    where x.user_id = _user and x.status = 'active'
      and y.status = 'active' and y.user_id <> _user;

  elsif _stage = 'terminal' then
    insert into public.notifications (recipient_id, alert_id, kind, body, params)
    select distinct s.r, _alert_id,
      case when _sos then 'sos' else 'terminal' end,
      case when _sos
        then '🆘 紧急：' || _name || ' SOS 求救且持续无响应。已为你解锁其地址与紧急联系人，请立即上门或协助报警。'
        else '紧急：' || _name || ' 持续无响应。已为你解锁其地址与紧急联系人，请上门探视或协助报警。' end,
      _p
    from (
      select w.user_id as r
      from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _user and t.monitored and t.status = 'active'
        and w.watching and w.status = 'active' and w.user_id <> _user
      union
      select g.guardian_id from public.guardianships g
      where g.ward_id = _user and g.status = 'active'
    ) s;
  end if;
end;
$$;


ALTER FUNCTION "private"."notify_stage"("_alert_id" "uuid", "_user" "uuid", "_stage" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."pin_alert_gap_profile_contract"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
BEGIN
  SELECT version.config_sha256, version.evidence_version
    INTO NEW.config_sha256, NEW.evidence_version
  FROM public.alert_model_versions AS version
  WHERE version.id = NEW.version_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'unknown alert model version %', NEW.version_id
      USING ERRCODE = '23503';
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "private"."pin_alert_gap_profile_contract"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."qualified_behavior_sessions"("_user_id" "uuid", "_from" timestamp with time zone, "_to" timestamp with time zone, "_version_id" "uuid") RETURNS TABLE("session_start" timestamp with time zone, "session_end" timestamp with time zone, "context_key" "text", "evidence_count" integer, "quality_state" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    AS $$
DECLARE
  _config jsonb;
  _status text;
  _evidence_version text;
  _config_sha256 text;
  _gap_minutes integer;
  _intervention_minutes integer;
  _definition text;
  _day_partition text;
  _bucket_minutes integer;
BEGIN
  IF _user_id IS NULL OR _version_id IS NULL OR _from IS NULL OR _to IS NULL OR _from >= _to THEN
    RETURN;
  END IF;

  SELECT config, status, evidence_version, config_sha256
    INTO _config, _status, _evidence_version, _config_sha256
  FROM public.alert_model_versions
  WHERE id = _version_id;

  IF NOT FOUND
     OR _status NOT IN ('replay', 'shadow')
     OR _evidence_version <> 'canonical-v2'
     OR _config_sha256 <> encode(extensions.digest(_config::text, 'sha256'), 'hex') THEN
    RETURN;
  END IF;

  BEGIN
    _gap_minutes := (_config #>> '{sessionization,gap_minutes}')::integer;
    _intervention_minutes := (_config #>> '{sessionization,intervention_window_minutes}')::integer;
    _definition := _config #>> '{context,definition_version}';
    _day_partition := _config #>> '{context,day_partition}';
    _bucket_minutes := (_config #>> '{context,hour_bucket_minutes}')::integer;
  EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
    RETURN;
  END;

  IF _gap_minutes <= 0 OR _intervention_minutes < 0 OR _definition IS NULL
     OR _day_partition NOT IN ('all_days', 'weekday_weekend')
     OR _bucket_minutes <= 0 OR mod(1440, _bucket_minutes) <> 0 THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH admitted AS (
    SELECT p.id, p.received_at, c.id AS coverage_id, c.timezone, c.utc_offset_minutes
    FROM public.behavior_pings AS p
    JOIN public.alert_observation_coverage_intervals AS c
      ON c.version_id = _version_id
     AND c.user_id = _user_id
     AND c.starts_at <= p.received_at
     AND c.ends_at > p.received_at
     AND c.activity_coverage_state = 'valid'
     AND c.intervention_coverage_state = 'valid'
     AND c.sleep_context_state = 'valid'
     AND c.evidence_version = 'canonical-v2'
     AND c.finalized_at IS NOT NULL
     AND c.finalized_at >= c.ends_at
     AND c.finalized_at < _to
    CROSS JOIN LATERAL (
      SELECT count(*) AS matching_coverage
      FROM public.alert_observation_coverage_intervals AS cc
      WHERE cc.version_id = _version_id
        AND cc.user_id = _user_id
        AND cc.starts_at <= p.received_at
        AND cc.ends_at > p.received_at
        AND cc.activity_coverage_state = 'valid'
        AND cc.intervention_coverage_state = 'valid'
        AND cc.sleep_context_state = 'valid'
        AND cc.evidence_version = 'canonical-v2'
        AND cc.finalized_at IS NOT NULL
        AND cc.finalized_at >= cc.ends_at
        AND cc.finalized_at < _to
    ) AS coverage_count
    WHERE p.user_id = _user_id
      AND p.ingest_version = 2
      AND p.received_at >= _from
      AND p.received_at < _to
      AND p.at < _to
      AND abs(extract(epoch FROM (p.received_at - p.at))) <= 300
      AND coverage_count.matching_coverage = 1
      AND EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names z WHERE z.name = c.timezone)
      AND floor(extract(epoch FROM (((p.received_at AT TIME ZONE c.timezone) AT TIME ZONE 'UTC') - p.received_at)) / 60)::integer = c.utc_offset_minutes
  ), marked AS (
    SELECT *, CASE WHEN lag(received_at) OVER (ORDER BY received_at, id) IS NULL
                       OR received_at - lag(received_at) OVER (ORDER BY received_at, id) > make_interval(mins => _gap_minutes)
                       OR coverage_id IS DISTINCT FROM lag(coverage_id) OVER (ORDER BY received_at, id)
                       OR timezone IS DISTINCT FROM lag(timezone) OVER (ORDER BY received_at, id)
                       OR utc_offset_minutes IS DISTINCT FROM lag(utc_offset_minutes) OVER (ORDER BY received_at, id)
                    THEN 1 ELSE 0 END AS starts_session
    FROM admitted
  ), grouped AS (
    SELECT *, sum(starts_session) OVER (ORDER BY received_at, id) AS session_no
    FROM marked
  ), summarized AS (
    SELECT min(received_at) AS session_start,
      max(received_at) AS session_end,
      (array_agg(timezone ORDER BY received_at, id))[1] AS timezone,
      count(*)::integer AS evidence_count
    FROM grouped
    GROUP BY session_no
  )
  SELECT s.session_start,
    s.session_end,
    concat(
      _definition, ':',
      CASE WHEN _day_partition = 'all_days' THEN 'all_days'
           WHEN extract(isodow FROM s.session_start AT TIME ZONE s.timezone) BETWEEN 1 AND 5 THEN 'weekday'
           ELSE 'weekend' END,
      ':h', lpad((floor(((extract(hour FROM s.session_start AT TIME ZONE s.timezone) * 60 + extract(minute FROM s.session_start AT TIME ZONE s.timezone)) / _bucket_minutes))::integer * _bucket_minutes)::text, 4, '0')
    )::text AS context_key,
    s.evidence_count,
    CASE WHEN EXISTS (
      SELECT 1 FROM public.alert_intervention_events AS i
      WHERE i.version_id = _version_id
        AND i.user_id = _user_id
        AND i.evidence_version = 'canonical-v2'
        AND i.occurred_at >= s.session_start - make_interval(mins => _intervention_minutes)
        AND i.occurred_at <= s.session_start
        AND i.captured_at < _to
    ) THEN 'intervention_excluded' ELSE 'valid' END::text AS quality_state
  FROM summarized AS s
  ORDER BY s.session_start;
END;
$$;


ALTER FUNCTION "private"."qualified_behavior_sessions"("_user_id" "uuid", "_from" timestamp with time zone, "_to" timestamp with time zone, "_version_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."rebuild_account_gap_profiles"("_through_date" "date" DEFAULT NULL::"date", "_lookback_days" integer DEFAULT 30, "_shrinkage_k" integer DEFAULT 50, "_percentile" numeric DEFAULT 0.95, "_cohort_min_gaps" integer DEFAULT 30, "_cohort_min_contributors" integer DEFAULT 2, "_cohort_fallback_minutes" integer DEFAULT 90, "_cohort_requires_consent" boolean DEFAULT true) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
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


ALTER FUNCTION "private"."rebuild_account_gap_profiles"("_through_date" "date", "_lookback_days" integer, "_shrinkage_k" integer, "_percentile" numeric, "_cohort_min_gaps" integer, "_cohort_min_contributors" integer, "_cohort_fallback_minutes" integer, "_cohort_requires_consent" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."rebuild_account_normal_bounds"("_through_date" "date" DEFAULT NULL::"date", "_lookback_days" integer DEFAULT 30, "_false_alarm_budget" numeric DEFAULT 1, "_buffer_high" integer DEFAULT 0, "_buffer_balanced" integer DEFAULT 45, "_buffer_low" integer DEFAULT 90, "_post_wake_grace_minutes" integer DEFAULT 120) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
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


ALTER FUNCTION "private"."rebuild_account_normal_bounds"("_through_date" "date", "_lookback_days" integer, "_false_alarm_budget" numeric, "_buffer_high" integer, "_buffer_balanced" integer, "_buffer_low" integer, "_post_wake_grace_minutes" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."rebuild_alert_gap_profiles"("_version_id" "uuid", "_through_date" "date") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    AS $$
DECLARE
  _config jsonb;
  _status text;
  _evidence_version text;
  _config_sha256 text;
  _historical_v1_policy text;
  _horizon_days integer;
  _daily_cap integer;
  _min_samples integer;
  _min_dates integer;
  _min_span integer;
  _max_age integer;
  _cutoff timestamptz;
  _from timestamptz;
  _profiles_written integer := 0;
  _profiles_deleted integer := 0;
  _completed_gaps integer := 0;
BEGIN
  IF _version_id IS NULL OR _through_date IS NULL THEN
    RETURN jsonb_build_object(
      'profiles_written', 0,
      'profiles_deleted', 0,
      'completed_gaps', 0,
      'explicit_quiet_minutes', 0
    );
  END IF;

  SELECT config, status, evidence_version, config_sha256
    INTO _config, _status, _evidence_version, _config_sha256
  FROM public.alert_model_versions
  WHERE id = _version_id;

  IF NOT FOUND
     OR _status NOT IN ('replay', 'shadow')
     OR _evidence_version <> 'canonical-v2'
     OR _config_sha256
       <> encode(extensions.digest(_config::text, 'sha256'), 'hex') THEN
    RETURN jsonb_build_object(
      'profiles_written', 0,
      'profiles_deleted', 0,
      'completed_gaps', 0,
      'explicit_quiet_minutes', 0
    );
  END IF;

  BEGIN
    _historical_v1_policy := coalesce(
      _config #>> '{sessionization,historical_v1_policy}',
      'disabled'
    );
    _horizon_days :=
      (_config #>> '{sessionization,training_horizon_days}')::integer;
    _daily_cap :=
      (_config #>> '{sessionization,per_user_day_gap_cap}')::integer;
    _min_samples := (_config #>> '{personal,min_samples}')::integer;
    _min_dates := (_config #>> '{personal,min_support_dates}')::integer;
    _min_span := (_config #>> '{personal,min_span_days}')::integer;
    _max_age := (_config #>> '{personal,max_age_days}')::integer;
  EXCEPTION
    WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      RETURN jsonb_build_object(
        'profiles_written', 0,
        'profiles_deleted', 0,
        'completed_gaps', 0,
        'explicit_quiet_minutes', 0
      );
  END;

  IF _historical_v1_policy NOT IN (
       'disabled',
       'sessionized_training_only_v1'
     )
     OR _horizon_days <= 0
     OR _daily_cap <= 0
     OR _min_samples <= 0
     OR _min_dates <= 0
     OR _min_span <= 0
     OR _max_age <= 0 THEN
    RETURN jsonb_build_object(
      'profiles_written', 0,
      'profiles_deleted', 0,
      'completed_gaps', 0,
      'explicit_quiet_minutes', 0
    );
  END IF;

  _cutoff := ((_through_date + 1)::timestamp AT TIME ZONE 'UTC');
  _from := _cutoff - make_interval(days => _horizon_days);

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      _version_id::text || ':' || _through_date::text,
      0
    )
  );

  DROP TABLE IF EXISTS pg_temp._alert_gap_profile_build;

  CREATE TEMP TABLE _alert_gap_profile_build ON COMMIT DROP AS
  WITH users AS (
    SELECT DISTINCT c.user_id
    FROM public.alert_observation_coverage_intervals AS c
    WHERE c.version_id = _version_id
      AND c.starts_at < _cutoff
      AND c.ends_at > _from
    UNION
    SELECT DISTINCT p.user_id
    FROM public.behavior_pings AS p
    WHERE _historical_v1_policy = 'sessionized_training_only_v1'
      AND p.ingest_version = 1
      AND p.at >= _from
      AND p.at < _cutoff
  ),
  sessions AS (
    SELECT
      u.user_id,
      s.*
    FROM users AS u
    CROSS JOIN LATERAL private.normalized_behavior_training_sessions(
      u.user_id,
      _from,
      _cutoff,
      _version_id
    ) AS s
  ),
  paired AS (
    SELECT
      s.*,
      lead(s.session_start) OVER (
        PARTITION BY
          s.user_id,
          s.source_ingest_version,
          s.training_provenance
        ORDER BY s.session_start
      ) AS next_start,
      lead(s.quality_state) OVER (
        PARTITION BY
          s.user_id,
          s.source_ingest_version,
          s.training_provenance
        ORDER BY s.session_start
      ) AS next_quality,
      lead(s.provenance_sha256) OVER (
        PARTITION BY
          s.user_id,
          s.source_ingest_version,
          s.training_provenance
        ORDER BY s.session_start
      ) AS next_session_provenance_sha256
    FROM sessions AS s
  ),
  coverage_gaps AS (
    SELECT
      p.user_id,
      p.session_end,
      p.next_start,
      p.context_key,
      c.id AS coverage_id,
      c.timezone,
      c.utc_offset_minutes,
      c.provenance_sha256 AS coverage_provenance_sha256,
      p.source_ingest_version,
      p.training_provenance,
      p.provenance_sha256 AS session_provenance_sha256,
      p.next_session_provenance_sha256
    FROM paired AS p
    JOIN public.alert_observation_coverage_intervals AS c
      ON c.version_id = _version_id
     AND c.user_id = p.user_id
     AND c.starts_at <= p.session_end
     AND c.ends_at >= p.next_start
     AND c.activity_coverage_state = 'valid'
     AND c.intervention_coverage_state = 'valid'
     AND c.sleep_context_state = 'valid'
     AND c.evidence_version = 'canonical-v2'
     AND c.finalized_at IS NOT NULL
     AND c.finalized_at >= c.ends_at
     AND c.finalized_at < _cutoff
    CROSS JOIN LATERAL (
      SELECT count(*) AS matching_coverage
      FROM public.alert_observation_coverage_intervals AS cc
      WHERE cc.version_id = _version_id
        AND cc.user_id = p.user_id
        AND cc.starts_at <= p.session_end
        AND cc.ends_at >= p.next_start
        AND cc.activity_coverage_state = 'valid'
        AND cc.intervention_coverage_state = 'valid'
        AND cc.sleep_context_state = 'valid'
        AND cc.evidence_version = 'canonical-v2'
        AND cc.finalized_at IS NOT NULL
        AND cc.finalized_at >= cc.ends_at
        AND cc.finalized_at < _cutoff
    ) AS coverage_count
    WHERE p.source_ingest_version = 2
      AND p.next_start IS NOT NULL
      AND p.quality_state = 'valid'
      AND p.next_quality = 'valid'
      AND coverage_count.matching_coverage = 1
      AND EXISTS (
        SELECT 1
        FROM pg_catalog.pg_timezone_names z
        WHERE z.name = c.timezone
      )
      AND floor(
        extract(
          epoch FROM (
            (
              (p.session_end AT TIME ZONE c.timezone)
              AT TIME ZONE 'UTC'
            ) - p.session_end
          )
        ) / 60
      )::integer = c.utc_offset_minutes
      AND NOT EXISTS (
        SELECT 1
        FROM public.alert_intervention_events AS i
        WHERE i.version_id = _version_id
          AND i.user_id = p.user_id
          AND i.evidence_version = 'canonical-v2'
          AND i.occurred_at >= p.session_end
          AND i.occurred_at < p.next_start
          AND i.captured_at < _cutoff
      )
  ),
  canonical_effective AS (
    SELECT
      g.*,
      greatest(
        0::numeric,
        extract(epoch FROM (g.next_start - g.session_end))
          - coalesce(sleep.sleep_seconds, 0)
      )::double precision AS effective_seconds,
      sleep.sleep_provenance_sha256
    FROM coverage_gaps AS g
    CROSS JOIN LATERAL (
      WITH raw_sleep AS (
        SELECT
          si.starts_at,
          si.ends_at,
          si.basis,
          si.confidence,
          si.provenance,
          tstzrange(
            greatest(si.starts_at, g.session_end),
            least(si.ends_at, g.next_start),
            '[)'
          ) AS clipped_range
        FROM private.candidate_sleep_intervals(
          g.user_id,
          g.session_end,
          g.next_start,
          _version_id
        ) AS si
        WHERE si.starts_at < g.next_start
          AND si.ends_at > g.session_end
      ),
      merged AS (
        SELECT unnest(range_agg(clipped_range)) AS r
        FROM raw_sleep
      )
      SELECT
        coalesce(
          (
            SELECT sum(extract(epoch FROM (upper(r) - lower(r))))
            FROM merged
          ),
          0
        )::double precision AS sleep_seconds,
        encode(
          extensions.digest(
            coalesce(
              (
                SELECT jsonb_agg(
                  jsonb_build_object(
                    'starts_at_utc',
                      to_char(
                        starts_at AT TIME ZONE 'UTC',
                        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
                      ),
                    'ends_at_utc',
                      to_char(
                        ends_at AT TIME ZONE 'UTC',
                        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
                      ),
                    'basis', basis,
                    'confidence', confidence,
                    'provenance', provenance
                  )
                  ORDER BY
                    starts_at,
                    ends_at,
                    basis,
                    confidence,
                    provenance::text
                )
                FROM raw_sleep
              ),
              '[]'::jsonb
            )::text,
            'sha256'
          ),
          'hex'
        ) AS sleep_provenance_sha256
    ) AS sleep
  ),
  historical_effective AS (
    SELECT
      p.user_id,
      p.session_end,
      p.next_start,
      p.context_key,
      NULL::uuid AS coverage_id,
      'UTC'::text AS timezone,
      0::integer AS utc_offset_minutes,
      NULL::text AS coverage_provenance_sha256,
      p.source_ingest_version,
      p.training_provenance,
      p.provenance_sha256 AS session_provenance_sha256,
      p.next_session_provenance_sha256,
      extract(
        epoch FROM (p.next_start - p.session_end)
      )::double precision AS effective_seconds,
      NULL::text AS sleep_provenance_sha256
    FROM paired AS p
    WHERE p.source_ingest_version = 1
      AND p.training_provenance = 'historical_v1_training_only'
      AND p.next_start IS NOT NULL
      AND p.quality_state = 'valid'
      AND p.next_quality = 'valid'
  ),
  effective AS (
    SELECT * FROM canonical_effective
    UNION ALL
    SELECT * FROM historical_effective
  ),
  capped AS (
    SELECT
      e.*,
      (e.next_start AT TIME ZONE e.timezone)::date AS local_date,
      row_number() OVER (
        PARTITION BY
          e.user_id,
          (e.next_start AT TIME ZONE e.timezone)::date
        ORDER BY md5(
          _version_id::text || ':' || e.user_id::text || ':'
          || to_char(
            e.session_end AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
          ) || ':'
          || to_char(
            e.next_start AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
          )
        )
      ) AS daily_rank
    FROM effective AS e
    WHERE e.effective_seconds > 0
  ),
  selected AS (
    SELECT *
    FROM capped
    WHERE daily_rank <= _daily_cap
  ),
  grouped AS (
    SELECT
      user_id,
      'personal_global'::text AS context_key,
      session_end,
      next_start,
      local_date,
      effective_seconds,
      coverage_id,
      timezone,
      utc_offset_minutes,
      coverage_provenance_sha256,
      sleep_provenance_sha256,
      source_ingest_version,
      training_provenance,
      session_provenance_sha256,
      next_session_provenance_sha256
    FROM selected
    UNION ALL
    SELECT
      user_id,
      context_key,
      session_end,
      next_start,
      local_date,
      effective_seconds,
      coverage_id,
      timezone,
      utc_offset_minutes,
      coverage_provenance_sha256,
      sleep_provenance_sha256,
      source_ingest_version,
      training_provenance,
      session_provenance_sha256,
      next_session_provenance_sha256
    FROM selected
    WHERE context_key IS NOT NULL
  ),
  aggregate_inputs AS (
    SELECT
      user_id,
      context_key,
      count(*)::integer AS sample_count,
      count(DISTINCT local_date)::integer AS distinct_support_dates,
      min(local_date) AS support_started_on,
      max(local_date) AS support_ended_on,
      max(next_start) AS latest_evidence_at,
      ceil(
        percentile_disc(0.95)
          WITHIN GROUP (ORDER BY effective_seconds) / 60.0
      )::integer AS neutral_p95_minutes,
      jsonb_agg(
        jsonb_build_object(
          'session_end_utc',
            to_char(
              session_end AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
          'next_start_utc',
            to_char(
              next_start AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
          'local_date', local_date,
          'effective_seconds', effective_seconds,
          'coverage_id', coverage_id,
          'coverage_timezone', timezone,
          'coverage_utc_offset_minutes', utc_offset_minutes,
          'coverage_provenance_sha256', coverage_provenance_sha256,
          'sleep_provenance_sha256', sleep_provenance_sha256,
          'source_ingest_version', source_ingest_version,
          'training_provenance', training_provenance,
          'session_provenance_sha256', session_provenance_sha256,
          'next_session_provenance_sha256',
            next_session_provenance_sha256
        )
        ORDER BY
          session_end,
          next_start,
          source_ingest_version,
          session_provenance_sha256
      ) AS gap_inputs
    FROM grouped
    GROUP BY user_id, context_key
  ),
  hashes AS (
    SELECT
      a.*,
      encode(
        extensions.digest(
          jsonb_build_object(
            'version_id', _version_id,
            'through_date', _through_date,
            'config_sha256', _config_sha256,
            'evidence_version', _evidence_version,
            'context_key', context_key,
            'gaps', gap_inputs
          )::text,
          'sha256'
        ),
        'hex'
      ) AS input_sha256
    FROM aggregate_inputs AS a
  ),
  prepared AS (
    SELECT
      h.*,
      CASE
        WHEN h.latest_evidence_at
          < _cutoff - make_interval(days => _max_age)
          THEN 'stale'
        WHEN h.sample_count >= _min_samples
          AND h.distinct_support_dates >= _min_dates
          AND (
            h.support_ended_on - h.support_started_on + 1
          ) >= _min_span
          THEN 'valid'
        ELSE 'low_support'
      END::text AS quality_state,
      CASE
        WHEN h.latest_evidence_at
          < _cutoff - make_interval(days => _max_age)
          THEN 0::double precision
        ELSE least(
          1::double precision,
          h.sample_count::double precision
            / _min_samples::double precision,
          h.distinct_support_dates::double precision
            / _min_dates::double precision,
          (h.support_ended_on - h.support_started_on + 1)::double precision
            / _min_span::double precision
        )
      END AS confidence
    FROM hashes AS h
  )
  SELECT
    p.user_id,
    p.context_key,
    _through_date AS through_date,
    p.neutral_p95_minutes,
    p.sample_count,
    p.distinct_support_dates,
    p.support_started_on,
    p.support_ended_on,
    p.latest_evidence_at,
    p.quality_state,
    p.confidence,
    p.input_sha256,
    encode(
      extensions.digest(
        jsonb_build_object(
          'version_id', _version_id,
          'user_id', p.user_id,
          'context_key', p.context_key,
          'through_date', _through_date,
          'neutral_p95_minutes', p.neutral_p95_minutes,
          'sample_count', p.sample_count,
          'distinct_support_dates', p.distinct_support_dates,
          'support_started_on', p.support_started_on,
          'support_ended_on', p.support_ended_on,
          'latest_evidence_at_utc',
            to_char(
              p.latest_evidence_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
          'quality_state', p.quality_state,
          'confidence', p.confidence,
          'input_sha256', p.input_sha256
        )::text,
        'sha256'
      ),
      'hex'
    ) AS profile_sha256
  FROM prepared AS p;

  SELECT coalesce(
    sum(sample_count) FILTER (WHERE context_key = 'personal_global'),
    0
  )::integer
    INTO _completed_gaps
  FROM pg_temp._alert_gap_profile_build;

  INSERT INTO public.alert_gap_profiles AS target (
    version_id,
    user_id,
    context_key,
    through_date,
    neutral_p95_minutes,
    sample_count,
    distinct_support_dates,
    support_started_on,
    support_ended_on,
    latest_evidence_at,
    quality_state,
    confidence,
    profile_sha256,
    input_sha256
  )
  SELECT
    _version_id,
    user_id,
    context_key,
    through_date,
    neutral_p95_minutes,
    sample_count,
    distinct_support_dates,
    support_started_on,
    support_ended_on,
    latest_evidence_at,
    quality_state,
    confidence,
    profile_sha256,
    input_sha256
  FROM pg_temp._alert_gap_profile_build
  ON CONFLICT (
    version_id,
    user_id,
    context_key,
    through_date
  ) DO UPDATE
  SET
    neutral_p95_minutes = EXCLUDED.neutral_p95_minutes,
    sample_count = EXCLUDED.sample_count,
    distinct_support_dates = EXCLUDED.distinct_support_dates,
    support_started_on = EXCLUDED.support_started_on,
    support_ended_on = EXCLUDED.support_ended_on,
    latest_evidence_at = EXCLUDED.latest_evidence_at,
    quality_state = EXCLUDED.quality_state,
    confidence = EXCLUDED.confidence,
    profile_sha256 = EXCLUDED.profile_sha256,
    input_sha256 = EXCLUDED.input_sha256,
    computed_at = clock_timestamp()
  WHERE target.input_sha256 IS DISTINCT FROM EXCLUDED.input_sha256
     OR target.profile_sha256 IS DISTINCT FROM EXCLUDED.profile_sha256;

  GET DIAGNOSTICS _profiles_written = ROW_COUNT;

  DELETE FROM public.alert_gap_profiles AS target
  WHERE target.version_id = _version_id
    AND target.through_date = _through_date
    AND NOT EXISTS (
      SELECT 1
      FROM pg_temp._alert_gap_profile_build AS b
      WHERE b.user_id = target.user_id
        AND b.context_key = target.context_key
    );

  GET DIAGNOSTICS _profiles_deleted = ROW_COUNT;

  RETURN jsonb_build_object(
    'profiles_written', _profiles_written,
    'profiles_deleted', _profiles_deleted,
    'completed_gaps', _completed_gaps,
    'explicit_quiet_minutes', 0
  );
END;
$$;


ALTER FUNCTION "private"."rebuild_alert_gap_profiles"("_version_id" "uuid", "_through_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."rebuild_routine_mode_cohort_priors"("_version_id" "uuid", "_through_date" "date", "_routine_mode" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    SET "DateStyle" TO 'ISO, YMD'
    SET "extra_float_digits" TO '3'
    AS $$
DECLARE
  _config jsonb;
  _config_sha256 text;
  _evidence_version text;
  _status text;
  _mode text := private.canonical_routine_mode(_routine_mode);
  _generation bigint;
  _personal_min_samples integer;
  _personal_min_dates integer;
  _personal_min_span integer;
  _personal_max_age integer;
  _cohort_min_contributors integer;
  _cohort_min_dates integer;
  _cohort_min_span integer;
  _cohort_max_age integer;
  _cohort_min_confidence double precision;
  _floor integer;
  _ceiling integer;
  _algorithm text;
  _trim_fraction double precision;
  _count integer;
  _support_dates integer;
  _conservative_span_days integer;
  _support_started date;
  _support_ended date;
  _oldest_evidence timestamptz;
  _latest_evidence timestamptz;
  _valid_until timestamptz;
  _minimum_confidence double precision;
  _confidence double precision;
  _neutral integer;
  _quality text;
  _multiset text;
  _input_sha256 text;
  _prior_sha256 text;
  _published integer := 0;
  _cutoff timestamptz;
BEGIN
  IF _version_id IS NULL OR _through_date IS NULL
     OR _mode NOT IN ('regular_9to5', 'semester_break', 'shift_irregular') THEN
    RETURN jsonb_build_object('published', 0, 'routine_mode', _mode);
  END IF;

  _cutoff := (_through_date + 1)::timestamptz;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('keep-contact:routine-mode-cohort:' || _mode, 0)
  );

  SELECT v.config, v.config_sha256, v.evidence_version, v.status
    INTO _config, _config_sha256, _evidence_version, _status
  FROM public.alert_model_versions AS v
  WHERE v.id = _version_id;

  SELECT generation INTO _generation
  FROM public.routine_mode_cohort_generations
  WHERE routine_mode = _mode;

  IF NOT FOUND OR _status NOT IN ('replay', 'shadow')
     OR _evidence_version <> 'canonical-v2'
     OR _config_sha256 <> encode(extensions.digest(_config::text, 'sha256'), 'hex') THEN
    RETURN jsonb_build_object('published', 0, 'routine_mode', _mode);
  END IF;

  BEGIN
    _personal_min_samples := (_config #>> '{personal,min_samples}')::integer;
    _personal_min_dates := (_config #>> '{personal,min_support_dates}')::integer;
    _personal_min_span := (_config #>> '{personal,min_span_days}')::integer;
    _personal_max_age := (_config #>> '{personal,max_age_days}')::integer;
    _cohort_min_contributors := (_config #>> '{cohort,min_contributors}')::integer;
    _cohort_min_dates := (_config #>> '{cohort,min_support_dates}')::integer;
    _cohort_min_span := (_config #>> '{cohort,min_span_days}')::integer;
    _cohort_max_age := (_config #>> '{cohort,max_age_days}')::integer;
    _cohort_min_confidence := (_config #>> '{cohort,min_confidence}')::double precision;
    _floor := (_config #>> '{cohort,contribution_floor_minutes}')::integer;
    _ceiling := (_config #>> '{cohort,contribution_ceiling_minutes}')::integer;
    _algorithm := _config #>> '{cohort,algorithm}';
    _trim_fraction := (_config #>> '{cohort,trim_fraction}')::double precision;
  EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
    RETURN jsonb_build_object('published', 0, 'routine_mode', _mode);
  END;

  IF _personal_min_samples <= 0 OR _personal_min_dates <= 0 OR _personal_min_span <= 0 OR _personal_max_age <= 0
     OR _cohort_min_contributors <= 0 OR _cohort_min_dates <= 0 OR _cohort_min_span <= 0 OR _cohort_max_age <= 0
     OR _cohort_min_confidence <= 0 OR _cohort_min_confidence > 1
     OR _floor <= 0 OR _ceiling < _floor
     OR _algorithm NOT IN ('weighted_median', 'trimmed_mean')
     OR _trim_fraction < 0 OR _trim_fraction >= 0.5
     OR _config #>> '{cohort,confidence_formula_version}' <> 'cohort_support_min_v1' THEN
    RETURN jsonb_build_object('published', 0, 'routine_mode', _mode);
  END IF;

  DROP TABLE IF EXISTS pg_temp._routine_mode_cohort_build;
  CREATE TEMP TABLE _routine_mode_cohort_build ON COMMIT DROP AS
  SELECT
    greatest(_floor, least(_ceiling, p.neutral_p95_minutes))::integer AS neutral_minutes,
    greatest(0::double precision, least(1::double precision, p.confidence)) AS profile_confidence,
    p.distinct_support_dates,
    p.support_started_on,
    p.support_ended_on,
    (p.support_ended_on - p.support_started_on + 1)::integer AS support_span_days,
    p.latest_evidence_at
  FROM public.alert_gap_profiles AS p
  JOIN public.profiles AS owner_profile ON owner_profile.id = p.user_id
  WHERE p.version_id = _version_id
    AND p.context_key = 'personal_global'
    AND p.through_date = _through_date
    AND p.quality_state = 'valid'
    AND owner_profile.consent_data_sharing = true
    AND private.canonical_routine_mode(owner_profile.routine_pattern) = _mode
    AND p.sample_count >= _personal_min_samples
    AND p.distinct_support_dates >= _personal_min_dates
    AND p.support_ended_on - p.support_started_on + 1 >= _personal_min_span
    AND p.confidence >= _cohort_min_confidence
    AND p.latest_evidence_at + make_interval(days => _personal_max_age) > _cutoff;

  SELECT count(*)::integer,
         min(distinct_support_dates), min(support_span_days), min(support_started_on), max(support_ended_on),
         min(latest_evidence_at), max(latest_evidence_at), min(profile_confidence),
         string_agg(neutral_minutes::text || ':' || profile_confidence::text, ',' ORDER BY neutral_minutes, profile_confidence)
    INTO _count, _support_dates, _conservative_span_days, _support_started, _support_ended,
         _oldest_evidence, _latest_evidence, _minimum_confidence, _multiset
  FROM pg_temp._routine_mode_cohort_build;

  IF _count = 0 THEN
    DELETE FROM public.routine_mode_cohort_priors
    WHERE version_id = _version_id AND routine_mode = _mode
      AND context_key = 'personal_global' AND through_date = _through_date;
    RETURN jsonb_build_object('published', 0, 'routine_mode', _mode);
  END IF;

  _valid_until := least(
    _oldest_evidence + make_interval(days => _personal_max_age),
    _oldest_evidence + make_interval(days => _cohort_max_age)
  );

  IF _valid_until <= _cutoff THEN
    DELETE FROM public.routine_mode_cohort_priors
    WHERE version_id = _version_id AND routine_mode = _mode
      AND context_key = 'personal_global' AND through_date = _through_date;
    RETURN jsonb_build_object('published', 0, 'routine_mode', _mode);
  END IF;

  IF _algorithm = 'weighted_median' THEN
    SELECT neutral_minutes INTO _neutral
    FROM (
      SELECT neutral_minutes,
             sum(profile_confidence) OVER (ORDER BY neutral_minutes, profile_confidence ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_weight,
             sum(profile_confidence) OVER () AS total_weight
      FROM pg_temp._routine_mode_cohort_build
    ) AS weighted
    WHERE cumulative_weight >= total_weight / 2.0
    ORDER BY neutral_minutes, cumulative_weight
    LIMIT 1;
  ELSE
    SELECT ceil(avg(neutral_minutes)::numeric)::integer INTO _neutral
    FROM (
      SELECT neutral_minutes,
             row_number() OVER (ORDER BY neutral_minutes, profile_confidence) AS ordinal,
             count(*) OVER () AS total_count
      FROM pg_temp._routine_mode_cohort_build
    ) AS trimmed
    WHERE ordinal > floor(total_count * _trim_fraction)
      AND ordinal <= total_count - floor(total_count * _trim_fraction);
  END IF;

  _confidence := least(
    1::double precision,
    _count::double precision / _cohort_min_contributors::double precision,
    _support_dates::double precision / _cohort_min_dates::double precision,
    _conservative_span_days::double precision / _cohort_min_span::double precision,
    _minimum_confidence / _cohort_min_confidence
  );
  _quality := CASE
    WHEN _count >= _cohort_min_contributors
      AND _support_dates >= _cohort_min_dates
      AND _conservative_span_days >= _cohort_min_span
      AND _minimum_confidence >= _cohort_min_confidence
      THEN 'valid'
    ELSE 'low_support'
  END;

  _input_sha256 := encode(extensions.digest(concat_ws('|',
    _version_id::text, _config_sha256, _evidence_version, _through_date::text, _mode,
    _algorithm, _generation::text, _multiset, _count::text, _support_dates::text,
    _conservative_span_days::text, _support_started::text, _support_ended::text,
    _oldest_evidence::text, _latest_evidence::text, _valid_until::text, _cutoff::text
  ), 'sha256'), 'hex');
  _prior_sha256 := encode(extensions.digest(concat_ws('|',
    _input_sha256, _version_id::text, _mode, 'personal_global', _through_date::text,
    _count::text, _support_dates::text, _conservative_span_days::text, _support_started::text,
    _support_ended::text, _latest_evidence::text, _oldest_evidence::text, _valid_until::text,
    _neutral::text, _quality, _confidence::text, _minimum_confidence::text, _algorithm,
    _config_sha256, _evidence_version, _generation::text
  ), 'sha256'), 'hex');

  INSERT INTO public.routine_mode_cohort_priors AS target (
    version_id, routine_mode, context_key, through_date, contributor_count,
    distinct_support_dates, support_started_on, support_ended_on, latest_evidence_at,
    oldest_evidence_at, valid_until, conservative_span_days, minimum_profile_confidence,
    neutral_p95_minutes, quality_state, confidence,
    algorithm, config_sha256, evidence_version, source_generation, input_sha256, prior_sha256
  ) VALUES (
    _version_id, _mode, 'personal_global', _through_date, _count,
    _support_dates, _support_started, _support_ended, _latest_evidence,
    _oldest_evidence, _valid_until, _conservative_span_days, _minimum_confidence,
    _neutral, _quality, _confidence,
    _algorithm, _config_sha256, _evidence_version, _generation, _input_sha256, _prior_sha256
  )
  ON CONFLICT (version_id, routine_mode, context_key, through_date) DO UPDATE
  SET contributor_count = EXCLUDED.contributor_count,
      distinct_support_dates = EXCLUDED.distinct_support_dates,
      support_started_on = EXCLUDED.support_started_on,
      support_ended_on = EXCLUDED.support_ended_on,
      latest_evidence_at = EXCLUDED.latest_evidence_at,
      oldest_evidence_at = EXCLUDED.oldest_evidence_at,
      valid_until = EXCLUDED.valid_until,
      conservative_span_days = EXCLUDED.conservative_span_days,
      minimum_profile_confidence = EXCLUDED.minimum_profile_confidence,
      neutral_p95_minutes = EXCLUDED.neutral_p95_minutes,
      quality_state = EXCLUDED.quality_state,
      confidence = EXCLUDED.confidence,
      algorithm = EXCLUDED.algorithm,
      config_sha256 = EXCLUDED.config_sha256,
      evidence_version = EXCLUDED.evidence_version,
      source_generation = EXCLUDED.source_generation,
      input_sha256 = EXCLUDED.input_sha256,
      prior_sha256 = EXCLUDED.prior_sha256,
      published_at = CASE WHEN target.prior_sha256 = EXCLUDED.prior_sha256 THEN target.published_at ELSE clock_timestamp() END
  WHERE target.prior_sha256 IS DISTINCT FROM EXCLUDED.prior_sha256;
  GET DIAGNOSTICS _published = ROW_COUNT;

  RETURN jsonb_build_object('published', _published, 'routine_mode', _mode, 'quality_state', _quality);
END;
$$;


ALTER FUNCTION "private"."rebuild_routine_mode_cohort_priors"("_version_id" "uuid", "_through_date" "date", "_routine_mode" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."record_account_threshold_shadow"("_through_date" "date" DEFAULT NULL::"date", "_lookback_days" integer DEFAULT 30, "_shrinkage_k" integer DEFAULT 50, "_percentile" numeric DEFAULT 0.95, "_buffer_high" integer DEFAULT 0, "_buffer_balanced" integer DEFAULT 45, "_buffer_low" integer DEFAULT 90, "_neutral_floor_minutes" integer DEFAULT 90, "_post_wake_grace_minutes" integer DEFAULT 120) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
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


ALTER FUNCTION "private"."record_account_threshold_shadow"("_through_date" "date", "_lookback_days" integer, "_shrinkage_k" integer, "_percentile" numeric, "_buffer_high" integer, "_buffer_balanced" integer, "_buffer_low" integer, "_neutral_floor_minutes" integer, "_post_wake_grace_minutes" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."record_alert_judgment_shadow"("_version_id" "uuid", "_evaluated_at" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    SET "DateStyle" TO 'ISO, YMD'
    SET "extra_float_digits" TO '3'
    AS $$
DECLARE
  _recorder_version constant text := 'adaptive_shadow_recorder_v1';
  _evaluator_version constant text := 'adaptive_candidate_v1';
  _supported_evidence_version constant text := 'canonical-v2';
  _required_keys constant text[] := ARRAY[
    'basis',
    'candidate_cap_reason',
    'candidate_ceiling_minutes',
    'candidate_deadline',
    'candidate_floor_minutes',
    'candidate_threshold_minutes',
    'confidence',
    'context_key',
    'deadline_basis',
    'decision_provenance',
    'effective_silence_minutes',
    'evaluated_at',
    'evaluator_version',
    'evidence_cutoff',
    'fallback_path',
    'guardian_used_as_activity',
    'neutral_threshold_minutes',
    'provenance_sha256',
    'quality_state',
    'replayable',
    'selected_source_sha256',
    'sensitivity_buffer_minutes',
    'sleep_interval_provenance',
    'subject_context_sha256',
    'unclamped_candidate_threshold_minutes',
    'unreplayable_reason',
    'version_id',
    'would_alert'
  ];
  _run_level_reasons constant text[] := ARRAY[
    'invalid_version_status',
    'config_hash_mismatch',
    'unsupported_evidence_version'
  ];
  _per_user_reasons constant text[] := ARRAY[
    'missing_subject_context',
    'ambiguous_subject_context',
    'subject_context_provenance_invalid',
    'missing_qualified_session'
  ];
  _version public.alert_model_versions%ROWTYPE;
  _population_user_id uuid;
  _evaluated_minute timestamptz;
  _evaluated_minute_utc text;
  _result jsonb;
  _result_key_count integer;
  _replayable boolean;
  _reason text;
  _decision_provenance jsonb;
  _provenance_sha text;
  _decision_sha text;
  _existing_decision_sha text;
  _fallback_path text[];
  _population_count integer := 0;
  _evaluated_count integer := 0;
  _replayable_count integer := 0;
  _inserted_count integer := 0;
  _duplicate_count integer := 0;
  _unreplayable_count integer := 0;
  _unreplayable_reason_counts jsonb := '{}'::jsonb;
  _result_status text;
BEGIN
  IF _version_id IS NULL THEN
    RAISE EXCEPTION 'shadow recorder requires a non-null version id';
  END IF;
  IF _evaluated_at IS NULL OR NOT isfinite(_evaluated_at) THEN
    RAISE EXCEPTION 'shadow recorder requires a finite evaluation timestamp';
  END IF;

  _evaluated_minute :=
    date_trunc('minute', _evaluated_at AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  _evaluated_minute_utc := to_char(
    _evaluated_minute AT TIME ZONE 'UTC',
    'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
  );

  SELECT version.*
    INTO _version
  FROM public.alert_model_versions AS version
  WHERE version.id = _version_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'shadow recorder version does not exist';
  END IF;
  IF _version.status <> 'shadow' THEN
    RAISE EXCEPTION 'shadow recorder requires status=shadow';
  END IF;
  IF _version.shadow_enabled_at IS NULL
     OR _evaluated_minute < _version.shadow_enabled_at THEN
    RAISE EXCEPTION 'shadow recorder evaluation precedes shadow enablement';
  END IF;
  IF _version.config_sha256
      <> encode(extensions.digest(_version.config::text, 'sha256'), 'hex') THEN
    RAISE EXCEPTION 'shadow recorder config hash mismatch';
  END IF;
  IF _version.evidence_version <> _supported_evidence_version THEN
    RAISE EXCEPTION 'shadow recorder evidence version is unsupported';
  END IF;
  IF _version.config #>> '{evaluator,contract_version}'
      <> _evaluator_version THEN
    RAISE EXCEPTION 'shadow recorder evaluator contract is unsupported';
  END IF;

  FOR _population_user_id IN
    SELECT DISTINCT ds.user_id
    FROM public.device_state AS ds
    WHERE EXISTS (
      SELECT 1
      FROM public.group_members AS gm
      WHERE gm.user_id = ds.user_id
        AND gm.status = 'active'
        AND gm.monitored
    )
    ORDER BY ds.user_id
  LOOP
    _population_count := _population_count + 1;
    _result := private.resolve_alert_candidate(
      _population_user_id,
      _evaluated_minute,
      _version_id
    );
    _evaluated_count := _evaluated_count + 1;

    IF _result IS NULL OR jsonb_typeof(_result) <> 'object' THEN
      RAISE EXCEPTION 'candidate evaluator returned a non-object result';
    END IF;
    SELECT count(*)::integer
      INTO _result_key_count
    FROM jsonb_object_keys(_result);
    IF NOT (_result ?& _required_keys)
       OR _result_key_count <> cardinality(_required_keys) THEN
      RAISE EXCEPTION 'candidate evaluator returned a malformed key contract';
    END IF;
    IF jsonb_typeof(_result -> 'replayable') <> 'boolean'
       OR _result ->> 'evaluator_version' <> _evaluator_version
       OR _result ->> 'version_id' <> _version_id::text
       OR _result ->> 'evaluated_at' <> _evaluated_minute_utc
       OR _result ->> 'evidence_cutoff' <> _evaluated_minute_utc
       OR jsonb_typeof(_result -> 'decision_provenance') <> 'object'
       OR jsonb_typeof(_result -> 'provenance_sha256') <> 'string'
       OR jsonb_typeof(_result -> 'guardian_used_as_activity') <> 'boolean'
       OR (_result ->> 'guardian_used_as_activity')::boolean THEN
      RAISE EXCEPTION 'candidate evaluator returned malformed identity fields';
    END IF;
    _decision_provenance := _result -> 'decision_provenance';
    _provenance_sha := encode(
      extensions.digest(_decision_provenance::text, 'sha256'),
      'hex'
    );
    IF _result ->> 'provenance_sha256' <> _provenance_sha THEN
      RAISE EXCEPTION 'candidate evaluator provenance hash mismatch';
    END IF;

    _replayable := (_result ->> 'replayable')::boolean;
    _reason := _result ->> 'unreplayable_reason';

    IF _reason = ANY (_run_level_reasons) THEN
      RAISE EXCEPTION 'candidate evaluator returned run-level reason: %', _reason;
    END IF;

    IF NOT _replayable THEN
      IF _reason IS NULL OR NOT (_reason = ANY (_per_user_reasons)) THEN
        RAISE EXCEPTION 'candidate evaluator returned an invalid per-user reason';
      END IF;
      IF _result ->> 'basis' IS NOT NULL
         OR _result ->> 'context_key' IS NOT NULL
         OR _result ->> 'neutral_threshold_minutes' IS NOT NULL
         OR _result ->> 'sensitivity_buffer_minutes' IS NOT NULL
         OR _result ->> 'unclamped_candidate_threshold_minutes' IS NOT NULL
         OR _result ->> 'candidate_floor_minutes' IS NOT NULL
         OR _result ->> 'candidate_ceiling_minutes' IS NOT NULL
         OR _result ->> 'candidate_cap_reason' IS NOT NULL
         OR _result ->> 'candidate_threshold_minutes' IS NOT NULL
         OR _result ->> 'effective_silence_minutes' IS NOT NULL
         OR _result ->> 'candidate_deadline' IS NOT NULL
         OR _result ->> 'deadline_basis' IS NOT NULL
         OR _result ->> 'would_alert' IS NOT NULL
         OR _result ->> 'confidence' IS NOT NULL
         OR _result ->> 'selected_source_sha256' IS NOT NULL
         OR _result ->> 'subject_context_sha256' IS NOT NULL
         OR _result ->> 'quality_state' <> 'coverage_invalid'
         OR _result -> 'fallback_path' <> '[]'::jsonb
         OR _result -> 'sleep_interval_provenance' <> '[]'::jsonb THEN
        RAISE EXCEPTION 'candidate evaluator returned malformed unreplayable fields';
      END IF;
      _unreplayable_count := _unreplayable_count + 1;
      _unreplayable_reason_counts := jsonb_set(
        _unreplayable_reason_counts,
        ARRAY[_reason],
        to_jsonb(coalesce(
          (_unreplayable_reason_counts ->> _reason)::integer,
          0
        ) + 1),
        true
      );
      CONTINUE;
    END IF;

    IF _reason IS NOT NULL
       OR jsonb_typeof(_result -> 'basis') <> 'string'
       OR jsonb_typeof(_result -> 'context_key') <> 'string'
       OR jsonb_typeof(_result -> 'neutral_threshold_minutes') <> 'number'
       OR jsonb_typeof(_result -> 'sensitivity_buffer_minutes') <> 'number'
       OR jsonb_typeof(_result -> 'unclamped_candidate_threshold_minutes') <> 'number'
       OR jsonb_typeof(_result -> 'candidate_floor_minutes') <> 'number'
       OR jsonb_typeof(_result -> 'candidate_ceiling_minutes') <> 'number'
       OR jsonb_typeof(_result -> 'candidate_cap_reason') <> 'string'
       OR jsonb_typeof(_result -> 'candidate_threshold_minutes') <> 'number'
       OR jsonb_typeof(_result -> 'effective_silence_minutes') <> 'number'
       OR jsonb_typeof(_result -> 'candidate_deadline') <> 'string'
       OR jsonb_typeof(_result -> 'deadline_basis') <> 'string'
       OR jsonb_typeof(_result -> 'would_alert') <> 'boolean'
       OR jsonb_typeof(_result -> 'confidence') <> 'number'
       OR jsonb_typeof(_result -> 'quality_state') <> 'string'
       OR jsonb_typeof(_result -> 'fallback_path') <> 'array'
       OR jsonb_array_length(_result -> 'fallback_path') < 1
       OR jsonb_typeof(_result -> 'sleep_interval_provenance') <> 'array'
       OR (
         _result -> 'selected_source_sha256' <> 'null'::jsonb
         AND jsonb_typeof(_result -> 'selected_source_sha256') <> 'string'
       )
       OR jsonb_typeof(_result -> 'subject_context_sha256') <> 'string'
       OR jsonb_typeof(_result -> 'decision_provenance') <> 'object'
       OR jsonb_typeof(_result -> 'provenance_sha256') <> 'string' THEN
      RAISE EXCEPTION 'candidate evaluator returned malformed replayable fields';
    END IF;

    _decision_sha := encode(
      extensions.digest(jsonb_build_object(
        'version_id', _version_id,
        'user_id', _population_user_id,
        'evaluated_minute', _evaluated_minute_utc,
        'evaluator_result', _result
      )::text, 'sha256'),
      'hex'
    );
    SELECT array_agg(value ORDER BY ordinal)
      INTO _fallback_path
    FROM jsonb_array_elements_text(_result -> 'fallback_path')
      WITH ORDINALITY AS path(value, ordinal);

    INSERT INTO public.alert_judgment_shadow_decisions (
      version_id,
      user_id,
      evaluated_at,
      basis,
      evaluator_version,
      context_key,
      neutral_threshold_minutes,
      sensitivity_buffer_minutes,
      candidate_threshold_minutes,
      effective_silence_minutes,
      candidate_deadline,
      would_alert,
      confidence,
      quality_state,
      fallback_path,
      sleep_interval_provenance,
      provenance_sha256,
      guardian_used_as_activity,
      evidence_cutoff,
      unclamped_candidate_threshold_minutes,
      candidate_floor_minutes,
      candidate_ceiling_minutes,
      candidate_cap_reason,
      deadline_basis,
      selected_source_sha256,
      subject_context_sha256,
      decision_provenance,
      decision_sha256
    ) VALUES (
      _version_id,
      _population_user_id,
      _evaluated_minute,
      _result ->> 'basis',
      _evaluator_version,
      _result ->> 'context_key',
      (_result ->> 'neutral_threshold_minutes')::integer,
      (_result ->> 'sensitivity_buffer_minutes')::integer,
      (_result ->> 'candidate_threshold_minutes')::integer,
      (_result ->> 'effective_silence_minutes')::double precision,
      (_result ->> 'candidate_deadline')::timestamptz,
      (_result ->> 'would_alert')::boolean,
      (_result ->> 'confidence')::double precision,
      _result ->> 'quality_state',
      _fallback_path,
      _result -> 'sleep_interval_provenance',
      _provenance_sha,
      false,
      (_result ->> 'evidence_cutoff')::timestamptz,
      (_result ->> 'unclamped_candidate_threshold_minutes')::integer,
      (_result ->> 'candidate_floor_minutes')::integer,
      (_result ->> 'candidate_ceiling_minutes')::integer,
      _result ->> 'candidate_cap_reason',
      _result ->> 'deadline_basis',
      _result ->> 'selected_source_sha256',
      _result ->> 'subject_context_sha256',
      _decision_provenance,
      _decision_sha
    )
    ON CONFLICT (version_id, user_id, evaluated_minute) DO NOTHING;

    IF FOUND THEN
      _inserted_count := _inserted_count + 1;
    ELSE
      SELECT decision.decision_sha256
        INTO _existing_decision_sha
      FROM public.alert_judgment_shadow_decisions AS decision
      WHERE decision.version_id = _version_id
        AND decision.user_id = _population_user_id
        AND decision.evaluated_minute = _evaluated_minute;
      IF _existing_decision_sha IS DISTINCT FROM _decision_sha THEN
        RAISE EXCEPTION 'same-minute shadow decision mismatch';
      END IF;
      _duplicate_count := _duplicate_count + 1;
    END IF;
    _replayable_count := _replayable_count + 1;
  END LOOP;

  _result_status := CASE
    WHEN _population_count = 0 THEN 'empty'
    WHEN _replayable_count = 0 THEN 'all_unreplayable'
    WHEN _unreplayable_count > 0 THEN 'partial'
    ELSE 'complete'
  END;

  RETURN jsonb_build_object(
    'recorder_contract_version', _recorder_version,
    'evaluator_version', _evaluator_version,
    'execution_scope', 'fixture_only_unscheduled',
    'operational_shadow', false,
    'result_status', _result_status,
    'population_count', _population_count,
    'evaluated_count', _evaluated_count,
    'replayable_count', _replayable_count,
    'inserted_count', _inserted_count,
    'duplicate_count', _duplicate_count,
    'unreplayable_count', _unreplayable_count,
    'unreplayable_reason_counts', _unreplayable_reason_counts,
    'skipped_count', _duplicate_count + _unreplayable_count,
    'error_count', 0
  );
END;
$$;


ALTER FUNCTION "private"."record_alert_judgment_shadow"("_version_id" "uuid", "_evaluated_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."record_alert_judgment_shadow_operational"("_version_id" "uuid", "_evaluated_at" timestamp with time zone, "_max_population" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    SET "DateStyle" TO 'ISO, YMD'
    SET "extra_float_digits" TO '3'
    AS $$
DECLARE
  _person_id uuid;
  _result jsonb;
  _replayable boolean;
  _reason text;
  _decision_sha text;
  _prior private.adaptive_alert_shadow_user_state%ROWTYPE;
  _fallback_path text[];
  _population_count integer := 0;
  _evaluated_count integer := 0;
  _replayable_count integer := 0;
  _unreplayable_count integer := 0;
  _persisted_count integer := 0;
  _detail_count integer;
  _should_persist boolean;
  _minute timestamptz;
  _provenance_sha text;
  _result_key_count integer;
  _minute_utc text;
  _required_keys constant text[] := ARRAY[
    'basis', 'candidate_cap_reason', 'candidate_ceiling_minutes',
    'candidate_deadline', 'candidate_floor_minutes',
    'candidate_threshold_minutes', 'confidence', 'context_key',
    'deadline_basis', 'decision_provenance', 'effective_silence_minutes',
    'evaluated_at', 'evaluator_version', 'evidence_cutoff', 'fallback_path',
    'guardian_used_as_activity', 'neutral_threshold_minutes',
    'provenance_sha256', 'quality_state', 'replayable',
    'selected_source_sha256', 'sensitivity_buffer_minutes',
    'sleep_interval_provenance', 'subject_context_sha256',
    'unclamped_candidate_threshold_minutes', 'unreplayable_reason',
    'version_id', 'would_alert'
  ];
BEGIN
  IF _version_id IS NULL OR _evaluated_at IS NULL
     OR _max_population IS NULL OR _max_population NOT BETWEEN 1 AND 10000 THEN
    RAISE EXCEPTION 'invalid operational shadow recorder arguments';
  END IF;
  _minute := date_trunc('minute', _evaluated_at AT TIME ZONE 'UTC')
    AT TIME ZONE 'UTC';
  _minute_utc := to_char(
    _minute AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
  );

  FOR _person_id IN
    WITH population AS (
      SELECT DISTINCT ds.user_id
      FROM public.device_state AS ds
      WHERE EXISTS (
        SELECT 1
        FROM public.group_members AS gm
        WHERE gm.user_id = ds.user_id
          AND gm.status = 'active'
          AND gm.monitored
      )
    )
    SELECT p.user_id
    FROM population AS p
    ORDER BY p.user_id
    LIMIT _max_population
  LOOP
    _population_count := _population_count + 1;
    _result := private.resolve_alert_candidate(_person_id, _minute, _version_id);
    _evaluated_count := _evaluated_count + 1;

    IF _result IS NULL OR jsonb_typeof(_result) <> 'object' THEN
      RAISE EXCEPTION 'malformed operational shadow result';
    END IF;
    SELECT count(*)::integer INTO _result_key_count
    FROM jsonb_object_keys(_result);
    IF NOT (_result ?& _required_keys)
       OR _result_key_count <> cardinality(_required_keys)
       OR jsonb_typeof(_result -> 'replayable') <> 'boolean'
       OR _result ->> 'version_id' <> _version_id::text
       OR _result ->> 'evaluated_at' <> _minute_utc
       OR _result ->> 'evidence_cutoff' <> _minute_utc
       OR _result ->> 'evaluator_version' <> 'adaptive_candidate_v1'
       OR jsonb_typeof(_result -> 'decision_provenance') <> 'object'
       OR jsonb_typeof(_result -> 'provenance_sha256') <> 'string'
       OR jsonb_typeof(_result -> 'guardian_used_as_activity') <> 'boolean'
       OR (_result ->> 'guardian_used_as_activity')::boolean THEN
      RAISE EXCEPTION 'malformed operational shadow result';
    END IF;

    _provenance_sha := encode(
      extensions.digest((_result -> 'decision_provenance')::text, 'sha256'),
      'hex'
    );
    IF _result ->> 'provenance_sha256' <> _provenance_sha THEN
      RAISE EXCEPTION 'operational shadow provenance mismatch';
    END IF;

    _replayable := (_result ->> 'replayable')::boolean;
    _reason := _result ->> 'unreplayable_reason';
    _decision_sha := encode(extensions.digest(jsonb_build_object(
      'version_id', _version_id,
      'user_id', _person_id,
      'evaluated_minute', _minute,
      'evaluator_result', _result
    )::text, 'sha256'), 'hex');

    SELECT s.* INTO _prior
    FROM private.adaptive_alert_shadow_user_state AS s
    WHERE s.version_id = _version_id AND s.user_id = _person_id;

    _should_persist := _replayable AND (
      NOT FOUND
      OR _prior.would_alert IS DISTINCT FROM
        (_result ->> 'would_alert')::boolean
      OR _prior.basis IS DISTINCT FROM _result ->> 'basis'
      OR _prior.candidate_threshold_minutes IS DISTINCT FROM
        (_result ->> 'candidate_threshold_minutes')::integer
      OR _prior.quality_state IS DISTINCT FROM _result ->> 'quality_state'
      OR _prior.unreplayable_reason IS DISTINCT FROM _reason
      OR _prior.last_persisted_at IS NULL
      OR _prior.last_persisted_at <= _minute - interval '1 hour'
    );

    INSERT INTO private.adaptive_alert_shadow_user_state (
      version_id, user_id, evaluated_at, replayable, would_alert, basis,
      candidate_threshold_minutes, quality_state, unreplayable_reason,
      decision_sha256, last_persisted_at, updated_at
    ) VALUES (
      _version_id, _person_id, _minute, _replayable,
      CASE WHEN _replayable THEN (_result ->> 'would_alert')::boolean END,
      CASE WHEN _replayable THEN _result ->> 'basis' END,
      CASE WHEN _replayable
        THEN (_result ->> 'candidate_threshold_minutes')::integer END,
      coalesce(_result ->> 'quality_state', 'coverage_invalid'),
      CASE WHEN _replayable THEN NULL ELSE _reason END,
      _decision_sha,
      CASE WHEN _should_persist THEN _minute ELSE _prior.last_persisted_at END,
      clock_timestamp()
    )
    ON CONFLICT (version_id, user_id) DO UPDATE SET
      evaluated_at = excluded.evaluated_at,
      replayable = excluded.replayable,
      would_alert = excluded.would_alert,
      basis = excluded.basis,
      candidate_threshold_minutes = excluded.candidate_threshold_minutes,
      quality_state = excluded.quality_state,
      unreplayable_reason = excluded.unreplayable_reason,
      decision_sha256 = excluded.decision_sha256,
      last_persisted_at = excluded.last_persisted_at,
      updated_at = excluded.updated_at;

    IF NOT _replayable THEN
      IF _reason NOT IN (
        'missing_subject_context', 'ambiguous_subject_context',
        'subject_context_provenance_invalid', 'missing_qualified_session'
      ) THEN
        RAISE EXCEPTION 'invalid operational shadow unreplayable reason';
      END IF;
      _unreplayable_count := _unreplayable_count + 1;
      CONTINUE;
    END IF;

    IF _result ->> 'basis' IS NULL
       OR _result ->> 'candidate_threshold_minutes' IS NULL
       OR _result ->> 'subject_context_sha256' IS NULL
       OR jsonb_typeof(_result -> 'fallback_path') <> 'array' THEN
      RAISE EXCEPTION 'malformed replayable operational shadow result';
    END IF;

    IF _should_persist THEN
      SELECT count(*)::integer INTO _detail_count
      FROM public.alert_judgment_shadow_decisions AS d
      WHERE d.version_id = _version_id
        AND d.user_id = _person_id
        AND d.evaluated_at >= date_trunc('day', _minute)
        AND d.evaluated_at < date_trunc('day', _minute) + interval '1 day';
      IF _detail_count >= 36 THEN
        RAISE EXCEPTION 'shadow_detail_budget_exceeded';
      END IF;

      SELECT array_agg(path.value ORDER BY path.ordinal)
        INTO _fallback_path
      FROM jsonb_array_elements_text(_result -> 'fallback_path')
        WITH ORDINALITY AS path(value, ordinal);

      INSERT INTO public.alert_judgment_shadow_decisions (
        version_id, user_id, evaluated_at, basis, evaluator_version,
        context_key, neutral_threshold_minutes, sensitivity_buffer_minutes,
        candidate_threshold_minutes, effective_silence_minutes,
        candidate_deadline, would_alert, confidence, quality_state,
        fallback_path, sleep_interval_provenance, provenance_sha256,
        guardian_used_as_activity, evidence_cutoff,
        unclamped_candidate_threshold_minutes, candidate_floor_minutes,
        candidate_ceiling_minutes, candidate_cap_reason, deadline_basis,
        selected_source_sha256, subject_context_sha256,
        decision_provenance, decision_sha256
      ) VALUES (
        _version_id, _person_id, _minute, _result ->> 'basis',
        _result ->> 'evaluator_version', _result ->> 'context_key',
        (_result ->> 'neutral_threshold_minutes')::integer,
        (_result ->> 'sensitivity_buffer_minutes')::integer,
        (_result ->> 'candidate_threshold_minutes')::integer,
        (_result ->> 'effective_silence_minutes')::double precision,
        (_result ->> 'candidate_deadline')::timestamptz,
        (_result ->> 'would_alert')::boolean,
        (_result ->> 'confidence')::double precision,
        _result ->> 'quality_state', _fallback_path,
        _result -> 'sleep_interval_provenance', _provenance_sha, false,
        (_result ->> 'evidence_cutoff')::timestamptz,
        (_result ->> 'unclamped_candidate_threshold_minutes')::integer,
        (_result ->> 'candidate_floor_minutes')::integer,
        (_result ->> 'candidate_ceiling_minutes')::integer,
        _result ->> 'candidate_cap_reason',
        _result ->> 'deadline_basis',
        _result ->> 'selected_source_sha256',
        _result ->> 'subject_context_sha256',
        _result -> 'decision_provenance', _decision_sha
      )
      ON CONFLICT (version_id, user_id, evaluated_minute) DO NOTHING;
      IF FOUND THEN
        _persisted_count := _persisted_count + 1;
      END IF;
    END IF;
    _replayable_count := _replayable_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'status', CASE WHEN _population_count = 0 THEN 'empty' ELSE 'completed' END,
    'population_count', _population_count,
    'evaluated_count', _evaluated_count,
    'replayable_count', _replayable_count,
    'unreplayable_count', _unreplayable_count,
    'persisted_count', _persisted_count
  );
END;
$$;


ALTER FUNCTION "private"."record_alert_judgment_shadow_operational"("_version_id" "uuid", "_evaluated_at" timestamp with time zone, "_max_population" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."record_alert_shadow_coverage_lease_core"("_user_id" "uuid", "_client_id" "text", "_channel" "text", "_collector_contract" "text", "_collector_state" "text", "_capability_sha256" "text", "_observed_at" timestamp with time zone, "_event_id" "uuid") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    AS $_$
DECLARE
  _received_at timestamptz := clock_timestamp();
  _platform text;
  _app_version text;
  _timezone text;
  _utc_offset_minutes integer;
  _enabled boolean;
  _accept boolean;
  _inserted integer;
BEGIN
  SELECT enabled, accept_coverage_leases
  INTO _enabled, _accept
  FROM private.adaptive_alert_shadow_runtime_config
  WHERE singleton;

  IF coalesce(_enabled, false) IS NOT TRUE
     OR coalesce(_accept, false) IS NOT TRUE THEN
    RETURN 'disabled';
  END IF;

  IF _user_id IS NULL THEN RETURN 'invalid'; END IF;
  IF _event_id IS NULL THEN RETURN 'invalid'; END IF;
  IF _client_id IS NULL OR length(trim(_client_id)) NOT BETWEEN 1 AND 64 THEN
    RETURN 'invalid';
  END IF;
  IF _channel NOT IN ('tauri', 'android-apk') THEN RETURN 'unsupported'; END IF;
  IF (
    _channel = 'tauri' AND _collector_contract <> 'tauri-idle-v1'
  ) OR (
    _channel = 'android-apk' AND _collector_contract <> 'android-passive-v1'
  ) THEN
    RETURN 'unsupported';
  END IF;
  IF _collector_state IS DISTINCT FROM 'operational' THEN
    RETURN 'unsupported';
  END IF;
  IF _capability_sha256 IS NULL
     OR _capability_sha256 !~ '^[a-f0-9]{64}$' THEN
    RETURN 'invalid';
  END IF;
  IF _observed_at IS NULL
     OR abs(extract(epoch FROM (_received_at - _observed_at))) > 300 THEN
    RETURN 'invalid';
  END IF;

  SELECT c.platform, c.app_version
  INTO _platform, _app_version
  FROM public.clients AS c
  WHERE c.user_id = _user_id
    AND c.client_id = _client_id;

  IF NOT FOUND THEN RETURN 'unregistered_client'; END IF;
  IF (
    _channel = 'tauri' AND _platform IS DISTINCT FROM 'tauri'
  ) OR (
    _channel = 'android-apk' AND _platform IS DISTINCT FROM 'android-apk'
  ) THEN
    RETURN 'capability_mismatch';
  END IF;
  IF _app_version IS NULL OR length(trim(_app_version)) NOT BETWEEN 1 AND 32 THEN
    RETURN 'capability_mismatch';
  END IF;

  SELECT coalesce(s.timezone, 'UTC')
  INTO _timezone
  FROM public.user_settings AS s
  WHERE s.user_id = _user_id;
  _timezone := coalesce(_timezone, 'UTC');

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_timezone_names
    WHERE name = _timezone
  ) THEN
    RETURN 'invalid';
  END IF;

  _utc_offset_minutes := round(
    extract(epoch FROM (
      (_received_at AT TIME ZONE _timezone)
      - (_received_at AT TIME ZONE 'UTC')
    )) / 60
  )::integer;

  INSERT INTO private.alert_shadow_coverage_leases (
    user_id, event_id, client_id, channel, collector_contract, collector_state,
    capability_sha256, observed_at, received_at, app_version, timezone,
    utc_offset_minutes
  ) VALUES (
    _user_id, _event_id, trim(_client_id), _channel, _collector_contract,
    _collector_state, _capability_sha256, _observed_at, _received_at,
    _app_version, _timezone, _utc_offset_minutes
  )
  ON CONFLICT (user_id, event_id) DO NOTHING;

  GET DIAGNOSTICS _inserted = ROW_COUNT;
  IF _inserted = 1 THEN
    RETURN 'inserted';
  END IF;
  RETURN 'duplicate';
END;
$_$;


ALTER FUNCTION "private"."record_alert_shadow_coverage_lease_core"("_user_id" "uuid", "_client_id" "text", "_channel" "text", "_collector_contract" "text", "_collector_state" "text", "_capability_sha256" "text", "_observed_at" timestamp with time zone, "_event_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."replay_config_is_valid"("_config" "jsonb") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    SET "extra_float_digits" TO '3'
    AS $$
  SELECT CASE
    WHEN jsonb_typeof(_config) IS DISTINCT FROM 'object'
      OR jsonb_typeof(_config -> 'replay') IS DISTINCT FROM 'object'
      OR NOT ((_config -> 'replay') ?& ARRAY[
        'contract_version', 'max_range_days', 'max_units'
      ])
      OR jsonb_typeof(_config #> '{replay,contract_version}') IS DISTINCT FROM 'string'
      OR jsonb_typeof(_config #> '{replay,max_range_days}') IS DISTINCT FROM 'number'
      OR jsonb_typeof(_config #> '{replay,max_units}') IS DISTINCT FROM 'number'
    THEN false
    ELSE
      _config #>> '{replay,contract_version}' = 'adaptive_replay_v1'
      AND (_config #>> '{replay,max_range_days}')::numeric BETWEEN 1 AND 2147483647
      AND (_config #>> '{replay,max_range_days}')::numeric
        = trunc((_config #>> '{replay,max_range_days}')::numeric)
      AND (_config #>> '{replay,max_units}')::numeric BETWEEN 1 AND 2147483647
      AND (_config #>> '{replay,max_units}')::numeric
        = trunc((_config #>> '{replay,max_units}')::numeric)
  END
$$;


ALTER FUNCTION "private"."replay_config_is_valid"("_config" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."resolve_alert_candidate"("_user_id" "uuid", "_evaluated_at" timestamp with time zone, "_version_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    SET "DateStyle" TO 'ISO, YMD'
    SET "extra_float_digits" TO '3'
    AS $$
DECLARE
  _evaluator_version constant text := 'adaptive_candidate_v1';
  _version public.alert_model_versions%ROWTYPE;
  _subject public.alert_judgment_subject_contexts%ROWTYPE;
  _profile public.alert_gap_profiles%ROWTYPE;
  _prior public.routine_mode_cohort_priors%ROWTYPE;
  _latest_session record;
  _subject_count integer;
  _subject_id uuid;
  _subject_expected_sha text;
  _subject_expected_sensitivity text;
  _offset_minutes integer;
  _session_from timestamptz;
  _session_found boolean := false;
  _personal_min_samples integer;
  _personal_min_dates integer;
  _personal_min_span integer;
  _personal_max_age integer;
  _personal_min_confidence double precision;
  _cohort_max_age integer;
  _candidate_floor integer;
  _candidate_ceiling integer;
  _sensitivity_buffer integer;
  _emergency_neutral integer;
  _emergency_definition_sha text;
  _basis text;
  _neutral integer;
  _unclamped integer;
  _threshold integer;
  _cap_reason text;
  _confidence double precision;
  _quality_state text;
  _selected_source_sha text;
  _selected_source_support jsonb;
  _fallback_path text[] := ARRAY[]::text[];
  _sleep_ranges tstzrange[] := ARRAY[]::tstzrange[];
  _sleep_range tstzrange;
  _sleep_provenance jsonb := '[]'::jsonb;
  _sleep_seconds double precision := 0;
  _wall_seconds double precision;
  _effective_minutes double precision;
  _remaining_seconds double precision;
  _awake_seconds double precision;
  _cursor timestamptz;
  _deadline timestamptz;
  _deadline_basis text;
  _would_alert boolean;
  _decision_provenance jsonb;
  _provenance_sha text;
  _unreplayable_reason text;
  _evaluated_at_utc text :=
    to_char(_evaluated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
BEGIN
  SELECT version.*
    INTO _version
  FROM public.alert_model_versions AS version
  WHERE version.id = _version_id;

  IF NOT FOUND OR _version.status NOT IN ('replay', 'shadow') THEN
    _unreplayable_reason := 'invalid_version_status';
  ELSIF _version.config_sha256
      <> encode(extensions.digest(_version.config::text, 'sha256'), 'hex') THEN
    _unreplayable_reason := 'config_hash_mismatch';
  ELSIF _version.evidence_version <> 'canonical-v2' THEN
    _unreplayable_reason := 'unsupported_evidence_version';
  END IF;

  -- Every helper-used config key (sessionization, context, personal, cohort,
  -- sensitivity buffers, candidate bounds, sleep compensation, evaluator,
  -- emergency) must have its required raw JSON type, enum/value, range, and
  -- integrality before any subject/session/profile/cohort evidence is read.
  -- A canonical config hash proves self-consistency, not validity: a
  -- pre-Task-6 legacy row can carry a self-consistent hash over malformed
  -- content (a JSON string where a number is required, an out-of-range or
  -- non-integral number, or a missing key), so this check cannot rely on
  -- casting first and catching failures after the fact.
  IF _unreplayable_reason IS NULL THEN
    IF NOT private.alert_candidate_config_is_valid(_version.config) THEN
      _unreplayable_reason := 'config_hash_mismatch';
    ELSE
      _personal_min_samples :=
        (_version.config #>> '{personal,min_samples}')::integer;
      _personal_min_dates :=
        (_version.config #>> '{personal,min_support_dates}')::integer;
      _personal_min_span :=
        (_version.config #>> '{personal,min_span_days}')::integer;
      _personal_max_age :=
        (_version.config #>> '{personal,max_age_days}')::integer;
      _personal_min_confidence :=
        (_version.config #>> '{personal,min_confidence}')::double precision;
      _cohort_max_age :=
        (_version.config #>> '{cohort,max_age_days}')::integer;
      _candidate_floor :=
        (_version.config #>> '{candidate_bounds,floor_minutes}')::integer;
      _candidate_ceiling :=
        (_version.config #>> '{candidate_bounds,ceiling_minutes}')::integer;
      _emergency_neutral :=
        (_version.config #>> '{emergency,neutral_minutes}')::integer;
      _emergency_definition_sha :=
        _version.config #>> '{emergency,expected_live_definition_sha256}';
    END IF;
  END IF;

  IF _unreplayable_reason IS NULL THEN
    SELECT
      count(*)::integer,
      (array_agg(context.id ORDER BY context.captured_at, context.id))[1]
      INTO _subject_count, _subject_id
    FROM public.alert_judgment_subject_contexts AS context
    WHERE context.version_id = _version_id
      AND context.user_id = _user_id
      AND context.effective_from <= _evaluated_at
      AND (context.effective_to IS NULL OR _evaluated_at < context.effective_to)
      AND context.captured_at <= _evaluated_at;

    IF _subject_count = 0 THEN
      _unreplayable_reason := 'missing_subject_context';
    ELSIF _subject_count <> 1 THEN
      _unreplayable_reason := 'ambiguous_subject_context';
    ELSE
      SELECT context.*
        INTO _subject
      FROM public.alert_judgment_subject_contexts AS context
      WHERE context.id = _subject_id;

      _subject_expected_sensitivity := CASE
        WHEN lower(trim(coalesce(_subject.raw_sensitivity, ''))) IN ('high', 'sensitive')
          THEN 'high'
        WHEN lower(trim(coalesce(_subject.raw_sensitivity, ''))) IN ('low', 'relaxed')
          THEN 'low'
        ELSE 'balanced'
      END;

      _subject_expected_sha := encode(extensions.digest(jsonb_build_object(
        'version_id', _subject.version_id,
        'user_id', _subject.user_id,
        'effective_from_utc',
          to_char(_subject.effective_from AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'effective_to_utc',
          CASE WHEN _subject.effective_to IS NULL THEN NULL
            ELSE to_char(_subject.effective_to AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
          END,
        'raw_sensitivity', _subject.raw_sensitivity,
        'canonical_sensitivity', _subject.canonical_sensitivity,
        'routine_mode', _subject.routine_mode,
        'timezone', _subject.timezone,
        'utc_offset_minutes', _subject.utc_offset_minutes,
        'settings_updated_at_utc',
          to_char(_subject.settings_updated_at AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'settings_provenance', _subject.settings_provenance,
        'captured_at_utc',
          to_char(_subject.captured_at AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'config_sha256', _subject.config_sha256,
        'evidence_version', _subject.evidence_version
      )::text, 'sha256'), 'hex');

      SELECT floor(extract(epoch FROM (
        ((_evaluated_at AT TIME ZONE _subject.timezone) AT TIME ZONE 'UTC')
        - _evaluated_at
      )) / 60)::integer
        INTO _offset_minutes
      WHERE EXISTS (
        SELECT 1
        FROM pg_catalog.pg_timezone_names AS zone
        WHERE zone.name = _subject.timezone
      );

      IF _subject.config_sha256 <> _version.config_sha256
         OR _subject.evidence_version <> _version.evidence_version
         OR _subject.subject_context_sha256 <> _subject_expected_sha
         OR _subject.canonical_sensitivity <> _subject_expected_sensitivity
         OR _subject.routine_mode NOT IN (
           'regular_9to5', 'semester_break', 'shift_irregular'
         )
         OR _offset_minutes IS NULL
         OR _offset_minutes <> _subject.utc_offset_minutes
         OR _subject.settings_updated_at > _subject.captured_at
         OR _subject.captured_at > _evaluated_at THEN
        _unreplayable_reason := 'subject_context_provenance_invalid';
      END IF;
    END IF;
  END IF;

  IF _unreplayable_reason IS NULL THEN
    SELECT min(coverage.starts_at)
      INTO _session_from
    FROM public.alert_observation_coverage_intervals AS coverage
    WHERE coverage.version_id = _version_id
      AND coverage.user_id = _user_id
      AND coverage.starts_at < _evaluated_at;

    IF _session_from IS NOT NULL AND _session_from < _evaluated_at THEN
      SELECT session.*
        INTO _latest_session
      FROM private.qualified_behavior_sessions(
        _user_id, _session_from, _evaluated_at, _version_id
      ) AS session
      WHERE session.quality_state = 'valid'
      ORDER BY session.session_end DESC, session.session_start DESC
      LIMIT 1;
      _session_found := FOUND;
    END IF;

    IF NOT _session_found THEN
      _unreplayable_reason := 'missing_qualified_session';
    END IF;
  END IF;

  IF _unreplayable_reason IS NOT NULL THEN
    _decision_provenance := jsonb_build_object(
      'version_id', _version_id,
      'evaluator_version', _evaluator_version,
      'evaluated_at', _evaluated_at_utc,
      'evidence_cutoff', _evaluated_at_utc,
      'replayable', false,
      'unreplayable_reason', _unreplayable_reason
    );
    _provenance_sha := encode(
      extensions.digest(_decision_provenance::text, 'sha256'), 'hex'
    );

    RETURN jsonb_build_object(
      'version_id', _version_id,
      'evaluator_version', _evaluator_version,
      'evaluated_at', _evaluated_at_utc,
      'evidence_cutoff', _evaluated_at_utc,
      'replayable', false,
      'unreplayable_reason', _unreplayable_reason,
      'basis', NULL,
      'context_key', NULL,
      'neutral_threshold_minutes', NULL,
      'sensitivity_buffer_minutes', NULL,
      'unclamped_candidate_threshold_minutes', NULL,
      'candidate_floor_minutes', NULL,
      'candidate_ceiling_minutes', NULL,
      'candidate_cap_reason', NULL,
      'candidate_threshold_minutes', NULL,
      'effective_silence_minutes', NULL,
      'candidate_deadline', NULL,
      'deadline_basis', NULL,
      'would_alert', NULL,
      'confidence', NULL,
      'quality_state', 'coverage_invalid',
      'fallback_path', '[]'::jsonb,
      'sleep_interval_provenance', '[]'::jsonb,
      'selected_source_sha256', NULL,
      'subject_context_sha256', NULL,
      'decision_provenance', _decision_provenance,
      'provenance_sha256', _provenance_sha,
      'guardian_used_as_activity', false
    );
  END IF;

  _sensitivity_buffer := CASE _subject.canonical_sensitivity
    WHEN 'high' THEN (_version.config #>> '{sensitivity_buffers_minutes,high}')::integer
    WHEN 'low' THEN (_version.config #>> '{sensitivity_buffers_minutes,low}')::integer
    ELSE (_version.config #>> '{sensitivity_buffers_minutes,balanced}')::integer
  END;

  _fallback_path := ARRAY['personal_context']::text[];

  WITH latest AS MATERIALIZED (
    SELECT candidate.*
    FROM public.alert_gap_profiles AS candidate
    WHERE candidate.version_id = _version_id
      AND candidate.user_id = _user_id
      AND candidate.context_key = _latest_session.context_key
      AND ((candidate.through_date + 1)::timestamp AT TIME ZONE 'UTC')
        <= _evaluated_at
      AND candidate.quality_state = 'valid'
      AND candidate.sample_count >= _personal_min_samples
      AND candidate.distinct_support_dates >= _personal_min_dates
      AND candidate.support_ended_on - candidate.support_started_on + 1
        >= _personal_min_span
      AND candidate.latest_evidence_at < _evaluated_at
      AND candidate.latest_evidence_at
        + make_interval(days => _personal_max_age) > _evaluated_at
      AND candidate.confidence >= _personal_min_confidence
      AND candidate.config_sha256 = _version.config_sha256
      AND candidate.evidence_version = _version.evidence_version
      AND candidate.profile_sha256 = encode(extensions.digest(jsonb_build_object(
        'version_id', candidate.version_id,
        'user_id', candidate.user_id,
        'context_key', candidate.context_key,
        'through_date', candidate.through_date,
        'neutral_p95_minutes', candidate.neutral_p95_minutes,
        'sample_count', candidate.sample_count,
        'distinct_support_dates', candidate.distinct_support_dates,
        'support_started_on', candidate.support_started_on,
        'support_ended_on', candidate.support_ended_on,
        'latest_evidence_at_utc',
          to_char(candidate.latest_evidence_at AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'quality_state', candidate.quality_state,
        'confidence', candidate.confidence,
        'input_sha256', candidate.input_sha256
      )::text, 'sha256'), 'hex')
    ORDER BY candidate.through_date DESC
    LIMIT 1
  )
  SELECT candidate.*
    INTO _profile
  FROM latest AS candidate;

  IF FOUND THEN
    _basis := 'personal_context';
  ELSE
    _fallback_path := pg_catalog.array_append(
      _fallback_path, 'personal_global'
    );
    WITH latest AS MATERIALIZED (
      SELECT candidate.*
      FROM public.alert_gap_profiles AS candidate
      WHERE candidate.version_id = _version_id
        AND candidate.user_id = _user_id
        AND candidate.context_key = 'personal_global'
        AND ((candidate.through_date + 1)::timestamp AT TIME ZONE 'UTC')
          <= _evaluated_at
        AND candidate.quality_state = 'valid'
        AND candidate.sample_count >= _personal_min_samples
        AND candidate.distinct_support_dates >= _personal_min_dates
        AND candidate.support_ended_on - candidate.support_started_on + 1
          >= _personal_min_span
        AND candidate.latest_evidence_at < _evaluated_at
        AND candidate.latest_evidence_at
          + make_interval(days => _personal_max_age) > _evaluated_at
        AND candidate.confidence >= _personal_min_confidence
        AND candidate.config_sha256 = _version.config_sha256
        AND candidate.evidence_version = _version.evidence_version
        AND candidate.profile_sha256 = encode(extensions.digest(jsonb_build_object(
          'version_id', candidate.version_id,
          'user_id', candidate.user_id,
          'context_key', candidate.context_key,
          'through_date', candidate.through_date,
          'neutral_p95_minutes', candidate.neutral_p95_minutes,
          'sample_count', candidate.sample_count,
          'distinct_support_dates', candidate.distinct_support_dates,
          'support_started_on', candidate.support_started_on,
          'support_ended_on', candidate.support_ended_on,
          'latest_evidence_at_utc',
            to_char(candidate.latest_evidence_at AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
          'quality_state', candidate.quality_state,
          'confidence', candidate.confidence,
          'input_sha256', candidate.input_sha256
        )::text, 'sha256'), 'hex')
      ORDER BY candidate.through_date DESC
      LIMIT 1
    )
    SELECT candidate.*
      INTO _profile
    FROM latest AS candidate;

    IF FOUND THEN
      _basis := 'personal_global';
    END IF;
  END IF;

  IF _basis IN ('personal_context', 'personal_global') THEN
    _neutral := _profile.neutral_p95_minutes;
    _confidence := _profile.confidence;
    _quality_state := _profile.quality_state;
    _selected_source_sha := _profile.profile_sha256;
    _selected_source_support := jsonb_build_object(
      'through_date', _profile.through_date,
      'sample_count', _profile.sample_count,
      'distinct_support_dates', _profile.distinct_support_dates,
      'support_started_on', _profile.support_started_on,
      'support_ended_on', _profile.support_ended_on,
      'latest_evidence_at_utc',
        to_char(_profile.latest_evidence_at AT TIME ZONE 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'input_sha256', _profile.input_sha256,
      'profile_sha256', _profile.profile_sha256,
      'config_sha256', _profile.config_sha256,
      'evidence_version', _profile.evidence_version
    );
  ELSE
    _fallback_path := pg_catalog.array_append(
      _fallback_path, 'routine_cohort'
    );

    WITH latest AS MATERIALIZED (
      SELECT candidate.*
      FROM public.routine_mode_cohort_priors AS candidate
      WHERE candidate.version_id = _version_id
        AND candidate.routine_mode = _subject.routine_mode
        AND candidate.context_key = 'personal_global'
        AND ((candidate.through_date + 1)::timestamp AT TIME ZONE 'UTC')
          <= _evaluated_at
        AND candidate.latest_evidence_at < _evaluated_at
        AND candidate.oldest_evidence_at < _evaluated_at
        AND candidate.valid_until = least(
          candidate.oldest_evidence_at
            + make_interval(days => _personal_max_age),
          candidate.oldest_evidence_at
            + make_interval(days => _cohort_max_age)
        )
        AND private.routine_mode_cohort_prior_is_valid(
          _version_id,
          _subject.routine_mode,
          candidate.through_date,
          _evaluated_at
        )
      ORDER BY candidate.through_date DESC
      LIMIT 1
    )
    SELECT candidate.*
      INTO _prior
    FROM latest AS candidate;

    IF FOUND THEN
      _basis := 'routine_cohort';
      _neutral := _prior.neutral_p95_minutes;
      _confidence := _prior.confidence;
      _quality_state := _prior.quality_state;
      _selected_source_sha := _prior.prior_sha256;
      _selected_source_support := jsonb_build_object(
        'through_date', _prior.through_date,
        'contributor_count', _prior.contributor_count,
        'distinct_support_dates', _prior.distinct_support_dates,
        'conservative_span_days', _prior.conservative_span_days,
        'support_started_on', _prior.support_started_on,
        'support_ended_on', _prior.support_ended_on,
        'latest_evidence_at_utc',
          to_char(_prior.latest_evidence_at AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'oldest_evidence_at_utc',
          to_char(_prior.oldest_evidence_at AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'valid_until_utc',
          to_char(_prior.valid_until AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'minimum_profile_confidence', _prior.minimum_profile_confidence,
        'algorithm', _prior.algorithm,
        'source_generation', _prior.source_generation,
        'input_sha256', _prior.input_sha256,
        'prior_sha256', _prior.prior_sha256,
        'config_sha256', _prior.config_sha256,
        'evidence_version', _prior.evidence_version
      );
    ELSE
      _fallback_path := pg_catalog.array_append(
        _fallback_path, 'deterministic_emergency'
      );
      _basis := 'deterministic_emergency';
      _neutral := _emergency_neutral;
      _confidence := 0;
      _quality_state := 'low_support';
      _selected_source_sha := NULL;
      _selected_source_support := jsonb_build_object(
        'contract_version', 'adr0022_v1',
        'neutral_minutes', _emergency_neutral,
        'expected_live_definition_sha256', _emergency_definition_sha
      );
    END IF;
  END IF;

  _unclamped := _neutral + _sensitivity_buffer;
  IF _basis = 'deterministic_emergency' THEN
    _threshold := _unclamped;
    _cap_reason := 'emergency_exempt';
  ELSIF _unclamped < _candidate_floor THEN
    _threshold := _candidate_floor;
    _cap_reason := 'floor';
  ELSIF _unclamped > _candidate_ceiling THEN
    _threshold := _candidate_ceiling;
    _cap_reason := 'ceiling';
  ELSE
    _threshold := _unclamped;
    _cap_reason := 'none';
  END IF;

  WITH raw_sleep AS MATERIALIZED (
    SELECT
      interval.starts_at,
      interval.ends_at,
      interval.basis,
      interval.confidence,
      interval.provenance,
      context.anchor_date,
      context.coverage_state,
      context.captured_at,
      context.finalized_at,
      context.provenance_sha256 AS context_provenance_sha256,
      tstzrange(
        greatest(interval.starts_at, _latest_session.session_end),
        least(interval.ends_at, _evaluated_at),
        '[)'
      ) AS clipped_range
    FROM private.candidate_sleep_intervals(
      _user_id,
      _latest_session.session_end,
      _evaluated_at,
      _version_id
    ) AS interval
    JOIN public.alert_sleep_night_contexts AS context
      ON context.version_id = _version_id
     AND context.user_id = _user_id
     AND context.anchor_starts_at =
       (interval.provenance ->> 'anchor_starts_at')::timestamptz
     AND context.anchor_ends_at =
       (interval.provenance ->> 'anchor_ends_at')::timestamptz
     AND context.evidence_version = _version.evidence_version
     AND context.captured_at <= _evaluated_at
     AND (
       (
         context.coverage_state = 'unknown'
         AND (
           context.finalized_at IS NULL
           OR context.finalized_at <= _evaluated_at
         )
       )
       OR (
         context.coverage_state IN ('valid', 'outage')
         AND context.finalized_at IS NOT NULL
         AND context.finalized_at >= context.anchor_ends_at
         AND context.finalized_at <= _evaluated_at
       )
     )
    WHERE interval.starts_at < _evaluated_at
      AND interval.ends_at > _latest_session.session_end
      AND greatest(interval.starts_at, _latest_session.session_end)
        < least(interval.ends_at, _evaluated_at)
  ), merged AS (
    SELECT unnest(range_agg(raw_sleep.clipped_range)) AS merged_range
    FROM raw_sleep
  ), described AS (
    SELECT
      merged.merged_range,
      jsonb_build_object(
        'starts_at_utc',
          to_char(lower(merged.merged_range) AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'ends_at_utc',
          to_char(upper(merged.merged_range) AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'sources', (
          SELECT jsonb_agg(jsonb_build_object(
            'starts_at_utc',
              to_char(source.starts_at AT TIME ZONE 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
            'ends_at_utc',
              to_char(source.ends_at AT TIME ZONE 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
            'basis', source.basis,
            'confidence', source.confidence,
            'anchor_date', source.anchor_date,
            'coverage_state', source.coverage_state,
            'captured_at_utc',
              to_char(source.captured_at AT TIME ZONE 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
            'finalized_at_utc',
              CASE WHEN source.finalized_at IS NULL THEN NULL
                ELSE to_char(source.finalized_at AT TIME ZONE 'UTC',
                  'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
              END,
            'context_provenance_sha256', source.context_provenance_sha256,
            'interval_provenance', source.provenance
          ) ORDER BY
            source.starts_at, source.ends_at, source.basis,
            source.confidence, source.provenance::text)
          FROM raw_sleep AS source
          WHERE source.clipped_range && merged.merged_range
        )
      ) AS provenance
    FROM merged
  )
  SELECT
    coalesce(
      array_agg(described.merged_range ORDER BY lower(described.merged_range)),
      ARRAY[]::tstzrange[]
    ),
    coalesce(
      jsonb_agg(described.provenance ORDER BY lower(described.merged_range)),
      '[]'::jsonb
    )
    INTO _sleep_ranges, _sleep_provenance
  FROM described;

  FOREACH _sleep_range IN ARRAY _sleep_ranges
  LOOP
    _sleep_seconds := _sleep_seconds
      + extract(epoch FROM (upper(_sleep_range) - lower(_sleep_range)));
  END LOOP;

  _wall_seconds :=
    extract(epoch FROM (_evaluated_at - _latest_session.session_end));
  _effective_minutes :=
    greatest(0::double precision, _wall_seconds - _sleep_seconds) / 60.0;
  _would_alert := _effective_minutes >= _threshold;

  IF _would_alert THEN
    _deadline_basis := 'known_interval_inversion';
    _remaining_seconds := _threshold::double precision * 60.0;
    _cursor := _latest_session.session_end;

    FOREACH _sleep_range IN ARRAY _sleep_ranges
    LOOP
      IF lower(_sleep_range) > _cursor THEN
        _awake_seconds := extract(epoch FROM (lower(_sleep_range) - _cursor));
        IF _remaining_seconds <= _awake_seconds THEN
          _deadline := _cursor + make_interval(secs => _remaining_seconds);
          EXIT;
        END IF;
        _remaining_seconds := _remaining_seconds - _awake_seconds;
      END IF;
      _cursor := greatest(_cursor, upper(_sleep_range));
    END LOOP;

    IF _deadline IS NULL THEN
      _deadline := _cursor + make_interval(secs => _remaining_seconds);
    END IF;
  ELSE
    _deadline_basis := 'no_future_exclusion';
    _deadline := _evaluated_at
      + make_interval(secs => (_threshold - _effective_minutes) * 60.0);
  END IF;

  _decision_provenance := jsonb_build_object(
    'version_id', _version_id,
    'evaluator_version', _evaluator_version,
    'evaluated_at', _evaluated_at_utc,
    'evidence_cutoff', _evaluated_at_utc,
    'replayable', true,
    'unreplayable_reason', NULL,
    'model_config_sha256', _version.config_sha256,
    'evidence_version', _version.evidence_version,
    'emergency_contract_version',
      _version.config #>> '{emergency,contract_version}',
    'emergency_expected_live_definition_sha256', _emergency_definition_sha,
    'subject_context_sha256', _subject.subject_context_sha256,
    'canonical_sensitivity', _subject.canonical_sensitivity,
    'routine_mode', _subject.routine_mode,
    'timezone', _subject.timezone,
    'utc_offset_minutes', _subject.utc_offset_minutes,
    'latest_session', jsonb_build_object(
      'session_start_utc',
        to_char(_latest_session.session_start AT TIME ZONE 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'session_end_utc',
        to_char(_latest_session.session_end AT TIME ZONE 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'context_key', _latest_session.context_key,
      'evidence_count', _latest_session.evidence_count,
      'quality_state', _latest_session.quality_state
    ),
    'basis', _basis,
    'fallback_path', to_jsonb(_fallback_path),
    'selected_source_sha256', _selected_source_sha,
    'selected_source_support', _selected_source_support,
    'neutral_threshold_minutes', _neutral,
    'sensitivity_buffer_minutes', _sensitivity_buffer,
    'unclamped_candidate_threshold_minutes', _unclamped,
    'candidate_floor_minutes', _candidate_floor,
    'candidate_ceiling_minutes', _candidate_ceiling,
    'candidate_cap_reason', _cap_reason,
    'candidate_threshold_minutes', _threshold,
    'sleep_interval_provenance', _sleep_provenance,
    'effective_silence_minutes', _effective_minutes,
    'candidate_deadline',
      to_char(_deadline AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'deadline_basis', _deadline_basis,
    'would_alert', _would_alert,
    'confidence', _confidence,
    'quality_state', _quality_state,
    'guardian_used_as_activity', false
  );
  _provenance_sha := encode(
    extensions.digest(_decision_provenance::text, 'sha256'), 'hex'
  );

  RETURN jsonb_build_object(
    'version_id', _version_id,
    'evaluator_version', _evaluator_version,
    'evaluated_at', _evaluated_at_utc,
    'evidence_cutoff', _evaluated_at_utc,
    'replayable', true,
    'unreplayable_reason', NULL,
    'basis', _basis,
    'context_key', _latest_session.context_key,
    'neutral_threshold_minutes', _neutral,
    'sensitivity_buffer_minutes', _sensitivity_buffer,
    'unclamped_candidate_threshold_minutes', _unclamped,
    'candidate_floor_minutes', _candidate_floor,
    'candidate_ceiling_minutes', _candidate_ceiling,
    'candidate_cap_reason', _cap_reason,
    'candidate_threshold_minutes', _threshold,
    'effective_silence_minutes', _effective_minutes,
    'candidate_deadline',
      to_char(_deadline AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'deadline_basis', _deadline_basis,
    'would_alert', _would_alert,
    'confidence', _confidence,
    'quality_state', _quality_state,
    'fallback_path', to_jsonb(_fallback_path),
    'sleep_interval_provenance', _sleep_provenance,
    'selected_source_sha256', _selected_source_sha,
    'subject_context_sha256', _subject.subject_context_sha256,
    'decision_provenance', _decision_provenance,
    'provenance_sha256', _provenance_sha,
    'guardian_used_as_activity', false
  );
END;
$$;


ALTER FUNCTION "private"."resolve_alert_candidate"("_user_id" "uuid", "_evaluated_at" timestamp with time zone, "_version_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."routine_mode_cohort_prior_is_valid"("_version_id" "uuid", "_routine_mode" "text", "_through_date" "date", "_evaluated_at" timestamp with time zone) RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    SET "DateStyle" TO 'ISO, YMD'
    SET "extra_float_digits" TO '3'
    AS $$
DECLARE
  _prior public.routine_mode_cohort_priors%ROWTYPE;
  _config jsonb;
  _config_sha256 text;
  _evidence_version text;
  _status text;
  _generation bigint;
  _mode text := private.canonical_routine_mode(_routine_mode);
  _min_contributors integer;
  _min_dates integer;
  _min_span integer;
  _min_confidence double precision;
  _floor integer;
  _ceiling integer;
  _algorithm text;
  _expected_confidence double precision;
  _expected_quality text;
  _expected_sha text;
  _cutoff timestamptz;
BEGIN
  IF _version_id IS NULL OR _through_date IS NULL OR _evaluated_at IS NULL
     OR _mode NOT IN ('regular_9to5', 'semester_break', 'shift_irregular') THEN
    RETURN false;
  END IF;
  _cutoff := (_through_date + 1)::timestamptz;
  IF _evaluated_at < _cutoff THEN
    RETURN false;
  END IF;

  SELECT * INTO _prior
  FROM public.routine_mode_cohort_priors AS prior
  WHERE prior.version_id = _version_id
    AND prior.routine_mode = _mode
    AND prior.context_key = 'personal_global'
    AND prior.through_date = _through_date;
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  SELECT version.config, version.config_sha256, version.evidence_version, version.status, generation.generation
    INTO _config, _config_sha256, _evidence_version, _status, _generation
  FROM public.alert_model_versions AS version
  JOIN public.routine_mode_cohort_generations AS generation ON generation.routine_mode = _mode
  WHERE version.id = _version_id;
  IF NOT FOUND OR _status NOT IN ('replay', 'shadow')
     OR _evidence_version <> 'canonical-v2'
     OR _config_sha256 <> encode(extensions.digest(_config::text, 'sha256'), 'hex')
     OR _prior.config_sha256 <> _config_sha256
     OR _prior.evidence_version <> _evidence_version
     OR _prior.source_generation <> _generation
     OR _prior.valid_until IS NULL OR _prior.valid_until <= _cutoff
     OR _evaluated_at >= _prior.valid_until
     OR _prior.contributor_count <= 0 OR _prior.distinct_support_dates <= 0
     OR _prior.conservative_span_days IS NULL OR _prior.conservative_span_days <= 0
     OR _prior.minimum_profile_confidence IS NULL OR _prior.minimum_profile_confidence <= 0
     OR _prior.confidence < 0 OR _prior.confidence > 1 THEN
    RETURN false;
  END IF;

  BEGIN
    _min_contributors := (_config #>> '{cohort,min_contributors}')::integer;
    _min_dates := (_config #>> '{cohort,min_support_dates}')::integer;
    _min_span := (_config #>> '{cohort,min_span_days}')::integer;
    _min_confidence := (_config #>> '{cohort,min_confidence}')::double precision;
    _floor := (_config #>> '{cohort,contribution_floor_minutes}')::integer;
    _ceiling := (_config #>> '{cohort,contribution_ceiling_minutes}')::integer;
    _algorithm := _config #>> '{cohort,algorithm}';
  EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
    RETURN false;
  END;
  IF _min_contributors <= 0 OR _min_dates <= 0 OR _min_span <= 0
     OR _min_confidence <= 0 OR _min_confidence > 1
     OR _floor <= 0 OR _ceiling < _floor
     OR _algorithm NOT IN ('weighted_median', 'trimmed_mean')
     OR _config #>> '{cohort,confidence_formula_version}' <> 'cohort_support_min_v1'
     OR _prior.algorithm <> _algorithm THEN
    RETURN false;
  END IF;
  IF _prior.neutral_p95_minutes < _floor OR _prior.neutral_p95_minutes > _ceiling THEN
    RETURN false;
  END IF;

  _expected_confidence := least(
    1::double precision,
    _prior.contributor_count::double precision / _min_contributors::double precision,
    _prior.distinct_support_dates::double precision / _min_dates::double precision,
    _prior.conservative_span_days::double precision / _min_span::double precision,
    _prior.minimum_profile_confidence / _min_confidence
  );
  _expected_quality := CASE
    WHEN _prior.contributor_count >= _min_contributors
      AND _prior.distinct_support_dates >= _min_dates
      AND _prior.conservative_span_days >= _min_span
      AND _prior.minimum_profile_confidence >= _min_confidence
      THEN 'valid'
    ELSE 'low_support'
  END;
  IF _prior.quality_state <> _expected_quality
     OR _prior.confidence <> _expected_confidence
     OR _prior.quality_state <> 'valid' THEN
    RETURN false;
  END IF;

  _expected_sha := encode(extensions.digest(concat_ws('|',
    _prior.input_sha256, _prior.version_id::text, _prior.routine_mode, _prior.context_key,
    _prior.through_date::text, _prior.contributor_count::text, _prior.distinct_support_dates::text,
    _prior.conservative_span_days::text, _prior.support_started_on::text, _prior.support_ended_on::text,
    _prior.latest_evidence_at::text, _prior.oldest_evidence_at::text, _prior.valid_until::text,
    _prior.neutral_p95_minutes::text, _prior.quality_state, _prior.confidence::text,
    _prior.minimum_profile_confidence::text, _prior.algorithm, _prior.config_sha256,
    _prior.evidence_version, _prior.source_generation::text
  ), 'sha256'), 'hex');
  RETURN _prior.prior_sha256 = _expected_sha;
END;
$$;


ALTER FUNCTION "private"."routine_mode_cohort_prior_is_valid"("_version_id" "uuid", "_routine_mode" "text", "_through_date" "date", "_evaluated_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."run_adaptive_alert_shadow_cycle"("_version_id" "uuid", "_evaluated_at" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    AS $$
DECLARE
  _runtime private.adaptive_alert_shadow_runtime_config%ROWTYPE;
  _version public.alert_model_versions%ROWTYPE;
  _minute timestamptz;
  _started_at timestamptz := clock_timestamp();
  _result jsonb;
  _population_count integer;
  _evaluated_count integer;
  _before_dml bigint := 0;
  _after_dml bigint := 0;
  _duration_ms integer;
  _metrics jsonb;
  _run_sha text;
  _person_id uuid;
  _population_total integer;
BEGIN
  SELECT c.* INTO _runtime
  FROM private.adaptive_alert_shadow_runtime_config AS c
  WHERE c.singleton;
  IF _runtime.enabled IS NOT TRUE THEN
    RETURN jsonb_build_object('status', 'disabled');
  END IF;
  IF _runtime.version_id IS DISTINCT FROM _version_id THEN
    RAISE EXCEPTION 'shadow_runtime_version_mismatch';
  END IF;
  IF _evaluated_at IS NULL THEN
    RAISE EXCEPTION 'shadow_invalid_evaluation_time';
  END IF;
  _minute := date_trunc('minute', _evaluated_at AT TIME ZONE 'UTC')
    AT TIME ZONE 'UTC';

  IF EXISTS (
    SELECT 1 FROM private.adaptive_alert_shadow_cycle_runs AS r
    WHERE r.version_id = _version_id AND r.evaluated_minute = _minute
  ) THEN
    RETURN jsonb_build_object('status', 'duplicate');
  END IF;
  IF NOT pg_try_advisory_xact_lock(
    hashtextextended('adaptive-alert-shadow:' || _version_id::text, 0)
  ) THEN
    RETURN jsonb_build_object('status', 'busy');
  END IF;

  SELECT v.* INTO _version
  FROM public.alert_model_versions AS v
  WHERE v.id = _version_id;
  IF NOT FOUND OR _version.status <> 'shadow'
     OR _version.shadow_enabled_at IS NULL
     OR _version.shadow_enabled_at > _minute
     OR _version.evidence_version <> 'canonical-v2'
     OR _version.config_sha256 <>
       encode(extensions.digest(_version.config::text, 'sha256'), 'hex') THEN
    RAISE EXCEPTION 'shadow_version_validation_failed';
  END IF;
  IF NOT private.shadow_live_definition_matches(
    _version.config #>> '{emergency,expected_live_definition_sha256}',
    pg_get_functiondef('private.silence_threshold(uuid)'::regprocedure)
  ) THEN
    RAISE EXCEPTION 'shadow_live_hash_mismatch';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS c
    WHERE c.oid IN (
      'private.adaptive_alert_shadow_user_state'::regclass,
      'private.adaptive_alert_shadow_cycle_runs'::regclass,
      'private.adaptive_alert_shadow_daily_reports'::regclass
    ) AND NOT c.relrowsecurity
  ) OR has_table_privilege(
    'authenticated', 'private.adaptive_alert_shadow_user_state', 'SELECT'
  ) THEN
    RAISE EXCEPTION 'shadow_acl_validation_failed';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_publication_tables AS p
    WHERE p.tablename LIKE 'adaptive_alert_shadow_%'
      AND p.schemaname IN ('private', 'public')
  ) THEN
    RAISE EXCEPTION 'shadow_publication_validation_failed';
  END IF;

  SELECT count(*)::integer INTO _population_total
  FROM (
    SELECT DISTINCT ds.user_id
    FROM public.device_state AS ds
    WHERE EXISTS (
      SELECT 1
      FROM public.group_members AS gm
      WHERE gm.user_id = ds.user_id
        AND gm.status = 'active'
        AND gm.monitored
    )
  ) AS population;
  IF _population_total > _runtime.max_population THEN
    RAISE EXCEPTION 'shadow_population_budget_exceeded';
  END IF;

  SELECT coalesce(sum(
    s.n_tup_ins + s.n_tup_upd + s.n_tup_del
  ), 0) INTO _before_dml
  FROM pg_catalog.pg_stat_xact_user_tables AS s
  WHERE s.relid IN (
    'public.alerts'::regclass,
    'public.alert_events'::regclass,
    'public.notifications'::regclass
  );

  IF _runtime.accept_coverage_leases THEN
    FOR _person_id IN
      WITH population AS (
        SELECT DISTINCT ds.user_id
        FROM public.device_state AS ds
        WHERE EXISTS (
          SELECT 1
          FROM public.group_members AS gm
          WHERE gm.user_id = ds.user_id
            AND gm.status = 'active'
            AND gm.monitored
        )
      )
      SELECT p.user_id FROM population AS p
      ORDER BY p.user_id LIMIT _runtime.max_population
    LOOP
      PERFORM private.finalize_alert_shadow_coverage(
        _person_id, _minute, _runtime.detail_retention_days
      );
    END LOOP;
  END IF;

  PERFORM private.capture_alert_shadow_subject_contexts(
    _version_id, _minute, _runtime.max_population
  );
  PERFORM private.capture_alert_shadow_interventions(
    _version_id, _minute, _runtime.max_population
  );
  PERFORM private.maintain_adaptive_alert_shadow(
    _minute, _runtime.max_population
  );
  _result := private.record_alert_judgment_shadow_operational(
    _version_id, _minute, _runtime.max_population
  );

  SELECT coalesce(sum(
    s.n_tup_ins + s.n_tup_upd + s.n_tup_del
  ), 0) INTO _after_dml
  FROM pg_catalog.pg_stat_xact_user_tables AS s
  WHERE s.relid IN (
    'public.alerts'::regclass,
    'public.alert_events'::regclass,
    'public.notifications'::regclass
  );
  IF _after_dml <> _before_dml THEN
    RAISE EXCEPTION 'shadow_live_write_detected';
  END IF;

  _population_count := (_result ->> 'population_count')::integer;
  _evaluated_count := (_result ->> 'evaluated_count')::integer;
  _duration_ms := greatest(
    0, round(extract(epoch FROM (clock_timestamp() - _started_at)) * 1000)::integer
  );
  _metrics := jsonb_build_object(
    'replayable_count', (_result ->> 'replayable_count')::integer,
    'unreplayable_count', (_result ->> 'unreplayable_count')::integer,
    'persisted_count', (_result ->> 'persisted_count')::integer
  );
  _run_sha := encode(extensions.digest(jsonb_build_object(
    'version_id', _version_id,
    'evaluated_minute', _minute,
    'population_count', _population_count,
    'evaluated_count', _evaluated_count,
    'metrics', _metrics
  )::text, 'sha256'), 'hex');

  INSERT INTO private.adaptive_alert_shadow_cycle_runs (
    version_id, evaluated_minute, status, duration_ms, population_count,
    evaluated_count, metrics, run_sha256
  ) VALUES (
    _version_id, _minute,
    CASE WHEN _population_count = 0 THEN 'empty' ELSE 'completed' END,
    _duration_ms, _population_count, _evaluated_count, _metrics, _run_sha
  );

  RETURN jsonb_build_object(
    'status', 'completed',
    'population_count', _population_count,
    'evaluated_count', _evaluated_count,
    'duration_ms', _duration_ms
  );
END;
$$;


ALTER FUNCTION "private"."run_adaptive_alert_shadow_cycle"("_version_id" "uuid", "_evaluated_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."run_alert_judgment_replay"("_version_id" "uuid", "_from" timestamp with time zone, "_to" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    SET "DateStyle" TO 'ISO, YMD'
    SET "extra_float_digits" TO '3'
    AS $$
DECLARE
  _replay_contract constant text := 'adaptive_replay_v1';
  _evaluator_contract constant text := 'adaptive_candidate_v1';
  _version public.alert_model_versions%ROWTYPE;
  _gap_minutes integer;
  _max_range_days integer;
  _max_units integer;
  _unit_count integer;
  _units_captured jsonb;
  _evaluated_count integer;
  _replayable_count integer;
  _unreplayable_count integer;
  _unreplayable_reason_counts jsonb;
  _live_alert_rows_observed integer;
  _unmatched_live_silence_alert_rows integer;
  _candidate_would_alert_gaps integer;
  _proxy_denominator integer;
  _both_proxy integer;
  _live_only_proxy integer;
  _candidate_only_proxy integer;
  _neither_proxy integer;
  _threshold_delta_denominator integer;
  _median_delta double precision;
  _p95_delta double precision;
  _basis_counts jsonb;
  _quality_counts jsonb;
  _cap_reason_counts jsonb;
  _report_status text;
  _units_json jsonb;
  _unmatched_json jsonb;
  _metrics jsonb;
  _input_sha text;
  _output_sha text;
  _from_utc text := to_char(_from AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
  _to_utc text := to_char(_to AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
BEGIN
  IF _version_id IS NULL OR _from IS NULL OR _to IS NULL OR NOT (_from < _to) THEN
    RAISE EXCEPTION 'adaptive_alert_replay_invalid_range'
      USING DETAIL = 'from must be strictly less than to';
  END IF;

  SELECT v.* INTO _version
  FROM public.alert_model_versions AS v
  WHERE v.id = _version_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'adaptive_alert_replay_unknown_version';
  END IF;

  IF _version.status <> 'replay' THEN
    RAISE EXCEPTION 'adaptive_alert_replay_invalid_version_status';
  END IF;

  IF _version.config_sha256
      <> encode(extensions.digest(_version.config::text, 'sha256'), 'hex') THEN
    RAISE EXCEPTION 'adaptive_alert_replay_config_hash_mismatch';
  END IF;

  IF _version.evidence_version <> 'canonical-v2' THEN
    RAISE EXCEPTION 'adaptive_alert_replay_unsupported_evidence_version';
  END IF;

  IF NOT private.alert_candidate_config_is_valid(_version.config) THEN
    RAISE EXCEPTION 'adaptive_alert_replay_invalid_evaluator_config';
  END IF;

  IF _version.config #>> '{evaluator,contract_version}' <> _evaluator_contract THEN
    RAISE EXCEPTION 'adaptive_alert_replay_unsupported_evaluator_contract';
  END IF;

  IF NOT private.replay_config_is_valid(_version.config) THEN
    RAISE EXCEPTION 'adaptive_alert_replay_invalid_replay_config';
  END IF;

  IF _version.config #>> '{replay,contract_version}' <> _replay_contract THEN
    RAISE EXCEPTION 'adaptive_alert_replay_unsupported_replay_contract';
  END IF;

  _max_range_days := (_version.config #>> '{replay,max_range_days}')::integer;
  _max_units := (_version.config #>> '{replay,max_units}')::integer;
  _gap_minutes := (_version.config #>> '{sessionization,gap_minutes}')::integer;

  IF (_to - _from) > make_interval(days => _max_range_days) THEN
    RAISE EXCEPTION 'adaptive_alert_replay_range_exceeds_max_range_days';
  END IF;

  -- Enumerate and sessionize exactly once, in exactly one MATERIALIZED CTE,
  -- inside a single statement/snapshot. The bounded result is captured into
  -- an in-memory jsonb array only (never a temp/permanent table, never a
  -- per-user row anywhere): no later statement re-reads behavior_pings, so
  -- no concurrent ping insert between statements can change what was
  -- counted against replay.max_units or what gets evaluated below.
  WITH candidate_replay_units AS MATERIALIZED (
    WITH range_admitted AS (
      SELECT p.id, p.user_id, p.received_at
      FROM public.behavior_pings AS p
      WHERE p.ingest_version = 2
        AND p.received_at >= _from
        AND p.received_at < _to
        AND p.at < _to
        AND abs(extract(epoch FROM (p.received_at - p.at))) <= 300
    ), prior_admitted AS (
      SELECT prior.id, prior.user_id, prior.received_at
      FROM (SELECT DISTINCT user_id FROM range_admitted) AS active_user
      CROSS JOIN LATERAL (
        SELECT p.id, p.user_id, p.received_at
        FROM public.behavior_pings AS p
        WHERE p.user_id = active_user.user_id
          AND p.ingest_version = 2
          AND p.received_at < _from
          AND p.at < _to
          AND abs(extract(epoch FROM (p.received_at - p.at))) <= 300
        ORDER BY p.received_at DESC, p.id DESC
        LIMIT 1
      ) AS prior
    ), admitted AS (
      SELECT * FROM range_admitted
      UNION ALL
      SELECT * FROM prior_admitted
    ), marked AS (
      SELECT admitted.*,
        CASE
          WHEN lag(received_at) OVER (PARTITION BY user_id ORDER BY received_at, id) IS NULL
            OR received_at - lag(received_at) OVER (PARTITION BY user_id ORDER BY received_at, id)
              > make_interval(mins => _gap_minutes)
          THEN 1 ELSE 0
        END AS starts_session
      FROM admitted
    ), grouped AS (
      SELECT marked.*,
        sum(starts_session) OVER (PARTITION BY user_id ORDER BY received_at, id) AS session_no
      FROM marked
    ), summarized AS (
      SELECT user_id, session_no,
        min(received_at) AS session_start,
        max(received_at) AS session_end
      FROM grouped
      GROUP BY user_id, session_no
    ), ordered AS (
      SELECT user_id, session_end,
        lead(session_start) OVER (PARTITION BY user_id ORDER BY session_start) AS next_start
      FROM summarized
    )
    SELECT user_id, session_end, next_start
    FROM ordered
    WHERE next_start IS NOT NULL
      AND next_start >= _from
      AND next_start < _to
  )
  SELECT
    count(*)::integer,
    coalesce(jsonb_agg(
      jsonb_build_object(
        'user_id', user_id,
        'session_end_utc',
          to_char(session_end AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'next_start_utc',
          to_char(next_start AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
      )
      ORDER BY session_end, next_start, user_id
    ), '[]'::jsonb)
  INTO _unit_count, _units_captured
  FROM candidate_replay_units;

  IF _unit_count > _max_units THEN
    RAISE EXCEPTION 'adaptive_alert_replay_max_units_exceeded';
  END IF;

  -- Evaluate strictly from the already-captured bounded set: exactly one
  -- resolve_alert_candidate call per unit, and no further read of
  -- behavior_pings, so the MATERIALIZED CTE above is the only
  -- sessionization pass in the whole run.
  WITH captured_units AS (
    SELECT
      (elem ->> 'user_id')::uuid AS user_id,
      (elem ->> 'session_end_utc')::timestamptz AS session_end,
      (elem ->> 'next_start_utc')::timestamptz AS next_start
    FROM jsonb_array_elements(_units_captured) AS elem
  ), evaluated AS MATERIALIZED (
    SELECT u.user_id, u.session_end, u.next_start,
      private.resolve_alert_candidate(u.user_id, u.next_start, _version_id) AS result
    FROM captured_units AS u
  ), live_matches AS (
    SELECT e.user_id, e.session_end, e.next_start,
      count(a.id)::integer AS matched_count
    FROM evaluated AS e
    LEFT JOIN public.alerts AS a
      ON a.user_id = e.user_id
     AND a.cause = 'silence'
     AND a.opened_at >= e.session_end
     AND a.opened_at < e.next_start
    GROUP BY e.user_id, e.session_end, e.next_start
  ), per_unit AS (
    SELECT
      e.user_id, e.session_end, e.next_start, e.result,
      m.matched_count,
      (e.result ->> 'replayable')::boolean AS replayable,
      e.result ->> 'unreplayable_reason' AS unreplayable_reason,
      (e.result ->> 'would_alert')::boolean AS would_alert,
      e.result ->> 'candidate_cap_reason' AS cap_reason,
      e.result ->> 'basis' AS basis,
      e.result ->> 'quality_state' AS quality_state,
      (e.result ->> 'candidate_threshold_minutes')::integer AS candidate_threshold_minutes,
      (e.result ->> 'sensitivity_buffer_minutes')::integer AS sensitivity_buffer_minutes
    FROM evaluated AS e
    JOIN live_matches AS m
      ON m.user_id = e.user_id
     AND m.session_end = e.session_end
     AND m.next_start = e.next_start
  ), unreplayable_reason_agg AS (
    SELECT coalesce(jsonb_object_agg(unreplayable_reason, cnt), '{}'::jsonb) AS obj
    FROM (
      SELECT unreplayable_reason, count(*)::integer AS cnt
      FROM per_unit
      WHERE NOT replayable
      GROUP BY unreplayable_reason
    ) AS t
  ), basis_agg AS (
    SELECT coalesce(jsonb_object_agg(basis, cnt), '{}'::jsonb) AS obj
    FROM (
      SELECT basis, count(*)::integer AS cnt
      FROM per_unit
      WHERE replayable
      GROUP BY basis
    ) AS t
  ), quality_agg AS (
    SELECT coalesce(jsonb_object_agg(quality_state, cnt), '{}'::jsonb) AS obj
    FROM (
      SELECT quality_state, count(*)::integer AS cnt
      FROM per_unit
      WHERE replayable
      GROUP BY quality_state
    ) AS t
  ), cap_reason_agg AS (
    SELECT coalesce(jsonb_object_agg(cap_reason, cnt), '{}'::jsonb) AS obj
    FROM (
      SELECT cap_reason, count(*)::integer AS cnt
      FROM per_unit
      WHERE replayable
      GROUP BY cap_reason
    ) AS t
  ), unmatched_agg AS (
    SELECT count(*)::integer AS unmatched_count,
      coalesce(jsonb_agg(
        to_char(a.opened_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
        ORDER BY a.opened_at, a.id
      ), '[]'::jsonb) AS unmatched_json
    FROM public.alerts AS a
    WHERE a.cause = 'silence'
      AND a.opened_at >= _from
      AND a.opened_at < _to
      AND NOT EXISTS (
        SELECT 1
        FROM captured_units AS u
        WHERE u.user_id = a.user_id
          AND a.opened_at >= u.session_end
          AND a.opened_at < u.next_start
      )
  ), units_agg AS (
    SELECT coalesce(jsonb_agg(
      jsonb_build_object(
        'session_end_utc', to_char(session_end AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'next_start_utc', to_char(next_start AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'replayable', replayable,
        'unreplayable_reason', unreplayable_reason,
        'evaluator_provenance_sha256', result ->> 'provenance_sha256',
        'matched_live_count', matched_count
      )
      ORDER BY
        session_end,
        next_start,
        coalesce(result ->> 'provenance_sha256', ''),
        replayable,
        coalesce(unreplayable_reason, ''),
        matched_count
    ), '[]'::jsonb) AS units_json
    FROM per_unit
  )
  SELECT
    count(*)::integer,
    count(*) FILTER (WHERE replayable)::integer,
    count(*) FILTER (WHERE NOT replayable)::integer,
    (SELECT obj FROM unreplayable_reason_agg),
    coalesce(sum(matched_count) FILTER (WHERE replayable), 0)::integer,
    (SELECT unmatched_count FROM unmatched_agg),
    count(*) FILTER (WHERE replayable AND would_alert)::integer,
    count(*) FILTER (WHERE replayable)::integer,
    count(*) FILTER (WHERE replayable AND matched_count > 0 AND would_alert)::integer,
    count(*) FILTER (WHERE replayable AND matched_count > 0 AND NOT would_alert)::integer,
    count(*) FILTER (WHERE replayable AND matched_count = 0 AND would_alert)::integer,
    count(*) FILTER (WHERE replayable AND matched_count = 0 AND NOT would_alert)::integer,
    count(*) FILTER (WHERE replayable)::integer,
    (SELECT percentile_cont(0.5) WITHIN GROUP (
      ORDER BY (candidate_threshold_minutes - (90 + sensitivity_buffer_minutes)))
      FROM per_unit WHERE replayable),
    (SELECT percentile_cont(0.95) WITHIN GROUP (
      ORDER BY (candidate_threshold_minutes - (90 + sensitivity_buffer_minutes)))
      FROM per_unit WHERE replayable),
    (SELECT obj FROM basis_agg),
    (SELECT obj FROM quality_agg),
    (SELECT obj FROM cap_reason_agg),
    (SELECT units_json FROM units_agg),
    (SELECT unmatched_json FROM unmatched_agg)
  INTO
    _evaluated_count, _replayable_count, _unreplayable_count, _unreplayable_reason_counts,
    _live_alert_rows_observed, _unmatched_live_silence_alert_rows,
    _candidate_would_alert_gaps, _proxy_denominator,
    _both_proxy, _live_only_proxy, _candidate_only_proxy, _neither_proxy,
    _threshold_delta_denominator, _median_delta, _p95_delta,
    _basis_counts, _quality_counts, _cap_reason_counts,
    _units_json, _unmatched_json
  FROM per_unit;

  IF _evaluated_count = 0 THEN
    _report_status := 'empty';
  ELSIF _replayable_count = 0 THEN
    _report_status := 'all_unreplayable';
  ELSIF _unreplayable_count = 0 THEN
    _report_status := 'complete';
  ELSE
    _report_status := 'partial';
  END IF;

  -- Canonical input hash: contract versions, model config/evidence hash,
  -- exact range, and an ordered multiset of unit timestamps, Task 6
  -- provenance hashes, and ordered live-proxy timestamps/counts. It excludes
  -- user/alert ids, runtime/transaction timing, created_at, and this row's
  -- own hash columns; duplicate tokens remain duplicated.
  _input_sha := encode(extensions.digest(jsonb_build_object(
    'replay_contract_version', _replay_contract,
    'evaluator_contract_version', _evaluator_contract,
    'model_config_sha256', _version.config_sha256,
    'model_evidence_version', _version.evidence_version,
    'from_utc', _from_utc,
    'to_utc', _to_utc,
    'units', _units_json,
    'unmatched_live_silence_alert_opened_at_utc', _unmatched_json
  )::text, 'sha256'), 'hex');

  _metrics := jsonb_build_object(
    'version_id', _version_id,
    'replay_contract_version', _replay_contract,
    'evaluator_version', _evaluator_contract,
    'from', _from_utc,
    'to', _to_utc,
    'report_status', _report_status,
    'evaluated_count', _evaluated_count,
    'replayable_count', _replayable_count,
    'unreplayable_count', _unreplayable_count,
    'unreplayable_reason_counts', _unreplayable_reason_counts,
    'replayable_completed_gap_count', _replayable_count,
    'live_alert_rows_observed', _live_alert_rows_observed,
    'unmatched_live_silence_alert_rows', _unmatched_live_silence_alert_rows,
    'candidate_would_alert_gaps', _candidate_would_alert_gaps,
    'proxy_denominator_replayable_gaps', _proxy_denominator,
    'both_proxy', _both_proxy,
    'live_only_proxy', _live_only_proxy,
    'candidate_only_proxy', _candidate_only_proxy,
    'neither_proxy', _neither_proxy,
    'threshold_delta_denominator_replayable_gaps', _threshold_delta_denominator,
    'median_candidate_minus_adr0022_threshold_proxy_minutes', _median_delta,
    'p95_candidate_minus_adr0022_threshold_proxy_minutes', _p95_delta,
    'basis_counts', _basis_counts,
    'quality_counts', _quality_counts,
    'cap_reason_counts', _cap_reason_counts,
    'adjudicated_risk_outcomes', 0,
    'unadjudicated_replayable_count', _replayable_count,
    'safety_claim', 'not_evaluated',
    'promotion_eligible', false
  );

  _output_sha := encode(extensions.digest(
    (_metrics || jsonb_build_object('input_sha256', _input_sha))::text, 'sha256'
  ), 'hex');

  INSERT INTO public.alert_judgment_evaluations (
    version_id, evaluation_kind, evaluated_from, evaluated_to,
    metrics, input_sha256, output_sha256, evaluator_version, promotion_eligible
  ) VALUES (
    _version_id, 'historical_replay', _from, _to,
    _metrics, _input_sha, _output_sha, _evaluator_contract, false
  )
  ON CONFLICT (version_id, evaluation_kind, evaluated_from, evaluated_to)
  DO UPDATE SET
    metrics = EXCLUDED.metrics,
    input_sha256 = EXCLUDED.input_sha256,
    output_sha256 = EXCLUDED.output_sha256,
    evaluator_version = EXCLUDED.evaluator_version,
    promotion_eligible = false
  WHERE public.alert_judgment_evaluations.metrics IS DISTINCT FROM EXCLUDED.metrics
     OR public.alert_judgment_evaluations.input_sha256 IS DISTINCT FROM EXCLUDED.input_sha256
     OR public.alert_judgment_evaluations.output_sha256 IS DISTINCT FROM EXCLUDED.output_sha256
     OR public.alert_judgment_evaluations.evaluator_version IS DISTINCT FROM EXCLUDED.evaluator_version;

  RETURN _metrics || jsonb_build_object(
    'input_sha256', _input_sha, 'output_sha256', _output_sha
  );
END;
$$;


ALTER FUNCTION "private"."run_alert_judgment_replay"("_version_id" "uuid", "_from" timestamp with time zone, "_to" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."shadow_live_definition_matches"("_expected_sha256" "text", "_actual_definition" "text") RETURNS boolean
    LANGUAGE "sql" IMMUTABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
      WITH hashes AS (
        SELECT
          encode(
            extensions.digest(_actual_definition, 'sha256'),
            'hex'
          ) AS raw_sha256,
          encode(
            extensions.digest(
              replace(_actual_definition, E'\r\n', E'\n'),
              'sha256'
            ),
            'hex'
          ) AS lf_sha256
      )
      SELECT CASE
        WHEN _expected_sha256 !~ '^[a-f0-9]{64}$'
          OR _actual_definition IS NULL
          THEN false
        ELSE
          _expected_sha256 IN (hashes.raw_sha256, hashes.lf_sha256)
          OR (
            _expected_sha256 =
              '1907d59473d274d46a0e8e0b9ce8027037b4494b0dddf073cb46abf67db92e21'
            AND hashes.lf_sha256 IN (
              '686116ef8f2df1d78f6d0d48ded8019555f283b098eeb5d354cfa1c14ebbcdca',
              '6be4ed54feff52428cf1d86210126bd9362953201fc5ac8b9e885abd586092ce',
              '1e98764ff3cf99f093bd1e292d2a14d84000c2863c9f0cb663227500e8208923'
            )
          )
      END
      FROM hashes
    $_$;


ALTER FUNCTION "private"."shadow_live_definition_matches"("_expected_sha256" "text", "_actual_definition" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."shares_community"("_a" "uuid", "_b" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1
    from public.community_members x
    join public.community_members y on x.community_id = y.community_id
    where x.user_id = _a and y.user_id = _b
      and x.status = 'active' and y.status = 'active' and _a <> _b
  );
$$;


ALTER FUNCTION "private"."shares_community"("_a" "uuid", "_b" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."shares_group_with"("_other" "uuid", "_user" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1
    from public.group_members a
    join public.group_members b on a.group_id = b.group_id
    where a.user_id = _user and b.user_id = _other
      and a.status = 'active' and b.status = 'active'
  );
$$;


ALTER FUNCTION "private"."shares_group_with"("_other" "uuid", "_user" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."silence_threshold"("_user_id" "uuid") RETURNS interval
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    AS $$
DECLARE
  _bound_minutes integer;
  _sensitivity text;
  _buffer_minutes integer;
BEGIN
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


ALTER FUNCTION "private"."silence_threshold"("_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."sleep_relaxed"("_user" "uuid", "_at" timestamp with time zone) RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  _start      time;
  _end        time;
  _timezone   text;
  _local_now  timestamptz;
  _local_time time;
  _local_date date;
  _start_ts   timestamptz;
  _end_ts     timestamptz;
  _wake_ts    timestamptz;
begin
  select sleep_start_local, sleep_end_local, coalesce(timezone, 'UTC')
    into _start, _end, _timezone
    from public.user_settings
   where user_id = _user;

  if _start is null or _end is null then
    return false;
  end if;

  -- Convert _at to user's local timezone (wall-clock)
  _local_now  := _at at time zone _timezone;
  _local_time := _local_now::time;
  _local_date := _local_now::date;

  -- Build start/end timestamps anchored to local date, handling overnight windows
  if _start > _end then
    -- Overnight (e.g. 23:00 -> 07:00)
    if _local_time < _end then
      _start_ts := (_local_date - 1 + _start) at time zone _timezone;
      _end_ts   := (_local_date     + _end  ) at time zone _timezone;
    else
      _start_ts := (_local_date     + _start) at time zone _timezone;
      _end_ts   := (_local_date + 1 + _end  ) at time zone _timezone;
    end if;
  else
    -- Same-day (e.g. 14:00 -> 16:00 nap)
    if _local_time < _start then
      _start_ts := (_local_date - 1 + _start) at time zone _timezone;
      _end_ts   := (_local_date - 1 + _end  ) at time zone _timezone;
    else
      _start_ts := (_local_date + _start) at time zone _timezone;
      _end_ts   := (_local_date + _end  ) at time zone _timezone;
    end if;
  end if;

  -- If currently inside the sleep window
  if _at >= _start_ts and _at < _end_ts then
    return true;
  end if;

  -- Check 2-hour post-wake grace period
  _wake_ts := (_local_date + _end) at time zone _timezone;
  if _wake_ts > _at then
    _wake_ts := _wake_ts - interval '1 day';
  end if;

  if _at >= _wake_ts and _at - _wake_ts < interval '2 hours' then
    return true;
  end if;

  return false;
end; $$;


ALTER FUNCTION "private"."sleep_relaxed"("_user" "uuid", "_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."trigger_push_dispatch"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  perform net.http_post(
    url := 'https://byekgmqyqlftgoveqnku.supabase.co/functions/v1/push-dispatch',
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := '{}'::jsonb
  );
exception when others then
  -- Fail silently to avoid blocking parent transaction
  null;
end;
$$;


ALTER FUNCTION "private"."trigger_push_dispatch"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."trigger_update_routine_profile"("_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  _secret text;
  _payload jsonb;
begin
  select value into _secret from private.app_config where key = 'cron_secret';
  _payload := jsonb_build_object('user_id', _user_id);
  perform net.http_post(
    url := 'https://byekgmqyqlftgoveqnku.supabase.co/functions/v1/update-routine-profile',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || _secret
    ),
    body := _payload
  );
exception when others then
  -- Fail silently to avoid blocking transaction
  null;
end;
$$;


ALTER FUNCTION "private"."trigger_update_routine_profile"("_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "private"."watches_user"("_watcher" "uuid", "_target" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select exists (
    select 1
    from public.group_members t
    join public.group_members w on w.group_id = t.group_id
    where t.user_id = _target and t.monitored and t.status = 'active'
      and w.user_id = _watcher and w.watching and w.status = 'active'
      and _watcher <> _target
  );
$$;


ALTER FUNCTION "private"."watches_user"("_watcher" "uuid", "_target" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ack_alert"("_alert_id" "uuid", "_minutes" integer DEFAULT 30) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare _uid uuid := auth.uid(); _target uuid; _aname text; _tname text;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if not private.can_see_alert(_alert_id, _uid) then raise exception 'forbidden'; end if;

  update public.alerts
    set paused_until = now() + make_interval(mins => _minutes), paused_by = _uid, updated_at = now()
    where id = _alert_id and status = 'open' returning user_id into _target;
  if _target is null then raise exception 'alert not open'; end if;

  insert into public.alert_events (alert_id, actor_id, kind) values (_alert_id, _uid, 'on_it');

  select coalesce(display_name, '') into _aname from public.profiles where id = _uid;
  select coalesce(display_name, '') into _tname from public.profiles where id = _target;
  insert into public.notifications (recipient_id, alert_id, kind, body, params)
  select distinct s.r, _alert_id, 'on_it', _aname || ' 正在跟进 ' || _tname || ' 的情况。',
    jsonb_build_object('actor', _aname, 'target', _tname)
  from (
    select _target as r
    union
    select w.user_id from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _target and t.monitored and t.status = 'active'
        and w.watching and w.status = 'active' and w.user_id <> _uid
  ) s;
end;
$$;


ALTER FUNCTION "public"."ack_alert"("_alert_id" "uuid", "_minutes" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."am_i_gm"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select private.is_admin(auth.uid())
$$;


ALTER FUNCTION "public"."am_i_gm"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."become_guardian_by_code"("_code" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  _uid uuid := auth.uid();
  _ward uuid;
begin
  if _uid is null then
    raise exception 'not authenticated';
  end if;
  select id into _ward from public.profiles where guardian_code = _code;
  if not found then
    raise exception 'invalid guardian code';
  end if;
  if _ward = _uid then
    raise exception 'cannot guard yourself';
  end if;
  insert into public.guardianships (guardian_id, ward_id, status)
  values (_uid, _ward, 'active')
  on conflict (guardian_id, ward_id) do update set status = 'active';
  return _ward;
end;
$$;


ALTER FUNCTION "public"."become_guardian_by_code"("_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."claim_unpushed_notifications"("p_batch_size" integer, "p_lease_duration" interval) RETURNS TABLE("id" "uuid", "recipient_id" "uuid", "kind" "text", "body" "text", "params" "jsonb", "alert_id" "uuid", "delivery_attempts" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
BEGIN
  RETURN QUERY
  WITH target_rows AS (
    SELECT n.id
    FROM public.notifications n
    WHERE n.pushed_at IS NULL
      AND n.created_at > (now() - interval '24 hours')
      AND (n.delivery_lease_expiry IS NULL OR n.delivery_lease_expiry < now())
      AND n.delivery_attempts < 5
    ORDER BY n.created_at ASC
    LIMIT p_batch_size
    FOR UPDATE SKIP LOCKED
  )
  UPDATE public.notifications n
  SET 
    delivery_lease_expiry = now() + p_lease_duration,
    delivery_attempts = n.delivery_attempts + 1
  FROM target_rows t
  WHERE n.id = t.id
  RETURNING 
    n.id,
    n.recipient_id,
    n.kind,
    n.body,
    n.params,
    n.alert_id,
    n.delivery_attempts;
END;
$$;


ALTER FUNCTION "public"."claim_unpushed_notifications"("p_batch_size" integer, "p_lease_duration" interval) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."clear_finished_notifications"() RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  delete from public.notifications n
  where n.recipient_id = auth.uid()
    and (
      n.alert_id is null
      or not exists (
        select 1 from public.alerts a
        where a.id = n.alert_id and a.status = 'open'
      )
    );
$$;


ALTER FUNCTION "public"."clear_finished_notifications"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_checkin_task"("_ward" "uuid", "_kind" "text", "_due_time_utc" time without time zone DEFAULT NULL::time without time zone, "_due_time_local" time without time zone DEFAULT NULL::time without time zone, "_interval_hours" integer DEFAULT NULL::integer, "_first_due" timestamp with time zone DEFAULT NULL::timestamp with time zone, "_grace" integer DEFAULT 30, "_label" "text" DEFAULT ''::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  _uid uuid := auth.uid();
  _id uuid;
  _self boolean;
  _name text;
  _timezone text;
  _local_date date;
  _next_due timestamptz;
BEGIN
  if _uid is null then raise exception 'not authenticated'; end if;
  _self := (_uid = _ward);
  if not _self and not private.is_guardian_of(_ward, _uid) then
    raise exception 'only the person or their guardian can create tasks';
  end if;

  _timezone := null;
  select timezone into _timezone from public.user_settings where user_id = _ward;
  _timezone := coalesce(_timezone, 'UTC');
  _local_date := (now() at time zone _timezone)::date;

  if _kind = 'daily' then
    -- TRANSITION SHIM: Pre-wall-clock clients never send _due_time_local.
    -- Derive it from _due_time_utc.
    if _due_time_local is null and _due_time_utc is not null then
      _due_time_local := (((_local_date + _due_time_utc) at time zone 'UTC') at time zone _timezone)::time;
    elsif _due_time_local is not null then
      _due_time_utc := (((_local_date + _due_time_local) at time zone _timezone) at time zone 'UTC')::time;
    end if;

    if _self then
      _next_due := (_local_date + _due_time_local) at time zone _timezone;
      if _next_due <= now() then
        _next_due := (_local_date + 1 + _due_time_local) at time zone _timezone;
      end if;
    end if;
  else
    if _self then
      _next_due := coalesce(_first_due, now() + make_interval(hours => _interval_hours));
    end if;
  end if;

  insert into public.checkin_tasks
    (ward_id, created_by, kind, due_time_utc, due_time_local, interval_hours, grace_minutes, label,
     status, next_due_at)
  values
    (_ward, _uid, _kind, _due_time_utc, _due_time_local, _interval_hours,
     coalesce(_grace, 30), coalesce(_label, ''),
     case when _self then 'active' else 'pending' end,
     _next_due)
  returning id into _id;

  if not _self then
    select coalesce(display_name, '') into _name from public.profiles where id = _uid;
    insert into public.notifications (recipient_id, kind, body, params)
    values (_ward, 'task_invite',
      _name || ' 为你设置了报平安任务，请确认是否接受。',
      jsonb_build_object('name', _name, 'label', coalesce(_label, '')));
  end if;
  return _id;
end;
$$;


ALTER FUNCTION "public"."create_checkin_task"("_ward" "uuid", "_kind" "text", "_due_time_utc" time without time zone, "_due_time_local" time without time zone, "_interval_hours" integer, "_first_due" timestamp with time zone, "_grace" integer, "_label" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."finalize_notification_delivery"("p_notification_id" "uuid", "p_outcome" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  v_attempts integer;
BEGIN
  IF p_outcome NOT IN ('sent', 'no_target', 'retry', 'native_missed') THEN
    RAISE EXCEPTION 'Invalid outcome: %', p_outcome;
  END IF;

  SELECT n.delivery_attempts INTO v_attempts
  FROM public.notifications n
  WHERE n.id = p_notification_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Notification not found: %', p_notification_id;
  END IF;

  IF p_outcome = 'sent' THEN
    UPDATE public.notifications
    SET
      pushed_at = now(),
      delivery_outcome = 'sent',
      delivery_lease_expiry = NULL
    WHERE id = p_notification_id;
  ELSIF p_outcome = 'no_target' THEN
    UPDATE public.notifications
    SET
      pushed_at = now(),
      delivery_outcome = 'no_target',
      delivery_lease_expiry = NULL
    WHERE id = p_notification_id;
  ELSIF p_outcome = 'native_missed' THEN
    UPDATE public.notifications
    SET
      pushed_at = now(),
      delivery_outcome = 'native_missed',
      delivery_lease_expiry = NULL
    WHERE id = p_notification_id;
  ELSIF p_outcome = 'retry' THEN
    IF v_attempts >= 5 THEN
      UPDATE public.notifications
      SET
        pushed_at = now(),
        delivery_outcome = 'failed',
        delivery_lease_expiry = NULL
      WHERE id = p_notification_id;
    ELSE
      UPDATE public.notifications
      SET
        delivery_lease_expiry = NULL
      WHERE id = p_notification_id;
    END IF;
  END IF;
END;
$$;


ALTER FUNCTION "public"."finalize_notification_delivery"("p_notification_id" "uuid", "p_outcome" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_app_config"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from private.app_config;
$$;


ALTER FUNCTION "public"."get_app_config"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_group_activity"("_group" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  _uid uuid := auth.uid();
  _visibility text;
  _is_owner boolean;
  _i_watching boolean;
  _i_share boolean;
  _members jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT g.activity_visibility,
         EXISTS (
           SELECT 1 FROM public.group_members gm
           WHERE gm.group_id = g.id AND gm.user_id = _uid
             AND gm.role = 'admin' AND gm.status = 'active'
         ),
         coalesce(me.watching, false)
    INTO _visibility, _is_owner, _i_watching
  FROM public.groups g
  JOIN public.group_members me
    ON me.group_id = g.id AND me.user_id = _uid AND me.status = 'active'
  WHERE g.id = _group;
  IF NOT FOUND THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT coalesce(us.share_activity, true) INTO _i_share
  FROM public.user_settings us WHERE us.user_id = _uid;
  _i_share := coalesce(_i_share, true);

  SELECT jsonb_agg(
    jsonb_build_object(
      'user_id', m.user_id,
      'name', coalesce(nullif(p.display_name, ''), left(m.user_id::text, 8)),
      'is_me', m.user_id = _uid,
      'status',
        CASE
          WHEN m.user_id = _uid THEN 'self'
          WHEN NOT coalesce(us.share_activity, true) AND NOT coalesce(al.alerted, false) THEN 'hidden'
          WHEN _visibility = 'watchers_only' AND NOT _i_watching AND NOT coalesce(al.alerted, false) THEN 'hidden'
          WHEN coalesce(al.alerted, false) THEN 'alert'
          WHEN bp.last_at IS NULL THEN 'unknown'
          WHEN bp.last_at > now() - interval '6 hours' THEN 'active'
          WHEN bp.last_at > now() - interval '24 hours' THEN 'quiet'
          ELSE 'silent'
        END,
      'hours',
        CASE
          WHEN bp.last_at IS NULL THEN null
          ELSE floor(extract(epoch from (now() - bp.last_at)) / 3600)::int
        END,
      'last_behavior_at', bp.last_at,
      'last_heartbeat_at', ds.last_heartbeat_at,
      'threshold_hours', round(extract(epoch from private.silence_threshold(m.user_id)) / 3600.0, 2),
      'alerted', coalesce(al.alerted, false)
    )
    ORDER BY (m.user_id = _uid) DESC, p.display_name NULLS LAST, m.user_id
  ) INTO _members
  FROM public.group_members m
  LEFT JOIN public.profiles p ON p.id = m.user_id
  LEFT JOIN public.user_settings us ON us.user_id = m.user_id
  LEFT JOIN public.device_state ds ON ds.user_id = m.user_id
  LEFT JOIN LATERAL (
    SELECT max(received_at) AS last_at
    FROM public.behavior_pings
    WHERE user_id = m.user_id
      AND ingest_version = 2
      AND abs(extract(epoch from (received_at - at))) <= 300
  ) bp ON true
  LEFT JOIN LATERAL (
    SELECT m.monitored AND EXISTS (
      SELECT 1 FROM public.alerts a
      WHERE a.user_id = m.user_id AND a.status = 'open'
        AND a.stage IN ('group', 'community', 'terminal')
    ) AS alerted
  ) al ON true
  WHERE m.group_id = _group AND m.status = 'active';

  RETURN jsonb_build_object(
    'visibility', _visibility,
    'is_owner', _is_owner,
    'i_share', _i_share,
    'members', coalesce(_members, '[]'::jsonb)
  );
END;
$$;


ALTER FUNCTION "public"."get_group_activity"("_group" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_group_activity_view"("_group" "uuid", "_view" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  _uid uuid := auth.uid();
  _mode text := coalesce(nullif(btrim(_view), ''), 'group');
  _is_owner boolean;
  _i_watching boolean;
  _i_share boolean;
  _members jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF _mode NOT IN ('watch', 'group') THEN RAISE EXCEPTION 'invalid activity view'; END IF;

  SELECT EXISTS (
           SELECT 1 FROM public.group_members gm
           WHERE gm.group_id = g.id and gm.user_id = _uid
             AND gm.role = 'admin' and gm.status = 'active'
         ),
         coalesce(me.watching, false)
    INTO _is_owner, _i_watching
  FROM public.groups g
  JOIN public.group_members me
    ON me.group_id = g.id and me.user_id = _uid and me.status = 'active'
  WHERE g.id = _group;
  IF NOT FOUND THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT coalesce(us.share_activity, true) INTO _i_share
  FROM public.user_settings us WHERE us.user_id = _uid;
  _i_share := coalesce(_i_share, true);

  SELECT coalesce(jsonb_agg(
    jsonb_build_object(
      'user_id', m.user_id,
      'name', coalesce(nullif(p.display_name, ''), left(m.user_id::text, 8)),
      'is_me', m.user_id = _uid,
      'status',
        CASE
          WHEN m.user_id = _uid THEN 'self'
          WHEN not coalesce(us.share_activity, true) and not coalesce(al.alerted, false) THEN 'hidden'
          WHEN coalesce(al.alerted, false) THEN 'alert'
          WHEN bp.last_at IS NULL THEN 'unknown'
          WHEN bp.last_at > now() - interval '6 hours' THEN 'active'
          WHEN bp.last_at > now() - interval '24 hours' THEN 'quiet'
          ELSE 'silent'
        END,
      'hours',
        CASE
          WHEN bp.last_at IS NULL THEN null
          ELSE floor(extract(epoch from (now() - bp.last_at)) / 3600)::int
        END,
      'last_behavior_at', bp.last_at,
      'last_heartbeat_at', ds.last_heartbeat_at,
      'threshold_hours', round(extract(epoch from private.silence_threshold(m.user_id)) / 3600.0, 2),
      'alerted', coalesce(al.alerted, false)
    )
    ORDER BY (m.user_id = _uid) DESC, p.display_name NULLS LAST, m.user_id
  ), '[]'::jsonb) INTO _members
  FROM public.group_members m
  LEFT JOIN public.profiles p ON p.id = m.user_id
  LEFT JOIN public.user_settings us ON us.user_id = m.user_id
  LEFT JOIN public.device_state ds ON ds.user_id = m.user_id
  LEFT JOIN LATERAL (
    SELECT max(received_at) as last_at
    FROM public.behavior_pings
    WHERE user_id = m.user_id
      AND ingest_version = 2
      AND abs(extract(epoch from (received_at - at))) <= 300
  ) bp ON true
  LEFT JOIN LATERAL (
    SELECT m.monitored AND exists (
      SELECT 1 FROM public.alerts a
      WHERE a.user_id = m.user_id and a.status = 'open'
        AND a.stage in ('group', 'community', 'terminal')
    ) as alerted
  ) al ON true
  WHERE m.group_id = _group
    AND m.status = 'active'
    AND (
      _mode = 'group'
      OR m.user_id = _uid
      OR (_i_watching and m.monitored)
    );

  RETURN jsonb_build_object(
    'visibility', CASE WHEN _mode = 'watch' THEN 'watchers_only' ELSE 'group_wide' END,
    'view', _mode,
    'is_owner', _is_owner,
    'i_share', _i_share,
    'members', _members
  );
END;
$$;


ALTER FUNCTION "public"."get_group_activity_view"("_group" "uuid", "_view" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."gm_delete_user"("_target" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not private.is_admin(auth.uid()) then raise exception 'forbidden'; end if;

  -- Delete all associated rows to prevent foreign key constraint violations
  delete from public.clients where user_id = _target;
  delete from public.notifications where recipient_id = _target or actor_id = _target;
  delete from public.alert_signals where user_id = _target;
  delete from public.alerts where user_id = _target or paused_by = _target;
  delete from public.guardians where user_id = _target or guardian_id = _target;
  delete from public.group_members where user_id = _target;
  delete from public.checkin_tasks where user_id = _target or created_by = _target;

  -- Finally delete user profile
  delete from public.profiles where id = _target;
end;
$$;


ALTER FUNCTION "public"."gm_delete_user"("_target" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."gm_list_clients"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
        'alerted', exists (
          SELECT 1 FROM public.alerts a
          WHERE a.user_id = p.id and a.status = 'open'
            AND a.stage in ('group','community','terminal')
        ),
        'status',
          CASE
            WHEN exists (
              SELECT 1 FROM public.alerts a
              WHERE a.user_id = p.id and a.status = 'open'
                AND a.stage in ('group','community','terminal')
            ) THEN 'alert'
            WHEN bp.last_at IS NULL THEN 'never'
            WHEN bp.last_at > now() - interval '6 hours' THEN 'active'
            WHEN bp.last_at > now() - interval '24 hours' THEN 'quiet'
            ELSE 'silent'
          END,
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
      LEFT JOIN public.gm_mutes mu ON mu.user_id = p.id
    ) s
  ), '[]'::jsonb);
END;
$$;


ALTER FUNCTION "public"."gm_list_clients"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."gm_mute_user"("_target" "uuid", "_until" timestamp with time zone DEFAULT NULL::timestamp with time zone, "_reason" "text" DEFAULT ''::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
BEGIN
  IF NOT private.is_admin(auth.uid()) THEN RAISE EXCEPTION 'forbidden'; END IF;
  INSERT INTO public.gm_mutes (user_id, muted_by, muted_at, muted_until, reason)
  VALUES (_target, auth.uid(), now(), _until, _reason)
  ON CONFLICT (user_id) DO UPDATE
    SET muted_by = auth.uid(), muted_at = now(), muted_until = _until, reason = _reason;
END;
$$;


ALTER FUNCTION "public"."gm_mute_user"("_target" "uuid", "_until" timestamp with time zone, "_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."gm_nudge_update"("_target" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not private.is_admin(auth.uid()) then raise exception 'forbidden'; end if;
  insert into public.notifications (recipient_id, kind, body, params)
  values (_target, 'update', '请更新到最新版本的 Keep Contact。', '{}'::jsonb);
end;
$$;


ALTER FUNCTION "public"."gm_nudge_update"("_target" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."gm_send_concern"("_target" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare _uid uuid := auth.uid(); _name text; _aid uuid;
begin
  if not private.is_admin(_uid) then raise exception 'forbidden'; end if;
  select coalesce(display_name, '') into _name from public.profiles where id = _uid;

  select id into _aid from public.alerts where user_id = _target and status = 'open' limit 1;
  if _aid is null then
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline, requires_explicit_unlock)
    values (_target, 'concern', 'self', now(), now() + interval '30 minutes', true)
    returning id into _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note)
    values (_aid, _uid, 'raised', 'gm_concern');
  else
    update public.alerts set requires_explicit_unlock = true, updated_at = now()
    where id = _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note)
    values (_aid, _uid, 'raised', 'gm_concern_on_open_alert');
  end if;

  insert into public.notifications (recipient_id, alert_id, kind, body, params)
  values (
    _target,
    _aid,
    'concern',
    coalesce(nullif(_name, ''), '管理员') || ' 在关心你，请打开 App 完成解锁报平安。',
    jsonb_build_object('name', _name)
  );
  perform private.trigger_push_dispatch();
end;
$$;


ALTER FUNCTION "public"."gm_send_concern"("_target" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."gm_unmute_user"("_target" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
BEGIN
  IF NOT private.is_admin(auth.uid()) THEN RAISE EXCEPTION 'forbidden'; END IF;
  DELETE FROM public.gm_mutes WHERE user_id = _target;
END;
$$;


ALTER FUNCTION "public"."gm_unmute_user"("_target" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_community"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  insert into public.community_members (community_id, user_id, role, status)
  values (new.id, new.created_by, 'admin', 'active')
  on conflict do nothing;
  return new;
end;
$$;


ALTER FUNCTION "public"."handle_new_community"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_group"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  insert into public.group_members (group_id, user_id, role, status)
  values (new.id, new.created_by, 'admin', 'active')
  on conflict do nothing;
  return new;
end;
$$;


ALTER FUNCTION "public"."handle_new_group"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, nullif(btrim(coalesce(
    new.raw_user_meta_data ->> 'display_name',
    new.raw_user_meta_data ->> 'name',
    new.raw_user_meta_data ->> 'full_name'
  )), ''))
  on conflict (id) do nothing;
  insert into public.heartbeat_tokens (user_id) values (new.id) on conflict (user_id) do nothing;
  insert into public.user_settings (user_id) values (new.id) on conflict (user_id) do nothing;
  return new;
end;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."initialize_user_routine_data"("_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
BEGIN
  -- Non-destructive no-op
  RETURN;
END;
$$;


ALTER FUNCTION "public"."initialize_user_routine_data"("_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."join_community_by_code"("_code" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  _uid uuid := auth.uid();
  _c public.communities;
begin
  if _uid is null then
    raise exception 'not authenticated';
  end if;
  select * into _c from public.communities where invite_code = _code;
  if not found then
    raise exception 'invalid invite code';
  end if;
  insert into public.community_members (community_id, user_id, status)
  values (_c.id, _uid, 'active')
  on conflict (community_id, user_id) do nothing;
  return _c.id;
end;
$$;


ALTER FUNCTION "public"."join_community_by_code"("_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."join_group_by_code"("_code" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  _uid uuid := auth.uid();
  _g public.groups;
begin
  if _uid is null then
    raise exception 'not authenticated';
  end if;
  select * into _g from public.groups where invite_code = _code;
  if not found then
    raise exception 'invalid invite code';
  end if;
  insert into public.group_members (group_id, user_id, status)
  values (_g.id, _uid, 'active')
  on conflict (group_id, user_id) do nothing;
  if _g.community_id is not null then
    insert into public.community_members (community_id, user_id, status)
    values (_g.community_id, _uid, 'active')
    on conflict (community_id, user_id) do nothing;
  end if;
  return _g.id;
end;
$$;


ALTER FUNCTION "public"."join_group_by_code"("_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."my_routine_status"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  _uid uuid := auth.uid();
  _threshold interval;
  _last_at timestamptz;
  _s text;
  _sleep_start time;
  _sleep_end time;
  _timezone text;
  _in_sleep_window boolean;
  _model_confidence double precision;
  _model_explanation text;
  _model_version text;
  _version_id uuid;
  _learning_active boolean := false;
  _min_support_dates integer;
  _sample_count integer;
  _support_days integer;
  _quality_state text;
  _confidence double precision;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT sensitivity, sleep_start_local, sleep_end_local, timezone
    INTO _s, _sleep_start, _sleep_end, _timezone
    FROM public.user_settings
   WHERE user_id = _uid;

  SELECT model_confidence, model_explanation, model_version
    INTO _model_confidence, _model_explanation, _model_version
    FROM public.user_activity_profiles
   WHERE user_id = _uid;

  _threshold := private.silence_threshold(_uid);
  _in_sleep_window := private.is_in_sleep_window(_uid, now());

  SELECT max(received_at)
    INTO _last_at
    FROM public.behavior_pings
   WHERE user_id = _uid
     AND ingest_version = 2
     AND abs(extract(epoch from (received_at - at))) <= 300;

  SELECT c.version_id
    INTO _version_id
    FROM private.adaptive_alert_shadow_runtime_config AS c
   WHERE c.singleton
     AND c.enabled
     AND c.version_id IS NOT NULL;

  IF _version_id IS NOT NULL THEN
    SELECT (v.config #>> '{personal,min_support_dates}')::integer
      INTO _min_support_dates
      FROM public.alert_model_versions AS v
     WHERE v.id = _version_id
       AND v.status = 'shadow';

    _learning_active := _min_support_dates IS NOT NULL;

    SELECT gp.sample_count, gp.distinct_support_dates, gp.quality_state, gp.confidence
      INTO _sample_count, _support_days, _quality_state, _confidence
      FROM public.alert_gap_profiles AS gp
     WHERE gp.version_id = _version_id
       AND gp.user_id = _uid
       AND gp.context_key = 'personal_global'
     ORDER BY gp.through_date DESC
     LIMIT 1;
  END IF;

  RETURN jsonb_build_object(
    'threshold_seconds', extract(epoch from _threshold)::bigint,
    'last_behavior_at', _last_at,
    'sensitivity', coalesce(_s, 'balanced'),
    'sleep_start', _sleep_start,
    'sleep_end', _sleep_end,
    'timezone', coalesce(_timezone, 'UTC'),
    'in_sleep_window', coalesce(_in_sleep_window, false),
    'model_confidence', _model_confidence,
    'model_explanation', _model_explanation,
    'model_version', _model_version,
    'learning_active', _learning_active,
    'evidence_sample_count', _sample_count,
    'evidence_support_days', _support_days,
    'evidence_min_support_days', _min_support_dates,
    'evidence_quality_state', _quality_state,
    'evidence_confidence', _confidence
  );
END;
$$;


ALTER FUNCTION "public"."my_routine_status"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."process_checkin_tasks"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  t record;
  _done boolean;
  _wname text;
  _timezone text;
  _local_date date;
  _candidate timestamptz;
BEGIN
  -- 1) 到点：提醒承担者 (Claim rows using FOR UPDATE SKIP LOCKED to prevent concurrent cron double-firing)
  FOR t IN
    SELECT * FROM public.checkin_tasks ct
    WHERE status = 'active' AND cycle_state = 'idle'
      AND next_due_at IS NOT NULL AND next_due_at <= now()
      AND NOT private.sleep_relaxed(ct.ward_id, now())
    FOR UPDATE SKIP LOCKED
  LOOP
    INSERT INTO public.notifications (recipient_id, kind, body, params)
    VALUES (t.ward_id, 'task_due', '到点报平安啦，点开 App 完成确认。',
            jsonb_build_object('label', t.label));

    UPDATE public.checkin_tasks
    SET cycle_state = 'due_notified', updated_at = now()
    WHERE id = t.id;
  END LOOP;

  -- 2) 宽限到期：心跳判定完成与否；漏卡 → 通知设置者(自设则通知守护人/同组守望者)
  -- (Claim rows using FOR UPDATE SKIP LOCKED to prevent concurrent cron double-firing)
  FOR t IN
    SELECT * FROM public.checkin_tasks ct
    WHERE status = 'active' AND cycle_state = 'due_notified'
      AND next_due_at + make_interval(mins => ct.grace_minutes) <= now()
      AND NOT private.sleep_relaxed(ct.ward_id, now())
    FOR UPDATE SKIP LOCKED
  LOOP
    -- Judge completion by REAL activity in behavior_pings (exists a behavior_pings row for ward_id with received_at >= next_due_at), NOT device_state.
    -- Live safety requires ingest_version=2, abs(received_at-observed_at)<=5m, received_at >= relevant alert/task time, observed_at >= relevant alert/task time.
    SELECT EXISTS (
      SELECT 1 FROM public.behavior_pings bp
      WHERE bp.user_id = t.ward_id
        AND bp.ingest_version = 2
        AND abs(extract(epoch from (bp.received_at - bp.at))) <= 300 -- drift <= 5m
        AND bp.received_at >= t.next_due_at
        AND bp.at >= t.next_due_at
    ) INTO _done;

    IF NOT _done THEN
      SELECT coalesce(display_name, '') INTO _wname FROM public.profiles WHERE id = t.ward_id;

      INSERT INTO public.notifications (recipient_id, kind, body, params)
      SELECT DISTINCT r.uid, 'task_missed',
        _wname || ' 未完成定时报平安，请关注。',
        jsonb_build_object('name', _wname, 'label', t.label)
      FROM (
        SELECT t.created_by AS uid WHERE t.created_by <> t.ward_id
        UNION
        SELECT g.guardian_id FROM public.guardianships g
          WHERE t.created_by = t.ward_id AND g.ward_id = t.ward_id AND g.status = 'active'
        UNION
        SELECT w.user_id FROM public.group_members gm
          JOIN public.group_members w ON w.group_id = gm.group_id
          WHERE t.created_by = t.ward_id
            AND gm.user_id = t.ward_id AND gm.monitored AND gm.status = 'active'
            AND w.watching AND w.status = 'active' AND w.user_id <> t.ward_id
            AND NOT EXISTS (SELECT 1 FROM public.guardianships g2
                            WHERE g2.ward_id = t.ward_id AND g2.status = 'active')
      ) r;
    END IF;

    -- 滚动下一轮（漏卡也滚动，避免重复轰炸；daily 跳到未来最近一个周期）
    IF t.kind = 'daily' THEN
      _timezone := null;
      SELECT timezone INTO _timezone FROM public.user_settings WHERE user_id = t.ward_id;
      _timezone := coalesce(_timezone, 'UTC');
      _local_date := (now() at time zone _timezone)::date;
      _candidate := (_local_date + t.due_time_local) at time zone _timezone;
      WHILE _candidate <= now() OR _candidate <= t.next_due_at LOOP
        _local_date := _local_date + 1;
        _candidate := (_local_date + t.due_time_local) at time zone _timezone;
      END LOOP;
    ELSE
      _candidate := now() + make_interval(hours => t.interval_hours);
    END IF;

    UPDATE public.checkin_tasks SET
      cycle_state = 'idle',
      next_due_at = _candidate,
      updated_at = now()
      WHERE id = t.id;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."process_checkin_tasks"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."process_escalations"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  _self_grace CONSTANT interval := interval '30 minutes';
  _group_dur  CONSTANT interval := interval '1 hour';
  _comm_dur   CONSTANT interval := interval '2 hours';
  r record;
  _aid uuid;
  _new text;
  _triggered boolean := false;
BEGIN
  -- Sleep/post-wake grace withdraws a silence alert it was wrong to raise.
  -- Activity never closes an alert here; see the migration header.
  FOR r IN
    SELECT
      a.id,
      a.user_id
    FROM public.alerts AS a
    WHERE a.status = 'open'
      AND a.cause = 'silence'
      AND private.sleep_relaxed(a.user_id, now())
  LOOP
    UPDATE public.alerts
    SET status = 'resolved',
        resolved_at = now(),
        resolved_by = NULL,
        updated_at = now()
    WHERE id = r.id;

    INSERT INTO public.alert_events (alert_id, kind, note)
    VALUES (r.id, 'auto_resolved', 'sleep_grace');

    PERFORM private.notify_auto_resolved(r.id, r.user_id);
    _triggered := true;
  END LOOP;

  -- device_state.status is descriptive state, not an independent authority to
  -- bypass the canonical silence calculation or sleep grace.
  FOR r IN
    SELECT
      ds.user_id,
      (now() - ds.last_heartbeat_at) > interval '18 hours' AS is_dark
    FROM public.device_state AS ds
    WHERE (
      now() - ds.last_heartbeat_at > interval '18 hours'
      OR (
        NOT private.sleep_relaxed(ds.user_id, now())
        AND now() - (
          SELECT coalesce(max(received_at), to_timestamp(0))
          FROM public.behavior_pings
          WHERE user_id = ds.user_id
            AND ingest_version = 2
            AND abs(extract(epoch FROM (received_at - at))) <= 300
        ) > private.silence_threshold(ds.user_id)
      )
    )
      AND EXISTS (
        SELECT 1
        FROM public.group_members AS gm
        WHERE gm.user_id = ds.user_id
          AND gm.monitored
          AND gm.status = 'active'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.alerts AS a
        WHERE a.user_id = ds.user_id
          AND a.status = 'open'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.alerts AS recent
        WHERE recent.user_id = ds.user_id
          AND recent.status = 'resolved'
          AND recent.cause IN ('silence', 'dark_device')
          AND recent.resolved_by IS NOT NULL
          AND recent.resolved_by <> recent.user_id
          AND recent.resolved_at > now() - _self_grace
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.gm_mutes AS mute
        WHERE mute.user_id = ds.user_id
          AND (mute.muted_until IS NULL OR mute.muted_until > now())
      )
  LOOP
    INSERT INTO public.alerts (
      user_id, cause, stage, stage_entered_at, next_deadline
    )
    VALUES (
      r.user_id,
      CASE WHEN r.is_dark THEN 'dark_device' ELSE 'silence' END,
      'self',
      now(),
      now() + _self_grace
    )
    RETURNING id INTO _aid;

    INSERT INTO public.alert_events (alert_id, kind)
    VALUES (_aid, 'raised');

    PERFORM private.notify_stage(_aid, r.user_id, 'self');
    _triggered := true;
  END LOOP;

  FOR r IN
    SELECT *
    FROM public.alerts
    WHERE status = 'open'
      AND next_deadline IS NOT NULL
      AND next_deadline <= now()
      AND coalesce(paused_until, to_timestamp(0)) <= now()
  LOOP
    _new := CASE r.stage
      WHEN 'self' THEN 'group'
      WHEN 'group' THEN 'community'
      WHEN 'community' THEN 'terminal'
      ELSE 'terminal'
    END;

    UPDATE public.alerts
    SET stage = _new,
        stage_entered_at = now(),
        paused_until = NULL,
        paused_by = NULL,
        updated_at = now(),
        next_deadline = CASE _new
          WHEN 'group' THEN now() + _group_dur
          WHEN 'community' THEN now() + _comm_dur
          ELSE NULL
        END
    WHERE id = r.id;

    INSERT INTO public.alert_events (alert_id, kind, note)
    VALUES (r.id, 'escalated', _new);

    PERFORM private.notify_stage(r.id, r.user_id, _new);
    _triggered := true;
  END LOOP;

  IF _triggered THEN
    PERFORM private.trigger_push_dispatch();
  END IF;
END;
$$;


ALTER FUNCTION "public"."process_escalations"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prune_stale_clients"() RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  delete from public.clients where last_seen_at < now() - interval '30 days';
$$;


ALTER FUNCTION "public"."prune_stale_clients"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."raise_sos"() RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare _uid uuid := auth.uid(); _aid uuid;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  select id into _aid from public.alerts where user_id = _uid and status = 'open';
  if _aid is null then
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    values (_uid, 'sos', 'group', now(), now() + interval '1 hour')
    returning id into _aid;
    insert into public.alert_events (alert_id, actor_id, kind) values (_aid, _uid, 'raised');
  else
    update public.alerts set cause = 'sos', stage = 'group', stage_entered_at = now(),
      next_deadline = now() + interval '1 hour', paused_until = null, updated_at = now()
      where id = _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note) values (_aid, _uid, 'escalated', 'sos');
  end if;
  perform private.notify_stage(_aid, _uid, 'group');

  perform private.trigger_push_dispatch();
  return _aid;
end;
$$;


ALTER FUNCTION "public"."raise_sos"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."raise_sos"("_lat" double precision DEFAULT NULL::double precision, "_lng" double precision DEFAULT NULL::double precision) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare _uid uuid := auth.uid(); _aid uuid;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  select id into _aid from public.alerts where user_id = _uid and status = 'open';
  if _aid is null then
    insert into public.alerts
      (user_id, cause, stage, stage_entered_at, next_deadline, sos_lat, sos_lng)
    values
      (_uid, 'sos', 'group', now(), now() + interval '1 hour', _lat, _lng)
    returning id into _aid;
    insert into public.alert_events (alert_id, actor_id, kind) values (_aid, _uid, 'raised');
  else
    update public.alerts
      set cause = 'sos',
          stage = 'group',
          stage_entered_at = now(),
          next_deadline = now() + interval '1 hour',
          paused_until = null,
          sos_lat = coalesce(_lat, sos_lat),
          sos_lng = coalesce(_lng, sos_lng),
          updated_at = now()
      where id = _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note)
    values (_aid, _uid, 'escalated', 'sos');
  end if;
  perform private.notify_stage(_aid, _uid, 'group');
  return _aid;
end;
$$;


ALTER FUNCTION "public"."raise_sos"("_lat" double precision, "_lng" double precision) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."raise_test_alert"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare _uid uuid := auth.uid(); _aid uuid;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  -- 已有 open 告警就复用（避免重复造），否则建一个不升级的测试告警
  select id into _aid from public.alerts where user_id = _uid and status = 'open' limit 1;
  if _aid is null then
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline)
    values (_uid, 'silence', 'self', now(), null)
    returning id into _aid;
    insert into public.alert_events (alert_id, kind) values (_aid, 'raised');
  end if;
  insert into public.notifications (recipient_id, kind, body, params, alert_id)
  values (_uid, 'self', '（测试）检测到异常沉默，点开 App 完成解锁报平安。', '{}'::jsonb, _aid);
end; $$;


ALTER FUNCTION "public"."raise_test_alert"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_alert_shadow_coverage_lease"("_client_id" "text", "_channel" "text", "_collector_contract" "text", "_collector_state" "text", "_capability_sha256" "text", "_observed_at" timestamp with time zone, "_event_id" "uuid") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    AS $$
BEGIN
  RETURN private.record_alert_shadow_coverage_lease_core(
    auth.uid(),
    _client_id,
    _channel,
    _collector_contract,
    _collector_state,
    _capability_sha256,
    _observed_at,
    _event_id
  );
END;
$$;


ALTER FUNCTION "public"."record_alert_shadow_coverage_lease"("_client_id" "text", "_channel" "text", "_collector_contract" "text", "_collector_state" "text", "_capability_sha256" "text", "_observed_at" timestamp with time zone, "_event_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_alert_shadow_coverage_lease_for_user"("_user_id" "uuid", "_client_id" "text", "_channel" "text", "_collector_contract" "text", "_collector_state" "text", "_capability_sha256" "text", "_observed_at" timestamp with time zone, "_event_id" "uuid") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "TimeZone" TO 'UTC'
    AS $$
BEGIN
  RETURN private.record_alert_shadow_coverage_lease_core(
    _user_id,
    _client_id,
    _channel,
    _collector_contract,
    _collector_state,
    _capability_sha256,
    _observed_at,
    _event_id
  );
END;
$$;


ALTER FUNCTION "public"."record_alert_shadow_coverage_lease_for_user"("_user_id" "uuid", "_client_id" "text", "_channel" "text", "_collector_contract" "text", "_collector_state" "text", "_capability_sha256" "text", "_observed_at" timestamp with time zone, "_event_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_behavior_ping"("event_id" "uuid", "observed_at" timestamp with time zone, "source" "text", "kind" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  _uid uuid := auth.uid();
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING errcode = '42501';
  END IF;
  RETURN private.insert_behavior_ping(_uid, event_id, observed_at, source, kind);
END;
$$;


ALTER FUNCTION "public"."record_behavior_ping"("event_id" "uuid", "observed_at" timestamp with time zone, "source" "text", "kind" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_behavior_ping_for_user"("_user_id" "uuid", "_event_id" "uuid", "_observed_at" timestamp with time zone, "_source" "text", "_kind" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
BEGIN
  RETURN private.insert_behavior_ping(_user_id, _event_id, _observed_at, _source, _kind);
END;
$$;


ALTER FUNCTION "public"."record_behavior_ping_for_user"("_user_id" "uuid", "_event_id" "uuid", "_observed_at" timestamp with time zone, "_source" "text", "_kind" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_behavior_pings"("events" "jsonb") RETURNS TABLE("status" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  _uid uuid := auth.uid();
  _evt record;
  _event_id uuid;
  _observed_at timestamptz;
  _source text;
  _kind text;
  _res text;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING errcode = '42501';
  END IF;

  IF events IS NULL OR jsonb_typeof(events) <> 'array' THEN
    RAISE EXCEPTION 'invalid batch format' USING errcode = '22023';
  END IF;

  IF jsonb_array_length(events) > 100 THEN
    RAISE EXCEPTION 'batch elements exceed maximum threshold of 100';
  END IF;

  -- auth.uid()-derived <=100 ordered batch query
  FOR _evt IN
    SELECT value, ordinality
    FROM jsonb_array_elements(events) WITH ORDINALITY
    ORDER BY ordinality
    LIMIT 100
  LOOP
    BEGIN
      _event_id := (_evt.value->>'event_id')::uuid;
      _observed_at := (_evt.value->>'observed_at')::timestamptz;
      _source := _evt.value->>'source';
      _kind := _evt.value->>'kind';

      IF _event_id IS NULL OR _observed_at IS NULL OR _source IS NULL OR _kind IS NULL THEN
        status := 'invalid';
        RETURN NEXT;
        CONTINUE;
      END IF;

      _res := private.insert_behavior_ping(_uid, _event_id, _observed_at, _source, _kind);
      status := _res;
      RETURN NEXT;
    EXCEPTION
      WHEN invalid_text_representation OR invalid_datetime_format OR datetime_field_overflow THEN
      status := 'invalid';
      RETURN NEXT;
    END;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."record_behavior_pings"("events" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_device_sample_for_user"("_user_id" "uuid", "_event_id" "uuid", "_payload" "jsonb") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  return private.insert_device_sample(_user_id, _event_id, _payload);
end;
$$;


ALTER FUNCTION "public"."record_device_sample_for_user"("_user_id" "uuid", "_event_id" "uuid", "_payload" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."register_fcm_token"("_token" "text", "_platform" "text" DEFAULT 'android'::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if _token is null or length(_token) < 10 then
    return;
  end if;
  insert into public.push_tokens (token, user_id, platform, updated_at)
  values (_token, auth.uid(), coalesce(_platform, 'android'), now())
  on conflict (token) do update
    set user_id = excluded.user_id, updated_at = now();
end;
$$;


ALTER FUNCTION "public"."register_fcm_token"("_token" "text", "_platform" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rename_community"("_community" "uuid", "_name" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  update public.communities c
    set name = nullif(btrim(_name), '')
    where c.id = _community and c.created_by = _uid
      and nullif(btrim(_name), '') is not null;
  if not found then raise exception 'forbidden'; end if;
end;
$$;


ALTER FUNCTION "public"."rename_community"("_community" "uuid", "_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rename_group"("_group" "uuid", "_name" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  update public.groups g
    set name = nullif(btrim(_name), '')
    where g.id = _group
      and exists (
        select 1 from public.group_members gm
        where gm.group_id = g.id and gm.user_id = _uid
          and gm.role = 'admin' and gm.status = 'active'
      )
      and nullif(btrim(_name), '') is not null;
  if not found then raise exception 'forbidden'; end if;
end;
$$;


ALTER FUNCTION "public"."rename_group"("_group" "uuid", "_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."report_client"("_client_id" "text", "_platform" "text", "_version" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if _client_id is null or length(_client_id) = 0 then return; end if;
  insert into public.clients (user_id, client_id, platform, app_version, first_seen_at, last_seen_at)
  values (_uid, left(_client_id, 64), left(_platform, 32), left(_version, 32), now(), now())
  on conflict (user_id, client_id) do update
    set platform = excluded.platform,
        app_version = excluded.app_version,
        last_seen_at = now();
end;
$$;


ALTER FUNCTION "public"."report_client"("_client_id" "text", "_platform" "text", "_version" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolve_alert"("_alert_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare _uid uuid := auth.uid(); _target uuid; _tname text;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if not private.can_see_alert(_alert_id, _uid) then raise exception 'forbidden'; end if;
  if not exists (select 1 from public.alerts where id = _alert_id and paused_by = _uid) then
    raise exception 'only the responder who reached out can confirm safe';
  end if;

  update public.alerts
    set status = 'resolved', resolved_at = now(), resolved_by = _uid, updated_at = now()
    where id = _alert_id and status = 'open' returning user_id into _target;
  if _target is null then raise exception 'alert not open'; end if;

  insert into public.alert_events (alert_id, actor_id, kind) values (_alert_id, _uid, 'confirmed_safe');

  insert into public.notifications (recipient_id, alert_id, kind, body)
  values (_target, _alert_id, 'self', '【系统提示】小组已确认你安全，但检测到设备仍未活动。请解锁或使用手机以恢复自动守护！');

  select coalesce(display_name, '') into _tname from public.profiles where id = _target;
  insert into public.notifications (recipient_id, alert_id, kind, body, params)
  select distinct s.r, _alert_id, 'resolved', _tname || ' 已确认安全，告警解除。',
    jsonb_build_object('target', _tname)
  from (
    select _target as r
    union
    select w.user_id from public.group_members t
      join public.group_members w on w.group_id = t.group_id
      where t.user_id = _target and t.monitored and t.status = 'active'
        and w.watching and w.status = 'active'
  ) s;

  perform private.trigger_push_dispatch();
end;
$$;


ALTER FUNCTION "public"."resolve_alert"("_alert_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolve_my_alert"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare _uid uuid := auth.uid(); _aid uuid;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  update public.alerts set status = 'resolved', resolved_at = now(), resolved_by = _uid, updated_at = now()
    where user_id = _uid and status = 'open' returning id into _aid;
  if _aid is not null then
    insert into public.alert_events (alert_id, actor_id, kind) values (_aid, _uid, 'resolved');
  end if;

  insert into public.behavior_pings (user_id, kind, at)
  values (_uid, 'manual_checkin', now());

  delete from public.notifications
    where recipient_id = _uid and kind in ('self', 'concern');

  perform private.trigger_push_dispatch();
end;
$$;


ALTER FUNCTION "public"."resolve_my_alert"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."respond_checkin_task"("_task" "uuid", "_accept" boolean, "_first_due" timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  _uid uuid := auth.uid();
  _t public.checkin_tasks;
  _name text;
  _timezone text;
  _local_date date;
  _next_due timestamptz;
BEGIN
  if _uid is null then raise exception 'not authenticated'; end if;
  select * into _t from public.checkin_tasks where id = _task and ward_id = _uid and status = 'pending';
  if not found then raise exception 'task not found or not pending'; end if;

  if _accept then
    if _t.kind = 'daily' then
      _timezone := null;
      select timezone into _timezone from public.user_settings where user_id = _uid;
      _timezone := coalesce(_timezone, 'UTC');
      _local_date := (now() at time zone _timezone)::date;
      _next_due := (_local_date + _t.due_time_local) at time zone _timezone;
      if _next_due <= now() then
        _next_due := (_local_date + 1 + _t.due_time_local) at time zone _timezone;
      end if;
    else
      _next_due := coalesce(_first_due, now() + make_interval(hours => _t.interval_hours));
    end if;
  end if;

  update public.checkin_tasks
    set status = case when _accept then 'active' else 'declined' end,
        next_due_at = _next_due,
        updated_at = now()
    where id = _task;

  select coalesce(display_name, '') into _name from public.profiles where id = _uid;
  insert into public.notifications (recipient_id, kind, body, params)
  values (_t.created_by,
    case when _accept then 'task_accepted' else 'task_declined' end,
    _name || case when _accept then ' 接受了报平安任务。' else ' 拒绝了报平安任务。' end,
    jsonb_build_object('name', _name, 'label', _t.label));
END;
$$;


ALTER FUNCTION "public"."respond_checkin_task"("_task" "uuid", "_accept" boolean, "_first_due" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."revoke_checkin_task"("_task" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  update public.checkin_tasks set status = 'revoked', updated_at = now()
    where id = _task and (ward_id = _uid or created_by = _uid) and status in ('pending', 'active');
  if not found then raise exception 'task not found'; end if;
end;
$$;


ALTER FUNCTION "public"."revoke_checkin_task"("_task" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."run_daily_aggregations"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  _user record;
  _timezone text;
  _yesterday date;
BEGIN
  FOR _user IN SELECT id FROM auth.users LOOP
    SELECT timezone INTO _timezone FROM public.user_settings WHERE user_id = _user.id;
    _timezone := coalesce(_timezone, 'UTC');

    _yesterday := (now() at time zone _timezone)::date - 1;

    PERFORM private.aggregate_user_daily_activity(_user.id, _yesterday);
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."run_daily_aggregations"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."send_concern"("_target" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare _uid uuid := auth.uid(); _name text; _aid uuid;
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if _uid = _target then raise exception 'bad target'; end if;
  if not private.shares_group_with(_target, _uid) and not private.is_guardian_of(_target, _uid) then
    raise exception 'forbidden';
  end if;
  select coalesce(display_name, '') into _name from public.profiles where id = _uid;

  select id into _aid from public.alerts where user_id = _target and status = 'open' limit 1;
  if _aid is null then
    insert into public.alerts (user_id, cause, stage, stage_entered_at, next_deadline, requires_explicit_unlock)
    values (_target, 'concern', 'self', now(), now() + interval '30 minutes', true)
    returning id into _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note)
    values (_aid, _uid, 'raised', 'concern');
  else
    update public.alerts set requires_explicit_unlock = true, updated_at = now()
    where id = _aid;
    insert into public.alert_events (alert_id, actor_id, kind, note)
    values (_aid, _uid, 'raised', 'concern_on_open_alert');
  end if;

  insert into public.notifications (recipient_id, alert_id, kind, body, params)
  values (
    _target,
    _aid,
    'concern',
    coalesce(nullif(_name, ''), '有人') || ' 在关心你，请打开 App 完成解锁报平安。',
    jsonb_build_object('name', _name)
  );
  perform private.trigger_push_dispatch();
end;
$$;


ALTER FUNCTION "public"."send_concern"("_target" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."send_heartbeat"("_status" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if _status not in ('normal', 'alert') then raise exception 'bad status'; end if;
  insert into public.device_state (user_id, status, last_heartbeat_at, updated_at)
  values (_uid, _status, now(), now())
  on conflict (user_id) do update
    set status = excluded.status, last_heartbeat_at = now(), updated_at = now();
end;
$$;


ALTER FUNCTION "public"."send_heartbeat"("_status" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."send_test_notification"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  insert into public.notifications (recipient_id, kind, body, params)
  values (auth.uid(), 'test', '这是一条测试通知，用来确认推送是否出声、醒目。', '{}'::jsonb);
end; $$;


ALTER FUNCTION "public"."send_test_notification"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_display_name"("_name" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  update public.profiles
    set display_name = nullif(btrim(_name), '')
    where id = _uid;
end;
$$;


ALTER FUNCTION "public"."set_display_name"("_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_group_community"("_group" "uuid", "_community" "uuid" DEFAULT NULL::"uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if _community is not null and not private.is_community_member(_community, _uid) then
    raise exception 'community not visible';
  end if;
  update public.groups g
    set community_id = _community
    where g.id = _group
      and exists (
        select 1 from public.group_members gm
        where gm.group_id = g.id and gm.user_id = _uid
          and gm.role = 'admin' and gm.status = 'active'
      );
  if not found then raise exception 'forbidden'; end if;
end;
$$;


ALTER FUNCTION "public"."set_group_community"("_group" "uuid", "_community" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_group_visibility"("_group" "uuid", "_visibility" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if _visibility not in ('watchers_only', 'group_wide') then
    raise exception 'bad visibility';
  end if;
  update public.groups g
    set activity_visibility = _visibility
    where g.id = _group
      and exists (
        select 1 from public.group_members gm
        where gm.group_id = g.id
          and gm.user_id = _uid
          and gm.role = 'admin'
          and gm.status = 'active'
      );
  if not found then raise exception 'forbidden'; end if;
end;
$$;


ALTER FUNCTION "public"."set_group_visibility"("_group" "uuid", "_visibility" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_monitoring_direction"("_group" "uuid", "_monitored" boolean DEFAULT NULL::boolean, "_watching" boolean DEFAULT NULL::boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if _monitored is null and _watching is null then
    raise exception 'nothing to update';
  end if;

  update public.group_members gm
     set monitored = coalesce(_monitored, gm.monitored),
         watching = coalesce(_watching, gm.watching)
   where gm.group_id = _group
     and gm.user_id = _uid
     and gm.status = 'active';

  if not found then raise exception 'group membership not found'; end if;
end;
$$;


ALTER FUNCTION "public"."set_monitoring_direction"("_group" "uuid", "_monitored" boolean, "_watching" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_sensitivity"("_s" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  if _s not in ('high', 'balanced', 'low') then raise exception 'bad sensitivity'; end if;
  insert into public.user_settings (user_id, sensitivity, updated_at)
  values (_uid, _s, now())
  on conflict (user_id) do update
    set sensitivity = excluded.sensitivity, updated_at = now();
end;
$$;


ALTER FUNCTION "public"."set_sensitivity"("_s" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_share_activity"("_share" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare _uid uuid := auth.uid();
begin
  if _uid is null then raise exception 'not authenticated'; end if;
  insert into public.user_settings (user_id, share_activity, updated_at)
  values (_uid, coalesce(_share, false), now())
  on conflict (user_id) do update
    set share_activity = excluded.share_activity, updated_at = now();
end;
$$;


ALTER FUNCTION "public"."set_share_activity"("_share" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_sleep_window"("_start" time without time zone DEFAULT NULL::time without time zone, "_end" time without time zone DEFAULT NULL::time without time zone, "_tz" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  _uid uuid := auth.uid();
  _existing_tz text;
begin
  if _uid is null then
    raise exception 'not authenticated';
  end if;

  -- TRANSITION SHIM: Pre-wall-clock clients never send _tz. If they set a window,
  -- they send UTC time-of-day digits. We convert these to local digits using their stored timezone.
  -- This shim should be removed in a future ADR once old clients age out.
  if _tz is null and _start is not null and _end is not null then
    select timezone into _existing_tz from public.user_settings where user_id = _uid;
    _start := (((current_date + _start) at time zone 'UTC') at time zone coalesce(_existing_tz, 'UTC'))::time;
    _end   := (((current_date + _end)   at time zone 'UTC') at time zone coalesce(_existing_tz, 'UTC'))::time;
  end if;

  insert into public.user_settings (user_id, sleep_start_local, sleep_end_local, timezone, updated_at)
  values (_uid, _start, _end, coalesce(_tz, 'UTC'), now())
  on conflict (user_id) do update
    set sleep_start_local = excluded.sleep_start_local,
        sleep_end_local = excluded.sleep_end_local,
        timezone = case when _tz is not null then excluded.timezone else user_settings.timezone end,
        updated_at = now();
end;
$$;


ALTER FUNCTION "public"."set_sleep_window"("_start" time without time zone, "_end" time without time zone, "_tz" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trigger_weekly_routine_updates"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  _secret text;
begin
  select value into _secret from private.app_config where key = 'cron_secret';
  perform net.http_post(
    url := 'https://byekgmqyqlftgoveqnku.supabase.co/functions/v1/update-routine-profile',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || _secret
    ),
    body := '{}'::jsonb
  );
exception when others then
  -- Fail silently to avoid blocking transaction
  null;
end;
$$;


ALTER FUNCTION "public"."trigger_weekly_routine_updates"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_checkin_task"("_task" "uuid", "_kind" "text", "_due_time_utc" time without time zone DEFAULT NULL::time without time zone, "_due_time_local" time without time zone DEFAULT NULL::time without time zone, "_interval_hours" integer DEFAULT NULL::integer, "_first_due" timestamp with time zone DEFAULT NULL::timestamp with time zone, "_grace" integer DEFAULT 30, "_label" "text" DEFAULT ''::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  _uid uuid := auth.uid();
  _ward uuid;
  _timezone text;
  _local_date date;
  _next_due timestamptz;
BEGIN
  if _uid is null then raise exception 'not authenticated'; end if;
  if _kind not in ('daily', 'interval') then raise exception 'bad kind'; end if;

  select ward_id into _ward from public.checkin_tasks
  where id = _task and created_by = _uid and status in ('pending', 'active', 'declined');
  if _ward is null then raise exception 'task not found'; end if;

  _timezone := null;
  select timezone into _timezone from public.user_settings where user_id = _ward;
  _timezone := coalesce(_timezone, 'UTC');
  _local_date := (now() at time zone _timezone)::date;

  if _kind = 'daily' then
    -- TRANSITION SHIM: Pre-wall-clock clients never send _due_time_local.
    -- Derive it from _due_time_utc.
    if _due_time_local is null and _due_time_utc is not null then
      _due_time_local := (((_local_date + _due_time_utc) at time zone 'UTC') at time zone _timezone)::time;
    elsif _due_time_local is not null then
      _due_time_utc := (((_local_date + _due_time_local) at time zone _timezone) at time zone 'UTC')::time;
    end if;

    _next_due := (_local_date + _due_time_local) at time zone _timezone;
    if _next_due <= now() then
      _next_due := (_local_date + 1 + _due_time_local) at time zone _timezone;
    end if;
  else
    _next_due := coalesce(_first_due, now() + make_interval(hours => _interval_hours));
  end if;

  update public.checkin_tasks t
  set kind = _kind,
      due_time_utc = case when _kind = 'daily' then _due_time_utc else null end,
      due_time_local = case when _kind = 'daily' then _due_time_local else null end,
      interval_hours = case when _kind = 'interval' then _interval_hours else null end,
      grace_minutes = coalesce(_grace, 30),
      label = coalesce(_label, ''),
      cycle_state = 'idle',
      next_due_at = _next_due,
      status = case when status = 'declined' then 'pending' else status end,
      updated_at = now()
  where t.id = _task and t.created_by = _uid and t.status in ('pending', 'active', 'declined');

  insert into public.notifications (recipient_id, kind, body, params)
  values (_ward, 'task_updated', '你的报平安任务已被修改，请留意新的时间安排。',
          jsonb_build_object('label', coalesce(_label, '')));
end;
$$;


ALTER FUNCTION "public"."update_checkin_task"("_task" "uuid", "_kind" "text", "_due_time_utc" time without time zone, "_due_time_local" time without time zone, "_interval_hours" integer, "_first_due" timestamp with time zone, "_grace" integer, "_label" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_sos_location"("_lat" double precision, "_lng" double precision) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  _uid uuid := auth.uid();
begin
  -- 1. Explicit auth validation
  if _uid is null then
    raise exception 'not authenticated';
  end if;

  -- 2. Explicit null/NaN/infinite/out-of-range validation
  if _lat is null or _lng is null or
     _lat = 'NaN'::double precision or _lng = 'NaN'::double precision or
     _lat = 'Infinity'::double precision or _lat = '-Infinity'::double precision or
     _lng = 'Infinity'::double precision or _lng = '-Infinity'::double precision or
     not (_lat between -90 and 90) or
     not (_lng between -180 and 180)
  then
    raise exception 'invalid coordinates';
  end if;

  -- 3. Update caller-owned open SOS only (and only coords+updated_at)
  update public.alerts
  set
    sos_lat = _lat,
    sos_lng = _lng,
    updated_at = now()
  where
    user_id = _uid
    and status = 'open'
    and cause = 'sos';

  -- Return FOUND (boolean indicating if a row was updated)
  return FOUND;
end;
$$;


ALTER FUNCTION "public"."update_sos_location"("_lat" double precision, "_lng" double precision) OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "private"."adaptive_alert_shadow_cohort_dirty" (
    "version_id" "uuid" NOT NULL,
    "routine_mode" "text" NOT NULL,
    "context_key" "text" NOT NULL,
    "invalidated_at" timestamp with time zone NOT NULL,
    "reason" "text" NOT NULL,
    CONSTRAINT "adaptive_alert_shadow_cohort_dirty_reason_check" CHECK (("reason" = ANY (ARRAY['settings_changed'::"text", 'profile_changed'::"text", 'consent_withdrawn'::"text", 'source_invalidation'::"text"]))),
    CONSTRAINT "adaptive_alert_shadow_cohort_dirty_routine_mode_check" CHECK (("routine_mode" = ANY (ARRAY['regular_9to5'::"text", 'semester_break'::"text", 'shift_irregular'::"text"])))
);


ALTER TABLE "private"."adaptive_alert_shadow_cohort_dirty" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."adaptive_alert_shadow_cycle_runs" (
    "version_id" "uuid" NOT NULL,
    "evaluated_minute" timestamp with time zone NOT NULL,
    "status" "text" NOT NULL,
    "duration_ms" integer NOT NULL,
    "population_count" integer NOT NULL,
    "evaluated_count" integer NOT NULL,
    "metrics" "jsonb" NOT NULL,
    "run_sha256" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "adaptive_alert_shadow_cycle_runs_duration_ms_check" CHECK (("duration_ms" >= 0)),
    CONSTRAINT "adaptive_alert_shadow_cycle_runs_evaluated_count_check" CHECK (("evaluated_count" >= 0)),
    CONSTRAINT "adaptive_alert_shadow_cycle_runs_metrics_check" CHECK (("jsonb_typeof"("metrics") = 'object'::"text")),
    CONSTRAINT "adaptive_alert_shadow_cycle_runs_population_count_check" CHECK (("population_count" >= 0)),
    CONSTRAINT "adaptive_alert_shadow_cycle_runs_run_sha256_check" CHECK (("run_sha256" ~ '^[a-f0-9]{64}$'::"text")),
    CONSTRAINT "adaptive_alert_shadow_cycle_runs_status_check" CHECK (("status" = ANY (ARRAY['completed'::"text", 'empty'::"text"])))
);


ALTER TABLE "private"."adaptive_alert_shadow_cycle_runs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."adaptive_alert_shadow_daily_reports" (
    "version_id" "uuid" NOT NULL,
    "report_date" "date" NOT NULL,
    "segment_key" "text" NOT NULL,
    "contributor_count" integer NOT NULL,
    "suppressed" boolean NOT NULL,
    "metrics" "jsonb" NOT NULL,
    "report_sha256" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "adaptive_alert_shadow_daily_reports_check" CHECK ((("contributor_count" < 10) = "suppressed")),
    CONSTRAINT "adaptive_alert_shadow_daily_reports_contributor_count_check" CHECK (("contributor_count" >= 0)),
    CONSTRAINT "adaptive_alert_shadow_daily_reports_metrics_check" CHECK (("jsonb_typeof"("metrics") = 'object'::"text")),
    CONSTRAINT "adaptive_alert_shadow_daily_reports_metrics_check1" CHECK ((NOT ("metrics" ?| ARRAY['user_id'::"text", 'client_id'::"text", 'event_id'::"text", 'alert_id'::"text", 'occurred_at'::"text", 'raw_error'::"text"]))),
    CONSTRAINT "adaptive_alert_shadow_daily_reports_report_sha256_check" CHECK (("report_sha256" ~ '^[a-f0-9]{64}$'::"text"))
);


ALTER TABLE "private"."adaptive_alert_shadow_daily_reports" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."adaptive_alert_shadow_intervention_cursor" (
    "version_id" "uuid" NOT NULL,
    "source_kind" "text" NOT NULL,
    "last_captured_at" timestamp with time zone NOT NULL,
    "last_source_id" "uuid",
    CONSTRAINT "adaptive_alert_shadow_intervention_cursor_source_kind_check" CHECK (("source_kind" = ANY (ARRAY['notification'::"text", 'checkin_task'::"text", 'guardianship'::"text"])))
);


ALTER TABLE "private"."adaptive_alert_shadow_intervention_cursor" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."adaptive_alert_shadow_profile_dirty" (
    "version_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "invalidated_at" timestamp with time zone NOT NULL,
    "reason" "text" NOT NULL,
    CONSTRAINT "adaptive_alert_shadow_profile_dirty_reason_check" CHECK (("reason" = ANY (ARRAY['settings_changed'::"text", 'profile_changed'::"text", 'consent_withdrawn'::"text"])))
);


ALTER TABLE "private"."adaptive_alert_shadow_profile_dirty" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."adaptive_alert_shadow_runtime_config" (
    "singleton" boolean DEFAULT true NOT NULL,
    "version_id" "uuid",
    "enabled" boolean DEFAULT false NOT NULL,
    "accept_coverage_leases" boolean DEFAULT false NOT NULL,
    "max_population" integer DEFAULT 10000 NOT NULL,
    "detail_retention_days" integer DEFAULT 35 NOT NULL,
    "cycle_timeout_seconds" integer DEFAULT 120 NOT NULL,
    "max_consecutive_failures" integer DEFAULT 3 NOT NULL,
    "consecutive_failures" integer DEFAULT 0 NOT NULL,
    "last_failure_code" "text",
    "updated_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "adaptive_alert_shadow_runtime_co_max_consecutive_failures_check" CHECK (("max_consecutive_failures" = 3)),
    CONSTRAINT "adaptive_alert_shadow_runtime_confi_cycle_timeout_seconds_check" CHECK (("cycle_timeout_seconds" = 120)),
    CONSTRAINT "adaptive_alert_shadow_runtime_confi_detail_retention_days_check" CHECK (("detail_retention_days" = 35)),
    CONSTRAINT "adaptive_alert_shadow_runtime_config_consecutive_failures_check" CHECK ((("consecutive_failures" >= 0) AND ("consecutive_failures" <= 3))),
    CONSTRAINT "adaptive_alert_shadow_runtime_config_max_population_check" CHECK ((("max_population" >= 1) AND ("max_population" <= 10000))),
    CONSTRAINT "adaptive_alert_shadow_runtime_config_singleton_check" CHECK ("singleton")
);


ALTER TABLE "private"."adaptive_alert_shadow_runtime_config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."adaptive_alert_shadow_subject_context_state" (
    "version_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "context_state" "text" NOT NULL,
    "unreplayable_reason" "text",
    "subject_context_sha256" "text" NOT NULL,
    "captured_at" timestamp with time zone NOT NULL,
    CONSTRAINT "adaptive_alert_shadow_subject_cont_subject_context_sha256_check" CHECK (("subject_context_sha256" ~ '^[a-f0-9]{64}$'::"text")),
    CONSTRAINT "adaptive_alert_shadow_subject_context_state_check" CHECK (((("context_state" = 'replayable'::"text") AND ("unreplayable_reason" IS NULL)) OR (("context_state" = 'unreplayable'::"text") AND ("unreplayable_reason" IS NOT NULL)))),
    CONSTRAINT "adaptive_alert_shadow_subject_context_state_context_state_check" CHECK (("context_state" = ANY (ARRAY['replayable'::"text", 'unreplayable'::"text"])))
);


ALTER TABLE "private"."adaptive_alert_shadow_subject_context_state" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."adaptive_alert_shadow_user_state" (
    "version_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "evaluated_at" timestamp with time zone NOT NULL,
    "replayable" boolean NOT NULL,
    "would_alert" boolean,
    "basis" "text",
    "candidate_threshold_minutes" integer,
    "quality_state" "text" NOT NULL,
    "unreplayable_reason" "text",
    "decision_sha256" "text" NOT NULL,
    "last_persisted_at" timestamp with time zone,
    "updated_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "adaptive_alert_shadow_user_state_check" CHECK (("replayable" OR ("would_alert" IS NULL))),
    CONSTRAINT "adaptive_alert_shadow_user_state_decision_sha256_check" CHECK (("decision_sha256" ~ '^[a-f0-9]{64}$'::"text"))
);


ALTER TABLE "private"."adaptive_alert_shadow_user_state" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."alert_shadow_coverage_leases" (
    "user_id" "uuid" NOT NULL,
    "event_id" "uuid" NOT NULL,
    "client_id" "text" NOT NULL,
    "channel" "text" NOT NULL,
    "collector_contract" "text" NOT NULL,
    "collector_state" "text" NOT NULL,
    "capability_sha256" "text" NOT NULL,
    "observed_at" timestamp with time zone NOT NULL,
    "received_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "app_version" "text" NOT NULL,
    "timezone" "text" NOT NULL,
    "utc_offset_minutes" integer NOT NULL,
    CONSTRAINT "alert_shadow_coverage_leases_app_version_check" CHECK ((("length"(TRIM(BOTH FROM "app_version")) >= 1) AND ("length"(TRIM(BOTH FROM "app_version")) <= 32))),
    CONSTRAINT "alert_shadow_coverage_leases_capability_sha256_check" CHECK (("capability_sha256" ~ '^[a-f0-9]{64}$'::"text")),
    CONSTRAINT "alert_shadow_coverage_leases_channel_check" CHECK (("channel" = ANY (ARRAY['tauri'::"text", 'android-apk'::"text"]))),
    CONSTRAINT "alert_shadow_coverage_leases_check" CHECK (((("channel" = 'tauri'::"text") AND ("collector_contract" = 'tauri-idle-v1'::"text")) OR (("channel" = 'android-apk'::"text") AND ("collector_contract" = 'android-passive-v1'::"text")))),
    CONSTRAINT "alert_shadow_coverage_leases_client_id_check" CHECK ((("length"(TRIM(BOTH FROM "client_id")) >= 1) AND ("length"(TRIM(BOTH FROM "client_id")) <= 64))),
    CONSTRAINT "alert_shadow_coverage_leases_collector_contract_check" CHECK (("collector_contract" = ANY (ARRAY['tauri-idle-v1'::"text", 'android-passive-v1'::"text"]))),
    CONSTRAINT "alert_shadow_coverage_leases_collector_state_check" CHECK (("collector_state" = 'operational'::"text")),
    CONSTRAINT "alert_shadow_coverage_leases_timezone_check" CHECK (("length"(TRIM(BOTH FROM "timezone")) > 0)),
    CONSTRAINT "alert_shadow_coverage_leases_utc_offset_minutes_check" CHECK ((("utc_offset_minutes" >= '-840'::integer) AND ("utc_offset_minutes" <= 840)))
);


ALTER TABLE "private"."alert_shadow_coverage_leases" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "private"."app_config" (
    "key" "text" NOT NULL,
    "value" "text" NOT NULL
);


ALTER TABLE "private"."app_config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."account_gap_profiles" (
    "user_id" "uuid" NOT NULL,
    "through_date" "date" NOT NULL,
    "lookback_days" integer NOT NULL,
    "shrinkage_k" integer NOT NULL,
    "percentile" numeric(4,3) NOT NULL,
    "computed_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "window_starts_at" timestamp with time zone NOT NULL,
    "window_ends_at" timestamp with time zone NOT NULL,
    "event_count" integer NOT NULL,
    "gap_count" integer NOT NULL,
    "distinct_event_days" integer NOT NULL,
    "first_event_at" timestamp with time zone,
    "last_event_at" timestamp with time zone,
    "sleep_window_applied" boolean NOT NULL,
    "sleep_minutes_removed" double precision DEFAULT 0 NOT NULL,
    "personal_p50_minutes" integer,
    "personal_pctl_minutes" integer,
    "personal_max_minutes" integer,
    "cohort_key" "text" NOT NULL,
    "cohort_pctl_minutes" integer NOT NULL,
    "cohort_contributor_count" integer NOT NULL,
    "cohort_source" "text" NOT NULL,
    "blend_weight" double precision NOT NULL,
    "blended_pctl_minutes" integer NOT NULL,
    "gaps_overlapping_open_alert" integer DEFAULT 0 NOT NULL,
    CONSTRAINT "account_gap_profiles_blend_weight_check" CHECK ((("blend_weight" >= (0)::double precision) AND ("blend_weight" <= (1)::double precision))),
    CONSTRAINT "account_gap_profiles_blended_pctl_minutes_check" CHECK (("blended_pctl_minutes" >= 0)),
    CONSTRAINT "account_gap_profiles_check" CHECK (("window_ends_at" > "window_starts_at")),
    CONSTRAINT "account_gap_profiles_check1" CHECK ((("gap_count" = 0) = ("personal_pctl_minutes" IS NULL))),
    CONSTRAINT "account_gap_profiles_cohort_contributor_count_check" CHECK (("cohort_contributor_count" >= 0)),
    CONSTRAINT "account_gap_profiles_cohort_pctl_minutes_check" CHECK (("cohort_pctl_minutes" >= 0)),
    CONSTRAINT "account_gap_profiles_cohort_source_check" CHECK (("cohort_source" = ANY (ARRAY['cohort'::"text", 'fallback'::"text"]))),
    CONSTRAINT "account_gap_profiles_distinct_event_days_check" CHECK (("distinct_event_days" >= 0)),
    CONSTRAINT "account_gap_profiles_event_count_check" CHECK (("event_count" >= 0)),
    CONSTRAINT "account_gap_profiles_gap_count_check" CHECK (("gap_count" >= 0)),
    CONSTRAINT "account_gap_profiles_gaps_overlapping_open_alert_check" CHECK (("gaps_overlapping_open_alert" >= 0)),
    CONSTRAINT "account_gap_profiles_lookback_days_check" CHECK (("lookback_days" > 0)),
    CONSTRAINT "account_gap_profiles_percentile_check" CHECK ((("percentile" > (0)::numeric) AND ("percentile" < (1)::numeric))),
    CONSTRAINT "account_gap_profiles_personal_max_minutes_check" CHECK (("personal_max_minutes" >= 0)),
    CONSTRAINT "account_gap_profiles_personal_p50_minutes_check" CHECK (("personal_p50_minutes" >= 0)),
    CONSTRAINT "account_gap_profiles_personal_pctl_minutes_check" CHECK (("personal_pctl_minutes" >= 0)),
    CONSTRAINT "account_gap_profiles_shrinkage_k_check" CHECK (("shrinkage_k" >= 0)),
    CONSTRAINT "account_gap_profiles_sleep_minutes_removed_check" CHECK (("sleep_minutes_removed" >= (0)::double precision))
);


ALTER TABLE "public"."account_gap_profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."account_normal_bounds" (
    "user_id" "uuid" NOT NULL,
    "through_date" "date" NOT NULL,
    "lookback_days" integer NOT NULL,
    "false_alarm_budget" numeric(5,2) NOT NULL,
    "computed_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "window_starts_at" timestamp with time zone NOT NULL,
    "window_ends_at" timestamp with time zone NOT NULL,
    "event_count" integer NOT NULL,
    "gap_count" integer NOT NULL,
    "evidence_days" integer NOT NULL,
    "first_event_at" timestamp with time zone,
    "last_event_at" timestamp with time zone,
    "sleep_window_applied" boolean NOT NULL,
    "order_index" integer NOT NULL,
    "normal_upper_bound_minutes" integer,
    "largest_gap_minutes" integer,
    "second_largest_gap_minutes" integer,
    "has_usable_signal" boolean NOT NULL,
    "sensitivity" "text" NOT NULL,
    "buffer_minutes" integer NOT NULL,
    "threshold_minutes" integer,
    "live_threshold_minutes" integer NOT NULL,
    "episodes_new" integer NOT NULL,
    "episodes_live" integer NOT NULL,
    CONSTRAINT "account_normal_bounds_buffer_minutes_check" CHECK (("buffer_minutes" >= 0)),
    CONSTRAINT "account_normal_bounds_check" CHECK (("window_ends_at" > "window_starts_at")),
    CONSTRAINT "account_normal_bounds_check1" CHECK (("has_usable_signal" = ("normal_upper_bound_minutes" IS NOT NULL))),
    CONSTRAINT "account_normal_bounds_check2" CHECK (("has_usable_signal" = ("threshold_minutes" IS NOT NULL))),
    CONSTRAINT "account_normal_bounds_episodes_live_check" CHECK (("episodes_live" >= 0)),
    CONSTRAINT "account_normal_bounds_episodes_new_check" CHECK (("episodes_new" >= 0)),
    CONSTRAINT "account_normal_bounds_event_count_check" CHECK (("event_count" >= 0)),
    CONSTRAINT "account_normal_bounds_evidence_days_check" CHECK (("evidence_days" >= 0)),
    CONSTRAINT "account_normal_bounds_false_alarm_budget_check" CHECK (("false_alarm_budget" >= (0)::numeric)),
    CONSTRAINT "account_normal_bounds_gap_count_check" CHECK (("gap_count" >= 0)),
    CONSTRAINT "account_normal_bounds_largest_gap_minutes_check" CHECK (("largest_gap_minutes" >= 0)),
    CONSTRAINT "account_normal_bounds_live_threshold_minutes_check" CHECK (("live_threshold_minutes" > 0)),
    CONSTRAINT "account_normal_bounds_lookback_days_check" CHECK (("lookback_days" > 0)),
    CONSTRAINT "account_normal_bounds_normal_upper_bound_minutes_check" CHECK (("normal_upper_bound_minutes" >= 0)),
    CONSTRAINT "account_normal_bounds_order_index_check" CHECK (("order_index" >= 1)),
    CONSTRAINT "account_normal_bounds_second_largest_gap_minutes_check" CHECK (("second_largest_gap_minutes" >= 0)),
    CONSTRAINT "account_normal_bounds_threshold_minutes_check" CHECK (("threshold_minutes" > 0))
);


ALTER TABLE "public"."account_normal_bounds" OWNER TO "postgres";


COMMENT ON TABLE "public"."account_normal_bounds" IS 'ADR-0037. Each account''s own observed upper bound of normal silence, learned continuously with no preset ceiling, floor, template anchor, or cohort shrinkage.';



CREATE TABLE IF NOT EXISTS "public"."account_threshold_shadow" (
    "user_id" "uuid" NOT NULL,
    "through_date" "date" NOT NULL,
    "lookback_days" integer NOT NULL,
    "shrinkage_k" integer NOT NULL,
    "percentile" numeric(4,3) NOT NULL,
    "computed_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "window_starts_at" timestamp with time zone NOT NULL,
    "window_ends_at" timestamp with time zone NOT NULL,
    "is_alertable" boolean NOT NULL,
    "sleep_window_applied" boolean NOT NULL,
    "sensitivity" "text" NOT NULL,
    "buffer_minutes" integer NOT NULL,
    "neutral_floor_minutes" integer NOT NULL,
    "neutral_minutes" integer NOT NULL,
    "live_threshold_minutes" integer NOT NULL,
    "candidate_floored_minutes" integer NOT NULL,
    "candidate_unfloored_minutes" integer NOT NULL,
    "gaps_evaluated" integer NOT NULL,
    "episodes_live" integer NOT NULL,
    "episodes_candidate_floored" integer NOT NULL,
    "episodes_candidate_unfloored" integer NOT NULL,
    "episodes_candidate_only" integer NOT NULL,
    "episodes_live_only" integer NOT NULL,
    "earliest_divergence_at" timestamp with time zone,
    "earliest_divergence_gap_minutes" integer,
    "longest_candidate_only_gap_minutes" integer,
    CONSTRAINT "account_threshold_shadow_alerts_candidate_floored_check" CHECK (("episodes_candidate_floored" >= 0)),
    CONSTRAINT "account_threshold_shadow_alerts_candidate_only_check" CHECK (("episodes_candidate_only" >= 0)),
    CONSTRAINT "account_threshold_shadow_alerts_candidate_unfloored_check" CHECK (("episodes_candidate_unfloored" >= 0)),
    CONSTRAINT "account_threshold_shadow_alerts_live_check" CHECK (("episodes_live" >= 0)),
    CONSTRAINT "account_threshold_shadow_alerts_live_only_check" CHECK (("episodes_live_only" >= 0)),
    CONSTRAINT "account_threshold_shadow_buffer_minutes_check" CHECK (("buffer_minutes" >= 0)),
    CONSTRAINT "account_threshold_shadow_candidate_floored_minutes_check" CHECK (("candidate_floored_minutes" > 0)),
    CONSTRAINT "account_threshold_shadow_candidate_unfloored_minutes_check" CHECK (("candidate_unfloored_minutes" > 0)),
    CONSTRAINT "account_threshold_shadow_check" CHECK (("window_ends_at" > "window_starts_at")),
    CONSTRAINT "account_threshold_shadow_check1" CHECK (("candidate_floored_minutes" >= "candidate_unfloored_minutes")),
    CONSTRAINT "account_threshold_shadow_check2" CHECK (("episodes_candidate_floored" <= "gaps_evaluated")),
    CONSTRAINT "account_threshold_shadow_check3" CHECK (("episodes_live" <= "gaps_evaluated")),
    CONSTRAINT "account_threshold_shadow_earliest_divergence_gap_minutes_check" CHECK (("earliest_divergence_gap_minutes" >= 0)),
    CONSTRAINT "account_threshold_shadow_gaps_evaluated_check" CHECK (("gaps_evaluated" >= 0)),
    CONSTRAINT "account_threshold_shadow_live_threshold_minutes_check" CHECK (("live_threshold_minutes" > 0)),
    CONSTRAINT "account_threshold_shadow_longest_candidate_only_gap_minut_check" CHECK (("longest_candidate_only_gap_minutes" >= 0)),
    CONSTRAINT "account_threshold_shadow_lookback_days_check" CHECK (("lookback_days" > 0)),
    CONSTRAINT "account_threshold_shadow_neutral_floor_minutes_check" CHECK (("neutral_floor_minutes" >= 0)),
    CONSTRAINT "account_threshold_shadow_neutral_minutes_check" CHECK (("neutral_minutes" >= 0)),
    CONSTRAINT "account_threshold_shadow_percentile_check" CHECK ((("percentile" > (0)::numeric) AND ("percentile" < (1)::numeric))),
    CONSTRAINT "account_threshold_shadow_shrinkage_k_check" CHECK (("shrinkage_k" >= 0))
);


ALTER TABLE "public"."account_threshold_shadow" OWNER TO "postgres";


COMMENT ON TABLE "public"."account_threshold_shadow" IS 'ADR-0035 step 2, record only. Episode counts compare the candidate threshold against the live one on identical gap history; they are not a reconstruction of the alerts table.';



CREATE TABLE IF NOT EXISTS "public"."alert_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "alert_id" "uuid" NOT NULL,
    "actor_id" "uuid",
    "kind" "text" NOT NULL,
    "note" "text",
    "at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "alert_events_kind_check" CHECK (("kind" = ANY (ARRAY['raised'::"text", 'escalated'::"text", 'on_it'::"text", 'confirmed_safe'::"text", 'resolved'::"text", 'auto_resolved'::"text"])))
);


ALTER TABLE "public"."alert_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."alert_gap_profiles" (
    "version_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "context_key" "text" NOT NULL,
    "through_date" "date" NOT NULL,
    "neutral_p95_minutes" integer NOT NULL,
    "sample_count" integer NOT NULL,
    "distinct_support_dates" integer NOT NULL,
    "support_started_on" "date" NOT NULL,
    "support_ended_on" "date" NOT NULL,
    "latest_evidence_at" timestamp with time zone NOT NULL,
    "quality_state" "text" NOT NULL,
    "confidence" double precision NOT NULL,
    "profile_sha256" "text" NOT NULL,
    "computed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "input_sha256" "text" DEFAULT "repeat"('0'::"text", 64) NOT NULL,
    "config_sha256" "text",
    "evidence_version" "text",
    CONSTRAINT "alert_gap_profiles_check" CHECK (("support_ended_on" >= "support_started_on")),
    CONSTRAINT "alert_gap_profiles_check1" CHECK (("through_date" >= "support_ended_on")),
    CONSTRAINT "alert_gap_profiles_confidence_check" CHECK ((("confidence" >= (0)::double precision) AND ("confidence" <= (1)::double precision))),
    CONSTRAINT "alert_gap_profiles_config_sha256_check" CHECK (("config_sha256" ~ '^[a-f0-9]{64}$'::"text")),
    CONSTRAINT "alert_gap_profiles_context_key_check" CHECK (("length"(TRIM(BOTH FROM "context_key")) > 0)),
    CONSTRAINT "alert_gap_profiles_distinct_support_dates_check" CHECK (("distinct_support_dates" > 0)),
    CONSTRAINT "alert_gap_profiles_evidence_version_check" CHECK ((("evidence_version" IS NULL) OR ("length"(TRIM(BOTH FROM "evidence_version")) > 0))),
    CONSTRAINT "alert_gap_profiles_input_sha256_check" CHECK (("input_sha256" ~ '^[a-f0-9]{64}$'::"text")),
    CONSTRAINT "alert_gap_profiles_neutral_p95_minutes_check" CHECK (("neutral_p95_minutes" > 0)),
    CONSTRAINT "alert_gap_profiles_profile_sha256_check" CHECK (("profile_sha256" ~ '^[a-f0-9]{64}$'::"text")),
    CONSTRAINT "alert_gap_profiles_quality_state_check" CHECK (("quality_state" = ANY (ARRAY['valid'::"text", 'low_support'::"text", 'stale'::"text", 'drift_invalid'::"text", 'coverage_invalid'::"text"]))),
    CONSTRAINT "alert_gap_profiles_sample_count_check" CHECK (("sample_count" > 0))
);


ALTER TABLE "public"."alert_gap_profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."alert_intervention_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "version_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "occurred_at" timestamp with time zone NOT NULL,
    "kind" "text" NOT NULL,
    "captured_at" timestamp with time zone NOT NULL,
    "evidence_version" "text" NOT NULL,
    "provenance_sha256" "text" NOT NULL,
    "source_kind" "text" DEFAULT 'legacy'::"text" NOT NULL,
    "source_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    CONSTRAINT "alert_intervention_events_check" CHECK (("captured_at" >= "occurred_at")),
    CONSTRAINT "alert_intervention_events_evidence_version_check" CHECK (("length"(TRIM(BOTH FROM "evidence_version")) > 0)),
    CONSTRAINT "alert_intervention_events_kind_check" CHECK (("kind" = ANY (ARRAY['self_alert'::"text", 'self_prompt'::"text", 'checkin_prompt'::"text", 'concern_prompt'::"text", 'guardian_confirmation'::"text"]))),
    CONSTRAINT "alert_intervention_events_provenance_sha256_check" CHECK (("provenance_sha256" ~ '^[a-f0-9]{64}$'::"text")),
    CONSTRAINT "alert_intervention_events_source_kind_check" CHECK (("source_kind" = ANY (ARRAY['legacy'::"text", 'notification'::"text", 'checkin_task'::"text", 'guardianship'::"text"])))
);


ALTER TABLE "public"."alert_intervention_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."alert_judgment_evaluations" (
    "version_id" "uuid" NOT NULL,
    "evaluation_kind" "text" NOT NULL,
    "evaluated_from" timestamp with time zone NOT NULL,
    "evaluated_to" timestamp with time zone NOT NULL,
    "metrics" "jsonb" NOT NULL,
    "input_sha256" "text" NOT NULL,
    "output_sha256" "text" NOT NULL,
    "evaluator_version" "text" NOT NULL,
    "promotion_eligible" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "alert_judgment_evaluations_check" CHECK (("evaluated_to" > "evaluated_from")),
    CONSTRAINT "alert_judgment_evaluations_evaluation_kind_check" CHECK (("evaluation_kind" = ANY (ARRAY['historical_replay'::"text", 'shadow_summary'::"text"]))),
    CONSTRAINT "alert_judgment_evaluations_evaluator_version_check" CHECK (("length"(TRIM(BOTH FROM "evaluator_version")) > 0)),
    CONSTRAINT "alert_judgment_evaluations_input_sha256_check" CHECK (("input_sha256" ~ '^[a-f0-9]{64}$'::"text")),
    CONSTRAINT "alert_judgment_evaluations_metrics_check" CHECK (("jsonb_typeof"("metrics") = 'object'::"text")),
    CONSTRAINT "alert_judgment_evaluations_output_sha256_check" CHECK (("output_sha256" ~ '^[a-f0-9]{64}$'::"text")),
    CONSTRAINT "alert_judgment_evaluations_promotion_eligible_check" CHECK (("promotion_eligible" = false))
);


ALTER TABLE "public"."alert_judgment_evaluations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."alert_judgment_shadow_decisions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "version_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "evaluated_at" timestamp with time zone NOT NULL,
    "evaluated_minute" timestamp with time zone GENERATED ALWAYS AS (("date_trunc"('minute'::"text", ("evaluated_at" AT TIME ZONE 'UTC'::"text")) AT TIME ZONE 'UTC'::"text")) STORED,
    "basis" "text" NOT NULL,
    "evaluator_version" "text" NOT NULL,
    "context_key" "text" NOT NULL,
    "neutral_threshold_minutes" integer NOT NULL,
    "sensitivity_buffer_minutes" integer NOT NULL,
    "candidate_threshold_minutes" integer NOT NULL,
    "effective_silence_minutes" double precision NOT NULL,
    "candidate_deadline" timestamp with time zone NOT NULL,
    "would_alert" boolean NOT NULL,
    "confidence" double precision NOT NULL,
    "quality_state" "text" NOT NULL,
    "fallback_path" "text"[] NOT NULL,
    "sleep_interval_provenance" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "provenance_sha256" "text" NOT NULL,
    "guardian_used_as_activity" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "evidence_cutoff" timestamp with time zone NOT NULL,
    "unclamped_candidate_threshold_minutes" integer NOT NULL,
    "candidate_floor_minutes" integer NOT NULL,
    "candidate_ceiling_minutes" integer NOT NULL,
    "candidate_cap_reason" "text" NOT NULL,
    "deadline_basis" "text" NOT NULL,
    "selected_source_sha256" "text",
    "subject_context_sha256" "text" NOT NULL,
    "decision_provenance" "jsonb" NOT NULL,
    "decision_sha256" "text" NOT NULL,
    CONSTRAINT "alert_judgment_shadow_decision_sensitivity_buffer_minutes_check" CHECK (("sensitivity_buffer_minutes" = ANY (ARRAY[0, 45, 90]))),
    CONSTRAINT "alert_judgment_shadow_decisions_basis_check" CHECK (("basis" = ANY (ARRAY['personal_context'::"text", 'personal_global'::"text", 'routine_cohort'::"text", 'deterministic_emergency'::"text"]))),
    CONSTRAINT "alert_judgment_shadow_decisions_candidate_cap_contract" CHECK (((("candidate_cap_reason" = 'none'::"text") AND ("basis" <> 'deterministic_emergency'::"text") AND ("candidate_threshold_minutes" = "unclamped_candidate_threshold_minutes") AND ("unclamped_candidate_threshold_minutes" >= "candidate_floor_minutes") AND ("unclamped_candidate_threshold_minutes" <= "candidate_ceiling_minutes")) OR (("candidate_cap_reason" = 'floor'::"text") AND ("basis" <> 'deterministic_emergency'::"text") AND ("unclamped_candidate_threshold_minutes" < "candidate_floor_minutes") AND ("candidate_threshold_minutes" = "candidate_floor_minutes")) OR (("candidate_cap_reason" = 'ceiling'::"text") AND ("basis" <> 'deterministic_emergency'::"text") AND ("unclamped_candidate_threshold_minutes" > "candidate_ceiling_minutes") AND ("candidate_threshold_minutes" = "candidate_ceiling_minutes")) OR (("candidate_cap_reason" = 'emergency_exempt'::"text") AND ("basis" = 'deterministic_emergency'::"text") AND ("candidate_threshold_minutes" = "unclamped_candidate_threshold_minutes")))),
    CONSTRAINT "alert_judgment_shadow_decisions_candidate_inputs_nonnegative" CHECK ((("unclamped_candidate_threshold_minutes" >= 0) AND ("candidate_floor_minutes" >= 0) AND ("candidate_ceiling_minutes" >= 0) AND ("candidate_ceiling_minutes" >= "candidate_floor_minutes"))),
    CONSTRAINT "alert_judgment_shadow_decisions_candidate_threshold_nonnegative" CHECK (("candidate_threshold_minutes" >= 0)),
    CONSTRAINT "alert_judgment_shadow_decisions_confidence_check" CHECK ((("confidence" >= (0)::double precision) AND ("confidence" <= (1)::double precision))),
    CONSTRAINT "alert_judgment_shadow_decisions_context_key_check" CHECK (("length"(TRIM(BOTH FROM "context_key")) > 0)),
    CONSTRAINT "alert_judgment_shadow_decisions_deadline_basis_check" CHECK (("deadline_basis" = ANY (ARRAY['known_interval_inversion'::"text", 'no_future_exclusion'::"text"]))),
    CONSTRAINT "alert_judgment_shadow_decisions_decision_provenance_check" CHECK ((("jsonb_typeof"("decision_provenance") = 'object'::"text") AND ("provenance_sha256" = "encode"("extensions"."digest"(("decision_provenance")::"text", 'sha256'::"text"), 'hex'::"text")))),
    CONSTRAINT "alert_judgment_shadow_decisions_decision_sha256_check" CHECK (("decision_sha256" ~ '^[a-f0-9]{64}$'::"text")),
    CONSTRAINT "alert_judgment_shadow_decisions_effective_silence_minutes_check" CHECK (("effective_silence_minutes" >= (0)::double precision)),
    CONSTRAINT "alert_judgment_shadow_decisions_evaluator_version_check" CHECK (("length"(TRIM(BOTH FROM "evaluator_version")) > 0)),
    CONSTRAINT "alert_judgment_shadow_decisions_fallback_path_check" CHECK (("cardinality"("fallback_path") >= 1)),
    CONSTRAINT "alert_judgment_shadow_decisions_guardian_used_as_activity_check" CHECK (("guardian_used_as_activity" = false)),
    CONSTRAINT "alert_judgment_shadow_decisions_neutral_threshold_minutes_check" CHECK (("neutral_threshold_minutes" >= 0)),
    CONSTRAINT "alert_judgment_shadow_decisions_provenance_sha256_check" CHECK (("provenance_sha256" ~ '^[a-f0-9]{64}$'::"text")),
    CONSTRAINT "alert_judgment_shadow_decisions_quality_state_check" CHECK (("quality_state" = ANY (ARRAY['valid'::"text", 'low_support'::"text", 'stale'::"text", 'drift_invalid'::"text", 'coverage_invalid'::"text"]))),
    CONSTRAINT "alert_judgment_shadow_decisions_selected_source_sha256_check" CHECK ((("selected_source_sha256" IS NULL) OR ("selected_source_sha256" ~ '^[a-f0-9]{64}$'::"text"))),
    CONSTRAINT "alert_judgment_shadow_decisions_sleep_interval_provenance_check" CHECK (("jsonb_typeof"("sleep_interval_provenance") = 'array'::"text")),
    CONSTRAINT "alert_judgment_shadow_decisions_subject_context_sha256_check" CHECK (("subject_context_sha256" ~ '^[a-f0-9]{64}$'::"text"))
);


ALTER TABLE "public"."alert_judgment_shadow_decisions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."alert_judgment_subject_contexts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "version_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "effective_from" timestamp with time zone NOT NULL,
    "effective_to" timestamp with time zone,
    "raw_sensitivity" "text",
    "canonical_sensitivity" "text" NOT NULL,
    "routine_mode" "text" NOT NULL,
    "timezone" "text" NOT NULL,
    "utc_offset_minutes" integer NOT NULL,
    "settings_updated_at" timestamp with time zone NOT NULL,
    "settings_provenance" "jsonb" NOT NULL,
    "captured_at" timestamp with time zone NOT NULL,
    "config_sha256" "text" NOT NULL,
    "evidence_version" "text" NOT NULL,
    "subject_context_sha256" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "alert_judgment_subject_contexts_canonical_sensitivity_check" CHECK (("canonical_sensitivity" = ANY (ARRAY['high'::"text", 'balanced'::"text", 'low'::"text"]))),
    CONSTRAINT "alert_judgment_subject_contexts_check" CHECK ((("effective_to" IS NULL) OR ("effective_to" > "effective_from"))),
    CONSTRAINT "alert_judgment_subject_contexts_check1" CHECK (("settings_updated_at" <= "captured_at")),
    CONSTRAINT "alert_judgment_subject_contexts_config_sha256_check" CHECK (("config_sha256" ~ '^[a-f0-9]{64}$'::"text")),
    CONSTRAINT "alert_judgment_subject_contexts_evidence_version_check" CHECK (("length"(TRIM(BOTH FROM "evidence_version")) > 0)),
    CONSTRAINT "alert_judgment_subject_contexts_routine_mode_check" CHECK (("routine_mode" = ANY (ARRAY['regular_9to5'::"text", 'semester_break'::"text", 'shift_irregular'::"text"]))),
    CONSTRAINT "alert_judgment_subject_contexts_settings_provenance_check" CHECK (("jsonb_typeof"("settings_provenance") = 'object'::"text")),
    CONSTRAINT "alert_judgment_subject_contexts_subject_context_sha256_check" CHECK (("subject_context_sha256" ~ '^[a-f0-9]{64}$'::"text")),
    CONSTRAINT "alert_judgment_subject_contexts_timezone_check" CHECK (("length"(TRIM(BOTH FROM "timezone")) > 0)),
    CONSTRAINT "alert_judgment_subject_contexts_utc_offset_minutes_check" CHECK ((("utc_offset_minutes" >= '-840'::integer) AND ("utc_offset_minutes" <= 840)))
);


ALTER TABLE "public"."alert_judgment_subject_contexts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."alert_model_versions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "status" "text" NOT NULL,
    "config" "jsonb" NOT NULL,
    "config_sha256" "text" NOT NULL,
    "evidence_version" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "shadow_enabled_at" timestamp with time zone,
    CONSTRAINT "alert_model_versions_check" CHECK ((("status" <> 'shadow'::"text") OR ("shadow_enabled_at" IS NOT NULL))),
    CONSTRAINT "alert_model_versions_config_check" CHECK ((("jsonb_typeof"("config") = 'object'::"text") AND ("config" ?& ARRAY['sessionization'::"text", 'context'::"text", 'personal'::"text", 'cohort'::"text", 'sensitivity_buffers_minutes'::"text", 'candidate_bounds'::"text", 'sleep_compensation'::"text"]) AND ("jsonb_typeof"(("config" -> 'sessionization'::"text")) = 'object'::"text") AND (("config" -> 'sessionization'::"text") ?& ARRAY['gap_minutes'::"text", 'per_user_day_gap_cap'::"text"]) AND ("jsonb_typeof"(("config" #> '{sessionization,gap_minutes}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{sessionization,gap_minutes}'::"text"[]))::numeric > (0)::numeric) AND ("jsonb_typeof"(("config" #> '{sessionization,per_user_day_gap_cap}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{sessionization,per_user_day_gap_cap}'::"text"[]))::numeric > (0)::numeric) AND ("jsonb_typeof"(("config" -> 'context'::"text")) = 'object'::"text") AND (("config" -> 'context'::"text") ?& ARRAY['definition_version'::"text"]) AND ("jsonb_typeof"(("config" #> '{context,definition_version}'::"text"[])) = 'string'::"text") AND ("length"(TRIM(BOTH FROM ("config" #>> '{context,definition_version}'::"text"[]))) > 0) AND ("jsonb_typeof"(("config" -> 'personal'::"text")) = 'object'::"text") AND (("config" -> 'personal'::"text") ?& ARRAY['min_samples'::"text", 'min_support_dates'::"text", 'min_span_days'::"text", 'max_age_days'::"text"]) AND ("jsonb_typeof"(("config" #> '{personal,min_samples}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{personal,min_samples}'::"text"[]))::numeric > (0)::numeric) AND ("jsonb_typeof"(("config" #> '{personal,min_support_dates}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{personal,min_support_dates}'::"text"[]))::numeric > (0)::numeric) AND ("jsonb_typeof"(("config" #> '{personal,min_span_days}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{personal,min_span_days}'::"text"[]))::numeric > (0)::numeric) AND ("jsonb_typeof"(("config" #> '{personal,max_age_days}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{personal,max_age_days}'::"text"[]))::numeric > (0)::numeric) AND ("jsonb_typeof"(("config" -> 'cohort'::"text")) = 'object'::"text") AND (("config" -> 'cohort'::"text") ?& ARRAY['min_contributors'::"text", 'min_support_dates'::"text", 'max_age_days'::"text", 'algorithm'::"text", 'trim_fraction'::"text"]) AND ("jsonb_typeof"(("config" #> '{cohort,min_contributors}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{cohort,min_contributors}'::"text"[]))::numeric > (0)::numeric) AND ("jsonb_typeof"(("config" #> '{cohort,min_support_dates}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{cohort,min_support_dates}'::"text"[]))::numeric > (0)::numeric) AND ("jsonb_typeof"(("config" #> '{cohort,max_age_days}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{cohort,max_age_days}'::"text"[]))::numeric > (0)::numeric) AND ("jsonb_typeof"(("config" #> '{cohort,algorithm}'::"text"[])) = 'string'::"text") AND (("config" #>> '{cohort,algorithm}'::"text"[]) = ANY (ARRAY['weighted_median'::"text", 'trimmed_mean'::"text"])) AND ("jsonb_typeof"(("config" #> '{cohort,trim_fraction}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{cohort,trim_fraction}'::"text"[]))::numeric >= (0)::numeric) AND ((("config" #>> '{cohort,trim_fraction}'::"text"[]))::numeric < 0.5) AND ("jsonb_typeof"(("config" -> 'sensitivity_buffers_minutes'::"text")) = 'object'::"text") AND (("config" -> 'sensitivity_buffers_minutes'::"text") ?& ARRAY['high'::"text", 'balanced'::"text", 'low'::"text"]) AND ("jsonb_typeof"(("config" #> '{sensitivity_buffers_minutes,high}'::"text"[])) = 'number'::"text") AND ("jsonb_typeof"(("config" #> '{sensitivity_buffers_minutes,balanced}'::"text"[])) = 'number'::"text") AND ("jsonb_typeof"(("config" #> '{sensitivity_buffers_minutes,low}'::"text"[])) = 'number'::"text") AND (("config" #>> '{sensitivity_buffers_minutes,high}'::"text"[]) = '0'::"text") AND (("config" #>> '{sensitivity_buffers_minutes,balanced}'::"text"[]) = '45'::"text") AND (("config" #>> '{sensitivity_buffers_minutes,low}'::"text"[]) = '90'::"text") AND ("jsonb_typeof"(("config" -> 'candidate_bounds'::"text")) = 'object'::"text") AND (("config" -> 'candidate_bounds'::"text") ?& ARRAY['floor_minutes'::"text", 'ceiling_minutes'::"text"]) AND ("jsonb_typeof"(("config" #> '{candidate_bounds,floor_minutes}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{candidate_bounds,floor_minutes}'::"text"[]))::numeric >= (0)::numeric) AND ("jsonb_typeof"(("config" #> '{candidate_bounds,ceiling_minutes}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{candidate_bounds,ceiling_minutes}'::"text"[]))::numeric >= (("config" #>> '{candidate_bounds,floor_minutes}'::"text"[]))::numeric) AND ("jsonb_typeof"(("config" -> 'sleep_compensation'::"text")) = 'object'::"text") AND (("config" -> 'sleep_compensation'::"text") ?& ARRAY['max_start_delay_minutes'::"text", 'max_wake_advance_minutes'::"text", 'max_wake_delay_minutes'::"text", 'max_update_minutes_per_day'::"text", 'min_positive_nights'::"text", 'timezone_tolerance_minutes'::"text"]) AND ("jsonb_typeof"(("config" #> '{sleep_compensation,max_start_delay_minutes}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{sleep_compensation,max_start_delay_minutes}'::"text"[]))::numeric >= (0)::numeric) AND ("jsonb_typeof"(("config" #> '{sleep_compensation,max_wake_advance_minutes}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{sleep_compensation,max_wake_advance_minutes}'::"text"[]))::numeric >= (0)::numeric) AND ("jsonb_typeof"(("config" #> '{sleep_compensation,max_wake_delay_minutes}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{sleep_compensation,max_wake_delay_minutes}'::"text"[]))::numeric >= (0)::numeric) AND ("jsonb_typeof"(("config" #> '{sleep_compensation,max_update_minutes_per_day}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{sleep_compensation,max_update_minutes_per_day}'::"text"[]))::numeric >= (0)::numeric) AND ("jsonb_typeof"(("config" #> '{sleep_compensation,min_positive_nights}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{sleep_compensation,min_positive_nights}'::"text"[]))::numeric > (0)::numeric) AND ("jsonb_typeof"(("config" #> '{sleep_compensation,timezone_tolerance_minutes}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{sleep_compensation,timezone_tolerance_minutes}'::"text"[]))::numeric >= (0)::numeric))),
    CONSTRAINT "alert_model_versions_config_sha256_check" CHECK (("config_sha256" ~ '^[a-f0-9]{64}$'::"text")),
    CONSTRAINT "alert_model_versions_evidence_version_check" CHECK (("length"(TRIM(BOTH FROM "evidence_version")) > 0)),
    CONSTRAINT "alert_model_versions_gap_profile_contract_check" CHECK (((("jsonb_typeof"(("config" #> '{sessionization,training_horizon_days}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{sessionization,training_horizon_days}'::"text"[]))::numeric > (0)::numeric) AND ((("config" #>> '{sessionization,training_horizon_days}'::"text"[]))::numeric = "trunc"((("config" #>> '{sessionization,training_horizon_days}'::"text"[]))::numeric)) AND ("jsonb_typeof"(("config" #> '{sessionization,intervention_window_minutes}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{sessionization,intervention_window_minutes}'::"text"[]))::numeric >= (0)::numeric) AND ((("config" #>> '{sessionization,intervention_window_minutes}'::"text"[]))::numeric = "trunc"((("config" #>> '{sessionization,intervention_window_minutes}'::"text"[]))::numeric)) AND ("jsonb_typeof"(("config" #> '{context,day_partition}'::"text"[])) = 'string'::"text") AND (("config" #>> '{context,day_partition}'::"text"[]) = ANY (ARRAY['all_days'::"text", 'weekday_weekend'::"text"])) AND ("jsonb_typeof"(("config" #> '{context,hour_bucket_minutes}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{context,hour_bucket_minutes}'::"text"[]))::numeric > (0)::numeric) AND ((("config" #>> '{context,hour_bucket_minutes}'::"text"[]))::numeric = "trunc"((("config" #>> '{context,hour_bucket_minutes}'::"text"[]))::numeric)) AND ("mod"(1440, (("config" #>> '{context,hour_bucket_minutes}'::"text"[]))::integer) = 0) AND ("jsonb_typeof"(("config" #> '{personal,confidence_formula_version}'::"text"[])) = 'string'::"text") AND (("config" #>> '{personal,confidence_formula_version}'::"text"[]) = 'support_ratio_v1'::"text")) IS TRUE)),
    CONSTRAINT "alert_model_versions_historical_v1_policy_check" CHECK ((((("config" #> '{sessionization,historical_v1_policy}'::"text"[]) IS NULL) OR (("jsonb_typeof"(("config" #> '{sessionization,historical_v1_policy}'::"text"[])) = 'string'::"text") AND (("config" #>> '{sessionization,historical_v1_policy}'::"text"[]) = ANY (ARRAY['disabled'::"text", 'sessionized_training_only_v1'::"text"])))) IS TRUE)),
    CONSTRAINT "alert_model_versions_name_check" CHECK ((("length"(TRIM(BOTH FROM "name")) >= 1) AND ("length"(TRIM(BOTH FROM "name")) <= 120))),
    CONSTRAINT "alert_model_versions_sleep_compensation_late_evidence_check" CHECK (((("jsonb_typeof"(("config" #> '{sleep_compensation,lookback_nights}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{sleep_compensation,lookback_nights}'::"text"[]))::numeric > (0)::numeric) AND ((("config" #>> '{sleep_compensation,lookback_nights}'::"text"[]))::numeric = "trunc"((("config" #>> '{sleep_compensation,lookback_nights}'::"text"[]))::numeric)) AND ("jsonb_typeof"(("config" #> '{sleep_compensation,min_late_events_per_night}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{sleep_compensation,min_late_events_per_night}'::"text"[]))::numeric > (0)::numeric) AND ((("config" #>> '{sleep_compensation,min_late_events_per_night}'::"text"[]))::numeric = "trunc"((("config" #>> '{sleep_compensation,min_late_events_per_night}'::"text"[]))::numeric)) AND ((("config" #>> '{sleep_compensation,min_positive_nights}'::"text"[]))::numeric <= (("config" #>> '{sleep_compensation,lookback_nights}'::"text"[]))::numeric)) IS TRUE)),
    CONSTRAINT "alert_model_versions_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'replay'::"text", 'shadow'::"text", 'retired'::"text"])))
);


ALTER TABLE "public"."alert_model_versions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."alert_observation_coverage_intervals" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "version_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "starts_at" timestamp with time zone NOT NULL,
    "ends_at" timestamp with time zone NOT NULL,
    "timezone" "text" NOT NULL,
    "utc_offset_minutes" integer NOT NULL,
    "activity_coverage_state" "text" NOT NULL,
    "intervention_coverage_state" "text" NOT NULL,
    "sleep_context_state" "text" NOT NULL,
    "captured_at" timestamp with time zone NOT NULL,
    "finalized_at" timestamp with time zone,
    "evidence_version" "text" NOT NULL,
    "provenance_sha256" "text" NOT NULL,
    CONSTRAINT "alert_observation_coverage_in_intervention_coverage_state_check" CHECK (("intervention_coverage_state" = ANY (ARRAY['valid'::"text", 'incomplete'::"text", 'unknown'::"text"]))),
    CONSTRAINT "alert_observation_coverage_interv_activity_coverage_state_check" CHECK (("activity_coverage_state" = ANY (ARRAY['valid'::"text", 'outage'::"text", 'unknown'::"text"]))),
    CONSTRAINT "alert_observation_coverage_intervals_check" CHECK (("ends_at" > "starts_at")),
    CONSTRAINT "alert_observation_coverage_intervals_check1" CHECK (("captured_at" <= "ends_at")),
    CONSTRAINT "alert_observation_coverage_intervals_check2" CHECK ((("finalized_at" IS NULL) OR ("finalized_at" >= "ends_at"))),
    CONSTRAINT "alert_observation_coverage_intervals_evidence_version_check" CHECK (("length"(TRIM(BOTH FROM "evidence_version")) > 0)),
    CONSTRAINT "alert_observation_coverage_intervals_provenance_sha256_check" CHECK (("provenance_sha256" ~ '^[a-f0-9]{64}$'::"text")),
    CONSTRAINT "alert_observation_coverage_intervals_sleep_context_state_check" CHECK (("sleep_context_state" = ANY (ARRAY['valid'::"text", 'incomplete'::"text", 'unknown'::"text"]))),
    CONSTRAINT "alert_observation_coverage_intervals_timezone_check" CHECK (("length"(TRIM(BOTH FROM "timezone")) > 0)),
    CONSTRAINT "alert_observation_coverage_intervals_utc_offset_minutes_check" CHECK ((("utc_offset_minutes" >= '-840'::integer) AND ("utc_offset_minutes" <= 840)))
);


ALTER TABLE "public"."alert_observation_coverage_intervals" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."alert_sleep_night_contexts" (
    "version_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "anchor_date" "date" NOT NULL,
    "timezone" "text" NOT NULL,
    "sleep_start_local" time without time zone NOT NULL,
    "sleep_end_local" time without time zone NOT NULL,
    "anchor_starts_at" timestamp with time zone NOT NULL,
    "anchor_ends_at" timestamp with time zone NOT NULL,
    "utc_offset_minutes" integer NOT NULL,
    "coverage_state" "text" NOT NULL,
    "captured_at" timestamp with time zone NOT NULL,
    "finalized_at" timestamp with time zone,
    "evidence_version" "text" NOT NULL,
    "provenance_sha256" "text" NOT NULL,
    CONSTRAINT "alert_sleep_night_contexts_check" CHECK (("sleep_start_local" <> "sleep_end_local")),
    CONSTRAINT "alert_sleep_night_contexts_check1" CHECK (("anchor_ends_at" > "anchor_starts_at")),
    CONSTRAINT "alert_sleep_night_contexts_check2" CHECK (("captured_at" <= "anchor_starts_at")),
    CONSTRAINT "alert_sleep_night_contexts_check3" CHECK ((("coverage_state" = 'unknown'::"text") OR (("finalized_at" IS NOT NULL) AND ("finalized_at" >= "anchor_ends_at")))),
    CONSTRAINT "alert_sleep_night_contexts_coverage_state_check" CHECK (("coverage_state" = ANY (ARRAY['valid'::"text", 'outage'::"text", 'unknown'::"text"]))),
    CONSTRAINT "alert_sleep_night_contexts_evidence_version_check" CHECK (("length"(TRIM(BOTH FROM "evidence_version")) > 0)),
    CONSTRAINT "alert_sleep_night_contexts_provenance_sha256_check" CHECK (("provenance_sha256" ~ '^[a-f0-9]{64}$'::"text")),
    CONSTRAINT "alert_sleep_night_contexts_timezone_check" CHECK (("length"(TRIM(BOTH FROM "timezone")) > 0)),
    CONSTRAINT "alert_sleep_night_contexts_utc_offset_minutes_check" CHECK ((("utc_offset_minutes" >= '-840'::integer) AND ("utc_offset_minutes" <= 840)))
);


ALTER TABLE "public"."alert_sleep_night_contexts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."alerts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "cause" "text" NOT NULL,
    "stage" "text" NOT NULL,
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "opened_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "stage_entered_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "next_deadline" timestamp with time zone,
    "paused_until" timestamp with time zone,
    "paused_by" "uuid",
    "resolved_at" timestamp with time zone,
    "resolved_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "sos_lat" double precision,
    "sos_lng" double precision,
    "requires_explicit_unlock" boolean DEFAULT false NOT NULL,
    CONSTRAINT "alerts_cause_check" CHECK (("cause" = ANY (ARRAY['silence'::"text", 'dark_device'::"text", 'sos'::"text", 'concern'::"text"]))),
    CONSTRAINT "alerts_stage_check" CHECK (("stage" = ANY (ARRAY['self'::"text", 'group'::"text", 'community'::"text", 'terminal'::"text"]))),
    CONSTRAINT "alerts_status_check" CHECK (("status" = ANY (ARRAY['open'::"text", 'resolved'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."alerts" OWNER TO "postgres";


COMMENT ON COLUMN "public"."alerts"."requires_explicit_unlock" IS 'Someone asked this subject to prove they are alright. Passive liveness may not clear it; only an explicit unlock may. Survives alert reuse, which a cause check cannot.';



CREATE TABLE IF NOT EXISTS "public"."app_admins" (
    "user_id" "uuid" NOT NULL
);


ALTER TABLE "public"."app_admins" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."app_versions" (
    "version" character varying(50) NOT NULL,
    "apk_url" "text",
    "exe_url" "text",
    "status" character varying(20) DEFAULT 'canary'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "public_rollout" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."app_versions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."behavior_pings" (
    "id" bigint NOT NULL,
    "user_id" "uuid" NOT NULL,
    "kind" "text" DEFAULT 'app'::"text" NOT NULL,
    "at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "source" "text",
    "received_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "ingest_version" smallint DEFAULT 1 NOT NULL,
    "event_id" "uuid",
    CONSTRAINT "behavior_pings_kind_check" CHECK (("kind" = ANY (ARRAY['app'::"text", 'interaction'::"text", 'steps'::"text", 'unlock'::"text", 'manual_checkin'::"text"]))),
    CONSTRAINT "behavior_pings_source_check" CHECK ((("source" IS NULL) OR ("source" = ANY (ARRAY['installed_pwa'::"text", 'tauri'::"text", 'capacitor'::"text", 'shortcut'::"text", 'manual'::"text", 'app'::"text"]))))
);


ALTER TABLE "public"."behavior_pings" OWNER TO "postgres";


ALTER TABLE "public"."behavior_pings" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."behavior_pings_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."checkin_tasks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "ward_id" "uuid" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "kind" "text" NOT NULL,
    "due_time_utc" time without time zone,
    "interval_hours" integer,
    "grace_minutes" integer DEFAULT 30 NOT NULL,
    "label" "text" DEFAULT ''::"text" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "cycle_state" "text" DEFAULT 'idle'::"text" NOT NULL,
    "next_due_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "due_time_local" time without time zone,
    CONSTRAINT "checkin_tasks_check" CHECK (((("kind" = 'daily'::"text") AND ("due_time_utc" IS NOT NULL)) OR (("kind" = 'interval'::"text") AND ("interval_hours" IS NOT NULL)))),
    CONSTRAINT "checkin_tasks_cycle_state_check" CHECK (("cycle_state" = ANY (ARRAY['idle'::"text", 'due_notified'::"text"]))),
    CONSTRAINT "checkin_tasks_grace_minutes_check" CHECK ((("grace_minutes" >= 10) AND ("grace_minutes" <= 240))),
    CONSTRAINT "checkin_tasks_interval_hours_check" CHECK ((("interval_hours" IS NULL) OR ("interval_hours" >= 2))),
    CONSTRAINT "checkin_tasks_kind_check" CHECK (("kind" = ANY (ARRAY['daily'::"text", 'interval'::"text"]))),
    CONSTRAINT "checkin_tasks_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'active'::"text", 'declined'::"text", 'revoked'::"text"])))
);


ALTER TABLE "public"."checkin_tasks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."clients" (
    "user_id" "uuid" NOT NULL,
    "client_id" "text" NOT NULL,
    "platform" "text",
    "app_version" "text",
    "first_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."clients" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."communities" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "invite_code" "text" DEFAULT "encode"("extensions"."gen_random_bytes"(6), 'hex'::"text") NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "communities_name_check" CHECK ((("char_length"("name") >= 1) AND ("char_length"("name") <= 80)))
);


ALTER TABLE "public"."communities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."community_members" (
    "community_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "text" DEFAULT 'member'::"text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "joined_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "community_members_role_check" CHECK (("role" = ANY (ARRAY['admin'::"text", 'member'::"text"]))),
    CONSTRAINT "community_members_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'active'::"text"])))
);


ALTER TABLE "public"."community_members" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."daily_activity_aggregates" (
    "id" bigint NOT NULL,
    "user_id" "uuid" NOT NULL,
    "date" "date" NOT NULL,
    "hourly_density" integer[] NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "daily_activity_aggregates_hourly_density_check" CHECK (("cardinality"("hourly_density") = 24))
);


ALTER TABLE "public"."daily_activity_aggregates" OWNER TO "postgres";


ALTER TABLE "public"."daily_activity_aggregates" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."daily_activity_aggregates_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."device_activity_samples" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "trigger" "text" NOT NULL,
    "observed_at" timestamp with time zone NOT NULL,
    "received_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "protected_data_available" boolean,
    "battery_level" real,
    "battery_state" "text",
    "low_power_mode" boolean,
    "system_uptime_seconds" double precision,
    "other_audio_playing" boolean,
    "motion_variance" double precision,
    "motion_sample_count" integer,
    "steps_since_last_sample" integer,
    "floors_since_last_sample" integer,
    "dominant_activity" "text",
    "activity_confidence" smallint,
    "volume_available_bytes" bigint,
    "client_id" "text",
    "app_version" "text",
    "collector_contract" "text" NOT NULL,
    "always_unlocked_suspect" boolean,
    CONSTRAINT "device_activity_samples_activity_confidence_check" CHECK ((("activity_confidence" IS NULL) OR (("activity_confidence" >= 0) AND ("activity_confidence" <= 2)))),
    CONSTRAINT "device_activity_samples_battery_level_check" CHECK ((("battery_level" IS NULL) OR (("battery_level" >= (0)::double precision) AND ("battery_level" <= (1)::double precision)))),
    CONSTRAINT "device_activity_samples_battery_state_check" CHECK ((("battery_state" IS NULL) OR ("battery_state" = ANY (ARRAY['unknown'::"text", 'unplugged'::"text", 'charging'::"text", 'full'::"text"])))),
    CONSTRAINT "device_activity_samples_dominant_activity_check" CHECK ((("dominant_activity" IS NULL) OR ("dominant_activity" = ANY (ARRAY['stationary'::"text", 'walking'::"text", 'running'::"text", 'cycling'::"text", 'automotive'::"text", 'unknown'::"text"])))),
    CONSTRAINT "device_activity_samples_trigger_check" CHECK (("trigger" = ANY (ARRAY['push-wake'::"text", 'health-wake'::"text", 'location-relaunch'::"text", 'foreground'::"text", 'unlock'::"text"])))
);


ALTER TABLE "public"."device_activity_samples" OWNER TO "postgres";


COMMENT ON TABLE "public"."device_activity_samples" IS 'Shadow-only multi-signal liveness sampling. Never feeds alert judgement. A null signal column means the device or build could not read it, not that the value was zero.';



CREATE TABLE IF NOT EXISTS "public"."device_state" (
    "user_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'normal'::"text" NOT NULL,
    "last_heartbeat_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "device_state_status_check" CHECK (("status" = ANY (ARRAY['normal'::"text", 'alert'::"text"])))
);


ALTER TABLE "public"."device_state" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."emergency_info" (
    "user_id" "uuid" NOT NULL,
    "home_address" "text",
    "medical_notes" "text",
    "emergency_contact_name" "text",
    "emergency_contact_phone" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "latitude" double precision,
    "longitude" double precision,
    "location_accuracy" double precision,
    "location_updated_at" timestamp with time zone
);


ALTER TABLE "public"."emergency_info" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."gm_mutes" (
    "user_id" "uuid" NOT NULL,
    "muted_by" "uuid" NOT NULL,
    "muted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "muted_until" timestamp with time zone,
    "reason" "text" DEFAULT ''::"text" NOT NULL
);


ALTER TABLE "public"."gm_mutes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."group_members" (
    "group_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "text" DEFAULT 'member'::"text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "monitored" boolean DEFAULT true NOT NULL,
    "watching" boolean DEFAULT true NOT NULL,
    "joined_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "group_members_role_check" CHECK (("role" = ANY (ARRAY['admin'::"text", 'member'::"text"]))),
    CONSTRAINT "group_members_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'active'::"text"])))
);


ALTER TABLE "public"."group_members" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."groups" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "community_id" "uuid",
    "name" "text" NOT NULL,
    "invite_code" "text" DEFAULT "encode"("extensions"."gen_random_bytes"(6), 'hex'::"text") NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "activity_visibility" "text" DEFAULT 'watchers_only'::"text" NOT NULL,
    CONSTRAINT "groups_activity_visibility_check" CHECK (("activity_visibility" = ANY (ARRAY['watchers_only'::"text", 'group_wide'::"text"]))),
    CONSTRAINT "groups_activity_visibility_chk" CHECK (("activity_visibility" = ANY (ARRAY['watchers_only'::"text", 'group_wide'::"text"]))),
    CONSTRAINT "groups_name_check" CHECK ((("char_length"("name") >= 1) AND ("char_length"("name") <= 80)))
);


ALTER TABLE "public"."groups" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."guardianships" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "guardian_id" "uuid" NOT NULL,
    "ward_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "guardianships_check" CHECK (("guardian_id" <> "ward_id")),
    CONSTRAINT "guardianships_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'active'::"text", 'revoked'::"text"])))
);


ALTER TABLE "public"."guardianships" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."heartbeat_tokens" (
    "user_id" "uuid" NOT NULL,
    "token" "text" DEFAULT "encode"("extensions"."gen_random_bytes"(16), 'hex'::"text") NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."heartbeat_tokens" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "recipient_id" "uuid" NOT NULL,
    "alert_id" "uuid",
    "kind" "text" NOT NULL,
    "body" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "read_at" timestamp with time zone,
    "params" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "pushed_at" timestamp with time zone,
    "delivery_attempts" integer DEFAULT 0 NOT NULL,
    "delivery_lease_expiry" timestamp with time zone,
    "delivery_outcome" "text",
    CONSTRAINT "notifications_delivery_outcome_check" CHECK (("delivery_outcome" = ANY (ARRAY['sent'::"text", 'no_target'::"text", 'failed'::"text", 'native_missed'::"text"])))
);


ALTER TABLE "public"."notifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "display_name" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "guardian_code" "text" DEFAULT "encode"("extensions"."gen_random_bytes"(6), 'hex'::"text") NOT NULL,
    "routine_pattern" "text" DEFAULT 'regular_9to5'::"text" NOT NULL,
    "consent_data_sharing" boolean DEFAULT false NOT NULL,
    CONSTRAINT "profiles_routine_pattern_canonical" CHECK (("routine_pattern" = ANY (ARRAY['regular_9to5'::"text", 'semester_break'::"text", 'shift_irregular'::"text"])))
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."push_subscriptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "endpoint" "text" NOT NULL,
    "p256dh" "text" NOT NULL,
    "auth" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."push_subscriptions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."push_tokens" (
    "token" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "platform" "text" DEFAULT 'android'::"text" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."push_tokens" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."routine_mode_cohort_generations" (
    "routine_mode" "text" NOT NULL,
    "generation" bigint DEFAULT 0 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "routine_mode_cohort_generations_generation_check" CHECK (("generation" >= 0)),
    CONSTRAINT "routine_mode_cohort_generations_routine_mode_check" CHECK (("routine_mode" = ANY (ARRAY['regular_9to5'::"text", 'semester_break'::"text", 'shift_irregular'::"text"])))
);


ALTER TABLE "public"."routine_mode_cohort_generations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."routine_mode_cohort_invalidations" (
    "routine_mode" "text" NOT NULL,
    "invalidated_at" timestamp with time zone NOT NULL,
    "generation" bigint DEFAULT 0 NOT NULL,
    CONSTRAINT "routine_mode_cohort_invalidations_generation_check" CHECK (("generation" >= 0)),
    CONSTRAINT "routine_mode_cohort_invalidations_routine_mode_check" CHECK (("routine_mode" = ANY (ARRAY['regular_9to5'::"text", 'semester_break'::"text", 'shift_irregular'::"text"])))
);


ALTER TABLE "public"."routine_mode_cohort_invalidations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."routine_mode_cohort_priors" (
    "version_id" "uuid" NOT NULL,
    "routine_mode" "text" NOT NULL,
    "context_key" "text" NOT NULL,
    "through_date" "date" NOT NULL,
    "contributor_count" integer NOT NULL,
    "distinct_support_dates" integer NOT NULL,
    "support_started_on" "date" NOT NULL,
    "support_ended_on" "date" NOT NULL,
    "latest_evidence_at" timestamp with time zone NOT NULL,
    "neutral_p95_minutes" integer NOT NULL,
    "quality_state" "text" NOT NULL,
    "confidence" double precision NOT NULL,
    "algorithm" "text" NOT NULL,
    "config_sha256" "text" NOT NULL,
    "evidence_version" "text" NOT NULL,
    "input_sha256" "text" NOT NULL,
    "prior_sha256" "text" NOT NULL,
    "published_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "source_generation" bigint DEFAULT 0 NOT NULL,
    "oldest_evidence_at" timestamp with time zone,
    "valid_until" timestamp with time zone,
    "conservative_span_days" integer,
    "minimum_profile_confidence" double precision,
    CONSTRAINT "routine_mode_cohort_priors_algorithm_check" CHECK (("algorithm" = ANY (ARRAY['weighted_median'::"text", 'trimmed_mean'::"text"]))),
    CONSTRAINT "routine_mode_cohort_priors_check" CHECK (("support_ended_on" >= "support_started_on")),
    CONSTRAINT "routine_mode_cohort_priors_check1" CHECK (("through_date" >= "support_ended_on")),
    CONSTRAINT "routine_mode_cohort_priors_confidence_check" CHECK ((("confidence" >= (0)::double precision) AND ("confidence" <= (1)::double precision))),
    CONSTRAINT "routine_mode_cohort_priors_config_sha256_check" CHECK (("config_sha256" ~ '^[a-f0-9]{64}$'::"text")),
    CONSTRAINT "routine_mode_cohort_priors_conservative_span_days_check" CHECK (("conservative_span_days" > 0)),
    CONSTRAINT "routine_mode_cohort_priors_context_key_check" CHECK (("length"(TRIM(BOTH FROM "context_key")) > 0)),
    CONSTRAINT "routine_mode_cohort_priors_contributor_count_check" CHECK (("contributor_count" > 0)),
    CONSTRAINT "routine_mode_cohort_priors_distinct_support_dates_check" CHECK (("distinct_support_dates" > 0)),
    CONSTRAINT "routine_mode_cohort_priors_evidence_version_check" CHECK (("length"(TRIM(BOTH FROM "evidence_version")) > 0)),
    CONSTRAINT "routine_mode_cohort_priors_input_sha256_check" CHECK (("input_sha256" ~ '^[a-f0-9]{64}$'::"text")),
    CONSTRAINT "routine_mode_cohort_priors_minimum_profile_confidence_check" CHECK ((("minimum_profile_confidence" > (0)::double precision) AND ("minimum_profile_confidence" <= (1)::double precision))),
    CONSTRAINT "routine_mode_cohort_priors_neutral_p95_minutes_check" CHECK (("neutral_p95_minutes" > 0)),
    CONSTRAINT "routine_mode_cohort_priors_prior_sha256_check" CHECK (("prior_sha256" ~ '^[a-f0-9]{64}$'::"text")),
    CONSTRAINT "routine_mode_cohort_priors_quality_state_check" CHECK (("quality_state" = ANY (ARRAY['valid'::"text", 'low_support'::"text", 'stale'::"text", 'drift_invalid'::"text", 'coverage_invalid'::"text"]))),
    CONSTRAINT "routine_mode_cohort_priors_routine_mode_check" CHECK (("routine_mode" = ANY (ARRAY['regular_9to5'::"text", 'semester_break'::"text", 'shift_irregular'::"text"]))),
    CONSTRAINT "routine_mode_cohort_priors_source_generation_check" CHECK (("source_generation" >= 0))
);


ALTER TABLE "public"."routine_mode_cohort_priors" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_activity_profiles" (
    "user_id" "uuid" NOT NULL,
    "hourly_thresholds" double precision[] NOT NULL,
    "weekend_multiplier" double precision DEFAULT 1.0 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "model_version" "text" DEFAULT 'hourly_threshold_v1'::"text" NOT NULL,
    "model_confidence" double precision,
    "hourly_confidence" double precision[],
    "gap_stats" "jsonb",
    "model_explanation" "text",
    CONSTRAINT "user_activity_profiles_hourly_thresholds_check" CHECK (("cardinality"("hourly_thresholds") = 24))
);


ALTER TABLE "public"."user_activity_profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_settings" (
    "user_id" "uuid" NOT NULL,
    "sensitivity" "text" DEFAULT 'balanced'::"text" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "share_activity" boolean DEFAULT false NOT NULL,
    "sleep_start_utc" time without time zone,
    "sleep_end_utc" time without time zone,
    "pattern_hash" "text",
    "timezone" "text" DEFAULT 'UTC'::"text" NOT NULL,
    "sleep_start_local" time without time zone,
    "sleep_end_local" time without time zone,
    "emergency_gps_consent" boolean DEFAULT false NOT NULL,
    CONSTRAINT "user_settings_sensitivity_check" CHECK (("sensitivity" = ANY (ARRAY['high'::"text", 'balanced'::"text", 'low'::"text"])))
);


ALTER TABLE "public"."user_settings" OWNER TO "postgres";


COMMENT ON COLUMN "public"."user_settings"."emergency_gps_consent" IS 'Whether the user agreed to their coordinates being captured and shared with their circle during an SOS. Enforced in dispatchSos; false means no location is fetched at all.';



ALTER TABLE ONLY "private"."adaptive_alert_shadow_cohort_dirty"
    ADD CONSTRAINT "adaptive_alert_shadow_cohort_dirty_pkey" PRIMARY KEY ("version_id", "routine_mode", "context_key");



ALTER TABLE ONLY "private"."adaptive_alert_shadow_cycle_runs"
    ADD CONSTRAINT "adaptive_alert_shadow_cycle_runs_pkey" PRIMARY KEY ("version_id", "evaluated_minute");



ALTER TABLE ONLY "private"."adaptive_alert_shadow_daily_reports"
    ADD CONSTRAINT "adaptive_alert_shadow_daily_reports_pkey" PRIMARY KEY ("version_id", "report_date", "segment_key");



ALTER TABLE ONLY "private"."adaptive_alert_shadow_intervention_cursor"
    ADD CONSTRAINT "adaptive_alert_shadow_intervention_cursor_pkey" PRIMARY KEY ("version_id", "source_kind");



ALTER TABLE ONLY "private"."adaptive_alert_shadow_profile_dirty"
    ADD CONSTRAINT "adaptive_alert_shadow_profile_dirty_pkey" PRIMARY KEY ("version_id", "user_id");



ALTER TABLE ONLY "private"."adaptive_alert_shadow_runtime_config"
    ADD CONSTRAINT "adaptive_alert_shadow_runtime_config_pkey" PRIMARY KEY ("singleton");



ALTER TABLE ONLY "private"."adaptive_alert_shadow_subject_context_state"
    ADD CONSTRAINT "adaptive_alert_shadow_subject_context_state_pkey" PRIMARY KEY ("version_id", "user_id");



ALTER TABLE ONLY "private"."adaptive_alert_shadow_user_state"
    ADD CONSTRAINT "adaptive_alert_shadow_user_state_pkey" PRIMARY KEY ("version_id", "user_id");



ALTER TABLE ONLY "private"."alert_shadow_coverage_leases"
    ADD CONSTRAINT "alert_shadow_coverage_leases_pkey" PRIMARY KEY ("user_id", "event_id");



ALTER TABLE ONLY "private"."app_config"
    ADD CONSTRAINT "app_config_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."account_gap_profiles"
    ADD CONSTRAINT "account_gap_profiles_pkey" PRIMARY KEY ("user_id", "through_date", "lookback_days", "shrinkage_k", "percentile");



ALTER TABLE ONLY "public"."account_normal_bounds"
    ADD CONSTRAINT "account_normal_bounds_pkey" PRIMARY KEY ("user_id", "through_date", "lookback_days", "false_alarm_budget");



ALTER TABLE ONLY "public"."account_threshold_shadow"
    ADD CONSTRAINT "account_threshold_shadow_pkey" PRIMARY KEY ("user_id", "through_date", "lookback_days", "shrinkage_k", "percentile");



ALTER TABLE ONLY "public"."alert_events"
    ADD CONSTRAINT "alert_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."alert_gap_profiles"
    ADD CONSTRAINT "alert_gap_profiles_pkey" PRIMARY KEY ("version_id", "user_id", "context_key", "through_date");



ALTER TABLE ONLY "public"."alert_intervention_events"
    ADD CONSTRAINT "alert_intervention_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."alert_intervention_events"
    ADD CONSTRAINT "alert_intervention_events_source_unique" UNIQUE ("version_id", "source_kind", "source_id");



ALTER TABLE ONLY "public"."alert_judgment_evaluations"
    ADD CONSTRAINT "alert_judgment_evaluations_pkey" PRIMARY KEY ("version_id", "evaluation_kind", "evaluated_from", "evaluated_to");



ALTER TABLE ONLY "public"."alert_judgment_shadow_decisions"
    ADD CONSTRAINT "alert_judgment_shadow_decisio_version_id_user_id_evaluated__key" UNIQUE ("version_id", "user_id", "evaluated_minute");



ALTER TABLE ONLY "public"."alert_judgment_shadow_decisions"
    ADD CONSTRAINT "alert_judgment_shadow_decisions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."alert_judgment_subject_contexts"
    ADD CONSTRAINT "alert_judgment_subject_contexts_pkey" PRIMARY KEY ("id");



ALTER TABLE "public"."alert_model_versions"
    ADD CONSTRAINT "alert_model_versions_candidate_evaluator_contract_check" CHECK (((("jsonb_typeof"(("config" #> '{personal,min_confidence}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{personal,min_confidence}'::"text"[]))::numeric > (0)::numeric) AND ((("config" #>> '{personal,min_confidence}'::"text"[]))::numeric <= (1)::numeric) AND ("jsonb_typeof"(("config" -> 'evaluator'::"text")) = 'object'::"text") AND (("config" #>> '{evaluator,contract_version}'::"text"[]) = 'adaptive_candidate_v1'::"text") AND ("jsonb_typeof"(("config" -> 'emergency'::"text")) = 'object'::"text") AND (("config" #>> '{emergency,contract_version}'::"text"[]) = 'adr0022_v1'::"text") AND ("jsonb_typeof"(("config" #> '{emergency,neutral_minutes}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{emergency,neutral_minutes}'::"text"[]))::numeric = (90)::numeric) AND ((("config" #>> '{emergency,neutral_minutes}'::"text"[]))::numeric = "trunc"((("config" #>> '{emergency,neutral_minutes}'::"text"[]))::numeric)) AND (("config" #>> '{emergency,expected_live_definition_sha256}'::"text"[]) = '1907d59473d274d46a0e8e0b9ce8027037b4494b0dddf073cb46abf67db92e21'::"text") AND (("config" #>> '{emergency,expected_live_definition_sha256}'::"text"[]) ~ '^[a-f0-9]{64}$'::"text") AND ((("config" #>> '{sensitivity_buffers_minutes,high}'::"text"[]))::numeric = "trunc"((("config" #>> '{sensitivity_buffers_minutes,high}'::"text"[]))::numeric)) AND ((("config" #>> '{sensitivity_buffers_minutes,balanced}'::"text"[]))::numeric = "trunc"((("config" #>> '{sensitivity_buffers_minutes,balanced}'::"text"[]))::numeric)) AND ((("config" #>> '{sensitivity_buffers_minutes,low}'::"text"[]))::numeric = "trunc"((("config" #>> '{sensitivity_buffers_minutes,low}'::"text"[]))::numeric)) AND ((("config" #>> '{candidate_bounds,floor_minutes}'::"text"[]))::numeric = "trunc"((("config" #>> '{candidate_bounds,floor_minutes}'::"text"[]))::numeric)) AND ((("config" #>> '{candidate_bounds,ceiling_minutes}'::"text"[]))::numeric = "trunc"((("config" #>> '{candidate_bounds,ceiling_minutes}'::"text"[]))::numeric))) IS TRUE)) NOT VALID;



ALTER TABLE "public"."alert_model_versions"
    ADD CONSTRAINT "alert_model_versions_cohort_prior_contract_check" CHECK (((("jsonb_typeof"(("config" #> '{cohort,contribution_floor_minutes}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{cohort,contribution_floor_minutes}'::"text"[]))::numeric > (0)::numeric) AND ((("config" #>> '{cohort,contribution_floor_minutes}'::"text"[]))::numeric = "trunc"((("config" #>> '{cohort,contribution_floor_minutes}'::"text"[]))::numeric)) AND ("jsonb_typeof"(("config" #> '{cohort,contribution_ceiling_minutes}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{cohort,contribution_ceiling_minutes}'::"text"[]))::numeric > (0)::numeric) AND ((("config" #>> '{cohort,contribution_ceiling_minutes}'::"text"[]))::numeric = "trunc"((("config" #>> '{cohort,contribution_ceiling_minutes}'::"text"[]))::numeric)) AND ((("config" #>> '{cohort,contribution_ceiling_minutes}'::"text"[]))::numeric >= (("config" #>> '{cohort,contribution_floor_minutes}'::"text"[]))::numeric) AND ("jsonb_typeof"(("config" #> '{cohort,min_span_days}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{cohort,min_span_days}'::"text"[]))::numeric > (0)::numeric) AND ((("config" #>> '{cohort,min_span_days}'::"text"[]))::numeric = "trunc"((("config" #>> '{cohort,min_span_days}'::"text"[]))::numeric)) AND ("jsonb_typeof"(("config" #> '{cohort,min_confidence}'::"text"[])) = 'number'::"text") AND ((("config" #>> '{cohort,min_confidence}'::"text"[]))::numeric > (0)::numeric) AND ((("config" #>> '{cohort,min_confidence}'::"text"[]))::numeric <= (1)::numeric) AND ("jsonb_typeof"(("config" #> '{cohort,confidence_formula_version}'::"text"[])) = 'string'::"text") AND (("config" #>> '{cohort,confidence_formula_version}'::"text"[]) = 'cohort_support_min_v1'::"text")) IS TRUE)) NOT VALID;



ALTER TABLE ONLY "public"."alert_model_versions"
    ADD CONSTRAINT "alert_model_versions_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."alert_model_versions"
    ADD CONSTRAINT "alert_model_versions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."alert_observation_coverage_intervals"
    ADD CONSTRAINT "alert_observation_coverage_intervals_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."alert_sleep_night_contexts"
    ADD CONSTRAINT "alert_sleep_night_contexts_pkey" PRIMARY KEY ("version_id", "user_id", "anchor_date");



ALTER TABLE ONLY "public"."alerts"
    ADD CONSTRAINT "alerts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."app_admins"
    ADD CONSTRAINT "app_admins_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."app_versions"
    ADD CONSTRAINT "app_versions_pkey" PRIMARY KEY ("version");



ALTER TABLE ONLY "public"."behavior_pings"
    ADD CONSTRAINT "behavior_pings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."checkin_tasks"
    ADD CONSTRAINT "checkin_tasks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."clients"
    ADD CONSTRAINT "clients_pkey" PRIMARY KEY ("user_id", "client_id");



ALTER TABLE ONLY "public"."communities"
    ADD CONSTRAINT "communities_invite_code_key" UNIQUE ("invite_code");



ALTER TABLE ONLY "public"."communities"
    ADD CONSTRAINT "communities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."community_members"
    ADD CONSTRAINT "community_members_pkey" PRIMARY KEY ("community_id", "user_id");



ALTER TABLE ONLY "public"."daily_activity_aggregates"
    ADD CONSTRAINT "daily_activity_aggregates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."daily_activity_aggregates"
    ADD CONSTRAINT "daily_activity_aggregates_user_id_date_key" UNIQUE ("user_id", "date");



ALTER TABLE ONLY "public"."device_activity_samples"
    ADD CONSTRAINT "device_activity_samples_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_state"
    ADD CONSTRAINT "device_state_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."emergency_info"
    ADD CONSTRAINT "emergency_info_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."gm_mutes"
    ADD CONSTRAINT "gm_mutes_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."group_members"
    ADD CONSTRAINT "group_members_pkey" PRIMARY KEY ("group_id", "user_id");



ALTER TABLE ONLY "public"."groups"
    ADD CONSTRAINT "groups_invite_code_key" UNIQUE ("invite_code");



ALTER TABLE ONLY "public"."groups"
    ADD CONSTRAINT "groups_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."guardianships"
    ADD CONSTRAINT "guardianships_guardian_id_ward_id_key" UNIQUE ("guardian_id", "ward_id");



ALTER TABLE ONLY "public"."guardianships"
    ADD CONSTRAINT "guardianships_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."heartbeat_tokens"
    ADD CONSTRAINT "heartbeat_tokens_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."heartbeat_tokens"
    ADD CONSTRAINT "heartbeat_tokens_token_key" UNIQUE ("token");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_guardian_code_key" UNIQUE ("guardian_code");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."push_subscriptions"
    ADD CONSTRAINT "push_subscriptions_endpoint_key" UNIQUE ("endpoint");



ALTER TABLE ONLY "public"."push_subscriptions"
    ADD CONSTRAINT "push_subscriptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."push_tokens"
    ADD CONSTRAINT "push_tokens_pkey" PRIMARY KEY ("token");



ALTER TABLE ONLY "public"."routine_mode_cohort_generations"
    ADD CONSTRAINT "routine_mode_cohort_generations_pkey" PRIMARY KEY ("routine_mode");



ALTER TABLE ONLY "public"."routine_mode_cohort_invalidations"
    ADD CONSTRAINT "routine_mode_cohort_invalidations_pkey" PRIMARY KEY ("routine_mode");



ALTER TABLE ONLY "public"."routine_mode_cohort_priors"
    ADD CONSTRAINT "routine_mode_cohort_priors_pkey" PRIMARY KEY ("version_id", "routine_mode", "context_key", "through_date");



ALTER TABLE ONLY "public"."user_activity_profiles"
    ADD CONSTRAINT "user_activity_profiles_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."user_settings"
    ADD CONSTRAINT "user_settings_pkey" PRIMARY KEY ("user_id");



CREATE INDEX "alert_shadow_coverage_leases_user_received_idx" ON "private"."alert_shadow_coverage_leases" USING "btree" ("user_id", "received_at", "event_id");



CREATE INDEX "account_gap_profiles_through_date_idx" ON "public"."account_gap_profiles" USING "btree" ("through_date" DESC, "user_id");



CREATE INDEX "account_normal_bounds_through_date_idx" ON "public"."account_normal_bounds" USING "btree" ("through_date" DESC, "user_id");



CREATE INDEX "account_threshold_shadow_through_date_idx" ON "public"."account_threshold_shadow" USING "btree" ("through_date" DESC, "user_id");



CREATE INDEX "alert_events_actor_idx" ON "public"."alert_events" USING "btree" ("actor_id");



CREATE INDEX "alert_events_alert_idx" ON "public"."alert_events" USING "btree" ("alert_id", "at");



CREATE INDEX "alert_intervention_events_version_user_time_idx" ON "public"."alert_intervention_events" USING "btree" ("version_id", "user_id", "occurred_at");



CREATE INDEX "alert_judgment_subject_contexts_as_of_idx" ON "public"."alert_judgment_subject_contexts" USING "btree" ("version_id", "user_id", "effective_from", "effective_to", "captured_at");



CREATE INDEX "alert_observation_coverage_intervals_version_user_time_idx" ON "public"."alert_observation_coverage_intervals" USING "btree" ("version_id", "user_id", "starts_at", "ends_at");



CREATE UNIQUE INDEX "alerts_one_open_per_user" ON "public"."alerts" USING "btree" ("user_id") WHERE ("status" = 'open'::"text");



CREATE INDEX "alerts_open_idx" ON "public"."alerts" USING "btree" ("status") WHERE ("status" = 'open'::"text");



CREATE INDEX "alerts_paused_by_idx" ON "public"."alerts" USING "btree" ("paused_by");



CREATE INDEX "alerts_resolved_by_idx" ON "public"."alerts" USING "btree" ("resolved_by");



CREATE INDEX "alerts_silence_user_opened_idx" ON "public"."alerts" USING "btree" ("user_id", "opened_at") WHERE ("cause" = 'silence'::"text");



CREATE INDEX "alerts_user_id_idx" ON "public"."alerts" USING "btree" ("user_id");



CREATE UNIQUE INDEX "behavior_pings_event_id_uidx" ON "public"."behavior_pings" USING "btree" ("user_id", "event_id") WHERE ("event_id" IS NOT NULL);



CREATE INDEX "behavior_pings_ingest2_user_received_idx" ON "public"."behavior_pings" USING "btree" ("user_id", "received_at", "id") WHERE ("ingest_version" = 2);



CREATE INDEX "behavior_pings_user_at_idx" ON "public"."behavior_pings" USING "btree" ("user_id", "at" DESC);



CREATE INDEX "checkin_tasks_created_by_idx" ON "public"."checkin_tasks" USING "btree" ("created_by");



CREATE INDEX "checkin_tasks_due_idx" ON "public"."checkin_tasks" USING "btree" ("next_due_at") WHERE ("status" = 'active'::"text");



CREATE INDEX "checkin_tasks_ward_idx" ON "public"."checkin_tasks" USING "btree" ("ward_id");



CREATE INDEX "communities_created_by_idx" ON "public"."communities" USING "btree" ("created_by");



CREATE INDEX "community_members_user_id_idx" ON "public"."community_members" USING "btree" ("user_id");



CREATE INDEX "device_activity_samples_trigger_idx" ON "public"."device_activity_samples" USING "btree" ("trigger", "observed_at" DESC);



CREATE INDEX "device_activity_samples_user_time_idx" ON "public"."device_activity_samples" USING "btree" ("user_id", "observed_at" DESC);



CREATE INDEX "group_members_user_id_idx" ON "public"."group_members" USING "btree" ("user_id");



CREATE INDEX "groups_community_id_idx" ON "public"."groups" USING "btree" ("community_id");



CREATE INDEX "groups_created_by_idx" ON "public"."groups" USING "btree" ("created_by");



CREATE INDEX "guardianships_guardian_id_idx" ON "public"."guardianships" USING "btree" ("guardian_id");



CREATE INDEX "guardianships_ward_id_idx" ON "public"."guardianships" USING "btree" ("ward_id");



CREATE INDEX "notifications_alert_idx" ON "public"."notifications" USING "btree" ("alert_id");



CREATE INDEX "notifications_delivery_claim_idx" ON "public"."notifications" USING "btree" ("created_at") WHERE (("pushed_at" IS NULL) AND ("delivery_attempts" < 5));



CREATE INDEX "notifications_recipient_idx" ON "public"."notifications" USING "btree" ("recipient_id", "created_at" DESC);



CREATE INDEX "notifications_unpushed_idx" ON "public"."notifications" USING "btree" ("created_at") WHERE ("pushed_at" IS NULL);



CREATE INDEX "push_subscriptions_user_idx" ON "public"."push_subscriptions" USING "btree" ("user_id");



CREATE OR REPLACE TRIGGER "adaptive_alert_shadow_profile_dirty_trigger" AFTER UPDATE OF "routine_pattern", "consent_data_sharing" ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "private"."mark_adaptive_alert_shadow_dirty"();



CREATE OR REPLACE TRIGGER "adaptive_alert_shadow_settings_dirty_trigger" AFTER UPDATE OF "sensitivity", "timezone" ON "public"."user_settings" FOR EACH ROW EXECUTE FUNCTION "private"."mark_adaptive_alert_shadow_dirty"();



CREATE OR REPLACE TRIGGER "on_alert_gap_profile_contract_pin" BEFORE INSERT OR UPDATE ON "public"."alert_gap_profiles" FOR EACH ROW EXECUTE FUNCTION "private"."pin_alert_gap_profile_contract"();



CREATE OR REPLACE TRIGGER "on_alert_gap_profile_routine_mode_cohort_invalidation" AFTER INSERT OR DELETE OR UPDATE ON "public"."alert_gap_profiles" FOR EACH ROW EXECUTE FUNCTION "private"."invalidate_routine_mode_cohort_profile"();



CREATE OR REPLACE TRIGGER "on_community_created" AFTER INSERT ON "public"."communities" FOR EACH ROW EXECUTE FUNCTION "public"."handle_new_community"();



CREATE OR REPLACE TRIGGER "on_group_created" AFTER INSERT ON "public"."groups" FOR EACH ROW EXECUTE FUNCTION "public"."handle_new_group"();



CREATE OR REPLACE TRIGGER "on_profile_routine_mode_cohort_invalidation" AFTER INSERT OR DELETE OR UPDATE OF "routine_pattern", "consent_data_sharing" ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "private"."invalidate_routine_mode_cohort"();



ALTER TABLE ONLY "private"."adaptive_alert_shadow_cohort_dirty"
    ADD CONSTRAINT "adaptive_alert_shadow_cohort_dirty_version_id_fkey" FOREIGN KEY ("version_id") REFERENCES "public"."alert_model_versions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."adaptive_alert_shadow_cycle_runs"
    ADD CONSTRAINT "adaptive_alert_shadow_cycle_runs_version_id_fkey" FOREIGN KEY ("version_id") REFERENCES "public"."alert_model_versions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."adaptive_alert_shadow_daily_reports"
    ADD CONSTRAINT "adaptive_alert_shadow_daily_reports_version_id_fkey" FOREIGN KEY ("version_id") REFERENCES "public"."alert_model_versions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."adaptive_alert_shadow_intervention_cursor"
    ADD CONSTRAINT "adaptive_alert_shadow_intervention_cursor_version_id_fkey" FOREIGN KEY ("version_id") REFERENCES "public"."alert_model_versions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."adaptive_alert_shadow_profile_dirty"
    ADD CONSTRAINT "adaptive_alert_shadow_profile_dirty_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."adaptive_alert_shadow_profile_dirty"
    ADD CONSTRAINT "adaptive_alert_shadow_profile_dirty_version_id_fkey" FOREIGN KEY ("version_id") REFERENCES "public"."alert_model_versions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."adaptive_alert_shadow_runtime_config"
    ADD CONSTRAINT "adaptive_alert_shadow_runtime_config_version_id_fkey" FOREIGN KEY ("version_id") REFERENCES "public"."alert_model_versions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "private"."adaptive_alert_shadow_subject_context_state"
    ADD CONSTRAINT "adaptive_alert_shadow_subject_context_state_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."adaptive_alert_shadow_subject_context_state"
    ADD CONSTRAINT "adaptive_alert_shadow_subject_context_state_version_id_fkey" FOREIGN KEY ("version_id") REFERENCES "public"."alert_model_versions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."adaptive_alert_shadow_user_state"
    ADD CONSTRAINT "adaptive_alert_shadow_user_state_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."adaptive_alert_shadow_user_state"
    ADD CONSTRAINT "adaptive_alert_shadow_user_state_version_id_fkey" FOREIGN KEY ("version_id") REFERENCES "public"."alert_model_versions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "private"."alert_shadow_coverage_leases"
    ADD CONSTRAINT "alert_shadow_coverage_leases_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."account_gap_profiles"
    ADD CONSTRAINT "account_gap_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."account_normal_bounds"
    ADD CONSTRAINT "account_normal_bounds_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."account_threshold_shadow"
    ADD CONSTRAINT "account_threshold_shadow_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."alert_events"
    ADD CONSTRAINT "alert_events_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."alert_events"
    ADD CONSTRAINT "alert_events_alert_id_fkey" FOREIGN KEY ("alert_id") REFERENCES "public"."alerts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."alert_gap_profiles"
    ADD CONSTRAINT "alert_gap_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."alert_gap_profiles"
    ADD CONSTRAINT "alert_gap_profiles_version_id_fkey" FOREIGN KEY ("version_id") REFERENCES "public"."alert_model_versions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."alert_intervention_events"
    ADD CONSTRAINT "alert_intervention_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."alert_intervention_events"
    ADD CONSTRAINT "alert_intervention_events_version_id_fkey" FOREIGN KEY ("version_id") REFERENCES "public"."alert_model_versions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."alert_judgment_evaluations"
    ADD CONSTRAINT "alert_judgment_evaluations_version_id_fkey" FOREIGN KEY ("version_id") REFERENCES "public"."alert_model_versions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."alert_judgment_shadow_decisions"
    ADD CONSTRAINT "alert_judgment_shadow_decisions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."alert_judgment_shadow_decisions"
    ADD CONSTRAINT "alert_judgment_shadow_decisions_version_id_fkey" FOREIGN KEY ("version_id") REFERENCES "public"."alert_model_versions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."alert_judgment_subject_contexts"
    ADD CONSTRAINT "alert_judgment_subject_contexts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."alert_judgment_subject_contexts"
    ADD CONSTRAINT "alert_judgment_subject_contexts_version_id_fkey" FOREIGN KEY ("version_id") REFERENCES "public"."alert_model_versions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."alert_observation_coverage_intervals"
    ADD CONSTRAINT "alert_observation_coverage_intervals_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."alert_observation_coverage_intervals"
    ADD CONSTRAINT "alert_observation_coverage_intervals_version_id_fkey" FOREIGN KEY ("version_id") REFERENCES "public"."alert_model_versions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."alert_sleep_night_contexts"
    ADD CONSTRAINT "alert_sleep_night_contexts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."alert_sleep_night_contexts"
    ADD CONSTRAINT "alert_sleep_night_contexts_version_id_fkey" FOREIGN KEY ("version_id") REFERENCES "public"."alert_model_versions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."alerts"
    ADD CONSTRAINT "alerts_paused_by_fkey" FOREIGN KEY ("paused_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."alerts"
    ADD CONSTRAINT "alerts_resolved_by_fkey" FOREIGN KEY ("resolved_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."alerts"
    ADD CONSTRAINT "alerts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."app_admins"
    ADD CONSTRAINT "app_admins_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."behavior_pings"
    ADD CONSTRAINT "behavior_pings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."checkin_tasks"
    ADD CONSTRAINT "checkin_tasks_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."checkin_tasks"
    ADD CONSTRAINT "checkin_tasks_ward_id_fkey" FOREIGN KEY ("ward_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."clients"
    ADD CONSTRAINT "clients_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."communities"
    ADD CONSTRAINT "communities_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."community_members"
    ADD CONSTRAINT "community_members_community_id_fkey" FOREIGN KEY ("community_id") REFERENCES "public"."communities"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."community_members"
    ADD CONSTRAINT "community_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."daily_activity_aggregates"
    ADD CONSTRAINT "daily_activity_aggregates_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_activity_samples"
    ADD CONSTRAINT "device_activity_samples_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."device_state"
    ADD CONSTRAINT "device_state_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."emergency_info"
    ADD CONSTRAINT "emergency_info_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."gm_mutes"
    ADD CONSTRAINT "gm_mutes_muted_by_fkey" FOREIGN KEY ("muted_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."gm_mutes"
    ADD CONSTRAINT "gm_mutes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."group_members"
    ADD CONSTRAINT "group_members_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "public"."groups"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."group_members"
    ADD CONSTRAINT "group_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."groups"
    ADD CONSTRAINT "groups_community_id_fkey" FOREIGN KEY ("community_id") REFERENCES "public"."communities"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."groups"
    ADD CONSTRAINT "groups_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."guardianships"
    ADD CONSTRAINT "guardianships_guardian_id_fkey" FOREIGN KEY ("guardian_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."guardianships"
    ADD CONSTRAINT "guardianships_ward_id_fkey" FOREIGN KEY ("ward_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."heartbeat_tokens"
    ADD CONSTRAINT "heartbeat_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_alert_id_fkey" FOREIGN KEY ("alert_id") REFERENCES "public"."alerts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_recipient_id_fkey" FOREIGN KEY ("recipient_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."push_subscriptions"
    ADD CONSTRAINT "push_subscriptions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."push_tokens"
    ADD CONSTRAINT "push_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."routine_mode_cohort_priors"
    ADD CONSTRAINT "routine_mode_cohort_priors_version_id_fkey" FOREIGN KEY ("version_id") REFERENCES "public"."alert_model_versions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."user_activity_profiles"
    ADD CONSTRAINT "user_activity_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_settings"
    ADD CONSTRAINT "user_settings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE "private"."adaptive_alert_shadow_cohort_dirty" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "private"."adaptive_alert_shadow_cycle_runs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "private"."adaptive_alert_shadow_daily_reports" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "private"."adaptive_alert_shadow_intervention_cursor" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "private"."adaptive_alert_shadow_profile_dirty" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "private"."adaptive_alert_shadow_runtime_config" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "private"."adaptive_alert_shadow_subject_context_state" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "private"."adaptive_alert_shadow_user_state" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "private"."alert_shadow_coverage_leases" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "Allow GMs to manage versions" ON "public"."app_versions" USING ((("auth"."uid"() IS NOT NULL) AND "private"."is_admin"("auth"."uid"())));



CREATE POLICY "Allow GMs to read any version" ON "public"."app_versions" FOR SELECT USING ((("auth"."uid"() IS NOT NULL) AND "private"."is_admin"("auth"."uid"())));



CREATE POLICY "Allow public read of released or public canary versions" ON "public"."app_versions" FOR SELECT USING (((("status")::"text" = 'released'::"text") OR ((("status")::"text" = 'canary'::"text") AND ("public_rollout" = true))));



ALTER TABLE "public"."account_gap_profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."account_normal_bounds" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."account_threshold_shadow" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."alert_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "alert_events_select" ON "public"."alert_events" FOR SELECT TO "authenticated" USING ("private"."can_see_alert"("alert_id", ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."alert_gap_profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."alert_intervention_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."alert_judgment_evaluations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."alert_judgment_shadow_decisions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."alert_judgment_subject_contexts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."alert_model_versions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."alert_observation_coverage_intervals" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."alert_sleep_night_contexts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."alerts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "alerts_select" ON "public"."alerts" FOR SELECT TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") = "user_id") OR "private"."is_guardian_of"("user_id", ( SELECT "auth"."uid"() AS "uid")) OR "private"."watches_user"(( SELECT "auth"."uid"() AS "uid"), "user_id") OR (("stage" = ANY (ARRAY['community'::"text", 'terminal'::"text"])) AND "private"."shares_community"(( SELECT "auth"."uid"() AS "uid"), "user_id"))));



ALTER TABLE "public"."app_admins" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."app_versions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."behavior_pings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "behavior_pings_select" ON "public"."behavior_pings" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."checkin_tasks" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "checkin_tasks_select" ON "public"."checkin_tasks" FOR SELECT TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") = "ward_id") OR (( SELECT "auth"."uid"() AS "uid") = "created_by")));



ALTER TABLE "public"."clients" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "clients select during active alert" ON "public"."clients" FOR SELECT TO "authenticated" USING ((("auth"."uid"() = "user_id") OR ((EXISTS ( SELECT 1
   FROM "public"."alerts" "a"
  WHERE (("a"."user_id" = "clients"."user_id") AND ("a"."status" = 'open'::"text") AND ("a"."stage" = ANY (ARRAY['group'::"text", 'community'::"text", 'terminal'::"text"]))))) AND ("private"."is_guardian_of"("user_id", ( SELECT "auth"."uid"() AS "uid")) OR "private"."watches_user"(( SELECT "auth"."uid"() AS "uid"), "user_id") OR "private"."shares_community"(( SELECT "auth"."uid"() AS "uid"), "user_id")))));



ALTER TABLE "public"."communities" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "communities_delete" ON "public"."communities" FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."community_members" "cm"
  WHERE (("cm"."community_id" = "communities"."id") AND ("cm"."user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("cm"."role" = 'admin'::"text") AND ("cm"."status" = 'active'::"text")))));



CREATE POLICY "communities_insert" ON "public"."communities" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "created_by"));



CREATE POLICY "communities_select" ON "public"."communities" FOR SELECT TO "authenticated" USING ((("created_by" = ( SELECT "auth"."uid"() AS "uid")) OR "private"."is_community_member"("id", ( SELECT "auth"."uid"() AS "uid"))));



CREATE POLICY "communities_update" ON "public"."communities" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."community_members" "cm"
  WHERE (("cm"."community_id" = "communities"."id") AND ("cm"."user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("cm"."role" = 'admin'::"text") AND ("cm"."status" = 'active'::"text"))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."community_members" "cm"
  WHERE (("cm"."community_id" = "communities"."id") AND ("cm"."user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("cm"."role" = 'admin'::"text") AND ("cm"."status" = 'active'::"text")))));



ALTER TABLE "public"."community_members" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "community_members_delete" ON "public"."community_members" FOR DELETE TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") = "user_id") OR "private"."is_community_admin"("community_id", ( SELECT "auth"."uid"() AS "uid"))));



CREATE POLICY "community_members_select" ON "public"."community_members" FOR SELECT TO "authenticated" USING ("private"."is_community_member"("community_id", ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "community_members_update" ON "public"."community_members" FOR UPDATE TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") = "user_id") OR "private"."is_community_admin"("community_id", ( SELECT "auth"."uid"() AS "uid")))) WITH CHECK (((( SELECT "auth"."uid"() AS "uid") = "user_id") OR "private"."is_community_admin"("community_id", ( SELECT "auth"."uid"() AS "uid"))));



ALTER TABLE "public"."daily_activity_aggregates" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "daily_aggregates_all_own" ON "public"."daily_activity_aggregates" TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."device_activity_samples" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."device_state" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "device_state_select" ON "public"."device_state" FOR SELECT TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") = "user_id") OR "private"."watches_user"(( SELECT "auth"."uid"() AS "uid"), "user_id") OR "private"."is_guardian_of"("user_id", ( SELECT "auth"."uid"() AS "uid"))));



ALTER TABLE "public"."emergency_info" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "emergency_info_insert" ON "public"."emergency_info" FOR INSERT TO "authenticated" WITH CHECK (((( SELECT "auth"."uid"() AS "uid") = "user_id") OR "private"."is_guardian_of"("user_id", ( SELECT "auth"."uid"() AS "uid"))));



CREATE POLICY "emergency_info_select" ON "public"."emergency_info" FOR SELECT TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") = "user_id") OR ((EXISTS ( SELECT 1
   FROM "public"."alerts" "a"
  WHERE (("a"."user_id" = "emergency_info"."user_id") AND ("a"."status" = 'open'::"text") AND (("a"."stage" = 'terminal'::"text") OR ("a"."cause" = 'sos'::"text"))))) AND ("private"."is_guardian_of"("user_id", ( SELECT "auth"."uid"() AS "uid")) OR "private"."watches_user"(( SELECT "auth"."uid"() AS "uid"), "user_id") OR "private"."shares_community"(( SELECT "auth"."uid"() AS "uid"), "user_id")))));



CREATE POLICY "emergency_info_update" ON "public"."emergency_info" FOR UPDATE TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") = "user_id") OR "private"."is_guardian_of"("user_id", ( SELECT "auth"."uid"() AS "uid")))) WITH CHECK (((( SELECT "auth"."uid"() AS "uid") = "user_id") OR "private"."is_guardian_of"("user_id", ( SELECT "auth"."uid"() AS "uid"))));



ALTER TABLE "public"."gm_mutes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."group_members" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "group_members_delete" ON "public"."group_members" FOR DELETE TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") = "user_id") OR "private"."is_group_admin"("group_id", ( SELECT "auth"."uid"() AS "uid"))));



CREATE POLICY "group_members_select" ON "public"."group_members" FOR SELECT TO "authenticated" USING ("private"."is_group_member"("group_id", ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "group_members_update" ON "public"."group_members" FOR UPDATE TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") = "user_id") OR "private"."is_group_admin"("group_id", ( SELECT "auth"."uid"() AS "uid")))) WITH CHECK (((( SELECT "auth"."uid"() AS "uid") = "user_id") OR "private"."is_group_admin"("group_id", ( SELECT "auth"."uid"() AS "uid"))));



ALTER TABLE "public"."groups" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "groups_delete" ON "public"."groups" FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."group_members" "gm"
  WHERE (("gm"."group_id" = "groups"."id") AND ("gm"."user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("gm"."role" = 'admin'::"text") AND ("gm"."status" = 'active'::"text")))));



CREATE POLICY "groups_insert" ON "public"."groups" FOR INSERT TO "authenticated" WITH CHECK (((( SELECT "auth"."uid"() AS "uid") = "created_by") AND (("community_id" IS NULL) OR "private"."is_community_member"("community_id", ( SELECT "auth"."uid"() AS "uid")))));



CREATE POLICY "groups_select" ON "public"."groups" FOR SELECT TO "authenticated" USING ((("created_by" = ( SELECT "auth"."uid"() AS "uid")) OR "private"."is_group_member"("id", ( SELECT "auth"."uid"() AS "uid")) OR (("community_id" IS NOT NULL) AND "private"."is_community_member"("community_id", ( SELECT "auth"."uid"() AS "uid")))));



CREATE POLICY "groups_update" ON "public"."groups" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."group_members" "gm"
  WHERE (("gm"."group_id" = "groups"."id") AND ("gm"."user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("gm"."role" = 'admin'::"text") AND ("gm"."status" = 'active'::"text"))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."group_members" "gm"
  WHERE (("gm"."group_id" = "groups"."id") AND ("gm"."user_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("gm"."role" = 'admin'::"text") AND ("gm"."status" = 'active'::"text")))));



ALTER TABLE "public"."guardianships" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "guardianships_delete" ON "public"."guardianships" FOR DELETE TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") = "guardian_id") OR (( SELECT "auth"."uid"() AS "uid") = "ward_id")));



CREATE POLICY "guardianships_insert" ON "public"."guardianships" FOR INSERT TO "authenticated" WITH CHECK (((( SELECT "auth"."uid"() AS "uid") = "guardian_id") OR (( SELECT "auth"."uid"() AS "uid") = "ward_id")));



CREATE POLICY "guardianships_select" ON "public"."guardianships" FOR SELECT TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") = "guardian_id") OR (( SELECT "auth"."uid"() AS "uid") = "ward_id")));



CREATE POLICY "guardianships_update" ON "public"."guardianships" FOR UPDATE TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") = "guardian_id") OR (( SELECT "auth"."uid"() AS "uid") = "ward_id"))) WITH CHECK (((( SELECT "auth"."uid"() AS "uid") = "guardian_id") OR (( SELECT "auth"."uid"() AS "uid") = "ward_id")));



ALTER TABLE "public"."heartbeat_tokens" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "heartbeat_tokens_select" ON "public"."heartbeat_tokens" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."notifications" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "notifications_delete" ON "public"."notifications" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "recipient_id"));



CREATE POLICY "notifications_select" ON "public"."notifications" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "recipient_id"));



CREATE POLICY "notifications_update" ON "public"."notifications" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "recipient_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "recipient_id"));



ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles_insert" ON "public"."profiles" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "id"));



CREATE POLICY "profiles_select" ON "public"."profiles" FOR SELECT TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") = "id") OR "private"."shares_group_with"("id", ( SELECT "auth"."uid"() AS "uid")) OR "private"."guardian_pair"("id", ( SELECT "auth"."uid"() AS "uid"))));



CREATE POLICY "profiles_update" ON "public"."profiles" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "id"));



CREATE POLICY "push_subs_delete" ON "public"."push_subscriptions" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "push_subs_insert" ON "public"."push_subscriptions" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "push_subs_select" ON "public"."push_subscriptions" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "push_subs_update" ON "public"."push_subscriptions" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."push_subscriptions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."push_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."routine_mode_cohort_generations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."routine_mode_cohort_invalidations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."routine_mode_cohort_priors" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_activity_profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_profiles_select_own" ON "public"."user_activity_profiles" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."user_settings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_settings_insert" ON "public"."user_settings" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "user_settings_select" ON "public"."user_settings" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



CREATE POLICY "user_settings_update" ON "public"."user_settings" FOR UPDATE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT USAGE ON SCHEMA "private" TO "authenticated";



REVOKE ALL ON FUNCTION "private"."aggregate_user_daily_activity"("_user_id" "uuid", "_date" "date") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."alert_candidate_config_is_valid"("_config" "jsonb") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."apply_liveness_side_effects"("_user_id" "uuid", "_observed_at" timestamp with time zone, "_received_at" timestamp with time zone) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."can_see_alert"("_alert_id" "uuid", "_user" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."can_see_alert"("_alert_id" "uuid", "_user" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "private"."candidate_sleep_intervals"("_user_id" "uuid", "_from" timestamp with time zone, "_to" timestamp with time zone, "_version_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."canonical_routine_mode"("_value" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."capture_alert_shadow_interventions"("_version_id" "uuid", "_through_at" timestamp with time zone, "_max_rows" integer) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."capture_alert_shadow_subject_contexts"("_version_id" "uuid", "_captured_at" timestamp with time zone, "_max_users" integer) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."disable_adaptive_alert_shadow"("_failure_code" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."dispatch_account_shadow_cycle"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."dispatch_adaptive_alert_shadow_cycle"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."dispatch_adaptive_alert_shadow_maintenance"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."finalize_alert_shadow_coverage"("_user_id" "uuid", "_through_at" timestamp with time zone, "_retention_days" integer) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."guardian_pair"("_a" "uuid", "_b" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."guardian_pair"("_a" "uuid", "_b" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "private"."insert_behavior_ping"("_user_id" "uuid", "_event_id" "uuid", "_observed_at" timestamp with time zone, "_source" "text", "_kind" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."insert_device_sample"("_user_id" "uuid", "_event_id" "uuid", "_payload" "jsonb") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."invalidate_routine_mode_cohort"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."invalidate_routine_mode_cohort_profile"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."is_community_admin"("_community_id" "uuid", "_user" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."is_community_admin"("_community_id" "uuid", "_user" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "private"."is_community_member"("_community_id" "uuid", "_user" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."is_community_member"("_community_id" "uuid", "_user" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "private"."is_group_admin"("_group_id" "uuid", "_user" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."is_group_admin"("_group_id" "uuid", "_user" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "private"."is_group_member"("_group_id" "uuid", "_user" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."is_group_member"("_group_id" "uuid", "_user" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "private"."is_guardian_of"("_ward" "uuid", "_guardian" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."is_guardian_of"("_ward" "uuid", "_guardian" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "private"."is_in_sleep_window"("_user_id" "uuid", "_now" timestamp with time zone) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."maintain_adaptive_alert_shadow"("_through_at" timestamp with time zone, "_max_rows" integer) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."mark_adaptive_alert_shadow_dirty"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."normalized_behavior_training_sessions"("_user_id" "uuid", "_from" timestamp with time zone, "_to" timestamp with time zone, "_version_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."notify_auto_resolved"("_alert_id" "uuid", "_target" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."notify_stage"("_alert_id" "uuid", "_user" "uuid", "_stage" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."notify_stage"("_alert_id" "uuid", "_user" "uuid", "_stage" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "private"."pin_alert_gap_profile_contract"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."qualified_behavior_sessions"("_user_id" "uuid", "_from" timestamp with time zone, "_to" timestamp with time zone, "_version_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."rebuild_account_gap_profiles"("_through_date" "date", "_lookback_days" integer, "_shrinkage_k" integer, "_percentile" numeric, "_cohort_min_gaps" integer, "_cohort_min_contributors" integer, "_cohort_fallback_minutes" integer, "_cohort_requires_consent" boolean) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."rebuild_account_normal_bounds"("_through_date" "date", "_lookback_days" integer, "_false_alarm_budget" numeric, "_buffer_high" integer, "_buffer_balanced" integer, "_buffer_low" integer, "_post_wake_grace_minutes" integer) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."rebuild_alert_gap_profiles"("_version_id" "uuid", "_through_date" "date") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."rebuild_routine_mode_cohort_priors"("_version_id" "uuid", "_through_date" "date", "_routine_mode" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."record_account_threshold_shadow"("_through_date" "date", "_lookback_days" integer, "_shrinkage_k" integer, "_percentile" numeric, "_buffer_high" integer, "_buffer_balanced" integer, "_buffer_low" integer, "_neutral_floor_minutes" integer, "_post_wake_grace_minutes" integer) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."record_alert_judgment_shadow"("_version_id" "uuid", "_evaluated_at" timestamp with time zone) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."record_alert_judgment_shadow_operational"("_version_id" "uuid", "_evaluated_at" timestamp with time zone, "_max_population" integer) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."record_alert_shadow_coverage_lease_core"("_user_id" "uuid", "_client_id" "text", "_channel" "text", "_collector_contract" "text", "_collector_state" "text", "_capability_sha256" "text", "_observed_at" timestamp with time zone, "_event_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."replay_config_is_valid"("_config" "jsonb") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."resolve_alert_candidate"("_user_id" "uuid", "_evaluated_at" timestamp with time zone, "_version_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."routine_mode_cohort_prior_is_valid"("_version_id" "uuid", "_routine_mode" "text", "_through_date" "date", "_evaluated_at" timestamp with time zone) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."run_adaptive_alert_shadow_cycle"("_version_id" "uuid", "_evaluated_at" timestamp with time zone) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."run_alert_judgment_replay"("_version_id" "uuid", "_from" timestamp with time zone, "_to" timestamp with time zone) FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."shadow_live_definition_matches"("_expected_sha256" "text", "_actual_definition" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."shares_community"("_a" "uuid", "_b" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."shares_community"("_a" "uuid", "_b" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "private"."shares_group_with"("_other" "uuid", "_user" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."shares_group_with"("_other" "uuid", "_user" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "private"."silence_threshold"("_user_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "private"."watches_user"("_watcher" "uuid", "_target" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "private"."watches_user"("_watcher" "uuid", "_target" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."ack_alert"("_alert_id" "uuid", "_minutes" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ack_alert"("_alert_id" "uuid", "_minutes" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."ack_alert"("_alert_id" "uuid", "_minutes" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."am_i_gm"() TO "anon";
GRANT ALL ON FUNCTION "public"."am_i_gm"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."am_i_gm"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."become_guardian_by_code"("_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."become_guardian_by_code"("_code" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."become_guardian_by_code"("_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."claim_unpushed_notifications"("p_batch_size" integer, "p_lease_duration" interval) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."claim_unpushed_notifications"("p_batch_size" integer, "p_lease_duration" interval) TO "service_role";



REVOKE ALL ON FUNCTION "public"."clear_finished_notifications"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."clear_finished_notifications"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."clear_finished_notifications"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_checkin_task"("_ward" "uuid", "_kind" "text", "_due_time_utc" time without time zone, "_due_time_local" time without time zone, "_interval_hours" integer, "_first_due" timestamp with time zone, "_grace" integer, "_label" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_checkin_task"("_ward" "uuid", "_kind" "text", "_due_time_utc" time without time zone, "_due_time_local" time without time zone, "_interval_hours" integer, "_first_due" timestamp with time zone, "_grace" integer, "_label" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_checkin_task"("_ward" "uuid", "_kind" "text", "_due_time_utc" time without time zone, "_due_time_local" time without time zone, "_interval_hours" integer, "_first_due" timestamp with time zone, "_grace" integer, "_label" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."finalize_notification_delivery"("p_notification_id" "uuid", "p_outcome" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."finalize_notification_delivery"("p_notification_id" "uuid", "p_outcome" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_app_config"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_app_config"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_group_activity"("_group" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_group_activity"("_group" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_group_activity"("_group" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_group_activity_view"("_group" "uuid", "_view" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_group_activity_view"("_group" "uuid", "_view" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_group_activity_view"("_group" "uuid", "_view" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."gm_delete_user"("_target" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."gm_delete_user"("_target" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gm_delete_user"("_target" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."gm_list_clients"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."gm_list_clients"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."gm_list_clients"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."gm_mute_user"("_target" "uuid", "_until" timestamp with time zone, "_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."gm_mute_user"("_target" "uuid", "_until" timestamp with time zone, "_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gm_mute_user"("_target" "uuid", "_until" timestamp with time zone, "_reason" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."gm_nudge_update"("_target" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."gm_nudge_update"("_target" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gm_nudge_update"("_target" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."gm_send_concern"("_target" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."gm_send_concern"("_target" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gm_send_concern"("_target" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."gm_unmute_user"("_target" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."gm_unmute_user"("_target" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gm_unmute_user"("_target" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."handle_new_community"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."handle_new_community"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."handle_new_group"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."handle_new_group"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."handle_new_user"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."initialize_user_routine_data"("_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."initialize_user_routine_data"("_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."join_community_by_code"("_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."join_community_by_code"("_code" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."join_community_by_code"("_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."join_group_by_code"("_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."join_group_by_code"("_code" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."join_group_by_code"("_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."my_routine_status"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."my_routine_status"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."my_routine_status"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."process_checkin_tasks"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."process_checkin_tasks"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."process_escalations"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."process_escalations"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prune_stale_clients"() TO "anon";
GRANT ALL ON FUNCTION "public"."prune_stale_clients"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."prune_stale_clients"() TO "service_role";



GRANT ALL ON FUNCTION "public"."raise_sos"() TO "anon";
GRANT ALL ON FUNCTION "public"."raise_sos"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."raise_sos"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."raise_sos"("_lat" double precision, "_lng" double precision) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."raise_sos"("_lat" double precision, "_lng" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."raise_sos"("_lat" double precision, "_lng" double precision) TO "service_role";



REVOKE ALL ON FUNCTION "public"."raise_test_alert"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."raise_test_alert"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."raise_test_alert"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_alert_shadow_coverage_lease"("_client_id" "text", "_channel" "text", "_collector_contract" "text", "_collector_state" "text", "_capability_sha256" "text", "_observed_at" timestamp with time zone, "_event_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_alert_shadow_coverage_lease"("_client_id" "text", "_channel" "text", "_collector_contract" "text", "_collector_state" "text", "_capability_sha256" "text", "_observed_at" timestamp with time zone, "_event_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."record_alert_shadow_coverage_lease_for_user"("_user_id" "uuid", "_client_id" "text", "_channel" "text", "_collector_contract" "text", "_collector_state" "text", "_capability_sha256" "text", "_observed_at" timestamp with time zone, "_event_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_alert_shadow_coverage_lease_for_user"("_user_id" "uuid", "_client_id" "text", "_channel" "text", "_collector_contract" "text", "_collector_state" "text", "_capability_sha256" "text", "_observed_at" timestamp with time zone, "_event_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_behavior_ping"("event_id" "uuid", "observed_at" timestamp with time zone, "source" "text", "kind" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_behavior_ping"("event_id" "uuid", "observed_at" timestamp with time zone, "source" "text", "kind" "text") TO "service_role";
GRANT ALL ON FUNCTION "public"."record_behavior_ping"("event_id" "uuid", "observed_at" timestamp with time zone, "source" "text", "kind" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."record_behavior_ping_for_user"("_user_id" "uuid", "_event_id" "uuid", "_observed_at" timestamp with time zone, "_source" "text", "_kind" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_behavior_ping_for_user"("_user_id" "uuid", "_event_id" "uuid", "_observed_at" timestamp with time zone, "_source" "text", "_kind" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_behavior_pings"("events" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_behavior_pings"("events" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "public"."record_behavior_pings"("events" "jsonb") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."record_device_sample_for_user"("_user_id" "uuid", "_event_id" "uuid", "_payload" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_device_sample_for_user"("_user_id" "uuid", "_event_id" "uuid", "_payload" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."register_fcm_token"("_token" "text", "_platform" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."register_fcm_token"("_token" "text", "_platform" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."register_fcm_token"("_token" "text", "_platform" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."rename_community"("_community" "uuid", "_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."rename_community"("_community" "uuid", "_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."rename_community"("_community" "uuid", "_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."rename_group"("_group" "uuid", "_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."rename_group"("_group" "uuid", "_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."rename_group"("_group" "uuid", "_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."report_client"("_client_id" "text", "_platform" "text", "_version" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."report_client"("_client_id" "text", "_platform" "text", "_version" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."report_client"("_client_id" "text", "_platform" "text", "_version" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."resolve_alert"("_alert_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."resolve_alert"("_alert_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."resolve_alert"("_alert_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."resolve_my_alert"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."resolve_my_alert"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."resolve_my_alert"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."respond_checkin_task"("_task" "uuid", "_accept" boolean, "_first_due" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."respond_checkin_task"("_task" "uuid", "_accept" boolean, "_first_due" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."respond_checkin_task"("_task" "uuid", "_accept" boolean, "_first_due" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."revoke_checkin_task"("_task" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."revoke_checkin_task"("_task" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."revoke_checkin_task"("_task" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."run_daily_aggregations"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."run_daily_aggregations"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."send_concern"("_target" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."send_concern"("_target" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."send_concern"("_target" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."send_heartbeat"("_status" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."send_heartbeat"("_status" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."send_heartbeat"("_status" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."send_test_notification"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."send_test_notification"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."send_test_notification"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_display_name"("_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_display_name"("_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_display_name"("_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_group_community"("_group" "uuid", "_community" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_group_community"("_group" "uuid", "_community" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_group_community"("_group" "uuid", "_community" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_group_visibility"("_group" "uuid", "_visibility" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_group_visibility"("_group" "uuid", "_visibility" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_group_visibility"("_group" "uuid", "_visibility" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_monitoring_direction"("_group" "uuid", "_monitored" boolean, "_watching" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_monitoring_direction"("_group" "uuid", "_monitored" boolean, "_watching" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_monitoring_direction"("_group" "uuid", "_monitored" boolean, "_watching" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_sensitivity"("_s" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_sensitivity"("_s" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_sensitivity"("_s" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_share_activity"("_share" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_share_activity"("_share" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_share_activity"("_share" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_sleep_window"("_start" time without time zone, "_end" time without time zone, "_tz" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_sleep_window"("_start" time without time zone, "_end" time without time zone, "_tz" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_sleep_window"("_start" time without time zone, "_end" time without time zone, "_tz" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."trigger_weekly_routine_updates"() TO "anon";
GRANT ALL ON FUNCTION "public"."trigger_weekly_routine_updates"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trigger_weekly_routine_updates"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_checkin_task"("_task" "uuid", "_kind" "text", "_due_time_utc" time without time zone, "_due_time_local" time without time zone, "_interval_hours" integer, "_first_due" timestamp with time zone, "_grace" integer, "_label" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_checkin_task"("_task" "uuid", "_kind" "text", "_due_time_utc" time without time zone, "_due_time_local" time without time zone, "_interval_hours" integer, "_first_due" timestamp with time zone, "_grace" integer, "_label" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_checkin_task"("_task" "uuid", "_kind" "text", "_due_time_utc" time without time zone, "_due_time_local" time without time zone, "_interval_hours" integer, "_first_due" timestamp with time zone, "_grace" integer, "_label" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_sos_location"("_lat" double precision, "_lng" double precision) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_sos_location"("_lat" double precision, "_lng" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_sos_location"("_lat" double precision, "_lng" double precision) TO "service_role";



GRANT ALL ON TABLE "public"."alert_events" TO "anon";
GRANT ALL ON TABLE "public"."alert_events" TO "authenticated";
GRANT ALL ON TABLE "public"."alert_events" TO "service_role";



GRANT ALL ON TABLE "public"."alerts" TO "anon";
GRANT ALL ON TABLE "public"."alerts" TO "authenticated";
GRANT ALL ON TABLE "public"."alerts" TO "service_role";



GRANT ALL ON TABLE "public"."app_admins" TO "anon";
GRANT ALL ON TABLE "public"."app_admins" TO "authenticated";
GRANT ALL ON TABLE "public"."app_admins" TO "service_role";



GRANT ALL ON TABLE "public"."app_versions" TO "anon";
GRANT ALL ON TABLE "public"."app_versions" TO "authenticated";
GRANT ALL ON TABLE "public"."app_versions" TO "service_role";



GRANT SELECT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."behavior_pings" TO "anon";
GRANT SELECT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."behavior_pings" TO "authenticated";
GRANT ALL ON TABLE "public"."behavior_pings" TO "service_role";



GRANT ALL ON SEQUENCE "public"."behavior_pings_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."behavior_pings_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."behavior_pings_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."checkin_tasks" TO "anon";
GRANT ALL ON TABLE "public"."checkin_tasks" TO "authenticated";
GRANT ALL ON TABLE "public"."checkin_tasks" TO "service_role";



GRANT ALL ON TABLE "public"."clients" TO "anon";
GRANT ALL ON TABLE "public"."clients" TO "authenticated";
GRANT ALL ON TABLE "public"."clients" TO "service_role";



GRANT ALL ON TABLE "public"."communities" TO "anon";
GRANT ALL ON TABLE "public"."communities" TO "authenticated";
GRANT ALL ON TABLE "public"."communities" TO "service_role";



GRANT ALL ON TABLE "public"."community_members" TO "anon";
GRANT ALL ON TABLE "public"."community_members" TO "authenticated";
GRANT ALL ON TABLE "public"."community_members" TO "service_role";



GRANT ALL ON TABLE "public"."daily_activity_aggregates" TO "anon";
GRANT ALL ON TABLE "public"."daily_activity_aggregates" TO "authenticated";
GRANT ALL ON TABLE "public"."daily_activity_aggregates" TO "service_role";



GRANT ALL ON SEQUENCE "public"."daily_activity_aggregates_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."daily_activity_aggregates_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."daily_activity_aggregates_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."device_activity_samples" TO "anon";
GRANT ALL ON TABLE "public"."device_activity_samples" TO "authenticated";
GRANT ALL ON TABLE "public"."device_activity_samples" TO "service_role";



GRANT ALL ON TABLE "public"."device_state" TO "anon";
GRANT ALL ON TABLE "public"."device_state" TO "authenticated";
GRANT ALL ON TABLE "public"."device_state" TO "service_role";



GRANT ALL ON TABLE "public"."emergency_info" TO "anon";
GRANT ALL ON TABLE "public"."emergency_info" TO "authenticated";
GRANT ALL ON TABLE "public"."emergency_info" TO "service_role";



GRANT ALL ON TABLE "public"."gm_mutes" TO "anon";
GRANT ALL ON TABLE "public"."gm_mutes" TO "authenticated";
GRANT ALL ON TABLE "public"."gm_mutes" TO "service_role";



GRANT ALL ON TABLE "public"."group_members" TO "anon";
GRANT ALL ON TABLE "public"."group_members" TO "authenticated";
GRANT ALL ON TABLE "public"."group_members" TO "service_role";



GRANT ALL ON TABLE "public"."groups" TO "anon";
GRANT ALL ON TABLE "public"."groups" TO "authenticated";
GRANT ALL ON TABLE "public"."groups" TO "service_role";



GRANT ALL ON TABLE "public"."guardianships" TO "anon";
GRANT ALL ON TABLE "public"."guardianships" TO "authenticated";
GRANT ALL ON TABLE "public"."guardianships" TO "service_role";



GRANT ALL ON TABLE "public"."heartbeat_tokens" TO "anon";
GRANT ALL ON TABLE "public"."heartbeat_tokens" TO "authenticated";
GRANT ALL ON TABLE "public"."heartbeat_tokens" TO "service_role";



GRANT ALL ON TABLE "public"."notifications" TO "anon";
GRANT ALL ON TABLE "public"."notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."notifications" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."push_subscriptions" TO "anon";
GRANT ALL ON TABLE "public"."push_subscriptions" TO "authenticated";
GRANT ALL ON TABLE "public"."push_subscriptions" TO "service_role";



GRANT ALL ON TABLE "public"."push_tokens" TO "anon";
GRANT ALL ON TABLE "public"."push_tokens" TO "authenticated";
GRANT ALL ON TABLE "public"."push_tokens" TO "service_role";



GRANT ALL ON TABLE "public"."user_activity_profiles" TO "anon";
GRANT ALL ON TABLE "public"."user_activity_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."user_activity_profiles" TO "service_role";



GRANT ALL ON TABLE "public"."user_settings" TO "anon";
GRANT ALL ON TABLE "public"."user_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."user_settings" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";









-- 3. What the dump does not carry -------------------------------------------

-- 3a. Realtime publication membership.
-- pg_dump omits ALTER PUBLICATION for a schema-scoped dump, so without this the
-- client subscriptions that drive live alert and status updates would silently
-- never fire.

alter publication supabase_realtime add table public.alerts;
alter publication supabase_realtime add table public.behavior_pings;
alter publication supabase_realtime add table public.clients;
alter publication supabase_realtime add table public.communities;
alter publication supabase_realtime add table public.community_members;
alter publication supabase_realtime add table public.device_state;
alter publication supabase_realtime add table public.group_members;
alter publication supabase_realtime add table public.groups;
alter publication supabase_realtime add table public.notifications;
alter publication supabase_realtime add table public.profiles;
alter publication supabase_realtime add table public.user_settings;

-- 3b. Scheduled jobs.
-- These are rows in cron.job, not schema, so a schema dump captures none of
-- them. process-escalations is the alert engine: without it the database is
-- structurally complete and never raises an alert again.
--
-- The two http_post jobs carry only an Edge Function URL and an empty body -
-- no service role key, no bearer token - which is why they are safe to commit.
-- They do name the production project, so a from-scratch replay elsewhere will
-- call production's Edge Functions until the URL is pointed somewhere else.

select cron.schedule('process-escalations', '* * * * *', $job$select public.process_escalations();$job$);
select cron.schedule('process-checkin-tasks', '* * * * *', $job$select public.process_checkin_tasks();$job$);
select cron.schedule('push-dispatch', '* * * * *', $job$
      select net.http_post(
        url := 'https://byekgmqyqlftgoveqnku.supabase.co/functions/v1/push-dispatch',
        headers := jsonb_build_object('Content-Type', 'application/json'),
        body := '{}'::jsonb
      );
$job$);
select cron.schedule('prune-stale-clients', '17 3 * * *', $job$select public.prune_stale_clients();$job$);
select cron.schedule('run-daily-aggregations', '5 0 * * *', $job$select public.run_daily_aggregations();$job$);
select cron.schedule('adaptive-alert-shadow-cycle-v1', '*/5 * * * *', $job$select private.dispatch_adaptive_alert_shadow_cycle();$job$);
select cron.schedule('adaptive-alert-shadow-maintenance-v1', '17 2 * * *', $job$select private.dispatch_adaptive_alert_shadow_maintenance();$job$);
select cron.schedule('account-shadow-cycle-v1', '37 2 * * *', $job$SELECT private.rebuild_account_normal_bounds();$job$);
select cron.schedule('passive-poll', '*/15 * * * *', $job$
      select net.http_post(
        url := 'https://byekgmqyqlftgoveqnku.supabase.co/functions/v1/passive-poll',
        headers := jsonb_build_object('Content-Type', 'application/json'),
        body := '{}'::jsonb
      );
$job$);

-- 4. Privileges production actually holds -----------------------------------
-- Supabase default privileges grant ALL on new tables in public to anon,
-- authenticated and service_role. Production had the unused ones taken back on
-- 14 tables, and a dump cannot express that: it records what was granted and
-- has no way to record what was revoked afterwards. Without this block a
-- rebuilt database would hand anon and authenticated REFERENCES, TRIGGER and
-- TRUNCATE on shadow-model and alert-judgment tables that production denies
-- them. Recovered from supabase db diff --linked, which is the only check that
-- catches a missing revoke.

revoke references on table "public"."account_gap_profiles" from "anon";
revoke trigger on table "public"."account_gap_profiles" from "anon";
revoke truncate on table "public"."account_gap_profiles" from "anon";
revoke references on table "public"."account_gap_profiles" from "authenticated";
revoke trigger on table "public"."account_gap_profiles" from "authenticated";
revoke truncate on table "public"."account_gap_profiles" from "authenticated";
revoke references on table "public"."account_gap_profiles" from "service_role";
revoke trigger on table "public"."account_gap_profiles" from "service_role";
revoke truncate on table "public"."account_gap_profiles" from "service_role";
revoke references on table "public"."account_normal_bounds" from "anon";
revoke trigger on table "public"."account_normal_bounds" from "anon";
revoke truncate on table "public"."account_normal_bounds" from "anon";
revoke references on table "public"."account_normal_bounds" from "authenticated";
revoke trigger on table "public"."account_normal_bounds" from "authenticated";
revoke truncate on table "public"."account_normal_bounds" from "authenticated";
revoke references on table "public"."account_normal_bounds" from "service_role";
revoke trigger on table "public"."account_normal_bounds" from "service_role";
revoke truncate on table "public"."account_normal_bounds" from "service_role";
revoke references on table "public"."account_threshold_shadow" from "anon";
revoke trigger on table "public"."account_threshold_shadow" from "anon";
revoke truncate on table "public"."account_threshold_shadow" from "anon";
revoke references on table "public"."account_threshold_shadow" from "authenticated";
revoke trigger on table "public"."account_threshold_shadow" from "authenticated";
revoke truncate on table "public"."account_threshold_shadow" from "authenticated";
revoke references on table "public"."account_threshold_shadow" from "service_role";
revoke trigger on table "public"."account_threshold_shadow" from "service_role";
revoke truncate on table "public"."account_threshold_shadow" from "service_role";
revoke references on table "public"."alert_gap_profiles" from "anon";
revoke trigger on table "public"."alert_gap_profiles" from "anon";
revoke truncate on table "public"."alert_gap_profiles" from "anon";
revoke references on table "public"."alert_gap_profiles" from "authenticated";
revoke trigger on table "public"."alert_gap_profiles" from "authenticated";
revoke truncate on table "public"."alert_gap_profiles" from "authenticated";
revoke references on table "public"."alert_gap_profiles" from "service_role";
revoke trigger on table "public"."alert_gap_profiles" from "service_role";
revoke truncate on table "public"."alert_gap_profiles" from "service_role";
revoke references on table "public"."alert_intervention_events" from "anon";
revoke trigger on table "public"."alert_intervention_events" from "anon";
revoke truncate on table "public"."alert_intervention_events" from "anon";
revoke references on table "public"."alert_intervention_events" from "authenticated";
revoke trigger on table "public"."alert_intervention_events" from "authenticated";
revoke truncate on table "public"."alert_intervention_events" from "authenticated";
revoke references on table "public"."alert_intervention_events" from "service_role";
revoke trigger on table "public"."alert_intervention_events" from "service_role";
revoke truncate on table "public"."alert_intervention_events" from "service_role";
revoke references on table "public"."alert_judgment_evaluations" from "anon";
revoke trigger on table "public"."alert_judgment_evaluations" from "anon";
revoke truncate on table "public"."alert_judgment_evaluations" from "anon";
revoke references on table "public"."alert_judgment_evaluations" from "authenticated";
revoke trigger on table "public"."alert_judgment_evaluations" from "authenticated";
revoke truncate on table "public"."alert_judgment_evaluations" from "authenticated";
revoke references on table "public"."alert_judgment_evaluations" from "service_role";
revoke trigger on table "public"."alert_judgment_evaluations" from "service_role";
revoke truncate on table "public"."alert_judgment_evaluations" from "service_role";
revoke references on table "public"."alert_judgment_shadow_decisions" from "anon";
revoke trigger on table "public"."alert_judgment_shadow_decisions" from "anon";
revoke truncate on table "public"."alert_judgment_shadow_decisions" from "anon";
revoke references on table "public"."alert_judgment_shadow_decisions" from "authenticated";
revoke trigger on table "public"."alert_judgment_shadow_decisions" from "authenticated";
revoke truncate on table "public"."alert_judgment_shadow_decisions" from "authenticated";
revoke references on table "public"."alert_judgment_shadow_decisions" from "service_role";
revoke trigger on table "public"."alert_judgment_shadow_decisions" from "service_role";
revoke truncate on table "public"."alert_judgment_shadow_decisions" from "service_role";
revoke references on table "public"."alert_judgment_subject_contexts" from "anon";
revoke trigger on table "public"."alert_judgment_subject_contexts" from "anon";
revoke truncate on table "public"."alert_judgment_subject_contexts" from "anon";
revoke references on table "public"."alert_judgment_subject_contexts" from "authenticated";
revoke trigger on table "public"."alert_judgment_subject_contexts" from "authenticated";
revoke truncate on table "public"."alert_judgment_subject_contexts" from "authenticated";
revoke references on table "public"."alert_judgment_subject_contexts" from "service_role";
revoke trigger on table "public"."alert_judgment_subject_contexts" from "service_role";
revoke truncate on table "public"."alert_judgment_subject_contexts" from "service_role";
revoke references on table "public"."alert_model_versions" from "anon";
revoke trigger on table "public"."alert_model_versions" from "anon";
revoke truncate on table "public"."alert_model_versions" from "anon";
revoke references on table "public"."alert_model_versions" from "authenticated";
revoke trigger on table "public"."alert_model_versions" from "authenticated";
revoke truncate on table "public"."alert_model_versions" from "authenticated";
revoke references on table "public"."alert_model_versions" from "service_role";
revoke trigger on table "public"."alert_model_versions" from "service_role";
revoke truncate on table "public"."alert_model_versions" from "service_role";
revoke references on table "public"."alert_observation_coverage_intervals" from "anon";
revoke trigger on table "public"."alert_observation_coverage_intervals" from "anon";
revoke truncate on table "public"."alert_observation_coverage_intervals" from "anon";
revoke references on table "public"."alert_observation_coverage_intervals" from "authenticated";
revoke trigger on table "public"."alert_observation_coverage_intervals" from "authenticated";
revoke truncate on table "public"."alert_observation_coverage_intervals" from "authenticated";
revoke references on table "public"."alert_observation_coverage_intervals" from "service_role";
revoke trigger on table "public"."alert_observation_coverage_intervals" from "service_role";
revoke truncate on table "public"."alert_observation_coverage_intervals" from "service_role";
revoke references on table "public"."alert_sleep_night_contexts" from "anon";
revoke trigger on table "public"."alert_sleep_night_contexts" from "anon";
revoke truncate on table "public"."alert_sleep_night_contexts" from "anon";
revoke references on table "public"."alert_sleep_night_contexts" from "authenticated";
revoke trigger on table "public"."alert_sleep_night_contexts" from "authenticated";
revoke truncate on table "public"."alert_sleep_night_contexts" from "authenticated";
revoke references on table "public"."alert_sleep_night_contexts" from "service_role";
revoke trigger on table "public"."alert_sleep_night_contexts" from "service_role";
revoke truncate on table "public"."alert_sleep_night_contexts" from "service_role";
revoke references on table "public"."routine_mode_cohort_generations" from "anon";
revoke trigger on table "public"."routine_mode_cohort_generations" from "anon";
revoke truncate on table "public"."routine_mode_cohort_generations" from "anon";
revoke references on table "public"."routine_mode_cohort_generations" from "authenticated";
revoke trigger on table "public"."routine_mode_cohort_generations" from "authenticated";
revoke truncate on table "public"."routine_mode_cohort_generations" from "authenticated";
revoke references on table "public"."routine_mode_cohort_generations" from "service_role";
revoke trigger on table "public"."routine_mode_cohort_generations" from "service_role";
revoke truncate on table "public"."routine_mode_cohort_generations" from "service_role";
revoke references on table "public"."routine_mode_cohort_invalidations" from "anon";
revoke trigger on table "public"."routine_mode_cohort_invalidations" from "anon";
revoke truncate on table "public"."routine_mode_cohort_invalidations" from "anon";
revoke references on table "public"."routine_mode_cohort_invalidations" from "authenticated";
revoke trigger on table "public"."routine_mode_cohort_invalidations" from "authenticated";
revoke truncate on table "public"."routine_mode_cohort_invalidations" from "authenticated";
revoke references on table "public"."routine_mode_cohort_invalidations" from "service_role";
revoke trigger on table "public"."routine_mode_cohort_invalidations" from "service_role";
revoke truncate on table "public"."routine_mode_cohort_invalidations" from "service_role";
revoke references on table "public"."routine_mode_cohort_priors" from "anon";
revoke trigger on table "public"."routine_mode_cohort_priors" from "anon";
revoke truncate on table "public"."routine_mode_cohort_priors" from "anon";
revoke references on table "public"."routine_mode_cohort_priors" from "authenticated";
revoke trigger on table "public"."routine_mode_cohort_priors" from "authenticated";
revoke truncate on table "public"."routine_mode_cohort_priors" from "authenticated";
revoke references on table "public"."routine_mode_cohort_priors" from "service_role";
revoke trigger on table "public"."routine_mode_cohort_priors" from "service_role";
revoke truncate on table "public"."routine_mode_cohort_priors" from "service_role";


-- 5. System configuration rows ----------------------------------------------
-- Also data rather than schema, and also invisible to a dump. These are not
-- production's accumulated state - they are what the original migrations
-- seeded so that a database works at all. Without the cohort generation rows,
-- the trigger private.invalidate_routine_mode_cohort raises a not-null
-- violation on the very first insert into public.profiles, so a fresh database
-- cannot register a single user. That was found by replaying this baseline into
-- an empty database and using it, which a schema diff does not do.
--
-- Counters start at zero on purpose. Production's generations have advanced to
-- 30 / 28 / 18 through real invalidations; a fresh database has no cohort
-- history to invalidate, so copying those numbers would assert a past that did
-- not happen.
--
-- public.alert_model_versions is deliberately not seeded: it is a registry
-- written when a model is activated, and the shadow dispatcher returns early
-- while runtime_config.version_id is null. public.app_admins and
-- public.app_versions are deliberately not seeded either - they are
-- environment-specific, and hardcoding a production admin's auth id into a
-- migration is exactly what broke local replay from June until 2026-08-08.

insert into public.routine_mode_cohort_generations (routine_mode, generation)
values ('regular_9to5', 0), ('semester_break', 0), ('shift_irregular', 0)
on conflict (routine_mode) do nothing;

insert into private.adaptive_alert_shadow_runtime_config (singleton)
values (true)
on conflict (singleton) do nothing;
