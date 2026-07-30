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
        CAPPluginMethod(name: "getGuardStatus", returnType: CAPPluginReturnPromise)
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
        PassiveGuard.shared.configure(supabaseUrl: supabaseUrl, token: token)
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
        call.resolve(PassiveGuard.shared.status())
    }
}
