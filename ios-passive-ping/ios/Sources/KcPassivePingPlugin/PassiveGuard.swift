import CoreLocation
import Foundation
import Security
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
/// Location appears here only as significant-change monitoring. Apple
/// documents relaunch after system termination; user force-quit remains unproven
/// until the device gate. No coordinate is ever read, stored, or sent.
final class PassiveGuard: NSObject, CLLocationManagerDelegate {
    static let shared = PassiveGuard()

    /// Matches the Android collector's contract: same endpoint, same body,
    /// same `source` value, so the backend needs no change to accept iOS.
    private static let pingSource = "capacitor"
    /// Real unlocks are minutes apart; this only collapses lock/unlock fidgeting.
    private static let minRecordInterval: TimeInterval = 30
    private static let maxRecordEntries = 500
    private static let evidenceContract = "ios-passive-evidence-v1"
    private static let qualificationPolicy = "passive-qualification-v1"
    private static let powerStableSeconds: TimeInterval = 5
    private static let powerCorrelationSeconds: TimeInterval = 60
    private static let keychainService = "com.keepcontact.passive-evidence"

    private enum Key {
        static let supabaseUrl = "kc.passive.supabaseUrl"
        static let token = "kc.passive.token"
        static let clientId = "kc.passive.clientId"
        static let appVersion = "kc.passive.appVersion"
        static let record = "kc.passive.record"
        static let lastRecordedAt = "kc.passive.lastRecordedAt"
        static let lastPingAt = "kc.passive.lastPingAt"
        static let lastEventAt = "kc.passive.lastEventAt"
        static let connectedAt = "kc.passive.connectedAt"
        static let evidenceBindingId = "kc.passive.evidenceBindingId"
        static let evidenceCollectorContract = "kc.passive.evidenceContract"
        static let evidenceQueue = "kc.passive.evidenceQueue"
        static let evidenceNextSequence = "kc.passive.evidenceNextSequence"
        static let stablePowerState = "kc.passive.stablePowerState"
        static let pendingPowerState = "kc.passive.pendingPowerState"
        static let pendingPowerSince = "kc.passive.pendingPowerSince"
        static let powerCorrelationId = "kc.passive.powerCorrelationId"
        static let powerCorrelationStarted = "kc.passive.powerCorrelationStarted"
    }

    private let defaults = UserDefaults.standard
    private let locationManager = CLLocationManager()
    private let session: URLSession
    private var observers: [NSObjectProtocol] = []
    private var armed = false
    private let evidenceLock = NSLock()
    private var evidenceSending = false

