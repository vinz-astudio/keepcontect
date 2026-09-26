package com.keepcontact.app;

import java.util.Arrays;

/** Only an explicit ingestion result can consume a durable observation. */
final class EvidenceUploadPolicy {
    enum Outcome { COMPLETE, REJECT, REVOKE, RETRY }

    static Outcome classify(int code, String status) {
        if (code == 200 && contains(status, "inserted", "duplicate")) return Outcome.COMPLETE;
        if (code == 422 && contains(status, "invalid", "outside_epoch", "conflict",
            "observed_time_out_of_range", "unsupported_evidence_class", "unsupported_qualification_policy",
            "query_does_not_contain_event")) return Outcome.REJECT;
        if (code == 400 && contains(status, "malformed_json", "invalid_request", "unknown_field",
            "invalid_event_id", "invalid_sequence", "invalid_observed_time", "invalid_qualification_facts",
            "invalid_query_interval", "invalid_correlation_id")) return Outcome.REJECT;
        if (code == 400 && contains(status, "invalid_credential", "invalid_binding_id")) return Outcome.REVOKE;
        if (code == 409 && contains(status, "revoked", "unregistered_binding", "credential_mismatch")) return Outcome.REVOKE;
        return Outcome.RETRY;
    }

    private static boolean contains(String value, String... options) {
        return value != null && Arrays.asList(options).contains(value);
    }
}
