/// Inert draft only. NativeNetworkSettingsController remains the sole Network validator.
public enum FirstRunNetworkDraftMode: String, Equatable, Sendable {
    case system, direct, manualHTTP
}
public struct FirstRunNetworkDraft: Equatable, Sendable {
    public let mode: FirstRunNetworkDraftMode
    public let host: String
    public let port: String
    public init(mode: FirstRunNetworkDraftMode = .system, host: String = "", port: String = "") {
        self.mode = mode; self.host = host; self.port = port
    }
}
/// Requested declarations only, never permissions, transport acceptance or execution authority.
public struct FirstRunChoices: Equatable, Sendable {
    public let dailyChecks: Bool
    public let notifications: Bool
    public let failureReports: Bool
    public let networkDraft: FirstRunNetworkDraft
    public init(dailyChecks: Bool = true, notifications: Bool = true, failureReports: Bool = true,
                networkDraft: FirstRunNetworkDraft = FirstRunNetworkDraft()) {
        self.dailyChecks = dailyChecks; self.notifications = notifications
        self.failureReports = failureReports; self.networkDraft = networkDraft
    }
}
/// Durable setup fields only. Daily checks and notifications belong to schedule.settings.
public struct FirstRunSetupState: Equatable, Sendable {
    public let failureReports: Bool
    public let completed: Bool
    public let networkDraft: FirstRunNetworkDraft
    public init(failureReports: Bool = true, completed: Bool = false,
                networkDraft: FirstRunNetworkDraft = FirstRunNetworkDraft()) {
        self.failureReports = failureReports; self.completed = completed; self.networkDraft = networkDraft
    }
}
public struct FirstRunSetupMutationReceipt: Equatable, Sendable {
    public let id: String
    public let choices: FirstRunChoices
    public let complete: Bool
    @_spi(Testing) public init(id: String, choices: FirstRunChoices, complete: Bool) {
        self.id = id; self.choices = choices; self.complete = complete
    }
}
