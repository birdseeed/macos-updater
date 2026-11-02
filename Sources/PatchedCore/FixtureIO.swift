import Foundation
import Darwin
import CryptoKit

// PAT-2582 descriptor-relative primitives for the fixture transaction. Every
// entry is reached by one name beneath a held directory, without following a
// link, and is confirmed to be the entry that name showed before it is used.
// Nothing here opens an absolute path.

/// Physical identity of one entry. `device` is the `UInt32` bit pattern of `st_dev`.
struct EntryIdentity: Equatable {
    let device: UInt64
    let inode: UInt64
    init(device: UInt64, inode: UInt64) { self.device = device; self.inode = inode }
    init(_ info: stat) { device = UInt64(UInt32(bitPattern: info.st_dev)); inode = UInt64(info.st_ino) }
}

func sha256Hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

enum FixtureIO {
    static let directoryFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
    static let readFlags = O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
    static let createFlags = O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC

    static func kind(_ info: stat) -> mode_t { info.st_mode & S_IFMT }
    static func permissions(_ info: stat) -> mode_t { info.st_mode & 0o7777 }
    /// An ASCII control byte makes a name ambiguous in the line-based tree digest and unreadable.
    static func hasControl<S: Sequence>(_ bytes: S) -> Bool where S.Element == UInt8 { bytes.contains { $0 < 32 || $0 == 127 } }

    /// The entry at `name`, not following a link. `nil` only when no entry has that name.
    static func named(_ name: String, in directory: Int32) throws -> stat? {
        var info = stat()
        if fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 { return info }
        guard errno == ENOENT else { throw TransactionFailure.unsafePath }
        return nil
    }
    /// A held descriptor that still has a name somewhere.
    static func held(_ descriptor: Int32) throws -> stat {
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_nlink > 0 else { throw TransactionFailure.identityChanged }
        return info
    }
    /// `name` is still the entry held by `descriptor`.
    static func confirm(_ descriptor: Int32, named name: String, in directory: Int32) throws -> stat {
        let info = try held(descriptor)
        guard let entry = try? named(name, in: directory), EntryIdentity(entry) == EntryIdentity(info),
              kind(entry) == kind(info) else { throw TransactionFailure.identityChanged }
        return info
    }

    /// Opens the directory at `name`. The caller owns the returned descriptor.
    static func openDirectory(_ name: String, in parent: Int32, missing: TransactionFailure) throws -> (Int32, stat) {
        guard let entry = try named(name, in: parent) else { throw missing }
        guard kind(entry) != S_IFLNK else { throw TransactionFailure.symlink }
        guard kind(entry) == S_IFDIR else { throw TransactionFailure.notDirectory }
        return try open(name, in: parent, flags: directoryFlags, entry: entry)
    }
    /// Opens the regular file at `name` for reading. A FIFO or device is refused before any open.
    static func openFile(_ name: String, in parent: Int32, missing: TransactionFailure) throws -> (Int32, stat) {
        guard let entry = try named(name, in: parent) else { throw missing }
        guard kind(entry) != S_IFLNK else { throw TransactionFailure.symlink }
        guard kind(entry) == S_IFREG else { throw TransactionFailure.specialFile }
        return try open(name, in: parent, flags: readFlags, entry: entry)
    }
    private static func open(_ name: String, in parent: Int32, flags: Int32, entry: stat) throws -> (Int32, stat) {
        let descriptor = openat(parent, name, flags)
        guard descriptor >= 0 else { throw errno == ELOOP ? TransactionFailure.symlink : TransactionFailure.identityChanged }
        var info = stat()
        // The opened entry must be the one the name showed: a swap between the two is refused.
        guard fstat(descriptor, &info) == 0, EntryIdentity(info) == EntryIdentity(entry), kind(info) == kind(entry) else {
            close(descriptor); throw TransactionFailure.identityChanged
        }
        return (descriptor, info)
    }

