import Foundation
import AppKit
import SwiftUI
import PatchedDisposableClient

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let configuration: NativeProofConfiguration
    var proof: NativeProofWindow?
    init(_ configuration: NativeProofConfiguration) { self.configuration = configuration }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let proof = NativeProofWindow(configuration: configuration); self.proof = proof
        proof.window.center(); proof.window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if configuration.proofDriver {
            Task { await proof.runProofDriver(); NSApplication.shared.terminate(nil) }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        proof?.operationRunning == true ? .terminateCancel : .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
@main struct DisposableClientApp {
    @MainActor static func main() {
        do {
            let configuration = try NativeProofConfiguration.parse(Array(CommandLine.arguments.dropFirst()))
            let app = NSApplication.shared, delegate = AppDelegate(configuration)
            app.setActivationPolicy(.regular); app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
        } catch {
            let object: [String: Any] = ["event": "native-arguments-refused", "reason": String(describing: error),
                "installedFirefoxProof": false, "productionTrust": false]
            if let bytes = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) { print(String(decoding: bytes, as: UTF8.self)) }
            exit(1)
        }
    }
}
