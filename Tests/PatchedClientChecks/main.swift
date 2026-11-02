import Foundation
import Darwin
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import ArtifactInspection
@_spi(Testing) import PatchedClient

// Acceptance checks for PAT-2600, the first read-only client flow. Written before the
// implementation: these checks define the smallest PatchedClient interface they need.
//
//   ClientController (MainActor, ObservableObject)
//     init()                                   production: the real ArtifactInspector.inspectLocal
//     @_spi(Testing) init(inspector:)          test-only construction; PatchedApp never imports the SPI
//     text: ClientViewText, phase: ClientPhase, versions: [String] (from FirefoxTargets.pins)
//     select(fileURL:), selectVersion(_:), check(), cancel()
//     @_spi(Testing) waitUntilIdle() async     returns once no inspector call is outstanding, stale ones included
//   ClientInspector = @Sendable (version, path) async throws -> ClientInspectionSummary
//   ClientInspectionSummary: Sendable value with provenance (.inspector / .testDouble), the inspector's own
//     origin and freshOSValidation, byte/app/container/cleanup results and a refusal string. Its
//     initialiser is SPI-only. It has no way to grant installation: a summary that claims it is refused.
//   ClientView(controller:) is the one shared SwiftUI view that PatchedApp composes.
//
// No app is launched, nothing is mounted or downloaded, no installed app or profile is read and
// no network is used. The one real-inspector case stages a tiny wrong-size file and is refused by
// the existing byte checks before any mount. Its disposable directory and the painted pictures
// are the only writes, and both are new directories beneath this worktree's .build.
struct CheckFailure: Error, CustomStringConvertible { let description: String }
func expect(_ condition: Bool, _ message: String) throws {
    if !condition { throw CheckFailure(description: message) }
}

var cases: [(String, @MainActor () async throws -> Void)] = []
@MainActor func check(_ name: String, _ action: @escaping @MainActor () async throws -> Void) { cases.append((name, action)) }

// PAT-2666 additive actual-consumer composition gate, separate from the frozen wire62.
if Array(CommandLine.arguments.dropFirst()) == ["--pat-2666-native-proxy-composition"] {
    registerNativeNetworkProbeCompositionChecks()
    registerNativeNetworkProbeSupplementalReentrancyChecks()
    guard cases.count == 61 else {
        print("FAIL native proxy composition: expected 61 checks, got \(cases.count)"); exit(1)
    }
    var compositionFailures = 0
    for (name, action) in cases {
        do { try await action(); print("PASS client: \(name)") }
        catch { compositionFailures += 1; print("FAIL client: \(name): \(error)") }
    }
    print("Native proxy composition: \(cases.count) controlled consumer checks, \(compositionFailures) failures; no installed acceptance.")
    exit(compositionFailures == 0 ? 0 : 1)
}

// PAT-2666 exact focused local-peer gate. Older focus registrations and counts stay exact.
if Array(CommandLine.arguments.dropFirst()) == ["--pat-2666-manual-proxy-probe"] {
    registerManualProxyProbeChecks()
    guard cases.count == 19 else {
        print("FAIL manual proxy probe: expected 19 checks, got \(cases.count)"); exit(1)
    }
    registerManualProxyFramingChecks()
    guard cases.count == 53 else {
        print("FAIL manual proxy framing: expected 53 checks (19 original + 34 framing), got \(cases.count)"); exit(1)
    }
    registerManualProxyFramingBoundChecks()
    guard cases.count == 56 else {
        print("FAIL manual proxy framing bounds: expected 56 checks (53 preserved + 3 bounds), got \(cases.count)"); exit(1)
    }
    registerManualProxyFramingFinalChecks()
    guard cases.count == 60 else {
        print("FAIL manual proxy final framing: expected 60 checks (56 preserved + 4 final), got \(cases.count)"); exit(1)
    }
    registerLoopbackShutdownControlChecks()
    guard cases.count == 61 else {
        print("FAIL loopback shutdown control: expected 61 checks (60 preserved + 1 control), got \(cases.count)"); exit(1)
    }
    registerArtifactLoopbackShutdownRaceChecks()
    guard cases.count == 62 else {
        print("FAIL artifact shutdown race: expected 62 checks (61 preserved + 1 race), got \(cases.count)"); exit(1)
    }
    var focusedFailures = 0
    for (name, action) in cases {
        do { try await action(); print("PASS client: \(name)") }
        catch { focusedFailures += 1; print("FAIL client: \(name): \(error)") }
    }
    print("Manual proxy probe: \(cases.count) controlled loopback checks, \(focusedFailures) failures; no external transport or installed acceptance.")
    exit(focusedFailures == 0 ? 0 : 1)
}

// PAT-2661 additive bounded-worker route. Synthetic child dispatch precedes registration.
if CommandLine.arguments.dropFirst().first == "--pat-2661-installed-identity-child" {
    runInstalledIdentityWorkerFixtureChild(Array(CommandLine.arguments.dropFirst()))
}
if Array(CommandLine.arguments.dropFirst()) == ["--pat-2661-installed-identity-worker"] {
    registerInstalledIdentityWorkerChecks()
    guard cases.count == 25 else { print("FAIL installed identity worker: expected 25 checks, got \(cases.count)"); exit(1) }
    var failures = 0
    for (name, action) in cases {
        do { try await action(); print("PASS client: \(name)") }
        catch { failures += 1; print("FAIL client: \(name): \(error)") }
    }
    print("Installed identity worker: \(cases.count) synthetic-child checks, \(failures) failures; no native Security or installation authority.")
    exit(failures == 0 ? 0 : 1)
}

