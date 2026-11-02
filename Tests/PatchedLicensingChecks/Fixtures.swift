import Foundation
import CryptoKit
import PatchedLicensing

// Public, deterministic TEST ONLY seeds. Never copy into a production target.
let fixtureKey = try! Curve25519.Signing.PrivateKey(rawRepresentation: Data("Patched-L1-TEST-ONLY-KEY-SEED-01".utf8))
let otherFixtureKey = try! Curve25519.Signing.PrivateKey(rawRepresentation: Data("Patched-L1-TEST-ONLY-KEY-SEED-02".utf8))
let fixtureTrust = LicenceTrust(keys: ["fixture-only-1": fixtureKey.publicKey.rawRepresentation])
let fixtureBinding = LicenceBinding(accountID: String(repeating: "a", count: 32),
                                    activationID: String(repeating: "b", count: 32),
                                    deviceKeySHA256: String(repeating: "c", count: 64))
let base: Int64 = 1_800_000_000
let day: Int64 = 86_400
let maximum: Int64 = 9_007_199_254_740_991

struct LeaseFixture {
    var state = "paid"
    var issuedAt = base
    var permittedUntil = base + 30 * day
    var hardEnd = base + 60 * day
    var evidence: String? = "\"paid\":{\"paidThrough\":\(base + 60 * day)}"
    var accountID = fixtureBinding.accountID
    var activationID = fixtureBinding.activationID
    var deviceKeySHA256 = fixtureBinding.deviceKeySHA256
    var sequence: Int64 = 2
    var entitlementRevision: Int64 = 2
    var activationRevision: Int64 = 2
    var payload: String {
        "{\"schemaVersion\":1,\"issuer\":\"im.patched.licence\",\"audience\":\"im.patched.mac\",\"accountID\":\"\(accountID)\",\"activationID\":\"\(activationID)\",\"deviceKeySHA256\":\"\(deviceKeySHA256)\",\"state\":\"\(state)\",\"entitlementRevision\":\(entitlementRevision),\"activationRevision\":\(activationRevision),\"sequence\":\(sequence),\"issuedAt\":\(issuedAt),\"permittedUntil\":\(permittedUntil),\"hardEnd\":\(hardEnd)\(evidence.map { "," + $0 } ?? "")}"
    }
    static func state(_ state: String, issued: Int64 = base, scheduledEnd: Int64? = nil) -> LeaseFixture {
        var f = LeaseFixture(); f.state = state; f.issuedAt = issued
        switch state {
        case "paid": break
        case "trial":
            f.hardEnd = base + 14 * day; f.permittedUntil = f.hardEnd
            f.evidence = "\"trial\":{\"startedAt\":\(base),\"expiresAt\":\(f.hardEnd)}"
        case "grace":
            f.hardEnd = base + 7 * day; f.permittedUntil = f.hardEnd
            f.evidence = "\"grace\":{\"paidThrough\":\(base),\"graceDeadline\":\(f.hardEnd)}"
        case "beta":
            f.permittedUntil = min(issued + 7 * day, scheduledEnd ?? maximum)
            f.hardEnd = f.permittedUntil; f.evidence = nil
        default:
            f.permittedUntil = issued; f.hardEnd = issued; f.evidence = nil
        }
        return f
    }
}
func signed(_ payload: Data, domain: String? = "im.patched.licence.v1",
            key: Curve25519.Signing.PrivateKey = fixtureKey, keyID: String = "fixture-only-1") throws -> Data {
    let prefix = domain.map { Data(($0 + "\0").utf8) } ?? Data()
    let signature = try key.signature(for: prefix + payload)
    return envelope(payload: payload.base64EncodedString(), signature: signature.base64EncodedString(), keyID: keyID)
}
func signed(_ fixture: LeaseFixture = LeaseFixture()) throws -> Data { try signed(Data(fixture.payload.utf8)) }
func envelope(payload: String, signature: String, keyID: String = "fixture-only-1") -> Data {
    Data("{\"keyID\":\"\(keyID)\",\"payload\":\"\(payload)\",\"signature\":\"\(signature)\"}".utf8)
}
func verified(_ fixture: LeaseFixture = LeaseFixture(), replay: LeaseReplay = .initialAuthenticatedRefresh) throws -> VerifiedLease {
    try SignedLease.verify(signed(fixture), trust: fixtureTrust, binding: fixtureBinding, replay: replay)
}
func anchor(_ fixture: LeaseFixture = LeaseFixture(), boot: String? = "fixture-boot-A", high: Int64? = nil) -> LicenceTimeAnchor {
    LicenceTimeAnchor(serverTime: fixture.issuedAt, monotonic: 100, boot: boot, highestObservedWall: high ?? fixture.issuedAt)
}
func sample(_ wall: Int64 = base, elapsed: Int64 = 0, boot: String? = "fixture-boot-A") -> LicenceClockSample {
    LicenceClockSample(wall: wall, monotonic: 100 + elapsed, boot: boot)
}
func decision(_ f: LeaseFixture = LeaseFixture(), at time: Int64 = base, start: ThirdPartyStart = .manual) throws -> LicenceStartDecision {
    LicenceGate.evaluate(start, lease: try verified(f), anchor: anchor(f), sample: sample(time, elapsed: time - f.issuedAt))
}
func refused(_ data: Data, reason: LicenceRefusal? = nil, trust: LicenceTrust = fixtureTrust,
             binding: LicenceBinding = fixtureBinding, replay: LeaseReplay = .initialAuthenticatedRefresh) throws {
    do {
        _ = try SignedLease.verify(data, trust: trust, binding: binding, replay: replay)
    } catch let refusal as LicenceRefusal {
        if let reason { try expect(refusal == reason, "Expected \(reason), got \(refusal)") }
        return
    }
    throw CheckFailure(description: "Invalid lease was accepted")
}
// Fixed RFC8032 reference corpus independently prepared with Node built-in crypto.
// CryptoKit signature(for:) randomises, so it remains the dynamic adversarial signer.
// This assembler covers ONLY these exact domain-plus-payload messages. It is not
// a general deterministic signing implementation or proof of Worker interoperability.
func fixedSigned(_ payload: Data, domain: String = "im.patched.licence.v1") throws -> Data {
    let message = Data((domain + "\0").utf8) + payload
    guard let encoded = deterministicFixtureSignatures[message.base64EncodedString()],
          let signature = Data(base64Encoded: encoded),
          fixtureKey.publicKey.isValidSignature(signature, for: message) else {
        throw CheckFailure(description: "Unknown exact fixture message or invalid fixed reference signature")
    }
    return envelope(payload: payload.base64EncodedString(), signature: encoded)
}
func fixedSigned(_ fixture: LeaseFixture) throws -> Data { try fixedSigned(Data(fixture.payload.utf8)) }
func verifyFixtureCorpus() throws {
    for (name, expected) in try wireVectors() {
        let actual = try Data(contentsOf: URL(fileURLWithPath: "Fixtures/Licensing/vectors/\(name).json"))
        try expect(actual == expected, "Producer byte drift: \(name)")
    }
}
private let deterministicFixtureSignatures: [String: String] = [
    "aW0ucGF0Y2hlZC5saWNlbmNlLnYxAHsic2NoZW1hVmVyc2lvbiI6MSwiaXNzdWVyIjoiaW0ucGF0Y2hlZC5saWNlbmNlIiwiYXVkaWVuY2UiOiJpbS5wYXRjaGVkLm1hYyIsImFjY291bnRJRCI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhIiwiYWN0aXZhdGlvbklEIjoiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmIiLCJkZXZpY2VLZXlTSEEyNTYiOiJjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjIiwic3RhdGUiOiJwYWlkIiwiZW50aXRsZW1lbnRSZXZpc2lvbiI6MiwiYWN0aXZhdGlvblJldmlzaW9uIjoyLCJzZXF1ZW5jZSI6Miwic2VxdVx1MDA2NW5jZSI6MywiaXNzdWVkQXQiOjE4MDAwMDAwMDAsInBlcm1pdHRlZFVudGlsIjoxODAyNTkyMDAwLCJoYXJkRW5kIjoxODA1MTg0MDAwLCJwYWlkIjp7InBhaWRUaHJvdWdoIjoxODA1MTg0MDAwfX0=": "yy35HDEDu6D8/9wPCZatIwewe42fRCM1tVmQtsVbh4phJElGOyd30AX7dlAq0HW7v643MwcbyDoE2bDdgsvXCA==",
    "aW0ucGF0Y2hlZC5saWNlbmNlLnYxAHsic2NoZW1hVmVyc2lvbiI6MSwiaXNzdWVyIjoiaW0ucGF0Y2hlZC5saWNlbmNlIiwiYXVkaWVuY2UiOiJpbS5wYXRjaGVkLm1hYyIsImFjY291bnRJRCI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhIiwiYWN0aXZhdGlvbklEIjoiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmIiLCJkZXZpY2VLZXlTSEEyNTYiOiJjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjIiwic3RhdGUiOiJiZXRhIiwiZW50aXRsZW1lbnRSZXZpc2lvbiI6MiwiYWN0aXZhdGlvblJldmlzaW9uIjoyLCJzZXF1ZW5jZSI6MiwiaXNzdWVkQXQiOjE4MDAwMDAwMDAsInBlcm1pdHRlZFVudGlsIjoxODAwNjA0ODAwLCJoYXJkRW5kIjoxODAwNjA0ODAwfQ==": "XG/AnqlOpyQeLkM0gUQoLDQ7TJZx3BLdej8hhEzcWT4EeAO+TZ9ypIHVr5sxPd/LKOT+xytaRkOWyspAPdl0Aw==",
    "aW0ucGF0Y2hlZC5saWNlbmNlLnYxAHsic2NoZW1hVmVyc2lvbiI6MSwiaXNzdWVyIjoiaW0ucGF0Y2hlZC5saWNlbmNlIiwiYXVkaWVuY2UiOiJpbS5wYXRjaGVkLm1hYyIsImFjY291bnRJRCI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhIiwiYWN0aXZhdGlvbklEIjoiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmIiLCJkZXZpY2VLZXlTSEEyNTYiOiJjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjIiwic3RhdGUiOiJleHBpcmVkIiwiZW50aXRsZW1lbnRSZXZpc2lvbiI6MiwiYWN0aXZhdGlvblJldmlzaW9uIjoyLCJzZXF1ZW5jZSI6MiwiaXNzdWVkQXQiOjE4MDAwMDAwMDAsInBlcm1pdHRlZFVudGlsIjoxODAwMDAwMDAwLCJoYXJkRW5kIjoxODAwMDAwMDAwfQ==": "7Mqk1DfH5R0eseC2MxNK7l0KWuyWCfYm5WAWDSWiVLSe54pbjk7qaXJrAgyOhkPyy5eE3L/WePmpxnIgeUeSBA==",
    "aW0ucGF0Y2hlZC5saWNlbmNlLnYxAHsic2NoZW1hVmVyc2lvbiI6MSwiaXNzdWVyIjoiaW0ucGF0Y2hlZC5saWNlbmNlIiwiYXVkaWVuY2UiOiJpbS5wYXRjaGVkLm1hYyIsImFjY291bnRJRCI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhIiwiYWN0aXZhdGlvbklEIjoiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmIiLCJkZXZpY2VLZXlTSEEyNTYiOiJjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjIiwic3RhdGUiOiJncmFjZSIsImVudGl0bGVtZW50UmV2aXNpb24iOjIsImFjdGl2YXRpb25SZXZpc2lvbiI6Miwic2VxdWVuY2UiOjIsImlzc3VlZEF0IjoxODAwMDAwMDAwLCJwZXJtaXR0ZWRVbnRpbCI6MTgwMDYwNDgwMCwiaGFyZEVuZCI6MTgwMDYwNDgwMCwiZ3JhY2UiOnsicGFpZFRocm91Z2giOjE4MDAwMDAwMDAsImdyYWNlRGVhZGxpbmUiOjE4MDA2MDQ4MDB9fQ==": "1xd3n/nkDeAjT27LinNjJuXcPBsBSylqLCPFKfJA/+IDVotrPKmgnwS7FwbX8ujUQaSSaYRIrGTgBoOyu2ukCQ==",
    "aW0ucGF0Y2hlZC5saWNlbmNlLnYxAHsic2NoZW1hVmVyc2lvbiI6MSwiaXNzdWVyIjoiaW0ucGF0Y2hlZC5saWNlbmNlIiwiYXVkaWVuY2UiOiJpbS5wYXRjaGVkLm1hYyIsImFjY291bnRJRCI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhIiwiYWN0aXZhdGlvbklEIjoiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmIiLCJkZXZpY2VLZXlTSEEyNTYiOiJjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjIiwic3RhdGUiOiJub25lIiwiZW50aXRsZW1lbnRSZXZpc2lvbiI6MiwiYWN0aXZhdGlvblJldmlzaW9uIjoyLCJzZXF1ZW5jZSI6MiwiaXNzdWVkQXQiOjE4MDAwMDAwMDAsInBlcm1pdHRlZFVudGlsIjoxODAwMDAwMDAwLCJoYXJkRW5kIjoxODAwMDAwMDAwfQ==": "zkN2AePLo3KGAh3mgNzkCOflbZ90weCGc+kKPiQGqXFiUb7u0HCSRxBxrOgf20zrH06fhM4ADmGbuzYMyMVYAA==",
    "aW0ucGF0Y2hlZC5saWNlbmNlLnYxAHsic2NoZW1hVmVyc2lvbiI6MSwiaXNzdWVyIjoiaW0ucGF0Y2hlZC5saWNlbmNlIiwiYXVkaWVuY2UiOiJpbS5wYXRjaGVkLm1hYyIsImFjY291bnRJRCI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhIiwiYWN0aXZhdGlvbklEIjoiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmIiLCJkZXZpY2VLZXlTSEEyNTYiOiJjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjIiwic3RhdGUiOiJwYWlkIiwiZW50aXRsZW1lbnRSZXZpc2lvbiI6MiwiYWN0aXZhdGlvblJldmlzaW9uIjoyLCJzZXF1ZW5jZSI6MiwiaXNzdWVkQXQiOjE4MDAwMDAwMDAsInBlcm1pdHRlZFVudGlsIjoxODAyNTkyMDAwLCJoYXJkRW5kIjoxODA1MTg0MDAwLCJwYWlkIjp7InBhaWRUaHJvdWdoIjoxODA1MTg0MDAwfX0=": "RzMbJ1uKQkWLI0VVktOld36Cgv8ZXyBHpiK7k53cR+yo+lmLFUrO7RMP8utc7t8mMWdnY+Fqx/rt3fmyQq+hBQ==",
    "aW0ucGF0Y2hlZC5saWNlbmNlLnYxAHsic2NoZW1hVmVyc2lvbiI6MSwiaXNzdWVyIjoiaW0ucGF0Y2hlZC5saWNlbmNlIiwiYXVkaWVuY2UiOiJpbS5wYXRjaGVkLm1hYyIsImFjY291bnRJRCI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhIiwiYWN0aXZhdGlvbklEIjoiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmIiLCJkZXZpY2VLZXlTSEEyNTYiOiJjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjIiwic3RhdGUiOiJyZXZva2VkIiwiZW50aXRsZW1lbnRSZXZpc2lvbiI6MiwiYWN0aXZhdGlvblJldmlzaW9uIjoyLCJzZXF1ZW5jZSI6MiwiaXNzdWVkQXQiOjE4MDAwMDAwMDAsInBlcm1pdHRlZFVudGlsIjoxODAwMDAwMDAwLCJoYXJkRW5kIjoxODAwMDAwMDAwfQ==": "x3PSI7m5bmFqaFZF1uBneCFGUYg7oqyoIphobq7BGldyTorhCzoe84DK2ZbVdMwGhIVhYA4X/YowtpJZhmyHBg==",
    "aW0ucGF0Y2hlZC5saWNlbmNlLnYxAHsic2NoZW1hVmVyc2lvbiI6MSwiaXNzdWVyIjoiaW0ucGF0Y2hlZC5saWNlbmNlIiwiYXVkaWVuY2UiOiJpbS5wYXRjaGVkLm1hYyIsImFjY291bnRJRCI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhIiwiYWN0aXZhdGlvbklEIjoiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmIiLCJkZXZpY2VLZXlTSEEyNTYiOiJjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjIiwic3RhdGUiOiJ0cmlhbCIsImVudGl0bGVtZW50UmV2aXNpb24iOjIsImFjdGl2YXRpb25SZXZpc2lvbiI6Miwic2VxdWVuY2UiOjIsImlzc3VlZEF0IjoxODAwMDAwMDAwLCJwZXJtaXR0ZWRVbnRpbCI6MTgwMTIwOTYwMCwiaGFyZEVuZCI6MTgwMTIwOTYwMCwidHJpYWwiOnsic3RhcnRlZEF0IjoxODAwMDAwMDAwLCJleHBpcmVzQXQiOjE4MDEyMDk2MDB9fQ==": "Q51yNejhrHATpyay53DF0IClejmjFQhI7OlagXdhXpT5osZDP91zs0BVou+RtN97LHD9VYHc69GjThxbQSt5Ag==",
    "aW0ucGF0Y2hlZC5saWNlbmNlLnYxAHsic2NoZW1hVmVyc2lvbiI6MSwiaXNzdWVyIjoiaW0ucGF0Y2hlZC5saWNlbmNlIiwiYXVkaWVuY2UiOiJpbS5wYXRjaGVkLm1hYyIsImFjY291bnRJRCI6ImRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkIiwiYWN0aXZhdGlvbklEIjoiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmIiLCJkZXZpY2VLZXlTSEEyNTYiOiJjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjIiwic3RhdGUiOiJwYWlkIiwiZW50aXRsZW1lbnRSZXZpc2lvbiI6MiwiYWN0aXZhdGlvblJldmlzaW9uIjoyLCJzZXF1ZW5jZSI6MiwiaXNzdWVkQXQiOjE4MDAwMDAwMDAsInBlcm1pdHRlZFVudGlsIjoxODAyNTkyMDAwLCJoYXJkRW5kIjoxODA1MTg0MDAwLCJwYWlkIjp7InBhaWRUaHJvdWdoIjoxODA1MTg0MDAwfX0=": "6tZRxD9SbQUEoGGIYt37kdTAuuVN3ZMKLMUfAd5pTHBNTx3dXplI6VmGYZT5OJ1J68h9ERc8gGn11LnqJqyYDg==",
    "aW0ucGF0Y2hlZC5saWNlbmNlLnYxAHsic2NoZW1hVmVyc2lvbiI6MSwiaXNzdWVyIjoiaW0ucGF0Y2hlZC5saWNlbmNlIiwiYXVkaWVuY2UiOiJpbS5wYXRjaGVkLm1hYyIsImFjY291bnRJRCI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhIiwiYWN0aXZhdGlvbklEIjoiZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGQiLCJkZXZpY2VLZXlTSEEyNTYiOiJjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjIiwic3RhdGUiOiJwYWlkIiwiZW50aXRsZW1lbnRSZXZpc2lvbiI6MiwiYWN0aXZhdGlvblJldmlzaW9uIjoyLCJzZXF1ZW5jZSI6MiwiaXNzdWVkQXQiOjE4MDAwMDAwMDAsInBlcm1pdHRlZFVudGlsIjoxODAyNTkyMDAwLCJoYXJkRW5kIjoxODA1MTg0MDAwLCJwYWlkIjp7InBhaWRUaHJvdWdoIjoxODA1MTg0MDAwfX0=": "NFXr3gAfjfMVn4UbIa8IRLdm9vP5qbSU8CaQuSZa6rAEEXUYVgOOTFn5CTU9Guclz7VZqt29aD3iK/L7H759BQ==",
    "aW0ucGF0Y2hlZC5saWNlbmNlLnYxAHsic2NoZW1hVmVyc2lvbiI6MSwiaXNzdWVyIjoiaW0ucGF0Y2hlZC5saWNlbmNlIiwiYXVkaWVuY2UiOiJpbS5wYXRjaGVkLm1hYyIsImFjY291bnRJRCI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhIiwiYWN0aXZhdGlvbklEIjoiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmIiLCJkZXZpY2VLZXlTSEEyNTYiOiJkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkZGRkIiwic3RhdGUiOiJwYWlkIiwiZW50aXRsZW1lbnRSZXZpc2lvbiI6MiwiYWN0aXZhdGlvblJldmlzaW9uIjoyLCJzZXF1ZW5jZSI6MiwiaXNzdWVkQXQiOjE4MDAwMDAwMDAsInBlcm1pdHRlZFVudGlsIjoxODAyNTkyMDAwLCJoYXJkRW5kIjoxODA1MTg0MDAwLCJwYWlkIjp7InBhaWRUaHJvdWdoIjoxODA1MTg0MDAwfX0=": "FywVrRRUDkNdn6VK721iXyaA+ADeB0VTBIJdDADyTE1mKGhucQQiG717Jg+77MghI3I6z84DibS7MdzrF3p6AA==",
    "aW0ucGF0Y2hlZC5jYXRhbG9ndWUudjEAeyJzY2hlbWFWZXJzaW9uIjoxLCJpc3N1ZXIiOiJpbS5wYXRjaGVkLmxpY2VuY2UiLCJhdWRpZW5jZSI6ImltLnBhdGNoZWQubWFjIiwiYWNjb3VudElEIjoiYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWEiLCJhY3RpdmF0aW9uSUQiOiJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYiIsImRldmljZUtleVNIQTI1NiI6ImNjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2MiLCJzdGF0ZSI6InBhaWQiLCJlbnRpdGxlbWVudFJldmlzaW9uIjoyLCJhY3RpdmF0aW9uUmV2aXNpb24iOjIsInNlcXVlbmNlIjoyLCJpc3N1ZWRBdCI6MTgwMDAwMDAwMCwicGVybWl0dGVkVW50aWwiOjE4MDI1OTIwMDAsImhhcmRFbmQiOjE4MDUxODQwMDAsInBhaWQiOnsicGFpZFRocm91Z2giOjE4MDUxODQwMDB9fQ==": "8lXIsYDRbasBA7yQm2Iks5VFDPAWHmOdDOBheY5hqmBfCJkJBPlOpClNyA/xpN8GOv3um3lxjAz2g0MqY66zDQ=="
]

func wireVectors() throws -> [(String, Data)] {
    var result: [(String, Data)] = []
    for state in ["paid", "grace", "trial", "beta", "none", "expired", "revoked"] {
        result.append(("valid-\(state)", try fixedSigned(.state(state))))
    }
    var foreign = LeaseFixture(); foreign.accountID = String(repeating: "d", count: 32)
    result.append(("wrong-account", try fixedSigned(foreign)))
    foreign = LeaseFixture(); foreign.activationID = String(repeating: "d", count: 32)
    result.append(("wrong-activation", try fixedSigned(foreign)))
    foreign = LeaseFixture(); foreign.deviceKeySHA256 = String(repeating: "d", count: 64)
    result.append(("wrong-device-key", try fixedSigned(foreign)))
    result.append(("wrong-domain", try fixedSigned(Data(LeaseFixture().payload.utf8), domain: "im.patched.catalogue.v1")))
    result.append(("duplicate-escaped-key", try fixedSigned(Data(LeaseFixture().payload.replacingOccurrences(of: "\"sequence\":2", with: "\"sequence\":2,\"sequ\\u0065nce\":3").utf8))))
    return result
}
