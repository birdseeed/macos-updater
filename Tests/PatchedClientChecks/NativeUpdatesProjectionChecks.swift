import Foundation
import Darwin
@_spi(Testing) import PatchedClient

// These independent checks use actual inert directories in this executable's
// physical .build. The observer reports read boundaries, never inventory values.
private struct UpdatesFixture {
    let base: URL
    let root: URL
    init() throws {
        base = try newDirectory("pat2661-native-projection")
        root = base.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    func clean() { try? FileManager.default.removeItem(at: base) }
    @discardableResult func app(_ name: String, version: String = "6.2", build: Any = "17", metadata: Bool = true) throws -> URL {
        let bundle = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        if metadata {
            let claims: [String: Any] = ["CFBundleDisplayName": "Literal <Copy>", "CFBundleIdentifier": "example.duplicate", "CFBundleShortVersionString": version, "CFBundleVersion": build]
            try PropertyListSerialization.data(fromPropertyList: claims, format: .xml, options: 0)
                .write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        }
        return bundle
    }
    @MainActor func controller(_ probe: UpdatesProbe? = nil, roots: [String]? = nil) -> LocalApplicationsController {
        let inventory: LocalApplicationInventory
        if let probe {
            inventory = LocalApplicationInventory(fixtureRoots: roots ?? [root.path], observer: { event in probe.read(event) })
        } else {
            inventory = LocalApplicationInventory(fixtureRoots: roots ?? [root.path])
        }
        return LocalApplicationsController(inventory: inventory)
    }
}

private final class UpdatesProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0, holds = 0
    private var holdNext = false, expired = false
    private let release = DispatchSemaphore(value: 0)
    var count: Int { lock.lock(); defer { lock.unlock() }; return reads }
    var blockedCount: Int { lock.lock(); defer { lock.unlock() }; return holds }
    var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return expired }
    func arm() { lock.lock(); holdNext = true; lock.unlock() }
    func open() { release.signal() }
    func read(_ event: LocalInventoryReadEvent) {
        lock.lock(); reads += 1; let hold = holdNext; holdNext = false
        if hold { holds += 1 }; lock.unlock()
        if hold && release.wait(timeout: .now() + 8) == .timedOut {
            lock.lock(); expired = true; lock.unlock()
        }
    }
}

@MainActor private func updatesScan(_ c: LocalApplicationsController) async throws -> LocalInventoryObservation {
    c.scan(); await c.waitUntilIdle()
    guard let result = c.observation else { throw CheckFailure(description: "Explicit scanner did not publish an observation") }
    try expect(c.phase == .finished, "Explicit scanner did not finish")
    return result
}
@MainActor private func updatesSafety(_ c: LocalApplicationsController, expectedUnknown: Int) throws {
    try expect(c.readyForUpdateCount == 0, "Read-only inventory invented ready updates")
    try expect(!c.allVerifiedUpToDate, "Unchecked inventory asserted all verified up to date")
    try expect(c.unknownUpdateCount == expectedUnknown, "Observed copies must all remain unknown: expected \(expectedUnknown), got \(c.unknownUpdateCount)")
    try expect(c.updatesText.notice == "Update availability has not been checked.", "Updates lacks the honest availability notice")
    if let observation = c.observation {
        try expect(observation.authorityUnknown && !observation.installationAllowed, "Observation grants installation authority")
        try expect(observation.applications.allSatisfy { $0.authorityUnknown && !$0.installationAllowed }, "Observed row grants authority")
    }
}
@MainActor private func updatesShare(_ c: LocalApplicationsController) throws {
    let a = c.text, u = c.updatesText
    try expect(u.rows == a.rows, "Updates changed, filtered or copied stale application rows")
    try expect(u.observedAt == a.observedAt && u.provenance == a.provenance, "Screens disagree on observation time or provenance")
    try expect(u.roots == a.roots && u.issues == a.issues, "Updates lost root coverage or observation issues")
    try expect(u.status == a.status && u.scanTitle == a.scanTitle && u.scanEnabled == a.scanEnabled, "Screens disagree on scanner state or explicit scan availability")
}

