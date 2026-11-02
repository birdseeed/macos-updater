import Foundation
import CoreFoundation
import Darwin
import ArtifactInspection

/// Testing facade only. The caller exclusively creates a private synthetic root
/// below the nearest .build containing the running check executable. This root
/// is not a guest run and cannot be adopted by a productive scope or executor.
@_spi(Testing) public struct SyntheticGatewayExpectation: Sendable {
    public let profile: DisposableTargetProfile
    public let binarySHA256: String
    public let receiptBytes: Data
    public let artifactSHA256: String
    public let artifactLength: Int64
    public init(binarySHA256: String, receiptBytes: Data, artifactSHA256: String, artifactLength: Int64, profile: DisposableTargetProfile = .legacy) {
        self.profile = profile
        self.binarySHA256 = binarySHA256; self.receiptBytes = receiptBytes
        self.artifactSHA256 = artifactSHA256; self.artifactLength = artifactLength
    }
}

/// Output-only retained inspection handle, never a native capability.
@_spi(Testing) public final class SyntheticGatewayInspection {
    public let binarySHA256: String
    public let artifactSHA256: String
    public let receiptSHA256: String
    public let targetManifest: ProofManifest
    private let held: GatewayPhysicalSnapshot
    private init(held: GatewayPhysicalSnapshot) {
        self.held = held; binarySHA256 = held.expected.binarySHA256
        artifactSHA256 = held.expected.artifactSHA256
        receiptSHA256 = digest(held.expected.receiptBytes); targetManifest = held.targetManifest
    }
    public static func capture(rootPath: String, expected: SyntheticGatewayExpectation) throws -> SyntheticGatewayInspection {
        // Validate lexical confinement before opening any supplied path. The
        // fixed direct-child prefix is exclusive to these synthetic checks.
        let executable = try kernelExecutable(), parts = try components(executable, absolute: true)
        guard let index = parts.lastIndex(of: ".build") else { throw DisposableFailure.notAuthorized }
        let build = "/" + parts[...index].joined(separator: "/")
        guard rootPath.hasPrefix(build + "/pat2602-gateway-"),
              let names = try? components(rootPath, absolute: true), names.count == index + 2,
              let name = names.last, UUID(uuidString: String(name.dropFirst("pat2602-gateway-".count)))?.uuidString ==
                String(name.dropFirst("pat2602-gateway-".count)) else { throw DisposableFailure.notAuthorized }
        let root = try HeldDirectory.absolute(rootPath)
        try requireTrustedAncestry(root)
        return SyntheticGatewayInspection(held: try GatewayPhysicalSnapshot(root: root, expected: expected))
    }
    public func revalidate() throws { try held.revalidate() }
}

/// Independent facts are SPI-only synthetic inputs. A productive readback issuer
/// must observe journal/tree/native facts itself; this value is never accepted
/// by NativeInstalledActionScope and cannot construct a productive capability.
@_spi(Testing) public struct SyntheticGatewayReadback: Sendable {
    public let targetPath: String
    public let version: String
    public let transactionID: String
    public let manifestSHA256: String
    public let retainedOldSHA256: String
    public let fresh: Bool
    public init(targetPath: String, version: String, transactionID: String, manifestSHA256: String,
                retainedOldSHA256: String, fresh: Bool) {
        self.targetPath = targetPath; self.version = version; self.transactionID = transactionID
        self.manifestSHA256 = manifestSHA256; self.retainedOldSHA256 = retainedOldSHA256; self.fresh = fresh
    }
}

