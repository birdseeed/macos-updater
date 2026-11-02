import Foundation
import Darwin
import CryptoKit
import ArtifactInspection
import PatchedCore

// PAT-2583 sign step. It builds the payload of Fixtures/Catalogue/README.md from a verified
// receipt and an explicit request, hands the exact message to the caller's signer, checks the
// answer against the root's public fixture trust and only then advances the durable
// high-water mark. It holds no key and writes no published file.
//
// Limits, stated rather than closed: the root is a trusted same-user namespace. A same-user
// process that changes something between the last confirmation here and the rename, or
// restores an earlier complete checkpoint afterwards, is not detected. Successful flushes are
// not a power-loss guarantee.
//
// Origin: the commit order follows this repository's own PAT-2581
// Sources/PatchedCore/ProofState.swift, duplicated privately with the operator's refusals.

/// What one signature was made over and for. Kept beside the public result, never encoded,
/// and checked again in full before anything is published.
struct OperatorSignedState: Sendable {
    let receipt: VerifiedArtifactReceipt
    let request: CatalogueRequest
    let trust: FixtureTrust
    let rootPath: String
    let rootIdentity: OperatorIdentity
    let payload: Data
    let signature: Data
}

enum CatalogueSigning {
    static let domain = "im.patched.catalogue.v1"
    static let maximumExactSecond: UInt64 = 9_007_199_254_740_991
    static let maximumLifetime: UInt64 = 259_200
    static let maximumSecondsAhead = 300.0
    static let maximumArtifactBytes: Int64 = ArtifactSizePolicy.absoluteMaximumBytes
    static let fixtureRecordKind = "patched-operator-fixture-inspection-v1"

    /// The request limits of the consumer, checked before any conversion and before any path is touched.
    static func validate(_ request: CatalogueRequest, trust: FixtureTrust, now: Double) throws {
        guard OperatorIO.sameBytes(request.keyID, trust.keyID) else { throw OperatorFailure.untrustedKey }
        guard OperatorIO.sameBytes(request.catalogueID, trust.catalogueID) else { throw OperatorFailure.wrongCatalogue }
        guard request.sequence > 0, request.issuedAt <= maximumExactSecond, request.expiresAt <= maximumExactSecond else {
            throw OperatorFailure.invalidConfiguration
        }
        guard now.isFinite, now >= 0, now <= Double(maximumExactSecond) else { throw OperatorFailure.invalidClock }
        guard request.expiresAt > request.issuedAt, request.expiresAt - request.issuedAt <= maximumLifetime else {
            throw OperatorFailure.invalidLifetime
        }
        guard Double(request.issuedAt) - now <= maximumSecondsAhead else { throw OperatorFailure.futureIssued }
        guard now < Double(request.expiresAt) else { throw OperatorFailure.expired }
        guard let minimum = version(request.minimumOS), let maximum = version(request.maximumOS),
              !maximum.lexicographicallyPrecedes(minimum) else {
            throw OperatorFailure.invalidConfiguration
        }
    }

    /// One to eight unsigned decimal components, each at most `UInt32.max`, without a leading zero
    /// except `0`. Absent trailing components count as zero, so the result is padded to eight.
    static func version(_ text: String) -> [UInt32]? {
        let parts = text.utf8.split(separator: 46, omittingEmptySubsequences: false)
        guard (1...8).contains(parts.count) else { return nil }
        var result: [UInt32] = []
        for part in parts {
            guard (1...10).contains(part.count), part.allSatisfy({ (48...57).contains($0) }), part.count == 1 || part.first != 48,
                  let value = UInt32(String(decoding: part, as: UTF8.self)) else { return nil }
            result.append(value)
        }
        return result + [UInt32](repeating: 0, count: 8 - result.count)
    }

