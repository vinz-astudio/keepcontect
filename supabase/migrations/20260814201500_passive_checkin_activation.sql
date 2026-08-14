-- ADR-0042 package 8: explicit migration, subject health display, and live activation gate.

CREATE FUNCTION private.passive_collector_health_summary(_user_id uuid,_now timestamptz)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
  WITH surfaces AS (
    SELECT b.id,b.collector_instance_id,b.surface_type,b.permission_state,b.capability_state,
      b.last_contact_at,r.expected_contact_cadence,
      CASE
        WHEN b.permission_state IN('denied','revoked') THEN 'permission_'||b.permission_state
        WHEN b.capability_state<>'ok' THEN 'capability_'||b.capability_state
        WHEN r.expected_contact_cadence IS NOT NULL
          AND (b.last_contact_at IS NULL OR _now-b.last_contact_at>r.expected_contact_cadence*2) THEN 'silent'
        ELSE NULL
      END reason
    FROM private.passive_collector_bindings b
    JOIN private.passive_surface_registry r USING(surface_type)
    WHERE b.user_id=_user_id AND b.revoked_at IS NULL
  ), items AS (
    SELECT *,CASE WHEN reason IS NULL THEN 'ready' ELSE 'limited' END state,
      CASE reason
        WHEN 'permission_denied' THEN 'Open system settings and grant the required permission.'
        WHEN 'permission_revoked' THEN 'Bind this device again after restoring permission.'
        WHEN 'capability_unsupported' THEN 'Use another supported device or collector.'
        WHEN 'capability_degraded' THEN 'Review this device setup and background restrictions.'
        WHEN 'silent' THEN 'Open Keep Contact on this device and repair background operation.'
        ELSE NULL
      END repair_action
    FROM surfaces
  )
  SELECT jsonb_build_object(
    'state',CASE WHEN count(*)=0 THEN 'off'
      WHEN bool_or(reason IS NOT NULL) THEN 'limited' ELSE 'ready' END,
    'devices',coalesce(jsonb_agg(jsonb_build_object(
      'binding_id',id,'device',collector_instance_id,'surface_type',surface_type,
      'state',state,'reason',reason,'repair_action',repair_action,
      'last_contact_at',last_contact_at
    ) ORDER BY collector_instance_id),'[]'::jsonb),
    'miss_counting_continues',true,
    'evaluated_at',_now
  ) FROM items
$$;

CREATE FUNCTION public.my_passive_collector_health()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _uid uuid:=auth.uid();
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='28000'; END IF;
  RETURN private.passive_collector_health_summary(_uid,clock_timestamp());
END;
$$;

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

REVOKE ALL ON FUNCTION private.passive_collector_health_summary(uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.my_passive_collector_health() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.activate_passive_checkin_contract(integer,integer,text,time,time,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.my_passive_collector_health() TO authenticated;
GRANT EXECUTE ON FUNCTION public.activate_passive_checkin_contract(integer,integer,text,time,time,text,text) TO authenticated;

COMMENT ON FUNCTION public.activate_passive_checkin_contract(integer,integer,text,time,time,text,text) IS
  'Explicit subject migration after 14 shadow days. Collector health is display-only and does not gate miss evaluation.';
