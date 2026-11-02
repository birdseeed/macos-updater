import Foundation
import CryptoKit
import Darwin
import ArtifactInspection
@_spi(Testing) import PatchedCore
@_spi(Testing) import PatchedOperator

struct CheckFailure: Error, CustomStringConvertible { let description: String }
struct Injected: Error {}
func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw CheckFailure(description: message) }
}
func refuses(_ reason: OperatorFailure, _ action: () throws -> Void) throws {
    do { try action() } catch let error as OperatorFailure {
        try expect(error == reason, "Expected \(reason.rawValue), received \(error.rawValue)")
        return
    }
    throw CheckFailure(description: "IMPROPER ACCEPTANCE: expected refusal \(reason.rawValue)")
}
func consumerRefuses(_ reason: CoreFailure, _ action: () throws -> Void) throws {
    do { try action() } catch let error as CoreFailure {
        try expect(error == reason, "Expected consumer \(reason.rawValue), received \(error.rawValue)")
        return
    }
    throw CheckFailure(description: "IMPROPER ACCEPTANCE: expected consumer refusal \(reason.rawValue)")
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
func bytes(_ url: URL) throws -> Data { try Data(contentsOf: url) }
/// An integer JSON token: never a boolean, a fraction or a quoted number.
func unsigned(_ value: Any?) -> UInt64? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), !CFNumberIsFloatType(number) else { return nil }
    return number.uint64Value
}
func flag(_ value: Any?) -> Bool? {
    guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
    return number.boolValue
}
func writeFile(_ data: Data, _ url: URL, mode: mode_t = 0o600) throws {
    try data.write(to: url, options: .withoutOverwriting)
    guard chmod(url.path, mode) == 0 else { throw CheckFailure(description: "Fixture chmod failed") }
}
func makeDirectory(_ url: URL, mode: mode_t = 0o700) throws {
    guard mkdir(url.path, mode) == 0, chmod(url.path, mode) == 0 else { throw CheckFailure(description: "Fixture mkdir failed: \(url.path) errno \(errno)") }
}

// MARK: Independent physical reading. Nothing here calls the operator library.

/// Every entry beneath `root` without following symlinks: type, mode, link count and content digest.
func snapshot(_ root: URL) throws -> [String: String] {
    var result: [String: String] = [:]
    func visit(_ url: URL, _ relative: String) throws {
        let info = try status(url)
        let mode = String(format: "%04o", info.st_mode & 0o7777)
        switch info.st_mode & S_IFMT {
        case S_IFDIR:
            result[relative] = "directory \(mode)"
            for name in try FileManager.default.contentsOfDirectory(atPath: url.path) {
                try visit(url.appendingPathComponent(name), relative == "." ? name : relative + "/" + name)
            }
        case S_IFREG: result[relative] = "file \(mode) links=\(info.st_nlink) inode=\(info.st_ino) \(sha(try bytes(url)))"
        case S_IFLNK: result[relative] = "symlink \(try FileManager.default.destinationOfSymbolicLink(atPath: url.path))"
        default: result[relative] = "special \(mode)"
        }
    }
    try visit(root, ".")
    return result
}
func names(_ url: URL) throws -> Set<String> { Set(try FileManager.default.contentsOfDirectory(atPath: url.path)) }
func expectPrivateFile(_ url: URL, _ what: String) throws {
    let info = try status(url)
    try expect(info.st_mode & S_IFMT == S_IFREG && info.st_mode & 0o7777 == 0o600 && info.st_nlink == 1 && info.st_uid == geteuid(),
               "\(what) is not a single-link owned mode-0600 regular file")
}
func expectPrivateDirectory(_ url: URL, _ what: String) throws {
    let info = try status(url)
    try expect(info.st_mode & S_IFMT == S_IFDIR && info.st_mode & 0o7777 == 0o700 && info.st_uid == geteuid(),
               "\(what) is not an owned mode-0700 directory")
}

// MARK: Deterministic TEST-ONLY trust. Private bytes exist in this executable target and nowhere else.

