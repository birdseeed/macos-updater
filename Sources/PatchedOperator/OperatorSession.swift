import Foundation
import Combine
import ArtifactInspection

// The read-only operator session: one chosen local disk image, one compiled pin and one
// explicit Verify. It downloads nothing, opens no app, installs nothing and holds no
// credential. Signing and publication are words only here: the session has no route to
// either. See docs/operator-session.md.

/// What the session shows of one verification. Display only: it carries no artifact, no
/// record and no authority, and nothing in the library accepts it in place of a receipt.
public struct OperatorSessionSummary: Equatable, Sendable {
    public let provenance: EvidenceOrigin
    public let appChecksPassed: Bool
    public let containerSignaturePassed: Bool
    public let containerGatekeeperPassed: Bool
    public let containerTicketPassed: Bool
    public let cleanupVerified: Bool
    /// Set for every summary built outside the library, whatever provenance it names.
    let testDouble: Bool
    let freshOSValidation: Bool

    /// A summary for the checks to display. It is always labelled a test double.
    @_spi(Testing)
    public init(provenance: EvidenceOrigin, appChecksPassed: Bool, containerSignaturePassed: Bool, containerGatekeeperPassed: Bool,
                containerTicketPassed: Bool, cleanupVerified: Bool) {
        self.provenance = provenance; self.appChecksPassed = appChecksPassed
        self.containerSignaturePassed = containerSignaturePassed; self.containerGatekeeperPassed = containerGatekeeperPassed
        self.containerTicketPassed = containerTicketPassed; self.cleanupVerified = cleanupVerified
        testDouble = true; freshOSValidation = false
    }

    /// The summary of an actual receipt, taken from its own fields and nothing else.
    init(_ receipt: VerifiedArtifactReceipt) {
        provenance = receipt.origin; appChecksPassed = receipt.appChecksPassed
        containerSignaturePassed = receipt.containerSignaturePassed; containerGatekeeperPassed = receipt.containerGatekeeperPassed
        containerTicketPassed = receipt.containerTicketPassed; cleanupVerified = receipt.cleanupVerified
        testDouble = false; freshOSValidation = receipt.freshOSValidation
    }
}

public enum OperatorSessionPhase: Equatable, Sendable {
    case idle, ready, verifying, cancelling, verified, refused
}

/// The words the session view shows. Every line is derived from what the session holds.
public struct OperatorSessionText: Equatable, Sendable {
    public let fileLine: String
    public let versionLine: String
    public let status: String
    public let provenanceLine: String?
    public let appLine: String?
    public let containerLines: [String]
    /// Set only by a verified cleanup or a typed cleanup failure; nil whenever neither happened.
    public let cleanupLine: String?
    public let verifyEnabled: Bool
    public let cancelEnabled: Bool
    public let signingEnabled: Bool
    public let signingReason: String
    public let publicationEnabled: Bool
    public let publicationReason: String
    public let footnote: String

    static let noFile = "No disk image chosen."
    static let unsupportedFile = "That item is not a local disk image file."
    static let noVersion = "No approved version chosen."
    static let signingUnavailable = "Signing is unavailable: this app has no signing capability."
    static let publicationUnavailable = "Publication is unavailable: this app has no publication destination."
    static let fixedFootnote = "Read-only. Nothing is downloaded, opened or installed, and a passed check gives no permission to install."
    static let maximumNameLength = 80

    /// The last path component only, without control or formatting characters and bounded in length.
    static func displayName(_ url: URL) -> String {
        let kept = url.lastPathComponent.unicodeScalars.filter {
            ![.control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .privateUse, .unassigned].contains($0.properties.generalCategory)
        }
        let name = String(String(String.UnicodeScalarView(kept)).prefix(maximumNameLength))
        return name.isEmpty ? "unnamed" : name
    }

    static func provenance(_ summary: OperatorSessionSummary) -> String {
        if summary.testDouble {
            switch summary.provenance {
            case .live: return "Test double labelled live. Display only: not a real live check."
            case .fixture: return "Test double labelled fixture. Display only: no macOS check was run."
            case .replayed: return "Test double labelled replayed. Display only: a saved record, not a check run now."
            }
        }
        switch summary.provenance {
        case .live: return summary.freshOSValidation ? "Live check run by this app just now, with fresh macOS checks."
            : "Live check run by this app just now."
        case .fixture: return "Fixture bytes only. No macOS check was run."
        case .replayed: return "Replayed from a saved record. Not a check run now."
        }
    }
    static let cleanupConfirmed = "Cleanup confirmed: the temporary mount was removed."
    static let cleanupNotConfirmed = "Cleanup not confirmed. The temporary mount may still be present."
    static func result(_ name: String, _ passed: Bool) -> String { name + (passed ? " passed." : " did not pass.") }
}

