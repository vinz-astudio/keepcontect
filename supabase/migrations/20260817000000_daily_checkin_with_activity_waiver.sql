-- Daily check-in with an activity waiver.
--
-- Product change, human decision 2026-08-17: KC stops trying to replace the
-- check-in with passive detection, and instead uses passive detection to WAIVE
-- the check-in. "Ask me once a day, unless I have obviously been using my
-- phone." That is the shape the market already uses and users already know.
--
-- The decisive reason is what happens when collection breaks. Under the window
-- grid a dead collector produced more and more questions, because absence of
-- evidence accumulated into a miss chain. Under the waiver a dead collector
-- produces exactly one question a day — the manual-check-in baseline — and
-- never more. KC therefore cannot be more annoying than the product it exists
-- to improve on, which is the acceptance criterion the design is gated against.
--
-- Almost nothing new is needed. The daily check-in IS one window: it runs from
-- the moment activity stops counting to the moment KC asks. So:
--
--   quiet period   -> interval_minutes  (the window length)
--   ask time       -> the epoch anchor  (where windows land in the local day)
--   miss           -> consecutive_misses = 1
--   the question   -> the existing self-stage alert
--   answer window  -> response_grace_minutes (new)
--
-- The existing evidence ingest, window generation and escalation funnel are
-- unchanged. Two old constraints written for the grid model had to be relaxed.

-- The grid capped a window at six hours because it sampled a day into pieces.
-- A waiver window is a whole quiet period, so it needs to reach a day or two.
ALTER TABLE public.passive_checkin_contract_versions
  DROP CONSTRAINT passive_checkin_contract_versions_interval_minutes_check;
ALTER TABLE public.passive_checkin_contract_versions
  ADD CONSTRAINT passive_checkin_contract_versions_interval_minutes_check
  CHECK (interval_minutes >= 20 AND interval_minutes <= 2880);

-- The grid only needed a timezone to place a sleep window. The waiver always
-- needs one, because "ask me at 09:00" is meaningless without it. The old
-- constraint actively forbade a timezone when sleep was off.
ALTER TABLE public.passive_checkin_contract_versions
  DROP CONSTRAINT passive_checkin_contract_versions_sleep_choice_check;
ALTER TABLE public.passive_checkin_contract_versions
  ADD CONSTRAINT passive_checkin_contract_versions_sleep_choice_check
  CHECK (
    (sleep_policy = 'configured'
      AND sleep_start_local IS NOT NULL AND sleep_end_local IS NOT NULL
      AND sleep_start_local <> sleep_end_local
      AND timezone IS NOT NULL AND length(btrim(timezone)) > 0)
    OR
    (sleep_policy = 'none'
      AND sleep_start_local IS NULL AND sleep_end_local IS NULL)
  );

-- How long the subject has to answer the daily question before the existing
-- funnel moves on. The grid model hardcoded thirty minutes inside the alert
-- opener, which is far too short for a question that means "are you up yet".
ALTER TABLE public.passive_checkin_contract_versions
  ADD COLUMN IF NOT EXISTS response_grace_minutes integer;
ALTER TABLE public.passive_checkin_contract_versions
  ADD CONSTRAINT passive_checkin_contract_versions_response_grace_check
  CHECK (response_grace_minutes IS NULL
    OR (response_grace_minutes >= 15 AND response_grace_minutes <= 720));

COMMENT ON COLUMN public.passive_checkin_contract_versions.response_grace_minutes IS
  'Minutes the subject has to answer the daily check-in before the self stage '
  'escalates. NULL on legacy grid contracts, which keep the old 30-minute default.';

