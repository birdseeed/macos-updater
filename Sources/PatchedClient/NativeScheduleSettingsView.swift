import SwiftUI
import AppKit
import PatchedUpdatePreferences

/// Rendering retains declarations without opening storage or starting a scheduler.
public struct NativeScheduleSettingsView: View {
    @ObservedObject private var controller: NativeScheduleSettingsController
    @ObservedObject private var firstRun: NativeFirstRunController
    public init(controller: NativeScheduleSettingsController) {
        self.controller = controller; self.firstRun = controller.firstRun
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "Schedule").font(.title2).accessibilityAddTraits(.isHeader)
            Text(verbatim: controller.statusText).fixedSize(horizontal: false, vertical: true)
            HStack {
                ScheduleActionButton(title: "Reload saved schedule settings", enabled: true) { controller.reload() }
                ScheduleActionButton(title: "Save schedule choices", enabled: controller.draft != nil) { _ = controller.save() }
            }
            if let settings = controller.settings {
                Toggle("Daily update checks", isOn: Binding(get: {
                    if case .dailyChecks(let value)? = controller.draft { return value }
                    return settings.dailyChecks
                }, set: { controller.choose(.dailyChecks($0)) }))
                Toggle("Update notifications", isOn: Binding(get: {
                    if case .notifications(let value)? = controller.draft { return value }
                    return settings.notifications
                }, set: { controller.choose(.notifications($0)) }))
                Text(verbatim: settings.automaticUpdates
                    ? "Saved automatic updates choice: on. Automatic installation remains unavailable."
                    : "Saved automatic updates choice: off. Automatic installation remains unavailable.")
                if settings.automaticUpdates {
                    ScheduleActionButton(title: "Choose automatic updates off", enabled: true) {
                        controller.choose(.automaticUpdates(false))
                    }
                }
                if let pause = settings.pause {
                    Text(verbatim: "Saved pause: UTC " + String(pause.resumeUTC) + " (" + pause.displayZone + ").")
                }
                Text(verbatim: "Pause declaration: absolute UTC seconds and a display zone label. This does not start checks or grant permission.")
                TextField("Resume UTC seconds", text: $controller.pauseUTCInput)
                TextField("Display zone", text: $controller.pauseZoneInput)
                HStack {
                    ScheduleActionButton(title: "Choose pause", enabled: true) {
                        guard let utc = Int64(controller.pauseUTCInput),
                              let pause = SchedulePauseChoice.declared(resumeUTC: utc, displayZone: controller.pauseZoneInput) else {
                            controller.invalidPauseInput = true; return
                        }
                        controller.invalidPauseInput = false; controller.choose(.pause(pause))
                    }
                    ScheduleActionButton(title: "Choose pause removed", enabled: true) {
                        controller.invalidPauseInput = false; controller.choose(.pause(nil))
                    }
                }
                if controller.invalidPauseInput { Text(verbatim: "Pause choice invalid. No choice saved.") }
                Text(verbatim: "Choose and save one setting at a time. Choices are declarations only. Trusted scheduled update checks unavailable.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if controller.acceptedRevision != nil {
                ScheduleActionButton(title: "Migrate saved schedule settings", enabled: true) { _ = controller.migrate() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Genuine native buttons retain public accessibility titles in hidden and visible hosts.
/// They use ordinary AppKit target/action, including keyboard and accessibility activation.
private struct ScheduleActionButton: NSViewRepresentable {
    let title: String
    let enabled: Bool
    let action: @MainActor () -> Void
    @MainActor final class Coordinator: NSObject {
        var action: @MainActor () -> Void
        init(action: @escaping @MainActor () -> Void) { self.action = action }
        @objc func press(_ sender: NSButton) { if sender.isEnabled { action() } }
    }
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.press(_:)))
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: NSFont.systemFontSize)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setAccessibilityLabel(title)
        button.setAccessibilityTitle(title)
        button.isEnabled = enabled
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.title = title; button.setAccessibilityLabel(title); button.setAccessibilityTitle(title)
        button.isEnabled = enabled
    }
}
