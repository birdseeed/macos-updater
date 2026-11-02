import Foundation
import PatchedScheduling
@_spi(Testing) import PatchedUpdatePreferences

@MainActor func ipContinuityChecks(_ c: Checks) {
    c.run("IP-P unchanged exact snapshot recomputes preferences and newer generation recovers") {
        let f = IPFixture()
        try require(f.refresh() == .accepted(generation: 1), "initial acceptance")
        try require(f.refresh() == .unchanged(generation: 1), "exact unchanged")
        try require(edit(f.preferences, .skip(ipRelease())) == .accepted(revision: 1), "preference edit fixture")
        try require(f.refresh() == .unchanged(generation: 1), "preference edit changed inventory generation")
        let p = f.coordinator.projection()
        try ipRows(p, [.skipped], ids: ["one"], versions: ["2"])
        try require(p.preferenceRevision == 1, "same generation stale preference projection")
        f.source.value = .snapshot(ipSnapshot(gen: 2, checked: UInt64.max))
        try require(f.refresh() == .accepted(generation: 2), "strictly newer")
        try require(f.coordinator.projection().syntheticLastChecked == UInt64.max, "clock overflow or arithmetic")
    }
    for mode in ["lower", "clock", "catalogue", "display", "order", "running", "route", "managed", "update", "rowCount"] {
        c.run("IP-N same-generation continuity drift \(mode) latches across restored bytes") {
            let second = ipIdentity([1: "second"], id: "two", location: "/Applications/Two.app")
            let original = ipSnapshot([ipRow(), ipRow(second, release: ipRelease([0: "second"]))], gen: 5)
            let f = IPFixture(original); _ = f.refresh()
            let first: InventoryObservation
            switch mode {
            case "display": first = ipRow(name: "Changed display")
            case "running": first = ipRow(running: .running)
            case "route": first = ipRow(route: .attention)
            case "managed": first = ipRow(managed: true)
            case "update": first = ipRow(update: .unknown)
            default: first = ipRow()
            }
            var rows = [first, ipRow(second, release: ipRelease([0: "second"]))]
            if mode == "order" { rows.reverse() }
            if mode == "rowCount" { rows.removeLast() }
            f.source.value = .snapshot(ipSnapshot(rows, gen: mode == "lower" ? 4 : 5,
                checked: mode == "clock" ? 101 : 100, catalogue: mode == "catalogue" ? .stale : .fresh))
            try require(f.refresh() == .refused(.generation), "drift accepted")
            let stale = f.coordinator.projection()
            try ipRows(stale, [.unknown, .unknown], ids: ["one", "two"], versions: ["2", "2"])
            try require(!stale.isFresh && stale.syntheticLastChecked == 100, "failed refresh stamped time")
            if mode != "lower" {
                f.source.value = .snapshot(original)
                try require(f.refresh() == .refused(.generation), "old bytes restored freshness")
            }
            f.source.value = .snapshot(ipSnapshot(original.rows, gen: 6, checked: 102))
            try require(f.refresh() == .accepted(generation: 6) && f.coordinator.projection().isFresh, "new generation did not recover")
        }
    }
    for field in 0..<11 {
        c.run("IP-N whole snapshot continuity includes identity field \(field)") {
            let f = IPFixture(); _ = f.refresh()
            let changed = ipIdentity([field: field == 8 ? "/Applications/Changed.app" : "changed"])
            // Unknown evidence isolates snapshot comparison from candidate-binding validation.
            let original = ipSnapshot([ipRow(update: .unknown)], gen: 2)
            f.source.value = .snapshot(original); _ = f.refresh()
            f.source.value = .snapshot(ipSnapshot([ipRow(changed, update: .unknown)], gen: 2))
            try require(f.refresh() == .refused(.generation), "identity drift omitted")
        }
    }
    for field in 0..<7 {
        c.run("IP-N whole snapshot continuity includes release field \(field)") {
            let f = IPFixture(); _ = f.refresh()
            let replacement = field == 6 ? String(repeating: "b", count: 64) : "changed"
            var identityChanges: [Int: String] = [:]
            if let identityField = [0: 1, 1: 2, 4: 5, 5: 6][field] { identityChanges[identityField] = replacement }
            let i = ipIdentity(identityChanges)
            f.source.value = .snapshot(ipSnapshot([ipRow(i, release: ipRelease([field: replacement]))]))
            try require(f.refresh() == .refused(.generation), "release drift omitted")
        }
    }
    for field in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] {
        c.run("IP-N continuity rejects canonical-equivalent identity bytes field \(field)") {
            let a = ipIdentity([field: field == 8 ? "/\u{e9}.app" : "\u{e9}"])
            let b = ipIdentity([field: field == 8 ? "/e\u{301}.app" : "e\u{301}"])
            let f = IPFixture(ipSnapshot([ipRow(a, update: .unknown)])); _ = f.refresh()
            f.source.value = .snapshot(ipSnapshot([ipRow(b, update: .unknown)]))
            try require(f.refresh() == .refused(.generation), "snapshot normalised identity bytes")
        }
    }
    c.run("IP-N continuity includes exact Unicode display bytes") {
        let f = IPFixture(ipSnapshot([ipRow(name: "\u{e9}")])); _ = f.refresh()
        f.source.value = .snapshot(ipSnapshot([ipRow(name: "e\u{301}")]))
        try require(f.refresh() == .refused(.generation), "snapshot normalised display bytes")
    }
    for field in [0,1,2,3,4,5] {
        c.run("IP-N continuity includes exact Unicode release bytes field \(field)") {
            let mapping = [0: 1, 1: 2, 4: 5, 5: 6]
            let a = ipIdentity(mapping[field].map { [$0: "\u{e9}"] } ?? [:])
            let b = ipIdentity(mapping[field].map { [$0: "e\u{301}"] } ?? [:])
            let f = IPFixture(ipSnapshot([ipRow(a, release: ipRelease([field: "\u{e9}"]))])); _ = f.refresh()
            f.source.value = .snapshot(ipSnapshot([ipRow(b, release: ipRelease([field: "e\u{301}"]))]))
            try require(f.refresh() == .refused(.generation), "snapshot normalised release bytes")
        }
    }
    c.run("IP-N unavailable and malformed refresh retain old rows unknown and old clock") {
        let f = IPFixture(); _ = f.refresh(); f.source.value = .unavailable
        try require(f.refresh() == .refused(.unavailable), "source unavailable accepted")
        var p = f.coordinator.projection()
        try ipRows(p, [.unknown], ids: ["one"], versions: ["2"]); try ipCounts(p, detected: 1, unknown: 1)
        try require(!p.isFresh && p.syntheticLastChecked == 100, "unavailable stamp")
        f.source.value = .snapshot(ipSnapshot([ipRow(ipIdentity([0: "bad/id"]))], gen: 2, checked: 999))
        try require(f.refresh() == .refused(.identity), "malformed refresh accepted")
        p = f.coordinator.projection()
        try require(!p.isFresh && p.syntheticLastChecked == 100 && p.modelReadyCount == 0 && p.syntheticCurrentCount == 0, "malformed new checked time")
        let empty = IPFixture(); empty.source.value = .unavailable; _ = empty.refresh()
        try ipRows(empty.coordinator.projection(), [], ids: [], versions: [])
    }
    for unavailable in [false, true] {
        c.run("IP-N failed refresh invalidates retained managed and current rows \(unavailable)") {
            let current = ipIdentity([1: "current"], id: "current", location: "/Current.app")
            let managed = ipIdentity([1: "managed"], id: "managed", location: "/Managed.app")
            let f = IPFixture(ipSnapshot([ipRow(), ipRow(current, update: .syntheticCurrent(current)),
                ipRow(managed, managed: true, release: ipRelease([0: "managed"]))]))
            try require(f.refresh() == .accepted(generation: 1), "retained state fixture")
            try ipRows(f.coordinator.projection(), [.syntheticReady, .syntheticCurrent, .externalManaged],
                ids: ["one", "current", "managed"], versions: ["2", nil, "2"])
            f.source.value = unavailable ? .unavailable : .snapshot(ipSnapshot([ipRow(ipIdentity([0: "bad/id"]))], gen: 2, checked: 999))
            try require(f.refresh() == .refused(unavailable ? .unavailable : .identity), "failed input accepted")
            let p = f.coordinator.projection()
            try ipRows(p, [.unknown, .unknown, .unknown], ids: ["one", "current", "managed"], versions: ["2", nil, "2"])
            try ipCounts(p, detected: 3, unknown: 3)
            try require(!p.isFresh && p.syntheticLastChecked == 100, "failed managed/current claimed freshness")
            try require(f.store.reads == 1 && f.store.writes == 0, "failed managed/current storage effects")
        }
    }
    c.run("IP-N caller principal refuses before source and preserves owner projection") {
        let f = IPFixture(); _ = f.refresh(); let calls = f.source.calls
        for bad in ["", "other", String(repeating: "x", count: 257), "synthetic-owner\u{0}"] {
            try require(f.coordinator.refresh(principal: SchedulingPrincipal(bad)) == .refused(.principal), "bad caller principal")
            try require(ipRefusal(f.coordinator.select(ipRequest(principal: SchedulingPrincipal(bad))), .principal), "bad select principal")
        }
        try require(f.source.calls == calls, "wrong caller touched source")
        try require(f.coordinator.projection().isFresh && f.coordinator.projection().modelReadyCount == 1, "wrong caller invalidated owner")
    }
    for (configured, requested) in [("\u{e9}", "e\u{301}"), ("e\u{301}", "\u{e9}")] {
        c.run("IP-N principal Unicode alias is not owner identity \(configured.utf8.count)") {
            let f = IPFixture(ipSnapshot(principal: SchedulingPrincipal(configured)), configured: SchedulingPrincipal(configured))
            try require(f.coordinator.refresh(principal: SchedulingPrincipal(requested)) == .refused(.principal), "canonical-equivalent caller accepted")
            try require(f.source.calls == 0, "Unicode caller reached source")
        }
    }
    for bad in ["", String(repeating: "x", count: 257), "bad\n"] {
        c.run("IP-N invalid configured principal and session generation \(bad.utf8.count)") {
            let principalFixture = IPFixture(configured: SchedulingPrincipal(bad))
            try require(principalFixture.refresh() == .refused(.principal) && principalFixture.source.calls == 0, "bad configured principal source call")
            let generationFixture = IPFixture(sessionGen: bad)
            try require(generationFixture.refresh() == .refused(.generation) && generationFixture.source.calls == 0, "bad configured generation source call")
        }
    }
    c.run("IP-N source principal drift invalidates old freshness") {
        let f = IPFixture(); _ = f.refresh()
        f.source.value = .snapshot(ipSnapshot(gen: 2, checked: 200, principal: SchedulingPrincipal("other")))
        try require(f.refresh() == .refused(.principal), "source owner changed")
        let p = f.coordinator.projection()
        try ipRows(p, [.unknown], ids: ["one"], versions: ["2"])
        try require(!p.isFresh && p.syntheticLastChecked == 100, "source owner drift kept freshness")
    }
    c.run("IP-N recursive source refresh and select refuse without recursive reads") {
        let f = IPFixture(); var refresh: InventoryRefreshResult?; var selection: InventorySelectionResult?
        f.source.duringRead = {
            refresh = f.coordinator.refresh(principal: owner)
            selection = f.coordinator.select(ipRequest())
        }
        try require(f.refresh() == .accepted(generation: 1), "outer refresh failed")
        try require(refresh == .refused(.reentrant), "recursive refresh")
        try require(selection.map { ipRefusal($0, .reentrant) } == true && f.source.calls == 1, "recursive source selection")
        try require(f.coordinator.projection().isFresh, "reentry invalidated outer owner")
    }
}
