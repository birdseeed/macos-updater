import Foundation
import Darwin
@_spi(Testing) import PatchedLicenceSupport
struct CheckFailure: Error, CustomStringConvertible { let description: String }
func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !value() { throw CheckFailure(description: message) }
}
func refuses(_ error: SupportError, _ body: () throws -> Void) throws {
    do { try body(); throw CheckFailure(description: "Expected \(error.rawValue)") }
    catch let actual as SupportError { try expect(actual == error, "Expected \(error.rawValue), received \(actual.rawValue)") }
}
var checks: [(String, () throws -> Void)] = []
@MainActor func check(_ name: String, _ body: @escaping () throws -> Void) { checks.append((name, body)) }
check("valid exact independent descriptor produces positive confirmation") {
    let v = try vector("deactivateActivation")
    let c = try decoded(Data(v.bytes.utf8), expected: v.sha256)
    try expect(c.action == .deactivateActivation && c.account.accountID == account && c.digest == v.sha256,
               "Valid descriptor must prepare the exact target")
}
registerDescriptorChecks()
registerContextChecks()
registerTransactionChecks()
registerRecoveryChecks()
registerHardeningChecks()
var failed = 0
for (name, body) in checks {
    do { try body(); print("PASS support: \(name)") }
    catch { failed += 1; print("FAIL support: \(name): \(error)") }
}
print("Pure support fixtures: \(checks.count) cases, \(failed) failures. No service authority, ownership proof, email or provider effects.")
exit(failed == 0 ? 0 : 1)
