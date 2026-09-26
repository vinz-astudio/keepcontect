import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Security)
import Security
#endif

/// Persistent, owner-scoped inbox. A read never consumes an action. Completed
/// identities remain in a bounded ledger so duplicate OS callbacks cannot replay.
final class NotificationActionQueue {
    static let shared = NotificationActionQueue()
    private let defaults: UserDefaults
    private let lock = NSRecursiveLock()
    private let key = "kc.notification.actions.v2"
    private let completedKey = "kc.notification.completed.v2"
    private let ownerKey = "kc.notification.owner.v2"
    private let generationKey = "kc.notification.generation.v2"
    private let bindingKey = "kc.notification.pushBinding.v1"
    private let revocationsKey = "kc.notification.pushRevocations.v1"
    private var revoking = false
    private let sendRevocation: (URLRequest, @escaping (Bool) -> Void) -> Void
    private let saveLegacyToken: (String, String) -> Bool
    private let readLegacyToken: (String) -> String?
    private let deleteLegacyToken: (String) -> Void
    init(defaults: UserDefaults = .standard, sendRevocation: ((URLRequest, @escaping (Bool) -> Void) -> Void)? = nil,
         saveLegacyToken: ((String, String) -> Bool)? = nil, readLegacyToken: ((String) -> String?)? = nil,
         deleteLegacyToken: ((String) -> Void)? = nil) {
        self.defaults = defaults
        self.sendRevocation = sendRevocation ?? Self.sendRemoteRevocation
        self.saveLegacyToken = saveLegacyToken ?? Self.keychainSaveLegacyToken
        self.readLegacyToken = readLegacyToken ?? Self.keychainReadLegacyToken
        self.deleteLegacyToken = deleteLegacyToken ?? Self.keychainDeleteLegacyToken
    }

