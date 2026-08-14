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

    /// Whether the user has been through the authorization sheet on this
    /// install. HealthKit deliberately refuses to report *read* authorization
    /// status — that would leak whether the user has any step data — so the
    /// only honest thing to track is whether we have asked.
    private static let askedKey = "kc.health.asked"
    private static let lastQueryKey = "kc.health.lastPositiveQueryEnd"

    private let store = HKHealthStore()
    private var observerQuery: HKObserverQuery?

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
            self.resume()
            completion?(granted)
        }
    }

    /// Re-arms the observer. Must run on **every** process start, including the
    /// background relaunches this spike is trying to prove exist: the
    /// background-delivery registration survives a relaunch, but the observer
    /// query itself does not — iOS relaunches the app and then expects to find
    /// an observer to call.
    func resume() {
        guard Self.isSupported, let stepType, hasAsked, observerQuery == nil else { return }

        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil, let self else {
                completionHandler()
                return
            }
            self.onWake(completion: completionHandler)
        }
        observerQuery = query
        store.execute(query)

        // `.immediate` is a request, not a promise: the system caps step count
        // to roughly hourly. Asking for the finest granularity and letting iOS
        // coarsen it is better than pre-coarsening it ourselves.
        store.enableBackgroundDelivery(for: stepType, frequency: .immediate) { _, _ in
            // A failure here is not actionable at runtime — it means the
            // entitlement is missing from the build, which the spike's own
            // absence of wakes will reveal.
        }
    }

    private func onWake(completion: @escaping () -> Void) {
        // The lease goes first and unconditionally. It says "the watcher was
        // awake here", which is true of this wake whether or not the sample
        // below finds anything worth reporting.
        PassiveGuard.shared.reportCoverageLease()
        queryPositiveHistory { observedAt, stepsPositive, floorsPositive, queryStart, queryEnd in
            if let observedAt {
                PassiveGuard.shared.recordMotionEvidence(
                    observedAt: observedAt,
                    stepsPositive: stepsPositive,
                    floorsPositive: floorsPositive,
                    automotive: false,
                    queryStart: queryStart,
                    queryEnd: queryEnd
                )
            }
            PassiveGuard.shared.captureSample(trigger: "health-wake", completion: completion)
        }
    }

    private func queryPositiveHistory(
        completion: @escaping (Date?, Bool, Bool, Date, Date) -> Void
    ) {
        let end = Date()
        let stored = UserDefaults.standard.double(forKey: Self.lastQueryKey)
        let start = stored > 0
            ? Date(timeIntervalSince1970: stored)
            : end.addingTimeInterval(-6 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let group = DispatchGroup()
        let lock = NSLock()
        var latest: Date?
        var stepsPositive = false
        var floorsPositive = false

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
                guard error == nil, let samples = samples as? [HKQuantitySample] else { return }
                lock.lock()
                defer { lock.unlock() }
                for sample in samples where sample.quantity.doubleValue(for: HKUnit.count()) > 0 {
                    if floors { floorsPositive = true } else { stepsPositive = true }
                    if latest == nil || sample.endDate > latest! { latest = sample.endDate }
                }
            }
            store.execute(query)
        }

        run(stepType, floors: false)
        run(floorType, floors: true)
        group.notify(queue: .main) {
            UserDefaults.standard.set(end.timeIntervalSince1970, forKey: Self.lastQueryKey)
            completion(latest, stepsPositive, floorsPositive, start, end)
        }
    }

    /// Sign-out. The authorization itself is the user's to revoke in the Health
    /// app; what KC must drop is the standing wake registration, otherwise a
    /// logged-out device keeps being relaunched to record observations that
    /// belong to nobody.
    func disable() {
        if let query = observerQuery {
            store.stop(query)
            observerQuery = nil
        }
        guard Self.isSupported, let stepType else { return }
        store.disableBackgroundDelivery(for: stepType) { _, _ in }
    }

    func resetHistoryAnchor() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastQueryKey)
    }

    /// Whether a relaunch-capable wake is actually armed right now, as opposed
    /// to merely entitled. The coverage lease reports capability, and an
    /// entitlement nobody granted would overstate what this install can see.
    var isObserving: Bool {
        observerQuery != nil
    }

    func status() -> [String: Any] {
        [
            "supported": Self.isSupported,
            "asked": hasAsked,
            "observing": observerQuery != nil
        ]
    }
}
