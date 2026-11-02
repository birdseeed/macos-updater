import Foundation
import CryptoKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import ArtifactInspection
@_spi(Testing) import PatchedCore
@_spi(Testing) import PatchedOperator

// The operator surface: the controller's state, its visible words and the shared native
// view. The actual OperatorView is painted offscreen with ImageRenderer. No app is launched
// or activated. Painted output supports visual review only.

let scopeNotice = "Fixture scope. No production key, no production publication and no installation."
let surfaceHeading = "Catalogue operator"
let surfaceFootnote = "Each step runs only when you choose it. Nothing is installed or opened."
let notRun = "Not run"
let refusedStatus = "Refused"
let verifiedStatus = "Fixture bytes matched. macOS checks not run"
let signedStatus = "Signed with the fixture key. Not published"
let publishedStatus = "Published to the local fixture folder"
let fallbackReason = "The step was refused."
let verifyFirst = "Verify the artifact first."
let signFirst = "Sign the catalogue first."

/// The proposed exact copy for every typed refusal. See docs/operator-runbook.md.
let reasons: [(OperatorFailure, String)] = [
    (.notImplemented, "This step is not available in this preview."),
    (.notAuthorized, "Patched is not authorised to sign or publish here."),
    (.invalidState, "That step is not available at this stage."),
    (.recordedEvidenceRefused, "A saved report cannot stand in for a fresh check."),
    (.unknownTarget, "That version is not one of the approved artifacts."),
    (.unsafePath, "That location cannot be used."),
    (.notRegularFile, "Something that should be a file is not a file."),
    (.hardlink, "A file with more than one name was found."),
    (.unsafeOwner, "A file or folder belongs to a different user."),
    (.unsafeMode, "A file or folder has permissions Patched does not accept."),
    (.resourceLimit, "A file is larger or smaller than this preview accepts."),
    (.lengthMismatch, "The artifact is not the expected size."),
    (.digestMismatch, "The artifact does not match its approved contents."),
    (.identityChanged, "Something changed on disk after it was checked. Verify again."),
    (.inspectionRefused, "The macOS checks did not pass for this artifact."),
    (.cleanupUnverified, "The inspection could not confirm that it cleaned up."),
    (.invalidConfiguration, "The catalogue details are not valid."),
    (.invalidClock, "The current time could not be used."),
    (.invalidLifetime, "The catalogue's dates are not valid."),
    (.futureIssued, "The catalogue's start time is too far ahead."),
    (.expired, "The catalogue has already expired."),
    (.untrustedKey, "The signing key is not the one configured here."),
    (.wrongCatalogue, "The catalogue name is not the one configured here."),
    (.signerFailed, "The signer did not return a signature."),
    (.invalidSignature, "The signature did not verify, so nothing was accepted."),
    (.replay, "A catalogue with this number or a later one already exists."),
    (.missingState, "The operator's saved record was not found. Nothing was reset."),
    (.corruptState, "The operator's saved record could not be read. Nothing was reset."),
    (.existingNamespace, "That operator folder already exists."),
    (.existingOutput, "Output for this catalogue already exists and was left as it is."),
    (.busy, "Another operator step is in progress."),
    (.persistenceFailed, "Patched could not save the result. Check the folder before trying again.")]
let claims = ["healthy", "secure", "protected", "safe", "trusted", "notarised", "notarized", "production ready", "released", "installed successfully",
              "automatic", "background", "scheduled", "\u{2014}", "\u{2013}"]

