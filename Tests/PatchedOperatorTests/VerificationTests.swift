import Foundation
import Darwin
import ArtifactInspection
@_spi(Testing) import PatchedCore
@_spi(Testing) import PatchedOperator

// The verify step. A fixture receipt records byte identity of a tiny owned file and
// nothing about macOS. The live entry is exercised here only with inputs the actual
// inspector refuses before any image tool runs; no disk image is mounted by this gate.

func expectFixtureOnly(_ receipt: VerifiedArtifactReceipt) throws {
    try expect(receipt.origin == .fixture && !receipt.freshOSValidation && !receipt.installationAuthorized,
               "Fixture receipt asserted a live origin, OS validation or installation authority")
    try expect(!receipt.appChecksPassed && !receipt.containerSignaturePassed && !receipt.containerGatekeeperPassed &&
               !receipt.containerTicketPassed && !receipt.cleanupVerified, "Fixture receipt asserted a macOS check it never ran")
    let encoded = try object(JSONEncoder().encode(receipt))
    try expect(encoded["origin"] as? String == "fixture" && flag(encoded["freshOSValidation"]) == false &&
               flag(encoded["installationAuthorized"]) == false && flag(encoded["appChecksPassed"]) == false,
               "Encoded fixture receipt lost its explicit no-trust fields")
}

@MainActor func registerVerificationChecks() {
    for version in ["157.0", "157.0.1"] {
        check("fixture receipt \(version): binds the pinned identity to the exact bytes and physical file, fixture origin only") {
            try withRoot { authority, layout in
                let before = try snapshot(layout.root)
                let receipt = try authority.fixtureReceipt(version: version, artifactPath: layout.artifact.path)
                let info = try status(layout.artifact)
                try expect(receipt.version == version && receipt.bundleID == Sample.bundleID && receipt.teamID == Sample.teamID,
                           "Receipt identity is not the compiled pin identity")
                try expect(receipt.sha256 == sha(Sample.artifact) && receipt.byteLength == Int64(Sample.artifact.count) && receipt.byteIntegrityVerified,
                           "Receipt digest or length is not that of the physical bytes")
                try expect(receipt.artifactPath == layout.artifact.path && receipt.artifactInode == UInt64(info.st_ino) &&
                           receipt.artifactDevice == UInt64(UInt32(bitPattern: info.st_dev)), "Receipt does not bind the physical file")
                try expect(receipt.inspectionRecordSHA256.utf8.count == 64 && receipt.inspectionRecordSHA256 != Sample.zeroDigest &&
                           (1...OperatorLimits.maximumInspectionRecordBytes).contains(receipt.inspectionRecordByteLength),
                           "Receipt does not bind a bounded inspection record")
                try expectFixtureOnly(receipt)
                try expect(try snapshot(layout.root) == before, "Read-only verification changed the operator root")
            }
        }
    }
    check("fixture receipt: a file of exactly the 64-KiB bound is accepted and one byte more is refused") {
        try withRoot { authority, layout in
            let largest = layout.input.appendingPathComponent("largest.dmg"), over = layout.input.appendingPathComponent("over.dmg")
            try writeFile(Data(repeating: 0x41, count: OperatorLimits.maximumFixtureArtifactBytes), largest)
            try writeFile(Data(repeating: 0x41, count: OperatorLimits.maximumFixtureArtifactBytes + 1), over)
            let receipt = try authority.fixtureReceipt(version: Sample.version, artifactPath: largest.path)
            try expect(receipt.byteLength == 65_536, "Bound differs from 64 KiB")
            try expectFixtureOnly(receipt)
            try refuses(.resourceLimit) { _ = try authority.fixtureReceipt(version: Sample.version, artifactPath: over.path) }
        }
    }
    let unacceptable: [(String, OperatorFailure, @Sendable (Layout) throws -> String)] = [
        ("an empty file", .resourceLimit, { layout in
            let url = layout.input.appendingPathComponent("empty.dmg"); try writeFile(Data(), url); return url.path }),
        ("a missing file", .unsafePath, { $0.input.appendingPathComponent("absent.dmg").path }),
        ("a file in the scratch directory outside the root", .unsafePath, { layout in
            let url = layout.scratch.appendingPathComponent("outside.dmg"); try writeFile(Sample.artifact, url); return url.path }),
        ("a file in the root but outside its input directory", .unsafePath, { layout in
            let url = layout.root.appendingPathComponent("loose.dmg"); try writeFile(Sample.artifact, url); return url.path }),
        ("a file in a subdirectory of the input directory", .unsafePath, { layout in
            let directory = layout.input.appendingPathComponent("deeper"); try makeDirectory(directory)
            let url = directory.appendingPathComponent("nested.dmg"); try writeFile(Sample.artifact, url); return url.path }),
        ("a symlink to the artifact", .unsafePath, { layout in
            let url = layout.input.appendingPathComponent("link.dmg")
            try expect(symlink(layout.artifact.path, url.path) == 0, "Fixture symlink failed"); return url.path }),
        ("a path with traversal", .unsafePath, { $0.input.path + "/../input/" + Sample.artifactName }),
        ("a relative path", .unsafePath, { _ in "input/" + Sample.artifactName }),
        ("a hard-linked file", .hardlink, { layout in
            let url = layout.input.appendingPathComponent("linked.dmg")
            try expect(link(layout.artifact.path, url.path) == 0, "Fixture link failed"); return url.path }),
        ("a group-readable file", .unsafeMode, { layout in
            let url = layout.input.appendingPathComponent("shared.dmg"); try writeFile(Sample.artifact, url, mode: 0o640); return url.path }),
        ("a directory", .notRegularFile, { layout in
            let url = layout.input.appendingPathComponent("folder.dmg"); try makeDirectory(url); return url.path }),
        ("a named pipe", .notRegularFile, { layout in
            let url = layout.input.appendingPathComponent("pipe.dmg")
            try expect(mkfifo(url.path, 0o600) == 0, "Fixture mkfifo failed"); return url.path })]
    for (name, reason, prepare) in unacceptable {
        check("fixture receipt: \(name) is refused as \(reason.rawValue)") {
            try withRoot { authority, layout in
                let path = try prepare(layout)
                try refuses(reason) { _ = try authority.fixtureReceipt(version: Sample.version, artifactPath: path) }
            }
        }
    }
    check("fixture receipt: a version that is not a compiled pin is refused") {
        try withRoot { authority, layout in
            for version in ["158.0", "157.0.2", "157", "", "157.0.1 ", "latest"] {
                try refuses(.unknownTarget) { _ = try authority.fixtureReceipt(version: version, artifactPath: layout.artifact.path) }
            }
        }
    }
    check("fixture receipt: one authority cannot issue a receipt for a file in another authority's root") {
        try withRoot { first, firstLayout in
            try withRoot { second, secondLayout in
                try refuses(.unsafePath) { _ = try first.fixtureReceipt(version: Sample.version, artifactPath: secondLayout.artifact.path) }
                try expectFixtureOnly(try second.fixtureReceipt(version: Sample.version, artifactPath: secondLayout.artifact.path))
                try expectFixtureOnly(try first.fixtureReceipt(version: Sample.version, artifactPath: firstLayout.artifact.path))
            }
        }
    }

    // The live entry. Each input below is refused by the actual inspector while it stages
    // bytes, before hdiutil or any other tool is run.
    check("live entry: a version that is not a compiled pin is refused before any file is opened") {
        try withLayout { layout in
            let file = layout.scratch.appendingPathComponent("Firefox.dmg"); try writeFile(Sample.artifact, file)
            for version in ["158.0", "157.0.2", "", "latest"] {
                try refuses(.unknownTarget) { _ = try OperatorVerification.verifyPinnedArtifact(version: version, path: file.path) }
            }
        }
    }
    let unstaged: [(String, OperatorFailure, @Sendable (Layout) throws -> String)] = [
        ("fixture bytes of the wrong length", .lengthMismatch, { layout in
            let url = layout.scratch.appendingPathComponent("Firefox.dmg"); try writeFile(Sample.artifact, url); return url.path }),
        ("a missing file", .unsafePath, { $0.scratch.appendingPathComponent("absent.dmg").path }),
        ("a relative path", .unsafePath, { _ in "Firefox.dmg" }),
        ("a path with traversal", .unsafePath, { $0.scratch.path + "/../" + $0.scratch.lastPathComponent + "/Firefox.dmg" }),
        ("a symlink to a file", .unsafePath, { layout in
            let target = layout.scratch.appendingPathComponent("target.dmg"), url = layout.scratch.appendingPathComponent("Firefox.dmg")
            try writeFile(Sample.artifact, target)
            try expect(symlink(target.path, url.path) == 0, "Fixture symlink failed"); return url.path }),
        ("a directory", .notRegularFile, { layout in
            let url = layout.scratch.appendingPathComponent("Firefox.dmg"); try makeDirectory(url); return url.path })]
    for (name, reason, prepare) in unstaged {
        check("live entry: \(name) is refused as \(reason.rawValue), with no receipt and the input unchanged") {
            try withLayout { layout in
                let path = try prepare(layout)
                let before = try snapshot(layout.scratch)
                for version in ["157.0", "157.0.1"] {
                    try refuses(reason) { _ = try OperatorVerification.verifyPinnedArtifact(version: version, path: path) }
                }
                try expect(try snapshot(layout.scratch) == before, "A refused live verification changed its input")
            }
        }
    }
}

