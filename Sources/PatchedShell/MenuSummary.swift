/// Display facts supplied by a future shared owner; never update authority.
public struct MenuSummaryCounts: Equatable, Sendable {
    public let ready: Int
    public let externallyManaged: Int
    public let skipped: Int
    public let deferred: Int

    public init(ready: Int, externallyManaged: Int, skipped: Int, deferred: Int) {
        self.ready = ready
        self.externallyManaged = externallyManaged
        self.skipped = skipped
        self.deferred = deferred
    }
}

/// Freshness is supplied, not observed by this presentation component.
public enum MenuSummaryObservation: Equatable, Sendable {
    case unavailable
    case current
    case cached(ageMinutes: Int?)
}

/// Immutable words only. Construction performs no operation or callback.
public struct MenuSummary: Equatable, Sendable {
    public let title: String
    public let details: [String]
    public let accessibilitySummary: String

    public init(counts: MenuSummaryCounts? = nil,
                observation: MenuSummaryObservation = .unavailable,
                isChecking: Bool = false,
                automaticInstallationPaused: Bool = false,
                needsAttention: Bool = false) {
        var projectedTitle = "Update status unavailable"
        var projectedDetails: [String] = []

        if let counts,
           counts.ready >= 0, counts.externallyManaged >= 0,
           counts.skipped >= 0, counts.deferred >= 0 {
            switch observation {
            case .unavailable:
                break
            case .current:
                switch counts.ready {
                case 0: projectedTitle = "No ready updates"
                case 1: projectedTitle = "1 update ready"
                default: projectedTitle = "\(counts.ready) updates ready"
                }
                projectedDetails = [
                    "Ready: \(counts.ready)",
                    "Externally managed: \(counts.externallyManaged)",
                    "Skipped: \(counts.skipped)",
                    "Deferred: \(counts.deferred)"
                ]
            case .cached(let ageMinutes):
                projectedTitle = "Cached update information"
                projectedDetails = [
                    "Cached ready: \(counts.ready)",
                    "Cached externally managed: \(counts.externallyManaged)",
                    "Cached skipped: \(counts.skipped)",
                    "Cached deferred: \(counts.deferred)"
                ]
                if let ageMinutes, ageMinutes >= 0 {
                    let unit = ageMinutes == 1 ? "minute" : "minutes"
                    projectedDetails.append("Last checked \(ageMinutes) \(unit) ago")
                } else {
                    projectedDetails.append("Last checked: age unavailable")
                }
            }
        }

        if isChecking {
            projectedDetails.append("Checking for updates")
        }
        if automaticInstallationPaused {
            projectedDetails.append("Automatic installation paused")
        }
        if needsAttention {
            projectedDetails.append("Needs attention")
        }

        title = projectedTitle
        details = projectedDetails
        accessibilitySummary = ([projectedTitle] + projectedDetails).joined(separator: ". ")
    }
}
