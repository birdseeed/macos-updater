import Foundation
import PatchedScheduling
@_spi(Testing) import PatchedUpdatePreferences

@MainActor func raceChecks(_ c: Checks) {
    for kind in [StartKind.manual, .updateAll, .automatic, .loginWindow] {
        c.run("exact skip blocks \(kind) at action time") {
            let (value, _) = loaded()
            try require(enqueue(value), "pending fixture queue")
            try require(edit(value, .skip(release)) == .accepted(revision: 1), "persist skip")
            try require(start(value, kind: kind) == .deferred(.skipped), "queued older policy bypassed skip")
            try require(value.state(of: "entry") == .pending, "deferred entry changed state")
        }
    }
    for kind in [StartKind.manual, .updateAll, .automatic, .loginWindow] {
        c.run("exclusion preserves manual/bulk and blocks automatic \(kind)") {
            let (value, _) = loaded()
            try require(edit(value, .exclusion(PreferenceAppKey(release), true)) == .accepted(revision: 1), "persist exclusion")
            try require(enqueue(value), "enqueue")
            let result = start(value, kind: kind)
            if kind == .manual || kind == .updateAll { try require(isStarted(result), "manual/bulk inherited exclusion") }
            else { try require(result == .deferred(.excluded), "automatic bypassed exclusion") }
        }
    }
    for other in [candidate(scope: "system"), candidate(edition: "enterprise"), candidate(channel: "beta")] {
        c.run("scoped exclusion isolation \(other.scope)/\(other.edition)/\(other.channel)") {
            let (value, _) = loaded(fixtureBytes(exclusions: [PreferenceAppKey(release)]))
            try require(enqueue(value, other), "enqueue distinct key")
            try require(isStarted(start(value, other, kind: .automatic)), "exclusion leaked across scoped key")
        }
    }
    for other in [candidate(scope: "system"), candidate(edition: "enterprise"), candidate(channel: "beta"), candidate(version: "3", build: "30", artifact: "digest-3")] {
        c.run("exact skip does not transfer \(other.scope)/\(other.edition)/\(other.channel)/\(other.release)") {
            let (value, _) = loaded(fixtureBytes(skips: [release]))
            try require(enqueue(value, other), "enqueue distinct identity")
            try require(isStarted(start(value, other)), "skip transferred")
        }
    }
    for other in [candidate(build: "21"), candidate(artifact: "different-digest")] {
        c.run("same skipped release changed identity defers \(other.build)/\(other.artifact)") {
            let (value, _) = loaded(fixtureBytes(skips: [release]))
            try require(enqueue(value, other), "enqueue changed identity")
            try require(start(value, other) == .deferred(.identity), "same-release ambiguity allowed")
        }
    }
    c.run("undo removes only exact skip") {
        let other = candidate(scope: "system")
        let (value, store) = loaded(fixtureBytes(skips: [release, other]))
        try require(edit(value, .undo(release)) == .accepted(revision: 1), "undo")
        try require(store.bytes == fixtureBytes(revision: 1, skips: [other], mutations: [("mutation-1", .undo(release))]), "undo erased unrelated skip")
        try require(enqueue(value) && isStarted(start(value)), "undo did not permit exact release")
    }
    c.run("start then skip leaves completion independent") {
        let (value, _) = loaded(); try require(enqueue(value), "enqueue")
        guard case .started(let attempt) = start(value) else { throw CheckFailure(message: "initial start") }
        try require(edit(value, .skip(release)) == .accepted(revision: 1), "post-start skip")
        try require(value.complete(attempt, principal: owner), "changed preferences denied completion")
        try require(value.state(of: "entry") == .completed, "completion not recorded")
    }
    c.run("start then exclusion leaves failure and recovery independent") {
        let (value, store) = loaded(); try require(enqueue(value), "enqueue")
        guard case .started(let attempt) = start(value, kind: .automatic) else { throw CheckFailure(message: "initial start") }
        try require(edit(value, .exclusion(PreferenceAppKey(release), true)) == .accepted(revision: 1), "post-start exclusion")
        store.bytes = nil; _ = value.reload(generation: generation)
        try require(value.fail(attempt, principal: owner, scope: .isolated), "preference failure denied failure transition")
        try require(value.recover(attempt, principal: owner, evidence: .verifiedIsolatedRollback), "preference failure denied recovery")
        try require(value.state(of: "entry") == .restored, "recovery state")
    }
    c.run("undo before pending start permits exact release") {
        let (value, _) = loaded(fixtureBytes(skips: [release])); try require(enqueue(value), "enqueue")
        try require(start(value) == .deferred(.skipped), "start before undo")
        try require(edit(value, .undo(release)) == .accepted(revision: 1), "undo")
        try require(isStarted(start(value)), "start after undo")
    }
    c.run("reentrant store callback cannot start or edit or reload") {
        let (value, store) = loaded(); try require(enqueue(value), "enqueue")
        var nestedStart: QueueStart?; var nestedEdit: PreferenceEditResult?; var nestedReload: PreferenceEditResult?
        store.callback = {
            nestedStart = start(value)
            nestedEdit = edit(value, .undo(release), id: "nested")
            nestedReload = value.reload(generation: generation)
        }
        try require(edit(value, .skip(release)) == .accepted(revision: 1), "outer edit")
        try require(nestedStart == .rejected, "reentrant start escaped CAS owner")
        try require(nestedEdit == .refused(.reentrant) && nestedReload == .refused(.reentrant), "reentrant mutation/reload escaped")
        try require(start(value) == .deferred(.skipped), "outer skip not used after callback")
    }
    c.run("refresh before edit binds new accepted revision") {
        let (value, store) = loaded(); store.bytes = fixtureBytes(revision: 1, exclusions: [PreferenceAppKey(release)])
        try require(value.reload(generation: generation) == .accepted(revision: 1), "refresh")
        try require(edit(value, .skip(release)) == .refused(.conflict), "stale view revision accepted")
        try require(edit(value, .skip(release), id: "current", revision: 1) == .accepted(revision: 2), "current revision edit")
        try require(store.bytes == fixtureBytes(revision: 2, exclusions: [PreferenceAppKey(release)], skips: [release], mutations: [("current", .skip(release))]), "refresh state lost")
    }
    c.run("edit before refresh preserves exact accepted revision") {
        let (value, store) = loaded()
        try require(edit(value, .skip(release)) == .accepted(revision: 1), "edit")
        let bytes = store.bytes
        try require(value.reload(generation: generation) == .accepted(revision: 1), "refresh after edit")
        try require(store.bytes == bytes, "refresh rewrote acknowledgement")
    }
    c.run("old generation actions cannot change new session") {
        let store = MemoryStore(bytes: fixtureBytes()); let value = session(store, gen: "generation-2")
        try require(value.reload(generation: "generation-2") == .accepted(revision: 0), "new generation load")
        try require(edit(value, .skip(release)) == .refused(.staleGeneration), "stale edit")
        try require(!value.enqueue(QueueEntry(id: "e", target: "fixture-target", release: release), principal: owner, generation: generation), "stale enqueue")
        try require(start(value, gen: generation) == .rejected && store.writes == 0, "stale start/write")
    }
    c.run("foreign principal and target cannot use session queue") {
        let (value, _) = loaded(); try require(enqueue(value), "enqueue")
        try require(start(value, principal: SchedulingPrincipal("foreign")) == .rejected, "foreign owner")
        let result = value.start(id: "entry", requestID: "request", principal: owner, generation: generation,
                                 kind: .manual, automaticEnabled: true, pause: nil, conditions: conditions(target: "foreign-target"))
        try require(result == .rejected && value.state(of: "entry") == .pending, "target substitution")
    }
    c.run("foreign queue attempt with same sequence rejected") {
        let (a, _) = loaded(); let store = MemoryStore(bytes: fixtureBytes()); let b = session(store, queue: "queue-2")
        try require(b.reload(generation: generation) == .accepted(revision: 0), "second queue load")
        try require(enqueue(a) && enqueue(b), "two queue entries")
        guard case .started(let aa) = start(a), case .started(let bb) = start(b) else { throw CheckFailure(message: "two queue starts") }
        try require(aa.sequence == bb.sequence && aa != bb, "queue lifetime identity lost")
        try require(!b.complete(aa, principal: owner) && b.complete(bb, principal: owner), "foreign attempt accepted")
    }
    c.run("global automatic off and pause remain injected current policy") {
        let (value, _) = loaded(); try require(enqueue(value), "enqueue")
        try require(start(value, kind: .automatic, automatic: false) == .deferred(.automaticOff), "global consent invented")
        let pause = AutomaticPause(resumeUTC: 200, displayZone: "UTC", anchor: conditions().clock)
        try require(start(value, kind: .automatic, pause: pause) == .deferred(.paused), "pause bypassed")
        try require(isStarted(start(value, kind: .manual, automatic: false, pause: pause)), "manual inherited automatic controls")
    }
    c.run("unknown release cannot become start authority") {
        let (value, _) = loaded(); try require(enqueue(value), "enqueue")
        var unknown = conditions(); unknown.release = .ambiguous
        let result = value.start(id: "entry", requestID: "request", principal: owner, generation: generation,
                                 kind: .manual, automaticEnabled: true, pause: nil, conditions: unknown)
        try require(result == .rejected, "unknown identity accepted")
    }
    c.run("empty channel or edition cannot be queued") {
        let (value, _) = loaded(); try require(value.acceptedRevision == 0, "load")
        try require(!enqueue(value, candidate(channel: "")), "empty channel")
        try require(!enqueue(value, candidate(edition: "")), "empty edition")
    }
    // Parent-authorised additive correction after group 1 red; previous cases stay exact.
    for (name, driftedBytes, reason) in [
        ("new revision with exact skip", Optional(fixtureBytes(revision: 1, skips: [release])), PreferenceRefusal.conflict),
        ("missing existing bytes", Optional<Data>.none, PreferenceRefusal.missing),
        ("malformed existing bytes", Optional(Data("{".utf8)), PreferenceRefusal.malformed),
        ("foreign principal and store scope", Optional(fixtureBytes(principal: "foreign-owner", scope: "foreign-store")), PreferenceRefusal.malformed)
    ] {
        c.run("action-time store drift rejects pending start: \(name)") {
            let (value, store) = loaded()
            try require(enqueue(value), "pending queue under accepted revision zero")
            let originalWrites = store.writes
            store.bytes = driftedBytes
            try require(start(value) == .rejected, "start used stale accepted preference bytes")
            try require(value.state(of: "entry") == .pending, "store drift changed pending queue")
            try require(store.writes == originalWrites && store.bytes == driftedBytes, "start rewrote drifted store")
            try require(value.acceptedRevision == 0 && value.blockedReason == reason, "drift diagnosis or optimistic publication")
            // Merely restoring bytes cannot clear a previously observed drift barrier.
            store.bytes = fixtureBytes()
            try require(start(value) == .rejected && value.state(of: "entry") == .pending,
                        "new start bypassed explicit validated reload")
            try require(value.acceptedRevision == 0 && value.blockedReason == reason && store.writes == originalWrites,
                        "restored bytes silently acknowledged without reload")
            try require(value.reload(generation: generation) == .accepted(revision: 0), "explicit validated reload refused")
            try require(value.blockedReason == nil && isStarted(start(value)), "validated reload did not unblock start")
        }
    }

}
