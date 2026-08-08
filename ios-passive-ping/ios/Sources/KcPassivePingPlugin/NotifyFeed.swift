import CryptoKit
import Foundation
import UserNotifications

/// iOS half of the native notification channel.
///
/// The Capacitor WebView has no Web Push, so an iOS install had no way at all to
/// show an alert: the silent push was consumed purely as unlock evidence and
/// nothing rendered a notification. An unusual-silence alert could therefore
/// raise, escalate to the group, and reach the community without its subject
/// ever being told — the one thing the `self` stage exists to prevent.
///
/// This mirrors Android's `NotifyWorker`: the push carries no content, the
/// device pulls the notifications itself from the token+HMAC authenticated
/// `notify-feed`, and the text is rendered locally. Notification content
/// therefore never transits Apple or Google.
enum NotifyFeed {
    private static let cursorKey = "kc.passive.notifySince"
    /// Ids already drawn on this device.
    ///
    /// The cursor alone was the only thing standing between the user and an
    /// endlessly repeating notification, and it held a value the server round-
    /// tripped through a millisecond-precision Date — so a row could come back
    /// as newer than itself and be posted again on every single wake. That is
    /// fixed in notify-feed, but the cost of the cursor being wrong again is
    /// paid by someone being woken repeatedly by an alert they already saw, so
    /// the device now also refuses to draw the same row twice on its own.
    private static let postedKey = "kc.passive.notifyPosted"
    /// The feed returns at most 20 rows and the cursor only moves forward, so
    /// this needs to cover a burst, not a history. Oldest ids fall off the end.
    private static let postedLimit = 100
    /// Mirrors src/features/push/alertPushKinds.ts: push-dispatch sends these as
    /// system-displayed alert pushes, so the app must not draw them a second time.
    private static let selfAddressedKinds: Set<String> = ["concern", "self"]
    private static let defaults = UserDefaults.standard

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration)
    }()

    /// Starts the cursor at "now" so a first run can never flood the user with
    /// a week of history as if it were fresh. Matches `NotifyWorker.schedule`.
    static func primeCursorIfNeeded() {
        if defaults.string(forKey: cursorKey) == nil {
            defaults.set(iso8601.string(from: Date()), forKey: cursorKey)
        }
    }

    /// Dropped on sign-out so the next account starts from its own "now".
    /// The posted-id ledger goes with it: it describes what the previous
    /// account was shown, and holding it back would suppress the next
    /// account's notifications on an id collision.
    static func resetCursor() {
        defaults.removeObject(forKey: cursorKey)
        defaults.removeObject(forKey: postedKey)
    }

    /// Ids drawn on this device, oldest first.
    private static func postedIds() -> [String] {
        defaults.stringArray(forKey: postedKey) ?? []
    }

    private static func rememberPosted(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        var ledger = postedIds()
        ledger.append(contentsOf: ids)
        if ledger.count > postedLimit {
            ledger.removeFirst(ledger.count - postedLimit)
        }
        defaults.set(ledger, forKey: postedKey)
    }

    /// Pulls undelivered notifications and posts them locally.
    /// `completion(true)` means at least one notification was posted, which the
    /// AppDelegate reports to iOS as `.newData` to protect the wake budget.
    static func fetchAndPost(completion: @escaping (Bool) -> Void) {
        guard let (baseUrl, token) = PassiveGuard.shared.credentials() else {
            completion(false)
            return
        }
        primeCursorIfNeeded()
        let since = defaults.string(forKey: cursorKey) ?? iso8601.string(from: Date())

        let timestamp = String(Int(Date().timeIntervalSince1970))
        guard let signature = hmacSHA256(message: timestamp, key: token),
              let url = feedURL(baseUrl: baseUrl, token: token, t: timestamp, sig: signature, since: since)
        else {
            completion(false)
            return
        }

        session.dataTask(with: url) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard error == nil, status == 200, let data else {
                completion(false)
                return
            }
            guard
                let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let list = payload["notifications"] as? [[String: Any]],
                !list.isEmpty
            else {
                completion(false)
                return
            }

            var latest = since
            var posted = false
            let alreadyPosted = Set(postedIds())
            var newlyPosted: [String] = []
            for item in list {
                let kind = item["kind"] as? String ?? ""
                if let createdAt = item["created_at"] as? String, createdAt > latest {
                    latest = createdAt
                }
                // These arrive as alert pushes that iOS has already drawn on the
                // lock screen. Posting them again from here would show the user
                // the same concern twice. The cursor still moves past them.
                if selfAddressedKinds.contains(kind) { continue }
                let id = item["id"] as? String ?? UUID().uuidString
                // Seen before: the cursor did not do its job. Move on quietly
                // rather than waking the user with a notification they answered
                // or dismissed already.
                if alreadyPosted.contains(id) { continue }
                let params = item["params"] as? [String: Any]
                let fallback = item["body"] as? String ?? ""
                post(body: render(kind: kind, params: params, fallback: fallback), id: id)
                newlyPosted.append(id)
                posted = true
            }
            rememberPosted(newlyPosted)
            defaults.set(latest, forKey: cursorKey)
            completion(posted)
        }.resume()
    }

    // MARK: - Request

    private static func feedURL(
        baseUrl: String, token: String, t: String, sig: String, since: String
    ) -> URL? {
        guard var components = URLComponents(string: baseUrl + "/functions/v1/notify-feed") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "t", value: t),
            URLQueryItem(name: "sig", value: sig),
            URLQueryItem(name: "since", value: since)
        ]
        return components.url
    }

    /// `sig = HMAC_SHA256(message=t, key=token)`, lower-case hex — the scheme
    /// notify-feed and /ping already verify for the Android client.
    private static func hmacSHA256(message: String, key: String) -> String? {
        guard let messageData = message.data(using: .utf8),
              let keyData = key.data(using: .utf8) else { return nil }
        let mac = HMAC<SHA256>.authenticationCode(
            for: messageData, using: SymmetricKey(data: keyData))
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Presentation

    private static func post(body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = "Keep Contact"
        content.body = body
        content.sound = .default
        // No trigger: deliver immediately, including while the screen is locked.
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Mirrors `public/sw.js` and Android's `NotifyWorker.renderBody` so all
    /// three channels speak identical copy.
    private static func render(kind: String, params: [String: Any]?, fallback: String) -> String {
        let dict = isZh ? zh : en
        var effectiveKind = kind
        guard var template = dict[effectiveKind] else {
            return fallback.isEmpty
                ? (isZh ? "有新的守护提醒，请打开 App 查看。" : "New care alert — open the app.")
                : fallback
        }

        let targetIsRecipient = String(describing: params?["target_is_recipient"] ?? "") == "true"
        if targetIsRecipient, effectiveKind == "on_it" || effectiveKind == "resolved" {
            effectiveKind += "_you"
            template = dict[effectiveKind] ?? template
        }

        let someone = isZh ? "某位成员" : "A member"
        func value(_ key: String) -> String {
            let raw = params?[key] as? String ?? ""
            return raw.isEmpty ? someone : raw
        }
        return template
            .replacingOccurrences(of: "{name}", with: value("name"))
            .replacingOccurrences(of: "{actor}", with: value("actor"))
            .replacingOccurrences(of: "{target}", with: value("target"))
    }

    private static var isZh: Bool {
        (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("zh")
    }

    private static let zh: [String: String] = [
        "self": "检测到异常沉默，请打开 App 完成解锁报平安。",
        "group": "{name} 出现异常沉默，请尽快联系确认其安全。",
        "community": "社区警示：{name} 长时间失联且其小组无人响应，请协助推动联系。",
        "terminal": "紧急：{name} 持续无响应。已为你解锁其地址与紧急联系人，请上门探视或协助报警。",
        "on_it": "{actor} 正在跟进 {target} 的情况。",
        "on_it_you": "{actor} 正在跟进你的情况。",
        "resolved": "{target} 已确认安全，告警解除。",
        "resolved_you": "你已确认安全，告警解除。",
        "task_invite": "{name} 为你设置了报平安任务，请打开 App 确认是否接受。",
        "task_due": "到点报平安啦，点开 App 完成确认。",
        "task_missed": "{name} 未完成定时报平安，请关注。",
        "task_accepted": "{name} 接受了你设置的报平安任务。",
        "task_declined": "{name} 拒绝了你设置的报平安任务。",
        "task_updated": "你的报平安任务已被修改，请留意新的时间安排。",
        "test": "这是一条测试通知，用来确认推送是否出声、醒目。",
        "concern": "{name} 在关心你，请打开 App 完成解锁报平安。"
    ]

    private static let en: [String: String] = [
        "self": "Unusual silence detected. Open the app and unlock to check in.",
        "group": "{name} has gone unusually silent. Please reach out and make sure they are safe.",
        "community": "Community alert: {name} is unreachable and their group has not responded.",
        "terminal": "URGENT: {name} is unresponsive. Their address and emergency contact are unlocked for you.",
        "on_it": "{actor} is following up on {target}.",
        "on_it_you": "{actor} is following up on you.",
        "resolved": "{target} is confirmed safe. Alert resolved.",
        "resolved_you": "You are confirmed safe. Alert resolved.",
        "task_invite": "{name} set up a check-in task for you. Open the app to accept or decline.",
        "task_due": "Time to check in — open the app to confirm.",
        "task_missed": "{name} missed a scheduled check-in. Please look in on them.",
        "task_accepted": "{name} accepted your check-in task.",
        "task_declined": "{name} declined your check-in task.",
        "task_updated": "Your check-in task was changed. Please note the new schedule.",
        "test": "This is a test notification — checking whether push is audible and prominent.",
        "concern": "{name} is checking on you — please open the app and check in."
    ]

    /// Byte-identical to the cursor format the feed returns and Android sends.
    private static let iso8601: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
