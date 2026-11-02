import PatchedScheduling

public enum InventoryAvailability: Equatable, Sendable {
    case unknown, syntheticReady, deferredRunning, attention, skipped, syntheticCurrent, externalManaged
}
public struct InventoryProjectionRow: Sendable {
    public let identity: InventoryIdentity
    public let displayName: String
    public let availableVersion: String?
    public let availability: InventoryAvailability
    public let automaticExcluded: Bool
    init(identity: InventoryIdentity, displayName: String, availableVersion: String?,
         availability: InventoryAvailability, automaticExcluded: Bool) {
        self.identity = identity; self.displayName = displayName; self.availableVersion = availableVersion
        self.availability = availability; self.automaticExcluded = automaticExcluded
    }
}
public struct InventoryProjection: Sendable {
    public let applications: [InventoryProjectionRow]
    public let updates: [InventoryProjectionRow]
    public let generation: UInt64?
    public let preferenceRevision: UInt64?
    public let syntheticLastChecked: UInt64?
    public let isFresh: Bool
    public let detectedInstanceCount: Int
    public let modelReadyCount: Int
    public let deferredRunningCount: Int
    public let attentionCount: Int
    public let skippedCount: Int
    public let unknownCount: Int
    public let syntheticCurrentCount: Int
    public let externallyManagedCount: Int
    public let automaticExcludedCount: Int
    public var isSynthetic: Bool { true }
    public var nativeVerification: Bool { false }
    public var installationAuthority: Bool { false }
    public var verifiedUpToDateCount: Int { 0 }
    public var allVerifiedUpToDate: Bool { false }
    init(rows: [InventoryProjectionRow] = [], generation: UInt64? = nil, preferenceRevision: UInt64? = nil,
         syntheticLastChecked: UInt64? = nil, isFresh: Bool = false) {
        applications = rows; updates = rows; self.generation = generation
        self.preferenceRevision = preferenceRevision; self.syntheticLastChecked = syntheticLastChecked
        self.isFresh = isFresh; detectedInstanceCount = rows.count
        modelReadyCount = rows.filter { $0.availability == .syntheticReady }.count
        deferredRunningCount = rows.filter { $0.availability == .deferredRunning }.count
        attentionCount = rows.filter { $0.availability == .attention }.count
        skippedCount = rows.filter { $0.availability == .skipped }.count
        unknownCount = rows.filter { $0.availability == .unknown }.count
        syntheticCurrentCount = rows.filter { $0.availability == .syntheticCurrent }.count
        externallyManagedCount = rows.filter { $0.availability == .externalManaged }.count
        automaticExcludedCount = rows.filter { $0.automaticExcluded }.count
    }
}
public struct InventorySelectionRequest: Sendable {
    public let principal: SchedulingPrincipal
    public let identity: InventoryIdentity
    public let release: ReleaseIdentity
    public let observedGeneration: UInt64
    public let preferenceRevision: UInt64
    public init(principal: SchedulingPrincipal, identity: InventoryIdentity, release: ReleaseIdentity,
                observedGeneration: UInt64, preferenceRevision: UInt64) {
        self.principal = principal; self.identity = identity; self.release = release
        self.observedGeneration = observedGeneration; self.preferenceRevision = preferenceRevision
    }
}
public struct SyntheticInventorySelection: Sendable {
    public let identity: InventoryIdentity
    public let release: ReleaseIdentity
    public let observedGeneration: UInt64
    public let preferenceRevision: UInt64
    public var isSynthetic: Bool { true }
    public var nativeVerification: Bool { false }
    public var installationAuthority: Bool { false }
    init(identity: InventoryIdentity, release: ReleaseIdentity, observedGeneration: UInt64, preferenceRevision: UInt64) {
        self.identity = identity; self.release = release; self.observedGeneration = observedGeneration
        self.preferenceRevision = preferenceRevision
    }
}
public enum InventorySelectionResult: Sendable {
    case refused(InventoryRefusal), selected(SyntheticInventorySelection)
}
