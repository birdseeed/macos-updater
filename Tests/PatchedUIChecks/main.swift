import Foundation
import Darwin
import CryptoKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import PatchedCore
import PatchedUI

// Acceptance checks for the PAT-2582 visible text and the shared native view.
// The real UpdateView is painted offscreen with ImageRenderer. No app is launched or
// activated, and no installed app, profile or network is read. The only writes are
// one new directory named patched-ui-fixture-<UUID> beneath this worktree's .build,
// which is kept for inspection. Painted output supports visual review only.
struct CheckFailure: Error, CustomStringConvertible { let description: String }
func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw CheckFailure(description: message) }
}

var cases: [(String, @MainActor () throws -> Void)] = []
@MainActor func check(_ name: String, _ action: @escaping @MainActor () throws -> Void) { cases.append((name, action)) }

let notice = "Fixture preview. No installed app is checked or changed."
let fixtureTarget = "/fixture/Applications/Firefox.app"
let readyNote = "Fixture target: \(fixtureTarget). Runs only when you choose Update."
let refusedNote = "Refused. Nothing runs until you choose Update again."
let fallbackReason = "The update was refused."
let deferredLine = "Deferred until 2027-01-16 08:00 UTC. Nothing runs on its own."

/// The proposed exact copy for every typed refusal. See docs/transaction-recovery.md.
let reasons: [(TransactionFailure, String)] = [
    (.notImplemented, "This step is not available in this preview."),
    (.notAuthorized, "Patched is not authorised to make this change."),
    (.userTriggerRequired, "An update starts only when you choose Update."),
    (.unsafePath, "That location cannot be used for an update."),
    (.aliasedPath, "The update and the app are in the same place."),
    (.existingRoot, "The preview folder already exists."),
    (.missingTarget, "The app to update was not found."),
    (.missingSource, "The update files were not found."),
    (.notDirectory, "Something that should be a folder is not a folder."),
    (.symlink, "A link was found where a real file or folder is required."),
    (.hardlink, "A file with more than one name was found."),
    (.specialFile, "An unsupported kind of file was found."),
    (.unsafeOwner, "A file or folder belongs to a different user."),
    (.unsafeMode, "A file or folder has permissions Patched does not accept."),
    (.crossVolume, "The update and the app are on different disks."),
    (.treeLimit, "The app is too large for this preview."),
    (.artifactMismatch, "The update file does not match the catalogue."),
    (.invalidManifest, "The update's list of files could not be read."),
    (.manifestMismatch, "The update files do not match their list."),
    (.stagedBytesMismatch, "The copied update files do not match their list."),
    (.invalidBundle, "The app's details could not be read."),
    (.wrongBundle, "The update is for a different app."),
    (.wrongVersion, "The update is not the expected version."),
    (.notNewer, "The update is not newer than the app."),
    (.appRunning, "The app is open. Close it yourself, then choose Update."),
    (.identityChanged, "Something changed on disk during the update. Recovery may be needed."),
    (.existingTransaction, "An earlier update attempt is on record. Recovery may be needed."),
    (.busy, "Another update is in progress."),
    (.persistenceFailed, "Patched could not save its progress. Recovery may be needed."),
    (.journalMissing, "No record of an update was found."),
    (.journalCorrupt, "The update record could not be read."),
    (.journalMismatch, "The update record does not match what is on disk."),
    (.ambiguousState, "Patched cannot tell which version is in place and will not guess."),
    (.invalidState, "That step is not available at this stage.")]

/// Refusals that can follow the swap or a failed record. Their copy must not promise an unchanged or restored app.
let mayNeedRecovery: [TransactionFailure] = [.identityChanged, .existingTransaction, .persistenceFailed]
let assurances = ["nothing changed", "nothing was changed", "nothing has changed", "no changes", "unchanged", "not changed", "safe",
                  "intact", "still in place", "restored", "rolled back"]
