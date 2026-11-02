import Foundation
import CryptoKit
@_spi(Testing) import PatchedCore

@MainActor func registerCatalogueChecks() {
    check("exact fixture signature returns immutable candidate after checkpoint") {
        try withWorkspace { root in
            try seedState(root)
            let candidate = try Fixture.verifier(root).verify(envelope: Fixture.envelope(), now: Fixture.now)
            try expect(candidate.sequence == 7 && candidate.catalogueID == Fixture.catalogueID, "Wrong candidate identity")
            try expect(candidate.payloadSHA256 == sha(try json(Fixture.payload())), "Not exact payload SHA-256")
            try expect(candidate.artifact.bundleID == "org.mozilla.firefox" && candidate.artifact.teamID == "43AQ936H96"
                       && candidate.artifact.version == "157.0.1" && candidate.artifact.byteLength == 3, "Artifact constraints lost")
            try expect(candidate.origin == "fixture" && !candidate.freshOSValidation && !candidate.installationAuthorized,
                       "Fixture catalogue claimed OS validation or installation authority")
            try assertCheckpoint(root, sequence: 7, payload: json(Fixture.payload()))
        }
    }
    for (field, value, reason) in [
        ("domain", "wrong.domain", CoreFailure.wrongDomain),
        ("catalogueID", "another.catalogue", .wrongCatalogue),
        ("keyID", "another.key", .untrustedKey)
    ] {
        check("signed identity \(field)") { try verifyRefusal(mutatePayload { $0[field] = value }, reason) }
    }
    check("signature from different deterministic fixture key") {
        try verifyRefusal(Fixture.signed(json(Fixture.payload()), alternateKey: true), .invalidSignature)
    }
    for frame in ["", Fixture.domain, "im.patched.catalogue.v2\0", Fixture.domain + "\0\0"] {
        check("explicit signature domain framing \(String(reflecting: frame))") {
            try verifyRefusal(Fixture.signed(json(Fixture.payload()), frame: frame), .invalidSignature)
        }
    }
    check("tampered payload retains original signature") {
        var value = try object(Fixture.envelope())
        value["payload"] = try json(Fixture.payload(sequence: 8)).base64EncodedString()
        try verifyRefusal(json(value), .invalidSignature)
    }
    check("changed whitespace cannot be accepted under old signature") {
        var value = try object(Fixture.envelope())
        value["payload"] = (try json(Fixture.payload()) + Data(" ".utf8)).base64EncodedString()
        try verifyRefusal(json(value), .invalidSignature)
    }
    check("envelope key must equal pinned and signed key") {
        var value = try object(Fixture.envelope()); value["keyID"] = "other"
        try verifyRefusal(json(value), .untrustedKey)
    }
    for (field, value) in [("signature", "!"), ("signature", Data(repeating: 0, count: 63).base64EncodedString()),
                           ("signature", Data(repeating: 0, count: 65).base64EncodedString()), ("payload", "!")] {
        check("invalid envelope encoding \(field) \(value.count)") {
            var valueObject = try object(Fixture.envelope()); valueObject[field] = value
            try verifyRefusal(json(valueObject), .invalidEnvelope)
        }
    }
    for field in ["payload", "signature", "keyID"] {
        check("missing envelope \(field)") {
            var value = try object(Fixture.envelope()); value.removeValue(forKey: field)
            try verifyRefusal(json(value), .invalidEnvelope)
        }
    }
    for field in ["schemaVersion", "domain", "keyID", "catalogueID", "sequence", "issuedAt", "expiresAt", "artifact"] {
        check("required payload \(field)") { try verifyRefusal(mutatePayload { $0.removeValue(forKey: field) }, .invalidPayload) }
    }
    for field in ["bundleID", "teamID", "platform", "minimumOS", "maximumOS", "version", "sha256", "byteLength"] {
        check("required artifact \(field)") { try verifyRefusal(mutateArtifact { $0.removeValue(forKey: field) }, .invalidPayload) }
    }
    for field in ["installationAuthorized", "freshOSValidation", "script", "url"] {
        check("unknown actionable payload field \(field)") { try verifyRefusal(mutatePayload { $0[field] = true }, .invalidPayload) }
        check("unknown actionable artifact field \(field)") { try verifyRefusal(mutateArtifact { $0[field] = true }, .invalidPayload) }
    }
    check("unknown envelope success flag") {
        var value = try object(Fixture.envelope()); value["verified"] = true
        try verifyRefusal(json(value), .invalidEnvelope)
    }
    for (name, edit) in [
        ("bundle", ["bundleID": "org.attacker.firefox"]), ("team", ["teamID": "ABCDEFGHIJ"]),
        ("empty bundle", ["bundleID": ""]), ("invalid team", ["teamID": "43AQ936H9!"])
    ] {
        check("artifact identity \(name)") {
            let data = try mutateArtifact { for (key, value) in edit { $0[key] = value } }
            try verifyRefusal(data, name.hasPrefix("invalid") || name.hasPrefix("empty") ? .invalidPayload : .wrongIdentity)
        }
    }
    check("wrong platform") { try verifyRefusal(mutateArtifact { $0["platform"] = "Windows" }, .wrongPlatform) }
    for os in ["12.9", "28.0"] {
        check("host outside OS range \(os)") { try verifyRefusal(Fixture.envelope(), .unsupportedOS, policy: Fixture.policy(os: os)) }
    }
    for os in ["13.0", "27.9", "13", "27.9.0"] {
        check("OS range numeric inclusive boundary \(os)") {
            try withWorkspace { root in
                try seedState(root)
                _ = try Fixture.verifier(root, policy: Fixture.policy(os: os)).verify(envelope: Fixture.envelope(), now: Fixture.now)
            }
        }
    }
    for installed in ["157.0.1", "157.0.1.0", "157.0.2", "158"] {
        check("candidate must be newer \(installed)") { try verifyRefusal(Fixture.envelope(), .notNewer, policy: Fixture.policy(installed: installed)) }
    }
    check("numeric version comparison 10 exceeds 9") {
        try withWorkspace { root in
            try seedState(root)
            let data = try mutateArtifact { $0["version"] = "157.0.10" }
            _ = try Fixture.verifier(root, policy: Fixture.policy(installed: "157.0.9")).verify(envelope: data, now: Fixture.now)
        }
    }
    let badVersions = ["", "01.0", "157..1", "157.0b1", "157.0\n", " 157", "+157", "-1", "1.", ".1", "١.0", "4294967296", "1.2.3.4.5.6.7.8.9"]
    for version in badVersions {
        check("invalid candidate version \(String(reflecting: version))") {
            try verifyRefusal(mutateArtifact { $0["version"] = version }, .invalidPayload)
        }
    }
    for field in ["minimumOS", "maximumOS"] {
        check("invalid \(field)") { try verifyRefusal(mutateArtifact { $0[field] = "27.x" }, .invalidPayload) }
    }
    check("reversed OS range") { try verifyRefusal(mutateArtifact { $0["minimumOS"] = "28"; $0["maximumOS"] = "13" }, .invalidPayload) }
    for policy in [Fixture.policy(os: "27beta"), Fixture.policy(installed: "latest")] {
        check("invalid caller numeric version \(policy.osVersion) \(policy.installedVersion)") { try verifyRefusal(Fixture.envelope(), .invalidPayload, policy: policy) }
    }
    for digest in ["", "a", String(repeating: "g", count: 64), String(repeating: "A", count: 64), sha(Fixture.bytes) + "\n"] {
        check("invalid required SHA256 \(String(reflecting: digest))") { try verifyRefusal(mutateArtifact { $0["sha256"] = digest }, .invalidPayload) }
    }
    for value: Any in [0, -1, 2_147_483_649, 3.5, true, "3", NSNull()] {
        check("invalid bounded artifact length \(value)") { try verifyRefusal(mutateArtifact { $0["byteLength"] = value }, .invalidPayload) }
    }
    for value: Any in [0, -1, 7.5, true, "7", NSNull()] {
        check("invalid sequence \(value)") { try verifyRefusal(mutatePayload { $0["sequence"] = value }, .invalidPayload) }
    }
    for value: Any in [2, true, "1"] {
        check("strict schema version \(value)") { try verifyRefusal(mutatePayload { $0["schemaVersion"] = value }, .invalidPayload) }
    }
    for (offset, expected) in [(0.0, true), (300.0, true), (301.0, false)] {
        check("future issue boundary \(offset)") {
            let data = try mutatePayload { $0["issuedAt"] = Int64(Fixture.now + offset); $0["expiresAt"] = Int64(Fixture.now + offset + 3600) }
            if expected {
                try withWorkspace { root in try seedState(root); _ = try Fixture.verifier(root).verify(envelope: data, now: Fixture.now) }
            } else { try verifyRefusal(data, .futureIssued) }
        }
    }
    for lifetime in [259_200, 259_201, 0, -1] {
        check("72-hour lifetime bound \(lifetime)") {
            let data = try mutatePayload { $0["expiresAt"] = Int64(Fixture.now) + Int64(lifetime) }
            if lifetime == 259_200 {
                try withWorkspace { root in try seedState(root); _ = try Fixture.verifier(root).verify(envelope: data, now: Fixture.now) }
            } else { try verifyRefusal(data, .invalidLifetime) }
        }
    }
    for now in [Fixture.now + 3600, Fixture.now + 3601] {
        check("expiry inclusive refusal \(now)") { try verifyRefusal(Fixture.envelope(), .expired, now: now) }
    }
    check("one instant before expiry accepted") {
        try withWorkspace { root in try seedState(root); _ = try Fixture.verifier(root).verify(envelope: Fixture.envelope(), now: Fixture.now + 3599.999) }
    }
    for now in [Double.nan, Double.infinity, -Double.infinity, -1] {
        check("invalid caller clock \(now)") { try verifyRefusal(Fixture.envelope(), .invalidClock, now: now) }
    }
    for field in ["issuedAt", "expiresAt"] {
        for value: Any in [true, "1800000000", -1, 1.5] {
            check("strict timestamp \(field) \(value)") { try verifyRefusal(mutatePayload { $0[field] = value }, .invalidPayload) }
        }
    }
    registerEncodingChecks()
}

