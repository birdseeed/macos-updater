import Foundation
import Darwin
@_spi(Testing) import PatchedCore
@_spi(Testing) import PatchedOperator

// PAT-2583 root creation boundary regressions. Each case names one new operator root and one
// new sibling directly beneath this executable's physical .build, and touches nothing else.
// The observer of `createFreshRoot` is used only to act as a same-user process at a real
// step of creation: it renames the root being created to the sibling and puts a private
// decoy directory at the authorised name. Creation must then refuse, and from that moment
// neither the moved root nor the decoy may gain or change a single entry.

let rootCreationPrefix = "root creation: "
let rootCreationPoints: [OperatorRootCreationPoint] = [.rootCaptured, .inputCreated, .publicationsCreated, .lockFlushed,
                                                       .checkpointFlushed, .namespaceFlushed, .directoriesSynced]
/// The names a root physically holds when each point is reported, in order of creation.
let rootCreationNames: [OperatorRootCreationPoint: Set<String>] = [
    .rootCaptured: [], .inputCreated: ["input"], .publicationsCreated: ["input", "publications"],
    .lockFlushed: ["input", "publications", "lock"], .checkpointFlushed: ["input", "publications", "lock", "checkpoint.json"],
    .namespaceFlushed: ["input", "publications", "lock", "checkpoint.json", "namespace.json"],
    .directoriesSynced: ["input", "publications", "lock", "checkpoint.json", "namespace.json"]]

/// Every entry beneath `root` without following symlinks or calling the operator library:
/// type, mode, owner, inode, and for files the link count, byte length and content digest.
func physicalSnapshot(_ root: URL) throws -> [String: String] {
    var result: [String: String] = [:]
    func visit(_ url: URL, _ relative: String) throws {
        let info = try status(url)
        let common = String(format: "%04o", info.st_mode & 0o7777) + " owner=\(info.st_uid) inode=\(info.st_ino)"
        switch info.st_mode & S_IFMT {
        case S_IFDIR:
            result[relative] = "directory \(common)"
            for name in try FileManager.default.contentsOfDirectory(atPath: url.path) {
                try visit(url.appendingPathComponent(name), relative == "." ? name : relative + "/" + name)
            }
        case S_IFREG: result[relative] = "file \(common) links=\(info.st_nlink) bytes=\(info.st_size) sha256=\(sha(try bytes(url)))"
        case S_IFLNK: result[relative] = "symlink \(try FileManager.default.destinationOfSymbolicLink(atPath: url.path))"
        default: result[relative] = "special \(common)"
        }
    }
    try visit(root, ".")
    return result
}
/// What differs between two physical snapshots, or `nil` when nothing does.
func laterWrites(from before: [String: String], to after: [String: String]) -> String? {
    let added = after.keys.filter { before[$0] == nil }.sorted()
    let removed = before.keys.filter { after[$0] == nil }.sorted()
    let changed = before.keys.filter { after[$0] != nil && after[$0] != before[$0] }.sorted()
    guard !added.isEmpty || !removed.isEmpty || !changed.isEmpty else { return nil }
    return "added \(added) changed \(changed) removed \(removed)"
}

/// What a boundary case recorded inside the observer, read only after creation returned.
final class RootCreationEvidence {
    var observed: [OperatorRootCreationPoint] = []
    var created: stat?
    var moved: [String: String]?
    var decoy: [String: String]?
    var atThrow: [String: String]?
}

/// Names one not-yet-existing operator root and one not-yet-existing sibling beneath `.build`.
/// Only those two new names are removed afterwards, and only once the evidence was compared.
func withBoundaryNames(_ body: (_ root: URL, _ moved: URL) throws -> Void) throws {
    let build = try buildDirectory(), id = UUID().uuidString
    let root = build.appendingPathComponent("patched-operator-fixture-\(id)")
    let moved = build.appendingPathComponent("patched-operator-moved-\(id)")
    try expect(!exists(root) && !exists(moved), "Boundary fixture names already exist")
    try expect(root.deletingLastPathComponent().path == build.path && moved.deletingLastPathComponent().path == build.path,
               "Boundary fixture names are not direct children of the build directory")
    defer { try? FileManager.default.removeItem(at: moved); try? FileManager.default.removeItem(at: root) }
    try body(root, moved)
}

