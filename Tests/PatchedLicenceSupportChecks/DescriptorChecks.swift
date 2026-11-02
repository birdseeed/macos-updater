import Foundation
@_spi(Testing) import PatchedLicenceSupport
@MainActor func registerDescriptorChecks() {
    check("six actions are closed and cannot express overrides") {
        try expect(Set(SupportAction.allCases.map(\.rawValue)) == Set(["deactivateActivation", "resendSignInCode",
            "reconcileProviderState", "initiateCancellation", "initiateRefund", "changeAccountEmail"]), "Closed action set")
        for bad in ["grantPaid", "resetTrial", "overrideSlots", "editPeriod", "clearHold", "mintLease", "mintKey"] {
            try expect(SupportAction(rawValue: bad) == nil, "Forbidden action cannot be represented")
        }
    }
    for action in SupportAction.allCases {
        check("independent stable vector and exact display for \(action.rawValue)") {
            let v = try vector(action.rawValue); let b = Data(v.bytes.utf8)
            try expect(digest(b) == v.sha256, "Independent SHA256 fixture disagrees")
            let c = try decoded(b, expected: v.sha256)
            try expect(c.descriptorBytes == b && c.action == action, "No reserialization or action loss")
            let display = try SupportPresentation.confirmation(c)
            let expected = flattened(try JSONSerialization.jsonObject(with: b))
            let actual = Dictionary(uniqueKeysWithValues: display.fields.map { ($0.path, $0.text) })
            // Full leaf display snapshot proves every value is derived from descriptor bytes.
            try expect(actual == expected, "Display does not exactly represent original bytes")
            try expect(display.consequenceWords.count == c.consequences.count &&
                       display.consequenceWords.allSatisfy { !$0.isEmpty }, "Compiled consequence words missing")
            try expect(actual["reasonNote"] == "Reviewed <b>claim</b> café", "Note must stay literal text")
        }
    }
    let mutations: [(String, String, String)] = [
        ("unknown action", "deactivateActivation", "grantPaid"),
        ("unknown member", "\"schemaVersion\":1,", "\"extra\":0,\"schemaVersion\":1,"),
        ("missing member", "\"schemaVersion\":1,", ""),
        ("duplicate member", "\"schemaVersion\":1,", "\"schemaVersion\":1,\"schemaVersion\":1,"),
        ("escaped duplicate member", "\"schemaVersion\":1,", "\"schemaVersion\":1,\"schema\\u0056ersion\":1,"),
        ("reordered member", "\"accountRevision\":7,\"entitlementRevision\":3", "\"entitlementRevision\":3,\"accountRevision\":7"),
        ("nested reordered member", "\"slot\":1,\"activationRevision\":9", "\"activationRevision\":9,\"slot\":1"),
        ("nested unknown member", "\"slot\":1", "\"untrustedLabel\":\"Mac\",\"slot\":1"),
        ("nested duplicate", "\"slot\":1", "\"slot\":1,\"slot\":1"),
        ("numeric boolean", "\"accountRevision\":7", "\"accountRevision\":true"),
        ("negative number", "\"accountRevision\":7", "\"accountRevision\":-7"),
        ("float number", "\"accountRevision\":7", "\"accountRevision\":7.0"),
        ("exponent number", "\"accountRevision\":7", "\"accountRevision\":7e0"),
        ("leading zero", "\"accountRevision\":7", "\"accountRevision\":07"),
        ("numeric string", "\"accountRevision\":7", "\"accountRevision\":\"7\""),
        ("zero revision", "\"accountRevision\":7", "\"accountRevision\":0"),
        ("unsafe integer", "\"accountRevision\":7", "\"accountRevision\":9007199254740992"),
        ("schema mismatch", "\"schemaVersion\":1", "\"schemaVersion\":2"),
        ("uppercase ID", account, account.uppercased()),
        ("short ID", account, "aaaa"),
        ("email as identity", account, "person@example.invalid"),
        ("invalid nonce", "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=", "AAE="),
        ("noncanonical nonce pad bits", "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=", "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh9="),
        ("unmasked email", "o***@example.invalid", "owner@example.invalid"),
        ("slot zero", "\"slot\":1", "\"slot\":0"),
        ("slot six", "\"slot\":1", "\"slot\":6"),
        ("grant reversed bounds", "\"permittedUntil\":1200", "\"permittedUntil\":799"),
        ("grant after hard end", "\"permittedUntil\":1200", "\"permittedUntil\":1501"),
        ("maximum below last grant", "\"maxGrantPermittedUntil\":1400", "\"maxGrantPermittedUntil\":1199"),
        ("non-granting cached state", "\"state\":\"paid\"", "\"state\":\"revoked\""),
        ("missing history maximum", ",\"maxGrantPermittedUntil\":1400", ""),
        ("unknown history", "\"cachedLease\":{", "\"historyUnknown\":true,\"cachedLease\":{"),
        ("last refresh before creation", "\"lastRefreshAt\":900", "\"lastRefreshAt\":99"),
        ("future creation", "\"createdAt\":100", "\"createdAt\":300001"),
        ("null maximum despite known grant", "\"maxGrantPermittedUntil\":1400", "\"maxGrantPermittedUntil\":null"),
        ("wrong consequence", "releaseActivation", "stopRenewalKeepPaidThrough"),
        ("extra consequence", "[\"releaseActivation\"]", "[\"releaseActivation\",\"releaseActivation\"]"),
        ("unknown reason code", "customerRequest", "operatorOverride"),
        ("wrong note digest", "\"reasonNoteSHA256\":\"", "\"reasonNoteSHA256\":\"0"),
        ("wrong expiry span", "\"expiresAt\":300300", "\"expiresAt\":300301"),
        ("nesting too deep", "\"evidence\":{}", "\"evidence\":{\"a\":{\"b\":{\"c\":{\"d\":{\"e\":0}}}}}")
    ]
    for (name, old, new) in mutations {
        check("strict descriptor rejects \(name)") {
            let b = try descriptor(); let changed = replace(b, old, new)
            try expect(changed != b, "Mutation must alter bytes")
            try refuses(.malformedDescriptor) { _ = try decoded(changed) }
        }
    }
    let wireMutations: [(String, (Data) -> Data)] = [
        ("BOM", { (b: Data) in Data([0xef,0xbb,0xbf]) + b }),
        ("NUL", { (b: Data) in b + Data([0]) }),
        ("invalid UTF8", { (b: Data) in b + Data([0xc0,0xaf]) }),
        ("leading whitespace", { (b: Data) in Data([32]) + b }),
        ("trailing whitespace", { (b: Data) in b + Data([10]) }),
        ("trailing object", { (b: Data) in b + Data("{}".utf8) }),
        ("4097 byte input", { (_: Data) in Data(repeating: 32, count: 4097) }),
        ("unterminated string", { (_: Data) in Data("{\"schemaVersion\":\"".utf8) })
    ]
    for (name, mutate) in wireMutations {
        check("wire rejects \(name)") { try refuses(.malformedDescriptor) { _ = try decoded(mutate(descriptor())) } }
    }
    for note in [String(repeating: "x", count: 201), String(repeating: "é", count: 101),
                 "contact@host", "code 123456", "line\nbreak", "tab\tvalue", "\u{0}", "\u{7f}",
                 "\u{85}", "\u{2028}", "\u{202e}", "\u{2066}", "cafe\u{301}"] {
        check("unsafe note rejected \(noteDigest(note).prefix(8))") {
            try refuses(.malformedDescriptor) { _ = try decoded(withNote(descriptor(), note)) }
        }
    }
    for note in ["", String(repeating: "x", count: 200), String(repeating: "é", count: 100), "<b>literal</b> 12345"] {
        check("valid printable NFC note \(note.utf8.count) bytes") {
            let c = try decoded(withNote(descriptor(), note))
            try expect(Array(c.reasonNote.utf8) == Array(note.utf8), "Decoded exact UTF8 note")
        }
    }
    check("escaped Unicode uses decoded note digest but original descriptor digest") {
        let b = replace(try descriptor(), "café", "caf\\u00e9")
        let c = try decoded(b)
        try expect(c.reasonNote == "Reviewed <b>claim</b> café" && c.digest == digest(b), "Exact wire binding")
        try refuses(.digestMismatch) { _ = try decoded(b, expected: digest(descriptor())) }
    }
    check("known never granted null pair accepted") {
        let b = replace(try descriptor(), "\"cachedLease\":{\"state\":\"paid\",\"issuedAt\":800,\"permittedUntil\":1200,\"hardEnd\":1500},\"maxGrantPermittedUntil\":1400", "\"cachedLease\":null,\"maxGrantPermittedUntil\":null")
        let c = try decoded(b)
        guard case .activation(let a) = c.target else { throw CheckFailure(description: "Typed activation") }
        try expect(a.cachedLease == nil && a.maxGrantPermittedUntil == nil, "Known never-granted history")
    }
    check("maximum across older lost-response grants is displayed") {
        let c = try decoded(descriptor())
        guard case .activation(let a) = c.target else { throw CheckFailure(description: "Typed activation") }
        try expect(a.cachedLease?.permittedUntil == 1200 && a.maxGrantPermittedUntil == 1400, "Keep actual and maximum distinct")
    }
    for action in [.initiateCancellation, .reconcileProviderState, .initiateRefund] as [SupportAction] {
        for (name, old, new) in [("foreign field", "\"subscriptionID\":", "\"code\":\"123456\",\"subscriptionID\":"),
                                 ("long provider ref", "sub_fixture", String(repeating: "s", count: 129)),
                                 ("unsafe provider ref", "sub_fixture", "sub@example.invalid"),
                                 ("reversed interval", "\"currentPeriodEnd\":2000", "\"currentPeriodEnd\":99")] {
            check("\(action) rejects \(name)") {
                try refuses(.malformedDescriptor) { _ = try decoded(replace(descriptor(action), old, new)) }
            }
        }
    }
    for (name, old, new) in [
        ("missing refund renewal-stop consequence", ",\"stopRenewalSeparately\"", ""),
        ("reordered refund consequences", "\"refundIntervalOnApproval\",\"stopRenewalSeparately\"", "\"stopRenewalSeparately\",\"refundIntervalOnApproval\""),
        ("false refund eligibility", "\"firstPurchase\":true", "\"firstPurchase\":false"),
        ("missing refund evidence", "\"withinThirtyDays\":true,", ""),
        ("refund wrong interval", "\"periodEnd\":2000", "\"periodEnd\":99")
    ] {
        check(name) { try refuses(.malformedDescriptor) { _ = try decoded(replace(descriptor(.initiateRefund), old, new)) } }
    }
    check("refund preserves distinct transaction interval") {
        let c = try decoded(replace(descriptor(.initiateRefund), "\"periodStart\":100,\"periodEnd\":2000", "\"periodStart\":50,\"periodEnd\":90"))
        guard case .provider(let p) = c.target else { throw CheckFailure(description: "Typed provider target") }
        try expect(p.periodStart == 50 && p.periodEnd == 90 && p.currentPeriodEnd == 2000, "Transaction is not current interval")
    }
    check("confirmation expires exclusively at plus 300") {
        let b = try descriptor()
        _ = try decoded(b, at: 300_299)
        try refuses(.expired) { _ = try decoded(b, at: 300_300) }
        try refuses(.expired) { _ = try decoded(b, at: 299_999) }
    }
    check("clock outside exact integer range refuses") {
        try refuses(.expired) { _ = try decoded(descriptor(), at: maxExact + 1) }
    }
    check("expiry addition cannot overflow exact integer range") {
        let b = replace(replace(try descriptor(), "\"preparedAt\":300000", "\"preparedAt\":9007199254740792"),
                        "\"expiresAt\":300300", "\"expiresAt\":9007199254740991")
        try refuses(.malformedDescriptor) { _ = try decoded(b, at: maxExact - 199) }
    }
    check("wrong digest and wrong domain refuse") {
        let b = try descriptor()
        try refuses(.digestMismatch) { _ = try decoded(b, expected: String(repeating: "0", count: 64)) }
        try refuses(.digestMismatch) { _ = try decoded(b, expected: digest(b, domain: "im.patched.support.recovery.v1")) }
    }
    check("foreign preparing operator refuses") {
        try refuses(.foreignOperator) { _ = try decoded(descriptor(), operatorID: foreignID) }
    }
}
