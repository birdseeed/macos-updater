import Foundation
import ArtifactInspection

@MainActor func addStrengtheningChecks() {
    addEncodingChecks()
    addSpawnFailureCheck()
    check("reverse duplicate schema still refused when final value valid") {
        let text = String(decoding: try Data(contentsOf: recordPath), as: UTF8.self)
            .replacingOccurrences(of: "\"schemaVersion\": 1", with: "\"schemaVersion\": 2, \"schemaVersion\": 1")
        try refuses(.invalidRecord) { _ = try FirefoxTargets.verifyRecord(Data(text.utf8)) }
    }
    check("escaped duplicate schema refused") {
        let text = String(decoding: try Data(contentsOf: recordPath), as: UTF8.self)
            .replacingOccurrences(of: "\"schemaVersion\": 1", with: #""\u0073chemaVersion": 2, "schemaVersion": 1"#)
        try refuses(.invalidRecord) { _ = try FirefoxTargets.verifyRecord(Data(text.utf8)) }
    }
    for key in ["sha256", "url"] {
        check("nested duplicate target \(key) refused when final value valid") {
            let text = String(decoding: try Data(contentsOf: recordPath), as: UTF8.self)
                .replacingOccurrences(of: "\"\(key)\":", with: "\"\(key)\": \"wrong\", \"\(key)\":")
            try refuses(.invalidRecord) { _ = try FirefoxTargets.verifyRecord(Data(text.utf8)) }
        }
    }
    check("nested duplicate raw command exit refused") {
        let text = String(decoding: try JSONEncoder().encode(evidence()), as: UTF8.self)
            .replacingOccurrences(of: "\"exitCode\":0", with: "\"exitCode\":1,\"exitCode\":0")
        try refuses(.invalidRecord) { _ = try EvidenceEvaluator.replay(Data(text.utf8), pin: old) }
    }
    check("self-asserted fresh validation added to raw evidence refused") {
        var raw = try object(JSONEncoder().encode(evidence())); raw["freshOSValidation"] = true
        try refuses(.invalidRecord) { _ = try EvidenceEvaluator.replay(json(raw), pin: old) }
    }
    check("descendant holding pipes cannot outlive command deadline") {
        var limits = InspectionLimits(); limits.commandSeconds = 0.1
        let start = Date()
        let result = try BoundedCommandRunner().run(executable: "/bin/sh", arguments: ["-c", "sleep 10 & exit 0"], limits: limits)
        try expect(result.timedOut && Date().timeIntervalSince(start) < 2, "Inherited pipes must be bounded after parent exit")
    }
}
