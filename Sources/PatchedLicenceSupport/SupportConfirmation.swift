import Foundation
import CryptoKit

/// An exact-byte display binding, not an authenticated assertion or permission.
/// There is no public initializer accepting parallel fields or a decoded dictionary.
public struct SupportConfirmation: Sendable {
    public let descriptorBytes: Data
    public let digest: String
    public let requestID: String
    public let operatorID: String
    public let action: SupportAction
    public let account: AccountTarget
    public let target: SupportTarget
    public let maskedEmail: String
    public let consequences: [String]
    public let reasonCode: String
    public let reasonNote: String
    public let reasonNoteSHA256: String
    public let preparedAt: UInt64
    public let expiresAt: UInt64
    let object: SupportJSON
    let recoveryEvidence: RecoveryEvidence?

    public static func parse(_ bytes: Data, expectedDigest: String, operatorID: String,
                             now: UInt64) throws -> SupportConfirmation {
        var parser = try SupportJSONParser(bytes)
        let object = try parser.parse()
        let fields = try object.fields([
            "schemaVersion", "requestID", "nonce", "operatorID", "action", "accountID", "accountRevision",
            "entitlementRevision", "maskedEmail", "target", "evidence", "consequences", "reasonCode",
            "reasonNote", "reasonNoteSHA256", "preparedAt", "expiresAt"
        ])
        guard try fields[0].number() == 1 else { throw SupportError.malformedDescriptor }
        let requestID = try fields[1].hex(32)
        let nonce = try fields[2].ascii(min: 44, max: 44)
        guard let nonceBytes = Data(base64Encoded: nonce), nonceBytes.count == 32,
              nonceBytes.base64EncodedString() == nonce else { throw SupportError.malformedDescriptor }
        let preparingOperator = try fields[3].hex(32)
        guard let action = SupportAction(rawValue: try fields[4].ascii(min: 1, max: 32)) else {
            throw SupportError.malformedDescriptor
        }
        let account = try AccountTarget(accountID: fields[5].hex(32), accountRevision: fields[6].revision(),
                                        entitlementRevision: fields[7].revision())
        let email = try fields[8].maskedEmail()
        let prepared = try fields[15].number()
        let expiry = try fields[16].number()
        guard let exactExpiry = SupportWire.add(prepared, 300), expiry == exactExpiry else {
            throw SupportError.malformedDescriptor
        }
        let target = try SupportTarget.parse(fields[9], action: action, account: account, preparedAt: prepared)
        var recoveryEvidence: RecoveryEvidence?
        switch action {
        case .initiateRefund:
            let evidence = try fields[10].fields(["firstPurchase", "withinThirtyDays", "noPriorRefundAdjustment"])
            for fact in evidence { try fact.requiredTrue() }
        case .changeAccountEmail:
            recoveryEvidence = try RecoveryEvidence.parse(fields[10])
        default:
            _ = try fields[10].fields([])
        }
        let consequences = try fields[11].array().map { try $0.ascii(min: 1, max: 64) }
        guard consequences == action.consequenceCodes else { throw SupportError.malformedDescriptor }
        let reason = try fields[12].ascii(min: 1, max: 32)
        try SupportWire.reason(reason, recovery: action == .changeAccountEmail)
        let note = try fields[13].text(max: 200)
        // String equality uses canonical equivalence; compare UTF-8 to require NFC on the wire.
        guard Array(note.utf8) == Array(note.precomposedStringWithCanonicalMapping.utf8),
              !note.contains("@") else { throw SupportError.malformedDescriptor }
        var digits = 0
        for scalar in note.unicodeScalars {
            digits = scalar.properties.generalCategory == .decimalNumber ? digits + 1 : 0
            guard digits < 6 else { throw SupportError.malformedDescriptor }
        }
        let noteHash = try fields[14].hex(64)
        guard SupportWire.sha256(Data(note.utf8)) == noteHash else { throw SupportError.malformedDescriptor }
        let actualDigest = SupportWire.digest(bytes, domain: "im.patched.support.confirm.v1")
        guard SupportWire.isHex(expectedDigest, count: 64), expectedDigest == actualDigest else {
            throw SupportError.digestMismatch
        }
        guard preparingOperator == operatorID else { throw SupportError.foreignOperator }
        guard now <= SupportWire.maximumExactSecond, prepared <= now, now < expiry else { throw SupportError.expired }
        return SupportConfirmation(descriptorBytes: bytes, digest: actualDigest, requestID: requestID,
            operatorID: preparingOperator, action: action, account: account, target: target, maskedEmail: email,
            consequences: consequences, reasonCode: reason, reasonNote: note, reasonNoteSHA256: noteHash,
            preparedAt: prepared, expiresAt: expiry, object: object, recoveryEvidence: recoveryEvidence)
    }
}

