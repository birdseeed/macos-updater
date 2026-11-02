import Foundation
import CryptoKit
import PatchedActivation

// Exact public CI captures; the race record identifies only the last prepared request.
private struct BidirectionalCapture {
    let name: String
    let file: String
    let fileSHA256: String
    let messageSHA256: String
    let signatureSHA256: String
    let companion: String

    func load() throws -> FixedProofReplayInput {
        let bytes = try Data(contentsOf: URL(fileURLWithPath: "Fixtures/Activation/" + file))
        try expect(hex(digest(bytes)) == fileSHA256, "Public CI capture bytes changed")
        return try JSONDecoder().decode(FixedProofReplayInput.self, from: bytes)
    }
}
private let bidirectionalCaptures = [
    BidirectionalCapture(name: "race last-prepared only", file: "ci-37995438633-race-last-prepared.json",
        fileSHA256: "800ad492f0138053ab1db6aab3f0bf53d023f0787cfba5d0287a1e997704e935",
        messageSHA256: "0244dc520d1879dbe80321b26eeb8676bc09f286ac3f1b0bbe0be2ddcdd4f236",
        signatureSHA256: "a7113d946b4fa9ac9a04b200fa9ae415d47ce18a1cd06baa11bd8f04642bd2d1",
        companion: "M1hmQ/vPbPJmtEMvmOVSzQQ7rPPAO7PoMQO5c0HTN2882rpI/nJkrqhhPacKeb0IMklZ6aZsDoWRZ88NoOIu9A=="),
    BidirectionalCapture(name: "stale first-apply input", file: "ci-37995438633-stale-first-apply.json",
        fileSHA256: "a75d03f5dd93fc1eb32e1fb1ca2653fed6cc2ac3ffd5f4bf832e8e205bc25172",
        messageSHA256: "0d6f6a0340291df243ca74a8113e271e3fec77855499730d299fef5e637ace0c",
        signatureSHA256: "1bcc6120667e0b0c046c1a98e2fe9c0dc1cdf8ac82de2c950ee642f38e382184",
        companion: "La/J77DdoeHvnZeYSaOqdUN0/WtYe4e/dtDwzEbAJGPFCgE8TdTFSPEtWFMEvBIyyuvODytEMQBEFL6LxTbr+A==")
]
private func bidirectionalContext(_ input: FixedProofReplayInput) throws -> PossessionContext {
    guard let operation = DeviceOperation(rawValue: input.operation) else {
        throw CheckFailure(description: "Unknown captured operation")
    }
    return PossessionContext(accountID: String(decoding: input.accountID, as: UTF8.self),
        activationID: input.activationID.map { String(decoding: $0, as: UTF8.self) },
        operation: operation, publicKey: input.publicKey, nonce: input.nonce, expiresAt: input.expiresAt)
}

