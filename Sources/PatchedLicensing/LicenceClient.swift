/// Fixture-only client over explicitly injected authenticated session, atomic
/// storage, transport and time. It cannot bootstrap unknown replay history.
@MainActor public final class LicenceClient {
    private let transport: any LicenceTransport
    private let sessions: any SessionStore
    private let cache: any LicenceCacheStore
    private let clock: any LicenceClockSource
    private let trust: LicenceTrust
    private var operating = false

    public init(transport: any LicenceTransport, sessions: any SessionStore,
                cache: any LicenceCacheStore, clock: any LicenceClockSource,
                trust: LicenceTrust = LicenceTrust()) {
        self.transport = transport; self.sessions = sessions; self.cache = cache
        self.clock = clock; self.trust = trust
    }

    public func refresh() -> LicenceStartDecision {
        operate { session, original, fenced in
            let result: LicenceTransportResult
            do { result = try transport.refresh(session: session) }
            catch { return blocked(fenced.state) }
            // Session identity includes its never-reused generation, so even a
            // switch away and back cannot make this response current again.
            guard sessions.currentSession() == session else { return blocked(fenced.state) }
            switch result {
            case .failure(let failure):
                return failure.classification == .eligibleOutage
                    ? cachedDecision(fenced.state, start: .manual) : blocked(fenced.state)
            case .response(let status, let body, let contentType, let validatedTLS):
                guard validatedTLS else { return blocked(fenced.state) }
                if status != 200 {
                    return LicenceRefreshOutcome.http(status).classification == .eligibleOutage
                        ? cachedDecision(fenced.state, start: .manual) : blocked(fenced.state)
                }
                guard contentType == "application/json",
                      let lease = try? SignedLease.verify(body, trust: trust, binding: session.binding,
                          replay: .authenticatedRefresh(after: original.state.safety.checkpoint)),
                      original.state.anchor.map({ lease.issuedAt >= $0.serverTime }) ?? true else {
                    return blocked(fenced.state)
                }
                var next = fenced.state
                next.safety.checkpoint = lease.checkpoint
                next.safety.verificationBlocked = false
                next.safety.terminalRevocation = lease.state == .revoked
                next.envelope = body
                next.anchor = nil
                switch lease.state {
                case .revoked: return (next, .revoked)
                case .expired: return (next, .expired)
                case .none: return (next, .noEntitlement)
                case .beta, .trial, .paid, .grace: break
                }
                // Only this own authenticated response can replace an anchor,
                // including recovery from an erroneously advanced wall clock.
                let observed = clock.sample()
                let anchor = LicenceTimeAnchor(serverTime: lease.issuedAt, monotonic: observed.monotonic,
                    boot: observed.boot, highestObservedWall: observed.wall)
                guard (try? LicenceClock.evaluate(anchor: anchor, sample: observed)) != nil else {
                    return blocked(next)
                }
                next.anchor = anchor
                return (next, LicenceGate.evaluate(.manual, lease: lease, anchor: anchor, sample: observed))
            }
        }
    }

    public func decision(for start: ThirdPartyStart) -> LicenceStartDecision {
        operate { _, _, fenced in cachedDecision(fenced.state, start: start) }
    }

    /// A live call owns only the exact version produced by its successful fence
    /// CAS. A matching session in a stored fence is never ownership evidence.
    /// No other call, restarted instance or reentrant adapter can resolve it.
    private func operate(_ action: (LicenceSession, LicenceCacheRecord, LicenceCacheRecord)
                         -> (LicenceCacheState, LicenceStartDecision)) -> LicenceStartDecision {
        guard !operating else { return .verificationRequired }
        operating = true
        defer { operating = false }
        guard let session = sessions.currentSession(),
              let read = try? cache.read(binding: session.binding),
              case .record(let original) = read,
              original.state.safety.checkpoint.lease.binding == session.binding,
              sessions.currentSession() == session else { return .verificationRequired }
        // Terminal authority is separate from removable cache bytes and time.
        if original.state.safety.terminalRevocation || original.state.safety.checkpoint.lease.state == .revoked {
            return .revoked
        }
        guard original.state.safety.inFlight == nil,
              original.version <= UInt64.max - 2 else { return .verificationRequired }
        var fenceState = original.state
        fenceState.safety.inFlight = session
        do {
            guard try cache.compareAndSwap(binding: session.binding, expectedVersion: original.version,
                                           replacement: fenceState),
                  sessions.currentSession() == session else { return .verificationRequired }
        } catch { return .verificationRequired }
        let fenced = LicenceCacheRecord(version: original.version + 1, state: fenceState)
        var (replacement, result) = action(session, original, fenced)
        guard sessions.currentSession() == session else { return .verificationRequired }
        replacement.safety.inFlight = nil
        do {
            guard try cache.compareAndSwap(binding: session.binding, expectedVersion: fenced.version,
                                           replacement: replacement),
                  sessions.currentSession() == session else { return .verificationRequired }
        } catch {
            // The write may have committed completely. This caller refuses;
            // a later client must inspect durable state, never this local copy.
            return .verificationRequired
        }
        return result
    }

    private func blocked(_ state: LicenceCacheState) -> (LicenceCacheState, LicenceStartDecision) {
        var next = state
        next.safety.verificationBlocked = true
        return (next, .verificationRequired)
    }

    /// Must run behind a durable fence: a failed high-water write must leave
    /// uncertainty across restart instead of forgetting an observed future wall.
    private func cachedDecision(_ state: LicenceCacheState, start: ThirdPartyStart)
                              -> (LicenceCacheState, LicenceStartDecision) {
        guard !state.safety.verificationBlocked, let envelope = state.envelope,
              let lease = try? SignedLease.verify(envelope, trust: trust,
                  binding: state.safety.checkpoint.lease.binding, replay: .cached(state.safety.checkpoint)) else {
            return blocked(state)
        }
        switch lease.state {
        case .revoked: return (state, .revoked)
        case .expired: return (state, .expired)
        case .none: return (state, .noEntitlement)
        case .beta, .trial, .paid, .grace: break
        }
        guard let anchor = state.anchor, anchor.serverTime == lease.issuedAt else { return blocked(state) }
        let observed = clock.sample()
        guard let time = try? LicenceClock.evaluate(anchor: anchor, sample: observed) else { return blocked(state) }
        var next = state
        next.anchor = LicenceTimeAnchor(serverTime: anchor.serverTime, monotonic: anchor.monotonic,
            boot: anchor.boot, highestObservedWall: time.highestObservedWall)
        return (next, LicenceGate.evaluate(start, lease: lease, anchor: next.anchor, sample: observed))
    }
}