-- The most recent local occurrence of `_minute_of_day` that is not in the
-- future. Windows are generated forward from the epoch start, so anchoring the
-- epoch here is what makes every window boundary land on the time the subject
-- actually chose instead of the second they pressed save.
CREATE FUNCTION private.passive_last_local_time(
  _minute_of_day integer, _timezone text, _now timestamptz
) RETURNS timestamptz LANGUAGE sql IMMUTABLE SET search_path TO '' AS $$
  SELECT CASE WHEN candidate > _now THEN candidate - interval '1 day' ELSE candidate END
  FROM (
    SELECT (((_now AT TIME ZONE _timezone)::date
      + pg_catalog.make_interval(mins => _minute_of_day)) AT TIME ZONE _timezone) AS candidate
  ) today
$$;

COMMENT ON FUNCTION private.passive_last_local_time(integer,text,timestamptz) IS
  'Most recent local wall-clock occurrence of a minute-of-day, at or before _now.';

CREATE FUNCTION public.set_daily_checkin_contract(
  _ask_at_local_minute integer,
  _quiet_period_minutes integer,
  _response_grace_minutes integer,
  _timezone text,
  _target_mode text DEFAULT 'shadow',
  _client_contract_version text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE
  _uid uuid := auth.uid();
  _now timestamptz;
  _anchor timestamptz;
  _version_number bigint;
  _contract_id uuid;
  _epoch_id uuid;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000';
  END IF;
  IF _ask_at_local_minute IS NULL OR _ask_at_local_minute NOT BETWEEN 0 AND 1439 THEN
    RAISE EXCEPTION 'ask_at_local_minute must be a minute of the day'
      USING ERRCODE = '22023';
  END IF;
  -- Below four hours the waiver stops being a waiver and becomes a tripwire;
  -- above two days the subject is not keeping a contract with anybody.
  IF _quiet_period_minutes IS NULL OR _quiet_period_minutes NOT BETWEEN 240 AND 2880 THEN
    RAISE EXCEPTION 'quiet_period_minutes must be between 240 and 2880'
      USING ERRCODE = '22023';
  END IF;
  IF _response_grace_minutes IS NULL OR _response_grace_minutes NOT BETWEEN 15 AND 720 THEN
    RAISE EXCEPTION 'response_grace_minutes must be between 15 and 720'
      USING ERRCODE = '22023';
  END IF;
  IF _timezone IS NULL OR length(btrim(_timezone)) = 0
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names zone WHERE zone.name = _timezone) THEN
    RAISE EXCEPTION 'a valid IANA timezone is required' USING ERRCODE = '22023';
  END IF;
  IF _client_contract_version IS DISTINCT FROM 'daily-checkin-v1' THEN
    RAISE EXCEPTION 'client does not implement daily-checkin-v1' USING ERRCODE = '22023';
  END IF;
  IF _target_mode NOT IN ('shadow','passive_checkin') THEN
    RAISE EXCEPTION 'target mode must be shadow or passive_checkin' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('kc-passive-checkin-contract'), pg_catalog.hashtext(_uid::text));

  INSERT INTO public.passive_checkin_accounts(user_id) VALUES (_uid)
  ON CONFLICT (user_id) DO NOTHING;
  PERFORM 1 FROM public.passive_checkin_accounts WHERE user_id = _uid FOR UPDATE;

  _now := clock_timestamp();
  _anchor := private.passive_last_local_time(_ask_at_local_minute, _timezone, _now);

  SELECT coalesce(max(version_number),0)+1 INTO _version_number
  FROM public.passive_checkin_contract_versions WHERE user_id = _uid;

  -- A settings change ends the old boundary rather than accumulating across it.
  UPDATE public.passive_checkin_windows
  SET outcome='superseded', finalized_at=_now, superseded_reason='contract_changed'
  WHERE user_id=_uid AND outcome='pending';
  UPDATE public.passive_monitoring_epochs
  SET ended_at=_now, end_reason='contract_changed'
  WHERE user_id=_uid AND ended_at IS NULL;

  -- Sleep is not a separate control any more. The subject picks the hour they
  -- are willing to be asked, which is the same protection stated in terms they
  -- can actually check, so a night gate has nothing left to add.
  INSERT INTO public.passive_checkin_contract_versions(
    user_id, version_number, interval_minutes, consecutive_misses,
    sleep_policy, sleep_start_local, sleep_end_local, timezone,
    response_grace_minutes, client_contract_version, effective_at, created_by
  ) VALUES (
    _uid, _version_number, _quiet_period_minutes, 1,
    'none', NULL, NULL, _timezone,
    _response_grace_minutes, _client_contract_version, _now, _uid
  ) RETURNING id INTO _contract_id;

  INSERT INTO public.passive_monitoring_epochs(user_id, contract_version_id, started_at, start_reason)
  VALUES (_uid, _contract_id, _anchor, 'contract_saved')
  RETURNING id INTO _epoch_id;

  UPDATE public.passive_checkin_accounts
  SET engine_mode=_target_mode, active_contract_version_id=_contract_id,
      active_epoch_id=_epoch_id, updated_at=_now
  WHERE user_id=_uid;

  RETURN jsonb_build_object(
    'contract_version_id', _contract_id, 'epoch_id', _epoch_id,
    'version_number', _version_number, 'engine_mode', _target_mode,
    'ask_at_local_minute', _ask_at_local_minute,
    'quiet_period_minutes', _quiet_period_minutes,
    'response_grace_minutes', _response_grace_minutes,
    'timezone', _timezone, 'anchored_at', _anchor, 'effective_at', _now);
