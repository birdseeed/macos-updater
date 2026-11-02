import Foundation
public protocol SupportClient {
    func lookup(accountID: String) throws -> SupportPresentation
    func prepare(action: SupportAction, accountID: String) throws -> SupportConfirmation
    func commit(requestID: String, digest: String) throws -> SupportOutcome
}
/// Permanent default. No injected test outcome can configure this client.
public struct RefusingSupportClient: SupportClient {
    public init() {}
    public func lookup(accountID: String) throws -> SupportPresentation { throw SupportError.notConfigured }
    public func prepare(action: SupportAction, accountID: String) throws -> SupportConfirmation { throw SupportError.notConfigured }
    public func commit(requestID: String, digest: String) throws -> SupportOutcome { throw SupportError.notConfigured }
}

/// Explicit synthetic input, never an assertion verifier or authentication result.
@_spi(Testing) public struct SupportFixtureContext {
    public var kind: String
    public var operatorID: String
    public var sessionID: String
    public var preparedSessionID: String
    public var requestID: String
    public var digest: String
    public var accountID: String
    public var accountRevision: UInt64
    public var entitlementRevision: UInt64
    public var targetRevision: UInt64
    public var targetID: String
    public var humanConfirmed: Bool
    public init(kind: String, operatorID: String, sessionID: String, preparedSessionID: String,
                requestID: String, digest: String, accountID: String, accountRevision: UInt64,
                entitlementRevision: UInt64, targetRevision: UInt64, targetID: String,
                humanConfirmed: Bool) {
        self.kind = kind; self.operatorID = operatorID; self.sessionID = sessionID
        self.preparedSessionID = preparedSessionID; self.requestID = requestID; self.digest = digest
        self.accountID = accountID; self.accountRevision = accountRevision
        self.entitlementRevision = entitlementRevision; self.targetRevision = targetRevision
        self.targetID = targetID; self.humanConfirmed = humanConfirmed
    }
}
@_spi(Testing) public enum SupportFixtureFault: CaseIterable {
    case none, missingEffect, falseGuard, missingDependent, auditThrows, auditNoRow, unmatchedCompletion, lostReadback
}
@_spi(Testing) public struct SupportFixtureLedger: Equatable {
    public var effectCount = 0
    public var dependentCount = 0
    public var audit: [String] = []
    public var outcome: SupportOutcome?
    public var terminalRequestID: String?
    public var terminalOperatorID: String?
    public var terminalDigest: String?
    public init() {}
}
/// In-memory transaction mechanics only, accessible through the explicit Testing SPI.
/// One ledger belongs to one prepared request. It is not a database or authentication adapter.
@_spi(Testing) public enum SupportFixtureModel {
    public static func commit(_ confirmation: SupportConfirmation, context: SupportFixtureContext,
                              now: UInt64, ledger: inout SupportFixtureLedger,
                              fault: SupportFixtureFault = .none) throws -> SupportOutcome {
        guard confirmation.action != .changeAccountEmail else { throw SupportError.recoveryHeld }
        let change = try transition(confirmation, context: context, now: now, ledger: ledger,
                                    requiredDependents: confirmation.action == .initiateRefund ? 2 : 1, fault: fault)
        ledger = change.ledger
        if change.didWrite && fault == .lostReadback { throw SupportError.unknownOutcome }
        return change.outcome
    }

    static func validateBinding(_ c: SupportConfirmation, context: SupportFixtureContext) throws {
        guard context.operatorID == c.operatorID else { throw SupportError.foreignOperator }
        guard context.kind == "operatorFixture", context.humanConfirmed,
              SupportWire.isHex(context.sessionID, count: 32), context.sessionID == context.preparedSessionID,
              context.requestID == c.requestID, context.digest == c.digest else { throw SupportError.invalidContext }
    }

