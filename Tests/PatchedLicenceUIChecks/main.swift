import Foundation
import Darwin
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import PatchedLicensing
import PatchedActivation
import PatchedUI

// Additive PAT-2648 checks. Inputs are inert synthetic facts, not verified evidence.
// Paint only, never launch PatchedApp. Exclusively retained outputs beneath .build.
struct Failure: Error, CustomStringConvertible { let description: String }
func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw Failure(description: message) }
}
var cases: [(String, @MainActor () throws -> Void)] = []
@MainActor func check(_ name: String, _ body: @escaping @MainActor () throws -> Void) { cases.append((name, body)) }
let account = "fixture-household"
func mac(_ index: Int, label: String = "Home Mac", accountID: String = account,
         status: MacDisplayStatus = .active, revision: UInt64 = 1) -> MacDisplayFact {
    MacDisplayFact(opaqueID: String(format: "%032x", index), accountID: accountID,
                   label: label, revision: revision, status: status)
}
func input(_ facts: [MacDisplayFact], session: MacManagementSession = .current,
           snapshot: UInt64 = 7, current: UInt64 = 7) -> ManageMacsInput {
    ManageMacsInput(session: session, accountID: account, localActivationID: mac(1).opaqueID,
                   facts: facts, snapshotRevision: snapshot, currentRevision: current)
}
func licence(_ state: LicenceDisplayState, trial: DisplayTrialAvailability = .unknown,
             label: String = "") -> LicencePresentation {
    LicencePresentation.make(.init(state: state, trial: trial, accountLabel: label))
}

check("defaults: anonymous discovery survives refusing presentation defaults") {
    let value = LicencePresentation.make()
    try expect(value.state == .anonymous && value.discoveryVisible, "Anonymous discovery hidden")
    try expect(value.selfUpdateVisible && value.recoveryVisible, "Safety surfaces hidden")
    try expect(value.intents == [.signIn], "Default must offer only inert sign-in intent")
    try expect(ManageMacsPresentation.make().rows.isEmpty && ManageMacsPresentation.make().needsVerification,
               "Default management must refuse targets")
}
let headings: [(LicenceDisplayState, String)] = [
    (.anonymous, "Browse updates without an account"), (.signedIn, "Signed in"),
    (.beta, "Private beta"), (.trial, "Trial active"), (.paid, "Subscription active"),
    (.grace, "Renewal grace period"), (.expired, "Update access expired"),
    (.revoked, "Update access revoked"), (.verificationRequired, "Verification required"),
    (.outage, "Licence service unavailable")]
