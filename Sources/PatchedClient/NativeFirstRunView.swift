import SwiftUI

/// Displays the retained setup draft. Only explicit controls request controller actions.
public struct NativeFirstRunView: View {
    @ObservedObject private var controller: NativeFirstRunController
    public init(controller: NativeFirstRunController) { self.controller = controller }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "app.badge.checkmark").accessibilityHidden(true)
                Text(verbatim: "Patched").font(.headline)
                Spacer()
                Text(verbatim: controller.networkPresented ? "Network settings" : stepLabel)
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    preferenceStatus
                    if controller.networkPresented {
                        Button(action: { controller.returnFromNetwork() }) {
                            Text(verbatim: "Return to setup")
                        }
                        .buttonStyle(ClientButtonStyle(enabled: true, prominent: false))
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel("Return to setup without saving choices")
                        NativeNetworkSettingsView(controller: controller.network, probe: controller.networkProbe)
                        detail("Network fields are a draft. Returning to setup does not apply, test or save a connection. The Network screen's explicit actions remain separate.")
                    } else {
                        stepContent
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            Divider()
            if !controller.networkPresented {
                actions
                    .padding(20)
            }
        }
        .font(.body)
        .frame(minWidth: 680, minHeight: 520)
    }

    private var stepLabel: String {
        switch controller.step {
        case .welcome: return "1 of 3"
        case .review: return "2 of 3"
        case .findApps: return "3 of 3"
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch controller.step {
        case .welcome:
            Image(systemName: "arrow.triangle.2.circlepath.circle")
                .font(.system(size: 48)).foregroundStyle(.tint).accessibilityHidden(true)
            heading("Keep your Mac apps up to date")
            detail("A clear view of your apps, with you in control of what happens next.")
            detail("Continue loads saved preferences locally. You can review your choices before saving or finding apps. Nothing is scanned just by opening setup.")
            networkButton
        case .review:
            heading("You choose what updates")
            detail("Review your choices before finding apps or making changes.")
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: Binding(get: { controller.dailyChecks }, set: { value in
                    controller.edit(dailyChecks: value, notifications: controller.notifications,
                        failureReports: controller.failureReports)
                })) { Text(verbatim: "Check daily") }
                    .accessibilityLabel("Check daily preference")
                Toggle(isOn: Binding(get: { controller.notifications }, set: { value in
                    controller.edit(dailyChecks: controller.dailyChecks, notifications: value,
                        failureReports: controller.failureReports)
                })) { Text(verbatim: "Notify me about updates") }
                    .accessibilityLabel("Notify me about updates preference")
                detail("Your choices are saved locally. Automatic checks and notifications are unavailable in this build. Setup does not request notification permission.")
                Divider()
                Toggle(isOn: Binding(get: { controller.failureReports }, set: { value in
                    controller.edit(dailyChecks: controller.dailyChecks, notifications: controller.notifications,
                        failureReports: value)
                })) { Text(verbatim: "Send failed-update reports when reporting is available") }
                    .accessibilityLabel("Failed-update report preference when reporting becomes available")
                detail("Reporting is unavailable in this build. Nothing is sent.")
                Divider()
                Toggle(isOn: .constant(false)) { Text(verbatim: "Help improve app coverage") }
                    .disabled(true)
                    .accessibilityLabel("Help improve app coverage, off and unavailable")
                detail("Coverage sharing is off and unavailable. No app inventory or coverage data is sent.")
                Toggle(isOn: .constant(false)) { Text(verbatim: "Install updates automatically") }
                    .disabled(true)
                    .accessibilityLabel("Install updates automatically, off and unavailable")
                detail("Automatic installation is unavailable in this build. Setup does not enable it.")
            }
            .toggleStyle(.checkbox)
            Divider()
            Text(verbatim: "Keep working until you are ready").font(.headline)
            detail("Future manual updates will ask before closing a running app. Automatic updates will require the app to be closed. Apps excluded from automatic updates can still be updated manually when that feature is available.")
            capabilityStatus
            networkButton
        case .findApps:
            heading("Find apps on this Mac")
            detail("Find apps saves your choices and setup completion, then scans your local applications.")
            detail("The scan lists local apps and versions. Update checks are unavailable in this build. Scanning does not download or change apps.")
            detail("You can also save completion and open Updates without scanning.")
            networkButton
        }
    }

    private var capabilityStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "Optional helper").font(.headline)
            detail("Unavailable in this build. Setup does not install a helper.")
            detail("The optional helper is uninstalled. Any future installation requires its own explicit approval.")
            Text(verbatim: "App Management").font(.headline)
            detail("Status unavailable. Finishing setup does not grant macOS permission.")
            detail("Helper approval and App Management permission are separate. Neither is required to view local observations.")
        }
    }

    private var networkButton: some View {
        Button(action: { controller.showNetwork() }) { Text(verbatim: "Network settings") }
            .buttonStyle(ClientButtonStyle(enabled: true, prominent: false))
            .accessibilityLabel("Open shared Network settings and retain setup choices")
    }

    private var preferenceStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(verbatim: localStateLabel).font(.headline)
            detail(controller.statusText)
                .accessibilityLabel("Local preference status: " + controller.statusText)
            if controller.localState != .unopened {
                Button(action: { controller.openPreferences() }) {
                    Text(verbatim: "Reload saved preferences")
                }
                .buttonStyle(ClientButtonStyle(enabled: true, prominent: false))
                .accessibilityLabel("Reload saved preferences, retaining unsaved choices")
            }
            if controller.localState == .missing {
                detail("No preference record was found. Create one explicitly, then save your choices. Existing or unreadable records are never reset here.")
                Button(action: { _ = controller.createFreshPreferences() }) {
                    Text(verbatim: "Create fresh preferences")
                }
                .buttonStyle(ClientButtonStyle(enabled: true, prominent: false))
                .accessibilityLabel("Create fresh local preferences only after confirmed absence")
            }
        }
    }

    private var localStateLabel: String {
        switch controller.localState {
        case .unopened: return "Local preferences have not been opened"
        case .missing: return "Local preferences are missing"
        case .available:
            switch controller.saveStatus {
            case .saved: return "Choices saved locally"
            case .loaded: return "Saved preferences loaded"
            case .unsaved, .missing, .unavailable, .refused: return "Choices remain unsaved"
            }
        case .unavailable: return "Local preferences are unavailable"
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if controller.step != .welcome {
                    Button(action: { controller.back() }) { Text(verbatim: "Back") }
                        .buttonStyle(ClientButtonStyle(enabled: true, prominent: false))
                        .accessibilityLabel("Back, retaining setup choices")
                }
                Spacer()
                if controller.step == .findApps {
                    Button(action: { controller.findApps() }) { Text(verbatim: "Find apps") }
                        .buttonStyle(ClientButtonStyle(enabled: true, prominent: true))
                        .keyboardShortcut(.defaultAction)
                        .accessibilityLabel("Save setup completion and find local apps")
                } else {
                    Button(action: { controller.advance() }) {
                        Text(verbatim: controller.step == .welcome ? "Continue" : "Save choices and continue")
                    }
                    .buttonStyle(ClientButtonStyle(enabled: true, prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel(controller.step == .welcome ? "Load saved preferences and review choices" : "Save choices and continue to Find apps")
                }
            }
            if controller.step == .findApps {
                Button(action: { controller.openUpdates() }) {
                    Text(verbatim: "Open Updates without scanning")
                }
                .buttonStyle(ClientButtonStyle(enabled: true, prominent: false))
                .accessibilityLabel("Save setup completion and open Updates without scanning")
            }
            if controller.localState == .missing || controller.localState == .unavailable {
                Button(action: { controller.scanWithoutSaving() }) {
                    Text(verbatim: "Scan without saving choices")
                }
                .buttonStyle(ClientButtonStyle(enabled: true, prominent: false))
                .accessibilityLabel("Scan local apps without saving choices or setup completion")
            }
            Button(action: { controller.dismiss() }) { Text(verbatim: "Open app without saving") }
                .buttonStyle(ClientButtonStyle(enabled: true, prominent: false))
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Open app without saving choices or setup completion")
        }
    }

    private func heading(_ value: String) -> some View {
        Text(verbatim: value).font(.largeTitle.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
    }

    private func detail(_ value: String) -> some View {
        Text(verbatim: value).font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