// Deliberately isolated from the licensing/activation parsers and their trust types.
// A small ordered syntax tree retains decoded strings and integer tokens without reserialising input.
indirect enum SupportJSON: Sendable {
    case object([(String, SupportJSON)]), array([SupportJSON]), string(String), number(UInt64), bool(Bool), null

    func fields(_ names: [String]) throws -> [SupportJSON] {
        guard case .object(let pairs) = self, pairs.map({ $0.0 }) == names else { throw SupportError.malformedDescriptor }
        return pairs.map { $0.1 }
    }
    func array() throws -> [SupportJSON] {
        guard case .array(let values) = self else { throw SupportError.malformedDescriptor }
        return values
    }
    func number() throws -> UInt64 {
        guard case .number(let n) = self else { throw SupportError.malformedDescriptor }
        return n
    }
    func revision() throws -> UInt64 {
        let n = try number()
        guard n > 0 else { throw SupportError.malformedDescriptor }
        return n
    }
    func text(max: Int) throws -> String {
        guard case .string(let s) = self, s.utf8.count <= max else { throw SupportError.malformedDescriptor }
        for scalar in s.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .unassigned:
                throw SupportError.malformedDescriptor
            default: break
            }
        }
        return s
    }
    func ascii(min: Int, max: Int) throws -> String {
        let s = try text(max: max)
        guard s.utf8.count >= min, s.utf8.allSatisfy({ $0 >= 0x20 && $0 <= 0x7e }) else {
            throw SupportError.malformedDescriptor
        }
        return s
    }
    func hex(_ count: Int) throws -> String {
        let s = try ascii(min: count, max: count)
        guard SupportWire.isHex(s, count: count) else { throw SupportError.malformedDescriptor }
        return s
    }
    func requiredTrue() throws {
        guard case .bool(true) = self else { throw SupportError.malformedDescriptor }
    }
    var isNull: Bool { if case .null = self { return true }; return false }
    func optionalNumber() throws -> UInt64? { isNull ? nil : try number() }
    func providerReference() throws -> String {
        let s = try ascii(min: 1, max: 128)
        guard s.utf8.allSatisfy({ SupportWire.alphanumeric($0) || $0 == 45 || $0 == 95 }) else {
            throw SupportError.malformedDescriptor
        }
        return s
    }
    func maskedEmail() throws -> String {
        let s = try ascii(min: 7, max: 254)
        let bytes = Array(s.utf8)
        let safeLocal = Array(".!#$%&'+-/=?^_`{|}~".utf8)
        guard SupportWire.alphanumeric(bytes[0]) || safeLocal.contains(bytes[0]),
              Array(bytes[1...4]) == Array("***@".utf8) else { throw SupportError.malformedDescriptor }
        let host = String(decoding: bytes.dropFirst(5), as: UTF8.self)
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { throw SupportError.malformedDescriptor }
        for label in labels {
            let part = Array(label.utf8)
            guard (1...63).contains(part.count), let first = part.first, let last = part.last,
                  SupportWire.alphanumeric(first), SupportWire.alphanumeric(last),
                  part.allSatisfy({ SupportWire.alphanumeric($0) || $0 == 45 }) else { throw SupportError.malformedDescriptor }
        }
        return s
    }
}

