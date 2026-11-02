# Keep Contact 核心业务逻辑笔记集合

## 业务模块：Alert System

## ADR-0045 æ›´æ–°ï¼šé»˜è®¤æœ¬äººæ´»åŠ¨è§£é™¤ï¼ˆæœ¬åœ°å®žçŽ°ï¼Œå°šæœªä¸Šçº¿ï¼‰

[Codex Â· 2026-09-23 20:11 +06:00]

ç”¨æˆ·å·²æ˜Žç¡®æ›¿ä»£æ—§çš„â€œè¢«åŠ¨æ´»åŠ¨æ°¸ä¸è§£é™¤â€è§„åˆ™ã€‚é»˜è®¤ silence/dark_device/concern åœ¨æ£€æµ‹åˆ°å‘Šè­¦æ‰“å¼€ä¹‹åŽã€æ¥æºä¸Žè´¦æˆ·æ­£ç¡®ã€v2 ä¸”åŠæ—¶é€è¾¾çš„æœ¬äººæ´»åŠ¨æ—¶è‡ªåŠ¨è§£é™¤ï¼›å¿ƒè·³ã€æœªæ¥æ—¶é—´ã€åŽ†å²è¡¥ä¼ åŠä»–äººæ“ä½œä¸ç®—æœ¬äººæ´»åŠ¨ã€‚æŒ‡å®šçš„æœ‰æ•ˆå®ˆæŠ¤è€…å¯ä¸ºå…¶è¢«å®ˆæŠ¤è€…å¼€å¯ pattern è¦æ±‚ï¼Œé»˜è®¤å…³é—­ï¼›ä»»ä¸€æœ‰æ•ˆè¦æ±‚ç”Ÿæ•ˆï¼Œè§£é™¤å…³ç³»åŽä¸å†ç”Ÿæ•ˆã€‚æœåŠ¡å™¨æ ¡éªŒ patternï¼Œæ™®é€šæŒ‰é’®åŠæ—§ RPC ä¸å¾—ç»•è¿‡ã€‚æ™®é€šé€šçŸ¥ä½¿ç”¨â€œä¸€åˆ‡å®‰å¥½â€æŒ‰é’®ï¼Œç‚¹é€šçŸ¥æ­£æ–‡åªæ‰“å¼€ç•Œé¢ã€‚SOS ä¿ç•™æ˜Žç¡®æ‰‹åŠ¨ç¡®è®¤ï¼Œé»˜è®¤ä¹Ÿä¸è¦æ±‚ patternã€‚

æ–°è¿ç§»ï¼š`20260923054905_activity_auto_resolution_guardian_pattern.sql`ã€‚æ´»åŠ¨è§£é™¤ä¿ç•™åŽ†å²å¹¶é‡å¼€è¢«åŠ¨ç›‘æµ‹ epochï¼Œé¿å…æ—§æ¼ç­¾é“¾ç«‹å³é‡å¤å‘Šè­¦ï¼›æ’¤å›žæœªå‘é€çš„æ—§é€šçŸ¥ï¼Œæ¢å¤é€šçŸ¥åªå‘æœ¬äººåŠæ—¢æœ‰æ¶‰åŠè€…ã€‚Android ä¸å†å‡­æœ¬åœ°è§£é”æˆ– UsageStats æå‰æ˜¾ç¤ºå®‰å…¨æˆåŠŸã€‚

æœ¬åœ°éªŒè¯ï¼š105 æ–‡ä»¶ / 629 é¡¹ Vitest é€šè¿‡ï¼›typecheckã€ç½‘é¡µ build é€šè¿‡ï¼›æœ€åŽ SQL é”é¡ºåºå’Œ SOS ä¿®æ­£åŽ 22 é¡¹éš”ç¦» PostgreSQL å›žå½’å†æ¬¡é€šè¿‡ã€‚æ­¤å‰ Android Java ç¼–è¯‘é€šè¿‡ã€‚å°šæœªåšå®Œæ•´ Supabase è¿ç§»å›žæ”¾ã€çœŸæœºéªŒæ”¶æˆ–éƒ¨ç½²ã€‚æœ¬èŠ‚æ˜¯çŽ°è¡Œå·²æŽ¥å—æ–¹å‘ï¼›ä¸‹æ–‡ç›¸å†²çªçš„æ—§æ´»åŠ¨è§£é™¤è§„åˆ™ä»…ä»£è¡¨åŽ†å²å®žçŽ°ï¼Œä¸å¯ç”¨äºŽå¦å®š ADR-0045ã€‚

# Alert System

#business-logic #kc #core

> è¿™æ˜¯ Keep Contact æœ€æ ¸å¿ƒçš„ä¸šåŠ¡é€»è¾‘ã€‚ä»»ä½•ä¿®æ”¹å‘Šè­¦ç›¸å…³ä»£ç å‰å¿…é¡»è¯»å®Œæœ¬æ–‡ã€‚

---

## ADR-0039 çŽ°è¡Œäº§å“å¥‘çº¦

[Codex Â· 2026-08-09 17:24 +06:00]

- è¢«åŠ¨ ping æ˜¯ activity/coverage è¯æ®ï¼Œ**ä¸èƒ½è§£é™¤ä»»ä½•å‘Šè­¦**ã€‚å®ƒå¯ä»¥è¯æ˜Žè®¾å¤‡æˆ– App æœ€è¿‘é€è¾¾äº†ä¸€ä¸ªåˆæ ¼ä¿¡å·ï¼Œä½†ä¸èƒ½è¯æ˜Žç”¨æˆ·å·²ç»çœ‹è§ã€ç†è§£å¹¶å›žåº”å‘Šè­¦ã€‚
- æœ¬äººå‘Šè­¦åªèƒ½ç”±ç”¨æˆ·çš„åˆ»æ„å“åº”åŠ¨ä½œè§£é™¤ï¼›ç…§é¡¾è€…/Guardian çš„ç¡®è®¤æ˜¯ç‹¬ç«‹çš„å¤–éƒ¨ç¡®è®¤ï¼›GM å…³é—­æ˜¯è¿è¥å¤„ç½®ã€‚ä¸‰è€…å¿…é¡»ä¿ç•™ä¸åŒ provenanceã€‚
- `concern` åªæ˜¯åœ¨æ—¢æœ‰ alert lifecycle ä¸Šè¡¨è¾¾å…³å¿ƒï¼Œä¸èƒ½åˆ›å»º alertï¼Œä¹Ÿä¸èƒ½ç»•è¿‡ escalation gateã€‚
  **å·²å®žçŽ°ï¼ˆS3-Aï¼Œ2026-08-09ï¼Œ`20260809220000_s3_concern_requires_active_alert.sql`ï¼‰**ï¼š`send_concern` ä¸Ž `gm_send_concern` åœ¨ç›®æ ‡æ—  open alert æ—¶æŠ› `active alert required`ï¼ˆP0001ï¼‰ï¼›æœ‰ open alert æ—¶ç½® `requires_explicit_unlock`ã€è®° `concern_on_open_alert`ã€é€šçŸ¥æœ¬äººã€‚è¢«æ‹’çš„ Concern é›¶å‘Šè­¦è¡Œé›¶é€šçŸ¥ï¼›è¢«æŽ¥å—çš„ Concern ä¸é€ ç¬¬äºŒä¸ªå‘Šè­¦ã€ä¸è§£é™¤å‘Šè­¦ã€ä¸äº§ç”Ÿæœ¬äºº `behavior_pings` è¯æ®ã€‚èµ„æ ¼ç”±æœåŠ¡ç«¯æ‰§è¡Œï¼›GM æŽ§åˆ¶å°æŒ‰é’®é—¨æŽ§åªæ˜¯ç¤¼è²Œï¼Œä¸æ›¿ä»£æœåŠ¡ç«¯æ‹’ç»ã€‚
- æ­£å¸¸ä¸” coverage å¯éªŒè¯æ—¶ä¿æŒå®‰é™ï¼›å·²çŸ¥è®¾å¤‡/App/æƒé™/åŽå°å®ˆæŠ¤å¤±æ•ˆæ—¶æ˜¾ç¤ºæŒç»­ `Limited`ï¼Œç›´åˆ°æœåŠ¡ç«¯å¯éªŒè¯æ¢å¤ã€‚æœªçŸ¥ä¸èƒ½è¢«å±•ç¤ºæˆå®‰å…¨æˆ–æ­£å¸¸ã€‚
- ä»¥ä¸‹å…³äºŽ live ping è‡ªåŠ¨è§£é™¤çš„æ—§æ•°æ®åº“è¡Œä¸ºå±žäºŽ**å¾…è¿ç§»çš„åŽ†å²å®žçŽ°**ï¼Œä¸å¾—å†ä½œä¸ºæ–°åŠŸèƒ½è®¾è®¡ä¾æ®ã€‚

---

## å‘Šè­¦ç±»åž‹

| cause | è§¦å‘æ¡ä»¶ | è¯´æ˜Ž |
|---|---|---|
| `unusual_silence` | è¶…è¿‡æ²‰é»˜é˜ˆå€¼æ— æ´»åŠ¨ | æœ€å¸¸è§ï¼Œè¢«åŠ¨æ£€æµ‹ |
| `dark_device` | æ²‰é»˜æ—¶é—´æ›´é•¿ï¼ˆé˜ˆå€¼ Ã—2ï¼‰| unusual_silence çš„å‡çº§ç‰ˆ |
| `sos` | ç”¨æˆ·ä¸»åŠ¨è§¦å‘ | ç«‹å³è·³åˆ°é«˜ä¼˜å…ˆçº§ |

---

## æ²‰é»˜é˜ˆå€¼ï¼ˆ`silence_threshold`ï¼‰

å½“å‰å®žçŽ°æ˜¯ç›®æ ‡æ¨¡åž‹çš„è¿‡æ¸¡å±‚ã€‚æœ€ç»ˆæ–¹å‘è§ [[Usual Behavior Model]]ï¼šç”¨é•¿æœŸã€è·¨è®¾å¤‡ã€å¸¦ confidence çš„ usualness / unusualness åˆ¤æ–­æ¥å†³å®š alert timingï¼Œè€Œä¸æ˜¯åªä¾èµ–ä¸€ä¸ªå›ºå®š timeoutã€‚

Gate 1 containment å·²äºŽ 2026-07-19 éƒ¨ç½²ç”Ÿäº§ï¼›live threshold æš‚æ—¶å†»ç»“ä¸ºç¡®å®šæ€§ã€å¯è§£é‡Šçš„ sensitivity fallbackï¼Œæ±¡æŸ“æˆ–è¿‡æ—¶çš„ learned profile ä¸å‚ä¸Žå®‰å…¨åˆ¤æ–­ï¼š

| sensitivity | ADR-0022 production live threshold |
|---|---|
| `high` / sensitive | 1.5 å°æ—¶ |
| `balanced` | 2.25 å°æ—¶ |
| `low` / relaxed | 3 å°æ—¶ |

ADR-0022 å·²äºŽ 2026-07-19 å‘å¸ƒç”Ÿäº§ï¼Œæ¢å¤ç”¨æˆ·ç•Œé¢å·²ç»æ‰¿è¯ºçš„ additive semanticsï¼šneutral base 1.5hï¼Œ`high=+0m` â†’ 1.5hã€`balanced=+45m` â†’ 2.25hã€`low=+90m` â†’ 3hã€‚è¯¥ä¿®æ­£åªæ›¿æ¢ `private.silence_threshold()` ä¸Žç›¸åŒçš„å‰ç«¯ helper presetï¼›ä¸ä¿®æ”¹ Profileã€sleepã€activity evidenceã€monitoring directionã€alert stage æˆ– GM 6/24h æè¿°åˆ†æ®µã€‚

`sleep_start_utc` / `sleep_end_utc` ä¸ä¼šç›´æŽ¥æ”¹å˜è¿™ä¸ª thresholdï¼›ç¡çœ çª—æ˜¯ç‹¬ç«‹ gateã€‚`process_escalations()` åªæœ‰åœ¨ `now() - last_behavior_at > private.silence_threshold(user)` ä¸”ä¸åœ¨ `private.is_in_sleep_window(user, now())` æ—¶æ‰åˆ›å»º/å‡çº§ silence alertã€‚

å‰ç«¯ Routine çš„ Alert Threshold åº”é€šè¿‡ `public.my_routine_status()` æ˜¾ç¤ºæœåŠ¡ç«¯çœŸå®žå€¼ï¼Œä¸è¦ç”¨æœ¬åœ°ä¼°ç®—å€¼è§£é‡Šå‘Šè­¦ã€‚

`sensitivity` æ˜¯ç”¨æˆ·è°ƒæ•´å·¥å…·ï¼Œä¸æ˜¯æ¨¡åž‹æœ¬èº«ã€‚AI routine profile åœ¨ Gate 1 æ˜¯ consent-gatedã€aggregate-only çš„æœªæ¥/å½±å­è¾“å…¥ï¼Œä¸èƒ½è‡ªåŠ¨é©±åŠ¨ live thresholdã€‚åŽç»­åªæœ‰è¾¾åˆ° ADR-0021 çš„ shadow evidence å’Œç‹¬ç«‹ promotion gate åŽï¼Œlearned model æ‰å¯èƒ½é‡æ–°è¿›å…¥ runtimeã€‚

---

## å‘Šè­¦é˜¶æ®µï¼ˆ`stage`ï¼‰

```
self â†’ group â†’ community â†’ terminal
```

æ¯ä¸ªé˜¶æ®µæœ‰ä¸åŒçš„é€šçŸ¥èŒƒå›´å’Œå‡çº§é—´éš”ï¼š

| stage | é€šçŸ¥å¯¹è±¡ | å‡çº§é—´éš” |
|---|---|---|
| `self` | ä»…ç”¨æˆ·è‡ªå·± | çº¦ 1Ã— é˜ˆå€¼ |
| `group` | ç”¨æˆ·æ‰€åœ¨ç¾¤ç»„çš„ watching æˆå‘˜ | çº¦ 1Ã— é˜ˆå€¼ |
| `community` | ç¤¾åŒºæˆå‘˜ | çº¦ 1Ã— é˜ˆå€¼ |
| `terminal` | æœ€ç»ˆé€šçŸ¥ï¼Œä¸å†å‡çº§ | â€” |

---

## æ ¸å¿ƒå‡½æ•°ä¸Žè§¦å‘å™¨

### `private.process_escalations()`
- **è§¦å‘**ï¼špg_cron æ¯åˆ†é’Ÿè°ƒç”¨
- **é€»è¾‘**ï¼š
  1. æ‰«ææ‰€æœ‰ `device_state` è®°å½•
  2. åªè¯»å– `ingest_version=2`ã€`abs(received_at-at)<=5m` çš„æœåŠ¡ç«¯å¯ä¿¡è¯æ®ï¼›åŽ†å²/ç¦»çº¿ replay ä¸å¯åˆ·æ–° live safety
  3. è‹¥è¶…è¿‡ `silence_threshold` ä¸”ä¸åœ¨ç¡çœ çª— â†’ åˆ›å»ºæˆ–å‡çº§ alert
  4. è°ƒç”¨ `private.notify_stage()` å‘é€é€šçŸ¥
  5. è°ƒç”¨ `private.trigger_push_dispatch()` è§¦å‘æŽ¨é€

### `private.apply_liveness_side_effects()`ï¼ˆå…±äº« validator å†…éƒ¨ï¼‰
- Gate 1 åˆ é™¤ `handle_behavior_ping_insert` triggerï¼›ç›´æŽ¥æ’å…¥ã€åŽ†å²å¯¼å…¥å’Œ v1 fallback éƒ½ä¸èƒ½è§¦å‘å®‰å…¨å‰¯ä½œç”¨ã€‚
- åˆæ ¼ live v2 äº‹ä»¶ç”¨æœåŠ¡ç«¯ `received_at` æ›´æ–° heartbeatã€‚
- ADR-0039 ç›®æ ‡è¯­ä¹‰ä¸‹ï¼Œåˆæ ¼ live v2 äº‹ä»¶ä¹Ÿåªæ›´æ–° activity/coverageï¼Œä¸èƒ½è§£é™¤ open alertã€‚ä»“åº“æˆ–ç”Ÿäº§è‹¥ä»å­˜åœ¨è‡ªåŠ¨è§£é™¤è·¯å¾„ï¼ŒæŒ‰ [[Known Issues]] ä½œä¸ºå¾…è¿ç§»ç¼ºå£å¤„ç†ã€‚
- åŒ user/source/è§‚å¯Ÿæ—¶é—´äº”åˆ†é’Ÿæ¡¶çš„è‡ªåŠ¨ä¿¡å·å¯è¿”å›ž `coalesced`ï¼›å³ä½¿æœªæ–°å¢žé‡å¤è¡Œï¼Œå½“å‰åˆæ ¼äº‹ä»¶ä»å¯åˆ·æ–° live heartbeatã€‚manual ä¸ coalesceã€‚

### `private.is_in_sleep_window(_user_id, _now)`
- åˆ¤æ–­å½“å‰æ—¶é—´æ˜¯å¦åœ¨ç”¨æˆ·ç¡çœ çª—å†…
- **å…³é”®**ï¼šå°† `_now` è½¬ä¸ºç”¨æˆ·æœ¬åœ°æ—¶åŒºåŽå†ä¸Ž `sleep_start/end` æ¯”è¾ƒ
- æ”¯æŒè·¨åˆå¤œçª—å£ï¼ˆå¦‚ 23:00 â†’ 07:00ï¼‰
- æœ‰åŠ¨æ€å»¶é•¿é€»è¾‘ï¼šè‹¥ç”¨æˆ·åœ¨ç¡çœ å‰ 1 å°æ—¶å†…æœ‰æ´»åŠ¨ï¼Œçª—å£å¯å»¶é•¿è‡³å¤š 3 å°æ—¶
- è¯¦è§ [[Sleep Window]]

### `private.notify_stage(_alert_id)`
- æ ¹æ® alert çš„å½“å‰ stage å‘å¯¹åº”æŽ¥æ”¶äººå†™å…¥ `notifications` è®°å½•
- `self` â†’ ä»…å†™ç»™ç”¨æˆ·è‡ªå·±
- `group` â†’ å†™ç»™æ‰€æœ‰ `watching=true` çš„ç¾¤ç»„æˆå‘˜
- `community` â†’ å†™ç»™ç¤¾åŒºæˆå‘˜
- `terminal` â†’ æœ€ç»ˆé€šçŸ¥

---

## å‘Šè­¦ç”Ÿå‘½å‘¨æœŸçŠ¶æ€æœº

```
[æ— å‘Šè­¦]
    â”‚ æ²‰é»˜è¶…é˜ˆå€¼ + ä¸åœ¨ç¡çœ çª—
    â–¼
[open / self]  â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ ç”¨æˆ·æœ¬äººåˆ»æ„å“åº”åŠ¨ä½œ â†’ [resolved / self-confirmed]
    â”‚ è¶…æ—¶æœªå“åº”
    â–¼
[open / group]  â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ ç…§é¡¾è€…/Guardian å¤–éƒ¨ç¡®è®¤ â†’ [resolved / caregiver-confirmed]
    â”‚ è¶…æ—¶æœªå“åº”
    â–¼
[open / community]
    â”‚ è¶…æ—¶æœªå“åº”
    â–¼
[open / terminal]

ä»»æ„é˜¶æ®µï¼š
    â”œâ”€â”€ è¿›å…¥ç¡çœ çª— â†’ paused_until = ç¡çœ çª—ç»“æŸæ—¶é—´
    â””â”€â”€ åˆæ ¼è¢«åŠ¨ ping â†’ åªæ›´æ–° activity/coverageï¼›ä¸æ”¹å˜ alert lifecycle
```

[Codex Â· 2026-07-19 20:35 +06:00] Gate 1 migrationã€`ping`/`update-routine-profile` Edge Functions ä¸Ž main-backed PWA å·²éƒ¨ç½²ç”Ÿäº§ï¼›çº¿ä¸Š catalogã€æƒé™ã€cronã€å‡½æ•°æ‹’ç»å¼çƒŸæµ‹ä¸ŽçŽ°æœ‰ production alias å‡å·²å¤æ ¸ã€‚

---

## ADR-0023 accepted candidate hierarchyï¼ˆå°šæœª liveï¼‰

å½“å‰ production ä»ä¸¥æ ¼ä½¿ç”¨ ADR-0022 `1.5h + 0/45/90m`ã€‚ADR-0023 åªæŽˆæƒ replay/shadowï¼š

1. comparable-context personal p95ï¼›
2. personal-global p95ï¼›
3. privacy-qualified Routine-mode cohort priorï¼›
4. deterministic threshold ä»…ä½œ emergency failsafeã€‚

`effective silence` ä»Žæœ€è¿‘ä¸€æ¬¡åˆæ ¼æœ¬äºº session ç»“æŸå¼€å§‹ï¼Œåªç´¯è®¡ monitor-eligible timeï¼›ä»…æ‰£é™¤æœ‰ provenance çš„ accepted sleep/quiet intervalã€‚ç¡çœ ä¸èƒ½ä½œä¸º boolean gate æŠŠæ•´æ™šå¢™é’Ÿæ—¶é—´å¸¦åˆ°æ¸…æ™¨ã€‚å€™é€‰è¾¾åˆ° threshold å‰åŽéƒ½è¦åŽŸå­é‡æŸ¥æ–°æœ¬äººå¯ä¿¡æ´»åŠ¨ã€‚

