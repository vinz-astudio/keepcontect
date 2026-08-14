-- ADR-0042 package 2: bound, revocable, positive-only passive evidence.

CREATE TABLE private.passive_surface_registry (
  surface_type text PRIMARY KEY,
  arrival_allowance interval NOT NULL CHECK (arrival_allowance >= interval '0'),
  expected_contact_cadence interval,
  d_floor_minutes integer NOT NULL CHECK (d_floor_minutes > 0),
  h_floor_minutes integer NOT NULL CHECK (h_floor_minutes > 0),
  supports_history boolean NOT NULL,
  allowed_evidence_classes text[] NOT NULL,
  CHECK (expected_contact_cadence IS NULL OR expected_contact_cadence > interval '0')
);

INSERT INTO private.passive_surface_registry VALUES
  ('tauri_native',       interval '12 minutes', interval '5 minutes',  10,  30, true,  ARRAY['direct_device_use']),
  ('tauri_native_linux', interval '12 minutes', interval '5 minutes', 360, 720, false, ARRAY['direct_device_use']),
  ('android_native',     interval '35 minutes', interval '15 minutes', 35, 120, true,  ARRAY['direct_device_use','personal_device_motion','power_transition']),
  ('ios_native',         interval '90 minutes', interval '60 minutes', 60, 720, true,  ARRAY['direct_device_use','personal_device_motion','power_transition']),
  ('pwa_browser',        interval '5 minutes',  NULL,                 360, 720, false, ARRAY['direct_device_use','explicit_self_activity']),
  ('shortcut',           interval '5 minutes',  NULL,                 360, 720, false, ARRAY['direct_device_use']);

CREATE TABLE private.passive_collector_bindings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.passive_checkin_accounts(user_id) ON DELETE CASCADE,
  collector_instance_id text NOT NULL CHECK (length(btrim(collector_instance_id)) BETWEEN 1 AND 128),
  surface_type text NOT NULL REFERENCES private.passive_surface_registry(surface_type) ON DELETE RESTRICT,
  collector_contract text NOT NULL CHECK (length(btrim(collector_contract)) BETWEEN 1 AND 80),
  client_version text NOT NULL CHECK (length(btrim(client_version)) BETWEEN 1 AND 80),
  credential_sha256 text NOT NULL CHECK (credential_sha256 ~ '^[a-f0-9]{64}$'),
  credential_version integer NOT NULL DEFAULT 1 CHECK (credential_version > 0),
  sequence_cursor bigint NOT NULL DEFAULT -1 CHECK (sequence_cursor >= -1),
  time_epoch integer NOT NULL DEFAULT 1 CHECK (time_epoch > 0),
  last_contact_at timestamptz,
  last_evidence_at timestamptz,
  permission_state text NOT NULL DEFAULT 'not_applicable'
    CHECK (permission_state IN ('granted','denied','revoked','not_applicable')),
  capability_state text NOT NULL DEFAULT 'ok'
    CHECK (capability_state IN ('ok','unsupported','degraded')),
  health_reported_at timestamptz,
  bound_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  revoked_at timestamptz,
  revocation_reason text,
  CHECK (revoked_at IS NULL OR revoked_at >= bound_at)
);

CREATE UNIQUE INDEX passive_collector_bindings_one_active_instance
  ON private.passive_collector_bindings(collector_instance_id)
  WHERE revoked_at IS NULL;
CREATE INDEX passive_collector_bindings_user_active
  ON private.passive_collector_bindings(user_id) WHERE revoked_at IS NULL;

