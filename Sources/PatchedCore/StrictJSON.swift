import Foundation

// A bounded single parser preserves numeric tokens and rejects duplicate decoded
// keys before any field is interpreted. Only JSON strings use the SDK decoder.
indirect enum JSONValue {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(String), boolean, null
    var object: [String: JSONValue]? { if case .object(let value) = self { value } else { nil } }
    var string: String? { if case .string(let value) = self { value } else { nil } }
    var unsigned: UInt64? {
        guard case .number(let value) = self, !value.isEmpty,
              value.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return UInt64(value)
    }
}

enum CoreJSON {
    static func object(_ data: Data, maximum: Int, failure: CoreFailure) throws -> [String: JSONValue] {
        guard !data.isEmpty, data.count <= maximum, !data.starts(with: [0xef, 0xbb, 0xbf]),
              !data.contains(0), String(data: data, encoding: .utf8) != nil else { throw failure }
        do {
            var scanner = Scanner(bytes: Array(data))
            let value = try scanner.value(depth: 0)
            scanner.space()
            guard scanner.index == scanner.bytes.count, let object = value.object else { throw failure }
            return object
        } catch { throw failure }
    }
    static func keys(_ object: [String: JSONValue], _ expected: Set<String>, failure: CoreFailure) throws {
        guard Set(object.keys) == expected else { throw failure }
    }
    private struct Scanner {
        let bytes: [UInt8]
        var index = 0
        var current: UInt8? { index < bytes.count ? bytes[index] : nil }
        mutating func space() { while let c = current, [9, 10, 13, 32].contains(c) { index += 1 } }
        mutating func consume(_ c: UInt8) throws {
            guard current == c else { throw CoreFailure.invalidPayload }; index += 1
        }
        mutating func string() throws -> String {
            let start = index
            try consume(34)
            while let c = current {
                index += 1
                if c == 92 {
                    guard current != nil else { throw CoreFailure.invalidPayload }
                    index += 1
                } else if c == 34 {
                    return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index]))
                }
            }
            throw CoreFailure.invalidPayload
        }
        mutating func digits() throws {
            let start = index
            while let c = current, (48...57).contains(c) { index += 1 }
            guard index > start else { throw CoreFailure.invalidPayload }
        }
        mutating func number() throws -> String {
            let start = index
            if current == 45 { index += 1 }
            if current == 48 { index += 1 }
            else {
                guard let c = current, (49...57).contains(c) else { throw CoreFailure.invalidPayload }
                try digits()
            }
            if current == 46 { index += 1; try digits() }
            if current == 69 || current == 101 {
                index += 1
                if current == 43 || current == 45 { index += 1 }
                try digits()
            }
            return String(decoding: bytes[start..<index], as: UTF8.self)
        }
        mutating func value(depth: Int) throws -> JSONValue {
            guard depth < 16 else { throw CoreFailure.invalidPayload }
            space()
            guard let c = current else { throw CoreFailure.invalidPayload }
            switch c {
            case 123:
                index += 1; space()
                var fields: [String: JSONValue] = [:]
                if current == 125 { index += 1; return .object(fields) }
                while true {
                    space(); let key = try string()
                    guard fields[key] == nil else { throw CoreFailure.invalidPayload }
                    space(); try consume(58); fields[key] = try value(depth: depth + 1); space()
                    if current == 125 { index += 1; return .object(fields) }
                    try consume(44)
                }
            case 91:
                index += 1; space()
                var entries: [JSONValue] = []
                if current == 93 { index += 1; return .array(entries) }
                while true {
                    entries.append(try value(depth: depth + 1)); space()
                    if current == 93 { index += 1; return .array(entries) }
                    try consume(44)
                }
            case 34: return .string(try string())
            case 45, 48...57: return .number(try number())
            case 116, 102, 110:
                let token = c == 116 ? "true" : c == 102 ? "false" : "null"
                for expected in token.utf8 { try consume(expected) }
                return c == 110 ? .null : .boolean
            default: throw CoreFailure.invalidPayload
            }
        }
    }
}

struct NumericVersion: Comparable {
    let components: [UInt32]
    init(_ text: String) throws {
        guard !text.isEmpty, text.utf8.count <= 87 else { throw CoreFailure.invalidPayload }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...8).contains(parts.count) else { throw CoreFailure.invalidPayload }
        self.components = try parts.map { part in
            guard !part.isEmpty, part.count == 1 || part.first != "0",
                  part.utf8.allSatisfy({ (48...57).contains($0) }), let value = UInt32(part) else { throw CoreFailure.invalidPayload }
            return value
        }
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let a = index < lhs.components.count ? lhs.components[index] : 0
            let b = index < rhs.components.count ? rhs.components[index] : 0
            if a != b { return a < b }
        }
        return false
    }
    static func == (lhs: Self, rhs: Self) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

func validDigest(_ text: String) -> Bool {
    text.utf8.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
}
func validIdentifier(_ text: String) -> Bool {
    !text.isEmpty && text.utf8.count <= 128 && text.utf8.allSatisfy {
        (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0)
    }
}
