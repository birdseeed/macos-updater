import Foundation

/// Pure licence evidence only. This module cannot perform an installation.
public enum Entitlement: String, CaseIterable, Sendable {
    case beta, trial, paid, grace, expired, revoked, none
}

public enum LicenceRefusal: Error, Equatable, Sendable {
    case verificationRequired, malformedEnvelope, unknownKey, badSignature
    case malformedPayload, wrongBinding, policyBounds, replay, clockUncertain
}

public struct LicenceBinding: Equatable, Sendable {
    public let accountID: String
    public let activationID: String
    public let deviceKeySHA256: String
    public init(accountID: String, activationID: String, deviceKeySHA256: String) {
        self.accountID = accountID
        self.activationID = activationID
        self.deviceKeySHA256 = deviceKeySHA256
    }
}

/// Only the verifier can construct this value from signed bytes.
public struct VerifiedLease: Sendable {
    public let state: Entitlement
    public let binding: LicenceBinding
    public let issuedAt: Int64
    public let permittedUntil: Int64
    public let hardEnd: Int64
    public let sequence: Int64
    public let entitlementRevision: Int64
    public let activationRevision: Int64
    let envelopeHash: Data
    public var checkpoint: LicenceCheckpoint { LicenceCheckpoint(lease: self) }
}

/// An injected high-water mark, not a persistence or authentication adapter.
public struct LicenceCheckpoint: Sendable {
    let lease: VerifiedLease
}

public enum LeaseReplay: Sendable {
    /// Caller has independently established a fresh authenticated refresh.
    case initialAuthenticatedRefresh
    case authenticatedRefresh(after: LicenceCheckpoint)
    case cached(LicenceCheckpoint)
}
