import Foundation
import Darwin
@_spi(Testing) import PatchedDisposableProof

func crashLayout(_ state: ProofState, swapped: Bool) throws -> (String, Data, Data, UInt64, UInt64) {
    let root = try fixture(), target = try tree(root, "Target"), retained = try tree(root, "Retained")
    try overwrite(retained + "/Contents/data", Data([4, 3, 2, 1]))
    let oldBytes = try bytes(target + "/Contents/data"), newBytes = try bytes(retained + "/Contents/data")
    let oldID = try statOf(target).st_ino, newID = try statOf(retained).st_ino
    var record = try journal(root, state: state)
    record["oldInode"] = oldID; record["newInode"] = newID
    record["beforeManifestSHA256"] = sha(canonical(try independentManifest(target)))
    record["afterManifestSHA256"] = sha(canonical(try independentManifest(retained)))
    try file(root + "/journal.json", json(record))
    if swapped { try expect(renameatx_np(AT_FDCWD, target, AT_FDCWD, retained, UInt32(RENAME_SWAP)) == 0, "Fixture atomic crash-layout setup") }
    return (root, oldBytes, newBytes, oldID, newID)
}
@MainActor func registerJournalCatalogueChecks() {
    for state in ProofState.allCases {
        check("strict valid journal \(state.rawValue)") {
            let root = try fixture(); try file(root + "/journal.json", json(journal(root, state: state)))
            try expect(try SyntheticProofFiles.readJournal(root: root, binding: binding(root)) == state, "Journal state decode")
        }
    }
    check("missing journal refuses") {
        let root = try fixture(); try refuses(.journalMissing) { _ = try SyntheticProofFiles.readJournal(root: root, binding: binding(root)) }
    }
    for mutation in ["truncated", "unknown", "duplicate", "state", "origin", "oversized", "schema", "digest"] {
        check("malformed journal \(mutation)") {
            let root = try fixture(); var object = try journal(root)
            switch mutation {
            case "unknown": object["ignored"] = true
            case "state": object["state"] = "success"
            case "origin": object["origin"] = "live"
            case "schema": object["schemaVersion"] = 2
            case "digest": object["beforeManifestSHA256"] = "not-a-hash"
            default: break
            }
            var data = try json(object)
            if mutation == "truncated" { data.removeLast() }
            if mutation == "duplicate" { data.removeLast(); data.append(Data(",\"state\":\"committed\"}".utf8)) }
            if mutation == "oversized" { data = Data(repeating: 32, count: 65_537) }
            try file(root + "/journal.json", data)
            try refuses(.journalCorrupt) { _ = try SyntheticProofFiles.readJournal(root: root, binding: binding(root)) }
            try expect(try bytes(root + "/journal.json") == data, "Malformed evidence was changed")
        }
    }
    for field in ["runID", "caseRoot", "device", "inode", "guestUUIDSHA256", "uid"] {
        check("journal binds \(field)") {
            let root = try fixture(); var object = try journal(root)
            switch field {
            case "runID": object[field] = "another-run"
            case "caseRoot": object[field] = "swap"
            case "device": object[field] = UInt64(0)
            case "inode": object[field] = UInt64(1)
            case "uid": object[field] = UInt64(getuid()) + 1
            default: object[field] = String(repeating: "f", count: 64)
            }
            try file(root + "/journal.json", json(object))
            try refuses(.journalMismatch) { _ = try SyntheticProofFiles.readJournal(root: root, binding: binding(root)) }
        }
    }
    check("journal durable write and exact reread") {
        let root = try fixture(), data = try json(journal(root))
        try SyntheticProofFiles.writeJournal(root: root, bytes: data, binding: binding(root))
        try expect(try bytes(root + "/journal.json") == data, "Journal write must preserve exact bytes")
        try expect(try SyntheticProofFiles.readJournal(root: root, binding: binding(root)) == .prepared, "Durable journal")
    }
    for stage in SyntheticSync.allCases {
        check("journal refuses durability failure \(stage.rawValue)") {
            let root = try fixture(); var observed = false
            let probe = SyntheticProbes(sync: { if $0 == stage { observed = true; throw ProbeRefusal() } })
            try refuses(.persistenceFailed) { try SyntheticProofFiles.writeJournal(root: root, bytes: json(journal(root)), binding: binding(root), probes: probe) }
            try expect(observed, "Required durability operation skipped")
        }
    }
    check("journal exclusive lock contention") {
        let root = try fixture(); try file(root + "/journal.lock", Data())
        let fd = open(root + "/journal.lock", O_RDWR | O_NOFOLLOW); try expect(fd >= 0, "Lock open"); defer { close(fd) }
        try expect(flock(fd, LOCK_EX | LOCK_NB) == 0, "Fixture lock")
        try refuses(.busy) { try SyntheticProofFiles.writeJournal(root: root, bytes: json(journal(root)), binding: binding(root)) }
        try expect(!exists(root + "/journal.json"), "Contender wrote a journal")
    }
    check("journal root replacement cannot redirect durable writes") {
        let root = try fixture(), data = try json(journal(root)), bound = try binding(root)
        let probe = SyntheticProbes(boundary: {
            if $0 == .beforeJournalReplace { try expect(rename(root, root + "-held") == 0, "Fixture rename"); try directory(root); try file(root + "/sentinel") }
        })
        try refuses(.identityChanged) { try SyntheticProofFiles.writeJournal(root: root, bytes: data, binding: bound, probes: probe) }
        try expect(!exists(root + "/journal.json"), "Redirected journal write")
    }
    for state in [ProofState.prepared, .staging, .staged] {
        check("physical pre-swap crash recovers old in place \(state.rawValue)") {
            let (root, old, _, oldID, _) = try crashLayout(state, swapped: false)
            try expect(try SyntheticProofFiles.recoverExchange(root: root, binding: binding(root)) == .oldAlreadyInPlace, "Old recovery action")
            try expect(try bytes(root + "/Target/Contents/data") == old && statOf(root + "/Target").st_ino == oldID, "Old target changed")
            try expect(try SyntheticProofFiles.readJournal(root: root, binding: binding(root)) == .rolledBack, "Recovery journal state")
        }
    }
    for state in [ProofState.swapIntended, .swapped] {
        check("physical post-swap crash restores retained whole old \(state.rawValue)") {
            let (root, old, new, oldID, newID) = try crashLayout(state, swapped: true)
            try expect(try SyntheticProofFiles.recoverExchange(root: root, binding: binding(root)) == .restoredOldBySwap, "Swap recovery action")
            try expect(try bytes(root + "/Target/Contents/data") == old && statOf(root + "/Target").st_ino == oldID, "Old target not restored by identity")
            try expect(try bytes(root + "/Retained/Contents/data") == new && statOf(root + "/Retained").st_ino == newID, "New bundle not retained whole")
            try expect(try SyntheticProofFiles.recoverExchange(root: root, binding: binding(root)) == .none, "Recovery is not idempotent")
        }
    }
    check("interrupted physical recovery can resume") {
        let (root, old, _, oldID, _) = try crashLayout(.swapped, swapped: true)
        var reached = false
        let probe = SyntheticProbes(boundary: { if $0 == .afterExchange { reached = true; throw ProbeRefusal() } })
        try refuses(.persistenceFailed) { _ = try SyntheticProofFiles.recoverExchange(root: root, binding: binding(root), probes: probe) }
        try expect(reached, "Recovery did not reach real exchange")
        try expect(try SyntheticProofFiles.recoverExchange(root: root, binding: binding(root)) == .oldAlreadyInPlace, "Interrupted recovery did not identify old")
        try expect(try bytes(root + "/Target/Contents/data") == old && statOf(root + "/Target").st_ino == oldID, "Repeated recovery changed old")
    }
    check("changed retained bundle refuses recovery and preserves all bytes") {
        let (root, _, new, _, _) = try crashLayout(.swapped, swapped: true)
        let altered = Data([7, 7, 7, 7]); try overwrite(root + "/Retained/Contents/data", altered)
        let before = try bytes(root + "/journal.json")
        try refuses(.ambiguousState) { _ = try SyntheticProofFiles.recoverExchange(root: root, binding: binding(root)) }
        try expect(try bytes(root + "/journal.json") == before && bytes(root + "/Target/Contents/data") == new && bytes(root + "/Retained/Contents/data") == altered, "Ambiguous state mutated")
    }
    check("committed physical recovery preserves new and old") {
        let (root, old, new, _, _) = try crashLayout(.committed, swapped: true)
        try expect(try SyntheticProofFiles.recoverExchange(root: root, binding: binding(root)) == .none, "Committed recovery rewound")
        try expect(try bytes(root + "/Target/Contents/data") == new && bytes(root + "/Retained/Contents/data") == old, "Committed content changed")
    }
    check("real signed test catalogue persists actual checkpoint without authority") {
        let root = try fixture()
        let result = try SyntheticProofFiles.verifyCatalogue(root: root, envelope: CatalogueFixture.envelope(), now: CatalogueFixture.now, bootstrap: true)
        try expect(result.sequence == 7 && result.testCatalogueTrust && !result.productionTrust && !result.freshOSValidation && !result.installationAuthorized, "Catalogue grants inappropriate authority")
        let checkpoint = try bytes(root + "/Catalogue/checkpoint.json")
        try expect(!checkpoint.isEmpty, "Actual durable checkpoint missing")
    }
    for reason in [DisposableFailure.invalidSignature, .untrustedKey, .replay, .expired, .unapprovedArtifact] {
        check("catalogue \(reason.rawValue) preserves checkpoint hash") {
            let root = try fixture()
            _ = try SyntheticProofFiles.verifyCatalogue(root: root, envelope: CatalogueFixture.envelope(), now: CatalogueFixture.now, bootstrap: true)
            let before = try bytes(root + "/Catalogue/checkpoint.json")
            let envelope: Data
            switch reason {
            case .invalidSignature: envelope = try CatalogueFixture.envelope(sequence: 8, badSignature: true)
            case .untrustedKey: envelope = try CatalogueFixture.envelope(sequence: 8, untrusted: true)
            case .replay: envelope = try CatalogueFixture.envelope(sequence: 6)
            case .expired: envelope = try CatalogueFixture.envelope(sequence: 8, expired: true)
            default: envelope = try CatalogueFixture.envelope(sequence: 8, artifactDigest: String(repeating: "0", count: 64))
            }
            try refuses(reason) { _ = try SyntheticProofFiles.verifyCatalogue(root: root, envelope: envelope, now: CatalogueFixture.now, bootstrap: false) }
            try expect(try sha(bytes(root + "/Catalogue/checkpoint.json")) == sha(before), "Refusal advanced replay checkpoint")
        }
    }
}
