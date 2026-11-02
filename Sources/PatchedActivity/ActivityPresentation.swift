import Foundation

public struct ActivityRow: Equatable, Sendable {
    public let eventID: String
    public let attemptID: String
    public let text: String
    public init(eventID: String, attemptID: String, text: String) { self.eventID = eventID; self.attemptID = attemptID; self.text = text }
}
public struct ActivityPresentation: Equatable, Sendable {
    public let headline: String
    public let provenance: String
    public let retainedRange: String
    public let policy: String
    public let rows: [ActivityRow]
    public init(headline: String, provenance: String, retainedRange: String, policy: String, rows: [ActivityRow]) {
        self.headline = headline; self.provenance = provenance; self.retainedRange = retainedRange
        self.policy = policy; self.rows = rows
    }
    public static func make(_ snapshot: ActivitySnapshot) -> ActivityPresentation {
        let dates = snapshot.events.compactMap(\.observedAt)
        var range: String
        if let earliest = dates.min(), let latest = dates.max() {
            range = String(earliest) + " to " + String(latest)
            if dates.count != snapshot.events.count { range += " • unknown dates" }
        } else { range = "Dates unknown" }
        if !snapshot.ageAvailable { range += " • Retention age unavailable" }
        let rows = snapshot.available ? snapshot.events.map { event in
            ActivityRow(eventID: event.eventID, attemptID: event.attemptID,
                        text: event.appName + " • " + label(event.status) + " • " + event.origin.rawValue +
                        "\nVersion: " + (event.beforeVersion ?? "Unknown") + " → " + (event.afterVersion ?? "Unknown") +
                        " • Build: " + (event.beforeBuild ?? "Unknown") + " → " + (event.afterBuild ?? "Unknown") +
                        "\nObserved: " + (event.observedAt.map(String.init) ?? "Unknown") +
                        "\nReason: " + reasonLabel(event.reason))
        } : []
        return ActivityPresentation(headline: !snapshot.available ? "Activity unavailable" : (rows.isEmpty ? "No activity" : "Activity"),
                                    provenance: "Synthetic fixture only", retainedRange: range,
                                    policy: "30 days • 2000 events • 2 MiB", rows: rows)
    }
    private static func label(_ status: ActivityStatus) -> String {
        status == .needsRecovery ? "Needs recovery" : status.rawValue.capitalized
    }
    private static func reasonLabel(_ reason: ActivityReason) -> String {
        switch reason {
        case .none: return "None"
        case .verificationFailed: return "Verification failed"
        case .runningApplication: return "Running application"
        case .userSkipped: return "User skipped"
        case .unavailableReadback: return "Unavailable readback"
        case .interrupted: return "Interrupted"
        case .recoveryRequired: return "Recovery required"
        case .unknown: return "Unknown"
        }
    }
}
