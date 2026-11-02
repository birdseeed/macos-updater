import Foundation
import SwiftUI
import AppKit
import PatchedShell
@_spi(Testing) import PatchedClient

// Independent acceptance preparation. Inventory values come only from the existing
// physical scanner in exclusive .build fixture roots. No constructed observations.
private final class MenuReads: @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0, holds = 0, armed = false, expired = false
    private let release = DispatchSemaphore(value: 0)
    var count: Int { lock.lock(); defer { lock.unlock() }; return reads }
    var blocked: Int { lock.lock(); defer { lock.unlock() }; return holds }
    var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return expired }
    func arm() { lock.lock(); armed = true; lock.unlock() }
    func open() { release.signal() }
    func read() {
        lock.lock(); reads += 1; let hold = armed; armed = false
        if hold { holds += 1 }; lock.unlock()
        if hold && release.wait(timeout: .now() + 8) == .timedOut {
            lock.lock(); expired = true; lock.unlock()
        }
    }
}

private struct MenuFixture {
    let base: URL
    let root: URL
    let reads = MenuReads()
    init() throws {
        base = try newDirectory("pat2670-native-menu")
        root = base.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    func clean() { try? FileManager.default.removeItem(at: base) }
    func add(_ name: String, version: String = "4.2") throws {
        let contents = root.appendingPathComponent(name + ".app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let claims = ["CFBundleDisplayName": name, "CFBundleIdentifier": "example." + name,
                      "CFBundleShortVersionString": version, "CFBundleVersion": "81"]
        try PropertyListSerialization.data(fromPropertyList: claims, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
    }
    @MainActor func controller(roots: [String]? = nil) -> LocalApplicationsController {
        let probe = reads
        return LocalApplicationsController(inventory: LocalApplicationInventory(
            fixtureRoots: roots ?? [root.path], observer: { _ in probe.read() }))
    }
}

@MainActor private func menuSession(_ applications: LocalApplicationsController,
                                   recorder: Recorder = Recorder()) -> NativeClientSession {
    let navigation = ShellNavigation(destination: .support, settingsSection: .network,
        drafts: ShellDrafts(values: [.network: "Retained <literal> proxy draft", .updates: "Retained update draft"]))
    return NativeClientSession(navigation: navigation, applications: applications,
        inspection: ready(scripted(recorder), version: "157.0.1"))
}

@MainActor private func menuHonesty(_ session: NativeClientSession) throws {
    let text = session.menuText
    try expect(text.summary.title == "Update status unavailable" && text.summary.details.isEmpty,
               "Unverified inventory became current/cached update counts or checking-for-updates authority")
    try expect(text.summary.accessibilitySummary == "Update status unavailable", "Accessibility overstates update availability")
    try expect(text.backgroundStatus.lowercased().contains("unavailable"), "Unavailable background checks/notifications not explained")
    try expect(!session.applications.allVerifiedUpToDate && session.applications.readyForUpdateCount == 0,
               "Menu action invented verified update authority")
}

@MainActor private func menuSharesInventory(_ session: NativeClientSession) throws {
    let a = session.applications.text, m = session.menuText
    try expect(m.inventoryStatus == a.status, "Menu hides or replaces the actual scanner status")
    try expect(m.observedAt == a.observedAt && m.provenance == a.provenance,
               "Menu invents observation freshness/origin or loses fixture provenance")
    try expect(m.scanTitle == a.scanTitle && m.scanEnabled == a.scanEnabled,
               "Menu Scan does not match the existing owner's singleflight state")
    try menuHonesty(session)
}

// Never shown or activated. Painting does not establish menu-bar, keyboard,
// VoiceOver, close/reopen or native lifecycle acceptance.
@MainActor private func menuPaint(_ session: NativeClientSession, openWindow: @escaping () -> Void,
    afterFirstPaint: (@MainActor () async throws -> Void)? = nil) async throws -> [Data] {
    let app = NSApplication.shared
    if app.activationPolicy() != .prohibited { _ = app.setActivationPolicy(.prohibited) }
    try expect(app.activationPolicy() == .prohibited && !app.isActive, "Menu capture must remain prohibited/inactive")
    let host = NSHostingView(rootView: NativeClientMenuView(session: session, openWindow: openWindow)
        .frame(width: 380, height: 440).environment(\.colorScheme, .light))
    host.frame = NSRect(x: 0, y: 0, width: 380, height: 440)
    host.appearance = NSAppearance(named: .aqua)
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.close() }
    func capture() throws -> Data {
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        let deadline = Date().addingTimeInterval(0.20)
        while Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.01)))
        }
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw CheckFailure(description: "Menu bitmap unavailable")
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try expect(!window.isVisible && !app.isActive && app.activationPolicy() == .prohibited,
                   "Menu capture became visible/active")
        guard let bytes = bitmap.representation(using: .png, properties: [:]) else {
            throw CheckFailure(description: "Menu pixels unavailable")
        }
        return bytes
    }
    let first = try capture()
    if let afterFirstPaint {
        try await afterFirstPaint()
        return [first, try capture()]
    }
    return [first]
}

