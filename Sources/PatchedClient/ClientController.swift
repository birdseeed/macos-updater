import Foundation
import ArtifactInspection

// PAT-2600: the first read-only client flow. One local disk image, chosen by the person, is
// checked against one compiled Firefox pin by the existing read-only inspector, and only when
// Check is chosen. See docs/client-flow.md for the contract these interfaces must meet.
//
// Nothing here downloads, looks at an installed app, replaces, opens or schedules anything.
// No result of a check grants or enables installation.

/// Where a result came from. Only `.inspector` is produced by linked product code.
public enum ClientResultProvenance: Sendable, Equatable { case inspector, testDouble }

/// What one inspection reported, reduced to what the client shows. The path is not carried.
/// The initialiser is test-only; product code receives a summary only from the production
/// inspector. A summary cannot grant installation: one that claims to is refused.
public struct ClientInspectionSummary: Sendable, Equatable {
    let version: String
    let provenance: ClientResultProvenance
    let byteIntegrityVerified: Bool
    let appChecksPassed: Bool?
    let containerSignaturePassed: Bool
    let containerGatekeeperPassed: Bool
    let containerTicketPassed: Bool
    let origin: EvidenceOrigin?
    let freshOSValidation: Bool
    let cleanupVerified: Bool
    let refusal: String?
    let installationAuthorized: Bool

    @_spi(Testing) public init(version: String, provenance: ClientResultProvenance, byteIntegrityVerified: Bool, appChecksPassed: Bool?,
                               containerSignaturePassed: Bool, containerGatekeeperPassed: Bool, containerTicketPassed: Bool,
                               origin: EvidenceOrigin?, freshOSValidation: Bool, cleanupVerified: Bool, refusal: String?,
                               installationAuthorized: Bool) {
        self.version = version; self.provenance = provenance; self.byteIntegrityVerified = byteIntegrityVerified
        self.appChecksPassed = appChecksPassed; self.containerSignaturePassed = containerSignaturePassed
        self.containerGatekeeperPassed = containerGatekeeperPassed; self.containerTicketPassed = containerTicketPassed
        self.origin = origin; self.freshOSValidation = freshOSValidation; self.cleanupVerified = cleanupVerified
        self.refusal = refusal; self.installationAuthorized = installationAuthorized
    }

    /// The inspector's own report for one requested local check. A report that is not exactly
    /// that check (another pin, mode or source, a network transport, a kept workspace) is
    /// carried as a refusal instead of being read as a result.
    init(report: InspectionReport, version: String, path: String) {
        let assessment = report.assessment
        let expected = report.mode == "inspect-local" && report.sourcePath == path && !report.transportObservedThisRun
            && (try? FirefoxTargets.select(version: version)) == report.pin
        self.version = report.pin.version; provenance = .inspector
        byteIntegrityVerified = report.byteIntegrityVerified
        appChecksPassed = assessment?.appChecksPassed
        containerSignaturePassed = assessment?.containerSignaturePassed ?? false
        containerGatekeeperPassed = assessment?.containerGatekeeperPassed ?? false
        containerTicketPassed = assessment?.containerTicketPassed ?? false
        origin = assessment?.origin; freshOSValidation = assessment?.freshOSValidation ?? false
        cleanupVerified = report.cleanupVerified && report.workspacePreserved == nil
        refusal = expected ? report.refusal : (report.refusal ?? ClientOutcome.unexpectedReport)
        installationAuthorized = report.installationAuthorized || assessment?.installationAuthorized == true
    }
}

/// One inspection of one local file for one pinned version. Called off the main actor.
public typealias ClientInspector = @Sendable (_ version: String, _ path: String) async throws -> ClientInspectionSummary

public enum ClientPhase: Sendable, Equatable { case needsSelection, ready, checking, passed, notPassed, refused }
public enum ClientResultKind: Sendable, Equatable { case bytes, app, container, cleanup }
public enum ClientResultState: Sendable, Equatable { case notRun, passed, failed }

/// One of the four separate results. The disk image's own result never stands in for the app's.
public struct ClientResultLine: Sendable, Equatable {
    public let kind: ClientResultKind
    public let state: ClientResultState
    public let title: String
    public let status: String
    public let detail: String
}