let claims = ["healthy", "secure", "protected", "up to date", "automatic", "background", "scheduled", "installed successfully", "\u{2014}", "\u{2013}"]

func ready(_ edit: (inout UpdateDisplayInput) -> Void = { _ in }) -> UpdateDisplayInput {
    var input = UpdateDisplayInput(appName: "Firefox")
    input.installedVersion = "157.0"; input.candidateVersion = "157.0.1"; input.checkedAt = 1_800_000_000
    input.catalogueCheck = .passed; input.artifactCheck = .passed; input.applicationOpen = false
    input.approvedFixtureTarget = fixtureTarget
    edit(&input); return input
}
func rows(_ catalogue: String, _ bytes: String, _ closed: String) -> [UpdateCheckRow] {
    [UpdateCheckRow(title: "Catalogue signature", status: catalogue), UpdateCheckRow(title: "Staged bytes", status: bytes),
     UpdateCheckRow(title: "macOS signature and notarisation", status: "Not run in this fixture preview"),
     UpdateCheckRow(title: "App closed", status: closed)]
}
/// What the view shows, through the actual presentation and the actual adapter.
func shown(_ input: UpdateDisplayInput) -> UpdateViewText { UpdateViewText(UpdatePresentation.make(input)) }
func fields(_ text: UpdateViewText) -> [String] {
    [text.previewNotice, text.heading, text.installedLine, text.checkedLine, text.refusalLine ?? "", text.deferralLine ?? "",
     text.actionTitle, text.actionNote] + text.checks.flatMap { [$0.title, $0.status] }
}
func hasCamelCase(_ text: String) -> Bool {
    let scalars = Array(text.unicodeScalars)
    return zip(scalars, scalars.dropFirst()).contains { CharacterSet.lowercaseLetters.contains($0) && CharacterSet.uppercaseLetters.contains($1) }
}
func hasDigit(_ text: String) -> Bool { text.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) } }
/// A brief plain sentence: no code, no claim about health or background work and no assurance about the app's state.
func expectPlain(_ text: String, _ context: String) throws {
    try expect(!text.isEmpty && text.count <= 90 && text.hasSuffix(".") && text.first?.isUppercase == true,
               "\(context) is not one brief sentence: \"\(text)\"")
    try expect(text.unicodeScalars.allSatisfy { $0.isASCII && $0.value >= 32 && $0.value != 127 } && !text.contains(":") && !text.contains("_"),
               "\(context) is not plain text: \"\(text)\"")
    try expect(!hasCamelCase(text) && !TransactionFailure.allCases.contains { text.contains($0.rawValue) }, "\(context) shows a raw code: \"\(text)\"")
    for banned in claims + assurances {
        try expect(!text.lowercased().contains(banned), "\(context) contains \"\(banned)\": \"\(text)\"")
    }
}
func expectText(_ input: UpdateDisplayInput, heading: String = "Firefox 157.0.1", installed: String = "Installed: 157.0",
                checked: String = "Checked: 2027-01-15 08:00 UTC", checks: [UpdateCheckRow], refusal: String? = nil,
                deferral: String? = nil, enabled: Bool, note: String) throws {
    let presentation = UpdatePresentation.make(input), text = UpdateViewText(presentation)
    try expect(text.previewNotice == notice, "Preview notice missing: \(text.previewNotice)")
    try expect(text.heading == heading && text.installedLine == installed && text.checkedLine == checked,
               "Candidate, version or time differs: \(text.heading) / \(text.installedLine) / \(text.checkedLine)")
    try expect(text.checks == checks, "Check rows differ: \(text.checks)")
    try expect(text.refusalLine == refusal && text.deferralLine == deferral,
               "Refusal or deferral differs: \(String(describing: text.refusalLine)) / \(String(describing: text.deferralLine))")
    try expect(text.actionTitle == "Update Firefox" && text.actionNote == note, "Manual action differs: \(text.actionTitle) note=\(text.actionNote)")
    try expect(text.actionEnabled == enabled && presentation.actionEnabled == enabled,
               "Enabled state differs: view=\(text.actionEnabled) presentation=\(presentation.actionEnabled)")
    try expect(UpdateViewText(presentation) == text, "Visible text is not a pure function of the presentation")
}

