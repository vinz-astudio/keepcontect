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
    private BroadcastReceiver chargingReceiver;

    @PluginMethod
    public void configure(PluginCall call) {
        String supabaseUrl = call.getString("supabaseUrl");
        String token = call.getString("token");
        Boolean allowChargingValue = call.getBoolean("allowCharging");
        Boolean allowUsageStatsValue = call.getBoolean("allowUsageStats");
        Boolean allowActivityRecognitionValue = call.getBoolean("allowActivityRecognition");

        boolean allowCharging = allowChargingValue != null && allowChargingValue;
        boolean allowUsageStats = allowUsageStatsValue != null && allowUsageStatsValue;
        boolean allowActivityRecognition = allowActivityRecognitionValue != null && allowActivityRecognitionValue;

        if (supabaseUrl == null || token == null || token.length() == 0) {
            call.reject("supabaseUrl and token are required");
            return;
        }

        PassivePing.configure(getContext(), supabaseUrl, token, allowCharging, allowUsageStats, allowActivityRecognition);
        refreshEventReceiver();

        // Logged in + configured -> keep the background notification poll alive.
        NotifyWorker.schedule(getContext());
        call.resolve(new JSObject());
    }

    @PluginMethod
    public void clear(PluginCall call) {
        unregisterEventReceiver();
        NotifyWorker.cancel(getContext());
        PassivePing.clear(getContext());
        call.resolve(new JSObject());
    }

    /** Android 13+ runtime request for POST_NOTIFICATIONS. */
    @PluginMethod
    public void requestNotificationPermission(PluginCall call) {
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            android.app.Activity activity = getActivity();
            if (activity != null &&
                androidx.core.content.ContextCompat.checkSelfPermission(
                    getContext(), "android.permission.POST_NOTIFICATIONS")
                    != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                androidx.core.app.ActivityCompat.requestPermissions(
                    activity, new String[] { "android.permission.POST_NOTIFICATIONS" }, 9010);
            }
        }
        call.resolve(new JSObject());
    }

    @PluginMethod
    public void pingApp(PluginCall call) {
        PassivePing.pingApp(getContext());
        call.resolve(new JSObject());
    }

    // —— Usage Stats Permission Bridge ——

    @PluginMethod
    public void isUsageStatsEnabled(PluginCall call) {
        JSObject ret = new JSObject();
        ret.put("enabled", PassivePing.isUsageAccessGranted(getContext()));
        call.resolve(ret);
    }

    @PluginMethod
    public void openUsageStatsSettings(PluginCall call) {
        Intent intent = new Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        getContext().startActivity(intent);
        call.resolve(new JSObject());
    }

    // —— Activity Recognition Permission Bridge ——

    @PluginMethod
    public void isActivityRecognitionEnabled(PluginCall call) {
        JSObject ret = new JSObject();
        ret.put("enabled", PassivePing.isActivityRecognitionGranted(getContext()));
        call.resolve(ret);
    }

    @PluginMethod
    public void requestActivityRecognitionPermission(PluginCall call) {
        if (android.os.Build.VERSION.SDK_INT >= 29) {
            android.app.Activity activity = getActivity();
            if (activity != null &&
                androidx.core.content.ContextCompat.checkSelfPermission(
                    getContext(), "android.permission.ACTIVITY_RECOGNITION")
                    != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                androidx.core.app.ActivityCompat.requestPermissions(
                    activity, new String[] { "android.permission.ACTIVITY_RECOGNITION" }, 9020);
            }
        }
        call.resolve(new JSObject());
    }

    /** Best-effort deep link to the OEM autostart whitelist (MIUI/HyperOS), falling back
     *  to the app-details page. */
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

    /** Guard liveness: returns status of permissions and foreground service liveness. */
    @PluginMethod
    public void getGuardStatus(PluginCall call) {
        Context context = getContext();
        JSObject ret = new JSObject();
        boolean usageGranted = PassivePing.isUsageAccessGranted(context);
        boolean activityGranted = PassivePing.isActivityRecognitionGranted(context);
        boolean serviceActive = PassivePing.serviceConnectedAt(context) > 0;

        ret.put("enabled", serviceActive);
        ret.put("connectedAt", PassivePing.serviceConnectedAt(context));
        // Use the last queryable active event time from UsageStats as the lastEventAt
        ret.put("lastEventAt", PassivePing.queryLastActiveTime(context));
        ret.put("lastPingAt", PassivePing.lastPingAt(context));
        ret.put("usageGranted", usageGranted);
        ret.put("activityGranted", activityGranted);
        call.resolve(ret);
    }

    // Keep legacy Accessibility methods as no-ops to avoid breaking old code if referenced
    @PluginMethod
    public void openAccessibilitySettings(PluginCall call) {
        call.resolve(new JSObject());
    }

    @PluginMethod
    public void isAccessibilityEnabled(PluginCall call) {
        JSObject ret = new JSObject();
        ret.put("enabled", false);
        call.resolve(ret);
    }

    @Override
    protected void handleOnResume() {
        refreshEventReceiver();
        PassivePing.updateBackgroundServices(getContext());
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
            // Already unregistered
        }
        return null;
    }
}
