import Foundation
import PatchedScheduling
@_spi(Testing) import PatchedUpdatePreferences

struct CheckFailure: Error { let message: String }
@MainActor final class Checks {
    var setupCount = 0; var setupFailures = 0; var behaviorCount = 0; var behaviorFailures = 0
    func run(_ name: String, setup: Bool = false, _ body: () throws -> Void) {
        if setup { setupCount += 1 } else { behaviorCount += 1 }
        do { try body(); print("PASS \(setup ? "SETUP" : "BEHAVIOR") \(name)") }
        catch {
            if setup { setupFailures += 1 } else { behaviorFailures += 1 }
            print("FAIL \(setup ? "SETUP" : "BEHAVIOR") \(name): \(error)")
        }
    }
}
func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !value() { throw CheckFailure(message: message) }
}
let owner = SchedulingPrincipal("synthetic-owner")
let storeScope = "synthetic-store"
let generation = "generation-1"
let release = ReleaseIdentity(product: "app", scope: "user", release: "2", build: "20", edition: "standard", channel: "stable", artifact: "digest-2")
func candidate(scope: String = "user", version: String = "2", build: String = "20", edition: String = "standard", channel: String = "stable", artifact: String = "digest-2") -> ReleaseIdentity {
    ReleaseIdentity(product: "app", scope: scope, release: version, build: build, edition: edition, channel: channel, artifact: artifact)
}
func conditions(_ value: ReleaseIdentity = release, principal: SchedulingPrincipal = owner, target: String = "fixture-target") -> StartConditions {
    StartConditions(principal: principal, target: target, release: .verified(value), route: .unattended,
                    eligibility: .eligible, targetClosed: .yes, awake: .yes, idle: .yes,
                    clock: ClockSample(utc: 100, monotonic: 10, boot: "synthetic-boot", trustedUTC: true))
}
@MainActor func session(_ store: any PreferenceStore, principal: SchedulingPrincipal = owner,
                        scope: String = storeScope, gen: String = generation, queue: String = "queue-1") -> PreferenceSession {
    PreferenceSession(store: store, principal: principal, storeScope: scope, generation: gen, queueID: queue)
}
@MainActor func loaded(_ bytes: Data = fixtureBytes()) -> (PreferenceSession, MemoryStore) {
    let store = MemoryStore(bytes: bytes); let value = session(store)
    _ = value.reload(generation: generation)
    return (value, store)
}
@MainActor func edit(_ value: PreferenceSession, _ change: PreferenceChange, id: String = "mutation-1", revision: UInt64 = 0, gen: String = generation) -> PreferenceEditResult {
    value.edit(change, mutationID: id, expectedRevision: revision, generation: gen)
}
@MainActor func enqueue(_ value: PreferenceSession, _ identity: ReleaseIdentity = release, id: String = "entry", principal: SchedulingPrincipal = owner) -> Bool {
    value.enqueue(QueueEntry(id: id, target: "fixture-target", release: identity), principal: principal, generation: generation)
}
@MainActor func start(_ value: PreferenceSession, _ identity: ReleaseIdentity = release, kind: StartKind = .manual,
                      id: String = "entry", request: String = "request", principal: SchedulingPrincipal = owner,
                      gen: String = generation, automatic: Bool = true, pause: AutomaticPause? = nil) -> QueueStart {
    value.start(id: id, requestID: request, principal: principal, generation: gen, kind: kind,
                automaticEnabled: automatic, pause: pause, conditions: conditions(identity, principal: principal))
}
func isStarted(_ value: QueueStart) -> Bool { if case .started = value { return true }; return false }

// Independent literal bytes: no trailing newline. Same bytes are in records.json.
let emptyLiteral = #"{"exclusions":[],"mutations":[],"principal":"synthetic-owner","revision":0,"schema":1,"skips":[],"storeScope":"synthetic-store"}"#
func appObject(_ value: PreferenceAppKey) -> [String: Any] {
    ["product": value.product, "scope": value.scope, "edition": value.edition, "channel": value.channel]
}
func releaseObject(_ value: ReleaseIdentity) -> [String: Any] {
    ["product": value.product, "scope": value.scope, "release": value.release, "build": value.build,
     "edition": value.edition, "channel": value.channel, "artifact": value.artifact]
}
func canonical(_ object: Any) -> Data {
    // Test-owned independent fixture encoding. No production codec is called for expectations.
    try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
}
func operation(_ change: PreferenceChange) -> String {
    let object: [String: Any]
    switch change {
    case .exclusion(let key, let excluded): object = ["action": "exclusion", "app": appObject(key), "excluded": excluded]
    case .skip(let identity): object = ["action": "skip", "release": releaseObject(identity)]
    case .undo(let identity): object = ["action": "undo", "release": releaseObject(identity)]
    }
    return String(decoding: canonical(object), as: UTF8.self)
}
func fixtureBytes(principal: String = "synthetic-owner", scope: String = "synthetic-store", revision: UInt64 = 0,
                  exclusions: [PreferenceAppKey] = [], skips: [ReleaseIdentity] = [], mutations: [(String, PreferenceChange)] = []) -> Data {
    let keys = exclusions.map(appObject).sorted { canonical($0).lexicographicallyPrecedes(canonical($1)) }
    let identities = skips.map(releaseObject).sorted { canonical($0).lexicographicallyPrecedes(canonical($1)) }
    return canonical(["exclusions": keys, "mutations": mutations.map { ["id": $0.0, "operation": operation($0.1)] },
                      "principal": principal, "revision": NSNumber(value: revision), "schema": 1, "skips": identities, "storeScope": scope])
}
@MainActor func runAll() {
    let checks = Checks()
    recordChecks(checks); persistenceChecks(checks); raceChecks(checks); projectionChecks(checks)
    print("SETUP \(checks.setupCount) failures \(checks.setupFailures); BEHAVIOR \(checks.behaviorCount) failures \(checks.behaviorFailures)")
    if checks.setupFailures + checks.behaviorFailures > 0 { exit(1) }
}
MainActor.assumeIsolated { runAll() }
