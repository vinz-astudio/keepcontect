import Capacitor
import Foundation

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
        CAPPluginMethod(name: "getFcmToken", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "consumeLaunchNotificationKind", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "enableHealthWake", returnType: CAPPluginReturnPromise)
    ]

    override public func load() {
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
        PassiveGuard.shared.configure(
            supabaseUrl: supabaseUrl,
            token: token,
            clientId: call.getString("clientId"),
            appVersion: call.getString("appVersion")
        )
        call.resolve()
    }

    @objc func clear(_ call: CAPPluginCall) {
        PassiveGuard.shared.clear()
        call.resolve()
    }

    @objc func pingApp(_ call: CAPPluginCall) {
        PassiveGuard.shared.recordEvent(reason: "app")
        call.resolve()
    }

    @objc func getGuardStatus(_ call: CAPPluginCall) {
        var status = PassiveGuard.shared.status()
        status["health"] = HealthWake.shared.status()
        call.resolve(status)
    }

    /// Asks for step-count read access and registers the HealthKit wake
    /// (KC-IOS-HEALTHWAKE-SPIKE-001). Resolves either way: a refused
    /// authorization is a normal outcome, not an error, and KC keeps working
    /// with the evidence sources it already has.
    @objc func enableHealthWake(_ call: CAPPluginCall) {
        HealthWake.shared.enable { granted in
            call.resolve(["granted": granted])
        }
    }

    @objc func requestNotificationPermission(_ call: CAPPluginCall) {
        PushRegistrar.requestPermission { granted in
            call.resolve(["granted": granted])
        }
    }

    /// Which notification kind opened the app, read once and cleared. Empty
    /// string means the app was opened some other way.
    @objc func consumeLaunchNotificationKind(_ call: CAPPluginCall) {
        call.resolve(["kind": NotificationTap.shared.consume()])
    }

    @objc func getFcmToken(_ call: CAPPluginCall) {
        PushRegistrar.fetchToken { token in
            // The web layer only registers a non-empty token, so an empty
            // string is a clean "not available yet" rather than an error.
            call.resolve(["token": token ?? ""])
        }
    }
}
