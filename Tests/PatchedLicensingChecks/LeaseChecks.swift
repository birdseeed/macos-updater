import Foundation
import PatchedLicensing

@MainActor func registerLeaseChecks() {
    check("checked-in exact wire vectors match deterministic Swift producer") {
        for (name, expected) in try wireVectors() {
            let actual = try Data(contentsOf: URL(fileURLWithPath: "Fixtures/Licensing/vectors/\(name).json"))
            try expect(actual == expected, "Producer byte drift: \(name)")
            if name.hasPrefix("valid-") {
                _ = try SignedLease.verify(actual, trust: fixtureTrust, binding: fixtureBinding, replay: .initialAuthenticatedRefresh)
            } else { try refused(actual) }
        }
    }
    check("inclusive wire byte limits accept valid signed input and reject next byte") {
        let original = try signed()
        let boundedEnvelope = original + Data(repeating: 32, count: 16_384 - original.count)
        _ = try SignedLease.verify(boundedEnvelope, trust: fixtureTrust, binding: fixtureBinding, replay: .initialAuthenticatedRefresh)
        try refused(boundedEnvelope + Data([32]), reason: .malformedEnvelope)
        let payload = Data(LeaseFixture().payload.utf8)
        let boundedPayload = payload + Data(repeating: 32, count: 8_192 - payload.count)
        _ = try SignedLease.verify(signed(boundedPayload), trust: fixtureTrust, binding: fixtureBinding, replay: .initialAuthenticatedRefresh)
        try refused(signed(boundedPayload + Data([32])))
    }
    check("unique escaped ASCII keys and strings preserve exact signed semantics") {
        let payload = LeaseFixture().payload.replacingOccurrences(of: "sequence", with: "sequ\\u0065nce")
            .replacingOccurrences(of: "im.patched.mac", with: "im.patched.ma\\u0063")
        _ = try SignedLease.verify(signed(Data(payload.utf8)), trust: fixtureTrust, binding: fixtureBinding, replay: .initialAuthenticatedRefresh)
    }
    check("all evidence times use strict integer tokens and decoded-key uniqueness") {
        for state in ["trial", "grace", "paid"] {
            let f = LeaseFixture.state(state)
            let field = state == "trial" ? "startedAt" : "paidThrough"
            let needle = "\"\(field)\":\(base)"
            let actualNeedle = state == "paid" ? "\"paidThrough\":\(base + 60 * day)" : needle
            for token in ["-1", "true", "\"1\"", "1.5", "1e0", "9007199254740992"] {
                let payload = f.payload.replacingOccurrences(of: actualNeedle, with: "\"\(field)\":\(token)")
                try refused(signed(Data(payload.utf8)))
            }
            let duplicate = actualNeedle + ",\"" + String(field.dropLast()) + "\\u" + String(format: "%04x", field.utf8.last!) + "\":1"
            try refused(signed(Data(f.payload.replacingOccurrences(of: actualNeedle, with: duplicate).utf8)))
        }
    }
    check("empty default trust refuses valid fixture lease") {
        try refused(signed(), reason: .unknownKey, trust: LicenceTrust())
    }
    check("unknown signing key refuses") {
        try refused(signed(Data(LeaseFixture().payload.utf8), keyID: "unknown"), reason: .unknownKey)
    }
    check("different signing key refuses") {
        try refused(signed(Data(LeaseFixture().payload.utf8), key: otherFixtureKey), reason: .badSignature)
    }
    check("configured issuer and audience are exact") {
        for trust in [LicenceTrust(keys: ["fixture-only-1": fixtureKey.publicKey.rawRepresentation], issuer: "other"),
                      LicenceTrust(keys: ["fixture-only-1": fixtureKey.publicKey.rawRepresentation], audience: "other")] {
            try refused(signed(), trust: trust)
        }
    }
    for domain in ["im.patched.catalogue.v1", "im.patched.licence.v1 ", ""] {
        check("wrong signature domain \(domain.debugDescription) refuses") {
            try refused(signed(Data(LeaseFixture().payload.utf8), domain: domain.isEmpty ? nil : domain), reason: .badSignature)
        }
    }
    check("exact payload bytes protected including whitespace and flipped byte") {
        let original = try signed()
        let object = try JSONSerialization.jsonObject(with: original) as! [String: String]
        for payload in [LeaseFixture().payload + " ", LeaseFixture().payload.replacingOccurrences(of: "\"sequence\":2", with: "\"sequence\":3")] {
            try refused(envelope(payload: Data(payload.utf8).base64EncodedString(), signature: object["signature"]!), reason: .badSignature)
        }
        var signature = Data(base64Encoded: object["signature"]!)!; signature[0] ^= 1
        try refused(envelope(payload: object["payload"]!, signature: signature.base64EncodedString()), reason: .badSignature)
        try refused(envelope(payload: object["payload"]!, signature: Data(signature.dropLast()).base64EncodedString()))
    }
    check("signature verification precedes payload interpretation") {
        try refused(envelope(payload: Data("not JSON".utf8).base64EncodedString(), signature: Data(repeating: 0, count: 64).base64EncodedString()), reason: .badSignature)
    }
    check("canonical padded base64 required for payload and signature") {
        let object = try JSONSerialization.jsonObject(with: signed()) as! [String: String]
        let p = object["payload"]!; let s = object["signature"]!
        for bad in [s.replacingOccurrences(of: "=", with: ""), s + "=", " " + s, s + "\n", "_" + s.dropFirst(), "!!!!"] {
            try refused(envelope(payload: p, signature: bad))
        }
        // Alternate nonzero pad bits decode to the same bytes in lenient decoders.
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
        var chars = Array(s); let i = chars.count - 3
        let n = alphabet.firstIndex(of: chars[i])!; chars[i] = alphabet[n + 1]
        try refused(envelope(payload: p, signature: String(chars)))
        for bad in [p + "=", " " + p, "!!!!"] { try refused(envelope(payload: bad, signature: s)) }
    }
    check("envelope exact fields and strict encoding") {
        let good = String(decoding: try signed(), as: UTF8.self)
        let variants = [
            good.replacingOccurrences(of: "{\"keyID\":", with: "{\"extra\":1,\"keyID\":"),
            good.replacingOccurrences(of: "{\"keyID\":", with: "{\"keyID\":\"fixture-only-1\",\"keyID\":"),
            good.replacingOccurrences(of: "{\"keyID\":", with: "{\"key\\u0049D\":\"fixture-only-1\",\"keyID\":"),
            good.replacingOccurrences(of: "\"keyID\":\"fixture-only-1\",", with: ""),
            good + "{}", "[" + good + "]", "\u{feff}" + good, good + "\0",
            good.replacingOccurrences(of: "\"keyID\":\"fixture-only-1\"", with: "\"keyID\":42"),
            String(repeating: " ", count: 16_385),
            "{\"keyID\":{\"a\":{\"b\":{\"c\":{\"d\":{}}}}},\"payload\":\"\",\"signature\":\"\"}"
        ]
        for variant in variants { try refused(Data(variant.utf8), reason: .malformedEnvelope) }
        try refused(Data([0xff]) + Data(good.utf8), reason: .malformedEnvelope)
        try refused(Data(good.utf16.flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] }), reason: .malformedEnvelope)
        // Whitespace is valid within the envelope byte bound.
        _ = try SignedLease.verify(Data((" \n" + good + "\t").utf8), trust: fixtureTrust, binding: fixtureBinding, replay: .initialAuthenticatedRefresh)
    }
    let malformedTokens = ["-1", "+1", "01", "1.0", "1e0", "1E0", "true", "false", "null", "\"2\"", "9007199254740992", "18446744073709551616", "NaN"]
    for token in malformedTokens {
        check("strict integer token \(token) refuses") {
            try refused(signed(Data(LeaseFixture().payload.replacingOccurrences(of: "\"sequence\":2", with: "\"sequence\":\(token)").utf8)))
        }
    }
    check("all required payload fields present and unknown fields rejected") {
        let payload = LeaseFixture().payload
        let fields = ["schemaVersion", "issuer", "audience", "accountID", "activationID", "deviceKeySHA256", "state", "entitlementRevision", "activationRevision", "sequence", "issuedAt", "permittedUntil", "hardEnd", "paid"]
        let dictionary = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as! [String: Any]
        for field in fields {
            var copy = dictionary; copy.removeValue(forKey: field)
            try refused(signed(JSONSerialization.data(withJSONObject: copy, options: [.sortedKeys])))
        }
        try refused(signed(Data(payload.replacingOccurrences(of: "{\"schemaVersion\":", with: "{\"unknown\":1,\"schemaVersion\":").utf8)))
        for value in ["0", "2"] {
            try refused(signed(Data(payload.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":\(value)").utf8)))
        }
    }
    check("payload duplicate decoded keys, malformed strings, NUL, BOM and trailing bytes refuse") {
        let p = LeaseFixture().payload
        let variants = [p.replacingOccurrences(of: "\"sequence\":2", with: "\"sequence\":2,\"sequence\":3"),
                        p.replacingOccurrences(of: "\"sequence\":2", with: "\"sequence\":2,\"sequ\\u0065nce\":3"),
                        p.replacingOccurrences(of: "im.patched.licence", with: "im.patched.licence\\u0000"),
                        p.replacingOccurrences(of: "im.patched.licence", with: "im.patched.licence\\uD800"),
                        p.replacingOccurrences(of: "im.patched.licence", with: "im.patched.licence\\q"),
                        p.replacingOccurrences(of: "im.patched.licence", with: "im.patched.licenceé"),
                        p + "null", "\u{feff}" + p, p + "\0", "[" + p + "]", "{", ""]
        for variant in variants { try refused(signed(Data(variant.utf8)), reason: .malformedPayload) }
        try refused(signed(Data([0xff]) + Data(p.utf8)), reason: .malformedPayload)
        try refused(signed(Data((p + String(repeating: " ", count: 8193)).utf8)))
        try refused(signed(Data(p.replacingOccurrences(of: "\"sequence\":2", with: "\"sequence\":{\"a\":{\"b\":{\"c\":{\"d\":1}}}}").utf8)))
    }
    check("opaque identifier syntax and exact expected bindings") {
        for field in ["accountID", "activationID", "deviceKeySHA256"] {
            for invalid in ["", "a", String(repeating: "A", count: field == "deviceKeySHA256" ? 64 : 32), String(repeating: "g", count: field == "deviceKeySHA256" ? 64 : 32)] {
                var f = LeaseFixture()
                switch field { case "accountID": f.accountID = invalid; case "activationID": f.activationID = invalid; default: f.deviceKeySHA256 = invalid }
                try refused(signed(f))
            }
        }
        for b in [LicenceBinding(accountID: String(repeating: "d", count: 32), activationID: fixtureBinding.activationID, deviceKeySHA256: fixtureBinding.deviceKeySHA256),
                  LicenceBinding(accountID: fixtureBinding.accountID, activationID: String(repeating: "d", count: 32), deviceKeySHA256: fixtureBinding.deviceKeySHA256),
                  LicenceBinding(accountID: fixtureBinding.accountID, activationID: fixtureBinding.activationID, deviceKeySHA256: String(repeating: "d", count: 64))] {
            try refused(signed(), reason: .wrongBinding, binding: b)
        }
    }
    check("replay sequence revisions and exact cached bytes") {
        let original = try signed()
        let first = try SignedLease.verify(original, trust: fixtureTrust, binding: fixtureBinding, replay: .initialAuthenticatedRefresh)
        let checkpoint = first.checkpoint
        _ = try SignedLease.verify(original, trust: fixtureTrust, binding: fixtureBinding, replay: .cached(checkpoint))
        try refused(signed(), reason: .replay, replay: .authenticatedRefresh(after: checkpoint))
        var f = LeaseFixture(); f.sequence = 1
        try refused(signed(f), reason: .replay, replay: .authenticatedRefresh(after: checkpoint))
        f.sequence = 3
        let newer = try verified(f, replay: .authenticatedRefresh(after: checkpoint))
        try refused(signed(), reason: .replay, replay: .authenticatedRefresh(after: newer.checkpoint))
        f.sequence = 2; f.permittedUntil -= 1
        try refused(signed(f), replay: .cached(checkpoint))
        // Even an otherwise equivalent envelope is not the identical cached byte sequence.
        try refused(original + Data(" ".utf8), reason: .replay, replay: .cached(checkpoint))
        for key in ["entitlement", "activation"] {
            f = LeaseFixture(); f.sequence = 3
            if key == "entitlement" { f.entitlementRevision = 1 } else { f.activationRevision = 1 }
            try refused(signed(f), reason: .replay, replay: .authenticatedRefresh(after: checkpoint))
        }
        f = LeaseFixture(); f.sequence = 3; f.issuedAt -= 1
        try refused(signed(f), replay: .authenticatedRefresh(after: checkpoint))
    }
    check("zero sequences and revisions refuse") {
        for field in ["sequence", "entitlementRevision", "activationRevision"] {
            try refused(signed(Data(LeaseFixture().payload.replacingOccurrences(of: "\"\(field)\":2", with: "\"\(field)\":0").utf8)))
        }
    }
    check("fixed reference corpus refuses unknown exact payload or domain") {
        for (payload, domain) in [(LeaseFixture().payload + " ", "im.patched.licence.v1"),
                                  (LeaseFixture().payload, "im.patched.unknown.v1")] {
            var refusedUnknown = false
            do { _ = try fixedSigned(Data(payload.utf8), domain: domain) }
            catch is CheckFailure { refusedUnknown = true }
            try expect(refusedUnknown, "Fixed corpus must not invent signatures for unknown inputs")
        }
    }
    check("revoked activation remains terminal even with higher granting sequence") {
        var revoked = LeaseFixture.state("revoked"); revoked.sequence = 3
        let marker = try verified(revoked)
        for state in ["paid", "grace", "trial", "beta", "none", "expired"] {
            var next = LeaseFixture.state(state)
            next.sequence = 4; next.entitlementRevision = 3; next.activationRevision = 3
            try refused(signed(next), reason: .replay, replay: .authenticatedRefresh(after: marker.checkpoint))
        }
    }
    check("none and expired suppress old grant but permit valid newer state") {
        let oldBytes = try signed()
        let old = try SignedLease.verify(oldBytes, trust: fixtureTrust, binding: fixtureBinding, replay: .initialAuthenticatedRefresh)
        for state in ["none", "expired"] {
            var blocked = LeaseFixture.state(state); blocked.sequence = 3
            let marker = try verified(blocked, replay: .authenticatedRefresh(after: old.checkpoint))
            try refused(oldBytes, reason: .replay, replay: .cached(marker.checkpoint))
            try refused(oldBytes, reason: .replay, replay: .authenticatedRefresh(after: marker.checkpoint))
            var next = LeaseFixture(); next.sequence = 4
            let renewed = try verified(next, replay: .authenticatedRefresh(after: marker.checkpoint))
            try expect(LicenceGate.evaluate(.manual, lease: renewed, anchor: anchor(next), sample: sample()) == .permitted,
                       "A valid newer lease can replace none or expired")
        }
    }
    check("revoking checkpoint prevents older grants") {
        var revoked = LeaseFixture.state("revoked"); revoked.sequence = 3
        let old = try verified()
        let marker = try verified(revoked, replay: .authenticatedRefresh(after: old.checkpoint))
        try refused(signed(), reason: .replay, replay: .cached(marker.checkpoint))
        try refused(signed(), reason: .replay, replay: .authenticatedRefresh(after: marker.checkpoint))
    }
}
