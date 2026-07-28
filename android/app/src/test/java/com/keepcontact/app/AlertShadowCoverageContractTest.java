package com.keepcontact.app;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.util.UUID;
import org.junit.Test;

public class AlertShadowCoverageContractTest {
    @Test
    public void operationalRequiresAllHealthInputs() {
        assertFalse(AlertShadowCoverageContract.isOperational(
            new AlertShadowCoverageContract.CapabilityInput(
                true, true, false, true, "c1", "0.5.20")));
        assertFalse(AlertShadowCoverageContract.isOperational(
            new AlertShadowCoverageContract.CapabilityInput(
                true, true, true, true, "", "0.5.20")));
        assertTrue(AlertShadowCoverageContract.isOperational(
            new AlertShadowCoverageContract.CapabilityInput(
                true, true, true, true, "c1", "0.5.20")));
    }

    @Test
    public void capabilityJsonIsCanonical() {
        AlertShadowCoverageContract.CapabilityInput input =
            new AlertShadowCoverageContract.CapabilityInput(
                true, true, true, true, "c1", "0.5.20");
        assertEquals(
            "{\"appVersion\":\"0.5.20\",\"channel\":\"android-apk\","
                + "\"collectorContract\":\"android-passive-v1\","
                + "\"usageStatsGranted\":true,\"workerExecuting\":true}",
            AlertShadowCoverageContract.capabilityJson(input));
        assertTrue(AlertShadowCoverageContract.capabilitySha256(input)
            .matches("^[a-f0-9]{64}$"));
    }

    @Test
    public void bodyNeverContainsActivityOrNotificationFields() {
        String body = AlertShadowCoverageContract.body(
            "token", "c1", "0.5.20", repeat("a", 64),
            "2026-07-27T10:00:00.000Z",
            UUID.fromString("00000000-0000-4000-8000-000000000001"));
        assertFalse(body.contains("behavior"));
        assertFalse(body.contains("notification"));
        assertFalse(body.contains("activity"));
        assertTrue(body.contains("\"collector_contract\":\"android-passive-v1\""));
        assertTrue(body.contains("\"collector_state\":\"operational\""));
        assertTrue(body.contains("\"client_id\":\"c1\""));
    }

    private static String repeat(String value, int count) {
        StringBuilder result = new StringBuilder(value.length() * count);
        for (int i = 0; i < count; i++) result.append(value);
        return result.toString();
    }
}
