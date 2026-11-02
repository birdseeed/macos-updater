import Foundation
import Combine
import ArtifactInspection

// PAT-2583: the operator surface's state and visible words. The controller keeps the
// output-only result of each step the operator chose and derives every visible word from
// what it holds. See docs/operator-runbook.md.

/// The three operator steps. Each runs only on its own explicit choice; none starts another.
public enum OperatorStage: String, CaseIterable, Sendable {
    case verify, sign, publish
}

/// One step as the view shows it. Display only: it holds no callback and no path authority.
public struct OperatorStageRow: Equatable, Sendable {
    public let stage: OperatorStage
    public let title: String
    public let status: String
    public let actionTitle: String
    public let actionEnabled: Bool
    public let reason: String?
}

/// The words the view shows. A step reads as done only while the controller holds the
/// output-only result of that step; no caller can supply a status.
public struct OperatorViewText: Equatable, Sendable {
    public let scopeNotice: String
    public let heading: String
    public let artifactLine: String
    public let rows: [OperatorStageRow]
    public let footnote: String

    static let fixedScopeNotice = "Fixture scope. No production key, no production publication and no installation."
    static let fixedHeading = "Catalogue operator"
    static let fixedFootnote = "Each step runs only when you choose it. Nothing is installed or opened."
    static let noArtifact = "No artifact chosen."
    static let notRun = "Not run"
    static let refused = "Refused"
    static let fixtureVerified = "Fixture bytes matched. macOS checks not run"
    static let signed = "Signed with the fixture key. Not published"
    static let published = "Published to the local fixture folder"
    static let fallbackReason = "The step was refused."

    static func artifactLine(_ name: String) -> String { "Artifact: " + name }

    /// What a held receipt supports saying, and no more. A fixture receipt ran no macOS check.
    /// A live receipt keeps the app's results apart from the disk image's own three results.
    static func verifiedStatus(_ receipt: VerifiedArtifactReceipt) -> String {
        guard receipt.origin == .live else { return fixtureVerified }
        let container = [receipt.containerSignaturePassed, receipt.containerGatekeeperPassed, receipt.containerTicketPassed]
        let image = container.allSatisfy { $0 } ? "Disk image checks passed"
            : container.contains(true) ? "Some disk image checks did not pass" : "Disk image checks did not pass"
        return "Bytes matched the approved pin. " + (receipt.appChecksPassed ? "App checks passed. " : "App checks did not pass. ") + image
    }

    /// A brief plain reason for one typed refusal. The code itself is never shown.
    public static func refusalReason(_ failure: OperatorFailure) -> String {
        switch failure {
        case .notImplemented: "This step is not available in this preview."
        case .notAuthorized: "Patched is not authorised to sign or publish here."
        case .invalidState: "That step is not available at this stage."
        case .recordedEvidenceRefused: "A saved report cannot stand in for a fresh check."
        case .unknownTarget: "That version is not one of the approved artifacts."
        case .unsafePath: "That location cannot be used."
        case .notRegularFile: "Something that should be a file is not a file."
        case .hardlink: "A file with more than one name was found."
        case .unsafeOwner: "A file or folder belongs to a different user."
        case .unsafeMode: "A file or folder has permissions Patched does not accept."
        case .resourceLimit: "A file is larger or smaller than this preview accepts."
        case .lengthMismatch: "The artifact is not the expected size."
        case .digestMismatch: "The artifact does not match its approved contents."
        case .identityChanged: "Something changed on disk after it was checked. Verify again."
        case .inspectionRefused: "The macOS checks did not pass for this artifact."
        case .cleanupUnverified: "The inspection could not confirm that it cleaned up."
        case .invalidConfiguration: "The catalogue details are not valid."
        case .invalidClock: "The current time could not be used."
        case .invalidLifetime: "The catalogue's dates are not valid."
        case .futureIssued: "The catalogue's start time is too far ahead."
        case .expired: "The catalogue has already expired."
        case .untrustedKey: "The signing key is not the one configured here."
        case .wrongCatalogue: "The catalogue name is not the one configured here."
        case .signerFailed: "The signer did not return a signature."
        case .invalidSignature: "The signature did not verify, so nothing was accepted."
        case .replay: "A catalogue with this number or a later one already exists."
        case .missingState: "The operator's saved record was not found. Nothing was reset."
        case .corruptState: "The operator's saved record could not be read. Nothing was reset."
        case .existingNamespace: "That operator folder already exists."
        case .existingOutput: "Output for this catalogue already exists and was left as it is."
        case .busy: "Another operator step is in progress."
        case .persistenceFailed: "Patched could not save the result. Check the folder before trying again."
        }
    }

