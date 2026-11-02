import Foundation
import AppKit
import PatchedDisposableClient

struct CheckFailure: Error { let message: String }
@MainActor func runNativeUIChecks() async {
        var count = 0, failures = 0
        func expect(_ condition: Bool, _ message: String) throws { if !condition { throw CheckFailure(message: message) } }
        func check(_ name: String, _ body: () async throws -> Void) async {
            count += 1
            do { try await body(); print("PASS native-ui: \(name)") }
            catch { failures += 1; print("FAIL native-ui: \(name): \(error)") }
        }
        _ = NSApplication.shared // Offscreen controls only; never run/show the app.
        await check("ordinary launch has no selection driver or automatic action") {
            let config = try NativeProofConfiguration.parse([]), window = NativeProofWindow(configuration: config)
            try expect(config.selection == nil && !config.proofDriver && !window.checkButton.isEnabled && !window.actionButton.isEnabled,
                       "Empty launch enabled action")
            try expect(window.controller.phase == .unavailable && !window.controller.isTestDouble && !window.window.isVisible, "Wrong concrete/offscreen composition")
        }
        for arguments in [["--other", "anything"], ["--proof-driver"],
            ["--run-id", "synthetic-native", "--case-root", "update", "--action", "update", "--action", "update"],
            ["--run-id", "synthetic-native", "--case-root", "swap", "--action", "update"]] {
            await check("closed arguments refuse \(arguments.joined(separator: " "))") {
                do { _ = try NativeProofConfiguration.parse(arguments); throw CheckFailure(message: "Arguments accepted") }
                catch is CheckFailure { throw CheckFailure(message: "Arguments accepted") }
                catch { /* Exact parser refusal; no factory or path access. */ }
            }
        }
        await check("actual Check button reaches real host factory refusal and cannot enable action") {
            let config = try NativeProofConfiguration.parse(["--run-id", "synthetic-native", "--case-root", "update", "--action", "update"])
            let proof = NativeProofWindow(configuration: config)
            try expect(proof.checkButton.isEnabled && !proof.actionButton.isEnabled, "Unprepared action enabled")
            proof.checkButton.performClick(nil); await proof.checkTask?.value
            try expect(proof.controller.phase == .refused && ["guestMismatch", "notAuthorized"].contains(proof.controller.refusalReason ?? ""), "Real factory guard did not refuse")
            try expect(!proof.actionButton.isEnabled && !proof.controller.installedFirefoxProof && proof.actionTask == nil, "Guard failure dispatched action")
            guard let view = proof.window.contentView else { throw CheckFailure(message: "No native content") }
            view.layoutSubtreeIfNeeded()
            guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CheckFailure(message: "Cannot paint offscreen") }
            view.cacheDisplay(in: view.bounds, to: image)
            try expect(image.pixelsWide > 0 && image.pixelsHigh > 0, "Empty system-font status rendering")
        }
        await check("proof driver cannot click through invisible window") {
            let config = try NativeProofConfiguration.parse(["--run-id", "synthetic-native", "--case-root", "update", "--action", "update", "--proof-driver"])
            let proof = NativeProofWindow(configuration: config)
            await proof.runProofDriver()
            try expect(proof.checkTask == nil && proof.actionTask == nil && proof.controller.phase == .unavailable,
                       "Invisible driver invoked a button")
        }
        print("Disposable native UI acceptance: \(count) cases, \(failures) failures. Offscreen actual controls and real host refusal only; no native guest proof or installation.")
        exit(failures == 0 ? 0 : 1)
}
await runNativeUIChecks()
