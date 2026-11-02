import Foundation
@_spi(Testing) import PatchedDisposableProof

// CHECK-ADDED PAT-2710: literal synthetic report compatibility only. These
// dictionaries are never native evidence and cannot issue installed authority.
private func installedSignatureProjectionReport() -> [String: Any] {
    var object = currentArchitectureProjectionReport()
    var observations = object["appObservations"] as! [[String: Any]]
    observations[0]["observedAt"] = "2026-10-20T00:00:02Z"
    observations[0]["signatureObservation"] = [
        "appPath": target,
        "requirement": "anchor apple generic and certificate leaf[subject.OU] = \"43AQ936H96\" and identifier \"org.mozilla.firefox\"",
        "validationFlags": 25, "validationStatus": 0, "signingInformationStatus": 0,
        "teamID": "43AQ936H96", "identifier": "org.mozilla.firefox",
        "startedAt": "2026-10-20T00:00:00Z", "finishedAt": "2026-10-20T00:00:01Z"
    ] as [String: Any]
    object["appObservations"] = observations
    return object
}

@MainActor func registerInstalledSignatureProjectionChecks() {
    let prefix = "PAT-2710 installed signature: "
    check(prefix + "structured current observation projects through synthetic completion") {
        try compare(installedSignatureProjectionReport(), physical: readback())
    }
    check(prefix + "legacy architecture fixture remains synthetic-compatible") {
        try compare(currentArchitectureProjectionReport(), physical: readback())
    }
    check(prefix + "legacy empty fixture remains synthetic-compatible") {
        try compare(report(), physical: readback())
    }
    let mutations: [(String, (inout [String: Any]) -> Void)] = [
        ("wrong path", { $0["appPath"] = "/Applications/Firefox.app" }),
        ("path wrong type", { $0["appPath"] = 42 }),
        ("weakened requirement", { $0["requirement"] = "anchor apple generic" }),
        ("wrong requirement team", { $0["requirement"] = "anchor apple generic and certificate leaf[subject.OU] = \"AAAAAAAAAA\" and identifier \"org.mozilla.firefox\"" }),
        ("requirement wrong type", { $0["requirement"] = true }),
        ("missing nested-code flag", { $0["validationFlags"] = 9 }),
        ("extra flag", { $0["validationFlags"] = 57 }),
        ("boolean flags", { $0["validationFlags"] = true }),
        ("string flags", { $0["validationFlags"] = "25" }),
        ("failed validation", { $0["validationStatus"] = -67050 }),
        ("failed signing information", { $0["signingInformationStatus"] = -50 }),
        ("boolean validation status", { $0["validationStatus"] = false }),
        ("boolean signing status", { $0["signingInformationStatus"] = false }),
        ("string validation status", { $0["validationStatus"] = "0" }),
        ("wrong team", { $0["teamID"] = "AAAAAAAAAA" }),
        ("wrong identifier", { $0["identifier"] = "org.other.firefox" }),
        ("empty start", { $0["startedAt"] = "" }),
        ("invalid start", { $0["startedAt"] = "yesterday" }),
        ("invalid finish", { $0["finishedAt"] = "tomorrow" }),
        ("reversed timestamps", { $0["finishedAt"] = "2026-10-19T23:59:59Z" }),
        ("numeric timestamp", { $0["finishedAt"] = 0 }),
        ("unknown signature field", { $0["installationAuthorized"] = true })
    ]
    for (name, mutate) in mutations {
        check(prefix + "refuses " + name) {
            var object = installedSignatureProjectionReport()
            var observations = object["appObservations"] as! [[String: Any]]
            var signature = observations[0]["signatureObservation"] as! [String: Any]
            mutate(&signature)
            observations[0]["signatureObservation"] = signature
            object["appObservations"] = observations
            try refusal(.notAuthorized) { try compare(object) }
        }
    }
    for key in ["appPath", "requirement", "validationFlags", "validationStatus", "signingInformationStatus",
                "teamID", "identifier", "startedAt", "finishedAt"] {
        check(prefix + "refuses missing " + key) {
            var object = installedSignatureProjectionReport()
            var observations = object["appObservations"] as! [[String: Any]]
            var signature = observations[0]["signatureObservation"] as! [String: Any]
            signature.removeValue(forKey: key)
            observations[0]["signatureObservation"] = signature
            object["appObservations"] = observations
            try refusal(.notAuthorized) { try compare(object) }
        }
    }
    for value in [NSNull(), "reported valid", 1, [Any]()] as [Any] {
        check(prefix + "refuses non-object signature " + String(describing: value)) {
            var object = installedSignatureProjectionReport()
            var observations = object["appObservations"] as! [[String: Any]]
            observations[0]["signatureObservation"] = value
            object["appObservations"] = observations
            try refusal(.notAuthorized) { try compare(object) }
        }
    }
    check(prefix + "refuses duplicate signature key in raw durable JSON") {
        let bytes = try json(installedSignatureProjectionReport())
        let original = Data("\"validationFlags\":25".utf8)
        guard let range = bytes.range(of: original) else { throw CheckFailure(description: "Literal signature fixture lacks unique flags") }
        var changed = bytes
        changed.replaceSubrange(range, with: Data("\"validationFlags\":0,\"validationFlags\":25".utf8))
        try refusal(.notAuthorized) {
            try compare(installedSignatureProjectionReport(), stdoutOverride: changed + Data([10]), durableOverride: changed)
        }
    }
}
