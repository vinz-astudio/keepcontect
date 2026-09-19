import Foundation

/// The evidence validator accepts at most seven days of historical positives.
enum HistoryQueryPolicy {
    static func start(cursor: TimeInterval, end: Date) -> Date {
        let candidate = cursor > 0 ? Date(timeIntervalSince1970: cursor) : end.addingTimeInterval(-6 * 3600)
        return min(end, max(candidate, end.addingTimeInterval(-7 * 24 * 3600)))
    }
}
