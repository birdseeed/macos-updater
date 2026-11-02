import Foundation
@_spi(Testing) import PatchedLicenceSupport
@MainActor func registerTransactionChecks() {
    check("same operator digest repeat returns terminal readback only including expired") {
        let c = try decoded(descriptor()); let context = fixtureContext(c); var ledger = SupportFixtureLedger()
        _ = try SupportFixtureModel.commit(c, context: context, now: now, ledger: &ledger)
        let stored = ledger
        for _ in 0..<12 {
            let result = try SupportFixtureModel.commit(c, context: context, now: 400_000, ledger: &ledger)
            try expect(result == stored.outcome && ledger == stored, "Repeated observation never repeats effects or audit")
        }
    }
    check("foreign operator and digest cannot read terminal result") {
        let c = try decoded(descriptor()); var context = fixtureContext(c); var ledger = SupportFixtureLedger()
        _ = try SupportFixtureModel.commit(c, context: context, now: now, ledger: &ledger); let before = ledger
        context.operatorID = foreignID
        try refuses(.foreignOperator) { _ = try SupportFixtureModel.commit(c, context: context, now: now, ledger: &ledger) }
        context = fixtureContext(c); context.digest = String(repeating: "0", count: 64)
        try refuses(.invalidContext) { _ = try SupportFixtureModel.commit(c, context: context, now: now, ledger: &ledger) }
        try expect(ledger == before, "Foreign readback changed terminal ledger")
    }
    check("expired and future confirmation remain unspent") {
        let c = try decoded(descriptor()); var ledger = SupportFixtureLedger()
        for at: UInt64 in [299_999, 300_300, maxExact + 1] {
            try refuses(.expired) { _ = try SupportFixtureModel.commit(c, context: fixtureContext(c), now: at, ledger: &ledger) }
            try expect(ledger == SupportFixtureLedger(), "Time refusal cannot claim")
        }
    }
    let stale: [(String, (inout SupportFixtureContext) -> Void)] = [
        ("account ID", { $0.accountID = foreignID }),
        ("account revision including email mapping", { $0.accountRevision += 1 }),
        ("entitlement revision", { $0.entitlementRevision += 1 }),
        ("target revision", { $0.targetRevision += 1 }),
        ("foreign target", { $0.targetID = foreignID })
    ]
    for (name, change) in stale {
        check("stale \(name) terminal targetChanged with no effects") {
            let c = try decoded(descriptor()); var context = fixtureContext(c); change(&context)
            var ledger = SupportFixtureLedger()
            let result = try SupportFixtureModel.commit(c, context: context, now: now, ledger: &ledger)
            try expect(result == .targetChanged && ledger.outcome == result && ledger.effectCount == 0 &&
                       ledger.dependentCount == 0 && !ledger.audit.isEmpty, "Guard loser terminal and audited")
            let before = ledger
            try expect(try SupportFixtureModel.commit(c, context: fixtureContext(c), now: now, ledger: &ledger) == .targetChanged,
                       "Guard cannot resurrect spent request")
            try expect(ledger == before, "Terminal repeat is read-only")
        }
    }
    for fault in [SupportFixtureFault.missingEffect, .missingDependent, .auditThrows, .auditNoRow, .unmatchedCompletion] {
        check("atomic rollback of claim effect audit for \(fault)") {
            let c = try decoded(descriptor()); var ledger = SupportFixtureLedger(); let before = ledger
            try refuses(.rollback) { _ = try SupportFixtureModel.commit(c, context: fixtureContext(c), now: now,
                                                                        ledger: &ledger, fault: fault) }
            try expect(ledger == before, "No claim, effect or pending row survives rollback")
            try expect(try SupportFixtureModel.commit(c, context: fixtureContext(c), now: now, ledger: &ledger) == .committed,
                       "Rolled back request remains usable")
        }
    }
    check("false operate guard becomes terminal targetChanged") {
        let c = try decoded(descriptor()); var ledger = SupportFixtureLedger()
        let result = try SupportFixtureModel.commit(c, context: fixtureContext(c), now: now, ledger: &ledger, fault: .falseGuard)
        try expect(result == .targetChanged && ledger.outcome == result && ledger.effectCount == 0,
                   "Missing operate effect is never committed")
    }
    check("ambiguous response resolved from terminal row with no repeat") {
        let c = try decoded(descriptor()); var ledger = SupportFixtureLedger()
        try refuses(.unknownOutcome) { _ = try SupportFixtureModel.commit(c, context: fixtureContext(c), now: now,
                                                                          ledger: &ledger, fault: .lostReadback) }
        try expect(ledger.outcome == .committed && ledger.effectCount == 1, "Lost response not rollback")
        let before = ledger
        try expect(try SupportFixtureModel.commit(c, context: fixtureContext(c), now: now, ledger: &ledger) == .committed,
                   "Readback resolves ambiguity")
        try expect(ledger == before, "No second effect")
    }
    for action in SupportAction.allCases.filter({ $0 != .changeAccountEmail }) {
        check("\(action) minimal audit has identity reason digest outcome without sensitive display") {
            let c = try decoded(descriptor(action)); var ledger = SupportFixtureLedger()
            _ = try SupportFixtureModel.commit(c, context: fixtureContext(c), now: now, ledger: &ledger)
            let audit = ledger.audit.joined(separator: "|")
            for required in [operatorID, account, c.digest, action.rawValue, "customerRequest", "committed", String(now)] {
                try expect(audit.contains(required), "Audit omitted \(required)")
            }
            for forbidden in ["example.invalid", "@", "123456", "challenge", "token", "Mac label", "Reviewed", "<b>", "AAECAw"] {
                try expect(!audit.contains(forbidden), "Audit contains forbidden content")
            }
            try expect(ledger.dependentCount > 0, "Every committed effect asserts dependent record")
        }
    }
}
