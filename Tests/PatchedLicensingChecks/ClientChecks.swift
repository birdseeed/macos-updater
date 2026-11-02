import Foundation
import PatchedLicensing

@MainActor final class FakeSessions: SessionStore {
    var value: LicenceSession? = LicenceSession(binding: fixtureBinding, generation: 1)
    func currentSession() -> LicenceSession? { value }
    func signIn(_ binding: LicenceBinding = fixtureBinding, generation: UInt64 = 2) {
        value = LicenceSession(binding: binding, generation: generation)
    }
}
@MainActor final class FakeClock: LicenceClockSource {
    var value = LicenceClockSample(wall: base, monotonic: 100, boot: "fixture-boot-A")
    var observations = 0
    func sample() -> LicenceClockSample { observations += 1; return value }
}
@MainActor final class FakeTransport: LicenceTransport {
    var result: LicenceTransportResult = .failure(.http(503))
    var calls: [LicenceSession] = []
    var duringRequest: (() throws -> Void)?
    func refresh(session: LicenceSession) throws -> LicenceTransportResult {
        calls.append(session)
        try duringRequest?()
        return result
    }
}

func freshFixture(sequence: Int64 = 3, state: String = "paid") -> LeaseFixture {
    var value = LeaseFixture.state(state)
    value.sequence = sequence
    return value
}
func response(_ fixture: LeaseFixture = freshFixture()) throws -> LicenceTransportResult {
    .response(status: 200, body: try signed(fixture), contentType: "application/json", validatedTLS: true)
}

@MainActor final class ClientRig {
    let sessions = FakeSessions()
    let clock = FakeClock()
    let transport = FakeTransport()
    let cache: FakeLicenceCache
    init(_ fixture: LeaseFixture = LeaseFixture()) throws { cache = try FakeLicenceCache(fixture) }
    func client(trust: LicenceTrust = fixtureTrust) -> LicenceClient {
        LicenceClient(transport: transport, sessions: sessions, cache: cache, clock: clock, trust: trust)
    }
    func expectClosed(_ client: LicenceClient, _ message: String) throws {
        for start in ThirdPartyStart.allCases {
            try expect(client.decision(for: start) != .permitted, message)
        }
    }
}

