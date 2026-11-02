import Foundation
import Darwin
@_spi(Testing) import PatchedDisposableProof

// The only child is this exact check executable. Modes write pipes, delay at
// most 100 ms and exit. They never open files, spawn children or invoke apps.
func standardOutput(_ mode: SyntheticChildMode) -> Data {
    Data(("{\"selfCheck\":true,\"mode\":\"" + mode.rawValue + "\"}\n").utf8)
}
func emit(_ handle: FileHandle, _ data: Data) {
    do { try handle.write(contentsOf: data) } catch { exit(91) }
}
if CommandLine.arguments.count > 1 {
    guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--synthetic-child",
          let mode = SyntheticChildMode(rawValue: CommandLine.arguments[2]) else { exit(92) }
    emit(.standardOutput, standardOutput(mode))
    if mode == .trailing { emit(.standardOutput, Data("trailing\n".utf8)) }
    if [.overflow, .overflowNonzero, .dualOverflow].contains(mode) {
        let block = Data(repeating: 65, count: 8192)
        for _ in 0..<128 {
            emit(.standardOutput, block)
            if mode == .dualOverflow { emit(.standardError, block) }
        }
    }
    usleep(mode == .delayed ? 100_000 : 50_000)
    emit(.standardError, Data("FINAL-CHILD-MARKER\n".utf8))
    exit(mode == .nonzero || mode == .overflowNonzero ? 7 : 0)
}

struct CheckFailure: Error, CustomStringConvertible { let description: String }
func expect(_ value: Bool, _ message: String) throws { if !value { throw CheckFailure(description: message) } }
func refusal(_ wanted: DisposableFailure, _ operation: () throws -> Void) throws {
    do { try operation(); throw CheckFailure(description: "Expected \(wanted), accepted") }
    catch let actual as DisposableFailure { try expect(actual == wanted, "Expected \(wanted), got \(actual)") }
}
func run(_ mode: SyntheticChildMode, limit: Int = 4096) throws -> SyntheticChildCompletion {
    let token = try SyntheticChildInvocation.selfCheck(mode)
    let result = try SyntheticChildProcess.capture(token, outputLimit: limit)
    try expect(result.executable == token.executable && result.arguments == ["--synthetic-child", mode.rawValue],
               "Runner changed exact executable/argv")
    try expect(result.childExited, "Completion returned while child was alive")
    return result
}

var cases = 0, failures = 0
@MainActor func check(_ name: String, _ operation: () throws -> Void) {
    cases += 1
    do { try operation(); print("PASS disposable-process: \(name)") }
    catch { failures += 1; print("FAIL disposable-process: \(name): \(error)") }
}
check("host live factory refuses before any proof path access") {
    try refusal(.guestMismatch) { _ = try NativeInstalledActionScope.open(runID: "../../not-a-run", caseRoot: "/Applications") }
}
check("synthetic token cannot enter productive dispatcher") {
    let token = try SyntheticChildInvocation.selfCheck(.clean)
    try refusal(.notAuthorized) { try SyntheticChildProcess.requestProductiveDispatch(token) }
}
check("clean self-check captures exact executable argv stdout stderr and actual exit") {
    let result = try run(.clean)
    try expect(result.stdout == standardOutput(.clean) && result.stderr == Data("FINAL-CHILD-MARKER\n".utf8), "Wrong captured bytes")
    try expect(result.exitCode == 0 && !result.outputExceeded, "Clean child failed or overflowed")
    try result.requireAccepted(expectedStdout: standardOutput(.clean))
}
check("delayed child completes only after final marker without timeout termination") {
    let began = Date(), result = try run(.delayed)
    try expect(Date().timeIntervalSince(began) >= 0.09 && result.stderr == Data("FINAL-CHILD-MARKER\n".utf8) && result.exitCode == 0,
               "Child was not waited through its bounded delay and final write")
    try result.requireAccepted(expectedStdout: standardOutput(.delayed))
}
check("nonzero child is drained and observed then refused") {
    let result = try run(.nonzero)
    try expect(result.exitCode == 7 && result.stderr == Data("FINAL-CHILD-MARKER\n".utf8) && !result.outputExceeded, "Nonzero exit was fabricated or killed")
    try refusal(.notAuthorized) { try result.requireAccepted(expectedStdout: standardOutput(.nonzero)) }
}
check("trailing stdout is preserved and refused after actual exit") {
    let result = try run(.trailing)
    try expect(result.exitCode == 0 && result.stdout == standardOutput(.trailing) + Data("trailing\n".utf8), "Trailing bytes were normalised away")
    try refusal(.notAuthorized) { try result.requireAccepted(expectedStdout: standardOutput(.trailing)) }
}
check("overflow caps retained stdout but drains to final stderr and exit without killing") {
    let result = try run(.overflow)
    try expect(result.outputExceeded && result.stdout.count == 4096 && result.stderr == Data("FINAL-CHILD-MARKER\n".utf8) && result.exitCode == 0,
               "Overflow did not remain bounded and drain to natural exit")
    try refusal(.notAuthorized) { try result.requireAccepted(expectedStdout: standardOutput(.overflow)) }
}
check("overflow retains actual nonzero exit and final marker") {
    let result = try run(.overflowNonzero)
    try expect(result.outputExceeded && result.stdout.count == 4096 && result.stderr == Data("FINAL-CHILD-MARKER\n".utf8) && result.exitCode == 7,
               "Overflow silently killed child or lost actual exit")
    try refusal(.notAuthorized) { try result.requireAccepted(expectedStdout: standardOutput(.overflowNonzero)) }
}
check("both streams drain concurrently with independent retained bounds") {
    let result = try run(.dualOverflow)
    try expect(result.outputExceeded && result.stdout.count == 4096 && result.stderr.count == 4096 && result.exitCode == 0,
               "Both streams did not drain through natural exit with bounded retention")
    try refusal(.notAuthorized) { try result.requireAccepted(expectedStdout: standardOutput(.dualOverflow)) }
}
check("an oversized capture limit refuses before dispatch") {
    let token = try SyntheticChildInvocation.selfCheck(.clean)
    try refusal(.invalidArguments) { _ = try SyntheticChildProcess.capture(token, outputLimit: 16_777_216) }
}
print("Disposable process acceptance: \(cases) cases, \(failures) failures. Self-check child only; no native scope, host app, guest action or installation authority.")
exit(failures == 0 ? 0 : 1)
