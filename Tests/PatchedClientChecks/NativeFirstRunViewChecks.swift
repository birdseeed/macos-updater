import Foundation
import SwiftUI
import AppKit
import PatchedShell
import PatchedScheduling
@_spi(Testing) import PatchedClient
@_spi(Testing) import PatchedNetworking
@_spi(Testing) import PatchedUpdatePreferences

// Independent fixed view/session contract. No default native preference opener is invoked.
private let nfvGeneration = "pat2667-view-generation"
private let nfvPrincipal = SchedulingPrincipal("pat2667-view-owner")
private let nfvScope = "pat2667-view-private-fixture"
private func nfvJSON(_ value: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
}
private func nfvBytes(host: String = "", port: String = "", manual: Bool = false) throws -> Data {
    let v1 = try nfvJSON(["schema": 1, "principal": nfvPrincipal.value, "storeScope": nfvScope,
        "revision": 0, "exclusions": [], "skips": [], "mutations": []])
    let v2 = try nfvJSON(["schema": 2, "preferences": String(decoding: v1, as: UTF8.self),
        "settings": ["dailyChecks": true, "notifications": true, "automaticUpdates": false, "pause": NSNull()],
        "settingsMutations": []])
    return try nfvJSON(["schema": 3, "scheduled": String(decoding: v2, as: UTF8.self),
        "setup": ["failureReports": true, "completed": false,
                  "networkDraft": ["mode": manual ? "manualHTTP" : "system", "host": host, "port": port]],
        "setupMutations": []])
}
@MainActor private final class NFVStore: PreferenceStore {
    var bytes: Data?
    var reads = 0, writes = 0
    var unavailable = false, refuseWrite = false
    init(_ bytes: Data?) { self.bytes = bytes }
    func read(maximumBytes: Int) -> PreferenceRead {
        reads += 1
        if unavailable { return .unavailable }
        guard let bytes else { return .missing }
        return bytes.count <= maximumBytes ? .bytes(bytes) : .unavailable
    }
    func compareAndSwap(expected: Data?, proposed: Data, maximumBytes: Int) -> PreferenceCommit {
        writes += 1
        guard !refuseWrite, proposed.count <= maximumBytes else { return .notCommitted }
        guard expected == bytes else { return .conflict }
        bytes = proposed; return .committed
    }
}
private final class NFVReads: @unchecked Sendable {
    private let lock = NSLock(); private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func record() { lock.lock(); value += 1; lock.unlock() }
}
@MainActor private final class NFVRequest: NativeNetworkObservationRequest { func cancel() {} }
@MainActor private final class NFVProvider: NativeNetworkObservationProvider {
    var calls = 0
    func begin(completion: @escaping @MainActor (NativeNetworkObservation) -> Void) -> any NativeNetworkObservationRequest {
        calls += 1; return NFVRequest()
    }
}
@MainActor private final class NFVOpen { var count = 0 }
@MainActor private struct NFVFixture {
    let root: URL
    let store: NFVStore
    let reads: NFVReads
    let provider: NFVProvider
    let opened: NFVOpen
    let recorder: Recorder
    let preferences: PreferenceSession
    let navigation: ShellNavigation
    let applications: LocalApplicationsController
    let inspection: ClientController
    let network: NativeNetworkSettingsController
    let controller: NativeFirstRunController
    let session: NativeClientSession
    init(_ store: NFVStore) throws {
        root = try newDirectory("pat2667-view-applications")
        let contents = root.appendingPathComponent("ViewFixture.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleDisplayName": "View fixture",
            "CFBundleIdentifier": "example.pat2667.view", "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1"], format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        self.store = store
        let reads = NFVReads(); self.reads = reads
        applications = LocalApplicationsController(inventory: LocalApplicationInventory(fixtureRoots: [root.path], observer: { _ in reads.record() }))
        navigation = ShellNavigation(destination: .applications, settingsSection: .updates, drafts: ShellDrafts(values: [:]))
        recorder = Recorder(); inspection = ready(scripted(recorder))
        provider = NFVProvider(); network = NativeNetworkSettingsController(provider: provider)
        opened = NFVOpen(); let opener = opened
        preferences = PreferenceSession(store: store, principal: nfvPrincipal, storeScope: nfvScope,
            generation: nfvGeneration, queueID: "pat2667-view-queue")
        controller = NativeFirstRunController(navigation: navigation, applications: applications, network: network,
            preferences: preferences, generation: nfvGeneration, onOpen: { opener.count += 1 })
        session = NativeClientSession(navigation: navigation, applications: applications, inspection: inspection,
            network: network, firstRun: controller)
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
    // Mandatory before rendering or any potentially scanning path: only private fixture owners.
    func assertOwners() throws {
        try expect(session.firstRun === controller && session.navigation === navigation && session.applications === applications &&
            session.inspection === inspection && session.network === network && controller.navigation === navigation &&
            controller.applications === applications && controller.network === network, "Replaced owner: refusing fixture render/action")
    }
    func assertIdle() throws {
        try expect(reads.count == 0 && applications.observation == nil && applications.phase == .idle && provider.calls == 0 &&
            !network.isRefreshing && network.snapshot == nil && network.choice == nil && inspection.phase == .ready,
            "Presentation caused scan/provider/inspection effects")
    }
    // Capture both draft and accepted owner projections; painting may not alter either.
    func fingerprint() -> [String] {
        [String(describing: controller.step), String(describing: controller.localState), String(describing: controller.saveStatus),
         String(controller.isPresented), String(controller.networkPresented), String(controller.dailyChecks),
         String(controller.notifications), String(controller.failureReports), controller.statusText,
         String(describing: controller.firstRunSetup), String(describing: controller.acceptedRevision),
         String(describing: preferences.firstRunSetup), String(describing: preferences.acceptedRevision),
         String(describing: navigation.destination), String(describing: navigation.settingsSection),
         String(describing: navigation.drafts), String(describing: network.mode), network.host, network.port,
         String(network.revision), String(describing: network.snapshot), String(describing: network.choice),
         String(describing: inspection.phase), String(describing: inspection.text), String(session.inspectionPresented),
         String(store.reads), String(store.writes), String(opened.count), String(provider.calls), String(reads.count)]
    }
}
// Bounded private offscreen AppKit paint. No activation, show, launch, keyboard or VO proof.
@MainActor private func nfvPaint(_ session: NativeClientSession, dark: Bool = false) throws -> Data {
    let app = NSApplication.shared
    if app.activationPolicy() != .prohibited { _ = app.setActivationPolicy(.prohibited) }
    try expect(app.activationPolicy() == .prohibited && !app.isActive, "View capture must stay prohibited/inactive")
    let host = NSHostingView(rootView: NativeClientRootView(session: session)
        .frame(width: 680, height: 520).environment(\.colorScheme, dark ? .dark : .light))
    host.frame = NSRect(x: 0, y: 0, width: 680, height: 520)
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.close() }
    host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    let deadline = Date().addingTimeInterval(0.15)
    while Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.01)))
    }
    host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CheckFailure(description: "First-run bitmap unavailable") }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try expect(!window.isVisible && !app.isActive && app.activationPolicy() == .prohibited, "First-run capture became visible/active")
    guard let bytes = bitmap.representation(using: .png, properties: [:]) else { throw CheckFailure(description: "First-run pixels unavailable") }
    try expect(bitmap.pixelsWide >= 680 && bitmap.pixelsHigh >= 520 && bytes.count > 100, "Blank/undersized first-run capture")
    return bytes
}
@MainActor private func nfvSafePaint(_ f: NFVFixture, dark: Bool = false) async throws -> Data {
    try f.assertOwners(); try f.assertIdle()
    let before = f.fingerprint(), bytes = f.store.bytes, inspector = await f.recorder.count
    let pixels = try nfvPaint(f.session, dark: dark)
    try expect(f.fingerprint() == before && f.store.bytes == bytes, "Render changed model, persistence, opener or provider")
    try expect(await f.recorder.count == inspector, "Render called artifact inspector")
    try f.assertOwners(); try f.assertIdle()
    return pixels
}
@MainActor private func nfvViewSource() throws -> String { code(try source("Sources/PatchedClient/NativeFirstRunView.swift")) }

