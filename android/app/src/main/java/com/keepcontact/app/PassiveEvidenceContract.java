package com.keepcontact.app;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;
import java.util.UUID;

final class PassiveEvidenceContract {
    static final String COLLECTOR_CONTRACT = "android-passive-evidence-v1";
    static final String QUALIFICATION_POLICY = "passive-qualification-v1";
    static final int USAGE_ACTIVITY_RESUMED = 1;
    static final int USAGE_USER_INTERACTION = 7;
    static final int USAGE_KEYGUARD_HIDDEN = 18;
    static final int USAGE_SCREEN_ON = 15;
    static final int ACTIVITY_IN_VEHICLE = 0;
    static final int ACTIVITY_WALKING = 7;
    static final int ACTIVITY_RUNNING = 8;
    static final long POWER_STABLE_MS = 5_000L;
    static final long POWER_CORRELATION_MS = 60_000L;

    private PassiveEvidenceContract() {}

    static boolean qualifiesUsageEvent(int eventType) {
        return eventType == USAGE_ACTIVITY_RESUMED
            || eventType == USAGE_USER_INTERACTION
            || eventType == USAGE_KEYGUARD_HIDDEN;
    }

    static boolean qualifiesPedestrianTransition(int activityType) {
        return activityType == ACTIVITY_WALKING || activityType == ACTIVITY_RUNNING;
    }

    static Evidence directUse(long observedAtMs, long queryStartedAtMs, long queryEndedAtMs) {
        return new Evidence(
            UUID.randomUUID().toString(), observedAtMs, "direct_device_use", null,
            "{\"interaction\":true}", queryStartedAtMs, queryEndedAtMs, true);
    }

    static Evidence pedestrianMotion(long observedAtMs) {
        return new Evidence(
            UUID.randomUUID().toString(), observedAtMs, "personal_device_motion", null,
            "{\"steps_positive\":true,\"pedestrian\":true,\"automotive\":false}",
            0L, 0L, false);
    }

    static final class Evidence {
        final String eventId;
        final long observedAtMs;
        final String evidenceClass;
        final String correlationId;
        final String qualificationFacts;
        final long queryStartedAtMs;
        final long queryEndedAtMs;
        final boolean querySucceeded;

        Evidence(
            String eventId,
            long observedAtMs,
            String evidenceClass,
            String correlationId,
            String qualificationFacts,
            long queryStartedAtMs,
            long queryEndedAtMs,
            boolean querySucceeded
        ) {
            this.eventId = eventId;
            this.observedAtMs = observedAtMs;
            this.evidenceClass = evidenceClass;
            this.correlationId = correlationId;
            this.qualificationFacts = qualificationFacts;
            this.queryStartedAtMs = queryStartedAtMs;
            this.queryEndedAtMs = queryEndedAtMs;
            this.querySucceeded = querySucceeded;
        }

        String toJson(String bindingId, String credential, long sequence) {
            String queryStart = queryStartedAtMs > 0 ? quote(iso(queryStartedAtMs)) : "null";
            String queryEnd = queryEndedAtMs > 0 ? quote(iso(queryEndedAtMs)) : "null";
            return "{"
                + "\"binding_id\":" + quote(bindingId) + ","
                + "\"credential\":" + quote(credential) + ","
                + "\"event_id\":" + quote(eventId) + ","
                + "\"sequence\":" + sequence + ","
                + "\"observed_at\":" + quote(iso(observedAtMs)) + ","
                + "\"evidence_class\":" + quote(evidenceClass) + ","
                + "\"qualification_policy_version\":" + quote(QUALIFICATION_POLICY) + ","
                + "\"correlation_id\":" + (correlationId == null ? "null" : quote(correlationId)) + ","
                + "\"qualification_facts\":" + qualificationFacts + ","
                + "\"query_started_at\":" + queryStart + ","
                + "\"query_ended_at\":" + queryEnd + ","
                + "\"query_succeeded\":" + querySucceeded
                + "}";
        }

        String toQueuedJson(String bindingId, long sequence) {
            return toJson(bindingId, null, sequence);
        }
    }

    static final class BindingState {
        final String bindingId;
        final long nextSequence;
        final int queuedCount;

        BindingState(String bindingId, long nextSequence, int queuedCount) {
            this.bindingId = bindingId;
            this.nextSequence = nextSequence;
            this.queuedCount = queuedCount;
        }
    }

    static BindingState bind(BindingState current, String bindingId) {
        if (current != null && bindingId != null && bindingId.equals(current.bindingId)) return current;
        return new BindingState(bindingId, 0L, 0);
    }

    static BindingState clearBinding(BindingState current) {
        return new BindingState(null, 0L, 0);
    }

    static final class PowerTracker {
        private Boolean stableState;
        private Boolean pendingState;
        private long pendingSince;
        private long correlationStartedAt;
        private String correlationId;

        Evidence observe(boolean charging, long atMs) {
            if (stableState != null && stableState == charging) {
                pendingState = null;
                return null;
            }
            if (pendingState == null || pendingState != charging) {
                pendingState = charging;
                pendingSince = atMs;
            }
            return null;
        }

        Evidence confirm(boolean charging, long atMs) {
            if (pendingState == null || pendingState != charging || atMs - pendingSince < POWER_STABLE_MS) {
                return null;
            }
            Boolean prior = stableState;
            stableState = charging;
            pendingState = null;
            if (prior == null || prior == charging) return null;
            if (correlationId == null || pendingSince - correlationStartedAt >= POWER_CORRELATION_MS) {
                correlationStartedAt = pendingSince;
                correlationId = "power-" + UUID.randomUUID();
            }
            String priorValue = prior ? "charging" : "not_charging";
            String newValue = charging ? "charging" : "not_charging";
            String facts = "{\"prior_power_state\":" + quote(priorValue)
                + ",\"new_power_state\":" + quote(newValue)
                + ",\"stable_for_ms\":" + POWER_STABLE_MS + "}";
            return new Evidence(
                UUID.randomUUID().toString(), pendingSince, "power_transition", correlationId,
                facts, 0L, 0L, false);
        }
    }

    static String iso(long atMs) {
        SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US);
        format.setTimeZone(TimeZone.getTimeZone("UTC"));
        return format.format(new Date(atMs));
    }

    static String attachCredential(String queuedJson, String credential) {
        return queuedJson.replace(
            "\"credential\":null",
            "\"credential\":" + quote(credential));
    }

    private static String quote(String value) {
        if (value == null) return "null";
        return "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
    }
}
