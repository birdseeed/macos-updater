import Foundation
import PatchedScheduling
@_spi(Testing) import PatchedUpdatePreferences

// Separate read-hook store: old fixtures and their assertions remain byte-exact.
@MainActor private final class IPSStore: PreferenceStore {
    var bytes: Data?
    var unavailable = false
    var reads: [Int] = []
    var writes = 0
    var onRead: (() -> Void)?
    init(_ bytes: Data?) { self.bytes = bytes }
    func read(maximumBytes: Int) -> PreferenceRead {
        reads.append(maximumBytes)
        let hook = onRead; onRead = nil; hook?()
        if unavailable { return .unavailable }
        guard let bytes else { return .missing }
        return bytes.count <= maximumBytes ? .bytes(bytes) : .unavailable
    }
    func compareAndSwap(expected: Data?, proposed: Data, maximumBytes: Int) -> PreferenceCommit {
        writes += 1
        guard !unavailable, expected == bytes else { return .conflict }
        guard proposed.count <= maximumBytes else { return .notCommitted }
        bytes = proposed; return .committed
    }
}
private func ipsWire(_ daily: Bool = true, _ notify: Bool = true, pause: Any = NSNull(),
                     inner: Data = fixtureBytes(), receipts: [[String: Any]] = []) -> Data {
    canonical(["schema": 2, "preferences": String(decoding: inner, as: UTF8.self),
        "settings": ["dailyChecks": daily, "notifications": notify, "automaticUpdates": false, "pause": pause],
        "settingsMutations": receipts])
}
private func ipsClock(_ elapsed: Int64 = 0, boot: String = "injected-boot", trusted: Bool = true) -> ClockSample {
    ClockSample(utc: 1_000 + elapsed, monotonic: 100 + elapsed, boot: boot, trustedUTC: trusted)
}
@MainActor private func ipsLoaded(_ bytes: Data = ipsWire()) throws -> (PreferenceSession, IPSStore) {
    let store = IPSStore(bytes); let value = session(store)
    try require(value.reload(generation: generation) == .accepted(revision: 0), "loaded canonical V2 setup")
    return (value, store)
}
@MainActor private func ipsObserve(_ value: PreferenceSession, _ elapsed: Int64 = 0,
                                   awake: KnownSignal = .yes, gen: String = generation) -> Bool {
    value.observeSchedule(.observation(sample: ipsClock(elapsed), awake: awake), generation: gen)
}
@MainActor private func ipsAttempt(_ value: PreferenceSession) throws -> ScheduledCheckAttempt {
    guard let attempt = value.beginScheduledCheck(generation: generation) else {
        throw CheckFailure(message: "expected one read-only check opportunity")
    }
    return attempt
}
@MainActor private func ipsEdit(_ value: PreferenceSession, _ change: ScheduleSettingsChange,
                                id: String = "ips-edit", revision: UInt64 = 0) -> PreferenceEditResult {
    value.editScheduleSettings(change, mutationID: id, expectedRevision: revision, generation: generation)
}

