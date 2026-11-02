import SwiftUI
import PatchedActivity

public enum NativeActivityPhase: Equatable, Sendable { case idle, loaded, unavailable }
/// Describes where a last-loaded record came from, never current installed state.
public enum NativeActivityProvenance: Equatable, Sendable { case nativeLocal, testDouble }

public struct NativeActivityHelpSelection: Equatable, Sendable {
    public let event: ActivityEvent
    public let revision: UInt64
    public let provenance: NativeActivityProvenance
    // Deliberately no public constructor or caller-selected native authority.
    init(event: ActivityEvent, revision: UInt64, provenance: NativeActivityProvenance) {
        self.event = event; self.revision = revision; self.provenance = provenance
    }
}

@_spi(Testing) @MainActor public protocol NativeActivityReadSession: AnyObject {
    var snapshot: ActivitySnapshot { get }
    func reload() throws
    func createFresh() throws
    func selectRetained() throws
}

/// Concrete account-bound adapter, created only by an explicit storage action.
@MainActor private final class NativeActivityAdapter: NativeActivityReadSession {
    private let context: NativeActivityContext
    init() throws { context = try NativeActivityContext.open() }
    var snapshot: ActivitySnapshot { context.snapshot }
    func reload() throws { try context.reload() }
    func createFresh() throws { try context.createFresh() }
    func selectRetained() throws { try context.selectRetained() }
}

/// Retains last-loaded descriptive history. Construction and selection perform no IO.
@MainActor public final class NativeActivityController: ObservableObject {
    @Published public private(set) var phase: NativeActivityPhase = .idle
    @Published public private(set) var snapshot: ActivitySnapshot?
    @Published public private(set) var helpSelection: NativeActivityHelpSelection?
    public let provenance: NativeActivityProvenance
    @_spi(Testing) public let testSession: (any NativeActivityReadSession)?
    private var activeSession: (any NativeActivityReadSession)?
    public var presentation: ActivityPresentation {
        let source = provenance == .testDouble ? "Test double: last-loaded history." : "Local history: last-loaded records."
        let disclosure = "Stored local records are descriptive, not current installed-state validation."
        guard phase == .loaded, let snapshot else {
            return ActivityPresentation(headline: "Activity unavailable", provenance: source,
                retainedRange: "No local history is available to display.", policy: disclosure, rows: [])
        }
        let displayed = ActivityPresentation.make(snapshot)
        return ActivityPresentation(headline: displayed.headline, provenance: source,
            retainedRange: displayed.retainedRange, policy: displayed.policy + " • " + disclosure,
            rows: displayed.rows)
    }
    public init() {
        provenance = .nativeLocal;
        testSession = nil
    }
    @_spi(Testing) public init(session: any NativeActivityReadSession) {
        provenance = .testDouble; testSession = session
    }
    public func load() { perform(fresh: false) { try $0.reload() } }
    public func createFresh() { perform(fresh: true) { try $0.createFresh() } }
    public func applyRetention() {
        guard phase == .loaded, let activeSession else { return }
        do {
            try activeSession.selectRetained()
            try publish(activeSession.snapshot, fresh: false)
        } catch { invalidate() }
    }
    @discardableResult public func selectHelp(eventID: String) -> Bool {
        guard phase == .loaded, let snapshot, let revision = snapshot.revision else { return false }
        let matches = snapshot.events.filter { $0.eventID == eventID }
        guard matches.count == 1, let event = matches.first else { return false }
        helpSelection = NativeActivityHelpSelection(event: event, revision: revision, provenance: provenance)
        return true
    }
    private func perform(fresh: Bool, action: (any NativeActivityReadSession) throws -> Void) {
        do {
            let session: any NativeActivityReadSession
            if let activeSession { session = activeSession }
            else if let testSession { session = testSession }
            else { session = try NativeActivityAdapter() }
            try action(session)
            try publish(session.snapshot, fresh: fresh)
            activeSession = session
        } catch { invalidate() }
    }
    private func publish(_ loaded: ActivitySnapshot, fresh: Bool) throws {
        guard loaded.available, let revision = loaded.revision,
              Set(loaded.events.map(\.eventID)).count == loaded.events.count,
              !fresh || (revision == 0 && loaded.events.isEmpty) else { throw ActivityRefusal.invalidWire }
        snapshot = loaded
        phase = .loaded
    }
    private func invalidate() {
        activeSession = nil
        snapshot = nil
        phase = .unavailable
        // A prior support handoff remains an immutable observation of its original load.
    }
}