final class Counts {
    var verify = 0, sign = 0, publish = 0
    var all: [Int] { [verify, sign, publish] }
}
/// Wires the three steps to the test-only fixture authority. Each closure counts its own calls.
func wired(_ authority: FixtureOperatorAuthority, _ layout: Layout, _ counts: Counts) -> OperatorConfiguration {
    var configuration = OperatorConfiguration()
    configuration.artifactName = Sample.artifactName
    configuration.verify = { counts.verify += 1; return try fixtureReceipt(authority, layout) }
    configuration.sign = { counts.sign += 1; return try authority.sign(receipt: $0, request: Sample.request(), now: Sample.now, signer: Sample.signer) }
    configuration.publish = { counts.publish += 1; return try authority.publish($0, now: Sample.now) }
    return configuration
}
func line(_ row: OperatorStageRow) -> String {
    "\(row.stage.rawValue)|\(row.title)|\(row.status)|\(row.actionTitle)|\(row.actionEnabled ? "enabled" : "disabled")|\(row.reason ?? "-")"
}
func lines(_ text: OperatorViewText) -> [String] { text.rows.map(line) }
func row(_ stage: OperatorStage, _ status: String, enabled: Bool, _ reason: String? = nil) -> String {
    let (title, action) = switch stage {
    case .verify: ("1. Verify artifact", "Verify")
    case .sign: ("2. Sign catalogue", "Sign")
    case .publish: ("3. Publish locally", "Publish")
    }
    return "\(stage.rawValue)|\(title)|\(status)|\(action)|\(enabled ? "enabled" : "disabled")|\(reason ?? "-")"
}
func words(_ text: OperatorViewText) -> [String] {
    [text.scopeNotice, text.heading, text.artifactLine, text.footnote] + text.rows.flatMap { [$0.title, $0.status, $0.actionTitle, $0.reason ?? ""] }
}
@MainActor func expectFrame(_ text: OperatorViewText, artifact: String) throws {
    try expect(text.scopeNotice == scopeNotice && text.heading == surfaceHeading && text.footnote == surfaceFootnote && text.artifactLine == artifact,
               "Fixed surface text differs: \(text.scopeNotice) / \(text.heading) / \(text.artifactLine) / \(text.footnote)")
}

