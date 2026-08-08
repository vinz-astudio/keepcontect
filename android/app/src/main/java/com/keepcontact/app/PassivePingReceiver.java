package com.keepcontact.app;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class PassivePingReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null || intent.getAction() == null) return;
        String action = intent.getAction();

        if (Intent.ACTION_BOOT_COMPLETED.equals(action) ||
            "android.intent.action.MY_PACKAGE_REPLACED".equals(action)) {
            PassivePing.updateBackgroundServices(context);
            return;
        }

        // Only the fallback guard needs reviving here. In silent mode there is no
        // service to keep alive: the periodic look-back at usage history is what
        // carries liveness, and it needs nothing running in between.
        if (PassivePing.isConfigured(context)
            && PassivePing.GUARD_PERSISTENT.equals(PassivePing.guardMode(context))) {
            KcForegroundService.start(context);
        }

        if (
            Intent.ACTION_POWER_CONNECTED.equals(action) ||
            Intent.ACTION_POWER_DISCONNECTED.equals(action) ||
            Intent.ACTION_USER_PRESENT.equals(action)
        ) {
            if (PassivePing.shouldPingForAction(context, action)) {
                PassivePing.pingApp(context);
            }
        }
    }
}
