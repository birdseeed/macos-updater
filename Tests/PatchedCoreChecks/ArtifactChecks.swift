import Foundation
import Darwin
import ArtifactInspection
@_spi(Testing) import PatchedCore

@MainActor func registerArtifactChecks() {
    check("fixture artifact exact bytes remain read-only and consistency-only") {
        try withWorkspace { root in
            try seedState(root)
            let candidate = try Fixture.verifier(root).verify(envelope: Fixture.envelope(), now: Fixture.now)
            let file = root.appendingPathComponent("artifact.dmg"); try writePrivate(Fixture.bytes, file)
            let result = try ArtifactVerifier.verify(path: file.path, candidate: candidate)
            try expect(result.byteLength == 3 && result.sha256 == sha(Fixture.bytes), "Byte proof lost constraints")
            try expect(result.origin == "fixture" && !result.freshOSValidation && !result.installationAuthorized,
                       "Catalogue/artifact consistency created OS or installation authority")
            try expect(try Data(contentsOf: file) == Fixture.bytes, "Read-only verifier changed bytes")
        }
    }
    for (name, bytes, reason) in [("tamper", Data("abd".utf8), CoreFailure.digestMismatch),
                                  ("short", Data("ab".utf8), .lengthMismatch), ("long", Data("abcd".utf8), .lengthMismatch)] {
        check("artifact \(name) refuses") {
            try withWorkspace { root in
                try seedState(root)
                let candidate = try Fixture.verifier(root).verify(envelope: Fixture.envelope(), now: Fixture.now)
                let file = root.appendingPathComponent("artifact.dmg"); try writePrivate(bytes, file)
                try refuses(reason) { _ = try ArtifactVerifier.verify(path: file.path, candidate: candidate) }
            }
        }
    }
    for kind in ["missing", "fifo", "directory", "symlink", "ancestor symlink", "relative", "traversal"] {
        check("artifact filesystem hazard \(kind)") {
            try withWorkspace { root in
                try seedState(root)
                let candidate = try Fixture.verifier(root).verify(envelope: Fixture.envelope(), now: Fixture.now)
                let file = root.appendingPathComponent("artifact.dmg")
                var path = file.path
                if kind == "fifo" { try expect(mkfifo(path, 0o600) == 0, "Fixture FIFO failed") }
                else if kind == "directory" { try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false) }
                else if kind == "symlink" {
                    try writePrivate(Fixture.bytes, root.appendingPathComponent("actual"))
                    try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: root.appendingPathComponent("actual").path)
                } else if kind == "ancestor symlink" {
                    try writePrivate(Fixture.bytes, file)
                    try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("alias").path, withDestinationPath: root.path)
                    path = root.appendingPathComponent("alias/artifact.dmg").path
                } else if kind == "relative" { path = "artifact.dmg" }
                else if kind == "traversal" { path = root.path + "/../artifact.dmg" }
                try refuses(kind == "fifo" || kind == "directory" ? .notRegularFile : .unsafePath) {
                    _ = try ArtifactVerifier.verify(path: path, candidate: candidate)
                }
            }
        }
    }
    check("fixture digest never creates a compiled inspection target") {
        try withWorkspace { root in
            try seedState(root)
            let candidate = try Fixture.verifier(root).verify(envelope: Fixture.envelope(), now: Fixture.now)
            try refuses(.unapprovedArtifact) { _ = try ArtifactVerifier.approvedInspectionTarget(candidate: candidate) }
        }
    }
    for pin in FirefoxTargets.pins {
        check("exact compiled Firefox \(pin.version) inspection input without OS trust") {
            try withWorkspace { root in
                try seedState(root)
                let data = try mutateArtifact { $0["version"] = pin.version; $0["sha256"] = pin.sha256; $0["byteLength"] = pin.byteLength }
                let candidate = try Fixture.verifier(root, policy: Fixture.policy(installed: "156.0")).verify(envelope: data, now: Fixture.now)
                let selected = try ArtifactVerifier.approvedInspectionTarget(candidate: candidate)
                try expect(selected == pin, "Catalogue widened compiled inspection pin")
                try expect(!candidate.freshOSValidation && !candidate.installationAuthorized, "Pin match asserted OS trust")
            }
        }
    }
    for changed in ["digest", "length", "bundle", "team", "version"] {
        check("catalogue cannot alter approved inspection \(changed)") {
            try withWorkspace { root in
                try seedState(root)
                let pin = FirefoxTargets.pins[1]
                let data = try mutateArtifact {
                    $0["version"] = pin.version; $0["sha256"] = pin.sha256; $0["byteLength"] = pin.byteLength
                    switch changed {
                    case "digest": $0["sha256"] = String(repeating: "a", count: 64)
                    case "length": $0["byteLength"] = pin.byteLength - 1
                    case "bundle": $0["bundleID"] = "org.fixture.other"
                    case "team": $0["teamID"] = "ABCDEFGHIJ"
                    default: $0["version"] = "158.0"
                    }
                }
                let policy = Fixture.policy(bundle: changed == "bundle" ? "org.fixture.other" : pin.bundleID,
                                            team: changed == "team" ? "ABCDEFGHIJ" : pin.teamID)
                let candidate = try Fixture.verifier(root, policy: policy).verify(envelope: data, now: Fixture.now)
                try refuses(.unapprovedArtifact) { _ = try ArtifactVerifier.approvedInspectionTarget(candidate: candidate) }
            }
        }
    }
}
