import Foundation
import Security

/// Refusal-only diagnostic data for the installed observer.
/// This record cannot represent an accepted signature observation or authority.
@_spi(Testing) public struct InstalledSignatureRefusalDiagnostic {
    public let appPath: String
    public let validationFlags: UInt32
    public let validationStatus: Int32
    public let signingInformationStatus: Int32
    public let teamID: String?
    public let identifier: String?

    public init(appPath: String, validationFlags: UInt32,
                validationStatus: Int32, signingInformationStatus: Int32,
                teamID: String?, identifier: String?) {
        self.appPath = appPath
        self.validationFlags = validationFlags
        self.validationStatus = validationStatus
        self.signingInformationStatus = signingInformationStatus
        self.teamID = teamID
        self.identifier = identifier
    }
}

// Use the exact pinned identifier/team grammar without creating an observation.
// A missing team is valid diagnostic data for a generically valid ad hoc signature.
func installedSignatureDiagnosticFieldsAreValid(teamID: String?, identifier: String?) -> Bool {
    guard let identifier else { return false }
    do {
        _ = try PinnedSignatureRequirement.make(teamID: teamID ?? "AAAAAAAAAA", bundleID: identifier)
        return true
    } catch { return false }
}

// Called only after the installed observer's pinned collector has refused and
// its caller-held binding has been confirmed. Generic validity can explain that
// refusal, but can never produce accepted signature evidence or authority.
func collectInstalledSignatureRefusalDiagnostic(appPath: String) throws -> InstalledSignatureRefusalDiagnostic {
    guard safeEvidencePath(appPath) else { throw InspectionFailure.signatureRejected }
    var staticCode: SecStaticCode?
    let createStatus = SecStaticCodeCreateWithPath(URL(fileURLWithPath: appPath) as CFURL,
                                                  SecCSFlags(), &staticCode)
    guard createStatus == errSecSuccess, let staticCode else {
        throw InspectionFailure.signatureRejected
    }
    let flags = SecCSFlags(rawValue: PinnedSignatureRequirement.validationFlags)
    let validationStatus = SecStaticCodeCheckValidity(staticCode, flags, nil)
    guard validationStatus == errSecSuccess else { throw InspectionFailure.signatureRejected }
    var signingInformation: CFDictionary?
    let signingInformationStatus = SecCodeCopySigningInformation(staticCode,
        SecCSFlags(rawValue: kSecCSSigningInformation), &signingInformation)
    guard signingInformationStatus == errSecSuccess, let signingInformation else {
        throw InspectionFailure.signatureRejected
    }
    let information = signingInformation as NSDictionary
    guard let identifier = information[kSecCodeInfoIdentifier as String] as? String else {
        throw InspectionFailure.signatureRejected
    }
    let teamID: String?
    if let rawTeam = information[kSecCodeInfoTeamIdentifier as String] {
        // NSNull and every other present non-string value are malformed, rather
        // than the legitimate absence used by a valid ad hoc signature.
        guard let team = rawTeam as? String else { throw InspectionFailure.signatureRejected }
        teamID = team
    } else {
        teamID = nil
    }
    guard installedSignatureDiagnosticFieldsAreValid(teamID: teamID, identifier: identifier) else {
        throw InspectionFailure.signatureRejected
    }
    return InstalledSignatureRefusalDiagnostic(appPath: appPath,
        validationFlags: PinnedSignatureRequirement.validationFlags,
        validationStatus: validationStatus, signingInformationStatus: signingInformationStatus,
        teamID: teamID, identifier: identifier)
}
