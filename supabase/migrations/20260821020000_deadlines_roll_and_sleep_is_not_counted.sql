-- The engine now does the two things the Routine screen has been promising.
--
-- The screen says two things that the grid engine did not do:
--
--   "these hours do not count towards the times above"  (the sleep sheet)
--   a countdown anchored on the last sign of life        (NextCheckin.tsx)
--
-- The grid did neither. Windows were laid out forward from a fixed epoch anchor,
-- so the deadline the subject was actually being judged against did not move when
-- they were seen, and every night burned through the threshold at wall-clock
-- speed. A person with a two-hour threshold and eight hours of sleep collected
-- four misses a night on a working phone. The chain guard then turned that into a
-- group notification, which is the single most expensive thing this product can
-- get wrong: a false alarm spends the responders' willingness to respond.
--
-- Two changes, both in how a window's end is computed:
--
--   rolling    a pending window ends `interval` after the LATEST evidence inside
--              it, not after its own start. Being seen pushes the deadline out,
--              which is exactly what the countdown on the screen shows.
--   awake      that `interval` is measured in awake time. Sleep is skipped, so
--              the threshold means the same thing at 22:00 and at 02:00.
--
-- With no evidence and no sleep window configured the new rules reproduce the old
-- grid exactly, so existing behaviour and its tests are preserved.
--
-- Row cost is lower, not higher. A window is only cut when a deadline actually
-- elapses, so a device reporting every five minutes keeps ONE pending window open
-- all day instead of closing one per report.


-- ---------------------------------------------------------------------------
-- Awake-time arithmetic
-- ---------------------------------------------------------------------------

-- Advance `_from` by `_minutes` of awake time, stepping over the subject's sleep
-- hours. Sleep is read from `public.user_settings`, which is what the Routine
-- screen writes through `set_sleep_window` — the contract's own sleep columns are
-- unused, because the daily contract always stores `sleep_policy = 'none'`.
--
-- No sleep window configured means no correction: the result is plain clock time.
CREATE FUNCTION private.passive_awake_deadline(
  _user_id uuid, _from timestamptz, _minutes integer
) RETURNS timestamptz LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE
  _start_local time; _end_local time; _tz text;
  _remaining interval; _cursor timestamptz;
  _day date; _span_start timestamptz; _span_end timestamptz;
  _next_start timestamptz; _next_end timestamptz;
  _offset integer; _guard integer := 0;
BEGIN
  IF _from IS NULL OR _minutes IS NULL OR _minutes <= 0 THEN RETURN NULL; END IF;

  SELECT settings.sleep_start_local, settings.sleep_end_local, coalesce(settings.timezone,'UTC')
    INTO _start_local, _end_local, _tz
    FROM public.user_settings AS settings WHERE settings.user_id = _user_id;

  IF _start_local IS NULL OR _end_local IS NULL OR _start_local = _end_local THEN
    RETURN _from + pg_catalog.make_interval(mins => _minutes);
  END IF;

  _remaining := pg_catalog.make_interval(mins => _minutes);
  _cursor := _from;

  LOOP
    _guard := _guard + 1;
    -- A pathological window (23 hours of "sleep") would need one pass per day.
    -- Giving up returns a LATER deadline than the truth, which errs towards
    -- silence rather than towards a false alarm.
    EXIT WHEN _guard > 120;

    -- The earliest sleep span that has not finished by `_cursor`. Three candidate
    -- days cover an overnight span that started before `_cursor`.
    _next_start := NULL; _next_end := NULL;
    _day := (_cursor AT TIME ZONE _tz)::date - 1;
    FOR _offset IN 0..2 LOOP
      _span_start := ((_day + _offset) + _start_local) AT TIME ZONE _tz;
      _span_end := CASE WHEN _end_local > _start_local
        THEN ((_day + _offset) + _end_local) AT TIME ZONE _tz
        ELSE ((_day + _offset + 1) + _end_local) AT TIME ZONE _tz END;
      IF _span_end > _cursor AND (_next_start IS NULL OR _span_start < _next_start) THEN
        _next_start := _span_start; _next_end := _span_end;
      END IF;
    END LOOP;

    -- Nothing left to skip, or the deadline lands before sleep begins.
    IF _next_start IS NULL OR _next_start >= _cursor + _remaining THEN
      RETURN _cursor + _remaining;
    END IF;

    -- Spend the awake stretch up to bedtime, then jump the night at no cost.
    _remaining := _remaining - greatest(interval '0', _next_start - _cursor);
    _cursor := _next_end;
  END LOOP;

  RETURN _cursor + _remaining;
END;
$$;

