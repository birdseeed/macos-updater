import Foundation

/// Data-only testing seam. It neither opens paths nor observes physical
/// identity, and cannot construct or adopt any runtime/native authority.
@_spi(Testing) public enum SyntheticProfileMarkers {
    public static func matches(bytes: Data, profile: DisposableTargetProfile = .legacy,
                               runID: String, caseRoot: String?, uid: UInt32,
                               device: UInt64, inode: UInt64, binarySHA256: String) -> Bool {
        (try? ProfileMarker.authenticate(bytes, profile: profile, runID: runID, caseRoot: caseRoot,
            uid: uid, device: device, inode: inode, binarySHA256: binarySHA256)) != nil
    }
}

/// Strict pure parser only. Productive callers supply their physically held
/// directory identities and selected, physically validated profile.
enum ProfileMarker {
    static func authenticate(_ bytes: Data, profile: DisposableTargetProfile, runID: String, caseRoot: String?,
                             uid: UInt32, device: UInt64, inode: UInt64, binarySHA256: String) throws {
        let o = try StrictObject.decode(bytes, maximum: 4096, failure: .notAuthorized)
        guard Set(o.keys) == ["schemaVersion", "kind", "guestUUIDSHA256", "uid", "runID", "caseRoot", "device", "inode", "binarySHA256"],
              unsigned(o["schemaVersion"]) == 1,
              o["kind"] as? String == (caseRoot == nil ? "patched-disposable-run-v1" : "patched-disposable-case-v1"),
              o["guestUUIDSHA256"] as? String == profile.guestUUIDSHA256, unsigned(o["uid"]) == UInt64(uid),
              o["runID"] as? String == runID, o["caseRoot"] as? String == (caseRoot ?? ""),
              unsigned(o["device"]) == device, unsigned(o["inode"]) == inode,
              o["binarySHA256"] as? String == binarySHA256 else { throw DisposableFailure.notAuthorized }
    }
}
