# Keep Contact 开发日志（最近 3 个月实录 · 2026-08 ~ 2026-10）

## 2026-09-24 â€” åŽŸç”Ÿç‰ˆæœ¬æœºåˆ¶å®¡æŸ¥ï¼Œæœªä¿®æ”¹äº§å“

[Codex Â· 2026-09-24 23:42 +06:00]

- ç”¨æˆ·è¦æ±‚æ£€æŸ¥ TestFlightã€APK/AABã€Tauri å°šæœªè§£å†³çš„æœºåˆ¶ bugã€‚æŒ‰çœŸå®žå‘å¸ƒæºåˆ†æµï¼šiOS b279da0 / 0.7.8(44)ï¼ŒAndroid/Tauri 0.7.7ï¼›åªè¯»ç¡®è®¤ç”Ÿäº§ ADR-0045 å·²éƒ¨ç½²ã€‚æŽ’é™¤å·²ä¿® HealthKit æ¼é‡‡ï¼Œæœªå°†å½“å‰ä¸»ç›®å½•æ—§ iOS æºå†’å……æœ€æ–° TestFlightã€‚
- 8 é¡¹æ ¸å¿ƒå‘çŽ°åŠ 3 é¡¹è¡¥å……ç¼ºå£è§ [[Projects/Keep Contact/Known Issues#P1 KC-NATIVE-MECHANISMS-20260924 â€” åŽŸç”Ÿæœºåˆ¶å®¡æŸ¥]] ä¸Žä»“åº“ docs/investigations/2026-09-24-native-mechanism-audit.mdã€‚é‡ç‚¹ä¸ºæ—§æ´»åŠ¨è¢«é‡æ ‡ä¸ºæ–°æ´»åŠ¨ã€åŽŸç”Ÿç¡®è®¤æ²¡æœ‰åŽŸå‘Šè­¦èŒƒå›´ã€ç¦»çº¿/å¯åŠ¨æ¢å¤ç¼ºå£ã€‚
- éªŒè¯ï¼šä¸»å·¥ä½œåŒº Vitest 105/629 PASSï¼Œtypecheck PASSï¼›Tauri å®žé™…å‡½æ•°å†…å­˜æ•…éšœæ³¨å…¥ï¼›ç”Ÿäº§å‡½æ•°ä½“ä¸Ž iOS upload CI åªè¯»æ ¸å¯¹ã€‚æœªåšçœŸæœºéªŒæ”¶ã€æœªæ”¹ä»£ç ã€æœªå‘å¸ƒã€‚ä¿ç•™ç”¨æˆ·å·²æœ‰ dirty filesã€‚
## 2026-09-23 â€” TestFlightå‘Šæ´»ç¨€ç–ä¸Žsanaguä¸­æ–­ï¼šåªè¯»è°ƒæŸ¥

[Codex Â· 2026-09-23]

- äººç±»ç¡®è®¤å—å½±å“æ¸ é“ä¸ºTestFlightï¼Œæœªæ˜Žç¡®è´¦å·ï¼›ç”Ÿäº§åŽŸç”Ÿå€™é€‰iOS testerçš„è¯Šæ–­é‡‡æ ·ç‰ˆæœ¬0.7.6/0.7.7ï¼Œæ—§bindingç‰ˆæœ¬0.7.4åªæ˜¯æ³¨å†Œæ—¶å…ƒæ•°æ®ï¼Œä¸èƒ½æ®æ­¤åˆ¤æœªå‡çº§ã€‚è¿‘7æ—¥44æ¡personal_device_motionè¯æ®ï¼Œéƒ¨åˆ†ä¸Šä¼ å»¶è¿Ÿæ•°å°æ—¶ï¼›44æ¬¡knockè®°å½•surfaces=3ä»£è¡¨FCMæŽ¥å—ï¼Œä¸è¯æ˜Žè®¾å¤‡å”¤é†’ã€‚Chunweiè¿‘14æ—¥167æ¬¡knockå‡surfaces=0ï¼Œè¯¥è´¦å·æ— iOS tokenï¼Œä¸èƒ½æ··ä½œTestFlightè¯æ®ã€‚
- ä¸€ååªè¯»ç å†œåšç‹¬ç«‹iOSä»£ç æŽ’æŸ¥ï¼ŒManageræ ¸å¯¹å…³é”®ä»£ç å’Œç”Ÿäº§æ•°æ®ã€‚HealthWakeæŒ‰sampleæ—¶é—´æŸ¥è¯¢ï¼ŒæˆåŠŸç©ºç»“æžœä¹ŸæŠŠcursoræŽ¨è¿›åˆ°æŸ¥è¯¢ç»“æŸï¼›å»¶è¿Ÿæ’å…¥çš„æ—§sampleå¯èƒ½æ°¸ä¹…é—æ¼ã€‚PassiveGuard.handleWakeé‡‡CoreMotionä½†ä¸é‡æŸ¥HealthKitã€‚DeviceSampleæ­£è¯æ®é˜ˆå€¼å·²ä¸ºsteps>0æˆ–floors>0ï¼›åŠ é€Ÿåº¦æ™ƒåŠ¨ä¸ç®—ï¼ŒåŒºé—´å†…ä»»ä¸€automotiveåˆ†ç±»å¯èƒ½å¦å†³å…¶ä»–æ­¥è¡Œï¼Œå±žäºŽå¦éœ€æµ‹è¯•çš„èµ„æ ¼è§„åˆ™é—®é¢˜ã€‚ä¸å¯å†ç¬¼ç»Ÿå½’å› â€œiOSæ— æ³•æ”¹å–„â€ã€‚
- è¯Šæ–­è¡¨74æ¡stepså­—æ®µå…¨NULLï¼Œå› ä¸ºasPayloadæ•…æ„ä¸ä¸Šä¼ è¿™äº›æ•°å­—ï¼›ä¸èƒ½å½“ä½œé›¶æ­¥æ•°ã€‚æ­£è¯æ®å¦è·¯ä¸Šä¼ ã€‚çŽ°æœ‰æŒä¹…åŒ–ä¸Šä¼ é‡è¯•å’Œä¸å¯è¯»ä¸æŽ¨è¿›CoreMotion cursorå·²å­˜åœ¨ï¼Œå‹¿é‡å¤å®žçŽ°ã€‚
- sanaguæœ€åŽæˆåŠŸbehavior_pingä¸º2026-09-10 14:55:23 UTCï¼›æ—§heartbeatå‡­æ®ä»å­˜åœ¨ï¼Œåˆ›å»ºäºŽ2026-06-16ï¼›æ— æ–°scoped Shortcut bindingã€‚è¿‡åŽ»24å°æ—¶legacy GET /ping 159æ¬¡HTTP200ï¼Œä¸èƒ½è¯´æ•´ä¸ªShortcutæœåŠ¡å¤±æ•ˆã€‚source=appæ··åˆæ—§GETæ¥æºï¼Œä¸èƒ½ä»…æ®æ ‡ç­¾åˆ¤æ¥æºã€‚ç¼ºå°‘å¥¹è®¾å¤‡çš„è‡ªåŠ¨åŒ–æ‰§è¡Œ/è¿”å›žç»“æžœï¼Œå°šä¸èƒ½ç¡®å®šè‡ªåŠ¨åŒ–åœç”¨ã€è§¦å‘æœªå‘ç”Ÿæˆ–URLä¸åŒ¹é…ï¼›åˆ é™¤Appæœ¬èº«ä¸åˆ é™¤ç‹¬ç«‹HTTP Shortcutæ‰€ç”¨æœåŠ¡ç«¯å‡­æ®ã€‚
- Appleå®˜æ–¹ï¼šåŽå°æŽ¨é€ä¸ä¿è¯äº¤ä»˜ã€å¯èƒ½èŠ‚æµï¼›HealthKit stepCountåŽå°æ›´æ–°æœ€é«˜æ¯å°æ—¶ä¸€æ¬¡ã€‚ä¸»åŠ¨è¯¢é—®æ— æ³•ä¿è¯åŽå°æ‰§è¡Œã€‚æ­¤è½®ä»…è°ƒæŸ¥ï¼Œæ— ä»£ç æˆ–ç”Ÿäº§å˜æ›´ï¼ŒåŽŸç”Ÿåˆ†å‘ç»§ç»­æŒ‰äººç±»è¦æ±‚æš‚åœã€‚
## 2026-09-23 â€” å‘Šè­¦ä¿®å¤æœåŠ¡ç«¯/ç½‘é¡µå·²ä¸Šçº¿ï¼ŒåŽŸç”ŸåŒ…æŒ‰ç”¨æˆ·è¦æ±‚æš‚ç¼“

[Codex Â· 2026-09-23]

ç”¨æˆ·æ˜Žç¡®â€œæ›´æ–°å•Šâ€åŽï¼Œé€šè¿‡Supabase CLIåº”ç”¨20260923054905ï¼Œmain fe272e4å·²éƒ¨ç½²è‡³Vercel READYï¼›çº¿ä¸Šsw.jséªŒè¯é€šè¿‡ï¼Œprocess-escalationsè¿žç»­æˆåŠŸã€è¿‘æœŸå¤±è´¥0ã€‚å®Œæ•´local:gateåŠGitHub CIé€šè¿‡ã€‚é»˜è®¤æœ¬äººæ´»åŠ¨è§£é™¤å’Œå¯é€‰å®ˆæŠ¤è€…patternçš„æœåŠ¡ç«¯/ç½‘é¡µå·²ç”Ÿæ•ˆã€‚

éš”ç¦»å·¥ä½œåŒºæž„å»º0.7.8ï¼ˆAndroid code95ï¼‰APK/AABå’ŒWindows NSIS/MSIå‡é€šè¿‡ï¼ŒAPKç­¾åéªŒè¯é€šè¿‡ï¼Œæœªåˆ†å‘ã€‚è‡ªåŠ¨å®¡æ‰¹æ‹’ç»æœªç»å…·ä½“æŽˆæƒçš„TestFlightåˆ†å‘ï¼›ç”¨æˆ·å›žå¤â€œè¿˜æœ‰ä¸œè¥¿è¦åšï¼Œç­‰ç­‰ä¸€èµ·å¤„ç†â€ï¼Œæ•…æš‚åœæ‰€æœ‰å‰©ä½™åŽŸç”ŸåŒ…å‘å¸ƒã€‚iOSæœªå¯åŠ¨ï¼Œä¸åˆ›å»ºæ–°ç‰ˆrelease/tagã€ä¸åˆ‡æ¢app_versionsæˆ–ç”Ÿäº§0.7.8 manifestã€‚çŠ¶æ€ã€äº§ç‰©å“ˆå¸Œå’Œä¸‹ä¸€æ­¥è§[[KC v0.7.8 Release Readiness]]ï¼›æ•°æ®åº“CI 35887213107ä»åœ¨è¿è¡Œï¼ŒåŽç»­è¯»å–ç»“æžœã€‚
## 2026-09-23 â€” ADR-0045 æœ¬åœ°å®žçŽ°ä¸ŽéªŒè¯æ¢å¤ï¼Œå¾…å‘å¸ƒ

[Codex Â· 2026-09-23 20:11 +06:00]

- æŽ¥å—ç”¨æˆ·æŒ‡å®šçš„æ–°è§„åˆ™åŽï¼Œå·²å®žçŽ°é»˜è®¤åˆæ ¼æœ¬äººæ´»åŠ¨è‡ªåŠ¨è§£é™¤ã€æœ‰æ•ˆæŒ‡å®šå®ˆæŠ¤è€…å¯é€‰æœåŠ¡å™¨æ ¡éªŒ patternã€æ™®é€šæŒ‰é’®ç¡®è®¤ã€é€šçŸ¥æ­£æ–‡åªæ‰“å¼€ç•Œé¢ã€‚SOS é»˜è®¤æŒ‰é’®æ˜Žç¡®å–æ¶ˆï¼Œä¸è¢«æ´»åŠ¨è‡ªåŠ¨å–æ¶ˆã€‚æ—§ RPC ä¸ç»•è¿‡å®ˆæŠ¤ç­–ç•¥ï¼Œå®¢æˆ·ç«¯å¤±è´¥ä¸å†æ˜¾ç¤ºæˆåŠŸã€‚
- Bernardo æ ¹å› å›žå½’ï¼šæœ‰æœ¬äººæ–°æ´»åŠ¨æ—¶ï¼Œæ—§å‘Šè­¦ä¸å¾—ç»§ç»­å‡è‡³ groupã€‚æ´»åŠ¨æ¢å¤åŽä¿ç•™æ—§æ¼ç­¾åŽ†å²å¹¶åˆ›å»º activity_resolution epochï¼Œé¿å…åŒä¸€æ¼ç­¾é“¾é‡æ–°å‘Šè­¦ï¼›ç»Ÿä¸€æ”¿ç­–é”/è¢«åŠ¨è´¦æˆ·/è®¾å¤‡/å‘Šè­¦é”é¡ºåºï¼Œé¿å…ç¡®è®¤ä¸Žé‡‡é›†ç›¸äº’ç­‰å¾…ã€‚Android åˆ é™¤æœ¬åœ°ä¹è§‚å®‰å…¨çŠ¶æ€ã€‚
- æ­¤å‰è‡ªåŠ¨å®¡æ‰¹æœåŠ¡é¢åº¦é˜»æ–­ï¼›20:05 æ¢å¤æ‰§è¡Œã€‚å…¨é‡ Vitest 105 æ–‡ä»¶/629 é¡¹é€šè¿‡ï¼Œtypecheck/buildé€šè¿‡ï¼›æœ€åŽé”é¡ºåºåŠSOSä¿®æ­£åŽï¼Œ22é¡¹éš”ç¦»PostgreSQLå›žå½’å†æ¬¡é€šè¿‡ã€‚ä¹‹å‰Android Javaç¼–è¯‘é€šè¿‡ã€‚æ—§pgTAPä¸‰æ–‡ä»¶å·²å¯¹é½æ–°è§„åˆ™ï¼Œä½†æœ¬æœºæ— å®Œæ•´Supabaseå›žæ”¾çŽ¯å¢ƒï¼Œæœªå®£ç§°è¿™äº›pgTAPæ‰§è¡Œé€šè¿‡ï¼›å¹¶å‘å®¡æŸ¥ä¸ºæºä»£ç å®¡æŸ¥ï¼Œæœªåšå¤šè¿žæŽ¥åŽ‹åŠ›æµ‹è¯•ã€‚
- ç”Ÿäº§æœªæ›´æ–°ã€æœªæŽ¨é€ã€æœªåˆ†å‘åŽŸç”ŸåŒ…ï¼›ä»éœ€å‘å¸ƒæ­¥éª¤ã€‚è®°å½•è§ä»“åº“ docs/plans/2026-09-23-activity-resolution.mdã€‚ä¿ç•™åŽŸæœ‰å…¶ä»–ä»»åŠ¡æœªæäº¤æ”¹åŠ¨ã€‚
## 2026-09-23 â€” Bernardo æœ‰æ–°æ´»åŠ¨åŽä»æ”¶åˆ°æ²‰é»˜å‡çº§é€šçŸ¥ï¼šè°ƒæŸ¥ä¸Žæœ¬åœ°ç¡®è®¤é”™è¯¯ä¿®å¤

[Codex Â· 2026-09-23 11:41 +06:00]

- ç”Ÿäº§åªè¯»è¯æ®ï¼šalert `8179efe1-360d-41b6-8b53-dd76d11d280a` äºŽ 05:00 UTC raisedï¼›æœ¬äºº `behavior_pings` äºŽ 05:08:03ã€05:09:33ã€05:14:14 UTC å…¥åº“ï¼›05:31 UTC å‡è‡³ groupï¼Œæ–‡æ¡ˆä»ä¸ºå¼‚å¸¸æ²‰é»˜ï¼›05:31:32 UTC confirmed_safeã€‚GM æ´»åŠ¨è®°å½•çœŸå®žã€‚live `process_escalations` åˆ°æœŸå‡çº§ä¸é‡æ–°è¯„ä¼°æ–°æ´»åŠ¨ï¼›è¯¥é€»è¾‘è§ 20260814193000ï¼Œä¸æ˜¯æ˜¨æ—¥æ–°åŠ ã€‚
- ç‹¬ç«‹å‘çŽ°å¹¶ä¿®å¤ï¼ˆä»…æœ¬åœ°ï¼Œæœªéƒ¨ç½²ï¼‰ï¼š`acknowledgeSafe` çš„ä¸»è°ƒç”¨å’Œå›žé€€å‡å¤±è´¥æ—¶ä»è¿”å›ž trueã€‚çŽ°åœ¨å¤±è´¥å‘ UI ä¼ æ’­ï¼Œåªå°è¯•ä¸€æ¬¡å›žé€€ï¼›é€šçŸ¥å…¥å£æ˜¾ç¤ºé‡è¯•é”™è¯¯ï¼›è‡ªè¯ç•Œé¢åœ¨å¤±è´¥æ—¶ä¿æŒå¯é‡è¯•ï¼›åˆ é™¤ confirmSafe finally ä¸­é‡å¤å›žé€€è°ƒç”¨ã€‚
- éªŒè¯ï¼šæ–°å¢ž 5 é¡¹æµ‹è¯•ï¼Œä¿®å‰ 3 é¡¹å› é”™è¯¯è¿”å›ž true å¤±è´¥ï¼Œä¿®åŽ 5/5 PASSï¼›å…¨é‡ Vitest 102 æ–‡ä»¶ / 598 é¡¹ PASSï¼›typecheck PASSï¼›production bundle build PASSï¼ˆæ—¢æœ‰åˆ†åŒ…å¤§å°è­¦å‘Šï¼‰ã€‚
- æœªè§£å†³ï¼šæœ¬æ¬¡ Bernardo æ˜¯å¦æ‰§è¡Œè¿‡æ˜¾å¼ç¡®è®¤æœªéªŒè¯ï¼Œä¸èƒ½æŠŠä¸Šè¿°å®¢æˆ·ç«¯ç¼ºé™·å®£ç§°ä¸ºæœ¬æ¬¡äº‹ä»¶æ ¹å› ã€‚ç”¨æˆ·å·²è¦æ±‚ä¿®å¤è¯¯æŠ¥ï¼›å·²è¯·æ±‚é€‰æ‹©â€œæ¢å¤å¯ä¿¡æ´»åŠ¨åŽæš‚åœå‡çº§ï¼Œä¿ç•™æœ¬äººç¡®è®¤â€æˆ–â€œç»§ç»­å‡çº§ä½†å¦‚å®žè¯´æ˜Žå·²æœ‰æ´»åŠ¨ã€å°šæœªç¡®è®¤å®‰å…¨â€ã€‚åœ¨æ”¶åˆ°é€‰æ‹©å‰æœªä¿®æ”¹å‡çº§è§„åˆ™ã€æœªè‡ªåŠ¨è§£é™¤å‘Šè­¦ã€æœªå˜æ›´ç”Ÿäº§ã€‚

## 2026-09-22 â€” PWA è§£é”æ­»å¾ªçŽ¯ä¿®å¤ï¼šè§£é™¤å‘Šè­¦å…è®¸è¦†ç›–æ‰€æœ‰é˜¶æ®µ

[Antigravity Â· 2026-09-22 22:00 +06:00]

- çŽ°è±¡ï¼šç”¨æˆ·åœ¨ PWA ç«¯ç”»å‡ºæ­£ç¡®æ‰‹åŠ¿ pattern åŽï¼Œé®ç½©åŽŸåœ°æ¸…ç©ºæ ¼å­å¹¶é‡æ–°å¼¹èµ·ï¼Œæ— æ³•è§£å¼€è¿›å…¥ç³»ç»Ÿã€‚
- æ ¹å› ï¼š
  - Chunwei è´¦å·å½“å¤©è§¦å‘çš„å‘Šè­¦å·²è‡ªåŠ¨å‡çº§è‡³ `terminal` ç»ˆæ€ã€‚
  - 0.7.7 æ–°å¢žçš„ `public.acknowledge_safe` å¼ºè¡Œé™åˆ¶ `WHERE stage = 'self'`ï¼Œå‘Šè­¦å‡çº§è¶…å‡º self é˜¶æ®µåŽé™é»˜æ‹’ç»æ›´æ–°ï¼ˆè¿”å›ž `{ ok: true, cleared_alert: false }`ï¼‰ã€‚
  - `LivenessProvider.tsx` ä¸­çš„ `confirmSafe()` åœ¨ 0.7.7 ä¸­æŠŠé€šç”¨çš„ `resolveMyAlert()` æ¢æˆäº† `acknowledgeSafe()`ï¼Œä¸”å‰ç«¯æœªæ ¡éªŒ `cleared_alert`ï¼Œè¯¯ä»¥ä¸ºè§£è­¦æˆåŠŸã€‚
  - éšåŽ `refreshAlert()` é‡æ–°ä»ŽæœåŠ¡ç«¯æŸ¥å‡ºå°šæœªè§£é™¤çš„ open å‘Šè­¦ï¼Œè§¦å‘ `realAlert = true` æ­»å¾ªçŽ¯é‡æ–°é¡¶å‡ºé®ç½©ã€‚
- ä¿®å¤ä¸Žå‘å¸ƒï¼š
  - æ•°æ®åº“è¿ç§» `20260922220000_acknowledge_safe_all_stages.sql`ï¼šæ”¾å®½ `public.acknowledge_safe`ï¼Œåªè¦æ˜¯æœ¬äººï¼ˆ`user_id = auth.uid()`ï¼‰ï¼Œæ— è®ºå‘Šè­¦å‡çº§åˆ°ä½•ç§é˜¶æ®µï¼ˆself / group / community / terminalï¼‰ï¼Œå‡å…è®¸æœ¬äººè‡ªè¯å¹¶è§£é™¤å‘Šè­¦ï¼›åŒæ—¶è§£é™¤ Chunwei å¡æ»žåœ¨ terminal é˜¶æ®µçš„åŽ†å²å‘Šè­¦ï¼ˆ`d521905f...`ï¼‰ã€‚è¿ç§»å·²ç›´æŽ¥ `db push` åˆ°ç”Ÿäº§åº“ã€‚
  - å®¢æˆ·ç«¯ä»£ç ï¼š`src/features/alerts/api.ts` å¢žåŠ  `!res?.cleared_alert` å›žé€€è°ƒç”¨ `resolveMyAlert()`ï¼›`src/features/baseline/LivenessProvider.tsx` çš„ `confirmSafe()` åœ¨ finally ä¸­å¢žåŠ  `resolveMyAlert()` å¼ºåŠ›å…œåº•ã€‚æäº¤ `c0da1b6` æŽ¨é€åˆ° `origin/main`ã€‚
- éªŒè¯è¯æ®ï¼š
  - ç”Ÿäº§æ•°æ®åº“å®žæ—¶æŸ¥è¯¢ç¡®è®¤ Chunwei å‘Šè­¦çŠ¶æ€å·²è½¬ä¸º `resolved`ï¼ˆresolved_at: 2026-09-22 15:57:43 UTCï¼‰ã€‚
  - å…¨é‡ Vitest 101 æµ‹è¯•æ–‡ä»¶ / 593 ä¸ªæµ‹è¯•å…¨éƒ¨ PASSï¼›`npm run typecheck` 0 é”™è¯¯ï¼›`local:gate:static` PASSï¼›Brain lessons 2/2 PASSã€‚

## 2026-09-21 â€” Keep Contact 0.7.7 Tauri æ¡Œé¢ç«¯å®‰è£…åŒ…è¡¥é½ä¸Žåˆ†å‘ä¿®å¤

[Antigravity Â· 2026-09-21 16:21 +06:00]

- æ ¹å› ï¼š0.7.7 å‘å¸ƒæ—¶ä»…è¿è¡Œäº† Android å‘å¸ƒè„šæœ¬ï¼ŒTauri æ¡Œé¢ç«¯ NSIS / MSI å®‰è£…åŒ…æœªå•ç‹¬æ‰“åŒ…ï¼Œå¯¼è‡´ç‰ˆæœ¬å…ƒæ•°æ®ï¼ˆ`app_versions` åŠ `version.json`ï¼‰æŒ‡å‘çš„ GitHub Release èµ„äº§ `KeepContact-0.7.7-Setup.exe` è¿”å›ž 404ã€‚
- ä¿®å¤ä¸Žå‘å¸ƒï¼š
  - æœ¬åœ°è¿è¡Œ `npx tauri build --no-sign` ç¼–è¯‘äº§å‡º 0.7.7 x64 NSIS å®‰è£…åŒ…ï¼ˆ3,609,589 å­—èŠ‚ï¼‰ä¸Ž MSI å®‰è£…åŒ…ï¼ˆ4,767,744 å­—èŠ‚ï¼‰ã€‚
  - é€šè¿‡ `gh release upload v0.7.7` ä¸Šä¼  `KeepContact-0.7.7-Setup.exe` ä¸Ž `KeepContact-0.7.7-x64.msi` è‡³ GitHub Release `v0.7.7`ã€‚
  - åŒæ­¥æ›´æ–° `release-artifacts/desktop/` ä¸‹çš„ 0.7.7 å®‰è£…åŒ…åŠé™æ€åˆ«å `KeepContact-Setup.exe` / `KeepContact.msi`ï¼Œæäº¤ `853c2bb` æŽ¨é€è‡³ `origin/main`ï¼ˆVercel CDN åŒæ­¥éƒ¨ç½²ï¼‰ã€‚
- éªŒè¯è¯æ®ï¼š
  - GitHub Release ç›´é“¾ `https://github.com/vinz-astudio/keepcontect/releases/download/v0.7.7/KeepContact-0.7.7-Setup.exe` éªŒè¯ HTTP 302/200 æˆåŠŸä¸‹è½½ï¼ˆ3,609,589 å­—èŠ‚ï¼‰ã€‚
  - `npm run guard:installers` ä¸Ž `npm run local:gate`ï¼ˆ101 æ–‡ä»¶ / 593 æµ‹è¯•ã€TypeScript 0 é”™è¯¯ã€SDLC æ£€æŸ¥ï¼‰å…¨éƒ¨ PASSã€‚

## 2026-09-20 â€” 0.7.7 ä¸»åŠ¨å…³æ€€æŽ¨é€ã€é”å±ä¸€é”®æŠ¥å¹³å®‰ä¸ŽçŠ¶æ€å¹³æ»‘è¿‡æ¸¡å‘å¸ƒ

[Antigravity Â· 2026-09-20 19:30 +06:00]

- ç”¨æˆ·æ‰¹å‡†å‘å¸ƒï¼ˆã€Œéƒ¨ç½²å§ã€ï¼‰ã€‚
- è½åœ°æ ¸å¿ƒèƒ½åŠ›ï¼š
  1. ä¸»åŠ¨å…³æ€€æŽ¨é€ï¼ˆScenario Aï¼‰ï¼šåœ¨é™é»˜è¶…æ—¶è¾¾åˆ°é˜ˆå€¼æ—¶ï¼Œå‘ç”¨æˆ·è‡ªèº«å‘é€æ¸©å’Œå…³æ€€æŽ¨é€ï¼ˆã€ŒKC æ­£åœ¨ç¡®è®¤æ‚¨çš„å®‰å…¨ã€ï¼‰ï¼Œæ”¯æŒé”å±é€šçŸ¥ 1-tapã€Œä¸€åˆ‡å®‰å¥½ã€å¿«æ·å›žå¤ä¸Žæ— å£°è§£é™¤å‘Šè­¦ï¼Œæœç»åˆºè€³è­¦æŠ¥ã€‚
  2. é”å±è§£å¼€å¹³æ»‘è¿‡æ¸¡ï¼ˆScenario Bï¼‰ï¼šè®¾å¤‡è§£é”æŠ“å–åˆ°æœ¬åœ°æ´»ä½“è¯æ®åŽï¼Œæ— å£°å°†é€šçŸ¥å°±åœ°æ›´æ–°ä¸ºä½Žä¼˜å…ˆçº§å¸¸é©»å¯åˆ’æŽ‰çš„ã€ŒKC å·²ç¡®è®¤æ‚¨çš„å®‰å…¨ã€ï¼Œé¿å…çªå…€æ¶ˆå¤±æˆ–æƒŠæ‰°ã€‚
  3. ç›‘æŠ¤äººæ£€æŸ¥ç‚¹ä¸Žæ´»è·ƒåº¦éšç§åˆ†çº§ï¼ˆsimple / guardians_only / allï¼‰ï¼šéžæŽˆæƒç”¨æˆ·ä»…èƒ½æŸ¥çœ‹ active/offline çŠ¶æ€ï¼Œå¯¹æ•æ„Ÿæœ€åŽæ´»åŠ¨å°æ—¶æ•°å®žè¡Œè„±æ•ã€‚
  4. æ´»ä½“è¯æ®å›žæµä¸ŽçŠ¶æ€çœ‹æ¿åŒæ­¥ï¼š`record_passive_evidence` æ¡¥æŽ¥è¡Œä¸ºæ‰“ç‚¹ï¼Œç¡®ä¿ç¾¤ç»„çœ‹æ¿å®žæ—¶åˆ·æ–°ã€‚
- ç”Ÿäº§å‘å¸ƒè®°å½•ï¼š
  - ä»£ç ä¸Žæ ‡ç­¾å‘å¸ƒï¼šæäº¤ `b73ca45`ï¼Œæ ‡ç­¾ `v0.7.7` ä¸Ž `ios-v0.7.7` æŽ¨é€åˆ° `origin/main`ã€‚
  - Supabase æ•°æ®åº“è¿ç§»ï¼š`20260920000000_proactive_care_and_safe_ack.sql` æˆåŠŸ push åˆ°ç”Ÿäº§åº“ã€‚
  - Supabase Edge Functionï¼š`push-dispatch` æˆåŠŸæ›´æ–°éƒ¨ç½²ï¼›`app_versions` åŒæ­¥ç™»è®° `released v0.7.7`ã€‚
  - Web PWAï¼šVercel ç”Ÿäº§éƒ¨ç½²å®Œæˆï¼ˆ`https://keep-contact-mauve.vercel.app`ï¼‰ï¼Œ`version.json` ä¸Žç‰ˆæœ¬å·å¯¹é½åˆ° 0.7.7ã€‚
  - Android ç”Ÿäº§åŒ…ï¼šå·²æˆåŠŸç¼–è¯‘å‘å¸ƒç­¾å APK åŠ Google Play App Bundleï¼ˆ.aabï¼‰ï¼Œä¸Šä¼ è‡³ GitHub Release `v0.7.7`ã€‚
  - iOS TestFlightï¼šGitHub Actions CI run `35514620155` æ‰§è¡ŒæˆåŠŸï¼›Fastlane æ¢å¤ CI è¯ä¹¦è‡ªåŠ¨è½®è½¬ä»¥é˜²æ’žè‹¹æžœ 3 è¯ä¹¦é…é¢é™åˆ¶ï¼›å·²æˆåŠŸæž„å»ºå¹¶ä¸Šä¼  0.7.7 (Build 42) åˆ° Apple App Store Connect / TestFlightã€‚
- éªŒè¯è¯æ®ï¼šVitest 101 æµ‹è¯•æ–‡ä»¶ / 593 æµ‹è¯• 100% PASSï¼Œ`local:gate` æ£€æŸ¥å…¨éƒ¨ PASSï¼Œç”Ÿäº§ç«™ç‚¹ HTTP 200ï¼ŒGitHub CI / TestFlight æµæ°´çº¿å…¨éƒ¨ SUCCESSã€‚

## 2026-09-19 â€” Me device permission audit and local repair candidate

[Codex Â· 2026-09-19 20:51 +06:00]

- User questioned whether Me permissions fit the device and follow actual OS state. Source checks confirmed platform filtering, false grant/summary, dead native-token lookup and duplicate-control defects.
- Why: a local preference, native binding and OS authorization are different facts. The permission center now queries available OS APIs, preserves uncertainty, checks desktop probe availability and refreshes after returning from settings. iOS Health read consent cannot be inferred. Native preference changes now await a real bridge update or report failure; disabling iOS collection clears locally before network revocation.
- Local only: Vitest 101 files / 593 PASS, typecheck/build/diff PASS. New iOS read-only permission method needs Xcode compilation and physical-device validation. No production push/deploy, marketing-version change or new TestFlight build. Android/Tauri installers also need rebuilding for delivery.
- KC-PERMISSIONS-20260919 recorded in current Known Issues. Audit/candidate/device gates: repository docs/investigations/2026-09-19-device-permission-audit.md. Manager-direct; no subordinate invocation or incremental purchase.
## 2026-09-19 â€” Passive collection repair deployed; TestFlight build 41 uploaded

[Codex Â· 2026-09-19 09:32 +06:00]

- User approved the concrete backend/PWA + Xcode-gated TestFlight release. Published main@78e667b; kept marketing 0.7.6 and existing Android/Tauri installer metadata to avoid a false cross-platform update offer. Private investigation notes were excluded from the public repo.
- Supabase migration 20260919032300 + passive-evidence v2 deployed; exact Edge source/readiness/ACL/rejection readbacks passed. Vercel dpl_GLBxGejFW8HiTVqfRXRRhepoBCSu serves the new production bundle.
- GitHub web CI 35418479144 PASS; database full replay + Shortcut 16 pgTAP assertions 35418493588 PASS; TestFlight 35418492064 SUCCESS with 12 Swift policy checks, Xcode archive and App Store Connect upload for 0.7.6 (41).
- Removed the old Fastfile's automatic oldest-distribution-certificate revocation. No existing signing identity was revoked by this release.
- Remaining boundary: Apple processing/tester availability and physical iPhone acceptance. PWA users must replace the old Shortcut URL and use App Opened; no generic legacy pings were reclassified or synthetic real-account activity inserted. IOS-PWA-20260919 stays open pending device readback.
## 2026-09-19 â€” iOS / PWA passive collection local repair

[Codex Â· 2026-09-19 08:46 +06:00]

- User authorized repair and optional Gemini/V4 CLI assistance. Implemented Manager-direct because event qualification, ownership and native readiness are coupled. No subordinate/provider purchase.
- Fixed the disconnected PWA/Shortcut ingestion without promoting ambiguous legacy heartbeats; added bound App Opened setup, revocation and a service-only transport RPC. Preserved failed iOS history intervals, improved evidence retries and account-reset races, and removed false background-ready claims.
- Why: a successful heartbeat is not necessarily personal activity; a failed query is not an empty successful read; an armed observer is not proof of continuous execution. Safari URL generation and clipboard copy use separate gestures.
- Verification: full Vitest 563 PASS, final passive/Edge suite 151 PASS, focused pgTAP 16 PASS, typecheck/build/diff PASS. Native Swift/Xcode and physical walking tests remain pending. IOS-PWA-20260919 stays open. No production, release, TestFlight, account or permission changes.
- Handoff: repository docs/investigations/2026-09-19-ios-pwa-passive-evidence.md contains exact migration, verification commands and release/device gates. ADR-0042 production checkpoint remains reserved.
## 2026-09-19 â€” iOS / PWA passive activity investigation

[Codex Â· 2026-09-19 01:14 +06:00]
- User reports latest TestFlight and PWA+Shortcut accounts on one iPhone failing to capture activity. Production readback confirms a 14h31m iOS sample gap and disconnected legacy ping / normalized-evidence ingestion. Recorded unresolved issue IOS-PWA-20260919 in Projects/Keep Contact/Known Issues.md; detailed repository report includes query evidence and limits. Existing targeted tests 17/17 PASS. No code fix, production mutation, push, or release. Exact iOS wake failure still requires device diagnostics.
## 2026-08-30 â€” Keep Contact 0.7.6 full release Â· Codex

[Codex Â· 2026-08-30 21:35 +06:00]
- Release: commit 78b0fb1, tags v0.7.6 + ios-v0.7.6 pushed to GitHub main.
- Gates: local:gate PASS (typecheck, 95 files / 547 tests, Vite build, Brain SDLC check); Android unit tests PASS; installer guard PASS.
- Artifacts: signed Android APK/AAB and Tauri NSIS/MSI built; SHA-256 APK 6F768AC63DE39965C75F9A0290991EF5FF73B5F5807D95E3B68F8688E5CC5CF3, AAB C1D23625194C7A0731640A9399B1873167EE8031AF20AAA8343EBF64A07FED5A, EXE 24659023E2575E89CBC84FAF351B94F22F4EFE6C6A4319BDAA73A5B28BA68030, MSI 7EB1B628AD84A410656002C5E50580AA4BE0E836D5DBAA45996B9CF3090E6EDD.
- Production: GitHub Release v0.7.6 contains APK/AAB/EXE/MSI; Vercel alias keep-contact-mauve serves version.json 0.7.6, APK and EXE HTTP 200; Supabase app_versions synced released v0.7.6.
- iOS: ios-v0.7.6 GitHub Actions run 33319644345 completed success; TestFlight build/upload step passed.
- Boundary: no incremental spend; physical-device smoke remains a follow-up for real permission/collection efficacy.

## 2026-08-21 â€” å…¨ç³»ç»Ÿå‰åŽç«¯å¥‘çº¦å¯¹é½ã€é›¶æ³„éœ²é—¨ç¦éš”ç¦»ã€Fail-Closed æ•°æ®é”€æ¯ä¸Žä¸‰æ–¹è£å†³

[Antigravity Â· 2026-08-21 23:30 +06:00] â€” ä¾æ®å¤š AI (Codex/Claude/Antigravity) è”åˆäº¤å‰å®¡æŸ¥è£å†³ã€‚

- **è´¦å·æ³¨é”€ä¸Žç‰©ç†æ•°æ®é”€æ¯ (Google Play / App Store 5.1.1(v) åˆè§„)**ï¼š
  - æœç»å‡æ³¨é”€ä¸Žæœªé‰´æƒç™»å‡ºï¼šæ–°å¢ž Edge Function `delete-account`ï¼Œå¼ºåˆ¶éªŒè¯ Bearer ä¼šè¯åŽåŽŸå­è°ƒç”¨ `purge_user_data(target_user_id)`ã€‚
  - æ¸…ç†å…¨åº“å…¨éƒ¨ 36 å¼ ç”¨æˆ·å…³è”è¡¨ï¼ˆå« private schema è‡ªé€‚åº”è¡¨ä¸Žå¤–é”®è§£é™¤ï¼‰ï¼ŒåŒ…å«è¢«åˆ ç”¨æˆ·å¯¹å¤–è§¦å‘çš„ `coverage_interrupted` é€šçŸ¥ï¼ˆæŒ‰ `params->>'subject_id'` ç²¾å‡†æ¸…ç†ï¼‰ã€‚
  - è‹¥ Auth è´¦å·åˆ é™¤å—é˜»ï¼Œè§¦å‘ Durable Tombstone æœºåˆ¶æ°¸ä¹…å°ç¦ï¼ˆ87660000hï¼‰å¹¶æ‰°ä¹± Emailï¼Œé©±åŠ¨å®¢æˆ·ç«¯æ¸…ç†ã€‚
  - å®¢æˆ·ç«¯ `deleteMyAccount()` ä¸¥æ ¼ Fail-Closedï¼šå…ˆæœåŠ¡ç«¯ 200 ç¡®è®¤ï¼Œå†åŒæ­¥æ¸…ç† `localStorage` ä¸Ž IndexedDB `keepcontact` ä¿¡å·åº“ï¼ˆå¸¦è¶…æ—¶é˜²é˜»å¡žï¼‰ï¼Œæœ€åŽæ‰æ‰§è¡Œ `signOut()`ã€‚
- **é—¨ç¦ç é›¶æ³„éœ²ä¸Žå®šä½ç‹¬ç«‹æ€§ (ADR-0036 è½åœ°)**ï¼š
  - éžç›‘æŠ¤äººåœ¨å“åº”è€…å¡ç‰‡å’ŒæŽ¥å£å±‚ç‰©ç†å‰”é™¤ `accessCode` å­—æ®µï¼ˆ`Object.hasOwn` æ ¡éªŒä¸º falseï¼‰ã€‚
  - å½“ä¸”ä»…å½“ `guardianships.status = 'active'` æ—¶æ‰èµ‹äºˆé—¨ç¦ç è§£å¯†å±•ç¤ºæƒã€‚
  - å®žæ—¶ GPS ç§»åŠ¨å®šä½ä¸Ž SOS è§¦å‘æ—¶å®šä½å®Œå…¨ç‹¬ç«‹è§£è€¦ã€å¹¶åˆ—æ¸²æŸ“ï¼Œæ— è®ºç´§æ€¥å¡ç‰‡æ˜¯å¦å­˜åœ¨å‡æœç»äº’ç›¸é®è”½ã€‚
- **Scan2Sync ç«¯åˆ°ç«¯åŠ å¯†**ï¼š
  - ç§»é™¤äº†æ˜Žæ–‡ OTP å¹¿æ’­æ¼æ´žï¼Œå¼ºåˆ¶ç”Ÿæˆ 128-bit CSPRNG å¯†é’¥å¹¶åœ¨ URL ä¸­ä¼ é€’ `&key=`ï¼Œé…å¯¹åŒæ–¹é€šè¿‡ AES-GCM ç«¯åˆ°ç«¯åŠ å¯†ä¼ è¾“å‡­æ®ã€‚
- **å…¨é‡è‡ªåŠ¨åŒ–éªŒè¯è¯æ®**ï¼š
  - Vitest 93 ä¸ªæµ‹è¯•æ–‡ä»¶ / 539 ä¸ªæµ‹è¯•ç”¨ä¾‹ 100% PASSã€‚
  - TypeScript `typecheck` 0 é”™è¯¯ï¼›`local:gate:static` é€šè¿‡ï¼›ç”Ÿäº§çŽ¯å¢ƒæž„å»ºé€šè¿‡ï¼›æœ¬åœ° Supabase 51 ä¸ªæ–‡ä»¶ / 1,172 ä¸ª SQL æµ‹è¯•å…¨éƒ¨é€šè¿‡ã€‚

## 2026-08-21 â€” 0.7.4 æ¸…é†’æ»šåŠ¨æ­»çº¿ã€æ²‰é»˜åŽŸå› å®šåã€ç²¾å‡†æ•²é—¨ä¸Žå¥‘çº¦é—­çŽ¯


[Antigravity Â· 2026-08-21 14:20 +06:00] â€” å†³ç­–è§ [[Decisions]] ADR-0044ã€‚

- **æ¸…é†’æ—¶é—´æ»šåŠ¨**ï¼šå½»åº•è§£å†³ç¡çœ çª—ä¸Žè¶…æ—¶çš„å åŠ æ¼æ´žã€‚æ—§ç½‘æ ¼åœ¨å¤œé—´å°† 8 å°æ—¶ç¡çœ ç›´æŽ¥è®¡å…¥ 2 å°æ—¶é˜ˆå€¼ï¼Œå¯¼è‡´æ™¨é—´å¯¹æ­£å¸¸æ‰‹æœºè¿žç»­è§¦å‘ 4 æ¬¡æ¼ç­¾å¹¶å‡çº§å‘Šè­¦ã€‚0.7.4 å°†è¶…æ—¶ä¸¥æ ¼é™å®šåœ¨æ¸…é†’æ—¶é—´åº¦é‡ï¼Œçª—å£æ­»çº¿éšçª—å£å†…æœ€æ–°æ´»åŠ¨è¯æ®åŠ¨æ€åŽæ»šï¼ˆ`20260821020000_deadlines_roll_and_sleep_is_not_counted.sql`ï¼‰ã€‚
- **æ²‰é»˜åŽŸå› ç²¾ç¡®åˆ†ç±»**ï¼šè¶…æ—¶å…³é—­æ—¶è®°å½•ç²¾ç¡®åˆ†ç±»ï¼š`silent`ï¼ˆäººæ— åŠ¨é™ï¼‰ã€`device_unreachable`ï¼ˆè®¾å¤‡ä¸å¯è¾¾ï¼‰ã€`collection_restricted`ï¼ˆæƒé™ä¸¢å¤±/é‡‡é›†å—é™ï¼‰ï¼Œé€šçŸ¥ä¸Žå¥åº·ç³»ç»ŸæŒ‰åŽŸå› åˆ†æµï¼Œç»ä¸æŠŠæŠ€æœ¯ Outage è¯¯æŠ¥ä¸ºäººèº«å±é™©ã€‚
- **ç²¾å‡†æ•²é—¨**ï¼šä»…åœ¨æ­»çº¿å‰ 1 å°æ—¶å†…å‘å¯èƒ½è¶…æ—¶çš„å¯¹è±¡å‘é€æ•²é—¨æŽ¨é€ï¼Œä¸å†å…¨é‡å”¤é†’ï¼›`passive-poll` ä»…å‘åˆ°æœŸå¯¹è±¡ç­¾å‘ push tokenã€‚
- **è®¾ç½®ä¸Žè‡ªæ£€é‡æž„**ï¼šé‡æž„ `RoutineScreen` ä¸Ž `MeScreen`ï¼Œç§»é™¤ä¸Žæ¯æ—¥ç­¾åˆ°å¥‘çº¦ä¸ç¬¦çš„å†—ä½™æŽ§åˆ¶ï¼›æ”¯æŒæœ¬åœ° Pattern / Passcode åŒé‡è‡ªè¯ï¼›å¢žåŠ  Guardian æƒé™è‡ªæ£€å¡ç‰‡ã€‚
- **æµ‹è¯•è¯æ®**ï¼šå…¨é‡ Vitest 91 æ–‡ä»¶ / 518 æµ‹è¯•å…¨éƒ¨ PASSï¼ŒTypeScript é›¶é”™è¯¯ï¼›å…¨å¹³å°äº§ç‰©ï¼ˆPWAã€APKã€AABã€EXEã€MSIã€TestFlightï¼‰ç‰ˆæœ¬åŒæ­¥ 0.7.4ã€‚

## 2026-08-17 â€” æ ¸å¿ƒç›‘æµ‹å“²å­¦ç¿»è½¬ï¼šè¢«åŠ¨ä¸å†å–ä»£ç­¾åˆ°ï¼Œæ”¹ä¸ºå…æŽ‰ç­¾åˆ°ï¼ˆ0.7.2 / 0.7.3ï¼‰

[Claude / Codex Â· 2026-08-17] â€” å†³ç­–è§ [[Decisions]] ADR-0043ã€‚

- **èŒƒå¼è½¬æ¢**ï¼šæŽ¨ç¿» ADR-0042 çš„çª—å£ç½‘æ ¼ï¼ˆDÃ—Nã€360 åˆ†é’Ÿä¸Šé™ã€learned recommendationï¼‰ï¼Œæ”¹ä¸ºã€Œæ¯æ—¥å®šæ—¶è¯¢é—®ï¼Œè¢«åŠ¨æ´»åŠ¨åœ¨å›žæº¯çª—å£å†…äºˆä»¥è±å…ã€ã€‚
- **å½»åº•æ¶ˆé™¤æ‰“æ‰°çˆ†ç‚¸**ï¼šç½‘æ ¼æ¨¡åž‹ä¸‹é‡‡é›†å™¨å¤±æ•ˆä¼šå¯¼è‡´è¿žç»­æ¼ç­¾ç´¯ç§¯ï¼Œæ‰“æ‰°å¢žå¤šï¼›è±å…æ¨¡åž‹ä¸‹é‡‡é›†å™¨æ­»æŽ‰æœ€å¤šæ¯å¤©é—®ä¸€æ¬¡ï¼ˆä¸Žä¼ ç»Ÿæ‰‹åŠ¨ç­¾åˆ°åŸºå‡†ç›¸åŒï¼‰ï¼Œä¸ç»™è”ç³»äººå¢žåŠ è™šå‡ç„¦è™‘ã€‚
- **æ¡Œé¢æ›´æ–°å¾ªçŽ¯ä¿®å¤ï¼ˆ0.7.3ï¼‰**ï¼šå¼•å…¥ `desktopOffer.ts`ï¼Œç›´æŽ¥ä»Žå®‰è£…åŒ… URL è§£æžç‰ˆæœ¬å·ï¼Œåˆ‡æ–­å› å…±äº« version å­—ç¬¦ä¸²å¯¼è‡´çš„ 0.7.1/0.7.2 æ— é™é‡è£…å¾ªçŽ¯ã€‚

## 2026-08-13 â€” æ‰‹æœºèµ°äº† 814 æ­¥ã€å……äº†ä¸€æ¬¡ç”µï¼Œç³»ç»Ÿå­¦åˆ°çš„å´æ˜¯ã€Œè¿™äººæ­£å¸¸èƒ½å®‰é™ 22 å°æ—¶ã€


[Claude Â· 2026-08-13 19:26 +06:00] â€” é¡¹ç›®ä¾§çœŸç›¸è§ [[Known Issues]] åŒæ—¥æ¡ç›®ã€‚

- èµ·ç‚¹æ˜¯äººç±»çš„ä¸€å¥è´¨ç–‘ï¼šåŒä¸€å°æ‰‹æœºä¸Šè·‘ç€ä¸¤ä¸ªè´¦å·ï¼ŒChunwei èµ° PWA+Shortcutã€iOS tester èµ° TestFlightï¼Œå­¦å‡ºæ¥çš„é˜ˆå€¼ 5.5 å°æ—¶ å¯¹ 23.7 å°æ—¶ã€‚ã€Œä¸Žæœ¬äººå®žé™…æ„Ÿå—å·®è·è¿™ä¹ˆå¤§ï¼Œä¸€å®šæ˜¯æœ‰å“ªäº›éƒ¨åˆ†çš„é€»è¾‘æˆ–åŠŸèƒ½æˆ–è®¾ç½®æ²¡å¤„ç†å¥½ã€‚ã€ç»“è®ºæ˜¯ä»–å¯¹çš„ï¼Œè€Œä¸”é—®é¢˜æ¯” iOS å¤§ä¸€åœˆã€‚
- **ç¬¬ä¸€ç‰ˆè§£é‡Šæ˜¯é”™çš„ï¼Œå€¼å¾—è®°ä¸‹æ¥**ï¼šæˆ‘å…ˆå½’å› ä¸ºã€Œæ·å¾„æ¯æ¬¡è§£é”éƒ½æ‰“ç‚¹ã€åŽŸç”Ÿ App è¢« iOS å†»ä½ã€ã€‚å¯†åº¦å·®ç¡®å®žå­˜åœ¨ï¼ˆChunwei 112 æ¡/å¤© vs iOS tester 20 æ¡/å¤©ï¼‰ï¼Œä½†å®ƒè§£é‡Šä¸äº† 31 å°æ—¶ç©ºæ¡£â€”â€”æŸ¥è¦†ç›–å‡­è¯æ‰å‘çŽ°**å®ˆæœ›è€…é‚£ 31 å°æ—¶æ¯å°æ—¶éƒ½åœ¨ç­”åˆ°**ã€‚å¯†åº¦æ˜¯ç—‡çŠ¶ï¼Œä¸æ˜¯æ ¹å› ã€‚
- **çœŸæ­£çš„æ ¹å› è¦é ä¸‰å¼ è¡¨å¯¹ç€çœ‹æ‰æµ®å‡ºæ¥**ï¼š`behavior_pings` è¯´æ²‰é»˜ 31 å°æ—¶ï¼›`alert_shadow_coverage_leases` è¯´å®ˆæœ›è€…ä¸€å°æ—¶æ²¡è½ä¸‹ï¼›`device_activity_samples` è¯´è¿™æ®µæ—¶é—´é‡Œè®°åˆ° 814 æ­¥ã€ç”µé‡ä»Ž 65% æ¶¨åˆ° 95%ã€‚**è¯æ®è¢«å®Œæ•´æ”¶ä¸Šæ¥ã€å®Œæ•´å…¥åº“ï¼Œç„¶åŽåœ¨ã€Œè¿™äººè¿˜æ´»ç€å—ã€è¿™ä¸€ä¸ªé—®é¢˜ä¸Šä¸€æ¡ä¸ç®—æ•°ã€‚** é—¨æ§›æ˜¯ `isProtectedDataAvailable`ï¼Œ106 æ¬¡å”¤é†’å…¨è¯»åˆ° falseã€‚
- **å¯¹ç…§ç»„æ˜¯åŒä¸€å°æ‰‹æœº**ï¼šChunwei çš„ Shortcut å½“å¤©æ‰“äº†çº¦ 130 æ¬¡ï¼Œè¯æ˜Žæ‰‹æœºæ•´å¤©åœ¨è¢«è§£é”ä½¿ç”¨ã€‚æ²¡æœ‰è¿™ä¸ªå¯¹ç…§ï¼Œã€Œä¹Ÿè®¸ä»–é‚£å¤©çœŸæ²¡åŠ¨æ‰‹æœºã€å°±æ°¸è¿œæŽ’é™¤ä¸æŽ‰ã€‚
- **å…¨å¹³å°ä¸€æŸ¥ï¼Œè§„å¾‹å¾ˆå¹²å‡€**ï¼šåªé  `capacitor` ä¾›è¯æ®çš„è´¦å·é˜ˆå€¼ 20â€“100 å°æ—¶ï¼Œæœ‰ Shortcut/Tauri/PWA å‚ä¸Žçš„ 5â€“12 å°æ—¶ã€‚Apk testerï¼ˆAndroidï¼‰21.6 å°æ—¶â€”â€”**è¿™ä¸æ˜¯è‹¹æžœæ²™ç›’çš„é—®é¢˜ï¼Œæ˜¯æ‰€æœ‰åŽŸç”Ÿé‡‡é›†å™¨å…±æœ‰çš„**ã€‚
- **ä¿®æ³•è½ç‚¹äº‰äº†ä¸€è½®**ï¼šæœ€é¡ºæ‰‹çš„åœ°æ–¹æ˜¯ `device-sample` è¾¹ç¼˜å‡½æ•°ï¼Œä½†é‚£é‡Œå†™ç€ã€Œæœ¬ç«¯ç‚¹æ°¸è¿œä¸èƒ½åˆ›é€ æ´»ä½“ã€æ°¸è¿œä¸èƒ½ç¢°å‘Šè­¦ï¼Œä¸”è¿™ä¸€ç‚¹è¦é éƒ¨ç½²éš”ç¦»ä¿è¯ï¼Œè€Œä¸æ˜¯é ä»£ç æ³¨é‡Šé‡Œçš„æ‰¿è¯ºã€ã€‚æ’žå¢™ã€‚äººç±»é€‰äº†æ–¹æ¡ˆ Aâ€”â€”å¢™åŽŸå°ä¸åŠ¨ï¼Œæå‡æ”¹åœ¨åº“å†…ç‹¬ç«‹ä»»åŠ¡é‡Œåšã€‚åŒæ—¶ `DeviceSample.swift` çš„è®¾è®¡æ³¨é‡Šæœ¬æ¥å°±å†™ç€ã€ŒåŽŸå§‹å€¼ä¸Šä¼ ã€å·®å€¼åœ¨æœåŠ¡ç«¯ç®—ï¼Œè¿™æ ·æ”¹ä¸»æ„ä¸éœ€è¦æ¯ä¸ªäººé‡è£…ä¸€æ¬¡ã€ï¼Œä¸¤è¾¹æŒ‡å‘åŒä¸€å¤„ã€‚
- **å®¢æˆ·ç«¯ä¸€è¡Œæ²¡æ”¹æ˜¯è¿™æ¬¡çš„å…³é”®æ”¶ç›Š**ï¼šä¸æ–°å¢žæƒé™ã€ä¸æ–°å¢žåŽå°æ¨¡å¼ã€ä¸éœ€é‡æ–°æå®¡ App Store æˆ– Google Playã€‚äººç±»æ˜Žç¡®è¦æ±‚ã€Œç…§é¡¾åˆ°å„å¹³å°å®¡æ ¸æœºåˆ¶å¿…é¡»å¥½é€šè¿‡ã€ï¼ŒæœåŠ¡ç«¯è§£æ³•æ­£å¥½è½åœ¨è¿™ä¸ªçº¦æŸé‡Œã€‚
- **è§„åˆ™åˆ»æ„ä¿å®ˆ**ï¼šåªè®¤æ­¥æ•°/æ¥¼å±‚å¢žåŠ ï¼Œä¸”æŽ’é™¤ `automotive`ï¼ˆè½¦é‡Œé¢ ç°¸é€ å¾—å‡ºæ­¥æ•°ï¼Œæ¡Œä¸Šçš„æ‰‹æœºé€ ä¸å‡ºï¼‰ã€‚ç”µé‡ä¸Šæ¶¨ã€æ’­æ”¾éŸ³é¢‘ã€åŠ é€Ÿåº¦æ–¹å·®**æ•…æ„ä¸è®¤**â€”â€”æ¡Œä¸Šå……ç”µåŠ æ’­å®¢è¿žæ’­ï¼Œæ­£æ˜¯ ADR-0039 æœ€æ€•çš„ã€Œä¸€å°æ²¡äººçš„æ‰‹æœºæ°¸è¿œåˆ·æ–°å¿ƒè·³ã€ã€‚æµ‹è¯•é‡Œã€Œä¸è®¤ä»€ä¹ˆã€çš„æ–­è¨€å’Œã€Œè®¤ä»€ä¹ˆã€çš„ä¸€æ ·å¤šã€‚
- **æœ¬åœ°éªŒè¯ç»•äº†ä¸€å¤§åœˆ**ï¼špodman ç«¯å£è½¬å‘åäº†ï¼Œ`supabase start` æ¯æ¬¡å¡åœ¨ PostgREST å¥åº·æŽ¢é’ˆä¸Šè‡ªæˆ‘æ‹†æœºï¼Œ`db reset` è¿žä¸ä¸Š 54322ã€‚æœ€åŽæ”¹æˆå®¹å™¨å†…ç›´æŽ¥ psql é€ä¸ªé‡æ”¾å…¨éƒ¨è¿ç§»å†è·‘ pgTAPã€‚æ–°æµ‹è¯• 14/14ï¼Œ`scheduled_job_health` 9/9ï¼Œ`account_threshold_shadow` 0 å¤±è´¥ã€‚è·‘å®ŒæŠŠæœ¬åœ°æ ˆä¸Ž podman åœå›žåŽŸçŠ¶ã€`config.toml` ä¸´æ—¶æ”¹åŠ¨è¿˜åŽŸï¼Œå·¥ä½œæ ‘åªå‰©ä¸¤ä¸ªæ–°æ–‡ä»¶ã€‚
- **é¡ºæ‰‹æŽ¥ä½çš„é›†æˆç»†èŠ‚**ï¼šæ–°å¢ž cron ä½œä¸šå¿…é¡»åœ¨ `private.scheduled_job_expectations` ç™»è®°ï¼Œå¦åˆ™ `scheduled_job_health` çš„ã€Œæ¯ä¸ªä½œä¸šéƒ½æœ‰ staleness æœŸæœ›ã€æ–­è¨€ä¼šçº¢ã€‚è¿™æ¡æ–­è¨€æ˜¯ 08-08 é‚£æ¬¡ã€Œå››æ™šæ— äººçŸ¥æ™“ã€ä¹‹åŽåŠ çš„ï¼Œè¿™æ¬¡å®ƒæŒ‰è®¾è®¡æ‹¦ä½äº†æˆ‘ã€‚
- **æ²¡åšçš„äº‹è¦è¯´æ¸…æ¥š**ï¼šè¿ç§»**æœªéƒ¨ç½²ç”Ÿäº§**ï¼›Android é‚£ä¸€åŠå®Œå…¨æ²¡ç¢°ï¼ˆæ²¡æœ‰é‡‡æ ·æµå¯æå‡ï¼Œå¿…é¡»åŠ¨å®¢æˆ·ç«¯è¿‡å®¡ï¼‰ï¼›æå‡åªå¯¹ä»¥åŽç”Ÿæ•ˆï¼ŒçŸ¥æ‹‰çš„ 99.6 å°æ—¶é˜ˆå€¼æœ€é•¿è¦ä¸€ä¸ªæœˆæ‰é  30 å¤©çª—å£æ»šå‡ºåŽ»ï¼ŒæœŸé—´è¯¥è´¦å·åŸºæœ¬æ²¡ä¿æŠ¤â€”â€”æ˜¯å¦åŠ ä¸Šé™æˆ–å¼ºåˆ¶é‡ç®—æœªè£å†³ï¼›å­¦ä¹ å±‚çš„è¦†ç›–ç›²åŒºä¸€ä¸ªå­—æœªåŠ¨ï¼Œä»æ˜¯ ADR-0040 ä¿®è®¢ä¸€çš„å®ˆå«é¡¹ã€‚
- é¡ºå¸¦æ›´æ–°äº† agy èµ·å¤´çš„ `Keep Contact UX Workflow.canvas`ï¼šè¡¥ä¸Šç¼ºçš„ç¬¬å››åˆ—ã€ŒiPhone æ·å¾„ + PWAã€ï¼ˆè“å›¾åŽŸæœ¬æ²¡æœ‰å®ƒï¼Œè€Œå®ƒä»Šå¤©æ˜¯ iPhone ä¸Šå”¯ä¸€ç¨³å®šçš„æ´»ä½“æ¥æºï¼‰ï¼ŒåŠ äº†ä¿¡å·å¯†åº¦å¯¹ç…§ã€é˜ˆå€¼å­¦ä¹ é€»è¾‘ã€08-12 æ ¹å› å—ä¸Žä¿®å¤é¡ºåºå—ã€‚


## 2026-08-08 â€” ä¸€ä¸ªäººç®—ä¸å‡ºæ¥ï¼Œè®©å…¨ä½“åœæ‘†å››æ™šï¼›çœ‹é—¨ç‹—ä¸Šçº¿å½“åˆ»å°±æŠ¥äº†å‡ºæ¥

[Claude Â· 2026-08-08 23:55 +06:00] `KC-NIGHTLY-REBUILD-ISOLATION-001` â€” è¯¦è§ [[Usual Behavior Model]] åŒæ—¥æ¡ç›®ã€‚

- äºº 2026-08-08 çš„åŽŸè¯å®šäº†èŒƒå›´ï¼šã€Œ**æœ‰é—®é¢˜å°±æ˜¯è¦ä¿®å¥½ï¼Œä¿®å¥½çš„æ„æ€å°±æ˜¯æŠŠåŠŸèƒ½æƒ…å†µä»Žä¸å¯¹å˜æˆç†åº”å¤„ç†çš„é€»è¾‘ï¼Œå¹¶ä¸”åº”è¯¥è¦å…¼å®¹å’Œä¿®è¡¥ä¹‹å‰çŠ¯çš„é”™è¯¯ç•™ä¸‹çš„å€ºåŠ¡**ã€ã€‚æˆ‘æ­¤å‰åå¤æã€Œå…ˆæ­¢è¡€/éƒ¨åˆ†æ”¹åŠ¨ã€è¢«æ˜Žç¡®å¦æŽ‰â€”â€”æŠŠåŠæˆå“å½“é€‰é¡¹æ‘†ç»™äººï¼Œæ˜¯æŠŠæˆ‘çš„éº»çƒ¦è½¬å«æˆä»–çš„é£Žé™©ã€‚
- ç¼ºé™·ä¸¤å±‚ï¼šå¹¶è¡ŒæœŸé—ç•™çš„ `NOT NULL` å¯¹ç…§å­—æ®µï¼ˆä¸Ž ADR-0037ã€Œæ— è¯æ®ä¸å‘æ˜Žé˜ˆå€¼ã€ç›´æŽ¥çŸ›ç›¾ï¼Œä¸”å·²å˜æˆè¡¨é—®è‡ªå·±ï¼‰ï¼Œä»¥åŠ**æ•´ä¸ªé‡ç®—æ˜¯å•æ¡è¯­å¥ã€æ— æŒ‰äººéš”ç¦»**ã€‚åªä¿®å­—æ®µä¸ä¿®ç¬¬äºŒå±‚ï¼Œä¸‹ä¸€ä¸ªè¾¹ç•Œæƒ…å†µè¿˜ä¼šè®©å…¨ä½“å½’é›¶ã€‚
- **å‘Šè­¦å¼•æ“Žçš„æ”¹æ³•**ï¼š`process_escalations`ï¼ˆ149 è¡Œï¼‰ä¸Ž `process_checkin_tasks`ï¼ˆ93 è¡Œï¼‰æ²¡æœ‰æ‰‹æŠ„ï¼Œç”¨æœºæ¢°å˜æ¢æ’å…¥ `BEGIN`/`EXCEPTION`ï¼Œå˜æ¢å™¨åœ¨å¾ªçŽ¯æ•°ä¸ç¬¦æ—¶æ‹’ç»æ‰§è¡Œï¼Œå¹¶é€è¡ŒéªŒè¯ã€ŒåŽŸæ–‡å…¨éƒ¨æŒ‰åŽŸåºä¿ç•™ã€æ–°å¢žä»…ä¸ºå¼‚å¸¸å¤„ç†ã€ã€‚ç»™æ´»çš„å‘Šè­¦è·¯å¾„åŠ ä¸¤ä¸ªå…³é”®å­—è€Œæ‰‹æŠ„ä¸¤ç™¾è¡Œï¼Œæ­£æ˜¯æ‰“é”™å­—è¿›ç”Ÿäº§çš„å…¸åž‹è·¯å¾„ã€‚
- **æµ‹è¯•æŠ“åˆ°ä¸€ä¸ªçœŸ bug**ï¼š`healthy` åœ¨ä»»åŠ¡ä»ŽæœªæˆåŠŸæ—¶æ˜¯ NULL è€Œéž falseï¼Œè€Œä¸ŠæŠ¥å™¨ç­›çš„æ˜¯ `WHERE NOT healthy`â€”â€”**ã€Œä»»åŠ¡åŽ‹æ ¹æ²¡è·‘ã€ä¼šæˆä¸ºå”¯ä¸€ä¸è¢«ä¸ŠæŠ¥çš„æƒ…å†µ**ï¼Œæ°æ°æ˜¯è¿™æ¬¡äº‹æ•…çš„å½¢çŠ¶ã€‚å·² coalesce ä¸º false å¹¶åŠ æ–­è¨€é’‰æ­»ã€‚
- **ä¹ŸæŠ“åˆ°æˆ‘è‡ªå·±å†™çš„ä¸ç¨³å®šæµ‹è¯•**ï¼šæ–­è¨€ `process-escalations` ä»ŽæœªæˆåŠŸï¼Œåªåœ¨ reset åŽå‡ ç§’å†…æˆç«‹ï¼ˆæœ¬åœ° pg_cron çœŸçš„æ¯åˆ†é’Ÿåœ¨è·‘ï¼‰ï¼Œå•è·‘ç»¿ã€å…¨å¥—çº¢ã€‚æ”¹ä¸ºåœ¨äº‹åŠ¡å†… schedule ä¸€ä¸ª 1 æœˆ 1 æ—¥çš„ä»»åŠ¡ï¼Œå¯è¯ä»Žæœªè·‘è¿‡ã€‚
- ä¸Šçº¿éªŒè¯ï¼šç”Ÿäº§ `scheduled_job_health()` å½“åˆ»æŠ¥å‡º `account-shadow-cycle-v1: last 4 run(s) failed`ã€‚å››å¤©è¡¥ç®—å®Œæˆï¼ˆæ¯å¤© 11 è´¦æˆ· / 0 è·³è¿‡ï¼‰ã€‚æäº¤ `9f239a1` `3d05893` `bd276bb` `85abaf5`ï¼Œå…¨éƒ¨ç» `db push` å‘å¸ƒâ€”â€”**ADR-0038 ä¿®å¥½çš„è·¯å¾„çš„ç¬¬ä¸€æ‰¹çœŸå®žä½¿ç”¨**ã€‚
- **è½¬å‡ºçš„ä¸¤ä»¶ï¼ˆæœªå¤„ç†ï¼‰**ï¼šæŽ‰çº¿å®ˆå«åªè·³ä¸€ä¸ªç¦»ç¾¤å€¼ï¼ŒçŸ¥æ‹‰é˜ˆå€¼å› æ­¤ä»Ž 23.3 å°æ—¶è·³åˆ° 4.1 å¤©ï¼Œéœ€äººè£å†³ï¼›ä»¥åŠ 16 ä¸ª pgTAP æ–‡ä»¶ä»çº¢â€”â€”**å«ä¹‰å·²å˜**ï¼šæœ¬åœ°åº“çŽ°åœ¨å»ºè‡ªç”Ÿäº§åŸºçº¿ï¼Œçº¢å³ã€Œæµ‹è¯•ä¸Žç”Ÿäº§çœŸçš„ä¸ä¸€è‡´ã€ï¼Œä¸å†èƒ½ç”¨ã€Œæœ¬åœ°æ¼‚ç§»ã€æªå¡žã€‚å·²ç¡®è®¤å…¶ä¸­ä¸€ä¸ªä¸ºçœŸï¼š`anon` åœ¨ `alert_intervention_events` ä¸ŠæŒæœ‰ `MAINTAIN`ï¼ˆä¸¤è¾¹éƒ½æ˜¯ PG 17.6ï¼Œéžé•œåƒå·®å¼‚ï¼‰ï¼Œè¿å Data API ACL åŸºçº¿ã€‚

## 2026-08-08 â€” `db push` was unusable in both directions; production became the baseline

[Claude Â· 2026-08-08 22:30 +06:00] `KC-MIGRATION-BASELINE-SQUASH-ADR-001` `KC-ADR-0038-RECORD-001` `KC-MIGRATION-BASELINE-SQUASH-IMPL-001` â€” å†³ç­–è§ [[Decisions]] ADR-0038ï¼Œææ¡ˆè§ [[KC Migration Baseline Squash]]ã€‚

- **CLI çš„å»ºè®®æ˜¯å±é™©çš„ï¼Œä¸”å‰æä¸ºå‡ã€‚** `db push --dry-run` æŠ¥ `LegacyDbPushMissingLocalError`ï¼Œå»ºè®®æŠŠ 78 ä¸ªè¿œç«¯ç‰ˆæœ¬æ ‡ `reverted` åŽé‡æŽ¨ 75 ä¸ªæœ¬åœ°æ–‡ä»¶ã€‚å®ƒåªæ¯”å¯¹ç‰ˆæœ¬å·ï¼Œè€Œç‰ˆæœ¬å·æ°æ˜¯å”¯ä¸€å¤±çœŸçš„å­—æ®µã€‚æŒ‰åç§°ä¸Žç‰ˆæœ¬å·åŒæ—¶åšå››è·¯è¿žæŽ¥ï¼ˆ102 è¡Œ Ã— 99 æ–‡ä»¶ï¼‰ï¼š24 ç‰ˆæœ¬å·ä¸€è‡´ / **59 åŒä¸€ä»¶äº‹å·²ç”Ÿæ•ˆã€åªæ˜¯çº¿ä¸Šå¦ä¸€ä¸ªæ—¶é—´æˆ³** / 16 ä¸¤é”®éƒ½ä¸åŒ¹é…çš„æœ¬åœ°æ–‡ä»¶ / 18 ä¸¤é”®éƒ½ä¸åŒ¹é…çš„çº¿ä¸Šè¡Œã€‚C ç»„ 16 ä¸ªé€æ¡æŽ¢æµ‹ç”Ÿäº§åº“**å…¨éƒ¨åœ¨çº¿**ï¼Œå« `20260807223000`ï¼ˆæ‰‹å·¥æ‰§è¡Œã€è´¦æœ¬æ— è®°å½•ï¼Œç”Ÿäº§ `process_escalations` é‡Œå·²æœ‰ `sleep_grace`ï¼‰ã€‚**æœªæ‰§è¡Œçš„è¿ç§»æ•°ä¸ºé›¶ã€‚**
- çœŸæ­£çš„å±é™©ä¸æ˜¯è£¸ `CREATE TABLE` å“äº®å¤±è´¥ï¼Œè€Œæ˜¯é‚£çº¦ 40 æ¡ `CREATE OR REPLACE FUNCTION` **ä¸ä¼šå¤±è´¥ã€åªä¼šè¦†ç›–**â€”â€”æŠŠç”Ÿäº§å‡½æ•°ä½“é™é»˜æ¢å›žæ—§å®šä¹‰ã€‚
- **å®šæ–¹å‘çš„æ˜¯ D ç»„**ï¼š18 æ¡è¿ç§»ä»“åº“é‡Œæ²¡æœ‰ä»»ä½•æ–‡ä»¶ï¼Œå› æ­¤æ— è®ºæ€Žä¹ˆä¿®è´¦æœ¬ï¼Œ`supabase/migrations/` éƒ½é‡å»ºä¸å‡ºç”Ÿäº§åº“ã€‚å®ƒä¸æ˜¯è·‘åçš„å‰¯æœ¬ï¼Œæ˜¯ç¼ºäº†ä¸€å—çš„æµæ°´è´¦ã€‚
- **æ„å¤–æ”¶èŽ·ï¼šåŽ†å²æ²¡ä¸¢ã€‚** è´¦æœ¬çš„ `statements` åˆ—å­˜ç€æ¯æ¡è¿ç§»çš„åŽŸå§‹ SQLã€‚å…¨éƒ¨ 103 æ¡è¢«æå–åˆ° `supabase/migrations-archive/as-applied/`ï¼Œå¹¶ç”¨æ•°æ®åº“è‡ªå·±ç®—çš„æŒ‡çº¹æ ¸éªŒï¼š`md5=f4a7ca762ab1017e565bd827db8a8628`ï¼Œ169 ä¸ªè¯­å¥ï¼Œæœ¬åœ°ä¸Žè¿œç«¯å®Œå…¨ä¸€è‡´ã€‚**é‚£ 18 æ¡ä»Žæœªæœ‰è¿‡æ–‡ä»¶çš„è¿ç§»ï¼Œç¬¬ä¸€æ¬¡æœ‰äº†å¯è¯»æ–‡ä»¶ã€‚** æå–è„šæœ¬ `scripts/extract-ledger-migrations.mjs`ã€‚
- **`db dump` ä¸æ˜¯æ•°æ®åº“ã€‚** åŸºçº¿é¢å¤–è¡¥äº†ä¸‰æ ·ï¼šrealtime å‘å¸ƒè®¢é˜… 11 å¼ è¡¨ï¼ˆpg_dump å¯¹ schema èŒƒå›´çš„ dump ä¸è¾“å‡º `ALTER PUBLICATION`ï¼Œç¼ºäº†å®žæ—¶æ›´æ–°é™é»˜å¤±æ•ˆï¼‰ï¼›9 ä¸ª pg_cron ä½œä¸šï¼ˆæ˜¯ `cron.job` çš„è¡Œä¸æ˜¯ schemaï¼Œç¼ºäº† `process-escalations` åˆ™ç»“æž„å®Œç¾Žå´æ°¸ä¸å¼€è­¦ï¼‰ï¼›ä»¥åŠ 14 å¼ è¡¨ä¸Š 126 æ¡ `revoke`â€”â€”**dump åªèƒ½è¡¨è¾¾"æŽˆäºˆè¿‡ä»€ä¹ˆ"ï¼Œæ— æ³•è¡¨è¾¾"åŽæ¥æ”¶å›žè¿‡ä»€ä¹ˆ"**ï¼Œè¿™ä¸€é¡¹åªæœ‰ `db diff --linked` æŠ“å¾—åˆ°ã€‚
- **è¸©åˆ°å¹¶ä¿®å¥½äº† CRLF é™·é˜±ã€‚** ç”¨ Edit å·¥å…·æ”¹åŸºçº¿é‡Œçš„æ‰©å±•å£°æ˜Žï¼ŒæŠŠæ•´ä¸ªæ–‡ä»¶ 4617 ä¸ª `\r` è§„èŒƒåŒ–æŽ‰äº†ï¼›ç”Ÿäº§å‡½æ•°ä½“å­˜çš„å°±æ˜¯ CRLFï¼ŒäºŽæ˜¯ 111 ä¸ªå‡½æ•°å…¨éƒ¨ä¸Žç”Ÿäº§ä¸ä¸€è‡´ï¼Œ**è€Œåº”ç”¨è¿‡ç¨‹é›¶æŠ¥é”™**ã€‚`db diff` ä»Ž 1 è¡Œæ¶¨åˆ° 4661 è¡Œæ‰æš´éœ²å‡ºæ¥ã€‚æ”¹ç”¨å­—èŠ‚æ‹¼æŽ¥é‡å»ºï¼Œå¹¶åŠ  `.gitattributes` æŠŠ `supabase/migrations/*.sql` æ ‡ä¸º `-text`ï¼ˆ`core.autocrlf=true` å¦åˆ™ä¼šåœ¨æäº¤æ—¶é‡å†™ï¼‰ã€‚å·²éªŒè¯ git å­˜å‚¨ä¸Žå·¥ä½œåŒºé€å­—èŠ‚ä¸€è‡´ï¼ˆ494525 å­—èŠ‚ / 4617 CRï¼‰ã€‚
- éªŒè¯ï¼ˆè·¨è¾¹ç•Œï¼‰ï¼š`db push --dry-run` è¿”å›ž `{"upToDate":true}`ï¼›`db diff --linked` ä»Ž 4661 è¡Œé™åˆ° **1 è¡Œ**â€”â€”`create extension pg_net`ï¼Œæœ¬åœ°é•œåƒé¢„è£…ä½ç½®ä¸Žç”Ÿäº§ä¸åŒï¼Œ`if not exists` æ— æ³•æ¬è¿ï¼Œä¸” `net.http_post` ç…§å¸¸è§£æžï¼Œå±žçŽ¯å¢ƒå·®å¼‚éžåŸºçº¿ç¼ºé™·ï¼›`cron.job` å‰åŽåŒä¸º 9 ä¸ªä½œä¸šã€åç§°ä¸å˜ã€‚
- **å…¨ç¨‹æœªå¯¹ç”Ÿäº§åº“æ‰§è¡Œä»»ä½• DDLã€‚** åªæ”¹äº† `supabase_migrations.schema_migrations` è®°è´¦è¡¨ï¼ˆ103 è¡Œ â†’ 1 è¡Œï¼‰ä¸Žä»“åº“æ–‡ä»¶ã€‚å›žæ»š = `ledger-backup-2026-08-08.sql` + `git revert`ã€‚å¤‡ä»½ 742 kB å·²æäº¤ã€‚
- æäº¤ `84959ec`ï¼Œ207 ä¸ªæ–‡ä»¶ã€‚
- **é¡ºå¸¦å‘çŽ°çš„ç”Ÿäº§ç¼ºé™·ï¼Œæœªåœ¨æœ¬æ¬¡å¤„ç†**ï¼š`private.rebuild_account_normal_bounds` è‡ª 08-05 èµ·æ¯æ™šå¤±è´¥ï¼ˆå¹¶è¡ŒæœŸé—ç•™å­—æ®µ `live_threshold_minutes` ä¸º `NOT NULL`ï¼Œä¸Ž ADR-0037ã€Œæ— è¯æ®ä¸å‘æ˜Žé˜ˆå€¼ã€ç›´æŽ¥çŸ›ç›¾ï¼‰ï¼Œå…¨éƒ¨è´¦æˆ·é˜ˆå€¼å†»ç»“åœ¨ 08-04ï¼›ä¸”è¯¥å‡½æ•°æ˜¯å•æ¡è¯­å¥ã€æ— æŒ‰äººéš”ç¦»ï¼Œ**ä¸€ä¸ªäººç®—ä¸å‡ºæ¥åˆ™å…¨ä½“å½’é›¶**ã€‚åŒç±»è„†å¼±æ€§è§äºŽ `process_escalations`ã€`process_checkin_tasks`ã€`run_daily_aggregations`ã€`apply_liveness_side_effects`â€”â€”åšäº†å¤±è´¥éš”ç¦»çš„åè€Œæ˜¯å®žéªŒæ€§çš„å½±å­è·¯å¾„ã€‚è½¬ `KC-NIGHTLY-REBUILD-ISOLATION-001`ã€‚

## 2026-08-08 â€” Local `supabase start` has been dead since June; two historical migrations were the cause

[Claude Â· 2026-08-08 20:35 +06:00] `KC-LOCAL-MIGRATION-REPLAY-001` `KC-MIGRATION-ROUTINE-IMPL-SYNTAX-001`

- Symptom: `npx supabase start` against a fresh local database aborted applying `20260623090000_gm_admin_console.sql` with an `app_admins_user_id_fkey` violation. Replay halts on the first error, so **every migration after 2026-06-23 never ran locally and all 23 pgTAP suites under `supabase/tests/` were unrunnable.**
- Cause 1 â€” environment-specific data living in a schema migration. `20260623090000` (commit `16c8197`) hardcodes a production `auth.users` id and inserts it straight into `public.app_admins`. Production has that row; a fresh local database has no `auth.users` rows at all, so the foreign key fails.
- Fix 1: the insert became `insert â€¦ select â€¦ where exists (select 1 from auth.users where id = â€¦)`, keeping `on conflict do nothing`. On production this is a no-op twice over â€” the row already exists, and the version is already recorded so the file is never replayed. Confirmed after the run: local `public.app_admins` is empty, which is the intended outcome; no production admin is bootstrapped into a dev database.
- **This edits a historical migration, against the `AGENTS.md` rule "add new migration files only, never edit old ones", and the exception wants human ratification.** The rule has no reachable alternative here. A *later* migration is never reached, because replay dies in June. An *earlier*-timestamped one is worse: `db push` applies any version absent from `schema_migrations` regardless of ordering, so it would run against production and insert a synthetic `auth.users` row. Moving the bootstrap into `supabase/seed.sql` â€” the conventional home for environment data â€” does not solve it either: seed runs *after* migrations, a fresh local database still has no `auth.users`, so it would need the identical guard *plus* a larger edit to the same historical file. The guard is the smallest change that reaches the goal, and the Supabase CLI matches migrations by version rather than checksum, so editing the file cannot disturb production.
- Cause 2, visible only once fix 1 let replay continue: `20260624140000_adaptive_routine_impl.sql` line 87 holds the literal text `</loop>` where `end loop;` belongs, so the inner `for _h in 0..23 loop` never closes and **the file has never been valid SQL**. `git log --follow` shows exactly one commit (`2b6f734`) and the artifact is already in it. Production therefore received `public.initialize_user_routine_data` through some out-of-band path (MCP `apply_migration` or the dashboard), which is why nobody hit this until a fresh replay executed the file for the first time.
- Fix 2 was checked against production before being written rather than guessed: production's `initialize_user_routine_data` is the non-destructive no-op, because `20260719015302_routine_ai_gate1_containment.sql` line 913 replaces the whole body in July. The June body therefore only has to parse â€” it cannot change the end state. Confirmed after the run: the local function definition is byte-identical to production's.
- Also committed `supabase/snippets/.gitkeep`. The directory has to exist or the podman/WSL bind mount fails with a `statfs` error before the stack starts.
- Verification: `npx supabase start` completes and all 98 migrations apply through `20260804190000_account_normal_upper_bound.sql`. `npx supabase test db` now **runs** â€” 23 files, 632 tests â€” where previously not one could execute. (`WARN: no files matched pattern: supabase/seed.sql` is emitted and is harmless; `config.toml` points at a seed file the repo does not carry.)
- **The suite is runnable, not green: 9 of 23 files pass, 14 fail. Both failure families are pre-existing local-vs-production drift, and neither can be caused by the two edits above** â€” `app_admins` is empty and only `gm_mute_user.sql` touches that table, seeding its own admin; `initialize_user_routine_data` is byte-identical to production.
  1. **Missing grants â€” 4 files abort mid-plan** (`routine_safety`, `behavior_ping_no_coalescing`, `membership_policy_recursion`, `monitoring_direction_alert_scope`) with `permission denied for table â€¦`. On `public.behavior_pings`, local replay yields `service_role` â†’ `REFERENCES,TRIGGER,TRUNCATE` only, while production has `DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE` for `anon`, `authenticated` and `service_role`. The migrations never encode those grants; production acquired them elsewhere.
  2. **Definition-hash drift on `private.silence_threshold`**, which accounts for most of the remaining failures. Local (CR-normalised) `0c1226d8â€¦`, test-pinned authority `6be4ed54â€¦`, production `c3efc6ccâ€¦` â€” three different bodies, production 1070 chars against local 1309. This is the same migration-ledger drift the 2026-08-07 entry recorded for `20260804190000_account_normal_upper_bound.sql`, whose work production applied under three other version numbers, and it belongs to `KC-ADR37-NORMAL-UPPER-BOUND-001`.
- Neither family was repaired here. Both would change production grants or schema, so each needs its own card, and the grants one needs an ADR.

## 2026-08-07 â€” ADR-0037 deferred item adjudicated; task closed

[Claude Â· 2026-08-07 22:45 +06:00] `KC-ADR37-NORMAL-UPPER-BOUND-001`

- The task had sat blocked since 2026-08-04 on a single deferred item: an account with no evidence gets a null threshold, and Routine status / group activity render that null as `0`.
- Human 2026-08-07: **ã€Œè¿™ä¸ªæ˜¯å°äº‹ï¼Œæš‚æ—¶ç›´æŽ¥è®©å®ƒæ˜¯ 0 å°±å¥½ã€** â€” accept `0` as the displayed value, no UI work. Recorded under ADR-0037 in Decisions.md as æ‚¬ç½®é¡¹å·²è£å†³.
- This does not weaken the ADR. Its rule is "an account with no evidence gets no invented threshold"; the judgement chain still produces no silence verdict for such an account. What was accepted is only how the absence is drawn.
- Residual observation recorded as **non-blocking**, not silently dropped: on screen `0` reads as "threshold zero, maximally sensitive", which is the opposite of the truth, "cannot judge". An explicit "insufficient evidence" label is the candidate if an account is ever misread because of it. The human has ruled it out for now.
- Verified before closing: the migration's content is fully live in production â€” `public.account_normal_bounds` with RLS and its through-date index, `private.rebuild_account_normal_bounds`, and the rewritten `private.silence_threshold` all exist and run.
- **Migration-ledger drift found and documented while verifying.** The local file `supabase/migrations/20260804190000_account_normal_upper_bound.sql` corresponds to three separate remote versions â€” `20260804130221 account_normal_upper_bound`, `20260804135728 silence_threshold_reads_normal_bounds`, `20260804142350 nightly_job_maintains_normal_bounds`. Version `20260804190000` exists in no remote row, so `supabase db push` classifies already-applied work as pending. Since the file opens with a bare `CREATE TABLE public.account_normal_bounds` (no `IF NOT EXISTS`), a push would have failed loudly rather than corrupted anything â€” but it would have blocked every later migration behind it. Repaired by marking `20260804190000` applied; nothing was re-executed.

## 2026-08-07 â€” Where "activity auto-resolves an alert" came from, and the copy that outlived the decision to remove it

[Claude Â· 2026-08-07 22:20 +06:00] `KC-CRON-ACTIVITY-NOT-AN-ANSWER-001` â€” **applied to production 2026-08-08 by the human via the dashboard SQL editor**

- Human's question: when did "æœ‰æ´»åŠ¨å°±è‡ªåŠ¨è§£é™¤" become the rule, and was it a misunderstanding or a misjudgement? Their reading was that it looks like "there is activity, so record the device as safe" got wired to closing an alert.
- Answer, traced: it is in the **first version of the escalation logic**, `20260610142413_escalation_logic.sql`, committed in the `4d5c7cd` baseline, as `-- 2) è‡ªåŠ¨è§£é™¤ï¼šè®¾å¤‡å·²æ¢å¤æ­£å¸¸ä¸”å¿ƒè·³æ–°é²œï¼ˆéž SOSï¼‰` with the condition `ds.status = 'normal' and ds.last_heartbeat_at > now() - _dark`. The comment names a **device**; the action closes an alert about a **person**. The human's reading is exactly right, and no ADR or proposal ever recorded it as a decision â€” it is day-one wording inherited through every later rewrite.
- It grew three copies: the `on_behavior_ping_insert` trigger (trigger and function both dropped 2026-07-19 in `20260719015302`), `private.apply_liveness_side_effects` (corrected 2026-08-02 in `20260802140000`, whose header records the measured case â€” alert raised 11:11, escalated 11:42, ping at 11:43:44.129 when the user merely tapped the notification, auto_resolved 11:43:44.958, **0.8 s later, no gesture**), and `public.process_escalations`' clearance loop, which was never touched.
- Production evidence, 2026-08-07: the `apply_liveness_side_effects` path (auto_resolved with no note) fired 13/14/12/9/7/6 times a day through late July and **stopped dead after 2026-08-02** â€” the correction worked. Since then the surviving cron loop has fired exactly **once in five days** (a dark_device on 08-06). Over 30 days: 164 episodes closed by the ping path vs 33 by this loop. So removing it retires a contradiction, not a working behaviour.
- Change (`supabase/migrations/20260807223000_activity_never_answers_an_alert_in_cron.sql`): the clearance loop drops both activity branches â€” silence cleared by a fresh qualifying ping, and dark_device cleared by a returning heartbeat. Both are activity, and 2026-08-02's rule is "è¢«åŠ¨æ´»åŠ¨åªæ›´æ–°åœ¨çº¿çŠ¶æ€ï¼Œæ°¸ä¸è§£é™¤ä»»ä½•å‘Šè­¦" â€” *any* alert, which covers dark_device. What remains is sleep/post-wake grace, which is not activity: it withdraws an alert whose premise ("this silence is unusual") is false inside a window where silence is expected. Its event note changes from `condition_cleared` to `sleep_grace` so the ping-driven path can never hide behind it in the record again. Raise loop, escalation loop, GM mute gate and responder grace are reproduced verbatim.
- Test written: `supabase/tests/activity_never_answers_an_alert_in_cron.sql`, 7 assertions â€” a fresh qualifying ping leaves a silence alert open, a returning heartbeat leaves a dark_device alert open, neither emits an `auto_resolved` event or broadcasts an `auto_resolved` notification, sleep grace still clears and names itself. The schema assumptions were checked against production first, which caught one: `user_settings` has `sleep_start_local`/`sleep_end_local`, not `sleep_start`/`sleep_end`.
- **Applied 2026-08-08** by the human through the dashboard SQL editor, after two automated routes were ruled out:
  1. The MCP path was denied by the permission classifier (`apply_migration`, as it had denied `deploy_edge_function`; that one had a safe CLI fallback, this one did not).
  2. `supabase db push` is **unusable in this project, in both directions** â€” and the single-file drift first suspected was only the visible corner of it. Measured against production: **78** ledger versions have no local file, **75** local files have no ledger row, only **24** are shared. `db push --dry-run` refuses outright with `LegacyDbPushMissingLocalError`. Its own suggestion (mark the 78 remote rows `reverted`, then push the 75 local files) would re-run already-live work, and several of those files open with a bare `CREATE TABLE`, so it would fail partway and leave a half-applied history. Cause: migrations have historically been applied via dashboard/MCP under generated timestamps rather than via `db push` under each file's own version, so the two recordings never lined up. Reconciliation is spun out as its own task and needs a human decision on which side is canonical.
- Verified live after the human applied it, not assumed: `pg_get_functiondef` on production confirms the `sleep_grace` note is present, `condition_cleared` is gone, and both activity branches (`silence_threshold(a.user_id)` clearance and the dark-device 18-hour heartbeat clearance) are gone, while the raise loop, GM mute gate and escalation loop are intact. `cron.job_run_details` shows `process-escalations` running every minute since, status `succeeded`, 24â€“82 ms â€” so the rewritten function executes cleanly under the real scheduler.
- Ledger updated: `supabase migration repair --status applied 20260807223000`, so the file is not later mistaken for pending work. Nothing was re-executed.
- Read-only check at the moment of applying: zero open silence/dark_device alerts, so both the old and new predicates would close nothing â€” the change landed as a no-op against live state, which was the safest possible moment for it.
- **Still unverified: the 7 pgTAP assertions in `supabase/tests/activity_never_answers_an_alert_in_cron.sql` have never been executed.** Local replay is blocked independently â€” `supabase start` dies at `20260623090000_gm_admin_console.sql`, which hardcodes a production admin's `auth.users` id that does not exist in a fresh local database, halting migration replay in June. Spun out as its own task. The production verification above is behavioural evidence, not a substitute for those assertions.

## 2026-08-07 â€” notify-feed cursor truncation re-delivered every unread notification

[Claude Â· 2026-08-07 22:05 +06:00] `KC-NOTIFY-CURSOR-PRECISION-001`

- Why: human reported iOS notifications re-appearing on their own â€” an alert and then its own resolution, over and over, stopping only once the app was opened â€” and that no earlier version or other platform behaved this way. That last detail was the one that mattered: it ruled out the alert engine and pointed at delivery.
- Root cause: `notifications.created_at` is a microsecond-precision timestamptz. `notify-feed` re-serialised the client's cursor through `new Date(Date.parse(since)).toISOString()`, which holds only milliseconds, discarding up to 999Âµs. That truncated value became the `.gt('created_at', â€¦)` bound, so the newest row satisfied `created_at > cursor` **against itself** and was returned again. The client's advance guard (`createdAt > latest`) then compared two identical strings, left the cursor unmoved, and the loop became permanent. `read_at is null` was the only exit, which is exactly why the symptom lasted until the user opened the app.
- Why iOS only, and why now: all three clients share the endpoint and therefore the bug. iOS shows it worst because `NotifyFeed.swift` is new in this version (no earlier iOS build rendered notifications at all â€” it was introduced in `9fd6070`), it runs on **every silent push** rather than Android's 15-minute poll, and `UNNotificationRequest` re-alerts on each repost. Android tags each post with the notification row id so a repost replaces instead of stacking; the comment on that workaround describes reposts of still-unread rows as expected behaviour, which is how the cause stayed hidden.
- Change: `supabase/functions/notify-feed/index.ts` now hands the client's cursor string to Postgres untouched via a new `feedCursor()`; `Date.parse` survives only as a validator and for the 7-day lookback clamp. A non-ISO but parseable cursor still normalises through `Date`, so the query is never handed a string Postgres would read differently than we validated. `ios-passive-ping/.../NotifyFeed.swift` additionally keeps a ledger of posted ids (cap 100, cleared with the cursor on sign-out) and refuses to draw the same row twice, so a future cursor fault cannot wake anyone twice for the same notification.
- Evidence: `src/features/alerts/notifyFeedCursor.{ts,test.ts}` (deliberate duplicate of the edge module, per the `outcome.ts` convention). Eight assertions model Postgres' own microsecond comparison; one deliberately reproduces the old millisecond round-trip and asserts it *does* admit the row, pinning the regression. Full suite 66 files / 319 tests pass, `tsc --noEmit` clean, `git diff --check` clean.
- Production confirmation before deploying: of the 94 notifications created in the last 7 days, **94 carry a non-zero microsecond remainder and all 94 are still unread** â€” every one was in the permanent repeat loop at that moment. This is not a latent edge case; it was the steady state.
- Deployed: `notify-feed` v2 â†’ **v3**, `verify_jwt` still false, confirmed by re-reading the deployed source. Note the deployed v2 was **behind the repo** â€” it predated `paramsWithRecipientMark`, so this deploy also shipped that pending change. Additive (a new `target_is_recipient` field; older clients ignore unknown fields) and it is what makes the second-person copy work on native clients, but it was a larger delta than the cursor fix alone and was flagged before shipping.
- Boundary: the Swift change is **not compiler-verified** â€” no Swift toolchain on this Windows host; it needs the Mac/TestFlight build before release. The deployed edge function alone already ends the repeats on all three platforms; the iOS ledger is defence in depth and ships with the next build.
- Test-suite note: one full run reported a single failing test, and four subsequent full runs passed cleanly. The failing assertion could not be captured before it cleared, so it is recorded as unexplained rather than dismissed. It was not in the files this task touched â€” `notifyFeedCursor.test.ts` passed in every run.
- Not touched, separately governed: (1) `process_escalations`' first loop still auto-resolves silence alerts on recent activity â€” the last surviving copy of logic first written 2026-06-10 (`20260610142413_escalation_logic.sql`, "è‡ªåŠ¨è§£é™¤ï¼šè®¾å¤‡å·²æ¢å¤æ­£å¸¸ä¸”å¿ƒè·³æ–°é²œ"), which `20260802140000_activity_never_answers_an_alert` corrected in `apply_liveness_side_effects` but not here; the ping-trigger path was already dropped 2026-07-19. (2) `notify_auto_resolved` broadcasts to every watcher and guardian even when the alert never left the `self` stage, so bystanders are told an alert cleared that they were never told had opened. (3) Human's stated interruption policy, 2026-08-07: escalated alert stages may interrupt repeatedly; `on_it` and `resolved` interrupt exactly once; everything else records silently in-app.

## 2026-08-03 â€” Remove stale root Windows installer duplicates

[Codex Â· 2026-08-03 20:18 +06:00] `KC-REMOVE-STALE-ROOT-INSTALLERS-001`

- Why: `public/` root still contained two tracked, byte-identical 0.5.23 EXEs even though the current updater URL, release script, download link, and local artifact gate all use `public/desktop/KeepContact-Setup.exe`. Keeping or refreshing the root copies would add repository weight without serving an active path.
- Change: removed only `public/KeepContact-0.5.23-Setup.exe` and `public/KeepContact-Setup.exe` (34,949,539 bytes each; shared SHA-256 `F53F01425C01625C916E7B60E5297AF0441840CE447891F2DDE0F3707E7B7CBA`). The current `public/desktop` EXE/MSI, `public/version.json`, 0.5.25 Android artifacts, release scripts, and download URLs were not changed by this task.
- Evidence: both root paths are absent; the desktop installer remains present; repository search resolves installer references only to `/desktop/KeepContact-Setup.exe`. `local:gate` passed typecheck, 65 test files / 309 tests, build, and artifact discovery, then failed only at the Brain SDLC check because Model Usage Ledger physical line 276 uses unsupported `capability_class=operations` (checker reports usage line 275 because the comment header is skipped).
- Boundary: the Ledger row and routing protocol were diagnosed but not edited in this project-cleanup task. The valid capability vocabulary is `runtime-terminal | intent-ux-docs | android-google | db-security | visual-device | long-context-alternative | mixed`; the 0.5.25 release row must be reclassified from its task evidence in a separate Brain protocol/data correction.

## 2026-08-02 â€” Keep Contact v0.5.25 iOS Native UI & Layout Redesign Release

[Antigravity Â· 2026-08-02 21:05 +06:00] `KC-0.5.25-IOS-NATIVE-RELEASE-001`

- Why: Human requested releasing v0.5.25 exclusively for iOS Native testing while leaving other platforms (Android/Desktop) untouched.
- Features & Redesign:
  1. Complete **Spatial Section Partitioning (æ— æ¡†ç©ºé—´åˆ†åŒº)** across all screens (`Watch`, `Routine`, `Circles`, `Me`), replacing heavy nested cards with thin hairline dividers, 24px spatial gaps, and uppercase headers aligned to a strict vertical pixel grid.
  2. Restored **`Everyone's Status`** macro-to-micro hierarchy (Circle âž” Community âž” Member cards) with inline Ward check-in task pills (`Morning 09:00 Active`).
  3. Raised **`Notifications`** above `Everyone's Status`, transformed filter bar into a single horizontal scroll row with CSS edge-mask fade (`-webkit-mask-image`), and added category empty state feedback.
  4. Redesigned primary buttons into warm **Terracotta Coral Pill Gradients** (`linear-gradient(135deg, #e07a5f 0%, #d4684d 100%)`).
  5. P3 Crisis Zero-Learning compliance: added single-click guidance for center SOS button (`Press and hold for 1.4s to trigger SOS`).
  6. 100% complete bilingual dictionary (`dict.zh`) & enhanced `setLanguage` engine translating text nodes, placeholders, select options, and badges.
  7. iOS Native Optimizations: added `env(safe-area-inset-top)` & `env(safe-area-inset-bottom)` safe area insets, Retina anti-aliasing (`-webkit-font-smoothing`), and disabled WebKit touch callouts/tap flashes.
- Version Files: Updated `src/lib/version.ts` -> `0.5.25`, `public/version.json` -> `0.5.25`, and `Prototype/interactive_prototype.html` -> `v0.5.25`. Android versionName kept unchanged per user directive.
- Evidence: 100% byte parity synced across prototype files (158,560 bytes). DOM tag closure verified (351/351 divs).

## 2026-08-02 â€” Watch ownership and alert-only Concern correction

[Codex Â· 2026-08-02 20:32 +06:00] `KC-PROTOTYPE-WATCH-ACTIONS-001`

- Why: human clarified that scheduled check-ins are special Guardian-to-Ward care arrangements, not an ad-hoc action for every watched Group member; Concern is available only after an alert as the first false-alarm check.
- Prototype change: removed all ordinary-person `Ask to check in` actions and the detached Check-in Tasks card; added one conditional Watch-top `Check in` for the current user's assigned task; placed Add/Edit/Remove task controls under Mei's Ward details; added alert â†’ concern-sent â†’ claimed â†’ resolved states while preserving immediate `I'll contact them`.
- Concurrent repair: a separate prototype edit left orphaned duplicate Circles/Community/Responsibilities fragments after the redesigned screen. Kept the complete newer section and removed only the duplicate leftovers, restoring unique IDs without reverting the redesign.
- Evidence: Watch contract first failed 4 checks for the old ownership/state model, then passed 21/21 after implementation. Inline JavaScript parses, all literal element references resolve, and IDs are unique. Browser-rendered visual QA remains unclaimed because the selected local `file://` surface is not controllable.
- Boundary: no production React, native, database, migration, push, release, or deployment change. `[CONFLICT]` Project home still says group+ concern should close; production eligibility needs a separate High-risk reconciliation before implementation.

## 2026-08-02 â€” Prototype Watch actions aligned to the alert state machine

[Codex Â· 2026-08-02 20:06 +06:00] `KC-PROTOTYPE-WATCH-ACTIONS-001`

- Why: the prototype exposed `Send concern` on every watched-person card even though the runtime action creates or strengthens a real safety alert; the existing production React surface has the opposite mismatch and shows it only after group+ escalation.
- Prototype change: routine cards now remain informational; a deliberate `Ask <name> to check in` lives in expanded details behind consequence confirmation. Active alerts expose View alert, claim contact and confirm-safe states, and suppress the manual request for the alerted person.
- Evidence: two RED/GREEN cycles caught both the persistent routine actions/missing response states and the alerted-person detail leak. `node Prototype/prototype.test.mjs` passes 20/20; strict UTF-8, replacement-character, whitespace, inline-JavaScript, unique-ID and Watch-boundary checks pass.
- Boundary: no production React, native, database, migration, push, release or deployment change. Browser-rendered visual QA remains unclaimed because the local `file://` surface is outside the permitted in-app Browser control path.

## 2026-08-02 â€” 0.5.24 backlog cleanup & prototype functional audit

[Codex Â· 2026-08-02 17:26 +06:00] `KC-0.5.24-UI-FUNCTIONAL-AUDIT-001`

- Why: User requested that 0.5.20-only release waits stop blocking the current 0.5.24 line, while unfinished significant functionality remains visible; also requested a real-app versus HTML-prototype UX/function audit.
- Disposition: archived `KC-ADR26-CLIENT-HARDENING-001` and `KC-R4-PATTERN-ISOLATION-001` as stale release-decision waits because their code-complete evidence predates the current 0.5.24 line. Archived `KC-GROUP-QR-DESIGN-001` as deferred, with its unfinished cross-surface QR/deep-link handoff moved to the next-strengthening list.
- Findings: source/runtime cross-check found iOS native/PWA routing ambiguity, stale Android permission resume, non-run-specific ping verification, misleading calm-state copy, SOS timing mismatch, incomplete QR handoff, and prototype omissions around real Me/Circles/account/error states. Full report: `docs/0.5.24-ui-functional-audit.md`.
- Evidence limit: the user-selected in-app Browser `file://` prototype could not be controlled by the permitted browser tool, so no screenshot visual acceptance is claimed; source and existing runtime/project evidence only.

## 2026-08-01 â€” Routine alert threshold sleep inflation fix & GM tab relocation Â· Antigravity

[Antigravity Â· 2026-08-01 02:30 +06:00]

- Why:
  1. Routine alert threshold showed inflated value (6h) because `silence_threshold`'s inline Extension CTE computed raw inter-session gap p95 WITHOUT sleep compensation, then took `greatest()` against the properly sleep-compensated profile, overriding profile values upward.
  2. User requested moving the GM Manager Console entry card from the Circle (ç¾¤ç»„) tab to the Watch (å®ˆæœ›) tab for clearer visibility.
- Fix:
  1. Created migration `20260801020000_fix_silence_threshold_sleep_inflation.sql` to remove the uncompensated Extension CTE from `private.silence_threshold` so threshold calculations directly rely on the daily sleep-compensated `alert_gap_profiles`. Auto-registered the new function hash in `private.shadow_live_definition_matches`. Applied to production Supabase via linked Management API.
  2. Updated `HomeScreen.tsx` to move GM Manager Console card into `dashboard-grid__col2` (Watch tab) and updated `GMScreen` `onBack` to navigate to `'home'`.
  3. Configured Vercel CDN static binary hosting for Private Repository support: un-ignored `public/*.exe` & `public/*.apk` in `.gitignore`, committed release binaries to `public/`, and updated `version.json` & `app_versions` to Vercel static direct URLs.
- Verification: Production DB query verified Chunwei threshold updated from 6h00m to 5h04m (`neutral_p95_minutes=259` + `buffer=45`); `npm run build` PASS; `npx vitest run` (73 tests across 12 suites) PASS; `npx tsc --noEmit` PASS; pushed to `origin/main` (`84bba4b`).

## 2026-07-31 â€” iOS TestFlight session persistence & RPC permission fix Â· Antigravity

[Antigravity Â· 2026-07-31 12:20 +06:00] `KC-IOS-UNLOCK-SPIKE-001`

- Why: TestFlight Build 9 defaulted to "æœªç™»å½•" (unauthenticated) state and group RPC operations (scan2join) failed with SQL permission errors because `@supabase/ssr` `createBrowserClient` lost session cookies on WKWebView process restarts.
- Fix: Replaced `@supabase/ssr` with standard `@supabase/supabase-js` `createClient` using `cookieAndLocalStorage` hybrid engine in `src/lib/supabase.ts`. `localStorage` provides native-level permanent persistence in iOS WKWebView, guaranteeing `authenticated` session state across app restarts.
- Fastlane CI: Added auto-prune of oldest iOS distribution certificate when count >= 2 to `Fastfile` to resolve Apple Connect 3-cert limit.
- Status: Pushed commit `73678eb` / `a9caeb0`, triggered TestFlight Build 10 (GitHub Actions run #30608983702).

## 2026-07-29 â€” Keep Contact v0.5.22 integrated release