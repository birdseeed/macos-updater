import Foundation

// PAT-2583 strict reader for the operator's own state records. One bounded pass over UTF-8
// bytes that keeps numeric tokens exact and refuses a byte-order mark, a NUL, a duplicate
// key (compared after escapes are decoded), trailing bytes and deep nesting before any field
// is interpreted. No SDK decoder is involved.
//
// Origin: follows this repository's own Sources/PatchedCore/StrictJSON.swift, duplicated
// privately so that PatchedCore exposes nothing new.

indirect enum OperatorJSONValue {
    case object([String: OperatorJSONValue]), array([OperatorJSONValue]), string(String), number(String), boolean, null
    var object: [String: OperatorJSONValue]? { if case .object(let value) = self { value } else { nil } }
    var string: String? { if case .string(let value) = self { value } else { nil } }
    /// A plain unsigned integer token: no sign, fraction, exponent or leading zero. A quoted
    /// number, a boolean and a value above `UInt64.max` are all `nil`.
    var unsigned: UInt64? {
        guard case .number(let value) = self, !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
              value.utf8.count == 1 || value.utf8.first != 48 else { return nil }
        return UInt64(value)
    }
}

enum OperatorJSON {
    private struct Malformed: Error {}

    /// The single object `data` holds, or `nil` when it is not one bounded strict document.
    static func object(_ data: Data, maximum: Int, depth: Int = 4) -> [String: OperatorJSONValue]? {
        guard !data.isEmpty, data.count <= maximum, !data.starts(with: [0xef, 0xbb, 0xbf]),
              !data.contains(0), String(data: data, encoding: .utf8) != nil else { return nil }
        var scanner = Scanner(bytes: Array(data), maximumDepth: depth)
        guard let value = try? scanner.value(depth: 0) else { return nil }
        scanner.space()
        guard scanner.index == scanner.bytes.count else { return nil }
        return value.object
    }

    private struct Scanner {
        let bytes: [UInt8]
        let maximumDepth: Int
        var index = 0
        var current: UInt8? { index < bytes.count ? bytes[index] : nil }
        mutating func space() { while let byte = current, [9, 10, 13, 32].contains(byte) { index += 1 } }
        mutating func consume(_ byte: UInt8) throws {
            guard current == byte else { throw Malformed() }; index += 1
        }
        mutating func hex() throws -> UInt32 {
            var value: UInt32 = 0
            for _ in 0..<4 {
                guard let byte = current else { throw Malformed() }
                switch byte {
                case 48...57: value = value * 16 + UInt32(byte - 48)
                case 65...70: value = value * 16 + UInt32(byte - 55)
                case 97...102: value = value * 16 + UInt32(byte - 87)
                default: throw Malformed()
                }
                index += 1
            }
            return value
        }
        /// The decoded text of one string token, so that `"a"` and `"a"` are the same key.
        mutating func string() throws -> String {
            try consume(34)
            var scalars = String.UnicodeScalarView(), raw: [UInt8] = []
            func flush() throws {
                guard !raw.isEmpty else { return }
                guard let text = String(bytes: raw, encoding: .utf8) else { throw Malformed() }
                scalars.append(contentsOf: text.unicodeScalars); raw.removeAll()
            }
            while let byte = current {
                index += 1
                if byte == 34 { try flush(); return String(scalars) }
                guard byte >= 32 else { throw Malformed() }
                guard byte == 92 else { raw.append(byte); continue }
                try flush()
                guard let escape = current else { throw Malformed() }
                index += 1
                switch escape {
                case 34, 92, 47: scalars.append(Unicode.Scalar(escape))
                case 98: scalars.append("\u{08}")
                case 102: scalars.append("\u{0C}")
                case 110: scalars.append("\n")
                case 114: scalars.append("\r")
                case 116: scalars.append("\t")
                case 117:
                    var code = try hex()
                    if (0xD800...0xDBFF).contains(code) {
                        try consume(92); try consume(117)
                        let low = try hex()
                        guard (0xDC00...0xDFFF).contains(low) else { throw Malformed() }
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                    }
                    guard let scalar = Unicode.Scalar(code) else { throw Malformed() }
                    scalars.append(scalar)
                default: throw Malformed()
                }
            }
            throw Malformed()
        }
        mutating func digits() throws {
            let start = index
            while let byte = current, (48...57).contains(byte) { index += 1 }
            guard index > start else { throw Malformed() }
        }
        mutating func number() throws -> String {
            let start = index
            if current == 45 { index += 1 }
            if current == 48 { index += 1 } else { try digits() }
            if current == 46 { index += 1; try digits() }
            if current == 69 || current == 101 {
                index += 1
                if current == 43 || current == 45 { index += 1 }
                try digits()
            }
            return String(decoding: bytes[start..<index], as: UTF8.self)
        }
        mutating func value(depth: Int) throws -> OperatorJSONValue {
            guard depth < maximumDepth else { throw Malformed() }
            space()
            guard let byte = current else { throw Malformed() }
            switch byte {
            case 123:
                index += 1; space()
                var fields: [String: OperatorJSONValue] = [:]
                if current == 125 { index += 1; return .object(fields) }
                while true {
                    space(); let key = try string()
                    guard fields[key] == nil else { throw Malformed() }
                    space(); try consume(58); fields[key] = try value(depth: depth + 1); space()
                    if current == 125 { index += 1; return .object(fields) }
                    try consume(44)
                }
            case 91:
                index += 1; space()
                var entries: [OperatorJSONValue] = []
                if current == 93 { index += 1; return .array(entries) }
                while true {
                    entries.append(try value(depth: depth + 1)); space()
                    if current == 93 { index += 1; return .array(entries) }
                    try consume(44)
                }
            case 34: return .string(try string())
            case 45, 48...57: return .number(try number())
            case 116, 102, 110:
                let token = byte == 116 ? "true" : byte == 102 ? "false" : "null"
                for expected in token.utf8 { try consume(expected) }
                return byte == 110 ? .null : .boolean
            default: throw Malformed()
            }
        }
    }
}

