import Foundation
import PatchedScheduling
@_spi(Testing) import PatchedUpdatePreferences

@MainActor func ipBindingChecks(_ c: Checks) {
    for field in 0..<11 {
        c.run("IP-N available evidence exact identity field \(field)") {
            let changed = ipIdentity([field: field == 8 ? "/Applications/Else.app" : "changed"])
            let f = IPFixture(ipSnapshot([ipRow(update: .syntheticAvailable(InventoryCandidate(identity: changed, release: ipRelease())))]))
            try require(f.refresh() == .refused(.identity), "candidate identity mismatch accepted")
            try ipRows(f.coordinator.projection(), [], ids: [], versions: [])
        }
        c.run("IP-N current evidence exact identity field \(field)") {
            let changed = ipIdentity([field: field == 8 ? "/Applications/Else.app" : "changed"])
            let f = IPFixture(ipSnapshot([ipRow(update: .syntheticCurrent(changed))]))
            try require(f.refresh() == .refused(.identity), "current identity mismatch accepted")
        }
    }
    for field in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] {
        c.run("IP-N canonical-equivalent Unicode current binding field \(field)") {
            let a = ipIdentity([field: field == 8 ? "/Applications/\u{e9}.app" : "\u{e9}"])
            let b = ipIdentity([field: field == 8 ? "/Applications/e\u{301}.app" : "e\u{301}"])
            let f = IPFixture(ipSnapshot([ipRow(a, update: .syntheticCurrent(b))]))
            try require(f.refresh() == .refused(.identity), "Unicode alias current identity")
        }
    }
    for field in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] {
        c.run("IP-N canonical-equivalent Unicode available binding field \(field)") {
            let a = ipIdentity([field: field == 8 ? "/Applications/\u{e9}.app" : "\u{e9}"])
            let b = ipIdentity([field: field == 8 ? "/Applications/e\u{301}.app" : "e\u{301}"])
            let mapping = [1: 0, 2: 1, 5: 4, 6: 5]
            let r = ipRelease(mapping[field].map { [$0: "\u{e9}"] } ?? [:])
            let f = IPFixture(ipSnapshot([ipRow(a, update: .syntheticAvailable(InventoryCandidate(identity: b, release: r)))]))
            try require(f.refresh() == .refused(.identity), "Unicode alias candidate identity")
        }
    }
    for (releaseField, identityField) in [(0, 1), (1, 2), (4, 5), (5, 6)] {
        c.run("IP-N candidate release field \(releaseField) binds inventory field \(identityField)") {
            let f = IPFixture(ipSnapshot([ipRow(release: ipRelease([releaseField: "other"]))]))
            try require(f.refresh() == .refused(.identity), "release identity correspondence")
            let a = ipIdentity([identityField: "\u{e9}"])
            let b = ipRelease([releaseField: "e\u{301}"])
            f.source.value = .snapshot(ipSnapshot([ipRow(a, release: b)]))
            try require(f.refresh() == .refused(.identity), "Unicode release correspondence")
        }
    }
    c.run("IP-N duplicate exact IDs and locations reject whole snapshot with no partial publication") {
        for rows in [[ipRow(), ipRow(ipIdentity([1: "different"], location: "/Applications/Two.app"), release: ipRelease([0: "different"]))],
                     [ipRow(), ipRow(ipIdentity(id: "two"))]] {
            let f = IPFixture(ipSnapshot(rows))
            try require(f.refresh() == .refused(.identity), "duplicate accepted")
            try ipRows(f.coordinator.projection(), [], ids: [], versions: [])
            try require(f.store.reads == 1 && f.store.writes == 0, "invalid snapshot accessed store")
        }
    }
    c.run("IP-P Unicode-equivalent distinct location bytes are not duplicate locations") {
        let a = ipIdentity([1: "a"], id: "a", location: "/Applications/\u{e9}.app")
        let b = ipIdentity([1: "b"], id: "b", location: "/Applications/e\u{301}.app")
        let f = IPFixture(ipSnapshot([ipRow(a, update: .syntheticCurrent(a)), ipRow(b, update: .syntheticCurrent(b))]))
        try require(f.refresh() == .accepted(generation: 1), "location Unicode alias collapsed")
        try ipRows(f.coordinator.projection(), [.syntheticCurrent, .syntheticCurrent], ids: ["a", "b"], versions: [nil, nil])
    }
}

