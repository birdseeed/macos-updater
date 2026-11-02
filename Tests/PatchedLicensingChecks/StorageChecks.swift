import Foundation
import PatchedLicensing

enum FakeStoreFailure: Error { case unavailable }

/// Memory-only model of durable storage: constructing another client retains
/// exactly this object, not any client latch. No disk/power-loss claim is made.
@MainActor final class FakeLicenceCache: LicenceCacheStore {
    var value: LicenceCacheRead
    var writeAttempts = 0
    var failBefore: Set<Int> = []
    var failAfter: Set<Int> = []
    var failReads = false
    init(_ fixture: LeaseFixture) throws {
        let bytes = try signed(fixture)
        let lease = try SignedLease.verify(bytes, trust: fixtureTrust, binding: fixtureBinding,
                                           replay: .initialAuthenticatedRefresh)
        value = .record(LicenceCacheRecord(version: 1, state: LicenceCacheState(
            safety: LicenceSafetyState(checkpoint: lease.checkpoint, terminalRevocation: fixture.state == "revoked"),
            envelope: bytes, anchor: anchor(fixture))))
    }
    func read(binding: LicenceBinding) throws -> LicenceCacheRead {
        if failReads { throw FakeStoreFailure.unavailable }
        return binding == fixtureBinding ? value : .missing
    }
    func record() throws -> LicenceCacheRecord {
        guard case .record(let record) = value else { throw CheckFailure(description: "Expected stored fixture record") }
        return record
    }
    func mutate(_ change: (inout LicenceCacheState) -> Void) {
        guard case .record(let old) = value else { return }
        var next = old.state; change(&next)
        value = .record(LicenceCacheRecord(version: old.version + 1, state: next))
    }
    func compareAndSwap(binding: LicenceBinding, expectedVersion: UInt64,
                        replacement: LicenceCacheState) throws -> Bool {
        writeAttempts += 1
        if failBefore.contains(writeAttempts) { throw FakeStoreFailure.unavailable }
        guard binding == fixtureBinding, case .record(let old) = value,
              old.version == expectedVersion, old.version < UInt64.max else { return false }
        value = .record(LicenceCacheRecord(version: old.version + 1, state: replacement))
        if failAfter.contains(writeAttempts) { throw FakeStoreFailure.unavailable }
        return true
    }
}

