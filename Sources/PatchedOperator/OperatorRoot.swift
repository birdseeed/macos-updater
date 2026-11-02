import Foundation
import Darwin
import CryptoKit
import PatchedCore

// PAT-2583 operator root capability. This file creates and reopens one disposable root
// beneath the build directory of the running executable and keeps it bound through held
// no-follow descriptors. It signs nothing and writes no catalogue.
//
// Limits, stated rather than closed: the build directory is a trusted same-user namespace.
// A same-user process that substitutes an entry before its first capture here, restores an
// earlier complete checkpoint, or changes something after the last confirmation of an
// operation is not detected. Explicit trust is supplied by the caller every time; the
// namespace record names identifiers only and there is no default trust.
//
// Origin: the scoping and held-chain logic follows this repository's own PAT-2582
// Sources/PatchedCore/FixtureRoot.swift, duplicated privately with the operator's refusals.

final class OperatorRoot: Sendable {
    static let namePrefix = "patched-operator-fixture-"
    static let namespaceName = "namespace.json"
    static let checkpointName = "checkpoint.json"
    static let lockName = "lock"
    static let inputName = "input"
    static let publicationsName = "publications"
    /// The only other name a root may hold: a checkpoint temporary left by an interrupted
    /// operation, kept as uncertain evidence. It is never read as state, adopted or deleted.
    static let temporaryPrefix = "checkpoint.json.pending-"
    static let temporarySuffixBytes = 32
    static let maximumRootEntries = 64

    let path: String
    let trust: FixtureTrust
    /// Held for as long as this root is alive. Every path is reached through these.
    let directory: Int32
    let input: Int32
    let publications: Int32
    private let build: OperatorHeldDirectories
    private let name: String
    private let namespace: Int32
    private let lock: Int32
    /// The process-local operation lease of this held root: tried, never waited for, not reentrant.
    private let operation = NSLock()

    private init(path: String, trust: FixtureTrust, build: OperatorHeldDirectories, name: String, directory: Int32,
                 input: Int32, publications: Int32, namespace: Int32, lock: Int32) {
        self.path = path; self.trust = trust; self.build = build; self.name = name; self.directory = directory
        self.input = input; self.publications = publications; self.namespace = namespace; self.lock = lock
    }
    deinit { for descriptor in [lock, namespace, publications, input, directory] { close(descriptor) } }

