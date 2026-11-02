import Foundation
@_spi(Testing) import PatchedActivation

@MainActor func registerLedgerChecks() {
    check("five allocations succeed and sixth is terminal limitReached") {
        var f = try LedgerFixture(); var attempts: [ModelAttempt] = []
        for key in 1...6 { attempts.append(try f.prepare(key: key, newID: 100 + key)) }
        var ledger = f.ledger()
        for (index, attempt) in attempts.enumerated() {
            let result = try ledger.apply(current(attempt, ledger))
            try expect(result.outcome == (index < 5 ? .activated : .limitReached), "Incorrect allocation result")
            try expect(result.grant == nil, "Activation granted entitlement")
            try expect(used(ledger) == min(index + 1, 5), "Wrong occupancy")
            try assertInvariants(ledger)
        }
    }
    check("same household key across fake local users reuses one slot") {
        var f = try LedgerFixture()
        let a = try f.prepare(key: 1, session: 10)
        let b = try f.prepare(key: 1, session: 11)
        var ledger = f.ledger(); let first = try ledger.apply(a)
        let revision = ledger.snapshot.accountRevisions[fixtureAccount]
        let second = try ledger.apply(current(b, ledger))
        try expect(second.outcome == .reused && second.activationID == first.activationID && used(ledger) == 1, "Local user consumed another slot")
        try expect(ledger.snapshot.accountRevisions[fixtureAccount] == revision, "Reused slot changed revision")
        try expect(ledger.snapshot.sessions[fixtureID(10)]?.activationID == first.activationID && ledger.snapshot.sessions[fixtureID(11)]?.activationID == first.activationID, "Users did not bind independently")
    }
    check("same copied fallback key in different households remains separate") {
        var f = try LedgerFixture()
        let a = try f.prepare(key: 1, session: 10); let b = try f.prepare(key: 1, session: 14)
        var ledger = f.ledger(); let first = try ledger.apply(a); let second = try ledger.apply(b)
        try expect(first.activationID != second.activationID && used(ledger) == 1 && used(ledger, account: otherAccount) == 1, "Households coalesced")
    }
    check("equal names never reuse different keys") {
        var f = try LedgerFixture(); let a = try f.prepare(key: 1); let b = try f.prepare(key: 2)
        var ledger = f.ledger(); let first = try ledger.apply(a); let second = try ledger.apply(current(b, ledger))
        try expect(first.activationID != second.activationID && used(ledger) == 2, "Name became identity")
    }
    for operation in [DeviceOperation.activate, .replace, .deactivate] {
        check("\(operation) lost response retries without another mutation") {
            var f = try LedgerFixture(occupied: operation == .activate ? 0 : 1)
            let a = try f.prepare(operation, key: 9)
            var ledger = f.ledger(); let first = try ledger.apply(a); let committed = ledger.snapshot
            var retry = a; retry.now = 1_700
            let second = try ledger.apply(retry)
            try expect(first == second && ledger.snapshot == committed, "Lost-response retry mutated state or required fresh proof")
        }
    }
    check("same request ID with changed action conflicts") {
        var f = try LedgerFixture(); let a = try f.prepare(request: 70, key: 1)
        let b = try f.prepare(request: 70, key: 2)
        var ledger = f.ledger(); _ = try ledger.apply(a); let before = ledger.snapshot
        try refuses(.requestConflict) { _ = try ledger.apply(current(b, ledger)) }
        try expect(ledger.snapshot == before, "Conflict changed dependent state")
    }
    for guardName in ["accountRevision", "audit", "deadSession", "recentAuth", "consumed", "expired", "foreignAccount", "foreignSession", "wrongPurpose", "wrongKey", "wrongNonceMAC"] {
        check("guard \(guardName) rolls back all dependent state") {
            var f = try LedgerFixture(); var a = try f.prepare()
            var error: ActivationError = .proofRefused
            let challenge = fixtureID(f.serial)
            switch guardName {
            case "accountRevision": a.expectedAccountRevision = 0; error = .stale
            case "audit": a.auditSucceeds = false; error = .auditFailed
            case "deadSession": f.state.sessions[fixtureID(10)]!.revoked = true; error = .invalidSession
            case "recentAuth": f.state.sessions[fixtureID(10)]!.authenticatedAt = 400; error = .reauthRequired
            case "consumed": f.state.challenges[challenge]!.consumed = true
            case "expired": f.state.challenges[challenge]!.expiresAt = fixtureNow
            case "foreignAccount": f.state.challenges[challenge]!.accountID = otherAccount
            case "foreignSession": f.state.challenges[challenge]!.sessionID = fixtureID(11)
            case "wrongPurpose": f.state.challenges[challenge]!.operation = .rebind
            case "wrongKey": f.state.challenges[challenge]!.keyDigest = digest(try fixtureKey(8).publicKey.x963Representation)
            default: f.state.challenges[challenge]!.nonceMAC = Data(repeating: 0, count: 32)
            }
            var ledger = f.ledger(); let before = ledger.snapshot
            try refuses(error) { _ = try ledger.apply(a) }
            try expect(ledger.snapshot == before, "Refusal consumed challenge, request, audit, slot, session or history")
        }
    }
    check("fresh challenge retries exact action after expired proof") {
        var f = try LedgerFixture(); let a = try f.prepare(request: 80)
        f.state.challenges[fixtureID(f.serial)]!.expiresAt = fixtureNow
        let b = try f.prepare(request: 80)
        var ledger = f.ledger()
        try refuses(.proofRefused) { _ = try ledger.apply(a) }
        let result = try ledger.apply(b)
        try expect(result.outcome == .activated && used(ledger) == 1 && ledger.snapshot.requests.count == 1, "Proof transport retry changed action identity")
    }
    check("copied session without matching activation key cannot refresh") {
        var f = try LedgerFixture(occupied: 1); let a = try f.prepare(.refresh, key: 9)
        var ledger = f.ledger(); let before = ledger.snapshot
        try refuses(.proofRefused) { _ = try ledger.apply(a) }
        try expect(ledger.snapshot == before, "Wrong-key refresh changed state")
    }
    check("consumed proof cannot authorise a different request action") {
        var f = try LedgerFixture(); let first = try f.prepare(request: 80)
        var second = first
        let original = try JSONSerialization.jsonObject(with: first.body) as! [String: Any]
        let oldProof = original["proof"] as! [String: String]
        let changedAction = try actionBytes(request: 81, key: 9)
        second.body = bodyBytes(action: changedAction, challenge: oldProof["challengeID"]!,
            nonce: Data(base64Encoded: oldProof["nonce"]!)!, signature: Data(base64Encoded: oldProof["signature"]!)!)
        var ledger = f.ledger(); _ = try ledger.apply(first); let before = ledger.snapshot
        try refuses(.proofRefused) { _ = try ledger.apply(current(second, ledger)) }
        try expect(ledger.snapshot == before, "Replayed proof mutated a new action")
    }
    check("audit failure on refresh retains nonce and maximum grant atomically") {
        var f = try LedgerFixture(occupied: 1)
        f.state.activations[fixtureID(100)]!.maxGrantPermittedUntil = 2_000
        var attempt = try f.prepare(.refresh, key: 1, grant: ModelGrant(issuedAt: 1_000, permittedUntil: 3_000, hardEnd: 3_000))
        attempt.auditSucceeds = false
        var ledger = f.ledger(); let before = ledger.snapshot
        try refuses(.auditFailed) { _ = try ledger.apply(attempt) }
        try expect(ledger.snapshot == before, "Audit failure advanced grant or nonce")
        attempt.auditSucceeds = true
        try expect(ledger.apply(attempt).outcome == .leased, "Rolled-back proof could not be retried")
    }
    check("maximum outstanding grant survives shorter subsequent grant") {
        var f = try LedgerFixture(occupied: 1)
        let a = try f.prepare(.refresh, key: 1, grant: ModelGrant(issuedAt: 1_000, permittedUntil: 3_000, hardEnd: 4_000))
        let b = try f.prepare(.refresh, key: 1, grant: ModelGrant(issuedAt: 1_000, permittedUntil: 2_000, hardEnd: 2_500))
        var ledger = f.ledger(); _ = try ledger.apply(a); _ = try ledger.apply(current(b, ledger))
        let row = ledger.snapshot.activations[fixtureID(100)]!
        try expect(row.maxGrantPermittedUntil == 3_000 && row.lastGrant?.permittedUntil == 2_000, "Latest grant lost older outstanding bound")
        let before = ledger.snapshot; let replay = try ledger.apply(a)
        try expect(replay.outcome == .superseded && replay.grant == nil && ledger.snapshot == before, "Grant replay reissued allowance")
    }
    check("released refresh stays non-granting despite renewed fixture entitlement") {
        var f = try LedgerFixture(occupied: 1)
        f.state.sessions[fixtureID(11)]!.activationID = fixtureID(100)
        let release = try f.prepare(.deactivate, session: 10)
        let refresh = try f.prepare(.refresh, key: 1, session: 11, grant: ModelGrant(issuedAt: 1_000, permittedUntil: 9_000, hardEnd: 9_000))
        var ledger = f.ledger(); _ = try ledger.apply(release)
        let result = try ledger.apply(current(refresh, ledger)); let after = ledger.snapshot
        try expect(result.outcome == .revokedLease && result.grant?.issuedAt == fixtureNow && result.grant?.permittedUntil == fixtureNow && result.grant?.hardEnd == fixtureNow, "Released refresh granted access")
        try expect(result.sequence == 1 && used(ledger) == 0 && after.activations[fixtureID(100)]?.lastRefreshAt == nil, "Terminal refresh changed active state")
        let retry = try ledger.apply(refresh)
        try expect(retry == result && ledger.snapshot == after, "Terminal lost-response replay changed lease inputs")
    }
}
