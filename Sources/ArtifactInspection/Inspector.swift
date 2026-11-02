import Foundation
import Darwin

public struct InspectionReport: Encodable, Sendable {
    public let schemaVersion: Int
    public let pin: TargetPin
    public let mode: String
    public var sourcePath: String?
    public var sourceURL: String
    public var redirectChain: [String]
    public var transportObservedThisRun: Bool
    public var byteIntegrityVerified: Bool
    public var commands: [CommandResult]
    public var evidence: AppEvidence?
    public var assessment: Assessment?
    public var refusal: String?
    public var workspacePreserved: String?
    public var cleanupVerified: Bool
    public let installationAuthorized: Bool
    public let providerActualCost: String
}

private final class RecordingRunner: ImageCommandRunning {
    var commands: [CommandResult] = []
    var retainedImage: VerifiedImage?
    func run(executable: String, arguments: [String], limits: InspectionLimits) throws -> CommandResult {
        // Productive attachment always enters the typed, same-owner route below.
        guard !(executable == "/usr/bin/hdiutil" && arguments.first == "attach") else {
            throw InspectionFailure.invalidMetadata
        }
        if arguments.contains(where: { $0.contains("/dev/fd") }) {
            guard let image = retainedImage else { throw InspectionFailure.invalidMetadata }
            return try run(image: image, executable: executable, arguments: arguments, limits: limits)
        }
        let result = try BoundedCommandRunner().run(executable: executable, arguments: arguments, limits: limits)
        commands.append(result); return result
    }
    func run(image: VerifiedImage, executable: String, arguments: [String], limits: InspectionLimits) throws -> CommandResult {
        guard retainedImage === image else { throw InspectionFailure.invalidMetadata }
        let result = try BoundedCommandRunner().run(image: image, executable: executable, arguments: arguments, limits: limits)
        commands.append(result); return result
    }
    func run(image: VerifiedImage, source: LoopbackImageSource, executable: String, arguments: [String], limits: InspectionLimits) throws -> CommandResult {
        guard retainedImage === image else { throw InspectionFailure.invalidMetadata }
        let result = try BoundedCommandRunner().run(image: image, source: source,
            executable: executable, arguments: arguments, limits: limits)
        commands.append(result); return result
    }
}

public enum ArtifactInspector {
    public static func inspectLocal(version: String, path: String) throws -> InspectionReport {
        try inspect(pin: FirefoxTargets.select(version: version), localPath: path)
    }
    public static func downloadAndInspect(version: String) throws -> InspectionReport {
        try inspect(pin: FirefoxTargets.select(version: version), localPath: nil)
    }
    public static func readRecord(path: String) throws -> Data { try SafeFiles.read(path, maximum: 1_048_576) }

