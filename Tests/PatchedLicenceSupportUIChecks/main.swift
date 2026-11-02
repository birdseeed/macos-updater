import Foundation
import Darwin
import SwiftUI
import AppKit
import ImageIO
@_spi(Testing) import PatchedLicenceSupport
@_spi(Testing) import PatchedLicenceSupportUI

struct Failure: Error, CustomStringConvertible { let description: String }
func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw Failure(description: message) }
}
var checks: [(String, @MainActor () throws -> Void)] = []
@MainActor func check(_ name: String, _ body: @escaping @MainActor () throws -> Void) { checks.append((name, body)) }
@MainActor func words(_ ui: LicenceSupportController) -> String { LicenceSupportViewText(ui).accessibilityText }

check("ordinary configuration refuses lookup prepare and commit") {
    let ui = LicenceSupportController(); let c = try fixture()
    try expect(!ui.canConfirm && ui.state == .idle, "default is not read-only")
    ui.lookup(accountID: account); ui.prepare(action: .deactivateActivation); confirm(ui, c)
    try expect(ui.state == .failed && !ui.canConfirm && ui.displayedDescriptorBytes == nil, "default permits action")
}
check("lookup never prepares or commits and starts read-only") {
    let (ui, fake) = try loaded(fixture())
    try expect(ui.state == .readOnly && !ui.canConfirm, "lookup is not read-only")
    try expect(fake.lookupCount == 1 && fake.prepareCount == 0 && fake.commits.isEmpty, "lookup mutated")
}
for action in SupportAction.allCases where action != .changeAccountEmail {
    check("exact display and explicit click for \(action)") {
        let c = try fixture(action); let (ui, fake) = try loaded(c)
        ui.prepare(action: action)
        try expect(ui.state == .confirmation && ui.canConfirm, "confirmation absent")
        try expect(ui.displayedDescriptorBytes == c.descriptorBytes && ui.displayedDigest == c.digest, "display binding lost")
        try expect(fake.commits.isEmpty, "prepare committed")
        let text = words(ui)
        for id in [account, operatorID, requestID] { try expect(text.contains(id), "full safe identifier omitted: \(id)") }
        try expect(text.contains(c.digest), "digest absent")
        for sentence in try SupportPresentation.confirmation(c).consequenceWords {
            try expect(text.contains(sentence), "consequence missing")
        }
        confirm(ui, c)
        try expect(fake.commits.count == 1 && fake.commits[0].0 == requestID && fake.commits[0].1 == c.digest,
                   "exact explicit click not delivered")
        try expect(fake.lookupCount == 2, "truthful refresh absent")
        try expect(ui.state == (action == .initiateCancellation || action == .initiateRefund || action == .reconcileProviderState ? .requested : .confirmed), "outcome overclaims")
    }
}
for action in SupportAction.allCases {
    check("secret leaves never paint \(action)") {
        let c = try fixture(action); let (ui, _) = try loaded(c); ui.prepare(action: action)
        let text = words(ui)
        for secret in ["AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=", "Reviewed <b>claim</b> café", c.reasonNoteSHA256,
                       "sourceVerified", "independentOwnershipJudgement", "newEmailHMAC", "possessionProof", "nonce"] {
            try expect(!text.contains(secret), "secret/evidence/claim leaked: \(secret)")
        }
    }
}
let invalidContexts: [(String, (inout SupportFixtureContext) -> Void)] = [
    ("consumer", { $0.kind = "consumer" }), ("missing operator", { $0.operatorID = "" }),
    ("foreign operator", { $0.operatorID = foreignID }), ("foreign customer", { $0.accountID = foreignID }),
    ("changed account revision", { $0.accountRevision += 1 }), ("changed entitlement revision", { $0.entitlementRevision += 1 }),
    ("changed target revision", { $0.targetRevision += 1 }), ("foreign target", { $0.targetID = foreignID }),
    ("stale session", { $0.sessionID = foreignID }), ("empty session", { $0.sessionID = "" }),
    ("foreign request", { $0.requestID = foreignID }), ("foreign digest", { $0.digest = String(repeating: "0", count: 64) })]
