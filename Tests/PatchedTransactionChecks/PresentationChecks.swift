import Foundation
import PatchedCore

let notice = "Fixture preview. No installed app is checked or changed."
let fixtureTarget = "/fixture/Applications/Firefox.app"
func rows(_ catalogue: String, _ bytes: String, _ closed: String) -> [UpdateCheckRow] {
    [UpdateCheckRow(title: "Catalogue signature", status: catalogue), UpdateCheckRow(title: "Staged bytes", status: bytes),
     UpdateCheckRow(title: "macOS signature and notarisation", status: "Not run in this fixture preview"),
     UpdateCheckRow(title: "App closed", status: closed)]
}
/// Candidate, both fixture checks passed, app closed and an approved fixture target: the only enabled state.
func ready(_ edit: (inout UpdateDisplayInput) -> Void = { _ in }) -> UpdateDisplayInput {
    var input = UpdateDisplayInput(appName: "Firefox")
    input.installedVersion = "157.0"; input.candidateVersion = "157.0.1"; input.checkedAt = 1_800_000_000
    input.catalogueCheck = .passed; input.artifactCheck = .passed; input.applicationOpen = false
    input.approvedFixtureTarget = fixtureTarget
    edit(&input); return input
}
func expectPresentation(_ input: UpdateDisplayInput, heading: String = "Firefox 157.0.1", installed: String = "Installed: 157.0",
                        checked: String = "Checked: 2027-01-15 08:00 UTC", checks: [UpdateCheckRow], refusal: String? = nil,
                        deferral: String? = nil, enabled: Bool, note: String) throws {
    let actual = UpdatePresentation.make(input)
    try expect(actual.previewNotice == notice, "Preview status missing: \(actual.previewNotice)")
    try expect(actual.heading == heading && actual.installedLine == installed && actual.checkedLine == checked,
               "Candidate, version or time differs: \(actual.heading) / \(actual.installedLine) / \(actual.checkedLine)")
    try expect(actual.checks == checks, "Check rows differ: \(actual.checks)")
    try expect(actual.refusalLine == refusal && actual.deferralLine == deferral, "Refusal or deferral differs: \(String(describing: actual.refusalLine)) / \(String(describing: actual.deferralLine))")
    try expect(actual.actionTitle == "Update Firefox" && actual.actionEnabled == enabled && actual.actionNote == note,
               "Manual action differs: \(actual.actionTitle) enabled=\(actual.actionEnabled) note=\(actual.actionNote)")
    try expect(UpdatePresentation.make(input) == actual, "Presentation is not a pure function of its input")
}

