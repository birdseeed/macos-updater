import Foundation
import Darwin
import PatchedScheduling

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}
func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure(description: message) }
}
var cases: [(String, () throws -> Void)] = []
@MainActor func check(_ name: String, _ action: @escaping () throws -> Void) { cases.append((name, action)) }
let owner = SchedulingPrincipal("fixture-owner")
let other = SchedulingPrincipal("fixture-other")
func release(_ version: String = "2", build: String = "20", artifact: String = "digest-A",
             product: String = "app-A", scope: String = "private-target", edition: String = "standard",
             channel: String = "stable") -> ReleaseIdentity {
    ReleaseIdentity(product: product, scope: scope, release: version, build: build,
                    edition: edition, channel: channel, artifact: artifact)
}
func clock(_ utc: Int64 = 100, _ monotonic: Int64 = 10,
           boot: String = "boot-A", trusted: Bool = true) -> ClockSample {
    ClockSample(utc: utc, monotonic: monotonic, boot: boot, trustedUTC: trusted)
}
func conditions(_ identity: ReleaseIdentity = release(), target: String = "target-A") -> StartConditions {
    StartConditions(principal: owner, target: target, release: .verified(identity), route: .unattended,
                    eligibility: .eligible, targetClosed: .yes, awake: .yes, idle: .yes, clock: clock())
}
func optedIn() -> SchedulePolicy { SchedulePolicy(principal: owner, automaticEnabled: true) }
func paused() -> SchedulePolicy {
    SchedulePolicy(principal: owner, automaticEnabled: true,
                   pause: AutomaticPause(resumeUTC: 200, displayZone: "Europe/Isle_of_Man", anchor: clock()))
}
func entry(_ id: String = "A", identity: ReleaseIdentity = release()) -> QueueEntry {
    QueueEntry(id: id, target: "target-\(id)", release: identity)
}
func started(_ result: QueueStart) throws -> QueueAttempt {
    guard case .started(let attempt) = result else {
        throw CheckFailure(description: "Expected started attempt, received \(result)")
    }
    return attempt
}

registerTimingChecks()
registerQueueChecks()
var failures = 0
for (name, action) in cases {
    do { try action(); print("PASS scheduling: \(name)") }
    catch { failures += 1; print("FAIL scheduling: \(name): \(error)") }
}
print("Pure scheduling fixtures: \(cases.count) cases, \(failures) failures. No native scheduling or installation authority.")
exit(failures == 0 ? 0 : 1)
