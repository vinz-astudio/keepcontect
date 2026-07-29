package com.keepcontact.app;

import android.content.Context;
import android.util.Log;
import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;
import java.util.UUID;
import org.json.JSONObject;

final class AlertShadowCoverageReporter {
    private static final String TAG = "KeepContactPassive";
    private static final long SUCCESS_THROTTLE_MS = 14 * 60 * 1000;
    private static final int TIMEOUT_MS = 8000;

    private AlertShadowCoverageReporter() {}

    static void reportIfOperational(Context context) {
        Context appContext = context.getApplicationContext();
        long now = System.currentTimeMillis();
        if (now - PassivePing.lastShadowCoverageLeaseAt(appContext)
            < SUCCESS_THROTTLE_MS) {
            return;
        }

        String base = PassivePing.supabaseUrl(appContext);
        String token = PassivePing.token(appContext);
        String clientId = PassivePing.clientId(appContext);
        String appVersion = PassivePing.appVersion(appContext);
        String collectorContract = PassivePing.collectorContract(appContext);
        AlertShadowCoverageContract.CapabilityInput capability =
            new AlertShadowCoverageContract.CapabilityInput(
                PassivePing.isConfigured(appContext),
                PassivePing.isUsageStatsAllowed(appContext),
                PassivePing.isUsageAccessGranted(appContext),
                true,
                clientId,
                appVersion);

        if (!AlertShadowCoverageContract.COLLECTOR_CONTRACT.equals(collectorContract)
            || !AlertShadowCoverageContract.isOperational(capability)
            || base == null
            || token == null
            || token.isEmpty()) {
            return;
        }

        HttpURLConnection connection = null;
        try {
            String body = AlertShadowCoverageContract.body(
                token,
                clientId,
                appVersion,
                AlertShadowCoverageContract.capabilitySha256(capability),
                isoAt(now),
                UUID.randomUUID());
            connection = (HttpURLConnection) new URL(
                base + "/functions/v1/shadow-coverage-lease").openConnection();
            connection.setConnectTimeout(TIMEOUT_MS);
            connection.setReadTimeout(TIMEOUT_MS);
            connection.setRequestMethod("POST");
            connection.setRequestProperty("Content-Type", "application/json; utf-8");
            connection.setDoOutput(true);
            byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
            try (OutputStream output = connection.getOutputStream()) {
                output.write(bytes);
            }

            int code = connection.getResponseCode();
            InputStream stream =
                code >= 400 ? connection.getErrorStream() : connection.getInputStream();
            String response = read(stream);
            if (code < 400 && !response.isEmpty()) {
                String status = new JSONObject(response).optString("status", "");
                if ("inserted".equals(status) || "duplicate".equals(status)) {
                    PassivePing.markShadowCoverageLeaseSuccess(appContext, now);
                }
            }
        } catch (Exception exception) {
            Log.d(TAG, "shadow coverage lease failed");
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    private static String read(InputStream stream) throws Exception {
        if (stream == null) return "";
        StringBuilder value = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(
            new InputStreamReader(stream, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) value.append(line);
        }
        return value.toString();
    }

    private static String isoAt(long timestamp) {
        SimpleDateFormat format =
            new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US);
        format.setTimeZone(TimeZone.getTimeZone("UTC"));
        return format.format(new Date(timestamp));
    }
}