@MainActor func inProcessScheduleChecks(_ c: Checks) {
    c.run("inprocess independent V2 bytes and bounded read-hook fixture", setup: true) {
        let literal = try Data(contentsOf: URL(fileURLWithPath: "Fixtures/SchedulePreferences/v2-default.json"))
        try require(ipsWire() == literal, "independent expected literal bytes")
        let store = IPSStore(literal); var callbacks = 0; store.onRead = { callbacks += 1 }
        try require(store.read(maximumBytes: literal.count - 1) == .unavailable, "fixture bound")
        try require(store.read(maximumBytes: literal.count) == .bytes(literal) && callbacks == 1, "fixture callback once")
        try require(store.reads == [literal.count - 1, literal.count] && store.writes == 0, "fixture accounting")
    }
    c.run("inprocess default legacy unloaded and foreign stores never gain opportunities") {
        let ordinary = PreferenceSession()
        let legacy = loaded().0
        let unloaded = session(IPSStore(ipsWire()))
        let foreign = session(IPSStore(ipsWire(inner: fixtureBytes(principal: "foreign"))))
        _ = foreign.reload(generation: generation)
        for value in [ordinary, legacy, unloaded, foreign] {
            try require(!ipsObserve(value) && value.beginScheduledCheck(generation: generation) == nil, "unbound owner scheduled")
            try require(!value.scheduleRuntimeSnapshot.automaticInstallationAvailable, "installation authority")
        }
    }
    c.run("inprocess first awake observation offers exactly one instance bound check and cached snapshot") {
        let (value, store) = try ipsLoaded(); let bytes = store.bytes
        try require(ipsObserve(value), "usable observation refused")
        let reads = store.reads.count
        let snapshot = value.scheduleRuntimeSnapshot
        try require(snapshot.clockState == .usable && snapshot.checkDue && !snapshot.checkInFlight, "first due description")
        try require(store.reads.count == reads, "snapshot performed IO")
        let attempt = try ipsAttempt(value)
        try require(store.reads.count == reads + 1 && store.reads.last == PreferenceRecord.maximumBytes, "begin exact one bounded read")
        try require(value.beginScheduledCheck(generation: generation) == nil && value.scheduleRuntimeSnapshot.checkInFlight, "duplicate begin")
        try require(value.completeScheduledCheck(attempt, generation: generation), "valid finish")
        try require(!value.completeScheduledCheck(attempt, generation: generation), "duplicate callback")
        try require(!value.scheduleRuntimeSnapshot.checkInFlight && store.bytes == bytes && store.writes == 0, "check wrote settings")
    }
    c.run("inprocess stale generation and foreign tokens preserve the valid current attempt") {
        let (a, _) = try ipsLoaded(); let (b, _) = try ipsLoaded()
        try require(ipsObserve(a) && ipsObserve(b), "two independent owners")
        let aa = try ipsAttempt(a); let bb = try ipsAttempt(b)
        try require(!ipsObserve(a, 1, gen: "old") && !a.cancelScheduledCheck(generation: "old"), "stale caller changed owner")
        try require(!a.completeScheduledCheck(aa, generation: "old") && !a.completeScheduledCheck(bb, generation: generation), "wrong callback accepted")
        try require(a.scheduleRuntimeSnapshot.checkInFlight && a.completeScheduledCheck(aa, generation: generation), "wrong callback destroyed valid work")
        try require(b.completeScheduledCheck(bb, generation: generation), "foreign owner lost work")
    }
    for notify in [false, true] {
        c.run("inprocess daily checks independent of notifications \(notify)") {
            let (value, _) = try ipsLoaded(ipsWire(true, notify)); try require(ipsObserve(value), "observation")
            let attempt = try ipsAttempt(value); try require(value.completeScheduledCheck(attempt, generation: generation), "notification choice blocked check")
            let (off, _) = try ipsLoaded(ipsWire(false, notify)); try require(ipsObserve(off), "daily off observation")
            try require(off.beginScheduledCheck(generation: generation) == nil && !off.scheduleRuntimeSnapshot.checkDue, "daily off checked")
        }
    }
    for finish in [false, true] {
        c.run("inprocess cadence consumed at begin and retained after \(finish ? "completion" : "cancel")") {
            let (value, _) = try ipsLoaded(); try require(ipsObserve(value), "observation")
            let token = try ipsAttempt(value)
            try require(finish ? value.completeScheduledCheck(token, generation: generation) : value.cancelScheduledCheck(generation: generation), "finish/cancel control")
            try require(!value.completeScheduledCheck(token, generation: generation), "late duplicate")
            try require(ipsObserve(value, 86_399) && value.beginScheduledCheck(generation: generation) == nil, "early daily opportunity")
            try require(ipsObserve(value, 86_400), "exact daily observation")
            let next = try ipsAttempt(value); try require(next != token, "attempt identity reused")
            try require(value.completeScheduledCheck(next, generation: generation), "next daily finish")
        }
    }
    c.run("inprocess saved settings invalidate tokens while exact replay preserves cadence and active attempt") {
        let (value, store) = try ipsLoaded(); try require(ipsObserve(value), "observation"); let old = try ipsAttempt(value)
        try require(ipsEdit(value, .notifications(false)) == .accepted(revision: 1), "saved setting")
        let expected = ipsWire(true, false, inner: fixtureBytes(revision: 1), receipts: [["id":"ips-edit", "change":["action":"notifications", "enabled":false]]])
        try require(store.bytes == expected && !value.completeScheduledCheck(old, generation: generation), "save bytes/token")
        try require(value.beginScheduledCheck(generation: generation) == nil, "saved edit reset cadence")
        try require(ipsObserve(value, 86_400), "next day"); let current = try ipsAttempt(value); let writes = store.writes
        try require(ipsEdit(value, .notifications(false), revision: 1) == .replayed(revision: 1), "exact replay")
        try require(value.completeScheduledCheck(current, generation: generation) && store.writes == writes, "replay invalidated active attempt")
        try require(ipsEdit(value, .dailyChecks(false), id: "off", revision: 1) == .accepted(revision: 2), "daily off")
        try require(ipsEdit(value, .dailyChecks(true), id: "on", revision: 2) == .accepted(revision: 3), "daily on")
        try require(value.beginScheduledCheck(generation: generation) == nil, "toggle reset cadence")
    }
    c.run("inprocess ordinary saved preferences invalidate pending check without replacing queue") {
        let (value, _) = try ipsLoaded(); try require(enqueue(value) && ipsObserve(value), "queue and observation")
        let token = try ipsAttempt(value)
        try require(edit(value, .exclusion(PreferenceAppKey(release), true)) == .accepted(revision: 1), "ordinary saved edit")
        try require(!value.completeScheduledCheck(token, generation: generation) && value.state(of: "entry") == .pending, "old revision callback or queue loss")
        try require(value.beginScheduledCheck(generation: generation) == nil, "preference edit reset cadence")
    }
    for elapsed: Int64 in [0, 100, 101] {
        c.run("inprocess saved UTC pause before exact after \(elapsed) does not block checks or manual") {
            let pause: [String: Any] = ["resumeUTC":1100, "displayZone":"Europe/Isle_of_Man"]
            let bytes = ipsWire(pause: pause); let (value, store) = try ipsLoaded(bytes)
            try require(ipsObserve(value, elapsed), "pause observation")
            try require(value.scheduleRuntimeSnapshot.pauseTiming == (elapsed < 100 ? .beforeDeadline : .atOrAfterDeadline), "UTC deadline comparison")
            let token = try ipsAttempt(value); try require(value.completeScheduledCheck(token, generation: generation), "pause blocked check")
            try require(enqueue(value) && isStarted(start(value)), "pause blocked manual")
            try require(store.bytes == bytes && store.writes == 0 && value.scheduleSettings?.pause?.resumeUTC == 1100, "pause silently cleared")
        }
    }
    c.run("inprocess display zone edit preserves absolute pause deadline and cancels old callback") {
        let (value, _) = try ipsLoaded(ipsWire(pause:["resumeUTC":1100,"displayZone":"Europe/Isle_of_Man"]))
        try require(ipsObserve(value), "observation"); let token = try ipsAttempt(value)
        try require(ipsEdit(value, .pause(SchedulePauseChoice(resumeUTC: 1100, displayZone: "America/New_York"))) == .accepted(revision: 1), "zone edit")
        try require(value.scheduleRuntimeSnapshot.pauseTiming == .beforeDeadline && !value.completeScheduledCheck(token, generation: generation), "zone shifted UTC or retained token")
        try require(ipsObserve(value, 100) && value.scheduleRuntimeSnapshot.pauseTiming == .atOrAfterDeadline, "zone changed expiry")
    }
    let invalidSamples = [ClockSample(utc: 999, monotonic: 101, boot:"injected-boot", trustedUTC:true),
        ClockSample(utc:1001, monotonic:99, boot:"injected-boot", trustedUTC:true),
        ClockSample(utc:1002, monotonic:101, boot:"injected-boot", trustedUTC:true), ipsClock(1, trusted:false),
        ipsClock(1, boot:"new-boot"), ipsClock(1, boot:"bad\nboot"), ipsClock(1, boot:String(repeating:"x",count:257)),
        ClockSample(utc: -1, monotonic:101, boot:"injected-boot", trustedUTC:true)]
    for (index, sample) in invalidSamples.enumerated() {
        c.run("inprocess invalid time latches until explicit reanchor \(index)") {
            let (value, _) = try ipsLoaded(); try require(ipsObserve(value), "valid initial observation"); let token = try ipsAttempt(value)
            _ = value.observeSchedule(.observation(sample:sample, awake:.yes), generation:generation)
            try require(value.scheduleRuntimeSnapshot.clockState == .invalid && !value.completeScheduledCheck(token, generation:generation), "fault did not latch/cancel")
            _ = ipsObserve(value, 2)
            try require(value.scheduleRuntimeSnapshot.clockState == .invalid && value.beginScheduledCheck(generation:generation) == nil, "ordinary observation cleared fault")
            try require(value.reanchorScheduleClock(ipsClock(3), awake:.yes, generation:generation), "explicit valid reanchor")
            try require(ipsObserve(value, 86_402) && value.beginScheduledCheck(generation:generation) == nil, "reanchor failed full day deferral")
            try require(ipsObserve(value, 86_403), "reanchor due observation"); _ = try ipsAttempt(value)
        }
    }
    c.run("inprocess exact UTF8 generation rejects canonically equivalent caller without harming valid token") {
        let actual = "caf\u{00e9}"; let alias = "cafe\u{0301}"
        let store = IPSStore(ipsWire()); let value = session(store, gen:actual)
        try require(value.reload(generation:actual) == .accepted(revision:0), "exact owner load")
        try require(value.observeSchedule(.observation(sample:ipsClock(),awake:.yes),generation:actual), "exact observation")
        guard let token = value.beginScheduledCheck(generation:actual) else { throw CheckFailure(message:"exact owner opportunity") }
        try require(value.beginScheduledCheck(generation:alias) == nil && !value.cancelScheduledCheck(generation:alias), "equivalent caller escaped exact binding")
        try require(!value.completeScheduledCheck(token,generation:alias) && value.completeScheduledCheck(token,generation:actual), "alias callback destroyed current work")
    }
    c.run("inprocess explicit invalidation cancels active token and requires valid explicit reanchor") {
        let (value, _) = try ipsLoaded(); try require(ipsObserve(value), "initial clock")
        let token = try ipsAttempt(value)
        try require(value.observeSchedule(.clockInvalidated,generation:generation), "invalidation event")
        try require(value.scheduleRuntimeSnapshot.clockState == .invalid && !value.completeScheduledCheck(token,generation:generation), "invalidated callback")
        try require(!value.reanchorScheduleClock(ipsClock(1,trusted:false),awake:.yes,generation:generation), "untrusted reanchor")
        try require(value.scheduleRuntimeSnapshot.clockState == .invalid, "bad reanchor cleared latch")
        try require(value.reanchorScheduleClock(ipsClock(2,boot:"replacement"),awake:.yes,generation:generation), "new boot explicit reanchor")
        try require(value.beginScheduledCheck(generation:generation) == nil, "reanchor immediate opportunity")
    }
    c.run("inprocess daily off cancels active token and preserves first begin cadence after reenable") {
        let (value, _) = try ipsLoaded(); try require(ipsObserve(value), "initial clock"); let token = try ipsAttempt(value)
        try require(ipsEdit(value,.dailyChecks(false)) == .accepted(revision:1), "daily off save")
        try require(!value.completeScheduledCheck(token,generation:generation) && value.beginScheduledCheck(generation:generation) == nil, "daily off retained work")
        try require(ipsEdit(value,.dailyChecks(true),id:"reenable",revision:1) == .accepted(revision:2), "daily reenable")
        try require(ipsObserve(value,86_399) && value.beginScheduledCheck(generation:generation) == nil, "toggle early begin")
        try require(ipsObserve(value,86_400), "exact day"); _ = try ipsAttempt(value)
    }
    c.run("inprocess action detected storage latch invalidates an active check but not queue recovery") {
        let (value, store) = try ipsLoaded(); try require(enqueue(value) && ipsObserve(value), "queue clock")
        let token = try ipsAttempt(value)
        store.bytes = ipsWire(false,inner:fixtureBytes(revision:1))
        try require(!isStarted(start(value)) && value.blockedReason == .conflict, "manual action failed to detect drift")
        try require(!value.completeScheduledCheck(token,generation:generation) && !value.scheduleRuntimeSnapshot.checkInFlight, "latched storage retained callback")
        try require(value.state(of:"entry") == .pending && store.writes == 0, "latch reset queue or repaired store")
    }
    c.run("inprocess representable Int64 ceiling never wraps into early opportunity") {
        let (value, _) = try ipsLoaded()
        let ceiling = ClockSample(utc:Int64.max, monotonic:Int64.max, boot:"ceiling", trustedUTC:true)
        _ = value.reanchorScheduleClock(ceiling, awake:.yes, generation:generation)
        try require(value.beginScheduledCheck(generation:generation) == nil && !value.scheduleRuntimeSnapshot.checkDue, "overflow created opportunity")
    }
    for unknown in [false, true] {
        c.run("inprocess sleep or unknown awake cancels callback and coalesces long wake \(unknown)") {
            let (value, _) = try ipsLoaded(); try require(ipsObserve(value), "initial awake"); let token = try ipsAttempt(value)
            if unknown { try require(ipsObserve(value, 1, awake:.unknown), "unknown observation") }
            else { try require(value.observeSchedule(.sleep, generation:generation), "sleep event") }
            try require(!value.completeScheduledCheck(token, generation:generation) && value.beginScheduledCheck(generation:generation) == nil, "sleep callback/begin")
            try require(value.scheduleRuntimeSnapshot.pauseTiming == .unavailable, "sleep advertised current pause timing")
            try require(ipsObserve(value, 3 * 86_400), "long wake"); let wake = try ipsAttempt(value)
            try require(value.completeScheduledCheck(wake, generation:generation) && value.beginScheduledCheck(generation:generation) == nil, "catchup burst")
        }
    }
    c.run("inprocess absent or nonawake time has no current pause timing and no implicit check") {
        let (value, store) = try ipsLoaded(ipsWire(pause:["resumeUTC":1100,"displayZone":"UTC"]))
        let reads = store.reads.count
        try require(value.scheduleRuntimeSnapshot.clockState == .unavailable && value.scheduleRuntimeSnapshot.pauseTiming == .unavailable, "unobserved timing")
        try require(value.beginScheduledCheck(generation:generation) == nil, "unobserved begin")
        try require(ipsObserve(value,awake:.no), "nonawake observation")
        try require(value.scheduleRuntimeSnapshot.pauseTiming == .unavailable && value.beginScheduledCheck(generation:generation) == nil, "nonawake timing/begin")
        try require(store.writes == 0 && store.reads.count >= reads, "timing wrote storage")
        try require(ipsObserve(value,1), "awake observation")
        let token = try ipsAttempt(value); try require(value.completeScheduledCheck(token,generation:generation), "first awake opportunity lost")
    }
    c.run("inprocess shutdown terminal and reconstruction rejects previous owner even same strings") {
        let (value, store) = try ipsLoaded(); try require(ipsObserve(value), "awake"); let old = try ipsAttempt(value)
        try require(value.observeSchedule(.shutdown, generation:generation), "shutdown")
        try require(!ipsObserve(value, 86_400) && !value.reanchorScheduleClock(ipsClock(86_400), awake:.yes, generation:generation), "terminal shutdown revived")
        try require(value.scheduleRuntimeSnapshot.clockState == .stopped && !value.completeScheduledCheck(old, generation:generation), "shutdown state/callback")
        let next = session(store); try require(next.reload(generation:generation) == .accepted(revision:0) && ipsObserve(next), "reconstructed choice owner")
        let current = try ipsAttempt(next)
        try require(!next.completeScheduledCheck(old, generation:generation) && next.completeScheduledCheck(current, generation:generation), "old owner replay destroyed current work")
    }
    for fault in ["drift", "missing", "unavailable", "malformed", "overlimit"] {
        c.run("inprocess action current bytes \(fault) latch without implicit adoption or repair") {
            let (value, store) = try ipsLoaded(); try require(ipsObserve(value), "awake"); let token = try ipsAttempt(value)
            try require(value.completeScheduledCheck(token, generation:generation) && ipsObserve(value,86_400), "control finish/next day")
            switch fault {
            case "drift": store.bytes = ipsWire(false, inner:fixtureBytes(revision:1))
            case "missing": store.bytes = nil
            case "unavailable": store.unavailable = true
            case "malformed": store.bytes = Data("{".utf8)
            default: store.bytes = Data(repeating:32,count:PreferenceRecord.maximumBytes+1)
            }
            let damaged = store.bytes; let reads = store.reads.count
            try require(value.beginScheduledCheck(generation:generation) == nil && store.reads.count == reads+1, "action did not independently read")
            try require(value.blockedReason != nil && value.scheduleSettings == nil && store.bytes == damaged && store.writes == 0, "implicit repair/adoption")
            store.bytes = ipsWire(); store.unavailable = false
            try require(value.beginScheduledCheck(generation:generation) == nil, "old bytes cleared latch")
            try require(value.reload(generation:generation) == .accepted(revision:0), "explicit reload recovery")
            _ = try ipsAttempt(value)
        }
    }
    c.run("inprocess action read reentrancy cannot mutate settings queue clock or current work") {
        let (value, store) = try ipsLoaded(); try require(enqueue(value) && ipsObserve(value), "queue/clock")
        var nestedBegin: ScheduledCheckAttempt?; var nestedObserve = true; var nestedCancel = true; var nestedEdit: PreferenceEditResult?
        store.onRead = {
            nestedBegin = value.beginScheduledCheck(generation:generation)
            nestedObserve = value.observeSchedule(.shutdown,generation:generation)
            nestedCancel = value.cancelScheduledCheck(generation:generation)
            nestedEdit = ipsEdit(value,.dailyChecks(false))
        }
        let token = try ipsAttempt(value)
        try require(nestedBegin == nil && !nestedObserve && !nestedCancel && nestedEdit == .refused(.reentrant), "read callback escaped busy barrier")
        try require(value.completeScheduledCheck(token,generation:generation) && value.state(of:"entry") == .pending && store.writes == 0, "nested callback damaged owner")
    }
    for event in ["pause", "dailyOff", "sleep", "shutdown", "clock", "storage"] {
        c.run("inprocess existing inflight completion fail recovery survive \(event), no scheduler starts") {
            for recovery in [false,true] {
                let (value, store) = try ipsLoaded(); try require(enqueue(value), "existing queue seed")
                guard case .started(let active) = start(value) else { throw CheckFailure(message:"existing manual positive") }
                let pendingRelease = candidate(version:"3",build:"30",artifact:"digest-3")
                try require(enqueue(value,pendingRelease,id:"pending") && ipsObserve(value), "pending queue and clock")
                _ = try ipsAttempt(value)
                switch event {
                case "pause": _ = ipsEdit(value,.pause(SchedulePauseChoice(resumeUTC:2000,displayZone:"UTC")))
                case "dailyOff": _ = ipsEdit(value,.dailyChecks(false))
                case "sleep": _ = value.observeSchedule(.sleep,generation:generation)
                case "shutdown": _ = value.observeSchedule(.shutdown,generation:generation)
                case "clock": _ = value.observeSchedule(.clockInvalidated,generation:generation)
                default:
                    store.unavailable = true
                    _ = value.cancelScheduledCheck(generation:generation)
                    _ = value.beginScheduledCheck(generation:generation)
                }
                try require(value.state(of:"pending") == .pending && value.state(of:"entry") == .running(active), "scheduler started or replaced existing queue")
                // With another operation active this checks joint barriers, not independent V2 guard discrimination.
                // The unchanged 65 settings checks supply positive manual-control discrimination for the V2 guard.
                for kind in [StartKind.automatic,.loginWindow] { try require(!isStarted(start(value,pendingRelease,kind:kind,id:"pending",request:"never-\(kind)")), "automatic start became available") }
                if recovery {
                    try require(value.fail(active,principal:owner,scope:.isolated), "inflight fail")
                    try require(value.recover(active,principal:owner,evidence:.verifiedIsolatedRollback) && value.state(of:"entry") == .restored, "inflight recovery")
                } else { try require(value.complete(active,principal:owner) && value.state(of:"entry") == .completed, "inflight completion") }
            }
        }
    }
}
