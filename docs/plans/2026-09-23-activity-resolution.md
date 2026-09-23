# Activity resolution and optional guardian pattern

Authority: user directive on 2026-09-23, recorded as Keep Contact ADR-0045.

## Intended behavior

- Ordinary silence, dark-device and concern alerts close on qualified activity from their subject after the alert opened. All escalation stages use the same rule.
- Keep the existing canonical v2 evidence qualification. Historical uploads, heartbeat/cache values, another person's actions and future observations do not close an alert.
- Only an active designated guardian can enable a pattern requirement for their own ward. Store the setting outside public writable relationship columns. Default off; any active guardian requirement wins. Removing/revoking a relationship removes its authority.
- Require an existing subject pattern before enabling the option. The subject sees who enabled it. The server rejects a plain confirmation when pattern is required; the legacy resolution RPC must enforce the same rule.
- A simple “I am safe” button is the default confirmation in the app and existing native/web notification actions. Pattern setup is optional for ordinary users; retain existing encryption keys and manual settings/practice.
- Active SOS retains explicit cancellation. No automatic safety claim from heartbeat or technical health.
- Resolution preserves event/notification history, withdraws pending alert notices and informs only recipients already involved.

## Implementation sequence

1. Isolated PostgreSQL regression fixture: reproduce fresh activity followed by group escalation; cover default/strict/expired relationship, time provenance and acknowledgement authorization.
2. Append-only migration: guardian policy RPCs, shared automatic resolution, escalation race guard, guarded explicit pattern confirmation, compatible normal acknowledgement.
3. Update guardian settings and confirmation UI. Keep failures visible and remove duplicate fallback attempts.
4. Run SQL behavior tests, full Vitest, typecheck and build. Update Brain runtime truth with local/production distinction.

## Release boundary

Local implementation and verification are authorized. No production migration, push, release or native binary distribution in this task without the release checkpoint. New migration must precede the new UI. Keep all unrelated pre-existing changes intact.

## Current status — 2026-09-23 20:11 +06:00

- Approval-review execution recovered. The quota block below is historical and no longer active.
- Full Vitest: **105 files / 629 tests passed**. Typecheck and production web build passed. Android Java compilation passed earlier with no subsequent Java changes.
- Latest database edits passed **22 isolated PostgreSQL cases** again: passive epoch restart, consistent policy/account/device/alert lock ordering, and SOS explicit button confirmation without a default pattern requirement. Guardian-required patterns still apply to SOS as well.
- Existing pgTAP expectations in three files were aligned with ADR-0045. They were reviewed but **not executed**: full local Supabase migration replay is unavailable. The isolated fixture is not a full production schema replay. Multi-connection concurrency and physical-device flows remain unverified.
- Brain policy pointers and Dev Log updated; lessons and lessons-watch both passed. No production changes, push, version bump or binary distribution.
- Release order: validate migration against a full disposable Supabase schema, apply the new migration, then publish matching client and native artifacts. Confirm the production release checkpoint first. Preserve unrelated existing dirty changes.

## Historical handoff — 2026-09-23, approval-review quota blocked

- Tasks: `KC-ACTIVITY-RESOLUTION-001`, companion `KC-ACTIVITY-NATIVE-001` in the shared Brain runtime. Both remain active. Manager-direct; no subordinate calls.
- Implemented locally: migration `20260923054905_activity_auto_resolution_guardian_pattern.sql`; guardian policy UI/RPC; server-checked pattern; default confirmation button; no automatic first-run pattern setup; truthful acknowledgement failures; notification tap/action separation; removed Android optimistic-safe notification.
- Verified before the latest edit: 20 isolated PostgreSQL behavior cases passed; 7 acknowledgement, 3 confirmation-policy, 3 notification-routing and 2 native contract cases passed. `npm run typecheck` passed. Android `:app:compileDebugJavaWithJavac` passed. Earlier full suite was 598 passing before the new policy implementation; **the final full suite has not run**.
- Last issue: the existing passive epoch restart trigger ignores `resolved_by IS NULL`, so automatic resolution could immediately re-alert from old missed windows. Added two executable cases and extended the migration to create `activity_resolution` epochs while preserving old history. **These latest fixture, test and migration edits are unverified.**
- Blocker: elevated `npm test -- src/features/alerts/activityResolutionDb.test.ts` was not executed. Automatic approval review failed because its usage quota was exhausted (tool suggested retry at 4:33 PM). This was not an unsafe-action verdict. Do not bypass that approval check or claim final success.
- Single next action when approved execution is available: run `npm test -- src/features/alerts/activityResolutionDb.test.ts` (22 cases now), fix any failure, then continue validation.
- Remaining after that: review concurrent resolution/policy locking; align superseded pgTAP expectations (`routine_safety.sql`, `activity_never_answers_an_alert_in_cron.sql`, `passive_window_engine.sql`) through an allowed write set; run full Vitest, typecheck, build; update Brain invariant/behavior/guardian/notification pointers to accepted ADR-0045 with local vs production distinction; record final evidence via brain-task runtime and run lesson checks. Native package distribution and production migration are not done.
- Preserve unrelated changes in PrivacyPolicy, GuardianPermissionsCard, guardianPermissions, passive/native, vercel.json and the pre-existing internal_rpc_execute_acl migration/test.
- Required capability: local TypeScript/PostgreSQL regression execution with functioning automatic approval review. No new billing authorization.
