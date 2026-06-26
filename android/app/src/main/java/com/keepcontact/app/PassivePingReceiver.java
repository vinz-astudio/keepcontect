package com.keepcontact.app;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class PassivePingReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null || intent.getAction() == null) return;
        String action = intent.getAction();
        if (
            Intent.ACTION_POWER_CONNECTED.equals(action) ||
            Intent.ACTION_POWER_DISCONNECTED.equals(action) ||
            Intent.ACTION_USER_PRESENT.equals(action)
        ) {
            if (PassivePing.shouldPingForAction(context, action)) {
                PassivePing.ping(context);
            }
        }
    }
}
