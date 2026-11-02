import Foundation
import Darwin
import CryptoKit

let directoryFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
let regularFlags = O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
func identity(_ s: stat) -> (UInt64, UInt64) { (UInt64(UInt32(bitPattern: s.st_dev)), s.st_ino) }
func sameIdentity(_ a: stat, _ b: stat) -> Bool { a.st_dev == b.st_dev && a.st_ino == b.st_ino }
func permissions(_ s: stat) -> mode_t { s.st_mode & 0o7777 }
func safeMode(_ s: stat) -> Bool { permissions(s) & 0o7022 == 0 }
func stable(_ a: stat, _ b: stat) -> Bool {
    sameIdentity(a, b) && a.st_mode == b.st_mode && a.st_uid == b.st_uid && a.st_nlink == b.st_nlink &&
        a.st_size == b.st_size && a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec &&
        a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec && a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec &&
        a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
}
func components(_ path: String, absolute: Bool = false) throws -> [String] {
    let bytes = Array(path.utf8)
    guard !bytes.isEmpty, bytes.count < Int(PATH_MAX), !bytes.contains(0),
          bytes.allSatisfy({ $0 >= 32 && $0 != 127 }), (bytes.first == 47) == absolute else { throw DisposableFailure.unsafePath }
    let input = absolute ? Array(bytes.dropFirst()) : bytes
    let pieces = input.split(separator: 47, omittingEmptySubsequences: false)
    guard !pieces.isEmpty, pieces.count <= 64, pieces.allSatisfy({
        !$0.isEmpty && $0.count <= Int(NAME_MAX) && !$0.elementsEqual([46]) && !$0.elementsEqual([46, 46])
    }) else { throw DisposableFailure.unsafePath }
    return pieces.map { String(decoding: $0, as: UTF8.self) }
}
func kernelExecutable() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
    let count = proc_pidpath(getpid(), &bytes, UInt32(bytes.count))
    guard count > 0, count < bytes.count else { throw DisposableFailure.notAuthorized }
    let result = String(decoding: bytes.prefix(Int(count)), as: UTF8.self)
    _ = try components(result, absolute: true); return result
}
struct FileHooks {
    var boundary: ((String) throws -> Void)?
    var sync: ((String) throws -> Void)?
    func hit(_ name: String) throws {
        do { try boundary?(name) } catch let error as DisposableFailure { throw error } catch { throw DisposableFailure.persistenceFailed }
    }
    func flush(_ name: String) throws {
        do { try sync?(name) } catch { throw DisposableFailure.persistenceFailed }
    }
}
// A mount callback owns a separate lease. Closing it invalidates every descriptor
// even when a callback accidentally retains a handle; ARC timing cannot keep a mount busy.
final class DescriptorHandle {
    private(set) var value: Int32
    init(_ value: Int32) { self.value = value }
    func closeNow() { if value >= 0 { Darwin.close(value); value = -1 } }
    deinit { closeNow() }
}
final class DescriptorLease {
    private var handles: [DescriptorHandle] = []
    func adopt(_ fd: Int32) -> DescriptorHandle {
        let handle = DescriptorHandle(fd); handles.append(handle); return handle
    }
    func closeAll() { for handle in handles { handle.closeNow() } }
}
final class HeldDirectory {
    private let handle: DescriptorHandle
    let lease: DescriptorLease
    var fd: Int32 { handle.value }
    let path: String
    let parent: HeldDirectory?
    let name: String
    let captured: stat
    init(fd: Int32, path: String, parent: HeldDirectory?, name: String) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { close(fd); throw DisposableFailure.notDirectory }
        let lease = parent?.lease ?? DescriptorLease()
        self.lease = lease; handle = lease.adopt(fd)
        self.path = path; self.parent = parent; self.name = name; captured = info
    }
    deinit { handle.closeNow() }
    func closeDescriptor() { handle.closeNow() }
    func closeOwnedChain() { lease.closeAll() }
    static func absolute(_ path: String) throws -> HeldDirectory {
        let names = try components(path, absolute: true)
        let fd = Darwin.open("/", directoryFlags); guard fd >= 0 else { throw DisposableFailure.unsafePath }
        var current = try HeldDirectory(fd: fd, path: "", parent: nil, name: "")
        for name in names { current = try current.child(name) }
        return current
    }
    func status() throws -> stat {
        var info = stat(); guard fstat(fd, &info) == 0, info.st_nlink > 0 else { throw DisposableFailure.identityChanged }; return info
    }
    func confirm() throws {
        try parent?.confirm(); let info = try status()
        guard sameIdentity(info, captured), info.st_mode == captured.st_mode, info.st_uid == captured.st_uid else { throw DisposableFailure.identityChanged }
        if let parent {
            var named = stat()
            guard fstatat(parent.fd, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
                  sameIdentity(named, info), named.st_mode & S_IFMT == S_IFDIR else { throw DisposableFailure.identityChanged }
        }
    }
    func owned(privateMode: Bool = false, uid: uid_t = getuid()) throws {
        let s = try status()
        guard s.st_uid == uid else { throw DisposableFailure.unsafeOwner }
        guard privateMode ? permissions(s) == 0o700 : safeMode(s) else { throw DisposableFailure.unsafeMode }
    }
    func named(_ name: String) throws -> stat? {
        _ = try components(name); guard !name.contains("/") else { throw DisposableFailure.unsafePath }
        var info = stat()
        if fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 { return info }
        guard errno == ENOENT else { throw DisposableFailure.unsafePath }; return nil
    }
    func child(_ name: String) throws -> HeldDirectory {
        try confirm()
        guard let before = try named(name) else { throw DisposableFailure.notDirectory }
        guard before.st_mode & S_IFMT != S_IFLNK else { throw DisposableFailure.symlink }
        guard before.st_mode & S_IFMT == S_IFDIR else { throw DisposableFailure.notDirectory }
        let opened = openat(fd, name, directoryFlags); guard opened >= 0 else { throw DisposableFailure.identityChanged }
        let child = try HeldDirectory(fd: opened, path: path + "/" + name, parent: self, name: name)
        guard sameIdentity(before, child.captured) else { throw DisposableFailure.identityChanged }
        try child.confirm(); return child
    }
    func descend(_ relative: String) throws -> HeldDirectory {
        var directory = self
        for part in try components(relative) { directory = try directory.child(part) }; return directory
    }
    func parentOf(_ relative: String) throws -> (HeldDirectory, String) {
        let parts = try components(relative); var directory = self
        for part in parts.dropLast() { directory = try directory.child(part) }
        return (directory, parts.last!)
    }
    func mkdir(_ name: String) throws -> HeldDirectory {
        try confirm(); _ = try components(name); guard !name.contains("/") else { throw DisposableFailure.unsafePath }
        guard mkdirat(fd, name, 0o700) == 0 else { throw errno == EEXIST ? DisposableFailure.existingRoot : .persistenceFailed }
        let child = try self.child(name); guard fchmod(child.fd, 0o700) == 0 else { throw DisposableFailure.persistenceFailed }
        try child.owned(privateMode: true); try syncDirectory(); return child
    }
    func syncDirectory(hooks: FileHooks = .init()) throws {
        try hooks.flush("directorySync"); try confirm()
        guard fsync(fd) == 0 else { throw DisposableFailure.persistenceFailed }; try confirm()
    }
    func names(maximum: Int) throws -> [String] {
        try confirm()
        let duplicate = dup(fd); guard duplicate >= 0, let stream = fdopendir(duplicate) else {
            if duplicate >= 0 { close(duplicate) }; throw DisposableFailure.unsafePath
        }
        defer { closedir(stream) }
        rewinddir(stream); var names: [String] = []
        errno = 0
        while let entry = readdir(stream) {
            var raw = entry.pointee.d_name
            let name = withUnsafePointer(to: &raw) { $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(validatingCString: $0) } }
            guard let name else { throw DisposableFailure.unsafePath }
            if name == "." || name == ".." { continue }
            _ = try components(name); guard !name.contains("/") else { throw DisposableFailure.unsafePath }
            names.append(name); guard names.count <= maximum else { throw DisposableFailure.treeLimit }; errno = 0
        }
        guard errno == 0 else { throw DisposableFailure.unsafePath }; try confirm()
        return names.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }
}
final class HeldFile {
    private let handle: DescriptorHandle
    var fd: Int32 { handle.value }
    let parent: HeldDirectory, name: String, captured: stat
    init(parent: HeldDirectory, name: String, writable: Bool = false, hooks: FileHooks = .init(), owner: uid_t? = getuid()) throws {
        try parent.confirm()
        guard let before = try parent.named(name) else { throw DisposableFailure.notRegularFile }
        try Self.validate(before, owner: owner)
        try hooks.hit("beforeFileOpen"); try parent.confirm()
        let opened = openat(parent.fd, name, (writable ? O_RDWR : O_RDONLY) | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard opened >= 0 else { throw DisposableFailure.identityChanged }
        var transferred = false
        defer { if !transferred { close(opened) } }
        var held = stat()
        guard fstat(opened, &held) == 0, stable(before, held) else { throw DisposableFailure.identityChanged }
        try hooks.hit("fileHeld"); try parent.confirm()
        var after = stat()
        guard fstat(opened, &after) == 0, stable(held, after),
              let named = try parent.named(name), stable(after, named) else { throw DisposableFailure.identityChanged }
        handle = parent.lease.adopt(opened); self.parent = parent; self.name = name; self.captured = held
        transferred = true
    }
    deinit { handle.closeNow() }
    static func validate(_ s: stat, owner: uid_t?) throws {
        guard s.st_mode & S_IFMT != S_IFLNK else { throw DisposableFailure.symlink }
        guard s.st_mode & S_IFMT == S_IFREG else { throw DisposableFailure.specialFile }
        guard s.st_nlink == 1 else { throw DisposableFailure.hardlink }
        if let owner { guard s.st_uid == owner else { throw DisposableFailure.unsafeOwner } }
        guard safeMode(s) else { throw DisposableFailure.unsafeMode }
    }
    func confirm() throws {
        try parent.confirm(); var current = stat()
        guard fstat(fd, &current) == 0, stable(current, captured),
              let named = try parent.named(name), stable(current, named) else { throw DisposableFailure.identityChanged }
    }
    func stream(maximum: Int64, consume: ((Data) throws -> Void)? = nil) throws -> (Int64, String) {
        try confirm(); guard captured.st_size <= maximum, captured.st_size >= 0 else { throw DisposableFailure.treeLimit }
        var hash = SHA256(), offset: Int64 = 0, buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = pread(fd, &buffer, buffer.count, off_t(offset))
            if count < 0 { if errno == EINTR { continue }; throw DisposableFailure.identityChanged }
            if count == 0 { break }
            offset += Int64(count); guard offset <= maximum, offset <= captured.st_size else { throw DisposableFailure.identityChanged }
            let data = Data(buffer.prefix(count)); hash.update(data: data); try consume?(data)
        }
        guard offset == captured.st_size else { throw DisposableFailure.identityChanged }; try confirm()
        return (offset, hex(hash.finalize()))
    }
    func data(maximum: Int) throws -> Data {
        var result = Data(); _ = try stream(maximum: Int64(maximum)) { result.append($0) }; return result
    }
    func verify(length: Int64, hash: String) throws {
        try confirm(); guard captured.st_size == length else { throw DisposableFailure.lengthMismatch }
        guard try stream(maximum: length).1 == hash else { throw DisposableFailure.digestMismatch }
    }
}
enum PhysicalIO {
    static func read(_ root: HeldDirectory, _ relative: String, maximum: Int, hooks: FileHooks = .init()) throws -> Data {
        let (directory, name) = try root.parentOf(relative)
        return try HeldFile(parent: directory, name: name, hooks: hooks).data(maximum: maximum)
    }
    static func write(_ root: HeldDirectory, _ name: String, data: Data, hooks: FileHooks = .init()) throws {
        let (directory, leaf) = try root.parentOf(name); try directory.confirm()
        let fd = openat(directory.fd, leaf, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw errno == EEXIST ? DisposableFailure.existingRoot : .persistenceFailed }
        defer { close(fd) }
        guard fchmod(fd, 0o600) == 0 else { throw DisposableFailure.persistenceFailed }
        var captured = stat(); guard fstat(fd, &captured) == 0 else { throw DisposableFailure.persistenceFailed }
        func confirm() throws {
            try directory.confirm(); guard let named = try directory.named(leaf), sameIdentity(named, captured),
                named.st_nlink == 1, permissions(named) == 0o600, named.st_uid == getuid() else { throw DisposableFailure.identityChanged }
        }
        try confirm(); try writeAll(fd, data); try confirm()
        try syncFile(fd, hooks: hooks); try directory.syncDirectory(hooks: hooks); try confirm()
        try hooks.flush("committedFileFullSync")
        guard fcntl(fd, F_FULLFSYNC) == 0 else { throw DisposableFailure.persistenceFailed }
    }
    static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let n = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw DisposableFailure.persistenceFailed }; offset += n
            }
        }
    }
    static func syncFile(_ fd: Int32, hooks: FileHooks = .init()) throws {
        try hooks.flush("fileSync"); guard fsync(fd) == 0 else { throw DisposableFailure.persistenceFailed }
        try hooks.flush("fileFullSync"); guard fcntl(fd, F_FULLFSYNC) == 0 else { throw DisposableFailure.persistenceFailed }
    }
    static func exchange(_ root: HeldDirectory, _ left: String, _ right: String, hooks: FileHooks = .init()) throws {
        guard left.utf8.elementsEqual(right.utf8) == false else { throw DisposableFailure.unsafePath }
        let (a, an) = try root.parentOf(left), (b, bn) = try root.parentOf(right)
        guard let beforeA = try a.named(an), let beforeB = try b.named(bn) else { throw DisposableFailure.ambiguousState }
        for s in [beforeA, beforeB] {
            guard s.st_mode & S_IFMT != S_IFLNK else { throw DisposableFailure.symlink }
            guard s.st_mode & S_IFMT == S_IFREG || s.st_mode & S_IFMT == S_IFDIR else { throw DisposableFailure.specialFile }
            guard s.st_uid == getuid(), safeMode(s) else { throw DisposableFailure.unsafeMode }
            if s.st_mode & S_IFMT == S_IFREG { guard s.st_nlink == 1 else { throw DisposableFailure.hardlink } }
        }
        try sameVolume(identity(beforeA).0, identity(beforeB).0)
        guard !sameIdentity(beforeA, beforeB) else { throw DisposableFailure.unsafePath }
        try hooks.hit("beforeExchange"); try root.confirm(); try a.confirm(); try b.confirm()
        guard let namedA = try a.named(an), let namedB = try b.named(bn),
              stable(beforeA, namedA), stable(beforeB, namedB) else { throw DisposableFailure.identityChanged }
        guard renameatx_np(a.fd, an, b.fd, bn, UInt32(RENAME_SWAP)) == 0 else { throw DisposableFailure.persistenceFailed }
        try a.syncDirectory(); try b.syncDirectory(); try root.confirm()
        guard let afterA = try a.named(an), let afterB = try b.named(bn),
              sameIdentity(afterA, beforeB), sameIdentity(afterB, beforeA) else { throw DisposableFailure.identityChanged }
        try hooks.hit("afterExchange")
    }
}
