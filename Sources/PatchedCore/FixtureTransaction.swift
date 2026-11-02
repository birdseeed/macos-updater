import Foundation
import Darwin

// PAT-2582 reversible bundle transaction inside one fixture root. It is reached
// only through `FixtureAuthority`; the default entries never construct it.
//
// Every path is reached through the root descriptor that the authority holds.
// The root, its marker and every held directory are confirmed to be the entries
// at their names after each test hook and before each mutation. So are the
// incoming directory, the source bundle and the artifact that `perform` read:
// their bytes are not read again, but their names must still show them. A refusal after
// transaction state exists undoes nothing in place and deletes nothing: the
// journal, both frozen manifests, any private journal file that was being
// written and both bundles stay as evidence for `recover`. A private journal
// file is never removed, even one whose write failed, because removal would be
// one more unverified change to the evidence directory.
//
// Limits that remain: a same-user process can substitute an entry before its
// first capture, rewrite the journal and both bundles consistently, or replace
// a name between the last confirmation and the exchange. The checks after the
// exchange then match no recorded state and the transaction fails closed.
// Successful flush calls are not a guarantee against hardware or power loss.

final class FixtureTransaction {
    private enum Position { case unchecked, absent, entry(EntryIdentity) }
    private struct Stage {
        let listing: TreeListing
        let contents: [Data?]
        let children: [[Int]]
        var identities: [EntryIdentity?]
    }
    /// Journal, frozen manifests and both bundle positions as physically read under the lock.
    private struct Evidence {
        var record: JournalRecord
        let before: ManifestDocument
        let after: ManifestDocument
        let target: PhysicalBundle?
        let exchanged: PhysicalBundle?
        func isOld(_ bundle: PhysicalBundle?) -> Bool {
            guard let bundle else { return false }
            return bundle.identity == record.old && bundle.listing.matches(before.listing)
        }
        func isNew(_ bundle: PhysicalBundle?) -> Bool {
            guard let bundle, let new = record.new else { return false }
            return bundle.identity == new && bundle.listing.matches(after.listing)
        }
    }

    private let handle: FixtureRootHandle
    private let root: String
    private let base: [String]
    private let hooks: FixtureHooks
    // Descriptors owned here are closed once, when the transaction object is released.
    private var owned: [Int32] = []
    private var applications: Int32 = -1, transaction: Int32 = -1, exchange: Int32 = -1, lock: Int32 = -1
    // The current `journal.json`; replaced, and the previous one closed, at each record.
    private var journal: Int32 = -1
    // The bundle directories held at each of the two names, and the identity expected there.
    private var atTarget: Int32 = -1, atExchange: Int32 = -1
    private var targetPosition = Position.unchecked, exchangePosition = Position.unchecked
    private var name = ""
    // The incoming side as `perform` captured it. Recovery holds none of these.
    private var incoming: Int32 = -1, sourceRoot: Int32 = -1, artifact: Int32 = -1
    private var artifactName = ""

    init(handle: FixtureRootHandle, root: String, hooks: FixtureHooks) throws {
        self.handle = handle; self.root = root; self.hooks = hooks; base = try rawComponents(root)
    }
    deinit {
        for descriptor in owned { close(descriptor) }
        if journal >= 0 { close(journal) }
    }

    /// Keeps the transaction and its descriptors alive for the whole call and lets only typed refusals out.
    static func run(_ handle: FixtureRootHandle, _ root: String, _ hooks: FixtureHooks,
                    _ body: (FixtureTransaction) throws -> TransactionReport) throws -> TransactionReport {
        do {
            let transaction = try FixtureTransaction(handle: handle, root: root, hooks: hooks)
            return try withExtendedLifetime(transaction) { try body(transaction) }
        } catch let refusal as TransactionFailure { throw refusal } catch { throw TransactionFailure.persistenceFailed }
    }

    // MARK: Request shape. Strings only; nothing here touches the filesystem.

