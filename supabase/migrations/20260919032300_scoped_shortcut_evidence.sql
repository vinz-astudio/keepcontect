-- App-open Shortcuts use a revocable, subject-bound collector credential.
-- Legacy heartbeat URLs remain diagnostic-only. The public transport cannot
-- choose an owner, event class, historical timestamp, or collector sequence.
CREATE OR REPLACE FUNCTION public.record_shortcut_passive_evidence(
  _binding_id uuid, _credential text, _event_id uuid
) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE
  _binding private.passive_collector_bindings%ROWTYPE;
  _existing private.passive_evidence_events%ROWTYPE;
  _sequence bigint;
  _observed_at timestamptz;
BEGIN
  IF _event_id IS NULL THEN RETURN 'invalid'; END IF;
  SELECT * INTO _binding FROM private.passive_collector_bindings
  WHERE id = _binding_id FOR UPDATE;
  IF NOT FOUND THEN RETURN 'unregistered_binding'; END IF;
  IF _binding.surface_type <> 'shortcut' THEN RETURN 'invalid'; END IF;

  -- Serialize allocation on the binding. Concurrent requests, including ones
  -- arriving in the same millisecond, must not collide on sequence numbers.
  _sequence := _binding.sequence_cursor + 1;
  _observed_at := clock_timestamp();
  SELECT * INTO _existing FROM private.passive_evidence_events WHERE event_id = _event_id;
  IF FOUND AND _existing.binding_id = _binding_id THEN
    _sequence := _existing.collector_sequence;
    _observed_at := _existing.observed_at;
  END IF;

  -- Shared validation checks the credential/revocation before idempotency,
  -- enforces the active monitoring epoch, and never resolves an alert.
  RETURN private.record_passive_evidence(
    _binding.user_id,_binding_id,_credential,false,_event_id,_sequence,_observed_at,
    'direct_device_use','passive-qualification-v1',NULL,'{"interaction":true}'::jsonb,
    NULL,NULL,false
  );
END;
$$;
REVOKE ALL ON FUNCTION public.record_shortcut_passive_evidence(uuid,text,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_shortcut_passive_evidence(uuid,text,uuid) TO service_role;
