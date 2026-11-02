import Combine
import Foundation
import PatchedShell
import PatchedNetworking
import PatchedUpdatePreferences

/// Retains requested declarations over the existing owners. Only explicit actions
/// open local preferences, save through their CAS owner or request a read-only scan.
@MainActor public final class NativeFirstRunController: ObservableObject {
    public enum Step: Equatable, Sendable { case welcome, review, findApps }
    public enum LocalState: Equatable, Sendable { case unopened, missing, available, unavailable }
    public enum SaveStatus: Equatable, Sendable { case unsaved, loaded, saved, missing, unavailable, refused }
    public let navigation: ShellNavigation
    public let applications: LocalApplicationsController
    public let network: NativeNetworkSettingsController
    public let networkProbe: NativeNetworkProbeController
    @Published public private(set) var step: Step = .welcome
    @Published public private(set) var localState: LocalState = .unopened
    @Published public private(set) var saveStatus: SaveStatus = .unsaved
    @Published public private(set) var isPresented = true
    @Published public private(set) var networkPresented = false
    @Published public private(set) var dailyChecks = true
    @Published public private(set) var notifications = true
    @Published public private(set) var failureReports = true
    private let fixturePreferences: PreferenceSession?
    private let fixtureGeneration: String?
    private let fixtureOnOpen: @MainActor () throws -> Void
    private var nativeContext: NativePreferenceContext?
    private var preferences: PreferenceSession?
    private var generation: String?
    private var opened = false
    private var lastLoadProvedMissing = false
    private var choicesEdited = false
    private var networkEdited = false
    private var restoringNetwork = false
    private var networkChanges: AnyCancellable?
    private var retainedNetworkRevision: UInt64
    @Published public private(set) var lastRefusal: PreferenceRefusal?
    // The shared owner alone publishes accepted state. A latched failure never
    // leaves an optimistic copy of setup in this controller.
    // Reading this bridge never acquires storage or changes ownership.
    var acquiredScheduleOwner: (session: PreferenceSession, generation: String)? {
        guard opened, let preferences, let generation else { return nil }
        return (preferences, generation)
    }
    public var acceptedRevision: UInt64? { preferences?.acceptedRevision }
    public var firstRunSetup: FirstRunSetupState? { preferences?.firstRunSetup }
    public var statusText: String {
        if let lastRefusal {
            return "Choices unsaved. Local preferences refused: " + lastRefusal.rawValue + ". Reload saved preferences before retrying a latched failure."
        }
        switch saveStatus {
        case .saved: return "Choices saved locally. Setup does not grant macOS permission."
        case .loaded: return "Saved choices loaded locally."
        case .missing: return "Choices unsaved. Local preferences are missing. Create fresh preferences explicitly to save choices."
        case .unavailable: return "Choices unsaved. Local preferences are unavailable."
        case .refused: return "Choices unsaved. The local preference action was refused."
        case .unsaved: return "Choices unsaved. No new choices have been accepted locally."
        }
    }

