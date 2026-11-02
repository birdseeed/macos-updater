import Foundation
import CryptoKit
@_spi(Testing) import PatchedLicenceSupport
@_spi(Testing) import PatchedLicenceSupportUI

let account = String(repeating: "a", count: 32)
let operatorID = String(repeating: "b", count: 32)
let requestID = String(repeating: "c", count: 32)
let activationID = String(repeating: "e", count: 32)
let sessionID = String(repeating: "f", count: 32)
let foreignID = String(repeating: "0", count: 32)
let now: UInt64 = 300_001
struct Vector: Decodable { let bytes: String; let sha256: String }
func fixture(_ action: SupportAction = .deactivateActivation, transform: (String) -> String = { $0 }) throws -> SupportConfirmation {
    let vector = try JSONDecoder().decode(Vector.self, from: Data(contentsOf: URL(fileURLWithPath:
        "Fixtures/LicenceSupport/vectors/\(action.rawValue).json")))
    let bytes = Data(transform(vector.bytes).utf8)
    let digest = SHA256.hash(data: Data("im.patched.support.confirm.v1".utf8) + Data([0]) + bytes)
        .map { String(format: "%02x", $0) }.joined()
    return try SupportConfirmation.parse(bytes, expectedDigest: digest, operatorID: operatorID, now: now)
}
func context(_ c: SupportConfirmation) -> SupportFixtureContext {
    let target: String; let revision: UInt64
    switch c.target {
    case .activation(let t): target = t.activationID; revision = t.activationRevision
    case .provider(let t): target = t.subscriptionID; revision = t.subscriptionRevision
    case .account(let t): target = t.accountID; revision = t.accountRevision
    case .recovery(let t): target = t.caseID; revision = t.account.accountRevision
    }
    return SupportFixtureContext(kind: "operatorFixture", operatorID: c.operatorID, sessionID: sessionID,
        preparedSessionID: sessionID, requestID: c.requestID, digest: c.digest, accountID: c.account.accountID,
        accountRevision: c.account.accountRevision, entitlementRevision: c.account.entitlementRevision,
        targetRevision: revision, targetID: target, humanConfirmed: false)
}
func readback(_ c: SupportConfirmation, status: LicenceSupportFixtureReadback.Status = .confirmed,
              time: UInt64 = now, accountID: String = account, digest: String? = nil,
              bytes: Data? = nil, action: SupportAction? = nil, targetID: String? = nil,
              accountRevision: UInt64 = 7, entitlementRevision: UInt64 = 3, targetRevision: UInt64? = nil) -> LicenceSupportFixtureReadback {
    let x = context(c)
    return LicenceSupportFixtureReadback(accountID: accountID, action: action ?? c.action,
        targetID: targetID ?? x.targetID, descriptorDigest: digest ?? c.digest, descriptorBytes: bytes ?? c.descriptorBytes,
        observedAt: time, accountRevision: accountRevision, entitlementRevision: entitlementRevision,
        targetRevision: targetRevision ?? x.targetRevision, status: status)
}
final class FakeClient: SupportClient {
    var confirmation: SupportConfirmation
    var lookupValue: SupportPresentation
    var lookupError: Error?
    var prepareError: Error?
    var commitError: Error?
    var commitOutcome: SupportOutcome = .committed
    var lookupCount = 0; var prepareCount = 0; var commits: [(String, String)] = []
    var afterCommit: (() -> Void)?
    var afterLookup: (() -> Void)?
    init(_ c: SupportConfirmation) throws { confirmation = c; lookupValue = try .confirmation(c) }
    func lookup(accountID: String) throws -> SupportPresentation {
        lookupCount += 1; afterLookup?()
        if let lookupError { throw lookupError }; return lookupValue
    }
    func prepare(action: SupportAction, accountID: String) throws -> SupportConfirmation {
        prepareCount += 1
        if let prepareError { throw prepareError }; return confirmation
    }
    func commit(requestID: String, digest: String) throws -> SupportOutcome {
        commits.append((requestID, digest)); afterCommit?()
        if let commitError { throw commitError }; return commitOutcome
    }
}
@MainActor func loaded(_ c: SupportConfirmation, edit: (inout SupportFixtureContext) -> Void = { _ in },
    readback: @escaping (SupportConfirmation) throws -> LicenceSupportFixtureReadback? = { _ in nil }) throws -> (LicenceSupportController, FakeClient) {
    let fake = try FakeClient(c); var x = context(c); edit(&x)
    let ui = LicenceSupportController(client: fake, context: x, now: now, readback: readback)
    ui.lookup(accountID: account)
    return (ui, fake)
}
@MainActor func confirm(_ ui: LicenceSupportController, _ c: SupportConfirmation) {
    ui.confirm(descriptorBytes: c.descriptorBytes, digest: c.digest)
}
