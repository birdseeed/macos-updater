import Foundation

public enum LicenceTransportResult: Sendable {
    case response(status: Int, body: Data, contentType: String, validatedTLS: Bool)
    /// Eligible connection failures mean before TLS or after validated TLS;
    /// certificate/hostname failure must be reported as tlsFailure instead.
    case failure(LicenceRefreshOutcome)
}

/// Only the response to this exact authenticated session request is eligible.
/// No implementation, credentials, HTTP client or production endpoint exists.
@MainActor public protocol LicenceTransport: AnyObject {
    func refresh(session: LicenceSession) throws -> LicenceTransportResult
}

/// Injected seconds with a monotonic source that counts sleep. Native clock
/// and boot identity behaviour are not proved by this fixture interface.
@MainActor public protocol LicenceClockSource: AnyObject {
    func sample() -> LicenceClockSample
}