    /// The receipt is one this library issued for an artifact directly inside this root's input
    /// directory. Labels alone decide nothing: the compiled pin, the held artifact, the cached
    /// record and the physical directories must all agree. Nothing is read from the artifact here.
    static func bind(_ receipt: VerifiedArtifactReceipt, to root: OperatorRoot) throws {
        let held = receipt.held, record = receipt.inspectionRecord
        guard receipt.origin != .replayed else { throw OperatorFailure.recordedEvidenceRefused }
        guard let pin = try? FirefoxTargets.select(version: receipt.version) else { throw OperatorFailure.unknownTarget }
        guard OperatorIO.sameBytes(receipt.bundleID, pin.bundleID), OperatorIO.sameBytes(receipt.teamID, pin.teamID),
              OperatorState.validIdentifier(pin.bundleID), pin.bundleID.utf8.contains(46), pin.teamID.utf8.count == 10,
              pin.teamID.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }), version(pin.version) != nil,
              OperatorState.validDigest(receipt.sha256), OperatorIO.sameBytes(receipt.sha256, held.sha256),
              (1...maximumArtifactBytes).contains(receipt.byteLength), receipt.byteLength == held.stamp.byteLength,
              receipt.artifactDevice == held.stamp.identity.device, receipt.artifactInode == held.stamp.identity.inode,
              receipt.byteIntegrityVerified, !receipt.installationAuthorized else { throw OperatorFailure.invalidState }
        guard (1...OperatorLimits.maximumInspectionRecordBytes).contains(record.count), record.count == receipt.inspectionRecordByteLength,
              OperatorIO.sameBytes(OperatorIO.sha256Hex(record), receipt.inspectionRecordSHA256),
              let fields = OperatorJSON.object(record, maximum: OperatorLimits.maximumInspectionRecordBytes, depth: 16) else {
            throw OperatorFailure.invalidState
        }
        func names(_ value: OperatorJSONValue?, _ text: String) -> Bool { value?.string.map { OperatorIO.sameBytes($0, text) } ?? false }

        // The directory that holds the artifact, as the receipt holds it.
        let parent: Int32
        switch receipt.origin {
        case .fixture:
            guard let source = held.root, held.ancestors == nil, held.bytes?.count == Int(held.stamp.byteLength),
                  !receipt.freshOSValidation, !receipt.appChecksPassed, !receipt.cleanupVerified, !receipt.containerSignaturePassed,
                  !receipt.containerGatekeeperPassed, !receipt.containerTicketPassed,
                  names(fields["kind"], fixtureRecordKind), names(fields["origin"], EvidenceOrigin.fixture.rawValue),
                  names(fields["version"], pin.version), names(fields["sha256"], receipt.sha256),
                  names(fields["artifactPath"], receipt.artifactPath) else { throw OperatorFailure.invalidState }
            var theirs = stat(), ours = stat()
            guard OperatorIO.sameBytes(source.path, root.path), fstat(source.directory, &theirs) == 0, fstat(root.directory, &ours) == 0,
                  OperatorIdentity(theirs) == OperatorIdentity(ours) else { throw OperatorFailure.unsafePath }
            parent = source.input
        case .live:
            guard held.root == nil, let ancestors = held.ancestors, held.bytes == nil,
                  OperatorIO.sameBytes(receipt.sha256, pin.sha256), receipt.byteLength == pin.byteLength,
                  receipt.freshOSValidation, receipt.appChecksPassed, receipt.cleanupVerified,
                  names(fields["mode"], "inspect-local"), names(fields["sourcePath"], receipt.artifactPath),
                  names(fields["pin"]?.object?["version"], pin.version), names(fields["pin"]?.object?["sha256"], pin.sha256),
                  names(fields["assessment"]?.object?["origin"], EvidenceOrigin.live.rawValue) else { throw OperatorFailure.invalidState }
            guard let expected = try? OperatorIO.components(root.path + "/" + OperatorRoot.inputName), expected.count == ancestors.names.count,
                  zip(expected, ancestors.names).allSatisfy(OperatorIO.sameBytes) else { throw OperatorFailure.unsafePath }
            parent = ancestors.directory
        case .replayed: throw OperatorFailure.recordedEvidenceRefused
        }
        // Path text is not enough: the held directory must physically be this root's input directory.
        var theirs = stat(), ours = stat()
        guard (try? OperatorIO.components("/" + held.name))?.count == 1,
              OperatorIO.sameBytes(receipt.artifactPath, root.path + "/" + OperatorRoot.inputName + "/" + held.name),
              fstat(parent, &theirs) == 0, fstat(root.input, &ours) == 0, OperatorIdentity(theirs) == OperatorIdentity(ours) else {
            throw OperatorFailure.unsafePath
        }
    }

    /// The exact payload bytes: fixed field order, integer tokens written from `UInt64` and
    /// `Int64` directly, and nothing beyond the consumer's schema. The bytes are read back
    /// strictly before they are offered for signing.
    static func payload(receipt: VerifiedArtifactReceipt, request: CatalogueRequest) throws -> Data {
        let text = OperatorIO.jsonString
        let artifact = ["\"bundleID\":" + text(receipt.bundleID), "\"teamID\":" + text(receipt.teamID), "\"platform\":\"macOS\"",
                        "\"minimumOS\":" + text(request.minimumOS), "\"maximumOS\":" + text(request.maximumOS),
                        "\"version\":" + text(receipt.version), "\"sha256\":" + text(receipt.sha256),
                        "\"byteLength\":" + String(receipt.byteLength)]
        let fields = ["\"schemaVersion\":1", "\"domain\":" + text(domain), "\"keyID\":" + text(request.keyID),
                      "\"catalogueID\":" + text(request.catalogueID), "\"sequence\":" + String(request.sequence),
                      "\"issuedAt\":" + String(request.issuedAt), "\"expiresAt\":" + String(request.expiresAt),
                      "\"artifact\":{" + artifact.joined(separator: ",") + "}"]
        let payload = Data(("{" + fields.joined(separator: ",") + "}").utf8)
        func names(_ value: OperatorJSONValue?, _ text: String) -> Bool { value?.string.map { OperatorIO.sameBytes($0, text) } ?? false }
        guard payload.count <= OperatorLimits.maximumPayloadBytes,
              let read = OperatorJSON.object(payload, maximum: OperatorLimits.maximumPayloadBytes),
              Set(read.keys) == ["schemaVersion", "domain", "keyID", "catalogueID", "sequence", "issuedAt", "expiresAt", "artifact"],
              read["schemaVersion"]?.unsigned == 1, names(read["domain"], domain), names(read["keyID"], request.keyID),
              names(read["catalogueID"], request.catalogueID), read["sequence"]?.unsigned == request.sequence,
              read["issuedAt"]?.unsigned == request.issuedAt, read["expiresAt"]?.unsigned == request.expiresAt,
              let signed = read["artifact"]?.object,
              Set(signed.keys) == ["bundleID", "teamID", "platform", "minimumOS", "maximumOS", "version", "sha256", "byteLength"],
              names(signed["bundleID"], receipt.bundleID), names(signed["teamID"], receipt.teamID), names(signed["platform"], "macOS"),
              names(signed["minimumOS"], request.minimumOS), names(signed["maximumOS"], request.maximumOS),
              names(signed["version"], receipt.version), names(signed["sha256"], receipt.sha256), receipt.byteLength > 0,
              signed["byteLength"]?.unsigned == UInt64(receipt.byteLength) else { throw OperatorFailure.invalidConfiguration }
        return payload
    }

    /// The fixed message: the domain, one NUL byte, then the exact payload bytes.
    static func frame(_ payload: Data) -> Data { Data(domain.utf8) + Data([0]) + payload }

    /// Exactly 64 bytes that verify over the frame under the root's public fixture key.
    static func verifies(_ signature: Data, payload: Data, trust: FixtureTrust) -> Bool {
        guard signature.count == 64, trust.publicKey.count == 32,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: trust.publicKey) else { return false }
        return key.isValidSignature(signature, for: frame(payload))
    }

    /// The envelope of the fixture contract: exactly `keyID`, `payload` and `signature`.
    static func envelope(keyID: String, payload: Data, signature: Data) -> Data {
        Data(("{\"keyID\":" + OperatorIO.jsonString(keyID) + ",\"payload\":\"" + payload.base64EncodedString() +
              "\",\"signature\":\"" + signature.base64EncodedString() + "\"}").utf8)
    }

    /// A test hook can observe or refuse. Whatever it throws is a refusal to persist, never a result.
    static func observed(_ hook: () throws -> Void) throws {
        do { try hook() } catch { throw OperatorFailure.persistenceFailed }
    }

    /// `name` is still the held private file and it reads back as exactly `bytes`.
    static func holds(_ descriptor: Int32, _ name: String, in directory: Int32, _ bytes: Data) throws {
        let marker = try OperatorRoot.confirmFile(descriptor, name, in: directory)
        guard Int(marker.st_size) == bytes.count, try OperatorIO.read(descriptor, marker) == bytes else { throw OperatorFailure.identityChanged }
    }

    static func sign(root: OperatorRoot, receipt: VerifiedArtifactReceipt, request: CatalogueRequest, now: Double,
                     signer: (Data) throws -> Data, hooks: OperatorHooks) throws -> SignedCatalogue {
        try validate(request, trust: root.trust, now: now)
        return try root.locked {
            let old = try root.confirm()
            // The whole check of the root, the receipt and the artifact's bytes, with the checkpoint
            // this point of the operation expects to find.
            func still(_ expected: OperatorState.Checkpoint) throws {
                guard try root.confirm() == expected else { throw OperatorFailure.identityChanged }
                try bind(receipt, to: root)
                try receipt.held.revalidate()
                // Reading the artifact is long, and a live receipt's hold checks no root record: confirmed once more.
                guard try root.confirm() == expected else { throw OperatorFailure.identityChanged }
            }
            try still(old)
            let payload = try Self.payload(receipt: receipt, request: request), digest = OperatorIO.sha256Hex(payload)
            // A lower sequence, or this sequence for any other payload, is refused before the signer is asked.
            guard request.sequence > old.sequence || (request.sequence == old.sequence && OperatorIO.sameBytes(digest, old.payloadSHA256)) else {
                throw OperatorFailure.replay
            }
            let answer: Data
            do { answer = Data(try signer(frame(payload))) } catch { throw OperatorFailure.signerFailed }
            guard verifies(answer, payload: payload, trust: root.trust) else { throw OperatorFailure.invalidSignature }
            let envelope = Self.envelope(keyID: request.keyID, payload: payload, signature: answer)
            guard envelope.count <= OperatorLimits.maximumEnvelopeBytes else { throw OperatorFailure.resourceLimit }
            var info = stat()
            guard fstat(root.directory, &info) == 0 else { throw OperatorFailure.identityChanged }
            // The signer is untrusted code: nothing is written until everything is confirmed again.
            try still(old)
            let next = OperatorState.Checkpoint(keyID: root.trust.keyID, catalogueID: root.trust.catalogueID, sequence: request.sequence,
                                                payloadSHA256: digest)
            // The identical payload at the recorded sequence changes nothing on disk.
            if next != old { try commit(next, replacing: old, in: root, hooks: hooks, still: still) }
            try still(next)
            return SignedCatalogue(
                envelope: envelope, envelopeSHA256: OperatorIO.sha256Hex(envelope), payloadSHA256: digest, keyID: request.keyID,
                catalogueID: request.catalogueID, sequence: request.sequence, receiptOrigin: receipt.origin,
                inspectionRecordSHA256: receipt.inspectionRecordSHA256, origin: "fixture", freshOSValidation: false,
                installationAuthorized: false, published: false,
                state: OperatorSignedState(receipt: receipt, request: request, trust: root.trust, rootPath: root.path,
                                           rootIdentity: OperatorIdentity(info), payload: payload, signature: answer))
        }
    }

    /// Replaces the held current checkpoint with `next` through an exclusive private temporary:
    /// written, flushed in full, renamed, the root synced and the committed file flushed in full
    /// again. Every hook report and every syscall is followed by the whole check, and the next
    /// mutation is preceded by it. A failure leaves whatever exists exactly where it is.
    private static func commit(_ next: OperatorState.Checkpoint, replacing old: OperatorState.Checkpoint, in root: OperatorRoot,
                               hooks: OperatorHooks, still: (OperatorState.Checkpoint) throws -> Void) throws {
        let bytes = OperatorState.checkpointBytes(next)
        guard bytes.count <= OperatorLimits.maximumStateBytes, (try? OperatorState.checkpoint(bytes)) == next else {
            throw OperatorFailure.persistenceFailed
        }
        // Only the record held here is replaced.
        let (current, marker) = try OperatorRoot.holdFile(OperatorRoot.checkpointName, in: root.directory)
        defer { close(current) }
        guard marker.st_size > 0, marker.st_size <= OperatorLimits.maximumStateBytes else { throw OperatorFailure.corruptState }
        let previous = try OperatorIO.read(current, marker)
        guard try OperatorState.checkpoint(previous) == old else { throw OperatorFailure.identityChanged }
        let name = OperatorRoot.temporaryPrefix + (0..<OperatorRoot.temporarySuffixBytes / 2).map { _ in
            String(format: "%02x", UInt8.random(in: .min ... .max))
        }.joined()
        try still(old)
        let temporary = try OperatorIO.createFile(name, in: root.directory, bytes)
        defer { close(temporary) }
        /// Before the rename: the old record is at the checkpoint name and the new one at the temporary name.
        func pending() throws {
            try still(old)
            try holds(current, OperatorRoot.checkpointName, in: root.directory, previous)
            try holds(temporary, name, in: root.directory, bytes)
        }
        /// After the rename: the file written here is the checkpoint, and it replaced the held old record.
        func committed() throws {
            try still(next)
            try holds(temporary, OperatorRoot.checkpointName, in: root.directory, bytes)
            var replaced = stat()
            guard try OperatorIO.named(name, in: root.directory) == nil, fstat(current, &replaced) == 0, replaced.st_nlink == 0 else {
                throw OperatorFailure.identityChanged
            }
        }
        try pending()
        try observed { try hooks.boundary?(.checkpointTemporaryWritten) }
        try pending()
        try observed { try hooks.sync?(.checkpointFileSync) }
        try pending()
        guard fsync(temporary) == 0 else { throw OperatorFailure.persistenceFailed }
        try pending()
        try observed { try hooks.sync?(.checkpointFileFullSync) }
        try pending()
        // fsync alone does not ask the drive to empty its volatile cache on macOS. No weaker fallback.
        guard fcntl(temporary, F_FULLFSYNC) == 0 else { throw OperatorFailure.persistenceFailed }
        try pending()
        try observed { try hooks.boundary?(.checkpointFileSynced) }
        try pending()
        try observed { try hooks.boundary?(.beforeCheckpointRename) }
        try pending()
        guard renameat(root.directory, name, root.directory, OperatorRoot.checkpointName) == 0 else { throw OperatorFailure.persistenceFailed }
        try committed()
        try observed { try hooks.boundary?(.checkpointRenamed) }
        try committed()
        try observed { try hooks.sync?(.rootDirectorySync) }
        try committed()
        guard fsync(root.directory) == 0 else { throw OperatorFailure.persistenceFailed }
        try committed()
        try observed { try hooks.sync?(.committedCheckpointFullSync) }
        try committed()
        // The committed file is flushed in full once more now that its name is durable.
        guard fcntl(temporary, F_FULLFSYNC) == 0 else { throw OperatorFailure.persistenceFailed }
        try committed()
        try observed { try hooks.boundary?(.rootSynced) }
        try committed()
        // Accepted only when the record read back through its name is the one just written.
        let (fresh, written) = try OperatorRoot.holdFile(OperatorRoot.checkpointName, in: root.directory)
        defer { close(fresh) }
        var held = stat()
        guard fstat(temporary, &held) == 0, OperatorIdentity(written) == OperatorIdentity(held), Int(written.st_size) == bytes.count,
              try OperatorIO.read(fresh, written) == bytes else { throw OperatorFailure.persistenceFailed }
    }
}