/// The words the view shows. Display only: it holds the file's name, never its path, no
/// inspector text and no callback, and nothing in it offers more than a check.
public struct ClientViewText: Sendable, Equatable {
    public let notice: String
    public let heading: String
    public let fileLine: String
    public let versionLine: String
    public let chooseTitle: String
    public let statusLine: String
    public let resultLines: [ClientResultLine]
    public let reason: String?
    public let provenanceLine: String?
    public let checkTitle: String
    public let checkEnabled: Bool
    public let cancelTitle: String
    public let cancelEnabled: Bool
    public let footnote: String

    /// Every string the view can paint for this state.
    public var allLines: [String] {
        [notice, heading, fileLine, versionLine, chooseTitle, statusLine]
            + resultLines.flatMap { [$0.title, $0.status, $0.detail] }
            + [reason, provenanceLine].compactMap { $0 } + [checkTitle, cancelTitle, footnote]
    }
}

/// How one finished inspection reads. Anything contradictory fails closed as a refusal.
struct ClientOutcome: Equatable {
    static let unexpectedReport = "unexpectedReport"

    let phase: ClientPhase
    let bytes: ClientResultState
    let app: ClientResultState
    let container: ClientResultState
    let containerDetail: String
    let cleanup: ClientResultState
    let reason: String?
    let provenance: ClientResultProvenance?

    /// The inspector threw instead of reporting. The error itself is never shown.
    static let failed = ClientOutcome(phase: .refused, bytes: .notRun, app: .notRun, container: .notRun, containerDetail: "",
                                      cleanup: .notRun, reason: "The check could not be completed. Nothing was changed.", provenance: nil)

    init(phase: ClientPhase, bytes: ClientResultState, app: ClientResultState, container: ClientResultState, containerDetail: String,
         cleanup: ClientResultState, reason: String?, provenance: ClientResultProvenance?) {
        self.phase = phase; self.bytes = bytes; self.app = app; self.container = container
        self.containerDetail = containerDetail; self.cleanup = cleanup; self.reason = reason; self.provenance = provenance
    }

    init(_ summary: ClientInspectionSummary, requestedVersion: String) {
        let cleanup: ClientResultState = summary.cleanupVerified ? .passed : .failed
        func refused(_ reason: String, bytes: ClientResultState = .notRun) -> ClientOutcome {
            ClientOutcome(phase: .refused, bytes: bytes, app: .notRun, container: .notRun, containerDetail: "", cleanup: cleanup,
                          reason: summary.cleanupVerified ? reason : reason + " " + Self.cleanupReason, provenance: summary.provenance)
        }
        let contradictory = "The check returned a result Patched does not accept, so it is not shown."
        guard !summary.installationAuthorized else { self = refused(contradictory); return }
        guard summary.version == requestedVersion else { self = refused(contradictory); return }
        if let code = summary.refusal {
            let mismatch = [InspectionFailure.lengthMismatch.rawValue, InspectionFailure.digestMismatch.rawValue].contains(code)
            let bytes: ClientResultState = mismatch ? .failed : (summary.byteIntegrityVerified ? .passed : .notRun)
            self = refused(Self.refusalReason(code), bytes: bytes); return
        }
        // Without a refusal, only the inspector's own live assessment on this Mac of verified bytes is a result.
        guard summary.byteIntegrityVerified, let appPassed = summary.appChecksPassed, summary.origin == .live,
              summary.freshOSValidation else { self = refused(contradictory); return }
        let checks = [("Signature", summary.containerSignaturePassed), ("Gatekeeper", summary.containerGatekeeperPassed),
                      ("Notarisation ticket", summary.containerTicketPassed)]
        let detail = checks.map { "\($0.0): \($0.1 ? "passed" : "did not pass")." }.joined(separator: " ")
        let reason: String? = !appPassed ? "The app inside this disk image did not pass its checks."
            : (summary.cleanupVerified ? nil : Self.cleanupReason)
        self.init(phase: appPassed && summary.cleanupVerified ? .passed : .notPassed, bytes: .passed, app: appPassed ? .passed : .failed,
                  container: checks.allSatisfy(\.1) ? .passed : .failed, containerDetail: detail, cleanup: cleanup,
                  reason: !appPassed && !summary.cleanupVerified ? reason! + " " + Self.cleanupReason : reason,
                  provenance: summary.provenance)
    }

