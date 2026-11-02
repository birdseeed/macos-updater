import Foundation
import Darwin
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import ArtifactInspection
@_spi(Testing) import PatchedOperator

// PAT-2601 checks for the read-only operator session. The success paths use distinctly labelled
// display-only summaries: no receipt is built here. Only the default verifier is real, and it
// is given a wrong-size or missing file, so it refuses before any mount. Writes stay beneath .build.
// No app is launched, nothing is mounted, no network, key or credential is touched.
struct CheckFailure: Error, CustomStringConvertible { let description: String }
struct Leak: Error, CustomStringConvertible { let description = "SECRET-RAW-ERROR /Users/someone/private" }
func expect(_ condition: Bool, _ message: String) throws { if !condition { throw CheckFailure(description: message) } }

/// A display-only verifier double. It records every call and thread, and can hold the worker until released.
final class Gate: @unchecked Sendable {
    private let lock = NSLock(), hold = DispatchSemaphore(value: 0)
    private var log: [(version: String, path: String, main: Bool)] = []
    private var running = 0, peak = 0
    let blocks: Bool, result: @Sendable () throws -> OperatorSessionSummary
    init(blocks: Bool = false, result: @escaping @Sendable () throws -> OperatorSessionSummary = { good() }) { self.blocks = blocks; self.result = result }
    func run(_ version: String, _ path: String) throws -> OperatorSessionSummary {
        lock.lock(); log.append((version, path, pthread_main_np() != 0)); running += 1; peak = max(peak, running); lock.unlock()
        defer { lock.lock(); running -= 1; lock.unlock() }
        if blocks, hold.wait(timeout: .now() + 20) == .timedOut { throw CheckFailure(description: "worker never released") }
        return try result()
    }
    func release() { hold.signal() }
    var calls: Int { lock.lock(); defer { lock.unlock() }; return log.count }
    var paths: [String] { lock.lock(); defer { lock.unlock() }; return log.map(\.path) }
    var versions: [String] { lock.lock(); defer { lock.unlock() }; return log.map(\.version) }
    var anyOnMain: Bool { lock.lock(); defer { lock.unlock() }; return log.contains { $0.main } }
    var maxOverlap: Int { lock.lock(); defer { lock.unlock() }; return peak }
    @MainActor var session: OperatorSession { OperatorSession(displaySummaryVerifier: { try self.run($0, $1) }) }
}
func good(_ origin: EvidenceOrigin = .live, app: Bool = true, sig: Bool = true, gk: Bool = true, ticket: Bool = true, clean: Bool = true) -> OperatorSessionSummary {
    OperatorSessionSummary(provenance: origin, appChecksPassed: app, containerSignaturePassed: sig, containerGatekeeperPassed: gk,
                           containerTicketPassed: ticket, cleanupVerified: clean)
}

var cases: [(String, @MainActor () async throws -> Void)] = []
@MainActor func check(_ name: String, _ action: @escaping @MainActor () async throws -> Void) { cases.append((name, action)) }

let work: URL = {
    var build = Bundle.main.executableURL!.resolvingSymlinksInPath()
    while build.lastPathComponent != ".build" && build.pathComponents.count > 1 { build.deleteLastPathComponent() }
    let directory = build.appendingPathComponent("patched-operator-session-\(UUID().uuidString)")
    precondition(mkdir(directory.path, 0o700) == 0, "work directory not created exclusively")
    return directory
}()
func file(_ name: String, bytes: Int = 10) -> URL {
    let url = work.appendingPathComponent(name)
    if bytes > 0 { precondition(FileManager.default.createFile(atPath: url.path, contents: Data(count: bytes), attributes: [.posixPermissions: 0o600])) }
    return url
}
let (fileA, fileB) = (file("a.dmg"), file("b.dmg"))
@MainActor func chosen(_ session: OperatorSession, _ url: URL = fileA, _ version: String = "157.0") {
    session.select(fileURL: url); session.selectVersion(version)
}
@MainActor func until(_ condition: @MainActor () -> Bool) async throws {
    for _ in 0..<2_000 { if condition() { return }; try await Task.sleep(nanoseconds: 5_000_000) }
    throw CheckFailure(description: "condition never became true")
}
/// Sign and publish are never enabled, each with its own concrete missing capability, and nothing names a raw path or error.
@MainActor func invariants(_ session: OperatorSession, _ label: String) throws {
    let text = session.text
    try expect(!text.signingEnabled && !text.publicationEnabled, "\(label): signing or publication enabled")
    try expect(text.signingReason.localizedCaseInsensitiveContains("signing") && text.signingReason.localizedCaseInsensitiveContains("capability"), "\(label): signing reason not concrete")
    try expect(text.publicationReason.localizedCaseInsensitiveContains("publication") && text.publicationReason.localizedCaseInsensitiveContains("destination"), "\(label): publication reason not concrete")
    try expect(text.signingReason != text.publicationReason, "\(label): reasons are not separate")
    let everything = String(describing: text)
    try expect(!everything.contains(work.path) && !everything.contains("/Users/") && !everything.contains("SECRET"), "\(label): raw path or error displayed")
}
/// The status words of a session that has only been selected, for comparing with a session whose late result was discarded.
@MainActor func readyStatus(_ version: String = "157.0") -> String { let s = Gate().session; chosen(s, fileA, version); return s.text.status }
@MainActor func idle(_ session: OperatorSession) async { await session.waitUntilIdle() }