Routine-mode cohort ä»¥ `regular_9to5 / semester_break / shift_irregular` ä¸‰ç±»ä¸º canonicalã€‚å…ˆç®—æ¯ä¸ªåˆæ ¼è´¡çŒ®è€…çš„ neutral p95ï¼Œå† robust aggregateï¼›ç¦æ­¢å¹³å‡ raw ping/heartbeatã€‚Sensitivity ç»§ç»­åœ¨ neutral baseline åŽåº”ç”¨ `+0/+45/+90m`ï¼Œä¸å‚ä¸Žå­¦ä¹ ã€‚

Replay/shadow åªè®°å½•å€™é€‰ threshold/deadline/basis/confidenceï¼Œä¸å¾—åˆ›å»ºã€å‡çº§ã€å»¶è¿Ÿã€æš‚åœã€è§£é™¤æˆ–é€šçŸ¥ alertã€‚ä»»ä½• live promotion è¦å•ç‹¬ accepted ADRã€‚

[Codex Â· 2026-07-27 08:34 +06:00] æœ¬åœ° candidate å·²å®žçŽ°è‡³ commit `e8b5d92`ï¼šshadow recorder çš„ population ä»…æ˜¯ `device_state` ç”¨æˆ·ä¸Ž active monitored membership çš„ DISTINCT äº¤é›†ï¼Œä¸ä»¥çŽ°æœ‰ alertã€Guardianã€device statusã€profile/context/coverage/sleep/session é¢„ç­›ï¼›å®Œæ•´ evaluator è¾“å‡ºå…ˆåŽŸå­æ ¡éªŒï¼Œå†åªå†™ shadow tableã€‚Guardian æ ‡å¿—è¢« schema CHECK ä¸Ž evaluator/recorder å›ºå®šä¸º falseï¼ŒçŽ°æœ‰ Guardian-confirmed-safe åŽæœ¬äººä»æ— å¯ä¿¡æ´»åŠ¨ 30 åˆ†é’Ÿçš„ live state machine/function hash æœªæ”¹å˜ã€‚å½“å‰ recorder æ˜Žç¡®è¿”å›ž `fixture_only_unscheduled` / `operational_shadow=false`ï¼Œæ²¡æœ‰ç”Ÿäº§æˆ– live æƒé™ã€‚

---

## Guardian ç¡®è®¤å®‰å…¨

å½“ Guardian æ‰‹åŠ¨ç¡®è®¤æŸç”¨æˆ·å®‰å…¨æ—¶ï¼š
1. å†™å…¥å¸¦ Guardian provenance çš„å¤–éƒ¨ç¡®è®¤äº‹ä»¶ï¼›**ä¸å¾—**å†™æˆç”¨æˆ·çš„ `manual_checkin` æˆ–æœ¬äºº activity
2. ä¾æ®å½“å‰ lifecycle å…³é—­/è½¬å…¥ caregiver-confirmed çŠ¶æ€ï¼Œå¹¶ä¿ç•™å®¡è®¡æ¥æº
3. ç»™ç›¸å…³ç…§é¡¾é¢å‘é€å·²å¤„ç†çŠ¶æ€ï¼›åŽ†å²é€šçŸ¥ä¸å¾—ä¼ªè£…åˆ é™¤ä¸ºâ€œä»Žæœªå‘ç”Ÿâ€
4. ä¿ç•™/é‡å‘ç”¨æˆ·è‡ªèº« nudgeï¼Œæé†’ç”¨æˆ·ä»éœ€æœ¬äººåˆ»æ„å“åº”ï¼›é‡å¤ç¡®è®¤ä¸èƒ½æ— é™å»¶æœŸåŽç»­å®ˆæŠ¤

> è®¾è®¡æ„å›¾ï¼šGuardian çš„ç¡®è®¤åªä»£è¡¨"å¤–éƒ¨è§†è§’å®‰å…¨"ï¼Œä¸èƒ½æ›¿ä»£ç”¨æˆ·è‡ªå·±çš„è®¾å¤‡æ´»åŠ¨ã€‚ç”¨æˆ·ä»éœ€äº²è‡ªæ‰“å¼€ App äº§ç”ŸçœŸå®ž pingã€‚

ADR-0023 æ˜Žç¡®ï¼šGuardian confirmation ä¸å¯ä½œä¸ºæœ¬äºº activityã€ä¸å¯è®­ç»ƒ personal/cohort gapã€ä¸å¯é‡ç½®æœ¬äºº `effective silence`ã€‚å½“æœ¬äººå¯ä¿¡æ´»åŠ¨ä»ç¼ºå¤±ä¸”æ—¢æœ‰çŠ¶æ€æœºè¦æ±‚æ—¶ï¼Œä¿ç•™ 30 åˆ†é’Ÿ re-alertï¼›é‡å¤ç¡®è®¤ä¸èƒ½æ— é™å»¶æœŸã€‚

è¯¦è§ [[Guardian Confirm]]

---

## ç›¸å…³ç¬”è®°
- [[Behavior Pings]]
- [[Usual Behavior Model]]
- [[Sleep Window]]
- [[Notification Flow]]
- [[Guardian Confirm]]
- [[Monitoring Direction]]

---

## Per-group alert surface boundary

[Codex Â· 2026-07-27 11:27 +06:00]

Alert ä»æ˜¯æŒ‰ `user_id` çš„å…¨å±€ç”Ÿå‘½å‘¨æœŸè®°å½•ï¼›ä¸€ä¸ªç”¨æˆ·åªè¦åœ¨ä»»ä¸€ active membership ä¸­ `monitored=true`ï¼ŒçŽ°æœ‰ `process_escalations` å°±å¯èƒ½åˆæ³•åœ°äº§ç”Ÿä¸€ä¸ª open alertã€‚å±•ç¤ºå±‚å¿…é¡»å¦å¤–å¥—ç”¨å½“å‰ç»„æˆå‘˜æŽˆæƒï¼šä¸¤ä¸ª group activity RPC çš„ `alerted` éƒ½æ˜¯ `current_membership.monitored AND global_open_alert_exists`ã€‚è¿™ä¸æ”¹å˜ alert åˆ›å»ºã€stageã€Guardian 30 åˆ†é’Ÿ re-alertã€ADR-0022 live threshold æˆ–é€šçŸ¥ fan-outã€‚

ä¿®å¤ï¼š`20260727090000_scope_group_alerts_to_monitoring_direction.sql` å·²äºŽ 2026-07-27 åº”ç”¨ productionã€‚è¿ç§»åªæ›¿æ¢ä¸¤ä¸ª group activity RPCï¼›`process_escalations` ä¸Ž `private.notify_stage` çš„ç”Ÿäº§å‡½æ•°å“ˆå¸Œå‰åŽä¸å˜ï¼Œå› æ­¤å‘Šè­¦åˆ›å»ºã€å‡çº§ã€è§£é™¤ä¸Žé€šçŸ¥ fan-out å‡æœªè¢«æœ¬æ¬¡å‘å¸ƒæ”¹å†™ã€‚


## ADR-0028 shadow population intersection repair

[Codex Â· 2026-07-29 07:52 +06:00]

Operational adaptive-shadow evaluation now uses the accepted exact population: a user must have `device_state` and at least one active membership with `monitored=true`. A monitored-only user without device state and a device-only user whose membership is unmonitored are both excluded; neither receives a subject context nor an operational candidate evaluation.

This changes shadow-only evidence selection, not live alert authority. ADR-0022, `process_escalations`, `notify_stage`, live alert tables, scheduler absence, 35-day identifiable retention and k<10 suppression remain unchanged. Claude A01R2 independently returned PASS with zero blockers.


## ADR-0028 adaptive shadow judgment completed

[Codex Â· 2026-07-29 08:08 +06:00]

The adaptive path accumulates source-identified evidence, normalizes immutable as-of context, evaluates every eligible monitored-device subject, and records only first/change/hourly shadow detail under a 36-row/user/UTC-day cap. Invalid timezone/future provenance becomes stable unreplayable state; consent withdrawal blocks cohort eligibility pending rebuild.

This is evidence-only. It does not call escalation/push functions or write `alerts`, `alert_events`, or `notifications`; ADR-0022 remains the only live authority. Group monitoring direction remains per member: unmonitored directions are excluded from both live group routing and adaptive-shadow population.

[Codex Â· 2026-07-29 09:21 +06:00] The evidence-only foundation shipped in `v0.5.21`, still disabled and unscheduled. Production `process_escalations` and `notify_stage` hashes are unchanged, so the per-group monitoring opt-out and current live alert path remain authoritative.

[Codex Â· 2026-07-29 23:04 +06:00] v0.5.22 is live. Under accepted ADR-0031, GM may temporarily mute a user only for future automatic silence/dark-device alert creation; existing alerts and their escalation/visibility continue, and ordinary users cannot call the GM RPCs. ADR-0022 remains the normal live authority; no Adaptive P2 or Phase-2 Cron was enabled.

[Codex Â· 2026-07-29 23:12 +06:00] ADR-0028 canary hash comparison is now line-ending deterministic without relaxing authority: LF-normalized `silence_threshold` SHA-256 stays `686116ef8f2df1d78f6d0d48ded8019555f283b098eeb5d354cfa1c14ebbcdca`; unknown definitions remain rejected. Production committed canary passed 7/7 with zero `alerts`/`alert_events`/`notifications` DML and adaptive Cron 0.

## History-seeded live threshold and sleep gate

[Codex Â· 2026-07-30 00:50 +06:00]

Production `private.silence_threshold` now selects the active shadow version's latest valid `personal_global` profile as the immediate starting point. The fixed sensitivity thresholds remain floors (`90/135/180m`), not starting templates when valid history exists. Canonical-v2 sessions after the selected profile's evidence boundary may only extend that baseline; advancing the profile boundary absorbs/replaces the temporary extension. The final value is capped at 600 minutes.

`process_escalations` now gates every silence-alert creation path with `private.sleep_relaxed` and auto-resolves an open silence alert during configured sleep or the two-hour post-wake grace. `device_state.status='alert'` no longer bypasses this gate. Dark-device detection remains the independent 18-hour rule; GM mute semantics remain unchanged.

Production readback after deployment: Chunwei retained p95 295m / 154 samples and now evaluates to 312m with later v2 extension, instead of 90m. The minute cron succeeded after deployment and there were zero open silence or dark-device alerts.

## âš ï¸ ä¸ŠèŠ‚ã€ŒHistory-seeded live threshold and sleep gateã€å·²ä½œåºŸ

[Claude Â· 2026-08-09 21:47 +06:00]

è¯¥èŠ‚æè¿°çš„ `personal_global` profile èµ·ç‚¹ã€`90/135/180m` å›ºå®š floor ä¸Ž 600 åˆ†é’Ÿ cap æ˜¯ **ADR-0037 ä¹‹å‰**çš„å®žçŽ°ï¼Œå·²äºŽ 2026-08-04 è¢«
`silence_threshold_reads_normal_bounds` / `account_normal_upper_bound` å–ä»£ï¼Œå¹¶åœ¨ S2.3 å®Œæˆå¥‘çº¦è¿ç§»ã€‚

**çŽ°è¡ŒçœŸç›¸**ï¼š`private.silence_threshold` åªè¯» `public.account_normal_bounds` ä¸­ `has_usable_signal` çš„æœ€æ–°ä¸€è¡Œï¼›æ— å¯ç”¨è¯æ®å³è¿”å›ž `NULL`ï¼ˆä¸æ˜¯æ¨¡æ¿ã€ä¸æ˜¯ 0ï¼‰ã€‚æ•æ„Ÿåº¦åªåšåŠ æ³• bufferï¼ˆhigh 0 / balanced 45 / low 90ï¼‰ï¼Œ**å½“å‰å®žçŽ°æ— ä¸Šé™ cap**ã€‚`alert_gap_profiles` æ˜¯å½±å­å­¦ä¹ è¯æ®ï¼Œæ°¸è¿œä¸èƒ½æˆä¸º live authorityã€‚

ä¿ç•™åŽŸèŠ‚ä»…ä¾›è¿½æº¯ï¼Œä¸å¾—ä½œä¸ºæ–°åŠŸèƒ½è®¾è®¡ä¾æ®ã€‚


---

## 业务模块：Behavior Pings

## ADR-0045 æ›´æ–°ï¼šé»˜è®¤æœ¬äººæ´»åŠ¨è§£é™¤ï¼ˆæœ¬åœ°å®žçŽ°ï¼Œå°šæœªä¸Šçº¿ï¼‰

[Codex Â· 2026-09-23 20:11 +06:00]

ç”¨æˆ·å·²æ˜Žç¡®æ›¿ä»£æ—§çš„â€œè¢«åŠ¨æ´»åŠ¨æ°¸ä¸è§£é™¤â€è§„åˆ™ã€‚é»˜è®¤ silence/dark_device/concern åœ¨æ£€æµ‹åˆ°å‘Šè­¦æ‰“å¼€ä¹‹åŽã€æ¥æºä¸Žè´¦æˆ·æ­£ç¡®ã€v2 ä¸”åŠæ—¶é€è¾¾çš„æœ¬äººæ´»åŠ¨æ—¶è‡ªåŠ¨è§£é™¤ï¼›å¿ƒè·³ã€æœªæ¥æ—¶é—´ã€åŽ†å²è¡¥ä¼ åŠä»–äººæ“ä½œä¸ç®—æœ¬äººæ´»åŠ¨ã€‚æŒ‡å®šçš„æœ‰æ•ˆå®ˆæŠ¤è€…å¯ä¸ºå…¶è¢«å®ˆæŠ¤è€…å¼€å¯ pattern è¦æ±‚ï¼Œé»˜è®¤å…³é—­ï¼›ä»»ä¸€æœ‰æ•ˆè¦æ±‚ç”Ÿæ•ˆï¼Œè§£é™¤å…³ç³»åŽä¸å†ç”Ÿæ•ˆã€‚æœåŠ¡å™¨æ ¡éªŒ patternï¼Œæ™®é€šæŒ‰é’®åŠæ—§ RPC ä¸å¾—ç»•è¿‡ã€‚æ™®é€šé€šçŸ¥ä½¿ç”¨â€œä¸€åˆ‡å®‰å¥½â€æŒ‰é’®ï¼Œç‚¹é€šçŸ¥æ­£æ–‡åªæ‰“å¼€ç•Œé¢ã€‚SOS ä¿ç•™æ˜Žç¡®æ‰‹åŠ¨ç¡®è®¤ï¼Œé»˜è®¤ä¹Ÿä¸è¦æ±‚ patternã€‚

æ–°è¿ç§»ï¼š`20260923054905_activity_auto_resolution_guardian_pattern.sql`ã€‚æ´»åŠ¨è§£é™¤ä¿ç•™åŽ†å²å¹¶é‡å¼€è¢«åŠ¨ç›‘æµ‹ epochï¼Œé¿å…æ—§æ¼ç­¾é“¾ç«‹å³é‡å¤å‘Šè­¦ï¼›æ’¤å›žæœªå‘é€çš„æ—§é€šçŸ¥ï¼Œæ¢å¤é€šçŸ¥åªå‘æœ¬äººåŠæ—¢æœ‰æ¶‰åŠè€…ã€‚Android ä¸å†å‡­æœ¬åœ°è§£é”æˆ– UsageStats æå‰æ˜¾ç¤ºå®‰å…¨æˆåŠŸã€‚

æœ¬åœ°éªŒè¯ï¼š105 æ–‡ä»¶ / 629 é¡¹ Vitest é€šè¿‡ï¼›typecheckã€ç½‘é¡µ build é€šè¿‡ï¼›æœ€åŽ SQL é”é¡ºåºå’Œ SOS ä¿®æ­£åŽ 22 é¡¹éš”ç¦» PostgreSQL å›žå½’å†æ¬¡é€šè¿‡ã€‚æ­¤å‰ Android Java ç¼–è¯‘é€šè¿‡ã€‚å°šæœªåšå®Œæ•´ Supabase è¿ç§»å›žæ”¾ã€çœŸæœºéªŒæ”¶æˆ–éƒ¨ç½²ã€‚æœ¬èŠ‚æ˜¯çŽ°è¡Œå·²æŽ¥å—æ–¹å‘ï¼›ä¸‹æ–‡ç›¸å†²çªçš„æ—§æ´»åŠ¨è§£é™¤è§„åˆ™ä»…ä»£è¡¨åŽ†å²å®žçŽ°ï¼Œä¸å¯ç”¨äºŽå¦å®š ADR-0045ã€‚

# Behavior Pings

#business-logic #kc

> `behavior_pings` æ˜¯ç”¨æˆ·æ´»è·ƒè¯æ®çš„äº‹å®žè¡¨ï¼›Gate 1 live safety çš„å”¯ä¸€æƒå¨æ˜¯å…¶ä¸­ç”±å…±äº«æœåŠ¡ç«¯ validator å†™å…¥ã€ç¬¦åˆæ—¶é—´çº¦æŸçš„ v2 è¡Œã€‚æ‰€æœ‰å‘Šè­¦é€»è¾‘ä¸å¾—æŠŠ `device_state` ç¼“å­˜ã€åŽ†å² v1 è¡Œæˆ–å®¢æˆ·ç«¯æ—¶é—´å•ç‹¬å½“çœŸç›¸ã€‚
> é•¿æœŸç›®æ ‡ï¼šè¿™äº› ping ä¸æ˜¯ä¸ºäº†â€œè¯æ˜Žç”¨æˆ·ä¸€ç›´åœ¨çº¿â€ï¼Œè€Œæ˜¯ä¸ºäº†åœ¨éšç§å…‹åˆ¶å‰æä¸‹å­¦ä¹ ç”¨æˆ·ä¸Žå„è®¾å¤‡çš„ usual relationshipï¼Œæ”¯æ’‘ [[Usual Behavior Model]]ã€‚

---

## è¡¨ç»“æž„

```sql
behavior_pings (
  id              bigint PK,
  user_id         uuid,
  kind            text DEFAULT 'app',
  source          text,
  at              timestamptz,        -- client observed time; analysis evidence
  received_at     timestamptz,        -- server receipt time
  ingest_version  smallint DEFAULT 1,
  event_id        uuid
)
```

---

## Ping ç±»åž‹ï¼ˆ`kind`ï¼‰

| kind | è§¦å‘åœºæ™¯ |
|---|---|
| `app` | ç”¨æˆ·æ­£å¸¸ä½¿ç”¨ Appï¼ˆé»˜è®¤ï¼‰|
| `manual_checkin` | ä»…ç”¨æˆ·æœ¬äººåˆ»æ„ Check-inï¼›Guardian/ç…§é¡¾è€…ç¡®è®¤å¿…é¡»å†™å…¥ç‹¬ç«‹ provenanceï¼Œä¸å¾—ä¼ªè£…æˆç”¨æˆ· activity |
| `heartbeat` | åŽå°å¿ƒè·³ï¼ˆApp åœ¨å‰å°æ—¶å®šæœŸå‘é€ï¼‰|
| `window_focus` | æµè§ˆå™¨çª—å£èŽ·å¾—ç„¦ç‚¹ |
| `interaction` | ç”¨æˆ·ä¸Žé¡µé¢äº¤äº’ï¼ˆç‚¹å‡»ã€æ»šåŠ¨ç­‰ï¼‰|

---

## Ping çš„è§¦å‘é“¾è·¯

### Web/PWA çŽ¯å¢ƒ
```
å®‰è£…æ€ PWA / Tauri / Capacitor ä¸­å”¯ä¸€ signal collector
    â†’ user-partitioned IndexedDB v2
    â†’ authenticated record_behavior_ping(s) RPC
    â†’ shared private validator
    â†’ behavior_pings v2 + bounded live side effects
```

æ™®é€š browser tab çš„ automatic source ä¸º nullï¼šå¯ä»¥ä¿ç•™æœ¬åœ° ownerless/quarantined è®°å½•ç”¨äºŽè¯Šæ–­ï¼Œä½†æ°¸ä¸ä¸Šä¼ ã€æ°¸ä¸æˆä¸º safety evidenceã€‚`PassivePingBoot` åªé…ç½® native token/notificationï¼Œä¸å†å¯åŠ¨ç¬¬äºŒå¥— Web heartbeat collectorã€‚

### Native Android APK

Gate 1 source contract: Capacitor native plugin + Android system-signal path ä½¿ç”¨ POST JSONï¼Œtoken ä¸æ”¾ query stringã€‚è¯¥ Android Java æ”¹åŠ¨å·²è¿›å…¥ main æºç ï¼Œä½†å½“å‰å·²å‘å¸ƒ APK æœªé‡å»ºï¼›åªæœ‰ä¸‹ä¸€æ¬¡ Android binary release æ‰ä¼šå®žé™…äº¤ä»˜ã€‚

```
native.ts -> PassivePing.configure(supabaseUrl, token, toggles)
          -> PassivePingPlugin stores token + feature toggles
          -> UsageStats / Activity Recognition / app-open signals
          -> POST /ping {token,event_id,observed_at,source}
          -> service-only record_behavior_ping_for_user
          -> shared validator -> behavior_pings v2
```

Supported Android evidence includes app open/resumeã€UsageStats-derived recent activityã€Activity Recognition transitions and configured charger/app activity paths. It remains best-effort under force-stop/OEM/offline/background limitsï¼›ä¸èƒ½å£°ç§°ä¸º medical-grade livenessã€‚

