import Foundation
import PatchedCore

enum TestCatalogue {
    // Public TEST key only. No private signing material or production trust in this target.
    static let trust = FixtureTrust(keyID: "patched-disposable-test-v1", catalogueID: "patched-disposable-firefox",
                                   publicKey: Data(base64Encoded: "0EqyMnQrtKs6E2i9RhXk5tAiSrcaAWuvhSCjMsl3hzc=")!)
    static func accept(root: HeldDirectory, envelope: Data, now: Double, os: String, installed: String, bootstrap: Bool) throws -> CatalogueCandidate {
        try root.confirm()
        // Extra refusal before durable Core acceptance. This parse grants nothing; actual
        // signature/domain/schema/time/replay verification remains the unchanged Core verifier.
        let outer = try StrictObject.decode(envelope, maximum: 131_072, failure: .invalidSignature)
        guard let encoded = outer["payload"] as? String, let payload = Data(base64Encoded: encoded),
              encoded == payload.base64EncodedString() else { throw DisposableFailure.invalidSignature }
        let object = try StrictObject.decode(payload, failure: .invalidSignature)
        guard let artifact = object["artifact"] as? [String: Any], let length = unsigned(artifact["byteLength"]),
              let hash = artifact["sha256"] as? String, let version = artifact["version"] as? String,
              let pin = try? fixedPin(version), version == "157.0.1", length == pin.byteLength, hash == pin.sha256,
              artifact["bundleID"] as? String == pin.bundleID, artifact["teamID"] as? String == pin.teamID,
              artifact["platform"] as? String == "macOS" else { throw DisposableFailure.unapprovedArtifact }
        let verifier = CatalogueVerifier(trust: trust,
            policy: .init(bundleID: pin.bundleID, teamID: pin.teamID, osVersion: os, installedVersion: installed),
            stateDirectory: root.path + "/Catalogue")
        do {
            let candidate = try bootstrap ? verifier.bootstrapFreshProofNamespace(envelope: envelope, now: now) : verifier.verify(envelope: envelope, now: now)
            try root.confirm()
            guard candidate.artifact.sha256 == pin.sha256, candidate.artifact.byteLength == pin.byteLength else { throw DisposableFailure.unapprovedArtifact }
            return candidate
        } catch let failure as CoreFailure {
            switch failure {
            case .invalidSignature: throw DisposableFailure.invalidSignature
            case .untrustedKey: throw DisposableFailure.untrustedKey
            case .replay: throw DisposableFailure.replay
            case .expired: throw DisposableFailure.expired
            case .stateBusy: throw DisposableFailure.busy
            case .persistenceFailed: throw DisposableFailure.persistenceFailed
            default: throw DisposableFailure.notAuthorized
            }
        }
    }
}
