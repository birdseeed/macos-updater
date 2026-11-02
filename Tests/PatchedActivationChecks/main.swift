import Foundation
import Darwin
@_spi(Testing) import PatchedActivation

struct CheckFailure: Error, CustomStringConvertible { let description: String }
func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !value() { throw CheckFailure(description: message) }
}
func refuses(_ expected: ActivationError, _ body: () throws -> Void) throws {
    do { try body(); throw CheckFailure(description: "Expected refusal \(expected)") }
    catch let error as ActivationError {
        try expect(error == expected, "Expected \(expected), received \(error)")
    }
}
var checks: [(String, () throws -> Void)] = []
@MainActor func check(_ name: String, _ body: @escaping () throws -> Void) { checks.append((name, body)) }

if CommandLine.arguments.dropFirst() == ["--emit-fixed-proof-replay"] {
    let bytes = try Data(contentsOf: URL(fileURLWithPath: "Fixtures/Activation/ci-refused-20261009.json"))
    let input = try JSONDecoder().decode(FixedProofReplayInput.self, from: bytes)
    let report = FixedProofReplay.inspect(input)
    guard report.availability == .complete else { throw CheckFailure(description: "Fresh-process replay unavailable") }
    print(try FixedProofReplay.render(report))
    // Independent Node verification confirms this n-S companion; the original fixture stays exact.
    var companion = input
    companion.signature = Data(base64Encoded: "A+s7gmPf/lMkzw6G4QrHvkYYWdRL1FfBj0jY8BYMi3GOfZMdSBUpjPsHdRTuwIm1kiVY8NLw+wSglh+1HX8KAg==")!
    print("Fixed-proof diagnostic variant: s-complement; original body unchanged")
    print(try FixedProofReplay.render(FixedProofReplay.inspect(companion)))
    exit(0)
}

if CommandLine.arguments.dropFirst() == ["--emit-fixture-vectors"] {
    let root = URL(fileURLWithPath: ".build/pat-2615-evidence/generated-vectors", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                          attributes: [.posixPermissions: 0o700])
    for vector in try referenceVectors() {
        let bytes = try JSONEncoder().encode(vector)
        try bytes.write(to: root.appendingPathComponent(vector.name + ".json"))
    }
    print("Generated public fixture vectors under .build/pat-2615-evidence/generated-vectors")
    exit(0)
}
check("valid independent P256 fixture proof verifies") {
    let fixture = try ProofFixture()
    try PossessionProof.verify(actionBytes: fixture.action, signature: fixture.signature,
                               context: fixture.context, now: 1_000)
}
registerWireChecks()
registerIdentityChecks()
registerLedgerChecks()
registerRaceChecks()
registerRecoveryChecks()
registerHardeningChecks()
registerDiagnosticChecks()
registerDiagnosticSafetyChecks()
registerFixedProofReplayChecks()
registerP256CompatibilityChecks()
registerBidirectionalProofChecks()
if CommandLine.arguments.dropFirst() == ["--diagnostic-force-proof-refusal"] {
    check("forced public fixture proof refusal") {
        var fixture = try LedgerFixture(); _ = try fixture.prepare()
        throw ActivationError.proofRefused
    }
}
var failed = 0
for (name, body) in checks {
    FixtureDiagnostics.reset()
    do { try runFixtureDiagnosticCase(body); print("PASS activation: \(name)") }
    catch { failed += 1; print("FAIL activation: \(name): \(error)") }
}
print("Pure activation fixtures: \(checks.count) cases, \(failed) failures. No native key, D1 concurrency or installation proof.")
exit(failed == 0 ? 0 : 1)
