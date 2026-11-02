import AppKit
import SwiftUI
import PatchedDisposableProof

/// CLI is intent only; it can neither supply observations nor issue authority.
public struct NativeProofConfiguration: Sendable {
    public let selection: InstalledActionSelection?
    public let action: InstalledAction?
    public let proofDriver: Bool
    private init(selection: InstalledActionSelection?, action: InstalledAction?, proofDriver: Bool) {
        self.selection = selection; self.action = action; self.proofDriver = proofDriver
    }
    public static func parse(_ arguments: [String]) throws -> NativeProofConfiguration {
        if arguments.isEmpty { return .init(selection: nil, action: nil, proofDriver: false) }
        var values: [String: String] = [:], driver = false, index = 0
        while index < arguments.count {
            let key = arguments[index]; index += 1
            if key == "--proof-driver" { guard !driver else { throw DisposableFailure.invalidArguments }; driver = true; continue }
            guard ["--run-id", "--case-root", "--action", "--target-id"].contains(key), values[key] == nil, index < arguments.count else { throw DisposableFailure.invalidArguments }
            values[key] = arguments[index]; index += 1
        }
        guard let run = values["--run-id"], let root = values["--case-root"], let raw = values["--action"],
              let action = InstalledAction.proofAction(named: raw) else { throw DisposableFailure.invalidArguments }
        let request = try DisposableArguments.parse(["--target-id", values["--target-id"] ?? DisposableScope.targetID, "--run-id", run,
            "--case-root", root, "--case", raw, "--explicit-trigger"])
        guard let targetPath = request.targetPath else { throw DisposableFailure.invalidArguments }
        return .init(selection: .init(runID: run, caseRoot: root,
            artifactPath: request.profile.runParent + "/" + run + "/Incoming/Firefox 157.0.1.dmg",
            targetPath: targetPath,
            version: "157.0.1", profile: request.profile), action: action, proofDriver: driver)
    }
}

private struct NativeProofStatus: View {
    @ObservedObject var controller: InstalledActionController
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Disposable Firefox proof").font(.title2)
            Text(controller.selection?.targetPath ?? "Select an approved run using the scoped command arguments.")
                .font(.system(.body, design: .default)).textSelection(.enabled)
            Text("State: " + String(describing: controller.phase))
            if let reason = controller.refusalReason { Text("Refused: " + reason) }
            Text(controller.installedFirefoxProof ? "Fresh installed Firefox proof verified for this action." : "No installed proof claimed.")
            Text("Production trust: false")
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Actual native buttons, concrete productive controller only. Offscreen checks
/// can inspect these controls but cannot inject a gateway, token or physical fact.
@MainActor public final class NativeProofWindow: NSObject, NSWindowDelegate {
    public let controller = InstalledActionController.nativeDisposable()
    public let window: NSWindow
    public let checkButton = NSButton(title: "Check selected run", target: nil, action: nil)
    public let actionButton = NSButton(title: "Perform selected action", target: nil, action: nil)
    public let configuration: NativeProofConfiguration
    public private(set) var checkTask: Task<Void, Never>?
    public private(set) var actionTask: Task<Void, Never>?
    private var driverCompleted = false
    public init(configuration: NativeProofConfiguration) {
        self.configuration = configuration
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 360),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Patched disposable native proof"; window.delegate = self; window.isReleasedWhenClosed = false
        if let selection = configuration.selection { controller.select(selection) }
        let status = NSHostingView(rootView: NativeProofStatus(controller: controller))
        let controls = NSStackView(views: [checkButton, actionButton]); controls.orientation = .horizontal; controls.spacing = 16
        let content = NSStackView(views: [status, controls]); content.orientation = .vertical; content.alignment = .leading
        content.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 20, right: 12)
        window.contentView = content
        checkButton.target = self; checkButton.action = #selector(checkClicked)
        actionButton.target = self; actionButton.action = #selector(actionClicked)
        if let action = configuration.action { actionButton.title = "Perform " + action.proofActionName }
        refreshButtons()
    }
    public var operationRunning: Bool { controller.phase == .running }
    public func windowShouldClose(_ sender: NSWindow) -> Bool { !operationRunning }
    private func refreshButtons() {
        checkButton.isEnabled = configuration.selection != nil && !operationRunning
        actionButton.isEnabled = configuration.action != nil && controller.actionEnabled
    }
    private func event(_ name: String, extra: [String: Any] = [:]) {
        var object: [String: Any] = ["event": name, "runID": configuration.selection?.runID ?? "",
            "caseRoot": configuration.selection?.caseRoot ?? "", "action": configuration.action?.proofActionName ?? "",
            "windowVisible": window.isVisible, "phase": String(describing: controller.phase),
            "installedFirefoxProof": controller.installedFirefoxProof, "productionTrust": false,
            "activation": configuration.proofDriver ? "programmatically activated native UI" : "native UI"]
        for (key, value) in extra { object[key] = value }
        if let reason = controller.refusalReason { object["reason"] = reason }
        if let evidence = controller.evidencePath { object["evidencePath"] = evidence }
        if let bytes = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) {
            print(String(decoding: bytes, as: UTF8.self)); fflush(stdout)
        }
    }
    @objc private func checkClicked() {
        guard checkButton.isEnabled else { return }
        event("native-check-button", extra: ["enabledAtActivation": true])
        checkButton.isEnabled = false; actionButton.isEnabled = false
        checkTask = Task { [self] in await controller.prepare(); refreshButtons(); event("native-check-completed") }
    }
    @objc private func actionClicked() {
        guard actionButton.isEnabled, let action = configuration.action else { return }
        event("native-action-button", extra: ["enabledAtActivation": true])
        actionButton.isEnabled = false; checkButton.isEnabled = false
        actionTask = Task { [self] in
            await controller.request(action, trigger: .explicitUserAction)
            refreshButtons(); event("native-action-completed")
        }
    }
    /// Called only after the real app displays its actual window. No driver
    /// bypass exists around readiness or the actual enabled NSButton targets.
    public func runProofDriver() async {
        guard configuration.proofDriver, !driverCompleted else { return }
        driverCompleted = true
        for _ in 0..<100 {
            if window.isVisible { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        guard window.isVisible, checkButton.isEnabled else { event("native-driver-refused", extra: ["actionActivated": false]); return }
        checkButton.performClick(nil)
        await checkTask?.value
        guard actionButton.isEnabled, controller.actionEnabled else {
            event("native-driver-preflight-refused", extra: ["actionActivated": false]); return
        }
        actionButton.performClick(nil)
        await actionTask?.value
        event("native-driver-finished", extra: ["actionActivated": true])
    }
}
