import Foundation
@_spi(Testing) import PatchedDisposableProof

// Literal current schema through the public Testing facade. This synthetic
// nonempty observation grants no native trust or installation authority.
func currentArchitectureProjectionReport() -> [String: Any] {
    var object = report()
    let manifests = object["bundleManifests"] as! [String: Any]
    let observation: [String: Any] = [
        "path": target, "version": "157.0.1", "bundleID": "org.mozilla.firefox", "teamID": "43AQ936H96",
        "observedAt": "2026-10-20T00:00:00Z", "commands": [object["harnessSigningObservation"] as! [String: Any]],
        "manifest": manifests["after"]!,
        "architectureObservation": ["executablePath": target + "/Contents/MacOS/firefox", "architectures": ["arm64", "x86_64"]]
    ]
    // Existing zero-entry manifests remain valid synthetic schema fixtures.
    // This API compares report consistency; it does not issue a live capability.
    object["appObservations"] = [observation]
    return object
}

@MainActor func registerArchitectureReportCompatibilityChecks() {
    check("current nonempty architecture report projects through public synthetic completion") {
        try compare(currentArchitectureProjectionReport(), physical: readback())
    }
    let observationMutations: [(String, (inout [String: Any]) -> Void)] = [
        ("legacy seven-key observation", { $0.removeValue(forKey: "architectureObservation") }),
        ("unknown observation field", { $0["unknown"] = true }),
        ("wrong architecture observation type", { $0["architectureObservation"] = "arm64,x86_64" }),
        ("command unknown field", { o in
            var commands = o["commands"] as! [[String: Any]]; commands[0]["unknown"] = true; o["commands"] = commands
        }),
        ("command missing field", { o in
            var commands = o["commands"] as! [[String: Any]]; commands[0].removeValue(forKey: "arguments"); o["commands"] = commands
        }),
        ("manifest unknown field", { o in
            var manifest = o["manifest"] as! [String: Any]; manifest["unknown"] = true; o["manifest"] = manifest
        }),
        ("manifest missing field", { o in
            var manifest = o["manifest"] as! [String: Any]; manifest.removeValue(forKey: "totalBytes"); o["manifest"] = manifest
        })
    ]
    for (name, mutate) in observationMutations {
        check("current nonempty report refuses " + name) {
            var object = currentArchitectureProjectionReport()
            var observations = object["appObservations"] as! [[String: Any]]
            mutate(&observations[0]); object["appObservations"] = observations
            try refusal(.notAuthorized) { try compare(object) }
        }
    }
    let architectureMutations: [(String, (inout [String: Any]) -> Void)] = [
        ("missing executable path", { $0.removeValue(forKey: "executablePath") }),
        ("missing architecture field", { $0.removeValue(forKey: "architectures") }),
        ("unknown architecture field", { $0["unknown"] = true }),
        ("wrong executable path", { $0["executablePath"] = "/Applications/Firefox.app/Contents/MacOS/firefox" }),
        ("wrong executable path type", { $0["executablePath"] = 1 }),
        ("duplicate architectures", { $0["architectures"] = ["arm64", "arm64", "x86_64"] }),
        ("reversed architectures", { $0["architectures"] = ["x86_64", "arm64"] }),
        ("missing architecture member", { $0["architectures"] = ["arm64"] }),
        ("empty architectures", { $0["architectures"] = [String]() }),
        ("extra architecture member", { $0["architectures"] = ["arm64", "x86_64", "i386"] }),
        ("unknown architecture name", { $0["architectures"] = ["arm64", "x86_64h"] }),
        ("wrong architecture scalar type", { $0["architectures"] = "arm64,x86_64" }),
        ("wrong architecture element type", { $0["architectures"] = ["arm64", 1] as [Any] })
    ]
    for (name, mutate) in architectureMutations {
        check("current nonempty report refuses " + name) {
            var object = currentArchitectureProjectionReport()
            var observations = object["appObservations"] as! [[String: Any]]
            var architecture = observations[0]["architectureObservation"] as! [String: Any]
            mutate(&architecture); observations[0]["architectureObservation"] = architecture; object["appObservations"] = observations
            try refusal(.notAuthorized) { try compare(object) }
        }
    }
}
