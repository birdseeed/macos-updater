import Foundation
import CryptoKit

public enum AllocationOutcome: String, Equatable, Sendable {
    case activated, reused, limitReached, replaced, released, alreadyReleased, renamed
    case rebound, leased, revokedLease, stale, notFound, notActive, superseded, possessionRecorded
}

public struct ModelGrant: Equatable, Sendable {
    public var issuedAt: UInt64
    public var permittedUntil: UInt64
    public var hardEnd: UInt64
    public init(issuedAt: UInt64, permittedUntil: UInt64, hardEnd: UInt64) {
        self.issuedAt = issuedAt; self.permittedUntil = permittedUntil; self.hardEnd = hardEnd
    }
}

public struct ModelActivation: Equatable, Sendable {
    public var id = ""
    public var accountID = ""
    public var publicKey = Data()
    public var displayName = ""
    public var slot: Int? = nil
    public var released = false
    public var revision: UInt64 = 1
    public var generation: UInt64 = 1
    public var sequence: UInt64 = 0
    public var lastGrant: ModelGrant? = nil
    public var maxGrantPermittedUntil: UInt64? = nil
    public var lastRefreshAt: UInt64? = nil
    public var attestation: FixtureAttestationResult? = nil
    public init() {}
}

public struct ModelSession: Equatable, Sendable {
    public var id = ""
    public var accountID = ""
    public var authenticatedAt: UInt64 = 0
    public var expiresAt: UInt64 = 0
    public var revoked = false
    public var activationID: String? = nil
    public init() {}
}

public struct ModelChallenge: Equatable, Sendable {
    public var id = ""
    public var sessionID = ""
    public var accountID = ""
    public var operation: DeviceOperation = .activate
    public var keyDigest = Data()
    public var nonceMAC = Data()
    public var expiresAt: UInt64 = 0
    public var consumed = false
    public var recoveryCaseID: String? = nil
    public var recoveryCaseDigest: String? = nil
    public init() {}
}

public struct ModelRecoveryCase: Equatable, Sendable {
    public var id = ""
    public var accountID = ""
    public var digest = ""
    public var possessionActivationID: String? = nil
    public init() {}
}

public struct AllocationResult: Equatable, Sendable {
    public let outcome: AllocationOutcome
    public let activationID: String?
    public let released: Bool
    public let sequence: UInt64?
    public let grant: ModelGrant?
    public let assurance: KeyAssurance
}

public struct ModelRequestRecord: Equatable, Sendable {
    public let sessionID: String
    public let accountID: String
    public let operation: DeviceOperation
    public let requestID: String
    public let actionDigest: Data
    public let result: AllocationResult
}

/// Only these non-secret fields may enter the model audit.
public struct ModelAuditEvent: Equatable, Sendable {
    public let sessionID: String
    public let serviceTime: UInt64
    public let accountID: String
    public let activationID: String?
    public let requestID: String
    public let outcome: AllocationOutcome
    public let keyDigest: Data?
}

public struct ModelState: Equatable, Sendable {
    public var accountRevisions: [String: UInt64] = [:]
    public var entitlementRevisions: [String: UInt64] = [:]
    public var activations: [String: ModelActivation] = [:]
    public var sessions: [String: ModelSession] = [:]
    public var challenges: [String: ModelChallenge] = [:]
    public var recoveryCases: [String: ModelRecoveryCase] = [:]
    public var requests: [ModelRequestRecord] = []
    public var audit: [ModelAuditEvent] = []
    public init() {}
}

/// Explicit fixture inputs model service-owned guards, time and grant bounds.
/// They are not authentication, entitlement verification or installation authority.
@_spi(Testing) public struct ModelAttempt {
    public var sessionID: String
    public var operation: DeviceOperation
    public var body: Data
    public var pathActivationID: String?
    public var now: UInt64
    public var expectedAccountRevision: UInt64
    public var newActivationID: String?
    public var grantingWindow: ModelGrant?
    public var auditSucceeds: Bool
    public init(sessionID: String, operation: DeviceOperation, body: Data,
                pathActivationID: String? = nil, now: UInt64, expectedAccountRevision: UInt64,
                newActivationID: String? = nil, grantingWindow: ModelGrant? = nil,
                auditSucceeds: Bool = true) {
        self.sessionID = sessionID; self.operation = operation; self.body = body
        self.pathActivationID = pathActivationID; self.now = now
        self.expectedAccountRevision = expectedAccountRevision; self.newActivationID = newActivationID
        self.grantingWindow = grantingWindow; self.auditSucceeds = auditSucceeds
    }
}