    public init(navigation: ShellNavigation, applications: LocalApplicationsController,
                network: NativeNetworkSettingsController, networkProbe: NativeNetworkProbeController? = nil) {
        self.navigation = navigation; self.applications = applications; self.network = network
        let probe = networkProbe ?? NativeNetworkProbeController(settings: network)
        precondition(probe.settings === network, "Probe settings owner must match first-run")
        self.networkProbe = probe
        fixturePreferences = nil; fixtureGeneration = nil; fixtureOnOpen = {}
        retainedNetworkRevision = network.revision
        observeNetworkEdits()
    }
    @_spi(Testing) public init(navigation: ShellNavigation, applications: LocalApplicationsController,
        network: NativeNetworkSettingsController, preferences: PreferenceSession, generation: String,
        onOpen: @escaping @MainActor () throws -> Void = {}, initiallyPresented: Bool = true,
        networkProbe: NativeNetworkProbeController? = nil) {
        self.navigation = navigation; self.applications = applications; self.network = network
        let probe = networkProbe ?? NativeNetworkProbeController(settings: network)
        precondition(probe.settings === network, "Probe settings owner must match first-run")
        self.networkProbe = probe
        fixturePreferences = preferences; fixtureGeneration = generation; fixtureOnOpen = onOpen
        isPresented = initiallyPresented
        retainedNetworkRevision = network.revision
        observeNetworkEdits()
    }
    private func observeNetworkEdits() {
        // revision changes only for edits, unlike observation/validation status.
        // Published delivery is synchronous; this records dirtiness without I/O.
        networkChanges = network.$revision.dropFirst().sink { [weak self] _ in
            guard let self, !self.restoringNetwork else { return }
            self.networkEdited = true
            self.saveStatus = .unsaved
        }
    }
    public func openPreferences() {
        loadPreferences(finishCompletedSetup: true)
    }
    func reloadSchedulePreferences() {
        loadPreferences(finishCompletedSetup: false)
    }
    private func loadPreferences(finishCompletedSetup: Bool) {
        if !opened {
            do {
                if let fixturePreferences, let fixtureGeneration {
                    // Testing SPI may fail before any fixture owner is acquired.
                    try fixtureOnOpen()
                    preferences = fixturePreferences; generation = fixtureGeneration
                } else {
                    let context = try NativePreferenceContext.open()
                    nativeContext = context
                    preferences = context.session; generation = context.generation
                }
                opened = true
            } catch {
                lastLoadProvedMissing = false
                localState = .unavailable; saveStatus = .unavailable
                lastRefusal = .unavailable
                return
            }
        }
        guard let preferences, let generation else { return }
        let result = preferences.reload(generation: generation)
        lastLoadProvedMissing = result == .refused(.missing)
        switch result {
        case .accepted, .replayed:
            localState = .available
            lastRefusal = nil
            // Edits made before first load and after failed saves remain drafts.
            if !choicesEdited {
                dailyChecks = preferences.scheduleSettings?.dailyChecks ?? true
                notifications = preferences.scheduleSettings?.notifications ?? true
                failureReports = preferences.firstRunSetup?.failureReports ?? true
            }
            if network.revision != retainedNetworkRevision { networkEdited = true }
            if !networkEdited && network.revision == retainedNetworkRevision,
               let draft = preferences.firstRunSetup?.networkDraft {
                restoreNetwork(draft)
            }
            if choicesEdited || networkEdited {
                saveStatus = .unsaved
            } else {
                saveStatus = preferences.firstRunSetup == nil ? .unsaved : .loaded
            }
            if finishCompletedSetup && preferences.firstRunSetup?.completed == true && !choicesEdited && !networkEdited {
                finishPresentation()
            }
        case .refused(let refusal):
            lastRefusal = refusal
            localState = refusal == .missing ? .missing : .unavailable
            saveStatus = refusal == .missing ? .missing : .unavailable
        }
    }
    private func restoreNetwork(_ draft: FirstRunNetworkDraft) {
        let mode: NetworkMode
        switch draft.mode {
        case .system: mode = .system
        case .direct: mode = .direct
        case .manualHTTP: mode = .manualHTTP
        }
        restoringNetwork = true
        defer { restoringNetwork = false }
        network.edit(mode: mode, host: draft.host, port: draft.port)
        retainedNetworkRevision = network.revision
    }
    @discardableResult public func createFreshPreferences() -> PreferenceEditResult {
        guard lastLoadProvedMissing, let preferences, let generation else {
            return .refused(lastRefusal ?? (opened ? .conflict : .missing))
        }
        lastLoadProvedMissing = false
        let result: PreferenceEditResult
        if let nativeContext { result = nativeContext.createFresh() }
        else { result = preferences.bootstrapFreshFixture(generation: generation) }
        switch result {
        case .accepted, .replayed:
            localState = .available; lastRefusal = nil; saveStatus = .unsaved
        case .refused(let refusal):
            lastRefusal = refusal; saveStatus = .unsaved
            localState = preferences.blockedReason == .missing ? .missing : .unavailable
        }
        return result
    }
    public func edit(dailyChecks: Bool, notifications: Bool, failureReports: Bool) {
        self.dailyChecks = dailyChecks; self.notifications = notifications
        self.failureReports = failureReports
        choicesEdited = true; saveStatus = .unsaved
    }
    public func showNetwork() {
        networkPresented = true
        navigation.select(.settings); navigation.selectSettings(.network)
    }
    public func returnFromNetwork() { networkPresented = false; isPresented = true }
    @discardableResult public func saveChoices(complete: Bool) -> PreferenceEditResult {
        guard let preferences, let generation, let revision = preferences.acceptedRevision else {
            lastRefusal = lastRefusal ?? .missing; saveStatus = .unsaved
            return .refused(lastRefusal ?? .missing)
        }
        lastLoadProvedMissing = false
        let mode: FirstRunNetworkDraftMode
        switch network.mode {
        case .system: mode = .system
        case .direct: mode = .direct
        case .manualHTTP: mode = .manualHTTP
        }
        let choices = FirstRunChoices(dailyChecks: dailyChecks, notifications: notifications,
            failureReports: failureReports,
            networkDraft: FirstRunNetworkDraft(mode: mode, host: network.host, port: network.port))
        let result = preferences.saveFirstRunChoices(choices, complete: complete,
            mutationID: UUID().uuidString.lowercased(), expectedRevision: revision, generation: generation)
        switch result {
        case .accepted, .replayed:
            choicesEdited = false; networkEdited = false
            retainedNetworkRevision = network.revision
            localState = .available; lastRefusal = nil; saveStatus = .saved
        case .refused(let refusal):
            // Retain the declarations, including false opt-outs, through reload.
            choicesEdited = true; networkEdited = true
            lastRefusal = refusal; saveStatus = .unsaved
            if let blocked = preferences.blockedReason {
                localState = blocked == .missing ? .missing : .unavailable
            }
        }
        return result
    }
    private func accepted(_ result: PreferenceEditResult) -> Bool {
        switch result { case .accepted, .replayed: return true; case .refused: return false }
    }
    private func finishPresentation() {
        isPresented = false; networkPresented = false
        navigation.select(.updates)
    }
    public func findApps() {
        guard isPresented, accepted(saveChoices(complete: true)) else { return }
        finishPresentation()
        applications.scan()
    }
    public func openUpdates() {
        guard isPresented, accepted(saveChoices(complete: true)) else { return }
        finishPresentation()
    }
    public func scanWithoutSaving() {
        guard isPresented, localState == .missing || localState == .unavailable else { return }
        saveStatus = .unsaved
        finishPresentation()
        applications.scan()
    }
    public func present() { isPresented = true }
    public func dismiss() { isPresented = false; networkPresented = false }
    public func advance() {
        guard isPresented else { return }
        switch step {
        case .welcome:
            openPreferences()
            if isPresented { step = .review }
        case .review:
            if accepted(saveChoices(complete: false)) { step = .findApps }
        case .findApps: findApps()
        }
    }
    public func back() {
        switch step {
        case .welcome: break
        case .review: step = .welcome
        case .findApps: step = .review
        }
    }
}
