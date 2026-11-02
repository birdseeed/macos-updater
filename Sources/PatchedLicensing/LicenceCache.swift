import Foundation

/// Safety survives removal/replacement of cached bytes. A checkpoint can only
/// originate in SignedLease verification; it must not be synthesised as zero.
public struct LicenceSafetyState: Sendable {
    public var checkpoint: LicenceCheckpoint
    public var verificationBlocked: Bool
    public var terminalRevocation: Bool
    /// Identifies the session being fenced, not ownership of its live call.
    /// A restarted or reentrant caller with the same session cannot resolve it.
    public var inFlight: LicenceSession?
    public init(checkpoint: LicenceCheckpoint, verificationBlocked: Bool = false,
                terminalRevocation: Bool = false, inFlight: LicenceSession? = nil) {
        self.checkpoint = checkpoint; self.verificationBlocked = verificationBlocked
        self.terminalRevocation = terminalRevocation; self.inFlight = inFlight
    }
}

public struct LicenceCacheState: Sendable {
    public var safety: LicenceSafetyState
    public var envelope: Data?
    public var anchor: LicenceTimeAnchor?
    public init(safety: LicenceSafetyState, envelope: Data?, anchor: LicenceTimeAnchor?) {
        self.safety = safety; self.envelope = envelope; self.anchor = anchor
    }
}

public struct LicenceCacheRecord: Sendable {
    public let version: UInt64
    public let state: LicenceCacheState
    public init(version: UInt64, state: LicenceCacheState) {
        self.version = version; self.state = state
    }
}
public enum LicenceCacheRead: Sendable { case missing, corrupt, record(LicenceCacheRecord) }

/// Trusted fixture storage boundary. Reads return one coherent snapshot, and
/// CAS atomically replaces safety, bytes and anchor for the named binding.
/// Success means durable before return; false means a conflict with no write.
/// Throw may mean no write or a complete write with lost acknowledgement, never
/// a partial record. Each committed CAS increments version by exactly one,
/// without reuse, including after restart; UInt64.max cannot be incremented.
/// Adapters must classify missing/corrupt evidence, never create default state.
/// Native durability and resistance to full valid-snapshot restore are unproved.
@MainActor public protocol LicenceCacheStore: AnyObject {
    func read(binding: LicenceBinding) throws -> LicenceCacheRead
    func compareAndSwap(binding: LicenceBinding, expectedVersion: UInt64,
                        replacement: LicenceCacheState) throws -> Bool
}
