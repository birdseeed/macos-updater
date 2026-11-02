import Foundation
import CryptoKit
import Darwin
@_spi(Testing) import PatchedCore

struct CheckFailure: Error, CustomStringConvertible { let description: String }
struct Injected: Error {}
func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw CheckFailure(description: message) }
}
func refuses(_ reason: TransactionFailure, _ action: () throws -> Void) throws {
    do { try action() } catch let error as TransactionFailure {
        try expect(error == reason, "Expected \(reason.rawValue), received \(error.rawValue)")
        return
    }
    throw CheckFailure(description: "IMPROPER ACCEPTANCE: expected refusal \(reason.rawValue)")
}
func json(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
}
func object(_ data: Data) throws -> [String: Any] {
    guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw CheckFailure(description: "Fixture is not an object")
    }
    return result
}
func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func exists(_ url: URL) -> Bool { var info = stat(); return lstat(url.path, &info) == 0 }
func status(_ url: URL) throws -> stat {
    var info = stat()
    guard lstat(url.path, &info) == 0 else { throw CheckFailure(description: "Missing fixture path \(url.path)") }
    return info
}
func unsigned(_ value: Any?) -> UInt64? { (value as? NSNumber)?.uint64Value }

// MARK: Independent physical tree reading. Nothing here calls the transaction core.

struct Entry: Equatable {
    let path: String, type: String, mode: UInt16, size: Int64, sha: String, inode: UInt64, link: String
    var line: String { "\(type)\t\(path)\t\(String(format: "%04o", mode))\t\(size)\t\(sha)\n" }
}
/// Every entry beneath `root`, without following symlinks. `.` is the root itself.
func walk(_ root: String) throws -> [Entry] {
    var result: [Entry] = []
    func visit(_ absolute: String, _ relative: String) throws {
        var info = stat()
        guard lstat(absolute, &info) == 0 else { throw CheckFailure(description: "lstat failed: \(absolute)") }
        let mode = UInt16(info.st_mode & 0o7777), inode = UInt64(info.st_ino)
        switch info.st_mode & S_IFMT {
        case S_IFDIR:
            result.append(Entry(path: relative, type: "directory", mode: mode, size: 0, sha: "-", inode: inode, link: ""))
            for name in try FileManager.default.contentsOfDirectory(atPath: absolute) {
                try visit(absolute + "/" + name, relative == "." ? name : relative + "/" + name)
            }
        case S_IFREG:
            let data = try Data(contentsOf: URL(fileURLWithPath: absolute))
            result.append(Entry(path: relative, type: "file", mode: mode, size: Int64(data.count), sha: sha(data), inode: inode, link: ""))
        case S_IFLNK:
            let destination = try FileManager.default.destinationOfSymbolicLink(atPath: absolute)
            result.append(Entry(path: relative, type: "symlink", mode: mode, size: 0, sha: "-", inode: inode, link: destination))
        default:
            result.append(Entry(path: relative, type: "special", mode: mode, size: 0, sha: "-", inode: inode, link: ""))
        }
    }
    try visit(root, ".")
    return result.sorted { Array($0.path.utf8).lexicographicallyPrecedes(Array($1.path.utf8)) }
}
func content(_ tree: [Entry]) -> [String] { tree.map(\.line) }
/// Documented tree digest: SHA-256 over one line per entry in ascending path byte order.
func treeDigest(_ tree: [Entry]) -> String { sha(Data(tree.map(\.line).joined().utf8)) }
func expectSame(_ expected: [Entry], _ actual: [Entry], _ message: String) throws {
    if expected == actual { return }
    for index in 0..<max(expected.count, actual.count) {
        let before = index < expected.count ? expected[index] : nil, after = index < actual.count ? actual[index] : nil
        if before != after {
            throw CheckFailure(description: "\(message): first difference at entry \(index): \(String(describing: before)) became \(String(describing: after))")
        }
    }
}
func expectContent(_ expected: [Entry], _ actual: [Entry], _ message: String) throws {
    try expect(content(expected) == content(actual),
               "\(message): \(expected.count) expected entries with digest \(treeDigest(expected)), found \(actual.count) with \(treeDigest(actual))")
}
/// Compares a core-reported manifest with an independently read tree: every entry, count and digest.
func expectManifest(_ manifest: BundleManifest, _ tree: [Entry], _ message: String) throws {
    let reported = manifest.entries.map {
        "\($0.type)\t\($0.path)\t\(String(format: "%04o", $0.mode))\t\($0.byteLength)\t\($0.type == "directory" ? "-" : $0.sha256)\n"
    }
    try expect(reported == content(tree), "\(message): reported entries differ from the physical tree")
    try expect(manifest.fileCount == tree.filter { $0.type == "file" }.count, "\(message): file count")
    try expect(manifest.directoryCount == tree.filter { $0.type == "directory" }.count, "\(message): directory count")
    try expect(manifest.totalBytes == tree.reduce(0) { $0 + $1.size }, "\(message): total bytes")
    try expect(manifest.treeSHA256 == treeDigest(tree), "\(message): tree digest")
}
/// Documented manifest document for a tree of plain files and directories.
func manifestObject(_ tree: [Entry], version: String = Sample.newVersion) -> [String: Any] {
    let rows: [[String: Any]] = tree.filter { $0.type == "file" || $0.type == "directory" }.map {
        $0.type == "directory" ? ["path": $0.path, "type": "directory", "mode": Int($0.mode)]
            : ["path": $0.path, "type": "file", "mode": Int($0.mode), "byteLength": NSNumber(value: $0.size), "sha256": $0.sha]
    }
    return ["schemaVersion": 1, "kind": "patched-fixture-bundle-manifest-v1", "bundleName": Sample.bundleName,
            "bundleID": Sample.bundleID, "version": version, "entries": rows]
}
/// Lines of a manifest document, for comparison with `content` of an independently read tree.
func manifestLines(_ data: Data) throws -> [String] {
    guard let rows = try object(data)["entries"] as? [[String: Any]] else { throw CheckFailure(description: "Manifest has no entries") }
    return try rows.map { row in
        guard let path = row["path"] as? String, let type = row["type"] as? String, let mode = unsigned(row["mode"]) else {
            throw CheckFailure(description: "Malformed manifest entry")
        }
        let length = type == "file" ? (unsigned(row["byteLength"]) ?? UInt64.max) : 0
        return "\(type)\t\(path)\t\(String(format: "%04o", mode))\t\(length)\t\(type == "file" ? (row["sha256"] as? String ?? "?") : "-")\n"
    }
}

