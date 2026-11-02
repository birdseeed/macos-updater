import Foundation

public struct ActivityStoredBytes: Equatable {
    public let revision: UInt64
    public let bytes: Data
    public init(revision: UInt64, bytes: Data) { self.revision = revision; self.bytes = bytes }
}
public enum ActivityWriteResult { case committed, knownNotCommitted, uncertain }
@MainActor public protocol ActivityStore: AnyObject {
    func read() throws -> ActivityStoredBytes?
    func compareAndSwap(expected: ActivityStoredBytes?, replacement: ActivityStoredBytes) throws -> ActivityWriteResult
}
public struct ActivitySnapshot: Equatable, Sendable {
    public let available: Bool
    public let revision: UInt64?
    public let events: [ActivityEvent]
    public let ageAvailable: Bool
    public init(available: Bool, revision: UInt64? = nil, events: [ActivityEvent] = [], ageAvailable: Bool = false) {
        self.available = available; self.revision = revision; self.events = events; self.ageAvailable = ageAvailable
    }
}
public struct ActivitySyntheticReadback: Equatable, Sendable {
    public let eventID: String
    public let attemptID: String
    public let transactionID: String
    public let afterVersion: String?
    public let afterBuild: String?
    public init(eventID: String, attemptID: String, transactionID: String, afterVersion: String?, afterBuild: String?) {
        self.eventID = eventID; self.attemptID = attemptID; self.transactionID = transactionID
        self.afterVersion = afterVersion; self.afterBuild = afterBuild
    }
}
@MainActor public final class ActivityHistoryOwner {
    public static let retentionSeconds: UInt64 = 30 * 24 * 60 * 60
    private let store: (any ActivityStore)?
    private let principal: String
    private let storeID: String
    private var retained: ActivityStoredBytes?
    private var state = ActivitySnapshot(available: false)
    private var busy = false
    // Ordinary composition is permanently unavailable, including after implementation.
    public init() { store = nil; principal = ""; storeID = "" }
    @_spi(Testing) public init(store: any ActivityStore, principal: String, storeID: String) {
        self.store = store; self.principal = principal; self.storeID = storeID
    }
    // Only the explicit OS-account factory binds ordinary native storage. The owner stays private there.
    init(authenticatedNativeStore: FileActivityStore, principal: String, storeID: String) {
        store = authenticatedNativeStore; self.principal = principal; self.storeID = storeID
    }
    public var snapshot: ActivitySnapshot { state }
    public func reload(now: UInt64?) throws {
        try enter(); defer { busy = false }
        do {
            guard let stored = try store?.read() else { throw ActivityRefusal.unavailable }
            let record = try validated(stored)
            retained = stored
            publish(record, now: now)
        } catch { invalidate(); throw error }
    }
    @_spi(Testing) public func bootstrapFreshFixture() throws { try bootstrapMissing(now: nil) }
    func bootstrapMissing(now: UInt64?) throws {
        try enter(); defer { busy = false }
        guard let store else { throw ActivityRefusal.unavailable }
        guard try store.read() == nil else { throw ActivityRefusal.conflict }
        let record = ActivityRecord(principal: principal, storeID: storeID, revision: 0, events: [])
        try commit(record, expected: nil, now: now)
    }
    @_spi(Testing) public func appendSynthetic(_ event: ActivityEvent, readback: ActivitySyntheticReadback? = nil,
                                              now: UInt64?) throws {
        try enter(); defer { busy = false }
        guard let retained, state.available else { throw ActivityRefusal.unavailable }
        let record = try validated(retained)
        if let previous = record.events.first(where: { $0.eventID == event.eventID }) {
            guard previous == event else { throw ActivityRefusal.conflict }
            // Even replay must still refer to the current exact retained generation.
            guard try store?.read() == retained else { invalidate(); throw ActivityRefusal.conflict }
            return
        }
        guard record.revision < UInt64.max,
              record.events.allSatisfy({ $0.sequence < event.sequence }) else { throw ActivityRefusal.conflict }
        if event.status == .succeeded || event.status == .restored {
            guard let readback, let transaction = event.transactionID,
                  event.afterVersion != nil || event.afterBuild != nil,
                  readback.eventID == event.eventID, readback.attemptID == event.attemptID,
                  readback.transactionID == transaction, readback.afterVersion == event.afterVersion,
                  readback.afterBuild == event.afterBuild else { throw ActivityRefusal.readbackMismatch }
        }
        let selected = selection(record.events, now: now).events
        let next = ActivityRecord(principal: principal, storeID: storeID, revision: record.revision + 1,
                                  events: selected + [event])
        try commit(next, expected: retained, now: now)
    }
    public func selectRetained(now: UInt64?) throws {
        try enter(); defer { busy = false }
        guard let retained, state.available else { throw ActivityRefusal.unavailable }
        let record = try validated(retained)
        let selected = selection(record.events, now: now)
        if selected.events == record.events {
            guard try store?.read() == retained else { invalidate(); throw ActivityRefusal.conflict }
            publish(record, now: now)
            return
        }
        guard record.revision < UInt64.max else { throw ActivityRefusal.conflict }
        try commit(ActivityRecord(principal: principal, storeID: storeID, revision: record.revision + 1,
                                  events: selected.events), expected: retained, now: now)
    }
    private func enter() throws {
        guard store != nil else { throw ActivityRefusal.unavailable }
        guard !busy else { throw ActivityRefusal.reentrant }
        busy = true
    }
    private func invalidate() { retained = nil; state = ActivitySnapshot(available: false) }
    private func validated(_ stored: ActivityStoredBytes) throws -> ActivityRecord {
        let record = try ActivityWire.decode(stored.bytes, principal: principal, storeID: storeID)
        guard record.revision == stored.revision else { throw ActivityRefusal.invalidWire }
        return record
    }
    private func commit(_ record: ActivityRecord, expected: ActivityStoredBytes?, now: UInt64?) throws {
        // Encoding/quota refusal happens before touching the injected store.
        let replacement = ActivityStoredBytes(revision: record.revision, bytes: try ActivityWire.encode(record))
        guard let store else { throw ActivityRefusal.unavailable }
        do {
            switch try store.compareAndSwap(expected: expected, replacement: replacement) {
            case .knownNotCommitted: throw ActivityRefusal.conflict
            case .uncertain: throw ActivityRefusal.uncertain
            case .committed: break
            }
            guard let read = try store.read(), read == replacement else { throw ActivityRefusal.readbackMismatch }
            let confirmed = try validated(read)
            retained = read
            publish(confirmed, now: now)
        } catch { invalidate(); throw error }
    }
    private func publish(_ record: ActivityRecord, now: UInt64?) {
        let ordered = record.events.sorted {
            if $0.observedAt != $1.observedAt {
                return ($0.observedAt ?? UInt64.max) < ($1.observedAt ?? UInt64.max)
            }
            if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
            return $0.eventID < $1.eventID
        }
        state = ActivitySnapshot(available: true, revision: record.revision, events: ordered,
                                 ageAvailable: selection(record.events, now: now).ageAvailable)
    }
    private func selection(_ events: [ActivityEvent], now: UInt64?) -> (events: [ActivityEvent], ageAvailable: Bool) {
        guard let now, events.allSatisfy({ event in
            (event.observedAt.map { $0 <= now } ?? true) && (event.resolvedAt.map { $0 <= now } ?? true)
        }) else { return (events, false) }
        let protectedAttempts = Set(events.filter { unresolved($0) }.map(\.attemptID))
        let ageAvailable = events.allSatisfy { $0.observedAt != nil && (unresolved($0) || $0.resolvedAt != nil) }
        guard ageAvailable else { return (events, false) }
        return (events.filter { event in
            if protectedAttempts.contains(event.attemptID) { return true }
            guard let resolved = event.resolvedAt else { return true }
            return now - resolved < Self.retentionSeconds
        }, true)
    }
    private func unresolved(_ event: ActivityEvent) -> Bool {
        event.resolvedAt == nil || [.queued, .started, .downloaded, .incomplete, .needsRecovery].contains(event.status)
    }
}
