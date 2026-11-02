import Foundation

// PAT-2582 journal record of one fixture transaction. The document is strict:
// exactly these fields, no unknown state, schema or origin. A record that does
// not parse is never repaired from outside information.

struct JournalRecord {
    static let kind = "patched-fixture-transaction-journal-v1"
    static let keys: Set<String> = ["schemaVersion", "kind", "transactionID", "state", "bundleName", "bundleID", "fromVersion",
        "toVersion", "cataloguePayloadSHA256", "artifactSHA256", "targetPath", "exchangePath", "device", "oldInode", "newInode",
        "beforeManifestSHA256", "afterManifestSHA256", "beforeTreeSHA256", "afterTreeSHA256", "origin"]

    let transactionID: String
    var state: TransactionState
    let bundleName: String
    let bundleID: String
    let fromVersion: String
    let toVersion: String
    let cataloguePayloadSHA256: String
    let artifactSHA256: String
    let targetPath: String
    let exchangePath: String
    let device: UInt64
    let oldInode: UInt64
    /// Zero until the staged bundle exists and has been verified.
    var newInode: UInt64
    let beforeManifestSHA256: String
    let afterManifestSHA256: String
    let beforeTreeSHA256: String
    let afterTreeSHA256: String

    var old: EntryIdentity { EntryIdentity(device: device, inode: oldInode) }
    var new: EntryIdentity? { newInode == 0 ? nil : EntryIdentity(device: device, inode: newInode) }

    var encoded: Data {
        let fields = ["\"schemaVersion\":1", "\"kind\":\"\(Self.kind)\"", "\"transactionID\":\(jsonString(transactionID))",
            "\"state\":\"\(state.rawValue)\"", "\"bundleName\":\(jsonString(bundleName))", "\"bundleID\":\(jsonString(bundleID))",
            "\"fromVersion\":\(jsonString(fromVersion))", "\"toVersion\":\(jsonString(toVersion))",
            "\"cataloguePayloadSHA256\":\"\(cataloguePayloadSHA256)\"", "\"artifactSHA256\":\"\(artifactSHA256)\"",
            "\"targetPath\":\(jsonString(targetPath))", "\"exchangePath\":\(jsonString(exchangePath))",
            "\"device\":\(device)", "\"oldInode\":\(oldInode)", "\"newInode\":\(newInode)",
            "\"beforeManifestSHA256\":\"\(beforeManifestSHA256)\"", "\"afterManifestSHA256\":\"\(afterManifestSHA256)\"",
            "\"beforeTreeSHA256\":\"\(beforeTreeSHA256)\"", "\"afterTreeSHA256\":\"\(afterTreeSHA256)\"", "\"origin\":\"fixture\""]
        return Data(("{" + fields.joined(separator: ",") + "}").utf8)
    }

    /// Anything but an exact well-typed record is `journalCorrupt`.
    static func parse(_ data: Data) throws -> JournalRecord {
        func digest(_ value: JSONValue?) -> String? { value?.string.flatMap { validDigest($0) ? $0 : nil } }
        guard let fields = try? CoreJSON.object(data, maximum: TransactionLimits.maximumJournalBytes, failure: .corruptState),
              Set(fields.keys) == keys, fields["schemaVersion"]?.unsigned == 1,
              fields["kind"]?.string.map({ sameBytes($0, kind) }) == true,
              fields["origin"]?.string.map({ sameBytes($0, "fixture") }) == true,
              let transactionID = fields["transactionID"]?.string,
              UUID(uuidString: transactionID).map({ sameBytes($0.uuidString, transactionID) }) == true,
              let state = fields["state"]?.string.flatMap({ text in TransactionState.allStates.first { sameBytes($0.rawValue, text) } }),
              let bundleName = fields["bundleName"]?.string, validBundleName(bundleName),
              let bundleID = fields["bundleID"]?.string, validIdentifier(bundleID),
              let fromVersion = fields["fromVersion"]?.string, (try? NumericVersion(fromVersion)) != nil,
              let toVersion = fields["toVersion"]?.string, (try? NumericVersion(toVersion)) != nil,
              let payload = digest(fields["cataloguePayloadSHA256"]), let artifact = digest(fields["artifactSHA256"]),
              let targetPath = fields["targetPath"]?.string, let exchangePath = fields["exchangePath"]?.string,
              let device = fields["device"]?.unsigned, device <= UInt64(UInt32.max),
              let oldInode = fields["oldInode"]?.unsigned, oldInode > 0, let newInode = fields["newInode"]?.unsigned,
              let beforeManifest = digest(fields["beforeManifestSHA256"]), let afterManifest = digest(fields["afterManifestSHA256"]),
              let beforeTree = digest(fields["beforeTreeSHA256"]), let afterTree = digest(fields["afterTreeSHA256"]) else {
            throw TransactionFailure.journalCorrupt
        }
        return JournalRecord(transactionID: transactionID, state: state, bundleName: bundleName, bundleID: bundleID,
            fromVersion: fromVersion, toVersion: toVersion, cataloguePayloadSHA256: payload, artifactSHA256: artifact,
            targetPath: targetPath, exchangePath: exchangePath, device: device, oldInode: oldInode, newInode: newInode,
            beforeManifestSHA256: beforeManifest, afterManifestSHA256: afterManifest, beforeTreeSHA256: beforeTree,
            afterTreeSHA256: afterTree)
    }
}

extension TransactionState {
    static let allStates: [TransactionState] = [.prepared, .staged, .swapIntended, .committed, .finalized, .rolledBack]
}
