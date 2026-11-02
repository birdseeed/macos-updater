public struct AccountTarget: Equatable, Sendable {
    public let accountID: String
    public let accountRevision: UInt64
    public let entitlementRevision: UInt64
}
public struct CachedLease: Equatable, Sendable {
    public let state: String
    public let issuedAt: UInt64
    public let permittedUntil: UInt64
    public let hardEnd: UInt64
}
public struct ActivationTarget: Equatable, Sendable {
    public let account: AccountTarget
    public let activationID: String
    public let slot: UInt64
    public let activationRevision: UInt64
    public let createdAt: UInt64
    public let lastRefreshAt: UInt64?
    public let cachedLease: CachedLease?
    public let maxGrantPermittedUntil: UInt64?
}
public struct ProviderTarget: Equatable, Sendable {
    public let account: AccountTarget
    public let subscriptionID: String
    public let subscriptionRevision: UInt64
    public let currentPeriodStart: UInt64
    public let currentPeriodEnd: UInt64
    public let paidThrough: UInt64
    public let transactionID: String?
    public let periodStart: UInt64?
    public let periodEnd: UInt64?
}
public struct RecoveryTarget: Equatable, Sendable {
    public let account: AccountTarget
    public let caseID: String
    public let caseDigest: String
    public let newMaskedEmail: String
    public let activations: [ActivationTarget]
}
public enum SupportTarget: Equatable, Sendable {
    case account(AccountTarget), activation(ActivationTarget), provider(ProviderTarget), recovery(RecoveryTarget)
}

extension ActivationTarget {
    static func parse(_ object: SupportJSON, account: AccountTarget, preparedAt: UInt64) throws -> ActivationTarget {
        let fields = try object.fields(["activationID", "slot", "activationRevision", "createdAt", "lastRefreshAt",
                                        "cachedLease", "maxGrantPermittedUntil"])
        let id = try fields[0].hex(32)
        let slot = try fields[1].number()
        let revision = try fields[2].revision()
        let created = try fields[3].number()
        let refreshed = try fields[4].optionalNumber()
        guard (1...5).contains(slot), created <= preparedAt,
              refreshed.map({ created <= $0 && $0 <= preparedAt }) ?? true else { throw SupportError.malformedDescriptor }
        let maximum = try fields[6].optionalNumber()
        let cached: CachedLease?
        if fields[5].isNull {
            guard maximum == nil else { throw SupportError.malformedDescriptor }
            cached = nil
        } else {
            let lease = try fields[5].fields(["state", "issuedAt", "permittedUntil", "hardEnd"])
            let state = try lease[0].ascii(min: 1, max: 5)
            let issued = try lease[1].number(); let permitted = try lease[2].number(); let end = try lease[3].number()
            guard ["paid", "grace", "trial", "beta"].contains(state), created <= issued, issued <= preparedAt,
                  issued < permitted, permitted <= end, let maximum, maximum >= permitted else {
                throw SupportError.malformedDescriptor
            }
            // Historical maximum includes older grants, even ones whose responses were lost.
            // It is deliberately not clamped to the newest grant's hardEnd.
            cached = CachedLease(state: state, issuedAt: issued, permittedUntil: permitted, hardEnd: end)
        }
        return ActivationTarget(account: account, activationID: id, slot: slot, activationRevision: revision,
            createdAt: created, lastRefreshAt: refreshed, cachedLease: cached, maxGrantPermittedUntil: maximum)
    }
}

extension SupportTarget {
    static func parse(_ object: SupportJSON, action: SupportAction, account: AccountTarget,
                      preparedAt: UInt64) throws -> SupportTarget {
        switch action {
        case .deactivateActivation:
            return .activation(try ActivationTarget.parse(object, account: account, preparedAt: preparedAt))
        case .resendSignInCode:
            _ = try object.fields([]); return .account(account)
        case .reconcileProviderState, .initiateCancellation, .initiateRefund:
            var keys = ["subscriptionID", "subscriptionRevision", "currentPeriodStart", "currentPeriodEnd", "paidThrough"]
            if action == .initiateRefund { keys += ["transactionID", "periodStart", "periodEnd"] }
            let fields = try object.fields(keys)
            let subscription = try fields[0].providerReference(); let revision = try fields[1].revision()
            let start = try fields[2].number(); let end = try fields[3].number(); let paid = try fields[4].number()
            guard start < end else { throw SupportError.malformedDescriptor }
            var transaction: String?; var periodStart: UInt64?; var periodEnd: UInt64?
            if action == .initiateRefund {
                transaction = try fields[5].providerReference()
                let first = try fields[6].number(); let last = try fields[7].number()
                guard first < last else { throw SupportError.malformedDescriptor }
                periodStart = first; periodEnd = last
            }
            return .provider(ProviderTarget(account: account, subscriptionID: subscription, subscriptionRevision: revision,
                currentPeriodStart: start, currentPeriodEnd: end, paidThrough: paid, transactionID: transaction,
                periodStart: periodStart, periodEnd: periodEnd))
        case .changeAccountEmail:
            let fields = try object.fields(["caseID", "caseDigest", "newMaskedEmail", "activations"])
            let caseID = try fields[0].hex(32); let digest = try fields[1].hex(64); let email = try fields[2].maskedEmail()
            let items = try fields[3].array()
            guard (1...5).contains(items.count) else { throw SupportError.malformedDescriptor }
            var targets: [ActivationTarget] = []; var seen = Set<String>(); var previousSlot: UInt64 = 0
            for item in items {
                let activation = try ActivationTarget.parse(item, account: account, preparedAt: preparedAt)
                guard activation.slot > previousSlot, seen.insert(activation.activationID).inserted else {
                    throw SupportError.malformedDescriptor
                }
                previousSlot = activation.slot; targets.append(activation)
            }
            return .recovery(RecoveryTarget(account: account, caseID: caseID, caseDigest: digest,
                                             newMaskedEmail: email, activations: targets))
        }
    }

    var binding: (id: String, revision: UInt64) {
        switch self {
        case .account(let a): return (a.accountID, a.accountRevision)
        case .activation(let a): return (a.activationID, a.activationRevision)
        case .provider(let p): return (p.subscriptionID, p.subscriptionRevision)
        case .recovery(let r): return (r.caseID, r.account.accountRevision)
        }
    }
    var auditIdentifiers: [String] {
        switch self {
        case .account(let a): return [a.accountID]
        case .activation(let a): return [a.activationID]
        case .provider(let p): return [p.subscriptionID] + (p.transactionID.map { [$0] } ?? [])
        case .recovery(let r): return [r.caseID] + r.activations.map(\.activationID)
        }
    }
}
