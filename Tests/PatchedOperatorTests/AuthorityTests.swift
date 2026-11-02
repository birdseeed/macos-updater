import Foundation
import Darwin
import ArtifactInspection
@_spi(Testing) import PatchedCore
@_spi(Testing) import PatchedOperator

// Who may verify, sign and publish, and where. A caller's report, a recorded inspection,
// a path outside the owned root and absent or altered state must each be refused by name.

/// A caller can build this evidence freely. It is the passing synthetic shape the inspector's own
/// fixture evaluation accepts, so it is the strongest report a caller could forge.
func forgedEvidence(dmg: String = "/private/tmp/forged/artifact.dmg") throws -> AppEvidence {
    let app = "/private/tmp/forged/mount/Firefox.app"
    let plist = try PropertyListSerialization.data(fromPropertyList: [
        "CFBundleIdentifier": Sample.bundleID, "CFBundleShortVersionString": Sample.version,
        "CFBundleExecutable": "firefox", "CFBundlePackageType": "APPL"], format: .xml, options: 0)
    func ran(_ executable: String, _ arguments: [String], _ stdout: String = "", _ stderr: String = "") -> CommandResult {
        CommandResult(executable: executable, arguments: arguments, stdout: stdout, stderr: stderr)
    }
    let accepted = "\(app): accepted\nsource=Notarized Developer ID\n"
    return AppEvidence(appPath: app, dmgPath: dmg, infoPlist: plist, commands: [
        "imageVerify": ran("/usr/bin/hdiutil", ["verify", dmg]),
        "signature": ran("/usr/bin/codesign", ["--verify", "--deep", "--strict", app]),
        "identity": ran("/usr/bin/codesign", ["-dv", "--verbose=4", app], "", "Identifier=\(Sample.bundleID)\nTeamIdentifier=\(Sample.teamID)\n"),
        "architectures": ran("/usr/bin/lipo", ["-archs", app + "/Contents/MacOS/firefox"], "x86_64 arm64\n"),
        "gatekeeper": ran("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=4", app], "", accepted),
        "ticket": ran("/usr/bin/xcrun", ["stapler", "validate", app], "The validate action worked!\n"),
        "containerSignature": ran("/usr/bin/codesign", ["--verify", "--deep", "--strict", dmg]),
        "containerGatekeeper": ran("/usr/sbin/spctl", ["--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=4", dmg],
                                   "", "\(dmg): accepted\nsource=Notarized Developer ID\n"),
        "containerTicket": ran("/usr/bin/xcrun", ["stapler", "validate", dmg], "The validate action worked!\n")])
}
func sources(_ directory: String) throws -> [(String, String)] {
    let path = FileManager.default.currentDirectoryPath + "/Sources/" + directory
    return try FileManager.default.contentsOfDirectory(atPath: path).filter { $0.hasSuffix(".swift") }.sorted().map {
        (directory + "/" + $0, try String(contentsOfFile: path + "/" + $0, encoding: .utf8))
    }
}
/// Ordinary use from nothing but the root path: reopen, receipt, sign. A refusal at any of the three counts.
func ordinaryUse(_ layout: Layout, trust: FixtureTrust? = nil) throws {
    let authority = try FixtureOperatorAuthority.reopenRoot(path: layout.root.path, trust: try trust ?? Sample.trust())
    _ = try signed(authority, layout)
}

