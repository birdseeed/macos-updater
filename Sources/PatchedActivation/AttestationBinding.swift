import Foundation

public struct FixtureAttestationResult: Equatable, Sendable {
    public var keyID: Data
    public var counter: UInt64
    public init(keyID: Data, counter: UInt64) { self.keyID = keyID; self.counter = counter }
}

/// Injection can prove fixture transitions only, never Apple or hardware validation.
@_spi(Testing) public protocol FixtureAttestationValidating {
    func validate(evidence: Data, keyID: Data?, message: Data,
                  assertion: Bool) throws -> FixtureAttestationResult
}

public enum AttestationBinding {
    /// Availability and a caller's claim cannot authenticate supplied evidence.
    /// Only the ledger's explicit fixture adapter may label a validated fixture.
    public static func assurance(evidenceSupplied: Bool, adapterAvailable: Bool) throws -> KeyAssurance {
        guard !evidenceSupplied else { throw ActivationError.proofRefused }
        return .secureStorageFallback
    }

    static func validate(_ proof: DeviceProofEnvelope, message: Data,
                         existing: FixtureAttestationResult?, operation: DeviceOperation,
                         adapter: (any FixtureAttestationValidating)?) throws -> FixtureAttestationResult? {
        guard let evidence = proof.attestation ?? proof.assertion else {
            guard operation != .rebind else { throw ActivationError.proofRefused }
            return nil
        }
        guard let adapter else { throw ActivationError.proofRefused }
        let validated: FixtureAttestationResult
        do {
            validated = try adapter.validate(evidence: evidence, keyID: proof.attestKeyID,
                                             message: message, assertion: proof.assertion != nil)
        } catch { throw ActivationError.proofRefused }
        guard (1...64).contains(validated.keyID.count),
              validated.counter <= ActivationIdentity.maximumExactInteger else { throw ActivationError.proofRefused }
        if proof.assertion != nil {
            guard let existing, validated.keyID == existing.keyID else { throw ActivationError.proofRefused }
            guard validated.counter > existing.counter else { throw ActivationError.assertionStale }
        } else {
            guard validated.keyID == proof.attestKeyID else { throw ActivationError.proofRefused }
            if operation == .rebind, existing?.keyID == validated.keyID {
                // Resetting a counter is only meaningful with a new fixture attestation key.
                throw ActivationError.proofRefused
            }
        }
        return validated
    }
}