    private func same(_ lhs: [String], _ rhs: [String]) -> Bool { lhs.count == rhs.count && zip(lhs, rhs).allSatisfy(sameBytes) }
    private func child(_ parts: [String], of directory: String) -> String? {
        guard parts.count == base.count + 2, same(Array(parts.prefix(base.count)), base), sameBytes(parts[base.count], directory) else { return nil }
        return parts[base.count + 1]
    }
    private func isTransactionDirectory(_ parts: [String]) -> Bool { same(parts, base + ["Transaction"]) }

    /// Accepts only the authority's own layout. Sets the bundle name and returns the artifact name.
    private func shape(_ request: UpdateRequest) throws -> String {
        guard request.trigger == .explicitUserAction else { throw TransactionFailure.userTriggerRequired }
        let target = try rawComponents(request.target), source = try rawComponents(request.sourceBundle)
        let artifact = try rawComponents(request.artifactPath), directory = try rawComponents(request.transactionDirectory)
        guard !(target + source + artifact + directory).contains(where: { FixtureIO.hasControl($0.utf8) }) else { throw TransactionFailure.unsafePath }
        guard !same(source, target), !same(artifact, source), !same(artifact, target) else { throw TransactionFailure.aliasedPath }
        guard let bundle = child(target, of: "Applications"), validBundleName(bundle),
              let incoming = child(source, of: "Incoming"), sameBytes(incoming, bundle),
              let pinned = child(artifact, of: "Incoming"), isTransactionDirectory(directory) else { throw TransactionFailure.notAuthorized }
        name = bundle
        return pinned
    }

    // MARK: Held identities and test hooks.

    /// The root, its marker and every held entry are still what their names show.
    private func confirm() throws {
        try handle.confirm()
        if applications >= 0 { try confirmPrivate(applications, "Applications", in: handle.descriptor) }
        if transaction >= 0 { try confirmPrivate(transaction, "Transaction", in: handle.descriptor) }
        if exchange >= 0 { try confirmPrivate(exchange, "exchange", in: transaction) }
        if lock >= 0 { try confirmPrivateFile(lock, "lock") }
        if journal >= 0 { try confirmPrivateFile(journal, "journal.json") }
        try confirm(targetPosition, atTarget, in: applications)
        try confirm(exchangePosition, atExchange, in: exchange)
        if incoming >= 0 { try confirmPrivate(incoming, "Incoming", in: handle.descriptor) }
        if sourceRoot >= 0 {
            let info = try FixtureIO.confirm(sourceRoot, named: name, in: incoming)
            guard FixtureIO.kind(info) == S_IFDIR, info.st_uid == geteuid(),
                  BundleTree.directoryModes.contains(FixtureIO.permissions(info)) else { throw TransactionFailure.identityChanged }
        }
        if artifact >= 0 {
            let info = try FixtureIO.confirm(artifact, named: artifactName, in: incoming)
            guard FixtureIO.kind(info) == S_IFREG, info.st_uid == geteuid(), info.st_nlink == 1,
                  BundleTree.fileModes.contains(FixtureIO.permissions(info)) else { throw TransactionFailure.identityChanged }
        }
    }
    private func confirmPrivate(_ descriptor: Int32, _ entry: String, in parent: Int32) throws {
        let info = try FixtureIO.confirm(descriptor, named: entry, in: parent)
        guard FixtureIO.kind(info) == S_IFDIR, info.st_uid == geteuid(), FixtureIO.permissions(info) == 0o700 else {
            throw TransactionFailure.identityChanged
        }
    }
    private func confirmPrivateFile(_ descriptor: Int32, _ entry: String) throws {
        let info = try FixtureIO.confirm(descriptor, named: entry, in: transaction)
        guard FixtureIO.kind(info) == S_IFREG, info.st_uid == geteuid(), info.st_nlink == 1, FixtureIO.permissions(info) == 0o600 else {
            throw TransactionFailure.identityChanged
        }
    }
    private func confirm(_ position: Position, _ descriptor: Int32, in parent: Int32) throws {
        switch position {
        case .unchecked: return
        case .absent:
            let found: stat?
            do { found = try FixtureIO.named(name, in: parent) } catch { throw TransactionFailure.identityChanged }
            guard found == nil else { throw TransactionFailure.identityChanged }
        case .entry(let identity):
            let info = try FixtureIO.confirm(descriptor, named: name, in: parent)
            guard FixtureIO.kind(info) == S_IFDIR, EntryIdentity(info) == identity else { throw TransactionFailure.identityChanged }
        }
    }
    private func require(_ succeeded: Bool) throws { guard succeeded else { throw TransactionFailure.persistenceFailed } }

