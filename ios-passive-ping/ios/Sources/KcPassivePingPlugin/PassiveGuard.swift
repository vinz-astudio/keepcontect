import CoreLocation
import Foundation
import UIKit

/// Unlock-evidence collector for the iOS passive guard (KC-IOS-UNLOCK-SPIKE-001).
///
/// The product question this answers: after a one-time setup inside KC, can an
/// ordinary phone unlock produce a liveness ping without the user ever opening
/// KC again?
///
/// iOS only delivers `protectedDataDidBecomeAvailable` to a process that is
/// actually executing — a suspended app never sees it and gets no replay on
/// resume. iOS also exposes no readable history of unlocks, so there is nothing
/// to reconstruct after the fact. Exact unlock events are therefore a bonus we
/// take whenever the process happens to be running, never something to depend
/// on.
///
/// The dependable path is the other way round: the server wakes the device with
/// a silent push, and the device answers with the one thing it can always
/// establish at that instant — whether it is currently unlocked. That is
/// sampled evidence rather than an event stream, which is enough because the
/// alert model sessionises activity at thirty minutes and never sees finer
/// detail anyway.
///
/// Location appears here only as significant-change monitoring, purely to
/// recover a force-quit app. No coordinate is ever read, stored, or sent.
final class PassiveGuard: NSObject, CLLocationManagerDelegate {
    static let shared = PassiveGuard()

    /// Matches the Android collector's contract: same endpoint, same body,
    /// same `source` value, so the backend needs no change to accept iOS.
    private static let pingSource = "capacitor"
    /// Real unlocks are minutes apart; this only collapses lock/unlock fidgeting.
    private static let minRecordInterval: TimeInterval = 30
    private static let maxRecordEntries = 500

    private enum Key {
        static let supabaseUrl = "kc.passive.supabaseUrl"
        static let token = "kc.passive.token"
        static let record = "kc.passive.record"
        static let lastRecordedAt = "kc.passive.lastRecordedAt"
        static let lastPingAt = "kc.passive.lastPingAt"
        static let lastEventAt = "kc.passive.lastEventAt"
        static let connectedAt = "kc.passive.connectedAt"
    }

    private let defaults = UserDefaults.standard
    private let locationManager = CLLocationManager()
    private let session: URLSession
    private var observers: [NSObjectProtocol] = []
    private var armed = false

