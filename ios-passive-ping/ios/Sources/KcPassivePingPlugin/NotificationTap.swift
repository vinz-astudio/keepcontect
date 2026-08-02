import Foundation
import UserNotifications

/// Remembers which notification the user tapped to open the app.
///
/// The web layer already has this contract: the service worker opens the PWA
/// with `?from=notif&notifKind=…`, and LivenessProvider raises the unlock prompt
/// on the first frame instead of waiting for the network to confirm an open
/// alert. A tapped system notification on iOS just launches the app with no such
/// signal, so the user landed on the home screen and watched it sync and flicker
/// before the prompt finally appeared — on the one screen that is supposed to be
/// immediate, because the alert is escalating to other people while they wait.
///
/// The tapped kind is stashed here and read once by the web layer at boot.
final class NotificationTap: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationTap()

    private static let storageKey = "kc.passive.launchNotifKind"
    private let defaults = UserDefaults.standard

    /// Must run in `didFinishLaunchingWithOptions`: a cold-start tap is
    /// delivered as soon as a delegate exists, and setting one later from a
    /// plugin's `load()` can miss the very launch that carried it.
    func register() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Returns the tapped kind and clears it, so a later resume cannot replay a
    /// prompt the user already dealt with.
    func consume() -> String {
        let value = defaults.string(forKey: Self.storageKey) ?? ""
        if !value.isEmpty { defaults.removeObject(forKey: Self.storageKey) }
        return value
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let kind = (info["notifKind"] as? String) ?? ""
        if !kind.isEmpty {
            defaults.set(kind, forKey: Self.storageKey)
        }
        completionHandler()
    }
}
