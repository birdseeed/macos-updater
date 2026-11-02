import Foundation

// Descriptive synthetic history data only. No observation here is native installation proof.
public enum ActivityOrigin: String, Codable, CaseIterable, Sendable {
    case manualIndividual, manualBatch, scheduled, recovery, customerRestoration
}
public enum ActivityStatus: String, Codable, CaseIterable, Sendable {
    case queued, started, downloaded, succeeded, failed, deferred, skipped, incomplete, needsRecovery, restored
}
public enum ActivityReason: String, Codable, CaseIterable, Sendable {
    case none, verificationFailed, runningApplication, userSkipped, unavailableReadback, interrupted, recoveryRequired, unknown
}
public enum ActivityReportState: String, Codable, CaseIterable, Sendable { case missing, queued, sent, failed }
public struct ActivityEvent: Codable, Equatable, Sendable {
    public let eventID: String
    public let attemptID: String
    public let targetKey: String
    public let appName: String
    public let origin: ActivityOrigin
    public let status: ActivityStatus
    public let reason: ActivityReason
    public let sequence: UInt64
    public let observedAt: UInt64?
    public let resolvedAt: UInt64?
    public let beforeVersion: String?
    public let afterVersion: String?
    public let beforeBuild: String?
    public let afterBuild: String?
    public let runID: String?
    public let requestID: String?
    public let transactionID: String?
    public let parentUpdateID: String?
    public let reportID: String?
    public init(eventID: String, attemptID: String, targetKey: String, appName: String,
                origin: ActivityOrigin, status: ActivityStatus, reason: ActivityReason = .none,
                sequence: UInt64, observedAt: UInt64? = nil, resolvedAt: UInt64? = nil,
                beforeVersion: String? = nil, afterVersion: String? = nil,
                beforeBuild: String? = nil, afterBuild: String? = nil,
                runID: String? = nil, requestID: String? = nil, transactionID: String? = nil,
                parentUpdateID: String? = nil, reportID: String? = nil) {
        self.eventID = eventID; self.attemptID = attemptID; self.targetKey = targetKey; self.appName = appName
        self.origin = origin; self.status = status; self.reason = reason; self.sequence = sequence
        self.observedAt = observedAt; self.resolvedAt = resolvedAt
        self.beforeVersion = beforeVersion; self.afterVersion = afterVersion
        self.beforeBuild = beforeBuild; self.afterBuild = afterBuild
        self.runID = runID; self.requestID = requestID; self.transactionID = transactionID
        self.parentUpdateID = parentUpdateID; self.reportID = reportID
    }
}
public struct ActivityRecord: Codable, Equatable, Sendable {
    public let schema: UInt64
    public let principal: String
    public let storeID: String
    public let revision: UInt64
    public let events: [ActivityEvent]
    public init(schema: UInt64 = 1, principal: String, storeID: String, revision: UInt64, events: [ActivityEvent]) {
        self.schema = schema; self.principal = principal; self.storeID = storeID
        self.revision = revision; self.events = events
    }
}
public enum ActivityRefusal: Error, Equatable { case unavailable, invalidWire, conflict, quota, uncertain, reentrant, readbackMismatch }
public enum ActivityWire {
    public static let maximumBytes = 2 * 1024 * 1024
    public static let maximumEvents = 2000
    // Contract: UTF8 JSONEncoder .sortedKeys + .withoutEscapingSlashes, absent optionals omitted,
    // no whitespace/newline; strict closed fields/types, canonical UUID uppercase, exact re-encode.
    public static func decode(_ bytes: Data, principal: String, storeID: String) throws -> ActivityRecord {
        guard bytes.count <= maximumBytes else { throw ActivityRefusal.quota }
        do {
            let record = try JSONDecoder().decode(ActivityRecord.self, from: bytes)
            guard record.principal == principal, record.storeID == storeID,
                  try encode(record) == bytes else { throw ActivityRefusal.invalidWire }
            return record
        } catch let refusal as ActivityRefusal { throw refusal }
        catch { throw ActivityRefusal.invalidWire }
    }
    public static func encode(_ record: ActivityRecord) throws -> Data {
        guard record.schema == 1, validText(record.principal, limit: 256), validUUID(record.storeID) else {
            throw ActivityRefusal.invalidWire
        }
        guard record.events.count <= maximumEvents else { throw ActivityRefusal.quota }
        var identities = Set<String>()
        for event in record.events {
            guard validUUID(event.eventID), validUUID(event.attemptID),
                  validText(event.targetKey, limit: 256), validText(event.appName, limit: 256),
                  identities.insert(event.eventID).inserted else { throw ActivityRefusal.invalidWire }
            for text in [event.beforeVersion, event.afterVersion, event.beforeBuild, event.afterBuild] {
                if let text, !validText(text, limit: 128) { throw ActivityRefusal.invalidWire }
            }
            for id in [event.runID, event.requestID, event.transactionID, event.parentUpdateID, event.reportID] {
                if let id, !validUUID(id) { throw ActivityRefusal.invalidWire }
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(record)
        guard bytes.count <= maximumBytes else { throw ActivityRefusal.quota }
        return bytes
    }
    private static func validUUID(_ text: String) -> Bool {
        text.utf8.count == 36 && UUID(uuidString: text)?.uuidString == text
    }
    private static func validText(_ text: String, limit: Int) -> Bool {
        !text.isEmpty && text.utf8.count <= limit &&
        !text.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}