Rules:
- Native event pings respect user toggles: `phone_unlock` and `phone_charger`.
- These pings are evidence of activity, not a medical-grade liveness guarantee. Server alert logic must continue using `behavior_pings.max(at)` and tolerate missing passive signals.
- If APK reliability becomes critical, next design should add an opt-in foreground monitoring mode with persistent notification + battery optimization guidance, or expose a Tasker/MacroDroid signed ping integration for advanced users.

[Codex Â· 2026-08-14 19:48 +06:00] ADR-0042 çš„æœ¬åœ° Android å€™é€‰åœ¨ä¸Šè¿° legacy `/ping` æ—æ–°å¢žç‹¬ç«‹æ­£è¯æ®è·¯å¾„ï¼šç»‘å®šå‡­æ®åªä»¥ Android Keystore å¯†æ–‡è½ç›˜ï¼Œsequence/æ— å‡­æ®é˜Ÿåˆ—æŒä¹…åŒ–ï¼›UsageStats ä¸Šä¼ çœŸå®žäº‹ä»¶æ—¶é—´ä¸”ä¸ä¸Šä¼ åŒ…åï¼›ä»… walking/runningã€çœŸå®žä½¿ç”¨å’Œç¡®è®¤ç¨³å®š 5 ç§’çš„å……ç”µè¾¹æ²¿åˆæ ¼ï¼Œscreen-onã€stationaryã€automotiveã€åˆå§‹ç”µæºçŠ¶æ€å’Œ flap ä¸åˆæ ¼ã€‚60 ç§’å†…ç”µæºè¾¹æ²¿å…±ç”¨ correlationï¼›ç™»å‡º/æ¢å·å…ˆæ’¤é”€å¹¶æ¸…ç©ºæ—§ç»‘å®šã€å‡­æ®å’Œé˜Ÿåˆ—ã€‚WorkManagerã€manifestã€æƒé™ã€wake lockã€exact alarm ä¸Žå‰å°æœåŠ¡é»˜è®¤è¡Œä¸ºå‡æœªæ”¹å˜ï¼›å°šæœªå‡ºåŒ…/éƒ¨ç½²ï¼ŒçœŸæœºä¸Ž Play gate ä»å¼€æ”¾ã€‚

---

## Long-Term Modeling Use

`behavior_pings` çš„é•¿æœŸä»·å€¼ä¸æ˜¯å•æ¡è®°å½•ï¼Œè€Œæ˜¯åˆ†å¸ƒï¼š

- ç”¨æˆ·åœ¨ä¸åŒæœ¬åœ°å°æ—¶ã€æ˜ŸæœŸã€æ—¥åž‹ä¸­çš„æ´»è·ƒæ¦‚çŽ‡ã€‚
- ç”¨æˆ·è·¨æ‰‹æœºã€æ¡Œé¢ã€PWAã€APK çš„è®¾å¤‡èŠ‚å¥ã€‚
- å„ä¸Šä¸‹æ–‡ä¸­çš„ silent gap åˆ†å¸ƒï¼šp50 / p75 / p90 / p95 / p99ã€‚
- æŸæ®µæ²‰é»˜æ˜¯å¦å·²ç»è¶…å‡ºè¯¥ç”¨æˆ· usual patternã€‚

å½“å‰è¡¨åªä¿å­˜åŸºç¡€ metadataï¼š`user_id`ã€`kind`ã€`at`ã€‚æœªæ¥ usual model éœ€è¦æ›´å¥½åœ°åŒºåˆ† device/channel signal qualityï¼Œå¯èƒ½éœ€è¦é¢å¤–èšåˆè¡¨æˆ–æ¨¡åž‹è¡¨ï¼›è¿™å±žäºŽ schema/retention çº§å˜æ›´ï¼Œå®žæ–½å‰éœ€è¦ ADRã€‚

éšç§è¾¹ç•Œï¼šé»˜è®¤åªç”¨ metadata åš safety inferenceï¼Œä¸é‡‡é›†å†…å®¹ã€ç²¾ç¡®ä½ç½®æˆ– app/browser å†…å®¹ã€‚

### åˆæ ¼å­¦ä¹ åŒºé—´ä¸Ž coverage

[Codex Â· 2026-08-09 17:24 +06:00]

- usualness åªä»Žè®¾å¤‡ã€Appã€æƒé™ä¸ŽåŽå°ç®¡çº¿å‡å¯éªŒè¯å¥åº·çš„ coverage-valid åŒºé—´å­¦ä¹ ã€‚
- å·²çŸ¥è®¾å¤‡/App/æƒé™æ•…éšœã€force-stopã€ç¦»çº¿æœªé€è¾¾æˆ–å®ˆæŠ¤ä¸å¯ç”¨çš„åŒºé—´ï¼Œä¸å¾—å½“æˆè¯¥ç”¨æˆ·çš„æ­£å¸¸æ²‰é»˜æ ·æœ¬ã€‚
- é•¿ç¼ºå£ä¹‹åŽè‡³å°‘éœ€è¦ä¸¤ä¸ªå½¼æ­¤ç‹¬ç«‹ã€å¯æ¯”è¾ƒä¸” coverage-valid çš„æ ·æœ¬ï¼Œæ‰å¯æ¢å¤å­¦ä¹ è¯¥ä¸Šä¸‹æ–‡ï¼›å•ä¸ªâ€œæ¢å¤åŽç¢°å·§æœ‰æ´»åŠ¨â€çš„æ ·æœ¬ä¸è¶³ä»¥é‡å»ºå¸¸æ€ã€‚
- `unknown` ä¸ç­‰äºŽ `healthy`ï¼Œä¹Ÿä¸è‡ªåŠ¨ç­‰äºŽå±é™©ï¼›é¢å‘ç”¨æˆ·å¿…é¡»è¯šå®žå±•ç¤ºè¯æ®è´¨é‡ä¸Ž `Limited` çŠ¶æ€ã€‚

---

## å…³é”®è§„åˆ™

### 1. æœåŠ¡ç«¯æŽ¥æ”¶æ—¶é—´ä¸Ž v2 validator æ˜¯ live authority
- `at` æ˜¯å®¢æˆ·ç«¯è§‚å¯Ÿæ—¶é—´ï¼Œåªèƒ½ä½œä¸ºå—é™åˆ†æžè¯æ®ã€‚
- `received_at` ç”±æœåŠ¡ç«¯ç”Ÿæˆï¼›validator å†™ `ingest_version=2`ã€‚
- `abs(received_at-at)>5m`ã€æœªæ¥æ—¶é—´ã€owner ä¸ç¬¦æˆ– malformed event è¿”å›ž `invalid`ï¼Œä¸èƒ½åˆ·æ–° safetyã€‚
- alert/check-in è¿˜éœ€ `received_at` å’Œ `at` éƒ½ä¸æ—©äºŽç›¸åº” `opened_at` / `next_due_at`ã€‚

### 2. æ´»åŠ¨è¯æ®ä¸Žå‘Šè­¦å›žç­”åˆ†ç¦»
å…±äº« validator å†…çš„åˆæ ¼ live v2 äº‹ä»¶åªå¯æ›´æ–° activity/coverageï¼Œä¸å¾—è§£é™¤ open alertã€‚å‘Šè­¦å›žç­”å¿…é¡»æ˜¯ç”¨æˆ·åˆ»æ„å“åº”ã€ç‹¬ç«‹ç…§é¡¾è€…ç¡®è®¤æˆ– GM æ˜Žç¡®å…³é—­ï¼Œå¹¶ä¿ç•™å„è‡ª provenanceã€‚è¡¨ INSERT trigger å·²åˆ é™¤ï¼Œdirect insert æƒé™å·²æ’¤é”€ï¼›ä»“åº“/ç”Ÿäº§è‹¥ä»æœ‰ ping auto-resolveï¼Œæ˜¯å¾…è¿ç§»åŽ†å²è¡Œä¸ºï¼Œä¸æ˜¯çŽ°è¡Œäº§å“å¥‘çº¦ã€‚

### 3. ä¸è¦æŠŠç¼“å­˜æˆ–åŽŸå§‹ `max(at)` å½“ live safety
```sql
-- âœ… æ­£ç¡®
SELECT max(received_at)
FROM behavior_pings
WHERE user_id = $1
  AND ingest_version = 2
  AND abs(extract(epoch from (received_at - at))) <= 300

-- âŒ é”™è¯¯ï¼ˆç¼“å­˜ï¼ŒéžçœŸç›¸ï¼‰
SELECT last_heartbeat_at FROM device_state WHERE user_id = $1

-- âŒ é”™è¯¯ï¼ˆåŽ†å²/offline/client-clock å¯æ±¡æŸ“ï¼‰
SELECT max(at) FROM behavior_pings WHERE user_id = $1
```

---

## IndexedDB ç¦»çº¿ç¼“å†²

å‰ç«¯åœ¨ `src/features/signals/store.ts` ç”¨ IndexedDB v2 å­˜å‚¨æœ€è¿‘ 35 å¤©çš„ ping è®°å½•ï¼š
- ç”¨é€”ï¼šPassiveSignalCard å±•ç¤ºæœ¬åœ°ç»Ÿè®¡ï¼ˆä¸ä¾èµ–æœåŠ¡ç«¯ 200 æ¡é™åˆ¶ï¼‰
- ç¦»çº¿æ—¶ ping ä¸ä¸¢å¤±ï¼Œè”ç½‘åŽæ‰¹é‡åŒæ­¥
- æ¯è¡ŒåŒ…å«ç¨³å®š `event_id` ä¸Ž authenticated `user_id`ï¼›åªä¸Šä¼ å½“å‰ uid çš„è¡Œã€‚
- ownerlessã€æ—§æ ¼å¼ã€å…¶ä»–è´¦æˆ·æˆ–æ™®é€š browser source è¡Œæ°¸ä¹… quarantineï¼Œä¸èƒ½ç”±ä¸‹ä¸€ä¸ªç™»å½•è´¦æˆ·è®¤é¢†ã€‚
- batch æœ€å¤š 100ï¼›server é€ ordinal å›žä¼ çŠ¶æ€ã€‚`event_id` æ˜¯å”¯ä¸€ ingestion å¹‚ç­‰é”®ï¼šæ¯ä¸ªé€šè¿‡ validator çš„ä¸åŒ `event_id` å„å­˜ä¸€è¡Œï¼Œé‡å¤ `event_id` è¿”å›ž `duplicate`ã€‚
- Web interaction collector åœ¨å®¢æˆ·ç«¯æŒ‰ running collector æ˜¾å¼é™åˆ¶ä¸ºæ¯äº”åˆ†é’Ÿæœ€å¤šå‘å°„ä¸€æ¬¡ï¼›å†™å…¥é‡æ²»ç†å±žäºŽå®¢æˆ·ç«¯/æ˜¾å¼ rate limitï¼Œä¸å†ç”±æ•°æ®åº“ä¸¢å¼ƒä¸åŒäº‹ä»¶ã€‚

[Codex Â· 2026-07-19 20:35 +06:00] æœ¬èŠ‚ Gate 1 çš„ Supabase ä¸Ž Web/PWA è·¯å¾„å·²éƒ¨ç½²ç”Ÿäº§ï¼›ç”Ÿäº§ migration history è®°å½• `20260719015302`ï¼ŒEdge ä¸Ž main PWA å·²å¤æ ¸ã€‚Android åŽŸç”Ÿæºç å°šå¾…ä¸‹ä¸€æ¬¡ APK é‡å»ºäº¤ä»˜ã€‚

[Codex Â· 2026-07-29 17:28 +06:00] ADR-0029 P3 append-only migration `20260729170000` å·²é€šè¿‡ merge commit `4b45e1b` åˆå…¥æœ¬åœ° `main`ï¼Œå¹¶ä¸Žå½“å‰ P5 candidate ä¸€èµ·å®Œæˆå®Œæ•´ replayï¼›å°šæœª push æˆ–éƒ¨ç½²ï¼Œç”Ÿäº§åœ¨ release gate å‰ä»æŒ‰å·²éƒ¨ç½² migration è¡Œä¸ºè¿è¡Œã€‚

---

## ç›¸å…³ç¬”è®°
- [[Alert System]]
- [[System Overview]]
- [[Usual Behavior Model]]

[Codex Â· 2026-07-29 23:04 +06:00] v0.5.22 production now preserves distinct trusted behavior events instead of database 5-minute bucket coalescing. Emission control moved to explicit collectors: Web/PWA/Tauri interaction and Android native passive ping each enforce a 5-minute cap. Immediate production aggregate readback showed no uncontrolled amplification. Android true unlock uses `ACTION_USER_PRESENT`; charging remains supported; `ACTION_SCREEN_ON` is not treated as unlock activity.

[Codex Â· 2026-08-14 19:28 +06:00] ADR-0042 package 2 introduces a separate normalized evidence path; legacy `behavior_pings` remains unchanged. Accepted evidence is positive-only, bound to one subject installation, occurrence-time based, idempotent by immutable event/payload and sequence identity, and limited to seven-day positive correction. Upload/wake/heartbeat, raw App/package/URL/input/location/motion/Health content, and absence are never passive evidence. A late positive may change `pending|missed` to `checked_in`; it never creates a miss or changes an alert.

[Codex Â· 2026-08-14 19:59 +06:00] iOS collector now queries bounded Health history after observer wake and emits only positive pedestrian evidence; zero-result wakes do nothing and automotive-dominant intervals are excluded. Raw Health/motion values do not enter the shadow upload. Unlock/foreground and 5-second-stable charging with 60-second correlation use occurrence time. Credentials live in Keychain; binding change/logout clears credential, queue, sequence and history anchors. Significant-location remains coordinate-blind wake only: Apple documents relaunch after system termination, while user force-quit remains a required real-device proof.

[Codex Â· 2026-08-14 20:12 +06:00] Tauri Windows/macOS now reconstructs `last_input_at = sample_time - idle_duration` inside the native command and emits only a closed `direct_device_use` fact when that timestamp advances. Five-minute sampling cannot upload key/app/URL/content or idle duration; sleep/tick wrap and wall-clock guards cannot create a future event. Evidence uses a one-session credential, persisted monotonic sequence and account-partitioned retry queue; account switch/sign-out revokes then clears local state. `channel=tauri`, evidence contract and legacy shadow-health lease remain distinct.

[Codex Â· 2026-08-14 20:32 +06:00] ADR-0042 window authority is implemented locally: server UTC half-open windows finalize by historical bound-surface allowance; absence misses independent of collector health; checked-in/superseded/epoch boundary clears the derived chain. The Nth consecutive miss snapshots exactly N causal windows and opens one existing `silence/self` alert only in `passive_checkin`; shadow never opens one and legacy silence/dark-device creation skips live-passive accounts. Configured sleep/post-wake counts misses but defers open/escalation. Passive evidence cannot resolve; explicit subject/Guardian resolution starts a fresh epoch. Passive group/community copy says KC lost contact, never danger.

[Codex Â· 2026-08-14 20:44 +06:00] ADR-0042 advisory learner is implemented locally. It uses 30 complete UTC days and B=1 ranked positive-evidence gaps, excludes sleep/post-wake, shortcut, unhealthy-surface, alert-lifecycle, pending/superseded-window and contract/clock-boundary episodes, and pins eligible episode IDs plus SHA-256 provenance. Fewer than 3 episodes/3 days yields conservative R=360m; one >150% jump is clamped unless corroborated on another date. Platform floors map R to proposed D/N/H. Recommendations are immutable, subject-readable summaries, advisory-only, and retained 90 days; they never mutate contract, windows or alerts.

[Codex Â· 2026-08-14 20:52 +06:00] ADR-0042 settings/migration UX is implemented locally. Legacy users must explicitly save a required D/N/sleep choice into shadow, then complete 14 consecutive shadow days with at least one bound collector and explicitly confirm again before live authority. One activation RPC creates one immutable server revision; save failure restores last server truth. Open alerts, kill switch, missing collector, old client contract and early activation fail closed. Collector health is subject-only `Ready|Limited|Off` with device/reason/repair detail and explicitly does not pause miss counting.

[Codex Â· 2026-08-14 21:00 +06:00] ADR-0042 shadow observability and global kill switch are implemented locally. Every shadow chain reaching N records immutable `would_open|duplicate_suppressed|sleep_deferred` with exact causal window IDs and still creates no alert/notification. The service-only report returns aggregate window/arrival/late-correction/ingest/chain/alert/recommendation/job/cohort metrics plus hard-invariant counters, without subject/device/event IDs. The gate requires actual consecutive shadow duration â‰¥14 days, â‰¥20 subjects per platform/client/contract cohort, median interruptions â‰¤0.2/user/day, p90 â‰¤1/day, zero hard-invariant violations and no active global stop. Global stop prevents new activation/new passive alerts, marks affected accounts Limited, and never rewrites windows or substitutes legacy authority.

### Me permission/collection state â€” local candidate, 2026-09-19

[Codex Â· 2026-09-19 20:51 +06:00]

The local KC-PERMISSIONS-20260919 repair separates OS authorization, collection preferences and runtime capability. Me lists only supported controls; native preferences use an authenticated token lookup and await the native bridge, reporting failure instead of silently succeeding. iOS uses one native collector switch for unlock/Health/Motion/charging observations; its new read-only bridge reports CoreMotion authorization and Background App Refresh, while Health read consent remains API-unverifiable. PWA checks notification permission; Tauri checks its existing idle probe. Native resume refresh and stale-response protection are included. This candidate is NOT deployed and its new iOS method is NOT Xcode-compiled; current production/TestFlight 41 behavior must not be inferred from these source edits. See current Known Issues and the repository audit artifact for delivery/device gates.

---

## 业务模块：GM Alert Mute

---
type: business-logic
project: Keep Contact
status: accepted
adr: ADR-0031
---

# GM Alert Mute

## Purpose

GM mute is a special administrator exception for a known false-positive situation. It temporarily prevents a selected user from receiving a newly raised `silence` or `dark_device` alert when the GM already knows the absence is expected or socially awkward to escalate.

## Authority and data

- Only an authenticated user present in `app_admins` may call `gm_mute_user` or `gm_unmute_user`.
- Current state is stored in `gm_mutes`: target, GM actor, start time, optional expiry, and optional reason.
- Direct client table access is not granted; the UI uses the two SECURITY DEFINER RPCs.
- `muted_until = null` means indefinite until explicit unmute. An expired row is inert.

## Alert semantics

- Active mute excludes the target only from creation of a new `silence` or `dark_device` alert.
- Existing open alerts continue through the unchanged escalation stages and notifications.
- Unmute or expiry immediately restores ordinary new-alert evaluation.
- Mute does not write behavior evidence, refresh liveness, change monitoring direction, alter sleep or sensitivity, or grant Adaptive Shadow any live authority.

## Verification and rollback

`supabase/tests/gm_mute_user.sql` covers role ACL, state provenance, active suppression, unmute, expiry, existing-alert continuation, and the unchanged `private.silence_threshold` hash. Operational rollback is `gm_unmute_user(target)`; migration rollback, if required, restores the preceding `process_escalations()` definition and removes the GM RPC/table only after active mute state is deliberately handled.

[Codex Â· 2026-07-29 22:12]


---

## 业务模块：Guardian Confirm

## ADR-0045 æ›´æ–°ï¼šé»˜è®¤æœ¬äººæ´»åŠ¨è§£é™¤ï¼ˆæœ¬åœ°å®žçŽ°ï¼Œå°šæœªä¸Šçº¿ï¼‰

[Codex Â· 2026-09-23 20:11 +06:00]

ç”¨æˆ·å·²æ˜Žç¡®æ›¿ä»£æ—§çš„â€œè¢«åŠ¨æ´»åŠ¨æ°¸ä¸è§£é™¤â€è§„åˆ™ã€‚é»˜è®¤ silence/dark_device/concern åœ¨æ£€æµ‹åˆ°å‘Šè­¦æ‰“å¼€ä¹‹åŽã€æ¥æºä¸Žè´¦æˆ·æ­£ç¡®ã€v2 ä¸”åŠæ—¶é€è¾¾çš„æœ¬äººæ´»åŠ¨æ—¶è‡ªåŠ¨è§£é™¤ï¼›å¿ƒè·³ã€æœªæ¥æ—¶é—´ã€åŽ†å²è¡¥ä¼ åŠä»–äººæ“ä½œä¸ç®—æœ¬äººæ´»åŠ¨ã€‚æŒ‡å®šçš„æœ‰æ•ˆå®ˆæŠ¤è€…å¯ä¸ºå…¶è¢«å®ˆæŠ¤è€…å¼€å¯ pattern è¦æ±‚ï¼Œé»˜è®¤å…³é—­ï¼›ä»»ä¸€æœ‰æ•ˆè¦æ±‚ç”Ÿæ•ˆï¼Œè§£é™¤å…³ç³»åŽä¸å†ç”Ÿæ•ˆã€‚æœåŠ¡å™¨æ ¡éªŒ patternï¼Œæ™®é€šæŒ‰é’®åŠæ—§ RPC ä¸å¾—ç»•è¿‡ã€‚æ™®é€šé€šçŸ¥ä½¿ç”¨â€œä¸€åˆ‡å®‰å¥½â€æŒ‰é’®ï¼Œç‚¹é€šçŸ¥æ­£æ–‡åªæ‰“å¼€ç•Œé¢ã€‚SOS ä¿ç•™æ˜Žç¡®æ‰‹åŠ¨ç¡®è®¤ï¼Œé»˜è®¤ä¹Ÿä¸è¦æ±‚ patternã€‚

