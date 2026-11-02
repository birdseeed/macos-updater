import Foundation
import Darwin
@_spi(Testing) import ArtifactInspection
@_spi(Testing) import PatchedClient

// PAT-2661 Phase A: synthetic subprocesses only, never Security or a vendor app.
// The child's echoed request is transport data, never a trusted SignatureObservation.
func runInstalledIdentityWorkerFixtureChild(_ args: [String]) -> Never {
    guard args.count == 4, args[0] == "--pat-2661-installed-identity-child",
          let requestBytes = Data(base64Encoded: args[3]),
          var request = (try? JSONSerialization.jsonObject(with: requestBytes)) as? [String: Any] else { exit(91) }
    let mode = args[1], marker = args[2]
    do { try Data(String(getpid()).utf8).write(to: URL(fileURLWithPath: marker), options: .withoutOverwriting) }
    catch { exit(92) }
    if mode == "pinned-stall" || mode == "diagnostic-stall" {
        if mode == "diagnostic-stall" {
            try? Data("entered refusal diagnostic".utf8).write(to: URL(fileURLWithPath: marker + ".diagnostic"))
        }
        sleep(10); exit(93)
    }
    if mode == "overflow" { FileHandle.standardOutput.write(Data(repeating: 65, count: 65_536)); exit(0) }
    if mode == "malformed" { FileHandle.standardOutput.write(Data("{incomplete".utf8)); exit(0) }
    if mode == "nonzero" { exit(7) }
    if mode == "wrong-path" { request["appPath"] = "/Applications/Unrelated.app" }
    if mode == "wrong-pin" { request["pin"] = ["version": "0"] }
    if mode == "wrong-flags" { request["validationFlags"] = 0 }
    if mode == "wrong-binding" { request["binding"] = ["appInode": 0] }
    if mode == "wrong-nonce" { request["nonce"] = "replayed-request" }
    var result: [String: Any] = ["kind": "pinned", "validationStatus": 0,
        "signingInformationStatus": 0, "teamID": "43AQ936H96", "identifier": "org.mozilla.firefox",
        "startedAt": "2026-10-29T08:45:00Z", "finishedAt": "2026-10-29T08:45:01Z"]
    if mode == "refused" { result["kind"] = "refused"; result["validationStatus"] = -67050 }
    if mode == "wrong-team" { result["teamID"] = "AAAAAAAAAA" }
    if mode == "wrong-identifier" { result["identifier"] = "org.unrelated.app" }
    if mode == "reverse-time" { result["finishedAt"] = "2026-10-29T08:44:59Z" }
    var envelope: [String: Any] = ["schemaVersion": 1, "request": request, "result": result]
    if mode == "unknown-field" { envelope["unexpected"] = true }
    guard let bytes = try? JSONSerialization.data(withJSONObject: envelope, options: .sortedKeys) else { exit(94) }
    if mode == "duplicate-field", let text = String(data: bytes, encoding: .utf8) {
        FileHandle.standardOutput.write(Data(("{\"schemaVersion\":1," + text.dropFirst()).utf8)); exit(0)
    }
    FileHandle.standardOutput.write(bytes); exit(0)
}