// PAT-2661 focused fixture-only projection gate, before all legacy registrations.
// CHECK-MODIFIED PAT-2661: additive identity integration gate; old gates unchanged.
if CommandLine.arguments.contains("--pat-2661-installed-identity") {
    registerInstalledIdentityIntegrationChecks()
    guard cases.count == 20 else {
        print("FAIL installed identity: expected 20 checks, got \(cases.count)"); exit(1)
    }
    var failures = 0
    for (name, action) in cases {
        do { try await action(); print("PASS client: \(name)") }
        catch { failures += 1; print("FAIL client: \(name): \(error)") }
    }
    print("Installed identity integration: \(cases.count) fixture-only checks, \(failures) failures; no native Security or update authority.")
    exit(failures == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--pat-2661-native-projection") {
    registerNativeUpdatesProjectionChecks()
    guard !cases.isEmpty else {
        print("FAIL native updates projection: no checks registered")
        exit(1)
    }
    var focusedFailures = 0
    for (name, action) in cases {
        do { try await action(); print("PASS client: \(name)") }
        catch { focusedFailures += 1; print("FAIL client: \(name): \(error)") }
    }
    print("Native updates projection acceptance: \(cases.count) cases, \(focusedFailures) failures. Fixture folders only; no update authority.")
    exit(focusedFailures == 0 ? 0 : 1)
}

// MARK: Test doubles. Confined to this executable; every summary they return is labelled .testDouble.

struct Call: Sendable { let version: String; let path: String; let onMainThread: Bool }
actor Recorder {
    private var calls: [Call] = []
    func record(_ call: Call) { calls.append(call) }
    var all: [Call] { calls }
    var count: Int { calls.count }
}
actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() { isOpen = true; let pending = waiters; waiters = []; pending.forEach { $0.resume() } }
}
struct Boom: Error, CustomStringConvertible { var description: String { "SECRET-INTERNAL-DETAIL /Users/nobody/private" } }

func summary(version: String = "157.0", provenance: ClientResultProvenance = .testDouble, bytes: Bool = true, app: Bool? = true,
             container: (Bool, Bool, Bool) = (false, false, false), origin: EvidenceOrigin? = .live, fresh: Bool = true,
             cleanup: Bool = true, refusal: String? = nil, installation: Bool = false) -> ClientInspectionSummary {
    ClientInspectionSummary(version: version, provenance: provenance, byteIntegrityVerified: bytes, appChecksPassed: app,
                            containerSignaturePassed: container.0, containerGatekeeperPassed: container.1,
                            containerTicketPassed: container.2, origin: origin, freshOSValidation: fresh,
                            cleanupVerified: cleanup, refusal: refusal, installationAuthorized: installation)
}
func scripted(_ recorder: Recorder, gate: Gate? = nil,
              _ make: @escaping @Sendable (Int) throws -> ClientInspectionSummary = { _ in summary() }) -> ClientInspector {
    { version, path in
        await recorder.record(Call(version: version, path: path, onMainThread: pthread_main_np() != 0))
        if let gate { await gate.wait() }
        return try make(await recorder.count)
    }
}
@MainActor func until(_ what: String, _ condition: () async -> Bool) async throws {
    for _ in 0..<1000 { if await condition() { return }; try await Task.sleep(nanoseconds: 5_000_000) }
    throw CheckFailure(description: "Timed out waiting for \(what)")
}
let firefoxA = URL(fileURLWithPath: "/Users/someone/Downloads/Firefox 157.0.dmg")
let firefoxB = URL(fileURLWithPath: "/Users/someone/Desktop/Other Name.dmg")
@MainActor func ready(_ inspector: @escaping ClientInspector, version: String = "157.0") -> ClientController {
    let controller = ClientController(inspector: inspector)
    controller.select(fileURL: firefoxA); controller.selectVersion(version)
    return controller
}
@MainActor func everyVisible(_ controller: ClientController) -> String {
    (controller.text.allLines + [String(reflecting: controller.text), String(describing: controller.phase)]).joined(separator: "\n")
}
func result(_ kind: ClientResultKind, in text: ClientViewText) -> ClientResultLine? { text.resultLines.first { $0.kind == kind } }

// Additive PAT-2670 lifecycle/image slice; original 15-check focused gate stays exact.
if CommandLine.arguments.contains("--pat-2670-menu-reopen") {
    registerNativeMenuReopenChecks()
    guard cases.count == 8 else {
        print("FAIL menu reopen: expected 8 checks, got \(cases.count)"); exit(1)
    }
    var errors = 0
    for (name, action) in cases {
        do { try await action(); print("PASS client: \(name)") }
        catch { errors += 1; print("FAIL client: \(name): \(error)") }
    }
    print("Menu reopen acceptance: \(cases.count) cases, \(errors) failures. Inactive adapter/image/source proof only; native proof remains separate.")
    exit(errors == 0 ? 0 : 1)
}

// PAT-2670 focused registration follows the shared fixture URL initialisation.
if CommandLine.arguments.contains("--pat-2670-native-menu") {
    registerNativeMenuIntegrationChecks()
    guard cases.count == 15 else {
        print("FAIL native menu integration: expected 15 independently prepared checks, got \(cases.count)")
        exit(1)
    }
    var focusedFailures = 0
    for (name, action) in cases {
        do { try await action(); print("PASS client: \(name)") }
        catch { focusedFailures += 1; print("FAIL client: \(name): \(error)") }
    }
    print("Native menu integration acceptance: \(cases.count) cases, \(focusedFailures) failures. Fixture/offscreen/source checks only; native operating acceptance remains separate.")
    exit(focusedFailures == 0 ? 0 : 1)
}

// MARK: Initial state and selection

