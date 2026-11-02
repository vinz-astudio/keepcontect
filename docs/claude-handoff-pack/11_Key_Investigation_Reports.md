# Keep Contact 关键专项技术调查与审计报告合集

## 报告一：iOS 24小时敲门实验报告 (2026-10-02)

# iOS 24 å°æ—¶"æ•²é—¨"å®žéªŒï¼ˆå¾…æ‰§è¡Œï¼‰

[Claude Â· 2026-10-02] çŠ¶æ€ï¼š**å·²ç»“æŸå¹¶è¿˜åŽŸï¼ˆ2026-10-08ï¼‰**ã€‚ç»“æžœè§æ–‡æœ«ã€‚ï¼ˆä»¥ä¸‹ä¸ºæ‰§è¡Œæ—¶è®°å½•ï¼‰äººç±»æ‰¹å‡†åŽï¼Œç¬¬ä¸€æ¬¡æ‰§è¡Œè¢«ç³»ç»Ÿæ‹¦æˆªï¼ˆProduction Deployï¼‰ï¼›äººç±»åœ¨èŠå¤©é‡Œæ”¾è¡ŒåŽäºŽ 2026-10-02 17:23:46Z æ‰§è¡ŒæˆåŠŸã€‚å‡½æ•°æƒé™è¯»å›žä»ä¸º `{postgres=X/postgres,service_role=X/postgres}`ã€‚å®žéªŒçª—å£ 17:30Zâ€“æ¬¡æ—¥ 17:30Zã€‚

## ç›®çš„
iPhone æ‹”ç”µæ—¶å‡ ä¹Žä¸å“åº”æœåŠ¡å™¨çš„é™é»˜æŽ¨é€ï¼ˆ"æ•²é—¨"ï¼‰ã€‚2026-08-21 ä¹‹åŽæ•²é—¨ä»Žæ¯ 15 åˆ†é’Ÿæ”¹æˆ"æˆªæ­¢å‰ 60 åˆ†é’Ÿå†…ã€é—´éš”è‡³å°‘ 30 åˆ†é’Ÿ"ï¼Œå“åº”æ•°ä¹Ÿéšä¹‹ä¸‹é™ï¼Œå‡ ä¹Žåªåœ¨å……ç”µæ—¶å“åº”ã€‚è¦éªŒè¯ï¼šæ¢å¤ 15 åˆ†é’Ÿä¸€æ¬¡çš„æ•²é—¨ï¼Œæ‹”ç”µæ—¶çš„å“åº”æ•°ä¼šä¸ä¼šå›žå‡ã€‚

## èŒƒå›´
- åªå¯¹ iOS æµ‹è¯•è´¦å· `c84e2f15-a272-40ce-9e98-f7de6820b230`ï¼ˆçŽ°çŠ¶ï¼š`passive_checkin` æ¨¡å¼ï¼Œæœªè§¦å‘ç†”æ–­å¼€å…³ï¼‰ã€‚
- åªæ”¹ä¸€ä¸ªå‡½æ•° `public.passive_knock_targets()`ã€‚ä¸æ”¹è¡¨ã€ä¸æ”¹è¿ç§»è´¦æœ¬ã€ä¸æ”¹å®¢æˆ·ç«¯ã€ä¸æ”¹å…¶ä»–è´¦å·ã€‚
- 24 å°æ—¶ï¼š`2026-10-02 17:30Z` åˆ° `2026-10-03 17:30Z`ï¼Œå…±çº¦ 96 æ¬¡æ•²é—¨ã€‚ç»“æŸæ—¶é—´å†™åœ¨å‡½æ•°é‡Œï¼Œåˆ°ç‚¹åŽå‡½æ•°è¡Œä¸ºä¸ŽåŽŸç‰ˆå®Œå…¨ç›¸åŒã€‚
- `passive-poll` å®šæ—¶ä»»åŠ¡çŽ°çŠ¶ï¼šæ¯ 15 åˆ†é’Ÿä¸€æ¬¡ï¼Œå·²å¯ç”¨ã€‚

## æ‰§è¡Œï¼ˆç”Ÿäº§å†™å…¥ï¼Œéœ€æ”¾è¡Œï¼‰
åŽŸå‡½æ•° sha256ï¼š`2ad7ba5162a8d686632be663d882ad115d62072a4a59de805dd4325440d201b6`ï¼ˆä¸Žä»“åº“è¿ç§» `20260821030000` ä¸­çš„å®šä¹‰ä¸€è‡´ï¼‰ã€‚
ä¸‹é¢çš„å‡½æ•° = åŽŸå‡½æ•° + ä¸€ä¸ªåªå¯¹è¯¥è´¦å·ã€åªåœ¨æ—¶é—´çª—å†…ç”Ÿæ•ˆçš„åˆ†æ”¯ã€‚ç”¨ `execute_sql` æ‰§è¡Œï¼Œä¸èµ°è¿ç§»ï¼Œæ‰€ä»¥è¿ç§»è´¦æœ¬ä¸å˜ã€‚

```sql
CREATE OR REPLACE FUNCTION public.passive_knock_targets()
 RETURNS TABLE(user_id uuid, window_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- TEMPORARY EXPERIMENT (human-approved 2026-10-02): second branch knocks the iOS tester
  -- c84e2f15-a272-40ce-9e98-f7de6820b230 on every 15-minute passive-poll run between
  -- 2026-10-02 17:30Z and 2026-10-03 17:30Z. After the end time it returns nothing.
  SELECT due.user_id, due.window_id FROM (
    SELECT DISTINCT ON (account.user_id)
      account.user_id, live.id AS window_id, live.arrival_deadline
    FROM public.passive_checkin_accounts AS account
    JOIN public.passive_checkin_windows AS live
      ON live.epoch_id = account.active_epoch_id AND live.outcome = 'pending'
    WHERE account.engine_mode IN ('shadow','passive_checkin')
      AND NOT account.kill_switch_active
    ORDER BY account.user_id, live.ordinal
  ) due
  WHERE due.arrival_deadline <= clock_timestamp() + interval '60 minutes'
    AND NOT EXISTS (
      SELECT 1 FROM private.passive_knock_attempts AS prior
      WHERE prior.window_id = due.window_id
        AND prior.requested_at > clock_timestamp() - interval '30 minutes'
    )
  UNION
  SELECT experiment.user_id, experiment.window_id FROM (
    SELECT DISTINCT ON (account.user_id)
      account.user_id, live.id AS window_id
    FROM public.passive_checkin_accounts AS account
    JOIN public.passive_checkin_windows AS live
      ON live.epoch_id = account.active_epoch_id AND live.outcome = 'pending'
    WHERE account.user_id = 'c84e2f15-a272-40ce-9e98-f7de6820b230'::uuid
      AND account.engine_mode IN ('shadow','passive_checkin')
      AND NOT account.kill_switch_active
      AND clock_timestamp() >= timestamptz '2026-10-02 17:30:00+00'
      AND clock_timestamp() <  timestamptz '2026-10-03 17:30:00+00'
    ORDER BY account.user_id, live.ordinal
  ) experiment
  WHERE NOT EXISTS (
    SELECT 1 FROM private.passive_knock_attempts AS prior
    WHERE prior.user_id = experiment.user_id
      AND prior.requested_at > clock_timestamp() - interval '10 minutes'
  )
$function$;
```