/// Explicitly invoked, never part of the unit gate: fresh read-only inspection of one existing
/// pinned DMG through the operator's live entry. It mounts the image read-only and launches nothing.
func runLiveInspection(version: String, path: String) -> Int32 {
    do {
        let pin = try FirefoxTargets.select(version: version)
        let receipt = try OperatorVerification.verifyPinnedArtifact(version: version, path: path)
        var info = stat()
        try expect(lstat(path, &info) == 0, "Input is missing after inspection")
        try expect(receipt.origin == .live && receipt.freshOSValidation && receipt.byteIntegrityVerified && receipt.appChecksPassed &&
                   receipt.cleanupVerified, "Live receipt does not record a fresh passing inspection with verified cleanup")
        try expect(!receipt.installationAuthorized, "Live receipt grants installation authority")
        try expect(receipt.version == pin.version && receipt.bundleID == pin.bundleID && receipt.teamID == pin.teamID &&
                   receipt.sha256 == pin.sha256 && receipt.byteLength == pin.byteLength, "Live receipt identity is not the exact pin")
        try expect(receipt.artifactPath == path && receipt.artifactInode == UInt64(info.st_ino) &&
                   receipt.artifactDevice == UInt64(UInt32(bitPattern: info.st_dev)), "Live receipt does not bind the physical input")
        // Both reviewed images are unsigned. Their container results stay recorded as failures.
        try expect(!receipt.containerSignaturePassed && !receipt.containerGatekeeperPassed && !receipt.containerTicketPassed,
                   "Unsigned container results were rewritten as passes")
        let encoded = try object(JSONEncoder().encode(receipt))
        try expect(encoded["origin"] as? String == "live" && flag(encoded["installationAuthorized"]) == false &&
                   flag(encoded["containerSignaturePassed"]) == false, "Encoded live receipt differs")
        print("PASS live operator inspection \(version): app checks passed, container failures kept, cleanup verified, no installation authority")
        return 0
    } catch { print("FAIL live operator inspection \(version): \(error)"); return 1 }
}
