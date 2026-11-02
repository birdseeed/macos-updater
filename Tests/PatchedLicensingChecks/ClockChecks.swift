import PatchedLicensing

func clockRefused(_ a: LicenceTimeAnchor?, _ s: LicenceClockSample) throws {
    do { _ = try LicenceClock.evaluate(anchor: a, sample: s) }
    catch let refusal as LicenceRefusal {
        try expect(refusal == .clockUncertain, "Clock failures must be named uncertainty")
        return
    }
    throw CheckFailure(description: "Uncertain clock was accepted")
}
@MainActor func registerClockChecks() {
    check("same boot monotonic ages frozen wall and simulated sleep") {
        let f = LeaseFixture.state("beta"); let lease = try verified(f)
        let before = sample(base, elapsed: 7 * day - 1)
        let result = try LicenceClock.evaluate(anchor: anchor(f), sample: before)
        try expect(result.effectiveNow == f.permittedUntil - 1, "Monotonic elapsed must include injected sleep")
        try expect(LicenceGate.evaluate(.manual, lease: lease, anchor: anchor(f), sample: before) == .permitted, "Frozen wall cannot stop valid predeadline grant")
        try expect(LicenceGate.evaluate(.manual, lease: lease, anchor: anchor(f), sample: sample(base, elapsed: 7 * day)) == .expired, "Frozen wall cannot extend access")
    }
    check("wall and high-water maximum plus conservative rollback refusal") {
        let a = anchor(high: base + 10)
        let result = try LicenceClock.evaluate(anchor: a, sample: sample(base + 20, elapsed: 5))
        try expect(result.effectiveNow == base + 20 && result.highestObservedWall == base + 20, "Forward wall shortens access and advances high water")
        try clockRefused(a, sample(base + 9, elapsed: 20))
        let carried = LicenceTimeAnchor(serverTime: base, monotonic: 100, boot: "fixture-boot-A", highestObservedWall: result.highestObservedWall)
        try clockRefused(carried, sample(base + 19, elapsed: 30))
    }
    check("new boot refuses with wall ahead equal or behind without fresh anchor") {
        let f = LeaseFixture(); let original = try signed(f)
        let lease = try SignedLease.verify(original, trust: fixtureTrust, binding: fixtureBinding, replay: .initialAuthenticatedRefresh)
        for wall in [base - 1, base, base + 1] {
            let s = sample(wall, boot: "fixture-boot-B")
            try clockRefused(anchor(f), s)
            for start in ThirdPartyStart.allCases {
                try expect(LicenceGate.evaluate(start, lease: lease, anchor: anchor(f), sample: s) == .verificationRequired, "Reboot outage cannot grant")
            }
        }
        _ = try SignedLease.verify(original, trust: fixtureTrust, binding: fixtureBinding, replay: .cached(lease.checkpoint))
        try expect(LicenceGate.evaluate(.manual, lease: lease, anchor: anchor(f), sample: sample(base, boot: "fixture-boot-B")) == .verificationRequired, "Reading identical cached bytes cannot re-anchor")
        var fresh = f; fresh.sequence += 1; fresh.issuedAt += 1
        fresh.permittedUntil += 1
        let freshLease = try verified(fresh, replay: .authenticatedRefresh(after: lease.checkpoint))
        let freshSample = sample(fresh.issuedAt, boot: "fixture-boot-B")
        try expect(LicenceGate.evaluate(.manual, lease: freshLease, anchor: anchor(fresh, boot: "fixture-boot-B"), sample: freshSample) == .permitted, "Injected authenticated fresh lease can establish new-boot anchor")
    }
    check("missing invalid and regressing clocks refuse") {
        try clockRefused(nil, sample())
        try clockRefused(anchor(), sample(boot: nil))
        try clockRefused(anchor(boot: nil), sample())
        try clockRefused(anchor(boot: ""), sample(boot: ""))
        try clockRefused(anchor(), sample(elapsed: -1))
        for invalid in [Int64(-1), maximum + 1, Int64.max] {
            try clockRefused(anchor(), LicenceClockSample(wall: invalid, monotonic: 100, boot: "fixture-boot-A"))
            try clockRefused(anchor(), LicenceClockSample(wall: base, monotonic: invalid, boot: "fixture-boot-A"))
            try clockRefused(LicenceTimeAnchor(serverTime: invalid, monotonic: 100, boot: "fixture-boot-A", highestObservedWall: base), sample())
            try clockRefused(LicenceTimeAnchor(serverTime: base, monotonic: invalid, boot: "fixture-boot-A", highestObservedWall: base), sample())
            try clockRefused(anchor(high: invalid), sample())
        }
        try clockRefused(LicenceTimeAnchor(serverTime: maximum, monotonic: 0, boot: "fixture-boot-A", highestObservedWall: maximum),
                         LicenceClockSample(wall: maximum, monotonic: 1, boot: "fixture-boot-A"))
    }
    check("anchor must match verified lease issue time") {
        let lease = try verified()
        let mismatched = LicenceTimeAnchor(serverTime: base - 1, monotonic: 100, boot: "fixture-boot-A", highestObservedWall: base)
        try expect(LicenceGate.evaluate(.manual, lease: lease, anchor: mismatched, sample: sample()) == .verificationRequired, "Old anchor cannot accompany fresh lease")
    }
}
