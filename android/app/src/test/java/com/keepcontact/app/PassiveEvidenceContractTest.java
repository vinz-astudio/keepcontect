package com.keepcontact.app;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class PassiveEvidenceContractTest {
    @Test
    public void usageQualificationKeepsTrueTimestampAndNoPackageField() {
        long observedAt = 1_725_000_123_456L;
        PassiveEvidenceContract.Evidence evidence =
            PassiveEvidenceContract.directUse(observedAt, 1_725_000_000_000L, 1_725_000_200_000L);

        assertEquals(observedAt, evidence.observedAtMs);
        assertTrue(PassiveEvidenceContract.qualifiesUsageEvent(PassiveEvidenceContract.USAGE_KEYGUARD_HIDDEN));
        assertTrue(PassiveEvidenceContract.qualifiesUsageEvent(PassiveEvidenceContract.USAGE_USER_INTERACTION));
        assertTrue(PassiveEvidenceContract.qualifiesUsageEvent(PassiveEvidenceContract.USAGE_ACTIVITY_RESUMED));
        assertFalse(PassiveEvidenceContract.qualifiesUsageEvent(PassiveEvidenceContract.USAGE_SCREEN_ON));
        assertFalse(evidence.toJson("binding", "credential", 4).contains("package"));
        assertTrue(evidence.toJson("binding", "credential", 4).contains(
            PassiveEvidenceContract.iso(observedAt)));
    }

    @Test
    public void onlyPedestrianWalkingOrRunningQualifies() {
        assertTrue(PassiveEvidenceContract.qualifiesPedestrianTransition(7));
        assertTrue(PassiveEvidenceContract.qualifiesPedestrianTransition(8));
        assertFalse(PassiveEvidenceContract.qualifiesPedestrianTransition(0));
        assertFalse(PassiveEvidenceContract.qualifiesPedestrianTransition(3));
    }

    @Test
    public void chargingNeedsKnownBaselineAndFiveStableSeconds() {
        PassiveEvidenceContract.PowerTracker tracker = new PassiveEvidenceContract.PowerTracker();
        assertNull(tracker.observe(true, 1_000L));
        assertNull(tracker.confirm(true, 6_000L));

        assertNull(tracker.observe(false, 10_000L));
        assertNull(tracker.confirm(false, 14_999L));
        PassiveEvidenceContract.Evidence edge = tracker.confirm(false, 15_000L);
        assertNotNull(edge);
        assertEquals("power_transition", edge.evidenceClass);
        assertTrue(edge.qualificationFacts.contains("\"stable_for_ms\":5000"));
    }

    @Test
    public void chargingFlapIsSuppressedAndNearbyEdgesShareCorrelation() {
        PassiveEvidenceContract.PowerTracker tracker = new PassiveEvidenceContract.PowerTracker();
        tracker.observe(false, 0L);
        tracker.confirm(false, 5_000L);
        tracker.observe(true, 10_000L);
        tracker.observe(false, 12_000L);
        assertNull(tracker.confirm(true, 15_000L));

        tracker.observe(true, 20_000L);
        PassiveEvidenceContract.Evidence first = tracker.confirm(true, 25_000L);
        tracker.observe(false, 40_000L);
        PassiveEvidenceContract.Evidence second = tracker.confirm(false, 45_000L);
        assertNotNull(first);
        assertNotNull(second);
        assertEquals(first.correlationId, second.correlationId);
    }

    @Test
    public void bindingChangeResetsSequenceAndQueueContract() {
        PassiveEvidenceContract.BindingState current =
            new PassiveEvidenceContract.BindingState("old", 9L, 3);
        PassiveEvidenceContract.BindingState same =
            PassiveEvidenceContract.bind(current, "old");
        assertEquals(9L, same.nextSequence);
        assertEquals(3, same.queuedCount);

        PassiveEvidenceContract.BindingState switched =
            PassiveEvidenceContract.bind(current, "new");
        assertEquals(0L, switched.nextSequence);
        assertEquals(0, switched.queuedCount);
        assertTrue(PassiveEvidenceContract.clearBinding(switched).bindingId == null);
    }
}
