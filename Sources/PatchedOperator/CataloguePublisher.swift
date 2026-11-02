import Foundation
import ArtifactInspection
import PatchedCore

// PAT-2583: interfaces of the operator's sign and publish steps. The default entries always
// refuse with `notAuthorized`: no production signing or publishing configuration exists. The
// test-only fixture authority signs with a signer its caller supplies and publishes only
// inside the disposable root it holds. See docs/operator-runbook.md for the contract.

/// The values an operator supplies explicitly. Everything else in the signed payload comes
/// from the verified receipt.
public struct CatalogueRequest: Sendable {
    public let keyID: String
    public let catalogueID: String
    public let sequence: UInt64
    public let issuedAt: UInt64
    public let expiresAt: UInt64
    public let minimumOS: String
    public let maximumOS: String
    public init(keyID: String, catalogueID: String, sequence: UInt64, issuedAt: UInt64, expiresAt: UInt64,
                minimumOS: String, maximumOS: String) {
        self.keyID = keyID; self.catalogueID = catalogueID; self.sequence = sequence
        self.issuedAt = issuedAt; self.expiresAt = expiresAt; self.minimumOS = minimumOS; self.maximumOS = maximumOS
    }
}

/// Output only: no public constructor, mutation or decoder. Signing writes no published file;
/// `envelope` holds the exact bytes a later publish step would write.
public struct SignedCatalogue: Encodable, Sendable {
    public let envelope: Data
    public let envelopeSHA256: String
    public let payloadSHA256: String
    public let keyID: String
    public let catalogueID: String
    public let sequence: UInt64
    public let receiptOrigin: EvidenceOrigin
    public let inspectionRecordSHA256: String
    public let origin: String
    public let freshOSValidation: Bool
    public let installationAuthorized: Bool
    public let published: Bool
    /// Private to the library and never encoded: what the signature was made over and for,
    /// kept for the publish step to check again.
    let state: OperatorSignedState

    private enum CodingKeys: String, CodingKey {
        case envelope, envelopeSHA256, payloadSHA256, keyID, catalogueID, sequence, receiptOrigin, inspectionRecordSHA256
        case origin, freshOSValidation, installationAuthorized, published
    }
}

/// Output only: no public constructor, mutation or decoder. Returned only after the committed
/// files were read back from disk. A local fixture publication is never a production release.
public struct PublishedCatalogue: Encodable, Sendable {
    public let publicationPath: String
    public let cataloguePath: String
    public let evidencePath: String
    public let inspectionRecordPath: String
    public let publicationRecordPath: String
    public let envelopeSHA256: String
    public let envelopeByteLength: Int
    public let payloadSHA256: String
    public let evidenceSHA256: String
    public let inspectionRecordSHA256: String
    public let keyID: String
    public let catalogueID: String
    public let sequence: UInt64
    public let receiptOrigin: EvidenceOrigin
    public let origin: String
    public let freshOSValidation: Bool
    public let installationAuthorized: Bool
    public let productionPublication: Bool
}

/// Default entry points. No production signing or publishing configuration exists in this
/// proof: a receipt, a request and any path are insufficient to sign or publish.
public enum CataloguePublisher {
    public static func sign(receipt: VerifiedArtifactReceipt, request: CatalogueRequest, now: Double) throws -> SignedCatalogue {
        throw OperatorFailure.notAuthorized
    }
    public static func publish(_ signed: SignedCatalogue, now: Double) throws -> PublishedCatalogue {
        throw OperatorFailure.notAuthorized
    }
}

/// Test-only boundaries at real filesystem steps. A probe can observe or refuse, never accept.
@_spi(Testing) public enum OperatorBoundary: String, CaseIterable, Sendable {
    case checkpointTemporaryWritten, checkpointFileSynced, beforeCheckpointRename, checkpointRenamed, rootSynced
    case pendingCreated, inspectionRecordWritten, evidenceWritten, catalogueWritten, publicationRecordWritten
    case pendingFilesSynced, pendingDirectorySynced, beforePublicationRename, publicationRenamed, publicationsSynced
}

/// Test-only refusal before each required synchronisation syscall.
@_spi(Testing) public enum OperatorSyncOperation: String, CaseIterable, Sendable {
    case checkpointFileSync, checkpointFileFullSync, rootDirectorySync, committedCheckpointFullSync
    case publicationFileSync, publicationFileFullSync, pendingDirectorySync, publicationsDirectorySync
}

/// Test-only hooks. Neither can return a result or skip a step.
@_spi(Testing) public struct OperatorHooks {
    public var boundary: ((OperatorBoundary) throws -> Void)?
    public var sync: ((OperatorSyncOperation) throws -> Void)?
    public init(boundary: ((OperatorBoundary) throws -> Void)? = nil, sync: ((OperatorSyncOperation) throws -> Void)? = nil) {
        self.boundary = boundary; self.sync = sync
    }
}

/// Test-only points during root creation, each reported after the real step it names. An
/// observer can observe or refuse, never return a result, replace a check or accept.
@_spi(Testing) public enum OperatorRootCreationPoint: String, CaseIterable, Sendable {
    case rootCaptured, inputCreated, publicationsCreated, lockFlushed, checkpointFlushed, namespaceFlushed, directoriesSynced
}

/// Test-only authority over one disposable operator root it exclusively created beneath the
/// `.build` directory that contains the running check executable. It cannot name any other
/// location, holds no key and can produce only fixture-origin output.
@_spi(Testing) public final class FixtureOperatorAuthority {
    public static let namePrefix = "patched-operator-fixture-"
    public let root: String
    private let handle: OperatorRoot
    private init(_ handle: OperatorRoot) { root = handle.path; self.handle = handle }

    /// The separate, explicit authority to create a new operator namespace. Refuses any existing one.
    public static func createFreshRoot(path: String, trust: FixtureTrust,
                                       observer: ((OperatorRootCreationPoint) throws -> Void)? = nil) throws -> FixtureOperatorAuthority {
        FixtureOperatorAuthority(try OperatorRoot.create(path: path, trust: trust, observer: observer))
    }
    /// Ordinary use. Refuses missing, reset or corrupt state and never repairs it.
    public static func reopenRoot(path: String, trust: FixtureTrust) throws -> FixtureOperatorAuthority {
        FixtureOperatorAuthority(try OperatorRoot.reopen(path: path, trust: trust))
    }
    /// A fixture-origin receipt for a tiny file inside this root's `input` directory. It records
    /// byte identity only: every macOS check stays false and `origin` is always `fixture`.
    public func fixtureReceipt(version: String, artifactPath: String) throws -> VerifiedArtifactReceipt {
        try OperatorVerification.fixtureReceipt(root: handle, version: version, artifactPath: artifactPath)
    }
    /// `signer` receives the exact message and returns a signature. Its answer is checked
    /// against this root's public fixture trust before anything is accepted.
    public func sign(receipt: VerifiedArtifactReceipt, request: CatalogueRequest, now: Double,
                     signer: (Data) throws -> Data, hooks: OperatorHooks = OperatorHooks()) throws -> SignedCatalogue {
        try CatalogueSigning.sign(root: handle, receipt: receipt, request: request, now: now, signer: signer, hooks: hooks)
    }
    /// Writes the exact signed bytes and their separate evidence into one new directory of this
    /// root. The signed catalogue must be the one this root's checkpoint records.
    public func publish(_ signed: SignedCatalogue, now: Double, hooks: OperatorHooks = OperatorHooks()) throws -> PublishedCatalogue {
        try CataloguePublication.publish(root: handle, signed: signed, now: now, hooks: hooks)
    }
}
