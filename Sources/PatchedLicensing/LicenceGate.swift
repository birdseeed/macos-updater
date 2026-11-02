/// Recovery, discovery, display and self-update are outside this action type.
public enum ThirdPartyStart: CaseIterable, Sendable { case manual, automatic, queued }
public enum LicenceStartDecision: Equatable, Sendable {
    case permitted, expired, revoked, noEntitlement, verificationRequired
}
public enum LicenceGate {
    public static func evaluate(_ start: ThirdPartyStart, lease: VerifiedLease?,
                                anchor: LicenceTimeAnchor?, sample: LicenceClockSample) -> LicenceStartDecision {
        guard let lease else { return .verificationRequired }
        // Signed denial never becomes a grant because time evidence is unavailable.
        switch lease.state {
        case .revoked: return .revoked
        case .expired: return .expired
        case .none: return .noEntitlement
        case .beta, .trial, .paid, .grace: break
        }
        guard let anchor, anchor.serverTime == lease.issuedAt,
              let time = try? LicenceClock.evaluate(anchor: anchor, sample: sample) else { return .verificationRequired }
        guard time.effectiveNow < lease.permittedUntil else {
            return lease.permittedUntil == lease.hardEnd ? .expired : .verificationRequired
        }
        return .permitted
    }
}
