import Foundation
import CryptoKit
@_spi(Testing) import PatchedActivation

@MainActor func registerWireChecks() {
    check("checked-in corpus matches independent bytes and fixed signatures") {
        for number in 1...5 {
            let bytes = try Data(contentsOf: URL(fileURLWithPath: "Fixtures/Activation/vectors/operation-\(number).json"))
            let v = try JSONDecoder().decode(ProofVector.self, from: bytes)
            let operation = DeviceOperation(rawValue: v.operation)!
            let action = Data(base64Encoded: v.actionBase64)!
            let context = PossessionContext(accountID: v.accountID, activationID: v.activationID,
                operation: operation, publicKey: Data(base64Encoded: v.publicKeyBase64)!,
                nonce: Data(base64Encoded: v.nonceBase64)!, expiresAt: v.expiresAt)
            try expect(action == actionBytes(operation), "Fixed action drift")
            let message = referenceMessage(action, context)
            try expect(message.count == 164 && hex(message) == v.messageHex, "Fixed exact message drift")
            try expect(hex(digest(action)) == v.actionSHA256, "Fixed action digest drift")
            let key = try P256.Signing.PublicKey(x963Representation: context.publicKey)
            let sig = try P256.Signing.ECDSASignature(rawRepresentation: Data(base64Encoded: v.signatureBase64)!)
            try expect(key.isValidSignature(sig, for: message), "Checked-in fixture signature invalid")
        }
    }
    for operation in [DeviceOperation.activate, .replace, .refresh, .rebind, .recoveryPossession] {
        check("operation \(operation.rawValue) exact 164-byte message and proof") {
            let f = try ProofFixture(operation: operation)
            let message = try PossessionProof.message(actionBytes: f.action, context: f.context)
            try expect(message == referenceMessage(f.action, f.context) && message.count == 164, "Exact proof bytes differ")
            try PossessionProof.verify(actionBytes: f.action, signature: f.signature, context: f.context, now: fixtureNow)
            let parsed = try DeviceRequest.parse(f.body, operation: operation, pathActivationID: f.context.activationID)
            try expect(parsed.action.bytes == f.action && parsed.action.digest == digest(f.action), "Original action bytes not retained")
        }
    }
    for field in ["operation", "account", "activation", "key", "nonce", "expiry", "action", "signature", "domain"] {
        check("proof changed \(field) refuses") {
            var f = try ProofFixture(operation: .refresh)
            switch field {
            case "operation": f.context.operation = .rebind
            case "account": f.context.accountID = otherAccount
            case "activation": f.context.activationID = fixtureID(101)
            case "key": f.context.publicKey = try fixtureKey(2).publicKey.x963Representation
            case "nonce": f.context.nonce[0] ^= 1
            case "expiry": f.context.expiresAt += 1
            case "action": f.action = try actionBytes(.refresh, request: 2)
            case "signature": f.signature = try fixtureKey(2).signature(for: referenceMessage(f.action, f.context)).rawRepresentation
            default:
                var wrongDomain = referenceMessage(f.action, f.context); wrongDomain[0] ^= 1
                f.signature = try fixtureKey().signature(for: wrongDomain).rawRepresentation
            }
            try refuses(.proofRefused) { try PossessionProof.verify(actionBytes: f.action, signature: f.signature, context: f.context, now: fixtureNow) }
        }
    }
    check("proof expiry is exclusive") {
        let f = try ProofFixture()
        try refuses(.proofRefused) { try PossessionProof.verify(actionBytes: f.action, signature: f.signature, context: f.context, now: 1_300) }
    }
    for length in [0, 63, 65, 72] {
        check("non-raw64 signature length \(length) refuses") {
            let f = try ProofFixture()
            try refuses(.proofRefused) { try PossessionProof.verify(actionBytes: f.action, signature: Data(repeating: 0, count: length), context: f.context, now: fixtureNow) }
        }
    }
    check("equivalent escaped name preserves distinct signed action bytes") {
        let f = try ProofFixture()
        let alternate = Data(String(decoding: f.action, as: UTF8.self).replacingOccurrences(of: "Fixture Mac", with: "\\u0046ixture Mac").utf8)
        let a = try DeviceRequest.parse(f.body, operation: .activate)
        let b = try DeviceRequest.parse(bodyBytes(action: alternate, signature: f.signature), operation: .activate)
        try expect(a.action.displayName == b.action.displayName, "Equivalent decoded name changed")
        try expect(a.action.digest != b.action.digest && b.action.digest == digest(alternate), "Parser reserialized signed bytes")
        try refuses(.proofRefused) { try PossessionProof.verify(actionBytes: alternate, signature: f.signature, context: f.context, now: fixtureNow) }
    }
    let malformed: [(String, (String) -> String)] = [
        ("duplicate", { $0.replacingOccurrences(of: "{", with: "{\"requestID\":\"\(fixtureID(1))\",") }),
        ("decoded duplicate", { $0.replacingOccurrences(of: "{", with: "{\"request\\u0049D\":\"\(fixtureID(1))\",") }),
        ("unknown", { String($0.dropLast()) + ",\"extra\":1}" }),
        ("missing", { $0.replacingOccurrences(of: ",\"displayName\":\"Fixture Mac\"", with: "") }),
        ("reordered", { "{\"displayName\":\"Fixture Mac\"," + $0.dropFirst().replacingOccurrences(of: ",\"displayName\":\"Fixture Mac\"", with: "") }),
        ("whitespace", { " " + $0 }), ("trailing", { $0 + "{}" }),
        ("BOM", { "\u{feff}" + $0 }), ("NUL", { $0 + "\0" }),
        ("nesting", { $0.replacingOccurrences(of: "\"Fixture Mac\"", with: "{\"nested\":{\"nested\":1}}") }),
        ("oversize", { $0.replacingOccurrences(of: "Fixture Mac", with: String(repeating: "x", count: 1_025)) })
    ]
    for (name, mutate) in malformed {
        check("action \(name) refuses") {
            let f = try ProofFixture()
            let invalid = Data(mutate(String(decoding: f.action, as: UTF8.self)).utf8)
            try refuses(.invalidRequest) { _ = try DeviceRequest.parse(bodyBytes(action: invalid, signature: f.signature), operation: .activate) }
        }
    }
    for token in ["-1", "+1", "01", "1.0", "1e0", "true", "\"1\"", "9007199254740992"] {
        check("integer token \(token) refuses") {
            let bytes = try actionBytes(.deactivate, revision: token)
            try refuses(.invalidRequest) { _ = try DeviceRequest.parse(bodyBytes(action: bytes), operation: .deactivate, pathActivationID: fixtureID(100)) }
        }
    }
    check("maximum exact integer parses") {
        let bytes = try actionBytes(.deactivate, revision: "9007199254740991")
        let parsed = try DeviceRequest.parse(bodyBytes(action: bytes), operation: .deactivate, pathActivationID: fixtureID(100))
        try expect(parsed.action.expectedRevision == 9_007_199_254_740_991, "Integer bound incorrectly narrowed")
    }
    check("path and action activation mismatch refuses") {
        let f = try ProofFixture(operation: .refresh)
        try refuses(.invalidRequest) { _ = try DeviceRequest.parse(f.body, operation: .refresh, pathActivationID: fixtureID(101)) }
    }
    for mutation in ["duplicate", "decodedDuplicate", "unknown", "missing", "base64", "invalidUTF8", "oversize"] {
        check("envelope \(mutation) refuses") {
            let f = try ProofFixture(); var body = f.body
            let raw = String(decoding: body, as: UTF8.self)
            switch mutation {
            case "duplicate": body = Data(raw.replacingOccurrences(of: "{\"action\":", with: "{\"action\":\"\",\"action\":").utf8)
            case "decodedDuplicate": body = Data(raw.replacingOccurrences(of: "{\"action\":", with: "{\"act\\u0069on\":\"\",\"action\":").utf8)
            case "unknown": body = Data((String(raw.dropLast()) + ",\"accountID\":\"\(otherAccount)\"}").utf8)
            case "missing": body = bodyBytes(action: f.action)
            case "base64": body = Data(raw.replacingOccurrences(of: f.action.base64EncodedString(), with: f.action.base64EncodedString() + "=").utf8)
            case "invalidUTF8": body[0] = 0xff
            default: body = Data(repeating: 0x20, count: 16_385)
            }
            try refuses(.invalidRequest) { _ = try DeviceRequest.parse(body, operation: .activate) }
        }
    }
}