    /// A probe can observe or refuse. Whatever it throws, the result is `persistenceFailed`.
    private func boundary(_ boundary: TransactionBoundary) throws {
        do { try hooks.boundary?(boundary) } catch { throw TransactionFailure.persistenceFailed }
        try confirm()
    }
    /// Probe, confirmation, then the synchronisation itself. A failure has no weaker fallback.
    private func sync(_ operation: TransactionSyncOperation, _ descriptor: Int32, full: Bool = false) throws {
        do { try hooks.sync?(operation) } catch { throw TransactionFailure.persistenceFailed }
        try confirm()
        try require(fsync(descriptor) == 0 && (!full || fcntl(descriptor, F_FULLFSYNC) == 0))
    }
    /// The fixture declaration only. It is never an OS observation, and nothing is quit.
    private func refuseIfRunning(_ bundleID: String) throws {
        let open = hooks.applicationRunning(bundleID)
        guard !open else { throw TransactionFailure.appRunning }
        try confirm()
    }

    private func openPrivate(_ entry: String, in parent: Int32, missing: TransactionFailure, device: dev_t) throws -> Int32 {
        let (descriptor, info) = try FixtureIO.openDirectory(entry, in: parent, missing: missing)
        owned.append(descriptor)
        try FixtureIO.requireDirectory(info, modes: [0o700])
        guard info.st_dev == device else { throw TransactionFailure.crossVolume }
        return descriptor
    }
    /// Holds a private directory this transaction has just exclusively created.
    private func holdCreated(_ entry: String, in parent: Int32) throws -> (Int32, stat) {
        let descriptor = openat(parent, entry, FixtureIO.directoryFlags)
        try require(descriptor >= 0)
        owned.append(descriptor)
        let info = try FixtureIO.confirm(descriptor, named: entry, in: parent)
        guard FixtureIO.kind(info) == S_IFDIR, info.st_uid == geteuid(), FixtureIO.permissions(info) == 0o700 else {
            throw TransactionFailure.persistenceFailed
        }
        return (descriptor, info)
    }

    // MARK: Journal and frozen manifests.

    /// A frozen manifest is written once, exclusively, before any journal exists. The directory
    /// entry becomes durable with the first journal record.
    private func freeze(_ bytes: Data, as file: String) throws {
        try confirm()
        let descriptor = openat(transaction, file, FixtureIO.createFlags, 0o600)
        try require(descriptor >= 0)
        defer { close(descriptor) }
        try FixtureIO.write(bytes, to: descriptor)
        try sync(.journalFileFullSync, descriptor, full: true)
        let info = try FixtureIO.confirm(descriptor, named: file, in: transaction)
        try FixtureIO.requireFile(info, modes: [0o600])
        try require(try FixtureIO.read(descriptor, info) == bytes)
    }

    /// New private file, full flush, atomic rename over `journal.json`, directory flush, then a
    /// second full flush through the retained descriptor so the rename is ordered behind the bytes.
    /// A failure after the rename leaves the new record visible but unreported: the caller gets
    /// `persistenceFailed` and `recover` decides from what is physically present.
    private func persist(_ record: JournalRecord) throws {
        let bytes = record.encoded
        try require(bytes.count <= TransactionLimits.maximumJournalBytes)
        try confirm()
        let temporary = "journal." + UUID().uuidString + ".tmp"
        let descriptor = openat(transaction, temporary, FixtureIO.createFlags, 0o600)
        try require(descriptor >= 0)
        var installed = false
        defer { if !installed { close(descriptor) } }
        try FixtureIO.write(bytes, to: descriptor)
        try sync(.journalFileFullSync, descriptor, full: true)
        try FixtureIO.requireFile(try FixtureIO.confirm(descriptor, named: temporary, in: transaction), modes: [0o600])
        if journal < 0 {
            try require(renameatx_np(transaction, temporary, transaction, "journal.json", UInt32(RENAME_EXCL)) == 0)
        } else {
            try require(renameat(transaction, temporary, transaction, "journal.json") == 0)
            close(journal)
        }
        journal = descriptor; installed = true
        try sync(.journalDirectorySync, transaction)
        try require(fcntl(journal, F_FULLFSYNC) == 0)
        try require(try FixtureIO.read(journal, try FixtureIO.held(journal)) == bytes)
    }

