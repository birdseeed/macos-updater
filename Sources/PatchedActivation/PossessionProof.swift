import Foundation
import CryptoKit

/// Trusted context supplied by the pure model, never fields accepted from request JSON.
public struct PossessionContext: Equatable, Sendable {
    public var accountID: String
    public var activationID: String?
    public var operation: DeviceOperation
    public var publicKey: Data
    public var nonce: Data
    public var expiresAt: UInt64
    public init(accountID: String, activationID: String?, operation: DeviceOperation,
                publicKey: Data, nonce: Data, expiresAt: UInt64) {
        self.accountID = accountID; self.activationID = activationID; self.operation = operation
        self.publicKey = publicKey; self.nonce = nonce; self.expiresAt = expiresAt
    }
}

public enum PossessionProof {
    public static func message(actionBytes: Data, context: PossessionContext) throws -> Data {
        do {
            guard (1...5).contains(context.operation.rawValue), context.nonce.count == 32,
                  context.expiresAt <= ActivationIdentity.maximumExactInteger else { throw ActivationError.proofRefused }
            let newIdentity = context.operation == .activate || context.operation == .replace
            guard newIdentity ? context.activationID == nil : context.activationID != nil else {
                throw ActivationError.proofRefused
            }
            let account = try ActivationIdentity.identifierBytes(context.accountID)
            let activation = try context.activationID.map(ActivationIdentity.identifierBytes) ?? Data(repeating: 0, count: 16)
            // Zero is the wire sentinel for actions without an activation, never an existing identity.
            guard newIdentity || activation != Data(repeating: 0, count: 16) else { throw ActivationError.proofRefused }
            let keyHash = try ActivationIdentity.publicKeyDigest(context.publicKey)
            let action = try DeviceRequest.parseAction(actionBytes, operation: context.operation, pathActivationID: context.activationID)
            guard action.publicKey == nil || action.publicKey == context.publicKey else { throw ActivationError.proofRefused }
            var bytes = Data("im.patched.device-proof.v1\0".utf8)
            bytes.append(context.operation.rawValue); bytes.append(account); bytes.append(activation)
            bytes.append(keyHash); bytes.append(context.nonce); bytes.append(Data(SHA256.hash(data: actionBytes)))
            for shift in stride(from: 56, through: 0, by: -8) {
                bytes.append(UInt8(truncatingIfNeeded: context.expiresAt >> UInt64(shift)))
            }
            guard bytes.count == 164 else { throw ActivationError.proofRefused }
            return bytes
        } catch { throw ActivationError.proofRefused }
    }

    public static func verify(actionBytes: Data, signature: Data, context: PossessionContext,
                              now: UInt64) throws {
        do {
            guard signature.count == 64, now <= ActivationIdentity.maximumExactInteger,
                  context.expiresAt > now else { throw ActivationError.proofRefused }
            let bytes = try message(actionBytes: actionBytes, context: context)
            let key = try P256.Signing.PublicKey(x963Representation: context.publicKey)
            try P256SignatureVerification.verify(rawSignature: signature, message: bytes, publicKey: key)
        } catch { throw ActivationError.proofRefused }
    }
}
