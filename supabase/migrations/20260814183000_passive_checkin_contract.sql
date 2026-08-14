-- ADR-0042 package 1: additive passive check-in contract storage.
--
-- This migration deliberately creates no scheduler and changes no legacy
-- alert function. Existing accounts do not receive a row and therefore remain
-- legacy. Package 6 owns evaluation and alert authority.

CREATE TABLE public.passive_checkin_accounts (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  engine_mode text NOT NULL DEFAULT 'legacy'
    CHECK (engine_mode IN ('legacy', 'shadow', 'passive_checkin')),
  active_contract_version_id uuid,
  active_epoch_id uuid,
  kill_switch_active boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE public.passive_checkin_contract_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL
    REFERENCES public.passive_checkin_accounts(user_id) ON DELETE CASCADE,
  version_number bigint NOT NULL CHECK (version_number > 0),
  interval_minutes integer NOT NULL
    CHECK (interval_minutes BETWEEN 20 AND 360),
  consecutive_misses integer NOT NULL
    CHECK (consecutive_misses BETWEEN 1 AND 1000000),
  sleep_policy text NOT NULL CHECK (sleep_policy IN ('configured', 'none')),
  sleep_start_local time,
  sleep_end_local time,
  timezone text,
  client_contract_version text NOT NULL
    CHECK (length(btrim(client_contract_version)) > 0),
  effective_at timestamptz NOT NULL,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT passive_checkin_contract_versions_user_version_uidx
    UNIQUE (user_id, version_number),
  CONSTRAINT passive_checkin_contract_versions_sleep_choice_check CHECK (
    (
      sleep_policy = 'configured'
      AND sleep_start_local IS NOT NULL
      AND sleep_end_local IS NOT NULL
      AND sleep_start_local <> sleep_end_local
      AND timezone IS NOT NULL
      AND length(btrim(timezone)) > 0
    )
    OR (
      sleep_policy = 'none'
      AND sleep_start_local IS NULL
      AND sleep_end_local IS NULL
      AND timezone IS NULL
    )
  )
);

CREATE TABLE public.passive_monitoring_epochs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL
    REFERENCES public.passive_checkin_accounts(user_id) ON DELETE CASCADE,
  contract_version_id uuid NOT NULL
    REFERENCES public.passive_checkin_contract_versions(id) ON DELETE RESTRICT,
  started_at timestamptz NOT NULL,
  ended_at timestamptz,
  start_reason text NOT NULL
    CHECK (start_reason IN ('contract_saved', 'explicit_resolution', 'manual_reset', 'rollback')),
  end_reason text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK (ended_at IS NULL OR ended_at >= started_at)
);

CREATE UNIQUE INDEX passive_monitoring_epochs_one_active_per_user
  ON public.passive_monitoring_epochs(user_id)
  WHERE ended_at IS NULL;

CREATE TABLE public.passive_checkin_windows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL
    REFERENCES public.passive_checkin_accounts(user_id) ON DELETE CASCADE,
  epoch_id uuid NOT NULL
    REFERENCES public.passive_monitoring_epochs(id) ON DELETE CASCADE,
  contract_version_id uuid NOT NULL
    REFERENCES public.passive_checkin_contract_versions(id) ON DELETE RESTRICT,
  ordinal bigint NOT NULL CHECK (ordinal >= 0),
  window_start timestamptz NOT NULL,
  window_end timestamptz NOT NULL,
  arrival_deadline timestamptz NOT NULL,
  outcome text NOT NULL DEFAULT 'pending'
    CHECK (outcome IN ('pending', 'checked_in', 'missed', 'superseded')),
  causal_evidence_id uuid,
  finalized_at timestamptz,
  superseded_reason text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK (window_end > window_start),
  CHECK (arrival_deadline >= window_end),
  CHECK (
    (outcome = 'pending' AND finalized_at IS NULL)
    OR (outcome <> 'pending' AND finalized_at IS NOT NULL)
  )
);

CREATE UNIQUE INDEX passive_checkin_windows_epoch_ordinal_uidx
  ON public.passive_checkin_windows(epoch_id, ordinal);
CREATE UNIQUE INDEX passive_checkin_windows_epoch_start_uidx
  ON public.passive_checkin_windows(epoch_id, window_start);
CREATE INDEX passive_checkin_windows_due_idx
  ON public.passive_checkin_windows(arrival_deadline)
  WHERE outcome = 'pending';

CREATE TABLE private.passive_alert_causal_windows (
  alert_id uuid NOT NULL REFERENCES public.alerts(id) ON DELETE CASCADE,
  window_id uuid NOT NULL
    REFERENCES public.passive_checkin_windows(id) ON DELETE RESTRICT,
  ordinal integer NOT NULL CHECK (ordinal >= 0),
  captured_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (alert_id, window_id),
  UNIQUE (alert_id, ordinal)
);