    private override init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration)
        super.init()
        locationManager.delegate = self
    }

    // MARK: - Lifecycle

    /// Called from the plugin's `load()` on every process start, including
    /// HealthKit and silent-push background relaunches.
    func resumeIfConfigured() {
        guard credentials() != nil else { return }
        arm()
        // A HealthKit relaunch lands here: the observer query does not survive
        // process death, so without this the very wake KC is trying to prove
        // would be the last one it ever got.
        HealthWake.shared.resume()
        flushRecord()
    }

    func configure(
        supabaseUrl: String,
        token: String,
        clientId: String?,
        appVersion: String?,
        evidenceBindingId: String?,
        evidenceCredential: String?,
        evidenceCollectorContract: String?
    ) {
        defaults.set(supabaseUrl, forKey: Key.supabaseUrl)
        defaults.set(token, forKey: Key.token)
        // Provenance for the multi-signal samples. The web layer has always sent
        // these; iOS simply dropped them, which left every sample unable to say
        // which install it came from.
        if let clientId { defaults.set(clientId, forKey: Key.clientId) }
        if let appVersion { defaults.set(appVersion, forKey: Key.appVersion) }
        if defaults.double(forKey: Key.connectedAt) == 0 {
            defaults.set(Date().timeIntervalSince1970, forKey: Key.connectedAt)
        }
        // Anchored here rather than on the first push, so a fresh install never
        // replays a week of history as if it had just happened.
        NotifyFeed.primeCursorIfNeeded()
        configureEvidenceBinding(
            bindingId: evidenceBindingId,
            credential: evidenceCredential,
            contract: evidenceCollectorContract
        )
        initializePowerBaseline()
        arm()
        flushRecord()
        flushEvidenceQueue()
    }

    func clear() {
        disarm()
        HealthWake.shared.disable()
        // The cursor goes too: the next account to configure this install must
        // start from its own "now", not inherit the previous one's position.
        NotifyFeed.resetCursor()
        clearEvidenceBinding()
        for key in [Key.supabaseUrl, Key.token, Key.clientId, Key.appVersion, Key.record, Key.lastPingAt, Key.lastEventAt, Key.lastRecordedAt, Key.connectedAt] {
            defaults.removeObject(forKey: key)
        }
    }

    func status() -> [String: Any] {
        return [
            "enabled": credentials() != nil && armed,
            "connectedAt": defaults.double(forKey: Key.connectedAt) * 1000,
            "lastEventAt": defaults.double(forKey: Key.lastEventAt) * 1000,
            "lastPingAt": defaults.double(forKey: Key.lastPingAt) * 1000,
            "pendingRecords": recordSize(),
            "evidenceConfigured": isEvidenceConfigured
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
                self?.recordDirectEvidence(observedAt: Date())
                self?.captureSample(trigger: "unlock")
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
                self?.recordDirectEvidence(observedAt: Date())
                // The control case. A foreground sample is the only one taken
                // while a human is provably present, so it is what every
                // background sample has to be calibrated against — without it
                // there is no reference for what "in use" looks like on this
                // particular device.
                self?.captureSample(trigger: "foreground")
                // A power transition that happened while the process was
                // suspended never fires a notification; compare states now.
                // Reported at observation time: iOS does not replay the real
                // timestamp of a missed transition.
                guard let self else { return }
                self.observePowerState(self.normalizedPowerState(UIDevice.current.batteryState))
            }
        )

        // Power transitions. Battery monitoring is per-process, so it must be
        // re-armed here — background relaunches start a fresh process. The
        // notification fires only while the process runs.
        UIDevice.current.isBatteryMonitoringEnabled = true
        observers.append(
            NotificationCenter.default.addObserver(
                forName: UIDevice.batteryStateDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.observePowerState(self.normalizedPowerState(UIDevice.current.batteryState))
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

    /// Registers the location wake that Apple documents for system termination.
    ///
    /// This is deliberately NOT a keepalive. An earlier version held a
    /// continuous location session so the in-process unlock notification would
    /// keep arriving; that session is what put a location indicator in the
    /// status bar and drew a battery baseline, and it has been removed.
    ///
    /// Significant-change monitoring is register-and-forget: nothing runs until
    /// the device actually moves between cell towers, at which point iOS
    /// may relaunch the app after system termination. Apple does not document
    /// recovery after an explicit user force-quit, so that remains unproven and
    /// must be measured on TestFlight rather than promised in source comments.
    ///
    /// Restored 2026-08-14 (human decision) after the 2026-08-10 removal, which
    /// took out both `UIBackgroundModes: location` and the Always usage
    /// description. Only the second comes back: significant-change monitoring
    /// never needed the background mode — that is for a continuous session via
    /// `startUpdatingLocation` + `allowsBackgroundLocationUpdates` — so what the
    /// app declares now matches exactly what it does. The original objection
    /// (declaring a background mode the app never used made KC look more
    /// protective than it was) still stands and is still honoured.
    ///
    /// It fires only when the device moves between cell towers, so it does
    /// nothing for someone who stays home. That gap is real and is covered by
    /// HealthKit step delivery instead, which needs no movement between towers.
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
        // Unconditional, and deliberately before the lock check. This records
        // that the watcher was awake and looking, which is true of this wake
        // even when the device is locked and the answer below is "nothing".
        // Reporting coverage only when something was observed is what let
        // S3-C2 conclude that a person's normal quiet was fourteen minutes.
        reportCoverageLease()

        let unlocked = UIApplication.shared.isProtectedDataAvailable
        if unlocked {
            recordEvent(reason: "wake-sample")
        }

        // Sampled whether or not the device is unlocked, which is the opposite
        // of how the ping above behaves and is deliberate. Lock state is only
        // one of the readings; battery drain, the pasteboard counter and the
        // step history describe the whole interval since the last wake and are
        // just as readable through a locked screen. Answering "still locked"
        // and collecting nothing would throw away the interval evidence at
        // exactly the moments it is most needed.
        captureSample(trigger: "push-wake") {
            completion(unlocked)
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Deliberately empty of any use of `locations`. Coordinates are never
        // read, stored, or sent — the fix exists only to prove to iOS that this
        // process is doing work. Any change here turns location into collection.
        //
        // Note what is deliberately absent: no `recordEvent`. A significant
        // location change is not evidence the person is active — a phone in a
        // passenger seat or in someone else's bag moves between towers just as
        // well. This wake is a chance to collect and hand over evidence, never
        // evidence in itself.
        //
        // The lease is reported for the same reason `handleWake` reports it: it
        // says the watcher was awake and looking here, which is true of this
        // relaunch whether or not the sample below finds anything.
        reportCoverageLease()
        flushRecord()
        captureSample(trigger: "location-relaunch")
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

    // MARK: - ADR-0042 positive evidence

    var isEvidenceConfigured: Bool {
        defaults.string(forKey: Key.evidenceBindingId) != nil
            && defaults.string(forKey: Key.evidenceCollectorContract) == Self.evidenceContract
            && keychainCredential() != nil
    }

    func recordDirectEvidence(observedAt: Date) {
        enqueueEvidence(
            observedAt: observedAt,
            evidenceClass: "direct_device_use",
            correlationId: nil,
            facts: ["interaction": true],
            queryStart: nil,
            queryEnd: nil,
            querySucceeded: false
        )
    }

    func recordMotionEvidence(
        observedAt: Date,
        stepsPositive: Bool,
        floorsPositive: Bool,
        automotive: Bool,
        queryStart: Date?,
        queryEnd: Date?
    ) {
        guard (stepsPositive || floorsPositive), !automotive else { return }
        enqueueEvidence(
            observedAt: observedAt,
            evidenceClass: "personal_device_motion",
            correlationId: nil,
            facts: [
                "steps_positive": stepsPositive,
                "floors_positive": floorsPositive,
                "pedestrian": true,
                "automotive": false
            ],
            queryStart: queryStart,
            queryEnd: queryEnd,
            querySucceeded: queryStart != nil && queryEnd != nil
        )
    }

    private func enqueueEvidence(
        observedAt: Date,
        evidenceClass: String,
        correlationId: String?,
        facts: [String: Any],
        queryStart: Date?,
        queryEnd: Date?,
        querySucceeded: Bool
    ) {
        guard isEvidenceConfigured else { return }
        evidenceLock.lock()
        let sequence = defaults.object(forKey: Key.evidenceNextSequence) == nil
            ? 0
            : defaults.integer(forKey: Key.evidenceNextSequence)
        defaults.set(sequence + 1, forKey: Key.evidenceNextSequence)
        let entry: [String: Any] = [
            "binding_id": defaults.string(forKey: Key.evidenceBindingId)!,
            "event_id": UUID().uuidString,
            "sequence": sequence,
            "observed_at": Self.iso8601.string(from: observedAt),
            "evidence_class": evidenceClass,
            "qualification_policy_version": Self.qualificationPolicy,
            "correlation_id": correlationId ?? NSNull(),
            "qualification_facts": facts,
            "query_started_at": queryStart.map { Self.iso8601.string(from: $0) } ?? NSNull(),
            "query_ended_at": queryEnd.map { Self.iso8601.string(from: $0) } ?? NSNull(),
            "query_succeeded": querySucceeded
        ]
        var queue = evidenceQueue()
        queue.append(entry)
        if queue.count > Self.maxRecordEntries {
            queue.removeFirst(queue.count - Self.maxRecordEntries)
        }
        saveEvidenceQueue(queue)
        evidenceLock.unlock()
        flushEvidenceQueue()
    }

    private func evidenceQueue() -> [[String: Any]] {
        guard let data = defaults.data(forKey: Key.evidenceQueue),
              let value = try? JSONSerialization.jsonObject(with: data),
              let queue = value as? [[String: Any]] else { return [] }
        return queue
    }

    private func saveEvidenceQueue(_ queue: [[String: Any]]) {
        guard let data = try? JSONSerialization.data(withJSONObject: queue) else { return }
        defaults.set(data, forKey: Key.evidenceQueue)
    }

    private func flushEvidenceQueue() {
        evidenceLock.lock()
        guard !evidenceSending,
              let first = evidenceQueue().first,
              let credential = keychainCredential(),
              let (baseUrl, _) = credentials(),
              let url = URL(string: baseUrl + "/functions/v1/passive-evidence") else {
            evidenceLock.unlock()
            return
        }
        evidenceSending = true
        evidenceLock.unlock()

        var body = first
        body["credential"] = credential
        let sentBindingId = first["binding_id"] as? String
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else {
            finishEvidenceSend(
                sentBindingId: sentBindingId,
                removeFirst: true,
                revoked: false
            )
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        session.dataTask(with: request) { [weak self] _, response, error in
            guard let self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if error != nil || status >= 500 || status == 0 {
                self.finishEvidenceSend(
                    sentBindingId: sentBindingId,
                    removeFirst: false,
                    revoked: false
                )
                return
            }
            self.finishEvidenceSend(
                sentBindingId: sentBindingId,
                removeFirst: true,
                revoked: status == 409
            )
        }.resume()
    }

    private func finishEvidenceSend(
        sentBindingId: String?,
        removeFirst: Bool,
        revoked: Bool
    ) {
        evidenceLock.lock()
        guard defaults.string(forKey: Key.evidenceBindingId) == sentBindingId else {
            evidenceSending = false
            evidenceLock.unlock()
            return
        }
        if removeFirst {
            var queue = evidenceQueue()
            if !queue.isEmpty { queue.removeFirst() }
            saveEvidenceQueue(queue)
        }
        evidenceSending = false
        evidenceLock.unlock()
        if revoked {
            clearEvidenceBinding()
        } else if removeFirst {
            flushEvidenceQueue()
        }
    }

    private func configureEvidenceBinding(bindingId: String?, credential: String?, contract: String?) {
        guard let bindingId,
              contract == Self.evidenceContract else {
            clearEvidenceBinding()
            return
        }
        let previous = defaults.string(forKey: Key.evidenceBindingId)
        if let previous, previous != bindingId { clearEvidenceBinding() }
        defaults.set(bindingId, forKey: Key.evidenceBindingId)
        defaults.set(Self.evidenceContract, forKey: Key.evidenceCollectorContract)
        if let credential, credential.count >= 32 { saveKeychainCredential(credential) }
        if previous != bindingId {
            defaults.set(0, forKey: Key.evidenceNextSequence)
            saveEvidenceQueue([])
            HealthWake.shared.resetHistoryAnchor()
            DeviceSampleCollector.shared.resetHistoryAnchor()
        }
    }

    private func clearEvidenceBinding() {
        evidenceLock.lock()
        evidenceSending = false
        for key in [
            Key.evidenceBindingId, Key.evidenceCollectorContract,
            Key.evidenceQueue, Key.evidenceNextSequence,
            Key.pendingPowerState, Key.pendingPowerSince
        ] { defaults.removeObject(forKey: key) }
        evidenceLock.unlock()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService
        ]
        SecItemDelete(query as CFDictionary)
        HealthWake.shared.resetHistoryAnchor()
        DeviceSampleCollector.shared.resetHistoryAnchor()
    }

    private func saveKeychainCredential(_ credential: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(credential.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    private func keychainCredential() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func initializePowerBaseline() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        guard let state = normalizedPowerState(UIDevice.current.batteryState) else {
            defaults.removeObject(forKey: Key.stablePowerState)
            return
        }
        defaults.set(state, forKey: Key.stablePowerState)
        defaults.removeObject(forKey: Key.pendingPowerState)
        defaults.removeObject(forKey: Key.pendingPowerSince)
    }

    private func observePowerState(_ rawState: String?) {
        let state: String?
        switch rawState {
        case "charging", "full": state = "charging"
        case "unplugged", "not_charging": state = "not_charging"
        default: state = nil
        }
        guard let state else { return }
        guard let stable = defaults.string(forKey: Key.stablePowerState) else {
            defaults.set(state, forKey: Key.stablePowerState)
            return
        }
        if stable == state {
            defaults.removeObject(forKey: Key.pendingPowerState)
            defaults.removeObject(forKey: Key.pendingPowerSince)
            return
        }
        let since = Date()
        defaults.set(state, forKey: Key.pendingPowerState)
        defaults.set(since.timeIntervalSince1970, forKey: Key.pendingPowerSince)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.powerStableSeconds) { [weak self] in
            self?.confirmPowerTransition(expected: state, prior: stable, since: since)
        }
    }

    private func confirmPowerTransition(expected: String, prior: String, since: Date) {
        guard defaults.string(forKey: Key.pendingPowerState) == expected,
              Date().timeIntervalSince(since) >= Self.powerStableSeconds,
              normalizedPowerState(UIDevice.current.batteryState) == expected else { return }
        defaults.set(expected, forKey: Key.stablePowerState)
        defaults.removeObject(forKey: Key.pendingPowerState)
        defaults.removeObject(forKey: Key.pendingPowerSince)
        let lastGroupAt = defaults.double(forKey: Key.powerCorrelationStarted)
        var correlationId = defaults.string(forKey: Key.powerCorrelationId)
        if correlationId == nil || since.timeIntervalSince1970 - lastGroupAt >= Self.powerCorrelationSeconds {
            correlationId = "power-" + UUID().uuidString
            defaults.set(correlationId, forKey: Key.powerCorrelationId)
            defaults.set(since.timeIntervalSince1970, forKey: Key.powerCorrelationStarted)
        }
        enqueueEvidence(
            observedAt: since,
            evidenceClass: "power_transition",
            correlationId: correlationId,
            facts: [
                "prior_power_state": prior,
                "new_power_state": expected,
                "stable_for_ms": Int(Self.powerStableSeconds * 1000)
            ],
            queryStart: nil,
            queryEnd: nil,
            querySucceeded: false
        )
    }

    private func normalizedPowerState(_ state: UIDevice.BatteryState) -> String? {
        switch state {
        case .charging, .full: return "charging"
        case .unplugged: return "not_charging"
        default: return nil
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

    // MARK: - Multi-signal sampling

    /// Takes a full reading of everything that hints at the device having been
    /// used, and posts it to the shadow endpoint.
    ///
    /// Kept entirely apart from the ping path above. A ping is safety evidence
    /// and is queued, retried and reconciled; a sample is analysis material that
    /// cannot refresh a heartbeat or touch an alert, so a failed upload is
    /// simply dropped. Retrying it would add a second queue to reason about in
    /// exchange for data we will have thousands of.
    /// `completion` runs once the upload has actually finished, because the
    /// caller is usually a background wake that must not tell iOS it is done
    /// while a request is still in flight — the process would be suspended and
    /// the sample lost.
    func captureSample(trigger: String, completion: (() -> Void)? = nil) {
        guard let (baseUrl, token) = credentials(),
              let url = URL(string: baseUrl + "/functions/v1/device-sample") else {
            completion?()
            return
        }

        DeviceSampleCollector.shared.collect(trigger: trigger) { [weak self] sample in
            guard let self else {
                completion?()
                return
            }
            self.observePowerState(sample.batteryState)
            if sample.hasPositivePedestrianMotion {
                self.recordMotionEvidence(
                    observedAt: sample.observedAt,
                    stepsPositive: (sample.stepsSinceLastSample ?? 0) > 0,
                    floorsPositive: (sample.floorsSinceLastSample ?? 0) > 0,
                    automotive: sample.dominantActivity == "automotive",
                    queryStart: sample.motionIntervalStart,
                    queryEnd: sample.observedAt
                )
            }
            var payload = sample.asPayload(
                clientId: self.defaults.string(forKey: Key.clientId),
                appVersion: self.defaults.string(forKey: Key.appVersion),
                contract: "ios-passive-v1"
            )
            payload["token"] = token
            guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
                completion?()
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
            self.session.dataTask(with: request) { _, _, _ in
                completion?()
            }.resume()
        }
    }

    // MARK: - Coverage lease

    /// Tells the server the watcher was awake at this moment (ADR-0039).
    ///
    /// Fire-and-forget on purpose: a wake has a few seconds of budget and the
    /// activity sample is the thing that must not be cut short. A dropped lease
    /// costs one interval, and the interval builder already treats a wider gap
    /// as `unknown` rather than inventing coverage across it.
    func reportCoverageLease() {
        guard let (baseUrl, token) = credentials(),
              let url = URL(string: baseUrl + "/functions/v1/shadow-coverage-lease"),
              let clientId = defaults.string(forKey: Key.clientId),
              let appVersion = defaults.string(forKey: Key.appVersion) else { return }

        let capability = AlertShadowCoverage.Capability(
            pushWakeAvailable: defaults.string(forKey: Key.token) != nil,
            healthWakeAvailable: HealthWake.shared.isObserving,
            clientId: clientId,
            appVersion: appVersion
        )
        // An install with no working wake source must not lease coverage it
        // cannot deliver; saying nothing leaves the account `unknown`, which is
        // the honest reading.
        guard capability.isOperational else { return }

        let body = AlertShadowCoverage.body(
            token: token,
            capability: capability,
            capabilitySha256: AlertShadowCoverage.capabilitySha256(capability),
            observedAt: Self.iso8601.string(from: Date()),
            eventId: UUID()
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        session.dataTask(with: request).resume()
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
