import Foundation
import PatchedScheduling
@_spi(Testing) import PatchedUpdatePreferences

@MainActor func recordChecks(_ c: Checks) {
    firstRunSetupChecks(c)
    c.run("literal independent fixture bytes", setup: true) {
        try require(fixtureBytes() == Data(emptyLiteral.utf8), "fixture encoder differs from literal")
        let disk = try Data(contentsOf: URL(fileURLWithPath: "Fixtures/UpdatePreferences/records.json"))
        try require(disk == Data(emptyLiteral.utf8), "checked-in literal changed")
    }
    c.run("synthetic identity and unchanged policy", setup: true) {
        var policy = SchedulePolicy(principal: owner, automaticEnabled: true)
        try require(policy.decision(for: .manual, conditions: conditions()) == .eligible, "unchanged manual control")
        policy.skip(release)
        try require(policy.decision(for: .manual, conditions: conditions()) == .deferred(.skipped), "unchanged skip control")
        try require(policy.decision(for: .manual, conditions: conditions(candidate(build: "21"))) == .deferred(.identity), "unchanged ambiguity control")
    }
    c.run("unchanged queue completion control", setup: true) {
        var queue = QueueModel(principal: owner, queueID: "control-queue")
        try require(queue.enqueue(QueueEntry(id: "e", target: "fixture-target", release: release), principal: owner), "enqueue control")
        let result = queue.start(id: "e", requestID: "r", principal: owner, kind: .manual,
                                 policy: SchedulePolicy(principal: owner), conditions: conditions())
        guard case .started(let attempt) = result else { throw CheckFailure(message: "queue start control") }
        try require(queue.complete(attempt, principal: owner), "completion control")
    }
    c.run("permanent ordinary store refusal with zero operations", setup: true) {
        let ordinary = RefusingPreferenceStore()
        try require(ordinary.read(maximumBytes: 16) == .unavailable, "ordinary read")
        try require(ordinary.compareAndSwap(expected: nil, proposed: Data(), maximumBytes: 16) == .notCommitted, "ordinary write")
        let value = PreferenceSession()
        try require(value.acceptedRevision == nil, "ordinary accepted state")
        try require(!enqueue(value) && !isStarted(start(value)), "ordinary start")
        if case .accepted = edit(value, .skip(release)) { throw CheckFailure(message: "ordinary edit") }
    }
    c.run("decode literal record") {
        let value = try PreferenceRecordCodec.decode(Data(emptyLiteral.utf8), principal: owner, storeScope: storeScope)
        try require(value.revision == 0 && value.exclusions.isEmpty && value.skips.isEmpty && value.mutations.isEmpty, "literal fields")
    }
    c.run("encode independently declared record exactly") {
        let value = PreferenceRecord(principal: owner, storeScope: storeScope, revision: 0)
        try require(try PreferenceRecordCodec.encode(value) == Data(emptyLiteral.utf8), "exact bytes")
    }
    c.run("canonical ordering and full identity preservation") {
        let other = candidate(scope: "system", channel: "beta")
        let bytes = fixtureBytes(revision: 7, exclusions: [PreferenceAppKey(other), PreferenceAppKey(release)],
                                 skips: [other, release], mutations: [("id-1", .skip(release))])
        let value = try PreferenceRecordCodec.decode(bytes, principal: owner, storeScope: storeScope)
        try require(value.skips == Set([release, other]) && value.exclusions.count == 2, "identity collapsed")
        try require(try PreferenceRecordCodec.encode(value) == bytes, "canonical ordering changed")
    }
    var invalid: [(String, Data)] = [
        ("empty", Data()), ("invalid UTF8", Data([0xff])), ("partial", Data("{".utf8)),
        ("oversize", Data(repeating: 32, count: 1_048_577)),
        ("unknown field", Data(emptyLiteral.replacingOccurrences(of: "{", with: "{\"extra\":1,", options: [], range: emptyLiteral.startIndex..<emptyLiteral.index(after: emptyLiteral.startIndex)).utf8)),
        ("duplicate field", Data(emptyLiteral.replacingOccurrences(of: "\"schema\":1", with: "\"schema\":1,\"schema\":1").utf8)),
        ("schema", Data(emptyLiteral.replacingOccurrences(of: "\"schema\":1", with: "\"schema\":2").utf8)),
        ("string revision", Data(emptyLiteral.replacingOccurrences(of: "\"revision\":0", with: "\"revision\":\"0\"").utf8)),
        ("boolean revision", Data(emptyLiteral.replacingOccurrences(of: "\"revision\":0", with: "\"revision\":false").utf8)),
        ("negative revision", Data(emptyLiteral.replacingOccurrences(of: "\"revision\":0", with: "\"revision\":-1").utf8)),
        ("fraction revision", Data(emptyLiteral.replacingOccurrences(of: "\"revision\":0", with: "\"revision\":0.0").utf8)),
        ("overflow revision", Data(emptyLiteral.replacingOccurrences(of: "\"revision\":0", with: "\"revision\":18446744073709551616").utf8)),
        ("noncanonical whitespace", Data((emptyLiteral + "\n").utf8)),
        ("noncanonical order", Data(emptyLiteral.replacingOccurrences(of: "\"revision\":0,\"schema\":1", with: "\"schema\":1,\"revision\":0").utf8)),
        ("foreign principal", fixtureBytes(principal: "another-owner")),
        ("foreign scope", fixtureBytes(scope: "another-store")),
        ("empty principal", fixtureBytes(principal: "")),
        ("NUL principal", fixtureBytes(principal: "owner\0")),
        ("control principal", fixtureBytes(principal: "owner\n")),
        ("long principal", fixtureBytes(principal: String(repeating: "a", count: 257))),
        ("UTF8 byte principal", fixtureBytes(principal: String(repeating: "é", count: 129))),
        ("empty scope", fixtureBytes(scope: "")),
        ("long scope", fixtureBytes(scope: String(repeating: "x", count: 257))),
        ("duplicate exclusion", fixtureBytes(exclusions: [PreferenceAppKey(release), PreferenceAppKey(release)])),
        ("duplicate skip", fixtureBytes(skips: [release, release])),
        ("duplicate mutation", fixtureBytes(mutations: [("same", .skip(release)), ("same", .skip(release))])),
        ("empty mutation", fixtureBytes(mutations: [("", .skip(release))])),
        ("long mutation", fixtureBytes(mutations: [(String(repeating: "x", count: 257), .skip(release))]))
    ]
    for field in ["product", "scope", "release", "build", "edition", "channel", "artifact"] {
        var object = releaseObject(release); object[field] = ""
        invalid.append(("empty release \(field)", canonical(["exclusions": [], "mutations": [], "principal": owner.value,
            "revision": 0, "schema": 1, "skips": [object], "storeScope": storeScope])))
        object[field] = String(repeating: "a", count: 257)
        invalid.append(("long release \(field)", canonical(["exclusions": [], "mutations": [], "principal": owner.value,
            "revision": 0, "schema": 1, "skips": [object], "storeScope": storeScope])))
    }
    for (name, bytes) in invalid {
        c.run("reject \(name)") {
            do { _ = try PreferenceRecordCodec.decode(bytes, principal: owner, storeScope: storeScope) }
            catch { return }
            throw CheckFailure(message: "invalid record accepted")
        }
    }
    for count in [256, 257] {
        c.run("exclusion boundary \(count)") {
            let keys = (0..<count).map { PreferenceAppKey(product: "app-\($0)", scope: "user", edition: "standard", channel: "stable") }
            let bytes = fixtureBytes(exclusions: keys)
            if count == 256 {
                let value = try PreferenceRecordCodec.decode(bytes, principal: owner, storeScope: storeScope)
                try require(value.exclusions.count == 256, "maximum exclusions refused")
            } else {
                do { _ = try PreferenceRecordCodec.decode(bytes, principal: owner, storeScope: storeScope) } catch { return }
                throw CheckFailure(message: "over-limit exclusions")
            }
        }
    }
    for count in [512, 513] {
        c.run("skip boundary \(count)") {
            let bytes = fixtureBytes(skips: (0..<count).map { candidate(version: "\($0)") })
            if count == 512 {
                let value = try PreferenceRecordCodec.decode(bytes, principal: owner, storeScope: storeScope)
                try require(value.skips.count == 512, "maximum skips refused")
            } else {
                do { _ = try PreferenceRecordCodec.decode(bytes, principal: owner, storeScope: storeScope) } catch { return }
                throw CheckFailure(message: "over-limit skips")
            }
        }
    }
    for count in [128, 129] {
        c.run("mutation history boundary \(count)") {
            let bytes = fixtureBytes(mutations: (0..<count).map { ("id-\($0)", .skip(release)) })
            if count == 128 {
                let value = try PreferenceRecordCodec.decode(bytes, principal: owner, storeScope: storeScope)
                try require(value.mutations.count == 128, "maximum history refused")
            } else {
                do { _ = try PreferenceRecordCodec.decode(bytes, principal: owner, storeScope: storeScope) } catch { return }
                throw CheckFailure(message: "over-limit history")
            }
        }
    }
    c.run("maximum UInt64 revision survives exact bytes") {
        let bytes = fixtureBytes(revision: UInt64.max)
        let value = try PreferenceRecordCodec.decode(bytes, principal: owner, storeScope: storeScope)
        try require(value.revision == UInt64.max, "revision precision lost")
        try require(try PreferenceRecordCodec.encode(value) == bytes, "revision canonical bytes")
    }
    c.run("256 UTF8 byte identity accepted") {
        let principal = String(repeating: "é", count: 128)
        let value = try PreferenceRecordCodec.decode(fixtureBytes(principal: principal), principal: SchedulingPrincipal(principal), storeScope: storeScope)
        try require(value.principal.value == principal, "byte boundary rejected")
    }
    c.run("raw byte exact ceiling fixture mechanics", setup: true) {
        try require(try exactByteFixture(1_048_576).count == 1_048_576, "exact maximum fixture length")
        try require(try exactByteFixture(1_048_577).count == 1_048_577, "exact oversize fixture length")
    }
    for length in [1_048_576, 1_048_577] {
        c.run("raw byte boundary \(length)") {
            let bytes = try exactByteFixture(length)
            if length == 1_048_576 {
                let value = try PreferenceRecordCodec.decode(bytes, principal: owner, storeScope: storeScope)
                try require(try PreferenceRecordCodec.encode(value) == bytes, "maximum raw bytes rejected")
            } else {
                do { _ = try PreferenceRecordCodec.decode(bytes, principal: owner, storeScope: storeScope) } catch { return }
                throw CheckFailure(message: "over byte limit accepted")
            }
        }
    }
    let malformedOperations = ["{}", #"{"action":"skip"}"#,
        #"{"action":"skip","release":false}"#,
        operation(.skip(release)) + " ",
        operation(.skip(release)).replacingOccurrences(of: "\"action\":\"skip\"", with: "\"action\":\"skip\",\"extra\":1"),
        operation(.skip(release)).replacingOccurrences(of: "\"action\":\"skip\"", with: "\"action\":\"skip\",\"action\":\"undo\""),
        operation(.exclusion(PreferenceAppKey(release), true)).replacingOccurrences(of: "\"excluded\":true", with: "\"excluded\":1"),
        String(repeating: "x", count: 4096), String(repeating: "x", count: 4097)]
    for (index, payload) in malformedOperations.enumerated() {
        c.run("reject malformed retained operation \(index)") {
            let bytes = canonical(["exclusions": [], "mutations": [["id": "id", "operation": payload]],
                                   "principal": owner.value, "revision": 0, "schema": 1, "skips": [], "storeScope": storeScope])
            do { _ = try PreferenceRecordCodec.decode(bytes, principal: owner, storeScope: storeScope) } catch { return }
            throw CheckFailure(message: "opaque operation admitted")
        }
    }
    for change in [PreferenceChange.exclusion(PreferenceAppKey(release), true), .skip(release), .undo(release)] {
        c.run("typed canonical retained operation \(operation(change))") {
            let bytes = fixtureBytes(mutations: [("receipt", change)])
            let value = try PreferenceRecordCodec.decode(bytes, principal: owner, storeScope: storeScope)
            try require(value.mutations.first?.operation == operation(change), "operation payload changed")
            try require(try PreferenceRecordCodec.encode(value) == bytes, "retained operation canonical bytes")
        }
    }
}