check("initial: nothing is chosen, nothing has run, Check is disabled and every result is not run") {
    let controller = ClientController()
    try expect(controller.phase == .needsSelection, "Initial phase is \(controller.phase)")
    let text = controller.text
    try expect(!text.checkEnabled, "Check is enabled before anything is chosen")
    try expect(text.resultLines.map(\.kind) == [.bytes, .app, .container, .cleanup], "Result kinds are not the four separate results")
    try expect(text.resultLines.allSatisfy { $0.state == .notRun }, "A result is shown before any check")
    try expect(text.reason == nil && text.provenanceLine == nil, "Reason or provenance shown before any check")
    try expect(controller.versions == FirefoxTargets.pins.map(\.version) && controller.versions == ["157.0", "157.0.1"],
               "Versions are not exactly the compiled pins: \(controller.versions)")
}
check("selection: choosing a file and a version runs nothing and only enables an explicit Check") {
    let recorder = Recorder()
    let controller = ClientController(inspector: scripted(recorder))
    controller.select(fileURL: firefoxA)
    try expect(controller.phase == .needsSelection && !controller.text.checkEnabled, "A file alone enables Check")
    controller.selectVersion("157.0.1")
    try expect(controller.phase == .ready && controller.text.checkEnabled, "File and version did not make the controller ready")
    try expect(controller.text.resultLines.allSatisfy { $0.state == .notRun }, "Selection shows a result")
    try await Task.sleep(nanoseconds: 100_000_000)
    try expect(await recorder.count == 0, "Selection called the inspector")
}
check("selection: display shows the file name and exact version, and keeps the path internal") {
    let controller = ready(scripted(Recorder()), version: "157.0.1")
    let shown = everyVisible(controller)
    try expect(controller.text.fileLine.contains("Firefox 157.0.dmg"), "File name not shown: \(controller.text.fileLine)")
    try expect(controller.text.versionLine.contains("157.0.1") && !controller.text.versionLine.contains("157.0.1.1"), "Exact version not shown: \(controller.text.versionLine)")
    for leak in ["/Users/someone", "Downloads/", "/Users"] { try expect(!shown.contains(leak), "Visible state exposes the path fragment \(leak)") }
}
check("selection: a version outside the compiled pins is refused and enables nothing") {
    let recorder = Recorder()
    let controller = ClientController(inspector: scripted(recorder))
    controller.select(fileURL: firefoxA)
    for version in ["158.0", "157", "157.0.1 ", "", "latest"] {
        controller.selectVersion(version)
        try expect(controller.phase == .refused && !controller.text.checkEnabled, "Version '\(version)' was accepted: \(controller.phase)")
        try expect(controller.text.reason?.isEmpty == false, "No plain reason for version '\(version)'")
    }
    controller.check()
    await controller.waitUntilIdle()
    try expect(await recorder.count == 0, "An unsupported version reached the inspector")
}
check("input: a non-DMG, a non-file URL and a missing selection are refused and never inspected") {
    let recorder = Recorder()
    let controller = ClientController(inspector: scripted(recorder))
    controller.selectVersion("157.0")
    controller.check()
    try expect(controller.phase != .checking, "Check with no file started a check")
    for url in [URL(fileURLWithPath: "/tmp/Firefox.zip"), URL(fileURLWithPath: "/tmp/Firefox"), URL(string: "https://example.com/Firefox.dmg")!,
                URL(string: "http://example.com/Firefox.dmg")!] {
        controller.select(fileURL: url)
        try expect(controller.phase == .refused && !controller.text.checkEnabled, "\(url) was accepted: \(controller.phase)")
        try expect(controller.text.reason?.isEmpty == false, "No plain reason for \(url)")
        controller.check()
        try expect(controller.phase == .refused, "Check after refused selection changed phase to \(controller.phase)")
    }
    await controller.waitUntilIdle()
    try expect(await recorder.count == 0, "A refused selection reached the inspector")
    controller.select(fileURL: URL(fileURLWithPath: "/tmp/Firefox.DMG"))
    try expect(controller.phase == .ready, "An upper-case .DMG extension was not accepted: \(controller.phase)")
}
check("selection: a refused replacement clears the earlier selection instead of leaving it armed") {
    let recorder = Recorder()
    let controller = ready(scripted(recorder))
    controller.select(fileURL: URL(fileURLWithPath: "/tmp/notes.txt"))
    try expect(!controller.text.checkEnabled, "Check stayed enabled after refusing the replacement")
    controller.check(); await controller.waitUntilIdle()
    try expect(await recorder.count == 0, "The earlier file was inspected after a refused replacement")
}

// MARK: Explicit single execution and the off-main-actor boundary

check("check: one explicit Check runs the inspector exactly once with the chosen version and file, off the main thread") {
    let recorder = Recorder()
    let controller = ready(scripted(recorder) { _ in summary(version: "157.0.1") }, version: "157.0.1")
    controller.check()
    await controller.waitUntilIdle()
    let calls = await recorder.all
    try expect(calls.count == 1, "Inspector called \(calls.count) times")
    try expect(calls[0].version == "157.0.1" && calls[0].path == firefoxA.path, "Inspector got \(calls[0].version) \(calls[0].path)")
    try expect(!calls[0].onMainThread, "The inspector ran on the main thread")
    try expect(controller.phase == .passed, "Phase is \(controller.phase)")
}
check("check: the main actor stays responsive and truthful while the inspector runs") {
    let recorder = Recorder(), gate = Gate()
    let controller = ready(scripted(recorder, gate: gate))
    controller.check()
    try await until("inspector start") { await recorder.count == 1 }
    try expect(controller.phase == .checking && !controller.text.checkEnabled, "Not shown as checking: \(controller.phase)")
    try expect(controller.text.resultLines.allSatisfy { $0.state == .notRun }, "A result is shown while still running")
    try expect(!controller.text.statusLine.lowercased().contains("passed"), "Progress claims a pass: \(controller.text.statusLine)")
    await gate.open(); await controller.waitUntilIdle()
    try expect(controller.phase == .passed, "Did not finish: \(controller.phase)")
}
check("check: repeated and reentrant Check calls while running never start a second inspection") {
    let recorder = Recorder(), gate = Gate()
    let controller = ready(scripted(recorder, gate: gate))
    controller.check(); controller.check(); controller.check()
    try await until("inspector start") { await recorder.count >= 1 }
    controller.check()
    try await Task.sleep(nanoseconds: 100_000_000)
    try expect(await recorder.count == 1, "Overlapping Check started \(await recorder.count) inspections")
    await gate.open(); await controller.waitUntilIdle()
    try expect(await recorder.count == 1, "A queued second inspection ran after the first")
}
check("check: a further Check after completion is a new explicit run and replaces the earlier result") {
    let recorder = Recorder()
    let controller = ready(scripted(recorder) { $0 == 1 ? summary() : summary(app: false) })
    controller.check(); await controller.waitUntilIdle()
    try expect(controller.phase == .passed, "First run: \(controller.phase)")
    controller.check(); await controller.waitUntilIdle()
    try expect(await recorder.count == 2 && controller.phase == .notPassed, "Second run did not replace the first: \(controller.phase)")
}

