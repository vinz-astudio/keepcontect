package com.keepcontact.app;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;
import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URLEncoder;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

final class PassivePing {
    private static final String TAG = "KeepContactPassive";
    private static final String PREFS = "keep_contact_passive";
    private static final String KEY_SUPABASE_URL = "supabase_url";
    private static final String KEY_TOKEN = "token";
    private static final String KEY_LAST_PING = "last_ping";
    private static final long APP_THROTTLE_MS = 5 * 60 * 1000;
    private static final ExecutorService EXECUTOR = Executors.newSingleThreadExecutor();

    private PassivePing() {}

    static void configure(Context context, String supabaseUrl, String token) {
        prefs(context)
            .edit()
            .putString(KEY_SUPABASE_URL, trimSlash(supabaseUrl))
            .putString(KEY_TOKEN, token)
            .apply();
    }

    static void clear(Context context) {
        prefs(context).edit().clear().apply();
    }

    static void ping(Context context) {
        ping(context, 0);
    }

    static void pingApp(Context context) {
        ping(context, APP_THROTTLE_MS);
    }

    private static void ping(Context context, long throttleMs) {
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
                    "&t=" + t +
                    "&sig=" + URLEncoder.encode(sig, StandardCharsets.UTF_8.name());
                conn = (HttpURLConnection) new URL(url).openConnection();
                conn.setConnectTimeout(8000);
                conn.setReadTimeout(8000);
                conn.setRequestMethod("GET");
                int code = conn.getResponseCode();
                if (code < 400 && throttleMs > 0) {
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

    private static String calculateHMAC(String data, String key) {
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

