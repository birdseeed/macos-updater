import Foundation
import Darwin
import CryptoKit
@_spi(Testing) import PatchedDisposableProof

struct CheckFailure: Error, CustomStringConvertible { let description: String }
func expect(_ condition: Bool, _ message: String) throws { if !condition { throw CheckFailure(description: message) } }
func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) }
func refusal(_ wanted: DisposableFailure, _ operation: () throws -> Void) throws {
    do { try operation(); throw CheckFailure(description: "Expected \(wanted), operation accepted") }
    catch let actual as DisposableFailure { try expect(actual == wanted, "Expected \(wanted), observed \(actual)") }
}
func buildRoot() throws -> URL {
    guard var url = Bundle.main.executableURL?.resolvingSymlinksInPath() else { throw CheckFailure(description: "No executable path") }
    while url.lastPathComponent != ".build" {
        guard url.pathComponents.count > 1 else { throw CheckFailure(description: "Not beneath .build") }
        url.deleteLastPathComponent()
    }
    return url
}
func privateDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
}
func file(_ url: URL, _ bytes: Data) throws {
    let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard fd >= 0 else {
        throw CheckFailure(description: "Exclusive fixture file failed")
    }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    try handle.write(contentsOf: bytes); try handle.synchronize(); try handle.close()
}
func changeFirstByteInPlace(_ url: URL) throws {
    var before = stat(), after = stat()
    try expect(lstat(url.path, &before) == 0 && before.st_mode & S_IFMT == S_IFREG, "Mutation fixture is not a regular file")
    let fd = Darwin.open(url.path, O_WRONLY | O_NOFOLLOW | O_CLOEXEC)
    try expect(fd >= 0, "Cannot hold mutation fixture")
    defer { close(fd) }
    var changed: UInt8 = 88
    try expect(withUnsafePointer(to: &changed) { pwrite(fd, $0, 1, 0) } == 1 && fsync(fd) == 0, "In-place fixture mutation failed")
    try expect(lstat(url.path, &after) == 0 && before.st_dev == after.st_dev && before.st_ino == after.st_ino,
               "Mutation accidentally replaced the original file")
}
struct Fixture {
    let root: URL
    let expected: SyntheticGatewayExpectation
    init() throws {
        root = try buildRoot().appendingPathComponent("pat2602-gateway-" + UUID().uuidString)
        try privateDirectory(root)
        for name in ["Tool", "Incoming", "Applications", "Baseline"] { try privateDirectory(root.appendingPathComponent(name)) }
        let binary = Data("synthetic non-executable tool\n".utf8), artifact = Data("synthetic image bytes\n".utf8)
        let receipt = try json(["binarySHA256": hash(binary), "sourceRevision": String(repeating: "a", count: 40)])
        expected = .init(binarySHA256: hash(binary), receiptBytes: receipt, artifactSHA256: hash(artifact), artifactLength: Int64(artifact.count))
        try file(root.appendingPathComponent("Tool/patched-disposable-proof"), binary)
        try file(root.appendingPathComponent("Tool/builder-receipt.json"), receipt)
        try file(root.appendingPathComponent("Incoming/artifact.dmg"), artifact)
        for name in ["Applications/Firefox.app", "Baseline/Firefox-157.0.app"] {
            try privateDirectory(root.appendingPathComponent(name))
            try file(root.appendingPathComponent(name + "/payload"), Data("original target\n".utf8))
        }
    }
    func capture() throws -> SyntheticGatewayInspection { try .capture(rootPath: root.path, expected: expected) }
}

let run = "synthetic-gateway", rootName = "update", transaction = "00000000-0000-4000-8000-000000000001"
let target = "/Users/andy/PatchedProof/synthetic-gateway/Cases/update/Applications/Firefox.app"
let treeHash = String(repeating: "b", count: 64), oldHash = String(repeating: "c", count: 64)
let invoke = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
func actionRoot(_ action: DisposableAction) -> String {
    action == .recoverAfterStaging ? "staging" : (action == .recoverAfterSwap ? "swap" : "update")
}
func actionTarget(_ action: DisposableAction) -> String {
    "/Users/andy/PatchedProof/" + run + "/Cases/" + actionRoot(action) + "/Applications/Firefox.app"
}
let reportExpected = SyntheticGatewayExpectation(binarySHA256: String(repeating: "a", count: 64),
    receiptBytes: Data("{\"binarySHA256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"sourceRevision\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}".utf8),
    artifactSHA256: "40a0a649120635460256dae9ad63e40377f77326cbc9c449a5d0a1d7f5dd7982", artifactLength: 161550118)
