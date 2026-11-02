import Foundation
import Darwin
import ArtifactInspection
@_spi(Testing) import PatchedClient

// CHECK-MODIFIED PAT-2661: additive Phase A physical-fixture contract.
// Inert executable bytes and injected observations only. No native Security call.
private final class IdentityProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func call() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}
private struct IdentityFixture {
    let base: URL, root: URL, app: URL
    init(version: String = "157.0", bundle: String = "org.mozilla.firefox") throws {
        base = try newDirectory("pat2661-identity")
        root = base.appendingPathComponent("Applications")
        app = root.appendingPathComponent("Unbranded.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let fields = ["CFBundleName": "Literal browser", "CFBundleIdentifier": bundle,
                      "CFBundleShortVersionString": version, "CFBundleVersion": "1",
                      "CFBundleExecutable": "firefox", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: fields, format: .xml, options: 0).write(to: plist)
        try Data("inert fixture executable".utf8).write(to: executable)
    }
    var plist: URL { app.appendingPathComponent("Contents/Info.plist") }
    var executable: URL { app.appendingPathComponent("Contents/MacOS/firefox") }
    func clean() { try? FileManager.default.removeItem(at: base) }
    func scanner(_ probe: IdentityProbe, identityBoundaryObserver: (@Sendable (String) -> Void)? = nil,
                 mutation: @escaping @Sendable () throws -> Void = {},
                 alter: @escaping @Sendable (inout SignatureObservation) -> Void = { _ in }) -> LocalApplicationInventory {
        LocalApplicationInventory(fixtureRoots: [root.path], identityCollector: { path, appFD, executableFD, bytes, pin in
            probe.call()
            var appStat = stat(), executableStat = stat(), named = stat()
            try expect(fstat(appFD, &appStat) == 0 && lstat(path, &named) == 0 && appStat.st_ino == named.st_ino,
                       "Collector did not borrow the captured physical bundle")
            try expect(fstat(executableFD, &executableStat) == 0 && executableStat.st_mode & S_IFMT == S_IFREG,
                       "Collector did not borrow a held regular executable")
            try expect(bytes == Data(contentsOf: plist), "Collector did not receive actual held plist bytes")
            try expect(path.hasPrefix(root.path + "/") && pin.bundleID == "org.mozilla.firefox" && pin.teamID == "43AQ936H96",
                       "Collector target changed")
            try mutation()
            var result = SignatureObservation(appPath: path,
                requirement: try PinnedSignatureRequirement.make(teamID: pin.teamID, bundleID: pin.bundleID),
                validationFlags: PinnedSignatureRequirement.validationFlags, validationStatus: 0,
                signingInformationStatus: 0, teamID: "43AQ936H96", identifier: "org.mozilla.firefox",
                startedAt: "2026-10-29T01:00:00Z", finishedAt: "2026-10-29T01:00:01Z")
            alter(&result)
            return result
        }, identityBoundaryObserver: identityBoundaryObserver)
    }
}
@MainActor private func identitySafety(_ c: LocalApplicationsController) throws {
    try expect(c.readyForUpdateCount == 0 && !c.allVerifiedUpToDate, "Signature observation invented update readiness")
    try expect(c.observation?.installationAllowed == false && c.observation?.authorityUnknown == true,
               "Signature observation invented installation authority")
    try expect(c.text.notice == "Update availability has not been checked.", "Update availability became known")
    try expect(c.unknownUpdateCount == c.observation?.applications.count && c.text.rows == c.updatesText.rows,
               "Shared owner disagrees on unknown availability or qualified rows")
}
@MainActor func registerInstalledIdentityIntegrationChecks() {
    for version in ["157.0", "157.0.1"] {
        check("PAT2661 identity: exact pinned physical fixture qualifies once \(version)") {
            let f = try IdentityFixture(version: version); defer { f.clean() }; let p = IdentityProbe()
            let c = LocalApplicationsController(inventory: f.scanner(p))
            try expect(p.count == 0 && c.text.rows.isEmpty, "Construction collected identity")
            c.scan(); await c.waitUntilIdle()
            guard let snapshot = c.observation, let row = snapshot.applications.first,
                  let identity = row.installedIdentity else { throw CheckFailure(description: "Missing scan-bound installed identity") }
            try expect(p.count == 1 && snapshot.applications.count == 1, "Expected one bounded collector call")
            try expect(identity.teamID == "43AQ936H96" && identity.bundleIdentifier == "org.mozilla.firefox" && identity.version == version,
                       "Observed identity differs from pinned literal")
            try expect(identity.sessionID == snapshot.sessionID && identity.generation == snapshot.generation && identity.physicalIdentity == row.physicalIdentity,
                       "Identity escaped physical/session/generation binding")
            try expect(snapshot.provenance == .fixture && identity.provenance == .fixture, "Fixture identity became native proof")
            try expect(c.text.allLines.joined(separator: "\n").contains("Fixture signature observation"), "Shared row hides fixture qualification")
            try expect(!c.text.allLines.joined(separator: "\n").contains("No candidate, publisher identity, signature or notarisation evidence is supplied by this inventory"),
                       "Qualified row still falsely denies its signature observation")
            let before = p.count; _ = c.updatesText; _ = c.text
            try expect(p.count == before, "Rendering recollected identity")
            try identitySafety(c)
        }
    }
    for mode in ["team", "bundle", "status", "timestamp"] {
        check("PAT2661 identity: injected wrong \(mode) never qualifies") {
            let f = try IdentityFixture(); defer { f.clean() }; let p = IdentityProbe()
            let result = await f.scanner(p, alter: { observation in
                switch mode {
                case "team": observation.teamID = "AAAAAAAAAA"
                case "bundle": observation.identifier = "org.other.browser"
                case "status": observation.validationStatus = -1
                default: observation.finishedAt = "2026-10-28T01:00:00Z"
                }
            }).scan()
            try expect(p.count == 1, "Refusal was never exercised through the injected collector")
            try expect(result.applications.allSatisfy { $0.installedIdentity == nil && !$0.installationAllowed }, "Invalid observation qualified")
        }
    }
    for target in [("158.0", "org.mozilla.firefox"), ("157.0", "org.other.browser")] {
        check("PAT2661 identity: unpinned metadata cannot invoke collector \(target.0) \(target.1)") {
            let f = try IdentityFixture(version: target.0, bundle: target.1); defer { f.clean() }; let p = IdentityProbe()
            let result = await f.scanner(p).scan()
            try expect(p.count == 0 && result.applications.count == 1 && result.applications[0].installedIdentity == nil,
                       "Non-target metadata reached signature collection or vanished")
        }
    }
    for leaf in ["bundle", "executable", "plist"] {
        check("PAT2661 identity: replacing held \(leaf) before collection prevents callback") {
            let f = try IdentityFixture(); defer { f.clean() }; let p = IdentityProbe(), boundary = IdentityProbe()
            let result = await f.scanner(p, identityBoundaryObserver: { path in
                guard path == f.app.path else { return }
                boundary.call()
                let target = leaf == "bundle" ? f.app : (leaf == "executable" ? f.executable : f.plist)
                // Failures remain visible as missing callback/changed binding assertions.
                try? FileManager.default.moveItem(at: target, to: target.appendingPathExtension("old"))
                if leaf == "bundle" { try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: false) }
                else { try? Data("replacement".utf8).write(to: target) }
            }).scan()
            let changed = leaf == "bundle" ? f.app : (leaf == "executable" ? f.executable : f.plist)
            try expect(FileManager.default.fileExists(atPath: changed.appendingPathExtension("old").path),
                       "Fixture replacement did not occur at the held boundary")
            try expect(boundary.count == 1 && p.count == 0, "Held input was not rechecked before collector")
            try expect(result.applications.allSatisfy { $0.installedIdentity == nil }, "Changed held input qualified")
        }
        check("PAT2661 identity: replacing \(leaf) during collection refuses binding") {
            let f = try IdentityFixture(); defer { f.clean() }; let p = IdentityProbe()
            let result = await f.scanner(p, mutation: {
                let target = leaf == "bundle" ? f.app : (leaf == "executable" ? f.executable : f.plist)
                try FileManager.default.moveItem(at: target, to: target.appendingPathExtension("old"))
                if leaf == "bundle" { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false) }
                else { try Data("replacement".utf8).write(to: target) }
            }).scan()
            let changed = leaf == "bundle" ? f.app : (leaf == "executable" ? f.executable : f.plist)
            try expect(FileManager.default.fileExists(atPath: changed.appendingPathExtension("old").path),
                       "Fixture replacement did not occur during collection")
            try expect(p.count == 1, "Replacement boundary was never exercised")
            try expect(result.applications.allSatisfy { $0.installedIdentity == nil }, "Changed physical input retained identity")
        }
    }
    check("PAT2661 identity: current generation and prior immutable snapshot stay separate") {
        let f = try IdentityFixture(); defer { f.clean() }; let p = IdentityProbe(), scanner = f.scanner(IdentityProbe())
        let first = await scanner.scan(), second = await scanner.scan()
        try expect(first.applications.first?.installedIdentity?.generation == first.generation &&
                   second.applications.first?.installedIdentity?.generation == second.generation && second.generation == first.generation + 1,
                   "Identity reused stale generation")
        let refused = await f.scanner(p, alter: { $0.teamID = "AAAAAAAAAA" }).scan()
        try expect(refused.applications.first?.installedIdentity == nil && first.applications.first?.installedIdentity != nil,
                   "Later refusal mutated previous snapshot or reused its identity")
    }
    check("PAT2661 identity: symlink alias never becomes an observed installed copy") {
        let f = try IdentityFixture(); defer { f.clean() }; let p = IdentityProbe()
        try FileManager.default.createSymbolicLink(at: f.root.appendingPathComponent("Alias.app"), withDestinationURL: f.app)
        let r = await f.scanner(p).scan()
        try expect(p.count == 1 && r.applications.count == 1 && r.applications.first?.installedIdentity != nil,
                   "Alias duplicated collection or displaced physical copy")
    }
    check("PAT2661 identity: duplicate bundle IDs on distinct physical copies stay distinct") {
        let f = try IdentityFixture(); defer { f.clean() }; let p = IdentityProbe()
        try FileManager.default.copyItem(at: f.app, to: f.root.appendingPathComponent("Other.app"))
        let r = await f.scanner(p).scan()
        try expect(p.count == 2 && r.applications.count == 2 && r.applications.allSatisfy { $0.installedIdentity != nil },
                   "Distinct copies collapsed or collector escaped its physical row")
        try expect(r.applications[0].physicalIdentity != r.applications[1].physicalIdentity,
                   "Distinct physical bundles acquired one identity")
    }
    check("PAT2661 identity: literal application cap bounds collection at 512 attempts") {
        let f = try IdentityFixture(); defer { f.clean() }; let p = IdentityProbe()
        for index in 0..<512 {
            try FileManager.default.copyItem(at: f.app, to: f.root.appendingPathComponent(String(format: "Copy%03d.app", index)))
        }
        let r = await f.scanner(p).scan()
        try expect(p.count == 512 && r.applications.count == 512 && r.completeness == .incomplete,
                   "Collector/input retention exceeded literal bound or skipped accepted rows")
        try expect(r.issues.contains { $0.kind == .applicationLimit }, "Literal cap did not report incomplete coverage")
    }
    check("PAT2661 identity: injected collector refusal stays unknown without native fallback") {
        let f = try IdentityFixture(); defer { f.clean() }; let p = IdentityProbe()
        let scanner = LocalApplicationInventory(fixtureRoots: [f.root.path], identityCollector: { _, _, _, _, _ in
            p.call(); throw InspectionFailure.signatureRejected
        })
        let r = await scanner.scan()
        try expect(p.count == 1 && r.applications.count == 1 && r.applications[0].installedIdentity == nil,
                   "Collector refusal disappeared or acquired a fallback identity")
        try expect(r.provenance == .fixture && !r.installationAllowed, "Refusal gained native/installation authority")
    }
    check("PAT2661 identity: fixture roots without an injected collector remain metadata only") {
        let f = try IdentityFixture(); defer { f.clean() }
        let r = await LocalApplicationInventory(fixtureRoots: [f.root.path]).scan()
        try expect(r.applications.count == 1 && r.applications[0].installedIdentity == nil && r.provenance == .fixture,
                   "Ordinary fixture scan acquired a signature identity")
    }
}