for (state, heading) in headings {
    check("state: \(state.rawValue) exact heading and independent safety surfaces") {
        let value = licence(state)
        let text = LicenceViewText(value)
        try expect(value.state == state && text.heading == heading, "Wrong heading for \(state)")
        try expect(value.discoveryVisible && value.selfUpdateVisible && value.recoveryVisible, "Licence hides discovery/recovery/self-update")
        try expect(text.discovery == "Available updates remain visible without update access.", "Missing independent discovery copy")
        try expect(text.safety == "Patched self-update and recovery remain available. Existing update safety checks still apply.", "Misleading safety copy")
    }
}
check("accessibility: exact sign-in, refresh and household-management intent labels") {
    try expect(LicenceViewText(licence(.anonymous)).actionLabels == ["Sign in"], "Wrong sign-in label")
    try expect(LicenceViewText(licence(.signedIn)).actionLabels == ["Refresh licence", "Manage Macs"], "Wrong signed-in labels")
    try expect(LicenceViewText(licence(.signedIn, trial: .eligible)).actionLabels == ["Start 14-day trial", "Refresh licence", "Manage Macs"], "Wrong explicit-trial labels")
}
check("trial: sign-in alone creates no trial and starts nothing") {
    let facts = LicenceDisplayInput(state: .signedIn, trial: .unknown)
    let first = LicencePresentation.make(facts), second = LicencePresentation.make(facts)
    try expect(first == second && first.state == .signedIn, "Presentation mutated sign-in facts")
    try expect(!first.intents.contains(.startTrial), "Unknown eligibility offered trial")
    try expect(LicenceViewText(first).trialNote == "Signing in does not start or use a trial.", "Missing explicit sign-in promise")
}
check("trial: explicit eligible signed-in intent only, no card and no automatic start") {
    let value = licence(.signedIn, trial: .eligible)
    try expect(value.state == .signedIn && value.intents.contains(.startTrial), "Explicit trial intent missing")
    let text = LicenceViewText(value)
    try expect(text.actionLabels.contains("Start 14-day trial"), "Trial accessibility label differs")
    try expect(text.trialNote == "Start your 14-day trial when you choose. No card required. Signing in does not start or use a trial.", "Wrong trial copy")
}
for state in LicenceDisplayState.allCases where state != .signedIn {
    check("trial: eligibility fact cannot auto-start or offer trial in \(state)") {
        let value = licence(state, trial: .eligible)
        try expect(!value.intents.contains(.startTrial), "Wrong state offered trial")
        try expect(value.state == state, "Eligibility changed entitlement display")
    }
}
for availability in [DisplayTrialAvailability.unknown, .used, .betaActive] {
    check("trial: refusing availability \(availability)") {
        try expect(!licence(.signedIn, trial: availability).intents.contains(.startTrial), "Unavailable trial offered")
    }
}
check("beta: free beta consumes no trial and never auto-converts") {
    let text = LicenceViewText(licence(.beta, trial: .betaActive))
    try expect(text.detail == "Free private beta. No card required. It does not automatically become a paid subscription.", "Beta terms wrong")
    try expect(text.trialNote == "Trial unavailable during beta. Your unused 14-day trial is preserved.", "Beta consumes trial")
}
check("outage: no new allowance or local extension promised") {
    try expect(LicenceViewText(licence(.outage)).detail == "Patched cannot refresh your licence. Any existing access keeps its original verified limit.", "Outage extends access")
}
check("literal account: quotes, angles, markdown and newline are data") {
    let untrusted = "\"Household\" <a href='https://invalid'>**name**</a>\nSecond line"
    let value = licence(.signedIn, label: untrusted)
    try expect(value.accountLabel == untrusted && LicenceViewText(value).account == untrusted, "Literal account changed")
}
check("bounded account: huge and multiline input has finite display") {
    let text = LicenceViewText(licence(.signedIn, label: String(repeating: "x\n", count: 10_000))).account
    try expect(!text.isEmpty && text.count <= 241 && text.components(separatedBy: "\n").count <= 3, "Unbounded account label")
}
for count in 0...5 {
    check("slots: \(count) active entries never allocate an extra Mac") {
        let result = ManageMacsPresentation.make(input((1...max(1, count)).prefix(count).map { mac($0) }))
        try expect(result.activeCount == count && result.limitReached == (count == 5), "Wrong five-slot summary")
        try expect(result.rows.count == count && !result.needsVerification, "Current inert snapshot hidden")
        try expect(ManageMacsText(result).capacity == "\(count) of 5 active Macs", "Wrong capacity accessibility label")
        try expect(result.rows.allSatisfy { row in row.intents.allSatisfy { $0.kind != .confirmReplacement || count == 5 } }, "Replacement offered below limit")
    }
}
check("slots: duplicate labels distinguish targets using complete safe opaque identifier") {
    let result = ManageMacsPresentation.make(input([mac(1), mac(2)]))
    let text = ManageMacsText(result)
    try expect(text.rowLabels == ["Home Mac (\(mac(1).opaqueID)) · This Mac · Active", "Home Mac (\(mac(2).opaqueID)) · Active"], "Ambiguous duplicate labels")
    try expect(result.rows[0].isThisMac && !result.rows[1].isThisMac, "This Mac inferred from name")
}
check("slots: current actions are confirmation intents bound to exact target and both revisions") {
    let result = ManageMacsPresentation.make(input((1...5).map { mac($0, revision: UInt64($0)) }))
    try expect(result.rows.count == 5, "Missing rows")
    for (offset, row) in result.rows.enumerated() {
        try expect(row.intents.map(\.kind) == [.rename, .confirmDeactivation, .confirmReplacement], "Wrong inert actions")
        try expect(row.intents.allSatisfy { $0.opaqueID == row.opaqueID && $0.expectedRevision == UInt64(offset + 1) && $0.snapshotRevision == 7 }, "Unbound target intent")
        let labels = ManageMacsText(result).actionLabels[offset]
        try expect(labels == ["Rename \(row.label)", "Deactivate \(row.label), confirmation required", "Replace \(row.label), confirmation required"], "Wrong accessibility actions")
    }
}
check("slots: released entries remain released and cannot act") {
    let result = ManageMacsPresentation.make(input([mac(1), mac(2, status: .released)]))
    try expect(result.rows.count == 2 && result.activeCount == 1 && !result.limitReached, "Released slot counted")
    try expect(result.rows.last?.status == .released && result.rows.last?.intents.isEmpty == true, "Released target enabled")
    try expect(ManageMacsText(result).rowLabels.last?.hasSuffix(" · Released") == true, "Release status hidden")
}
for session in [MacManagementSession.unavailable, .stale, .terminalOnly] {
    check("slots: \(session) session refuses all management facts") {
        let result = ManageMacsPresentation.make(input([mac(1)], session: session))
        try expect(result.rows.isEmpty && result.needsVerification, "Unavailable session exposes private target")
    }
}
check("slots: cross-account facts do not reveal or enable targets") {
    let result = ManageMacsPresentation.make(input([mac(1, accountID: "other-household")]))
    try expect(result.rows.isEmpty && result.needsVerification, "Foreign account target visible")
}
check("slots: stale snapshot cannot enable action") {
    let result = ManageMacsPresentation.make(input([mac(1)], snapshot: 6))
    try expect(result.rows.isEmpty && result.needsVerification, "Stale revision enabled intent")
}
check("slots: oversized released history refuses bounded display") {
    let result = ManageMacsPresentation.make(input((1...51).map { mac($0, status: .released) }))
    try expect(result.rows.isEmpty && result.needsVerification, "Unbounded history displayed")
}
check("slots: six active entries refuse rather than legitimise extra allocation") {
    let result = ManageMacsPresentation.make(input((1...6).map { mac($0) }))
    try expect(result.rows.isEmpty && result.needsVerification, "Six-slot snapshot accepted")
}
check("slots: absent revision cannot bind an actionable target") {
    let result = ManageMacsPresentation.make(input([mac(1, revision: 0)]))
    try expect(result.rows.isEmpty && result.needsVerification, "Missing target revision enabled")
    let absent = ManageMacsPresentation.make(input([mac(1)], snapshot: 0, current: 0))
    try expect(absent.rows.isEmpty && absent.needsVerification, "Missing snapshot revision enabled")
}
check("slots: duplicate opaque IDs refuse ambiguous intent even with differing labels") {
    let result = ManageMacsPresentation.make(input([mac(1), mac(1, label: "Different Mac")]))
    try expect(result.rows.isEmpty && result.needsVerification, "Duplicate target enabled")
}
for id in ["/Users/private/token", "secret=raw-bearer", "<script>", String(repeating: "a", count: 33), String(repeating: "0", count: 32)] {
    check("slots: unsafe opaque identifier refuses whole snapshot: \(id.prefix(12))") {
        var fact = mac(1); fact.opaqueID = id
        let result = ManageMacsPresentation.make(input([fact]))
        try expect(result.rows.isEmpty && result.needsVerification, "Unsafe target displayed")
    }
}
check("literal Macs: bounded labels never become identity") {
    let raw = "\"Mac\" <b>**local**</b>\nLine two"
    let result = ManageMacsPresentation.make(input([mac(1, label: raw), mac(2, label: String(repeating: "z", count: 10_000))]))
    try expect(result.rows.count == 2, "Missing literal rows")
    try expect(result.rows[0].label == raw && result.rows[1].label.count <= 241, "Unbounded or nonliteral Mac label")
    try expect(result.rows[1].intents.allSatisfy { $0.opaqueID == mac(2).opaqueID }, "Label used as identity")
}

