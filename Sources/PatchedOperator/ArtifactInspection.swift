import Foundation
import Darwin
import ArtifactInspection

// PAT-2583: the operator's artifact verification step. PHASE 2A: the live entry and the
// test-only fixture receipt operate; nothing here signs or publishes. See
// docs/operator-runbook.md for the contract these interfaces must meet.
//
// Limits, stated rather than closed: a receipt binds bytes and one physical file at the
// times they were checked here. Something that changes the file after the last check, or
// substitutes it before the first capture, is not detected by this step.

/// Typed refusals of the operator verify, sign and publish steps.
public enum OperatorFailure: String, Error, Sendable, CaseIterable {
    case notImplemented, notAuthorized, invalidState
    case recordedEvidenceRefused
    case unknownTarget, unsafePath, notRegularFile, hardlink, unsafeOwner, unsafeMode, resourceLimit
    case lengthMismatch, digestMismatch, identityChanged
    case inspectionRefused, cleanupUnverified
    case invalidConfiguration, invalidClock, invalidLifetime, futureIssued, expired
    case untrustedKey, wrongCatalogue, signerFailed, invalidSignature
    case replay, missingState, corruptState, existingNamespace, existingOutput, busy, persistenceFailed
}

/// Bounds of the operator proof. Production bounds are a later decision.
public enum OperatorLimits {
    public static let maximumFixtureArtifactBytes = 65_536
    public static let maximumInspectionRecordBytes = 4_194_304
    public static let maximumEvidenceBytes = 16_384
    public static let maximumStateBytes = 8_192
    public static let maximumEnvelopeBytes = 131_072
    public static let maximumPayloadBytes = 65_536
}

/// Output only: no public constructor, mutation or decoder. A receipt records that this
/// process verified one named artifact; it is never built from a caller's report, a
/// serialized record or a replay. It grants no installation authority.
///
/// `origin` is `live` only for a receipt returned by `OperatorVerification.verifyPinnedArtifact`.
/// The three container fields keep the disk image's own results separate from the app checks.
public struct VerifiedArtifactReceipt: Encodable, Sendable {
    public let origin: EvidenceOrigin
    public let version: String
    public let bundleID: String
    public let teamID: String
    public let sha256: String
    public let byteLength: Int64
    public let artifactPath: String
    public let artifactDevice: UInt64
    public let artifactInode: UInt64
    public let inspectionRecordSHA256: String
    public let inspectionRecordByteLength: Int
    public let byteIntegrityVerified: Bool
    public let appChecksPassed: Bool
    public let containerSignaturePassed: Bool
    public let containerGatekeeperPassed: Bool
    public let containerTicketPassed: Bool
    public let cleanupVerified: Bool
    public let freshOSValidation: Bool
    public let installationAuthorized: Bool
    /// Private to the library and never encoded: the held artifact and the exact record bytes
    /// the two digests above name, kept for the later steps to check again.
    let held: OperatorHeldArtifact
    let inspectionRecord: Data

    private enum CodingKeys: String, CodingKey {
        case origin, version, bundleID, teamID, sha256, byteLength, artifactPath, artifactDevice, artifactInode
        case inspectionRecordSHA256, inspectionRecordByteLength, byteIntegrityVerified, appChecksPassed
        case containerSignaturePassed, containerGatekeeperPassed, containerTicketPassed, cleanupVerified
        case freshOSValidation, installationAuthorized
    }
}

/// One artifact as it was verified: a descriptor for the file, held descriptors for every
/// directory above it, and the identity, length and digest it had. Nothing here writes.
final class OperatorHeldArtifact: Sendable {
    /// Fixture receipts: the root whose `input` directory holds the artifact.
    let root: OperatorRoot?
    /// Live receipts: every ancestor directory of the artifact, from `/`.
    let ancestors: OperatorHeldDirectories?
    let name: String
    let file: Int32
    let stamp: OperatorFileStamp
    let sha256: String
    /// The exact bytes of a fixture artifact. A pinned image is never held in memory.
    let bytes: Data?