enum Sample {
    static let now = 1_800_000_000.0
    static let issued: UInt64 = 1_800_000_000
    static let domain = "im.patched.catalogue.v1"
    static let keyID = "fixture-only-operator-ed25519-v1"
    static let catalogueID = "fixture.operator.firefox"
    static let version = "157.0.1"
    static let installed = "157.0"
    static let bundleID = "org.mozilla.firefox"
    static let teamID = "43AQ936H96"
    static let artifactName = "Firefox-fixture.dmg"
    static let artifact = Data("PATCHED OPERATOR FIXTURE ARTIFACT. NOT A DISK IMAGE AND NOT FIREFOX.\n".utf8)
    static let zeroDigest = String(repeating: "0", count: 64)

    static func key(_ alternate: Bool = false) throws -> Curve25519.Signing.PrivateKey {
        try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: alternate ? 0x58 : 0x4F, count: 32))
    }
    static func trust(keyID: String = keyID, catalogueID: String = catalogueID) throws -> FixtureTrust {
        FixtureTrust(keyID: keyID, catalogueID: catalogueID, publicKey: try key().publicKey.rawRepresentation)
    }
    static func request(sequence: UInt64 = 7, keyID: String = keyID, catalogueID: String = catalogueID,
                        issuedAt: UInt64 = issued, expiresAt: UInt64 = issued + 3_600,
                        minimumOS: String = "13.0", maximumOS: String = "27.9") -> CatalogueRequest {
        CatalogueRequest(keyID: keyID, catalogueID: catalogueID, sequence: sequence, issuedAt: issuedAt, expiresAt: expiresAt,
                         minimumOS: minimumOS, maximumOS: maximumOS)
    }
    /// The only signing in this proof: the test target answers the library's callback.
    static func signer(_ message: Data) throws -> Data { try key().signature(for: message) }
    static func policy(installed: String = installed) -> CandidatePolicy {
        CandidatePolicy(bundleID: bundleID, teamID: teamID, osVersion: "27.0.1", installedVersion: installed)
    }
}

// MARK: Disposable physical fixtures beneath the .build that holds this executable.

/// The `.build` directory, found from this executable independently of the operator library.
func buildDirectory() throws -> URL {
    guard var build = Bundle.main.executableURL?.resolvingSymlinksInPath() else { throw CheckFailure(description: "Executable path unknown") }
    while build.lastPathComponent != ".build" {
        guard build.pathComponents.count > 1 else { throw CheckFailure(description: "This executable is not beneath a .build directory") }
        build.deleteLastPathComponent()
    }
    guard let physical = realpath(build.path, nil) else { throw CheckFailure(description: "No physical build directory") }
    defer { free(physical) }
    return URL(fileURLWithPath: String(cString: physical))
}

struct Layout {
    let build: URL, root: URL, scratch: URL
    var namespace: URL { root.appendingPathComponent("namespace.json") }
    var checkpoint: URL { root.appendingPathComponent("checkpoint.json") }
    var lock: URL { root.appendingPathComponent("lock") }
    var input: URL { root.appendingPathComponent("input") }
    var artifact: URL { input.appendingPathComponent(Sample.artifactName) }
    var publications: URL { root.appendingPathComponent("publications") }
    var consumerState: URL { scratch.appendingPathComponent("consumer-state") }
    func publication(_ sequence: UInt64) -> URL { publications.appendingPathComponent("sequence-\(sequence)") }
    func pending(_ sequence: UInt64) -> URL { publications.appendingPathComponent("pending-sequence-\(sequence)") }
    func catalogue(_ sequence: UInt64) -> URL { publication(sequence).appendingPathComponent("catalogue.json") }
}
let publicationFiles: Set<String> = ["catalogue.json", "evidence.json", "inspection-record.json", "publication.json"]

