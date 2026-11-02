import Foundation
import SwiftUI
import AppKit
import PatchedActivity
import PatchedShell
@_spi(Testing) import PatchedClient

// Synthetic controller checks only. Never open NativeActivityContext, touch a home,
// or call an action on an ordinary controller. Fake identity gates precede actions.
@MainActor private final class NavigationHistory: NativeActivityReadSession {
    var snapshot = ActivitySnapshot(available: false)
    var next = ActivitySnapshot(available: true, revision: 7, events: [navigationEvent()])
    var failure: ActivityRefusal?
    var calls: [String] = []
    func reload() throws { try perform("reload") }
    func createFresh() throws { try perform("create") }
    func selectRetained() throws { try perform("retention") }
    private func perform(_ action: String) throws {
        calls.append(action)
        // An error intentionally leaves the lower cache available: the controller
        // must not republish it or keep using this failed owner.
        if let failure { throw failure }
        snapshot = next
    }
}
private func navigationEvent(id: String = "11111111-1111-4111-8111-111111111111",
                             name: String = "Literal **App** <tag> & café",
                             status: ActivityStatus = .failed, reason: ActivityReason = .verificationFailed) -> ActivityEvent {
    ActivityEvent(eventID: id, attemptID: "22222222-2222-4222-8222-222222222222",
        targetKey: "example.literal", appName: name, origin: .manualIndividual,
        status: status, reason: reason, sequence: 18, observedAt: 1234,
        beforeVersion: "1.0 <old>", afterVersion: "2.0 **new**", beforeBuild: "17", afterBuild: "18",
        runID: "33333333-3333-4333-8333-333333333333",
        transactionID: "44444444-4444-4444-8444-444444444444")
}
@MainActor private func navigationPair() throws -> (NativeActivityController, NavigationHistory) {
    let fake = NavigationHistory(), controller = NativeActivityController(session: NavigationHistory())
    // Use a separately constructed sentinel to catch constructors that disregard injection.
    try expect(controller.testSession != nil && controller.provenance == .testDouble, "SPI constructor lost its descriptive fake label")
    let selected = NativeActivityController(session: fake)
    try navigationIdentity(selected, fake)
    return (selected, fake)
}
@MainActor private func navigationIdentity(_ controller: NativeActivityController, _ fake: NavigationHistory) throws {
    try expect(controller.testSession === fake && controller.provenance == .testDouble,
               "Refusing action: injected history identity or test-double provenance lost")
}
@MainActor private func navigationLoad(_ controller: NativeActivityController, _ fake: NavigationHistory) throws {
    try navigationIdentity(controller, fake); controller.load()
}
@MainActor private func navigationSession(_ activity: NativeActivityController) throws -> NativeClientSession {
    let nav = ShellNavigation(destination: .activity, settingsSection: .network,
        drafts: ShellDrafts(values: [.network: "Retained **literal** draft"]))
    let session = NativeClientSession(navigation: nav, applications: LocalApplicationsController(),
        inspection: ClientController(), activity: activity)
    try expect(session.activity === activity, "Refusing actions: session replaced fake owner")
    return session
}
@MainActor private func navigationPaint<V: View>(_ view: V, dark: Bool = false,
    activateHelp: Bool = false) throws -> Data {
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
    if activateHelp {
        // Only this process's inactive, hidden hosting tree. No AX trust,
        // external process, event injection, app launch or native storage.
        var visited = Set<ObjectIdentifier>()
        var buttons: [any NSAccessibilityProtocol] = []
        var observed: [String] = []
        var appKitButtons: [String] = []
        var appKitButtonCount = 0
        var soleAppKitButton: NSButton?
        func visit(_ object: AnyObject) {
            guard visited.count < 4096, visited.insert(ObjectIdentifier(object)).inserted else { return }
            // Use the public NSButton cast: an AXUnknown SwiftUI implementation
            // class name does not establish conformance or a usable public title.
            // Keep this inventory separate from the first few AX ancestors so
            // it still reports controls deep inside the actual Activity root.
            if let button = object as? NSButton {
                appKitButtonCount += 1
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
                   accessible.accessibilityLabel()?.lowercased() == "get help" || accessible.accessibilityTitle()?.lowercased() == "get help" { buttons.append(accessible) }
                for child in accessible.accessibilityChildren() ?? [] { visit(child as AnyObject) }
            }
            if let view = object as? NSView { for child in view.subviews { visit(child) } }
        }
        visit(host)
        let diagnostics = observed.joined(separator: " | ")
            + " NSButtonCount=" + String(appKitButtonCount) + " NSButtons=" + appKitButtons.joined(separator: " | ")
            + " visited=" + String(visited.count)
        if buttons.count == 1 {
            try expect(buttons[0].accessibilityPerformPress(), "Actual Get help button refused explicit activation")
        } else if buttons.isEmpty, appKitButtonCount == 1, visited.count < 4096,
                  let button = soleAppKitButton {
            // CHECK-MODIFIED: RED7 established that the harmless hidden SwiftUI
            // button is an enabled NSButton with erased AX/name/identifier and
            // nil public action/target. Try its public control activation once.
            // A second NSButton or incomplete traversal refuses this fallback;
            // the unchanged real callback assertions decide whether it worked.
            try expect(button.isEnabled, "Sole hidden NSButton is disabled: " + diagnostics)
            button.performClick(nil)
        } else {
            throw CheckFailure(description: "Expected exactly one actual Get help AX button or sole hidden NSButton: " + diagnostics)
        }
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    }
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CheckFailure(description: "Activity bitmap unavailable") }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try expect(!window.isVisible && !app.isActive && app.activationPolicy() == .prohibited, "Activity capture became visible")
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CheckFailure(description: "Activity PNG unavailable") }
    try expect(png.count > 1000, "Activity paint is implausibly blank")
    return png
}
@MainActor private func navigationCleared(_ controller: NativeActivityController) throws {
    try expect(controller.phase == .unavailable && controller.snapshot == nil && controller.presentation.rows.isEmpty,
               "Failure retained a displayed snapshot or cached rows")
}

