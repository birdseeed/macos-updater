import Foundation
import Darwin
@_spi(Testing) import PatchedCore

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.count == 2 && arguments[0] == "--restart-probe" {
    do {
        let root = URL(fileURLWithPath: arguments[1])
        let result = try Fixture.verifier(root).verify(envelope: Fixture.envelope(), now: Fixture.now)
        try expect(result.sequence == 7 && result.origin == "fixture" && !result.freshOSValidation && !result.installationAuthorized,
                   "Incorrect fixture result after process restart")
        try assertCheckpoint(root, sequence: 7, payload: json(Fixture.payload()))
        print("fixture restart accepted sequence 7; no OS or installation trust")
        exit(0)
    } catch { print("fixture restart refused: \(error)"); exit(1) }
}
if arguments.count == 2 && arguments[0] == "--locked-probe" {
    do {
        try refuses(.stateBusy) { _ = try Fixture.verifier(URL(fileURLWithPath: arguments[1])).verify(envelope: Fixture.envelope(), now: Fixture.now) }
        print("fixture concurrent state writer refused")
        exit(0)
    } catch { print("fixture lock probe failed: \(error)"); exit(1) }
}

var cases: [(String, () throws -> Void)] = []
@MainActor func check(_ name: String, _ action: @escaping () throws -> Void) { cases.append((name, action)) }
if arguments == ["--size-policy"] {
    registerSizePolicyCatalogueChecks()
    var failures = 0
    for (name, action) in cases {
        do { try action(); print("PASS fixture: \(name)") }
        catch { failures += 1; print("FAIL fixture: \(name): \(error)") }
    }
    print("PAT-2709 catalogue: \(cases.count) cases, \(failures) failures")
    exit(failures == 0 ? 0 : 1)
}
registerSizePolicyCatalogueChecks()
registerCatalogueChecks()
registerStateChecks()
registerArtifactChecks()
var failures = 0
for (name, action) in cases {
    do { try action(); print("PASS fixture: \(name)") }
    catch { failures += 1; print("FAIL fixture: \(name): \(error)") }
}
print("Fixture core acceptance: \(cases.count) cases, \(failures) failures. No fresh OS trust or installed success.")
exit(failures == 0 ? 0 : 1)