    /// The plain reason for whatever a step threw. Anything untyped gets the one fallback.
    static func refusalReason(for error: Error) -> String {
        (error as? OperatorFailure).map(refusalReason) ?? fallbackReason
    }
}

/// What a caller may wire to the three steps. Every member is absent by default: no input,
/// no signing capability and no output location.
public struct OperatorConfiguration {
    public var artifactName: String?
    public var verify: (() throws -> VerifiedArtifactReceipt)?
    public var sign: ((VerifiedArtifactReceipt) throws -> SignedCatalogue)?
    public var publish: ((SignedCatalogue) throws -> PublishedCatalogue)?
    public init() {}
}

/// Holds the results of the steps chosen so far. Creating it runs nothing, and it owns no
/// timer, network request or scan. A step reads as done only while its own result is held,
/// and a later result is held only when it follows from the earlier one held here. Callbacks
/// are trusted process code; these checks relate results to one another and are not a sandbox.
@MainActor public final class OperatorController: ObservableObject {
    @Published public private(set) var text: OperatorViewText

    private let configuration: OperatorConfiguration
    private var receipt: VerifiedArtifactReceipt?
    private var signed: SignedCatalogue?
    private var published: PublishedCatalogue?
    /// The plain reason for the last refusal of each step, kept only until that step or an earlier one is chosen again.
    private var refusals: [OperatorStage: String] = [:]
    private var running = false

    public init(_ configuration: OperatorConfiguration = OperatorConfiguration()) {
        self.configuration = configuration
        text = Self.words(configuration, receipt: nil, signed: nil, published: nil, refusals: [:])
    }

    /// The operator's explicit choice of one step. It calls that step's own callback once and
    /// nothing else. A disabled step, or a choice made while a step is running, calls nothing.
    public func choose(_ stage: OperatorStage) {
        guard !running, text.rows.first(where: { $0.stage == stage })?.actionEnabled == true else { return }
        running = true
        defer { running = false; refresh() }
        // The chosen step's earlier result and everything after it are dropped before the
        // callback runs, so a refusal leaves no later step standing on a stale result.
        do {
            switch stage {
            case .verify:
                guard let verify = configuration.verify else { return }
                (receipt, signed, published, refusals) = (nil, nil, nil, [:])
                let result = try verify()
                // Only a fixture or live receipt has words here. Nothing in the library returns any other.
                guard result.origin == .fixture || result.origin == .live else { throw OperatorFailure.recordedEvidenceRefused }
                receipt = result
            case .sign:
                guard let sign = configuration.sign, let receipt else { return }
                (signed, published) = (nil, nil)
                refusals[.sign] = nil; refusals[.publish] = nil
                let result = try sign(receipt)
                try Self.requireSigned(result, from: receipt)
                signed = result
            case .publish:
                guard let publish = configuration.publish, let signed else { return }
                published = nil
                refusals[.publish] = nil
                let result = try publish(signed)
                try Self.requirePublished(result, of: signed)
                published = result
            }
        } catch {
            refusals[stage] = OperatorViewText.refusalReason(for: error)
        }
    }

    /// A callback can hand back any result this library ever issued. A signed result is held only
    /// when it was made from the very receipt held here: the same held artifact object, not an
    /// equal record, because two verifications of unchanged bytes encode identically.
    private static func requireSigned(_ result: SignedCatalogue, from receipt: VerifiedArtifactReceipt) throws {
        let same = OperatorIO.sameBytes
        guard result.state.receipt.held === receipt.held, result.receiptOrigin == receipt.origin,
              result.state.receipt.origin == receipt.origin, same(result.inspectionRecordSHA256, receipt.inspectionRecordSHA256),
              same(result.state.receipt.inspectionRecordSHA256, receipt.inspectionRecordSHA256), same(result.origin, "fixture"),
              !result.freshOSValidation, !result.installationAuthorized, !result.published else { throw OperatorFailure.invalidState }
    }

