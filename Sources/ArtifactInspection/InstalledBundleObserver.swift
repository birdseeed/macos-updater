import Foundation

/// Read-only signature observation for a caller-held installed bundle.
/// An observation grants no installation or other live authority.
public enum InstalledBundleObserver {
    public static func collect(appPath: String, appDescriptor: Int32,
                               executableDescriptor: Int32, infoPlist: Data,
                               pin: TargetPin) throws -> SignatureObservation {
        try collectInstalledBundleSignature(appPath: appPath,
            appDescriptor: appDescriptor, executableDescriptor: executableDescriptor,
            infoPlist: infoPlist, pin: pin,
            collector: { path, target in
                try collectPinnedSignature(appPath: path, pin: target)
            }, diagnostic: { path in
                try collectInstalledSignatureRefusalDiagnostic(appPath: path)
            })
    }
}

// One pipeline for native collection and synthetic injection; neither issues authority.
private func collectInstalledBundleSignature(
    appPath: String, appDescriptor: Int32, executableDescriptor: Int32,
    infoPlist: Data, pin: TargetPin,
    collector: (String, TargetPin) throws -> SignatureObservation,
    diagnostic: (String) throws -> InstalledSignatureRefusalDiagnostic
) throws -> SignatureObservation {
    guard FirefoxTargets.pins.contains(pin) else { throw InspectionFailure.unknownTarget }
    guard safeEvidencePath(appPath), infoPlist.count <= 1_048_576 else {
        throw InspectionFailure.invalidMetadata
    }
    let metadata: [String: Any]
    do {
        guard let value = try PropertyListSerialization.propertyList(from: infoPlist,
            options: [], format: nil) as? [String: Any] else { throw InspectionFailure.invalidMetadata }
        metadata = value
    } catch { throw InspectionFailure.invalidMetadata }
    guard metadata["CFBundleIdentifier"] as? String == pin.bundleID else { throw InspectionFailure.wrongBundle }
    guard metadata["CFBundleShortVersionString"] as? String == pin.version else { throw InspectionFailure.wrongVersion }
    guard metadata["CFBundleExecutable"] as? String == "firefox",
          metadata["CFBundlePackageType"] as? String == "APPL" else { throw InspectionFailure.invalidMetadata }
    let binding = try HeldSignatureBundleBinding(appPath: appPath, appDescriptor: appDescriptor,
        executableDescriptor: executableDescriptor, infoPlist: infoPlist)
    let requirement = try PinnedSignatureRequirement.make(teamID: pin.teamID, bundleID: pin.bundleID)
    let observation: SignatureObservation
    do {
        observation = try collector(appPath, pin)
    } catch InspectionFailure.signatureRejected {
        // Only a collector-thrown pinned refusal enters this path. A returned
        // observation is still checked below and can never trigger diagnostics.
        try binding.confirm()
        let result = Result { try diagnostic(appPath) }
        // Check even when diagnostics failed: a changed binding takes precedence
        // over every identity classification and every diagnostic error.
        try binding.confirm()
        guard case .success(let refusal) = result,
              refusal.appPath == appPath,
              refusal.validationFlags == PinnedSignatureRequirement.validationFlags,
              refusal.validationStatus == 0, refusal.signingInformationStatus == 0,
              installedSignatureDiagnosticFieldsAreValid(teamID: refusal.teamID,
                  identifier: refusal.identifier) else {
            throw InspectionFailure.signatureRejected
        }
        guard refusal.teamID == pin.teamID else { throw InspectionFailure.wrongTeam }
        guard refusal.identifier == pin.bundleID else { throw InspectionFailure.wrongBundle }
        // Matching diagnostic identity cannot overturn the original pinned refusal.
        throw InspectionFailure.signatureRejected
    }
    try binding.confirm()
    guard observation.appPath == appPath, observation.requirement == requirement,
          observation.validationFlags == PinnedSignatureRequirement.validationFlags,
          let start = parseTimestamp(observation.startedAt), let end = parseTimestamp(observation.finishedAt),
          end >= start else { throw InspectionFailure.invalidMetadata }
    guard observation.validationStatus == 0, observation.signingInformationStatus == 0 else {
        throw InspectionFailure.signatureRejected
    }
    guard observation.teamID == pin.teamID else { throw InspectionFailure.wrongTeam }
    guard observation.identifier == pin.bundleID else { throw InspectionFailure.wrongBundle }
    return observation
}

/// Injects observation data into the same pipeline for synthetic checks only.
/// The adapter has no native collector fallback and issues no live authority.
@_spi(Testing) public enum InstalledBundleObserverTestAdapter {
    public static func collect(appPath: String, appDescriptor: Int32,
                               executableDescriptor: Int32, infoPlist: Data,
                               pin: TargetPin,
                               collector: (String, TargetPin) throws -> SignatureObservation)
        throws -> SignatureObservation {
        try collectInstalledBundleSignature(appPath: appPath,
            appDescriptor: appDescriptor, executableDescriptor: executableDescriptor,
            infoPlist: infoPlist, pin: pin, collector: collector,
            diagnostic: { _ in throw InspectionFailure.signatureRejected })
    }
}

// Both callbacks are mandatory; injected checks never fall back to native Security.
extension InstalledBundleObserverTestAdapter {
    @_spi(Testing) public static func collect(appPath: String, appDescriptor: Int32,
                               executableDescriptor: Int32, infoPlist: Data,
                               pin: TargetPin,
                               collector: (String, TargetPin) throws -> SignatureObservation,
                               diagnostic: (String) throws -> InstalledSignatureRefusalDiagnostic)
        throws -> SignatureObservation {
        try collectInstalledBundleSignature(appPath: appPath, appDescriptor: appDescriptor,
            executableDescriptor: executableDescriptor, infoPlist: infoPlist,
            pin: pin, collector: collector, diagnostic: diagnostic)
    }
}
