import Foundation
import PatchedScheduling

/// Pure versioned declaration. The existing schema-2 envelope is embedded unchanged.
public struct FirstRunPreferenceRecord: Equatable, Sendable {
    public static let maximumBytes = PreferenceRecord.maximumBytes
    public static let maximumCombinedMutations = 128
    public let schema: UInt64
    public let scheduled: SchedulePreferenceRecord
    public let setup: FirstRunSetupState
    public let setupMutations: [FirstRunSetupMutationReceipt]
    @_spi(Testing) public init(schema: UInt64 = 3, scheduled: SchedulePreferenceRecord,
                              setup: FirstRunSetupState, setupMutations: [FirstRunSetupMutationReceipt] = []) {
        self.schema = schema; self.scheduled = scheduled; self.setup = setup; self.setupMutations = setupMutations
    }
}
/// Strict canonical schema-3 wrapper around the unchanged schema-2 codec.
public enum FirstRunPreferenceRecordCodec {
    public static func encode(_ record: FirstRunPreferenceRecord) throws -> Data {
        do {
            let oldCount = record.scheduled.preferences.mutations.count + record.scheduled.settingsMutations.count
            guard record.schema == 3,
                  record.setupMutations.count <= FirstRunPreferenceRecord.maximumCombinedMutations,
                  oldCount <= FirstRunPreferenceRecord.maximumCombinedMutations - record.setupMutations.count else {
                throw PreferenceRefusal.malformed
            }
            let scheduled = try SchedulePreferenceRecordCodec.encode(record.scheduled)
            guard let scheduledText = String(data: scheduled, encoding: .utf8) else { throw PreferenceRefusal.malformed }
            var ids = Set(record.scheduled.preferences.mutations.map { $0.id })
            ids.formUnion(record.scheduled.settingsMutations.map { $0.id })
            let receipts: [[String: Any]] = try record.setupMutations.map { receipt in
                guard firstRunReceiptIDIsValid(receipt.id), ids.insert(receipt.id).inserted else {
                    throw PreferenceRefusal.malformed
                }
                return ["id": receipt.id, "choices": try firstRunChoicesObject(receipt.choices), "complete": receipt.complete]
            }
            let bytes = try JSONSerialization.data(withJSONObject: [
                "schema": NSNumber(value: record.schema), "scheduled": scheduledText,
                "setup": ["failureReports": record.setup.failureReports, "completed": record.setup.completed,
                          "networkDraft": try firstRunDraftObject(record.setup.networkDraft)],
                "setupMutations": receipts
            ], options: [.sortedKeys, .withoutEscapingSlashes])
            guard bytes.count <= FirstRunPreferenceRecord.maximumBytes else { throw PreferenceRefusal.limit }
            return bytes
        } catch let reason as PreferenceRefusal { throw reason == .limit ? reason : .malformed }
        catch { throw PreferenceRefusal.malformed }
    }
    public static func decodeV3(_ bytes: Data, principal: SchedulingPrincipal,
                                storeScope: String) throws -> FirstRunPreferenceRecord {
        guard !bytes.isEmpty, bytes.count <= FirstRunPreferenceRecord.maximumBytes else { throw PreferenceRefusal.malformed }
        do {
            let wire = try JSONDecoder().decode(FirstRunRecordWire.self, from: bytes)
            let scheduled = try SchedulePreferenceRecordCodec.decodeV2(Data(wire.scheduled.utf8),
                principal: principal, storeScope: storeScope)
            // Swift String equality permits canonical Unicode equivalents; owner identity does not.
            guard scheduled.preferences.principal.value.utf8.elementsEqual(principal.value.utf8),
                  scheduled.preferences.storeScope.utf8.elementsEqual(storeScope.utf8) else {
                throw PreferenceRefusal.malformed
            }
            let record = FirstRunPreferenceRecord(schema: wire.schema, scheduled: scheduled,
                setup: try wire.setup.value(), setupMutations: try wire.setupMutations.map {
                    FirstRunSetupMutationReceipt(id: $0.id, choices: try $0.choices.value(), complete: $0.complete)
                })
            // This also rejects unknown/duplicate keys and noncanonical scalar spellings at every level.
            guard try encode(record) == bytes else { throw PreferenceRefusal.malformed }
            return record
        } catch { throw PreferenceRefusal.malformed }
    }
}

private struct FirstRunRecordWire: Decodable {
    let schema: UInt64
    let scheduled: String
    let setup: FirstRunSetupWire
    let setupMutations: [FirstRunReceiptWire]
}
private struct FirstRunReceiptWire: Decodable {
    let id: String
    let choices: FirstRunChoicesWire
    let complete: Bool
}
private struct FirstRunDraftWire: Decodable {
    let mode: String
    let host: String
    let port: String
    func value() throws -> FirstRunNetworkDraft {
        guard let mode = FirstRunNetworkDraftMode(rawValue: mode) else { throw PreferenceRefusal.malformed }
        return FirstRunNetworkDraft(mode: mode, host: host, port: port)
    }
}
private struct FirstRunSetupWire: Decodable {
    let failureReports: Bool
    let completed: Bool
    let networkDraft: FirstRunDraftWire
    func value() throws -> FirstRunSetupState {
        FirstRunSetupState(failureReports: failureReports, completed: completed, networkDraft: try networkDraft.value())
    }
}
private struct FirstRunChoicesWire: Decodable {
    let dailyChecks: Bool
    let notifications: Bool
    let failureReports: Bool
    let networkDraft: FirstRunDraftWire
    func value() throws -> FirstRunChoices {
        FirstRunChoices(dailyChecks: dailyChecks, notifications: notifications,
                        failureReports: failureReports, networkDraft: try networkDraft.value())
    }
}
private func firstRunReceiptIDIsValid(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 256 &&
        !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
}
private func firstRunDraftObject(_ draft: FirstRunNetworkDraft) throws -> [String: Any] {
    guard draft.host.utf8.count <= 254, draft.port.utf8.count <= 6,
          ![draft.host, draft.port].contains(where: { value in
              value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
          }), !draft.host.contains("@"), !draft.host.contains("://"),
          draft.mode == .manualHTTP || (draft.host.isEmpty && draft.port.isEmpty) else {
        throw PreferenceRefusal.malformed
    }
    return ["mode": draft.mode.rawValue, "host": draft.host, "port": draft.port]
}
private func firstRunChoicesObject(_ choices: FirstRunChoices) throws -> [String: Any] {
    ["dailyChecks": choices.dailyChecks, "notifications": choices.notifications,
     "failureReports": choices.failureReports, "networkDraft": try firstRunDraftObject(choices.networkDraft)]
}
