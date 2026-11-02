import Foundation
import SwiftUI
import AppKit
import PatchedShell
@_spi(Testing) import PatchedClient

// Independent Phase A checks. Real inventory reads occur only within a new
// .build fixture, never from a constructed observation or installed directory.
private final class CompositionReads: @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return reads }
    func read() { lock.lock(); reads += 1; lock.unlock() }
}
private struct CompositionFixture {
    let root: URL
    let reads = CompositionReads()
    init() throws {
        root = try newDirectory("pat2660-composition")
        try add("Before", version: "4.2")
    }
    func add(_ name: String, version: String) throws {
        let contents = root.appendingPathComponent(name + ".app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let claims = ["CFBundleDisplayName": name, "CFBundleIdentifier": "example." + name,
                      "CFBundleShortVersionString": version, "CFBundleVersion": "81"]
        try PropertyListSerialization.data(fromPropertyList: claims, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
    }
    @MainActor func controller() -> LocalApplicationsController {
        let probe = reads
        return LocalApplicationsController(inventory: LocalApplicationInventory(fixtureRoots: [root.path], observer: { _ in probe.read() }))
    }
}
@MainActor private func compositionNavigation() -> ShellNavigation {
    ShellNavigation(destination: .applications, settingsSection: .network,
                    drafts: ShellDrafts(values: [.network: "Retained literal draft"]))
}
// Never shown or activated; this exercises SwiftUI layout/appearance without
// granting a native application launch or accessibility acceptance claim.
@MainActor private func compositionPaint(_ session: NativeClientSession) throws -> Data {
    let app = NSApplication.shared
    if app.activationPolicy() != .prohibited { _ = app.setActivationPolicy(.prohibited) }
    try expect(app.activationPolicy() == .prohibited && !app.isActive, "Composition capture must remain prohibited/inactive")
    let host = NSHostingView(rootView: NativeClientRootView(session: session)
        .frame(width: 1000, height: 800).environment(\.colorScheme, .light))
    host.frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
    host.appearance = NSAppearance(named: .aqua)
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.close() }
    host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    let deadline = Date().addingTimeInterval(0.20)
    while Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.01)))
    }
    host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        throw CheckFailure(description: "Composition bitmap unavailable")
    }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try expect(!window.isVisible && !app.isActive && app.activationPolicy() == .prohibited, "Composition capture became visible/active")
    guard let bytes = bitmap.representation(using: .png, properties: [:]) else {
        throw CheckFailure(description: "Composition pixels unavailable")
    }
    return bytes
}

