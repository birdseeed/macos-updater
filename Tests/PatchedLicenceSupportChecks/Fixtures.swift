import Foundation
import CryptoKit
import CoreFoundation
@_spi(Testing) import PatchedLicenceSupport

let account = String(repeating: "a", count: 32)
let operatorID = String(repeating: "b", count: 32)
let requestID = String(repeating: "c", count: 32)
let caseID = String(repeating: "d", count: 32)
let activationID = String(repeating: "e", count: 32)
let sessionID = String(repeating: "f", count: 32)
let foreignID = String(repeating: "0", count: 32)
let now: UInt64 = 300_001
let maxExact: UInt64 = 9_007_199_254_740_991
struct Vector: Decodable { let name: String; let bytes: String; let sha256: String }
func vector(_ name: String) throws -> Vector {
    try JSONDecoder().decode(Vector.self, from: Data(contentsOf: URL(fileURLWithPath:
        "Fixtures/LicenceSupport/vectors/\(name).json")))
}
func digest(_ bytes: Data, domain: String = "im.patched.support.confirm.v1") -> String {
    SHA256.hash(data: Data(domain.utf8) + Data([0]) + bytes).map { String(format: "%02x", $0) }.joined()
}
func noteDigest(_ note: String) -> String {
    SHA256.hash(data: Data(note.utf8)).map { String(format: "%02x", $0) }.joined()
}
func descriptor(_ action: SupportAction = .deactivateActivation) throws -> Data {
    Data(try vector(action.rawValue).bytes.utf8)
}
func decoded(_ bytes: Data, at: UInt64 = now, operatorID: String = operatorID,
             expected: String? = nil) throws -> SupportConfirmation {
    try SupportConfirmation.parse(bytes, expectedDigest: expected ?? digest(bytes), operatorID: operatorID, now: at)
}
func replace(_ bytes: Data, _ old: String, _ new: String) -> Data {
    Data(String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: old, with: new).utf8)
}
func jsonString(_ text: String) -> String {
    // Independent fixture producer; deliberately not the production parser or encoder.
    let bytes = try! JSONSerialization.data(withJSONObject: [text], options: [.fragmentsAllowed, .withoutEscapingSlashes])
    return String(decoding: bytes.dropFirst().dropLast(), as: UTF8.self)
}
func withNote(_ bytes: Data, _ note: String) -> Data {
    let old = "Reviewed <b>claim</b> café"
    return replace(replace(bytes, jsonString(old), jsonString(note)), noteDigest(old), noteDigest(note))
}
func fixtureContext(_ confirmation: SupportConfirmation) -> SupportFixtureContext {
    let targetID: String
    let targetRevision: UInt64
    switch confirmation.action {
    case .deactivateActivation: targetID = activationID; targetRevision = 9
    case .resendSignInCode: targetID = account; targetRevision = 7
    case .changeAccountEmail: targetID = caseID; targetRevision = 7
    default: targetID = "sub_fixture"; targetRevision = 4
    }
    return SupportFixtureContext(kind: "operatorFixture", operatorID: operatorID,
        sessionID: sessionID, preparedSessionID: sessionID, requestID: requestID, digest: confirmation.digest,
        accountID: account, accountRevision: 7, entitlementRevision: 3,
        targetRevision: targetRevision, targetID: targetID, humanConfirmed: true)
}
func recoveryCase(_ kind: String = "paid") throws -> RecoveryCase {
    let v = try vector("recovery-case")
    let bytes = replace(Data(v.bytes.utf8), "\"paid\"", "\"\(kind)\"")
    return try RecoveryCase.parse(bytes, expectedDigest: digest(bytes, domain: "im.patched.support.recovery.v1"))
}
func recoveryConfirmation(_ recovery: RecoveryCase) throws -> SupportConfirmation {
    let original = try vector("recovery-case")
    var bytes = replace(try descriptor(.changeAccountEmail), original.sha256, recovery.digest)
    bytes = replace(bytes, "\"sourceKind\":\"paid\"", "\"sourceKind\":\"\(recovery.kind)\"")
    return try decoded(bytes)
}
func recoveryContext(_ recovery: RecoveryCase) -> RecoveryFixtureContext {
    RecoveryFixtureContext(operatorID: operatorID, accountID: account, caseID: caseID, caseDigest: recovery.digest,
        independentOwnershipJudgement: true, ownershipReference: String(repeating: "4", count: 32),
        sourceKind: recovery.kind, sourceAccountID: account, sourceVerified: true, betaInvitationVerified: true,
        activeMacPossession: true, possessionCaseDigest: recovery.digest, proofPurpose: "email-recovery",
        proofAccountID: account, proofCaseID: caseID, proofCaseDigest: recovery.digest,
        proofNewEmailHMAC: String(repeating: "6", count: 64), proofVerifiedAt: 300_000, proofExpiresAt: 300_300,
        noticeCaseDigest: recovery.digest, noticeAcceptedAt: 40_800, hold: "none", addressCollision: false,
        exceptionalLostAllMacs: false)
}
func recoveryState() -> RecoveryFixtureState {
    RecoveryFixtureState(accountID: account, accountRevision: 7, entitlementRevision: 3,
        emailHMAC: String(repeating: "5", count: 64), sessions: [sessionID: true, foreignID: true],
        activationRevisions: [activationID: 9], occupiedSlots: [1: activationID],
        trialStart: 10, trialEnd: 20, betaInvitation: String(repeating: "7", count: 32),
        paidHistory: ["opaque-period-one", "opaque-period-two"])
}
func flattened(_ value: Any, path: String = "") -> [String: String] {
    if let object = value as? [String: Any] {
        return object.reduce(into: [:]) { result, pair in result.merge(flattened(pair.value,
            path: path.isEmpty ? pair.key : path + "." + pair.key)) { _, new in new } }
    }
    if let array = value as? [Any] {
        return array.enumerated().reduce(into: [:]) { result, pair in
            result.merge(flattened(pair.element, path: path + "[\(pair.offset)]")) { _, new in new }
        }
    }
    if value is NSNull { return [path: "null"] }
    if let s = value as? String { return [path: s] }
    if let n = value as? NSNumber {
        return [path: CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true" : "false") : n.stringValue]
    }
    return [:]
}