func readback(targetPath: String = target, version: String = "157.0.1", tx: String = transaction,
              tree: String = treeHash, old: String = oldHash, fresh: Bool = true) -> SyntheticGatewayReadback {
    .init(targetPath: targetPath, version: version, transactionID: tx, manifestSHA256: tree, retainedOldSHA256: old, fresh: fresh)
}
func report(action: DisposableAction = .update) -> [String: Any] {
    let isUpdate = action == .update
    let command: [String: Any] = ["executable": "/usr/bin/codesign", "arguments": ["-dv", "--verbose=4", "/synthetic/tool"],
        "exitCode": 1, "stdout": "", "stderr": "synthetic unsigned tool", "timedOut": false, "outputExceeded": false,
        "startedAt": "2026-10-11T00:00:00Z", "finishedAt": "2026-10-11T00:00:00Z"]
    // Literal full native report schema. Empty observation arrays are explicitly
    // synthetic projection fixtures, not accepted live native trust evidence.
    let manifests: [String: Any] = isUpdate ? ["after": ["entries": [], "totalBytes": 0, "digest": treeHash],
        "before": ["entries": [], "totalBytes": 0, "digest": oldHash],
        "retainedOld": ["entries": [], "totalBytes": 0, "digest": oldHash], "baseline": ["entries": [], "totalBytes": 0, "digest": oldHash]] :
        ["baseline": ["entries": [], "totalBytes": 0, "digest": oldHash]]
    return ["action": action.rawValue, "runID": run, "caseRoot": actionRoot(action),
        "state": isUpdate ? "committed" : "rolledBack",
        "recoveryAction": isUpdate ? "none" : (action == .recoverAfterStaging ? "oldAlreadyInPlace" : "restoredOldBySwap"),
        "testCatalogueTrust": true, "productionTrust": false, "installedFirefoxProof": isUpdate, "freshOSValidation": true,
        "binarySHA256": reportExpected.binarySHA256, "sourceRevisionObservedByHarness": false,
        "builderProvenanceReceiptSHA256": hash(reportExpected.receiptBytes), "builderProvenanceReceipt": reportExpected.receiptBytes.base64EncodedString(),
        "manifestCoverage": ["type", "mode", "size", "link", "sha256digest"], "limitations": ["Synthetic projection only"],
        "guest": ["platformUUIDSHA256": DisposableScope.guestUUIDSHA256, "user": "andy", "home": "/Users/andy",
            "hostname": DisposableScope.guestHostname, "osVersion": DisposableScope.guestOS, "osBuild": DisposableScope.guestBuild,
            "architecture": "arm64", "uid": 501, "effectiveUID": 501, "consoleUID": 501, "hypervisor": 1],
        "nativeCommands": [], "appObservations": [],
        "bundleManifests": manifests,
        "imageObservations": [], "journalStatesReached": isUpdate ? ["prepared", "staging", "staged", "swapIntended", "swapped", "committed"] : ["rolledBack"],
        "independentMtreeFiles": [:], "spaceObservations": [], "targetPath": actionTarget(action),
        "exchangePath": "/Users/andy/PatchedProof/" + run + "/Cases/" + actionRoot(action) + "/Transaction/Exchange/Firefox.app",
        "harnessSigningObservation": command, "targetID": DisposableScope.targetID, "trigger": "explicitUserAction",
        "transactionID": transaction, "containerObservations": [], "catalogueObservations": [],
        "ownedMountsAbsent": true, "globalProductReadiness": false]
}
func compare(_ object: [String: Any], physical: SyntheticGatewayReadback = readback(), exit: Int32 = 0,
             observed: UUID = invoke, isNew: Bool = true, action: DisposableAction = .update,
             stdoutOverride: Data? = nil, durableOverride: Data? = nil) throws {
    let bytes = try json(object)
    try SyntheticGatewayCompletion.compare(stdout: stdoutOverride ?? (bytes + Data([10])), durableReport: durableOverride ?? bytes,
        childExit: exit, expectedInvocationID: invoke, observedInvocationID: observed, durableFileIsNew: isNew,
        action: action, runID: run, caseRoot: actionRoot(action), expected: reportExpected, readback: physical)
}

