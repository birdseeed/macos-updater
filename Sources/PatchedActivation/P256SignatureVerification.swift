import Foundation
import CryptoKit

// Package-internal A1 representation compatibility. No caller or wire bytes are changed.
package enum P256SignatureVerification {
    // P-256 subgroup order n and floor(n / 2), unsigned big-endian scalars.
    private static let order: [UInt8] = [
        0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xbc, 0xe6, 0xfa, 0xad, 0xa7, 0x17, 0x9e, 0x84,
        0xf3, 0xb9, 0xca, 0xc2, 0xfc, 0x63, 0x25, 0x51
    ]
    private static let halfOrder: [UInt8] = [
        0x7f, 0xff, 0xff, 0xff, 0x80, 0x00, 0x00, 0x00,
        0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xde, 0x73, 0x7d, 0x56, 0xd3, 0x8b, 0xcf, 0x42,
        0x79, 0xdc, 0xe5, 0x61, 0x7e, 0x31, 0x92, 0xa8
    ]

    package static func highSRepresentation(rawSignature: Data) throws -> Data {
        let bytes = try validatedBytes(rawSignature)
        return Data(halfOrder.lexicographicallyPrecedes(bytes.suffix(32)) ? bytes : try complement(bytes))
    }

    private static func validatedBytes(_ rawSignature: Data) throws -> [UInt8] {
        guard rawSignature.count == 64 else { throw ActivationError.proofRefused }
        // Copy into zero-based storage so sliced Data has the same scalar interpretation.
        let bytes = Array(rawSignature)
        let r = bytes.prefix(32)
        let s = bytes.suffix(32)
        guard r.contains(where: { $0 != 0 }), s.contains(where: { $0 != 0 }),
              r.lexicographicallyPrecedes(order), s.lexicographicallyPrecedes(order) else {
            throw ActivationError.proofRefused
        }
        return bytes
    }

    // Called only with validated scalars. Public n-S arithmetic preserves R and works
    // in either direction; it never establishes validity without ordinary CryptoKit.
    private static func complement(_ validated: [UInt8]) throws -> [UInt8] {
        var bytes = validated
        var borrow = 0
        for index in stride(from: 31, through: 0, by: -1) {
            let difference = Int(order[index]) - Int(bytes[32 + index]) - borrow
            bytes[32 + index] = UInt8(difference < 0 ? difference + 256 : difference)
            borrow = difference < 0 ? 1 : 0
        }
        guard borrow == 0 else { throw ActivationError.proofRefused }
        return bytes
    }

    package static func verify(rawSignature: Data, message: Data, publicKey: P256.Signing.PublicKey) throws {
        do {
            // Validate before either candidate can be accepted; never replace a working
            // original with a representation the platform might falsely refuse.
            let bytes = try validatedBytes(rawSignature)
            let original = try P256.Signing.ECDSASignature(rawRepresentation: Data(bytes))
            if publicKey.isValidSignature(original, for: message) { return }
            let alternate = try P256.Signing.ECDSASignature(rawRepresentation: Data(complement(bytes)))
            guard publicKey.isValidSignature(alternate, for: message) else {
                throw ActivationError.proofRefused
            }
        } catch { throw ActivationError.proofRefused }
    }
}