    static let cleanupReason = "Patched could not confirm its temporary copy was removed."

    /// A brief plain reason for one inspector refusal. The inspector's own text is never shown.
    static func refusalReason(_ code: String) -> String {
        guard let failure = InspectionFailure(rawValue: code) else { return "The check was refused." }
        switch failure {
        case .unsafePath: return "That file could not be read safely. It may be missing or reached through a link."
        case .notRegularFile: return "That is not an ordinary file."
        case .lengthMismatch: return "This file is not the size of the expected Firefox disk image."
        case .digestMismatch: return "This file's contents do not match the expected Firefox disk image."
        case .wrongBundle: return "The disk image holds a different app."
        case .wrongVersion: return "The disk image holds a different version of Firefox."
        case .wrongArchitecture: return "The app is not built for the expected kinds of Mac."
        case .wrongTeam: return "The app is not signed by the expected developer."
        case .signatureRejected: return "macOS did not accept the app's signature."
        case .notarizationRejected: return "macOS did not accept the app as notarised by Apple."
        case .ticketRejected: return "The app's notarisation record was not accepted."
        case .invalidMount: return "The disk image could not be opened read-only."
        case .invalidMetadata, .missingEvidence, .invalidRecord: return "The disk image's details could not be read."
        case .commandFailed, .outputLimit: return "A macOS check could not be completed."
        case .commandTimedOut: return "A macOS check took too long and was stopped."
        case .cleanupFailed: return "The check ended before a result could be confirmed."
        case .unknownTarget: return "That version of Firefox is not one Patched can check."
        case .notImplemented, .unsafeURL, .redirectLimit, .downloadLimit: return "The check was refused."
        }
    }
}

/// Everything the controller holds. The words and the phase are derived from it and nothing else.
struct ClientModel: Equatable {
    var fileURL: URL?
    var fileRefusal: String?
    var version: String?
    var versionRefusal: String?
    var outcome: ClientOutcome?
    /// Advanced by every selection change and cancel; a result from an earlier value is discarded.
    var generation: UInt64 = 0
    /// The single-run lease: held from Check until the inspector itself returns.
    var running = false
    /// The generation the running inspection was started for.
    var runningGeneration: UInt64?

    var awaited: Bool { running && runningGeneration == generation }
    var canCheck: Bool { fileURL != nil && version != nil && !running }

    var phase: ClientPhase {
        if fileRefusal != nil || versionRefusal != nil { return .refused }
        guard fileURL != nil, version != nil else { return .needsSelection }
        if awaited { return .checking }
        return outcome?.phase ?? .ready
    }

