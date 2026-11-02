import Foundation
import Darwin
import CryptoKit

// PAT-2583 descriptor-relative primitives for the operator root and its receipts. Every
// entry is reached by one name beneath a held directory, without following a link, and is
// confirmed to be the entry that name showed before it is used.
//
// Origin: private duplicates of this repository's own PAT-2582 primitives in
// Sources/PatchedCore/FixtureRoot.swift and Sources/PatchedCore/FixtureIO.swift, with the
// operator's typed refusals. They are duplicated so that PatchedCore exposes nothing new.

/// Physical identity of one entry. `device` is the `UInt32` bit pattern of `st_dev`.
struct OperatorIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    init(_ info: stat) { device = UInt64(UInt32(bitPattern: info.st_dev)); inode = UInt64(info.st_ino) }
}

/// What one regular file looked like when it was read: identity, size, links, mode, owner and times.
struct OperatorFileStamp: Equatable, Sendable {
    let identity: OperatorIdentity
    let byteLength: Int64
    let links: UInt64
    let mode: UInt32
    let owner: UInt32
    let modified: [Int]
    let changed: [Int]
    init(_ info: stat) {
        identity = OperatorIdentity(info); byteLength = Int64(info.st_size); links = UInt64(info.st_nlink)
        mode = UInt32(info.st_mode); owner = UInt32(info.st_uid)
        modified = [info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec]
        changed = [info.st_ctimespec.tv_sec, info.st_ctimespec.tv_nsec]
    }
}

// Retains a descriptor for `/` and for every named directory beneath it, opened without
// following links. Later operations go through these descriptors; the path is never walked
// again from the root.
final class OperatorHeldDirectories: Sendable {
    let names: [String]
    private let descriptors: [Int32]
    var directory: Int32 { descriptors.last! }
    /// Any component that cannot be held as a directory, a symlink included, is `unsafePath`.
    init(_ names: [String]) throws {
        var opened: [Int32] = []
        do {
            let root = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            guard root >= 0 else { throw OperatorFailure.unsafePath }
            opened.append(root)
            for name in names {
                let descriptor = openat(opened.last!, name, OperatorIO.directoryFlags)
                guard descriptor >= 0 else { throw OperatorFailure.unsafePath }
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
                  held.st_nlink > 0, OperatorIdentity(named) == OperatorIdentity(held) else { throw OperatorFailure.identityChanged }
        }
    }
}

enum OperatorIO {
    static let directoryFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
    static let readFlags = O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
    static let createFlags = O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC

    static func kind(_ info: stat) -> mode_t { info.st_mode & S_IFMT }
    static func permissions(_ info: stat) -> mode_t { info.st_mode & 0o7777 }
    static func sameBytes(_ lhs: String, _ rhs: String) -> Bool { lhs.utf8.elementsEqual(rhs.utf8) }
    static func hasControl<S: Sequence>(_ bytes: S) -> Bool where S.Element == UInt8 { bytes.contains { $0 < 32 || $0 == 127 } }
    static func sha256Hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// Raw components of an absolute path. Nothing is normalised: a relative path, traversal,
    /// a doubled separator or a control byte is refused, never erased.
    static func components(_ path: String) throws -> [String] {
        let bytes = Array(path.utf8)
        guard bytes.first == 47, bytes.count > 1, bytes.count < Int(PATH_MAX), !hasControl(bytes) else {
            throw OperatorFailure.unsafePath
        }
        let parts = bytes.dropFirst().split(separator: 47, omittingEmptySubsequences: false)
        guard parts.count < 64, parts.allSatisfy({
            !$0.isEmpty && $0.count <= Int(NAME_MAX) && !$0.elementsEqual([46]) && !$0.elementsEqual([46, 46])
        }) else { throw OperatorFailure.unsafePath }
        return parts.map { String(decoding: $0, as: UTF8.self) }
    }

    /// The entry at `name`, not following a link. `nil` only when no entry has that name.
    static func named(_ name: String, in directory: Int32) throws -> stat? {
        var info = stat()
        if fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 { return info }
        guard errno == ENOENT else { throw OperatorFailure.unsafePath }
        return nil
    }
    /// Opens the entry `entry` described at `name`. A swap between the two is refused.
    static func open(_ name: String, in parent: Int32, flags: Int32, entry: stat) throws -> Int32 {
        let descriptor = openat(parent, name, flags)
        guard descriptor >= 0 else { throw errno == ELOOP ? OperatorFailure.unsafePath : OperatorFailure.identityChanged }
        var info = stat()
        guard fstat(descriptor, &info) == 0, OperatorIdentity(info) == OperatorIdentity(entry), kind(info) == kind(entry) else {
            close(descriptor); throw OperatorFailure.identityChanged
        }
        return descriptor
    }

    /// An owned directory of exactly mode 0700.
    static func requirePrivateDirectory(_ info: stat) throws {
        guard kind(info) == S_IFDIR else { throw OperatorFailure.unsafePath }
        guard info.st_uid == geteuid() else { throw OperatorFailure.unsafeOwner }
        guard permissions(info) == 0o700 else { throw OperatorFailure.unsafeMode }
    }
    /// An owned single-link regular file of exactly mode 0600.
    static func requirePrivateFile(_ info: stat) throws {
        guard kind(info) != S_IFLNK else { throw OperatorFailure.unsafePath }
        guard kind(info) == S_IFREG else { throw OperatorFailure.notRegularFile }
        guard info.st_uid == geteuid() else { throw OperatorFailure.unsafeOwner }
        guard info.st_nlink == 1 else { throw OperatorFailure.hardlink }
        guard permissions(info) == 0o600 else { throw OperatorFailure.unsafeMode }
    }

