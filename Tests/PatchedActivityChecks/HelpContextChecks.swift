import Foundation
@_spi(Testing) import PatchedActivity

@MainActor func registerHelpContextChecks() {
    let draft = ActivityDraft(email: " Andy+日本語@example.invalid \r\n", message: "My unchanged message\n<b>literal</b>\r\n")
    check("setup: caller draft bytes survive independent Codable reconstruction", setup: true) {
        let encoder = JSONEncoder(); let decoded = try JSONDecoder().decode(ActivityDraft.self, from: encoder.encode(draft))
        try expect(Data(decoded.email.utf8) == Data(draft.email.utf8) && Data(decoded.message.utf8) == Data(draft.message.utf8), "Independent draft roundtrip changed user bytes")
    }
    check("help: one separate context preserves caller email and message bytes") {
        let result = try ActivityHelpContext.append(event: event(), revision: 1, report: nil, to: draft)
        try expect(result.email == draft.email && result.message == draft.message && result.contexts.count == 1,
                   "Context replaced caller draft")
        let block = result.contexts[0]
        try expect(block.eventID == eventID && block.attemptID == attemptID && block.revision == 1,
                   "Context bound to wrong failure")
        try expect(block.text.contains(eventID) && block.text.contains(attemptID) && block.text.contains("Failed") && block.text.contains("Verification failed") && block.text.contains("Synthetic fixture only"),
                   "Finite context labels/correlations missing")
    }
    check("help: identical event attempt revision appends exactly once") {
        let once = try ActivityHelpContext.append(event: event(), revision: 1, report: nil, to: draft)
        let twice = try ActivityHelpContext.append(event: event(), revision: 1, report: nil, to: once)
        try expect(once == twice && twice.contexts.count == 1, "Repeated selection duplicated context")
    }
    check("help: actual reconstructed owner and draft preserve append identity") {
        let (_, owner) = try loaded([event()])
        let once = try ActivityHelpContext.append(event: owner.snapshot.events[0], revision: 1, report: nil, to: draft)
        let store = try OwnedStore(); try store.seed(bytes(owner.snapshot.events, revision: 1))
        let draftURL = store.directory.appendingPathComponent("draft.json")
        try JSONEncoder().encode(once).write(to: draftURL, options: .withoutOverwriting)
        let reconstructedDraft = try JSONDecoder().decode(ActivityDraft.self, from: Data(contentsOf: draftURL))
        let fresh = fixtureOwner(store); try fresh.reload(now: epoch)
        let result = try ActivityHelpContext.append(event: fresh.snapshot.events[0], revision: 1, report: nil, to: reconstructedDraft)
        try expect(result == once && result.contexts.count == 1, "Fixture reconstruction duplicated context")
    }
    check("help: two failures remain distinct and edited caller text is untouched") {
        var once = try ActivityHelpContext.append(event: event(), revision: 1, report: nil, to: draft)
        once.message += "Edited after selection\n"; once.email = "new@example.invalid"
        let next = event(id: otherID, attempt: otherID, reason: .interrupted, sequence: 2)
        let result = try ActivityHelpContext.append(event: next, revision: 1, report: nil, to: once)
        try expect(result.contexts.count == 2 && result.contexts[0] == once.contexts[0] && result.message == once.message && result.email == once.email,
                   "Second failure replaced first context or draft")
    }
    check("help: different revision is distinct append identity") {
        let once = try ActivityHelpContext.append(event: event(), revision: 1, report: nil, to: draft)
        let next = try ActivityHelpContext.append(event: event(), revision: 2, report: nil, to: once)
        try expect(next.contexts.count == 2 && next.contexts.map(\.revision) == [1, 2], "Revision identity collapsed")
    }
    check("help: target display and version private text never enters automatic export") {
        let e = event(target: privateText, name: privateText, before: "/Users/private", after: "token=TOPSECRET",
                      beforeBuild: "profile=PRIVATE", afterBuild: "inventory=PRIVATE", run: runID, request: requestID,
                      transaction: transactionID, parent: otherID)
        let result = try ActivityHelpContext.append(event: e, revision: 1, report: nil, to: draft)
        let preview = try ActivityHelpContext.preview(result).joined(separator: "\n")
        for forbidden in ["/Users/", "secret-owner", "SECRET", "profile", "inventory", "opaque-target", "Fixture app"] {
            try expect(!preview.contains(forbidden), "Private non-allowlisted field leaked")
        }
        for id in [eventID, attemptID, runID, requestID, transactionID, otherID] {
            try expect(preview.contains(id), "Opaque canonical correlation omitted")
        }
        try expect(preview.utf8.count <= 2048 && result.email == draft.email && result.message == draft.message, "Context unbounded or draft changed")
    }
    for reason in ActivityReason.allCases {
        check("help: finite reason only \(reason.rawValue)") {
            let e = event(name: literalName, reason: reason)
            let result = try ActivityHelpContext.append(event: e, revision: 1, report: nil, to: draft)
            let preview = try ActivityHelpContext.preview(result).joined(separator: "\n")
            try expect(!preview.contains(literalName) && !preview.contains("<b>") && !preview.contains("**") && preview.utf8.count <= 2048,
                       "Arbitrary local text exported as reason")
        }
    }
    for state in ActivityReportState.allCases {
        check("report: matching independent fixture state \(state.rawValue)") {
            let report = ActivityReport(reportID: reportID, eventID: eventID, attemptID: attemptID, state: state)
            try expect(ActivityHelpContext.reportState(event: event(), report: report) == state, "Report state collapsed or invented")
            let result = try ActivityHelpContext.append(event: event(), revision: 1, report: report, to: draft)
            try expect(result.contexts.count == 1 && result.contexts[0].text.contains(state.rawValue.capitalized), "Report state missing from preview")
        }
    }
    for mismatch in ["missing", "report", "event", "attempt", "no event report"] {
        check("report: unknown or mismatch never becomes sent \(mismatch)") {
            let report: ActivityReport? = mismatch == "missing" ? nil : ActivityReport(
                reportID: mismatch == "report" ? otherID : reportID,
                eventID: mismatch == "event" ? otherID : eventID,
                attemptID: mismatch == "attempt" ? otherID : attemptID, state: .sent)
            let e = event(report: mismatch == "no event report" ? nil : reportID)
            try expect(ActivityHelpContext.reportState(event: e, report: report) == .missing, "Mismatched receipt promoted to sent")
            let result = try ActivityHelpContext.append(event: e, revision: 1, report: report, to: draft)
            try expect(result.contexts[0].text.contains("Missing") && !result.contexts[0].text.contains("Sent"), "Preview asserted false delivery")
        }
    }
    check("help: immutable selected event remains selected after newer failure") {
        let selected = event(); let latest = event(id: otherID, attempt: otherID, reason: .interrupted, sequence: 2)
        let (_, owner) = try loaded([selected, latest])
        let result = try ActivityHelpContext.append(event: selected, revision: 1, report: nil, to: draft)
        try expect(owner.snapshot.events.count == 2 && result.contexts[0].eventID == eventID &&
                   !result.contexts[0].text.contains(otherID), "Global latest error replaced selected context")
    }
    for text in [privateText, "<script>token=SECRET</script>", "status: Sent\n/Users/private", "x\u{0}y", String(repeating: "x", count: 4096)] {
        check("help: untrusted reconstructed context preview refuses raw text \(text.utf8.count)") {
            let malicious = ActivityDraft(email: draft.email, message: draft.message,
                contexts: [ActivityContextBlock(eventID: eventID, attemptID: attemptID, revision: 1, text: text)])
            try refused { _ = try ActivityHelpContext.preview(malicious) }
        }
    }
    check("help: invalid correlation refuses context rather than exporting arbitrary ID") {
        try refused { _ = try ActivityHelpContext.append(event: event(id: privateText), revision: 1, report: nil, to: draft) }
    }
    check("help: conflicting context identity refuses rather than overwriting") {
        let old = ActivityDraft(email: draft.email, message: draft.message,
            contexts: [ActivityContextBlock(eventID: eventID, attemptID: attemptID, revision: 1, text: privateText)])
        try refused { _ = try ActivityHelpContext.append(event: event(), revision: 1, report: nil, to: old) }
    }
    check("draft: exact email/message UTF8 limits accepted and source serialization reconstructs") {
        let bounded = ActivityDraft(email: String(repeating: "é", count: 160), message: String(repeating: "é", count: 8192))
        let next = try ActivityHelpContext.append(event: event(), revision: 1, report: nil, to: bounded)
        let encoded = try ActivityHelpContext.encodeDraft(next)
        let decoded = try ActivityHelpContext.decodeDraft(encoded)
        try expect(decoded == next && next.email == bounded.email && next.message == bounded.message, "Boundary draft altered or serialization lost blocks")
    }
    for field in ["email", "message"] {
        check("draft: overlimit refuses append and serialization without truncation " + field) {
            let email = field == "email" ? String(repeating: "é", count: 161) : draft.email
            let message = field == "message" ? String(repeating: "é", count: 8193) : draft.message
            let over = ActivityDraft(email: email, message: message)
            let retained = try JSONEncoder().encode(over)
            try refused { _ = try ActivityHelpContext.append(event: event(), revision: 1, report: nil, to: over) }
            try refused { _ = try ActivityHelpContext.encodeDraft(over) }
            try refused { _ = try ActivityHelpContext.decodeDraft(retained) }
            try expect(over.email == email && over.message == message && over.contexts.isEmpty, "Overlimit input changed")
        }
    }
    check("draft: exact 256 contexts retained; distinct 257th refuses") {
        var filled = draft
        for index in 1...256 {
            let id = String(format: "BBBBBBBB-0000-4000-8000-%012d", index)
            filled = try ActivityHelpContext.append(event: event(id: id, attempt: id, sequence: UInt64(index)), revision: 1, report: nil, to: filled)
        }
        try expect(filled.contexts.count == 256, "Bounded context count collapsed")
        let encoded = try ActivityHelpContext.encodeDraft(filled)
        try expect(try ActivityHelpContext.decodeDraft(encoded) == filled, "Full bounded draft not reconstructed")
        let same = try ActivityHelpContext.append(event: event(id: eventID, attempt: eventID), revision: 1, report: nil, to: filled)
        try expect(same == filled, "Idempotent append at quota mutated draft")
        let extraID = "BBBBBBBB-0000-4000-8000-000000000257"
        try refused { _ = try ActivityHelpContext.append(event: event(id: extraID, attempt: extraID), revision: 1, report: nil, to: filled) }
        try expect(try ActivityHelpContext.encodeDraft(filled) == encoded, "Refused append truncated old context")
    }
    check("draft: 257 reconstructed contexts refuse serialization/readback") {
        let block = ActivityContextBlock(eventID: eventID, attemptID: attemptID, revision: 1, text: "Failed")
        let over = ActivityDraft(email: draft.email, message: draft.message, contexts: Array(repeating: block, count: 257))
        try refused { _ = try ActivityHelpContext.encodeDraft(over) }
        try refused { _ = try ActivityHelpContext.decodeDraft(JSONEncoder().encode(over)) }
        try expect(over.contexts.count == 257 && over.email == draft.email && over.message == draft.message, "Oversized draft altered")
    }
    check("draft: context revision overflow refuses with original bytes preserved") {
        // Compare the canonical wire bytes, whose key order is stable.
        let retained = try ActivityHelpContext.encodeDraft(draft)
        try refused { _ = try ActivityHelpContext.append(event: event(), revision: UInt64.max, report: nil, to: draft) }
        try expect(try ActivityHelpContext.encodeDraft(draft) == retained, "Overflow altered caller draft")
    }
    check("navigation/view/reconstruction: read-only paths issue zero fixture writes") {
        let (store, owner) = try loaded([event()]); let before = try store.actual()
        for _ in 0..<3 {
            try owner.reload(now: epoch)
            _ = ActivityPresentation.make(owner.snapshot)
            _ = try ActivityHelpContext.append(event: event(), revision: 1, report: nil, to: draft)
            _ = ActivityHelpContext.reportState(event: event(), report: nil)
        }
        let fresh = fixtureOwner(store); try fresh.reload(now: epoch)
        let after = try store.actual()
        try expect(before == after && store.writes == 0, "Reading/context creation wrote history")
        // There is structurally no transport, send, enqueue, mail, app or installation API.
        // This fixture does not claim to instrument a future native Help integration.
    }
}
