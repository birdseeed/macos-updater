import Foundation
@_spi(Testing) import PatchedLicenceSupport
@MainActor func registerContextChecks() {
    check("ordinary default refuses all lookups including known foreign and malformed") {
        let client = RefusingSupportClient()
        for id in [account, foreignID, "", "*", "a", "person@example.invalid"] {
            try refuses(.notConfigured) { _ = try client.lookup(accountID: id) }
        }
    }
    for action in SupportAction.allCases {
        check("ordinary default refuses \(action.rawValue) prepare and commit") {
            let client = RefusingSupportClient()
            try refuses(.notConfigured) { _ = try client.prepare(action: action, accountID: account) }
            try refuses(.notConfigured) { _ = try client.commit(requestID: requestID, digest: String(repeating: "1", count: 64)) }
        }
        check("explicit fixture positive transition \(action.rawValue)") {
            // Recovery has additional requirements and uses its dedicated atomic model.
            if action == .changeAccountEmail {
                let r = try recoveryCase(); let c = try recoveryConfirmation(r)
                var state = recoveryState(); var ledger = SupportFixtureLedger()
                let result = try RecoveryFixtureModel.commit(r, confirmation: c, context: recoveryContext(r),
                    supportContext: fixtureContext(c), now: now, state: &state, ledger: &ledger)
                try expect(result == .committed && ledger.effectCount == 1, "Explicit fixture recovery succeeds")
            } else {
                let c = try decoded(descriptor(action)); var ledger = SupportFixtureLedger()
                let outcome = try SupportFixtureModel.commit(c, context: fixtureContext(c), now: now, ledger: &ledger)
                try expect(outcome == .committed && ledger.effectCount == 1, "Explicit fixture commit succeeds")
            }
        }
    }
    for kind in ["none", "consumerSession", "restrictedPurchase", "checkoutEmail", "receipt", "providerPayment", "verifiedHousehold", "operator", "spoofedIdentityHeader"] {
        check("\(kind) cannot become fixture operator") {
            let c = try decoded(descriptor()); var context = fixtureContext(c); context.kind = kind
            var ledger = SupportFixtureLedger(); let before = ledger
            try refuses(.invalidContext) { _ = try SupportFixtureModel.commit(c, context: context, now: now, ledger: &ledger) }
            try expect(ledger == before, "Unauthorised context writes nothing")
        }
    }
    let contexts: [(String, (inout SupportFixtureContext) -> Void)] = [
        ("request ID", { $0.requestID = foreignID }),
        ("digest", { $0.digest = String(repeating: "0", count: 64) }),
        ("session switch", { $0.sessionID = foreignID }),
        ("empty session", { $0.sessionID = ""; $0.preparedSessionID = "" }),
        ("missing human confirmation", { $0.humanConfirmed = false })
    ]
    for (name, change) in contexts {
        check("fixture refuses changed \(name) without spending") {
            let c = try decoded(descriptor()); var context = fixtureContext(c); change(&context)
            var ledger = SupportFixtureLedger(); let before = ledger
            try refuses(.invalidContext) { _ = try SupportFixtureModel.commit(c, context: context, now: now, ledger: &ledger) }
            try expect(ledger == before, "Invalid context leaves request prepared")
        }
    }
    check("operator switching cannot commit prepared confirmation") {
        let c = try decoded(descriptor()); var context = fixtureContext(c); context.operatorID = foreignID
        var ledger = SupportFixtureLedger()
        try refuses(.foreignOperator) { _ = try SupportFixtureModel.commit(c, context: context, now: now, ledger: &ledger) }
        try expect(ledger.effectCount == 0 && ledger.outcome == nil, "Foreign operator refused")
    }
    check("pure ordinary commit cannot bypass recovery checks") {
        let c = try decoded(descriptor(.changeAccountEmail)); var ledger = SupportFixtureLedger()
        try refuses(.recoveryHeld) { _ = try SupportFixtureModel.commit(c, context: fixtureContext(c), now: now, ledger: &ledger) }
        try expect(ledger == SupportFixtureLedger(), "Recovery requires dedicated evidence model")
    }
}