    private static func inspect(pin: TargetPin, localPath: String?) throws -> InspectionReport {
        let workspace = try SafeFiles.makeWorkspace()
        let runner = RecordingRunner()
        var report = InspectionReport(schemaVersion: 1, pin: pin, mode: localPath == nil ? "download-inspect" : "inspect-local",
            sourcePath: localPath, sourceURL: pin.url, redirectChain: [], transportObservedThisRun: false,
            byteIntegrityVerified: false, commands: [], evidence: nil, assessment: nil, refusal: nil,
            workspacePreserved: nil, cleanupVerified: false, installationAuthorized: false, providerActualCost: "unknown")
        do {
            let heldImage: VerifiedImage
            if let localPath { heldImage = try SafeFiles.stageImage(path: localPath, pin: pin, workspace: workspace) }
            else {
                let downloaded = try downloadImage(pin: pin, workspace: workspace)
                heldImage = downloaded.0; report.redirectChain = downloaded.1.redirectChain; report.transportObservedThisRun = true
            }
            // The same retained reader remains alive through detach and all
            // container observations; attach uses a bridge bound to that object.
            runner.retainedImage = heldImage
            defer { runner.retainedImage = nil; heldImage.closeImage() }
            let dmg = heldImage.operand
            report.byteIntegrityVerified = true
            let image = try runner.run(image: heldImage, executable: "/usr/bin/hdiutil", arguments: ["verify", dmg], limits: .init())
            try checkResult(image)
            let os = try runner.run(executable: "/usr/bin/sw_vers", arguments: ["-productVersion"], limits: .init())
            let build = try runner.run(executable: "/usr/bin/sw_vers", arguments: ["-buildVersion"], limits: .init())
            try checkResult(os); try checkResult(build)
            let osVersion = os.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let osBuild = build.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !osVersion.isEmpty, !osBuild.isEmpty else { throw InspectionFailure.invalidMetadata }
            report.evidence = try ReadOnlyMount.withImage(image: heldImage, workspace: workspace, runner: runner) { mount in
                var mountedInfo = statfs()
                guard statfs(mount, &mountedInfo) == 0, mountedInfo.f_flags & UInt32(MNT_RDONLY) != 0,
                      (try mountedPaths()).contains(mount) else { throw InspectionFailure.invalidMount }
                let applications = try FileManager.default.contentsOfDirectory(atPath: mount).filter { $0.hasSuffix(".app") }
                guard applications == ["Firefox.app"] else { throw InspectionFailure.invalidMetadata }
                let app = mount + "/Firefox.app"
                let appFD = try SafeFiles.openPath(app, directory: true); defer { close(appFD) }
                let info = try SafeFiles.read(app + "/Contents/Info.plist", maximum: 1_048_576)
                let executable = try SafeFiles.openPath(app + "/Contents/MacOS/firefox"); defer { close(executable) }
                _ = try SafeFiles.regular(executable)
                let signatureBinding = try HeldSignatureBundleBinding(appPath: app, appDescriptor: appFD,
                    executableDescriptor: executable, infoPlist: info)
                let architectures = try MachOArchitectures.inspect(fileDescriptor: executable)
                func confirmSignatureBinding() throws {
                    try signatureBinding.confirm()
                    var volume = statfs()
                    guard fstatfs(appFD, &volume) == 0, volume.f_flags & UInt32(MNT_RDONLY) != 0,
                          (try mountedPaths()).contains(mount) else { throw InspectionFailure.invalidMount }
                }
                // App and executable are read from the owned read-only mount;
                // no application process or installer is ever started.
                try confirmSignatureBinding()
                let signature = try collectPinnedSignature(appPath: app, pin: pin)
                try confirmSignatureBinding()
                let expected = pinnedSignatureExpectedCommands(app: app, dmg: dmg)
                var observations: [String: CommandResult] = ["imageVerify": image]
                for key in expected.keys.sorted() where key != "imageVerify" {
                    let invocation = expected[key]!
                    observations[key] = try runner.run(executable: invocation.0, arguments: invocation.1, limits: .init())
                }
                try confirmSignatureBinding()
                let collected = AppEvidence(appPath: app, dmgPath: dmg, infoPlist: info, commands: observations,
                                            observedAt: timestamp(), osVersion: osVersion, osBuild: osBuild,
                                            schemaVersion: 3, architectureObservation: .init(
                                                executablePath: app + "/Contents/MacOS/firefox", architectures: architectures),
                                            signatureObservation: signature)
                report.evidence = collected
                report.assessment = try assess(collected, pin: pin, origin: .live)
                return collected
            }
        } catch {
            report.refusal = (error as? InspectionFailure)?.rawValue ?? "inspectionFailed: \(error)"
            report.assessment = nil
        }
        report.commands = runner.commands
        do {
            guard !(try mountedPaths()).contains(where: { $0 == workspace || $0.hasPrefix(workspace + "/") }),
                  report.refusal != InspectionFailure.cleanupFailed.rawValue else { throw InspectionFailure.cleanupFailed }
            let owned = try SafeFiles.privateDirectory(workspace); defer { close(owned) }
            // Remove only the known staged file, then the now-empty workspace.
            // Unknown children are preserved, never recursively removed.
            if unlinkat(owned, "artifact.dmg", 0) != 0 && errno != ENOENT { throw InspectionFailure.cleanupFailed }
            guard rmdir(workspace) == 0 else { throw InspectionFailure.cleanupFailed }
            report.cleanupVerified = true
        } catch {
            report.refusal = InspectionFailure.cleanupFailed.rawValue
            report.assessment = nil; report.workspacePreserved = workspace
        }
        return report
    }
}
