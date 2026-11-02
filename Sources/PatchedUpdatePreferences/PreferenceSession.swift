import Foundation
import PatchedScheduling

public enum PreferenceEditResult: Equatable, Sendable {
    case accepted(revision: UInt64), replayed(revision: UInt64), refused(PreferenceRefusal)
}
public enum PreferenceAvailability: String, Equatable, Sendable { case unknown, skipped, available }
public struct PreferenceProjectionRow: Equatable, Sendable {
    public let id: String
    public let availability: PreferenceAvailability
    public let automaticExcluded: Bool
    public let canUndo: Bool
    public init(id: String, availability: PreferenceAvailability, automaticExcluded: Bool, canUndo: Bool) {
        self.id = id; self.availability = availability; self.automaticExcluded = automaticExcluded; self.canUndo = canUndo
    }
}
public struct PreferenceProjection: Equatable, Sendable {
    public let revision: UInt64?
    public let applications: [PreferenceProjectionRow]
    public let updates: [PreferenceProjectionRow]
    public let settingsExclusionCount: Int
    public let availableCount: Int
    public let skippedCount: Int
    public let unknownCount: Int
    public init(revision: UInt64?, applications: [PreferenceProjectionRow], updates: [PreferenceProjectionRow],
                settingsExclusionCount: Int, availableCount: Int, skippedCount: Int, unknownCount: Int) {
        self.revision = revision; self.applications = applications; self.updates = updates
        self.settingsExclusionCount = settingsExclusionCount; self.availableCount = availableCount
        self.skippedCount = skippedCount; self.unknownCount = unknownCount
    }
}
public struct PreferenceCandidate: Sendable {
    public let id: String
    public let release: ReleaseEvidence
    public init(id: String, release: ReleaseEvidence) { self.id = id; self.release = release }
}
/// One synchronous owner serialises accepted state, CAS, publication and symbolic starts.
/// This has no native start or installation authority. No reusable eligible policy is exposed.
@MainActor public final class PreferenceSession {
    public private(set) var acceptedRevision: UInt64? = nil
    public private(set) var blockedReason: PreferenceRefusal? = .defaultComposition
    private var store: (any PreferenceStore)?
    private var principal = SchedulingPrincipal("")
    private var storeScope = ""
    private var generation = ""
    private var queue: QueueModel?
    private enum AcceptedState: Equatable {
        case legacy(PreferenceRecord)
        case scheduled(SchedulePreferenceRecord)
        case firstRun(FirstRunPreferenceRecord)
        var preferences: PreferenceRecord {
            switch self {
            case .legacy(let value): return value
            case .scheduled(let value): return value.preferences
            case .firstRun(let value): return value.scheduled.preferences
            }
        }
        var schedule: SchedulePreferenceRecord? {
            switch self {
            case .legacy: return nil
            case .scheduled(let value): return value
            case .firstRun(let value): return value.scheduled
            }
        }
        var firstRun: FirstRunPreferenceRecord? {
            if case .firstRun(let value) = self { return value }
            return nil
        }
    }
    private var acceptedState: AcceptedState?
    private var record: PreferenceRecord? { acceptedState?.preferences }
    private var acceptedBytes: Data?
    private var busy = false
    private var fixtureBootstrapAllowed = false
    private let scheduledCheckOwner = ScheduledCheckAttemptOwner()
    private var scheduledCheckSequence: UInt64 = 0
    private var scheduledCheck: ScheduledCheckAttempt?
    private var scheduleClockState: ScheduleClockState = .unavailable
    private var scheduleAwake: KnownSignal = .unknown
    private var scheduleSample: ClockSample?
    // Consumed at begin, or conservatively at explicit reanchor. Never persisted.
    private var scheduleCadenceAnchor: ClockSample?

