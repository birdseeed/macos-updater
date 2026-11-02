import Foundation
import Darwin
@_spi(Testing) import PatchedActivity

// Independent descriptor IO, never NativeActivityContext, real home, Keychain or a child process.
// Declaring checks does no IO. Every mutation below targets an exclusively created .build root.
@MainActor private final class ActivityFileFixture {
    let url: URL
    let parent: Int32
    let fd: Int32
    let name: String
    private let identity: stat
    private var closed = false
    private var ownedChildren: Set<String> = []
    static func build() throws -> URL {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        try expect(proc_pidpath(getpid(), &buffer, UInt32(buffer.count)) > 0, "kernel executable path unavailable")
        let raw = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let executable = URL(fileURLWithPath: raw)
        try expect(executable.lastPathComponent == "patched-activity-checks", "wrong fixture executable")
        var build = executable.deletingLastPathComponent()
        while build.path != "/" && build.lastPathComponent != ".build" { build.deleteLastPathComponent() }
        try expect(build.lastPathComponent == ".build", "check executable outside .build")
        var cursor = URL(fileURLWithPath: "/")
        for component in build.pathComponents.dropFirst() {
            cursor.appendPathComponent(component)
            var s = stat()
            try expect(lstat(cursor.path, &s) == 0 && s.st_mode & S_IFMT == S_IFDIR,
                       "fixture ancestry is not physical")
        }
        return build
    }
    init() throws {
        let build = try Self.build()
        let p = open(build.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard p >= 0 else { throw Failure(description: "fixture parent open") }
        var ps = stat()
        guard fstat(p, &ps) == 0, ps.st_uid == getuid() else { close(p); throw Failure(description: "fixture parent owner") }
        let n = "pat2663-native-store-" + UUID().uuidString.lowercased()
        guard mkdirat(p, n, 0o700) == 0 else { close(p); throw Failure(description: "exclusive fixture root") }
        let d = openat(p, n, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        var s = stat()
        guard d >= 0, fstat(d, &s) == 0, s.st_uid == getuid(), s.st_mode & S_IFMT == S_IFDIR,
              s.st_mode & 0o7777 == 0o700 else {
            if d >= 0 { close(d) }; unlinkat(p, n, AT_REMOVEDIR); close(p)
            throw Failure(description: "fixture root ownership")
        }
        parent = p; fd = d; name = n; identity = s; url = build.appendingPathComponent(n)
    }
    var selector: FixtureActivityRoot { FixtureActivityRoot(checkOwnedDirectory: url) }
    func store(_ fault: FixtureActivityFault = .none, owner: String = principal, id: String = storeID) -> FileActivityStore {
        FileActivityStore(fixtureRoot: selector, principal: owner, storeID: id, fault: fault)
    }
    func seed(_ data: Data, name: String = "record.json", mode: mode_t = 0o600) throws {
        try expect(!name.contains("/") && name != "." && name != "..", "unsafe fixture child")
        let child = openat(fd, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode)
        guard child >= 0 else { throw Failure(description: "exclusive fixture seed") }
        ownedChildren.insert(name); defer { close(child) }
        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(child, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                try expect(count > 0, "fixture seed write")
                offset += count
            }
        }
        try expect(fsync(child) == 0, "fixture seed sync")
    }
    func data(_ name: String = "record.json") throws -> Data {
        let child = openat(fd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard child >= 0 else { throw Failure(description: "fixture read open") }; defer { close(child) }
        var s = stat()
        try expect(fstat(child, &s) == 0 && s.st_mode & S_IFMT == S_IFREG && s.st_size >= 0 && s.st_size <= 2_097_153,
                   "fixture read bound/type")
        var result = Data(count: Int(s.st_size))
        try result.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.read(child, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                try expect(count > 0, "fixture full read"); offset += count
            }
        }
        var extra: UInt8 = 0
        try expect(Darwin.read(child, &extra, 1) == 0, "fixture exact EOF")
        return result
    }
    func names() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: url.path).sorted() }
    func absent(_ child: String = "record.json") -> Bool {
        var s = stat(); return fstatat(fd, child, &s, AT_SYMLINK_NOFOLLOW) != 0 && errno == ENOENT
    }
    func registerOwned(_ child: String) { ownedChildren.insert(child) }
    func rootIdentity(_ child: String) throws {
        var s = stat()
        try expect(fstatat(parent, child, &s, AT_SYMLINK_NOFOLLOW) == 0 && s.st_dev == identity.st_dev &&
                   s.st_ino == identity.st_ino && s.st_mode & S_IFMT == S_IFDIR, "fixture root identity changed")
    }
    func withRenamed(_ body: (URL) throws -> Void) throws {
        let moved = name + "-invalid"
        try rootIdentity(name)
        var s = stat()
        try expect(fstatat(parent, moved, &s, AT_SYMLINK_NOFOLLOW) != 0 && errno == ENOENT, "rename destination exists")
        try expect(renameat(parent, name, parent, moved) == 0, "fixture root rename")
        let result = Result { try body(url.deletingLastPathComponent().appendingPathComponent(moved)) }
        try rootIdentity(moved)
        try expect(fstatat(parent, name, &s, AT_SYMLINK_NOFOLLOW) != 0 && errno == ENOENT, "restore destination exists")
        try expect(renameat(parent, moved, parent, name) == 0, "fixture root restore")
        try result.get()
    }
    func withSymlinkSelector(_ body: (FixtureActivityRoot) throws -> Void) throws {
        let alias = "pat2663-native-store-" + UUID().uuidString.lowercased()
        try rootIdentity(name)
        try expect(symlinkat(name, parent, alias) == 0, "exclusive fixture alias")
        var before = stat()
        try expect(fstatat(parent, alias, &before, AT_SYMLINK_NOFOLLOW) == 0, "alias stat")
        let result = Result { try body(FixtureActivityRoot(checkOwnedDirectory: url.deletingLastPathComponent().appendingPathComponent(alias))) }
        var after = stat()
        try expect(fstatat(parent, alias, &after, AT_SYMLINK_NOFOLLOW) == 0 && before.st_dev == after.st_dev &&
                   before.st_ino == after.st_ino && after.st_mode & S_IFMT == S_IFLNK, "alias identity drift")
        try expect(unlinkat(parent, alias, 0) == 0, "owned alias cleanup")
        try result.get()
    }
    func cleanup() throws {
        guard !closed else { return }
        try rootIdentity(name)
        // No enumeration-driven removal: only our declared children and the adapter's fixed names.
        // Unknown/leaked adapter temps remain evidence and prevent rmdir.
        for child in ownedChildren.union(["record.json", "lock"]) {
            var s = stat()
            if fstatat(fd, child, &s, AT_SYMLINK_NOFOLLOW) != 0 {
                try expect(errno == ENOENT, "cleanup inspect"); continue
            }
            try expect(s.st_uid == getuid() && s.st_dev == identity.st_dev, "cleanup foreign inode")
            let flags: Int32 = s.st_mode & S_IFMT == S_IFDIR ? AT_REMOVEDIR : 0
            try expect(unlinkat(fd, child, flags) == 0, "cleanup declared child")
        }
        try expect(unlinkat(parent, name, AT_REMOVEDIR) == 0, "cleanup root nonempty")
        close(fd); close(parent); closed = true
    }
    deinit { if !closed { close(fd); close(parent) } }
}

