import Foundation
import CryptoKit

public enum ActivationError: Error, Equatable {
    case unavailable, invalidRequest, proofRefused, invalidSession, requestConflict
    case reauthRequired, stale, assertionStale, auditFailed, keyUnavailable
}

public enum ActivationIdentity {
    static let maximumExactInteger: UInt64 = 9_007_199_254_740_991

    public static func identifierBytes(_ value: String) throws -> Data {
        let bytes = Array(value.utf8)
        guard bytes.count == 32, bytes.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw ActivationError.invalidRequest
        }
        func nibble(_ byte: UInt8) -> UInt8 { byte <= 57 ? byte - 48 : byte - 87 }
        return Data(stride(from: 0, to: 32, by: 2).map { nibble(bytes[$0]) << 4 | nibble(bytes[$0 + 1]) })
    }

    public static func publicKeyDigest(_ bytes: Data) throws -> Data {
        guard bytes.count == 65, bytes.first == 4,
              (try? P256.Signing.PublicKey(x963Representation: bytes)) != nil else {
            throw ActivationError.invalidRequest
        }
        return Data(SHA256.hash(data: bytes))
    }

    public static func displayName(_ value: String) throws -> String {
        // Reject raw controls before trimming: trimming must never conceal a forbidden newline.
        for scalar in value.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator: throw ActivationError.invalidRequest
            default: break
            }
            let code = scalar.value
            guard !(0x202A...0x202E).contains(code), !(0x2066...0x2069).contains(code),
                  ![0x061C, 0x200E, 0x200F].contains(code) else { throw ActivationError.invalidRequest }
        }
        let normalised = value.trimmingCharacters(in: .whitespaces).precomposedStringWithCanonicalMapping
        guard (1...64).contains(normalised.unicodeScalars.count), normalised.utf8.count <= 256 else {
            throw ActivationError.invalidRequest
        }
        return normalised
    }
}

public enum KeyAssurance: String, Equatable, Sendable {
    case secureStorageFallback, hardwarePreferred, fixtureAttested
}
