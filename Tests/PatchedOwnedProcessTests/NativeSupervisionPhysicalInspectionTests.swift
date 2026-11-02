import Foundation
import Testing
import Darwin
@testable import PatchedDisposableProof

// Physical controls use only owned scratch files and anonymous pipes.
@Suite("OwnedProcessLifecycleTests.NativeSupervisionPhysicalInspectionTests", .serialized)
struct NativeSupervisionPhysicalInspectionOwnedProcessLifecycleTests {
    private final class Files {
        let parent: HeldDirectory
        let base: HeldDirectory
        let leaf: String
        var fds: [Int32] = []
        private var cleaned = false
        let bytes: Data
        var inherited: Int32 { fds[0] }
        init(bytes: Data = Data("physical-control-v1\n".utf8)) throws {
            self.bytes = bytes
            // The test-only helper provisions/reuses the private base under the existing .build.
            let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            let build = try HeldDirectory.absolute(project.appendingPathComponent(".build").path)
            base = try OwnedPhysicalFixtureBase.open(in: build)
            leaf = "inspection-" + UUID().uuidString
            parent = try base.mkdir(leaf)
            var complete = false
            defer { if !complete { cleanup() } }
            try requirePrivateACL(parent)
            try create("control", bytes)
            let fd = openat(parent.fd, "control", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            try #require(fd >= 0); fds.append(fd); complete = true
        }
        func create(_ name: String, _ data: Data) throws {
            let fd = openat(parent.fd, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            try #require(fd >= 0); defer { _ = close(fd) }
            try #require(fchmod(fd, 0o600) == 0)
            try PhysicalIO.writeAll(fd, data)
        }
        func adopt(_ fd: Int32) throws -> Int32 { try #require(fd >= 0); fds.append(fd); return fd }
        deinit { cleanup() }
        private func cleanup() {
            guard !cleaned else { return }; cleaned = true
            for fd in fds where fd >= 0 { _ = close(fd) }
            // Fixed, bounded names only; no recursive removal or symlink traversal.
            for name in ["control", "saved", "other", "alias"] { _ = unlinkat(parent.fd, name, 0) }
            parent.closeDescriptor(); _ = unlinkat(base.fd, leaf, AT_REMOVEDIR)
            base.closeOwnedChain()
        }
    }
    private func noACL(_ fd: Int32) throws {
        errno = 0
        guard let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) else {
            try #require(errno == ENOENT); return
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        try #require(acl_valid(acl) == 0)
        var entry: acl_entry_t?
        errno = 0
        let result = acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry)
        try #require(result == -1 && errno == EINVAL)
    }
    private func controlBaseline(_ f: Files) throws {
        try f.parent.confirm(); try f.parent.owned(privateMode: true); try requirePrivateACL(f.parent)
        var s = stat(), named = stat()
        try #require(fstat(f.inherited, &s) == 0)
        try #require(fstatat(f.parent.fd, "control", &named, AT_SYMLINK_NOFOLLOW) == 0)
        try #require(s.st_mode & S_IFMT == S_IFREG); try #require(permissions(s) == 0o600)
        try #require(s.st_nlink == 1); try #require(s.st_uid == getuid()); try noACL(f.inherited)
        try #require(sameIdentity(s, named)); try #require(fcntl(f.inherited, F_GETFL) & O_ACCMODE == O_RDONLY)
        try #require(lseek(f.inherited, 2, SEEK_SET) == 2)
        let observed = try NativeSupervisionPhysicalInspection.controlFile(parent: f.parent, name: "control",
            inheritedFD: f.inherited, expectedBytes: f.bytes)
        #expect(observed.device == UInt64(UInt32(bitPattern: s.st_dev)))
        #expect(observed.inode == s.st_ino); #expect(observed.uid == s.st_uid); #expect(observed.bytes == f.bytes)
        #expect(lseek(f.inherited, 0, SEEK_CUR) == 2)
    }
    private func refuses(_ operation: () throws -> Void) {
        do { try operation(); Issue.record("Invalid physical binding accepted") }
        catch let error as DisposableFailure { #expect(error == .notAuthorized) }
        catch { Issue.record(Comment(rawValue: "Unexpected refusal: \(error)")) }
    }
    @Test func validControlPreservesIdentityBytesAndOffset() throws { try controlBaseline(Files()) }
    @Test(arguments: [1, 4096]) func validControlSizeBoundaries(_ count: Int) throws {
        try controlBaseline(Files(bytes: Data(repeating: 65, count: count)))
    }
    enum FileFault: CaseIterable { case mode, ownerReadOnlyMode, hardlink, symlink, replacement, otherFD, writableFD, oversized, empty, mismatch, changedBytes, closedFD, parentMode }
    @Test(arguments: FileFault.allCases)
    func controlRefusesOnePhysicalFault(_ fault: FileFault) throws {
        let f = try Files(); try controlBaseline(f) // An always-refusing inspector cannot pass a negative.
        var fd = f.inherited, expected = f.bytes
        switch fault {
        case .mode: try #require(fchmod(fd, 0o640) == 0)
        case .ownerReadOnlyMode: try #require(fchmod(fd, 0o400) == 0)
        case .hardlink: try #require(linkat(f.parent.fd, "control", f.parent.fd, "alias", 0) == 0)
        case .symlink:
            try #require(renameat(f.parent.fd, "control", f.parent.fd, "saved") == 0)
            try #require(symlinkat("saved", f.parent.fd, "control") == 0)
        case .replacement:
            try #require(renameat(f.parent.fd, "control", f.parent.fd, "saved") == 0)
            try f.create("control", f.bytes)
        case .otherFD:
            try f.create("other", f.bytes)
            fd = try f.adopt(openat(f.parent.fd, "other", O_RDONLY | O_NOFOLLOW | O_CLOEXEC))
        case .writableFD: fd = try f.adopt(openat(f.parent.fd, "control", O_RDWR | O_NOFOLLOW | O_CLOEXEC))
        case .oversized, .empty:
            let writable = try f.adopt(openat(f.parent.fd, "control", O_RDWR | O_NOFOLLOW | O_CLOEXEC))
            let count: Int
            switch fault { case .empty: count = 0; default: count = 4097 }
            try #require(ftruncate(writable, 0) == 0)
            let data = Data(repeating: 65, count: count); try PhysicalIO.writeAll(writable, data); expected = data
        case .mismatch: expected = Data("different".utf8)
        case .changedBytes:
            let writable = try f.adopt(openat(f.parent.fd, "control", O_RDWR | O_NOFOLLOW | O_CLOEXEC))
            try PhysicalIO.writeAll(writable, Data(repeating: 90, count: f.bytes.count))
        case .closedFD:
            let duplicate = dup(fd); try #require(duplicate >= 0); try #require(close(duplicate) == 0); fd = duplicate
        case .parentMode: try #require(fchmod(f.parent.fd, 0o750) == 0)
        }
        refuses { _ = try NativeSupervisionPhysicalInspection.controlFile(parent: f.parent, name: "control", inheritedFD: fd, expectedBytes: expected) }
    }
    private final class Pipe {
        var fds: [Int32] = [-1, -1]
        var reader: Int32 { fds[0] }; var writer: Int32 { fds[1] }
        init() throws {
            var complete = false
            defer { if !complete { cleanup() } }
            let result = fds.withUnsafeMutableBufferPointer { Darwin.pipe($0.baseAddress!) }
            try #require(result == 0)
            let flags = fcntl(writer, F_GETFL); try #require(flags >= 0)
            try #require(fcntl(writer, F_SETFL, flags | O_NONBLOCK) == 0)
            // Darwin qualified constants F_SETNOSIGPIPE=73, F_GETNOSIGPIPE=74.
            try #require(fcntl(writer, 73, 1) == 0); complete = true
        }
        private func cleanup() {
            for index in fds.indices where fds[index] >= 0 { _ = close(fds[index]); fds[index] = -1 }
        }
        deinit { cleanup() }
    }
    private func rawPipe(_ fd: Int32) throws -> pipe_fdinfo {
        var raw = pipe_fdinfo(); let size = MemoryLayout<pipe_fdinfo>.size
        try #require(proc_pidfdinfo(getpid(), fd, PROC_PIDFDPIPEINFO, &raw, Int32(size)) == size)
        return raw
    }
    private func pipeBaseline(_ p: Pipe) throws {
        var r = stat(), w = stat()
        try #require(fstat(p.reader, &r) == 0); try #require(fstat(p.writer, &w) == 0)
        try #require(r.st_mode & S_IFMT == S_IFIFO); try #require(w.st_mode & S_IFMT == S_IFIFO)
        try #require(fcntl(p.reader, F_GETFL) & O_ACCMODE == O_RDONLY)
        let flags = fcntl(p.writer, F_GETFL); try #require(flags >= 0)
        try #require(flags & O_ACCMODE == O_WRONLY); try #require(flags & O_NONBLOCK != 0)
        try #require(fcntl(p.writer, 74) == 1)
        let rr = try rawPipe(p.reader), rw = try rawPipe(p.writer)
        try #require(rr.pipeinfo.pipe_peerhandle == rw.pipeinfo.pipe_handle)
        try #require(rw.pipeinfo.pipe_peerhandle == rr.pipeinfo.pipe_handle)
        let result = try NativeSupervisionPhysicalInspection.stopChannel(readerPID: getpid(), readerFD: p.reader, writerFD: p.writer)
        for (value, physical, raw) in [(result.reader, r, rr), (result.writer, w, rw)] {
            #expect(value.handle == raw.pipeinfo.pipe_handle); #expect(value.peerHandle == raw.pipeinfo.pipe_peerhandle)
            #expect(value.device == UInt64(UInt32(bitPattern: physical.st_dev)))
            #expect(value.inode == physical.st_ino); #expect(value.uid == physical.st_uid)
            #expect(value.openFlags == raw.pfi.fi_openflags)
        }
        #expect(result.reader.openFlags & UInt32(FREAD | FWRITE) == UInt32(FREAD))
        #expect(result.writer.openFlags & UInt32(FREAD | FWRITE) == UInt32(FWRITE))
    }
    @Test func validStopChannelPreservesIndependentKernelFacts() throws { try pipeBaseline(Pipe()) }
    enum PipeFault: CaseIterable { case otherPipe, swapped, blocking, sigpipe, closedReader, closedWriter, nonpipe, missingPID }
    @Test(arguments: PipeFault.allCases)
    func stopRefusesOnePhysicalFault(_ fault: PipeFault) throws {
        let p = try Pipe(); try pipeBaseline(p)
        let other = try Pipe(); var reader = p.reader, writer = p.writer, pid = getpid()
        var nullFD: Int32 = -1
        defer { if nullFD >= 0 { _ = close(nullFD) } }
        switch fault {
        case .otherPipe: reader = other.reader
        case .swapped: reader = p.writer; writer = p.reader
        case .blocking:
            let flags = fcntl(writer, F_GETFL); try #require(flags >= 0)
            try #require(fcntl(writer, F_SETFL, flags & ~O_NONBLOCK) == 0)
        case .sigpipe: try #require(fcntl(writer, 73, 0) == 0)
        case .closedReader: try #require(close(reader) == 0); p.fds[0] = -1
        case .closedWriter: try #require(close(writer) == 0); p.fds[1] = -1
        case .nonpipe: nullFD = open("/dev/null", O_RDONLY | O_CLOEXEC); try #require(nullFD >= 0); reader = nullFD
        case .missingPID: pid = -1
        }
        refuses { _ = try NativeSupervisionPhysicalInspection.stopChannel(readerPID: pid, readerFD: reader, writerFD: writer) }
        withExtendedLifetime(other) {}
    }
}