CREATE TABLE private.passive_evidence_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.passive_checkin_accounts(user_id) ON DELETE CASCADE,
  binding_id uuid NOT NULL REFERENCES private.passive_collector_bindings(id) ON DELETE RESTRICT,
  epoch_id uuid NOT NULL REFERENCES public.passive_monitoring_epochs(id) ON DELETE RESTRICT,
  window_id uuid NOT NULL REFERENCES public.passive_checkin_windows(id) ON DELETE RESTRICT,
  event_id uuid NOT NULL UNIQUE,
  collector_sequence bigint NOT NULL CHECK (collector_sequence >= 0),
  collector_time_epoch integer NOT NULL CHECK (collector_time_epoch > 0),
  observed_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  evidence_class text NOT NULL
    CHECK (evidence_class IN ('direct_device_use','personal_device_motion','power_transition','explicit_self_activity')),
  qualification_policy_version text NOT NULL,
  collector_contract text NOT NULL,
  client_version text NOT NULL,
  correlation_id text,
  qualification_facts jsonb NOT NULL DEFAULT '{}'::jsonb,
  query_started_at timestamptz,
  query_ended_at timestamptz,
  query_succeeded boolean NOT NULL DEFAULT false,
  payload_sha256 text NOT NULL CHECK (payload_sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (binding_id, collector_sequence),
  CHECK ((query_started_at IS NULL) = (query_ended_at IS NULL)),
  CHECK (query_started_at IS NULL OR query_started_at <= query_ended_at)
);

CREATE INDEX passive_evidence_events_user_observed
  ON private.passive_evidence_events(user_id, observed_at DESC);

CREATE TABLE private.passive_evidence_incidents (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid REFERENCES public.passive_checkin_accounts(user_id) ON DELETE CASCADE,
  binding_id uuid REFERENCES private.passive_collector_bindings(id) ON DELETE CASCADE,
  event_id uuid,
  collector_sequence bigint,
  reason text NOT NULL CHECK (reason IN ('event_conflict','sequence_conflict','credential_mismatch','revoked_binding')),
  incoming_payload_sha256 text,
  existing_payload_sha256 text,
  received_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE private.passive_surface_health_intervals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.passive_checkin_accounts(user_id) ON DELETE CASCADE,
  binding_id uuid NOT NULL REFERENCES private.passive_collector_bindings(id) ON DELETE CASCADE,
  started_at timestamptz NOT NULL,
  ended_at timestamptz,
  reason text NOT NULL CHECK (reason IN (
    'silent','permission_denied','permission_revoked','capability_unsupported','capability_degraded'
  )),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK (ended_at IS NULL OR ended_at >= started_at)
);

ALTER TABLE private.passive_surface_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.passive_collector_bindings ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.passive_evidence_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.passive_evidence_incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.passive_surface_health_intervals ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION private.reject_passive_evidence_mutation()
RETURNS trigger LANGUAGE plpgsql SET search_path TO '' AS $$
BEGIN
  RAISE EXCEPTION 'passive evidence events are immutable' USING ERRCODE = '55000';
END;
$$;
CREATE TRIGGER passive_evidence_events_immutable
BEFORE UPDATE ON private.passive_evidence_events
FOR EACH ROW EXECUTE FUNCTION private.reject_passive_evidence_mutation();