/// Builds canonical valid-shaped bytes at the exact raw ceiling without production encoding.
func exactByteFixture(_ desiredCount: Int) throws -> Data {
    var keys = (0..<256).map { appObject(PreferenceAppKey(product: "key-\($0)", scope: "u", edition: "e", channel: "c")) }
    var identities = (0..<512).map { releaseObject(candidate(version: "r-\($0)")) }
    func object() -> [String: Any] {
        ["exclusions": keys.sorted { canonical($0).lexicographicallyPrecedes(canonical($1)) }, "mutations": [],
         "principal": owner.value, "revision": 0, "schema": 1,
         "skips": identities.sorted { canonical($0).lexicographicallyPrecedes(canonical($1)) }, "storeScope": storeScope]
    }
    var remaining = desiredCount - canonical(object()).count
    guard remaining >= 0 else { throw CheckFailure(message: "exact-byte fixture smaller than baseline") }
    for index in identities.indices {
        for field in ["product", "scope", "release", "build", "edition", "channel", "artifact"] {
            let value = identities[index][field] as! String
            let count = min(remaining, 256 - value.utf8.count)
            identities[index][field] = value + String(repeating: "x", count: count)
            remaining -= count
        }
    }
    for index in keys.indices {
        for field in ["product", "scope", "edition", "channel"] {
            let value = keys[index][field] as! String
            let count = min(remaining, 256 - value.utf8.count)
            keys[index][field] = value + String(repeating: "x", count: count)
            remaining -= count
        }
    }
    guard remaining == 0 else { throw CheckFailure(message: "exact-byte fixture capacity insufficient") }
    return canonical(object())
}
