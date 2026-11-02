import Foundation
/// Deterministic case binding only; neither a hash nor necessary checks establish ownership.
public struct RecoveryCase: Sendable {
    public let caseID: String
    public let digest: String
    public let account: AccountTarget
    public let operatorID: String
    public let kind: String
    public let newEmailHMAC: String
    let oldEmailHMAC: String
    let evidence: RecoveryEvidence

    public static func parse(_ bytes: Data, expectedDigest: String) throws -> RecoveryCase {
        var parser = try SupportJSONParser(bytes)
        let object = try parser.parse()
        let f = try object.fields(["schemaVersion", "caseID", "accountID", "accountRevision", "entitlementRevision",
                                   "oldEmailHMAC", "newEmailHMAC", "evidence", "operatorID", "reasonCode"])
        guard try f[0].number() == 1 else { throw SupportError.malformedDescriptor }
        let id = try f[1].hex(32)
        let account = try AccountTarget(accountID: f[2].hex(32), accountRevision: f[3].revision(),
                                        entitlementRevision: f[4].revision())
        let old = try f[5].hex(64); let new = try f[6].hex(64)
        guard old != new else { throw SupportError.malformedDescriptor }
        let evidence = try RecoveryEvidence.parse(f[7])
        let operatorID = try f[8].hex(32)
        try SupportWire.reason(f[9].ascii(min: 1, max: 32), recovery: true)
        let actual = SupportWire.digest(bytes, domain: "im.patched.support.recovery.v1")
        guard SupportWire.isHex(expectedDigest, count: 64), expectedDigest == actual else { throw SupportError.digestMismatch }
        return RecoveryCase(caseID: id, digest: actual, account: account, operatorID: operatorID,
                            kind: evidence.kind, newEmailHMAC: new, oldEmailHMAC: old, evidence: evidence)
    }
}

