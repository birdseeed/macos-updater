import Foundation
@_spi(Testing) import PatchedLicenceSupport

/// Additive coverage after the parent released Phase B. Frozen assertion bodies stay unchanged.
@MainActor func registerHardeningChecks() {
    for note in ["رمز ١٢٣٤٥٦", "番号 １２３４５６", "mixed 1٢３4٥６"] {
        check("six Unicode decimal digits refused \(noteDigest(note).prefix(8))") {
            try refuses(.malformedDescriptor) { _ = try decoded(withNote(descriptor(), note)) }
        }
    }
    check("five Unicode decimal digits remain ordinary printable text") {
        let note = "Case ١٢٣٤٥"
        try expect(try decoded(withNote(descriptor(), note)).reasonNote == note, "Five digits are allowed")
    }
    for escaped in ["\\uD800", "\\uDC00", "\\uD800\\u0041", "\\u0000", "\\x41", "\\uZZZZ"] {
        check("malformed string escape rejected \(escaped)") {
            let b = replace(try descriptor(), "Reviewed <b>claim</b> café", escaped)
            try refuses(.malformedDescriptor) { _ = try decoded(b) }
        }
    }
    check("valid escaped supplementary scalar keeps exact note digest") {
        let note = "Reviewed 😀"
        let raw = try withNote(descriptor(), note)
        let escaped = replace(raw, "😀", "\\ud83d\\ude00")
        let c = try decoded(escaped)
        try expect(c.reasonNote == note && c.reasonNoteSHA256 == noteDigest(note), "Surrogate pair decodes exactly")
    }
    for (name, old, new) in [
        ("missing last granting lease record", "\"cachedLease\":{\"state\":\"paid\",\"issuedAt\":800,\"permittedUntil\":1200,\"hardEnd\":1500},", ""),
        ("never-granted null with historical maximum", "\"cachedLease\":{\"state\":\"paid\",\"issuedAt\":800,\"permittedUntil\":1200,\"hardEnd\":1500}", "\"cachedLease\":null"),
        ("future issued grant", "\"issuedAt\":800", "\"issuedAt\":300001"),
        ("unsafe historical maximum", "\"maxGrantPermittedUntil\":1400", "\"maxGrantPermittedUntil\":9007199254740992"),
        ("unbounded historical maximum string", "\"maxGrantPermittedUntil\":1400", "\"maxGrantPermittedUntil\":\"unknown\""),
        ("malicious masked markup", "o***@example.invalid", "<***@example.invalid")
    ] {
        check(name) { try refuses(.malformedDescriptor) { _ = try decoded(replace(descriptor(), old, new)) } }
    }
    check("terminal row binds request ID as well as operator and digest") {
        let c = try decoded(descriptor()); var ledger = SupportFixtureLedger()
        _ = try SupportFixtureModel.commit(c, context: fixtureContext(c), now: now, ledger: &ledger)
        ledger.terminalRequestID = foreignID
        let before = ledger
        try refuses(.invalidContext) { _ = try SupportFixtureModel.commit(c, context: fixtureContext(c), now: now, ledger: &ledger) }
        try expect(ledger == before, "Mismatched terminal request cannot be overwritten")
    }
    check("different valid descriptor cannot reuse a terminal request ledger") {
        let c = try decoded(descriptor()); var ledger = SupportFixtureLedger()
        _ = try SupportFixtureModel.commit(c, context: fixtureContext(c), now: now, ledger: &ledger)
        let changed = try decoded(withNote(descriptor(), "Another reviewed note")); let before = ledger
        try refuses(.invalidContext) { _ = try SupportFixtureModel.commit(changed, context: fixtureContext(changed), now: now, ledger: &ledger) }
        try expect(ledger == before, "A different digest cannot read or replace the stored result")
    }
    check("terminal committed row without dependent record refuses") {
        let c = try decoded(descriptor()); var ledger = SupportFixtureLedger()
        _ = try SupportFixtureModel.commit(c, context: fixtureContext(c), now: now, ledger: &ledger)
        ledger.dependentCount = 0
        try refuses(.rollback) { _ = try SupportFixtureModel.commit(c, context: fixtureContext(c), now: now, ledger: &ledger) }
    }
    for (reference, value) in [("sourceReference", "1"), ("possessionReference", "2"),
                                ("newEmailReference", "3"), ("ownershipReference", "4")] {
        check("recovery confirmation cannot substitute \(reference)") {
            let r = try recoveryCase()
            let original = try recoveryConfirmation(r)
            let b = replace(original.descriptorBytes, "\"\(reference)\":\"\(String(repeating: value, count: 32))\"",
                            "\"\(reference)\":\"\(foreignID)\"")
            let c = try decoded(b)
            var state = recoveryState(); let before = state; var ledger = SupportFixtureLedger()
            try refuses(.recoveryHeld) { _ = try RecoveryFixtureModel.commit(r, confirmation: c, context: recoveryContext(r),
                supportContext: fixtureContext(c), now: now, state: &state, ledger: &ledger) }
            try expect(state == before && ledger == SupportFixtureLedger(), "Changed evidence creates no partial recovery")
        }
    }
    check("case and confirmation account revisions must be identical") {
        let r = try recoveryCase(); let original = try recoveryConfirmation(r)
        let c = try decoded(replace(original.descriptorBytes, "\"accountRevision\":7", "\"accountRevision\":8"))
        var state = recoveryState(); var ledger = SupportFixtureLedger()
        try refuses(.recoveryHeld) { _ = try RecoveryFixtureModel.commit(r, confirmation: c, context: recoveryContext(r),
            supportContext: fixtureContext(c), now: now, state: &state, ledger: &ledger) }
    }
    check("recovery duplicate identity across distinct slots refuses") {
        let base = try descriptor(.changeAccountEmail)
        let activation = String(decoding: try descriptor(), as: UTF8.self).components(separatedBy: "\"target\":")[1].components(separatedBy: ",\"evidence\":")[0]
        let nextSlot = activation.replacingOccurrences(of: "\"slot\":1", with: "\"slot\":2")
        let b = replace(base, "\"activations\":[\(activation)]", "\"activations\":[\(activation),\(nextSlot)]")
        try refuses(.malformedDescriptor) { _ = try decoded(b) }
    }
    check("recovery changed slot occupant is terminal without any mutation") {
        let r = try recoveryCase(); let c = try recoveryConfirmation(r)
        var state = recoveryState(); state.occupiedSlots = [1: foreignID]; state.activationRevisions[foreignID] = 9
        let before = state; var ledger = SupportFixtureLedger()
        let result = try RecoveryFixtureModel.commit(r, confirmation: c, context: recoveryContext(r),
            supportContext: fixtureContext(c), now: now, state: &state, ledger: &ledger)
        try expect(result == .targetChanged && state == before && ledger.effectCount == 0, "Cannot release a replacement occupant")
    }
    check("recovery lost result preserves atomic effects and reads terminal state once") {
        let r = try recoveryCase(); let c = try recoveryConfirmation(r)
        var state = recoveryState(); var ledger = SupportFixtureLedger()
        try refuses(.unknownOutcome) { _ = try RecoveryFixtureModel.commit(r, confirmation: c, context: recoveryContext(r),
            supportContext: fixtureContext(c), now: now, state: &state, ledger: &ledger, fault: .lostReadback) }
        try expect(state.occupiedSlots.isEmpty && state.accountRevision == 8 && ledger.outcome == .committed,
                   "Lost response does not erase committed recovery")
        let after = state; let terminal = ledger
        let result = try RecoveryFixtureModel.commit(r, confirmation: c, context: recoveryContext(r),
            supportContext: fixtureContext(c), now: 400_000, state: &state, ledger: &ledger)
        try expect(result == .committed && state == after && ledger == terminal, "Expired proof does not repeat a terminal effect")
    }
    check("recovery revision arithmetic overflow leaves complete state and claim unchanged") {
        let v = try vector("recovery-case")
        let bytes = replace(Data(v.bytes.utf8), "\"accountRevision\":7", "\"accountRevision\":\(maxExact)")
        let r = try RecoveryCase.parse(bytes, expectedDigest: digest(bytes, domain: "im.patched.support.recovery.v1"))
        var b = replace(try descriptor(.changeAccountEmail), v.sha256, r.digest)
        b = replace(b, "\"accountRevision\":7", "\"accountRevision\":\(maxExact)")
        let c = try decoded(b); var context = fixtureContext(c)
        context.accountRevision = maxExact; context.targetRevision = maxExact
        var state = recoveryState(); state.accountRevision = maxExact
        let before = state; var ledger = SupportFixtureLedger()
        try refuses(.rollback) { _ = try RecoveryFixtureModel.commit(r, confirmation: c, context: recoveryContext(r),
            supportContext: context, now: now, state: &state, ledger: &ledger) }
        try expect(state == before && ledger == SupportFixtureLedger(), "Revision overflow cannot reset to zero")
    }
    check("recovery new email proof clock cannot exceed exact integer range") {
        let r = try recoveryCase(); let c = try recoveryConfirmation(r); var context = recoveryContext(r)
        context.proofExpiresAt = maxExact + 1
        var state = recoveryState(); var ledger = SupportFixtureLedger()
        try refuses(.recoveryHeld) { _ = try RecoveryFixtureModel.commit(r, confirmation: c, context: context,
            supportContext: fixtureContext(c), now: now, state: &state, ledger: &ledger) }
    }
    check("provider intents distinguish both refund and renewal dependencies") {
        let c = try decoded(descriptor(.initiateRefund)); var ledger = SupportFixtureLedger()
        _ = try SupportFixtureModel.commit(c, context: fixtureContext(c), now: now, ledger: &ledger)
        try expect(ledger.dependentCount == 2, "Refund and independent renewal stop have separate dependent records")
        let audit = ledger.audit.joined()
        try expect(audit.contains("sub_fixture") && audit.contains("txn_fixture") && audit.contains(c.reasonNoteSHA256),
                   "Audit binds opaque subscription, transaction and exact note digest")
    }
}