æ–°è¿ç§»ï¼š`20260923054905_activity_auto_resolution_guardian_pattern.sql`ã€‚æ´»åŠ¨è§£é™¤ä¿ç•™åŽ†å²å¹¶é‡å¼€è¢«åŠ¨ç›‘æµ‹ epochï¼Œé¿å…æ—§æ¼ç­¾é“¾ç«‹å³é‡å¤å‘Šè­¦ï¼›æ’¤å›žæœªå‘é€çš„æ—§é€šçŸ¥ï¼Œæ¢å¤é€šçŸ¥åªå‘æœ¬äººåŠæ—¢æœ‰æ¶‰åŠè€…ã€‚Android ä¸å†å‡­æœ¬åœ°è§£é”æˆ– UsageStats æå‰æ˜¾ç¤ºå®‰å…¨æˆåŠŸã€‚

æœ¬åœ°éªŒè¯ï¼š105 æ–‡ä»¶ / 629 é¡¹ Vitest é€šè¿‡ï¼›typecheckã€ç½‘é¡µ build é€šè¿‡ï¼›æœ€åŽ SQL é”é¡ºåºå’Œ SOS ä¿®æ­£åŽ 22 é¡¹éš”ç¦» PostgreSQL å›žå½’å†æ¬¡é€šè¿‡ã€‚æ­¤å‰ Android Java ç¼–è¯‘é€šè¿‡ã€‚å°šæœªåšå®Œæ•´ Supabase è¿ç§»å›žæ”¾ã€çœŸæœºéªŒæ”¶æˆ–éƒ¨ç½²ã€‚æœ¬èŠ‚æ˜¯çŽ°è¡Œå·²æŽ¥å—æ–¹å‘ï¼›ä¸‹æ–‡ç›¸å†²çªçš„æ—§æ´»åŠ¨è§£é™¤è§„åˆ™ä»…ä»£è¡¨åŽ†å²å®žçŽ°ï¼Œä¸å¯ç”¨äºŽå¦å®š ADR-0045ã€‚

# Guardian Confirm

#business-logic #kc

---

## ä»€ä¹ˆæ˜¯ Guardian/Wardï¼Ÿ

Guardian/Ward æ˜¯ KC ä¸­æœ€é«˜ä¿¡ä»»ã€æœ€å…¨é¢çš„æŒç»­ç…§é¡¾å…³ç³»ã€‚Guardian åº”åœ¨è¢«æŽˆæƒèŒƒå›´å†…çœ‹åˆ° App èƒ½è§¦è¾¾çš„å®ˆæŠ¤ä¿¡æ¯ã€coverageã€å‘Šè­¦çŠ¶æ€ä¸Žç…§é¡¾æ“ä½œï¼Œè€Œä¸æ˜¯åªæ¯”æ™®é€šç¾¤æˆå‘˜å¤šä¸€ä¸ªæŒ‰é’®ã€‚

å…³ç³»å­˜å‚¨åœ¨ `guardianships` è¡¨ï¼š`guardian_id` â†’ `ward_id`ã€‚

è¿™ä¸ªé«˜æƒé™ä»æœ‰ä¸å¯è·¨è¶Šçš„è¾¹ç•Œï¼šGuardian ä¸èƒ½å†’å…… Ward èº«ä»½ã€ä¸èƒ½æ›¿ Ward äº§ç”Ÿæœ¬äºº activity/check-inã€ä¸èƒ½æ›¿ Ward æŽˆäºˆè®¾å¤‡æƒé™ã€ä¸èƒ½è§£é” Ward è®¾å¤‡ï¼Œä¹Ÿä¸èƒ½æŠŠæœªçŸ¥æˆ–å¤±æ•ˆçš„å®ˆæŠ¤çŠ¶æ€æ ‡æˆå®‰å…¨ã€‚

---

## Guardian ç¡®è®¤å®‰å…¨çš„æµç¨‹

[Codex Â· 2026-08-09 17:24 +06:00]

å½“ Guardian åœ¨ App ä¸­ç‚¹å‡»â€œç¡®è®¤å®‰å…¨â€æ—¶ï¼š

1. å†™å…¥ç‹¬ç«‹çš„ caregiver/Guardian confirmationï¼Œè®°å½•æ“ä½œè€…ã€æ—¶é—´ã€ç›®æ ‡ã€å¯¹åº” alert ä¸Ž provenanceã€‚
2. æŒ‰ alert lifecycle å°†è¯¥äº‹ä»¶æ ‡è®°ä¸ºå¤–éƒ¨ç…§é¡¾è€…å·²ç¡®è®¤ï¼›ä¸å¾—å†™å…¥ `behavior_pings.kind='manual_checkin'`ï¼Œä¸å¾—åˆ·æ–° Ward çš„æœ¬äºº activity æˆ–è®­ç»ƒ usualnessã€‚
3. ä¿ç•™åŽ†å²é€šçŸ¥å¹¶å‘ç›¸å…³ç…§é¡¾é¢æ›´æ–°â€œå·²ç”±è°ç¡®è®¤â€çš„çŠ¶æ€ï¼Œé¿å…é‡å¤æŠ•å…¥äººåŠ›ã€‚
4. ä¿ç•™æˆ–é‡å‘ Ward æœ¬äººçš„ nudgeï¼šå¤–éƒ¨ç¡®è®¤ä¸ç­‰äºŽ Ward å·²çœ‹è§å¹¶å›žåº”ã€‚
5. è‹¥æœ¬äººå¯ä¿¡æ´»åŠ¨ä»ç¼ºå¤±ï¼Œæ—¢å®šçš„ re-check/re-alert è§„åˆ™ç»§ç»­ç”Ÿæ•ˆï¼›é‡å¤ Guardian ç¡®è®¤ä¸èƒ½æ— é™å»¶åŽå®ˆæŠ¤ã€‚

---

## ä¸ºä»€ä¹ˆä¿ç•™ self é€šçŸ¥ï¼Ÿ

Guardian çš„ç¡®è®¤åªä»£è¡¨**å¤–éƒ¨è§†è§’**çš„å®‰å…¨åˆ¤æ–­ï¼Œä¸èƒ½è¯æ˜Ž Ward æ­£å¸¸ä½¿ç”¨è®¾å¤‡ã€App æ­£å¸¸å·¥ä½œæˆ– Ward å·²å“åº”å‘Šè­¦ã€‚å› æ­¤ç³»ç»Ÿè¦æ˜Žç¡®åŒºåˆ†ï¼š

- `self-confirmed`ï¼šWard æœ¬äººçš„åˆ»æ„åŠ¨ä½œï¼›
- `caregiver-confirmed`ï¼šGuardian/ç…§é¡¾è€…çš„å¤–éƒ¨ç¡®è®¤ï¼›
- `activity observed`ï¼šè®¾å¤‡/App çš„è¢«åŠ¨æ´»åŠ¨è¯æ®ï¼›
- `coverage limited/unknown`ï¼šå®ˆæŠ¤ç®¡çº¿ä¸å¯éªŒè¯ã€‚

è¿™å››è€…ä¸å¯äº’ç›¸ä¼ªé€ ã€‚å¥åº·æ—¶å¯ä»¥å®‰é™ï¼›å®ˆæŠ¤å¤±æ•ˆæ—¶å¿…é¡»æ˜¾ç¤ºæŒç»­ `Limited`ï¼Œä¸èƒ½é é™é»˜åˆ¶é€ â€œä»åœ¨æ­£å¸¸ä¿æŠ¤â€çš„é”™è§‰ã€‚

---

## ä¸Žæ™®é€š Group / Special Attention çš„åŒºåˆ«

- æ™®é€šç»„å‘˜åªéœ€åœ¨ç»„åå•æŸ¥çœ‹æˆå‘˜çŠ¶æ€ï¼Œä¸å› å¼‚å¸¸è‡ªåŠ¨è¢«ç‰¹æ„é€šçŸ¥ã€‚
- ç”¨æˆ·å¯ç§ä¸‹ã€é»˜è®¤å…³é—­åœ°æŠŠå°‘æ•°æˆå‘˜å‹¾é€‰ä¸º `Special Attention`ï¼Œæ‰æŽ¥æ”¶é¢å¤–å¼‚å¸¸é€šçŸ¥ã€‚
- Guardian/Ward ä¸æ˜¯ Special Attention çš„åˆ«åï¼Œè€Œæ˜¯æ›´å…¨é¢ã€æŒç»­ã€åŒå‘å¯å®¡è®¡çš„ç…§é¡¾å…³ç³»ï¼›å…¶æƒé™ä¸Žéšç§èŒƒå›´å¿…é¡»æ˜Žç¡®å±•ç¤ºå¹¶å¯æ’¤é”€ã€‚

---

## ç›¸å…³ç¬”è®°

- [[Alert System]]
- [[Notification Flow]]
- [[Behavior Pings]]
- [[Known Issues]]


---

## 业务模块：Monitoring Direction

# Monitoring Direction

#business-logic #kc

---

## ä¸¤ä¸ªç‹¬ç«‹å¼€å…³

`group_members` è¡¨æœ‰ä¸¤ä¸ªå¸ƒå°”å­—æ®µï¼ŒæŽ§åˆ¶ç›‘æŽ§æ–¹å‘ï¼š

| å­—æ®µ | UI æ–‡æœ¬ | å«ä¹‰ |
|---|---|---|
| `monitored` | å¼€å¯æˆ‘çš„æ²‰é»˜æŠ¥è­¦ | **æˆ‘** æ˜¯å¦è¢«ç¾¤ç»„ç›‘æŽ§ï¼ˆæˆ‘æ²‰é»˜æ—¶ç¾¤ç»„ä¼šæ”¶åˆ°å‘Šè­¦ï¼‰|
| `watching` | æŽ¥æ”¶ä»–äººæŠ¥è­¦ | **æˆ‘** æ˜¯å¦æŽ¥æ”¶ç¾¤ç»„ä¸­ä»–äººçš„å‘Šè­¦ |

---

## å¸¸è§è¯¯åŒº

è¿™ä¸¤ä¸ªå¼€å…³**å®Œå…¨ç‹¬ç«‹**ï¼š

```
monitored=true,  watching=false â†’ æˆ‘è¢«ç›‘æŽ§ï¼Œä½†æˆ‘ä¸çœ‹åˆ«äººçš„å‘Šè­¦
monitored=false, watching=true  â†’ æˆ‘ä¸è¢«ç›‘æŽ§ï¼Œä½†æˆ‘ä¼šæ”¶åˆ°åˆ«äººçš„å‘Šè­¦
monitored=false, watching=false â†’ å®Œå…¨ä¸å‚ä¸Žäº’ç›¸ç›‘æŽ§
monitored=true,  watching=true  â†’ å®Œå…¨å‚ä¸Žï¼ˆé»˜è®¤ï¼‰
```

---

## è®¾è®¡æ„å›¾

- æœ‰äº›ç”¨æˆ·åªæƒ³"è¢«ç…§é¡¾"ï¼Œä¸æƒ³å¤„ç†ä»–äººçš„å‘Šè­¦é€šçŸ¥ â†’ `monitored=true, watching=false`
- æœ‰äº›ç”¨æˆ·æ˜¯ç®¡ç†å‘˜è§’è‰²ï¼Œæƒ³ç›‘æŽ§æ‰€æœ‰äººä½†ä¸æƒ³è¢«æ‰“æ‰° â†’ å¯çµæ´»é…ç½®
- ä¸æ˜¯"watched"/"watching others"è¿™ç§ç›¸äº’ç»‘å®šçš„æ¦‚å¿µï¼Œè€Œæ˜¯å®Œå…¨ç‹¬ç«‹çš„æƒé™

---

## RPC

ä¿®æ”¹è¿™ä¸¤ä¸ªå¼€å…³ä¸èƒ½ç›´æŽ¥é€šè¿‡ PostgREST Update æ›´æ–°ï¼ˆä¼šå›  RLS ç­–ç•¥æˆ– active çŠ¶æ€åˆ¤æ–­å¯¼è‡´é™é»˜å¤±è´¥ï¼Œå³è¿”å›ž 0 rows affected å´ä¸æŠ¥é”™ï¼‰ï¼Œè€Œå¿…é¡»é€šè¿‡ Security Definer RPC å®Œæˆï¼š
```sql
public.set_monitoring_direction(
  _group uuid,
  _monitored boolean default null,
  _watching boolean default null
)
```

**è®¾è®¡ä¸Žå®žçŽ°ç»†èŠ‚**ï¼š
- **å®‰å…¨æ€§**ï¼šä½¿ç”¨ `security definer` ç»•è¿‡ç›´æŽ¥æ›´æ–° `group_members` è¡¨çš„ RLS é™åˆ¶ã€‚
- **ç¡®ä¿¡æ“ä½œ**ï¼šé™åˆ¶æ›´æ–°è°ƒç”¨è€…æœ¬äººï¼ˆé€šè¿‡ `auth.uid()` åˆ¤å®šï¼‰åœ¨æŒ‡å®šç¾¤ç»„ä¸­ä¸” `status = 'active'` çš„æˆå‘˜è®°å½•ã€‚
- **é”™è¯¯æ•èŽ·**ï¼šè‹¥æ›´æ–°å½±å“è¡Œæ•°ä¸º 0ï¼ˆä¾‹å¦‚ï¼šéžç¾¤ç»„æˆå‘˜ã€ä¼šè¯è¿‡æœŸã€éž active æˆå‘˜ï¼‰ï¼Œä¼šæ˜Žç¡®æŠ›å‡º `group membership not found` å¼‚å¸¸ï¼Œå‰ç«¯å¯æ•èŽ·å¹¶æŠ¥é”™ï¼Œé¿å…é™é»˜å¤±è´¥ã€‚
- **å‚æ•°æ”¯æŒ**ï¼šè‹¥æŸå¼€å…³ä¼ å…¥ `null` / æœªæŒ‡å®šï¼Œåˆ™ä¿æŒåŽŸæ ·ï¼Œå…è®¸åªæ›´æ–°å•è¾¹å¼€å…³ã€‚åœ¨å‰ç«¯ï¼ˆå¦‚ `src/features/relationships/api.ts` çš„ `setMonitoringDirection()`ï¼‰è°ƒç”¨æ—¶ï¼Œéœ€ä¼ å…¥æ˜¾å¼çš„ `false` / `true`ã€‚

---

## ç›¸å…³ç¬”è®°
- [[Alert System]]
- [[Notification Flow]]

---

## å½“å‰ç»„å‘Šè­¦å±•ç¤ºä¸å˜é‡

[Codex Â· 2026-07-27 11:27 +06:00]

`group_members.monitored` æ˜¯æŒ‰ç»„ç”Ÿæ•ˆçš„ç›®æ ‡æˆå‘˜æŽˆæƒã€‚å³ä½¿åŒä¸€ç”¨æˆ·å› ä¸ºå¦ä¸€ä¸ª `monitored=true` çš„ç»„è€Œå­˜åœ¨å…¨å±€ open silence alertï¼Œ`get_group_activity_view` ä¸Žå…¼å®¹ RPC `get_group_activity` ä¹Ÿåªèƒ½åœ¨å½“å‰ç»„è¯¥æˆå‘˜ `monitored=true` æ—¶è¿”å›ž `alerted=true/status=alert`ã€‚å½“å‰ç»„ä¸º `monitored=false` æ—¶ï¼Œä¸å¾—å€Ÿç”±å…¨å±€ alert æŠŠå‘Šè­¦çŠ¶æ€æ³„æ¼åˆ°è¯¥ç»„ï¼›è¯¥ç»„çš„ watch lens ä¹Ÿä¸å¾—åŒ…å«è¯¥ç›®æ ‡ã€‚

æºç å€™é€‰ç”± append-only migration `20260727090000_scope_group_alerts_to_monitoring_direction.sql` ä¿®å¤ï¼›pgTAP `monitoring_direction_alert_scope.sql` åŒæ—¶è¦†ç›–ä¸¤ç»„ã€ä¸¤ä¸ª RPCã€watch lens å’Œé€šçŸ¥æ”¶ä»¶è¾¹ç•Œã€‚è¯¥ migration å·²äºŽ 2026-07-27 åº”ç”¨åˆ° productionï¼ˆledger `20260727090000`ï¼‰ã€‚ç”Ÿäº§åªè¯»åŒç»„ smoke ä½¿ç”¨çŽ°æœ‰åŽ»æ ‡è¯†åŒ–æ··åˆç›‘æŽ§ç›®æ ‡éªŒè¯ï¼šå…³é—­ç›‘æŽ§çš„ç»„ä¸­ `get_group_activity_view` ä¸Ž `get_group_activity` å‡è¿”å›ž `alerted=false`ï¼›åŒä¸€ç›®æ ‡åœ¨ä»å¼€å¯ç›‘æŽ§çš„å¦ä¸€ä¸ªç»„ä¸­ä¸¤è€…å‡ä¿æŒ `alerted=true`ã€‚


---

## 业务模块：Notification Flow

## ADR-0045 æ›´æ–°ï¼šé»˜è®¤æœ¬äººæ´»åŠ¨è§£é™¤ï¼ˆæœ¬åœ°å®žçŽ°ï¼Œå°šæœªä¸Šçº¿ï¼‰

[Codex Â· 2026-09-23 20:11 +06:00]

ç”¨æˆ·å·²æ˜Žç¡®æ›¿ä»£æ—§çš„â€œè¢«åŠ¨æ´»åŠ¨æ°¸ä¸è§£é™¤â€è§„åˆ™ã€‚é»˜è®¤ silence/dark_device/concern åœ¨æ£€æµ‹åˆ°å‘Šè­¦æ‰“å¼€ä¹‹åŽã€æ¥æºä¸Žè´¦æˆ·æ­£ç¡®ã€v2 ä¸”åŠæ—¶é€è¾¾çš„æœ¬äººæ´»åŠ¨æ—¶è‡ªåŠ¨è§£é™¤ï¼›å¿ƒè·³ã€æœªæ¥æ—¶é—´ã€åŽ†å²è¡¥ä¼ åŠä»–äººæ“ä½œä¸ç®—æœ¬äººæ´»åŠ¨ã€‚æŒ‡å®šçš„æœ‰æ•ˆå®ˆæŠ¤è€…å¯ä¸ºå…¶è¢«å®ˆæŠ¤è€…å¼€å¯ pattern è¦æ±‚ï¼Œé»˜è®¤å…³é—­ï¼›ä»»ä¸€æœ‰æ•ˆè¦æ±‚ç”Ÿæ•ˆï¼Œè§£é™¤å…³ç³»åŽä¸å†ç”Ÿæ•ˆã€‚æœåŠ¡å™¨æ ¡éªŒ patternï¼Œæ™®é€šæŒ‰é’®åŠæ—§ RPC ä¸å¾—ç»•è¿‡ã€‚æ™®é€šé€šçŸ¥ä½¿ç”¨â€œä¸€åˆ‡å®‰å¥½â€æŒ‰é’®ï¼Œç‚¹é€šçŸ¥æ­£æ–‡åªæ‰“å¼€ç•Œé¢ã€‚SOS ä¿ç•™æ˜Žç¡®æ‰‹åŠ¨ç¡®è®¤ï¼Œé»˜è®¤ä¹Ÿä¸è¦æ±‚ patternã€‚

æ–°è¿ç§»ï¼š`20260923054905_activity_auto_resolution_guardian_pattern.sql`ã€‚æ´»åŠ¨è§£é™¤ä¿ç•™åŽ†å²å¹¶é‡å¼€è¢«åŠ¨ç›‘æµ‹ epochï¼Œé¿å…æ—§æ¼ç­¾é“¾ç«‹å³é‡å¤å‘Šè­¦ï¼›æ’¤å›žæœªå‘é€çš„æ—§é€šçŸ¥ï¼Œæ¢å¤é€šçŸ¥åªå‘æœ¬äººåŠæ—¢æœ‰æ¶‰åŠè€…ã€‚Android ä¸å†å‡­æœ¬åœ°è§£é”æˆ– UsageStats æå‰æ˜¾ç¤ºå®‰å…¨æˆåŠŸã€‚

æœ¬åœ°éªŒè¯ï¼š105 æ–‡ä»¶ / 629 é¡¹ Vitest é€šè¿‡ï¼›typecheckã€ç½‘é¡µ build é€šè¿‡ï¼›æœ€åŽ SQL é”é¡ºåºå’Œ SOS ä¿®æ­£åŽ 22 é¡¹éš”ç¦» PostgreSQL å›žå½’å†æ¬¡é€šè¿‡ã€‚æ­¤å‰ Android Java ç¼–è¯‘é€šè¿‡ã€‚å°šæœªåšå®Œæ•´ Supabase è¿ç§»å›žæ”¾ã€çœŸæœºéªŒæ”¶æˆ–éƒ¨ç½²ã€‚æœ¬èŠ‚æ˜¯çŽ°è¡Œå·²æŽ¥å—æ–¹å‘ï¼›ä¸‹æ–‡ç›¸å†²çªçš„æ—§æ´»åŠ¨è§£é™¤è§„åˆ™ä»…ä»£è¡¨åŽ†å²å®žçŽ°ï¼Œä¸å¯ç”¨äºŽå¦å®š ADR-0045ã€‚

