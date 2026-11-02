import Foundation
@_spi(Testing) import PatchedActivation

@MainActor func registerDiagnosticSafetyChecks() {
    for malformed in [false, true] {
        check("diagnostic failed capture replaces prior success: malformed=\(malformed)") {
            var f = try DiagnosticInput(); try f.capture(); _ = try decodedDiagnostic()
            if malformed { f.context.accountID = "invalid" }
            else { f.attempt.body = Data(repeating: 65, count: 65_537) }
            try? f.capture()
            let reason = malformed ? "input-shape" : "input-bound"
            try expect(try FixtureDiagnostics.render() == "{\"diagnostic\":\"unavailable\",\"reason\":\"" + reason + "\"}",
                       "Failed capture retained preceding exact proof")
        }
    }
    check("diagnostic custom reporter output remains bounded") {
        var lines: [String] = []
        try refuses(.proofRefused) {
            try runFixtureDiagnosticCase({ throw ActivationError.proofRefused }, emit: { lines.append($0) },
                report: { String(repeating: "x", count: 65_537) })
        }
        try expect(lines == ["{\"diagnostic\":\"unavailable\",\"reason\":\"output-bound\"}"], "Reporter bypassed output bound")
    }
}
