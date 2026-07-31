import FirebaseCore
import FirebaseMessaging
import Foundation
import UIKit

/// APNs/FCM registration for the iOS app.
///
/// iOS reaches KC's alert ladder through the same Firebase project and the same
/// `push_tokens` table as Android, so `push-dispatch` needs no iOS-specific
/// branch: an iOS device simply appears as one more FCM token.
///
/// This matters more than it looks. The `self` alert stage is the user's only
/// chance to clear an alert before it reaches their group — if the notification
/// cannot land on the device, every unusual silence escalates to other people
/// with no way for the user to say "I'm fine".
///
/// Firebase is configured in code rather than from a bundled
/// GoogleService-Info.plist: adding a resource file would mean editing the
/// Capacitor-generated pbxproj, and these values are not secrets (they ship
/// inside every copy of the app anyway).
enum PushRegistrar {
    private static let googleAppID = "1:336945812261:ios:313ac102272a5c5c6180cc"
    private static let gcmSenderID = "336945812261"
    private static let apiKey = "AIzaSyB8nuZ0c-JMGPh1r4pZHJgAREdk9Z7OIOE"
    private static let projectID = "keep-contect"
    private static let bundleID = "com.keepcontact.app"

    private static var configured = false

    static func configureIfNeeded() {
        guard !configured, FirebaseApp.app() == nil else {
            configured = true
            return
        }
        let options = FirebaseOptions(googleAppID: googleAppID, gcmSenderID: gcmSenderID)
        options.apiKey = apiKey
        options.projectID = projectID
        options.bundleID = bundleID
        FirebaseApp.configure(options: options)
        configured = true
    }

    /// Asks for notification permission, then registers with APNs. Firebase's
    /// app-delegate proxy forwards the APNs token to Messaging, so no
    /// AppDelegate changes are needed in the Capacitor template.
    static func requestPermission(completion: @escaping (Bool) -> Void) {
        configureIfNeeded()
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            completion(granted)
        }
    }

    static func fetchToken(completion: @escaping (String?) -> Void) {
        configureIfNeeded()
        Messaging.messaging().token { token, _ in
            completion(token)
        }
    }
}
