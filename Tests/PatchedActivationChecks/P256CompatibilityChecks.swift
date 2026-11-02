import Foundation
import CryptoKit
import PatchedActivation

// Package access tests the pure scalar boundary without exporting an SPI or verifier override.
private let compatibilityOrder = unhex("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551")
private let compatibilityCompanion = Data(base64Encoded:
    "A+s7gmPf/lMkzw6G4QrHvkYYWdRL1FfBj0jY8BYMi3GOfZMdSBUpjPsHdRTuwIm1kiVY8NLw+wSglh+1HX8KAg==")!
private let rawCompatibilityStages = ["cryptoKitMessageVerification", "cryptoKitDigestVerification",
                                      "securityMessageVerification", "securityDigestVerification"]
private func compatibilityCapture() throws -> FixedProofReplayInput {
    let bytes = try Data(contentsOf: URL(fileURLWithPath: "Fixtures/Activation/ci-refused-20261009.json"))
    return try JSONDecoder().decode(FixedProofReplayInput.self, from: bytes)
}
private func compatibilityContext(_ input: FixedProofReplayInput) -> PossessionContext {
    PossessionContext(accountID: String(decoding: input.accountID, as: UTF8.self),
        activationID: input.activationID.map { String(decoding: $0, as: UTF8.self) },
        operation: DeviceOperation(rawValue: input.operation)!, publicKey: input.publicKey,
        nonce: input.nonce, expiresAt: input.expiresAt)
}
// Test-only independent complement producer uses 32-bit limbs. Literal arithmetic goldens
// below anchor it; it is never used to decide whether any signature is cryptographically valid.
private func referenceSCompanion(_ raw: Data) throws -> Data {
    try expect(raw.count == 64, "Reference companion requires raw64")
    let s = Array(raw.suffix(32)); let order = Array(compatibilityOrder)
    var result = [UInt8](repeating: 0, count: 32); var borrow: UInt64 = 0
    for offset in stride(from: 28, through: 0, by: -4) {
        let nLimb = order[offset..<offset + 4].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let sLimb = s[offset..<offset + 4].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let subtrahend = sLimb + borrow
        let difference = (UInt64(1) << 32) + nLimb - subtrahend
        borrow = nLimb < subtrahend ? 1 : 0
        for index in 0..<4 { result[offset + index] = UInt8(truncatingIfNeeded: difference >> (24 - 8 * index)) }
    }
    try expect(borrow == 0, "Reference scalar exceeds order")
    return Data(raw.prefix(32)) + Data(result)
}
private func requireCompatibilityRefusal(_ raw: Data, _ input: FixedProofReplayInput) throws {
    let key = try P256.Signing.PublicKey(x963Representation: input.publicKey)
    try refuses(.proofRefused) {
        try P256SignatureVerification.verify(rawSignature: raw, message: input.referenceMessage, publicKey: key)
    }
    try refuses(.proofRefused) {
        try PossessionProof.verify(actionBytes: input.action, signature: raw,
                                   context: compatibilityContext(input), now: input.now)
    }
}

