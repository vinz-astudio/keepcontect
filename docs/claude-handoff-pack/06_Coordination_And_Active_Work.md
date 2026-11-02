# 多 IDE 协作规范与活跃看板

---
type: coordination
---

# ðŸ¤ å¤š IDE åä½œä¸­æž¢

> **æžç®€åä½œæ€»çº²**ï¼šä»»ä½• IDE / AIï¼ˆCodexã€Antigravityã€Claude Codeã€å…¶ä»–ï¼‰åœ¨æœ¬ vault å…³è”çš„é¡¹ç›®å¼€å‘å‰å¿…è¯»ã€‚
> **æ ¸å¿ƒèŒè´£**ï¼šAI è‡ªè¡ŒæŸ¥è¯äº‹å®žå¹¶ç›´æŽ¥æ‰§è¡Œï¼ˆDirect Work Defaultï¼‰ï¼›**äººç±»åªä¿ç•™äº§å“æ–¹å‘ã€ADR è£å†³ã€æ–°å¢žä»˜è´¹ã€ä¸å¯é€†ä¸Žå‘å¸ƒç­‰æœ€ç»ˆæƒåŠ›**ã€‚

---

## ä¸€ã€ åä½œä¸‰è¦ç´ 

1. **[[Active Work]]** â€” ç”± `brain-task.mjs` ç»´æŠ¤çš„å½“å‰æ´»è·ƒ/é˜»å¡ž/å¾…è£å†³çœ‹æ¿ï¼›
2. **[[SDLC Unified Workflow]]** â€” **ç»Ÿä¸€å·¥ç¨‹æµæ°´çº¿**ï¼šç›´è¾¾æ‰§è¡Œã€ç¬¬ä¸€æ€§åŽŸç† Root Requirement Gate ä¸Žäººç±» Checkpoint æŠ¤æ ï¼›
3. **[[Model Routing Guideline]]** â€” ä¸‰å®¶å…¬å¸æ¨¡åž‹åˆ†å·¥ã€é¢åº¦è€—å°½è‡ªåŠ¨æ”¹é“ä¸Ž `Provider Access Registry.json` èµ„é‡‘è¾¹ç•Œã€‚

---

## äºŒã€ æ ¸å¿ƒåè®®ï¼ˆæ‰€æœ‰ IDE å¿…é¡»éµå®ˆï¼‰