@MainActor func registerRootCreationBoundaryChecks() {
    check(rootCreationPrefix + "control: an observed, untouched creation reports every real step once and yields the accepted initial root") {
        try withBoundaryNames { root, _ in
            let evidence = RootCreationEvidence()
            var mismatches: [String] = []
            let authority = try FixtureOperatorAuthority.createFreshRoot(path: root.path, trust: Sample.trust()) { point in
                evidence.observed.append(point)
                let held = try names(root)
                if held != rootCreationNames[point] { mismatches.append("\(point.rawValue) held \(held.sorted())") }
            }
            try expect(evidence.observed == rootCreationPoints, "Creation reported \(evidence.observed.map(\.rawValue))")
            try expect(mismatches.isEmpty, "A point was reported around something other than its real step: \(mismatches)")
            try expect(authority.root == root.path, "The authority names a different root")
            let layout = Layout(build: try buildDirectory(), root: root, scratch: root)
            try expectPrivateDirectory(root, "Root"); try expectPrivateDirectory(layout.input, "Input")
            try expectPrivateDirectory(layout.publications, "Publications")
            try expectPrivateFile(layout.namespace, "Namespace record"); try expectPrivateFile(layout.lock, "Lock")
            try expect(try names(root) == ["namespace.json", "checkpoint.json", "lock", "input", "publications"], "Root entries differ")
            try expect(try names(layout.input).isEmpty && names(layout.publications).isEmpty && bytes(layout.lock).isEmpty,
                       "A fresh root holds input, a publication or lock bytes")
            let checkpoint = try checkpointFields(layout)
            try expect(checkpoint.sequence == 0 && checkpoint.payloadSHA256 == Sample.zeroDigest, "Initial checkpoint is not sequence 0 with the zero digest")
            let marker = try object(bytes(layout.namespace))
            try expect(marker["keyID"] as? String == Sample.keyID && marker["catalogueID"] as? String == Sample.catalogueID,
                       "Namespace record does not name the explicit fixture trust")
            // The same acceptance as an unobserved creation: reopen, refuse a second create, change nothing.
            let before = try physicalSnapshot(root)
            let reopened = try FixtureOperatorAuthority.reopenRoot(path: root.path, trust: Sample.trust())
            try expect(reopened.root == root.path, "Reopen names a different root")
            try refuses(.existingNamespace) { _ = try FixtureOperatorAuthority.createFreshRoot(path: root.path, trust: Sample.trust()) }
            try refuses(.existingNamespace) { _ = try FixtureOperatorAuthority.createFreshRoot(path: root.path, trust: Sample.trust()) { _ in } }
            try expect(try physicalSnapshot(root) == before, "Reopening or a refused second creation changed the root")
        }
    }
    check(rootCreationPrefix + "control: an observed creation writes the same records as an unobserved one") {
        try withBoundaryNames { observed, _ in
            try withBoundaryNames { plain, _ in
                _ = try FixtureOperatorAuthority.createFreshRoot(path: observed.path, trust: Sample.trust()) { _ in }
                _ = try FixtureOperatorAuthority.createFreshRoot(path: plain.path, trust: Sample.trust())
                for name in ["namespace.json", "checkpoint.json", "lock"] {
                    try expect(try bytes(observed.appendingPathComponent(name)) == bytes(plain.appendingPathComponent(name)), "\(name) differs")
                }
                func shape(_ root: URL) throws -> [String: String] {
                    try snapshot(root).mapValues { $0.replacingOccurrences(of: #"inode=\d+ "#, with: "", options: .regularExpression) }
                }
                try expect(try shape(observed) == shape(plain), "Observed and unobserved roots differ in entries, modes or bytes")
            }
        }
    }
    for point in rootCreationPoints {
        check(rootCreationPrefix + "control: an observer refusal at \(point.rawValue) stops creation with no later write") {
            try withBoundaryNames { root, _ in
                let evidence = RootCreationEvidence()
                do {
                    _ = try FixtureOperatorAuthority.createFreshRoot(path: root.path, trust: Sample.trust()) { reported in
                        evidence.observed.append(reported)
                        guard reported == point else { return }
                        evidence.atThrow = try physicalSnapshot(root)
                        throw Injected()
                    }
                    throw CheckFailure(description: "IMPROPER ACCEPTANCE: creation returned a root after its observer refused at \(point.rawValue)")
                } catch is Injected {}
                try expect(evidence.observed.last == point && evidence.observed.filter({ $0 == point }).count == 1,
                           "Creation went on to \(evidence.observed.map(\.rawValue)) after a refusal at \(point.rawValue)")
                guard let atThrow = evidence.atThrow else { throw CheckFailure(description: "The observer never reached \(point.rawValue)") }
                try expect(Set(atThrow.keys.filter { $0 != "." && !$0.contains("/") }) == rootCreationNames[point],
                           "\(point.rawValue) was reported around something other than its real step: \(atThrow.keys.sorted())")
                // The incomplete root is preserved exactly as the refusal left it: not continued, repaired or deleted.
                let after = try physicalSnapshot(root)
                if let difference = laterWrites(from: atThrow, to: after) {
                    throw CheckFailure(description: "LATER WRITE after an observer refusal at \(point.rawValue): \(difference)")
                }
            }
        }
    }
    for point in rootCreationPoints {
        check(rootCreationPrefix + "boundary: the root renamed away with a decoy at its name after \(point.rawValue) is refused with no later write") {
            try withBoundaryNames { root, moved in
                let evidence = RootCreationEvidence()
                var outcome = "accepted"
                do {
                    _ = try FixtureOperatorAuthority.createFreshRoot(path: root.path, trust: Sample.trust()) { reported in
                        evidence.observed.append(reported)
                        guard reported == point, evidence.moved == nil else { return }
                        // Acting as another same-user process: only this case's own two new names are touched.
                        evidence.created = try status(root)
                        guard rename(root.path, moved.path) == 0 else { throw CheckFailure(description: "Fixture rename failed: errno \(errno)") }
                        try makeDirectory(root)
                        evidence.moved = try physicalSnapshot(moved)
                        evidence.decoy = try physicalSnapshot(root)
                    }
                } catch let error as OperatorFailure { outcome = error.rawValue }
                guard let created = evidence.created, let movedBefore = evidence.moved, let decoyBefore = evidence.decoy else {
                    throw CheckFailure(description: "The substitution at \(point.rawValue) was never made: creation ended \(outcome) after \(evidence.observed.map(\.rawValue))")
                }
                // The evidence is read before anything is judged or removed.
                let movedAfter = try physicalSnapshot(moved), decoyAfter = try physicalSnapshot(root)
                let movedInfo = try status(moved), decoyInfo = try status(root)
                try expect(movedInfo.st_ino == created.st_ino && movedInfo.st_dev == created.st_dev && decoyInfo.st_ino != created.st_ino,
                           "The fixture did not move the created root and put a different directory at its name")
                try expect(Set(movedBefore.keys.filter { $0 != "." && !$0.contains("/") }) == rootCreationNames[point],
                           "\(point.rawValue) was reported around something other than its real step: \(movedBefore.keys.sorted())")
                try expect(decoyBefore == [".": "directory 0700 owner=\(geteuid()) inode=\(decoyInfo.st_ino)"], "The decoy was not an empty private directory")
                var findings: [String] = []
                if let difference = laterWrites(from: movedBefore, to: movedAfter) {
                    findings.append("LATER WRITE INTO THE MOVED ROOT after it left the authorised name at \(point.rawValue): \(difference)")
                }
                if let difference = laterWrites(from: decoyBefore, to: decoyAfter) {
                    findings.append("LATER WRITE INTO THE DECOY at the authorised name after \(point.rawValue): \(difference)")
                }
                if !["identityChanged", "unsafePath", "missingState"].contains(outcome) {
                    findings.append(outcome == "accepted" ? "IMPROPER ACCEPTANCE: creation returned a root whose name holds a decoy"
                                                          : "creation ended \(outcome), not identityChanged, unsafePath or missingState")
                }
                let later = evidence.observed.drop { $0 != point }.dropFirst().map(\.rawValue)
                if !findings.isEmpty {
                    throw CheckFailure(description: findings.joined(separator: "; ") + "; creation ended \(outcome)" +
                                       (later.isEmpty ? "" : " after continuing through \(later)"))
                }
            }
        }
    }
}

/// The explicit `--root-creation-regressions` command: only the cases registered above.
@MainActor func runRootCreationRegressions(_ registered: [(String, @MainActor () throws -> Void)]) -> Int32 {
    let selected = registered.filter { $0.0.hasPrefix(rootCreationPrefix) }
    var failures = 0
    for (name, action) in selected {
        do { try action(); print("PASS operator: \(name)") }
        catch { failures += 1; print("FAIL operator: \(name): \(error)") }
    }
    print("Root creation boundary regressions: \(selected.count) cases, \(failures) failures. Fixture trust only. No production key, publication, fresh OS trust or installation authority.")
    return failures == 0 ? 0 : 1
}
