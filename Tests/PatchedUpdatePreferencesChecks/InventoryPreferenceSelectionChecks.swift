import Foundation
import PatchedScheduling
@_spi(Testing) import PatchedUpdatePreferences

@MainActor func ipPreferenceChecks(_ c: Checks) {
    c.run("IP-P exact skip and undo use existing sole preference owner") {
        let f = IPFixture(bytes: fixtureBytes(skips: [ipRelease()]))
        _ = f.refresh()
        try ipRows(f.coordinator.projection(), [.skipped], ids: ["one"], versions: ["2"])
        try require(ipRefusal(f.coordinator.select(ipRequest()), .notReady), "skipped selected")
        try require(edit(f.preferences, .undo(ipRelease())) == .accepted(revision: 1), "undo fixture")
        let calls = f.source.calls; let reads = f.store.reads; let writes = f.store.writes
        let p = f.coordinator.projection()
        try ipRows(p, [.syntheticReady], ids: ["one"], versions: ["2"]); try ipCounts(p, detected: 1, ready: 1)
        try require(p.preferenceRevision == 1 && f.source.calls == calls && f.store.reads == reads && f.store.writes == writes, "projection must read accepted preference state only")
    }
    for field in 0..<7 {
        c.run("IP-P existing skip owner semantics for changed release field \(field)") {
            let replacement = field == 6 ? String(repeating: "b", count: 64) : "different"
            let mapping = [0: 1, 1: 2, 4: 5, 5: 6]
            let identity = ipIdentity(mapping[field].map { [$0: replacement] } ?? [:])
            let f = IPFixture(ipSnapshot([ipRow(identity, release: ipRelease([field: replacement]))]), bytes: fixtureBytes(skips: [ipRelease()]))
            try require(f.refresh() == .accepted(generation: 1), "valid skip variant")
            let expected: InventoryAvailability = field == 3 || field == 6 ? .unknown : .syntheticReady
            try ipRows(f.coordinator.projection(), [expected], ids: ["one"], versions: [field == 2 ? "different" : "2"])
        }
    }
    c.run("IP-P exclusions annotate manual model readiness without subtracting count") {
        let f = IPFixture(bytes: fixtureBytes(exclusions: [PreferenceAppKey(ipRelease())])); _ = f.refresh()
        let p = f.coordinator.projection()
        try ipRows(p, [.syntheticReady], ids: ["one"], versions: ["2"], excluded: [true]); try ipCounts(p, detected: 1, ready: 1, excluded: 1)
        guard case .selected = f.coordinator.select(ipRequest()) else { throw CheckFailure(message: "manual display selection excluded") }
        try require(edit(f.preferences, .exclusion(PreferenceAppKey(ipRelease()), false)) == .accepted(revision: 1), "remove exclusion")
        try ipRows(f.coordinator.projection(), [.syntheticReady], ids: ["one"], versions: ["2"], excluded: [false])
    }
    c.run("IP-P unknown and skipped precede running and attention") {
        let f = IPFixture(ipSnapshot([ipRow(running: .running, route: .attention)]), bytes: fixtureBytes(skips: [ipRelease()]))
        _ = f.refresh(); try ipRows(f.coordinator.projection(), [.skipped], ids: ["one"], versions: ["2"])
        f.source.value = .snapshot(ipSnapshot([ipRow(running: .running, route: .attention, release: ipRelease([3: "changed"]))], gen: 2))
        _ = f.refresh(); try ipRows(f.coordinator.projection(), [.unknown], ids: ["one"], versions: ["2"])
    }
    c.run("IP-P unaccepted preferences hide ready rows and refuse selection") {
        let f = IPFixture(load: false); _ = f.refresh()
        try ipRows(f.coordinator.projection(), [.unknown], ids: ["one"], versions: ["2"])
        try require(f.coordinator.projection().preferenceRevision == nil, "invented revision")
        try require(ipRefusal(f.coordinator.select(ipRequest()), .preferences), "missing preference owner selection")
        try require(f.store.reads == 0 && f.store.writes == 0, "coordinator reloaded preferences")
    }
    c.run("IP-P blocked accepted preference owner invalidates prior ready projection without source read") {
        let f = IPFixture(); _ = f.refresh()
        f.store.bytes = Data("malformed".utf8)
        try require(f.preferences.reload(generation: generation) == .refused(.malformed), "block preference fixture")
        let calls = f.source.calls; let reads = f.store.reads
        let p = f.coordinator.projection()
        try ipRows(p, [.unknown], ids: ["one"], versions: ["2"]); try ipCounts(p, detected: 1, unknown: 1)
        try require(f.source.calls == calls && f.store.reads == reads && f.store.writes == 0, "blocked projection did IO")
        try require(ipRefusal(f.coordinator.select(ipRequest()), .preferences), "blocked owner selected")
    }
    c.run("IP-N wrong valid configured session generation refuses before source") {
        let f = IPFixture(sessionGen: "different-valid-generation")
        try require(f.refresh() == .refused(.preferences), "unbound session generation")
        try require(ipRefusal(f.coordinator.select(ipRequest()), .preferences), "unbound session selection")
        try require(f.source.calls == 0 && f.store.reads == 1 && f.store.writes == 0, "unbound owner effects")
        try ipRows(f.coordinator.projection(), [], ids: [], versions: [])
    }
    c.run("IP-N different accepted preference principal refuses before source") {
        let f = IPFixture(bytes: fixtureBytes(principal: "different-owner"), preferencePrincipal: SchedulingPrincipal("different-owner"))
        try require(f.refresh() == .refused(.preferences), "another preference owner accepted")
        try require(ipRefusal(f.coordinator.select(ipRequest()), .preferences), "another preference owner selected")
        try require(f.source.calls == 0 && f.store.reads == 1 && f.store.writes == 0, "different owner effects")
        try ipRows(f.coordinator.projection(), [], ids: [], versions: [])
    }
    for matching in [false, true] {
        c.run("IP-\(matching ? "P" : "N") preference principal owner binds exact Unicode bytes \(matching)") {
            let composed = SchedulingPrincipal("\u{e9}")
            let preferenceOwner = SchedulingPrincipal(matching ? "\u{e9}" : "e\u{301}")
            let f = IPFixture(ipSnapshot(principal: composed), bytes: fixtureBytes(principal: preferenceOwner.value),
                configured: composed, preferencePrincipal: preferenceOwner)
            let result = f.coordinator.refresh(principal: composed)
            try require(result == (matching ? .accepted(generation: 1) : .refused(.preferences)), "preference principal Unicode binding")
            try require(f.source.calls == (matching ? 1 : 0), "Unicode owner source effects")
            if matching { try ipRows(f.coordinator.projection(), [.syntheticReady], ids: ["one"], versions: ["2"]) }
            else { try ipRows(f.coordinator.projection(), [], ids: [], versions: []) }
        }
    }
    for matching in [false, true] {
        c.run("IP-\(matching ? "P" : "N") preference session generation binds exact Unicode bytes \(matching)") {
            let f = IPFixture(sessionGen: "\u{e9}", preferenceGeneration: matching ? "\u{e9}" : "e\u{301}")
            try require(f.refresh() == (matching ? .accepted(generation: 1) : .refused(.preferences)), "session generation Unicode binding")
            try require(f.source.calls == (matching ? 1 : 0), "session generation binding effects")
        }
    }
    c.run("IP-P configured principal and session generation256bytes accept exact bound owner") {
        let name = String(repeating: "p", count: 256); let gen = String(repeating: "g", count: 256)
        let principal = SchedulingPrincipal(name)
        let f = IPFixture(ipSnapshot(principal: principal), bytes: fixtureBytes(principal: name), configured: principal,
            sessionGen: gen, preferencePrincipal: principal, preferenceGeneration: gen)
        try require(f.coordinator.refresh(principal: principal) == .accepted(generation: 1), "maximum bound owner rejected")
        try ipRows(f.coordinator.projection(), [.syntheticReady], ids: ["one"], versions: ["2"])
    }
    c.run("IP-P accepted preference owner emits one exact candidate ID per inventory instance") {
        let ids = ["a", "b", "c"]
        let rows = ids.enumerated().map { index, id -> InventoryObservation in
            let i = ipIdentity([1: "product\(index)"], id: id, location: "/\(id).app")
            return ipRow(i, release: ipRelease([0: "product\(index)"]))
        }
        let f = IPFixture(ipSnapshot(rows)); _ = f.refresh()
        try ipRows(f.coordinator.projection(), [.syntheticReady, .syntheticReady, .syntheticReady], ids: ids, versions: ["2", "2", "2"])
        try ipCounts(f.coordinator.projection(), detected: 3, ready: 3)
    }
}

