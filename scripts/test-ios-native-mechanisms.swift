import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// swiftc ios-passive-ping/ios/Sources/KcPassivePingPlugin/{MotionEvidenceWindow,NotificationActionQueue}.swift scripts/test-ios-native-mechanisms.swift -o /tmp/kc-ios-mechanisms && /tmp/kc-ios-mechanisms

@main
struct NativeMechanismRegression {
    static func main() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(7200)
        let step = start.addingTimeInterval(300)
        let search = MotionEvidenceWindow.Search(start: start, end: end)
        while let interval = search.nextQuery() {
            let positive = interval.start <= step && step < interval.end
            search.accept(steps: positive ? 1 : 0, floors: 0)
        }
        guard case let .positive(interval, _, _) = search.result else { fatalError("old steps must survive") }
        precondition(interval.start <= step && step <= interval.end)
        precondition(interval.end.timeIntervalSince(interval.start) <= 60)
        precondition(interval.start < end.addingTimeInterval(-300), "old steps must never look fresh")
        precondition(search.queryCount <= 16)
        let failed = MotionEvidenceWindow.Search(start: start, end: end)
        _ = failed.nextQuery(); failed.accept(steps: nil, floors: nil)
        precondition(failed.result == .failed)
        let empty = MotionEvidenceWindow.Search(start: start, end: end)
        _ = empty.nextQuery(); empty.accept(steps: 0, floors: 0)
        precondition(empty.result == .empty)
        let suite = "kc-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID().uuidString, alert = UUID().uuidString, user = UUID().uuidString, binding = UUID().uuidString
        // Real APNs/FCM envelope: `kind` routes transport; `notifKind` is the
        // semantic notification kind that authorizes the explicit safe action.
        let payload: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Keep Contact", "body": "Please check in"], "category": "KC_CARE_CHECKIN"],
            "notificationId": id, "alertId": alert, "recipientUserId": user,
            "kind": "alert", "notifKind": "self", "contractVersion": "2", "pushBindingId": binding
        ]
        precondition(NotificationActionQueue.metadata(payload)?["kind"] as? String == "self", "remote semantic kind must survive transport envelope")
        precondition(NotificationActionQueue.metadata(payload)?["contractVersion"] as? Int == 2, "remote string version must normalize")
        var localPayload = payload
        localPayload.removeValue(forKey: "notifKind")
        localPayload["kind"] = "concern"
        localPayload["contractVersion"] = 2
        precondition(NotificationActionQueue.metadata(localPayload)?["kind"] as? String == "concern")
        precondition(NotificationActionQueue.metadata(localPayload)?["contractVersion"] as? Int == 2, "local integer version must normalize")
        var requests: [URLRequest] = []
        var replies: [(Bool) -> Void] = []
        let transport: (URLRequest, @escaping (Bool) -> Void) -> Void = { request, completion in
            requests.append(request); replies.append(completion)
        }
        var secureTokens: [String: String] = [:]
        var secureTokensReadable = true
        let saveToken: (String, String) -> Bool = { binding, token in secureTokens[binding] = token; return true }
        let readToken: (String) -> String? = { binding in secureTokensReadable ? secureTokens[binding] : nil }
        let deleteToken: (String) -> Void = { binding in secureTokens.removeValue(forKey: binding) }
        let queue = NotificationActionQueue(defaults: defaults, sendRevocation: transport,
            saveLegacyToken: saveToken, readLegacyToken: readToken, deleteLegacyToken: deleteToken)
        let generation = queue.configure(recipientUserId: user, pushBindingId: binding,
            revokeSecret: String(repeating: "a", count: 64), supabaseUrl: "https://project.invalid", anonKey: "public-key", legacyToken: "legacy-fcm-token")!
        precondition(queue.append(userInfo: payload, action: "acknowledge_safe"))
        precondition(!queue.append(userInfo: payload, action: "acknowledge_safe"))
        var remoteConcern = payload
        let concernId = UUID().uuidString.lowercased()
        remoteConcern["notificationId"] = concernId
        remoteConcern["notifKind"] = "concern"
        precondition(queue.append(userInfo: remoteConcern, action: "acknowledge_safe"), "remote concern must also be acknowledged")
        queue.complete(eventId: concernId + ":acknowledge_safe", generation: generation)
        let relaunched = NotificationActionQueue(defaults: defaults, sendRevocation: transport,
            saveLegacyToken: saveToken, readLegacyToken: readToken, deleteLegacyToken: deleteToken)
        precondition(relaunched.pending().count == 1, "cold launch must retain action")
        precondition(relaunched.pending().count == 1, "reading must not consume")
        relaunched.complete(eventId: id.lowercased() + ":acknowledge_safe", generation: "stale")
        precondition(relaunched.pending().count == 1, "old generation cannot consume a new action")
        relaunched.complete(eventId: id.lowercased() + ":acknowledge_safe", generation: generation)
        precondition(relaunched.pending().isEmpty)
        precondition(!relaunched.append(userInfo: payload, action: "acknowledge_safe"), "completed action must not replay")
        precondition(!relaunched.append(userInfo: ["kind": "self"], action: "acknowledge_safe"))
        precondition(relaunched.append(userInfo: payload, action: "open"))
        let otherUser = UUID().uuidString
        secureTokensReadable = false
        _ = relaunched.configure(recipientUserId: otherUser)
        precondition(requests.isEmpty, "locked Keychain must retain the complete revoke task")
        let persisted = defaults.array(forKey: "kc.notification.pushRevocations.v1") as! [[String: String]]
        precondition(persisted.first?["legacyTokenStored"] == "true")
        precondition(!persisted.flatMap { $0.values }.contains("legacy-fcm-token"), "FCM token must not enter UserDefaults")
        secureTokensReadable = true
        relaunched.retryPendingRevocations()
        precondition(relaunched.pending().isEmpty, "owner switch must clear pending actions")
        precondition(requests.count == 1, "logout must attempt a scoped revocation")
        precondition(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer public-key")
        let body = try! JSONSerialization.jsonObject(with: requests[0].httpBody!) as! [String: String]
        precondition(body["_binding_id"] == binding.lowercased() && body["_legacy_token"] == "legacy-fcm-token" && body.count == 3)
        replies.removeFirst()(false)
        precondition((defaults.array(forKey: "kc.notification.pushRevocations.v1") ?? []).count == 1, "offline revoke must persist")
        relaunched.retryPendingRevocations()
        precondition(requests.count == 2)
        replies.removeFirst()(true)
        precondition(secureTokens[binding.lowercased()] == nil, "successful exact-binding revoke deletes only its protected token")
        precondition((defaults.array(forKey: "kc.notification.pushRevocations.v1") ?? []).isEmpty, "successful revoke clears only its tombstone")
        precondition(!relaunched.append(userInfo: payload, action: "acknowledge_safe"), "wrong owner cannot enqueue")
        _ = relaunched.configure(recipientUserId: user)
        precondition(!relaunched.accepts(recipientUserId: user, generation: generation), "A to B to A must invalidate old callbacks")
        precondition(!relaunched.append(userInfo: payload, action: "acknowledge_safe"), "old binding cannot confirm after re-login")
        precondition(relaunched.append(userInfo: payload, action: "open"))
        precondition(relaunched.pending()[0]["generation"] as? String == relaunched.generation)
        relaunched.clear()
        precondition(!relaunched.append(userInfo: payload, action: "open"), "signed-out callbacks must not enqueue")
        precondition(NotificationActionQueue(defaults: defaults, sendRevocation: transport).pending().isEmpty)
        for duration in [30.0, 120.0, 6 * 3600.0, 7 * 86400.0] {
            let finish = start.addingTimeInterval(duration)
            let old = start.addingTimeInterval(duration / 8)
            let recent = start.addingTimeInterval(duration * 0.9)
            let history = MotionEvidenceWindow.Search(start: start, end: finish)
            while let bin = history.nextQuery() {
                let positives = [old, recent].filter { bin.start <= $0 && $0 < bin.end }.count
                history.accept(steps: 0, floors: positives)
            }
            guard case let .positive(bin, _, floors) = history.result else { fatalError("floors must count") }
            precondition(bin.start <= recent && recent <= bin.end, "search selects latest positive interval")
            precondition(bin.end.timeIntervalSince(bin.start) <= 60 && floors > 0)
            precondition(history.queryCount <= 16)
        }
        let inconsistent = MotionEvidenceWindow.Search(start: start, end: start.addingTimeInterval(30))
        _ = inconsistent.nextQuery(); inconsistent.accept(steps: 1, floors: 0)
        _ = inconsistent.nextQuery(); inconsistent.accept(steps: 0, floors: 0)
        precondition(inconsistent.result == .failed, "inconsistent history must not advance the cursor")
        print("iOS native mechanisms: executable motion and notification regressions passed")
    }
}
