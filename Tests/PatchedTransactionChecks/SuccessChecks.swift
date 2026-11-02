import Foundation
import Darwin
@_spi(Testing) import PatchedCore

let performBoundaries: [TransactionBoundary] = [.transactionDirectoryCreated, .lockAcquired, .journalPrepared, .stageCreated,
    .stageCopied, .stageSynced, .stageVerified, .swapIntended, .swapped, .targetParentSynced, .beforeCommitRecord]
let journalKeys: Set<String> = ["schemaVersion", "kind", "transactionID", "state", "bundleName", "bundleID", "fromVersion",
    "toVersion", "cataloguePayloadSHA256", "artifactSHA256", "targetPath", "exchangePath", "device", "oldInode", "newInode",
    "beforeManifestSHA256", "afterManifestSHA256", "beforeTreeSHA256", "afterTreeSHA256", "origin"]

@MainActor func registerSuccessChecks() {
    check("explicit fixture transaction replaces the named bundle whole and retains the old one") {
        try withRoot { authority, layout in
            let prepared = try seeded(layout)
            let oldTree = try walk(layout.target.path), newTree = try walk(layout.source.path), others = try unrelated(layout)
            let report = try authority.perform(prepared.request, hooks: idle())
            let targetNow = try walk(layout.target.path), exchangeNow = try walk(layout.exchanged.path)
            try expectContent(newTree, targetNow, "Target is not exactly the pinned new tree")
            try expectSame(oldTree, exchangeNow, "Old bundle identity and bytes were not retained in the exchange directory")
            try expect(Set(targetNow.map(\.inode)).isDisjoint(with: Set(newTree.map(\.inode))), "Target must be the owned staged copy, not the incoming inodes")
            try expectSame(others, try unrelated(layout), "Unrelated app, dummy profile or incoming bytes changed")
            try expect(try topLevel(layout.applications) == [Sample.bundleName, "Other.app"], "Applications directory gained or lost an entry")
            try expect(report.state == .committed && report.recoveryAction == RecoveryAction.none, "Successful transaction is not committed pending decision")
            try expectManifest(report.before, oldTree, "Frozen before manifest")
            try expectManifest(report.after, newTree, "Frozen after manifest")
            try expectManifest(report.targetNow, targetNow, "Reported target")
            try expectManifest(report.exchangeNow, exchangeNow, "Reported exchange")
            try expect(report.bundleName == Sample.bundleName && report.bundleID == Sample.bundleID && report.fromVersion == Sample.oldVersion &&
                       report.toVersion == Sample.newVersion && report.targetPath == layout.target.path && report.exchangePath == layout.exchanged.path &&
                       report.journalPath == layout.journal.path && report.trigger == .explicitUserAction &&
                       report.atomicPrimitive == "renameatx_np(RENAME_SWAP)", "Report misdescribes the transaction")
            try expectFixtureOnly(report)
        }
    }
    check("committed transaction leaves a private exact journal and frozen manifests") {
        try withRoot { authority, layout in
            let prepared = try seeded(layout)
            let oldTree = try walk(layout.target.path), newTree = try walk(layout.source.path)
            let report = try authority.perform(prepared.request, hooks: idle())
            try expect(try topLevel(layout.transaction) == ["after-manifest.json", "before-manifest.json", "exchange", "journal.json", "lock"],
                       "Committed transaction directory differs from the contract")
            for (name, mode) in [("", mode_t(0o700)), ("exchange", 0o700), ("journal.json", 0o600), ("lock", 0o600),
                                 ("before-manifest.json", 0o600), ("after-manifest.json", 0o600)] {
                let info = try status(name.isEmpty ? layout.transaction : layout.transaction.appendingPathComponent(name))
                try expect(info.st_mode & 0o7777 == mode && info.st_uid == geteuid() && (mode == 0o700 || info.st_nlink == 1), "Unsafe owner, mode or links: \(name)")
            }
            try expect(try status(layout.lock).st_size == 0 && topLevel(layout.exchange) == [Sample.bundleName], "Lock or exchange holds unexpected content")
            let fields = try journalFields(layout), target = try status(layout.target), exchanged = try status(layout.exchanged)
            try expect(Set(fields.keys) == journalKeys, "Journal fields differ from the contract")
            try expect(unsigned(fields["schemaVersion"]) == 1 && fields["kind"] as? String == "patched-fixture-transaction-journal-v1" &&
                       fields["state"] as? String == "committed" && fields["origin"] as? String == "fixture", "Journal header or state is wrong")
            try expect(fields["transactionID"] as? String == report.transactionID && UUID(uuidString: report.transactionID) != nil, "Journal lacks the transaction identity")
            try expect(fields["bundleName"] as? String == Sample.bundleName && fields["bundleID"] as? String == Sample.bundleID &&
                       fields["fromVersion"] as? String == Sample.oldVersion && fields["toVersion"] as? String == Sample.newVersion &&
                       fields["targetPath"] as? String == layout.target.path && fields["exchangePath"] as? String == layout.exchanged.path,
                       "Journal names a different bundle or path")
            try expect(fields["cataloguePayloadSHA256"] as? String == prepared.candidate.payloadSHA256 && fields["artifactSHA256"] as? String == sha(prepared.manifest),
                       "Journal is not bound to the signed catalogue and pinned artifact")
            try expect(unsigned(fields["device"]) == UInt64(UInt32(bitPattern: target.st_dev)) && target.st_dev == exchanged.st_dev &&
                       unsigned(fields["oldInode"]) == UInt64(exchanged.st_ino) && unsigned(fields["newInode"]) == UInt64(target.st_ino) &&
                       unsigned(fields["oldInode"]) == oldTree[0].inode, "Journal identities differ from the physical bundles")
            let before = try Data(contentsOf: layout.transaction.appendingPathComponent("before-manifest.json"))
            let after = try Data(contentsOf: layout.transaction.appendingPathComponent("after-manifest.json"))
            try expect(after == prepared.manifest && fields["afterManifestSHA256"] as? String == sha(prepared.manifest), "Frozen after manifest is not the exact pinned artifact")
            try expect(fields["beforeManifestSHA256"] as? String == sha(before) && (try manifestLines(before)) == content(oldTree),
                       "Frozen before manifest does not record every old entry")
            let frozen = try object(before)
            try expect(Set(frozen.keys) == ["schemaVersion", "kind", "bundleName", "bundleID", "version", "entries"] &&
                       frozen["kind"] as? String == "patched-fixture-bundle-manifest-v1" && frozen["version"] as? String == Sample.oldVersion &&
                       frozen["bundleID"] as? String == Sample.bundleID && frozen["bundleName"] as? String == Sample.bundleName, "Frozen before manifest header is wrong")
            try expect(fields["beforeTreeSHA256"] as? String == treeDigest(oldTree) && fields["afterTreeSHA256"] as? String == treeDigest(newTree),
                       "Journal tree digests differ from independent digests")
        }
    }
    check("every boundary, journal state and synchronisation occurs in order around one atomic swap") {
        try withRoot { authority, layout in
            let prepared = try seeded(layout)
            let oldInode = UInt64(try status(layout.target).st_ino), newTree = try walk(layout.source.path), log = EventLog()
            var states: [String: String] = [:], targetAt: [String: UInt64] = [:], exchangedAt: [String: UInt64] = [:]
            let hooks = FixtureHooks(applicationRunning: { log.running.append($0); return false }, boundary: { boundary in
                log.events.append("b:" + boundary.rawValue)
                if exists(layout.journal) { states[boundary.rawValue] = try journalState(layout) }
                targetAt[boundary.rawValue] = UInt64(try status(layout.target).st_ino)
                if exists(layout.exchanged) { exchangedAt[boundary.rawValue] = UInt64(try status(layout.exchanged).st_ino) }
            }, sync: { log.events.append("s:" + $0.rawValue) })
            let report = try authority.perform(prepared.request, hooks: hooks)
            try expect(report.state == .committed, "Transaction did not commit")
            try expect(log.events.filter { $0.hasPrefix("b:") } == performBoundaries.map { "b:" + $0.rawValue }, "Boundaries missing, repeated or out of order")
            try expect(states == ["journalPrepared": "prepared", "stageCreated": "prepared", "stageCopied": "prepared", "stageSynced": "prepared",
                                  "stageVerified": "staged", "swapIntended": "swapIntended", "swapped": "swapIntended",
                                  "targetParentSynced": "swapIntended", "beforeCommitRecord": "swapIntended"] && (try journalState(layout)) == "committed",
                       "Journal state transitions differ from the contract: \(states)")
            for boundary in performBoundaries {
                let swapped = [.swapped, .targetParentSynced, .beforeCommitRecord].contains(boundary)
                try expect((targetAt[boundary.rawValue] == oldInode) == !swapped, "Old bundle left or stayed at the target at the wrong step: \(boundary.rawValue)")
                if swapped { try expect(exchangedAt[boundary.rawValue] == oldInode, "Old bundle is not in the exchange directory after the swap") }
            }
            try expect(exchangedAt["stageVerified"] != nil && exchangedAt["stageVerified"] == targetAt["swapped"], "Replacement is not the verified staged identity")
            func position(_ event: String) throws -> Int {
                guard let index = log.index(event) else { throw CheckFailure(description: "Missing event \(event)") }
                return index
            }
            func last(_ event: String) -> Int { log.events.lastIndex(of: event) ?? -1 }
            try expect(log.count("s:transactionParentSync") >= 1 && position("s:transactionParentSync") < position("b:transactionDirectoryCreated"),
                       "Transaction directory creation was not synchronised first")
            try expect(log.count("s:stagedFileFullSync") == newTree.filter { $0.type == "file" }.count &&
                       log.count("s:stagedDirectorySync") == newTree.filter { $0.type == "directory" }.count, "Not every staged file and directory was synchronised")
            for event in ["s:stagedFileFullSync", "s:stagedDirectorySync"] {
                try expect(position(event) > position("b:stageCopied") && last(event) < position("b:stageSynced"), "Staged synchronisation outside its step")
            }
            try expect(log.count("s:journalFileFullSync") >= 4 && log.count("s:journalDirectorySync") >= 4, "Journal transitions were not each flushed")
            try expect(position("s:journalFileFullSync") > position("b:lockAcquired") && position("s:journalDirectorySync") < position("b:journalPrepared") &&
                       last("s:journalFileFullSync") > position("b:beforeCommitRecord") && last("s:journalDirectorySync") > position("b:beforeCommitRecord"),
                       "Prepared or commit record was not flushed at its step")
            for event in ["s:targetParentSync", "s:exchangeDirectorySync"] {
                try expect(last(event) > position("b:swapped") && last(event) < position("b:targetParentSynced"), "Swap was not synchronised before it was recorded")
            }
            try expect(log.running.count >= 2 && log.running.allSatisfy { $0 == Sample.bundleID }, "Running declaration was not consulted for the exact bundle before staging and before the swap")
        }
    }
    check("single writer: a held transaction refuses a second writer and a second transaction") {
        try withRoot { authority, layout in
            let prepared = try seeded(layout)
            var contended = false
            let report = try authority.perform(prepared.request, hooks: idle(boundary: { boundary in
                guard boundary == .lockAcquired else { return }
                let second = try FixtureAuthority.reopenRoot(path: layout.root.path)
                try refuses(.busy) { _ = try second.recover(transactionDirectory: layout.transaction.path, hooks: idle()) }
                try refuses(.existingTransaction) { _ = try second.perform(prepared.request, hooks: idle()) }
                contended = true
            }))
            try expect(contended && report.state == .committed, "Contention probe did not run inside a committed transaction")
        }
    }
    check("a second transaction in a used root refuses and changes nothing") {
        try withRoot { authority, layout in
            let prepared = try seeded(layout)
            _ = try authority.perform(prepared.request, hooks: idle())
            let before = try walk(layout.root.path)
            try refuses(.existingTransaction) { _ = try authority.perform(prepared.request, hooks: idle()) }
            try expectSame(before, try walk(layout.root.path), "Refused second transaction changed the fixture")
        }
    }
    check("recovery of a committed transaction changes nothing, in this and a separate process") {
        try withRoot { authority, layout in
            let prepared = try seeded(layout)
            let newTree = try walk(layout.source.path)
            _ = try authority.perform(prepared.request, hooks: idle())
            let before = try walk(layout.root.path)
            let report = try FixtureAuthority.reopenRoot(path: layout.root.path).recover(transactionDirectory: layout.transaction.path, hooks: idle())
            try expect(report.state == .committed && report.recoveryAction == RecoveryAction.none, "Committed transaction was not left pending decision")
            try expectManifest(report.targetNow, newTree, "Recovered report target"); try expectFixtureOnly(report)
            let (code, output) = try boundedChild(["--recover-probe", layout.root.path])
            try expect(code == 0 && output.contains("state=committed action=none " + noTrustSuffix), "Separate process disagreed: \(output)")
            try expectSame(before, try walk(layout.root.path), "Recovery of a committed transaction changed physical state")
        }
    }
    check("explicit keep-new decision finalises and still retains the old bundle") {
        try withRoot { authority, layout in
            let prepared = try seeded(layout)
            let oldTree = try walk(layout.target.path), newTree = try walk(layout.source.path), others = try unrelated(layout)
            _ = try authority.perform(prepared.request, hooks: idle())
            let committedTarget = try walk(layout.target.path)
            let report = try authority.decide(.keepNew, transactionDirectory: layout.transaction.path, trigger: .explicitUserAction, hooks: idle())
            try expect(report.state == .finalized && (try journalState(layout)) == "finalized", "Keep-new decision was not recorded")
            try expectSame(committedTarget, try walk(layout.target.path), "Keep-new changed the new bundle")
            try expectSame(oldTree, try walk(layout.exchanged.path), "Keep-new deleted or changed the retained old bundle")
            try expectManifest(report.targetNow, newTree, "Finalised target"); try expectFixtureOnly(report)
            try expectSame(others, try unrelated(layout), "Decision changed unrelated bytes")
            let before = try walk(layout.root.path)
            for decision in [FinalDecision.keepNew, .restoreOld] {
                try refuses(.invalidState) { _ = try authority.decide(decision, transactionDirectory: layout.transaction.path, trigger: .explicitUserAction, hooks: idle()) }
            }
            try expectSame(before, try walk(layout.root.path), "A repeated decision changed physical state")
        }
    }
    check("explicit restore-old decision swaps the original identity and bytes back and retains the new bundle") {
        try withRoot { authority, layout in
            let prepared = try seeded(layout)
            let oldTree = try walk(layout.target.path), newTree = try walk(layout.source.path), others = try unrelated(layout)
            _ = try authority.perform(prepared.request, hooks: idle())
            let committedTarget = try walk(layout.target.path), log = EventLog()
            let report = try authority.decide(.restoreOld, transactionDirectory: layout.transaction.path, trigger: .explicitUserAction,
                                              hooks: idle(boundary: { log.events.append($0.rawValue) }))
            try expect(report.state == .rolledBack && report.recoveryAction == .restoredOldBySwap && (try journalState(layout)) == "rolledBack", "Restore was not recorded")
            try expect(log.events == ["beforeSwapBack", "swappedBack"], "Restore did not pass its two boundaries once")
            try expectSame(oldTree, try walk(layout.target.path), "Original bundle identity and bytes were not restored")
            try expectSame(committedTarget, try walk(layout.exchanged.path), "New bundle was not retained after restore")
            try expectManifest(report.targetNow, oldTree, "Restored target"); try expectManifest(report.exchangeNow, newTree, "Retained new bundle")
            try expectFixtureOnly(report)
            try expectSame(others, try unrelated(layout), "Restore changed unrelated bytes")
            try refuses(.invalidState) { _ = try authority.decide(.keepNew, transactionDirectory: layout.transaction.path, trigger: .explicitUserAction, hooks: idle()) }
        }
    }
    for (name, reason, trigger, running) in [("a background trigger", TransactionFailure.userTriggerRequired, TransactionTrigger.background, false),
                                             ("a running fixture declaration", .appRunning, .explicitUserAction, true)] {
        check("restore-old decision with \(name) refuses and changes nothing") {
            try withRoot { authority, layout in
                let prepared = try seeded(layout)
                _ = try authority.perform(prepared.request, hooks: idle())
                let before = try walk(layout.root.path)
                try refuses(reason) {
                    _ = try authority.decide(.restoreOld, transactionDirectory: layout.transaction.path, trigger: trigger,
                                             hooks: FixtureHooks(applicationRunning: { _ in running }))
                }
                try expectSame(before, try walk(layout.root.path), "Refused decision changed physical state")
            }
        }
    }
    check("a decision before any committed transaction refuses") {
        try withRoot { authority, layout in
            _ = try interrupted(authority, layout, at: .stageVerified)
            let before = try walk(layout.root.path)
            for decision in [FinalDecision.keepNew, .restoreOld] {
                try refuses(.invalidState) { _ = try authority.decide(decision, transactionDirectory: layout.transaction.path, trigger: .explicitUserAction, hooks: idle()) }
            }
            try expectSame(before, try walk(layout.root.path), "Refused decision changed an uncommitted transaction")
        }
    }
}
