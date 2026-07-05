package com.keepcontact.app;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import androidx.annotation.NonNull;
import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;
import androidx.work.Constraints;
import androidx.work.ExistingPeriodicWorkPolicy;
import androidx.work.NetworkType;
import androidx.work.PeriodicWorkRequest;
import androidx.work.WorkManager;
import androidx.work.Worker;
import androidx.work.WorkerParameters;
import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import org.json.JSONArray;
import org.json.JSONObject;

/**
 * Native notification channel for the Android APK.
 *
 * The Capacitor WebView has no Web Push, so APK users never receive the web
 * notifications that PWA users get. This worker polls the token+HMAC
 * authenticated notify-feed edge function every ~15 minutes and posts local
 * system notifications. Latency (<=15 min) is acceptable for Keep Contact's
 * hour-scale escalation chain; an FCM fast path for GMS devices is a separate
 * proposal (ADR-0004). Content is rendered locally from kind+params — mirrors
 * public/sw.js so both channels speak identical copy.
 */
public class NotifyWorker extends Worker {
    private static final String TAG = "KeepContactPassive";
    private static final String WORK_NAME = "kc-notify-poll";
    private static final String CHANNEL_ID = "kc_alerts";
    private static final String PREFS = "keep_contact_passive";
    private static final String KEY_SINCE = "notify_since";

    public NotifyWorker(@NonNull Context context, @NonNull WorkerParameters params) {
        super(context, params);
    }

