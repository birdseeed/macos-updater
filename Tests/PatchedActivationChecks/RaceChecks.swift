import Foundation
@_spi(Testing) import PatchedActivation

@MainActor func registerRaceChecks() {
    check("three-way final-slot competition in all six deterministic orderings") {
        let bytes = try Data(contentsOf: URL(fileURLWithPath: "Fixtures/Activation/vectors/final-slot.json"))
        let vector = try JSONDecoder().decode(RaceVector.self, from: bytes)
        for order in permutations(vector.competitorKeys) {
            var f = try LedgerFixture(occupied: vector.initialOccupied)
            let attempts = try order.map { try f.prepare(key: $0) }
            var ledger = f.ledger(); var results: [AllocationOutcome] = []
            for attempt in attempts {
                results.append(try ledger.apply(current(attempt, ledger)).outcome)
                try assertInvariants(ledger)
            }
            try expect(results.filter { $0 == .activated }.count == vector.expectedActivated, "Final-slot winner count")
            try expect(results.filter { $0 == .limitReached }.count == vector.expectedLimitReached && used(ledger) == 5, "Final-slot cap/order failure")
        }
    }
    check("release versus activate at capacity in both orderings") {
        for order in permutations([0, 1]) {
            var f = try LedgerFixture(occupied: 5)
            let attempts = [try f.prepare(.deactivate, session: 11), try f.prepare(key: 9)]
            var ledger = f.ledger(); var activationResult: AllocationResult?
            for index in order {
                let result = try ledger.apply(current(attempts[index], ledger))
                if index == 1 { activationResult = result }
                try assertInvariants(ledger)
            }
            try expect(activationResult?.outcome == (order[0] == 0 ? .activated : .limitReached), "Incorrect serialised race result")
            let before = ledger.snapshot; let retry = try ledger.apply(attempts[1])
            try expect(retry == activationResult && ledger.snapshot == before, "Capacity refusal replay executed again after free slot")
        }
    }
    check("two replaces race for same immutable old activation") {
        for order in permutations([0, 1]) {
            var f = try LedgerFixture(occupied: 5)
            let attempts = [try f.prepare(.replace, key: 8, session: 11), try f.prepare(.replace, key: 9, session: 12)]
            var ledger = f.ledger(); var outcomes: [AllocationOutcome] = []
            for index in order {
                outcomes.append(try ledger.apply(current(attempts[index], ledger)).outcome)
                try assertInvariants(ledger)
            }
            try expect(outcomes == [.replaced, .stale] && used(ledger) == 5, "Replace race released wrong occupant")
            try expect(ledger.snapshot.activations[fixtureID(100)]?.released == true, "Old ID not terminal")
        }
    }
    check("replace versus deactivate never frees replacement") {
        for order in permutations([0, 1]) {
            var f = try LedgerFixture(occupied: 5)
            let attempts = [try f.prepare(.replace, key: 8, session: 11), try f.prepare(.deactivate, session: 12)]
            var ledger = f.ledger()
            for index in order { _ = try ledger.apply(current(attempts[index], ledger)); try assertInvariants(ledger) }
            try expect(used(ledger) == (order[0] == 0 ? 5 : 4), "Old-ID release freed new occupant")
        }
    }
    check("released identifier remains terminal after request retention purge") {
        var f = try LedgerFixture(occupied: 1)
        f.state.activations[fixtureID(100)]!.released = true; f.state.activations[fixtureID(100)]!.slot = nil
        f.state.activations[fixtureID(100)]!.revision = 2
        let newActivation = try f.prepare(key: 1, newID: 200)
        let reuseReleasedID = try f.prepare(key: 2, newID: 100)
        var ledger = f.ledger(); let result = try ledger.apply(newActivation)
        try expect(result.outcome == .activated && result.activationID == fixtureID(200), "Surviving key did not get new ID")
        try expect(ledger.snapshot.activations[fixtureID(200)]?.generation == 2 && ledger.snapshot.activations[fixtureID(100)]?.released == true, "Generation/history erased")
        let before = ledger.snapshot
        try refuses(.invalidRequest) { _ = try ledger.apply(current(reuseReleasedID, ledger)) }
        try expect(ledger.snapshot == before, "Released ID reused")
    }
    check("released activation replay reads current state without resurrection") {
        var f = try LedgerFixture()
        let activate = try f.prepare(key: 1, newID: 200)
        let release = try f.prepare(.deactivate, activation: fixtureID(200), session: 11)
        var ledger = f.ledger(); _ = try ledger.apply(activate); _ = try ledger.apply(current(release, ledger))
        var replay = activate; replay.sessionID = fixtureID(12)
        let before = ledger.snapshot; let result = try ledger.apply(replay)
        try expect(result.outcome == .activated && result.released && result.grant == nil && ledger.snapshot == before, "Replay resurrected released identity")
        try refuses(.invalidSession) { _ = try ledger.apply(activate) }
    }
    check("audit failure rolls back terminal stale claim and consumed nonce") {
        var f = try LedgerFixture(occupied: 1)
        var action = try f.prepare(.replace, revision: 2); action.auditSucceeds = false
        var ledger = f.ledger(); let before = ledger.snapshot
        try refuses(.auditFailed) { _ = try ledger.apply(action) }
        try expect(ledger.snapshot == before, "Failed stale audit retained claim/nonce/history")
    }
    check("stale activation revision leaves slot and history intact") {
        var f = try LedgerFixture(occupied: 1)
        let action = try f.prepare(.replace, revision: 2)
        var ledger = f.ledger(); let before = ledger.snapshot.activations
        let result = try ledger.apply(action)
        try expect(result.outcome == .stale && ledger.snapshot.activations == before && used(ledger) == 1, "Stale revision changed occupancy/history")
        try expect(ledger.snapshot.requests.count == 1 && ledger.snapshot.audit.count == 1, "Terminal stale outcome not recorded/audited")
        let committed = ledger.snapshot; let retry = try ledger.apply(action)
        try expect(retry == result && ledger.snapshot == committed, "Terminal stale replay mutated state")
    }
}
struct RaceVector: Decodable {
    let initialOccupied: Int
    let competitorKeys: [Int]
    let expectedActivated: Int
    let expectedLimitReached: Int
}