@MainActor func registerStorageChecks() {
    check("L2 fake CAS specifies atomic conflict and lost acknowledgement semantics") {
        let cache = try FakeLicenceCache(LeaseFixture()); let old = try cache.record()
        var changed = old.state; changed.safety.verificationBlocked = true
        try expect(try !cache.compareAndSwap(binding: fixtureBinding, expectedVersion: 0, replacement: changed), "Conflict must not write")
        try expect(try !cache.record().state.safety.verificationBlocked, "Conflict preserves original record")
        cache.failBefore = [2]
        do { _ = try cache.compareAndSwap(binding: fixtureBinding, expectedVersion: 1, replacement: changed) }
        catch FakeStoreFailure.unavailable {}
        try expect(try cache.record().version == 1, "Pre-write failure preserves original record")
        cache.failAfter = [3]
        do { _ = try cache.compareAndSwap(binding: fixtureBinding, expectedVersion: 1, replacement: changed) }
        catch FakeStoreFailure.unavailable {}
        try expect(try cache.record().version == 2 && cache.record().state.safety.verificationBlocked,
                   "Lost acknowledgement leaves one whole committed record")
    }
    for kind in ["missing", "corrupt", "unreadable"] {
        check("L2 \(kind) whole safety state refuses without default bootstrap") {
            let rig = try ClientRig()
            if kind == "missing" { rig.cache.value = .missing }
            if kind == "corrupt" { rig.cache.value = .corrupt }
            if kind == "unreadable" { rig.cache.failReads = true }
            try rig.expectClosed(rig.client(), "Unknown replay history cannot grant")
            rig.transport.result = try response()
            try expect(rig.client().refresh() == .verificationRequired, "No first-sign-in/recovery authority in this slice")
            try expect(rig.transport.calls.isEmpty && rig.cache.writeAttempts == 0, "Must not silently replace unknown high water")
        }
    }
    for damage in ["missing bytes", "malformed bytes", "equal sequence different bytes", "missing anchor", "mismatched anchor"] {
        check("L2 \(damage) refuses cache and can recover only by newer own refresh") {
            let rig = try ClientRig()
            let conflicting = try signed(freshFixture(sequence: 2, state: "beta"))
            rig.cache.mutate { state in
                switch damage {
                case "missing bytes": state.envelope = nil
                case "malformed bytes": state.envelope = Data("{}".utf8)
                case "equal sequence different bytes": state.envelope = conflicting
                case "missing anchor": state.anchor = nil
                default: state.anchor = LicenceTimeAnchor(serverTime: base - 1, monotonic: 100, boot: "fixture-boot-A", highestObservedWall: base)
                }
            }
            try rig.expectClosed(rig.client(), "Inconsistent cache must refuse")
            try expect(rig.client().refresh() == .verificationRequired, "Outage cannot repair damaged cache")
            rig.transport.result = try response()
            try expect(rig.client().refresh() == .permitted, "Known safety history permits authenticated newer repair")
        }
    }
    check("L2 fence must persist before transport, failure sends nothing") {
        let rig = try ClientRig(); rig.cache.failBefore = [1]; rig.transport.result = try response()
        try expect(rig.client().refresh() == .verificationRequired, "Failed durable fence must refuse")
        try expect(rig.cache.writeAttempts == 1 && rig.transport.calls.isEmpty, "No request before successful durable fence")
        rig.cache.failBefore = []
        try expect(rig.client().decision(for: .manual) == .permitted, "No request was sent and old durable state remains valid")
    }
    check("L2 fence visible during request blocks a simulated restart") {
        let rig = try ClientRig(); rig.transport.result = try response()
        var observed = false
        rig.transport.duringRequest = {
            let state = try rig.cache.record().state
            try expect(state.safety.inFlight == rig.sessions.value, "Fence must name requesting session")
            try rig.expectClosed(rig.client(), "Fresh process during unresolved refresh must refuse")
            observed = true
        }
        try expect(rig.client().refresh() == .permitted && observed, "Original current request can complete its own fence")
    }
    check("L2 acknowledged lost response keeps old bounded grant and allows next server sequence") {
        let rig = try ClientRig(); rig.transport.result = .failure(.readTimeout)
        try expect(rig.client().refresh() == .permitted, "Lost response may use unchanged bounded cache")
        rig.transport.result = try response(freshFixture(sequence: 4))
        try expect(rig.client().refresh() == .permitted, "Client need not see every server sequence")
    }
    check("L2 reentrant and competing same-session refresh cannot resolve another live request fence") {
        let rig = try ClientRig(); rig.transport.result = try response()
        let original = rig.client(); var observed = false
        rig.transport.duringRequest = {
            // Bound even a defective implementation: the nested request must
            // fail the assertions, never recurse until the process crashes.
            rig.transport.duringRequest = nil
            try expect(original.refresh() == .verificationRequired, "Reentrant refresh cannot borrow its caller's fence")
            try expect(rig.client().refresh() == .verificationRequired, "Same session is not ownership of a different live operation")
            try expect(rig.transport.calls.count == 1, "Neither competing operation may send")
            observed = true
        }
        try expect(original.refresh() == .permitted && observed, "Original own request retains sole fence resolution authority")
    }
    for revoked in [false, true] {
        check("L2 failed \(revoked ? "revocation" : "invalid response") persistence retains fence across restart and renewal") {
            let rig = try ClientRig(); rig.cache.failBefore = Set(2...100)
            rig.transport.result = revoked ? try response(freshFixture(state: "revoked")) : .failure(.http(401))
            try expect(rig.client().refresh() != .permitted, "Response without atomic acceptance grants nothing")
            try expect(rig.transport.calls.count == 1 && rig.cache.writeAttempts >= 2, "Exercise post-response write failure")
            try expect(try rig.cache.record().state.safety.inFlight != nil, "Pre-request durable fence must survive failed response write")
            rig.cache.failBefore = []; rig.sessions.signIn()
            rig.transport.result = .failure(.http(503))
            try expect(rig.client().refresh() != .permitted, "Restart cannot forget unresolved response")
            rig.transport.result = try response(freshFixture(sequence: 4))
            try expect(rig.client().refresh() != .permitted, "Orphaned fence may hide terminal revocation; paid renewal cannot clear it")
        }
    }
    check("L2 failed accepted-lease commit preserves old replay bytes behind fence") {
        let rig = try ClientRig(); let original = try rig.cache.record().state.envelope
        rig.cache.failBefore = [2]; rig.transport.result = try response()
        try expect(rig.client().refresh() == .verificationRequired, "Uncommitted lease must not grant")
        let state = try rig.cache.record().state
        try expect(rig.cache.writeAttempts >= 2 && state.envelope == original && state.safety.inFlight != nil,
                   "No partial cache acceptance and no lost fence")
        try rig.expectClosed(rig.client(), "Simulated restart must read durable fence")
    }
    check("L2 lost acknowledgement after complete acceptance does not create partial state") {
        let rig = try ClientRig(); rig.cache.failAfter = [2]; rig.transport.result = try response()
        try expect(rig.client().refresh() == .verificationRequired, "Current caller must refuse uncertain write outcome")
        let state = try rig.cache.record().state
        let lease = try SignedLease.verify(state.envelope!, trust: fixtureTrust, binding: fixtureBinding, replay: .cached(state.safety.checkpoint))
        try expect(lease.sequence == 3 && state.safety.inFlight == nil, "Only complete durable acceptance may survive lost acknowledgement")
        try expect(rig.client().decision(for: .manual) == .permitted, "New process can use independently coherent accepted state")
    }
    check("L2 failed outage fence resolution cannot revive cache after restart") {
        let rig = try ClientRig(); rig.cache.failBefore = [2]
        try expect(rig.client().refresh() == .verificationRequired, "Outage requires successful durable fence resolution")
        try expect(rig.transport.calls.count == 1 && rig.cache.writeAttempts >= 2, "Must attempt outage transition")
        try rig.expectClosed(rig.client(), "Unresolved outage remains fenced across restart")
    }
    check("L2 another local user's advanced activation checkpoint wins CAS race") {
        let rig = try ClientRig(); rig.transport.result = try response()
        let newerBytes = try signed(freshFixture(sequence: 5))
        let newer = try SignedLease.verify(newerBytes, trust: fixtureTrust, binding: fixtureBinding, replay: .initialAuthenticatedRefresh)
        rig.transport.duringRequest = {
            rig.cache.mutate { state in
                state.safety.checkpoint = newer.checkpoint
                state.safety.verificationBlocked = true
                state.safety.inFlight = nil
                state.envelope = newerBytes
            }
        }
        try expect(rig.client().refresh() == .verificationRequired, "Stale response cannot overwrite another user's higher sequence")
        try expect(rig.transport.calls.count == 1, "Race must occur during actual request")
        let state = try rig.cache.record().state
        let accepted = try SignedLease.verify(state.envelope!, trust: fixtureTrust, binding: fixtureBinding, replay: .cached(state.safety.checkpoint))
        try expect(accepted.sequence == 5 && state.safety.verificationBlocked, "CAS loser cannot clear winner's block")
    }
    check("L2 wall high water persists before grant and rollback refuses across restart") {
        let rig = try ClientRig(); rig.clock.value = sample(base + 20, elapsed: 20)
        try expect(rig.client().decision(for: .manual) == .permitted, "Forward clock within lease is valid")
        try expect(try rig.cache.record().state.anchor?.highestObservedWall == base + 20, "Highest observed wall must persist")
        rig.clock.value = sample(base + 19, elapsed: 30)
        try rig.expectClosed(rig.client(), "New process cannot forget wall high water")
    }
    check("L2 failed high-water persistence refuses current grant") {
        let rig = try ClientRig(); rig.clock.value = sample(base + 20, elapsed: 20)
        rig.cache.failBefore = Set(2...100)
        try expect(rig.client().decision(for: .queued) == .verificationRequired, "No grant before durable wall observation")
        try expect(rig.cache.writeAttempts >= 2, "Persist a pre-observation fence before sampling clock, then the observed high water")
        try expect(try rig.cache.record().state.safety.inFlight != nil, "Unrecorded observation retains durable uncertainty")
        rig.cache.failBefore = []; rig.clock.value = sample(base + 1, elapsed: 30)
        try rig.expectClosed(rig.client(), "Restart cannot forget unsaved advanced-wall observation")
    }
    check("L2 failed pre-observation fence does not consume unsaved clock evidence") {
        let rig = try ClientRig(); rig.cache.failBefore = [1]
        try expect(rig.client().decision(for: .manual) == .verificationRequired, "Fence failure refuses")
        try expect(rig.cache.writeAttempts == 1 && rig.clock.observations == 0, "No clock observation before durable safety fence")
    }
    check("L2 interruption before response leaves orphan fence closed to newer paid renewal") {
        let rig = try ClientRig()
        rig.cache.mutate { $0.safety.inFlight = rig.sessions.value }
        rig.sessions.signIn(); rig.transport.result = try response(freshFixture(sequence: 4))
        try expect(rig.client().refresh() == .verificationRequired, "A restarted client cannot prove an old fence belongs to its live request")
        try expect(rig.transport.calls.isEmpty, "Orphan fence has no automatic recovery path in this slice")
        try rig.expectClosed(rig.client(), "Interrupted request stays closed")
    }
    for state in ["paid", "grace", "trial", "beta"] {
        check("L2 \(state) outage honours exact signed exclusive deadline with frozen wall and sleep") {
            let fixture = LeaseFixture.state(state); let rig = try ClientRig(fixture)
            rig.clock.value = sample(base, elapsed: fixture.permittedUntil - base - 1)
            try expect(rig.client().refresh() == .permitted, "Last second before authenticated deadline permits")
            rig.clock.value = sample(base, elapsed: fixture.permittedUntil - base)
            try expect(rig.client().refresh() != .permitted, "Frozen wall/sleep cannot extend exact deadline")
            try expect(try rig.cache.record().state.anchor?.serverTime == base, "Outage must never move anchor or infer grace")
        }
    }
    check("L2 reboot outage refuses until newer authenticated refresh reanchors") {
        let rig = try ClientRig(); rig.clock.value = sample(base + 1, boot: "fixture-boot-B")
        try expect(rig.client().refresh() == .verificationRequired, "Changed boot cannot use cache during outage")
        rig.transport.result = try response()
        try expect(rig.client().refresh() == .permitted, "Own fresh response may reanchor new boot")
        try expect(try rig.cache.record().state.anchor?.boot == "fixture-boot-B", "Persist accepted new boot")
    }
    for time in [sample(base - 1), sample(elapsed: -1), sample(boot: nil),
                 LicenceClockSample(wall: -1, monotonic: 100, boot: "fixture-boot-A")] {
        check("L2 uncertain injected time refuses an established cache") {
            let rig = try ClientRig()
            try expect(rig.client().decision(for: .manual) == .permitted, "Establish that the cached grant works before clock damage")
            rig.clock.value = time
            try rig.expectClosed(rig.client(), "Rollback, unknown boot and invalid time must refuse")
            try expect(rig.client().refresh() == .verificationRequired, "Outage cannot repair uncertain time")
        }
    }
    check("L2 pure public operations remain outside the closed new-start action set") {
        try expect(ThirdPartyStart.allCases.count == 3, "Only manual automatic and queued third-party starts belong here")
        // Discovery, display, self-update and recovery have no LicenceClient
        // entry point or adapter dependency. This is a type boundary, not UI proof.
    }
}
