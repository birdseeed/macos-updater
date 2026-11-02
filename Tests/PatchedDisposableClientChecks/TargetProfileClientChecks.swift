import Foundation
import PatchedDisposableProof
@_spi(Testing) import PatchedDisposableClient

private func profileConfigArgs() -> [String] { ["--run-id", "profile-a", "--case-root", "update", "--action", "update"] }
private func profileConfigRefuses(_ arguments: [String]) throws {
    do { _ = try NativeProofConfiguration.parse(arguments) }
    catch let e as DisposableFailure {
        try expect(e == .invalidArguments || e == .unknownTarget, "Unexpected refusal: \(e)"); return
    }
    throw CheckFailure(description: "Invalid native selector/fact was accepted")
}
@MainActor func registerTargetProfileClientChecks() {
    let prefix = "PAT-2710 profile client: "
    check(prefix + "omission preserves native legacy configuration [control]") {
        let c = try NativeProofConfiguration.parse(profileConfigArgs())
        try expect(c.selection?.profile == .legacy && c.selection?.artifactPath == "/Users/andy/PatchedProof/profile-a/Incoming/Firefox 157.0.1.dmg" &&
            c.selection?.targetPath == "/Users/andy/PatchedProof/profile-a/Cases/update/Applications/Firefox.app" &&
            c.action == .update && !c.proofDriver, "Omitted selector changed old contract")
        let empty = try NativeProofConfiguration.parse([])
        try expect(empty.selection == nil && empty.action == nil && !empty.proofDriver, "Empty config remains unarmed")
    }
    for (profile, id, parent) in [
        (DisposableTargetProfile.legacy, "parallels-0A0A0A0A-0000-4000-8000-000000000001", "/Users/andy/PatchedProof"),
        (.ssdTesting, "parallels-0A0A0A0A-0000-4000-8000-000000000002", "/Users/runner/PatchedTesting")
    ] {
        check(prefix + "exact native selector \(profile) [expect RED]") {
            let c = try NativeProofConfiguration.parse(profileConfigArgs() + ["--target-id", id])
            try expect(c.selection?.profile == profile && c.selection?.runID == "profile-a" && c.selection?.caseRoot == "update" &&
                c.selection?.artifactPath == parent + "/profile-a/Incoming/Firefox 157.0.1.dmg" &&
                c.selection?.targetPath == parent + "/profile-a/Cases/update/Applications/Firefox.app", "Fixed profile-derived native paths")
        }
        check(prefix + "typed selection retained \(profile) [control]") {
            let selection = InstalledActionSelection(runID: "profile-a", caseRoot: "update",
                artifactPath: parent + "/profile-a/Incoming/Firefox 157.0.1.dmg",
                targetPath: parent + "/profile-a/Cases/update/Applications/Firefox.app", version: "157.0.1", profile: profile)
            let controller = InstalledActionController(); controller.select(selection)
            try expect(selection.profile == profile && controller.selection == selection && controller.selection?.profile == profile &&
                !controller.actionEnabled && !controller.installedFirefoxProof, "Selection lost profile or issued authority")
        }
    }
    check(prefix + "selection default remains legacy [control]") {
        let s = InstalledActionSelection(runID: "profile-a", caseRoot: "update", artifactPath: "/TEST-ONLY/a", targetPath: "/TEST-ONLY/b", version: "157.0.1")
        try expect(s.profile == .legacy, "Old selection constructor must keep legacy default")
    }
    for extra in [["--target-id", "unknown"], ["--target-id", "ssdTesting"],
                  ["--target-id", "parallels-0a0a0a0a-0000-4000-8000-000000000002"],
                  ["--target-id", "parallels-0A0A0A0A-0000-4000-8000-000000000002", "--target-id", "parallels-0A0A0A0A-0000-4000-8000-000000000002"],
                  ["--guest-home", "/Users/runner"], ["--run-parent", "/Users/runner/PatchedTesting"],
                  ["--guest-uuid", "asserted"], ["--target-path", "/Applications/Firefox.app"], ["--profile", "ssdTesting"],
                  ["--proof-driver", "--proof-driver"], ["--unknown"], ["--target-id"]] {
        check(prefix + "closed native CLI refuses \(extra.joined(separator: " ")) [control]") {
            try profileConfigRefuses(profileConfigArgs() + extra)
        }
    }
    check(prefix + "native gateway forwards typed profile before path acceptance [expect RED]") {
        let text = try source("Sources/PatchedDisposableClient/NativeInstalledActionGateway.swift")
        try expect(text.contains("profile: selection.profile"), "Native issuer call must forward typed selection profile")
        try expect(!text.contains("selection.targetPath == DisposableScope.runParent") &&
            !text.contains("selection.artifactPath == DisposableScope.runParent"), "Native path validation mixes legacy literals with selected profile")
    }
    check(prefix + "native UI parser derives typed request profile [expect RED]") {
        let text = try source("Sources/PatchedDisposableClient/NativeProofWindow.swift")
        try expect(text.contains("\"--target-id\"") && text.contains("profile:"), "UI config must carry the validated typed selector into selection")
        try expect(!text.contains("artifactPath: DisposableScope.runParent") && !text.contains("targetPath: DisposableScope.runParent"),
                   "UI config paths must follow validated profile")
    }
}
