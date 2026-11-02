import Foundation
import Security

public struct SignatureObservation: Codable, Equatable, Sendable {
    public var appPath: String
    public var requirement: String
    public var validationFlags: UInt32
    public var validationStatus: Int32
    public var signingInformationStatus: Int32
    public var teamID: String
    public var identifier: String
    public var startedAt: String
    public var finishedAt: String

    public init(appPath: String, requirement: String, validationFlags: UInt32,
                validationStatus: Int32, signingInformationStatus: Int32,
                teamID: String, identifier: String, startedAt: String, finishedAt: String) {
        self.appPath = appPath; self.requirement = requirement; self.validationFlags = validationFlags
        self.validationStatus = validationStatus; self.signingInformationStatus = signingInformationStatus
        self.teamID = teamID; self.identifier = identifier; self.startedAt = startedAt; self.finishedAt = finishedAt
    }
}

public enum PinnedSignatureRequirement {
    public static let validationFlags: UInt32 = kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode

    public static func make(teamID: String, bundleID: String) throws -> String {
        let team = Array(teamID.utf8), bundle = Array(bundleID.utf8)
        guard team.count == 10, team.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }),
              (1...255).contains(bundle.count),
              bundle.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) ||
                  (48...57).contains($0) || $0 == 45 || $0 == 46 }) else {
            throw InspectionFailure.invalidMetadata
        }
        let components = bundleID.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 2, components.allSatisfy({ !$0.isEmpty }) else {
            throw InspectionFailure.invalidMetadata
        }
        return "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" and identifier \"\(bundleID)\""
    }
}

// Called only while the inspector holds its private read-only mounted bundle.
func collectPinnedSignature(appPath: String, pin: TargetPin) throws -> SignatureObservation {
    guard safeEvidencePath(appPath) else { throw InspectionFailure.invalidMetadata }
    let requirementText = try PinnedSignatureRequirement.make(teamID: pin.teamID, bundleID: pin.bundleID)
    let startedAt = timestamp()
    var staticCode: SecStaticCode?
    let createStatus = SecStaticCodeCreateWithPath(URL(fileURLWithPath: appPath) as CFURL,
                                                  SecCSFlags(), &staticCode)
    guard createStatus == errSecSuccess else { throw InspectionFailure.signatureRejected }
    guard let staticCode else { throw InspectionFailure.signatureRejected }
    var parsedRequirement: SecRequirement?
    let requirementStatus = SecRequirementCreateWithString(requirementText as CFString,
                                                           SecCSFlags(), &parsedRequirement)
    guard requirementStatus == errSecSuccess else { throw InspectionFailure.signatureRejected }
    guard let parsedRequirement else { throw InspectionFailure.signatureRejected }
    let flags = SecCSFlags(rawValue: PinnedSignatureRequirement.validationFlags)
    let validationStatus = SecStaticCodeCheckValidity(staticCode, flags, parsedRequirement)
    guard validationStatus == errSecSuccess else { throw InspectionFailure.signatureRejected }
    var signingInformation: CFDictionary?
    let signingInformationStatus = SecCodeCopySigningInformation(staticCode,
        SecCSFlags(rawValue: kSecCSSigningInformation), &signingInformation)
    guard signingInformationStatus == errSecSuccess else { throw InspectionFailure.signatureRejected }
    guard let signingInformation else { throw InspectionFailure.signatureRejected }
    let information = signingInformation as NSDictionary
    guard let teamID = information[kSecCodeInfoTeamIdentifier as String] as? String else {
        throw InspectionFailure.signatureRejected
    }
    guard let identifier = information[kSecCodeInfoIdentifier as String] as? String else {
        throw InspectionFailure.signatureRejected
    }
    guard teamID == pin.teamID else { throw InspectionFailure.wrongTeam }
    guard identifier == pin.bundleID else { throw InspectionFailure.wrongBundle }
    return SignatureObservation(appPath: appPath, requirement: requirementText,
        validationFlags: PinnedSignatureRequirement.validationFlags, validationStatus: validationStatus,
        signingInformationStatus: signingInformationStatus, teamID: teamID, identifier: identifier,
        startedAt: startedAt, finishedAt: timestamp())
}
