/// Injected whole-second samples. This module never reads the system clock.
public struct ClockSample: Equatable, Sendable {
    public let utc: Int64
    public let monotonic: Int64
    public let boot: String
    public let trustedUTC: Bool

    public init(utc: Int64, monotonic: Int64, boot: String, trustedUTC: Bool = false) {
        self.utc = utc
        self.monotonic = monotonic
        self.boot = boot
        self.trustedUTC = trustedUTC
    }
}

/// An absolute customer-selected UTC deadline; display zone does not shift it.
public struct AutomaticPause: Equatable, Sendable {
    public let resumeUTC: Int64
    public let displayZone: String
    public let anchor: ClockSample

    public init(resumeUTC: Int64, displayZone: String, anchor: ClockSample) {
        self.resumeUTC = resumeUTC
        self.displayZone = displayZone
        self.anchor = anchor
    }
}

extension ClockSample {
    /// Injected-model validity only; this predicate does not attest native time.
    public var isUsable: Bool {
        trustedUTC && utc >= 0 && monotonic >= 0 && !boot.isEmpty
    }

    /// Conservative whole-second fixture contract. Same-boot wall and monotonic
    /// elapsed time must agree; a future adapter must supply trustworthy samples.
    /// A new boot needs trustworthy UTC again, never a carried monotonic anchor.
    /// Comparing injected samples supplies no OS clock or boot authority.
    public func isConsistent(with earlier: ClockSample) -> Bool {
        guard isUsable, earlier.isUsable else { return false }
        guard boot == earlier.boot else { return true }
        let wall = utc.subtractingReportingOverflow(earlier.utc)
        let elapsed = monotonic.subtractingReportingOverflow(earlier.monotonic)
        return !wall.overflow && !elapsed.overflow && wall.partialValue >= 0 &&
            elapsed.partialValue >= 0 && wall.partialValue == elapsed.partialValue
    }
}
