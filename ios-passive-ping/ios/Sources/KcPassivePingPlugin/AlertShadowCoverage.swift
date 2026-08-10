import CryptoKit
import Foundation

/// iOS side of the shadow coverage lease (ADR-0039, ADR-0040 revision one).
///
/// A lease is not evidence that the person did anything. It is the watcher
/// saying "I was awake and looking at this moment", which is the half KC never
/// had on iOS: activity pings only exist when there is activity, so a system
/// that infers coverage from them decides it is watching exactly when the
/// person happens to be busy. That reasoning is what made S3-C2 conclude a
/// tester's normal quiet lasted fourteen minutes, and raise a false alarm.
///
/// So this reports on every wake, whether or not anything was observed, and
/// whether or not the screen was unlocked.
///
/// It deliberately mirrors `AlertShadowCoverageContract.java` field for field.
/// The two collectors are different languages against the same server contract,
/// and the day they disagree about the shape of a capability digest is the day
/// one platform silently stops counting.
enum AlertShadowCoverage {
    static let channel = "ios-app"
    static let collectorContract = "ios-wake-v1"

    /// What this install can actually do, as opposed to what it is entitled to.
    ///
    /// The two wake sources are not interchangeable. Silent push is delivered
    /// only while the app has not been force-quit, and iOS may delay, coalesce
    /// or drop it. HealthKit background delivery is the one that can relaunch a
    /// terminated app. An install with neither cannot observe anything at all,
    /// and must say so rather than lease coverage it will not deliver.
    struct Capability {
        let pushWakeAvailable: Bool
        let healthWakeAvailable: Bool
        let clientId: String
        let appVersion: String

        var isOperational: Bool {
            (pushWakeAvailable || healthWakeAvailable)
                && !clientId.trimmingCharacters(in: .whitespaces).isEmpty
                && !appVersion.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    /// Canonical JSON for the capability digest. Key order is fixed and
    /// alphabetical, matching the Android contract, because the server compares
    /// digests and a reordered key would read as a different collector.
    static func capabilityJson(_ capability: Capability) -> String {
        "{"
            + "\"appVersion\":" + jsonString(capability.appVersion) + ","
            + "\"channel\":\"\(channel)\","
            + "\"collectorContract\":\"\(collectorContract)\","
            + "\"healthWakeAvailable\":\(capability.healthWakeAvailable),"
            + "\"pushWakeAvailable\":\(capability.pushWakeAvailable)"
            + "}"
    }

    static func capabilitySha256(_ capability: Capability) -> String {
        sha256Hex(capabilityJson(capability))
    }

    static func body(
        token: String,
        capability: Capability,
        capabilitySha256: String,
        observedAt: String,
        eventId: UUID
    ) -> String {
        "{"
            + "\"token\":" + jsonString(token) + ","
            + "\"client_id\":" + jsonString(capability.clientId) + ","
            + "\"channel\":\"\(channel)\","
            + "\"collector_contract\":\"\(collectorContract)\","
            + "\"collector_state\":\"operational\","
            + "\"capability_sha256\":" + jsonString(capabilitySha256) + ","
            + "\"observed_at\":" + jsonString(observedAt) + ","
            + "\"event_id\":" + jsonString(eventId.uuidString.lowercased())
            + "}"
    }

    // MARK: - Helpers

    private static func jsonString(_ value: String) -> String {
        var escaped = "\""
        for character in value.unicodeScalars {
            switch character {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\u{08}": escaped += "\\b"
            case "\u{0C}": escaped += "\\f"
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default:
                if character.value < 0x20 {
                    escaped += String(format: "\\u%04x", character.value)
                } else {
                    escaped.unicodeScalars.append(character)
                }
            }
        }
        return escaped + "\""
    }

    private static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