// MARK: Disposable fixture construction beneath this worktree's .build only.

enum Sample {
    static let bundleName = "FixtureSample.app"
    static let bundleID = "im.patched.fixture.sample"
    static let teamID = "FIXTURE000"
    static let oldVersion = "157.0"
    static let newVersion = "157.0.1"
    static let now = 1_800_000_000.0
    static let keyID = "fixture-only-ed25519-transaction-v1"
    static let catalogueID = "fixture.transaction"
    static let rootPrefix = "patched-transaction-fixture-"
    // Deterministic TEST-ONLY key material lives exclusively in this executable target.
    static func key(_ alternate: Bool = false) throws -> Curve25519.Signing.PrivateKey {
        try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: alternate ? 0x54 : 0x58, count: 32))
    }
}

struct Layout {
    let root: URL
    var applications: URL { root.appendingPathComponent("Applications") }
    var incoming: URL { root.appendingPathComponent("Incoming") }
    var profile: URL { root.appendingPathComponent("Profile") }
    var transaction: URL { root.appendingPathComponent("Transaction") }
    var target: URL { applications.appendingPathComponent(Sample.bundleName) }
    var other: URL { applications.appendingPathComponent("Other.app") }
    var source: URL { incoming.appendingPathComponent(Sample.bundleName) }
    var artifact: URL { incoming.appendingPathComponent("FixtureSample.manifest.json") }
    var journal: URL { transaction.appendingPathComponent("journal.json") }
    var lock: URL { transaction.appendingPathComponent("lock") }
    var exchange: URL { transaction.appendingPathComponent("exchange") }
    var exchanged: URL { exchange.appendingPathComponent(Sample.bundleName) }
}

