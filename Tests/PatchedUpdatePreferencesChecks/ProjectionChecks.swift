import Foundation
import PatchedScheduling
@_spi(Testing) import PatchedUpdatePreferences

@MainActor func projectionChecks(_ c: Checks) {
    c.run("Applications Updates Settings share one accepted revision and honest counts") {
        let (value, _) = loaded(fixtureBytes(revision: 9, exclusions: [PreferenceAppKey(release)], skips: [release]))
        let view = value.projection([PreferenceCandidate(id: "skipped", release: .verified(release)),
                                    PreferenceCandidate(id: "available", release: .verified(candidate(version: "3"))),
                                    PreferenceCandidate(id: "unknown", release: .ambiguous)])
        try require(view.revision == 9 && view.applications == view.updates, "shared revision/rows diverged")
        try require(view.availableCount == 1 && view.skippedCount == 1 && view.unknownCount == 1, "honest counts")
        try require(view.settingsExclusionCount == 1, "settings exclusion count")
        try require(view.applications.map(\.availability) == [.skipped, .available, .unknown], "skip labelled current/installed")
        try require(view.applications[0].canUndo && view.applications[0].automaticExcluded, "skip undo/exclusion lost")
        try require(!view.applications[1].canUndo && view.applications[1].automaticExcluded, "later release inherited skip")
    }
    c.run("projection publication waits for CAS and exact readback") {
        let (value, store) = loaded(); let candidates = [PreferenceCandidate(id: "e", release: .verified(release))]
        let before = value.projection(candidates); var during: PreferenceProjection?
        store.callback = { during = value.projection(candidates) }
        try require(edit(value, .skip(release)) == .accepted(revision: 1), "edit")
        try require(during == before && during?.revision == 0, "optimistic projection")
        let after = value.projection(candidates)
        try require(after.revision == 1 && after.skippedCount == 1, "acknowledged projection missing")
    }
    c.run("known write failure leaves accepted projections unchanged") {
        let (value, store) = loaded(); let candidates = [PreferenceCandidate(id: "e", release: .verified(release))]
        let before = value.projection(candidates); try require(before.revision == 0, "initial projection")
        store.fault = .beforeWrite
        try require(edit(value, .skip(release)) == .refused(.unavailable), "failed edit")
        try require(value.projection(candidates) == before, "failure rendered success")
    }
    c.run("same-release identity ambiguity projects unknown while exact undo stays scoped") {
        let (value, _) = loaded(fixtureBytes(skips: [release]))
        let view = value.projection([PreferenceCandidate(id: "changed", release: .verified(candidate(build: "21"))),
                                    PreferenceCandidate(id: "channel", release: .verified(candidate(channel: "beta")))])
        try require(view.revision == 0 && view.unknownCount == 1 && view.availableCount == 1, "ambiguous identity rendered available")
        try require(view.applications.map(\.availability) == [.unknown, .available], "scoped projection identity")
        try require(view.applications.allSatisfy { !$0.canUndo }, "inexact undo offered")
    }
    c.run("default unknown projection carries no accepted revision") {
        let value = PreferenceSession()
        let view = value.projection([PreferenceCandidate(id: "e", release: .verified(release))])
        try require(view.revision == nil && view.availableCount == 0 && view.skippedCount == 0, "default accepted state")
        try require(view.unknownCount == 1 && view.applications.first?.availability == .unknown, "default unknown silently omitted")
    }
}