ALTER TABLE public.passive_checkin_accounts
  ADD CONSTRAINT passive_checkin_accounts_active_contract_fkey
  FOREIGN KEY (active_contract_version_id)
  REFERENCES public.passive_checkin_contract_versions(id) ON DELETE RESTRICT,
  ADD CONSTRAINT passive_checkin_accounts_active_epoch_fkey
  FOREIGN KEY (active_epoch_id)
  REFERENCES public.passive_monitoring_epochs(id) ON DELETE RESTRICT;

CREATE FUNCTION private.reject_passive_contract_version_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $$
BEGIN
  RAISE EXCEPTION 'passive check-in contract versions are immutable'
    USING ERRCODE = '55000';
END;
$$;

CREATE TRIGGER passive_checkin_contract_versions_immutable
BEFORE UPDATE ON public.passive_checkin_contract_versions
FOR EACH ROW EXECUTE FUNCTION private.reject_passive_contract_version_mutation();

CREATE FUNCTION public.set_passive_checkin_contract(
  _interval_minutes integer,
  _consecutive_misses integer,
  _sleep_policy text,
  _sleep_start_local time DEFAULT NULL,
  _sleep_end_local time DEFAULT NULL,
  _timezone text DEFAULT NULL,
  _target_mode text DEFAULT 'shadow',
  _client_contract_version text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  _uid uuid := auth.uid();
  _effective_at timestamptz;
  _version_number bigint;
  _contract_id uuid;
  _epoch_id uuid;
  _window_end timestamptz;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000';
  END IF;

  IF _interval_minutes IS NULL OR _interval_minutes NOT BETWEEN 20 AND 360 THEN
    RAISE EXCEPTION 'interval_minutes must be between 20 and 360'
      USING ERRCODE = '22023';
  END IF;
  IF _consecutive_misses IS NULL
     OR _consecutive_misses NOT BETWEEN 1 AND 1000000 THEN
    RAISE EXCEPTION 'consecutive_misses must be between 1 and 1000000'
      USING ERRCODE = '22023';
  END IF;
  IF _sleep_policy NOT IN ('configured', 'none') THEN
    RAISE EXCEPTION 'sleep_policy must be configured or none'
      USING ERRCODE = '22023';
  END IF;
  IF _sleep_policy = 'configured' THEN
    IF _sleep_start_local IS NULL
       OR _sleep_end_local IS NULL
       OR _sleep_start_local = _sleep_end_local
       OR _timezone IS NULL
       OR length(btrim(_timezone)) = 0
       OR NOT EXISTS (
         SELECT 1 FROM pg_catalog.pg_timezone_names AS zone
         WHERE zone.name = _timezone
       ) THEN
      RAISE EXCEPTION 'configured sleep requires distinct bounds and an IANA timezone'
        USING ERRCODE = '22023';
    END IF;
  ELSIF _sleep_start_local IS NOT NULL
        OR _sleep_end_local IS NOT NULL
        OR _timezone IS NOT NULL THEN
    RAISE EXCEPTION 'no-sleep policy cannot carry sleep bounds or timezone'
      USING ERRCODE = '22023';
  END IF;

  IF _client_contract_version IS DISTINCT FROM 'passive-checkin-v1' THEN
    RAISE EXCEPTION 'client does not implement passive-checkin-v1'
      USING ERRCODE = '22023';
  END IF;
  IF _target_mode = 'passive_checkin' THEN
    RAISE EXCEPTION 'live passive activation requires package 8 capability gates'
      USING ERRCODE = '0A000';
  END IF;
  IF _target_mode IS DISTINCT FROM 'shadow' THEN
    RAISE EXCEPTION 'target mode must be shadow in contract package 1'
      USING ERRCODE = '22023';
  END IF;

  -- One settings writer per account. The two-key form keeps this lock in a
  -- KC-specific namespace and avoids a read/max/insert race on version_number.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('kc-passive-checkin-contract'),
    pg_catalog.hashtext(_uid::text)
  );

  INSERT INTO public.passive_checkin_accounts(user_id)
  VALUES (_uid)
  ON CONFLICT (user_id) DO NOTHING;

  -- Lock the pointer row before closing the prior boundary.
  PERFORM 1
  FROM public.passive_checkin_accounts
  WHERE user_id = _uid
  FOR UPDATE;

  _effective_at := clock_timestamp();
  SELECT coalesce(max(version_number), 0) + 1
  INTO _version_number
  FROM public.passive_checkin_contract_versions
  WHERE user_id = _uid;

  UPDATE public.passive_checkin_windows
  SET outcome = 'superseded',
      finalized_at = _effective_at,
      superseded_reason = 'contract_changed'
  WHERE user_id = _uid
    AND outcome = 'pending';

  UPDATE public.passive_monitoring_epochs
  SET ended_at = _effective_at,
      end_reason = 'contract_changed'
  WHERE user_id = _uid
    AND ended_at IS NULL;

  INSERT INTO public.passive_checkin_contract_versions (
    user_id, version_number, interval_minutes, consecutive_misses,
    sleep_policy, sleep_start_local, sleep_end_local, timezone,
    client_contract_version, effective_at, created_by
  ) VALUES (
    _uid, _version_number, _interval_minutes, _consecutive_misses,
    _sleep_policy,
    CASE WHEN _sleep_policy = 'configured' THEN _sleep_start_local END,
    CASE WHEN _sleep_policy = 'configured' THEN _sleep_end_local END,
    CASE WHEN _sleep_policy = 'configured' THEN _timezone END,
    _client_contract_version, _effective_at, _uid
  )
  RETURNING id INTO _contract_id;

  INSERT INTO public.passive_monitoring_epochs (
    user_id, contract_version_id, started_at, start_reason
  ) VALUES (
    _uid, _contract_id, _effective_at, 'contract_saved'
  )
  RETURNING id INTO _epoch_id;

  _window_end := _effective_at
    + pg_catalog.make_interval(mins => _interval_minutes);

  INSERT INTO public.passive_checkin_windows (
    user_id, epoch_id, contract_version_id, ordinal,
    window_start, window_end, arrival_deadline
  ) VALUES (
    _uid, _epoch_id, _contract_id, 0,
    _effective_at, _window_end, _window_end
  );

  UPDATE public.passive_checkin_accounts
  SET engine_mode = 'shadow',
      active_contract_version_id = _contract_id,
      active_epoch_id = _epoch_id,
      updated_at = _effective_at
  WHERE user_id = _uid;

  RETURN public.my_passive_checkin_status();
