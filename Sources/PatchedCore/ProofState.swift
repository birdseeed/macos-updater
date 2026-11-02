import Foundation
import Darwin

// Descriptors retain every directory in the path, so replacing an ancestor or
// namespace cannot redirect a later relative open or silently detach a commit.
private final class DirectoryChain {
    let descriptors: [Int32]
    let names: [String]
    // A child chain keeps its original ancestors alive and closes only `owned`.
    private let ancestors: DirectoryChain?
    private let owned: [Int32]
    var directory: Int32 { descriptors.last! }
    init(path: String, missing: CoreFailure) throws {
        let parts = try Self.parts(path)
        var opened: [Int32] = []
        do {
            let root = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            guard root >= 0 else { throw CoreFailure.unsafePath }
            opened.append(root)
            for part in parts {
                let descriptor = openat(opened.last!, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
                guard descriptor >= 0 else { throw errno == ENOENT ? missing : CoreFailure.unsafePath }
                opened.append(descriptor)
            }
        } catch { for descriptor in opened { close(descriptor) }; throw error }
        descriptors = opened; names = parts; ancestors = nil; owned = opened
    }
    // Opens one child through the held parent descriptor. The path is never
    // walked again from the root, so the original ancestors stay authoritative.
    init(parent: DirectoryChain, child: String, missing: CoreFailure) throws {
        let descriptor = openat(parent.directory, child, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw errno == ENOENT ? missing : CoreFailure.unsafePath }
        descriptors = parent.descriptors + [descriptor]; names = parent.names + [child]
        ancestors = parent; owned = [descriptor]
    }
    deinit { for descriptor in owned { close(descriptor) } }
    static func parts(_ path: String) throws -> [String] {
        guard path.hasPrefix("/"), path != "/", path.utf8.count < 4096, !path.contains("\0") else { throw CoreFailure.unsafePath }
        let parts = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count < 256, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw CoreFailure.unsafePath }
        return parts
    }
    func confirm(failure: CoreFailure) throws {
        for index in names.indices {
            var named = stat(), held = stat()
            guard fstatat(descriptors[index], names[index], &named, AT_SYMLINK_NOFOLLOW) == 0,
                  fstat(descriptors[index + 1], &held) == 0,
                  named.st_mode & S_IFMT == S_IFDIR, held.st_nlink > 0,
                  named.st_dev == held.st_dev, named.st_ino == held.st_ino else { throw failure }
        }
    }
}