    private override init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration)
        super.init()
        locationManager.delegate = self
    }

    // MARK: - Lifecycle

    /// Called from the plugin's `load()` on every process start, including the
    /// background relaunches iOS performs after a significant location change.
    /// Without this the watcher would only exist in sessions the user started.
    func resumeIfConfigured() {
        guard credentials() != nil else { return }
        arm()
        // A HealthKit relaunch lands here: the observer query does not survive
        // process death, so without this the very wake KC is trying to prove
        // would be the last one it ever got.
        HealthWake.shared.resume()
        flushRecord()
    }

    func configure(supabaseUrl: String, token: String) {
        defaults.set(supabaseUrl, forKey: Key.supabaseUrl)
        defaults.set(token, forKey: Key.token)
        if defaults.double(forKey: Key.connectedAt) == 0 {
            defaults.set(Date().timeIntervalSince1970, forKey: Key.connectedAt)
        }
        // Anchored here rather than on the first push, so a fresh install never
        // replays a week of history as if it had just happened.
        NotifyFeed.primeCursorIfNeeded()
        arm()
        flushRecord()
    }

    func clear() {
        disarm()
        HealthWake.shared.disable()
        // The cursor goes too: the next account to configure this install must
        // start from its own "now", not inherit the previous one's position.
        NotifyFeed.resetCursor()
        for key in [Key.supabaseUrl, Key.token, Key.record, Key.lastPingAt, Key.lastEventAt, Key.lastRecordedAt, Key.connectedAt] {
            defaults.removeObject(forKey: key)
        }
    }

    func status() -> [String: Any] {
        let authorized: Bool
        switch locationManager.authorizationStatus {
        case .authorizedAlways: authorized = true
        default: authorized = false
        }
        return [
            "enabled": credentials() != nil && armed,
            "connectedAt": defaults.double(forKey: Key.connectedAt) * 1000,
            "lastEventAt": defaults.double(forKey: Key.lastEventAt) * 1000,
            "lastPingAt": defaults.double(forKey: Key.lastPingAt) * 1000,
            "keepAliveGranted": authorized,
            "pendingRecords": recordSize()
        ]
    }

    // MARK: - Watching

    private func arm() {
        guard !armed else { return }
        armed = true

        // Exact unlock signal. Only fires while this process happens to be
        // executing, so it is opportunistic precision, not the mechanism KC
        // relies on.
        observers.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.protectedDataDidBecomeAvailableNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.recordEvent(reason: "unlock")
            }
        )

        // Foreground use is evidence too, and matches the Android collector's
        // app-open ping.
        observers.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.recordEvent(reason: "foreground")
            }
        )

        armRecoveryWake()
    }

    private func disarm() {
        armed = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        locationManager.stopMonitoringSignificantLocationChanges()
    }

    /// Registers the one location service that survives a user force-quit.
    ///
    /// This is deliberately NOT a keepalive. An earlier version held a
    /// continuous location session so the in-process unlock notification would
    /// keep arriving; that session is what put a location indicator in the
    /// status bar and drew a battery baseline, and it has been removed.
    ///
    /// Significant-change monitoring is register-and-forget: nothing runs until
    /// the device actually moves between cell towers, at which point iOS
    /// relaunches the app — the only documented mechanism that still works
    /// after the user swipes KC away. Silent push is the primary wake path;
    /// this exists purely so a force-quit device is not lost forever.
    private func armRecoveryWake() {
        locationManager.requestAlwaysAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        // No startUpdatingLocation, no allowsBackgroundLocationUpdates: those
        // are what a persistent session needs, and we do not want one.
        locationManager.startMonitoringSignificantLocationChanges()
    }

    /// Called when a silent push wakes the process. The push proves the device
    /// is reachable, which is not the same as the user being active, so the
    /// evidence comes from the lock state instead: protected data is available
    /// only after the user has unlocked the device and while it stays unlocked.
    ///
    /// A locked device deliberately reports nothing. Treating mere
    /// reachability as liveness would let a phone sitting on a table refresh
    /// the heartbeat forever, which is the one failure mode that would make KC
    /// worse than having no monitoring at all.
    func handleWake(completion: @escaping (Bool) -> Void) {
        guard credentials() != nil else {
            completion(false)
            return
        }
        arm()
        flushRecord()

        let unlocked = UIApplication.shared.isProtectedDataAvailable
        if unlocked {
            recordEvent(reason: "wake-sample")
        }
        completion(unlocked)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Deliberately empty. Coordinates are never read, stored, or sent —
        // the fix exists only to prove to iOS that this process is doing work.
        // Any change here turns location into collection.
        // A relaunch by significant change is also a chance to hand over the record.
        flushRecord()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keepalive is best effort; a failed fix is not an app-level problem.
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard credentials() != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            armRecoveryWake()
        default:
            break
        }
    }

    // MARK: - Local record

    /// Every observation lands here first — nothing is reported the instant it
    /// happens. The device keeps its own record and hands it over when it can
    /// (on a wake, on a foreground, or opportunistically), which is the whole
    /// point of the design: the server asks, the device answers with what it
    /// accumulated, instead of the device chattering per event.
    ///
    /// It also collapses what used to be two separate ideas — an "offline
    /// queue" and a "local record" — into one. A ping that failed to send and
    /// an observation that has not been asked for yet are the same thing.
    /// `kind` is what the server records the ping as, and it is the only way to
    /// tell later how a ping was produced: `reason` has never left the device,
    /// so today every iOS ping arrives indistinguishable from every other one.
    /// It defaults to `app` so existing callers keep their meaning.
    func recordEvent(reason: String, kind: String = "app") {
        let now = Date()
        defaults.set(now.timeIntervalSince1970, forKey: Key.lastEventAt)

        let last = defaults.double(forKey: Key.lastRecordedAt)
        if last > 0, now.timeIntervalSince1970 - last < Self.minRecordInterval {
            return
        }
        defaults.set(now.timeIntervalSince1970, forKey: Key.lastRecordedAt)

        append(entry: [
            "event_id": UUID().uuidString,
            "observed_at": now.timeIntervalSince1970,
            "reason": reason,
            "kind": kind
        ])
        flushRecord()
    }

    private func append(entry: [String: Any]) {
        var record = localRecord()
        record.append(entry)
        // The oldest entries are the least useful: anything past the server's
        // ±5-minute window is already analysis-only evidence.
        if record.count > Self.maxRecordEntries {
            record.removeFirst(record.count - Self.maxRecordEntries)
        }
        defaults.set(record, forKey: Key.record)
    }

    private func localRecord() -> [[String: Any]] {
        defaults.array(forKey: Key.record) as? [[String: Any]] ?? []
    }

    func recordSize() -> Int { localRecord().count }

    /// Hands the accumulated record to the server, one entry per request
    /// because that is the contract `/functions/v1/ping` already speaks — no
    /// backend change is needed to adopt this model.
    ///
    /// Entries that arrive outside the server's ±5-minute window are stored as
    /// analysis evidence and deliberately do not refresh live safety. A
    /// replayed unlock must never resolve an alert after the fact.
    private func flushRecord() {
        let record = localRecord()
        guard !record.isEmpty, credentials() != nil else { return }
        // Cleared up front so a slow flush cannot double-send; anything that
        // fails is put back by `send`.
        defaults.removeObject(forKey: Key.record)
        for entry in record {
            guard let eventId = entry["event_id"] as? String,
                  let observedAt = entry["observed_at"] as? TimeInterval else { continue }
            send(
                eventId: eventId,
                observedAt: Date(timeIntervalSince1970: observedAt),
                reason: entry["reason"] as? String ?? "unknown",
                // Entries written by an earlier build carry no kind; they were
                // all app-level observations, so that is the honest default.
                kind: entry["kind"] as? String ?? "app"
            )
        }
    }

    private func send(eventId: String, observedAt: Date, reason: String, kind: String) {
        guard let (baseUrl, token) = credentials(),
              let url = URL(string: baseUrl + "/functions/v1/ping") else { return }

        let body: [String: Any] = [
            "token": token,
            "event_id": eventId,
            "observed_at": Self.iso8601.string(from: observedAt),
            "source": Self.pingSource,
            // An older server ignores this field, so a client that ships ahead
            // of the function deploy degrades to the previous behaviour rather
            // than failing.
            "kind": kind
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload

        session.dataTask(with: request) { [weak self] _, response, error in
            guard let self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if error == nil, status > 0, status < 400 {
                self.defaults.set(Date().timeIntervalSince1970, forKey: Key.lastPingAt)
                return
            }
            // A 4xx is the server rejecting this entry on its merits; keeping it
            // would just retry the same rejection forever.
            if error == nil, status >= 400, status < 500 { return }
            self.append(entry: [
                "event_id": eventId,
                "observed_at": observedAt.timeIntervalSince1970,
                "reason": reason,
                "kind": kind
            ])
        }.resume()
    }

    // MARK: - Helpers

    /// Internal rather than private: `NotifyFeed` authenticates against the
    /// same heartbeat token, and duplicating the UserDefaults keys would let
    /// the two drift apart.
    func credentials() -> (String, String)? {
        guard let baseUrl = defaults.string(forKey: Key.supabaseUrl),
              let token = defaults.string(forKey: Key.token),
              !baseUrl.isEmpty, !token.isEmpty else { return nil }
        return (baseUrl, token)
    }

    /// Byte-identical to the Android collector's timestamp format.
    private static let iso8601: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

/// Entry point for the app target, which cannot see internal types in this pod.
public enum KcPassiveBridge {
    /// Call from `didFinishLaunchingWithOptions`. A cold-start notification tap
    /// is delivered as soon as a delegate exists, so registering later — from a
    /// plugin's `load()`, say — can miss the launch that carried it.
    public static func registerNotificationTapCapture() {
        NotificationTap.shared.register()
    }

    /// Forwarded from the AppDelegate's silent-push handler.
    ///
    /// The wake-up serves two purposes at once: it samples whether the device is
    /// unlocked (liveness), and it is the only moment a suspended app can learn
    /// that a notification is waiting. Both run on every push — a device that
    /// answers "still locked" is exactly the device whose owner needs to be
    /// shown the alert.
    ///
    /// `true` means something arrived, which iOS reads as a reason to keep
    /// granting this app background wake-ups.
    public static func handleSilentPush(completion: @escaping (Bool) -> Void) {
        let group = DispatchGroup()
        var recordedPing = false
        var postedNotification = false

        group.enter()
        PassiveGuard.shared.handleWake { recorded in
            recordedPing = recorded
            group.leave()
        }

        group.enter()
        NotifyFeed.fetchAndPost { posted in
            postedNotification = posted
            group.leave()
        }

        group.notify(queue: .main) {
            completion(recordedPing || postedNotification)
        }
    }
}