@MainActor func registerP256CompatibilityChecks() {
    check("P256 compatibility original capture verifies without replacing wire bytes") {
        let input = try compatibilityCapture(); let before = input
        try PossessionProof.verify(actionBytes: input.action, signature: input.signature,
                                   context: compatibilityContext(input), now: input.now)
        try expect(input == before, "Verification changed original wire fields")
        let parsed = try DeviceRequest.parse(input.body, operation: .replace, pathActivationID: nil)
        try expect(parsed.proof?.signature == input.signature, "Original body signature changed")
    }
    check("P256 compatibility fixed companion verifies with every raw framework stage positive") {
        var input = try compatibilityCapture(); let originalBody = input.body
        input.signature = compatibilityCompanion
        let report = FixedProofReplay.inspect(input)
        try expect(report.availability == .complete && report.reason == nil && report.input == input,
                   "Companion replay not complete/exact")
        for name in rawCompatibilityStages {
            try expect(report.stages[name]?.status == .accepted && report.stages[name]?.errorType == nil,
                       "Companion raw framework stage failed: \(name)")
        }
        try expect(report.stages["bodySignatureMatches"]?.status == .refused && input.body == originalBody,
                   "Companion silently replaced original body")
        try expect(report.stages["productionProof"]?.status == .accepted, "Companion production proof refused")
    }
    check("P256 compatibility original and companion converge to exact high-S golden") {
        let input = try compatibilityCapture()
        try expect(try referenceSCompanion(input.signature) == compatibilityCompanion, "Reference complement golden differs")
        try expect(try referenceSCompanion(compatibilityCompanion) == input.signature, "Complement is not involutive")
        for raw in [input.signature, compatibilityCompanion] {
            try expect(try P256SignatureVerification.highSRepresentation(rawSignature: raw) == compatibilityCompanion,
                       "Captured pair did not converge to independently verified companion")
            try P256SignatureVerification.verify(rawSignature: raw, message: input.referenceMessage,
                publicKey: P256.Signing.PublicKey(x963Representation: input.publicKey))
        }
    }
    let goldens = [
        ("0000000000000000000000000000000000000000000000000000000000000001", "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632550"),
        ("0000000000000000000000000000000000000000000000000000000000000002", "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc63254f"),
        ("7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a8", "7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a9"),
        ("7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a9", "7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a9"),
        ("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632550", "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632550"),
        ("0000000000000000000000000000000100000000000000000000000000000000", "ffffffff00000000fffffffffffffffebce6faada7179e84f3b9cac2fc632551")
    ]
    for (index, golden) in goldens.enumerated() {
        check("P256 compatibility scalar complement literal golden \(index)") {
            // n-1 is a valid R boundary independently of whether this pair is a valid signature.
            let r = unhex("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632550")
            let raw = r + unhex(golden.0); let wanted = r + unhex(golden.1)
            let converted = try P256SignatureVerification.highSRepresentation(rawSignature: raw)
            try expect(converted == wanted && converted.prefix(32) == r, "Complement/unchanged R differs from literal")
            try expect(try P256SignatureVerification.highSRepresentation(rawSignature: converted) == wanted,
                       "High-S conversion not idempotent")
            let companion = try referenceSCompanion(raw)
            try expect(companion == wanted || raw == wanted, "Independent limb complement differs from golden")
        }
    }
    for keyNumber in [1, 2, 9, 17] {
        check("P256 compatibility real signed low/high pair key \(keyNumber)") {
            let fixture = try ProofFixture(key: keyNumber, request: 700 + keyNumber)
            let key = try fixtureKey(keyNumber).publicKey
            let message = referenceMessage(fixture.action, fixture.context)
            let companion = try referenceSCompanion(fixture.signature)
            try expect(companion != fixture.signature && companion.prefix(32) == fixture.signature.prefix(32),
                       "Generated pair does not contain different equivalent S scalars")
            let high = fixture.signature.suffix(32).lexicographicallyPrecedes(companion.suffix(32)) ? companion : fixture.signature
            // Raw framework acceptance can depend on the representation. Evaluate both exact
            // members independently, without using production conversion as the positive anchor.
            let originalAccepted = try key.isValidSignature(
                P256.Signing.ECDSASignature(rawRepresentation: fixture.signature), for: message)
            let companionAccepted = try key.isValidSignature(
                P256.Signing.ECDSASignature(rawRepresentation: companion), for: message)
            try expect(originalAccepted || companionAccepted, "Independent raw pair framework positive failed")
            for raw in [fixture.signature, companion] {
                try expect(try P256SignatureVerification.highSRepresentation(rawSignature: raw) == high,
                           "Generated pair did not converge")
                try P256SignatureVerification.verify(rawSignature: raw, message: message, publicKey: key)
                try PossessionProof.verify(actionBytes: fixture.action, signature: raw, context: fixture.context, now: 1_000)
            }
        }
    }
    let invalidScalars = [
        ("zero", Data(repeating: 0, count: 32)),
        ("order", compatibilityOrder),
        ("order plus one", unhex("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632552")),
        ("maximum unsigned", Data(repeating: 0xff, count: 32))
    ]
    for (name, scalar) in invalidScalars {
        for isR in [true, false] {
            check("P256 compatibility refuses \(isR ? "R" : "S") \(name)") {
                let input = try compatibilityCapture()
                let raw = isR ? scalar + Data(input.signature.suffix(32)) : Data(input.signature.prefix(32)) + scalar
                try refuses(.proofRefused) { _ = try P256SignatureVerification.highSRepresentation(rawSignature: raw) }
                try requireCompatibilityRefusal(raw, input)
            }
        }
    }
    for count in [0, 1, 31, 32, 63, 65, 70, 72, 128] {
        check("P256 compatibility refuses signature length \(count)") {
            let raw = Data(repeating: 1, count: count); let input = try compatibilityCapture()
            try refuses(.proofRefused) { _ = try P256SignatureVerification.highSRepresentation(rawSignature: raw) }
            try requireCompatibilityRefusal(raw, input)
        }
    }
    for isR in [true, false] {
        check("P256 compatibility in-range \(isR ? "R" : "S") n-1 cannot bypass actual verification") {
            let input = try compatibilityCapture()
            let edge = unhex("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632550")
            let raw = isR ? edge + Data(input.signature.suffix(32)) : Data(input.signature.prefix(32)) + edge
            _ = try P256SignatureVerification.highSRepresentation(rawSignature: raw)
            try requireCompatibilityRefusal(raw, input)
        }
    }
    for index in [0, 15, 31, 32, 47, 63] {
        check("P256 compatibility tampered signature byte \(index) refuses") {
            let input = try compatibilityCapture()
            for original in [input.signature, compatibilityCompanion] {
                var raw = original; raw[index] ^= 1
                try requireCompatibilityRefusal(raw, input)
            }
        }
    }
    check("P256 compatibility changed message refuses both representations") {
        let input = try compatibilityCapture(); var message = input.referenceMessage; message[0] ^= 1
        let key = try P256.Signing.PublicKey(x963Representation: input.publicKey)
        for raw in [input.signature, compatibilityCompanion] {
            try refuses(.proofRefused) { try P256SignatureVerification.verify(rawSignature: raw, message: message, publicKey: key) }
        }
    }
    check("P256 compatibility wrong valid public key refuses both representations") {
        let input = try compatibilityCapture(); let wrongKey = try fixtureKey(8).publicKey
        for raw in [input.signature, compatibilityCompanion] {
            try refuses(.proofRefused) {
                try P256SignatureVerification.verify(rawSignature: raw, message: input.referenceMessage, publicKey: wrongKey)
            }
        }
    }
    check("P256 compatibility changed trusted context refuses both representations") {
        let input = try compatibilityCapture(); var context = compatibilityContext(input); context.nonce[0] ^= 1
        for raw in [input.signature, compatibilityCompanion] {
            try refuses(.proofRefused) {
                try PossessionProof.verify(actionBytes: input.action, signature: raw, context: context, now: input.now)
            }
        }
    }
    check("P256 compatibility DER signature is not raw wire format") {
        let input = try compatibilityCapture()
        let der = try P256.Signing.ECDSASignature(rawRepresentation: input.signature).derRepresentation
        try refuses(.proofRefused) { _ = try P256SignatureVerification.highSRepresentation(rawSignature: der) }
        try requireCompatibilityRefusal(der, input)
    }
    check("P256 compatibility nonzero Data start index preserves raw scalar interpretation") {
        let input = try compatibilityCapture()
        let backing = Data([0xff]) + input.signature
        let sliced = backing.dropFirst()
        try expect(sliced.startIndex == 1, "Slice precondition lost")
        try expect(try P256SignatureVerification.highSRepresentation(rawSignature: sliced) == compatibilityCompanion,
                   "Data start index changed scalar conversion")
        try PossessionProof.verify(actionBytes: input.action, signature: sliced,
                                   context: compatibilityContext(input), now: input.now)
    }
}
