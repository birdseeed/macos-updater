import Foundation
import CryptoKit

public struct LicenceTrust: Sendable {
    let keys: [String: Data]
    let issuer: String
    let audience: String
    public init(keys: [String: Data] = [:], issuer: String = "im.patched.licence",
                audience: String = "im.patched.mac") {
        self.keys = keys; self.issuer = issuer; self.audience = audience
    }
}

public enum SignedLease {
    public static func verify(_ envelope: Data, trust: LicenceTrust = LicenceTrust(),
                              binding: LicenceBinding, replay: LeaseReplay) throws -> VerifiedLease {
        let object = try LicenceStrictJSON.object(envelope, maximumBytes: 16_384, refusal: .malformedEnvelope)
        guard Set(object.keys) == ["keyID", "payload", "signature"],
              case .string(let keyID) = object["keyID"], !keyID.isEmpty, keyID.utf8.count <= 128,
              case .string(let payloadText) = object["payload"],
              case .string(let signatureText) = object["signature"] else { throw LicenceRefusal.malformedEnvelope }
        guard let keyData = trust.keys[keyID],
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else { throw LicenceRefusal.unknownKey }
        guard let payload = Data(base64Encoded: payloadText), payload.count <= 8_192,
              payload.base64EncodedString() == payloadText,
              let signature = Data(base64Encoded: signatureText), signature.count == 64,
              signature.base64EncodedString() == signatureText else { throw LicenceRefusal.malformedEnvelope }
        let message = Data("im.patched.licence.v1\0".utf8) + payload
        guard key.isValidSignature(signature, for: message) else { throw LicenceRefusal.badSignature }
        // Never parse or reserialise payload bytes before their signature has verified.
        let claims = try LicenceStrictJSON.object(payload, maximumBytes: 8_192, refusal: .malformedPayload)
        guard try claims.number("schemaVersion") == 1,
              try claims.text("issuer") == trust.issuer, try claims.text("audience") == trust.audience else {
            throw LicenceRefusal.malformedPayload
        }
        let account = try claims.text("accountID"), activation = try claims.text("activationID")
        let hash = try claims.text("deviceKeySHA256")
        guard lowerHex(account, length: 32), lowerHex(activation, length: 32), lowerHex(hash, length: 64) else {
            throw LicenceRefusal.malformedPayload
        }
        let actualBinding = LicenceBinding(accountID: account, activationID: activation, deviceKeySHA256: hash)
        guard binding == actualBinding else { throw LicenceRefusal.wrongBinding }
        guard let state = Entitlement(rawValue: try claims.text("state")) else { throw LicenceRefusal.malformedPayload }
        let sequence = try claims.number("sequence")
        let entitlementRevision = try claims.number("entitlementRevision")
        let activationRevision = try claims.number("activationRevision")
        guard sequence > 0, entitlementRevision > 0, activationRevision > 0 else { throw LicenceRefusal.malformedPayload }
        let issued = try claims.number("issuedAt"), until = try claims.number("permittedUntil"), hardEnd = try claims.number("hardEnd")
        try LicencePolicy.validate(claims, state: state, issued: issued, until: until, hardEnd: hardEnd)
        let lease = VerifiedLease(state: state, binding: actualBinding, issuedAt: issued, permittedUntil: until,
                                  hardEnd: hardEnd, sequence: sequence, entitlementRevision: entitlementRevision,
                                  activationRevision: activationRevision, envelopeHash: Data(SHA256.hash(data: envelope)))
        try validateReplay(lease, replay: replay)
        return lease
    }

    private static func lowerHex(_ value: String, length: Int) -> Bool {
        value.utf8.count == length && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func validateReplay(_ lease: VerifiedLease, replay: LeaseReplay) throws {
        let previous: VerifiedLease
        let cached: Bool
        switch replay {
        case .initialAuthenticatedRefresh: return
        case .authenticatedRefresh(let checkpoint): previous = checkpoint.lease; cached = false
        case .cached(let checkpoint): previous = checkpoint.lease; cached = true
        }
        guard lease.binding == previous.binding,
              lease.entitlementRevision >= previous.entitlementRevision,
              lease.activationRevision >= previous.activationRevision,
              lease.issuedAt >= previous.issuedAt else { throw LicenceRefusal.replay }
        if cached {
            guard lease.sequence == previous.sequence, lease.envelopeHash == previous.envelopeHash else {
                throw LicenceRefusal.replay
            }
        } else {
            guard lease.sequence > previous.sequence else { throw LicenceRefusal.replay }
            // An activation-level revocation cannot be laundered through none/expired.
            guard previous.state != .revoked || lease.state == .revoked else { throw LicenceRefusal.replay }
        }
    }
}
