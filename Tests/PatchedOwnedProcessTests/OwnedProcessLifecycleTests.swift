import Foundation
import Testing
@testable import PatchedDisposableProof

// PURE UNIT ONLY: no process, signal, guest, native app or productive authority.
// Scripts supply observations to the same internal lifecycle intended for the
// physical adapter. They contain no per-scenario expected-output implementation.
private enum ScriptExhausted: Error { case noFurtherObservation }
private final class ScriptedSystem: OwnedProcessSystem {
    let facts: OwnedProcessAdmissionFacts
    let spawned: OwnedProcessSpawnObservation
    var events: [OwnedProcessEvent]
    var failSpawn = false
    private(set) var spawnCount = 0
    private(set) var closeCount = 0
    private(set) var eventsConsumed = 0
    init(facts: OwnedProcessAdmissionFacts, group: Int32 = 410, events: [OwnedProcessEvent]) {
        self.facts = facts; spawned = .init(pid: 430, pgid: group); self.events = events
    }
    func admission() throws -> OwnedProcessAdmissionFacts { facts }
    func spawnInInheritedGroup() throws -> OwnedProcessSpawnObservation {
        spawnCount += 1
        if failSpawn { throw DisposableFailure.commandFailed }
        return spawned
    }
    func nextObservation() throws -> OwnedProcessEvent {
        guard !events.isEmpty else { throw ScriptExhausted.noFurtherObservation }
        eventsConsumed += 1; return events.removeFirst()
    }
    func closeCaptureDescriptors() { closeCount += 1 }
}

