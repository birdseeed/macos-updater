import Foundation

/// Deliberately independent of Core. No Foundation JSON coercion or duplicate-key loss.
/// Schema 1 needs objects, printable ASCII strings and exact unsigned integers only.
enum LicenceJSONValue {
    case object([String: LicenceJSONValue]), string(String), integer(Int64)
}
enum LicenceStrictJSON {
    static func object(_ data: Data, maximumBytes: Int, refusal: LicenceRefusal) throws -> [String: LicenceJSONValue] {
        guard !data.isEmpty, data.count <= maximumBytes,
              String(data: data, encoding: .utf8) != nil, !data.contains(0),
              !data.starts(with: [0xef, 0xbb, 0xbf]) else { throw refusal }
        var parser = Parser(bytes: Array(data), refusal: refusal)
        let object = try parser.object(depth: 1)
        parser.whitespace()
        guard parser.offset == parser.bytes.count else { throw refusal }
        return object
    }

    private struct Parser {
        let bytes: [UInt8]
        let refusal: LicenceRefusal
        var offset = 0
        var current: UInt8? { offset < bytes.count ? bytes[offset] : nil }
        mutating func whitespace() {
            while let byte = current, [9, 10, 13, 32].contains(byte) { offset += 1 }
        }
        mutating func consume(_ byte: UInt8) throws {
            guard current == byte else { throw refusal }
            offset += 1
        }
        mutating func object(depth: Int) throws -> [String: LicenceJSONValue] {
            guard depth <= 4 else { throw refusal }
            whitespace(); try consume(123); whitespace()
            var result: [String: LicenceJSONValue] = [:]
            if current == 125 { offset += 1; return result }
            while true {
                let key = try string()
                guard result[key] == nil else { throw refusal }
                whitespace(); try consume(58); whitespace()
                let value: LicenceJSONValue
                guard let token = current else { throw refusal }
                switch token {
                case 123: value = .object(try object(depth: depth + 1))
                case 34: value = .string(try string())
                case 48...57: value = .integer(try integer())
                default: throw refusal
                }
                result[key] = value
                whitespace()
                if current == 125 { offset += 1; return result }
                try consume(44); whitespace()
            }
        }
        mutating func string() throws -> String {
            try consume(34)
            var decoded: [UInt8] = []
            while let byte = current {
                offset += 1
                if byte == 34 { return String(decoding: decoded, as: UTF8.self) }
                var value = byte
                if byte == 92 {
                    guard let escape = current else { throw refusal }
                    offset += 1
                    switch escape {
                    case 34, 47, 92: value = escape
                    case 117:
                        var scalar: UInt16 = 0
                        for _ in 0..<4 {
                            guard let hex = current else { throw refusal }
                            let digit: UInt16
                            switch hex {
                            case 48...57: digit = UInt16(hex - 48)
                            case 65...70: digit = UInt16(hex - 55)
                            case 97...102: digit = UInt16(hex - 87)
                            default: throw refusal
                            }
                            scalar = scalar * 16 + digit; offset += 1
                        }
                        guard scalar >= 32, scalar <= 126 else { throw refusal }
                        value = UInt8(scalar)
                    default: throw refusal
                    }
                }
                guard value >= 32, value <= 126 else { throw refusal }
                decoded.append(value)
            }
            throw refusal
        }
        mutating func integer() throws -> Int64 {
            guard let first = current, first >= 48, first <= 57 else { throw refusal }
            if first == 48 {
                offset += 1
                if let next = current, next >= 48, next <= 57 { throw refusal }
                return 0
            }
            var result: Int64 = 0
            while let byte = current, byte >= 48, byte <= 57 {
                let digit = Int64(byte - 48)
                guard result <= (LicencePolicy.maximumExactSecond - digit) / 10 else { throw refusal }
                result = result * 10 + digit; offset += 1
            }
            return result
        }
    }
}

extension Dictionary where Key == String, Value == LicenceJSONValue {
    func exactFields(_ fields: Set<String>) throws {
        guard Set(keys) == fields else { throw LicenceRefusal.malformedPayload }
    }
    func text(_ key: String, maximum: Int = 256) throws -> String {
        guard case .string(let value) = self[key], !value.isEmpty, value.utf8.count <= maximum else {
            throw LicenceRefusal.malformedPayload
        }
        return value
    }
    func number(_ key: String) throws -> Int64 {
        guard case .integer(let value) = self[key] else { throw LicenceRefusal.malformedPayload }
        return value
    }
    func evidence(_ key: String, fields: Set<String>) throws -> [String: LicenceJSONValue] {
        guard case .object(let object) = self[key] else { throw LicenceRefusal.malformedPayload }
        try object.exactFields(fields)
        return object
    }
}