private func committed(_ result: ActivityWriteResult) -> Bool { if case .committed = result { return true }; return false }
private func notCommitted(_ result: ActivityWriteResult) -> Bool { if case .knownNotCommitted = result { return true }; return false }
private func uncertain(_ result: ActivityWriteResult) -> Bool { if case .uncertain = result { return true }; return false }
@MainActor private func fileOwner(_ store: FileActivityStore, owner: String = principal, id: String = storeID) -> ActivityHistoryOwner {
    ActivityHistoryOwner(store: store, principal: owner, storeID: id)
}
@MainActor private func checkRefusingStore(_ store: FileActivityStore, old: ActivityStoredBytes, next: ActivityStoredBytes) throws {
    try refused { _ = try store.read() }
    try expect(notCommitted(try store.compareAndSwap(expected: old, replacement: next)), "unsafe write not known refused")
}
private func installAllowACL(_ descriptor: Int32) throws {
    guard let acl = acl_init(1) else { throw Failure(description: "fixture acl_init") }
    var mutableACL: acl_t? = acl
    defer { if let current = mutableACL { acl_free(UnsafeMutableRawPointer(current)) } }
    var entry: acl_entry_t?
    try expect(acl_create_entry(&mutableACL, &entry) == 0, "fixture ACL entry")
    guard let entry else { throw Failure(description: "fixture ACL entry missing") }
    try expect(acl_set_tag_type(entry, ACL_EXTENDED_ALLOW) == 0, "fixture allow tag")
    var qualifier = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000099")!.uuid
    try expect(withUnsafePointer(to: &qualifier) { acl_set_qualifier(entry, $0) } == 0, "fixture ACL qualifier")
    var permissions: acl_permset_t?
    try expect(acl_get_permset(entry, &permissions) == 0, "fixture ACL permissions")
    guard let permissions else { throw Failure(description: "fixture ACL permissions missing") }
    try expect(acl_add_perm(permissions, ACL_READ_DATA) == 0 && acl_set_permset(entry, permissions) == 0,
               "fixture ACL read grant")
    guard let complete = mutableACL else { throw Failure(description: "fixture ACL missing") }
    try expect(acl_valid(complete) == 0 && acl_set_fd_np(descriptor, complete, ACL_TYPE_EXTENDED) == 0, "fixture ACL install")
}