@MainActor func registerNativeFirstRunViewChecks() {
    check("PAT2667 view: ordinary session owns one inert presented first-run controller") {
        let s = NativeClientSession()
        try expect(s.firstRun.navigation === s.navigation && s.firstRun.applications === s.applications && s.firstRun.network === s.network,
                   "Ordinary session duplicated owners")
        try expect(s.firstRun.isPresented && s.firstRun.step == .welcome && s.firstRun.localState == .unopened &&
            s.firstRun.acceptedRevision == nil && s.firstRun.firstRunSetup == nil && s.applications.phase == .idle &&
            s.applications.observation == nil && s.inspection.phase == .needsSelection && !s.network.isRefreshing && s.network.snapshot == nil,
            "Ordinary construction performed work or suppressed welcome")
    }
    check("PAT2667 view: old Testing initializer suppresses first-run with exact shared owners") {
        let f = try NFVFixture(NFVStore(try nfvBytes())); defer { f.cleanup() }
        let s = NativeClientSession(navigation: f.navigation, applications: f.applications, inspection: f.inspection, network: f.network)
        try expect(!s.firstRun.isPresented && s.firstRun.navigation === f.navigation && s.firstRun.applications === f.applications &&
            s.firstRun.network === f.network && s.network === f.network, "Legacy fixture paint contract/owner changed")
        try expect(f.store.reads == 0 && f.store.writes == 0 && f.opened.count == 0, "Testing construction opened preferences")
        try f.assertIdle()
    }
    check("PAT2667 view: explicit injected first-run is retained without loads or provider work") {
        let f = try NFVFixture(NFVStore(try nfvBytes())); defer { f.cleanup() }
        try f.assertOwners(); try f.assertIdle()
        try expect(f.controller.isPresented && f.controller.localState == .unopened && f.store.reads == 0 && f.store.writes == 0 && f.opened.count == 0,
                   "Session altered explicit controller state")
    }
    check("PAT2667 view: repeated welcome paint has no preference scanner provider or inspector effects") {
        let f = try NFVFixture(NFVStore(try nfvBytes())); defer { f.cleanup() }
        _ = try await nfvSafePaint(f); _ = try await nfvSafePaint(f)
        try expect(f.controller.step == .welcome && f.store.reads == 0 && f.opened.count == 0, "Welcome autoloaded")
    }
    check("PAT2667 view: actual root paints distinct welcome and review over same owners") {
        let f = try NFVFixture(NFVStore(try nfvBytes())); defer { f.cleanup() }
        let welcome = try await nfvSafePaint(f)
        try f.assertOwners(); f.controller.advance()
        try expect(f.controller.step == .review && f.store.writes == 0, "Welcome action did not load only")
        let review = try await nfvSafePaint(f)
        try expect(welcome != review, "Root did not paint first-run review state")
    }
    check("PAT2667 view: actual root paints distinct review and Find apps after partial save") {
        let f = try NFVFixture(NFVStore(try nfvBytes())); defer { f.cleanup() }; try f.assertOwners()
        f.controller.advance(); let review = try await nfvSafePaint(f); f.controller.advance()
        try expect(f.controller.step == .findApps && f.preferences.firstRunSetup?.completed == false && f.store.writes == 1, "Partial review save missing")
        try expect(try await nfvSafePaint(f) != review, "Find apps state not painted")
    }
    check("PAT2667 view: save failure paints differently while preserving opt-outs and unsaved state") {
        let f = try NFVFixture(NFVStore(try nfvBytes())); defer { f.cleanup() }; try f.assertOwners()
        f.controller.advance(); let loaded = try await nfvSafePaint(f)
        f.controller.edit(dailyChecks: false, notifications: false, failureReports: false)
        f.store.refuseWrite = true; f.controller.advance()
        try expect(f.controller.step == .review && f.controller.saveStatus == .unsaved && !f.controller.failureReports &&
            f.controller.statusText.lowercased().contains("unsaved"), "Failure hid/discarded opt-outs")
        try expect(try await nfvSafePaint(f) != loaded, "Failure/draft state not painted")
    }
    check("PAT2667 view: shared Network route paints distinctly and return retains opt-outs and literal draft") {
        try expect(try nfvViewSource().contains("NativeNetworkSettingsView(controller: controller.network, probe: controller.networkProbe)"), "Setup must compose the retained Network child")
        let f = try NFVFixture(NFVStore(try nfvBytes())); defer { f.cleanup() }; try f.assertOwners()
        f.controller.advance(); f.controller.edit(dailyChecks: false, notifications: false, failureReports: false)
        let review = try await nfvSafePaint(f); let reads = f.store.reads, writes = f.store.writes
        f.controller.showNetwork(); f.network.edit(mode: .manualHTTP, host: "view.invalid", port: "abc")
        try expect(f.controller.networkPresented, "Network route absent")
        try expect(try await nfvSafePaint(f) != review, "Root did not paint shared Network view")
        f.controller.returnFromNetwork(); _ = try await nfvSafePaint(f)
        try expect(!f.controller.networkPresented && !f.controller.dailyChecks && !f.controller.notifications && !f.controller.failureReports &&
            f.network.host == "view.invalid" && f.network.port == "abc" && f.store.reads == reads && f.store.writes == writes,
            "Network return reset/applied/persisted declarations")
    }
    check("PAT2667 view: 680 by 520 light and dark long-draft paints remain inert") {
        let f = try NFVFixture(NFVStore(try nfvBytes())); defer { f.cleanup() }; try f.assertOwners()
        f.controller.advance(); f.controller.showNetwork()
        f.network.edit(mode: .manualHTTP, host: String(repeating: "long-draft-", count: 23), port: "abc")
        let light = try await nfvSafePaint(f), dark = try await nfvSafePaint(f, dark: true)
        try expect(light != dark && f.network.host.count > 200, "Appearance not differentiated or long draft discarded")
    }
    check("PAT2667 view: dismiss restores existing shell and present restores setup without effects") {
        let f = try NFVFixture(NFVStore(try nfvBytes())); defer { f.cleanup() }; try f.assertOwners()
        let welcome = try await nfvSafePaint(f); f.controller.dismiss()
        let shell = try await nfvSafePaint(f)
        try expect(!f.controller.isPresented && shell != welcome, "Dismiss did not restore real shell")
        f.controller.present(); _ = try await nfvSafePaint(f)
        try expect(f.controller.isPresented && f.store.reads == 0 && f.store.writes == 0 && f.opened.count == 0, "Presentation acquired effects")
    }
    check("PAT2667 view: actual root observes shared first-run and retains all existing real children") {
        let text = code(try source("Sources/PatchedClient/NativeClientSession.swift"))
        for token in ["NativeFirstRunView(", "session.firstRun", "isPresented", "@ObservedObject", "ShellView(",
            "LocalApplicationsView(", "ActivityView(", "LicenceView(", "ClientView(", "NativeNetworkSettingsView(controller: session.network, probe: session.networkProbe)",
            "applicationsController: session.applications", "case .applications", "case .updates", "case .activity", "case .licence"] {
            try expect(text.contains(token), "Root lacks shared wiring/retained real child: \(token)")
        }
        // Dedicated observation is needed because the session's published fields do not forward the child.
        try expect(text.components(separatedBy: "@ObservedObject").count >= 3, "Root does not observe first-run changes directly")
    }
    check("PAT2667 view: copy distinguishes declarations unavailable capabilities and explicit bypasses") {
        let text = try nfvViewSource()
        for token in ["Keep your Mac apps up to date", "You choose what updates", "Check daily", "Notify me about updates",
            "Send failed-update reports when reporting is available", "Reporting is unavailable in this build. Nothing is sent.",
            "Help improve app coverage", "Install updates automatically", "Optional helper",
            "Unavailable in this build. Setup does not install a helper.", "App Management",
            "Status unavailable. Finishing setup does not grant macOS permission.", "Network settings", "Return to setup",
            "Find apps on this Mac", "Find apps", "Open Updates without scanning", "Scan without saving choices",
            "Open app without saving", "Reload saved preferences"] {
            try expect(text.contains(token), "Required finite first-run copy absent: \(token)")
        }
        let lower = text.lowercased()
        try expect(lower.contains("running") && lower.contains("confirm") && lower.contains("exclu"), "Running-app confirmation/exclusion explanation absent")
        try expect(text.contains(".disabled(true)") && text.contains(".constant(false)"), "Unavailable choices lack disabled OFF declaration")
    }
    check("PAT2667 view: controls bind retained draft and explicit methods instead of private stores") {
        let text = try nfvViewSource()
        for token in ["@ObservedObject", "NativeFirstRunController", "controller.dailyChecks", "controller.notifications", "controller.failureReports",
            "controller.edit(", "controller.advance()", "controller.back()", "controller.findApps()", "controller.openUpdates()",
            "controller.scanWithoutSaving()", "controller.dismiss()", "controller.openPreferences()", "controller.createFreshPreferences()",
            "controller.showNetwork()", "controller.returnFromNetwork()", "controller.networkPresented", "controller.localState",
            "controller.statusText", "NativeNetworkSettingsView(controller: controller.network, probe: controller.networkProbe)", "Binding(", "ClientButtonStyle("] {
            try expect(text.contains(token), "View lacks exact shared action/state binding: \(token)")
        }
    }
    check("PAT2667 view: source declares scroll keyboard accessibility and no lifecycle or factory authority") {
        let view = try nfvViewSource(), session = code(try source("Sources/PatchedClient/NativeClientSession.swift"))
        for token in ["ScrollView", ".keyboardShortcut(", ".accessibilityLabel("] {
            try expect(view.contains(token), "Missing layout/accessibility declaration: \(token)")
        }
        for token in ["NativeFirstRunController(", "NativeNetworkSettingsController(", "LocalApplicationsController(", "PreferenceSession(", "NativeNetworkSettingsController.native("] {
            try expect(!view.contains(token), "View manufactures a second authority owner: \(token)")
        }
        for text in [view, session] {
            for token in [".onAppear", ".task", "Task {", "Task{", "Timer", "URLSession", "URLRequest", "SMAppService", "AXIsProcessTrusted",
                "NativePreferenceContext", "FileManager", "UserDefaults", "NWPathMonitor", "DispatchQueue", ".scan()", ".refresh()", ".applyChoice()"] {
                try expect(!text.contains(token), "Presentation source acquired effect/factory authority: \(token)")
            }
        }
    }
    check("PAT2667 view: missing and unavailable storage remain explicit distinct render states") {
        let missing = try NFVFixture(NFVStore(nil)); defer { missing.cleanup() }; try missing.assertOwners()
        missing.controller.openPreferences(); let missingPaint = try await nfvSafePaint(missing)
        let badStore = NFVStore(nil); badStore.unavailable = true
        let unavailable = try NFVFixture(badStore); defer { unavailable.cleanup() }; try unavailable.assertOwners()
        unavailable.controller.openPreferences(); let unavailablePaint = try await nfvSafePaint(unavailable)
        try expect(missing.controller.localState == .missing && unavailable.controller.localState == .unavailable && missingPaint != unavailablePaint,
                   "Missing/unavailable state collapsed or not visibly distinguished")
        try expect(missing.store.writes == 0 && unavailable.store.writes == 0 && missing.preferences.firstRunSetup == nil && unavailable.preferences.firstRunSetup == nil,
                   "Rendering created/reset preferences")
    }
    check("PAT2667 view: back dismiss and repaint retain all three opt-outs without extra persistence") {
        let f = try NFVFixture(NFVStore(try nfvBytes())); defer { f.cleanup() }; try f.assertOwners()
        f.controller.advance(); f.controller.edit(dailyChecks: false, notifications: false, failureReports: false)
        let reads = f.store.reads, writes = f.store.writes
        f.controller.back(); f.controller.dismiss(); f.controller.present(); _ = try await nfvSafePaint(f)
        try expect(!f.controller.dailyChecks && !f.controller.notifications && !f.controller.failureReports && f.store.reads == reads && f.store.writes == writes,
                   "Back/dismiss/presentation lost opt-outs or performed persistence")
    }
    check("PAT2667 edge: pre-load opt-outs survive first explicit stored-v3 load and stay unsaved") {
        let f = try NFVFixture(NFVStore(try nfvBytes())); defer { f.cleanup() }; try f.assertOwners()
        f.controller.edit(dailyChecks: false, notifications: false, failureReports: false)
        try expect(f.store.reads == 0 && f.store.writes == 0, "Pre-load edit acquired persistence")
        f.controller.openPreferences()
        try expect(!f.controller.dailyChecks && !f.controller.notifications && !f.controller.failureReports && f.controller.saveStatus == .unsaved,
                   "First explicit load overwrote editable opt-outs or claimed them saved")
        try expect(f.controller.firstRunSetup == f.preferences.firstRunSetup && f.preferences.firstRunSetup?.failureReports == true &&
            f.controller.acceptedRevision == f.preferences.acceptedRevision && f.store.reads == 1 && f.store.writes == 0,
            "Accepted owner was changed/mirrored instead of projecting stored state")
        try f.assertIdle()
    }
    check("PAT2667 edge: external shared Network draft edit alone marks loaded setup unsaved without I/O") {
        let f = try NFVFixture(NFVStore(try nfvBytes(host: "stored.invalid", port: "8080", manual: true))); defer { f.cleanup() }; try f.assertOwners()
        f.controller.openPreferences()
        try expect(f.controller.saveStatus == .loaded && f.network.host == "stored.invalid" && f.network.port == "8080", "Stored-draft restoration falsely marked dirty")
        let reads = f.store.reads, writes = f.store.writes, opened = f.opened.count, accepted = f.preferences.firstRunSetup
        f.network.edit(mode: .manualHTTP, host: "external.invalid", port: "abc")
        try expect(f.controller.saveStatus == .unsaved && f.network.host == "external.invalid" && f.network.port == "abc",
                   "Shared Network edit was not reflected as unsaved")
        _ = f.network.text; _ = f.controller.statusText; _ = f.controller.firstRunSetup
        try expect(f.store.reads == reads && f.store.writes == writes && f.opened.count == opened && f.preferences.firstRunSetup == accepted &&
            f.controller.firstRunSetup == accepted && f.network.snapshot == nil && !f.network.isRefreshing,
            "Draft/bookkeeping getters wrote, probed or claimed new accepted settings")
        try f.assertIdle()
    }
}
