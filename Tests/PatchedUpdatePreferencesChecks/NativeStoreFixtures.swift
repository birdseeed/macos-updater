import Foundation
import Darwin
import PatchedScheduling
@_spi(Testing) import PatchedUpdatePreferences

/// Independent fixture IO only. Never constructs a NativePreferenceContext or calls its factory.
/// The parent later admits execution; merely declaring these fixtures performs no IO.
@MainActor final class NativeStoreFixture {
    let url: URL
    let fd: Int32
    let parent: Int32
    let name: String
    private let device: dev_t
    private let inode: ino_t
    private var cleaned = false
    static func executable() throws -> URL {
        // proc_info.h defines PROC_PIDPATHINFO_MAXSIZE as 4 * MAXPATHLEN; Swift cannot import that macro.
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let count = proc_pidpath(getpid(), &buffer, UInt32(buffer.count))
        guard count > 0 else { throw CheckFailure(message: "kernel executable path unavailable") }
        let pathBytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return URL(fileURLWithPath: String(decoding: pathBytes, as: UTF8.self)).standardizedFileURL.resolvingSymlinksInPath()
    }
    static func buildDirectory() throws -> URL {
        var cursor = try executable().deletingLastPathComponent()
        while cursor.path != "/" {
            if cursor.lastPathComponent == ".build" { return cursor }
            cursor.deleteLastPathComponent()
        }
        throw CheckFailure(message: "actual check executable is not below .build")
    }
    init() throws {
        let build = try Self.buildDirectory()
        let openedParent = open(build.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard openedParent >= 0 else { throw CheckFailure(message: "open executable .build") }
        var parentInfo = stat()
        guard fstat(openedParent, &parentInfo) == 0, parentInfo.st_uid == getuid() else {
            close(openedParent); throw CheckFailure(message: "foreign executable .build")
        }
        let ownedName = "pat2662-native-store-" + UUID().uuidString.lowercased()
        guard mkdirat(openedParent, ownedName, 0o700) == 0 else { close(openedParent); throw CheckFailure(message: "exclusive fixture root") }
        let openedRoot = openat(openedParent, ownedName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        var s = stat()
        guard openedRoot >= 0, fstat(openedRoot, &s) == 0, s.st_uid == getuid(), s.st_mode & 0o777 == 0o700,
              s.st_mode & S_IFMT == S_IFDIR else {
            if openedRoot >= 0 { close(openedRoot) }; unlinkat(openedParent, ownedName, AT_REMOVEDIR); close(openedParent)
            throw CheckFailure(message: "owned root stat")
        }
        parent = openedParent; fd = openedRoot; name = ownedName
        device = s.st_dev; inode = s.st_ino; url = build.appendingPathComponent(ownedName)
    }
    var selector: FixturePreferenceRoot { FixturePreferenceRoot(checkOwnedDirectory: url) }
    func store(_ fault: FixturePreferenceFault = .none) -> FilePreferenceStore { FilePreferenceStore(fixtureRoot: selector, fault: fault) }
    func seed(_ bytes: Data, name: String = "record.json", mode: mode_t = 0o600) throws {
        let child = openat(fd, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode)
        guard child >= 0 else { throw CheckFailure(message: "exclusive seed") }; defer { close(child) }
        let count = bytes.withUnsafeBytes { Darwin.write(child, $0.baseAddress, $0.count) }
        try require(count == bytes.count && fsync(child) == 0, "independent seed bytes")
    }
    func bytes(_ name: String = "record.json") throws -> Data {
        let child = openat(fd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard child >= 0 else { throw CheckFailure(message: "independent read") }; defer { close(child) }
        var s = stat(); try require(fstat(child, &s) == 0 && s.st_size >= 0 && s.st_size <= 1_048_577, "bounded fixture read")
        var result = Data(count: Int(s.st_size))
        let count = result.withUnsafeMutableBytes { Darwin.read(child, $0.baseAddress, $0.count) }
        try require(count == result.count, "independent full read"); return result
    }
    func absent(_ name: String = "record.json") -> Bool {
        var s = stat(); return fstatat(fd, name, &s, AT_SYMLINK_NOFOLLOW) != 0 && errno == ENOENT
    }
    func names() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: url.path).sorted() }
    /// Guards mutations/restoration against the exact held root identity, never a supplied path.
    private func requireOwnedRoot(named child: String) throws {
        var info = stat()
        try require(fstatat(parent, child, &info, AT_SYMLINK_NOFOLLOW) == 0 &&
                    info.st_dev == device && info.st_ino == inode && info.st_uid == getuid() &&
                    info.st_mode & S_IFMT == S_IFDIR, "selector fixture root identity changed")
    }
    private func requireAbsentParentChild(_ child: String) throws {
        var info = stat()
        try require(fstatat(parent, child, &info, AT_SYMLINK_NOFOLLOW) != 0 && errno == ENOENT,
                    "selector fixture destination already exists")
    }
    func withNonUUIDSelector(_ body: (FixturePreferenceRoot, URL) throws -> Void) throws {
        let badName = name + "-bad"
        try requireOwnedRoot(named: name); try requireAbsentParentChild(badName)
        try require(renameat(parent, name, parent, badName) == 0, "rename exact root for invalid selector")
        let badURL = url.deletingLastPathComponent().appendingPathComponent(badName)
        let result = Result { try body(FixturePreferenceRoot(checkOwnedDirectory: badURL), badURL) }
        // Restore only the exact root, and never replace a concurrently appearing original name.
        try requireOwnedRoot(named: badName); try requireAbsentParentChild(name)
        try require(renameat(parent, badName, parent, name) == 0, "restore exact selector root")
        try requireOwnedRoot(named: name)
        try result.get()
    }
    func withOwnedSymlinkSelector(_ body: (FixturePreferenceRoot) throws -> Void) throws {
        try requireOwnedRoot(named: name)
        let alias = "pat2662-native-store-" + UUID().uuidString.lowercased()
        try requireAbsentParentChild(alias)
        try require(symlinkat(name, parent, alias) == 0, "exclusive owned selector alias")
        var original = stat()
        try require(fstatat(parent, alias, &original, AT_SYMLINK_NOFOLLOW) == 0 &&
                    original.st_uid == getuid() && original.st_mode & S_IFMT == S_IFLNK,
                    "selector alias identity")
        let aliasURL = url.deletingLastPathComponent().appendingPathComponent(alias)
        let result = Result { try body(FixturePreferenceRoot(checkOwnedDirectory: aliasURL)) }
        var current = stat()
        try require(fstatat(parent, alias, &current, AT_SYMLINK_NOFOLLOW) == 0 &&
                    current.st_dev == original.st_dev && current.st_ino == original.st_ino &&
                    current.st_uid == getuid() && current.st_mode & S_IFMT == S_IFLNK,
                    "selector alias changed before exact unlink")
        try require(unlinkat(parent, alias, 0) == 0, "unlink exact owned selector alias")
        try requireOwnedRoot(named: name)
        try result.get()
    }
    func cleanup() throws {
        guard !cleaned else { return }
        var s = stat()
        try require(fstatat(parent, name, &s, AT_SYMLINK_NOFOLLOW) == 0 && s.st_dev == device && s.st_ino == inode, "cleanup changed root")
        // Only exact check-owned fixed children. Unknown entries remain visible and prevent removal.
        for child in ["record.json", "lock", "keep", "alias", "fifo", "child-output"] {
            if unlinkat(fd, child, 0) != 0 && errno != ENOENT { throw CheckFailure(message: "cleanup exact child \(child)") }
        }
        try require(unlinkat(parent, name, AT_REMOVEDIR) == 0, "cleanup root nonempty")
        cleaned = true; close(fd); close(parent)
    }
}

@MainActor func nativeFixtureSession(_ store: FilePreferenceStore, gen: String = generation,
                                    principal: SchedulingPrincipal = owner, scope: String = storeScope) -> PreferenceSession {
    // Existing PreferenceSession remains the only accepted record, CAS, revision, queue and policy owner.
    session(store, principal: principal, scope: scope, gen: gen)
}

/// Only a validated parent-owned .build fixture is opened by this child mode.
/// A pass is fixture process relaunch evidence, never actual account/native factory evidence.
@MainActor func nativeStoreChildDispatch() -> Bool {
    guard CommandLine.arguments.dropFirst().first == "--pat-2662-native-store-child" else { return false }
    do {
        let args = CommandLine.arguments
        try require(args.count == 3, "child exact argv")
        let root = URL(fileURLWithPath: args[2]).standardizedFileURL
        try require(root.deletingLastPathComponent() == (try NativeStoreFixture.buildDirectory()) &&
                    root.lastPathComponent.hasPrefix("pat2662-native-store-") &&
                    UUID(uuidString: String(root.lastPathComponent.dropFirst("pat2662-native-store-".count))) != nil,
                    "child owned selector")
        let rootFD = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard rootFD >= 0 else { throw CheckFailure(message: "child nofollow root") }
        defer { close(rootFD) }
        var info = stat()
        try require(fstat(rootFD, &info) == 0 && info.st_uid == getuid() && info.st_mode & 0o777 == 0o700 &&
                    root.resolvingSymlinksInPath() == root, "child physical owned root")
        let store = FilePreferenceStore(fixtureRoot: FixturePreferenceRoot(checkOwnedDirectory: root))
        let value = nativeFixtureSession(store, gen: "child-generation")
        try require(value.reload(generation: "child-generation") == .accepted(revision: 2), "child durable reload")
        let view = value.projection([PreferenceCandidate(id: "fixture", release: .verified(release))])
        try require(view.skippedCount == 1 && view.settingsExclusionCount == 1, "child durable intent")
        print("PAT2662-FIXTURE-RELAUNCH-OK"); exit(0)
    } catch { print("PAT2662-FIXTURE-RELAUNCH-FAIL \(error)"); exit(1) }
}
