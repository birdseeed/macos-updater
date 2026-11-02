import Foundation
import Darwin
@_spi(Testing) import PatchedCore

// The documented tree digest is line based and joins fields with tab and LF. A relative entry
// path containing those bytes can therefore forge the lines of other entries. The contract
// rejects every ASCII control scalar (1...31 and 127) in a relative entry path. NUL can only
// occur in the signed manifest document, never in a physical name, so it has no physical case.
let controlNames: [(String, String)] = [("tab", "\t"), ("LF", "\n"), ("CR", "\r"), ("0x01", "\u{01}"), ("DEL", "\u{7f}")]

@MainActor func registerPathEncodingChecks() {
    // CHECK-ADDED: precondition for the encoding ambiguity, independent of the implementation.
    check("harness: line-based tree encoding is ambiguous for a tab and LF in a directory name") {
        try withScratch { root in
            let forged = root.appendingPathComponent("forged"), honest = root.appendingPathComponent("honest")
            try makeDirectory(forged); try makeDirectory(honest)
            try makeDirectory(forged.appendingPathComponent("a\t0755\t0\t-\ndirectory\tb"))
            try makeDirectory(honest.appendingPathComponent("a")); try makeDirectory(honest.appendingPathComponent("b"))
            let one = try walk(forged.path), two = try walk(honest.path)
            try expect(one.count == 2 && two.count == 3, "Scratch trees do not have one and two empty child directories")
            try expect(one.allSatisfy { $0.type == "directory" && $0.mode == 0o755 } &&
                       two.allSatisfy { $0.type == "directory" && $0.mode == 0o755 }, "Scratch entries are not 0755 directories")
            try expect(one.map(\.path) != two.map(\.path) && one != two, "Independent walks should yield unequal entries")
            try expect(content(one) != content(two), "Per-entry lines should differ")
            try expect(content(one).joined() == content(two).joined(), "Line bytes should be identical")
            try expect(treeDigest(one) == treeDigest(two), "Line digests should be identical")
        }
    }

    for (name, scalar) in controlNames {
        let file = "ctl" + scalar + "name"
        hazard("pinned manifest with a physical \(name) in an entry path", .invalidManifest,
               before: { try writeFile(Data("x".utf8), resource($0.source, "en.lproj/" + file)) })
        for (side, bundle) in [("source", { (l: Layout) in l.source }), ("target", { (l: Layout) in l.target })] {
            hazard("\(name) in a \(side) tree entry name added after the manifest is pinned", .unsafePath,
                   after: { try writeFile(Data("x".utf8), resource(bundle($0), "en.lproj/" + file)) })
        }
    }
    hazard("NUL in a pinned manifest entry path", .invalidManifest,
           manifest: { try editedEntries($0) { $0[$0.count - 1]["path"] = "Contents/Resources/zero\u{00}name" } })
}
