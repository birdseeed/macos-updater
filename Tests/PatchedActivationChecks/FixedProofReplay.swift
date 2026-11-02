import Foundation
import CryptoKit
import Security
@_spi(Testing) import PatchedActivation

// Check-target only: exact public proof replay, never a ledger or installation authority.
struct FixedProofReplayInput: Codable, Equatable {
    var body: Data
    var action: Data
    var publicKey: Data
    var signature: Data
    var referenceMessage: Data
    var accountID: Data
    var activationID: Data?
    var operation: UInt8
    var nonce: Data
    var expiresAt: UInt64
    var now: UInt64
}
enum FixedProofReplayAvailability: String, Codable { case complete, unavailable, notImplemented }
enum FixedProofReplayStatus: String, Codable { case accepted, refused, error, unavailable }
enum FixedProofReplayError: String, Error, Codable {
    case notImplemented, inputBound, inputShape, invalidSignatureLength, outputBound
    case invalidRequest, proofRefused, cryptoKitError, securityError
}
struct FixedProofReplayStage: Codable, Equatable {
    let status: FixedProofReplayStatus
    let errorType: FixedProofReplayError?
}
struct FixedProofReplayReport: Codable {
    var schema = 1
    var scope = "fixed-public-proof-replay"
    var availability: FixedProofReplayAvailability = .notImplemented
    var reason: FixedProofReplayError? = .notImplemented
    var os = ""
    var architecture = ""
    var input: FixedProofReplayInput?
    var canonicalDER: Data?
    var cryptoKitDER: Data?
    var stages: [String: FixedProofReplayStage] = [:]
}
enum FixedProofReplay {
    static let maximumOutputBytes = 65_536
    private static let stageNames = [
        "bodyParse", "bodyActionMatches", "bodyPublicKeyMatches", "bodySignatureMatches", "bodyNonceMatches",
        "referenceMessageMatches", "productionMessageMatches", "cryptoKitKeyConstruction",
        "cryptoKitSignatureConstruction", "cryptoKitRawRoundTrip", "canonicalDERConstruction",
        "cryptoKitDERMatchesCanonical", "cryptoKitDERRoundTrip", "cryptoKitMessageVerification",
        "cryptoKitDigestVerification", "securityKeyConstruction", "securityMessageAlgorithm",
        "securityDigestAlgorithm", "securityMessageVerification", "securityDigestVerification", "productionProof"
    ]
    private static func bounded(_ input: FixedProofReplayInput) -> Bool {
        input.body.count <= 16_384 && input.action.count <= 1_024 && input.publicKey.count <= 1_024
            && input.signature.count <= 8_192 && input.referenceMessage.count <= 1_024
            && input.nonce.count <= 1_024 && input.accountID.count <= 1_024
            && (input.activationID?.count ?? 0) <= 1_024
    }
    private static func identifier(_ bytes: Data) -> Bool {
        bytes.count == 32 && bytes.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func inspect(_ input: FixedProofReplayInput) -> FixedProofReplayReport {
        var report = FixedProofReplayReport()
        report.os = ProcessInfo.processInfo.operatingSystemVersionString
        #if arch(arm64)
        report.architecture = "arm64"
        #elseif arch(x86_64)
        report.architecture = "x86_64"
        #else
        report.architecture = "other"
        #endif
        guard bounded(input) else {
            report.availability = .unavailable; report.reason = .inputBound; return report
        }
        // The independent reference producer requires safe hexadecimal identifiers.
        guard identifier(input.accountID), input.activationID.map(identifier) ?? true,
              let operation = DeviceOperation(rawValue: input.operation) else {
            report.availability = .unavailable; report.reason = .inputShape; return report
        }
        let context = PossessionContext(accountID: String(decoding: input.accountID, as: UTF8.self),
            activationID: input.activationID.map { String(decoding: $0, as: UTF8.self) },
            operation: operation, publicKey: input.publicKey, nonce: input.nonce, expiresAt: input.expiresAt)
        report.availability = .complete; report.reason = nil; report.input = input
        report.stages = Dictionary(uniqueKeysWithValues: stageNames.map {
            ($0, FixedProofReplayStage(status: .unavailable, errorType: nil))
        })
        func result(_ name: String, _ accepted: Bool) {
            report.stages[name] = FixedProofReplayStage(status: accepted ? .accepted : .refused, errorType: nil)
        }
        func failure(_ name: String, _ kind: FixedProofReplayError) {
            report.stages[name] = FixedProofReplayStage(status: .error, errorType: kind)
        }
        do {
            let parsed = try DeviceRequest.parse(input.body, operation: operation, pathActivationID: context.activationID)
            result("bodyParse", true)
            result("bodyActionMatches", parsed.action.bytes == input.action)
            result("bodyPublicKeyMatches", parsed.action.publicKey == input.publicKey)
            result("bodySignatureMatches", parsed.proof?.signature == input.signature)
            result("bodyNonceMatches", parsed.proof?.nonce == input.nonce)
        } catch { failure("bodyParse", .invalidRequest) }
        result("referenceMessageMatches", referenceMessage(input.action, context) == input.referenceMessage)
        do {
            result("productionMessageMatches", try PossessionProof.message(actionBytes: input.action, context: context)
                   == input.referenceMessage)
        } catch { failure("productionMessageMatches", .proofRefused) }

        var cryptoKey: P256.Signing.PublicKey?
        var cryptoSignature: P256.Signing.ECDSASignature?
        do {
            cryptoKey = try P256.Signing.PublicKey(x963Representation: input.publicKey)
            result("cryptoKitKeyConstruction", true)
        } catch { failure("cryptoKitKeyConstruction", .cryptoKitError) }
        do {
            cryptoSignature = try P256.Signing.ECDSASignature(rawRepresentation: input.signature)
            result("cryptoKitSignatureConstruction", true)
        } catch { failure("cryptoKitSignatureConstruction", .cryptoKitError) }
        do {
            report.canonicalDER = try canonicalDER(rawSignature: input.signature)
            result("canonicalDERConstruction", true)
        } catch { failure("canonicalDERConstruction", .invalidSignatureLength) }
        if let signature = cryptoSignature {
            result("cryptoKitRawRoundTrip", signature.rawRepresentation == input.signature)
            report.cryptoKitDER = signature.derRepresentation
            if let independentDER = report.canonicalDER {
                result("cryptoKitDERMatchesCanonical", signature.derRepresentation == independentDER)
            }
            do {
                let roundTrip = try P256.Signing.ECDSASignature(derRepresentation: signature.derRepresentation)
                result("cryptoKitDERRoundTrip", roundTrip.rawRepresentation == input.signature)
            } catch { failure("cryptoKitDERRoundTrip", .cryptoKitError) }
        }
        let messageDigest = SHA256.hash(data: input.referenceMessage)
        if let key = cryptoKey, let signature = cryptoSignature {
            result("cryptoKitMessageVerification", key.isValidSignature(signature, for: input.referenceMessage))
            result("cryptoKitDigestVerification", key.isValidSignature(signature, for: messageDigest))
        }

        // Import the captured public X9.63 bytes only; no Keychain or key generation.
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
                                          kSecAttrKeyClass: kSecAttrKeyClassPublic, kSecAttrKeySizeInBits: 256]
        if let key = SecKeyCreateWithData(input.publicKey as CFData, attributes as CFDictionary, nil) {
            result("securityKeyConstruction", true)
            let messageAlgorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256
            let digestAlgorithm = SecKeyAlgorithm.ecdsaSignatureDigestX962SHA256
            let supportsMessage = SecKeyIsAlgorithmSupported(key, .verify, messageAlgorithm)
            let supportsDigest = SecKeyIsAlgorithmSupported(key, .verify, digestAlgorithm)
            result("securityMessageAlgorithm", supportsMessage)
            result("securityDigestAlgorithm", supportsDigest)
            // Feed independently encoded DER, never CryptoKit's conversion, to Security.
            if let der = report.canonicalDER {
                if supportsMessage {
                    result("securityMessageVerification", SecKeyVerifySignature(key, messageAlgorithm,
                        input.referenceMessage as CFData, der as CFData, nil))
                }
                if supportsDigest {
                    result("securityDigestVerification", SecKeyVerifySignature(key, digestAlgorithm,
                        Data(messageDigest) as CFData, der as CFData, nil))
                }
            }
        } else { failure("securityKeyConstruction", .securityError) }
        do {
            try PossessionProof.verify(actionBytes: input.action, signature: input.signature, context: context, now: input.now)
            result("productionProof", true)
        } catch { result("productionProof", false) }
        return report
    }
    static func canonicalDER(rawSignature: Data) throws -> Data {
        guard rawSignature.count == 64 else { throw FixedProofReplayError.invalidSignatureLength }
        // Fixed unsigned R/S become minimal positive DER INTEGERs; never alter their numeric values.
        func integer(_ bytes: Data.SubSequence) -> Data {
            var value = Array(bytes)
            while value.count > 1 && value.first == 0 { value.removeFirst() }
            if value[0] & 0x80 != 0 { value.insert(0, at: 0) }
            return Data([0x02, UInt8(value.count)] + value)
        }
        let values = integer(rawSignature.prefix(32)) + integer(rawSignature.suffix(32))
        return Data([0x30, UInt8(values.count)]) + values
    }
    static func render(_ report: FixedProofReplayReport) throws -> String {
        // Preflight caller-constructed reports before JSONEncoder allocates base64 or output buffers.
        func short(_ value: String, _ limit: Int) -> Bool { value.utf8.prefix(limit + 1).count <= limit }
        guard short(report.scope, 64), short(report.os, 256), short(report.architecture, 16),
              report.stages.count <= stageNames.count,
              report.stages.keys.allSatisfy({ short($0, 64) }),
              (report.canonicalDER?.count ?? 0) <= 72, (report.cryptoKitDER?.count ?? 0) <= 72,
              report.input.map(bounded) ?? true else { throw FixedProofReplayError.outputBound }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(report)
        guard bytes.count <= maximumOutputBytes else { throw FixedProofReplayError.outputBound }
        return String(decoding: bytes, as: UTF8.self)
    }
}