@MainActor func registerNativeFileStoreChecks() {
    check("native-file setup: independent physical seed read and cleanup", setup: true) {
        let f = try ActivityFileFixture(); defer { try? f.cleanup() }
        let literal = try bytes([event()]); try f.seed(literal.bytes)
        try expect(try f.data() == literal.bytes, "independent fixture seed")
        var s = stat(); try expect(fstat(f.fd, &s) == 0 && s.st_mode & 0o7777 == 0o700, "private root")
        try expect(fstatat(f.fd, "record.json", &s, AT_SYMLINK_NOFOLLOW) == 0 && s.st_mode & 0o7777 == 0o600 && s.st_nlink == 1, "private seed")
        try f.cleanup()
        try expect(!FileManager.default.fileExists(atPath: f.url.path), "owned root cleanup failed")
    }
    check("native-file setup: independent canonical oracle matches accepted wire", setup: true) {
        let value = try bytes([event()], revision: 7)
        try expect(try ActivityWire.decode(value.bytes, principal: principal, storeID: storeID).revision == 7, "wire oracle mismatch")
    }
    check("native-file setup: independent allow ACL is physically present", setup: true) {
        let f = try ActivityFileFixture(); defer { try? f.cleanup() }
        try installAllowACL(f.fd)
        guard let acl = acl_get_fd_np(f.fd, ACL_TYPE_EXTENDED) else { throw Failure(description: "fixture ACL readback") }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?
        try expect(acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry) == 0, "fixture ACL first entry")
        guard let entry else { throw Failure(description: "fixture ACL no entry") }
        var tag = ACL_UNDEFINED_TAG
        try expect(acl_get_tag_type(entry, &tag) == 0 && tag == ACL_EXTENDED_ALLOW, "fixture allow ACL missing")
    }
    check("native-file: missing read has no creation and explicit bootstrap persists revision zero") {
        let f = try ActivityFileFixture(); defer { try? f.cleanup() }; let store = f.store()
        try expect(try store.read() == nil && f.names().isEmpty, "missing read creates state")
        let owner = fileOwner(store); try refused { try owner.reload(now: epoch) }
        try expect(!owner.snapshot.available && f.absent(), "reload auto-created")
        try owner.bootstrapFreshFixture()
        try expect(try f.data() == bytes().bytes && owner.snapshot.revision == 0, "explicit bootstrap not persisted")
    }
    check("native-file: independent seed reopens exact bytes and revision") {
        let f = try ActivityFileFixture(); defer { try? f.cleanup() }; let old = try bytes([event()], revision: 8); try f.seed(old.bytes)
        try expect(try f.store().read() == old && f.store().read() == old && f.data() == old.bytes, "reopen rewrote or lost bytes")
    }
    check("native-file: absent CAS only accepts revision zero then exact next revision") {
        let f = try ActivityFileFixture(); defer { try? f.cleanup() }; let a = f.store(); let b = f.store()
        let old = try bytes(); let next = try bytes([event()], revision: 1)
        try expect(committed(try a.compareAndSwap(expected: nil, replacement: old)), "fresh CAS refused")
        try expect(try a.read() == old && b.read() == old, "independent adapters lost same bytes")
        try expect(committed(try a.compareAndSwap(expected: old, replacement: next)), "next CAS refused")
        try expect(notCommitted(try b.compareAndSwap(expected: old, replacement: bytes([], revision: 1))), "stale expected won")
        try expect(notCommitted(try b.compareAndSwap(expected: nil, replacement: old)), "nil replaced existing")
        try expect(notCommitted(try b.compareAndSwap(expected: next, replacement: next)), "duplicate revision committed")
        try expect(try f.data() == next.bytes, "losing CAS clobbered winner")
        try expect(Set(try f.names()).subtracting(["record.json", "lock"]).isEmpty, "successful CAS leaked temporary")
    }
    for initialRevision in [UInt64(1), 9, UInt64.max] {
        check("native-file: absent CAS rejects initial revision \(initialRevision)") {
            let f = try ActivityFileFixture(); defer { try? f.cleanup() }
            try expect(notCommitted(try f.store().compareAndSwap(expected: nil, replacement: bytes([], revision: initialRevision))) && f.absent(), "nonzero fresh revision accepted")
        }
    }
    for proposedRevision in [UInt64(0), 3, UInt64.max] {
        check("native-file: rejects non-successor revision \(proposedRevision)") {
            let f = try ActivityFileFixture(); defer { try? f.cleanup() }; let old = try bytes([], revision: 1); try f.seed(old.bytes)
            try expect(notCommitted(try f.store().compareAndSwap(expected: old, replacement: bytes([], revision: proposedRevision))), "revision discontinuity accepted")
            try expect(try f.data() == old.bytes, "bad revision clobbered old")
        }
    }
    check("native-file: maximum current revision never wraps") {
        let f = try ActivityFileFixture(); defer { try? f.cleanup() }; let old = try bytes([], revision: UInt64.max); try f.seed(old.bytes)
        try expect(try f.store().read() == old, "maximum revision read lost")
        try expect(notCommitted(try f.store().compareAndSwap(expected: old, replacement: bytes())), "revision wrapped")
        try expect(try f.data() == old.bytes, "overflow changed bytes")
    }
    check("native-file: exact expected bytes includes more than the revision") {
        let f = try ActivityFileFixture(); defer { try? f.cleanup() }; let old = try bytes([event()], revision: 1); try f.seed(old.bytes)
        let store = f.store()
        try expect(try store.read() == old, "safe read prerequisite")
        try expect(notCommitted(try store.compareAndSwap(expected: bytes([], revision: 1), replacement: bytes([], revision: 2))), "revision-only comparison")
        try expect(try f.data() == old.bytes, "mismatching expected clobbered")
    }
    let malformed: [(String, ActivityStoredBytes)] = [
        ("invalid JSON", ActivityStoredBytes(revision: 1, bytes: Data("{".utf8))),
        ("noncanonical newline", ActivityStoredBytes(revision: 1, bytes: try! bytes([], revision: 1).bytes + Data([10]))),
        ("revision metadata", ActivityStoredBytes(revision: 1, bytes: try! bytes([], revision: 2).bytes)),
        ("principal", try! bytes([], revision: 1, owner: "foreign-owner")),
        ("storeID", try! bytes([], revision: 1, store: otherID)),
        ("byte quota", ActivityStoredBytes(revision: 1, bytes: Data(repeating: 32, count: 2_097_153))),
        ("event quota", try! bytes((1...2001).map { event(id: String(format: "BBBBBBBB-0000-4000-8000-%012d", $0), sequence: UInt64($0)) }, revision: 1))
    ]
    for (label, proposal) in malformed {
        check("native-file: proposal \(label) refuses without changing accepted record") {
            let f = try ActivityFileFixture(); defer { try? f.cleanup() }; let old = try bytes(); try f.seed(old.bytes)
            let store = f.store(); try expect(try store.read() == old, "valid accepted read")
            try expect(notCommitted(try store.compareAndSwap(expected: old, replacement: proposal)), "invalid proposal accepted")
            try expect(try f.data() == old.bytes, "invalid proposal overwrote record")
        }
    }
    for (label, stored) in malformed where label != "revision metadata" {
        check("native-file: existing \(label) never repaired or bootstrapped") {
            let f = try ActivityFileFixture(); defer { try? f.cleanup() }; try f.seed(stored.bytes); let store = f.store()
            try checkRefusingStore(store, old: stored, next: bytes([], revision: 2))
            let owner = fileOwner(store); try refused { try owner.bootstrapFreshFixture() }
            try expect(!owner.snapshot.available && (try f.data()) == stored.bytes, "corrupt state repaired")
        }
    }
    for kind in ["symlink", "hardlink", "fifo", "directory", "mode", "special-mode", "record-acl", "root-acl", "root-mode", "lock-symlink", "lock-fifo", "lock-mode"] {
        check("native-file: unsafe \(kind) refuses without adoption or clobber") {
            let f = try ActivityFileFixture(); defer { fchmod(f.fd, 0o700); try? f.cleanup() }
            let old = try bytes(); let next = try bytes([event()], revision: 1)
            if kind == "symlink" {
                try f.seed(old.bytes, name: "keep"); try expect(symlinkat("keep", f.fd, "record.json") == 0, "symlink setup")
            } else if kind == "fifo" { try expect(mkfifoat(f.fd, "record.json", 0o600) == 0, "FIFO setup")
            } else if kind == "directory" { try expect(mkdirat(f.fd, "record.json", 0o700) == 0, "directory setup")
            } else { try f.seed(old.bytes) }
            if kind == "hardlink" { try expect(linkat(f.fd, "record.json", f.fd, "alias", 0) == 0, "hardlink setup"); f.registerOwned("alias") }
            if kind == "mode" || kind == "special-mode" { try expect(fchmodat(f.fd, "record.json", kind == "mode" ? 0o644 : 0o4600, 0) == 0, "record mode setup") }
            if kind == "root-mode" { try expect(fchmod(f.fd, 0o755) == 0, "root mode setup") }
            if kind == "root-acl" { try installAllowACL(f.fd) }
            if kind == "record-acl" {
                let child = openat(f.fd, "record.json", O_RDONLY | O_NOFOLLOW); try expect(child >= 0, "ACL record open")
                defer { close(child) }; try installAllowACL(child)
            }
            if kind == "lock-symlink" { try f.seed(Data("lock target".utf8), name: "keep"); try expect(symlinkat("keep", f.fd, "lock") == 0, "lock symlink setup") }
            if kind == "lock-fifo" { try expect(mkfifoat(f.fd, "lock", 0o600) == 0, "lock FIFO setup") }
            if kind == "lock-mode" { try f.seed(Data(), name: "lock", mode: 0o644) }
            let beforeNames = try f.names(); var before = stat()
            try expect(fstatat(f.fd, "record.json", &before, AT_SYMLINK_NOFOLLOW) == 0, "unsafe identity before")
            let store = f.store()
            if !kind.hasPrefix("lock-") { try refused { _ = try store.read() } }
            try expect(notCommitted(try store.compareAndSwap(expected: old, replacement: next)), "unsafe CAS accepted")
            var after = stat()
            try expect(fstatat(f.fd, "record.json", &after, AT_SYMLINK_NOFOLLOW) == 0 && before.st_ino == after.st_ino && before.st_dev == after.st_dev &&
                       before.st_mode == after.st_mode && before.st_nlink == after.st_nlink && (try f.names()) == beforeNames, "unsafe object repaired/replaced")
            if before.st_mode & S_IFMT == S_IFREG { try expect(try f.data() == old.bytes, "unsafe bytes changed") }
            if kind == "symlink" { try expect(try f.data("keep") == old.bytes, "symlink target changed") }
        }
    }
    check("native-file: lock contention refuses promptly and retains previous bytes") {
        let f = try ActivityFileFixture(); defer { try? f.cleanup() }; let old = try bytes(); try f.seed(old.bytes); try f.seed(Data(), name: "lock")
        let lock = openat(f.fd, "lock", O_RDWR | O_NOFOLLOW); try expect(lock >= 0, "lock open")
        defer { flock(lock, LOCK_UN); close(lock) }; try expect(flock(lock, LOCK_EX | LOCK_NB) == 0, "fixture lock")
        let begin = ProcessInfo.processInfo.systemUptime
        try expect(notCommitted(try f.store().compareAndSwap(expected: old, replacement: bytes([event()], revision: 1))), "contended write accepted")
        try expect(ProcessInfo.processInfo.systemUptime - begin < 1 && (try f.data()) == old.bytes, "blocking lock or clobber")
    }
    check("native-file: renamed retained root refuses even while original descriptor remains readable") {
        let f = try ActivityFileFixture(); defer { try? f.cleanup() }; let old = try bytes(); try f.seed(old.bytes); let store = f.store()
        try expect(try store.read() == old, "retained-root prerequisite")
        try f.withRenamed { _ in
            try checkRefusingStore(store, old: old, next: bytes([event()], revision: 1))
            try expect(try f.data() == old.bytes, "moved root changed")
        }
        try expect(try f.store().read() == old, "restored physical fixture lost")
    }
    check("native-file: nonUUID raw selector refuses without touching bytes") {
        let f = try ActivityFileFixture(); defer { try? f.cleanup() }; let old = try bytes(); try f.seed(old.bytes)
        try f.withRenamed { renamed in
            let store = FileActivityStore(fixtureRoot: FixtureActivityRoot(checkOwnedDirectory: renamed), principal: principal, storeID: storeID)
            try checkRefusingStore(store, old: old, next: bytes([event()], revision: 1))
            try expect(try f.data() == old.bytes, "invalid raw selector touched bytes")
        }
    }
    check("native-file: UUID symlink selector cannot adopt the target") {
        let f = try ActivityFileFixture(); defer { try? f.cleanup() }; let old = try bytes(); try f.seed(old.bytes)
        try f.withSymlinkSelector { selector in
            try checkRefusingStore(FileActivityStore(fixtureRoot: selector, principal: principal, storeID: storeID), old: old, next: bytes([event()], revision: 1))
            try expect(try f.data() == old.bytes, "alias followed")
        }
    }
    check("native-file: valid UUID nested selector cannot escape immediate .build confinement") {
        let f = try ActivityFileFixture(); defer { try? f.cleanup() }
        let nested = "pat2663-native-store-" + UUID().uuidString.lowercased()
        try expect(mkdirat(f.fd, nested, 0o700) == 0, "nested fixture root")
        f.registerOwned(nested)
        let store = FileActivityStore(fixtureRoot: FixtureActivityRoot(checkOwnedDirectory: f.url.appendingPathComponent(nested)), principal: principal, storeID: storeID)
        try refused { _ = try store.read() }
        try expect(notCommitted(try store.compareAndSwap(expected: nil, replacement: bytes())), "nested selector created state")
        try expect(try FileManager.default.contentsOfDirectory(atPath: f.url.appendingPathComponent(nested).path).isEmpty, "nested selector mutated")
    }
    check("native-file: replacement directory at original name cannot rebind retained adapter") {
        let f = try ActivityFileFixture(); defer { try? f.cleanup() }
        let old = try bytes(); try f.seed(old.bytes); let store = f.store()
        try expect(try store.read() == old, "replacement root safe prerequisite")
        try f.withRenamed { _ in
            try expect(mkdirat(f.parent, f.name, 0o700) == 0, "replacement root setup")
            var before = stat()
            try expect(fstatat(f.parent, f.name, &before, AT_SYMLINK_NOFOLLOW) == 0, "replacement identity")
            let result = Result {
                try checkRefusingStore(store, old: old, next: bytes([event()], revision: 1))
                try expect(try f.data() == old.bytes, "retained old root changed")
                try expect(try FileManager.default.contentsOfDirectory(atPath: f.url.path).isEmpty, "replacement root adopted")
            }
            var after = stat()
            try expect(fstatat(f.parent, f.name, &after, AT_SYMLINK_NOFOLLOW) == 0 && before.st_dev == after.st_dev &&
                       before.st_ino == after.st_ino && after.st_mode & S_IFMT == S_IFDIR, "replacement root cleanup identity")
            try expect(unlinkat(f.parent, f.name, AT_REMOVEDIR) == 0, "replacement root cleanup")
            try result.get()
        }
    }
    for fault in [FixtureActivityFault.shortWriteThenContinue, .interruptedWriteThenContinue] {
        check("native-file: \(fault.rawValue) actually reached and exact write completes") {
            let f = try ActivityFileFixture(); defer { try? f.cleanup() }; let old = try bytes(); let next = try bytes([event()], revision: 1); try f.seed(old.bytes)
            let store = f.store(fault)
            try expect(committed(try store.compareAndSwap(expected: old, replacement: next)), "recoverable write failed")
            try expect(store.exercisedFaults == [fault] && (try f.data()) == next.bytes && (try f.store().read()) == next, "write branch unexercised or partial")
        }
    }
    for fault in [FixtureActivityFault.writeFailure, .fileSync, .fullFlush, .rename] {
        check("native-file: pre-rename \(fault.rawValue) retains old and unrelated lookalike temp") {
            let f = try ActivityFileFixture(); defer { try? f.cleanup() }; let old = try bytes(); try f.seed(old.bytes)
            let foreign = "temporary-00000000-0000-0000-0000-000000000000"
            let sentinel = Data("check-owned but never adapter-owned".utf8); try f.seed(sentinel, name: foreign)
            let before = Set(try f.names()); let store = f.store(fault)
            try expect(notCommitted(try store.compareAndSwap(expected: old, replacement: bytes([event()], revision: 1))), "pre-rename failure ambiguous/committed")
            try expect(store.exercisedFaults == [fault], "pre-rename fault not reached")
            try expect(try f.data() == old.bytes && f.data(foreign) == sentinel, "old or unrelated bytes changed")
            try expect(Set(try f.names()).subtracting(["lock"]) == before, "temp leaked or broad cleanup")
        }
    }
    for fault in [FixtureActivityFault.directorySync, .afterRename, .readback] {
        check("native-file: post-rename \(fault.rawValue) uncertain never acknowledged by owner") {
            let f = try ActivityFileFixture(); defer { try? f.cleanup() }; let old = try bytes(); try f.seed(old.bytes)
            let store = f.store(fault); let owner = fileOwner(store); try owner.reload(now: epoch)
            try refused { try owner.appendSynthetic(event(), now: epoch) }
            try expect(!owner.snapshot.available && owner.snapshot.events.isEmpty, "uncertain owner acknowledged")
            try expect(store.exercisedFaults == [fault] && (try f.data()) == bytes([event()], revision: 1).bytes, "post-rename lost bytes/seam")
            let reopened = fileOwner(f.store()); try reopened.reload(now: epoch)
            try reopened.appendSynthetic(event(), now: epoch)
            try expect(reopened.snapshot.events == [event()] && reopened.snapshot.revision == 1, "uncertain replay duplicated")
        }
        check("native-file: post-rename \(fault.rawValue) primitive outcome is explicitly uncertain") {
            let f = try ActivityFileFixture(); defer { try? f.cleanup() }; let old = try bytes(); let next = try bytes([event()], revision: 1); try f.seed(old.bytes)
            let store = f.store(fault)
            try expect(uncertain(try store.compareAndSwap(expected: old, replacement: next)) && store.exercisedFaults == [fault], "post-rename outcome hidden")
            try expect(try f.data() == next.bytes && f.store().read() == next, "post-rename readback lost")
        }
    }
    check("native-file: two roots and principals remain independent and copied bytes refuse") {
        let a = try ActivityFileFixture(); let b = try ActivityFileFixture(); defer { try? a.cleanup(); try? b.cleanup() }
        let one = try bytes([event()], revision: 1); let two = try bytes([event(id: otherID, attempt: otherID)], revision: 3, owner: "fixture-owner-B", store: otherID)
        try a.seed(one.bytes); try b.seed(two.bytes)
        try expect(try a.store().read() == one && b.store(owner: "fixture-owner-B", id: otherID).read() == two && a.url != b.url, "principals mixed")
        try refused { _ = try a.store(owner: "fixture-owner-B", id: otherID).read() }
        let copied = try ActivityFileFixture(); defer { try? copied.cleanup() }; try copied.seed(one.bytes)
        let foreign = copied.store(owner: "fixture-owner-B", id: otherID)
        try checkRefusingStore(foreign, old: one, next: bytes([], revision: 2, owner: "fixture-owner-B", store: otherID))
        try expect(try copied.data() == one.bytes && b.data() == two.bytes, "cross-copy adopted/clobbered")
    }
    check("native-file: reopened synthetic correlation replay and unresolved whole-attempt retention") {
        let f = try ActivityFileFixture(); defer { try? f.cleanup() }
        let failure = event(before: "1", run: runID, transaction: transactionID)
        let unresolved = event(id: otherID, status: .needsRecovery, reason: .recoveryRequired, sequence: 2, resolved: nil, run: runID, transaction: transactionID)
        let expired = event(id: requestID, attempt: requestID, origin: .scheduled, sequence: 3)
        let owner = fileOwner(f.store()); try owner.bootstrapFreshFixture()
        for e in [failure, unresolved, expired] { try owner.appendSynthetic(e, now: epoch) }
        let reopened = fileOwner(f.store()); try reopened.reload(now: epoch + thirtyDays)
        try expect(reopened.snapshot.events == [failure, unresolved, expired], "reopen lost correlation")
        let before = try f.data(); try reopened.appendSynthetic(failure, now: epoch + thirtyDays)
        try expect(try f.data() == before, "identical replay wrote")
        try f.seed(Data("journal outside Activity authority".utf8), name: "journal-sentinel")
        try f.seed(Data("backup outside Activity authority".utf8), name: "backup-sentinel")
        try reopened.selectRetained(now: epoch + thirtyDays)
        let final = fileOwner(f.store()); try final.reload(now: epoch + thirtyDays)
        try expect(final.snapshot.events == [failure, unresolved] && final.snapshot.revision == 4, "retention lost protected attempt or failed to expire resolved")
        try expect(final.snapshot.events[0].runID == runID && final.snapshot.events[0].transactionID == transactionID && final.snapshot.events[0].beforeVersion == "1" && final.snapshot.events[0].afterVersion == nil, "observations fabricated or correlation lost")
        try expect(try f.data("journal-sentinel") == Data("journal outside Activity authority".utf8) && f.data("backup-sentinel") == Data("backup outside Activity authority".utf8), "retention removed recovery material")
        try expect(!ActivityHistoryOwner().snapshot.available, "default owner became available")
    }
}
