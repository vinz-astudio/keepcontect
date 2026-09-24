import Foundation

/// The evidence validator accepts at most seven days of historical positives.
enum HistoryQueryPolicy {
    static let recoveryOverlap: TimeInterval = 48 * 60 * 60

    // CoreMotion aggregates its interval and must never replay earlier steps as
    // a new observation. Only sample-ID-deduplicated HealthKit opts into overlap.
    static func start(cursor: TimeInterval, end: Date, notBefore: Date? = nil, overlap: TimeInterval = 0) -> Date {
        let endTimestamp = end.timeIntervalSince1970
        let candidate: Date
        if cursor <= 0 {
            candidate = end.addingTimeInterval(-6 * 3600)
        } else if cursor > endTimestamp {
            candidate = end
        } else {
            candidate = Date(timeIntervalSince1970: cursor).addingTimeInterval(-max(0, overlap))
        }
        let sevenDayFloor = end.addingTimeInterval(-7 * 24 * 3600)
        let floor = max(sevenDayFloor, notBefore ?? .distantPast)
        return min(end, max(candidate, floor))
    }
}
