import Foundation
import Darwin
import OpenDirectory
import PatchedScheduling

/// Explicit local-account storage composition. This establishes storage ownership only.
@MainActor public final class NativePreferenceContext {
    public let session: PreferenceSession
    public let generation: String
    private init(session: PreferenceSession, generation: String) {
        self.session = session; self.generation = generation
    }
    private static let processGeneration = UUID().uuidString.lowercased()
    public static func open() throws -> NativePreferenceContext {
        do {
            let account = try LocalPreferenceAccount.observe()
            let home = try PreferenceDirectory.absolute(account.home)
            try home.requireCurrentOwner()
            let library = try home.child("Library", create: false, privateMode: false)
            let support = try library.child("Application Support", create: false, privateMode: false)
            let container = try support.child("Patched", create: true, privateMode: true)
            let store = FilePreferenceStore(nativeRoot: container, account: account)
            let principal = SchedulingPrincipal("local-account:" + account.generatedUID)
            let scope = "native-preferences-v1:" + account.generatedUID
            let session = PreferenceSession.bound(store: store, principal: principal, storeScope: scope,
                generation: processGeneration, queueID: "native-preferences:" + UUID().uuidString.lowercased())
            return NativePreferenceContext(session: session, generation: processGeneration)
        } catch { throw PreferenceRefusal.unavailable }
    }
    public func createFresh() -> PreferenceEditResult { session.bootstrapMissing(generation: generation) }
    public func reload() -> PreferenceEditResult { session.reload(generation: generation) }
}

// No injected account metadata and no search-node or network directory lookup.
// GeneratedUID must be an actual attribute of exactly one local record, never mbr_uid_to_uuid's fallback.
private struct LocalPreferenceAccount: Equatable {
    let uid: uid_t
    let name: String
    let home: String
    let generatedUID: String
    static func observe() throws -> LocalPreferenceAccount {
        let uid = getuid()
        guard uid != 0, geteuid() == uid else { throw PreferenceRefusal.identity }
        // Do not use getpwuid/search-policy nodes: their lookup may consult a network directory.
        // The kernel UID must instead resolve to exactly one record in the fixed local node.
        let node = try ODNode(session: ODSession.default(), name: "/Local/Default")
        let attributes = [kODAttributeTypeUniqueID, kODAttributeTypeGUID, kODAttributeTypeNFSHomeDirectory, kODAttributeTypeRecordName]
        let query = try ODQuery(node: node, forRecordTypes: kODRecordTypeUsers,
            attribute: kODAttributeTypeUniqueID, matchType: ODMatchType(kODMatchEqualTo),
            queryValues: String(uid), returnAttributes: attributes, maximumResults: 2)
        guard let records = try query.resultsAllowingPartial(false) as? [ODRecord], records.count == 1 else {
            throw PreferenceRefusal.identity
        }
        let record = records[0]
        func one(_ attribute: String) throws -> String {
            guard let values = try record.values(forAttribute: attribute) as? [String], values.count == 1 else {
                throw PreferenceRefusal.identity
            }
            return values[0]
        }
        let accountName: String? = record.recordName
        let home = try one(kODAttributeTypeNFSHomeDirectory)
        guard let name = accountName, !name.isEmpty, name.utf8.count <= 256, home.hasPrefix("/"), home != "/",
              !home.utf8.contains(0), URL(fileURLWithPath: home).standardizedFileURL.path == home else {
            throw PreferenceRefusal.identity
        }
        guard try one(kODAttributeTypeUniqueID) == String(uid),
              let uuid = UUID(uuidString: try one(kODAttributeTypeGUID)),
              uuid != UUID(uuidString: "00000000-0000-0000-0000-000000000000") else { throw PreferenceRefusal.identity }
        // Darwin's reserved UID-derived identity namespace cannot identify an account incarnation.
        let generated = uuid.uuidString.lowercased()
        guard !generated.hasPrefix("ffffeeee-dddd-cccc-bbbb-aaaa") else { throw PreferenceRefusal.identity }
        return LocalPreferenceAccount(uid: uid, name: name, home: home, generatedUID: generated)
    }
}

/// A selector for an exclusively check-owned directory below the actual executable's .build.
/// This is untrusted input, not a native account, context, principal or installed identity.
/// The adapter physically validates confinement and retained identity on every operation.
@_spi(Testing) public struct FixturePreferenceRoot: Sendable {
    public let checkOwnedDirectory: URL
    public init(checkOwnedDirectory: URL) { self.checkOwnedDirectory = checkOwnedDirectory }
}

/// Fault declarations apply only to fixture construction. Native construction has no hook input.
@_spi(Testing) public enum FixturePreferenceFault: String, CaseIterable, Sendable {
    case none, shortWriteThenContinue, interruptedWriteThenContinue, writeFailure
    case fileSync, fullFlush, rename, directorySync, afterRename, readback
}