    // MARK: Stage and exchange.

    private func copy(_ index: Int, into directory: Int32, _ stage: inout Stage) throws {
        for child in stage.children[index] {
            let entry = stage.listing.entries[child], leaf = TreeListing.leaf(entry.path)
            try confirm()
            if entry.isDirectory {
                try require(mkdirat(directory, leaf, 0o700) == 0)
                let opened = openat(directory, leaf, FixtureIO.directoryFlags)
                try require(opened >= 0)
                defer { close(opened) }
                let info = try FixtureIO.confirm(opened, named: leaf, in: directory)
                try require(FixtureIO.kind(info) == S_IFDIR && info.st_uid == geteuid() && fchmod(opened, mode_t(entry.mode)) == 0)
                stage.identities[child] = EntryIdentity(info)
                try copy(child, into: opened, &stage)
            } else {
                guard let data = stage.contents[child] else { throw TransactionFailure.persistenceFailed }
                let opened = openat(directory, leaf, FixtureIO.createFlags, 0o600)
                try require(opened >= 0)
                defer { close(opened) }
                try FixtureIO.write(data, to: opened)
                try require(fchmod(opened, mode_t(entry.mode)) == 0)
                stage.identities[child] = EntryIdentity(try FixtureIO.confirm(opened, named: leaf, in: directory))
            }
        }
    }
    /// Full flush of every staged file, then `fsync` of every staged directory, children first.
    private func flush(_ index: Int, _ directory: Int32, _ stage: Stage) throws {
        for child in stage.children[index] {
            let entry = stage.listing.entries[child], leaf = TreeListing.leaf(entry.path)
            let (opened, info) = try (entry.isDirectory ? FixtureIO.openDirectory(leaf, in: directory, missing: .identityChanged)
                                                        : FixtureIO.openFile(leaf, in: directory, missing: .identityChanged))
            defer { close(opened) }
            guard EntryIdentity(info) == stage.identities[child] else { throw TransactionFailure.identityChanged }
            if entry.isDirectory { try flush(child, opened, stage) } else { try sync(.stagedFileFullSync, opened, full: true) }
        }
        try sync(.stagedDirectorySync, directory)
    }

    /// Exactly one atomic exchange of the two held names. There is no fallback to an ordinary rename.
    private func exchangeBundles() throws {
        try confirm()
        try require(renameatx_np(applications, name, exchange, name, UInt32(RENAME_SWAP)) == 0)
        swap(&atTarget, &atExchange)
        swap(&targetPosition, &exchangePosition)
        try confirm()
    }
    /// Both bundles are read again in full after an exchange. Anything unexpected matches no
    /// recorded state.
    private func verified(target expected: TreeListing, exchanged retained: TreeListing) throws -> (TreeListing, TreeListing) {
        let target = try BundleTree.read(atTarget), exchanged = try BundleTree.read(atExchange)
        try confirm()
        guard case .entry(let held) = targetPosition, held == target.identity,
              case .entry(let kept) = exchangePosition, kept == exchanged.identity,
              target.listing.matches(expected), exchanged.listing.matches(retained) else { throw TransactionFailure.ambiguousState }
        return (target.listing, exchanged.listing)
    }

    private func report(_ record: JournalRecord, _ action: RecoveryAction, before: TreeListing, after: TreeListing,
                        target: TreeListing, exchanged: TreeListing) -> TransactionReport {
        TransactionReport(transactionID: record.transactionID, state: record.state, recoveryAction: action,
            bundleName: record.bundleName, bundleID: record.bundleID, fromVersion: record.fromVersion, toVersion: record.toVersion,
            targetPath: record.targetPath, exchangePath: record.exchangePath, journalPath: root + "/Transaction/journal.json",
            before: before.report, after: after.report, targetNow: target.report, exchangeNow: exchanged.report,
            trigger: .explicitUserAction, atomicPrimitive: "renameatx_np(RENAME_SWAP)", runningCheck: "fixtureProbe",
            origin: "fixture", freshOSValidation: false, installationAuthorized: false, installedFirefoxProof: false)
    }

