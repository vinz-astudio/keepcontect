package com.keepcontact.app;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.UUID;

final class AlertShadowCoverageContract {
    static final String CHANNEL = "android-apk";
    static final String COLLECTOR_CONTRACT = "android-passive-v1";

    static final class CapabilityInput {
        final boolean configured;
        final boolean usageStatsEnabled;
        final boolean usageStatsGranted;
        final boolean workerExecuting;
        final String clientId;
        final String appVersion;

        CapabilityInput(
            boolean configured,
            boolean usageStatsEnabled,
            boolean usageStatsGranted,
            boolean workerExecuting,
            String clientId,
            String appVersion
        ) {
            this.configured = configured;
            this.usageStatsEnabled = usageStatsEnabled;
            this.usageStatsGranted = usageStatsGranted;
            this.workerExecuting = workerExecuting;
            this.clientId = clientId;
            this.appVersion = appVersion;
        }
    }

    private AlertShadowCoverageContract() {}

    static boolean isOperational(CapabilityInput input) {
        return input != null
            && input.configured
            && input.usageStatsEnabled
            && input.usageStatsGranted
            && input.workerExecuting
            && notBlank(input.clientId)
            && notBlank(input.appVersion);
    }

    static String capabilityJson(CapabilityInput input) {
        return "{"
            + "\"appVersion\":" + jsonString(input.appVersion) + ","
            + "\"channel\":\"android-apk\","
            + "\"collectorContract\":\"android-passive-v1\","
            + "\"usageStatsGranted\":" + input.usageStatsGranted + ","
            + "\"workerExecuting\":" + input.workerExecuting
            + "}";
    }

    static String capabilitySha256(CapabilityInput input) {
        return sha256(capabilityJson(input));
    }

    static String body(
        String token,
        String clientId,
        String appVersion,
        String capabilitySha256,
        String observedAt,
        UUID eventId
    ) {
        return "{"
            + "\"token\":" + jsonString(token) + ","
            + "\"client_id\":" + jsonString(clientId) + ","
            + "\"channel\":\"android-apk\","
            + "\"collector_contract\":\"android-passive-v1\","
            + "\"collector_state\":\"operational\","
            + "\"capability_sha256\":" + jsonString(capabilitySha256) + ","
            + "\"observed_at\":" + jsonString(observedAt) + ","
            + "\"event_id\":" + jsonString(eventId.toString())
            + "}";
    }

    private static boolean notBlank(String value) {
        return value != null && !value.trim().isEmpty();
    }

    private static String sha256(String value) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] bytes = digest.digest(value.getBytes(StandardCharsets.UTF_8));
            StringBuilder result = new StringBuilder(bytes.length * 2);
            for (byte item : bytes) result.append(String.format("%02x", item));
            return result.toString();
        } catch (Exception exception) {
            throw new IllegalStateException("SHA-256 unavailable", exception);
        }
    }

    private static String jsonString(String value) {
        if (value == null) return "null";
        StringBuilder escaped = new StringBuilder(value.length() + 2);
        escaped.append('"');
        for (int i = 0; i < value.length(); i++) {
            char current = value.charAt(i);
            switch (current) {
                case '"': escaped.append("\\\""); break;
                case '\\': escaped.append("\\\\"); break;
                case '\b': escaped.append("\\b"); break;
                case '\f': escaped.append("\\f"); break;
                case '\n': escaped.append("\\n"); break;
                case '\r': escaped.append("\\r"); break;
                case '\t': escaped.append("\\t"); break;
                default:
                    if (current < 0x20) {
                        escaped.append(String.format("\\u%04x", (int) current));
                    } else {
                        escaped.append(current);
                    }
            }
        }
        return escaped.append('"').toString();
    }
}
