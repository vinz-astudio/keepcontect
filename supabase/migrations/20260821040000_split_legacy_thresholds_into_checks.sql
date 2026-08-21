-- Bring the live contracts into the range the settings screen can actually show.
--
-- Three accounts are on the engine, and all three were configured before the new
-- Routine screen existed. They hold single thresholds of 8, 12 and 24 hours with
-- `consecutive_misses = 1`. The screen offers 90..360 minutes and 2..8 misses, so
-- none of those numbers can be displayed — and worse, `clampCheckin` pulls the
-- draft to the 360 ceiling the moment the screen loads. A subject who opened
-- their settings and changed anything at all would have had a 24-hour threshold
-- silently rewritten to 6 hours: a fourfold tightening nobody asked for, which
-- nothing on screen would have mentioned.
--
-- Human decision, 2026-08-21: express the same total as a number of checks
-- instead of one long one. Divide by the six-hour ceiling to get the count, then
-- split the original evenly across it:
--
--     checks   = ceil(threshold / 360)
--     interval = threshold / checks
--
--      8h  ->  2 checks of 4h
--     12h  ->  2 checks of 6h
--     24h  ->  4 checks of 6h
--
-- The total time before anyone is contacted is unchanged, which is the part the
-- subject actually chose. What changes is that the number is now expressible on
-- the screen, and a single missed check no longer reaches anyone on its own —
-- the chain is what tells a reporting gap apart from a person in trouble.
--
-- This does NOT undo the awake-time clock from 20260821020000. Their total is now
-- counted in awake time like everyone else's, so a stretch of silence beginning
-- before bedtime still runs longer in wall-clock terms than it used to. That is
-- the deliberate behaviour of this release, not an oversight of this migration.

-- The split, as a function rather than inline in a DO block, so that the same
-- code the migration runs is the code the tests exercise. A conversion nobody can
-- re-run is a conversion nobody can check.
CREATE FUNCTION private.split_legacy_threshold(_threshold_minutes integer)
RETURNS TABLE(checks integer, interval_minutes integer)
LANGUAGE plpgsql IMMUTABLE SET search_path TO '' AS $$
DECLARE _checks integer; _step integer;
BEGIN
  IF _threshold_minutes IS NULL OR _threshold_minutes <= 0 THEN RETURN; END IF;
  -- Already displayable: leave it exactly alone.
  IF _threshold_minutes <= 360 THEN
    RETURN QUERY SELECT 1, _threshold_minutes; RETURN;
  END IF;

  _checks := ceil(_threshold_minutes / 360.0)::integer;
  LOOP
    -- Rounded UP to a whole half hour, so the total is never shortened.
    -- Shortening would contact the group sooner than the subject chose.
    _step := (ceil(_threshold_minutes::numeric / _checks / 30) * 30)::integer;
    EXIT WHEN _step <= 360;
    _checks := _checks + 1;
  END LOOP;

  IF _step < 90 THEN _step := 90; END IF;
  IF _checks < 2 THEN _checks := 2; END IF;
  IF _checks > 8 THEN _checks := 8; END IF;
  RETURN QUERY SELECT _checks, _step;
END;
$$;

COMMENT ON FUNCTION private.split_legacy_threshold(integer) IS
  'Expresses a pre-screen threshold as checks x interval, both inside 90..360 and 2..8, total never shortened.';