# Notification Flow

#business-logic #kc

---

## ADR-0039 çŽ°è¡Œé€šçŸ¥å¥‘çº¦

[Codex Â· 2026-08-09 17:24 +06:00]

- å¥åº·ä¸” coverage å¯éªŒè¯æ—¶å°½å¯èƒ½ä¿æŒå®‰é™ï¼›å½“è®¾å¤‡ã€Appã€æƒé™æˆ–åŽå°å®ˆæŠ¤å·²çŸ¥ä¸æ­£å¸¸æ—¶ï¼Œä¸€æ¬¡æ˜Žç¡®æç¤ºåŽæŒç»­æ˜¾ç¤º `Limited`ï¼Œç›´åˆ°æœåŠ¡ç«¯å¯éªŒè¯æ¢å¤ã€‚ä¸èƒ½ç”¨ä¸é€šçŸ¥æ¥ä¼ªè£…å®ˆæŠ¤æ­£å¸¸ã€‚
- `concern` åªèƒ½é™„ç€åˆ°çŽ°æœ‰ alert lifecycleï¼Œä¸èƒ½åˆ›å»º alertã€‚
- æ™®é€šç»„å‘˜åœ¨åå•é‡Œâ€œçŸ¥é“â€æˆå‘˜çŠ¶æ€ï¼›é¢å¤–é€šçŸ¥åªå‘é€ç»™ç”¨æˆ·ç§ä¸‹ã€é»˜è®¤å…³é—­åœ°å‹¾é€‰ä¸º `Special Attention` çš„æˆå‘˜ã€‚è¯¥é€‰æ‹©ä¸åº”å…¬å¼€æš´éœ²ç»™å…¶ä»–ç»„å‘˜ã€‚
- Guardian/Ward æ˜¯æœ€å…¨é¢çš„æŒç»­ç…§é¡¾é¢ï¼Œä½† Guardian çš„ç¡®è®¤å¿…é¡»æ˜¯ç‹¬ç«‹å¤–éƒ¨ confirmationï¼Œä¸å¾—å†™æˆ Ward çš„ activity æˆ–æœ¬äºº check-inã€‚
- è¢«åŠ¨ ping ä¸äº§ç”Ÿä»»ä½• resolved é€šçŸ¥ï¼›åªæœ‰æœ¬äººåˆ»æ„å“åº”ã€ç…§é¡¾è€…å¤–éƒ¨ç¡®è®¤æˆ– GM æ˜Žç¡®å…³é—­æ‰å¯äº§ç”Ÿç›¸åº”çš„ lifecycle é€šçŸ¥ã€‚

---

## é€šçŸ¥ç±»åž‹ï¼ˆ`kind`ï¼‰

| kind | æŽ¥æ”¶äºº | è§¦å‘æ—¶æœº |
|---|---|---|
| `self` | ç”¨æˆ·è‡ªå·± | alert è¿›å…¥ self é˜¶æ®µ;guardian ç¡®è®¤å®‰å…¨åŽçš„ nudge |
| `group` | ç¾¤ç»„ watching æˆå‘˜ + guardian | alert è¿›å…¥ group é˜¶æ®µ(SOS æ—¶ kind ä¸º `sos`) |
| `community` | ç¤¾åŒºæˆå‘˜ | alert è¿›å…¥ community é˜¶æ®µ |
| `terminal` | ç¾¤ç»„æˆå‘˜ + guardian | alert è¿›å…¥ terminal é˜¶æ®µ |
| `sos` | åŒä¸Šå„é˜¶æ®µæŽ¥æ”¶é¢ | cause=sos æ—¶æ›¿ä»£ group/community/terminal æ–‡æ¡ˆ |
| `on_it` | ç›®æ ‡ + å…¶ä»– watcher(**ä¸å«æ“ä½œè€…**) | æœ‰äººç‚¹ã€Œæˆ‘åŽ»è”ç³»ã€(`ack_alert`) |
| `resolved` | ç›®æ ‡ + å…¨ä½“ watcher | è®¤é¢†è€…ç‚¹ã€Œç¡®è®¤å®‰å…¨ã€(`resolve_alert`) |
| `auto_resolved` | åŽ†å²å®¢æˆ·ç«¯å…¼å®¹ | åŽ†å²å®žçŽ°æ›¾ç”± liveness/cron äº§ç”Ÿï¼›ADR-0039 ä¸‹ä¸å¾—ç”±è¢«åŠ¨ ping äº§ç”Ÿï¼Œæ–°æµç¨‹åº”è¿ç§»åˆ°æœ‰ provenance çš„æ˜Žç¡®è§£é™¤ç±»åž‹ |
| `concern` | ç›®æ ‡æœ¬äºº | ä»…åœ¨å·²æœ‰ alert ä¸Šè¡¨è¾¾å…³å¿ƒï¼›ä¸èƒ½åˆ›å»º alert |

---

## å†™å…¥æµç¨‹

```
process_escalations()
    â†’ notify_stage(alert_id)
        â†’ å†™å…¥ notifications è¡¨ï¼ˆå¤šæ¡ï¼Œæ¯ä¸ª recipient ä¸€æ¡ï¼‰
        â†’ trigger_push_dispatch()
            â†’ è°ƒç”¨ /push-dispatch Edge Function
                â†’ è¯»å–æœª pushed çš„ notifications
                â†’ å‘é€ Web Push
                â†’ æ›´æ–° notifications.pushed_at
```

---

## Notification click routing

When a push notification opens the PWA, the Service Worker carries the notification `kind` into the app. Only `self` and `concern` notifications may optimistically show the "Are you OK" self-check overlay before `getMyOpenAlert()` returns. `group`, `community`, `terminal`, `on_it`, `resolved`, and task notifications must only refresh/open the relevant app context; they must not force the current user through the self-check overlay unless that current user also has their own open alert.

---

## Guardian ç¡®è®¤åŽçš„é€šçŸ¥å¤„ç†

å½“è®¤é¢†è€…(`paused_by`)ç¡®è®¤ç”¨æˆ·å®‰å…¨(`resolve_alert`,2026-06-24 èµ·çŽ°è¡Œç‰ˆ):
1. âœ… **ä¿ç•™**è¯¥ alert çš„å…¨éƒ¨åŽ†å²é€šçŸ¥(ä¸å†æ¸…é™¤)
2. âž• ç»™ç›®æ ‡+å…¨ä½“ watcher è¡¥å‘ `resolved` é€šçŸ¥
3. âž• ç»™ç”¨æˆ·æœ¬äººå‘é€ `self` nudge
   > æé†’ç”¨æˆ·ï¼šè™½ç„¶å·²è¢«å¤–éƒ¨ç¡®è®¤å®‰å…¨ï¼Œä½†ä»éœ€è‡ªè¡Œæ‰“å¼€ App äº§ç”ŸçœŸå®žæ´»åŠ¨è®°å½•
4. âž• å†™å…¥ç‹¬ç«‹ caregiver confirmationï¼›ä¸å¾—å†™å…¥ Ward çš„ `manual_checkin`ã€ä¸å¾—åˆ·æ–°æœ¬äºº activityã€‚è‹¥éœ€æŠ‘åˆ¶ç«‹å³é‡æŠ¥ï¼Œä½¿ç”¨æœ‰ç•Œä¸”å¯å®¡è®¡çš„ caregiver-confirmed lifecycle çŠ¶æ€

---

## é‡è¦åŽŸåˆ™

[Codex Â· 2026-07-27 14:34 +06:00] Group-stage æ”¶ä»¶è¾¹ç•Œä¸Žå±•ç¤ºè¾¹ç•Œéƒ½å¿…é¡»æŒ‰â€œç›®æ ‡ç”¨æˆ·åœ¨è¯¥ exact group çš„ active membership ä¸” `monitored=true`â€åˆ¤æ–­ã€‚`private.notify_stage` åŽŸå·²ç¬¦åˆè¯¥è§„åˆ™ï¼›production migration `20260727090000` çŽ°å·²è¡¥é½ä¸¤ä¸ª group activity RPCï¼Œé˜²æ­¢å¦ä¸€ä¸ªç»„è§¦å‘çš„å…¨å±€ alert åœ¨ opt-out ç»„ä¸­æ˜¾ç¤ºã€‚ä¸Šçº¿å‰åŽ `private.notify_stage` å“ˆå¸Œå‡ä¸º `fe83bf7a14a954424026f3999c1b67e8`ã€‚

- `notifications` è¡¨æ˜¯**æŒä¹…è®°å½•**ï¼šåŽ†å²è§£é™¤é€šçŸ¥åº”ä¿ç•™ã€‚`auto_resolved` ä»…æ˜¯æ—§å®¢æˆ·ç«¯/æ—§æ•°æ®å…¼å®¹è¯­ä¹‰ï¼›ADR-0039 æ–°æµç¨‹ä¸å¾—è®©è¢«åŠ¨ activity è§£é™¤å‘Šè­¦ã€‚
  > 2026-07-20 å‰ auto-resolve æ›¾é™é»˜ `DELETE` è¯¥ alert å…¨éƒ¨é€šçŸ¥ä¸”ä¸è¡¥å‘(NOTIF-01,å·²ç”±è¿ç§»
  > `20260720150000_keep_notifications_on_auto_resolve` ä¿®å¤;è¯Šæ–­è§ Dev Log 2026-07-20)ã€‚
- ã€ŒClear allã€çš„ keep åˆ¤å®šåœ¨æœåŠ¡ç«¯ RPC `clear_finished_notifications()`:ä»…åˆ é™¤æœ¬äººã€Œæ—  alert æˆ– alert å·²éž openã€çš„é€šçŸ¥;å®¢æˆ·ç«¯ä¸å†è‡ªç®— keep åˆ—è¡¨(æ›¾æœ‰ items ç«žæ€ + limit 30 é™·é˜±)ã€‚
- å“åº”å¡ç‰‡(ã€Œæˆ‘åŽ»è”ç³»/ç¡®è®¤å®‰å…¨ã€)ç›®å‰ä»ç”±é€šçŸ¥è¡Œæ´¾ç”Ÿ:kindâˆˆgroup/community/terminal/sos ä¸” alert open(`auto_resolved`/`on_it` ä¸å‚ä¸Žæ´¾ç”Ÿ)ã€‚æ”¹ç”± open alerts æ´¾ç”Ÿæ˜¯åŽç»­å€™é€‰(NOTIF-01 æ–¹å‘ b,æœªåš)ã€‚
- `pushed_at = null` çš„è®°å½• = å¾…æŽ¨é€é˜Ÿåˆ—
- `read_at` ç”±å‰ç«¯åœ¨ç”¨æˆ·æŸ¥çœ‹é€šçŸ¥æ—¶æ›´æ–°
- **`read_at` æ˜¯å±•ç¤ºè¿‡æ»¤å™¨,ä¸æ˜¯æŠ•é€’é—¸é—¨ã€‚** `notify-feed` åŒæ—¶æŒ‰ `read_at is null` ä¸Ž
  `created_at > cursor` å–è¡Œ;çœŸæ­£é˜²æ­¢ã€ŒåŒä¸€è¡Œè¢«é‡å¤æŠ•é€’ã€çš„åªæœ‰ cursorã€‚cursor ä¸€æ—¦ä¸å‰è¿›,
  æœªè¯»è¡Œå°±ä¼šåœ¨æ¯æ¬¡å”¤é†’æ—¶è¢«é‡æŠ•,ç›´åˆ°ç”¨æˆ·æ‰“å¼€ App æŠŠ `read_at` å†™ä¸Šä¸ºæ­¢â€”â€”ç”¨æˆ·ä¾§çš„è¡¨è±¡å³
  ã€Œä¸è¿› App å°±ä¸€ç›´è‡ªå·±è·³ã€ã€‚
  > 2026-08-07 `KC-NOTIFY-CURSOR-PRECISION-001`:`notifications.created_at` æ˜¯å¾®ç§’ç²¾åº¦çš„
  > timestamptz,è€Œ notify-feed æŠŠå®¢æˆ·ç«¯ cursor ç» `new Date(Date.parse(since)).toISOString()`
  > è½¬äº†ä¸€æ‰‹,æˆªæ–­åˆ°æ¯«ç§’(ä¸¢æœ€å¤š 999Âµs)ã€‚æˆªæ–­å€¼å½“ä½œ `.gt()` ä¸‹ç•Œ,äºŽæ˜¯**æœ€æ–°ä¸€è¡Œæ¯”å®ƒè‡ªå·±æ›´æ–°**,
  > æ¯æ¬¡è½®è¯¢éƒ½è¢«è¿”å›ž;å®¢æˆ·ç«¯ `createdAt > latest` çœ‹åˆ°åŒä¸€å­—ç¬¦ä¸²åˆä¸æŽ¨è¿› cursor,å¾ªçŽ¯æ°¸ä¹…æˆç«‹ã€‚
  > ä¿®æ³•:cursor åŽŸæ ·äº¤ç»™ Postgres,`Date.parse` åªç•™ä½œæ ¡éªŒä¸Ž 7 å¤©å›žçœ‹å¤¹å–ã€‚
  > ä¸‰ç«¯å…±ç”¨æ­¤ç«¯ç‚¹,æ•…åŒä¸€ bug ä¸‰ç«¯éƒ½ä¸­;iOS ç—‡çŠ¶æœ€é‡â€”â€”NotifyFeed æœ¬ç‰ˆæ‰é¦–æ¬¡è®© iOS å…·å¤‡
  > æ˜¾ç¤ºé€šçŸ¥çš„èƒ½åŠ›,ä¸”å®ƒåœ¨**æ¯æ¬¡é™é»˜æŽ¨é€**éƒ½è·‘(éž Android çš„ 15 åˆ†é’Ÿè½®è¯¢),
  > `UNNotificationRequest` æ¯æ¬¡é‡æŠ•éƒ½é‡æ–°å“é“ƒã€‚Android ç”¨ `tag = notification id` è®©é‡æŠ•
  > **è¦†ç›–**è€Œéžå †å ,è¯¥ workaround çš„æ³¨é‡ŠæŠŠã€Œé‡æŠ•æœªè¯»è¡Œã€å½“æˆé¢„æœŸè¡Œä¸º,æŽ©ç›–äº†æ ¹å› ã€‚
  > iOS ä¾§å¦åŠ å·²æŠ•é€’ id å°è´¦(ä¸Šé™ 100,ç™»å‡ºéš cursor ä¸€èµ·æ¸…),cursor å†å‡ºé”™ä¹Ÿä¸ä¼šé‡å¤å“é“ƒã€‚
- æ—§å®¢æˆ·ç«¯å¯¹æœªçŸ¥ kind(å¦‚ `auto_resolved`)åœ¨ App å†…ä¸Ž sw.js ä¸­å‡å›žé€€æ˜¾ç¤ºæœåŠ¡ç«¯ body åŽŸæ–‡

---

## ç›¸å…³ç¬”è®°
- [[Alert System]]
- [[Guardian Confirm]]

## ç‰¹åˆ«å…³æ³¨ï¼ˆSpecial Attentionï¼‰â€” ADR-0039

[Claude Â· 2026-08-09 22:01 +06:00] å·²å®žçŽ°æ•°æ®å¥‘çº¦ï¼Œè§ `20260809230000_s3_special_attention.sql`ã€‚

- **ç§å¯†**ï¼š`public.special_attention_subscriptions` å¼€å¯ RLS ä¸”**æ— ä»»ä½• policyã€æ— ä»»ä½• grant**â€”â€”æ²¡æœ‰ Data API è·¯å¾„ã€‚è¢«å…³æ³¨è€…æ°¸è¿œä¸çŸ¥é“è°åœ¨å…³æ³¨ä»–ï¼›ä»»ä½•å®¢æˆ·ç«¯è§’è‰²éƒ½ä¸èƒ½æ‰§è¡Œ `special_attention_recipients`ã€‚
- **é»˜è®¤å…³é—­**ï¼šæ²¡æœ‰è¡Œå°±æ˜¯å…³ã€‚è¿ç§»ä¸æ’­ç§ã€‚
- **æ— æƒé™**ï¼šåªæ˜¯é€šçŸ¥åå¥½ï¼Œä¸è¯»å†™ alerts / emergency_info / checkin_tasks / guardianshipsã€‚
- **èµ„æ ¼éšå…³ç³»ã€åå¥½ä¸éš**ï¼šæˆå‘˜çŠ¶æ€ç¦»å¼€ `active` ç«‹å³åœæ­¢é€šçŸ¥ï¼Œä½†æœ¬äººçš„è®¢é˜…è¡Œä¿ç•™ï¼›å…³ç³»æ¢å¤åˆ™é€šçŸ¥èµ„æ ¼è‡ªåŠ¨æ¢å¤ã€‚
- **å¼€å¯éœ€ active å…³ç³»ï¼Œå…³é—­æ°¸ä¸éœ€è¦**â€”â€”é€€å‡ºçš„æƒåˆ©ä¸èƒ½è¢«å…³ç³»çŠ¶æ€å¡ä½ã€‚
- APIï¼š`set_special_attention(_subject uuid, _enabled boolean)`ã€`my_special_attention()`ï¼ˆä»…è‡ªå·±ï¼‰ã€`special_attention_recipients(_subject uuid)`ï¼ˆä»…æœåŠ¡ç«¯ï¼‰ã€‚

**å°šæœªå®žçŽ°**ï¼šé€šçŸ¥çš„å®žé™…å‘å‡ºã€‚ADR-0039 è¦æ±‚ã€Œæœ¬äººå·²æ”¶åˆ°æç¤º + é¢å¤–å¥åº·å®½é™åŽã€æ‰å‘è®¢é˜…è€…å‘ä¸€æ¬¡ã€Œè®¾å¤‡/App è¦†ç›–ä¸­æ–­ï¼Œä¸ä»£è¡¨é‡é™©ã€ã€‚è¿™ä¾èµ–å®ˆæŠ¤å¥åº·åˆ¤å®šï¼Œå±žäºŽ S3-Cã€‚æ–‡æ¡ˆ key å·²å°±ä½ï¼š`special.notice` / `special.hint` / `special.needsActive`ã€‚


---

## 业务模块：Sleep Window

# Sleep Window

#business-logic #kc

---

## æ¦‚å¿µ

ç”¨æˆ·å¯ä»¥è®¾å®šä¸€ä¸ª"ç¡çœ æ—¶é—´æ®µ"ï¼Œåœ¨æ­¤æœŸé—´ç³»ç»Ÿ**ä¸å‘é€å‘Šè­¦**ï¼ˆalert ä¼šè¢« pauseï¼‰ã€‚

**å¢™é’ŸçœŸç›¸ï¼ˆADR-0016ï¼Œ2026-07-16 è½åœ°ï¼‰**ï¼šç”¨æˆ·è¾“å…¥çš„æ•°å­—ï¼ˆå¦‚ `23:00â€“07:00`ï¼‰åœ¨ä»»ä½•æ—¶åŒºå˜åŒ–åŽä¿æŒä¸å˜ï¼›`timezone` åªæ˜¯è§£é‡Š"çŽ°åœ¨å‡ ç‚¹"çš„å…ƒæ•°æ®ã€‚

---

## å­˜å‚¨æ–¹å¼

`user_settings` è¡¨ï¼š
- `sleep_start_local` / `sleep_end_local` â€” ç¡çœ èµ·æ­¢ï¼ˆ**æœ¬åœ°æ—¶é’Ÿæ•°å­—**ï¼Œå¦‚ `23:00`ï¼‰ï¼Œ`set_sleep_window` ç›´æŽ¥åŽŸæ ·å­˜å‚¨
- `timezone` â€” ç”¨æˆ·å½“å‰æ—¶åŒºï¼ˆIANAï¼Œå¦‚ `Asia/Thimphu`ï¼‰ï¼Œæ–°å‰ç«¯æ¯æ¬¡ä¿å­˜ç¡çœ çª—æ—¶éš `_tz` å‚æ•°æ›´æ–°
- `sleep_start_utc` / `sleep_end_utc` â€” **å·²å†»ç»“çš„æ—§åˆ—**ï¼ˆæ›¾å­˜ UTC time-of-dayï¼‰ï¼Œä»…ç•™ä½œå›žæ»šå‚ç…§ï¼Œä»»ä½•æ–°é€»è¾‘ä¸å¾—å†è¯»å†™

> åŽ†å²ï¼š2026-07-16 ä¹‹å‰æ—§å‰ç«¯æŠŠæœ¬åœ°æ•°å­—æŒ‰è®¾å¤‡æ—¶åŒºæ¢ç®—æˆ UTC å­˜è¿› `_utc` åˆ—ï¼Œæ¢æ—¶åŒºåŽçª—å£æ¼‚ç§»ï¼ˆADR-0016 çš„ bugï¼‰ã€‚è¿ç§» `20260716120000` å·²æŒ‰æ¯è¡Œçš„ `timezone` æŠŠ UTC æ•°å­—æ¢ç®—å›žæœ¬åœ°æ•°å­—å›žå¡«è¿› `_local` åˆ—ï¼ˆå½“æ—¥è¡Œä¸ºä¸å˜ï¼‰ã€‚æœ¬ç¬”è®°æ­¤å‰å£°ç§°"_utc åˆ—å®žä¸ºæœ¬åœ°æ•°å­—"æ˜¯**é”™çš„**ï¼Œå‹¿å†å¼•ç”¨æ—§ç‰ˆæœ¬ã€‚

