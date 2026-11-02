import Foundation

/// Display values only. This type supplies no lease or installation authority.
public struct SubscriptionSummary: Sendable, Equatable {
    public let subscriptionID: String
    public let status: String
    public let paidThrough: Int64?
    public let renewsAt: Int64?
    public let cancellationState: String
    public let accessEnds: Int64?
    public let paymentState: String
    public let graceDeadline: Int64?
    public let refund: String
    public let endReason: String?
    public enum Refusal: Error { case invalidDisplay }
    public static func decode(_ data: Data) throws -> SubscriptionSummary {
        var parser = DisplayParser(data)
        let root = try parser.decode()
        func object(_ value: DisplayValue?, _ fields: Set<String>) throws -> [String: DisplayValue] {
            guard case .object(let result) = value, Set(result.keys) == fields else { throw Refusal.invalidDisplay }
            return result
        }
        func text(_ value: DisplayValue?, _ allowed: Set<String>) throws -> String {
            guard case .text(let result) = value, allowed.contains(result) else { throw Refusal.invalidDisplay }
            return result
        }
        func second(_ value: DisplayValue?) throws -> Int64? {
            if case .null = value { return nil }
            guard case .number(let result) = value, result <= 253402300799 else { throw Refusal.invalidDisplay }
            return result
        }
        let r = try object(root, ["schemaVersion", "subscriptionID", "status", "paidThrough", "renewsAt", "cancellation", "payment", "refund", "endReason"])
        guard case .number(1) = r["schemaVersion"], case .text(let identifier) = r["subscriptionID"],
              identifier.range(of: "^sub_fixture_[A-Za-z0-9-]{1,48}$", options: .regularExpression) != nil else { throw Refusal.invalidDisplay }
        let c = try object(r["cancellation"], ["state", "accessEnds"])
        let p = try object(r["payment"], ["state", "graceDeadline"])
        let paid = try second(r["paidThrough"]), grace = try second(p["graceDeadline"])
        if let grace { guard let paid, grace == paid + 604800 else { throw Refusal.invalidDisplay } }
        let endReason: String?
        if case .null = r["endReason"] { endReason = nil }
        else { endReason = try text(r["endReason"], ["expired", "refunded", "chargeback"]) }
        return SubscriptionSummary(subscriptionID: identifier,
            status: try text(r["status"], ["none", "active", "cancelling", "pastDue", "ended"]),
            paidThrough: paid, renewsAt: try second(r["renewsAt"]),
            cancellationState: try text(c["state"], ["none", "requested", "scheduled", "effective"]),
            accessEnds: try second(c["accessEnds"]), paymentState: try text(p["state"], ["current", "failed", "ended"]),
            graceDeadline: grace, refund: try text(r["refund"], ["none", "pending", "refunded"]), endReason: endReason)
    }
}

// Independent display grammar includes explicit nulls without widening lease decoding.
private indirect enum DisplayValue {
    case object([String: DisplayValue]), text(String), number(Int64), null
}
private struct DisplayParser {
    private let bytes: [UInt8]
    private var offset = 0
    init(_ data: Data) { bytes = Array(data) }
    private var current: UInt8? { offset < bytes.count ? bytes[offset] : nil }
    private mutating func whitespace() { while let c = current, [9, 10, 13, 32].contains(c) { offset += 1 } }
    private mutating func take(_ byte: UInt8) throws {
        guard current == byte else { throw SubscriptionSummary.Refusal.invalidDisplay }
        offset += 1
    }
    mutating func decode() throws -> DisplayValue {
        guard !bytes.isEmpty, bytes.count <= 16384, !bytes.contains(0),
              !bytes.starts(with: [239, 187, 191]), String(bytes: bytes, encoding: .utf8) != nil else { throw SubscriptionSummary.Refusal.invalidDisplay }
        let result = try value(depth: 1)
        whitespace()
        guard offset == bytes.count else { throw SubscriptionSummary.Refusal.invalidDisplay }
        return result
    }
    private mutating func value(depth: Int) throws -> DisplayValue {
        guard depth <= 4 else { throw SubscriptionSummary.Refusal.invalidDisplay }
        whitespace()
        if current == 123 {
            offset += 1; whitespace()
            var object: [String: DisplayValue] = [:]
            if current == 125 { offset += 1; return .object(object) }
            while true {
                let key = try string()
                guard object[key] == nil, object.count < 32 else { throw SubscriptionSummary.Refusal.invalidDisplay }
                whitespace(); try take(58)
                object[key] = try value(depth: depth + 1)
                whitespace()
                if current == 125 { offset += 1; return .object(object) }
                try take(44); whitespace()
            }
        }
        if current == 34 { return .text(try string()) }
        if current == 110 {
            for c in [UInt8(110), 117, 108, 108] { try take(c) }
            return .null
        }
        guard let first = current, (48...57).contains(first) else { throw SubscriptionSummary.Refusal.invalidDisplay }
        var number: Int64 = 0
        while let c = current, (48...57).contains(c) {
            if offset > 0, number == 0, bytes[offset - 1] == 48 { throw SubscriptionSummary.Refusal.invalidDisplay }
            let digit = Int64(c - 48)
            guard number <= (253402300799 - digit) / 10 else { throw SubscriptionSummary.Refusal.invalidDisplay }
            number = number * 10 + digit; offset += 1
        }
        return .number(number)
    }
    private mutating func string() throws -> String {
        try take(34)
        var result: [UInt8] = []
        while let c = current {
            offset += 1
            if c == 34 { return String(decoding: result, as: UTF8.self) }
            var decoded = c
            if c == 92 {
                guard let escape = current else { throw SubscriptionSummary.Refusal.invalidDisplay }
                offset += 1
                if [34, 47, 92].contains(escape) { decoded = escape }
                else if escape == 117 {
                    var scalar: UInt16 = 0
                    for _ in 0..<4 {
                        guard let h = current else { throw SubscriptionSummary.Refusal.invalidDisplay }
                        let digit: UInt16
                        switch h {
                        case 48...57: digit = UInt16(h - 48)
                        case 65...70: digit = UInt16(h - 55)
                        case 97...102: digit = UInt16(h - 87)
                        default: throw SubscriptionSummary.Refusal.invalidDisplay
                        }
                        scalar = scalar * 16 + digit; offset += 1
                    }
                    guard scalar >= 32, scalar <= 126 else { throw SubscriptionSummary.Refusal.invalidDisplay }
                    decoded = UInt8(scalar)
                } else { throw SubscriptionSummary.Refusal.invalidDisplay }
            }
            guard decoded >= 32, decoded <= 126, result.count < 256 else { throw SubscriptionSummary.Refusal.invalidDisplay }
            result.append(decoded)
        }
        throw SubscriptionSummary.Refusal.invalidDisplay
    }
}
