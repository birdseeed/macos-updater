/// Inert display facts. No case is verified evidence or installation permission.
public enum LicenceDisplayState: String, CaseIterable, Sendable {
    case anonymous, signedIn, beta, trial, paid, grace, expired, revoked, verificationRequired, outage
}
public enum LicenceIntent: String, Equatable, Sendable { case signIn, startTrial, refresh, manageMacs }
public enum DisplayTrialAvailability: Sendable { case unknown, eligible, used, betaActive }
public struct LicenceDisplayInput: Sendable {
    public var state: LicenceDisplayState
    public var trial: DisplayTrialAvailability
    public var accountLabel: String
    public init(state: LicenceDisplayState = .anonymous, trial: DisplayTrialAvailability = .unknown,
                accountLabel: String = "") {
        self.state = state; self.trial = trial; self.accountLabel = accountLabel
    }
}
/// Display only; intents must be re-authorised by the eventual command boundary.
public struct LicencePresentation: Equatable, Sendable {
    public let state: LicenceDisplayState
    public let accountLabel: String
    public let intents: [LicenceIntent]
    public let discoveryVisible: Bool
    public let selfUpdateVisible: Bool
    public let recoveryVisible: Bool
    public static func make(_ input: LicenceDisplayInput = .init()) -> Self {
        var intents: [LicenceIntent] = input.state == .anonymous ? [.signIn] : [.refresh, .manageMacs]
        if input.state == .signedIn && input.trial == .eligible { intents.insert(.startTrial, at: 0) }
        return Self(state: input.state, accountLabel: boundedLicenceLabel(input.accountLabel), intents: intents,
                    discoveryVisible: true, selfUpdateVisible: true, recoveryVisible: true)
    }
}

// Bound work as well as output, preserving literal characters within the ceiling.
private func boundedLicenceLabel(_ value: String) -> String {
    guard value.utf8.prefix(16_385).count <= 16_384 else { return "Label too long" }
    var result = ""
    var lines = 1
    var count = 0
    for character in value {
        if count == 240 || (character.isNewline && lines == 3) { return result + "…" }
        if character.isNewline { lines += 1 }
        result.append(character)
        count += 1
    }
    return result
}