CREATE FUNCTION private.passive_expected_contract(_surface_type text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO '' AS $$
  SELECT CASE _surface_type
    WHEN 'android_native' THEN 'android-passive-evidence-v1'
    WHEN 'ios_native' THEN 'ios-passive-evidence-v1'
    WHEN 'tauri_native' THEN 'tauri-passive-evidence-v1'
    WHEN 'tauri_native_linux' THEN 'tauri-linux-foreground-v1'
    WHEN 'pwa_browser' THEN 'pwa-interaction-v1'
    WHEN 'shortcut' THEN 'shortcut-app-open-v1'
  END
$$;

CREATE FUNCTION private.passive_arrival_allowance(_user_id uuid)
RETURNS interval LANGUAGE sql STABLE SET search_path TO '' AS $$
  SELECT coalesce(max(registry.arrival_allowance), interval '0')
  FROM private.passive_collector_bindings AS binding
  JOIN private.passive_surface_registry AS registry USING (surface_type)
  WHERE binding.user_id = _user_id AND binding.revoked_at IS NULL
$$;

CREATE FUNCTION public.bind_passive_collector(
  _collector_instance_id text,
  _surface_type text,
  _collector_contract text,
  _client_version text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE
  _uid uuid := auth.uid();
  _credential text;
  _binding_id uuid;
  _now timestamptz := clock_timestamp();
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000'; END IF;
  IF _collector_instance_id IS NULL OR length(btrim(_collector_instance_id)) NOT BETWEEN 1 AND 128
     OR _client_version IS NULL OR length(btrim(_client_version)) NOT BETWEEN 1 AND 80 THEN
    RAISE EXCEPTION 'invalid collector identity' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM private.passive_surface_registry WHERE surface_type = _surface_type)
     OR _collector_contract IS DISTINCT FROM private.passive_expected_contract(_surface_type) THEN
    RAISE EXCEPTION 'unsupported surface or collector contract' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.passive_checkin_accounts
    WHERE user_id = _uid AND active_epoch_id IS NOT NULL AND engine_mode IN ('shadow','passive_checkin')
  ) THEN RAISE EXCEPTION 'passive contract is not active' USING ERRCODE = '55000'; END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('kc-passive-collector'), pg_catalog.hashtext(btrim(_collector_instance_id))
  );
  IF EXISTS (
    SELECT 1 FROM private.passive_collector_bindings
    WHERE collector_instance_id = btrim(_collector_instance_id) AND revoked_at IS NULL AND user_id <> _uid
  ) THEN RAISE EXCEPTION 'collector is bound to another account' USING ERRCODE = '23505'; END IF;

  UPDATE private.passive_collector_bindings
  SET revoked_at = _now, revocation_reason = 'credential_rotated', permission_state = 'revoked'
  WHERE collector_instance_id = btrim(_collector_instance_id) AND revoked_at IS NULL;

  _credential := encode(extensions.gen_random_bytes(32), 'hex');
  INSERT INTO private.passive_collector_bindings (
    user_id, collector_instance_id, surface_type, collector_contract, client_version,
    credential_sha256, bound_at
  ) VALUES (
    _uid, btrim(_collector_instance_id), _surface_type, _collector_contract, btrim(_client_version),
    encode(extensions.digest(_credential, 'sha256'), 'hex'), _now
  ) RETURNING id INTO _binding_id;

  UPDATE public.passive_checkin_windows
  SET arrival_deadline = window_end + private.passive_arrival_allowance(_uid)
  WHERE user_id = _uid AND outcome = 'pending';

  RETURN jsonb_build_object(
    'binding_id', _binding_id, 'credential', _credential, 'credential_version', 1,
    'surface_type', _surface_type, 'collector_contract', _collector_contract
  );
END;
$$;

