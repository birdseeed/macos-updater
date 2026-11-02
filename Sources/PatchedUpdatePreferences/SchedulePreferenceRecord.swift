import Foundation
import PatchedScheduling

/// Pure versioned storage value. The embedded schema-1 record remains unchanged.
public struct SchedulePreferenceRecord: Equatable, Sendable {
    public static let maximumBytes = 4_194_304
    public static let maximumCombinedMutations = 128
    public let schema: UInt64
    public let preferences: PreferenceRecord
    public let settings: ScheduleSettings
    public let settingsMutations: [ScheduleSettingsMutationReceipt]
    /// Unvalidated declaration, never an accepted session or persistence acknowledgement.
    @_spi(Testing) public init(schema: UInt64 = 2, preferences: PreferenceRecord,
                              settings: ScheduleSettings, settingsMutations: [ScheduleSettingsMutationReceipt] = []) {
        self.schema = schema; self.preferences = preferences; self.settings = settings
        self.settingsMutations = settingsMutations
    }
}
/// An inert proposal. A future sole CAS owner must independently validate and persist it.
public struct SchedulePreferenceMigrationProposal: Equatable, Sendable {
    public let originalV1Bytes: Data
    public let proposedV2Bytes: Data
    public let record: SchedulePreferenceRecord
    @_spi(Testing) public init(originalV1Bytes: Data, proposedV2Bytes: Data, record: SchedulePreferenceRecord) {
        self.originalV1Bytes = originalV1Bytes; self.proposedV2Bytes = proposedV2Bytes; self.record = record
    }
}
public enum SchedulePreferenceRecordCodec {
    public static func encode(_ record: SchedulePreferenceRecord) throws -> Data {
        do {
            guard record.schema == 2,
                  record.settingsMutations.count <= SchedulePreferenceRecord.maximumCombinedMutations,
                  record.preferences.mutations.count <= SchedulePreferenceRecord.maximumCombinedMutations - record.settingsMutations.count else {
                throw PreferenceRefusal.malformed
            }
            // The existing codec alone owns the inner schema, history and integer precision.
            let inner = try PreferenceRecordCodec.encode(record.preferences)
            guard let innerText = String(data: inner, encoding: .utf8) else { throw PreferenceRefusal.malformed }
            var ids = Set(record.preferences.mutations.map { $0.id })
            let receipts: [[String: Any]] = try record.settingsMutations.map { receipt in
                guard validScheduleReceiptID(receipt.id), ids.insert(receipt.id).inserted else {
                    throw PreferenceRefusal.malformed
                }
                return ["id": receipt.id, "change": try scheduleChangeObject(receipt.change)]
            }
            let bytes = try JSONSerialization.data(withJSONObject: [
                "schema": NSNumber(value: record.schema), "preferences": innerText,
                "settings": try scheduleSettingsObject(record.settings), "settingsMutations": receipts
            ], options: [.sortedKeys, .withoutEscapingSlashes])
            guard bytes.count <= SchedulePreferenceRecord.maximumBytes else { throw PreferenceRefusal.limit }
            return bytes
        } catch let reason as PreferenceRefusal { throw reason == .limit ? reason : .malformed }
        catch { throw PreferenceRefusal.malformed }
    }
    public static func decodeV2(_ bytes: Data, principal: SchedulingPrincipal,
                                storeScope: String) throws -> SchedulePreferenceRecord {
        guard !bytes.isEmpty, bytes.count <= SchedulePreferenceRecord.maximumBytes else {
            throw PreferenceRefusal.malformed
        }
        do {
            let wire = try JSONDecoder().decode(ScheduleRecordWire.self, from: bytes)
            let preferences = try PreferenceRecordCodec.decode(Data(wire.preferences.utf8), principal: principal, storeScope: storeScope)
            let record = SchedulePreferenceRecord(schema: wire.schema, preferences: preferences,
                settings: wire.settings.value, settingsMutations: wire.settingsMutations.map {
                    ScheduleSettingsMutationReceipt(id: $0.id, change: $0.change.value)
                })
            // Reject unknown/duplicate keys and every noncanonical spelling at all outer levels.
            guard try encode(record) == bytes else { throw PreferenceRefusal.malformed }
            return record
        } catch { throw PreferenceRefusal.malformed }
    }
    public static func proposeV1Migration(_ bytes: Data, principal: SchedulingPrincipal,
                                          storeScope: String) throws -> SchedulePreferenceMigrationProposal {
        let preferences = try PreferenceRecordCodec.decode(bytes, principal: principal, storeScope: storeScope)
        let record = SchedulePreferenceRecord(preferences: preferences, settings: ScheduleSettings())
        return SchedulePreferenceMigrationProposal(originalV1Bytes: bytes, proposedV2Bytes: try encode(record), record: record)
    }
}