---

## ä¸‰ä¸ªè¯»è·¯å¾„ï¼Œå…¨éƒ¨æœ¬åœ°æ¨¡åž‹

1. **`private.sleep_relaxed(_user, _at)`** â€” å®šæ—¶æŠ¥å¹³å®‰/å‡çº§çš„"ç¡çœ æœŸä¸æ‰“æ‰°"é—¸é—¨ã€‚æŠŠ `_at` è½¬ä¸ºç”¨æˆ·æœ¬åœ°æ—¶åˆ»ï¼Œä¸Žæœ¬åœ°æ•°å­—æ¯”è¾ƒï¼›å«è·¨åˆå¤œä¸Ž**é†’åŽ 2 å°æ—¶å®½é™**ã€‚ï¼ˆF4 ä¹‹å‰å®ƒæ•´ä¸ªå¿½ç•¥æ—¶åŒºã€æ‹¿ UTC æ•°å­—ç¡¬æ¯”â€”â€”æ ¸å¿ƒ bugï¼Œå·²ä¿®ã€‚ï¼‰
2. **`private.is_in_sleep_window(_user_id, _now)`** â€” alert æš‚åœåˆ¤æ–­ã€‚åŒä¸€æœ¬åœ°æ¨¡åž‹ + **åŠ¨æ€å»¶é•¿**ï¼šç¡å‰ 1 å°æ—¶å†…æœ‰æ´»åŠ¨ â†’ `dynamic_end = min(last_active + çª—å£æ—¶é•¿, åŽŸç»“æŸ + 3h)`ã€‚
3. **`public.my_routine_status()`** â€” UI å±•ç¤ºã€‚ç›´æŽ¥è¿”å›ž `_local` æ•°å­—ï¼ˆæ— éœ€æ¢ç®—ï¼‰ã€‚

---

## å†™è·¯å¾„ä¸Žæ—§å®¢æˆ·ç«¯åž«ç‰‡

`public.set_sleep_window(_start, _end, _tz)`ï¼š
- æ–°å®¢æˆ·ç«¯ï¼šæœ¬åœ°æ•°å­—ç›´å­˜ + `_tz`ï¼ˆè®¾å¤‡ IANA æ—¶åŒºï¼Œå…œåº• `'UTC'`ï¼‰æ›´æ–° `timezone`ã€‚**æ–°å®¢æˆ·ç«¯å¿…é¡»æ€»æ˜¯å¸¦ `_tz`**ï¼Œç¼ºçœä¼šè¢«å½“æ—§å®¢æˆ·ç«¯å¤„ç†ã€‚
- **è¿‡æ¸¡åž«ç‰‡**ï¼šæ—§ç‰ˆ Appï¼ˆå°¤å…¶æœªæ›´æ–°çš„ APKï¼‰ä¸å¸¦ `_tz` ä¸”ä»å‘"æ¢ç®—æˆ UTC çš„æ•°å­—"â†’ æœåŠ¡ç«¯è¯†åˆ«åŽè‡ªåŠ¨æŒ‰å­˜å‚¨æ—¶åŒºæ¢ç®—å›žæœ¬åœ°æ•°å­—å†å­˜ï¼Œæ—§ç‰ˆä¿®æ”¹è®¾ç½®ä¹Ÿä¸ä¼šå¼„é”™çª—å£ã€‚**å¾…æ—§å®¢æˆ·ç«¯æ·˜æ±°åŽç”±å•ç‹¬ ADR æ‹†é™¤ã€‚**
- æ¸…é™¤çª—å£ï¼šå…¨å‚æ•°ç¼ºçœï¼ˆå­˜ nullï¼‰ã€‚

---

## æ—¶åŒºè‡ªåŠ¨è·Ÿéšï¼ˆçŽ°åœ¨å¯¹æ‰€æœ‰è·¯å¾„æˆç«‹ï¼‰

```
è®¾å¤‡æ¢æ—¶åŒº â†’ å‰ç«¯ä¿å­˜ç¡çœ çª—æ—¶å¸¦æ–° _tz â†’ timezone æ›´æ–°
â†’ sleep_relaxed / is_in_sleep_window / my_routine_status å…¨éƒ¨æŒ‰æ–°æ—¶åŒºè§£é‡Š"çŽ°åœ¨"
â†’ "23:00 ç¡è§‰"åœ¨ä»»ä½•åœ°æ–¹éƒ½è¿˜æ˜¯å½“åœ°æ—¶é—´ 23:00,æ•°å­—æ°¸ä¸æ¼‚ç§»
```

---

## UI æ˜¾ç¤ºçº¦æŸ

å®¢æˆ·ç«¯æŠŠå†…ç½®ç¡çœ  quiet-window reason è®°ä¸ºå†…éƒ¨ key `sleep`ï¼Œä¸è¦ç¡¬ç¼–ç æˆæŸä¸€ç§è¯­è¨€çš„æ˜¾ç¤ºè¯ã€‚

æ˜¾ç¤ºæ—¶å¿…é¡»æŒ‰å½“å‰ UI è¯­è¨€æœ¬åœ°åŒ–ï¼š
- English: `Sleep`
- ä¸­æ–‡: `ç¡çœ `

ç”¨æˆ·è‡ªå®šä¹‰ quiet-window label åˆ™åŽŸæ ·ä¿ç•™ã€‚

---

## ADR-0023 dynamic compensation candidateï¼ˆshadow-onlyï¼‰

Configured `sleep_start_local / sleep_end_local` æ˜¯æ¯æ™š anchorï¼Œä¸æ˜¯ç²¾ç¡®è§‚æµ‹äº‹å®žï¼š

- å½“æ™šåˆæ ¼æœ¬äººæ´»åŠ¨å¯ä»¥æŠŠ candidate sleep start å»¶åŽï¼›
- æ¸…æ™¨åˆæ ¼æœ¬äººæ´»åŠ¨å¯ä»¥æŠŠ candidate wake æå‰ï¼›
- wake å»¶åŽåªèƒ½ä¾æ®å¤šæ™š coverage-valid çš„æ­£å‘æ™šæ´»åŠ¨ clusterï¼Œprospectiveã€æ¸è¿›ã€æœ‰ç¡¬ä¸Šé™ï¼›
- å½“å¤©æŒç»­ç¼ºå¸­ã€è®¾å¤‡ outageã€missing evidenceã€Guardian confirmation æ°¸è¿œä¸èƒ½å»¶é•¿ start/end æˆ–åœæ­¢ effective-silenceï¼›
- æ—¶åŒºæ˜¾è‘—å˜åŒ–ã€æ¨¡å¼åˆ‡æ¢ã€schedule drift æˆ– quality failure æ—¶å›žåˆ° configured anchorã€‚

Replay/shadow å¿…é¡»åŒæ—¶ä¿å­˜ configured anchorã€candidate compensationã€positive-evidence basisã€confidenceã€cap/drift reasonã€‚å½“å‰ `is_in_sleep_window`ã€`sleep_relaxed` ä¸Ž live pause è¡Œä¸ºä¸å›  ADR-0023 è‡ªåŠ¨æ”¹å˜ï¼›live compensation éœ€åŽç»­ promotion ADR æ˜Žç¡®æœ€å¤§ start/end movement ä¸Ž update rateã€‚

[Codex Â· 2026-07-27 08:34 +06:00] Local candidate function å·²å®žçŽ°å¹¶éªŒè¯ï¼šåªæœ‰ persisted as-of context ä¸Žåˆæ ¼æœ¬äººæ­£å‘æ´»åŠ¨å¯ä»¥åœ¨ config cap/update-rate å†…å¾®è°ƒï¼›missing/malformed/stale contextã€æ— è¦†ç›–ã€outageã€æŒç»­ç¼ºå¸­æˆ– Guardian confirmation å‡ fail closed åˆ° configured anchor / no extensionã€‚å®ƒå°šæ—  producerã€scheduler æˆ– live pause authorityã€‚

---

## ç›¸å…³ç¬”è®°
- [[Alert System]]
- [[Database Schema]]
- [[Decisions]]ï¼ˆADR-0016ï¼‰

## Live silence enforcement correction

[Codex Â· 2026-07-30 00:50 +06:00]

`process_escalations` now uses `private.sleep_relaxed` for both silence-alert creation and automatic resolution. Therefore the configured local sleep window and the existing two-hour post-wake grace are effective in the real live alert path, not only in check-in helpers.

`device_state.status='alert'` can no longer create a silence alert outside the canonical silence calculation or bypass sleep/grace. The separate 18-hour `dark_device` safety condition remains active. Accounts without `sleep_start_local/sleep_end_local` still have no sleep gate and must configure a window to receive this protection.


---

## 业务模块：Usual Behavior Model

# Usual Behavior Model

#business-logic #kc #core

> Keep Contact çš„æ ¸å¿ƒåˆ¤æ–­ç›®æ ‡ä¸æ˜¯â€œè¶…è¿‡å›ºå®šå‡ å°æ—¶å°±æŠ¥è­¦â€ï¼Œè€Œæ˜¯ç”¨é•¿æœŸã€è·¨è®¾å¤‡ã€éšç§å…‹åˆ¶çš„è¡Œä¸ºä¿¡å·ï¼Œç†è§£æŸä¸ªç”¨æˆ·ä¸Žéšèº«è®¾å¤‡ä¹‹é—´çš„ usual relationshipï¼Œå†åˆ¤æ–­å½“å‰æ²‰é»˜æ˜¯å¦ unusual enough to alertã€‚

---

## North Star

Keep Contact åº”å°½å¯èƒ½åœ¨ç”¨æˆ·æ— éœ€ä¸»åŠ¨æ“ä½œçš„æƒ…å†µä¸‹ï¼Œé€šè¿‡ 7/24 passive pings ç†è§£ï¼š

- ç”¨æˆ·é€šå¸¸åœ¨ä»€ä¹ˆæ—¶é—´æ®µä½¿ç”¨å“ªäº›è®¾å¤‡ã€‚
- ç”¨æˆ·è·¨æ‰‹æœºã€æ¡Œé¢ã€PWAã€APK ç­‰æ¸ é“çš„ç»¼åˆæ´»åŠ¨èŠ‚å¥ã€‚
- æŸä¸ªæ—¶æ®µè‡ªç„¶æ²‰é»˜å¤šä¹…æ˜¯ usualï¼Œå¤šä¹…å¼€å§‹å˜å¾— unusualã€‚
- å½“å‰åˆ¤æ–­çš„ confidence æœ‰å¤šé«˜ï¼Œæ˜¯å¦åº”å…ˆè‡ªæˆ‘æé†’ã€å»¶è¿Ÿã€è¿˜æ˜¯å‡çº§ç»™ watcherã€‚

`unusual_silence` ä¸åº”åªæ˜¯ `now() - last_behavior_at > X hours`ã€‚æœ€ç»ˆåº”æ˜¯ï¼š

```text
current silence + local context + device rhythm + historical distribution + confidence
  -> unusualness score
  -> alert threshold / delay / stage decision
```

---

## Privacy Boundary

åŽŸåˆ™ï¼šåªæ”¶é›† safety inference æ‰€éœ€çš„æœ€å° metadataã€‚

Allowed signal shape:
- timestamp
- ping kind
- client/device/channel id
- platform/channel
- app version
- timezone / local-hour context

Not part of the default model:
- message/content
- browsing/app content
- precise location
- contacts/social graph beyond KC relationships

Retention design is not yet finalized and needs ADR before schema/runtime changes. Preferred direction to evaluate:
- short/mid-term raw ping metadata for model learning and debugging
- long-term privacy-preserving aggregates for 3-12 month usual pattern memory
- optional explicit consent for longer raw metadata retention if stronger personal safety modeling is desired

---

## Target Architecture

### 1. Evidence Layer

Collect and normalize behavior signals across devices. It should know not only the latest ping, but where signals came from.

Examples:
- phone unlock / charger / app open
- PWA focus / interaction / heartbeat
- desktop app heartbeat
- manual check-in
- guardian-confirmed safe event, clearly marked as external evidence rather than user's own device activity

Evidence layer should protect against historical sync spikes, duplicate uploads, device clock drift, and low-quality signal bursts.

### 2. Usual Model Layer

Convert long-term evidence into a personal model. This layer should produce structured facts, not only a 24-number threshold array.

Model outputs should include:
- active windows by local day type and hour
- quiet windows and sleep-like windows
- device rhythm: which device/channel is usually active at which time
- gap distributions: p50 / p75 / p90 / p95 / p99 by context
- day clusters: weekday, weekend, irregular, travel/shift-like, holiday-like
- recent drift: whether routine changed in the last days/weeks
- confidence: sample count, stability, device coverage, recency
- explanation: why the model considers a silence usual or unusual

AI's role is to summarize and explain this model, detect patterns/edge cases, and propose structured profile updates. AI should not be the only source of truth and should not return only a naked threshold.

### 3. Runtime Risk Layer

`process_escalations` should eventually evaluate an unusualness score:

- current silence duration since user's own latest behavior ping
- local time, day type, timezone, sleep window
- expected device coverage for this context
- historical percentile of this silence length in similar contexts
- confidence and data quality
- current alert history and cooldown

The runtime output can still become a threshold for UX, but the threshold is only an explanation of the model decision, not the model itself.

---

## Current Implementation Status

Production since 2026-07-19 runs ADR-0021 Gate 1 containment. The former learned-profile v1 remains stored as an intermediate/audit layer, but it is not live safety authority:

- `behavior_pings` is the activity truth.
- `daily_activity_aggregates` stores hourly density.
- `user_activity_profiles.hourly_thresholds` stores one neutral baseline threshold per hour.
- `user_activity_profiles.model_version`, `model_confidence`, `hourly_confidence`, `gap_stats`, and `model_explanation` store v1 model metadata.
- `private.silence_threshold()` is frozen to a deterministic Gate 1 fallback and does not read the learned profile.
- `update-routine-profile` may retain aggregate profile metadata for shadow/audit work, but its weekly cron is unscheduled and its output has no live safety authority.
- Frontend pure helper `usualModel.ts` can build a deterministic local model for tests/offline logic.
- ADR-0029 P1 local candidate adds an owner-only normalized training source for retained `ingest_version=1` history. It sessionizes by the model's configured gap, binds each session to a deterministic source-row hash, and admits completed gaps only when the replay/shadow version explicitly opts in. Historical v1 is global-profile training evidence only: it supplies no live activity, no check-in completion, no alert resolution, no comparable local context, and no current coverage/sleep inference.

Sensitivity is no longer part of the learned model. ADR-0022 production uses one deterministic neutral base of 1.5h:
- `high` / sensitive: +0 minutes = 1.5h.
- `balanced`: +45 minutes = 2.25h.
- `low` / relaxed: +90 minutes = 3h.

Do not multiply sensitivity on top of the model again. Heavy multiplier stacking (`model * weekend * sensitivity`) makes active users look safer for too long and hides real unusual silence.

This v1 fixes threshold semantics and creates model metadata, but it is still shallow compared with the North Star. It does not yet fully model:

- device-specific rhythm
- day clusters beyond simple weekend multiplier
- long-term aggregate memory beyond current tables
- explicit unusualness score
- user-facing explanation of why a specific live silence is unusual

### ADR-0021 Gate 1 containment (production since 2026-07-19)

[Codex Â· 2026-07-19 14:45]

- Historical/synthetic/v1 evidence remains retained but cannot drive live safety. Only validator-created v2 evidence with server receipt/drift/causality checks is canonical for current status, escalation and check-in completion.
- `update-routine-profile` checks each user's `consent_data_sharing` before any Gemini call; it receives aggregate metadata, does not seed random history, and fails visibly when DB writes fail.
- The weekly AI profile cron is unscheduled. Existing learned profiles remain stored for audit. ADR-0022 production uses neutral 1.5h + 0/45/90m (1.5h / 2.25h / 3h) without restoring any profile authority.
- Daily aggregates count canonical v2 evidence only. A later Gate 2/3 must rebuild safe quiet-period/shadow evidence; AI remains advisory and cannot promote itself.
- The product still lacks temporary travel/shift exceptions, evidence correction UI, model rollback, and user-facing per-decision explanation. Gate 1 is containment, not completion of the North Star.

### ADR-0023 accepted replay/shadow architecture (2026-07-25)

[Codex Â· 2026-07-25 21:50]

- Canonical Routine modes are `regular_9to5`, `semester_break`, and `shift_irregular`; legacy `student`, `shift_worker`, and `flexible` values normalize to the nearest canonical mode.
- The normal cold-start prior is learned from consenting, evidence-qualified users in the same Routine mode. It aggregates per-user neutral p95 values robustly; raw heartbeat/event pooling is forbidden.
- Candidate fallback: comparable-context personal p95 â†’ personal-global p95 â†’ Routine-mode cohort prior â†’ deterministic emergency failsafe.
- Personal/context confidence controls fall-through. Low confidence does not invent an earlier/later threshold.
- Configured sleep is a prior. Positive own activity may support bounded compensation; absence/outage/Guardian never extends it.
- Historical replay and live shadow use one deterministic/versioned evaluator. Shadow records would-have-decided output and has no live alert/notification authority.
- `update-routine-profile` v1, hard-coded mode arrays, old `gap<=12h` raw ping statistics, synthetic aggregate history, and external AI output are not this architecture and cannot be reactivated as a shortcut.
- A future unusualness/risk scorer may implement the same candidate interface but remains shadow-only until it independently beats the p95 architecture on accepted safety metrics.

[Codex Â· 2026-07-27 08:34 +06:00] Implementation checkpoint: the three-mode taxonomy, privacy-qualified personal/context/global p95 profiles, one-user-one-value same-mode cohort prior, bounded positive-evidence sleep candidate, deterministic evaluator, aggregate replay, and unscheduled shadow recorder are present locally through `e8b5d92`. Full local verification and cross-provider audit passed. This is candidate/replay infrastructure only: insufficient users fall through the stated hierarchy, and no learned value has live alert authority.

---

## Design Rules For Future Agents

1. Do not reduce KC safety logic to a fixed global timeout.
2. Do not treat `user_activity_profiles.hourly_thresholds` as the final model. It is a transitional output.
3. Preserve privacy by default: collect metadata, not content.
4. Separate user's own device behavior from external guardian confirmation.
5. Keep confidence visible in backend decisions. Low-confidence users should get conservative staged behavior, not false certainty.
6. Any new long-term raw retention, schema expansion, or alert runtime rewrite requires an ADR before implementation.

---

## Related Notes
- [[Alert System]]
- [[Behavior Pings]]
- [[Sleep Window]]
- [[System Overview]]
- [[Database Schema]]


## ADR-0028 production-shadow usual-behavior model

[Codex Â· 2026-07-29 08:08 +06:00]

Routine modes are canonicalized and candidate evaluation uses versioned gap profiles, sleep candidates, cohort priors, replayable as-of contexts, and explicit intervention provenance. Candidate outputs stay shadow-only until a separately authorized promotion task.

Operational eligibility is the exact intersection of a device-state subject and at least one active monitored direction. Guardian/manual/Shortcut activity never becomes passive evidence, and browser/PWA cannot claim continuous native coverage.

[Codex Â· 2026-07-29 09:21 +06:00] This shadow model foundation is production-deployed in `v0.5.21` but not activated. No learned or candidate threshold has been promoted into live alert authority.

[Codex Â· 2026-07-29 23:04 +06:00] v0.5.22 deploys sessionized v1 training evidence and the corrected Routine progress UI, but does not promote learned thresholds. Shadow coverage accepts truthful Android (`android-passive-v1`) and Tauri (`tauri-idle-v1`) leases; adaptive Cron remains zero and promotion still requires a separate accepted gate.

[Codex Â· 2026-07-30 00:10 +06:00] ADR-0029 Phase 2 is active in production under model `kc-shadow-prod-v2-history-seeded`. Initial personal profiles are rebuilt from retained, sessionized `ingest_version=1` history; qualified canonical-v2 sessions then extend the same versioned rolling profile during daily maintenance. The fixed ADR-0022 sensitivity template is not used as the profile seed. It remains only the unchanged live safety authority until a separately accepted promotion.

Production evidence for the most complete profile is `personal_global` neutral p95 295 minutes from 154 gaps across 20 support dates, confidence 1.0. With that account's current low-sensitivity +90 minute buffer, the expected shadow candidate is 385 minutes, not 90/135/180 minutes. This is profile evidence, not yet a live decision.

The five-minute shadow cycle and daily maintenance job are enabled. Subject-context provenance now uses the evaluator's complete-row hash contract; 7/7 production contexts pass that gate. The current operational population still stops at `missing_qualified_session` because no finalized coverage interval exists yet for these subjects. Existing history is intentionally sufficient for training but cannot be fabricated into current continuous-coverage proof. Android/Tauri v0.5.22 coverage leases must form qualified canonical sessions before persisted shadow decisions begin.

### ADR-0032 live continuity

[Codex Â· 2026-07-30 00:50 +06:00]

Valid retained `personal_global` history is now live authority as a one-way extension over the fixed sensitivity floor. Users do not restart learning and do not wait for a new 14/35-day window. New canonical-v2 session gaps after the profile's `latest_evidence_at` extend the retained p95 without claiming continuous coverage; when daily maintenance advances the profile evidence boundary, the rebuilt profile replaces that temporary extension.

Fallback remains deterministic only when the selected profile is missing, stale, low-support, provenance-mismatched, or otherwise invalid. Sensitivity stays additive (`+0/+45/+90m`) and the 600-minute ceiling remains enforced.

