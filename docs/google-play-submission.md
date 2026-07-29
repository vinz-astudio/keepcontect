# Google Play Store Submission Guide & Declaration Materials

This document provides copy-paste ready materials for submitting **Keep Contact** to Google Play Console.

---

## 1. Store Listing Information (应用商店信息)

### App Name / 应用名称 (Max 30 chars)
`Keep Contact: Safety Monitor` (or `Keep Contact 独居安全守护`)

### Short Description / 简短描述 (Max 80 chars)
`Automated, calm safety & liveness check-ins for lone dwellers and elderly family.`

### Full Description / 详细描述 (Max 4000 chars)
```text
Keep Contact is a calm, privacy-first safety and liveness monitoring companion designed for lone dwellers, elderly relatives, and individuals living alone.

Key Features:
• Passive Liveness Checks: Detects routine device activity (screen wakes, charger connections) without requiring manual daily check-ins.
• Calm Safeguard: Zero intrusive popups or invasive surveillance. Respects your privacy and runs quietly in the background.
• Emergency Guardian Alerts: Automatically notifies designated family members or trusted contacts if no activity is detected after your customized threshold.
• Fast SOS Trigger: One-tap emergency dispatch for immediate help when you need it most.
• Cross-Platform Sync: Works seamlessly across Android and web.

Privacy & Security Promise:
We respect your privacy. Keep Contact DOES NOT record, store, or transmit your private messages, screen content, browsed websites, photos, or physical location logs. All data is encrypted in transit and stored securely.

Required Permissions:
- Foreground Service (specialUse): Runs a background monitoring service to ensure continuous 24/7 safety checks for lone dwellers.
- Usage Access (Optional): Used solely to check timestamps of device usage to confirm user safety.
```

---

## 2. Foreground Service (FGS) Declaration for Google Play Console
When prompted for FGS Permission `FOREGROUND_SERVICE_SPECIAL_USE` in Play Console:

- **FGS Category:** `specialUse`
- **Subtype Value:** `Emergency and personal safety monitoring for lone dwellers`
- **Justification Text for Google Reviewer (Copy & Paste):**
```text
Keep Contact provides automated 24/7 safety and liveness monitoring for individuals living alone and vulnerable users. The Foreground Service (KcForegroundService) is required to dynamically listen for passive liveness events (such as screen unlock and charging connections) and maintain active heartbeats. Without this continuous foreground service, Android battery optimization would kill the process, preventing timely emergency alerts to designated guardians if a lone dweller becomes incapacitated.
```
- **Demo Video Requirements:**
  Provide an unedited video link showing:
  1. App launching with ongoing notification "Passive guard is active".
  2. User locking and unlocking screen.
  3. Passive status updating in app.

---

## 3. Data Safety Form Answers (数据安全问卷答案)

In Play Console -> App Content -> Data Safety:

1. **Does your app collect or share user data?**
   - Answer: **Yes**

2. **Is all user data encrypted in transit?**
   - Answer: **Yes** (All requests use HTTPS/TLS)

3. **Do you provide a way for users to request data deletion?**
   - Answer: **Yes**
   - URL: `https://keep-contact-mauve.vercel.app/delete-account`

4. **Data Types Collected & Purpose:**
   - **Personal Info -> Email Address:** Collected for Account Management & Guardian Notifications.
   - **App Activity -> App interactions:** Timestamp of last active event for Liveness & Safety Check.
   - **Device or other IDs -> Device ID:** Collected for multi-device sync.

---

## 4. Submission Checklist (上架前的最终检查清单)

- [x] Privacy Policy Web URL active (`https://keep-contact-mauve.vercel.app/privacy`)
- [x] Data Deletion Request Web URL active (`https://keep-contact-mauve.vercel.app/delete-account`)
- [x] Signed Production APK / AAB built (`keep-contact-v0.5.21.apk`)
- [x] Accessibility Service permission completely removed (`BIND_ACCESSIBILITY_SERVICE` removed)
- [x] FGS `specialUse` subtype declared in AndroidManifest.xml