CREATE FUNCTION public.revoke_passive_collector(_binding_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _uid uuid := auth.uid(); _changed boolean;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000'; END IF;
  UPDATE private.passive_collector_bindings
  SET revoked_at = clock_timestamp(), revocation_reason = 'user_revoked', permission_state = 'revoked'
  WHERE id = _binding_id AND user_id = _uid AND revoked_at IS NULL;
  _changed := FOUND;
  UPDATE public.passive_checkin_windows
  SET arrival_deadline = window_end + private.passive_arrival_allowance(_uid)
  WHERE user_id = _uid AND outcome = 'pending';
  RETURN _changed;
END;
$$;

CREATE FUNCTION private.passive_payload_sha256(
  _binding_id uuid, _event_id uuid, _sequence bigint, _observed_at timestamptz,
  _evidence_class text, _qualification_policy_version text, _correlation_id text,
  _qualification_facts jsonb, _query_started_at timestamptz, _query_ended_at timestamptz,
  _query_succeeded boolean
)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO '' AS $$
  SELECT encode(extensions.digest(
    jsonb_build_object(
      'binding_id', _binding_id, 'event_id', _event_id, 'sequence', _sequence,
      'observed_at', _observed_at, 'evidence_class', _evidence_class,
      'qualification_policy_version', _qualification_policy_version,
      'correlation_id', _correlation_id, 'qualification_facts', _qualification_facts,
      'query_started_at', _query_started_at, 'query_ended_at', _query_ended_at,
      'query_succeeded', _query_succeeded
    )::text, 'sha256'), 'hex')
$$;

CREATE FUNCTION private.record_passive_evidence(
  _subject_id uuid, _binding_id uuid, _credential text, _authenticated_path boolean,
  _event_id uuid, _sequence bigint, _observed_at timestamptz, _evidence_class text,
  _qualification_policy_version text, _correlation_id text, _qualification_facts jsonb,
  _query_started_at timestamptz, _query_ended_at timestamptz, _query_succeeded boolean
)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE
  _binding private.passive_collector_bindings%ROWTYPE;
  _registry private.passive_surface_registry%ROWTYPE;
  _existing private.passive_evidence_events%ROWTYPE;
  _now timestamptz := clock_timestamp();
  _payload_sha text;
  _epoch_id uuid;
  _contract_id uuid;
  _started_at timestamptz;
  _interval_minutes integer;
  _ordinal bigint;
  _window_id uuid;
  _window_start timestamptz;
  _window_end timestamptz;
  _event_row_id uuid;
BEGIN
  SELECT * INTO _binding FROM private.passive_collector_bindings WHERE id = _binding_id FOR UPDATE;
  IF NOT FOUND OR _binding.user_id <> _subject_id THEN RETURN 'unregistered_binding'; END IF;
  IF _binding.revoked_at IS NOT NULL THEN
    INSERT INTO private.passive_evidence_incidents(user_id,binding_id,event_id,collector_sequence,reason)
    VALUES (_subject_id,_binding_id,_event_id,_sequence,'revoked_binding');
    RETURN 'revoked';
  END IF;
  IF NOT _authenticated_path AND (
    _credential IS NULL OR encode(extensions.digest(_credential, 'sha256'), 'hex') <> _binding.credential_sha256
  ) THEN
    INSERT INTO private.passive_evidence_incidents(user_id,binding_id,event_id,collector_sequence,reason)
    VALUES (_subject_id,_binding_id,_event_id,_sequence,'credential_mismatch');
    RETURN 'credential_mismatch';
  END IF;
  SELECT * INTO STRICT _registry FROM private.passive_surface_registry WHERE surface_type = _binding.surface_type;
  IF _authenticated_path AND _binding.surface_type <> 'pwa_browser' THEN RETURN 'invalid'; END IF;
  IF _qualification_policy_version IS DISTINCT FROM 'passive-qualification-v1'
     OR NOT (_evidence_class = ANY(_registry.allowed_evidence_classes))
     OR _sequence < 0 OR _observed_at IS NULL
     OR _observed_at > _now + interval '5 minutes'
     OR _observed_at < _now - interval '7 days'
     OR jsonb_typeof(coalesce(_qualification_facts, '{}'::jsonb)) <> 'object'
     OR (_correlation_id IS NOT NULL AND length(_correlation_id) NOT BETWEEN 1 AND 128)
     OR EXISTS (
       SELECT 1 FROM jsonb_object_keys(coalesce(_qualification_facts,'{}'::jsonb)) AS key
       WHERE key NOT IN (
         'interaction','steps_positive','floors_positive','pedestrian','automotive',
         'prior_power_state','new_power_state','stable_for_ms'
       )
     )
     OR ((_query_started_at IS NULL) <> (_query_ended_at IS NULL))
     OR (_query_started_at IS NOT NULL AND _query_started_at > _query_ended_at)
     THEN RETURN 'invalid'; END IF;

  IF _evidence_class = 'direct_device_use' AND coalesce((_qualification_facts->>'interaction')::boolean, false) IS NOT TRUE
     OR _evidence_class = 'personal_device_motion' AND NOT (
       coalesce((_qualification_facts->>'pedestrian')::boolean, false)
       AND NOT coalesce((_qualification_facts->>'automotive')::boolean, false)
       AND (coalesce((_qualification_facts->>'steps_positive')::boolean, false)
            OR coalesce((_qualification_facts->>'floors_positive')::boolean, false))
     )
     OR _evidence_class = 'power_transition' AND NOT (
       _qualification_facts->>'prior_power_state' IN ('charging','not_charging')
       AND _qualification_facts->>'new_power_state' IN ('charging','not_charging')
       AND _qualification_facts->>'prior_power_state' <> _qualification_facts->>'new_power_state'
       AND coalesce((_qualification_facts->>'stable_for_ms')::integer, 0) >= 5000
     ) THEN RETURN 'invalid'; END IF;

  IF _observed_at < _now - interval '5 minutes' AND NOT (
    _registry.supports_history AND _query_succeeded
    AND _query_started_at IS NOT NULL AND _query_ended_at IS NOT NULL
    AND _query_started_at <= _observed_at AND _observed_at <= _query_ended_at
  ) THEN RETURN 'invalid'; END IF;

  _payload_sha := private.passive_payload_sha256(
    _binding_id,_event_id,_sequence,_observed_at,_evidence_class,
    _qualification_policy_version,_correlation_id,coalesce(_qualification_facts,'{}'::jsonb),
    _query_started_at,_query_ended_at,_query_succeeded
  );
  SELECT * INTO _existing FROM private.passive_evidence_events WHERE event_id = _event_id;
  IF FOUND THEN
    IF _existing.binding_id = _binding_id AND _existing.payload_sha256 = _payload_sha THEN
      UPDATE private.passive_collector_bindings SET last_contact_at = _now WHERE id = _binding_id;
      RETURN 'duplicate';
    END IF;
    INSERT INTO private.passive_evidence_incidents(
      user_id,binding_id,event_id,collector_sequence,reason,incoming_payload_sha256,existing_payload_sha256
    ) VALUES (_subject_id,_binding_id,_event_id,_sequence,'event_conflict',_payload_sha,_existing.payload_sha256);
    RETURN 'conflict';
  END IF;
  SELECT * INTO _existing FROM private.passive_evidence_events
  WHERE binding_id = _binding_id AND collector_sequence = _sequence;
  IF FOUND THEN
    INSERT INTO private.passive_evidence_incidents(
      user_id,binding_id,event_id,collector_sequence,reason,incoming_payload_sha256,existing_payload_sha256
    ) VALUES (_subject_id,_binding_id,_event_id,_sequence,'sequence_conflict',_payload_sha,_existing.payload_sha256);
    RETURN 'conflict';
  END IF;

  SELECT epoch.id, epoch.contract_version_id, epoch.started_at, contract.interval_minutes
  INTO _epoch_id, _contract_id, _started_at, _interval_minutes
  FROM public.passive_monitoring_epochs AS epoch
  JOIN public.passive_checkin_contract_versions AS contract ON contract.id = epoch.contract_version_id
  WHERE epoch.user_id = _subject_id AND epoch.ended_at IS NULL;
  IF _epoch_id IS NULL OR _observed_at < _started_at THEN RETURN 'outside_epoch'; END IF;
  _ordinal := floor(extract(epoch FROM (_observed_at - _started_at)) / (_interval_minutes * 60))::bigint;
  _window_start := _started_at + pg_catalog.make_interval(mins => (_ordinal * _interval_minutes)::integer);
  _window_end := _window_start + pg_catalog.make_interval(mins => _interval_minutes);
  INSERT INTO public.passive_checkin_windows(
    user_id,epoch_id,contract_version_id,ordinal,window_start,window_end,arrival_deadline
  ) VALUES (
    _subject_id,_epoch_id,_contract_id,_ordinal,_window_start,_window_end,
    _window_end + private.passive_arrival_allowance(_subject_id)
  ) ON CONFLICT (epoch_id,ordinal) DO NOTHING;
  SELECT id INTO STRICT _window_id FROM public.passive_checkin_windows
  WHERE epoch_id = _epoch_id AND ordinal = _ordinal FOR UPDATE;

  INSERT INTO private.passive_evidence_events(
    user_id,binding_id,epoch_id,window_id,event_id,collector_sequence,collector_time_epoch,
    observed_at,received_at,evidence_class,qualification_policy_version,collector_contract,
    client_version,correlation_id,qualification_facts,query_started_at,query_ended_at,
    query_succeeded,payload_sha256
  ) VALUES (
    _subject_id,_binding_id,_epoch_id,_window_id,_event_id,_sequence,_binding.time_epoch,
    _observed_at,_now,_evidence_class,_qualification_policy_version,_binding.collector_contract,
    _binding.client_version,_correlation_id,coalesce(_qualification_facts,'{}'::jsonb),
    _query_started_at,_query_ended_at,_query_succeeded,_payload_sha
  ) RETURNING id INTO _event_row_id;

  UPDATE public.passive_checkin_windows
  SET outcome = 'checked_in', causal_evidence_id = _event_row_id, finalized_at = _now
  WHERE id = _window_id AND outcome IN ('pending','missed');
  UPDATE private.passive_collector_bindings
  SET sequence_cursor = greatest(sequence_cursor,_sequence), last_contact_at = _now,
      last_evidence_at = greatest(coalesce(last_evidence_at,_observed_at),_observed_at)
  WHERE id = _binding_id;
  RETURN 'inserted';
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
  RETURN 'invalid';
END;
$$;

CREATE FUNCTION public.record_passive_evidence_with_credential(
  _binding_id uuid, _credential text, _event_id uuid, _sequence bigint,
  _observed_at timestamptz, _evidence_class text, _qualification_policy_version text,
  _correlation_id text DEFAULT NULL, _qualification_facts jsonb DEFAULT '{}'::jsonb,
  _query_started_at timestamptz DEFAULT NULL, _query_ended_at timestamptz DEFAULT NULL,
  _query_succeeded boolean DEFAULT false
)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _uid uuid;
BEGIN
  SELECT user_id INTO _uid FROM private.passive_collector_bindings WHERE id = _binding_id;
  IF _uid IS NULL THEN RETURN 'unregistered_binding'; END IF;
  RETURN private.record_passive_evidence(
    _uid,_binding_id,_credential,false,_event_id,_sequence,_observed_at,_evidence_class,
    _qualification_policy_version,_correlation_id,_qualification_facts,
    _query_started_at,_query_ended_at,_query_succeeded
  );
END;
$$;

CREATE FUNCTION public.record_authenticated_passive_evidence(
  _binding_id uuid, _event_id uuid, _sequence bigint, _observed_at timestamptz,
  _evidence_class text, _qualification_policy_version text,
  _correlation_id text DEFAULT NULL, _qualification_facts jsonb DEFAULT '{}'::jsonb
)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _uid uuid := auth.uid();
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000'; END IF;
  RETURN private.record_passive_evidence(
    _uid,_binding_id,NULL,true,_event_id,_sequence,_observed_at,_evidence_class,
    _qualification_policy_version,_correlation_id,_qualification_facts,NULL,NULL,false
  );
END;
$$;

CREATE FUNCTION private.prune_passive_checkin_data()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE _evidence bigint; _incidents bigint; _health bigint; _windows bigint;
BEGIN
  DELETE FROM private.passive_evidence_events WHERE received_at < clock_timestamp() - interval '35 days';
  GET DIAGNOSTICS _evidence = ROW_COUNT;
  DELETE FROM private.passive_evidence_incidents WHERE received_at < clock_timestamp() - interval '35 days';
  GET DIAGNOSTICS _incidents = ROW_COUNT;
  DELETE FROM private.passive_surface_health_intervals
  WHERE ended_at IS NOT NULL AND ended_at < clock_timestamp() - interval '90 days';
  GET DIAGNOSTICS _health = ROW_COUNT;
  DELETE FROM public.passive_checkin_windows AS w
  WHERE w.window_end < clock_timestamp() - interval '90 days'
    AND NOT EXISTS (SELECT 1 FROM private.passive_alert_causal_windows causal WHERE causal.window_id = w.id);
  GET DIAGNOSTICS _windows = ROW_COUNT;
  RETURN jsonb_build_object('evidence',_evidence,'incidents',_incidents,'health',_health,'windows',_windows);
END;
$$;

REVOKE ALL ON TABLE private.passive_surface_registry FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE private.passive_collector_bindings FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE private.passive_evidence_events FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE private.passive_evidence_incidents FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE private.passive_surface_health_intervals FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.bind_passive_collector(text,text,text,text) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.revoke_passive_collector(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.record_authenticated_passive_evidence(uuid,uuid,bigint,timestamptz,text,text,text,jsonb) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.record_passive_evidence_with_credential(uuid,text,uuid,bigint,timestamptz,text,text,text,jsonb,timestamptz,timestamptz,boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.prune_passive_checkin_data() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bind_passive_collector(text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_passive_collector(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_authenticated_passive_evidence(uuid,uuid,bigint,timestamptz,text,text,text,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_passive_evidence_with_credential(uuid,text,uuid,bigint,timestamptz,text,text,text,jsonb,timestamptz,timestamptz,boolean) TO service_role;
GRANT EXECUTE ON FUNCTION private.prune_passive_checkin_data() TO service_role;