@MainActor func registerNativeShellCompositionChecks() {
    check("PAT2660: ordinary default session retains safe idle owners through every route") {
        let session = NativeClientSession()
        let navigation = session.navigation, applications = session.applications, inspection = session.inspection
        for destination in ShellDestination.allCases {
            navigation.select(destination)
            session.presentInspection(); session.dismissInspection()
            try expect(session.navigation === navigation && session.applications === applications && session.inspection === inspection,
                       "Default session replaced a retained owner")
            try expect(applications.observation == nil && applications.phase == .idle && inspection.phase == .needsSelection,
                       "Default session performed work without an explicit action")
        }
    }
    check("PAT2660: one injected owner survives every destination, settings and explicit inspection presentation") {
        let fixture = try CompositionFixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let navigation = compositionNavigation(), applications = fixture.controller(), inspection = ready(scripted(Recorder()))
        let session = NativeClientSession(navigation: navigation, applications: applications, inspection: inspection)
        for destination in ShellDestination.allCases {
            try expect(session.navigation === navigation && session.applications === applications && session.inspection === inspection,
                       "Session replaced an injected owner")
            session.navigation.select(destination)
            for section in ShellSettingsSection.allCases { session.navigation.selectSettings(section) }
            session.presentInspection()
            try expect(session.inspectionPresented, "Explicit presentation was refused")
            session.dismissInspection()
            try expect(!session.inspectionPresented, "Explicit dismissal was refused")
            try expect(navigation.drafts.values[.network] == "Retained literal draft", "Navigation discarded a display draft")
            try expect(inspection.phase == .ready && inspection.text.fileLine.contains("Firefox 157.0.dmg"), "Navigation discarded inspection selection")
        }
        try expect(session.navigation === navigation && session.applications === applications && session.inspection === inspection, "Final owners changed")
    }
    check("PAT2660: construction, navigation, presentation and offscreen root rendering never scan or check") {
        let fixture = try CompositionFixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let recorder = Recorder(), navigation = compositionNavigation(), applications = fixture.controller()
        let inspection = ready(scripted(recorder))
        let session = NativeClientSession(navigation: navigation, applications: applications, inspection: inspection)
        try expect(session.applications === applications && session.inspection === inspection && session.navigation === navigation, "Cannot safely observe replaced owners")
        for destination in ShellDestination.allCases {
            navigation.select(destination); _ = try compositionPaint(session)
        }
        for section in ShellSettingsSection.allCases { navigation.selectSettings(section); _ = try compositionPaint(session) }
        session.presentInspection(); _ = try compositionPaint(session); session.dismissInspection()
        try expect(fixture.reads.count == 0 && applications.observation == nil && applications.phase == .idle, "A lifecycle event scanned")
        try expect(await recorder.count == 0, "A lifecycle event checked")
        try expect(inspection.phase == .ready && inspection.text.checkEnabled, "A lifecycle event changed inspection state")
    }
    check("PAT2660: explicit fixture scan is singleflight and its immutable observation survives all routes and presentation") {
        let fixture = try CompositionFixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let navigation = compositionNavigation(), applications = fixture.controller(), inspection = ClientController()
        let session = NativeClientSession(navigation: navigation, applications: applications, inspection: inspection)
        // Refuse before invoking scan on any replaced/default owner.
        try expect(session.applications === applications, "Session lost fixture controller; refusing scan")
        session.applications.scan(); session.applications.scan()
        await applications.waitUntilIdle()
        guard let observed = applications.observation else { throw CheckFailure(description: "Explicit scan missing") }
        try expect(observed.provenance == .fixture && observed.generation == 1 && observed.applications.count == 1,
                   "Explicit scan was duplicated or not the real fixture observation")
        try expect(observed.applications[0].claimedShortVersion == "4.2", "Literal fixture claim missing")
        let reads = fixture.reads.count
        try expect(reads > 0, "Real fixture physical reads missing")
        try fixture.add("After", version: "9.9")
        for destination in ShellDestination.allCases {
            session.navigation.select(destination); session.presentInspection(); session.dismissInspection()
            try expect(session.applications === applications && session.applications.observation == observed, "Route replaced or changed retained observation")
        }
        try expect(fixture.reads.count == reads && observed.applications.count == 1, "Navigation rescanned or mutated prior observation")
        applications.scan(); await applications.waitUntilIdle()
        try expect(applications.observation?.generation == 2 && applications.observation?.applications.count == 2,
                   "Second explicit scan did not observe changed fixture")
        try expect(observed.generation == 1 && observed.applications.count == 1, "Prior immutable observation changed")
    }
    check("PAT2660: actual root uses shared shell/real children and renders retained application rows") {
        let root = code(try source("Sources/PatchedClient/NativeClientSession.swift"))
        for required in ["ShellView(", "LocalApplicationsView(", "ActivityView(", "LicenceView(", "ClientView(", "session.applications", "session.inspection", "session.navigation",
                         "case .applications", "case .updates", "case .activity", "case .licence",
                         "applicationsController: session.applications"] {
            try expect(root.contains(required), "Root lacks real composition binding: \(required)")
        }
        for forbidden in [".onAppear", ".task", "Timer", "URLSession", "ArtifactInspector", "UpdateView(", "onUpdate", "Fixture", "Task {"] {
            try expect(!root.contains(forbidden), "Root contains forbidden operation: \(forbidden)")
        }
        let fixture = try CompositionFixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let navigation = compositionNavigation(), applications = fixture.controller()
        let session = NativeClientSession(navigation: navigation, applications: applications, inspection: ClientController())
        try expect(session.applications === applications, "Refusing to scan replaced owner")
        let before = try compositionPaint(session)
        navigation.select(.updates)
        let updatesBefore = try compositionPaint(session)
        navigation.select(.applications)
        applications.scan(); await applications.waitUntilIdle()
        let after = try compositionPaint(session)
        try expect(before != after, "Applications root did not paint real scan result")
        navigation.select(.updates)
        let updates = try compositionPaint(session)
        try expect(updates != after, "Updates did not render its selected child")
        try expect(updates != updatesBefore, "Updates child did not render the same actual scan observation")
        navigation.select(.applications)
        try expect(try compositionPaint(session) == after, "Returning to Applications changed retained child rendering")
    }
}