/// Atomic value-model transitions only. No persistence, network or native adapter.
public struct SlotLedger {
    public private(set) var snapshot: ModelState
    private let nonceAuthenticationKey: Data
    private let attestationAdapter: (any FixtureAttestationValidating)?
    public init() { snapshot = ModelState(); nonceAuthenticationKey = Data(); attestationAdapter = nil }
    @_spi(Testing) public init(fixtureState: ModelState, nonceAuthenticationKey: Data,
                              attestationAdapter: (any FixtureAttestationValidating)? = nil) {
        snapshot = fixtureState; self.nonceAuthenticationKey = nonceAuthenticationKey
        self.attestationAdapter = attestationAdapter
    }

    @_spi(Testing) public mutating func apply(_ attempt: ModelAttempt) throws -> AllocationResult {
        guard attempt.now <= ActivationIdentity.maximumExactInteger,
              let session = snapshot.sessions[attempt.sessionID], session.id == attempt.sessionID, !session.revoked,
              session.expiresAt > attempt.now, session.expiresAt <= ActivationIdentity.maximumExactInteger,
              session.authenticatedAt <= ActivationIdentity.maximumExactInteger,
              snapshot.accountRevisions[session.accountID] != nil else {
            throw ActivationError.invalidSession
        }
        let request = try DeviceRequest.parse(attempt.body, operation: attempt.operation,
                                               pathActivationID: attempt.pathActivationID)
        let action = request.action
        let terminalOnly = try terminalSession(session, request: request)
        if let prior = snapshot.requests.first(where: {
            $0.accountID == session.accountID && $0.operation == request.operation && $0.requestID == action.requestID
        }) {
            guard !terminalOnly || prior.sessionID == session.id else { throw ActivationError.invalidSession }
            guard prior.actionDigest == action.digest else { throw ActivationError.requestConflict }
            let old = prior.result
            return AllocationResult(outcome: old.outcome == .leased ? .superseded : old.outcome,
                activationID: old.activationID,
                released: old.activationID.flatMap { snapshot.activations[$0]?.released } ?? old.released,
                sequence: old.outcome == .leased ? nil : old.sequence,
                grant: old.outcome == .leased ? nil : old.grant, assurance: old.assurance)
        }
        try Self.invariants(snapshot)
        guard snapshot.accountRevisions[session.accountID] == attempt.expectedAccountRevision else {
            throw ActivationError.stale
        }
        if [.activate, .replace, .deactivate, .rebind].contains(request.operation) {
            guard session.authenticatedAt <= attempt.now, attempt.now - session.authenticatedAt < 600 else {
                throw ActivationError.reauthRequired
            }
        }
        var next = snapshot
        let targetID = action.activationID ?? action.releaseActivationID
        let target = targetID.flatMap { snapshot.activations[$0] }.flatMap { $0.accountID == session.accountID ? $0 : nil }
        var keyDigest: Data?
        var validatedAttestation: FixtureAttestationResult?
        if let proof = request.proof {
            guard let publicKey = action.publicKey ?? target?.publicKey,
                  var challenge = next.challenges[proof.challengeID], !challenge.consumed,
                  challenge.sessionID == session.id, challenge.accountID == session.accountID,
                  challenge.operation == request.operation, challenge.expiresAt > attempt.now,
                  challenge.expiresAt <= ActivationIdentity.maximumExactInteger,
                  challenge.expiresAt - attempt.now <= 300,
                  nonceAuthenticationKey.count >= 32 else { throw ActivationError.proofRefused }
            let hash: Data
            do { hash = try ActivationIdentity.publicKeyDigest(publicKey) }
            catch { throw ActivationError.proofRefused }
            guard challenge.keyDigest == hash else { throw ActivationError.proofRefused }
            let material = try ActivationIdentity.identifierBytes(challenge.id)
                + ActivationIdentity.identifierBytes(session.accountID) + Data([request.operation.rawValue]) + proof.nonce
            guard challenge.id == proof.challengeID,
                  HMAC<SHA256>.isValidAuthenticationCode(challenge.nonceMAC, authenticating: material,
                                                        using: SymmetricKey(data: nonceAuthenticationKey)) else {
                throw ActivationError.proofRefused
            }
            let context = PossessionContext(accountID: session.accountID, activationID: action.activationID,
                operation: request.operation, publicKey: publicKey, nonce: proof.nonce, expiresAt: challenge.expiresAt)
            try PossessionProof.verify(actionBytes: action.bytes, signature: proof.signature, context: context, now: attempt.now)
            if request.operation == .recoveryPossession {
                guard let target, !target.released, target.slot != nil,
                      let id = action.caseID, let recovery = next.recoveryCases[id],
                      recovery.id == id, recovery.accountID == session.accountID,
                      recovery.digest == action.caseDigest, challenge.recoveryCaseID == id,
                      challenge.recoveryCaseDigest == action.caseDigest else { throw ActivationError.proofRefused }
            }
            validatedAttestation = try AttestationBinding.validate(proof,
                message: PossessionProof.message(actionBytes: action.bytes, context: context),
                existing: target?.attestation, operation: request.operation, adapter: attestationAdapter)
            challenge.consumed = true; next.challenges[challenge.id] = challenge; keyDigest = hash
        }
        let assurance: KeyAssurance = validatedAttestation == nil ? .secureStorageFallback : .fixtureAttested
        var outcome: AllocationOutcome = .notFound
        var resultID = target?.id
        var resultSequence: UInt64?
        var resultGrant: ModelGrant?
        var accountChanged = false
        switch request.operation {
        case .activate, .replace:
            guard let publicKey = action.publicKey, let name = action.displayName else { throw ActivationError.invalidRequest }
            if let existing = next.activations.values.first(where: {
                $0.accountID == session.accountID && $0.publicKey == publicKey && $0.slot != nil
            }) {
                outcome = .reused; resultID = existing.id
                next.sessions[session.id]?.activationID = existing.id
            } else {
                let slot: Int?
                if request.operation == .replace {
                    if let target {
                        if target.released || target.revision != action.expectedRevision { outcome = .stale; slot = nil }
                        else { slot = target.slot }
                    } else { slot = nil }
                } else {
                    let occupied = Set(next.activations.values.filter { $0.accountID == session.accountID }.compactMap(\.slot))
                    slot = (1...5).first(where: { !occupied.contains($0) })
                    if slot == nil { outcome = .limitReached }
                }
                if let slot {
                    guard let id = attempt.newActivationID, next.activations[id] == nil else { throw ActivationError.invalidRequest }
                    _ = try ActivationIdentity.identifierBytes(id)
                    guard id != String(repeating: "0", count: 32) else { throw ActivationError.invalidRequest }
                    let priorGeneration = next.activations.values.filter {
                        $0.accountID == session.accountID && $0.publicKey == publicKey
                    }.map(\.generation).max() ?? 0
                    if request.operation == .replace, var old = target {
                        old.released = true; old.slot = nil; old.revision = try Self.increment(old.revision)
                        next.activations[old.id] = old
                    }
                    var created = ModelActivation(); created.id = id; created.accountID = session.accountID
                    created.publicKey = publicKey; created.displayName = name; created.slot = slot
                    created.generation = try Self.increment(priorGeneration); created.attestation = validatedAttestation
                    next.activations[id] = created; next.sessions[session.id]?.activationID = id
                    resultID = id; accountChanged = true
                    outcome = request.operation == .replace ? .replaced : .activated
                }
            }
        case .deactivate:
            if var target {
                if target.released { outcome = .alreadyReleased }
                else if target.revision != action.expectedRevision { outcome = .stale }
                else {
                    target.released = true; target.slot = nil; target.revision = try Self.increment(target.revision)
                    next.activations[target.id] = target; accountChanged = true; outcome = .released
                }
            }
        case .rename, .rebind:
            if var target {
                if target.released { outcome = .notActive }
                else if target.revision != action.expectedRevision { outcome = .stale }
                else {
                    if request.operation == .rename {
                        guard let name = action.displayName else { throw ActivationError.invalidRequest }
                        target.displayName = name; outcome = .renamed
                    } else {
                        guard let validatedAttestation else { throw ActivationError.proofRefused }
                        target.attestation = validatedAttestation; outcome = .rebound
                    }
                    target.revision = try Self.increment(target.revision)
                    next.activations[target.id] = target; accountChanged = true
                }
            }
        case .refresh:
            guard var target else { throw ActivationError.proofRefused }
            target.sequence = try Self.increment(target.sequence); resultSequence = target.sequence
            if let validatedAttestation { target.attestation = validatedAttestation }
            if target.released {
                outcome = .revokedLease
                resultGrant = ModelGrant(issuedAt: attempt.now, permittedUntil: attempt.now, hardEnd: attempt.now)
            } else {
                outcome = .leased; target.lastRefreshAt = attempt.now
                let grant = attempt.grantingWindow ?? ModelGrant(issuedAt: attempt.now, permittedUntil: attempt.now, hardEnd: attempt.now)
                guard grant.issuedAt == attempt.now, grant.issuedAt <= grant.permittedUntil,
                      grant.permittedUntil <= grant.hardEnd, grant.hardEnd <= ActivationIdentity.maximumExactInteger,
                      grant.permittedUntil > grant.issuedAt || grant.hardEnd == grant.issuedAt else {
                    throw ActivationError.invalidRequest
                }
                resultGrant = grant
                if grant.permittedUntil > grant.issuedAt {
                    target.lastGrant = grant
                    target.maxGrantPermittedUntil = max(target.maxGrantPermittedUntil ?? 0, grant.permittedUntil)
                }
            }
            next.activations[target.id] = target
        case .recoveryPossession:
            guard let id = action.caseID, let target else { throw ActivationError.proofRefused }
            next.recoveryCases[id]?.possessionActivationID = target.id; outcome = .possessionRecorded
        }
        if accountChanged {
            guard let revision = next.accountRevisions[session.accountID] else { throw ActivationError.invalidRequest }
            next.accountRevisions[session.accountID] = try Self.increment(revision)
        }
        let result = AllocationResult(outcome: outcome, activationID: resultID,
            released: resultID.flatMap { next.activations[$0]?.released } ?? false,
            sequence: resultSequence, grant: resultGrant, assurance: assurance)
        next.requests.append(ModelRequestRecord(sessionID: session.id, accountID: session.accountID,
            operation: request.operation, requestID: action.requestID, actionDigest: action.digest, result: result))
        guard attempt.auditSucceeds else { throw ActivationError.auditFailed }
        next.audit.append(ModelAuditEvent(sessionID: session.id, serviceTime: attempt.now,
            accountID: session.accountID, activationID: resultID, requestID: action.requestID,
            outcome: outcome, keyDigest: keyDigest))
        try Self.invariants(next)
        snapshot = next
        return result
    }

