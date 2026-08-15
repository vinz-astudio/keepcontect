package com.keepcontact.app;

import android.app.AppOpsManager;
import android.app.PendingIntent;
import android.app.usage.UsageEvents;
import android.app.usage.UsageStats;
import android.app.usage.UsageStatsManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.BatteryManager;
import android.os.SystemClock;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
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
import java.security.KeyStore;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import org.json.JSONArray;

final class PassivePing {
    private static final String TAG = "KeepContactPassive";
    private static final String PREFS = "keep_contact_passive";
    private static final String KEY_SUPABASE_URL = "supabase_url";
    private static final String KEY_TOKEN = "token";
    private static final String KEY_LAST_PING = "last_ping";
    private static final String KEY_ALLOW_USAGE_STATS = "allow_usage_stats";
    private static final String KEY_ALLOW_ACTIVITY_RECOGNITION = "allow_activity_recognition";
    private static final String KEY_ALLOW_CHARGING = "allow_charging";
    private static final String KEY_CLIENT_ID = "client_id";
    private static final String KEY_APP_VERSION = "app_version";
    private static final String KEY_COLLECTOR_CONTRACT = "collector_contract";
    private static final String KEY_LAST_SHADOW_COVERAGE_LEASE_AT =
        "last_shadow_coverage_lease_at";
    private static final String KEY_EVIDENCE_BINDING_ID = "evidence_binding_id";
    private static final String KEY_EVIDENCE_CONTRACT = "evidence_contract";
    private static final String KEY_EVIDENCE_CREDENTIAL_CIPHER = "evidence_credential_cipher";
    private static final String KEY_EVIDENCE_CREDENTIAL_IV = "evidence_credential_iv";
    private static final String KEY_EVIDENCE_NEXT_SEQUENCE = "evidence_next_sequence";
    private static final String KEY_EVIDENCE_QUEUE = "evidence_queue";
    private static final String KEY_LAST_USAGE_EVIDENCE_AT = "last_usage_evidence_at";
    private static final String KEY_LAST_USAGE_QUERY_END = "last_usage_query_end";
    private static final String KEY_POWER_STABLE_STATE = "power_stable_state";
    private static final String KEY_POWER_PENDING_STATE = "power_pending_state";
    private static final String KEY_POWER_PENDING_SINCE = "power_pending_since";
    private static final String KEY_POWER_CORRELATION_ID = "power_correlation_id";
    private static final String KEY_POWER_CORRELATION_STARTED = "power_correlation_started";
    private static final String EVIDENCE_KEY_ALIAS = "keep_contact_passive_evidence_v1";
    private static final long APP_THROTTLE_MS = 5 * 60 * 1000;
    private static final ExecutorService EXECUTOR = Executors.newSingleThreadExecutor();
    private static final ScheduledExecutorService SCHEDULER =
        Executors.newSingleThreadScheduledExecutor();

    private PassivePing() {}

    static void configure(
        Context context,
        String supabaseUrl,
        String token,
        boolean allowCharging,
        boolean allowUsageStats,
        boolean allowActivityRecognition,
        String clientId,
        String appVersion,
        String collectorContract,
        String evidenceBindingId,
        String evidenceCredential,
        String evidenceCollectorContract
    ) {
        SharedPreferences prefs = prefs(context);
        prefs
            .edit()
            .putString(KEY_SUPABASE_URL, trimSlash(supabaseUrl))
            .putString(KEY_TOKEN, token)
            .putBoolean(KEY_ALLOW_CHARGING, allowCharging)
            .putBoolean(KEY_ALLOW_USAGE_STATS, allowUsageStats)
            .putBoolean(KEY_ALLOW_ACTIVITY_RECOGNITION, allowActivityRecognition)
            .putString(KEY_CLIENT_ID, clientId)
            .putString(KEY_APP_VERSION, appVersion)
            .putString(KEY_COLLECTOR_CONTRACT, collectorContract)
            .apply();

        configureEvidenceBinding(
            context, evidenceBindingId, evidenceCredential, evidenceCollectorContract);
        initializePowerBaseline(context);

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
        clearEvidenceBinding(context);
        prefs(context).edit().clear().apply();
    }