/// Names one not-yet-created operator root and creates a separate scratch directory. Both are
/// removed afterwards; nothing else is touched.
func withLayout(_ body: (Layout) throws -> Void) throws {
    let build = try buildDirectory(), id = UUID().uuidString
    let layout = Layout(build: build, root: build.appendingPathComponent("patched-operator-fixture-\(id)"),
                        scratch: build.appendingPathComponent("patched-operator-scratch-\(id)"))
    try makeDirectory(layout.scratch)
    defer { try? FileManager.default.removeItem(at: layout.scratch); try? FileManager.default.removeItem(at: layout.root) }
    try body(layout)
}
/// A fresh root created by the explicit authority, with the fixture artifact physically written into it.
func withRoot(_ body: (FixtureOperatorAuthority, Layout) throws -> Void) throws {
    try withLayout { layout in
        let authority = try FixtureOperatorAuthority.createFreshRoot(path: layout.root.path, trust: Sample.trust())
        try writeFile(Sample.artifact, layout.artifact)
        try body(authority, layout)
    }
}
func fixtureReceipt(_ authority: FixtureOperatorAuthority, _ layout: Layout) throws -> VerifiedArtifactReceipt {
    try authority.fixtureReceipt(version: Sample.version, artifactPath: layout.artifact.path)
}
func signed(_ authority: FixtureOperatorAuthority, _ layout: Layout, sequence: UInt64 = 7) throws -> SignedCatalogue {
    try authority.sign(receipt: fixtureReceipt(authority, layout), request: Sample.request(sequence: sequence), now: Sample.now,
                       signer: Sample.signer)
}
func checkpointFields(_ layout: Layout) throws -> (sequence: UInt64, payloadSHA256: String) {
    let fields = try object(bytes(layout.checkpoint))
    try expect(Set(fields.keys) == ["schemaVersion", "keyID", "catalogueID", "sequence", "payloadSHA256"], "Checkpoint fields differ: \(fields.keys.sorted())")
    guard unsigned(fields["schemaVersion"]) == 1, fields["keyID"] as? String == Sample.keyID,
          fields["catalogueID"] as? String == Sample.catalogueID, let sequence = unsigned(fields["sequence"]),
          let digest = fields["payloadSHA256"] as? String else { throw CheckFailure(description: "Checkpoint is not the documented record") }
    try expectPrivateFile(layout.checkpoint, "Checkpoint")
    return (sequence, digest)
}

// MARK: Independent verification of signed bytes. CryptoKit and JSONSerialization only.

struct Decoded { let payload: Data; let fields: [String: Any]; let artifact: [String: Any] }
/// Checks the documented envelope, frame, signature and exact payload schema of `envelope`
/// without calling the operator library or the consumer.
func verifyIndependently(_ envelope: Data, request: CatalogueRequest, artifact: Data = Sample.artifact,
                         version: String = Sample.version) throws -> Decoded {
    try expect(envelope.count <= 131_072 && String(data: envelope, encoding: .utf8) != nil && !envelope.starts(with: [0xef, 0xbb, 0xbf]),
               "Envelope is not bounded UTF-8 without a BOM")
    let outer = try object(envelope)
    try expect(Set(outer.keys) == ["keyID", "payload", "signature"], "Envelope fields differ: \(outer.keys.sorted())")
    guard outer["keyID"] as? String == request.keyID, let encodedPayload = outer["payload"] as? String,
          let encodedSignature = outer["signature"] as? String, let payload = Data(base64Encoded: encodedPayload),
          let signature = Data(base64Encoded: encodedSignature) else { throw CheckFailure(description: "Envelope is not the documented record") }
    try expect(payload.base64EncodedString() == encodedPayload && signature.base64EncodedString() == encodedSignature && signature.count == 64,
               "Envelope base64 is not canonical or the signature is not 64 bytes")
    try expect(payload.count <= 65_536, "Payload exceeds 64 KiB")
    try expect(try Sample.key().publicKey.isValidSignature(signature, for: Data((Sample.domain + "\0").utf8) + payload),
               "Signature does not verify over the documented frame with the test public key")
    try expect(!(try Sample.key(true).publicKey.isValidSignature(signature, for: Data((Sample.domain + "\0").utf8) + payload)),
               "Signature verifies under an unrelated key")
    let fields = try object(payload)
    try expect(Set(fields.keys) == ["schemaVersion", "domain", "keyID", "catalogueID", "sequence", "issuedAt", "expiresAt", "artifact"],
               "Payload fields differ: \(fields.keys.sorted())")
    try expect(unsigned(fields["schemaVersion"]) == 1 && fields["domain"] as? String == Sample.domain &&
               fields["keyID"] as? String == request.keyID && fields["catalogueID"] as? String == request.catalogueID,
               "Payload identity differs from the request")
    try expect(unsigned(fields["sequence"]) == request.sequence && unsigned(fields["issuedAt"]) == request.issuedAt &&
               unsigned(fields["expiresAt"]) == request.expiresAt, "Payload sequence or times differ from the request")
    guard let signedArtifact = fields["artifact"] as? [String: Any] else { throw CheckFailure(description: "Payload has no artifact object") }
    try expect(Set(signedArtifact.keys) == ["bundleID", "teamID", "platform", "minimumOS", "maximumOS", "version", "sha256", "byteLength"],
               "Artifact fields differ: \(signedArtifact.keys.sorted())")
    try expect(signedArtifact["bundleID"] as? String == Sample.bundleID && signedArtifact["teamID"] as? String == Sample.teamID &&
               signedArtifact["platform"] as? String == "macOS" && signedArtifact["version"] as? String == version,
               "Signed artifact identity is not the pinned identity")
    try expect(signedArtifact["minimumOS"] as? String == request.minimumOS && signedArtifact["maximumOS"] as? String == request.maximumOS,
               "Signed OS range differs from the request")
    try expect(signedArtifact["sha256"] as? String == sha(artifact) && unsigned(signedArtifact["byteLength"]) == UInt64(artifact.count),
               "Signed digest or length is not that of the verified artifact bytes")
    return Decoded(payload: payload, fields: fields, artifact: signedArtifact)
}
func consumer(_ layout: Layout, installed: String = Sample.installed) throws -> CatalogueVerifier {
    CatalogueVerifier(trust: try Sample.trust(), policy: Sample.policy(installed: installed), stateDirectory: layout.consumerState.path)
}
func expectFixtureCandidate(_ candidate: CatalogueCandidate, sequence: UInt64, payload: Data) throws {
    try expect(candidate.sequence == sequence && candidate.catalogueID == Sample.catalogueID && candidate.payloadSHA256 == sha(payload),
               "Consumer accepted a different catalogue")
    try expect(candidate.origin == "fixture" && !candidate.freshOSValidation && !candidate.installationAuthorized,
               "Consumer result asserted OS validation or installation authority")
    try expect(candidate.artifact.sha256 == sha(Sample.artifact) && candidate.artifact.byteLength == Int64(Sample.artifact.count) &&
               candidate.artifact.version == Sample.version, "Consumer artifact differs from the verified bytes")
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
        throw CheckFailure(description: "Operator child exceeded eight-second fixture bound")
    }
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
}
let noTrustSuffix = "origin=fixture freshOSValidation=false installationAuthorized=false"

