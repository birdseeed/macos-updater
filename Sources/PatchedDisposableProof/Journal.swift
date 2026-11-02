import Foundation
import Darwin

struct JournalBinding {
    let profile: DisposableTargetProfile
    let run: String, caseRoot: String, origin: String
    let uid: uid_t, device: UInt64, inode: UInt64
    init(root: HeldDirectory, run: String, caseRoot: String, origin: String, profile: DisposableTargetProfile = .legacy) throws {
        let info = try root.status()
        self.run = run; self.caseRoot = caseRoot; self.origin = origin; self.profile = profile
        uid = info.st_uid; device = identity(info).0; inode = info.st_ino
    }
}
struct ProofJournal {
    static let keys: Set<String> = ["schemaVersion", "kind", "origin", "guestUUIDSHA256", "uid", "runID",
        "caseRoot", "device", "inode", "state", "transactionID", "oldInode", "newInode",
        "beforeManifestSHA256", "afterManifestSHA256", "cataloguePayloadSHA256", "artifactSHA256"]
    var object: [String: Any]
    var state: ProofState { ProofState(rawValue: object["state"] as! String)! }
    var oldInode: UInt64 { unsigned(object["oldInode"])! }
    var newInode: UInt64 { unsigned(object["newInode"])! }
    var oldDigest: String { object["beforeManifestSHA256"] as! String }
    var newDigest: String { object["afterManifestSHA256"] as! String }
    var encoded: Data { get throws { try encodeJSON(object) } }
    static func decode(_ bytes: Data, binding: JournalBinding) throws -> ProofJournal {
        let object = try StrictObject.decode(bytes)
        guard Set(object.keys) == keys, unsigned(object["schemaVersion"]) == 1,
              object["kind"] as? String == "patched-disposable-journal-v1",
              let origin = object["origin"] as? String, origin == binding.origin,
              let raw = object["state"] as? String, ProofState(rawValue: raw) != nil,
              let transaction = object["transactionID"] as? String, UUID(uuidString: transaction)?.uuidString == transaction,
              let run = object["runID"] as? String, validRun(run),
              let root = object["caseRoot"] as? String, DisposableScope.caseRoots.contains(root),
              let uid = unsigned(object["uid"]), let device = unsigned(object["device"]), let inode = unsigned(object["inode"]),
              let old = unsigned(object["oldInode"]), old > 0, unsigned(object["newInode"]) != nil,
              let guest = object["guestUUIDSHA256"] as? String, validDigest(guest),
              ["beforeManifestSHA256", "afterManifestSHA256", "cataloguePayloadSHA256", "artifactSHA256"].allSatisfy({
                  (object[$0] as? String).map(validDigest) == true
              }) else { throw DisposableFailure.journalCorrupt }
        guard run == binding.run, root == binding.caseRoot, uid == binding.uid, device == binding.device,
              inode == binding.inode, guest == binding.profile.guestUUIDSHA256 else { throw DisposableFailure.journalMismatch }
        return .init(object: object)
    }
    mutating func transition(_ to: ProofState) throws { try requireTransition(state, to); object["state"] = to.rawValue }
}
final class ExclusiveLock {
    let file: HeldFile
    init(_ root: HeldDirectory, name: String) throws {
        try root.confirm()
        if try root.named(name) == nil {
            do { try PhysicalIO.write(root, name, data: Data()) }
            catch DisposableFailure.existingRoot { /* competing creator must still obtain flock */ }
        }
        file = try HeldFile(parent: root, name: name, writable: true)
        guard flock(file.fd, LOCK_EX | LOCK_NB) == 0 else { throw DisposableFailure.busy }
        try file.confirm()
    }
    deinit { _ = flock(file.fd, LOCK_UN) }
}
enum JournalStore {
    static func read(_ root: HeldDirectory, binding: JournalBinding) throws -> ProofJournal {
        guard try root.named("journal.json") != nil else { throw DisposableFailure.journalMissing }
        let bytes: Data
        do { bytes = try PhysicalIO.read(root, "journal.json", maximum: 65_536) }
        catch DisposableFailure.treeLimit { throw DisposableFailure.journalCorrupt }
        return try ProofJournal.decode(bytes, binding: binding)
    }
    static func write(_ root: HeldDirectory, data: Data, binding: JournalBinding, hooks: FileHooks = .init(), locked: Bool = false) throws {
        _ = try ProofJournal.decode(data, binding: binding)
        let lock = locked ? nil : try ExclusiveLock(root, name: "journal.lock")
        defer { withExtendedLifetime(lock) {} }
        let name = ".journal-" + UUID().uuidString
        try PhysicalIO.write(root, name, data: data, hooks: hooks)
        let file = try HeldFile(parent: root, name: name, writable: true)
        try hooks.hit("beforeJournalReplace"); try root.confirm(); try file.confirm()
        if let existing = try root.named("journal.json") { try HeldFile.validate(existing, owner: getuid()) }
        guard renameat(root.fd, name, root.fd, "journal.json") == 0 else { throw DisposableFailure.persistenceFailed }
        try hooks.hit("journalReplaced"); try root.syncDirectory(hooks: hooks)
        try hooks.flush("committedFileFullSync")
        guard fcntl(file.fd, F_FULLFSYNC) == 0 else { throw DisposableFailure.persistenceFailed }
        guard let observed = try root.named("journal.json"), sameIdentity(observed, file.captured),
              try PhysicalIO.read(root, "journal.json", maximum: 65_536) == data else { throw DisposableFailure.persistenceFailed }
    }
}
enum SharedRecovery {
    static func recover(_ root: HeldDirectory, binding: JournalBinding, target: String, retained: String,
                        hooks: FileHooks = .init(), journalDirectory: HeldDirectory? = nil, verifyOld: ((HeldDirectory) throws -> Void)? = nil) throws -> ProofRecovery {
        let storage = journalDirectory ?? root
        let lock = try ExclusiveLock(storage, name: "journal.lock"); defer { withExtendedLifetime(lock) {} }
        var journal = try JournalStore.read(storage, binding: binding)
        let physicalTarget = try root.descend(target)
        let targetManifest = try ManifestReader.read(physicalTarget)
        let targetID = physicalTarget.captured.st_ino
        let targetOld = targetID == journal.oldInode && targetManifest.digest == journal.oldDigest
        let targetNew = targetID == journal.newInode && targetManifest.digest == journal.newDigest
        let (retainedParent, retainedName) = try root.parentOf(retained)
        var retainedOld = false, retainedNew = false
        if !targetOld, try retainedParent.named(retainedName) != nil {
            let physical = try retainedParent.child(retainedName), manifest = try ManifestReader.read(physical)
            retainedOld = physical.captured.st_ino == journal.oldInode && manifest.digest == journal.oldDigest
            retainedNew = physical.captured.st_ino == journal.newInode && manifest.digest == journal.newDigest
        }
        let action = try recoveryDecision(journal.state, targetOld, targetNew, retainedOld, targetNew && retainedOld)
        if journal.state == .committed { guard retainedOld else { throw DisposableFailure.ambiguousState } }
        if action == .restoredOldBySwap {
            let heldOld = try root.descend(retained); try verifyOld?(heldOld)
            try PhysicalIO.exchange(root, target, retained, hooks: hooks)
            let restored = try root.descend(target)
            guard restored.captured.st_ino == journal.oldInode, try ManifestReader.read(restored).digest == journal.oldDigest else { throw DisposableFailure.ambiguousState }
            try verifyOld?(restored)
        } else if targetOld { try verifyOld?(physicalTarget) }
        if action != .none {
            try journal.transition(.rolledBack)
            try JournalStore.write(storage, data: journal.encoded, binding: binding, hooks: hooks, locked: true)
        }
        _ = retainedNew // Partial stage is deliberately retained when old target is intact.
        return action
    }
}
