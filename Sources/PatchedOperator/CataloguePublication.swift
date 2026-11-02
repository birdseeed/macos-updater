import Foundation
import Darwin
import ArtifactInspection
import PatchedCore

// PAT-2583 publish step. It writes the exact signed envelope, the exact inspection record
// the receipt bound, and two small digest-linked records into one new private directory of
// the held root: created under a pending name, flushed, then renamed without replacing
// anything. It signs nothing and never moves the high-water mark.
//
// Limits, stated rather than closed: the root is a trusted same-user namespace. A same-user
// process that changes something between the last confirmation here and the rename, or after
// the final read back, is not detected. Successful flushes are not a power-loss guarantee.
// A local fixture publication is never a production release.

enum CataloguePublication {
    static let publicationPrefix = "sequence-"
    static let pendingPrefix = "pending-sequence-"
    static let inspectionRecordName = "inspection-record.json"
    static let evidenceName = "evidence.json"
    static let catalogueName = "catalogue.json"
    static let publicationRecordName = "publication.json"

    /// The signed result is the one this library returned for this root and this trust, and its
    /// bytes, digests and signature are still exactly what was signed. Nothing is read from disk here.
    private static func confirmSigned(_ signed: SignedCatalogue, for root: OperatorRoot) throws {
        let state = signed.state, request = state.request, receipt = state.receipt
        var info = stat()
        guard fstat(root.directory, &info) == 0, OperatorIdentity(info) == state.rootIdentity, OperatorIO.sameBytes(root.path, state.rootPath),
              OperatorIO.sameBytes(root.trust.keyID, state.trust.keyID), OperatorIO.sameBytes(root.trust.catalogueID, state.trust.catalogueID),
              root.trust.publicKey == state.trust.publicKey else { throw OperatorFailure.unsafePath }
        guard try CatalogueSigning.payload(receipt: receipt, request: request) == state.payload,
              CatalogueSigning.verifies(state.signature, payload: state.payload, trust: root.trust) else { throw OperatorFailure.invalidSignature }
        guard signed.envelope == CatalogueSigning.envelope(keyID: request.keyID, payload: state.payload, signature: state.signature),
              signed.envelope.count <= OperatorLimits.maximumEnvelopeBytes,
              OperatorIO.sameBytes(signed.envelopeSHA256, OperatorIO.sha256Hex(signed.envelope)),
              OperatorIO.sameBytes(signed.payloadSHA256, OperatorIO.sha256Hex(state.payload)),
              OperatorIO.sameBytes(signed.keyID, request.keyID), OperatorIO.sameBytes(signed.catalogueID, request.catalogueID),
              signed.sequence == request.sequence, signed.receiptOrigin == receipt.origin,
              OperatorIO.sameBytes(signed.inspectionRecordSHA256, receipt.inspectionRecordSHA256), OperatorIO.sameBytes(signed.origin, "fixture"),
              !signed.freshOSValidation, !signed.installationAuthorized, !signed.published else { throw OperatorFailure.invalidState }
    }

    /// The separate evidence: what the receipt recorded, beside the catalogue's own fixture origin.
    private static func evidence(_ receipt: VerifiedArtifactReceipt) -> Data {
        let text = OperatorIO.jsonString
        let fields: [String] = [
            "\"schemaVersion\":1", "\"kind\":\"patched-operator-evidence-v1\"", "\"receiptOrigin\":" + text(receipt.origin.rawValue),
            "\"catalogueOrigin\":\"fixture\"", "\"version\":" + text(receipt.version), "\"bundleID\":" + text(receipt.bundleID),
            "\"teamID\":" + text(receipt.teamID), "\"sha256\":" + text(receipt.sha256), "\"byteLength\":" + String(receipt.byteLength),
            "\"byteIntegrityVerified\":\(receipt.byteIntegrityVerified)", "\"appChecksPassed\":\(receipt.appChecksPassed)",
            "\"containerSignaturePassed\":\(receipt.containerSignaturePassed)",
            "\"containerGatekeeperPassed\":\(receipt.containerGatekeeperPassed)", "\"containerTicketPassed\":\(receipt.containerTicketPassed)",
            "\"cleanupVerified\":\(receipt.cleanupVerified)", "\"freshOSValidation\":\(receipt.freshOSValidation)",
            "\"inspectionRecordSHA256\":" + text(receipt.inspectionRecordSHA256),
            "\"inspectionRecordByteLength\":" + String(receipt.inspectionRecordByteLength),
            "\"installationAuthorized\":false", "\"productionPublication\":false"]
        return Data(("{" + fields.joined(separator: ",") + "}").utf8)
    }

