import Foundation
import Darwin
@_spi(Testing) import PatchedCore

/// A real interrupted transaction whose evidence is then damaged. Recovery by a fresh authority
/// must refuse with the named reason and leave every physical path exactly as it found it.
@MainActor func recoveryHazard(_ name: String, _ reason: TransactionFailure, at boundary: TransactionBoundary = .swapped,
                               _ damage: @escaping (Layout) throws -> Void) {
    check("recovery: \(name) fails closed with \(reason.rawValue) and restores nothing") {
        try withRoot { authority, layout in
            _ = try interrupted(authority, layout, at: boundary)
            try damage(layout)
            let snapshot = try walk(layout.root.path)
            let fresh = try FixtureAuthority.reopenRoot(path: layout.root.path)
            try refuses(reason) { _ = try fresh.recover(transactionDirectory: layout.transaction.path, hooks: idle()) }
            try expectSame(snapshot, try walk(layout.root.path), "Refused recovery changed physical state")
        }
    }
}
func rawJournal(_ layout: Layout, _ edit: (Data) -> Data) throws {
    try writeFile(edit(try Data(contentsOf: layout.journal)), layout.journal, mode: 0o600)
}

@MainActor func registerRecoveryChecks() {
    recoveryHazard("missing journal", .journalMissing) { try FileManager.default.removeItem(at: $0.journal) }
    recoveryHazard("journal truncated midway", .journalCorrupt) { layout in try rawJournal(layout) { $0.prefix($0.count / 2) } }
    recoveryHazard("empty journal", .journalCorrupt) { layout in try rawJournal(layout) { _ in Data() } }
    recoveryHazard("journal that is not JSON", .journalCorrupt) { layout in try rawJournal(layout) { _ in Data("committed".utf8) } }
    recoveryHazard("journal with a duplicate key", .journalCorrupt) { layout in
        try rawJournal(layout) { Data("{\"state\":\"committed\",".utf8) + $0.dropFirst() } }
    recoveryHazard("journal with trailing bytes", .journalCorrupt) { layout in try rawJournal(layout) { $0 + Data("{}".utf8) } }
    recoveryHazard("journal above its size bound", .journalCorrupt) { layout in
        try rawJournal(layout) { $0 + Data(repeating: 0x20, count: TransactionLimits.maximumJournalBytes) } }
    recoveryHazard("journal with an unknown field", .journalCorrupt) { try editJournal($0) { $0["installationAuthorized"] = true } }
    recoveryHazard("journal with a missing field", .journalCorrupt) { try editJournal($0) { $0["oldInode"] = nil } }
    recoveryHazard("journal with an unknown state", .journalCorrupt) { try editJournal($0) { $0["state"] = "accepted" } }
    recoveryHazard("journal with an unknown schema version", .journalCorrupt) { try editJournal($0) { $0["schemaVersion"] = 2 } }
    recoveryHazard("journal claiming a non-fixture origin", .journalCorrupt) { try editJournal($0) { $0["origin"] = "live" } }

    recoveryHazard("journal naming an unrelated app as target", .journalMismatch) { layout in try editJournal(layout) { $0["targetPath"] = layout.other.path } }
    recoveryHazard("journal naming the ordinary applications directory", .journalMismatch) { try editJournal($0) { $0["targetPath"] = "/Applications/" + Sample.bundleName } }
    recoveryHazard("journal naming another exchange path", .journalMismatch) { layout in try editJournal(layout) { $0["exchangePath"] = layout.source.path } }
    recoveryHazard("journal for another bundle identifier", .journalMismatch) { try editJournal($0) { $0["bundleID"] = "im.patched.fixture.unrelated" } }
    recoveryHazard("journal for another before-manifest digest", .journalMismatch) { try editJournal($0) { $0["beforeManifestSHA256"] = String(repeating: "0", count: 64) } }
    recoveryHazard("journal for another old tree digest", .journalMismatch) { try editJournal($0) { $0["beforeTreeSHA256"] = String(repeating: "0", count: 64) } }
    recoveryHazard("journal for another new version", .journalMismatch) { try editJournal($0) { $0["toVersion"] = "158.0" } }
    recoveryHazard("changed frozen before manifest", .journalMismatch) { layout in
        let file = layout.transaction.appendingPathComponent("before-manifest.json")
        var bytes = try Data(contentsOf: file); bytes[bytes.count / 2] ^= 1; try writeFile(bytes, file, mode: 0o600) }
    recoveryHazard("missing frozen after manifest", .journalMismatch) { try FileManager.default.removeItem(at: $0.transaction.appendingPathComponent("after-manifest.json")) }

    // Identities or bytes that match neither recorded bundle are never chosen between automatically.
    recoveryHazard("journal with another old identity", .ambiguousState) { try editJournal($0) { $0["oldInode"] = (unsigned($0["oldInode"]) ?? 0) + 1 } }
    recoveryHazard("journal with another new identity", .ambiguousState) { try editJournal($0) { $0["newInode"] = (unsigned($0["newInode"]) ?? 0) + 1 } }
    recoveryHazard("commit claimed although the old bundle is still the target", .ambiguousState, at: .stageVerified) { try editJournal($0) { $0["state"] = "committed" } }
    recoveryHazard("retained old bundle with one changed byte", .ambiguousState) { layout in
        let file = resource(layout.exchanged, "data.bin")
        var bytes = try Data(contentsOf: file); bytes[0] ^= 1; try writeFile(bytes, file) }
    recoveryHazard("retained old bundle with an extra file", .ambiguousState) { try writeFile(Data("extra".utf8), resource($0.exchanged, "extra.txt")) }
    recoveryHazard("new bundle at the target with one changed byte", .ambiguousState) { layout in
        let file = resource(layout.target, "data.bin")
        var bytes = try Data(contentsOf: file); bytes[0] ^= 1; try writeFile(bytes, file) }
    recoveryHazard("target replaced by a third bundle", .ambiguousState) { layout in
        try move(layout.target, layout.applications.appendingPathComponent("Moved.app"))
        try writeBundle(layout.target, bundleID: Sample.bundleID, version: Sample.oldVersion, label: "third") }
    recoveryHazard("target missing", .ambiguousState) { try move($0.target, $0.applications.appendingPathComponent("Moved.app")) }
    recoveryHazard("retained old bundle missing", .ambiguousState) { try move($0.exchanged, $0.exchange.appendingPathComponent("Moved.app")) }
    recoveryHazard("old bundle changed before any swap", .ambiguousState, at: .stageVerified) { layout in
        let file = resource(layout.target, "data.bin")
        var bytes = try Data(contentsOf: file); bytes[0] ^= 1; try writeFile(bytes, file) }

    // Evidence files and directories keep the same physical rules as the transaction itself.
    recoveryHazard("journal replaced by a symlink", .symlink) { layout in
        let moved = layout.transaction.appendingPathComponent("journal-real.json")
        try move(layout.journal, moved); try symlinkTo(moved, at: layout.journal) }
    recoveryHazard("hardlinked journal", .hardlink) { try hardlink($0.journal, at: $0.profile.appendingPathComponent("journal-alias.json")) }
    recoveryHazard("journal that is a FIFO", .specialFile) { layout in
        try move(layout.journal, layout.transaction.appendingPathComponent("journal-real.json"))
        try expect(mkfifo(layout.journal.path, 0o600) == 0, "Fixture FIFO failed") }
    recoveryHazard("group-readable journal", .unsafeMode) { try setMode($0.journal, 0o640) }
    recoveryHazard("transaction directory that is not private", .unsafeMode) { try setMode($0.transaction, 0o755) }
    recoveryHazard("exchange directory replaced by a symlink", .symlink) { layout in
        let moved = layout.transaction.appendingPathComponent("exchange-real")
        try move(layout.exchange, moved); try symlinkTo(moved, at: layout.exchange) }
    recoveryHazard("transaction directory replaced by a symlink", .symlink) { layout in
        let moved = layout.root.appendingPathComponent("Transaction-real")
        try move(layout.transaction, moved); try symlinkTo(moved, at: layout.transaction) }
    recoveryHazard("applications ancestor replaced by a symlink", .symlink) { layout in
        let moved = layout.root.appendingPathComponent("Applications-real")
        try move(layout.applications, moved); try symlinkTo(moved, at: layout.applications) }
    recoveryHazard("symlink inside the retained old bundle", .symlink) { try symlinkTo($0.profile.appendingPathComponent("prefs.js"), at: resource($0.exchanged, "link")) }

    check("recovery with no transaction directory refuses and creates nothing") {
        try withRoot { authority, layout in
            _ = try seeded(layout)
            let snapshot = try walk(layout.root.path)
            try refuses(.journalMissing) { _ = try authority.recover(transactionDirectory: layout.transaction.path, hooks: idle()) }
            try expectSame(snapshot, try walk(layout.root.path), "Refused recovery created state")
        }
    }
    check("recovery named at another directory is not authorised") {
        try withRoot { authority, layout in
            _ = try interrupted(authority, layout, at: .swapped)
            let snapshot = try walk(layout.root.path)
            for path in [layout.applications.path, layout.root.path, "/Applications", layout.transaction.path + "/exchange"] {
                try refuses(.notAuthorized) { _ = try authority.recover(transactionDirectory: path, hooks: idle()) }
            }
            try refuses(.unsafePath) { _ = try authority.recover(transactionDirectory: layout.root.path + "/Transaction/../Transaction", hooks: idle()) }
            try expectSame(snapshot, try walk(layout.root.path), "Refused recovery changed physical state")
        }
    }
    check("single writer: recovery refuses while this process holds the transaction lock") {
        try withRoot { authority, layout in
            _ = try interrupted(authority, layout, at: .swapped)
            let snapshot = try walk(layout.root.path)
            let descriptor = open(layout.lock.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
            try expect(descriptor >= 0 && flock(descriptor, LOCK_EX | LOCK_NB) == 0, "Check could not hold the real transaction lock")
            defer { close(descriptor) }
            try refuses(.busy) { _ = try FixtureAuthority.reopenRoot(path: layout.root.path).recover(transactionDirectory: layout.transaction.path, hooks: idle()) }
            try refuses(.busy) {
                _ = try authority.decide(.restoreOld, transactionDirectory: layout.transaction.path, trigger: .explicitUserAction, hooks: idle())
            }
            try expectSame(snapshot, try walk(layout.root.path), "Contended recovery changed physical state")
        }
    }
    check("single writer: a separate process is refused while the lock is held, then recovers once it is released") {
        try withRoot { authority, layout in
            _ = try interrupted(authority, layout, at: .swapped)
            let oldTree = try walk(layout.exchanged.path), snapshot = try walk(layout.root.path)
            let descriptor = open(layout.lock.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
            try expect(descriptor >= 0 && flock(descriptor, LOCK_EX | LOCK_NB) == 0, "Check could not hold the real transaction lock")
            let (held, heldOutput) = try boundedChild(["--recover-probe", layout.root.path])
            try expect(held == 1 && heldOutput.contains("refused=busy"), "Separate process was not refused: \(heldOutput)")
            try expectSame(snapshot, try walk(layout.root.path), "Contended process changed physical state")
            close(descriptor)
            let (released, output) = try boundedChild(["--recover-probe", layout.root.path])
            try expect(released == 0 && output.contains("state=rolledBack action=restoredOldBySwap " + noTrustSuffix), "Recovery after release differs: \(output)")
            try expectSame(oldTree, try walk(layout.target.path), "Original bundle identity and bytes were not restored")
        }
    }
}