var checks: [(String, () throws -> Void)] = []
@MainActor func check(_ name: String, _ body: @escaping () throws -> Void) { checks.append((name, body)) }
check("host live issuer refuses guestMismatch before malformed proof-path arguments") {
    try refusal(.guestMismatch) { _ = try NativeInstalledActionScope.open(runID: "../../must-not-open", caseRoot: "/Applications") }
}
check("host live issuer also refuses an otherwise allowlisted update root") {
    try refusal(.guestMismatch) { _ = try NativeInstalledActionScope.open(runID: "future-native-run", caseRoot: "update") }
}
check("synthetic physical snapshot holds exact binary, receipt, artifact and target manifest") {
    let f = try Fixture(), inspected = try f.capture()
    try expect(inspected.binarySHA256 == f.expected.binarySHA256 && inspected.receiptSHA256 == hash(f.expected.receiptBytes) &&
               inspected.artifactSHA256 == f.expected.artifactSHA256 && inspected.targetManifest.entries.contains { $0.path == "payload" }, "Wrong captured physical binding")
    try inspected.revalidate()
}
for relative in ["Tool/patched-disposable-proof", "Tool/builder-receipt.json", "Incoming/artifact.dmg", "Applications/Firefox.app", "Baseline/Firefox-157.0.app"] {
    check("retained identity rejects same-byte replacement: " + relative) {
        let f = try Fixture(), held = try f.capture(), path = f.root.appendingPathComponent(relative)
        let saved = path.appendingPathExtension("retained-original")
        try FileManager.default.moveItem(at: path, to: saved)
        if relative.hasSuffix(".app") {
            try privateDirectory(path); try file(path.appendingPathComponent("payload"), Data("original target\n".utf8))
        } else { try file(path, Data(contentsOf: saved)) }
        try refusal(.identityChanged) { try held.revalidate() }
    }
}
check("retained artifact rejects in-place byte change on the same inode") {
    let f = try Fixture(), held = try f.capture()
    try changeFirstByteInPlace(f.root.appendingPathComponent("Incoming/artifact.dmg"))
    try refusal(.identityChanged) { try held.revalidate() }
}
for relative in ["Applications/Firefox.app/payload", "Baseline/Firefox-157.0.app/payload"] {
    check("retained tree rejects payload change with stable bundle root inode: " + relative) {
        let f = try Fixture(), held = try f.capture()
        let bundle = f.root.appendingPathComponent(relative).deletingLastPathComponent()
        var before = stat(), after = stat()
        try expect(lstat(bundle.path, &before) == 0, "No original bundle root")
        try changeFirstByteInPlace(f.root.appendingPathComponent(relative))
        try expect(lstat(bundle.path, &after) == 0 && before.st_ino == after.st_ino && before.st_dev == after.st_dev,
                   "Payload mutation replaced the bundle root")
        try refusal(.manifestMismatch) { try held.revalidate() }
    }
}
for ancestor in ["Tool", "Incoming"] {
    check("retained ancestry rejects same-content replacement: " + ancestor) {
        let f = try Fixture(), held = try f.capture(), path = f.root.appendingPathComponent(ancestor)
        let retained = path.appendingPathExtension("retained-original")
        try FileManager.default.moveItem(at: path, to: retained); try privateDirectory(path)
        let names = ancestor == "Tool" ? ["patched-disposable-proof", "builder-receipt.json"] : ["artifact.dmg"]
        for name in names { try file(path.appendingPathComponent(name), Data(contentsOf: retained.appendingPathComponent(name))) }
        try refusal(.identityChanged) { try held.revalidate() }
    }
}
check("synthetic root with non-private permissions refuses capture") {
    let f = try Fixture()
    try expect(chmod(f.root.path, 0o755) == 0, "Could not weaken synthetic root for test")
    try refusal(.unsafeMode) { _ = try f.capture() }
}
check("changed receipt bytes reject capture before any productive scope") {
    let f = try Fixture(); try Data("changed receipt".utf8).write(to: f.root.appendingPathComponent("Tool/builder-receipt.json"))
    try refusal(.notAuthorized) { _ = try f.capture() }
}
check("changed artifact bytes reject capture by digest") {
    let f = try Fixture(); var bytes = try Data(contentsOf: f.root.appendingPathComponent("Incoming/artifact.dmg")); bytes[0] ^= 1
    try bytes.write(to: f.root.appendingPathComponent("Incoming/artifact.dmg"))
    try refusal(.digestMismatch) { _ = try f.capture() }
}
check("symlink artifact refuses without following it") {
    let f = try Fixture(), path = f.root.appendingPathComponent("Incoming/artifact.dmg")
    try FileManager.default.moveItem(at: path, to: path.appendingPathExtension("retained-original"))
    try FileManager.default.createSymbolicLink(atPath: path.path, withDestinationPath: path.appendingPathExtension("retained-original").path)
    try refusal(.symlink) { _ = try f.capture() }
}
check("hardlinked executable refuses") {
    let f = try Fixture(), path = f.root.appendingPathComponent("Tool/patched-disposable-proof")
    try FileManager.default.linkItem(at: path, to: path.appendingPathExtension("retained-link"))
    try refusal(.hardlink) { _ = try f.capture() }
}
check("synthetic facade refuses host path outside nearest build root") {
    try refusal(.notAuthorized) { _ = try SyntheticGatewayInspection.capture(rootPath: "/Applications", expected: reportExpected) }
}
check("full native report projection compares fresh invocation, exact durable bytes and physical readback") {
    try compare(report())
}
for action in [DisposableAction.recoverAfterStaging, .recoverAfterSwap, .restoreOld] {
    check("native recovery projection verifies old physical readback: " + action.rawValue) {
        try compare(report(action: action), physical: readback(targetPath: actionTarget(action), version: "157.0", tree: oldHash), action: action)
    }
}
for (name, mutate) in [
    ("unknown top-level field", { (o: inout [String: Any]) in o["inventedSuccess"] = true }),
    ("saved verdict claims source attestation", { (o: inout [String: Any]) in o["sourceRevisionObservedByHarness"] = true }),
    ("wrong binary", { (o: inout [String: Any]) in o["binarySHA256"] = String(repeating: "d", count: 64) }),
    ("wrong receipt", { (o: inout [String: Any]) in o["builderProvenanceReceipt"] = Data("forged".utf8).base64EncodedString() }),
    ("wrong target", { (o: inout [String: Any]) in o["targetPath"] = "/Applications/Firefox.app" }),
    ("wrong guest UID", { (o: inout [String: Any]) in var g = o["guest"] as! [String: Any]; g["uid"] = 0; o["guest"] = g }),
    ("incomplete state", { (o: inout [String: Any]) in o["state"] = "swapped" }),
    ("owned mount remains", { (o: inout [String: Any]) in o["ownedMountsAbsent"] = false })] {
    check("closed report refuses " + name) {
        var o = report(); mutate(&o); try refusal(.notAuthorized) { try compare(o) }
    }
}
check("failed child exit refuses despite successful report") { try refusal(.notAuthorized) { try compare(report(), exit: 1) } }
check("old invocation refuses") { try refusal(.notAuthorized) { try compare(report(), observed: UUID()) } }
check("previously existing durable report refuses") { try refusal(.notAuthorized) { try compare(report(), isNew: false) } }
check("raw durable bytes must match stdout, not just decoded values") {
    let bytes = try JSONSerialization.data(withJSONObject: report(), options: [.prettyPrinted, .sortedKeys])
    try refusal(.notAuthorized) { try compare(report(), durableOverride: bytes) }
}
check("duplicate JSON keys refuse even if the last value agrees") {
    let bytes = try json(report()); let duplicate = Data("{\"runID\":\"wrong\",".utf8) + bytes.dropFirst()
    try refusal(.notAuthorized) { try compare(report(), stdoutOverride: duplicate + Data([10]), durableOverride: duplicate) }
}
for (name, physical) in [("target", readback(targetPath: "/Applications/Firefox.app")), ("version", readback(version: "157.0")),
    ("transaction", readback(tx: "00000000-0000-4000-8000-000000000099")), ("manifest", readback(tree: oldHash)),
    ("retained old", readback(old: treeHash)), ("stale evidence", readback(fresh: false))] {
    check("independent physical readback refuses changed " + name) {
        try refusal(.notAuthorized) { try compare(report(), physical: physical) }
    }
}

