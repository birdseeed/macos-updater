import Foundation
import CryptoKit
@_spi(Testing) import PatchedActivation

// Frozen Phase A acceptance cases. All new proof bytes come from public synthetic fixtures.
struct DiagnosticInput {
    var attempt: ModelAttempt
    var action: Data
    var context: PossessionContext
    var signature: Data
    let challengeID = fixtureID(500)
    init() throws {
        let bytes = try Data(contentsOf: URL(fileURLWithPath: "Fixtures/Activation/vectors/operation-1.json"))
        let v = try JSONDecoder().decode(ProofVector.self, from: bytes)
        action = Data(base64Encoded: v.actionBase64)!
        signature = Data(base64Encoded: v.signatureBase64)!
        context = PossessionContext(accountID: v.accountID, activationID: v.activationID, operation: .activate,
            publicKey: Data(base64Encoded: v.publicKeyBase64)!, nonce: Data(base64Encoded: v.nonceBase64)!, expiresAt: v.expiresAt)
        attempt = ModelAttempt(sessionID: fixtureID(10), operation: .activate,
            body: bodyBytes(action: action, nonce: context.nonce, signature: signature), now: fixtureNow,
            expectedAccountRevision: 1, newActivationID: fixtureID(1_501),
            grantingWindow: ModelGrant(issuedAt: 999, permittedUntil: 1_200, hardEnd: 1_400))
    }
    @MainActor func capture() throws {
        try FixtureDiagnostics.capture(attempt: attempt, action: action, context: context,
                                       signature: signature, challengeID: challengeID)
    }
}
@MainActor func decodedDiagnostic() throws -> PreparedFixtureDiagnostic {
    guard let text = try FixtureDiagnostics.render() else { throw CheckFailure(description: "Missing positive diagnostic capture") }
    try expect(text.utf8.count <= FixtureDiagnostics.maximumOutputBytes, "Diagnostic exceeds fixed output bound")
    return try JSONDecoder().decode(PreparedFixtureDiagnostic.self, from: Data(text.utf8))
}
@MainActor func registerDiagnosticChecks() {
    check("diagnostic exact prepared public bytes and independent stages") {
        let f = try DiagnosticInput(); try f.capture(); let d = try decodedDiagnostic()
        try expect(d.schema == 1 && d.scope == "last-prepared-fixture", "Mislabelled diagnostic scope")
        try expect(!d.os.isEmpty && !d.architecture.isEmpty, "Missing cheap platform metadata")
        try expect(d.body == f.attempt.body && d.action == f.action && d.signature == f.signature, "Public bytes changed")
        try expect(d.publicKey == f.context.publicKey && d.nonce == f.context.nonce, "Key or nonce changed")
        try expect(d.accountID == Data(f.context.accountID.utf8) && d.activationID == nil, "Context identity changed")
        try expect(d.expiresAt == f.context.expiresAt && d.operation == 1 && d.challengeID == Data(f.challengeID.utf8), "Context/challenge changed")
        try expect(d.referenceMessage == referenceMessage(f.action, f.context), "Independent message changed")
        try expect(d.sessionID == Data(f.attempt.sessionID.utf8) && d.now == fixtureNow && d.expectedAccountRevision == 1,
                   "Attempt metadata changed")
        try expect(d.pathActivationID == nil && d.newActivationID == Data(f.attempt.newActivationID!.utf8)
                   && d.grant == [999, 1_200, 1_400] && d.auditSucceeds, "Incomplete prepared attempt")
        try expect(d.parse == "accepted" && d.productionMessage == "matches-reference"
                   && d.independentSignature == "accepted" && d.productionProof == "accepted", "Independent phases absent")
        try expect(d.apply == "not-observed" && d.currentState == "not-captured" && d.modelReplay == "not-performed",
                   "Invented failed apply guard or current ledger evidence")
    }
    check("diagnostic exact captured signature independently replays") {
        let f = try DiagnosticInput(); try f.capture(); let d = try decodedDiagnostic()
        let key = try P256.Signing.PublicKey(x963Representation: d.publicKey)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: d.signature!)
        try expect(key.isValidSignature(signature, for: d.referenceMessage), "Captured signature cannot replay")
    }
    check("diagnostic tampered fixed signature is retained and replay refuses") {
        var f = try DiagnosticInput(); f.signature[0] ^= 1
        f.attempt.body = bodyBytes(action: f.action, nonce: f.context.nonce, signature: f.signature)
        try f.capture(); let d = try decodedDiagnostic()
        try expect(d.signature == f.signature && d.independentSignature == "refused" && d.productionProof == "refused",
                   "Rejected signature hidden or substituted")
        let key = try P256.Signing.PublicKey(x963Representation: d.publicKey)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: d.signature!)
        try expect(!key.isValidSignature(signature, for: d.referenceMessage), "Captured bad signature verifies")
    }
    check("diagnostic deterministic forced proof refusal preserves original error") {
        var f = try LedgerFixture(); var lines: [String] = []
        var prepared: ModelAttempt?
        try refuses(.proofRefused) {
            try runFixtureDiagnosticCase({ prepared = try f.prepare(); throw ActivationError.proofRefused }, emit: { lines.append($0) })
        }
        try expect(lines.count == 1, "Forced refusal did not emit one diagnostic")
        guard let prepared else { throw CheckFailure(description: "Forced refusal lost prepared attempt") }
        let request = try DeviceRequest.parse(prepared.body, operation: prepared.operation)
        guard let proof = request.proof, let challenge = f.state.challenges[proof.challengeID] else {
            throw CheckFailure(description: "Forced refusal lost prepared proof or challenge")
        }
        let context = PossessionContext(accountID: challenge.accountID, activationID: nil, operation: .activate,
            publicKey: try fixtureKey(9).publicKey.x963Representation, nonce: proof.nonce, expiresAt: challenge.expiresAt)
        let d = try JSONDecoder().decode(PreparedFixtureDiagnostic.self, from: Data(lines[0].utf8))
        try expect(d.body == prepared.body && d.action == request.action.bytes && d.signature == proof.signature
                   && d.publicKey == context.publicKey && d.nonce == context.nonce
                   && d.accountID == Data(context.accountID.utf8) && d.activationID == nil
                   && d.operation == context.operation.rawValue && d.expiresAt == context.expiresAt
                   && d.now == prepared.now && d.challengeID == Data(proof.challengeID.utf8)
                   && d.referenceMessage == referenceMessage(request.action.bytes, context), "Forced refusal changed captured proof bytes")
        let key = try P256.Signing.PublicKey(x963Representation: d.publicKey)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: proof.signature)
        let rawStatus = key.isValidSignature(signature, for: d.referenceMessage) ? "accepted" : "refused"
        try expect(d.independentSignature == rawStatus, "Forced refusal misreported raw signature verification")
        try PossessionProof.verify(actionBytes: request.action.bytes, signature: proof.signature, context: context, now: prepared.now)
        try expect(d.parse == "accepted" && d.productionMessage == "matches-reference" && d.productionProof == "accepted",
                   "Forced refusal lost production proof acceptance")
        try expect(d.apply == "not-observed" && d.currentState == "not-captured" && d.modelReplay == "not-performed",
                   "Forced refusal invented apply or ledger evidence")
    }
    check("diagnostic success and expected refusal emit nothing") {
        let f = try DiagnosticInput(); var lines: [String] = []
        try runFixtureDiagnosticCase({ try f.capture() }, emit: { lines.append($0) })
        try runFixtureDiagnosticCase({ try refuses(.proofRefused) { throw ActivationError.proofRefused } }, emit: { lines.append($0) })
        try expect(lines.isEmpty, "Expected path emitted diagnostics")
    }
    check("diagnostic per-case reset never leaks prior prepared fixture") {
        let f = try DiagnosticInput(); try f.capture(); _ = try decodedDiagnostic(); FixtureDiagnostics.reset()
        try expect(try FixtureDiagnostics.render() == nil, "Reset retained prior fixture")
        var lines: [String] = []
        try refuses(.stale) { try runFixtureDiagnosticCase({ throw ActivationError.stale }, emit: { lines.append($0) }) }
        try expect(lines.isEmpty, "Unrelated failure leaked prior fixture")
    }
    check("diagnostic malformed public body stays exact and bounded") {
        var f = try DiagnosticInput(); f.attempt.body = Data([0, 0xff, 10, 27])
        try f.capture(); let d = try decodedDiagnostic()
        try expect(d.body == f.attempt.body && d.parse == "refused", "Malformed bytes hidden or accepted")
        let text = try FixtureDiagnostics.render()!
        try expect(!text.contains("\u{1b}") && !text.contains("\u{0}"), "Raw control escaped diagnostic structure")
    }
    check("diagnostic untrusted fixture text is encoded") {
        var f = try DiagnosticInput(); f.attempt.sessionID = "<script>\n\u{1b}[31m"
        try f.capture(); let d = try decodedDiagnostic(); let text = try FixtureDiagnostics.render()!
        try expect(d.sessionID == Data(f.attempt.sessionID.utf8), "Encoded text lost exact bytes")
        try expect(!text.contains("<script>") && !text.contains("\u{1b}"), "Text altered log structure")
    }
    check("diagnostic oversized input signals unavailable without truncation and keeps failure") {
        var f = try DiagnosticInput(); f.attempt.body = Data(repeating: 65, count: 65_537)
        try? f.capture(); var lines: [String] = []
        try refuses(.proofRefused) { try runFixtureDiagnosticCase({ throw ActivationError.proofRefused }, emit: { lines.append($0) }) }
        try expect(lines.count == 1 && lines[0].utf8.count <= FixtureDiagnostics.maximumOutputBytes, "Oversize diagnostic unbounded/missing")
        try expect(lines[0] == "{\"diagnostic\":\"unavailable\",\"reason\":\"input-bound\"}", "Truncated bytes claimed exact")
    }
    check("diagnostic malformed context cannot trap or mask original refusal") {
        var f = try DiagnosticInput(); f.context.accountID = "not-hex\n"
        try? f.capture(); var lines: [String] = []
        try refuses(.proofRefused) { try runFixtureDiagnosticCase({ throw ActivationError.proofRefused }, emit: { lines.append($0) }) }
        try expect(lines == ["{\"diagnostic\":\"unavailable\",\"reason\":\"input-shape\"}"], "Malformed reference context not safely refused")
    }
    check("diagnostic reporter failure preserves exact original error and status") {
        final class Original: Error {}
        let original = Original(); var escaped: Error?; var status = 0; var lines: [String] = []
        do { try runFixtureDiagnosticCase({ throw original }, emit: { lines.append($0) }, report: { throw FixtureDiagnosticError.unavailable }) }
        catch { escaped = error; status = 1 }
        try expect((escaped as? Original) === original && status == 1, "Reporter masked original failure/failing status")
        try expect(lines == ["{\"diagnostic\":\"unavailable\",\"reason\":\"reporter-failure\"}"], "Reporter failure not signalled safely")
    }
}
