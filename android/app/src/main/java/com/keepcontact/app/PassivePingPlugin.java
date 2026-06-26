package com.keepcontact.app;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import androidx.core.content.ContextCompat;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

@CapacitorPlugin(name = "PassivePing")
public class PassivePingPlugin extends Plugin {
    private BroadcastReceiver eventReceiver;

    @PluginMethod
    public void configure(PluginCall call) {
        String supabaseUrl = call.getString("supabaseUrl");
        String token = call.getString("token");
        Boolean allowUnlockValue = call.getBoolean("allowUnlock");
        Boolean allowChargingValue = call.getBoolean("allowCharging");
        boolean allowUnlock = allowUnlockValue != null && allowUnlockValue;
        boolean allowCharging = allowChargingValue != null && allowChargingValue;
        if (supabaseUrl == null || token == null || token.length() == 0) {
            call.reject("supabaseUrl and token are required");
            return;
        }
        PassivePing.configure(getContext(), supabaseUrl, token, allowUnlock, allowCharging);
        refreshEventReceiver();
        call.resolve(new JSObject());
    }

    @PluginMethod
    public void clear(PluginCall call) {
        unregisterEventReceiver();
        PassivePing.clear(getContext());
        call.resolve(new JSObject());
    }

    @PluginMethod
    public void pingApp(PluginCall call) {
        PassivePing.pingApp(getContext());
        call.resolve(new JSObject());
    }

    @Override
    protected void handleOnResume() {
        refreshEventReceiver();
        PassivePing.pingApp(getContext());
    }

    @Override
    protected void handleOnDestroy() {
        unregisterEventReceiver();
    }

    private void refreshEventReceiver() {
        unregisterEventReceiver();
        Context context = getContext();
        IntentFilter filter = PassivePing.eventIntentFilter(context);
        if (filter.countActions() == 0) return;

        eventReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context receiverContext, Intent intent) {
                if (intent == null) return;
                String action = intent.getAction();
                if (PassivePing.shouldPingForAction(receiverContext, action)) {
                    PassivePing.ping(receiverContext);
                }
            }
        };
        ContextCompat.registerReceiver(context, eventReceiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED);
    }

    private void unregisterEventReceiver() {
        if (eventReceiver == null) return;
        try {
            getContext().unregisterReceiver(eventReceiver);
        } catch (IllegalArgumentException ignored) {
            // Receiver was already gone with the Activity context.
        } finally {
            eventReceiver = null;
        }
    }
}