    // —— Guard mode ——
    //
    // KC used to hold a foreground service permanently, which meant an ongoing
    // notification the user could not get rid of. That service's only unique
    // contribution was pinging at the instant of an unlock: ACTION_USER_PRESENT
    // is not an exempt implicit broadcast, so catching it live needs a resident
    // process. But instant was never worth anything here — the alert model
    // groups activity into thirty-minute sessions and judges silence in hours —
    // and Android will tell us *when the device was last used* after the fact,
    // which NotifyWorker already reads every fifteen minutes.
    //
    // So the guard sleeps. The service now exists only as a fallback for devices
    // that will not let a sleeping app wake up again. From 2026-03-01 Google Play
    // also penalises apps that hold wake locks excessively, so staying resident
    // stopped being merely rude and became a distribution risk.
    private static final String KEY_GUARD_MODE = "guard_mode";
    private static final String KEY_MISSED_WAKEUPS = "guard_missed_wakeups";
    private static final String KEY_DEMOTION_PENDING = "guard_demotion_pending";
    static final String GUARD_SILENT = "silent";
    static final String GUARD_PERSISTENT = "persistent";

    /** How many overdue wake-ups before KC accepts that this device kills it. */
    private static final int DEMOTE_AFTER_MISSED = 3;

    static String guardMode(Context context) {
        return prefs(context).getString(KEY_GUARD_MODE, GUARD_SILENT);
    }

    /**
     * Records whether the periodic wake-up arrived when it should have.
     *
     * A device that freezes KC produces no ping and no complaint — the guard
     * simply stops, and stopping looks exactly like the user being silent, which
     * is how a frozen phone turns into a false alarm for somebody's family. So
     * KC watches its own heartbeat rather than the user's device settings, and
     * demotes itself to the visible guard once the evidence is unambiguous.
     *
     * Detecting it does not act on it. Becoming visible is a change the user can
     * see and did not choose, so it is raised as a request the next time they
     * open KC rather than applied behind their back — the app promised to stay
     * out of the way, and quietly breaking that promise is worse than asking.
     * No notification is posted for this; it waits in the app.
     */
    static void recordWakeupPunctuality(Context context, boolean onTime) {
        if (GUARD_PERSISTENT.equals(guardMode(context))) return;
        SharedPreferences prefs = prefs(context);
        if (prefs.getBoolean(KEY_DEMOTION_PENDING, false)) return;
        int missed = onTime ? 0 : prefs.getInt(KEY_MISSED_WAKEUPS, 0) + 1;
        if (missed >= DEMOTE_AFTER_MISSED) {
            prefs.edit()
                .putBoolean(KEY_DEMOTION_PENDING, true)
                .putInt(KEY_MISSED_WAKEUPS, 0)
                .apply();
            Log.i(TAG, "Guard demotion proposed: " + missed + " missed wake-ups");
            return;
        }
        prefs.edit().putInt(KEY_MISSED_WAKEUPS, missed).apply();
    }

    /** Whether KC has concluded this device freezes it and is waiting to ask. */
    static boolean isDemotionPending(Context context) {
        return prefs(context).getBoolean(KEY_DEMOTION_PENDING, false);
    }

    /**
     * The user's answer to that request.
     *
     * Declining is a real answer, not a deferral: the question is cleared and
     * KC stays invisible. It will keep missing wake-ups and keep reporting less
     * often, and that is the user's call to make about their own phone.
     */
    static void resolveDemotion(Context context, boolean accepted) {
        prefs(context).edit()
            .putBoolean(KEY_DEMOTION_PENDING, false)
            .putString(KEY_GUARD_MODE, accepted ? GUARD_PERSISTENT : GUARD_SILENT)
            .apply();
        updateBackgroundServices(context);
    }

