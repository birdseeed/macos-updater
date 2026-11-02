import Foundation
import Darwin

// Data only. A decoded record never constructs or grants productive authority.
struct NativeSupervisionDescriptor: Sendable {
    let schemaVersion: UInt64
    let kind: String
    let targetID: String
    let runID: String
    let sourceRevision: String
    let nativeBinarySHA256: String
    let childBinarySHA256: String
    let nonce: String
    let clock: String
    let startedNanoseconds: UInt64
    let deadlineNanoseconds: UInt64
    let leaderPID: Int32
    let leaderStartSeconds: UInt64
    let leaderStartMicroseconds: UInt64
    let ownerPID: Int32
    let ownerStartSeconds: UInt64
    let ownerStartMicroseconds: UInt64
    let stopWriterDevice: UInt64
    let stopWriterInode: UInt64

    static func decode(_ data: Data, expectedTargetID: String, expectedRunID: String,
                       expectedSourceRevision: String, expectedNativeBinarySHA256: String,
                       expectedChildBinarySHA256: String) throws -> Self {
        // Foundation can canonicalise 1.0 and 1e0 to an integer NSNumber. Check
        // the original flat-schema lexemes before asking it for typed values.
        guard data.count <= 4096, integerLexemesOnly(data) else { throw DisposableFailure.notAuthorized }
        let object = try StrictObject.decode(data, maximum: 4096, failure: .notAuthorized)
        let keys: Set<String> = [
            "schemaVersion", "kind", "targetID", "runID", "sourceRevision",
            "nativeBinarySHA256", "childBinarySHA256", "nonce", "clock",
            "startedNanoseconds", "deadlineNanoseconds", "leaderPID", "leaderStartSeconds",
            "leaderStartMicroseconds", "ownerPID", "ownerStartSeconds", "ownerStartMicroseconds",
            "stopWriterDevice", "stopWriterInode"
        ]
        guard Set(object.keys) == keys,
              let schema = unsigned(object["schemaVersion"]), schema == 1,
              let kind = object["kind"] as? String, kind == "patched-owned-native-supervision-v1",
              let target = object["targetID"] as? String, target == expectedTargetID,
              let run = object["runID"] as? String, run == expectedRunID, validRun(run),
              let revision = object["sourceRevision"] as? String, revision == expectedSourceRevision,
              lowerHex(revision, count: 40),
              let nativeHash = object["nativeBinarySHA256"] as? String, nativeHash == expectedNativeBinarySHA256,
              validDigest(nativeHash),
              let childHash = object["childBinarySHA256"] as? String, childHash == expectedChildBinarySHA256,
              validDigest(childHash),
              let nonce = object["nonce"] as? String, validDigest(nonce),
              let clock = object["clock"] as? String, clock == "darwin-mach-absolute-ns-v1",
              let started = unsigned(object["startedNanoseconds"]), started > 0,
              let deadline = unsigned(object["deadlineNanoseconds"]), deadline > started,
              deadline - started <= 1_770_000_000_000,
              let leader = unsigned(object["leaderPID"]), (2...UInt64(Int32.max)).contains(leader),
              let owner = unsigned(object["ownerPID"]), (2...UInt64(Int32.max)).contains(owner), owner != leader,
              let leaderSeconds = unsigned(object["leaderStartSeconds"]), leaderSeconds > 0,
              let leaderMicros = unsigned(object["leaderStartMicroseconds"]), leaderMicros < 1_000_000,
              let ownerSeconds = unsigned(object["ownerStartSeconds"]), ownerSeconds > 0,
              let ownerMicros = unsigned(object["ownerStartMicroseconds"]), ownerMicros < 1_000_000,
              let device = unsigned(object["stopWriterDevice"]),
              let inode = unsigned(object["stopWriterInode"]), inode > 0 else {
            throw DisposableFailure.notAuthorized
        }
        return Self(schemaVersion: schema, kind: kind, targetID: target, runID: run,
                    sourceRevision: revision, nativeBinarySHA256: nativeHash, childBinarySHA256: childHash,
                    nonce: nonce, clock: clock, startedNanoseconds: started, deadlineNanoseconds: deadline,
                    leaderPID: Int32(leader), leaderStartSeconds: leaderSeconds, leaderStartMicroseconds: leaderMicros,
                    ownerPID: Int32(owner), ownerStartSeconds: ownerSeconds, ownerStartMicroseconds: ownerMicros,
                    stopWriterDevice: device, stopWriterInode: inode)
    }

