import Foundation
import Darwin
import PatchedScheduling
@_spi(Testing) import PatchedUpdatePreferences

@MainActor func nativeStoreChecks(_ c: Checks) {
    nativeStoreBoundaryChecks(c)
    nativeStoreSelectorBoundaryChecks(c)
    let maximum = PreferenceRecord.maximumBytes
    let old = Data(emptyLiteral.utf8)
    let next = fixtureBytes(revision: 1)
    c.run("NS setup kernel executable root and independent owned bytes", setup: true) {
        let f = try NativeStoreFixture(); defer { try? f.cleanup() }
        try require(f.url.deletingLastPathComponent() == (try NativeStoreFixture.buildDirectory()), "wrong build root")
        try f.seed(old); try require((try f.bytes()) == old, "seed observation")
        var info = stat(); try require(fstatat(f.fd, "record.json", &info, AT_SYMLINK_NOFOLLOW) == 0 &&
            info.st_uid == getuid() && info.st_nlink == 1 && info.st_mode & 0o777 == 0o600, "seed private file")
    }
    c.run("NS setup independent symlink hardlink FIFO and lock fixtures", setup: true) {
        let f = try NativeStoreFixture(); defer { try? f.cleanup() }; try f.seed(old)
        try require(linkat(f.fd, "record.json", f.fd, "alias", 0) == 0, "hardlink fixture")
        var info = stat(); try require(fstatat(f.fd, "alias", &info, AT_SYMLINK_NOFOLLOW) == 0 && info.st_nlink == 2, "hardlink observation")
        try require(symlinkat("record.json", f.fd, "keep") == 0 && mkfifoat(f.fd, "fifo", 0o600) == 0, "special fixtures")
        try f.seed(Data(), name: "lock")
        let lockFD = openat(f.fd, "lock", O_RDWR | O_NOFOLLOW)
        try require(lockFD >= 0 && flock(lockFD, LOCK_EX | LOCK_NB) == 0, "independent lock")
        defer { flock(lockFD, LOCK_UN); close(lockFD) }
        let other = openat(f.fd, "lock", O_RDWR | O_NOFOLLOW); defer { if other >= 0 { close(other) } }
        try require(other >= 0 && flock(other, LOCK_EX | LOCK_NB) != 0, "lock contention observation")
    }
    c.run("NS ordinary session and coordinator remain refusing") {
        let value = PreferenceSession()
        try require(value.acceptedRevision == nil && value.reload(generation: generation) == .refused(.defaultComposition), "ordinary owner escaped")
        let request = InventorySelectionRequest(principal: owner, identity: ipIdentity(), release: ipRelease(), observedGeneration: 1, preferenceRevision: 0)
        guard case .refused(.unavailable) = VerifiedUpdateCoordinator().requestStart(request, kind: .manual) else {
            throw CheckFailure(message: "coordinator started")
        }
    }
    c.run("NS missing is explicit and read does not bootstrap") {
        let f = try NativeStoreFixture(); defer { try? f.cleanup() }; let store = f.store()
        try require(store.read(maximumBytes: maximum) == .missing, "missing diagnosed incorrectly")
        try require(f.absent(), "read created record")
        let value = nativeFixtureSession(store)
        try require(value.reload(generation: generation) == .refused(.missing) && f.absent(), "reload auto-created")
    }
    c.run("NS explicit createFresh same session persists exact bytes private mode") {
        let f = try NativeStoreFixture(); defer { try? f.cleanup() }; let value = nativeFixtureSession(f.store())
        try require(value.bootstrapFreshFixture(generation: generation) == .accepted(revision: 0), "fresh refused")
        try require((try f.bytes()) == old && value.acceptedRevision == 0, "fresh exact bytes")
        var info = stat(); try require(fstatat(f.fd, "record.json", &info, AT_SYMLINK_NOFOLLOW) == 0 && info.st_mode & 0o777 == 0o600, "record mode")
    }
    c.run("NS reopen separately constructed store loads exact existing record without write") {
        let f = try NativeStoreFixture(); defer { try? f.cleanup() }; try f.seed(old)
        let value = nativeFixtureSession(f.store(), gen: "new-process-generation")
        try require(value.reload(generation: "new-process-generation") == .accepted(revision: 0), "reopen refused")
        try require((try f.bytes()) == old && value.acceptedRevision == 0, "reopen rewrote bytes")
    }
    c.run("NS absent CAS nil and stale two owners enforce exact expected bytes") {
        let f = try NativeStoreFixture(); defer { try? f.cleanup() }; let a = f.store(); let b = f.store()
        try require(a.compareAndSwap(expected: nil, proposed: old, maximumBytes: maximum) == .committed, "missing CAS")
        try require(a.read(maximumBytes: maximum) == .bytes(old) && b.read(maximumBytes: maximum) == .bytes(old), "two owner read")
        try require(a.compareAndSwap(expected: old, proposed: next, maximumBytes: maximum) == .committed, "first owner CAS")
        try require(b.compareAndSwap(expected: old, proposed: fixtureBytes(revision: 2), maximumBytes: maximum) == .conflict, "stale owner won")
        try require(b.compareAndSwap(expected: nil, proposed: old, maximumBytes: maximum) == .conflict && (try f.bytes()) == next, "nil adopted existing")
    }
    for (label, principal, scope) in [("principal", SchedulingPrincipal("foreign"), storeScope), ("scope", owner, "foreign")] {
        c.run("NS existing codec fences \(label) and preserves bytes") {
            let f = try NativeStoreFixture(); defer { try? f.cleanup() }; try f.seed(old)
            let value = nativeFixtureSession(f.store(), principal: principal, scope: scope)
            try require(value.reload(generation: generation) == .refused(.malformed), "binding accepted")
            try require(value.acceptedRevision == nil && (try f.bytes()) == old, "binding reset record")
        }
    }
    for variant in ["symlink", "hardlink", "fifo", "oversize", "mode"] {
        c.run("NS unsafe \(variant) refuses read CAS without adoption") {
            let f = try NativeStoreFixture(); defer { try? f.cleanup() }
            switch variant {
            case "symlink": try f.seed(old, name: "keep"); try require(symlinkat("keep", f.fd, "record.json") == 0, "symlink setup")
            case "fifo": try require(mkfifoat(f.fd, "record.json", 0o600) == 0, "fifo setup")
            case "oversize": try f.seed(Data(repeating: 32, count: maximum + 1))
            case "mode": try f.seed(old); try require(fchmodat(f.fd, "record.json", 0o644, 0) == 0, "mode setup")
            default: try f.seed(old); try require(linkat(f.fd, "record.json", f.fd, "alias", 0) == 0, "hardlink setup")
            }
            let beforeNames = try (try f.names()); var before = stat()
            try require(fstatat(f.fd, "record.json", &before, AT_SYMLINK_NOFOLLOW) == 0, "before identity")
            let store = f.store()
            try require(store.read(maximumBytes: maximum) == .unavailable, "unsafe read")
            try require(store.compareAndSwap(expected: nil, proposed: next, maximumBytes: maximum) == .notCommitted, "unsafe CAS")
            var after = stat(); try require(fstatat(f.fd, "record.json", &after, AT_SYMLINK_NOFOLLOW) == 0 &&
                before.st_ino == after.st_ino && before.st_mode == after.st_mode && before.st_nlink == after.st_nlink && (try f.names()) == beforeNames, "unsafe state adopted")
            if variant == "symlink" { try require((try f.bytes("keep")) == old, "symlink target changed") }
            if variant == "hardlink" || variant == "mode" { try require((try f.bytes()) == old, "unsafe bytes changed") }
        }
    }
    c.run("NS changed parent identity refuses retained adapter and preserves original") {
        let f = try NativeStoreFixture(); defer { try? f.cleanup() }; try f.seed(old); let store = f.store()
        try require(store.read(maximumBytes: maximum) == .bytes(old), "safe prerequisite read")
        let moved = f.name + "-moved"
        try require(renameat(f.parent, f.name, f.parent, moved) == 0, "move root")
        defer { unlinkat(f.parent, f.name, AT_REMOVEDIR); renameat(f.parent, moved, f.parent, f.name) }
        try require(mkdirat(f.parent, f.name, 0o700) == 0, "replacement root")
        try require(store.read(maximumBytes: maximum) == .unavailable && store.compareAndSwap(expected: old, proposed: next, maximumBytes: maximum) == .notCommitted, "changed parent accepted")
        try require((try f.bytes()) == old, "retained original changed")
    }
    c.run("NS cooperative lock contention is bounded refusal with original bytes") {
        let f = try NativeStoreFixture(); defer { try? f.cleanup() }; try f.seed(old); try f.seed(Data(), name: "lock")
        let fd = openat(f.fd, "lock", O_RDWR | O_NOFOLLOW); try require(fd >= 0, "lock open")
        defer { flock(fd, LOCK_UN); close(fd) }; try require(flock(fd, LOCK_EX | LOCK_NB) == 0, "lock owned")
        let store = f.store(); let begin = ProcessInfo.processInfo.systemUptime
        try require(store.compareAndSwap(expected: old, proposed: next, maximumBytes: maximum) == .notCommitted, "contended commit")
        try require(ProcessInfo.processInfo.systemUptime - begin < 1 && (try f.bytes()) == old, "blocking lock or changed bytes")
    }
    for fault in [FixturePreferenceFault.shortWriteThenContinue, .interruptedWriteThenContinue] {
        c.run("NS \(fault.rawValue) writes complete exact bytes") {
            let f = try NativeStoreFixture(); defer { try? f.cleanup() }; try f.seed(old)
            let store = f.store(fault)
            try require(store.compareAndSwap(expected: old, proposed: next, maximumBytes: maximum) == .committed, "recoverable write refused")
            try require(store.exercisedFaults == [fault], "write seam not reached")
            try require((try f.bytes()) == next, "partial proposed record")
        }
    }
    for fault in [FixturePreferenceFault.writeFailure, .fileSync, .fullFlush, .rename] {
        c.run("NS known failure \(fault.rawValue) preserves accepted bytes exact cleanup") {
            let f = try NativeStoreFixture(); defer { try? f.cleanup() }; try f.seed(old); try f.seed(Data("unrelated".utf8), name: "keep")
            let store = f.store(fault)
            try require(store.compareAndSwap(expected: old, proposed: next, maximumBytes: maximum) == .notCommitted, "known failure outcome")
            try require(store.exercisedFaults == [fault], "known-failure seam not reached")
            try require((try f.bytes()) == old && (try f.bytes("keep")) == Data("unrelated".utf8), "known failure changed accepted/unrelated bytes")
            try require(Set((try f.names())).subtracting(["record.json", "keep", "lock"]).isEmpty, "temporary leaked or cleanup scope expanded")
        }
    }
    for fault in [FixturePreferenceFault.directorySync, .afterRename, .readback] {
        c.run("NS postrename \(fault.rawValue) remains uncertain with committed bytes") {
            let f = try NativeStoreFixture(); defer { try? f.cleanup() }; try f.seed(old)
            let store = f.store(fault)
            try require(store.compareAndSwap(expected: old, proposed: next, maximumBytes: maximum) == .uncertain, "postrename uncertainty hidden")
            try require(store.exercisedFaults == [fault], "postrename seam not reached")
            try require((try f.bytes()) == next, "postrename expected bytes absent")
        }
    }
    c.run("NS durable exclusion skip Undo new release and channel reuse same owner") {
        let f = try NativeStoreFixture(); defer { try? f.cleanup() }; try f.seed(old)
        let a = nativeFixtureSession(f.store()); try require(a.reload(generation: generation) == .accepted(revision: 0), "load")
        try require(edit(a, .exclusion(PreferenceAppKey(release), true), id: "exclude") == .accepted(revision: 1), "exclude")
        try require(edit(a, .skip(release), id: "skip", revision: 1) == .accepted(revision: 2), "skip")
        let b = nativeFixtureSession(f.store()); try require(b.reload(generation: generation) == .accepted(revision: 2), "reopen")
        let projection = b.projection([PreferenceCandidate(id: "old", release: .verified(release)), PreferenceCandidate(id: "new", release: .verified(candidate(version: "3"))), PreferenceCandidate(id: "channel", release: .verified(candidate(channel: "beta")))])
        try require(projection.skippedCount == 1 && projection.availableCount == 2 && projection.applications.map(\.automaticExcluded) == [true, true, false], "intent transferred/lost")
        try require(edit(b, .undo(release), id: "undo", revision: 2) == .accepted(revision: 3), "Undo")
        let d = nativeFixtureSession(f.store()); try require(d.reload(generation: generation) == .accepted(revision: 3), "Undo reopen")
        try require(d.projection([PreferenceCandidate(id: "old", release: .verified(release))]).skippedCount == 0, "Undo lost")
    }
    c.run("NS in-flight symbolic completion survives durable preference edit") {
        let f = try NativeStoreFixture(); defer { try? f.cleanup() }; try f.seed(old); let value = nativeFixtureSession(f.store())
        try require(value.reload(generation: generation) == .accepted(revision: 0) && enqueue(value), "queue setup")
        guard case .started(let attempt) = start(value) else { throw CheckFailure(message: "symbolic start") }
        try require(edit(value, .skip(release)) == .accepted(revision: 1), "durable skip")
        try require(value.complete(attempt, principal: owner) && value.state(of: "entry") == .completed, "in-flight interrupted")
    }
    c.run("NS fixture process relaunch observes durable intent in same session type") {
        let f = try NativeStoreFixture(); defer { try? f.cleanup() }
        // Independent literal seed enables the child even while the store implementation refuses.
        try f.seed(fixtureBytes(revision: 2, exclusions: [PreferenceAppKey(release)], skips: [release]))
        try f.seed(Data(), name: "child-output")
        let outputFD = openat(f.fd, "child-output", O_WRONLY | O_NOFOLLOW)
        try require(outputFD >= 0, "child output"); let handle = FileHandle(fileDescriptor: outputFD, closeOnDealloc: true)
        let process = Process(); process.executableURL = try NativeStoreFixture.executable()
        process.arguments = ["--pat-2662-native-store-child", f.url.path]
        process.environment = [:]; process.currentDirectoryURL = try NativeStoreFixture.buildDirectory()
        process.standardOutput = handle; process.standardError = handle
        try process.run(); let begin = ProcessInfo.processInfo.systemUptime
        while process.isRunning {
            var s = stat(); let sizeOK = fstat(outputFD, &s) == 0 && s.st_size <= 131_072
            if !sizeOK || ProcessInfo.processInfo.systemUptime - begin >= 10 {
                process.terminate(); usleep(100_000); if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit(); throw CheckFailure(message: "bounded child timeout/output")
            }
            usleep(10_000)
        }
        process.waitUntilExit()
        try require(process.terminationStatus == 0 && (try f.bytes("child-output")) == Data("PAT2662-FIXTURE-RELAUNCH-OK\n".utf8), "child durable intent refused")
    }
}