@MainActor func registerEncodingChecks() {
    let raw = String(decoding: try! json(Fixture.payload()), as: UTF8.self)
    let payloadVariants: [(String, Data)] = [
        ("trailing bytes", Data((raw + " {}").utf8)), ("UTF8 BOM", Data([0xef, 0xbb, 0xbf]) + Data(raw.utf8)),
        ("UTF16", raw.data(using: .utf16)!), ("invalid UTF8", Data([0xff, 0xfe, 0x80])),
        ("truncated", Data(raw.dropLast().utf8)), ("array root", Data("[]".utf8)),
        ("duplicate root", Data(raw.replacingOccurrences(of: "\"sequence\":7", with: "\"sequence\":7,\"sequence\":8").utf8)),
        ("duplicate nested", Data(raw.replacingOccurrences(of: "\"byteLength\":3", with: "\"byteLength\":3,\"byteLength\":4").utf8)),
        ("escaped duplicate nested", Data(raw.replacingOccurrences(of: "\"byteLength\":3", with: "\"byteLength\":3,\"byte\\u004cength\":3").utf8)),
        ("escaped duplicate root", Data(raw.replacingOccurrences(of: "\"sequence\":7", with: "\"sequence\":7,\"sequen\\u0063e\":7").utf8)),
        ("sequence overflow", Data(raw.replacingOccurrences(of: "\"sequence\":7", with: "\"sequence\":18446744073709551616").utf8)),
        ("length overflow", Data(raw.replacingOccurrences(of: "\"byteLength\":3", with: "\"byteLength\":9223372036854775808").utf8)),
        ("timestamp overflow", Data(raw.replacingOccurrences(of: "\"issuedAt\":1800000000", with: "\"issuedAt\":9223372036854775808").utf8)),
        ("nonfinite JSON time", Data(raw.replacingOccurrences(of: "\"issuedAt\":1800000000", with: "\"issuedAt\":1e999").utf8)),
        ("NaN token", Data(raw.replacingOccurrences(of: "\"issuedAt\":1800000000", with: "\"issuedAt\":NaN").utf8)),
        ("oversized payload", Data(repeating: 0x20, count: 65_537)),
        ("deep nesting", Data((String(repeating: "[", count: 80) + "0" + String(repeating: "]", count: 80)).utf8))
    ]
    for (name, bytes) in payloadVariants {
        check("signed malformed payload \(name)") { try verifyRefusal(Fixture.signed(bytes), .invalidPayload) }
    }
    check("unique escaped key retains exact signed payload semantics") {
        let bytes = Data(raw.replacingOccurrences(of: "\"bundleID\"", with: "\"bundle\\u0049D\"").utf8)
        try withWorkspace { root in
            try seedState(root)
            let result = try Fixture.verifier(root).verify(envelope: Fixture.signed(bytes), now: Fixture.now)
            try expect(result.payloadSHA256 == sha(bytes), "Escaped spelling was canonicalised before hash")
        }
    }
    let envelope = String(decoding: try! Fixture.envelope(), as: UTF8.self)
    let envelopeVariants: [(String, Data)] = [
        ("BOM", Data([0xef, 0xbb, 0xbf]) + Data(envelope.utf8)), ("UTF16", envelope.data(using: .utf16)!),
        ("trailing", Data((envelope + "false").utf8)), ("duplicate keyID", Data(("{\"keyID\":\"x\"," + envelope.dropFirst()).utf8)),
        ("escaped duplicate keyID", Data(("{\"key\\u0049D\":\"x\"," + envelope.dropFirst()).utf8)),
        ("oversized", Data(repeating: 0x20, count: 131_073)), ("invalid UTF8", Data([0xff])), ("array", Data("[]".utf8))
    ]
    for (name, bytes) in envelopeVariants { check("malformed envelope \(name)") { try verifyRefusal(bytes, .invalidEnvelope) } }
    for publicKey in [Data(), Data(repeating: 1, count: 31), Data(repeating: 1, count: 33)] {
        check("malformed pinned public key \(publicKey.count)") {
            try withWorkspace { root in
                try seedState(root)
                let verifier = CatalogueVerifier(trust: .init(keyID: Fixture.keyID, catalogueID: Fixture.catalogueID, publicKey: publicKey),
                    policy: Fixture.policy(), stateDirectory: root.appendingPathComponent("state").path)
                try refuses(.untrustedKey) { _ = try verifier.verify(envelope: Fixture.envelope(), now: Fixture.now) }
            }
        }
    }
}