// MARK: Results: success, failures, refusals, honesty

check("success: byte, app, container and cleanup results are separate and the test double is labelled") {
    let controller = ready(scripted(Recorder()))
    controller.check(); await controller.waitUntilIdle()
    let text = controller.text
    try expect(controller.phase == .passed, "Phase is \(controller.phase)")
    for kind in [ClientResultKind.bytes, .app, .cleanup] { try expect(result(kind, in: text)?.state == .passed, "\(kind) is not passed") }
    try expect(result(.container, in: text)?.state == .failed, "Unsigned container failures are hidden behind the app result")
    let label = text.provenanceLine ?? ""
    try expect(label.contains("Test double") && !label.lowercased().contains("fresh"), "A test double is not labelled as one: '\(label)'")
}
check("success: the disk image's three results are kept apart and a fully passing image reads as passed") {
    let controller = ready(scripted(Recorder()) { _ in summary(container: (true, true, true)) })
    controller.check(); await controller.waitUntilIdle()
    try expect(result(.container, in: controller.text)?.state == .passed, "All three container checks passing did not read as passed")
    let mixed = ready(scripted(Recorder()) { _ in summary(container: (true, false, true)) })
    mixed.check(); await mixed.waitUntilIdle()
    try expect(result(.container, in: mixed.text)?.state == .failed && mixed.phase == .passed, "One failed container check hid or overrode the app result")
    let detail = result(.container, in: mixed.text)?.detail.lowercased() ?? ""
    try expect(detail.contains("signature") && detail.contains("gatekeeper") && detail.contains("ticket"), "Container detail does not name the three checks: \(detail)")
}
check("failure: an app check that did not pass is not success and keeps its other results separate") {
    let controller = ready(scripted(Recorder()) { _ in summary(app: false) })
    controller.check(); await controller.waitUntilIdle()
    try expect(controller.phase == .notPassed, "Phase is \(controller.phase)")
    try expect(result(.app, in: controller.text)?.state == .failed && result(.bytes, in: controller.text)?.state == .passed, "App and byte results are not separate")
    try expect(controller.text.reason?.isEmpty == false, "No plain reason")
}
check("failure: unverified bytes are never success even when every other claim passes") {
    let controller = ready(scripted(Recorder()) { _ in summary(bytes: false) })
    controller.check(); await controller.waitUntilIdle()
    try expect(controller.phase != .passed && result(.bytes, in: controller.text)?.state != .passed, "Bytes not verified yet shown as success")
}
check("failure: cleanup that was not verified is never success and says so separately") {
    let controller = ready(scripted(Recorder()) { _ in summary(cleanup: false) })
    controller.check(); await controller.waitUntilIdle()
    try expect(controller.phase != .passed, "Phase is \(controller.phase) after cleanup failure")
    try expect(result(.cleanup, in: controller.text)?.state == .failed, "Cleanup failure not shown")
    let refused = ready(scripted(Recorder()) { _ in summary(app: nil, cleanup: false, refusal: "cleanupFailed") })
    refused.check(); await refused.waitUntilIdle()
    try expect(refused.phase == .refused && result(.cleanup, in: refused.text)?.state == .failed, "Inspector cleanup refusal not shown")
    try expect(!everyVisible(refused).contains("cleanupFailed"), "Raw refusal code is shown")
}
check("refusal: every inspector refusal is shown in plain words with no success and no raw code") {
    for code in ["unsafePath", "notRegularFile", "lengthMismatch", "digestMismatch", "wrongVersion", "wrongTeam", "signatureRejected",
                 "notarizationRejected", "ticketRejected", "invalidMount", "commandFailed", "commandTimedOut", "inspectionFailed: boom /private/path"] {
        let controller = ready(scripted(Recorder()) { _ in summary(bytes: false, app: nil, refusal: code) })
        controller.check(); await controller.waitUntilIdle()
        try expect(controller.phase == .refused, "\(code): phase \(controller.phase)")
        try expect(controller.text.resultLines.allSatisfy { $0.state != .passed || $0.kind == .cleanup }, "\(code): a result reads as passed")
        let shown = everyVisible(controller)
        try expect(controller.text.reason?.isEmpty == false && !shown.contains(code) && !shown.contains("/private/path"), "\(code): reason missing or raw: \(shown)")
    }
}
check("refusal: a thrown error becomes one generic plain refusal that does not echo the error") {
    let controller = ready(scripted(Recorder()) { _ in throw Boom() })
    controller.check(); await controller.waitUntilIdle()
    try expect(controller.phase == .refused && controller.text.reason?.isEmpty == false, "Thrown error phase \(controller.phase)")
    let shown = everyVisible(controller)
    try expect(!shown.contains("SECRET-INTERNAL-DETAIL") && !shown.contains("/Users/nobody") && !shown.contains("Boom"), "Thrown error text leaked: \(shown)")
    try expect(controller.text.resultLines.allSatisfy { $0.state != .passed }, "A result reads as passed after a throw")
}
check("honesty: only a live, fresh-OS inspector assessment can read as a fresh check; fixture and replayed origins are refused") {
    for (origin, fresh) in [(EvidenceOrigin.fixture, false), (.replayed, false), (.fixture, true), (.replayed, true), (.live, false)] {
        let controller = ready(scripted(Recorder()) { _ in summary(origin: origin, fresh: fresh) })
        controller.check(); await controller.waitUntilIdle()
        try expect(controller.phase == .refused, "origin \(origin) fresh \(fresh) gave \(controller.phase)")
        let shown = everyVisible(controller).lowercased()
        try expect(!shown.contains("checked now") && !shown.contains("fresh check"), "origin \(origin) fresh \(fresh) presented as a fresh check")
    }
    let missing = ready(scripted(Recorder()) { _ in summary(app: true, origin: nil) })
    missing.check(); await missing.waitUntilIdle()
    try expect(missing.phase == .refused, "An app pass without an assessment origin gave \(missing.phase)")
}
check("honesty: a result for version A is refused when the inspector reports a different version") {
    let controller = ready(scripted(Recorder()) { _ in summary(version: "157.0.1") }, version: "157.0")
    controller.check(); await controller.waitUntilIdle()
    try expect(controller.phase == .refused, "Mismatched reported version gave \(controller.phase)")
}