@MainActor func registerAuthorityChecks() {
    check("authority: the default sign entry refuses a fixture receipt, a valid request and a valid clock") {
        try withRoot { authority, layout in
            let receipt = try fixtureReceipt(authority, layout)
            let before = try snapshot(layout.root)
            try refuses(.notAuthorized) { _ = try CataloguePublisher.sign(receipt: receipt, request: Sample.request(), now: Sample.now) }
            try expect(try snapshot(layout.root) == before, "A refused default sign changed the operator root")
        }
    }
    check("authority: the default publish entry refuses a correctly signed fixture catalogue") {
        try withRoot { authority, layout in
            let catalogue = try signed(authority, layout)
            let before = try snapshot(layout.root)
            try refuses(.notAuthorized) { _ = try CataloguePublisher.publish(catalogue, now: Sample.now) }
            try expect(try snapshot(layout.root) == before, "A refused default publish changed the operator root")
        }
    }

    check("forged report: evidence the inspector's own fixture evaluation passes is refused as a verification") {
        let evidence = try forgedEvidence()
        let assessment = try EvidenceEvaluator.evaluateFixture(evidence, pin: FirefoxTargets.select(version: Sample.version))
        try expect(assessment.appChecksPassed && assessment.origin == .fixture, "The forged evidence is not the strongest caller-built shape")
        try refuses(.recordedEvidenceRefused) {
            _ = try OperatorVerification.acceptRecordedInspection(JSONEncoder().encode(evidence), version: Sample.version)
        }
    }
    check("forged report: a serialized report asserting a live passing assessment is refused") {
        let pin = try FirefoxTargets.select(version: Sample.version)
        let report: [String: Any] = [
            "schemaVersion": 1, "mode": "inspect-local", "sourcePath": "/private/tmp/forged/Firefox.dmg", "sourceURL": pin.url,
            "redirectChain": [String](), "transportObservedThisRun": false, "byteIntegrityVerified": true, "commands": [Any](),
            "pin": ["version": pin.version, "url": pin.url, "sha256": pin.sha256, "byteLength": pin.byteLength,
                    "bundleID": pin.bundleID, "teamID": pin.teamID, "architectures": pin.architectures],
            "evidence": try object(JSONEncoder().encode(forgedEvidence())),
            "assessment": ["appChecksPassed": true, "containerSignaturePassed": true, "containerGatekeeperPassed": true,
                           "containerTicketPassed": true, "origin": "live", "freshOSValidation": true, "installationAuthorized": false],
            "cleanupVerified": true, "installationAuthorized": false, "providerActualCost": "unknown"]
        for record in [try json(report), try json(report["assessment"]!), Data(), Data("{}".utf8)] {
            try refuses(.recordedEvidenceRefused) { _ = try OperatorVerification.acceptRecordedInspection(record, version: Sample.version) }
        }
    }
    check("forged report: a replayed record stays cached and is refused as a verification") {
        let record = try JSONEncoder().encode(forgedEvidence())
        let replayed = try EvidenceEvaluator.replay(record, pin: FirefoxTargets.select(version: Sample.version))
        try expect(replayed.origin == .replayed && !replayed.freshOSValidation, "Replay is no longer labelled cached")
        try refuses(.recordedEvidenceRefused) { _ = try OperatorVerification.acceptRecordedInspection(record, version: Sample.version) }
    }

    check("source guard: operator sources hold no key material, decoder, network, timer, scan or process launch") {
        let forbidden = ["PrivateKey", "Decodable", "Codable", "SecKey", "Keychain", "URLSession", "URLRequest", "Timer", "DispatchSource",
                         "NSWorkspace", "Process(", "posix_spawn", "downloadAndInspect", "evaluateFixture", ".onAppear", ".task"]
        let files = try sources("PatchedOperator") + sources("PatchedOperatorApp")
        try expect(files.count >= 5, "Operator sources were not found from the package root")
        for (name, text) in files {
            for word in forbidden { try expect(!text.contains(word), "\(name) contains \(word)") }
        }
    }
    check("source guard: no public entry takes a caller's report, evidence or assessment") {
        for (name, text) in try sources("PatchedOperator") {
            for line in text.split(separator: "\n") where line.contains("public") {
                for type in ["InspectionReport", "AppEvidence", "Assessment"] {
                    try expect(!line.contains(type), "\(name) exposes \(type) on a public line: \(line)")
                }
            }
        }
    }
    check("source guard: the output-only results have no public or testing constructor") {
        let text = try sources("PatchedOperator").map(\.1).joined(separator: "\n")
        for type in ["VerifiedArtifactReceipt", "SignedCatalogue", "PublishedCatalogue"] {
            guard let start = text.range(of: "public struct \(type): Encodable, Sendable {"),
                  let end = text.range(of: "\n}", range: start.upperBound..<text.endIndex) else {
                throw CheckFailure(description: "\(type) is not declared as an output-only Encodable struct")
            }
            let body = text[start.upperBound..<end.lowerBound]
            try expect(!body.contains("public init") && !body.contains("@_spi") && !body.contains(" var "),
                       "\(type) can be constructed or mutated by a caller")
        }
    }
    check("source guard: the live entry calls the actual inspector for a local artifact exactly once") {
        let text = try sources("PatchedOperator").map(\.1).joined(separator: "\n")
        try expect(text.components(separatedBy: "ArtifactInspector.inspectLocal(").count == 2,
                   "The operator library does not call ArtifactInspector.inspectLocal exactly once")
    }

    let outside: [(String, (Layout) throws -> String)] = [
        ("a temporary directory outside .build", { _ in "/private/tmp/patched-operator-fixture-\(UUID().uuidString)" }),
        ("a name without the fixture prefix", { $0.build.appendingPathComponent("operator-\(UUID().uuidString)").path }),
        ("a nested directory beneath .build", { layout in
            layout.scratch.appendingPathComponent("patched-operator-fixture-nested").path }),
        ("a relative path", { ".build/" + $0.root.lastPathComponent }),
        ("a path with traversal", { $0.scratch.path + "/../" + $0.root.lastPathComponent }),
        ("a doubled separator", { $0.build.path + "//" + $0.root.lastPathComponent }),
        ("an alias of .build through a symlink", { layout in
            let alias = layout.scratch.appendingPathComponent("alias")
            try expect(symlink(layout.build.path, alias.path) == 0, "Fixture symlink failed")
            return alias.path + "/" + layout.root.lastPathComponent }),
        ("a name with a control byte", { $0.root.path + "\n" }),
        ("an overlong name", { $0.root.path + String(repeating: "a", count: 80) })]
    for (name, path) in outside {
        check("new namespace: \(name) is refused and nothing is created") {
            try withLayout { layout in
                let requested = try path(layout)
                try refuses(.unsafePath) { _ = try FixtureOperatorAuthority.createFreshRoot(path: requested, trust: Sample.trust()) }
                var info = stat()
                try expect(lstat(requested, &info) != 0 && !exists(layout.root), "A refused namespace request created an entry")
            }
        }
    }
    check("new namespace: an existing empty directory is refused and left untouched") {
        try withLayout { layout in
            try makeDirectory(layout.root)
            try refuses(.existingNamespace) { _ = try FixtureOperatorAuthority.createFreshRoot(path: layout.root.path, trust: Sample.trust()) }
            try expect(try names(layout.root).isEmpty, "A refused creation wrote into an existing directory")
        }
    }
    check("new namespace: an existing complete root is refused, never adopted or reset") {
        try withRoot { _, layout in
            let before = try snapshot(layout.root)
            try refuses(.existingNamespace) { _ = try FixtureOperatorAuthority.createFreshRoot(path: layout.root.path, trust: Sample.trust()) }
            try expect(try snapshot(layout.root) == before, "A refused creation changed an existing root")
        }
    }
    check("new namespace: a symlink at the root name is refused and its destination is not written") {
        try withLayout { layout in
            let elsewhere = layout.scratch.appendingPathComponent("elsewhere")
            try makeDirectory(elsewhere)
            try expect(symlink(elsewhere.path, layout.root.path) == 0, "Fixture symlink failed")
            try refuses(.unsafePath) { _ = try FixtureOperatorAuthority.createFreshRoot(path: layout.root.path, trust: Sample.trust()) }
            try expect(try names(elsewhere).isEmpty, "Creation wrote through a symlink")
        }
    }
    let untrusted: [(String, () throws -> FixtureTrust)] = [
        ("a 31-byte public key", { FixtureTrust(keyID: Sample.keyID, catalogueID: Sample.catalogueID, publicKey: Data(repeating: 1, count: 31)) }),
        ("an empty public key", { FixtureTrust(keyID: Sample.keyID, catalogueID: Sample.catalogueID, publicKey: Data()) }),
        ("a key identifier with a space", { try Sample.trust(keyID: "fixture key") }),
        ("an empty catalogue identifier", { try Sample.trust(catalogueID: "") }),
        ("a 129-byte key identifier", { try Sample.trust(keyID: String(repeating: "k", count: 129)) })]
    for (name, trust) in untrusted {
        check("new namespace: \(name) is refused as untrusted and nothing is created") {
            try withLayout { layout in
                try refuses(.untrustedKey) { _ = try FixtureOperatorAuthority.createFreshRoot(path: layout.root.path, trust: trust()) }
                try expect(!exists(layout.root), "A refused namespace request created an entry")
            }
        }
    }
    check("new namespace: the fresh root has the exact documented entries, modes and initial state") {
        try withLayout { layout in
            let authority = try FixtureOperatorAuthority.createFreshRoot(path: layout.root.path, trust: Sample.trust())
            try expect(authority.root == layout.root.path, "Authority names a different root")
            try expect(try names(layout.root) == ["namespace.json", "checkpoint.json", "lock", "input", "publications"],
                       "Fresh root entries differ: \(try names(layout.root).sorted())")
            try expectPrivateDirectory(layout.root, "Root"); try expectPrivateDirectory(layout.input, "Input directory")
            try expectPrivateDirectory(layout.publications, "Publications directory")
            try expectPrivateFile(layout.namespace, "Namespace record"); try expectPrivateFile(layout.lock, "Lock")
            try expect(try names(layout.input).isEmpty && names(layout.publications).isEmpty, "Fresh root already holds input or output")
            let namespace = try object(bytes(layout.namespace))
            try expect(Set(namespace.keys) == ["schemaVersion", "namespace", "keyID", "catalogueID"] && unsigned(namespace["schemaVersion"]) == 1 &&
                       namespace["namespace"] as? String == "patched-operator-fixture-v1" && namespace["keyID"] as? String == Sample.keyID &&
                       namespace["catalogueID"] as? String == Sample.catalogueID, "Namespace record differs: \(namespace)")
            let checkpoint = try checkpointFields(layout)
            try expect(checkpoint.sequence == 0 && checkpoint.payloadSHA256 == Sample.zeroDigest, "Fresh checkpoint is not the empty high-water mark")
            try expect(try bytes(layout.lock).isEmpty, "Lock file is not empty")
        }
    }

    check("ordinary use: a root that was never created is refused as missing and is not created") {
        try withLayout { layout in
            try refuses(.missingState) { _ = try FixtureOperatorAuthority.reopenRoot(path: layout.root.path, trust: Sample.trust()) }
            try expect(!exists(layout.root), "Ordinary use created a namespace")
        }
    }
    let damaged: [(String, OperatorFailure, @Sendable (Layout) throws -> Void)] = [
        ("a missing checkpoint", .missingState, { try FileManager.default.removeItem(at: $0.checkpoint) }),
        ("a missing namespace record", .missingState, { try FileManager.default.removeItem(at: $0.namespace) }),
        ("a missing lock", .missingState, { try FileManager.default.removeItem(at: $0.lock) }),
        ("a missing publications directory", .missingState, { try FileManager.default.removeItem(at: $0.publications) }),
        ("an empty checkpoint", .corruptState, { try Data().write(to: $0.checkpoint) }),
        ("a truncated checkpoint", .corruptState, { try Data(try bytes($0.checkpoint).dropLast(2)).write(to: $0.checkpoint) }),
        ("a checkpoint with a duplicate sequence", .corruptState, { layout in
            let text = "{\"schemaVersion\":1,\"keyID\":\"\(Sample.keyID)\",\"catalogueID\":\"\(Sample.catalogueID)\"," +
                "\"sequence\":9,\"sequence\":0,\"payloadSHA256\":\"\(Sample.zeroDigest)\"}"
            try Data(text.utf8).write(to: layout.checkpoint) }),
        ("a checkpoint with an unknown field", .corruptState, { layout in
            var fields = try object(bytes(layout.checkpoint)); fields["published"] = true
            try json(fields).write(to: layout.checkpoint) }),
        ("a checkpoint with a quoted sequence", .corruptState, { layout in
            var fields = try object(bytes(layout.checkpoint)); fields["sequence"] = "0"
            try json(fields).write(to: layout.checkpoint) }),
        ("a checkpoint with a byte-order mark", .corruptState, { layout in
            try (Data([0xef, 0xbb, 0xbf]) + bytes(layout.checkpoint)).write(to: layout.checkpoint) }),
        ("an oversized checkpoint", .corruptState, { layout in
            try (bytes(layout.checkpoint) + Data(repeating: 0x20, count: 8_192)).write(to: layout.checkpoint) }),
        ("a namespace record for another kind", .corruptState, { layout in
            var fields = try object(bytes(layout.namespace)); fields["namespace"] = "patched-fixture-state-v1"
            try json(fields).write(to: layout.namespace) }),
        ("a checkpoint replaced by a symlink", .unsafePath, { layout in
            let copy = layout.scratch.appendingPathComponent("checkpoint-copy")
            try writeFile(bytes(layout.checkpoint), copy); try FileManager.default.removeItem(at: layout.checkpoint)
            try expect(symlink(copy.path, layout.checkpoint.path) == 0, "Fixture symlink failed") }),
        ("a checkpoint with a second hard link", .hardlink, { layout in
            try expect(link(layout.checkpoint.path, layout.scratch.appendingPathComponent("checkpoint-link").path) == 0, "Fixture link failed") }),
        ("a group-readable checkpoint", .unsafeMode, { try expect(chmod($0.checkpoint.path, 0o640) == 0, "Fixture chmod failed") }),
        ("a world-searchable root", .unsafeMode, { try expect(chmod($0.root.path, 0o755) == 0, "Fixture chmod failed") }),
        ("a checkpoint replaced by a directory", .notRegularFile, { layout in
            try FileManager.default.removeItem(at: layout.checkpoint); try makeDirectory(layout.checkpoint) }),
        ("a publications directory replaced by a symlink", .unsafePath, { layout in
            let elsewhere = layout.scratch.appendingPathComponent("elsewhere"); try makeDirectory(elsewhere)
            try FileManager.default.removeItem(at: layout.publications)
            try expect(symlink(elsewhere.path, layout.publications.path) == 0, "Fixture symlink failed") })]
    for (name, reason, damage) in damaged {
        check("ordinary use: \(name) is refused as \(reason.rawValue) and is never repaired") {
            try withRoot { _, layout in
                try damage(layout)
                let before = try snapshot(layout.root), outside = try snapshot(layout.scratch)
                var signerCalls = 0
                try refuses(reason) {
                    let authority = try FixtureOperatorAuthority.reopenRoot(path: layout.root.path, trust: Sample.trust())
                    let receipt = try fixtureReceipt(authority, layout)
                    _ = try authority.sign(receipt: receipt, request: Sample.request(), now: Sample.now) { signerCalls += 1; return try Sample.signer($0) }
                }
                try expect(signerCalls == 0, "The signer was asked to sign over refused state")
                try expect(try snapshot(layout.root) == before && snapshot(layout.scratch) == outside, "Refused state was repaired, reset or written through")
            }
        }
    }
    check("ordinary use: reopening with another key identifier or catalogue is refused by name") {
        try withRoot { _, layout in
            let before = try snapshot(layout.root)
            try refuses(.untrustedKey) { try ordinaryUse(layout, trust: Sample.trust(keyID: "another-key")) }
            try refuses(.wrongCatalogue) { try ordinaryUse(layout, trust: Sample.trust(catalogueID: "another.catalogue")) }
            try refuses(.untrustedKey) {
                try ordinaryUse(layout, trust: FixtureTrust(keyID: Sample.keyID, catalogueID: Sample.catalogueID, publicKey: Data(repeating: 1, count: 31)))
            }
            try expect(try snapshot(layout.root) == before, "A refused reopen changed the root")
        }
    }
}
