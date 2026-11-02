public enum LicencePolicy {
    public static let maximumExactSecond: Int64 = 9_007_199_254_740_991
    public static let paidInterval: Int64 = 2_592_000
    public static let trialInterval: Int64 = 1_209_600
    public static let betaInterval: Int64 = 604_800

    static func sum(_ first: Int64, _ second: Int64) throws -> Int64 {
        guard first >= 0, second >= 0, first <= maximumExactSecond,
              second <= maximumExactSecond - first else { throw LicenceRefusal.policyBounds }
        return first + second
    }
    static func validate(_ claims: [String: LicenceJSONValue], state: Entitlement,
                         issued: Int64, until: Int64, hardEnd: Int64) throws {
        var fields: Set<String> = ["schemaVersion", "issuer", "audience", "accountID", "activationID",
                                   "deviceKeySHA256", "state", "entitlementRevision", "activationRevision",
                                   "sequence", "issuedAt", "permittedUntil", "hardEnd"]
        if [.paid, .grace, .trial].contains(state) { fields.insert(state.rawValue) }
        try claims.exactFields(fields)
        guard [.beta, .trial, .paid, .grace].contains(state) else {
            guard until == issued, hardEnd == issued else { throw LicenceRefusal.policyBounds }
            return
        }
        guard issued < until, until <= hardEnd else { throw LicenceRefusal.policyBounds }
        switch state {
        case .paid:
            let evidence = try claims.evidence("paid", fields: ["paidThrough"])
            let paidThrough = try evidence.number("paidThrough")
            guard hardEnd == paidThrough, until <= min(try sum(issued, paidInterval), paidThrough) else {
                throw LicenceRefusal.policyBounds
            }
        case .grace:
            let evidence = try claims.evidence("grace", fields: ["paidThrough", "graceDeadline"])
            let deadline = try evidence.number("graceDeadline")
            guard deadline == (try sum(evidence.number("paidThrough"), betaInterval)), hardEnd == deadline,
                  until <= min(try sum(issued, paidInterval), deadline) else { throw LicenceRefusal.policyBounds }
        case .trial:
            let evidence = try claims.evidence("trial", fields: ["startedAt", "expiresAt"])
            let start = try evidence.number("startedAt"), end = try evidence.number("expiresAt")
            guard end == (try sum(start, trialInterval)), hardEnd == end,
                  start <= issued, issued < end, until <= end else { throw LicenceRefusal.policyBounds }
        case .beta:
            guard hardEnd == until, until <= (try sum(issued, betaInterval)) else { throw LicenceRefusal.policyBounds }
        case .expired, .revoked, .none: break
        }
    }
}

/// Pure classification only; L2 owns transport, durable blocks and cache use.
public enum LicenceRefreshOutcome: Sendable {
    case noRoute, dnsFailure, connectTimeout, readTimeout, connectionReset
    case http(Int), tlsFailure, authenticationFailure, invalidLease
}
public enum LicenceRefreshClass: Equatable, Sendable { case eligibleOutage, verificationRequired }
public extension LicenceRefreshOutcome {
    var classification: LicenceRefreshClass {
        switch self {
        case .noRoute, .dnsFailure, .connectTimeout, .readTimeout, .connectionReset: .eligibleOutage
        case .http(let status) where [429, 500, 502, 503, 504].contains(status): .eligibleOutage
        default: .verificationRequired
        }
    }
}