    static func requireDirectory(_ info: stat, modes: [mode_t]) throws {
        guard kind(info) == S_IFDIR else { throw TransactionFailure.notDirectory }
        guard info.st_uid == geteuid() else { throw TransactionFailure.unsafeOwner }
        guard modes.contains(permissions(info)) else { throw TransactionFailure.unsafeMode }
    }
    static func requireFile(_ info: stat, modes: [mode_t]) throws {
        guard kind(info) == S_IFREG else { throw TransactionFailure.specialFile }
        guard info.st_uid == geteuid() else { throw TransactionFailure.unsafeOwner }
        guard info.st_nlink == 1 else { throw TransactionFailure.hardlink }
        guard modes.contains(permissions(info)) else { throw TransactionFailure.unsafeMode }
    }

    /// Reads exactly the bytes `info` promised. The caller bounds `st_size` first. A file that grew,
    /// shrank or was rewritten while it was read is refused rather than returned.
    static func read(_ descriptor: Int32, _ info: stat) throws -> Data {
        let size = Int(info.st_size)
        var bytes = [UInt8](repeating: 0, count: size + 1), offset = 0
        while offset <= size {
            let count = bytes.withUnsafeMutableBytes { pread(descriptor, $0.baseAddress! + offset, size + 1 - offset, off_t(offset)) }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw TransactionFailure.identityChanged }
            if count == 0 { break }
            offset += count
        }
        var after = stat()
        guard offset == size, fstat(descriptor, &after) == 0, EntryIdentity(after) == EntryIdentity(info),
              after.st_size == info.st_size, after.st_nlink == info.st_nlink, after.st_mode == info.st_mode,
              after.st_mtimespec.tv_sec == info.st_mtimespec.tv_sec, after.st_mtimespec.tv_nsec == info.st_mtimespec.tv_nsec,
              after.st_ctimespec.tv_sec == info.st_ctimespec.tv_sec, after.st_ctimespec.tv_nsec == info.st_ctimespec.tv_nsec else {
            throw TransactionFailure.identityChanged
        }
        return Data(bytes.prefix(size))
    }
    static func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { throw TransactionFailure.persistenceFailed }
                offset += written
            }
        }
    }
    /// fsync alone does not ask the drive to empty its volatile cache on macOS. Both must succeed;
    /// there is no weaker fallback.
    static func flush(_ descriptor: Int32) throws {
        guard fsync(descriptor) == 0, fcntl(descriptor, F_FULLFSYNC) == 0 else { throw TransactionFailure.persistenceFailed }
    }

    /// Entry names of a held directory, read through a second description of the same directory so
    /// the held descriptor keeps no read position. More than `limit` names is `treeLimit`.
    static func names(in directory: Int32, limit: Int) throws -> [String] {
        let copy = openat(directory, ".", directoryFlags)
        guard copy >= 0 else { throw TransactionFailure.identityChanged }
        guard let stream = fdopendir(copy) else { close(copy); throw TransactionFailure.identityChanged }
        defer { closedir(stream) }
        var names: [String] = []
        while true {
            errno = 0
            guard let pointer = readdir(stream) else {
                guard errno == 0 else { throw TransactionFailure.identityChanged }
                return names
            }
            var entry = pointer.pointee
            let length = Int(entry.d_namlen)
            let bytes = withUnsafeBytes(of: &entry.d_name) { Array($0.prefix(length)) }
            if bytes == [46] || bytes == [46, 46] { continue }
            // A name must survive the round trip through a string byte for byte.
            guard !bytes.isEmpty, !bytes.contains(0), !bytes.contains(47), !hasControl(bytes),
                  let name = String(bytes: bytes, encoding: .utf8), Array(name.utf8) == bytes else {
                throw TransactionFailure.unsafePath
            }
            guard names.count < limit else { throw TransactionFailure.treeLimit }
            names.append(name)
        }
    }
}