for (name, edit) in invalidContexts {
    check("invalid preparation refuses \(name)") {
        let c = try fixture(); let (ui, fake) = try loaded(c, edit: edit)
        ui.prepare(action: c.action); confirm(ui, c)
        try expect(!ui.canConfirm && fake.commits.isEmpty && ui.state == .failed, "invalid context acts")
    }
    check("context change invalidates displayed confirmation: \(name)") {
        let c = try fixture(); let (ui, fake) = try loaded(c); ui.prepare(action: c.action)
        var x = context(c); edit(&x); ui.update(context: x, now: now)
        try expect(!ui.canConfirm && ui.displayedDescriptorBytes == nil, "stale descriptor retained")
        confirm(ui, c); try expect(fake.commits.isEmpty, "stale click acts")
    }
}
for at: UInt64 in [299_999, 300_300, 300_301, UInt64.max] {
    check("outside exact confirmation clock boundary \(at)") {
        let c = try fixture(); let (ui, fake) = try loaded(c); ui.update(context: context(c), now: at)
        ui.prepare(action: c.action); confirm(ui, c)
        try expect(!ui.canConfirm && fake.commits.isEmpty, "out of bounds time acts")
    }
}
for at: UInt64 in [300_000, 300_299] {
    check("inside exact confirmation clock boundary \(at)") {
        let c = try fixture(); let (ui, fake) = try loaded(c); ui.update(context: context(c), now: at)
        ui.prepare(action: c.action); try expect(ui.canConfirm, "valid boundary refuses")
        confirm(ui, c); try expect(fake.commits.count == 1, "valid boundary never acts")
    }
}
check("time change invalidates displayed bytes even within interval") {
    let c = try fixture(); let (ui, fake) = try loaded(c); ui.prepare(action: c.action)
    ui.update(context: context(c), now: now + 1); confirm(ui, c)
    try expect(!ui.canConfirm && fake.commits.isEmpty, "old display survives time update")
}
check("foreign lookup never prepares or reveals target") {
    let c = try fixture(); let (ui, fake) = try loaded(c); ui.lookup(accountID: foreignID)
    ui.prepare(action: c.action); confirm(ui, c)
    try expect(fake.commits.isEmpty && !words(ui).contains(account), "foreign lookup exposes/acts")
}
check("wrong action returned from prepare refuses") {
    let c = try fixture(); let (ui, fake) = try loaded(c); ui.prepare(action: .initiateRefund); confirm(ui, c)
    try expect(!ui.canConfirm && fake.commits.isEmpty, "wrong action acts")
}
for variant in ["bytes", "digest", "before display"] {
    check("explicit click refuses \(variant)") {
        let c = try fixture(); let (ui, fake) = try loaded(c)
        if variant != "before display" { ui.prepare(action: c.action) }
        ui.confirm(descriptorBytes: variant == "bytes" ? c.descriptorBytes + Data([32]) : c.descriptorBytes,
                   digest: variant == "digest" ? String(repeating: "0", count: 64) : c.digest)
        try expect(fake.commits.isEmpty, "unbound click acts")
    }
}
check("humanConfirmed before preparation does not trigger action") {
    let c = try fixture(); let (ui, fake) = try loaded(c, edit: { $0.humanConfirmed = true })
    ui.prepare(action: c.action); try expect(fake.commits.isEmpty, "pre-display auth auto acts")
    confirm(ui, c); try expect(fake.commits.count == 1, "explicit post-display click refused")
}
check("successful duplicate click and prepare do not repeat mutation") {
    let c = try fixture(); let (ui, fake) = try loaded(c)
    ui.prepare(action: c.action); confirm(ui, c); confirm(ui, c)
    ui.prepare(action: c.action); confirm(ui, c)
    try expect(fake.commits.count == 1, "confirmed request was redispatched")
}
check("foreign customer returned by lookup is suppressed") {
    let c = try fixture(); let other = try fixture(transform: { $0.replacingOccurrences(of: account, with: foreignID) })
    let (ui, fake) = try loaded(c); fake.lookupValue = try .confirmation(other)
    ui.lookup(accountID: account); ui.prepare(action: c.action); confirm(ui, c)
    try expect(ui.state == .failed && fake.commits.isEmpty && !words(ui).contains(foreignID), "foreign lookup revealed")
}
check("lookup allowlist exposes only bounded safe descriptor fields") {
    let c = try fixture(); let (ui, _) = try loaded(c)
    let safe: Set<String> = ["requestID", "operatorID", "action", "accountID", "accountRevision", "entitlementRevision",
        "maskedEmail", "preparedAt", "expiresAt", "target.activationID", "target.slot", "target.activationRevision",
        "target.createdAt", "target.lastRefreshAt", "target.cachedLease.state", "target.cachedLease.issuedAt",
        "target.cachedLease.permittedUntil", "target.cachedLease.hardEnd", "target.maxGrantPermittedUntil", "descriptorDigest"]
    try expect(!ui.rows.isEmpty && ui.rows.allSatisfy { safe.contains($0.label) && $0.value.utf8.count <= 254 }, "unbounded or non-whitelisted lookup row")
    ui.prepare(action: c.action)
    try expect(ui.rows.allSatisfy { safe.contains($0.label) }, "non-whitelisted confirmation row")
    for label in ["target.activationID", "target.maxGrantPermittedUntil", "target.cachedLease.permittedUntil", "target.slot"] {
        try expect(ui.rows.contains { $0.label == label }, "critical target/grant limit absent: \(label)")
    }
}
for error in [SupportError.unknownOutcome, .rollback, .notConfigured, .targetChanged] {
    check("commit error remains truthful and retry does not redispatch \(error)") {
        let c = try fixture(.initiateRefund); let (ui, fake) = try loaded(c)
        fake.commitError = error; ui.prepare(action: c.action); confirm(ui, c); confirm(ui, c)
        ui.prepare(action: c.action); confirm(ui, c)
        try expect(fake.commits.count == 1, "retry redispatched same prepared action")
        try expect(ui.state == (error == .unknownOutcome ? .unknown : .failed), "commit error overclaims")
        try expect(!words(ui).contains(error.rawValue), "raw error exposed")
    }
}
check("target changed commit never claims success") {
    let c = try fixture(); let (ui, fake) = try loaded(c); fake.commitOutcome = .targetChanged
    ui.prepare(action: c.action); confirm(ui, c)
    try expect(ui.state == .failed && !ui.canConfirm, "target change claims success")
}
check("lookup/prepare failures suppress raw server messages") {
    struct Secret: Error, CustomStringConvertible { var description: String { "code=123456 secret=fixture" } }
    let c = try fixture(); let (ui, fake) = try loaded(c); fake.prepareError = Secret()
    ui.prepare(action: c.action); try expect(ui.state == .failed && !words(ui).contains("123456"), "prepare secret leaked")
    fake.lookupError = Secret(); ui.lookup(accountID: account)
    try expect(ui.state == .failed && !words(ui).contains("secret=fixture"), "lookup secret leaked")
}
check("successful commit with refresh failure is unknown") {
    let c = try fixture(); let (ui, fake) = try loaded(c)
    fake.afterCommit = { fake.lookupError = SupportError.unknownOutcome }
    ui.prepare(action: c.action); confirm(ui, c)
    try expect(ui.state == .unknown && fake.lookupCount == 2, "failed refresh claims verified success")
}
check("refresh replaces old safe facts") {
    let c = try fixture(); let replacement = try fixture(transform: { $0.replacingOccurrences(of: "\"slot\":1", with: "\"slot\":2") })
    let (ui, fake) = try loaded(c); fake.afterCommit = { fake.lookupValue = try! .confirmation(replacement) }
    ui.prepare(action: c.action); confirm(ui, c)
    try expect(ui.rows.contains { $0.label == "target.slot" && $0.value == "2" }, "old lookup facts remain")
}
check("foreign refresh after committed action remains unknown and suppresses foreign facts") {
    let c = try fixture(); let other = try fixture(transform: { $0.replacingOccurrences(of: account, with: foreignID) })
    let (ui, fake) = try loaded(c)
    fake.afterCommit = { fake.lookupValue = try! .confirmation(other) }
    ui.prepare(action: c.action); confirm(ui, c)
    try expect(ui.state == .unknown && !words(ui).contains(foreignID), "foreign refresh confirms or leaks")
}
check("provider readback context race cannot confirm") {
    let c = try fixture(.initiateRefund)
    var controller: LicenceSupportController?
    let (ui, _) = try loaded(c, readback: { value in
        var x = context(value); x.accountRevision += 1
        controller?.update(context: x, now: now)
        return readback(value)
    })
    controller = ui
    ui.prepare(action: c.action); confirm(ui, c)
    try expect(ui.state == .unknown && !ui.canConfirm, "changed context accepted readback")
}
for status: LicenceSupportFixtureReadback.Status in [.pending, .unknown, .failed, .confirmed] {
    check("closed separately bound provider status \(status)") {
        let c = try fixture(.initiateRefund); let (ui, _) = try loaded(c, readback: { readback($0, status: status) })
        ui.prepare(action: c.action); confirm(ui, c)
        let expected: LicenceSupportUIState = switch status { case .pending: .requested; case .unknown: .unknown; case .failed: .failed; case .confirmed: .confirmed }
        try expect(ui.state == expected, "provider status misrepresented")
    }
}
let mismatches: [(String, (SupportConfirmation) -> LicenceSupportFixtureReadback)] = [
    ("account", { readback($0, accountID: foreignID) }), ("action", { readback($0, action: .initiateCancellation) }),
    ("target", { readback($0, targetID: "sub_foreign") }), ("digest", { readback($0, digest: String(repeating: "0", count: 64)) }),
    ("bytes", { readback($0, bytes: $0.descriptorBytes + Data([32])) }),
    ("stale time", { readback($0, time: now - 1) }), ("future time", { readback($0, time: now + 1) }),
    ("account revision", { readback($0, accountRevision: 8) }), ("entitlement revision", { readback($0, entitlementRevision: 4) }),
    ("target revision", { readback($0, targetRevision: 5) })]