### ADR-0035 è´¦æˆ·çº§ç”»åƒï¼ˆç¬¬ä¸€æ­¥ï¼Œå·²ä¸Šç”Ÿäº§ä½†æœªæŽ¥çº¿ï¼‰

[Claude Â· 2026-08-02 20:15 +01:00] `KC-ADR35-ACCOUNT-PROFILE-001`

å­¦ä¹ æ ¹åŸºæ”¹å»ºä¸ºè´¦æˆ·çº§ã€‚æ–°å¢ž `public.account_gap_profiles` ä¸Ž `private.rebuild_account_gap_profiles(...)`ï¼šæŒ‰ `user_id` æ±‡æ€»å…¨éƒ¨è®¾å¤‡çš„å‘Šæ´»è®°å½• â†’ æ‰£é™¤é…ç½®ç¡çœ çª— â†’ å– p95 â†’ æŒ‰ `n/(n+k)` å‘ preset ç¾¤ä½“æ”¶ç¼©ã€‚**æ— è¦†ç›–ç§Ÿçº¦ã€æ— è§‚æµ‹è¯æ˜Žã€æ— ä»»ä½•ä¸Šé™é’³åˆ¶**ã€‚

ä¸‰æ¡å®žçŽ°çº¦æŸï¼Œæ”¹åŠ¨å‰å¿…é¡»å…ˆç†è§£ï¼š

1. **å­¦ä¹ æµå¿…é¡»ç­‰äºŽæ£€æµ‹æµã€‚** æ²¿ç”¨å®žæ—¶åˆ¤å®šåŒä¸€å¥—å®šä¹‰ï¼š`ingest_version = 2`ã€`|received_at - at| <= 300s`ã€ä»¥ `received_at` è®¡æ—¶ã€‚è‹¥å­¦ä¹ æ”¶å¾—æ¯”æ£€æµ‹å®½ï¼Œå­¦åˆ°çš„é—´éš”æ’çŸ­äºŽæ£€æµ‹å®žé™…è§‚æµ‹åˆ°çš„é—´éš”ï¼Œé˜ˆå€¼ä¼šç³»ç»Ÿæ€§åç´§ã€‚ADR-0035 è¯´çš„"å®½è¿›"æ˜¯åŽ»æŽ‰è¦†ç›–ç§Ÿçº¦ï¼Œä¸æ˜¯é‡æ–°å®šä¹‰ä»€ä¹ˆç®—ä¸€æ¬¡å‘Šæ´»ã€‚
2. **ç¡çœ åªæ‰£ä¸åŠ ã€‚** è·¨å¤œæ²‰é»˜ä¸æ˜¯"èŠ‚å¥æ…¢"çš„è¯æ®ï¼Œå–åˆ†ä½æ•°å‰å…ˆæ‰£æŽ‰ä¸Žè´¦æˆ·é…ç½®ç¡çœ çª—çš„é‡å ã€‚`private.sleep_relaxed` çš„ 2 å°æ—¶é†’åŽå®½é™**ä¸æ‰£**â€”â€”é‚£æ˜¯æŠ‘åˆ¶å‘Šè­¦çš„è£…ç½®ï¼Œä¸æ˜¯å…³äºŽä½œæ¯çš„è¯æ®ã€‚
3. **åŒä¸€è§„åˆ™åªç•™ä¸€ä»½å®žçŽ°ã€‚** é¦–ç‰ˆæŠŠç¡çœ é‡å å†™æˆ per-gap è¾…åŠ©å‡½æ•°ï¼Œç”Ÿäº§é‡çº§ä¸‹è·‘ä¸å®Œï¼›å·²æ”¹ä¸º rebuild å†…éƒ¨ä¸€æ¬¡æ€§é›†åˆè¿ç®—ï¼Œè¾…åŠ©å‡½æ•°åˆ é™¤ã€‚

ç”»åƒè¡Œæ˜¯**ä¸­æ€§å€¼**ï¼šä¸å« sensitivity bufferã€ä¸å«åœ°æ¿ä¸Žå¤©èŠ±æ¿ã€‚è°æ¥ç»„è£…æœ€ç»ˆé˜ˆå€¼ï¼Œè°è´Ÿè´£è¿™äº›ã€‚ä¸»é”®å¸¦å‚æ•° `(user_id, through_date, lookback_days, shrinkage_k, percentile)`ï¼Œå› æ­¤ç¬¬ä¸‰æ­¥æ ‡å®š `k` æ—¶å¤šç»„ç»“æžœå¯ä»¥å…±å­˜æ¯”å¯¹ã€‚

`gaps_overlapping_open_alert` æ˜¯è¯Šæ–­åˆ—ä¸æ˜¯è¿‡æ»¤å™¨ï¼šADR-0035 é€‰äº†å®½è¿›ï¼Œè¢«å‘Šè­¦è¦†ç›–çš„é—´éš”ç…§æ”¶ï¼Œä½†å¿…é¡»å¯é‡åŒ–â€”â€”å¦åˆ™"ç³»ç»Ÿåˆ¤å®šå¼‚å¸¸ â†’ è¯¥æ®µæ²‰é»˜è¿›å…¥ç”»åƒ â†’ é˜ˆå€¼æŠ¬é«˜ â†’ ä¸‹æ¬¡æ›´éš¾è§¦å‘"æ˜¯ä¸€æ¡é—­åˆçš„åé¦ˆå›žè·¯ã€‚

**ç”Ÿäº§å®žæµ‹ï¼ˆ2026-08-02ï¼Œçª—å£ 07-04ï½ž08-03ï¼Œk=50ï¼‰**ï¼š

| è´¦æˆ· | n | æ‰£ç¡çœ åŽ p95 | é”š | blended | çŽ°è¡Œ live | è¢«å‘Šè­¦è¦†ç›–çš„é—´éš” |
|---|---|---|---|---|---|---|
| Chunwei | 1385 | 39 | 317 (cohort) | 49 | 280 | 16 |
| Tong Kam Sheng | 791 | 63 | 90 (fallback) | 65 | 435 | 31 |
| Bernardo Gumapac | 593 | 96 | 90 | 96 | 426 | 25 |
| sanagu | 592 | 105 | 90 | 104 | 575 | 25 |
| iOS tester | 150 | 640 | 317 | 559 | 600 | 34 |
| Sonam Tshering | 133 | 595 | 317 | 519 | 600 | 31 |
| çŸ¥æ‹‰ | 68 | 490 | 90 | 321 | 180 | 0 |
| Karma Cheki | 64 | 615 | 90 | 385 | 600 | **45 / 64** |
| Apk tester | 59 | 297 | 90 | 202 | 180 | 6 |
| AI Audit | 6 | 42 | 90 | 85 | 135 | 0 |
| Sonam Pemo | 0 | â€” | 317 | 317 | 135 | 0 |

ä¸‰ç‚¹å¿…é¡»å¸¦è¿›ç¬¬ 2/3 æ­¥ï¼š

- **æ”¹åŠ¨æ–¹å‘æ˜¯åŒå‘çš„ï¼Œå¯†é›†è´¦æˆ·æ”¶ç´§æžçŒ›ã€‚** Chunwei çŽ°è¡Œ 280 åˆ†é’Ÿã€æ–°ä¸­æ€§å€¼ 49ï¼›å³ä¾¿åŠ ä¸Š balanced çš„ +45 ä¹Ÿåªæœ‰ 94ã€‚çŽ°è¡Œ `silence_threshold` æœ«å°¾çš„ `greatest(fixed_minutes, â€¦)` åœ°æ¿ï¼ˆ90/135/180ï¼‰ä¿ä¸ä¿ç•™ï¼Œç›´æŽ¥å†³å®šè¿™ä¸ªæ”¶ç´§åˆ°ä¸åˆ°å¾—äº†ç”Ÿäº§ã€‚
- **consent é—¨æŠŠç¾¤ä½“æ¨¡åž‹é¥¿æ­»äº†ã€‚** 11 ä¸ªè´¦æˆ·åªæœ‰ 2 ä¸ª `consent_data_sharing = true`ï¼Œä¸”éƒ½è½åœ¨ `semester_break`ï¼ŒäºŽæ˜¯è¯¥ preset çš„"ä¸­ä½æ•°"æ˜¯ 39 åˆ†é’Ÿçš„äººä¸Ž 595 åˆ†é’Ÿçš„äººå–ä¸­ç‚¹ï¼ˆ317ï¼‰ï¼Œå…¶ä½™ preset å…¨éƒ¨å›žè½åˆ°å¸¸æ•° 90ã€‚æ”¾ä¸æ”¾å¼€æ˜¯éšç§å†³å®šï¼Œå› æ­¤åšæˆå‚æ•° `_cohort_requires_consent`ï¼Œé»˜è®¤å¼€ã€‚
- **Karma Cheki çš„ 64 ä¸ªé—´éš”é‡Œæœ‰ 45 ä¸ªä¸Žå‘Šè­¦é‡å ã€‚** è¿™æ¡ç”»åƒåŸºæœ¬æ˜¯ä»Ž"ç³»ç»Ÿå·²åˆ¤å®šå¼‚å¸¸"çš„æ—¶æ®µå­¦æ¥çš„ï¼Œåé¦ˆå›žè·¯å·²ç»ä¸æ˜¯ç†è®ºé£Žé™©ã€‚

`distinct_event_days` æœ€é«˜ 15 å¤©è€Œéž 30ï¼šcanonical-v2 å‘Šæ´»è‡ª 2026-07-19 æ‰å¼€å§‹ï¼Œçª—å£å‰åŠæ®µæ²¡æœ‰å¯ç”¨è¯æ®ã€‚

**æœªæŽ¥çº¿**ï¼š`private.silence_threshold` ä»è¯» `public.alert_gap_profiles`ï¼›æœªè£… cronï¼›æœªåŠ å…¥ realtime publicationï¼›è¡¨åªæœ‰ owner æƒé™ä¸” RLS å¼€å¯æ— ç­–ç•¥ã€‚ç¬¬ 2 æ­¥ï¼ˆå½±å­å¹¶è¡Œè®°å½•æ¯”å¯¹ï¼‰ã€ç¬¬ 3 æ­¥ï¼ˆç”¨çœŸå®žæ•°æ®æ ‡å®š `k` äº¤äººç¡®è®¤ï¼‰ã€ç¬¬ 4 æ­¥ï¼ˆåˆ‡æ¢æ•°æ®æºï¼‰ã€ç¬¬ 5 æ­¥ï¼ˆè¦†ç›–ç§Ÿçº¦æ‘˜é™¤ï¼‰å„è‡ªç‹¬ç«‹æ²»ç†ã€‚

### ADR-0035 ç¬¬äºŒæ­¥ï¼šå€™é€‰ä¸ŽçŽ°è¡Œå¹¶è¡Œ + åäº‹å®žå›žæ”¾ï¼ˆå·²ä¸Šç”Ÿäº§ï¼Œä»æœªæŽ¥çº¿ï¼‰

[Claude Â· 2026-08-02 23:10 +01:00] `KC-ADR35-SHADOW-COMPARE-001`

æ–°å¢ž `public.account_threshold_shadow` ä¸Ž `private.record_account_threshold_shadow(...)`ï¼Œå¦åŠ æ¯æ—¥ cron `account-shadow-cycle-v1`ï¼ˆ02:37 UTCï¼Œåªå†™è¿™ä¸¤å¼ å½±å­è¡¨ï¼‰ã€‚

**é˜ˆå€¼ä¸æ˜¯å†³ç­–ï¼Œå¼€è­¦æ‰æ˜¯ã€‚** å› æ­¤ä¸åªè®°ä¸¤ä¸ªæ•°ï¼Œè€Œæ˜¯æŠŠçª—å£å†…æ¯ä¸€æ®µæ²‰é»˜æŒ‰å„æ¡è§„åˆ™å›žæ”¾ä¸€éï¼Œæ•°å‡ºä¼šå¼€è­¦çš„æ¬¡æ•°ï¼Œå¹¶ä¿ç•™å¯æŸ¥çš„åˆ†æ­§æ ·æœ¬ã€‚

ä¸‰æ¡å®¹æ˜“æžé”™çš„åœ°æ–¹ï¼Œå·²å†™è¿›è¿ç§»æ³¨é‡Šï¼š

1. **ç¡çœ åœ¨"å­¦ä¹ "æ—¶æ‰£é™¤ï¼Œåœ¨"å¼€è­¦"æ—¶æŠ‘åˆ¶ã€‚** å®žæ—¶åˆ¤å®šæ¯”çš„æ˜¯åŽŸå§‹ç»è¿‡æ—¶é—´ï¼ˆ`now() - last_ping`ï¼‰ï¼Œå¦å¤–é  `sleep_relaxed` æ‹’ç»å¼€è­¦ã€‚æ‰€ä»¥å›žæ”¾ç”¨**åŽŸå§‹é—´éš”**ï¼Œç¡çœ åªä½œä¸ºæŠ‘åˆ¶çª—ï¼ˆå«é†’åŽ 2 å°æ—¶å®½é™ï¼‰æŠŠè§¦å‘æ—¶åˆ»å¾€åŽæŽ¨ã€‚æ‰£ä¸¤æ¬¡ä¼šå‡­ç©ºé€ å‡ºæ°¸è¿œä¸å¯èƒ½å‘ç”Ÿçš„å‘Šè­¦ã€‚
2. **åœ°æ¿å­˜åºŸæ˜¯å¾…å†³é—®é¢˜ï¼Œæ‰€ä»¥ä¸¤ä¸ªç­”æ¡ˆéƒ½è®°ã€‚** æ¯è¡ŒåŒæ—¶å¸¦ `candidate_floored_minutes`ï¼ˆä¿ç•™ 90 åˆ†é’Ÿä¸­æ€§åœ°æ¿ï¼Œç­‰äºŽçŽ°è¡Œ ADR-0022 è£…é…ï¼‰ä¸Ž `candidate_unfloored_minutes`ï¼Œä»¥åŠå„è‡ªçš„å¼€è­¦æ¬¡æ•°ã€‚ç”¨æ•°æ®å›žç­”ï¼Œè€Œä¸æ˜¯å†å‘ä¸€æ¬¡è¿ç§»ã€‚
3. **åˆ—åæ˜¯ episodes ä¸æ˜¯ alertsã€‚** ä¸€æ¬¡ä¸é—´æ–­çš„æ²‰é»˜åœ¨ `alerts` è¡¨é‡Œå¯èƒ½æ˜¯å‡ åè¡Œâ€”â€”æ¯æ¬¡è¢«äººè§£é™¤åŽï¼Œ30 åˆ†é’Ÿå†·å´ä¸€è¿‡ã€äººä»ç„¶æ²‰é»˜ï¼Œå°±å†å¼€ä¸€æ¬¡ã€‚Karma Cheki åŒä¸€ 30 å¤©çª—å£é‡Œ `alerts` æœ‰ 101 è¡Œï¼Œè€Œæœ¬è¡¨è®°ä¸º 13 æ¬¡ episodeã€‚æ‹¿æœ¬è¡¨ä¸Ž `alerts` è¡¨å¯¹æ•°æ˜¯é”™çš„æ¯”è¾ƒï¼Œæœ¬è¡¨æ˜¯ä¸¤æ¡è§„åˆ™åœ¨åŒä¸€ä»½é—´éš”åŽ†å²ä¸Šçš„åŒæ³•å¯¹æ¯”ã€‚

**ç”Ÿäº§å®žæµ‹ï¼ˆ2026-08-02ï¼Œçª—å£ 07-04ï½ž08-03ï¼Œä¿ç•™åœ°æ¿ï¼‰**ï¼š

| è´¦æˆ· | é—´éš”æ•° | çŽ°è¡Œé˜ˆå€¼ | çŽ°è¡Œ episode | k=25 é˜ˆå€¼/æ¬¡ | k=50 é˜ˆå€¼/æ¬¡ | k=100 é˜ˆå€¼/æ¬¡ | k=50 åŽ»åœ°æ¿ |
|---|---|---|---|---|---|---|---|
| Chunwei | 1417 | 280 | 1 | 135 / 4 | 135 / 4 | 135 / 4 | 12 |
| Tong Kam Sheng | 800 | 435 | 0 | 135 / 9 | 135 / 9 | 135 / 9 | 12 |
| sanagu | 617 | 575 | 2 | 148 / 15 | 148 / 15 | 147 / 15 | 15 |
| Bernardo Gumapac | 610 | 426 | 0 | 149 / 23 | 149 / 23 | 148 / 23 | 23 |
| iOS tester | 159 | 600 | 12 | 674 / 9 | 642 / 10 | 596 / 12 | 10 |
| Sonam Tshering | 135 | 600 | 11 | 641 / 11 | 609 / 11 | 566 / 11 | 11 |
| çŸ¥æ‹‰ | 68 | 180 | 7 | 472 / 4 | 411 / 4 | 342 / 4 | 4 |
| Karma Cheki | 64 | 600 | 8 | 513 / 11 | 430 / 13 | 340 / 17 | 13 |
| Apk tester | 60 | 180 | 7 | 325 / 4 | 292 / 4 | 257 / 4 | 4 |
| AI Audit | 6 | 135 | 0 | 135 / 0 | 135 / 0 | 135 / 0 | 0 |
| Sonam Pemo | 0 | 135 | 0 | 361 / 0 | 361 / 0 | 361 / 0 | 0 |

ç»“è®ºï¼Œç›´æŽ¥å–‚ç»™ç¬¬ 3ã€4 æ­¥ï¼š

- **æ€»é‡çº¦ç¿»å€**ï¼šçŽ°è¡Œ 48 æ¬¡ â†’ å€™é€‰ï¼ˆä¿ç•™åœ°æ¿ï¼Œk=50ï¼‰93 æ¬¡ã€‚å¢žé‡å‡ ä¹Žå…¨éƒ¨æ¥è‡ªå¯†é›†è´¦æˆ·ï¼ŒBernardo ä¸€äººä»Ž 0 åˆ° 23ã€‚
- **åœ°æ¿ç¡®å®žåœ¨å¹²æ´»**ï¼šChunwei åŽ»æŽ‰åœ°æ¿åŽé˜ˆå€¼ 94 åˆ†é’Ÿã€12 æ¬¡ï¼Œä¿ç•™åœ°æ¿ 135 åˆ†é’Ÿã€4 æ¬¡ã€‚å››ä¸ªå¯†é›†è´¦æˆ·è¢«åœ°æ¿é’‰åœ¨ 135â€“149ï¼Œ`k` å–ä»€ä¹ˆéƒ½ä¸å½±å“å®ƒä»¬ã€‚
- **`k` åªå¯¹ç¨€ç–è´¦æˆ·æœ‰æ„ä¹‰ï¼Œä¸”æ–¹å‘åç›´è§‰**ï¼šk è¶Šå¤§è¶Šå‘ç¾¤ä½“æ”¶ç¼©ï¼Œè€Œç¾¤ä½“é”šåä½Žï¼ŒäºŽæ˜¯ç¨€ç–è´¦æˆ·é˜ˆå€¼åè€Œ**ä¸‹é™**ã€å¼€è­¦**å¢žå¤š**ï¼ˆKarma 11â†’13â†’17ï¼‰ã€‚"k è¶Šå¤§è¶Šä¿å®ˆ"åœ¨è¿™ä»½æ•°æ®é‡Œä¸æˆç«‹ã€‚
- **ç¨€ç–è´¦æˆ·æ–¹å‘æ˜¯æ”¾å®½**ï¼šçŸ¥æ‹‰ 7â†’4ã€Apk tester 7â†’4ã€iOS tester 12â†’10ï¼Œæ­£æ˜¯ ADR-0035 æƒ³è¦çš„å‡å°‘è¯¯æŠ¥ã€‚

**å›žæ”¾ä¸ŽçœŸå®žåŽ†å²ä¸å¯ç›´æŽ¥å¯¹æ•°**ï¼Œä¸¤ä¸ªå·²æŸ¥æ˜Žçš„åŽŸå› ï¼šâ‘  çŽ°è¡Œé˜ˆå€¼æ˜¯**ä»Šå¤©**çš„å€¼ï¼Œè€Œçª—å£å†…å¤§éƒ¨åˆ†æ—¶é—´è·‘çš„æ˜¯ 07-30 history-seeded æ¿€æ´»å‰çš„æ¨¡æ¿ï¼›â‘¡ ä¸€æ¬¡æ²‰é»˜åœ¨çœŸå®žç³»ç»Ÿé‡Œä¼šåå¤é‡å¼€ï¼ˆè§ä¸‹ï¼‰ã€‚å›žæ”¾çš„ç”¨é€”æ˜¯åŒæ³•å¯¹æ¯”ä¸¤æ¡è§„åˆ™ï¼Œä¸æ˜¯é‡å»ºåŽ†å²ã€‚

