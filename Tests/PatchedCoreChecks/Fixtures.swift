import Foundation
import CryptoKit
import Darwin
@_spi(Testing) import PatchedCore

struct CheckFailure: Error, CustomStringConvertible { let description: String }
func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw CheckFailure(description: message) }
}
func refuses(_ reason: CoreFailure, _ action: () throws -> Void) throws {
    do { try action() } catch let error as CoreFailure {
        try expect(error == reason, "Expected \(reason.rawValue), received \(error.rawValue)")
        return
    }
    throw CheckFailure(description: "Expected refusal: \(reason.rawValue)")
}
func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
func object(_ data: Data) throws -> [String: Any] {
    guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw CheckFailure(description: "Fixture is not an object")
    }
    return result
}
func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

enum Fixture {
    static let now = 1_800_000_000.0
    static let domain = "im.patched.catalogue.v1"
    static let catalogueID = "fixture.firefox"
    static let keyID = "fixture-only-ed25519-v1"
    static let bytes = Data("abc".utf8)
    // Deterministic TEST-ONLY key material lives exclusively in this executable target.
    static func key(_ alternate: Bool = false) throws -> Curve25519.Signing.PrivateKey {
        try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: alternate ? 0x42 : 0x46, count: 32))
    }
    static func trust() throws -> FixtureTrust {
        .init(keyID: keyID, catalogueID: catalogueID, publicKey: try key().publicKey.rawRepresentation)
    }
    static func policy(os: String = "27.0.1", installed: String = "157.0", bundle: String = "org.mozilla.firefox",
                       team: String = "43AQ936H96", platform: String = "macOS") -> CandidatePolicy {
        .init(bundleID: bundle, teamID: team, platform: platform, osVersion: os, installedVersion: installed)
    }
    static func payload(sequence: UInt64 = 7) -> [String: Any] {
        ["schemaVersion": 1, "domain": domain, "keyID": keyID, "catalogueID": catalogueID,
         "sequence": sequence, "issuedAt": Int64(now), "expiresAt": Int64(now + 3600),
         "artifact": ["bundleID": "org.mozilla.firefox", "teamID": "43AQ936H96", "platform": "macOS",
                      "minimumOS": "13.0", "maximumOS": "27.9", "version": "157.0.1",
                      "sha256": sha(bytes), "byteLength": 3]]
    }
    static func signed(_ bytes: Data, alternateKey: Bool = false, frame: String = domain + "\0") throws -> Data {
        let signature = try key(alternateKey).signature(for: Data(frame.utf8) + bytes)
        return try json(["keyID": keyID, "payload": bytes.base64EncodedString(), "signature": signature.base64EncodedString()])
    }
    static func envelope(sequence: UInt64 = 7) throws -> Data { try signed(json(payload(sequence: sequence))) }
    static func verifier(_ root: URL, policy: CandidatePolicy = policy()) throws -> CatalogueVerifier {
        CatalogueVerifier(trust: try trust(), policy: policy, stateDirectory: root.appendingPathComponent("state").path)
    }
}

func withWorkspace(_ body: (URL) throws -> Void) throws {
    let base = FileManager.default.currentDirectoryPath + "/.build"
    guard let physical = realpath(base, nil) else { throw CheckFailure(description: "No physical build fixture root") }
    defer { free(physical) }
    let root = URL(fileURLWithPath: String(cString: physical)).appendingPathComponent("core-fixture-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root)
}
func writePrivate(_ data: Data, _ url: URL) throws {
    try data.write(to: url)
    guard chmod(url.path, 0o600) == 0 else { throw CheckFailure(description: "Fixture chmod failed") }
}
/// Independently constructs the documented physical state, not a mock of the production store.
func seedState(_ root: URL, sequence: UInt64 = 6, payload: Data? = nil) throws {
    let directory = root.appendingPathComponent("state")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    try writePrivate(json(["schemaVersion": 1, "namespace": "patched-fixture-state-v1",
                           "keyID": Fixture.keyID, "catalogueID": Fixture.catalogueID]), directory.appendingPathComponent("namespace.json"))
    let payloadBytes = try payload ?? json(Fixture.payload(sequence: sequence))
    try writePrivate(json(["schemaVersion": 1, "keyID": Fixture.keyID, "catalogueID": Fixture.catalogueID,
                           "sequence": sequence, "payloadSHA256": sha(payloadBytes)]), directory.appendingPathComponent("checkpoint.json"))
    try writePrivate(Data(), directory.appendingPathComponent("lock"))
}
func checkpoint(_ root: URL) throws -> [String: Any] {
    try object(Data(contentsOf: root.appendingPathComponent("state/checkpoint.json")))
}
func assertCheckpoint(_ root: URL, sequence: UInt64, payload: Data) throws {
    let value = try checkpoint(root)
    try expect((value["sequence"] as? NSNumber)?.uint64Value == sequence, "Physical highest sequence differs")
    try expect(value["payloadSHA256"] as? String == sha(payload), "Physical checkpoint must hash exact uncanonicalised payload")
    try expect(value["catalogueID"] as? String == Fixture.catalogueID && value["keyID"] as? String == Fixture.keyID,
               "Checkpoint lost trust identity")
    var info = stat()
    let path = root.appendingPathComponent("state/checkpoint.json").path
    try expect(lstat(path, &info) == 0 && info.st_mode & 0o777 == 0o600 && info.st_uid == geteuid(), "Unsafe checkpoint permissions/owner")
}
func verifyRefusal(_ data: Data, _ reason: CoreFailure, now: Double = Fixture.now,
                   policy: CandidatePolicy = Fixture.policy()) throws {
    try withWorkspace { root in
        try seedState(root)
        let before = try Data(contentsOf: root.appendingPathComponent("state/checkpoint.json"))
        try refuses(reason) { _ = try Fixture.verifier(root, policy: policy).verify(envelope: data, now: now) }
        let after = try Data(contentsOf: root.appendingPathComponent("state/checkpoint.json"))
        try expect(before == after, "Refused input changed durable highest sequence")
    }
}
func mutatePayload(_ edit: (inout [String: Any]) -> Void) throws -> Data {
    var value = Fixture.payload(); edit(&value); return try Fixture.signed(json(value))
}
func mutateArtifact(_ edit: (inout [String: Any]) -> Void) throws -> Data {
    try mutatePayload { value in
        var artifact = value["artifact"] as! [String: Any]; edit(&artifact); value["artifact"] = artifact
    }
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
        throw CheckFailure(description: "Core child exceeded eight-second fixture bound")
    }
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
}
