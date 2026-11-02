import Foundation
import Combine
import SwiftUI
import AppKit
import PatchedShell
@_spi(Testing) import PatchedNetworking
import PatchedScheduling
@_spi(Testing) import PatchedClient
@_spi(Testing) import PatchedUpdatePreferences

// Independent literal persistence and fake process lifecycle. No timer, observer,
// DMG inspection, native home, permission, download or trusted dispatcher fixture.
private let nsaGeneration = "pat2668-app-generation"
private let nsaPrincipal = SchedulingPrincipal("pat2668-app-owner")
private let nsaScope = "pat2668-app-store"
private func nsaJSON(_ value: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
}
private func nsaBytes(schema: Int = 3, revision: UInt64 = 0, automatic: Bool = false) throws -> Data {
    let v1 = try nsaJSON(["schema": 1, "principal": nsaPrincipal.value, "storeScope": nsaScope,
        "revision": NSNumber(value: revision), "exclusions": [], "skips": [], "mutations": []])
    if schema == 1 { return v1 }
    let v2 = try nsaJSON(["schema": 2, "preferences": String(decoding: v1, as: UTF8.self),
        "settings": ["dailyChecks": true, "notifications": true, "automaticUpdates": automatic, "pause": NSNull()],
        "settingsMutations": []])
    if schema == 2 { return v2 }
    return try nsaJSON(["schema": 3, "scheduled": String(decoding: v2, as: UTF8.self),
        "setup": ["failureReports": false, "completed": true,
            "networkDraft": ["mode": "manualHTTP", "host": "proxy.fixture", "port": "8080"]], "setupMutations": []])
}
@MainActor private final class NSAStore: PreferenceStore {
    enum Fault: String, CaseIterable { case none, unavailable, conflict, notCommitted, uncertain, readback }
    var bytes: Data?; var reads = 0; var writes = 0; var fault: Fault = .none
    var mismatch = false
    init(_ bytes: Data?) { self.bytes = bytes }
    func read(maximumBytes: Int) -> PreferenceRead {
        reads += 1
        if fault == .unavailable { return .unavailable }
        if mismatch { return .bytes(Data("invalid-readback".utf8)) }
        guard let bytes else { return .missing }
        return bytes.count <= maximumBytes ? .bytes(bytes) : .unavailable
    }
    func compareAndSwap(expected: Data?, proposed: Data, maximumBytes: Int) -> PreferenceCommit {
        writes += 1
        guard proposed.count <= maximumBytes else { return .notCommitted }
        if fault == .conflict || expected != bytes { return .conflict }
        if fault == .notCommitted { return .notCommitted }
        bytes = proposed
        if fault == .readback { mismatch = true }
        return fault == .uncertain ? .uncertain : .committed
    }
}
@MainActor private final class NSANetworkRequest: NativeNetworkObservationRequest { func cancel() {} }
@MainActor private final class NSANetwork: NativeNetworkObservationProvider {
    var calls = 0
    func begin(completion: @escaping @MainActor (NativeNetworkObservation) -> Void) -> any NativeNetworkObservationRequest {
        calls += 1; return NSANetworkRequest()
    }
}
@MainActor private final class NSARequest: NativeScheduleFixtureRequest { var cancellations = 0; func cancel() { cancellations += 1 } }
@MainActor private final class NSASubscription: NativeScheduleFixtureSubscription { var cancellations = 0; func cancel() { cancellations += 1 } }
@MainActor private final class NSAHooks: NativeScheduleFixtureHooks {
    var subscriptions = 0; let token = NSASubscription()
    var synchronousEvent: NativeScheduleFixtureEvent?
    var receive: (@MainActor (NativeScheduleFixtureEvent) -> Void)?
    func subscribe(_ receive: @escaping @MainActor (NativeScheduleFixtureEvent) -> Void) -> any NativeScheduleFixtureSubscription {
        subscriptions += 1; self.receive = receive
        if let synchronousEvent { receive(synchronousEvent) }
        return token
    }
    // Deliberately can deliver after cancel: driver must fence stale callbacks itself.
    func send(_ event: NativeScheduleFixtureEvent) { receive?(event) }
}
@MainActor private final class NSADispatcher: NativeScheduleFixtureDispatcher {
    var synchronous = false
    var requests: [NSARequest] = []; var completions: [@MainActor (Bool) -> Void] = []
    func begin(completion: @escaping @MainActor (Bool) -> Void) -> any NativeScheduleFixtureRequest {
        let request = NSARequest(); requests.append(request); completions.append(completion)
        if synchronous { completion(true) }
        return request
    }
    func finish(_ index: Int = 0, success: Bool = true) { completions[index](success) }
}
@MainActor private final class NSAClock {
    var reads = 0; var second: UInt64 = 1000; var invalid = false
    func raw() -> NativeScheduleClockRawRead {
        reads += 1
        return NativeScheduleClockRawRead(wallSeconds: invalid ? -1 : Double(second),
            continuousBeforeNanoseconds: second * 1_000_000_000,
            continuousAfterNanoseconds: second * 1_000_000_000,
            bootBefore: "12345678-1234-1234-1234-123456789abc", bootAfter: "12345678-1234-1234-1234-123456789abc")
    }
}
@MainActor private struct NSA {
    let store: NSAStore; let preferences: PreferenceSession; let firstRun: NativeFirstRunController
    let session: NativeClientSession; let settings: NativeScheduleSettingsController
    let networkProvider: NSANetwork
    let clock: NSAClock; let hooks: NSAHooks; let dispatcher: NSADispatcher; let driver: NativeScheduleDriver
    init(bytes: Data? = nil, missingChecker: Bool = false, generation: String = nsaGeneration) throws {
        store = NSAStore(bytes)
        preferences = PreferenceSession(store: store, principal: nsaPrincipal, storeScope: nsaScope,
            generation: nsaGeneration, queueID: "pat2668-app-queue")
        let navigation = ShellNavigation(destination: .settings, settingsSection: .updates,
            drafts: ShellDrafts(values: [.network: "Keep network draft"]))
        let applications = LocalApplicationsController(inventory: LocalApplicationInventory(fixtureRoots: []))
        networkProvider = NSANetwork()
        let network = NativeNetworkSettingsController(provider: networkProvider)
        firstRun = NativeFirstRunController(navigation: navigation, applications: applications, network: network,
            preferences: preferences, generation: generation, initiallyPresented: false)
        session = NativeClientSession(navigation: navigation, applications: applications, inspection: ClientController(),
            network: network, firstRun: firstRun)
        settings = session.scheduleSettings
        clock = NSAClock(); hooks = NSAHooks(); dispatcher = NSADispatcher()
        let raw = clock
        driver = NativeScheduleDriver(firstRun: firstRun, applications: applications,
            clock: NativeScheduleClock(rawReader: { raw.raw() }), hooks: hooks,
            dispatcher: missingChecker ? nil : dispatcher)
    }
    func open() { firstRun.openPreferences(); settings.reload() }
    func started() throws {
        open()
        try expect(settings.testPreferenceOwner === preferences && driver.testPreferenceOwner === preferences,
            "Must acquire exact first-run owner before any fixture dispatch")
        try expect(driver.start(), "Injected fake checker failed explicit start")
        try expect(dispatcher.requests.count == 1 && driver.physicalCheckInFlight, "First opportunity did not create exactly one physical fake check")
    }
    func idle() throws {
        try expect(networkProvider.calls == 0 && clock.reads == 0 && hooks.subscriptions == 0 && dispatcher.requests.isEmpty,
            "Construction/render/missing capability invoked clock, hooks or checker")
        try expect(session.applications.observation == nil && session.applications.phase == .idle && session.inspection.phase == .needsSelection,
            "Schedule invoked inventory/DMG inspection")
    }
}
private func nsaAccepted(_ value: PreferenceEditResult) -> Bool {
    switch value { case .accepted, .replayed: return true; case .refused: return false }
}
// Harmless public AppKit target/action fixture for the hidden-host press harness.
@MainActor private struct NSAHarmlessNativeButton: NSViewRepresentable {
    let enabled: Bool
    var count = 1
    let action: @MainActor () -> Void
    @MainActor final class Coordinator: NSObject {
        var action: @MainActor () -> Void
        init(action: @escaping @MainActor () -> Void) { self.action = action }
        @objc func press(_ sender: NSButton) { action() }
    }
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 100))
        for index in 0..<count {
            let title = "Reload saved schedule settings"
            let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.press(_:)))
            button.frame = NSRect(x: 0, y: index * 40, width: 300, height: 32)
            button.setAccessibilityLabel(title); button.setAccessibilityTitle(title)
            button.isEnabled = enabled
            container.addSubview(button)
        }
        return container
    }
    func updateNSView(_ view: NSView, context: Context) { context.coordinator.action = action }
}
@MainActor private func nsaPaint<V: View>(_ view: V, dark: Bool = false,
    activateReload: Bool = false, target: String = "Reload saved schedule settings") throws -> Data {
    let app = NSApplication.shared
    if app.activationPolicy() != .prohibited { _ = app.setActivationPolicy(.prohibited) }
    try expect(app.activationPolicy() == .prohibited && !app.isActive, "Offscreen capture must remain inactive")
    let host = NSHostingView(rootView: view.frame(width: 1000, height: 800)
        .environment(\.colorScheme, dark ? .dark : .light))
    host.frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.close() }
    host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    let deadline = Date().addingTimeInterval(0.20)
    while Date() < deadline { _ = RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.01))) }
    host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    if activateReload {
        // Only this process's inactive, hidden hosting tree. No AX trust,
        // external process, event injection, app launch or native storage.
        var visited = Set<ObjectIdentifier>()
        var buttons: [any NSAccessibilityProtocol] = []
        var observed: [String] = []
        var appKitButtons: [String] = []
        var namedNativeButtons: [NSButton] = []
        var appKitButtonCount = 0
        var soleAppKitButton: NSButton?
        func visit(_ object: AnyObject) {
            guard visited.count < 4096, visited.insert(ObjectIdentifier(object)).inserted else { return }
            // Use the public NSButton cast: an AXUnknown SwiftUI implementation
            // class name does not establish conformance or a usable public title.
            // Keep this inventory separate from the first few AX ancestors so
            // it still reports controls deep inside the actual Schedule root.
            if let button = object as? NSButton {
                appKitButtonCount += 1
                if button.title.lowercased() == target.lowercased() { namedNativeButtons.append(button) }
                if appKitButtonCount == 1 { soleAppKitButton = button }
                if appKitButtons.count < 16 {
                    let action = button.action.map { NSStringFromSelector($0) } ?? "nil"
                    let fields = [String(reflecting: type(of: button)),
                        "title=" + String(button.title.prefix(80)),
                        "attributedTitle=" + String(button.attributedTitle.string.prefix(80)),
                        "identifier=" + String((button.identifier?.rawValue ?? "nil").prefix(80)),
                        "accessibilityIdentifier=" + String((button.accessibilityIdentifier() ?? "nil").prefix(80)),
                        "action=" + String(action.prefix(80)),
                        "hasTarget=" + String(button.target != nil),
                        "enabled=" + String(button.isEnabled)]
                    appKitButtons.append(fields.joined(separator: " "))
                }
            }
            if let accessible = object as? any NSAccessibilityProtocol {
                if observed.count < 12 {
                    observed.append(String((String(reflecting: type(of: object)) + " role=" + (accessible.accessibilityRole()?.rawValue ?? "nil") + " label=" + (accessible.accessibilityLabel() ?? "nil") + " title=" + (accessible.accessibilityTitle() ?? "nil")).prefix(180)))
                }
                if accessible.accessibilityRole() == .button,
                   accessible.accessibilityLabel()?.lowercased() == target.lowercased() || accessible.accessibilityTitle()?.lowercased() == target.lowercased() { buttons.append(accessible) }
                for child in accessible.accessibilityChildren() ?? [] { visit(child as AnyObject) }
            }
            if let view = object as? NSView { for child in view.subviews { visit(child) } }
        }
        visit(host)
        let diagnostics = observed.joined(separator: " | ")
            + " NSButtonCount=" + String(appKitButtonCount) + " NSButtons=" + appKitButtons.joined(separator: " | ")
            + " namedNativeButtonCount=" + String(namedNativeButtons.count)
            + " matchedAXTypes=" + buttons.map { String(reflecting: type(of: $0)) }.joined(separator: " | ")
            + " visited=" + String(visited.count)
        if buttons.count == 1 {
            if namedNativeButtons.count == 1 {
                let button = namedNativeButtons[0]
                try expect(visited.count < 4096, "Matched actual NSButton traversal is incomplete")
                try expect(button.isEnabled, "Matched actual NSButton is disabled")
                try expect(button.action != nil && button.target != nil, "Matched actual NSButton lacks public target/action")
                // Invoke the real public target/action exactly once. Hidden inactive
                // AppKit controls need no preceding AX press or synthetic callback.
                button.performClick(nil)
            } else if namedNativeButtons.count > 1 {
                throw CheckFailure(description: "Expected exactly one actual Reload saved schedule settings AX button or sole hidden NSButton: " + diagnostics)
            } else {
                try expect(buttons[0].accessibilityPerformPress(), "Actual Reload saved schedule settings button refused explicit activation: " + diagnostics)
            }
        } else if buttons.isEmpty, appKitButtonCount == 1, visited.count < 4096,
                  let button = soleAppKitButton {
            // Historical accepted PAT2663 CHECK-MODIFIED RED7 established that the harmless hidden SwiftUI
            // button is an enabled NSButton with erased AX/name/identifier and
            // nil public action/target. Try its public control activation once.
            // A second NSButton or incomplete traversal refuses this fallback;
            // the unchanged real callback assertions decide whether it worked.
            try expect(button.isEnabled, "Sole hidden NSButton is disabled: " + diagnostics)
            button.performClick(nil)
        } else {
            throw CheckFailure(description: "Expected exactly one actual Reload saved schedule settings AX button or sole hidden NSButton: " + diagnostics)
        }
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    }
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CheckFailure(description: "Schedule bitmap unavailable") }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try expect(!window.isVisible && !app.isActive && app.activationPolicy() == .prohibited, "Schedule capture became visible")
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CheckFailure(description: "Schedule PNG unavailable") }
    try expect(png.count > 1000, "Schedule paint is implausibly blank")
    return png
}