/// Holds the operator's selection and the one result of the latest explicit Verify. Creating
/// it runs nothing. Any change of file or version, a cancel, a new Verify or a refusal drops
/// what was held at once, and a result that arrives for an earlier selection is discarded.
@MainActor public final class OperatorSession: ObservableObject {
    /// One finished verification as the worker hands it back. The receipt is the library's
    /// own output and is present only for the real verifier.
    private enum Outcome: Sendable {
        case verified(VerifiedArtifactReceipt?, OperatorSessionSummary)
        case refused(String, cleanupFailed: Bool)
    }
    private typealias Verifier = @Sendable (_ version: String, _ path: String) -> Outcome

    @Published public private(set) var phase: OperatorSessionPhase = .idle
    @Published public private(set) var text: OperatorSessionText
    @Published public private(set) var selectedVersion: String?
    /// The compiled pins, in their compiled order. Nothing else can be chosen.
    public let versions: [String] = FirefoxTargets.pins.map(\.version)
    public var holdsResult: Bool { summary != nil }

    private let verifier: Verifier
    private var file: URL?
    private var unsupportedFile = false
    /// The actual output-only receipt of the latest real verification. It never leaves the session.
    private var receipt: VerifiedArtifactReceipt?
    private var summary: OperatorSessionSummary?
    private var refusal: String?
    /// Set only when the refusal was the typed cleanup failure, never inferred from its words.
    private var cleanupFailed = false
    /// Bumped by every selection, cancel and Verify, so a late result can be told from a current one.
    private var generation = 0
    /// Held from Verify until the synchronous worker has really returned, whatever happened meanwhile.
    private var workerGeneration: Int?
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    /// The product session: Verify runs the library's real pinned-artifact verification.
    public init() {
        verifier = { version, path in
            Self.outcome {
                let receipt = try OperatorVerification.verifyPinnedArtifact(version: version, path: path)
                guard receipt.version == version, receipt.artifactPath == path, receipt.byteIntegrityVerified,
                      !receipt.installationAuthorized else { throw OperatorFailure.invalidState }
                return (receipt, OperatorSessionSummary(receipt))
            }
        }
        text = Self.words(phase: .idle, file: nil, unsupportedFile: false, version: nil, summary: nil, refusal: nil, cleanupFailed: false)
    }

    /// For the checks only: Verify shows the supplied display summary, labelled a test double.
    /// No receipt is made or held, and nothing can be done with the summary but display it.
    @_spi(Testing)
    public init(displaySummaryVerifier: @escaping @Sendable (_ version: String, _ path: String) throws -> OperatorSessionSummary) {
        verifier = { version, path in Self.outcome { (nil, try displaySummaryVerifier(version, path)) } }
        text = Self.words(phase: .idle, file: nil, unsupportedFile: false, version: nil, summary: nil, refusal: nil, cleanupFailed: false)
    }

    /// The operator's choice of one local disk image file. It runs nothing.
    public func select(fileURL: URL) {
        let supported = fileURL.isFileURL && fileURL.pathExtension.lowercased() == "dmg" && fileURL.path.hasPrefix("/")
        file = supported ? fileURL : nil
        unsupportedFile = !supported
        invalidate()
    }

    /// The operator's choice of one compiled pin by its exact version. It runs nothing.
    public func selectVersion(_ version: String) {
        selectedVersion = versions.contains(version) ? version : nil
        invalidate()
    }

    /// Drops any result and disowns a verification in progress. The worker cannot be
    /// interrupted, so Verify stays unavailable until it has returned.
    public func cancel() { invalidate() }

