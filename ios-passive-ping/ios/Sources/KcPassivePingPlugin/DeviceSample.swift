import AVFoundation
import CoreMotion
import Foundation
import UIKit

/// Reads everything KC can legitimately learn about whether a human has been
/// using this device, at the moment something wakes the process.
///
/// The reason this is a bundle rather than a single reading: on iOS no one
/// signal survives contact with reality. A phone face-down on a table defeats
/// motion. A phone with no passcode reports "unlocked" forever. Someone lying
/// in bed reading for three hours produces no steps at all. Each signal here is
/// weak on its own and they fail for unrelated reasons, which is precisely what
/// makes collecting them together worth doing.
///
/// Two of them — battery level and the pasteboard counter — are worth more than
/// the rest, because they describe the *interval* since the previous sample
/// rather than the instant of the wake. Wakes are scarce and unpredictable, so
/// a reading that summarises the whole gap beats one that describes a single
/// second. Neither is computed here: the raw values are shipped and the deltas
/// are derived server-side, where a change of mind about the model does not
/// require a new build on everybody's phone.
///
/// Every field is optional, and nil means "this device or this OS would not
/// give it to us". That distinction is the entire point — it is how one run on
/// real hardware tells us which of these signals actually exist in the field,
/// rather than leaving a zero to be misread as evidence of stillness.
///
/// Nothing here reads content. The pasteboard counter is a counter, never the
/// clipboard; the audio check is a boolean about whether *something* is
/// playing, never what; motion is reduced to a single variance number before it
/// leaves this file.
struct DeviceSample {
    let eventId: String
    let observedAt: Date
    let trigger: String

    var protectedDataAvailable: Bool?
    var batteryLevel: Float?
    var batteryState: String?
    var lowPowerMode: Bool?
    var pasteboardChangeCount: Int?
    var systemUptimeSeconds: TimeInterval?
    var otherAudioPlaying: Bool?
    var motionVariance: Double?
    var motionSampleCount: Int?
    var stepsSinceLastSample: Int?
    var floorsSinceLastSample: Int?
    var dominantActivity: String?
    var activityConfidence: Int?
    var volumeAvailableBytes: Int64?

    func asPayload(clientId: String?, appVersion: String?, contract: String) -> [String: Any] {
        var body: [String: Any] = [
            "event_id": eventId,
            "observed_at": DeviceSampleCollector.iso8601.string(from: observedAt),
            "trigger": trigger,
            "collector_contract": contract
        ]
        // Absent rather than null: a key that never appears is unmistakably
        // "not read", and it keeps the payload small on the metered background
        // connections these wakes usually run over.
        func put(_ key: String, _ value: Any?) {
            if let value { body[key] = value }
        }
        put("protected_data_available", protectedDataAvailable)
        put("battery_level", batteryLevel)
        put("battery_state", batteryState)
        put("low_power_mode", lowPowerMode)
        put("pasteboard_change_count", pasteboardChangeCount)
        put("system_uptime_seconds", systemUptimeSeconds)
        put("other_audio_playing", otherAudioPlaying)
        put("motion_variance", motionVariance)
        put("motion_sample_count", motionSampleCount)
        put("steps_since_last_sample", stepsSinceLastSample)
        put("floors_since_last_sample", floorsSinceLastSample)
        put("dominant_activity", dominantActivity)
        put("activity_confidence", activityConfidence)
        put("volume_available_bytes", volumeAvailableBytes)
        put("client_id", clientId)
        put("app_version", appVersion)
        return body
    }
}

final class DeviceSampleCollector {
    static let shared = DeviceSampleCollector()

    /// How long to hold the accelerometer open to tell "in a hand" from "on a
    /// table". Long enough for a few hand tremors, short enough that it cannot
    /// meaningfully eat a background execution budget.
    private static let motionWindow: TimeInterval = 2.0
    private static let motionHz: Double = 20

    private enum Key {
        static let lastSampleAt = "kc.sample.lastAt"
    }

    private let defaults = UserDefaults.standard
    private let motionManager = CMMotionManager()
    private let pedometer = CMPedometer()
    private let activityManager = CMMotionActivityManager()

