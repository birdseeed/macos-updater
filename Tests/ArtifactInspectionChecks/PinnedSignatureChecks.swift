import Foundation
import Darwin
import ArtifactInspection

// Synthetic observations only. No case creates fresh OS or installation authority.
@MainActor func runPinnedSignatureChecks() -> Never {
    let pin = FirefoxTargets.pins[0]
    let app = "/fixture/private/mount/Firefox.app", dmg = "/fixture/private/Firefox.dmg"
    // Independent oracle: never obtain an expected string or flags from the builder.
    let requirement = "anchor apple generic and certificate leaf[subject.OU] = \"43AQ936H96\" and identifier \"org.mozilla.firefox\""
    var cases: [(String, () throws -> Void)] = []
    func add(_ name: String, _ body: @escaping () throws -> Void) { cases.append((name, body)) }
    func sample() throws -> AppEvidence {
        AppEvidence(appPath: app, dmgPath: dmg, infoPlist: try plist([
            "CFBundleIdentifier": pin.bundleID, "CFBundleShortVersionString": pin.version,
            "CFBundleExecutable": "firefox", "CFBundlePackageType": "APPL"]), commands: [
                "imageVerify": .init(executable: "/usr/bin/hdiutil", arguments: ["verify", dmg]),
                "gatekeeper": .init(executable: "/usr/sbin/spctl", arguments: ["--assess", "--type", "execute", "--verbose=4", app],
                    stderr: app + ": accepted\nsource=Notarized Developer ID\n"),
                "containerSignature": .init(executable: "/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", dmg], exitCode: 1),
                "containerGatekeeper": .init(executable: "/usr/sbin/spctl", arguments: ["--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=4", dmg], exitCode: 3)],
            schemaVersion: 3, architectureObservation: .init(executablePath: app + "/Contents/MacOS/firefox", architectures: ["arm64", "x86_64"]),
            signatureObservation: .init(appPath: app, requirement: requirement, validationFlags: 25,
                validationStatus: 0, signingInformationStatus: 0, teamID: "43AQ936H96", identifier: "org.mozilla.firefox",
                startedAt: "2026-10-07T14:35:32Z", finishedAt: "2026-10-07T14:35:33Z"))
    }
    func evaluate(_ item: AppEvidence, replay: Bool) throws -> Assessment {
        try (replay ? EvidenceEvaluator.replay(JSONEncoder().encode(item), pin: pin) : EvidenceEvaluator.evaluateFixture(item, pin: pin))
    }
    func reject(_ name: String, _ reason: InspectionFailure, replayReason: InspectionFailure? = nil,
                _ change: @escaping (inout AppEvidence) throws -> Void) {
        for replay in [false, true] {
            add("\(name) replay=\(replay)") {
                var item = try sample(); try change(&item)
                try refuses(replay ? replayReason ?? reason : reason) { _ = try evaluate(item, replay: replay) }
            }
        }
    }
    // These two positive controls must be the first failures on the refusing Phase A.
    for replay in [false, true] {
        add("schema3 structured positive replay=\(replay)") {
            let result = try evaluate(sample(), replay: replay)
            try expect(result.appChecksPassed && result.origin == (replay ? .replayed : .fixture) &&
                !result.freshOSValidation && !result.installationAuthorized && !result.containerTicketPassed &&
                !result.containerSignaturePassed && !result.containerGatekeeperPassed,
                "Structured acceptance lost origin, container refusals or authority boundaries")
        }
    }
    add("pin requirement literal and flags") {
        let actual = try PinnedSignatureRequirement.make(teamID: pin.teamID, bundleID: pin.bundleID)
        try expect(actual == requirement,
                   "Requirement must pin Apple anchor, leaf team and exact identifier")
        try expect(PinnedSignatureRequirement.validationFlags == UInt32(25), "All three validation options required")
    }
    for team in ["", "43AQ936H9", "43AQ936H960", "43aq936h96", "43AQ936H9é", "43AQ936H9\"", "43AQ936H9\n", "43AQ936H9\\", "AAAAAAAAA "] {
        add("refuse team grammar \(String(reflecting: team))") {
            try refuses(.invalidMetadata) { _ = try PinnedSignatureRequirement.make(teamID: team, bundleID: pin.bundleID) }
        }
    }
    for bundle in ["", "firefox", ".firefox", "org.", "org..firefox", "org.mo zilla", "org.é", "org.firefox\n", "org.firefox\" or true", "org.firefox\\", String(repeating: "a", count: 254) + ".b"] {
        add("refuse identifier grammar \(bundle.utf8.count) \(String(reflecting: String(bundle.prefix(40))))") {
            try refuses(.invalidMetadata) { _ = try PinnedSignatureRequirement.make(teamID: pin.teamID, bundleID: bundle) }
        }
    }
    for bundle in ["a.b", "org.mozilla.firefox", "a-b.c9", String(repeating: "a", count: 253) + ".b"] {
        add("valid identifier grammar length \(bundle.count)") {
            let expected = "anchor apple generic and certificate leaf[subject.OU] = \"43AQ936H96\" and identifier \"" + bundle + "\""
            let actual = try PinnedSignatureRequirement.make(teamID: pin.teamID, bundleID: bundle)
            try expect(actual == expected, "Valid ASCII pin changed")
        }
    }
    reject("missing signature observation", .missingEvidence, replayReason: .invalidRecord) { $0.signatureObservation = nil }
    for status in [Int32(-67050), 1] {
        reject("validation failure \(status)", .signatureRejected) { $0.signatureObservation!.validationStatus = status }
        reject("signing info failure \(status)", .signatureRejected) { $0.signatureObservation!.signingInformationStatus = status }
    }
    reject("wrong structured team", .wrongTeam) { $0.signatureObservation!.teamID = "AAAAAAAAAA" }
    reject("wrong structured identifier", .wrongBundle) { $0.signatureObservation!.identifier = "org.fake.firefox" }
    for flags in [UInt32(0), 1, 8, 16, 17, 24, 57, UInt32.max] {
        reject("wrong flags \(flags)", .invalidMetadata) { $0.signatureObservation!.validationFlags = flags }
    }
    for value in ["", "anchor apple generic", requirement + " or true", requirement + " and notarized"] {
        reject("wrong requirement \(value.count)", .invalidMetadata) { $0.signatureObservation!.requirement = value }
    }
    reject("wrong signature path", .invalidMetadata) { $0.signatureObservation!.appPath = "/Applications/Firefox.app" }
    reject("invalid signature start", .invalidMetadata) { $0.signatureObservation!.startedAt = "invalid" }
    reject("invalid signature finish", .invalidMetadata) { $0.signatureObservation!.finishedAt = "" }
    reject("reversed signature interval", .invalidMetadata) { $0.signatureObservation!.startedAt = "2026-10-07T14:35:35Z" }
    reject("missing architecture", .missingEvidence, replayReason: .invalidRecord) { $0.architectureObservation = nil }
    reject("wrong architecture", .wrongArchitecture) { $0.architectureObservation!.architectures = ["arm64"] }
    reject("wrong executable path", .invalidMetadata) { $0.architectureObservation!.executablePath = "/other/firefox" }
    for path in ["relative/Firefox.app", "/fixture/../Firefox.app", "/fixture//Firefox.app", "/fixture/Firefox.app\n"] {
        reject("unsafe app path \(String(reflecting: path))", .invalidMetadata) { $0.appPath = path }
    }
    reject("missing observation time", .invalidMetadata) { $0.observedAt = "" }
    reject("missing OS metadata", .invalidMetadata) { $0.osBuild = "" }
    for (key, value, reason) in [("CFBundleIdentifier", "org.fake", InspectionFailure.wrongBundle),
        ("CFBundleShortVersionString", "0.0", .wrongVersion), ("CFBundleExecutable", "../firefox", .invalidMetadata),
        ("CFBundlePackageType", "BNDL", .invalidMetadata)] {
        reject("wrong plist \(key)", reason) {
            var info = ["CFBundleIdentifier": pin.bundleID, "CFBundleShortVersionString": pin.version,
                "CFBundleExecutable": "firefox", "CFBundlePackageType": "APPL"]
            info[key] = value; $0.infoPlist = try plist(info)
        }
    }
    for key in ["signature", "identity", "ticket", "containerTicket", "architectures", "unknown"] {
        reject("schema3 refuses CLI observation \(key)", .invalidMetadata) { $0.commands[key] = .init(executable: "/bin/true", arguments: []) }
    }
    for key in ["imageVerify", "gatekeeper", "containerSignature", "containerGatekeeper"] {
        reject("missing command \(key)", .missingEvidence) { $0.commands.removeValue(forKey: key) }
        reject("wrong executable \(key)", .invalidMetadata) { $0.commands[key]!.executable = "/bin/true" }
        reject("wrong arguments \(key)", .invalidMetadata) { $0.commands[key]!.arguments.append("--extra") }
        reject("timeout \(key)", .commandTimedOut) { $0.commands[key]!.timedOut = true }
        reject("truncated \(key)", .outputLimit) { $0.commands[key]!.outputExceeded = true }
        reject("reversed timestamp \(key)", .invalidMetadata) { $0.commands[key]!.startedAt = "2026-10-07T14:35:35Z" }
        reject("bounded output \(key)", .outputLimit, replayReason: .invalidRecord) { $0.commands[key]!.stdout = String(repeating: "x", count: 1_048_577) }
    }
    for key in ["imageVerify", "gatekeeper"] {
        reject("nonzero required command \(key)", .commandFailed) { $0.commands[key]!.exitCode = 1 }
    }
    for text in ["", "assessment unavailable\n", app + ": rejected\nsource=Notarized Developer ID\n",
        app + ": accepted\nsource=Developer ID\n", "/other.app: accepted\nsource=Notarized Developer ID\n",
        app + ": accepted\nsource=Notarized Developer ID\n" + app + ": rejected\n"] {
        reject("affirmative notarisation \(String(reflecting: text))", .notarizationRejected) { $0.commands["gatekeeper"]!.stderr = text }
    }
    for signaturePassed in [false, true] {
        for gatekeeperPassed in [false, true] {
            for replay in [false, true] {
                add("independent container results signature=\(signaturePassed) gatekeeper=\(gatekeeperPassed) replay=\(replay)") {
                    var item = try sample()
                    item.commands["containerSignature"]!.exitCode = signaturePassed ? 0 : 1
                    item.commands["containerGatekeeper"]!.exitCode = gatekeeperPassed ? 0 : 3
                    item.commands["containerGatekeeper"]!.stderr = gatekeeperPassed ? dmg + ": accepted\nsource=Notarized Developer ID\n" : "rejected\n"
                    let result = try evaluate(item, replay: replay)
                    try expect(result.appChecksPassed && result.containerSignaturePassed == signaturePassed &&
                        result.containerGatekeeperPassed == gatekeeperPassed && !result.containerTicketPassed &&
                        !result.freshOSValidation && !result.installationAuthorized, "Raw container observations were conflated")
                }
            }
        }
    }
    add("unknown pin refuses") {
        var unknown = pin; unknown.teamID = "AAAAAAAAAA"
        try refuses(.unknownTarget) { _ = try EvidenceEvaluator.evaluateFixture(sample(), pin: unknown) }
    }
    func rejectJSON(_ name: String, _ change: @escaping (inout [String: Any]) -> Void) {
        add(name) {
            var doc = try object(JSONEncoder().encode(sample())); change(&doc)
            try refuses(.invalidRecord) { _ = try EvidenceEvaluator.replay(json(doc), pin: pin) }
        }
    }
    let signatureKeys = ["appPath", "requirement", "validationFlags", "validationStatus", "signingInformationStatus", "teamID", "identifier", "startedAt", "finishedAt"]
    for key in signatureKeys {
        for mode in ["missing", "null", "wrong type"] {
            rejectJSON("strict signature \(key) \(mode)") { doc in
                var sig = doc["signatureObservation"] as! [String: Any]
                if mode == "missing" { sig.removeValue(forKey: key) }
                else { sig[key] = mode == "null" ? NSNull() : ["wrong"] as Any }
                doc["signatureObservation"] = sig
            }
        }
    }
    for key in ["appPath", "dmgPath", "infoPlist", "commands", "observedAt", "osVersion", "osBuild"] {
        rejectJSON("missing historical root \(key)") { $0.removeValue(forKey: key) }
        rejectJSON("null historical root \(key)") { $0[key] = NSNull() }
    }
    for container in ["architectureObservation", "commands"] {
        rejectJSON("unknown nested \(container)") { doc in
            var nested = doc[container] as! [String: Any]; nested["untrusted"] = true; doc[container] = nested
        }
    }
    rejectJSON("unknown command observation key") { doc in
        var commands = doc["commands"] as! [String: Any]
        var command = commands["imageVerify"] as! [String: Any]; command["trusted"] = true
        commands["imageVerify"] = command; doc["commands"] = commands
    }
    for (key, value) in [("validationFlags", Int64(-1)), ("validationFlags", Int64(4_294_967_296)),
                         ("validationStatus", Int64(2_147_483_648)), ("signingInformationStatus", Int64(-2_147_483_649))] {
        rejectJSON("signature numeric range \(key) \(value)") { doc in
            var sig = doc["signatureObservation"] as! [String: Any]; sig[key] = value; doc["signatureObservation"] = sig
        }
    }
    for key in ["schemaVersion", "architectureObservation", "signatureObservation"] {
        rejectJSON("null root \(key)") { $0[key] = NSNull() }
        rejectJSON("wrong root type \(key)") { $0[key] = "3" }
    }
    rejectJSON("unknown root") { $0["freshOSValidation"] = true }
    rejectJSON("unknown signature key") { doc in
        var sig = doc["signatureObservation"] as! [String: Any]; sig["trusted"] = true; doc["signatureObservation"] = sig
    }
    for version in [0, 1, 2, 4] { rejectJSON("wrong schema \(version)") { $0["schemaVersion"] = version } }
    for key in ["validationFlags", "validationStatus", "signingInformationStatus"] {
        for value in [true, 0.5, "0"] as [Any] {
            rejectJSON("numeric signature type \(key) \(value)") { doc in
                var sig = doc["signatureObservation"] as! [String: Any]; sig[key] = value; doc["signatureObservation"] = sig
            }
        }
    }
    for (name, duplicate) in [("root", "\"schemaVersion\":3,"), ("escaped root", "\"schema\\u0056ersion\":3,")] {
        add("duplicate \(name)") {
            let raw = String(decoding: try JSONEncoder().encode(sample()), as: UTF8.self)
            let changed = "{" + duplicate + String(raw.dropFirst())
            try refuses(.invalidRecord) { _ = try EvidenceEvaluator.replay(Data(changed.utf8), pin: pin) }
        }
    }
    add("duplicate nested signature") {
        let raw = String(decoding: try JSONEncoder().encode(sample()), as: UTF8.self)
        let changed = raw.replacingOccurrences(of: "\"validationFlags\":25", with: "\"validationFlags\":25,\"validationFlags\":25")
        try expect(changed != raw, "Duplicate control did not mutate JSON")
        try refuses(.invalidRecord) { _ = try EvidenceEvaluator.replay(Data(changed.utf8), pin: pin) }
    }
    for replay in [false, true] {
        for schema in [1, 2] {
            add("historical schema\(schema) remains imported replay=\(replay)") {
                var item = try sample(); item.signatureObservation = nil
                item.schemaVersion = schema == 1 ? nil : 2
                if schema == 1 { item.architectureObservation = nil }
                item.commands["signature"] = .init(executable: "/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", app])
                item.commands["identity"] = .init(executable: "/usr/bin/codesign", arguments: ["-dv", "--verbose=4", app], stderr: "Identifier=org.mozilla.firefox\nTeamIdentifier=43AQ936H96\n")
                if schema == 1 {
                    item.commands["architectures"] = .init(executable: "/usr/bin/lipo", arguments: ["-archs", app + "/Contents/MacOS/firefox"], stdout: "arm64 x86_64")
                    for key in ["ticket", "containerTicket"] {
                        item.commands[key] = .init(executable: "/usr/bin/xcrun", arguments: ["stapler", "validate", key == "ticket" ? app : dmg], stdout: "The validate action worked!\n")
                    }
                }
                let result = try evaluate(item, replay: replay)
                try expect(result.appChecksPassed && !result.freshOSValidation && !result.installationAuthorized &&
                    result.origin == (replay ? .replayed : .fixture), "Historical import gained authority or lost compatibility")
                let doc = try object(JSONEncoder().encode(item))
                try expect(doc["signatureObservation"] == nil, "Historical encoding acquired a signature key")
            }
        }
    }
    // CHECK-ADDED PAT-2708 F1: all original 268 cases remain unchanged.
    cases += pinnedSignatureBindingCases()
    var failures: [String] = []
    for (name, body) in cases { do { try body() } catch { failures.append("\(name): \(error)") } }
    failures.prefix(12).forEach { print("FAIL \($0)") }
    print("PAT-2708 pinned signature fixtures: \(cases.count) cases; \(failures.count) failures; showing at most 12. No native or installed proof.")
    exit(failures.isEmpty ? 0 : 1)
}
