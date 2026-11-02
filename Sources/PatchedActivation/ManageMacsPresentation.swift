/// Inert UI facts, never a session, allocation request or device credential.
public enum MacDisplayStatus: String, Sendable { case active, released }
public enum MacManagementSession: Sendable { case unavailable, current, stale, terminalOnly }
public struct MacDisplayFact: Sendable {
    public var opaqueID: String
    public var accountID: String
    public var label: String
    public var revision: UInt64
    public var status: MacDisplayStatus
    public init(opaqueID: String, accountID: String, label: String, revision: UInt64 = 1,
                status: MacDisplayStatus = .active) {
        self.opaqueID = opaqueID; self.accountID = accountID; self.label = label
        self.revision = revision; self.status = status
    }
}
public struct ManageMacsInput: Sendable {
    public var session: MacManagementSession
    public var accountID: String
    public var localActivationID: String?
    public var facts: [MacDisplayFact]
    public var snapshotRevision: UInt64
    public var currentRevision: UInt64
    public init(session: MacManagementSession = .unavailable, accountID: String = "",
                localActivationID: String? = nil, facts: [MacDisplayFact] = [],
                snapshotRevision: UInt64 = 0, currentRevision: UInt64 = 0) {
        self.session = session; self.accountID = accountID; self.localActivationID = localActivationID
        self.facts = facts; self.snapshotRevision = snapshotRevision; self.currentRevision = currentRevision
    }
}
public enum MacIntentKind: String, Equatable, Sendable { case rename, confirmDeactivation, confirmReplacement }
/// A selection for confirmation only. It cannot execute a mutation or allocate a slot.
public struct MacDisplayIntent: Equatable, Sendable {
    public let kind: MacIntentKind
    public let opaqueID: String
    public let expectedRevision: UInt64
    public let snapshotRevision: UInt64
}
public struct MacDisplayRow: Equatable, Sendable {
    public let opaqueID: String
    public let label: String
    public let isThisMac: Bool
    public let status: MacDisplayStatus
    public let intents: [MacDisplayIntent]
}
public struct ManageMacsPresentation: Equatable, Sendable {
    public let rows: [MacDisplayRow]
    public let activeCount: Int
    public let limitReached: Bool
    public let needsVerification: Bool
    public static func make(_ input: ManageMacsInput = .init()) -> Self {
        let refused = Self(rows: [], activeCount: 0, limitReached: false, needsVerification: true)
        guard input.session == .current, !input.accountID.isEmpty,
              input.snapshotRevision > 0, input.snapshotRevision == input.currentRevision,
              input.facts.count <= 50,
              input.localActivationID.map(validDisplayID) ?? true else { return refused }
        var seen = Set<String>()
        for fact in input.facts {
            guard fact.accountID == input.accountID, fact.revision > 0,
                  validDisplayID(fact.opaqueID), seen.insert(fact.opaqueID).inserted else { return refused }
        }
        let activeCount = input.facts.filter { $0.status == .active }.count
        guard activeCount <= 5 else { return refused }
        let baseLabels = input.facts.map { boundedMacLabel($0.label) }
        let counts = Dictionary(grouping: baseLabels, by: { $0 }).mapValues { $0.count }
        func identifiedLabel(_ index: Int) -> String {
            // Reserve space for the complete identifier, including punctuation.
            boundedMacLabel(input.facts[index].label, limit: 204) + " (" + input.facts[index].opaqueID + ")"
        }
        var labels = baseLabels.enumerated().map { index, label in
            counts[label, default: 0] > 1 ? identifiedLabel(index) : label
        }
        // A literal unique name might equal a generated duplicate-name label.
        // Disambiguate every row if that occurs, still binding actions only to IDs.
        if Set(labels).count != labels.count { labels = input.facts.indices.map(identifiedLabel) }
        let rows = input.facts.enumerated().map { index, fact in
            let kinds: [MacIntentKind] = fact.status == .released ? [] :
                ([.rename, .confirmDeactivation] + (activeCount == 5 ? [.confirmReplacement] : []))
            return MacDisplayRow(opaqueID: fact.opaqueID, label: labels[index],
                                 isThisMac: fact.opaqueID == input.localActivationID, status: fact.status,
                                 intents: kinds.map { MacDisplayIntent(kind: $0, opaqueID: fact.opaqueID,
                                     expectedRevision: fact.revision, snapshotRevision: input.snapshotRevision) })
        }
        return Self(rows: rows, activeCount: activeCount, limitReached: activeCount == 5, needsVerification: false)
    }
}

private func validDisplayID(_ value: String) -> Bool {
    let bytes = Array(value.utf8.prefix(33))
    return bytes.count == 32 && bytes.contains(where: { $0 != 48 }) &&
        bytes.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
}
private func boundedMacLabel(_ value: String, limit: Int = 240) -> String {
    guard value.utf8.prefix(16_385).count <= 16_384 else { return "Label too long" }
    var result = ""
    var lines = 1
    var count = 0
    for character in value {
        if count == limit || (character.isNewline && lines == 3) { return result + "…" }
        if character.isNewline { lines += 1 }
        result.append(character)
        count += 1
    }
    return result
}
