import PatchedScheduling

/// Injected model events only, never native time or sleep attestation.
public enum ScheduleRuntimeEvent: Sendable {
    case observation(sample: ClockSample, awake: KnownSignal)
    case sleep, clockInvalidated, shutdown
}
public enum ScheduleClockState: Equatable, Sendable { case unavailable, usable, invalid, stopped }
public enum SchedulePauseTiming: Equatable, Sendable { case unavailable, notPaused, beforeDeadline, atOrAfterDeadline }
/// Cached model description. No field establishes freshness, permission or installation authority.
public struct ScheduleRuntimeSnapshot: Sendable {
    public let clockState: ScheduleClockState
    public let awake: KnownSignal
    public let checkDue: Bool
    public let checkInFlight: Bool
    public let pauseTiming: SchedulePauseTiming
    public var automaticInstallationAvailable: Bool { false }
    init(clockState: ScheduleClockState, awake: KnownSignal, checkDue: Bool,
         checkInFlight: Bool, pauseTiming: SchedulePauseTiming) {
        self.clockState = clockState; self.awake = awake; self.checkDue = checkDue
        self.checkInFlight = checkInFlight; self.pauseTiming = pauseTiming
    }
}
/// One instance-bound read-only check opportunity. It conveys no actual check result or native authority.
public struct ScheduledCheckAttempt: Equatable, Sendable {
    let owner: ScheduledCheckAttemptOwner
    let sequence: UInt64
    let revision: UInt64
    let generation: String
    init(owner: ScheduledCheckAttemptOwner, sequence: UInt64, revision: UInt64, generation: String) {
        self.owner = owner; self.sequence = sequence; self.revision = revision; self.generation = generation
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.owner === rhs.owner && lhs.sequence == rhs.sequence && lhs.revision == rhs.revision &&
            lhs.generation.utf8.elementsEqual(rhs.generation.utf8)
    }
}
final class ScheduledCheckAttemptOwner: Sendable {}