struct RecoveryEvidence: Equatable, Sendable {
    let kind: String
    let sourceReference: String
    let possessionReference: String
    let newEmailReference: String
    let ownershipReference: String
    static func parse(_ object: SupportJSON) throws -> RecoveryEvidence {
        let f = try object.fields(["sourceKind", "sourceVerified", "sourceReference", "possessionVerified", "possessionReference",
                                   "newEmailVerified", "newEmailReference", "ownershipJudgement", "ownershipReference"])
        let kind = try f[0].ascii(min: 1, max: 5)
        guard ["paid", "trial", "beta"].contains(kind) else { throw SupportError.malformedDescriptor }
        for index in [1, 3, 5, 7] { try f[index].requiredTrue() }
        return try RecoveryEvidence(kind: kind, sourceReference: f[2].hex(32), possessionReference: f[4].hex(32),
                                     newEmailReference: f[6].hex(32), ownershipReference: f[8].hex(32))
    }
}
@_spi(Testing) public struct RecoveryFixtureContext {
    public var operatorID: String
    public var accountID: String
    public var caseID: String
    public var caseDigest: String
    public var independentOwnershipJudgement: Bool
    public var ownershipReference: String
    public var sourceKind: String
    public var sourceAccountID: String
    public var sourceVerified: Bool
    public var betaInvitationVerified: Bool
    public var activeMacPossession: Bool
    public var possessionCaseDigest: String
    public var proofPurpose: String
    public var proofAccountID: String
    public var proofCaseID: String
    public var proofCaseDigest: String
    public var proofNewEmailHMAC: String
    public var proofVerifiedAt: UInt64
    public var proofExpiresAt: UInt64
    public var noticeCaseDigest: String
    public var noticeAcceptedAt: UInt64?
    public var hold: String
    public var addressCollision: Bool
    public var exceptionalLostAllMacs: Bool
    public init(operatorID: String, accountID: String, caseID: String, caseDigest: String,
                independentOwnershipJudgement: Bool, ownershipReference: String, sourceKind: String,
                sourceAccountID: String, sourceVerified: Bool, betaInvitationVerified: Bool,
                activeMacPossession: Bool, possessionCaseDigest: String, proofPurpose: String,
                proofAccountID: String, proofCaseID: String, proofCaseDigest: String, proofNewEmailHMAC: String,
                proofVerifiedAt: UInt64, proofExpiresAt: UInt64, noticeCaseDigest: String,
                noticeAcceptedAt: UInt64?, hold: String, addressCollision: Bool, exceptionalLostAllMacs: Bool) {
        self.operatorID = operatorID; self.accountID = accountID; self.caseID = caseID; self.caseDigest = caseDigest
        self.independentOwnershipJudgement = independentOwnershipJudgement; self.ownershipReference = ownershipReference
        self.sourceKind = sourceKind; self.sourceAccountID = sourceAccountID; self.sourceVerified = sourceVerified
        self.betaInvitationVerified = betaInvitationVerified; self.activeMacPossession = activeMacPossession
        self.possessionCaseDigest = possessionCaseDigest; self.proofPurpose = proofPurpose
        self.proofAccountID = proofAccountID; self.proofCaseID = proofCaseID; self.proofCaseDigest = proofCaseDigest
        self.proofNewEmailHMAC = proofNewEmailHMAC; self.proofVerifiedAt = proofVerifiedAt
        self.proofExpiresAt = proofExpiresAt; self.noticeCaseDigest = noticeCaseDigest
        self.noticeAcceptedAt = noticeAcceptedAt; self.hold = hold; self.addressCollision = addressCollision
        self.exceptionalLostAllMacs = exceptionalLostAllMacs
    }
}
@_spi(Testing) public struct RecoveryFixtureState: Equatable {
    public var accountID: String
    public var accountRevision: UInt64
    public var entitlementRevision: UInt64
    public var emailHMAC: String
    public var sessions: [String: Bool]
    public var activationRevisions: [String: UInt64]
    public var occupiedSlots: [UInt64: String]
    public var trialStart: UInt64?
    public var trialEnd: UInt64?
    public var betaInvitation: String?
    public var paidHistory: [String]
    public var mintedSessions = 0
    public var mintedKeys = 0
    public var mintedLeases = 0
    public init(accountID: String, accountRevision: UInt64, entitlementRevision: UInt64, emailHMAC: String,
                sessions: [String: Bool], activationRevisions: [String: UInt64], occupiedSlots: [UInt64: String],
                trialStart: UInt64?, trialEnd: UInt64?, betaInvitation: String?, paidHistory: [String]) {
        self.accountID = accountID; self.accountRevision = accountRevision; self.entitlementRevision = entitlementRevision
        self.emailHMAC = emailHMAC; self.sessions = sessions; self.activationRevisions = activationRevisions
        self.occupiedSlots = occupiedSlots; self.trialStart = trialStart; self.trialEnd = trialEnd
        self.betaInvitation = betaInvitation; self.paidHistory = paidHistory
    }
}
/// Necessary recovery mechanics with separately injected synthetic ownership judgement.
/// This API cannot authenticate a human, send a notice, mint a credential or mutate a service.
@_spi(Testing) public enum RecoveryFixtureModel {
    public static func commit(_ recovery: RecoveryCase, confirmation: SupportConfirmation,
                              context: RecoveryFixtureContext, supportContext: SupportFixtureContext,
                              now: UInt64, state: inout RecoveryFixtureState,
                              ledger: inout SupportFixtureLedger,
                              fault: SupportFixtureFault = .none) throws -> SupportOutcome {
        try SupportFixtureModel.validateBinding(confirmation, context: supportContext)
        guard context.operatorID == recovery.operatorID, recovery.operatorID == confirmation.operatorID else {
            throw SupportError.foreignOperator
        }
        guard confirmation.action == .changeAccountEmail, case .recovery(let target) = confirmation.target,
              target.caseID == recovery.caseID, target.caseDigest == recovery.digest,
              target.account == recovery.account, confirmation.account == recovery.account,
              context.accountID == recovery.account.accountID, context.caseID == recovery.caseID,
              context.caseDigest == recovery.digest, confirmation.recoveryEvidence == recovery.evidence else {
            throw SupportError.recoveryHeld
        }
        // Terminal repeats read the durable result. Expired proof/notice cannot cause another effect.
        if let terminal = try SupportFixtureModel.terminal(confirmation, ledger: ledger) { return terminal }
        guard now <= SupportWire.maximumExactSecond, confirmation.preparedAt <= now, now < confirmation.expiresAt else {
            throw SupportError.expired
        }
        try necessaryChecks(recovery, context: context, now: now)
        let changed = !stateMatches(recovery, target: target, state: state)
        var nextState = state
        if !changed {
            guard let revision = SupportWire.add(state.accountRevision, 1) else { throw SupportError.rollback }
            nextState.accountRevision = revision
            nextState.emailHMAC = recovery.newEmailHMAC
            for session in state.sessions.keys { nextState.sessions[session] = false }
            for activation in target.activations {
                guard let revision = SupportWire.add(activation.activationRevision, 1) else { throw SupportError.rollback }
                nextState.activationRevisions[activation.activationID] = revision
            }
            nextState.occupiedSlots.removeAll()
        }
        let transition = try SupportFixtureModel.transition(confirmation, context: supportContext, now: now,
            ledger: ledger, requiredDependents: 1 + state.sessions.count + target.activations.count * 2,
            forcedTargetChanged: changed, fault: fault)
        // Publish both complete replacements only after every effect/dependent/audit assertion succeeds.
        if transition.outcome == .committed && transition.didWrite { state = nextState }
        ledger = transition.ledger
        if transition.didWrite && fault == .lostReadback { throw SupportError.unknownOutcome }
        return transition.outcome
    }

