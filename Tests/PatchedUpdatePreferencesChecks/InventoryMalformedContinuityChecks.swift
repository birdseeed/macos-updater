import Foundation
import PatchedScheduling
@_spi(Testing) import PatchedUpdatePreferences

/// Independent additive regression: malformed returned bytes are observed same-generation drift.
/// The original finite input refusal remains visible; restored old bytes cannot undo the drift.
@MainActor func ipMalformedContinuityChecks(_ c: Checks) {
    for mode in ["identity-path", "display-bounds", "row-bounds", "source-principal"] {
        c.run("IP-N malformed same-generation drift latches \(mode)") {
            let original = ipSnapshot([ipRow()], gen: 1, checked: 100)
            let f = IPFixture(original)
            try require(f.refresh() == .accepted(generation: 1), "valid continuity fixture refused")
            try ipRows(f.coordinator.projection(), [.syntheticReady], ids: ["one"], versions: ["2"])
            let refusal: InventoryRefusal
            switch mode {
            case "identity-path":
                f.source.value = .snapshot(ipSnapshot([ipRow(ipIdentity([8: "/Applications/../Bad.app"]))], gen: 1, checked: 900))
                refusal = .identity
            case "display-bounds":
                f.source.value = .snapshot(ipSnapshot([ipRow(name: String(repeating: "d", count: 257))], gen: 1, checked: 901))
                refusal = .bounds
            case "row-bounds":
                let rows = (0..<513).map { n in
                    ipRow(ipIdentity(id: "row\(n)", location: "/Applications/Row\(n).app"), update: .unknown)
                }
                f.source.value = .snapshot(ipSnapshot(rows, gen: 1, checked: 902))
                refusal = .bounds
            default:
                f.source.value = .snapshot(ipSnapshot([ipRow()], gen: 1, checked: 903, principal: SchedulingPrincipal("another-synthetic-owner")))
                refusal = .principal
            }
            try require(f.refresh() == .refused(refusal), "malformed input lost its original finite refusal")
            let invalidated = f.coordinator.projection()
            try ipRows(invalidated, [.unknown], ids: ["one"], versions: ["2"])
            try ipCounts(invalidated, detected: 1, unknown: 1)
            try require(!invalidated.isFresh && invalidated.syntheticLastChecked == 100,
                "malformed same-generation response advanced time or kept freshness")
            f.source.value = .snapshot(original)
            try require(f.refresh() == .refused(.generation), "restored accepted bytes erased observed malformed same-generation drift")
            let restored = f.coordinator.projection()
            try ipRows(restored, [.unknown], ids: ["one"], versions: ["2"])
            try require(!restored.isFresh && restored.syntheticLastChecked == 100, "restored old bytes revived freshness")
            f.source.value = .snapshot(ipSnapshot([ipRow()], gen: 2, checked: 200))
            try require(f.refresh() == .accepted(generation: 2), "strictly newer valid snapshot failed to clear malformed drift")
            let newer = f.coordinator.projection()
            try ipRows(newer, [.syntheticReady], ids: ["one"], versions: ["2"])
            try ipCounts(newer, detected: 1, ready: 1)
            try require(newer.isFresh && newer.generation == 2 && newer.preferenceRevision == 0 && newer.syntheticLastChecked == 200,
                "new valid generation did not restore synthetic projection")
            try require(f.source.calls == 4 && f.source.limits == [512, 512, 512, 512] && f.store.reads == 1 && f.store.writes == 0,
                "malformed continuity affected source bounds or preference storage")
        }
    }
}