@MainActor func registerNativeMenuIntegrationChecks() {
    check("PAT2670: ordinary idle menu permits only explicit Scan and claims no update/background readiness") {
        let session = NativeClientSession()
        try expect(session.applications.phase == .idle && session.applications.observation == nil,
                   "Default menu construction scanned")
        try menuSharesInventory(session)
        try expect(session.menuText.scanEnabled, "Idle explicit Scan is unavailable")
    }
    check("PAT2670: all menu route actions retain the exact injected owners, settings drafts and inspector selection") {
        let f = try MenuFixture(); defer { f.clean() }; let recorder = Recorder()
        let applications = f.controller(), session = menuSession(applications, recorder: recorder)
        let navigation = session.navigation, drafts = navigation.drafts, inspection = session.inspection
        let routes: [(NativeClientMenuAction, ShellDestination)] = [(.updates, .updates), (.applications, .applications),
            (.activity, .activity), (.settings, .settings)]
        for (action, destination) in routes {
            navigation.select(.support)
            try expect(session.performMenuAction(action), "Route did not request main-window reopening")
            try expect(navigation.destination == destination, "Menu selected the wrong destination")
            try expect(session.navigation === navigation && session.applications === applications && session.inspection === inspection,
                       "Menu route replaced a shared owner")
            try expect(navigation.drafts === drafts && drafts.values[.network] == "Retained <literal> proxy draft"
                && drafts.values[.updates] == "Retained update draft" && navigation.settingsSection == .network,
                "Menu route discarded settings section/drafts")
            try expect(inspection.phase == .ready && inspection.text.fileLine.contains("Firefox 157.0.dmg")
                && inspection.text.versionLine.contains("157.0.1"), "Menu route discarded inspector selection")
        }
        try expect(f.reads.count == 0 && applications.observation == nil && applications.phase == .idle,
                   "Menu route scanned without explicit Scan")
        try expect(await recorder.count == 0, "Menu route checked a disk image")
    }
    check("PAT2670: repeated selected menu routes still request stable-window reopening without selection callbacks or IO") {
        let f = try MenuFixture(); defer { f.clean() }; var selections = 0
        let navigation = ShellNavigation(destination: .updates, settingsSection: .diagnostics,
            drafts: ShellDrafts(values: [:]), onSelection: { _ in selections += 1 })
        let session = NativeClientSession(navigation: navigation, applications: f.controller(), inspection: ClientController())
        for _ in 0..<4 { try expect(session.performMenuAction(.updates), "Already-selected Updates cannot reopen the window") }
        try expect(selections == 0 && f.reads.count == 0, "Reopening retriggered selection side effects or scanning")
    }
    check("PAT2670: reading and painting every menu route is inert and never reopens a window") {
        let f = try MenuFixture(); defer { f.clean() }; try f.add("Unopened")
        let recorder = Recorder(), session = menuSession(f.controller(), recorder: recorder)
        let applications = session.applications; var reopenings = 0
        for destination in ShellDestination.allCases {
            session.navigation.select(destination)
            for _ in 0..<5 { _ = session.menuText }
            _ = try await menuPaint(session, openWindow: { reopenings += 1 })
        }
        try expect(reopenings == 0 && f.reads.count == 0 && applications.observation == nil && applications.phase == .idle,
                   "Presentation performed Scan or reopened a window")
        try expect(await recorder.count == 0, "Presentation invoked inspection")
    }
    check("PAT2670: menu Scan uses the exact physical inventory owner and never the inspector") {
        let f = try MenuFixture(); defer { f.clean() }; try f.add("Before")
        let recorder = Recorder(), applications = f.controller(), session = menuSession(applications, recorder: recorder)
        try expect(session.applications === applications, "Refusing scan on a replaced owner")
        try expect(!session.performMenuAction(.scan), "Scan unexpectedly requested a route/window change")
        await applications.waitUntilIdle()
        guard let observed = applications.observation else { throw CheckFailure(description: "Menu Scan did not reach shared owner") }
        try expect(observed.provenance == .fixture && observed.generation == 1 && observed.applications.count == 1
            && observed.applications[0].claimedShortVersion == "4.2" && f.reads.count == 1,
            "Menu Scan did not perform one actual fixture read")
        try expect(session.navigation.destination == .support, "Menu Scan changed route")
        try expect(await recorder.count == 0, "Menu Scan checked a disk image")
        try menuSharesInventory(session)
    }
    check("PAT2670: menu and main-window Scan share existing singleflight and expose in-flight status") {
        let f = try MenuFixture(); defer { f.clean() }; try f.add("Held")
        let applications = f.controller(), session = menuSession(applications)
        try expect(session.applications === applications, "Refusing held scan on a replaced owner")
        f.reads.arm(); session.performMenuAction(.scan)
        do {
            try await until("menu physical scanner hold") { f.reads.blocked == 1 }
            session.performMenuAction(.scan); applications.scan(); session.performMenuAction(.scan)
            try expect(applications.phase == .scanning && !session.menuText.scanEnabled
                && session.menuText.scanTitle == "Scanning…", "Menu does not expose shared in-flight Scan")
            try menuSharesInventory(session)
        } catch { f.reads.open(); await applications.waitUntilIdle(); throw error }
        f.reads.open(); await applications.waitUntilIdle()
        try expect(applications.observation?.generation == 1 && f.reads.count == 1 && !f.reads.timedOut,
                   "Menu/window actions duplicated the scanner or exhausted the fixture hold")
    }
    check("PAT2670: main-window refresh updates menu and explicit menu refresh updates both retained screens") {
        let f = try MenuFixture(); defer { f.clean() }; try f.add("First")
        let applications = f.controller(), session = menuSession(applications)
        applications.scan(); await applications.waitUntilIdle()
        guard let old = applications.observation else { throw CheckFailure(description: "Fixture setup did not scan") }
        try menuSharesInventory(session)
        try f.add("Second", version: "9.9")
        session.performMenuAction(.scan); await applications.waitUntilIdle()
        guard let fresh = applications.observation else { throw CheckFailure(description: "Menu refresh lost observation") }
        try expect(fresh.sessionID == old.sessionID && fresh.generation == 2 && fresh.applications.count == 2 && f.reads.count == 3,
                   "Menu used another scanner or did not publish the new physical observation")
        try expect(applications.text.rows == applications.updatesText.rows && applications.text.rows.count == 2,
                   "Menu refresh did not reach both retained screens")
        try expect(old.generation == 1 && old.applications.count == 1, "Prior immutable observation changed")
        try menuSharesInventory(session)
    }
    check("PAT2670: cached inventory remains labelled during refresh and cannot become cached update readiness") {
        let f = try MenuFixture(); defer { f.clean() }; try f.add("Before")
        let applications = f.controller(), session = menuSession(applications)
        applications.scan(); await applications.waitUntilIdle()
        let old = applications.observation, text = session.menuText
        f.reads.arm(); applications.scan()
        do {
            try await until("main-window refresh hold") { f.reads.blocked == 1 }
            try expect(applications.observation == old && session.menuText.observedAt == text.observedAt,
                       "Menu discarded cached inventory observation/time")
            try expect(session.menuText.inventoryStatus.contains("Previous observation"), "Menu hides cached inventory during refresh")
            try menuSharesInventory(session)
        } catch { f.reads.open(); await applications.waitUntilIdle(); throw error }
        f.reads.open(); await applications.waitUntilIdle()
        try expect(!f.reads.timedOut, "Fixture refresh hold expired")
    }
    check("PAT2670: a real empty scanned root never means no-ready-updates or verified-current") {
        let f = try MenuFixture(); defer { f.clean() }; let applications = f.controller(), session = menuSession(applications)
        applications.scan(); await applications.waitUntilIdle()
        try expect(applications.observation?.applications.isEmpty == true
            && applications.observation?.roots.first?.status == .scanned, "Empty setup did not scan a physical empty root")
        try expect(session.menuText.inventoryStatus == "No applications found in the scanned folders.", "Menu overstates an empty observation")
        try menuSharesInventory(session)
    }
    check("PAT2670: actual unavailable and incomplete root observations remain visible with no update readiness") {
        let f = try MenuFixture(); defer { f.clean() }; try f.add("Visible")
        for roots in [[""], [f.root.path, "", f.base.appendingPathComponent("Absent").path]] {
            let applications = f.controller(roots: roots), session = menuSession(applications)
            applications.scan(); await applications.waitUntilIdle()
            try expect(applications.observation?.issues.isEmpty == false && applications.observation?.completeness == .incomplete,
                       "Root-failure setup produced no actual failure observation")
            try expect(session.menuText.inventoryStatus.contains("incomplete"), "Menu conceals failed root coverage")
            try menuSharesInventory(session)
        }
    }
    check("PAT2670: rendering menu after shared inventory changes paints the new observation without another read") {
        let f = try MenuFixture(); defer { f.clean() }; try f.add("Painted")
        let applications = f.controller(), session = menuSession(applications); var reopenings = 0
        let pixels = try await menuPaint(session, openWindow: { reopenings += 1 }, afterFirstPaint: {
            try expect(f.reads.count == 0, "Initial menu painting performed a scan")
            applications.scan(); await applications.waitUntilIdle()
            try expect(f.reads.count == 1, "Explicit scan did not read the physical fixture once")
        })
        try expect(pixels.count == 2 && pixels[0] != pixels[1],
                   "Same mounted menu view did not observe its retained applications owner")
        try expect(f.reads.count == 1 && reopenings == 0, "Menu paint scanned or reopened a window")
    }
    check("PAT2670: app composes actual MenuBarExtra and shared view over its sole stable session/window") {
        let app = code(try source("Sources/PatchedApp/PatchedApp.swift"))
        for binding in ["MenuBarExtra(", "NativeClientMenuView(session: session", "NativeClientRootView(session: session)",
                        "id: NativeClientMenuWindow.id", "openWindow(id: NativeClientMenuWindow.id)"] {
            try expect(app.contains(binding), "App lacks the real native scene binding: \(binding)")
        }
        try expect(app.components(separatedBy: "NativeClientSession()").count == 2,
                   "App must construct exactly one session for both scenes")
        try expect(!app.contains("@_spi"), "App imports fixture injection")
    }
    check("PAT2670: shared menu view exposes only the five explicit shared-owner actions") {
        let menu = code(try source("Sources/PatchedClient/NativeClientMenu.swift"))
        try expect(menu.contains("Button(") && menu.contains("session.performMenuAction("), "Menu has no real explicit action wiring")
        for action in [".scan", ".updates", ".applications", ".activity", ".settings"] {
            try expect(menu.contains(action), "Menu lacks explicit action \(action)")
        }
        try expect(menu.contains("openWindow()"), "Route buttons cannot reopen the stable window")
    }
    check("PAT2670: user-session close-window policy is explicit and adopted by the native app delegate") {
        try expect(NativeClientLifecyclePolicy.continuesSessionAfterLastWindowCloses,
                   "Closed-window menu session policy is not implemented")
        let app = try swiftSources("Sources/PatchedApp").map { code($0.1) }.joined(separator: "\n")
        for binding in ["@NSApplicationDelegateAdaptor", "applicationShouldTerminateAfterLastWindowClosed",
                        "NativeClientLifecyclePolicy.continuesSessionAfterLastWindowCloses"] {
            try expect(app.contains(binding), "Native app does not adopt lifecycle policy: \(binding)")
        }
    }
    check("PAT2670: native menu composition adds no automatic work, notifications or productive update route") {
        let app = try swiftSources("Sources/PatchedApp").map { code($0.1) }.joined(separator: "\n")
        let menu = code(try source("Sources/PatchedClient/NativeClientMenu.swift"))
        for forbidden in [".task", ".onAppear", "Timer", "URLSession", "UNUserNotificationCenter", "requestAuthorization",
                          "SMAppService", "LaunchAgent", "Process(", "ArtifactInspector", "installationAuthorized: true",
                          "LocalApplicationInventory(", "LocalApplicationsController(", "ClientController("] {
            try expect(!(app + menu).contains(forbidden), "Menu/app adds forbidden operation or competing owner: \(forbidden)")
        }
    }
}
