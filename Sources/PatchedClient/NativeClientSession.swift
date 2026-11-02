import SwiftUI
import PatchedShell
import PatchedActivity
import PatchedUI
import PatchedNetworking

/// Retains display selection and read-only controllers for the shared client session.
/// Construction and presentation do no work; Scan and Check remain explicit actions.
@MainActor public final class NativeClientSession: ObservableObject {
    public let navigation: ShellNavigation
    public let applications: LocalApplicationsController
    public let inspection: ClientController
    public let network: NativeNetworkSettingsController
    public var networkProbe: NativeNetworkProbeController { firstRun.networkProbe }
    public let firstRun: NativeFirstRunController
    public let scheduleSettings: NativeScheduleSettingsController
    public let scheduleDriver: NativeScheduleDriver
    public let activity: NativeActivityController
    @Published public private(set) var inspectionPresented = false

    public convenience init() { self.init(rawProbeEndpoint: nil) }

    /// Explicit development configuration; construction performs no observation or transport.
    public static func controlledDevelopment(rawProbeEndpoint: String) -> NativeClientSession {
        NativeClientSession(rawProbeEndpoint: rawProbeEndpoint)
    }
    private init(rawProbeEndpoint: String?) {
        let resolvedNavigation = ShellNavigation(destination: .updates, settingsSection: .updates,
            drafts: ShellDrafts(values: [:]))
        let resolvedApplications = LocalApplicationsController()
        let network: NativeNetworkSettingsController
        network = .native()
        navigation = resolvedNavigation
        applications = resolvedApplications
        inspection = ClientController()
        self.network = network
        firstRun = NativeFirstRunController(navigation: resolvedNavigation,
            applications: resolvedApplications, network: network,
            networkProbe: NativeNetworkProbeController(settings: network, rawProbeEndpoint: rawProbeEndpoint))
        scheduleSettings = NativeScheduleSettingsController(firstRun: firstRun)
        scheduleDriver = NativeScheduleDriver(firstRun: firstRun, applications: resolvedApplications)
        activity = NativeActivityController()
    }
    // Testing-only injection must retain the exact three fixture owners. The nil
    // default suppresses setup to preserve every older fixture's paint contract.
    @_spi(Testing) public init(navigation: ShellNavigation,
        applications: LocalApplicationsController, inspection: ClientController,
        network: NativeNetworkSettingsController? = nil,
        firstRun: NativeFirstRunController? = nil, activity: NativeActivityController? = nil) {
        let resolvedNetwork = network ?? .native()
        let setup = firstRun ?? NativeFirstRunController(navigation: navigation,
            applications: applications, network: resolvedNetwork)
        precondition(setup.navigation === navigation && setup.applications === applications &&
            setup.network === resolvedNetwork, "Testing first-run owners must match the session")
        if firstRun == nil { setup.dismiss() }
        self.navigation = navigation
        self.applications = applications
        self.inspection = inspection
        self.network = resolvedNetwork
        self.scheduleSettings = NativeScheduleSettingsController(firstRun: setup)
        self.scheduleDriver = NativeScheduleDriver(firstRun: setup, applications: applications)
        self.firstRun = setup
        self.activity = activity ?? NativeActivityController()
    }
    public func presentInspection() { inspectionPresented = true }
    public func dismissInspection() { inspectionPresented = false }
    @discardableResult public func showActivityHelp(_ row: ActivityRow) -> Bool {
        guard activity.phase == .loaded, let snapshot = activity.snapshot,
              activity.presentation.rows.contains(row),
              snapshot.events.contains(where: { $0.eventID == row.eventID && $0.attemptID == row.attemptID }),
              activity.selectHelp(eventID: row.eventID) else { return false }
        navigation.select(.support)
        return true
    }
}

/// Composes existing read-only views over the session's stable owners.
public struct NativeClientRootView: View {
    @ObservedObject private var session: NativeClientSession
    @ObservedObject private var firstRun: NativeFirstRunController
    @ObservedObject private var activity: NativeActivityController

    public init(session: NativeClientSession) {
        self.session = session
        self.firstRun = session.firstRun
        self.activity = session.activity
    }

    public var body: some View {
        Group {
            if firstRun.isPresented {
                NativeFirstRunView(controller: session.firstRun)
            } else {
                shell
            }
        }
        .frame(minWidth: 680, minHeight: 520)
    }

