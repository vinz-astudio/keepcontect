-- One push registration generation per installation. Revocation credentials can
-- only revoke that generation and are independent of the login refresh token.
CREATE TABLE private.push_installations(id uuid PRIMARY KEY,generation bigint NOT NULL,binding_id uuid NOT NULL);
CREATE TABLE private.push_bindings(
  id uuid PRIMARY KEY,user_id uuid,installation_id uuid,generation bigint,
  revoke_sha256 text NOT NULL CHECK(revoke_sha256 ~ '^[a-f0-9]{64}$'),
  revoked_at timestamptz,created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.push_tokens ADD COLUMN binding_id uuid REFERENCES private.push_bindings(id);
CREATE INDEX push_tokens_binding_id ON public.push_tokens(binding_id);
REVOKE ALL ON private.push_installations,private.push_bindings FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.create_push_binding(_binding_id uuid,_installation_id uuid,_generation bigint,_revoke_sha256 text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _uid uuid:=auth.uid(); _existing private.push_bindings%ROWTYPE; _install private.push_installations%ROWTYPE;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='28000'; END IF;
  IF _binding_id IS NULL OR _installation_id IS NULL OR _generation IS NULL OR _generation<1
    OR _revoke_sha256 IS NULL OR _revoke_sha256 !~ '^[a-f0-9]{64}$' THEN
    RAISE EXCEPTION 'invalid push binding' USING ERRCODE='22023';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('kc:push-install:'||_installation_id::text,0));
  -- Revoke can arrive first while an offline logout races an earlier create.
  INSERT INTO private.push_bindings(id,user_id,installation_id,generation,revoke_sha256)
    VALUES(_binding_id,_uid,_installation_id,_generation,_revoke_sha256) ON CONFLICT(id) DO NOTHING;
  SELECT * INTO _existing FROM private.push_bindings WHERE id=_binding_id FOR UPDATE;
  IF _existing.revoked_at IS NOT NULL OR _existing.user_id IS DISTINCT FROM _uid
    OR _existing.installation_id IS DISTINCT FROM _installation_id OR _existing.generation IS DISTINCT FROM _generation
    OR _existing.revoke_sha256<>_revoke_sha256 THEN
    RAISE EXCEPTION 'push binding revoked or conflicting' USING ERRCODE='55000';
  END IF;
  SELECT * INTO _install FROM private.push_installations WHERE id=_installation_id FOR UPDATE;
  IF FOUND THEN
    IF _install.generation>_generation OR (_install.generation=_generation AND _install.binding_id<>_binding_id) THEN
      RAISE EXCEPTION 'stale push generation' USING ERRCODE='55000';
    END IF;
    IF _install.binding_id<>_binding_id THEN
      UPDATE private.push_bindings SET revoked_at=coalesce(revoked_at,clock_timestamp()) WHERE id=_install.binding_id;
      DELETE FROM public.push_tokens WHERE binding_id=_install.binding_id;
    END IF;
  END IF;
  INSERT INTO private.push_installations VALUES(_installation_id,_generation,_binding_id)
  ON CONFLICT(id) DO UPDATE SET generation=excluded.generation,binding_id=excluded.binding_id;
  RETURN true;
END;
$$;

CREATE FUNCTION public.register_push_token(_binding_id uuid,_token text,_platform text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _binding private.push_bindings%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='28000'; END IF;
  SELECT * INTO _binding FROM private.push_bindings WHERE id=_binding_id AND user_id=auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'push binding not owned' USING ERRCODE='42501'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('kc:push-install:'||_binding.installation_id::text,0));
  SELECT * INTO _binding FROM private.push_bindings WHERE id=_binding_id FOR UPDATE;
  IF _binding.revoked_at IS NOT NULL OR NOT EXISTS(SELECT 1 FROM private.push_installations
    WHERE id=_binding.installation_id AND binding_id=_binding_id AND generation=_binding.generation) THEN
    RAISE EXCEPTION 'push binding revoked' USING ERRCODE='55000';
  END IF;
  IF _token IS NULL OR length(_token) NOT BETWEEN 10 AND 4096 OR _platform NOT IN('ios','android') THEN
    RAISE EXCEPTION 'invalid push token' USING ERRCODE='22023';
  END IF;
  INSERT INTO public.push_tokens(token,user_id,platform,updated_at,binding_id)
    VALUES(_token,_binding.user_id,_platform,clock_timestamp(),_binding_id)
  ON CONFLICT(token) DO UPDATE SET user_id=excluded.user_id,platform=excluded.platform,
    updated_at=excluded.updated_at,binding_id=excluded.binding_id;
  RETURN true;
END;
$$;

CREATE FUNCTION public.revoke_push_binding(_binding_id uuid,_revoke_secret text,_legacy_token text DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _hash text; _stored_hash text;
BEGIN
  IF _binding_id IS NULL OR _revoke_secret IS NULL OR _revoke_secret !~ '^[a-f0-9]{64}$' THEN RETURN false; END IF;
  _hash:=encode(sha256(convert_to(_revoke_secret,'UTF8')),'hex');
  INSERT INTO private.push_bindings(id,revoke_sha256,revoked_at) VALUES(_binding_id,_hash,clock_timestamp())
    ON CONFLICT(id) DO NOTHING;
  SELECT revoke_sha256 INTO _stored_hash FROM private.push_bindings WHERE id=_binding_id FOR UPDATE;
  IF _stored_hash<>_hash THEN RETURN false; END IF;
  UPDATE private.push_bindings SET revoked_at=coalesce(revoked_at,clock_timestamp()) WHERE id=_binding_id;
  DELETE FROM public.push_tokens WHERE binding_id=_binding_id;
  -- A legacy FCM token is already an unguessable installation capability. It may
  -- remove only its unbound predecessor, never a newer signed-in registration.
  IF _legacy_token IS NOT NULL AND length(_legacy_token) BETWEEN 10 AND 4096 THEN
    DELETE FROM public.push_tokens WHERE token=_legacy_token AND binding_id IS NULL;
  END IF;
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.register_fcm_token(_token text,_platform text DEFAULT 'android')
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF _token IS NULL OR length(_token)<10 THEN RETURN; END IF;
  INSERT INTO public.push_tokens(token,user_id,platform,updated_at) VALUES(_token,auth.uid(),coalesce(_platform,'android'),now())
  ON CONFLICT(token) DO UPDATE SET user_id=excluded.user_id,platform=excluded.platform,updated_at=now()
    WHERE push_tokens.binding_id IS NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.create_push_binding(uuid,uuid,bigint,text) FROM PUBLIC,anon,service_role;
REVOKE ALL ON FUNCTION public.register_push_token(uuid,text,text) FROM PUBLIC,anon,service_role;
REVOKE ALL ON FUNCTION public.revoke_push_binding(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_push_binding(uuid,uuid,bigint,text),public.register_push_token(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_push_binding(uuid,text,text) TO anon,authenticated;