    // MARK: Perform.

    func perform(_ request: UpdateRequest) throws -> TransactionReport {
        let pinnedName = try shape(request), candidate = request.candidate, pin = candidate.artifact
        guard sameBytes(candidate.origin, "fixture"), !candidate.freshOSValidation, !candidate.installationAuthorized,
              validDigest(candidate.payloadSHA256), let wanted = try? NumericVersion(pin.version) else { throw TransactionFailure.notAuthorized }

        // Everything up to the running declaration only reads. A refusal leaves the root as found.
        let rootInfo = try handle.confirm(), device = rootInfo.st_dev
        applications = try openPrivate("Applications", in: handle.descriptor, missing: .missingTarget, device: device)
        incoming = try openPrivate("Incoming", in: handle.descriptor, missing: .missingSource, device: device)
        if let existing = try FixtureIO.named("Transaction", in: handle.descriptor) {
            throw FixtureIO.kind(existing) == S_IFLNK ? TransactionFailure.symlink : TransactionFailure.existingTransaction
        }

        let (pinnedFile, artifactInfo) = try FixtureIO.openFile(pinnedName, in: incoming, missing: .missingSource)
        owned.append(pinnedFile)
        try FixtureIO.requireFile(artifactInfo, modes: BundleTree.fileModes)
        guard artifactInfo.st_dev == device else { throw TransactionFailure.crossVolume }
        guard artifactInfo.st_size == pin.byteLength else { throw TransactionFailure.artifactMismatch }
        guard artifactInfo.st_size <= TransactionLimits.maximumManifestBytes else { throw TransactionFailure.invalidManifest }
        let pinned = try FixtureIO.read(pinnedFile, artifactInfo), artifactSHA256 = sha256Hex(pinned)
        _ = try FixtureIO.confirm(pinnedFile, named: pinnedName, in: incoming)
        artifact = pinnedFile; artifactName = pinnedName
        guard sameBytes(artifactSHA256, pin.sha256) else { throw TransactionFailure.artifactMismatch }
        let document = try ManifestDocument.parse(pinned)
        guard sameBytes(document.bundleName, name), sameBytes(document.bundleID, pin.bundleID) else { throw TransactionFailure.wrongBundle }
        guard sameBytes(document.version, pin.version) else { throw TransactionFailure.wrongVersion }

        let (heldSource, _) = try FixtureIO.openDirectory(name, in: incoming, missing: .missingSource)
        owned.append(heldSource)
        // The verified bytes are kept and are the bytes later staged; the source is not read twice.
        let source = try BundleTree.read(heldSource, retainContents: true)
        _ = try FixtureIO.confirm(heldSource, named: name, in: incoming)
        sourceRoot = heldSource
        guard source.identity.device == EntryIdentity(rootInfo).device else { throw TransactionFailure.crossVolume }
        guard source.listing.matches(document.listing) else { throw TransactionFailure.manifestMismatch }
        let incomingIdentity = try BundleIdentity(source)
        guard sameBytes(incomingIdentity.bundleID, pin.bundleID) else { throw TransactionFailure.wrongBundle }
        guard sameBytes(incomingIdentity.version, pin.version) else { throw TransactionFailure.wrongVersion }

        let (targetRoot, _) = try FixtureIO.openDirectory(name, in: applications, missing: .missingTarget)
        owned.append(targetRoot); atTarget = targetRoot
        let target = try BundleTree.read(atTarget)
        guard target.identity.device == source.identity.device else { throw TransactionFailure.crossVolume }
        guard target.identity != source.identity else { throw TransactionFailure.aliasedPath }
        let installed = try BundleIdentity(target)
        guard sameBytes(installed.bundleID, pin.bundleID) else { throw TransactionFailure.wrongBundle }
        guard let current = try? NumericVersion(installed.version) else { throw TransactionFailure.invalidBundle }
        guard current < wanted else { throw TransactionFailure.notNewer }
        targetPosition = .entry(target.identity)

        // Both documents that recovery will depend on must read back strictly before any state exists.
        let frozen = ManifestDocument(bundleName: name, bundleID: installed.bundleID, version: installed.version, listing: target.listing).encoded
        guard frozen.count <= TransactionLimits.maximumManifestBytes else { throw TransactionFailure.treeLimit }
        guard (try? ManifestDocument.parse(frozen))?.listing.matches(target.listing) == true else { throw TransactionFailure.invalidBundle }
        var record = JournalRecord(transactionID: UUID().uuidString, state: .prepared, bundleName: name, bundleID: pin.bundleID,
            fromVersion: installed.version, toVersion: pin.version, cataloguePayloadSHA256: candidate.payloadSHA256,
            artifactSHA256: artifactSHA256, targetPath: root + "/Applications/" + name,
            exchangePath: root + "/Transaction/exchange/" + name, device: target.identity.device, oldInode: target.identity.inode,
            newInode: 0, beforeManifestSHA256: sha256Hex(frozen), afterManifestSHA256: artifactSHA256,
            beforeTreeSHA256: target.listing.digest, afterTreeSHA256: document.listing.digest)
        guard record.encoded.count <= TransactionLimits.maximumJournalBytes - 64, (try? JournalRecord.parse(record.encoded)) != nil else {
            throw TransactionFailure.unsafePath
        }
        try refuseIfRunning(pin.bundleID)

        // Transaction state begins here.
        guard mkdirat(handle.descriptor, "Transaction", 0o700) == 0 else {
            throw errno == EEXIST ? TransactionFailure.existingTransaction : TransactionFailure.persistenceFailed
        }
        transaction = try holdCreated("Transaction", in: handle.descriptor).0
        try sync(.transactionParentSync, handle.descriptor)
        try boundary(.transactionDirectoryCreated)
        let created = openat(transaction, "lock", FixtureIO.createFlags, 0o600)
        try require(created >= 0)
        owned.append(created); lock = created
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw errno == EWOULDBLOCK ? TransactionFailure.busy : TransactionFailure.persistenceFailed }
        try boundary(.lockAcquired)
        try require(mkdirat(transaction, "exchange", 0o700) == 0)
        exchange = try holdCreated("exchange", in: transaction).0
        exchangePosition = .absent
        try freeze(frozen, as: "before-manifest.json")
        try freeze(pinned, as: "after-manifest.json")
        try persist(record)
        try boundary(.journalPrepared)

