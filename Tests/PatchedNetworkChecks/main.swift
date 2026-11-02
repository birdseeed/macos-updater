import Foundation
import Darwin
@_spi(Testing) import PatchedNetworking

struct CheckFailure: Error, CustomStringConvertible { let description: String }
func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure(description: message) }
}
var checks: [(String, () throws -> Void)] = []
@MainActor func check(_ name: String, _ body: @escaping () throws -> Void) { checks.append((name, body)) }
// Independent literal fixtures: expected decisions never come from candidate policy code.
let digestA = String(repeating: "a", count: 64)
let digestB = String(repeating: "b", count: 64)
func artifact() -> NetworkArtifact { NetworkArtifact(app: "fixture-app", version: "1", digest: digestA) }
func endpoints() -> [NetworkEndpoint] {
    [NetworkEndpoint(.catalogueFixture, .catalogue, .get), NetworkEndpoint(.artifactFixture, .artifact, .get),
     NetworkEndpoint(.supportFixture, .manualSupport, .post), NetworkEndpoint(.reportFixture, .failureReport, .post)]
}
func configuration(_ mode: NetworkMode = .system, host: String? = nil, port: Int? = nil,
                   reference: String? = nil, revision: UInt64 = 7) -> NetworkConfiguration {
    NetworkConfiguration(principal: .fixtureOwner, revision: revision, mode: mode,
                         host: host, port: port, credentialReference: reference)
}
func admission(_ purpose: NetworkPurpose = .catalogue, route: NetworkRoute = .systemDirect) -> NetworkAdmission {
    let destination: NetworkDestination
    let method: NetworkMethod
    switch purpose {
    case .catalogue: destination = .catalogueFixture; method = .get
    case .artifact: destination = .artifactFixture; method = .get
    case .manualSupport: destination = .supportFixture; method = .post
    case .failureReport: destination = .reportFixture; method = .post
    }
    let submission = purpose == .manualSupport || purpose == .failureReport
    return NetworkAdmission(principal: .fixtureOwner, revision: 7, purpose: purpose, destination: destination,
                            method: method, bodyDigest: submission ? digestA : nil, frozenBodyDigest: submission ? digestA : nil, now: 100, expires: 200,
                            route: route, path: .online, artifact: purpose == .artifact ? artifact() : nil,
                            consentGeneration: submission ? 3 : nil,
                            consent: submission ? NetworkConsent(principal: .fixtureOwner, purpose: purpose, generation: 3, allowed: true) : nil)
}
func override() -> NetworkLimitedOverride {
    NetworkLimitedOverride(principal: .fixtureOwner, revision: 7, purpose: .artifact,
                           destination: .artifactFixture, artifact: artifact(), expires: 150)
}
final class EffectSpy: NetworkConfigurationStore, SystemProxyResolver, ProxyCredentialProvider,
    NetworkPathSource, NetworkTransport, NetworkEffectSink {
    var calls: [String] = []
    func load() -> NetworkConfiguration? { calls.append("store"); return nil }
    func resolve(_ configuration: NetworkConfiguration) -> NetworkRoute { calls.append("resolver"); return .unavailable }
    func available(_ reference: String) -> Bool { calls.append("credentials"); return false }
    func current() -> NetworkPath { calls.append("path"); return .unknown }
    func dispatch(_ model: NetworkSyntheticModel) -> NetworkDispatchOutcome { calls.append("dispatch"); return .unavailable }
    func observe(_ effect: NetworkEffect) { calls.append(effect.rawValue) }
    var boundaries: NetworkBoundaries { NetworkBoundaries(store: self, resolver: self, credentials: self, path: self, transport: self, effects: self) }
}
func evaluate(_ config: NetworkConfiguration, _ observation: NetworkAdmission) throws -> NetworkDecision {
    let spy = EffectSpy()
    let policy = NetworkPolicy(syntheticEndpoints: endpoints(), boundaries: spy.boundaries)
    let result = policy.admit(configuration: config, observation: observation)
    try expect(spy.calls.isEmpty, "pure admission called an injected effect boundary")
    try expect(policy.dispatch(result) == .unavailable, "synthetic result enabled native dispatch")
    try expect(spy.calls.isEmpty, "dispatch called an injected effect boundary")
    return result
}
func permitted(_ config: NetworkConfiguration = configuration(), _ input: NetworkAdmission = admission()) throws {
    let decision = try evaluate(config, input)
    guard case .syntheticPermitted(let model) = decision else { throw CheckFailure(description: "expected SYNTHETIC permitted model") }
    try expect(model.marker.rawValue == "SYNTHETIC MODEL ONLY", "synthetic marker absent")
    try expect(model.principal == config.principal && model.revision == config.revision && model.purpose == input.purpose, "opaque model binding mismatch")
    try expect(!model.grantsNativeAuthority && !model.grantsInstallationAuthority, "model granted authority")
}
func refused(_ config: NetworkConfiguration = configuration(), _ input: NetworkAdmission,
             _ reason: NetworkRefusal) throws {
    let decision = try evaluate(config, input)
    try expect(decision == .refused(reason), "expected finite refusal \(reason.rawValue)")
}
registerPolicyChecks()
registerDenialChecks()
registerSecretChecks()
// PAT-2666 additive independent native settings contract checks.
registerNativeSettingsChecks()
var failures = 0
for (name, body) in checks {
    do { try body(); print("PASS network: \(name)") }
    catch { failures += 1; print("FAIL network: \(name): \(error)") }
}
print("Synthetic network model: \(checks.count) checks, \(failures) failures. No native transport or installation authority.")
exit(failures == 0 ? 0 : 1)