// One immutable host/root/window allocation for observation propagation checks.
// Reconstructing the root after the action would hide a missing nested observer.
@MainActor private final class RetainedActivityRoot {
    let host: NSHostingView<AnyView>
    let window: NSWindow
    init(_ session: NativeClientSession) throws {
        let app = NSApplication.shared
        if app.activationPolicy() != .prohibited { _ = app.setActivationPolicy(.prohibited) }
        try expect(app.activationPolicy() == .prohibited && !app.isActive, "Retained root must remain inactive")
        host = NSHostingView(rootView: AnyView(NativeClientRootView(session: session)
            .frame(width: 1000, height: 800).environment(\.colorScheme, .light)))
        host.frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        host.appearance = NSAppearance(named: .aqua)
        window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
    }
    func pixels() throws -> Data {
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        let deadline = Date().addingTimeInterval(0.20)
        while Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.01)))
        }
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw CheckFailure(description: "Retained root bitmap unavailable")
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let app = NSApplication.shared
        try expect(!window.isVisible && !app.isActive && app.activationPolicy() == .prohibited,
                   "Retained root became visible or active")
        guard let data = bitmap.representation(using: .png, properties: [:]), data.count > 1000 else {
            throw CheckFailure(description: "Retained root PNG unavailable or blank")
        }
        return data
    }
    func close() { window.close() }
}