private final class WorkerProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    func called() { lock.lock(); calls += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
}
private struct WorkerFixture: Sendable {
    let base: URL, root: URL, app: URL, marker: URL
    init() throws {
        base = try newDirectory("pat2661-worker")
        root = base.appendingPathComponent("Applications")
        app = root.appendingPathComponent("Literal.app")
        marker = base.appendingPathComponent("Markers/child.pid")
        try FileManager.default.createDirectory(at: base.appendingPathComponent("Markers"), withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let fields = ["CFBundleName": "Literal browser", "CFBundleIdentifier": "org.mozilla.firefox",
            "CFBundleShortVersionString": "157.0", "CFBundleVersion": "1", "CFBundleExecutable": "firefox", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: fields, format: .xml, options: 0).write(to: plist)
        try Data("inert executable".utf8).write(to: executable)
    }
    var plist: URL { app.appendingPathComponent("Contents/Info.plist") }
    var executable: URL { app.appendingPathComponent("Contents/MacOS/firefox") }
    func clean() { try? FileManager.default.removeItem(at: base) }
    func scanner(mode: String, budget: InstalledIdentityScanBudget = .init(seconds: 2),
                 probe: WorkerProbe = WorkerProbe(), commandSeconds: Double = 0.5,
                 mutation: (@Sendable () throws -> Void)? = nil) -> LocalApplicationInventory {
        let ownExecutable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
        return LocalApplicationInventory(fixtureRoots: [root.path], identityCollector: { path, appFD, execFD, bytes, pin in
            probe.called()
            return try InstalledIdentityWorkerTestAdapter.collect(appPath: path, appDescriptor: appFD,
                executableDescriptor: execFD, infoPlist: bytes, pin: pin, budget: budget,
                childExecutable: ownExecutable,
                childArguments: ["--pat-2661-installed-identity-child", mode, path == app.path ? marker.path : marker.path + "." + URL(fileURLWithPath: path).lastPathComponent],
                commandSeconds: commandSeconds, outputBytes: 4096, boundaryObserver: mutation)
        })
    }
    func childPID() throws -> pid_t {
        guard let bytes = try? Data(contentsOf: marker), let text = String(data: bytes, encoding: .utf8), let pid = Int32(text), pid > 1 else {
            throw CheckFailure(description: "Worker never launched its actual bounded child")
        }
        return pid
    }
    func assertReaped() throws {
        let pid = try childPID()
        errno = 0
        try expect(kill(pid, 0) == -1 && errno == ESRCH, "Owned worker remains alive after collection returned")
        var status: Int32 = 0; errno = 0
        try expect(waitpid(pid, &status, WNOHANG) == -1 && errno == ECHILD, "Immediate worker was not reaped by the real runner")
    }
}
private func workerUnknown(_ value: LocalInventoryObservation) throws {
    try expect(value.applications.count == 1 && value.applications[0].installedIdentity == nil, "Worker refusal erased the physical row or manufactured identity")
    try expect(value.provenance == .fixture && !value.installationAllowed && value.authorityUnknown, "Fixture subprocess issued authority")
}
@MainActor func registerInstalledIdentityWorkerChecks() {
    check("PAT2661 worker: exact synthetic transport qualifies fixture identity only") {
        let f = try WorkerFixture(); defer { f.clean() }
        let value = await f.scanner(mode: "valid").scan()
        try f.assertReaped()
        guard let identity = value.applications.first?.installedIdentity else { throw CheckFailure(description: "Bounded worker positive behavior is missing") }
        try expect(identity.provenance == .fixture && identity.sessionID == value.sessionID && identity.generation == value.generation,
                   "Synthetic child escaped fixture/session/generation binding")
        try expect(identity.physicalIdentity == value.applications[0].physicalIdentity && !value.installationAllowed && value.authorityUnknown,
                   "Synthetic child escaped physical binding or issued authority")
    }
    for mode in ["pinned-stall", "diagnostic-stall"] {
        check("PAT2661 worker: \(mode) is killed and reaped; controller completes and retries") {
            let f = try WorkerFixture(); defer { f.clean() }; let probe = WorkerProbe()
            let c = LocalApplicationsController(inventory: f.scanner(mode: mode, probe: probe))
            let start = DispatchTime.now().uptimeNanoseconds
            c.scan(); await c.waitUntilIdle()
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
            try expect(elapsed < 2 && c.phase == .finished && c.text.scanEnabled, "Stalled worker held the scan/controller past its deadline")
            try f.assertReaped()
            if mode == "diagnostic-stall" { try expect(FileManager.default.fileExists(atPath: f.marker.path + ".diagnostic"), "Diagnostic stall route was not entered") }
            guard let first = c.observation else { throw CheckFailure(description: "No completed scan after worker timeout") }
            try workerUnknown(first)
            try FileManager.default.removeItem(at: f.marker)
            c.scan(); await c.waitUntilIdle()
            try expect(c.phase == .finished && c.observation?.generation == first.generation + 1 && probe.count == 2,
                       "Timed out collection prevented a later explicit scan")
            try workerUnknown(c.observation!); try f.assertReaped()
        }
    }
    for mode in ["malformed", "overflow", "nonzero", "unknown-field", "duplicate-field", "wrong-path", "wrong-pin", "wrong-flags", "wrong-binding", "wrong-nonce", "wrong-team", "wrong-identifier", "reverse-time", "refused"] {
        check("PAT2661 worker: \(mode) transport refuses after actual child execution") {
            let f = try WorkerFixture(); defer { f.clean() }
            let value = await f.scanner(mode: mode).scan()
            try f.assertReaped(); try workerUnknown(value)
        }
    }
    check("PAT2661 worker: physical executable drift after child completion refuses") {
        let f = try WorkerFixture(); defer { f.clean() }; let observed = WorkerProbe()
        let value = await f.scanner(mode: "valid", mutation: {
            observed.called()
            try Data("changed physical executable bytes".utf8).write(to: f.executable)
        }).scan()
        try f.assertReaped()
        try expect(observed.count == 1, "Physical binding completion boundary was never exercised")
        try workerUnknown(value)
    }
    check("PAT2661 worker: exact plist drift after child completion refuses") {
        let f = try WorkerFixture(); defer { f.clean() }; let observed = WorkerProbe()
        let value = await f.scanner(mode: "valid", mutation: {
            observed.called()
            try Data("changed plist bytes".utf8).write(to: f.plist)
        }).scan()
        try f.assertReaped()
        try expect(observed.count == 1, "Plist binding completion boundary was never exercised")
        try workerUnknown(value)
    }
    for (label, seconds) in [("zero", 0.0), ("negative", -1.0), ("infinity", Double.infinity), ("NaN", Double.nan)] {
        check("PAT2661 worker: invalid \(label) budget refuses before child admission") {
            let f = try WorkerFixture(); defer { f.clean() }
            let value = await f.scanner(mode: "valid", budget: .init(seconds: seconds)).scan()
            try workerUnknown(value)
            try expect(!FileManager.default.fileExists(atPath: f.marker.path), "Invalid budget admitted a child")
        }
    }
    check("PAT2661 worker: one shared budget bounds all rows of one scan") {
        let f = try WorkerFixture(); defer { f.clean() }; let probe = WorkerProbe()
        for name in ["Second.app", "Third.app"] {
            try FileManager.default.copyItem(at: f.app, to: f.root.appendingPathComponent(name))
        }
        let start = DispatchTime.now().uptimeNanoseconds
        let value = await f.scanner(mode: "pinned-stall", budget: .init(seconds: 0.3), probe: probe, commandSeconds: 1).scan()
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        try f.assertReaped()
        try expect(value.applications.count == 3 && value.applications.allSatisfy { $0.installedIdentity == nil },
                   "Shared deadline removed rows or invented identity")
        try expect(probe.count == 3 && elapsed < 2, "Per-row work did not share the same monotonic deadline")
        try expect(!FileManager.default.fileExists(atPath: f.marker.path + ".Second.app") &&
                   !FileManager.default.fileExists(atPath: f.marker.path + ".Third.app"), "Exhausted scan budget launched another row child")
    }
    check("PAT2661 worker: shared monotonic budget refuses further child admission") {
        let f = try WorkerFixture(); defer { f.clean() }
        let budget = InstalledIdentityScanBudget(seconds: 0.3)
        let scanner = f.scanner(mode: "pinned-stall", budget: budget, commandSeconds: 1)
        let start = DispatchTime.now().uptimeNanoseconds
        try workerUnknown(await scanner.scan()); try f.assertReaped()
        try FileManager.default.removeItem(at: f.marker)
        try workerUnknown(await scanner.scan())
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        try expect(elapsed < 2, "Per-child budget replaced the shared monotonic budget")
        try expect(!FileManager.default.fileExists(atPath: f.marker.path), "Exhausted shared budget admitted another child")
    }
}
