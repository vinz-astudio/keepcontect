package com.keepcontact.app;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;
import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;
import androidx.core.content.ContextCompat;
import java.util.Locale;

public class KcForegroundService extends Service {
    private static final String CHANNEL_ID = "kc_foreground_service";
    private static final int NOTIFICATION_ID = 90210;

    private BroadcastReceiver passiveEventReceiver;

    /**
     * The published notification, kept so repeat starts reuse it.
     *
     * `start()` runs again on every broadcast the passive receiver sees — every
     * unlock, every power connect — as a cheap way to revive the service if
     * Android had killed it. When the service was already alive that still
     * reached here and built and posted a fresh notification under the same id,
     * and several ROMs re-animate the shade entry on a re-post. Users saw the
     * guardian notification reappear every time they picked their phone up,
     * reported as "a notification every ten minutes" — which is simply how often
     * an ordinary person unlocks a phone.
     *
     * `startForeground()` is still called on every start, deliberately: on
     * Android 8+ a `startForegroundService()` must be answered within about five
     * seconds or the process is killed with
     * ForegroundServiceDidNotStartInTimeException. Skipping the call to avoid
     * the re-post would trade an annoyance for a crash. Reusing the identical
     * Notification instance, plus setOnlyAlertOnce below, is what keeps it
     * quiet.
     */
    private Notification publishedNotification;

    @Override
    public void onCreate() {
        super.onCreate();
        registerPassiveReceiver();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (publishedNotification != null) {
            // Answer the start obligation with the notification that is already
            // showing, rather than announcing the guard all over again.
            enterForeground(publishedNotification);
            return START_STICKY;
        }

        ensureNotificationChannel();

        Intent launchIntent = getPackageManager().getLaunchIntentForPackage(getPackageName());
        PendingIntent pendingIntent = null;
        if (launchIntent != null) {
            launchIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            pendingIntent = PendingIntent.getActivity(
                this, 0, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        }

        // Kept deliberately flat. Android will not let a foreground service hide
        // its notification, so the only thing left to control is how much
        // attention it asks for. "Passive guard is active / Active sensing is
        // enabled to ensure your safety" reads like an announcement; users who
        // clear their shade every day do not want to be told this daily. A bare
        // statement of fact is the quietest honest wording available.
        boolean isZh = Locale.getDefault().getLanguage().startsWith("zh");
        String title = isZh ? "Keep Contact" : "Keep Contact";
        String body = isZh ? "守护中" : "Watching over you";

        Notification notification = new NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(getApplicationInfo().icon)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            // Belt to the reuse braces above: even if something posts this
            // notification again, the shade must not treat it as news.
            .setOnlyAlertOnce(true)
            // Android 12+ will hold the notification back for about ten seconds
            // rather than showing it the instant the service starts. It does not
            // help a guard that runs all day, but it does stop the entry
            // flashing into view every time the service is restarted after the
            // system reclaims it.
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_DEFERRED)
            .build();

        publishedNotification = notification;
        enterForeground(notification);

        return START_STICKY;
    }

    private void enterForeground(Notification notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }
    }

    private void ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationManager manager = getSystemService(NotificationManager.class);
        if (manager == null) return;
        boolean isZh = Locale.getDefault().getLanguage().startsWith("zh");
        NotificationChannel channel = new NotificationChannel(
            CHANNEL_ID,
            isZh ? "后台监护通道" : "Background Guard Channel",
            NotificationManager.IMPORTANCE_MIN);
        channel.setDescription(isZh
            ? "Keep Contact 紧急安全守护的前台常驻状态"
            : "Foreground status for Keep Contact safety monitor");
        // No launcher badge. IMPORTANCE_MIN already keeps this out of the status
        // bar and at the bottom of the shade, but the badge dot was still
        // putting a permanent mark on the home screen icon for a notification
        // the user is never meant to act on.
        channel.setShowBadge(false);
        channel.setSound(null, null);
        channel.enableVibration(false);
        manager.createNotificationChannel(channel);
    }

    @Override
    public void onDestroy() {
        unregisterPassiveReceiver();
        super.onDestroy();
    }

    private void registerPassiveReceiver() {
        if (passiveEventReceiver != null) return;
        passiveEventReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                if (intent == null) return;
                String action = intent.getAction();
                android.util.Log.d("KcForegroundService", "Passive event received in Service: " + action);
                // The service used to ping and nothing else, so a charging edge
                // caught here produced a liveness ping but never the
                // power_transition evidence the passive check-in windows count.
                // Both are idempotent, so overlapping with the plugin's own
                // receiver while the app is open costs nothing.
                PassivePing.recordPowerBroadcast(context, action);
                if (PassivePing.shouldPingForAction(context, action)) {
                    PassivePing.pingApp(context);
                }
            }
        };

        // One source of truth for which actions the user consented to. The
        // hardcoded list this replaces registered for the charger and unlock
        // even when their sensor toggles were off.
        IntentFilter filter = PassivePing.passiveIntentFilter(this);
        if (filter.countActions() == 0) {
            passiveEventReceiver = null;
            return;
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(passiveEventReceiver, filter, Context.RECEIVER_EXPORTED);
            } else {
                registerReceiver(passiveEventReceiver, filter);
            }
        } catch (Exception e) {
            android.util.Log.e("KcForegroundService", "Failed to register passive event receiver", e);
        }
    }

    private void unregisterPassiveReceiver() {
        if (passiveEventReceiver == null) return;
        try {
            unregisterReceiver(passiveEventReceiver);
        } catch (Exception ignored) {
            // Already unregistered
        }
        passiveEventReceiver = null;
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    public static void start(Context context) {
        Intent intent = new Intent(context, KcForegroundService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
    }

    public static void stop(Context context) {
        Intent intent = new Intent(context, KcForegroundService.class);
        context.stopService(intent);
    }
}