@MainActor func registerNativeActivityNavigationChecks() {
    check("PAT2663 navigation: offscreen press harness activates one harmless ordinary SwiftUI button exactly once") {
        var presses = 0
        _ = try navigationPaint(Button(action: { presses += 1 }) { Text(verbatim: "Get help") }
            .accessibilityIdentifier("PAT2663.harmless.get-help"), activateHelp: true)
        try expect(presses == 1, "Offscreen press harness did not activate ordinary SwiftUI button exactly once")
        let app = NSApplication.shared
        try expect(!app.isActive && app.activationPolicy() == .prohibited, "Press harness activated the application")
    }
    check("PAT2663 navigation: ordinary construction/navigation preserves idle distinct owners without native action") {
        let a = NativeClientSession(), b = NativeClientSession(), activity = a.activity
        try expect(activity !== b.activity && activity.testSession == nil, "Ordinary sessions share a history or inject a fake")
        for destination in ShellDestination.allCases {
            a.navigation.select(destination)
            for setting in ShellSettingsSection.allCases { a.navigation.selectSettings(setting) }
            try expect(a.activity === activity && activity.phase == .idle && activity.snapshot == nil && activity.helpSelection == nil,
                       "Ordinary navigation opened history or replaced its owner")
        }
        try expect(ActivityHistoryOwner().snapshot.available == false, "Ordinary lower owner acquired authority")
    }
    check("PAT2663 navigation: fake construction and every route/settings/root paint are inert and preserve all owners/drafts") {
        let (activity, fake) = try navigationPair(), session = try navigationSession(activity)
        let applications = session.applications, inspection = session.inspection, network = session.network, nav = session.navigation
        for destination in ShellDestination.allCases {
            nav.select(destination); _ = try navigationPaint(NativeClientRootView(session: session))
            for setting in ShellSettingsSection.allCases { nav.selectSettings(setting) }
            try expect(session.activity === activity && session.applications === applications && session.inspection === inspection && session.network === network && session.navigation === nav,
                       "Navigation replaced a retained owner")
        }
        try expect(fake.calls.isEmpty && activity.phase == .idle && activity.snapshot == nil, "Render or navigation called history")
        try expect(nav.drafts.values[.network] == "Retained **literal** draft", "Activity navigation discarded drafts")
    }
    check("PAT2663 navigation: explicit load calls only reload once and publishes exact immutable snapshot/correlation") {
        let (activity, fake) = try navigationPair(); try navigationLoad(activity, fake)
        try expect(fake.calls == ["reload"], "Load did not call exactly reload")
        try expect(activity.phase == .loaded && activity.snapshot == fake.next, "Load did not publish exact snapshot")
        try expect(activity.presentation.rows == ActivityPresentation.make(fake.next).rows, "Load altered row literals or event/attempt correlation")
        try expect(activity.presentation.provenance.lowercased().contains("test double") && activity.presentation.provenance.lowercased().contains("last"), "Fake last-loaded provenance missing")
        try expect(!activity.presentation.provenance.lowercased().contains("current installed"), "Fake provenance claims current installation")
    }
    check("PAT2663 navigation: explicit create accepts only fresh empty revision zero and never reloads") {
        let (activity, fake) = try navigationPair(); fake.next = ActivitySnapshot(available: true, revision: 0)
        try navigationIdentity(activity, fake); activity.createFresh()
        try expect(fake.calls == ["create"] && activity.phase == .loaded && activity.snapshot == fake.next, "Explicit fresh creation not exact")
    }
    for invalid in [ActivitySnapshot(available: false), ActivitySnapshot(available: true),
                    ActivitySnapshot(available: true, revision: 1),
                    ActivitySnapshot(available: true, revision: 0, events: [navigationEvent()])] {
        check("PAT2663 navigation: creation refuses nonfresh result available=\(invalid.available) revision=\(String(describing: invalid.revision)) events=\(invalid.events.count)") {
            let (activity, fake) = try navigationPair(); fake.next = invalid
            try navigationIdentity(activity, fake); activity.createFresh()
            try expect(fake.calls == ["create"], "Invalid create retried or loaded")
            try navigationCleared(activity)
        }
    }
    check("PAT2663 navigation: retention before a successful load refuses without calling backend") {
        let (activity, fake) = try navigationPair(); try navigationIdentity(activity, fake); activity.applyRetention()
        try expect(fake.calls.isEmpty && activity.snapshot == nil, "Retention opened an unloaded owner")
    }
    check("PAT2663 navigation: explicit retention uses loaded owner once and publishes exact retained generation") {
        let (activity, fake) = try navigationPair(); try navigationLoad(activity, fake)
        fake.next = ActivitySnapshot(available: true, revision: 8, events: [], ageAvailable: true)
        try navigationIdentity(activity, fake); activity.applyRetention()
        try expect(fake.calls == ["reload", "retention"] && activity.snapshot == fake.next && activity.phase == .loaded, "Retention did not use exact loaded owner")
    }
    for failure in [ActivityRefusal.unavailable, .invalidWire, .conflict, .uncertain, .readbackMismatch] {
        check("PAT2663 navigation: reload \(failure) clears stale lower cache, drops failed owner and never creates/retries") {
            let (activity, fake) = try navigationPair(); try navigationLoad(activity, fake)
            try expect(activity.snapshot != nil, "Positive setup did not load")
            fake.failure = failure; try navigationLoad(activity, fake)
            try navigationCleared(activity)
            try expect(fake.snapshot.available && fake.calls == ["reload", "reload"], "Error setup/cache or exact reload count wrong")
            try navigationIdentity(activity, fake); activity.applyRetention()
            try expect(fake.calls == ["reload", "reload"], "Failed owner remained active for retention")
            try expect(!activity.selectHelp(eventID: navigationEvent().eventID), "Unavailable history allowed a selection")
        }
    }
    for invalid in [ActivitySnapshot(available: false, revision: 9, events: [navigationEvent()]),
                    ActivitySnapshot(available: true, events: [navigationEvent()]),
                    ActivitySnapshot(available: true, revision: 9, events: [navigationEvent(), navigationEvent()])] {
        check("PAT2663 navigation: invalid reload snapshot refuses available=\(invalid.available) revision=\(String(describing: invalid.revision)) events=\(invalid.events.count)") {
            let (activity, fake) = try navigationPair(); fake.next = invalid; try navigationLoad(activity, fake)
            try expect(fake.calls == ["reload"], "Invalid reload invoked fallback")
            try navigationCleared(activity)
        }
    }
    for operation in ["create", "retention"] {
        check("PAT2663 navigation: \(operation) error invalidates displayed cache and drops active backend") {
            let (activity, fake) = try navigationPair(); try navigationLoad(activity, fake)
            try expect(activity.snapshot != nil, "Positive setup did not load")
            fake.failure = .uncertain; try navigationIdentity(activity, fake)
            if operation == "create" { activity.createFresh() } else { activity.applyRetention() }
            try navigationCleared(activity)
            try expect(fake.calls == ["reload", operation], "Action retried or fell back")
            try navigationIdentity(activity, fake); activity.applyRetention()
            try expect(fake.calls == ["reload", operation], "Failed owner retained after action error")
        }
    }
    check("PAT2663 navigation: exact loaded Get help selection is immutable, typed and does no backend work") {
        let (activity, fake) = try navigationPair(); try navigationLoad(activity, fake)
        let selected = navigationEvent(), calls = fake.calls
        try expect(activity.selectHelp(eventID: selected.eventID), "Exact loaded event was refused")
        guard let original = activity.helpSelection else { throw CheckFailure(description: "Selected local handoff missing") }
        try expect(original.event == selected && original.revision == 7 && original.provenance == .testDouble, "Handoff substituted event/attempt/revision/status/reason/provenance")
        try expect(!activity.selectHelp(eventID: "unknown") && activity.helpSelection == original && fake.calls == calls, "Unknown event changed original handoff or called backend")
        fake.next = ActivitySnapshot(available: true, revision: 8, events: [navigationEvent(id: "55555555-5555-4555-8555-555555555555", status: .needsRecovery, reason: .recoveryRequired)])
        try navigationLoad(activity, fake)
        try expect(activity.helpSelection == original, "New snapshot replaced original selected failure")
        fake.failure = .invalidWire; try navigationLoad(activity, fake)
        try expect(activity.helpSelection == original && original.event == selected, "Later load failure mutated original selected record")
    }
    check("PAT2663 navigation: finite status/reason selection preserves exact typed values without reinterpretation") {
        for status in ActivityStatus.allCases {
            for reason in ActivityReason.allCases {
                let (activity, fake) = try navigationPair()
                let event = navigationEvent(status: status, reason: reason)
                fake.next = ActivitySnapshot(available: true, revision: 23, events: [event])
                try navigationLoad(activity, fake)
                try expect(activity.selectHelp(eventID: event.eventID), "Exact finite status/reason event refused")
                try expect(activity.helpSelection?.event == event && activity.helpSelection?.revision == 23 && fake.calls == ["reload"],
                           "Selection reinterpreted typed status/reason or performed IO")
            }
        }
    }
    check("PAT2663 navigation: unavailable/duplicate membership refuses Get help without backend or routing") {
        let (activity, fake) = try navigationPair(), session = try navigationSession(activity)
        try expect(!activity.selectHelp(eventID: navigationEvent().eventID) && activity.helpSelection == nil, "Idle selection accepted")
        try expect(fake.calls.isEmpty && session.navigation.destination == .activity, "Idle selection operated or routed")
        fake.next = ActivitySnapshot(available: true, revision: 7, events: [navigationEvent(), navigationEvent()])
        try navigationLoad(activity, fake)
        try expect(!activity.selectHelp(eventID: navigationEvent().eventID) && activity.helpSelection == nil, "Ambiguous duplicate membership accepted")
    }
    check("PAT2663 navigation: selected local handoff and rows survive all routes and support paints without IO") {
        let (activity, fake) = try navigationPair(), session = try navigationSession(activity)
        try navigationLoad(activity, fake)
        try expect(activity.selectHelp(eventID: navigationEvent().eventID), "Selection setup failed")
        let original = activity.helpSelection, snapshot = activity.snapshot, calls = fake.calls
        for destination in ShellDestination.allCases {
            session.navigation.select(destination)
            _ = try navigationPaint(NativeClientRootView(session: session))
            try expect(session.activity === activity && activity.helpSelection == original && activity.snapshot == snapshot, "Route mutated local selection/history")
        }
        try expect(fake.calls == calls, "Support/render/navigation sent or read history")
    }
    check("PAT2663 navigation: actual Activity root observes controller and paints loaded rows, support paints selected handoff") {
        let (activity, fake) = try navigationPair(), session = try navigationSession(activity)
        let before = try navigationPaint(NativeClientRootView(session: session))
        try navigationLoad(activity, fake)
        let loaded = try navigationPaint(NativeClientRootView(session: session))
        try expect(before != loaded, "Activity root is not bound to loaded controller")
        session.navigation.select(.support)
        let unselected = try navigationPaint(NativeClientRootView(session: session))
        try expect(activity.selectHelp(eventID: navigationEvent().eventID), "Selection setup failed")
        let selected = try navigationPaint(NativeClientRootView(session: session))
        try expect(unselected != selected, "Support root does not display selected local record")
        try expect(fake.calls == ["reload"], "Root composition performed extra IO")
    }
    check("PAT2663 navigation: same hidden hosting root observes load and selected support without reconstruction") {
        let (activity, fake) = try navigationPair(), session = try navigationSession(activity)
        let retained = try RetainedActivityRoot(session); defer { retained.close() }
        let host = retained.host, window = retained.window
        let before = try retained.pixels()
        try navigationLoad(activity, fake)
        try expect(activity.snapshot == fake.next, "Retained-root load setup did not publish")
        let loaded = try retained.pixels()
        try expect(before != loaded, "Same hosting root did not observe nested activity load")
        session.navigation.select(.support)
        let unselected = try retained.pixels()
        try navigationIdentity(activity, fake)
        try expect(activity.selectHelp(eventID: navigationEvent().eventID), "Retained-root support selection setup failed")
        let selected = try retained.pixels()
        try expect(unselected != selected, "Same support root did not observe nested help selection")
        try expect(retained.host === host && retained.window === window && fake.calls == ["reload"],
                   "Retained-root check replaced a host/window or performed extra IO")
    }
    check("PAT2663 navigation: session local help intent selects exact row and refuses malformed correlation without side effects") {
        let (activity, fake) = try navigationPair(), session = try navigationSession(activity)
        try navigationLoad(activity, fake)
        guard let row = activity.presentation.rows.first else { throw CheckFailure(description: "Session intent setup missing row") }
        try navigationIdentity(activity, fake)
        try expect(session.showActivityHelp(row), "Exact current row intent refused")
        let selection = activity.helpSelection
        try expect(selection?.event == navigationEvent() && selection?.revision == 7 && selection?.provenance == .testDouble && session.navigation.destination == .support,
                   "Session intent did not bind exact event/attempt/revision and route support")
        session.navigation.select(.applications)
        let drafts = session.navigation.drafts.values, calls = fake.calls
        for malformed in [ActivityRow(eventID: "malformed", attemptID: row.attemptID, text: row.text),
                          ActivityRow(eventID: row.eventID, attemptID: "99999999-9999-4999-8999-999999999999", text: row.text),
                          ActivityRow(eventID: row.eventID, attemptID: row.attemptID, text: row.text + " changed")] {
            try navigationIdentity(activity, fake)
            try expect(!session.showActivityHelp(malformed), "Mismatched callback row accepted")
            try expect(activity.helpSelection == selection && session.navigation.destination == .applications && session.navigation.drafts.values == drafts && fake.calls == calls,
                       "Refused callback changed selection/navigation/drafts or performed IO")
        }
    }
    check("PAT2663 navigation: session refuses old changed-row callback and unavailable history while preserving original handoff") {
        let (activity, fake) = try navigationPair(), session = try navigationSession(activity)
        try navigationLoad(activity, fake)
        guard let old = activity.presentation.rows.first else { throw CheckFailure(description: "Stale callback setup missing row") }
        try navigationIdentity(activity, fake)
        try expect(session.showActivityHelp(old), "Original session selection setup failed")
        let original = activity.helpSelection
        fake.next = ActivitySnapshot(available: true, revision: 8, events: [navigationEvent(name: "Changed local failure", status: .needsRecovery, reason: .recoveryRequired)])
        try navigationLoad(activity, fake)
        try expect(activity.presentation.rows.first != old, "Stale callback setup did not change row")
        session.navigation.select(.licence)
        let drafts = session.navigation.drafts.values, calls = fake.calls
        try navigationIdentity(activity, fake)
        try expect(!session.showActivityHelp(old) && activity.helpSelection == original && session.navigation.destination == .licence && session.navigation.drafts.values == drafts && fake.calls == calls,
                   "Old changed-row callback substituted new failure, routed or performed IO")
        fake.failure = .invalidWire; try navigationLoad(activity, fake)
        let failedCalls = fake.calls
        try navigationIdentity(activity, fake)
        try expect(!session.showActivityHelp(old) && activity.helpSelection == original && session.navigation.destination == .licence && session.navigation.drafts.values == drafts && fake.calls == failedCalls,
                   "Unavailable callback changed retained handoff/navigation/drafts or performed IO")
    }
    check("PAT2663 navigation: light/dark long literal controller/view/root paints are inert and callback only explicit") {
        let (activity, fake) = try navigationPair(), session = try navigationSession(activity)
        fake.next = ActivitySnapshot(available: true, revision: 9,
            events: [navigationEvent(name: String(repeating: "<tag> **literal** café & ", count: 9))])
        try navigationLoad(activity, fake)
        try expect(activity.presentation.rows == ActivityPresentation.make(fake.next).rows, "Long literal rows changed")
        let snapshot = activity.snapshot, calls = fake.calls
        var callbacks = 0
        for dark in [false, true] {
            let original = try navigationPaint(ActivityView(presentation: activity.presentation), dark: dark)
            _ = try navigationPaint(ActivityView(presentation: activity.presentation, onGetHelp: { _ in callbacks += 1 }), dark: dark)
            _ = try navigationPaint(NativeClientRootView(session: session), dark: dark)
            try expect(!original.isEmpty && callbacks == 0 && fake.calls == calls && activity.snapshot == snapshot && activity.helpSelection == nil, "Painting operated, selected or altered history")
        }
    }
    check("PAT2663 navigation: actual shared row button passes exact row once only on explicit activation") {
        let presentation = ActivityPresentation.make(ActivitySnapshot(available: true, revision: 7, events: [navigationEvent()]))
        var callbacks: [ActivityRow] = []
        _ = try navigationPaint(ActivityView(presentation: presentation, onGetHelp: { callbacks.append($0) }), activateHelp: true)
        try expect(callbacks == presentation.rows, "Real row activation did not supply exact event/attempt/literal row once")
    }
    check("PAT2663 navigation: actual root Get help button selects exact local record and routes support without backend work") {
        let (activity, fake) = try navigationPair(), session = try navigationSession(activity)
        try navigationLoad(activity, fake)
        _ = try navigationPaint(NativeClientRootView(session: session), activateHelp: true)
        try expect(session.navigation.destination == .support && activity.helpSelection?.event == navigationEvent() && activity.helpSelection?.revision == 7,
                   "Real root callback did not select exact record and route support")
        try expect(fake.calls == ["reload"], "Real Get help callback read/wrote history")
    }
    check("PAT2663 navigation: native boundary/source composition uses explicit factory, real callback and local no-send support") {
        // Native factory is deliberately NOT executed. Static guards cover this
        // non-executable boundary and actual row callback wiring only.
        let controller = code(try source("Sources/PatchedClient/NativeActivityController.swift"))
        let root = code(try source("Sources/PatchedClient/NativeClientSession.swift"))
        let view = code(try source("Sources/PatchedActivity/ActivityView.swift"))
        try expect(controller.contains("NativeActivityContext.open()") && controller.contains("private"), "Explicit private native adapter missing")
        try expect(root.contains("session.activity") && root.contains("onGetHelp:") && root.contains("session.showActivityHelp") && root.contains("selectHelp(eventID:") && root.contains(".select(.support)"), "Root lacks actual callback/session-intent/selection/support routing")
        try expect(root.contains("row.eventID") && (root.contains(".rows.contains(row)") || root.contains("row.attemptID")) && root.contains("helpSelection"), "Root does not bind row correlation or display immutable handoff")
        try expect(view.contains("Button") && view.contains("onGetHelp"), "Real row button is not bound to callback")
        try expect(root.contains("No message or diagnostic report is sent."), "Existing no-send support disclosure lost")
        for forbidden in ["URLSession", "mailto:", "SupportClient(", "ActivityHistoryOwner(", ".onAppear", ".task", "Timer("] {
            try expect(!root.contains(forbidden) && !controller.contains(forbidden), "Navigation introduced IO/authority: \(forbidden)")
        }
    }
}