    /// A published result is held only when it reports the signed catalogue held here, in the one
    /// directory of that catalogue's own root. The same payload published from another root is refused.
    private static func requirePublished(_ result: PublishedCatalogue, of signed: SignedCatalogue) throws {
        let same = OperatorIO.sameBytes
        let directory = signed.state.rootPath + "/" + OperatorRoot.publicationsName + "/" + CataloguePublication.publicationPrefix + String(signed.sequence)
        guard same(result.keyID, signed.keyID), same(result.catalogueID, signed.catalogueID), result.sequence == signed.sequence,
              same(result.envelopeSHA256, signed.envelopeSHA256), result.envelopeByteLength == signed.envelope.count,
              same(result.payloadSHA256, signed.payloadSHA256), same(result.inspectionRecordSHA256, signed.inspectionRecordSHA256),
              result.receiptOrigin == signed.receiptOrigin, same(result.origin, "fixture"), !result.freshOSValidation,
              !result.installationAuthorized, !result.productionPublication, same(result.publicationPath, directory),
              same(result.cataloguePath, directory + "/" + CataloguePublication.catalogueName),
              same(result.evidencePath, directory + "/" + CataloguePublication.evidenceName),
              same(result.inspectionRecordPath, directory + "/" + CataloguePublication.inspectionRecordName),
              same(result.publicationRecordPath, directory + "/" + CataloguePublication.publicationRecordName) else {
            throw OperatorFailure.invalidState
        }
    }

    private func refresh() {
        text = Self.words(configuration, receipt: receipt, signed: signed, published: published, refusals: refusals)
    }

    private static func words(_ configuration: OperatorConfiguration, receipt: VerifiedArtifactReceipt?, signed: SignedCatalogue?,
                              published: PublishedCatalogue?, refusals: [OperatorStage: String]) -> OperatorViewText {
        let configured = configuration.artifactName.flatMap { $0.isEmpty ? nil : $0 }
        // Once a receipt is held, the name shown is the file that receipt names, not the caller's label.
        let verifiedName = receipt.map { URL(fileURLWithPath: $0.artifactPath).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 }
        let artifactLine = (verifiedName ?? configured).map(OperatorViewText.artifactLine) ?? OperatorViewText.noArtifact

        func row(_ stage: OperatorStage, _ title: String, _ action: String, done: String?, blocked: String?) -> OperatorStageRow {
            if let blocked {
                return OperatorStageRow(stage: stage, title: title, status: OperatorViewText.notRun, actionTitle: action, actionEnabled: false, reason: blocked)
            }
            if let refusal = refusals[stage] {
                return OperatorStageRow(stage: stage, title: title, status: OperatorViewText.refused, actionTitle: action, actionEnabled: true, reason: refusal)
            }
            return OperatorStageRow(stage: stage, title: title, status: done ?? OperatorViewText.notRun, actionTitle: action, actionEnabled: true, reason: nil)
        }
        return OperatorViewText(
            scopeNotice: OperatorViewText.fixedScopeNotice, heading: OperatorViewText.fixedHeading, artifactLine: artifactLine,
            rows: [row(.verify, "1. Verify artifact", "Verify", done: receipt.map(OperatorViewText.verifiedStatus),
                       blocked: configuration.verify == nil || configured == nil ? "No artifact is configured." : nil),
                   row(.sign, "2. Sign catalogue", "Sign", done: signed == nil ? nil : OperatorViewText.signed,
                       blocked: configuration.sign == nil ? "No signing capability is configured." : receipt == nil ? "Verify the artifact first." : nil),
                   row(.publish, "3. Publish locally", "Publish", done: published == nil ? nil : OperatorViewText.published,
                       blocked: configuration.publish == nil ? "No output location is configured." : signed == nil ? "Sign the catalogue first." : nil)],
            footnote: OperatorViewText.fixedFootnote)
    }
}