// MARK: Refusal reasons

check("reasons: the proposed copy names every typed refusal exactly once") {
    try expect(reasons.map { $0.0.rawValue } == TransactionFailure.allCases.map(\.rawValue), "Copy table does not follow TransactionFailure.allCases")
    try expect(Set(reasons.map { $0.1 } + [fallbackReason]).count == reasons.count + 1, "Two refusals share one sentence")
    for (failure, text) in reasons { try expectPlain(text, "Proposed copy for \(failure.rawValue)") }
    try expectPlain(fallbackReason, "Proposed fallback copy")
}
check("reasons: every typed refusal maps to a brief plain sentence with no raw code") {
    var seen = Set<String>()
    for failure in TransactionFailure.allCases {
        let text = UpdateViewText.refusalReason(diagnosticCode: failure.rawValue)
        try expectPlain(text, "Reason for \(failure.rawValue)")
        try expect(text != fallbackReason, "\(failure.rawValue) has no reason of its own")
        try expect(seen.insert(text).inserted, "\(failure.rawValue) repeats another refusal's reason: \"\(text)\"")
        try expect(UpdateViewText.refusalReason(diagnosticCode: failure.rawValue) == text, "Reason is not a pure function of its code")
    }
}
check("reasons: every typed refusal uses the reviewed copy") {
    let wrong = reasons.filter { UpdateViewText.refusalReason(diagnosticCode: $0.0.rawValue) != $0.1 }
    try expect(wrong.isEmpty, "Copy differs for \(wrong.map { "\($0.0.rawValue)=\"\(UpdateViewText.refusalReason(diagnosticCode: $0.0.rawValue))\"" })")
}
for (failure, text) in [(TransactionFailure.appRunning, "The app is open. Close it yourself, then choose Update."),
                        (.unsafePath, "That location cannot be used for an update."),
                        (.identityChanged, "Something changed on disk during the update. Recovery may be needed."),
                        (.persistenceFailed, "Patched could not save its progress. Recovery may be needed."),
                        (.ambiguousState, "Patched cannot tell which version is in place and will not guess."),
                        (.notAuthorized, "Patched is not authorised to make this change.")] {
    check("reasons: \(failure.rawValue) reads \"\(text)\"") {
        let actual = UpdateViewText.refusalReason(diagnosticCode: failure.rawValue)
        try expect(actual == text, "Received \"\(actual)\"")
    }
}
check("reasons: an unknown diagnostic code falls back without being shown") {
    for code in ["", " ", "invalidSignature", "digestMismatch", "APPRUNNING", "apprunning", " appRunning", "appRunning ", "appRunning\n",
                 "Refused: appRunning", "appRunning.persistenceFailed", "futureCode", "0", "\u{0}", "Passed"] {
        let actual = UpdateViewText.refusalReason(diagnosticCode: code)
        try expect(actual == fallbackReason, "Code \(code.debugDescription) produced \"\(actual)\"")
    }
}
check("reasons: a refusal that may leave work unfinished mentions recovery and promises no unchanged app") {
    for failure in mayNeedRecovery {
        let text = UpdateViewText.refusalReason(diagnosticCode: failure.rawValue)
        try expect(text.hasSuffix("Recovery may be needed."), "\(failure.rawValue) does not mention recovery: \"\(text)\"")
    }
    for failure in TransactionFailure.allCases {
        let text = UpdateViewText.refusalReason(diagnosticCode: failure.rawValue).lowercased()
        try expect(!text.isEmpty && text != "not implemented", "\(failure.rawValue) has no reason")
        for banned in assurances { try expect(!text.contains(banned), "\(failure.rawValue) reason asserts \"\(banned)\": \(text)") }
    }
}

