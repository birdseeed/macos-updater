import Foundation
import CoreFoundation
import Darwin
@_spi(Testing) import PatchedActivity

// Test-owned private bytes only. No source filesystem adapter or authenticated OS history claim.
// Does not establish atomic CAS against malicious same-user writers or hardware durability.
@MainActor final class OwnedStore: ActivityStore {
    enum Fault: Equatable { case none, beforeWrite, knownNotCommitted, uncertainWithoutWrite, afterCommit, readbackMismatch, readError }
    let directory: URL
    let file: URL
    private let device: dev_t
    private let inode: ino_t
    var fault: Fault = .none
    var reads = 0
    var writes = 0
    var reenter: (() -> Void)?
    // Test-owned boundary hooks make descriptor/allocation/EOF guards independently observable.
    var afterPreopenCheck: (() throws -> Void)?
    var afterOpenedCheck: (() throws -> Void)?
    var beforeDirectorySync: (() throws -> Void)?
    private(set) var allocatedReadBytes = 0
    private(set) var directorySyncs = 0
    private var mismatching = false
    init() throws {
        guard var build = Bundle.main.executableURL?.resolvingSymlinksInPath() else { throw Failure(description: "No executable URL") }
        while build.lastPathComponent != ".build" {
            guard build.pathComponents.count > 1 else { throw Failure(description: "Fixture must run below .build") }
            build.deleteLastPathComponent()
        }
        // Resolve the executable first, then reject symlinks at every actual ancestor.
        var cursor = URL(fileURLWithPath: "/")
        for component in build.pathComponents.dropFirst() {
            cursor.appendPathComponent(component)
            var info = stat()
            guard lstat(cursor.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { throw Failure(description: "Unsafe build ancestry") }
        }
        directory = build.appendingPathComponent("patched-activity-fixture-" + UUID().uuidString)
        guard mkdir(directory.path, 0o700) == 0 else { throw Failure(description: "Exclusive fixture directory unavailable") }
        file = directory.appendingPathComponent("record.json")
        var info = stat()
        guard lstat(directory.path, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o777 == 0o700 else {
            throw Failure(description: "Fixture ownership unavailable")
        }
        device = info.st_dev; inode = info.st_ino
    }
    func validateDirectory() throws {
        var info = stat()
        guard lstat(directory.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid(), info.st_mode & 0o777 == 0o700,
              info.st_dev == device, info.st_ino == inode,
              directory.resolvingSymlinksInPath().path == directory.path else { throw Failure(description: "Owned fixture directory changed") }
    }
    func actual() throws -> ActivityStoredBytes? {
        allocatedReadBytes = 0
        try validateDirectory()
        var info = stat()
        if lstat(file.path, &info) != 0 {
            guard errno == ENOENT else { throw Failure(description: "Cannot inspect fixture file") }
            return nil
        }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1, info.st_uid == getuid(),
              info.st_mode & 0o777 == 0o600, info.st_size >= 0, info.st_size <= 3 * 1024 * 1024 else {
            throw Failure(description: "Unsafe fixture file")
        }
        try afterPreopenCheck?()
        let fd = open(file.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard fd >= 0 else { throw Failure(description: "Fixture no-follow open failed") }
        defer { close(fd) }
        var opened = stat()
        guard fstat(fd, &opened) == 0, opened.st_ino == info.st_ino, opened.st_dev == info.st_dev,
              opened.st_mode & S_IFMT == S_IFREG, opened.st_uid == getuid(),
              opened.st_mode & 0o777 == 0o600, opened.st_nlink == 1,
              opened.st_size >= 0, opened.st_size <= 3 * 1024 * 1024 else {
            throw Failure(description: "Opened fixture descriptor unsafe or changed")
        }
        try afterOpenedCheck?()
        allocatedReadBytes = Int(opened.st_size)
        var data = Data(count: allocatedReadBytes)
        let count = data.withUnsafeMutableBytes { buffer in Darwin.read(fd, buffer.baseAddress, buffer.count) }
        guard count == data.count else { throw Failure(description: "Short fixture read") }
        var extra: UInt8 = 0
        guard Darwin.read(fd, &extra, 1) == 0 else { throw Failure(description: "Fixture EOF guard refused changed bytes") }
        var final = stat()
        guard fstat(fd, &final) == 0, final.st_ino == opened.st_ino, final.st_dev == opened.st_dev,
              final.st_mode & S_IFMT == S_IFREG, final.st_uid == getuid(),
              final.st_mode & 0o777 == 0o600, final.st_nlink == 1,
              final.st_size == opened.st_size else { throw Failure(description: "Fixture changed during read") }
        try validateDirectory()
        guard let wrapper = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(wrapper.keys) == ["revision", "payload"],
              let revision = wrapper["revision"] as? NSNumber, CFGetTypeID(revision) != CFBooleanGetTypeID(),
              let payload = wrapper["payload"] as? String, let bytes = Data(base64Encoded: payload) else {
            throw Failure(description: "Invalid test-owned wrapper")
        }
        return ActivityStoredBytes(revision: revision.uint64Value, bytes: bytes)
    }
    func read() throws -> ActivityStoredBytes? {
        reads += 1
        if fault == .readError { throw Failure(description: "Injected read failure") }
        if mismatching { return try bytes([], revision: 999) }
        return try actual()
    }
    func seed(_ value: ActivityStoredBytes) throws { try persist(value) }
    private func persist(_ value: ActivityStoredBytes) throws {
        try validateDirectory()
        _ = try actual() // refuses pre-existing links/unsafe record
        let data = try canonical(["revision": NSNumber(value: value.revision), "payload": value.bytes.base64EncodedString()])
        guard data.count <= 3 * 1024 * 1024 else { throw Failure(description: "Test wrapper over limit") }
        let temporary = directory.appendingPathComponent("pending-" + UUID().uuidString)
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw Failure(description: "Cannot create owned pending record") }
        defer { close(fd); unlink(temporary.path) }
        let count = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        guard count == data.count, fsync(fd) == 0 else { throw Failure(description: "Fixture write/sync failed") }
        try validateDirectory()
        guard rename(temporary.path, file.path) == 0 else { throw Failure(description: "Fixture rename failed") }
        // Rename may already have committed. A failed directory sync is explicitly uncertain.
        do {
            try beforeDirectorySync?()
            try syncOwnedDirectory()
        } catch { throw ActivityRefusal.uncertain }
    }
    private func syncOwnedDirectory() throws {
        try validateDirectory()
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NONBLOCK | O_NOFOLLOW)
        guard fd >= 0 else { throw Failure(description: "Cannot open owned directory for sync") }
        defer { close(fd) }
        var opened = stat()
        guard fstat(fd, &opened) == 0, opened.st_mode & S_IFMT == S_IFDIR,
              opened.st_dev == device, opened.st_ino == inode, opened.st_uid == getuid(),
              opened.st_mode & 0o777 == 0o700 else { throw Failure(description: "Owned sync descriptor changed") }
        guard fsync(fd) == 0 else { throw Failure(description: "Owned directory sync failed") }
        try validateDirectory()
        directorySyncs += 1
    }
    func compareAndSwap(expected: ActivityStoredBytes?, replacement: ActivityStoredBytes) throws -> ActivityWriteResult {
        writes += 1
        reenter?()
        guard try actual() == expected else { return .knownNotCommitted }
        switch fault {
        case .beforeWrite: throw Failure(description: "Injected pre-write interruption")
        case .knownNotCommitted: return .knownNotCommitted
        case .uncertainWithoutWrite: return .uncertain
        default: break
        }
        try persist(replacement)
        if fault == .afterCommit { return .uncertain }
        if fault == .readbackMismatch { mismatching = true }
        return .committed
    }
    func clearFault() {
        fault = .none; mismatching = false; reenter = nil
        afterPreopenCheck = nil; afterOpenedCheck = nil; beforeDirectorySync = nil
    }
}
