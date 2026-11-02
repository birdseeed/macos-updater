import Foundation
import PatchedScheduling
@_spi(Testing) import PatchedUpdatePreferences

// Independent wire expectations. Session behavior never supplies expected bytes.
private func ssSettings(_ daily: Bool = true, _ notify: Bool = true, _ automatic: Bool = false,
                        _ pause: Any = NSNull()) -> [String: Any] {
    ["dailyChecks": daily, "notifications": notify, "automaticUpdates": automatic, "pause": pause]
}
private func ssPause(_ utc: Int64 = 200, _ zone: String = "Europe/Isle_of_Man") -> [String: Any] {
    ["resumeUTC": NSNumber(value: utc), "displayZone": zone]
}
private func ssReceipt(_ id: String, _ action: String, _ value: Any) -> [String: Any] {
    ["id": id, "change": ["action": action, action == "pause" ? "pause" : "enabled": value]]
}
private func ssWire(_ inner: Data = fixtureBytes(), settings: [String: Any] = ssSettings(),
                    receipts: [[String: Any]] = []) -> Data {
    canonical(["schema": 2, "preferences": String(decoding: inner, as: UTF8.self),
               "settings": settings, "settingsMutations": receipts])
}
private func ssRefused(_ result: PreferenceEditResult) -> Bool {
    if case .refused = result { return true }; return false
}
@MainActor private func ssEdit(_ value: PreferenceSession, _ change: ScheduleSettingsChange,
                              id: String = "setting-1", revision: UInt64 = 0,
                              gen: String = generation) -> PreferenceEditResult {
    value.editScheduleSettings(change, mutationID: id, expectedRevision: revision, generation: gen)
}
@MainActor private func ssLoaded(_ bytes: Data = ssWire(), revision: UInt64 = 0) throws -> (PreferenceSession, MemoryStore) {
    let store = MemoryStore(bytes: bytes); let value = session(store)
    try require(value.reload(generation: generation) == .accepted(revision: revision), "strict v2 reload")
    return (value, store)
}

