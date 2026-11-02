import Foundation
import PatchedLicensing

@MainActor func registerPolicyChecks() {
    for state in ["beta", "trial", "paid", "grace"] {
        check("\(state) exclusive deadline for manual automatic and queued starts") {
            let f = LeaseFixture.state(state)
            for start in ThirdPartyStart.allCases {
                try expect(try decision(f, at: f.permittedUntil - 1, start: start) == .permitted, "Valid \(state) just before deadline must grant")
                for time in [f.permittedUntil, f.permittedUntil + 1] {
                    let expected: LicenceStartDecision = f.permittedUntil == f.hardEnd ? .expired : .verificationRequired
                    try expect(try decision(f, at: time, start: start) == expected, "\(state) deadline must be exclusive")
                }
            }
        }
    }
    for state in ["none", "expired", "revoked"] {
        check("\(state) never permits new starts") {
            let f = LeaseFixture.state(state)
            let expected: LicenceStartDecision = state == "none" ? .noEntitlement : state == "revoked" ? .revoked : .expired
            for start in ThirdPartyStart.allCases { try expect(try decision(f, start: start) == expected, "Non-granting state must refuse") }
            var bad = f; bad.permittedUntil += 1; bad.hardEnd += 1
            try refused(signed(bad))
        }
    }
    check("state evidence exact required object and membership") {
        for state in Entitlement.allCases.map(\.rawValue) {
            let good = LeaseFixture.state(state)
            for evidenceState in ["trial", "paid", "grace"] where evidenceState != state {
                var f = good
                let extra = LeaseFixture.state(evidenceState).evidence!
                f.evidence = good.evidence.map { $0 + "," + extra } ?? extra
                try refused(signed(f))
            }
            if ["trial", "paid", "grace"].contains(state) {
                var f = good; f.evidence = nil; try refused(signed(f))
                f.evidence = "\"\(state)\":{}"; try refused(signed(f))
                f.evidence = good.evidence!.replacingOccurrences(of: "{", with: "{\"extra\":1,"); try refused(signed(f))
                f.evidence = "\"\(state)\":null"; try refused(signed(f))
                f.evidence = good.evidence! + "," + good.evidence!; try refused(signed(f))
            }
        }
        for (state, field) in [("trial", "startedAt"), ("trial", "expiresAt"), ("paid", "paidThrough"), ("grace", "paidThrough"), ("grace", "graceDeadline")] {
            let good = LeaseFixture.state(state)
            let object = try JSONSerialization.jsonObject(with: Data(good.payload.utf8)) as! [String: Any]
            var copy = object; var evidence = object[state] as! [String: Any]
            evidence.removeValue(forKey: field); copy[state] = evidence
            try refused(signed(JSONSerialization.data(withJSONObject: copy)))
        }
    }
    check("paid minimum uses both sides of original paidThrough") {
        for days: Int64 in [10, 30, 60] {
            var f = LeaseFixture(); f.hardEnd = base + days * day
            f.permittedUntil = min(base + 30 * day, f.hardEnd)
            f.evidence = "\"paid\":{\"paidThrough\":\(f.hardEnd)}"
            try expect(try decision(f, at: f.permittedUntil - 1) == .permitted, "Valid paid minimum")
            f.permittedUntil += 1; try refused(signed(f))
        }
        var f = LeaseFixture(); f.hardEnd += 1; try refused(signed(f))
    }
    check("confirmed grace fixed original deadline and never inferred from expired paid") {
        var grace = LeaseFixture.state("grace")
        grace.issuedAt = base + 6 * day
        try expect(try decision(grace, at: grace.hardEnd - 1) == .permitted, "Late retry retains original grace")
        try expect(try decision(grace, at: grace.hardEnd) == .expired, "Grace cannot reset")
        grace.hardEnd += 1; grace.permittedUntil += 1
        grace.evidence = "\"grace\":{\"paidThrough\":\(base),\"graceDeadline\":\(grace.hardEnd)}"
        try refused(signed(grace))
        var paid = LeaseFixture(); paid.hardEnd = base + day; paid.permittedUntil = paid.hardEnd
        paid.evidence = "\"paid\":{\"paidThrough\":\(paid.hardEnd)}"
        try expect(try decision(paid, at: paid.hardEnd) == .expired, "Expired paid evidence cannot infer grace")
        var long = LeaseFixture.state("grace"); long.hardEnd = base + 40 * day
        long.permittedUntil = base + 30 * day
        long.evidence = "\"grace\":{\"paidThrough\":\(long.hardEnd - 7 * day),\"graceDeadline\":\(long.hardEnd)}"
        try expect(try decision(long, at: long.permittedUntil - 1) == .permitted, "Grace also observes 30-day issue cap")
        long.permittedUntil += 1; try refused(signed(long))
    }
    check("trial retains signed original fourteen-day end on late issue") {
        var f = LeaseFixture.state("trial", issued: base + 13 * day)
        try expect(try decision(f, at: f.hardEnd - 1) == .permitted, "Day 13 issue retains day 14 end")
        f.permittedUntil = f.issuedAt + 100
        try expect(try decision(f, at: f.permittedUntil - 1) == .permitted, "Shorter trial lease is tolerated")
        for offset: Int64 in [-1, 1, day] {
            var bad = f; bad.hardEnd += offset
            bad.evidence = "\"trial\":{\"startedAt\":\(base),\"expiresAt\":\(bad.hardEnd)}"
            try refused(signed(bad))
        }
        var bad = f; bad.hardEnd -= 1; try refused(signed(bad))
        bad = f; bad.issuedAt = base - 1; try refused(signed(bad))
        bad = f; bad.issuedAt = bad.hardEnd; try refused(signed(bad))
        bad = f; bad.permittedUntil = bad.hardEnd + 1; try refused(signed(bad))
    }
    check("beta seven-day and scheduled cap producer") {
        for scheduled in [base + day, base + 7 * day, base + 8 * day] {
            let f = LeaseFixture.state("beta", scheduledEnd: scheduled)
            try expect(f.permittedUntil == min(base + 7 * day, scheduled), "Producer applies scheduled cap")
            try expect(try decision(f, at: f.permittedUntil - 1) == .permitted, "Valid beta cap grants before deadline")
        }
        for interval in [7 * day + 1, 30 * day] {
            var f = LeaseFixture.state("beta"); f.permittedUntil = base + interval; f.hardEnd = f.permittedUntil
            try refused(signed(f))
        }
        var f = LeaseFixture.state("beta"); f.hardEnd += 1; try refused(signed(f))
    }
    check("checked sums never overflow maximum exact second") {
        for state in ["paid", "grace", "trial", "beta"] {
            var f = LeaseFixture.state(state); f.issuedAt = maximum - 10
            f.permittedUntil = maximum; f.hardEnd = maximum
            switch state {
            case "paid": f.evidence = "\"paid\":{\"paidThrough\":\(maximum)}"
            case "grace": f.evidence = "\"grace\":{\"paidThrough\":\(maximum - 10),\"graceDeadline\":\(maximum)}"
            case "trial": f.evidence = "\"trial\":{\"startedAt\":\(maximum - 10),\"expiresAt\":\(maximum)}"
            default: break
            }
            try refused(signed(f))
        }
        for token in ["-1", "9007199254740992"] {
            try refused(signed(Data(LeaseFixture().payload.replacingOccurrences(of: "\"issuedAt\":\(base)", with: "\"issuedAt\":\(token)").utf8)))
        }
    }
    check("granting interval must start strictly before deadline") {
        for state in ["paid", "grace", "trial", "beta"] {
            var f = LeaseFixture.state(state); f.permittedUntil = f.issuedAt
            try refused(signed(f))
            f.permittedUntil = f.hardEnd + 1; try refused(signed(f))
        }
    }
    check("refresh classifier accepts only enumerated eligible outages") {
        for outcome: LicenceRefreshOutcome in [.noRoute, .dnsFailure, .connectTimeout, .readTimeout, .connectionReset,
                                              .http(429), .http(500), .http(502), .http(503), .http(504)] {
            try expect(outcome.classification == .eligibleOutage, "Eligible outage must be classified")
        }
        for outcome: LicenceRefreshOutcome in [.http(200), .http(301), .http(400), .http(401), .http(403), .http(501), .http(505), .tlsFailure, .authenticationFailure, .invalidLease] {
            try expect(outcome.classification == .verificationRequired, "Non-outage must not allow cache fallback")
        }
    }
    check("missing lease or anchor refuses all new start types") {
        for start in ThirdPartyStart.allCases {
            try expect(LicenceGate.evaluate(start, lease: nil, anchor: nil, sample: sample()) == .verificationRequired, "Missing state never grants")
            try expect(LicenceGate.evaluate(start, lease: try verified(), anchor: nil, sample: sample()) == .verificationRequired, "Missing anchor never grants")
        }
        // The complete action set proves callers cannot ask this gate to deny discovery,
        // display, self-update or safe recovery. This is no claim of app composition.
        try expect(ThirdPartyStart.allCases.count == 3, "Only new third-party starts belong in the gate")
    }
}
