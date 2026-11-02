import Foundation

/// Closed intent selector, never native authority. Compiled expectations must
/// match independent physical observation before any productive scope opens.
public enum DisposableTargetProfile: CaseIterable, Sendable, Equatable {
    case legacy, ssdTesting
    public var targetID: String { self == .legacy ? DisposableScope.targetID : "parallels-0A0A0A0A-0000-4000-8000-000000000002" }
    /// Host selector only; it is not the guest's physical IOPlatformUUID.
    public var hostVMUUID: String { self == .legacy ? "0a0a0a0a-0000-4000-8000-000000000001" : "0a0a0a0a-0000-4000-8000-000000000002" }
    public var guestUUIDSHA256: String { self == .legacy ? DisposableScope.guestUUIDSHA256 : "a44c836bfbda0c6beb1df7b3b3178a171479d362ecfacd534a62b09890dde705" }
    public var guestUID: UInt32 { DisposableScope.guestUID }
    public var guestUser: String { self == .legacy ? DisposableScope.guestUser : "runner" }
    public var guestHome: String { self == .legacy ? DisposableScope.guestHome : "/Users/runner" }
    public var guestHostname: String { self == .legacy ? DisposableScope.guestHostname : "patched-test-01" }
    public var guestOS: String { DisposableScope.guestOS }
    public var guestBuild: String { DisposableScope.guestBuild }
    public var guestArchitecture: String { DisposableScope.guestArchitecture }
    public var runParent: String { self == .legacy ? DisposableScope.runParent : "/Users/runner/PatchedTesting" }
    public static func resolve(targetID: String) throws -> Self {
        guard let profile = allCases.first(where: { $0.targetID == targetID }) else { throw DisposableFailure.unknownTarget }
        return profile
    }
}

/// Data-only declared facts for independent predicate checks. This SPI cannot
/// observe the OS, call GuestGuard, write, run a process or issue any capability.
@_spi(Testing) public struct SyntheticDeclaredGuestIdentity: Sendable {
    public var realUID: UInt32, effectiveUID: UInt32, consoleUID: UInt32
    public var accountName: String, accountHome: String, homeEnvironment: String
    public var hypervisor: Int32
    public var osVersion: String, osBuild: String, architecture: String
    public var hostname: String, platformUUIDSHA256: String
    public init(realUID: UInt32, effectiveUID: UInt32, consoleUID: UInt32,
                accountName: String, accountHome: String, homeEnvironment: String,
                hypervisor: Int32, osVersion: String, osBuild: String, architecture: String,
                hostname: String, platformUUIDSHA256: String) {
        self.realUID = realUID; self.effectiveUID = effectiveUID; self.consoleUID = consoleUID
        self.accountName = accountName; self.accountHome = accountHome; self.homeEnvironment = homeEnvironment
        self.hypervisor = hypervisor; self.osVersion = osVersion; self.osBuild = osBuild
        self.architecture = architecture; self.hostname = hostname; self.platformUUIDSHA256 = platformUUIDSHA256
    }
}
@_spi(Testing) public enum SyntheticDeclaredGuestPredicate {
    public static func matches(_ identity: SyntheticDeclaredGuestIdentity, profile: DisposableTargetProfile) -> Bool {
        GuestIdentityFacts(realUID: identity.realUID, effectiveUID: identity.effectiveUID, consoleUID: identity.consoleUID,
            accountName: identity.accountName, accountHome: identity.accountHome, homeEnvironment: identity.homeEnvironment,
            hypervisor: identity.hypervisor, osVersion: identity.osVersion, osBuild: identity.osBuild,
            architecture: identity.architecture, hostname: identity.hostname,
            platformUUIDSHA256: identity.platformUUIDSHA256).matches(profile)
    }
}

/// Pure comparison shared with the physically observing guard. It issues no
/// capability and cannot call that guard or open a runtime/native scope.
struct GuestIdentityFacts {
    let realUID: UInt32, effectiveUID: UInt32, consoleUID: UInt32
    let accountName: String, accountHome: String, homeEnvironment: String
    let hypervisor: Int32
    let osVersion: String, osBuild: String, architecture: String, hostname: String, platformUUIDSHA256: String
    func matches(_ profile: DisposableTargetProfile) -> Bool {
        realUID == profile.guestUID && effectiveUID == profile.guestUID && consoleUID == profile.guestUID &&
        accountName == profile.guestUser && accountHome == profile.guestHome && homeEnvironment == profile.guestHome &&
        hypervisor == 1 && osVersion == profile.guestOS && osBuild == profile.guestBuild &&
        architecture == profile.guestArchitecture && hostname == profile.guestHostname && platformUUIDSHA256 == profile.guestUUIDSHA256
    }
}
