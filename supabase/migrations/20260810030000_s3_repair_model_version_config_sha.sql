-- Repair · a model version must never disagree with its own digest.
--
-- What went wrong
-- ---------------
-- 20260809210000_s2_reauthorize_live_threshold_pin re-pinned
-- `emergency.expected_live_definition_sha256` inside `config`, but did not
-- recompute `config_sha256`. Every row it touched therefore stopped matching
-- its own integrity digest.
--
-- `private.run_adaptive_alert_shadow_cycle` validates that digest before doing
-- anything, so the cycle raised `shadow_version_validation_failed` and started
-- burning the runtime's failure budget — which is exactly how coverage
-- collection died on 2026-08-04 in the first place, for a different reason.
--
-- Why the tests did not catch it: `public.alert_model_versions` is empty on a
-- fresh local base (ADR-0038 leaves activation to the environment), so that
-- UPDATE matched zero rows locally and the branch was never executed. The
-- defect could only appear where real rows exist.
--
-- This repair is idempotent and touches only rows whose stored digest disagrees
-- with their config. It changes no config, no pin, and no runtime state.
--
-- Append-only: the deployed migration is not edited.

UPDATE public.alert_model_versions
SET config_sha256 = encode(extensions.digest(config::text, 'sha256'), 'hex')
WHERE config_sha256 IS DISTINCT FROM encode(extensions.digest(config::text, 'sha256'), 'hex');
