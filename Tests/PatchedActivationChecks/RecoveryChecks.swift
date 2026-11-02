import Foundation
@_spi(Testing) import PatchedActivation

struct ExactFixtureAttestation: FixtureAttestationValidating {
    let expectedMessage: Data
    let result: FixtureAttestationResult
    func validate(evidence: Data, keyID: Data?, message: Data, assertion: Bool) throws -> FixtureAttestationResult {
        guard evidence == Data("fixture-evidence".utf8), message == expectedMessage else { throw ActivationError.proofRefused }
        return result
    }
}
func independentAttemptMessage(_ attempt: ModelAttempt, state: ModelState, key: Int) throws -> Data {
    let object = try JSONSerialization.jsonObject(with: attempt.body) as! [String: Any]
    let proof = object["proof"] as! [String: String]
    let challenge = state.challenges[proof["challengeID"]!]!
    let context = PossessionContext(accountID: state.sessions[attempt.sessionID]!.accountID,
        activationID: attempt.operation == .activate || attempt.operation == .replace ? nil : attempt.pathActivationID,
        operation: attempt.operation, publicKey: try fixtureKey(key).publicKey.x963Representation,
        nonce: Data(base64Encoded: proof["nonce"]!)!, expiresAt: challenge.expiresAt)
    return referenceMessage(Data(base64Encoded: object["action"] as! String)!, context)
}
@MainActor func registerRecoveryChecks() {
    check("operation5 records case-bound possession only") {
        var f = try LedgerFixture(occupied: 1)
        var recovery = ModelRecoveryCase(); recovery.id = fixtureID(900); recovery.accountID = fixtureAccount
        recovery.digest = String(repeating: "c", count: 64); f.state.recoveryCases[recovery.id] = recovery
        let action = try f.prepare(.recoveryPossession, key: 1)
        var ledger = f.ledger(); let before = ledger.snapshot
        let result = try ledger.apply(action)
        try expect(result.outcome == .possessionRecorded && result.grant == nil && result.sequence == nil, "Recovery granted entitlement")
        try expect(ledger.snapshot.activations == before.activations && ledger.snapshot.sessions == before.sessions && ledger.snapshot.accountRevisions == before.accountRevisions && ledger.snapshot.entitlementRevisions == before.entitlementRevisions, "Recovery mutated slot/session/entitlement")
        try expect(ledger.snapshot.recoveryCases[fixtureID(900)]?.possessionActivationID == fixtureID(100), "Case possession not recorded")
    }
    for mismatch in ["caseID", "digest", "foreignAccount", "released", "challengeCase", "challengeDigest"] {
        check("recovery \(mismatch) refuses all authority") {
            var f = try LedgerFixture(occupied: 1)
            var recovery = ModelRecoveryCase(); recovery.id = fixtureID(900); recovery.accountID = fixtureAccount
            recovery.digest = String(repeating: "c", count: 64)
            if mismatch == "caseID" { recovery.id = fixtureID(901) }
            if mismatch == "digest" { recovery.digest = String(repeating: "d", count: 64) }
            if mismatch == "foreignAccount" { recovery.accountID = otherAccount }
            f.state.recoveryCases[recovery.id] = recovery
            if mismatch == "released" { f.state.activations[fixtureID(100)]!.released = true; f.state.activations[fixtureID(100)]!.slot = nil }
            let action = try f.prepare(.recoveryPossession, key: 1)
            if mismatch == "challengeCase" { f.state.challenges[fixtureID(f.serial)]!.recoveryCaseID = fixtureID(901) }
            if mismatch == "challengeDigest" { f.state.challenges[fixtureID(f.serial)]!.recoveryCaseDigest = String(repeating: "d", count: 64) }
            var ledger = f.ledger(); let before = ledger.snapshot
            try refuses(.proofRefused) { _ = try ledger.apply(action) }
            try expect(ledger.snapshot == before, "Refused recovery wrote dependent state")
        }
    }
    check("fake optional attestation rebind preserves slot and resets fixture counter") {
        var f = try LedgerFixture(occupied: 1)
        f.state.activations[fixtureID(100)]!.attestation = FixtureAttestationResult(keyID: Data([1]), counter: 50)
        let extras = ",\"attestation\":\"\(Data("fixture-evidence".utf8).base64EncodedString())\",\"attestKeyID\":\"Ag==\""
        let action = try f.prepare(.rebind, key: 1, extraProof: extras)
        let adapter = ExactFixtureAttestation(expectedMessage: try independentAttemptMessage(action, state: f.state, key: 1),
                                             result: FixtureAttestationResult(keyID: Data([2]), counter: 1))
        var ledger = f.ledger(adapter: adapter); let result = try ledger.apply(action)
        let row = ledger.snapshot.activations[fixtureID(100)]!
        try expect(result.outcome == .rebound && result.grant == nil && row.slot == 1 && row.revision == 2 && row.attestation?.counter == 1, "Fixture rebind changed slot or failed counter reset")
        try assertInvariants(ledger)
    }
    check("supplied unvalidated attestation never falls back silently") {
        var f = try LedgerFixture()
        let extras = ",\"attestation\":\"ZmFrZQ==\",\"attestKeyID\":\"Ag==\""
        let action = try f.prepare(extraProof: extras)
        var ledger = f.ledger(); let before = ledger.snapshot
        try refuses(.proofRefused) { _ = try ledger.apply(action) }
        try expect(ledger.snapshot == before, "Unvalidated evidence accepted or spent state")
    }
    check("fixture equal assertion counter is consumed only once") {
        var f = try LedgerFixture(occupied: 1)
        f.state.activations[fixtureID(100)]!.attestation = FixtureAttestationResult(keyID: Data([2]), counter: 5)
        let extras = ",\"assertion\":\"\(Data("fixture-evidence".utf8).base64EncodedString())\""
        let grant = ModelGrant(issuedAt: 1_000, permittedUntil: 2_000, hardEnd: 2_000)
        let first = try f.prepare(.refresh, key: 1, grant: grant, extraProof: extras)
        let second = try f.prepare(.refresh, key: 1, grant: grant, extraProof: extras)
        let adapter = MultiMessageFixtureAttestation(messages: try [first, second].map { try independentAttemptMessage($0, state: f.state, key: 1) })
        var ledger = f.ledger(adapter: adapter)
        try expect(ledger.apply(first).outcome == .leased, "First fixture assertion failed")
        let before = ledger.snapshot
        try refuses(.assertionStale) { _ = try ledger.apply(current(second, ledger)) }
        try expect(ledger.snapshot == before, "Equal counter mutated nonce/request/lease/slot")
    }
    check("absent optional assertion permits fallback despite stored fixture attestation") {
        var f = try LedgerFixture(occupied: 1)
        f.state.activations[fixtureID(100)]!.attestation = FixtureAttestationResult(keyID: Data([2]), counter: 5)
        let attempt = try f.prepare(.refresh, key: 1, grant: ModelGrant(issuedAt: 1_000, permittedUntil: 2_000, hardEnd: 2_000))
        var ledger = f.ledger()
        try expect(ledger.apply(attempt).outcome == .leased, "Stored optional key became mandatory")
    }
    for extra in [",\"attestation\":\"\(Data(repeating: 0, count: 8_193).base64EncodedString())\",\"attestKeyID\":\"Ag==\"",
                  ",\"assertion\":\"\(Data(repeating: 0, count: 1_025).base64EncodedString())\"",
                  ",\"attestation\":\"Ag==\"",
                  ",\"assertion\":\"Ag==\",\"attestation\":\"Ag==\",\"attestKeyID\":\"Ag==\""] {
        check("malformed optional evidence shape or size refuses") {
            let f = try ProofFixture()
            try refuses(.invalidRequest) { _ = try DeviceRequest.parse(bodyBytes(action: f.action, signature: f.signature, extraProof: extra), operation: .activate) }
        }
    }
}

struct MultiMessageFixtureAttestation: FixtureAttestationValidating {
    let messages: [Data]
    func validate(evidence: Data, keyID: Data?, message: Data, assertion: Bool) throws -> FixtureAttestationResult {
        guard assertion, evidence == Data("fixture-evidence".utf8), messages.contains(message) else { throw ActivationError.proofRefused }
        return FixtureAttestationResult(keyID: Data([2]), counter: 6)
    }
}