// MARK: No installation authority

check("authority: no summary, state or text can claim or enable installation") {
    let claimed = ready(scripted(Recorder()) { _ in summary(container: (true, true, true), installation: true) })
    claimed.check(); await claimed.waitUntilIdle()
    try expect(claimed.phase == .refused, "A summary claiming installation authority gave \(claimed.phase)")
    let builds: [@Sendable () -> ClientInspectionSummary] = [{ summary() }, { summary(container: (true, true, true)) }, { summary(app: false) }, { summary(refusal: "unsafePath") }]
    for build in builds {
        let controller = ready(scripted(Recorder()) { _ in build() })
        controller.check(); await controller.waitUntilIdle()
        let text = controller.text
        let action = text.checkTitle.lowercased()
        try expect(!action.contains("install") && !action.contains("update") && !action.contains("replace") && !action.contains("open"), "Action title offers more than a check: \(text.checkTitle)")
        try expect(text.footnote.lowercased().contains("nothing is installed") || text.footnote.lowercased().contains("no installation"), "Footnote does not say nothing is installed: \(text.footnote)")
        try expect(!text.allLines.joined(separator: " ").lowercased().contains("ready to install"), "Text suggests install readiness")
    }
}

// MARK: Selection change, cancellation, stale results

check("stale: changing the file during a check discards that result, clears prior success and blocks overlap until the old run ends") {
    let recorder = Recorder(), gate = Gate()
    let controller = ready(scripted(recorder, gate: gate))
    controller.check()
    try await until("inspector start") { await recorder.count == 1 }
    controller.select(fileURL: firefoxB)
    try expect(controller.phase == .ready && controller.text.fileLine.contains("Other Name.dmg"), "Replacement not applied: \(controller.phase)")
    try expect(!controller.text.checkEnabled, "Check re-enabled while the earlier inspection is still running")
    controller.check()
    try await Task.sleep(nanoseconds: 100_000_000)
    try expect(await recorder.count == 1, "A second inspection overlapped the stale one")
    await gate.open(); await controller.waitUntilIdle()
    try expect(controller.phase == .ready, "Stale result changed phase to \(controller.phase)")
    try expect(controller.text.resultLines.allSatisfy { $0.state == .notRun } && controller.text.reason == nil && controller.text.provenanceLine == nil, "Stale result became visible")
    try expect(controller.text.checkEnabled, "Check did not return once the stale run ended")
    controller.check(); await controller.waitUntilIdle()
    let calls = await recorder.all
    try expect(calls.count == 2 && calls[1].path == firefoxB.path, "The new check did not use the new file")
    try expect(controller.phase == .passed && controller.text.fileLine.contains("Other Name.dmg"), "New check not shown for the new file")
}
check("stale: changing the version during a check discards that result") {
    let recorder = Recorder(), gate = Gate()
    let controller = ready(scripted(recorder, gate: gate))
    controller.check()
    try await until("inspector start") { await recorder.count == 1 }
    controller.selectVersion("157.0.1")
    await gate.open(); await controller.waitUntilIdle()
    try expect(controller.phase == .ready && controller.text.versionLine.contains("157.0.1"), "Stale result applied after version change: \(controller.phase)")
    try expect(controller.text.resultLines.allSatisfy { $0.state == .notRun }, "Result for the old version is visible")
}
check("stale: a stale refusal or throw is discarded as well as a stale success") {
    for make in [{ @Sendable (_: Int) throws -> ClientInspectionSummary in throw Boom() },
                 { @Sendable (_: Int) throws -> ClientInspectionSummary in summary(app: nil, refusal: "digestMismatch") }] {
        let recorder = Recorder(), gate = Gate()
        let controller = ready(scripted(recorder, gate: gate, make))
        controller.check()
        try await until("inspector start") { await recorder.count == 1 }
        controller.select(fileURL: firefoxB)
        await gate.open(); await controller.waitUntilIdle()
        try expect(controller.phase == .ready && controller.text.reason == nil, "Stale failure became visible: \(controller.phase)")
    }
}
check("stale: replacing the selection after a finished check clears the earlier success") {
    let controller = ready(scripted(Recorder()))
    controller.check(); await controller.waitUntilIdle()
    try expect(controller.phase == .passed, "Setup: \(controller.phase)")
    controller.select(fileURL: firefoxB)
    try expect(controller.phase == .ready, "Phase after replacing file: \(controller.phase)")
    try expect(controller.text.resultLines.allSatisfy { $0.state == .notRun } && controller.text.provenanceLine == nil && controller.text.reason == nil, "Earlier success survived a replaced file")
    controller.check(); await controller.waitUntilIdle()
    controller.selectVersion("157.0.1")
    try expect(controller.phase == .ready && controller.text.resultLines.allSatisfy { $0.state == .notRun }, "Earlier success survived a changed version")
}
check("cancel: cancelling a running check discards its result, shows no success and blocks overlap until it ends") {
    let recorder = Recorder(), gate = Gate()
    let controller = ready(scripted(recorder, gate: gate))
    controller.check()
    try await until("inspector start") { await recorder.count == 1 }
    controller.cancel()
    try expect(controller.phase == .ready && !controller.text.checkEnabled, "Cancel state: \(controller.phase) enabled=\(controller.text.checkEnabled)")
    controller.check()
    try await Task.sleep(nanoseconds: 50_000_000)
    try expect(await recorder.count == 1, "Check ran while the cancelled inspection was still running")
    await gate.open(); await controller.waitUntilIdle()
    try expect(controller.phase == .ready && controller.text.resultLines.allSatisfy { $0.state == .notRun }, "Cancelled result became visible: \(controller.phase)")
}
check("cancel: cancelling after a finished check clears the success but keeps the selection") {
    let controller = ready(scripted(Recorder()))
    controller.check(); await controller.waitUntilIdle()
    controller.cancel()
    try expect(controller.phase == .ready && controller.text.checkEnabled, "Cancel after success: \(controller.phase)")
    try expect(controller.text.resultLines.allSatisfy { $0.state == .notRun } && controller.text.provenanceLine == nil, "Success survived cancel")
    let idle = ClientController(inspector: scripted(Recorder()))
    idle.cancel()
    try expect(idle.phase == .needsSelection, "Cancel with nothing chosen changed phase to \(idle.phase)")
}