**é¡ºå¸¦æŸ¥å‡ºçš„ç‹¬ç«‹ç¼ºé™·ï¼ˆæœªä¿®ï¼Œå¾…ç«‹é¡¹ï¼‰**ï¼šä¸€æ¬¡ä¸é—´æ–­çš„æ²‰é»˜ä¼šåå¤å¼€è­¦â€”â€”äººè§£é™¤ â†’ 30 åˆ†é’Ÿ `_self_grace` å†·å´ â†’ äººä»æ²‰é»˜ â†’ ç«‹å³å†å¼€ã€‚30 å¤©å†… Karma Cheki 101 è¡Œã€Sonam Tshering 86 è¡Œã€iOS tester 71 è¡Œ silence å‘Šè­¦ï¼Œä¸”ç»å¤§å¤šæ•°ç”±äººè§£é™¤ï¼ˆ72/78/60ï¼‰ã€‚è¿™ä¸Ž ADR-0035 æ˜¯ä¸¤ä»¶äº‹ï¼Œä½†ä¼šç›¸ä¹˜ï¼šå€™é€‰è§„åˆ™è‹¥åˆ¶é€ æ›´å¤š episodeï¼Œæ¯ä¸ª episode è¿˜ä¼šå†è¢«è¿™æ¡å¾ªçŽ¯æ”¾å¤§ã€‚

### ADR-0037ï¼šp95 ä½œåºŸï¼Œæ”¹ä¸ºã€Œè¿™ä¸ªäººè‡ªå·±çš„æ­£å¸¸ä¸Šç•Œã€

[Claude Â· 2026-08-04 19:30 +01:00] `KC-ADR37-NORMAL-UPPER-BOUND-001`

**2026-08-04 çš„å¥åº·æ£€æŸ¥å‘çŽ°çŽ°è¡Œæœºåˆ¶æ ¹æœ¬æ²¡åœ¨å­¦**ï¼ˆè¯¦è§ [[Dev Log]] åŒæ—¥æ¡ç›®ï¼‰ï¼š`alert_observation_coverage_intervals` åªæœ‰ä¸¤ä¸ª tester æœ‰è¡Œï¼Œ7 ä¸ªçœŸå®žç”¨æˆ·ä¸º 0ï¼›6 ä¸ªè´¦æˆ·çš„è¯æ®åœåœ¨ 2026-07-19ï¼ˆv1â†’v2 åˆ‡æ¢æ—¥ï¼‰ï¼Œç”»åƒæ¯å¤©æŽ‰ 6â€“8 ä¸ªæ ·æœ¬ã€æŽ‰ 1 ä¸ªæ”¯æ’‘æ—¥ï¼Œé¢„è®¡ 08-09 è‡³ 08-12 é€ä¸ªè·Œç ´æœ‰æ•ˆæ€§ã€**é™é»˜é€€å›žå†™æ­»æ¨¡æ¿**ã€‚

åŒæ—¥å®žæµ‹è¿˜è¯æ˜Žï¼š07-20 ä»¥æ¥ 180 æ¬¡çœŸå®ž silence å‘Šè­¦ï¼Œè‹¥æ¯ä¸ªè´¦æˆ·ç”¨è‡ªå·±çš„æ­£å¸¸ä¸Šç•Œï¼Œåªå‰© 12 æ¬¡ã€‚**å¤±è´¥åŽŸå› ä¸æ˜¯"å­¦ä¸å‡†"ï¼Œæ˜¯ä¸‰å±‚é¢„è®¾ï¼ˆæ¨¡æ¿ 90/135/180ã€600 å¤©èŠ±æ¿ã€æ‹ŸåŠ çš„ 90 åœ°æ¿ï¼‰æŠŠå­¦å‡ºæ¥çš„å€¼ä»Žå¤´åˆ°å°¾è¦†ç›–æŽ‰äº†**ï¼Œè€Œ p95 æ˜¯ç¬¬å››ä¸ªé”™è¯¯â€”â€”å®ƒçš„å®šä¹‰å°±æ˜¯"æ”¾è¿‡ 5%"ï¼Œä¸æ˜¯ä¸Šç•Œã€‚

æ–°è¡¨ `public.account_normal_bounds` + `private.rebuild_account_normal_bounds(...)`ï¼š

- **å­¦çš„é‡æ˜¯ `escape_minutes`**ï¼šå¯¹æ¯ä¸€æ®µæ²‰é»˜ï¼Œ"æœ€å¤§çš„ã€ä»ä¼šå¯¹å®ƒå¼€è­¦çš„é˜ˆå€¼" = ä»Žæ²‰é»˜å¼€å§‹ï¼Œåˆ°å®ƒç»“æŸå‰æœ€åŽä¸€ä¸ªåˆ¤å®šå™¨**è¢«å…è®¸åŠ¨ä½œ**çš„çž¬é—´ã€‚ç¡çœ çª—ä¸Žé†’åŽå®½é™ç›´æŽ¥å†…å«åœ¨è¿™ä¸ªé‡é‡Œï¼Œä¸å†æ˜¯å•ç‹¬çš„æ‰£å‡â€”â€”è¿™ä¹Ÿä¿®æ­£äº†ç¬¬ä¸€æ­¥"å­¦ä¹ æ‰£ç¡çœ ã€åˆ¤å®šæ¯”åŽŸå§‹æ—¶é•¿"çš„å£å¾„ä¸ä¸€è‡´ã€‚
- **é˜ˆå€¼ = é™åºç¬¬ `i` ä¸ª escape + sensitivity buffer**ï¼Œ`i = max(æŽ‰çº¿å®ˆå«, 1 + round(B Ã— D / 30))`ï¼ŒB ä¸ºæ¯ 30 å¤©å®¹è®¸è¯¯æŠ¥æ•°ï¼ŒD ä¸ºè¯æ®å¤©æ•°ã€‚**è®¾åœ¨ç¬¬ `i` ä¸ªä¹‹ä¸Šï¼Œæœ€å¤šåªæœ‰ iâˆ’1 æ®µæ²‰é»˜ä¼šå¼€è­¦**â€”â€”è¯¯æŠ¥çŽ‡æˆäº†å”¯ä¸€çš„ç­–ç•¥è¾“å…¥ã€‚
- **æŽ‰çº¿å®ˆå«**ï¼šåªè¦æ²‰é»˜æ•° â‰¥10 å°±å¼ºåˆ¶ `i â‰¥ 2`ï¼Œä¸€æ¬¡æŽ‰çº¿æ°¸è¿œä¸èƒ½æˆä¸ºæŸäººçš„ä¸Šç•Œã€‚çŸ¥æ‹‰æœ€é•¿é—´éš” 13839 åˆ†é’Ÿï¼ˆ9.6 å¤©æŽ‰çº¿ï¼‰ï¼Œæ— å®ˆå«æ—¶ `i=1` ä¼šæŠŠä»–çš„çº¿å®šåˆ° 9.7 å¤©ï¼Œç­‰äºŽå–æ¶ˆä¿æŠ¤ï¼›åŠ å®ˆå«åŽè½åœ¨ 1398 åˆ†é’Ÿï¼ˆ23.3 å°æ—¶ï¼‰ã€‚**è¿™æ¡å®ˆå«æ˜¯é˜²ç¦»ç¾¤å€¼ï¼Œä¸æ˜¯å¯¹ç”¨æˆ·é¢‘çŽ‡çš„é¢„è®¾ã€‚**
- **æ— å¤©èŠ±æ¿ã€æ— åœ°æ¿ã€æ— æ¨¡æ¿é”šç‚¹ã€æ— ç¾¤ä½“æ”¶ç¼©**ï¼ˆADR-0035 çš„ `n/(n+k)` ä¸€å¹¶ä½œåºŸï¼šå‘ç¾¤ä½“ä¸­ä½æ•°æ”¶ç¼©æœ¬èº«æ˜¯é¢„è®¾ï¼Œä¸”ä¼šæŠŠç¨€ç–è´¦æˆ·çš„çº¿å¾€ä¸‹æ‹‰ï¼Œæ–¹å‘é”™è¯¯ï¼‰ã€‚
- **æ— è¯æ®ä¸å‘æ˜Žé˜ˆå€¼**ï¼š`has_usable_signal=false`ã€`threshold_minutes` ä¸º NULLï¼Œå¦‚å®žæ ‡æ³¨è€Œä¸æ˜¯æ‹¿æ¨¡æ¿å†’å……ä¿æŠ¤ã€‚

**ç”Ÿäº§å®žæµ‹ï¼ˆ2026-08-04ï¼Œçª—å£ 07-06ï½ž08-05ï¼ŒB=1ï¼‰**ï¼š

| è´¦æˆ· | è¯æ®å¤© | æ²‰é»˜æ•° | i | æœ€é•¿ï¼ˆæŽ‰çº¿ï¼‰ | ä¸Šç•Œ | æ–°é˜ˆå€¼ | çŽ°è¡Œé˜ˆå€¼ | æ–° episode | çŽ°è¡Œ episode |
|---|---|---|---|---|---|---|---|---|---|
| Chunwei | 17 | 1667 | 2 | 377 | 253 | 298 | 340 | 1 | 1 |
| Tong Kam Sheng | 17 | 890 | 2 | 286 | 262 | 307 | 435 | 0 | 0 |
| sanagu | 17 | 884 | 2 | 702 | 663 | 708 | 486 | 0 | 2 |
| Bernardo Gumapac | 17 | 699 | 2 | 425 | 425 | 470 | 411 | 0 | 3 |
| iOS tester | 17 | 224 | 2 | 2369 | 1334 | 1424 | 600 | 1 | 13 |
| Sonam Tshering | 17 | 148 | 2 | 1208 | 971 | 1061 | 600 | 1 | 12 |
| Karma Cheki | 17 | 112 | 2 | 1193 | 1114 | 1159 | 600 | 1 | 9 |
| Apk tester | 7 | 100 | 2 | 1240 | 1098 | 1188 | 180 | 1 | 10 |
| çŸ¥æ‹‰ | 8 | 98 | 2 | 13839 | 1398 | 1488 | 180 | 1 | 9 |
| AI Audit | 2 | 14 | 2 | 793 | 427 | 472 | 135 | 1 | 2 |
| Sonam Pemo | 0 | 0 | 1 | â€” | â€” | æ—  | 135 | 0 | 0 |

**å…¨ä½“ 61 â†’ 7 æ¬¡ã€‚äºº 2026-08-04 åœˆå®šçš„ã€Œæ­£å¸¸ä½œæ¯ã€6 äººï¼ˆChunweiã€Tongã€sanaguã€Bernardoã€çŸ¥æ‹‰ã€AI Auditï¼‰ï¼š17 â†’ 3 æ¬¡ã€‚**

~~**ä»æœªæŽ¥çº¿**ï¼š`private.silence_threshold` ä¾ç„¶è¯» `public.alert_gap_profiles`~~ â€”â€” **æ­¤æ¡å·²äºŽ 2026-08-08 æ ¸å®žä¸ºè¿‡æ—¶**ã€‚ç”Ÿäº§ `private.silence_threshold` è¯»çš„æ˜¯ `public.account_normal_bounds`ï¼Œä¸”å·²ä¸å†å¼•ç”¨ `alert_gap_profiles`ï¼›æŽ¥çº¿ç”± `20260804135728_silence_threshold_reads_normal_bounds` äºŽ 08-04 13:57 å®Œæˆã€‚08-09 è‡³ 08-12 çš„é™é»˜é€€å›žæ¨¡æ¿é£Žé™©éšä¹‹è§£é™¤ã€‚

### 2026-08-08ï¼šæŽ¥çº¿ä¹‹åŽæ¯æ™šé‡ç®—æŒ‚äº†å››å¤©

[Claude Â· 2026-08-08 23:50 +06:00] `KC-NIGHTLY-REBUILD-ISOLATION-001`

`account-shadow-cycle-v1` è‡ª 08-05 èµ·è¿žç»­å››æ™šå¤±è´¥ï¼Œå…¨éƒ¨è´¦æˆ·é˜ˆå€¼å†»ç»“åœ¨ 08-04ï¼Œ**æ— ä»»ä½•å‘Šè­¦**ã€‚ä¸¤ä¸ªç‹¬ç«‹ç¼ºé™·å åŠ ï¼š

- **å¹¶è¡ŒæœŸé—ç•™å­—æ®µã€‚** `live_threshold_minutes` ä¸Ž `episodes_live` æ˜¯ ADR-0037 ä¸Šçº¿å‰"æ–°æ—§å¹¶æŽ’å¯¹æ¯”"çš„äº§ç‰©ã€‚æ—§é˜ˆå€¼ 08-04 é€€ä¼‘åŽï¼Œè¿™ä¸€åˆ—é—®çš„æ˜¯ `silence_threshold`â€”â€”ä¹Ÿå°±æ˜¯**æ­£åœ¨è¢«é‡ç®—çš„é‚£å¼ è¡¨è‡ªå·±**ï¼ŒäºŽæ˜¯ `episodes_live` è‡ªåˆ‡æ¢èµ·å°±æ˜¯åºŸæ•°ï¼›è€Œæ— è¯æ®è´¦æˆ·çš„æ­£ç¡®ç­”æ¡ˆæ˜¯ NULLï¼Œè¢« `NOT NULL` çº¦æŸæ‹’ç»ã€‚è¯¥åˆ—ä¸Žæœ¬ ADRã€Œæ— è¯æ®ä¸å‘æ˜Žé˜ˆå€¼ã€ç›´æŽ¥çŸ›ç›¾ï¼Œå·²åˆ é™¤ï¼ˆ`account_threshold_shadow` çš„åŒååˆ—æ˜¯çœŸå½±å­ï¼Œä¿ç•™ï¼‰ã€‚
- **æ— æŒ‰äººéš”ç¦»ã€‚** æ•´ä¸ªé‡ç®—æ˜¯å•æ¡ `INSERT ... SELECT`ï¼Œä¸€è¡Œè¿è§„æ•´æ¡å›žæ»šã€‚**åªä¿®å­—æ®µä¸ä¿®è¿™ä¸€ç‚¹ï¼Œä¸‹ä¸€ä¸ªæ²¡é¢„è§åˆ°çš„è¾¹ç•Œæƒ…å†µè¿˜ä¼šè®©å…¨ä½“å½’é›¶ã€‚** çŽ°æ”¹ä¸ºï¼šæ˜‚è´µçš„æ‰«æä»åªè·‘ä¸€æ¬¡ï¼Œå†™å…¥æŒ‰äººéš”ç¦»ï¼Œç®—ä¸å‡ºæ¥çš„è®°è¿› `private.job_failures` å¹¶ç»§ç»­ã€‚åŒç±»ä¿®å¤å·²åº”ç”¨äºŽ `process_escalations`ã€`process_checkin_tasks`ã€`run_daily_aggregations`ï¼ˆé€è¡ŒéªŒè¯åªå¢žä¸æ”¹ï¼‰ã€‚
- **è¡¥ç®—**ï¼š08-05 è‡³ 08-08 å››å¤©å·²è¡¥ï¼Œæ¯å¤© 11 è´¦æˆ·ã€0 è·³è¿‡ã€‚

**æ–°å‘çŽ°ï¼ˆæœªå¤„ç†ï¼Œå¾…è£å†³ï¼‰ï¼šæŽ‰çº¿å®ˆå«åªè·³è¿‡ä¸€ä¸ªç¦»ç¾¤å€¼ï¼Œè·³ä¸è¿‡ä¸¤ä¸ªã€‚** çŸ¥æ‹‰çª—å£å†…çŽ°æœ‰ä¸¤æ¬¡é•¿æŽ‰çº¿â€”â€”æœ€é•¿ 13839 åˆ†ï¼ˆ9.6 å¤©ï¼‰ã€ç¬¬äºŒé•¿ **5885 åˆ†ï¼ˆ4.1 å¤©ï¼‰**ï¼›å®ˆå«å¼ºåˆ¶ `order_index â‰¥ 2` åªæŽ’é™¤æœ€é•¿çš„é‚£æ¬¡ï¼Œç¬¬äºŒæ¬¡ç›´æŽ¥æˆä¸ºä»–çš„æ­£å¸¸ä¸Šç•Œï¼Œé˜ˆå€¼ä»Ž 08-04 çš„ 1488 åˆ†ï¼ˆ23.3 å°æ—¶ï¼‰è·³åˆ° **5975 åˆ†ï¼ˆ4.1 å¤©ï¼‰**ã€‚æ¨¡åž‹æ— æ³•åŒºåˆ†ã€Œè®¾å¤‡æ²¡ä¿¡å·ã€ä¸Žã€Œè¿™ä¸ªäººæœ¬æ¥å°±é™ã€ï¼Œå› æ­¤**è¶Šæ˜¯åå¤æŽ‰çº¿çš„äººï¼Œä¿æŠ¤è¶Šæ¾**â€”â€”è€Œè®¾å¤‡æœ€ä¸å¯é çš„äººæ­£æ˜¯æœ€éœ€è¦ä¿æŠ¤çš„äººã€‚ADR-0037 å·²æŽ¥å—ç¨€ç–è´¦æˆ·å¾—åˆ°é•¿çº¿ï¼Œä½† 4.1 å¤©ä¸Žäººå½“åˆæŽ¥å—çš„ 23 å°æ—¶æ˜¯ä¸¤å›žäº‹ï¼Œéœ€äººè£å†³ã€‚

**çœ‹é—¨ç‹—**ï¼š`private.scheduled_job_health()` çŽ°åœ¨ä»Ž `cron.job_run_details` ä¸Ž `job_failures` æŽ¨å¯¼æ¯ä¸ªå®šæ—¶ä»»åŠ¡çš„å¥åº·ï¼ˆè·‘æŒ‚äº† / ä¸è·‘äº† / è·‘äº†ä½†è·³è¿‡äº†äººï¼‰ï¼Œæ¯ 30 åˆ†é’Ÿç» `private.report_unhealthy_jobs()` é€šçŸ¥ GMï¼ŒåŒä¸€æ¬¡å¼‚å¸¸åªé€šçŸ¥ä¸€æ¬¡ã€‚ä¸Šçº¿å½“åˆ»å³æŠ¥å‡º `account-shadow-cycle-v1: last 4 run(s) failed`â€”â€”**è¿™æ­£æ˜¯å››å¤©å‰æœ¬è¯¥å‘ç”Ÿçš„äº‹**ã€‚

## è¦†ç›–æœ‰æ•ˆå­¦ä¹ ï¼ˆADR-0039ï¼ŒS3-C2 å·²å®žçŽ°ï¼‰

[Claude Â· 2026-08-10] `20260810000000_s3_coverage_valid_learning.sql`

`private.rebuild_account_normal_bounds` çŽ°åœ¨æœ‰å››é“é—¨ï¼š

1. **è¦†ç›–**ï¼šgap å¿…é¡»**å®Œæ•´è½åœ¨**ä¸‰è½´ï¼ˆ`activity_coverage_state` / `intervention_coverage_state` / `sleep_context_state`ï¼‰çš† `valid` çš„ `alert_observation_coverage_intervals` ä¹‹å†…ã€‚åŒ…å«è€Œéžé‡å â€”â€”åŠä¸ª gap åœ¨è¦†ç›–å†…ï¼Œå¦å¤–åŠä¸ªæ°æ°æ˜¯å¯èƒ½å‡ºäº‹çš„åœ°æ–¹ã€‚
2. **æ¥æº**ï¼š`kind='manual_checkin'`ã€`source in ('shortcut','manual')`ã€replayï¼ˆ`received_at` ä¸Ž `at` åå·® > 300sï¼‰ä¸€å¾‹ä¸è®­ç»ƒï¼›Guardian è¡Œä¸ºåŒç†ã€‚
3. **é‡å¤è¯æ®**ï¼šå€™é€‰æ˜¯å¦"å¼‚å¸¸"ï¼Œä»¥**å…¶ä½™ gap çš„ä¸­ä½æ•°**è¡¡é‡ï¼ˆä¸å«è‡ªèº«ï¼‰ï¼›å¼‚å¸¸å€™é€‰éœ€åœ¨æœ¬äººæ—¶åŒºä¸‹**ä¸¤ä¸ªä¸åŒæ—¥æœŸ**å­˜åœ¨ â‰¥80% é•¿åº¦çš„å¯æ¯” gapï¼Œå¦åˆ™å‘**æ›´å°**å€™é€‰ä¸‹ç§»ã€‚åªæœ‰ä¸€ä¸ª gap æ—¶ä¸å­˜åœ¨åˆ†å¸ƒï¼Œä¸åˆ¤å¼‚å¸¸ï¼Œå¦‚å®žé‡‡ç”¨ã€‚
4. **ç»“æžœ**ï¼šæ— åˆæ ¼è¯æ® â†’ `has_usable_signal=false` + `threshold_minutes=NULL`ã€‚ç»ä¸æ¨¡æ¿ã€ç»ä¸ 0ã€‚

**å…³é”®è¿è¥å«ä¹‰**ï¼šNULL é˜ˆå€¼ â†’ `process_escalations` ä¸äº§ç”Ÿæ²‰é»˜å‘Šè­¦ã€‚è¦†ç›–åŒºé—´ç”±é»˜è®¤å…³é—­çš„ adaptive shadow çº¿äº§å‡ºï¼Œå› æ­¤**æœªå¯ç”¨è¦†ç›–é‡‡é›†çš„çŽ¯å¢ƒéƒ¨ç½²æ­¤ç‰ˆæœ¬ = æ²‰é»˜å‘Šè­¦é™é»˜å¤±æ•ˆ**ã€‚å¿…é¡»å…ˆæœ‰å®ˆæŠ¤å¥åº·æ˜¾çŽ° `Limited`/`unknown`ï¼ˆS3-C3ï¼‰ï¼Œä¸” rollout å‰ç¡®è®¤è¦†ç›–é‡‡é›†çœŸåœ¨äº§å‡ºã€‚


---