@MainActor func registerNativeScheduleAppChecks() {
    check("PAT2668 app: default session retains distinct inert schedule owners and exact setup/application identities") {
        let a = NativeClientSession(), b = NativeClientSession()
        try expect(a.scheduleSettings !== b.scheduleSettings && a.scheduleDriver !== b.scheduleDriver, "Cross-session shared schedule owner")
        try expect(a.scheduleSettings.firstRun === a.firstRun && a.scheduleDriver.firstRun === a.firstRun &&
            a.scheduleDriver.applications === a.applications, "Composition replaced first-run or inventory owner")
        try expect(a.scheduleSettings.settings == nil && a.scheduleSettings.acceptedRevision == nil &&
            a.scheduleDriver.phase == .idle && !a.scheduleDriver.physicalCheckInFlight && !a.scheduleDriver.checkCapabilityAvailable,
            "Ordinary composition invented accepted state/capability")
    }
    check("PAT2668 app: fake construction and every root route paint are inert and preserve all draft/owner identities") {
        let f = try NSA(bytes: nsaBytes())
        for destination in ShellDestination.allCases {
            f.session.navigation.select(destination)
            _ = try nsaPaint(NativeClientRootView(session: f.session))
            if destination == .settings {
                for section in ShellSettingsSection.allCases {
                    f.session.navigation.selectSettings(section)
                    _ = try nsaPaint(NativeClientRootView(session: f.session))
                }
            }
        }
        try f.idle()
        try expect(f.store.reads == 0 && f.store.writes == 0 && f.session.scheduleSettings === f.settings &&
            f.settings.firstRun === f.firstRun && f.session.network === f.firstRun.network &&
            f.session.navigation.drafts.values[.network] == "Keep network draft", "Paint replaced owners/draft or opened store")
    }
    check("PAT2668 app: unavailable ordinary checker refuses before clock/hooks/attempt consumption even after accepted setup") {
        let f = try NSA(bytes: nsaBytes(), missingChecker: true); f.firstRun.openPreferences()
        let reads = f.store.reads
        try expect(!f.driver.start() && !f.driver.checkCapabilityAvailable, "Missing trusted checker started")
        try f.idle()
        try expect(f.store.reads == reads && !f.preferences.scheduleRuntimeSnapshot.checkInFlight &&
            f.preferences.scheduleRuntimeSnapshot.clockState == .unavailable, "Missing checker consumed opportunity or read storage")
        try expect(f.driver.statusText.lowercased().contains("unavailable"), "False scheduled check claim")
    }
    check("PAT2668 app: explicit reload binds settings and driver to exact acquired setup PreferenceSession") {
        let f = try NSA(bytes: nsaBytes()); f.open()
        try expect(f.settings.testPreferenceOwner === f.preferences && f.driver.testPreferenceOwner === f.preferences &&
            f.settings.acceptedRevision == 0 && f.settings.settings == f.preferences.scheduleSettings, "Owner bridge/revision/projection missing")
        try expect(f.store.writes == 0, "Reload wrote")
    }
    check("PAT2668 app: unsaved schedule draft survives navigation and never mutates setup/network drafts or disk") {
        let f = try NSA(bytes: nsaBytes()); f.open(); let original = f.store.bytes, setup = f.preferences.firstRunSetup
        f.settings.choose(.dailyChecks(false)); f.session.navigation.select(.applications); f.session.navigation.selectSettings(.updates)
        try expect(f.settings.draft == .dailyChecks(false) && f.store.bytes == original && f.store.writes == 0 &&
            f.preferences.firstRunSetup == setup && f.session.navigation.drafts.values[.network] == "Keep network draft", "Unsaved draft lost or saved")
    }
    for (name, change) in [("daily off", ScheduleSettingsChange.dailyChecks(false)), ("notifications off", .notifications(false)), ("automatic off", .automaticUpdates(false))] {
        check("PAT2668 app: same-owner explicit durable save/readback preserves schema3 setup and network: " + name) {
            let f = try NSA(bytes: nsaBytes()); f.open(); let setup = f.preferences.firstRunSetup
            f.session.network.edit(mode: .manualHTTP, host: "unsaved.fixture", port: "9090")
            f.settings.choose(change)
            try expect(nsaAccepted(f.settings.save()) && f.store.writes == 1 && f.settings.acceptedRevision == 1 &&
                f.preferences.acceptedRevision == 1 && f.settings.settings == f.preferences.scheduleSettings && f.settings.draft == nil,
                "Explicit save did not use accepted CAS owner/readback")
            try expect(f.preferences.firstRunSetup == setup && f.session.network.mode == .manualHTTP &&
                f.session.network.host == "unsaved.fixture" && f.session.network.port == "9090",
                "Schedule save lost schema3 setup/network or applied unsaved network draft")
            let reopened = PreferenceSession(store: f.store, principal: nsaPrincipal, storeScope: nsaScope,
                generation: nsaGeneration, queueID: "reopened")
            _ = reopened.reload(generation: nsaGeneration)
            try expect(reopened.scheduleSettings == f.settings.settings && reopened.firstRunSetup == setup && reopened.acceptedRevision == 1,
                "A second readback did not see durable exact state")
        }
    }
    for schema in [1, 2] {
        check("PAT2668 app: explicit migration from schema\(schema) through same owner remains inert until save") {
            let f = try NSA(bytes: nsaBytes(schema: schema)); f.open()
            try expect(f.settings.acceptedRevision == 0 && f.store.writes == 0 &&
                (schema == 1 ? f.settings.settings == nil : f.settings.settings != nil), "Migration load invented defaults or wrote")
            if schema == 1 { try expect(nsaAccepted(f.settings.migrate()) && f.store.writes == 1, "Explicit same-owner migration refused") }
            f.settings.choose(.dailyChecks(false)); try expect(nsaAccepted(f.settings.save()), "Explicit migration/save unavailable")
            try expect(f.preferences.scheduleSettings?.dailyChecks == false && f.store.writes == (schema == 1 ? 2 : 1), "Migration save wrong")
        }
    }
    for fault in [NSAStore.Fault.conflict, .notCommitted, .uncertain, .readback] {
        check("PAT2668 app: explicit failed save is unsaved and never claims acceptance: " + fault.rawValue) {
            let f = try NSA(bytes: nsaBytes()); f.open(); f.store.fault = fault
            f.settings.choose(.dailyChecks(false)); let result = f.settings.save()
            try expect(!nsaAccepted(result) && f.store.writes == 1 && f.settings.draft == .dailyChecks(false) &&
                f.settings.statusText.lowercased().contains("unsaved"), "Failed CAS/readback granted acceptance or lost retry draft")
            if fault == .conflict || fault == .uncertain || fault == .readback {
                try expect(f.settings.settings == nil && f.settings.acceptedRevision == nil, "Latched failure exposed accepted mirror")
            }
        }
    }
    for name in ["missing", "corrupt", "unavailable"] {
        check("PAT2668 app: " + name + " never resets/creates and hides accepted settings") {
            let bytes: Data? = name == "missing" ? nil : name == "corrupt" ? Data("bad".utf8) : try nsaBytes()
            let f = try NSA(bytes: bytes); if name == "unavailable" { f.store.fault = .unavailable }
            f.open(); f.settings.choose(.dailyChecks(false))
            try expect(!nsaAccepted(f.settings.save()) && f.settings.settings == nil && f.store.writes == 0,
                "Blocked load repaired/reset storage or claimed settings")
        }
    }
    check("PAT2668 app: wrong generation cannot load/save or begin any fake dispatcher") {
        let f = try NSA(bytes: nsaBytes(), generation: "wrong"); f.open(); f.settings.choose(.dailyChecks(false))
        try expect(!nsaAccepted(f.settings.save()) && !f.driver.start() && f.store.reads == 0 && f.store.writes == 0,
            "Wrong generation performed I/O")
        try f.idle()
    }
    check("PAT2668 app: external accepted revision change refuses stale draft and hides optimistic mirror") {
        let f = try NSA(bytes: nsaBytes()); f.open(); f.settings.choose(.dailyChecks(false))
        f.store.bytes = try nsaBytes(revision: 7)
        try expect(!nsaAccepted(f.settings.save()) && f.settings.settings == nil && f.settings.acceptedRevision == nil &&
            f.settings.draft == .dailyChecks(false), "Stale revision overwrote/claimed external state")
    }
    check("PAT2668 app: automatic true explicit edit always refuses without store write") {
        let f = try NSA(bytes: nsaBytes()); f.open(); f.settings.choose(.automaticUpdates(true))
        try expect(!nsaAccepted(f.settings.save()) && f.store.writes == 0 && f.preferences.scheduleSettings?.automaticUpdates == false,
            "Automatic true granted execution or persisted")
    }
    check("PAT2668 app: legacy automatic true is displayed honestly and never grants automatic installation") {
        let f = try NSA(bytes: nsaBytes(automatic: true), missingChecker: true); f.open()
        try expect(f.settings.settings?.automaticUpdates == true && !f.driver.start() &&
            !f.preferences.scheduleRuntimeSnapshot.automaticInstallationAvailable && f.store.writes == 0,
            "Legacy true hidden or turned into execution")
        try f.idle()
    }
    for (utc, zone) in [(Int64(0), "UTC"), (Int64.max, "Etc/GMT+1"), (1, String(repeating: "a", count: 128)), (1, "A_b/C-d")] {
        check("PAT2668 app: inert productive pause declaration accepts exact boundary \(utc)/\(zone)") {
            let choice = SchedulePauseChoice.declared(resumeUTC: utc, displayZone: zone)
            try expect(choice?.resumeUTC == utc && choice?.displayZone == zone, "Valid inert pause declaration refused")
        }
    }
    for (utc, zone) in [(Int64(-1), "UTC"), (0, ""), (0, String(repeating: "a", count: 129)), (0, "/UTC"),
        (0, "UTC/"), (0, "A//B"), (0, "A B"), (0, "A.B"), (0, "é"), (0, "A\nB")] {
        check("PAT2668 app: pause declaration rejects exact invalid syntax \(utc)/\(zone.debugDescription)") {
            try expect(SchedulePauseChoice.declared(resumeUTC: utc, displayZone: zone) == nil, "Malformed pause accepted")
        }
    }
    check("PAT2668 app: explicit pause save/remove preserves absolute UTC, display zone and setup") {
        let f = try NSA(bytes: nsaBytes()); f.open(); let setup = f.preferences.firstRunSetup
        guard let pause = SchedulePauseChoice.declared(resumeUTC: 2000, displayZone: "Europe/Isle_of_Man") else { throw CheckFailure(description: "Pause declaration missing") }
        f.settings.choose(.pause(pause)); try expect(nsaAccepted(f.settings.save()), "Pause save refused")
        try expect(f.preferences.scheduleSettings?.pause == pause, "Pause changed UTC/zone")
        f.settings.choose(.pause(nil)); try expect(nsaAccepted(f.settings.save()) && f.preferences.scheduleSettings?.pause == nil &&
            f.preferences.firstRunSetup == setup, "Resume lost setup or retained pause")
    }
    check("PAT2668 app: fixture explicit start installs one fake hook and dispatches one opportunity exactly once") {
        let f = try NSA(bytes: nsaBytes()); try f.started()
        try expect(f.driver.phase == .running && f.driver.checkCapabilityAvailable && f.hooks.subscriptions == 1 && f.clock.reads == 1,
            "Explicit fixture lifecycle was not started once")
        try expect(f.driver.start() && f.hooks.subscriptions == 1 && f.dispatcher.requests.count == 1, "Repeated start duplicated lifecycle")
        f.driver.stop(); f.dispatcher.finish()
    }
    check("PAT2668 app: accepted callback completes exact attempt after independent readback") {
        let f = try NSA(bytes: nsaBytes()); try f.started(); let reads = f.store.reads
        f.dispatcher.finish()
        try expect(!f.driver.physicalCheckInFlight && f.driver.acceptedCompletions == 1 && f.store.reads > reads &&
            !f.preferences.scheduleRuntimeSnapshot.checkInFlight, "Exact completion/readback missing")
        let completionReads = f.store.reads
        f.dispatcher.finish()
        try expect(f.driver.acceptedCompletions == 1 && f.store.reads == completionReads,
            "Duplicate callback reused completed capability or reread storage")
        f.driver.stop()
    }
    check("PAT2668 app: many fake ticks cannot overlap a physically pending check even after a day") {
        let f = try NSA(bytes: nsaBytes()); try f.started()
        f.clock.second += 86400
        for _ in 0..<8 { f.hooks.send(.tick) }
        try expect(f.dispatcher.requests.count == 1 && f.driver.physicalCheckInFlight, "Ticks overlapped actual pending dispatcher")
        f.dispatcher.finish(); f.hooks.send(.tick)
        try expect(f.dispatcher.requests.count == 2, "Actually terminated physical check never released eligible next dispatch")
        f.driver.stop(); f.dispatcher.finish(1)
    }
    check("PAT2668 app: failure consumes cadence, no catchup before exact day, one start at day boundary") {
        let f = try NSA(bytes: nsaBytes()); try f.started(); f.dispatcher.finish(success: false)
        f.clock.second += 86399; f.hooks.send(.tick)
        try expect(f.dispatcher.requests.count == 1 && f.driver.acceptedCompletions == 0, "Fault retried early or claimed success")
        f.clock.second += 1; f.hooks.send(.tick)
        try expect(f.dispatcher.requests.count == 2, "Exact daily boundary did not dispatch")
        f.driver.stop(); f.dispatcher.finish(1)
    }
    for event in [NativeScheduleFixtureEvent.sleep, .clockInvalidated] {
        check("PAT2668 app: invalidation cancels once, fences late success and prevents overlap: \(event)") {
            let f = try NSA(bytes: nsaBytes()); try f.started(); f.hooks.send(event)
            try expect(f.dispatcher.requests[0].cancellations == 1 && f.driver.physicalCheckInFlight &&
                !f.preferences.scheduleRuntimeSnapshot.checkInFlight, "Cancellation incorrectly proved physical termination")
            f.clock.second += 86400; f.hooks.send(.wake); f.hooks.send(.tick)
            try expect(f.dispatcher.requests.count == 1, "Cancelled child overlapped another check")
            f.dispatcher.finish()
            try expect(f.driver.acceptedCompletions == 0 && !f.driver.physicalCheckInFlight, "Late invalidated completion accepted")
            f.driver.stop()
        }
    }
    check("PAT2668 app: consent revocation through same preference owner cancels pending callback and fences result") {
        let f = try NSA(bytes: nsaBytes()); try f.started()
        f.settings.choose(.dailyChecks(false)); try expect(nsaAccepted(f.settings.save()), "Cannot revoke accepted consent")
        f.hooks.send(.tick)
        try expect(f.dispatcher.requests[0].cancellations == 1 && f.driver.physicalCheckInFlight, "Consent edit failed physical cancellation fence")
        f.dispatcher.finish(); f.clock.second += 86400; f.hooks.send(.tick)
        try expect(f.driver.acceptedCompletions == 0 && f.dispatcher.requests.count == 1, "Revoked result/start accepted")
        f.driver.stop()
    }
    check("PAT2668 app: setup owner revision mutation fences dispatch even when daily consent remains true") {
        let f = try NSA(bytes: nsaBytes()); try f.started()
        f.firstRun.edit(dailyChecks: true, notifications: false, failureReports: false)
        try expect(nsaAccepted(f.firstRun.saveChoices(complete: true)), "Same setup owner save failed")
        f.hooks.send(.tick); let reads = f.store.reads; f.dispatcher.finish()
        try expect(f.driver.acceptedCompletions == 0 && f.store.reads == reads && f.dispatcher.requests[0].cancellations == 1,
            "Stale revision callback performed readback or claimed acceptance")
        f.driver.stop()
    }
    check("PAT2668 app: external bytes mutation during pending callback refuses accepted completion") {
        let f = try NSA(bytes: nsaBytes()); try f.started(); f.store.bytes = try nsaBytes(revision: 9)
        f.dispatcher.finish()
        try expect(f.driver.acceptedCompletions == 0 && f.preferences.blockedReason != nil && !f.driver.physicalCheckInFlight,
            "Changed accepted bytes were not independently refused")
        f.driver.stop()
    }
    check("PAT2668 app: raw clock invalidity latches until explicit reanchor with full-day deferral") {
        let f = try NSA(bytes: nsaBytes()); try f.started(); f.dispatcher.finish()
        f.clock.invalid = true; f.hooks.send(.tick)
        try expect(f.preferences.scheduleRuntimeSnapshot.clockState == .invalid, "Raw invalid clock not latched")
        f.clock.invalid = false; f.clock.second += 86400; f.hooks.send(.tick)
        try expect(f.dispatcher.requests.count == 1, "Tick silently recovered invalid clock")
        try expect(f.driver.reanchor(), "Explicit reanchor failed")
        f.hooks.send(.tick); f.clock.second += 86399; f.hooks.send(.tick)
        try expect(f.dispatcher.requests.count == 1, "Reanchor consumed less than full-day deferral")
        f.clock.second += 1; f.hooks.send(.tick)
        try expect(f.dispatcher.requests.count == 2, "Full consistent day after reanchor did not dispatch")
        f.driver.stop(); f.dispatcher.finish(1)
    }
    check("PAT2668 app: stop is terminal, unsubscribes once, fences retained fake hooks and late completion") {
        let f = try NSA(bytes: nsaBytes()); try f.started(); f.driver.stop(); f.driver.stop()
        try expect(f.driver.phase == .stopped && f.hooks.token.cancellations == 1 && f.dispatcher.requests[0].cancellations == 1 &&
            f.driver.physicalCheckInFlight && f.preferences.scheduleRuntimeSnapshot.clockState == .stopped, "Stop lost terminal/physical fence")
        let reads = f.clock.reads
        f.clock.second += 86400; f.hooks.send(.tick); f.hooks.send(.wake)
        try expect(!f.driver.start() && !f.driver.reanchor() && f.clock.reads == reads && f.dispatcher.requests.count == 1,
            "Stopped lifetime restarted or consumed observations")
        f.dispatcher.finish()
        try expect(f.driver.acceptedCompletions == 0 && !f.driver.physicalCheckInFlight, "Stopped completion accepted")
    }
    check("PAT2668 app: offscreen press harness activates one harmless real SwiftUI reload control exactly once") {
        var presses = 0
        _ = try nsaPaint(Button(action: { presses += 1 }) { Text(verbatim: "Reload saved schedule settings") }, activateReload: true)
        try expect(presses == 1, "Actual hidden control positive failed")
        var nativePresses = 0
        _ = try nsaPaint(NSAHarmlessNativeButton(enabled: true, action: { nativePresses += 1 }), activateReload: true)
        try expect(nativePresses == 1, "Actual hidden native control did not activate exactly once")

        var disabledPresses = 0
        var disabledRefused = false
        do {
            _ = try nsaPaint(NSAHarmlessNativeButton(enabled: false, action: { disabledPresses += 1 }), activateReload: true)
        } catch let failure as CheckFailure {
            try expect(failure.description == "Matched actual NSButton is disabled", "Disabled native control failed for an unrelated reason: " + failure.description)
            disabledRefused = true
        }
        try expect(disabledRefused && disabledPresses == 0, "Disabled native control was not refused without activation")

        var duplicatePresses = 0
        var duplicatesRefused = false
        do {
            _ = try nsaPaint(NSAHarmlessNativeButton(enabled: true, count: 2, action: { duplicatePresses += 1 }), activateReload: true)
        } catch let failure as CheckFailure {
            try expect(failure.description.hasPrefix("Expected exactly one actual Reload saved schedule settings AX button or sole hidden NSButton: "),
                "Duplicate native controls failed for an unrelated reason: " + failure.description)
            duplicatesRefused = true
        }
        try expect(duplicatesRefused && duplicatePresses == 0, "Duplicate native controls were not refused without activation")
    }
    check("PAT2668 app: actual settings view reload control acquires same owner and does not save") {
        let f = try NSA(bytes: nsaBytes()); f.firstRun.openPreferences(); let reads = f.store.reads
        _ = try nsaPaint(NativeScheduleSettingsView(controller: f.settings), activateReload: true)
        try expect(f.settings.testPreferenceOwner === f.preferences && f.settings.acceptedRevision == 0 && f.store.reads > reads &&
            f.store.writes == 0 && f.settings.settings == f.preferences.scheduleSettings, "Real settings Reload not bound to exact owner")
        try f.idle()
    }
    check("PAT2668 app: actual root settings control uses retained owner and keeps network draft") {
        let f = try NSA(bytes: nsaBytes()); f.firstRun.openPreferences(); f.session.navigation.select(.settings); f.session.navigation.selectSettings(.updates)
        _ = try nsaPaint(NativeClientRootView(session: f.session), activateReload: true)
        try expect(f.session.navigation.destination == .settings && f.session.navigation.settingsSection == .updates,
            "Schedule Reload left the current Settings route")
        try expect(f.settings.acceptedRevision == 0 && f.settings.testPreferenceOwner === f.preferences &&
            f.session.navigation.drafts.values[.network] == "Keep network draft" && f.store.writes == 0,
            "Root failed real retained settings control")
        try f.idle()
    }
    check("PAT2668 app: actual settings Save control durably applies exact selected choice") {
        let f = try NSA(bytes: nsaBytes()); f.open(); f.settings.choose(.dailyChecks(false))
        _ = try nsaPaint(NativeScheduleSettingsView(controller: f.settings), activateReload: true, target: "Save schedule choices")
        try expect(f.preferences.scheduleSettings?.dailyChecks == false && f.settings.acceptedRevision == 1 && f.store.writes == 1 &&
            f.settings.draft == nil, "Actual Save control did not save selected choice through exact owner")
        try f.idle()
    }
    check("PAT2668 app: blocked owner later reloads exact durable state while preserving unsaved choice") {
        let f = try NSA(bytes: nsaBytes()); f.open(); f.settings.choose(.dailyChecks(false)); f.store.fault = .unavailable
        f.settings.reload()
        try expect(f.settings.settings == nil && f.settings.draft == .dailyChecks(false), "Blocked reload lost dirty choice or showed accepted mirror")
        f.store.fault = .none; f.settings.reload()
        try expect(f.settings.acceptedRevision == 0 && f.settings.settings == f.preferences.scheduleSettings &&
            f.settings.draft == .dailyChecks(false) && f.store.writes == 0, "Explicit reload failed recovery/preserved draft")
    }
    check("PAT2668 app: accepted mutation limit refuses 129th settings request without write") {
        let f = try NSA(bytes: nsaBytes()); f.open()
        for index in 0..<128 {
            f.settings.choose(.notifications(index % 2 == 0))
            try expect(nsaAccepted(f.settings.save()), "Could not establish accepted mutation-boundary positive")
        }
        let bytes = f.store.bytes, writes = f.store.writes
        f.settings.choose(.dailyChecks(false))
        try expect(!nsaAccepted(f.settings.save()) && f.store.bytes == bytes && f.store.writes == writes && writes == 128,
            "Combined mutation limit not preserved")
    }
    check("PAT2668 app: synchronous dispatcher completion does not retain phantom physical check") {
        let f = try NSA(bytes: nsaBytes()); f.open(); f.dispatcher.synchronous = true
        try expect(f.driver.start() && f.dispatcher.requests.count == 1 && !f.driver.physicalCheckInFlight &&
            f.driver.acceptedCompletions == 1 && !f.preferences.scheduleRuntimeSnapshot.checkInFlight,
            "Synchronous callback was lost or returned request re-created a completed physical lifetime")
        f.clock.second += 86400; f.hooks.send(.tick)
        try expect(f.dispatcher.requests.count == 2 && f.driver.acceptedCompletions == 2 && !f.driver.physicalCheckInFlight,
            "Synchronous completion blocked next full-day check")
        f.driver.stop()
    }
    check("PAT2668 app: sleep survives a full-day tick until explicit wake after completed initial request") {
        let f = try NSA(bytes: nsaBytes()); try f.started(); f.dispatcher.finish()
        try expect(f.driver.acceptedCompletions == 1 && !f.driver.physicalCheckInFlight &&
            !f.preferences.scheduleRuntimeSnapshot.checkInFlight, "Initial request did not physically and logically complete")
        f.hooks.send(.sleep); f.clock.second += 86400; f.hooks.send(.tick)
        try expect(f.dispatcher.requests.count == 1 && !f.driver.physicalCheckInFlight &&
            !f.preferences.scheduleRuntimeSnapshot.checkInFlight && f.driver.acceptedCompletions == 1,
            "Sleeping full-day tick dispatched or reserved an extra check without wake")
        f.dispatcher.finish()
        try expect(f.driver.acceptedCompletions == 1, "Sleeping tick accepted a duplicate old completion")
        f.hooks.send(.wake)
        try expect(f.dispatcher.requests.count == 2 && f.driver.physicalCheckInFlight &&
            f.preferences.scheduleRuntimeSnapshot.checkInFlight, "Explicit wake did not release exactly the eligible next opportunity")
        for _ in 0..<8 { f.hooks.send(.tick) }
        try expect(f.dispatcher.requests.count == 2, "Post-wake ticks overlapped the pending physical check")
        f.dispatcher.finish(1)
        try expect(f.driver.acceptedCompletions == 2 && !f.driver.physicalCheckInFlight &&
            !f.preferences.scheduleRuntimeSnapshot.checkInFlight, "Awakened opportunity did not complete exactly once")
        f.driver.stop()
    }
    check("PAT2668 app: synchronous subscription sleep blocks initial observation and ticks until explicit wake") {
        let f = try NSA(bytes: nsaBytes()); f.open(); f.hooks.synchronousEvent = .sleep
        try expect(f.driver.start() && f.driver.phase == .running, "Synchronous subscription sleep incorrectly stopped lifecycle")
        try expect(f.dispatcher.requests.isEmpty && !f.driver.physicalCheckInFlight &&
            !f.preferences.scheduleRuntimeSnapshot.checkInFlight && f.driver.acceptedCompletions == 0,
            "Synchronous subscription sleep was overwritten by initial post-subscription observation")
        f.clock.second += 1
        for _ in 0..<8 { f.hooks.send(.tick) }
        try expect(f.dispatcher.requests.isEmpty && !f.driver.physicalCheckInFlight &&
            !f.preferences.scheduleRuntimeSnapshot.checkInFlight && f.driver.acceptedCompletions == 0,
            "Tick dispatched or consumed an attempt while synchronously subscribed asleep")
        f.hooks.send(.wake)
        try expect(f.dispatcher.requests.count == 1 && f.driver.physicalCheckInFlight &&
            f.preferences.scheduleRuntimeSnapshot.checkInFlight && f.hooks.subscriptions == 1 &&
            f.driver.testPreferenceOwner === f.preferences && f.settings.testPreferenceOwner === f.preferences,
            "Wake lost first opportunity, exact owner or single subscription after synchronous sleep")
        for _ in 0..<8 { f.hooks.send(.tick) }
        try expect(f.dispatcher.requests.count == 1, "Ticks overlapped first request after synchronous sleep")
        f.driver.stop(); f.driver.stop()
        try expect(f.hooks.token.cancellations == 1 && f.dispatcher.requests[0].cancellations == 1 &&
            f.driver.physicalCheckInFlight && !f.preferences.scheduleRuntimeSnapshot.checkInFlight,
            "Synchronous-sleep lifecycle cleanup lost cancellation versus physical termination boundary")
        f.dispatcher.finish(); f.clock.second += 86400; f.hooks.send(.wake); f.hooks.send(.tick)
        try expect(f.driver.phase == .stopped && !f.driver.physicalCheckInFlight && !f.driver.start() &&
            f.driver.acceptedCompletions == 0 && f.dispatcher.requests.count == 1 && f.hooks.token.cancellations == 1,
            "Terminal synchronous-sleep lifecycle accepted late result or restarted")
    }
    check("PAT2668 app: synchronous physical-reservation observer stop prevents dispatcher begin and clears only undispatched flight") {
        let f = try NSA(bytes: nsaBytes()); f.open()
        var stoppedOnReservation = false
        let observer = f.driver.objectWillChange.sink { _ in
            guard !stoppedOnReservation, f.driver.physicalCheckInFlight else { return }
            // Set before stop publishes again so this synchronous observer is one-shot.
            stoppedOnReservation = true
            f.driver.stop()
        }
        defer { observer.cancel() }
        let started = f.driver.start()
        try expect(stoppedOnReservation && !started && f.driver.phase == .stopped && f.dispatcher.requests.isEmpty,
            "Synchronous observer stop still allowed dispatcher begin after terminal stop")
        try expect(!f.driver.physicalCheckInFlight && !f.preferences.scheduleRuntimeSnapshot.checkInFlight &&
            f.driver.acceptedCompletions == 0 && f.preferences.scheduleRuntimeSnapshot.clockState == .stopped &&
            f.hooks.subscriptions == 1 && f.hooks.token.cancellations == 1,
            "Undispatched reservation survived stop as a phantom physical or logical attempt")
        let reads = f.clock.reads
        f.clock.second += 86400; f.hooks.send(.tick); f.hooks.send(.wake); f.driver.stop()
        try expect(!f.driver.start() && !f.driver.reanchor() && f.clock.reads == reads &&
            f.dispatcher.requests.isEmpty && !f.driver.physicalCheckInFlight &&
            !f.preferences.scheduleRuntimeSnapshot.checkInFlight && f.hooks.token.cancellations == 1,
            "Retained hooks or repeated stop restarted the undispatched terminal lifetime")
    }
    check("PAT2668 app: reentrant tick after invalidated physical completion preserves the replacement logical attempt") {
        let f = try NSA(bytes: nsaBytes()); try f.started(); f.hooks.send(.sleep)
        try expect(f.driver.physicalCheckInFlight && !f.preferences.scheduleRuntimeSnapshot.checkInFlight &&
            f.dispatcher.requests[0].cancellations == 1, "Sleep did not retain cancelled physical request without logical attempt")
        f.clock.second += 86400; f.hooks.send(.wake)
        try expect(f.dispatcher.requests.count == 1 && f.driver.physicalCheckInFlight &&
            !f.preferences.scheduleRuntimeSnapshot.checkInFlight && f.preferences.scheduleRuntimeSnapshot.checkDue,
            "Wake failed to leave due owner blocked only by old physical request")
        var tickedOnPhysicalRelease = false
        let observer = f.driver.objectWillChange.sink { _ in
            guard !tickedOnPhysicalRelease, !f.driver.physicalCheckInFlight else { return }
            tickedOnPhysicalRelease = true
            f.hooks.send(.tick)
        }
        defer { observer.cancel() }
        f.dispatcher.finish()
        try expect(tickedOnPhysicalRelease && f.dispatcher.requests.count == 2 && f.driver.physicalCheckInFlight &&
            f.preferences.scheduleRuntimeSnapshot.checkInFlight && f.driver.acceptedCompletions == 0,
            "Old invalidated completion cancelled the reentrant replacement logical attempt")
        f.dispatcher.finish()
        try expect(f.dispatcher.requests.count == 2 && f.driver.physicalCheckInFlight &&
            f.preferences.scheduleRuntimeSnapshot.checkInFlight && f.dispatcher.requests[1].cancellations == 0,
            "Stale old completion cancelled or displaced the replacement request")
        f.dispatcher.finish(1)
        try expect(f.driver.acceptedCompletions == 1 && !f.driver.physicalCheckInFlight &&
            !f.preferences.scheduleRuntimeSnapshot.checkInFlight, "Valid replacement completion was not accepted exactly once")
        f.dispatcher.finish(1); f.dispatcher.finish()
        try expect(f.driver.acceptedCompletions == 1 && f.dispatcher.requests.count == 2 &&
            !f.driver.physicalCheckInFlight && !f.preferences.scheduleRuntimeSnapshot.checkInFlight,
            "Duplicate completions changed the accepted replacement result")
        f.driver.stop()
    }
    check("PAT2668 app: synchronous running-phase will-set observer stop remains terminal before subscription and observation") {
        let f = try NSA(bytes: nsaBytes()); f.open()
        var stoppedOnRunningPublication = false
        let observer = f.driver.objectWillChange.sink { _ in
            guard !stoppedOnRunningPublication else { return }
            // The first driver publication is phase's running will-set, before its value changes.
            // Mark first so stop's own phase publication cannot recurse.
            stoppedOnRunningPublication = true
            f.driver.stop()
        }
        defer { observer.cancel() }
        let started = f.driver.start()
        try expect(stoppedOnRunningPublication && !started && f.driver.phase == .stopped &&
            f.hooks.subscriptions == 0 && f.clock.reads == 0 && f.dispatcher.requests.isEmpty,
            "Running-phase will-set publication resurrected stopped driver and subscribed or sampled")
        try expect(!f.driver.physicalCheckInFlight && !f.preferences.scheduleRuntimeSnapshot.checkInFlight &&
            f.driver.acceptedCompletions == 0 && f.hooks.token.cancellations == 0,
            "Stop before subscription retained phantom work or cancelled a nonexistent subscription")
        f.clock.second += 86400; f.hooks.send(.tick); f.hooks.send(.wake)
        try expect(!f.driver.start() && !f.driver.reanchor() && f.driver.phase == .stopped &&
            f.hooks.subscriptions == 0 && f.clock.reads == 0 && f.dispatcher.requests.isEmpty &&
            !f.driver.physicalCheckInFlight && !f.preferences.scheduleRuntimeSnapshot.checkInFlight,
            "Stopped running-publication lifetime restarted through later start, reanchor or hooks")
    }
}