func buildDirectory() throws -> String {
    guard let physical = realpath(FileManager.default.currentDirectoryPath + "/.build", nil) else {
        throw CheckFailure(description: "No physical build fixture root")
    }
    defer { free(physical) }
    return String(cString: physical)
}
func makeDirectory(_ url: URL, mode: mode_t = 0o755) throws {
    guard mkdir(url.path, mode) == 0, chmod(url.path, mode) == 0 else { throw CheckFailure(description: "Fixture mkdir failed: \(url.path)") }
}
func writeFile(_ data: Data, _ url: URL, mode: mode_t = 0o644) throws {
    try data.write(to: url)
    guard chmod(url.path, mode) == 0 else { throw CheckFailure(description: "Fixture chmod failed: \(url.path)") }
}
func setMode(_ url: URL, _ mode: mode_t) throws {
    guard chmod(url.path, mode) == 0 else { throw CheckFailure(description: "Fixture chmod failed: \(url.path)") }
}
func move(_ from: URL, _ to: URL) throws {
    guard rename(from.path, to.path) == 0 else { throw CheckFailure(description: "Fixture rename failed: \(from.path)") }
}
func symlinkTo(_ destination: URL, at link: URL) throws {
    guard symlink(destination.path, link.path) == 0 else { throw CheckFailure(description: "Fixture symlink failed: \(link.path)") }
}
func hardlink(_ existing: URL, at link: URL) throws {
    guard Darwin.link(existing.path, link.path) == 0 else { throw CheckFailure(description: "Fixture hardlink failed: \(link.path)") }
}
func removeFixture(_ path: String) {
    guard let build = try? buildDirectory(), path.hasPrefix(build + "/patched-transaction-") else { return }
    var info = stat()
    guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return }
    try? FileManager.default.removeItem(atPath: path)
}
/// A plain test-owned directory for checks that need no transaction authority.
func withScratch(_ body: (URL) throws -> Void) throws {
    let root = URL(fileURLWithPath: try buildDirectory() + "/patched-transaction-scratch-" + UUID().uuidString)
    try makeDirectory(root, mode: 0o700)
    defer { removeFixture(root.path) }
    try body(root)
}
func freshRootPath() throws -> String { try buildDirectory() + "/" + Sample.rootPrefix + UUID().uuidString }
/// The authority itself exclusively creates the root; the check only names it and removes it afterwards.
func withRoot(_ body: (FixtureAuthority, Layout) throws -> Void) throws {
    let path = try freshRootPath()
    defer { removeFixture(path) }
    let authority = try FixtureAuthority.createFreshRoot(path: path)
    try body(authority, Layout(root: URL(fileURLWithPath: path)))
}

