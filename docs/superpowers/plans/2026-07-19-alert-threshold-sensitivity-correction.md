# Alert Threshold Sensitivity Correction Implementation Plan

> **For Codex:** Execute this plan task-by-task with TDD. ADR-0022 is binding. Do not deploy from this implementation task.

**Goal:** Restore the user-visible `+0m / +45m / +90m` sensitivity contract on a deterministic 1.5-hour neutral base without allowing learned profiles or external AI to regain live safety authority.

**Architecture:** One append-only migration replaces only `private.silence_threshold(uuid)`. The function continues to read `user_settings.sensitivity`, keeps `SECURITY DEFINER SET search_path = ''`, and remains non-executable by `PUBLIC`, `anon`, and `authenticated`. Frontend offline/helper arithmetic uses matching additive presets. All server consumers continue to call the same private function.

**Tech Stack:** PostgreSQL/Supabase migrations + pgTAP, React/Vite/TypeScript, Vitest.

**Cost boundary:** Existing included subscriptions and local/open-source tools only; incremental external spend US$0. No Supabase branch creation.

## Pre-mutation impact matrix

Sources reviewed: Product Requirement, System Design, Database Schema, Feature Modules, Alert System, Usual Behavior Model, Sleep Window, Monitoring Direction, Scenario Matrix, repository consumers, and a deidentified read-only production snapshot on 2026-07-19.

| Area | Current authority / production evidence | Intended effect | Required invariant |
|---|---|---|---|
| `profiles` | Identity and `consent_data_sharing`; 10 production rows | No write and no threshold read | Consent remains authoritative for any future external AI call |
| `user_settings` | Stores sensitivity; 6 balanced and 4 low rows | Balanced 3h -> 2.25h; low 6h -> 3h; future high remains 1.5h | Missing/unknown setting defaults to balanced 2.25h |
| `user_activity_profiles` | 10 stored learned profiles; 8 belong to users without current sharing consent | No read by live threshold; no row mutation | Learned threshold/profile data remains quarantined; metadata may still be displayed by Routine |
| `private.silence_threshold` | Production returns absolute 1.5/3/6h | Return neutral base 1.5h plus 0/.75/1.5h | No profile/AI dependency; exact high/balanced/low and legacy alias mapping |
| `public.process_escalations` | Calls threshold for silence open/auto-resolve; dark-device remains fixed 18h | Earlier silence eligibility for balanced/low | Sleep gate, monitored membership, trusted v2 evidence, cooldown, stages unchanged |
| `private.is_in_sleep_window` | Independent local-wall-clock gate | No code change | Sleep still pauses alert logic independently of threshold arithmetic |
| `public.my_routine_status` / Routine UI | Displays threshold from server; separately reads profile explanation/confidence | Shows exact corrected server threshold after DB migration | Local fallback uses identical additive math; profile metadata never becomes threshold |
| `public.get_group_activity(_view)` / Watch & Group | Exposes `threshold_hours` through same private function; status bands use separate fixed 6/24h presentation buckets | Threshold field becomes exact corrected value | Privacy visibility, `monitored`/`watching`, alert state, and activity evidence unchanged |
| `public.gm_list_clients` / GM | Uses alert truth plus fixed 6/24h status bands; does not call threshold | No direct change; indirect alerts may occur earlier | GM permissions, client data, and fixed descriptive bands unchanged |
| dark-device / SOS / check-in | Dark device fixed at 18h; SOS immediate; check-in schedule uses its own task/sleep rules | No change | No sensitivity coupling introduced |

Production function privileges are currently correct: `private.silence_threshold` is `SECURITY DEFINER`, empty `search_path`, and not executable by anon/authenticated. Public consumer functions retain their existing grants.

## Task 1: Write failing frontend contract

**Files:**
- Modify: `src/features/baseline/usualModel.test.ts`

1. Add an exact contract test using neutral base `1.5` and expecting `1.5`, `2.25`, and `3` hours.
2. Run `npm test -- src/features/baseline/usualModel.test.ts`.
3. Confirm RED because current presets produce `1.75`, `2`, and `3`.

## Task 2: Write failing migration and consumer contract

**Files:**
- Create: `src/features/baseline/thresholdContractMigration.test.ts`

1. Require exactly one append-only migration containing `correct_gate1_sensitivity_contract`.
2. Assert exact high/sensitive `1.5h`, balanced `2.25h`, low/relaxed `3h` mappings.
3. Assert the replacement function does not mention `user_activity_profiles`, AI/Gemini, or hourly learned thresholds.
4. Assert `SECURITY DEFINER`, empty `search_path`, and execute revocation.
5. Assert established consumers remain in Gate 1 and still call `private.silence_threshold`, while GM remains deliberately threshold-independent.
6. Run focused Vitest and confirm RED because the correction migration does not exist.

## Task 3: Implement the minimal correction

**Files:**
- Modify: `src/features/baseline/types.ts`
- Create via Supabase CLI: `supabase/migrations/*_correct_gate1_sensitivity_contract.sql`

1. Run `npm exec --package=supabase@2.109.1 -- supabase migration new correct_gate1_sensitivity_contract`.
2. Replace only `private.silence_threshold(uuid)` in the generated migration.
3. Preserve `STABLE SECURITY DEFINER SET search_path = ''` and revoke execution from `PUBLIC`, `anon`, and `authenticated`.
4. Change frontend buffers to `0`, `.75`, `1.5`; do not change the neutral model builder.
5. Re-run focused Vitest and confirm GREEN.

## Task 4: Add real SQL behavior and profile-quarantine tests

**Files:**
- Modify: `supabase/tests/routine_safety.sql`

1. Extend pgTAP plan for exact high/balanced/low results.
2. Insert/update only synthetic test settings/profile rows inside the rolled-back test transaction.
3. Prove changing `user_activity_profiles.hourly_thresholds` cannot change `private.silence_threshold`.
4. Prove the function remains non-executable by authenticated users while public consumers keep their expected contract.
5. Run the established zero-cost local PostgreSQL/Supabase test path and confirm all pgTAP assertions pass.

## Task 5: Full regression verification

1. Run focused Vitest:
   `npm test -- src/features/baseline/usualModel.test.ts src/features/baseline/thresholdContractMigration.test.ts src/features/baseline/routineSafetyMigration.test.ts`
2. Run `npm run typecheck`.
3. Run full `npm test`.
4. Run `npm run build`.
5. Run `npm run local:gate:static`.
6. Run `git diff --check` and inspect the entire diff.

## Task 6: Independent review and truth write-back

1. Give Claude the accepted ADR, impact matrix, full diff, and verification evidence in a fresh included-subscription CLI session with no write authority.
2. Resolve at most one bounded repair round; rerun affected verification.
3. Update Database Schema, System Design, Alert System, Usual Behavior Model, Scenario Matrix, and Dev Log with final candidate-vs-production boundaries.
4. Commit only the scoped implementation files. A separate release task may push/apply only after all gates pass.