for (name, make) in mismatches {
    check("provider readback mismatch remains unknown \(name)") {
        let c = try fixture(.initiateRefund); let (ui, _) = try loaded(c, readback: { make($0) })
        ui.prepare(action: c.action); confirm(ui, c); try expect(ui.state == .unknown, "unbound provider result trusted")
    }
}
check("throwing provider readback stays unknown") {
    let c = try fixture(.initiateRefund); let (ui, _) = try loaded(c, readback: { _ in throw SupportError.unknownOutcome })
    ui.prepare(action: c.action); confirm(ui, c); try expect(ui.state == .unknown, "readback outage confirmed")
}
check("context race while refreshing stays unknown") {
    let c = try fixture(.initiateRefund); let (ui, fake) = try loaded(c, readback: { readback($0) })
    fake.afterCommit = { fake.afterLookup = { var x = context(c); x.sessionID = foreignID; ui.update(context: x, now: now) } }
    ui.prepare(action: c.action); confirm(ui, c); try expect(ui.state == .unknown, "refresh race confirms foreign session")
}
check("exceptional recovery unavailable despite a fully populated descriptor and pre-existing confirmation") {
    let c = try fixture(.changeAccountEmail); let (ui, fake) = try loaded(c, edit: { $0.humanConfirmed = true })
    ui.prepare(action: c.action); confirm(ui, c)
    try expect(!ui.recoveryAvailable && !ui.canConfirm && fake.commits.isEmpty, "unsupported recovery acts")
    try expect(words(ui).contains("Account recovery is unavailable."), "recovery limitation absent")
}
check("literal masked identifier includes markdown punctuation without interpretation") {
    let c = try fixture(.resendSignInCode, transform: { $0.replacingOccurrences(of: "o***@example.invalid", with: "`***@example.invalid") })
    let (ui, _) = try loaded(c); ui.prepare(action: c.action)
    try expect(words(ui).contains("`***@example.invalid"), "literal punctuation changed")
}
check("full long safe provider identifier remains accessible and unellipsised") {
    let id = String(repeating: "x", count: 128)
    let c = try fixture(.initiateRefund, transform: { $0.replacingOccurrences(of: "sub_fixture", with: id) })
    let (ui, _) = try loaded(c); ui.prepare(action: c.action)
    try expect(words(ui).contains(id) && !words(ui).contains("…"), "full ID inaccessible")
}
check("actual native views paint different state-specific offscreen PNGs") {
    let root = URL(fileURLWithPath: ".build", isDirectory: true).appendingPathComponent("support-ui-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let c = try fixture(.initiateRefund); let (ui, fake) = try loaded(c)
    let ordinary = LicenceSupportController()
    var images: [Data] = []
    @MainActor func paint(_ controller: LicenceSupportController, name: String) throws {
        let text = LicenceSupportViewText(controller)
        let renderer = ImageRenderer(content: LicenceSupportView(controller: controller))
        renderer.scale = 1
        guard let image = renderer.cgImage else { throw Failure(description: "real view did not paint") }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw Failure(description: "PNG unavailable") }
        try expect(image.width >= 800 && image.height >= 180, "view clipped unexpectedly")
        try expect(data.count > 5000, "blank/unsupported native view")
        try data.write(to: root.appendingPathComponent(name + ".png"), options: [.withoutOverwriting])
        try Data(text.accessibilityText.utf8).write(to: root.appendingPathComponent(name + "-accessibility.txt"), options: [.withoutOverwriting])
        images.append(data)
    }
    try paint(ordinary, name: "unconfigured")
    ui.prepare(action: c.action); try paint(ui, name: "refund-confirmation")
    try expect(words(ui).contains("txn_fixture") && words(ui).contains("sub_fixture"), "refund targets absent in accessibility content")
    confirm(ui, c); try paint(ui, name: "refund-requested")
    try expect(fake.commits.count == 1, "painting triggered an action")
    try expect(Set(images).count == 3, "real rendered states identical")
    print("OFFSCREEN \(root.path)")
}
var failed = 0
for (name, body) in checks {
    do { try body(); print("PASS \(name)") } catch { failed += 1; print("FAIL \(name): \(error)") }
}
print("Licence support UI: \(checks.count) cases, \(failed) failures")
exit(failed == 0 ? 0 : 1)