func writeInfo(_ bundle: URL, bundleID: String, version: String, packageType: String = "APPL") throws {
    let values: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version,
                                 "CFBundlePackageType": packageType, "CFBundleExecutable": "fixture", "CFBundleName": "Fixture Sample"]
    let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
    try writeFile(data, bundle.appendingPathComponent("Contents/Info.plist"))
}
/// Unsigned and not runnable: no file has an execute bit and the "executable" is explanatory text.
func writeBundle(_ bundle: URL, bundleID: String, version: String, label: String) throws {
    for directory in ["", "Contents", "Contents/MacOS", "Contents/Resources", "Contents/Resources/en.lproj"] {
        try makeDirectory(directory.isEmpty ? bundle : bundle.appendingPathComponent(directory))
    }
    try writeInfo(bundle, bundleID: bundleID, version: version)
    try writeFile(Data("FIXTURE ONLY. Not a program. \(label) \(version)\n".utf8), bundle.appendingPathComponent("Contents/MacOS/fixture"))
    let block = Data(SHA256.hash(data: Data("\(label) \(version)".utf8)))
    try writeFile(Data((0..<128).flatMap { _ in block }), bundle.appendingPathComponent("Contents/Resources/data.bin"))
    try writeFile(Data("\"label\" = \"\(label) \(version)\";\n".utf8), bundle.appendingPathComponent("Contents/Resources/en.lproj/strings.txt"))
    try writeFile(Data("present only in \(label)\n".utf8), bundle.appendingPathComponent("Contents/Resources/\(label)-only.txt"))
}
/// Old named target, an unrelated app, dummy profile bytes and the incoming new bundle.
func seedFiles(_ layout: Layout) throws {
    for directory in [layout.applications, layout.incoming, layout.profile] { try makeDirectory(directory, mode: 0o700) }
    try writeBundle(layout.target, bundleID: Sample.bundleID, version: Sample.oldVersion, label: "old")
    try writeBundle(layout.other, bundleID: "im.patched.fixture.unrelated", version: "9.9", label: "unrelated")
    try writeBundle(layout.source, bundleID: Sample.bundleID, version: Sample.newVersion, label: "new")
    try writeFile(Data("user_pref(\"fixture.dummy\", true);\n".utf8), layout.profile.appendingPathComponent("prefs.js"), mode: 0o600)
    try writeFile(Data(repeating: 0x5a, count: 2048), layout.profile.appendingPathComponent("places.sqlite"), mode: 0o600)
}

func signedCatalogue(artifact: Data, version: String = Sample.newVersion, bundleID: String = Sample.bundleID,
                     alternateKey: Bool = false) throws -> Data {
    let payload = try json(["schemaVersion": 1, "domain": "im.patched.catalogue.v1", "keyID": Sample.keyID,
        "catalogueID": Sample.catalogueID, "sequence": 7, "issuedAt": Int64(Sample.now), "expiresAt": Int64(Sample.now + 3600),
        "artifact": ["bundleID": bundleID, "teamID": Sample.teamID, "platform": "macOS", "minimumOS": "13.0",
                     "maximumOS": "27.9", "version": version, "sha256": sha(artifact), "byteLength": artifact.count]])
    let signature = try Sample.key(alternateKey).signature(for: Data("im.patched.catalogue.v1\0".utf8) + payload)
    return try json(["keyID": Sample.keyID, "payload": payload.base64EncodedString(), "signature": signature.base64EncodedString()])
}
/// A candidate from the real PAT-2581 verifier over an explicitly bootstrapped fixture namespace.
func verifiedCandidate(envelope: Data, in directory: URL, bundleID: String = Sample.bundleID) throws -> CatalogueCandidate {
    let holder = directory.appendingPathComponent("Catalogue-" + UUID().uuidString)
    try makeDirectory(holder, mode: 0o700)
    let trust = FixtureTrust(keyID: Sample.keyID, catalogueID: Sample.catalogueID, publicKey: try Sample.key().publicKey.rawRepresentation)
    let policy = CandidatePolicy(bundleID: bundleID, teamID: Sample.teamID, osVersion: "27.0.1", installedVersion: Sample.oldVersion)
    return try CatalogueVerifier(trust: trust, policy: policy, stateDirectory: holder.appendingPathComponent("state").path)
        .bootstrapFreshProofNamespace(envelope: envelope, now: Sample.now)
}

