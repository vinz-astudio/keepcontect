import Foundation

enum EvidenceUploadDisposition: Equatable { case retry, discard, revoke }

enum EvidenceUploadPolicy {
    static func disposition(httpStatus: Int, bodyStatus: String?, failed: Bool) -> EvidenceUploadDisposition {
        guard !failed, let bodyStatus else { return .retry }
        if httpStatus == 200 && ["inserted", "duplicate"].contains(bodyStatus) { return .discard }
        if httpStatus == 422 && [
            "invalid", "outside_epoch", "conflict", "observed_time_out_of_range",
            "unsupported_evidence_class", "unsupported_qualification_policy", "query_does_not_contain_event"
        ].contains(bodyStatus) { return .discard }
        if httpStatus == 400 && [
            "malformed_json", "invalid_request", "unknown_field", "invalid_event_id", "invalid_sequence",
            "invalid_observed_time", "invalid_qualification_facts", "invalid_query_interval", "invalid_correlation_id"
        ].contains(bodyStatus) { return .discard }
        if httpStatus == 400 && ["invalid_credential", "invalid_binding_id"].contains(bodyStatus) { return .revoke }
        if httpStatus == 409 && ["revoked", "unregistered_binding", "credential_mismatch"].contains(bodyStatus) { return .revoke }
        // Rate limits, gateways, malformed responses and transport failures
        // never acknowledge an observation. Retry its persisted event identity.
        return .retry
    }
}
