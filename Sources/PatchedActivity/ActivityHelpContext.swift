import Foundation

public struct ActivityReport: Equatable, Sendable {
    public let reportID: String
    public let eventID: String
    public let attemptID: String
    public let state: ActivityReportState
    public init(reportID: String, eventID: String, attemptID: String, state: ActivityReportState) {
        self.reportID = reportID; self.eventID = eventID; self.attemptID = attemptID; self.state = state
    }
}
public struct ActivityContextBlock: Codable, Equatable, Sendable {
    public let eventID: String
    public let attemptID: String
    public let revision: UInt64
    public let text: String
    public init(eventID: String, attemptID: String, revision: UInt64, text: String) {
        self.eventID = eventID; self.attemptID = attemptID; self.revision = revision; self.text = text
    }
}
public struct ActivityDraft: Codable, Equatable, Sendable {
    public var email: String
    public var message: String
    public var contexts: [ActivityContextBlock]
    public init(email: String, message: String, contexts: [ActivityContextBlock] = []) {
        self.email = email; self.message = message; self.contexts = contexts
    }
}
public enum ActivityHelpContext {
    public static let maximumEmailBytes = 320
    public static let maximumMessageBytes = 16_384
    public static let maximumContexts = 256
    public static func encodeDraft(_ draft: ActivityDraft) throws -> Data {
        try validate(draft)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(draft)
    }
    public static func decodeDraft(_ bytes: Data) throws -> ActivityDraft {
        guard bytes.count <= 1_048_576 else { throw ActivityRefusal.quota }
        do {
            let draft = try JSONDecoder().decode(ActivityDraft.self, from: bytes)
            guard try encodeDraft(draft) == bytes else { throw ActivityRefusal.invalidWire }
            return draft
        } catch let error as ActivityRefusal { throw error }
        catch { throw ActivityRefusal.invalidWire }
    }
    public static func append(event: ActivityEvent, revision: UInt64, report: ActivityReport?, to draft: ActivityDraft) throws -> ActivityDraft {
        try validate(draft)
        guard revision < UInt64.max, validUUID(event.eventID), validUUID(event.attemptID) else {
            throw ActivityRefusal.invalidWire
        }
        let correlations: [(String, String?)] = [("Run", event.runID), ("Request", event.requestID),
            ("Transaction", event.transactionID), ("Parent update", event.parentUpdateID), ("Report", event.reportID)]
        var lines = ["Synthetic fixture only", "Event: " + event.eventID, "Attempt: " + event.attemptID,
                     "Context revision: " + String(revision), "Status: " + statusLabel(event.status),
                     "Reason: " + reasonLabel(event.reason), "Report state: " + reportState(event: event, report: report).rawValue.capitalized]
        for (label, id) in correlations {
            if let id {
                guard validUUID(id) else { throw ActivityRefusal.invalidWire }
                lines.append(label + ": " + id)
            }
        }
        let block = ActivityContextBlock(eventID: event.eventID, attemptID: event.attemptID, revision: revision,
                                         text: lines.joined(separator: "\n"))
        if let existing = draft.contexts.first(where: {
            $0.eventID == event.eventID && $0.attemptID == event.attemptID && $0.revision == revision
        }) {
            guard existing == block else { throw ActivityRefusal.conflict }
            return draft
        }
        guard draft.contexts.count < maximumContexts else { throw ActivityRefusal.quota }
        var result = draft; result.contexts.append(block)
        return result
    }
    public static func reportState(event: ActivityEvent, report: ActivityReport?) -> ActivityReportState {
        guard let report, let id = event.reportID, validUUID(id), validUUID(event.eventID), validUUID(event.attemptID),
              report.reportID == id, report.eventID == event.eventID, report.attemptID == event.attemptID else { return .missing }
        return report.state
    }
    public static func preview(_ draft: ActivityDraft) throws -> [String] {
        try validate(draft)
        return draft.contexts.map(\.text)
    }
    private static func validUUID(_ value: String) -> Bool {
        value.utf8.count == 36 && UUID(uuidString: value)?.uuidString == value
    }
    private static func validate(_ draft: ActivityDraft) throws {
        guard draft.email.utf8.count <= maximumEmailBytes, draft.message.utf8.count <= maximumMessageBytes,
              draft.contexts.count <= maximumContexts else { throw ActivityRefusal.quota }
        var identities = Set<String>()
        for block in draft.contexts {
            guard validUUID(block.eventID), validUUID(block.attemptID), block.revision < UInt64.max,
                  block.text.utf8.count <= 2048,
                  identities.insert(block.eventID + "/" + block.attemptID + "/" + String(block.revision)).inserted else {
                throw ActivityRefusal.invalidWire
            }
            let lines = block.text.components(separatedBy: "\n")
            guard (7...12).contains(lines.count), lines[0] == "Synthetic fixture only",
                  lines[1] == "Event: " + block.eventID, lines[2] == "Attempt: " + block.attemptID,
                  lines[3] == "Context revision: " + String(block.revision),
                  ActivityStatus.allCases.map({ "Status: " + statusLabel($0) }).contains(lines[4]),
                  ActivityReason.allCases.map({ "Reason: " + reasonLabel($0) }).contains(lines[5]),
                  ActivityReportState.allCases.map({ "Report state: " + $0.rawValue.capitalized }).contains(lines[6]) else {
                throw ActivityRefusal.invalidWire
            }
            let labels = ["Run", "Request", "Transaction", "Parent update", "Report"]
            var previousIndex = -1
            for line in lines.dropFirst(7) {
                guard let index = labels.firstIndex(where: { line.hasPrefix($0 + ": ") }), index > previousIndex else {
                    throw ActivityRefusal.invalidWire
                }
                let value = String(line.dropFirst(labels[index].count + 2))
                guard validUUID(value) else { throw ActivityRefusal.invalidWire }
                previousIndex = index
            }
        }
    }
    private static func statusLabel(_ status: ActivityStatus) -> String {
        switch status {
        case .needsRecovery: return "Needs recovery"
        default: return status.rawValue.capitalized
        }
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