    private func terminalSession(_ session: ModelSession, request: DeviceRequest) throws -> Bool {
        guard session.id != "", let id = session.activationID else { return false }
        guard let bound = snapshot.activations[id], bound.accountID == session.accountID else { throw ActivationError.invalidSession }
        if bound.released {
            guard request.operation == .refresh, request.action.activationID == id else { throw ActivationError.invalidSession }
            return true
        }
        return false
    }
    private static func increment(_ value: UInt64) throws -> UInt64 {
        guard value < ActivationIdentity.maximumExactInteger else { throw ActivationError.invalidRequest }
        return value + 1
    }
    private static func invariants(_ state: ModelState) throws {
        var slots: [String: Set<Int>] = [:]; var keys: [String: Set<Data>] = [:]
        for (account, revision) in state.accountRevisions {
            _ = try ActivationIdentity.identifierBytes(account)
            guard (1...ActivationIdentity.maximumExactInteger).contains(revision),
                  let entitlement = state.entitlementRevisions[account],
                  (1...ActivationIdentity.maximumExactInteger).contains(entitlement) else { throw ActivationError.invalidRequest }
        }
        for (id, row) in state.activations {
            _ = try ActivationIdentity.identifierBytes(id)
            _ = try ActivationIdentity.publicKeyDigest(row.publicKey)
            guard row.id == id, id != String(repeating: "0", count: 32),
                  state.accountRevisions[row.accountID] != nil, row.released == (row.slot == nil),
                  (1...ActivationIdentity.maximumExactInteger).contains(row.revision),
                  (1...ActivationIdentity.maximumExactInteger).contains(row.generation),
                  row.sequence <= ActivationIdentity.maximumExactInteger else { throw ActivationError.invalidRequest }
            if let slot = row.slot {
                guard (1...5).contains(slot), slots[row.accountID, default: []].insert(slot).inserted,
                      keys[row.accountID, default: []].insert(row.publicKey).inserted else { throw ActivationError.invalidRequest }
            }
            if let maximum = row.maxGrantPermittedUntil {
                guard maximum <= ActivationIdentity.maximumExactInteger else { throw ActivationError.invalidRequest }
            }
            if let last = row.lastGrant {
                guard last.issuedAt < last.permittedUntil, last.permittedUntil <= last.hardEnd,
                      last.hardEnd <= ActivationIdentity.maximumExactInteger,
                      let maximum = row.maxGrantPermittedUntil, maximum >= last.permittedUntil,
                      maximum <= ActivationIdentity.maximumExactInteger else { throw ActivationError.invalidRequest }
            }
        }
    }
}