// MARK: Real inspector binding (refused before any mount)

/// The `.build` directory that holds this executable, found independently of the library.
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
func newDirectory(_ prefix: String) throws -> URL {
    let directory = try buildDirectory().appendingPathComponent("\(prefix)-\(UUID().uuidString)")
    try expect(mkdir(directory.path, 0o700) == 0, "Directory was not created exclusively: errno \(errno)")
    return directory
}
check("production: the default controller reaches the real ArtifactInspector, which refuses a wrong-size file before any mount") {
    let directory = try newDirectory("patched-client-input")
    let file = directory.appendingPathComponent("Firefox 157.0.dmg")
    try Data("not a disk image".utf8).write(to: file)
    let controller = ClientController()
    controller.select(fileURL: file); controller.selectVersion("157.0")
    controller.check()
    await controller.waitUntilIdle()
    try expect(controller.phase == .refused, "Real inspector outcome was \(controller.phase)")
    try expect(result(.bytes, in: controller.text)?.state != .passed && result(.app, in: controller.text)?.state != .passed, "A bad file shows a passed result")
    try expect(result(.cleanup, in: controller.text)?.state == .passed, "The real inspector's verified cleanup is not reported")
    let label = (controller.text.provenanceLine ?? "").lowercased()
    try expect(!label.contains("test double"), "The production path is labelled as a test double: '\(label)'")
    try expect(!everyVisible(controller).contains(directory.path) && !everyVisible(controller).contains("lengthMismatch"), "Path or raw code leaked")
}
check("production: a missing file is refused by the real inspector without a result") {
    let directory = try newDirectory("patched-client-missing")
    let controller = ClientController()
    controller.select(fileURL: directory.appendingPathComponent("Absent.dmg")); controller.selectVersion("157.0.1")
    controller.check(); await controller.waitUntilIdle()
    try expect(controller.phase == .refused && controller.text.reason?.isEmpty == false, "Missing file gave \(controller.phase)")
    try expect(controller.text.resultLines.allSatisfy { $0.state != .passed || $0.kind == .cleanup }, "A missing file shows a passed result")
}
check("production: the existing pins, their digests and the inspector's refusal of unknown versions are unchanged") {
    try expect(FirefoxTargets.pins.map(\.version) == ["157.0", "157.0.1"], "Pinned versions changed")
    try expect(FirefoxTargets.pins.map(\.sha256) == ["df6d8c79b6126bcf24cb70ebab9371916a662028e2d706e462d432e78fdf396c",
                                                     "40a0a649120635460256dae9ad63e40377f77326cbc9c449a5d0a1d7f5dd7982"], "Pinned digests changed")
    try expect(FirefoxTargets.pins.map(\.byteLength) == [161304638, 161550118], "Pinned lengths changed")
    do { _ = try ArtifactInspector.inspectLocal(version: "158.0", path: "/nonexistent.dmg"); throw CheckFailure(description: "Unknown version accepted") }
    catch InspectionFailure.unknownTarget {}
}

// MARK: Static composition binding. Source text is checked only where behaviour cannot reach the code
// (the native chooser, the app's composition root, and tokens that must never appear).