    static void ping(Context context) {
        ping(context, 0);
    }

    static void pingApp(Context context) {
        ping(context, 0);
    }

    static boolean isConfigured(Context context) {
        SharedPreferences prefs = prefs(context);
        String base = prefs.getString(KEY_SUPABASE_URL, null);
        String token = prefs.getString(KEY_TOKEN, null);
        return base != null && token != null && token.length() > 0;
    }

    static boolean isKeyguardLocked(Context context) {
        try {
            android.app.KeyguardManager km = (android.app.KeyguardManager) context.getSystemService(Context.KEYGUARD_SERVICE);
            return km != null && km.isKeyguardLocked();
        } catch (Exception e) {
            return false;
        }
    }

    static boolean shouldPingForAction(Context context, String action) {
        if (!isConfigured(context) || action == null) return false;
        SharedPreferences prefs = prefs(context);
        if (Intent.ACTION_POWER_CONNECTED.equals(action) || Intent.ACTION_POWER_DISCONNECTED.equals(action)) {
            // Charging is a liveness signal even while the keyguard is locked:
            // plugging a cable in is a hand-on-device event. The keyguard gate
            // below exists only for USER_PRESENT-style actions.
            return prefs.getBoolean(KEY_ALLOW_CHARGING, false);
        }
        if (Intent.ACTION_USER_PRESENT.equals(action)) {
            // Never allow passive ping action when the keyguard is still locked (e.g. pulling down quick settings)
            if (isKeyguardLocked(context)) {
                return false;
            }
            return prefs.getBoolean(KEY_ALLOW_USAGE_STATS, false);
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
            if (appOps != null) {
                int mode;
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    mode = appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS,
                        android.os.Process.myUid(), context.getPackageName());
                } else {
                    mode = appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS,
                        android.os.Process.myUid(), context.getPackageName());
                }
                if (mode == AppOpsManager.MODE_ALLOWED) {
                    return true;
                }
            }
            // Fallback check for OEM ROMs (MIUI/HyperOS/ColorOS/OriginOS/OneUI)
            long now = System.currentTimeMillis();
            UsageStatsManager usm = (UsageStatsManager) context.getSystemService(Context.USAGE_STATS_SERVICE);
            if (usm != null) {
                List<UsageStats> stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, now - 1000 * 60 * 60, now);
                return stats != null && !stats.isEmpty();
            }
            return false;
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

    static PassiveEvidenceContract.Evidence queryLatestUsageEvidence(Context context) {
        if (!isEvidenceConfigured(context)
            || !isUsageStatsAllowed(context)
            || !isUsageAccessGranted(context)) return null;
        try {
            UsageStatsManager usm =
                (UsageStatsManager) context.getSystemService(Context.USAGE_STATS_SERVICE);
            if (usm == null) return null;
            SharedPreferences prefs = prefs(context);
            long now = System.currentTimeMillis();
            long previousEnd = prefs.getLong(KEY_LAST_USAGE_QUERY_END, 0L);
            long queryStart = previousEnd > 0L
                ? Math.max(previousEnd - 120_000L, now - 7L * 24L * 60L * 60L * 1000L)
                : now - 24L * 60L * 60L * 1000L;
            UsageEvents usageEvents = usm.queryEvents(queryStart, now);
            UsageEvents.Event event = new UsageEvents.Event();
            long latest = prefs.getLong(KEY_LAST_USAGE_EVIDENCE_AT, 0L);
            while (usageEvents.hasNextEvent()) {
                usageEvents.getNextEvent(event);
                if (PassiveEvidenceContract.qualifiesUsageEvent(event.getEventType())
                    && event.getTimeStamp() > latest
                    && event.getTimeStamp() <= now) {
                    latest = event.getTimeStamp();
                }
            }
            prefs.edit().putLong(KEY_LAST_USAGE_QUERY_END, now).apply();
            if (latest <= prefs.getLong(KEY_LAST_USAGE_EVIDENCE_AT, 0L)) return null;
            return PassiveEvidenceContract.directUse(latest, queryStart, now);
        } catch (Exception e) {
            Log.d(TAG, "Usage evidence query unavailable", e);
            return null;
        }
    }

    static void recordPedestrianTransition(Context context, int activityType, long elapsedRealtimeNanos) {
        if (!isEvidenceConfigured(context)
            || !isActivityRecognitionAllowed(context)
            || !PassiveEvidenceContract.qualifiesPedestrianTransition(activityType)) return;
        long ageNanos = Math.max(0L, SystemClock.elapsedRealtimeNanos() - elapsedRealtimeNanos);
        long observedAt = System.currentTimeMillis() - TimeUnit.NANOSECONDS.toMillis(ageNanos);
        enqueueEvidence(context, PassiveEvidenceContract.pedestrianMotion(observedAt));
    }

    static void recordPowerBroadcast(Context context, String action) {
        if (!isEvidenceConfigured(context)
            || !prefs(context).getBoolean(KEY_ALLOW_CHARGING, false)) return;
        final boolean charging;
        if (Intent.ACTION_POWER_CONNECTED.equals(action)) charging = true;
        else if (Intent.ACTION_POWER_DISCONNECTED.equals(action)) charging = false;
        else return;
        SharedPreferences prefs = prefs(context);
        String stable = prefs.getString(KEY_POWER_STABLE_STATE, null);
        if (stable != null && Boolean.parseBoolean(stable) == charging) {
            prefs.edit().remove(KEY_POWER_PENDING_STATE).remove(KEY_POWER_PENDING_SINCE).apply();
            return;
        }
        long now = System.currentTimeMillis();
        prefs.edit()
            .putString(KEY_POWER_PENDING_STATE, String.valueOf(charging))
            .putLong(KEY_POWER_PENDING_SINCE, now)
            .apply();
        Context appContext = context.getApplicationContext();
        SCHEDULER.schedule(
            () -> confirmPowerTransition(appContext, charging),
            PassiveEvidenceContract.POWER_STABLE_MS,
            TimeUnit.MILLISECONDS);
    }

    // —— Foreground Service & GMS transition lifecycle managers ——

    static void updateBackgroundServices(Context context) {
        boolean configured = isConfigured(context);
        boolean needsService = configured;

        if (configured) {
            boolean activityRecognitionActive = isActivityRecognitionAllowed(context) && isActivityRecognitionGranted(context);

            // Update GMS Activity Recognition transitions
            try {
                updateActivityTransitions(context, activityRecognitionActive);
            } catch (Exception e) {
                Log.e(TAG, "Failed to update activity transitions", e);
            }
        }

        // The service is no longer what keeps the guard alive — NotifyWorker's
        // periodic look-back is. It runs only for devices that have proven they
        // will not let a sleeping app wake up.
        if (needsService && GUARD_PERSISTENT.equals(guardMode(context))) {
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

    static String supabaseUrl(Context context) {
        return prefs(context).getString(KEY_SUPABASE_URL, null);
    }

    static String token(Context context) {
        return prefs(context).getString(KEY_TOKEN, null);
    }

    static String clientId(Context context) {
        return prefs(context).getString(KEY_CLIENT_ID, null);
    }

    static String appVersion(Context context) {
        return prefs(context).getString(KEY_APP_VERSION, null);
    }

    static String collectorContract(Context context) {
        return prefs(context).getString(KEY_COLLECTOR_CONTRACT, null);
    }

    static long lastShadowCoverageLeaseAt(Context context) {
        return prefs(context).getLong(KEY_LAST_SHADOW_COVERAGE_LEASE_AT, 0);
    }

    static void markShadowCoverageLeaseSuccess(Context context, long at) {
        prefs(context).edit().putLong(KEY_LAST_SHADOW_COVERAGE_LEASE_AT, at).apply();
    }

    // —— Event Receiver Helpers ——

    static IntentFilter passiveIntentFilter(Context context) {
        SharedPreferences prefs = prefs(context);
        IntentFilter filter = new IntentFilter();
        if (isConfigured(context)) {
            if (prefs.getBoolean(KEY_ALLOW_USAGE_STATS, false)) {
                filter.addAction(Intent.ACTION_USER_PRESENT);
            }
            // POWER_CONNECTED/DISCONNECTED are handled by the manifest
            // receiver (they are exempt implicit broadcasts); registering them
            // here too would double-report every foreground transition.
        }
        return filter;
    }

    static IntentFilter chargingIntentFilter(Context context) {
        return passiveIntentFilter(context);
    }

    static void ping(Context context, long throttleMs) {
        Context appContext = context.getApplicationContext();
        SharedPreferences prefs = prefs(appContext);
        String base = prefs.getString(KEY_SUPABASE_URL, null);
        String token = prefs.getString(KEY_TOKEN, null);
        if (base == null || token == null || token.length() == 0) return;

        // A power transition observed by the dead-process manifest receiver may
        // outlive its 5-second stabilisation timer. Confirm it on the next wake
        // instead of losing it.
        confirmPendingPowerTransitionIfDue(appContext);

        long now = System.currentTimeMillis();
        if (throttleMs > 0 && now - prefs.getLong(KEY_LAST_PING, 0) < throttleMs) return;

        EXECUTOR.execute(() -> {
            HttpURLConnection conn = null;
            try {
                java.text.SimpleDateFormat sdf = new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US);
                sdf.setTimeZone(java.util.TimeZone.getTimeZone("UTC"));
                String observedAt = sdf.format(new java.util.Date(now));
                String eventId = java.util.UUID.randomUUID().toString();

                // We have always known, from UsageStats, when the phone was last
                // actually used — and have always thrown it away, reporting only
                // "I am awake now". Waking from Doze at 14:00 able to prove the
                // user unlocked at 13:35 and saying nothing about 13:35 is the
                // whole defect. Send it; the server records it at its real time.
                //
                // Runs inside the executor because a UsageStats event scan is not
                // something to do on whatever thread happened to call ping().
                // Returns 0 when Usage Access is not granted, in which case the
                // field is simply absent and the request is unchanged.
                long lastActive = queryLastActiveTime(appContext);
                String lastActiveField = "";
                if (lastActive > 0 && lastActive <= now) {
                    lastActiveField =
                        "\"last_active_at\":\"" + sdf.format(new java.util.Date(lastActive)) + "\",";
                }

                String bodyJson = "{" +
                    "\"token\":\"" + token + "\"," +
                    "\"event_id\":\"" + eventId + "\"," +
                    "\"observed_at\":\"" + observedAt + "\"," +
                    lastActiveField +
                    "\"source\":\"capacitor\"" +
                    "}";

                String url = base + "/functions/v1/ping";
                conn = (HttpURLConnection) new URL(url).openConnection();
                conn.setConnectTimeout(8000);
                conn.setReadTimeout(8000);
                conn.setRequestMethod("POST");
                conn.setRequestProperty("Content-Type", "application/json; utf-8");
                conn.setDoOutput(true);

                try (java.io.OutputStream os = conn.getOutputStream()) {
                    byte[] input = bodyJson.getBytes(StandardCharsets.UTF_8);
                    os.write(input, 0, input.length);
                }

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

    static boolean isEvidenceConfigured(Context context) {
        SharedPreferences prefs = prefs(context);
        String bindingId = prefs.getString(KEY_EVIDENCE_BINDING_ID, null);
        String contract = prefs.getString(KEY_EVIDENCE_CONTRACT, null);
        return bindingId != null
            && PassiveEvidenceContract.COLLECTOR_CONTRACT.equals(contract)
            && decryptEvidenceCredential(context) != null;
    }

    static void enqueueEvidence(Context context, PassiveEvidenceContract.Evidence evidence) {
        if (evidence == null || !isEvidenceConfigured(context)) return;
        Context appContext = context.getApplicationContext();
        synchronized (PassivePing.class) {
            SharedPreferences prefs = prefs(appContext);
            String bindingId = prefs.getString(KEY_EVIDENCE_BINDING_ID, null);
            if (bindingId == null) return;
            long sequence = prefs.getLong(KEY_EVIDENCE_NEXT_SEQUENCE, 0L);
            JSONArray queue = readEvidenceQueue(prefs);
            queue.put(evidence.toQueuedJson(bindingId, sequence));
            prefs.edit()
                .putLong(KEY_EVIDENCE_NEXT_SEQUENCE, sequence + 1L)
                .putString(KEY_EVIDENCE_QUEUE, queue.toString())
                .apply();
            if (evidence.querySucceeded && "direct_device_use".equals(evidence.evidenceClass)) {
                prefs.edit().putLong(KEY_LAST_USAGE_EVIDENCE_AT, evidence.observedAtMs).apply();
            }
        }
        EXECUTOR.execute(() -> drainEvidenceQueue(appContext));
    }

    private static void drainEvidenceQueue(Context context) {
        while (true) {
            String queued;
            synchronized (PassivePing.class) {
                JSONArray queue = readEvidenceQueue(prefs(context));
                if (queue.length() == 0) return;
                queued = queue.optString(0, null);
            }
            String credential = decryptEvidenceCredential(context);
            String base = prefs(context).getString(KEY_SUPABASE_URL, null);
            if (queued == null || credential == null || base == null) return;

            HttpURLConnection conn = null;
            try {
                conn = (HttpURLConnection) new URL(base + "/functions/v1/passive-evidence").openConnection();
                conn.setConnectTimeout(8000);
                conn.setReadTimeout(8000);
                conn.setRequestMethod("POST");
                conn.setRequestProperty("Content-Type", "application/json; utf-8");
                conn.setDoOutput(true);
                byte[] body = PassiveEvidenceContract.attachCredential(queued, credential)
                    .getBytes(StandardCharsets.UTF_8);
                try (java.io.OutputStream output = conn.getOutputStream()) {
                    output.write(body);
                }
                int code = conn.getResponseCode();
                InputStream stream = code >= 400 ? conn.getErrorStream() : conn.getInputStream();
                if (stream != null) {
                    try (BufferedReader ignored = new BufferedReader(new InputStreamReader(stream))) {
                        while (ignored.readLine() != null) { /* drain */ }
                    }
                }
                if (code >= 500) return;
                if (code == 409) {
                    clearEvidenceBinding(context);
                    return;
                }
                removeFirstQueuedEvidence(context);
            } catch (Exception e) {
                Log.d(TAG, "passive evidence upload deferred");
                return;
            } finally {
                if (conn != null) conn.disconnect();
            }
        }
    }

    private static void removeFirstQueuedEvidence(Context context) {
        synchronized (PassivePing.class) {
            SharedPreferences prefs = prefs(context);
            JSONArray current = readEvidenceQueue(prefs);
            JSONArray remaining = new JSONArray();
            for (int i = 1; i < current.length(); i++) remaining.put(current.opt(i));
            prefs.edit().putString(KEY_EVIDENCE_QUEUE, remaining.toString()).apply();
        }
    }

    private static JSONArray readEvidenceQueue(SharedPreferences prefs) {
        try {
            return new JSONArray(prefs.getString(KEY_EVIDENCE_QUEUE, "[]"));
        } catch (Exception ignored) {
            return new JSONArray();
        }
    }

    private static void configureEvidenceBinding(
        Context context,
        String bindingId,
        String credential,
        String contract
    ) {
        SharedPreferences prefs = prefs(context);
        String previous = prefs.getString(KEY_EVIDENCE_BINDING_ID, null);
        boolean valid = bindingId != null
            && PassiveEvidenceContract.COLLECTOR_CONTRACT.equals(contract);
        if (!valid) {
            clearEvidenceBinding(context);
            return;
        }
        if (previous != null && !previous.equals(bindingId)) clearEvidenceBinding(context);
        prefs.edit()
            .putString(KEY_EVIDENCE_BINDING_ID, bindingId)
            .putString(KEY_EVIDENCE_CONTRACT, contract)
            .apply();
        if (credential != null && credential.length() >= 32) {
            encryptEvidenceCredential(context, credential);
        }
        if (previous == null || !previous.equals(bindingId)) {
            prefs.edit()
                .putLong(KEY_EVIDENCE_NEXT_SEQUENCE, 0L)
                .putString(KEY_EVIDENCE_QUEUE, "[]")
                .apply();
        }
        if (isEvidenceConfigured(context)) EXECUTOR.execute(() -> drainEvidenceQueue(context));
    }

    private static void clearEvidenceBinding(Context context) {
        prefs(context).edit()
            .remove(KEY_EVIDENCE_BINDING_ID)
            .remove(KEY_EVIDENCE_CONTRACT)
            .remove(KEY_EVIDENCE_CREDENTIAL_CIPHER)
            .remove(KEY_EVIDENCE_CREDENTIAL_IV)
            .remove(KEY_EVIDENCE_NEXT_SEQUENCE)
            .remove(KEY_EVIDENCE_QUEUE)
            .remove(KEY_LAST_USAGE_EVIDENCE_AT)
            .remove(KEY_LAST_USAGE_QUERY_END)
            .remove(KEY_POWER_PENDING_STATE)
            .remove(KEY_POWER_PENDING_SINCE)
            .apply();
        try {
            KeyStore keyStore = KeyStore.getInstance("AndroidKeyStore");
            keyStore.load(null);
            if (keyStore.containsAlias(EVIDENCE_KEY_ALIAS)) keyStore.deleteEntry(EVIDENCE_KEY_ALIAS);
        } catch (Exception ignored) { /* fail closed: encrypted bytes are already gone */ }
    }

    private static void encryptEvidenceCredential(Context context, String credential) {
        try {
            KeyStore keyStore = KeyStore.getInstance("AndroidKeyStore");
            keyStore.load(null);
            SecretKey key;
            if (keyStore.containsAlias(EVIDENCE_KEY_ALIAS)) {
                key = ((KeyStore.SecretKeyEntry) keyStore.getEntry(EVIDENCE_KEY_ALIAS, null)).getSecretKey();
            } else {
                KeyGenerator generator = KeyGenerator.getInstance(
                    KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
                generator.init(new KeyGenParameterSpec.Builder(
                    EVIDENCE_KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .build());
                key = generator.generateKey();
            }
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, key);
            byte[] encrypted = cipher.doFinal(credential.getBytes(StandardCharsets.UTF_8));
            prefs(context).edit()
                .putString(KEY_EVIDENCE_CREDENTIAL_CIPHER, Base64.encodeToString(encrypted, Base64.NO_WRAP))
                .putString(KEY_EVIDENCE_CREDENTIAL_IV, Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP))
                .apply();
        } catch (Exception e) {
            Log.e(TAG, "Unable to protect passive evidence credential", e);
            clearEvidenceBinding(context);
        }
    }

    private static String decryptEvidenceCredential(Context context) {
        try {
            SharedPreferences prefs = prefs(context);
            String encoded = prefs.getString(KEY_EVIDENCE_CREDENTIAL_CIPHER, null);
            String encodedIv = prefs.getString(KEY_EVIDENCE_CREDENTIAL_IV, null);
            if (encoded == null || encodedIv == null) return null;
            KeyStore keyStore = KeyStore.getInstance("AndroidKeyStore");
            keyStore.load(null);
            KeyStore.SecretKeyEntry entry =
                (KeyStore.SecretKeyEntry) keyStore.getEntry(EVIDENCE_KEY_ALIAS, null);
            if (entry == null) return null;
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(
                Cipher.DECRYPT_MODE,
                entry.getSecretKey(),
                new GCMParameterSpec(128, Base64.decode(encodedIv, Base64.NO_WRAP)));
            return new String(
                cipher.doFinal(Base64.decode(encoded, Base64.NO_WRAP)),
                StandardCharsets.UTF_8);
        } catch (Exception ignored) {
            return null;
        }
    }

    private static void initializePowerBaseline(Context context) {
        Boolean charging = currentChargingState(context);
        SharedPreferences.Editor editor = prefs(context).edit()
            .remove(KEY_POWER_PENDING_STATE)
            .remove(KEY_POWER_PENDING_SINCE);
        if (charging == null) editor.remove(KEY_POWER_STABLE_STATE);
        else editor.putString(KEY_POWER_STABLE_STATE, String.valueOf(charging));
        editor.apply();
    }

    private static Boolean currentChargingState(Context context) {
        try {
            Intent battery = context.registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
            if (battery == null) return null;
            int status = battery.getIntExtra(BatteryManager.EXTRA_STATUS, -1);
            return status == BatteryManager.BATTERY_STATUS_CHARGING
                || status == BatteryManager.BATTERY_STATUS_FULL;
        } catch (Exception ignored) {
            return null;
        }
    }

    private static void confirmPowerTransition(Context context, boolean expected) {
        SharedPreferences prefs = prefs(context);
        String pending = prefs.getString(KEY_POWER_PENDING_STATE, null);
        long since = prefs.getLong(KEY_POWER_PENDING_SINCE, 0L);
        Boolean actual = currentChargingState(context);
        long now = System.currentTimeMillis();
        if (pending == null || actual == null || actual != expected
            || Boolean.parseBoolean(pending) != expected
            || now - since < PassiveEvidenceContract.POWER_STABLE_MS) return;
        String priorText = prefs.getString(KEY_POWER_STABLE_STATE, null);
        prefs.edit()
            .putString(KEY_POWER_STABLE_STATE, String.valueOf(expected))
            .remove(KEY_POWER_PENDING_STATE)
            .remove(KEY_POWER_PENDING_SINCE)
            .apply();
        if (priorText == null || Boolean.parseBoolean(priorText) == expected) return;

        long correlationStarted = prefs.getLong(KEY_POWER_CORRELATION_STARTED, 0L);
        String correlationId = prefs.getString(KEY_POWER_CORRELATION_ID, null);
        if (correlationId == null
            || since - correlationStarted >= PassiveEvidenceContract.POWER_CORRELATION_MS) {
            correlationId = "power-" + UUID.randomUUID();
            prefs.edit()
                .putString(KEY_POWER_CORRELATION_ID, correlationId)
                .putLong(KEY_POWER_CORRELATION_STARTED, since)
                .apply();
        }
        String prior = Boolean.parseBoolean(priorText) ? "charging" : "not_charging";
        String next = expected ? "charging" : "not_charging";
        String facts = "{\"prior_power_state\":\"" + prior
            + "\",\"new_power_state\":\"" + next
            + "\",\"stable_for_ms\":" + PassiveEvidenceContract.POWER_STABLE_MS + "}";
        enqueueEvidence(context, new PassiveEvidenceContract.Evidence(
            UUID.randomUUID().toString(), since, "power_transition", correlationId,
            facts, 0L, 0L, false));
    }

    static void confirmPendingPowerTransitionIfDue(Context context) {
        if (!isEvidenceConfigured(context)
            || !prefs(context).getBoolean(KEY_ALLOW_CHARGING, false)) return;
        SharedPreferences prefs = prefs(context);
        String pending = prefs.getString(KEY_POWER_PENDING_STATE, null);
        if (pending == null) return;
        long since = prefs.getLong(KEY_POWER_PENDING_SINCE, 0L);
        if (System.currentTimeMillis() - since < PassiveEvidenceContract.POWER_STABLE_MS) return;
        confirmPowerTransition(context, Boolean.parseBoolean(pending));
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
