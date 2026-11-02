import Foundation
import Darwin
import ArtifactInspection

// Ready to port additively into Tests/ArtifactInspectionChecks after PAT-2706
// source delivery. Uses only the accepted schema2 API; no future product seam.
@MainActor func runUnstapledEvidenceChecks() -> Never {
    let pin = FirefoxTargets.pins[0], app = "/fixture/private/mount/Firefox.app", dmg = "/fixture/private/Firefox.dmg"
    var cases: [(String, () throws -> Void)] = []
    func sample() throws -> AppEvidence {
        AppEvidence(appPath: app, dmgPath: dmg,
            infoPlist: try plist(["CFBundleIdentifier": pin.bundleID, "CFBundleShortVersionString": pin.version,
                "CFBundleExecutable": "firefox", "CFBundlePackageType": "APPL"]), commands: [
                "imageVerify": .init(executable: "/usr/bin/hdiutil", arguments: ["verify", dmg]),
                "signature": .init(executable: "/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", app]),
                "identity": .init(executable: "/usr/bin/codesign", arguments: ["-dv", "--verbose=4", app], stderr: "Identifier=org.mozilla.firefox\nTeamIdentifier=43AQ936H96\n"),
                "gatekeeper": .init(executable: "/usr/sbin/spctl", arguments: ["--assess", "--type", "execute", "--verbose=4", app], stderr: app + ": accepted\nsource=Notarized Developer ID\n"),
                "containerSignature": .init(executable: "/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", dmg], exitCode: 1),
                "containerGatekeeper": .init(executable: "/usr/sbin/spctl", arguments: ["--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=4", dmg], exitCode: 3)],
            schemaVersion: 2, architectureObservation: .init(executablePath: app + "/Contents/MacOS/firefox", architectures: ["arm64", "x86_64"]))
    }
    func add(_ name: String, _ body: @escaping () throws -> Void) { cases.append((name, body)) }
    func reject(_ name: String, _ reason: InspectionFailure, replayReason: InspectionFailure? = nil, _ change: @escaping (inout AppEvidence) throws -> Void) {
        add(name) {
            for replay in [false, true] {
                var item = try sample(); try change(&item)
                try refuses(replay ? (replayReason ?? reason) : reason) {
                    _ = try (replay ? EvidenceEvaluator.replay(JSONEncoder().encode(item), pin: pin) : EvidenceEvaluator.evaluateFixture(item, pin: pin))
                }
            }
        }
    }
    for replay in [false, true] {
        add("notarised unstapled accepted replay=\(replay)") {
            let item = try sample()
            let result = try (replay ? EvidenceEvaluator.replay(JSONEncoder().encode(item), pin: pin) : EvidenceEvaluator.evaluateFixture(item, pin: pin))
            try expect(result.appChecksPassed && !result.containerTicketPassed && !result.freshOSValidation && !result.installationAuthorized,
                       "Absent staple became refusal, fabricated ticket success or live authority")
            try expect(result.origin == (replay ? .replayed : .fixture), "Imported record changed origin")
        }
    }
    for text in [app + ": accepted\nsource=Developer ID\n", app + ": rejected\nsource=Notarized Developer ID\n",
                 "assessment unavailable\n", "", "/other.app: accepted\nsource=Notarized Developer ID\n",
                 app + ": accepted\nsource=Notarized Developer ID\n" + app + ": rejected\n"] {
        reject("unstapled notarisation refuses \(String(reflecting: text))", .notarizationRejected) { $0.commands["gatekeeper"]!.stderr = text }
    }
    for key in ["imageVerify", "signature", "identity", "gatekeeper", "containerSignature", "containerGatekeeper"] {
        reject("required observation \(key)", .missingEvidence) { $0.commands.removeValue(forKey: key) }
    }
    for key in ["imageVerify", "signature", "identity", "gatekeeper"] {
        reject("required command fails \(key)", .commandFailed) { $0.commands[key]!.exitCode = 1 }
    }
    reject("Gatekeeper timeout refuses", .commandTimedOut) { $0.commands["gatekeeper"]!.timedOut = true }
    reject("Gatekeeper truncated refuses", .outputLimit) { $0.commands["gatekeeper"]!.outputExceeded = true }
    reject("wrong signer refuses without staple", .wrongTeam) { $0.commands["identity"]!.stderr = "Identifier=org.mozilla.firefox\nTeamIdentifier=WRONG\n" }
    reject("wrong bundle refuses without staple", .wrongBundle) { $0.commands["identity"]!.stderr = "Identifier=org.fake.firefox\nTeamIdentifier=43AQ936H96\n" }
    reject("wrong architecture refuses without staple", .wrongArchitecture) { $0.architectureObservation!.architectures = ["arm64"] }
    reject("wrong architecture path refuses without staple", .invalidMetadata) { $0.architectureObservation!.executablePath = "/other/firefox" }
    for key in ["ticket", "containerTicket"] {
        for code in [Int32(0), 65] {
            add("optional historical snapshot \(key) exit=\(code) cannot determine trust") {
                var item = try sample()
                item.commands[key] = .init(executable: "/usr/bin/xcrun", arguments: ["stapler", "validate", key == "ticket" ? app : dmg],
                    exitCode: code, stdout: code == 0 ? "Arbitrary output, no exact success text\n" : "not stapled\n")
                let result = try EvidenceEvaluator.replay(JSONEncoder().encode(item), pin: pin)
                try expect(result.appChecksPassed && !result.containerTicketPassed && result.origin == .replayed && !result.freshOSValidation,
                           "Optional imported stapling snapshot determined acceptance or invented current ticket success")
            }
        }
        reject("optional historical snapshot wrong executable \(key)", .invalidMetadata) {
            $0.commands[key] = .init(executable: "/bin/true", arguments: ["stapler", "validate", key == "ticket" ? app : dmg])
        }
        reject("optional historical snapshot wrong path \(key)", .invalidMetadata) {
            $0.commands[key] = .init(executable: "/usr/bin/xcrun", arguments: ["stapler", "validate", "/other"])
        }
        reject("optional historical snapshot timeout \(key)", .commandTimedOut) {
            $0.commands[key] = .init(executable: "/usr/bin/xcrun", arguments: ["stapler", "validate", key == "ticket" ? app : dmg], timedOut: true)
        }
    }
    add("optional historical success cannot override rejected Gatekeeper") {
        var item = try sample()
        for key in ["ticket", "containerTicket"] {
            item.commands[key] = .init(executable: "/usr/bin/xcrun", arguments: ["stapler", "validate", key == "ticket" ? app : dmg], stdout: "The validate action worked!\n")
        }
        item.commands["gatekeeper"]!.stderr = app + ": rejected\nsource=Notarized Developer ID\n"
        try refuses(.notarizationRejected) { _ = try EvidenceEvaluator.evaluateFixture(item, pin: pin) }
    }
    // Repeat every refusal through strict replay as well as the direct fixture API.
    // The original local helpers are safe before legacy main.swift global initialisers.
    reject("wrong plist version without staple", .wrongVersion) {
        $0.infoPlist = try plist(["CFBundleIdentifier": pin.bundleID, "CFBundleShortVersionString": "0.0.0",
            "CFBundleExecutable": "firefox", "CFBundlePackageType": "APPL"])
    }
    reject("wrong plist bundle without staple", .wrongBundle) {
        $0.infoPlist = try plist(["CFBundleIdentifier": "org.fake.firefox", "CFBundleShortVersionString": pin.version,
            "CFBundleExecutable": "firefox", "CFBundlePackageType": "APPL"])
    }
    reject("unknown current observation", .invalidMetadata) {
        $0.commands["unknown"] = .init(executable: "/bin/true", arguments: [])
    }
    for key in ["ticket", "containerTicket"] {
        let path = key == "ticket" ? app : dmg
        for replay in [false, true] {
            add("optional historical fixture/replay \(key) replay=\(replay)") {
                var item = try sample()
                item.commands[key] = .init(executable: "/usr/bin/xcrun", arguments: ["stapler", "validate", path],
                    exitCode: 65, stdout: "No ticket, arbitrary historical text")
                let result = try (replay ? EvidenceEvaluator.replay(JSONEncoder().encode(item), pin: pin) : EvidenceEvaluator.evaluateFixture(item, pin: pin))
                try expect(result.appChecksPassed && !result.containerTicketPassed && !result.freshOSValidation &&
                    !result.installationAuthorized && result.origin == (replay ? .replayed : .fixture),
                    "Optional historical snapshot changed trust or origin")
            }
        }
        reject("optional snapshot wrong arguments \(key)", .invalidMetadata) {
            $0.commands[key] = .init(executable: "/usr/bin/xcrun", arguments: ["stapler", "validate", path, "--extra"])
        }
        reject("optional snapshot invalid timestamp \(key)", .invalidMetadata) {
            $0.commands[key] = .init(executable: "/usr/bin/xcrun", arguments: ["stapler", "validate", path], startedAt: "invalid")
        }
        reject("optional snapshot reversed interval \(key)", .invalidMetadata) {
            $0.commands[key] = .init(executable: "/usr/bin/xcrun", arguments: ["stapler", "validate", path],
                startedAt: "2026-10-07T14:35:34Z", finishedAt: "2026-10-07T14:35:32Z")
        }
        reject("optional snapshot truncation \(key)", .outputLimit) {
            $0.commands[key] = .init(executable: "/usr/bin/xcrun", arguments: ["stapler", "validate", path], outputExceeded: true)
        }
        reject("optional snapshot combined output bound \(key)", .outputLimit, replayReason: .invalidRecord) {
            $0.commands[key] = .init(executable: "/usr/bin/xcrun", arguments: ["stapler", "validate", path],
                stdout: String(repeating: "a", count: 524_289), stderr: String(repeating: "b", count: 524_288))
        }
    }
    add("both historical snapshots with arbitrary successful text remain informational") {
        var item = try sample()
        for key in ["ticket", "containerTicket"] {
            item.commands[key] = .init(executable: "/usr/bin/xcrun", arguments: ["stapler", "validate", key == "ticket" ? app : dmg],
                stdout: "No magic stapler success text")
        }
        for replay in [false, true] {
            let result = try (replay ? EvidenceEvaluator.replay(JSONEncoder().encode(item), pin: pin) : EvidenceEvaluator.evaluateFixture(item, pin: pin))
            try expect(result.appChecksPassed && !result.containerTicketPassed && !result.freshOSValidation && !result.installationAuthorized,
                "Historical success was treated as mandatory proof or current validation")
        }
    }
    var failures: [String] = []
    for (name, body) in cases { do { try body() } catch { failures.append("\(name): \(error)") } }
    failures.forEach { print("FAIL \($0)") }
    print("PAT-2707 unstapled fixtures: \(cases.count) cases; \(failures.count) failures. No genuine unstapled or clean-Mac proof.")
    exit(failures.isEmpty ? 0 : 1)
}
