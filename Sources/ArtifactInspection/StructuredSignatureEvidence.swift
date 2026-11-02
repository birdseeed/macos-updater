import Foundation

func pinnedSignatureExpectedCommands(app: String, dmg: String) -> [String: (String, [String])] {
    ["imageVerify": ("/usr/bin/hdiutil", ["verify", dmg]),
     "gatekeeper": ("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=4", app]),
     "containerSignature": ("/usr/bin/codesign", ["--verify", "--deep", "--strict", dmg]),
     "containerGatekeeper": ("/usr/sbin/spctl", ["--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=4", dmg])]
}

func assessPinnedSignatureEvidence(_ evidence: AppEvidence, pin: TargetPin, origin: EvidenceOrigin) throws -> Assessment {
    guard FirefoxTargets.pins.contains(pin) else { throw InspectionFailure.unknownTarget }
    guard evidence.schemaVersion == 3,
          safeEvidencePath(evidence.appPath), safeEvidencePath(evidence.dmgPath),
          evidence.appPath.hasSuffix("/Firefox.app"), parseTimestamp(evidence.observedAt) != nil,
          !evidence.osVersion.isEmpty, !evidence.osBuild.isEmpty, evidence.infoPlist.count <= 1_048_576 else {
        throw InspectionFailure.invalidMetadata
    }
    guard let architecture = evidence.architectureObservation,
          let signature = evidence.signatureObservation else { throw InspectionFailure.missingEvidence }
    guard architecture.executablePath == evidence.appPath + "/Contents/MacOS/firefox" else {
        throw InspectionFailure.invalidMetadata
    }
    guard architecture.architectures == pin.architectures.sorted() else { throw InspectionFailure.wrongArchitecture }
    let requirement = try PinnedSignatureRequirement.make(teamID: pin.teamID, bundleID: pin.bundleID)
    guard signature.appPath == evidence.appPath, signature.requirement == requirement,
          signature.validationFlags == PinnedSignatureRequirement.validationFlags,
          let start = parseTimestamp(signature.startedAt), let end = parseTimestamp(signature.finishedAt), end >= start else {
        throw InspectionFailure.invalidMetadata
    }
    guard signature.validationStatus == 0, signature.signingInformationStatus == 0 else {
        throw InspectionFailure.signatureRejected
    }
    guard signature.teamID == pin.teamID else { throw InspectionFailure.wrongTeam }
    guard signature.identifier == pin.bundleID else { throw InspectionFailure.wrongBundle }
    let expected = pinnedSignatureExpectedCommands(app: evidence.appPath, dmg: evidence.dmgPath)
    guard Set(evidence.commands.keys).isSubset(of: Set(expected.keys)) else { throw InspectionFailure.invalidMetadata }
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
    guard gatekeeperAccepted(evidence.commands["gatekeeper"]!, path: evidence.appPath) else {
        throw InspectionFailure.notarizationRejected
    }
    return Assessment(appChecksPassed: true,
        containerSignaturePassed: evidence.commands["containerSignature"]!.exitCode == 0,
        containerGatekeeperPassed: gatekeeperAccepted(evidence.commands["containerGatekeeper"]!, path: evidence.dmgPath),
        containerTicketPassed: false, origin: origin, freshOSValidation: origin == .live, installationAuthorized: false)
}
