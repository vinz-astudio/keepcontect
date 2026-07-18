package com.keepcontact.app;

import android.app.AppOpsManager;
import android.app.PendingIntent;
import android.app.usage.UsageEvents;
import android.app.usage.UsageStatsManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;
import android.util.Log;
import androidx.core.content.ContextCompat;
import com.google.android.gms.location.ActivityRecognition;
import com.google.android.gms.location.ActivityTransition;
import com.google.android.gms.location.ActivityTransitionRequest;
import com.google.android.gms.location.DetectedActivity;
import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

final class PassivePing {
    private static final String TAG = "KeepContactPassive";
    private static final String PREFS = "keep_contact_passive";
    private static final String KEY_SUPABASE_URL = "supabase_url";
    private static final String KEY_TOKEN = "token";
    private static final String KEY_LAST_PING = "last_ping";
    private static final String KEY_ALLOW_USAGE_STATS = "allow_usage_stats";
    private static final String KEY_ALLOW_ACTIVITY_RECOGNITION = "allow_activity_recognition";
    private static final String KEY_ALLOW_CHARGING = "allow_charging";
    private static final long APP_THROTTLE_MS = 5 * 60 * 1000;
    private static final ExecutorService EXECUTOR = Executors.newSingleThreadExecutor();

    private PassivePing() {}

    static void configure(Context context, String supabaseUrl, String token, boolean allowCharging, boolean allowUsageStats, boolean allowActivityRecognition) {
        prefs(context)
            .edit()
            .putString(KEY_SUPABASE_URL, trimSlash(supabaseUrl))
            .putString(KEY_TOKEN, token)
            .putBoolean(KEY_ALLOW_CHARGING, allowCharging)
            .putBoolean(KEY_ALLOW_USAGE_STATS, allowUsageStats)
            .putBoolean(KEY_ALLOW_ACTIVITY_RECOGNITION, allowActivityRecognition)
            .apply();

        updateBackgroundServices(context);
    }

    static void clear(Context context) {
        // Stop any active foreground service & activity transition listeners first
        stopForegroundService(context);
        try {
            updateActivityTransitions(context, false);
        } catch (Exception e) {
            Log.e(TAG, "Failed to unregister transitions on clear", e);
        }
        prefs(context).edit().clear().apply();
    }

    static void ping(Context context) {
        ping(context, 0);
    }

    static void pingApp(Context context) {
        ping(context, APP_THROTTLE_MS);
    }

    static boolean isConfigured(Context context) {
        SharedPreferences prefs = prefs(context);
        String base = prefs.getString(KEY_SUPABASE_URL, null);
        String token = prefs.getString(KEY_TOKEN, null);
        return base != null && token != null && token.length() > 0;
    }

    static boolean shouldPingForAction(Context context, String action) {
        if (!isConfigured(context) || action == null) return false;
        SharedPreferences prefs = prefs(context);
        if (Intent.ACTION_POWER_CONNECTED.equals(action) || Intent.ACTION_POWER_DISCONNECTED.equals(action)) {
            return prefs.getBoolean(KEY_ALLOW_CHARGING, false);
        }
        return false;
    }

    static boolean isUsageStatsAllowed(Context context) {
        return isConfigured(context) && prefs(context).getBoolean(KEY_ALLOW_USAGE_STATS, false);
    }

    static boolean isActivityRecognitionAllowed(Context context) {
        return isConfigured(context) && prefs(context).getBoolean(KEY_ALLOW_ACTIVITY_RECOGNITION, false);
    }

    // —— Permission Check Helpers ——

