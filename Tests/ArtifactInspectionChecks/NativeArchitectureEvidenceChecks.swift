import Foundation
import Darwin
import ArtifactInspection

// Added before the corresponding product paths. These do not issue live authority.
@MainActor func runNativeArchitectureEvidenceChecks() {
    var items: [(String, () throws -> Void)] = []
    let pin = FirefoxTargets.pins[0], app = "/fixture/private/mount/Firefox.app", dmg = "/fixture/private/Firefox.dmg"
    func nativeEvidence() throws -> AppEvidence {
        let commands: [String: CommandResult] = [
            "imageVerify": .init(executable: "/usr/bin/hdiutil", arguments: ["verify", dmg]),
            "signature": .init(executable: "/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", app]),
            "identity": .init(executable: "/usr/bin/codesign", arguments: ["-dv", "--verbose=4", app], stderr: "Identifier=org.mozilla.firefox\nTeamIdentifier=43AQ936H96\n"),
            "gatekeeper": .init(executable: "/usr/sbin/spctl", arguments: ["--assess", "--type", "execute", "--verbose=4", app], stderr: app + ": accepted\nsource=Notarized Developer ID\n"),
            "ticket": .init(executable: "/usr/bin/xcrun", arguments: ["stapler", "validate", app], stdout: "The validate action worked!\n"),
            "containerSignature": .init(executable: "/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", dmg], exitCode: 1),
            "containerGatekeeper": .init(executable: "/usr/sbin/spctl", arguments: ["--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=4", dmg], exitCode: 1),
            "containerTicket": .init(executable: "/usr/bin/xcrun", arguments: ["stapler", "validate", dmg], exitCode: 65)]
        return AppEvidence(appPath: app, dmgPath: dmg,
            infoPlist: try plist(["CFBundleIdentifier": pin.bundleID, "CFBundleShortVersionString": pin.version,
                                 "CFBundleExecutable": "firefox", "CFBundlePackageType": "APPL"]), commands: commands,
            schemaVersion: 2, architectureObservation: .init(executablePath: app + "/Contents/MacOS/firefox", architectures: ["arm64", "x86_64"]))
    }
    items.append(("v2 fixture stays fixture", {
        let result = try EvidenceEvaluator.evaluateFixture(nativeEvidence(), pin: pin)
        try expect(result.appChecksPassed && result.origin == .fixture && !result.freshOSValidation && !result.installationAuthorized, "Structured fixture promoted to native authority")
    }))
    items.append(("v2 replay stays replayed", {
        let result = try EvidenceEvaluator.replay(JSONEncoder().encode(nativeEvidence()), pin: pin)
        try expect(result.appChecksPassed && result.origin == .replayed && !result.freshOSValidation && !result.installationAuthorized, "Structured replay promoted to native authority")
    }))
    for names in [[], ["arm64"], ["x86_64"], ["arm64", "x86_64", "ppc"], ["arm64", "arm64", "x86_64"], ["x86_64", "arm64"]] {
        items.append(("v2 noncanonical architecture \(names)", {
            var item = try nativeEvidence(); item.architectureObservation!.architectures = names
            try refuses(.wrongArchitecture) { _ = try EvidenceEvaluator.evaluateFixture(item, pin: pin) }
        }))
    }
    items.append(("v2 wrong executable path", {
        var item = try nativeEvidence(); item.architectureObservation!.executablePath = "/Applications/Firefox.app/Contents/MacOS/firefox"
        try refuses(.invalidMetadata) { _ = try EvidenceEvaluator.evaluateFixture(item, pin: pin) }
    }))
    items.append(("v2 missing observation", {
        var item = try nativeEvidence(); item.architectureObservation = nil
        try refuses(.missingEvidence) { _ = try EvidenceEvaluator.evaluateFixture(item, pin: pin) }
    }))
    items.append(("v2 command substitution refused", {
        var item = try nativeEvidence(); item.commands["architectures"] = .init(executable: "/bin/true", arguments: [], stdout: "arm64 x86_64")
        try refuses(.invalidMetadata) { _ = try EvidenceEvaluator.evaluateFixture(item, pin: pin) }
    }))
    for mutation in ["unknownRoot", "unknownObservation", "wrongVersion", "mixedLegacy", "forgedLive", "duplicateArchitectureKey"] {
        items.append(("v2 strict replay \(mutation)", {
            var document = try object(JSONEncoder().encode(nativeEvidence()))
            switch mutation {
            case "unknownRoot": document["extra"] = true
            case "unknownObservation": var observation = document["architectureObservation"] as! [String: Any]; observation["passed"] = true; document["architectureObservation"] = observation
            case "wrongVersion": document["schemaVersion"] = 3
            case "mixedLegacy": document.removeValue(forKey: "schemaVersion")
            case "forgedLive": document["origin"] = "live"; document["freshOSValidation"] = true
            default: break
            }
            var bytes = try json(document)
            if mutation == "duplicateArchitectureKey" {
                let text = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "\"architectures\":[", with: "\"architectures\":[],\"architectures\":[")
                bytes = Data(text.utf8)
            }
            try refuses(.invalidRecord) { _ = try EvidenceEvaluator.replay(bytes, pin: pin) }
        }))
    }
    items.append(("invalid descriptor refuses", {
        try refuses(.notRegularFile) { _ = try MachOArchitectures.inspect(fileDescriptor: -1) }
    }))
    items.append(("directory descriptor refuses", {
        try withWorkspace { root in
            let fd = open(root.path, O_RDONLY | O_DIRECTORY); defer { if fd >= 0 { close(fd) } }
            try expect(fd >= 0, "Cannot open owned fixture")
            try refuses(.notRegularFile) { _ = try MachOArchitectures.inspect(fileDescriptor: fd) }
        }
    }))
    // Full minimum 64-bit little-endian arm64 executable header.
    let header = Data([0xcf, 0xfa, 0xed, 0xfe, 12, 0, 0, 1, 0, 0, 0, 0, 2, 0, 0, 0] + [UInt8](repeating: 0, count: 16))
    items.append(("held descriptor read preserves caller offset and ownership", {
        try withWorkspace { root in
            let path = root.appendingPathComponent("inert-header"); try header.write(to: path)
            let fd = open(path.path, O_RDONLY | O_NOFOLLOW); defer { if fd >= 0 { close(fd) } }
            try expect(fd >= 0 && lseek(fd, 7, SEEK_SET) == 7, "Cannot position owned fixture")
            let architectures = try MachOArchitectures.inspect(fileDescriptor: fd)
            try expect(architectures == ["arm64"], "Reader lost header CPU")
            try expect(lseek(fd, 0, SEEK_CUR) == 7 && fcntl(fd, F_GETFD) >= 0, "Reader changed offset or closed caller fd")
        }
    }))
    items.append(("held descriptor truncated data refuses", {
        try withWorkspace { root in
            let path = root.appendingPathComponent("truncated-header"); try header.prefix(31).write(to: path)
            let fd = open(path.path, O_RDONLY | O_NOFOLLOW); defer { if fd >= 0 { close(fd) } }
            try expect(fd >= 0, "Cannot open owned fixture")
            try refuses(.wrongArchitecture) { _ = try MachOArchitectures.inspect(fileDescriptor: fd) }
        }
    }))
    var failures: [String] = []
    for (name, body) in items { do { try body() } catch { failures.append("\(name): \(error)") } }
    failures.forEach { print("FAIL \($0)") }
    print("PAT-2706 native observation fixtures: \(items.count) cases; \(failures.count) failures. No live or clean-Mac proof.")
    if !failures.isEmpty { exit(1) }
}
