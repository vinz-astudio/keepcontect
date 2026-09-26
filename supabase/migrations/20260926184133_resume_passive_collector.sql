-- Resume an existing owned collector without discarding offline event identity.
CREATE FUNCTION public.resume_passive_collector(_binding_id uuid,_client_version text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _uid uuid:=auth.uid(); _binding private.passive_collector_bindings%ROWTYPE; _credential text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='28000'; END IF;
  IF _client_version IS NULL OR length(btrim(_client_version)) NOT BETWEEN 1 AND 80 THEN
    RAISE EXCEPTION 'invalid client version' USING ERRCODE='22023';
  END IF;
  SELECT * INTO _binding FROM private.passive_collector_bindings WHERE id=_binding_id FOR UPDATE;
  IF NOT FOUND OR _binding.revoked_at IS NOT NULL THEN
    RAISE EXCEPTION 'passive collector is revoked or unavailable' USING ERRCODE='55000';
  END IF;
  IF _binding.user_id<>_uid THEN RAISE EXCEPTION 'collector not owned' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.passive_checkin_accounts
    WHERE user_id=_uid AND active_epoch_id IS NOT NULL AND engine_mode IN('shadow','passive_checkin')) THEN
    RAISE EXCEPTION 'passive contract is not active' USING ERRCODE='55000';
  END IF;
  _credential:=encode(extensions.gen_random_bytes(32),'hex');
  UPDATE private.passive_collector_bindings SET credential_sha256=encode(extensions.digest(_credential,'sha256'),'hex'),
    credential_version=credential_version+1,client_version=btrim(_client_version)
  WHERE id=_binding_id RETURNING * INTO _binding;
  RETURN jsonb_build_object('binding_id',_binding.id,'credential',_credential,'credential_version',_binding.credential_version,
    'surface_type',_binding.surface_type,'collector_contract',_binding.collector_contract,'next_sequence',_binding.sequence_cursor+1);
END;
$$;
REVOKE ALL ON FUNCTION public.resume_passive_collector(uuid,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.resume_passive_collector(uuid,text) TO authenticated;