@MainActor func registerPresentationChecks() {
    check("presentation: default state has no candidate, no approved target and a disabled manual action") {
        try expectPresentation(UpdateDisplayInput(appName: "Firefox"), heading: "No update candidate", installed: "Installed: unknown",
                               checked: "Checked: never", checks: rows("Not run", "Not run", "Not checked"), enabled: false, note: "No update candidate.")
    }
    check("presentation: verified closed fixture candidate shows version, time and checks and enables only the manual action") {
        try expectPresentation(ready(), checks: rows("Passed", "Passed", "Closed"), enabled: true,
                               note: "Fixture target: \(fixtureTarget). Runs only when you choose Update.")
    }
    for (name, edit, catalogue, bytes) in [
        ("catalogue not run", { (i: inout UpdateDisplayInput) in i.catalogueCheck = .notRun }, "Not run", "Passed"),
        ("catalogue refused", { (i: inout UpdateDisplayInput) in i.catalogueCheck = .refused("invalidSignature") }, "Refused: invalidSignature", "Passed"),
        ("staged bytes not run", { (i: inout UpdateDisplayInput) in i.artifactCheck = .notRun }, "Passed", "Not run"),
        ("staged bytes refused", { (i: inout UpdateDisplayInput) in i.artifactCheck = .refused("digestMismatch") }, "Passed", "Refused: digestMismatch")] {
        check("presentation: \(name) disables the action") {
            try expectPresentation(ready(edit), checks: rows(catalogue, bytes, "Closed"), enabled: false, note: "Checks have not passed.")
        }
    }
    check("presentation: an open app disables the action and is never quit") {
        try expectPresentation(ready { $0.applicationOpen = true }, checks: rows("Passed", "Passed", "Open. Patched will not quit it"),
                               enabled: false, note: "Firefox is open. Close it yourself, then choose Update.")
    }
    check("presentation: unknown app state disables the action") {
        try expectPresentation(ready { $0.applicationOpen = nil }, checks: rows("Passed", "Passed", "Not checked"), enabled: false, note: "App state not checked.")
    }
    check("presentation: no approved target disables the action") {
        try expectPresentation(ready { $0.approvedFixtureTarget = nil }, checks: rows("Passed", "Passed", "Closed"), enabled: false, note: "No approved target.")
    }
    check("presentation: every typed refusal is shown plainly and disables the action") {
        for refusal in TransactionFailure.allCases {
            try expectPresentation(ready { $0.refusal = refusal }, checks: rows("Passed", "Passed", "Closed"),
                                   refusal: "Refused: \(refusal.rawValue)", enabled: false, note: "Refused. Nothing runs until you choose Update again.")
        }
    }
    check("presentation: deferral is shown with its time and nothing is scheduled") {
        let line = "Deferred until 2027-01-16 08:00 UTC. Nothing runs on its own."
        try expectPresentation(ready { $0.deferredUntil = 1_800_086_400 }, checks: rows("Passed", "Passed", "Closed"), deferral: line,
                               enabled: true, note: "Fixture target: \(fixtureTarget). Runs only when you choose Update.")
        try expectPresentation(ready { $0.deferredUntil = 1_800_086_400; $0.approvedFixtureTarget = nil }, checks: rows("Passed", "Passed", "Closed"),
                               deferral: line, enabled: false, note: "No approved target.")
    }
    check("presentation: times are whole UTC minutes and invalid clocks are not invented") {
        for (value, text) in [(0.0, "Checked: 1970-01-01 00:00 UTC"), (1_800_000_059.9, "Checked: 2027-01-15 08:00 UTC"),
                              (1_709_251_199.0, "Checked: 2024-02-29 23:59 UTC"), (-1.0, "Checked: unknown"),
                              (Double.nan, "Checked: unknown"), (Double.infinity, "Checked: unknown")] {
            try expectPresentation(ready { $0.checkedAt = value }, checked: text, checks: rows("Passed", "Passed", "Closed"), enabled: true,
                                   note: "Fixture target: \(fixtureTarget). Runs only when you choose Update.")
        }
        try expectPresentation(ready { $0.deferredUntil = Double.nan }, checks: rows("Passed", "Passed", "Closed"),
                               deferral: "Deferred. Nothing runs on its own.", enabled: true,
                               note: "Fixture target: \(fixtureTarget). Runs only when you choose Update.")
    }
    check("presentation: the first unmet condition is the one explained") {
        try expectPresentation(ready { $0.candidateVersion = nil; $0.refusal = .appRunning }, heading: "No update candidate",
                               checks: rows("Passed", "Passed", "Closed"), refusal: "Refused: appRunning", enabled: false, note: "No update candidate.")
        try expectPresentation(ready { $0.refusal = .appRunning; $0.applicationOpen = true; $0.approvedFixtureTarget = nil },
                               checks: rows("Passed", "Passed", "Open. Patched will not quit it"), refusal: "Refused: appRunning", enabled: false,
                               note: "Refused. Nothing runs until you choose Update again.")
        try expectPresentation(ready { $0.catalogueCheck = .notRun; $0.applicationOpen = true; $0.approvedFixtureTarget = nil },
                               checks: rows("Not run", "Passed", "Open. Patched will not quit it"), enabled: false, note: "Checks have not passed.")
        try expectPresentation(ready { $0.applicationOpen = true; $0.approvedFixtureTarget = nil },
                               checks: rows("Passed", "Passed", "Open. Patched will not quit it"), enabled: false,
                               note: "Firefox is open. Close it yourself, then choose Update.")
        try expectPresentation(ready { $0.installedVersion = nil }, installed: "Installed: unknown", checks: rows("Passed", "Passed", "Closed"),
                               enabled: true, note: "Fixture target: \(fixtureTarget). Runs only when you choose Update.")
    }
    check("presentation: no state makes a health claim, promises background activity or uses a dash flourish") {
        var inputs = [UpdateDisplayInput(appName: "Firefox"), ready(), ready { $0.applicationOpen = true }, ready { $0.deferredUntil = 1_800_086_400 },
                      ready { $0.catalogueCheck = .refused("invalidSignature") }, ready { $0.approvedFixtureTarget = nil }]
        inputs += TransactionFailure.allCases.map { refusal in ready { $0.refusal = refusal } }
        for input in inputs {
            let shown = UpdatePresentation.make(input)
            try expect(shown.previewNotice == notice, "Preview status missing: \(shown.previewNotice)")
            let text = ([shown.previewNotice, shown.heading, shown.installedLine, shown.checkedLine, shown.actionTitle, shown.actionNote,
                         shown.refusalLine ?? "", shown.deferralLine ?? ""] + shown.checks.flatMap { [$0.title, $0.status] }).joined(separator: "\n").lowercased()
            for banned in ["healthy", "secure", "protected", "up to date", "automatic", "background", "scheduled", "installed successfully", "\u{2014}", "\u{2013}"] {
                try expect(!text.contains(banned), "Presentation contains \"\(banned)\": \(text)")
            }
        }
    }
}
