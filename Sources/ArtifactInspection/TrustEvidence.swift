import Foundation

func timestamp() -> String { ISO8601DateFormatter().string(from: Date()) }
func parseTimestamp(_ value: String) -> Date? {
    let parser = ISO8601DateFormatter()
    if let result = parser.date(from: value) { return result }
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return parser.date(from: value)
}
func checkResult(_ result: CommandResult, requireSuccess: Bool = true) throws {
    guard !result.timedOut else { throw InspectionFailure.commandTimedOut }
    guard !result.outputExceeded, result.stdout.utf8.count + result.stderr.utf8.count <= 1_048_576 else { throw InspectionFailure.outputLimit }
    guard let start = parseTimestamp(result.startedAt), let end = parseTimestamp(result.finishedAt), end >= start else {
        throw InspectionFailure.invalidMetadata
    }
    if requireSuccess && result.exitCode != 0 { throw InspectionFailure.commandFailed }
}
// Historical snapshots remain fixture/replay-only; no live caller uses this command table.
func legacyExpectedCommands(app: String, dmg: String) -> [String: (String, [String])] {
    ["imageVerify": ("/usr/bin/hdiutil", ["verify", dmg]),
     "signature": ("/usr/bin/codesign", ["--verify", "--deep", "--strict", app]),
     "identity": ("/usr/bin/codesign", ["-dv", "--verbose=4", app]),
     "architectures": ("/usr/bin/lipo", ["-archs", app + "/Contents/MacOS/firefox"]),
     "gatekeeper": ("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=4", app]),
     "ticket": ("/usr/bin/xcrun", ["stapler", "validate", app]),
     "containerSignature": ("/usr/bin/codesign", ["--verify", "--deep", "--strict", dmg]),
     "containerGatekeeper": ("/usr/sbin/spctl", ["--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=4", dmg]),
     "containerTicket": ("/usr/bin/xcrun", ["stapler", "validate", dmg])]
}
func expectedCommands(app: String, dmg: String) -> [String: (String, [String])] {
    ["imageVerify": ("/usr/bin/hdiutil", ["verify", dmg]),
     "signature": ("/usr/bin/codesign", ["--verify", "--deep", "--strict", app]),
     "identity": ("/usr/bin/codesign", ["-dv", "--verbose=4", app]),
     "gatekeeper": ("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=4", app]),
     "containerSignature": ("/usr/bin/codesign", ["--verify", "--deep", "--strict", dmg]),
     "containerGatekeeper": ("/usr/sbin/spctl", ["--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=4", dmg])]
}
func replayExpectedStaplingCommands(app: String, dmg: String) -> [String: (String, [String])] {
    ["ticket": ("/usr/bin/xcrun", ["stapler", "validate", app]),
     "containerTicket": ("/usr/bin/xcrun", ["stapler", "validate", dmg])]
}
func lines(_ result: CommandResult) -> [String] { (result.stdout + "\n" + result.stderr).split(separator: "\n").map(String.init) }
func field(_ name: String, in result: CommandResult) -> [String] {
    lines(result).filter { $0.hasPrefix(name + "=") }.map { String($0.dropFirst(name.count + 1)) }
}
func gatekeeperAccepted(_ result: CommandResult, path: String) -> Bool {
    let output = lines(result)
    return result.exitCode == 0 && output.filter({ $0 == path + ": accepted" }).count == 1 &&
        output.filter({ $0 == "source=Notarized Developer ID" }).count == 1 &&
        !output.contains(where: { $0.localizedCaseInsensitiveContains("rejected") || $0.localizedCaseInsensitiveContains("unavailable") })
}
func ticketAccepted(_ result: CommandResult) -> Bool {
    result.exitCode == 0 && lines(result).filter { $0 == "The validate action worked!" }.count == 1
}
func safeEvidencePath(_ path: String) -> Bool {
    path.hasPrefix("/") && !path.contains("//") && !path.utf8.contains(where: { $0 < 32 || $0 == 127 }) &&
        !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
}
func assess(_ evidence: AppEvidence, pin: TargetPin, origin: EvidenceOrigin) throws -> Assessment {
    if evidence.schemaVersion == 3 {
        return try assessPinnedSignatureEvidence(evidence, pin: pin, origin: origin)
    }
    guard origin != .live else { throw InspectionFailure.missingEvidence }
    guard evidence.signatureObservation == nil else { throw InspectionFailure.invalidMetadata }
    guard FirefoxTargets.pins.contains(pin) else { throw InspectionFailure.unknownTarget }
    guard safeEvidencePath(evidence.appPath), safeEvidencePath(evidence.dmgPath),
          evidence.appPath.hasSuffix("/Firefox.app"), parseTimestamp(evidence.observedAt) != nil,
          !evidence.osVersion.isEmpty, !evidence.osBuild.isEmpty, evidence.infoPlist.count <= 1_048_576 else {
        throw InspectionFailure.invalidMetadata
    }
    let legacy = evidence.schemaVersion == nil && evidence.architectureObservation == nil
    // Imported observations never choose origin. The only live collector must
    // provide the new native observation, never a historical command snapshot.
    guard !legacy || origin != .live else { throw InspectionFailure.missingEvidence }
    guard legacy || evidence.schemaVersion == 2 else { throw InspectionFailure.invalidMetadata }
    if !legacy {
        guard let architecture = evidence.architectureObservation else { throw InspectionFailure.missingEvidence }
        guard architecture.executablePath == evidence.appPath + "/Contents/MacOS/firefox" else { throw InspectionFailure.invalidMetadata }
        guard architecture.architectures == pin.architectures.sorted() else { throw InspectionFailure.wrongArchitecture }
    }
    let expected = legacy ? legacyExpectedCommands(app: evidence.appPath, dmg: evidence.dmgPath) :
        expectedCommands(app: evidence.appPath, dmg: evidence.dmgPath)
    let replayOnly = !legacy && origin != .live ? replayExpectedStaplingCommands(app: evidence.appPath, dmg: evidence.dmgPath) : [:]
    guard Set(evidence.commands.keys).isSubset(of: Set(expected.keys).union(replayOnly.keys)) else { throw InspectionFailure.invalidMetadata }
    for (key, invocation) in replayOnly {
        if let result = evidence.commands[key] {
            guard result.executable == invocation.0, result.arguments == invocation.1 else { throw InspectionFailure.invalidMetadata }
            try checkResult(result, requireSuccess: false)
        }
    }
    for key in expected.keys.sorted() {
        guard let result = evidence.commands[key], let invocation = expected[key] else { throw InspectionFailure.missingEvidence }
        guard result.executable == invocation.0, result.arguments == invocation.1 else { throw InspectionFailure.invalidMetadata }
        try checkResult(result, requireSuccess: !key.hasPrefix("container"))
    }
    let metadata: [String: Any]
    do {
        guard let parsed = try PropertyListSerialization.propertyList(from: evidence.infoPlist, options: [], format: nil) as? [String: Any] else {
            throw InspectionFailure.invalidMetadata
        }; metadata = parsed
    } catch { throw InspectionFailure.invalidMetadata }
    guard metadata["CFBundleIdentifier"] as? String == pin.bundleID else { throw InspectionFailure.wrongBundle }
    guard let version = metadata["CFBundleShortVersionString"] as? String, version == pin.version,
          version.range(of: "^(0|[1-9][0-9]*)(\\.(0|[1-9][0-9]*))+$", options: .regularExpression) != nil else {
        throw InspectionFailure.wrongVersion
    }
    guard metadata["CFBundleExecutable"] as? String == "firefox", metadata["CFBundlePackageType"] as? String == "APPL" else {
        throw InspectionFailure.invalidMetadata
    }
    let identity = evidence.commands["identity"]!
    guard field("TeamIdentifier", in: identity) == [pin.teamID] else { throw InspectionFailure.wrongTeam }
    guard field("Identifier", in: identity) == [pin.bundleID] else { throw InspectionFailure.wrongBundle }
    if legacy {
        let architectures = evidence.commands["architectures"]!.stdout.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard architectures.sorted() == pin.architectures.sorted() else { throw InspectionFailure.wrongArchitecture }
    }
    guard gatekeeperAccepted(evidence.commands["gatekeeper"]!, path: evidence.appPath) else { throw InspectionFailure.notarizationRejected }
    if legacy {
        guard ticketAccepted(evidence.commands["ticket"]!) else { throw InspectionFailure.ticketRejected }
    }
    return Assessment(appChecksPassed: true,
        containerSignaturePassed: evidence.commands["containerSignature"]!.exitCode == 0,
        containerGatekeeperPassed: gatekeeperAccepted(evidence.commands["containerGatekeeper"]!, path: evidence.dmgPath),
        containerTicketPassed: legacy && ticketAccepted(evidence.commands["containerTicket"]!), origin: origin,
        freshOSValidation: origin == .live, installationAuthorized: false)
}
