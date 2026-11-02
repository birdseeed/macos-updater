/// Injected, already authenticated session identity. No token or sign-in adapter.
public struct LicenceSession: Equatable, Sendable {
    public let binding: LicenceBinding
    public let generation: UInt64
    public init(binding: LicenceBinding, generation: UInt64) {
        self.binding = binding; self.generation = generation
    }
}

/// Generation must change on every cancellation, switch or new sign-in, even
/// when the binding returns to its earlier value. It must never be reused.
@MainActor public protocol SessionStore: AnyObject {
    func currentSession() -> LicenceSession?
}
