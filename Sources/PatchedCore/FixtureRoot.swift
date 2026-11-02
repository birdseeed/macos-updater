import Foundation
import Darwin

// PAT-2582 fixture root authority. This file creates and reopens one disposable
// root beneath the build directory of the running executable, and keeps it bound
// for a transaction. It holds no journal, stage, replacement or recovery logic.
//
// A same-user process that substitutes an entry before its first capture here,
// or rewrites the root and its marker consistently, is not detected. The build
// directory is a trusted same-user temporary namespace.

private let directoryFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC

func sameBytes(_ lhs: String, _ rhs: String) -> Bool { lhs.utf8.elementsEqual(rhs.utf8) }
private func sameEntry(_ lhs: stat, _ rhs: stat) -> Bool { lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino }
private func isSymlink(_ name: String, in directory: Int32) -> Bool {
    var info = stat()
    return fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 && info.st_mode & S_IFMT == S_IFLNK
}

/// Raw components of an absolute path. Nothing is normalised: a hazard is refused, never erased.
func rawComponents(_ path: String) throws -> [String] {
    let bytes = Array(path.utf8)
    guard bytes.first == 47, bytes.count > 1, bytes.count < Int(PATH_MAX), !bytes.contains(0) else {
        throw TransactionFailure.unsafePath
    }
    let parts = bytes.dropFirst().split(separator: 47, omittingEmptySubsequences: false)
    guard parts.count < 64, parts.allSatisfy({
        !$0.isEmpty && $0.count <= Int(NAME_MAX) && !$0.elementsEqual([46]) && !$0.elementsEqual([46, 46])
    }) else { throw TransactionFailure.unsafePath }
    return parts.map { String(decoding: $0, as: UTF8.self) }
}

// Retains a descriptor for `/` and for every named directory beneath it, opened
// without following links. Later operations go through these descriptors; the
// path is never walked again from the root.
private final class HeldDirectories {
    let names: [String]
    private let descriptors: [Int32]
    var directory: Int32 { descriptors.last! }
    /// A symlinked component is `symlink`; any other component that cannot be held is `refusal`.
    init(_ names: [String], refusal: TransactionFailure) throws {
        var opened: [Int32] = []
        do {
            let root = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            guard root >= 0 else { throw refusal }
            opened.append(root)
            for name in names {
                let descriptor = openat(opened.last!, name, directoryFlags)
                guard descriptor >= 0 else { throw isSymlink(name, in: opened.last!) ? TransactionFailure.symlink : refusal }
                opened.append(descriptor)
            }
        } catch { for descriptor in opened { close(descriptor) }; throw error }
        self.names = names; descriptors = opened
    }
    deinit { for descriptor in descriptors { close(descriptor) } }
    /// Every held directory is still the entry at its name beneath its held parent.
    func confirm() throws {
        for index in names.indices {
            var named = stat(), held = stat()
            guard fstatat(descriptors[index], names[index], &named, AT_SYMLINK_NOFOLLOW) == 0,
                  fstat(descriptors[index + 1], &held) == 0, named.st_mode & S_IFMT == S_IFDIR,
                  held.st_nlink > 0, sameEntry(named, held) else { throw TransactionFailure.identityChanged }
        }
    }
}

/// One disposable fixture root and the descriptors that bind it: the build directory chain of the
/// running executable, the root directory and its marker. It grants a temporary-fixture capability
/// only, never OS trust or installation authority.
final class FixtureRootHandle {
    static let namePrefix = "patched-transaction-fixture-"
    static let markerName = "fixture-root.json"
    static let markerKind = "patched-transaction-fixture-root-v1"
    static let maximumMarkerBytes = 512

    private let build: HeldDirectories
    private let name: String
    private let directory: Int32
    private let marker: Int32
    private init(build: HeldDirectories, name: String, directory: Int32, marker: Int32) {
        self.build = build; self.name = name; self.directory = directory; self.marker = marker
    }
    deinit { close(marker); close(directory) }

    /// The held root directory. It stays open for as long as this handle is alive; a transaction
    /// reaches every path through it and never walks the caller's absolute path again.
    var descriptor: Int32 { directory }

    /// The build chain, the root and the marker are still the entries at their names, and the
    /// marker still records the identity of the held root. Returns the root as physically observed.
    @discardableResult func confirm() throws -> stat {
        try Self.confirm(build, name, directory, marker: marker)
        let info = try Self.rootStatus(directory)
        guard Self.records(info, try Self.read(marker)) else { throw TransactionFailure.notAuthorized }
        return info
    }