check("start: nothing chosen, nothing run, verify and cancel off, sign and publish refused with separate reasons") {
    let gate = Gate(), session = gate.session
    try expect(session.phase == .idle && !session.text.verifyEnabled && !session.text.cancelEnabled && !session.holdsResult, "default state")
    try expect(session.text.cleanupLine == nil, "initial state implies a cleanup result")
    session.verify(); await idle(session)
    try expect(gate.calls == 0, "verify ran with nothing chosen")
    try invariants(session, "start")
}
check("select: a file and a pinned version make Verify available without running it; no path is shown") {
    let gate = Gate(), session = gate.session
    session.select(fileURL: fileA); try expect(session.phase == .idle && !session.text.verifyEnabled, "file alone")
    session.selectVersion("157.0.1"); try expect(session.phase == .ready && session.text.verifyEnabled && gate.calls == 0, "ready")
    try invariants(session, "ready")
}
check("unsupported: non-file URL, non-DMG file and unknown version never enable or run Verify") {
    let gate = Gate(), session = gate.session
    session.select(fileURL: URL(string: "https://example.com/a.dmg")!); session.selectVersion("157.0")
    try expect(!session.text.verifyEnabled, "network URL accepted")
    session.select(fileURL: file("note.txt")); try expect(!session.text.verifyEnabled, "non-DMG accepted")
    session.select(fileURL: fileA); session.selectVersion("158.0"); try expect(!session.text.verifyEnabled, "unknown version accepted")
    session.verify(); await idle(session); try expect(gate.calls == 0 && session.phase == .idle, "unsupported input ran")
    try invariants(session, "unsupported")
}
check("verify: runs exactly once off the main thread, main stays responsive, a second click cannot overlap") {
    let gate = Gate(blocks: true), session = gate.session
    chosen(session, fileA, "157.0.1"); session.verify()
    try await until { gate.calls == 1 }
    try expect(session.phase == .verifying && !session.text.verifyEnabled && session.text.cancelEnabled, "not verifying")
    session.verify(); session.verify(); try await Task.sleep(nanoseconds: 50_000_000)
    try expect(gate.calls == 1 && gate.maxOverlap == 1, "reentrant verify")
    try invariants(session, "verifying")
    gate.release(); await idle(session)
    try expect(gate.calls == 1 && !gate.anyOnMain, "verifier ran \(gate.calls) times or on main")
    try expect(gate.paths == [fileA.path] && gate.versions == ["157.0.1"], "verifier got the wrong input")
    try expect(session.phase == .verified && session.holdsResult && session.text.provenanceLine != nil, "no result held")
    try expect(session.text.cleanupLine?.localizedCaseInsensitiveContains("confirmed") == true && session.text.cleanupLine?.localizedCaseInsensitiveContains("not") == false,
               "success does not explicitly confirm cleanup: \(String(describing: session.text.cleanupLine))")
    try invariants(session, "verified")
}
check("verify again: the earlier success is cleared at once and the second run completes alone") {
    let gate = Gate(), session = gate.session
    chosen(session); session.verify(); await idle(session)
    try expect(session.holdsResult, "first success")
    session.verify(); try expect(session.phase == .verifying && !session.holdsResult && session.text.provenanceLine == nil, "success kept while verifying")
    await idle(session); try expect(gate.calls == 2 && session.phase == .verified && gate.maxOverlap == 1, "second run")
}
check("stale success: changing file or version while verifying discards the late result") {
    for change in 0..<2 {
        let gate = Gate(blocks: true), session = gate.session
        chosen(session); session.verify(); try await until { gate.calls == 1 }
        if change == 0 { session.select(fileURL: fileB) } else { session.selectVersion("157.0.1") }
        try expect(!session.holdsResult && session.phase != .verified, "change \(change) left a result")
        gate.release(); await idle(session)
        try expect(session.phase == .ready && !session.holdsResult && session.text.provenanceLine == nil && session.text.status == readyStatus(change == 0 ? "157.0" : "157.0.1"), "late success shown after change \(change)")
        try invariants(session, "stale success \(change)")
    }
}
check("stale failure: a late refusal after a change or cancel is not shown") {
    for change in 0..<3 {
        let gate = Gate(blocks: true, result: { throw OperatorFailure.digestMismatch }), session = gate.session
        chosen(session); session.verify(); try await until { gate.calls == 1 }
        switch change { case 0: session.select(fileURL: fileB); case 1: session.selectVersion("157.0.1"); default: session.cancel() }
        gate.release(); await idle(session)
        try expect(session.phase == .ready && session.text.status == readyStatus(change == 1 ? "157.0.1" : "157.0"), "late refusal shown after change \(change)")
    }
}
check("cancel: clears a previous success and an in-flight run; Verify stays blocked until the real worker returns") {
    let gate = Gate(blocks: true), session = gate.session
    chosen(session); session.verify(); try await until { gate.calls == 1 }
    session.cancel()
    try expect(session.phase == .cancelling && !session.text.verifyEnabled && !session.text.cancelEnabled && !session.holdsResult, "cancel state")
    try expect(session.text.status == "The earlier check is still running. Its result will be discarded when it ends." && session.text.cleanupLine == nil, "cancelling words: \(session.text.status)")
    session.verify(); try await Task.sleep(nanoseconds: 50_000_000)
    try expect(gate.calls == 1 && gate.maxOverlap == 1, "verify overlapped a cancelled worker")
    gate.release(); await idle(session)
    try expect(session.phase == .ready && session.text.verifyEnabled && !session.holdsResult, "not ready after worker returned")
    session.verify(); try await until { gate.calls == 2 }; gate.release(); await idle(session)
    try expect(session.phase == .verified && gate.maxOverlap == 1, "verify after the worker returned")
    let finished = Gate().session
    chosen(finished); finished.verify(); await idle(finished); finished.cancel()
    try expect(finished.phase == .ready && !finished.holdsResult && finished.text.provenanceLine == nil, "cancel kept a success")
}
check("select during a run: a new Verify waits for the old worker, then runs once with the new file") {
    let gate = Gate(blocks: true), session = gate.session
    chosen(session); session.verify(); try await until { gate.calls == 1 }
    session.select(fileURL: fileB); session.verify(); try await Task.sleep(nanoseconds: 50_000_000)
    try expect(gate.calls == 1 && gate.maxOverlap == 1, "overlapping verify")
    gate.release(); await idle(session)
    session.verify(); try await until { gate.calls == 2 }; gate.release(); await idle(session)
    try expect(gate.paths == [fileA.path, fileB.path] && session.phase == .verified && gate.maxOverlap == 1, "second run input")
}
check("failure: a typed refusal shows its plain reason; an untyped error shows only a generic one; nothing is held") {
    let typed = Gate(result: { throw OperatorFailure.lengthMismatch }).session
    chosen(typed); typed.verify(); await idle(typed)
    try expect(typed.phase == .refused && !typed.holdsResult && typed.text.status.contains(OperatorViewText.refusalReason(.lengthMismatch)), "typed refusal")
    try expect(typed.text.cleanupLine == nil, "ordinary refusal implies a cleanup result")
    try invariants(typed, "typed refusal")
    let untyped = Gate(result: { throw Leak() }).session
    chosen(untyped); untyped.verify(); await idle(untyped)
    try expect(untyped.phase == .refused && !untyped.holdsResult && !untyped.text.status.isEmpty, "untyped refusal")
    try expect(untyped.text.cleanupLine == nil, "untyped refusal implies a cleanup result")
    try invariants(untyped, "untyped refusal")
}
check("refusal then success: the refusal is cleared and the success shown") {
    let flip = Gate(result: { throw OperatorFailure.inspectionRefused }), session = flip.session
    chosen(session); session.verify(); await idle(session); try expect(session.phase == .refused, "refused")
    session.select(fileURL: fileB); try expect(session.phase == .ready && session.text.status == readyStatus(), "refusal kept after new selection")
}
check("provenance: live, fixture and replayed results are labelled differently and only live claims a fresh check") {
    var lines: [String] = []
    for origin in [EvidenceOrigin.live, .fixture, .replayed] {
        let session = Gate(result: { good(origin) }).session
        chosen(session); session.verify(); await idle(session)
        let line = try { guard let line = session.text.provenanceLine else { throw CheckFailure(description: "\(origin) unlabelled") }; return line }()
        lines.append(line)
        try expect(line.localizedCaseInsensitiveContains("test double"), "Display-only double was not labelled: \(line)")
        try expect(origin == .live || !String(describing: session.text).localizedCaseInsensitiveContains("fresh"), "\(origin) claims a fresh check")
        try expect(line.localizedCaseInsensitiveContains(origin.rawValue == "live" ? "live" : origin.rawValue), "\(origin) label wrong: \(line)")
        try invariants(session, "provenance \(origin)")
    }
    try expect(Set(lines).count == 3, "provenance labels not distinct")
}
check("containers: signature, Gatekeeper and ticket are three separate lines, apart from the app checks") {
    let session = Gate(result: { good(sig: true, gk: false, ticket: true) }).session
    chosen(session); session.verify(); await idle(session)
    let lines = session.text.containerLines
    try expect(session.phase == .verified && lines.count == 3, "container lines")
    try expect(lines[0].localizedCaseInsensitiveContains("signature") && lines[1].localizedCaseInsensitiveContains("gatekeeper") && lines[2].localizedCaseInsensitiveContains("ticket"), "container order")
    try expect(!lines[0].contains("not") && lines[1].contains("did not pass") && !lines[2].contains("not"), "container results merged: \(lines)")
    try expect(session.text.appLine?.contains("passed") == true && session.text.appLine?.contains("not") == false, "app line")
}
check("containers: a failing app check is not hidden by passing disk image checks") {
    let session = Gate(result: { good(app: false) }).session
    chosen(session); session.verify(); await idle(session)
    try expect(session.text.appLine?.contains("did not pass") == true && session.text.containerLines.allSatisfy { !$0.contains("not") }, "app and container merged")
}
check("cleanup: an unverified cleanup is a refusal, never a success") {
    let session = Gate(result: { good(clean: false) }).session
    chosen(session); session.verify(); await idle(session)
    try expect(session.phase == .refused && !session.holdsResult && session.text.provenanceLine == nil, "cleanup failure counted as success")
    try expect(session.text.cleanupLine?.localizedCaseInsensitiveContains("not confirmed") == true, "cleanup failure not separately shown: \(String(describing: session.text.cleanupLine))")
    try expect(session.text.appLine == nil && session.text.containerLines.isEmpty, "cleanup failure shows held results")
    let typed = Gate(result: { throw OperatorFailure.cleanupUnverified }).session
    chosen(typed); typed.verify(); await idle(typed)
    try expect(typed.phase == .refused && !typed.holdsResult && typed.text.cleanupLine?.localizedCaseInsensitiveContains("not confirmed") == true, "typed cleanup failure not shown")
    chosen(session, fileB)
    try expect(session.text.cleanupLine == nil, "cleanup failure survived a new selection")
    try invariants(session, "cleanup")
}
check("default verifier: a wrong-size or missing file is refused before any mount, with no raw path") {
    for (index, url) in [file("tiny.dmg", bytes: 10), work.appendingPathComponent("missing.dmg")].enumerated() {
        let session = OperatorSession()
        try expect(session.phase == .idle && !session.holdsResult, "default session not idle")
        chosen(session, url); session.verify(); await idle(session)
        try expect(session.phase == .refused && !session.holdsResult && session.text.provenanceLine == nil, "real verifier accepted case \(index)")
        if index == 0 { try expect(session.text.status.contains(OperatorViewText.refusalReason(.lengthMismatch)), "wrong-size reason") }
        try invariants(session, "real verifier \(index)")
    }
}

