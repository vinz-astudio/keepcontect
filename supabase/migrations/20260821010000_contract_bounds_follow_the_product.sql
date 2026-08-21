-- The contract bounds now follow the product, not the other way round.
--
-- Three limits in `set_daily_checkin_contract` were written before the settings
-- screen existed, and the screen that shipped contradicts all three:
--
--   quiet period      accepted 240..2880, the screen offers 90..360
--   consecutive misses hardcoded to 1,    the screen offers 2..8
--   grace             accepted 15..720,   the screen offers 15..90
--
-- The 90-minute floor is not a preference. `private.passive_surface_registry`
-- declares `arrival_allowance = 90 minutes` for `ios_native`: evidence from a
-- perfectly healthy iOS collector is allowed to arrive that late. A floor below
-- it would mark working devices as out of contact. The old 240 carried no such
-- derivation.
--
-- Two consecutive misses replace the hardcoded 1 for the same reason the screen
-- asks for it: one quiet stretch is usually a phone that could not report, not a
-- person in trouble. Requiring a chain is what keeps that from reaching anyone.
--
-- The grace ceiling stays at 720 here even though the screen offers at most 90.
-- Narrowing it would reject the 120-minute contracts three live accounts already
-- hold. The screen is the tighter promise; the column keeps accepting history.

CREATE OR REPLACE FUNCTION public.set_daily_checkin_contract(
  _ask_at_local_minute integer,
  _quiet_period_minutes integer,
  _response_grace_minutes integer,
  _timezone text,
  _target_mode text DEFAULT 'shadow',
  _client_contract_version text DEFAULT NULL,
  _consecutive_misses integer DEFAULT 2
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
  -- 90 is the iOS collector's own declared arrival allowance; 360 keeps at least
  -- two checks inside the shortest outreach the screen can compose.
  IF _quiet_period_minutes IS NULL OR _quiet_period_minutes NOT BETWEEN 90 AND 2880 THEN
    RAISE EXCEPTION 'quiet_period_minutes must be between 90 and 2880'
      USING ERRCODE = '22023';
  END IF;
  IF _response_grace_minutes IS NULL OR _response_grace_minutes NOT BETWEEN 15 AND 720 THEN
    RAISE EXCEPTION 'response_grace_minutes must be between 15 and 720'
      USING ERRCODE = '22023';
  END IF;
  -- One miss is a reporting gap, not evidence. The chain is the false-alarm guard.
  IF _consecutive_misses IS NULL OR _consecutive_misses NOT BETWEEN 2 AND 8 THEN
    RAISE EXCEPTION 'consecutive_misses must be between 2 and 8'
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

  UPDATE public.passive_checkin_windows
  SET outcome='superseded', finalized_at=_now, superseded_reason='contract_changed'
  WHERE user_id=_uid AND outcome='pending';
  UPDATE public.passive_monitoring_epochs
  SET ended_at=_now, end_reason='contract_changed'
  WHERE user_id=_uid AND ended_at IS NULL;

  INSERT INTO public.passive_checkin_contract_versions(
    user_id, version_number, interval_minutes, consecutive_misses,
    sleep_policy, sleep_start_local, sleep_end_local, timezone,
    response_grace_minutes, client_contract_version, effective_at, created_by
  ) VALUES (
    _uid, _version_number, _quiet_period_minutes, _consecutive_misses,
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
    'consecutive_misses', _consecutive_misses,
    'response_grace_minutes', _response_grace_minutes,
    'timezone', _timezone);
END;
$$;

-- The window table's own floor was written for the grid model and still says 20.
-- Leave it: it is wider than the RPC and rejects nothing the screen can produce.

REVOKE ALL ON FUNCTION public.set_daily_checkin_contract(integer,integer,integer,text,text,text,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_daily_checkin_contract(integer,integer,integer,text,text,text,integer) TO authenticated;

-- The six-argument overload would otherwise stay callable and keep writing 1.
DROP FUNCTION IF EXISTS public.set_daily_checkin_contract(integer,integer,integer,text,text,text);


-- `my_daily_checkin` never returned `consecutive_misses`, so a screen that shows
-- the number would always fall back to its own default and quietly disagree with
-- the contract actually in force. Return what the engine is really using.
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
    'consecutive_misses', _contract.consecutive_misses,
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