    /// The operator's explicit Verify. It starts one worker away from the main actor and
    /// does nothing without a supported file and version or while a worker is still running.
    public func verify() {
        guard workerGeneration == nil, let file, let version = selectedVersion else { return }
        invalidate()
        let run = generation, path = file.path, verifier = verifier
        workerGeneration = run
        refresh()
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = verifier(version, path)
            Task { @MainActor in self.finish(run, outcome) }
        }
    }

    /// Returns once no worker is running.
    @_spi(Testing)
    public func waitUntilIdle() async {
        guard workerGeneration != nil else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    private func finish(_ run: Int, _ outcome: Outcome) {
        workerGeneration = nil
        // Only the result of the current selection is shown; anything later than its own run is stale.
        if run == generation {
            switch outcome {
            case .verified(let receipt, let summary): self.receipt = receipt; self.summary = summary
            case .refused(let reason, let failed): refusal = reason; cleanupFailed = failed
            }
        }
        refresh()
        let waiters = idleWaiters
        idleWaiters = []
        waiters.forEach { $0.resume() }
    }

    private func invalidate() {
        generation += 1
        receipt = nil; summary = nil; refusal = nil; cleanupFailed = false
        refresh()
    }

    private func refresh() {
        let selected = file != nil && selectedVersion != nil
        if let workerGeneration { phase = workerGeneration == generation ? .verifying : .cancelling }
        else if summary != nil { phase = .verified }
        else if refusal != nil { phase = .refused }
        else { phase = selected ? .ready : .idle }
        text = Self.words(phase: phase, file: file, unsupportedFile: unsupportedFile, version: selectedVersion, summary: summary, refusal: refusal, cleanupFailed: cleanupFailed)
    }

    /// Runs one verification and reduces whatever it threw to a plain reason. A result whose
    /// cleanup was not confirmed is a refusal, never a success.
    private nonisolated static func outcome(_ body: () throws -> (VerifiedArtifactReceipt?, OperatorSessionSummary)) -> Outcome {
        do {
            let (receipt, summary) = try body()
            guard summary.cleanupVerified else { throw OperatorFailure.cleanupUnverified }
            return .verified(receipt, summary)
        } catch {
            return .refused(OperatorViewText.refusalReason(for: error), cleanupFailed: (error as? OperatorFailure) == .cleanupUnverified)
        }
    }

    private static func words(phase: OperatorSessionPhase, file: URL?, unsupportedFile: Bool, version: String?,
                              summary: OperatorSessionSummary?, refusal: String?, cleanupFailed: Bool) -> OperatorSessionText {
        let status: String
        switch phase {
        case .idle: status = "Choose a disk image and an approved version."
        case .ready: status = "Ready to verify. Nothing has been checked yet."
        case .verifying: status = "Verifying. This can take a few minutes."
        case .cancelling: status = "The earlier check is still running. Its result will be discarded when it ends."
        case .verified: status = summary?.testDouble == false ? "Bytes matched the approved version." : "Test double result. No file was checked."
        case .refused: status = "Refused. " + (refusal ?? OperatorViewText.fallbackReason)
        }
        return OperatorSessionText(
            fileLine: file.map { "Disk image: " + OperatorSessionText.displayName($0) }
                ?? (unsupportedFile ? OperatorSessionText.unsupportedFile : OperatorSessionText.noFile),
            versionLine: version.map { "Version: Firefox " + $0 } ?? OperatorSessionText.noVersion,
            status: status,
            provenanceLine: summary.map(OperatorSessionText.provenance),
            appLine: summary.map { OperatorSessionText.result("App checks", $0.appChecksPassed) },
            containerLines: summary.map {
                [OperatorSessionText.result("Disk image signature", $0.containerSignaturePassed),
                 OperatorSessionText.result("Disk image Gatekeeper check", $0.containerGatekeeperPassed),
                 OperatorSessionText.result("Disk image stapled ticket", $0.containerTicketPassed)]
            } ?? [],
            cleanupLine: summary.map { $0.cleanupVerified ? OperatorSessionText.cleanupConfirmed : OperatorSessionText.cleanupNotConfirmed }
                ?? (cleanupFailed ? OperatorSessionText.cleanupNotConfirmed : nil),
            verifyEnabled: phase == .ready || phase == .verified || phase == .refused,
            cancelEnabled: phase == .verifying || phase == .verified || phase == .refused,
            signingEnabled: false, signingReason: OperatorSessionText.signingUnavailable,
            publicationEnabled: false, publicationReason: OperatorSessionText.publicationUnavailable,
            footnote: OperatorSessionText.fixedFootnote)
    }
}
