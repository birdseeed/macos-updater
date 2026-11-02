import Foundation
import CryptoKit
import ArtifactInspection

/// Fixture-only catalogue verification. These interfaces grant no production or installation trust.
public enum CoreFailure: String, Error, Sendable {
    case notImplemented, invalidEnvelope, invalidPayload, invalidSignature, untrustedKey
    case wrongDomain, wrongCatalogue, wrongIdentity, wrongPlatform, unsupportedOS, notNewer
    case invalidClock, invalidLifetime, futureIssued, expired, replay
    case missingState, corruptState, existingNamespace, unsafePath, stateBusy, persistenceFailed
    case notRegularFile, lengthMismatch, digestMismatch, unapprovedArtifact
}

public struct FixtureTrust: Sendable {
    public let keyID: String
    public let catalogueID: String
    public let publicKey: Data
    public init(keyID: String, catalogueID: String, publicKey: Data) {
        self.keyID = keyID; self.catalogueID = catalogueID; self.publicKey = publicKey
    }
}

public struct CandidatePolicy: Sendable {
    public let bundleID: String
    public let teamID: String
    public let platform: String
    public let osVersion: String
    public let installedVersion: String
    public init(bundleID: String, teamID: String, platform: String = "macOS",
                osVersion: String, installedVersion: String) {
        self.bundleID = bundleID; self.teamID = teamID; self.platform = platform
        self.osVersion = osVersion; self.installedVersion = installedVersion
    }
}

/// Output only: no public constructor, mutation or decoding from an asserted success record.
public struct CatalogueCandidate: Encodable, Sendable {
    public let catalogueID: String
    public let sequence: UInt64
    public let payloadSHA256: String
    public let artifact: CatalogueArtifact
    public let origin: String
    public let freshOSValidation: Bool
    public let installationAuthorized: Bool
}

public struct CatalogueArtifact: Encodable, Sendable {
    public let bundleID: String
    public let teamID: String
    public let platform: String
    public let minimumOS: String
    public let maximumOS: String
    public let version: String
    public let sha256: String
    public let byteLength: Int64
}

/// Test-only failure injection cannot create an accepted result or bypass durable state.
@_spi(Testing) public enum PersistenceStage: String, CaseIterable, Sendable {
    case temporaryWritten, fileSynced, beforeRename, renamed, directorySynced
}

/// Fault probes are test-only and can only refuse an operation before its syscall.
@_spi(Testing) public enum PersistenceSyncOperation: String, CaseIterable, Sendable {
    case fileSync, fileFullSync, directorySync, committedFileFullSync
}

/// Test-only boundary after the real namespace mkdir; it can only observe or refuse, never accept.
@_spi(Testing) public enum BootstrapBoundary: String, CaseIterable, Sendable {
    case namespaceCreated
}

public struct CatalogueVerifier {
    private let trust: FixtureTrust
    private let policy: CandidatePolicy
    private let stateDirectory: String
    private let probe: ((PersistenceStage) throws -> Void)?
    private let syncProbe: ((PersistenceSyncOperation) throws -> Void)?
    private let bootstrapProbe: ((BootstrapBoundary) throws -> Void)?

    public init(trust: FixtureTrust, policy: CandidatePolicy, stateDirectory: String) {
        self.trust = trust; self.policy = policy; self.stateDirectory = stateDirectory; self.probe = nil; self.syncProbe = nil
        self.bootstrapProbe = nil
    }
    @_spi(Testing) public init(trust: FixtureTrust, policy: CandidatePolicy, stateDirectory: String,
                               persistenceProbe: @escaping (PersistenceStage) throws -> Void) {
        self.trust = trust; self.policy = policy; self.stateDirectory = stateDirectory; self.probe = persistenceProbe; self.syncProbe = nil
        self.bootstrapProbe = nil
    }

    @_spi(Testing) public init(trust: FixtureTrust, policy: CandidatePolicy, stateDirectory: String,
                               persistenceProbe: @escaping (PersistenceStage) throws -> Void,
                               syncProbe: @escaping (PersistenceSyncOperation) throws -> Void) {
        self.trust = trust; self.policy = policy; self.stateDirectory = stateDirectory
        self.probe = persistenceProbe; self.syncProbe = syncProbe; self.bootstrapProbe = nil
    }

    @_spi(Testing) public init(trust: FixtureTrust, policy: CandidatePolicy, stateDirectory: String,
                               bootstrapProbe: @escaping (BootstrapBoundary) throws -> Void) {
        self.trust = trust; self.policy = policy; self.stateDirectory = stateDirectory
        self.probe = nil; self.syncProbe = nil; self.bootstrapProbe = bootstrapProbe
    }

    /// Fixed signed message: UTF8("im.patched.catalogue.v1\0") || exact payload bytes.
    /// Ordinary operation refuses missing, reset or corrupt proof state.
    public func verify(envelope: Data, now: Double) throws -> CatalogueCandidate {
        let candidate = try authenticate(envelope, now: now)
        let state = try ProofState.open(path: stateDirectory, trust: trust)
        try state.accept(candidate, probe: probe, syncProbe: syncProbe)
        return candidate
    }

