import Foundation

// Compile with the production policy sources. No HealthKit, signing or device
// access is needed; the full plugin still requires the Xcode build/device gate.
@main
struct EvidencePolicyRegression {
    static func main() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let beforeOutage = end.addingTimeInterval(-15 * 3600)
        precondition(HistoryQueryPolicy.start(cursor: beforeOutage.timeIntervalSince1970, end: end) == beforeOutage,
                     "A long suspended interval must not be truncated to six hours")
        precondition(HistoryQueryPolicy.start(cursor: end.addingTimeInterval(-10 * 86400).timeIntervalSince1970, end: end) == end.addingTimeInterval(-7 * 86400),
                     "History must stay inside the server's accepted horizon")
        precondition(HistoryQueryPolicy.start(cursor: end.addingTimeInterval(3600).timeIntervalSince1970, end: end) == end,
                     "A backwards wall-clock adjustment must not invert the query")
        precondition(EvidenceUploadPolicy.disposition(httpStatus: 429, bodyStatus: "rate_limited", failed: false) == .retry)
        precondition(EvidenceUploadPolicy.disposition(httpStatus: 200, bodyStatus: nil, failed: false) == .retry)
        precondition(EvidenceUploadPolicy.disposition(httpStatus: 200, bodyStatus: "inserted", failed: true) == .retry)
        precondition(EvidenceUploadPolicy.disposition(httpStatus: 500, bodyStatus: "database_error", failed: false) == .retry)
        precondition(EvidenceUploadPolicy.disposition(httpStatus: 200, bodyStatus: "inserted", failed: false) == .discard)
        precondition(EvidenceUploadPolicy.disposition(httpStatus: 200, bodyStatus: "duplicate", failed: false) == .discard)
        precondition(EvidenceUploadPolicy.disposition(httpStatus: 422, bodyStatus: "outside_epoch", failed: false) == .discard)
        precondition(EvidenceUploadPolicy.disposition(httpStatus: 422, bodyStatus: "observed_time_out_of_range", failed: false) == .discard,
                     "Expired queue entries must not block fresh observations forever")
        precondition(EvidenceUploadPolicy.disposition(httpStatus: 409, bodyStatus: "revoked", failed: false) == .revoke)
        print("iOS evidence policy: 12 checks passed")
    }
}
