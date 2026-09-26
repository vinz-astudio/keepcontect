-- Fail closed for legacy unscoped confirmations; never retarget a newer alert.
CREATE OR REPLACE FUNCTION private.confirm_subject_safety(_alert_id uuid,_pattern integer[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _uid uuid:=auth.uid(); _alert public.alerts%ROWTYPE; _hash text; _result text;
BEGIN
  IF _alert_id IS NULL THEN RAISE EXCEPTION 'alert_id_required' USING ERRCODE='22023'; END IF;
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='28000'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('kc:alert-policy:'||_uid::text,0));
  PERFORM 1 FROM public.passive_checkin_accounts WHERE user_id=_uid FOR UPDATE;
  SELECT * INTO _alert FROM public.alerts WHERE user_id=_uid
    AND id=_alert_id
    ORDER BY opened_at DESC LIMIT 1 FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',_alert_id IS NULL,'cleared_alert',false,
      'already_resolved',_alert_id IS NULL,'reason','alert_not_found');
  END IF;
  IF _alert.status<>'open' THEN
    RETURN jsonb_build_object('ok',true,'cleared_alert',false,'already_resolved',true);
  END IF;
  IF private.guardian_requires_pattern(_uid) THEN
    IF _pattern IS NULL THEN RAISE EXCEPTION 'pattern_required' USING ERRCODE='42501'; END IF;
    SELECT pattern_hash INTO _hash FROM public.user_settings WHERE user_id=_uid;
    IF _hash IS NULL OR cardinality(_pattern)<4 OR cardinality(_pattern)>9
      OR EXISTS(SELECT 1 FROM unnest(_pattern) n WHERE n IS NULL OR n<0 OR n>8)
      OR (SELECT count(DISTINCT n) FROM unnest(_pattern) n)<>cardinality(_pattern)
      OR encode(sha256(convert_to('kc:'||array_to_string(_pattern,'-'),'UTF8')),'hex')<>_hash THEN
      RAISE EXCEPTION 'invalid_pattern' USING ERRCODE='42501';
    END IF;
  END IF;
  UPDATE public.alerts SET status='resolved',resolved_at=clock_timestamp(),resolved_by=_uid,
    next_deadline=NULL,paused_until=NULL,paused_by=NULL,updated_at=clock_timestamp() WHERE id=_alert.id;
  INSERT INTO public.alert_events(alert_id,actor_id,kind,note)
  VALUES(_alert.id,_uid,'resolved',CASE WHEN private.guardian_requires_pattern(_uid)
    THEN 'self_pattern_confirmed' ELSE 'self_acknowledged' END);
  UPDATE public.notifications SET read_at=coalesce(read_at,clock_timestamp()),
    delivery_outcome=CASE WHEN pushed_at IS NULL THEN 'no_target' ELSE delivery_outcome END,
    pushed_at=coalesce(pushed_at,clock_timestamp()),delivery_lease_expiry=NULL
  WHERE alert_id=_alert.id AND kind IN('self','concern','group','community','terminal');
  INSERT INTO public.notifications(recipient_id,alert_id,kind,body,params)
  SELECT recipient,_alert.id,'resolved',coalesce(nullif(p.display_name,''),'成员')||' 已确认安全，告警解除。',
    jsonb_build_object('target',coalesce(p.display_name,''))
  FROM (SELECT _uid AS recipient UNION SELECT recipient_id FROM public.notifications
    WHERE alert_id=_alert.id AND kind IN('group','community','terminal','concern')) recipients
  LEFT JOIN public.profiles p ON p.id=_uid;
  _result:=private.insert_behavior_ping(_uid,gen_random_uuid(),clock_timestamp(),'manual','manual_checkin');
  IF _result<>'inserted' THEN RAISE EXCEPTION 'manual_checkin_rejected: %',_result; END IF;
  PERFORM private.trigger_push_dispatch();
  RETURN jsonb_build_object('ok',true,'cleared_alert',true);
END;
$$;
REVOKE ALL ON FUNCTION private.confirm_subject_safety(uuid,integer[]) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.acknowledge_notification_safe(_notification_id uuid,_alert_id uuid,_pattern integer[] DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _uid uuid:=auth.uid(); _notification public.notifications%ROWTYPE;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='28000'; END IF;
  IF _alert_id IS NULL OR _notification_id IS NULL THEN RAISE EXCEPTION 'alert_id_required' USING ERRCODE='22023'; END IF;
  -- Same policy lock order as ordinary confirmation. Do not lock a notification
  -- before confirm_subject_safety, which updates all notifications for the alert.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('kc:alert-policy:'||_uid::text,0));
  SELECT * INTO _notification FROM public.notifications WHERE id=_notification_id AND recipient_id=_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'notification_not_owned' USING ERRCODE='42501'; END IF;
  IF _notification.alert_id IS DISTINCT FROM _alert_id OR _notification.kind NOT IN ('self','concern')
    OR NOT EXISTS(SELECT 1 FROM public.alerts WHERE id=_alert_id AND user_id=_uid) THEN
    RAISE EXCEPTION 'notification_alert_mismatch' USING ERRCODE='42501';
  END IF;
  RETURN private.confirm_subject_safety(_alert_id,_pattern);
END;
$$;
REVOKE ALL ON FUNCTION public.acknowledge_notification_safe(uuid,uuid,integer[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.acknowledge_notification_safe(uuid,uuid,integer[]) TO authenticated;

-- Queued device activity has an immutable owner even when the SDK session changes
-- while IndexedDB or network work is pending. Never infer a new owner at upload.
CREATE FUNCTION public.record_owned_behavior_ping(_expected_user_id uuid,_event_id uuid,_observed_at timestamptz,_source text,_kind text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
  IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM _expected_user_id THEN
    RAISE EXCEPTION 'activity_owner_changed' USING ERRCODE='42501';
  END IF;
  RETURN private.insert_behavior_ping(_expected_user_id,_event_id,_observed_at,_source,_kind);
END;
$$;
CREATE FUNCTION public.record_owned_behavior_pings(_expected_user_id uuid,_events jsonb)
RETURNS TABLE(status text) LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
  IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM _expected_user_id THEN
    RAISE EXCEPTION 'activity_owner_changed' USING ERRCODE='42501';
  END IF;
  RETURN QUERY SELECT r.status FROM public.record_behavior_pings(_events) r;
END;
$$;
REVOKE ALL ON FUNCTION public.record_owned_behavior_ping(uuid,uuid,timestamptz,text,text),public.record_owned_behavior_pings(uuid,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.record_owned_behavior_ping(uuid,uuid,timestamptz,text,text),public.record_owned_behavior_pings(uuid,jsonb) TO authenticated;