    static boolean isUsageAccessGranted(Context context) {
        try {
            AppOpsManager appOps = (AppOpsManager) context.getSystemService(Context.APP_OPS_SERVICE);
            if (appOps == null) return false;
            int mode = appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(), context.getPackageName());
            return mode == AppOpsManager.MODE_ALLOWED;
        } catch (Exception e) {
            return false;
        }
    }

    static boolean isActivityRecognitionGranted(Context context) {
        if (Build.VERSION.SDK_INT >= 29) {
            return ContextCompat.checkSelfPermission(context, "android.permission.ACTIVITY_RECOGNITION")
                == PackageManager.PERMISSION_GRANTED;
        }
        return true; // Auto-granted below API 29
    }

    // —— Usage Stats Scanner (Event-driven/Interval check) ——

    static long queryLastActiveTime(Context context) {
        if (!isUsageAccessGranted(context)) return 0;
        try {
            UsageStatsManager usm = (UsageStatsManager) context.getSystemService(Context.USAGE_STATS_SERVICE);
            if (usm == null) return 0;

            long now = System.currentTimeMillis();
            // Query only the last 24 hours of events
            UsageEvents usageEvents = usm.queryEvents(now - 24 * 60 * 60 * 1000, now);
            UsageEvents.Event event = new UsageEvents.Event();
            long lastActiveTime = 0;

            while (usageEvents.hasNextEvent()) {
                usageEvents.getNextEvent(event);
                int eventType = event.getEventType();
                // ACTIVITY_RESUMED (1), USER_INTERACTION (7), KEYGUARD_HIDDEN (18)
                if (eventType == UsageEvents.Event.ACTIVITY_RESUMED
                    || eventType == UsageEvents.Event.USER_INTERACTION
                    || eventType == UsageEvents.Event.KEYGUARD_HIDDEN) {
                    if (event.getTimeStamp() > lastActiveTime) {
                        lastActiveTime = event.getTimeStamp();
                    }
                }
            }
            return lastActiveTime;
        } catch (Exception e) {
            Log.e(TAG, "Failed to query usage stats events", e);
            return 0;
        }
    }

    // —— Foreground Service & GMS transition lifecycle managers ——

    static void updateBackgroundServices(Context context) {
        boolean configured = isConfigured(context);
        boolean needsService = false;

        if (configured) {
            boolean usageStatsActive = isUsageStatsAllowed(context) && isUsageAccessGranted(context);
            boolean activityRecognitionActive = isActivityRecognitionAllowed(context) && isActivityRecognitionGranted(context);
            needsService = usageStatsActive || activityRecognitionActive;

            // Update GMS Activity Recognition transitions
            try {
                updateActivityTransitions(context, activityRecognitionActive);
            } catch (Exception e) {
                Log.e(TAG, "Failed to update activity transitions", e);
            }
        }

        if (needsService) {
            startForegroundService(context);
        } else {
            stopForegroundService(context);
        }
    }

    private static void startForegroundService(Context context) {
        try {
            KcForegroundService.start(context);
            prefs(context).edit().putLong("service_connected_at", System.currentTimeMillis()).apply();
        } catch (Exception e) {
            Log.e(TAG, "Failed to start KcForegroundService", e);
        }
    }

    private static void stopForegroundService(Context context) {
        try {
            KcForegroundService.stop(context);
        } catch (Exception e) {
            Log.e(TAG, "Failed to stop KcForegroundService", e);
        }
    }

    private static void updateActivityTransitions(Context context, boolean enable) {
        try {
            if (Build.VERSION.SDK_INT >= 29
                && ContextCompat.checkSelfPermission(
                    context,
                    android.Manifest.permission.ACTIVITY_RECOGNITION
                ) != PackageManager.PERMISSION_GRANTED) {
                Log.w(TAG, "Activity recognition permission not granted; skipping transition update");
                return;
            }

            Intent intent = new Intent(context, ActivityTransitionReceiver.class);
            intent.setAction("com.keepcontact.app.ACTION_PROCESS_ACTIVITY_TRANSITIONS");
            // Must specify FLAG_MUTABLE starting with Android 12 for GMS PendingIntents
            int flags = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                flags |= PendingIntent.FLAG_MUTABLE;
            }
            PendingIntent pendingIntent = PendingIntent.getBroadcast(context, 9030, intent, flags);

            if (enable) {
                List<ActivityTransition> transitions = new ArrayList<>();
                int[] activities = {DetectedActivity.STILL, DetectedActivity.WALKING, DetectedActivity.RUNNING};
                for (int activity : activities) {
                    transitions.add(new ActivityTransition.Builder()
                        .setActivityType(activity)
                        .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                        .build());
                    transitions.add(new ActivityTransition.Builder()
                        .setActivityType(activity)
                        .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_EXIT)
                        .build());
                }

                ActivityTransitionRequest request = new ActivityTransitionRequest(transitions);
                ActivityRecognition.getClient(context)
                    .requestActivityTransitionUpdates(request, pendingIntent)
                    .addOnSuccessListener(aVoid -> Log.d(TAG, "GMS Transitions registered successfully"))
                    .addOnFailureListener(e -> Log.e(TAG, "Failed to register GMS transitions", e));
            } else {
                ActivityRecognition.getClient(context)
                    .removeActivityTransitionUpdates(pendingIntent)
                    .addOnCompleteListener(task -> Log.d(TAG, "GMS Transitions removed"));
            }
        } catch (Exception e) {
            Log.e(TAG, "Error in GMS transitions setup", e);
        }
    }

    // —— Liveness Instrumentation for UI ——

    static long serviceConnectedAt(Context context) {
        return prefs(context).getLong("service_connected_at", 0);
    }

    static long lastPingAt(Context context) {
        return prefs(context).getLong(KEY_LAST_PING, 0);
    }

    // —— Charging Receiver Helpers ——

    static IntentFilter chargingIntentFilter(Context context) {
        SharedPreferences prefs = prefs(context);
        IntentFilter filter = new IntentFilter();
        if (isConfigured(context) && prefs.getBoolean(KEY_ALLOW_CHARGING, false)) {
            filter.addAction(Intent.ACTION_POWER_CONNECTED);
            filter.addAction(Intent.ACTION_POWER_DISCONNECTED);
        }
        return filter;
    }

    static void ping(Context context, long throttleMs) {
        Context appContext = context.getApplicationContext();
        SharedPreferences prefs = prefs(appContext);
        String base = prefs.getString(KEY_SUPABASE_URL, null);
        String token = prefs.getString(KEY_TOKEN, null);
        if (base == null || token == null || token.length() == 0) return;

        long now = System.currentTimeMillis();
        if (throttleMs > 0 && now - prefs.getLong(KEY_LAST_PING, 0) < throttleMs) return;

        EXECUTOR.execute(() -> {
            HttpURLConnection conn = null;
            try {
                long t = System.currentTimeMillis() / 1000;
                String sig = calculateHMAC(String.valueOf(t), token);
                String url =
                    base +
                    "/functions/v1/ping?token=" +
                    URLEncoder.encode(token, StandardCharsets.UTF_8.name()) +
                    "&source=capacitor" +
                    "&t=" + t +
                    "&sig=" + URLEncoder.encode(sig, StandardCharsets.UTF_8.name());
                conn = (HttpURLConnection) new URL(url).openConnection();
                conn.setConnectTimeout(8000);
                conn.setReadTimeout(8000);
                conn.setRequestMethod("GET");
                int code = conn.getResponseCode();
                if (code < 400) {
                    prefs.edit().putLong(KEY_LAST_PING, now).apply();
                }
                InputStream stream = code >= 400 ? conn.getErrorStream() : conn.getInputStream();
                if (stream != null) {
                    try (BufferedReader ignored = new BufferedReader(new InputStreamReader(stream))) {
                        while (ignored.readLine() != null) {
                            // Drain response so the connection can close cleanly.
                        }
                    }
                }
            } catch (Exception e) {
                Log.d(TAG, "passive ping failed", e);
            } finally {
                if (conn != null) conn.disconnect();
            }
        });
    }

    static String calculateHMAC(String data, String key) {
        try {
            javax.crypto.spec.SecretKeySpec signingKey = new javax.crypto.spec.SecretKeySpec(key.getBytes(StandardCharsets.UTF_8), "HmacSHA256");
            javax.crypto.Mac mac = javax.crypto.Mac.getInstance("HmacSHA256");
            mac.init(signingKey);
            byte[] rawHmac = mac.doFinal(data.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder(rawHmac.length * 2);
            for (byte b : rawHmac) {
                sb.append(String.format("%02x", b));
            }
            return sb.toString();
        } catch (Exception e) {
            Log.e(TAG, "Failed to calculate HMAC", e);
            return "";
        }
    }

    private static SharedPreferences prefs(Context context) {
        return context.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private static String trimSlash(String value) {
        if (value.endsWith("/")) return value.substring(0, value.length() - 1);
        return value;
    }
}