æ‰§è¡ŒåŽæ£€æŸ¥ï¼šå‡½æ•°æƒé™ä»æ˜¯ `{postgres=X/postgres,service_role=X/postgres}`ï¼›å…¶ä»–è´¦å·çš„æ•²é—¨è¡Œä¸ºä¸å˜ã€‚

## è¿˜åŽŸï¼ˆå®žéªŒç»“æŸåŽï¼Œæˆ–ä»»ä½•æ—¶å€™æƒ³æå‰åœï¼‰
æŠŠå‡½æ•°æ”¹å›žåŽŸç‰ˆï¼ˆä»“åº“è¿ç§» `supabase/migrations/20260821030000_knock_before_the_miss_and_name_it.sql` é‡Œçš„å®šä¹‰ï¼‰ï¼Œå¹¶ç¡®è®¤ sha256 å›žåˆ° `2ad7ba51â€¦01b6`ã€‚æå‰åœä¹Ÿåªéœ€è¿™ä¸€æ­¥ã€‚

## è¯»æ•°ï¼ˆå®žéªŒç»“æŸåŽï¼Œåªè¯»ï¼‰
- å¯¹æ¯”å®žéªŒå‰ 10 å¤©ä¸Žå®žéªŒ 24 å°æ—¶ï¼ŒåŒä¸€è´¦å·ï¼šæ•²é—¨æ¬¡æ•°ã€è¢«å›žç­”æ¬¡æ•°ã€å›žç­”æ—¶çš„å……ç”µçŠ¶æ€ï¼ˆæ‹”ç”µ vs å……ç”µï¼‰ã€‚
- æ•°æ®æ¥æºï¼š`private.passive_knock_attempts`ï¼ˆæ¯æ¬¡æ•²é—¨åŠåˆ°è¾¾è®¾å¤‡æ•°ï¼‰ä¸Ž `device_activity_samples` / è¢«åŠ¨è¯æ®äº‹ä»¶ï¼ˆå›žç­”æ—¶çš„ç”µé‡çŠ¶æ€ï¼‰ã€‚
- å®žéªŒå‰åŸºçº¿ï¼ˆè§ Known Issues IOS-PWA-20260919ï¼Œ2026-10-02 è¯»æ•°ï¼‰ï¼š08-21 ä¹‹åŽæ¯å¤© 1â€“16 æ¬¡æ•²é—¨ï¼Œçº¦ 1â€“3 æ¬¡è¢«å›žç­”ï¼Œå‡ ä¹Žå…¨åœ¨ `charging/full`ï¼›08-31..09-16 HealthKit å”¤é†’æ‹”ç”µæ—¶æ¯å¤©çº¦ 8â€“14 æ¬¡ï¼Œ09-17 èµ·çº¦ 0â€“4 æ¬¡ã€‚
- åˆ¤è¯»ï¼šè‹¥æ‹”ç”µæ—¶å“åº”æ•°æ˜Žæ˜¾å›žå‡ â†’ åŽŸå› åœ¨æ•²é—¨é¢‘çŽ‡ï¼›è‹¥ä»å‡ ä¹Žåªåœ¨å……ç”µæ—¶å“åº” â†’ åŽŸå› åœ¨ iOS å¯¹ä½Žä¼˜å…ˆçº§æŽ¨é€çš„èŠ‚æµï¼Œéœ€å¦æƒ³åŠžæ³•ï¼ˆä¾‹å¦‚å®¢æˆ·ç«¯æ”¹æ³•ï¼‰ã€‚

## ä»£ä»·ä¸Žé£Žé™©
- 24 å°æ—¶çº¦ 96 æ¬¡é™é»˜æŽ¨é€å‘å¾€è¯¥æµ‹è¯•è´¦å·çš„ iPhoneã€‚ä¼šæ¶ˆè€—å°‘é‡ç”µé‡ï¼Œä¸ä¼šå‘ç”¨æˆ·æ˜¾ç¤ºä»»ä½•é€šçŸ¥ã€‚
- åªå½±å“è¿™ä¸€ä¸ªè´¦å·ï¼Œä¸å½±å“å…¶ä»–ç”¨æˆ·çš„å‘Šè­¦åˆ¤æ–­ã€‚

## ç»“æžœï¼ˆ2026-10-08 è¯»æ•°ï¼Œåªè¯»ï¼‰

**ç»“è®ºï¼šæŠŠæ•²é—¨ä»Žçº¦ 13 æ¬¡/å¤©æé«˜åˆ° 96 æ¬¡/å¤©ï¼Œæ²¡æœ‰è®©æ‰‹æœºåœ¨æ‹”ç”µæ—¶å“åº”ã€‚æ‹”ç”µæ—¶çš„å“åº”æ•°ä»ç„¶æ˜¯ 0ã€‚æ•²é—¨é¢‘çŽ‡ä¸æ˜¯åŽŸå› ã€‚**

