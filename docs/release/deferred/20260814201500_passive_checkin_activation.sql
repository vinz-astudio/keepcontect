-- ADR-0042 package 8: explicit migration, subject health display, and live activation gate.

CREATE FUNCTION public.activate_passive_checkin_contract(
  _interval_minutes integer,
  _consecutive_misses integer,
  _sleep_policy text,
  _sleep_start_local time DEFAULT NULL,
  _sleep_end_local time DEFAULT NULL,
  _timezone text DEFAULT NULL,
  _client_contract_version text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE
  _uid uuid:=auth.uid();
  _account public.passive_checkin_accounts%ROWTYPE;
  _epoch_started_at timestamptz;
  _status jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='28000'; END IF;
  SELECT * INTO _account FROM public.passive_checkin_accounts WHERE user_id=_uid FOR UPDATE;
  IF NOT FOUND OR _account.engine_mode='legacy' OR _account.active_epoch_id IS NULL THEN
    RAISE EXCEPTION 'save shadow settings before live activation' USING ERRCODE='55000';
  END IF;
  IF _account.kill_switch_active THEN
    RAISE EXCEPTION 'passive check-in is disabled by the safety switch' USING ERRCODE='55000';
  END IF;
  IF EXISTS(SELECT 1 FROM public.alerts WHERE user_id=_uid AND status='open') THEN
    RAISE EXCEPTION 'resolve the current alert before changing passive authority' USING ERRCODE='55000';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM private.passive_collector_bindings WHERE user_id=_uid AND revoked_at IS NULL) THEN
    RAISE EXCEPTION 'bind at least one collector before live activation' USING ERRCODE='55000';
  END IF;
  SELECT started_at INTO STRICT _epoch_started_at FROM public.passive_monitoring_epochs
  WHERE id=_account.active_epoch_id AND user_id=_uid;
  IF _account.engine_mode='shadow' AND _epoch_started_at>clock_timestamp()-interval '14 days' THEN
    RAISE EXCEPTION 'fourteen consecutive shadow days are required' USING ERRCODE='55000';
  END IF;

  -- This is still one client RPC. The existing validator creates the immutable
  -- version/epoch/window, then this explicit migration gives it live authority.
  _status:=public.set_passive_checkin_contract(
    _interval_minutes,_consecutive_misses,_sleep_policy,_sleep_start_local,
    _sleep_end_local,_timezone,'shadow',_client_contract_version
  );
  UPDATE public.passive_checkin_accounts
  SET engine_mode='passive_checkin',updated_at=clock_timestamp()
  WHERE user_id=_uid;
  RETURN public.my_passive_checkin_status();
END;
$$;

REVOKE ALL ON FUNCTION public.activate_passive_checkin_contract(integer,integer,text,time,time,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.activate_passive_checkin_contract(integer,integer,text,time,time,text,text) TO authenticated;
