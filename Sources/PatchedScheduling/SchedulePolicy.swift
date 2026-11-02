/// Opaque policy owner, injected by a future authenticated boundary, not an email or UID parser.
public struct SchedulingPrincipal: Hashable, Sendable {
    public let value: String
    public init(_ value: String) { self.value = value }
}

/// Exact verified upstream identity input, not a verification receipt or installation capability.
public struct ReleaseIdentity: Hashable, Sendable {
    public let product: String
    public let scope: String
    public let release: String
    public let build: String
    public let edition: String
    public let channel: String
    public let artifact: String

    public init(product: String, scope: String, release: String, build: String,
                edition: String, channel: String, artifact: String) {
        self.product = product
        self.scope = scope
        self.release = release
        self.build = build
        self.edition = edition
        self.channel = channel
        self.artifact = artifact
    }
}

public enum ReleaseEvidence: Equatable, Sendable {
    case verified(ReleaseIdentity)
    case ambiguous
}
public enum InstallationRoute: Sendable { case unattended, restartRequired, interactive, unknown }
public enum StartKind: Sendable { case manual, updateAll, automatic, loginWindow }
public enum KnownSignal: Sendable { case yes, no, unknown }
public enum Eligibility: Sendable { case eligible, refused, unknown }
public enum ScheduleDeferral: String, Equatable, Sendable {
    case principal, identity, skipped, automaticOff, excluded, paused, clock
    case eligibility, targetOpen, awake, idle, route
}
public enum ScheduleDecision: Equatable, Sendable {
    case eligible
    case deferred(ScheduleDeferral)
}

/// Current action-time input for this exact principal/candidate. Callers must refresh it for each start.
/// This is a pure decision model, never an installation-authority constructor.
public struct StartConditions: Sendable {
    public var principal: SchedulingPrincipal
    public var target: String
    public var release: ReleaseEvidence
    public var route: InstallationRoute
    public var eligibility: Eligibility
    public var targetClosed: KnownSignal
    public var awake: KnownSignal
    public var idle: KnownSignal
    public var clock: ClockSample
    public var previousClock: ClockSample?

    public init(principal: SchedulingPrincipal, target: String, release: ReleaseEvidence,
                route: InstallationRoute = .unknown, eligibility: Eligibility = .unknown,
                targetClosed: KnownSignal = .unknown, awake: KnownSignal = .unknown,
                idle: KnownSignal = .unknown, clock: ClockSample, previousClock: ClockSample? = nil) {
        self.principal = principal
        self.target = target
        self.release = release
        self.route = route
        self.eligibility = eligibility
        self.targetClosed = targetClosed
        self.awake = awake
        self.idle = idle
        self.clock = clock
        self.previousClock = previousClock
    }
}

public struct SchedulePolicy: Sendable {
    public let principal: SchedulingPrincipal
    public var automaticEnabled: Bool
    public var excludedProducts: Set<String>
    public var pause: AutomaticPause?
    public private(set) var skippedReleases: Set<ReleaseIdentity> = []

    public init(principal: SchedulingPrincipal, automaticEnabled: Bool = false,
                excludedProducts: Set<String> = [], pause: AutomaticPause? = nil) {
        self.principal = principal
        self.automaticEnabled = automaticEnabled
        self.excludedProducts = excludedProducts
        self.pause = pause
    }

    public mutating func skip(_ release: ReleaseIdentity) {
        skippedReleases.insert(release)
    }

    public mutating func unskip(_ release: ReleaseIdentity) {
        skippedReleases.remove(release)
    }

    public func decision(for kind: StartKind, conditions: StartConditions) -> ScheduleDecision {
        guard !principal.value.isEmpty, principal == conditions.principal else {
            return .deferred(.principal)
        }
        guard !conditions.target.isEmpty,
              case .verified(let candidate) = conditions.release, candidate.isComplete else {
            return .deferred(.identity)
        }
        if skippedReleases.contains(candidate) { return .deferred(.skipped) }
        // A changed build/digest under a skipped release is not proof of a later
        // release. Metadata revision is deliberately absent from the skip key.
        if skippedReleases.contains(where: { $0.sameRelease(as: candidate) }) {
            return .deferred(.identity)
        }
        guard conditions.eligibility == .eligible else { return .deferred(.eligibility) }
        guard conditions.targetClosed == .yes else { return .deferred(.targetOpen) }
        // Manual approval for interactive/restart routes is outside this starter.
        // No caller Boolean can turn either route into unattended eligibility.
        guard conditions.route == .unattended else { return .deferred(.route) }
        guard kind == .automatic || kind == .loginWindow else { return .eligible }
        guard automaticEnabled else { return .deferred(.automaticOff) }
        guard !excludedProducts.contains(candidate.product) else { return .deferred(.excluded) }
        guard conditions.clock.isUsable else { return .deferred(.clock) }
        if let previous = conditions.previousClock,
           !conditions.clock.isConsistent(with: previous) {
            return .deferred(.clock)
        }
        if let pause {
            guard pause.resumeUTC >= 0, conditions.clock.isConsistent(with: pause.anchor) else {
                return .deferred(.clock)
            }
            if conditions.clock.utc < pause.resumeUTC { return .deferred(.paused) }
        }
        guard conditions.awake == .yes else { return .deferred(.awake) }
        guard conditions.idle == .yes else { return .deferred(.idle) }
        return .eligible
    }

    /// Read-only discovery is independent of third-party start controls.
    public func permitsCheck(for principal: SchedulingPrincipal) -> Bool {
        !self.principal.value.isEmpty && principal == self.principal
    }
}

extension ReleaseIdentity {
    var isComplete: Bool {
        [product, scope, release, build, edition, channel, artifact].allSatisfy { !$0.isEmpty }
    }

    func sameRelease(as other: ReleaseIdentity) -> Bool {
        product == other.product && scope == other.scope && release == other.release &&
            edition == other.edition && channel == other.channel
    }
}
