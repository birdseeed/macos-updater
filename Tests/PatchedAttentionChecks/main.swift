import Foundation
import Darwin
import PatchedScheduling

struct AttentionCheckFailure: Error, CustomStringConvertible { let description: String }
func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw AttentionCheckFailure(description: message) }
}
var checks: [(String, () throws -> Void)] = []
@MainActor func check(_ name: String, _ action: @escaping () throws -> Void) { checks.append((name, action)) }
let owner = SchedulingPrincipal("attention-fixture-owner")
let foreign = SchedulingPrincipal("attention-fixture-foreign")
func release(_ version: String = "2", build: String = "20", artifact: String = "artifact-two",
             product: String = "fixture-app", scope: String = "user", edition: String = "standard",
             channel: String = "stable") -> ReleaseIdentity {
    ReleaseIdentity(product: product, scope: scope, release: version, build: build,
                    edition: edition, channel: channel, artifact: artifact)
}
func clock(_ utc: Int64 = 100, _ monotonic: Int64 = 10, boot: String = "boot-one",
           trusted: Bool = true) -> ClockSample {
    ClockSample(utc: utc, monotonic: monotonic, boot: boot, trustedUTC: trusted)
}
func requirements(_ restart: AttentionRequirement = .notRequired,
                  _ interaction: AttentionRequirement = .notRequired) -> AttentionRequirements {
    AttentionRequirements(restart: restart, interaction: interaction)
}
func binding(_ requirements: AttentionRequirements = requirements(), principal: SchedulingPrincipal = owner,
             target: String = "target-one", identity: ReleaseIdentity = release(), routeID: String = "route-one",
             revision: UInt64 = 1, session: UInt64 = 1) -> AttentionBinding {
    AttentionBinding(principal: principal, target: target, release: identity, routeID: routeID,
                     requirements: requirements, observationRevision: revision, sessionGeneration: session)
}
func observation(_ binding: AttentionBinding = binding(), permission: AttentionPermission = .granted,
                 helper: AttentionHelper = .notRequired, time: ClockSample = clock()) -> AttentionObservation {
    let route: InstallationRoute = binding.requirements.interaction == .required ? .interactive :
        (binding.requirements.restart == .required ? .restartRequired : .unattended)
    let conditions = StartConditions(principal: binding.principal, target: binding.target,
        release: .verified(binding.release), route: route, eligibility: .eligible,
        targetClosed: .yes, awake: .yes, idle: .yes, clock: time)
    return AttentionObservation(binding: binding, permission: permission, helper: helper,
        conditions: conditions, policy: SchedulePolicy(principal: binding.principal, automaticEnabled: true))
}
func controller(_ observation: AttentionObservation = observation()) throws -> AttentionController {
    var value = AttentionController(principal: owner)
    try expect(value.refresh(observation), "valid synthetic observation accepted")
    return value
}
func isBlocked(_ decision: AttentionDecision) -> Bool {
    if case .blocked = decision { return true }; return false
}
func hasReason(_ controller: AttentionController, _ reason: AttentionReason) -> Bool {
    controller.presentation.reasons.contains(reason)
}
func launched(_ controller: inout AttentionController, _ binding: AttentionBinding) throws -> AttentionAttempt {
    guard let attempt = controller.requestManualStart(binding: binding) else {
        throw AttentionCheckFailure(description: "explicit exact synthetic launch must produce an opaque model attempt")
    }
    return attempt
}
func installed(_ binding: AttentionBinding, pending: KnownSignal = .no,
               identity: ReleaseIdentity = release()) -> AttentionInstalledReadback {
    AttentionInstalledReadback(binding: binding, installedRelease: identity, restartPending: pending)
}

registerPermissionChecks()
registerConsentChecks()
registerInstallerChecks()
registerBoundaryChecks()
registerRestartReadbackChecks()
registerUnexpectedRestartChecks()
var failures = 0
for (name, action) in checks {
    do { try action(); print("PASS attention: \(name)") }
    catch { failures += 1; print("FAIL attention: \(name): \(error)") }
}
print("Pure injected attention model: \(checks.count) cases, \(failures) failures. No operating evidence or installation authority.")
exit(failures == 0 ? 0 : 1)
