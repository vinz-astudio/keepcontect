import Foundation

// Compile with the production policy sources. No HealthKit, signing or device
// access is needed; the full plugin still requires the Xcode build/device gate.
@main
struct EvidencePolicyRegression {
    static func main() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let beforeOutage = end.addingTimeInterval(-15 * 3600)
        let recoveredStart = beforeOutage.addingTimeInterval(-48 * 3600)
        precondition(HistoryQueryPolicy.start(cursor: beforeOutage.timeIntervalSince1970, end: end) == beforeOutage,
                     "CoreMotion must not replay old steps as fresh activity")
        precondition(HistoryQueryPolicy.start(cursor: beforeOutage.timeIntervalSince1970, end: end, overlap: HistoryQueryPolicy.recoveryOverlap) == recoveredStart,
                     "An overlapping history query must recover samples inserted after the cursor advanced")
        let resetFloor = end.addingTimeInterval(-20 * 3600)
        precondition(HistoryQueryPolicy.start(cursor: beforeOutage.timeIntervalSince1970, end: end, notBefore: resetFloor, overlap: HistoryQueryPolicy.recoveryOverlap) == resetFloor,
                     "A binding reset must prevent history from crossing account boundaries")
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
        print("iOS evidence policy: 14 checks passed")
    }
}
