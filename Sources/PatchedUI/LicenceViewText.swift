import PatchedLicensing
public struct LicenceViewText: Equatable, Sendable {
    public let heading: String
    public let detail: String
    public let account: String
    public let trialNote: String
    public let discovery: String
    public let safety: String
    public let actionLabels: [String]
    public init(_ presentation: LicencePresentation) {
        switch presentation.state {
        case .anonymous:
            heading = "Browse updates without an account"
            detail = "Sign in when you want to use update access or manage your Macs."
        case .signedIn:
            heading = "Signed in"
            detail = "Signing in alone does not grant update access."
        case .beta:
            heading = "Private beta"
            detail = "Free private beta. No card required. It does not automatically become a paid subscription."
        case .trial:
            heading = "Trial active"
            detail = "Your trial's verified expiry still applies."
        case .paid:
            heading = "Subscription active"
            detail = "Your subscription's verified access limit still applies."
        case .grace:
            heading = "Renewal grace period"
            detail = "Your existing grace period keeps its original expiry."
        case .expired:
            heading = "Update access expired"
            detail = "New third-party updates require renewed, verified access."
        case .revoked:
            heading = "Update access revoked"
            detail = "New third-party updates are unavailable until access is verified again."
        case .verificationRequired:
            heading = "Verification required"
            detail = "Patched needs to verify your licence before starting new third-party updates."
        case .outage:
            heading = "Licence service unavailable"
            detail = "Patched cannot refresh your licence. Any existing access keeps its original verified limit."
        }
        account = presentation.accountLabel
        if presentation.state == .beta {
            trialNote = "Trial unavailable during beta. Your unused 14-day trial is preserved."
        } else if presentation.intents.contains(.startTrial) {
            trialNote = "Start your 14-day trial when you choose. No card required. Signing in does not start or use a trial."
        } else {
            trialNote = "Signing in does not start or use a trial."
        }
        discovery = "Available updates remain visible without update access."
        safety = "Patched self-update and recovery remain available. Existing update safety checks still apply."
        actionLabels = presentation.intents.map {
            switch $0 {
            case .signIn: "Sign in"
            case .startTrial: "Start 14-day trial"
            case .refresh: "Refresh licence"
            case .manageMacs: "Manage Macs"
            }
        }
    }
}
