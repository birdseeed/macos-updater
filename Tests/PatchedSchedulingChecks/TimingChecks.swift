import Foundation
import PatchedScheduling

@MainActor func registerTimingChecks() {
    check("allowed automatic start with fresh eligible closed target") {
        try expect(optedIn().decision(for: .automatic, conditions: conditions()) == .eligible,
                   "explicit opt-in plus fresh safe unattended inputs must be eligible")
    }
    check("automatic defaults off; manual and checks remain available") {
        let policy = SchedulePolicy(principal: owner)
        try expect(policy.decision(for: .automatic, conditions: conditions()) == .deferred(.automaticOff), "default opt-out")
        try expect(policy.decision(for: .manual, conditions: conditions()) == .eligible, "manual independent")
        try expect(policy.permitsCheck(for: owner), "read-only check independent")
        try expect(!policy.permitsCheck(for: other), "check owner binding")
    }
    check("exclusion applies only to automatic starts") {
        var policy = optedIn()
        policy.excludedProducts.insert(release().product)
        for kind: StartKind in [.automatic, .loginWindow] {
            try expect(policy.decision(for: kind, conditions: conditions()) == .deferred(.excluded), "excluded automatic")
        }
        try expect(policy.decision(for: .updateAll, conditions: conditions()) == .eligible, "manual bulk independent")
    }
    check("UTC pause blocks desktop and login window only") {
        let policy = paused()
        for kind: StartKind in [.automatic, .loginWindow] {
            try expect(policy.decision(for: kind, conditions: conditions()) == .deferred(.paused), "pause active")
        }
        try expect(policy.decision(for: .manual, conditions: conditions()) == .eligible, "paused manual")
        try expect(policy.permitsCheck(for: owner), "paused checks")
    }
    check("pause boundary rechecks opt-in exclusions and fresh eligibility") {
        var input = conditions()
        input.clock = clock(200, 110)
        var policy = paused()
        try expect(policy.decision(for: .automatic, conditions: input) == .eligible, "exact deadline resumes")
        policy.automaticEnabled = false
        try expect(policy.decision(for: .automatic, conditions: input) == .deferred(.automaticOff), "deadline never enables consent")
        policy.automaticEnabled = true
        policy.excludedProducts.insert(release().product)
        try expect(policy.decision(for: .automatic, conditions: input) == .deferred(.excluded), "deadline retains exclusion")
        policy.excludedProducts.removeAll()
        input.eligibility = .unknown
        try expect(policy.decision(for: .automatic, conditions: input) == .deferred(.eligibility), "fresh eligibility required")
    }
    check("consumed deterministic UTC and clock vectors") {
        struct Vector: Decodable {
            let name: String
            let utc: Int64
            let monotonic: Int64
            let boot: String
            let trusted: Bool
            let expected: String
        }
        let url = URL(fileURLWithPath: "Fixtures/Helper/policy-vectors.json")
        let vectors = try JSONDecoder().decode([Vector].self, from: Data(contentsOf: url))
        try expect(vectors.count >= 8, "timing vectors must not disappear")
        for vector in vectors {
            var input = conditions()
            input.clock = clock(vector.utc, vector.monotonic, boot: vector.boot, trusted: vector.trusted)
            let decision = paused().decision(for: .automatic, conditions: input)
            let expected: ScheduleDecision
            if vector.expected == "eligible" { expected = .eligible }
            else if let reason = ScheduleDeferral(rawValue: vector.expected) { expected = .deferred(reason) }
            else { throw CheckFailure(description: "Unknown vector expectation") }
            try expect(decision == expected, "\(vector.name): expected \(expected), got \(decision)")
        }
    }
    check("previous observation prevents rollback and future wall-clock jump") {
        var input = conditions()
        input.previousClock = clock(210, 120)
        input.clock = clock(205, 115)
        try expect(paused().decision(for: .automatic, conditions: input) == .deferred(.clock), "both clocks rolled back")
        input.clock = clock(300, 121)
        try expect(paused().decision(for: .automatic, conditions: input) == .deferred(.clock), "wall clock fast forward")
    }
    check("sleep never becomes a start and next awake opportunity rechecks") {
        var input = conditions()
        input.clock = clock(500, 410)
        input.awake = .no
        try expect(paused().decision(for: .automatic, conditions: input) == .deferred(.awake), "no sleep start")
        input.awake = .yes
        try expect(paused().decision(for: .automatic, conditions: input) == .eligible, "awake reevaluation")
        input.targetClosed = .no
        try expect(paused().decision(for: .automatic, conditions: input) == .deferred(.targetOpen), "target reopened")
    }
    check("missing and negative current safety inputs always defer") {
        for signal: KnownSignal in [.unknown, .no] {
            var input = conditions()
            input.awake = signal
            try expect(optedIn().decision(for: .automatic, conditions: input) == .deferred(.awake), "awake signal")
            input = conditions(); input.idle = signal
            try expect(optedIn().decision(for: .automatic, conditions: input) == .deferred(.idle), "idle signal")
            input = conditions(); input.targetClosed = signal
            for kind: StartKind in [.automatic, .manual] {
                try expect(optedIn().decision(for: kind, conditions: input) == .deferred(.targetOpen), "closed signal")
            }
        }
        var input = conditions()
        input.eligibility = .refused
        try expect(optedIn().decision(for: .manual, conditions: input) == .deferred(.eligibility), "manual fresh eligibility")
    }
    check("closed route enum keeps restart interactive and unknown for attention") {
        for route: InstallationRoute in [.restartRequired, .interactive, .unknown] {
            var input = conditions(); input.route = route
            for kind: StartKind in [.automatic, .loginWindow, .manual, .updateAll] {
                try expect(optedIn().decision(for: kind, conditions: input) == .deferred(.route), "route requires separate future consent flow")
            }
        }
    }
    check("exact skip persists across policy copy until explicit unskip") {
        var policy = optedIn()
        policy.skip(release())
        let reconstructed = policy
        for kind: StartKind in [.automatic, .loginWindow, .manual, .updateAll] {
            try expect(reconstructed.decision(for: kind, conditions: conditions()) == .deferred(.skipped), "skip applies to every new start")
        }
        try expect(policy.skippedReleases.contains(release()), "skip state retained")
        policy.unskip(release())
        try expect(policy.decision(for: .updateAll, conditions: conditions()) == .eligible, "explicit unskip")
    }
    check("later exact release allowed; same-release repack and ambiguity defer") {
        var policy = optedIn(); policy.skip(release())
        try expect(policy.decision(for: .automatic, conditions: conditions(release("3", build: "30", artifact: "digest-B"))) == .eligible, "distinct release")
        try expect(policy.decision(for: .automatic, conditions: conditions(release(artifact: "repack"))) == .deferred(.identity), "same release different bytes")
        var input = conditions(); input.release = .ambiguous
        try expect(policy.decision(for: .automatic, conditions: input) == .deferred(.identity), "ambiguous identity")
        for variant in [release(product: "app-B"), release(scope: "other-scope"),
                        release(edition: "pro"), release(channel: "preview")] {
            try expect(policy.decision(for: .automatic, conditions: conditions(variant)) == .eligible, "skip exact tuple only")
        }
    }
    check("cross-principal policy and incomplete identity refuse") {
        var input = conditions(); input.principal = other
        try expect(optedIn().decision(for: .automatic, conditions: input) == .deferred(.principal), "principal mismatch")
        input = conditions(release(artifact: ""))
        try expect(optedIn().decision(for: .manual, conditions: input) == .deferred(.identity), "empty identity")
    }
    // CHECK-ADDED: no wall-clock fallback, display-zone shift or incomplete identity shortcut.
    check("missing time and each incomplete identity field defer") {
        var input = conditions(); input.clock = clock(trusted: false)
        try expect(optedIn().decision(for: .automatic, conditions: input) == .deferred(.clock), "untrusted time")
        input.clock = clock(boot: "")
        try expect(optedIn().decision(for: .automatic, conditions: input) == .deferred(.clock), "unknown boot")
        for identity in [release(""), release(build: ""), release(product: ""), release(scope: ""),
                         release(edition: ""), release(channel: ""), release(artifact: "")] {
            try expect(optedIn().decision(for: .automatic, conditions: conditions(identity)) == .deferred(.identity), "missing exact identity component")
        }
        try expect(optedIn().decision(for: .manual, conditions: conditions(target: "")) == .deferred(.identity), "missing target")
    }
    check("pause reconstruction retains UTC deadline regardless of display zone") {
        let original = paused()
        var reconstructed = original
        reconstructed.pause = AutomaticPause(resumeUTC: 200, displayZone: "Pacific/Auckland", anchor: clock())
        var input = conditions(); input.clock = clock(199, 109)
        try expect(reconstructed.decision(for: .automatic, conditions: input) == .deferred(.paused), "zone never advances expiry")
        input.clock = clock(200, 110)
        try expect(reconstructed.decision(for: .loginWindow, conditions: input) == .eligible, "same UTC login-window boundary")
        reconstructed.skip(release())
        try expect(reconstructed.decision(for: .loginWindow, conditions: input) == .deferred(.skipped), "deadline cannot bypass skip")
    }
    check("same-version build change remains ambiguous under existing skip") {
        var policy = optedIn(); policy.skip(release())
        try expect(policy.decision(for: .updateAll, conditions: conditions(release(build: "21"))) == .deferred(.identity), "repack build cannot bypass skip")
        policy.unskip(release(build: "21"))
        try expect(policy.decision(for: .automatic, conditions: conditions()) == .deferred(.skipped), "unskip must match exact recorded identity")
    }

}
