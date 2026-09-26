import Capacitor
import Foundation
import UIKit
import CoreMotion

/// iOS half of the `PassivePing` bridge. The JS name matches the Android
/// plugin so `src/features/passive/native.ts` talks to both through one
/// interface; only the methods iOS can actually honour are registered here.
@objc(KcPassivePingPlugin)
public class KcPassivePingPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "KcPassivePingPlugin"
    public let jsName = "PassivePing"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "configure", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clear", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pingApp", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getGuardStatus", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestNotificationPermission", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getNotificationPermissionStatus", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getCollectionPermissionStatus", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "openNotificationSettings", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "openAppSettings", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "configurePushNotifications", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getPendingNotificationActions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "completeNotificationAction", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clearPushNotifications", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getFcmToken", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "consumeLaunchNotificationKind", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "enableHealthWake", returnType: CAPPluginReturnPromise)
    ]

    private var notificationObserver: NSObjectProtocol?

    deinit {
        if let notificationObserver { NotificationCenter.default.removeObserver(notificationObserver) }
    }

    override public func load() {
        NotificationTap.shared.register()
        NotificationActionQueue.shared.retryPendingRevocations()
        notificationObserver = NotificationCenter.default.addObserver(
            forName: NotificationTap.pendingNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.notifyListeners("notificationActionPending", data: [:]) }
        // Runs on every process start, including background relaunches, so a
        // guard configured in an earlier session re-arms without user action.
        PassiveGuard.shared.resumeIfConfigured()
    }

    @objc func configure(_ call: CAPPluginCall) {
        guard let supabaseUrl = call.getString("supabaseUrl"), !supabaseUrl.isEmpty else {
            call.reject("supabaseUrl is required")
            return
        }
        guard let token = call.getString("token"), !token.isEmpty else {
            call.reject("token is required")
            return
        }
        DispatchQueue.main.async {
            PassiveGuard.shared.configure(
                supabaseUrl: supabaseUrl,
                token: token,
                clientId: call.getString("clientId"),
                appVersion: call.getString("appVersion"),
                evidenceBindingId: call.getString("bindingId"),
                evidenceCredential: call.getString("evidenceCredential"),
                evidenceCollectorContract: call.getString("evidenceCollectorContract")
            )
            call.resolve(["evidenceConfigured": PassiveGuard.shared.isEvidenceConfigured])
        }
    }

    @objc func clear(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            PassiveGuard.shared.clear()
            call.resolve()
        }
    }

    @objc func pingApp(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            PassiveGuard.shared.recordEvent(reason: "app")
            PassiveGuard.shared.recordDirectEvidence(observedAt: Date())
            call.resolve()
        }
    }

    @objc func getGuardStatus(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            var status = PassiveGuard.shared.status()
            status["health"] = HealthWake.shared.status()
            call.resolve(status)
        }
    }

    /// Asks for step-count read access and registers the HealthKit wake
    /// (KC-IOS-HEALTHWAKE-SPIKE-001). Resolves either way: a refused
    /// authorization is a normal outcome, not an error, and KC keeps working
    /// with the evidence sources it already has.
    @objc func enableHealthWake(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            HealthWake.shared.enable { granted in
                call.resolve(["granted": granted])
            }
        }
    }

    @objc func requestNotificationPermission(_ call: CAPPluginCall) {
        PushRegistrar.requestPermission { granted in
            call.resolve(["granted": granted])
        }
    }

    @objc func getNotificationPermissionStatus(_ call: CAPPluginCall) {
        PushRegistrar.status { granted, canRequest in
            call.resolve(["granted": granted, "canRequest": canRequest])
        }
    }

    @objc func openNotificationSettings(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let urlString: String
            if #available(iOS 16.0, *) {
                urlString = UIApplication.openNotificationSettingsURLString
            } else {
                urlString = UIApplication.openSettingsURLString
            }
            guard let url = URL(string: urlString) else {
                call.reject("notification settings URL unavailable")
                return
            }
            UIApplication.shared.open(url) { _ in call.resolve() }
        }
    }

    /// Opens the app's general settings page for background/privacy controls
    /// that do not have a dedicated permission sheet on iOS.
    @objc func openAppSettings(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                call.reject("app settings URL unavailable")
                return
            }
            UIApplication.shared.open(url) { _ in call.resolve() }
        }
    }

    /// Read-only OS truth. Never request access or infer HealthKit read consent.
    @objc func getCollectionPermissionStatus(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            func motionState(_ status: CMAuthorizationStatus) -> String {
                switch status {
                case .authorized: return "granted"
                case .denied: return "denied"
                case .restricted: return "restricted"
                case .notDetermined: return "prompt"
                @unknown default: return "unavailable"
                }
            }
            var states: [String] = []
            if CMPedometer.isStepCountingAvailable() {
                states.append(motionState(CMPedometer.authorizationStatus()))
            }
            if CMMotionActivityManager.isActivityAvailable() {
                states.append(motionState(CMMotionActivityManager.authorizationStatus()))
            }
            let motion = states.contains("restricted") ? "restricted"
                : states.contains("denied") ? "denied"
                : states.contains("prompt") ? "prompt"
                : !states.isEmpty && states.allSatisfy({ $0 == "granted" }) ? "granted"
                : "unavailable"
            let background: String
            switch UIApplication.shared.backgroundRefreshStatus {
            case .available: background = "granted"
            case .denied: background = "denied"
            case .restricted: background = "restricted"
            @unknown default: background = "unavailable"
            }
            call.resolve(["motion": motion, "backgroundRefresh": background])
        }
    }

    /// Which notification kind opened the app, read once and cleared. Empty
    /// string means the app was opened some other way.
    @objc func consumeLaunchNotificationKind(_ call: CAPPluginCall) {
        call.resolve(NotificationTap.shared.consume())
    }

    @objc func configurePushNotifications(_ call: CAPPluginCall) {
        guard let owner = call.getString("recipientUserId"), UUID(uuidString: owner) != nil else {
            call.reject("recipientUserId is required"); return
        }
        DispatchQueue.main.async {
            guard let generation = NotificationTap.shared.configure(recipientUserId: owner,
                pushBindingId: call.getString("pushBindingId"), revokeSecret: call.getString("revokeSecret"),
                supabaseUrl: call.getString("supabaseUrl"), anonKey: call.getString("anonKey"), legacyToken: call.getString("legacyToken")) else {
                call.reject("Push notification configuration could not be stored"); return
            }
            PushRegistrar.activate()
            call.resolve(["generation": generation])
        }
    }

    @objc func getPendingNotificationActions(_ call: CAPPluginCall) {
        call.resolve(["actions": NotificationActionQueue.shared.pending()])
    }

    @objc func completeNotificationAction(_ call: CAPPluginCall) {
        guard let eventId = call.getString("eventId"), let generation = call.getString("generation") else {
            call.reject("eventId and generation are required"); return
        }
        NotificationActionQueue.shared.complete(eventId: eventId, generation: generation)
        call.resolve()
    }

    @objc func clearPushNotifications(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            NotificationTap.shared.clear()
            PushRegistrar.deactivate()
            call.resolve()
        }
    }

    @objc func getFcmToken(_ call: CAPPluginCall) {
        PushRegistrar.fetchToken { token in
            // The web layer only registers a non-empty token, so an empty
            // string is a clean "not available yet" rather than an error.
            call.resolve(["token": token ?? ""])
        }
    }
}
