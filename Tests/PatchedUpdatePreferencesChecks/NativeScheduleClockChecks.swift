import Foundation
import PatchedScheduling
@_spi(Testing) import PatchedUpdatePreferences

private let nscBoot = "12345678-1234-4234-8234-123456789ABC"
private let nscOtherBoot = "87654321-4321-4321-8321-CBA987654321"
private enum NSCReadError: Error { case unavailable }
// Controlled observations only: no clock, sysctl, native permission or installer capability.
@MainActor private final class NSCRawFixture {
    var raw: NativeScheduleClockRawRead
    var fails = false
    var reads = 0
    init(_ raw: NativeScheduleClockRawRead) { self.raw = raw }
    func read() throws -> NativeScheduleClockRawRead {
        reads += 1
        if fails { throw NSCReadError.unavailable }
        return raw
    }
    func clock() -> NativeScheduleClock { NativeScheduleClock(rawReader: { try self.read() }) }
}
private func nscRaw(_ wall: Double = 1_000.75, _ before: UInt64 = 100_900_000_000,
                    after: UInt64? = nil, boot: String = nscBoot,
                    afterBoot: String? = nil) -> NativeScheduleClockRawRead {
    NativeScheduleClockRawRead(wallSeconds: wall, continuousBeforeNanoseconds: before,
        continuousAfterNanoseconds: after ?? before, bootBefore: boot, bootAfter: afterBoot ?? boot)
}
private func nscExpected(_ utc: Int64, _ monotonic: Int64, boot: String = nscBoot) -> ClockSample {
    // Legacy model usability flag only; no authenticated UTC assertion.
    ClockSample(utc: utc, monotonic: monotonic, boot: boot, trustedUTC: true)
}
@MainActor private func nscSample(_ clock: NativeScheduleClock) throws -> ClockSample {
    guard let sample = clock.sample() else { throw CheckFailure(message: "expected bounded local scheduling sample") }
    return sample
}
private func nscWire() -> Data {
    canonical(["schema": 2, "preferences": String(decoding: fixtureBytes(), as: UTF8.self),
        "settings": ["dailyChecks": true, "notifications": true, "automaticUpdates": false, "pause": NSNull()],
        "settingsMutations": []])
}
@MainActor private func nscLoaded() throws -> (PreferenceSession, MemoryStore) {
    let store = MemoryStore(bytes: nscWire()); let value = session(store)
    try require(value.reload(generation: generation) == .accepted(revision: 0), "native clock owner fixture load")
    try require(enqueue(value), "pending queue fixture")
    return (value, store)
}
@MainActor private func nscObserve(_ value: PreferenceSession, _ sample: ClockSample) throws {
    try require(value.observeSchedule(.observation(sample: sample, awake: .yes), generation: generation), "local scheduling observation")
}
@MainActor private func nscAttempt(_ value: PreferenceSession) throws -> ScheduledCheckAttempt {
    guard let attempt = value.beginScheduledCheck(generation: generation) else { throw CheckFailure(message: "expected due check opportunity") }
    return attempt
}

