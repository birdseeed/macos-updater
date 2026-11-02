import Foundation
import CryptoKit
@_spi(Testing) import PatchedActivation

// This MAC encoding is an in-memory fixture convention, not a service wire contract.
func fixtureNonceMAC(id: String, account: String, operation: DeviceOperation, nonce: Data) -> Data {
    let material = unhex(id) + unhex(account) + Data([operation.rawValue]) + nonce
    return Data(HMAC<SHA256>.authenticationCode(for: material, using: SymmetricKey(data: fixtureMACKey)))
}
struct LedgerFixture {
    var state = ModelState()
    var serial = 500
    init(occupied: Int = 0) throws {
        for account in [fixtureAccount, otherAccount] {
            state.accountRevisions[account] = 1; state.entitlementRevisions[account] = 11
        }
        for number in 10...14 {
            var session = ModelSession(); session.id = fixtureID(number)
            session.accountID = number == 14 ? otherAccount : fixtureAccount
            session.authenticatedAt = 999; session.expiresAt = 5_000
            state.sessions[session.id] = session
        }
        for index in 0..<occupied {
            var activation = ModelActivation(); activation.id = fixtureID(100 + index)
            activation.accountID = fixtureAccount; activation.publicKey = try fixtureKey(index + 1).publicKey.x963Representation
            activation.slot = index + 1; activation.displayName = "Duplicate fixture name"
            state.activations[activation.id] = activation
        }
    }
    @MainActor mutating func prepare(_ operation: DeviceOperation = .activate, request: Int? = nil, key: Int = 9,
                          activation: String = fixtureID(100), revision: UInt64 = 1,
                          session: Int = 10, newID: Int? = nil, name: String = "Fixture Mac",
                          grant: ModelGrant? = nil, extraProof: String = "") throws -> ModelAttempt {
        serial += 1
        let action = try actionBytes(operation, request: request ?? serial, key: key, name: name,
                                     activation: activation, revision: String(revision))
        let owner = state.sessions[fixtureID(session)]!.accountID
        let publicKey = try fixtureKey(key).publicKey.x963Representation
        let nonce = Data(repeating: UInt8(serial % 250 + 1), count: 32)
        let context = PossessionContext(accountID: owner,
            activationID: operation == .activate || operation == .replace ? nil : activation,
            operation: operation, publicKey: publicKey, nonce: nonce, expiresAt: 1_300)
        var body: Data
        var preparedSignature: Data?
        if operation == .deactivate || operation == .rename { body = bodyBytes(action: action) }
        else {
            var challenge = ModelChallenge(); challenge.id = fixtureID(serial)
            challenge.sessionID = fixtureID(session); challenge.accountID = owner; challenge.operation = operation
            challenge.keyDigest = digest(publicKey); challenge.expiresAt = 1_300
            challenge.nonceMAC = fixtureNonceMAC(id: challenge.id, account: owner, operation: operation, nonce: nonce)
            if operation == .recoveryPossession {
                challenge.recoveryCaseID = fixtureID(900); challenge.recoveryCaseDigest = String(repeating: "c", count: 64)
            }
            state.challenges[challenge.id] = challenge
            let signature = try fixtureKey(key).signature(for: referenceMessage(action, context)).rawRepresentation
            preparedSignature = signature
            body = bodyBytes(action: action, challenge: challenge.id, nonce: nonce,
                             signature: signature, extraProof: extraProof)
        }
        let attempt = ModelAttempt(sessionID: fixtureID(session), operation: operation, body: body,
            pathActivationID: operation == .activate || operation == .replace ? nil : activation,
            now: fixtureNow, expectedAccountRevision: state.accountRevisions[owner]!,
            newActivationID: newID.map(fixtureID) ?? fixtureID(1_000 + serial), grantingWindow: grant)
        try? FixtureDiagnostics.capture(attempt: attempt, action: action, context: context,
            signature: preparedSignature, challengeID: preparedSignature == nil ? nil : fixtureID(serial))
        return attempt
    }
    func ledger(adapter: (any FixtureAttestationValidating)? = nil) -> SlotLedger {
        SlotLedger(fixtureState: state, nonceAuthenticationKey: fixtureMACKey, attestationAdapter: adapter)
    }
}
func used(_ ledger: SlotLedger, account: String = fixtureAccount) -> Int {
    ledger.snapshot.activations.values.filter { $0.accountID == account && $0.slot != nil }.count
}
func current(_ attempt: ModelAttempt, _ ledger: SlotLedger) -> ModelAttempt {
    var fresh = attempt
    if let account = ledger.snapshot.sessions[attempt.sessionID]?.accountID {
        fresh.expectedAccountRevision = ledger.snapshot.accountRevisions[account]!
    }
    return fresh
}
func assertInvariants(_ ledger: SlotLedger) throws {
    for account in ledger.snapshot.accountRevisions.keys {
        let rows = ledger.snapshot.activations.values.filter { $0.accountID == account && $0.slot != nil }
        try expect(rows.count <= 5, "Five-slot cap exceeded")
        try expect(Set(rows.compactMap(\.slot)).count == rows.count, "Duplicate slot")
        try expect(Set(rows.map(\.publicKey)).count == rows.count, "Duplicate occupied key")
    }
    for row in ledger.snapshot.activations.values {
        try expect(row.released == (row.slot == nil), "Released state and occupancy disagree")
    }
    try expect(ledger.snapshot.entitlementRevisions.values.allSatisfy { $0 == 11 }, "Allocation changed entitlement")
}
func permutations<T>(_ values: [T]) -> [[T]] {
    if values.isEmpty { return [[]] }
    return values.indices.flatMap { index -> [[T]] in
        var remaining = values; let first = remaining.remove(at: index)
        return permutations(remaining).map { [first] + $0 }
    }
}