@MainActor func ipSelectionChecks(_ c: Checks) {
    for field in 0..<11 {
        c.run("IP-N selection exact identity all11 field \(field)") {
            let f = IPFixture(); _ = f.refresh()
            let i = ipIdentity([field: field == 8 ? "/Applications/Else.app" : "different"])
            try require(ipRefusal(f.coordinator.select(ipRequest(i)), .identity), "identity field bypass")
            try require(f.source.calls == 2 && f.store.reads == 1 && f.store.writes == 0, "selection wrong effect budget")
        }
    }
    for field in 0..<7 {
        c.run("IP-N selection exact release all7 field \(field)") {
            let f = IPFixture(); _ = f.refresh()
            let replacement = field == 6 ? String(repeating: "b", count: 64) : "different"
            try require(ipRefusal(f.coordinator.select(ipRequest(release: ipRelease([field: replacement]))), .identity), "release field bypass")
        }
    }
    for field in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] {
        c.run("IP-N selection rejects canonical-equivalent identity field \(field)") {
            let a = ipIdentity([field: field == 8 ? "/\u{e9}.app" : "\u{e9}"])
            let b = ipIdentity([field: field == 8 ? "/e\u{301}.app" : "e\u{301}"])
            let mapping = [1: 0, 2: 1, 5: 4, 6: 5]
            let r = ipRelease(mapping[field].map { [$0: "\u{e9}"] } ?? [:])
            let f = IPFixture(ipSnapshot([ipRow(a, release: r)])); _ = f.refresh()
            try require(ipRefusal(f.coordinator.select(ipRequest(b, release: r)), .identity), "Unicode identity selection alias")
        }
    }
    for field in [0, 1, 2, 3, 4, 5] {
        c.run("IP-N selection rejects canonical-equivalent release field \(field)") {
            let mapping = [0: 1, 1: 2, 4: 5, 5: 6]
            let i = ipIdentity(mapping[field].map { [$0: "\u{e9}"] } ?? [:])
            let f = IPFixture(ipSnapshot([ipRow(i, release: ipRelease([field: "\u{e9}"]))])); _ = f.refresh()
            try require(ipRefusal(f.coordinator.select(ipRequest(i, release: ipRelease([field: "e\u{301}"]))), .identity), "Unicode release selection alias")
        }
    }
    for (gen, rev) in [(UInt64(0), UInt64(0)), (2, 0), (1, 1), (UInt64.max, UInt64.max)] {
        c.run("IP-N stale selection generation\(gen) revision\(rev)") {
            let f = IPFixture(); _ = f.refresh()
            try require(ipRefusal(f.coordinator.select(ipRequest(gen: gen, rev: rev)), .staleSelection), "stale request")
        }
    }
    c.run("IP-N preference edit makes prior selection stale and new revision can select") {
        let f = IPFixture(); _ = f.refresh()
        try require(edit(f.preferences, .exclusion(PreferenceAppKey(ipRelease()), true)) == .accepted(revision: 1), "revision fixture")
        try require(ipRefusal(f.coordinator.select(ipRequest()), .staleSelection), "old preference revision selected")
        guard case .selected(let selected) = f.coordinator.select(ipRequest(rev: 1)) else { throw CheckFailure(message: "current preference revision refused") }
        try require(selected.preferenceRevision == 1, "selection retained old revision")
    }
    for drift in ["generation", "candidate", "location", "principal", "unavailable"] {
        c.run("IP-N select refresh observes current source \(drift) drift") {
            let f = IPFixture(); _ = f.refresh()
            switch drift {
            case "generation": f.source.value = .snapshot(ipSnapshot(gen: 2))
            case "candidate": f.source.value = .snapshot(ipSnapshot([ipRow(release: ipRelease([2: "3"]))], gen: 2))
            case "location": f.source.value = .snapshot(ipSnapshot([ipRow(ipIdentity([8: "/Else.app"]))], gen: 2))
            case "principal": f.source.value = .snapshot(ipSnapshot(gen: 2, principal: SchedulingPrincipal("other")))
            default: f.source.value = .unavailable
            }
            let result = f.coordinator.select(ipRequest())
            let expected: InventoryRefusal = drift == "principal" ? .principal : drift == "unavailable" ? .unavailable : .staleSelection
            try require(ipRefusal(result, expected), "stale source selected")
            try require(f.source.calls == 2, "selection failed to refresh")
        }
    }
    for mode in ["unknown", "running", "attention", "managed", "current"] {
        c.run("IP-N nonready \(mode) is never selected") {
            let row: InventoryObservation
            switch mode {
            case "running": row = ipRow(running: .running)
            case "attention": row = ipRow(route: .attention)
            case "managed": row = ipRow(managed: true)
            case "current": row = ipRow(update: .syntheticCurrent(ipIdentity()))
            default: row = ipRow(update: .unknown)
            }
            let f = IPFixture(ipSnapshot([row])); _ = f.refresh()
            try require(ipRefusal(f.coordinator.select(ipRequest()), .notReady), "nonready selection")
        }
    }
    for phase in ["pending", "running", "recovering"] {
        c.run("IP-N requestStart every kind has zero effects and preserves \(phase) queue") {
            let f = IPFixture()
            try require(enqueue(f.preferences, ipRelease()), "queue seed")
            if phase != "pending" {
                guard case .started(let attempt) = start(f.preferences, ipRelease()) else { throw CheckFailure(message: "running queue fixture") }
                if phase == "recovering" { try require(f.preferences.fail(attempt, principal: owner, scope: .shared), "recovery barrier fixture") }
            }
            let state = f.preferences.state(of: "entry")
            _ = f.refresh()
            let calls = f.source.calls; let reads = f.store.reads; let writes = f.store.writes; let bytes = f.store.bytes
            for kind in [StartKind.manual, .updateAll, .automatic, .loginWindow] {
                for request in [ipRequest(), ipRequest(gen: 0, rev: UInt64.max, principal: SchedulingPrincipal("wrong"))] {
                    try require(ipRefusal(f.coordinator.requestStart(request, kind: kind), .unavailable), "start opened execution path")
                    try require(f.source.calls == calls && f.store.reads == reads && f.store.writes == writes && f.store.bytes == bytes,
                        "individual requestStart had effects")
                    try require(f.preferences.state(of: "entry") == state, "individual requestStart mutated queue")
                }
            }
            _ = f.coordinator.select(ipRequest()); _ = f.coordinator.projection()
            try require(f.source.calls == calls + 1 && f.store.reads == reads && f.store.writes == writes && f.store.bytes == bytes, "start/select touched storage or unexpected source")
            try require(f.preferences.state(of: "entry") == state, "projection/start disturbed queue")
            f.source.value = .unavailable; _ = f.refresh()
            try require(f.preferences.state(of: "entry") == state, "refusal disturbed queue")
            if phase == "recovering" {
                try require(enqueue(f.preferences, ipRelease([2: "3"]), id: "later"), "later queue fixture")
                try require(start(f.preferences, ipRelease([2: "3"]), id: "later", request: "later-request") == .stopped, "shared recovery barrier lost")
            }
        }
    }
}