    /// Reads exactly the bytes `info` promised from the start of the held file. The caller bounds
    /// `st_size` first. A file that grew, shrank or was rewritten while it was read is refused.
    static func read(_ descriptor: Int32, _ info: stat) throws -> Data {
        let size = Int(info.st_size)
        var bytes = [UInt8](repeating: 0, count: size + 1), offset = 0
        while offset <= size {
            let count = bytes.withUnsafeMutableBytes { pread(descriptor, $0.baseAddress! + offset, size + 1 - offset, off_t(offset)) }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw OperatorFailure.identityChanged }
            if count == 0 { break }
            offset += count
        }
        var after = stat()
        guard offset == size, fstat(descriptor, &after) == 0, OperatorFileStamp(after) == OperatorFileStamp(info) else {
            throw OperatorFailure.identityChanged
        }
        return Data(bytes.prefix(size))
    }
    /// SHA-256 of exactly `length` bytes read through the held descriptor, never held in memory at once.
    static func digest(_ descriptor: Int32, length: Int64) throws -> String {
        var hash = SHA256(), offset: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while true {
            let count = buffer.withUnsafeMutableBytes { pread(descriptor, $0.baseAddress!, $0.count, off_t(offset)) }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw OperatorFailure.identityChanged }
            if count == 0 { break }
            offset += Int64(count)
            guard offset <= length else { throw OperatorFailure.lengthMismatch }
            buffer.withUnsafeBytes { hash.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0.prefix(count))) }
        }
        guard offset == length else { throw OperatorFailure.lengthMismatch }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Exclusively creates the regular file `name` with mode 0600 and writes `data` to it. The
    /// caller owns the returned descriptor and flushes it. Nothing is replaced or followed.
    static func createFile(_ name: String, in directory: Int32, _ data: Data) throws -> Int32 {
        let descriptor = openat(directory, name, createFlags, 0o600)
        guard descriptor >= 0 else { throw OperatorFailure.persistenceFailed }
        do {
            guard fchmod(descriptor, 0o600) == 0 else { throw OperatorFailure.persistenceFailed }
            try data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let written = Darwin.write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                    if written < 0 && errno == EINTR { continue }
                    guard written > 0 else { throw OperatorFailure.persistenceFailed }
                    offset += written
                }
            }
            return descriptor
        } catch { close(descriptor); throw error }
    }
    /// Exclusively creates the directory `name` with mode 0700 and holds it.
    static func createDirectory(_ name: String, in parent: Int32) throws -> Int32 {
        guard mkdirat(parent, name, 0o700) == 0 else { throw OperatorFailure.persistenceFailed }
        let descriptor = openat(parent, name, directoryFlags)
        guard descriptor >= 0 else { throw OperatorFailure.persistenceFailed }
        var info = stat()
        guard fchmod(descriptor, 0o700) == 0, fstat(descriptor, &info) == 0, (try? requirePrivateDirectory(info)) != nil else {
            close(descriptor); throw OperatorFailure.persistenceFailed
        }
        return descriptor
    }
    /// fsync alone does not ask the drive to empty its volatile cache on macOS. Both must succeed;
    /// there is no weaker fallback.
    static func flush(_ descriptor: Int32) throws {
        guard fsync(descriptor) == 0, fcntl(descriptor, F_FULLFSYNC) == 0 else { throw OperatorFailure.persistenceFailed }
    }
    static func syncDirectory(_ descriptor: Int32) throws {
        guard fsync(descriptor) == 0 else { throw OperatorFailure.persistenceFailed }
    }

    /// Entry names of a held directory, read through a second description of the same directory
    /// so the held descriptor keeps no read position. `nil` when it holds more than `limit` names
    /// or a name that is not plain text.
    static func names(in directory: Int32, limit: Int) throws -> [String]? {
        let copy = openat(directory, ".", directoryFlags)
        guard copy >= 0 else { throw OperatorFailure.identityChanged }
        guard let stream = fdopendir(copy) else { close(copy); throw OperatorFailure.identityChanged }
        defer { closedir(stream) }
        var names: [String] = []
        while true {
            errno = 0
            guard let pointer = readdir(stream) else {
                guard errno == 0 else { throw OperatorFailure.identityChanged }
                return names
            }
            var entry = pointer.pointee
            let length = Int(entry.d_namlen)
            let bytes = withUnsafeBytes(of: &entry.d_name) { Array($0.prefix(length)) }
            if bytes == [46] || bytes == [46, 46] { continue }
            guard names.count < limit, !bytes.isEmpty, !bytes.contains(47), !hasControl(bytes),
                  let name = String(bytes: bytes, encoding: .utf8), Array(name.utf8) == bytes else { return nil }
            names.append(name)
        }
    }

    /// One JSON string token for text the operator writes into its own records.
    static func jsonString(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case _ where scalar.value < 32 || scalar.value == 127: result += String(format: "\\u%04x", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}
