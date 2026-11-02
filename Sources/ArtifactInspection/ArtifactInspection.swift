import Foundation
import Darwin

// Native read-only artifact inspection contract. No installation authority.
public enum InspectionFailure: String, Error, Codable {
    case notImplemented, unknownTarget, unsafeURL, redirectLimit, downloadLimit
    case unsafePath, notRegularFile, lengthMismatch, digestMismatch
    case invalidRecord, missingEvidence, invalidMetadata, wrongBundle, wrongVersion
    case wrongArchitecture, wrongTeam, commandFailed, commandTimedOut, outputLimit
    case signatureRejected, notarizationRejected, ticketRejected, invalidMount, cleanupFailed
}

public struct TargetPin: Codable, Equatable, Sendable {
    public var version: String
    public var url: String
    public var sha256: String
    public var byteLength: Int64
    public var bundleID: String = "org.mozilla.firefox"
    public var teamID: String = "43AQ936H96"
    public var architectures: [String] = ["arm64", "x86_64"]
    public init(version: String, url: String, sha256: String, byteLength: Int64) {
        self.version = version; self.url = url; self.sha256 = sha256; self.byteLength = byteLength
    }
}

public enum FirefoxTargets {
    public static let pins: [TargetPin] = [
        TargetPin(version: "157.0", url: "https://archive.mozilla.org/pub/firefox/releases/157.0/mac/en-US/Firefox%20157.0.dmg",
                  sha256: "df6d8c79b6126bcf24cb70ebab9371916a662028e2d706e462d432e78fdf396c", byteLength: 161304638),
        TargetPin(version: "157.0.1", url: "https://archive.mozilla.org/pub/firefox/releases/157.0.1/mac/en-US/Firefox%20157.0.1.dmg",
                  sha256: "40a0a649120635460256dae9ad63e40377f77326cbc9c449a5d0a1d7f5dd7982", byteLength: 161550118)
    ]
    public static func select(version: String) throws -> TargetPin {
        guard let pin = pins.first(where: { $0.version == version }) else { throw InspectionFailure.unknownTarget }
        return pin
    }
    public static func verifyRecord(_ data: Data) throws -> [TargetPin] { try verifyPinRecord(data) }
}

public struct InspectionLimits: Sendable {
    public var redirects: Int = 3
    public var downloadSeconds: Double = 180
    public var downloadBytes: Int64 = ArtifactSizePolicy.absoluteMaximumBytes
    public var commandSeconds: Double = 30
    public var outputBytes: Int = 1_048_576
    public init() {}
}

public enum DownloadPolicy {
    // hops includes the initial URL, then each redirect URL before following it.
    // The only reviewed host is archive.mozilla.org; arbitrary CDN expansion is forbidden.
    public static func validate(hops: [String], pin: TargetPin, receivedBytes: Int64,
                                elapsedSeconds: Double, limits: InspectionLimits = .init()) throws {
        try validateDownload(hops: hops, pin: pin, receivedBytes: receivedBytes, elapsedSeconds: elapsedSeconds, limits: limits)
    }
}

public enum ArtifactBytes {
    // Descriptor-based, no symlinks in any component, bounded streaming hash.
    public static func verify(path: String, expectedSHA256: String, expectedLength: Int64) throws {
        let fd = try SafeFiles.openPath(path); defer { close(fd) }
        try SafeFiles.stream(fd, length: expectedLength, digest: expectedSHA256)
    }
}

public struct CommandResult: Codable, Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var timedOut: Bool
    public var outputExceeded: Bool
    public var startedAt: String
    public var finishedAt: String
    public init(executable: String, arguments: [String], exitCode: Int32 = 0,
                stdout: String = "", stderr: String = "", timedOut: Bool = false,
                outputExceeded: Bool = false, startedAt: String = "2026-10-07T14:35:32Z",
                finishedAt: String = "2026-10-07T14:35:33Z") {
        self.executable = executable; self.arguments = arguments; self.exitCode = exitCode
        self.stdout = stdout; self.stderr = stderr; self.timedOut = timedOut
        self.outputExceeded = outputExceeded; self.startedAt = startedAt; self.finishedAt = finishedAt
    }
}

public protocol InspectionCommandRunning {
    func run(executable: String, arguments: [String], limits: InspectionLimits) throws -> CommandResult
}

public struct BoundedCommandRunner: InspectionCommandRunning {
    public init() {}
    public func run(executable: String, arguments: [String], limits: InspectionLimits) throws -> CommandResult {
        try runBounded(executable: executable, arguments: arguments, limits: limits)
    }
}

public struct ArchitectureObservation: Codable, Equatable, Sendable {
    public var executablePath: String
    public var architectures: [String]
    public init(executablePath: String, architectures: [String]) {
        self.executablePath = executablePath; self.architectures = architectures
    }
}

public struct AppEvidence: Codable, Sendable {
    public var schemaVersion: Int?
    public var architectureObservation: ArchitectureObservation?
    public var signatureObservation: SignatureObservation?
    public var appPath: String
    public var dmgPath: String
    public var infoPlist: Data
    public var commands: [String: CommandResult]
    public var observedAt: String
    public var osVersion: String
    public var osBuild: String
    public init(appPath: String, dmgPath: String, infoPlist: Data, commands: [String: CommandResult],
                observedAt: String = "2026-10-07T14:35:34Z", osVersion: String = "27.0.1",
                osBuild: String = "26A434", schemaVersion: Int? = nil,
                architectureObservation: ArchitectureObservation? = nil,
                signatureObservation: SignatureObservation? = nil) {
        self.schemaVersion = schemaVersion; self.architectureObservation = architectureObservation
        self.signatureObservation = signatureObservation
        self.appPath = appPath; self.dmgPath = dmgPath; self.infoPlist = infoPlist
        self.commands = commands; self.observedAt = observedAt; self.osVersion = osVersion; self.osBuild = osBuild
    }
}

public enum EvidenceOrigin: String, Codable, Sendable { case fixture, replayed, live }
// Output only. Imported JSON must be replayed from raw observations; this type
// deliberately has no Decodable conformance or mutable trust fields.
public struct Assessment: Encodable, Equatable, Sendable {
    public let appChecksPassed: Bool
    public let containerSignaturePassed: Bool
    public let containerGatekeeperPassed: Bool
    public let containerTicketPassed: Bool
    public let origin: EvidenceOrigin
    public let freshOSValidation: Bool
    public let installationAuthorized: Bool
}

public enum EvidenceEvaluator {
    // Fixture evaluation is always labelled fixture. A loaded record can only be
    // replayed; only an internal live inspection path may mark fresh OS validation.
    public static func evaluateFixture(_ evidence: AppEvidence, pin: TargetPin) throws -> Assessment {
        try assess(evidence, pin: pin, origin: .fixture)
    }
    public static func replay(_ data: Data, pin: TargetPin) throws -> Assessment {
        try assess(decodeEvidence(data), pin: pin, origin: .replayed)
    }
}

public enum ReadOnlyMount {
    public static func validateAttachment(_ data: Data, ownedMountPath: String) throws -> String {
        try validateMount(data, ownedPath: ownedMountPath)
    }
    // Workspace must already be a private, owned, real directory. Only its
    // exclusive mount child may be detached, never a tool-supplied device/path.
    public static func withImage<T>(dmgPath: String, workspace: String,
                                    runner: any InspectionCommandRunning,
                                    body: (String) throws -> T) throws -> T {
        try withReadOnlyImage(dmgPath: dmgPath, workspace: workspace, runner: runner, body: body)
    }
}
