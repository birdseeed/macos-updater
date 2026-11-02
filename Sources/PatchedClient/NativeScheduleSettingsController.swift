import Combine
import Foundation
import PatchedUpdatePreferences

/// Explicit declarations over the setup controller's sole preference owner.
@MainActor public final class NativeScheduleSettingsController: ObservableObject {
    public let firstRun: NativeFirstRunController
    @Published public private(set) var draft: ScheduleSettingsChange?
    // Presentation input is retained across navigation and is never persisted by editing.
    @Published public var pauseUTCInput = ""
    @Published public var pauseZoneInput = "UTC"
    @Published public var invalidPauseInput = false
    @Published private var loadedRevision: UInt64?
    @Published private var refusal: PreferenceRefusal?
    private var loadedOwner: PreferenceSession?
    private var loadedGeneration: String?
    private var currentOwner: PreferenceSession? {
        guard let acquired = firstRun.acquiredScheduleOwner,
              acquired.session === loadedOwner, acquired.generation == loadedGeneration,
              acquired.session.blockedReason == nil,
              acquired.session.acceptedRevision == loadedRevision else { return nil }
        return acquired.session
    }
    public var settings: ScheduleSettings? { currentOwner?.scheduleSettings }
    public var acceptedRevision: UInt64? { currentOwner?.acceptedRevision }
    public var statusText: String {
        if let refusal { return "Schedule choices unsaved. Local preferences refused: " + refusal.rawValue + ". Reload saved schedule settings before retrying." }
        guard currentOwner != nil else { return "Schedule settings unavailable. Choices unsaved. Reload saved schedule settings explicitly." }
        if draft != nil { return "Schedule choices unsaved. Save schedule choices to apply this declaration locally." }
        if settings == nil { return "Saved legacy preferences loaded. Explicit schedule migration is required." }
        return "Saved schedule choices loaded locally. Trusted scheduled update checks unavailable. Automatic installation unavailable."
    }
    public init(firstRun: NativeFirstRunController) { self.firstRun = firstRun }
    public func choose(_ change: ScheduleSettingsChange) { draft = change }
    public func reload() {
        // This existing explicit load preserves dirty setup and network declarations.
        firstRun.reloadSchedulePreferences()
        guard let acquired = firstRun.acquiredScheduleOwner,
              firstRun.lastRefusal == nil, acquired.session.blockedReason == nil else {
            loadedRevision = nil
            refusal = firstRun.lastRefusal ?? firstRun.acquiredScheduleOwner?.session.blockedReason ?? .missing
            return
        }
        loadedOwner = acquired.session; loadedGeneration = acquired.generation
        loadedRevision = acquired.session.acceptedRevision; refusal = nil
    }
    @discardableResult public func migrate() -> PreferenceEditResult {
        guard let owner = currentOwner, let generation = loadedGeneration, let revision = loadedRevision else {
            return refused()
        }
        let result = owner.migrateScheduleSettings(expectedRevision: revision, generation: generation)
        record(result)
        return result
    }
    @discardableResult public func save() -> PreferenceEditResult {
        guard let change = draft, let owner = currentOwner,
              let generation = loadedGeneration, let revision = loadedRevision else { return refused() }
        let result = owner.editScheduleSettings(change, mutationID: UUID().uuidString.lowercased(),
            expectedRevision: revision, generation: generation)
        record(result)
        switch result { case .accepted, .replayed: draft = nil; case .refused: break }
        return result
    }
    private func refused() -> PreferenceEditResult {
        let reason = firstRun.acquiredScheduleOwner?.session.blockedReason ?? refusal ?? .conflict
        refusal = reason
        return .refused(reason)
    }
    private func record(_ result: PreferenceEditResult) {
        switch result {
        case .accepted(let revision), .replayed(let revision): loadedRevision = revision; refusal = nil
        case .refused(let reason): refusal = reason
        }
    }
    @_spi(Testing) public var testPreferenceOwner: PreferenceSession? { firstRun.acquiredScheduleOwner?.session }
}