    private init(root: OperatorRoot?, ancestors: OperatorHeldDirectories?, name: String, file: Int32, stamp: OperatorFileStamp,
                 sha256: String, bytes: Data?) {
        self.root = root; self.ancestors = ancestors; self.name = name; self.file = file; self.stamp = stamp
        self.sha256 = sha256; self.bytes = bytes
    }
    deinit { close(file) }
    private var parent: Int32 { root?.input ?? ancestors!.directory }

    /// A tiny file directly inside `root`'s input directory: owned, mode 0600, single link,
    /// 1 to 65,536 bytes, read once through the held descriptor.
    static func fixture(root: OperatorRoot, path: String) throws -> OperatorHeldArtifact {
        let prefix = root.path + "/" + OperatorRoot.inputName + "/"
        let name = String(decoding: path.utf8.dropFirst(prefix.utf8.count), as: UTF8.self)
        guard path.utf8.starts(with: prefix.utf8), (try? OperatorIO.components("/" + name))?.count == 1 else {
            throw OperatorFailure.unsafePath
        }
        try root.confirm()
        guard let entry = try OperatorIO.named(name, in: root.input) else { throw OperatorFailure.unsafePath }
        try OperatorIO.requirePrivateFile(entry)
        let bound = 1...Int64(OperatorLimits.maximumFixtureArtifactBytes)
        guard bound.contains(Int64(entry.st_size)) else { throw OperatorFailure.resourceLimit }
        let file = try OperatorIO.open(name, in: root.input, flags: OperatorIO.readFlags, entry: entry)
        let held: OperatorHeldArtifact
        do {
            var info = stat()
            guard fstat(file, &info) == 0 else { throw OperatorFailure.identityChanged }
            try OperatorIO.requirePrivateFile(info)
            guard bound.contains(Int64(info.st_size)) else { throw OperatorFailure.resourceLimit }
            let bytes = try OperatorIO.read(file, info)
            held = OperatorHeldArtifact(root: root, ancestors: nil, name: name, file: file, stamp: OperatorFileStamp(info),
                                        sha256: OperatorIO.sha256Hex(bytes), bytes: bytes)
        } catch { close(file); throw error }
        // The descriptor now belongs to `held`.
        try held.confirmStill()
        return held
    }

    /// One existing regular file at an absolute path that is exactly the compiled pin. Every
    /// ancestor is held without following a link before the file is opened or read.
    static func pinned(path: String, pin: TargetPin) throws -> OperatorHeldArtifact {
        let parts = try OperatorIO.components(path)
        let ancestors = try OperatorHeldDirectories(Array(parts.dropLast())), name = parts.last!
        return try withExtendedLifetime(ancestors) {
            guard let entry = try OperatorIO.named(name, in: ancestors.directory), OperatorIO.kind(entry) != S_IFLNK else {
                throw OperatorFailure.unsafePath
            }
            guard OperatorIO.kind(entry) == S_IFREG else { throw OperatorFailure.notRegularFile }
            let file = try OperatorIO.open(name, in: ancestors.directory, flags: OperatorIO.readFlags, entry: entry)
            let held: OperatorHeldArtifact
            do {
                var info = stat(), after = stat()
                guard fstat(file, &info) == 0 else { throw OperatorFailure.identityChanged }
                guard info.st_uid == geteuid() else { throw OperatorFailure.unsafeOwner }
                guard info.st_nlink == 1 else { throw OperatorFailure.hardlink }
                guard info.st_mode & 0o022 == 0 else { throw OperatorFailure.unsafeMode }
                guard Int64(info.st_size) == pin.byteLength else { throw OperatorFailure.lengthMismatch }
                guard try OperatorIO.digest(file, length: pin.byteLength) == pin.sha256 else { throw OperatorFailure.digestMismatch }
                guard fstat(file, &after) == 0, OperatorFileStamp(after) == OperatorFileStamp(info) else { throw OperatorFailure.identityChanged }
                held = OperatorHeldArtifact(root: nil, ancestors: ancestors, name: name, file: file, stamp: OperatorFileStamp(info),
                                            sha256: pin.sha256, bytes: nil)
            } catch { close(file); throw error }
            // The descriptor now belongs to `held`.
            try held.confirmStill()
            return held
        }
    }

