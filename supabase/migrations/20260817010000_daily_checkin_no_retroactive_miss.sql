-- Saving settings must never manufacture a miss.
--
-- The epoch is anchored to the most recent local occurrence of the chosen ask
-- time, so that windows land on the hour the subject picked. That anchor is by
-- construction in the past — up to a full quiet period before the save. The
-- window generator then produced a window that had already ended before the
-- contract existed, found no evidence inside it, called it `missed`, and with
-- consecutive_misses = 1 opened a self alert on the spot.
--
-- Observed in production 2026-08-16 on two accounts: a subject who chose 12:30
-- local and saved at 02:28 local was asked to confirm within two minutes. They
-- saved twice and were asked twice.
--
-- A window that began before the contract took effect is a partial window, and
-- the counting model already has the right outcome for it: `superseded`, which
-- resets the chain and is never counted. The engine applied that to the
-- outgoing contract's trailing window already; it had no way to know the first
-- window of a NEW epoch could be partial too, because only the anchor makes it
-- so.
CREATE OR REPLACE FUNCTION public.set_daily_checkin_contract(
  _ask_at_local_minute integer,
  _quiet_period_minutes integer,
  _response_grace_minutes integer,
  _timezone text,
  _target_mode text DEFAULT 'shadow',
  _client_contract_version text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE
  _uid uuid := auth.uid();
  _now timestamptz; _anchor timestamptz;
  _version_number bigint; _contract_id uuid; _epoch_id uuid;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='28000'; END IF;
  IF _ask_at_local_minute IS NULL OR _ask_at_local_minute NOT BETWEEN 0 AND 1439 THEN
    RAISE EXCEPTION 'ask_at_local_minute must be a minute of the day' USING ERRCODE='22023'; END IF;
  IF _quiet_period_minutes IS NULL OR _quiet_period_minutes NOT BETWEEN 240 AND 2880 THEN
    RAISE EXCEPTION 'quiet_period_minutes must be between 240 and 2880' USING ERRCODE='22023'; END IF;
  IF _response_grace_minutes IS NULL OR _response_grace_minutes NOT BETWEEN 15 AND 720 THEN
    RAISE EXCEPTION 'response_grace_minutes must be between 15 and 720' USING ERRCODE='22023'; END IF;
  IF _timezone IS NULL OR length(btrim(_timezone))=0
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names z WHERE z.name=_timezone) THEN
    RAISE EXCEPTION 'a valid IANA timezone is required' USING ERRCODE='22023'; END IF;
  IF _client_contract_version IS DISTINCT FROM 'daily-checkin-v1' THEN
    RAISE EXCEPTION 'client does not implement daily-checkin-v1' USING ERRCODE='22023'; END IF;
  IF _target_mode NOT IN ('shadow','passive_checkin') THEN
    RAISE EXCEPTION 'target mode must be shadow or passive_checkin' USING ERRCODE='22023'; END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('kc-passive-checkin-contract'), pg_catalog.hashtext(_uid::text));
  INSERT INTO public.passive_checkin_accounts(user_id) VALUES (_uid) ON CONFLICT (user_id) DO NOTHING;
  PERFORM 1 FROM public.passive_checkin_accounts WHERE user_id=_uid FOR UPDATE;

  _now := clock_timestamp();
  _anchor := private.passive_last_local_time(_ask_at_local_minute, _timezone, _now);

  SELECT coalesce(max(version_number),0)+1 INTO _version_number
  FROM public.passive_checkin_contract_versions WHERE user_id=_uid;

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
    _uid, _version_number, _quiet_period_minutes, 1,
    'none', NULL, NULL, _timezone,
    _response_grace_minutes, _client_contract_version, _now, _uid
  ) RETURNING id INTO _contract_id;

  INSERT INTO public.passive_monitoring_epochs(user_id, contract_version_id, started_at, start_reason)
  VALUES (_uid, _contract_id, _anchor, 'contract_saved')
  RETURNING id INTO _epoch_id;

  -- Close every window of the new epoch that had already started before this
  -- contract existed. The subject cannot be judged on a period they had not
  -- yet agreed to.
  INSERT INTO public.passive_checkin_windows(
    user_id, epoch_id, contract_version_id, ordinal,
    window_start, window_end, arrival_deadline,
    outcome, finalized_at, superseded_reason)
  SELECT _uid, _epoch_id, _contract_id, gs.ordinal,
    _anchor + pg_catalog.make_interval(mins => (gs.ordinal*_quiet_period_minutes)::integer),
    _anchor + pg_catalog.make_interval(mins => ((gs.ordinal+1)*_quiet_period_minutes)::integer),
    _anchor + pg_catalog.make_interval(mins => ((gs.ordinal+1)*_quiet_period_minutes)::integer),
    'superseded', _now, 'contract_changed'
  FROM generate_series(
    0,
    greatest(0, floor(extract(epoch FROM (_now - _anchor))/60/_quiet_period_minutes)::bigint)
  ) AS gs(ordinal)
  WHERE _anchor + pg_catalog.make_interval(mins => (gs.ordinal*_quiet_period_minutes)::integer) < _now
  ON CONFLICT (epoch_id, ordinal) DO NOTHING;

  UPDATE public.passive_checkin_accounts
  SET engine_mode=_target_mode, active_contract_version_id=_contract_id,
      active_epoch_id=_epoch_id, updated_at=_now
  WHERE user_id=_uid;

  RETURN jsonb_build_object(
    'contract_version_id',_contract_id,'epoch_id',_epoch_id,
    'version_number',_version_number,'engine_mode',_target_mode,
    'ask_at_local_minute',_ask_at_local_minute,'quiet_period_minutes',_quiet_period_minutes,
    'response_grace_minutes',_response_grace_minutes,'timezone',_timezone,
    'anchored_at',_anchor,'effective_at',_now);
END;
$fn$;

-- Repair accounts that were already judged on a period predating their contract.
UPDATE public.passive_checkin_windows w
SET outcome='superseded', superseded_reason='contract_changed', finalized_at=clock_timestamp()
FROM public.passive_checkin_accounts a
JOIN public.passive_checkin_contract_versions v ON v.id=a.active_contract_version_id
WHERE w.epoch_id=a.active_epoch_id
  AND v.client_contract_version='daily-checkin-v1'
  AND w.window_start < v.effective_at
  AND w.outcome IN ('missed','pending');
