package com.keepcontact.app;

import android.text.TextUtils;
import android.view.accessibility.AccessibilityEvent;
import android.accessibilityservice.AccessibilityService;

/**
 * Background liveness sensor for Android.
 *
 * Once the user grants the Accessibility permission, Android keeps this service
 * running independently of the app's main process — it survives the app being
 * killed and is restarted after reboot. That is exactly what the old USER_PRESENT
 * (unlock) runtime receiver could NOT do, so this replaces it as the reliable
 * background "the user is actively using the phone" signal.
 *
 * Privacy (Keep Contact's "judgement is fully offline" principle):
 *  - We only listen to TYPE_WINDOW_STATE_CHANGED and read the foreground app's
 *    package name to detect that *some* app came to the foreground.
 *  - The package name NEVER leaves the device. We only fire Keep Contact's
 *    existing content-free heartbeat ping (throttled), identical to every other
 *    passive signal. The server only learns "active at time T", not which app.
 *  - canRetrieveWindowContent is false in the config, so we cannot read screen
 *    content even if we wanted to.
 */
public class AppActivityService extends AccessibilityService {
    private String lastPackage = null;

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        // Liveness breadcrumb: proves the system actually bound the service
        // (HyperOS/MIUI can show the toggle ON while never binding).
        PassivePing.markGuardConnected(this);
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event == null) return;
        if (event.getEventType() != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return;
        PassivePing.markGuardEvent(this);

        CharSequence pkg = event.getPackageName();
        if (pkg == null || pkg.length() == 0) return;
        String pkgName = pkg.toString();

        // Only react when the foreground app actually changes — window-state events
        // fire often within one app, and the heartbeat is throttled anyway.
        if (TextUtils.equals(pkgName, lastPackage)) return;
        lastPackage = pkgName;

        // Ignore our own app and the system UI so the signal reflects real usage,
        // not Keep Contact opening itself or transient system overlays.
        if (pkgName.equals(getPackageName())) return;
        if (pkgName.equals("com.android.systemui")) return;

        // Fire the throttled, content-free heartbeat — only if the user enabled this
        // sensor and a heartbeat token is configured (i.e. they are logged in).
        if (PassivePing.isAppActivityAllowed(this)) {
            PassivePing.pingApp(this);
        }
    }

    @Override
    public void onInterrupt() {
        // No interruptible feedback to cancel.
    }
}