@MainActor func nativeStoreBoundaryChecks(_ c: Checks) {
    let maximum = PreferenceRecord.maximumBytes; let old = Data(emptyLiteral.utf8)
    for malformed in [Data("{".utf8), fixtureBytes(principal: "foreign-owner"), fixtureBytes(scope: "foreign-scope")] {
        c.run("NS malformed existing bytes preserved without bootstrap \(malformed.count)") {
            let f = try NativeStoreFixture(); defer { try? f.cleanup() }; try f.seed(malformed)
            let value = nativeFixtureSession(f.store())
            try require(value.reload(generation: generation) == .refused(.malformed), "malformed accepted or unavailable")
            try require(value.bootstrapFreshFixture(generation: generation) == .refused(.conflict), "existing state reset")
            try require((try f.bytes()) == malformed && value.acceptedRevision == nil, "malformed bytes changed")
        }
    }
    c.run("NS existing valid record createFresh conflicts with no replacement") {
        let f = try NativeStoreFixture(); defer { try? f.cleanup() }; try f.seed(old)
        let value = nativeFixtureSession(f.store())
        try require(value.bootstrapFreshFixture(generation: generation) == .refused(.conflict) && (try f.bytes()) == old, "createFresh overwrote existing")
    }
    c.run("NS stale two sessions cannot publish failed exclusion") {
        let f = try NativeStoreFixture(); defer { try? f.cleanup() }; try f.seed(old)
        let a = nativeFixtureSession(f.store()); let b = nativeFixtureSession(f.store())
        try require(a.reload(generation: generation) == .accepted(revision: 0) && b.reload(generation: generation) == .accepted(revision: 0), "two sessions load")
        try require(edit(a, .skip(release), id: "a") == .accepted(revision: 1), "first commit")
        let accepted = try f.bytes()
        try require(edit(b, .exclusion(PreferenceAppKey(release), true), id: "b") == .refused(.conflict), "stale commit accepted")
        try require(b.acceptedRevision == 0 && b.blockedReason == .conflict && (try f.bytes()) == accepted, "optimistic publication or lost winner")
    }
    for fault in [FixturePreferenceFault.directorySync, .afterRename, .readback] {
        c.run("NS uncertain \(fault.rawValue) never publishes session acknowledgement") {
            let f = try NativeStoreFixture(); defer { try? f.cleanup() }; try f.seed(old)
            let store = f.store(fault); let value = nativeFixtureSession(store)
            try require(value.reload(generation: generation) == .accepted(revision: 0), "fault owner load")
            try require(edit(value, .skip(release)) == .refused(.uncertain), "uncertain edit acknowledged")
            try require(store.exercisedFaults == [fault], "uncertain session seam not reached")
            try require(value.acceptedRevision == 0 && value.blockedReason == .uncertain, "optimistic uncertain publication")
            let expected = fixtureBytes(revision: 1, skips: [release], mutations: [("mutation-1", .skip(release))])
            try require((try f.bytes()) == expected, "postrename intent bytes lost")
        }
    }
    c.run("NS root mode change refuses without chmod or adopting existing bytes") {
        let f = try NativeStoreFixture(); defer { fchmod(f.fd, 0o700); try? f.cleanup() }; try f.seed(old)
        let store = f.store(); try require(store.read(maximumBytes: maximum) == .bytes(old), "safe root read")
        try require(fchmod(f.fd, 0o755) == 0, "root mode setup")
        try require(store.read(maximumBytes: maximum) == .unavailable && store.compareAndSwap(expected: old, proposed: old, maximumBytes: maximum) == .notCommitted, "unsafe root accepted")
        var s = stat(); try require(fstat(f.fd, &s) == 0 && s.st_mode & 0o777 == 0o755 && (try f.bytes()) == old, "root silently repaired")
    }
    c.run("NS invalid bound or oversize proposal cannot change accepted bytes") {
        let f = try NativeStoreFixture(); defer { try? f.cleanup() }; try f.seed(old); let store = f.store()
        try require(store.read(maximumBytes: -1) == .unavailable && store.read(maximumBytes: maximum + 1) == .unavailable, "invalid bounds accepted")
        try require(store.compareAndSwap(expected: old, proposed: Data(repeating: 0, count: maximum + 1), maximumBytes: maximum) == .notCommitted && (try f.bytes()) == old, "oversize proposal changed bytes")
    }
    c.run("NS cleanup keeps unrelated lookalike temporary inode") {
        let f = try NativeStoreFixture(); defer { try? f.cleanup() }; try f.seed(old)
        // Deliberately resembles a temp but was not created by the adapter's current CAS.
        let lookalike = "temporary-00000000-0000-0000-0000-000000000000"
        try f.seed(Data("unowned-by-adapter".utf8), name: lookalike)
        defer { unlinkat(f.fd, lookalike, 0) }
        let store = f.store(.rename)
        try require(store.compareAndSwap(expected: old, proposed: fixtureBytes(revision: 1), maximumBytes: maximum) == .notCommitted, "rename fault outcome")
        try require(store.exercisedFaults == [.rename], "cleanup seam not reached")
        try require((try f.bytes(lookalike)) == Data("unowned-by-adapter".utf8) && (try f.bytes()) == old, "broad cleanup deleted unrelated temp")
    }
}


