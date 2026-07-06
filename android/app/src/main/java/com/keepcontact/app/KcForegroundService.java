package com.keepcontact.app;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;
import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;
import java.util.Locale;

public class KcForegroundService extends Service {
    private static final String CHANNEL_ID = "kc_foreground_service";
    private static final int NOTIFICATION_ID = 90210;

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        ensureNotificationChannel();

        Intent launchIntent = getPackageManager().getLaunchIntentForPackage(getPackageName());
        PendingIntent pendingIntent = null;
        if (launchIntent != null) {
            launchIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            pendingIntent = PendingIntent.getActivity(
                this, 0, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        }

        boolean isZh = Locale.getDefault().getLanguage().startsWith("zh");
        String title = isZh ? "被动安全监护运行中" : "Passive guard is active";
        String body = isZh 
            ? "已启用日常活跃感应以保障您的安全。" 
            : "Active sensing is enabled to ensure your safety.";

        Notification notification = new NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(getApplicationInfo().icon)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build();

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }

        return START_STICKY;
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
        manager.createNotificationChannel(channel);
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