    // Read-only binding to this existing owner; it performs no store access.
    func matchesInventoryProjectionOwner(principal: SchedulingPrincipal, generation: String) -> Bool {
        store != nil && self.principal.value.utf8.elementsEqual(principal.value.utf8) &&
            self.generation.utf8.elementsEqual(generation.utf8)
    }
    /// Independently read-back setup only; legacy defaults are not accepted choices.
    public var firstRunSetup: FirstRunSetupState? {
        blockedReason == nil ? acceptedState?.firstRun?.setup : nil
    }
    public func saveFirstRunChoices(_ choices: FirstRunChoices, complete: Bool, mutationID: String,
                                    expectedRevision: UInt64, generation: String) -> PreferenceEditResult {
        if let refusal = actionRefusal(generation) { return .refused(refusal) }
        busy = true; defer { busy = false }
        guard let store, let record, let acceptedBytes else { return .refused(blockedReason ?? .missing) }
        guard blockedReason == nil else { return .refused(blockedReason ?? .unavailable) }
        guard validText(mutationID) else { return .refused(.identity) }
        let draft = choices.networkDraft
        guard draft.host.utf8.count <= 254, draft.port.utf8.count <= 6,
              ![draft.host, draft.port].contains(where: { value in
                  value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
              }), !draft.host.contains("@"), !draft.host.contains("://"),
              draft.mode == .manualHTTP || (draft.host.isEmpty && draft.port.isEmpty) else {
            return .refused(.malformed)
        }
        let schedule = acceptedState?.schedule
        let setup = acceptedState?.firstRun
        guard !record.mutations.contains(where: { $0.id == mutationID }),
              !(schedule?.settingsMutations.contains(where: { $0.id == mutationID }) ?? false) else {
            return .refused(.conflict)
        }
        if let retained = setup?.setupMutations.first(where: { $0.id == mutationID }) {
            return retained.choices == choices && retained.complete == complete
                ? .replayed(revision: record.revision) : .refused(.conflict)
        }
        guard expectedRevision == record.revision else { return .refused(.conflict) }
        let next = record.revision.addingReportingOverflow(1)
        guard !next.overflow else { return .refused(.revisionOverflow) }
        guard mutationCount < FirstRunPreferenceRecord.maximumCombinedMutations else { return .refused(.limit) }
        let old = schedule?.settings ?? ScheduleSettings()
        let preferences = PreferenceRecord(principal: record.principal, storeScope: record.storeScope,
            revision: next.partialValue, exclusions: record.exclusions, skips: record.skips, mutations: record.mutations)
        let scheduled = SchedulePreferenceRecord(preferences: preferences,
            settings: ScheduleSettings(dailyChecks: choices.dailyChecks, notifications: choices.notifications,
                                       automaticUpdates: old.automaticUpdates, pause: old.pause),
            settingsMutations: schedule?.settingsMutations ?? [])
        let proposed = FirstRunPreferenceRecord(scheduled: scheduled,
            setup: FirstRunSetupState(failureReports: choices.failureReports,
                                     completed: (setup?.setup.completed ?? false) || complete, networkDraft: draft),
            setupMutations: (setup?.setupMutations ?? []) + [FirstRunSetupMutationReceipt(id: mutationID, choices: choices, complete: complete)])
        do {
            let bytes = try FirstRunPreferenceRecordCodec.encode(proposed)
            return commit(.firstRun(proposed), bytes: bytes, expected: acceptedBytes, store: store)
        } catch let refusal as PreferenceRefusal { return .refused(refusal) }
        catch { return .refused(.malformed) }
    }
    private var mutationCount: Int {
        (record?.mutations.count ?? 0) + (acceptedState?.schedule?.settingsMutations.count ?? 0) +
            (acceptedState?.firstRun?.setupMutations.count ?? 0)
    }
    // All existing edit paths retain the outer setup value and its request history.
    private func commitSchedule(_ schedule: SchedulePreferenceRecord, expected: Data,
                                store: any PreferenceStore) throws -> PreferenceEditResult {
        if let current = acceptedState?.firstRun {
            let proposed = FirstRunPreferenceRecord(scheduled: schedule, setup: current.setup,
                                                    setupMutations: current.setupMutations)
            return commit(.firstRun(proposed), bytes: try FirstRunPreferenceRecordCodec.encode(proposed),
                          expected: expected, store: store)
        }
        return commit(.scheduled(schedule), bytes: try SchedulePreferenceRecordCodec.encode(schedule),
                      expected: expected, store: store)
    }
    /// Last independently read-back choices, hidden while a storage error is latched.
    public var scheduleSettings: ScheduleSettings? {
        blockedReason == nil ? acceptedState?.schedule?.settings : nil
    }
    public func migrateScheduleSettings(expectedRevision: UInt64, generation: String) -> PreferenceEditResult {
        if let refusal = actionRefusal(generation) { return .refused(refusal) }
        busy = true; defer { busy = false }
        guard let store, let record, let acceptedBytes else { return .refused(blockedReason ?? .missing) }
        guard blockedReason == nil else { return .refused(blockedReason ?? .unavailable) }
        guard expectedRevision == record.revision else { return .refused(.conflict) }
        if acceptedState?.schedule != nil { return .replayed(revision: record.revision) }
        do {
            let proposal = try SchedulePreferenceRecordCodec.proposeV1Migration(acceptedBytes,
                principal: principal, storeScope: storeScope)
            guard proposal.originalV1Bytes == acceptedBytes, proposal.record.preferences == record else {
                return block(.malformed)
            }
            return commit(.scheduled(proposal.record), bytes: proposal.proposedV2Bytes,
                          expected: acceptedBytes, store: store)
        } catch let refusal as PreferenceRefusal { return .refused(refusal) }
        catch { return .refused(.malformed) }
    }
    public func editScheduleSettings(_ change: ScheduleSettingsChange, mutationID: String,
                                     expectedRevision: UInt64, generation: String) -> PreferenceEditResult {
        if let refusal = actionRefusal(generation) { return .refused(refusal) }
        busy = true; defer { busy = false }
        guard let store, let record, let acceptedBytes else { return .refused(blockedReason ?? .missing) }
        guard blockedReason == nil else { return .refused(blockedReason ?? .unavailable) }
        guard let schedule = acceptedState?.schedule else { return .refused(.unimplemented) }
        guard validText(mutationID) else { return .refused(.identity) }
        // A retained declaration is never authority to enable unattended execution.
        if case .automaticUpdates(true) = change { return .refused(.unimplemented) }
        guard !record.mutations.contains(where: { $0.id == mutationID }),
              !(acceptedState?.firstRun?.setupMutations.contains(where: { $0.id == mutationID }) ?? false) else {
            return .refused(.conflict)
        }
        if let retained = schedule.settingsMutations.first(where: { $0.id == mutationID }) {
            return retained.change == change ? .replayed(revision: record.revision) : .refused(.conflict)
        }
        guard expectedRevision == record.revision else { return .refused(.conflict) }
        let next = record.revision.addingReportingOverflow(1)
        guard !next.overflow else { return .refused(.revisionOverflow) }
        guard mutationCount < SchedulePreferenceRecord.maximumCombinedMutations else {
            return .refused(.limit)
        }
        let old = schedule.settings
        let settings: ScheduleSettings
        switch change {
        case .dailyChecks(let value):
            settings = ScheduleSettings(dailyChecks: value, notifications: old.notifications,
                automaticUpdates: old.automaticUpdates, pause: old.pause)
        case .notifications(let value):
            settings = ScheduleSettings(dailyChecks: old.dailyChecks, notifications: value,
                automaticUpdates: old.automaticUpdates, pause: old.pause)
        case .automaticUpdates(let value):
            settings = ScheduleSettings(dailyChecks: old.dailyChecks, notifications: old.notifications,
                automaticUpdates: value, pause: old.pause)
        case .pause(let value):
            settings = ScheduleSettings(dailyChecks: old.dailyChecks, notifications: old.notifications,
                automaticUpdates: old.automaticUpdates, pause: value)
        }
        let preferences = PreferenceRecord(principal: record.principal, storeScope: record.storeScope,
            revision: next.partialValue, exclusions: record.exclusions, skips: record.skips, mutations: record.mutations)
        let proposed = SchedulePreferenceRecord(preferences: preferences, settings: settings,
            settingsMutations: schedule.settingsMutations + [ScheduleSettingsMutationReceipt(id: mutationID, change: change)])
        do {
            return try commitSchedule(proposed, expected: acceptedBytes, store: store)
        } catch let refusal as PreferenceRefusal { return .refused(refusal) }
        catch { return .refused(.malformed) }
    }
    /// Cached injected-model observations only; reading this property performs no I/O.
    public var scheduleRuntimeSnapshot: ScheduleRuntimeSnapshot {
        let timing: SchedulePauseTiming
        if blockedReason == nil, acceptedState?.schedule != nil,
           scheduleClockState == .usable, scheduleAwake == .yes, let sample = scheduleSample {
            if let pause = acceptedState?.schedule?.settings.pause {
                timing = sample.utc < pause.resumeUTC ? .beforeDeadline : .atOrAfterDeadline
            } else { timing = .notPaused }
        } else { timing = .unavailable }
        return ScheduleRuntimeSnapshot(clockState: scheduleClockState, awake: scheduleAwake,
            checkDue: scheduledCheckIsDue, checkInFlight: scheduledCheck != nil, pauseTiming: timing)
    }
    /// Accepts supplied model events, never reads a native clock or starts queue work.
    public func observeSchedule(_ event: ScheduleRuntimeEvent, generation: String) -> Bool {
        guard scheduleCallerAllowed(generation), scheduleClockState != .stopped else { return false }
        busy = true; defer { busy = false }
        switch event {
        case .shutdown:
            scheduledCheck = nil; scheduleAwake = .unknown; scheduleClockState = .stopped
        case .sleep:
            scheduledCheck = nil; scheduleAwake = .no
        case .clockInvalidated:
            invalidateScheduleClock()
        case .observation(let sample, let awake):
            guard scheduleClockState != .invalid else { return false }
            guard usableScheduleSample(sample), scheduleSample.map({ earlier in
                sample.boot.utf8.elementsEqual(earlier.boot.utf8) && sample.isConsistent(with: earlier)
            }) ?? true else {
                invalidateScheduleClock(); return false
            }
            scheduleSample = sample; scheduleClockState = .usable; scheduleAwake = awake
            if awake != .yes { scheduledCheck = nil }
        }
        return true
    }
    /// Explicit recovery defers the next opportunity for a complete consistent day.
    public func reanchorScheduleClock(_ sample: ClockSample, awake: KnownSignal, generation: String) -> Bool {
        guard scheduleCallerAllowed(generation), scheduleClockState != .stopped else { return false }
        busy = true; defer { busy = false }
        guard usableScheduleSample(sample) else { invalidateScheduleClock(); return false }
        scheduledCheck = nil; scheduleSample = sample; scheduleCadenceAnchor = sample
        scheduleClockState = .usable; scheduleAwake = awake
        return true
    }
    public func beginScheduledCheck(generation: String) -> ScheduledCheckAttempt? {
        guard scheduleCallerAllowed(generation), scheduledCheckIsDue,
              let revision = acceptedRevision, let sample = scheduleSample else { return nil }
        busy = true; defer { busy = false }
        guard validateCurrentAcceptedBytes() else { return nil }
        let next = scheduledCheckSequence.addingReportingOverflow(1)
        guard !next.overflow else { return nil }
        let attempt = ScheduledCheckAttempt(owner: scheduledCheckOwner, sequence: next.partialValue,
            revision: revision, generation: self.generation)
        scheduledCheckSequence = next.partialValue; scheduledCheck = attempt
        scheduleCadenceAnchor = sample
        return attempt
    }
    public func completeScheduledCheck(_ attempt: ScheduledCheckAttempt, generation: String) -> Bool {
        // Check the exact active capability before any callback-time storage read.
        guard scheduleCallerAllowed(generation), let active = scheduledCheck, active == attempt,
              attempt.owner === scheduledCheckOwner, attempt.revision == acceptedRevision,
              attempt.generation.utf8.elementsEqual(self.generation.utf8), blockedReason == nil else { return false }
        busy = true; defer { busy = false }
        guard validateCurrentAcceptedBytes() else { return false }
        scheduledCheck = nil
        return true
    }
    /// Cancellation only discards this owner's pending read-only callback; cadence stays consumed.
    public func cancelScheduledCheck(generation: String) -> Bool {
        guard scheduleCallerAllowed(generation), scheduledCheck != nil else { return false }
        busy = true; defer { busy = false }
        scheduledCheck = nil
        return true
    }
    private func scheduleCallerAllowed(_ caller: String) -> Bool {
        actionRefusal(caller) == nil && self.generation.utf8.elementsEqual(caller.utf8) &&
            acceptedState?.schedule != nil
    }
    private var scheduledCheckIsDue: Bool {
        guard blockedReason == nil, acceptedState?.schedule?.settings.dailyChecks == true,
              scheduleClockState == .usable, scheduleAwake == .yes,
              scheduledCheck == nil, let sample = scheduleSample else { return false }
        guard let anchor = scheduleCadenceAnchor else { return true }
        guard sample.boot.utf8.elementsEqual(anchor.boot.utf8), sample.isConsistent(with: anchor) else { return false }
        let elapsed = sample.monotonic.subtractingReportingOverflow(anchor.monotonic)
        return !elapsed.overflow && elapsed.partialValue >= 86_400
    }
    private func usableScheduleSample(_ sample: ClockSample) -> Bool {
        sample.isUsable && validText(sample.boot)
    }
    private func invalidateScheduleClock() {
        scheduledCheck = nil; scheduleClockState = .invalid; scheduleAwake = .unknown
    }
    public init() {}
    @_spi(Testing) public init(store: any PreferenceStore, principal: SchedulingPrincipal,
                               storeScope: String, generation: String, queueID: String) {
        configure(store: store, principal: principal, storeScope: storeScope, generation: generation, queueID: queueID)
        fixtureBootstrapAllowed = true
    }
    // Module-only composition: native construction never needs the public Testing injection seam.
    static func bound(store: any PreferenceStore, principal: SchedulingPrincipal,
                      storeScope: String, generation: String, queueID: String) -> PreferenceSession {
        let session = PreferenceSession()
        session.configure(store: store, principal: principal, storeScope: storeScope, generation: generation, queueID: queueID)
        return session
    }
    private func configure(store: any PreferenceStore, principal: SchedulingPrincipal,
                           storeScope: String, generation: String, queueID: String) {
        self.store = store; self.principal = principal; self.storeScope = storeScope; self.generation = generation
        queue = QueueModel(principal: principal, queueID: queueID)
        blockedReason = .missing
    }
    /// Only explicit fresh fixture bootstrap may create missing state. Existing load never resets it.
    public func bootstrapFreshFixture(generation: String) -> PreferenceEditResult {
        if let refusal = actionRefusal(generation) { return .refused(refusal) }
        guard fixtureBootstrapAllowed else { return .refused(.defaultComposition) }
        return bootstrapMissing(generation: generation)
    }
    // Shared bootstrap algorithm, also reached by the physically bound context's explicit createFresh.
    func bootstrapMissing(generation: String) -> PreferenceEditResult {
        if let refusal = actionRefusal(generation) { return .refused(refusal) }
        busy = true; defer { busy = false }
        guard let store else { return .refused(.defaultComposition) }
        guard record == nil else { return .refused(.conflict) }
        switch store.read(maximumBytes: PreferenceRecord.maximumBytes) {
        case .bytes: return .refused(.conflict)
        case .unavailable: return block(.unavailable)
        case .missing: break
        }
        let fresh = PreferenceRecord(principal: principal, storeScope: storeScope, revision: 0)
        do {
            let bytes = try PreferenceRecordCodec.encode(fresh)
            _ = try PreferenceRecordCodec.decode(bytes, principal: principal, storeScope: storeScope)
            return commit(.legacy(fresh), bytes: bytes, expected: nil, store: store)
        } catch { return block(.malformed) }
    }
    public func reload(generation: String) -> PreferenceEditResult {
        if let refusal = actionRefusal(generation) { return .refused(refusal) }
        busy = true; defer { busy = false }
        guard let store else { return .refused(.defaultComposition) }
        switch store.read(maximumBytes: PreferenceRecord.maximumBytes) {
        case .missing: return block(.missing)
        case .unavailable: return block(.unavailable)
        case .bytes(let bytes):
            do {
                let loaded = try decodeAcceptedState(bytes)
                publish(loaded, bytes: bytes)
                return .accepted(revision: loaded.preferences.revision)
            } catch { return block(.malformed) }
        }
    }
    public func edit(_ change: PreferenceChange, mutationID: String, expectedRevision: UInt64,
                     generation: String) -> PreferenceEditResult {
        if let refusal = actionRefusal(generation) { return .refused(refusal) }
        busy = true; defer { busy = false }
        guard let store, let record, let acceptedBytes else { return .refused(blockedReason ?? .missing) }
        guard blockedReason == nil else { return .refused(blockedReason ?? .unavailable) }
        guard validText(mutationID), validChange(change) else { return .refused(.identity) }
        do {
            let operation = try operationBytes(change)
            let schedule = acceptedState?.schedule
            guard !(schedule?.settingsMutations.contains(where: { $0.id == mutationID }) ?? false),
                  !(acceptedState?.firstRun?.setupMutations.contains(where: { $0.id == mutationID }) ?? false) else {
                return .refused(.conflict)
            }
            if let retained = record.mutations.first(where: { $0.id == mutationID }) {
                return retained.operation == operation ? .replayed(revision: record.revision) : .refused(.conflict)
            }
            guard expectedRevision == record.revision else { return .refused(.conflict) }
            let next = record.revision.addingReportingOverflow(1)
            guard !next.overflow else { return .refused(.revisionOverflow) }
            guard mutationCount < PreferenceRecord.maximumMutations else {
                return .refused(.limit)
            }
            var exclusions = record.exclusions
            var skips = record.skips
            switch change {
            case .exclusion(let key, let excluded):
                if excluded { exclusions.insert(key) } else { exclusions.remove(key) }
            case .skip(let release): skips.insert(release)
            case .undo(let release): skips.remove(release)
            }
            guard exclusions.count <= PreferenceRecord.maximumExclusions,
                  skips.count <= PreferenceRecord.maximumSkips else { return .refused(.limit) }
            let proposed = PreferenceRecord(principal: principal, storeScope: storeScope, revision: next.partialValue,
                exclusions: exclusions, skips: skips,
                mutations: record.mutations + [PreferenceMutationReceipt(id: mutationID, operation: operation)])
            if let schedule {
                let envelope = SchedulePreferenceRecord(preferences: proposed, settings: schedule.settings,
                    settingsMutations: schedule.settingsMutations)
                return try commitSchedule(envelope, expected: acceptedBytes, store: store)
            }
            let bytes = try PreferenceRecordCodec.encode(proposed)
            return commit(.legacy(proposed), bytes: bytes, expected: acceptedBytes, store: store)
        } catch let refusal as PreferenceRefusal { return .refused(refusal) }
        catch { return .refused(.malformed) }
    }
    public func projection(_ candidates: [PreferenceCandidate]) -> PreferenceProjection {
        let rows = candidates.map { candidate -> PreferenceProjectionRow in
            guard let record, case .verified(let release) = candidate.release else {
                return PreferenceProjectionRow(id: candidate.id, availability: .unknown, automaticExcluded: false, canUndo: false)
            }
            let policy = policy(for: release, record: record, automaticEnabled: false, pause: nil)
            let conditions = StartConditions(principal: principal, target: "synthetic-projection", release: candidate.release,
                route: .unattended, eligibility: .eligible, targetClosed: .yes,
                clock: ClockSample(utc: 0, monotonic: 0, boot: "synthetic-projection"))
            let availability: PreferenceAvailability
            switch policy.decision(for: .manual, conditions: conditions) {
            case .eligible: availability = .available
            case .deferred(.skipped): availability = .skipped
            default: availability = .unknown
            }
            return PreferenceProjectionRow(id: candidate.id, availability: availability,
                automaticExcluded: record.exclusions.contains(PreferenceAppKey(release)),
                canUndo: availability == .skipped)
        }
        return PreferenceProjection(revision: acceptedRevision, applications: rows, updates: rows,
            settingsExclusionCount: record?.exclusions.count ?? 0,
            availableCount: rows.filter { $0.availability == .available }.count,
            skippedCount: rows.filter { $0.availability == .skipped }.count,
            unknownCount: rows.filter { $0.availability == .unknown }.count)
    }
    public func enqueue(_ entry: QueueEntry, principal: SchedulingPrincipal, generation: String) -> Bool {
        guard actionRefusal(generation) == nil, principal == self.principal,
              validRelease(entry.release), validText(entry.id), validText(entry.target) else { return false }
        busy = true; defer { busy = false }
        return queue?.enqueue(entry, principal: principal) ?? false
    }
    public func start(id: String, requestID: String, principal: SchedulingPrincipal, generation: String,
                      kind: StartKind, automaticEnabled: Bool, pause: AutomaticPause?, conditions: StartConditions) -> QueueStart {
        guard actionRefusal(generation) == nil, principal == self.principal, blockedReason == nil,
              let record, store != nil, acceptedBytes != nil else { return .rejected }
        busy = true; defer { busy = false }
        // A bounded action-time read and exact-byte check precede the synchronous handoff.
        // Once observed, drift stays latched even if an external writer restores old bytes.
        guard validateCurrentAcceptedBytes() else { return .rejected }
        if acceptedState?.schedule != nil {
            switch kind {
            case .automatic, .loginWindow: return .rejected
            case .manual, .updateAll: break
            }
        }
        guard case .verified(let release) = conditions.release else { return .rejected }
        let current = policy(for: release, record: record, automaticEnabled: automaticEnabled, pause: pause)
        return queue?.start(id: id, requestID: requestID, principal: principal, kind: kind,
                            policy: current, conditions: conditions) ?? .rejected
    }
    public func state(of id: String) -> QueueState? { queue?.state(of: id) }
    public func complete(_ attempt: QueueAttempt, principal: SchedulingPrincipal) -> Bool {
        guard !busy else { return false }
        busy = true; defer { busy = false }
        return queue?.complete(attempt, principal: principal) ?? false
    }
    public func fail(_ attempt: QueueAttempt, principal: SchedulingPrincipal, scope: FailureScope) -> Bool {
        guard !busy else { return false }
        busy = true; defer { busy = false }
        return queue?.fail(attempt, principal: principal, scope: scope) ?? false
    }
    public func recover(_ attempt: QueueAttempt, principal: SchedulingPrincipal, evidence: RecoveryEvidence) -> Bool {
        guard !busy else { return false }
        busy = true; defer { busy = false }
        return queue?.recover(attempt, principal: principal, evidence: evidence) ?? false
    }
    private func actionRefusal(_ generation: String) -> PreferenceRefusal? {
        guard store != nil else { return .defaultComposition }
        guard !busy else { return .reentrant }
        guard !self.generation.isEmpty, generation.utf8.elementsEqual(self.generation.utf8) else { return .staleGeneration }
        return nil
    }
    private func block(_ reason: PreferenceRefusal) -> PreferenceEditResult {
        scheduledCheck = nil
        blockedReason = reason
        return .refused(reason)
    }
    // Caller holds the shared busy barrier. This read never adopts external bytes.
    private func validateCurrentAcceptedBytes() -> Bool {
        guard blockedReason == nil, let store, let acceptedBytes else { return false }
        switch store.read(maximumBytes: PreferenceRecord.maximumBytes) {
        case .missing: _ = block(.missing); return false
        case .unavailable: _ = block(.unavailable); return false
        case .bytes(let bytes):
            do { _ = try decodeAcceptedState(bytes) }
            catch { _ = block(.malformed); return false }
            guard bytes == acceptedBytes else { _ = block(.conflict); return false }
            return true
        }
    }
    private func decodeAcceptedState(_ bytes: Data) throws -> AcceptedState {
        guard !bytes.isEmpty, bytes.count <= PreferenceRecord.maximumBytes else { throw PreferenceRefusal.malformed }
        let state: AcceptedState
        if let legacy = try? PreferenceRecordCodec.decode(bytes, principal: principal, storeScope: storeScope) {
            state = .legacy(legacy)
        } else if let scheduled = try? SchedulePreferenceRecordCodec.decodeV2(bytes, principal: principal, storeScope: storeScope) {
            state = .scheduled(scheduled)
        } else {
            state = .firstRun(try FirstRunPreferenceRecordCodec.decodeV3(bytes, principal: principal, storeScope: storeScope))
        }
        // Require exact owner bytes even for canonically equivalent Unicode strings.
        guard state.preferences.principal.value.utf8.elementsEqual(principal.value.utf8),
              state.preferences.storeScope.utf8.elementsEqual(storeScope.utf8) else { throw PreferenceRefusal.malformed }
        return state
    }
    private func publish(_ state: AcceptedState, bytes: Data) {
        if acceptedBytes != bytes { scheduledCheck = nil }
        acceptedState = state; acceptedBytes = bytes; acceptedRevision = state.preferences.revision; blockedReason = nil
    }
    private func commit(_ proposed: AcceptedState, bytes: Data, expected: Data?, store: any PreferenceStore) -> PreferenceEditResult {
        // The physical owner's bound applies to the entire envelope, not only its inner record.
        guard bytes.count <= PreferenceRecord.maximumBytes else { return .refused(.limit) }
        do {
            guard try decodeAcceptedState(bytes) == proposed else { return .refused(.malformed) }
        } catch { return .refused(.malformed) }
        switch store.compareAndSwap(expected: expected, proposed: bytes, maximumBytes: PreferenceRecord.maximumBytes) {
        case .notCommitted: return .refused(.unavailable)
        case .conflict: return block(.conflict)
        case .uncertain: return block(.uncertain)
        case .committed:
            guard case .bytes(let readback) = store.read(maximumBytes: PreferenceRecord.maximumBytes),
                  readback == bytes else { return block(.readback) }
            do {
                let validated = try decodeAcceptedState(readback)
                guard validated == proposed else { return block(.readback) }
                publish(validated, bytes: readback)
                return .accepted(revision: validated.preferences.revision)
            } catch { return block(.readback) }
        }
    }
    private func policy(for release: ReleaseIdentity, record: PreferenceRecord, automaticEnabled: Bool,
                        pause: AutomaticPause?) -> SchedulePolicy {
        let excluded: Set<String> = record.exclusions.contains(PreferenceAppKey(release)) ? [release.product] : []
        var policy = SchedulePolicy(principal: principal, automaticEnabled: automaticEnabled,
                                    excludedProducts: excluded, pause: pause)
        for skipped in record.skips { policy.skip(skipped) }
        return policy
    }
    private func validText(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 &&
            !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    private func validRelease(_ release: ReleaseIdentity) -> Bool {
        [release.product, release.scope, release.release, release.build, release.edition, release.channel, release.artifact].allSatisfy(validText)
    }
    private func validChange(_ change: PreferenceChange) -> Bool {
        switch change {
        case .exclusion(let key, _): return [key.product, key.scope, key.edition, key.channel].allSatisfy(validText)
        case .skip(let release), .undo(let release): return validRelease(release)
        }
    }
    private func operationBytes(_ change: PreferenceChange) throws -> String {
        let object: [String: Any]
        switch change {
        case .exclusion(let key, let excluded):
            object = ["action": "exclusion", "app": ["channel": key.channel, "edition": key.edition,
                "product": key.product, "scope": key.scope], "excluded": excluded]
        case .skip(let release), .undo(let release):
            let action: String
            if case .skip = change { action = "skip" } else { action = "undo" }
            object = ["action": action, "release": ["artifact": release.artifact, "build": release.build,
                "channel": release.channel, "edition": release.edition, "product": release.product,
                "release": release.release, "scope": release.scope]]
        }
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        guard bytes.count <= 4096 else { throw PreferenceRefusal.limit }
        return String(decoding: bytes, as: UTF8.self)
    }
}
