import Foundation
import HealthKit

/// Wake source built on HealthKit background delivery (KC-IOS-HEALTHWAKE-SPIKE-001).
///
/// Apple documents relaunch after system termination. Whether HealthKit or the
/// significant-change wake recovers after an explicit user force-quit remains
/// unproven until the TestFlight device gate; source code must not claim it.
///
/// HealthKit is one of the few documented mechanisms that can relaunch a
/// terminated app, and unlike DeviceActivity/FamilyControls it needs no
/// entitlement approval from Apple. The shape is also unusually good for KC:
/// the thing that triggers the wake — the person walking — *is* the evidence,
/// so the carrier and the proof are the same event rather than two mechanisms
/// that have to line up.
///
/// The wake itself is health telemetry, never a check-in. It starts a bounded
/// positive-history query; only a positive step/floor sample is normalized and
/// sent, with its real sample end time. Counts and raw samples stay on-device.
final class HealthWake {
    static let shared = HealthWake()

    private struct PositiveHistorySample {
        let id: UUID
        let observedAt: Date
        let stepsPositive: Bool
        let floorsPositive: Bool
    }

    /// Whether the user has been through the authorization sheet on this
    /// install. HealthKit deliberately refuses to report *read* authorization
    /// status — that would leak whether the user has any step data — so the
    /// only honest thing to track is whether we have asked.
    private static let askedKey = "kc.health.asked"
    private static let lastQueryKey = "kc.health.lastPositiveQueryEnd"
    private static let resetFloorKey = "kc.health.historyResetFloor"
    private static let seenPositiveSamplesKey = "kc.health.seenPositiveSamples"

    private let store = HKHealthStore()
    private var observerQuery: HKObserverQuery?
    private var backgroundDeliveryEnabled: Bool?
    private var registeringDelivery = false
    private var queryInFlight = false
    private var queryGeneration = 0
    private var pendingCompletions: [() -> Void] = []
    private var pendingNeedsSample = false
    private var pendingNeedsCoverageLease = false
    private var lastQuerySucceeded: Bool?
    private var lastQueryAt: Date?
    private var lastPositiveAt: Date?
    private var lastBackgroundWakeAt: Date?

