import Foundation
import Darwin

// A separate process group lets timeout/output limits terminate descendants that
// inherited the pipes, even if the original child has already exited.
func runBounded(executable: String, arguments: [String], limits: InspectionLimits,
                imageDescriptor: Int32? = nil) throws -> CommandResult {
    guard executable.hasPrefix("/"), !executable.contains("\0"), arguments.allSatisfy({ !$0.contains("\0") }),
          limits.commandSeconds.isFinite, limits.commandSeconds > 0, limits.commandSeconds <= 180,
          limits.outputBytes > 0, limits.outputBytes <= 1_048_576 else { throw InspectionFailure.invalidMetadata }
    // Keep every owned spawn source away from stdio and the fixed image slot.
    // dup2 in the child alone removes CLOEXEC; parent flags are never cleared.
    var inherited: Int32 = -1
    if let imageDescriptor {
        let flags = fcntl(imageDescriptor, F_GETFL)
        guard flags >= 0, flags & O_ACCMODE == O_RDONLY else { throw InspectionFailure.invalidMetadata }
        _ = try SafeFiles.regular(imageDescriptor)
        inherited = fcntl(imageDescriptor, F_DUPFD_CLOEXEC, 200)
        guard inherited >= 0 else { throw InspectionFailure.commandFailed }
    }
    defer { if inherited >= 0 { close(inherited) } }
    func disjointPipe() throws -> [Int32] {
        var raw: [Int32] = [-1, -1]
        guard pipe(&raw) == 0 else { throw InspectionFailure.commandFailed }
        defer { raw.forEach { close($0) } }
        let reader = fcntl(raw[0], F_DUPFD_CLOEXEC, 200)
        guard reader >= 0 else { throw InspectionFailure.commandFailed }
        let writer = fcntl(raw[1], F_DUPFD_CLOEXEC, 200)
        guard writer >= 0 else { close(reader); throw InspectionFailure.commandFailed }
        return [reader, writer]
    }
    var out = try disjointPipe()
    defer { for fd in out where fd >= 0 { close(fd) } }
    var err = try disjointPipe()
    defer { for fd in err where fd >= 0 { close(fd) } }
    for fd in out + err { guard fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 else { throw InspectionFailure.commandFailed } }
    var actions: posix_spawn_file_actions_t?; var attributes: posix_spawnattr_t?
    guard posix_spawn_file_actions_init(&actions) == 0 else { throw InspectionFailure.commandFailed }
    defer { posix_spawn_file_actions_destroy(&actions) }
    guard posix_spawnattr_init(&attributes) == 0 else { throw InspectionFailure.commandFailed }
    defer { posix_spawnattr_destroy(&attributes) }
    guard posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0,
          posix_spawn_file_actions_adddup2(&actions, out[1], STDOUT_FILENO) == 0,
          posix_spawn_file_actions_adddup2(&actions, err[1], STDERR_FILENO) == 0,
          // Darwin sys/spawn.h documents CLOEXEC_DEFAULT (0x4000): only
          // descriptors named by explicit spawn actions survive, including a
          // caller's unrelated descriptors that lack FD_CLOEXEC in the parent.
          posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)) == 0,
          posix_spawnattr_setpgroup(&attributes, 0) == 0 else { throw InspectionFailure.commandFailed }
    for fd in out + err { guard posix_spawn_file_actions_addclose(&actions, fd) == 0 else { throw InspectionFailure.commandFailed } }
    if inherited >= 0 {
        guard posix_spawn_file_actions_adddup2(&actions, inherited, VerifiedImage.childDescriptor) == 0,
              posix_spawn_file_actions_addclose(&actions, inherited) == 0 else { throw InspectionFailure.commandFailed }
    }
    let argv = ([executable] + arguments).map { strdup($0) } + [nil]
    let environment: [String] = ["PATH=/usr/bin:/bin:/usr/sbin:/sbin", "LANG=C", "LC_ALL=C"]
    let env = environment.map { strdup($0) } + [nil]
    defer { argv.forEach { free($0) }; env.forEach { free($0) } }
    var pid: pid_t = 0
    let started = timestamp(); let start = DispatchTime.now().uptimeNanoseconds
    let launched = argv.withUnsafeBufferPointer { a in env.withUnsafeBufferPointer { e in
        posix_spawn(&pid, executable, &actions, &attributes, a.baseAddress!, e.baseAddress!)
    } }
    guard launched == 0 else { throw InspectionFailure.commandFailed }
    close(out[1]); out[1] = -1; close(err[1]); err[1] = -1
    var ended = false; var status: Int32 = 0; var killed = false
    func terminateOwnedGroup() {
        // The unreaped leader reserves its PID/PGID. Consume this permission
        // once; after reaping, that number may already belong to another job.
        guard !ended && !killed else { return }
        killed = true
        kill(-pid, SIGKILL)
    }
    defer {
        if !ended {
            terminateOwnedGroup()
            while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
        }
    }
    guard fcntl(out[0], F_SETFL, O_NONBLOCK) == 0, fcntl(err[0], F_SETFL, O_NONBLOCK) == 0 else {
        throw InspectionFailure.commandFailed
    }
    var stdout = Data(); var stderr = Data(); var readFailed = false
    var eof = [false, false]; var timeout = false; var exceeded = false
    var buffer = [UInt8](repeating: 0, count: 16384)
    while !ended || !eof.allSatisfy({ $0 }) {
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
        if elapsed >= limits.commandSeconds { timeout = true }
        if timeout || exceeded { terminateOwnedGroup() }
        for (index, fd) in [out[0], err[0]].enumerated() where !eof[index] {
            // One chunk per pipe per iteration keeps a busy writer from starving
            // the deadline or the other stream.
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count == 0 { eof[index] = true }
            else if count > 0 {
                let remaining = max(0, limits.outputBytes - stdout.count - stderr.count)
                if count > remaining { exceeded = true }
                let bytes = buffer.prefix(min(count, remaining))
                if index == 0 { stdout.append(contentsOf: bytes) } else { stderr.append(contentsOf: bytes) }
            } else if errno != EAGAIN && errno != EINTR { terminateOwnedGroup(); eof[index] = true; readFailed = true }
        }
        // A leader that exits while descendants retain the pipes must remain
        // unreaped until group termination has consumed the signalling right.
        if !ended && (killed || eof.allSatisfy({ $0 })) {
            let waited = waitpid(pid, &status, WNOHANG)
            if waited == pid { ended = true }
            else if waited < 0 && errno != EINTR {
                // ECHILD means custody was lost; never signal a reusable number.
                if errno == ECHILD { ended = true }
                throw InspectionFailure.commandFailed
            }
        }
        // Descendants cannot hold the caller indefinitely after group termination.
        if killed && ended && elapsed >= limits.commandSeconds + 1 { break }
        if !ended || !eof.allSatisfy({ $0 }) { usleep(1000) }
    }
    guard !readFailed else { throw InspectionFailure.commandFailed }
    let exitCode: Int32 = status & 0x7f == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
    guard let outputText = String(data: stdout, encoding: .utf8), let errorText = String(data: stderr, encoding: .utf8) else {
        throw InspectionFailure.invalidMetadata
    }
    return CommandResult(executable: executable, arguments: arguments, exitCode: exitCode, stdout: outputText,
        stderr: errorText, timedOut: timeout, outputExceeded: exceeded, startedAt: started, finishedAt: timestamp())
}
