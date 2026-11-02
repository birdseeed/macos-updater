import Foundation
import ArtifactInspection

/// Byte consistency output only. Signature of a catalogue never establishes fresh OS trust.
public struct ArtifactConsistency: Encodable, Sendable {
    public let sha256: String
    public let byteLength: Int64
    public let origin: String
    public let freshOSValidation: Bool
    public let installationAuthorized: Bool
}

public enum ArtifactVerifier {
    /// Descriptor-based, bounded read-only byte verification. Refuses symlinks in all components.
    public static func verify(path: String, candidate: CatalogueCandidate) throws -> ArtifactConsistency {
        do {
            try ArtifactBytes.verify(path: path, expectedSHA256: candidate.artifact.sha256,
                                     expectedLength: candidate.artifact.byteLength)
        } catch let error as InspectionFailure {
            switch error {
            case .notRegularFile: throw CoreFailure.notRegularFile
            case .lengthMismatch: throw CoreFailure.lengthMismatch
            case .digestMismatch: throw CoreFailure.digestMismatch
            default: throw CoreFailure.unsafePath
            }
        }
        return ArtifactConsistency(sha256: candidate.artifact.sha256, byteLength: candidate.artifact.byteLength,
            origin: "fixture", freshOSValidation: false, installationAuthorized: false)
    }

    /// Select the existing read-only inspector's compiled pin only on an exact identity/digest/length match.
    /// The returned pin is input to inspection, never an OS assessment or installation authorisation.
    public static func approvedInspectionTarget(candidate: CatalogueCandidate) throws -> TargetPin {
        let artifact = candidate.artifact
        guard artifact.platform == "macOS", let pin = FirefoxTargets.pins.first(where: {
            $0.version == artifact.version && $0.bundleID == artifact.bundleID && $0.teamID == artifact.teamID &&
            $0.sha256 == artifact.sha256 && $0.byteLength == artifact.byteLength
        }) else { throw CoreFailure.unapprovedArtifact }
        return pin
    }
}
