import Foundation
import SwiftUI
import AppKit
import PatchedShell
import PatchedScheduling
@_spi(Testing) import PatchedClient
@_spi(Testing) import PatchedNetworking
@_spi(Testing) import PatchedUpdatePreferences

// Independent controller checks. No OS identity, permission, helper, transport or native home fixture.
private let nfrGeneration = "pat2667-generation"
private let nfrPrincipal = SchedulingPrincipal("pat2667-check-owner")
private let nfrScope = "pat2667-private-fixture"
private func nfrCanonical(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
}
// Expected inputs are hand-declared wire objects, independent of product codecs.
private func nfrBytes(_ schema: Int = 3, revision: UInt64 = 0, daily: Bool = true,
                      notify: Bool = true, reports: Bool = true, complete: Bool = false,
                      mode: String = "system", host: String = "", port: String = "") throws -> Data {
    let v1 = try nfrCanonical(["schema": 1, "principal": nfrPrincipal.value, "storeScope": nfrScope,
        "revision": NSNumber(value: revision), "exclusions": [], "skips": [], "mutations": []])
    if schema == 1 { return v1 }
    let v2 = try nfrCanonical(["schema": 2, "preferences": String(decoding: v1, as: UTF8.self),
        "settings": ["dailyChecks": daily, "notifications": notify, "automaticUpdates": false, "pause": NSNull()],
        "settingsMutations": []])
    if schema == 2 { return v2 }
    return try nfrCanonical(["schema": 3, "scheduled": String(decoding: v2, as: UTF8.self),
        "setup": ["failureReports": reports, "completed": complete,
                  "networkDraft": ["mode": mode, "host": host, "port": port]], "setupMutations": []])
}
@MainActor private class NFRStore: PreferenceStore {
    enum Fault: String, CaseIterable { case none, unavailableRead, notCommitted, conflict, uncertain, readback }
    var bytes: Data?
    var reads = 0, writes = 0
    var fault: Fault = .none
    var proposals: [Data] = []
    var expectedValues: [Data?] = []
    private var mismatch = false
    init(_ bytes: Data? = nil) { self.bytes = bytes }
    func read(maximumBytes: Int) -> PreferenceRead {
        reads += 1
        if fault == .unavailableRead { return .unavailable }
        if mismatch { return .bytes(Data("readback-mismatch".utf8)) }
        guard let bytes else { return .missing }
        return bytes.count <= maximumBytes ? .bytes(bytes) : .unavailable
    }
    func compareAndSwap(expected: Data?, proposed: Data, maximumBytes: Int) -> PreferenceCommit {
        writes += 1; proposals.append(proposed); expectedValues.append(expected)
        guard proposed.count <= maximumBytes else { return .notCommitted }
        if fault == .conflict || expected != bytes { return .conflict }
        if fault == .notCommitted { return .notCommitted }
        bytes = proposed
        if fault == .readback { mismatch = true }
        return fault == .uncertain ? .uncertain : .committed
    }
    func recover() { fault = .none; mismatch = false }
}
// Serial check-owned persistence, private physical .build root supplied only by newDirectory.
// This fixture is deliberately not a replacement for FilePreferenceStore's security policy.
@MainActor private final class NFRDiskStore: PreferenceStore {
    let root: URL
    private var file: URL { root.appendingPathComponent("record.json") }
    var reads = 0, writes = 0
    init() throws { root = try newDirectory("pat2667-preferences") }
    func read(maximumBytes: Int) -> PreferenceRead {
        reads += 1
        guard FileManager.default.fileExists(atPath: file.path) else { return .missing }
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= maximumBytes, let bytes = try? Data(contentsOf: file), bytes.count <= maximumBytes else { return .unavailable }
        return .bytes(bytes)
    }
    func compareAndSwap(expected: Data?, proposed: Data, maximumBytes: Int) -> PreferenceCommit {
        writes += 1
        guard proposed.count <= maximumBytes else { return .notCommitted }
        switch read(maximumBytes: maximumBytes) {
        case .missing: guard expected == nil else { return .conflict }
        case .bytes(let current): guard expected == current else { return .conflict }
        case .unavailable: return .notCommitted
        }
        do { try proposed.write(to: file, options: .atomic); return .committed }
        catch { return .uncertain }
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
private final class NFRReads: @unchecked Sendable {
    private let lock = NSLock(); private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func record() { lock.lock(); value += 1; lock.unlock() }
}
@MainActor private final class NFRRequest: NativeNetworkObservationRequest { func cancel() {} }
@MainActor private final class NFRNetwork: NativeNetworkObservationProvider {
    var calls = 0
    func begin(completion: @escaping @MainActor (NativeNetworkObservation) -> Void) -> any NativeNetworkObservationRequest {
        calls += 1; return NFRRequest()
    }
}
private enum NFRFactoryFailure: Error { case unavailable }
@MainActor private final class NFROpen { var count = 0; var failuresRemaining = 0 }
@MainActor private func nfrSession(_ store: any PreferenceStore) -> PreferenceSession {
    PreferenceSession(store: store, principal: nfrPrincipal, storeScope: nfrScope,
        generation: nfrGeneration, queueID: "pat2667-check-queue")
}
@MainActor private struct NFRFixture {
    let root: URL
    let reads: NFRReads
    let applications: LocalApplicationsController
    let navigation: ShellNavigation
    let network: NativeNetworkSettingsController
    let provider: NFRNetwork
    let opened: NFROpen
    let preferences: PreferenceSession
    let controller: NativeFirstRunController
    init(_ store: any PreferenceStore, generation: String = nfrGeneration,
         initiallyPresented: Bool = true, openFailures: Int = 0) throws {
        root = try newDirectory("pat2667-applications")
        let contents = root.appendingPathComponent("Fixture.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleDisplayName": "Fixture",
            "CFBundleIdentifier": "example.pat2667.fixture", "CFBundleShortVersionString": "1.2",
            "CFBundleVersion": "12"], format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        reads = NFRReads(); let counter = reads
        applications = LocalApplicationsController(inventory: LocalApplicationInventory(fixtureRoots: [root.path], observer: { _ in counter.record() }))
        navigation = ShellNavigation(destination: .applications, settingsSection: .updates, drafts: ShellDrafts(values: [:]))
        provider = NFRNetwork(); network = NativeNetworkSettingsController(provider: provider)
        opened = NFROpen(); opened.failuresRemaining = openFailures; let opener = opened
        preferences = nfrSession(store)
        controller = NativeFirstRunController(navigation: navigation, applications: applications, network: network,
            preferences: preferences, generation: generation, onOpen: {
                opener.count += 1
                if opener.failuresRemaining > 0 {
                    opener.failuresRemaining -= 1
                    throw NFRFactoryFailure.unavailable
                }
            }, initiallyPresented: initiallyPresented)
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
    // This assertion must precede every path which might call the scanner.
    func assertOwners() throws {
        try expect(controller.applications === applications && controller.navigation === navigation && controller.network === network,
                   "Replaced fixture owner; refusing any scan")
    }
    func assertIdle() throws {
        try expect(reads.count == 0 && applications.observation == nil && applications.phase == .idle && provider.calls == 0,
                   "Implicit scan or Network observation")
    }
}
@MainActor private func nfrDraft(_ c: NativeFirstRunController) -> [Bool] { [c.dailyChecks, c.notifications, c.failureReports] }
private func nfrRefused(_ result: PreferenceEditResult) -> Bool { if case .refused = result { return true }; return false }
private func nfrReceipts(_ bytes: Data?) throws -> [[String: Any]] {
    guard let bytes, let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
          let receipts = object["setupMutations"] as? [[String: Any]] else { throw CheckFailure(description: "No literal schema3 receipts") }
    return receipts
}
// Bounded offscreen paint of only the explicitly checked fixture controller.
@MainActor private func nfrPaint(_ f: NFRFixture) throws {
    try f.assertOwners()
    let app = NSApplication.shared
    if app.activationPolicy() != .prohibited { _ = app.setActivationPolicy(.prohibited) }
    try expect(app.activationPolicy() == .prohibited && !app.isActive, "Recovery paint must remain inactive")
    let host = NSHostingView(rootView: NativeFirstRunView(controller: f.controller).frame(width: 680, height: 520))
    host.frame = NSRect(x: 0, y: 0, width: 680, height: 520)
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.close() }
    host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    let deadline = Date().addingTimeInterval(0.03)
    while Date() < deadline { _ = RunLoop.current.run(mode: .default, before: deadline) }
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        throw CheckFailure(description: "Recovery fixture bitmap unavailable")
    }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0, "Recovery fixture was not painted")
}
@MainActor func registerNativeFirstRunChecks() {
    check("PAT2667: construction retains exact owners and has no opener, preference or scanner effects") {
        let store = NFRStore(try nfrBytes()); let f = try NFRFixture(store); defer { f.cleanup() }
        try f.assertOwners(); try f.assertIdle()
        try expect(f.opened.count == 0 && store.reads == 0 && store.writes == 0, "Constructor opened/read/wrote")
        try expect(f.controller.localState == .unopened && f.controller.step == .welcome && f.controller.isPresented && !f.controller.networkPresented,
                   "Initial presentation state")
    }
    check("PAT2667: defaults are unsaved declarations with no accepted setup") {
        let store = NFRStore(); let f = try NFRFixture(store); defer { f.cleanup() }
        try expect(nfrDraft(f.controller) == [true, true, true] && f.controller.saveStatus == .unsaved,
                   "Default declarations changed")
        try expect(f.controller.firstRunSetup == nil && f.controller.acceptedRevision == nil && f.controller.statusText.lowercased().contains("unsaved"),
                   "Declarations presented as accepted")
        try expect(store.reads == 0 && store.writes == 0, "Getter I/O")
    }
    check("PAT2667: ordinary constructor and pre-load refusal never require native context") {
        let navigation = ShellNavigation(destination: .applications, settingsSection: .updates, drafts: ShellDrafts(values: [:]))
        let applications = LocalApplicationsController(), provider = NFRNetwork(), network = NativeNetworkSettingsController(provider: provider)
        let c = NativeFirstRunController(navigation: navigation, applications: applications, network: network)
        try expect(c.navigation === navigation && c.applications === applications && c.network === network, "Ordinary owners replaced")
        try expect(nfrRefused(c.saveChoices(complete: true)) && nfrRefused(c.createFreshPreferences()), "Unopened ordinary state granted write")
        c.present(); c.dismiss(); c.present(); c.edit(dailyChecks: false, notifications: false, failureReports: false)
        try expect(c.acceptedRevision == nil && c.firstRunSetup == nil && applications.observation == nil && provider.calls == 0,
                   "Ordinary display acquired accepted state/effects")
    }
    check("PAT2667: present and dismiss preserve choices and perform no persistence") {
        let s = NFRStore(); let f = try NFRFixture(s, initiallyPresented: false); defer { f.cleanup() }
        try expect(!f.controller.isPresented, "Initial suppression ignored")
        f.controller.present(); try expect(f.controller.isPresented, "Present failed")
        f.controller.edit(dailyChecks: false, notifications: false, failureReports: false)
        f.controller.dismiss(); try expect(!f.controller.isPresented, "Dismiss failed")
        f.controller.present()
        try expect(nfrDraft(f.controller) == [false, false, false] && f.controller.firstRunSetup == nil, "Dismiss reset/accepted choices")
        try expect(f.opened.count == 0 && s.reads == 0 && s.writes == 0, "Presentation opened store")
        try f.assertIdle()
    }
    check("PAT2667: first explicit open calls factory once and later explicit opens reload same owner") {
        let s = NFRStore(try nfrBytes()); let f = try NFRFixture(s); defer { f.cleanup() }
        f.controller.openPreferences()
        try expect(f.opened.count == 1 && s.reads == 1 && s.writes == 0 && f.controller.localState == .available, "Explicit open boundary")
        f.controller.openPreferences()
        try expect(f.opened.count == 1 && s.reads == 2 && s.writes == 0 && f.controller.acceptedRevision == f.preferences.acceptedRevision,
                   "Reload replaced owner or reopened factory")
        try f.assertIdle()
    }
    check("PAT2667: missing load does not create defaults or advance to accepted setup") {
        let s = NFRStore(); let f = try NFRFixture(s); defer { f.cleanup() }
        f.controller.openPreferences()
        try expect(f.controller.localState == .missing && f.controller.lastRefusal == .missing && f.controller.firstRunSetup == nil && s.bytes == nil && s.writes == 0,
                   "Missing became accepted/reset")
        f.controller.advance()
        try expect(f.controller.step != .findApps && s.writes == 0 && f.controller.isPresented, "Continue auto-created missing preferences")
        try f.assertIdle()
    }
    check("PAT2667: fresh creation refuses before the last load proves missing") {
        let s = NFRStore(); let f = try NFRFixture(s); defer { f.cleanup() }
        try expect(nfrRefused(f.controller.createFreshPreferences()) && s.reads == 0 && s.writes == 0 && f.opened.count == 0,
                   "Create inferred missing or opened")
    }
    check("PAT2667: explicit missing create writes only schema1 revision0; choices need a separate save") {
        let s = NFRStore(); let f = try NFRFixture(s); defer { f.cleanup() }
        f.controller.openPreferences(); f.controller.edit(dailyChecks: false, notifications: false, failureReports: false)
        try expect(f.controller.createFreshPreferences() == .accepted(revision: 0), "Explicit fresh creation missing")
        try expect(s.writes == 1 && s.bytes == (try nfrBytes(1)) && f.preferences.firstRunSetup == nil,
                   "Fresh create silently committed schema3/setup")
        try expect(nfrDraft(f.controller) == [false, false, false], "Fresh create discarded unsaved opt-outs")
        try expect(f.controller.saveChoices(complete: false) == .accepted(revision: 1) && s.writes == 2, "Separate choices CAS missing")
        try f.assertIdle()
    }
    for label in ["corrupt", "existing", "unavailable"] {
        check("PAT2667: explicit create never resets \(label) state") {
            let bytes: Data
            if label == "existing" { bytes = try nfrBytes() } else { bytes = Data("not-json".utf8) }
            let s = NFRStore(bytes); if label == "unavailable" { s.fault = .unavailableRead }
            let f = try NFRFixture(s); defer { f.cleanup() }; f.controller.openPreferences()
            let original = s.bytes, reads = s.reads
            try expect(nfrRefused(f.controller.createFreshPreferences()) && s.writes == 0 && s.bytes == original && s.reads == reads,
                       "Create reset existing/corrupt/unavailable state")
            if label != "existing" {
                try expect(f.controller.localState == .unavailable && f.controller.firstRunSetup == nil, "Bad state shown accepted")
                let reason: PreferenceRefusal = label == "corrupt" ? .malformed : .unavailable
                try expect(f.controller.lastRefusal == reason, "Corrupt/unavailable refusal collapsed")
            }
            try f.assertIdle()
        }
    }
    check("PAT2667: state appearing after missing load conflicts instead of resetting") {
        let s = NFRStore(); let f = try NFRFixture(s); defer { f.cleanup() }; f.controller.openPreferences()
        let appeared = try nfrBytes(revision: 4, reports: false); s.bytes = appeared
        try expect(nfrRefused(f.controller.createFreshPreferences()) && s.writes == 0 && s.bytes == appeared,
                   "Late existing record reset")
        try expect(f.controller.firstRunSetup == nil, "Refused create granted setup")
    }
    for schema in [1, 2] {
        check("PAT2667: v\(schema) explicit load is read-only; defaults remain unsaved until one migration save") {
            let bytes = try nfrBytes(schema, daily: false, notify: false); let s = NFRStore(bytes)
            let f = try NFRFixture(s); defer { f.cleanup() }; f.controller.openPreferences()
            try expect(s.bytes == bytes && s.writes == 0 && f.controller.firstRunSetup == nil && f.controller.saveStatus == .unsaved,
                       "Legacy load inferred accepted setup/migrated")
            if schema == 2 { try expect(!f.controller.dailyChecks && !f.controller.notifications, "Legacy schedule values lost") }
            f.controller.edit(dailyChecks: false, notifications: false, failureReports: false)
            try expect(f.controller.saveChoices(complete: false) == .accepted(revision: 1) && s.writes == 1,
                       "Legacy migration not single explicit CAS")
            try expect(f.preferences.firstRunSetup?.failureReports == false && f.preferences.firstRunSetup?.completed == false,
                       "Migration lost explicit declarations")
            try f.assertIdle()
        }
    }
    check("PAT2667: v3 explicit load projects stored opt-outs and Network draft without applying or refreshing") {
        let s = NFRStore(try nfrBytes(daily: false, notify: false, reports: false, mode: "manualHTTP", host: "draft.invalid", port: "abc"))
        let f = try NFRFixture(s); defer { f.cleanup() }; f.controller.openPreferences()
        try expect(nfrDraft(f.controller) == [false, false, false] && f.controller.firstRunSetup == f.preferences.firstRunSetup,
                   "Stored opt-outs lost or accepted mirror differs")
        try expect(f.network.mode == .manualHTTP && f.network.host == "draft.invalid" && f.network.port == "abc" && f.network.choice == nil && f.network.snapshot == nil,
                   "Draft validated/applied/observed instead of restored")
        try expect(s.writes == 0 && f.controller.saveStatus == .loaded, "Load wrote or stayed default")
        try f.assertIdle()
    }
    check("PAT2667: a Network edit made after construction wins over first load") {
        let s = NFRStore(try nfrBytes(mode: "manualHTTP", host: "stored.invalid", port: "8080")); let f = try NFRFixture(s); defer { f.cleanup() }
        f.network.edit(mode: .manualHTTP, host: "draft.invalid", port: "abc"); let revision = f.network.revision
        f.controller.openPreferences()
        try expect(f.network.host == "draft.invalid" && f.network.port == "abc" && f.network.revision == revision && f.network.choice == nil,
                   "Load overwrote a newer shared Network draft")
        try expect(f.controller.saveStatus == .unsaved && s.writes == 0, "Newer Network edit presented as saved")
    }
    check("PAT2667: Network presentation returns to setup with exact owner, drafts and no extra I/O") {
        let s = NFRStore(try nfrBytes()); let f = try NFRFixture(s); defer { f.cleanup() }; f.controller.openPreferences()
        f.controller.edit(dailyChecks: false, notifications: true, failureReports: false); let reads = s.reads
        f.controller.showNetwork()
        try expect(f.controller.networkPresented && f.navigation.destination == .settings && f.navigation.settingsSection == .network,
                   "Network route absent")
        f.network.edit(mode: .manualHTTP, host: "proxy.invalid", port: "notnum"); let revision = f.network.revision
        f.controller.returnFromNetwork()
        try expect(!f.controller.networkPresented && f.controller.isPresented && nfrDraft(f.controller) == [false, true, false], "Return reset setup")
        try expect(f.network.host == "proxy.invalid" && f.network.port == "notnum" && f.network.revision == revision && f.network.choice == nil,
                   "Return replaced/applied draft")
        try expect(s.reads == reads && s.writes == 0, "Network route performed persistence")
        try f.assertOwners(); try f.assertIdle()
    }
    check("PAT2667: memory-only opt-outs and getters perform no reads writes or effects") {
        let s = NFRStore(try nfrBytes()); let f = try NFRFixture(s); defer { f.cleanup() }; f.controller.openPreferences(); let reads = s.reads
        f.controller.edit(dailyChecks: false, notifications: false, failureReports: false)
        for _ in 0..<4 { _ = f.controller.statusText; _ = f.controller.acceptedRevision; _ = f.controller.firstRunSetup }
        try expect(nfrDraft(f.controller) == [false, false, false] && f.controller.saveStatus == .unsaved,
                   "Edit did not retain unsaved opt-outs")
        try expect(s.reads == reads && s.writes == 0 && f.preferences.firstRunSetup?.failureReports == true, "Draft mutated accepted owner")
        try f.assertIdle()
    }
    check("PAT2667: successful save uses one exact-byte CAS and independent readback before acceptance") {
        let before = try nfrBytes(revision: 7); let s = NFRStore(before); let f = try NFRFixture(s); defer { f.cleanup() }; f.controller.openPreferences()
        f.controller.edit(dailyChecks: false, notifications: false, failureReports: false)
        f.network.edit(mode: .manualHTTP, host: "proxy.invalid", port: "abc"); let reads = s.reads
        try expect(f.controller.saveChoices(complete: true) == .accepted(revision: 8), "Save not acknowledged")
        try expect(s.writes == 1 && s.expectedValues.count == 1 && s.expectedValues[0] == before && s.reads == reads + 1,
                   "Save omitted readback or used multiple/wrong CAS")
        try expect(f.controller.acceptedRevision == f.preferences.acceptedRevision && f.controller.firstRunSetup == f.preferences.firstRunSetup && f.controller.saveStatus == .saved,
                   "Acceptance differs from shared owner")
        let receipt = try nfrReceipts(s.bytes)
        try expect(receipt.count == 1 && receipt[0]["complete"] as? Bool == true && (receipt[0]["id"] as? String)?.isEmpty == false, "Missing bounded user-request receipt")
        try expect(f.preferences.firstRunSetup == FirstRunSetupState(failureReports: false, completed: true,
            networkDraft: FirstRunNetworkDraft(mode: .manualHTTP, host: "proxy.invalid", port: "abc")), "Saved wrong declarations")
        try expect(f.controller.isPresented && f.navigation.destination == .applications, "Completion alone hid or navigated")
        try f.assertIdle()
    }
    check("PAT2667: each explicit save has a fresh mutation ID and preserves monotonic completion") {
        let s = NFRStore(try nfrBytes()); let f = try NFRFixture(s); defer { f.cleanup() }; f.controller.openPreferences()
        try expect(f.controller.saveChoices(complete: true) == .accepted(revision: 1), "First save")
        f.controller.edit(dailyChecks: false, notifications: false, failureReports: false)
        try expect(f.controller.saveChoices(complete: false) == .accepted(revision: 2), "Second save reused stale revision/ID")
        let receipts = try nfrReceipts(s.bytes); let ids = receipts.compactMap { $0["id"] as? String }
        try expect(s.writes == 2 && ids.count == 2 && Set(ids).count == 2 && ids.allSatisfy { !$0.isEmpty && $0.utf8.count <= 256 }, "Mutation IDs not fresh/bounded")
        try expect(f.preferences.firstRunSetup?.completed == true && f.preferences.firstRunSetup?.failureReports == false, "Completion regressed/optout restored")
        try f.assertIdle()
    }
    for fault in [NFRStore.Fault.notCommitted, .conflict, .uncertain, .readback] {
        check("PAT2667: \(fault.rawValue) save preserves editable opt-outs and prevents navigation/scan") {
            let s = NFRStore(try nfrBytes()); let f = try NFRFixture(s); defer { f.cleanup() }; f.controller.openPreferences()
            f.controller.edit(dailyChecks: false, notifications: false, failureReports: false)
            f.network.edit(mode: .manualHTTP, host: "kept.invalid", port: "abc"); s.fault = fault
            try f.assertOwners(); f.controller.findApps(); await f.applications.waitUntilIdle()
            try expect(s.writes == 1 && f.controller.isPresented && f.navigation.destination == .applications && f.controller.saveStatus == .unsaved,
                       "Failed save hid/navigated/claimed saved")
            try expect(nfrDraft(f.controller) == [false, false, false] && f.network.host == "kept.invalid" && f.network.port == "abc",
                       "Failure discarded editable drafts")
            try expect(f.controller.statusText.lowercased().contains("unsaved"), "Failure lacks visible unsaved status")
            if fault != .notCommitted {
                try expect(f.controller.firstRunSetup == nil && f.preferences.firstRunSetup == nil, "Blocked setup exposed")
                s.recover(); let reads = s.reads, writes = s.writes
                try expect(nfrRefused(f.controller.saveChoices(complete: true)) && s.reads == reads && s.writes == writes,
                           "Latched save bypassed explicit reload")
            }
            try f.assertIdle()
        }
    }
    check("PAT2667: explicit conflict reload preserves unsaved drafts and visible failure") {
        let s = NFRStore(try nfrBytes()); let f = try NFRFixture(s); defer { f.cleanup() }; f.controller.openPreferences()
        f.controller.edit(dailyChecks: false, notifications: false, failureReports: false)
        f.network.edit(mode: .manualHTTP, host: "kept.invalid", port: "abc")
        s.bytes = try nfrBytes(revision: 1); _ = f.controller.saveChoices(complete: true)
        f.controller.openPreferences()
        try expect(f.opened.count == 1 && f.preferences.acceptedRevision == 1 && nfrDraft(f.controller) == [false, false, false], "Reload reset opt-outs/replaced owner")
        try expect(f.network.host == "kept.invalid" && f.network.port == "abc" && f.controller.saveStatus == .unsaved,
                   "Conflict reload reset Network draft or cleared unsaved status")
        try expect(f.controller.saveChoices(complete: true) == .accepted(revision: 2), "Explicit retry did not use new accepted revision")
    }
    check("PAT2667: known no-commit failure permits explicit retry without reloading or losing opt-outs") {
        let s = NFRStore(try nfrBytes()); let f = try NFRFixture(s); defer { f.cleanup() }; f.controller.openPreferences()
        f.controller.edit(dailyChecks: false, notifications: false, failureReports: false); s.fault = .notCommitted
        try expect(nfrRefused(f.controller.saveChoices(complete: true)), "Known failure accepted")
        s.recover(); try expect(f.controller.saveChoices(complete: true) == .accepted(revision: 1) && s.writes == 2,
                              "Known noncommit retry failed")
        try expect(f.preferences.firstRunSetup?.failureReports == false, "Retry discarded opt-out")
    }
    check("PAT2667: stale injected generation refuses before store access") {
        let s = NFRStore(try nfrBytes()); let f = try NFRFixture(s, generation: "other-generation"); defer { f.cleanup() }
        f.controller.openPreferences(); try expect(nfrRefused(f.controller.saveChoices(complete: true)), "Wrong generation accepted")
        try expect(s.reads == 0 && s.writes == 0 && f.controller.firstRunSetup == nil, "Wrong generation I/O")
        try f.assertIdle()
    }
    check("PAT2667: welcome advance loads only; review advance requires accepted partial save") {
        let s = NFRStore(try nfrBytes()); let f = try NFRFixture(s); defer { f.cleanup() }
        f.controller.advance()
        try expect(f.controller.step == .review && f.opened.count == 1 && s.writes == 0, "Welcome performed more than explicit load")
        f.controller.edit(dailyChecks: false, notifications: false, failureReports: false); f.controller.advance()
        try expect(f.controller.step == .findApps && s.writes == 1 && f.preferences.firstRunSetup?.completed == false,
                   "Review did not save partial choices exactly once")
        try f.assertIdle()
    }
    check("PAT2667: refused review advance stays in review with editable unsaved choices") {
        let s = NFRStore(try nfrBytes()); let f = try NFRFixture(s); defer { f.cleanup() }; f.controller.advance()
        f.controller.edit(dailyChecks: false, notifications: false, failureReports: false); s.fault = .notCommitted; f.controller.advance()
        try expect(f.controller.step == .review && f.controller.isPresented && nfrDraft(f.controller) == [false, false, false] && f.controller.saveStatus == .unsaved,
                   "Refused review save advanced/reset")
        try f.assertIdle()
    }
    check("PAT2667: back navigation never loads saves scans or resets drafts") {
        let s = NFRStore(try nfrBytes()); let f = try NFRFixture(s); defer { f.cleanup() }; f.controller.advance(); f.controller.advance()
        f.controller.edit(dailyChecks: false, notifications: false, failureReports: false); let reads = s.reads, writes = s.writes
        f.controller.back(); try expect(f.controller.step == .review, "FindApps back")
        f.controller.back(); try expect(f.controller.step == .welcome, "Review back")
        f.controller.back(); try expect(f.controller.step == .welcome && nfrDraft(f.controller) == [false, false, false], "Welcome back reset")
        try expect(s.reads == reads && s.writes == writes, "Back persisted/reloaded"); try f.assertIdle()
    }
    check("PAT2667: already completed first explicit load opens Updates without save or scan") {
        let bytes = try nfrBytes(daily: false, notify: false, reports: false, complete: true)
        let s = NFRStore(bytes); let f = try NFRFixture(s); defer { f.cleanup() }; try f.assertOwners(); f.controller.advance()
        try expect(!f.controller.isPresented && f.navigation.destination == .updates && nfrDraft(f.controller) == [false, false, false], "Completed load ignored/opt-outs reset")
        try expect(s.writes == 0 && s.bytes == bytes && f.controller.firstRunSetup?.completed == true, "Completed load wrote")
        try f.assertIdle()
    }
    check("PAT2667: Find apps accepts complete save then scans SAME fixture owner once") {
        let s = NFRStore(try nfrBytes()); let f = try NFRFixture(s); defer { f.cleanup() }; f.controller.openPreferences()
        try f.assertOwners(); f.controller.findApps(); f.controller.findApps(); await f.applications.waitUntilIdle()
        try expect(s.writes == 1 && f.preferences.firstRunSetup?.completed == true && !f.controller.isPresented && f.navigation.destination == .updates,
                   "Find apps did not complete exactly one request")
        try expect(f.applications.observation?.provenance == .fixture && f.applications.observation?.generation == 1 && f.applications.observation?.applications.count == 1 && f.reads.count > 0,
                   "Find apps did not use singleflight real fixture scanner")
        try expect(f.provider.calls == 0 && f.applications.text.notice.contains("not been checked"), "Scan implied network/update availability")
    }
    check("PAT2667: Open Updates saves completion but never scans") {
        let s = NFRStore(try nfrBytes()); let f = try NFRFixture(s); defer { f.cleanup() }; f.controller.openPreferences(); try f.assertOwners()
        f.controller.openUpdates()
        try expect(s.writes == 1 && f.preferences.firstRunSetup?.completed == true && !f.controller.isPresented && f.navigation.destination == .updates, "Open Updates completion missing")
        try f.assertIdle()
    }
    check("PAT2667: unavailable preferences require separate explicit scan-without-saving action") {
        let s = NFRStore(); s.fault = .unavailableRead; let f = try NFRFixture(s); defer { f.cleanup() }; f.controller.openPreferences()
        try f.assertOwners(); f.controller.findApps(); f.controller.openUpdates(); await f.applications.waitUntilIdle()
        try expect(f.controller.isPresented && s.writes == 0, "Unavailable preferences permitted saved route"); try f.assertIdle()
        try f.assertOwners(); f.controller.scanWithoutSaving(); f.controller.scanWithoutSaving(); await f.applications.waitUntilIdle()
        try expect(!f.controller.isPresented && f.navigation.destination == .updates && s.writes == 0 && f.controller.firstRunSetup == nil && f.controller.saveStatus == .unsaved,
                   "Read-only bypass claimed completion or wrote")
        try expect(f.applications.observation?.provenance == .fixture && f.applications.observation?.generation == 1 && f.reads.count > 0 && f.provider.calls == 0,
                   "Read-only scan bypass did not use retained singleflight owner")
    }
    check("PAT2667: private physical store relaunch retains opt-outs only after explicit load") {
        let s = try NFRDiskStore(); defer { s.cleanup() }
        let first = try NFRFixture(s); defer { first.cleanup() }; first.controller.openPreferences()
        try expect(first.controller.createFreshPreferences() == .accepted(revision: 0), "Physical fresh fixture")
        first.controller.edit(dailyChecks: false, notifications: false, failureReports: false)
        try expect(first.controller.saveChoices(complete: true) == .accepted(revision: 1), "Physical choices save")
        let second = try NFRFixture(s); defer { second.cleanup() }; let writes = s.writes
        try expect(second.controller.firstRunSetup == nil && nfrDraft(second.controller) == [true, true, true], "Constructor claimed disk state")
        second.controller.openPreferences()
        try expect(second.controller.firstRunSetup?.completed == true && nfrDraft(second.controller) == [false, false, false] && s.writes == writes,
                   "Explicit relaunch load lost opt-outs or wrote")
        try second.assertIdle()
    }
    check("PAT2667: accepted projections follow the shared owner's block rather than a retained optimistic mirror") {
        let s = NFRStore(try nfrBytes()); let f = try NFRFixture(s); defer { f.cleanup() }; f.controller.openPreferences()
        try expect(f.controller.firstRunSetup != nil && f.controller.firstRunSetup == f.preferences.firstRunSetup, "Shared accepted setup was never projected")
        s.bytes = Data("corrupt".utf8); _ = f.preferences.reload(generation: nfrGeneration)
        try expect(f.preferences.firstRunSetup == nil && f.controller.firstRunSetup == nil, "Controller retained accepted mirror after owner block")
        try expect(nfrRefused(f.controller.saveChoices(complete: true)) && s.writes == 0 && f.controller.isPresented, "Owner block bypass")
    }
    check("PAT2667: accepted revision is a live projection of the original injected owner") {
        let s = NFRStore(try nfrBytes()); let f = try NFRFixture(s); defer { f.cleanup() }; f.controller.openPreferences()
        try expect(f.preferences.saveFirstRunChoices(FirstRunChoices(failureReports: false), complete: false,
            mutationID: "independent-owner-edit", expectedRevision: 0, generation: nfrGeneration) == .accepted(revision: 1), "Independent shared-owner edit")
        try expect(f.controller.acceptedRevision == 1 && f.controller.firstRunSetup == f.preferences.firstRunSetup,
                   "Controller retained an accepted-state mirror or replaced preference owner")
        try f.assertIdle()
    }
    check("PAT2667: controller source has no unsupported native capability or background effect adapters") {
        let text = code(try source("Sources/PatchedClient/NativeFirstRunController.swift"))
        for forbidden in ["URLSession", "URLRequest", "NWPathMonitor", "CFNetworkCopy", "SMAppService", "TCC", "AXIsProcessTrusted", "Process(", "Timer", ".refresh()", ".applyChoice()", "UserDefaults", "FileManager", "DispatchQueue", "AttentionObservation("] {
            try expect(!text.contains(forbidden), "First-run controller adds unsupported effect/capability: \(forbidden)")
        }
    }
    check("PAT2667: throwing acquisition has no accepted owner and paint navigation Back Network return never retry") {
        let s = NFRStore(try nfrBytes()); let f = try NFRFixture(s, openFailures: 1); defer { f.cleanup() }
        try f.assertOwners(); try nfrPaint(f)
        f.controller.edit(dailyChecks: false, notifications: false, failureReports: false)
        f.network.edit(mode: .manualHTTP, host: "kept.invalid", port: "")
        let revision = f.network.revision
        f.navigation.select(.updates); f.controller.back(); f.controller.showNetwork(); try nfrPaint(f); f.controller.returnFromNetwork()
        try expect(f.opened.count == 0 && s.reads == 0 && s.writes == 0, "Pre-load paint/navigation acquired preferences")
        f.controller.openPreferences()
        try expect(f.opened.count == 1 && s.reads == 0 && s.writes == 0, "Throwing acquisition touched store or retried")
        try expect(f.controller.acceptedRevision == nil && f.controller.firstRunSetup == nil && f.preferences.acceptedRevision == nil,
                   "Factory throw acquired an accepted owner")
        try expect(f.controller.localState == .unavailable && f.controller.saveStatus == .unavailable && f.controller.lastRefusal == .unavailable,
                   "Factory throw did not share unavailable acquisition state")
        try expect(nfrRefused(f.controller.createFreshPreferences()) && s.writes == 0, "Factory failure inferred missing/create authority")
        f.controller.back(); f.controller.showNetwork(); try nfrPaint(f); f.controller.returnFromNetwork()
        f.controller.dismiss(); f.controller.present(); _ = f.controller.statusText
        try expect(f.opened.count == 1 && s.reads == 0 && s.writes == 0 && f.controller.acceptedRevision == nil,
                   "Display/navigation implicitly retried factory")
        try expect(nfrDraft(f.controller) == [false, false, false] && f.network.mode == .manualHTTP &&
            f.network.host == "kept.invalid" && f.network.port == "" && f.network.revision == revision,
                   "Factory failure/navigation discarded unsaved declarations")
        try f.assertIdle()
    }
    check("PAT2667: explicit Reload recovers factory acquisition preserves drafts clears refusal and saves through original owner") {
        let s = NFRStore(try nfrBytes()); let f = try NFRFixture(s, openFailures: 1); defer { f.cleanup() }
        f.controller.edit(dailyChecks: false, notifications: false, failureReports: false)
        f.network.edit(mode: .manualHTTP, host: "kept.invalid", port: ""); let revision = f.network.revision
        f.controller.openPreferences()
        try expect(f.opened.count == 1 && s.reads == 0 && f.controller.lastRefusal == .unavailable,
                   "Recovery setup did not fail before owner acquisition")
        f.controller.openPreferences()
        try expect(f.opened.count == 2 && s.reads == 1 && s.writes == 0,
                   "Explicit Reload did not retry failed factory acquisition exactly once")
        try expect(f.controller.localState == .available && f.controller.acceptedRevision == 0 &&
            f.controller.acceptedRevision == f.preferences.acceptedRevision && f.controller.firstRunSetup == f.preferences.firstRunSetup,
                   "Recovery did not acquire original fixture owner revision0")
        try expect(f.controller.lastRefusal == nil && f.controller.saveStatus == .unsaved,
                   "Successful recovery retained obsolete acquisition refusal or claimed saved drafts")
        try expect(nfrDraft(f.controller) == [false, false, false] && f.network.mode == .manualHTTP &&
            f.network.host == "kept.invalid" && f.network.port == "" && f.network.revision == revision && f.network.choice == nil,
                   "Recovery replaced opt-outs or applied/overwrote incomplete Network draft")
        try f.assertIdle()
        let reads = s.reads
        f.controller.openPreferences()
        try expect(f.opened.count == 2 && s.reads == reads + 1 && s.writes == 0 && f.controller.acceptedRevision == 0,
                   "Further Reload reconstructed acquired owner")
        try expect(f.preferences.saveFirstRunChoices(FirstRunChoices(failureReports: true), complete: false,
            mutationID: "recovery-owner-edit", expectedRevision: 0, generation: nfrGeneration) == .accepted(revision: 1),
                   "Original shared owner unavailable after recovery")
        try expect(f.controller.acceptedRevision == 1 && f.controller.firstRunSetup == f.preferences.firstRunSetup,
                   "Recovery retained optimistic mirror or replaced original owner")
        let before = s.bytes, writes = s.writes
        try expect(f.controller.saveChoices(complete: true) == .accepted(revision: 2), "Recovered save used wrong accepted revision")
        try expect(s.writes == writes + 1 && s.expectedValues.last == before && f.controller.acceptedRevision == 2 &&
            f.controller.firstRunSetup == f.preferences.firstRunSetup && f.controller.saveStatus == .saved,
                   "Recovered save bypassed exact shared-owner CAS/readback")
        try expect(f.preferences.scheduleSettings?.dailyChecks == false && f.preferences.scheduleSettings?.notifications == false &&
            f.preferences.firstRunSetup == FirstRunSetupState(failureReports: false, completed: true,
                networkDraft: FirstRunNetworkDraft(mode: .manualHTTP, host: "kept.invalid", port: "")),
                   "Recovered save lost three false opt-outs or incomplete Network draft")
        try expect(f.controller.lastRefusal == nil && f.controller.statusText.contains("does not grant macOS permission") &&
            f.network.choice == nil && f.network.snapshot == nil && f.controller.isPresented,
                   "Completion granted permission, applied Network, or navigated implicitly")
        try f.assertOwners(); try f.assertIdle()
    }
    check("PAT2667: acquired owner survives later factory failure opportunity and Reload projects original owner") {
        let s = NFRStore(try nfrBytes()); let f = try NFRFixture(s); defer { f.cleanup() }
        f.controller.openPreferences(); f.opened.failuresRemaining = 1
        try expect(f.preferences.saveFirstRunChoices(FirstRunChoices(failureReports: false), complete: false,
            mutationID: "retained-owner-control", expectedRevision: 0, generation: nfrGeneration) == .accepted(revision: 1),
                   "Positive control could not mutate original owner")
        let reads = s.reads, writes = s.writes
        f.controller.openPreferences()
        try expect(f.opened.count == 1 && f.opened.failuresRemaining == 1 && s.reads == reads + 1 && s.writes == writes &&
            f.controller.localState == .available && f.controller.lastRefusal == nil,
                   "Successful owner was discarded/reacquired on Reload")
        try expect(f.controller.acceptedRevision == 1 && f.controller.firstRunSetup == f.preferences.firstRunSetup &&
            f.controller.failureReports == false, "Reload did not use original shared accepted owner")
        try f.assertOwners(); try f.assertIdle()
    }

    // PAT2667-NATIVE-002: these faults install real fixture bytes before refusing
    // acknowledgement. recover() removes only the read fault, never the record.
    for fault in [NFRStore.Fault.uncertain, .readback] {
        for edits in ["choices-only", "network-only", "combined"] {
            check("PAT2667: \(fault.rawValue) completed reload keeps \(edits) drafts reachable until explicit save") {
                let s = NFRStore(try nfrBytes()); let f = try NFRFixture(s); defer { f.cleanup() }
                try f.assertOwners(); f.controller.advance(); f.controller.advance()
                try expect(f.controller.step == .findApps && s.writes == 1 && f.preferences.acceptedRevision == 1 &&
                    f.preferences.firstRunSetup?.completed == false, "Dirty completed Reload setup did not reach saved partial choices")
                let beforeCompletion = s.bytes
                s.fault = fault; f.controller.openUpdates()
                let refusal: PreferenceRefusal = fault == .uncertain ? .uncertain : .readback
                try expect(s.writes == 2 && s.expectedValues.count == 2 && s.expectedValues[1] == beforeCompletion &&
                    s.proposals.count == 2 && s.bytes == s.proposals[1] && s.bytes != beforeCompletion,
                    "Completion fault did not physically install its exact CAS proposal")
                guard let physical = s.bytes,
                      let envelope = try JSONSerialization.jsonObject(with: physical) as? [String: Any],
                      let setup = envelope["setup"] as? [String: Any] else {
                    throw CheckFailure(description: "Completion fault left no literal physical setup")
                }
                try expect(setup["completed"] as? Bool == true && setup["failureReports"] as? Bool == true &&
                    (try nfrReceipts(s.bytes)).last?["complete"] as? Bool == true,
                    "Fault fixture did not persist completed=true before refusing")
                try expect(f.controller.isPresented && f.controller.lastRefusal == refusal &&
                    f.preferences.blockedReason == refusal && f.preferences.acceptedRevision == 1 &&
                    f.controller.firstRunSetup == nil && f.preferences.firstRunSetup == nil &&
                    f.controller.saveStatus == .unsaved && f.navigation.destination == .applications,
                    "Unacknowledged physical completion escaped its original owner latch")
                try f.assertIdle()
                // Mutate only the named axis after failure, while the old completed
                // record remains physically installed with all three choices true.
                f.controller.back()
                let changeChoices = edits != "network-only", changeNetwork = edits != "choices-only"
                if changeChoices {
                    f.controller.edit(dailyChecks: false, notifications: false, failureReports: false)
                }
                if changeNetwork {
                    f.controller.showNetwork()
                    f.network.edit(mode: .manualHTTP, host: "edited-after-failure.invalid", port: "")
                }
                let expectedChoices = changeChoices ? [false, false, false] : [true, true, true]
                let expectedNetwork = changeNetwork
                    ? FirstRunNetworkDraft(mode: .manualHTTP, host: "edited-after-failure.invalid", port: "")
                    : FirstRunNetworkDraft()
                let revision = f.network.revision
                let destination = f.navigation.destination, section = f.navigation.settingsSection
                let reads = s.reads, writes = s.writes, proposals = s.proposals, expectedValues = s.expectedValues
                s.recover()
                try expect(nfrRefused(f.controller.saveChoices(complete: true)) &&
                    s.reads == reads && s.writes == writes && s.bytes == physical,
                    "Recovery silently retried a latched completion before explicit Reload")
                f.controller.openPreferences()
                try f.assertOwners(); try f.assertIdle()
                try expect(f.opened.count == 1 && s.reads == reads + 1 && s.writes == writes &&
                    s.bytes == physical && s.proposals == proposals && s.expectedValues == expectedValues,
                    "Dirty completed Reload wrote, retried, reacquired or changed physical bytes")
                try expect(f.controller.acceptedRevision == 2 && f.preferences.acceptedRevision == 2 &&
                    f.controller.firstRunSetup == f.preferences.firstRunSetup && f.preferences.firstRunSetup?.completed == true &&
                    f.preferences.firstRunSetup?.failureReports == true &&
                    f.preferences.scheduleSettings?.dailyChecks == true && f.preferences.scheduleSettings?.notifications == true &&
                    f.preferences.firstRunSetup?.networkDraft == FirstRunNetworkDraft() &&
                    f.preferences.blockedReason == nil && f.controller.lastRefusal == nil &&
                    f.controller.localState == .available && f.controller.saveStatus == .unsaved &&
                    f.controller.statusText.lowercased().contains("unsaved"),
                    "Reload did not clear refusal through the original owner while retaining unsaved status")
                try expect(nfrDraft(f.controller) == expectedChoices && f.network.revision == revision &&
                    f.network.mode == (changeNetwork ? .manualHTTP : .system) &&
                    f.network.host == expectedNetwork.host && f.network.port == expectedNetwork.port &&
                    f.network.choice == nil && f.network.snapshot == nil && !f.network.isRefreshing,
                    "Completed Reload overwrote edited opt-outs or incomplete Network draft")
                // First expected RED: current finishPresentation hides these controls
                // and selects Updates merely because the physical record is complete.
                try expect(f.controller.isPresented && f.controller.step == .review &&
                    f.controller.networkPresented == changeNetwork && f.navigation.destination == destination &&
                    f.navigation.settingsSection == section,
                    "Dirty completed Reload hid setup or moved its unsaved controls")
                try nfrPaint(f)
                try expect(s.reads == reads + 1 && s.writes == writes && s.bytes == physical &&
                    f.network.revision == revision, "Recovery paint persisted or altered retained drafts")
                if changeNetwork { f.controller.returnFromNetwork() }
                try expect(f.controller.isPresented && !f.controller.networkPresented && f.controller.step == .review &&
                    nfrDraft(f.controller) == expectedChoices, "Unsaved review controls are not reachable")
                // Use the existing visible review Continue, then completion control.
                // No present() or direct owner save may rescue a hidden setup here.
                let beforeSave = s.bytes, beforeSaveReads = s.reads
                f.controller.advance()
                try expect(s.writes == writes + 1 && s.reads == beforeSaveReads + 1 &&
                    s.expectedValues.last == beforeSave && f.preferences.acceptedRevision == 3 &&
                    f.controller.acceptedRevision == 3 && f.controller.saveStatus == .saved &&
                    f.controller.lastRefusal == nil && f.controller.isPresented && f.controller.step == .findApps,
                    "Explicit review save did not persist via the retained owner's exact CAS/readback before exit")
                let savedSetup = FirstRunSetupState(failureReports: !changeChoices, completed: true,
                    networkDraft: expectedNetwork)
                try expect(f.preferences.scheduleSettings?.dailyChecks == !changeChoices &&
                    f.preferences.scheduleSettings?.notifications == !changeChoices &&
                    f.preferences.firstRunSetup == savedSetup && f.controller.firstRunSetup == savedSetup,
                    "Explicit review save lost edited declarations or regressed physical completion")
                let savedBytes = s.bytes, beforeExitReads = s.reads
                try f.assertOwners(); f.controller.openUpdates()
                try expect(s.writes == writes + 2 && s.reads == beforeExitReads + 1 &&
                    s.expectedValues.last == savedBytes && f.preferences.acceptedRevision == 4 &&
                    f.controller.acceptedRevision == 4 && f.preferences.firstRunSetup == savedSetup &&
                    !f.controller.isPresented && !f.controller.networkPresented && f.navigation.destination == .updates &&
                    f.controller.saveStatus == .saved && f.controller.lastRefusal == nil,
                    "Explicit completion did not save the edited values before opening Updates")
                let receipts = try nfrReceipts(s.bytes)
                let ids = receipts.compactMap { $0["id"] as? String }
                try expect(receipts.count == 4 && ids.count == 4 && Set(ids).count == 4 &&
                    receipts[2]["complete"] as? Bool == false && receipts[3]["complete"] as? Bool == true,
                    "Recovery saves reused a receipt or omitted explicit partial/completion requests")
                try f.assertOwners(); try f.assertIdle()
                try expect(f.opened.count == 1 && f.network.revision == revision &&
                    f.network.choice == nil && f.network.snapshot == nil && !f.network.isRefreshing,
                    "Recovery replaced owner or applied/observed Network")
            }
        }
    }
    check("PAT2667: clean completed explicit reload retains fast exit through the original owner without extra effects") {
        let s = NFRStore(try nfrBytes()); let f = try NFRFixture(s); defer { f.cleanup() }
        try f.assertOwners(); f.controller.advance()
        // Change the already retained owner, leaving controller drafts clean.
        let completed = FirstRunChoices(dailyChecks: false, notifications: false, failureReports: false,
            networkDraft: FirstRunNetworkDraft(mode: .manualHTTP, host: "clean-saved.invalid", port: "8080"))
        try expect(f.preferences.saveFirstRunChoices(completed, complete: true,
            mutationID: "clean-completed-reload-control", expectedRevision: 0, generation: nfrGeneration) == .accepted(revision: 1),
            "Clean control could not persist completion through original shared owner")
        try expect(f.controller.isPresented && f.controller.step == .review && f.controller.lastRefusal == nil,
            "Clean control exited before explicit Reload")
        let bytes = s.bytes, reads = s.reads, writes = s.writes
        let proposals = s.proposals, expectedValues = s.expectedValues
        f.controller.openPreferences()
        try expect(!f.controller.isPresented && !f.controller.networkPresented && f.navigation.destination == .updates &&
            f.controller.saveStatus == .loaded && f.controller.lastRefusal == nil &&
            f.controller.acceptedRevision == 1 && f.controller.firstRunSetup == f.preferences.firstRunSetup,
            "Clean completed Reload lost its fast exit or original accepted owner")
        try expect(nfrDraft(f.controller) == [false, false, false] && f.network.mode == .manualHTTP &&
            f.network.host == "clean-saved.invalid" && f.network.port == "8080" &&
            f.network.choice == nil && f.network.snapshot == nil && !f.network.isRefreshing,
            "Clean completed Reload failed to restore saved declarations without applying Network")
        try expect(f.opened.count == 1 && s.reads == reads + 1 && s.writes == writes && s.bytes == bytes &&
            s.proposals == proposals && s.expectedValues == expectedValues,
            "Clean completed Reload wrote or reacquired preferences")
        try f.assertOwners(); try f.assertIdle()
    }
}
