import Foundation

// PAT-2582: interfaces of the reversible bundle transaction. The default entries
// always refuse with `notAuthorized`. Only the test-only fixture authority can
// run a transaction, and only inside the disposable root it created; see
// FixtureTransaction.swift. See docs/transaction-recovery.md for the contract.

/// Typed refusals of the reversible fixture bundle transaction.
public enum TransactionFailure: String, Error, Sendable, CaseIterable {
    case notImplemented, notAuthorized, userTriggerRequired
    case unsafePath, aliasedPath, existingRoot
    case missingTarget, missingSource, notDirectory, symlink, hardlink, specialFile, unsafeOwner, unsafeMode
    case crossVolume, treeLimit
    case artifactMismatch, invalidManifest, manifestMismatch, stagedBytesMismatch
    case invalidBundle, wrongBundle, wrongVersion, notNewer
    case appRunning, identityChanged
    case existingTransaction, busy, persistenceFailed
    case journalMissing, journalCorrupt, journalMismatch, ambiguousState, invalidState
}

/// Fixture bounds for every bundle tree read by a transaction. Production bounds are a later decision.
public enum TransactionLimits {
    public static let maximumEntries = 512
    public static let maximumDepth = 16
    public static let maximumTotalBytes: Int64 = 8_388_608
    public static let maximumManifestBytes = 262_144
    public static let maximumJournalBytes = 16_384
    public static let maximumInfoPlistBytes = 65_536
}

/// Only an explicit owner action may start, finish or reverse a transaction.
public enum TransactionTrigger: String, Encodable, Sendable {
    case explicitUserAction, background
}

public enum TransactionState: String, Encodable, Sendable {
    case prepared, staged, swapIntended, committed, finalized, rolledBack
}

public enum RecoveryAction: String, Encodable, Sendable {
    case none, oldAlreadyInPlace, restoredOldBySwap
}

/// The old bundle stays in the owned exchange directory under either decision. Nothing is deleted.
public enum FinalDecision: String, Encodable, Sendable {
    case keepNew, restoreOld
}

/// Output only. One physically read entry of a bundle tree; `.` is the bundle root.
public struct BundleManifestEntry: Encodable, Equatable, Sendable {
    public let path: String
    public let type: String
    public let mode: UInt16
    public let byteLength: Int64
    public let sha256: String
}

/// Output only: no public constructor or decoder.
public struct BundleManifest: Encodable, Equatable, Sendable {
    public let entries: [BundleManifestEntry]
    public let fileCount: Int
    public let directoryCount: Int
    public let totalBytes: Int64
    public let treeSHA256: String
}

/// Output only: no public constructor, mutation or decoding from an asserted success record.
/// A fixture transaction never establishes fresh OS validation or an installed Firefox update.
public struct TransactionReport: Encodable, Sendable {
    public let transactionID: String
    public let state: TransactionState
    public let recoveryAction: RecoveryAction
    public let bundleName: String
    public let bundleID: String
    public let fromVersion: String
    public let toVersion: String
    public let targetPath: String
    public let exchangePath: String
    public let journalPath: String
    public let before: BundleManifest
    public let after: BundleManifest
    public let targetNow: BundleManifest
    public let exchangeNow: BundleManifest
    public let trigger: TransactionTrigger
    public let atomicPrimitive: String
    public let runningCheck: String
    public let origin: String
    public let freshOSValidation: Bool
    public let installationAuthorized: Bool
    public let installedFirefoxProof: Bool
}

/// Names every path exactly. Nothing is discovered by scanning.
public struct UpdateRequest: Sendable {
    public let candidate: CatalogueCandidate
    public let artifactPath: String
    public let sourceBundle: String
    public let target: String
    public let transactionDirectory: String
    public let trigger: TransactionTrigger
    public init(candidate: CatalogueCandidate, artifactPath: String, sourceBundle: String, target: String,
                transactionDirectory: String, trigger: TransactionTrigger) {
        self.candidate = candidate; self.artifactPath = artifactPath; self.sourceBundle = sourceBundle
        self.target = target; self.transactionDirectory = transactionDirectory; self.trigger = trigger
    }
}

/// Default entry points. No production authority exists in this proof: a fixture catalogue
/// candidate, any caller-supplied report and any path are insufficient to replace an app.
public enum UpdateTransaction {
    public static func perform(_ request: UpdateRequest) throws -> TransactionReport {
        throw TransactionFailure.notAuthorized
    }
    public static func recover(transactionDirectory: String) throws -> TransactionReport {
        throw TransactionFailure.notAuthorized
    }
}

/// Test-only boundaries at real filesystem steps. A probe can observe or refuse, never accept.
@_spi(Testing) public enum TransactionBoundary: String, CaseIterable, Sendable {
    case transactionDirectoryCreated, lockAcquired, journalPrepared
    case stageCreated, stageCopied, stageSynced, stageVerified
    case swapIntended, swapped, targetParentSynced, beforeCommitRecord
    case beforeSwapBack, swappedBack
}

/// Test-only refusal before each required synchronisation syscall.
@_spi(Testing) public enum TransactionSyncOperation: String, CaseIterable, Sendable {
    case transactionParentSync, journalFileFullSync, journalDirectorySync
    case stagedFileFullSync, stagedDirectorySync, exchangeDirectorySync, targetParentSync
}

/// Test-only hooks. `applicationRunning` is a fixture declaration, never an OS observation.
@_spi(Testing) public struct FixtureHooks {
    public var applicationRunning: (String) -> Bool
    public var boundary: ((TransactionBoundary) throws -> Void)?
    public var sync: ((TransactionSyncOperation) throws -> Void)?
    public init(applicationRunning: @escaping (String) -> Bool,
                boundary: ((TransactionBoundary) throws -> Void)? = nil,
                sync: ((TransactionSyncOperation) throws -> Void)? = nil) {
        self.applicationRunning = applicationRunning; self.boundary = boundary; self.sync = sync
    }
}

/// Test-only authority over one disposable root it exclusively created beneath the `.build`
/// directory that contains the running check executable. It cannot name any other location.
@_spi(Testing) public final class FixtureAuthority {
    public let root: String
    // Keeps the build directory chain, the root and its marker held for the authority's lifetime.
    private let handle: FixtureRootHandle
    private init(root: String, handle: FixtureRootHandle) { self.root = root; self.handle = handle }

    public static func createFreshRoot(path: String) throws -> FixtureAuthority {
        FixtureAuthority(root: path, handle: try FixtureRootHandle.create(path: path))
    }
    public static func reopenRoot(path: String) throws -> FixtureAuthority {
        FixtureAuthority(root: path, handle: try FixtureRootHandle.reopen(path: path))
    }
    public func perform(_ request: UpdateRequest, hooks: FixtureHooks) throws -> TransactionReport {
        try FixtureTransaction.run(handle, root, hooks) { try $0.perform(request) }
    }
    public func recover(transactionDirectory: String, hooks: FixtureHooks) throws -> TransactionReport {
        try FixtureTransaction.run(handle, root, hooks) { try $0.recover(transactionDirectory) }
    }
    public func decide(_ decision: FinalDecision, transactionDirectory: String, trigger: TransactionTrigger,
                       hooks: FixtureHooks) throws -> TransactionReport {
        try FixtureTransaction.run(handle, root, hooks) { try $0.decide(decision, transactionDirectory, trigger: trigger) }
    }
}
