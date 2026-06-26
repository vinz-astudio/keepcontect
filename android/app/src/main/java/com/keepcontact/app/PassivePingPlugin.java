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
    // Split so USER_PRESENT (SystemUI uid) can be exported while charger stays not-exported.
    private BroadcastReceiver chargingReceiver;
    private BroadcastReceiver unlockReceiver;

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

        IntentFilter chargingFilter = PassivePing.chargingIntentFilter(context);
        if (chargingFilter.countActions() > 0) {
            chargingReceiver = buildReceiver();
            ContextCompat.registerReceiver(
                context, chargingReceiver, chargingFilter, ContextCompat.RECEIVER_NOT_EXPORTED);
        }

        IntentFilter unlockFilter = PassivePing.unlockIntentFilter(context);
        if (unlockFilter.countActions() > 0) {
            unlockReceiver = buildReceiver();
            // EXPORTED is required: USER_PRESENT comes from SystemUI, not the system uid.
            ContextCompat.registerReceiver(
                context, unlockReceiver, unlockFilter, ContextCompat.RECEIVER_EXPORTED);
        }
    }

    private BroadcastReceiver buildReceiver() {
        return new BroadcastReceiver() {
            @Override
            public void onReceive(Context receiverContext, Intent intent) {
                if (intent == null) return;
                String action = intent.getAction();
                android.util.Log.d("KeepContactPassive", "receiver onReceive: " + action);
                if (PassivePing.shouldPingForAction(receiverContext, action)) {
                    PassivePing.ping(receiverContext);
                }
            }
        };
    }

    private void unregisterEventReceiver() {
        chargingReceiver = unregister(chargingReceiver);
        unlockReceiver = unregister(unlockReceiver);
    }

    private BroadcastReceiver unregister(BroadcastReceiver receiver) {
        if (receiver == null) return null;
        try {
            getContext().unregisterReceiver(receiver);
        } catch (IllegalArgumentException ignored) {
            // Receiver was already gone with the Activity context.
        }
        return null;
    }
}
