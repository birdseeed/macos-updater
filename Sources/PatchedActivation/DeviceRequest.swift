import Foundation
import CryptoKit

public enum DeviceOperation: UInt8, CaseIterable, Sendable {
    case activate = 1, replace = 2, refresh = 3, rebind = 4, recoveryPossession = 5
    case deactivate = 6, rename = 7
}

public struct DeviceAction: Equatable, Sendable {
    public let bytes: Data
    public let digest: Data
    public let requestID: String
    public let publicKey: Data?
    public let displayName: String?
    public let activationID: String?
    public let releaseActivationID: String?
    public let expectedRevision: UInt64?
    public let caseID: String?
    public let caseDigest: String?
}

public struct DeviceProofEnvelope: Equatable, Sendable {
    public let challengeID: String
    public let nonce: Data
    public let signature: Data
    public let attestation: Data?
    public let attestKeyID: Data?
    public let assertion: Data?
}

public struct DeviceRequest: Equatable, Sendable {
    public let operation: DeviceOperation
    public let action: DeviceAction
    public let proof: DeviceProofEnvelope?

    public static func parse(_ body: Data, operation: DeviceOperation,
                             pathActivationID: String? = nil) throws -> Self {
        let large = [.activate, .replace, .rebind].contains(operation)
        var parser = try ActivationJSON(body, maximum: large ? 16_384 : 4_096, whitespace: true)
        let root = try parser.root()
        let bound = operation.rawValue <= 5
        try root.fields(bound ? ["action", "proof"] : ["action"])
        let actionBytes = try decode64(root.string("action"), minimum: 1, maximum: 1_024)
        let action = try parseAction(actionBytes, operation: operation, pathActivationID: pathActivationID)
        var proof: DeviceProofEnvelope?
        if bound {
            let object = try root.object("proof")
            let names = Set(object.map(\.0))
            let base: Set<String> = ["challengeID", "nonce", "signature"]
            let attestation = names.contains("attestation")
            let assertion = names.contains("assertion")
            guard !(attestation && assertion) else { throw ActivationError.invalidRequest }
            let optional: Set<String> = attestation ? ["attestation", "attestKeyID"] : assertion ? ["assertion"] : []
            guard names == base.union(optional), !attestation || large,
                  !assertion || operation == .refresh else { throw ActivationError.invalidRequest }
            let id = try object.string("challengeID")
            _ = try ActivationIdentity.identifierBytes(id)
            proof = DeviceProofEnvelope(challengeID: id,
                nonce: try decode64(object.string("nonce"), minimum: 32, maximum: 32),
                signature: try decode64(object.string("signature"), minimum: 64, maximum: 64),
                attestation: attestation ? try decode64(object.string("attestation"), minimum: 1, maximum: 8_192) : nil,
                attestKeyID: attestation ? try decode64(object.string("attestKeyID"), minimum: 1, maximum: 64) : nil,
                assertion: assertion ? try decode64(object.string("assertion"), minimum: 1, maximum: 1_024) : nil)
        }
        return Self(operation: operation, action: action, proof: proof)
    }

    static func parseAction(_ bytes: Data, operation: DeviceOperation, pathActivationID: String?) throws -> DeviceAction {
        var parser = try ActivationJSON(bytes, maximum: 1_024, whitespace: false)
        let fields = try parser.root()
        let expected: [String]
        switch operation {
        case .activate: expected = ["requestID", "devicePublicKey", "displayName"]
        case .replace: expected = ["requestID", "devicePublicKey", "displayName", "releaseActivationID", "expectedRevision"]
        case .refresh: expected = ["requestID", "activationID"]
        case .rebind, .deactivate: expected = ["requestID", "activationID", "expectedRevision"]
        case .rename: expected = ["requestID", "activationID", "expectedRevision", "displayName"]
        case .recoveryPossession: expected = ["requestID", "activationID", "caseID", "caseDigest"]
        }
        guard fields.map(\.0) == expected else { throw ActivationError.invalidRequest }
        let requestID = try fields.string("requestID")
        _ = try ActivationIdentity.identifierBytes(requestID)
        func identifier(_ name: String) throws -> String? {
            guard expected.contains(name) else { return nil }
            let id = try fields.string(name); _ = try ActivationIdentity.identifierBytes(id)
            return id
        }
        let activationID = try identifier("activationID")
        guard activationID == pathActivationID else { throw ActivationError.invalidRequest }
        let releaseID = try identifier("releaseActivationID")
        let key = expected.contains("devicePublicKey") ? try decode64(fields.string("devicePublicKey"), minimum: 65, maximum: 65) : nil
        if let key { _ = try ActivationIdentity.publicKeyDigest(key) }
        let name = expected.contains("displayName") ? try ActivationIdentity.displayName(fields.string("displayName")) : nil
        let revision = expected.contains("expectedRevision") ? try fields.integer("expectedRevision") : nil
        let caseID = try identifier("caseID")
        let caseDigest = expected.contains("caseDigest") ? try fields.string("caseDigest") : nil
        if let caseDigest {
            guard caseDigest.utf8.count == 64,
                  caseDigest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw ActivationError.invalidRequest
            }
        }
        return DeviceAction(bytes: bytes, digest: Data(SHA256.hash(data: bytes)), requestID: requestID,
            publicKey: key, displayName: name, activationID: activationID, releaseActivationID: releaseID,
            expectedRevision: revision, caseID: caseID, caseDigest: caseDigest)
    }

    private static func decode64(_ text: String, minimum: Int, maximum: Int) throws -> Data {
        guard text.utf8.count <= ((maximum + 2) / 3) * 4,
              let value = Data(base64Encoded: text), (minimum...maximum).contains(value.count),
              value.base64EncodedString() == text else { throw ActivationError.invalidRequest }
        return value
    }
}

