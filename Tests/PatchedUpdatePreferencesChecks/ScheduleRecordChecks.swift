import Foundation
import PatchedScheduling
@_spi(Testing) import PatchedUpdatePreferences

// Expectations come only from literals and test-owned JSON, never the new codec.
private let srV1 = #"{"exclusions":[],"mutations":[],"principal":"synthetic-owner","revision":0,"schema":1,"skips":[],"storeScope":"synthetic-store"}"#
private let srV2 = #"{"preferences":"{\"exclusions\":[],\"mutations\":[],\"principal\":\"synthetic-owner\",\"revision\":0,\"schema\":1,\"skips\":[],\"storeScope\":\"synthetic-store\"}","schema":2,"settings":{"automaticUpdates":false,"dailyChecks":true,"notifications":true,"pause":null},"settingsMutations":[]}"#
private func srJSON(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
}
private func srPause(_ utc: Int64, _ zone: String) -> [String: Any] {
    ["resumeUTC": NSNumber(value: utc), "displayZone": zone]
}
private func srSettings(_ daily: Bool = true, _ notify: Bool = true, _ automatic: Bool = false,
                        _ pause: Any = NSNull()) -> [String: Any] {
    ["dailyChecks": daily, "notifications": notify, "automaticUpdates": automatic, "pause": pause]
}
private func srWire(_ inner: String = srV1, settings: [String: Any] = srSettings(),
                    receipts: [[String: Any]] = [], schema: Any = 2) throws -> Data {
    try srJSON(["schema": schema, "preferences": inner, "settings": settings, "settingsMutations": receipts])
}
private func srReceipt(_ id: String, _ action: String, _ value: Any) -> [String: Any] {
    ["id": id, "change": ["action": action, action == "pause" ? "pause" : "enabled": value]]
}
private func srDecode(_ bytes: Data) throws -> SchedulePreferenceRecord {
    try SchedulePreferenceRecordCodec.decodeV2(bytes, principal: owner, storeScope: storeScope)
}
private func srRefuses(_ body: () throws -> Void) throws {
    do { try body() }
    catch let reason as PreferenceRefusal {
        try require(reason == .malformed || reason == .limit, "wrong closed refusal: \(reason)")
        return
    }
    throw CheckFailure(message: "invalid input accepted")
}
private func srRecord(_ settings: ScheduleSettings = ScheduleSettings(),
                      inner: PreferenceRecord? = nil,
                      receipts: [ScheduleSettingsMutationReceipt] = []) -> SchedulePreferenceRecord {
    SchedulePreferenceRecord(preferences: inner ?? PreferenceRecord(principal: owner, storeScope: storeScope, revision: 0),
                             settings: settings, settingsMutations: receipts)
}

