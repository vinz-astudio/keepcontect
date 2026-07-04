package com.keepcontact.app;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.provider.Settings;
import androidx.core.content.ContextCompat;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

@CapacitorPlugin(name = "PassivePing")
public class PassivePingPlugin extends Plugin {
    // Charger events use a runtime receiver; unlock detection was removed (it only
    // worked while the process was alive) and replaced by AppActivityService.
    private BroadcastReceiver chargingReceiver;

    @PluginMethod
    public void configure(PluginCall call) {
        String supabaseUrl = call.getString("supabaseUrl");
        String token = call.getString("token");
        Boolean allowChargingValue = call.getBoolean("allowCharging");
        Boolean allowAppActivityValue = call.getBoolean("allowAppActivity");
        boolean allowCharging = allowChargingValue != null && allowChargingValue;
        boolean allowAppActivity = allowAppActivityValue != null && allowAppActivityValue;
        if (supabaseUrl == null || token == null || token.length() == 0) {
            call.reject("supabaseUrl and token are required");
            return;
        }
        PassivePing.configure(getContext(), supabaseUrl, token, allowCharging, allowAppActivity);
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

    /** Deep-link the user to the system Accessibility settings to enable AppActivityService. */
    @PluginMethod
    public void openAccessibilitySettings(PluginCall call) {
        Intent intent = new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        getContext().startActivity(intent);
        call.resolve(new JSObject());
    }

    /** Best-effort deep link to the OEM autostart whitelist (MIUI/HyperOS), falling back
     *  to the app-details page. Chinese ROMs kill background services (including
     *  accessibility) unless the app is whitelisted for autostart. */
    @PluginMethod
    public void openAutostartSettings(PluginCall call) {
        Context context = getContext();
        Intent miui = new Intent();
        miui.setClassName(
            "com.miui.securitycenter",
            "com.miui.permcenter.autostart.AutoStartManagementActivity");
        miui.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            context.startActivity(miui);
        } catch (Exception e) {
            Intent fallback = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
            fallback.setData(android.net.Uri.parse("package:" + context.getPackageName()));
            fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(fallback);
        }
        call.resolve(new JSObject());
    }

    /** Report whether our AppActivityService is currently enabled in system settings. */
    @PluginMethod
    public void isAccessibilityEnabled(PluginCall call) {
        JSObject ret = new JSObject();
        ret.put("enabled", isAccessibilityServiceEnabled());
        call.resolve(ret);
    }

    private boolean isAccessibilityServiceEnabled() {
        String enabled = Settings.Secure.getString(
            getContext().getContentResolver(),
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
        if (enabled == null || enabled.isEmpty()) return false;
        String pkg = getContext().getPackageName();
        return enabled.contains(pkg + "/" + AppActivityService.class.getName())
            || enabled.contains(pkg + "/.AppActivityService");
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