struct Prepared {
    let layout: Layout
    let candidate: CatalogueCandidate
    let manifest: Data
    var request: UpdateRequest { requesting() }
    func requesting(target: String? = nil, source: String? = nil, artifact: String? = nil, transaction: String? = nil,
                 trigger: TransactionTrigger = .explicitUserAction) -> UpdateRequest {
        UpdateRequest(candidate: candidate, artifactPath: artifact ?? layout.artifact.path, sourceBundle: source ?? layout.source.path,
                      target: target ?? layout.target.path, transactionDirectory: transaction ?? layout.transaction.path, trigger: trigger)
    }
}
/// Writes the pinned manifest as the catalogue artifact and obtains a real signed fixture candidate for its bytes.
func prepare(_ layout: Layout, manifest supplied: Data? = nil) throws -> Prepared {
    let manifest = try supplied ?? json(manifestObject(walk(layout.source.path)))
    try writeFile(manifest, layout.artifact, mode: 0o600)
    let candidate = try verifiedCandidate(envelope: signedCatalogue(artifact: manifest), in: layout.root)
    return Prepared(layout: layout, candidate: candidate, manifest: manifest)
}
func seeded(_ layout: Layout) throws -> Prepared { try seedFiles(layout); return try prepare(layout) }

final class EventLog {
    var events: [String] = []
    var running: [String] = []
    func index(_ event: String) -> Int? { events.firstIndex(of: event) }
    func count(_ event: String) -> Int { events.filter { $0 == event }.count }
}
func idle(boundary: ((TransactionBoundary) throws -> Void)? = nil,
          sync: ((TransactionSyncOperation) throws -> Void)? = nil) -> FixtureHooks {
    FixtureHooks(applicationRunning: { _ in false }, boundary: boundary, sync: sync)
}
/// Everything a transaction of the named target must never change.
func unrelated(_ layout: Layout) throws -> [Entry] {
    try walk(layout.other.path) + walk(layout.profile.path) + walk(layout.incoming.path)
}
func journalFields(_ layout: Layout) throws -> [String: Any] { try object(Data(contentsOf: layout.journal)) }
func journalState(_ layout: Layout) throws -> String {
    guard let state = try journalFields(layout)["state"] as? String else { throw CheckFailure(description: "Journal has no state") }
    return state
}
func editJournal(_ layout: Layout, _ edit: (inout [String: Any]) -> Void) throws {
    var fields = try journalFields(layout); edit(&fields)
    try writeFile(json(fields), layout.journal, mode: 0o600)
}
func topLevel(_ url: URL) throws -> Set<String> { Set(try FileManager.default.contentsOfDirectory(atPath: url.path)) }
func expectFixtureOnly(_ report: TransactionReport) throws {
    try expect(report.origin == "fixture" && !report.freshOSValidation && !report.installationAuthorized && !report.installedFirefoxProof,
               "Fixture transaction asserted OS validation, installation authority or Firefox proof")
    let encoded = try object(JSONEncoder().encode(report))
    try expect(encoded["origin"] as? String == "fixture" && encoded["freshOSValidation"] as? Bool == false &&
               encoded["installationAuthorized"] as? Bool == false && encoded["installedFirefoxProof"] as? Bool == false,
               "Encoded fixture report lost its explicit no-trust fields")
    try expect(report.runningCheck == "fixtureProbe", "Fixture running declaration presented as an OS observation")
}
/// Runs a real transaction that is interrupted by a refusal injected at one boundary.
func interrupted(_ authority: FixtureAuthority, _ layout: Layout, at boundary: TransactionBoundary) throws -> Prepared {
    let prepared = try seeded(layout)
    try refuses(.persistenceFailed) {
        _ = try authority.perform(prepared.request, hooks: idle(boundary: { if $0 == boundary { throw Injected() } }))
    }
    return prepared
}
func boundedChild(_ arguments: [String]) throws -> (Int32, String) {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    process.arguments = arguments; process.standardOutput = pipe; process.standardError = pipe
    try process.run()
    let deadline = Date().addingTimeInterval(8)
    while process.isRunning && Date() < deadline { usleep(10_000) }
    if process.isRunning {
        kill(process.processIdentifier, SIGKILL); process.waitUntilExit()
        throw CheckFailure(description: "Transaction child exceeded eight-second fixture bound")
    }
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
}
let noTrustSuffix = "origin=fixture freshOSValidation=false installationAuthorized=false installedFirefoxProof=false"
