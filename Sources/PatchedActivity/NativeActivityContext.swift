import Foundation
import Darwin
import OpenDirectory

/// Explicit account-bound storage only. No event producer or installed-success authority.
@MainActor public final class NativeActivityContext {
    private let owner: ActivityHistoryOwner
    private init(owner: ActivityHistoryOwner) { self.owner = owner }
    public var snapshot: ActivitySnapshot { owner.snapshot }

    /// This explicit operation observes the local account and opens fixed physical storage.
    /// It must not be called by app construction, rendering or navigation.
    public static func open() throws -> NativeActivityContext {
        do {
            let account = try LocalActivityAccount.observe()
            let home = try ActivityDirectory.absolute(account.home)
            try home.requireCurrentOwner()
            let library = try home.child("Library", create: false, privateMode: false)
            let support = try library.child("Application Support", create: false, privateMode: false)
            let container = try support.child("Patched", create: true, privateMode: true)
            let root = try container.child("Activity", create: true, privateMode: true)
            let store = FileActivityStore(nativeRoot: root, account: account)
            guard try LocalActivityAccount.observe() == account else { throw ActivityRefusal.unavailable }
            try root.validate()
            let owner = ActivityHistoryOwner(authenticatedNativeStore: store,
                principal: account.principal, storeID: account.generatedUID)
            return NativeActivityContext(owner: owner)
        } catch { throw ActivityRefusal.unavailable }
    }
    public func createFresh() throws { try owner.bootstrapMissing(now: Self.now()) }
    public func reload() throws { try owner.reload(now: Self.now()) }
    public func selectRetained() throws { try owner.selectRetained(now: Self.now()) }
    private static func now() -> UInt64? {
        let seconds = Date().timeIntervalSince1970
        guard seconds.isFinite, seconds >= 0, seconds < Double(UInt64.max) else { return nil }
        return UInt64(seconds.rounded(.down))
    }
}

// No injected account metadata and no search-node or network directory lookup.
// GeneratedUID must be an actual attribute of exactly one local record, never mbr_uid_to_uuid's fallback.
fileprivate struct LocalActivityAccount: Equatable {
    let uid: uid_t
    let name: String
    let home: String
    let generatedUID: String
    var principal: String { "local-account:" + generatedUID }
    static func observe() throws -> LocalActivityAccount {
        let uid = getuid()
        guard uid != 0, geteuid() == uid else { throw ActivityRefusal.unavailable }
        // Do not use getpwuid/search-policy nodes: their lookup may consult a network directory.
        // The kernel UID must instead resolve to exactly one record in the fixed local node.
        let node = try ODNode(session: ODSession.default(), name: "/Local/Default")
        let attributes = [kODAttributeTypeUniqueID, kODAttributeTypeGUID, kODAttributeTypeNFSHomeDirectory, kODAttributeTypeRecordName]
        let query = try ODQuery(node: node, forRecordTypes: kODRecordTypeUsers,
            attribute: kODAttributeTypeUniqueID, matchType: ODMatchType(kODMatchEqualTo),
            queryValues: String(uid), returnAttributes: attributes, maximumResults: 2)
        guard let records = try query.resultsAllowingPartial(false) as? [ODRecord], records.count == 1 else {
            throw ActivityRefusal.unavailable
        }
        let record = records[0]
        func one(_ attribute: String) throws -> String {
            guard let values = try record.values(forAttribute: attribute) as? [String], values.count == 1 else {
                throw ActivityRefusal.unavailable
            }
            return values[0]
        }
        let accountName: String? = record.recordName
        let home = try one(kODAttributeTypeNFSHomeDirectory)
        guard let name = accountName, !name.isEmpty, name.utf8.count <= 256, home.hasPrefix("/"), home != "/",
              !home.utf8.contains(0), URL(fileURLWithPath: home).standardizedFileURL.path == home else {
            throw ActivityRefusal.unavailable
        }
        guard try one(kODAttributeTypeUniqueID) == String(uid),
              let uuid = UUID(uuidString: try one(kODAttributeTypeGUID)),
              uuid != UUID(uuidString: "00000000-0000-0000-0000-000000000000") else { throw ActivityRefusal.unavailable }
        // Darwin's reserved UID-derived identity namespace cannot identify an account incarnation.
        let generated = uuid.uuidString
        guard !generated.lowercased().hasPrefix("ffffeeee-dddd-cccc-bbbb-aaaa") else { throw ActivityRefusal.unavailable }
        return LocalActivityAccount(uid: uid, name: name, home: home, generatedUID: generated)
    }
}