@MainActor func scheduleSessionChecks(_ c: Checks) {
    nativeScheduleClockChecks(c)
    inProcessScheduleChecks(c)
    c.run("schedule session independent canonical fixture controls", setup: true) {
        let expected = try Data(contentsOf: URL(fileURLWithPath: "Fixtures/SchedulePreferences/v2-default.json"))
        try require(ssWire() == expected, "independent wire/literal mismatch")
        let inner = fixtureBytes(revision: 7, exclusions: [PreferenceAppKey(release)], skips: [release], mutations: [("old", .skip(release))])
        let proposal = try SchedulePreferenceRecordCodec.proposeV1Migration(inner, principal: owner, storeScope: storeScope)
        try require(proposal.originalV1Bytes == inner && proposal.proposedV2Bytes == ssWire(inner), "proposal wire control")
        try require(try SchedulePreferenceRecordCodec.decodeV2(ssWire(inner), principal: owner, storeScope: storeScope).preferences.revision == 7, "v2 fixture revision")
    }
    c.run("schedule session fault fixture controls", setup: true) {
        for fault in [MemoryStore.Fault.beforeWrite, .uncertainAfterWrite, .lostAcknowledgement, .readbackMismatch] {
            let store = MemoryStore(bytes: fixtureBytes()); store.fault = fault
            let result = store.compareAndSwap(expected: fixtureBytes(), proposed: ssWire(), maximumBytes: PreferenceRecord.maximumBytes)
            if fault == .beforeWrite {
                try require(result == .notCommitted && store.bytes == fixtureBytes(), "before-write control")
            } else {
                try require(store.bytes == ssWire(), "post-write fixture bytes")
                if fault == .readbackMismatch { try require(store.read(maximumBytes: PreferenceRecord.maximumBytes) == .bytes(Data("mismatch".utf8)), "mismatch control") }
                else { try require(result == .uncertain, "uncertain control") }
            }
        }
    }
    c.run("schedule session default owner refuses every new API") {
        let value = PreferenceSession()
        try require(value.scheduleSettings == nil && value.acceptedRevision == nil, "default published settings")
        try require(value.migrateScheduleSettings(expectedRevision: 0, generation: generation) == .refused(.defaultComposition), "default migrated")
        try require(ssEdit(value, .dailyChecks(false)) == .refused(.defaultComposition), "default setting write")
        try require(value.scheduleSettings == nil && value.acceptedRevision == nil && value.blockedReason == .defaultComposition, "default authority changed")
    }
    c.run("schedule session v1 reload remains read only without implicit migration") {
        let old = fixtureBytes(revision: 7, exclusions: [PreferenceAppKey(release)], skips: [release])
        let (value, store) = loaded(old)
        try require(value.acceptedRevision == 7 && value.blockedReason == nil && value.scheduleSettings == nil, "legacy load changed")
        try require(ssRefused(ssEdit(value, .dailyChecks(false), revision: 7)), "settings silently migrated v1")
        try require(store.bytes == old && store.writes == 0, "v1 rewritten")
    }
    c.run("schedule session explicit migration exact CAS and readback preserves all v1 state") {
        let old = fixtureBytes(revision: 7, exclusions: [PreferenceAppKey(release)], skips: [release], mutations: [("old", .skip(release))])
        let (value, store) = loaded(old); let reads = store.reads
        var during: ScheduleSettings?; var duringRevision: UInt64?
        store.callback = { during = value.scheduleSettings; duringRevision = value.acceptedRevision }
        try require(value.migrateScheduleSettings(expectedRevision: 7, generation: generation) == .accepted(revision: 7), "explicit migration refused")
        try require(store.bytes == ssWire(old) && store.writes == 1 && store.reads > reads, "migration bytes or readback")
        try require(during == nil && duringRevision == 7, "optimistic migration publication")
        try require(value.scheduleSettings == ScheduleSettings() && value.acceptedRevision == 7, "migration defaults/revision")
        try require(value.projection([PreferenceCandidate(id: "app", release: .verified(release))]).skippedCount == 1, "migration lost skip")
        try require(value.migrateScheduleSettings(expectedRevision: 7, generation: generation) == .replayed(revision: 7), "migration not idempotent")
        try require(value.migrateScheduleSettings(expectedRevision: 6, generation: generation) == .refused(.conflict), "stale migration replay")
        try require(store.writes == 1 && store.bytes == ssWire(old), "migration replay wrote")
    }
    for (name, bytes) in [("missing", Optional<Data>.none), ("corrupt", Optional(Data("{".utf8))),
                          ("foreign principal", Optional(fixtureBytes(principal: "foreign"))),
                          ("foreign scope", Optional(fixtureBytes(scope: "foreign"))),
                          ("oversize", Optional(Data(repeating: 32, count: PreferenceRecord.maximumBytes + 1)))] {
        c.run("schedule session migration refuses \(name) without reset") {
            let store = MemoryStore(bytes: bytes); let value = session(store)
            try require(ssRefused(value.reload(generation: generation)), "invalid state loaded")
            try require(ssRefused(value.migrateScheduleSettings(expectedRevision: 0, generation: generation)), "invalid migrated")
            try require(value.scheduleSettings == nil && store.bytes == bytes && store.writes == 0, "reset/repair on invalid migration")
        }
    }
    c.run("schedule session migration requires accepted load and current generation revision") {
        let store = MemoryStore(bytes: fixtureBytes()); let value = session(store)
        try require(ssRefused(value.migrateScheduleSettings(expectedRevision: 0, generation: generation)) && store.writes == 0, "unloaded migrated")
        try require(value.reload(generation: generation) == .accepted(revision: 0), "legacy control load")
        try require(value.migrateScheduleSettings(expectedRevision: 0, generation: "old") == .refused(.staleGeneration), "stale generation migrated")
        try require(value.migrateScheduleSettings(expectedRevision: 1, generation: generation) == .refused(.conflict), "stale revision migrated")
        try require(store.bytes == fixtureBytes() && store.writes == 0 && value.scheduleSettings == nil, "stale migration wrote")
    }
    c.run("schedule session migration exact-byte drift latches until explicit reload") {
        let (value, store) = loaded(); let changed = fixtureBytes(revision: 1, skips: [release]); store.bytes = changed
        try require(value.migrateScheduleSettings(expectedRevision: 0, generation: generation) == .refused(.conflict), "drift accepted")
        try require(store.bytes == changed && value.acceptedRevision == 0 && value.scheduleSettings == nil, "drift overwritten or published")
        store.bytes = fixtureBytes(); let writes = store.writes
        try require(ssRefused(value.migrateScheduleSettings(expectedRevision: 0, generation: generation)) && store.writes == writes, "restored bytes cleared latch")
        try require(value.reload(generation: generation) == .accepted(revision: 0), "explicit reload")
        try require(value.migrateScheduleSettings(expectedRevision: 0, generation: generation) == .accepted(revision: 0), "migration after reload")
    }
    c.run("schedule session reentrancy covers migration settings old edit reload and start") {
        let (value, store) = loaded(); try require(enqueue(value), "pending queue")
        var results: [PreferenceEditResult] = []; var nestedStart: QueueStart?
        store.callback = {
            results = [value.migrateScheduleSettings(expectedRevision: 0, generation: generation), ssEdit(value, .notifications(false)), edit(value, .skip(release)), value.reload(generation: generation)]
            nestedStart = start(value)
        }
        try require(value.migrateScheduleSettings(expectedRevision: 0, generation: generation) == .accepted(revision: 0), "outer migration")
        try require(results.count == 4 && results.allSatisfy { $0 == .refused(.reentrant) } && nestedStart == .rejected, "nested operation escaped owner")
        try require(value.state(of: "entry") == .pending && store.bytes == ssWire() && store.writes == 1, "queue reset or nested write")
    }
    c.run("schedule session same owned fixture persists after adapter and session reconstruction") {
        let store = try OwnedStore(); defer { try? store.cleanup() }
        let old = fixtureBytes(revision: 8, exclusions: [PreferenceAppKey(release)], skips: [release], mutations: [("old", .skip(release))])
        try require(store.compareAndSwap(expected: nil, proposed: old, maximumBytes: PreferenceRecord.maximumBytes) == .committed, "fixture seed")
        let value = session(store)
        try require(value.reload(generation: generation) == .accepted(revision: 8), "v1 fixture load")
        try require(value.migrateScheduleSettings(expectedRevision: 8, generation: generation) == .accepted(revision: 8), "fixture migration")
        try require(ssEdit(value, .notifications(false), revision: 8) == .accepted(revision: 9), "fixture setting save")
        let replacement = try OwnedStore(reopening: store); defer { replacement.closeReopenedHandles() }
        let restarted = session(replacement, gen: "generation-2", queue: "new-queue")
        try require(restarted.reload(generation: "generation-2") == .accepted(revision: 9), "reopened v2 refused")
        let inner = fixtureBytes(revision: 9, exclusions: [PreferenceAppKey(release)], skips: [release], mutations: [("old", .skip(release))])
        try require(replacement.read(maximumBytes: PreferenceRecord.maximumBytes) == .bytes(ssWire(inner, settings: ssSettings(true, false), receipts: [ssReceipt("setting-1", "notifications", false)])), "reopen bytes lost")
        try require(restarted.scheduleSettings == ScheduleSettings(notifications: false), "reconstructed choice")
    }
    let changes: [(String, ScheduleSettingsChange, ScheduleSettings, [String: Any], [String: Any])] = [
        ("daily", .dailyChecks(false), ScheduleSettings(dailyChecks: false), ssSettings(false), ssReceipt("setting-1", "dailyChecks", false)),
        ("notify", .notifications(false), ScheduleSettings(notifications: false), ssSettings(true, false), ssReceipt("setting-1", "notifications", false)),
        ("automatic off", .automaticUpdates(false), ScheduleSettings(), ssSettings(), ssReceipt("setting-1", "automaticUpdates", false)),
        ("pause set", .pause(SchedulePauseChoice(resumeUTC: 200, displayZone: "Europe/Isle_of_Man")), ScheduleSettings(pause: SchedulePauseChoice(resumeUTC: 200, displayZone: "Europe/Isle_of_Man")), ssSettings(true, true, false, ssPause()), ssReceipt("setting-1", "pause", ssPause())),
        ("pause clear", .pause(nil), ScheduleSettings(), ssSettings(), ssReceipt("setting-1", "pause", NSNull()))]
    for (name, change, settings, wireSettings, receipt) in changes {
        c.run("schedule session typed \(name) saves shared revision and exact receipts") {
            let initial = name == "pause clear" ? ssWire(settings: ssSettings(true, true, false, ssPause())) : ssWire()
            let (value, store) = try ssLoaded(initial); let reads = store.reads
            var during: ScheduleSettings?; store.callback = { during = value.scheduleSettings }
            let before = value.scheduleSettings
            try require(ssEdit(value, change) == .accepted(revision: 1), "typed save refused")
            let expected = ssWire(fixtureBytes(revision: 1), settings: wireSettings, receipts: [receipt])
            try require(store.bytes == expected && store.writes == 1 && store.reads > reads, "typed save exact bytes/readback")
            try require(during == before && value.scheduleSettings == settings && value.acceptedRevision == 1, "optimistic or wrong settings")
            try require(ssEdit(value, change, revision: 0) == .replayed(revision: 1) && store.writes == 1, "exact stale-revision replay wrote")
            let restarted = session(store, gen: "next")
            try require(restarted.reload(generation: "next") == .accepted(revision: 1) && restarted.scheduleSettings == settings, "same-store restart lost typed choice")
        }
    }
    c.run("schedule session automatic enable refuses without storage or start authority") {
        let (value, store) = try ssLoaded()
        try require(ssRefused(ssEdit(value, .automaticUpdates(true))), "automatic enabled in admitted phase")
        try require(store.bytes == ssWire() && store.writes == 0 && value.scheduleSettings == ScheduleSettings(), "refusal changed choices")
    }
    c.run("schedule session retained automatic enable cannot replay or enable with a fresh ID") {
        let bytes = ssWire(settings: ssSettings(true, true, true), receipts: [ssReceipt("auto-old", "automaticUpdates", true)])
        let (value, store) = try ssLoaded(bytes)
        try require(value.scheduleSettings == ScheduleSettings(automaticUpdates: true), "prior declaration not preserved on load")
        try require(ssRefused(ssEdit(value, .automaticUpdates(true), id: "auto-old")), "retained automatic enable replayed")
        try require(ssRefused(ssEdit(value, .automaticUpdates(true), id: "auto-fresh")), "fresh automatic enable accepted")
        try require(store.writes == 0 && store.bytes == bytes && value.acceptedRevision == 0 && value.scheduleSettings == ScheduleSettings(automaticUpdates: true), "enable refusal changed loaded bytes or choices")
        try require(enqueue(value), "pending fixture for retained declaration")
        try require(!isStarted(start(value, kind: .automatic, automatic: true)) && value.state(of: "entry") == .pending && store.writes == 0, "retained enable receipt conferred start authority")
    }
    c.run("schedule session existing edits and settings share one revision and preserve both histories") {
        let original = fixtureBytes(exclusions: [PreferenceAppKey(release)], skips: [release], mutations: [("old", .skip(release))])
        let (value, store) = try ssLoaded(ssWire(original))
        try require(ssEdit(value, .notifications(false), id: "notify") == .accepted(revision: 1), "setting edit")
        try require(edit(value, .undo(release), id: "undo", revision: 1) == .accepted(revision: 2), "existing v2 edit")
        let receipts = [ssReceipt("notify", "notifications", false)]
        let inner = fixtureBytes(revision: 2, exclusions: [PreferenceAppKey(release)], mutations: [("old", .skip(release)), ("undo", .undo(release))])
        try require(store.bytes == ssWire(inner, settings: ssSettings(true, false), receipts: receipts), "existing edit dropped settings/history")
        try require(ssEdit(value, .dailyChecks(false), id: "daily", revision: 2) == .accepted(revision: 3), "later setting edit")
        let finalInner = fixtureBytes(revision: 3, exclusions: [PreferenceAppKey(release)], mutations: [("old", .skip(release)), ("undo", .undo(release))])
        try require(store.bytes == ssWire(finalInner, settings: ssSettings(false, false), receipts: receipts + [ssReceipt("daily", "dailyChecks", false)]), "setting edit dropped preferences/history")
        try require(value.projection([]).revision == 3 && value.scheduleSettings == ScheduleSettings(dailyChecks: false, notifications: false), "shared projection revision")
    }
    c.run("schedule session mutation ID namespace refuses cross-type collisions in both directions") {
        let old = fixtureBytes(mutations: [("shared", .skip(release))])
        let (a, sa) = try ssLoaded(ssWire(old))
        try require(ssEdit(a, .notifications(false), id: "shared") == .refused(.conflict), "preference ID reused by settings")
        try require(sa.writes == 0 && sa.bytes == ssWire(old), "collision rewrote old history")
        let bytes = ssWire(receipts: [ssReceipt("shared", "notifications", false)])
        let (b, sb) = try ssLoaded(bytes)
        try require(edit(b, .skip(release), id: "shared") == .refused(.conflict), "setting ID reused by preferences")
        try require(ssEdit(b, .dailyChecks(false), id: "shared") == .refused(.conflict), "setting ID changed action")
        try require(ssEdit(b, .notifications(true), id: "shared") == .refused(.conflict), "setting ID changed value")
        try require(sb.writes == 0 && sb.bytes == bytes, "collision changed bytes")
    }
    c.run("schedule session stale settings generation and revision refuse before write") {
        let (value, store) = try ssLoaded()
        try require(ssEdit(value, .dailyChecks(false), gen: "old") == .refused(.staleGeneration), "stale generation")
        try require(ssEdit(value, .dailyChecks(false), revision: 1) == .refused(.conflict), "stale revision")
        try require(store.writes == 0 && store.bytes == ssWire(), "stale write")
    }
    c.run("schedule session maximum revision settings edit never wraps") {
        let bytes = ssWire(fixtureBytes(revision: UInt64.max)); let (value, store) = try ssLoaded(bytes, revision: UInt64.max)
        try require(ssEdit(value, .dailyChecks(false), revision: UInt64.max) == .refused(.revisionOverflow), "wrapped revision")
        try require(store.bytes == bytes && store.writes == 0, "overflow wrote")
    }
    for preferenceCount in [0, 64, 128] {
        c.run("schedule session combined 128 receipts preserve both namespaces \(preferenceCount)") {
            let old = (0..<preferenceCount).map { ("old-\($0)", PreferenceChange.skip(release)) }
            let settings = (preferenceCount..<128).map { ssReceipt("setting-\($0)", "notifications", false) }
            let bytes = ssWire(fixtureBytes(mutations: old), receipts: settings); let (value, store) = try ssLoaded(bytes)
            try require(ssEdit(value, .dailyChecks(false), id: "new") == .refused(.limit), "combined limit evicted history")
            try require(edit(value, .skip(release), id: "new-old") == .refused(.limit), "existing edit ignored combined limit")
            if preferenceCount > 0 { try require(edit(value, .skip(release), id: "old-0") == .replayed(revision: 0), "old replay lost") }
            if preferenceCount < 128 { try require(ssEdit(value, .notifications(false), id: "setting-\(preferenceCount)") == .replayed(revision: 0), "setting replay lost") }
            try require(store.writes == 0 && store.bytes == bytes, "combined limit trimmed/reset")
        }
    }
    for id in ["", "bad\nid", "bad\0id", String(repeating: "x", count: 257)] {
        c.run("schedule session rejects invalid settings mutation ID \(id.utf8.count)") {
            let (value, store) = try ssLoaded()
            try require(ssEdit(value, .dailyChecks(false), id: id) == .refused(.identity), "invalid ID accepted")
            try require(store.writes == 0 && store.bytes == ssWire(), "invalid ID wrote")
        }
    }
    c.run("schedule session strict accepted v2 migration replay preserves saved settings") {
        let bytes = ssWire(fixtureBytes(revision: 9), settings: ssSettings(false, false, false, ssPause()), receipts: [ssReceipt("pause", "pause", ssPause())])
        let (value, store) = try ssLoaded(bytes, revision: 9)
        try require(value.migrateScheduleSettings(expectedRevision: 9, generation: generation) == .replayed(revision: 9), "loaded v2 migration not replayed")
        try require(value.migrateScheduleSettings(expectedRevision: 8, generation: generation) == .refused(.conflict), "loaded v2 stale migration")
        try require(store.writes == 0 && store.bytes == bytes && value.scheduleSettings == ScheduleSettings(dailyChecks: false, notifications: false, pause: SchedulePauseChoice(resumeUTC: 200, displayZone: "Europe/Isle_of_Man")), "replay reset saved settings")
    }
    c.run("schedule session settings CAS reentrancy shares the existing owner barrier") {
        let (value, store) = try ssLoaded(); try require(enqueue(value), "pending queue")
        var nested: [PreferenceEditResult] = []; var nestedStart: QueueStart?
        store.callback = {
            nested = [ssEdit(value, .dailyChecks(false), id: "nested"), value.migrateScheduleSettings(expectedRevision: 0, generation: generation), edit(value, .skip(release)), value.reload(generation: generation)]
            nestedStart = start(value)
        }
        try require(ssEdit(value, .notifications(false)) == .accepted(revision: 1), "outer setting edit")
        try require(nested.count == 4 && nested.allSatisfy { $0 == .refused(.reentrant) } && nestedStart == .rejected, "settings callback escaped owner")
        try require(value.state(of: "entry") == .pending && store.writes == 1, "settings callback reset queue or wrote twice")
    }
    let good = String(decoding: ssWire(), as: UTF8.self)
    let malformed = [good + " ", good.replacingOccurrences(of: "\"schema\":2", with: "\"schema\":2,\"schema\":2"),
        good.replacingOccurrences(of: "\"schema\":2", with: "\"schema\":2,\"extra\":true"),
        good.replacingOccurrences(of: "\"dailyChecks\":true,", with: ""),
        good.replacingOccurrences(of: "\"notifications\":true", with: "\"notifications\":true,\"notifications\":true")]
    for (index, text) in malformed.enumerated() {
        c.run("schedule session strict v2 reload rejects malformed canonical envelope \(index)") {
            let (value, store) = try ssLoaded(); let invalid = Data(text.utf8); store.bytes = invalid
            try require(value.reload(generation: generation) == .refused(.malformed), "invalid envelope accepted")
            try require(value.scheduleSettings == nil && value.acceptedRevision == 0, "latched owner exposed new acknowledgement")
            try require(ssRefused(ssEdit(value, .dailyChecks(false))) && store.writes == 0 && store.bytes == invalid, "malformed state reset")
        }
    }
    let badHistory: [Data] = [
        ssWire(receipts: [["id": "missing-change"]]),
        ssWire(receipts: [["change": ["action": "notifications", "enabled": false]]]),
        ssWire(receipts: [["id": "unknown", "change": ["action": "runHelper", "enabled": true]]]),
        ssWire(receipts: [["id": "extra", "change": ["action": "notifications", "enabled": false], "extra": true]]),
        ssWire(receipts: [ssReceipt("same", "notifications", false), ssReceipt("same", "dailyChecks", false)]),
        ssWire(fixtureBytes(mutations: [("same", .skip(release))]), receipts: [ssReceipt("same", "notifications", false)]),
        ssWire(receipts: (0..<129).map { ssReceipt("id-\($0)", "notifications", false) }),
        ssWire(fixtureBytes(mutations: (0..<64).map { ("old-\($0)", .skip(release)) }), receipts: (0..<65).map { ssReceipt("setting-\($0)", "notifications", false) })]
    for (index, bytes) in badHistory.enumerated() {
        c.run("schedule session strict v2 reload rejects malformed or over-limit history \(index)") {
            let store = MemoryStore(bytes: bytes); let value = session(store)
            try require(value.reload(generation: generation) == .refused(.malformed), "invalid history loaded")
            try require(value.scheduleSettings == nil && value.acceptedRevision == nil && store.writes == 0 && store.bytes == bytes, "invalid history reset")
        }
    }
    c.run("schedule session bounded near-limit vector controls", setup: true) {
        let inner = try exactByteFixture(PreferenceRecord.maximumBytes)
        try require(try PreferenceRecordCodec.decode(inner, principal: owner, storeScope: storeScope).revision == 0, "canonical near-limit inner")
        let outer = ssWire(inner)
        try require(outer.count > PreferenceRecord.maximumBytes && outer.count < SchedulePreferenceRecord.maximumBytes, "envelope did not cross native bound")
        try require(try SchedulePreferenceRecordCodec.decodeV2(outer, principal: owner, storeScope: storeScope).preferences.revision == 0, "pure codec ceiling control")
    }
    c.run("schedule session oversized migration proposal refuses before CAS preserving valid v1") {
        let old = try exactByteFixture(PreferenceRecord.maximumBytes); let (value, store) = loaded(old)
        try require(value.acceptedRevision == 0, "valid full v1 load")
        try require(value.migrateScheduleSettings(expectedRevision: 0, generation: generation) == .refused(.limit), "native bound widened for proposal")
        try require(store.writes == 0 && store.bytes == old && value.scheduleSettings == nil, "oversized proposal reached store or reset v1")
    }
    c.run("schedule session oversized loaded outer refuses at unchanged total store bound") {
        let bytes = ssWire(try exactByteFixture(PreferenceRecord.maximumBytes)); let store = MemoryStore(bytes: bytes); let value = session(store)
        try require(value.reload(generation: generation) == .refused(.unavailable), "session widened total read bound")
        try require(ssRefused(value.migrateScheduleSettings(expectedRevision: 0, generation: generation)) && ssRefused(ssEdit(value, .dailyChecks(false))), "oversized state repaired")
        try require(store.writes == 0 && store.bytes == bytes && value.scheduleSettings == nil, "oversized load wrote")
    }
    c.run("schedule session near-native-bound settings mutation refuses before CAS") {
        // Envelope growth is fixed for these ASCII fixtures. Two encodings, no search.
        let probe = try exactByteFixture(1_000_000); let overhead = ssWire(probe).count - probe.count
        let inner = try exactByteFixture(PreferenceRecord.maximumBytes - overhead)
        let bytes = ssWire(inner)
        try require(bytes.count == PreferenceRecord.maximumBytes, "deterministic exact outer ceiling")
        let (value, store) = try ssLoaded(bytes)
        try require(ssEdit(value, .notifications(false)) == .refused(.limit), "oversized settings mutation accepted")
        try require(store.writes == 0 && store.bytes == bytes && value.acceptedRevision == 0, "oversized mutation reached CAS")
    }
    for migrating in [true, false] {
        for fault in [MemoryStore.Fault.beforeWrite, .uncertainAfterWrite, .lostAcknowledgement, .readbackMismatch] {
            c.run("schedule session \(migrating ? "migration" : "setting") fault \(fault) never optimistically acknowledges") {
                let original = migrating ? fixtureBytes() : ssWire()
                let store = MemoryStore(bytes: original); let value = session(store)
                try require(value.reload(generation: generation) == .accepted(revision: 0), "fault source load")
                try require(enqueue(value), "in-flight queue seed")
                guard case .started(let attempt) = start(value) else { throw CheckFailure(message: "manual attempt before fault") }
                store.fault = fault
                let result = migrating ? value.migrateScheduleSettings(expectedRevision: 0, generation: generation) : ssEdit(value, .notifications(false))
                let reason: PreferenceRefusal = fault == .beforeWrite ? .unavailable : (fault == .readbackMismatch ? .readback : .uncertain)
                try require(result == .refused(reason) && value.acceptedRevision == 0, "fault acknowledged or wrong diagnosis")
                let actual = migrating ? ssWire() : ssWire(fixtureBytes(revision: 1), settings: ssSettings(true, false), receipts: [ssReceipt("setting-1", "notifications", false)])
                try require(store.bytes == (fault == .beforeWrite ? original : actual), "observed durable bytes")
                if fault == .beforeWrite { try require(value.scheduleSettings == (migrating ? nil : ScheduleSettings()), "known failure published settings") }
                else {
                    try require(value.scheduleSettings == nil && value.blockedReason == reason, "latched failure exposed acknowledgement")
                    let writes = store.writes; store.clearFault()
                    try require(ssRefused(ssEdit(value, .dailyChecks(false))) && store.writes == writes, "latched failure bypassed explicit reload")
                    try require(value.reload(generation: generation) == .accepted(revision: migrating ? 0 : 1), "explicit reload actual bytes")
                    try require(value.scheduleSettings == (migrating ? ScheduleSettings() : ScheduleSettings(notifications: false)), "reload did not publish actual choices")
                }
                try require(value.complete(attempt, principal: owner) && value.state(of: "entry") == .completed, "settings error reset in-flight queue/completion")
            }
        }
    }
    c.run("schedule session v2 conflict hides settings and preserves fail recover across latch") {
        let (value, store) = try ssLoaded(); try require(enqueue(value), "queue seed")
        guard case .started(let attempt) = start(value) else { throw CheckFailure(message: "manual queue start") }
        let changed = ssWire(fixtureBytes(revision: 1), settings: ssSettings(false)); store.bytes = changed
        try require(ssEdit(value, .notifications(false)) == .refused(.conflict), "conflict accepted")
        try require(value.scheduleSettings == nil && value.acceptedRevision == 0 && store.bytes == changed, "conflict publication")
        store.bytes = ssWire(); let writes = store.writes
        try require(ssRefused(ssEdit(value, .dailyChecks(false))) && store.writes == writes, "restored bytes cleared conflict")
        try require(value.fail(attempt, principal: owner, scope: .isolated), "latched failure blocked fail")
        try require(value.recover(attempt, principal: owner, evidence: .verifiedIsolatedRollback) && value.state(of: "entry") == .restored, "latched failure blocked recover")
        try require(value.reload(generation: generation) == .accepted(revision: 0) && value.scheduleSettings == ScheduleSettings(), "explicit reload did not restore choices")
    }
    c.run("schedule session v2 action-time drift latches without starting or repairing") {
        let (value, store) = try ssLoaded(); try require(enqueue(value), "pending manual fixture")
        let changed = ssWire(fixtureBytes(revision: 1), settings: ssSettings(false)); store.bytes = changed
        try require(start(value) == .rejected && value.state(of: "entry") == .pending, "stale v2 bytes started")
        try require(value.blockedReason == .conflict && value.scheduleSettings == nil && store.bytes == changed && store.writes == 0, "start drift repaired or acknowledged")
        store.bytes = ssWire()
        try require(start(value) == .rejected && value.scheduleSettings == nil, "restored bytes cleared start latch")
        try require(value.reload(generation: generation) == .accepted(revision: 0) && isStarted(start(value)), "fresh explicit reload did not recover manual start")
    }
    for storedAutomatic in [false, true] {
        for kind in [StartKind.automatic, .loginWindow] {
            c.run("schedule session v2 stored automatic \(storedAutomatic) caller true never enables \(kind)") {
                let (value, store) = try ssLoaded(ssWire(settings: ssSettings(true, true, storedAutomatic)))
                try require(enqueue(value), "pending automatic fixture")
                let result = start(value, kind: kind, automatic: true)
                try require(!isStarted(result) && value.state(of: "entry") == .pending, "stored/caller boolean conferred productive authority")
                try require(store.writes == 0, "start rewrote consent")
                try require(isStarted(start(value, kind: .manual)), "manual model regressed under stored settings")
            }
        }
    }
}