    private var shell: some View {
        VStack(spacing: 0) {
            ShellView(navigation: session.navigation,
                destinationContent: { destination in AnyView(destinationView(destination)) },
                settingsContent: { section, drafts in AnyView(settingsView(section, drafts: drafts)) })
            Divider()
            HStack {
                Text(verbatim: "Read-only preview").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button(action: { session.presentInspection() }) {
                    Text(verbatim: "Check a local disk image…")
                }
                .buttonStyle(ClientButtonStyle(enabled: true, prominent: false))
            }
            .padding(12)
        }
        .frame(minWidth: 680, minHeight: 520)
        .sheet(isPresented: Binding(get: { session.inspectionPresented }, set: { presented in
            if presented { session.presentInspection() } else { session.dismissInspection() }
        })) {
            ScrollView {
                VStack(spacing: 0) {
                    ClientView(controller: session.inspection, applicationsController: session.applications)
                    HStack {
                        Spacer()
                        Button(action: { session.dismissInspection() }) { Text(verbatim: "Done") }
                            .buttonStyle(ClientButtonStyle(enabled: true, prominent: false))
                            .keyboardShortcut(.cancelAction)
                    }
                    .padding([.horizontal, .bottom], 20)
                }
            }
            .frame(width: 620, height: 640)
        }
    }

    @ViewBuilder private func destinationView(_ destination: ShellDestination) -> some View {
        switch destination {
        case .applications:
            LocalApplicationsView(controller: session.applications, presentation: .applications)
                .frame(minHeight: 440)
        case .updates:
            LocalApplicationsView(controller: session.applications, presentation: .updates)
                .frame(minHeight: 440)
        case .activity:
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button(action: { session.activity.load() }) { Text(verbatim: "Load local history") }
                        .buttonStyle(ClientButtonStyle(enabled: true, prominent: false))
                    Button(action: { session.activity.createFresh() }) { Text(verbatim: "Create empty history") }
                        .buttonStyle(ClientButtonStyle(enabled: true, prominent: false))
                    Button(action: { session.activity.applyRetention() }) { Text(verbatim: "Apply retention") }
                        .buttonStyle(ClientButtonStyle(enabled: activity.phase == .loaded, prominent: false))
                        .disabled(activity.phase != .loaded)
                }
                ActivityView(presentation: session.activity.presentation,
                    onGetHelp: { row in _ = session.showActivityHelp(row) })
            }
            .frame(height: 440)
        case .licence:
            LicenceView()
        case .support:
            VStack(alignment: .leading, spacing: 12) {
                unavailable("Help & Support", detail: "Support submission is unavailable in this preview. No message or diagnostic report is sent.")
                if let selection = session.activity.helpSelection {
                    Text(verbatim: selection.provenance == .testDouble
                        ? "Test double: selected last-loaded record."
                        : "Local history: selected last-loaded record.")
                    Text(verbatim: "History revision: " + String(selection.revision))
                    Text(verbatim: "Event: " + selection.event.eventID + " • Attempt: " + selection.event.attemptID)
                    let selected = ActivityPresentation.make(ActivitySnapshot(available: true,
                        revision: selection.revision, events: [selection.event]))
                    ForEach(selected.rows, id: \.eventID) { row in
                        Text(verbatim: row.text).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .settings:
            // ShellView supplies the selected settings section through its own closure.
            EmptyView()
        }
    }

    @ViewBuilder private func settingsView(_ section: ShellSettingsSection, drafts: ShellDrafts) -> some View {
        if section == .network {
            NativeNetworkSettingsView(controller: session.network, probe: session.networkProbe)
        } else if section == .updates {
            NativeScheduleSettingsView(controller: session.scheduleSettings)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                unavailable(session.navigation.label(for: section),
                    detail: "Settings are unavailable in this preview. Display drafts are retained for this app session and are not applied or saved.")
                if let draft = drafts.values[section], !draft.isEmpty {
                    Text(verbatim: "Display draft").font(.headline)
                    Text(verbatim: draft).font(.body).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func unavailable(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: title).font(.title2).accessibilityAddTraits(.isHeader)
            Text(verbatim: detail).font(.body).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
