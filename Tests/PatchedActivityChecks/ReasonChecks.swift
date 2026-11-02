import Foundation
import PatchedActivity

@MainActor func registerReasonChecks() {
    // Expected copy is an independent acceptance oracle, not derived from enum raw values.
    let specimens: [(ActivityReason, String)] = [
        (.none, "None"),
        (.verificationFailed, "Verification failed"),
        (.runningApplication, "Running application"),
        (.userSkipped, "User skipped"),
        (.unavailableReadback, "Unavailable readback"),
        (.interrupted, "Interrupted"),
        (.recoveryRequired, "Recovery required"),
        (.unknown, "Unknown")
    ]
    for (reason, expectedLabel) in specimens {
        check("plain Activity reason is visible: \(expectedLabel)") {
            let event = ActivityEvent(
                eventID: "A1000000-0000-4000-8000-000000000001",
                attemptID: "A2000000-0000-4000-8000-000000000001",
                targetKey: "synthetic.reason.fixture", appName: "Reason fixture",
                origin: .manualIndividual, status: .failed, reason: reason,
                sequence: 1, observedAt: 100, resolvedAt: 101,
                beforeVersion: "1.0", afterVersion: "1.1", beforeBuild: "10", afterBuild: "11")
            let presentation = ActivityPresentation.make(ActivitySnapshot(
                available: true, revision: 1, events: [event], ageAvailable: true))
            try expect(presentation.provenance == "Synthetic fixture only",
                       "Reason presentation lost its synthetic provenance")
            try expect(presentation.rows.count == 1,
                       "Reason fixture must produce exactly one visible row")
            guard let row = presentation.rows.first else { return }
            try expect(row.text.contains("Reason: " + expectedLabel),
                       "Visible row omitted the plain reason: " + expectedLabel)
            try expect(row.text.components(separatedBy: "Reason: ").count == 2,
                       "Visible row must have one distinct reason field")
            for (_, otherLabel) in specimens where otherLabel != expectedLabel {
                try expect(!row.text.contains("Reason: " + otherLabel),
                           "Visible row substituted or combined another reason: " + otherLabel)
            }
        }
    }
    check("unavailable Activity snapshot conceals even synthetic reason rows") {
        let event = ActivityEvent(
            eventID: "A1000000-0000-4000-8000-000000000001",
            attemptID: "A2000000-0000-4000-8000-000000000001",
            targetKey: "synthetic.reason.fixture", appName: "Reason fixture",
            origin: .manualIndividual, status: .failed, reason: .verificationFailed,
            sequence: 1)
        let presentation = ActivityPresentation.make(ActivitySnapshot(
            available: false, revision: 1, events: [event]))
        try expect(presentation.headline == "Activity unavailable",
                   "Unavailable reason snapshot lost its unavailable state")
        try expect(presentation.provenance == "Synthetic fixture only",
                   "Unavailable reason snapshot lost its synthetic provenance")
        try expect(presentation.rows.isEmpty,
                   "Unavailable snapshot exposed reason rows")
    }
}
