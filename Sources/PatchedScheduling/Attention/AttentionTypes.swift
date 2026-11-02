/// Every value in this API is injected model data, never operating evidence or
/// an installation capability. No type performs an OS or installer operation.
public enum AttentionPermission: String, CaseIterable, Equatable, Sendable {
    case unknown, notDetermined, granted, denied, revoked
}
public enum AttentionHelper: Equatable, Sendable {
    case unknown, notRequired, available, unavailable
}
public enum AttentionRequirement: Equatable, Sendable {
    case unknown, notRequired, required
}
public struct AttentionRequirements: Equatable, Sendable {
    public let restart: AttentionRequirement
    public let interaction: AttentionRequirement
    public init(restart: AttentionRequirement = .unknown,
                interaction: AttentionRequirement = .unknown) {
        self.restart = restart; self.interaction = interaction
    }
}
public struct AttentionBinding: Equatable, Sendable {
    public let principal: SchedulingPrincipal
    public let target: String
    public let release: ReleaseIdentity
    public let routeID: String
    public let requirements: AttentionRequirements
    public let observationRevision: UInt64
    public let sessionGeneration: UInt64
    public init(principal: SchedulingPrincipal, target: String, release: ReleaseIdentity,
                routeID: String, requirements: AttentionRequirements,
                observationRevision: UInt64, sessionGeneration: UInt64) {
        self.principal = principal; self.target = target; self.release = release
        self.routeID = routeID; self.requirements = requirements
        self.observationRevision = observationRevision; self.sessionGeneration = sessionGeneration
    }
}
public struct AttentionObservation: Sendable {
    public var binding: AttentionBinding
    public var permission: AttentionPermission
    public var helper: AttentionHelper
    public var conditions: StartConditions
    public var policy: SchedulePolicy
    public init(binding: AttentionBinding, permission: AttentionPermission = .unknown,
                helper: AttentionHelper = .unknown, conditions: StartConditions,
                policy: SchedulePolicy) {
        self.binding = binding; self.permission = permission; self.helper = helper
        self.conditions = conditions; self.policy = policy
    }
}
public enum AttentionReason: Equatable, Sendable {
    case missingEvidence, permissionNeeded, permissionDenied, permissionRevoked
    case helperUnavailable, targetRunning, interactiveApproval, restartApproval
    case installerPending, recoveryRequired, installedRestartPending, alreadyInstalled
    case scheduleDeferred(ScheduleDeferral)
}
public enum AttentionAction: Equatable, Sendable {
    case reviewAppManagement, recheck, approveRestart, startUpdate, launchInstaller, cancel, viewRecovery
}
public enum AttentionDecision: Equatable, Sendable {
    case blocked([AttentionReason]), unattendedPolicyEligible, explicitRoutePrepared
}
public enum AttentionLifecycle: Equatable, Sendable {
    case pending, awaitingInstaller, installed, installedRestartPending, recoveryRequired
}
public enum AttentionInstallerResult: Equatable, Sendable {
    case cancelled, failed, unknown, reportedSuccess
}
/// Opaque, controller-instance-bound model token. Public callers cannot mint it.
public struct AttentionAttempt: Equatable, Sendable {
    let owner: AttentionAttemptOwner
    let sequence: UInt64
    let binding: AttentionBinding
    init(owner: AttentionAttemptOwner, sequence: UInt64, binding: AttentionBinding) {
        self.owner = owner; self.sequence = sequence; self.binding = binding
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.owner === rhs.owner && lhs.sequence == rhs.sequence && lhs.binding == rhs.binding
    }
}
final class AttentionAttemptOwner: Sendable {}
/// Explicitly injected readback data, not a trusted native receipt. The future
/// action boundary must independently establish these facts; this model cannot.
public struct AttentionInstalledReadback: Equatable, Sendable {
    public let binding: AttentionBinding
    public let installedRelease: ReleaseIdentity
    public let restartPending: KnownSignal
    public init(binding: AttentionBinding, installedRelease: ReleaseIdentity,
                restartPending: KnownSignal) {
        self.binding = binding; self.installedRelease = installedRelease
        self.restartPending = restartPending
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.binding == rhs.binding && lhs.installedRelease == rhs.installedRelease &&
            lhs.restartPending == rhs.restartPending
    }
}
public struct AttentionPostRestartReadback: Sendable {
    public let binding: AttentionBinding
    public let installedRelease: ReleaseIdentity
    public let observedBoot: String
    public let restartPending: KnownSignal
    public init(binding: AttentionBinding, installedRelease: ReleaseIdentity,
                observedBoot: String, restartPending: KnownSignal) {
        self.binding = binding; self.installedRelease = installedRelease
        self.observedBoot = observedBoot; self.restartPending = restartPending
    }
}