    private static func lowerHex(_ text: String, count: Int) -> Bool {
        text.utf8.count == count && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// Strings retain their JSON escapes; every unquoted value in this schema
    /// must be an unsigned decimal integer. StrictObject checks the JSON grammar,
    /// duplicate decoded keys and trailing input; field checks enforce the schema.
    private static func integerLexemesOnly(_ data: Data) -> Bool {
        var inString = false, escaped = false
        for byte in data {
            if inString {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { inString = false }
            } else if byte == 34 {
                inString = true
            } else if !(48...57).contains(byte) && ![9, 10, 13, 32, 44, 58, 123, 125].contains(byte) {
                return false
            }
        }
        return !inString && !escaped
    }
}

// Read-only observations. No signalling, execution, stop notification or context factory.
struct NativeSupervisionPipeSnapshot: Sendable {
    let handle: UInt64
    let peerHandle: UInt64
    let device: UInt64
    let inode: UInt64
    let uid: UInt32
    let openFlags: UInt32
}
struct NativeSupervisionProcessSnapshot: Sendable {
    let pid: Int32
    let parentPID: Int32
    let processGroupID: Int32
    let uid: UInt32
    let realUID: UInt32
    let startSeconds: UInt64
    let startMicroseconds: UInt64
    let status: UInt32
}
enum NativeSupervisionKernel {
    static func process(pid: Int32) throws -> NativeSupervisionProcessSnapshot {
        guard pid > 0 else { throw DisposableFailure.notAuthorized }
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == size,
              info.pbi_pid == UInt32(pid),
              info.pbi_ppid <= UInt32(Int32.max), info.pbi_pgid > 0,
              info.pbi_pgid <= UInt32(Int32.max), info.pbi_start_tvsec > 0,
              info.pbi_start_tvusec < 1_000_000, info.pbi_status > 0 else {
            throw DisposableFailure.notAuthorized
        }
        return NativeSupervisionProcessSnapshot(pid: Int32(info.pbi_pid), parentPID: Int32(info.pbi_ppid),
            processGroupID: Int32(info.pbi_pgid), uid: info.pbi_uid, realUID: info.pbi_ruid,
            startSeconds: info.pbi_start_tvsec, startMicroseconds: info.pbi_start_tvusec,
            status: info.pbi_status)
    }
    static func pipe(pid: Int32, fd: Int32) throws -> NativeSupervisionPipeSnapshot {
        guard pid > 0, fd >= 0 else { throw DisposableFailure.notAuthorized }
        var info = pipe_fdinfo()
        let size = MemoryLayout<pipe_fdinfo>.size
        guard proc_pidfdinfo(pid, fd, PROC_PIDFDPIPEINFO, &info, Int32(size)) == size,
              info.pfi.fi_type == Int32(PROX_FDTYPE_PIPE),
              UInt32(info.pipeinfo.pipe_stat.vst_mode) & UInt32(S_IFMT) == UInt32(S_IFIFO),
              info.pipeinfo.pipe_handle != 0, info.pipeinfo.pipe_peerhandle != 0,
              info.pipeinfo.pipe_handle != info.pipeinfo.pipe_peerhandle else {
            throw DisposableFailure.notAuthorized
        }
        let access = info.pfi.fi_openflags & UInt32(FREAD | FWRITE)
        guard access == UInt32(FREAD) || access == UInt32(FWRITE) else {
            throw DisposableFailure.notAuthorized
        }
        // Darwin's pipe_stat.vst_ino is not the endpoint's fstat inode. The
        // qualified endpoint identity is pipe_handle; the peer has its own handle.
        // Neither endpoint observation establishes exclusive ownership or readers.
        return NativeSupervisionPipeSnapshot(handle: info.pipeinfo.pipe_handle,
            peerHandle: info.pipeinfo.pipe_peerhandle, device: UInt64(info.pipeinfo.pipe_stat.vst_dev),
            inode: info.pipeinfo.pipe_handle, uid: info.pipeinfo.pipe_stat.vst_uid,
            openFlags: info.pfi.fi_openflags)
    }
    static func nowNanoseconds() throws -> UInt64 {
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS,
              timebase.numer > 0, timebase.denom > 0 else { throw DisposableFailure.notAuthorized }
        let product = mach_absolute_time().multipliedFullWidth(by: UInt64(timebase.numer))
        let divisor = UInt64(timebase.denom)
        // dividingFullWidth traps if its quotient cannot fit. Preserve the full
        // product so a representable result is not rejected by intermediate overflow.
        guard product.high < divisor else { throw DisposableFailure.notAuthorized }
        let nanoseconds = divisor.dividingFullWidth(product).quotient
        guard nanoseconds > 0 else { throw DisposableFailure.notAuthorized }
        return nanoseconds
    }
}
