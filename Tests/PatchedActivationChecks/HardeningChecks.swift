import Foundation
import CryptoKit
@_spi(Testing) import PatchedActivation

// Additive Phase B checks; the original 130 cases and static vectors are unchanged.
@MainActor func registerHardeningChecks() {
    for operation in [DeviceOperation.deactivate, .rename] {
        check("direct proof API refuses operation \(operation.rawValue)") {
            let f = try ProofFixture(operation: operation)
            try refuses(.proofRefused) { _ = try PossessionProof.message(actionBytes: f.action, context: f.context) }
            try refuses(.proofRefused) { try PossessionProof.verify(actionBytes: f.action, signature: f.signature, context: f.context, now: fixtureNow) }
        }
    }
    for shape in ["missingActivation", "zeroActivation", "unexpectedActivation", "shortNonce", "longNonce", "invalidPoint", "upperAccount", "overflowExpiry"] {
        check("direct proof context \(shape) refuses") {
            var f = try ProofFixture(operation: shape == "unexpectedActivation" ? .activate : .refresh)
            switch shape {
            case "missingActivation": f.context.activationID = nil
            case "zeroActivation":
                f.context.activationID = String(repeating: "0", count: 32)
                f.action = try actionBytes(.refresh, activation: f.context.activationID!)
            case "unexpectedActivation": f.context.activationID = fixtureID(100)
            case "shortNonce": f.context.nonce = Data(repeating: 0, count: 31)
            case "longNonce": f.context.nonce = Data(repeating: 0, count: 33)
            case "invalidPoint": f.context.publicKey = Data([4]) + Data(repeating: 0, count: 64)
            case "upperAccount": f.context.accountID = String(repeating: "A", count: 32)
            default: f.context.expiresAt = 9_007_199_254_740_992
            }
            try refuses(.proofRefused) { _ = try PossessionProof.message(actionBytes: f.action, context: f.context) }
            try refuses(.proofRefused) { try PossessionProof.verify(actionBytes: f.action, signature: f.signature, context: f.context, now: fixtureNow) }
        }
    }
    check("proof signing key must equal embedded activation public key") {
        var f = try ProofFixture()
        f.context.publicKey = try fixtureKey(2).publicKey.x963Representation
        f.signature = try fixtureKey(2).signature(for: referenceMessage(f.action, f.context)).rawRepresentation
        try refuses(.proofRefused) { try PossessionProof.verify(actionBytes: f.action, signature: f.signature, context: f.context, now: fixtureNow) }
    }
    check("bare hardware or adapter claim never labels supplied evidence validated") {
        try refuses(.proofRefused) { _ = try AttestationBinding.assurance(evidenceSupplied: true, adapterAvailable: true) }
        var f = try LedgerFixture(); let attempt = try f.prepare()
        var ledger = f.ledger(); let result = try ledger.apply(attempt)
        try expect(result.assurance == .secureStorageFallback, "Ordinary possession falsely became hardware evidence")
    }
    for operation in [DeviceOperation.deactivate, .rename, .rebind] {
        check("audit failure in \(operation) rolls back dependent state") {
            var f = try LedgerFixture(occupied: 1)
            let extra = operation == .rebind ? ",\"attestation\":\"\(Data("fixture-evidence".utf8).base64EncodedString())\",\"attestKeyID\":\"Ag==\"" : ""
            var attempt = try f.prepare(operation, key: 1, extraProof: extra); attempt.auditSucceeds = false
            let adapter = operation == .rebind ? ExactFixtureAttestation(expectedMessage: try independentAttemptMessage(attempt, state: f.state, key: 1), result: FixtureAttestationResult(keyID: Data([2]), counter: 1)) : nil
            var ledger = f.ledger(adapter: adapter); let before = ledger.snapshot
            try refuses(.auditFailed) { _ = try ledger.apply(attempt) }
            try expect(ledger.snapshot == before, "Audit failure left state in \(operation)")
        }
    }
    check("sequence overflow cannot consume proof or mint lease inputs") {
        var f = try LedgerFixture(occupied: 1)
        f.state.activations[fixtureID(100)]!.sequence = 9_007_199_254_740_991
        let attempt = try f.prepare(.refresh, key: 1)
        var ledger = f.ledger(); let before = ledger.snapshot
        try refuses(.invalidRequest) { _ = try ledger.apply(attempt) }
        try expect(ledger.snapshot == before, "Sequence overflow changed state")
    }
    check("rename is display-only and advances guarded revisions") {
        var f = try LedgerFixture(occupied: 1)
        let attempt = try f.prepare(.rename, name: "  Cafe\u{301}  ")
        var ledger = f.ledger(); let before = ledger.snapshot.activations[fixtureID(100)]!
        let result = try ledger.apply(attempt); let after = ledger.snapshot.activations[fixtureID(100)]!
        try expect(result.outcome == .renamed && after.displayName == "Café" && after.slot == before.slot && after.publicKey == before.publicKey, "Name changed identity")
        try expect(after.revision == 2 && ledger.snapshot.accountRevisions[fixtureAccount] == 2, "Rename omitted revisions")
    }
    for operation in [DeviceOperation.deactivate, .rename, .replace] {
        check("foreign target and unknown target share \(operation) refusal") {
            var outcomes: [AllocationOutcome] = []
            for targetID in [fixtureID(100), fixtureID(999)] {
                var f = try LedgerFixture(occupied: 1)
                let attempt = try f.prepare(operation, activation: targetID, session: 14)
                var ledger = f.ledger(); let before = ledger.snapshot.activations
                outcomes.append(try ledger.apply(attempt).outcome)
                try expect(ledger.snapshot.activations == before, "Foreign target changed")
            }
            try expect(outcomes == [.notFound, .notFound], "Cross-account target existence leaked")
        }
    }
    check("same-current active refresh replay is superseded without any new allowance") {
        var f = try LedgerFixture(occupied: 1)
        let attempt = try f.prepare(.refresh, key: 1, grant: ModelGrant(issuedAt: 1_000, permittedUntil: 2_000, hardEnd: 3_000))
        var ledger = f.ledger(); let original = try ledger.apply(attempt)
        try expect(original.outcome == .leased && original.grant?.permittedUntil == 2_000, "Original fixture grant missing")
        let before = ledger.snapshot; let replay = try ledger.apply(attempt)
        try expect(replay.outcome == .superseded && replay.grant == nil && replay.sequence == nil && ledger.snapshot == before, "Active grant replay returned allowance")
    }
    check("terminal-only session replay of its old granting refresh has no allowance") {
        var f = try LedgerFixture(occupied: 1)
        f.state.sessions[fixtureID(10)]!.activationID = fixtureID(100)
        let refresh = try f.prepare(.refresh, key: 1, grant: ModelGrant(issuedAt: 1_000, permittedUntil: 2_000, hardEnd: 3_000))
        let release = try f.prepare(.deactivate, session: 11)
        var ledger = f.ledger(); _ = try ledger.apply(refresh); _ = try ledger.apply(release)
        let before = ledger.snapshot; let replay = try ledger.apply(refresh)
        try expect(replay.outcome == .superseded && replay.released && replay.grant == nil && ledger.snapshot == before, "Released session recovered old grant")
    }
    check("terminal-only session cannot replay another user's revoked refresh") {
        var f = try LedgerFixture(occupied: 1)
        f.state.activations[fixtureID(100)]!.released = true; f.state.activations[fixtureID(100)]!.slot = nil
        f.state.sessions[fixtureID(10)]!.activationID = fixtureID(100)
        f.state.sessions[fixtureID(11)]!.activationID = fixtureID(100)
        let first = try f.prepare(.refresh, key: 1); var other = first; other.sessionID = fixtureID(11)
        var ledger = f.ledger(); _ = try ledger.apply(first); let before = ledger.snapshot
        try refuses(.invalidSession) { _ = try ledger.apply(other) }
        try expect(ledger.snapshot == before, "Terminal replay crossed session boundary")
    }
    check("escaped surrogate pair is valid Unicode with exact action digest") {
        let f = try ProofFixture()
        let raw = Data(String(decoding: f.action, as: UTF8.self).replacingOccurrences(of: "Fixture Mac", with: "\\uD83D\\uDC08").utf8)
        let parsed = try DeviceRequest.parse(bodyBytes(action: raw, signature: f.signature), operation: .activate)
        try expect(parsed.action.displayName == "🐈" && parsed.action.digest == digest(raw), "Surrogate pair changed exact bytes")
    }
    for escape in ["\\uD800", "\\uDC00", "\\uD800\\u0041", "\\u0000", "\\u202E"] {
        check("malformed or forbidden escaped scalar \(escape) refuses") {
            let f = try ProofFixture()
            let raw = Data(String(decoding: f.action, as: UTF8.self).replacingOccurrences(of: "Fixture Mac", with: escape).utf8)
            try refuses(.invalidRequest) { _ = try DeviceRequest.parse(bodyBytes(action: raw, signature: f.signature), operation: .activate) }
        }
    }
}
