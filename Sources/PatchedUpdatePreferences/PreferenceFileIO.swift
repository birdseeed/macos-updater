import Foundation
import Darwin

// All path traversal is descriptor relative. Retained descriptors are checked against their
// parent names at each use; a directory moved aside cannot silently become the current root.
final class PreferenceDirectory {
    let fd: Int32
    private let parent: PreferenceDirectory?
    private let name: String
    private let identity: stat
    private let privateMode: Bool
    private let currentOwner: Bool

    private init(fd: Int32, parent: PreferenceDirectory?, name: String,
                 privateMode: Bool, currentOwner: Bool) throws {
        self.fd = fd; self.parent = parent; self.name = name
        self.privateMode = privateMode; self.currentOwner = currentOwner
        var info = stat()
        guard fstat(fd, &info) == 0 else { close(fd); throw PreferenceRefusal.unavailable }
        identity = info
        // Initial validation is done by the caller so a throwing initialiser never double-closes.
    }
    deinit { close(fd) }

    static func absolute(_ path: String) throws -> PreferenceDirectory {
        guard path.hasPrefix("/"), !path.utf8.contains(0),
              URL(fileURLWithPath: path).standardizedFileURL.path == path else { throw PreferenceRefusal.unavailable }
        let descriptor = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw PreferenceRefusal.unavailable }
        var directory = try PreferenceDirectory(fd: descriptor, parent: nil, name: "/", privateMode: false, currentOwner: false)
        try directory.validate()
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            directory = try directory.openChild(String(component), create: false, privateMode: false, currentOwner: false)
        }
        return directory
    }
    static func fixture(_ url: URL) throws -> PreferenceDirectory {
        guard url.isFileURL, url.standardizedFileURL == url else { throw PreferenceRefusal.unavailable }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(getpid(), &buffer, UInt32(buffer.count)) > 0 else { throw PreferenceRefusal.unavailable }
        let pathBytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let executable = URL(fileURLWithPath: String(decoding: pathBytes, as: UTF8.self))
        guard executable.lastPathComponent == "patched-update-preferences-checks" else { throw PreferenceRefusal.unavailable }
        let executableParent = try absolute(executable.deletingLastPathComponent().path)
        let executableFD = openat(executableParent.fd, executable.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard executableFD >= 0 else { throw PreferenceRefusal.unavailable }
        defer { close(executableFD) }
        var executableInfo = stat(), namedExecutable = stat()
        guard fstat(executableFD, &executableInfo) == 0,
              executableInfo.st_mode & S_IFMT == S_IFREG, executableInfo.st_uid == getuid(),
              executableInfo.st_nlink == 1, executableInfo.st_mode & 0o7022 == 0,
              executableInfo.st_mode & 0o100 != 0,
              fstatat(executableParent.fd, executable.lastPathComponent, &namedExecutable, AT_SYMLINK_NOFOLLOW) == 0,
              samePreferenceInode(executableInfo, namedExecutable) else { throw PreferenceRefusal.unavailable }
        try requirePreferenceACL(executableFD, privateMode: false)
        var build = executable.deletingLastPathComponent()
        while build.path != "/" && build.lastPathComponent != ".build" { build.deleteLastPathComponent() }
        guard build.lastPathComponent == ".build", url.deletingLastPathComponent() == build else {
            throw PreferenceRefusal.unavailable
        }
        let name = url.lastPathComponent, prefix = "pat2662-native-store-"
        guard name.hasPrefix(prefix), let uuid = UUID(uuidString: String(name.dropFirst(prefix.count))),
              name == prefix + uuid.uuidString.lowercased() else { throw PreferenceRefusal.unavailable }
        let parent = try absolute(build.path)
        try parent.requireCurrentOwner()
        return try parent.child(name, create: false, privateMode: true)
    }
    func child(_ name: String, create: Bool, privateMode: Bool) throws -> PreferenceDirectory {
        try openChild(name, create: create, privateMode: privateMode, currentOwner: true)
    }
    private func openChild(_ name: String, create: Bool, privateMode: Bool, currentOwner: Bool) throws -> PreferenceDirectory {
        guard validPreferenceName(name) else { throw PreferenceRefusal.unavailable }
        try validate()
        var info = stat()
        if fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT, create, mkdirat(fd, name, 0o700) == 0 else { throw PreferenceRefusal.unavailable }
            guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw PreferenceRefusal.unavailable }
        }
        guard info.st_mode & S_IFMT == S_IFDIR else { throw PreferenceRefusal.unavailable }
        let descriptor = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw PreferenceRefusal.unavailable }
        let directory = try PreferenceDirectory(fd: descriptor, parent: self, name: name,
                                               privateMode: privateMode, currentOwner: currentOwner)
        guard try directory.matches(info) else { throw PreferenceRefusal.unavailable }
        try directory.validate()
        return directory
    }
    private func matches(_ other: stat) throws -> Bool {
        var current = stat()
        guard fstat(fd, &current) == 0 else { throw PreferenceRefusal.unavailable }
        return samePreferenceInode(current, other)
    }
    func sameIdentity(as other: PreferenceDirectory) throws -> Bool {
        try validate(); try other.validate()
        return samePreferenceInode(identity, other.identity)
    }
    func requireCurrentOwner() throws {
        try validate()
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid() else { throw PreferenceRefusal.unavailable }
    }
    func validate() throws {
        if let parent { try parent.validate() }
        var info = stat()
        guard fstat(fd, &info) == 0, samePreferenceInode(info, identity),
              info.st_mode & S_IFMT == S_IFDIR, info.st_nlink > 0,
              info.st_uid == identity.st_uid,
              currentOwner ? info.st_uid == getuid() : (info.st_uid == 0 || info.st_uid == getuid()),
              privateMode ? info.st_mode & 0o7777 == 0o700 : info.st_mode & 0o7022 == 0 else {
            throw PreferenceRefusal.unavailable
        }
        if let parent {
            var named = stat()
            guard fstatat(parent.fd, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
                  samePreferenceInode(named, info), named.st_mode & S_IFMT == S_IFDIR,
                  !privateMode || named.st_dev == parent.identity.st_dev else { throw PreferenceRefusal.unavailable }
        }
        try requirePreferenceACL(fd, privateMode: privateMode)
    }
}