private struct ScheduleRecordWire: Decodable {
    let schema: UInt64
    let preferences: String
    let settings: ScheduleSettingsWire
    let settingsMutations: [ScheduleReceiptWire]
}
private struct ScheduleReceiptWire: Decodable {
    let id: String
    let change: ScheduleChangeWire
}
private struct SchedulePauseWire: Decodable {
    let resumeUTC: Int64
    let displayZone: String
    var value: SchedulePauseChoice { SchedulePauseChoice(resumeUTC: resumeUTC, displayZone: displayZone) }
}
private struct ScheduleSettingsWire: Decodable {
    let dailyChecks: Bool
    let notifications: Bool
    let automaticUpdates: Bool
    let pause: SchedulePauseWire?
    private enum CodingKeys: String, CodingKey { case dailyChecks, notifications, automaticUpdates, pause }
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        dailyChecks = try fields.decode(Bool.self, forKey: .dailyChecks)
        notifications = try fields.decode(Bool.self, forKey: .notifications)
        automaticUpdates = try fields.decode(Bool.self, forKey: .automaticUpdates)
        // decode(Optional.self) requires the key even when its value is null.
        pause = try fields.decode(SchedulePauseWire?.self, forKey: .pause)
    }
    var value: ScheduleSettings {
        ScheduleSettings(dailyChecks: dailyChecks, notifications: notifications,
                         automaticUpdates: automaticUpdates, pause: pause?.value)
    }
}
private struct ScheduleChangeWire: Decodable {
    let value: ScheduleSettingsChange
    private enum CodingKeys: String, CodingKey { case action, enabled, pause }
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        switch try fields.decode(String.self, forKey: .action) {
        case "dailyChecks": value = .dailyChecks(try fields.decode(Bool.self, forKey: .enabled))
        case "notifications": value = .notifications(try fields.decode(Bool.self, forKey: .enabled))
        case "automaticUpdates": value = .automaticUpdates(try fields.decode(Bool.self, forKey: .enabled))
        case "pause": value = .pause(try fields.decode(SchedulePauseWire?.self, forKey: .pause)?.value)
        default: throw PreferenceRefusal.malformed
        }
    }
}
private func validScheduleReceiptID(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 256 &&
        !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
}
private func schedulePauseObject(_ pause: SchedulePauseChoice?) throws -> Any {
    guard let pause else { return NSNull() }
    let label = pause.displayZone.utf8
    guard pause.resumeUTC >= 0, !label.isEmpty, label.count <= 128 else { throw PreferenceRefusal.malformed }
    var segmentHasCharacter = false
    for byte in label {
        if byte == 47 {
            guard segmentHasCharacter else { throw PreferenceRefusal.malformed }
            segmentHasCharacter = false
        } else {
            guard (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) ||
                  byte == 95 || byte == 43 || byte == 45 else { throw PreferenceRefusal.malformed }
            segmentHasCharacter = true
        }
    }
    guard segmentHasCharacter else { throw PreferenceRefusal.malformed }
    return ["resumeUTC": NSNumber(value: pause.resumeUTC), "displayZone": pause.displayZone]
}
private func scheduleSettingsObject(_ settings: ScheduleSettings) throws -> [String: Any] {
    ["dailyChecks": settings.dailyChecks, "notifications": settings.notifications,
     "automaticUpdates": settings.automaticUpdates, "pause": try schedulePauseObject(settings.pause)]
}
private func scheduleChangeObject(_ change: ScheduleSettingsChange) throws -> [String: Any] {
    switch change {
    case .dailyChecks(let enabled): return ["action": "dailyChecks", "enabled": enabled]
    case .notifications(let enabled): return ["action": "notifications", "enabled": enabled]
    case .automaticUpdates(let enabled): return ["action": "automaticUpdates", "enabled": enabled]
    case .pause(let pause): return ["action": "pause", "pause": try schedulePauseObject(pause)]
    }
}