/// Untrusted fixture selector. Implementation must physically confine every operation.
@_spi(Testing) public struct FixtureActivityRoot: Sendable {
    public let checkOwnedDirectory: URL
    public init(checkOwnedDirectory: URL) { self.checkOwnedDirectory = checkOwnedDirectory }
}

@_spi(Testing) public enum FixtureActivityFault: String, CaseIterable, Sendable {
    case none, shortWriteThenContinue, interruptedWriteThenContinue, writeFailure
    case fileSync, fullFlush, rename, directorySync, afterRename, readback
}

/// Shared descriptor/CAS primitive. Fixture construction grants no native account authority.
@_spi(Testing) @MainActor public final class FileActivityStore: ActivityStore {
    public private(set) var exercisedFaults: [FixtureActivityFault] = []
    private let root: ActivityDirectory?
    private let fixtureURL: URL?
    private let account: LocalActivityAccount?
    private let principal: String
    private let storeID: String
    private let fault: FixtureActivityFault?
    private var lockFile: ActivityFile?

    public init(fixtureRoot: FixtureActivityRoot, principal: String, storeID: String,
                fault: FixtureActivityFault = .none) {
        fixtureURL = fixtureRoot.checkOwnedDirectory; account = nil; self.fault = fault
        self.principal = principal; self.storeID = storeID
        root = try? ActivityDirectory.fixture(fixtureRoot.checkOwnedDirectory)
    }
    fileprivate init(nativeRoot: ActivityDirectory, account: LocalActivityAccount) {
        root = nativeRoot; self.account = account; fixtureURL = nil; fault = nil
        principal = account.principal; storeID = account.generatedUID
    }
    private func validatedRoot() throws -> ActivityDirectory {
        guard let root else { throw ActivityRefusal.unavailable }
        if let fixtureURL {
            let observed = try ActivityDirectory.fixture(fixtureURL)
            guard try root.sameIdentity(as: observed) else { throw ActivityRefusal.unavailable }
        } else {
            guard let account, try LocalActivityAccount.observe() == account else { throw ActivityRefusal.unavailable }
        }
        try root.validate()
        // A retained cooperative lock may never silently rebind to a replacement inode.
        if let lockFile { try lockFile.validate() }
        else { _ = try ActivityFile.existing(root: root, name: "lock", maximum: 0) }
        return root
    }
    private func validated(_ stored: ActivityStoredBytes) throws -> ActivityRecord {
        let record = try ActivityWire.decode(stored.bytes, principal: principal, storeID: storeID)
        guard record.revision == stored.revision else { throw ActivityRefusal.invalidWire }
        return record
    }
    public func read() throws -> ActivityStoredBytes? {
        let stored = try readRecord(root: validatedRoot())
        _ = try validatedRoot()
        return stored
    }
    private func readRecord(root: ActivityDirectory, expectedFile: ActivityFile? = nil) throws -> ActivityStoredBytes? {
        guard let file = try ActivityFile.existing(root: root, name: "record.json", maximum: ActivityWire.maximumBytes) else {
            try root.validate()
            return nil
        }
        if let expectedFile {
            guard try file.sameIdentity(as: expectedFile.fd) else { throw ActivityRefusal.unavailable }
        }
        let bytes = try file.bytes(maximum: ActivityWire.maximumBytes)
        let record = try ActivityWire.decode(bytes, principal: principal, storeID: storeID)
        try root.validate(); try file.validate()
        return ActivityStoredBytes(revision: record.revision, bytes: bytes)
    }
    private func reached(_ selected: FixtureActivityFault) -> Bool {
        guard fault == selected else { return false }
        exercisedFaults.append(selected); return true
    }
    public func compareAndSwap(expected: ActivityStoredBytes?, replacement: ActivityStoredBytes) throws -> ActivityWriteResult {
        var renameAttempted = false
        do {
            _ = try validated(replacement)
            if let expected {
                _ = try validated(expected)
                guard expected.revision < UInt64.max, replacement.revision == expected.revision + 1 else {
                    return .knownNotCommitted
                }
            } else if replacement.revision != 0 { return .knownNotCommitted }
            let root = try validatedRoot()
            // Refuse corrupt or unsafe state before creating even the cooperative lock.
            _ = try readRecord(root: root)
            if lockFile == nil { lockFile = try ActivityFile.lock(root: root) }
            guard let lockFile else { return .knownNotCommitted }
            try lockFile.validate()
            guard flock(lockFile.fd, LOCK_EX | LOCK_NB) == 0 else { return .knownNotCommitted }
            defer { flock(lockFile.fd, LOCK_UN) }
            _ = try validatedRoot(); try lockFile.validate()
            let current = try readRecord(root: root)
            guard current == expected else { return .knownNotCommitted }
            let temporary = try ActivityFile.temporary(root: root)
            defer { if !renameAttempted { temporary.removeIfIdentical() } }
            var injectedWrite = false
            try replacement.bytes.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                var offset = 0
                while offset < buffer.count {
                    var amount = buffer.count - offset
                    let count: Int
                    if !injectedWrite && reached(.writeFailure) { throw ActivityRefusal.unavailable }
                    if !injectedWrite && reached(.interruptedWriteThenContinue) {
                        injectedWrite = true; errno = EINTR; count = -1
                    } else {
                        if !injectedWrite && reached(.shortWriteThenContinue) {
                            injectedWrite = true; amount = max(1, amount / 2)
                        }
                        count = Darwin.write(temporary.fd, buffer.baseAddress!.advanced(by: offset), amount)
                    }
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw ActivityRefusal.unavailable }
                    offset += count
                }
            }
            guard !reached(.fileSync), fsync(temporary.fd) == 0 else { return .knownNotCommitted }
            guard !reached(.fullFlush), fcntl(temporary.fd, F_FULLFSYNC) == 0 else { return .knownNotCommitted }
            _ = try validatedRoot(); try lockFile.validate(); try temporary.validate()
            guard try readRecord(root: root) == current else { return .knownNotCommitted }
            guard !reached(.rename) else { return .knownNotCommitted }
            // Once attempted, rename failure is conservatively ambiguous. Preserve any evidence.
            renameAttempted = true
            guard renameat(root.fd, temporary.name, root.fd, "record.json") == 0 else { return .uncertain }
            guard !reached(.afterRename) else { return .uncertain }
            guard !reached(.directorySync), fsync(root.fd) == 0 else { return .uncertain }
            _ = try validatedRoot(); try lockFile.validate()
            var held = stat(), installed = stat()
            guard fstat(temporary.fd, &held) == 0,
                  fstatat(root.fd, "record.json", &installed, AT_SYMLINK_NOFOLLOW) == 0,
                  held.st_dev == installed.st_dev, held.st_ino == installed.st_ino else { return .uncertain }
            guard !reached(.readback), try readRecord(root: root, expectedFile: temporary) == replacement else { return .uncertain }
            // Independently reopening proved the persisted bytes; recheck authority before acknowledgement.
            _ = try validatedRoot()
            return .committed
        } catch { return renameAttempted ? .uncertain : .knownNotCommitted }
    }
}
