// Pure synthetic admission over supplied observations, never native authority.
public struct NetworkPolicy {
    internal let syntheticEndpoints: [NetworkEndpoint]
    internal let boundaries: NetworkBoundaries
    public init() { syntheticEndpoints = []; boundaries = NetworkBoundaries() }
    @_spi(Testing) public init(syntheticEndpoints: [NetworkEndpoint], boundaries: NetworkBoundaries = NetworkBoundaries()) {
        self.syntheticEndpoints = syntheticEndpoints; self.boundaries = boundaries
    }
    public func admit(configuration: NetworkConfiguration, observation: NetworkAdmission) -> NetworkDecision {
        guard configuration.validate() == .syntheticValid else { return .refused(.invalidConfiguration) }
        guard !syntheticEndpoints.isEmpty, observation.route != .unavailable else { return .refused(.unavailable) }
        guard observation.principal == configuration.principal, observation.revision == configuration.revision else {
            return .refused(.bindingMismatch)
        }
        if let reason = Self.timeRefusal(now: observation.now, expires: observation.expires) {
            return .refused(reason)
        }
        guard syntheticEndpoints.contains(where: {
            $0.destination == observation.destination && $0.purpose == observation.purpose
        }) else { return .refused(.destinationMismatch) }
        let submission = observation.purpose == .manualSupport || observation.purpose == .failureReport
        let expectedMethod: NetworkMethod = submission ? .post : .get
        guard observation.method == expectedMethod, syntheticEndpoints.contains(where: {
            $0.destination == observation.destination && $0.purpose == observation.purpose && $0.method == observation.method
        }) else { return .refused(.methodMismatch) }
        if submission {
            guard let body = observation.bodyDigest, let frozen = observation.frozenBodyDigest,
                  Self.validDigest(body), Self.validDigest(frozen), body == frozen else { return .refused(.bodyMismatch) }
        } else if observation.bodyDigest != nil || observation.frozenBodyDigest != nil {
            return .refused(.bodyMismatch)
        }
        switch observation.route {
        case .unavailable: return .refused(.unavailable)
        case .pacFailure: return .refused(.pacFailure)
        case .authenticationNeeded: return .refused(.authenticationNeeded)
        case .unsupported: return .refused(.unsupported)
        case .systemDirect, .systemProxy:
            guard configuration.mode == .system else { return .refused(.routeMismatch) }
        case .direct:
            guard configuration.mode == .direct else { return .refused(.routeMismatch) }
        case .manualProxy(let host, let port, let reference):
            guard configuration.mode == .manualHTTP, let configuredHost = configuration.host,
                  configuredHost.utf8.elementsEqual(host.utf8), configuration.port == port,
                  Self.equalUTF8(configuration.credentialReference, reference) else { return .refused(.routeMismatch) }
        }
        switch observation.path {
        case .offline: return .refused(.offline)
        case .unknown: return .refused(.unknownPath)
        case .online: break
        case .limited:
            switch observation.purpose {
            case .catalogue: break
            case .manualSupport, .failureReport: return .refused(.limitedData)
            case .artifact:
                guard Self.validLimitedTransfer(observation) else { return .refused(.limitedData) }
            }
        }
        if submission {
            guard let consent = observation.consent, let generation = observation.consentGeneration,
                  generation > 0, consent.allowed, consent.generation == generation,
                  consent.principal == observation.principal, consent.purpose == observation.purpose else {
                return .refused(.consentRequired)
            }
        }
        return .syntheticPermitted(NetworkSyntheticModel(principal: configuration.principal,
                                                       revision: configuration.revision, purpose: observation.purpose))
    }

    private static func equalUTF8(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (.some(let lhs), .some(let rhs)): return lhs.utf8.elementsEqual(rhs.utf8)
        default: return false
        }
    }

    private static func timeRefusal(now: Int64?, expires: Int64) -> NetworkRefusal? {
        let maximum: Int64 = 9_007_199_254_740_991
        guard let now, (0...maximum).contains(now), (0...maximum).contains(expires) else { return .invalidTime }
        guard expires > now else { return .expired }
        // Bounds and ordering above make this subtraction safe.
        return expires - now <= 300 ? nil : .invalidTime
    }

    private static func validDigest(_ value: String) -> Bool {
        value.utf8.prefix(65).count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static func validToken(_ value: String) -> Bool {
        (1...64).contains(value.utf8.prefix(65).count) && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) ||
            $0 == 46 || $0 == 95 || $0 == 45
        }
    }

    private static func validLimitedTransfer(_ observation: NetworkAdmission) -> Bool {
        guard observation.transfer == .explicit, let artifact = observation.artifact,
              validToken(artifact.app), validToken(artifact.version), validDigest(artifact.digest),
              let override = observation.limitedOverride, override.principal == observation.principal,
              override.revision == observation.revision, override.purpose == observation.purpose,
              override.destination == observation.destination,
              override.artifact.app.utf8.elementsEqual(artifact.app.utf8),
              override.artifact.version.utf8.elementsEqual(artifact.version.utf8),
              override.artifact.digest.utf8.elementsEqual(artifact.digest.utf8),
              timeRefusal(now: observation.now, expires: override.expires) == nil else { return false }
        return true
    }
    // Permanent refusal: a synthetic decision is not a native transport capability.
    public func dispatch(_ decision: NetworkDecision) -> NetworkDispatchOutcome { .unavailable }
}
