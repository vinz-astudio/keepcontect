package com.keepcontact.app;

import android.os.Build;
import android.os.Bundle;
import android.content.Intent;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(PassivePingPlugin.class);
        // A concern's full-screen intent launches this activity from a locked
        // screen. Without these the system would hold it behind the keyguard,
        // so the screen would stay dark and the notification would sit unseen —
        // which is exactly what the alert ladder is trying to prevent.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true);
            setTurnScreenOn(true);
        }
        // Created here rather than on the first poll: a `concern` push arriving
        // before the channel exists would be filed under a default-importance
        // channel, which shows no heads-up banner and makes no sound — the two
        // things that make it reach someone whose phone is face-down.
        NotifyWorker.ensureChannel(this);
        NotificationActionQueue.capture(this, getIntent());
        super.onCreate(savedInstanceState);
    }

    @Override
    protected void onNewIntent(Intent intent) {
        setIntent(intent);
        NotificationActionQueue.capture(this, intent);
        super.onNewIntent(intent);
    }
}