/// The same descriptor/CAS primitive is used by the physically bound native factory.
@_spi(Testing) @MainActor public final class FilePreferenceStore: PreferenceStore {
    /// Test-only observation: populated only when the CAS actually reaches its selected fault.
    public private(set) var exercisedFaults: [FixturePreferenceFault] = []
    private let root: PreferenceDirectory?
    private let fixtureURL: URL?
    private let account: LocalPreferenceAccount?
    private let fault: FixturePreferenceFault?
    private var lockFile: PreferenceFile?
    public init(fixtureRoot: FixturePreferenceRoot, fault: FixturePreferenceFault = .none) {
        fixtureURL = fixtureRoot.checkOwnedDirectory; account = nil; self.fault = fault
        root = try? PreferenceDirectory.fixture(fixtureRoot.checkOwnedDirectory)
    }
    fileprivate init(nativeRoot: PreferenceDirectory, account: LocalPreferenceAccount) {
        root = nativeRoot; self.account = account; fixtureURL = nil; fault = nil
    }
    private func validatedRoot() throws -> PreferenceDirectory {
        guard let root else { throw PreferenceRefusal.unavailable }
        if let fixtureURL {
            let observed = try PreferenceDirectory.fixture(fixtureURL)
            guard try root.sameIdentity(as: observed) else { throw PreferenceRefusal.unavailable }
        } else {
            guard let account, try LocalPreferenceAccount.observe() == account else { throw PreferenceRefusal.identity }
        }
        try root.validate()
        return root
    }
    private func bound(_ maximum: Int) -> Bool { maximum > 0 && maximum <= PreferenceRecord.maximumBytes }
    public func read(maximumBytes: Int) -> PreferenceRead {
        guard bound(maximumBytes) else { return .unavailable }
        do { return try readRecord(root: validatedRoot(), maximum: maximumBytes) }
        catch { return .unavailable }
    }
    private func readRecord(root: PreferenceDirectory, maximum: Int) throws -> PreferenceRead {
        guard let file = try PreferenceFile.existing(root: root, name: "record.json", maximum: maximum) else { return .missing }
        let bytes = try file.bytes(maximum: maximum)
        try root.validate(); try file.validate()
        return .bytes(bytes)
    }
    private func reached(_ selected: FixturePreferenceFault) -> Bool {
        guard fault == selected else { return false }
        exercisedFaults.append(selected); return true
    }
    public func compareAndSwap(expected: Data?, proposed: Data, maximumBytes: Int) -> PreferenceCommit {
        guard bound(maximumBytes), proposed.count <= maximumBytes,
              expected == nil || expected!.count <= maximumBytes else { return .notCommitted }
        var renamed = false
        do {
            let root = try validatedRoot()
            // Refuse unsafe existing records before creating even the cooperative lock.
            _ = try readRecord(root: root, maximum: maximumBytes)
            if lockFile == nil { lockFile = try PreferenceFile.lock(root: root) }
            guard let lockFile else { return .notCommitted }
            try lockFile.validate()
            guard flock(lockFile.fd, LOCK_EX | LOCK_NB) == 0 else { return .notCommitted }
            defer { flock(lockFile.fd, LOCK_UN) }
            try root.validate(); try lockFile.validate()
            let current = try readRecord(root: root, maximum: maximumBytes)
            switch current {
            case .missing: guard expected == nil else { return .conflict }
            case .bytes(let bytes): guard expected == bytes else { return .conflict }
            case .unavailable: return .notCommitted
            }
            let temporary = try PreferenceFile.temporary(root: root)
            defer { if !renamed { temporary.removeIfIdentical() } }
            var injectedWrite = false
            try proposed.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                var offset = 0
                repeat {
                    var amount = buffer.count - offset
                    let count: Int
                    if !injectedWrite && reached(.writeFailure) { throw PreferenceRefusal.unavailable }
                    if !injectedWrite && reached(.interruptedWriteThenContinue) {
                        injectedWrite = true; errno = EINTR; count = -1
                    } else {
                        if !injectedWrite && reached(.shortWriteThenContinue) {
                            injectedWrite = true; amount = max(1, amount / 2)
                        }
                        if amount == 0 { break }
                        count = Darwin.write(temporary.fd, buffer.baseAddress!.advanced(by: offset), amount)
                    }
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw PreferenceRefusal.unavailable }
                    offset += count
                } while offset < buffer.count
            }
            guard !reached(.fileSync), fsync(temporary.fd) == 0 else { return .notCommitted }
            guard !reached(.fullFlush), fcntl(temporary.fd, F_FULLFSYNC) == 0 else { return .notCommitted }
            try root.validate(); try lockFile.validate(); try temporary.validate()
            guard try readRecord(root: root, maximum: maximumBytes) == current else { return .conflict }
            guard !reached(.rename) else { return .notCommitted }
            // Once rename is attempted an error is conservatively ambiguous; never claim no write.
            renamed = true
            guard renameat(root.fd, temporary.name, root.fd, "record.json") == 0 else {
                temporary.removeIfIdentical(); return .uncertain
            }
            guard !reached(.afterRename) else { return .uncertain }
            guard !reached(.directorySync), fsync(root.fd) == 0 else { return .uncertain }
            try root.validate(); try lockFile.validate()
            var heldTemporary = stat(), installed = stat()
            guard fstat(temporary.fd, &heldTemporary) == 0,
                  fstatat(root.fd, "record.json", &installed, AT_SYMLINK_NOFOLLOW) == 0,
                  heldTemporary.st_dev == installed.st_dev, heldTemporary.st_ino == installed.st_ino else { return .uncertain }
            guard !reached(.readback),
                  try readRecord(root: root, maximum: maximumBytes) == .bytes(proposed) else { return .uncertain }
            return .committed
        } catch { return renamed ? .uncertain : .notCommitted }
    }
}