END;
$$;

CREATE FUNCTION public.my_passive_checkin_status()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  _uid uuid := auth.uid();
  _account public.passive_checkin_accounts%ROWTYPE;
  _contract public.passive_checkin_contract_versions%ROWTYPE;
  _epoch public.passive_monitoring_epochs%ROWTYPE;
  _window public.passive_checkin_windows%ROWTYPE;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO _account
  FROM public.passive_checkin_accounts
  WHERE user_id = _uid;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'engine_mode', 'legacy',
      'kill_switch_active', false,
      'contract', NULL,
      'epoch', NULL,
      'current_window', NULL,
      'collector_health', NULL,
      'recommendation', NULL
    );
  END IF;

  SELECT * INTO _contract
  FROM public.passive_checkin_contract_versions
  WHERE id = _account.active_contract_version_id
    AND user_id = _uid;

  SELECT * INTO _epoch
  FROM public.passive_monitoring_epochs
  WHERE id = _account.active_epoch_id
    AND user_id = _uid;

  SELECT * INTO _window
  FROM public.passive_checkin_windows
  WHERE epoch_id = _account.active_epoch_id
    AND user_id = _uid
    AND outcome = 'pending'
  ORDER BY ordinal
  LIMIT 1;

  RETURN jsonb_build_object(
    'engine_mode', _account.engine_mode,
    'kill_switch_active', _account.kill_switch_active,
    'contract', jsonb_build_object(
      'id', _contract.id,
      'version_number', _contract.version_number,
      'interval_minutes', _contract.interval_minutes,
      'consecutive_misses', _contract.consecutive_misses,
      'nominal_h_minutes',
        _contract.interval_minutes::bigint * _contract.consecutive_misses::bigint,
      'sleep_policy', _contract.sleep_policy,
      'sleep_start_local', _contract.sleep_start_local,
      'sleep_end_local', _contract.sleep_end_local,
      'timezone', _contract.timezone,
      'client_contract_version', _contract.client_contract_version,
      'effective_at', _contract.effective_at
    ),
    'epoch', jsonb_build_object(
      'id', _epoch.id,
      'started_at', _epoch.started_at,
      'start_reason', _epoch.start_reason
    ),
    'current_window', CASE
      WHEN _window.id IS NULL THEN NULL
      ELSE jsonb_build_object(
        'id', _window.id,
        'ordinal', _window.ordinal,
        'window_start', _window.window_start,
        'window_end', _window.window_end,
        'arrival_deadline', _window.arrival_deadline,
        'outcome', _window.outcome
      )
    END,
    'collector_health', NULL,
    'recommendation', NULL
  );
END;
$$;

ALTER TABLE public.passive_checkin_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.passive_checkin_contract_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.passive_monitoring_epochs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.passive_checkin_windows ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.passive_alert_causal_windows ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.passive_checkin_accounts FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.passive_checkin_contract_versions FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.passive_monitoring_epochs FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.passive_checkin_windows FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE private.passive_alert_causal_windows FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION private.reject_passive_contract_version_mutation() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.set_passive_checkin_contract(integer, integer, text, time, time, text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_passive_checkin_contract(integer, integer, text, time, time, text, text, text)
  TO authenticated;
REVOKE ALL ON FUNCTION public.my_passive_checkin_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_passive_checkin_status() TO authenticated;

COMMENT ON TABLE public.passive_checkin_contract_versions IS
  'ADR-0042 immutable user-owned D/N/sleep contract revisions. Client access is RPC-only.';
COMMENT ON TABLE public.passive_checkin_windows IS
  'ADR-0042 server-owned half-open UTC windows. Package 6 owns evaluation.';