- å®žéªŒçª—å£ 10-02 17:30Z â†’ 10-03 17:30Zï¼š96 æ¬¡æ•²é—¨ï¼Œå…¨éƒ¨è¢« FCM æŽ¥å—ï¼ˆsurfaces=3ï¼‰ã€‚å¯¹ç…§ï¼šå‰ 9 ä¸ªåŒé•¿åº¦çª—å£æ¯ä¸ª 10â€“14 æ¬¡æ•²é—¨ã€1â€“3 æ¬¡ push-wake å“åº”ã€‚
- çª—å£å†… 7 æ¬¡ push-wake å“åº”ï¼Œ**å…¨éƒ¨åœ¨å……ç”µæ—¶**ï¼›æ‹”ç”µæ—¶å“åº” 0ã€‚
- é€æ¡çœ‹æ ·æœ¬ï¼ˆç”µé‡å˜åŒ–æ˜¯è¯æ®ï¼‰ï¼š
  - 10-02 13:44Z ä¹‹åŽåˆ° 10-03 08:59Z çº¦ 19 å°æ—¶æ²¡æœ‰ä»»ä½•å“åº”ï¼Œç”µé‡åªä»Ž 0.35 é™åˆ° 0.30ï¼ˆæ‰‹æœºæ²¡åœ¨å……ç”µï¼‰ã€‚å…¶é—´çº¦ 60 æ¬¡æ•²é—¨å…¨éƒ¨æ— å“åº”ã€‚
  - 10-03 08:59Z èµ·æ‰‹æœºæŽ¥ä¸Šå……ç”µï¼ˆç”µé‡ 0.30 â†’ 0.90ï¼‰ï¼Œå¯¹æ¯ä¸€æ¬¡æ•²é—¨åœ¨å‡ ç§’å†…å“åº”ï¼ˆ09:00ã€09:15ã€09:30ã€09:45ï¼‰ã€‚10:07Z é”å±å……ç”µæ—¶ä»å“åº”ä¸€æ¬¡ã€‚
  - 10:07Z ä¹‹åŽåˆ° 17:11Z çº¦ 7 å°æ—¶æ— å“åº”ï¼Œç”µé‡ 0.90 â†’ 0.70ï¼ˆæ‹”ç”µï¼‰ã€‚å…¶é—´çº¦ 28 æ¬¡æ•²é—¨æ— å“åº”ã€‚
- æ‰€ä»¥ï¼šå“åº”ä¸Ž"æ˜¯å¦åœ¨å……ç”µ"å®Œå…¨å¯¹åº”ï¼Œä¸Ž"æ˜¯å¦é”å±"æ— å…³ï¼ˆ10:07Z é”å±ä»å“åº”ï¼‰ã€‚
- å±€é™ï¼šåªæœ‰ä¸€å°æ‰‹æœºï¼›çª—å£å†…åªæœ‰ä¸¤æ®µæ‹”ç”µæœŸï¼›è¿˜ä¸èƒ½åŒºåˆ†"iOS ä¸æ”¾è¡Œ"å’Œ"è¿™å°æ‰‹æœºçš„æŸé¡¹è®¾ç½®"ï¼ˆä¾‹å¦‚åŽå° App åˆ·æ–°ï¼‰ã€‚09-13..09-16 åŒä¸€è´¦å·æ‹”ç”µæ—¶æ¯å¤©æœ‰ 7â€“14 æ¬¡å”¤é†’ï¼Œ09-17 èµ·å‡å°‘ï¼ŒåŽŸå› ä»æœªæ‰¾åˆ°ï¼ˆç‰ˆæœ¬ä¸€ç›´æ˜¯ 0.7.6/0.7.7ï¼Œæ‰‹æœºåœ¨ 09-23 é‡å¯è¿‡ï¼Œä¸æ˜¯ 09-17ï¼‰ã€‚

## è¿˜åŽŸ
2026-10-08 å·²æŠŠ `passive_knock_targets()` æ”¹å›žåŽŸç‰ˆï¼Œsha256 è¯»å›ž `2ad7ba51â€¦01b6`ï¼Œæƒé™è¯»å›ž `{postgres=X/postgres,service_role=X/postgres}`ã€‚


---

## 报告二：原生机制审查报告 (2026-09-24)

# KC åŽŸç”Ÿç‰ˆæœ¬æœºåˆ¶å®¡æŸ¥ â€” 2026-09-24

[Codex Â· 2026-09-24 23:40 +06:00]

ç»“è®ºï¼šç¡®è®¤ 8 é¡¹é«˜å¯ä¿¡æœºåˆ¶ç¼ºé™·ï¼Œå¦åˆ— 3 é¡¹è¡¥å……ç¼ºå£ã€‚æ­¤æ¬¡åªå®¡æŸ¥ï¼Œæ²¡æœ‰ä¿®æ”¹äº§å“ä»£ç æˆ–å‘å¸ƒã€‚

## ç‰ˆæœ¬ä¸Žè¯æ®è¾¹ç•Œ

