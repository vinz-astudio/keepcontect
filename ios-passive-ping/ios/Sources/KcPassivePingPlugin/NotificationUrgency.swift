import Foundation

/// Which notification kinds may break through Focus and Notification Summary
/// (human decision D1, 2026-11-02). The subject's own safety ask and real
/// emergencies do; lost-contact notices to the circle do not, so they do not
/// spend other people's attention. Mirrors
/// `supabase/functions/push-dispatch/interruption.ts`.
enum NotificationUrgency {
    static let timeSensitiveKinds: Set<String> = ["self", "concern", "sos", "terminal"]

    static func isTimeSensitive(kind: String) -> Bool {
        timeSensitiveKinds.contains(kind)
    }
}
