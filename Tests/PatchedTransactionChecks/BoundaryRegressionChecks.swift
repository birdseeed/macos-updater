import Foundation
import Darwin
@_spi(Testing) import PatchedCore

// PAT-2582 phase 2C. Held path identity of the incoming side, the root marker, a fault inside an
// explicit restore decision, and a failure after the commit record's rename. Every actor below runs
// inside a real transaction at a real boundary, on unsigned bundles that cannot be run.

private enum Outcome { case refused(TransactionFailure), accepted(TransactionReport) }

/// Collects every broken expectation of one case, so an improper acceptance is reported with its physical effect.
private final class Findings {
    private var messages: [String] = []
    func verify(_ body: () throws -> Void) { do { try body() } catch { messages.append("\(error)") } }
    func finish() throws { if !messages.isEmpty { throw CheckFailure(description: messages.joined(separator: " | ")) } }
}

/// Runs a real transaction whose actor acts once at `boundary`. An actor that fails, or a boundary
/// that is never reached, is a setup failure and is never counted as a refusal.
private func performActing(_ authority: FixtureAuthority, _ prepared: Prepared, at boundary: TransactionBoundary,
                           _ actor: @escaping () throws -> Void) throws -> (outcome: Outcome, later: [String]) {
    var reached = 0, setup: Error?, later: [String] = []
    let hooks = idle(boundary: {
        if reached > 0 { later.append($0.rawValue) }
        guard $0 == boundary else { return }
        reached += 1
        do { try actor() } catch { setup = error; throw error }
    })
    let outcome: Outcome
    do { outcome = .accepted(try authority.perform(prepared.request, hooks: hooks)) }
    catch let error as TransactionFailure { outcome = .refused(error) }
    if let setup { throw CheckFailure(description: "SETUP FAILURE: actor at \(boundary.rawValue) failed: \(setup)") }
    try expect(reached == 1, "SETUP FAILURE: actor boundary \(boundary.rawValue) was reached \(reached) times")
    return (outcome, later)
}
/// The transaction refused with `reason` at the actor's boundary, returned no report and left the old target as it was.
private func expectRefusal(_ result: (outcome: Outcome, later: [String]), _ reason: TransactionFailure, _ layout: Layout,
                           old: [Entry], _ findings: Findings) {
    findings.verify {
        switch result.outcome {
        case .accepted(let report):
            throw CheckFailure(description: "IMPROPER ACCEPTANCE: expected refusal \(reason.rawValue), received a \(report.state.rawValue) " +
                               "report after continuing through \(result.later.joined(separator: ","))")
        case .refused(let error):
            try expect(error == reason, "Expected \(reason.rawValue), received \(error.rawValue)")
            try expect(result.later.isEmpty, "Refused only after continuing through \(result.later.joined(separator: ","))")
        }
    }
    findings.verify { try expectSame(old, try walk(layout.target.path), "Old target identity or bytes changed") }
}
private func marker(_ layout: Layout) -> URL { layout.root.appendingPathComponent("fixture-root.json") }
/// Rewrites a file through its existing inode. Nothing is renamed or replaced.
private func overwriteInPlace(_ data: Data, _ url: URL) throws {
    let descriptor = open(url.path, O_WRONLY | O_TRUNC | O_NOFOLLOW)
    guard descriptor >= 0 else { throw CheckFailure(description: "Fixture open failed: \(url.path)") }
    defer { close(descriptor) }
    let written = data.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
    guard written == data.count else { throw CheckFailure(description: "Fixture write failed: \(url.path)") }
}