COMMENT ON FUNCTION private.passive_awake_deadline(uuid,timestamptz,integer) IS
  'The instant at which _minutes of AWAKE time have elapsed after _from, skipping '
  'the sleep hours in public.user_settings. Falls back to clock time when unset.';


-- ---------------------------------------------------------------------------
-- The miss chain
-- ---------------------------------------------------------------------------

-- How many deadlines have elapsed since the last sign of life.
--
-- The old query counted missed windows with no `checked_in` or `superseded`
-- window after them. That worked only because the grid closed a window on the
-- first evidence inside it. A rolling window is not closed by evidence — it is
-- extended by it — so the chain has to be anchored on the evidence itself.
--
-- The `checked_in`/`superseded` terms are kept so that a corrected or reset
-- window still clears everything before it.
CREATE FUNCTION private.passive_miss_chain(_epoch_id uuid)
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
  WITH boundary AS (
    SELECT greatest(
      (SELECT epoch.started_at FROM public.passive_monitoring_epochs AS epoch WHERE epoch.id = _epoch_id),
      (SELECT max(event.observed_at) FROM private.passive_evidence_events AS event WHERE event.epoch_id = _epoch_id),
      (SELECT max(closed.window_end) FROM public.passive_checkin_windows AS closed
        WHERE closed.epoch_id = _epoch_id AND closed.outcome IN ('checked_in','superseded'))
    ) AS at
  )
  SELECT count(*) FROM public.passive_checkin_windows AS missed, boundary
  WHERE missed.epoch_id = _epoch_id AND missed.outcome = 'missed'
    AND missed.window_start >= boundary.at
$$;

COMMENT ON FUNCTION private.passive_miss_chain(uuid) IS
  'Consecutive elapsed deadlines since the latest evidence, closed window or epoch start.';


-- ---------------------------------------------------------------------------
-- Why a deadline elapsed
-- ---------------------------------------------------------------------------

-- An elapsed deadline is not one fact, it is three, and they call for different
-- responses from whoever is told about it:
--
--   silent                 the collectors were working and reported nothing.
--                          This is the only kind that is evidence about a person.
--   device_unreachable     no collector made contact at all during the window.
--                          A flat battery looks exactly like this.
--   collection_restricted  a collector is bound but is not permitted or able to
--                          observe. The silence proves nothing whatsoever.
--
-- Recording this at the moment the window closes is the only chance to get it
-- right: binding health is live state and will have moved on by the time anyone
-- reads the notification.
ALTER TABLE public.passive_checkin_windows
  ADD COLUMN IF NOT EXISTS miss_kind text;
ALTER TABLE public.passive_checkin_windows
  ADD CONSTRAINT passive_checkin_windows_miss_kind_check
  CHECK (miss_kind IS NULL OR miss_kind IN ('silent','device_unreachable','collection_restricted'));

COMMENT ON COLUMN public.passive_checkin_windows.miss_kind IS
  'Why this window was missed, decided when it closed. NULL unless outcome = missed.';

CREATE FUNCTION private.passive_miss_kind(
  _user_id uuid, _window_start timestamptz, _window_end timestamptz
) RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
  -- Nothing bound, or something bound that is not allowed to look.
  IF NOT EXISTS (
    SELECT 1 FROM private.passive_collector_bindings AS binding
    WHERE binding.user_id = _user_id AND binding.revoked_at IS NULL
  ) OR EXISTS (
    SELECT 1 FROM private.passive_collector_bindings AS binding
    WHERE binding.user_id = _user_id AND binding.revoked_at IS NULL
      AND (binding.permission_state IN ('denied','revoked')
        OR binding.capability_state IN ('unsupported','degraded'))
  ) THEN
    RETURN 'collection_restricted';
  END IF;

  -- Bound and permitted, but out of touch by its own standard.
  --
  -- The test is not "did it ever speak inside this window". A phone that reported
  -- once at the start and then died would pass that, and the group would be told
  -- the person was quiet when the truth is the battery went flat. Each surface
  -- declares in the registry how late a healthy report of its own may arrive; a
  -- collector that has not been in touch within its own allowance of the deadline
  -- is not a working collector.
  IF NOT EXISTS (
    SELECT 1 FROM private.passive_collector_bindings AS binding
    JOIN private.passive_surface_registry AS registry USING(surface_type)
    WHERE binding.user_id = _user_id AND binding.revoked_at IS NULL
      AND binding.last_contact_at >= greatest(
        _window_end - registry.arrival_allowance, _window_start)
  ) THEN
    RETURN 'device_unreachable';
  END IF;

  RETURN 'silent';
END;
$$;

COMMENT ON FUNCTION private.passive_miss_kind(uuid,timestamptz,timestamptz) IS
  'Classifies an elapsed deadline as silent, device_unreachable or collection_restricted.';


