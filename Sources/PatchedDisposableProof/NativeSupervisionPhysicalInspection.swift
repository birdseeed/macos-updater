import Foundation
import Darwin

// INTERNAL DATA ONLY. These observations never admit a context or grant an action.
struct NativeSupervisionControlObservation: Sendable {
    let device: UInt64
    let inode: UInt64
    let uid: UInt32
    let bytes: Data
}
struct NativeSupervisionStopObservation: Sendable {
    let reader: NativeSupervisionPipeSnapshot
    let writer: NativeSupervisionPipeSnapshot
}
enum NativeSupervisionPhysicalInspection {
    static func controlFile(parent: HeldDirectory, name: String, inheritedFD: Int32,
                            expectedBytes: Data) throws -> NativeSupervisionControlObservation {
        do {
            guard try components(name).count == 1, inheritedFD >= 0,
                  (1...4096).contains(expectedBytes.count) else { throw DisposableFailure.notAuthorized }
            try parent.confirm(); try parent.owned(privateMode: true); try requirePrivateACL(parent)
            let parentBefore = try parent.status()
            guard let named = try parent.named(name) else { throw DisposableFailure.notAuthorized }
            try validateControl(named)
            // Validate the supplied descriptor before opening anything, so a closed
            // numeric FD cannot be accidentally revived by our own openat.
            var inherited = stat()
            let inheritedFlags = fcntl(inheritedFD, F_GETFL)
            guard fstat(inheritedFD, &inherited) == 0, stable(named, inherited),
                  inheritedFlags >= 0, inheritedFlags & O_ACCMODE == O_RDONLY else {
                throw DisposableFailure.notAuthorized
            }
            try noACL(inheritedFD)
            let opened = openat(parent.fd, name, regularFlags)
            guard opened >= 0 else { throw DisposableFailure.notAuthorized }
            defer { _ = close(opened) }
            let openedFlags = fcntl(opened, F_GETFL)
            guard opened != inheritedFD, openedFlags >= 0 else { throw DisposableFailure.notAuthorized }

            func confirm() throws {
                try parent.confirm(); try parent.owned(privateMode: true); try requirePrivateACL(parent)
                guard stable(parentBefore, try parent.status()),
                      let currentName = try parent.named(name), stable(named, currentName) else {
                    throw DisposableFailure.notAuthorized
                }
                for (fd, originalFlags) in [(opened, openedFlags), (inheritedFD, inheritedFlags)] {
                    var current = stat()
                    let flags = fcntl(fd, F_GETFL)
                    guard fstat(fd, &current) == 0, stable(named, current),
                          flags == originalFlags, flags & O_ACCMODE == O_RDONLY else {
                        throw DisposableFailure.notAuthorized
                    }
                    try validateControl(current); try noACL(fd)
                }
            }
            try confirm()
            guard named.st_size == off_t(expectedBytes.count) else { throw DisposableFailure.notAuthorized }
            // Read through our own held descriptor. pread never moves the inherited offset.
            var buffer = [UInt8](repeating: 0, count: expectedBytes.count + 1)
            var count = 0
            while count < buffer.count {
                let read = buffer.withUnsafeMutableBytes { bytes in
                    pread(opened, bytes.baseAddress!.advanced(by: count), bytes.count - count, off_t(count))
                }
                if read < 0 && errno == EINTR { continue }
                guard read >= 0 else { throw DisposableFailure.notAuthorized }
                if read == 0 { break }
                count += read
            }
            try confirm()
            let bytes = Data(buffer.prefix(count))
            guard bytes == expectedBytes else { throw DisposableFailure.notAuthorized }
            return .init(device: identity(named).0, inode: named.st_ino, uid: named.st_uid, bytes: bytes)
        } catch { throw DisposableFailure.notAuthorized }
    }
    static func stopChannel(readerPID: Int32, readerFD: Int32,
                            writerFD: Int32) throws -> NativeSupervisionStopObservation {
        do {
            guard readerPID > 0, readerFD >= 0, writerFD >= 0 else { throw DisposableFailure.notAuthorized }
            let process = try NativeSupervisionKernel.process(pid: readerPID)
            guard process.uid == getuid(), process.realUID == getuid() else { throw DisposableFailure.notAuthorized }
            let reader = try NativeSupervisionKernel.pipe(pid: readerPID, fd: readerFD)
            let writer = try NativeSupervisionKernel.pipe(pid: getpid(), fd: writerFD)
            let flags = fcntl(writerFD, F_GETFL)
            var writerStat = stat()
            guard fstat(writerFD, &writerStat) == 0 else { throw DisposableFailure.notAuthorized }

            func confirm() throws {
                let currentProcess = try NativeSupervisionKernel.process(pid: readerPID)
                guard currentProcess.pid == process.pid, currentProcess.uid == process.uid,
                      currentProcess.realUID == process.realUID,
                      currentProcess.startSeconds == process.startSeconds,
                      currentProcess.startMicroseconds == process.startMicroseconds,
                      currentProcess.parentPID == process.parentPID,
                      currentProcess.processGroupID == process.processGroupID,
                      flags >= 0, flags & O_ACCMODE == O_WRONLY, flags & O_NONBLOCK != 0,
                      fcntl(writerFD, F_GETFL) == flags, fcntl(writerFD, 74) == 1,
                      writerStat.st_mode & S_IFMT == S_IFIFO, writerStat.st_uid == getuid(),
                      reader.uid == getuid(), writer.uid == getuid(),
                      reader.device == writer.device, writer.device == identity(writerStat).0,
                      writer.inode == writerStat.st_ino, writer.handle == writerStat.st_ino,
                      reader.handle != writer.handle, reader.peerHandle == writer.handle,
                      writer.peerHandle == reader.handle,
                      reader.openFlags & UInt32(FREAD | FWRITE) == UInt32(FREAD),
                      writer.openFlags & UInt32(FREAD | FWRITE) == UInt32(FWRITE) else {
                    throw DisposableFailure.notAuthorized
                }
                var currentWriter = stat()
                guard fstat(writerFD, &currentWriter) == 0, stable(writerStat, currentWriter),
                      samePipe(reader, try NativeSupervisionKernel.pipe(pid: readerPID, fd: readerFD)),
                      samePipe(writer, try NativeSupervisionKernel.pipe(pid: getpid(), fd: writerFD)) else {
                    throw DisposableFailure.notAuthorized
                }
                if readerPID == getpid() {
                    var readerStat = stat()
                    guard fstat(readerFD, &readerStat) == 0, readerStat.st_mode & S_IFMT == S_IFIFO,
                          readerStat.st_uid == getuid(), identity(readerStat).0 == reader.device,
                          readerStat.st_ino == reader.handle else { throw DisposableFailure.notAuthorized }
                }
            }
            try confirm(); try confirm()
            // These are endpoint observations, not proof of exclusive reader ownership.
            return .init(reader: reader, writer: writer)
        } catch { throw DisposableFailure.notAuthorized }
    }

    private static func validateControl(_ value: stat) throws {
        guard value.st_mode & S_IFMT == S_IFREG, permissions(value) == 0o600,
              value.st_uid == getuid(), value.st_nlink == 1,
              (1...4096).contains(value.st_size) else { throw DisposableFailure.notAuthorized }
    }

    private static func noACL(_ fd: Int32) throws {
        errno = 0
        guard let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) else {
            guard errno == ENOENT else { throw DisposableFailure.notAuthorized }; return
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_valid(acl) == 0 else { throw DisposableFailure.notAuthorized }
        var entry: acl_entry_t?
        errno = 0
        guard acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry) == -1,
              errno == EINVAL else { throw DisposableFailure.notAuthorized }
    }

    private static func samePipe(_ a: NativeSupervisionPipeSnapshot, _ b: NativeSupervisionPipeSnapshot) -> Bool {
        a.handle == b.handle && a.peerHandle == b.peerHandle && a.device == b.device &&
            a.inode == b.inode && a.uid == b.uid && a.openFlags == b.openFlags
    }
}