@MainActor func scheduleRecordChecks(_ c: Checks) {
    c.run("schedule literal fixture and independent encoder controls", setup: true) {
        let directory = URL(fileURLWithPath: "Fixtures/SchedulePreferences")
        try require(try Data(contentsOf: directory.appendingPathComponent("v1-default.json")) == Data(srV1.utf8), "v1 literal drift")
        try require(try Data(contentsOf: directory.appendingPathComponent("v2-default.json")) == Data(srV2.utf8), "v2 literal drift")
        try require(try srWire() == Data(srV2.utf8), "test-owned encoder differs from literal")
        let old = try PreferenceRecordCodec.decode(Data(srV1.utf8), principal: owner, storeScope: storeScope)
        try require(try PreferenceRecordCodec.encode(old) == Data(srV1.utf8), "old codec setup")
        try require(SchedulePreferenceRecord.maximumBytes == 4_194_304 &&
                    PreferenceRecord.maximumBytes == 1_048_576 && SchedulePreferenceRecord.maximumCombinedMutations == 128, "wire limits")
    }
    c.run("schedule inert declarations confer no ordinary session or store authority", setup: true) {
        let choices = ScheduleSettings()
        try require(choices.dailyChecks && choices.notifications && !choices.automaticUpdates && choices.pause == nil, "defaults")
        let declaration = SchedulePauseChoice(resumeUTC: -1, displayZone: "not a zone")
        try require(declaration.resumeUTC == -1, "SPI constructor pretends to validate")
        let ordinary = PreferenceSession()
        try require(ordinary.acceptedRevision == nil && ordinary.blockedReason == .defaultComposition, "declaration created session authority")
        try require(RefusingPreferenceStore().read(maximumBytes: 4_194_304) == .unavailable, "declaration created store")
    }
    c.run("schedule default encode equals independent literal") {
        try require(try SchedulePreferenceRecordCodec.encode(srRecord()) == Data(srV2.utf8), "default exact wire")
    }
    c.run("schedule default decode fields and canonical roundtrip") {
        let decoded = try srDecode(Data(srV2.utf8))
        try require(decoded == srRecord(), "decoded default values")
        try require(try SchedulePreferenceRecordCodec.encode(decoded) == Data(srV2.utf8), "default roundtrip")
    }
    c.run("schedule strict v1 migration proposes exact literal without acknowledgement") {
        let bytes = Data(srV1.utf8); let snapshot = bytes
        let proposal = try SchedulePreferenceRecordCodec.proposeV1Migration(bytes, principal: owner, storeScope: storeScope)
        try require(proposal.originalV1Bytes == snapshot && bytes == snapshot, "original bytes changed")
        try require(proposal.proposedV2Bytes == Data(srV2.utf8) && proposal.record == srRecord(), "migration defaults or bytes")
        let again = try SchedulePreferenceRecordCodec.proposeV1Migration(bytes, principal: owner, storeScope: storeScope)
        try require(again == proposal, "migration is nondeterministic")
        try require(PreferenceSession().acceptedRevision == nil, "migration acknowledged storage")
    }
    for daily in [false, true] { for notify in [false, true] { for automatic in [false, true] {
        c.run("schedule independent toggle choices \(daily)/\(notify)/\(automatic)") {
            let expected = try srWire(settings: srSettings(daily, notify, automatic))
            let value = srRecord(ScheduleSettings(dailyChecks: daily, notifications: notify, automaticUpdates: automatic))
            try require(try SchedulePreferenceRecordCodec.encode(value) == expected, "toggle wire")
            try require(try srDecode(expected) == value, "toggle independence")
        }
    } } }
    for deadline in [Int64(0), 1, 99, 100, 101, Int64.max] {
        for zone in ["UTC", "Europe/Isle_of_Man", "Etc/GMT+12", "Not_A_Real_Zone", "A/B/C", "-", "+", "_", "0", "A-B_C+1", String(repeating: "Z", count: 128)] {
            c.run("schedule retains absolute pause \(deadline) zone \(zone)") {
                let pause = SchedulePauseChoice(resumeUTC: deadline, displayZone: zone)
                let value = srRecord(ScheduleSettings(pause: pause))
                let expected = try srWire(settings: srSettings(true, true, false, srPause(deadline, zone)))
                try require(try SchedulePreferenceRecordCodec.encode(value) == expected, "pause exact encode")
                let decoded = try srDecode(expected)
                try require(decoded == value && !decoded.settings.automaticUpdates, "expiry/zone changed opt-in or instant")
            }
        }
    }
    for revision in [UInt64(0), 9_007_199_254_740_993, UInt64.max] {
        c.run("schedule migration preserves complete old history revision \(revision)") {
            let oldBytes = fixtureBytes(revision: revision, exclusions: [PreferenceAppKey(release)], skips: [release],
                mutations: [("old-exclude", .exclusion(PreferenceAppKey(release), true)), ("old-skip", .skip(release)), ("old-undo", .undo(release))])
            let original = oldBytes
            let old = try PreferenceRecordCodec.decode(oldBytes, principal: owner, storeScope: storeScope)
            let migration = try SchedulePreferenceRecordCodec.proposeV1Migration(oldBytes, principal: owner, storeScope: storeScope)
            try require(migration.originalV1Bytes == original && oldBytes == original && migration.record.preferences == old, "old values/history changed")
            try require(try PreferenceRecordCodec.encode(migration.record.preferences) == original, "v1 revision precision or bytes lost")
            try require(migration.proposedV2Bytes == (try srWire(String(decoding: original, as: UTF8.self))), "outer migration bytes")
            try require(try srDecode(migration.proposedV2Bytes) == migration.record, "migration roundtrip")
        }
    }
    let changes: [(ScheduleSettingsChange, String, Any)] = [
        (.dailyChecks(false), "dailyChecks", false), (.dailyChecks(true), "dailyChecks", true),
        (.notifications(false), "notifications", false), (.notifications(true), "notifications", true),
        (.automaticUpdates(false), "automaticUpdates", false), (.automaticUpdates(true), "automaticUpdates", true),
        (.pause(nil), "pause", NSNull()),
        (.pause(SchedulePauseChoice(resumeUTC: 0, displayZone: "UTC")), "pause", srPause(0, "UTC"))]
    c.run("schedule ordered closed receipt variants and cancel retained without executing") {
        let receipts = changes.enumerated().map { ScheduleSettingsMutationReceipt(id: "settings-\($0.offset)", change: $0.element.0) }
        let wire = changes.enumerated().map { srReceipt("settings-\($0.offset)", $0.element.1, $0.element.2) }
        let value = srRecord(receipts: receipts); let expected = try srWire(receipts: wire)
        try require(try SchedulePreferenceRecordCodec.encode(value) == expected, "closed receipt encode/order")
        let decoded = try srDecode(expected)
        try require(decoded == value && decoded.settings == ScheduleSettings(), "receipts executed or reordered")
        try require(try SchedulePreferenceRecordCodec.encode(decoded) == expected, "receipt canonical roundtrip")
    }
    for (oldCount, newCount) in [(0, 128), (128, 0), (64, 64), (127, 1), (0, 129), (128, 1), (64, 65)] {
        c.run("schedule combined receipt count \(oldCount)+\(newCount)") {
            let innerBytes = fixtureBytes(mutations: (0..<oldCount).map { ("old-\($0)", .skip(release)) })
            let inner = try PreferenceRecordCodec.decode(innerBytes, principal: owner, storeScope: storeScope)
            let receipts = (0..<newCount).map { ScheduleSettingsMutationReceipt(id: "new-\($0)", change: .notifications(false)) }
            let expected = try srWire(String(decoding: innerBytes, as: UTF8.self), receipts: (0..<newCount).map { srReceipt("new-\($0)", "notifications", false) })
            let value = srRecord(inner: inner, receipts: receipts)
            if oldCount + newCount <= 128 {
                try require(try SchedulePreferenceRecordCodec.encode(value) == expected, "combined maximum encode")
                try require(try srDecode(expected) == value, "combined maximum decode")
                let migration = try SchedulePreferenceRecordCodec.proposeV1Migration(innerBytes, principal: owner, storeScope: storeScope)
                try require(migration.record.preferences.mutations == inner.mutations && migration.record.settingsMutations.isEmpty, "migration evicted receipts")
            } else {
                try srRefuses { _ = try srDecode(expected) }
                try srRefuses { _ = try SchedulePreferenceRecordCodec.encode(value) }
            }
        }
    }
    for id in ["a", String(repeating: "x", count: 256), String(repeating: "é", count: 128), "receipt/with spaces"] {
        c.run("schedule receipt text valid UTF8 bound \(id.utf8.count)") {
            let value = srRecord(receipts: [ScheduleSettingsMutationReceipt(id: id, change: .pause(nil))])
            let expected = try srWire(receipts: [srReceipt(id, "pause", NSNull())])
            try require(try SchedulePreferenceRecordCodec.encode(value) == expected, "valid ID encoding")
            try require(try srDecode(expected) == value, "valid ID decode")
        }
    }
    for id in ["", "a\0b", "a\nb", "a\u{7f}b", String(repeating: "x", count: 257), String(repeating: "é", count: 129)] {
        c.run("schedule receipt invalid UTF8 bound/control \(id.utf8.count)") {
            try srRefuses { _ = try srDecode(srWire(receipts: [srReceipt(id, "dailyChecks", true)])) }
            try srRefuses { _ = try SchedulePreferenceRecordCodec.encode(srRecord(receipts: [ScheduleSettingsMutationReceipt(id: id, change: .dailyChecks(true))])) }
        }
    }
    c.run("schedule duplicate new and cross-history IDs refuse without eviction") {
        let oldBytes = fixtureBytes(mutations: [("same", .skip(release))])
        let inner = try PreferenceRecordCodec.decode(oldBytes, principal: owner, storeScope: storeScope)
        let repeated = ScheduleSettingsMutationReceipt(id: "same", change: .pause(nil))
        for (bytes, value) in [
            (try srWire(receipts: [srReceipt("same", "pause", NSNull()), srReceipt("same", "pause", NSNull())]), srRecord(receipts: [repeated, repeated])),
            (try srWire(String(decoding: oldBytes, as: UTF8.self), receipts: [srReceipt("same", "pause", NSNull())]), srRecord(inner: inner, receipts: [repeated]))] {
            try srRefuses { _ = try srDecode(bytes) }
            try srRefuses { _ = try SchedulePreferenceRecordCodec.encode(value) }
        }
    }
    var invalid: [(String, Data)] = [
        ("empty", Data()), ("invalid UTF8", Data([0xff])), ("truncated", Data("{".utf8)),
        ("outer at ceiling malformed", Data(repeating: 32, count: 4_194_304)),
        ("outer beyond ceiling", Data(repeating: 32, count: 4_194_305)),
        ("BOM", Data([0xef, 0xbb, 0xbf]) + Data(srV2.utf8)),
        ("trailing whitespace", Data((srV2 + "\n").utf8)),
        ("root duplicate", Data(srV2.replacingOccurrences(of: "\"schema\":2", with: "\"schema\":2,\"schema\":2").utf8)),
        ("root unknown", Data(srV2.replacingOccurrences(of: "\"schema\":2", with: "\"schema\":2,\"unknown\":null").utf8)),
        ("noncanonical order", Data(srV2.replacingOccurrences(of: "\"automaticUpdates\":false,\"dailyChecks\":true", with: "\"dailyChecks\":true,\"automaticUpdates\":false").utf8)),
        ("noncanonical escaped name", Data(srV2.replacingOccurrences(of: "dailyChecks", with: "daily\\u0043hecks").utf8)),
        ("noncanonical escaped inner text", Data(srV2.replacingOccurrences(of: "synthetic-store", with: "synthetic\\u002dstore").utf8)),
        ("settings duplicate", Data(srV2.replacingOccurrences(of: "\"dailyChecks\":true", with: "\"dailyChecks\":true,\"dailyChecks\":true").utf8))]
    for schema in ([0, 1, 3, "2", true, NSNull(), 2.5] as [Any]) { invalid.append(("schema \(schema)", try! srWire(schema: schema))) }
    invalid.append(("schema decimal", Data(srV2.replacingOccurrences(of: "\"schema\":2", with: "\"schema\":2.0").utf8)))
    invalid.append(("schema exponent", Data(srV2.replacingOccurrences(of: "\"schema\":2", with: "\"schema\":2e0").utf8)))
    for field in ["preferences", "settings", "settingsMutations", "schema"] {
        var object = try! JSONSerialization.jsonObject(with: Data(srV2.utf8)) as! [String: Any]
        object.removeValue(forKey: field); invalid.append(("missing root \(field)", try! srJSON(object)))
        for wrong in ([NSNull(), [], [:], false, "wrong", 0] as [Any]) {
            object = try! JSONSerialization.jsonObject(with: Data(srV2.utf8)) as! [String: Any]
            if field == "settingsMutations", let array = wrong as? [Any], array.isEmpty { continue }
            object[field] = wrong; invalid.append(("wrong root \(field) \(wrong)", try! srJSON(object)))
        }
    }
    for field in ["dailyChecks", "notifications", "automaticUpdates", "pause"] {
        var settings = srSettings(); settings.removeValue(forKey: field)
        invalid.append(("missing settings \(field)", try! srWire(settings: settings)))
        for wrong in (["true", 1, [], [:], NSNull()] as [Any]) {
            if field == "pause", wrong is NSNull { continue }
            settings = srSettings(); settings[field] = wrong
            invalid.append(("wrong settings \(field) \(wrong)", try! srWire(settings: settings)))
        }
    }
    var settingsUnknown = srSettings(); settingsUnknown["helperApproved"] = true
    invalid.append(("unknown settings authority", try! srWire(settings: settingsUnknown)))
    for zone in ["", "/UTC", "UTC/", "A//B", "A.B", "A/../B", "A B", "A\nB", "A\0B", "Éurope/Paris", "A\\B", String(repeating: "a", count: 129)] {
        invalid.append(("invalid zone \(zone)", try! srWire(settings: srSettings(true, true, false, srPause(1, zone)))))
        c.run("schedule encode rejects invalid zone \(zone)") {
            try srRefuses { _ = try SchedulePreferenceRecordCodec.encode(srRecord(ScheduleSettings(pause: SchedulePauseChoice(resumeUTC: 1, displayZone: zone)))) }
        }
    }
    for utc in ([-1, "1", true, NSNull(), [], 1.5] as [Any]) {
        invalid.append(("invalid UTC \(utc)", try! srWire(settings: srSettings(true, true, false, ["resumeUTC": utc, "displayZone": "UTC"]))))
    }
    for wire in [#"{"displayZone":"UTC","resumeUTC":9223372036854775808}"#,
                 #"{"displayZone":"UTC","resumeUTC":1.0}"#,
                 #"{"displayZone":"UTC","resumeUTC":1e0}"#,
                 #"{"displayZone":"UTC","resumeUTC":1,"resumeUTC":1}"#,
                 #"{"displayZone":"UTC","resumeUTC":1,"trustedUTC":true}"#,
                 #"{"resumeUTC":1}"#, #"{"displayZone":"UTC"}"#] {
        invalid.append(("invalid pause object \(wire)", Data(srV2.replacingOccurrences(of: "\"pause\":null", with: "\"pause\":" + wire).utf8)))
    }
    c.run("schedule encode rejects negative pause and invalid schema declarations") {
        try srRefuses { _ = try SchedulePreferenceRecordCodec.encode(srRecord(ScheduleSettings(pause: SchedulePauseChoice(resumeUTC: -1, displayZone: "UTC")))) }
        for schema in [UInt64(0), 1, 3, UInt64.max] {
            let value = SchedulePreferenceRecord(schema: schema, preferences: srRecord().preferences, settings: ScheduleSettings())
            try srRefuses { _ = try SchedulePreferenceRecordCodec.encode(value) }
        }
    }
    let badChanges: [[String: Any]] = [[:], ["action": "unknown", "enabled": true], ["action": "skip", "enabled": true],
        ["action": "dailyChecks"], ["action": "dailyChecks", "enabled": 1], ["action": "dailyChecks", "enabled": "true"],
        ["action": "dailyChecks", "enabled": true, "pause": NSNull()], ["action": "dailyChecks", "enabled": true, "extra": false],
        ["action": "pause"], ["action": "pause", "pause": NSNull(), "enabled": true], ["action": "pause", "pause": false],
        ["action": "pause", "pause": srPause(-1, "UTC")], ["action": "pause", "pause": srPause(1, "Bad.Zone")]]
    for (index, change) in badChanges.enumerated() {
        invalid.append(("closed change \(index)", try! srWire(receipts: [["id": "id", "change": change]])))
    }
    for receipt in ([["change": ["action": "pause", "pause": NSNull()]], ["id": "id"],
        ["id": true, "change": ["action": "pause", "pause": NSNull()]], ["id": "id", "change": "{}"],
        ["id": "id", "change": ["action": "pause", "pause": NSNull()], "operation": "{}"]] as [[String: Any]]) {
        invalid.append(("malformed receipt \(receipt)", try! srWire(receipts: [receipt])))
    }
    let validReceiptWire = String(decoding: try! srWire(receipts: [srReceipt("id", "notifications", true)]), as: UTF8.self)
    invalid.append(("duplicate receipt id key", Data(validReceiptWire.replacingOccurrences(of: "\"id\":\"id\"", with: "\"id\":\"id\",\"id\":\"id\"").utf8)))
    invalid.append(("duplicate change action", Data(validReceiptWire.replacingOccurrences(of: "\"action\":\"notifications\"", with: "\"action\":\"notifications\",\"action\":\"notifications\"").utf8)))
    for (name, bytes) in invalid {
        c.run("schedule rejects \(name)") { try srRefuses { _ = try srDecode(bytes) } }
    }
    var badInner: [(String, Data)] = [("empty", Data()), ("invalid UTF8", Data([0xff])), ("truncated", Data("{".utf8)),
        ("v2 as v1", Data(srV2.utf8)), ("foreign principal", fixtureBytes(principal: "foreign")),
        ("foreign scope", fixtureBytes(scope: "foreign")), ("oversized", Data(repeating: 32, count: 1_048_577)),
        ("whitespace", Data((srV1 + " ").utf8)),
        ("unknown", Data(srV1.replacingOccurrences(of: "\"schema\":1", with: "\"schema\":1,\"unknown\":null").utf8)),
        ("duplicate", Data(srV1.replacingOccurrences(of: "\"schema\":1", with: "\"schema\":1,\"schema\":1").utf8)),
        ("noncanonical operation", fixtureBytes(mutations: [("id", .skip(release))]))]
    badInner[badInner.count - 1].1 = canonical(["exclusions": [], "mutations": [["id": "id", "operation": operation(.skip(release)) + " "]],
        "principal": owner.value, "revision": 0, "schema": 1, "skips": [], "storeScope": storeScope])
    for mutation in ["0.0", "0e0", "false", "-1", "18446744073709551616", "\"0\""] {
        badInner.append(("numeric revision \(mutation)", Data(srV1.replacingOccurrences(of: "\"revision\":0", with: "\"revision\":" + mutation).utf8)))
    }
    for (name, bytes) in badInner {
        c.run("schedule rejects nested old and migration \(name)") {
            try srRefuses { _ = try SchedulePreferenceRecordCodec.proposeV1Migration(bytes, principal: owner, storeScope: storeScope) }
            try srRefuses { _ = try srDecode(srWire(String(decoding: bytes, as: UTF8.self))) }
        }
    }
    for (principal, scope) in [(SchedulingPrincipal("foreign"), storeScope), (owner, "foreign"), (SchedulingPrincipal(""), storeScope), (owner, "")] {
        c.run("schedule binds caller principal and scope \(principal.value)/\(scope)") {
            try srRefuses { _ = try SchedulePreferenceRecordCodec.decodeV2(Data(srV2.utf8), principal: principal, storeScope: scope) }
            try srRefuses { _ = try SchedulePreferenceRecordCodec.proposeV1Migration(Data(srV1.utf8), principal: principal, storeScope: scope) }
        }
    }
    c.run("schedule encode reuses strict v1 validation on unvalidated declarations") {
        let invalidInner = [
            PreferenceRecord(schema: 2, principal: owner, storeScope: storeScope, revision: 0),
            PreferenceRecord(principal: SchedulingPrincipal(""), storeScope: storeScope, revision: 0),
            PreferenceRecord(principal: owner, storeScope: "", revision: 0),
            PreferenceRecord(principal: owner, storeScope: storeScope, revision: 0,
                mutations: [PreferenceMutationReceipt(id: "bad", operation: "{}")]),
            PreferenceRecord(principal: owner, storeScope: storeScope, revision: 0,
                mutations: [PreferenceMutationReceipt(id: "same", operation: operation(.skip(release))),
                            PreferenceMutationReceipt(id: "same", operation: operation(.undo(release)))])]
        for inner in invalidInner { try srRefuses { _ = try SchedulePreferenceRecordCodec.encode(srRecord(inner: inner)) } }
    }
    c.run("schedule pause cancellation is retained as null without changing prior choices") {
        let innerBytes = fixtureBytes(revision: 8, exclusions: [PreferenceAppKey(release)], skips: [release])
        let inner = try PreferenceRecordCodec.decode(innerBytes, principal: owner, storeScope: storeScope)
        let settings = ScheduleSettings(dailyChecks: false, notifications: false, automaticUpdates: true)
        let receipt = ScheduleSettingsMutationReceipt(id: "cancel", change: .pause(nil))
        let value = srRecord(settings, inner: inner, receipts: [receipt])
        let expected = try srWire(String(decoding: innerBytes, as: UTF8.self), settings: srSettings(false, false, true),
                                  receipts: [srReceipt("cancel", "pause", NSNull())])
        try require(try SchedulePreferenceRecordCodec.encode(value) == expected, "cancel encoding")
        try require(try srDecode(expected) == value, "cancel changed consent/exclusions/skips")
    }
    c.run("schedule preserves maximum canonical inner byte record") {
        let innerBytes = try exactByteFixture(1_048_576)
        let proposal = try SchedulePreferenceRecordCodec.proposeV1Migration(innerBytes, principal: owner, storeScope: storeScope)
        let expected = try srWire(String(decoding: innerBytes, as: UTF8.self))
        try require(proposal.originalV1Bytes == innerBytes && proposal.proposedV2Bytes == expected, "maximum inner migrated bytes")
        try require(expected.count <= 4_194_304 && expected.count > innerBytes.count, "transparent JSON-string envelope bounds")
        try require(try PreferenceRecordCodec.encode(srDecode(expected).preferences) == innerBytes, "maximum inner roundtrip")
    }
}
