import Foundation
import Darwin

/// Closed synthetic modes for this check executable only. There is no supplied
/// executable, shell, environment, arbitrary argument or productive command.
@_spi(Testing) public enum SyntheticChildMode: String, CaseIterable, Sendable {
    case clean, delayed, nonzero, trailing, overflow, overflowNonzero, dualOverflow
}

enum InstalledChildOrigin { case syntheticCheck, nativeScope }
struct InstalledChildInvocation {
    let executable: String
    let arguments: [String]
    let origin: InstalledChildOrigin
    let profile: DisposableTargetProfile
    init(executable: String, arguments: [String], origin: InstalledChildOrigin, profile: DisposableTargetProfile = .legacy) {
        self.executable = executable; self.arguments = arguments; self.origin = origin; self.profile = profile
    }
}

/// Output-only test token. A native scope cannot adopt it or obtain its own
/// opaque NativeInstalledChildCommand from it.
@_spi(Testing) public final class SyntheticChildInvocation {
    public let executable: String
    public let arguments: [String]
    fileprivate let invocation: InstalledChildInvocation
    private init(executable: String, mode: SyntheticChildMode) {
        self.executable = executable; arguments = ["--synthetic-child", mode.rawValue]
        invocation = .init(executable: executable, arguments: arguments, origin: .syntheticCheck)
    }
    public static func selfCheck(_ mode: SyntheticChildMode) throws -> SyntheticChildInvocation {
        let executable = try kernelExecutable(), names = try components(executable, absolute: true)
        guard names.last == "patched-disposable-process-checks", names.contains(".build") else {
            throw DisposableFailure.notAuthorized
        }
        return SyntheticChildInvocation(executable: executable, mode: mode)
    }
}

/// Raw completion is synthetic-only. Overflow is observed while continuing to
/// drain both streams and wait for actual exit; it never authorises termination.
@_spi(Testing) public struct SyntheticChildCompletion {
    public let stdout: Data
    public let stderr: Data
    public let exitCode: Int32
    public let outputExceeded: Bool
    public let childExited: Bool
    public let executable: String
    public let arguments: [String]
    let exitedNormally: Bool
    let streamsComplete: Bool
    let evidenceRecorded: Bool
    let evidenceFailure: String?
    // No public/SPI constructor or decoded-result entry point.
    internal init(stdout: Data, stderr: Data, exitCode: Int32, outputExceeded: Bool,
                  childExited: Bool, executable: String, arguments: [String],
                  exitedNormally: Bool, streamsComplete: Bool, evidenceRecorded: Bool = true, evidenceFailure: String? = nil) {
        self.stdout = stdout; self.stderr = stderr; self.exitCode = exitCode
        self.outputExceeded = outputExceeded; self.childExited = childExited
        self.executable = executable; self.arguments = arguments
        self.exitedNormally = exitedNormally; self.streamsComplete = streamsComplete
        self.evidenceRecorded = evidenceRecorded
        self.evidenceFailure = evidenceFailure
    }
    public func requireAccepted(expectedStdout: Data) throws {
        guard childExited, exitedNormally, streamsComplete, evidenceRecorded, exitCode == 0, !outputExceeded,
              stdout == expectedStdout else { throw DisposableFailure.notAuthorized }
    }
}

/// Each drain owns its reader and state on one worker. The calling thread reads
/// the result only after DispatchGroup.wait establishes completion. This class
/// is not a general shared mutable buffer or a productive observation issuer.
private final class InstalledPipeDrain: @unchecked Sendable {
    let reader: FileHandle
    let limit: Int
    private(set) var bytes = Data()
    private(set) var exceeded = false
    private(set) var complete = false
    init(reader: FileHandle, limit: Int) { self.reader = reader; self.limit = limit }
    func drain() {
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(reader.fileDescriptor, &buffer, buffer.count)
            if count == 0 { complete = true; return }
            if count < 0 {
                if errno == EINTR { continue }
                return // Refuse after child exit; never signal it on a read failure.
            }
            let remaining = limit - bytes.count
            if count > remaining { exceeded = true }
            if remaining > 0 { bytes.append(contentsOf: buffer.prefix(min(count, remaining))) }
            // Keep draining even when no more bytes can be retained.
        }
    }
}