    /// Caller explicitly authorises a fresh local fixture namespace. Refuses ANY existing namespace.
    /// Validate first; exclusively create mode-0700 namespace, persist durably before returning.
    public func bootstrapFreshProofNamespace(envelope: Data, now: Double) throws -> CatalogueCandidate {
        let candidate = try authenticate(envelope, now: now)
        let state = try ProofState.bootstrap(path: stateDirectory, trust: trust, boundary: bootstrapProbe)
        try state.accept(candidate, probe: probe, syncProbe: syncProbe)
        return candidate
    }

    private func authenticate(_ envelope: Data, now: Double) throws -> CatalogueCandidate {
        // Unix seconds are bounded to the exact integer range of the caller's
        // Double clock. Larger signed integers must never round away skew.
        let maximumExactSecond: UInt64 = 9_007_199_254_740_991
        guard now.isFinite, now >= 0, now <= Double(maximumExactSecond) else { throw CoreFailure.invalidClock }
        guard validIdentifier(trust.keyID), validIdentifier(trust.catalogueID), trust.publicKey.count == 32,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: trust.publicKey) else { throw CoreFailure.untrustedKey }
        let outer = try CoreJSON.object(envelope, maximum: 131_072, failure: .invalidEnvelope)
        try CoreJSON.keys(outer, ["keyID", "payload", "signature"], failure: .invalidEnvelope)
        guard let keyID = outer["keyID"]?.string, let encodedPayload = outer["payload"]?.string,
              let encodedSignature = outer["signature"]?.string,
              let payload = Data(base64Encoded: encodedPayload), payload.base64EncodedString() == encodedPayload,
              let signature = Data(base64Encoded: encodedSignature), signature.count == 64,
              signature.base64EncodedString() == encodedSignature else { throw CoreFailure.invalidEnvelope }
        guard keyID == trust.keyID else { throw CoreFailure.untrustedKey }
        guard payload.count <= 65_536 else { throw CoreFailure.invalidPayload }
        guard key.isValidSignature(signature, for: Data("im.patched.catalogue.v1\0".utf8) + payload) else {
            throw CoreFailure.invalidSignature
        }
        let fields = try CoreJSON.object(payload, maximum: 65_536, failure: .invalidPayload)
        try CoreJSON.keys(fields, ["schemaVersion", "domain", "keyID", "catalogueID", "sequence", "issuedAt", "expiresAt", "artifact"], failure: .invalidPayload)
        guard fields["schemaVersion"]?.unsigned == 1, let domain = fields["domain"]?.string,
              let signedKey = fields["keyID"]?.string, let catalogueID = fields["catalogueID"]?.string,
              let sequence = fields["sequence"]?.unsigned, sequence > 0,
              let issued = fields["issuedAt"]?.unsigned, issued <= maximumExactSecond,
              let expires = fields["expiresAt"]?.unsigned, expires <= maximumExactSecond,
              let artifactFields = fields["artifact"]?.object else { throw CoreFailure.invalidPayload }
        guard domain == "im.patched.catalogue.v1" else { throw CoreFailure.wrongDomain }
        guard signedKey == trust.keyID else { throw CoreFailure.untrustedKey }
        guard catalogueID == trust.catalogueID else { throw CoreFailure.wrongCatalogue }
        guard expires > issued, expires - issued <= 259_200 else { throw CoreFailure.invalidLifetime }
        guard Double(issued) - now <= 300 else { throw CoreFailure.futureIssued }
        guard now < Double(expires) else { throw CoreFailure.expired }
        let artifact = try validateArtifact(artifactFields)
        return CatalogueCandidate(catalogueID: catalogueID, sequence: sequence,
            payloadSHA256: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined(),
            artifact: artifact, origin: "fixture", freshOSValidation: false, installationAuthorized: false)
    }

    private func validateArtifact(_ fields: [String: JSONValue]) throws -> CatalogueArtifact {
        try CoreJSON.keys(fields, ["bundleID", "teamID", "platform", "minimumOS", "maximumOS", "version", "sha256", "byteLength"], failure: .invalidPayload)
        guard let bundle = fields["bundleID"]?.string, validIdentifier(bundle), bundle.contains("."),
              let team = fields["teamID"]?.string, team.utf8.count == 10,
              team.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }),
              let platform = fields["platform"]?.string, let minOS = fields["minimumOS"]?.string,
              let maxOS = fields["maximumOS"]?.string, let version = fields["version"]?.string,
              let digest = fields["sha256"]?.string, validDigest(digest),
              let length = fields["byteLength"]?.unsigned, length > 0, length <= UInt64(ArtifactSizePolicy.absoluteMaximumBytes) else { throw CoreFailure.invalidPayload }
        let minimum = try NumericVersion(minOS), maximum = try NumericVersion(maxOS)
        let target = try NumericVersion(version), host = try NumericVersion(policy.osVersion), installed = try NumericVersion(policy.installedVersion)
        guard minimum <= maximum else { throw CoreFailure.invalidPayload }
        guard bundle == policy.bundleID, team == policy.teamID else { throw CoreFailure.wrongIdentity }
        guard platform == "macOS", platform == policy.platform else { throw CoreFailure.wrongPlatform }
        guard minimum <= host, host <= maximum else { throw CoreFailure.unsupportedOS }
        guard installed < target else { throw CoreFailure.notNewer }
        return CatalogueArtifact(bundleID: bundle, teamID: team, platform: platform,
            minimumOS: minOS, maximumOS: maxOS, version: version, sha256: digest, byteLength: Int64(length))
    }
}
