import Foundation
import PatchedShell

@MainActor func registerMenuSummaryChecks() {
    let sample = MenuSummaryCounts(ready: 2, externallyManaged: 3, skipped: 5, deferred: 7)
    let currentRows = ["Ready: 2", "Externally managed: 3", "Skipped: 5", "Deferred: 7"]
    let cachedRows = ["Cached ready: 2", "Cached externally managed: 3", "Cached skipped: 5", "Cached deferred: 7"]
    let unavailableTitle = "Update status unavailable"
    let cachedTitle = "Cached update information"

    func assertWords(_ summary: MenuSummary, title: String, details: [String]) throws {
        try expect(summary.title == title, "Wrong truthful menu title: \(summary.title)")
        try expect(summary.details == details, "Missing, conflated or reordered menu facts: \(summary.details)")
        try expect(summary.accessibilitySummary == ([title] + details).joined(separator: ". "),
                   "Accessibility summary does not expose the same ordered facts")
    }

    check("menu summary: default construction is unavailable, never zero-ready") {
        try assertWords(MenuSummary(), title: unavailableTitle, details: [])
    }
    check("menu summary: current counts remain distinct") {
        try assertWords(MenuSummary(counts: sample, observation: .current),
                        title: "2 updates ready", details: currentRows)
    }
    check("menu summary: one ready update uses singular words") {
        let counts = MenuSummaryCounts(ready: 1, externallyManaged: 0, skipped: 0, deferred: 0)
        try assertWords(MenuSummary(counts: counts, observation: .current), title: "1 update ready",
                        details: ["Ready: 1", "Externally managed: 0", "Skipped: 0", "Deferred: 0"])
    }
    check("menu summary: current zero describes ready subset only") {
        let counts = MenuSummaryCounts(ready: 0, externallyManaged: 3, skipped: 5, deferred: 7)
        try assertWords(MenuSummary(counts: counts, observation: .current), title: "No ready updates",
                        details: ["Ready: 0", "Externally managed: 3", "Skipped: 5", "Deferred: 7"])
    }
    check("menu summary: known cached age labels every count cached") {
        try assertWords(MenuSummary(counts: sample, observation: .cached(ageMinutes: 42)),
                        title: cachedTitle, details: cachedRows + ["Last checked 42 minutes ago"])
    }
    for (age, label) in [(0, "Last checked 0 minutes ago"), (1, "Last checked 1 minute ago"),
                         (Int.max, "Last checked \(Int.max) minutes ago")] {
        check("menu summary: cached age boundary \(age)") {
            try assertWords(MenuSummary(counts: sample, observation: .cached(ageMinutes: age)),
                            title: cachedTitle, details: cachedRows + [label])
        }
    }
    let unknownAges: [Int?] = [nil, -1, Int.min]
    for age in unknownAges {
        check("menu summary: unknown or invalid age \(String(describing: age)) stays unknown") {
            try assertWords(MenuSummary(counts: sample, observation: .cached(ageMinutes: age)),
                            title: cachedTitle, details: cachedRows + ["Last checked: age unavailable"])
        }
    }
    check("menu summary: cached zero never asserts a current ready result") {
        let zero = MenuSummaryCounts(ready: 0, externallyManaged: 0, skipped: 0, deferred: 0)
        try assertWords(MenuSummary(counts: zero, observation: .cached(ageMinutes: 0)), title: cachedTitle,
                        details: ["Cached ready: 0", "Cached externally managed: 0", "Cached skipped: 0",
                                  "Cached deferred: 0", "Last checked 0 minutes ago"])
    }
    let observations: [MenuSummaryObservation] = [.unavailable, .current, .cached(ageMinutes: 42)]
    for observation in observations {
        check("menu summary: missing counts remain unavailable for \(observation)") {
            try assertWords(MenuSummary(observation: observation), title: unavailableTitle, details: [])
        }
    }
    check("menu summary: supplied counts cannot override unavailable observation") {
        try assertWords(MenuSummary(counts: sample, observation: .unavailable), title: unavailableTitle, details: [])
    }
    for index in 0..<4 {
        for invalid in [-1, Int.min] {
            for observation in observations {
                check("menu summary: invalid count \(index)/\(invalid)/\(observation) refuses whole projection") {
                    var values = [2, 3, 5, 7]
                    values[index] = invalid
                    let counts = MenuSummaryCounts(ready: values[0], externallyManaged: values[1],
                                                   skipped: values[2], deferred: values[3])
                    try assertWords(MenuSummary(counts: counts, observation: observation),
                                    title: unavailableTitle, details: [])
                }
            }
        }
    }
    check("menu summary: independent Int.max counts never overflow a total") {
        let maximum = MenuSummaryCounts(ready: Int.max, externallyManaged: Int.max, skipped: Int.max, deferred: Int.max)
        try assertWords(MenuSummary(counts: maximum, observation: .current), title: "\(Int.max) updates ready",
                        details: ["Ready: \(Int.max)", "Externally managed: \(Int.max)",
                                  "Skipped: \(Int.max)", "Deferred: \(Int.max)"])
        try assertWords(MenuSummary(counts: maximum, observation: .cached(ageMinutes: nil)), title: cachedTitle,
                        details: ["Cached ready: \(Int.max)", "Cached externally managed: \(Int.max)",
                                  "Cached skipped: \(Int.max)", "Cached deferred: \(Int.max)",
                                  "Last checked: age unavailable"])
    }
    // Every simultaneous fact survives, including when the underlying result is unavailable.
    for observation in observations {
        for bits in 0..<8 {
            check("menu summary: orthogonal status combination \(observation)/\(bits)") {
                let checking = bits & 1 != 0
                let paused = bits & 2 != 0
                let attention = bits & 4 != 0
                var facts: [String] = []
                if checking { facts.append("Checking for updates") }
                if paused { facts.append("Automatic installation paused") }
                if attention { facts.append("Needs attention") }
                let title: String
                let rows: [String]
                switch observation {
                case .unavailable:
                    title = unavailableTitle
                    rows = []
                case .current:
                    title = "2 updates ready"
                    rows = currentRows
                case .cached:
                    title = cachedTitle
                    rows = cachedRows + ["Last checked 42 minutes ago"]
                }
                let summary = MenuSummary(counts: sample, observation: observation, isChecking: checking,
                                          automaticInstallationPaused: paused, needsAttention: attention)
                try assertWords(summary, title: title, details: rows + facts)
                try expect(summary == MenuSummary(counts: sample, observation: observation, isChecking: checking,
                                                  automaticInstallationPaused: paused, needsAttention: attention),
                           "Identical immutable inputs produced different output")
            }
        }
    }
    check("menu summary: refused counts retain all orthogonal facts") {
        let invalid = MenuSummaryCounts(ready: -1, externallyManaged: 0, skipped: 0, deferred: 0)
        try assertWords(MenuSummary(counts: invalid, observation: .current, isChecking: true,
                                   automaticInstallationPaused: true, needsAttention: true),
                        title: unavailableTitle,
                        details: ["Checking for updates", "Automatic installation paused", "Needs attention"])
    }
    check("menu summary: later construction cannot mutate an earlier value") {
        let earlier = MenuSummary(counts: sample, observation: .current)
        _ = MenuSummary(isChecking: true, automaticInstallationPaused: true, needsAttention: true)
        try assertWords(earlier, title: "2 updates ready", details: currentRows)
    }
}
