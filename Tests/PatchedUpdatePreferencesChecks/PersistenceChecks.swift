import Foundation
import Darwin
import PatchedScheduling
@_spi(Testing) import PatchedUpdatePreferences

@MainActor func persistenceChecks(_ c: Checks) {
    c.run("memory CAS mechanics preserve exact bytes", setup: true) {
        let store = MemoryStore(bytes: Data(emptyLiteral.utf8))
        try require(store.read(maximumBytes: 1_048_576) == .bytes(Data(emptyLiteral.utf8)), "read bytes")
        try require(store.compareAndSwap(expected: nil, proposed: Data("other".utf8), maximumBytes: 1_048_576) == .conflict, "CAS conflict")
        try require(store.bytes == Data(emptyLiteral.utf8), "conflict changed bytes")
    }
    c.run("owned actual bytes private root and cleanup", setup: true) {
        let store = try OwnedStore(); defer { try? store.cleanup() }
        let attributes = try FileManager.default.attributesOfItem(atPath: store.rootURL.path)
        try require((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700, "root mode")
        try require(store.compareAndSwap(expected: nil, proposed: Data(emptyLiteral.utf8), maximumBytes: 1_048_576) == .committed, "actual fixture write")
        try require(store.read(maximumBytes: 1_048_576) == .bytes(Data(emptyLiteral.utf8)), "actual fixture read")
        try store.cleanup()
        try require(!FileManager.default.fileExists(atPath: store.rootURL.path), "owned cleanup")
    }
    for fault in [OwnedStore.Fault.beforeWrite, .shortWrite, .sync, .rename] {
        c.run("owned known failure \(fault) preserves bytes", setup: true) {
            let store = try OwnedStore(); defer { try? store.cleanup() }
            let original = Data(emptyLiteral.utf8)
            try require(store.compareAndSwap(expected: nil, proposed: original, maximumBytes: 1_048_576) == .committed, "seed")
            store.fault = fault
            try require(store.compareAndSwap(expected: original, proposed: fixtureBytes(revision: 1), maximumBytes: 1_048_576) == .notCommitted, "fault outcome")
            try require(store.read(maximumBytes: 1_048_576) == .bytes(original), "known failure changed original")
        }
    }
    c.run("owned uncertain rename reports committed bytes without acknowledgement", setup: true) {
        let store = try OwnedStore(); defer { try? store.cleanup() }
        store.fault = .uncertainAfterRename
        let bytes = Data(emptyLiteral.utf8)
        try require(store.compareAndSwap(expected: nil, proposed: bytes, maximumBytes: 1_048_576) == .uncertain, "uncertainty hidden")
        try require(store.read(maximumBytes: 1_048_576) == .bytes(bytes), "uncertain bytes absent")
    }
    c.run("owned symlink child refuses bounded read", setup: true) {
        let store = try OwnedStore(); defer { try? store.cleanup() }
        let path = store.rootURL.appendingPathComponent("record.json").path
        try require(symlink("nonexistent-owned-test-target", path) == 0, "create owned inert symlink")
        try require(store.read(maximumBytes: 1_048_576) == .unavailable, "symlink followed")
    }
    c.run("owned hardlink child refuses bounded read", setup: true) {
        let store = try OwnedStore(); defer { try? store.cleanup() }
        let bytes = Data(emptyLiteral.utf8)
        try require(store.compareAndSwap(expected: nil, proposed: bytes, maximumBytes: 1_048_576) == .committed, "seed")
        let original = store.rootURL.appendingPathComponent("record.json").path
        let extra = store.rootURL.appendingPathComponent("second-link").path
        try require(link(original, extra) == 0, "owned hardlink setup")
        defer { unlink(extra) }
        try require(store.read(maximumBytes: 1_048_576) == .unavailable, "hardlink accepted")
    }
    c.run("owned overlong bytes refuse read", setup: true) {
        let store = try OwnedStore(); defer { try? store.cleanup() }
        let bytes = Data(repeating: 32, count: 1_048_577)
        try bytes.write(to: store.rootURL.appendingPathComponent("record.json"))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: store.rootURL.appendingPathComponent("record.json").path)
        try require(store.read(maximumBytes: 1_048_576) == .unavailable, "oversize allocation accepted")
    }
    c.run("existing literal load publishes revision") {
        let (value, store) = loaded()
        try require(value.acceptedRevision == 0 && value.blockedReason == nil, "load did not accept exact record")
        try require(store.writes == 0, "load silently rewrote record")
    }
    c.run("explicit fresh bootstrap persists exact literal") {
        let store = MemoryStore(); let value = session(store)
        try require(value.bootstrapFreshFixture(generation: generation) == .accepted(revision: 0), "fresh bootstrap refused")
        try require(store.bytes == Data(emptyLiteral.utf8) && value.acceptedRevision == 0, "bootstrap bytes/revision")
    }
    c.run("missing existing store never silently bootstraps") {
        let store = MemoryStore(); let value = session(store)
        try require(value.reload(generation: generation) == .refused(.missing), "missing must be diagnosed")
        try require(store.writes == 0 && value.acceptedRevision == nil, "missing state reset")
    }
    c.run("bootstrap refuses existing state without erase") {
        let bytes = fixtureBytes(revision: 4, skips: [release]); let store = MemoryStore(bytes: bytes); let value = session(store)
        try require(value.bootstrapFreshFixture(generation: generation) == .refused(.conflict), "bootstrap overwrote existing state")
        try require(store.bytes == bytes && store.writes == 0, "existing bytes erased")
    }
    c.run("acknowledged skip persists canonical exact revision") {
        let (value, store) = loaded()
        try require(edit(value, .skip(release)) == .accepted(revision: 1), "skip refused")
        let expected = fixtureBytes(revision: 1, skips: [release], mutations: [("mutation-1", .skip(release))])
        try require(store.bytes == expected && value.acceptedRevision == 1, "acknowledgement lacks exact bytes")
        try require(store.reads >= 2, "no readback")
    }
    c.run("owned persisted bytes fresh adapter and session restart") {
        let store = try OwnedStore(); defer { try? store.cleanup() }
        let value = session(store)
        try require(value.bootstrapFreshFixture(generation: generation) == .accepted(revision: 0), "bootstrap")
        try require(edit(value, .skip(release)) == .accepted(revision: 1), "persist skip")
        let replacement = try OwnedStore(reopening: store); defer { replacement.closeReopenedHandles() }
        let restarted = session(replacement, gen: "generation-2", queue: "new-queue")
        try require(restarted.reload(generation: "generation-2") == .accepted(revision: 1), "restart did not recover bytes")
        try require(restarted.projection([PreferenceCandidate(id: "e", release: .verified(release))]).skippedCount == 1, "restart skip lost")
    }
    for fault in [MemoryStore.Fault.beforeWrite, .uncertainAfterWrite, .readbackMismatch] {
        c.run("session write fault \(fault) never publishes success") {
            let (value, store) = loaded(); store.fault = fault
            let result = edit(value, .skip(release))
            let expected: PreferenceRefusal = fault == .beforeWrite ? .unavailable : (fault == .readbackMismatch ? .readback : .uncertain)
            try require(result == .refused(expected), "fault was not diagnosed")
            try require(value.acceptedRevision == 0, "optimistic publication")
            if fault == .beforeWrite { try require(store.bytes == Data(emptyLiteral.utf8), "known failure changed original") }
            else {
                _ = enqueue(value)
                try require(!isStarted(start(value)), "uncertain preference allowed start")
                store.clearFault()
                try require(value.reload(generation: generation) == .accepted(revision: 1), "explicit validated reload required")
            }
        }
    }
    c.run("lost acknowledgement reload replay and conflicting ID") {
        let (value, store) = loaded(); store.fault = .lostAcknowledgement
        try require(edit(value, .skip(release)) == .refused(.uncertain), "lost reply diagnosed")
        store.clearFault()
        try require(value.reload(generation: generation) == .accepted(revision: 1), "reload")
        let bytes = store.bytes; let writes = store.writes
        try require(edit(value, .skip(release), revision: 0) == .replayed(revision: 1), "idempotent replay inverted change")
        try require(store.bytes == bytes && store.writes == writes, "replay wrote again")
        try require(edit(value, .undo(release), revision: 1) == .refused(.conflict), "conflicting mutation ID accepted")
        try require(store.bytes == bytes, "conflicting operation erased history")
    }
    c.run("stale CAS exact bytes block optimistic acceptance") {
        let (value, store) = loaded(); let foreign = fixtureBytes(revision: 1, skips: [candidate(version: "3")]); store.bytes = foreign
        try require(edit(value, .skip(release)) == .refused(.conflict), "stale CAS accepted")
        try require(value.acceptedRevision == 0 && store.bytes == foreign, "conflict overwrote durable state")
    }
    for corrupt in [Data("{".utf8), Data(), fixtureBytes(principal: "foreign-owner")] {
        c.run("corrupt existing record refuses and preserves \(corrupt.count)") {
            let store = MemoryStore(bytes: corrupt); let value = session(store)
            try require(value.reload(generation: generation) == .refused(.malformed), "corrupt reload diagnosis")
            try require(store.bytes == corrupt && store.writes == 0 && !isStarted(start(value)), "corrupt reset/start")
        }
    }
    c.run("deletion after prior acknowledgement blocks starts") {
        let (value, store) = loaded(); store.bytes = nil
        try require(value.reload(generation: generation) == .refused(.missing), "deleted record reset")
        try require(!isStarted(start(value)) && store.writes == 0, "deleted preferences started/reset")
    }
    c.run("revision overflow preserves bytes") {
        let original = fixtureBytes(revision: UInt64.max); let (value, store) = loaded(original)
        try require(edit(value, .skip(release), revision: UInt64.max) == .refused(.revisionOverflow), "revision wrapped")
        try require(store.bytes == original && store.writes == 0, "overflow mutated store")
    }
    c.run("full idempotency history refuses new edit without eviction") {
        let original = fixtureBytes(mutations: (0..<128).map { ("id-\($0)", .skip(release)) }); let (value, store) = loaded(original)
        try require(edit(value, .skip(release)) == .refused(.limit), "history silently evicted")
        try require(store.bytes == original && store.writes == 0, "history altered")
        try require(edit(value, .skip(release), id: "id-0") == .replayed(revision: 0), "old retained replay refused")
    }
    c.run("exclusion set full refuses additional key but permits removal") {
        let keys = (0..<256).map { PreferenceAppKey(product: "key-\($0)", scope: "user", edition: "standard", channel: "stable") }
        let original = fixtureBytes(exclusions: keys); let (value, store) = loaded(original)
        try require(edit(value, .exclusion(PreferenceAppKey(release), true)) == .refused(.limit), "exclusion limit bypassed")
        try require(store.bytes == original && store.writes == 0, "exclusion overflow changed record")
        try require(edit(value, .exclusion(keys[0], false), id: "remove") == .accepted(revision: 1), "full set cannot remove")
    }
    c.run("skip set full refuses additional identity but permits undo") {
        let identities = (0..<512).map { candidate(version: "v-\($0)") }
        let original = fixtureBytes(skips: identities); let (value, store) = loaded(original)
        try require(edit(value, .skip(release)) == .refused(.limit), "skip limit bypassed")
        try require(store.bytes == original && store.writes == 0, "skip overflow changed record")
        try require(edit(value, .undo(identities[0]), id: "undo") == .accepted(revision: 1), "full set cannot undo")
    }
    for id in ["", "bad\0id", "bad\nid", String(repeating: "x", count: 257)] {
        c.run("invalid mutation ID refuses exact previous bytes \(id.utf8.count)") {
            let (value, store) = loaded()
            try require(edit(value, .skip(release), id: id) == .refused(.identity), "invalid mutation ID accepted")
            try require(store.bytes == Data(emptyLiteral.utf8) && store.writes == 0, "invalid ID wrote")
        }
    }
    c.run("mutation ID exact 256 UTF8 bytes accepted") {
        let (value, store) = loaded(); let id = String(repeating: "é", count: 128)
        try require(edit(value, .skip(release), id: id) == .accepted(revision: 1), "maximum mutation ID refused")
        try require(store.bytes == fixtureBytes(revision: 1, skips: [release], mutations: [(id, .skip(release))]), "ID canonical retention")
    }
    for principal in [SchedulingPrincipal(""), SchedulingPrincipal("foreign-owner")] {
        c.run("invalid/foreign session principal \(principal.value)") {
            let store = MemoryStore(bytes: fixtureBytes()); let value = session(store, principal: principal)
            try require(value.reload(generation: generation) == .refused(.malformed), "owner not bound")
            try require(store.writes == 0 && !isStarted(start(value)), "foreign owner side effect")
        }
    }
    c.run("wrong store scope refuses exact existing bytes") {
        let store = MemoryStore(bytes: fixtureBytes()); let value = session(store, scope: "foreign-store")
        try require(value.reload(generation: generation) == .refused(.malformed), "store scope not bound")
        try require(store.bytes == Data(emptyLiteral.utf8) && store.writes == 0, "foreign store altered")
    }
    c.run("truncation/replacement after accepted state blocks new starts") {
        let (value, store) = loaded(); try require(enqueue(value), "enqueue")
        store.bytes = Data("{".utf8)
        try require(value.reload(generation: generation) == .refused(.malformed), "truncation not diagnosed")
        try require(!isStarted(start(value)), "truncated record permitted start")
        store.bytes = fixtureBytes(principal: "foreign-owner")
        try require(value.reload(generation: generation) == .refused(.malformed), "replacement not diagnosed")
        try require(!isStarted(start(value)), "replacement permitted start")
    }
}