// MARK: Check rows

for (diagnostic, visible) in [("Not run", "Not run"), ("Passed", "Passed"), ("Refused: invalidSignature", "Did not pass"),
                              ("Refused: digestMismatch", "Did not pass"), ("Refused: ", "Did not pass"), ("Refused: Passed", "Did not pass"),
                              ("Not run in this fixture preview", "Not run in this fixture preview"), ("Not checked", "Not checked"),
                              ("Closed", "Closed"), ("Open. Patched will not quit it", "Open. Patched will not quit it")] {
    check("rows: diagnostic status \"\(diagnostic)\" is shown as \"\(visible)\"") {
        let actual = UpdateViewText.checkStatus(diagnosticStatus: diagnostic)
        try expect(actual == visible, "Received \"\(actual)\"")
    }
}
for (name, edit, catalogue, bytes) in [
    ("catalogue not run", { (i: inout UpdateDisplayInput) in i.catalogueCheck = .notRun }, "Not run", "Passed"),
    ("catalogue refused", { (i: inout UpdateDisplayInput) in i.catalogueCheck = .refused("invalidSignature") }, "Did not pass", "Passed"),
    ("staged bytes not run", { (i: inout UpdateDisplayInput) in i.artifactCheck = .notRun }, "Passed", "Not run"),
    ("staged bytes refused", { (i: inout UpdateDisplayInput) in i.artifactCheck = .refused("digestMismatch") }, "Passed", "Did not pass"),
    ("both refused with a typed code", { (i: inout UpdateDisplayInput) in i.catalogueCheck = .refused("appRunning"); i.artifactCheck = .refused("") },
     "Did not pass", "Did not pass")] {
    check("view text: \(name) is shown without a code and leaves the action disabled") {
        try expectText(ready(edit), checks: rows(catalogue, bytes, "Closed"), enabled: false, note: "Checks have not passed.")
    }
}

// MARK: Actual presentation through the adapter

