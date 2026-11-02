import Foundation
import Darwin

/// One monotonic identity-observation budget shared by every row of a scan.
public final class InstalledIdentityScanBudget: @unchecked Sendable {
    public let seconds: Double
    private let started: UInt64
    public init(seconds: Double = 15) {
        self.seconds = seconds
        started = DispatchTime.now().uptimeNanoseconds
    }
    internal func remaining() throws -> Double {
        guard seconds.isFinite, seconds > 0, seconds <= 180 else { throw InspectionFailure.invalidMetadata }
        let now = DispatchTime.now().uptimeNanoseconds
        guard now >= started else { throw InspectionFailure.commandTimedOut }
        let remaining = seconds - Double(now - started) / 1_000_000_000
        guard remaining > 0 else { throw InspectionFailure.commandTimedOut }
        return remaining
    }
}

public enum InstalledIdentityWorker {
    public static func collect(appPath: String, appDescriptor: Int32,
                               executableDescriptor: Int32, infoPlist: Data,
                               pin: TargetPin, budget: InstalledIdentityScanBudget) throws -> SignatureObservation {
        try transport(appPath: appPath, appDescriptor: appDescriptor,
            executableDescriptor: executableDescriptor, infoPlist: infoPlist, pin: pin,
            budget: budget, selection: { try InstalledIdentitySelf.capture() },
            commandSeconds: 3, outputBytes: 16_384, boundaryObserver: nil)
    }

    /// Called before constructing the SwiftUI App or any client session. This
    /// read-only child route accepts no caller-supplied executable or collector.
    public static func dispatchChild(arguments: [String]) -> Int32? {
        guard arguments.dropFirst().contains(where: { $0.hasPrefix("--patched-installed-identity") }) else { return nil }
        guard arguments.count == 3, arguments[1] == childMode else { return 64 }
        do {
            let own = try InstalledIdentitySelf.capture()
            guard arguments[2].utf8.count <= 43_692,
                  let bytes = Data(base64Encoded: arguments[2]), bytes.count <= 32_768 else {
                throw InspectionFailure.invalidRecord
            }
            let request = try InstalledIdentityWire.decodeRequest(bytes)
            let app = try SafeFiles.openPath(request.appPath, directory: true)
            defer { close(app) }
            let executable = try SafeFiles.openPath(request.appPath + "/Contents/MacOS/firefox")
            defer { close(executable) }
            let plist = try SafeFiles.read(request.appPath + "/Contents/Info.plist", maximum: 1_048_576)
            let binding = try HeldSignatureBundleBinding(appPath: request.appPath,
                appDescriptor: app, executableDescriptor: executable, infoPlist: plist)
            try InstalledIdentityWire.validate(request, infoPlist: plist)
            guard request.binding == (try InstalledIdentityBinding(app: app, executable: executable, plist: plist)) else {
                throw InspectionFailure.unsafePath
            }
            try own.confirm()
            let result = Result { try InstalledBundleObserver.collect(appPath: request.appPath,
                appDescriptor: app, executableDescriptor: executable, infoPlist: plist, pin: request.pin) }
            // Both pinned validation and refusal diagnostics happened in this one
            // child. Changes override success and every native refusal.
            try binding.confirm()
            guard request.binding == (try InstalledIdentityBinding(app: app, executable: executable, plist: plist)) else {
                throw InspectionFailure.unsafePath
            }
            try own.confirm()
            let payload: InstalledIdentityResult
            switch result {
            case .success(let signature): payload = InstalledIdentityResult(signature)
            case .failure: payload = .refused
            }
            let output = try JSONEncoder().encode(InstalledIdentityEnvelope(schemaVersion: 1, request: request, result: payload))
            guard output.count <= 16_384 else { throw InspectionFailure.outputLimit }
            FileHandle.standardOutput.write(output)
            return 0
        } catch { return 65 }
    }

    private static let childMode = "--patched-installed-identity-worker-v1"