@MainActor func registerClientChecks() {
    check("L2 valid own-request newer refresh atomically permits all new starts") {
        let rig = try ClientRig(); rig.transport.result = try response()
        let client = rig.client()
        try expect(client.refresh() == .permitted, "Valid newer authenticated fixture response must permit")
        try expect(rig.transport.calls.count == 1, "Must use injected own-request transport")
        let record = try rig.cache.record()
        try expect(record.state.safety.inFlight == nil && !record.state.safety.verificationBlocked,
                   "Successful acceptance must clear its durable fence/block")
        let accepted = try SignedLease.verify(record.state.envelope!, trust: fixtureTrust,
            binding: fixtureBinding, replay: .cached(record.state.safety.checkpoint))
        try expect(accepted.sequence == 3, "Cache and replay checkpoint must advance together")
        for start in ThirdPartyStart.allCases {
            try expect(client.decision(for: start) == .permitted, "Each third-party start uses accepted state")
        }
    }
    for failure in [LicenceRefreshOutcome.noRoute, .dnsFailure, .connectTimeout, .readTimeout,
                    .connectionReset, .http(429), .http(500), .http(502), .http(503), .http(504)] {
        check("L2 bounded cached outage succeeds for \(failure)") {
            let rig = try ClientRig(); rig.clock.value = sample(base + 1, elapsed: 1)
            rig.transport.result = .failure(failure)
            let original = try rig.cache.record().state.envelope
            try expect(rig.client().refresh() == .permitted, "Eligible outage must retain a valid same-boot grant")
            let state = try rig.cache.record().state
            try expect(state.envelope == original && state.anchor?.serverTime == base,
                       "Outage must neither mint bytes nor re-anchor time")
            try expect(state.safety.inFlight == nil, "Outage fence must be durably resolved")
        }
    }
    check("L2 validated TLS HTTP503 response permits bounded cached fallback") {
        let rig = try ClientRig()
        rig.transport.result = .response(status: 503, body: Data(), contentType: "text/plain", validatedTLS: true)
        try expect(rig.client().refresh() == .permitted, "Validated TLS outage status may fall back without a lease body")
    }
    let refusedResponses: [(String, () throws -> LicenceTransportResult)] = [
        ("401", { .failure(.http(401)) }), ("403", { .failure(.http(403)) }),
        ("TLS", { .failure(.tlsFailure) }), ("authentication", { .failure(.authenticationFailure) }),
        ("unvalidated TLS 503", { .response(status: 503, body: Data(), contentType: "application/json", validatedTLS: false) }),
        ("unvalidated TLS 200", { .response(status: 200, body: try signed(freshFixture()), contentType: "application/json", validatedTLS: false) }),
        ("wrong content type", { .response(status: 200, body: try signed(freshFixture()), contentType: "text/html", validatedTLS: true) }),
        ("malformed", { .response(status: 200, body: Data("{}".utf8), contentType: "application/json", validatedTLS: true) }),
        ("bad signature", { .response(status: 200, body: try signed(Data(freshFixture().payload.utf8), key: otherFixtureKey), contentType: "application/json", validatedTLS: true) }),
        ("unknown key", { .response(status: 200, body: try signed(Data(freshFixture().payload.utf8), keyID: "unknown-fixture"), contentType: "application/json", validatedTLS: true) }),
        ("oversized", { .response(status: 200, body: Data(repeating: 32, count: 16_385), contentType: "application/json", validatedTLS: true) }),
        ("foreign account", { var f = freshFixture(); f.accountID = String(repeating: "d", count: 32); return try response(f) }),
        ("foreign activation", { var f = freshFixture(); f.activationID = String(repeating: "d", count: 32); return try response(f) }),
        ("foreign key", { var f = freshFixture(); f.deviceKeySHA256 = String(repeating: "d", count: 64); return try response(f) }),
        ("stale sequence", { try response(freshFixture(sequence: 1)) }),
        ("equal sequence conflicting bytes", { var f = freshFixture(sequence: 2); f.permittedUntil -= 1; return try response(f) }),
        ("lower entitlement revision", { var f = freshFixture(); f.entitlementRevision = 1; return try response(f) }),
        ("lower activation revision", { var f = freshFixture(); f.activationRevision = 1; return try response(f) })
    ]
    for (name, makeResponse) in refusedResponses {
        check("L2 \(name) then restart/outage cannot resurrect cache") {
            let rig = try ClientRig(); rig.transport.result = try makeResponse()
            try expect(rig.client().refresh() == .verificationRequired, "Invalid response must refuse")
            let state = try rig.cache.record().state
            try expect(state.safety.verificationBlocked || state.safety.inFlight != nil,
                       "Refusal must survive process loss independently of cached bytes")
            rig.sessions.signIn(); rig.transport.result = .failure(.http(503))
            try expect(rig.client().refresh() == .verificationRequired, "New sign-in plus outage must preserve block")
            try rig.expectClosed(rig.client(), "Restart cannot revive old grant")
        }
    }
    check("L2 same-binding sign-in preserves markers until a newer own response") {
        let rig = try ClientRig(); rig.transport.result = .failure(.http(401))
        _ = rig.client().refresh(); rig.sessions.signIn()
        try expect(try rig.cache.record().state.safety.verificationBlocked, "Signing in must not erase refusal")
        rig.transport.result = try response(freshFixture(sequence: 2))
        try expect(rig.client().refresh() == .verificationRequired, "Equal response cannot clear the block")
        rig.transport.result = try response()
        try expect(rig.client().refresh() == .permitted, "New sign-in may recover through a valid newer response")
    }
    for change in ["cancel", "account", "activation", "key", "same binding generation", "switch away and back"] {
        check("L2 \(change) during request rejects old response") {
            let rig = try ClientRig(); rig.transport.result = try response()
            rig.transport.duringRequest = {
                switch change {
                case "cancel": rig.sessions.value = nil
                case "account": rig.sessions.signIn(LicenceBinding(accountID: String(repeating: "d", count: 32), activationID: fixtureBinding.activationID, deviceKeySHA256: fixtureBinding.deviceKeySHA256))
                case "activation": rig.sessions.signIn(LicenceBinding(accountID: fixtureBinding.accountID, activationID: String(repeating: "d", count: 32), deviceKeySHA256: fixtureBinding.deviceKeySHA256))
                case "key": rig.sessions.signIn(LicenceBinding(accountID: fixtureBinding.accountID, activationID: fixtureBinding.activationID, deviceKeySHA256: String(repeating: "d", count: 64)))
                case "switch away and back":
                    rig.sessions.signIn(LicenceBinding(accountID: String(repeating: "d", count: 32), activationID: fixtureBinding.activationID, deviceKeySHA256: fixtureBinding.deviceKeySHA256))
                    rig.sessions.signIn(generation: 3)
                default: rig.sessions.signIn(generation: 3)
                }
            }
            try expect(rig.client().refresh() == .verificationRequired, "Old response cannot apply after session change")
            try expect(rig.transport.calls.count == 1, "Scenario must actually cross the request boundary")
            let state = try rig.cache.record().state
            try expect(state.safety.inFlight != nil || state.safety.verificationBlocked, "Old response must not clear safety fence")
            rig.transport.duringRequest = nil; rig.sessions.signIn(generation: 4)
            rig.transport.result = .failure(.http(503))
            try expect(rig.client().refresh() == .verificationRequired, "Returning to original binding cannot resurrect grant")
        }
    }
    check("L2 terminal revocation survives cached-byte loss restart and paid renewal") {
        let rig = try ClientRig(); rig.transport.result = try response(freshFixture(state: "revoked"))
        try expect(rig.client().refresh() == .revoked, "Verified revocation is authoritative")
        try expect(try rig.cache.record().state.safety.terminalRevocation, "Terminal marker must be separate")
        rig.cache.mutate { $0.envelope = nil; $0.anchor = nil }
        rig.sessions.signIn(); rig.transport.result = try response(freshFixture(sequence: 4))
        try expect(rig.client().refresh() == .revoked, "Paid renewal cannot reactivate a revoked activation")
        rig.transport.result = .failure(.http(503))
        try expect(rig.client().refresh() == .revoked, "Restart/outage remains revoked without cached bytes")
    }
    for state in ["none", "expired"] {
        check("L2 authoritative \(state) suppresses old grant but valid newer paid can recover") {
            let rig = try ClientRig(); rig.transport.result = try response(freshFixture(state: state))
            let expected: LicenceStartDecision = state == "none" ? .noEntitlement : .expired
            try expect(rig.client().refresh() == expected, "Signed denial must replace previous grant")
            rig.transport.result = .failure(.http(503))
            try expect(rig.client().refresh() == expected, "Outage cannot resurrect superseded paid lease")
            rig.transport.result = try response(freshFixture(sequence: 4))
            try expect(rig.client().refresh() == .permitted, "Nonterminal denial can recover with newer authority")
        }
    }
    check("L2 new client default trust and signed-out session refuse") {
        let rig = try ClientRig(); rig.transport.result = try response()
        try expect(rig.client(trust: LicenceTrust()).refresh() == .verificationRequired, "Default trust refuses")
        let second = try ClientRig(); second.sessions.value = nil
        try expect(second.client().refresh() == .verificationRequired && second.transport.calls.isEmpty,
                   "No authenticated session means no request")
        try second.expectClosed(second.client(), "No session may borrow established cache")
    }
}
