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
/// resume. So the guard needs a background mode to stay alive, and location is
/// the only one that both survives termination (via significant-location
/// relaunch) and does not require faking an unrelated feature.
///
/// Location is the power source, never the evidence. `didUpdateLocations`
/// discards every fix without reading, storing, or transmitting a coordinate,
/// and no location value ever reaches the network layer below. The only thing
/// that produces a ping is the unlock notification itself.
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

        // The unlock signal itself. Only fires while this process is executing,
        // which is exactly what the location keepalive below buys us.
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

        startKeepAlive()
    }

    private func disarm() {
        armed = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.allowsBackgroundLocationUpdates = false
    }

    /// Keeps the process executing so unlock notifications keep arriving.
    /// Tuned to be as cheap and as blind as possible: three-kilometre accuracy
    /// never wakes GPS, and an infinite distance filter means iOS has no reason
    /// to deliver updates at all.
    private func startKeepAlive() {
        locationManager.requestAlwaysAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = CLLocationDistanceMax
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = false
        // Requires the `location` UIBackgroundModes entry; iOS throws without it.
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.startUpdatingLocation()
        // Survives termination: iOS relaunches the app on a significant change,
        // and `resumeIfConfigured()` re-arms the watcher.
        locationManager.startMonitoringSignificantLocationChanges()
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
            startKeepAlive()
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