1. **Direct work is the default**ï¼šæ¸…æ™°ã€å¯é€†ã€åœ¨èŒƒå›´å†…ä¸”æ— è§¦å‘å™¨çš„å·¥ä½œç›´æŽ¥è°ƒæŸ¥ã€ä¿®æ”¹ã€éªŒè¯ã€æ”¶å£ï¼Œä¸åˆ›å»º task cardã€Task Contextã€é€è°ƒç”¨è´¦æœ¬ã€‚
2. **Human checkpoint**ï¼šæ²¡æœ‰é€šç”¨çš„æ—¶é—´æˆ– token å®¡æ ¸çº¿ã€‚**Approved task execution envelope** å†…ä¸åšé‡å¤ token-only checkpointï¼›gross/cache tokens ä»…ä¸º diagnostic telemetryã€‚åªæœ‰æ˜Žç¡®é¢åº¦è¶…é™ã€stage gateã€incremental spendã€ä¸å¯é€†æŸå¤±ã€production/external actionã€account/permission/privacyã€product direction/accepted decision æˆ–é‡å¤§æ­§ä¹‰æ‰å†æ¬¡åœä¸‹ã€‚
3. **Guarded work**ï¼šåªæœ‰å‘½ä¸­è§¦å‘å™¨æ‰è¿è¡Œ `node Coordination/tools/brain-task.mjs start|update|finish`ï¼ŒæŒ‰éœ€åŠ è½½ generated Task Contextï¼Œç¦æ­¢æ‰‹æ”¹ Active Workã€‚
4. **Event-driven memory**ï¼šä»£ç ã€migrationã€æµ‹è¯•å’Œ live runtime æ˜¯è¿è¡Œæ—¶çœŸç›¸ï¼›ä»…åœ¨ project truthã€accepted decisionã€handoffã€æœªè§£ blocker æŒä¹…å˜åŒ–æ—¶å›žå†™ Brainã€‚
5. **åŒé€šé“æ²Ÿé€š**ï¼šå†…éƒ¨æŒ‡ç¤ºã€è®¾ç½®åŠé€šä¿¡æŒ‰ [[ADR-0041 Caveman Internal Communication#Amendment 2 â€” Consumer-specific representation]] é€‰æ‹©è¡¨ç¤ºï¼›`caveman-delta-v1` / `machine-delta-v1` ä¿ç•™ä¸ºå…¼å®¹é»˜è®¤ï¼Œæ—¢æœ‰å¿…éœ€æœºå™¨å¥‘çº¦ä¸å˜ã€‚**é¢å‘äººç±»æ²Ÿé€šå…¨å±€å¼ºåˆ¶**ï¼š**ç”¨æˆ·æ˜¯ ADHDï¼Œæ²Ÿé€šä¸¥ç¦å•°å—¦ï¼Œå…ˆç»“è®ºã€ç›´å¥”é‡ç‚¹ã€æ‹’ç»åºŸè¯**ï¼›ç»Ÿä¸€é‡‡ç”¨ **[[STE100 Communication Protocol]]**ï¼ˆçŸ­å¥ã€ä¸€è¯ä¸€ä¹‰ã€å…ˆç»“è®ºåŽç»†èŠ‚ã€æ— å®¢å¥—ï¼‰ã€‚ä¸ä»¥ literal binary/Base64 ä½œä¸ºæœªç»éªŒè¯çš„ä¸Šä¸‹æ–‡ä¼˜åŒ–ã€‚

---

## ä¸‰ã€ ç›¸å…³ç´¢å¼•

- èµ„æ–™ç»´æŠ¤æ­£æœ¬ï¼š[[Profile Guide]]ã€[[References/Library Guide]]ã€[[Commands/Library Maintenance Command]]ã€‚æ´¾ç”Ÿç›®å½•ç”± `library-maintain.mjs` ç”Ÿæˆï¼›åˆ†ç±»ä¸ŽéªŒè¯åˆ†å¼€ï¼ŒåŽŸä»¶å˜åŒ–ä¸è‡ªåŠ¨å–å¾—æ–°æƒå¨ã€‚

- Profile åˆ†ç±»å…¥å£ï¼š`Coordination/Project Context Map.json` çš„ `global_profile` ä¸Žé¡¹ç›® `profile`ã€‚æŒ‰èµ„æ–™ã€çŠ¶æ€ã€åŽ†å²ã€åå¥½ã€é™åˆ¶å¼•ç”¨åŽŸæœ‰æ¥æºï¼›æ˜ å°„ä¸ç­‰äºŽå½“å‰äº‹å®žå·²éªŒè¯ã€‚èŒƒå›´ä¸Žç¼ºå£è§ [[Coordination/Status/Profile åˆ†ç±»æ•´ç† 2026-10-22]]ã€‚

- [[Brain Rules]] Â· [[Active Work]] Â· [[SDLC Unified Workflow]] Â· [[Model Routing Guideline]] Â· [[Provider Access Registry.json]] Â· [[Antigravity Precision Execution Harness]]


---

# 当前活跃任务看板 (Active Work)

---
type: active-work
generated_by: Coordination/tools/brain-task.mjs
---

# Active Work

> Generated current-only board. Use `brain-task start|update|finish`; do not hand-edit.

## Active

- [Codex root Â· 2026-10-27T13:05:26.574Z] `BRAIN-CONTROL-PLANE-THRESHOLD-20261027` Â· Brain Â· High-risk/M3 Â· Restore accepted no-general-threshold policy in control-plane source and installed artifacts Â· write=11 paths
- [Codex root Â· 2026-10-28T18:18:49.236Z] `BRAIN-CROSS-AI-ACTIVATION-20261027` Â· Brain Â· High-risk/M3 Â· Complete human-authorized cross-AI runtime activation Â· write=45 paths Â· blockers=å…±ç”¨ MD äº¤ä»˜ã€å®žé™…æŽ¥æ”¶æ£€æŸ¥åŠä¸€æ¬¡ Gemini Flash æŽ¥æ‰‹å·²æœ‰ç»„ä»¶è¯æ®ï¼›å…¶ä»–å…¥å£ã€References å‰©ä½™å…¨æ–‡è¯­ä¹‰æ¯”è¾ƒåŠå…¨éƒ¨å®žé™…ä»»åŠ¡è¡Œä¸ºä»æœªéªŒæ”¶ã€‚
- [Codex root Â· 2026-10-27T13:05:27.786Z] `BRAIN-CROSS-AI-PROJECTION-20261027` Â· Brain Â· High-risk/M3 Â· Align route template and observed model context with accepted runtime Â· write=6 paths
- [Codex root Â· 2026-10-27T22:39:07.061Z] `BRAIN-FALLBACK-CANARY-20261028` Â· Brain Â· High-risk/M3 Â· Repair brittle live-catalog canary model-name assertion; preserve complete ordered provider failover verification after accepted model refresh. Â· write=2 paths
- [Codex root Â· 2026-10-27T18:26:41.461Z] `BRAIN-INCLUDED-CONTROL-PLANE-20261028` Â· Brain Â· High-risk/M3 Â· Connect existing included read-only CLI seats and verified cost-tier tie-break to the guarded runtime Â· write=24 paths
- [Codex root Â· 2026-10-27T23:06:51.577Z] `BRAIN-INCLUDED-CONTROL-PLANE-R3-20261028` Â· Brain Â· High-risk/M3 Â· Complete raw Opus review corrections to included read-only adapters; R1/R2 retained as immutable predecessor orders. Â· write=24 paths
- [Codex root Â· 2026-10-28T13:47:15.518Z] `BRAIN-LEGACY-POLICY-CONSOLIDATION-20261028` Â· Brain Â· High-risk/M3 Â· Apply already accepted Oct2 and capability-first rules to contradictory active ADR/adapter bodies; prevent their known retired clauses from returning. Â· write=6 paths
- [Codex root Â· 2026-10-27T18:34:28.876Z] `BRAIN-MODEL-ACTIVATION-20261028` Â· Brain Â· High-risk/M3 Â· Activate source-scoped model data and verify original-source guarded execution under the accepted framework Â· write=23 paths
- [Codex root Â· 2026-10-28T13:47:17.331Z] `BRAIN-MODEL-BINDING-WORDING-20261028` Â· Brain Â· High-risk/M3 Â· Replace stale provider-balanced owner-selection wording with capability-filtered physical model binding, preserving existing resolver and human model ranks. Â· write=2 paths
- [Codex root Â· 2026-10-28T13:47:13.457Z] `BRAIN-NATIVE-ENTRY-RECEIPT-20261028` Â· Brain Â· High-risk/M3 Â· Verify source-bound stdin receipts and normal native startup without confusing isolated-worker probes with default host behavior. Â· write=6 paths
- [Codex root Â· 2026-10-28T13:47:16.485Z] `BRAIN-ONBOARDING-POLICY-PROJECTION-20261028` Â· Brain Â· High-risk/M3 Â· Apply accepted direct-work, no-general-ceiling and local-vault-commit rules to the remaining onboarding projection. Â· write=2 paths
- [Codex root Â· 2026-10-27T13:15:39.283Z] `BRAIN-RUNTIME-PROJECTIONS-20261027` Â· Brain Â· High-risk/M3 Â· Reconcile task and route template projections with capability policy4 and fix obsolete control-plane regression fixtures while preserving runtime permission and subscription checks. Â· write=7 paths
- [Codex root Â· 2026-10-27T13:01:38.841Z] `BRAIN-RUNTIME-RECONCILE-20261027` Â· Brain Â· High-risk/M3 Â· Repair active-card protection, archived legacy inventory matching and non-human blocker reminders without weakening dispatch controls. Â· write=9 paths
- [Codex root Â· 2026-10-27T13:17:42.993Z] `BRAIN-RUNTIME-REFRESH-20261027` Â· Brain Â· High-risk/M3 Â· Deliver changed accepted runtime to already-open conversations through existing prompt hooks, with bounded evidence-based refresh and no new hook permissions. Â· write=8 paths
- [Codex root Â· 2026-10-28T04:31:22.148Z] `BRAIN-SEMANTIC-PILOT-REPAIR-20261028` Â· Brain Â· High-risk/M3 Â· Repair reproduced Windows Agy long-prompt spawn failure and stale remaining-state report; independently review bounded original-evidence pilot before further host acceptance. Â· write=7 paths

## Awaiting Human

- [Codex Â· 2026-10-08T10:41:26.468Z] `NEO-EXECUTION-PREP-001` Â· Brain Â· Standard/M2 Â· Neo preparation complete; field and measurement contracts await human adjudication. Â· write=5 paths Â· blockers=Field ownership and shape rules unresolved; Provenance, query log and 600-token rules unresolved; P2 seed/holdout freeze required before P4/P5; Sol-first review; Opus only on Sol request

## Blocked

- [Codex Â· 2026-10-27T13:05:28.294Z] `NEO-P1-V4-001` Â· Brain Â· Standard/M2 Â· Apply Astra strategy to the Neo P1 specification through the V4 Pro mechanical executor. Â· write=1 paths Â· blockers=Core Specification does not meet the original P1 acceptance; no Sol pass/locked execution receipt is recorded. UXD202 Pilot v0.2 supersedes KC-domain experiment settings only, not the full P1 specification. Not a prerequisite for default Brain work.

## Project Truth Pointers

- 80äº¿çš„è¿›åŒ– â€” project home missing; do not infer state
- [[BNLI]] â€” `Projects/BNLI/BNLI.md`
- GCIT Curriculum â€” project home missing; do not infer state
- [[GCIT Website]] â€” `Projects/GCIT Website/GCIT Website.md`
- [[Keep Contact]] â€” `Projects/Keep Contact/Keep Contact.md`
- [[Studio K BrandOps]] â€” `Projects/Studio K BrandOps/Studio K BrandOps.md`
- [[è§„åˆ™ç†è§£ä¸Žæ‰§è¡Œè¯Šæ–­ 2026-10-24]] â€” `Coordination/Status/è§„åˆ™ç†è§£ä¸Žæ‰§è¡Œè¯Šæ–­ 2026-10-24.md`
- [[è·¨ AI è‡ªåŠ¨è¿è¡ŒéªŒæ”¶ 2026-10-27]] â€” `Coordination/Status/è·¨ AI è‡ªåŠ¨è¿è¡ŒéªŒæ”¶ 2026-10-27.md`
- [[æ¨¡åž‹æ¡£ä½èµ„æ–™æ ¸æŸ¥ 2026-10-27]] â€” `Coordination/Status/æ¨¡åž‹æ¡£ä½èµ„æ–™æ ¸æŸ¥ 2026-10-27.md`
- [[é»˜è®¤æ¡†æž¶æŠŠå…³ 2026-10-23]] â€” `Coordination/Status/é»˜è®¤æ¡†æž¶æŠŠå…³ 2026-10-23.md`
- [[é»˜è®¤æ¡†æž¶æŽ¥ç»­æ ¸å¯¹ 2026-10-22]] â€” `Coordination/Status/é»˜è®¤æ¡†æž¶æŽ¥ç»­æ ¸å¯¹ 2026-10-22.md`
- [[é»˜è®¤æ¡†æž¶å®žé™…è¿è¡Œæ ¸æŸ¥ 2026-10-22]] â€” `Coordination/Status/é»˜è®¤æ¡†æž¶å®žé™…è¿è¡Œæ ¸æŸ¥ 2026-10-22.md`
- [[æ–°ç³»ç»Ÿå¯ç”¨æ ¸æŸ¥ 2026-10-27]] â€” `Coordination/Status/æ–°ç³»ç»Ÿå¯ç”¨æ ¸æŸ¥ 2026-10-27.md`
- [[èµ„æ–™åº“ä¸ŽèŒè´£éªŒæ”¶ 2026-10-22]] â€” `Coordination/Status/èµ„æ–™åº“ä¸ŽèŒè´£éªŒæ”¶ 2026-10-22.md`
- [[DESIGN.md Kit æ ¸å¯¹ 2026-10-22]] â€” `Coordination/Status/DESIGN.md Kit æ ¸å¯¹ 2026-10-22.md`
- [[framework-pass-inventory-2026-10-27]] â€” `Coordination/Status/framework-pass-inventory-2026-10-27.md`
- [[Global Entry Legacy Exceptions]] â€” `Coordination/Status/Global Entry Legacy Exceptions.md`
- [[Keep Contact Status]] â€” `Coordination/Status/Keep Contact Status.md`
- [[opus-runtime-enforcement-review-prompt-2026-10-24]] â€” `Coordination/Status/opus-runtime-enforcement-review-prompt-2026-10-24.md`
- [[Pi æœ¬åœ°å€™é€‰æ¨¡åž‹æ¦œå•æ”¶é›† 2026-10-30]] â€” `Coordination/Status/Pi æœ¬åœ°å€™é€‰æ¨¡åž‹æ¦œå•æ”¶é›† 2026-10-30.md`
- [[Pi å€™é€‰æ¨¡åž‹ä¸‰é¢˜è¯•è·‘ 2026-10-30]] â€” `Coordination/Status/Pi å€™é€‰æ¨¡åž‹ä¸‰é¢˜è¯•è·‘ 2026-10-30.md`
- [[Pi å€™é€‰æ¨¡åž‹v2ç­›é€‰è½® 2026-10-30]] â€” `Coordination/Status/Pi å€™é€‰æ¨¡åž‹v2ç­›é€‰è½® 2026-10-30.md`
- [[Pi å€™é€‰æ¨¡åž‹v2ç»ˆè½® 2026-10-31]] â€” `Coordination/Status/Pi å€™é€‰æ¨¡åž‹v2ç»ˆè½® 2026-10-31.md`
- [[Pi å€™é€‰æ¨¡åž‹v2é‡å¤è½® 2026-10-31]] â€” `Coordination/Status/Pi å€™é€‰æ¨¡åž‹v2é‡å¤è½® 2026-10-31.md`
- [[Pi è¯„åˆ†å¤æ ¸ææ–™ 2026-10-30]] â€” `Coordination/Status/Pi è¯„åˆ†å¤æ ¸ææ–™ 2026-10-30.md`
- [[Pi Brainç¬¬ä¸€é˜¶æ®µéƒ¨ç½²è®°å½• 2026-10-30]] â€” `Coordination/Status/Pi Brainç¬¬ä¸€é˜¶æ®µéƒ¨ç½²è®°å½• 2026-10-30.md`
- [[Pi Durable å•äººéªŒè¯éƒ¨ç½²è®°å½• 2026-10-30]] â€” `Coordination/Status/Pi Durable å•äººéªŒè¯éƒ¨ç½²è®°å½• 2026-10-30.md`
- [[Pi Durable Qwen è½»é‡è´¨é‡æµ‹è¯• 2026-10-30]] â€” `Coordination/Status/Pi Durable Qwen è½»é‡è´¨é‡æµ‹è¯• 2026-10-30.md`
- [[Pi Durable VMä¸Žæœ¬åœ°ç¼–ç¨‹æ¨¡åž‹è¯„ä¼° 2026-10-30]] â€” `Coordination/Status/Pi Durable VMä¸Žæœ¬åœ°ç¼–ç¨‹æ¨¡åž‹è¯„ä¼° 2026-10-30.md`
- [[Pi Durable VMé¢„æ£€ä¸Žå®‰è£…ææ¡ˆ 2026-10-30]] â€” `Coordination/Status/Pi Durable VMé¢„æ£€ä¸Žå®‰è£…ææ¡ˆ 2026-10-30.md`
- [[Pi Durable Workerè‡ªæ£€ä¸Žæ¨¡åž‹å¹¶è¡Œè¯„ä¼° 2026-10-30]] â€” `Coordination/Status/Pi Durable Workerè‡ªæ£€ä¸Žæ¨¡åž‹å¹¶è¡Œè¯„ä¼° 2026-10-30.md`
- [[Pi Flintæ€è€ƒé¢„ç®—è°ƒæŸ¥ 2026-10-30]] â€” `Coordination/Status/Pi Flintæ€è€ƒé¢„ç®—è°ƒæŸ¥ 2026-10-30.md`
- [[Pi Harnessä¸Ž2nd Brainæ•´ä½“æ–¹æ¡ˆ 2026-10-30]] â€” `Coordination/Status/Pi Harnessä¸Ž2nd Brainæ•´ä½“æ–¹æ¡ˆ 2026-10-30.md`
- [[Pi v2è¯„åˆ†å¤æ ¸ææ–™ 2026-10-31]] â€” `Coordination/Status/Pi v2è¯„åˆ†å¤æ ¸ææ–™ 2026-10-31.md`
- [[Pi v3è¯„åˆ†å¤æ ¸ææ–™ 2026-10-31]] â€” `Coordination/Status/Pi v3è¯„åˆ†å¤æ ¸ææ–™ 2026-10-31.md`
- [[Pi v4å¤æ ¸ææ–™ 2026-10-31]] â€” `Coordination/Status/Pi v4å¤æ ¸ææ–™ 2026-10-31.md`
- [[Pi Workeråœæ­¢ä¸Žæ¨¡åž‹å¯¹æ¯” 2026-10-30]] â€” `Coordination/Status/Pi Workeråœæ­¢ä¸Žæ¨¡åž‹å¯¹æ¯” 2026-10-30.md`
- [[Pi Workeré€‰å®š 2026-10-31]] â€” `Coordination/Status/Pi Workeré€‰å®š 2026-10-31.md`
- [[pi-vm-code-review-raw-2026-10-30]] â€” `Coordination/Status/pi-vm-code-review-raw-2026-10-30.md`
- [[pi-vm-provider-final-raw-2026-10-30]] â€” `Coordination/Status/pi-vm-provider-final-raw-2026-10-30.md`
- [[Profile åˆ†ç±»æ•´ç† 2026-10-22]] â€” `Coordination/Status/Profile åˆ†ç±»æ•´ç† 2026-10-22.md`
- [[profile-context-plan-2026-10-29]] â€” `Coordination/Status/profile-context-plan-2026-10-29.md`
- [[source-delivery-pilot-2026-10-29]] â€” `Coordination/Status/source-delivery-pilot-2026-10-29.md`
- [[stale-settings-inventory-2026-10-27]] â€” `Coordination/Status/stale-settings-inventory-2026-10-27.md`
- [[workflow-mechanical-layers-2026-10-29]] â€” `Coordination/Status/workflow-mechanical-layers-2026-10-29.md`

## Legacy Archive

- [[Active Work through 2026-07-17]]
- [[Model Usage Ledger through 2026-07-16]]