@MainActor func registerNativeUpdatesProjectionChecks() {
    check("native updates projection: idle reads are inert and Updates has its own heading") {
        let f = try UpdatesFixture(); defer { f.clean() }; try f.app("Unopened.app")
        let p = UpdatesProbe(), c = f.controller(p)
        for _ in 0..<20 { _ = c.updatesText; _ = c.text; _ = c.unknownUpdateCount; _ = c.readyForUpdateCount; _ = c.allVerifiedUpToDate }
        try expect(p.count == 0 && c.phase == .idle && c.observation == nil, "Reading a presentation started filesystem work")
        try expect(c.updatesText.rows.isEmpty && c.updatesText.observedAt == nil && c.updatesText.scanEnabled, "Idle projection invented an observation")
        try updatesSafety(c, expectedUnknown: 0); try updatesShare(c)
        try expect(c.text.heading == "Applications" && c.updatesText.heading == "Updates", "Updates heading is not distinct from Applications")
    }
    check("native updates projection: explicit scan shares literal duplicate rows and one immutable observation") {
        let f = try UpdatesFixture(); defer { f.clean() }
        let first = try f.app("First.app", version: "9.01"), second = try f.app("Second.app", version: "1.000")
        let p = UpdatesProbe(), c = f.controller(p), r = try await updatesScan(c)
        try expect(r.provenance == .fixture && r.generation == 1 && r.applications.count == 2 && p.count == 2, "Real fixture scanner did not read two physical copies once")
        let text = c.updatesText
        try expect(text.rows.map(\.location) == [first.path, second.path] && text.rows.map(\.name) == ["Literal <Copy>", "Literal <Copy>"], "Updates collapsed copies or interpreted literal names")
        try expect(text.rows.map(\.version) == ["Claimed version: 9.01", "Claimed version: 1.000"] && text.rows.allSatisfy { $0.build == "Claimed build: 17" && $0.metadata == "Observed metadata; claims unverified." }, "Updates changed literal unverified claims")
        try expect(text.provenance == "Fixture observation: test folders only." && text.observedAt != nil, "Fixture origin/time disappeared")
        for _ in 0..<20 { _ = c.updatesText; _ = c.text; _ = c.unknownUpdateCount }
        try expect(c.observation == r && p.count == 2, "Projection read republished or rescanned the inventory")
        try updatesShare(c); try updatesSafety(c, expectedUnknown: 2)
    }
    check("native updates projection: single flight retains old generation while scanning and refreshes both screens") {
        let f = try UpdatesFixture(); defer { f.clean() }; try f.app("First.app")
        let p = UpdatesProbe(), c = f.controller(p), old = try await updatesScan(c)
        let oldText = c.updatesText
        try f.app("Second.app", version: "8.8")
        p.arm(); c.scan(); defer { p.open() }
        do {
            try await until("bounded projection scanner read") { p.blockedCount == 1 }
            c.scan(); c.scan()
            try expect(c.phase == .scanning && !c.updatesText.scanEnabled && c.updatesText.scanTitle == "Scanning…", "Projection does not show in-flight scanner state")
            // PAT-2731 adds phase-dependent freshness; retain every immutable row claim
            // while independently requiring stale details for this held real scan.
            let inFlightText = c.updatesText
            try expect(c.observation == old && inFlightText.observedAt == oldText.observedAt &&
                       inFlightText.rows.count == oldText.rows.count, "In-flight projection lost the previous observation")
            for (row, previous) in zip(inFlightText.rows, oldText.rows) {
                try expect(row.name == previous.name && row.version == previous.version &&
                           row.build == previous.build && row.location == previous.location &&
                           row.metadata == previous.metadata, "In-flight projection changed a physical copy or claimed row field")
                let fresh = previous.provenance.lines.filter { $0.hasPrefix("Evidence freshness:") }
                let stale = row.provenance.lines.filter { $0.hasPrefix("Evidence freshness:") }
                try expect(fresh.count == 1 && fresh[0].contains("point-in-time") && !fresh[0].contains("stale") &&
                           stale.count == 1 && stale[0].contains("stale") && stale[0].contains("previous observation"),
                           "In-flight provenance did not distinguish stale evidence from the immutable previous snapshot")
                try expect(row.provenance.lines.count == previous.provenance.lines.count &&
                           row.provenance.lines.filter { !$0.hasPrefix("Evidence freshness:") } ==
                           previous.provenance.lines.filter { !$0.hasPrefix("Evidence freshness:") },
                           "In-flight provenance changed source, installed claims, candidate or verification evidence")
                try expect(!previous.provenance.disclosureID.isEmpty && !row.provenance.disclosureID.isEmpty &&
                           row.provenance.disclosureID != previous.provenance.disclosureID,
                           "Scanning phase retained the previous disclosure identity")
            }
            try expect(c.updatesText.rows == inFlightText.rows && oldText.rows.allSatisfy {
                $0.provenance.lines.filter { $0.hasPrefix("Evidence freshness:") }.allSatisfy {
                    $0.contains("point-in-time") && !$0.contains("stale")
                }
            }, "Repeated in-flight reads changed details or mutated the previous point-in-time snapshot")
            try expect(c.updatesText.status.contains("Previous observation"), "Stale visible observation is not labelled during refresh")
            try updatesShare(c); try updatesSafety(c, expectedUnknown: 1)
            let reads = p.count
            for _ in 0..<20 { _ = c.updatesText; _ = c.text }
            try expect(p.count == reads, "Reading in-flight projections started another scan")
        } catch {
            // Even discriminating RED must join its held scanner before fixture cleanup.
            p.open(); await c.waitUntilIdle(); throw error
        }
        p.open(); await c.waitUntilIdle()
        guard let current = c.observation else { throw CheckFailure(description: "Refresh lost observation") }
        try expect(current.sessionID == old.sessionID && current.generation == old.generation + 1 && current.startedAt >= old.finishedAt && current.finishedAt >= current.startedAt, "Refresh used a competing scanner/session or invalid generation/time")
        try expect(current.applications.count == 2 && p.count == 3 && !p.timedOut, "Single flight duplicated scans or did not refresh both copies")
        try expect(c.updatesText.rows.count == 2 && c.updatesText.scanEnabled && c.updatesText.scanTitle == "Scan again", "Finished projection did not expose refreshed rows")
        try updatesShare(c); try updatesSafety(c, expectedUnknown: 2)
        try expect(old.applications.count == 1 && oldText.rows.count == 1, "Prior immutable observation changed")
    }
    check("native updates projection: empty scanned folder never means verified up to date") {
        let f = try UpdatesFixture(); defer { f.clean() }; let c = f.controller(), r = try await updatesScan(c)
        try expect(r.applications.isEmpty && r.roots.count == 1 && r.roots[0].status == .scanned && r.completeness == .complete, "Empty control did not scan an actual empty root")
        try expect(c.updatesText.status == "No applications found in the scanned folders.", "Empty projection overstates the observation")
        try updatesShare(c); try updatesSafety(c, expectedUnknown: 0)
    }
    check("native updates projection: unavailable roots and partial coverage retain exact explanations") {
        let f = try UpdatesFixture(); defer { f.clean() }; try f.app("Visible.app")
        let absent = f.base.appendingPathComponent("Absent").path
        let c = f.controller(roots: [f.root.path, "", absent]), r = try await updatesScan(c)
        try expect(r.roots.map(\.status) == [.scanned, .unavailable, .absent] && r.completeness == .incomplete && r.issues.contains { $0.kind == .unavailable }, "Partial control did not preserve unavailable/absent coverage")
        try expect(c.updatesText.status.contains("incomplete") && c.updatesText.roots.contains { $0.contains("Path unavailable") } && !c.updatesText.issues.isEmpty, "Updates hid incomplete coverage")
        try updatesShare(c); try updatesSafety(c, expectedUnknown: 1)
        let none = f.controller(roots: [""]), unavailable = try await updatesScan(none)
        try expect(unavailable.applications.isEmpty && unavailable.roots[0].status == .unavailable && !none.updatesText.issues.isEmpty, "Unavailable-only control fabricated rows or hid errors")
        try updatesShare(none); try updatesSafety(none, expectedUnknown: 0)
    }
    check("native updates projection: malformed and missing metadata keep safe literal claims unverified") {
        let f = try UpdatesFixture(); defer { f.clean() }
        let malformed = try f.app("Malformed.app", version: "7.000", build: 42)
        let missing = try f.app("Missing.app", metadata: false)
        let c = f.controller(), r = try await updatesScan(c)
        try expect(r.completeness == .incomplete && r.applications.count == 2 && r.issues.contains { $0.kind == .malformedMetadata } && r.issues.contains { $0.kind == .metadataUnavailable }, "Malformed/absent metadata control did not exercise both issues")
        let rows = c.updatesText.rows
        try expect(rows[0].location == malformed.path && rows[0].version == "Claimed version: 7.000" && rows[0].build == "Claimed build: unavailable" && rows[0].metadata == "Some metadata is malformed; displayed claims remain unverified.", "Malformed metadata lost safe claims or declared them verified")
        try expect(rows[1].location == missing.path && rows[1].version == "Claimed version: unavailable" && rows[1].metadata.contains("unverified"), "Missing metadata invented a version or verification")
        try updatesShare(c); try updatesSafety(c, expectedUnknown: 2)
    }
    check("native updates projection: changed namespace remains incomplete with no accepted replacement claims") {
        let f = try UpdatesFixture(); defer { f.clean() }; let app = try f.app("Changed.app")
        let plist = app.appendingPathComponent("Contents/Info.plist"), saved = f.base.appendingPathComponent("Saved.plist")
        let inventory = LocalApplicationInventory(fixtureRoots: [f.root.path], observer: { _ in
            do { try FileManager.default.moveItem(at: plist, to: saved); try Data("replacement".utf8).write(to: plist) }
            catch { /* Physical saved file and scanner issue asserted below. */ }
        })
        let c = LocalApplicationsController(inventory: inventory), r = try await updatesScan(c)
        try expect(FileManager.default.fileExists(atPath: saved.path) && r.issues.contains { $0.kind == .changedDuringScan } && r.completeness == .incomplete, "Changed-namespace control did not reach the captured real read boundary")
        try expect(r.applications.count == 1 && r.applications[0].claimedShortVersion == nil && r.applications[0].metadataDisposition == .refused, "Changed metadata supplied accepted claims")
        try expect(c.updatesText.rows[0].version == "Claimed version: unavailable" && c.updatesText.rows[0].metadata.contains("unverified") && c.updatesText.issues.contains { $0.contains("changed during the scan") }, "Updates concealed the change or invented authority")
        try updatesShare(c); try updatesSafety(c, expectedUnknown: 1)
    }
}