/// This comparison proves only synthetic evidence consistency, never OS trust or
/// installation. Its full top-level schema is DisposableReport's current schema,
/// not the controller test gateway's small flat header. Stdout must equal the
/// exact durable report bytes plus its one print newline. The invocation nonce
/// and newly-created durable record observation are caller-controlled only in
/// SPI; a future runner observes them for its actual child invocation.
@_spi(Testing) public enum SyntheticGatewayCompletion {
    public static func compare(stdout: Data, durableReport: Data, childExit: Int32,
                               expectedInvocationID: UUID, observedInvocationID: UUID, durableFileIsNew: Bool,
                               action: DisposableAction, runID: String, caseRoot: String,
                               expected: SyntheticGatewayExpectation, readback: SyntheticGatewayReadback) throws {
        guard childExit == 0, expectedInvocationID == observedInvocationID, durableFileIsNew,
              !durableReport.isEmpty, durableReport.count <= 16_777_216,
              stdout == durableReport + Data([10]) else { throw DisposableFailure.notAuthorized }
        let report = try StrictObject.decode(durableReport, maximum: 16_777_216, failure: .notAuthorized)
        try GatewayReportProjection.compare(report, action: action, runID: runID, caseRoot: caseRoot,
                                            expected: expected, readback: readback)
    }
}

/// Shared descriptor mechanics only. This type neither observes guest authority
/// nor creates a native scope. A later live issuer must supply its own guarded
/// path layout and native validation instead of adopting a synthetic snapshot.
private final class GatewayPhysicalSnapshot {
    let expected: SyntheticGatewayExpectation
    let root: HeldDirectory, tool: HeldDirectory, incoming: HeldDirectory
    let applications: HeldDirectory, baselineParent: HeldDirectory
    let target: HeldDirectory, baseline: HeldDirectory
    let binary: HeldFile, receipt: HeldFile, artifact: HeldFile
    let targetManifest: ProofManifest, baselineManifest: ProofManifest
    init(root: HeldDirectory, expected: SyntheticGatewayExpectation) throws {
        self.root = root; self.expected = expected
        try root.owned(privateMode: true); try requirePrivateACL(root)
        tool = try root.child("Tool"); incoming = try root.child("Incoming")
        applications = try root.child("Applications"); baselineParent = try root.child("Baseline")
        for directory in [tool, incoming, applications, baselineParent] {
            try directory.owned(privateMode: true); try requirePrivateACL(directory)
            try sameVolume(identity(root.captured).0, identity(directory.captured).0)
        }
        binary = try HeldFile(parent: tool, name: "patched-disposable-proof")
        receipt = try HeldFile(parent: tool, name: "builder-receipt.json")
        artifact = try HeldFile(parent: incoming, name: "artifact.dmg")
        guard validDigest(expected.binarySHA256), validDigest(expected.artifactSHA256),
              expected.artifactLength > 0, expected.artifactLength <= DisposableScope.maximumTotalBytes,
              !expected.receiptBytes.isEmpty, expected.receiptBytes.count <= 65_536 else { throw DisposableFailure.notAuthorized }
        let actualBinary = try binary.stream(maximum: 268_435_456).1
        guard actualBinary == expected.binarySHA256,
              try receipt.data(maximum: 65_536) == expected.receiptBytes else { throw DisposableFailure.notAuthorized }
        try GatewayReportProjection.receipt(expected)
        try artifact.verify(length: expected.artifactLength, hash: expected.artifactSHA256)
        target = try applications.child("Firefox.app"); baseline = try baselineParent.child("Firefox-157.0.app")
        try sameVolume(identity(root.captured).0, identity(target.captured).0)
        try sameVolume(identity(root.captured).0, identity(baseline.captured).0)
        targetManifest = try ManifestReader.read(target); baselineManifest = try ManifestReader.read(baseline)
        guard targetManifest == baselineManifest else { throw DisposableFailure.manifestMismatch }
        try revalidate()
    }
    func revalidate() throws {
        for directory in [root, tool, incoming, applications, baselineParent, target, baseline] { try directory.confirm() }
        for directory in [root, tool, incoming, applications, baselineParent] {
            try directory.owned(privateMode: true); try requirePrivateACL(directory)
        }
        // HeldFile.confirm also detects in-place size/mode/mtime/ctime changes.
        try binary.confirm(); try receipt.confirm(); try artifact.confirm()
        guard try binary.stream(maximum: 268_435_456).1 == expected.binarySHA256,
              try receipt.data(maximum: 65_536) == expected.receiptBytes else { throw DisposableFailure.identityChanged }
        try artifact.verify(length: expected.artifactLength, hash: expected.artifactSHA256)
        guard try ManifestReader.read(target) == targetManifest,
              try ManifestReader.read(baseline) == baselineManifest else { throw DisposableFailure.manifestMismatch }
    }
}