    fileprivate static func transport(appPath: String, appDescriptor: Int32,
        executableDescriptor: Int32, infoPlist: Data, pin: TargetPin,
        budget: InstalledIdentityScanBudget, selection: () throws -> InstalledIdentityChildSelection,
        commandSeconds: Double, outputBytes: Int,
        boundaryObserver: (@Sendable () throws -> Void)?) throws -> SignatureObservation {
        // Capture the caller's borrowed physical binding before any selection or
        // child launch. Neither this function nor the child owns those descriptors.
        let binding = try HeldSignatureBundleBinding(appPath: appPath, appDescriptor: appDescriptor,
            executableDescriptor: executableDescriptor, infoPlist: infoPlist)
        let physical = try InstalledIdentityBinding(app: appDescriptor, executable: executableDescriptor, plist: infoPlist)
        let result: Result<SignatureObservation, Error> = Result {
            let request = InstalledIdentityRequest(schemaVersion: 1, appPath: appPath, pin: pin,
                requirement: try PinnedSignatureRequirement.make(teamID: pin.teamID, bundleID: pin.bundleID),
                validationFlags: PinnedSignatureRequirement.validationFlags, binding: physical,
                nonce: UUID().uuidString)
            try InstalledIdentityWire.validate(request, infoPlist: infoPlist)
            _ = try budget.remaining()
            guard commandSeconds.isFinite, commandSeconds > 0, commandSeconds <= 180,
                  outputBytes > 0, outputBytes <= 16_384 else { throw InspectionFailure.invalidMetadata }
            let child = try selection()
            // Keep authentication custody alive until after transport and decode,
            // including every thrown error from the runner.
            let captured: Result<SignatureObservation, Error> = Result {
                try child.confirm()
                let bytes = try JSONEncoder().encode(request)
                guard bytes.count <= 32_768 else { throw InspectionFailure.outputLimit }
                var limits = InspectionLimits()
                limits.commandSeconds = min(commandSeconds, try budget.remaining())
                limits.outputBytes = outputBytes
                let command = try BoundedCommandRunner().run(executable: child.executable,
                    arguments: child.arguments + [bytes.base64EncodedString()], limits: limits)
                guard !command.timedOut else { throw InspectionFailure.commandTimedOut }
                guard !command.outputExceeded else { throw InspectionFailure.outputLimit }
                guard command.exitCode == 0, command.stderr.isEmpty,
                      let response = command.stdout.data(using: .utf8) else { throw InspectionFailure.commandFailed }
                _ = try budget.remaining()
                let envelope = try InstalledIdentityWire.decodeEnvelope(response)
                guard envelope.schemaVersion == 1, envelope.request == request else { throw InspectionFailure.invalidRecord }
                let value = envelope.result
                guard value.kind == "pinned", value.validationStatus == 0, value.signingInformationStatus == 0,
                      value.teamID == pin.teamID, value.identifier == pin.bundleID,
                      let start = parseTimestamp(value.startedAt), let end = parseTimestamp(value.finishedAt), end >= start else {
                    throw InspectionFailure.signatureRejected
                }
                return SignatureObservation(appPath: appPath, requirement: request.requirement,
                    validationFlags: request.validationFlags, validationStatus: value.validationStatus,
                    signingInformationStatus: value.signingInformationStatus, teamID: value.teamID,
                    identifier: value.identifier, startedAt: value.startedAt, finishedAt: value.finishedAt)
            }
            try child.confirm()
            return try captured.get()
        }
        let boundary = Result { try boundaryObserver?() }
        // This check executes after every outcome, including admission refusal,
        // spawn failure, timeout, output overflow and malformed responses.
        try binding.confirm()
        guard physical == (try InstalledIdentityBinding(app: appDescriptor,
            executable: executableDescriptor, plist: infoPlist)) else { throw InspectionFailure.unsafePath }
        try boundary.get()
        return try result.get()
    }
}

/// Fixture-only child injection. It must never select or issue production evidence.
@_spi(Testing) public enum InstalledIdentityWorkerTestAdapter {
    public static func collect(appPath: String, appDescriptor: Int32,
                               executableDescriptor: Int32, infoPlist: Data,
                               pin: TargetPin, budget: InstalledIdentityScanBudget,
                               childExecutable: String, childArguments: [String],
                               commandSeconds: Double = 0.2, outputBytes: Int = 4096,
                               boundaryObserver: (@Sendable () throws -> Void)? = nil) throws -> SignatureObservation {
        try InstalledIdentityWorker.transport(appPath: appPath, appDescriptor: appDescriptor,
            executableDescriptor: executableDescriptor, infoPlist: infoPlist, pin: pin,
            budget: budget, selection: {
                InstalledIdentityFixtureChild(executable: childExecutable, arguments: childArguments)
            }, commandSeconds: commandSeconds, outputBytes: outputBytes, boundaryObserver: boundaryObserver)
    }
}

// The fixture selection cannot be used by the public productive entry point.
internal protocol InstalledIdentityChildSelection {
    var executable: String { get }
    var arguments: [String] { get }
    func confirm() throws
}
private struct InstalledIdentityFixtureChild: InstalledIdentityChildSelection {
    let executable: String
    let arguments: [String]
    func confirm() throws {}
}