    /// The file's own name with control characters removed and a bounded length. Never the path.
    private var fileName: String? {
        guard let name = fileURL?.lastPathComponent else { return nil }
        let printable = String(String.UnicodeScalarView(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
        return printable.count > 80 ? String(printable.prefix(80)) + "…" : printable
    }

    var text: ClientViewText {
        let phase = phase, shown = awaited ? nil : outcome
        let status: String
        switch phase {
        case .needsSelection: status = "Choose a disk image and the version it should be."
        case .ready: status = running ? "An earlier check is still finishing. You can check again when it ends."
                                      : "Not checked yet. Choose Check to start."
        case .checking: status = "Checking. This can take a minute or two."
        case .passed: status = "The app inside this disk image passed its checks."
        case .notPassed: status = "This disk image did not pass."
        case .refused: status = shown == nil ? "That choice cannot be checked." : "The check was refused."
        }
        func line(_ kind: ClientResultKind, _ title: String, _ state: ClientResultState?, _ detail: String = "") -> ClientResultLine {
            let state = state ?? .notRun
            return ClientResultLine(kind: kind, state: state, title: title,
                                    status: state == .notRun ? "Not run" : (state == .passed ? "Passed" : "Did not pass"), detail: detail)
        }
        let provenance: String? = shown?.provenance.map {
            if $0 == .testDouble { return "Test double result. Not an inspection of a real file." }
            return shown?.phase == .refused ? "Refused during a read-only check on this Mac." : "Checked now on this Mac by the read-only check."
        }
        return ClientViewText(
            notice: "Preview. Patched checks one disk image you choose. It does not download, install or open anything.",
            heading: "Check a Firefox disk image",
            fileLine: "Disk image: " + (fileName ?? "none chosen"),
            versionLine: "Expected version: " + (version.map { "Firefox " + $0 } ?? "none chosen"),
            chooseTitle: "Choose disk image…",
            statusLine: status,
            resultLines: [line(.bytes, "File matches the expected download", shown?.bytes),
                          line(.app, "App inside the disk image", shown?.app),
                          line(.container, "Disk image itself", shown?.container, shown?.containerDetail ?? ""),
                          line(.cleanup, "Temporary copy removed", shown?.cleanup)],
            reason: fileRefusal ?? versionRefusal ?? shown?.reason,
            provenanceLine: provenance,
            checkTitle: "Check this disk image", checkEnabled: canCheck,
            cancelTitle: awaited ? "Cancel" : "Clear result", cancelEnabled: awaited || outcome != nil,
            footnote: "This is a read-only check. Nothing is installed, replaced or opened, and a passed check does not approve an installation.")
    }
}

/// Holds one selection and at most one running inspection. Selecting never inspects; only
/// `check()` does, once, and a result is shown only if nothing was changed or cancelled since.
@MainActor
public final class ClientController: ObservableObject {
    @Published private var model = ClientModel()
    private let inspect: ClientInspector
    private var run: Task<Void, Never>?

    /// The versions that can be chosen: exactly the compiled pins.
    public let versions: [String] = FirefoxTargets.pins.map(\.version)
    public var phase: ClientPhase { model.phase }
    public var text: ClientViewText { model.text }
    /// The chosen version, for the view to mark. Nil until a compiled pin is chosen.
    public var selectedVersion: String? { model.version }

    /// The product controller: the existing read-only inspector and nothing else.
    public init() { inspect = Self.production }
    @_spi(Testing) public init(inspector: @escaping ClientInspector) { inspect = inspector }

    /// The only call of the inspector. It blocks until the inspector returns, on a queue of its
    /// own choosing, never on the main actor.
    private static let production: ClientInspector = { version, path in
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result {
                    ClientInspectionSummary(report: try ArtifactInspector.inspectLocal(version: version, path: path), version: version, path: path)
                })
            }
        }
    }

    /// One local file whose name ends in .dmg. Anything else clears the selection. Nothing is read.
    public func select(fileURL: URL) {
        model.generation &+= 1; model.outcome = nil
        if fileURL.isFileURL, fileURL.pathExtension.lowercased() == "dmg" {
            model.fileURL = fileURL; model.fileRefusal = nil
        } else {
            model.fileURL = nil; model.fileRefusal = "Choose a disk image file from this Mac. Its name ends in .dmg."
        }
    }

    /// One of the compiled pins, exactly as written. Anything else clears the version.
    public func selectVersion(_ version: String) {
        model.generation &+= 1; model.outcome = nil
        if versions.contains(version) {
            model.version = version; model.versionRefusal = nil
        } else {
            model.version = nil; model.versionRefusal = "That version of Firefox is not one Patched can check."
        }
    }

    /// Starts one inspection of the current selection. Does nothing without a complete selection
    /// or while an earlier inspection, cancelled or not, has yet to return.
    public func check() {
        guard model.canCheck, let path = model.fileURL?.path, let version = model.version else { return }
        let generation = model.generation, inspect = inspect
        model.outcome = nil; model.running = true; model.runningGeneration = generation
        run = Task { [self] in
            let summary = await Task.detached { try? await inspect(version, path) }.value
            model.running = false; model.runningGeneration = nil; run = nil
            // A result for a selection that has since changed, or a cancelled check, is dropped.
            guard model.generation == generation else { return }
            model.outcome = summary.map { ClientOutcome($0, requestedVersion: version) } ?? .failed
        }
    }

    /// Discards the shown or awaited result and keeps the selection. A running inspection is
    /// not interrupted; its result is dropped and Check stays unavailable until it returns.
    public func cancel() {
        guard model.running || model.outcome != nil else { return }
        model.generation &+= 1; model.outcome = nil
    }

    @_spi(Testing) public func waitUntilIdle() async {
        while let run { await run.value }
    }
}
