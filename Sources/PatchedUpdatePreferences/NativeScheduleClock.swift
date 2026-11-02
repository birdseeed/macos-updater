import Darwin
import PatchedScheduling

/// Untrusted controlled raw observations for checks only. No native or installer authority.
@_spi(Testing) public struct NativeScheduleClockRawRead: Sendable {
    public let wallSeconds: Double
    public let continuousBeforeNanoseconds: UInt64
    public let continuousAfterNanoseconds: UInt64
    public let bootBefore: String
    public let bootAfter: String
    public init(wallSeconds: Double, continuousBeforeNanoseconds: UInt64,
                continuousAfterNanoseconds: UInt64, bootBefore: String, bootAfter: String) {
        self.wallSeconds = wallSeconds
        self.continuousBeforeNanoseconds = continuousBeforeNanoseconds
        self.continuousAfterNanoseconds = continuousAfterNanoseconds
        self.bootBefore = bootBefore; self.bootAfter = bootAfter
    }
}

/// Explicit process-local scheduling projection only. Never authenticated UTC,
/// licence/catalogue freshness, native permission or installation authority.
@MainActor public final class NativeScheduleClock {
    private struct Observation {
        let raw: NativeScheduleClockRawRead
        let midpoint: UInt64
        let wholeWall: Int64
        let wholeMonotonic: Int64
    }
    private enum ReadError: Error { case unavailable }
    private let rawReader: () throws -> NativeScheduleClockRawRead
    private var anchor: Observation?
    private var last: Observation?
    private var invalid = false

    /// Construction is inert, including for the ordinary native composition.
    public init() { rawReader = { try NativeScheduleClock.readNative() } }
    /// Fake/untrusted fixture seam. Construction never invokes the reader.
    @_spi(Testing) public init(rawReader: @escaping () throws -> NativeScheduleClockRawRead) {
        self.rawReader = rawReader
    }

    public func sample() -> ClockSample? {
        guard !invalid else { return nil }
        guard let current = readObservation() else { return refuse() }
        guard let anchor, let last else { return acceptAnchor(current) }
        guard current.raw.bootBefore == anchor.raw.bootBefore,
              current.raw.wallSeconds >= last.raw.wallSeconds,
              current.raw.continuousBeforeNanoseconds >= last.raw.continuousAfterNanoseconds,
              current.midpoint >= anchor.midpoint else { return refuse() }

        let elapsed = current.midpoint - anchor.midpoint
        let wallElapsed = current.raw.wallSeconds - anchor.raw.wallSeconds
        guard wallElapsed.isFinite,
              abs(wallElapsed - Double(elapsed) / 1_000_000_000) <= 0.25,
              let seconds = Int64(exactly: elapsed / 1_000_000_000) else { return refuse() }
        let utc = anchor.wholeWall.addingReportingOverflow(seconds)
        let monotonic = anchor.wholeMonotonic.addingReportingOverflow(seconds)
        guard !utc.overflow, !monotonic.overflow,
              utc.partialValue <= current.wholeWall else { return refuse() }
        self.last = current
        return projection(utc: utc.partialValue, monotonic: monotonic.partialValue, boot: anchor.raw.bootBefore)
    }

    /// Resets this sampler only. Caller must separately reanchor PreferenceSession.
    public func reanchor() -> ClockSample? {
        guard let current = readObservation() else { return refuse() }
        return acceptAnchor(current)
    }

    private func refuse() -> ClockSample? {
        invalid = true
        return nil
    }

    private func acceptAnchor(_ current: Observation) -> ClockSample {
        anchor = current
        last = current
        invalid = false
        return projection(utc: current.wholeWall, monotonic: current.wholeMonotonic, boot: current.raw.bootBefore)
    }

    private func projection(utc: Int64, monotonic: Int64, boot: String) -> ClockSample {
        // The legacy flag permits local scheduler use only, not authenticated UTC.
        ClockSample(utc: utc, monotonic: monotonic, boot: boot, trustedUTC: true)
    }

    private func readObservation() -> Observation? {
        guard let raw = try? rawReader(),
              raw.wallSeconds.isFinite, raw.wallSeconds >= 0,
              let wholeWall = Int64(exactly: raw.wallSeconds.rounded(.down)),
              raw.continuousAfterNanoseconds >= raw.continuousBeforeNanoseconds,
              raw.continuousAfterNanoseconds - raw.continuousBeforeNanoseconds <= 50_000_000,
              Self.validBoot(raw.bootBefore), Self.validBoot(raw.bootAfter),
              raw.bootBefore == raw.bootAfter else { return nil }
        let midpoint = raw.continuousBeforeNanoseconds +
            (raw.continuousAfterNanoseconds - raw.continuousBeforeNanoseconds) / 2
        guard let wholeMonotonic = Int64(exactly: midpoint / 1_000_000_000) else { return nil }
        return Observation(raw: raw, midpoint: midpoint, wholeWall: wholeWall, wholeMonotonic: wholeMonotonic)
    }

    private static func validBoot(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 36 else { return false }
        var nonzero = false
        for (index, byte) in bytes.enumerated() {
            if index == 8 || index == 13 || index == 18 || index == 23 {
                guard byte == 45 else { return false }
            } else {
                guard (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte) else { return false }
                nonzero = nonzero || byte != 48
            }
        }
        return nonzero
    }

    private static func readNative() throws -> NativeScheduleClockRawRead {
        let bootBefore = try readBoot()
        let before = try readContinuous()
        var wall = timespec()
        guard clock_gettime(CLOCK_REALTIME, &wall) == 0,
              wall.tv_sec >= 0, wall.tv_nsec >= 0, wall.tv_nsec < 1_000_000_000 else { throw ReadError.unavailable }
        let after = try readContinuous()
        let bootAfter = try readBoot()
        return NativeScheduleClockRawRead(
            wallSeconds: Double(wall.tv_sec) + Double(wall.tv_nsec) / 1_000_000_000,
            continuousBeforeNanoseconds: before, continuousAfterNanoseconds: after,
            bootBefore: bootBefore, bootAfter: bootAfter)
    }

    private static func readContinuous() throws -> UInt64 {
        var value = timespec()
        // On Darwin CLOCK_MONOTONIC_RAW uses sleep-inclusive continuous time.
        guard clock_gettime(CLOCK_MONOTONIC_RAW, &value) == 0,
              let seconds = UInt64(exactly: value.tv_sec),
              value.tv_nsec >= 0, value.tv_nsec < 1_000_000_000 else { throw ReadError.unavailable }
        let scaled = seconds.multipliedReportingOverflow(by: 1_000_000_000)
        let nanos = scaled.partialValue.addingReportingOverflow(UInt64(value.tv_nsec))
        guard !scaled.overflow, !nanos.overflow else { throw ReadError.unavailable }
        return nanos.partialValue
    }

    private static func readBoot() throws -> String {
        // Fixed key and fixed capacity, with no sizing request or fallback identity.
        var bytes = [UInt8](repeating: 0, count: 37)
        var length = bytes.count
        let result = bytes.withUnsafeMutableBytes { buffer in
            sysctlbyname("kern.bootsessionuuid", buffer.baseAddress, &length, nil, 0)
        }
        guard result == 0, length == 37, bytes[36] == 0 else { throw ReadError.unavailable }
        let boot = String(decoding: bytes.prefix(36), as: UTF8.self)
        guard validBoot(boot) else { throw ReadError.unavailable }
        return boot
    }
}