check("view text: default state has no candidate, no approved target and a disabled manual action") {
    try expectText(UpdateDisplayInput(appName: "Firefox"), heading: "No update candidate", installed: "Installed: unknown",
                   checked: "Checked: never", checks: rows("Not run", "Not run", "Not checked"), enabled: false, note: "No update candidate.")
}
check("view text: ready fixture candidate keeps the presentation's wording and its enabled manual action") {
    try expectText(ready(), checks: rows("Passed", "Passed", "Closed"), enabled: true, note: readyNote)
}
check("view text: an open app is shown as open and the action stays disabled") {
    try expectText(ready { $0.applicationOpen = true }, checks: rows("Passed", "Passed", "Open. Patched will not quit it"), enabled: false,
                   note: "Firefox is open. Close it yourself, then choose Update.")
}
check("view text: a refusal with a deferral shows the plain reason, the deferral and a disabled action") {
    try expectText(ready { $0.refusal = .persistenceFailed; $0.deferredUntil = 1_800_086_400 }, checks: rows("Passed", "Passed", "Closed"),
                   refusal: "Patched could not save its progress. Recovery may be needed.", deferral: deferredLine, enabled: false, note: refusedNote)
}
check("view text: every typed refusal is shown as its reason, never as its code") {
    for (failure, text) in reasons {
        try expectText(ready { $0.refusal = failure }, checks: rows("Passed", "Passed", "Closed"), refusal: text, enabled: false, note: refusedNote)
        let visible = fields(shown(ready { $0.refusal = failure; $0.catalogueCheck = .refused(failure.rawValue) }))
        for code in TransactionFailure.allCases {
            try expect(!visible.contains { $0.contains(code.rawValue) }, "Refusal \(failure.rawValue) shows raw code \(code.rawValue): \(visible)")
        }
        try expect(!visible.contains { $0.contains("Refused:") }, "Refusal \(failure.rawValue) shows a diagnostic line: \(visible)")
    }
}
check("view text: every state keeps the fixture notice and the unrun macOS row, and makes no claim") {
    var inputs = [UpdateDisplayInput(appName: "Firefox"), ready(), ready { $0.applicationOpen = true }, ready { $0.deferredUntil = 1_800_086_400 },
                  ready { $0.catalogueCheck = .refused("invalidSignature") }, ready { $0.artifactCheck = .refused("digestMismatch") },
                  ready { $0.approvedFixtureTarget = nil }, ready { $0.checkedAt = Double.greatestFiniteMagnitude }]
    inputs += TransactionFailure.allCases.map { refusal in ready { $0.refusal = refusal; $0.deferredUntil = Double.nan } }
    for input in inputs {
        let text = shown(input)
        try expect(text.previewNotice == notice, "Preview notice missing: \(text.previewNotice)")
        try expect(text.checks.count == 4 && text.checks[2] == UpdateCheckRow(title: "macOS signature and notarisation", status: "Not run in this fixture preview"),
                   "macOS row missing or claims a result: \(text.checks)")
        let all = fields(text).joined(separator: "\n").lowercased()
        for banned in claims { try expect(!all.contains(banned), "Visible text contains \"\(banned)\": \(all)") }
        if input.refusal != nil {
            for banned in assurances {
                try expect(!(text.refusalLine ?? "").lowercased().contains(banned) && !text.actionNote.lowercased().contains(banned),
                           "Refused state asserts \"\(banned)\": \(String(describing: text.refusalLine)) / \(text.actionNote)")
            }
        }
    }
}
check("view text: the adapter never enables an action and exposes no callback or authority") {
    var inputs = [UpdateDisplayInput(appName: "Firefox"), ready { $0.applicationOpen = true }, ready { $0.applicationOpen = nil },
                  ready { $0.approvedFixtureTarget = nil }, ready { $0.candidateVersion = nil }, ready { $0.catalogueCheck = .notRun },
                  ready { $0.artifactCheck = .refused("digestMismatch") }]
    inputs += TransactionFailure.allCases.map { refusal in ready { $0.refusal = refusal } }
    for input in inputs {
        let presentation = UpdatePresentation.make(input), text = UpdateViewText(presentation)
        try expect(!presentation.actionEnabled && !text.actionEnabled, "IMPROPER ACCEPTANCE: a state that is not ready shows an enabled action")
        try expect(text.actionTitle == "Update Firefox" && !text.actionNote.isEmpty && text.actionNote != readyNote,
                   "Disabled action is not explained: \(text.actionTitle) / \(text.actionNote)")
    }
    let presentation = UpdatePresentation.make(ready()), text = UpdateViewText(presentation)
    try expect(presentation.actionEnabled && text.actionEnabled, "The one ready state lost its manual action")
    let stored = Mirror(reflecting: text).children.map { ($0.label ?? "", $0.value) }
    try expect(stored.map { $0.0 } == ["previewNotice", "heading", "installedLine", "checkedLine", "checks", "refusalLine", "deferralLine",
                                       "actionTitle", "actionEnabled", "actionNote"], "Visible text stores unexpected state: \(stored.map { $0.0 })")
    let plain: [Any.Type] = [String.self, String?.self, Bool.self, [UpdateCheckRow].self]
    try expect(stored.allSatisfy { child in plain.contains { $0 == type(of: child.1) } }, "Visible text stores something other than words")
}

// MARK: Extreme clocks

let unknownClocks: [(String, Double)] = [
    ("greatest finite magnitude", Double.greatestFiniteMagnitude), ("negative greatest finite magnitude", -Double.greatestFiniteMagnitude),
    ("first second of year 10000", 253_402_300_800), ("year 33658", 1e12), ("beyond Int64", 9.3e18), ("1e300", 1e300),
    ("nan", Double.nan), ("signalling nan", Double.signalingNaN), ("infinity", Double.infinity), ("negative infinity", -Double.infinity),
    ("minus one second", -1), ("minus half a second", -0.5), ("smallest negative", -Double.leastNonzeroMagnitude)]