    /// The directories above the artifact are still the held entries, and the name still shows
    /// the held file with one link, the same owner and mode, and the same length.
    private func confirmStill() throws {
        if let root { try root.confirm() }
        try ancestors?.confirm()
        var info = stat()
        guard let entry = try OperatorIO.named(name, in: parent), OperatorIO.kind(entry) == S_IFREG, fstat(file, &info) == 0,
              info.st_nlink > 0, OperatorIdentity(entry) == stamp.identity, OperatorIdentity(info) == stamp.identity else {
            throw OperatorFailure.identityChanged
        }
        guard info.st_uid == geteuid() else { throw OperatorFailure.unsafeOwner }
        guard info.st_nlink == 1 else { throw OperatorFailure.hardlink }
        guard UInt32(info.st_mode) == stamp.mode else { throw OperatorFailure.unsafeMode }
        guard Int64(info.st_size) == stamp.byteLength else { throw OperatorFailure.lengthMismatch }
    }

    /// The full check for a later step: the same physical file beneath unchanged directories,
    /// with exactly the verified length and digest, read again through the held descriptor.
    func revalidate() throws {
        try confirmStill()
        guard try OperatorIO.digest(file, length: stamp.byteLength) == sha256 else { throw OperatorFailure.digestMismatch }
        // The read can be long: the names above the file must still bind it once the digest is known.
        try confirmStill()
    }
}

/// The verify step. It runs only when called: nothing here runs at startup or on a timer.
public enum OperatorVerification {
    /// Fresh read-only inspection of one compiled Firefox 157.0/157.0.1 pin through the
    /// actual inspector. The file is held and matched to the pin before the inspector is
    /// asked, and checked again afterwards. Nothing is written to the file or beside it.
    public static func verifyPinnedArtifact(version: String, path: String) throws -> VerifiedArtifactReceipt {
        let pin = try compiledPin(version)
        let held = try OperatorHeldArtifact.pinned(path: path, pin: pin)
        let report = try inspected { try ArtifactInspector.inspectLocal(version: pin.version, path: path) }
        guard report.cleanupVerified, report.workspacePreserved == nil else { throw OperatorFailure.cleanupUnverified }
        if let refused = report.refusal { throw refusal(refused) }
        // Only the inspector's own fresh result counts. The disk image's own three results are
        // carried as they were observed: neither required to pass nor rewritten.
        guard report.byteIntegrityVerified, !report.installationAuthorized, report.pin == pin, report.mode == "inspect-local",
              report.sourcePath == path, !report.transportObservedThisRun, report.evidence != nil,
              let assessment = report.assessment, assessment.origin == .live, assessment.freshOSValidation,
              assessment.appChecksPassed, !assessment.installationAuthorized else { throw OperatorFailure.inspectionRefused }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let record = try? encoder.encode(report) else { throw OperatorFailure.inspectionRefused }
        guard record.count <= OperatorLimits.maximumInspectionRecordBytes else { throw OperatorFailure.resourceLimit }
        guard OperatorJSON.object(record, maximum: OperatorLimits.maximumInspectionRecordBytes, depth: 16) != nil else {
            throw OperatorFailure.inspectionRefused
        }
        // The source must still be the same physical file with the pinned bytes after inspection.
        try held.revalidate()
        return VerifiedArtifactReceipt(
            origin: .live, version: pin.version, bundleID: pin.bundleID, teamID: pin.teamID, sha256: pin.sha256, byteLength: pin.byteLength,
            artifactPath: path, artifactDevice: held.stamp.identity.device, artifactInode: held.stamp.identity.inode,
            inspectionRecordSHA256: OperatorIO.sha256Hex(record), inspectionRecordByteLength: record.count,
            byteIntegrityVerified: true, appChecksPassed: true, containerSignaturePassed: assessment.containerSignaturePassed,
            containerGatekeeperPassed: assessment.containerGatekeeperPassed, containerTicketPassed: assessment.containerTicketPassed,
            cleanupVerified: true, freshOSValidation: true, installationAuthorized: false, held: held, inspectionRecord: record)
    }