- iOSï¼šæŒ‰æœ€æ–°ä¸Šä¼ æº `b279da0543c823635b8ea3af6add3addd14d3ab5` å®¡æŸ¥ï¼Œå³ TestFlight 0.7.8 (44)ã€‚GitHub workflow `35999493934` çš„ archive/upload job å®žæ—¶æŸ¥è¯¢ä¸º SUCCESSã€‚Apple processingã€æµ‹è¯•è€…å®‰è£…å’ŒçœŸæœºéªŒæ”¶æœªéªŒè¯ã€‚
- Android APK/AABï¼šå½“å‰åˆ†å‘ç™»è®°ä¸º 0.7.7ã€‚å…³é”® Java æ–‡ä»¶ä¸Ž `v0.7.7` æ¯”è¾ƒæ— å·®å¼‚ï¼›0.7.8 å·²æž„å»ºã€æœªåˆ†å‘ã€‚APK/AAB ä½¿ç”¨åŒä¸€å®žçŽ°ï¼Œä»¥ä¸‹é—®é¢˜ä¸å› åŒ…è£…æ ¼å¼æ¶ˆå¤±ã€‚
- Tauriï¼šæœ¬åœ°åˆ†å‘ç›®å½•çš„ EXE äº§å“ç‰ˆæœ¬ä¸º 0.7.7ï¼Œç‰ˆæœ¬åŒ–æ–‡ä»¶ä¸Žåˆ«å SHA-256 å‡ä¸º `0084E7E21C8BBDDBB2B2B81B5B95056EBE9652AFEC471B202DE10F2C293AA145`ã€‚ä»¥ä¸‹ TS æ–‡ä»¶ä¸Ž `v0.7.7` æ— å·®å¼‚ã€‚æœªåç¼–è¯‘è¿œç«¯ EXEï¼Œä¸èƒ½å®£ç§°å®Œæ•´äºŒè¿›åˆ¶ä¸Žæºç ä¸€è‡´æ€§è¯æ˜Žã€‚
- ç”Ÿäº§ï¼šåªè¯»æ ¸å¯¹ migration `20260923054905` å·²éƒ¨ç½²ï¼›è¯»å– `private.confirm_subject_safety` å®žé™…å‡½æ•°ä½“ï¼Œç¡®è®¤æ–°æ´»åŠ¨è§£é™¤ä¸Žå½“å‰ç¡®è®¤è§„åˆ™ã€‚`app_versions` æœ€æ–°å…¬å¼€ç™»è®°ä»ä¸º 0.7.7ï¼Œä¸èƒ½ç”¨è¯¥è¡¨å¦è®¤å•ç‹¬ä¸Šä¼ çš„ TestFlight 0.7.8ã€‚
- æ—§ HealthKit æŸ¥è¯¢æ¸¸æ ‡æ¼é‡‡ã€é™é»˜å”¤é†’ä¸é‡æŸ¥ HealthKitï¼šå·²åœ¨ä¸Šè¿° iOS æºä¿®å¤ï¼Œä¸åˆ—ä½œæœªè§£å†³ã€‚

## éœ€è¦ä¼˜å…ˆä¿®å¤

### M01 Â· P1 Â· iOS æŠŠæ— å¯†ç è®¾å¤‡çš„åŽå°å”¤é†’å½“æˆæœ¬äººæ´»åŠ¨

- è§¦å‘ï¼šè®¾å¤‡æœªè®¾ç½®é”å±å¯†ç ï¼›æ— äººæ“ä½œæ—¶æ”¶åˆ°é™é»˜æŽ¨é€ã€‚
- æ ¹å› ï¼š`PassiveGuard.swift:285-287` ç”¨ `isProtectedDataAvailable` åˆ¤å®šæ­£åœ¨ä½¿ç”¨è®¾å¤‡ï¼Œç›´æŽ¥è°ƒç”¨ `recordEvent(reason: "wake-sample")`ã€‚è¯¥å±žæ€§è¡¨ç¤ºæ•°æ®ä¿æŠ¤å¯ç”¨æ€§ï¼Œä¸æ˜¯ä¸€æ¬¡çœŸå®žäº¤äº’ã€‚`DeviceSample.swift:9-10` è‡ªèº«ä¹Ÿè®°å½•äº†æ— å¯†ç è®¾å¤‡é•¿æœŸæ˜¾ç¤º unlocked çš„æƒ…å†µã€‚
- åŽæžœï¼šåˆ›å»ºå½“å‰æ—¶é—´çš„ `app/capacitor` æ´»åŠ¨ï¼›å¯æŽ¨è¿Ÿæ²‰é»˜åˆ¤å®šï¼Œå¹¶åœ¨æœªè¦æ±‚ guardian pattern æ—¶è§£é™¤æ™®é€šå‘Šè­¦ã€‚
- é“¾è·¯ï¼š`recordEvent` â†’ `/ping` â†’ `record_behavior_ping_for_user` â†’ ADR-0045 `resolve_activity_alerts`ã€‚æ­¤è·¯å¾„åœ¨æœ€æ–° iOS ä¸Šä¼ æºä»å­˜åœ¨ã€‚
- éªŒè¯ï¼šæºä»£ç å’Œå¹³å°è¯­ä¹‰æ ¸å¯¹ï¼›æœªåšæ— å¯†ç  iPhone çœŸæœºé‡æ”¾ã€‚ä¿®å¤åº”ä¾æ®çœŸå®žäº¤äº’è¯æ®ï¼Œä¸åº”æŠŠå®ˆæŠ¤è€… pattern å½“ä½œæ­¤ç¼ºé™·çš„è¡¥æ•‘ã€‚
- å®˜æ–¹ä¾æ®ï¼š[Apple keychain accessibility](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility?changes=_9) æ˜Žç¡®è¯´æ˜Žæ— å¯†ç è®¾å¤‡è§†ä¸ºä¸€ç›´è§£é”ï¼›[æ–‡ä»¶æ•°æ®ä¿æŠ¤](https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files?changes=lat_5) è¯´æ˜Žè®¾ç½®æœ‰æ•ˆå¯†ç æ‰è‡ªåŠ¨å¯ç”¨æ•°æ®ä¿æŠ¤ã€‚å·²é€šè¿‡å®˜æ–¹æ­£æ–‡æœç´¢ç»“æžœæ ¸å¯¹ï¼Œéžä»…ä¾æ® JS å ä½é¡µã€‚

### M02 Â· P1 Â· iOS åŽ†å²æ­¥æ•°è¢«æ ‡æˆå”¤é†’æ—¶çš„æ–°æ´»åŠ¨

