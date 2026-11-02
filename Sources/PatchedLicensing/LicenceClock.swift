/// Integer seconds exclude non-finite and fractional input by construction.
public struct LicenceClockSample: Sendable {
    public let wall: Int64
    public let monotonic: Int64
    public let boot: String?
    public init(wall: Int64, monotonic: Int64, boot: String?) {
        self.wall = wall; self.monotonic = monotonic; self.boot = boot
    }
}

/// An injected anchor, with no OS clock, storage or authenticated transport.
public struct LicenceTimeAnchor: Sendable {
    public let serverTime: Int64
    public let monotonic: Int64
    public let boot: String?
    public let highestObservedWall: Int64
    public init(serverTime: Int64, monotonic: Int64, boot: String?, highestObservedWall: Int64) {
        self.serverTime = serverTime; self.monotonic = monotonic
        self.boot = boot; self.highestObservedWall = highestObservedWall
    }
}
public struct LicenceTimeEvaluation: Sendable {
    public let effectiveNow: Int64
    public let highestObservedWall: Int64
}
public enum LicenceClock {
    public static func evaluate(anchor: LicenceTimeAnchor?, sample: LicenceClockSample) throws -> LicenceTimeEvaluation {
        guard let anchor,
              let boot = anchor.boot, !boot.isEmpty, boot.utf8.count <= 256,
              boot.utf8.allSatisfy({ (32...126).contains($0) }), sample.boot == boot,
              [anchor.serverTime, anchor.monotonic, anchor.highestObservedWall,
               sample.wall, sample.monotonic].allSatisfy({ $0 >= 0 && $0 <= LicencePolicy.maximumExactSecond }),
              sample.monotonic >= anchor.monotonic,
              sample.wall >= anchor.highestObservedWall else { throw LicenceRefusal.clockUncertain }
        let elapsed = sample.monotonic - anchor.monotonic
        guard elapsed <= LicencePolicy.maximumExactSecond - anchor.serverTime else { throw LicenceRefusal.clockUncertain }
        return LicenceTimeEvaluation(effectiveNow: max(anchor.serverTime + elapsed, sample.wall, anchor.highestObservedWall),
                                     highestObservedWall: max(sample.wall, anchor.highestObservedWall))
    }
}
