import Foundation
import Darwin

struct Failure: Error, CustomStringConvertible { let description: String }
func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !value() { throw Failure(description: message) }
}
func refused(_ body: () throws -> Void) throws {
    do { try body() } catch { return }
    throw Failure(description: "Operation unexpectedly accepted")
}
var cases: [(String, Bool, @MainActor () throws -> Void)] = []
@MainActor func check(_ name: String, setup: Bool = false, _ body: @escaping @MainActor () throws -> Void) {
    cases.append((name, setup, body))
}
registerHistoryChecks()
registerHelpContextChecks()
registerOffscreenChecks()
registerReasonChecks()
registerNativeFileStoreChecks()
var failures = 0
var setupFailures = 0
for (name, setup, body) in cases {
    do { try body(); print("PASS activity: \(name)") }
    catch { failures += 1; if setup { setupFailures += 1 }; print("FAIL activity: \(name): \(error)") }
}
print("Activity fixture checks: \(cases.count) cases, \(failures) failures; \(cases.filter { $0.1 }.count) setup controls, \(setupFailures) setup failures. No native installation, app relaunch or support delivery proved.")
exit(failures == 0 ? 0 : 1)
