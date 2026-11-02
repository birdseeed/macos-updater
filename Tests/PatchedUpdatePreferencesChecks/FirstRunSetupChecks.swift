import Foundation
import PatchedScheduling
@_spi(Testing) import PatchedUpdatePreferences

// Expectations are independently constructed wire objects, never candidate codec output.
private func frDraft(_ mode: String = "system", _ host: String = "", _ port: String = "") -> [String: Any] {
    ["mode": mode, "host": host, "port": port]
}
private func frChoices(_ daily: Bool = true, _ notify: Bool = true, _ reports: Bool = true,
                       _ draft: [String: Any] = frDraft()) -> [String: Any] {
    ["dailyChecks": daily, "notifications": notify, "failureReports": reports, "networkDraft": draft]
}
private func frSetup(_ reports: Bool = true, _ completed: Bool = false,
                     _ draft: [String: Any] = frDraft()) -> [String: Any] {
    ["failureReports": reports, "completed": completed, "networkDraft": draft]
}
private func frReceipt(_ id: String, _ choices: [String: Any] = frChoices(), _ complete: Bool = false) -> [String: Any] {
    ["id": id, "choices": choices, "complete": complete]
}
private func frScheduled(_ inner: Data = fixtureBytes(), daily: Bool = true, notify: Bool = true,
                         automatic: Bool = false, pause: Any = NSNull(), receipts: [[String: Any]] = []) -> Data {
    canonical(["schema": 2, "preferences": String(decoding: inner, as: UTF8.self),
        "settings": ["dailyChecks": daily, "notifications": notify, "automaticUpdates": automatic, "pause": pause],
        "settingsMutations": receipts])
}
private func frWire(_ scheduled: Data = frScheduled(), setup: [String: Any] = frSetup(),
                    receipts: [[String: Any]] = []) -> Data {
    canonical(["schema": 3, "scheduled": String(decoding: scheduled, as: UTF8.self),
        "setup": setup, "setupMutations": receipts])
}
private func frRefused(_ result: PreferenceEditResult) -> Bool {
    if case .refused = result { return true }; return false
}
@MainActor private func frSave(_ value: PreferenceSession, _ choices: FirstRunChoices = FirstRunChoices(),
                               complete: Bool = false, id: String = "setup-1", revision: UInt64 = 0,
                               gen: String = generation) -> PreferenceEditResult {
    value.saveFirstRunChoices(choices, complete: complete, mutationID: id, expectedRevision: revision, generation: gen)
}
@MainActor private func frLoaded(_ bytes: Data = frWire(), revision: UInt64 = 0) throws -> (PreferenceSession, MemoryStore) {
    let store = MemoryStore(bytes: bytes); let value = session(store)
    try require(value.reload(generation: generation) == .accepted(revision: revision), "strict schema3 source reload")
    return (value, store)
}
@MainActor private final class FRUnavailableStore: PreferenceStore {
    var reads = 0; var writes = 0
    func read(maximumBytes: Int) -> PreferenceRead { reads += 1; return .unavailable }
    func compareAndSwap(expected: Data?, proposed: Data, maximumBytes: Int) -> PreferenceCommit {
        writes += 1; return .notCommitted
    }
}