    /// Collects a sample and hands it back. Every reading is individually
    /// guarded: a device that refuses one of them still returns everything
    /// else, because a partial sample is far more useful than none.
    func collect(trigger: String, completion: @escaping (DeviceSample) -> Void) {
        var sample = DeviceSample(
            eventId: UUID().uuidString,
            observedAt: Date(),
            trigger: trigger
        )

        sample.protectedDataAvailable = UIApplication.shared.isProtectedDataAvailable
        sample.systemUptimeSeconds = ProcessInfo.processInfo.systemUptime
        sample.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        // Battery reporting is off by default and returns -1 until enabled;
        // -1 would otherwise be stored as a real reading.
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        sample.batteryLevel = level >= 0 ? level : nil
        switch UIDevice.current.batteryState {
        case .unplugged: sample.batteryState = "unplugged"
        case .charging: sample.batteryState = "charging"
        case .full: sample.batteryState = "full"
        default: sample.batteryState = "unknown"
        }

        // The counter only. Reading the pasteboard's *contents* shows the user a
        // "pasted from" banner and would be an unforgivable thing for a
        // background process to do; reading how many times it changed does not
        // and cannot expose anything that was copied.
        sample.pasteboardChangeCount = UIPasteboard.general.changeCount

        // Covers the person who is lying still with a podcast on — the exact
        // case that produces no steps and no unlocks for hours.
        sample.otherAudioPlaying = AVAudioSession.sharedInstance().isOtherAudioPlaying

        if let capacity = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityKey])
            .volumeAvailableCapacity {
            sample.volumeAvailableBytes = Int64(capacity)
        }

        let since = lastSampleAt()
        let group = DispatchGroup()

        group.enter()
        readMotionVariance { variance, count in
            sample.motionVariance = variance
            sample.motionSampleCount = count
            group.leave()
        }

        group.enter()
        readPedometer(since: since) { steps, floors in
            sample.stepsSinceLastSample = steps
            sample.floorsSinceLastSample = floors
            group.leave()
        }

        group.enter()
        readDominantActivity(since: since) { activity, confidence in
            sample.dominantActivity = activity
            sample.activityConfidence = confidence
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            self?.defaults.set(sample.observedAt.timeIntervalSince1970, forKey: Key.lastSampleAt)
            completion(sample)
        }
    }

    // MARK: - Individual readings

    private func lastSampleAt() -> Date {
        let stored = defaults.double(forKey: Key.lastSampleAt)
        // A first run has nothing to look back at. Six hours is chosen to be
        // longer than any plausible wake interval without dragging in a whole
        // night of history that belongs to an earlier session.
        guard stored > 0 else { return Date().addingTimeInterval(-6 * 3600) }
        return Date(timeIntervalSince1970: stored)
    }

    /// A phone resting on a surface produces acceleration magnitudes that barely
    /// move off 1g; a phone in a hand never stops wobbling. The variance of the
    /// magnitude separates the two without recording anything about *how* it
    /// moved.
    private func readMotionVariance(completion: @escaping (Double?, Int?) -> Void) {
        guard motionManager.isAccelerometerAvailable else {
            completion(nil, nil)
            return
        }
        var magnitudes: [Double] = []
        motionManager.accelerometerUpdateInterval = 1.0 / Self.motionHz
        motionManager.startAccelerometerUpdates(to: OperationQueue()) { data, _ in
            guard let a = data?.acceleration else { return }
            magnitudes.append((a.x * a.x + a.y * a.y + a.z * a.z).squareRoot())
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + Self.motionWindow) { [weak self] in
            self?.motionManager.stopAccelerometerUpdates()
            guard magnitudes.count > 1 else {
                completion(nil, magnitudes.count)
                return
            }
            let mean = magnitudes.reduce(0, +) / Double(magnitudes.count)
            let variance = magnitudes.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(magnitudes.count)
            completion(variance, magnitudes.count)
        }
    }

    /// Steps and floors over the interval. Floors matter more than they look:
    /// they come from the barometer, so a phone rattling around in a vehicle
    /// cannot manufacture them the way it can manufacture steps.
    private func readPedometer(since: Date, completion: @escaping (Int?, Int?) -> Void) {
        guard CMPedometer.isStepCountingAvailable() else {
            completion(nil, nil)
            return
        }
        pedometer.queryPedometerData(from: since, to: Date()) { data, _ in
            guard let data else {
                completion(nil, nil)
                return
            }
            let floors = CMPedometer.isFloorCountingAvailable()
                ? data.floorsAscended?.intValue
                : nil
            completion(data.numberOfSteps.intValue, floors)
        }
    }

    /// Which activity dominated the interval. This is what keeps a phone left on
    /// a bus from reading as a walking human: that interval comes back
    /// `automotive`, and motion evidence from an automotive interval is worth
    /// nothing.
    private func readDominantActivity(since: Date, completion: @escaping (String?, Int?) -> Void) {
        guard CMMotionActivityManager.isActivityAvailable() else {
            completion(nil, nil)
            return
        }
        activityManager.queryActivityStarting(from: since, to: Date(), to: OperationQueue()) { activities, _ in
            guard let activities, !activities.isEmpty else {
                completion(nil, nil)
                return
            }
            // Ranked rather than counted: a single confident automotive stretch
            // has to outweigh a scattering of low-confidence walking, because
            // the whole purpose of this field is to disqualify motion evidence,
            // not to describe the journey.
            let ranked = activities.max { lhs, rhs in
                Self.rank(lhs) < Self.rank(rhs)
            }
            guard let winner = ranked else {
                completion(nil, nil)
                return
            }
            completion(Self.name(for: winner), winner.confidence.rawValue)
        }
    }

    private static func rank(_ activity: CMMotionActivity) -> Int {
        // automotive first: it is the one that invalidates other evidence.
        if activity.automotive { return 5 }
        if activity.cycling { return 4 }
        if activity.running { return 3 }
        if activity.walking { return 2 }
        if activity.stationary { return 1 }
        return 0
    }

    private static func name(for activity: CMMotionActivity) -> String {
        if activity.automotive { return "automotive" }
        if activity.cycling { return "cycling" }
        if activity.running { return "running" }
        if activity.walking { return "walking" }
        if activity.stationary { return "stationary" }
        return "unknown"
    }

    static let iso8601: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
