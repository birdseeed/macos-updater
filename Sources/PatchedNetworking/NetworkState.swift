public enum NetworkPurpose: String, CaseIterable, Equatable, Sendable {
    case catalogue, artifact, manualSupport, failureReport
}
public enum NetworkDestination: String, Equatable, Sendable {
    case catalogueFixture, artifactFixture, supportFixture, reportFixture, unapprovedFixture
}
public enum NetworkMethod: String, Equatable, Sendable { case get, post, put }
public enum NetworkPath: String, Equatable, Sendable { case online, offline, limited, unknown }
public enum NetworkRoute: Equatable, Sendable {
    case systemDirect, systemProxy, direct
    case manualProxy(host: String, port: Int, credentialReference: String?)
    case unavailable, pacFailure, authenticationNeeded, unsupported
}
public enum NetworkTransfer: String, Equatable, Sendable { case automatic, explicit }
public enum NetworkRefusal: String, CaseIterable, Equatable, Sendable {
    case unavailable, invalidConfiguration, bindingMismatch, invalidTime, expired
    case destinationMismatch, methodMismatch, bodyMismatch, routeMismatch
    case pacFailure, authenticationNeeded, unsupported, offline, limitedData, unknownPath, consentRequired
}
public struct NetworkEndpoint: Equatable, Sendable {
    public let destination: NetworkDestination
    public let purpose: NetworkPurpose
    public let method: NetworkMethod
    public init(_ destination: NetworkDestination, _ purpose: NetworkPurpose, _ method: NetworkMethod) {
        self.destination = destination; self.purpose = purpose; self.method = method
    }
}
public struct NetworkArtifact: Equatable, Sendable {
    public var app: String
    public var version: String
    public var digest: String
    public init(app: String, version: String, digest: String) {
        self.app = app; self.version = version; self.digest = digest
    }
}
public struct NetworkConsent: Equatable, Sendable {
    public var principal: NetworkPrincipal
    public var purpose: NetworkPurpose
    public var generation: UInt64
    public var allowed: Bool
    public init(principal: NetworkPrincipal, purpose: NetworkPurpose, generation: UInt64, allowed: Bool) {
        self.principal = principal; self.purpose = purpose; self.generation = generation; self.allowed = allowed
    }
}
public struct NetworkLimitedOverride: Equatable, Sendable {
    public var principal: NetworkPrincipal
    public var revision: UInt64
    public var purpose: NetworkPurpose
    public var destination: NetworkDestination
    public var artifact: NetworkArtifact
    public var expires: Int64
    public init(principal: NetworkPrincipal, revision: UInt64, purpose: NetworkPurpose,
                destination: NetworkDestination, artifact: NetworkArtifact, expires: Int64) {
        self.principal = principal; self.revision = revision; self.purpose = purpose
        self.destination = destination; self.artifact = artifact; self.expires = expires
    }
}
// These are untrusted injected observations, never platform facts or native authority.
public struct NetworkAdmission: Equatable, Sendable {
    public var principal: NetworkPrincipal
    public var revision: UInt64
    public var purpose: NetworkPurpose
    public var destination: NetworkDestination
    public var method: NetworkMethod
    public var bodyDigest: String?
    public var frozenBodyDigest: String?
    public var now: Int64?
    public var expires: Int64
    public var route: NetworkRoute
    public var path: NetworkPath
    public var transfer: NetworkTransfer
    public var artifact: NetworkArtifact?
    public var limitedOverride: NetworkLimitedOverride?
    public var consentGeneration: UInt64?
    public var consent: NetworkConsent?
    public init(principal: NetworkPrincipal, revision: UInt64, purpose: NetworkPurpose,
                destination: NetworkDestination, method: NetworkMethod, bodyDigest: String? = nil, frozenBodyDigest: String? = nil,
                now: Int64? = nil, expires: Int64 = 0, route: NetworkRoute = .unavailable,
                path: NetworkPath = .unknown, transfer: NetworkTransfer = .automatic,
                artifact: NetworkArtifact? = nil, limitedOverride: NetworkLimitedOverride? = nil,
                consentGeneration: UInt64? = nil, consent: NetworkConsent? = nil) {
        self.principal = principal; self.revision = revision; self.purpose = purpose
        self.destination = destination; self.method = method; self.bodyDigest = bodyDigest; self.frozenBodyDigest = frozenBodyDigest
        self.now = now; self.expires = expires; self.route = route; self.path = path
        self.transfer = transfer; self.artifact = artifact; self.limitedOverride = limitedOverride
        self.consentGeneration = consentGeneration; self.consent = consent
    }
}
public enum NetworkSyntheticMarker: String, Equatable, Sendable { case syntheticModelOnly = "SYNTHETIC MODEL ONLY" }
public struct NetworkSyntheticModel: Equatable, Sendable {
    public let marker: NetworkSyntheticMarker
    public let principal: NetworkPrincipal
    public let revision: UInt64
    public let purpose: NetworkPurpose
    // No URLs, credential reference, digest, arbitrary strings, error or dispatch token.
    public var grantsNativeAuthority: Bool { false }
    public var grantsInstallationAuthority: Bool { false }
    internal init(principal: NetworkPrincipal, revision: UInt64, purpose: NetworkPurpose) {
        self.marker = .syntheticModelOnly; self.principal = principal
        self.revision = revision; self.purpose = purpose
    }
}
public enum NetworkDecision: Equatable, Sendable {
    case refused(NetworkRefusal)
    case syntheticPermitted(NetworkSyntheticModel)
}
public enum NetworkDispatchOutcome: String, Equatable, Sendable { case unavailable }
