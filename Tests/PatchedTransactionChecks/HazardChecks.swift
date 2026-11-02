import Foundation
import Darwin
@_spi(Testing) import PatchedCore

/// One physical hazard in an otherwise valid fixture. `before` runs ahead of the manifest and
/// catalogue, so they agree with it; `after` runs once they are pinned. Every refusal here
/// precedes any transaction state, so the whole root must be physically unchanged.
@MainActor func hazard(_ name: String, _ reason: TransactionFailure, before: @escaping (Layout) throws -> Void = { _ in },
                       manifest: ((Layout) throws -> Data)? = nil, after: @escaping (Layout) throws -> Void = { _ in }) {
    check("hazard: \(name) refuses \(reason.rawValue) before any transaction state") {
        try withRoot { authority, layout in
            try seedFiles(layout); try before(layout)
            let prepared = try prepare(layout, manifest: manifest?(layout))
            try after(layout)
            let snapshot = try walk(layout.root.path)
            try refuses(reason) { _ = try authority.perform(prepared.request, hooks: idle()) }
            try expectSame(snapshot, try walk(layout.root.path), "Refused hazard changed the fixture root")
        }
    }
}
func resource(_ bundle: URL, _ name: String) -> URL { bundle.appendingPathComponent("Contents/Resources/" + name) }
func editedManifest(_ layout: Layout, _ edit: (inout [String: Any]) -> Void) throws -> Data {
    var value = manifestObject(try walk(layout.source.path)); edit(&value); return try json(value)
}
func editedEntries(_ layout: Layout, _ edit: (inout [[String: Any]]) -> Void) throws -> Data {
    try editedManifest(layout) { value in
        var entries = value["entries"] as! [[String: Any]]; edit(&entries); value["entries"] = entries
    }
}
func fill(_ directory: URL, files: Int) throws {
    for index in 0..<files { try writeFile(Data("x".utf8), directory.appendingPathComponent(String(format: "f%04d", index))) }
}
func replaceWithLink(_ url: URL) throws {
    let moved = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + "-real")
    try move(url, moved); try symlinkTo(moved, at: url)
}