        try confirm()
        try require(mkdirat(exchange, name, 0o700) == 0)
        let (stagedRoot, stagedInfo) = try holdCreated(name, in: exchange)
        guard stagedInfo.st_dev == device else { throw TransactionFailure.crossVolume }
        atExchange = stagedRoot; exchangePosition = .entry(EntryIdentity(stagedInfo))
        try boundary(.stageCreated)
        var stage = Stage(listing: document.listing, contents: source.contents, children: document.listing.children,
                          identities: [EntryIdentity?](repeating: nil, count: document.listing.entries.count))
        try require(fchmod(atExchange, mode_t(document.listing.entries[0].mode)) == 0)
        try copy(0, into: atExchange, &stage)
        try boundary(.stageCopied)
        try flush(0, atExchange, stage)
        try sync(.exchangeDirectorySync, exchange)
        try boundary(.stageSynced)

        // The staged bytes are read back from the disk through the held stage, not trusted from memory.
        let staged = try BundleTree.read(atExchange)
        guard staged.listing.matches(document.listing), staged.identity == EntryIdentity(stagedInfo) else {
            throw TransactionFailure.stagedBytesMismatch
        }
        record.newInode = staged.identity.inode; record.state = .staged
        try persist(record)
        try boundary(.stageVerified)
        record.state = .swapIntended
        try persist(record)
        try boundary(.swapIntended)

