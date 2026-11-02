import Foundation
import ArtifactInspection

// Separate bounded guest proof contract. Existing Core default entries remain refusing.
public enum DisposableFailure: String, Error, CaseIterable, Sendable {
    case caseConditionMissing, insufficientSpace, notImplemented, invalidArguments, unknownTarget, userTriggerRequired, guestMismatch
    case unsafePath, unknownCase, caseMismatch, existingRoot, notAuthorized, identityChanged
    case notDirectory, notRegularFile, unsafeOwner, unsafeMode, symlink, escapingLink, cyclicLink
    case hardlink, specialFile, crossVolume, treeLimit, manifestMismatch
    case lengthMismatch, digestMismatch, unapprovedArtifact, recordedEvidenceRefused
    case busy, persistenceFailed, journalMissing, journalCorrupt, journalMismatch, invalidState, ambiguousState
    case appRunning, wrongTeam, wrongBundle, wrongVersion, signatureRejected, notarizationRejected
    case ticketRejected, wrongArchitecture, invalidMount, cleanupFailed, commandFailed, commandTimedOut, outputLimit
    case invalidSignature, untrustedKey, replay, expired
}

public enum DisposableScope {
    public static let targetID = "parallels-0A0A0A0A-0000-4000-8000-000000000001"
    public static let guestUUIDSHA256 = "d0c5822c54defb6c6971336fc87f86d794dfca4d3d9497a57701f04d016de959"
    public static let runParent = "/Users/andy/PatchedProof"
    public static let guestUID: UInt32 = 501
    public static let guestHome = "/Users/andy"
    public static let guestUser = "andy"
    public static let guestHostname = "mac-staging.local"
    public static let guestOS = "27.0.1"
    public static let guestBuild = "26A434"
    public static let guestArchitecture = "arm64"
    public static let maximumEntries = 20_000
    public static let maximumDepth = 40
    public static let maximumTotalBytes: Int64 = 2_147_483_648
    public static let caseRoots = ["tampered-artifact", "truncated-artifact", "recorded-evidence",
        "wrong-signer-target", "wrong-signer-staged", "invalid-signature", "untrusted-key",
        "replayed-sequence", "expired-catalogue", "open-app", "staging", "update", "swap"]
}

public enum DisposableAction: String, CaseIterable, Sendable {
    case initializeRun = "init-run", prepareRoot = "prepare-root"
    case tamperedArtifact = "tampered-artifact", truncatedArtifact = "truncated-artifact"
    case recordedEvidence = "recorded-evidence", wrongSignerTarget = "wrong-signer-target"
    case wrongSignerStaged = "wrong-signer-staged", invalidCatalogue = "invalid-catalogue"
    case replayedCatalogue = "replayed-catalogue", openApp = "open-app"
    case stagingFailure = "staging-failure", recoverAfterStaging = "recover-after-staging"
    case update, interruptedSwap = "interrupted-swap", recoverAfterSwap = "recover-after-swap"
    case restoreOld = "restore-old", report
}
public enum DisposablePause: String, Sendable { case stageCopy = "stage-copy", beforeSwap = "before-swap", beforeCommit = "before-commit" }

/// Request parsing selects fixed paths only. It does not grant authority. There is no guest,
/// clock, installed-version, public-key, OS runner or inspection-success input.
public struct DisposableRequest: Sendable {
    public let profile: DisposableTargetProfile
    public let targetID: String
    public let runID: String
    public let caseRoot: String?
    public let action: DisposableAction
    public let explicitTrigger: Bool
    public let pause: DisposablePause?
    public let recordedEvidencePath: String?
    public let runPath: String
    public let targetPath: String?
    // Internal initialisation prevents callers constructing a validated-looking request.
}
public enum DisposableArguments {
    public static func parse(_ arguments: [String]) throws -> DisposableRequest { try parseArguments(arguments) }
}

/// Output only. A report is not a capability, has no decoder and cannot be supplied as live evidence.
public struct DisposableReport: Encodable, Sendable {
    public let action: String
    public let runID: String
    public let caseRoot: String?
    public let state: String
    public let recoveryAction: String
    public let testCatalogueTrust: Bool
    public let productionTrust: Bool
    public let installedFirefoxProof: Bool
    public let freshOSValidation: Bool
    public let binarySHA256: String
    public let sourceRevisionObservedByHarness: Bool
    public let builderProvenanceReceiptSHA256: String?
    public let builderProvenanceReceipt: Data?
    public let manifestCoverage: [String]
    public let limitations: [String]
    public let guest: GuestObservation
    public let nativeCommands: [CommandResult]
    public let appObservations: [NativeAppObservation]
    public let bundleManifests: [String: ProofManifest]
    public let imageObservations: [[String: String]]
    public let journalStatesReached: [String]
    public let independentMtreeFiles: [String: String]
    public let spaceObservations: [[String: Int64]]
    public let targetPath: String?
    public let exchangePath: String?
    public let harnessSigningObservation: CommandResult
    public let targetID: String
    public let trigger: String
    public let transactionID: String?
    public let containerObservations: [CommandResult]
    public let catalogueObservations: [[String: String]]
    public let recordedInspectionSHA256: String?
    public let ownedMountsAbsent: Bool
    public let globalProductReadiness: Bool
}
public enum DisposableProof {
    /// Real platform observation must precede every write, including init-run and report.
    /// Only physical observations bind its internal, non-exported guest authority.
    public static func execute(_ request: DisposableRequest) throws -> DisposableReport { try GuestRuntime.execute(request) }
    /// An explicit recorded input can never become fresh OS assessment or authority.
    public static func rejectRecordedEvidence(_ bytes: Data) throws { throw DisposableFailure.recordedEvidenceRefused }
}

public enum ProofState: String, Codable, CaseIterable, Sendable {
    case prepared, staging, staged, swapIntended, swapped, committed, rolledBack
}
public enum ProofRecovery: String, Sendable { case none, oldAlreadyInPlace, restoredOldBySwap }
/// Pure decisions only: these inputs can never be passed to the runtime as observations.
public enum ProofMechanics {
    public static func requireTransition(from: ProofState, to: ProofState) throws { try PatchedDisposableProof.requireTransition(from, to) }
    public static func recovery(state: ProofState, targetIsOld: Bool, targetIsNew: Bool,
                                retainedIsOld: Bool, stageMatches: Bool) throws -> ProofRecovery { try recoveryDecision(state, targetIsOld, targetIsNew, retainedIsOld, stageMatches) }
    public static func requireExactPin(_ pin: TargetPin, version: String) throws { try requirePin(pin, version) }
    public static func requireArtifactMetadata(version: String, length: Int64, sha256: String) throws { try requireArtifact(version, length, sha256) }
    public static func requireSameVolume(rootDevice: UInt64, entryDevice: UInt64) throws { try sameVolume(rootDevice, entryDevice) }
}

public struct ProofManifestEntry: Encodable, Equatable, Sendable {
    public let path: String
    public let type: String
    public let mode: UInt16
    public let byteLength: Int64
    public let link: String
    public let sha256: String
}
public struct ProofManifest: Encodable, Equatable, Sendable {
    public let entries: [ProofManifestEntry]
    public let totalBytes: Int64
    public let digest: String
}