for (name, value) in unknownClocks {
    check("clock: \(name) is an unknown time, never a fabricated one") {
        let checked = UpdatePresentation.make(ready { $0.checkedAt = value })
        try expect(checked.checkedLine == "Checked: unknown" && checked.actionEnabled && checked.actionNote == readyNote,
                   "Checked time invented or state changed: \(checked.checkedLine) enabled=\(checked.actionEnabled)")
        let deferred = UpdatePresentation.make(ready { $0.deferredUntil = value })
        try expect(deferred.deferralLine == "Deferred. Nothing runs on its own." && deferred.checkedLine == "Checked: 2027-01-15 08:00 UTC" && deferred.actionEnabled,
                   "Deferral time invented or state changed: \(String(describing: deferred.deferralLine)) / \(deferred.checkedLine)")
        let text = shown(ready { $0.checkedAt = value; $0.deferredUntil = value; $0.refusal = .appRunning })
        try expect(text.checkedLine == "Checked: unknown" && text.deferralLine == "Deferred. Nothing runs on its own.",
                   "View text invents a time: \(text.checkedLine) / \(String(describing: text.deferralLine))")
        try expect(!hasDigit(text.checkedLine) && !hasDigit(text.deferralLine ?? "0") && !text.actionEnabled, "View text shows a number for an unknown clock")
    }
}
check("clock: the last minute of year 9999 is still shown as a whole UTC minute") {
    for value in [253_402_300_740.0, 253_402_300_799.0, 253_402_300_799.999] {
        let text = shown(ready { $0.checkedAt = value; $0.deferredUntil = value })
        try expect(text.checkedLine == "Checked: 9999-12-31 23:59 UTC" && text.deferralLine == "Deferred until 9999-12-31 23:59 UTC. Nothing runs on its own.",
                   "Last valid minute differs: \(text.checkedLine) / \(String(describing: text.deferralLine))")
    }
}

// MARK: Painted states of the actual shared view

struct Painted {
    let name: String, input: UpdateDisplayInput, presentation: UpdatePresentation, text: UpdateViewText
    let width: Int, height: Int, pixels: Data, png: Data
    /// Pixels the renderer filled with its yellow stand-in for a control it could not paint.
    let unpaintedPixels: Int, distinctPixels: Int
}
let paintedWidth = 480, paintedScale = 2
let states: [(String, UpdateDisplayInput)] = [
    ("default", UpdateDisplayInput(appName: "Firefox")), ("ready", ready()), ("running", ready { $0.applicationOpen = true }),
    ("refused-deferred", ready { $0.refusal = .persistenceFailed; $0.deferredUntil = 1_800_086_400 })]