private func safeStat(_ descriptor: Int32, directory: Bool = false, failure: CoreFailure = .unsafePath) throws -> stat {
    var info = stat()
    guard fstat(descriptor, &info) == 0, info.st_uid == geteuid(),
          info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG),
          info.st_mode & 0o7777 == (directory ? 0o700 : 0o600),
          directory || info.st_nlink == 1 else { throw failure }
    return info
}
private func confirmedFile(_ descriptor: Int32, name: String, directory: Int32, failure: CoreFailure) throws {
    let held = try safeStat(descriptor, failure: failure)
    var named = stat()
    guard fstatat(directory, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
          named.st_dev == held.st_dev, named.st_ino == held.st_ino else { throw failure }
}
private func writeAll(_ data: Data, to descriptor: Int32) throws {
    try data.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
            let written = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
            if written < 0 && errno == EINTR { continue }
            guard written > 0 else { throw CoreFailure.persistenceFailed }
            offset += written
        }
    }
}
private func sync(_ descriptor: Int32) throws {
    guard fsync(descriptor) == 0 else { throw CoreFailure.persistenceFailed }
}
private func createFile(_ name: String, in directory: Int32) throws -> Int32 {
    let descriptor = openat(directory, name, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw CoreFailure.persistenceFailed }
    do {
        guard fchmod(descriptor, 0o600) == 0 else { throw CoreFailure.persistenceFailed }
        _ = try safeStat(descriptor, failure: .persistenceFailed)
        return descriptor
    } catch { close(descriptor); throw error }
}
private func openFile(_ name: String, in directory: Int32, write: Bool = false) throws -> Int32 {
    let descriptor = openat(directory, name, (write ? O_RDWR : O_RDONLY) | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard descriptor >= 0 else { throw errno == ENOENT ? CoreFailure.missingState : CoreFailure.unsafePath }
    do { _ = try safeStat(descriptor); return descriptor }
    catch { close(descriptor); throw error }
}
private func readFile(_ descriptor: Int32) throws -> Data {
    let before = try safeStat(descriptor)
    guard before.st_size > 0, before.st_size <= 8192, lseek(descriptor, 0, SEEK_SET) == 0 else { throw CoreFailure.corruptState }
    var bytes = Data(), buffer = [UInt8](repeating: 0, count: 1024)
    while true {
        let count = Darwin.read(descriptor, &buffer, buffer.count)
        if count < 0 && errno == EINTR { continue }
        guard count >= 0 else { throw CoreFailure.corruptState }
        if count == 0 { break }
        guard bytes.count + count <= 8192 else { throw CoreFailure.corruptState }
        bytes.append(contentsOf: buffer.prefix(count))
    }
    let after = try safeStat(descriptor)
    guard Int64(bytes.count) == before.st_size, before.st_size == after.st_size,
          before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
          before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else {
        throw CoreFailure.corruptState
    }
    return bytes
}

private struct Marker: Encodable {
    let schemaVersion = 1
    let namespace = "patched-fixture-state-v1"
    let keyID: String
    let catalogueID: String
}
private struct Checkpoint: Encodable {
    let schemaVersion = 1
    let keyID: String
    let catalogueID: String
    let sequence: UInt64
    let payloadSHA256: String
}

final class ProofState {
    private let chain: DirectoryChain
    private let trust: FixtureTrust
    private let lock: Int32
    private let marker: Int32
    private let originalMarker: Data
    private var checkpoint: Int32?
    private var originalCheckpoint: Data?

    private init(chain: DirectoryChain, trust: FixtureTrust, lock: Int32, marker: Int32,
                 markerBytes: Data, checkpoint: Int32?, checkpointBytes: Data?) {
        self.chain = chain; self.trust = trust; self.lock = lock; self.marker = marker
        originalMarker = markerBytes; self.checkpoint = checkpoint; originalCheckpoint = checkpointBytes
    }
    deinit {
        if let checkpoint { close(checkpoint) }
        close(marker); close(lock)
    }

    static func open(path: String, trust: FixtureTrust) throws -> ProofState {
        let chain = try DirectoryChain(path: path, missing: .missingState)
        _ = try safeStat(chain.directory, directory: true)
        let lock = try openFile("lock", in: chain.directory, write: true)
        var marker: Int32?, checkpoint: Int32?
        var transferred = false
        do {
            let info = try safeStat(lock)
            guard info.st_size == 0 else { throw CoreFailure.corruptState }
            guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw errno == EWOULDBLOCK ? CoreFailure.stateBusy : CoreFailure.unsafePath }
            let markerFD = try openFile("namespace.json", in: chain.directory); marker = markerFD
            let checkpointFD = try openFile("checkpoint.json", in: chain.directory); checkpoint = checkpointFD
            let markerBytes = try readFile(markerFD), checkpointBytes = try readFile(checkpointFD)
            let state = ProofState(chain: chain, trust: trust, lock: lock, marker: markerFD,
                                   markerBytes: markerBytes, checkpoint: checkpointFD, checkpointBytes: checkpointBytes)
            // Ownership transfers to state before further throwing operations.
            transferred = true
            try state.validateMarker(markerBytes)
            _ = try state.decodeCheckpoint(checkpointBytes)
            try state.confirm(failure: .unsafePath)
            return state
        } catch {
            if !transferred {
                if let marker { close(marker) }
                if let checkpoint { close(checkpoint) }
                close(lock)
            }
            throw error
        }
    }

    static func bootstrap(path: String, trust: FixtureTrust,
                          boundary: ((BootstrapBoundary) throws -> Void)? = nil) throws -> ProofState {
        let parts = try DirectoryChain.parts(path)
        guard parts.count > 1 else { throw CoreFailure.unsafePath }
        let parentPath = "/" + parts.dropLast().joined(separator: "/")
        let parent = try DirectoryChain(path: parentPath, missing: .unsafePath)
        try parent.confirm(failure: .unsafePath)
        guard mkdirat(parent.directory, parts.last!, 0o700) == 0 else {
            throw errno == EEXIST ? CoreFailure.existingNamespace : CoreFailure.unsafePath
        }
        // Failed bootstraps preserve the incomplete namespace. Explicit bootstrap
        // can never silently reuse or erase it on a subsequent attempt.
        try sync(parent.directory)
        try boundary?(.namespaceCreated)
        // The child is opened through the held parent. Every original ancestor
        // and the held child must still be the named entries before any file is
        // created, so nothing is written into a substituted replacement. A
        // same-user swap of the child before this first open is not detectable.
        let chain = try DirectoryChain(parent: parent, child: parts.last!, missing: .persistenceFailed)
        try chain.confirm(failure: .unsafePath)
        _ = try safeStat(chain.directory, directory: true)
        let lock = try createFile("lock", in: chain.directory)
        var marker: Int32?
        do {
            guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw CoreFailure.persistenceFailed }
            try sync(lock)
            try chain.confirm(failure: .unsafePath)
            let markerFD = try createFile("namespace.json", in: chain.directory); marker = markerFD
            let bytes = try JSONEncoder().encode(Marker(keyID: trust.keyID, catalogueID: trust.catalogueID))
            try writeAll(bytes, to: markerFD); try sync(markerFD)
            let state = ProofState(chain: chain, trust: trust, lock: lock, marker: markerFD,
                                   markerBytes: bytes, checkpoint: nil, checkpointBytes: nil)
            marker = nil
            return state
        } catch { if let marker { close(marker) }; close(lock); throw error }
    }

    private func validateMarker(_ bytes: Data) throws {
        let value = try CoreJSON.object(bytes, maximum: 8192, failure: .corruptState)
        try CoreJSON.keys(value, ["schemaVersion", "namespace", "keyID", "catalogueID"], failure: .corruptState)
        guard value["schemaVersion"]?.unsigned == 1, value["namespace"]?.string == "patched-fixture-state-v1",
              value["keyID"]?.string == trust.keyID, value["catalogueID"]?.string == trust.catalogueID else { throw CoreFailure.corruptState }
    }
    private func decodeCheckpoint(_ bytes: Data) throws -> Checkpoint {
        let value = try CoreJSON.object(bytes, maximum: 8192, failure: .corruptState)
        try CoreJSON.keys(value, ["schemaVersion", "keyID", "catalogueID", "sequence", "payloadSHA256"], failure: .corruptState)
        guard value["schemaVersion"]?.unsigned == 1, value["keyID"]?.string == trust.keyID,
              value["catalogueID"]?.string == trust.catalogueID, let sequence = value["sequence"]?.unsigned, sequence > 0,
              let hash = value["payloadSHA256"]?.string, validDigest(hash) else { throw CoreFailure.corruptState }
        return Checkpoint(keyID: trust.keyID, catalogueID: trust.catalogueID, sequence: sequence, payloadSHA256: hash)
    }
    private func confirm(failure: CoreFailure, includeCheckpoint: Bool = true) throws {
        do {
            try chain.confirm(failure: failure)
            _ = try safeStat(chain.directory, directory: true, failure: failure)
            try confirmedFile(lock, name: "lock", directory: chain.directory, failure: failure)
            try confirmedFile(marker, name: "namespace.json", directory: chain.directory, failure: failure)
            guard try readFile(marker) == originalMarker else { throw failure }
            if includeCheckpoint {
                if let checkpoint {
                    try confirmedFile(checkpoint, name: "checkpoint.json", directory: chain.directory, failure: failure)
                    guard try readFile(checkpoint) == originalCheckpoint else { throw failure }
                } else {
                    var info = stat()
                    guard fstatat(chain.directory, "checkpoint.json", &info, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else { throw failure }
                }
            }
        } catch { throw failure }
    }

    func accept(_ candidate: CatalogueCandidate, probe: ((PersistenceStage) throws -> Void)?,
                syncProbe: ((PersistenceSyncOperation) throws -> Void)?) throws {
        try confirm(failure: .unsafePath)
        if let originalCheckpoint {
            let previous = try decodeCheckpoint(originalCheckpoint)
            guard candidate.sequence >= previous.sequence,
                  candidate.sequence != previous.sequence || candidate.payloadSHA256 == previous.payloadSHA256 else { throw CoreFailure.replay }
        }
        let value = Checkpoint(keyID: trust.keyID, catalogueID: trust.catalogueID,
                               sequence: candidate.sequence, payloadSHA256: candidate.payloadSHA256)
        let encoded = try JSONEncoder().encode(value)
        let temporaryName = "checkpoint-pending-" + UUID().uuidString + ".json"
        let temporary = try createFile(temporaryName, in: chain.directory)
        defer { close(temporary) }
        do {
            try writeAll(encoded, to: temporary)
            try probe?(.temporaryWritten)
            try confirm(failure: .persistenceFailed)
            try syncProbe?(.fileSync)
            try sync(temporary)
            try syncProbe?(.fileFullSync)
            // fsync alone does not request a flush of the drive's volatile cache
            // on macOS. No weaker fallback is permitted if full flush fails.
            guard fcntl(temporary, F_FULLFSYNC) == 0 else { throw CoreFailure.persistenceFailed }
            try probe?(.fileSynced)
            try confirm(failure: .persistenceFailed)
            try probe?(.beforeRename)
            try confirm(failure: .persistenceFailed)
            try confirmedFile(temporary, name: temporaryName, directory: chain.directory, failure: .persistenceFailed)
            guard try readFile(temporary) == encoded else { throw CoreFailure.persistenceFailed }
            guard renameat(chain.directory, temporaryName, chain.directory, "checkpoint.json") == 0 else { throw CoreFailure.persistenceFailed }
            try probe?(.renamed)
            try confirm(failure: .persistenceFailed, includeCheckpoint: false)
            try confirmedFile(temporary, name: "checkpoint.json", directory: chain.directory, failure: .persistenceFailed)
            try syncProbe?(.directorySync)
            try sync(chain.directory)
            try syncProbe?(.committedFileFullSync)
            // Flush the regular checkpoint again after persisting its directory
            // entry. Directory fsync is retained; no drive guarantee is invented.
            guard fcntl(temporary, F_FULLFSYNC) == 0 else { throw CoreFailure.persistenceFailed }
            try probe?(.directorySynced)
            try confirm(failure: .persistenceFailed, includeCheckpoint: false)
            try confirmedFile(temporary, name: "checkpoint.json", directory: chain.directory, failure: .persistenceFailed)
            guard try readFile(temporary) == encoded else { throw CoreFailure.persistenceFailed }
        } catch { throw CoreFailure.persistenceFailed }
    }
}