END;
$$;

REVOKE ALL ON FUNCTION public.set_daily_checkin_contract(integer,integer,integer,text,text,text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_daily_checkin_contract(integer,integer,integer,text,text,text)
  TO authenticated;

-- The question itself. Unchanged except for its deadline: the grid opened the
-- self stage with a hardcoded thirty minutes, which is a reasonable deadline
-- for "you have been silent for hours" and an unreasonable one for "good
-- morning, are you up". Legacy contracts keep thirty minutes.
CREATE OR REPLACE FUNCTION private.maybe_open_passive_checkin_alert(
  _user_id uuid, _epoch_id uuid, _contract_id uuid, _now timestamptz
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _account public.passive_checkin_accounts%ROWTYPE;
  _contract public.passive_checkin_contract_versions%ROWTYPE;
  _chain bigint; _alert_id uuid; _grace interval;
BEGIN
  SELECT * INTO _account FROM public.passive_checkin_accounts WHERE user_id=_user_id;
  SELECT * INTO STRICT _contract FROM public.passive_checkin_contract_versions WHERE id=_contract_id;
  SELECT count(*) INTO _chain FROM public.passive_checkin_windows candidate
  WHERE candidate.epoch_id=_epoch_id AND candidate.outcome='missed'
    AND NOT EXISTS(SELECT 1 FROM public.passive_checkin_windows later
      WHERE later.epoch_id=_epoch_id AND later.ordinal>candidate.ordinal
        AND later.outcome IN('checked_in','superseded'));
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

-- The subject's own view of the contract, in the vocabulary the settings screen
-- now uses. The grid RPC exposed D, N and H; none of those are user concepts.
CREATE OR REPLACE FUNCTION public.my_daily_checkin()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _uid uuid := auth.uid();
  _account public.passive_checkin_accounts%ROWTYPE;
  _contract public.passive_checkin_contract_versions%ROWTYPE;
  _epoch public.passive_monitoring_epochs%ROWTYPE;
  _ask_minute integer;
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

  RETURN jsonb_build_object(
    'engine_mode', _account.engine_mode,
    'kill_switch_active', _account.kill_switch_active,
    'version_number', _contract.version_number,
    'ask_at_local_minute', _ask_minute,
    'quiet_period_minutes', _contract.interval_minutes,
    'response_grace_minutes', coalesce(_contract.response_grace_minutes, 30),
    'timezone', _contract.timezone,
    'effective_at', _contract.effective_at,
    'next_question_at', (
      SELECT min(window_end) FROM public.passive_checkin_windows
      WHERE epoch_id=_epoch.id AND outcome='pending'),
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

REVOKE ALL ON FUNCTION public.my_daily_checkin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_daily_checkin() TO authenticated;
