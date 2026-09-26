import Foundation

/// Finds an interval containing recent positive steps. The lower bound is a
/// conservative activity time; CMPedometer exposes no individual step times.
enum MotionEvidenceWindow {
    static let maximumWidth: TimeInterval = 60
    static let maximumQueries = 16
    struct Interval: Equatable {
        let start: Date
        let end: Date
    }
    enum Result: Equatable {
        case pending
        case empty
        case failed
        case positive(Interval, Int, Int)
    }
    final class Search {
        private var interval: Interval
        private var pending: Interval?
        private var root = true
        private var confirming = false
        private(set) var queryCount = 0
        private(set) var result: Result = .pending
        init(start: Date, end: Date) {
            interval = Interval(start: start, end: end)
            if start >= end { result = .empty }
        }
        func nextQuery() -> Interval? {
            guard result == .pending, pending == nil else { return nil }
            guard queryCount < maximumQueries else { result = .failed; return nil }
            let next: Interval
            if root || confirming {
                next = interval
            } else {
                let middle = interval.start.addingTimeInterval(interval.end.timeIntervalSince(interval.start) / 2)
                next = Interval(start: middle, end: interval.end)
            }
            pending = next
            queryCount += 1
            return next
        }
        func accept(steps: Int?, floors: Int?) {
            guard result == .pending, let queried = pending else { return }
            pending = nil
            guard let steps, steps >= 0, (floors ?? 0) >= 0 else { result = .failed; return }
            let positive = steps > 0 || (floors ?? 0) > 0
            if confirming {
                result = positive ? .positive(queried, steps, floors ?? 0) : .failed
                return
            }
            if root {
                root = false
                guard positive else { result = .empty; return }
            } else if positive {
                interval = queried
            } else {
                interval = Interval(start: interval.start, end: queried.start)
            }
            if interval.end.timeIntervalSince(interval.start) <= maximumWidth {
                confirming = true
            }
        }
    }
}