    /// A fixture-origin receipt for a tiny file inside `root`'s input directory. The compiled pin
    /// supplies the version, bundle and team labels only; the bytes are whatever the file holds
    /// and no macOS check is run or claimed.
    static func fixtureReceipt(root: OperatorRoot, version: String, artifactPath: String) throws -> VerifiedArtifactReceipt {
        let pin = try compiledPin(version)
        let held = try OperatorHeldArtifact.fixture(root: root, path: artifactPath)
        let identity = held.stamp.identity
        let fields: [String] = [
            "\"schemaVersion\":1", "\"kind\":\"patched-operator-fixture-inspection-v1\"", "\"origin\":\"fixture\"",
            "\"version\":" + OperatorIO.jsonString(pin.version), "\"bundleID\":" + OperatorIO.jsonString(pin.bundleID),
            "\"teamID\":" + OperatorIO.jsonString(pin.teamID), "\"sha256\":" + OperatorIO.jsonString(held.sha256),
            "\"byteLength\":" + String(held.stamp.byteLength), "\"artifactPath\":" + OperatorIO.jsonString(artifactPath),
            "\"artifactDevice\":" + String(identity.device), "\"artifactInode\":" + String(identity.inode),
            "\"byteIntegrityVerified\":true", "\"appChecksPassed\":false", "\"containerSignaturePassed\":false",
            "\"containerGatekeeperPassed\":false", "\"containerTicketPassed\":false", "\"cleanupVerified\":false",
            "\"freshOSValidation\":false", "\"installationAuthorized\":false"]
        let record = Data(("{" + fields.joined(separator: ",") + "}").utf8)
        return VerifiedArtifactReceipt(
            origin: .fixture, version: pin.version, bundleID: pin.bundleID, teamID: pin.teamID, sha256: held.sha256,
            byteLength: held.stamp.byteLength, artifactPath: artifactPath, artifactDevice: identity.device, artifactInode: identity.inode,
            inspectionRecordSHA256: OperatorIO.sha256Hex(record), inspectionRecordByteLength: record.count,
            byteIntegrityVerified: true, appChecksPassed: false, containerSignaturePassed: false, containerGatekeeperPassed: false,
            containerTicketPassed: false, cleanupVerified: false, freshOSValidation: false, installationAuthorized: false,
            held: held, inspectionRecord: record)
    }

    private static func compiledPin(_ version: String) throws -> TargetPin {
        guard let pin = try? FirefoxTargets.select(version: version) else { throw OperatorFailure.unknownTarget }
        return pin
    }
    /// A refusal the inspector raised instead of reporting keeps its own name where the operator has one.
    private static func inspected<T>(_ body: () throws -> T) throws -> T {
        do { return try body() } catch let failure as InspectionFailure { throw refusal(failure.rawValue) }
        catch { throw OperatorFailure.inspectionRefused }
    }
    private static func refusal(_ name: String) -> OperatorFailure {
        switch name {
        case InspectionFailure.unknownTarget.rawValue: .unknownTarget
        case InspectionFailure.unsafePath.rawValue: .unsafePath
        case InspectionFailure.notRegularFile.rawValue: .notRegularFile
        case InspectionFailure.lengthMismatch.rawValue: .lengthMismatch
        case InspectionFailure.digestMismatch.rawValue: .digestMismatch
        case InspectionFailure.cleanupFailed.rawValue: .cleanupUnverified
        default: .inspectionRefused
        }
    }

    /// An exported report, its `evidence` object or any other recorded inspection is untrusted
    /// text. It can be replayed by `artifact-inspector`, never accepted here as a verification.
    public static func acceptRecordedInspection(_ record: Data, version: String) throws -> VerifiedArtifactReceipt {
        throw OperatorFailure.recordedEvidenceRefused
    }
}