// MARK: Painted states of the actual view, offscreen

@MainActor func paint(_ name: String, _ session: OperatorSession) throws -> (Data, Int) {
    let renderer = ImageRenderer(content: OperatorSessionView(session: session).frame(width: 480, alignment: .leading)
        .background(Color.white).environment(\.colorScheme, .light))
    renderer.scale = 2
    guard let image = renderer.cgImage, let pixels = image.dataProvider?.data as Data?, image.bitsPerPixel == 32 else { throw CheckFailure(description: "no image for \(name)") }
    var distinct = Set<UInt32>(), unpainted = 0
    for row in 0..<image.height {
        for offset in stride(from: row * image.bytesPerRow, to: row * image.bytesPerRow + image.width * 4, by: 4) {
            let (a, g, c) = (pixels[offset], pixels[offset + 1], pixels[offset + 2])
            if (190...215).contains(g) && ((a > 240 && c < 20) || (c > 240 && a < 20)) { unpainted += 1 }
            distinct.insert(UInt32(a) << 16 | UInt32(g) << 8 | UInt32(c))
        }
    }
    try expect(distinct.count > 2 && unpainted == 0, "\(name) is blank or has unpainted controls")
    let png = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else { throw CheckFailure(description: "no PNG") }
    CGImageDestinationAddImage(destination, image, nil)
    try expect(CGImageDestinationFinalize(destination), "PNG not encoded")
    try (png as Data).write(to: work.appendingPathComponent("\(name).png"), options: .withoutOverwriting)
    return (pixels, image.height)
}
check("render: the real OperatorSessionView paints empty, selected, double-success and refused states, all different") {
    let empty = Gate().session
    let selected = Gate().session; chosen(selected)
    let doubled = Gate().session; chosen(doubled)
    doubled.verify(); await idle(doubled); doubled.verify(); await idle(doubled)
    try expect(doubled.phase == .verified, "double success")
    let refused = Gate(result: { throw OperatorFailure.digestMismatch }).session; chosen(refused); refused.verify(); await idle(refused)
    let painted = try [("empty", empty), ("selected", selected), ("double-success", doubled), ("refused", refused)].map { try paint($0.0, $0.1) }
    for (index, first) in painted.enumerated() {
        for second in painted.dropFirst(index + 1) { try expect(first.0 != second.0 || first.1 != second.1, "two states paint identically") }
    }
    print("Painted session states kept for inspection: \(work.path)")
}