@MainActor func firstRunSetupChecks(_ c: Checks) {
    c.run("first run inert defaults and unchanged old codec controls", setup: true) {
        let choices = FirstRunChoices()
        try require(choices.dailyChecks && choices.notifications && choices.failureReports && choices.networkDraft == FirstRunNetworkDraft(), "choice defaults")
        try require(FirstRunSetupState() == FirstRunSetupState(failureReports: true, completed: false, networkDraft: FirstRunNetworkDraft(mode: .system)), "setup defaults")
        try require(try PreferenceRecordCodec.encode(PreferenceRecord(principal: owner, storeScope: storeScope, revision: 0)) == fixtureBytes(), "schema1 changed")
        let v2 = SchedulePreferenceRecord(preferences: PreferenceRecord(principal: owner, storeScope: storeScope, revision: 0), settings: ScheduleSettings())
        try require(try SchedulePreferenceRecordCodec.encode(v2) == frScheduled(), "schema2 changed")
        try require(frWire() == Data(firstRunLiteral.utf8), "independent literal does not match independent fixture builder")
    }
    c.run("first run strict literal codec and independently declared record") {
        let record = try FirstRunPreferenceRecordCodec.decodeV3(Data(firstRunLiteral.utf8), principal: owner, storeScope: storeScope)
        try require(record.schema == 3 && record.setup == FirstRunSetupState() && record.setupMutations.isEmpty, "literal setup fields")
        try require(record.scheduled.preferences.revision == 0 && record.scheduled.settings == ScheduleSettings(), "literal nested fields")
        let declared = FirstRunPreferenceRecord(scheduled: SchedulePreferenceRecord(preferences: PreferenceRecord(principal: owner, storeScope: storeScope, revision: 0), settings: ScheduleSettings()), setup: FirstRunSetupState())
        try require(try FirstRunPreferenceRecordCodec.encode(declared) == Data(firstRunLiteral.utf8), "canonical encode")
    }
    c.run("first run encoder rejects invalid declarations and shared histories") {
        let preferences = PreferenceRecord(principal: owner, storeScope: storeScope, revision: 0)
        let scheduled = SchedulePreferenceRecord(preferences: preferences, settings: ScheduleSettings())
        let invalid: [FirstRunPreferenceRecord] = [
            FirstRunPreferenceRecord(schema: 2, scheduled: scheduled, setup: FirstRunSetupState()),
            FirstRunPreferenceRecord(scheduled: scheduled, setup: FirstRunSetupState(networkDraft: FirstRunNetworkDraft(host: "unexpected"))),
            FirstRunPreferenceRecord(scheduled: scheduled, setup: FirstRunSetupState(), setupMutations: [FirstRunSetupMutationReceipt(id: "", choices: FirstRunChoices(), complete: false)]),
            FirstRunPreferenceRecord(scheduled: scheduled, setup: FirstRunSetupState(), setupMutations: [FirstRunSetupMutationReceipt(id: "a", choices: FirstRunChoices(), complete: false), FirstRunSetupMutationReceipt(id: "a", choices: FirstRunChoices(), complete: false)]),
            FirstRunPreferenceRecord(scheduled: scheduled, setup: FirstRunSetupState(), setupMutations: (0..<129).map { FirstRunSetupMutationReceipt(id: "f-\($0)", choices: FirstRunChoices(), complete: false) }),
            FirstRunPreferenceRecord(scheduled: SchedulePreferenceRecord(preferences: preferences, settings: ScheduleSettings(), settingsMutations: [ScheduleSettingsMutationReceipt(id: "shared", change: .notifications(false))]), setup: FirstRunSetupState(), setupMutations: [FirstRunSetupMutationReceipt(id: "shared", choices: FirstRunChoices(), complete: false)]),
            FirstRunPreferenceRecord(scheduled: scheduled, setup: FirstRunSetupState(), setupMutations: [FirstRunSetupMutationReceipt(id: "bad-choice", choices: FirstRunChoices(networkDraft: FirstRunNetworkDraft(mode: .direct, port: "1")), complete: false)])
        ]
        for host in ["user:secret@proxy.invalid", "https://proxy.invalid"] {
            let invalidHost = FirstRunPreferenceRecord(scheduled: scheduled, setup: FirstRunSetupState(networkDraft: FirstRunNetworkDraft(mode: .manualHTTP, host: host)))
            do { _ = try FirstRunPreferenceRecordCodec.encode(invalidHost) }
            catch { continue }
            throw CheckFailure(message: "userinfo or URI host retained by encoder")
        }
        for value in invalid {
            do { _ = try FirstRunPreferenceRecordCodec.encode(value) }
            catch { continue }
            throw CheckFailure(message: "invalid declaration encoded")
        }
    }
    c.run("first run no getter constructor or reload implicitly migrates accepted legacy choices") {
        for bytes in [fixtureBytes(), frScheduled(), frWire()] {
            let store = MemoryStore(bytes: bytes); let value = session(store)
            try require(store.reads == 0 && store.writes == 0 && value.firstRunSetup == nil, "constructor performed implicit work")
            try require(value.reload(generation: generation) == .accepted(revision: 0), "explicit load")
            let reads = store.reads
            for _ in 0..<3 { _ = value.firstRunSetup; _ = value.scheduleSettings; _ = value.projection([]) }
            try require(store.reads == reads && store.writes == 0 && store.bytes == bytes, "getter or reload migrated")
            try require(value.firstRunSetup == (bytes == frWire() ? FirstRunSetupState() : nil), "legacy synthesized accepted setup")
        }
    }
    for legacy in [true, false] {
        c.run("first run one CAS migrates \(legacy ? "v1" : "v2") preserving histories pause and automatic declaration") {
            let old = fixtureBytes(revision: 9, exclusions: [PreferenceAppKey(release)], skips: [release], mutations: [("old", .skip(release))])
            let pause: [String: Any] = ["resumeUTC": 200, "displayZone": "Europe/Isle_of_Man"]
            let settingsReceipts: [[String: Any]] = [["id": "notify-old", "change": ["action": "notifications", "enabled": false]]]
            let before = legacy ? old : frScheduled(old, daily: false, notify: false, automatic: true, pause: pause, receipts: settingsReceipts)
            let store = MemoryStore(bytes: before); let value = session(store)
            try require(value.reload(generation: generation) == .accepted(revision: 9) && value.firstRunSetup == nil, "legacy loaded without setup")
            let draft = FirstRunNetworkDraft(mode: .manualHTTP, host: "proxy.invalid", port: "abc")
            let choices = FirstRunChoices(dailyChecks: false, notifications: true, failureReports: false, networkDraft: draft)
            try require(frSave(value, choices, complete: true, revision: 9) == .accepted(revision: 10), "joint migration/save")
            let inner = fixtureBytes(revision: 10, exclusions: [PreferenceAppKey(release)], skips: [release], mutations: [("old", .skip(release))])
            let scheduled = frScheduled(inner, daily: false, notify: true, automatic: !legacy, pause: legacy ? NSNull() : pause, receipts: legacy ? [] : settingsReceipts)
            let expected = frWire(scheduled, setup: frSetup(false, true, frDraft("manualHTTP", "proxy.invalid", "abc")), receipts: [frReceipt("setup-1", frChoices(false, true, false, frDraft("manualHTTP", "proxy.invalid", "abc")), true)])
            try require(store.bytes == expected && store.writes == 1, "migration discarded fields or was more than one CAS")
            try require(value.firstRunSetup == FirstRunSetupState(failureReports: false, completed: true, networkDraft: draft), "accepted setup")
            let next = session(store); try require(next.reload(generation: generation) == .accepted(revision: 10), "restart")
            try require(next.firstRunSetup == value.firstRunSetup && next.scheduleSettings == value.scheduleSettings, "restart lost joint choices")
        }
    }
    c.run("first run completion monotonic opt out retained and replay never restores stale choices") {
        let (value, store) = try frLoaded()
        let optedOut = FirstRunChoices(dailyChecks: false, notifications: false, failureReports: false)
        try require(frSave(value, optedOut, complete: true) == .accepted(revision: 1), "complete opt out")
        let direct = FirstRunNetworkDraft(mode: .direct)
        let later = FirstRunChoices(dailyChecks: true, notifications: false, failureReports: false, networkDraft: direct)
        try require(frSave(value, later, id: "later", revision: 1) == .accepted(revision: 2), "later partial save")
        let expected = frWire(frScheduled(fixtureBytes(revision: 2), notify: false), setup: frSetup(false, true, frDraft("direct")), receipts: [frReceipt("setup-1", frChoices(false, false, false), true), frReceipt("later", frChoices(true, false, false, frDraft("direct")))])
        try require(store.bytes == expected && value.firstRunSetup == FirstRunSetupState(failureReports: false, completed: true, networkDraft: direct), "completion or opt out reset")
        let reads = store.reads; let writes = store.writes
        try require(frSave(value, optedOut, complete: true, revision: 0) == .replayed(revision: 2), "replay uses current revision")
        try require(frSave(value, optedOut, revision: 2) == .refused(.conflict), "complete flag mismatch replayed")
        try require(frSave(value, FirstRunChoices(), complete: true, revision: 2) == .refused(.conflict), "different choices replayed")
        try require(frSave(value, id: "new", revision: 1) == .refused(.conflict), "new stale ID accepted")
        try require(store.reads == reads && store.writes == writes && store.bytes == expected, "replay/conflict performed I/O or restored old fields")
    }
    c.run("first run existing edit settings edit and migration preserve setup and all histories") {
        let receipts = [frReceipt("setup-old", frChoices(false, false, false), true)]
        let before = frWire(frScheduled(notify: false), setup: frSetup(false, true), receipts: receipts)
        let (value, store) = try frLoaded(before)
        try require(edit(value, .skip(release), id: "skip") == .accepted(revision: 1), "old edit in schema3")
        try require(value.editScheduleSettings(.dailyChecks(false), mutationID: "daily", expectedRevision: 1, generation: generation) == .accepted(revision: 2), "settings edit in schema3")
        let inner = fixtureBytes(revision: 2, skips: [release], mutations: [("skip", .skip(release))])
        let scheduled = frScheduled(inner, daily: false, notify: false, receipts: [["id": "daily", "change": ["action": "dailyChecks", "enabled": false]]])
        let expected = frWire(scheduled, setup: frSetup(false, true), receipts: receipts)
        try require(store.bytes == expected && value.firstRunSetup == FirstRunSetupState(failureReports: false, completed: true), "old operation discarded setup/history")
        let reads = store.reads; let writes = store.writes
        try require(value.migrateScheduleSettings(expectedRevision: 2, generation: generation) == .replayed(revision: 2), "schema3 migration replay")
        try require(frSave(value, FirstRunChoices(dailyChecks: false, notifications: false, failureReports: false), complete: true, id: "setup-old", revision: 0) == .replayed(revision: 2), "setup history lost after old edits")
        try require(store.reads == reads && store.writes == writes && store.bytes == expected, "history replay wrote")
    }
    for origin in ["preference", "settings", "setup"] {
        c.run("first run shared mutation namespace from \(origin) rejects other kinds with zero I/O") {
            let old = origin == "preference" ? fixtureBytes(mutations: [("shared", .skip(release))]) : fixtureBytes()
            let settings: [[String: Any]] = origin == "settings" ? [["id": "shared", "change": ["action": "notifications", "enabled": false]]] : []
            let setup = origin == "setup" ? [frReceipt("shared")] : []
            let bytes = frWire(frScheduled(old, receipts: settings), receipts: setup); let (value, store) = try frLoaded(bytes)
            let reads = store.reads
            if origin != "setup" { try require(frSave(value, id: "shared") == .refused(.conflict), "setup reused other namespace") }
            if origin != "preference" { try require(edit(value, .skip(release), id: "shared") == .refused(.conflict), "old edit reused other namespace") }
            if origin != "settings" { try require(value.editScheduleSettings(.notifications(false), mutationID: "shared", expectedRevision: 0, generation: generation) == .refused(.conflict), "settings reused other namespace") }
            try require(store.reads == reads && store.writes == 0 && store.bytes == bytes, "namespace refusal I/O")
        }
    }
    for counts in [(128, 0, 0), (0, 128, 0), (0, 0, 128), (42, 43, 43)] {
        c.run("first run joint 128 receipt limit \(counts) retains exact replay and refuses all new edits") {
            let old = (0..<counts.0).map { ("p-\($0)", PreferenceChange.skip(release)) }
            let settings: [[String: Any]] = (0..<counts.1).map { ["id": "s-\($0)", "change": ["action": "notifications", "enabled": false]] }
            let setup = (0..<counts.2).map { frReceipt("f-\($0)") }
            let bytes = frWire(frScheduled(fixtureBytes(mutations: old), receipts: settings), receipts: setup)
            let (value, store) = try frLoaded(bytes); let reads = store.reads
            try require(frSave(value, id: "new") == .refused(.limit), "setup bypassed combined cap")
            try require(edit(value, .skip(release), id: "new-p") == .refused(.limit), "old edit bypassed setup cap")
            try require(value.editScheduleSettings(.notifications(false), mutationID: "new-s", expectedRevision: 0, generation: generation) == .refused(.limit), "settings bypassed setup cap")
            if counts.2 > 0 { try require(frSave(value, id: "f-0") == .replayed(revision: 0), "full history lost setup replay") }
            try require(store.reads == reads && store.writes == 0 && store.bytes == bytes, "cap trimmed history or performed I/O")
        }
    }
    c.run("first run 127 to128 receipt transition shares all kinds then refuses") {
        let before = frWire(frScheduled(fixtureBytes(mutations: (0..<63).map { ("p-\($0)", .skip(release)) }), receipts: (0..<63).map { ["id": "s-\($0)", "change": ["action": "notifications", "enabled": false]] }), receipts: [frReceipt("f-old")])
        let (value, store) = try frLoaded(before)
        try require(frSave(value, id: "last") == .accepted(revision: 1), "128th receipt refused")
        let record = try FirstRunPreferenceRecordCodec.decodeV3(store.bytes!, principal: owner, storeScope: storeScope)
        try require(record.setupMutations.count == 2 && record.scheduled.settingsMutations.count == 63 && record.scheduled.preferences.mutations.count == 63, "joint histories altered")
        let reads = store.reads; let writes = store.writes
        try require(frSave(value, id: "over", revision: 1) == .refused(.limit) && store.reads == reads && store.writes == writes, "129th receipt reached I/O")
    }
    c.run("first run UInt64 ceiling refuses before all store operations") {
        let bytes = frWire(frScheduled(fixtureBytes(revision: UInt64.max))); let (value, store) = try frLoaded(bytes, revision: UInt64.max)
        let reads = store.reads
        try require(frSave(value, revision: UInt64.max) == .refused(.revisionOverflow), "wrapped revision")
        try require(store.reads == reads && store.writes == 0 && store.bytes == bytes, "overflow I/O")
    }
    c.run("first run exact UTF8 generation checked before store I/O") {
        let actual = "caf\u{00e9}"; let alias = "cafe\u{0301}"
        let store = MemoryStore(bytes: frWire()); let value = session(store, gen: actual)
        try require(value.reload(generation: actual) == .accepted(revision: 0), "exact owner load")
        let reads = store.reads
        try require(frSave(value, gen: alias) == .refused(.staleGeneration), "equivalent generation accepted")
        try require(store.reads == reads && store.writes == 0, "wrong generation I/O")
        try require(frSave(value, gen: actual) == .accepted(revision: 1), "exact generation refused")
    }
    for field in ["principal", "scope"] {
        c.run("first run exact UTF8 \(field) binding") {
            let actual = "caf\u{00e9}"; let alias = "cafe\u{0301}"
            let bytes = frWire(frScheduled(fixtureBytes(principal: field == "principal" ? alias : owner.value, scope: field == "scope" ? alias : storeScope)))
            let store = MemoryStore(bytes: bytes); let value = session(store, principal: field == "principal" ? SchedulingPrincipal(actual) : owner, scope: field == "scope" ? actual : storeScope)
            try require(value.reload(generation: generation) == .refused(.malformed) && value.firstRunSetup == nil && store.writes == 0, "canonical equivalent owner loaded")
        }
    }
    for id in ["", "bad\nid", "bad\0id", String(repeating: "é", count: 129)] {
        c.run("first run invalid ID refuses with zero I/O \(id.utf8.count)") {
            let (value, store) = try frLoaded(); let reads = store.reads
            try require(frSave(value, id: id) == .refused(.identity) && store.reads == reads && store.writes == 0, "invalid mutation ID accepted or I/O")
        }
    }
    let invalidDrafts = [FirstRunNetworkDraft(host: "extra"), FirstRunNetworkDraft(mode: .direct, port: "1"),
        FirstRunNetworkDraft(mode: .manualHTTP, host: String(repeating: "é", count: 128)),
        FirstRunNetworkDraft(mode: .manualHTTP, port: "1234567"), FirstRunNetworkDraft(mode: .manualHTTP, host: "bad\nhost"),
        FirstRunNetworkDraft(mode: .manualHTTP, port: "\0"),
        FirstRunNetworkDraft(mode: .manualHTTP, host: "user:secret@proxy.invalid"),
        FirstRunNetworkDraft(mode: .manualHTTP, host: "https://proxy.invalid")]
    for (index, draft) in invalidDrafts.enumerated() {
        c.run("first run invalid draft refuses with zero I/O \(index)") {
            let (value, store) = try frLoaded(); let reads = store.reads
            try require(frRefused(frSave(value, FirstRunChoices(networkDraft: draft))), "invalid draft saved")
            try require(store.reads == reads && store.writes == 0 && store.bytes == frWire(), "invalid draft reached store")
        }
    }
    for draft in [FirstRunNetworkDraft(mode: .manualHTTP), FirstRunNetworkDraft(mode: .manualHTTP, host: String(repeating: "é", count: 127), port: "abcdef"), FirstRunNetworkDraft(mode: .manualHTTP, host: "proxy.invalid", port: "0")] {
        c.run("first run manual incomplete draft accepted without Network validation \(draft.host.utf8.count) \(draft.port)") {
            let (value, _) = try frLoaded()
            try require(frSave(value, FirstRunChoices(networkDraft: draft)) == .accepted(revision: 1), "draft treated as validated Network settings")
            try require(value.firstRunSetup?.networkDraft == draft, "draft lost")
        }
    }
    let good = String(decoding: frWire(), as: UTF8.self)
    var malformed: [Data] = [Data(), Data([0xff]), Data("{".utf8), Data((good + " ").utf8),
        Data(good.replacingOccurrences(of: "\"schema\":3", with: "\"schema\":3,\"schema\":3").utf8),
        Data(good.replacingOccurrences(of: "\"schema\":3", with: "\"schema\":3.0").utf8),
        Data(good.replacingOccurrences(of: "\"schema\":3", with: "\"schema\":true").utf8),
        Data(good.replacingOccurrences(of: "\"schema\":3", with: "\"schema\":4").utf8),
        Data(good.replacingOccurrences(of: "\"schema\":3", with: "\"extra\":true,\"schema\":3").utf8),
        Data(good.replacingOccurrences(of: "\"completed\":false,", with: "").utf8),
        Data(good.replacingOccurrences(of: "\"completed\":false", with: "\"completed\":0").utf8),
        Data(good.replacingOccurrences(of: "\"failureReports\":true", with: "\"failureReports\":true,\"failureReports\":true").utf8),
        Data(good.replacingOccurrences(of: "\"failureReports\":true", with: "\"failureReports\":true,\"coverageSharing\":true").utf8),
        Data(good.replacingOccurrences(of: "\"mode\":\"system\"", with: "\"mode\":\"automatic\"").utf8),
        Data(good.replacingOccurrences(of: "\"host\":\"\"", with: "\"host\":\"\",\"password\":\"x\"").utf8),
        Data(good.replacingOccurrences(of: "\"port\":\"\"", with: "\"port\":null").utf8),
        frWire(Data((String(decoding: frScheduled(), as: UTF8.self) + " ").utf8)),
        frWire(frScheduled(Data((emptyLiteral + " ").utf8))),
        frWire(frScheduled(fixtureBytes(principal: "foreign-owner"))), frWire(frScheduled(fixtureBytes(scope: "foreign-scope"))),
        frWire(setup: frSetup(true, false, frDraft("manualHTTP", String(repeating: "é", count: 128)))),
        frWire(setup: frSetup(true, false, frDraft("direct", "host"))),
        frWire(setup: frSetup(true, false, frDraft("manualHTTP", "", "1234567"))),
        frWire(setup: frSetup(true, false, frDraft("manualHTTP", "user:secret@proxy.invalid"))),
        frWire(setup: frSetup(true, false, frDraft("manualHTTP", "https://proxy.invalid"))),
        frWire(receipts: [frReceipt("userinfo-retention", frChoices(true, true, true, frDraft("manualHTTP", "user:secret@proxy.invalid")))]),
        frWire(receipts: [frReceipt("uri-retention", frChoices(true, true, true, frDraft("manualHTTP", "https://proxy.invalid")))]),
        frWire(receipts: [["id": "missing-choices", "complete": true]]),
        frWire(receipts: [["id": "missing-complete", "choices": frChoices()]]),
        frWire(receipts: [["id": "wrong-complete", "choices": frChoices(), "complete": 1]]),
        frWire(receipts: [["id": "extra", "choices": frChoices(), "complete": false, "extra": true]]),
        frWire(receipts: [frReceipt("same"), frReceipt("same")]),
        frWire(frScheduled(fixtureBytes(mutations: [("same", .skip(release))])), receipts: [frReceipt("same")]),
        frWire(frScheduled(receipts: [["id": "same", "change": ["action": "notifications", "enabled": false]]]), receipts: [frReceipt("same")]),
        frWire(receipts: (0..<129).map { frReceipt("f-\($0)") }),
        frWire(frScheduled(fixtureBytes(mutations: (0..<64).map { ("p-\($0)", .skip(release)) })), receipts: (0..<65).map { frReceipt("f-\($0)") }),
        Data(repeating: 32, count: PreferenceRecord.maximumBytes + 1)]
    var missingChoice = frChoices(); missingChoice.removeValue(forKey: "notifications")
    malformed.append(frWire(receipts: [frReceipt("missing-notify", missingChoice)]))
    var extraDraft = frDraft(); extraDraft["userinfo"] = "x"
    malformed.append(frWire(receipts: [frReceipt("extra-draft", frChoices(true, true, true, extraDraft))]))
    var extraChoice = frChoices(); extraChoice["coverageSharing"] = true
    malformed.append(frWire(receipts: [frReceipt("extra-choice", extraChoice)]))
    malformed.append(canonical(["schema": 3, "scheduled": NSNull(), "setup": frSetup(), "setupMutations": []]))
    malformed.append(canonical(["schema": 3, "scheduled": String(decoding: frScheduled(), as: UTF8.self), "setup": true, "setupMutations": []]))
    malformed.append(Data(good.replacingOccurrences(of: "\"mode\":\"system\"", with: "\"mode\":\"system\",\"mode\":\"system\"").utf8))
    for (index, bytes) in malformed.enumerated() {
        c.run("first run strict codec and owner reject malformed vector \(index)") {
            do {
                _ = try FirstRunPreferenceRecordCodec.decodeV3(bytes, principal: owner, storeScope: storeScope)
                throw CheckFailure(message: "invalid codec input accepted")
            } catch is CheckFailure { throw CheckFailure(message: "invalid codec input accepted") }
            catch {}
            let store = MemoryStore(bytes: bytes); let value = session(store)
            try require(frRefused(value.reload(generation: generation)), "invalid owner loaded")
            let reads = store.reads
            try require(frRefused(frSave(value)) && value.firstRunSetup == nil && store.writes == 0 && store.reads == reads && store.bytes == bytes, "malformed owner reset or leaked setup")
        }
    }
    c.run("first run whole envelope bound is exactly existing owner 1MiB") {
        try require(FirstRunPreferenceRecord.maximumBytes == PreferenceRecord.maximumBytes, "new owner bound")
        let probe = try exactByteFixture(1_000_000)
        let overhead = frWire(frScheduled(probe)).count - probe.count
        let bytes = frWire(frScheduled(try exactByteFixture(PreferenceRecord.maximumBytes - overhead)))
        try require(bytes.count == PreferenceRecord.maximumBytes, "exact envelope ceiling fixture")
        _ = try FirstRunPreferenceRecordCodec.decodeV3(bytes, principal: owner, storeScope: storeScope)
        let (value, store) = try frLoaded(bytes); let reads = store.reads
        try require(frSave(value) == .refused(.limit) && store.writes == 0 && store.reads == reads && store.bytes == bytes, "receipt expansion crossed total bound")
        let oversize = frWire(frScheduled(try exactByteFixture(PreferenceRecord.maximumBytes)))
        do {
            _ = try FirstRunPreferenceRecordCodec.decodeV3(oversize, principal: owner, storeScope: storeScope)
            throw CheckFailure(message: "pure codec accepted oversize envelope")
        } catch is CheckFailure { throw CheckFailure(message: "pure codec accepted oversize envelope") }
        catch {}
    }
    c.run("first run migration growth refuses before CAS leaving valid legacy owner") {
        let bytes = try exactByteFixture(PreferenceRecord.maximumBytes); let (value, store) = loaded(bytes)
        try require(value.acceptedRevision == 0, "legacy ceiling fixture load")
        let reads = store.reads
        try require(frSave(value) == .refused(.limit) && store.writes == 0 && store.reads == reads && store.bytes == bytes && value.firstRunSetup == nil, "oversize migration reached owner or reset")
    }
    c.run("first run missing and unavailable never bootstrap implicitly") {
        let missing = MemoryStore(); let a = session(missing)
        try require(a.reload(generation: generation) == .refused(.missing), "missing load")
        let reads = missing.reads
        try require(frRefused(frSave(a)) && a.firstRunSetup == nil && missing.reads == reads && missing.writes == 0 && missing.bytes == nil, "missing reset")
        let unavailable = FRUnavailableStore(); let b = session(unavailable)
        try require(b.reload(generation: generation) == .refused(.unavailable), "unavailable load")
        let unavailableReads = unavailable.reads
        try require(frRefused(frSave(b)) && b.firstRunSetup == nil && unavailable.reads == unavailableReads && unavailable.writes == 0, "unavailable reset")
        let ordinary = PreferenceSession()
        try require(ordinary.firstRunSetup == nil && frRefused(frSave(ordinary)), "ordinary composition acquired store")
    }
    for source in ["v1", "v2", "v3"] {
        for fault in [MemoryStore.Fault.beforeWrite, .uncertainAfterWrite, .lostAcknowledgement, .readbackMismatch] {
            c.run("first run \(source) CAS fault \(fault) preserves previous acknowledgement and queue") {
                let before = source == "v1" ? fixtureBytes() : (source == "v2" ? frScheduled() : frWire())
                let store = MemoryStore(bytes: before); let value = session(store)
                try require(value.reload(generation: generation) == .accepted(revision: 0) && enqueue(value), "fault source/queue load")
                guard case .started(let attempt) = start(value) else { throw CheckFailure(message: "existing manual start before fault") }
                store.fault = fault
                let choices = FirstRunChoices(dailyChecks: false, notifications: false, failureReports: false)
                let reason: PreferenceRefusal = fault == .beforeWrite ? .unavailable : (fault == .readbackMismatch ? .readback : .uncertain)
                try require(frSave(value, choices, complete: true) == .refused(reason) && value.acceptedRevision == 0, "optimistic acknowledgement")
                let actual = frWire(frScheduled(fixtureBytes(revision: 1), daily: false, notify: false), setup: frSetup(false, true), receipts: [frReceipt("setup-1", frChoices(false, false, false), true)])
                try require(store.bytes == (fault == .beforeWrite ? before : actual), "fault durable bytes differ")
                if fault == .beforeWrite {
                    try require(value.firstRunSetup == (source == "v3" ? FirstRunSetupState() : nil) && value.blockedReason == nil, "known no-commit changed accepted setup")
                } else {
                    try require(value.firstRunSetup == nil && value.scheduleSettings == nil && value.blockedReason == reason, "latched uncertain choices exposed")
                    store.clearFault(); let reads = store.reads; let writes = store.writes
                    try require(frRefused(frSave(value, id: "blocked")) && store.writes == writes && store.reads == reads, "latch bypass without reload")
                    try require(value.reload(generation: generation) == .accepted(revision: 1) && value.firstRunSetup == FirstRunSetupState(failureReports: false, completed: true), "explicit recovery failed")
                }
                try require(value.complete(attempt, principal: owner) && value.state(of: "entry") == .completed, "setup failure replaced existing queue")
            }
        }
    }
    c.run("first run CAS conflict hides both choices and requires explicit reload") {
        let (value, store) = try frLoaded(); let changed = frWire(frScheduled(fixtureBytes(revision: 1)), setup: frSetup(false, true)); store.bytes = changed
        try require(frSave(value) == .refused(.conflict) && value.firstRunSetup == nil && value.scheduleSettings == nil && value.acceptedRevision == 0, "conflict accepted")
        store.bytes = frWire(); let reads = store.reads; let writes = store.writes
        try require(frRefused(frSave(value)) && store.reads == reads && store.writes == writes, "restored bytes cleared latch")
        try require(value.reload(generation: generation) == .accepted(revision: 0) && value.firstRunSetup == FirstRunSetupState(), "explicit conflict reload")
    }
    c.run("first run shares reentrancy barrier with old edits reload scheduler and queue") {
        let (value, store) = try frLoaded(); try require(enqueue(value), "queue seed")
        var nested: [PreferenceEditResult] = []; var nestedStart: QueueStart?; var nestedCheck: ScheduledCheckAttempt?
        store.callback = {
            nested = [frSave(value, id: "nested"), edit(value, .skip(release)), value.editScheduleSettings(.notifications(false), mutationID: "nested-setting", expectedRevision: 0, generation: generation), value.reload(generation: generation)]
            nestedStart = start(value); nestedCheck = value.beginScheduledCheck(generation: generation)
        }
        try require(frSave(value) == .accepted(revision: 1), "outer save")
        try require(nested.count == 4 && nested.allSatisfy { $0 == .refused(.reentrant) } && nestedStart == .rejected && nestedCheck == nil, "nested callback escaped shared owner")
        try require(store.writes == 1 && value.state(of: "entry") == .pending, "nested owner mutated queue/storage")
    }
    c.run("first run owned durable fixture reopens same physical store without fresh bootstrap") {
        let store = try OwnedStore(); defer { try? store.cleanup() }
        let value = session(store)
        try require(value.bootstrapFreshFixture(generation: generation) == .accepted(revision: 0), "explicit fixture bootstrap")
        let choices = FirstRunChoices(dailyChecks: false, notifications: false, failureReports: false, networkDraft: FirstRunNetworkDraft(mode: .manualHTTP, host: "draft.invalid", port: ""))
        try require(frSave(value, choices, complete: true) == .accepted(revision: 1), "durable fixture save")
        let reopened = try OwnedStore(reopening: store); defer { reopened.closeReopenedHandles() }
        let next = session(reopened)
        try require(next.firstRunSetup == nil && next.reload(generation: generation) == .accepted(revision: 1), "physical owner reconstruction")
        try require(next.firstRunSetup == value.firstRunSetup && next.scheduleSettings == value.scheduleSettings, "physical reconstruction lost saved choices")
        try require(frSave(next, choices, complete: true, revision: 0) == .replayed(revision: 1), "durable receipt reconstruction")
    }
    c.run("first run save cancels stale scheduler callback preserves cadence active queue and authority limits") {
        let (value, store) = try frLoaded(); try require(enqueue(value), "queue seed")
        guard case .started(let active) = start(value) else { throw CheckFailure(message: "schema3 manual positive control") }
        let pending = candidate(version: "3", build: "30", artifact: "digest-3")
        try require(enqueue(value, pending, id: "pending"), "pending queue")
        func clock(_ elapsed: Int64 = 0) -> ClockSample { ClockSample(utc: 1000 + elapsed, monotonic: 100 + elapsed, boot: "first-run-boot", trustedUTC: true) }
        try require(value.observeSchedule(.observation(sample: clock(), awake: .yes), generation: generation), "scheduler observation")
        guard let old = value.beginScheduledCheck(generation: generation) else { throw CheckFailure(message: "schema3 scheduled opportunity") }
        try require(frSave(value, FirstRunChoices(notifications: false), complete: true) == .accepted(revision: 1), "joint save")
        let reads = store.reads
        try require(!value.completeScheduledCheck(old, generation: generation) && store.reads == reads && !value.scheduleRuntimeSnapshot.checkInFlight, "stale callback read or survived save")
        try require(value.beginScheduledCheck(generation: generation) == nil, "save reset daily cadence")
        try require(value.observeSchedule(.observation(sample: clock(86400), awake: .yes), generation: generation), "next day")
        guard let current = value.beginScheduledCheck(generation: generation) else { throw CheckFailure(message: "next opportunity lost") }
        let writes = store.writes; let replayReads = store.reads
        try require(frSave(value, FirstRunChoices(notifications: false), complete: true, revision: 0) == .replayed(revision: 1) && store.reads == replayReads && store.writes == writes, "replay did I/O")
        try require(value.completeScheduledCheck(current, generation: generation), "replay cancelled current attempt")
        try require(value.state(of: "entry") == .running(active) && value.state(of: "pending") == .pending, "setup replaced/started queue")
        try require(value.fail(active, principal: owner, scope: .isolated) && value.recover(active, principal: owner, evidence: .verifiedIsolatedRollback), "old active recovery lost")
        for kind in [StartKind.automatic, .loginWindow] { try require(!isStarted(start(value, pending, kind: kind, id: "pending", request: "never-\(kind)")), "first run declarations enabled unattended execution") }
        try require(isStarted(start(value, pending, id: "pending", request: "manual-next")), "schema3 manual control lost")
    }
}

// Literal canonical schema3, including independently literal nested schema2/schema1 bytes.
private let firstRunLiteral = #"{"scheduled":"{\"preferences\":\"{\\\"exclusions\\\":[],\\\"mutations\\\":[],\\\"principal\\\":\\\"synthetic-owner\\\",\\\"revision\\\":0,\\\"schema\\\":1,\\\"skips\\\":[],\\\"storeScope\\\":\\\"synthetic-store\\\"}\",\"schema\":2,\"settings\":{\"automaticUpdates\":false,\"dailyChecks\":true,\"notifications\":true,\"pause\":null},\"settingsMutations\":[]}","schema":3,"setup":{"completed":false,"failureReports":true,"networkDraft":{"host":"","mode":"system","port":""}},"setupMutations":[]}"#
