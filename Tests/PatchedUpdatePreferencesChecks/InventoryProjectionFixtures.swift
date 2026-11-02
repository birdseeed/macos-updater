import Foundation
import PatchedScheduling
@_spi(Testing) import PatchedUpdatePreferences

// Independent test values and UTF8 comparisons; no candidate validator/policy computes expectations.
let ipDigest = String(repeating: "a", count: 64)
func ipIdentity(_ changes: [Int: String] = [:], id: String = "one", location: String = "/Applications/One.app") -> InventoryIdentity {
    var f = [id, "app", "user", "test.synthetic.app", "Synthetic Publisher", "standard", "stable", "arm64", location, "1", "10"]
    for (i, value) in changes { f[i] = value }
    return InventoryIdentity(instanceID: f[0], product: f[1], scope: f[2], bundleID: f[3], publisher: f[4],
        edition: f[5], channel: f[6], architecture: f[7], location: f[8], installedVersion: f[9], installedBuild: f[10])
}
func ipIdentityFields(_ i: InventoryIdentity) -> [String] {
    [i.instanceID, i.product, i.scope, i.bundleID, i.publisher, i.edition, i.channel, i.architecture, i.location, i.installedVersion, i.installedBuild]
}
func ipRelease(_ changes: [Int: String] = [:]) -> ReleaseIdentity {
    var f = ["app", "user", "2", "20", "standard", "stable", ipDigest]
    for (i, value) in changes { f[i] = value }
    return ReleaseIdentity(product: f[0], scope: f[1], release: f[2], build: f[3], edition: f[4], channel: f[5], artifact: f[6])
}
func ipReleaseFields(_ r: ReleaseIdentity) -> [String] { [r.product, r.scope, r.release, r.build, r.edition, r.channel, r.artifact] }
func ipExact(_ a: [String], _ b: [String]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { Array($0.0.utf8) == Array($0.1.utf8) }
}
func ipRow(_ identity: InventoryIdentity = ipIdentity(), name: String = "Synthetic One",
           running: InventoryRunningState = .closed, route: InventoryRoute = .unattended,
           managed: Bool = false, update: InventoryUpdateEvidence? = nil,
           release: ReleaseIdentity = ipRelease()) -> InventoryObservation {
    InventoryObservation(identity: identity, displayName: name, running: running, route: route, externallyManaged: managed,
        update: update ?? .syntheticAvailable(InventoryCandidate(identity: identity, release: release)))
}
func ipSnapshot(_ rows: [InventoryObservation] = [ipRow()], gen: UInt64 = 1, checked: UInt64 = 100,
                catalogue: InventoryCatalogueState = .fresh, principal: SchedulingPrincipal = owner) -> InventorySnapshot {
    InventorySnapshot(principal: principal, generation: gen, observedAt: checked, catalogue: catalogue, rows: rows)
}
func ipRequest(_ identity: InventoryIdentity = ipIdentity(), release: ReleaseIdentity = ipRelease(),
               gen: UInt64 = 1, rev: UInt64 = 0, principal: SchedulingPrincipal = owner) -> InventorySelectionRequest {
    InventorySelectionRequest(principal: principal, identity: identity, release: release, observedGeneration: gen, preferenceRevision: rev)
}
@MainActor final class IPSource: SyntheticInventorySource {
    var value: InventoryRead
    var calls = 0
    var limits: [Int] = []
    var duringRead: (() -> Void)?
    init(_ value: InventoryRead) { self.value = value }
    func read(maximumRows: Int) -> InventoryRead {
        calls += 1; limits.append(maximumRows)
        let callback = duringRead; duringRead = nil; callback?()
        return value
    }
}
@MainActor final class IPFixture {
    let source: IPSource
    let preferences: PreferenceSession
    let store: MemoryStore
    let coordinator: VerifiedUpdateCoordinator
    init(_ snapshot: InventorySnapshot = ipSnapshot(), bytes: Data = fixtureBytes(),
         configured: SchedulingPrincipal = owner, sessionGen: String = generation, load: Bool = true,
         preferencePrincipal: SchedulingPrincipal = owner, preferenceGeneration: String = generation) {
        source = IPSource(.snapshot(snapshot)); store = MemoryStore(bytes: bytes)
        preferences = session(store, principal: preferencePrincipal, gen: preferenceGeneration)
        if load { _ = preferences.reload(generation: preferenceGeneration) }
        coordinator = VerifiedUpdateCoordinator(source: source, preferences: preferences,
            principal: configured, sessionGeneration: sessionGen)
    }
    func refresh() -> InventoryRefreshResult { coordinator.refresh(principal: owner) }
}
func ipRefusal(_ result: InventorySelectionResult, _ reason: InventoryRefusal) -> Bool {
    if case .refused(let actual) = result { return actual == reason }; return false
}
func ipNoAuthority(_ p: InventoryProjection) throws {
    try require(p.isSynthetic && !p.nativeVerification && !p.installationAuthority, "projection native authority")
    try require(p.verifiedUpToDateCount == 0 && !p.allVerifiedUpToDate, "native up-to-date claim")
}
func ipVersions(_ a: [String?], _ b: [String?]) -> Bool {
    guard a.count == b.count else { return false }
    return zip(a, b).allSatisfy { left, right in
        switch (left, right) {
        case (nil, nil): return true
        case (.some(let x), .some(let y)): return ipExact([x], [y])
        default: return false
        }
    }
}
func ipRows(_ p: InventoryProjection, _ states: [InventoryAvailability], ids: [String], versions: [String?], excluded: [Bool]? = nil) throws {
    try require(p.applications.count == states.count && p.updates.count == states.count, "literal row count")
    try require(p.applications.map(\.availability) == states && p.updates.map(\.availability) == states, "literal availability/order")
    try require(ipExact(p.applications.map { $0.identity.instanceID }, ids), "literal instance/order")
    try require(ipVersions(p.applications.map(\.availableVersion), versions), "literal available versions")
    for (a, u) in zip(p.applications, p.updates) {
        try require(ipExact(ipIdentityFields(a.identity), ipIdentityFields(u.identity)), "screens identity bytes diverged")
        try require(ipExact([a.displayName], [u.displayName]) && ipVersions([a.availableVersion], [u.availableVersion]) && a.automaticExcluded == u.automaticExcluded, "screens values diverged")
    }
    if let excluded { try require(p.applications.map(\.automaticExcluded) == excluded, "literal exclusion annotation") }
    try ipNoAuthority(p)
}
func ipCounts(_ p: InventoryProjection, detected: Int, ready: Int = 0, running: Int = 0, attention: Int = 0,
              skipped: Int = 0, unknown: Int = 0, current: Int = 0, managed: Int = 0, excluded: Int = 0) throws {
    try require(p.detectedInstanceCount == detected && p.modelReadyCount == ready && p.deferredRunningCount == running &&
        p.attentionCount == attention && p.skippedCount == skipped && p.unknownCount == unknown &&
        p.syntheticCurrentCount == current && p.externallyManagedCount == managed && p.automaticExcludedCount == excluded,
        "literal partition/annotation counts")
    try ipNoAuthority(p)
}