    /// Exclusively creates the named root. An incomplete root left by a failure is preserved:
    /// it is never repaired, adopted or deleted here.
    static func create(path: String) throws -> FixtureRootHandle {
        let (build, name) = try scope(path)
        // The held chain must outlive every use of its raw descriptors, including on refusal.
        defer { withExtendedLifetime(build) {} }
        guard mkdirat(build.directory, name, 0o700) == 0 else {
            guard errno == EEXIST else { throw TransactionFailure.persistenceFailed }
            throw isSymlink(name, in: build.directory) ? TransactionFailure.symlink : TransactionFailure.existingRoot
        }
        var directory: Int32 = -1, marker: Int32 = -1
        do {
            directory = openat(build.directory, name, directoryFlags)
            guard directory >= 0 else { throw TransactionFailure.persistenceFailed }
            let info = try rootStatus(directory)
            // The held root must be the named entry beneath the confirmed chain before anything is
            // written into it, so no marker lands in a substituted directory.
            try confirm(build, name, directory)
            guard fsync(build.directory) == 0 else { throw TransactionFailure.persistenceFailed }
            marker = openat(directory, markerName, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
            guard marker >= 0, fchmod(marker, 0o600) == 0 else { throw TransactionFailure.persistenceFailed }
            _ = try markerStatus(marker)
            let bytes = Data(("{\"schemaVersion\":1,\"kind\":\"\(markerKind)\",\"device\":\(UInt32(bitPattern: info.st_dev))," +
                              "\"inode\":\(UInt64(info.st_ino))}").utf8)
            try write(bytes, to: marker)
            // fsync alone does not request a flush of the drive's volatile cache on macOS.
            // No weaker fallback is permitted if the full flush fails.
            guard fsync(marker) == 0, fcntl(marker, F_FULLFSYNC) == 0, fsync(directory) == 0 else {
                throw TransactionFailure.persistenceFailed
            }
            try confirm(build, name, directory, marker: marker)
            guard try read(marker) == bytes else { throw TransactionFailure.persistenceFailed }
            return FixtureRootHandle(build: build, name: name, directory: directory, marker: marker)
        } catch {
            if marker >= 0 { close(marker) }
            if directory >= 0 { close(directory) }
            throw error
        }
    }

    /// Resumes an existing root without changing it. The marker must record the identity of the
    /// directory physically observed, so a marker copied into another directory grants nothing.
    static func reopen(path: String) throws -> FixtureRootHandle {
        let (build, name) = try scope(path)
        // The held chain must outlive every use of its raw descriptors, including on refusal.
        defer { withExtendedLifetime(build) {} }
        let directory = openat(build.directory, name, directoryFlags)
        guard directory >= 0 else {
            throw isSymlink(name, in: build.directory) ? TransactionFailure.symlink : TransactionFailure.notAuthorized
        }
        var marker: Int32 = -1
        do {
            let info = try rootStatus(directory)
            marker = openat(directory, markerName, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard marker >= 0 else {
                throw isSymlink(markerName, in: directory) ? TransactionFailure.symlink : TransactionFailure.notAuthorized
            }
            _ = try markerStatus(marker)
            guard records(info, try read(marker)) else { throw TransactionFailure.notAuthorized }
            try confirm(build, name, directory, marker: marker)
            return FixtureRootHandle(build: build, name: name, directory: directory, marker: marker)
        } catch {
            if marker >= 0 { close(marker) }
            close(directory)
            throw error
        }
    }

    /// Holds the build directory of the running executable and accepts `path` only as a correctly
    /// named direct child of it. Nothing is written here.
    private static func scope(_ path: String) throws -> (HeldDirectories, String) {
        let parts = try rawComponents(path)
        let name = parts.last!, parent = Array(parts.dropLast())
        let suffix = Array(name.utf8.dropFirst(namePrefix.utf8.count))
        guard name.utf8.starts(with: namePrefix.utf8), (1...64).contains(suffix.count), suffix.allSatisfy({
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
        }) else { throw TransactionFailure.unsafePath }
        let build = try executableBuildDirectory()
        // The caller's own spelling of the parent is walked only to refuse it precisely. It grants
        // nothing: authority rests on the chain held from the executable.
        let named = try HeldDirectories(parent, refusal: .notAuthorized)
        try withExtendedLifetime(named) {
            var requested = stat(), held = stat()
            guard parent.count == build.names.count, zip(parent, build.names).allSatisfy(sameBytes),
                  fstat(named.directory, &requested) == 0, fstat(build.directory, &held) == 0,
                  sameEntry(requested, held) else { throw TransactionFailure.notAuthorized }
        }
        try build.confirm()
        return (build, name)
    }

    /// The nearest `.build` ancestor of the running executable, from the kernel's record of the
    /// executable vnode. The working directory, `argv[0]` and the caller's path play no part.
    private static func executableBuildDirectory() throws -> HeldDirectories {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(getpid(), &buffer, UInt32(buffer.count))
        guard length > 0, Int(length) < buffer.count,
              let parts = try? rawComponents(String(decoding: buffer.prefix(Int(length)), as: UTF8.self)),
              let index = parts.dropLast().lastIndex(where: { sameBytes($0, ".build") }) else {
            throw TransactionFailure.notAuthorized
        }
        do {
            let build = try HeldDirectories(Array(parts[...index]), refusal: .notAuthorized)
            defer { withExtendedLifetime(build) {} }
            // The executable must physically be a regular file beneath the held directory.
            var descriptors: [Int32] = []
            defer { for descriptor in descriptors { close(descriptor) } }
            var current = build.directory
            for part in parts[(index + 1)...].dropLast() {
                current = openat(current, part, directoryFlags)
                guard current >= 0 else { throw TransactionFailure.notAuthorized }
                descriptors.append(current)
            }
            var executable = stat(), info = stat()
            guard fstatat(current, parts.last!, &executable, AT_SYMLINK_NOFOLLOW) == 0,
                  executable.st_mode & S_IFMT == S_IFREG, fstat(build.directory, &info) == 0 else {
                throw TransactionFailure.notAuthorized
            }
            guard info.st_uid == geteuid() else { throw TransactionFailure.unsafeOwner }
            guard info.st_mode & 0o022 == 0 else { throw TransactionFailure.unsafeMode }
            return build
        } catch TransactionFailure.symlink { throw TransactionFailure.notAuthorized }
    }

    /// Strict marker document naming exactly the observed root identity.
    private static func records(_ info: stat, _ bytes: Data) -> Bool {
        guard let fields = try? CoreJSON.object(bytes, maximum: maximumMarkerBytes, failure: .corruptState),
              Set(fields.keys) == ["schemaVersion", "kind", "device", "inode"],
              fields["schemaVersion"]?.unsigned == 1, fields["kind"]?.string.map({ sameBytes($0, markerKind) }) == true,
              fields["device"]?.unsigned == UInt64(UInt32(bitPattern: info.st_dev)),
              fields["inode"]?.unsigned == UInt64(info.st_ino) else { return false }
        return true
    }
    private static func rootStatus(_ directory: Int32) throws -> stat {
        var info = stat()
        guard fstat(directory, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { throw TransactionFailure.notDirectory }
        guard info.st_uid == geteuid() else { throw TransactionFailure.unsafeOwner }
        guard info.st_mode & 0o7777 == 0o700 else { throw TransactionFailure.unsafeMode }
        return info
    }
    private static func markerStatus(_ marker: Int32) throws -> stat {
        var info = stat()
        guard fstat(marker, &info) == 0 else { throw TransactionFailure.notAuthorized }
        guard info.st_mode & S_IFMT == S_IFREG else { throw TransactionFailure.specialFile }
        guard info.st_uid == geteuid() else { throw TransactionFailure.unsafeOwner }
        guard info.st_nlink == 1 else { throw TransactionFailure.hardlink }
        guard info.st_mode & 0o7777 == 0o600 else { throw TransactionFailure.unsafeMode }
        return info
    }
    /// The chain, the root and (when given) the marker are still the entries at their names.
    private static func confirm(_ build: HeldDirectories, _ name: String, _ directory: Int32, marker: Int32? = nil) throws {
        try build.confirm()
        var named = stat(), held = try rootStatus(directory)
        guard fstatat(build.directory, name, &named, AT_SYMLINK_NOFOLLOW) == 0, sameEntry(named, held) else {
            throw TransactionFailure.identityChanged
        }
        if let marker {
            held = try markerStatus(marker)
            guard fstatat(directory, markerName, &named, AT_SYMLINK_NOFOLLOW) == 0, sameEntry(named, held) else {
                throw TransactionFailure.identityChanged
            }
        }
    }
    private static func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { throw TransactionFailure.persistenceFailed }
                offset += written
            }
        }
    }
    /// Bounded read from the start of the held marker. An oversized marker grants nothing.
    private static func read(_ marker: Int32) throws -> Data {
        var bytes = Data(), buffer = [UInt8](repeating: 0, count: maximumMarkerBytes + 1)
        while bytes.count <= maximumMarkerBytes {
            let count = pread(marker, &buffer, buffer.count - bytes.count, off_t(bytes.count))
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw TransactionFailure.notAuthorized }
            if count == 0 { return bytes }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        throw TransactionFailure.notAuthorized
    }
}