registerArchitectureReportCompatibilityChecks()
// CHECK-ADDED PAT-2710: default suite retains every prior check; exact focused
// selection executes only new synthetic projection checks, never a native scope.
registerInstalledSignatureProjectionChecks()
registerTargetProfileProjectionChecks()
if Array(CommandLine.arguments.dropFirst()) == ["--pat-2710-profile-projection"] {
    checks = checks.filter { $0.0.hasPrefix("PAT-2710 profile projection: ") }
    if checks.isEmpty { print("FAIL PAT-2710 profile projection selection empty"); exit(1) }
}
if Array(CommandLine.arguments.dropFirst()) == ["--pat-2710-target-profile-host-refusal"] {
    // Separate physical-host-only negative-runtime experiment. These checks
    // are deliberately absent from the normal VM/CI gate and pure focus.
    registerTargetProfileHostRefusalChecks()
    checks = checks.filter { $0.0.hasPrefix("PAT-2710 profile host refusal: ") }
    if checks.isEmpty { print("FAIL PAT-2710 profile host refusal selection empty"); exit(1) }
}
if Array(CommandLine.arguments.dropFirst()) == ["--pat-2710-installed-signature"] {
    checks = checks.filter { $0.0.hasPrefix("PAT-2710 installed signature: ") }
    if checks.isEmpty { print("FAIL PAT-2710 focused selection registered no synthetic checks"); exit(1) }
}

var failures = 0
for (name, body) in checks {
    do { try body(); print("PASS disposable-gateway: \(name)") }
    catch { failures += 1; print("FAIL disposable-gateway: \(name): \(error)") }
}
print("Disposable gateway acceptance: \(checks.count) cases, \(failures) failures. Synthetic .build files and SPI comparisons only; no native scope, process execution, guest action or install authority.")
exit(failures == 0 ? 0 : 1)
