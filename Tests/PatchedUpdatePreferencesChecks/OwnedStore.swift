import Foundation
import Darwin
@_spi(Testing) import PatchedUpdatePreferences

@MainActor final class MemoryStore: PreferenceStore {
    enum Fault { case none, beforeWrite, uncertainAfterWrite, lostAcknowledgement, readbackMismatch }
    var bytes: Data?
    var fault: Fault = .none
    var reads = 0; var writes = 0
    var callback: (() -> Void)?
    private var mismatch = false
    init(bytes: Data? = nil) { self.bytes = bytes }
    func read(maximumBytes: Int) -> PreferenceRead {
        reads += 1
        guard let bytes else { return .missing }
        if mismatch { return .bytes(Data("mismatch".utf8)) }
        return bytes.count <= maximumBytes ? .bytes(bytes) : .unavailable
    }
    func compareAndSwap(expected: Data?, proposed: Data, maximumBytes: Int) -> PreferenceCommit {
        writes += 1
        let hook = callback; callback = nil; hook?()
        guard proposed.count <= maximumBytes else { return .notCommitted }
        guard expected == bytes else { return .conflict }
        if fault == .beforeWrite { return .notCommitted }
        bytes = proposed
        if fault == .readbackMismatch { mismatch = true }
        if fault == .uncertainAfterWrite || fault == .lostAcknowledgement { return .uncertain }
        return .committed
    }
    func clearFault() { fault = .none; mismatch = false }
}

/// Test-only private .build directory. No supplied path or productive store composition.
/// This serial fixture adapter does not defend against a malicious process with the same UID.
@MainActor final class OwnedStore: PreferenceStore {
    enum Fault: CaseIterable { case none, beforeWrite, shortWrite, sync, rename, uncertainAfterRename }
    var fault: Fault = .none
    let rootURL: URL
    private let parentFD: Int32
    private let rootFD: Int32
    private let name: String
    private let device: dev_t
    private let inode: ino_t
    private var handlesClosed = false
    init() throws {
        let cwd = FileManager.default.currentDirectoryPath
        let cwdFD = open(cwd, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard cwdFD >= 0 else { throw CheckFailure(message: "open cwd") }
        defer { close(cwdFD) }
        if mkdirat(cwdFD, ".build", 0o700) != 0 && errno != EEXIST { throw CheckFailure(message: "create .build") }
        let parent = openat(cwdFD, ".build", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parent >= 0 else { throw CheckFailure(message: "open .build") }
        var parentStat = stat()
        guard fstat(parent, &parentStat) == 0, parentStat.st_uid == getuid() else {
            close(parent); throw CheckFailure(message: "foreign .build")
        }
        let suffix = "update-preferences-checks-" + UUID().uuidString.lowercased()
        guard mkdirat(parent, suffix, 0o700) == 0 else { close(parent); throw CheckFailure(message: "exclusive root") }
        let root = openat(parent, suffix, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        var info = stat()
        guard root >= 0, fstat(root, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o777 == 0o700 else {
            if root >= 0 { close(root) }; unlinkat(parent, suffix, AT_REMOVEDIR); close(parent)
            throw CheckFailure(message: "private owned root")
        }
        let url = URL(fileURLWithPath: cwd).appendingPathComponent(".build").appendingPathComponent(suffix)
        guard url.resolvingSymlinksInPath().path == url.path else {
            close(root); unlinkat(parent, suffix, AT_REMOVEDIR); close(parent)
            throw CheckFailure(message: "noncanonical owned root")
        }
        parentFD = parent; rootFD = root; name = suffix; rootURL = url; device = info.st_dev; inode = info.st_ino
    }
    /// Reopens only the exact identity held by a live owned fixture, never a caller path.
    init(reopening original: OwnedStore) throws {
        let parent = dup(original.parentFD)
        let root = openat(parent, original.name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        var info = stat()
        guard parent >= 0, root >= 0, fstat(root, &info) == 0,
              info.st_dev == original.device, info.st_ino == original.inode,
              info.st_uid == getuid(), info.st_mode & 0o777 == 0o700 else {
            if root >= 0 { close(root) }; if parent >= 0 { close(parent) }
            throw CheckFailure(message: "reopen identity changed")
        }
        parentFD = parent; rootFD = root; name = original.name; rootURL = original.rootURL
        device = info.st_dev; inode = info.st_ino
    }
    func closeReopenedHandles() {
        guard !handlesClosed else { return }; handlesClosed = true; close(rootFD); close(parentFD)
    }
    func read(maximumBytes: Int) -> PreferenceRead {
        guard maximumBytes >= 0, maximumBytes <= PreferenceRecord.maximumBytes else { return .unavailable }
        let fd = openat(rootFD, "record.json", O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        if fd < 0 { return errno == ENOENT ? .missing : .unavailable }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
              info.st_uid == getuid(), info.st_mode & 0o777 == 0o600,
              info.st_size >= 0, info.st_size <= maximumBytes else { return .unavailable }
        var data = Data(count: Int(info.st_size))
        let count = data.withUnsafeMutableBytes { buffer in Darwin.read(fd, buffer.baseAddress, buffer.count) }
        guard count == data.count else { return .unavailable }
        var extra: UInt8 = 0
        guard Darwin.read(fd, &extra, 1) == 0 else { return .unavailable }
        return .bytes(data)
    }
    func compareAndSwap(expected: Data?, proposed: Data, maximumBytes: Int) -> PreferenceCommit {
        guard proposed.count <= maximumBytes, maximumBytes <= PreferenceRecord.maximumBytes else { return .notCommitted }
        switch read(maximumBytes: maximumBytes) {
        case .missing: guard expected == nil else { return .conflict }
        case .bytes(let current): guard expected == current else { return .conflict }
        case .unavailable: return .notCommitted
        }
        if fault == .beforeWrite { return .notCommitted }
        let temporary = "temporary-" + UUID().uuidString.lowercased()
        let fd = openat(rootFD, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { return .notCommitted }
        defer { close(fd); unlinkat(rootFD, temporary, 0) }
        let length = fault == .shortWrite ? max(0, proposed.count - 1) : proposed.count
        let count = proposed.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, length) }
        guard count == proposed.count, fault != .sync, fsync(fd) == 0, fault != .rename else { return .notCommitted }
        guard renameat(rootFD, temporary, rootFD, "record.json") == 0 else { return .notCommitted }
        guard fsync(rootFD) == 0 else { return .uncertain }
        return fault == .uncertainAfterRename ? .uncertain : .committed
    }
    func cleanup() throws {
        guard !handlesClosed else { return }
        var info = stat()
        guard fstatat(parentFD, name, &info, AT_SYMLINK_NOFOLLOW) == 0,
              info.st_dev == device, info.st_ino == inode, info.st_uid == getuid(),
              info.st_mode & S_IFMT == S_IFDIR else { throw CheckFailure(message: "cleanup identity changed") }
        // Exact owned child names only. Never traverse or recursively remove unknown content.
        if unlinkat(rootFD, "record.json", 0) != 0 && errno != ENOENT { throw CheckFailure(message: "cleanup record") }
        guard unlinkat(parentFD, name, AT_REMOVEDIR) == 0 else { throw CheckFailure(message: "cleanup root nonempty") }
        closeReopenedHandles()
    }
}
