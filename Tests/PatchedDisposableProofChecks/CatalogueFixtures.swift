import Foundation
import CryptoKit

// Publicly known TEST material. This file belongs solely to the check/fixture generator target.
// It must never be copied to the proof library or runtime harness.
enum CatalogueFixture {
    static let now = 1_791_590_400.0
    static let keyID = "patched-disposable-test-v1"
    static let catalogueID = "patched-disposable-firefox"
    static var key: Curve25519.Signing.PrivateKey { try! .init(rawRepresentation: Data(repeating: 0x11, count: 32)) }
    static func envelope(sequence: UInt64 = 7, now: Double = now, expired: Bool = false,
                         untrusted: Bool = false, badSignature: Bool = false,
                         artifactDigest: String = "40a0a649120635460256dae9ad63e40377f77326cbc9c449a5d0a1d7f5dd7982") throws -> Data {
        let id = untrusted ? "unrelated-test-key" : keyID
        let payload = try json(["schemaVersion": 1, "domain": "im.patched.catalogue.v1", "keyID": id,
            "catalogueID": catalogueID, "sequence": sequence, "issuedAt": UInt64(now) - 3600,
            "expiresAt": UInt64(now) + (expired ? 0 : 3600),
            "artifact": ["bundleID": "org.mozilla.firefox", "teamID": "43AQ936H96", "platform": "macOS",
                         "minimumOS": "27.0.1", "maximumOS": "27.0.1", "version": "157.0.1", "sha256": artifactDigest,
                         "byteLength": 161550118]])
        let signer = untrusted ? try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 0x22, count: 32)) : key
        var signature = try signer.signature(for: Data("im.patched.catalogue.v1\0".utf8) + payload)
        if badSignature { signature[0] ^= 1 }
        return try json(["keyID": id, "payload": payload.base64EncodedString(), "signature": signature.base64EncodedString()])
    }
}