@MainActor func nativeStoreSelectorBoundaryChecks(_ c: Checks) {
    let maximum = PreferenceRecord.maximumBytes; let old = Data(emptyLiteral.utf8)
    c.run("NS raw fixture selector rejects owned same-prefix non-UUID root") {
        let f = try NativeStoreFixture(); defer { try? f.cleanup() }; try f.seed(old)
        let before = try f.names()
        try f.withNonUUIDSelector { selector, renamedURL in
            let store = FilePreferenceStore(fixtureRoot: selector)
            try require(store.read(maximumBytes: maximum) == .unavailable &&
                        store.compareAndSwap(expected: old, proposed: fixtureBytes(revision: 1), maximumBytes: maximum) == .notCommitted,
                        "non-UUID selector accepted")
            try require((try f.bytes()) == old &&
                        (try FileManager.default.contentsOfDirectory(atPath: renamedURL.path).sorted()) == before,
                        "invalid selector changed owned seed or entries")
        }
        try require((try f.bytes()) == old && (try f.names()) == before, "restored selector fixture changed")
    }
    c.run("NS raw fixture selector rejects owned UUID symlink alias") {
        let f = try NativeStoreFixture(); defer { try? f.cleanup() }; try f.seed(old)
        let before = try f.names()
        try f.withOwnedSymlinkSelector { selector in
            let store = FilePreferenceStore(fixtureRoot: selector)
            try require(store.read(maximumBytes: maximum) == .unavailable &&
                        store.compareAndSwap(expected: old, proposed: fixtureBytes(revision: 1), maximumBytes: maximum) == .notCommitted,
                        "symlink selector accepted")
            try require((try f.bytes()) == old && (try f.names()) == before,
                        "selector alias changed actual seed or directory entries")
        }
        try require((try f.bytes()) == old && (try f.names()) == before, "selector alias cleanup changed fixture")
    }
}