@MainActor func nativeScheduleClockChecks(_ c: Checks) {
    c.run("native clock constructors perform no raw read", setup: true) {
        let fixture = NSCRawFixture(nscRaw()); let clock = fixture.clock()
        _ = NativeScheduleClock()
        try require(fixture.reads == 0, "injected construction read clock")
        _ = clock // Never call the ordinary native sampler in checks.
    }
    // First behavior query is intentionally positive: the Phase A nil stub is meaningfully RED.
    c.run("native clock first sample anchors independent whole seconds") {
        let fixture = NSCRawFixture(nscRaw()); let clock = fixture.clock()
        try require(try nscSample(clock) == nscExpected(1_000, 100), "initial floor anchor")
        try require(fixture.reads == 1, "explicit sample must read one bounded raw pair")
    }
    c.run("native clock aligned fractional projection preserves strict predicate") {
        let fixture = NSCRawFixture(nscRaw()); let clock = fixture.clock()
        let anchor = try nscSample(clock)
        let vectors: [(Double, UInt64, Int64, Int64)] = [
            (1_000.85, 101_000_000_000, 1_000, 100),
            (1_001.749999999, 101_899_999_999, 1_000, 100),
            (1_001.75, 101_900_000_000, 1_001, 101),
            (1_001.750000001, 101_900_000_001, 1_001, 101),
            (1_002.75, 102_900_000_000, 1_002, 102)]
        for (wall, nanos, utc, mono) in vectors {
            fixture.raw = nscRaw(wall, nanos)
            let sample = try nscSample(clock)
            try require(sample == nscExpected(utc, mono) && sample.isConsistent(with: anchor), "independent fraction boundary expectation")
        }
    }
    c.run("native clock midpoint uses ordered subtraction without UInt64 sum overflow") {
        let fixture = NSCRawFixture(nscRaw(100.5, UInt64.max - 50_000_000, after: UInt64.max))
        let clock = fixture.clock()
        try require(try nscSample(clock) == nscExpected(100, 18_446_744_073), "safe midpoint near UInt64 ceiling")
    }
    c.run("native clock midpoint at subsecond boundary is independently floored") {
        let fixture = NSCRawFixture(nscRaw(100.5, 999_999_999, after: 1_000_000_001))
        try require(try nscSample(fixture.clock()) == nscExpected(100, 1), "midpoint crossed whole second")
    }
    for drift in [-0.25, 0.25] {
        c.run("native clock accepts inclusive 250ms raw wall agreement \(drift)") {
            let fixture = NSCRawFixture(nscRaw(100.5, 10_000_000_000)); let clock = fixture.clock()
            _ = try nscSample(clock); fixture.raw = nscRaw(101.5 + drift, 11_000_000_000)
            try require(try nscSample(clock) == nscExpected(101, 11), "inclusive tolerance changed projection")
        }
    }
    let invalidInitial: [(String, NativeScheduleClockRawRead)] = [
        ("negative", nscRaw(-0.1)), ("nan", nscRaw(.nan)), ("positive infinity", nscRaw(.infinity)),
        ("negative infinity", nscRaw(-.infinity)),
        ("rounded Int64 ceiling", nscRaw(Double(Int64.max))),
        ("larger than Int64", nscRaw(Double.greatestFiniteMagnitude)),
        ("reversed bracket", nscRaw(100, 101, after: 100)),
        ("bracket over 50ms", nscRaw(100, 0, after: 50_000_001)),
        ("different boot within pair", nscRaw(100, 0, afterBoot: nscOtherBoot))]
    for (name, raw) in invalidInitial {
        c.run("native clock invalid initial raw pair refuses \(name)") {
            let fixture = NSCRawFixture(raw)
            try require(fixture.clock().sample() == nil, "invalid initial raw accepted")
        }
    }
    for badBoot in ["", "not-a-uuid", "12345678123442348234123456789ABC", "00000000-0000-0000-0000-000000000000", nscBoot + "\n", " " + nscBoot] {
        c.run("native clock paired malformed boot refuses \(badBoot.utf8.count)") {
            let fixture = NSCRawFixture(nscRaw(100, 0, boot: badBoot))
            try require(fixture.clock().sample() == nil, "matching malformed UUID strings accepted")
        }
    }
    c.run("native clock finite safe Double to Int64 conversion accepts representable predecessor") {
        let fixture = NSCRawFixture(nscRaw(Double(Int64.max).nextDown, 0))
        try require(try nscSample(fixture.clock()) == nscExpected(9_223_372_036_854_774_784, 0), "safe predecessor truncated rounded ceiling")
    }
    c.run("native clock exact zero anchor is valid") {
        let fixture = NSCRawFixture(nscRaw(0, 0))
        try require(try nscSample(fixture.clock()) == nscExpected(0, 0), "nonnegative boundary refused")
    }
    let invalidLater: [(String, NativeScheduleClockRawRead)] = [
        ("forward wall step", nscRaw(1_002.000001, 101_900_000_000)),
        ("slow wall step", nscRaw(1_001.499999, 101_900_000_000)),
        ("backward wall within tolerance", nscRaw(1_000.70, 100_910_000_000)),
        ("backward monotonic", nscRaw(1_000.75, 100_899_999_999)),
        ("overlapping rollback before previous after", nscRaw(1_000.75, 100_899_999_999, after: 100_900_000_001)),
        ("changed boot", nscRaw(1_001.75, 101_900_000_000, boot: nscOtherBoot))]
    for (name, invalid) in invalidLater {
        c.run("native clock invalid later raw latches until explicit recovery \(name)") {
            let fixture = NSCRawFixture(nscRaw()); let clock = fixture.clock()
            _ = try nscSample(clock); fixture.raw = invalid
            try require(clock.sample() == nil, "invalid later raw accepted")
            fixture.raw = nscRaw(1_002.75, 102_900_000_000)
            try require(clock.sample() == nil, "ordinary sample cleared invalid latch")
            guard let recovered = clock.reanchor() else { throw CheckFailure(message: "explicit fresh reanchor refused") }
            try require(recovered == nscExpected(1_002, 102), "reanchor retained stale fraction or anchor")
            fixture.raw = nscRaw(1_003.75, 103_900_000_000)
            try require(try nscSample(clock) == nscExpected(1_003, 103), "recovered sampler remained latched")
        }
    }
    c.run("native clock failed first read also latches and failed reanchor cannot clear it") {
        let fixture = NSCRawFixture(nscRaw()); fixture.fails = true; let clock = fixture.clock()
        try require(clock.sample() == nil, "failed first read accepted")
        fixture.fails = false
        try require(clock.sample() == nil, "first-read failure silently recovered")
        fixture.raw = nscRaw(.nan)
        try require(clock.reanchor() == nil, "bad explicit reanchor accepted")
        fixture.raw = nscRaw()
        try require(clock.sample() == nil, "failed reanchor cleared latch")
        try require(clock.reanchor() == nscExpected(1_000, 100), "valid explicit recovery")
    }
    c.run("native clock read error after anchor latches") {
        let fixture = NSCRawFixture(nscRaw()); let clock = fixture.clock(); _ = try nscSample(clock)
        fixture.fails = true; try require(clock.sample() == nil, "read error accepted")
        fixture.fails = false; fixture.raw = nscRaw(1_001.75, 101_900_000_000)
        try require(clock.sample() == nil && clock.reanchor() == nscExpected(1_001, 101), "read error did not require explicit recovery")
    }
    c.run("native clock unsafe ceiling advance refuses rather than wrapping projection") {
        let fixture = NSCRawFixture(nscRaw(Double(Int64.max).nextDown, 0)); let clock = fixture.clock()
        _ = try nscSample(clock)
        fixture.raw = nscRaw(Double(Int64.max), 2_048_000_000_000)
        try require(clock.sample() == nil, "overflow/unsafe conversion yielded wrapped projection")
    }
    for complete in [false, true] {
        c.run("native clock sleep inclusive day projection preserves same owner due and cancel \(complete)") {
            let fixture = NSCRawFixture(nscRaw()); let clock = fixture.clock(); let (value, store) = try nscLoaded()
            let original = store.bytes
            try nscObserve(value, nscSample(clock)); let first = try nscAttempt(value)
            try require(complete ? value.completeScheduledCheck(first, generation: generation) : value.cancelScheduledCheck(generation: generation), "finish or cancel")
            try require(!value.completeScheduledCheck(first, generation: generation), "old callback survived")
            fixture.raw = nscRaw(87_400.749999999, 86_500_899_999_999)
            try nscObserve(value, nscSample(clock))
            try require(value.beginScheduledCheck(generation: generation) == nil, "day minus nanosecond became due")
            try require(value.observeSchedule(.sleep, generation: generation), "sleep event")
            fixture.raw = nscRaw(87_400.75, 86_500_900_000_000)
            let wake = try nscSample(clock)
            try require(wake == nscExpected(87_400, 86_500), "sleep inclusive elapsed day")
            try nscObserve(value, wake); let next = try nscAttempt(value)
            try require(next != first && value.beginScheduledCheck(generation: generation) == nil, "coalescing/identity")
            try require(value.completeScheduledCheck(next, generation: generation), "next due completion")
            try require(store.bytes == original && store.writes == 0 && value.state(of: "entry") == .pending, "clock/check changed settings or started queue")
            try require(!value.scheduleRuntimeSnapshot.automaticInstallationAvailable, "projection minted install authority")
        }
    }
    c.run("native clock refusal requires caller invalidation and explicit owner reanchor defers day") {
        let fixture = NSCRawFixture(nscRaw()); let clock = fixture.clock(); let (value, store) = try nscLoaded()
        try nscObserve(value, nscSample(clock)); let old = try nscAttempt(value)
        fixture.fails = true; try require(clock.sample() == nil, "read failure")
        try require(value.scheduleRuntimeSnapshot.checkInFlight && value.scheduleRuntimeSnapshot.clockState == .usable, "sampler silently mutated separate owner")
        try require(value.observeSchedule(.clockInvalidated, generation: generation), "caller invalidation")
        try require(!value.completeScheduledCheck(old, generation: generation), "invalidated old callback")
        fixture.fails = false; fixture.raw = nscRaw(2_000.5, 200_000_000_000, boot: nscOtherBoot)
        guard let recovered = clock.reanchor() else { throw CheckFailure(message: "fresh boot sampler recovery") }
        try require(value.scheduleRuntimeSnapshot.clockState == .invalid, "sampler recovery silently recovered owner")
        _ = value.observeSchedule(.observation(sample: recovered, awake: .yes), generation: generation)
        try require(value.scheduleRuntimeSnapshot.clockState == .invalid, "ordinary observation cleared owner latch")
        try require(value.reanchorScheduleClock(recovered, awake: .yes, generation: generation), "explicit same-owner recovery")
        fixture.raw = nscRaw(88_399.5, 86_599_000_000_000, boot: nscOtherBoot)
        try nscObserve(value, nscSample(clock))
        try require(value.beginScheduledCheck(generation: generation) == nil, "explicit reanchor failed day deferral")
        fixture.raw = nscRaw(88_400.5, 86_600_000_000_000, boot: nscOtherBoot)
        try nscObserve(value, nscSample(clock)); _ = try nscAttempt(value)
        try require(store.writes == 0 && store.bytes == nscWire() && value.state(of: "entry") == .pending, "recovery wrote or started queue")
    }
    // Additive pause-boundary regression: controlled raw reads only, no native I/O.
    for wall in [1_000.75, 1_000.750001, 1_000.999999] {
        c.run("native clock refuses projection ahead of observed whole wall and latches \(wall)") {
            let fixture = NSCRawFixture(nscRaw(1_000.0, 100_000_000_000)); let clock = fixture.clock()
            try require(try nscSample(clock) == nscExpected(1_000, 100), "whole-second boundary anchor")
            fixture.raw = nscRaw(wall, 101_000_000_000)
            try require(clock.sample() == nil, "projection crossed pause deadline before observed wall")
            fixture.raw = nscRaw(1_001.0, 101_000_000_000)
            try require(clock.sample() == nil, "ordinary valid observation cleared early-projection latch")
            fixture.raw = nscRaw(1_001.75, 102_000_000_000)
            guard let recovered = clock.reanchor() else { throw CheckFailure(message: "explicit boundary recovery refused") }
            try require(recovered == nscExpected(1_001, 102), "explicit recovery failed fresh independent anchor")
            fixture.raw = nscRaw(1_002.75, 103_000_000_000)
            let next = try nscSample(clock)
            try require(next == nscExpected(1_002, 103) && next.isConsistent(with: recovered), "boundary recovery broke strict elapsed predicate")
        }
    }
    for wall in [1_001.0, 1_001.000001] {
        c.run("native clock accepts projection at or behind observed whole wall \(wall)") {
            let fixture = NSCRawFixture(nscRaw(1_000.0, 100_000_000_000)); let clock = fixture.clock()
            let anchor = try nscSample(clock)
            fixture.raw = nscRaw(wall, 101_000_000_000)
            let sample = try nscSample(clock)
            try require(sample == nscExpected(1_001, 101) && sample.isConsistent(with: anchor), "exact or just-after deadline over-refused")
        }
    }
    c.run("native clock refusal preserves saved pause until observed wall reaches deadline") {
        let fixture = NSCRawFixture(nscRaw(1_000.0, 100_000_000_000)); let clock = fixture.clock()
        let (value, store) = try nscLoaded()
        let pause = SchedulePauseChoice(resumeUTC: 1_001, displayZone: "UTC")
        try require(value.editScheduleSettings(.pause(pause), mutationID: "native-clock-pause-boundary-regression",
            expectedRevision: 0, generation: generation) == .accepted(revision: 1), "deliberate saved pause choice")
        let savedBytes = store.bytes; let savedWrites = store.writes
        try require(savedWrites == 1 && value.scheduleSettings?.pause == pause, "pause choice was not persisted exactly once")
        try nscObserve(value, nscSample(clock))
        try require(value.scheduleRuntimeSnapshot.pauseTiming == .beforeDeadline, "anchor prematurely expired saved pause")
        let old = try nscAttempt(value)
        fixture.raw = nscRaw(1_000.75, 101_000_000_000)
        try require(clock.sample() == nil, "early projected UTC must refuse before session observation")
        try require(value.scheduleRuntimeSnapshot.clockState == .usable &&
            value.scheduleRuntimeSnapshot.pauseTiming == .beforeDeadline && value.scheduleRuntimeSnapshot.checkInFlight,
            "sampler refusal silently mutated separate session")
        try require(value.observeSchedule(.clockInvalidated, generation: generation), "explicit caller invalidation")
        try require(value.scheduleRuntimeSnapshot.clockState == .invalid &&
            value.scheduleRuntimeSnapshot.pauseTiming == .unavailable && !value.scheduleRuntimeSnapshot.checkDue,
            "invalidated owner advertised current pause timing or due check")
        try require(!value.completeScheduledCheck(old, generation: generation), "invalidated old attempt survived")
        guard let recovered = clock.reanchor() else { throw CheckFailure(message: "explicit pre-deadline sampler reanchor refused") }
        try require(recovered == nscExpected(1_000, 101), "pre-deadline reanchor did not floor fresh wall")
        try require(value.scheduleRuntimeSnapshot.clockState == .invalid &&
            value.scheduleRuntimeSnapshot.pauseTiming == .unavailable, "sampler reanchor silently recovered separate session")
        try require(value.reanchorScheduleClock(recovered, awake: .yes, generation: generation), "explicit same-owner session recovery")
        try require(value.scheduleRuntimeSnapshot.pauseTiming == .beforeDeadline &&
            !value.scheduleRuntimeSnapshot.checkDue && value.beginScheduledCheck(generation: generation) == nil,
            "pre-deadline recovery expired pause or bypassed full-day deferral")
        fixture.raw = nscRaw(1_001.75, 102_000_000_000)
        let reached = try nscSample(clock)
        try require(reached == nscExpected(1_001, 102) && reached.isConsistent(with: recovered), "recovered deadline sample inconsistent")
        try nscObserve(value, reached)
        try require(value.scheduleRuntimeSnapshot.pauseTiming == .atOrAfterDeadline &&
            !value.scheduleRuntimeSnapshot.checkDue, "observed wall deadline or cadence deferral incorrect")
        try require(store.bytes == savedBytes && store.writes == savedWrites &&
            value.scheduleSettings?.pause == pause && value.state(of: "entry") == .pending,
            "clock recovery rewrote saved pause or started pending queue")
        try require(!value.scheduleRuntimeSnapshot.automaticInstallationAvailable &&
            !value.completeScheduledCheck(old, generation: generation), "recovery minted install authority or revived old attempt")
    }
}