/// Pure report projection. This is deliberately not an issuer or a live OS
/// verifier. Empty native arrays are permitted only because this API is SPI and
/// compares synthetic observations; productive acceptance must verify them live.
enum GatewayReportProjection {
    static let required: Set<String> = ["action", "runID", "caseRoot", "state", "recoveryAction", "testCatalogueTrust",
        "productionTrust", "installedFirefoxProof", "freshOSValidation", "binarySHA256", "sourceRevisionObservedByHarness",
        "builderProvenanceReceiptSHA256", "builderProvenanceReceipt", "manifestCoverage", "limitations", "guest",
        "nativeCommands", "appObservations", "bundleManifests", "imageObservations", "journalStatesReached",
        "independentMtreeFiles", "spaceObservations", "targetPath", "exchangePath", "harnessSigningObservation",
        "targetID", "trigger", "transactionID", "containerObservations", "catalogueObservations", "ownedMountsAbsent", "globalProductReadiness"]
    static func demand(_ accepted: Bool) throws { if !accepted { throw DisposableFailure.notAuthorized } }
    static func flag(_ value: Any?, _ expected: Bool) -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
        return number.boolValue == expected
    }
    static func receipt(_ expected: SyntheticGatewayExpectation) throws {
        let object = try StrictObject.decode(expected.receiptBytes, failure: .notAuthorized)
        try demand(object["binarySHA256"] as? String == expected.binarySHA256 && validDigest(expected.binarySHA256))
        guard let revision = object["sourceRevision"] as? String else { throw DisposableFailure.notAuthorized }
        try demand(revision.utf8.count == 40 && revision.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) })
    }
    static func compare(_ o: [String: Any], action: DisposableAction, runID: String, caseRoot: String,
                        expected: SyntheticGatewayExpectation, readback: SyntheticGatewayReadback) throws {
        let keys = Set(o.keys)
        try demand(keys == required || keys == required.union(["recordedInspectionSHA256"]))
        if let recorded = o["recordedInspectionSHA256"] { try demand((recorded as? String).map(validDigest) == true) }
        try demand([DisposableAction.update, .recoverAfterStaging, .recoverAfterSwap, .restoreOld].contains(action))
        let profile = expected.profile
        _ = try DisposableArguments.parse(["--target-id", profile.targetID, "--run-id", runID,
            "--case-root", caseRoot, "--case", action.rawValue, "--explicit-trigger"])
        let target = profile.runParent + "/" + runID + "/Cases/" + caseRoot + "/Applications/Firefox.app"
        let exchange = profile.runParent + "/" + runID + "/Cases/" + caseRoot + "/Transaction/Exchange/Firefox.app"
        let update = action == .update
        let recovery = update ? "none" : (action == .recoverAfterStaging ? "oldAlreadyInPlace" : "restoredOldBySwap")
        try demand(o["action"] as? String == action.rawValue && o["runID"] as? String == runID && o["caseRoot"] as? String == caseRoot &&
            o["targetPath"] as? String == target && o["exchangePath"] as? String == exchange && o["targetID"] as? String == profile.targetID &&
            o["trigger"] as? String == "explicitUserAction" && o["state"] as? String == (update ? "committed" : "rolledBack") &&
            o["recoveryAction"] as? String == recovery)
        for key in ["testCatalogueTrust", "freshOSValidation", "ownedMountsAbsent"] { try demand(flag(o[key], true)) }
        for key in ["productionTrust", "globalProductReadiness", "sourceRevisionObservedByHarness"] { try demand(flag(o[key], false)) }
        try demand(flag(o["installedFirefoxProof"], update))
        try receipt(expected)
        let pin = try fixedPin("157.0.1")
        try demand(expected.artifactSHA256 == pin.sha256 && expected.artifactLength == pin.byteLength &&
            o["binarySHA256"] as? String == expected.binarySHA256 &&
            o["builderProvenanceReceiptSHA256"] as? String == digest(expected.receiptBytes) &&
            o["builderProvenanceReceipt"] as? String == expected.receiptBytes.base64EncodedString())
        guard let transaction = o["transactionID"] as? String else { throw DisposableFailure.notAuthorized }
        try demand(UUID(uuidString: transaction)?.uuidString == transaction)
        try guest(o["guest"], profile: profile)
        try demand(o["manifestCoverage"] as? [String] == ["type", "mode", "size", "link", "sha256digest"])
        try demand(o["limitations"] is [String] && o["journalStatesReached"] is [String])
        for key in ["nativeCommands", "containerObservations"] {
            guard let values = o[key] as? [[String: Any]] else { throw DisposableFailure.notAuthorized }
            try demand(values.count <= 100_000); for value in values { try command(value) }
        }
        guard let signing = o["harnessSigningObservation"] as? [String: Any] else { throw DisposableFailure.notAuthorized }
        try command(signing)
        try demand(o["imageObservations"] is [[String: String]] && o["catalogueObservations"] is [[String: String]] &&
                   o["independentMtreeFiles"] is [String: String])
        guard let spaces = o["spaceObservations"] as? [[String: Any]] else { throw DisposableFailure.notAuthorized }
        try demand(spaces.allSatisfy { $0.values.allSatisfy { unsigned($0) != nil } })
        guard let observations = o["appObservations"] as? [[String: Any]] else { throw DisposableFailure.notAuthorized }
        for observation in observations {
            let keys = Set(observation.keys)
            try demand(keys == observationKeys || keys == observationKeys.union(["signatureObservation"]))
            for key in ["path", "version", "bundleID", "teamID", "observedAt"] { try demand(observation[key] is String) }
            guard let path = observation["path"] as? String,
                  let architecture = observation["architectureObservation"] as? [String: Any] else { throw DisposableFailure.notAuthorized }
            try demand(Set(architecture.keys) == ["executablePath", "architectures"] &&
                architecture["executablePath"] as? String == path + "/Contents/MacOS/firefox" &&
                architecture["architectures"] as? [String] == ["arm64", "x86_64"])
            if keys.contains("signatureObservation") {
                try demand(observation["bundleID"] as? String == "org.mozilla.firefox" &&
                           observation["teamID"] as? String == "43AQ936H96")
                try signature(observation["signatureObservation"], path: path,
                              version: observation["version"] as? String ?? "")
            }
            guard let commands = observation["commands"] as? [[String: Any]] else { throw DisposableFailure.notAuthorized }
            for item in commands { try command(item) }; _ = try manifest(observation["manifest"])
        }
        guard let manifests = o["bundleManifests"] as? [String: Any] else { throw DisposableFailure.notAuthorized }
        try demand(Set(manifests.keys) == (update ? Set(["after", "baseline", "before", "retainedOld"]) : Set(["baseline"])))
        let old = try manifest(manifests["baseline"])
        let current = update ? try manifest(manifests["after"]) : old
        if update { try demand(try manifest(manifests["before"]) == old && manifest(manifests["retainedOld"]) == old) }
        try demand(readback.fresh && readback.targetPath == target && readback.version == (update ? "157.0.1" : "157.0") &&
            readback.transactionID == transaction && readback.manifestSHA256 == current && readback.retainedOldSHA256 == old)
    }
    static let observationKeys: Set<String> = ["path", "version", "bundleID", "teamID", "observedAt",
        "commands", "manifest", "architectureObservation"]

    // Pure structural validation shared by synthetic projection and productive
    // report acceptance. It cannot turn decoded fields into native authority.
    static func signature(_ value: Any?, path: String, version: String) throws {
        guard path.hasPrefix("/"), !path.contains("//"),
              !path.utf8.contains(where: { $0 < 32 || $0 == 127 }),
              !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
              let s = value as? [String: Any],
              let pin = FirefoxTargets.pins.first(where: { $0.version == version }) else {
            throw DisposableFailure.notAuthorized
        }
        try demand(Set(s.keys) == ["appPath", "requirement", "validationFlags", "validationStatus",
            "signingInformationStatus", "teamID", "identifier", "startedAt", "finishedAt"])
        let requirement = try PinnedSignatureRequirement.make(teamID: pin.teamID, bundleID: pin.bundleID)
        try demand(s["appPath"] as? String == path && s["requirement"] as? String == requirement &&
            unsigned(s["validationFlags"]) == UInt64(PinnedSignatureRequirement.validationFlags) &&
            unsigned(s["validationStatus"]) == 0 && unsigned(s["signingInformationStatus"]) == 0 &&
            s["teamID"] as? String == pin.teamID && s["identifier"] as? String == pin.bundleID)
        func date(_ value: Any?) -> Date? {
            guard let text = value as? String else { return nil }
            let parser = ISO8601DateFormatter()
            if let result = parser.date(from: text) { return result }
            parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return parser.date(from: text)
        }
        guard let start = date(s["startedAt"]), let end = date(s["finishedAt"]), end >= start else {
            throw DisposableFailure.notAuthorized
        }
    }
    static func guest(_ value: Any?, profile: DisposableTargetProfile = .legacy) throws {
        guard let g = value as? [String: Any] else { throw DisposableFailure.notAuthorized }
        try demand(Set(g.keys) == ["platformUUIDSHA256", "user", "home", "hostname", "osVersion", "osBuild", "architecture", "uid", "effectiveUID", "consoleUID", "hypervisor"])
        let strings = ["platformUUIDSHA256": profile.guestUUIDSHA256, "user": profile.guestUser, "home": profile.guestHome,
            "hostname": profile.guestHostname, "osVersion": profile.guestOS, "osBuild": profile.guestBuild, "architecture": profile.guestArchitecture]
        try demand(strings.allSatisfy { g[$0.key] as? String == $0.value })
        for key in ["uid", "effectiveUID", "consoleUID"] { try demand(unsigned(g[key]) == UInt64(profile.guestUID)) }
        try demand(unsigned(g["hypervisor"]) == 1)
    }
    static func command(_ o: [String: Any]) throws {
        try demand(Set(o.keys) == ["executable", "arguments", "exitCode", "stdout", "stderr", "timedOut", "outputExceeded", "startedAt", "finishedAt"])
        for key in ["executable", "stdout", "stderr", "startedAt", "finishedAt"] { try demand(o[key] is String) }
        try demand(o["arguments"] is [String])
        guard let exit = o["exitCode"] as? NSNumber else { throw DisposableFailure.notAuthorized }
        try demand(CFGetTypeID(exit) != CFBooleanGetTypeID() && Int32(exit.stringValue) != nil)
        for key in ["timedOut", "outputExceeded"] { try demand(flag(o[key], false) || flag(o[key], true)) }
    }
    static func manifest(_ value: Any?) throws -> String {
        guard let m = value as? [String: Any], let hash = m["digest"] as? String,
              let entries = m["entries"] as? [[String: Any]] else { throw DisposableFailure.notAuthorized }
        try demand(Set(m.keys) == ["entries", "totalBytes", "digest"] && validDigest(hash) && unsigned(m["totalBytes"]) != nil && entries.count <= DisposableScope.maximumEntries)
        for e in entries {
            try demand(Set(e.keys) == ["path", "type", "mode", "byteLength", "link", "sha256"])
            for key in ["path", "type", "link", "sha256"] { try demand(e[key] is String) }
            try demand(unsigned(e["mode"]).map { $0 <= 0o7777 } == true && unsigned(e["byteLength"]) != nil)
        }
        return hash
    }
}
