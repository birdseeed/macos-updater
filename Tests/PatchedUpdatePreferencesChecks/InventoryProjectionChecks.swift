import Foundation
import PatchedScheduling
@_spi(Testing) import PatchedUpdatePreferences

@MainActor func inventoryProjectionChecks(_ c: Checks) {
    c.run("IP-S fixtures are independent literal synthetic bytes", setup: true) {
        let f = IPFixture()
        try require(f.preferences.acceptedRevision == 0 && f.preferences.blockedReason == nil, "existing preference fixture")
        try require(f.store.reads == 1 && f.store.writes == 0 && f.source.calls == 0, "fixture effects")
        try require(!ipExact(["\u{e9}"], ["e\u{301}"]) && "\u{e9}" == "e\u{301}", "Unicode alias control")
        try require(ipIdentityFields(ipIdentity()).count == 11 && ipReleaseFields(ipRelease()).count == 7, "fixture field count")
        try require(ipDigest.utf8.count == 64 && ipDigest == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "literal digest")
    }
    c.run("IP-N default composition permanently refuses without a source") {
        let v = VerifiedUpdateCoordinator()
        try require(v.refresh(principal: owner) == .refused(.unavailable), "default refresh")
        try require(ipRefusal(v.select(ipRequest()), .unavailable), "default select")
        for kind in [StartKind.manual, .updateAll, .automatic, .loginWindow] {
            try require(ipRefusal(v.requestStart(ipRequest(), kind: kind), .unavailable), "default start")
        }
        let p = v.projection()
        try ipRows(p, [], ids: [], versions: [])
        try ipCounts(p, detected: 0)
        try require(!p.isFresh && p.generation == nil && p.preferenceRevision == nil && p.syntheticLastChecked == nil, "default accepted metadata")
    }
    c.run("IP-P fresh available publishes exact shared rows and synthetic selection") {
        let f = IPFixture(); let reads = f.store.reads
        try require(f.refresh() == .accepted(generation: 1), "valid inventory refused")
        try require(f.source.calls == 1 && f.source.limits == [512], "source row bound")
        let p = f.coordinator.projection()
        try ipRows(p, [.syntheticReady], ids: ["one"], versions: ["2"], excluded: [false])
        try ipCounts(p, detected: 1, ready: 1)
        try require(p.isFresh && p.generation == 1 && p.preferenceRevision == 0 && p.syntheticLastChecked == 100, "accepted metadata")
        try require(ipExact(ipIdentityFields(p.applications[0].identity), ipIdentityFields(ipIdentity())) && p.applications[0].displayName == "Synthetic One", "identity/display loss")
        guard case .selected(let s) = f.coordinator.select(ipRequest()) else { throw CheckFailure(message: "valid selection refused") }
        try require(s.isSynthetic && !s.nativeVerification && !s.installationAuthority, "selection authority")
        try require(ipExact(ipIdentityFields(s.identity), ipIdentityFields(ipIdentity())) && ipExact(ipReleaseFields(s.release), ipReleaseFields(ipRelease())), "selection binding")
        try require(s.observedGeneration == 1 && s.preferenceRevision == 0 && f.source.calls == 2, "selection did not refresh")
        try require(f.store.reads == reads && f.store.writes == 0, "read-only projection/selection touched store")
    }
    c.run("IP-P empty success and nonempty current never claim native completion") {
        let f = IPFixture(ipSnapshot([]))
        try require(f.refresh() == .accepted(generation: 1), "empty valid snapshot")
        let empty = f.coordinator.projection()
        try ipRows(empty, [], ids: [], versions: []); try ipCounts(empty, detected: 0)
        try require(empty.isFresh && empty.syntheticLastChecked == 100, "empty synthetic check missing")
        f.source.value = .snapshot(ipSnapshot([ipRow(update: .syntheticCurrent(ipIdentity()))], gen: 2))
        try require(f.refresh() == .accepted(generation: 2), "current snapshot")
        let p = f.coordinator.projection()
        try ipRows(p, [.syntheticCurrent], ids: ["one"], versions: [nil]); try ipCounts(p, detected: 1, current: 1)
    }
    c.run("IP-P all availability states have literal partition counts") {
        func i(_ n: Int) -> InventoryIdentity { ipIdentity([1: "app\(n)"], id: "r\(n)", location: "/Applications/R\(n).app") }
        func r(_ n: Int) -> ReleaseIdentity { ipRelease([0: "app\(n)"]) }
        let rows = [ipRow(i(1), release: r(1)), ipRow(i(2), running: .running, release: r(2)),
            ipRow(i(3), route: .attention, release: r(3)), ipRow(i(4), release: r(4)),
            ipRow(i(5), update: .unknown), ipRow(i(6), update: .syntheticCurrent(i(6))),
            ipRow(i(7), managed: true, release: r(7))]
        let f = IPFixture(ipSnapshot(rows), bytes: fixtureBytes(exclusions: [PreferenceAppKey(r(1))], skips: [r(4)]))
        try require(f.refresh() == .accepted(generation: 1), "matrix snapshot")
        let p = f.coordinator.projection()
        try ipRows(p, [.syntheticReady, .deferredRunning, .attention, .skipped, .unknown, .syntheticCurrent, .externalManaged],
            ids: ["r1", "r2", "r3", "r4", "r5", "r6", "r7"], versions: ["2", "2", "2", "2", nil, nil, "2"],
            excluded: [true, false, false, false, false, false, false])
        try ipCounts(p, detected: 7, ready: 1, running: 1, attention: 1, skipped: 1, unknown: 1, current: 1, managed: 1, excluded: 1)
    }
    let precedence: [(String, InventoryRunningState, InventoryRoute, InventoryAvailability)] = [
        ("running wins attention", .running, .attention, .deferredRunning),
        ("unknown running", .unknown, .attention, .unknown),
        ("unknown route", .closed, .unknown, .unknown), ("attention route", .closed, .attention, .attention)]
    for (label, running, route, expected) in precedence {
        c.run("IP-P precedence \(label)") {
            let f = IPFixture(ipSnapshot([ipRow(running: running, route: route)])); _ = f.refresh()
            try ipRows(f.coordinator.projection(), [expected], ids: ["one"], versions: ["2"])
        }
    }
    for catalogue in [InventoryCatalogueState.stale, .offline, .missing] {
        c.run("IP-P nonfresh catalogue \(catalogue) retains rows as unknown") {
            let f = IPFixture(ipSnapshot([ipRow()], catalogue: catalogue)); _ = f.refresh()
            let p = f.coordinator.projection()
            try ipRows(p, [.unknown], ids: ["one"], versions: ["2"]); try ipCounts(p, detected: 1, unknown: 1)
            try require(!p.isFresh && ipRefusal(f.coordinator.select(ipRequest()), .notReady), "nonfresh ready selection")
        }
        c.run("IP-P external management precedes nonfresh catalogue \(catalogue)") {
            let f = IPFixture(ipSnapshot([ipRow(managed: true)], catalogue: catalogue)); _ = f.refresh()
            try ipRows(f.coordinator.projection(), [.externalManaged], ids: ["one"], versions: ["2"])
            try ipCounts(f.coordinator.projection(), detected: 1, managed: 1)
        }
    }
    c.run("IP-P duplicate copies are conservative attention and distinct products remain ready") {
        let two = ipIdentity(id: "two", location: "/Users/Synthetic/One.app")
        let three = ipIdentity([1: "other"], id: "three", location: "/Applications/Three.app")
        let f = IPFixture(ipSnapshot([ipRow(), ipRow(two), ipRow(three, release: ipRelease([0: "other"]))]))
        try require(f.refresh() == .accepted(generation: 1), "multiple copies rejected")
        try ipRows(f.coordinator.projection(), [.attention, .attention, .syntheticReady], ids: ["one", "two", "three"], versions: ["2", "2", "2"])
        try ipCounts(f.coordinator.projection(), detected: 3, ready: 1, attention: 2)
        try require(ipRefusal(f.coordinator.select(ipRequest()), .notReady), "ambiguous copy selected")
    }
    for field in [1, 2, 3, 4, 5, 6, 7] {
        c.run("IP-P duplicate grouping binds UTF8 field \(field)") {
            let a = ipIdentity([field: "\u{e9}"], id: "a", location: "/Applications/A.app")
            let b = ipIdentity([field: "e\u{301}"], id: "b", location: "/Applications/B.app")
            let f = IPFixture(ipSnapshot([ipRow(a, update: .syntheticCurrent(a)), ipRow(b, update: .syntheticCurrent(b))]))
            try require(f.refresh() == .accepted(generation: 1), "Unicode input refused")
            try ipRows(f.coordinator.projection(), [.syntheticCurrent, .syntheticCurrent], ids: ["a", "b"], versions: [nil, nil])
        }
    }
    ipContinuityChecks(c)
    ipMalformedContinuityChecks(c)
    ipBindingChecks(c)
    ipBoundsChecks(c)
    ipPreferenceChecks(c)
    ipSelectionChecks(c)
}