    /** Enqueue the periodic poll (idempotent). Initializes the cursor to "now" on
     *  first schedule so old history never floods the user as fresh alerts. */
    static void schedule(Context context) {
        SharedPreferences prefs =
            context.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        if (prefs.getString(KEY_SINCE, null) == null) {
            prefs.edit().putString(KEY_SINCE, isoNow()).apply();
        }
        PeriodicWorkRequest request = new PeriodicWorkRequest.Builder(
                NotifyWorker.class, 15, TimeUnit.MINUTES)
            .setConstraints(new Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build())
            .build();
        WorkManager.getInstance(context.getApplicationContext())
            .enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, request);
    }

    static void cancel(Context context) {
        WorkManager.getInstance(context.getApplicationContext()).cancelUniqueWork(WORK_NAME);
    }

    @NonNull
    @Override
    public Result doWork() {
        Context context = getApplicationContext();
        if (!PassivePing.isConfigured(context)) return Result.success();
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) {
            return Result.success();
        }

        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        String base = prefs.getString("supabase_url", null);
        String token = prefs.getString("token", null);
        if (base == null || token == null) return Result.success();
        String since = prefs.getString(KEY_SINCE, isoNow());

        HttpURLConnection conn = null;
        try {
            long t = System.currentTimeMillis() / 1000;
            String sig = PassivePing.calculateHMAC(String.valueOf(t), token);
            String url = base + "/functions/v1/notify-feed?token="
                + URLEncoder.encode(token, StandardCharsets.UTF_8.name())
                + "&t=" + t
                + "&sig=" + URLEncoder.encode(sig, StandardCharsets.UTF_8.name())
                + "&since=" + URLEncoder.encode(since, StandardCharsets.UTF_8.name());
            conn = (HttpURLConnection) new URL(url).openConnection();
            conn.setConnectTimeout(8000);
            conn.setReadTimeout(8000);
            conn.setRequestMethod("GET");
            int code = conn.getResponseCode();
            if (code >= 500) return Result.retry();
            if (code >= 400) return Result.success(); // auth problem: retrying won't help

            StringBuilder sb = new StringBuilder();
            InputStream stream = conn.getInputStream();
            try (BufferedReader reader =
                     new BufferedReader(new InputStreamReader(stream, StandardCharsets.UTF_8))) {
                String line;
                while ((line = reader.readLine()) != null) sb.append(line);
            }

            JSONObject payload = new JSONObject(sb.toString());
            JSONArray list = payload.optJSONArray("notifications");
            if (list == null || list.length() == 0) return Result.success();

            ensureChannel(context);
            String latest = since;
            for (int i = 0; i < list.length(); i++) {
                JSONObject n = list.getJSONObject(i);
                String id = n.optString("id", String.valueOf(i));
                String kind = n.optString("kind", "");
                JSONObject params = n.optJSONObject("params");
                String body = renderBody(kind, params, n.optString("body", ""));
                postNotification(context, id, body);
                String createdAt = n.optString("created_at", "");
                if (createdAt.compareTo(latest) > 0) latest = createdAt;
            }
            prefs.edit().putString(KEY_SINCE, latest).apply();
            return Result.success();
        } catch (Exception e) {
            android.util.Log.d(TAG, "notify poll failed", e);
            return Result.retry();
        } finally {
            if (conn != null) conn.disconnect();
        }
    }

    private static void ensureChannel(Context context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (manager == null) return;
        NotificationChannel channel = new NotificationChannel(
            CHANNEL_ID,
            isZh() ? "守护提醒" : "Care alerts",
            NotificationManager.IMPORTANCE_HIGH);
        channel.setDescription(isZh()
            ? "异常沉默、关心确认与报平安任务的提醒"
            : "Unusual-silence, concern, and check-in task alerts");
        manager.createNotificationChannel(channel);
    }

    private static void postNotification(Context context, String id, String body) {
        Intent launch = context.getPackageManager()
            .getLaunchIntentForPackage(context.getPackageName());
        if (launch == null) return;
        launch.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent pending = PendingIntent.getActivity(
            context, id.hashCode(), launch,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        NotificationCompat.Builder builder = new NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(context.getApplicationInfo().icon)
            .setContentTitle("Keep Contact")
            .setContentText(body)
            .setStyle(new NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pending);
        try {
            NotificationManagerCompat.from(context).notify(id.hashCode(), builder.build());
        } catch (SecurityException ignored) {
            // POST_NOTIFICATIONS revoked between the check and here.
        }
    }

    private static boolean isZh() {
        return Locale.getDefault().getLanguage().startsWith("zh");
    }

    /** Mirrors the templates in public/sw.js so both channels speak identical copy. */
    private static String renderBody(String kind, JSONObject params, String fallback) {
        Map<String, String> dict = isZh() ? zh() : en();
        String tpl = dict.get(kind);
        if (tpl == null) {
            return fallback != null && !fallback.isEmpty()
                ? fallback
                : (isZh() ? "有新的守护提醒，请打开 App 查看。" : "New care alert — open the app.");
        }
        String someone = isZh() ? "某位成员" : "A member";
        String name = params != null ? params.optString("name", someone) : someone;
        String actor = params != null ? params.optString("actor", someone) : someone;
        String target = params != null ? params.optString("target", someone) : someone;
        return tpl.replace("{name}", name.isEmpty() ? someone : name)
            .replace("{actor}", actor.isEmpty() ? someone : actor)
            .replace("{target}", target.isEmpty() ? someone : target);
    }

    private static Map<String, String> zh() {
        Map<String, String> d = new HashMap<>();
        d.put("self", "检测到异常沉默，请打开 App 完成解锁报平安。");
        d.put("group", "{name} 出现异常沉默，请尽快联系确认其安全。");
        d.put("community", "社区警示：{name} 长时间失联且其小组无人响应，请协助推动联系。");
        d.put("terminal", "紧急：{name} 持续无响应。已为你解锁其地址与紧急联系人，请上门探视或协助报警。");
        d.put("on_it", "{actor} 正在跟进 {target} 的情况。");
        d.put("resolved", "{target} 已确认安全，告警解除。");
        d.put("task_invite", "{name} 为你设置了报平安任务，请打开 App 确认是否接受。");
        d.put("task_due", "到点报平安啦，点开 App 完成确认。");
        d.put("task_missed", "{name} 未完成定时报平安，请关注。");
        d.put("task_accepted", "{name} 接受了你设置的报平安任务。");
        d.put("task_declined", "{name} 拒绝了你设置的报平安任务。");
        d.put("task_updated", "你的报平安任务已被修改，请留意新的时间安排。");
        d.put("test", "这是一条测试通知，用来确认推送是否出声、醒目。");
        d.put("concern", "{name} 在关心你，请打开 App 完成解锁报平安。");
        return d;
    }

    private static Map<String, String> en() {
        Map<String, String> d = new HashMap<>();
        d.put("self", "Unusual silence detected. Open the app and unlock to check in.");
        d.put("group", "{name} has gone unusually silent. Please reach out and make sure they are safe.");
        d.put("community", "Community alert: {name} is unreachable and their group has not responded.");
        d.put("terminal", "URGENT: {name} is unresponsive. Their address and emergency contact are unlocked for you.");
        d.put("on_it", "{actor} is following up on {target}.");
        d.put("resolved", "{target} is confirmed safe. Alert resolved.");
        d.put("task_invite", "{name} set up a check-in task for you. Open the app to accept or decline.");
        d.put("task_due", "Time to check in — open the app to confirm.");
        d.put("task_missed", "{name} missed a scheduled check-in. Please look in on them.");
        d.put("task_accepted", "{name} accepted your check-in task.");
        d.put("task_declined", "{name} declined your check-in task.");
        d.put("task_updated", "Your check-in task was changed. Please note the new schedule.");
        d.put("test", "This is a test notification — checking whether push is audible and prominent.");
        d.put("concern", "{name} is checking on you — please open the app and check in.");
        return d;
    }

    private static String isoNow() {
        return new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US) {{
            setTimeZone(java.util.TimeZone.getTimeZone("UTC"));
        }}.format(new java.util.Date());
    }
}