@MainActor func registerHazardChecks() {
    // Named paths and their ancestors.
    hazard("missing target", .missingTarget, after: { try FileManager.default.removeItem(at: $0.target) })
    hazard("target is a regular file", .notDirectory, after: {
        try move($0.target, $0.profile.appendingPathComponent("moved.app")); try writeFile(Data("file".utf8), $0.target) })
    hazard("target is a symlink to a real bundle", .symlink, after: { try replaceWithLink($0.target) })
    hazard("applications ancestor is a symlink", .symlink, after: { try replaceWithLink($0.applications) })
    hazard("incoming ancestor is a symlink", .symlink, after: { try replaceWithLink($0.incoming) })
    hazard("source is a symlink to a real bundle", .symlink, after: { try replaceWithLink($0.source) })
    hazard("artifact is a symlink", .symlink, after: { try replaceWithLink($0.artifact) })
    hazard("missing source", .missingSource, after: { try FileManager.default.removeItem(at: $0.source) })
    hazard("source is a regular file", .notDirectory, after: {
        try FileManager.default.removeItem(at: $0.source); try writeFile(Data("file".utf8), $0.source) })
    hazard("missing artifact", .missingSource, after: { try FileManager.default.removeItem(at: $0.artifact) })
    hazard("existing empty transaction directory", .existingTransaction, after: { try makeDirectory($0.transaction, mode: 0o700) })
    hazard("existing regular file at the transaction path", .existingTransaction, after: { try writeFile(Data(), $0.transaction, mode: 0o600) })
    hazard("symlink at the transaction path", .symlink, after: {
        try makeDirectory($0.root.appendingPathComponent("Decoy"), mode: 0o700); try symlinkTo($0.root.appendingPathComponent("Decoy"), at: $0.transaction) })

    // Physical safety of every entry is judged before any manifest comparison.
    for (side, bundle) in [("source", { (l: Layout) in l.source }), ("target", { (l: Layout) in l.target })] {
        hazard("symlink inside the \(side) tree", .symlink, after: { try symlinkTo($0.profile.appendingPathComponent("prefs.js"), at: resource(bundle($0), "link")) })
        hazard("directory symlink inside the \(side) tree", .symlink, after: { try replaceWithLink(resource(bundle($0), "en.lproj")) })
        hazard("FIFO inside the \(side) tree", .specialFile, after: { try expect(mkfifo(resource(bundle($0), "pipe").path, 0o600) == 0, "Fixture FIFO failed") })
        hazard("hardlinked file inside the \(side) tree", .hardlink, after: {
            let file = resource(bundle($0), "data.bin"), spare = $0.profile.appendingPathComponent("spare.bin")
            try move(file, spare); try hardlink(spare, at: file) })
        hazard("executable file inside the \(side) tree", .unsafeMode, after: { try setMode(bundle($0).appendingPathComponent("Contents/MacOS/fixture"), 0o755) })
        hazard("group-writable file inside the \(side) tree", .unsafeMode, after: { try setMode(resource(bundle($0), "data.bin"), 0o664) })
        hazard("set-user-ID file inside the \(side) tree", .unsafeMode, after: { try setMode(resource(bundle($0), "data.bin"), 0o4644) })
        hazard("world-writable directory inside the \(side) tree", .unsafeMode, after: { try setMode(bundle($0).appendingPathComponent("Contents/Resources"), 0o777) })
        hazard("world-writable \(side) bundle root", .unsafeMode, after: { try setMode(bundle($0), 0o777) })
        hazard("\(side) tree above the entry bound", .treeLimit, after: { try fill(resource(bundle($0), "en.lproj"), files: TransactionLimits.maximumEntries) })
        hazard("\(side) tree above the depth bound", .treeLimit, after: {
            var directory = bundle($0)
            for _ in 0...TransactionLimits.maximumDepth { directory = directory.appendingPathComponent("d"); try makeDirectory(directory) } })
        hazard("\(side) tree above the byte bound", .treeLimit, after: {
            try writeFile(Data(count: Int(TransactionLimits.maximumTotalBytes) + 1), resource(bundle($0), "data.bin")) })
    }
    hazard("source file aliased to a target file by hardlink", .hardlink, after: {
        let name = "Contents/MacOS/fixture"
        try FileManager.default.removeItem(at: $0.source.appendingPathComponent(name))
        try hardlink($0.target.appendingPathComponent(name), at: $0.source.appendingPathComponent(name)) })
    hazard("applications directory is not private", .unsafeMode, after: { try setMode($0.applications, 0o755) })
    hazard("incoming directory is not private", .unsafeMode, after: { try setMode($0.incoming, 0o755) })
    hazard("fixture root is not private", .unsafeMode, after: { try setMode($0.root, 0o755) })
    hazard("world-writable artifact", .unsafeMode, after: { try setMode($0.artifact, 0o666) })
    hazard("hardlinked artifact", .hardlink, after: { try hardlink($0.artifact, at: $0.profile.appendingPathComponent("alias.json")) })

    // Artifact bytes are read and compared with the signed catalogue before anything else is trusted.
    hazard("artifact byte changed at the same length", .artifactMismatch, after: {
        var bytes = try Data(contentsOf: $0.artifact); bytes[bytes.count / 2] ^= 1; try writeFile(bytes, $0.artifact, mode: 0o600) })
    hazard("artifact truncated", .artifactMismatch, after: { try writeFile(try Data(contentsOf: $0.artifact).dropLast(), $0.artifact, mode: 0o600) })
    hazard("artifact extended", .artifactMismatch, after: { try writeFile(try Data(contentsOf: $0.artifact) + Data(" ".utf8), $0.artifact, mode: 0o600) })

    // Correctly signed and pinned, but not a valid manifest document.
    let documents: [(String, (Layout) throws -> Data)] = [
        ("not JSON", { _ in Data("not json".utf8) }),
        ("byte order mark", { try Data([0xef, 0xbb, 0xbf]) + editedManifest($0) { _ in } }),
        ("trailing bytes", { try editedManifest($0) { _ in } + Data(" x".utf8) }),
        ("duplicate key", { Data("{\"kind\":\"x\",".utf8) + (try editedManifest($0) { _ in }).dropFirst() }),
        ("unknown kind", { try editedManifest($0) { $0["kind"] = "patched-fixture-bundle-manifest-v2" } }),
        ("unknown schema version", { try editedManifest($0) { $0["schemaVersion"] = 2 } }),
        ("unexpected script field", { try editedManifest($0) { $0["postinstall"] = "/bin/sh" } }),
        ("missing version", { try editedManifest($0) { $0["version"] = nil } }),
        ("bundle name with a path", { try editedManifest($0) { $0["bundleName"] = "../" + Sample.bundleName } }),
        ("unexpected entry field", { try editedEntries($0) { $0[1]["owner"] = "root" } }),
        ("unsorted entries", { try editedEntries($0) { $0.swapAt(1, 2) } }),
        ("duplicate entry", { try editedEntries($0) { $0.insert($0[1], at: 1) } }),
        ("missing bundle root entry", { try editedEntries($0) { $0.removeFirst() } }),
        ("entry path traversal", { try editedEntries($0) { $0[$0.count - 1]["path"] = "Contents/../../escape" } }),
        ("absolute entry path", { try editedEntries($0) { $0[$0.count - 1]["path"] = "/tmp/escape" } }),
        ("entry path with an empty component", { try editedEntries($0) { $0[$0.count - 1]["path"] = "Contents//x" } }),
        ("unknown entry type", { try editedEntries($0) { $0[$0.count - 1]["type"] = "symlink" } }),
        ("uppercase digest", { try editedEntries($0) { $0[$0.count - 1]["sha256"] = String(repeating: "A", count: 64) } }),
        ("fractional byte length", { try editedEntries($0) { $0[$0.count - 1]["byteLength"] = 1.5 } }),
        ("mode beyond permission bits", { try editedEntries($0) { $0[$0.count - 1]["mode"] = 4096 } }),
        ("directory entry with a digest", { try editedEntries($0) { $0[0]["sha256"] = String(repeating: "a", count: 64) } })
    ]
    for (name, document) in documents {
        hazard("pinned manifest with \(name)", .invalidManifest, manifest: document)
    }
    hazard("pinned manifest above the entry bound", .treeLimit, before: { try fill(resource($0.source, "en.lproj"), files: TransactionLimits.maximumEntries) })
    hazard("pinned manifest for another bundle name", .wrongBundle, manifest: { try editedManifest($0) { $0["bundleName"] = "Other.app" } })
    hazard("pinned manifest for another bundle identifier", .wrongBundle, manifest: { try editedManifest($0) { $0["bundleID"] = "im.patched.fixture.unrelated" } })
    hazard("pinned manifest for another version", .wrongVersion, manifest: { try editedManifest($0) { $0["version"] = "157.0.2" } })

    // A physically safe source that differs from its pinned manifest.
    hazard("source byte changed at the same length", .manifestMismatch, after: {
        var bytes = try Data(contentsOf: resource($0.source, "data.bin")); bytes[4095] ^= 1; try writeFile(bytes, resource($0.source, "data.bin")) })
    hazard("source file extended", .manifestMismatch, after: {
        try writeFile(try Data(contentsOf: resource($0.source, "data.bin")) + Data([0]), resource($0.source, "data.bin")) })
    hazard("extra source file", .manifestMismatch, after: { try writeFile(Data("extra".utf8), resource($0.source, "extra.txt")) })
    hazard("extra empty source directory", .manifestMismatch, after: { try makeDirectory(resource($0.source, "Extra")) })
    hazard("missing source file", .manifestMismatch, after: { try FileManager.default.removeItem(at: resource($0.source, "new-only.txt")) })
    hazard("source file mode differs", .manifestMismatch, after: { try setMode(resource($0.source, "data.bin"), 0o600) })
    hazard("source directory mode differs", .manifestMismatch, after: { try setMode(resource($0.source, "en.lproj"), 0o700) })
    hazard("source file replaced by a directory", .manifestMismatch, after: {
        try FileManager.default.removeItem(at: resource($0.source, "new-only.txt")); try makeDirectory(resource($0.source, "new-only.txt")) })

    // Identity is read physically from both bundles and must agree with the signed candidate.
    hazard("staged bundle identifier differs from the catalogue", .wrongBundle, before: { try writeInfo($0.source, bundleID: "im.patched.fixture.unrelated", version: Sample.newVersion) })
    hazard("staged bundle version differs from the catalogue", .wrongVersion, before: { try writeInfo($0.source, bundleID: Sample.bundleID, version: "157.0.2") })
    hazard("staged bundle is not an application package", .invalidBundle, before: { try writeInfo($0.source, bundleID: Sample.bundleID, version: Sample.newVersion, packageType: "BNDL") })
    hazard("staged bundle has no Info.plist", .invalidBundle, before: { try FileManager.default.removeItem(at: $0.source.appendingPathComponent("Contents/Info.plist")) })
    hazard("staged bundle has a malformed Info.plist", .invalidBundle, before: { try writeFile(Data("<plist".utf8), $0.source.appendingPathComponent("Contents/Info.plist")) })
    hazard("target bundle identifier differs", .wrongBundle, after: { try writeInfo($0.target, bundleID: "im.patched.fixture.unrelated", version: Sample.oldVersion) })
    hazard("target already at the candidate version", .notNewer, after: { try writeInfo($0.target, bundleID: Sample.bundleID, version: Sample.newVersion) })
    hazard("target newer than the candidate", .notNewer, after: { try writeInfo($0.target, bundleID: Sample.bundleID, version: "158.0") })
    hazard("target has no Info.plist", .invalidBundle, after: { try FileManager.default.removeItem(at: $0.target.appendingPathComponent("Contents/Info.plist")) })
    hazard("target has a malformed Info.plist", .invalidBundle, after: { try writeFile(Data("<plist".utf8), $0.target.appendingPathComponent("Contents/Info.plist")) })
    hazard("target version is not numeric", .invalidBundle, after: { try writeInfo($0.target, bundleID: Sample.bundleID, version: "latest") })

    check("running fixture declaration refuses without quitting, staging or changing anything") {
        try withRoot { authority, layout in
            let prepared = try seeded(layout), log = EventLog()
            let snapshot = try walk(layout.root.path)
            try refuses(.appRunning) {
                _ = try authority.perform(prepared.request, hooks: FixtureHooks(applicationRunning: { log.running.append($0); return true },
                                                                                boundary: { log.events.append($0.rawValue) }))
            }
            try expect(log.running == [Sample.bundleID] && log.events.isEmpty, "Running refusal consulted the wrong bundle or began a transaction")
            try expectSame(snapshot, try walk(layout.root.path), "Running refusal changed the fixture root")
        }
    }
    check("declaration that the app opened before the swap refuses with the old bundle untouched") {
        try withRoot { authority, layout in
            let prepared = try seeded(layout), log = EventLog()
            let oldTree = try walk(layout.target.path), others = try unrelated(layout)
            try refuses(.appRunning) {
                _ = try authority.perform(prepared.request, hooks: FixtureHooks(applicationRunning: { log.running.append($0); return log.running.count > 1 },
                                                                                boundary: { log.events.append($0.rawValue) }))
            }
            try expect(!log.events.contains("swapped") && log.events.contains("swapIntended"), "Second running check is not immediately before the swap")
            try expectSame(oldTree, try walk(layout.target.path), "Old bundle changed although the swap was refused")
            try expectSame(others, try unrelated(layout), "Unrelated bytes changed")
            let report = try FixtureAuthority.reopenRoot(path: layout.root.path).recover(transactionDirectory: layout.transaction.path, hooks: idle())
            try expect(report.state == .rolledBack && report.recoveryAction == .oldAlreadyInPlace, "Refused swap did not recover as old-in-place")
            try expectSame(oldTree, try walk(layout.target.path), "Recovery changed the untouched old bundle")
        }
    }
}