// Bounded JSON scanner preserves decoded-key uniqueness and original action bytes.
// Foundation object decoding would silently discard duplicate keys.
private indirect enum ActivationJSONValue {
    case string(String), integer(UInt64), object([(String, ActivationJSONValue)])
}
private extension Array where Element == (String, ActivationJSONValue) {
    func fields(_ expected: Set<String>) throws {
        guard Set(map(\.0)) == expected else { throw ActivationError.invalidRequest }
    }
    func string(_ name: String) throws -> String {
        guard let field = first(where: { $0.0 == name }), case .string(let value) = field.1 else { throw ActivationError.invalidRequest }
        return value
    }
    func integer(_ name: String) throws -> UInt64 {
        guard let field = first(where: { $0.0 == name }), case .integer(let value) = field.1 else { throw ActivationError.invalidRequest }
        return value
    }
    func object(_ name: String) throws -> Self {
        guard let field = first(where: { $0.0 == name }), case .object(let value) = field.1 else { throw ActivationError.invalidRequest }
        return value
    }
}
private struct ActivationJSON {
    let bytes: [UInt8]
    let whitespace: Bool
    var index = 0
    init(_ data: Data, maximum: Int, whitespace: Bool) throws {
        guard !data.isEmpty, data.count <= maximum, String(data: data, encoding: .utf8) != nil,
              !data.contains(0), !data.starts(with: [0xef, 0xbb, 0xbf]) else { throw ActivationError.invalidRequest }
        bytes = Array(data); self.whitespace = whitespace
    }
    mutating func skip() {
        if whitespace { while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
    }
    mutating func take(_ byte: UInt8) throws {
        skip(); guard index < bytes.count, bytes[index] == byte else { throw ActivationError.invalidRequest }; index += 1
    }
    mutating func root() throws -> [(String, ActivationJSONValue)] {
        let result = try object(depth: 1); skip()
        guard index == bytes.count else { throw ActivationError.invalidRequest }
        return result
    }
    mutating func object(depth: Int) throws -> [(String, ActivationJSONValue)] {
        guard depth <= 2 else { throw ActivationError.invalidRequest }
        try take(123); skip()
        var fields: [(String, ActivationJSONValue)] = []; var names = Set<String>()
        if index < bytes.count && bytes[index] == 125 { index += 1; return fields }
        while true {
            let name = try string()
            guard names.insert(name).inserted else { throw ActivationError.invalidRequest }
            try take(58); skip()
            guard index < bytes.count else { throw ActivationError.invalidRequest }
            let value: ActivationJSONValue
            if bytes[index] == 34 { value = .string(try string()) }
            else if bytes[index] == 123 { value = .object(try object(depth: depth + 1)) }
            else { value = .integer(try integer()) }
            fields.append((name, value)); skip()
            guard index < bytes.count else { throw ActivationError.invalidRequest }
            if bytes[index] == 125 { index += 1; return fields }
            try take(44)
        }
    }
    mutating func integer() throws -> UInt64 {
        let start = index
        while index < bytes.count && (48...57).contains(bytes[index]) { index += 1 }
        guard index > start, index - start == 1 || bytes[start] != 48,
              let value = UInt64(String(decoding: bytes[start..<index], as: UTF8.self)),
              value <= ActivationIdentity.maximumExactInteger else { throw ActivationError.invalidRequest }
        return value
    }
    mutating func hex4() throws -> UInt32 {
        guard index + 4 <= bytes.count else { throw ActivationError.invalidRequest }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = bytes[index]; index += 1
            let digit: UInt8
            switch byte {
            case 48...57: digit = byte - 48
            case 65...70: digit = byte - 55
            case 97...102: digit = byte - 87
            default: throw ActivationError.invalidRequest
            }
            value = value * 16 + UInt32(digit)
        }
        return value
    }
    mutating func string() throws -> String {
        try take(34); var value = Data()
        while index < bytes.count {
            let byte = bytes[index]; index += 1
            if byte == 34 {
                guard let decoded = String(data: value, encoding: .utf8) else { throw ActivationError.invalidRequest }
                return decoded
            }
            guard byte >= 32 else { throw ActivationError.invalidRequest }
            if byte != 92 { value.append(byte); continue }
            guard index < bytes.count else { throw ActivationError.invalidRequest }
            let escape = bytes[index]; index += 1
            switch escape {
            case 34, 47, 92: value.append(escape)
            case 98: value.append(8)
            case 102: value.append(12)
            case 110: value.append(10)
            case 114: value.append(13)
            case 116: value.append(9)
            case 117:
                var scalar = try hex4()
                if (0xD800...0xDBFF).contains(scalar) {
                    guard index + 2 <= bytes.count, bytes[index] == 92, bytes[index + 1] == 117 else { throw ActivationError.invalidRequest }
                    index += 2; let low = try hex4()
                    guard (0xDC00...0xDFFF).contains(low) else { throw ActivationError.invalidRequest }
                    scalar = 0x10000 + (scalar - 0xD800) * 0x400 + low - 0xDC00
                }
                guard let unicode = UnicodeScalar(scalar) else { throw ActivationError.invalidRequest }
                value.append(contentsOf: String(unicode).utf8)
            default: throw ActivationError.invalidRequest
            }
        }
        throw ActivationError.invalidRequest
    }
}