    /// Exclusively creates the named root with its fixed entries and the empty high-water mark.
    /// A root left incomplete by a failure is preserved: it is never repaired, adopted or deleted.
    /// `observer` is test-only: it is told which real step just finished and may refuse.
    static func create(path: String, trust: FixtureTrust,
                       observer: ((OperatorRootCreationPoint) throws -> Void)? = nil) throws -> OperatorRoot {
        try validate(trust)
        let (build, name) = try scope(path)
        // The held chain must outlive every use of its raw descriptors, including on refusal.
        defer { withExtendedLifetime(build) {} }
        guard mkdirat(build.directory, name, 0o700) == 0 else {
            guard errno == EEXIST else { throw OperatorFailure.persistenceFailed }
            let entry = try OperatorIO.named(name, in: build.directory)
            throw entry.map(OperatorIO.kind) == S_IFLNK ? OperatorFailure.unsafePath : OperatorFailure.existingNamespace
        }
        var opened: [Int32] = []
        do {
            let directory = openat(build.directory, name, OperatorIO.directoryFlags)
            guard directory >= 0 else { throw OperatorFailure.persistenceFailed }
            opened.append(directory)
            var info = stat()
            guard fchmod(directory, 0o700) == 0, fstat(directory, &info) == 0 else { throw OperatorFailure.persistenceFailed }
            try OperatorIO.requirePrivateDirectory(info)
            // The held root must be the named entry beneath the confirmed chain before anything is
            // written into it, so no record lands in a substituted directory.
            try build.confirm()
            guard let entry = try OperatorIO.named(name, in: build.directory), OperatorIdentity(entry) == OperatorIdentity(info) else {
                throw OperatorFailure.identityChanged
            }
            // From here every mutation, flush and directory sync is preceded and followed by the same
            // check, and so is every observer report: a root that left its name gains nothing more.
            var created: [CreatedEntry] = []
            let captured = OperatorIdentity(info)
            func still() throws {
                try confirmCreating(build: build, name: name, directory: directory, captured: captured, created: created)
            }
            try still()
            try OperatorIO.syncDirectory(build.directory)
            try still()
            try observer?(.rootCaptured)
            try still()
            let input = try OperatorIO.createDirectory(inputName, in: directory); opened.append(input)
            created.append(CreatedEntry(name: inputName, descriptor: input, bytes: nil))
            try still()
            try observer?(.inputCreated)
            try still()
            let publications = try OperatorIO.createDirectory(publicationsName, in: directory); opened.append(publications)
            created.append(CreatedEntry(name: publicationsName, descriptor: publications, bytes: nil))
            try still()
            try observer?(.publicationsCreated)
            try still()
            let lock = try OperatorIO.createFile(lockName, in: directory, Data()); opened.append(lock)
            created.append(CreatedEntry(name: lockName, descriptor: lock, bytes: Data()))
            guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw OperatorFailure.busy }
            try still()
            try OperatorIO.flush(lock)
            try still()
            try observer?(.lockFlushed)
            try still()
            let initial = OperatorState.Checkpoint(keyID: trust.keyID, catalogueID: trust.catalogueID, sequence: 0,
                                                   payloadSHA256: OperatorState.zeroDigest)
            let checkpoint = try OperatorIO.createFile(checkpointName, in: directory, OperatorState.checkpointBytes(initial))
            opened.append(checkpoint)
            created.append(CreatedEntry(name: checkpointName, descriptor: checkpoint, bytes: OperatorState.checkpointBytes(initial),
                                        record: { try OperatorState.checkpoint($0) == initial }))
            try still()
            try OperatorIO.flush(checkpoint)
            try still()
            try observer?(.checkpointFlushed)
            try still()
            // The namespace record is written last: a root without it was never completed.
            let record = OperatorState.namespaceBytes(keyID: trust.keyID, catalogueID: trust.catalogueID)
            let namespace = try OperatorIO.createFile(namespaceName, in: directory, record); opened.append(namespace)
            created.append(CreatedEntry(name: namespaceName, descriptor: namespace, bytes: record, record: {
                let named = try OperatorState.namespace($0)
                return OperatorIO.sameBytes(named.keyID, trust.keyID) && OperatorIO.sameBytes(named.catalogueID, trust.catalogueID)
            }))
            try still()
            try OperatorIO.flush(namespace)
            try still()
            try observer?(.namespaceFlushed)
            try still()
            for descriptor in [input, publications, directory, build.directory] {
                try OperatorIO.syncDirectory(descriptor)
                try still()
            }
            try observer?(.directoriesSynced)
            try still()
            // The committed files are flushed in full once more now that their names are durable.
            for descriptor in [checkpoint, namespace] {
                guard fcntl(descriptor, F_FULLFSYNC) == 0 else { throw OperatorFailure.persistenceFailed }
                try still()
            }
            guard flock(lock, LOCK_UN) == 0 else { throw OperatorFailure.persistenceFailed }
            close(checkpoint); opened.removeAll { $0 == checkpoint }
            let root = OperatorRoot(path: path, trust: trust, build: build, name: name, directory: directory, input: input,
                                    publications: publications, namespace: namespace, lock: lock)
            opened = []
            // Accepted only when the records read back from disk are the ones just written.
            var marker = stat()
            guard try root.confirm() == initial, fstat(namespace, &marker) == 0, try OperatorIO.read(namespace, marker) == record else {
                throw OperatorFailure.persistenceFailed
            }
            return root
        } catch { for descriptor in opened { close(descriptor) }; throw error }
    }

    /// One entry creation has made so far: its name, its held descriptor and, for a file, the
    /// exact bytes written to it. `nil` bytes mean a directory.
    private struct CreatedEntry {
        let name: String
        let descriptor: Int32
        let bytes: Data?
        /// For a state record: the strict reading of those bytes still names this creation's values.
        var record: ((Data) throws -> Bool)? = nil
    }

    /// The check creation makes at each of its own boundaries, before the fixed entries all exist
    /// and `confirm()` can run. The build chain and the captured root are still the held entries at
    /// their names; the root holds exactly the names created so far; each is still its held
    /// descriptor with the required owner, mode and link count; and each file reads back as the
    /// exact record written. Nothing is repaired, removed or adopted on refusal.
    private static func confirmCreating(build: OperatorHeldDirectories, name: String, directory: Int32, captured: OperatorIdentity,
                                        created: [CreatedEntry]) throws {
        try build.confirm()
        try confirmDirectory(directory, name, in: build.directory)
        var info = stat()
        guard fstat(directory, &info) == 0, OperatorIdentity(info) == captured else { throw OperatorFailure.identityChanged }
        guard let names = try OperatorIO.names(in: directory, limit: maximumRootEntries), names.count == created.count,
              names.allSatisfy({ name in created.contains { OperatorIO.sameBytes($0.name, name) } }) else {
            throw OperatorFailure.corruptState
        }
        for entry in created {
            guard let bytes = entry.bytes else {
                try confirmDirectory(entry.descriptor, entry.name, in: directory)
                continue
            }
            let marker = try confirmFile(entry.descriptor, entry.name, in: directory)
            guard Int(marker.st_size) == bytes.count else { throw OperatorFailure.corruptState }
            let read = try OperatorIO.read(entry.descriptor, marker)
            guard read == bytes, try entry.record?(read) ?? true else { throw OperatorFailure.corruptState }
        }
        // The same physical root is still at its name once every entry has been read.
        try build.confirm()
        try confirmDirectory(directory, name, in: build.directory)
    }

    /// Resumes an existing root without changing it. Missing, altered or unsafe state is refused
    /// and never recreated or healed.
    static func reopen(path: String, trust: FixtureTrust) throws -> OperatorRoot {
        try validate(trust)
        let (build, name) = try scope(path)
        defer { withExtendedLifetime(build) {} }
        var opened: [Int32] = []
        do {
            let directory = try holdDirectory(name, in: build.directory); opened.append(directory)
            let input = try holdDirectory(inputName, in: directory); opened.append(input)
            let publications = try holdDirectory(publicationsName, in: directory); opened.append(publications)
            let lock = try holdFile(lockName, in: directory).0; opened.append(lock)
            let namespace = try holdFile(namespaceName, in: directory).0; opened.append(namespace)
            let root = OperatorRoot(path: path, trust: trust, build: build, name: name, directory: directory, input: input,
                                    publications: publications, namespace: namespace, lock: lock)
            opened = []
            try root.confirm()
            return root
        } catch { for descriptor in opened { close(descriptor) }; throw error }
    }

    /// The check made at every operation boundary. The build chain, the root, its directories,
    /// the lock and the namespace record are still the held entries at their names with the
    /// required owner, mode and link count; the namespace record still names this trust; and the
    /// checkpoint at its name is a complete strict record. Returns that checkpoint as read.
    @discardableResult func confirm() throws -> OperatorState.Checkpoint {
        try build.confirm()
        try Self.confirmDirectory(directory, name, in: build.directory)
        try Self.confirmDirectory(input, Self.inputName, in: directory)
        try Self.confirmDirectory(publications, Self.publicationsName, in: directory)
        guard try Self.confirmFile(lock, Self.lockName, in: directory).st_size == 0 else { throw OperatorFailure.corruptState }
        let marker = try Self.confirmFile(namespace, Self.namespaceName, in: directory)
        guard marker.st_size <= OperatorLimits.maximumStateBytes else { throw OperatorFailure.corruptState }
        let recorded = try OperatorState.namespace(try OperatorIO.read(namespace, marker))
        guard OperatorIO.sameBytes(recorded.keyID, trust.keyID) else { throw OperatorFailure.untrustedKey }
        guard OperatorIO.sameBytes(recorded.catalogueID, trust.catalogueID) else { throw OperatorFailure.wrongCatalogue }
        let (descriptor, info) = try Self.holdFile(Self.checkpointName, in: directory)
        defer { close(descriptor) }
        guard info.st_size > 0, info.st_size <= OperatorLimits.maximumStateBytes else { throw OperatorFailure.corruptState }
        let checkpoint = try OperatorState.checkpoint(try OperatorIO.read(descriptor, info))
        guard OperatorIO.sameBytes(checkpoint.keyID, trust.keyID), OperatorIO.sameBytes(checkpoint.catalogueID, trust.catalogueID) else {
            throw OperatorFailure.corruptState
        }
        try confirmEntries()
        return checkpoint
    }

    /// Mutations hold two leases and never wait for either. The first is this held root's own
    /// process-local operation lease. `flock` belongs to the open file description, so the
    /// descriptor held here would be granted its own kernel lock again and a nested release would
    /// drop the outer operation's lock; an operation entered through this root while another is
    /// inside it, from a signer or a hook included, is therefore refused as busy before any state
    /// is read, before the kernel lock is touched and before `body`. The second is the exclusive
    /// advisory lock on the held lock file, which refuses other open file descriptions of it:
    /// another process, or this root reopened. The lock file stays held by descriptor and the lock
    /// itself is released between operations. The lock and the namespace record must be the held
    /// entries at their names before the lock is taken and again once it is held. A refusal inside
    /// `body` is reported as it was raised and the lock is released as far as it can be; a result
    /// is returned only when the release itself succeeded. The operation lease is given up on every
    /// exit, and only by the attempt that took it.
    ///
    /// Limits, stated rather than closed: both leases are cooperative. Neither sandboxes this
    /// process nor stops a same-user process that ignores the advisory lock.
    func locked<T>(_ body: () throws -> T) throws -> T {
        guard operation.try() else { throw OperatorFailure.busy }
        defer { operation.unlock() }
        try confirm()
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw errno == EWOULDBLOCK ? OperatorFailure.busy : OperatorFailure.persistenceFailed }
        let result: T
        do {
            try confirm()
            result = try body()
        } catch { _ = flock(lock, LOCK_UN); throw error }
        guard flock(lock, LOCK_UN) == 0 else { throw OperatorFailure.persistenceFailed }
        return result
    }

    /// A root holds its five fixed names and, at most, bounded private checkpoint temporaries.
    /// Any other entry is unexplained state: it is refused and left exactly where it is.
    private func confirmEntries() throws {
        guard let names = try OperatorIO.names(in: directory, limit: Self.maximumRootEntries) else { throw OperatorFailure.corruptState }
        let fixed = [Self.namespaceName, Self.checkpointName, Self.lockName, Self.inputName, Self.publicationsName]
        for name in names where !fixed.contains(where: { OperatorIO.sameBytes($0, name) }) {
            let suffix = name.utf8.dropFirst(Self.temporaryPrefix.utf8.count)
            guard name.utf8.starts(with: Self.temporaryPrefix.utf8), suffix.count == Self.temporarySuffixBytes,
                  suffix.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw OperatorFailure.corruptState }
            guard let entry = try OperatorIO.named(name, in: directory) else { continue }
            try OperatorIO.requirePrivateFile(entry)
            guard entry.st_size <= OperatorLimits.maximumStateBytes else { throw OperatorFailure.corruptState }
        }
    }

    /// Identifier bounds and a well-formed 32-byte public key, checked before any path is touched.
    private static func validate(_ trust: FixtureTrust) throws {
        guard OperatorState.validIdentifier(trust.keyID), OperatorState.validIdentifier(trust.catalogueID), trust.publicKey.count == 32,
              (try? Curve25519.Signing.PublicKey(rawRepresentation: trust.publicKey)) != nil else { throw OperatorFailure.untrustedKey }
    }

    /// Holds the build directory of the running executable and accepts `path` only as a correctly
    /// named direct child of it. Nothing is written here.
    private static func scope(_ path: String) throws -> (OperatorHeldDirectories, String) {
        let parts = try OperatorIO.components(path)
        let name = parts.last!, parent = Array(parts.dropLast())
        let suffix = Array(name.utf8.dropFirst(namePrefix.utf8.count))
        guard name.utf8.starts(with: namePrefix.utf8), (1...64).contains(suffix.count), suffix.allSatisfy({
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
        }) else { throw OperatorFailure.unsafePath }
        let build = try executableBuildDirectory()
        // The caller's own spelling of the parent is walked only to refuse it precisely. It grants
        // nothing: authority rests on the chain held from the executable.
        let named = try OperatorHeldDirectories(parent)
        try withExtendedLifetime(named) {
            var requested = stat(), held = stat()
            guard parent.count == build.names.count, zip(parent, build.names).allSatisfy(OperatorIO.sameBytes),
                  fstat(named.directory, &requested) == 0, fstat(build.directory, &held) == 0,
                  OperatorIdentity(requested) == OperatorIdentity(held) else { throw OperatorFailure.unsafePath }
        }
        try build.confirm()
        return (build, name)
    }

    /// The nearest `.build` ancestor of the running executable, from the kernel's record of the
    /// executable vnode. The working directory, `argv[0]` and the caller's path play no part.
    private static func executableBuildDirectory() throws -> OperatorHeldDirectories {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(getpid(), &buffer, UInt32(buffer.count))
        guard length > 0, Int(length) < buffer.count,
              let parts = try? OperatorIO.components(String(decoding: buffer.prefix(Int(length)), as: UTF8.self)),
              let index = parts.dropLast().lastIndex(where: { OperatorIO.sameBytes($0, ".build") }) else {
            throw OperatorFailure.unsafePath
        }
        let build = try OperatorHeldDirectories(Array(parts[...index]))
        defer { withExtendedLifetime(build) {} }
        // The executable must physically be a regular file beneath the held directory.
        var descriptors: [Int32] = []
        defer { for descriptor in descriptors { close(descriptor) } }
        var current = build.directory
        for part in parts[(index + 1)...].dropLast() {
            current = openat(current, part, OperatorIO.directoryFlags)
            guard current >= 0 else { throw OperatorFailure.unsafePath }
            descriptors.append(current)
        }
        var executable = stat(), info = stat()
        guard fstatat(current, parts.last!, &executable, AT_SYMLINK_NOFOLLOW) == 0,
              OperatorIO.kind(executable) == S_IFREG, fstat(build.directory, &info) == 0 else { throw OperatorFailure.unsafePath }
        guard info.st_uid == geteuid() else { throw OperatorFailure.unsafeOwner }
        guard info.st_mode & 0o022 == 0 else { throw OperatorFailure.unsafeMode }
        return build
    }

    /// Holds the owned mode-0700 directory at `name`. The caller owns the descriptor.
    private static func holdDirectory(_ name: String, in parent: Int32) throws -> Int32 {
        guard let entry = try OperatorIO.named(name, in: parent) else { throw OperatorFailure.missingState }
        try OperatorIO.requirePrivateDirectory(entry)
        return try OperatorIO.open(name, in: parent, flags: OperatorIO.directoryFlags, entry: entry)
    }
    /// Holds the owned single-link mode-0600 regular file at `name`, refusing a link or a special
    /// file before any open. The caller owns the descriptor.
    static func holdFile(_ name: String, in parent: Int32) throws -> (Int32, stat) {
        guard let entry = try OperatorIO.named(name, in: parent) else { throw OperatorFailure.missingState }
        try OperatorIO.requirePrivateFile(entry)
        let descriptor = try OperatorIO.open(name, in: parent, flags: OperatorIO.readFlags, entry: entry)
        var info = stat()
        guard fstat(descriptor, &info) == 0, (try? OperatorIO.requirePrivateFile(info)) != nil else {
            close(descriptor); throw OperatorFailure.identityChanged
        }
        return (descriptor, info)
    }
    /// `name` is still the held directory, with the required owner and mode.
    static func confirmDirectory(_ held: Int32, _ name: String, in parent: Int32) throws {
        guard let entry = try OperatorIO.named(name, in: parent) else { throw OperatorFailure.missingState }
        guard OperatorIO.kind(entry) == S_IFDIR else { throw OperatorFailure.unsafePath }
        var info = stat()
        guard fstat(held, &info) == 0, info.st_nlink > 0, OperatorIdentity(info) == OperatorIdentity(entry) else {
            throw OperatorFailure.identityChanged
        }
        try OperatorIO.requirePrivateDirectory(info)
    }
    /// `name` is still the held regular file, with the required owner, mode and single link.
    static func confirmFile(_ held: Int32, _ name: String, in parent: Int32) throws -> stat {
        guard let entry = try OperatorIO.named(name, in: parent) else { throw OperatorFailure.missingState }
        guard OperatorIO.kind(entry) != S_IFLNK else { throw OperatorFailure.unsafePath }
        guard OperatorIO.kind(entry) == S_IFREG else { throw OperatorFailure.notRegularFile }
        var info = stat()
        guard fstat(held, &info) == 0, info.st_nlink > 0, OperatorIdentity(info) == OperatorIdentity(entry) else {
            throw OperatorFailure.identityChanged
        }
        try OperatorIO.requirePrivateFile(info)
        return info
    }
}
