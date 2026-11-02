import Foundation

// PAT-2582: display types and the pure presentation of one fixture update state.
// See docs/transaction-recovery.md for the presentation contract.

public enum DisplayCheckStatus: Equatable, Sendable {
    case notRun, passed, refused(String)
}

/// Plain display state. It carries no trust: nothing here can authorise or start a transaction.
public struct UpdateDisplayInput: Sendable {
    public var appName: String
    public var installedVersion: String?
    public var candidateVersion: String?
    public var checkedAt: Double?
    public var catalogueCheck: DisplayCheckStatus = .notRun
    public var artifactCheck: DisplayCheckStatus = .notRun
    public var applicationOpen: Bool?
    public var approvedFixtureTarget: String?
    public var deferredUntil: Double?
    public var refusal: TransactionFailure?
    public init(appName: String) { self.appName = appName }
}

public struct UpdateCheckRow: Equatable, Sendable {
    public let title: String
    public let status: String
    public init(title: String, status: String) { self.title = title; self.status = status }
}

/// Diagnostic strings for one display state. Refusals carry their raw code here; the words
/// a person sees come from `UpdateViewText` in PatchedUI. Nothing here reads a path or grants authority.
public struct UpdatePresentation: Equatable, Sendable {
    public let previewNotice: String
    public let heading: String
    public let installedLine: String
    public let checkedLine: String
    public let checks: [UpdateCheckRow]
    public let refusalLine: String?
    public let deferralLine: String?
    public let actionTitle: String
    public let actionEnabled: Bool
    public let actionNote: String

    public static func make(_ input: UpdateDisplayInput) -> UpdatePresentation {
        let checkedLine: String
        if let checkedAt = input.checkedAt {
            checkedLine = "Checked: \(utcMinute(checkedAt) ?? "unknown")"
        } else {
            checkedLine = "Checked: never"
        }
        let closed: String
        switch input.applicationOpen {
        case nil: closed = "Not checked"
        case false?: closed = "Closed"
        case true?: closed = "Open. Patched will not quit it"
        }
        // A deferral is information only. Nothing is scheduled and it never disables the action.
        let deferralLine = input.deferredUntil.map { until in
            utcMinute(until).map { "Deferred until \($0). Nothing runs on its own." } ?? "Deferred. Nothing runs on its own."
        }

        // The first unmet condition, in this order, is the one explained.
        let enabled: Bool, note: String
        if input.candidateVersion == nil {
            (enabled, note) = (false, "No update candidate.")
        } else if input.refusal != nil {
            (enabled, note) = (false, "Refused. Nothing runs until you choose Update again.")
        } else if input.catalogueCheck != .passed || input.artifactCheck != .passed {
            (enabled, note) = (false, "Checks have not passed.")
        } else if input.applicationOpen == nil {
            (enabled, note) = (false, "App state not checked.")
        } else if input.applicationOpen == true {
            (enabled, note) = (false, "\(input.appName) is open. Close it yourself, then choose Update.")
        } else if let target = input.approvedFixtureTarget {
            (enabled, note) = (true, "Fixture target: \(target). Runs only when you choose Update.")
        } else {
            (enabled, note) = (false, "No approved target.")
        }

        return UpdatePresentation(
            previewNotice: "Fixture preview. No installed app is checked or changed.",
            heading: input.candidateVersion.map { "\(input.appName) \($0)" } ?? "No update candidate",
            installedLine: "Installed: \(input.installedVersion ?? "unknown")",
            checkedLine: checkedLine,
            checks: [UpdateCheckRow(title: "Catalogue signature", status: status(input.catalogueCheck)),
                     UpdateCheckRow(title: "Staged bytes", status: status(input.artifactCheck)),
                     UpdateCheckRow(title: "macOS signature and notarisation", status: "Not run in this fixture preview"),
                     UpdateCheckRow(title: "App closed", status: closed)],
            refusalLine: input.refusal.map { "Refused: \($0.rawValue)" },
            deferralLine: deferralLine,
            actionTitle: "Update \(input.appName)", actionEnabled: enabled, actionNote: note)
    }

    private static func status(_ check: DisplayCheckStatus) -> String {
        switch check {
        case .notRun: "Not run"
        case .passed: "Passed"
        case .refused(let reason): "Refused: \(reason)"
        }
    }

    /// The first second of year 10000. A clock at or beyond it is unknown.
    private static let clockLimit = 253_402_300_800.0

    /// `YYYY-MM-DD HH:MM UTC` for the whole minute containing a clock value, or nil for a clock that is
    /// not finite, is negative or is at or beyond year 10000. The range is checked before any conversion,
    /// so no time is invented and no out-of-range value reaches an integer or a calendar.
    private static func utcMinute(_ seconds: Double) -> String? {
        guard seconds.isFinite, seconds >= 0, seconds < clockLimit else { return nil }
        let minute = Int((seconds / 60).rounded(.down))
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        guard let utc = TimeZone(secondsFromGMT: 0) else { return nil }
        calendar.timeZone = utc
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute],
                                            from: Date(timeIntervalSince1970: Double(minute * 60)))
        guard let year = parts.year, let month = parts.month, let day = parts.day, let hour = parts.hour,
              let minutes = parts.minute, (1970...9999).contains(year) else { return nil }
        func padded(_ value: Int, _ width: Int) -> String {
            let digits = String(value)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        return "\(padded(year, 4))-\(padded(month, 2))-\(padded(day, 2)) \(padded(hour, 2)):\(padded(minutes, 2)) UTC"
    }
}