- è§¦å‘ï¼š10:05 èµ°åŠ¨ï¼Œæ­¤åŽé™æ­¢ï¼›12:00 æ‰æ‰§è¡Œä¸Šæ¬¡é‡‡æ ·ä»¥æ¥çš„ CoreMotion æŸ¥è¯¢ã€‚
- æ ¹å› ï¼š`DeviceSample.swift:119` å…ˆå°† `observedAt` è®¾ä¸ºå½“å‰æ—¶é—´ï¼›pedometer æŸ¥è¯¢è¿”å›žæ•´ä¸ªåŒºé—´çš„ç´¯è®¡æ­¥æ•°ã€‚æœ€æ–°æº `PassiveGuard.swift:797-804` å°†è¿™ä¸ª 12:00 æ—¶é—´æäº¤ä¸º motion evidenceã€‚
- åŽæžœï¼š10:05 çš„æ—§æ­¥æ•°è¢«ä¿å­˜ä¸º 12:00 æ´»åŠ¨ï¼›å¯è§£é™¤ 10:05 ä¹‹åŽäº§ç”Ÿçš„æ™®é€šå‘Šè­¦ã€‚HealthKit çš„åŽ†å²é‡å ä¿®å¤æ²¡æœ‰è§£å†³æ­¤è·¯å¾„ã€‚
- æœåŠ¡ç«¯ï¼š`20260920000000_proactive_care_and_safe_ack.sql:441-453` æŠŠè¯¥æ—¶é—´æ¡¥æŽ¥æˆ `behavior_pings(kind=steps)`ï¼›ADR-0045 ä¾æ®è¯¥æ—¶é—´åˆ¤æ–­æ–°æ´»åŠ¨ã€‚
- éªŒè¯ï¼šå®Œæ•´ä»£ç é“¾è·¯ï¼›æœªå£°ç§°å·²è§‚æµ‹åˆ°ç”Ÿäº§è¯¯è§£é™¤äº‹ä»¶ã€‚éœ€è¦åŒºåˆ†åŒºé—´è¯æ®å’Œå¯è¯æ˜Žçš„æ–°æ´»åŠ¨æ—¶é—´ã€‚

### M03 Â· P1 Â· Tauri å¯¹åŒä¸€æ¬¡æ—§è¾“å…¥é‡å¤ç”Ÿæˆæ–°æ´»åŠ¨

- è§¦å‘ï¼šç”¨æˆ·åªåœ¨ç¬¬ 0 åˆ†é’Ÿä½¿ç”¨ä¸€æ¬¡é”®é¼ ï¼Œæ­¤åŽä¿æŒé™æ­¢ã€‚
- æ ¹å› ï¼š`src/features/signals/sources.ts:59-63` æ¯ 2 åˆ†é’ŸæŸ¥è¯¢ï¼Œåªè¦ idle å°äºŽ 10 åˆ†é’Ÿï¼Œå°±æŒ‰ 5 åˆ†é’ŸèŠ‚æµé‡æ–° `record('interaction')`ã€‚`src/features/signals/store.ts:118` é»˜è®¤ä½¿ç”¨å½“å‰æ—¶é—´ã€‚
- åŽæžœï¼šç¬¬ 6 åˆ†é’Ÿè¿˜èƒ½ç”Ÿæˆæ–°çš„ interactionï¼›å¯æŽ¨è¿Ÿæ²‰é»˜ï¼Œä¹Ÿå¯åœ¨åŠæ—¶ä¸Šä¼ æ—¶è§£é™¤çœŸå®žè¾“å…¥ä¹‹åŽäº§ç”Ÿçš„å‘Šè­¦ã€‚
- éªŒè¯ï¼šå†…å­˜è¿è¡Œå®žé™…å‡½æ•°å¹¶æ³¨å…¥æ—¶é’Ÿ/idle æŽ¢é’ˆï¼Œå•æ¬¡çœŸå®žè¾“å…¥äº§ç”Ÿç¬¬ 0ã€6 åˆ†é’Ÿä¸¤æ¡äº‹ä»¶ã€‚`getAutomaticPingSource` å¯¹ Tauri è¿”å›ž `tauri`ï¼ŒæœåŠ¡ç«¯æ˜Žç¡®æŽ¥å— tauri/interactionï¼Œæ™®é€šæµè§ˆå™¨è¿‡æ»¤æ— æ³•é˜»æ­¢å®ƒã€‚
- è¾¹ç•Œï¼šå³æ—¶ä¸Šä¼ æœ‰ 10 åˆ†é’ŸèŠ‚æµï¼›å¯è§é¡µ reload/sync ä¼šè¡¥ä¼ ã€‚æ˜¯å¦è§£é™¤æŸæ¬¡å‘Šè­¦ä»å–å†³äºŽä¸Šä¼ æ–°é²œåº¦ä¸Ž guardian policyã€‚

### M04 Â· P1 Â· iOS/Android çš„æ—§é€šçŸ¥æŒ‰é’®ä¼šç¡®è®¤æ–°çš„å‘Šè­¦

- è§¦å‘ï¼šå‘Šè­¦ A çš„é€šçŸ¥ä»åœ¨ç³»ç»Ÿé€šçŸ¥ä¸­å¿ƒï¼›A å·²è§£å†³ï¼›éšåŽäº§ç”Ÿå‘Šè­¦ Bï¼Œç”šè‡³ SOSï¼›ç”¨æˆ·ä»Ž A çš„â€œä¸€åˆ‡å®‰å¥½â€æŒ‰é’®å†·å¯åŠ¨åº”ç”¨ã€‚
- æ ¹å› ï¼šAndroid `NotifyWorker.java:290-295`ã€iOS `NotificationTap.swift:45-70` åªä¼  kind/ackSafeï¼Œä¸ä¼ åŽŸ alert ID æˆ– ownerã€‚`LivenessProvider.tsx:136` è°ƒç”¨æ—  ID çš„ `acknowledgeSafe()`ã€‚
- ç”Ÿäº§è¡Œä¸ºï¼šå½“å‰ `private.confirm_subject_safety` åœ¨ ID ä¸º NULL æ—¶é€‰æ‹©å½“å‰è´¦æˆ·æœ€æ–° open alertï¼Œæœªé™åˆ¶ä¸ºé€šçŸ¥åŽŸå‘Šè­¦æˆ–æ™®é€šå‘Šè­¦ã€‚å› æ­¤ä¼šç¡®è®¤ Bã€‚guardian pattern æ ¡éªŒä»æ‰§è¡Œã€‚
- éªŒè¯ï¼šå®¢æˆ·ç«¯ä¸¤ç«¯ payloadã€æœ€æ–° iOS æºã€å®žæ—¶ç”Ÿäº§å‡½æ•°ä½“äº¤å‰æ ¸å¯¹ï¼›æœªåœ¨çœŸå®žç”¨æˆ·ä¸Šè§¦å‘å‘Šè­¦æµ‹è¯•ã€‚
- ä¿®å¤è¾¹ç•Œï¼šé€šçŸ¥åŠ¨ä½œå¿…é¡»ç»‘å®šåŽŸå‘Šè­¦å’Œè´¦æˆ·ï¼›è¿‡æœŸåŠ¨ä½œä¸å¯è½¬è€Œç¡®è®¤å¦ä¸€å‘Šè­¦ã€‚