-- ---------------------------------------------------------------------------
-- Alert authority
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.maybe_open_passive_checkin_alert(
  _user_id uuid, _epoch_id uuid, _contract_id uuid, _now timestamptz
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _account public.passive_checkin_accounts%ROWTYPE;
  _contract public.passive_checkin_contract_versions%ROWTYPE;
  _chain bigint; _alert_id uuid; _grace interval;
BEGIN
  SELECT * INTO _account FROM public.passive_checkin_accounts WHERE user_id=_user_id;
  SELECT * INTO STRICT _contract FROM public.passive_checkin_contract_versions WHERE id=_contract_id;
  _chain := private.passive_miss_chain(_epoch_id);
  IF _account.engine_mode<>'passive_checkin' OR _account.kill_switch_active
     OR _chain<_contract.consecutive_misses
     OR private.passive_sleep_relaxed(_user_id,_contract_id,_now)
     OR EXISTS(SELECT 1 FROM public.alerts WHERE user_id=_user_id AND status='open') THEN
    RETURN NULL;
  END IF;
  _grace := pg_catalog.make_interval(
    mins => coalesce(_contract.response_grace_minutes, 30));
  INSERT INTO public.alerts(user_id,cause,stage,stage_entered_at,next_deadline,requires_explicit_unlock)
  VALUES(_user_id,'silence','self',_now,_now+_grace,true)
  RETURNING id INTO _alert_id;
  INSERT INTO public.alert_events(alert_id,kind,note)
  VALUES(_alert_id,'raised','passive_checkin_consecutive_misses');
  INSERT INTO private.passive_alert_causal_windows(alert_id,window_id,ordinal)
  SELECT _alert_id,id,(row_number() OVER(ORDER BY ordinal)-1)::integer
  FROM (SELECT id,ordinal FROM public.passive_checkin_windows
    WHERE epoch_id=_epoch_id AND outcome='missed'
    ORDER BY ordinal DESC LIMIT _contract.consecutive_misses) causal
  ORDER BY ordinal;
  RETURN _alert_id;
END;
$$;


-- ---------------------------------------------------------------------------
-- The evaluator
-- ---------------------------------------------------------------------------

-- One pending window exists at a time. Each pass recomputes its end from the
-- latest evidence inside it and, if that end plus the collector's arrival
-- allowance is already past, closes it and opens the next one.
--
--   evidence inside  -> `checked_in`, cut at that evidence, next window starts there
--   nothing inside   -> `missed`, next window starts at the elapsed deadline
--
-- Cutting at the evidence rather than at the scheduled end is what makes the
-- chain mean "N thresholds since you were last seen" instead of "N thresholds
-- since some arbitrary grid boundary".
--
-- The invariant this function maintains is that an active epoch has EXACTLY ONE
-- live window. Opening the next one is therefore done in a single place, from the
-- highest window the epoch already has, rather than from whichever window was just
-- closed. The grid engine left accounts with several pending windows at once —
-- ingest could open one ahead of the evaluator — and an epoch carrying a window
-- whose start collides with the next one the chain wants would raise a unique
-- violation on every pass, permanently, without ever being judged again. A
-- protection that fails must not fail silently.
CREATE OR REPLACE FUNCTION private.process_passive_checkin_subject(_user_id uuid, _now timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' SET TimeZone TO 'UTC' AS $$
DECLARE
  _account public.passive_checkin_accounts%ROWTYPE;
  _contract public.passive_checkin_contract_versions%ROWTYPE;
  _epoch public.passive_monitoring_epochs%ROWTYPE;
  _window public.passive_checkin_windows%ROWTYPE;
  _last_evidence timestamptz;
  _evidence_id uuid;
  _anchor timestamptz;
  _end timestamptz;
  _deadline timestamptz;
  _next_start timestamptz;
  _last_ordinal bigint;
  _chain bigint;
  _alert_id uuid;
  _guard integer := 0;
BEGIN
  IF _now IS NULL THEN RAISE EXCEPTION 'evaluation time is required'; END IF;
  SELECT * INTO _account FROM public.passive_checkin_accounts
  WHERE user_id=_user_id FOR UPDATE;
  IF NOT FOUND OR _account.engine_mode NOT IN ('shadow','passive_checkin')
     OR _account.active_epoch_id IS NULL THEN
    RETURN jsonb_build_object('status','inactive');
  END IF;
  SELECT * INTO STRICT _contract FROM public.passive_checkin_contract_versions
  WHERE id=_account.active_contract_version_id AND user_id=_user_id;
  SELECT * INTO STRICT _epoch FROM public.passive_monitoring_epochs
  WHERE id=_account.active_epoch_id AND user_id=_user_id AND ended_at IS NULL;

  LOOP
    _guard := _guard + 1;
    -- A subject the job has not seen for months is caught up over several passes
    -- rather than in one transaction that holds the account row for minutes.
    EXIT WHEN _guard > 500;

    SELECT * INTO _window FROM public.passive_checkin_windows
    WHERE epoch_id=_epoch.id AND outcome='pending' ORDER BY ordinal LIMIT 1 FOR UPDATE;

    IF NOT FOUND THEN
      -- No live window: open one after the last window the epoch has, or at the
      -- epoch anchor for a fresh epoch. This is the ONLY place a window is opened.
      SELECT tail.ordinal, greatest(tail.window_end,_epoch.started_at)
      INTO _last_ordinal, _next_start
      FROM public.passive_checkin_windows AS tail
      WHERE tail.epoch_id=_epoch.id ORDER BY tail.ordinal DESC LIMIT 1;
      IF _last_ordinal IS NULL THEN
        _last_ordinal := -1; _next_start := _epoch.started_at;
      END IF;
      _end := private.passive_awake_deadline(_user_id,_next_start,_contract.interval_minutes);
      -- Bare DO NOTHING: the ordinal and the start each have their own unique
      -- index, and a legacy epoch can collide on either. Losing the race is
      -- survivable; raising here would strand the subject unjudged forever.
      INSERT INTO public.passive_checkin_windows(
        user_id,epoch_id,contract_version_id,ordinal,window_start,window_end,arrival_deadline
      ) VALUES (_user_id,_epoch.id,_contract.id,_last_ordinal+1,_next_start,_end,
        _end+private.passive_window_arrival_allowance(_user_id,_next_start,_end))
      ON CONFLICT DO NOTHING;
      EXIT WHEN NOT FOUND;
      CONTINUE;
    END IF;

    -- Strictly after the start: evidence exactly on the boundary is what opened
    -- this window, and re-anchoring on it would never make progress.
    SELECT event.observed_at, event.id INTO _last_evidence, _evidence_id
    FROM private.passive_evidence_events AS event
    WHERE event.user_id=_user_id AND event.epoch_id=_epoch.id
      AND event.observed_at > _window.window_start
    ORDER BY event.observed_at DESC, event.id DESC LIMIT 1;

    _anchor := coalesce(_last_evidence,_window.window_start);
    _end := private.passive_awake_deadline(_user_id,_anchor,_contract.interval_minutes);
    _deadline := _end+private.passive_window_arrival_allowance(_user_id,_window.window_start,_end);

    IF _deadline > _now THEN
      UPDATE public.passive_checkin_windows
      SET window_end=_end, arrival_deadline=_deadline
      WHERE id=_window.id AND outcome='pending';
      EXIT;
    END IF;

    IF _last_evidence IS NOT NULL THEN
      -- Cut the window at the report. The next threshold is measured from there.
      UPDATE public.passive_checkin_windows
      SET outcome='checked_in', finalized_at=_now, causal_evidence_id=_evidence_id,
          window_end=_last_evidence,
          arrival_deadline=greatest(_window.arrival_deadline,_last_evidence)
      WHERE id=_window.id AND outcome='pending';
    ELSE
      UPDATE public.passive_checkin_windows
      SET outcome='missed', finalized_at=_now, window_end=_end, arrival_deadline=_deadline,
          miss_kind=private.passive_miss_kind(_user_id,_window.window_start,_end)
      WHERE id=_window.id AND outcome='pending';
      _alert_id:=coalesce(
        _alert_id,
        private.maybe_open_passive_checkin_alert(_user_id,_epoch.id,_contract.id,_now)
      );
    END IF;
    -- The next window is opened by the top of this loop, from the epoch's highest
    -- window, so that one rule decides where the chain continues.
  END LOOP;

  _chain := private.passive_miss_chain(_epoch.id);

  IF _account.engine_mode='passive_checkin' AND NOT _account.kill_switch_active
     AND _chain>=_contract.consecutive_misses THEN
    _alert_id:=coalesce(_alert_id,
      private.maybe_open_passive_checkin_alert(_user_id,_epoch.id,_contract.id,_now));
  END IF;
  RETURN jsonb_build_object('status','processed','consecutive_misses',_chain,'alert_id',_alert_id);
END;
$$;

COMMENT ON FUNCTION private.process_passive_checkin_subject(uuid,timestamptz) IS
  'ADR-0042 deterministic per-subject evaluator, rolling and awake-time. Reads '
  'evidence, contract and sleep hours, never collector health.';


-- ---------------------------------------------------------------------------
-- Ingest
-- ---------------------------------------------------------------------------

-- Evidence no longer computes a grid ordinal. A report belongs to the window the
-- evaluator is currently judging; only a report older than that window's start is
-- matched against history.
--
-- It also stops closing the live window. Under the grid the first report of a
-- window ended it; under a rolling deadline the report EXTENDS the window, and
-- only the evaluator may finalize. A report that lands inside an already-missed
-- window is still a late positive and still corrects it.
CREATE OR REPLACE FUNCTION private.record_passive_evidence(
  _subject_id uuid, _binding_id uuid, _credential text, _authenticated_path boolean,
  _event_id uuid, _sequence bigint, _observed_at timestamptz, _evidence_class text,
  _qualification_policy_version text, _correlation_id text, _qualification_facts jsonb,
  _query_started_at timestamptz, _query_ended_at timestamptz, _query_succeeded boolean
)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE
  _binding private.passive_collector_bindings%ROWTYPE;
  _registry private.passive_surface_registry%ROWTYPE;
  _existing private.passive_evidence_events%ROWTYPE;
  _now timestamptz := clock_timestamp();
  _payload_sha text;
  _epoch_id uuid;
  _contract_id uuid;
  _started_at timestamptz;
  _interval_minutes integer;
  _window_id uuid;
  _window_start timestamptz;
  _window_end timestamptz;
  _event_row_id uuid;
BEGIN
  SELECT * INTO _binding FROM private.passive_collector_bindings WHERE id = _binding_id FOR UPDATE;
  IF NOT FOUND OR _binding.user_id <> _subject_id THEN RETURN 'unregistered_binding'; END IF;
  IF _binding.revoked_at IS NOT NULL THEN
    INSERT INTO private.passive_evidence_incidents(user_id,binding_id,event_id,collector_sequence,reason)
    VALUES (_subject_id,_binding_id,_event_id,_sequence,'revoked_binding');
    RETURN 'revoked';
  END IF;
  IF NOT _authenticated_path AND (
    _credential IS NULL OR encode(extensions.digest(_credential, 'sha256'), 'hex') <> _binding.credential_sha256
  ) THEN
    INSERT INTO private.passive_evidence_incidents(user_id,binding_id,event_id,collector_sequence,reason)
    VALUES (_subject_id,_binding_id,_event_id,_sequence,'credential_mismatch');
    RETURN 'credential_mismatch';
  END IF;
  SELECT * INTO STRICT _registry FROM private.passive_surface_registry WHERE surface_type = _binding.surface_type;
  IF _authenticated_path AND _binding.surface_type <> 'pwa_browser' THEN RETURN 'invalid'; END IF;
  IF _qualification_policy_version IS DISTINCT FROM 'passive-qualification-v1'
     OR NOT (_evidence_class = ANY(_registry.allowed_evidence_classes))
     OR _sequence < 0 OR _observed_at IS NULL
     OR _observed_at > _now + interval '5 minutes'
     OR _observed_at < _now - interval '7 days'
     OR jsonb_typeof(coalesce(_qualification_facts, '{}'::jsonb)) <> 'object'
     OR (_correlation_id IS NOT NULL AND length(_correlation_id) NOT BETWEEN 1 AND 128)
     OR EXISTS (
       SELECT 1 FROM jsonb_object_keys(coalesce(_qualification_facts,'{}'::jsonb)) AS key
       WHERE key NOT IN (
         'interaction','steps_positive','floors_positive','pedestrian','automotive',
         'prior_power_state','new_power_state','stable_for_ms'
       )
     )
     OR ((_query_started_at IS NULL) <> (_query_ended_at IS NULL))
     OR (_query_started_at IS NOT NULL AND _query_started_at > _query_ended_at)
     THEN RETURN 'invalid'; END IF;

  IF _evidence_class = 'direct_device_use' AND coalesce((_qualification_facts->>'interaction')::boolean, false) IS NOT TRUE
     OR _evidence_class = 'personal_device_motion' AND NOT (
       coalesce((_qualification_facts->>'pedestrian')::boolean, false)
       AND NOT coalesce((_qualification_facts->>'automotive')::boolean, false)
       AND (coalesce((_qualification_facts->>'steps_positive')::boolean, false)
            OR coalesce((_qualification_facts->>'floors_positive')::boolean, false))
     )
     OR _evidence_class = 'power_transition' AND NOT (
       _qualification_facts->>'prior_power_state' IN ('charging','not_charging')
       AND _qualification_facts->>'new_power_state' IN ('charging','not_charging')
       AND _qualification_facts->>'prior_power_state' <> _qualification_facts->>'new_power_state'
       AND coalesce((_qualification_facts->>'stable_for_ms')::integer, 0) >= 5000
     ) THEN RETURN 'invalid'; END IF;

  IF _observed_at < _now - interval '5 minutes' AND NOT (
    _registry.supports_history AND _query_succeeded
    AND _query_started_at IS NOT NULL AND _query_ended_at IS NOT NULL
    AND _query_started_at <= _observed_at AND _observed_at <= _query_ended_at
  ) THEN RETURN 'invalid'; END IF;

  _payload_sha := private.passive_payload_sha256(
    _binding_id,_event_id,_sequence,_observed_at,_evidence_class,
    _qualification_policy_version,_correlation_id,coalesce(_qualification_facts,'{}'::jsonb),
    _query_started_at,_query_ended_at,_query_succeeded
  );
  SELECT * INTO _existing FROM private.passive_evidence_events WHERE event_id = _event_id;
  IF FOUND THEN
    IF _existing.binding_id = _binding_id AND _existing.payload_sha256 = _payload_sha THEN
      UPDATE private.passive_collector_bindings SET last_contact_at = _now WHERE id = _binding_id;
      RETURN 'duplicate';
    END IF;
    INSERT INTO private.passive_evidence_incidents(
      user_id,binding_id,event_id,collector_sequence,reason,incoming_payload_sha256,existing_payload_sha256
    ) VALUES (_subject_id,_binding_id,_event_id,_sequence,'event_conflict',_payload_sha,_existing.payload_sha256);
    RETURN 'conflict';
  END IF;
  SELECT * INTO _existing FROM private.passive_evidence_events
  WHERE binding_id = _binding_id AND collector_sequence = _sequence;
  IF FOUND THEN
    INSERT INTO private.passive_evidence_incidents(
      user_id,binding_id,event_id,collector_sequence,reason,incoming_payload_sha256,existing_payload_sha256
    ) VALUES (_subject_id,_binding_id,_event_id,_sequence,'sequence_conflict',_payload_sha,_existing.payload_sha256);
    RETURN 'conflict';
  END IF;

  SELECT epoch.id, epoch.contract_version_id, epoch.started_at, contract.interval_minutes
  INTO _epoch_id, _contract_id, _started_at, _interval_minutes
  FROM public.passive_monitoring_epochs AS epoch
  JOIN public.passive_checkin_contract_versions AS contract ON contract.id = epoch.contract_version_id
  WHERE epoch.user_id = _subject_id AND epoch.ended_at IS NULL;
  IF _epoch_id IS NULL OR _observed_at < _started_at THEN RETURN 'outside_epoch'; END IF;

  -- The window the evaluator is currently judging. Anything at or after its start
  -- belongs to it, including a report that arrives after its stale end: the end is
  -- not a boundary any more, it is a deadline that this report is about to move.
  --
  -- Ingest never creates a window past the first one. Only the evaluator advances
  -- the chain, so a collector cannot lay down a window that overlaps the live one.
  SELECT live.id, live.window_start INTO _window_id, _window_start
  FROM public.passive_checkin_windows AS live
  WHERE live.epoch_id = _epoch_id AND live.outcome = 'pending'
  ORDER BY live.ordinal LIMIT 1;

  IF _window_id IS NULL OR _observed_at < _window_start THEN
    -- History: the window this report actually falls inside.
    SELECT past.id INTO _window_id
    FROM public.passive_checkin_windows AS past
    WHERE past.epoch_id = _epoch_id
      AND past.window_start <= _observed_at AND past.window_end > _observed_at
    ORDER BY past.ordinal DESC LIMIT 1;
  END IF;

  IF _window_id IS NULL THEN
    -- An epoch whose first window the evaluator has not opened yet.
    _window_end := private.passive_awake_deadline(_subject_id,_started_at,_interval_minutes);
    INSERT INTO public.passive_checkin_windows(
      user_id,epoch_id,contract_version_id,ordinal,window_start,window_end,arrival_deadline
    ) VALUES (
      _subject_id,_epoch_id,_contract_id,0,_started_at,_window_end,
      _window_end + private.passive_arrival_allowance(_subject_id)
    ) ON CONFLICT (epoch_id,ordinal) DO NOTHING;
    SELECT first_window.id INTO _window_id FROM public.passive_checkin_windows AS first_window
    WHERE first_window.epoch_id = _epoch_id AND first_window.ordinal = 0;
    IF _window_id IS NULL THEN RETURN 'outside_epoch'; END IF;
  END IF;

  PERFORM 1 FROM public.passive_checkin_windows WHERE id = _window_id FOR UPDATE;

  INSERT INTO private.passive_evidence_events(
    user_id,binding_id,epoch_id,window_id,event_id,collector_sequence,collector_time_epoch,
    observed_at,received_at,evidence_class,qualification_policy_version,collector_contract,
    client_version,correlation_id,qualification_facts,query_started_at,query_ended_at,
    query_succeeded,payload_sha256
  ) VALUES (
    _subject_id,_binding_id,_epoch_id,_window_id,_event_id,_sequence,_binding.time_epoch,
    _observed_at,_now,_evidence_class,_qualification_policy_version,_binding.collector_contract,
    _binding.client_version,_correlation_id,coalesce(_qualification_facts,'{}'::jsonb),
    _query_started_at,_query_ended_at,_query_succeeded,_payload_sha
  ) RETURNING id INTO _event_row_id;

  -- Late positive only. A pending window is extended by the evaluator, not closed
  -- here, so that further reports keep pushing the same deadline out.
  UPDATE public.passive_checkin_windows
  SET outcome = 'checked_in', causal_evidence_id = _event_row_id, finalized_at = _now
  WHERE id = _window_id AND outcome = 'missed';

  UPDATE private.passive_collector_bindings
  SET sequence_cursor = greatest(sequence_cursor,_sequence), last_contact_at = _now,
      last_evidence_at = greatest(coalesce(last_evidence_at,_observed_at),_observed_at)
  WHERE id = _binding_id;
  RETURN 'inserted';
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
  RETURN 'invalid';
END;
$$;


-- ---------------------------------------------------------------------------
-- Epoch restart after an explicit answer
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.restart_passive_epoch_after_resolution()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE
  _account public.passive_checkin_accounts%ROWTYPE;
  _at timestamptz;
  _epoch_id uuid;
  _contract public.passive_checkin_contract_versions%ROWTYPE;
  _finish timestamptz;
BEGIN
  IF OLD.status<>'open' OR NEW.status<>'resolved' OR NEW.resolved_by IS NULL
     OR NOT EXISTS(SELECT 1 FROM private.passive_alert_causal_windows WHERE alert_id=NEW.id) THEN
    RETURN NEW;
  END IF;
  _at:=coalesce(NEW.resolved_at,clock_timestamp());
  SELECT * INTO _account FROM public.passive_checkin_accounts WHERE user_id=NEW.user_id FOR UPDATE;
  IF NOT FOUND OR _account.active_contract_version_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO STRICT _contract FROM public.passive_checkin_contract_versions
  WHERE id=_account.active_contract_version_id;
  UPDATE public.passive_checkin_windows SET outcome='superseded',finalized_at=_at,
    superseded_reason='explicit_resolution'
  WHERE user_id=NEW.user_id AND outcome='pending';
  UPDATE public.passive_monitoring_epochs SET ended_at=_at,end_reason='explicit_resolution'
  WHERE user_id=NEW.user_id AND ended_at IS NULL;
  INSERT INTO public.passive_monitoring_epochs(user_id,contract_version_id,started_at,start_reason)
  VALUES(NEW.user_id,_contract.id,_at,'explicit_resolution') RETURNING id INTO _epoch_id;
  -- Answering by hand is a sign of life, so the fresh window is measured in awake
  -- time from the answer, exactly like one started by a passive report.
  _finish:=private.passive_awake_deadline(NEW.user_id,_at,_contract.interval_minutes);
  INSERT INTO public.passive_checkin_windows(
    user_id,epoch_id,contract_version_id,ordinal,window_start,window_end,arrival_deadline
  ) VALUES(NEW.user_id,_epoch_id,_contract.id,0,_at,_finish,
    _finish+private.passive_window_arrival_allowance(NEW.user_id,_at,_finish));
  UPDATE public.passive_checkin_accounts SET active_epoch_id=_epoch_id,updated_at=_at
  WHERE user_id=NEW.user_id;
  RETURN NEW;
END;
$$;


-- ---------------------------------------------------------------------------
-- What the subject is shown
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.my_passive_window_state()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _uid uuid:=auth.uid(); _account public.passive_checkin_accounts%ROWTYPE;
  _contract public.passive_checkin_contract_versions%ROWTYPE; _window record;
  _chain bigint:=0; _alert record;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='28000'; END IF;
  SELECT * INTO _account FROM public.passive_checkin_accounts WHERE user_id=_uid;
  IF NOT FOUND THEN RETURN jsonb_build_object('engine_mode','legacy','consecutive_misses',0,
    'current_window',NULL,'open_alert',NULL,'sleep_deferred',false); END IF;
  SELECT * INTO _contract FROM public.passive_checkin_contract_versions WHERE id=_account.active_contract_version_id;
  SELECT * INTO _window FROM public.passive_checkin_windows WHERE epoch_id=_account.active_epoch_id
  ORDER BY ordinal DESC LIMIT 1;
  _chain := coalesce(private.passive_miss_chain(_account.active_epoch_id),0);
  SELECT a.id,a.stage,a.opened_at INTO _alert FROM public.alerts a
  WHERE a.user_id=_uid AND a.status='open'
    AND EXISTS(SELECT 1 FROM private.passive_alert_causal_windows c WHERE c.alert_id=a.id)
  LIMIT 1;
  RETURN jsonb_build_object(
    'engine_mode',_account.engine_mode,'consecutive_misses',_chain,
    'current_window',CASE WHEN _window.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id',_window.id,'ordinal',_window.ordinal,'window_start',_window.window_start,
      'window_end',_window.window_end,'arrival_deadline',_window.arrival_deadline,'outcome',_window.outcome) END,
    'open_alert',CASE WHEN _alert.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id',_alert.id,'stage',_alert.stage,'opened_at',_alert.opened_at) END,
    'sleep_deferred',_account.engine_mode='passive_checkin' AND _alert.id IS NULL
      AND _chain>=coalesce(_contract.consecutive_misses,2147483647)
      AND private.passive_sleep_relaxed(_uid,_account.active_contract_version_id,clock_timestamp())
  );
END;
$$;


-- The screen was computing its own countdown as `last activity + threshold`. That
-- is right about the anchor and wrong about the clock: it does not know the
-- subject's sleep hours, so at 03:00 it showed a deadline the engine was never
-- going to act on. Return the deadline the engine will actually use.
CREATE OR REPLACE FUNCTION public.my_daily_checkin()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _uid uuid := auth.uid();
  _account public.passive_checkin_accounts%ROWTYPE;
  _contract public.passive_checkin_contract_versions%ROWTYPE;
  _epoch public.passive_monitoring_epochs%ROWTYPE;
  _pending public.passive_checkin_windows%ROWTYPE;
  _ask_minute integer;
  _anchor timestamptz;
  _deadline timestamptz;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='28000'; END IF;
  SELECT * INTO _account FROM public.passive_checkin_accounts WHERE user_id=_uid;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO _contract FROM public.passive_checkin_contract_versions
  WHERE id=_account.active_contract_version_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO _epoch FROM public.passive_monitoring_epochs WHERE id=_account.active_epoch_id;

  _ask_minute := CASE WHEN _epoch.started_at IS NULL OR _contract.timezone IS NULL THEN NULL ELSE
    (extract(hour FROM (_epoch.started_at AT TIME ZONE _contract.timezone))*60
      + extract(minute FROM (_epoch.started_at AT TIME ZONE _contract.timezone)))::integer END;

  SELECT * INTO _pending FROM public.passive_checkin_windows
  WHERE epoch_id=_epoch.id AND outcome='pending' ORDER BY ordinal LIMIT 1;
  IF FOUND THEN
    _anchor := greatest(_pending.window_start, (
      SELECT max(event.observed_at) FROM private.passive_evidence_events AS event
      WHERE event.user_id=_uid AND event.epoch_id=_epoch.id
        AND event.observed_at > _pending.window_start));
    _deadline := private.passive_awake_deadline(_uid,_anchor,_contract.interval_minutes);
  END IF;

  RETURN jsonb_build_object(
    'engine_mode', _account.engine_mode,
    'kill_switch_active', _account.kill_switch_active,
    'version_number', _contract.version_number,
    'ask_at_local_minute', _ask_minute,
    'quiet_period_minutes', _contract.interval_minutes,
    'consecutive_misses', _contract.consecutive_misses,
    'response_grace_minutes', coalesce(_contract.response_grace_minutes, 30),
    'timezone', _contract.timezone,
    'effective_at', _contract.effective_at,
    'next_question_at', _deadline,
    'next_deadline_at', _deadline,
    'missed_so_far', coalesce(private.passive_miss_chain(_epoch.id),0),
    -- Why the last deadline elapsed. "Nobody could look" and "you were quiet"
    -- read the same on screen unless the screen is told which one happened.
    'last_miss_kind', (
      SELECT recent.miss_kind FROM public.passive_checkin_windows AS recent
      WHERE recent.epoch_id=_epoch.id AND recent.outcome='missed'
      ORDER BY recent.ordinal DESC LIMIT 1),
    'last_activity_at', (
      SELECT max(observed_at) FROM private.passive_evidence_events WHERE user_id=_uid),
    'days_observed', (
      SELECT count(*) FROM public.passive_checkin_windows
      WHERE epoch_id=_epoch.id AND outcome IN ('checked_in','missed')),
    'days_asked', (
      SELECT count(*) FROM public.passive_checkin_windows
      WHERE epoch_id=_epoch.id AND outcome='missed'));
END;
$$;


REVOKE ALL ON FUNCTION private.passive_awake_deadline(uuid,timestamptz,integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.passive_miss_chain(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.passive_miss_kind(uuid,timestamptz,timestamptz) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.my_daily_checkin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_daily_checkin() TO authenticated;
REVOKE ALL ON FUNCTION public.my_passive_window_state() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.my_passive_window_state() TO authenticated;