    static func terminal(_ c: SupportConfirmation, ledger: SupportFixtureLedger) throws -> SupportOutcome? {
        if let outcome = ledger.outcome {
            guard ledger.terminalOperatorID == c.operatorID else { throw SupportError.foreignOperator }
            guard ledger.terminalRequestID == c.requestID, ledger.terminalDigest == c.digest else { throw SupportError.invalidContext }
            guard !ledger.audit.isEmpty,
                  outcome == .committed ? (ledger.effectCount == 1 && ledger.dependentCount > 0) :
                    (ledger.effectCount == 0 && ledger.dependentCount == 0) else { throw SupportError.rollback }
            return outcome
        }
        guard ledger == SupportFixtureLedger() else { throw SupportError.rollback }
        return nil
    }

    static func matches(_ c: SupportConfirmation, context: SupportFixtureContext) -> Bool {
        c.account.accountID == context.accountID && c.account.accountRevision == context.accountRevision &&
        c.account.entitlementRevision == context.entitlementRevision && c.target.binding.id == context.targetID &&
        c.target.binding.revision == context.targetRevision
    }

    struct Transition {
        let outcome: SupportOutcome
        let ledger: SupportFixtureLedger
        let didWrite: Bool
    }

    /// Calculate a whole replacement before publishing it. A thrown constraint/audit error
    /// exposes neither the effect nor the claim. Real D1 batch semantics are not modelled here.
    static func transition(_ c: SupportConfirmation, context: SupportFixtureContext, now: UInt64,
                           ledger: SupportFixtureLedger, requiredDependents: Int,
                           forcedTargetChanged: Bool = false, fault: SupportFixtureFault) throws -> Transition {
        try validateBinding(c, context: context)
        if let outcome = try terminal(c, ledger: ledger) {
            return Transition(outcome: outcome, ledger: ledger, didWrite: false)
        }
        guard now <= SupportWire.maximumExactSecond, c.preparedAt <= now, now < c.expiresAt else {
            throw SupportError.expired
        }
        guard requiredDependents > 0 else { throw SupportError.rollback }
        let changed = !matches(c, context: context) || forcedTargetChanged || fault == .falseGuard
        // The attempt's effect marker exists only if operate actually wrote under every guard.
        let effect = !changed && fault != .missingEffect
        let outcome: SupportOutcome
        if effect { outcome = .committed }
        else if changed { outcome = .targetChanged }
        else { throw SupportError.rollback } // unmatched pending completion would violate NOT NULL
        guard fault != .unmatchedCompletion else { throw SupportError.rollback }
        var staged = ledger
        staged.effectCount = effect ? 1 : 0
        staged.dependentCount = effect && fault != .missingDependent ? requiredDependents : 0
        staged.outcome = outcome
        staged.terminalRequestID = c.requestID
        staged.terminalOperatorID = c.operatorID
        staged.terminalDigest = c.digest
        guard fault != .auditThrows else { throw SupportError.rollback }
        if fault != .auditNoRow {
            // No note text, masked email, nonce, case evidence or human-supplied labels enter the audit.
            // Target strings come only from validated opaque descriptor fields.
            let event = "event=commit|time=\(now)|operatorID=\(c.operatorID)|requestID=\(c.requestID)" +
                "|action=\(c.action.rawValue)|accountID=\(c.account.accountID)|targets=\(c.target.auditIdentifiers.joined(separator: ","))" +
                "|accountRevision=\(c.account.accountRevision)|entitlementRevision=\(c.account.entitlementRevision)" +
                "|targetRevision=\(c.target.binding.revision)|descriptorDigest=\(c.digest)" +
                "|reasonCode=\(c.reasonCode)|reasonNoteSHA256=\(c.reasonNoteSHA256)|outcome=\(outcome.rawValue)"
            staged.audit.append(event)
        }
        guard !staged.audit.isEmpty, !effect || staged.dependentCount == requiredDependents else {
            throw SupportError.rollback
        }
        return Transition(outcome: outcome, ledger: staged, didWrite: true)
    }
}