struct Painted { let name: String; let width: Int; let height: Int; let pixels: Data; let png: Data; let unpainted: Int; let distinct: Int; let lines: [String] }
let paintedWidth = 520, paintedScale = 2
@MainActor func paint(_ name: String, _ controller: OperatorController) throws -> Painted {
    let renderer = ImageRenderer(content: OperatorView(controller: controller)
        .frame(width: CGFloat(paintedWidth), alignment: .leading).background(Color.white).environment(\.colorScheme, .light))
    renderer.scale = CGFloat(paintedScale)
    guard let image = renderer.cgImage, let pixels = image.dataProvider?.data as Data? else { throw CheckFailure(description: "No image for \(name)") }
    try expect(image.bitsPerPixel == 32 && pixels.count >= image.bytesPerRow * image.height, "Unexpected pixel layout for \(name)")
    var unpainted = 0, distinct = Set<UInt32>()
    for line in 0..<image.height {
        for offset in stride(from: line * image.bytesPerRow, to: line * image.bytesPerRow + image.width * 4, by: 4) {
            let (first, green, third) = (pixels[offset], pixels[offset + 1], pixels[offset + 2])
            // ImageRenderer paints a yellow stand-in where a control could not be drawn.
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
    return Painted(name: name, width: image.width, height: image.height, pixels: pixels, png: png as Data, unpainted: unpainted,
                   distinct: distinct.count, lines: [controller.text.artifactLine] + lines(controller.text))
}
/// Exclusively creates one new directory directly beneath the .build that holds this executable.
func createOutputDirectory() throws -> URL {
    let directory = try buildDirectory().appendingPathComponent("patched-operator-ui-fixture-\(UUID().uuidString)")
    try expect(mkdir(directory.path, 0o700) == 0, "Output directory was not created exclusively: errno \(errno)")
    return directory
}

@MainActor func registerSurfaceChecks() {
    check("surface: the default controller has no artifact, no signing capability, no output location and three disabled steps") {
        let text = OperatorController().text
        try expectFrame(text, artifact: "No artifact chosen.")
        try expect(lines(text) == [row(.verify, notRun, enabled: false, "No artifact is configured."),
                                   row(.sign, notRun, enabled: false, "No signing capability is configured."),
                                   row(.publish, notRun, enabled: false, "No output location is configured.")], "Default steps differ: \(lines(text))")
    }
    check("surface: choosing any step on the default controller changes nothing") {
        let controller = OperatorController(), before = controller.text
        try expect(before.rows.count == 3, "Default controller shows \(before.rows.count) steps")
        for stage in OperatorStage.allCases + OperatorStage.allCases { controller.choose(stage) }
        try expect(controller.text == before, "A disabled step changed the surface")
    }
    check("surface: creating a wired controller runs no step; verification waits for an explicit choice") {
        try withRoot { authority, layout in
            let counts = Counts(), before = try snapshot(layout.root)
            let controller = OperatorController(wired(authority, layout, counts))
            try expectFrame(controller.text, artifact: "Artifact: \(Sample.artifactName)")
            try expect(lines(controller.text) == [row(.verify, notRun, enabled: true), row(.sign, notRun, enabled: false, verifyFirst),
                                                  row(.publish, notRun, enabled: false, signFirst)], "Wired steps differ: \(lines(controller.text))")
            try expect(counts.all == [0, 0, 0] && (try snapshot(layout.root)) == before, "A step ran when the controller was created")
        }
    }
    check("surface: a step with no capability stays disabled with its own reason even when the others are wired") {
        var configuration = OperatorConfiguration()
        configuration.artifactName = Sample.artifactName
        configuration.verify = { throw OperatorFailure.digestMismatch }
        let text = OperatorController(configuration).text
        try expect(lines(text) == [row(.verify, notRun, enabled: true), row(.sign, notRun, enabled: false, "No signing capability is configured."),
                                   row(.publish, notRun, enabled: false, "No output location is configured.")], "Partly wired steps differ: \(lines(text))")
    }
    check("surface: signing or publishing chosen before its earlier step invokes nothing") {
        try withRoot { authority, layout in
            let counts = Counts(), controller = OperatorController(wired(authority, layout, counts)), before = controller.text
            try expect(before.rows.count == 3, "Wired controller shows \(before.rows.count) steps")
            controller.choose(.sign); controller.choose(.publish); controller.choose(.sign)
            try expect(counts.all == [0, 0, 0] && controller.text == before, "A later step ran out of order: \(counts.all)")
            try expect(try names(layout.publications).isEmpty && checkpointFields(layout).sequence == 0, "An out-of-order choice signed or published")
        }
    }
    check("surface: a refused verification shows a plain reason, stays retryable and unlocks nothing") {
        var calls = 0
        var configuration = OperatorConfiguration()
        configuration.artifactName = Sample.artifactName
        configuration.verify = { calls += 1; throw OperatorFailure.digestMismatch }
        configuration.sign = { _ in throw OperatorFailure.notAuthorized }
        configuration.publish = { _ in throw OperatorFailure.notAuthorized }
        let controller = OperatorController(configuration)
        controller.choose(.verify)
        try expect(calls == 1, "Verification ran \(calls) times for one choice")
        try expect(lines(controller.text) == [row(.verify, refusedStatus, enabled: true, "The artifact does not match its approved contents."),
                                              row(.sign, notRun, enabled: false, verifyFirst), row(.publish, notRun, enabled: false, signFirst)],
                   "Refused verification differs: \(lines(controller.text))")
        try expect(!words(controller.text).contains { $0.contains("digestMismatch") }, "A diagnostic code is shown")
    }
    check("surface: an untyped failure shows the fallback reason and never a passed step") {
        var configuration = OperatorConfiguration()
        configuration.artifactName = Sample.artifactName
        configuration.verify = { throw Injected() }
        let controller = OperatorController(configuration)
        controller.choose(.verify)
        try expect(controller.text.rows.first.map(line) == row(.verify, refusedStatus, enabled: true, fallbackReason),
                   "Untyped failure differs: \(lines(controller.text))")
    }
    check("surface: verify, sign and publish each run once on their own choice and the published bytes pass the real consumer") {
        try withRoot { authority, layout in
            let counts = Counts(), controller = OperatorController(wired(authority, layout, counts))
            controller.choose(.verify)
            try expect(counts.all == [1, 0, 0], "Choosing Verify ran \(counts.all)")
            try expect(lines(controller.text) == [row(.verify, verifiedStatus, enabled: true), row(.sign, notRun, enabled: true),
                                                  row(.publish, notRun, enabled: false, signFirst)], "Verified steps differ: \(lines(controller.text))")
            controller.choose(.publish)
            try expect(counts.all == [1, 0, 0], "Publish ran before Sign")
            controller.choose(.sign)
            try expect(counts.all == [1, 1, 0] && (try names(layout.publications)).isEmpty, "Choosing Sign ran \(counts.all) or published")
            try expect(lines(controller.text) == [row(.verify, verifiedStatus, enabled: true), row(.sign, signedStatus, enabled: true),
                                                  row(.publish, notRun, enabled: true)], "Signed steps differ: \(lines(controller.text))")
            controller.choose(.publish)
            try expect(counts.all == [1, 1, 1], "Choosing Publish ran \(counts.all)")
            try expect(lines(controller.text) == [row(.verify, verifiedStatus, enabled: true), row(.sign, signedStatus, enabled: true),
                                                  row(.publish, publishedStatus, enabled: true)], "Published steps differ: \(lines(controller.text))")
            let physical = try bytes(layout.catalogue(7))
            let decoded = try verifyIndependently(physical, request: Sample.request())
            try expectFixtureCandidate(try consumer(layout).bootstrapFreshProofNamespace(envelope: physical, now: Sample.now), sequence: 7, payload: decoded.payload)
        }
    }
    check("surface: verifying again discards the earlier signature and publication results") {
        try withRoot { authority, layout in
            let counts = Counts(), controller = OperatorController(wired(authority, layout, counts))
            controller.choose(.verify); controller.choose(.sign); controller.choose(.verify)
            try expect(counts.all == [2, 1, 0], "Steps ran \(counts.all)")
            try expect(lines(controller.text) == [row(.verify, verifiedStatus, enabled: true), row(.sign, notRun, enabled: true),
                                                  row(.publish, notRun, enabled: false, signFirst)], "Re-verified steps differ: \(lines(controller.text))")
        }
    }
    check("surface: evidence changed after verification is refused at Sign with a plain reason and Publish stays locked") {
        try withRoot { authority, layout in
            let counts = Counts(), controller = OperatorController(wired(authority, layout, counts))
            controller.choose(.verify)
            let handle = try FileHandle(forWritingTo: layout.artifact)
            try handle.write(contentsOf: Data("X".utf8)); try handle.close()
            controller.choose(.sign); controller.choose(.publish)
            try expect(counts.all == [1, 1, 0], "Steps ran \(counts.all)")
            try expect(lines(controller.text) == [row(.verify, verifiedStatus, enabled: true),
                                                  row(.sign, refusedStatus, enabled: true, "The artifact does not match its approved contents."),
                                                  row(.publish, notRun, enabled: false, signFirst)], "Changed-evidence steps differ: \(lines(controller.text))")
            try expect(try checkpointFields(layout).sequence == 0 && names(layout.publications).isEmpty, "Changed evidence was signed or published")
        }
    }
    check("surface: a second Publish is refused with a plain reason and the first publication is untouched") {
        try withRoot { authority, layout in
            let counts = Counts(), controller = OperatorController(wired(authority, layout, counts))
            controller.choose(.verify); controller.choose(.sign); controller.choose(.publish)
            let before = try snapshot(layout.root)
            controller.choose(.publish)
            try expect(counts.all == [1, 1, 2] && before[ "publications/sequence-7/catalogue.json"] != nil, "Steps ran \(counts.all)")
            try expect(controller.text.rows.last.map(line) == row(.publish, refusedStatus, enabled: true, "Output for this catalogue already exists and was left as it is."),
                       "Second publish differs: \(lines(controller.text))")
            try expect(try snapshot(layout.root) == before, "A refused publish changed the first publication")
        }
    }

    for (failure, reason) in reasons {
        check("words: \(failure.rawValue) has the proposed plain reason") {
            try expect(OperatorViewText.refusalReason(failure) == reason, "Reason differs: \(OperatorViewText.refusalReason(failure))")
        }
    }
    check("words: every typed refusal has its own reason, with no code, claim or dash") {
        try expect(Set(reasons.map(\.0)) == Set(OperatorFailure.allCases) && reasons.count == OperatorFailure.allCases.count, "The reason table does not cover every refusal")
        let shown = OperatorFailure.allCases.map(OperatorViewText.refusalReason)
        try expect(Set(shown).count == shown.count && !shown.contains(fallbackReason), "Two refusals share a reason")
        for (failure, text) in zip(OperatorFailure.allCases, shown) {
            // "expired" is also the plain English word its exact copy needs, so only that code is exempt from the
            // substring guard. The exact-copy check above still rejects a reason that is the raw code alone.
            try expect(text.hasSuffix(".") && text.utf8.count <= 80 && (failure == .expired || !text.contains(failure.rawValue)),
                       "\(failure.rawValue) reason is not brief plain words: \(text)")
            for claim in claims { try expect(!text.lowercased().contains(claim), "\(failure.rawValue) reason contains \(claim)") }
        }
    }
    check("words: no visible text of the default surface makes a product claim") {
        let shown = words(OperatorController().text)
        try expect(shown.filter { !$0.isEmpty }.count >= 16, "Default surface shows too little text: \(shown)")
        for text in shown { for claim in claims { try expect(!text.lowercased().contains(claim), "Surface text contains \(claim): \(text)") } }
    }

    var painted: [Painted] = []
    check("render: the actual OperatorView paints the default and wired states as bounded pictures saved beneath .build") {
        var unwired = OperatorConfiguration()
        unwired.artifactName = Sample.artifactName
        unwired.verify = { throw OperatorFailure.digestMismatch }
        let refused = OperatorController(unwired)
        refused.choose(.verify)
        painted = [try paint("default", OperatorController()), try paint("verify-refused", refused)]
        for state in painted {
            try expect(state.width == paintedWidth * paintedScale && (300...4_000).contains(state.height), "\(state.name) has unbounded size \(state.width)x\(state.height)")
            try expect(state.distinct > 2 && state.unpainted == 0, "\(state.name) is blank or shows a stand-in for an unpainted control")
            try expect(state.png.count > 1_024 && state.png.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), "\(state.name) is not a PNG")
            try expect(state.lines.count == 4, "\(state.name) was painted without three steps")
        }
        let directory = try createOutputDirectory()
        for state in painted {
            let file = directory.appendingPathComponent("\(state.name).png")
            try state.png.write(to: file, options: .withoutOverwriting)
            try expect(try Data(contentsOf: file) == state.png, "\(state.name).png does not read back")
        }
        try expect(painted[0].pixels != painted[1].pixels || painted[0].height != painted[1].height, "Default and refused states paint identical pixels")
        let metadata: [String: Any] = [
            "kind": "patched-operator-ui-fixture-render-v1", "view": "PatchedOperator.OperatorView", "renderer": "SwiftUI ImageRenderer, offscreen",
            "pointWidth": paintedWidth, "scale": paintedScale, "appLaunched": false,
            "claim": "Visual review only. Fixture scope. No OS trust, production key or publication.",
            "states": painted.map { ["file": "\($0.name).png", "pixelWidth": $0.width, "pixelHeight": $0.height, "pngSHA256": sha($0.png), "visibleSteps": $0.lines] }]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("metadata.json"), options: .withoutOverwriting)
        print("Painted operator states kept for inspection: \(directory.path)")
    }
    check("render: the verified, signed and published states are painted from real fixture steps and differ from one another") {
        try withRoot { authority, layout in
            let controller = OperatorController(wired(authority, layout, Counts()))
            var states: [Painted] = []
            for (name, stage, status) in [("verified", OperatorStage.verify, verifiedStatus), ("signed", .sign, signedStatus), ("published", .publish, publishedStatus)] {
                controller.choose(stage)
                let state = try paint(name, controller)
                try expect(state.lines.contains { $0.contains(status) }, "\(name) was painted from the wrong state: \(state.lines)")
                try expect(state.distinct > 2 && state.unpainted == 0 && (300...4_000).contains(state.height), "\(name) is blank, unbounded or unpainted")
                states.append(state)
            }
            for (index, first) in states.enumerated() {
                for second in states.dropFirst(index + 1) {
                    try expect(first.pixels != second.pixels || first.height != second.height, "\(first.name) and \(second.name) paint identical pixels")
                }
            }
            let directory = try createOutputDirectory()
            for state in states { try state.png.write(to: directory.appendingPathComponent("\(state.name).png"), options: .withoutOverwriting) }
            print("Painted operator steps kept for inspection: \(directory.path)")
        }
    }
}
