import Foundation
import Darwin
@_spi(Testing) import PatchedCore

// These cases exercise the already merged PAT-2581 core, the fixture builder and
// the platform primitive. They need no transaction implementation.
@MainActor func registerHarnessChecks() {
    check("harness: fixture bundles are plain, owned and not runnable") {
        try withScratch { root in
            let layout = Layout(root: root); try seedFiles(layout)
            for bundle in [layout.target, layout.other, layout.source] {
                let tree = try walk(bundle.path)
                try expect(tree.filter { $0.type == "file" }.count == 5 && tree.filter { $0.type == "directory" }.count == 5,
                           "Fixture bundle must hold five files and five directories")
                try expect(tree.allSatisfy { $0.type == "directory" ? $0.mode == 0o755 : $0.mode == 0o644 }, "Fixture modes include an execute or write hazard")
                for entry in tree {
                    let info = try status(bundle.appendingPathComponent(entry.path))
                    try expect(info.st_uid == geteuid() && (entry.type == "directory" || info.st_nlink == 1), "Fixture entry is not singly owned")
                }
            }
            try expect(content(try walk(layout.target.path)) != content(try walk(layout.source.path)), "Old and new fixture bundles must differ")
        }
    }
    check("harness: independent tree digest observes a one-byte same-length change") {
        try withScratch { root in
            let layout = Layout(root: root); try seedFiles(layout)
            let before = try walk(layout.source.path)
            let file = layout.source.appendingPathComponent("Contents/Resources/data.bin")
            var bytes = try Data(contentsOf: file); bytes[100] ^= 1; try writeFile(bytes, file)
            let after = try walk(layout.source.path)
            try expect(before.count == after.count && treeDigest(before) != treeDigest(after), "Independent digest missed a changed byte")
            try expect(try manifestLines(json(manifestObject(after))) == content(after), "Manifest document does not round-trip the physical tree")
        }
    }
    check("real core: signed fixture catalogue pins the exact manifest bytes without any authority") {
        try withScratch { root in
            let layout = Layout(root: root); try seedFiles(layout)
            let prepared = try prepare(layout)
            let consistency = try ArtifactVerifier.verify(path: layout.artifact.path, candidate: prepared.candidate)
            try expect(consistency.sha256 == sha(prepared.manifest) && consistency.byteLength == Int64(prepared.manifest.count), "Catalogue did not pin manifest bytes")
            try expect(prepared.candidate.artifact.bundleID == Sample.bundleID && prepared.candidate.artifact.version == Sample.newVersion,
                       "Candidate lost the signed identity or version")
            try expect(prepared.candidate.origin == "fixture" && !prepared.candidate.freshOSValidation && !prepared.candidate.installationAuthorized &&
                       consistency.origin == "fixture" && !consistency.freshOSValidation && !consistency.installationAuthorized,
                       "Fixture catalogue verification created OS or installation authority")
        }
    }
    check("real core: tampered catalogue signature yields no candidate") {
        try withScratch { root in
            do {
                _ = try verifiedCandidate(envelope: signedCatalogue(artifact: Data("manifest".utf8), alternateKey: true), in: root)
                throw CheckFailure(description: "IMPROPER ACCEPTANCE: wrong-key catalogue produced a candidate")
            } catch let error as CoreFailure { try expect(error == .invalidSignature, "Expected invalidSignature, received \(error.rawValue)") }
        }
    }
    for (name, edit, reason) in [("changed byte", { (data: inout Data) in data[data.count / 2] ^= 1 }, CoreFailure.digestMismatch),
                                 ("truncation", { (data: inout Data) in data.removeLast() }, .lengthMismatch)] {
        check("real core: pinned manifest \(name) is refused by actual read") {
            try withScratch { root in
                let layout = Layout(root: root); try seedFiles(layout)
                let prepared = try prepare(layout)
                var bytes = prepared.manifest; edit(&bytes); try writeFile(bytes, layout.artifact, mode: 0o600)
                do {
                    _ = try ArtifactVerifier.verify(path: layout.artifact.path, candidate: prepared.candidate)
                    throw CheckFailure(description: "IMPROPER ACCEPTANCE: altered manifest bytes verified")
                } catch let error as CoreFailure { try expect(error == reason, "Expected \(reason.rawValue), received \(error.rawValue)") }
            }
        }
    }
    check("platform: renameatx_np RENAME_SWAP atomically exchanges two fixture directories") {
        try withScratch { root in
            let first = root.appendingPathComponent("first"), second = root.appendingPathComponent("second")
            try makeDirectory(first); try makeDirectory(second)
            try writeFile(Data("one".utf8), first.appendingPathComponent("marker"))
            let firstInode = try status(first).st_ino, secondInode = try status(second).st_ino
            try expect(renameatx_np(AT_FDCWD, first.path, AT_FDCWD, second.path, UInt32(RENAME_SWAP)) == 0, "RENAME_SWAP unsupported: errno \(errno)")
            try expect(try status(first).st_ino == secondInode && status(second).st_ino == firstInode, "Swap did not exchange directory identities")
            try expect(try Data(contentsOf: second.appendingPathComponent("marker")) == Data("one".utf8) && topLevel(first).isEmpty, "Swap lost or merged bytes")
        }
    }
    check("types: transaction, manifest and candidate outputs cannot be decoded from asserted records") {
        try expect(!((TransactionReport.self as Any) is Decodable.Type) && !((BundleManifest.self as Any) is Decodable.Type) &&
                   !((BundleManifestEntry.self as Any) is Decodable.Type) && !((CatalogueCandidate.self as Any) is Decodable.Type),
                   "An output-only trust record became decodable")
    }
}