/// Shared bounded capture mechanics. Productive dispatch remains refusing until
/// its own physical scope/lease exists. Overflow and elapsed time never cause a
/// signal: callers retain their operation lease while waiting for actual exit.
enum InstalledChildRunner {
    static func capture(_ invocation: InstalledChildInvocation, outputLimit: Int,
                        onSpawn: ((Int32) throws -> Void)? = nil) throws -> SyntheticChildCompletion {
        guard (1...8_388_608).contains(outputLimit) else { throw DisposableFailure.invalidArguments }
        // No caller-supplied path/argv can cross the current synthetic boundary.
        // Future native dispatch must enter through its separately guarded path.
        let current = try kernelExecutable(), names = try components(current, absolute: true)
        if invocation.origin == .syntheticCheck {
            guard invocation.executable == current,
              names.last == "patched-disposable-process-checks", names.contains(".build"),
              invocation.arguments.count == 2, invocation.arguments[0] == "--synthetic-child",
              SyntheticChildMode(rawValue: invocation.arguments[1]) != nil else { throw DisposableFailure.notAuthorized }
        } else {
            _ = try GuestGuard.observe(profile: invocation.profile)
            let request = try DisposableArguments.parse(invocation.arguments)
            guard request.profile == invocation.profile,
                  current == invocation.profile.runParent + "/.native-bootstrap-" + request.runID +
                    "/PatchedDisposableClientApp.app/Contents/MacOS/PatchedDisposableClientApp",
                  invocation.executable == invocation.profile.runParent + "/.bootstrap-" + request.runID + "/patched-disposable-proof" else {
                throw DisposableFailure.notAuthorized
            }
        }
        let output = Pipe(), errors = Pipe(), process = Process()
        let out = InstalledPipeDrain(reader: output.fileHandleForReading, limit: outputLimit)
        let err = InstalledPipeDrain(reader: errors.fileHandleForReading, limit: outputLimit)
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output; process.standardError = errors
        // The self-check needs no inherited DYLD, shell or user configuration.
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C"]
        if invocation.origin == .nativeScope {
            process.environment?["HOME"] = invocation.profile.guestHome
            process.environment?["USER"] = invocation.profile.guestUser
        }
        do { try process.run() } catch { throw DisposableFailure.notAuthorized }
        // Close only the parent's duplicate writers, so EOF reflects the child.
        try? output.fileHandleForWriting.close(); try? errors.fileHandleForWriting.close()
        let drains = DispatchGroup()
        drains.enter(); DispatchQueue.global().async { out.drain(); drains.leave() }
        drains.enter(); DispatchQueue.global().async { err.drain(); drains.leave() }
        var evidenceRecorded = true
        var evidenceFailure: String?
        // Callback failure cannot abandon a running child or its drainers.
        do { try onSpawn?(process.processIdentifier) } catch {
            evidenceRecorded = false; evidenceFailure = (error as? DisposableFailure)?.rawValue ?? "persistenceFailed"
        }
        process.waitUntilExit()
        drains.wait()
        try? output.fileHandleForReading.close(); try? errors.fileHandleForReading.close()
        return SyntheticChildCompletion(stdout: out.bytes, stderr: err.bytes, exitCode: process.terminationStatus,
            outputExceeded: out.exceeded || err.exceeded, childExited: !process.isRunning,
            executable: invocation.executable, arguments: invocation.arguments,
            exitedNormally: process.terminationReason == .exit, streamsComplete: out.complete && err.complete,
            evidenceRecorded: evidenceRecorded, evidenceFailure: evidenceFailure)
    }
    static func productiveDispatch(_ invocation: InstalledChildInvocation) throws {
        guard invocation.origin == .nativeScope else { throw DisposableFailure.notAuthorized }
        throw DisposableFailure.notImplemented
    }
}

@_spi(Testing) public enum SyntheticChildProcess {
    public static func capture(_ invocation: SyntheticChildInvocation, outputLimit: Int = 4096) throws -> SyntheticChildCompletion {
        try InstalledChildRunner.capture(invocation.invocation, outputLimit: outputLimit)
    }
    /// Exercises the shared productive-origin boundary without exposing an
    /// arbitrary executor or minting a productive command/capability.
    public static func requestProductiveDispatch(_ invocation: SyntheticChildInvocation) throws {
        try InstalledChildRunner.productiveDispatch(invocation.invocation)
    }
}