@MainActor func ipBoundsChecks(_ c: Checks) {
    c.run("IP-N zero generation never accepted") {
        let f = IPFixture(ipSnapshot(gen: 0)); try require(f.refresh() == .refused(.generation), "zero generation")
    }
    c.run("IP-P UInt64 maximum generation and clock are accepted without overflow") {
        let f = IPFixture(ipSnapshot(gen: UInt64.max, checked: UInt64.max))
        try require(f.refresh() == .accepted(generation: UInt64.max), "max generation")
        try require(f.refresh() == .unchanged(generation: UInt64.max), "max unchanged")
    }
    for field in 0..<11 {
        for invalid in ["", String(repeating: "x", count: field == 0 ? 129 : field == 8 ? 1025 : 257), "bad\u{0}", "bad\n", "bad\u{7f}"] {
            c.run("IP-N identity field \(field) invalid UTF8 bound/control \(invalid.utf8.count)") {
                let f = IPFixture(ipSnapshot([ipRow(ipIdentity([field: invalid]), update: .unknown)]))
                let result = f.refresh()
                // Bounds versus malformed identity is the public finite classification.
                let oversized = invalid.utf8.count > (field == 0 ? 128 : field == 8 ? 1024 : 256)
                try require(result == .refused(oversized ? .bounds : .identity), "identity invalid accepted or wrong reason")
            }
        }
        c.run("IP-P identity maximum byte length field \(field)") {
            let text: String
            if field == 0 { text = String(repeating: "x", count: 128) }
            else if field == 8 { text = "/" + String(repeating: "x", count: 1019) + ".app" }
            else { text = String(repeating: "\u{e9}", count: 128) }
            let i = ipIdentity([field: text]); let f = IPFixture(ipSnapshot([ipRow(i, update: .syntheticCurrent(i))]))
            try require(f.refresh() == .accepted(generation: 1), "valid maximum identity refused")
            try require(ipExact(ipIdentityFields(f.coordinator.projection().applications.first?.identity ?? ipIdentity()), ipIdentityFields(i)), "identity bytes lost")
        }
    }
    for bad in ["relative.app", "/Applications//One.app", "/Applications/./One.app", "/Applications/../One.app", "/One.app/", "/Applications/One.APP", "/", "/Applications/One"] {
        c.run("IP-N malformed location \(bad)") {
            let f = IPFixture(ipSnapshot([ipRow(ipIdentity([8: bad]), update: .unknown)]))
            try require(f.refresh() == .refused(.identity), "malformed location")
        }
    }
    for bad in ["with space", "slash/id", "\u{e9}", "colon:id", "emoji\u{1f642}"] {
        c.run("IP-N restricted instance ID \(bad)") {
            let f = IPFixture(ipSnapshot([ipRow(ipIdentity([0: bad]), update: .unknown)]))
            try require(f.refresh() == .refused(.identity), "instance syntax")
        }
    }
    c.run("IP-P restricted instance allowed punctuation") {
        let f = IPFixture(ipSnapshot([ipRow(ipIdentity([0: "A_z-0.9"]), update: .unknown)]))
        try require(f.refresh() == .accepted(generation: 1), "legal instance ID")
    }
    for field in 0..<7 {
        for invalid in ["", String(repeating: "x", count: 257), "bad\u{0}", "bad\n"] {
            c.run("IP-N release field \(field) invalid bound/control \(invalid.utf8.count)") {
                let f = IPFixture(ipSnapshot([ipRow(release: ipRelease([field: invalid]))]))
                try require(f.refresh() == .refused(invalid.utf8.count > 256 ? .bounds : .identity), "invalid release accepted")
            }
        }
        if field != 6 {
            c.run("IP-P release maximum bytes field \(field)") {
                let text = String(repeating: "\u{e9}", count: 128)
                let mapping = [0: 1, 1: 2, 4: 5, 5: 6]
                let i = ipIdentity(mapping[field].map { [$0: text] } ?? [:])
                let f = IPFixture(ipSnapshot([ipRow(i, release: ipRelease([field: text]))]))
                try require(f.refresh() == .accepted(generation: 1), "valid maximum release")
            }
        }
    }
    for bad in [String(repeating: "a", count: 63), String(repeating: "a", count: 65), String(repeating: "A", count: 64), String(repeating: "g", count: 64), String(repeating: "\u{e9}", count: 32)] {
        c.run("IP-N digest requires exactly64 lowercase ASCII hex \(bad.utf8.count)-\(bad.prefix(1))") {
            let f = IPFixture(ipSnapshot([ipRow(release: ipRelease([6: bad]))]))
            try require(f.refresh() == .refused(.identity), "malformed digest")
        }
    }
    for (display, reason) in [("", InventoryRefusal.identity), (String(repeating: "x", count: 257), .bounds), ("bad\n", .identity), ("bad\u{0}", .identity)] {
        c.run("IP-N display name malformed \(display.utf8.count)") {
            let f = IPFixture(ipSnapshot([ipRow(name: display)]))
            try require(f.refresh() == .refused(reason), "invalid display")
        }
    }
    c.run("IP-P display name256bytes and512rows accepted") {
        let rows = (0..<512).map { n -> InventoryObservation in
            let i = ipIdentity([1: "p\(n)"], id: "r\(n)", location: "/A\(n).app")
            return ipRow(i, name: String(repeating: "\u{e9}", count: 128), update: .syntheticCurrent(i))
        }
        let f = IPFixture(ipSnapshot(rows)); try require(f.refresh() == .accepted(generation: 1), "512 maximum rows")
        try ipCounts(f.coordinator.projection(), detected: 512, current: 512)
        try require(f.source.limits == [512], "maximumRows contract")
    }
    c.run("IP-N 513rows refuse bounds before grouping") {
        let rows = (0..<513).map { ipRow(ipIdentity(id: "r\($0)", location: "/A\($0).app"), update: .unknown) }
        let f = IPFixture(ipSnapshot(rows)); try require(f.refresh() == .refused(.bounds), "row cap")
    }
    for current in [false, true] {
        c.run("IP-N aggregate counts every repeated nested \(current ? "current" : "candidate") string") {
            let rows = (0..<(current ? 147 : 120)).map { n -> InventoryObservation in
                let tag = String(n)
                let id = String(repeating: "i", count: 128 - tag.utf8.count) + tag
                let path = "/" + String(repeating: "x", count: 1019 - tag.utf8.count) + tag + ".app"
                var fields: [Int: String] = [:]
                for field in [1,2,3,4,5,6,7,9,10] { fields[field] = String(repeating: "x", count: 256) }
                let i = ipIdentity(fields, id: id, location: path)
                let text = String(repeating: "x", count: 256)
                let r = ipRelease([0: text, 1: text, 2: text, 3: text, 4: text, 5: text])
                return ipRow(i, name: text, update: current ? .syntheticCurrent(i) : .syntheticAvailable(InventoryCandidate(identity: i, release: r)))
            }
            let f = IPFixture(ipSnapshot(rows))
            try require(f.refresh() == .refused(.bounds), "nested strings omitted or deduplicated from bound")
            try require(f.store.reads == 1 && f.store.writes == 0, "oversized nested snapshot touched store")
        }
    }
    for extra in [0, 1] {
        c.run("IP-\(extra == 0 ? "P" : "N") aggregate exact1MiB plus\(extra) bytes") {
            // 282*(128+9*256+1024+256) + 1777 + 15 = 1048576.
            // Last row:128+256+256+106+6*1+1024+1 =1777. +1 changes bundle only.
            let rows = (0..<283).map { n -> InventoryObservation in
                let tag = String(n)
                let id = String(repeating: "i", count: 128 - tag.utf8.count) + tag
                let path = "/" + String(repeating: "x", count: 1019 - tag.utf8.count) + tag + ".app"
                var fields: [Int: String] = [:]
                for field in [1,2,3,4,5,6,7,9,10] { fields[field] = String(repeating: "x", count: n == 282 ? 1 : 256) }
                if n == 282 { fields[1] = String(repeating: "x", count: 256); fields[2] = String(repeating: "x", count: 256); fields[3] = String(repeating: "x", count: 106 + extra) }
                return ipRow(ipIdentity(fields, id: id, location: path), name: String(repeating: "d", count: n == 282 ? 1 : 256), update: .unknown)
            }
            let f = IPFixture(ipSnapshot(rows))
            try require(f.refresh() == (extra == 0 ? .accepted(generation: 1) : .refused(.bounds)), "aggregate threshold")
        }
    }
}