func packageRoot() throws -> URL { try buildDirectory().deletingLastPathComponent() }
func source(_ relative: String) throws -> String {
    guard let text = try? String(contentsOf: try packageRoot().appendingPathComponent(relative), encoding: .utf8) else {
        throw CheckFailure(description: "Cannot read \(relative)")
    }
    return text
}
func swiftSources(_ directory: String) throws -> [(String, String)] {
    let root = try packageRoot().appendingPathComponent(directory)
    let names = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".swift") }.sorted()
    try expect(!names.isEmpty, "No sources in \(directory)")
    return try names.map { ($0, try source(directory + "/" + $0)) }
}
/// Source with whole-line comments removed, so prose cannot satisfy or trip a check.
func code(_ text: String) -> String { text.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n") }

check("composition: the client library calls the existing inspector exactly once, and only for a local file") {
    let text = try swiftSources("Sources/PatchedClient").filter { ["ClientController.swift", "ClientView.swift"].contains($0.0) }.map { code($0.1) }.joined(separator: "\n")
    try expect(text.components(separatedBy: "ArtifactInspector.inspectLocal(").count == 2, "PatchedClient must call ArtifactInspector.inspectLocal exactly once")
    for forbidden in ["downloadAndInspect", "URLSession", "NSURLConnection", "NSWorkspace", "NSRunningApplication", "Process(", "Timer", "DispatchSource",
                      "/Applications", "SMAppService", "Keychain", "SecItem", "readRecord", "EvidenceEvaluator", "ReadOnlyMount", "evaluateFixture", "replay("] {
        try expect(!text.contains(forbidden), "PatchedClient contains \(forbidden)")
    }
}
check("composition: test injection is SPI-only, so no linked product code can supply a result") {
    for (name, text) in try swiftSources("Sources/PatchedClient") {
        let lines = code(text).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for (index, line) in lines.enumerated() where line.contains("public init(") && (line.contains("inspector") || line.contains("provenance")) {
            let marked = line.contains("@_spi(Testing)") || (index > 0 && lines[index - 1].contains("@_spi(Testing)"))
            try expect(marked, "\(name) line \(index + 1) exposes a result-supplying initialiser without @_spi(Testing)")
        }
        try expect(!text.contains("#if DEBUG") && !text.contains("#if TEST"), "\(name) has a conditional test route")
    }
    let provenance = try swiftSources("Sources/PatchedClient").map { code($0.1) }.joined(separator: "\n")
    try expect(provenance.contains("testDouble"), "The test-double label is not defined in PatchedClient")
}
check("composition: PatchedApp composes the one shared ClientView over the default controller with no injection or update callback") {
    let app = code(try source("Sources/PatchedApp/PatchedApp.swift"))
    try expect(app.contains("import PatchedClient") && app.contains("@StateObject") && app.contains("NativeClientSession()") && app.contains("NativeClientRootView(session:"), "PatchedApp does not own the default native session/root")
    let composition = code(try source("Sources/PatchedClient/NativeClientSession.swift"))
    for required in ["public convenience init()", "ClientController()", "LocalApplicationsController()", "ShellNavigation(", "ClientView(", "session.inspection", "session.applications"] {
        try expect(composition.contains(required), "Default native composition lacks \(required)")
    }
    // CHECK-MODIFIED PAT-2666: convenience init shares the designated owner path;
    // the ordinary constructor still explicitly selects no development endpoint.
    try expect(composition.contains("public convenience init() { self.init(rawProbeEndpoint: nil) }") &&
        composition.contains("private init(rawProbeEndpoint: String?)") &&
        composition.contains("networkProbe: NativeNetworkProbeController(settings: network, rawProbeEndpoint: rawProbeEndpoint)"),
        "Ordinary/development construction no longer shares inert unconfigured ownership")
    for forbidden in ["inspector:", "ClientInspectionSummary", "UpdateView(", "onUpdate", "ArtifactInspector", "FixtureRoot", "Fixture", "URLSession", "Timer", "@_spi(Testing) import", ".onAppear", ".task"] {
        try expect(!composition.contains(forbidden), "Native composition contains \(forbidden)")
    }
    for forbidden in ["@_spi", "inspector:", "ClientInspectionSummary", "UpdateView(", "onUpdate", "ArtifactInspector", "FixtureRoot", "Fixture", "URLSession", "Timer"] {
        try expect(!app.contains(forbidden), "PatchedApp contains \(forbidden)")
    }
    let package = try source("Package.swift")
    guard let line = package.split(separator: "\n").first(where: { $0.contains("executableTarget(name: \"PatchedApp\"") }) else { throw CheckFailure(description: "PatchedApp target not found") }
    try expect(line.contains("\"PatchedClient\"") && !line.contains("Checks"), "PatchedApp dependencies are wrong: \(line)")
    try expect(!package.contains(".executable(name: \"patched-client-checks\", targets: [\"PatchedClient\"") , "The check product is bound to the library")
}
check("composition: the native chooser accepts exactly one disk image file and the view uses only system fonts") {
    let view = code(try swiftSources("Sources/PatchedClient").first(where: { $0.0 == "ClientView.swift" })?.1 ?? "")
    try expect(!view.isEmpty, "ClientView.swift is missing")
    try expect(view.contains("NSOpenPanel") && view.contains("allowsMultipleSelection = false") && view.contains("canChooseDirectories = false") && view.contains("canChooseFiles = true"),
               "The chooser is not limited to one file")
    try expect(view.contains(".diskImage") || view.contains("\"dmg\""), "The chooser is not limited to disk images")
    for forbidden in ["Font.custom", ".custom(", "design:", "NSFont(name", "fontName"] { try expect(!view.contains(forbidden), "ClientView uses a non-system font: \(forbidden)") }
    try expect(!view.contains("check()") || view.contains("controller.check()"), "ClientView starts a check other than through the controller")
    try expect(!view.contains(".onAppear") && !view.contains(".task"), "ClientView acts on appearance")
}

// MARK: Offscreen paint of the shared view

struct Painted { let name: String; let width: Int; let height: Int; let png: Data; let unpainted: Int; let distinct: Int }
@MainActor func paint(_ name: String, _ controller: ClientController) throws -> Painted {
    let renderer = ImageRenderer(content: ClientView(controller: controller).frame(width: 520, alignment: .leading)
        .background(Color.white).environment(\.colorScheme, .light))
    renderer.scale = 2
    guard let image = renderer.cgImage, let pixels = image.dataProvider?.data as Data? else { throw CheckFailure(description: "No image for \(name)") }
    try expect(image.bitsPerPixel == 32 && pixels.count >= image.bytesPerRow * image.height, "Unexpected pixel layout for \(name)")
    var unpainted = 0, distinct = Set<UInt32>()
    for line in 0..<image.height {
        for offset in stride(from: line * image.bytesPerRow, to: line * image.bytesPerRow + image.width * 4, by: 4) {
            let (first, green, third) = (pixels[offset], pixels[offset + 1], pixels[offset + 2])
            if (190...215).contains(green) && ((first > 240 && third < 20) || (third > 240 && first < 20)) { unpainted += 1 }
            distinct.insert(UInt32(first) << 16 | UInt32(green) << 8 | UInt32(third))
        }
    }
    let png = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else { throw CheckFailure(description: "No PNG destination") }
    CGImageDestinationAddImage(destination, image, nil)
    try expect(CGImageDestinationFinalize(destination), "PNG for \(name) was not encoded")
    return Painted(name: name, width: image.width, height: image.height, png: png as Data, unpainted: unpainted, distinct: distinct.count)
}
check("render: the real ClientView paints empty, ready, passed and refused states offscreen without running anything") {
    let recorder = Recorder()
    let empty = ClientController(inspector: scripted(recorder))
    let readyState = ready(scripted(recorder))
    let passed = ready(scripted(recorder)); passed.check(); await passed.waitUntilIdle()
    let refused = ready(scripted(recorder) { _ in summary(bytes: false, app: nil, refusal: "digestMismatch") }); refused.check(); await refused.waitUntilIdle()
    let callsBefore = await recorder.count
    let output = try newDirectory("patched-client-ui-fixture")
    var heights: [Int] = []
    for (name, controller) in [("empty", empty), ("ready", readyState), ("passed", passed), ("refused", refused)] {
        let before = controller.text
        let painted = try paint(name, controller)
        try expect(painted.width == 1040 && painted.height > 100, "\(name) has an implausible size \(painted.width)x\(painted.height)")
        try expect(painted.unpainted == 0, "\(name) shows the renderer's stand-in for an unpainted control: \(painted.unpainted) pixels")
        try expect(painted.distinct > 8, "\(name) looks blank: \(painted.distinct) colours")
        try expect(controller.text == before, "Painting \(name) changed the controller")
        try painted.png.write(to: output.appendingPathComponent("\(name).png"))
        heights.append(painted.height)
    }
    try expect(await recorder.count == callsBefore, "Painting called the inspector")
    try expect(Set(heights).count > 1, "All four states paint to the same height; the states are not distinguished")
}

// PAT-2704 additive independent native inventory checks.
registerLocalInventoryChecks()

// PAT-2705 additive independent Applications presentation checks.
registerLocalApplicationsChecks()

// PAT-2661 additive independent native inventory-to-Updates projection checks.
registerNativeUpdatesProjectionChecks()

// CHECK-MODIFIED PAT-2661: additive physical installed-identity checks in full gate.
registerInstalledIdentityIntegrationChecks()

// PAT-2660 additive independent native shell composition checks.
if CommandLine.arguments.contains("--pat-2660-native-composition") { cases.removeAll() }
registerNativeShellCompositionChecks()

// PAT-2670 registers once in the ordinary gate; existing focused gates retain their scope.
if !CommandLine.arguments.contains("--pat-2660-native-composition") { registerNativeMenuIntegrationChecks() }

// PAT-2672 additive installed vendor metadata extraction checks.
if !CommandLine.arguments.contains("--pat-2660-native-composition") { registerInstalledVendorMetadataChecks() }

// PAT-2666 additive independent settings checks.
if !CommandLine.arguments.contains("--pat-2660-native-composition") { registerNativeNetworkSettingsChecks() }

// PAT-2667 additive independent controller checks; preserve older focused scopes.
if CommandLine.arguments.contains("--pat-2667-native-first-run") {
    cases.removeAll()
    registerNativeFirstRunChecks()
    registerNativeFirstRunViewChecks()
} else if !CommandLine.arguments.contains("--pat-2660-native-composition") {
    registerNativeFirstRunChecks()
    registerNativeFirstRunViewChecks()
}

// MARK: Run
if !CommandLine.arguments.contains("--pat-2660-native-composition") && !CommandLine.arguments.contains("--pat-2667-native-first-run") { registerNativeActivityNavigationChecks() }

// PAT-2668 final registration: new focus replaces all earlier cases; old focus scopes remain exact.
if CommandLine.arguments.contains("--pat-2668-native-schedule-app") {
    cases.removeAll()
    registerNativeScheduleAppChecks()
} else if !CommandLine.arguments.contains("--pat-2660-native-composition") && !CommandLine.arguments.contains("--pat-2667-native-first-run") {
    registerNativeScheduleAppChecks()
}

// PAT-2731 additive source/provenance checks; preserve every earlier focus scope.
if CommandLine.arguments.contains("--pat-2731-provenance") {
    cases.removeAll()
    registerProvenancePresentationChecks()
    registerProvenanceBoundaryChecks()
} else if !CommandLine.arguments.contains("--pat-2660-native-composition") &&
          !CommandLine.arguments.contains("--pat-2667-native-first-run") &&
          !CommandLine.arguments.contains("--pat-2668-native-schedule-app") {
    registerProvenancePresentationChecks()
    registerProvenanceBoundaryChecks()
}

// Preserve the PAT-2731 focus while retaining the PAT-2732 registration verbatim.
if !CommandLine.arguments.contains("--pat-2731-provenance") {
// PAT-2732 final focus preserves every pre-existing focused scope.
if CommandLine.arguments.contains("--pat-2732-product-metadata") {
    cases.removeAll()
    registerVSCodeProductMetadataChecks()
} else if !CommandLine.arguments.contains("--pat-2660-native-composition") && !CommandLine.arguments.contains("--pat-2667-native-first-run") && !CommandLine.arguments.contains("--pat-2668-native-schedule-app") {
    registerVSCodeProductMetadataChecks()
}

}

// PAT-2660 additive installed-icon checks. Earlier focused scopes remain exact.
if CommandLine.arguments.contains("--pat-2660-installed-icons-fixtures") {
    cases.removeAll()
    registerInstalledIconFixturePreflightChecks()
} else if CommandLine.arguments.contains("--pat-2660-installed-icons") {
    cases.removeAll()
    registerInstalledIconFixturePreflightChecks()
    registerInstalledIconChecks()
} else if !CommandLine.arguments.contains("--pat-2660-native-composition") &&
          !CommandLine.arguments.contains("--pat-2667-native-first-run") &&
          !CommandLine.arguments.contains("--pat-2668-native-schedule-app") &&
          !CommandLine.arguments.contains("--pat-2731-provenance") &&
          !CommandLine.arguments.contains("--pat-2732-product-metadata") {
    registerInstalledIconFixturePreflightChecks()
    registerInstalledIconChecks()
}

if CommandLine.arguments.count == 1 { registerInstalledIdentityWorkerChecks() }

// Register in the ordinary no-argument full gate without altering older focused scopes.
if CommandLine.arguments.count == 1 { registerNativeMenuReopenChecks() }

// Add the controlled local-peer checks to the full gate; preserve every older focus.
if CommandLine.arguments.count == 1 { registerManualProxyProbeChecks() }
if CommandLine.arguments.count == 1 { registerManualProxyFramingChecks() }
if CommandLine.arguments.count == 1 { registerManualProxyFramingBoundChecks() }
if CommandLine.arguments.count == 1 { registerManualProxyFramingFinalChecks() }
if CommandLine.arguments.count == 1 { registerLoopbackShutdownControlChecks() }
if CommandLine.arguments.count == 1 { registerArtifactLoopbackShutdownRaceChecks() }

if CommandLine.arguments.count == 1 { registerNativeNetworkProbeCompositionChecks() }
if CommandLine.arguments.count == 1 { registerNativeNetworkProbeSupplementalReentrancyChecks() }

var failures = 0
for (name, action) in cases {
    do { try await action(); print("PASS client: \(name)") }
    catch { failures += 1; print("FAIL client: \(name): \(error)") }
}
print("Client flow acceptance: \(cases.count) cases, \(failures) failures. Test doubles are labelled and grant nothing. No download, mount of a real artifact, installation or launch.")
exit(failures == 0 ? 0 : 1)
