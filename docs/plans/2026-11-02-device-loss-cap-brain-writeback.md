# Brain write-back: device-loss alerts capped below terminal (2026-11-02)

- **From**: Claude Code (cloud session; no Obsidian access, so this file carries the write-back)
- **For**: whichever agent has the Brain; apply the items below, then delete nothing here
- **Code**: branch `claude/exciting-ramanujan-5z62ve`, migration
  `supabase/migrations/20261101213426_cap_device_loss_below_terminal.sql`
- **Production status (2026-11-02)**:
  - DB migration applied 04:16 UTC in one transaction via the Supabase connector, ledger version
    `20261101213426` (aligned with the file name). Live function fingerprints matched the repo
    (whitespace-insensitive md5: process_escalations `2b2cd041…`, notify_stage_before_passive_checkin
    `fd6554db…`, device_loss_alert_never_terminal `bb4870f3…`). process-escalations cron: 19/19 succeeded
    in the 19 minutes after, 0 job_failures.
  - Web: `main` fast-forwarded to `e98e6f6` 04:37 UTC (also carries `f3bed38`, `878ae50`, `ee86410` from
    `test/sql-replay-production-acl`, whose migration was already in production). GitHub CI passed. The
    Vercel result was not observable from the cloud session (host blocked); confirm on the live site.
  - iOS: TestFlight build 0.7.9 (46) from `main@e98e6f6` uploaded 05:10 UTC (Actions run 41390051614,
    attempt 3). Attempts 1–2 failed at `get_certificates`: an Apple developer agreement had expired;
    the human re-signed it. Still needs Apple processing and tester distribution in App Store Connect.
  - Android: not built or released (needs the human's machine: keystore + SDK).
  - Tauri desktop: not built.

## 1. Decisions.md, 快记 (replace the open item, add the new ones)

Replace the line "2026-11-02 · 待人类裁决（未决）· collection_restricted …" with:

- 2026-11-02 · 决定 · collection_restricted 同样封顶：最多到 group/community，不进 terminal，不解锁资料 · 原话「2 封」 · 理由：采集被关/无权限同样不是关于人的证据；近 90 天 0 条 · 来源：人类 · 复查：上线后核对
- 2026-11-02 · 决定 · 旧引擎 dark_device（心跳断 18h+）同样封顶，并改用「KC 失去联系」措辞 · 原话「3 封」 · 理由：9 个受监护成员中 5 个仍走旧引擎；近 90 天 11 条 dark_device 到 terminal、发出 23 条「已解锁资料」通知 · 来源：人类 · 复查：上线后核对
- 2026-11-02 · 决定 · 历史 terminal 告警不修正 · 原话「1 不改」 · 理由：当时 0 条 open（共 860 条全部 resolved），无资料处于解锁状态；改写只会扭曲审计 · 来源：人类

## 2. Projects/Keep Contact (Alert System, Notification Flow)

Runtime truth after this migration is applied:

- `process_escalations()` holds an alert at its current stage, clears `next_deadline`, sends nothing,
  instead of promoting to `terminal`, when: last causal window `miss_kind` is `device_unreachable` or
  `collection_restricted`, or `cause='dark_device'`. Unchanged: passive `silent`, legacy `silence`, SOS.
- Trigger `alerts_device_loss_never_terminal` (function `private.device_loss_alert_never_terminal()`)
  rejects any INSERT/UPDATE that sets such an alert to `terminal` (SQLSTATE 23514). A regression shows up
  in `private.job_failures`, and the alert stays put. Rows already at terminal are untouched.
- `emergency_info_select` is unchanged: reveal only at `stage='terminal'` or `cause='sos'`.
- Legacy notifier `private.notify_stage_before_passive_checkin`: dark_device group/community wording is
  now "设备与 KC 失去联系"; params gain `cause='dark_device'`, `miss_kind='device_unreachable'`.
- **Clients ignore the server body for group/community/terminal/self** and render their own templates:
  in-app list (`src/features/alerts/notificationCopy.ts` + `src/lib/i18n.tsx`), Web Push (`public/sw.js`),
  Android (`NotifyWorker.java`). All three now pick copy from `params.miss_kind` (+ `params.cause` for
  passive alerts). Before this, every passive alert, device_unreachable included, was shown as
  "出现异常沉默". In-app `notif.self` no longer says "解锁" (ADR-0045).
- Old installed clients keep the old copy until updated. Android needs a new build.

## 3. Known Issues

- `KC-OUTAGE-ESCALATION-20261009`: fixed in branch; pending production migration, web deploy (main),
  and an Android build. Re-check after deploy: count of `terminal` notifications for device-loss alerts
  should stay 0.

## 4. Open items for the human (not decided; do not act on them)

1. **Plan A vs scenario 1 on iPhone.** Known bug 2: an unplugged, locked iPhone almost never answers
   silent pushes, so it is classified `device_unreachable`. With plan A, a real emergency on such an
   iPhone now stops at community and never unlocks the address. This is the accepted trade-off of
   plan A, but it lands on scenario 1 (life baseline) for iOS users until bug 2 is solved.
2. **ADR-0039 staged disclosure conflicts with plan A if implemented as written.** ADR-0039 says
   ordinary group members get the full emergency profile at the Group stage (not implemented; runtime
   is terminal-only). Implemented literally, a device-loss alert capped at community would unlock the
   profile at Group. Whoever implements ADR-0039 disclosure must exclude device-loss alerts. Guardian
   relationship-scoped access (also ADR-0039) is not affected; the new tests check privacy from a
   watcher for this reason.
3. **ADR-0042 wording** says passive alerts enter "self → group → community"; scenario 1 and runtime let
   passive `silent` reach terminal. Left as is (plan A said "silent 不变"); worth one line of
   clarification in the ADR.

## 5. Dev Log entry (why)

2026-11-02 · Claude Code · Device loss never reaches terminal. Plan A plus the human's follow-up
decisions: device_unreachable, collection_restricted and legacy dark_device stop at community. The cap
lives in process_escalations and, because the Brain names "a guard written as a field check, bypassed
by another branch" as a recurring defect shape, also in a table trigger. Found while doing it: all
three clients overrode the server's honest wording with "异常沉默", so the passive engine's
ADR-0042 wording had never reached a user; fixed on all three. Production function bodies were
checked identical to the repo before editing (whitespace-insensitive md5). Verified: PGlite DB test
22/22 (9 of the cap cases fail against the current production functions), copy tests on all three
clients, full vitest 719/719, typecheck clean, migration applied twice cleanly. Not run: pgTAP replay
(Podman), Android gradle tests (no SDK in the cloud container; the changed method was compiled and run
standalone instead).
