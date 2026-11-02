import Foundation

// PURE UNIT preparation only. These internal observations cannot issue physical
// authority. The real adapter must independently retain the authenticated
// supervisor identity, ancestry, owner, start identity and run-root binding.
// Integer PID/PGID equality and supplied test facts are never that binding.
struct OwnedProcessAdmissionFacts {
    let callerPID: Int32
    let callerParentPID: Int32
    let callerPGID: Int32
    let supervisorPID: Int32
    let supervisorPGID: Int32
    let verifiedContextBinding: Bool
    let leaderAliveUnreaped: Bool
    let exclusiveReaper: Bool
    let sigchldDefault: Bool
    let noChildWait: Bool
    let sigactionQuerySucceeded: Bool
    let deadlineNanoseconds: UInt64
    let nowNanoseconds: UInt64
}

struct OwnedProcessSpawnObservation {
    let pid: Int32
    let pgid: Int32
}

enum OwnedProcessEvent {
    case stdout(Data), stderr(Data)
    // These events describe actual reap observations, never requested signals.
    case exit(Int32), signal(Int32)
    case stdoutEOF, stderrEOF, readFailure
    case clock(UInt64)
    case evidenceFailure
}

// No signal, arbitrary executable, argv, environment or group operation exists
// on this seam. The test adapter supplies only closed in-memory observations.
// Productive adapters must be private and physically guarded independently.
protocol OwnedProcessSystem: AnyObject {
    func admission() throws -> OwnedProcessAdmissionFacts
    func spawnInInheritedGroup() throws -> OwnedProcessSpawnObservation
    func nextObservation() throws -> OwnedProcessEvent
    func closeCaptureDescriptors()
}

struct OwnedProcessLifecycleResult {
    let stdout: Data
    let stderr: Data
    let exitCode: Int32?
    let signal: Int32?
    let childExited: Bool
    let streamsComplete: Bool
    let outputExceeded: Bool
    let timedOut: Bool
    // Capture acceptance only. Never installed acceptance or physical authority.
    let accepted: Bool
    let originalDeadline: UInt64
    // False while actual child death is absent, including timeout/incomplete I/O.
    let operationLeaseMayRelease: Bool
}

enum OwnedProcessLifecycle {
    static func capture(system: any OwnedProcessSystem, outputLimit: Int, combinedOutputLimit: Int? = nil) throws -> OwnedProcessLifecycleResult {
        let maximumOutput = 8_388_608
        guard (1...maximumOutput).contains(outputLimit),
              combinedOutputLimit.map({ (1...maximumOutput).contains($0) }) ?? true else {
            throw DisposableFailure.invalidArguments
        }
        let facts = try system.admission()
        guard facts.verifiedContextBinding,
              facts.callerPID > 0, facts.callerParentPID > 0,
              facts.callerPGID > 0, facts.supervisorPID > 0,
              facts.supervisorPGID == facts.supervisorPID,
              facts.callerPGID == facts.supervisorPGID,
              facts.callerPID != facts.supervisorPID,
              facts.leaderAliveUnreaped, facts.exclusiveReaper,
              facts.sigchldDefault, !facts.noChildWait,
              facts.sigactionQuerySucceeded,
              facts.nowNanoseconds < facts.deadlineNanoseconds else {
            throw DisposableFailure.notAuthorized
        }

        // Admission transfers capture ownership. Cleanup runs once even when
        // spawning throws; a returned lease never asserts an unobserved death.
        defer { system.closeCaptureDescriptors() }
        let spawned = try system.spawnInInheritedGroup()
        var failed = spawned.pid <= 0 || spawned.pid == facts.supervisorPID
            || spawned.pid == facts.callerPID || spawned.pgid != facts.supervisorPGID
        var stdout = Data(), stderr = Data()
        var stdoutClosed = false, stderrClosed = false
        var readFailed = false, outputExceeded = false, timedOut = false
        var exitCode: Int32?, terminationSignal: Int32?
        var childExited = false
        var lastClock = facts.nowNanoseconds

        // Retain only the prefix permitted by both budgets, without accumulating
        // an unbounded byte counter. Overflow is sticky while draining continues.
        func retain(_ bytes: Data, in stream: inout Data, otherCount: Int) {
            let streamRoom = outputLimit - stream.count
            let combinedRoom = combinedOutputLimit.map { $0 - stream.count - otherCount }
                ?? streamRoom
            let count = min(bytes.count, min(streamRoom, combinedRoom))
            if count < bytes.count { outputExceeded = true }
            stream.append(contentsOf: bytes.prefix(count))
        }

        while !(childExited && stdoutClosed && stderrClosed) {
            let event: OwnedProcessEvent
            do {
                event = try system.nextObservation()
            } catch {
                // Exhaustion or I/O failure is not EOF, nor a reap receipt.
                failed = true
                break
            }
            switch event {
            case .stdout(let bytes):
                if stdoutClosed { failed = true }
                retain(bytes, in: &stdout, otherCount: stderr.count)
            case .stderr(let bytes):
                if stderrClosed { failed = true }
                retain(bytes, in: &stderr, otherCount: stdout.count)
            case .stdoutEOF:
                stdoutClosed = true
            case .stderrEOF:
                stderrClosed = true
            case .readFailure:
                readFailed = true
                failed = true
            case .evidenceFailure:
                failed = true
            case .clock(let now):
                if now < lastClock { failed = true }
                lastClock = max(lastClock, now)
                if now >= facts.deadlineNanoseconds { timedOut = true }
            case .exit(let code):
                if code < 0 {
                    failed = true
                } else if childExited {
                    if exitCode != code || terminationSignal != nil { failed = true }
                } else {
                    exitCode = code
                    childExited = true
                }
            case .signal(let number):
                if number <= 0 {
                    failed = true
                } else if childExited {
                    if terminationSignal != number || exitCode != nil { failed = true }
                } else {
                    terminationSignal = number
                    childExited = true
                }
            }
        }

        let streamsComplete = stdoutClosed && stderrClosed && !readFailed
        return OwnedProcessLifecycleResult(
            stdout: stdout, stderr: stderr, exitCode: exitCode,
            signal: terminationSignal, childExited: childExited,
            streamsComplete: streamsComplete, outputExceeded: outputExceeded,
            timedOut: timedOut,
            accepted: childExited && exitCode == 0 && terminationSignal == nil
                && streamsComplete && !failed && !outputExceeded && !timedOut,
            originalDeadline: facts.deadlineNanoseconds,
            operationLeaseMayRelease: childExited
        )
    }
}
