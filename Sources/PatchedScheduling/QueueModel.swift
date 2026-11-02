public struct QueueEntry: Equatable, Sendable {
    public let id: String
    public let target: String
    public let release: ReleaseIdentity
    public init(id: String, target: String, release: ReleaseIdentity) {
        self.id = id
        self.target = target
        self.release = release
    }
}

/// Created only by a successful queue transition. Sequence state survives snapshots.
public struct QueueAttempt: Equatable, Sendable {
    public let entryID: String
    public let sequence: UInt64
    private let principal: SchedulingPrincipal
    private let queueID: String
    init(entryID: String, sequence: UInt64, principal: SchedulingPrincipal, queueID: String) {
        self.entryID = entryID
        self.sequence = sequence
        self.principal = principal
        self.queueID = queueID
    }
}
public enum QueueState: Equatable, Sendable {
    case pending, running(QueueAttempt), recovering(QueueAttempt), completed, restored, attention
}
public enum QueueStart: Equatable, Sendable {
    case started(QueueAttempt), deferred(ScheduleDeferral), rejected, stopped
}
public enum FailureScope: Sendable { case isolated, shared }
public enum RecoveryEvidence: Sendable { case verifiedIsolatedRollback, uncertain, sharedFailure }

/// Serial, principal-bound decision state, with no OS adapter or mutation authority.
/// A future owner must persist atomically before executing any corresponding action.
/// Snapshots are typed in-memory values, not a durable or trusted wire format.
public struct QueueModel: Sendable {
    public struct Snapshot: Sendable {
        fileprivate let queueID: String
        fileprivate let principal: SchedulingPrincipal
        fileprivate let entries: [QueueEntry]
        fileprivate let states: [String: QueueState]
        fileprivate let requestIDs: Set<String>
        fileprivate let sequence: UInt64
        fileprivate let sharedBarrier: Bool
    }

    public let principal: SchedulingPrincipal
    public let queueID: String
    public private(set) var entries: [QueueEntry] = []
    private var states: [String: QueueState] = [:]
    private var requestIDs: Set<String> = []
    private var sequence: UInt64 = 0
    private var sharedBarrier = false

    public var snapshot: Snapshot {
        Snapshot(queueID: queueID, principal: principal, entries: entries, states: states,
                 requestIDs: requestIDs, sequence: sequence, sharedBarrier: sharedBarrier)
    }

    /// The owner supplies a stable, distinct identity for each logical queue lifetime.
    public init(principal: SchedulingPrincipal, queueID: String) {
        self.principal = principal
        self.queueID = queueID
    }

    /// An interrupted running operation is uncertain, so it must recover before
    /// any further start. Completed/restored/attention states retain their meaning.
    public init(restoring snapshot: Snapshot) {
        queueID = snapshot.queueID
        principal = snapshot.principal
        entries = snapshot.entries
        states = snapshot.states.mapValues { state in
            if case .running(let attempt) = state { return .recovering(attempt) }
            return state
        }
        requestIDs = snapshot.requestIDs
        sequence = snapshot.sequence
        sharedBarrier = snapshot.sharedBarrier
    }

    public func state(of id: String) -> QueueState? { states[id] }

    public mutating func enqueue(_ entry: QueueEntry, principal: SchedulingPrincipal) -> Bool {
        guard owns(principal), !entry.id.isEmpty, !entry.target.isEmpty, entry.release.isComplete,
              states[entry.id] == nil,
              !entries.contains(where: { $0.target == entry.target && $0.release == entry.release }) else {
            return false
        }
        entries.append(entry)
        states[entry.id] = .pending
        return true
    }

    public mutating func start(id: String, requestID: String, principal: SchedulingPrincipal,
                               kind: StartKind, policy: SchedulePolicy,
                               conditions: StartConditions) -> QueueStart {
        guard owns(principal), policy.principal == self.principal,
              conditions.principal == self.principal, !requestID.isEmpty,
              !requestIDs.contains(requestID), states[id] == .pending,
              let entry = entries.first(where: { $0.id == id }),
              conditions.target == entry.target, conditions.release == .verified(entry.release) else { return .rejected }
        guard !sharedBarrier, !hasActiveOperation else { return .stopped }
        switch policy.decision(for: kind, conditions: conditions) {
        case .deferred(let reason): return .deferred(reason)
        case .eligible: break
        }
        let next = sequence.addingReportingOverflow(1)
        guard !next.overflow else { return .stopped }
        sequence = next.partialValue
        let attempt = QueueAttempt(entryID: id, sequence: sequence, principal: self.principal, queueID: queueID)
        requestIDs.insert(requestID)
        states[id] = .running(attempt)
        return .started(attempt)
    }

    /// Completion and recovery deliberately take no changing start-policy input.
    public mutating func complete(_ attempt: QueueAttempt, principal: SchedulingPrincipal) -> Bool {
        guard owns(principal), states[attempt.entryID] == .running(attempt) else { return false }
        states[attempt.entryID] = .completed
        return true
    }

    public mutating func fail(_ attempt: QueueAttempt, principal: SchedulingPrincipal,
                              scope: FailureScope) -> Bool {
        guard owns(principal), states[attempt.entryID] == .running(attempt) else { return false }
        if scope == .shared { sharedBarrier = true }
        states[attempt.entryID] = .recovering(attempt)
        return true
    }

    public mutating func recover(_ attempt: QueueAttempt, principal: SchedulingPrincipal,
                                 evidence: RecoveryEvidence) -> Bool {
        guard owns(principal), states[attempt.entryID] == .recovering(attempt) else { return false }
        switch evidence {
        case .verifiedIsolatedRollback:
            // A rollback claim cannot erase a previously observed shared fault.
            states[attempt.entryID] = sharedBarrier ? .attention : .restored
        case .uncertain, .sharedFailure:
            sharedBarrier = true
            states[attempt.entryID] = .attention
        }
        return true
    }

    private func owns(_ principal: SchedulingPrincipal) -> Bool {
        !self.principal.value.isEmpty && !queueID.isEmpty && principal == self.principal
    }

    private var hasActiveOperation: Bool {
        states.values.contains { state in
            switch state {
            case .running, .recovering: return true
            default: return false
            }
        }
    }
}