### M05 Â· P1 Â· åŽŸç”Ÿé€šçŸ¥å¿«æ·ç¡®è®¤åªå¤„ç†å†·å¯åŠ¨

- è§¦å‘ï¼šåº”ç”¨é¡µé¢å·²ç»åŠ è½½ï¼ŒéšåŽè¿›å…¥åŽå°ï¼›ç”¨æˆ·ç‚¹å‡»ç³»ç»Ÿé€šçŸ¥çš„â€œä¸€åˆ‡å®‰å¥½â€ã€‚
- æ ¹å› ï¼š`LivenessProvider.tsx:96-99,130-152` é€šè¿‡ `promptedRef` åªæ¶ˆè´¹ä¸€æ¬¡ã€‚iOS delegate åªä¿å­˜åŠ¨ä½œï¼Œæ— æ¢å¤æ¶ˆè´¹ï¼›Android è¿˜æœ‰ `singleTask/onNewIntent` ç¼ºå£ï¼Œplugin è¯»å–çš„ `getIntent()` ä»æ˜¯å¯åŠ¨ Intentã€‚
- åŽæžœï¼šåº”ç”¨æ‰“å¼€ï¼Œä½†æ˜¾å¼ç¡®è®¤åŠ¨ä½œæœªæ‰§è¡Œã€‚æ™®é€šå‰å°æ´»åŠ¨è‡ªåŠ¨è§£è­¦å¯æŽ©ç›–é—®é¢˜ï¼Œä¸èƒ½è¯æ˜Žå¿«æ·ç¡®è®¤æˆåŠŸã€‚iOS åŠ¨ä½œè¿˜å¯èƒ½ç•™å¾…åŽç»­å†·å¯åŠ¨æ¶ˆè´¹ã€‚
- éªŒè¯ï¼šæºä»£ç ã€å·²å®‰è£… Capacitor bridge å’Œ Android å®˜æ–¹ Activity åˆçº¦æ ¸å¯¹ï¼›æœªåšçœŸæœºæ“ä½œéªŒæ”¶ã€‚
- å®˜æ–¹ä¾æ®ï¼š[Activity.getIntent](https://developer.android.com/reference/android/app/Activity#getIntent())ã€‚

### M06 Â· P1 Â· Android å·²æŒä¹…åŒ–çš„ä¸Šä¼ é˜Ÿåˆ—ç¼ºå°‘ç‹¬ç«‹é‡è¯•

- è§¦å‘ï¼šä¸€æ¡ evidence ä¸Šä¼ è¶…æ—¶æˆ– 5xxï¼›éšåŽç½‘ç»œæ¢å¤ï¼Œæ‰‹æœºæ— æ–°æ´»åŠ¨ï¼Œç”¨æˆ·ä¸é‡å¼€åº”ç”¨ã€‚
- æ ¹å› ï¼š`PassivePing.java:661-679` åœ¨ä¸Šä¼ å‰æŽ¨è¿› usage evidence æ—¶é—´ï¼›æ–°æ‰«ææ— æ›´æ–°æ—¶ `enqueueEvidence(null)` ç«‹å³è¿”å›žã€‚`drainEvidenceQueue` ä»…ç”±éžç©ºæ–°äº‹ä»¶æˆ– configure è§¦å‘ã€‚`NotifyWorker.java:148-149` æ²¡æœ‰å•ç‹¬ drainï¼Œä¹Ÿä¸ç­‰å¾…è¯¥å¼‚æ­¥ä¸Šä¼ å†å†³å®š retryã€‚
- åŽæžœï¼šç£ç›˜å·²æœ‰çš„æ­£è¯æ®åœåœ¨é˜Ÿåˆ—ï¼›åŽå°è½®è¯¢æˆåŠŸä¸ä»£è¡¨æ•°æ®ä¸Šä¼ æˆåŠŸã€‚åªæœ‰æ–°äº‹ä»¶æˆ–é‡æ–°é…ç½®æ‰å†å°è¯•ã€‚
- éªŒè¯ï¼šæ‰€æœ‰ drain è°ƒç”¨ç‚¹åŠ worker è¿”å›žè·¯å¾„æ ¸å¯¹ï¼›å…³é”®å®žçŽ°ä¸Ž v0.7.7 ä¸€è‡´ã€‚æœªåšæ–­ç½‘çœŸæœºé‡æ”¾ã€‚

### M07 Â· P1 Â· Tauri å¯åŠ¨å¤±è´¥åŽä¸æ¢å¤è¢«åŠ¨è¯æ®é‡‡é›†

- è§¦å‘ï¼šå¯åŠ¨æ—¶è®¤è¯æŸ¥è¯¢/collector binding è¯·æ±‚å¤±è´¥ï¼›æˆ–è¿è¡Œä¸­ evidence binding è¢«æ’¤é”€ã€‚
- æ ¹å› ï¼š`shadowCoverage.ts:253-272` åˆå§‹åŒ–æˆåŠŸåŽæ‰å»ºç«‹å®šæ—¶å™¨ï¼›å¼‚å¸¸ç›´æŽ¥åžæŽ‰ã€‚æ’¤é”€åœ¨ `:209-214` å°† binding æ¸…ç©ºï¼ŒåŽç»­ sample å›  binding ä¸ºç©ºç›´æŽ¥è¿”å›žï¼Œä¸é‡æ–°ç»‘å®šã€‚
- åŽæžœï¼šè”ç½‘æ¢å¤åŽä»ä¸é‡è¯•æ­¤é‡‡é›†é“¾è·¯ï¼Œéœ€è¦é‡å¯/é‡æ–°æŒ‚è½½ã€‚æ—§ interaction é“¾è·¯ä»å¯èƒ½è¿è¡Œï¼Œå› æ­¤ä¸èƒ½æŠŠæœ¬é¡¹æè¿°æˆâ€œæ¡Œé¢å®Œå…¨æ²¡æœ‰ä»»ä½• pingâ€ã€‚
- éªŒè¯ï¼šå†…å­˜æ‰§è¡Œå®žé™…å¯¼å‡ºå‡½æ•°å¹¶æ³¨å…¥æ•…éšœã€‚getUser å¤±è´¥ï¼š0 timer/0 probeï¼›bind å¤±è´¥ï¼š1 bind/0 timer/0 probeï¼›revoked åŽæ‰§è¡Œä¸¤æ¬¡å®šæ—¶å›žè°ƒï¼šä»åªæœ‰ 1 bind/1 probe/1 sendã€‚

### M08 Â· P2 Â· Tauri é‡å¯ä¼šä¸¢å¼ƒåŒä¸€è´¦æˆ·çš„ç¦»çº¿è¯æ®

- è§¦å‘ï¼šç¦»çº¿äº‹ä»¶å°šæœªä¸Šä¼ å°±å…³é—­åº”ç”¨ï¼›åŒä¸€è´¦æˆ·é‡æ–°å¯åŠ¨ã€‚
- æ ¹å› ï¼š`shadowCoverage.ts:260-269` æ’¤é”€æ—§ bindingï¼Œè°ƒç”¨ `clearTauriStorage`ï¼Œå†åˆ›å»ºç©ºé˜Ÿåˆ—ã€‚
- åŽæžœï¼šåŽ†å²è§‚å¯Ÿæ°¸ä¹…ä¸¢å¤±ï¼Œæ— æ³•è¡¥æ­£å¯¹åº” passive check-in windowã€‚
- éªŒè¯ï¼šæ³¨å…¥åŒè´¦æˆ·æ—§ binding ä¸ŽæŒä¹…åŒ– `offline-event`ï¼Œæ‰§è¡ŒçœŸå®žåˆå§‹åŒ–ï¼›ç»“æžœ `revoked=['old-binding']`ã€`sent=[]`ã€`queueAfterRestart='[]'`ã€‚
- ä¿®å¤æ¶‰åŠå‡­æ®æŒä¹…åŒ–ä¸Žé˜Ÿåˆ—å½’å±žè®¾è®¡ï¼Œä¸èƒ½ç®€å•åŽ»æŽ‰è·¨è´¦æˆ·æ¸…ç†ã€‚

## è¡¥å……ç¼ºå£

- iOS é€€å‡ºåŽæŽ¨é€ç»‘å®šä»ç•™åœ¨æœåŠ¡ç«¯ï¼š`AuthProvider.tsx:163-173` åªæ¸…åŽŸç”Ÿ collector å’Œ auth sessionï¼›æœªæ³¨é”€ FCM tokenã€‚ç”Ÿäº§ `register_fcm_token` æ²¡æœ‰é…å¥—æ³¨é”€å‡½æ•°ï¼›ç”Ÿäº§ push-dispatch å¯¹ iOS self/concern ä»ç›´æŽ¥å‘å¯è§æ¶ˆæ¯ã€‚å› æ­¤é€€å‡ºåˆ°ç™»å½•é¡µåŽï¼Œæ—§è´¦æˆ·é€šçŸ¥ä»å¯ç”±ç³»ç»Ÿæ˜¾ç¤ºã€‚å†æ¬¡æˆåŠŸæ³¨å†ŒåŒä¸€ä¸ª token ç»™æ–°è´¦æˆ·æ—¶ä¼šæ”¹å˜å½’å±žã€‚æ­¤é¡¹ä¸ºä»£ç /æœåŠ¡ç«¯å¥‘çº¦ç¼ºé™·ï¼Œæœªåšè®¾å¤‡é‡æ”¾ã€‚
- Tauri æ‰˜ç›˜ç­¾åˆ°ç›‘å¬é”™è¯¯ï¼š`sources.ts:74-80` æ£€æŸ¥ `__TAURI_INTERNALS__.listen`ï¼›å®‰è£…çš„ Tauri 2 äº‹ä»¶æŽ¥å£æ²¡æœ‰è¯¥æ–¹æ³•ï¼Œå¯¼è‡´ç›‘å¬è·³è¿‡ã€‚éœ€é€šè¿‡æ­£å¼ event API æŽ¥å…¥å¹¶éªŒæ”¶æ‰˜ç›˜åŠ¨ä½œã€‚
- Tauri ç³»ç»Ÿé€šçŸ¥ä»ä¸ºæ—¢æœ‰ DESK-01ï¼š`pushApi.ts` æ˜Žç¡®å¯¹ Tauri ç¦ç”¨ Web Pushï¼Œæœªæ‰¾åˆ°æ¡Œé¢åŽŸç”Ÿé€šçŸ¥æŠ•é€’å®žçŽ°ã€‚ç«™å†…é€šçŸ¥ä¸ç­‰äºŽåŽå°ç³»ç»Ÿé€šçŸ¥ï¼›è¿™æ˜¯å·²çŸ¥èƒ½åŠ›ç¼ºå£ã€‚

## æœ¬æ¬¡éªŒè¯ä¸Žæœªè¦†ç›–é¡¹

- å½“å‰ä¸»å·¥ä½œåŒº `npm run test -- --reporter=dot`ï¼š105 æ–‡ä»¶ / 629 æµ‹è¯• PASSã€‚
- `npm run typecheck`ï¼šPASSã€‚
- Brain `check-all.mjs --only lessons,lessons-watch`ï¼š2/2 PASSã€‚
- Tauri ä¸‰é¡¹æ•…éšœæ³¨å…¥åªåœ¨å†…å­˜è¿è¡Œï¼Œæ— æµ‹è¯•æ–‡ä»¶æˆ–ä¸šåŠ¡æ–‡ä»¶ä¿®æ”¹ã€‚
- iOS æœ€æ–°å‘å¸ƒæµæ°´çº¿å®žæ—¶æ ¸æŸ¥ SUCCESSï¼›æœªé‡æ–°ç¼–è¯‘å‘å¸ƒï¼Œä¹Ÿæœªæ›´æ”¹ä»»ä½•ç”Ÿäº§æ•°æ®ã€‚
- æœªåš iPhone/Android/Windows çœŸæœºç«¯åˆ°ç«¯éªŒè¯ã€é•¿æœŸå¾…æœºè¯•éªŒæˆ–å®Œæ•´å®‰å…¨å®¡è®¡ã€‚æµ‹è¯•é€šè¿‡ä¸èƒ½æŽ’é™¤ä¸Šè¿°æœªè¦†ç›–ç”Ÿå‘½å‘¨æœŸåœºæ™¯ã€‚

å»ºè®®ä¿®å¤é¡ºåºï¼šM01â€“M04ï¼ˆæ´»åŠ¨ä¸Žè§£é™¤çœŸå®žæ€§ï¼‰ï¼ŒM05â€“M08ï¼ˆé€šçŸ¥åŠ¨ä½œå’Œé‡‡é›†æ¢å¤ï¼‰ï¼Œå†å¤„ç†è¡¥å……ç¼ºå£åŠè®¾å¤‡çŸ©é˜µéªŒæ”¶ã€‚


---

## 报告三：设备权限中心审计报告 (2026-09-19)

# Me device permissions audit and local repair

Status: LOCAL CANDIDATE, not released. Baseline main `78e667b6319e81a5cf373937a9187ded83a40415` (PWA and TestFlight 0.7.6 build 41). Android/Tauri published installers still precede this candidate. No production data, permissions, signing identities or release metadata changed.

## Confirmed source defects

1. `getAvailableSensors()` returned unsupported entries. `GuardianPermissionsCard` rendered them without the filter used by other consumers. The card offered computer input, Android motion and charging controls on unsupported devices.
2. Sensor rows used a local preference as their default permission result. Most displayed â€œGrantedâ€ without an OS query. The summary counted only denied states: initial, unavailable and limited states could display â€œKC has everything it needs.â€
3. `setSensorEnabled()` looked for `kc.passiveToken`. No writer exists anywhere in `src`; startup fetches the token from the authenticated server API. Normal switch changes therefore did not reconfigure the native collector, and errors were swallowed.
4. iOS â€œbackground guardâ€ permission was actually `enabled && evidenceConfigured`, not a system permission. Motion authorization and Background App Refresh were not exposed by the old bridge. Health read consent cannot be inferred from `asked`, observer registration or successful empty queries.
5. PWA notification permission was omitted. Tauri input availability was inferred from a preference rather than a native probe.
6. Me rendered a second set of collection switches in `PassiveSignalCard`, which could disagree with the permission center. Android silent mode was also labeled as a stopped service requiring permission, although a resident foreground service is optional.
7. The card refreshed on browser events only; no explicit native resume listener or stale-response guard existed.

These are code-proven defects, not proof of the original 14.5-hour iPhone wake-gap cause.

## Candidate behavior

| Surface | System checks | Collection and limitations |
| --- | --- | --- |
| Android APK/AAB | OS notification authorization, battery-optimization exemption, motion permission, usage-access permission | Shared binary behavior; supported controls only. Exemption does not verify background execution or OEM autostart. |
| iOS TestFlight/App Store | Existing OS notification check; new read-only CoreMotion and Background App Refresh bridge | One native collector switch covers unlock, motion/Health history and charging observations. Binding is not authorization. Restricted settings have no misleading repair button. Old shells show unverified for missing APIs. |
| Web/installed PWA | Current `Notification.permission` when push is supported | Page interaction only; ordinary browser tabs remain limited. Notification permission does not establish subscription delivery or background collection. Shortcuts remain a separate explicit setup. |
| Tauri | No native notification authorization bridge in this product | Query existing native idle-probe capability; absent/failed probes stay unverified. No mobile permission controls. |

- Preferences and OS authorization are separate labels. Unknown/checking/limited no longer produce an all-ready summary. Optional disabled preferences are not counted as denied OS permissions.
- Native preferences fetch the authenticated token and await the bridge; failure reports an error and restores the preference. iOS stop clears local collection before waiting for best-effort server revocation, without fetching a token. Settings synchronization emits no extra app activity ping.
- Refresh on visible/focus, preference changes and native active events, with late listener cleanup and generation protection against stale reads. Manual refresh remains available.
- One set of Me collection controls; the lower panel retains platform runtime/setup details.
- No database/schema/alert changes, new permission requests on inspection, Family Controls, background location, foreground-service policy changes or provider delegation.

## Verification and remaining gates

- Regression tests first reproduced unsupported controls, missing native synchronization, swallowed failure, and duplicated Me controls.
- Behavioral tests cover platform lists, initial summary, web revocation, Health uncertainty, missing/failed native bridges, system restrictions, native token synchronization, offline local stop order, desktop probe failure and listener cleanup.
- Final full Vitest: 101 files / 593 tests PASS (2026-09-19 20:50 +06:00).
- TypeScript check, final frontend build and `git diff --check` PASS. Existing bundle-size and mixed-import warnings remain; no new build failure.
- Brain lessons and lessons-watch checks PASS (2/2); sandbox child-process EPERM resolved by normal elevated read-only checker execution.
- Windows cannot compile UIKit/CoreMotion or validate OS permission panels. **New iOS bridge has NOT been Xcode-compiled or tested on an iPhone.** It requires an Xcode build before upload.
- No push, deployment, installer rebuild, TestFlight upload or physical-device validation for this candidate.

Device acceptance after a separately approved release: open Me; revoke and restore each applicable system permission; return to KC without restarting; compare the displayed state; test each collector switch against actual native events. Include iOS Low Power Mode/restrictions, denied Health access, Android silent mode/OEM power limits, installed-PWA notification revocation and Tauri probe failure. Do not create synthetic activity for real users.

## Platform sources

- Apple CMPedometer authorization: https://developer.apple.com/documentation/coremotion/cmpedometer/authorizationstatus()
- Apple motion activity authorization: https://developer.apple.com/documentation/coremotion/cmmotionactivitymanager/authorizationstatus()
- Apple Background App Refresh, including low-power and restricted states: https://developer.apple.com/documentation/uikit/uiapplication/backgroundrefreshstatus
- Apple Health read privacy: https://developer.apple.com/documentation/healthkit/hkauthorizationstatus
- WebKit installed iOS PWA push: https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/

Apple CoreMotion/UIKit Markdown bodies were fetched and read directly after the web reader rejected their Markdown content type. API names/signatures were not inferred from a JavaScript placeholder page.


---