@MainActor func registerBidirectionalProofChecks() {
    for capture in bidirectionalCaptures {
        check("bidirectional \(capture.name) exact public message and body binding") {
            let input = try capture.load(); let context = try bidirectionalContext(input)
            try expect(input.operation == 2 && input.activationID == nil && input.now == 1_000 && input.expiresAt == 1_300,
                       "Captured replacement/time context changed")
            try expect(hex(digest(input.publicKey)) == "7710e28392251c0b70f8299fd465e9c200db6e7c415d18bae009e1ac75b17dc9",
                       "Captured public key changed")
            try expect(hex(digest(input.referenceMessage)) == capture.messageSHA256
                       && hex(digest(input.signature)) == capture.signatureSHA256, "Public proof golden changed")
            try expect(referenceMessage(input.action, context) == input.referenceMessage,
                       "Independent reference message differs from captured bytes")
            try expect(try PossessionProof.message(actionBytes: input.action, context: context) == input.referenceMessage,
                       "Production message differs from independent capture")
            let parsed = try DeviceRequest.parse(input.body, operation: context.operation)
            try expect(parsed.action.bytes == input.action && parsed.action.publicKey == input.publicKey
                       && parsed.proof?.signature == input.signature && parsed.proof?.nonce == input.nonce,
                       "Captured body does not bind the exact action/key/signature/nonce")
        }
        check("bidirectional \(capture.name) literal companion is exactly n-S") {
            let input = try capture.load(); let companion = Data(base64Encoded: capture.companion)!
            try expect(input.signature.count == 64 && companion.count == 64
                       && input.signature.prefix(32) == companion.prefix(32) && input.signature != companion,
                       "Companion shape/R changed")
            // Independent addition validates the Node/OpenSSL-verified literal companion.
            // It checks only representation arithmetic, never cryptographic acceptance.
            let first = Array(input.signature.suffix(32)), second = Array(companion.suffix(32))
            var sum = [UInt8](repeating: 0, count: 32); var carry = 0
            for index in stride(from: 31, through: 0, by: -1) {
                let total = Int(first[index]) + Int(second[index]) + carry
                sum[index] = UInt8(total & 255); carry = total >> 8
            }
            try expect(carry == 0 && Data(sum) == unhex("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551"),
                       "Literal companion is not the true scalar complement")
        }
        for useCompanion in [false, true] {
            let variant = useCompanion ? "companion" : "original"
            func signature(_ input: FixedProofReplayInput) -> Data {
                useCompanion ? Data(base64Encoded: capture.companion)! : input.signature
            }
            check("bidirectional \(capture.name) \(variant) production verifies without mutation") {
                let input = try capture.load(); let before = input
                let raw = signature(input); let rawBefore = raw; let context = try bidirectionalContext(input)
                try P256SignatureVerification.verify(rawSignature: raw, message: input.referenceMessage,
                    publicKey: P256.Signing.PublicKey(x963Representation: input.publicKey))
                try PossessionProof.verify(actionBytes: input.action, signature: raw, context: context, now: input.now)
                try expect(input == before && raw == rawBefore && context == bidirectionalContext(input),
                           "Verification changed caller input bytes/context")
                try expect(try capture.load() == before, "Verification changed the public fixture")
            }
            check("bidirectional \(capture.name) \(variant) tampered R and S refuse") {
                let input = try capture.load(); let context = try bidirectionalContext(input)
                for index in [0, 32] {
                    var raw = signature(input); raw[index] ^= 1
                    try refuses(.proofRefused) {
                        try PossessionProof.verify(actionBytes: input.action, signature: raw, context: context, now: input.now)
                    }
                }
            }
            check("bidirectional \(capture.name) \(variant) changed message and wrong valid key refuse") {
                let input = try capture.load(); let raw = signature(input)
                let key = try P256.Signing.PublicKey(x963Representation: input.publicKey)
                var message = input.referenceMessage; message[0] ^= 1
                try refuses(.proofRefused) {
                    try P256SignatureVerification.verify(rawSignature: raw, message: message, publicKey: key)
                }
                let wrongKey = try fixtureKey(8).publicKey
                try expect(wrongKey.x963Representation != input.publicKey, "Wrong-key negative lost its precondition")
                try refuses(.proofRefused) {
                    try P256SignatureVerification.verify(rawSignature: raw, message: input.referenceMessage, publicKey: wrongKey)
                }
            }
            check("bidirectional \(capture.name) \(variant) changed valid action and nonce refuse") {
                let input = try capture.load(); let raw = signature(input); let context = try bidirectionalContext(input)
                let text = String(decoding: input.action, as: UTF8.self)
                let action = Data(text.replacingOccurrences(of: "Fixture Mac", with: "Changed Mac").utf8)
                try expect(action != input.action, "Changed-action negative lost its precondition")
                // A well-formed action must reach signature verification, rather than fail parsing.
                _ = try PossessionProof.message(actionBytes: action, context: context)
                try refuses(.proofRefused) {
                    try PossessionProof.verify(actionBytes: action, signature: raw, context: context, now: input.now)
                }
                var changed = context; changed.nonce[0] ^= 1
                try refuses(.proofRefused) {
                    try PossessionProof.verify(actionBytes: input.action, signature: raw, context: changed, now: input.now)
                }
            }
            check("bidirectional \(capture.name) \(variant) exact expiry and excessive time refuse") {
                let input = try capture.load(); let raw = signature(input); let context = try bidirectionalContext(input)
                for now in [input.expiresAt, UInt64.max] {
                    try refuses(.proofRefused) {
                        try PossessionProof.verify(actionBytes: input.action, signature: raw, context: context, now: now)
                    }
                }
            }
        }
    }
}