        try refuseIfRunning(pin.bundleID)
        try exchangeBundles()
        try boundary(.swapped)
        try sync(.targetParentSync, applications)
        try sync(.exchangeDirectorySync, exchange)
        try boundary(.targetParentSynced)
        try boundary(.beforeCommitRecord)
        let (targetNow, exchangeNow) = try verified(target: document.listing, exchanged: target.listing)
        // The swapped bytes are on disk before this point; only this record makes them the accepted state.
        record.state = .committed
        try persist(record)
        return report(record, RecoveryAction.none, before: target.listing, after: document.listing, target: targetNow, exchanged: exchangeNow)
    }

    // MARK: Recovery and final decision.

    private func frozen(_ file: String, _ digest: String) throws -> ManifestDocument {
        let (opened, info) = try FixtureIO.openFile(file, in: transaction, missing: .journalMismatch)
        defer { close(opened) }
        try FixtureIO.requireFile(info, modes: [0o600])
        guard info.st_size <= TransactionLimits.maximumManifestBytes else { throw TransactionFailure.journalMismatch }
        let bytes = try FixtureIO.read(opened, info)
        // The name must still show the file that was read before its bytes are accepted.
        _ = try FixtureIO.confirm(opened, named: file, in: transaction)
        guard sameBytes(sha256Hex(bytes), digest), let document = try? ManifestDocument.parse(bytes) else { throw TransactionFailure.journalMismatch }
        return document
    }
    /// The bundle at this transaction's name beneath `parent`, or `nil` when the name is absent.
    private func bundle(in parent: Int32) throws -> (Int32, PhysicalBundle)? {
        guard let entry = try FixtureIO.named(name, in: parent) else { return nil }
        guard FixtureIO.kind(entry) != S_IFLNK else { throw TransactionFailure.symlink }
        guard FixtureIO.kind(entry) == S_IFDIR else { throw TransactionFailure.ambiguousState }
        let (opened, _) = try FixtureIO.openDirectory(name, in: parent, missing: .ambiguousState)
        owned.append(opened)
        return (opened, try BundleTree.read(opened))
    }

    /// Takes the persistent lock, then reads and cross-checks all evidence. Nothing is written.
    private func load(_ transactionDirectory: String) throws -> Evidence {
        guard isTransactionDirectory(try rawComponents(transactionDirectory)) else { throw TransactionFailure.notAuthorized }
        let rootInfo = try handle.confirm(), device = rootInfo.st_dev
        transaction = try openPrivate("Transaction", in: handle.descriptor, missing: .journalMissing, device: device)
        let (held, lockInfo) = try FixtureIO.openFile("lock", in: transaction, missing: .journalMissing)
        owned.append(held)
        try FixtureIO.requireFile(lockInfo, modes: [0o600])
        guard flock(held, LOCK_EX | LOCK_NB) == 0 else { throw TransactionFailure.busy }
        lock = held

        let (opened, journalInfo) = try FixtureIO.openFile("journal.json", in: transaction, missing: .journalMissing)
        journal = opened
        try FixtureIO.requireFile(journalInfo, modes: [0o600])
        guard journalInfo.st_size > 0, journalInfo.st_size <= TransactionLimits.maximumJournalBytes else { throw TransactionFailure.journalCorrupt }
        let record = try JournalRecord.parse(try FixtureIO.read(journal, journalInfo))
        name = record.bundleName

        applications = try openPrivate("Applications", in: handle.descriptor, missing: .ambiguousState, device: device)
        exchange = try openPrivate("exchange", in: transaction, missing: .ambiguousState, device: device)
        guard sameBytes(record.targetPath, root + "/Applications/" + name),
              sameBytes(record.exchangePath, root + "/Transaction/exchange/" + name),
              record.device == EntryIdentity(rootInfo).device else { throw TransactionFailure.journalMismatch }
        let before = try frozen("before-manifest.json", record.beforeManifestSHA256)
        let after = try frozen("after-manifest.json", record.afterManifestSHA256)
        guard sameBytes(before.bundleName, name), sameBytes(after.bundleName, name),
              sameBytes(before.bundleID, record.bundleID), sameBytes(after.bundleID, record.bundleID),
              sameBytes(before.version, record.fromVersion), sameBytes(after.version, record.toVersion),
              sameBytes(before.listing.digest, record.beforeTreeSHA256), sameBytes(after.listing.digest, record.afterTreeSHA256),
              sameBytes(record.artifactSHA256, record.afterManifestSHA256),
              let from = try? NumericVersion(record.fromVersion), let to = try? NumericVersion(record.toVersion), from < to else {
            throw TransactionFailure.journalMismatch
        }

        let target = try bundle(in: applications), exchanged = try bundle(in: exchange)
        if let target { atTarget = target.0; targetPosition = .entry(target.1.identity) } else { targetPosition = .absent }
        if let exchanged { atExchange = exchanged.0; exchangePosition = .entry(exchanged.1.identity) } else { exchangePosition = .absent }
        try confirm()
        return Evidence(record: record, before: before, after: after, target: target?.1, exchanged: exchanged?.1)
    }

    /// Puts the fully verified old bundle back with one exchange, then records `rolledBack`.
    private func restore(_ evidence: Evidence) throws -> TransactionReport {
        var record = evidence.record
        try refuseIfRunning(record.bundleID)
        try boundary(.beforeSwapBack)
        try exchangeBundles()
        try boundary(.swappedBack)
        try sync(.targetParentSync, applications)
        try sync(.exchangeDirectorySync, exchange)
        let (target, exchanged) = try verified(target: evidence.before.listing, exchanged: evidence.after.listing)
        record.state = .rolledBack
        try persist(record)
        return report(record, .restoredOldBySwap, before: evidence.before.listing, after: evidence.after.listing, target: target, exchanged: exchanged)
    }

    func recover(_ transactionDirectory: String) throws -> TransactionReport {
        let evidence = try load(transactionDirectory)
        var record = evidence.record
        let before = evidence.before.listing, after = evidence.after.listing
        switch record.state {
        case .prepared, .staged, .swapIntended:
            if evidence.isOld(evidence.target), let target = evidence.target {
                // The stage may be absent, partial or complete. It is reported as physically read.
                record.state = .rolledBack
                try persist(record)
                return report(record, .oldAlreadyInPlace, before: before, after: after, target: target.listing,
                              exchanged: evidence.exchanged?.listing ?? .empty)
            }
            guard record.state == .swapIntended, evidence.isNew(evidence.target), evidence.isOld(evidence.exchanged) else {
                throw TransactionFailure.ambiguousState
            }
            return try restore(evidence)
        case .committed, .finalized:
            guard evidence.isNew(evidence.target), evidence.isOld(evidence.exchanged), let target = evidence.target,
                  let exchanged = evidence.exchanged else { throw TransactionFailure.ambiguousState }
            return report(record, RecoveryAction.none, before: before, after: after, target: target.listing, exchanged: exchanged.listing)
        case .rolledBack:
            guard evidence.isOld(evidence.target), let target = evidence.target else { throw TransactionFailure.ambiguousState }
            return report(record, RecoveryAction.none, before: before, after: after, target: target.listing,
                          exchanged: evidence.exchanged?.listing ?? .empty)
        }
    }

    func decide(_ decision: FinalDecision, _ transactionDirectory: String, trigger: TransactionTrigger) throws -> TransactionReport {
        guard trigger == .explicitUserAction else { throw TransactionFailure.userTriggerRequired }
        var evidence = try load(transactionDirectory)
        guard evidence.record.state == .committed else { throw TransactionFailure.invalidState }
        guard evidence.isNew(evidence.target), evidence.isOld(evidence.exchanged), let target = evidence.target,
              let exchanged = evidence.exchanged else { throw TransactionFailure.ambiguousState }
        switch decision {
        case .keepNew:
            evidence.record.state = .finalized
            try persist(evidence.record)
            return report(evidence.record, RecoveryAction.none, before: evidence.before.listing, after: evidence.after.listing,
                          target: target.listing, exchanged: exchanged.listing)
        case .restoreOld:
            try refuseIfRunning(evidence.record.bundleID)
            // The commit is withdrawn durably before the exchange, so an interruption on either
            // side of it is an uncommitted swap that `recover` resolves to the old bundle.
            evidence.record.state = .swapIntended
            try persist(evidence.record)
            return try restore(evidence)
        }
    }
}
