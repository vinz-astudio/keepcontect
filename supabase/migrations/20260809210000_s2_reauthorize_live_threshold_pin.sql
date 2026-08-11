-- S2 · re-authorize the adaptive-shadow live-definition pin (ADR-0037).
--
-- Why this exists
-- ---------------
-- The adaptive-shadow evaluator is deliberately fail-closed: its model config
-- carries `emergency.expected_live_definition_sha256`, and the operational
-- cycle refuses to run when the live `private.silence_threshold(uuid)` source
-- does not hash to that pin. The pin was last authorized on 2026-07-29.
--
-- On 2026-08-04, ADR-0037 legitimately rewrote `private.silence_threshold` to
-- read `public.account_normal_bounds`
-- (`20260804135728_silence_threshold_reads_normal_bounds.sql` and
-- `20260804190000_account_normal_upper_bound.sql`). Neither migration
-- re-authorized the pin, and no later migration did either. The guard has been
-- firing correctly ever since — the live definition really did change — but for
-- an authorized reason nobody recorded. Net effect: the shadow evaluator has
-- been hard-blocked with `shadow_live_hash_mismatch` and can record nothing.
--
-- This migration records the missing authorization. It does NOT weaken the
-- guard:
--   * it refuses to run unless the live definition hashes to exactly the value
--     authorized below, so environment drift fails loudly instead of being
--     blessed;
--   * it moves the pin to that one specific definition rather than widening any
--     allowlist;
--   * `private.shadow_live_definition_matches` keeps its existing legacy
--     compatibility branch untouched, so retired pins still only accept the
--     retired definitions they were issued against;
--   * tampered or unknown definitions remain rejected.
--
-- Append-only: no historical migration is edited.

DO $migration$
DECLARE
  _retired_pin constant text :=
    '1907d59473d274d46a0e8e0b9ce8027037b4494b0dddf073cb46abf67db92e21';
  _authorized_pin constant text :=
    'c3efc6cc664dc334166a034651ff584d4c7766d80775c3fe3bc012eb97a9b150';
  _constraint_name constant text :=
    'alert_model_versions_candidate_evaluator_contract_check';
  _live_hash text;
  _validator_definition text;
  _constraint_definition text;
  _occurrences integer;
BEGIN
  SELECT encode(
           extensions.digest(
             replace(
               pg_get_functiondef('private.silence_threshold(uuid)'::regprocedure),
               E'\r\n',
               E'\n'
             ),
             'sha256'
           ),
           'hex'
         )
    INTO _live_hash;

  IF _live_hash IS DISTINCT FROM _authorized_pin THEN
    RAISE EXCEPTION
      'refusing to re-authorize the shadow live pin: private.silence_threshold hashes to %, which is not the authorized definition %',
      _live_hash, _authorized_pin;
  END IF;

  -- 1. Config validator.
  _validator_definition :=
    pg_get_functiondef('private.alert_candidate_config_is_valid(jsonb)'::regprocedure);
  _occurrences :=
    (length(_validator_definition) - length(replace(_validator_definition, _retired_pin, '')))
    / length(_retired_pin);

  IF _occurrences <> 1 THEN
    RAISE EXCEPTION
      'expected exactly one retired pin inside private.alert_candidate_config_is_valid, found %',
      _occurrences;
  END IF;

  EXECUTE replace(_validator_definition, _retired_pin, _authorized_pin);

  -- 2. Table contract check.
  SELECT pg_get_constraintdef(oid)
    INTO _constraint_definition
  FROM pg_constraint
  WHERE conname = _constraint_name
    AND conrelid = 'public.alert_model_versions'::regclass;

  IF _constraint_definition IS NULL THEN
    RAISE EXCEPTION 'constraint % is missing from public.alert_model_versions', _constraint_name;
  END IF;

  IF strpos(_constraint_definition, _retired_pin) = 0 THEN
    RAISE EXCEPTION 'constraint % does not carry the retired pin; refusing to guess', _constraint_name;
  END IF;

  EXECUTE format(
    'ALTER TABLE public.alert_model_versions DROP CONSTRAINT %I',
    _constraint_name
  );
  EXECUTE format(
    'ALTER TABLE public.alert_model_versions ADD CONSTRAINT %I %s',
    _constraint_name,
    replace(_constraint_definition, _retired_pin, _authorized_pin)
  );

  -- 3. Narrow, explicit re-authorization of stored model versions that were
  --    pinned to the retired definition. Rows carrying any other pin are left
  --    alone and keep failing closed until they are authorized on their own
  --    evidence.
  UPDATE public.alert_model_versions
     SET config = jsonb_set(
           config,
           '{emergency,expected_live_definition_sha256}',
           to_jsonb(_authorized_pin)
         )
   WHERE config #>> '{emergency,expected_live_definition_sha256}' = _retired_pin;
END
$migration$;
