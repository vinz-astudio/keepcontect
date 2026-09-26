import Foundation
import UIKit
import UserNotifications

final class NotificationTap: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationTap()
    static let pendingNotification = Notification.Name("kc.notificationActionPending")
    private static let storageKey = "kc.passive.launchNotifKind"
    private static let safeAckKey = "kc.passive.launchAckSafe"
    private let defaults = UserDefaults.standard

    func register() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let isZh = Locale.current.languageCode == "zh"
        let safeAction = UNNotificationAction(identifier: "ACTION_SAFE", title: isZh ? "一切安好" : "I'm Safe", options: [.foreground])
        let category = UNNotificationCategory(identifier: "KC_CARE_CHECKIN", actions: [safeAction], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }
    func configure(recipientUserId: String, pushBindingId: String?, revokeSecret: String?, supabaseUrl: String?, anonKey: String?, legacyToken: String?) -> String? {
        if !NotificationActionQueue.shared.accepts(recipientUserId: recipientUserId) { clear() }
        return NotificationActionQueue.shared.configure(recipientUserId: recipientUserId, pushBindingId: pushBindingId,
            revokeSecret: revokeSecret, supabaseUrl: supabaseUrl, anonKey: anonKey, legacyToken: legacyToken)
    }
    func clear() {
        NotificationActionQueue.shared.clear()
        defaults.removeObject(forKey: Self.storageKey)
        defaults.removeObject(forKey: Self.safeAckKey)
        NotifyFeed.resetCursor()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UIApplication.shared.unregisterForRemoteNotifications()
    }
    /// Legacy intent is navigation only; it cannot authorize confirmation.
    func consume() -> [String: Any] {
        let kind = defaults.string(forKey: Self.storageKey) ?? ""
        defaults.removeObject(forKey: Self.storageKey)
        defaults.removeObject(forKey: Self.safeAckKey)
        return ["kind": kind, "ackSafe": false]
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier else { return }
        let info = response.notification.request.content.userInfo
        if let metadata = NotificationActionQueue.metadata(info) {
            guard NotificationActionQueue.shared.accepts(recipientUserId: metadata["recipientUserId"] as? String) else { return }
            let canAcknowledge = NotificationActionQueue.shared.matchesPushBinding(metadata["pushBindingId"] as? String)
            let action = response.actionIdentifier == "ACTION_SAFE" && canAcknowledge ? "acknowledge_safe" : "open"
            if NotificationActionQueue.shared.append(userInfo: info, action: action) {
                NotificationCenter.default.post(name: Self.pendingNotification, object: nil)
            }
        } else {
            // Old payloads may open the UI, but never become an acknowledgement.
            defaults.set((info["kind"] as? String) ?? (info["notifKind"] as? String) ?? "", forKey: Self.storageKey)
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let metadata = NotificationActionQueue.metadata(notification.request.content.userInfo)
        let allowed = NotificationActionQueue.shared.accepts(recipientUserId: metadata?["recipientUserId"] as? String)
        completionHandler(allowed ? [.banner, .sound, .list] : [])
    }
}
