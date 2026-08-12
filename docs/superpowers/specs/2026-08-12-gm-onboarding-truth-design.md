# GM and Native Onboarding Truth Design

## Outcome

GM must not label a native phone `device_dark` while canonical recent coverage proves its collector is still reporting. Native onboarding must describe and verify the permissions and collector states the shipped Android APK/AAB and TestFlight iOS builds actually use.

## Evidence and constraints

- Android 0.6.0 is producing coverage about every 17 minutes, with no open protection-health incident.
- iOS 0.6.0 is producing silent-push and HealthKit wakes, but its tail is irregular and must remain described as best effort.
- `alert_observation_coverage_intervals.activity_coverage_state = 'valid'` is canonical coverage truth. A valid interval ending within 26 hours matches the existing protection-health staleness window.
- The live learning rebuild runs daily but currently does not filter gaps by coverage. Onboarding must not claim that learning is fully coverage-qualified.
- Apple does not reveal denial of HealthKit read permission. UI may say the authorization sheet was handled and the observer was armed, but not that Health read access was granted.
- APK and AAB share one Android codebase. Android Play constraints require honest degradation, prominent Usage Access disclosure, and no assumption that battery exemption or OEM autostart is universal.
- The accepted 2026-08-10 decision removed background location as an iOS relaunch mechanism. No native background-location request may remain.

## Design

### GM classification

`gm_list_clients()` keeps existing behavior bands and alert precedence. Its `silence_kind` discriminator becomes:

1. Recent behavior within six hours: `null`.
2. A canonical valid coverage interval ending within 26 hours: `person_quiet`.
3. Otherwise, preserve the legacy Web/PWA fallback: fresh device heartbeat within one hour means `person_quiet`; missing heartbeat means `unknown`; stale heartbeat means `device_dark`.

No alert, escalation, protection-health, learning, or collector behavior changes.

### Permission truth

The native bridge exposes `getNotificationPermissionStatus()` on Android and iOS. Onboarding considers notifications ready only when both the OS authorization is granted and a native FCM token exists. A granted permission with no token is shown as unverified, not as an action that can be repaired by asking again.

Android onboarding classifies:

- Required: notifications, Usage Access, connected background guard.
- Recommended: Activity Recognition, battery-optimization exemption, OEM autostart review.

Only required items gate Ready. Coverage already proves that an APK installation with Usage Access and its worker operational can report; recommended items improve evidence density or OEM resilience but are not universal prerequisites.

iOS onboarding classifies:

- Required: notifications and connected background guard.
- Recommended: Health movement wake.

Health authorization is requested only from the explicit onboarding action, after the explanatory row is visible. `asked + observing` is labelled `Set up`, not `Allowed`. It does not independently prove background delivery; the result page says the OS may delay updates.

### Copy

The welcome screen says Keep Contact records coarse activity timestamps and gradually learns usual quiet gaps. It explicitly avoids claiming that missing evidence proves danger or that the model is coverage-qualified.

The Ready result says required settings are on and that the app will continue checking the collector, with OS-delivery delays possible. It no longer promises that the phone continuously keeps a safety status up to date.

### iOS location cleanup

Remove CoreLocation ownership, Always authorization, significant-change monitoring, and related delegate callbacks from `PassiveGuard`. Foreground SOS location remains owned elsewhere and retains `NSLocationWhenInUseUsageDescription`.

## Verification

- pgTAP regression proves recent valid coverage wins over stale heartbeat for both `ios-app` and `android-apk`, while expired/no coverage uses the legacy fallback.
- Vitest proves permission/readiness classification and honest result copy.
- Platform contract test proves iOS contains no background-location request or significant-change monitor.
- Typecheck, full Vitest, local database replay/pgTAP where available, Android unit tests, Android release APK/AAB build, and web build pass.
- A rendered 390×844 onboarding comparison is visually inspected against the pre-change screenshots.

## Non-scope

- No production migration, deployment, TestFlight upload, APK/AAB publication, or store-console change.
- No change to learning authority, thresholds, alerts, protection-health evaluation, or coverage cadence.
- No server-RPC readiness wait in onboarding.

