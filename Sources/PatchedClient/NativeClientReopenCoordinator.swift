import AppKit

/// Retains the current main-window route without performing work at registration.
@MainActor public final class NativeClientReopenCoordinator {
    private var opener: (@MainActor () -> Void)?

    public init() {}

    public func register(opener: @escaping @MainActor () -> Void) {
        self.opener = opener
    }

    public func handleReopen(hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows, let opener else { return true }
        opener()
        return false
    }
}
