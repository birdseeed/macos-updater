import Foundation
@_spi(Testing) import PatchedClient

// External preparation only. Parent must accept the allLines display contract,
// copy to Tests/PatchedClientChecks, observe compiling RED, and freeze it.
// No mock result constructors, network, candidate imports, app launch or rendering.
private struct ProvenanceFixture {
    let base: URL
    let root: URL
    init() throws {
        base = try newDirectory("pat2731-provenance")
        root = base.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    func clean() { try? FileManager.default.removeItem(at: base) }
    func app(_ name: String, feed: String? = nil, version: String = "2.3", build: String = "47") throws {
        let contents = root.appendingPathComponent(name).appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var p = ["CFBundleName": name, "CFBundleIdentifier": "example.same",
                 "CFBundleShortVersionString": version, "CFBundleVersion": build]
        if let feed { p["SUFeedURL"] = feed }
        try PropertyListSerialization.data(fromPropertyList: p, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
    }
    @MainActor func controller() -> LocalApplicationsController {
        LocalApplicationsController(inventory: LocalApplicationInventory(fixtureRoots: [root.path]))
    }
}
@MainActor private func provenanceScan(_ c: LocalApplicationsController, root: URL, app: String,
                                        version: String, build: String, feed: String?) async throws {
    c.scan(); await c.waitUntilIdle()
    guard c.phase == .finished, let observation = c.observation else {
        throw CheckFailure(description: "Provenance fixture setup failed: real scanner did not finish")
    }
    try expect(observation.provenance == .fixture && observation.completeness == .complete
               && observation.issues.isEmpty,
               "Provenance fixture setup failed: scan was not a complete issue-free fixture observation")
    try expect(observation.roots.count == 1 && observation.roots.first?.path == root.path
               && observation.roots.first?.scope == .fixture && observation.roots.first?.status == .scanned,
               "Provenance fixture setup failed: exact owned root was not scanned")
    guard observation.applications.count == 1, let row = observation.applications.first else {
        throw CheckFailure(description: "Provenance fixture setup failed: expected exactly one application")
    }
    try expect(row.path == root.appendingPathComponent(app).path && row.displayName == app
               && row.claimedBundleIdentifier == "example.same" && row.claimedShortVersion == version
               && row.claimedBuild == build && row.metadataDisposition == .observed,
               "Provenance fixture setup failed: exact application path or claimed metadata was not observed")
    try expect(row.vendorMetadata.sparkleFeedURL == feed
               && row.vendorMetadata.sparkleDisposition == (feed == nil ? .unavailable : .observed),
               "Provenance fixture setup failed: expected literal feed observation or explicit absence was not retained")
}
@MainActor private func provenanceLines(_ c: LocalApplicationsController) -> String {
    c.updatesText.allLines.joined(separator: "\n")
}
@MainActor func registerProvenancePresentationChecks() {
    check("provenance: absent source and candidate evidence remain explicit") {
        let f = try ProvenanceFixture(); defer { f.clean() }; try f.app("Absent.app")
        let c = f.controller(); try await provenanceScan(c, root: f.root, app: "Absent.app", version: "2.3", build: "47", feed: nil)
        let s = provenanceLines(c)
        for expected in ["Publisher: unknown", "Update source: unknown", "Candidate version: unknown",
                         "Candidate build: unknown", "Verification: not checked"] {
            try expect(s.contains(expected), "Missing honest provenance field: \(expected)")
        }
        try expect(!c.allVerifiedUpToDate && c.readyForUpdateCount == 0, "Details invented update authority")
    }
    check("provenance: installed Sparkle source is observed, never verified identity") {
        let f = try ProvenanceFixture(); defer { f.clean() }
        try f.app("Observed.app", feed: "https://updates.example.invalid/feed.xml")
        let c = f.controller(); try await provenanceScan(c, root: f.root, app: "Observed.app", version: "2.3", build: "47", feed: "https://updates.example.invalid/feed.xml")
        let s = provenanceLines(c)
        for expected in ["Sparkle", "updates.example.invalid", "observed", "Publisher: unknown", "Verification: not checked"] {
            try expect(s.contains(expected), "Source claim lost its honest field: \(expected)")
        }
        try expect(!s.contains("Verified publisher") && !s.contains("Ready to install"), "Observed feed became authority")
        try expect(c.text.rows == c.updatesText.rows, "Details created a second inventory projection")
    }
    check("provenance: destination hides query and path secrets while preserving useful host") {
        let f = try ProvenanceFixture(); defer { f.clean() }
        try f.app("Sensitive.app", feed: "https://updates.example.invalid/private-secret/feed.xml?token=QUERY_SECRET&user=PRIVATE_PERSON")
        let c = f.controller(); try await provenanceScan(c, root: f.root, app: "Sensitive.app", version: "2.3", build: "47", feed: "https://updates.example.invalid/private-secret/feed.xml?token=QUERY_SECRET&user=PRIVATE_PERSON")
        let s = provenanceLines(c)
        try expect(s.contains("updates.example.invalid"), "Safe destination host is missing")
        for secret in ["QUERY_SECRET", "PRIVATE_PERSON", "private-secret", "?token=", "&user="] {
            try expect(!s.contains(secret), "Sensitive source URL material displayed: \(secret)")
        }
    }
    check("provenance: actual rescan replaces previous source without promoting checks") {
        let f = try ProvenanceFixture(); defer { f.clean() }
        try f.app("Same.app", feed: "https://old.example.invalid/feed.xml", version: "1", build: "1")
        let c = f.controller(); try await provenanceScan(c, root: f.root, app: "Same.app", version: "1", build: "1", feed: "https://old.example.invalid/feed.xml")
        let old = c.observation!, oldText = provenanceLines(c)
        try expect(oldText.contains("old.example.invalid"), "Old observed source setup not displayed")
        try f.app("Same.app", feed: "https://new.example.invalid/feed.xml", version: "2", build: "2")
        try await provenanceScan(c, root: f.root, app: "Same.app", version: "2", build: "2", feed: "https://new.example.invalid/feed.xml")
        let current = provenanceLines(c)
        try expect(c.observation!.sessionID == old.sessionID && c.observation!.generation == old.generation + 1, "Competing inventory owner")
        try expect(current.contains("new.example.invalid") && !current.contains("old.example.invalid"), "Old source survived actual rescan")
        try expect(current.contains("Claimed version: 2") && current.contains("Claimed build: 2") && current.contains("Verification: not checked"), "New source inherited authority or old version")
        try expect(oldText.contains("old.example.invalid"), "Previously captured value mutated")
    }
}
