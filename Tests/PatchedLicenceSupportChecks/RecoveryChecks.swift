import Foundation
@_spi(Testing) import PatchedLicenceSupport
@MainActor func registerRecoveryChecks() {
    check("independent case digest vector uses exact deterministic bytes") {
        let v = try vector("recovery-case"); let b = Data(v.bytes.utf8)
        try expect(digest(b, domain: "im.patched.support.recovery.v1") == v.sha256, "Independent recovery digest")
        let r = try RecoveryCase.parse(b, expectedDigest: v.sha256)
        try expect(r.caseID == caseID && r.account.accountID == account && r.digest == v.sha256, "Exact recovery binding")
        try refuses(.digestMismatch) { _ = try RecoveryCase.parse(b, expectedDigest: digest(b)) }
    }
    for (name, old, new) in [
        ("case unknown field", "\"schemaVersion\":1", "\"schemaVersion\":1,\"extra\":0"),
        ("case duplicate decoded key", "\"caseID\":", "\"case\\u0049D\":\"x\",\"caseID\":"),
        ("case missing ownership judgement", "\"ownershipJudgement\":true,", ""),
        ("case false ownership judgement", "\"ownershipJudgement\":true", "\"ownershipJudgement\":false"),
        ("case missing reference", "\"ownershipReference\":\"44444444444444444444444444444444\"", "\"ownershipReference\":\"\""),
        ("case invalid kind", "\"sourceKind\":\"paid\"", "\"sourceKind\":\"receipt\""),
        ("case clear email", String(repeating: "6", count: 64), "new@example.invalid"),
        ("case reordered fields", "\"accountRevision\":7,\"entitlementRevision\":3", "\"entitlementRevision\":3,\"accountRevision\":7")
    ] {
        check(name) {
            let b = replace(Data(try vector("recovery-case").bytes.utf8), old, new)
            try refuses(.malformedDescriptor) { _ = try RecoveryCase.parse(b, expectedDigest: digest(b, domain: "im.patched.support.recovery.v1")) }
        }
    }
    for kind in ["paid", "trial", "beta"] {
        check("\(kind) full fixture recovery preserves history and releases all authority") {
            let r = try recoveryCase(kind); let c = try recoveryConfirmation(r)
            var state = recoveryState(); let before = state; var ledger = SupportFixtureLedger()
            let outcome = try RecoveryFixtureModel.commit(r, confirmation: c, context: recoveryContext(r),
                supportContext: fixtureContext(c), now: now, state: &state, ledger: &ledger)
            try expect(outcome == .committed && ledger.outcome == .committed, "Recovery committed through ledger")
            try expect(state.accountID == before.accountID && state.accountRevision == before.accountRevision + 1 &&
                       state.entitlementRevision == before.entitlementRevision, "Identity preserved; account revision only")
            try expect(state.emailHMAC == r.newEmailHMAC, "Exact new email opaque binding")
            try expect(state.sessions.keys == before.sessions.keys && state.sessions.values.allSatisfy { !$0 }, "All sessions revoked")
            try expect(state.occupiedSlots.isEmpty && state.activationRevisions[activationID] == 10, "All activation revisions advance and slots released")
            try expect(state.trialStart == before.trialStart && state.trialEnd == before.trialEnd &&
                       state.betaInvitation == before.betaInvitation && state.paidHistory == before.paidHistory, "No entitlement history reset")
            try expect(state.mintedSessions == 0 && state.mintedKeys == 0 && state.mintedLeases == 0, "Recovery mints no authority")
            let after = state; let terminal = ledger
            try expect(try RecoveryFixtureModel.commit(r, confirmation: c, context: recoveryContext(r),
                supportContext: fixtureContext(c), now: now, state: &state, ledger: &ledger) == .committed, "Terminal recovery repeat")
            try expect(state == after && ledger == terminal, "Terminal recovery cannot increment again")
        }
    }
    let contextChanges: [(String, SupportError, (inout RecoveryFixtureContext) -> Void)] = [
        ("no independent ownership judgement", .ownershipUnproven, { $0.independentOwnershipJudgement = false }),
        ("no ownership evidence reference", .ownershipUnproven, { $0.ownershipReference = "" }),
        ("foreign ownership evidence reference", .ownershipUnproven, { $0.ownershipReference = foreignID }),
        ("receipt screenshot alone", .ownershipUnproven, { $0.sourceVerified = false; $0.activeMacPossession = false }),
        ("old email alone", .ownershipUnproven, { $0.sourceVerified = false; $0.independentOwnershipJudgement = false }),
        ("device proof alone", .ownershipUnproven, { $0.sourceVerified = false }),
        ("copied token without key", .ownershipUnproven, { $0.activeMacPossession = false }),
        ("foreign purchase mapping", .ownershipUnproven, { $0.sourceAccountID = foreignID }),
        ("restricted purchase credential", .ownershipUnproven, { $0.sourceKind = "restrictedPurchase" }),
        ("provider payment alone", .ownershipUnproven, { $0.independentOwnershipJudgement = false; $0.activeMacPossession = false }),
        ("foreign possession case", .ownershipUnproven, { $0.possessionCaseDigest = String(repeating: "0", count: 64) }),
        ("proof wrong purpose", .recoveryHeld, { $0.proofPurpose = "sign-in" }),
        ("proof wrong account", .recoveryHeld, { $0.proofAccountID = foreignID }),
        ("proof wrong case", .recoveryHeld, { $0.proofCaseID = foreignID }),
        ("proof wrong digest", .recoveryHeld, { $0.proofCaseDigest = String(repeating: "0", count: 64) }),
        ("proof wrong new email", .recoveryHeld, { $0.proofNewEmailHMAC = String(repeating: "0", count: 64) }),
        ("expired new email proof", .recoveryHeld, { $0.proofExpiresAt = now }),
        ("future new email proof", .recoveryHeld, { $0.proofVerifiedAt = now + 1 }),
        ("missing accepted notice", .recoveryHeld, { $0.noticeAcceptedAt = nil }),
        ("ambiguous notice", .recoveryHeld, { $0.hold = "ambiguousSend" }),
        ("bounce", .recoveryHeld, { $0.hold = "bounce" }),
        ("old owner objection", .recoveryHeld, { $0.hold = "objection" }),
        ("disputed ownership", .recoveryHeld, { $0.hold = "disputedOwnership" }),
        ("unknown hold", .recoveryHeld, { $0.hold = "unrecognised" }),
        ("notice changed case digest", .recoveryHeld, { $0.noticeCaseDigest = String(repeating: "0", count: 64) }),
        ("notice at exact 72h boundary", .recoveryHeld, { $0.noticeAcceptedAt = now - 259_200 }),
        ("future notice timestamp", .recoveryHeld, { $0.noticeAcceptedAt = now + 1 }),
        ("notice timestamp overflow", .recoveryHeld, { $0.noticeAcceptedAt = maxExact }),
        ("new address collision", .addressCollision, { $0.addressCollision = true }),
        ("all Macs lost exceptional path", .ownershipUnproven, { $0.exceptionalLostAllMacs = true }),
        ("case changed", .recoveryHeld, { $0.caseID = foreignID }),
        ("case digest changed", .recoveryHeld, { $0.caseDigest = String(repeating: "0", count: 64) }),
        ("recovery foreign operator", .foreignOperator, { $0.operatorID = foreignID }),
        ("recovery foreign account", .recoveryHeld, { $0.accountID = foreignID })
    ]
    for (name, refusal, mutate) in contextChanges {
        check("recovery refuses \(name) with no state change") {
            let r = try recoveryCase(); let c = try recoveryConfirmation(r); var context = recoveryContext(r); mutate(&context)
            var state = recoveryState(); let before = state; var ledger = SupportFixtureLedger()
            try refuses(refusal) { _ = try RecoveryFixtureModel.commit(r, confirmation: c, context: context,
                supportContext: fixtureContext(c), now: now, state: &state, ledger: &ledger) }
            try expect(state == before && ledger == SupportFixtureLedger(), "Refusal cannot disclose or mutate")
        }
    }
    check("beta requires independent invitation record") {
        let r = try recoveryCase("beta"); let c = try recoveryConfirmation(r); var context = recoveryContext(r)
        context.betaInvitationVerified = false
        var state = recoveryState(); var ledger = SupportFixtureLedger()
        try refuses(.ownershipUnproven) { _ = try RecoveryFixtureModel.commit(r, confirmation: c, context: context,
            supportContext: fixtureContext(c), now: now, state: &state, ledger: &ledger) }
    }
    check("current case cannot reuse notice or proof after changed new address") {
        let v = try vector("recovery-case")
        let altered = replace(Data(v.bytes.utf8), String(repeating: "6", count: 64), String(repeating: "8", count: 64))
        let old = try recoveryCase(); let changed = try RecoveryCase.parse(altered, expectedDigest: digest(altered, domain: "im.patched.support.recovery.v1"))
        let c = try recoveryConfirmation(changed); var context = recoveryContext(old)
        context.caseDigest = changed.digest
        var state = recoveryState(); let before = state; var ledger = SupportFixtureLedger()
        // The old possession also binds the old digest and must be renewed.
        try refuses(.ownershipUnproven) { _ = try RecoveryFixtureModel.commit(changed, confirmation: c, context: context,
            supportContext: fixtureContext(c), now: now, state: &state, ledger: &ledger) }
        try expect(state == before, "Changed case cannot reuse older evidence")
    }
    for fault in [SupportFixtureFault.missingEffect, .missingDependent, .auditThrows, .auditNoRow, .unmatchedCompletion] {
        check("recovery rollback restores every session slot revision for \(fault)") {
            let r = try recoveryCase(); let c = try recoveryConfirmation(r)
            var state = recoveryState(); let before = state; var ledger = SupportFixtureLedger()
            try refuses(.rollback) { _ = try RecoveryFixtureModel.commit(r, confirmation: c, context: recoveryContext(r),
                supportContext: fixtureContext(c), now: now, state: &state, ledger: &ledger, fault: fault) }
            try expect(state == before && ledger == SupportFixtureLedger(), "No partial recovery survives")
        }
    }
    check("recovery omitted live activation refuses rather than only releasing listed slot") {
        let r = try recoveryCase(); let c = try recoveryConfirmation(r)
        var state = recoveryState(); state.activationRevisions[foreignID] = 1; state.occupiedSlots[2] = foreignID
        let before = state; var ledger = SupportFixtureLedger()
        let result = try RecoveryFixtureModel.commit(r, confirmation: c, context: recoveryContext(r),
            supportContext: fixtureContext(c), now: now, state: &state, ledger: &ledger)
        try expect(result == .targetChanged && state == before && ledger.effectCount == 0, "Omitted activation invalidates entire recovery")
    }
    for (name, old, new) in [
        ("empty recovery target set", "\"activations\":[{", "\"activations\":[],\"unexpected\":[{"),
        ("short case digest", "\"caseDigest\":\"", "\"caseDigest\":\"x"),
        ("missing recovery check", "\"possessionVerified\":true,", ""),
        ("false recovery check", "\"ownershipJudgement\":true", "\"ownershipJudgement\":false"),
        ("unknown recovery check", "\"sourceKind\":", "\"emailCode\":\"123456\",\"sourceKind\":")
    ] {
        check(name) { try refuses(.malformedDescriptor) { _ = try decoded(replace(descriptor(.changeAccountEmail), old, new)) } }
    }
    check("recovery duplicate activation IDs and slots refuse") {
        let b = try descriptor(.changeAccountEmail)
        let activation = String(decoding: try descriptor(), as: UTF8.self).components(separatedBy: "\"target\":")[1].components(separatedBy: ",\"evidence\":")[0]
        let duplicate = replace(b, "\"activations\":[\(activation)]", "\"activations\":[\(activation),\(activation)]")
        try expect(duplicate != b, "Duplicate fixture must change bytes")
        try refuses(.malformedDescriptor) { _ = try decoded(duplicate) }
        let other = activation.replacingOccurrences(of: activationID, with: foreignID)
        try refuses(.malformedDescriptor) { _ = try decoded(replace(b, "\"activations\":[\(activation)]", "\"activations\":[\(activation),\(other)]")) }
    }
    check("recovery exact five occupied targets releases every slot and session") {
        let r = try recoveryCase(); let single = try recoveryConfirmation(r)
        let original = String(decoding: try descriptor(), as: UTF8.self).components(separatedBy: "\"target\":")[1].components(separatedBy: ",\"evidence\":")[0]
        var targets: [String] = []; var state = recoveryState()
        for slot in 1...5 {
            let id = slot == 1 ? activationID : String(repeating: String(slot), count: 32)
            let t = original.replacingOccurrences(of: activationID, with: id)
                .replacingOccurrences(of: "\"slot\":1", with: "\"slot\":\(slot)")
            targets.append(t); state.activationRevisions[id] = 9; state.occupiedSlots[UInt64(slot)] = id
        }
        let b = replace(single.descriptorBytes, "\"activations\":[\(original)]", "\"activations\":[\(targets.joined(separator: ","))]")
        try expect(b.count <= 4096, "Five targets must fit the bounded descriptor")
        let c = try decoded(b); var ledger = SupportFixtureLedger()
        try expect(try RecoveryFixtureModel.commit(r, confirmation: c, context: recoveryContext(r),
            supportContext: fixtureContext(c), now: now, state: &state, ledger: &ledger) == .committed, "Five-target recovery")
        try expect(state.occupiedSlots.isEmpty && state.activationRevisions.count == 5 &&
                   state.activationRevisions.values.allSatisfy { $0 == 10 } && state.sessions.values.allSatisfy { !$0 },
                   "Every occupied activation revision and session changes together")
    }
    check("empty recovery activation list is refused") {
        let b = try descriptor(.changeAccountEmail)
        let original = String(decoding: try descriptor(), as: UTF8.self).components(separatedBy: "\"target\":")[1].components(separatedBy: ",\"evidence\":")[0]
        let empty = replace(b, "\"activations\":[\(original)]", "\"activations\":[]")
        try expect(empty != b, "Fixture must really omit every target")
        try refuses(.malformedDescriptor) { _ = try decoded(empty) }
    }
    let staleStates: [(String, (inout RecoveryFixtureState) -> Void)] = [
        ("account ID", { $0.accountID = foreignID }),
        ("account revision", { $0.accountRevision += 1 }),
        ("entitlement revision", { $0.entitlementRevision += 1 }),
        ("activation revision", { $0.activationRevisions[activationID] = 10 }),
        ("old email mapping", { $0.emailHMAC = String(repeating: "0", count: 64) })
    ]
    for (name, mutate) in staleStates {
        check("recovery stale \(name) cannot partially apply") {
            let r = try recoveryCase(); let c = try recoveryConfirmation(r)
            var state = recoveryState(); mutate(&state); let before = state; var ledger = SupportFixtureLedger()
            let result = try RecoveryFixtureModel.commit(r, confirmation: c, context: recoveryContext(r),
                supportContext: fixtureContext(c), now: now, state: &state, ledger: &ledger)
            try expect(result == .targetChanged && state == before && ledger.effectCount == 0, "Stale recovery is terminal without effects")
        }
    }
    check("recovery affects only exact household and preserves unrelated household byte values") {
        let r = try recoveryCase(); let c = try recoveryConfirmation(r)
        var other = recoveryState()
        other.accountID = foreignID; other.accountRevision = 41; other.entitlementRevision = 13
        other.emailHMAC = String(repeating: "9", count: 64)
        other.sessions = [String(repeating: "8", count: 32): true]
        other.activationRevisions = [foreignID: 27]; other.occupiedSlots = [4: foreignID]
        other.trialStart = 70; other.trialEnd = 90; other.betaInvitation = nil
        other.paidHistory = ["unrelated-original-paid-period"]
        var households = [account: recoveryState(), foreignID: other]
        let unrelatedBefore = households[foreignID]!
        var ledger = SupportFixtureLedger()
        // Inout is restricted to the exact selected account state, with its identity checked again.
        let result = try RecoveryFixtureModel.commit(r, confirmation: c, context: recoveryContext(r),
            supportContext: fixtureContext(c), now: now, state: &households[account]!, ledger: &ledger)
        try expect(result == .committed && households[account]!.occupiedSlots.isEmpty, "Target household recovered")
        try expect(households[foreignID] == unrelatedBefore, "Other household sessions, activations and all history unchanged")
    }
    check("historical maximum above newest hardEnd is retained") {
        let b = replace(try descriptor(), "\"maxGrantPermittedUntil\":1400", "\"maxGrantPermittedUntil\":2500")
        let c = try decoded(b)
        guard case .activation(let a) = c.target else { throw CheckFailure(description: "Typed activation") }
        try expect(a.maxGrantPermittedUntil == 2500 && a.cachedLease?.hardEnd == 1500, "Do not clamp older issued grant")
    }
}
