/// Pure local contract; these values confer no service or installation authority.
public enum SupportAction: String, CaseIterable, Sendable {
    case deactivateActivation, resendSignInCode, reconcileProviderState
    case initiateCancellation, initiateRefund, changeAccountEmail
}
public enum SupportError: String, Error, Sendable {
    case notConfigured, malformedDescriptor, digestMismatch, expired, foreignOperator
    case invalidContext, targetChanged, unknownHistory, recoveryHeld, ownershipUnproven
    case addressCollision, rollback, unknownOutcome
}
public enum SupportOutcome: String, Sendable { case committed, targetChanged }

extension SupportAction {
    var consequenceCodes: [String] {
        switch self {
        case .deactivateActivation: return ["releaseActivation"]
        case .resendSignInCode: return ["resendRegisteredAddress"]
        case .reconcileProviderState: return ["reconcileEntitlement"]
        case .initiateCancellation: return ["stopRenewalKeepPaidThrough"]
        case .initiateRefund: return ["refundIntervalOnApproval", "stopRenewalSeparately"]
        case .changeAccountEmail: return ["changeEmailRevokeSessionsReleaseActivations"]
        }
    }
}