enum SupportWire {
    static let maximumExactSecond: UInt64 = 9_007_199_254_740_991
    static func alphanumeric(_ b: UInt8) -> Bool { (48...57).contains(b) || (65...90).contains(b) || (97...122).contains(b) }
    static func isHex(_ s: String, count: Int) -> Bool {
        s.utf8.count == count && s.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func add(_ value: UInt64, _ amount: UInt64) -> UInt64? {
        guard value <= maximumExactSecond, amount <= maximumExactSecond - value else { return nil }
        return value + amount
    }
    static func sha256(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    static func digest(_ bytes: Data, domain: String) -> String { sha256(Data(domain.utf8) + Data([0]) + bytes) }
    static func reason(_ reason: String, recovery: Bool) throws {
        guard recovery ? reason == "accountRecovery" : ["customerRequest", "providerMismatch"].contains(reason) else {
            throw SupportError.malformedDescriptor
        }
    }
}

struct SupportJSONParser {
    private let bytes: [UInt8]
    private var index = 0
    init(_ data: Data) throws {
        guard !data.isEmpty, data.count <= 4096, !data.contains(0),
              !data.starts(with: [0xef, 0xbb, 0xbf]), String(data: data, encoding: .utf8) != nil else {
            throw SupportError.malformedDescriptor
        }
        bytes = Array(data)
    }
    mutating func parse() throws -> SupportJSON {
        let value = try value(depth: 0)
        guard index == bytes.count else { throw SupportError.malformedDescriptor }
        return value
    }
    private mutating func value(depth: Int) throws -> SupportJSON {
        guard index < bytes.count else { throw SupportError.malformedDescriptor }
        switch bytes[index] {
        case 123:
            guard depth < 5 else { throw SupportError.malformedDescriptor }
            index += 1
            var pairs: [(String, SupportJSON)] = []; var seen = Set<String>()
            if consume(125) { return .object(pairs) }
            while true {
                let key = try string()
                guard seen.insert(key).inserted, consume(58) else { throw SupportError.malformedDescriptor }
                pairs.append((key, try value(depth: depth + 1)))
                if consume(125) { return .object(pairs) }
                guard consume(44) else { throw SupportError.malformedDescriptor }
            }
        case 91:
            guard depth < 5 else { throw SupportError.malformedDescriptor }
            index += 1; var values: [SupportJSON] = []
            if consume(93) { return .array(values) }
            while true {
                values.append(try value(depth: depth + 1))
                if consume(93) { return .array(values) }
                guard consume(44) else { throw SupportError.malformedDescriptor }
            }
        case 34: return .string(try string())
        case 48...57:
            let start = index
            var result: UInt64 = 0
            while index < bytes.count, (48...57).contains(bytes[index]) {
                let digit = UInt64(bytes[index] - 48)
                guard result <= (SupportWire.maximumExactSecond - digit) / 10 else { throw SupportError.malformedDescriptor }
                result = result * 10 + digit; index += 1
            }
            guard index - start == 1 || bytes[start] != 48 else { throw SupportError.malformedDescriptor }
            return .number(result)
        case 116: try literal("true"); return .bool(true)
        case 102: try literal("false"); return .bool(false)
        case 110: try literal("null"); return .null
        default: throw SupportError.malformedDescriptor
        }
    }
    private mutating func consume(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1; return true
    }
    private mutating func literal(_ text: String) throws {
        for b in text.utf8 { guard consume(b) else { throw SupportError.malformedDescriptor } }
    }
    private mutating func string() throws -> String {
        guard consume(34) else { throw SupportError.malformedDescriptor }
        var output: [UInt8] = []
        while index < bytes.count {
            let b = bytes[index]; index += 1
            if b == 34 {
                guard let s = String(bytes: output, encoding: .utf8) else { throw SupportError.malformedDescriptor }
                return s
            }
            guard b >= 0x20 else { throw SupportError.malformedDescriptor }
            if b != 92 { output.append(b); continue }
            guard index < bytes.count else { throw SupportError.malformedDescriptor }
            let escape = bytes[index]; index += 1
            switch escape {
            case 34, 47, 92: output.append(escape)
            case 98: output.append(8)
            case 102: output.append(12)
            case 110: output.append(10)
            case 114: output.append(13)
            case 116: output.append(9)
            case 117:
                let first = try hexQuad()
                var code = first
                if (0xd800...0xdbff).contains(first) {
                    guard consume(92), consume(117) else { throw SupportError.malformedDescriptor }
                    let second = try hexQuad()
                    guard (0xdc00...0xdfff).contains(second) else { throw SupportError.malformedDescriptor }
                    code = 0x10000 + (first - 0xd800) * 0x400 + (second - 0xdc00)
                }
                guard let scalar = Unicode.Scalar(code), code != 0 else { throw SupportError.malformedDescriptor }
                output.append(contentsOf: String(scalar).utf8)
            default: throw SupportError.malformedDescriptor
            }
        }
        throw SupportError.malformedDescriptor
    }
    private mutating func hexQuad() throws -> UInt32 {
        var result: UInt32 = 0
        for _ in 0..<4 {
            guard index < bytes.count else { throw SupportError.malformedDescriptor }
            let b = bytes[index]; index += 1
            let digit: UInt32
            switch b {
            case 48...57: digit = UInt32(b - 48)
            case 65...70: digit = UInt32(b - 55)
            case 97...102: digit = UInt32(b - 87)
            default: throw SupportError.malformedDescriptor
            }
            result = result * 16 + digit
        }
        return result
    }
}