    @discardableResult func configure(recipientUserId: String, pushBindingId: String? = nil,
                                     revokeSecret: String? = nil, supabaseUrl: String? = nil, anonKey: String? = nil, legacyToken: String? = nil) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard UUID(uuidString: recipientUserId) != nil else { return nil }
        let owner = recipientUserId.lowercased()
        let oldBinding = defaults.dictionary(forKey: bindingKey)?["bindingId"] as? String
        if defaults.string(forKey: ownerKey) != owner || (pushBindingId != nil && oldBinding != nil && oldBinding != pushBindingId?.lowercased()) {
            clear()
            defaults.set(owner, forKey: ownerKey)
        }
        if let pushBindingId, UUID(uuidString: pushBindingId) != nil,
           let revokeSecret, revokeSecret.count == 64, revokeSecret.allSatisfy({ $0.isHexDigit }),
           let supabaseUrl, let url = URL(string: supabaseUrl), url.scheme == "https", url.host != nil,
           let anonKey, !anonKey.isEmpty {
            let id = pushBindingId.lowercased()
            var binding = ["bindingId": id, "revokeSecret": revokeSecret,
                           "supabaseUrl": supabaseUrl, "anonKey": anonKey]
            if let legacyToken, !legacyToken.isEmpty {
                guard saveLegacyToken(id, legacyToken) else { return nil }
                binding["legacyTokenStored"] = "true"
            } else if oldBinding == id, defaults.dictionary(forKey: bindingKey)?["legacyTokenStored"] as? String == "true" {
                binding["legacyTokenStored"] = "true"
            }
            // The tombstone stores a Keychain reference, never the FCM token.
            defaults.set(binding, forKey: bindingKey)
        }
        if defaults.string(forKey: generationKey) == nil { defaults.set(UUID().uuidString, forKey: generationKey) }
        return defaults.string(forKey: generationKey)
    }
    var pushBindingId: String? {
        lock.lock(); defer { lock.unlock() }
        return defaults.dictionary(forKey: bindingKey)?["bindingId"] as? String
    }
    func matchesPushBinding(_ candidate: String?) -> Bool {
        guard let candidate, UUID(uuidString: candidate) != nil, let current = pushBindingId else { return false }
        return current == candidate.lowercased()
    }
    var recipientUserId: String? {
        lock.lock(); defer { lock.unlock() }
        return defaults.string(forKey: ownerKey)
    }
    var generation: String? {
        lock.lock(); defer { lock.unlock() }
        return defaults.string(forKey: generationKey)
    }
    func accepts(recipientUserId: String?, generation: String? = nil) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let recipientUserId, let owner = defaults.string(forKey: ownerKey), owner == recipientUserId.lowercased() else { return false }
        return generation == nil || generation == defaults.string(forKey: generationKey)
    }
    static func metadata(_ info: [AnyHashable: Any]) -> [String: Any]? {
        func string(_ key: String, _ fallback: String) -> String { (info[key] as? String) ?? (info[fallback] as? String) ?? "" }
        let id = string("notificationId", "id")
        let recipient = string("recipientUserId", "recipient_id")
        let alert = string("alertId", "alert_id")
        // Remote pushes use kind=alert/tickle for transport routing and put
        // the actual self/concern/etc. kind in notifKind. Local posts use kind.
        let kind = string("notifKind", "kind")
        let version = String(describing: info["contractVersion"] ?? info["contract_version"] ?? "")
        guard version == "2", UUID(uuidString: id) != nil, UUID(uuidString: recipient) != nil, !kind.isEmpty else { return nil }
        var metadata: [String: Any] = ["notificationId": id.lowercased(), "alertId": alert.lowercased(), "recipientUserId": recipient.lowercased(), "kind": kind, "contractVersion": 2]
        let binding = string("pushBindingId", "push_binding_id")
        if UUID(uuidString: binding) != nil { metadata["pushBindingId"] = binding.lowercased() }
        if let generation = info["generation"] as? String { metadata["generation"] = generation }
        return metadata
    }
    @discardableResult func append(userInfo: [AnyHashable: Any], action: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard var item = Self.metadata(userInfo), accepts(recipientUserId: item["recipientUserId"] as? String), ["open", "acknowledge_safe"].contains(action) else { return false }
        if action == "acknowledge_safe" {
            guard matchesPushBinding(item["pushBindingId"] as? String),
                  accepts(recipientUserId: item["recipientUserId"] as? String, generation: item["generation"] as? String),
                  let alert = item["alertId"] as? String, UUID(uuidString: alert) != nil,
                  let kind = item["kind"] as? String, ["self", "concern"].contains(kind) else { return false }
        }
        let eventId = (item["notificationId"] as! String).lowercased() + ":" + action
        var items = pending()
        guard !items.contains(where: { $0["eventId"] as? String == eventId }), !(defaults.stringArray(forKey: completedKey) ?? []).contains(eventId) else { return false }
        item["generation"] = generation
        item["eventId"] = eventId
        item["action"] = action
        items.append(item)
        // Never silently evict an unhandled action. Completion/logout removes it.
        defaults.set(items, forKey: key)
        return true
    }
    func pending() -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return (defaults.array(forKey: key) as? [[String: Any]] ?? []).filter { accepts(recipientUserId: $0["recipientUserId"] as? String, generation: $0["generation"] as? String) }
    }
    func complete(eventId: String, generation expectedGeneration: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        guard expectedGeneration == nil || expectedGeneration == generation else { return }
        guard pending().contains(where: { $0["eventId"] as? String == eventId }) else { return }
        var completed = defaults.stringArray(forKey: completedKey) ?? []
        completed.append(eventId)
        defaults.set(Array(completed.suffix(200)), forKey: completedKey)
        defaults.set(pending().filter { $0["eventId"] as? String != eventId }, forKey: key)
    }
    func clear() {
        lock.lock(); defer { lock.unlock() }
        if let binding = defaults.dictionary(forKey: bindingKey) as? [String: String] {
            var pending = defaults.array(forKey: revocationsKey) as? [[String: String]] ?? []
            if !pending.contains(where: { $0["bindingId"] == binding["bindingId"] }) {
                pending.append(binding)
                defaults.set(pending, forKey: revocationsKey)
                // The revoke-only capability must reach disk before active
                // account state is erased, including during offline sign-out.
                defaults.synchronize()
            }
        }
        for value in [key, completedKey, ownerKey, bindingKey] { defaults.removeObject(forKey: value) }
        defaults.set(UUID().uuidString, forKey: generationKey)
        retryPendingRevocations()
    }

    /// No user access/refresh token is retained. Each capability can only revoke
    /// its own server binding, so a late A callback cannot unlink B.
    func retryPendingRevocations() {
        lock.lock()
        guard !revoking, let first = (defaults.array(forKey: revocationsKey) as? [[String: String]])?.first,
              let baseUrl = first["supabaseUrl"], let key = first["anonKey"],
              let binding = first["bindingId"], let secret = first["revokeSecret"],
              let url = URL(string: baseUrl + "/rest/v1/rpc/revoke_push_binding") else { lock.unlock(); return }
        var body = ["_binding_id": binding, "_revoke_secret": secret]
        if first["legacyTokenStored"] == "true" {
            // Protected data can be unavailable before the first device unlock.
            // Keep the whole tombstone until its legacy token can be included.
            guard let legacyToken = readLegacyToken(binding), !legacyToken.isEmpty else { lock.unlock(); return }
            body["_legacy_token"] = legacyToken
        }
        revoking = true
        lock.unlock()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        sendRevocation(request) { success in
            self.lock.lock()
            self.revoking = false
            if success {
                self.deleteLegacyToken(binding)
                let pending = self.defaults.array(forKey: self.revocationsKey) as? [[String: String]] ?? []
                self.defaults.set(pending.filter { $0["bindingId"] != binding || $0["revokeSecret"] != secret }, forKey: self.revocationsKey)
            }
            self.lock.unlock()
            if success { self.retryPendingRevocations() }
        }
    }

    private static let legacyTokenService = "com.keepcontact.push-legacy-revocation"
    private static func keychainSaveLegacyToken(_ binding: String, _ token: String) -> Bool {
        #if canImport(Security)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyTokenService, kSecAttrAccount as String: binding]
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        return SecItemAdd(query.merging(attributes) { _, value in value } as CFDictionary, nil) == errSecSuccess
        #else
        return false
        #endif
    }
    private static func keychainReadLegacyToken(_ binding: String) -> String? {
        #if canImport(Security)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyTokenService, kSecAttrAccount as String: binding,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
        #else
        return nil
        #endif
    }
    private static func keychainDeleteLegacyToken(_ binding: String) {
        #if canImport(Security)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyTokenService, kSecAttrAccount as String: binding]
        SecItemDelete(query as CFDictionary)
        #endif
    }

    private static func sendRemoteRevocation(_ request: URLRequest, completion: @escaping (Bool) -> Void) {
        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let result = data.flatMap { try? JSONSerialization.jsonObject(with: $0, options: [.fragmentsAllowed]) } as? Bool
            completion(error == nil && (200..<300).contains(status) && result == true)
        }.resume()
    }
}