@MainActor func registerBoundaryRegressionChecks() {
    check("incoming directory substituted at journalPrepared refuses, the decoy stays empty and the moved input is unchanged") {
        try withRoot { authority, layout in
            let prepared = try seeded(layout)
            let oldTree = try walk(layout.target.path), input = try walk(layout.incoming.path)
            let other = try walk(layout.other.path), profile = try walk(layout.profile.path)
            let moved = layout.root.appendingPathComponent("Incoming-moved"), findings = Findings()
            var decoy: [Entry] = []
            let result = try performActing(authority, prepared, at: .journalPrepared) {
                try move(layout.incoming, moved)
                guard mkdir(layout.incoming.path, 0o700) == 0 else { throw CheckFailure(description: "Decoy Incoming was not exclusively created") }
                try setMode(layout.incoming, 0o700)
                decoy = try walk(layout.incoming.path)
            }
            try expect(decoy.count == 1 && decoy[0].mode == 0o700 && decoy[0].inode != input[0].inode, "SETUP FAILURE: decoy Incoming is not a new empty 0700 directory")
            expectRefusal(result, .identityChanged, layout, old: oldTree, findings)
            findings.verify { try expectSame(decoy, try walk(layout.incoming.path), "Substituted Incoming was written into or replaced") }
            findings.verify { try expectSame(input, try walk(moved.path), "Original incoming tree changed after its directory was renamed") }
            findings.verify { try expectSame(other, try walk(layout.other.path), "Unrelated app changed") }
            findings.verify { try expectSame(profile, try walk(layout.profile.path), "Dummy profile changed") }
            try findings.finish()
        }
    }
    check("source bundle substituted at stageVerified refuses, the decoy and the moved source are unchanged") {
        try withRoot { authority, layout in
            let prepared = try seeded(layout)
            let oldTree = try walk(layout.target.path), source = try walk(layout.source.path)
            let other = try walk(layout.other.path), profile = try walk(layout.profile.path)
            let moved = layout.incoming.appendingPathComponent("Source-moved.app"), findings = Findings()
            var decoy: [Entry] = []
            let result = try performActing(authority, prepared, at: .stageVerified) {
                try move(layout.source, moved)
                try writeBundle(layout.source, bundleID: Sample.bundleID, version: Sample.newVersion, label: "decoy")
                decoy = try walk(layout.source.path)
            }
            try expect(!decoy.isEmpty && decoy[0].inode != source[0].inode && content(decoy) != content(source),
                       "SETUP FAILURE: decoy source is not a fresh bundle with different bytes")
            expectRefusal(result, .identityChanged, layout, old: oldTree, findings)
            findings.verify { try expectSame(decoy, try walk(layout.source.path), "Decoy source bundle was changed by the transaction") }
            findings.verify { try expectSame(source, try walk(moved.path), "Original source bundle identity or bytes changed after it was renamed") }
            findings.verify { try expectSame(other, try walk(layout.other.path), "Unrelated app changed") }
            findings.verify { try expectSame(profile, try walk(layout.profile.path), "Dummy profile changed") }
            try findings.finish()
        }
    }
    check("artifact substituted at swapIntended refuses, the decoy and the moved artifact are unchanged") {
        try withRoot { authority, layout in
            let prepared = try seeded(layout)
            let oldTree = try walk(layout.target.path), artifact = try walk(layout.artifact.path)
            let other = try walk(layout.other.path), profile = try walk(layout.profile.path)
            let moved = layout.incoming.appendingPathComponent("manifest-moved.json"), findings = Findings()
            var decoy: [Entry] = []
            let result = try performActing(authority, prepared, at: .swapIntended) {
                try move(layout.artifact, moved)
                try writeFile(Data("{\"decoy\":true}\n".utf8), layout.artifact, mode: 0o600)
                decoy = try walk(layout.artifact.path)
            }
            try expect(decoy.count == 1 && decoy[0].type == "file" && decoy[0].mode == 0o600 && decoy[0].inode != artifact[0].inode &&
                       decoy[0].sha != artifact[0].sha, "SETUP FAILURE: decoy artifact is not a fresh different 0600 file")
            expectRefusal(result, .identityChanged, layout, old: oldTree, findings)
            findings.verify { try expectSame(decoy, try walk(layout.artifact.path), "Decoy artifact bytes, inode or mode were changed by the transaction") }
            findings.verify { try expectSame(artifact, try walk(moved.path), "Original artifact bytes or inode changed after it was renamed") }
            findings.verify { try expectSame(other, try walk(layout.other.path), "Unrelated app changed") }
            findings.verify { try expectSame(profile, try walk(layout.profile.path), "Dummy profile changed") }
            try findings.finish()
        }
    }

    // Guard for the handle that is running. It does not claim that a fresh authority detects a
    // same-user process that rewrites the marker consistently.
    check("root marker replaced by a new file with the same bytes at journalPrepared refuses the running transaction") {
        try withRoot { authority, layout in
            let prepared = try seeded(layout)
            let oldTree = try walk(layout.target.path), original = try walk(marker(layout).path)
            let retained = layout.root.appendingPathComponent("fixture-root.retained.json"), findings = Findings()
            var replacement: [Entry] = []
            let result = try performActing(authority, prepared, at: .journalPrepared) {
                let bytes = try Data(contentsOf: marker(layout))
                try move(marker(layout), retained)
                try writeFile(bytes, marker(layout), mode: 0o600)
                replacement = try walk(marker(layout).path)
            }
            try expect(replacement.count == 1 && replacement[0].inode != original[0].inode && content(replacement) == content(original),
                       "SETUP FAILURE: replacement marker is not a new 0600 file with the exact original bytes")
            expectRefusal(result, .identityChanged, layout, old: oldTree, findings)
            findings.verify { try expectSame(original, try walk(retained.path), "Retained original marker changed") }
            findings.verify { try expectSame(replacement, try walk(marker(layout).path), "Replacement marker was changed by the transaction") }
            try findings.finish()
        }
    }
    check("root marker contents corrupted through the same inode at stageSynced refuse as notAuthorized") {
        let corruptions: [(String, (String, UInt64) -> String)] = [
            ("kind", { text, _ in text.replacingOccurrences(of: "patched-transaction-fixture-root-v1", with: "patched-transaction-fixture-root-v2") }),
            ("inode", { text, inode in text.replacingOccurrences(of: "\"inode\":\(inode)", with: "\"inode\":\(inode + 1)") })
        ]
        for (field, corrupt) in corruptions {
            try withRoot { authority, layout in
                let prepared = try seeded(layout)
                let oldTree = try walk(layout.target.path), original = try walk(marker(layout).path), findings = Findings()
                var corrupted: [Entry] = []
                let result = try performActing(authority, prepared, at: .stageSynced) {
                    let bytes = try Data(contentsOf: marker(layout))
                    guard let inode = unsigned(try object(bytes)["inode"]) else { throw CheckFailure(description: "Marker records no inode") }
                    try overwriteInPlace(Data(corrupt(String(decoding: bytes, as: UTF8.self), inode).utf8), marker(layout))
                    corrupted = try walk(marker(layout).path)
                }
                try expect(corrupted.count == 1 && corrupted[0].inode == original[0].inode && corrupted[0].mode == 0o600 &&
                           corrupted[0].sha != original[0].sha, "SETUP FAILURE: marker \(field) was not changed through its own inode")
                expectRefusal(result, .notAuthorized, layout, old: oldTree, findings)
                findings.verify { try expectSame(corrupted, try walk(marker(layout).path), "Transaction repaired or rewrote the corrupted marker (\(field))") }
                try findings.finish()
            }
        }
    }

    // The original checks interrupt `recover`. These interrupt the explicit decision itself.
    for boundary in [TransactionBoundary.beforeSwapBack, .swappedBack] {
        check("fault in explicit restore-old decision at \(boundary.rawValue): commit withdrawn first, a separate process recovers the old bundle") {
            try withRoot { authority, layout in
                let prepared = try seeded(layout)
                let oldTree = try walk(layout.target.path), others = try unrelated(layout)
                let committed = try authority.perform(prepared.request, hooks: idle())
                let newTree = try walk(layout.target.path)
                try expect(committed.state == .committed && (try journalState(layout)) == "committed" && (try walk(layout.exchanged.path)) == oldTree,
                           "SETUP FAILURE: no committed transaction to decide on")
                let log = EventLog()
                var withdrawn: String?, targetAtWithdrawal: [Entry] = []
                try refuses(.persistenceFailed) {
                    _ = try authority.decide(.restoreOld, transactionDirectory: layout.transaction.path, trigger: .explicitUserAction, hooks: idle(boundary: {
                        log.events.append("b:" + $0.rawValue)
                        if $0 == .beforeSwapBack { withdrawn = try journalState(layout); targetAtWithdrawal = try walk(layout.target.path) }
                        if $0 == boundary { throw Injected() }
                    }, sync: { log.events.append("s:" + $0.rawValue) }))
                }
                try expect(log.events.last == "b:" + boundary.rawValue, "Decision did not stop at the injected fault: \(log.events)")
                try expect(withdrawn == "swapIntended", "Commit was not withdrawn in the journal before the exchange: \(withdrawn ?? "unread")")
                try expectSame(newTree, targetAtWithdrawal, "Exchange preceded the withdrawal of the commit")
                guard let before = log.index("b:beforeSwapBack"), let file = log.index("s:journalFileFullSync"),
                      let directory = log.index("s:journalDirectorySync"), file < directory, directory < before else {
                    throw CheckFailure(description: "Withdrawal record was not flushed before the exchange: \(log.events)")
                }
                try expect(try journalState(layout) == "swapIntended", "Interrupted decision recorded a final state")
                let restored = try walk(layout.target.path) == oldTree
                try expect(restored == (boundary == .swappedBack), "Swap-back state does not match the interrupted boundary")
                if !restored {
                    try expectSame(newTree, try walk(layout.target.path), "Refused decision altered the target")
                    try expectSame(oldTree, try walk(layout.exchanged.path), "Refused decision altered the retained old bundle")
                }
                let (code, output) = try boundedChild(["--recover-probe", layout.root.path])
                let action = restored ? "oldAlreadyInPlace" : "restoredOldBySwap"
                try expect(code == 0 && output.contains("state=rolledBack action=\(action) " + noTrustSuffix), "Separate-process recovery differs: \(output)")
                try expect(try journalState(layout) == "rolledBack", "Recovery was not recorded durably")
                try expectSame(oldTree, try walk(layout.target.path), "Original bundle identity and bytes were not restored")
                try expectSame(newTree, try walk(layout.exchanged.path), "New staged bundle was not retained exactly")
                try expectSame(others, try unrelated(layout), "Unrelated app, dummy profile or incoming bytes changed")
            }
        }
    }

    // Acknowledged limitation, not a durability claim: the commit record is visible once it is
    // renamed. When the directory synchronisation after that rename fails, `perform` reports nothing,
    // yet a later `recover` reads the visible record and reports `committed`. No hardware or
    // power-loss guarantee is made for that record.
    check("failure at the final journalDirectorySync: perform reports nothing, the visible commit record is recovered as committed") {
        var syncs = 0
        try withRoot { authority, layout in
            _ = try authority.perform(try seeded(layout).request, hooks: idle(sync: { if $0 == .journalDirectorySync { syncs += 1 } }))
        }
        try expect(syncs >= 4, "SETUP FAILURE: a complete transaction synchronised the journal directory fewer than four times")
        try withRoot { authority, layout in
            let prepared = try seeded(layout)
            let oldTree = try walk(layout.target.path), newTree = try walk(layout.source.path), others = try unrelated(layout)
            var seen = 0, thrown = 0
            try refuses(.persistenceFailed) {
                _ = try authority.perform(prepared.request, hooks: idle(sync: {
                    if $0 == .journalDirectorySync { seen += 1; if seen == syncs { thrown += 1; throw Injected() } }
                }))
            }
            try expect(thrown == 1 && seen == syncs, "Transaction continued after the refused final journalDirectorySync")
            try expectContent(newTree, try walk(layout.target.path), "Target is not the complete new bundle")
            try expectSame(oldTree, try walk(layout.exchanged.path), "Old bundle is not retained whole in the exchange directory")
            try expect(try topLevel(layout.transaction) == ["after-manifest.json", "before-manifest.json", "exchange", "journal.json", "lock"],
                       "Transaction directory differs from the contract")
            let fields = try journalFields(layout), info = try status(layout.journal)
            try expect(Set(fields.keys) == journalKeys && unsigned(fields["schemaVersion"]) == 1 &&
                       fields["kind"] as? String == "patched-fixture-transaction-journal-v1" && fields["state"] as? String == "committed" &&
                       fields["origin"] as? String == "fixture" && info.st_mode & 0o7777 == 0o600 && info.st_nlink == 1,
                       "Visible journal is not a strict committed record")
            let whole = try walk(layout.root.path)
            let report = try FixtureAuthority.reopenRoot(path: layout.root.path).recover(transactionDirectory: layout.transaction.path, hooks: idle())
            try expect(report.state == .committed && report.recoveryAction == RecoveryAction.none, "Visible commit record recovered as \(report.state.rawValue)")
            try expectManifest(report.before, oldTree, "Recovered before manifest"); try expectManifest(report.after, newTree, "Recovered after manifest")
            try expectManifest(report.targetNow, newTree, "Recovered target"); try expectManifest(report.exchangeNow, oldTree, "Recovered exchange")
            try expectFixtureOnly(report)
            let (code, output) = try boundedChild(["--recover-probe", layout.root.path])
            try expect(code == 0 && output.contains("state=committed action=none " + noTrustSuffix), "Separate process disagreed: \(output)")
            try expectSame(whole, try walk(layout.root.path), "Recovery of the visible commit record changed physical state")
            try expectSame(oldTree, try walk(layout.exchanged.path), "Old bundle was not retained whole")
            try expectSame(others, try unrelated(layout), "Unrelated app, dummy profile or incoming bytes changed")
        }
    }
}