    private static func necessaryChecks(_ recovery: RecoveryCase, context c: RecoveryFixtureContext, now: UInt64) throws {
        guard !c.exceptionalLostAllMacs, c.independentOwnershipJudgement,
              c.ownershipReference == recovery.evidence.ownershipReference,
              SupportWire.isHex(c.ownershipReference, count: 32),
              c.sourceKind == recovery.kind, c.sourceAccountID == recovery.account.accountID, c.sourceVerified,
              recovery.kind != "beta" || c.betaInvitationVerified,
              c.activeMacPossession, c.possessionCaseDigest == recovery.digest else { throw SupportError.ownershipUnproven }
        guard !c.addressCollision else { throw SupportError.addressCollision }
        guard c.hold == "none", c.proofPurpose == "email-recovery", c.proofAccountID == recovery.account.accountID,
              c.proofCaseID == recovery.caseID, c.proofCaseDigest == recovery.digest,
              c.proofNewEmailHMAC == recovery.newEmailHMAC, c.proofVerifiedAt <= now,
              now < c.proofExpiresAt, c.proofExpiresAt <= SupportWire.maximumExactSecond,
              c.noticeCaseDigest == recovery.digest, let accepted = c.noticeAcceptedAt,
              let deadline = SupportWire.add(accepted, 259_200), now > deadline else { throw SupportError.recoveryHeld }
    }

    private static func stateMatches(_ recovery: RecoveryCase, target: RecoveryTarget, state: RecoveryFixtureState) -> Bool {
        guard state.accountID == recovery.account.accountID, state.accountRevision == recovery.account.accountRevision,
              state.entitlementRevision == recovery.account.entitlementRevision, state.emailHMAC == recovery.oldEmailHMAC,
              state.occupiedSlots.count == target.activations.count else { return false }
        for activation in target.activations {
            guard state.occupiedSlots[activation.slot] == activation.activationID,
                  state.activationRevisions[activation.activationID] == activation.activationRevision else { return false }
        }
        return true
    }
}