/// Changes made to the named artifact after a receipt exists, and the refusal each must cause.
let evidenceMutations: [(String, OperatorFailure, @Sendable (Layout) throws -> Void)] = [
    ("same-length bytes overwritten in place", .digestMismatch, { layout in
        let handle = try FileHandle(forWritingTo: layout.artifact); defer { try? handle.close() }
        try handle.write(contentsOf: Data("X".utf8))
    }),
    ("bytes appended in place", .lengthMismatch, { layout in
        let handle = try FileHandle(forWritingTo: layout.artifact); defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: Data("extra".utf8))
    }),
    ("truncated in place", .lengthMismatch, { layout in
        try expect(truncate(layout.artifact.path, 10) == 0, "Fixture truncate failed")
    }),
    ("replaced by a new file with identical bytes", .identityChanged, { layout in
        let other = layout.input.appendingPathComponent("replacement")
        try writeFile(Sample.artifact, other)
        try expect(rename(other.path, layout.artifact.path) == 0, "Fixture replace failed")
    }),
    ("deleted", .identityChanged, { layout in
        try expect(unlink(layout.artifact.path) == 0, "Fixture unlink failed")
    }),
    ("renamed to another name", .identityChanged, { layout in
        try expect(rename(layout.artifact.path, layout.input.appendingPathComponent("moved.dmg").path) == 0, "Fixture rename failed")
    }),
    ("its directory renamed and an identical copy put at the old name", .identityChanged, { layout in
        try expect(rename(layout.input.path, layout.root.appendingPathComponent("input-moved").path) == 0, "Fixture rename failed")
        try makeDirectory(layout.input)
        try writeFile(Sample.artifact, layout.artifact)
    }),
    ("given a second hard link", .hardlink, { layout in
        try expect(link(layout.artifact.path, layout.scratch.appendingPathComponent("second-name").path) == 0, "Fixture link failed")
    })]
