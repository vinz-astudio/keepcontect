import Foundation
import HealthKit

/// Wake source built on HealthKit background delivery (KC-IOS-HEALTHWAKE-SPIKE-001).
///
/// Everything else KC has on iOS needs the app to already be executing when the
/// human does something: `protectedDataDidBecomeAvailable` is only delivered to
/// a running process, and APNs background pushes are not delivered at all once
/// the user has swiped the app away. So a force-quit KC currently produces no
/// evidence until the user opens it again, which is indistinguishable from the
/// user being in trouble.
///
/// HealthKit is one of the few documented mechanisms that can relaunch a
/// terminated app, and unlike DeviceActivity/FamilyControls it needs no
/// entitlement approval from Apple. The shape is also unusually good for KC:
/// the thing that triggers the wake — the person walking — *is* the evidence,
/// so the carrier and the proof are the same event rather than two mechanisms
/// that have to line up.
///
/// This type deliberately does not read step counts. The spike answers one
/// question only: does a force-quit app get relaunched at all? Reading history
/// to backfill a silent window is the follow-up, and it is worthless until this
/// answer is known.
///
/// No health data leaves the device. The observer fires, KC records that a wake
/// happened, and the ping carries a timestamp and nothing else.
final class HealthWake {
    static let shared = HealthWake()

    /// Whether the user has been through the authorization sheet on this
    /// install. HealthKit deliberately refuses to report *read* authorization
    /// status — that would leak whether the user has any step data — so the
    /// only honest thing to track is whether we have asked.
    private static let askedKey = "kc.health.asked"

    private let store = HKHealthStore()
    private var observerQuery: HKObserverQuery?

    private var stepType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .stepCount)
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
        store.requestAuthorization(toShare: [], read: [stepType]) { [weak self] granted, _ in
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
            defer {
                // Not calling this is treated by iOS as a failed delivery and it
                // will back off, then stop waking the app entirely. It has to run
                // on every path, including the error path.
                completionHandler()
            }
            guard error == nil else { return }
            self?.onWake()
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

    /// The whole point of the spike: something ran while the app was not open.
    ///
    /// Recorded through the same local record every other iOS observation goes
    /// through, so it inherits the 30-second collapse and the retry-on-failure
    /// behaviour, and it is labelled `steps` so it can be told apart from a ping
    /// the user produced by opening KC. Without that label the result would be
    /// unreadable — which is exactly the position the `unlock`/`foreground`
    /// distinction is in today.
    private func onWake() {
        // The lease goes first and unconditionally. It says "the watcher was
        // awake here", which is true of this wake whether or not the sample
        // below finds anything worth reporting.
        PassiveGuard.shared.reportCoverageLease()
        PassiveGuard.shared.recordEvent(reason: "health-wake", kind: "steps")
        // The wake fired because new step data exists, so movement is already
        // implied. The sample is taken anyway for the signals movement cannot
        // supply — whether the screen is unlocked right now, how hard the
        // battery has been working, whether anything was copied. Motion says a
        // body moved; those say a person was operating the device.
        PassiveGuard.shared.captureSample(trigger: "health-wake")
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