// MARK: Source composition guards (they complement the behaviour above)

func source(_ path: String) throws -> String {
    try String(contentsOfFile: FileManager.default.currentDirectoryPath + "/" + path, encoding: .utf8)
}
func count(_ needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }
check("source: the session calls the real verifier exactly once and has no sign, publish, key, network or launch path") {
    let session = try source("Sources/PatchedOperator/OperatorSession.swift")
    try expect(count("OperatorVerification.verifyPinnedArtifact(", in: session) == 1, "real verifier not called exactly once")
    for banned in ["fixtureReceipt", "VerifiedArtifactReceipt(", "acceptRecordedInspection", "FixtureOperatorAuthority", "CatalogueSigning", "CataloguePublisher",
                   "SignedCatalogue", "PublishedCatalogue", "func sign", "func publish", "URLSession", "Process(", "NSWorkspace", "hdiutil",
                   "Keychain", "SecItem", "PrivateKey", "Timer", "NSOpenPanel(directory", "inspectLocal", "ArtifactDownloader"] {
        try expect(!session.contains(banned), "session source contains \(banned)")
    }
    for line in session.split(separator: "\n") where line.contains("@_spi") {
        try expect(!line.localizedCaseInsensitiveContains("sign") && !line.localizedCaseInsensitiveContains("publish") && !line.localizedCaseInsensitiveContains("key"),
                   "SPI hook for sign, publish or key: \(line)")
    }
    let sourceLines = session.split(separator: "\n").map(String.init)
    let injected = sourceLines.enumerated().filter { $0.element.contains("public init(") && $0.element.contains("displaySummaryVerifier") }
    try expect(injected.count == 1, "expected exactly one injected-summary init")
    for (index, line) in injected {
        try expect(line.contains("@_spi(Testing)") || (index > 0 && sourceLines[index - 1].contains("@_spi(Testing)")), "injected-summary init is not SPI-only")
    }
    let view = try source("Sources/PatchedOperator/OperatorSessionView.swift")
    try expect(view.contains("NSOpenPanel") && view.contains("allowsMultipleSelection = false") && view.contains("canChooseDirectories = false"), "single-DMG chooser")
    try expect(!view.contains(".onAppear") && !view.contains(".task") && !view.contains("design: .") && !view.contains("Font.custom") && !view.contains(".custom("), "view runs work on appear or uses a custom font")
}
check("source: the app wires the default real session with no startup work, SPI or timer") {
    let app = try source("Sources/PatchedOperatorApp/PatchedOperatorApp.swift")
    try expect(app.contains("OperatorSession()") && app.contains("OperatorSessionView("), "app does not use the default session")
    for banned in ["_spi", ".verify(", ".onAppear", ".task", "Timer", "URLSession", "displaySummaryVerifier"] { try expect(!app.contains(banned), "app contains \(banned)") }
}

var failures = 0
for (name, action) in cases {
    do { try await action(); print("PASS \(name)") } catch { failures += 1; print("FAIL \(name): \(error)") }
}
print(failures == 0 ? "All \(cases.count) operator session checks passed." : "\(failures) of \(cases.count) operator session checks FAILED.")
exit(failures == 0 ? 0 : 1)
