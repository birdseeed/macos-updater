import Foundation
import Darwin
@_spi(Testing) import PatchedCore

// Acceptance checks for the PAT-2582 fixture transaction and its presentation.
// Every write is confined to new disposable directories beneath this worktree's
// .build. No app is launched, no installed app or profile is read or changed.
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.count == 2 && arguments[0] == "--recover-probe" {
    // An independent process with no state from the interrupted writer.
    do {
        let authority = try FixtureAuthority.reopenRoot(path: arguments[1])
        let report = try authority.recover(transactionDirectory: arguments[1] + "/Transaction", hooks: idle())
        print("state=\(report.state.rawValue) action=\(report.recoveryAction.rawValue) origin=\(report.origin) " +
              "freshOSValidation=\(report.freshOSValidation) installationAuthorized=\(report.installationAuthorized) " +
              "installedFirefoxProof=\(report.installedFirefoxProof)")
        exit(0)
    } catch let error as TransactionFailure { print("refused=\(error.rawValue)"); exit(1) }
    catch { print("failed=\(error)"); exit(3) }
}

var cases: [(String, () throws -> Void)] = []
@MainActor func check(_ name: String, _ action: @escaping () throws -> Void) { cases.append((name, action)) }
registerHarnessChecks()
registerAuthorityChecks()
registerSuccessChecks()
registerHazardChecks()
registerFaultChecks()
registerRecoveryChecks()
registerPresentationChecks()
registerPathEncodingChecks() // CHECK-ADDED
registerBoundaryRegressionChecks() // CHECK-ADDED
var failures = 0
for (name, action) in cases {
    do { try action(); print("PASS transaction: \(name)") }
    catch { failures += 1; print("FAIL transaction: \(name): \(error)") }
}
print("Fixture transaction acceptance: \(cases.count) cases, \(failures) failures. No fresh OS trust, installed update or Firefox proof.")
exit(failures == 0 ? 0 : 1)