@MainActor func paint(_ name: String, _ input: UpdateDisplayInput) throws -> Painted {
    let presentation = UpdatePresentation.make(input)
    let renderer = ImageRenderer(content: UpdateView(presentation: presentation, onUpdate: {})
        .frame(width: CGFloat(paintedWidth), alignment: .leading).background(Color.white).environment(\.colorScheme, .light))
    renderer.scale = CGFloat(paintedScale)
    guard let image = renderer.cgImage, let pixels = image.dataProvider?.data as Data? else { throw CheckFailure(description: "No image for \(name)") }
    try expect(image.bitsPerPixel == 32 && pixels.count >= image.bytesPerRow * image.height, "Unexpected pixel layout for \(name)")
    var unpainted = 0, distinct = Set<UInt32>()
    for row in 0..<image.height {
        for offset in stride(from: row * image.bytesPerRow, to: row * image.bytesPerRow + image.width * 4, by: 4) {
            let (first, green, third) = (pixels[offset], pixels[offset + 1], pixels[offset + 2])
            if (190...215).contains(green) && ((first > 240 && third < 20) || (third > 240 && first < 20)) { unpainted += 1 }
            distinct.insert(UInt32(first) << 16 | UInt32(green) << 8 | UInt32(third))
        }
    }
    let png = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else {
        throw CheckFailure(description: "No PNG destination for \(name)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    try expect(CGImageDestinationFinalize(destination), "PNG for \(name) was not encoded")
    return Painted(name: name, input: input, presentation: presentation, text: UpdateViewText(presentation),
                   width: image.width, height: image.height, pixels: pixels, png: png as Data,
                   unpaintedPixels: unpainted, distinctPixels: distinct.count)
}
func describe(_ status: DisplayCheckStatus) -> String {
    switch status { case .notRun: "notRun"; case .passed: "passed"; case .refused(let code): "refused(\(code))" }
}
func describe(_ rows: [UpdateCheckRow]) -> [[String: String]] { rows.map { ["title": $0.title, "status": $0.status] } }
func record(_ state: Painted) -> [String: Any] {
    let input: [String: Any] = [
        "appName": state.input.appName, "installedVersion": state.input.installedVersion ?? NSNull(),
        "candidateVersion": state.input.candidateVersion ?? NSNull(), "checkedAt": state.input.checkedAt ?? NSNull(),
        "catalogueCheck": describe(state.input.catalogueCheck), "artifactCheck": describe(state.input.artifactCheck),
        "applicationOpen": state.input.applicationOpen ?? NSNull(), "approvedFixtureTarget": state.input.approvedFixtureTarget ?? NSNull(),
        "deferredUntil": state.input.deferredUntil ?? NSNull(), "refusal": state.input.refusal?.rawValue ?? NSNull()]
    let presentation: [String: Any] = [
        "previewNotice": state.presentation.previewNotice, "heading": state.presentation.heading, "installedLine": state.presentation.installedLine,
        "checkedLine": state.presentation.checkedLine, "checks": describe(state.presentation.checks),
        "refusalLine": state.presentation.refusalLine ?? NSNull(), "deferralLine": state.presentation.deferralLine ?? NSNull(),
        "actionTitle": state.presentation.actionTitle, "actionEnabled": state.presentation.actionEnabled, "actionNote": state.presentation.actionNote]
    let text: [String: Any] = [
        "previewNotice": state.text.previewNotice, "heading": state.text.heading, "installedLine": state.text.installedLine,
        "checkedLine": state.text.checkedLine, "checks": describe(state.text.checks), "refusalLine": state.text.refusalLine ?? NSNull(),
        "deferralLine": state.text.deferralLine ?? NSNull(), "actionTitle": state.text.actionTitle, "actionEnabled": state.text.actionEnabled,
        "actionNote": state.text.actionNote]
    return ["file": "\(state.name).png", "pixelWidth": state.width, "pixelHeight": state.height, "pngByteLength": state.png.count,
            "unpaintedControlPixels": state.unpaintedPixels,
            "pngSHA256": SHA256.hash(data: state.png).map { String(format: "%02x", $0) }.joined(),
            "displayInput": input, "diagnosticPresentation": presentation, "adapterViewText": text]
}
/// Exclusively creates one new directory directly beneath the .build that holds this executable. No caller chooses the path.
func createOutputDirectory() throws -> URL {
    guard var build = Bundle.main.executableURL?.resolvingSymlinksInPath() else { throw CheckFailure(description: "Executable path unknown") }
    while build.lastPathComponent != ".build" {
        guard build.pathComponents.count > 1 else { throw CheckFailure(description: "This executable is not beneath a .build directory") }
        build.deleteLastPathComponent()
    }
    let directory = build.appendingPathComponent("patched-ui-fixture-\(UUID().uuidString)")
    try expect(mkdir(directory.path, 0o700) == 0, "Output directory was not created exclusively: errno \(errno)")
    return directory
}

var paintedStates: [Painted] = []
var outputDirectory: URL?
check("render: the actual UpdateView paints four bounded states that are saved as PNG files") {
    paintedStates = try states.map { try paint($0.0, $0.1) }
    let directory = try createOutputDirectory()
    outputDirectory = directory
    for state in paintedStates {
        try expect(state.width == paintedWidth * paintedScale && (100...4_000).contains(state.height), "\(state.name) has unbounded size \(state.width)x\(state.height)")
        try expect(state.distinctPixels > 2, "\(state.name) is blank")
        try expect(state.png.count > 1_024 && state.png.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), "\(state.name) is not a PNG")
        let file = directory.appendingPathComponent("\(state.name).png")
        try state.png.write(to: file, options: .withoutOverwriting)
        try expect(try Data(contentsOf: file) == state.png, "\(state.name).png does not read back")
    }
    let metadata: [String: Any] = [
        "kind": "patched-ui-fixture-render-v1", "view": "PatchedUI.UpdateView", "renderer": "SwiftUI ImageRenderer, offscreen",
        "pointWidth": paintedWidth, "scale": paintedScale, "appLaunched": false,
        "claim": "Visual review only. No OS trust, installed update or Firefox proof.", "states": paintedStates.map(record)]
    try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        .write(to: directory.appendingPathComponent("metadata.json"), options: .withoutOverwriting)
    print("Painted states kept for inspection: \(directory.path)")
}
check("render: the four painted states differ from one another") {
    try expect(paintedStates.count == states.count, "States were not painted")
    for (index, first) in paintedStates.enumerated() {
        for second in paintedStates.dropFirst(index + 1) {
            try expect(first.pixels != second.pixels || first.height != second.height, "\(first.name) and \(second.name) paint identical pixels")
        }
    }
}
check("render: every control of the actual view is painted, with no stand-in for an unpainted control") {
    try expect(paintedStates.count == states.count, "States were not painted")
    for state in paintedStates {
        try expect(state.unpaintedPixels == 0, "\(state.name) shows the renderer's stand-in for an unpainted control: \(state.unpaintedPixels) pixels")
    }
}
check("render: each painted state was laid out from the expected presentation with the fixture notice") {
    try expect(paintedStates.count == states.count, "States were not painted")
    let expected: [(heading: String, enabled: Bool, refusal: String?, deferral: String?, closed: String)] = [
        ("No update candidate", false, nil, nil, "Not checked"), ("Firefox 157.0.1", true, nil, nil, "Closed"),
        ("Firefox 157.0.1", false, nil, nil, "Open. Patched will not quit it"),
        ("Firefox 157.0.1", false, "Patched could not save its progress. Recovery may be needed.", deferredLine, "Closed")]
    for (state, want) in zip(paintedStates, expected) {
        try expect(state.presentation.previewNotice == notice && state.text.previewNotice == notice, "\(state.name) was painted without the fixture notice")
        try expect(state.presentation.heading == want.heading && state.presentation.actionEnabled == want.enabled && state.text.actionEnabled == want.enabled,
                   "\(state.name) was painted from the wrong state: \(state.presentation.heading) enabled=\(state.presentation.actionEnabled)")
        try expect(state.text.refusalLine == want.refusal && state.text.deferralLine == want.deferral && state.text.checks.last?.status == want.closed,
                   "\(state.name) visible text differs: \(String(describing: state.text.refusalLine)) / \(String(describing: state.text.deferralLine))")
    }
}

var failures = 0
for (name, action) in cases {
    do { try action(); print("PASS ui: \(name)") }
    catch { failures += 1; print("FAIL ui: \(name): \(error)") }
}
print("Fixture view acceptance: \(cases.count) cases, \(failures) failures. Painted output is for visual review only. No fresh OS trust, installed update or Firefox proof.")
exit(failures == 0 ? 0 : 1)