@Suite("OwnedProcessLifecycleTests")
struct OwnedProcessLifecycleTests {
    private let deadline: UInt64 = 1_800_000_000_000
    private func facts(group: Int32 = 410, binding: Bool = true, leader: Bool = true,
                       exclusive: Bool = true, sigchld: Bool = true, noWait: Bool = false,
                       queried: Bool = true, now: UInt64 = 100) -> OwnedProcessAdmissionFacts {
        // The caller's parent is deliberately not the supervisor. A nested proof
        // child must not be rejected merely for lacking direct-child ancestry.
        .init(callerPID: 420, callerParentPID: 415, callerPGID: group,
              supervisorPID: 410, supervisorPGID: 410, verifiedContextBinding: binding,
              leaderAliveUnreaped: leader, exclusiveReaper: exclusive,
              sigchldDefault: sigchld, noChildWait: noWait, sigactionQuerySucceeded: queried,
              deadlineNanoseconds: deadline, nowNanoseconds: now)
    }
    private func clean(_ facts: OwnedProcessAdmissionFacts? = nil) -> ScriptedSystem {
        ScriptedSystem(facts: facts ?? self.facts(), events: [.stdout(Data("ok".utf8)), .stderr(Data("final".utf8)), .exit(0), .stdoutEOF, .stderrEOF])
    }
    private func capture(_ system: ScriptedSystem, limit: Int = 4096) throws -> OwnedProcessLifecycleResult {
        try OwnedProcessLifecycle.capture(system: system, outputLimit: limit)
    }
    private func refusesBeforeSpawn(_ system: ScriptedSystem, limit: Int = 4096,
                                    expected: DisposableFailure = .notAuthorized,
                                    file: StaticString = #filePath, line: UInt = #line) {
        do { _ = try capture(system, limit: limit); Issue.record(Comment(rawValue: "PURE UNIT admission accepted invalid observations"), sourceLocation: SourceLocation(fileID: String(describing: file), filePath: String(describing: file), line: Int(line), column: 1)) }
        catch let failure as DisposableFailure { #expect(failure == expected, Comment(rawValue: "PURE UNIT admission must discriminate its refusal"), sourceLocation: SourceLocation(fileID: String(describing: file), filePath: String(describing: file), line: Int(line), column: 1)) }
        catch { Issue.record(Comment(rawValue: "Unexpected admission failure: \(error)"), sourceLocation: SourceLocation(fileID: String(describing: file), filePath: String(describing: file), line: Int(line), column: 1)) }
        #expect(system.spawnCount == 0, Comment(rawValue: "Refusal must precede dispatch"), sourceLocation: SourceLocation(fileID: String(describing: file), filePath: String(describing: file), line: Int(line), column: 1))
    }
    @Test
    func testProofChildInheritsVerifiedGroupAndActualExit() throws {
        let system = clean(), result = try capture(system)
        #expect(system.spawnCount == 1); #expect(result.accepted)
        #expect(result.childExited); #expect(result.streamsComplete)
        #expect(result.stdout == Data("ok".utf8)); #expect(result.stderr == Data("final".utf8))
        #expect(result.exitCode == 0); #expect(result.signal == nil)
        #expect(result.originalDeadline == deadline); #expect(result.operationLeaseMayRelease)
    }
    @Test
    func testSpawnFailureClosesDescriptorsWithoutInventingChildCompletion() {
        let system = clean(); system.failSpawn = true
        do { _ = try capture(system); Issue.record(Comment(rawValue: "Failed spawn returned a fabricated completion")) }
        catch let failure as DisposableFailure { #expect(failure == .commandFailed) }
        catch { Issue.record(Comment(rawValue: "Unexpected spawn failure: \(error)")) }
        #expect(system.spawnCount == 1); #expect(system.eventsConsumed == 0)
        #expect(system.closeCount == 1)
    }
    @Test
    func testActionsAndRelaunchCannotResetSequenceDeadline() throws {
        for now in [UInt64(100), 900_000_000_000, 1_799_000_000_000] {
            let result = try capture(clean(facts(now: now)))
            #expect(result.originalDeadline == deadline, Comment(rawValue: "Action/relaunch reset original absolute deadline"))
            #expect(result.accepted)
        }
    }
    @Test
    func testWrongCallerGroupRefusesBeforeSpawn() { refusesBeforeSpawn(clean(facts(group: 999))) }
    @Test
    func testUnboundSupervisorFactsRefuseBeforeSpawn() { refusesBeforeSpawn(clean(facts(binding: false))) }
    @Test
    func testReapedLeaderRefusesBeforeSpawn() { refusesBeforeSpawn(clean(facts(leader: false))) }
    @Test
    func testConcurrentReaperRefusesBeforeSpawn() { refusesBeforeSpawn(clean(facts(exclusive: false))) }
    @Test
    func testNonDefaultSIGCHLDRefusesBeforeSpawn() { refusesBeforeSpawn(clean(facts(sigchld: false))) }
    @Test
    func testNoChildWaitRefusesBeforeSpawn() { refusesBeforeSpawn(clean(facts(noWait: true))) }
    @Test
    func testSigactionQueryFailureRefusesBeforeSpawn() { refusesBeforeSpawn(clean(facts(queried: false))) }
    @Test
    func testExpiredAbsoluteDeadlineRefusesBeforeSpawn() { refusesBeforeSpawn(clean(facts(now: deadline))) }
    @Test
    func testInvalidOutputLimitRefusesBeforeSpawn() { refusesBeforeSpawn(clean(), limit: 0, expected: .invalidArguments) }
    @Test
    func testPostSpawnWrongGroupCannotAcceptOrReleaseLiveLease() throws {
        let system = ScriptedSystem(facts: facts(), group: 999, events: [])
        let result = try capture(system)
        #expect(system.spawnCount == 1); #expect(!(result.accepted))
        #expect(!(result.childExited)); #expect(!(result.operationLeaseMayRelease))
    }
    @Test
    func testDeadlineCannotBecomeSuccessAfterActualZeroExit() throws {
        let system = ScriptedSystem(facts: facts(), events: [.clock(deadline), .exit(0), .stdoutEOF, .stderrEOF])
        let result = try capture(system)
        #expect(result.timedOut); #expect(!(result.accepted))
        #expect(result.childExited); #expect(result.exitCode == 0)
        #expect(result.originalDeadline == deadline)
    }
    @Test
    func testActualSignalIsPreservedSeparatelyFromShellExit137() throws {
        let system = ScriptedSystem(facts: facts(), events: [.signal(9), .stdoutEOF, .stderrEOF])
        let result = try capture(system)
        #expect(result.signal == 9); #expect(result.exitCode == nil)
        #expect(result.childExited); #expect(!(result.accepted))
    }
    @Test
    func testIncompleteDrainWithNoDeathRetainsOperationLease() throws {
        let system = ScriptedSystem(facts: facts(), events: [.stdout(Data("partial".utf8)), .clock(deadline), .readFailure])
        let result = try capture(system)
        #expect(result.timedOut); #expect(!(result.childExited))
        #expect(!(result.streamsComplete)); #expect(!(result.accepted))
        #expect(!(result.operationLeaseMayRelease)); #expect(result.stdout == Data("partial".utf8))
    }
    @Test
    func testDualOverflowDrainsToActualNonzeroExit() throws {
        let system = ScriptedSystem(facts: facts(), events: [.stdout(Data(repeating: 65, count: 32)), .stderr(Data(repeating: 66, count: 32)), .exit(7), .stdoutEOF, .stderrEOF])
        let result = try capture(system, limit: 8)
        #expect(result.stdout == Data(repeating: 65, count: 8)); #expect(result.stderr == Data(repeating: 66, count: 8))
        #expect(result.outputExceeded); #expect(result.streamsComplete)
        #expect(result.childExited); #expect(result.exitCode == 7); #expect(result.signal == nil)
        #expect(!(result.accepted)); #expect(system.eventsConsumed == 5)
    }
    @Test
    func testEvidenceFailureStillObservesActualDeathAndFinalBytes() throws {
        let system = ScriptedSystem(facts: facts(), events: [.evidenceFailure, .stderr(Data("final".utf8)), .exit(0), .stdoutEOF, .stderrEOF])
        let result = try capture(system)
        #expect(!(result.accepted)); #expect(result.childExited); #expect(result.streamsComplete)
        #expect(result.stderr == Data("final".utf8)); #expect(result.exitCode == 0)
        #expect(system.eventsConsumed == 5); #expect(system.closeCount == 1)
    }
    // PURE UNIT: NativeCommands preserves its original combined stdout/stderr
    // budget. Nil retains the existing separate-stream capture contract.
    @Test
    func testCombinedOutputLimitRetainsSixThenTwoAndDrainsActualExit() throws {
        let system = ScriptedSystem(facts: facts(), events: [.stdout(Data(repeating: 65, count: 6)), .stderr(Data(repeating: 66, count: 6)), .exit(7), .stdoutEOF, .stderrEOF])
        let result = try OwnedProcessLifecycle.capture(system: system, outputLimit: 8, combinedOutputLimit: 8)
        #expect(result.stdout == Data(repeating: 65, count: 6))
        #expect(result.stderr == Data(repeating: 66, count: 2))
        #expect(result.stdout.count + result.stderr.count == 8)
        #expect(result.stdout.count <= 8); #expect(result.stderr.count <= 8)
        #expect(result.outputExceeded); #expect(result.streamsComplete)
        #expect(result.childExited); #expect(result.exitCode == 7); #expect(result.signal == nil)
        #expect(!(result.accepted)); #expect(system.eventsConsumed == 5)
        #expect(system.spawnCount == 1); #expect(system.closeCount == 1)
    }
    @Test
    func testZeroCombinedOutputLimitRefusesBeforeSpawn() {
        let system = clean()
        do {
            _ = try OwnedProcessLifecycle.capture(system: system, outputLimit: 8, combinedOutputLimit: 0)
            Issue.record(Comment(rawValue: "Zero combined output limit accepted"))
        } catch let failure as DisposableFailure {
            #expect(failure == .invalidArguments)
        } catch {
            Issue.record(Comment(rawValue: "Unexpected combined limit refusal: \(error)"))
        }
        #expect(system.spawnCount == 0)
    }
}
