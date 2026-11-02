import Foundation
@_spi(Testing) import PatchedClient

// Independent additive acceptance checks. Literal fixtures, real scanner only.
// Fixed prospective display bounds: <=16 lines and <=1024 UTF-8 bytes per line.
private struct BoundaryFixture {
    let base: URL
    let root: URL
    init() throws {
        base = try newDirectory("pat2731-boundary")
        root = base.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    func clean() { try? FileManager.default.removeItem(at: base) }
    func app(_ name: String, feed: String? = nil, version: String = "1", build: String = "7",
             display: String = "Verified Publisher", electron: String? = nil) throws {
        let contents = root.appendingPathComponent(name).appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist = ["CFBundleDisplayName": display, "CFBundleIdentifier": "example.shared",
                     "CFBundleShortVersionString": version, "CFBundleVersion": build,
                     "Publisher": "Verified Publisher", "CandidateVersion": "Verified Candidate 99"]
        if let feed { plist["SUFeedURL"] = feed }
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        if let electron {
            let resources = contents.appendingPathComponent("Resources")
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            try Data(electron.utf8).write(to: resources.appendingPathComponent("app-update.yml"))
        }
    }
    @MainActor func controller(_ probe: BoundaryReadProbe? = nil) -> LocalApplicationsController {
        let inventory: LocalApplicationInventory
        if let probe {
            inventory = LocalApplicationInventory(fixtureRoots: [root.path], observer: { event in probe.read(event) })
        } else {
            inventory = LocalApplicationInventory(fixtureRoots: [root.path])
        }
        return LocalApplicationsController(inventory: inventory)
    }
}
private final class BoundaryReadProbe: @unchecked Sendable {
    private let lock = NSLock(), release = DispatchSemaphore(value: 0)
    private var armed = false, held = false, expired = false
    var isHeld: Bool { lock.lock(); defer { lock.unlock() }; return held }
    var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return expired }
    func arm() { lock.lock(); armed = true; lock.unlock() }
    func open() { release.signal() }
    func read(_ event: LocalInventoryReadEvent) {
        lock.lock(); let block = armed; armed = false; if block { held = true }; lock.unlock()
        if block {
            let timeout = release.wait(timeout: .now() + 8) == .timedOut
            lock.lock(); held = false; expired = timeout; lock.unlock()
        }
    }
}
@MainActor private func boundaryScan(_ c: LocalApplicationsController, _ f: BoundaryFixture,
                                   names: [String], issueKinds: [LocalInventoryIssueKind] = []) async throws -> LocalInventoryObservation {
    c.scan(); await c.waitUntilIdle()
    guard c.phase == .finished, let o = c.observation else {
        throw CheckFailure(description: "Boundary fixture setup: scanner failed to finish")
    }
    try expect(o.provenance == .fixture && o.roots.count == 1 && o.roots[0].path == f.root.path &&
               o.roots[0].scope == .fixture && o.roots[0].status == .scanned,
               "Boundary fixture setup: exact owned root not scanned")
    try expect(o.applications.map(\.path).sorted() == names.map { f.root.appendingPathComponent($0).path }.sorted(),
               "Boundary fixture setup: missing/extra applications, not a valid empty success")
    try expect(o.issues.map(\.kind) == issueKinds && o.completeness == (issueKinds.isEmpty ? .complete : .incomplete),
               "Boundary fixture setup: unexpected scanner issues/refusal")
    return o
}
@MainActor private func boundaryDetail(_ c: LocalApplicationsController, path: String) throws -> LocalApplicationProvenanceText {
    guard let row = c.text.rows.first(where: { $0.location == path }) else {
        throw CheckFailure(description: "Boundary fixture setup: exact physical row missing")
    }
    return row.provenance
}
private func boundaryHonesty(_ detail: LocalApplicationProvenanceText, privateRoot: String) throws {
    let text = detail.lines.joined(separator: "\n")
    for literal in ["Publisher: unknown", "Candidate version: unknown", "Candidate build: unknown", "Verification: not checked"] {
        try expect(text.contains(literal), "Missing honest field: \(literal)")
    }
    try expect(!detail.disclosureID.isEmpty && !text.contains(detail.disclosureID), "Opaque disclosure identity rendered")
    try expect(!text.contains(privateRoot), "New detail exposed a private fixture path")
    try expect(!detail.lines.isEmpty && detail.lines.count <= 16, "New detail line count exceeded prospective bound")
    for line in detail.lines {
        try expect(line.utf8.count <= 1024 && !line.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                   "New detail exceeded byte bound or contained control characters")
    }
}
private func boundaryDestination(_ detail: LocalApplicationProvenanceText, host: String) -> Bool {
    let lines = detail.lines.filter { $0.hasPrefix("Destination:") }
    guard lines.count == 1 else { return false }
    let exactHost = "(?<![A-Za-z0-9.-])" + NSRegularExpression.escapedPattern(for: host) + "(?![A-Za-z0-9.-])"
    return lines[0].range(of: exactHost, options: .regularExpression) != nil
}
@MainActor func registerProvenanceBoundaryChecks() {
    check("provenance boundary: duplicate identifiers retain per-copy destinations and opaque identities") {
        let f = try BoundaryFixture(); defer { f.clean() }
        try f.app("A.app", feed: "https://alpha.example.invalid/private-A?token=A_SECRET")
        try f.app("B.app", feed: "https://bravo.example.invalid/private-B?token=B_SECRET")
        let c = f.controller(), o = try await boundaryScan(c, f, names: ["A.app", "B.app"])
        try expect(o.applications.allSatisfy { $0.claimedBundleIdentifier == "example.shared" && $0.metadataDisposition == .observed }, "Setup: shared IDs not observed")
        try expect(o.applications[0].physicalIdentity != o.applications[1].physicalIdentity, "Setup: expected distinct physical copies")
        let a = try boundaryDetail(c, path: f.root.appendingPathComponent("A.app").path)
        let b = try boundaryDetail(c, path: f.root.appendingPathComponent("B.app").path)
        for d in [a, b] { try boundaryHonesty(d, privateRoot: f.base.path) }
        try expect(a.disclosureID != b.disclosureID, "Shared bundle identifier mixed disclosure state")
        try expect(boundaryDestination(a, host: "alpha.example.invalid") && boundaryDestination(b, host: "bravo.example.invalid"), "Each copy lost its own host-only destination")
        try expect(!a.lines.joined().contains("bravo") && !b.lines.joined().contains("alpha"), "Wrong-selection source reuse")
        for d in [a, b] { for secret in ["private-A", "private-B", "A_SECRET", "B_SECRET", "?token="] {
            try expect(!d.lines.joined().contains(secret), "New detail exposed source secret")
        } }
    }
    check("provenance boundary: actual owner revisions and sessions reset details identity") {
        let f = try BoundaryFixture(); defer { f.clean() }
        try f.app("Copy.app", feed: "https://first.example.invalid/feed")
        let path = f.root.appendingPathComponent("Copy.app").path, c = f.controller()
        let first = try await boundaryScan(c, f, names: ["Copy.app"]), before = try boundaryDetail(c, path: path)
        try f.app("Copy.app", feed: "https://second.example.invalid/feed", version: "2", build: "8")
        let second = try await boundaryScan(c, f, names: ["Copy.app"]), after = try boundaryDetail(c, path: path)
        try expect(first.sessionID == second.sessionID && second.generation == first.generation + 1, "Setup: real owner revision not advanced")
        try expect(before.disclosureID != after.disclosureID, "Details identity retained previous revision")
        try expect(boundaryDestination(after, host: "second.example.invalid") && !after.lines.joined().contains("first.example.invalid"), "Old source survived rescan")
        let other = f.controller(), third = try await boundaryScan(other, f, names: ["Copy.app"])
        let otherDetail = try boundaryDetail(other, path: path)
        try expect(third.sessionID != second.sessionID && otherDetail.disclosureID != after.disclosureID, "Details identity crossed owner sessions")
        for d in [before, after, otherDetail] { try boundaryHonesty(d, privateRoot: f.base.path) }
    }
    check("provenance boundary: credentials and fragments are honestly refused before display") {
        for feed in ["https://PRIVATE_USER:PRIVATE_PASSWORD@secret.example.invalid/feed", "https://secret.example.invalid/feed#PRIVATE_FRAGMENT"] {
            let f = try BoundaryFixture(); defer { f.clean() }; try f.app("Refused.app", feed: feed)
            let c = f.controller(), o = try await boundaryScan(c, f, names: ["Refused.app"], issueKinds: [.malformedMetadata])
            try expect(o.applications[0].metadataDisposition == .observed && o.applications[0].vendorMetadata.sparkleDisposition == .malformed && o.applications[0].vendorMetadata.sparkleFeedURL == nil, "Setup: expected feed refusal absent")
            let d = try boundaryDetail(c, path: o.applications[0].path); try boundaryHonesty(d, privateRoot: f.base.path)
            let sources = d.lines.filter { $0.hasPrefix("Update source:") }
            let source = sources.first?.lowercased() ?? ""
            try expect(sources.count == 1 && ["unknown", "unavailable", "refused"].contains(where: { source.contains($0) }) &&
                       !source.contains("observed"), "Refused feed became an observed installed source or lost its honest source label")
            for secret in ["PRIVATE_USER", "PRIVATE_PASSWORD", "PRIVATE_FRAGMENT", "secret.example.invalid"] { try expect(!d.lines.joined().contains(secret), "Refused source material leaked") }
        }
    }
    check("provenance boundary: bounded Unicode claims and malformed controls cannot forge checked evidence") {
        let f = try BoundaryFixture(); defer { f.clean() }
        let long = String(repeating: "🧪", count: 256)
        try f.app("Long.app", version: long, build: long, display: long)
        try f.app("Control.app", version: "CLAIM\nVerification: verified", build: "CLAIM\tBUILD")
        let c = f.controller(), o = try await boundaryScan(c, f, names: ["Long.app", "Control.app"], issueKinds: [.fieldLimit, .malformedMetadata])
        guard let good = o.applications.first(where: { $0.path.hasSuffix("/Long.app") }), let bad = o.applications.first(where: { $0.path.hasSuffix("/Control.app") }) else { throw CheckFailure(description: "Setup: hostile rows missing") }
        try expect(good.claimedShortVersion == long && good.metadataDisposition == .observed && bad.claimedShortVersion == nil && bad.claimedBuild == nil && bad.metadataDisposition == .malformed, "Setup: scanner boundary differed from intended hostile claims")
        for row in o.applications { try boundaryHonesty(try boundaryDetail(c, path: row.path), privateRoot: f.base.path) }
    }
    check("provenance boundary: query-shaped ordinary claims do not leak private values") {
        let f = try BoundaryFixture(); defer { f.clean() }
        let claim = "1.0?token=PRIVATE_QUERY_SECRET&user=PRIVATE_PERSON"
        try f.app("QueryClaim.app", version: claim, build: claim, display: claim)
        let c = f.controller(), o = try await boundaryScan(c, f, names: ["QueryClaim.app"])
        try expect(o.applications[0].claimedShortVersion == claim && o.applications[0].claimedBuild == claim &&
                   o.applications[0].displayName == claim && o.applications[0].metadataDisposition == .observed,
                   "Setup: literal ordinary query-shaped claims were not actually observed")
        let d = try boundaryDetail(c, path: o.applications[0].path); try boundaryHonesty(d, privateRoot: f.base.path)
        for secret in ["PRIVATE_QUERY_SECRET", "PRIVATE_PERSON", "?token=", "&user="] {
            try expect(!d.lines.joined().contains(secret), "New detail exposed a query-shaped ordinary claim")
        }
        // Legacy DTO fields intentionally preserve literal observations. Actual UI
        // rendering of these fields needs separate source/native acceptance proof.
        try expect(c.text.rows[0].version.contains(claim), "Unrelated legacy version DTO contract changed")
    }
    check("provenance boundary: observed Electron bytes do not become publisher or candidate authority") {
        let f = try BoundaryFixture(); defer { f.clean() }
        try f.app("Electron.app", electron: "provider: generic\nurl: https://electron.example.invalid/private?token=ELECTRON_SECRET\npublisherName: Verified Publisher\nversion: Verified Candidate 99\n")
        let c = f.controller(), o = try await boundaryScan(c, f, names: ["Electron.app"])
        try expect(o.applications[0].vendorMetadata.electronDisposition == .observed && o.applications[0].vendorMetadata.electronConfigBytes != nil, "Setup: real Electron bytes not observed")
        let d = try boundaryDetail(c, path: o.applications[0].path); try boundaryHonesty(d, privateRoot: f.base.path)
        let words = d.lines.joined(separator: " ").lowercased()
        try expect(words.contains("electron") && words.contains("observed") && words.contains("configuration"), "Observed installed configuration lacks honest label")
        try expect(!words.contains("electron_secret") && !words.contains("verified publisher") && !words.contains("verified candidate"), "Raw configuration promoted or exposed")
    }
    check("provenance boundary: held real refresh marks old evidence stale until new observation") {
        let f = try BoundaryFixture(); defer { f.clean() }; try f.app("Held.app", feed: "https://old.example.invalid/feed")
        let p = BoundaryReadProbe(), c = f.controller(p), old = try await boundaryScan(c, f, names: ["Held.app"])
        let path = old.applications[0].path, first = try boundaryDetail(c, path: path)
        try expect(first.lines.joined().lowercased().contains("point-in-time"), "Finished evidence lacks point-in-time qualification")
        try f.app("Held.app", feed: "https://new.example.invalid/feed", version: "2")
        p.arm(); defer { p.open() }; c.scan()
        let deadline = Date().addingTimeInterval(3)
        while !p.isHeld && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        try expect(p.isHeld && !p.timedOut && c.phase == .scanning && c.observation == old, "Setup: real scanner was not held before metadata read")
        let stale = try boundaryDetail(c, path: path), words = stale.lines.joined().lowercased()
        try expect(words.contains("previous observation") && words.contains("stale") && words.contains("old.example.invalid") && !words.contains("new.example.invalid"), "Old evidence not explicitly stale during real refresh")
        try boundaryHonesty(stale, privateRoot: f.base.path)
        p.open(); await c.waitUntilIdle()
        try expect(c.phase == .finished && c.observation?.generation == old.generation + 1 && !p.timedOut, "Setup: held scan did not complete normally")
        let current = try boundaryDetail(c, path: path), final = current.lines.joined().lowercased()
        try expect(current.disclosureID != first.disclosureID && final.contains("point-in-time") && !final.contains("stale") && final.contains("new.example.invalid") && !final.contains("old.example.invalid"), "Refresh retained stale source or details identity")
        try boundaryHonesty(current, privateRoot: f.base.path)
    }
}