    private var stepType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .stepCount)
    }

    private var floorType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .flightsClimbed)
    }

    static var isSupported: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private var hasAsked: Bool {
        UserDefaults.standard.bool(forKey: Self.askedKey)
    }

    // MARK: - Setup

    /// Shows the Health authorization sheet the first time, then registers the
    /// wake. Safe to call repeatedly: iOS shows the sheet once per install and
    /// silently succeeds afterwards.
    func enable(completion: ((Bool) -> Void)? = nil) {
        guard Self.isSupported, let stepType else {
            completion?(false)
            return
        }
        var readTypes: Set<HKObjectType> = [stepType]
        if let floorType { readTypes.insert(floorType) }
        store.requestAuthorization(toShare: [], read: readTypes) { [weak self] granted, _ in
            guard let self else { return }
            UserDefaults.standard.set(true, forKey: Self.askedKey)
            // `granted` only reports that the sheet completed, not that the user
            // allowed reading — HealthKit never discloses that for read access.
            // Registering regardless is correct: if permission was refused the
            // observer simply never fires, which is exactly the same outcome as
            // not registering.
            DispatchQueue.main.async {
                self.resume()
                self.retryHistory()
                completion?(granted)
            }
        }
    }

    /// Re-arms the observer. Must run on **every** process start, including the
    /// background relaunches this spike is trying to prove exist: the
    /// background-delivery registration survives a relaunch, but the observer
    /// query itself does not — iOS relaunches the app and then expects to find
    /// an observer to call.
    func resume() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.resume() }
            return
        }
        guard Self.isSupported, let stepType, hasAsked else { return }

        if observerQuery == nil {
            let query = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, completionHandler, error in
                guard error == nil, let self else {
                    completionHandler()
                    return
                }
                DispatchQueue.main.async {
                    self.lastBackgroundWakeAt = Date()
                    self.onWake(completion: completionHandler)
                }
            }
            observerQuery = query
            store.execute(query)
        }

        // `.immediate` is a request, not a promise: the system caps step count
        // to roughly hourly. Asking for the finest granularity and letting iOS
        // coarsen it is better than pre-coarsening it ourselves.
        guard backgroundDeliveryEnabled != true, !registeringDelivery else { return }
        registeringDelivery = true
        let generation = queryGeneration
        store.enableBackgroundDelivery(for: stepType, frequency: .immediate) { [weak self] success, _ in
            DispatchQueue.main.async {
                guard let self, generation == self.queryGeneration else { return }
                self.registeringDelivery = false
                self.backgroundDeliveryEnabled = success
                self.retryHistory()
            }
        }
    }

    /// Retry unread history after foreground/unlock. Neither wake nor an empty
    /// result is activity. A denied/locked query must not consume its interval.
    func retryHistory(reportCoverageLease: Bool = true, completion: (() -> Void)? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.retryHistory(reportCoverageLease: reportCoverageLease, completion: completion)
            }
            return
        }
        guard hasAsked, observerQuery != nil else {
            completion?()
            return
        }
        onWake(captureSample: false, reportCoverageLease: reportCoverageLease) {
            completion?()
        }
    }

    private func onWake(
        captureSample: Bool = true,
        reportCoverageLease: Bool = true,
        completion: @escaping () -> Void
    ) {
        guard observerQuery != nil, PassiveGuard.shared.isEvidenceConfigured else {
            completion()
            return
        }
        pendingCompletions.append(completion)
        pendingNeedsSample = pendingNeedsSample || captureSample
        pendingNeedsCoverageLease = pendingNeedsCoverageLease || reportCoverageLease
        guard !queryInFlight else { return }
        queryInFlight = true
        let generation = queryGeneration
        let callbacks = pendingCompletions
        let needsSample = pendingNeedsSample
        let needsCoverageLease = pendingNeedsCoverageLease
        pendingCompletions = []
        pendingNeedsSample = false
        pendingNeedsCoverageLease = false
        // The lease goes first and unconditionally. It says "the watcher was
        // awake here", which is true of this wake whether or not the sample
        // below finds anything worth reporting.
        if needsCoverageLease { PassiveGuard.shared.reportCoverageLease() }
        queryPositiveHistory { samples, queryStart, queryEnd in
            guard generation == self.queryGeneration else {
                self.queryInFlight = false
                callbacks.forEach { $0() }
                self.drainPendingQueries()
                return
            }
            if let latest = samples.max(by: { $0.observedAt < $1.observedAt }) {
                if self.lastPositiveAt == nil || latest.observedAt > self.lastPositiveAt! {
                    self.lastPositiveAt = latest.observedAt
                }
            }
            let cutoff = queryEnd.addingTimeInterval(-7 * 24 * 3600).timeIntervalSince1970
            let storedSeen = UserDefaults.standard.dictionary(forKey: Self.seenPositiveSamplesKey) as? [String: TimeInterval] ?? [:]
            var seen: [String: TimeInterval] = [:]
            for (sampleID, timestamp) in storedSeen where timestamp >= cutoff {
                seen[sampleID] = timestamp
            }
            let unseen = samples.filter { seen[$0.id.uuidString] == nil }
            if let sample = unseen.max(by: { $0.observedAt < $1.observedAt }) {
                PassiveGuard.shared.recordMotionEvidence(
                    observedAt: sample.observedAt,
                    stepsPositive: sample.stepsPositive,
                    floorsPositive: sample.floorsPositive,
                    automotive: false,
                    queryStart: queryStart,
                    queryEnd: queryEnd
                )
            }
            for sample in samples {
                seen[sample.id.uuidString] = sample.observedAt.timeIntervalSince1970
            }
            UserDefaults.standard.set(seen, forKey: Self.seenPositiveSamplesKey)
            let finished = {
                DispatchQueue.main.async {
                    self.queryInFlight = false
                    callbacks.forEach { $0() }
                    self.drainPendingQueries()
                }
            }
            if needsSample {
                PassiveGuard.shared.captureSample(trigger: "health-wake", completion: finished)
            } else {
                // A foreground history retry is not a Health background wake.
                // Avoid starting a second CoreMotion sample beside the one the
                // foreground/unlock path already requested.
                PassiveGuard.shared.finishBackgroundEvidence(deadline: Date().addingTimeInterval(5), completion: finished)
            }
        }
    }

    private func drainPendingQueries() {
        guard !pendingCompletions.isEmpty else { return }
        // Wakes arriving during a query must get a new end time, rather than
        // being acknowledged against a query that predates their samples.
        let pending = pendingCompletions
        let needsSample = pendingNeedsSample
        let needsCoverageLease = pendingNeedsCoverageLease
        pendingCompletions = []
        pendingNeedsSample = false
        pendingNeedsCoverageLease = false
        onWake(captureSample: needsSample, reportCoverageLease: needsCoverageLease) {
            pending.forEach { $0() }
        }
    }

    private func queryPositiveHistory(
        completion: @escaping ([PositiveHistorySample], Date, Date) -> Void
    ) {
        let end = Date()
        let stored = UserDefaults.standard.double(forKey: Self.lastQueryKey)
        let resetTimestamp = UserDefaults.standard.double(forKey: Self.resetFloorKey)
        let notBefore = resetTimestamp > 0 ? Date(timeIntervalSince1970: resetTimestamp) : nil
        let start = HistoryQueryPolicy.start(cursor: stored, end: end, notBefore: notBefore, overlap: HistoryQueryPolicy.recoveryOverlap)
        let generation = queryGeneration
        let predicateOptions: HKQueryOptions = notBefore == nil ? [] : [.strictStartDate]
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: predicateOptions)
        let group = DispatchGroup()
        let lock = NSLock()
        var positives: [PositiveHistorySample] = []
        var allQueriesSucceeded = true

        func run(_ type: HKQuantityType?, floors: Bool) {
            guard let type else { return }
            group.enter()
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                defer { group.leave() }
                lock.lock()
                defer { lock.unlock() }
                guard error == nil, let samples = samples as? [HKQuantitySample] else {
                    allQueriesSucceeded = false
                    return
                }
                for sample in samples where sample.endDate <= end && sample.quantity.doubleValue(for: HKUnit.count()) > 0 {
                    positives.append(PositiveHistorySample(
                        id: sample.uuid,
                        observedAt: sample.endDate,
                        stepsPositive: !floors,
                        floorsPositive: floors
                    ))
                }
            }
            store.execute(query)
        }

        run(stepType, floors: false)
        run(floorType, floors: true)
        group.notify(queue: .main) {
            guard generation == self.queryGeneration else {
                completion([], start, end)
                return
            }
            self.lastQueryAt = end
            self.lastQuerySucceeded = allQueriesSucceeded
            if allQueriesSucceeded {
                UserDefaults.standard.set(end.timeIntervalSince1970, forKey: Self.lastQueryKey)
            }
            // A failed floors read must not discard successfully read steps (or
            // vice versa). Keep the cursor for retrying the failed interval;
            // sample IDs prevent uploading the successful results again.
            completion(positives, start, end)
        }
    }

    /// Sign-out. The authorization itself is the user's to revoke in the Health
    /// app; what KC must drop is the standing wake registration, otherwise a
    /// logged-out device keeps being relaunched to record observations that
    /// belong to nobody.
    func disable() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.disable() }
            return
        }
        queryGeneration += 1
        registeringDelivery = false
        backgroundDeliveryEnabled = nil
        let pending = pendingCompletions
        pendingCompletions = []
        pendingNeedsSample = false
        pendingNeedsCoverageLease = false
        pending.forEach { $0() }
        if let query = observerQuery {
            store.stop(query)
            observerQuery = nil
        }
        guard Self.isSupported, let stepType else { return }
        store.disableBackgroundDelivery(for: stepType) { _, _ in }
    }

    func resetHistoryAnchor() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.resetHistoryAnchor() }
            return
        }
        queryGeneration += 1
        registeringDelivery = false
        lastQuerySucceeded = nil
        lastQueryAt = nil
        lastPositiveAt = nil
        lastBackgroundWakeAt = nil
        let resetAt = Date()
        UserDefaults.standard.set(resetAt.timeIntervalSince1970, forKey: Self.lastQueryKey)
        UserDefaults.standard.set(resetAt.timeIntervalSince1970, forKey: Self.resetFloorKey)
        UserDefaults.standard.removeObject(forKey: Self.seenPositiveSamplesKey)
    }

    /// Whether a relaunch-capable wake is actually armed right now, as opposed
    /// to merely entitled. The coverage lease reports capability, and an
    /// entitlement nobody granted would overstate what this install can see.
    var isObserving: Bool {
        if !Thread.isMainThread { return DispatchQueue.main.sync { self.isObserving } }
        return observerQuery != nil && backgroundDeliveryEnabled == true
    }

    func status() -> [String: Any] {
        if !Thread.isMainThread { return DispatchQueue.main.sync { self.status() } }
        return [
            "supported": Self.isSupported,
            "asked": hasAsked,
            "observing": observerQuery != nil,
            "backgroundDeliveryEnabled": backgroundDeliveryEnabled as Any? ?? NSNull(),
            "lastQuerySucceeded": lastQuerySucceeded as Any? ?? NSNull(),
            "lastQueryAt": (lastQueryAt?.timeIntervalSince1970).map { $0 * 1000 } as Any? ?? NSNull(),
            "lastPositiveAt": (lastPositiveAt?.timeIntervalSince1970).map { $0 * 1000 } as Any? ?? NSNull(),
            "lastBackgroundWakeAt": (lastBackgroundWakeAt?.timeIntervalSince1970).map { $0 * 1000 } as Any? ?? NSNull()
        ]
    }
}
