import Foundation
import Darwin
@_spi(Testing) import PatchedCore

let swappedBoundaries: [TransactionBoundary] = [.swapped, .targetParentSynced, .beforeCommitRecord]

/// After a refused transaction the old bundle is either still the named target, or whole in the exchange directory.
func expectOldPreserved(_ layout: Layout, old: [Entry], new: [Entry]) throws -> Bool {
    let target = try walk(layout.target.path)
    if target == old { return false }
    try expectContent(new, target, "Target is neither the old bundle nor the complete new bundle")
    try expectSame(old, try walk(layout.exchanged.path), "Old bundle is not preserved whole in the exchange directory")
    return true
}

@MainActor func registerFaultChecks() {
    for boundary in performBoundaries {
        check("fault at \(boundary.rawValue): no accepted result, old bytes intact or recovered by a separate process") {
            try withRoot { authority, layout in
                let prepared = try seeded(layout)
                let oldTree = try walk(layout.target.path), newTree = try walk(layout.source.path), others = try unrelated(layout)
                try refuses(.persistenceFailed) {
                    _ = try authority.perform(prepared.request, hooks: idle(boundary: { if $0 == boundary { throw Injected() } }))
                }
                let swapped = swappedBoundaries.contains(boundary)
                try expect(try expectOldPreserved(layout, old: oldTree, new: newTree) == swapped, "Swap state does not match the interrupted boundary")
                try expectSame(others, try unrelated(layout), "Interrupted transaction changed unrelated bytes")
                let evidence = try topLevel(layout.transaction)
                let (code, output) = try boundedChild(["--recover-probe", layout.root.path])
                if boundary == .transactionDirectoryCreated || boundary == .lockAcquired {
                    try expect(code == 1 && output.contains("refused=journalMissing"), "Journal-less directory was not refused: \(output)")
                } else {
                    let action = swapped ? "restoredOldBySwap" : "oldAlreadyInPlace"
                    try expect(code == 0 && output.contains("state=rolledBack action=\(action) " + noTrustSuffix), "Separate-process recovery differs: \(output)")
                    try expect(try journalState(layout) == "rolledBack", "Recovery was not recorded durably")
                }
                try expectSame(oldTree, try walk(layout.target.path), "Original bundle identity and bytes are not at the target after recovery")
                if swapped { try expectContent(newTree, try walk(layout.exchanged.path), "Recovery did not retain the new bundle as evidence") }
                try expect(evidence.isSubset(of: try topLevel(layout.transaction)), "Recovery removed transaction evidence")
                try expectSame(others, try unrelated(layout), "Recovery changed unrelated bytes")
                try refuses(.existingTransaction) { _ = try FixtureAuthority.reopenRoot(path: layout.root.path).perform(prepared.request, hooks: idle()) }
            }
        }
    }
    for operation in TransactionSyncOperation.allCases {
        check("refused \(operation.rawValue): no weaker flush, no accepted result, old bytes intact or recovered") {
            try withRoot { authority, layout in
                let prepared = try seeded(layout)
                let oldTree = try walk(layout.target.path), newTree = try walk(layout.source.path), others = try unrelated(layout)
                var refused = 0
                try refuses(.persistenceFailed) {
                    _ = try authority.perform(prepared.request, hooks: idle(sync: { if $0 == operation { refused += 1; throw Injected() } }))
                }
                try expect(refused == 1, "Transaction continued after a refused \(operation.rawValue)")
                _ = try expectOldPreserved(layout, old: oldTree, new: newTree)
                do {
                    let report = try FixtureAuthority.reopenRoot(path: layout.root.path).recover(transactionDirectory: layout.transaction.path, hooks: idle())
                    try expect(report.state == .rolledBack, "Unaccepted transaction recovered as \(report.state.rawValue)")
                    try expectFixtureOnly(report)
                } catch TransactionFailure.journalMissing {
                    try expect(!exists(layout.journal), "Recovery denied an existing journal")
                }
                try expectSame(oldTree, try walk(layout.target.path), "Original bundle identity and bytes are not at the target")
                try expectSame(others, try unrelated(layout), "Unrelated bytes changed")
            }
        }
    }
    check("refused flush of the commit record leaves the swap uncommitted and recovery restores the old bundle") {
        var flushes = 0
        try withRoot { authority, layout in
            _ = try authority.perform(try seeded(layout).request, hooks: idle(sync: { if $0 == .journalFileFullSync { flushes += 1 } }))
        }
        try expect(flushes >= 4, "A complete transaction flushed fewer than four journal records")
        try withRoot { authority, layout in
            let prepared = try seeded(layout)
            let oldTree = try walk(layout.target.path), newTree = try walk(layout.source.path)
            var seen = 0
            try refuses(.persistenceFailed) {
                _ = try authority.perform(prepared.request, hooks: idle(sync: {
                    if $0 == .journalFileFullSync { seen += 1; if seen == flushes { throw Injected() } }
                }))
            }
            try expect(try expectOldPreserved(layout, old: oldTree, new: newTree), "Commit-record failure should follow the swap")
            try expect(try journalState(layout) == "swapIntended", "An unflushed commit record became the journal")
            let report = try FixtureAuthority.reopenRoot(path: layout.root.path).recover(transactionDirectory: layout.transaction.path, hooks: idle())
            try expect(report.state == .rolledBack && report.recoveryAction == .restoredOldBySwap, "Uncommitted swap was not rolled back")
            try expectSame(oldTree, try walk(layout.target.path), "Original bundle was not restored")
        }
    }
    for boundary in [TransactionBoundary.beforeSwapBack, .swappedBack] {
        check("fault during recovery at \(boundary.rawValue): refused, then a later recovery converges on the old bundle") {
            try withRoot { authority, layout in
                _ = try interrupted(authority, layout, at: .swapped)
                let oldTree = try walk(layout.exchanged.path), newTree = try walk(layout.target.path), others = try unrelated(layout)
                try refuses(.persistenceFailed) {
                    _ = try FixtureAuthority.reopenRoot(path: layout.root.path).recover(transactionDirectory: layout.transaction.path,
                        hooks: idle(boundary: { if $0 == boundary { throw Injected() } }))
                }
                let restored = try walk(layout.target.path) == oldTree
                try expect(restored == (boundary == .swappedBack), "Swap-back state does not match the interrupted boundary")
                if !restored { try expectSame(newTree, try walk(layout.target.path), "Refused recovery altered the target") }
                try expect(try journalState(layout) == "swapIntended", "Interrupted recovery recorded a final state")
                let (code, output) = try boundedChild(["--recover-probe", layout.root.path])
                let action = restored ? "oldAlreadyInPlace" : "restoredOldBySwap"
                try expect(code == 0 && output.contains("state=rolledBack action=\(action) " + noTrustSuffix), "Second recovery differs: \(output)")
                try expectSame(oldTree, try walk(layout.target.path), "Original bundle identity and bytes were not restored")
                try expectSame(newTree, try walk(layout.exchanged.path), "New bundle was not retained as evidence")
                try expectSame(others, try unrelated(layout), "Recovery changed unrelated bytes")
            }
        }
    }
    check("recovery never swaps back while the fixture declares the app running") {
        try withRoot { authority, layout in
            _ = try interrupted(authority, layout, at: .swapped)
            let before = try walk(layout.root.path)
            try refuses(.appRunning) {
                _ = try FixtureAuthority.reopenRoot(path: layout.root.path).recover(transactionDirectory: layout.transaction.path,
                                                                                    hooks: FixtureHooks(applicationRunning: { _ in true }))
            }
            try expectSame(before, try walk(layout.root.path), "Refused recovery changed physical state")
        }
    }

    // The named target, an ancestor or the transaction directory is substituted at a real boundary.
    let substitutions: [(String, (Layout) throws -> (decoy: URL, original: URL))] = [
        ("named target", { layout in
            let moved = layout.applications.appendingPathComponent("Moved.app")
            try move(layout.target, moved); try writeBundle(layout.target, bundleID: Sample.bundleID, version: Sample.oldVersion, label: "decoy")
            return (layout.target, moved) }),
        ("applications ancestor", { layout in
            let moved = layout.root.appendingPathComponent("Applications-moved")
            try move(layout.applications, moved); try makeDirectory(layout.applications, mode: 0o700)
            try writeBundle(layout.target, bundleID: Sample.bundleID, version: Sample.oldVersion, label: "decoy")
            return (layout.applications, moved) }),
        ("transaction directory", { layout in
            let moved = layout.root.appendingPathComponent("Transaction-moved")
            try move(layout.transaction, moved); try makeDirectory(layout.transaction, mode: 0o700)
            return (layout.transaction, moved) })
    ]
    for boundary in [TransactionBoundary.journalPrepared, .stageVerified, .swapIntended] {
        for (name, substitute) in substitutions {
            check("\(name) substituted at \(boundary.rawValue) refuses and nothing is written into the substitute") {
                try withRoot { authority, layout in
                    let prepared = try seeded(layout)
                    let oldTree = try walk(layout.target.path), profile = try walk(layout.profile.path), incoming = try walk(layout.incoming.path)
                    var decoy: [Entry] = [], decoyURL = layout.root, originalTarget = layout.target
                    try refuses(.identityChanged) {
                        _ = try authority.perform(prepared.request, hooks: idle(boundary: {
                            guard $0 == boundary else { return }
                            let result = try substitute(layout)
                            decoyURL = result.decoy; decoy = try walk(decoyURL.path)
                            if name == "named target" { originalTarget = result.original }
                            if name == "applications ancestor" { originalTarget = result.original.appendingPathComponent(Sample.bundleName) }
                        }))
                    }
                    try expect(!decoy.isEmpty, "Substitution boundary was never reached")
                    try expectSame(decoy, try walk(decoyURL.path), "Transaction wrote into or replaced a substituted path")
                    try expectSame(oldTree, try walk(originalTarget.path), "Original old bundle changed after its name was substituted")
                    try expectSame(profile, try walk(layout.profile.path), "Dummy profile changed")
                    try expectSame(incoming, try walk(layout.incoming.path), "Incoming bundle changed")
                }
            }
        }
    }
    check("staged bytes changed before the swap refuse and the old bundle is untouched") {
        try withRoot { authority, layout in
            let prepared = try seeded(layout)
            let oldTree = try walk(layout.target.path), others = try unrelated(layout), log = EventLog()
            try refuses(.stagedBytesMismatch) {
                _ = try authority.perform(prepared.request, hooks: idle(boundary: {
                    log.events.append($0.rawValue)
                    guard $0 == .stageSynced else { return }
                    let staged = resource(layout.exchanged, "data.bin")
                    var bytes = try Data(contentsOf: staged); bytes[7] ^= 1; try writeFile(bytes, staged)
                }))
            }
            try expect(log.events.last == "stageSynced", "Transaction continued past unverified staged bytes")
            try expectSame(oldTree, try walk(layout.target.path), "Old bundle changed")
            try expectSame(others, try unrelated(layout), "Unrelated bytes changed")
            try expect(try journalState(layout) == "prepared", "Unverified stage was recorded as staged")
        }
    }
    check("exchange directory replaced by a symlink during staging refuses and the decoy stays empty") {
        try withRoot { authority, layout in
            let prepared = try seeded(layout)
            let oldTree = try walk(layout.target.path), decoy = layout.root.appendingPathComponent("Decoy")
            try refuses(.identityChanged) {
                _ = try authority.perform(prepared.request, hooks: idle(boundary: {
                    guard $0 == .stageCreated else { return }
                    try makeDirectory(decoy, mode: 0o700)
                    try move(layout.exchange, layout.transaction.appendingPathComponent("exchange-moved")); try symlinkTo(decoy, at: layout.exchange)
                }))
            }
            try expect(exists(decoy) && (try topLevel(decoy)).isEmpty, "Staging wrote through a substituted symlink")
            try expectSame(oldTree, try walk(layout.target.path), "Old bundle changed")
        }
    }
}
