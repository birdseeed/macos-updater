import Foundation

public enum PreferenceRead: Equatable, Sendable {
    case bytes(Data), missing, unavailable
}
public enum PreferenceCommit: Equatable, Sendable {
    case committed, notCommitted, conflict, uncertain
}
/// Synchronous CAS over exact previous bytes, including revision. nil means explicitly absent.
/// Implementations must bound reads before allocating, and preserve existing bytes on known failure.
@_spi(Testing) @MainActor public protocol PreferenceStore: AnyObject {
    func read(maximumBytes: Int) -> PreferenceRead
    func compareAndSwap(expected: Data?, proposed: Data, maximumBytes: Int) -> PreferenceCommit
}
/// Ordinary composition has no store injection, filesystem, network, helper or start adapter.
public struct RefusingPreferenceStore: Sendable {
    public init() {}
    public func read(maximumBytes: Int) -> PreferenceRead { .unavailable }
    public func compareAndSwap(expected: Data?, proposed: Data, maximumBytes: Int) -> PreferenceCommit { .notCommitted }
}
