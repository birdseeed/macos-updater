import Foundation
import CryptoKit
import Darwin
@_spi(Testing) import PatchedCore

// TEST-ONLY signing material; this target generates only its own fixed proof
// fixture. It cannot sign a supplied catalogue, publish or install anything.
let fixtureKey = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 0x46, count: 32))
let trust = FixtureTrust(keyID: "fixture-only-ed25519-v1", catalogueID: "fixture.firefox", publicKey: fixtureKey.publicKey.rawRepresentation)
let policy = CandidatePolicy(bundleID: "org.mozilla.firefox", teamID: "43AQ936H96", osVersion: "27.0.1", installedVersion: "157.0")
let maximumExactSecond: Int64 = 9_007_199_254_740_991
func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
func payload(sequence: UInt64 = 7, issued: Int64 = 1_800_000_000, expires: Int64 = 1_800_003_600) throws -> Data {
    try json(["schemaVersion": 1, "domain": "im.patched.catalogue.v1", "keyID": trust.keyID,
              "catalogueID": trust.catalogueID, "sequence": sequence, "issuedAt": issued, "expiresAt": expires,
              "artifact": ["bundleID": "org.mozilla.firefox", "teamID": "43AQ936H96", "platform": "macOS",
                           "minimumOS": "13.0", "maximumOS": "27.9", "version": "157.0.1", "byteLength": 3,
                           "sha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"]])
}
func envelope(_ payload: Data) throws -> Data {
    try json(["keyID": trust.keyID, "payload": payload.base64EncodedString(),
              "signature": fixtureKey.signature(for: Data("im.patched.catalogue.v1\0".utf8) + payload).base64EncodedString()])
}
struct Failure: Error, CustomStringConvertible { let description: String }
func require(_ condition: Bool, _ detail: String) throws { if !condition { throw Failure(description: detail) } }
func refuse(_ reason: CoreFailure, action: () throws -> CatalogueCandidate) throws {
    do {
        let candidate = try action()
        throw Failure(description: "IMPROPER ACCEPTANCE: expected \(reason), accepted sequence \(candidate.sequence)")
    } catch let actual as CoreFailure {
        try require(actual == reason, "Expected \(reason), received \(actual)")
    }
}
func withNamespace(_ action: (CatalogueVerifier) throws -> Void) throws {
    guard let resolved = realpath(FileManager.default.currentDirectoryPath + "/.build", nil) else { throw Failure(description: "No build directory") }
    defer { free(resolved) }
    let root = URL(fileURLWithPath: String(cString: resolved)).appendingPathComponent("core-regression-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: root) }
    try action(CatalogueVerifier(trust: trust, policy: policy, stateDirectory: root.appendingPathComponent("state").path))
}

func withPhysicalNamespace(_ action: (String) throws -> Void) throws {
    guard let resolved = realpath(FileManager.default.currentDirectoryPath + "/.build", nil) else { throw Failure(description: "No build directory") }
    defer { free(resolved) }
    let root = URL(fileURLWithPath: String(cString: resolved)).appendingPathComponent("core-sync-regression-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: root) }
    try action(root.appendingPathComponent("state").path)
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.count == 2 && arguments[0] == "--emit-fixed-fixture" {
    let destination = URL(fileURLWithPath: arguments[1])
    guard arguments[1].hasPrefix("/"), !FileManager.default.fileExists(atPath: destination.path) else {
        print("Refused: fixed test fixture needs a new absolute directory"); exit(1)
    }
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let payloadBytes = try payload()
    let outputs: [String: Data] = ["catalogue.fixture.json": try envelope(payloadBytes), "public-key.fixture.raw": fixtureKey.publicKey.rawRepresentation,
                                  "lower-sequence.fixture.json": try envelope(payload(sequence: 6)), "artifact.fixture": Data("abc".utf8),
                                  "tampered-artifact.fixture": Data("abd".utf8), "exact-payload.fixture.json": payloadBytes]
    for (name, data) in outputs {
        let file = destination.appendingPathComponent(name)
        try data.write(to: file, options: [.withoutOverwriting]); chmod(file.path, 0o600)
    }
    print("Generated fixed TEST-ONLY fixture; no private key exported, production trust, OS trust or installed success.")
    exit(0)
}
if arguments.count == 2 && arguments[0] == "--prove-persistence-boundaries" {
    let root = URL(fileURLWithPath: arguments[1])
    guard arguments[1].hasPrefix("/"), !FileManager.default.fileExists(atPath: root.path) else {
        print("Refused: persistence fixture needs a new absolute directory"); exit(1)
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    var reports: [[String: Any]] = []
    let names = PersistenceStage.allCases.map { "stage-" + $0.rawValue } + PersistenceSyncOperation.allCases.map { "sync-" + $0.rawValue }
    for name in names {
        let parent = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let path = parent.appendingPathComponent("state").path
        _ = try CatalogueVerifier(trust: trust, policy: policy, stateDirectory: path)
            .bootstrapFreshProofNamespace(envelope: envelope(payload(sequence: 6)), now: 1_800_000_000)
        var events: [String] = []
        var injected = false
        let verifier = CatalogueVerifier(trust: trust, policy: policy, stateDirectory: path,
            persistenceProbe: { point in
                events.append("stage-" + point.rawValue)
                if name == "stage-" + point.rawValue { injected = true; throw CoreFailure.persistenceFailed }
            }, syncProbe: { point in
                events.append("sync-" + point.rawValue)
                if name == "sync-" + point.rawValue { injected = true; throw CoreFailure.persistenceFailed }
            })
        try refuse(.persistenceFailed) { try verifier.verify(envelope: envelope(payload()), now: 1_800_000_000) }
        try require(injected, "Named failure was not injected")
        let bytes = try Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("checkpoint.json"))
        guard let checkpoint = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let sequence = (checkpoint["sequence"] as? NSNumber)?.uint64Value else { throw Failure(description: "Torn physical checkpoint") }
        try require(sequence == 6 || sequence == 7, "Checkpoint is neither old nor new")
        let expectedHash = SHA256.hash(data: try payload(sequence: sequence)).map { String(format: "%02x", $0) }.joined()
        try require(checkpoint["payloadSHA256"] as? String == expectedHash, "Physical checkpoint payload hash mismatch")
        reports.append(["origin": "fixture", "injectedFailure": name, "candidateReturned": false,
                        "events": events, "checkpoint": checkpoint,
                        "retainedFiles": try FileManager.default.contentsOfDirectory(atPath: path),
                        "freshOSValidation": false, "installationAuthorized": false])
    }
    let result = try json(["origin": "fixture", "cases": reports, "hardwarePowerLossTested": false])
    try result.write(to: root.appendingPathComponent("proof-report.json"), options: [.withoutOverwriting])
    FileHandle.standardOutput.write(result); print("")
    exit(0)
}
if !arguments.isEmpty { print("Usage: patched-core-regression-checks [--emit-fixed-fixture|--prove-persistence-boundaries /new/fixture-directory]"); exit(2) }
var cases: [(String, () throws -> Void)] = [
    ("future 400-second proof cannot round to accepted at 2^62", {
        let clock: Int64 = 1 << 62
        try withNamespace { verifier in
            try refuse(.invalidClock) { try verifier.bootstrapFreshProofNamespace(envelope: envelope(payload(issued: clock + 400, expires: clock + 4000)), now: Double(clock)) }
        }
    }),
    ("caller clock above exact supported range refuses", {
        try withNamespace { verifier in
            try refuse(.invalidClock) { try verifier.bootstrapFreshProofNamespace(envelope: envelope(payload()), now: Double(maximumExactSecond + 1)) }
        }
    }),
    ("issued time above exact supported range refuses", {
        try withNamespace { verifier in
            try refuse(.invalidPayload) { try verifier.bootstrapFreshProofNamespace(envelope: envelope(payload(issued: maximumExactSecond + 1, expires: maximumExactSecond + 1000)), now: 1_800_000_000) }
        }
    }),
    ("expiry above exact supported range refuses", {
        try withNamespace { verifier in
            try refuse(.invalidPayload) { try verifier.bootstrapFreshProofNamespace(envelope: envelope(payload(issued: maximumExactSecond - 100, expires: maximumExactSecond + 1)), now: Double(maximumExactSecond - 100)) }
        }
    }),
    ("last exactly represented supported second boundary accepts", {
        try withNamespace { verifier in
            let result = try verifier.bootstrapFreshProofNamespace(envelope: envelope(payload(issued: maximumExactSecond - 100, expires: maximumExactSecond)), now: Double(maximumExactSecond - 1))
            try require(result.sequence == 7 && result.origin == "fixture" && !result.freshOSValidation && !result.installationAuthorized, "Wrong bounded fixture result")
        }
    }),
    ("future skew at last supported range remains strict", {
        try withNamespace { verifier in
            try refuse(.futureIssued) { try verifier.bootstrapFreshProofNamespace(envelope: envelope(payload(issued: maximumExactSecond - 100, expires: maximumExactSecond)), now: Double(maximumExactSecond - 401)) }
        }
    })
]
// CHECK-ADDED: unsupported/failed flushes must never return a candidate.
for operation in PersistenceSyncOperation.allCases {
    cases.append(("sync operation failure refuses before acceptance: \(operation.rawValue)", {
        try withPhysicalNamespace { path in
            var reached = false
            let verifier = CatalogueVerifier(trust: trust, policy: policy, stateDirectory: path,
                persistenceProbe: { _ in }, syncProbe: { point in
                    if point == operation { reached = true; throw CoreFailure.persistenceFailed }
                })
            try refuse(.persistenceFailed) { try verifier.bootstrapFreshProofNamespace(envelope: envelope(payload()), now: 1_800_000_000) }
            try require(reached, "Sync fault never reached its real operation boundary")
        }
    }))
}
cases.append(("accepted checkpoint follows both full drive flush requests", {
    try withPhysicalNamespace { path in
        var operations: [PersistenceSyncOperation] = []
        let verifier = CatalogueVerifier(trust: trust, policy: policy, stateDirectory: path,
            persistenceProbe: { _ in }, syncProbe: { operations.append($0) })
        _ = try verifier.bootstrapFreshProofNamespace(envelope: envelope(payload()), now: 1_800_000_000)
        try require(operations == PersistenceSyncOperation.allCases, "Accepted before file fsync/fullflush, directory fsync and committed fullflush")
    }
}))

// CHECK-ADDED: bootstrap must stay inside the ancestor chain it created the namespace under.
func withAncestorNamespace(_ action: (URL) throws -> Void) throws {
    guard let resolved = realpath(FileManager.default.currentDirectoryPath + "/.build", nil) else { throw Failure(description: "No build directory") }
    defer { free(resolved) }
    let root = URL(fileURLWithPath: String(cString: resolved)).appendingPathComponent("core-ancestor-regression-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root.appendingPathComponent("parent"), withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    try action(root)
}
func identity(_ path: String) throws -> (dev: dev_t, ino: ino_t, mode: mode_t) {
    var info = stat()
    guard lstat(path, &info) == 0 else { throw Failure(description: "Missing \(path)") }
    return (info.st_dev, info.st_ino, info.st_mode)
}
func makeOwnedDirectory(_ path: String) throws {
    guard mkdir(path, 0o700) == 0, chmod(path, 0o700) == 0 else { throw Failure(description: "Could not create \(path)") }
}
cases.append(("bootstrap boundary control: created namespace is the accepted namespace", {
    try withAncestorNamespace { root in
        let state = root.appendingPathComponent("parent/state").path
        var boundaries: [BootstrapBoundary] = []
        var created: (dev: dev_t, ino: ino_t, mode: mode_t)?
        let verifier = CatalogueVerifier(trust: trust, policy: policy, stateDirectory: state, bootstrapProbe: { point in
            boundaries.append(point); created = try identity(state)
        })
        let result = try verifier.bootstrapFreshProofNamespace(envelope: envelope(payload()), now: 1_800_000_000)
        try require(result.sequence == 7 && result.origin == "fixture" && !result.freshOSValidation && !result.installationAuthorized, "Wrong bounded fixture result")
        try require(boundaries == [.namespaceCreated], "Bootstrap boundary not reached exactly once after mkdir")
        let accepted = try identity(state)
        try require(created.map { $0.dev == accepted.dev && $0.ino == accepted.ino } == true, "Accepted namespace is not the created directory")
        try require(Set(try FileManager.default.contentsOfDirectory(atPath: state)) == ["lock", "namespace.json", "checkpoint.json"], "Control namespace missing durable files")
        try refuse(.replay) {
            try CatalogueVerifier(trust: trust, policy: policy, stateDirectory: state).verify(envelope: envelope(payload(sequence: 6)), now: 1_800_000_000)
        }
    }
}))
cases.append(("bootstrap refuses ancestor replaced between mkdir and namespace open", {
    try withAncestorNamespace { root in
        let parent = root.appendingPathComponent("parent").path
        let retained = root.appendingPathComponent("parent-retained").path
        let state = parent + "/state"
        var reached = false
        var created: (dev: dev_t, ino: ino_t, mode: mode_t)?
        let verifier = CatalogueVerifier(trust: trust, policy: policy, stateDirectory: state, bootstrapProbe: { _ in
            reached = true
            created = try identity(state)
            guard rename(parent, retained) == 0 else { throw Failure(description: "Could not retain original parent") }
            try makeOwnedDirectory(parent); try makeOwnedDirectory(state)
        })
        try refuse(.unsafePath) { try verifier.bootstrapFreshProofNamespace(envelope: envelope(payload()), now: 1_800_000_000) }
        try require(reached, "Bootstrap boundary never reached after real mkdir")
        let replacementEntries = try FileManager.default.contentsOfDirectory(atPath: state)
        try require(replacementEntries.isEmpty, "Replacement namespace received writes: \(replacementEntries.sorted())")
        let original = try identity(retained + "/state")
        try require(created.map { $0.dev == original.dev && $0.ino == original.ino } == true && original.mode & 0o7777 == 0o700,
                    "Original incomplete namespace not preserved under retained parent")
        let originalEntries = try FileManager.default.contentsOfDirectory(atPath: retained + "/state")
        try require(!originalEntries.contains("namespace.json") && !originalEntries.contains("checkpoint.json"),
                    "Original incomplete namespace received namespace/checkpoint writes: \(originalEntries.sorted())")
    }
}))
var failures = 0
for (name, action) in cases {
    do { try action(); print("PASS fixture regression: \(name)") }
    catch { failures += 1; print("FAIL fixture regression: \(name): \(error)") }
}
print("Fixture core regressions: \(cases.count) cases, \(failures) failures. No OS or installation trust.")
exit(failures == 0 ? 0 : 1)