/// The two durable records of an operator root, in the exact documented schema.
enum OperatorState {
    static let namespaceKind = "patched-operator-fixture-v1"
    static let zeroDigest = String(repeating: "0", count: 64)

    struct Checkpoint: Equatable, Sendable {
        let keyID: String
        let catalogueID: String
        let sequence: UInt64
        let payloadSHA256: String
    }

    static func validDigest(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func validIdentifier(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= 128 && text.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0)
        }
    }

    // Identifiers and digests are restricted to characters that need no JSON escape.
    static func namespaceBytes(keyID: String, catalogueID: String) -> Data {
        Data("{\"schemaVersion\":1,\"namespace\":\"\(namespaceKind)\",\"keyID\":\"\(keyID)\",\"catalogueID\":\"\(catalogueID)\"}".utf8)
    }
    static func checkpointBytes(_ checkpoint: Checkpoint) -> Data {
        Data(("{\"schemaVersion\":1,\"keyID\":\"\(checkpoint.keyID)\",\"catalogueID\":\"\(checkpoint.catalogueID)\"," +
              "\"sequence\":\(checkpoint.sequence),\"payloadSHA256\":\"\(checkpoint.payloadSHA256)\"}").utf8)
    }

    /// The key and catalogue identifiers a namespace record names. Anything else is `corruptState`.
    static func namespace(_ data: Data) throws -> (keyID: String, catalogueID: String) {
        guard let fields = OperatorJSON.object(data, maximum: OperatorLimits.maximumStateBytes),
              Set(fields.keys) == ["schemaVersion", "namespace", "keyID", "catalogueID"],
              fields["schemaVersion"]?.unsigned == 1, fields["namespace"]?.string == namespaceKind,
              let keyID = fields["keyID"]?.string, let catalogueID = fields["catalogueID"]?.string,
              validIdentifier(keyID), validIdentifier(catalogueID) else { throw OperatorFailure.corruptState }
        return (keyID, catalogueID)
    }
    /// The high-water mark a checkpoint records. Sequence 0 is the empty mark and the only one
    /// with the all-zero digest. Anything else is `corruptState`.
    static func checkpoint(_ data: Data) throws -> Checkpoint {
        guard let fields = OperatorJSON.object(data, maximum: OperatorLimits.maximumStateBytes),
              Set(fields.keys) == ["schemaVersion", "keyID", "catalogueID", "sequence", "payloadSHA256"],
              fields["schemaVersion"]?.unsigned == 1, let keyID = fields["keyID"]?.string,
              let catalogueID = fields["catalogueID"]?.string, validIdentifier(keyID), validIdentifier(catalogueID),
              let sequence = fields["sequence"]?.unsigned, let digest = fields["payloadSHA256"]?.string, validDigest(digest),
              (sequence == 0) == (digest == zeroDigest) else { throw OperatorFailure.corruptState }
        return Checkpoint(keyID: keyID, catalogueID: catalogueID, sequence: sequence, payloadSHA256: digest)
    }
}