    /// The record that links the files beside it by digest.
    private static func publicationRecord(_ signed: SignedCatalogue, evidence: Data) -> Data {
        let text = OperatorIO.jsonString
        let fields: [String] = [
            "\"schemaVersion\":1", "\"kind\":\"patched-operator-publication-v1\"", "\"keyID\":" + text(signed.keyID),
            "\"catalogueID\":" + text(signed.catalogueID), "\"sequence\":" + String(signed.sequence),
            "\"catalogueSHA256\":" + text(signed.envelopeSHA256), "\"catalogueByteLength\":" + String(signed.envelope.count),
            "\"payloadSHA256\":" + text(signed.payloadSHA256), "\"evidenceSHA256\":" + text(OperatorIO.sha256Hex(evidence)),
            "\"inspectionRecordSHA256\":" + text(signed.inspectionRecordSHA256), "\"origin\":\"fixture\"",
            "\"installationAuthorized\":false", "\"productionPublication\":false"]
        return Data(("{" + fields.joined(separator: ",") + "}").utf8)
    }

    static func publish(root: OperatorRoot, signed: SignedCatalogue, now: Double, hooks: OperatorHooks) throws -> PublishedCatalogue {
        let receipt = signed.state.receipt, request = signed.state.request
        try confirmSigned(signed, for: root)
        try CatalogueSigning.validate(request, trust: root.trust, now: now)
        return try root.locked {
            // Publishing requires the signed catalogue to be the one the checkpoint records, and
            // the checkpoint must stay exactly that record throughout.
            let mark = try root.confirm()
            guard mark.sequence == request.sequence, OperatorIO.sameBytes(mark.payloadSHA256, signed.payloadSHA256) else {
                throw OperatorFailure.replay
            }
            func still() throws {
                guard try root.confirm() == mark else { throw OperatorFailure.identityChanged }
                try confirmSigned(signed, for: root)
                try CatalogueSigning.bind(receipt, to: root)
                try receipt.held.revalidate()
                // Reading the artifact is long, and a live receipt's hold checks no root record: confirmed once more.
                guard try root.confirm() == mark else { throw OperatorFailure.identityChanged }
            }
            try still()

            let record = receipt.inspectionRecord, evidence = Self.evidence(receipt)
            let contents: [(name: String, bytes: Data)] = [
                (inspectionRecordName, record), (evidenceName, evidence), (catalogueName, signed.envelope),
                (publicationRecordName, publicationRecord(signed, evidence: evidence))]
            guard record.count <= OperatorLimits.maximumInspectionRecordBytes, evidence.count <= OperatorLimits.maximumEvidenceBytes,
                  contents[3].bytes.count <= OperatorLimits.maximumStateBytes, contents.allSatisfy({ !$0.bytes.isEmpty }) else {
                throw OperatorFailure.resourceLimit
            }
            let accepted = publicationPrefix + String(request.sequence), pendingName = pendingPrefix + String(request.sequence)
            // Any entry at either name, whatever it is, is earlier output: never adopted, completed or replaced.
            guard try OperatorIO.named(accepted, in: root.publications) == nil,
                  try OperatorIO.named(pendingName, in: root.publications) == nil else { throw OperatorFailure.existingOutput }
            guard mkdirat(root.publications, pendingName, 0o700) == 0 else {
                throw errno == EEXIST ? OperatorFailure.existingOutput : OperatorFailure.persistenceFailed
            }
            let pending = openat(root.publications, pendingName, OperatorIO.directoryFlags)
            guard pending >= 0 else { throw OperatorFailure.persistenceFailed }
            var written: [(name: String, descriptor: Int32, bytes: Data)] = []
            defer { for file in written { close(file.descriptor) }; close(pending) }
            var created = stat()
            guard fchmod(pending, 0o700) == 0, fstat(pending, &created) == 0, (try? OperatorIO.requirePrivateDirectory(created)) != nil else {
                throw OperatorFailure.persistenceFailed
            }

            /// The whole check, then the output itself: the held directory is the private entry at
            /// the one name it should have and no entry has the other; it holds exactly the files
            /// written so far; and each is still its held private file with exactly its bytes.
            func confirmed(as name: String, not other: String) throws {
                try still()
                func placed() throws {
                    var info = stat()
                    guard let entry = try OperatorIO.named(name, in: root.publications), OperatorIO.kind(entry) == S_IFDIR,
                          fstat(pending, &info) == 0, info.st_nlink > 0, OperatorIdentity(info) == OperatorIdentity(entry),
                          OperatorIdentity(info) == OperatorIdentity(created) else { throw OperatorFailure.identityChanged }
                    try OperatorIO.requirePrivateDirectory(info)
                    guard try OperatorIO.named(other, in: root.publications) == nil else {
                        throw OperatorIO.sameBytes(other, accepted) ? OperatorFailure.existingOutput : OperatorFailure.identityChanged
                    }
                }
                try placed()
                guard let names = try OperatorIO.names(in: pending, limit: contents.count), names.count == written.count,
                      names.allSatisfy({ name in written.contains { OperatorIO.sameBytes($0.name, name) } }) else {
                    throw OperatorFailure.identityChanged
                }
                for file in written { try CatalogueSigning.holds(file.descriptor, file.name, in: pending, file.bytes) }
                // The files were read after the root and the directory were confirmed: both once more, without the artifact.
                guard try root.confirm() == mark else { throw OperatorFailure.identityChanged }
                try placed()
            }
            func uncommitted() throws { try confirmed(as: pendingName, not: accepted) }
            func committed() throws { try confirmed(as: accepted, not: pendingName) }

            try uncommitted()
            try CatalogueSigning.observed { try hooks.boundary?(.pendingCreated) }
            let boundaries: [OperatorBoundary] = [.inspectionRecordWritten, .evidenceWritten, .catalogueWritten, .publicationRecordWritten]
            for (file, boundary) in zip(contents, boundaries) {
                try uncommitted()
                let descriptor = try OperatorIO.createFile(file.name, in: pending, file.bytes)
                written.append((file.name, descriptor, file.bytes))
                try uncommitted()
                try CatalogueSigning.observed { try hooks.boundary?(boundary) }
            }
            for file in written {
                try uncommitted()
                try CatalogueSigning.observed { try hooks.sync?(.publicationFileSync) }
                try uncommitted()
                guard fsync(file.descriptor) == 0 else { throw OperatorFailure.persistenceFailed }
                try uncommitted()
                try CatalogueSigning.observed { try hooks.sync?(.publicationFileFullSync) }
                try uncommitted()
                // fsync alone does not ask the drive to empty its volatile cache on macOS. No weaker fallback.
                guard fcntl(file.descriptor, F_FULLFSYNC) == 0 else { throw OperatorFailure.persistenceFailed }
            }
            try uncommitted()
            try CatalogueSigning.observed { try hooks.boundary?(.pendingFilesSynced) }
            try uncommitted()
            try CatalogueSigning.observed { try hooks.sync?(.pendingDirectorySync) }
            try uncommitted()
            guard fsync(pending) == 0 else { throw OperatorFailure.persistenceFailed }
            try uncommitted()
            try CatalogueSigning.observed { try hooks.boundary?(.pendingDirectorySynced) }
            try uncommitted()
            try CatalogueSigning.observed { try hooks.boundary?(.beforePublicationRename) }
            try uncommitted()
            // Both names are in the one held directory. The rename replaces nothing.
            guard renameatx_np(root.publications, pendingName, root.publications, accepted, UInt32(RENAME_EXCL)) == 0 else {
                throw errno == EEXIST ? OperatorFailure.existingOutput : OperatorFailure.persistenceFailed
            }
            try committed()
            try CatalogueSigning.observed { try hooks.boundary?(.publicationRenamed) }
            try committed()
            try CatalogueSigning.observed { try hooks.sync?(.publicationsDirectorySync) }
            try committed()
            guard fsync(root.publications) == 0 else { throw OperatorFailure.persistenceFailed }
            try committed()
            try CatalogueSigning.observed { try hooks.boundary?(.publicationsSynced) }
            try committed()
            // Accepted only when every file read back through its committed name is the one written.
            for file in written {
                let (fresh, info) = try OperatorRoot.holdFile(file.name, in: pending)
                defer { close(fresh) }
                var held = stat()
                guard fstat(file.descriptor, &held) == 0, OperatorIdentity(info) == OperatorIdentity(held), Int(info.st_size) == file.bytes.count,
                      try OperatorIO.read(fresh, info) == file.bytes else { throw OperatorFailure.persistenceFailed }
            }
            try committed()
            let directory = root.path + "/" + OperatorRoot.publicationsName + "/" + accepted
            return PublishedCatalogue(
                publicationPath: directory, cataloguePath: directory + "/" + catalogueName, evidencePath: directory + "/" + evidenceName,
                inspectionRecordPath: directory + "/" + inspectionRecordName, publicationRecordPath: directory + "/" + publicationRecordName,
                envelopeSHA256: signed.envelopeSHA256, envelopeByteLength: signed.envelope.count, payloadSHA256: signed.payloadSHA256,
                evidenceSHA256: OperatorIO.sha256Hex(evidence), inspectionRecordSHA256: receipt.inspectionRecordSHA256, keyID: signed.keyID,
                catalogueID: signed.catalogueID, sequence: signed.sequence, receiptOrigin: receipt.origin, origin: "fixture",
                freshOSValidation: false, installationAuthorized: false, productionPublication: false)
        }
    }
}
