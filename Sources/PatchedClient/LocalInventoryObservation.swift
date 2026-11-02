import Foundation

/// Bounds of an explicit read-only observation, never installation authority.
public enum LocalInventoryLimits {
    public static let applications = 512
    public static let directoryEntries = 8192
    public static let directoryDepth = 4
    public static let plistBytes = 1_048_576
    public static let totalMetadataBytes = 16_777_216
    public static let issues = 512
    public static let fieldBytes = 1024
    public static let pathBytes = 4096
}
public enum LocalInventoryProvenance: Sendable, Equatable { case native, fixture }
public enum LocalInventoryCompleteness: Sendable, Equatable { case complete, incomplete, unavailable }
public enum LocalInventoryRootScope: Sendable, Equatable { case systemApplications, userApplications, fixture }
public enum LocalInventoryRootStatus: Sendable, Equatable { case scanned, absent, refused, unavailable }
public enum LocalInventoryMetadataDisposition: Sendable, Equatable { case observed, unavailable, malformed, refused }
public enum LocalInventoryIssueKind: Sendable, Equatable {
    case unavailable, unsafePath, unreadable, malformedMetadata, metadataUnavailable, changedDuringScan
    case entryLimit, depthLimit, applicationLimit, plistLimit, totalMetadataLimit, issueLimit, fieldLimit, pathLimit
    case generationExhausted
}
public struct LocalInventoryRootObservation: Sendable, Equatable {
    public let path: String
    public let scope: LocalInventoryRootScope
    public let status: LocalInventoryRootStatus
}
public struct LocalInventoryIssue: Sendable, Equatable {
    public let kind: LocalInventoryIssueKind
    public let path: String?
}
/// These identifiers describe one observation; they are not durable execution authority.
public struct LocalInventoryPhysicalIdentity: Sendable, Equatable {
    public let device: UInt64
    public let inode: UInt64
    public let changeSeconds: Int64
    public let changeNanoseconds: Int64
}
public struct LocalApplicationObservation: Sendable, Equatable {
    /// A scan-bound observation only. Construction is internal; raw public claims
    /// and synthetic catalogue values cannot manufacture this qualification.
    public let installedIdentity: LocalInstalledIdentity?
    public let path: String
    public let physicalIdentity: LocalInventoryPhysicalIdentity
    public let displayName: String
    public let claimedBundleIdentifier: String?
    public let claimedShortVersion: String?
    public let claimedBuild: String?
    public let metadataDisposition: LocalInventoryMetadataDisposition
    public let vendorMetadata: LocalInstalledVendorMetadata
    public let installedIcon: LocalInstalledIcon?

    internal init(path: String, physicalIdentity: LocalInventoryPhysicalIdentity, displayName: String,
                  claimedBundleIdentifier: String?, claimedShortVersion: String?, claimedBuild: String?,
                  metadataDisposition: LocalInventoryMetadataDisposition,
                  vendorMetadata: LocalInstalledVendorMetadata = .unavailable,
                  installedIcon: LocalInstalledIcon? = nil,
                  installedIdentity: LocalInstalledIdentity? = nil) {
        self.installedIdentity = installedIdentity
        self.path = path
        self.physicalIdentity = physicalIdentity
        self.displayName = displayName
        self.claimedBundleIdentifier = claimedBundleIdentifier
        self.claimedShortVersion = claimedShortVersion
        self.claimedBuild = claimedBuild
        self.metadataDisposition = metadataDisposition
        self.vendorMetadata = vendorMetadata
        self.installedIcon = installedIcon
    }
    /// Publisher, product, edition, channel, architecture, running status, Homebrew
    /// ownership, catalogue matching and update eligibility are all unknown.
    public var authorityUnknown: Bool { true }
    public var installationAllowed: Bool { false }
}
public struct LocalInstalledIdentity: Sendable, Equatable {
    public let teamID: String
    public let bundleIdentifier: String
    public let version: String
    public let sessionID: UUID
    public let generation: UInt64
    public let physicalIdentity: LocalInventoryPhysicalIdentity
    public let provenance: LocalInventoryProvenance
    internal init(teamID: String, bundleIdentifier: String, version: String,
                  sessionID: UUID, generation: UInt64,
                  physicalIdentity: LocalInventoryPhysicalIdentity, provenance: LocalInventoryProvenance) {
        self.teamID = teamID; self.bundleIdentifier = bundleIdentifier; self.version = version
        self.sessionID = sessionID; self.generation = generation
        self.physicalIdentity = physicalIdentity; self.provenance = provenance
    }
}
public struct LocalInventoryObservation: Sendable, Equatable {
    public let sessionID: UUID
    public let generation: UInt64
    public let startedAt: Date
    public let finishedAt: Date
    public let provenance: LocalInventoryProvenance
    public let roots: [LocalInventoryRootObservation]
    public let applications: [LocalApplicationObservation]
    public let issues: [LocalInventoryIssue]
    public let completeness: LocalInventoryCompleteness
    public var authorityUnknown: Bool { true }
    public var installationAllowed: Bool { false }
}
/// A test-only notification of a real filesystem operation, not an outcome supplier.
@_spi(Testing) public enum LocalInventoryReadEvent: Sendable {
    case beforeMetadataRead(applicationPath: String)
    case beforeProductMetadataRead(applicationPath: String)
    case beforeIconRead(applicationPath: String)
    case beforeIconDecode(applicationPath: String)
}
