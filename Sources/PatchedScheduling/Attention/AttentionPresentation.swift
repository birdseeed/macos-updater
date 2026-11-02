public struct AttentionPresentation: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let reasons: [AttentionReason]
    public let actions: [AttentionAction]
    public let scanAvailable: Bool
    public let viewAvailable: Bool
    public let lifecycle: AttentionLifecycle
    public init(title: String, detail: String, reasons: [AttentionReason], actions: [AttentionAction],
                scanAvailable: Bool, viewAvailable: Bool, lifecycle: AttentionLifecycle) {
        self.title = title; self.detail = detail; self.reasons = reasons; self.actions = actions
        self.scanAvailable = scanAvailable; self.viewAvailable = viewAvailable; self.lifecycle = lifecycle
    }
    static let refusing = AttentionPresentation(
        title: "Needs your attention", detail: "Current update evidence is unavailable.",
        reasons: [.missingEvidence], actions: [.recheck], scanAvailable: true,
        viewAvailable: true, lifecycle: .pending)
}

extension AttentionPresentation {
    static func make(lifecycle: AttentionLifecycle, reasons: [AttentionReason],
                     actions: [AttentionAction]) -> AttentionPresentation {
        let title: String
        let detail: String
        switch lifecycle {
        case .awaitingInstaller:
            title = "Waiting for installer"
            detail = "The explicitly requested update is awaiting a result. Completion needs an independent installed-app check."
        case .recoveryRequired:
            title = "Recovery required"
            detail = "The update outcome is uncertain. Review recovery before starting this update again."
        case .installedRestartPending:
            title = "Installed, restart pending"
            detail = "The installed release was checked. A later check after a restart is needed to finish."
        case .installed:
            title = "Installed"
            detail = "The exact installed release was checked."
        case .pending:
            title = reasons.isEmpty ? "Ready for policy checks" : "Needs your attention"
            detail = reasons.isEmpty ? "Current supplied evidence permits consideration. No update has started." :
                reasons.map(explanation).joined(separator: " ")
        }
        return AttentionPresentation(title: title, detail: detail, reasons: reasons,
            actions: actions, scanAvailable: true, viewAvailable: true, lifecycle: lifecycle)
    }

    private static func explanation(_ reason: AttentionReason) -> String {
        switch reason {
        case .missingEvidence: return "Current update evidence is unavailable or uncertain. Recheck before proceeding."
        case .permissionNeeded: return "Review App Management permission to allow this update. Scanning and viewing remain available."
        case .permissionDenied: return "App Management permission was denied. Review it in System Settings."
        case .permissionRevoked: return "App Management permission was revoked. Review it before starting another update."
        case .helperUnavailable: return "The required helper is unavailable. Recheck its status."
        case .targetRunning: return "The target app is running. Close it when convenient, then recheck."
        case .interactiveApproval: return "This update needs installer input. Open the installer explicitly and review its prompts yourself."
        case .restartApproval: return "This exact update needs restart approval before it starts. Approval does not restart the Mac."
        case .installerPending: return "The installer has not produced a verified completion result."
        case .recoveryRequired: return "The update outcome is uncertain and needs recovery review."
        case .installedRestartPending: return "The update is installed and still needs a restart check."
        case .alreadyInstalled: return "The exact release is already installed."
        case .scheduleDeferred(let reason):
            switch reason {
            case .principal: return "The update owner could not be confirmed."
            case .identity: return "The exact release could not be confirmed."
            case .skipped: return "This release is skipped. Undo the skip to consider it again."
            case .automaticOff: return "Automatic updates are off."
            case .excluded: return "This app is excluded from automatic updates."
            case .paused: return "Automatic updates are paused."
            case .clock: return "Reliable update timing could not be confirmed."
            case .eligibility: return "This update has not been established as eligible."
            case .targetOpen: return "The target app must be confirmed closed."
            case .awake: return "The Mac must be confirmed awake."
            case .idle: return "Waiting for a confirmed idle opportunity."
            case .route: return "This installer route cannot start through unattended scheduling."
            }
        }
    }
}