final class PreferenceFile {
    let fd: Int32
    let name: String
    private let root: PreferenceDirectory
    private let identity: stat
    private let maximum: Int
    private init(fd: Int32, root: PreferenceDirectory, name: String, maximum: Int) throws {
        self.fd = fd; self.root = root; self.name = name; self.maximum = maximum
        var info = stat()
        guard fstat(fd, &info) == 0 else { close(fd); throw PreferenceRefusal.unavailable }
        identity = info
    }
    deinit { close(fd) }
    static func existing(root: PreferenceDirectory, name: String, maximum: Int) throws -> PreferenceFile? {
        try root.validate()
        var info = stat()
        guard fstatat(root.fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            guard errno == ENOENT else { throw PreferenceRefusal.unavailable }; return nil
        }
        // Reject nonregular objects before open (including FIFOs and devices).
        guard info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0, info.st_size <= maximum else {
            throw PreferenceRefusal.unavailable
        }
        let descriptor = openat(root.fd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw PreferenceRefusal.unavailable }
        let file = try PreferenceFile(fd: descriptor, root: root, name: name, maximum: maximum)
        guard samePreferenceInode(info, file.identity) else { throw PreferenceRefusal.unavailable }
        try file.validate(); return file
    }
    static func lock(root: PreferenceDirectory) throws -> PreferenceFile {
        try root.validate()
        let descriptor: Int32
        let created = openat(root.fd, "lock", O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        if created >= 0 { descriptor = created }
        else {
            guard errno == EEXIST else { throw PreferenceRefusal.unavailable }
            var info = stat()
            guard fstatat(root.fd, "lock", &info, AT_SYMLINK_NOFOLLOW) == 0,
                  info.st_mode & S_IFMT == S_IFREG else { throw PreferenceRefusal.unavailable }
            descriptor = openat(root.fd, "lock", O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        }
        guard descriptor >= 0 else { throw PreferenceRefusal.unavailable }
        let file = try PreferenceFile(fd: descriptor, root: root, name: "lock", maximum: 0)
        try file.validate(); return file
    }
    static func temporary(root: PreferenceDirectory) throws -> PreferenceFile {
        try root.validate()
        let name = "temporary-" + UUID().uuidString.lowercased()
        let descriptor = openat(root.fd, name, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw PreferenceRefusal.unavailable }
        let file = try PreferenceFile(fd: descriptor, root: root, name: name, maximum: PreferenceRecord.maximumBytes)
        do { try file.validate(); return file }
        catch { file.removeIfIdentical(); throw error }
    }
    func validate() throws {
        try root.validate()
        var info = stat(), named = stat(), directory = stat()
        guard fstat(fd, &info) == 0, fstat(root.fd, &directory) == 0,
              samePreferenceInode(info, identity), info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_mode & 0o7777 == 0o600, info.st_nlink == 1,
              info.st_dev == directory.st_dev, info.st_size >= 0, info.st_size <= maximum,
              fstatat(root.fd, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              samePreferenceInode(info, named), named.st_mode & S_IFMT == S_IFREG else {
            throw PreferenceRefusal.unavailable
        }
        try requirePreferenceACL(fd, privateMode: true)
    }
    func bytes(maximum: Int) throws -> Data {
        try validate()
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_size >= 0, before.st_size <= maximum else { throw PreferenceRefusal.unavailable }
        var bytes = Data(count: Int(before.st_size))
        try bytes.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            var offset = 0
            while offset < buffer.count {
                let count = pread(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset, off_t(offset))
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw PreferenceRefusal.unavailable }
                offset += count
            }
        }
        var extra: UInt8 = 0
        var count: Int
        repeat { count = pread(fd, &extra, 1, before.st_size) } while count < 0 && errno == EINTR
        var after = stat()
        guard count == 0, fstat(fd, &after) == 0, samePreferenceInode(before, after),
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw PreferenceRefusal.unavailable }
        try validate(); return bytes
    }
    // No directory scans, wildcard cleanup or adoption of another operation's temporary.
    func removeIfIdentical() {
        guard (try? root.validate()) != nil else { return }
        var named = stat(), held = stat()
        guard fstat(fd, &held) == 0, samePreferenceInode(held, identity),
              held.st_uid == getuid(), held.st_mode & S_IFMT == S_IFREG, held.st_nlink == 1,
              fstatat(root.fd, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              samePreferenceInode(named, held), named.st_mode & S_IFMT == S_IFREG else { return }
        _ = unlinkat(root.fd, name, 0)
    }
}

private func validPreferenceName(_ name: String) -> Bool {
    !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.utf8.contains(0)
}
private func samePreferenceInode(_ a: stat, _ b: stat) -> Bool { a.st_dev == b.st_dev && a.st_ino == b.st_ino }
private func requirePreferenceACL(_ descriptor: Int32, privateMode: Bool) throws {
    errno = 0
    guard let acl = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else {
        guard errno == ENOENT else { throw PreferenceRefusal.unavailable }; return
    }
    defer { acl_free(UnsafeMutableRawPointer(acl)) }
    guard acl_valid(acl) == 0 else { throw PreferenceRefusal.unavailable }
    var entry: acl_entry_t?, cursor = Int32(ACL_FIRST_ENTRY.rawValue)
    while true {
        errno = 0
        let result = acl_get_entry(acl, cursor, &entry)
        if result == -1 {
            guard errno == EINVAL else { throw PreferenceRefusal.unavailable }; return
        }
        guard result == 0, let entry else { throw PreferenceRefusal.unavailable }
        var tag = ACL_UNDEFINED_TAG
        guard !privateMode, acl_get_tag_type(entry, &tag) == 0, tag == ACL_EXTENDED_DENY else {
            throw PreferenceRefusal.unavailable
        }
        cursor = Int32(ACL_NEXT_ENTRY.rawValue)
    }
}
