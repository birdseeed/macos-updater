import Foundation
import Darwin
import PatchedLicensing

struct CheckFailure: Error, CustomStringConvertible { let description: String }
func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw CheckFailure(description: message) }
}
var cases: [(String, () throws -> Void)] = []
@MainActor func check(_ name: String, _ action: @escaping () throws -> Void) { cases.append((name, action)) }

// Explicit development mode writes only the private build fixture root.
if CommandLine.arguments.dropFirst() == ["--emit-fixture-vectors"] {
    let root = URL(fileURLWithPath: ".build/pat-2613-evidence/generated-vectors", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    for (name, bytes) in try wireVectors() { try bytes.write(to: root.appendingPathComponent(name + ".json")) }
    print("Emitted test-only vectors under .build/pat-2613-evidence/generated-vectors")
    exit(0)
}
if CommandLine.arguments.dropFirst() == ["--verify-fixture-corpus"] {
    try verifyFixtureCorpus()
    print("PASS licensing: fixed corpus signatures verify and checked-in exact wire bytes match")
    exit(0)
}
check("valid signed paid lease permits manual new start") {
    let result = try? decision()
    try expect(result == .permitted, "A valid fixture-signed paid lease before its deadline must permit a manual third-party new start")
}
registerLeaseChecks()
registerPolicyChecks()
registerClockChecks()
registerClientChecks()
registerStorageChecks()
registerSubscriptionSummaryChecks()
var failures = 0
for (name, action) in cases {
    do { try action(); print("PASS licensing: \(name)") }
    catch { failures += 1; print("FAIL licensing: \(name): \(error)") }
}
print("Pure licensing fixtures: \(cases.count) cases, \(failures) failures. No production trust or installation authority.")
exit(failures == 0 ? 0 : 1)