@MainActor func png<V: View>(_ view: V) throws -> Data {
    let renderer = ImageRenderer(content: view.frame(width: 520).background(Color.white).environment(\.colorScheme, .light))
    renderer.scale = 1
    guard let image = renderer.cgImage, image.width == 520, (40...4000).contains(image.height) else {
        throw Failure(description: "Unbounded or missing offscreen rendering")
    }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
        throw Failure(description: "Missing PNG destination")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination), data.length > 1024 else { throw Failure(description: "Blank/invalid PNG") }
    return data as Data
}
@MainActor func outputDirectory() throws -> URL {
    guard var build = Bundle.main.executableURL?.resolvingSymlinksInPath() else { throw Failure(description: "No executable path") }
    while build.lastPathComponent != ".build" {
        guard build.pathComponents.count > 1 else { throw Failure(description: "Executable outside .build") }
        build.deleteLastPathComponent()
    }
    let output = build.appendingPathComponent("patched-licence-ui-fixture-\(UUID().uuidString)")
    guard mkdir(output.path, 0o700) == 0 else { throw Failure(description: "Output not exclusive") }
    return output
}
check("render: actual licence view paints distinct states without invoking an intent") {
    let output = try outputDirectory()
    var actions = 0
    var rendered = Set<Data>()
    for state in LicenceDisplayState.allCases {
        let bytes = try png(LicenceView(presentation: licence(state), onIntent: { _ in actions += 1 }))
        rendered.insert(bytes)
        try bytes.write(to: output.appendingPathComponent("licence-\(state.rawValue).png"), options: .withoutOverwriting)
    }
    print("Offscreen licence output: \(output.path)")
    try expect(actions == 0, "Rendering triggered an action")
    try expect(rendered.count == LicenceDisplayState.allCases.count, "Licence states paint identically")
}
check("render: actual Manage Macs view distinguishes empty/full/released/refusing/literal states") {
    let output = try outputDirectory()
    let samples = [ManageMacsPresentation.make(input([])), ManageMacsPresentation.make(input((1...5).map { mac($0) })),
                   ManageMacsPresentation.make(input([mac(1, status: .released)])), ManageMacsPresentation.make(),
                   ManageMacsPresentation.make(input([mac(1, label: "\"Home\" <b>**name**</b>\nSecond line")]))]
    var actions = 0
    var rendered = Set<Data>()
    for (index, sample) in samples.enumerated() {
        let bytes = try png(ManageMacsView(presentation: sample, onIntent: { _ in actions += 1 }))
        rendered.insert(bytes)
        try bytes.write(to: output.appendingPathComponent("macs-\(index).png"), options: .withoutOverwriting)
    }
    print("Offscreen Manage Macs output: \(output.path)")
    try expect(actions == 0, "Rendering triggered mutation")
    try expect(rendered.count == samples.count, "Manage Macs states paint identically")
}
var failures = 0
for (name, body) in cases {
    do { try body(); print("PASS licence-ui: \(name)") }
    catch { failures += 1; print("FAIL licence-ui: \(name): \(error)") }
}
print("Local inert presentation/offscreen acceptance: \(cases.count) cases, \(failures) failures. No app launch, verified entitlement or installation authority.")
exit(failures == 0 ? 0 : 1)