CREATE FUNCTION private.convert_legacy_checkin_contract(_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE
  _account public.passive_checkin_accounts%ROWTYPE;
  _contract public.passive_checkin_contract_versions%ROWTYPE;
  _checks integer; _interval integer;
  _now timestamptz := clock_timestamp();
  _version bigint; _contract_id uuid; _epoch_id uuid;
BEGIN
  SELECT * INTO _account FROM public.passive_checkin_accounts
  WHERE user_id = _user_id FOR UPDATE;
  IF NOT FOUND OR _account.active_contract_version_id IS NULL
     OR _account.engine_mode NOT IN ('shadow','passive_checkin') THEN
    RETURN jsonb_build_object('status','skipped','reason','not an engine account');
  END IF;

  SELECT * INTO _contract FROM public.passive_checkin_contract_versions
  WHERE id = _account.active_contract_version_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status','skipped','reason','no active contract');
  END IF;
  IF _contract.interval_minutes <= 360 THEN
    RETURN jsonb_build_object('status','skipped','reason','already displayable');
  END IF;

  SELECT split.checks, split.interval_minutes INTO _checks, _interval
  FROM private.split_legacy_threshold(_contract.interval_minutes) AS split;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('kc-passive-checkin-contract'),
    pg_catalog.hashtext(_user_id::text));

  SELECT coalesce(max(version_number),0)+1 INTO _version
  FROM public.passive_checkin_contract_versions WHERE user_id = _user_id;

  -- The same closing sequence a settings change performs: the old boundary ends
  -- rather than accumulating across the change.
  UPDATE public.passive_checkin_windows
  SET outcome='superseded', finalized_at=_now, superseded_reason='contract_changed'
  WHERE user_id=_user_id AND outcome='pending';
  UPDATE public.passive_monitoring_epochs
  SET ended_at=_now, end_reason='contract_changed'
  WHERE user_id=_user_id AND ended_at IS NULL;

  INSERT INTO public.passive_checkin_contract_versions(
    user_id, version_number, interval_minutes, consecutive_misses,
    sleep_policy, sleep_start_local, sleep_end_local, timezone,
    response_grace_minutes, client_contract_version, effective_at, created_by
  ) VALUES (
    _user_id, _version, _interval, _checks,
    _contract.sleep_policy, _contract.sleep_start_local, _contract.sleep_end_local,
    _contract.timezone, _contract.response_grace_minutes,
    _contract.client_contract_version, _now, _user_id
  ) RETURNING id INTO _contract_id;

  -- Anchored at the conversion, not at the old epoch start. Re-basing from now is
  -- what guarantees nobody wakes up already part-way through a chain of missed
  -- checks they never had a chance to answer.
  --
  -- The side effect is that `my_daily_checkin` will derive `ask_at_local_minute`
  -- from this instant instead of the hour originally chosen. That number is
  -- vestigial under rolling deadlines — the chain re-anchors on the first piece
  -- of evidence and never returns to it — and the settings screen does not show
  -- it. Preserving it would mean anchoring in the past, which is the one thing
  -- that could manufacture a missed check out of the conversion itself.
  INSERT INTO public.passive_monitoring_epochs(
    user_id, contract_version_id, started_at, start_reason
  ) VALUES (_user_id, _contract_id, _now, 'contract_saved')
  RETURNING id INTO _epoch_id;

  UPDATE public.passive_checkin_accounts
  SET active_contract_version_id=_contract_id, active_epoch_id=_epoch_id, updated_at=_now
  WHERE user_id=_user_id;

  RETURN jsonb_build_object(
    'status','converted',
    'from_interval_minutes', _contract.interval_minutes,
    'from_consecutive_misses', _contract.consecutive_misses,
    'to_interval_minutes', _interval,
    'to_consecutive_misses', _checks,
    'total_minutes_before', _contract.interval_minutes * _contract.consecutive_misses,
    'total_minutes_after', _interval * _checks);
END;
$$;

REVOKE ALL ON FUNCTION private.split_legacy_threshold(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.convert_legacy_checkin_contract(uuid) FROM PUBLIC, anon, authenticated;

DO $$
DECLARE _subject record; _result jsonb; _converted integer := 0;
BEGIN
  FOR _subject IN
    SELECT user_id FROM public.passive_checkin_accounts
    WHERE engine_mode IN ('shadow','passive_checkin')
      AND active_contract_version_id IS NOT NULL
    ORDER BY user_id
  LOOP
    _result := private.convert_legacy_checkin_contract(_subject.user_id);
    IF _result->>'status' = 'converted' THEN
      _converted := _converted + 1;
      RAISE NOTICE 'converted % : % x1 -> % x%', _subject.user_id,
        _result->>'from_interval_minutes', _result->>'to_interval_minutes',
        _result->>'to_consecutive_misses';
    END IF;
  END LOOP;
  RAISE NOTICE 'legacy threshold conversion complete: % account(s)', _converted;
END;
$$;
