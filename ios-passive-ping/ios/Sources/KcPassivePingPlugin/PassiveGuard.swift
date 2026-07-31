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
    private static let minPingInterval: TimeInterval = 30
    private static let maxQueuedPings = 200

    private enum Key {
        static let supabaseUrl = "kc.passive.supabaseUrl"
        static let token = "kc.passive.token"
        static let queue = "kc.passive.queue"
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
        flushQueue()
    }

    func configure(supabaseUrl: String, token: String) {
        defaults.set(supabaseUrl, forKey: Key.supabaseUrl)
        defaults.set(token, forKey: Key.token)
        if defaults.double(forKey: Key.connectedAt) == 0 {
            defaults.set(Date().timeIntervalSince1970, forKey: Key.connectedAt)
        }
        arm()
        flushQueue()
    }

    func clear() {
        disarm()
        for key in [Key.supabaseUrl, Key.token, Key.queue, Key.lastPingAt, Key.lastEventAt, Key.connectedAt] {
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
            "queuedPings": queuedPings().count
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
        flushQueue()

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
        // Any change here turns a keepalive into location collection.
        flushQueue()
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

    // MARK: - Evidence

    func recordEvent(reason: String) {
        let now = Date()
        defaults.set(now.timeIntervalSince1970, forKey: Key.lastEventAt)

        let last = defaults.double(forKey: Key.lastPingAt)
        if last > 0, now.timeIntervalSince1970 - last < Self.minPingInterval {
            return
        }
        send(eventId: UUID().uuidString, observedAt: now, isRetry: false)
        _ = reason
    }

    private func send(eventId: String, observedAt: Date, isRetry: Bool) {
        guard let (baseUrl, token) = credentials(),
              let url = URL(string: baseUrl + "/functions/v1/ping") else { return }

        let body: [String: Any] = [
            "token": token,
            "event_id": eventId,
            "observed_at": Self.iso8601.string(from: observedAt),
            "source": Self.pingSource
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
            // A 4xx other than a transport failure means the server rejected the
            // ping on its merits; retrying cannot fix it.
            if error == nil, status >= 400, status < 500 { return }
            if !isRetry {
                self.enqueue(eventId: eventId, observedAt: observedAt)
            }
        }.resume()
    }

    // MARK: - Offline queue

    /// Pings that miss their window still get recorded, but the server's
    /// ±5-minute rule means a late one lands as analysis evidence rather than
    /// refreshing live safety. That asymmetry is intentional: a replayed unlock
    /// must never resolve an alert after the fact.
    private func enqueue(eventId: String, observedAt: Date) {
        var queue = queuedPings()
        queue.append(["event_id": eventId, "observed_at": observedAt.timeIntervalSince1970])
        if queue.count > Self.maxQueuedPings {
            queue.removeFirst(queue.count - Self.maxQueuedPings)
        }
        defaults.set(queue, forKey: Key.queue)
    }

    private func queuedPings() -> [[String: Any]] {
        defaults.array(forKey: Key.queue) as? [[String: Any]] ?? []
    }

    private func flushQueue() {
        let queue = queuedPings()
        guard !queue.isEmpty, credentials() != nil else { return }
        defaults.removeObject(forKey: Key.queue)
        for entry in queue {
            guard let eventId = entry["event_id"] as? String,
                  let observedAt = entry["observed_at"] as? TimeInterval else { continue }
            send(eventId: eventId, observedAt: Date(timeIntervalSince1970: observedAt), isRetry: true)
        }
    }

    // MARK: - Helpers

    private func credentials() -> (String, String)? {
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
    /// Forwarded from the AppDelegate's silent-push handler.
    /// `true` means the device was unlocked and a ping was recorded.
    public static func handleSilentPush(completion: @escaping (Bool) -> Void) {
        PassiveGuard.shared.handleWake(completion: completion)
    }
}
