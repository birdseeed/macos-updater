import Foundation
import Darwin
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
@_spi(Testing) import PatchedClient

// Independent fixtures contain literal plist claims and real directories. No result
// constructors, result loaders, mock scanners or application launch are used here.
private struct ApplicationsFixture {
    let base: URL
    let root: URL
    init() throws {
        base = try newDirectory("pat2705-applications")
        root = base.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    func clean() { try? FileManager.default.removeItem(at: base) }
    @discardableResult func app(_ name: String, version: String = "3.7", build: String = "91", display: String = "Literal Copy", metadata: Bool = true) throws -> URL {
        let bundle = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        if metadata {
            let plist = ["CFBundleDisplayName": display, "CFBundleIdentifier": "example.same-copy", "CFBundleShortVersionString": version, "CFBundleVersion": build]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        }
        return bundle
    }
    @MainActor func controller(_ probe: ApplicationsReadProbe? = nil, roots: [String]? = nil) -> LocalApplicationsController {
        let inventory: LocalApplicationInventory
        if let probe {
            inventory = LocalApplicationInventory(fixtureRoots: roots ?? [root.path], observer: { event in probe.read(event) })
        } else {
            inventory = LocalApplicationInventory(fixtureRoots: roots ?? [root.path])
        }
        return LocalApplicationsController(inventory: inventory)
    }
}

/// The scanner's SPI reports a physical read boundary only. Blocking is bounded,
/// happens on the scanner actor, and never supplies a result or blocks MainActor.
private final class ApplicationsReadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    private var blockNext = false
    private var timedOut = false
    private let release = DispatchSemaphore(value: 0)
    var count: Int { lock.lock(); defer { lock.unlock() }; return reads }
    var timeout: Bool { lock.lock(); defer { lock.unlock() }; return timedOut }
    func arm() { lock.lock(); blockNext = true; lock.unlock() }
    func open() { release.signal() }
    func read(_ event: LocalInventoryReadEvent) {
        lock.lock(); reads += 1; let block = blockNext; blockNext = false; lock.unlock()
        if block && release.wait(timeout: .now() + 8) == .timedOut {
            lock.lock(); timedOut = true; lock.unlock()
        }
    }
}

@MainActor private func completed(_ controller: LocalApplicationsController) async throws -> LocalInventoryObservation {
    controller.scan(); await controller.waitUntilIdle()
    guard let observation = controller.observation else { throw CheckFailure(description: "Explicit scan did not publish its actual scanner observation") }
    try expect(controller.phase == .finished && controller.text.scanEnabled, "Finished observation did not restore Scan again")
    return observation
}
@MainActor private func applicationsCapture<V: View>(_ view: V, width: Int, height: Int, dark: Bool) throws -> CGImage {
    let app = NSApplication.shared
    if app.activationPolicy() != .prohibited { _ = app.setActivationPolicy(.prohibited) }
    try expect(app.activationPolicy() == .prohibited && !app.isActive, "Inactive prohibited fixture process unavailable")
    let content = view
        .frame(width: CGFloat(width), height: CGFloat(height)).background(dark ? Color.black : Color.white)
        .environment(\.colorScheme, dark ? .dark : .light)
    let hosting = NSHostingView(rootView: content)
    hosting.frame = NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
    hosting.bounds = hosting.frame
    hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    hosting.wantsLayer = true
    let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = hosting.appearance
    window.contentView = hosting
    // Never order, activate or run this fixture window. Close only what we own.
    defer { window.close() }
    func assertUnshown() throws {
        try expect(app.activationPolicy() == .prohibited && !app.isActive && !window.isVisible,
            "Owned capture fixture became active or visible")
    }
    try assertUnshown()
    hosting.needsLayout = true
    hosting.layoutSubtreeIfNeeded()
    hosting.needsDisplay = true
    hosting.displayIfNeeded(); window.displayIfNeeded(); try assertUnshown()
    // Fixed lifecycle settlement, not a capture retry or wait-until-success loop.
    let deadline = Date().addingTimeInterval(0.20)
    while Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.01)))
    }
    try assertUnshown()
    hosting.layoutSubtreeIfNeeded(); hosting.displayIfNeeded(); window.displayIfNeeded(); try assertUnshown()
    guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        throw CheckFailure(description: "Applications native cache bitmap unavailable")
    }
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    try assertUnshown()
    guard let captured = bitmap.cgImage, width > 0, height > 0,
          captured.width % width == 0, captured.height % height == 0,
          captured.width / width == captured.height / height,
          (1...4).contains(captured.width / width) else {
        throw CheckFailure(description: "Actual native capture has unsupported dimensions or backing scale")
    }
    // Normalise actual native pixels to the frozen 2x output and explicit RGBA.
    // This is not a claim that the never-shown window had a native 2x backing.
    guard let context = CGContext(data: nil, width: width * 2, height: height * 2,
        bitsPerComponent: 8, bytesPerRow: width * 8, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw CheckFailure(description: "Native capture normalisation unavailable")
    }
    context.interpolationQuality = .high
    context.draw(captured, in: CGRect(x: 0, y: 0, width: CGFloat(width * 2), height: CGFloat(height * 2)))
    guard let image = context.makeImage() else { throw CheckFailure(description: "Native capture normalisation failed") }
    try assertUnshown()
    return image
}

private struct ApplicationsPixelMetrics {
    var colours = Set<UInt32>()
    var placeholder = 0
    var bodyInk = 0
    var bodyBackground = 0
    var bodyPixels = 0
    var headerInk = 0
    var bodyMagenta = 0
    // Identical predicate for product captures and independent capability controls.
    var bodyVisible: Bool {
        bodyPixels > 0 && bodyInk >= 100 && bodyInk * 5 < bodyPixels * 2 && bodyBackground * 5 >= bodyPixels * 3
    }
    // CHECK-MODIFIED: native NSHostingView paints real yellow/cyan content, including
    // the accent button. ImageRenderer's legacy RGB sentinel is diagnostic here;
    // independent colour controls and blank/header-only controls exercise this predicate.
    func validNativeCapture(bodyExpected: Bool) -> Bool {
        colours.count > 8 && headerInk >= 100 && (!bodyExpected || bodyVisible)
    }
}
private func applicationsPixels(_ image: CGImage, dark: Bool) throws -> ApplicationsPixelMetrics {
    guard let pixels = image.dataProvider?.data as Data?, image.bitsPerPixel == 32,
          pixels.count >= image.bytesPerRow * image.height else { throw CheckFailure(description: "Normalised RGBA pixels unavailable") }
    // CHECK-MODIFIED: borrow checked bytes once; preserve every pixel and metric.
    return pixels.withUnsafeBytes { (pixels: UnsafeRawBufferPointer) in
        var result = ApplicationsPixelMetrics()
        for line in 0..<image.height {
            for offset in stride(from: line * image.bytesPerRow, to: line * image.bytesPerRow + image.width * 4, by: 4) {
                let (a, g, b) = (pixels[offset], pixels[offset + 1], pixels[offset + 2])
                result.colours.insert(UInt32(a) << 16 | UInt32(g) << 8 | UInt32(b))
                if (190...215).contains(g) && ((a > 240 && b < 20) || (b > 240 && a < 20)) { result.placeholder += 1 }
                let column = (offset - line * image.bytesPerRow) / 4
                let visible = pixels[offset + 3] > 190
                let contrasting = visible && (dark ? max(a, max(g, b)) > 80 : min(a, min(g, b)) < 175)
                let background = visible && (dark ? max(a, max(g, b)) < 35 : min(a, min(g, b)) > 220)
                // CGImage rows use PNG top-origin order. Header ink independently
                // confirms this orientation; none counts towards the body assertion.
                if column >= 40 && column < image.width - 40 {
                    if line >= 40 && line < 200 && contrasting { result.headerInk += 1 }
                    if line >= 300 && line < image.height - 40 {
                        result.bodyPixels += 1
                        if contrasting { result.bodyInk += 1 }
                        if background { result.bodyBackground += 1 }
                        if visible && a > 240 && g < 15 && b > 240 { result.bodyMagenta += 1 }
                    }
                }
            }
        }
        return result
    }
}
private func applicationsSavePNG(_ image: CGImage, to path: URL) throws {
    let bytes = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil) else { throw CheckFailure(description: "PNG destination unavailable") }
    CGImageDestinationAddImage(destination, image, nil)
    try expect(CGImageDestinationFinalize(destination), "PNG encoding failed")
    try (bytes as Data).write(to: path)
}
@MainActor private func applicationsPaint(_ controller: LocalApplicationsController, dark: Bool, name: String, output: URL) throws {
    let before = controller.text
    // The second size is the sheet's outer aspect, content only: Done is not shown.
    for (suffix, width, height) in [("", 460, 620), ("-sheet-content", 620, 460)] {
        let image = try applicationsCapture(LocalApplicationsView(controller: controller), width: width, height: height, dark: dark)
        let capturePath = output.appendingPathComponent(name + suffix + (dark ? "-dark.png" : "-light.png"))
        // Retain the actual capture before any validation can throw.
        try applicationsSavePNG(image, to: capturePath)
        if suffix.isEmpty {
            try expect(image.width == 920 && image.height == 1240 && image.bitsPerPixel == 32, "Unexpected compact render geometry")
        } else {
            try expect(image.width == 1240 && image.height == 920 && image.bitsPerPixel == 32, "Unexpected sheet-content render geometry")
        }
        let measured = try applicationsPixels(image, dark: dark)
        print("Applications capture \(capturePath.path): colours=\(measured.colours.count), legacyPlaceholderMatches=\(measured.placeholder), headerInk=\(measured.headerInk), bodyInk=\(measured.bodyInk), bodyBackground=\(measured.bodyBackground)")
        try expect(measured.validNativeCapture(bodyExpected: !before.roots.isEmpty),
            "Shared native-render acceptance rejected retained capture \(capturePath.path)")
        try expect(measured.colours.count > 8, "Insufficient render colours: \(measured.colours.count); retained \(capturePath.path)")
        try expect(measured.headerInk >= 100, "Native capture has no visible upper header or has inverted pixel orientation")
        if !before.roots.isEmpty {
            try expect(measured.bodyVisible,
                "Observed folder/body content is absent, transparent or a solid fill in \(name)\(suffix): ink=\(measured.bodyInk), background=\(measured.bodyBackground), pixels=\(measured.bodyPixels)")
        }
        try expect(controller.text == before, "Rendering changed the presentation")
    }
}

@MainActor func registerLocalApplicationsChecks() {
    check("applications: native capture observes a physical scroll-body probe and refuses header-only visibility") {
        let output = try newDirectory("pat2705-capture-capability")
        for (suffix, width, height) in [("compact", 460, 620), ("sheet-content", 620, 460)] {
            for dark in [false, true] {
                for populated in [false, true] {
                    // Independent literal layout, with its body beginning at 150pt.
                    // No product display values, callbacks or result suppliers enter it.
                    let specimen = VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "Independent fixture header")
                            .frame(maxWidth: .infinity, minHeight: 130, maxHeight: 130, alignment: .topLeading)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                if populated {
                                    Rectangle().fill(Color(red: 1, green: 0, blue: 1)).frame(width: 40, height: 40)
                                } else {
                                    Color.clear.frame(width: 40, height: 40)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(20)
                    let image = try applicationsCapture(specimen, width: width, height: height, dark: dark)
                    let label = (populated ? "probe-" : "header-only-") + suffix + (dark ? "-dark.png" : "-light.png")
                    try applicationsSavePNG(image, to: output.appendingPathComponent(label))
                    let measured = try applicationsPixels(image, dark: dark)
                    print("Capture control \(label): bodyInk=\(measured.bodyInk), bodyBackground=\(measured.bodyBackground), bodyMagenta=\(measured.bodyMagenta), bodyVisible=\(measured.bodyVisible)")
                    try expect(measured.headerInk >= 100, "Independent fixture header absent or vertically inverted")
                    if populated {
                        // Forty logical points normalise to eighty output pixels;
                        // allow only a bounded edge-interpolation loss around 6400.
                        try expect((5000...6800).contains(measured.bodyMagenta), "Actual 40x40 ScrollView body probe is absent, clipped or incorrectly scaled: \(measured.bodyMagenta)")
                        try expect(measured.bodyVisible, "The unchanged visibility predicate rejected the independent visible scroll body")
                    } else {
                        try expect(measured.bodyMagenta == 0 && !measured.bodyVisible,
                            "Header-only native capture falsely passed the shared body visibility predicate")
                    }
                }
            }
        }
        print("Applications native capture controls: \(output.path)")
    }
    check("applications: native yellow and cyan are valid colours while blank and header-only captures are rejected") {
        let output = try newDirectory("pat2705-native-colour-controls")
        var captures: [(kind: String, label: String, metrics: ApplicationsPixelMetrics)] = []
        for (suffix, width, height) in [("compact", 460, 620), ("sheet-content", 620, 460)] {
            for dark in [false, true] {
                for kind in ["blank", "header-only", "yellow", "cyan"] {
                    // Literal native colours deliberately overlap the old unsupported
                    // ImageRenderer sentinel heuristic. They are ordinary valid content.
                    let specimen = VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "Independent native colour header")
                            .opacity(kind == "blank" ? 0 : 1)
                            .frame(maxWidth: .infinity, minHeight: 130, maxHeight: 130, alignment: .topLeading)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                if kind == "yellow" {
                                    Rectangle().fill(Color(red: 1, green: 0.8, blue: 0)).frame(width: 40, height: 40)
                                } else if kind == "cyan" {
                                    Rectangle().fill(Color(red: 0, green: 0.8, blue: 1)).frame(width: 40, height: 40)
                                } else {
                                    Color.clear.frame(width: 40, height: 40)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(20)
                    let image = try applicationsCapture(specimen, width: width, height: height, dark: dark)
                    let label = kind + "-" + suffix + (dark ? "-dark.png" : "-light.png")
                    let path = output.appendingPathComponent(label)
                    // Retain every scheme/size before the expected failing assertion.
                    try applicationsSavePNG(image, to: path)
                    let measured = try applicationsPixels(image, dark: dark)
                    print("Native colour control \(path.path): colours=\(measured.colours.count), legacyPlaceholderMatches=\(measured.placeholder), headerInk=\(measured.headerInk), bodyInk=\(measured.bodyInk), bodyBackground=\(measured.bodyBackground), bodyVisible=\(measured.bodyVisible), validNativeCapture=\(measured.validNativeCapture(bodyExpected: true))")
                    captures.append((kind, label, measured))
                }
            }
        }
        for capture in captures {
            let measured = capture.metrics
            if capture.kind == "yellow" || capture.kind == "cyan" {
                try expect(measured.placeholder > 1000,
                    "Literal native colour did not exercise the legacy sentinel heuristic in \(capture.label): \(measured.placeholder)")
                try expect(measured.colours.count > 8 && measured.headerInk >= 100 && measured.bodyVisible,
                    "Independent native colour fixture failed the unchanged colour diversity/header/body conditions in \(capture.label)")
                try expect(measured.validNativeCapture(bodyExpected: true),
                    "Valid literal native colour was rejected by shared native-render acceptance in \(capture.label); retained \(output.path)")
            } else {
                try expect(!measured.validNativeCapture(bodyExpected: true),
                    "Blank or header-only capture falsely passed shared native-render acceptance in \(capture.label)")
            }
        }
        print("Applications independent native colour controls: \(output.path)")
    }
    check("applications: construction, repeated view opening and light/dark painting are inert") {
        let f = try ApplicationsFixture(); defer { f.clean() }
        try f.app("NeverRead.app")
        let probe = ApplicationsReadProbe(), c = f.controller(probe)
        let output = try newDirectory("pat2705-idle-paints")
        for dark in [false, true] { try applicationsPaint(c, dark: dark, name: "idle", output: output) }
        _ = LocalApplicationsView(controller: c); _ = LocalApplicationsView(controller: c)
        await c.waitUntilIdle()
        try expect(probe.count == 0 && c.phase == .idle && c.observation == nil, "Opening or rendering performed a scan")
        try expect(c.text.rows.isEmpty && c.text.observedAt == nil && c.text.roots.isEmpty, "Unscanned view invented observed rows/time/scope")
        try expect(c.text.scanTitle == "Scan" && c.text.scanEnabled, "Initial explicit Scan is unavailable")
        try expect(!c.text.status.lowercased().contains("found"), "Unscanned state claims an app count")
    }
    check("applications: an explicit scan physically reads and preserves duplicate copies, claims and locations") {
        let f = try ApplicationsFixture(); defer { f.clean() }
        let z = try f.app("Z.app"), a = try f.app("A.app")
        let probe = ApplicationsReadProbe(), c = f.controller(probe)
        let r = try await completed(c)
        try expect(probe.count == 2 && r.applications.map(\.path) == [a.path, z.path], "Controller bypassed real scanner reads or collapsed duplicates")
        try expect(c.text.rows.count == 2 && c.text.rows.map(\.location) == [a.path, z.path], "Presentation lost physical copy paths")
        for row in c.text.rows {
            try expect(row.name == "Literal Copy" && row.version.contains("3.7") && row.build.contains("91"), "Literal name/version/build absent")
            try expect(row.metadata.lowercased().contains("observed") || row.metadata.lowercased().contains("unverified"), "Metadata status claims no observation boundary")
        }
        try expect(c.text.scanTitle == "Scan again", "Finished action is not explicit Scan again")
    }
    check("applications: fixture provenance, observation time and actual root scope are visible") {
        let f = try ApplicationsFixture(); defer { f.clean() }; try f.app("Time.app")
        let c = f.controller(), start = Date(), r = try await completed(c), end = Date()
        try expect(r.startedAt >= start && r.finishedAt >= r.startedAt && r.finishedAt <= end, "Observation timestamps are not bounded by the real scan")
        try expect(c.text.provenance?.lowercased().contains("fixture") == true, "Fixture observation is not conspicuously labelled")
        try expect(c.text.observedAt?.isEmpty == false && c.text.observedAt!.rangeOfCharacter(from: .decimalDigits) != nil, "No observed date/time")
        try expect(c.text.roots.contains { $0.contains(f.root.path) && $0.lowercased().contains("scanned") && $0.lowercased().contains("fixture") }, "Actual fixture scope/status missing")
    }
    check("applications: one scan in flight ignores repeated requests and publishes only on completion") {
        let f = try ApplicationsFixture(); defer { f.clean() }; try f.app("Blocked.app")
        let p = ApplicationsReadProbe(); p.arm(); defer { p.open() }
        let c = f.controller(p); c.scan()
        try expect(c.phase == .scanning && !c.text.scanEnabled, "Scan did not enter visible busy state synchronously")
        try await until("Applications physical scanner read") { p.count == 1 }
        try expect(c.observation == nil && c.text.rows.isEmpty, "Published an unfinished observation")
        let output = try newDirectory("pat2705-scanning-paints")
        for dark in [false, true] { try applicationsPaint(c, dark: dark, name: "scanning", output: output) }
        for _ in 0..<5 { c.scan() }
        try expect(p.count == 1, "Repeated scans overlapped")
        p.open(); await c.waitUntilIdle()
        try expect(c.phase == .finished && c.observation?.generation == 1 && p.count == 1 && !p.timeout, "Repeated requests queued extra scans or blocked MainActor")
    }
    check("applications: refresh retains old immutable observation while clearly scanning and observes changed files") {
        let f = try ApplicationsFixture(); defer { f.clean() }; try f.app("Changing.app")
        let p = ApplicationsReadProbe(), c = f.controller(p), old = try await completed(c)
        try f.app("Changing.app", version: "8.4", build: "202")
        p.arm(); defer { p.open() }; c.scan()
        try expect(c.phase == .scanning && c.observation == old && c.text.status.lowercased().contains("scanning"), "Refresh hid previous observation or presented it as fresh")
        try await until("refresh physical read") { p.count == 2 }
        try expect(c.observation == old && c.text.rows.first?.version.contains("3.7") == true, "Refresh published changed metadata before scanner completion")
        p.open(); await c.waitUntilIdle()
        try expect(c.observation?.generation == 2 && c.observation?.sessionID == old.sessionID && c.text.rows.first?.version.contains("8.4") == true && c.text.rows.first?.build.contains("202") == true && !p.timeout, "Explicit refresh did not reuse its scanner and read changed files")
    }
    check("applications: complete empty scanned scope uses qualified empty wording") {
        let f = try ApplicationsFixture(); defer { f.clean() }; let c = f.controller()
        let r = try await completed(c)
        let text = c.text.allLines.joined(separator: " ").lowercased()
        try expect(r.completeness == .complete && c.text.rows.isEmpty, "Empty scanned fixture was not complete")
        try expect(text.contains("no applications found") && text.contains("scanned folders"), "Empty wording fails to limit its claim to scanned folders")
        try expect(!text.contains("no apps installed") && !text.contains("no applications installed"), "Empty scope became a global installation claim")
    }
    check("applications: absent roots remain explicitly absent without an invented scanned-empty claim") {
        let f = try ApplicationsFixture(); defer { f.clean() }
        let missing = f.base.appendingPathComponent("Absent").path, c = f.controller(roots: [missing])
        let r = try await completed(c), words = c.text.allLines.joined(separator: " ").lowercased()
        try expect(r.roots.first?.status == .absent && c.text.roots.contains { $0.contains(missing) && $0.lowercased().contains("absent") }, "Absent root not disclosed")
        try expect(!words.contains("no applications found") && !words.contains("no apps installed"), "Absent root was presented as a scanned-empty result")
    }
    check("applications: refused zero-row root is incomplete with an explanation, never empty success") {
        let f = try ApplicationsFixture(); defer { f.clean() }
        let file = f.base.appendingPathComponent("NotDirectory"); try Data("file".utf8).write(to: file)
        let c = f.controller(roots: [file.path]), r = try await completed(c)
        let words = c.text.allLines.joined(separator: " ").lowercased()
        try expect(r.completeness == .incomplete && c.text.rows.isEmpty && !c.text.issues.isEmpty, "Refused scope hid its incomplete result/issues")
        try expect(c.text.roots.contains { $0.contains(file.path) && $0.lowercased().contains("refused") }, "Refused root status missing")
        try expect(words.contains("incomplete") && !words.contains("no applications found") && !words.contains("no apps installed"), "Incomplete zero rows claim empty success")
    }
    check("applications: unavailable root is distinct from absent and scanned-empty scope") {
        let f = try ApplicationsFixture(); defer { f.clean() }
        let c = f.controller(roots: [""]), r = try await completed(c)
        let words = c.text.allLines.joined(separator: " ").lowercased()
        try expect(r.roots.first?.status == .unavailable && r.completeness != .complete && c.text.rows.isEmpty, "Unavailable root fabricated a complete scope")
        try expect(c.text.roots.contains { $0.lowercased().contains("unavailable") } && !c.text.issues.isEmpty, "Unavailable root and explanation are not visible")
        try expect(!words.contains("no applications found") && !words.contains("no apps installed"), "Unavailable scope became empty success")
    }
    check("applications: mixed good and unavailable metadata retains rows and explicit unknown values") {
        let f = try ApplicationsFixture(); defer { f.clean() }
        let missing = try f.app("Unknown.app", metadata: false); try f.app("Good.app")
        let c = f.controller(), r = try await completed(c)
        guard let row = c.text.rows.first(where: { $0.location == missing.path }) else { throw CheckFailure(description: "Unavailable metadata erased observed physical row") }
        try expect(r.completeness == .incomplete && c.text.rows.count == 2 && !c.text.issues.isEmpty, "Partial observation became complete or lost rows")
        try expect(row.name == "Unknown" && row.version.lowercased().contains("unavailable") && row.build.lowercased().contains("unavailable") && row.metadata.lowercased().contains("unavailable"), "Missing claims became blank or invented metadata")
    }
    check("applications: hostile and long metadata remains exact literal display data") {
        let f = try ApplicationsFixture(); defer { f.clean() }
        let hostile = "**[Open](file:///tmp/never)** <script>alert(1)</script> %@ " + String(repeating: "W", count: 800)
        let version = "[9.1](https://invalid.example)", build = "<b>123</b>"
        try f.app("Hostile.app", version: version, build: build, display: hostile)
        let c = f.controller(); _ = try await completed(c)
        try expect(c.text.rows.first?.name == hostile && c.text.rows.first?.version.contains(version) == true && c.text.rows.first?.build.contains(build) == true, "Observed metadata was interpreted, shortened or replaced")
        let output = try newDirectory("pat2705-hostile-paints")
        for dark in [false, true] { try applicationsPaint(c, dark: dark, name: "hostile-long", output: output) }
    }
    check("applications: malformed metadata retains valid fields without declaring every claim unavailable") {
        let f = try ApplicationsFixture(); defer { f.clean() }
        let bundle = try f.app("Malformed.app")
        let plist: [String: Any] = ["CFBundleDisplayName": "Literal Malformed", "CFBundleIdentifier": 9,
            "CFBundleShortVersionString": "3.7", "CFBundleVersion": "91"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        let c = f.controller(), r = try await completed(c)
        guard let observed = r.applications.first(where: { $0.path == bundle.path }),
              let row = c.text.rows.first(where: { $0.location == bundle.path }) else {
            throw CheckFailure(description: "Malformed numeric identifier erased valid physical observation")
        }
        try expect(observed.metadataDisposition == .malformed && observed.claimedBundleIdentifier == nil && observed.claimedShortVersion == "3.7" && observed.claimedBuild == "91", "Actual malformed fixture failed to retain its independently valid fields")
        try expect(row.name == "Literal Malformed" && row.version.contains("3.7") && row.build.contains("91"), "Presentation lost valid claims beside malformed metadata")
        let status = row.metadata.lowercased()
        try expect(status.contains("malformed") && status.contains("unverified") && !status.contains("claims unavailable"), "Metadata status falsely declares all displayed claims unavailable: \(row.metadata)")
    }
    check("applications: every state disclaims unchecked updates and offers only scan authority") {
        let f = try ApplicationsFixture(); defer { f.clean() }; try f.app("Claims.app")
        let c = f.controller()
        for scanned in [false, true] {
            if scanned { _ = try await completed(c) }
            let words = c.text.allLines.joined(separator: " ").lowercased()
            try expect(words.contains("update availability has not been checked"), "Unchecked update availability not disclosed")
            for claim in ["all up to date", "up-to-date", "verified publisher", "homebrew managed", "ready to install", "update available"] { try expect(!words.contains(claim), "Display invented authority: \(claim)") }
            if let r = c.observation { try expect(r.authorityUnknown && !r.installationAllowed, "UI observation grants authority") }
        }
    }
    check("applications: actual ClientView retains a controller and exposes an explicit Applications button and sheet") {
        let view = code(try source("Sources/PatchedClient/ClientView.swift"))
        try expect(view.contains("@StateObject") && view.contains("LocalApplicationsController()"), "ClientView does not retain one Applications controller")
        try expect(view.contains("Button") && view.contains("Applications") && view.contains(".sheet(") && view.contains("LocalApplicationsView(controller:"), "No actual Applications button/sheet composition")
        try expect(!view.contains(".scan()") && !view.contains(".onAppear") && !view.contains(".task"), "Opening the Applications sheet starts work")
        for path in ["Sources/PatchedClient/ClientView.swift", "Sources/PatchedClient/ClientController.swift", "Sources/PatchedApp/PatchedApp.swift"] { try expect(!code(try source(path)).contains("LocalApplicationInventory"), "Legacy composition owns scanner: \(path)") }
    }
    check("applications: real view uses scrolling literal text, generic symbol, keyboard scan and system fonts") {
        let view = code(try source("Sources/PatchedClient/LocalApplicationsView.swift"))
        try expect(view.contains("ScrollView") && view.contains("Text(verbatim:") && view.contains("Image(systemName:"), "Applications view lacks scrolling literal rows or generic symbol")
        try expect(view.contains("controller.scan()") && view.contains("Button") && view.contains(".keyboardShortcut(") && view.contains(".disabled("), "Explicit keyboard-capable scan control is absent")
        for field in [".name", ".version", ".build", ".location", ".metadata", ".roots", ".issues", ".observedAt", ".provenance", ".notice"] { try expect(view.contains(field), "Actual view omits \(field)") }
        for forbidden in [".onAppear", ".task", "Timer", "NSWorkspace", "NSImage(contentsOf", "Link(", "AttributedString", "Font.custom", ".custom(", "NSFont(name"] { try expect(!view.contains(forbidden), "View contains an implicit effect, interpreter or non-system font: \(forbidden)") }
    }
    check("applications: default controller owns one ordinary scanner with no arbitrary result injection or external effects") {
        let controller = code(try source("Sources/PatchedClient/LocalApplicationsController.swift"))
        try expect(controller.components(separatedBy: "LocalApplicationInventory()").count == 2, "Default controller must construct exactly one ordinary scanner")
        for forbidden in ["URLSession", "NSWorkspace", "Process(", "Timer", ".onAppear", ".task", "ArtifactInspector", "Transaction", "Installer", "FileManager", "Data(contentsOf:"] { try expect(!controller.contains(forbidden), "Controller bypasses scanner or introduces effects: \(forbidden)") }
        let lines = controller.split(separator: "\n").map(String.init)
        for (i, line) in lines.enumerated() where line.contains("public init(") && line.contains("inventory:") {
            try expect(line.contains("@_spi(Testing)") || (i > 0 && lines[i - 1].contains("@_spi(Testing)")), "Scanner injection escaped Testing SPI")
        }
        try expect(!controller.contains("async -> LocalInventoryObservation") && !controller.contains("loader:"), "Controller accepts an arbitrary outcome supplier")
    }
    check("applications: compact light/dark populated, partial and empty views paint without additional reads") {
        let f = try ApplicationsFixture(); defer { f.clean() }; try f.app("Visible.app")
        let p = ApplicationsReadProbe(), c = f.controller(p); _ = try await completed(c)
        let output = try newDirectory("pat2705-state-paints")
        let before = p.count
        for dark in [false, true] { try applicationsPaint(c, dark: dark, name: "populated", output: output) }
        try expect(p.count == before, "Rendering repeated a filesystem scan")
        try f.app("Missing.app", metadata: false); _ = try await completed(c)
        for dark in [false, true] { try applicationsPaint(c, dark: dark, name: "partial", output: output) }
        let empty = try ApplicationsFixture(); defer { empty.clean() }; let e = empty.controller(); _ = try await completed(e)
        for dark in [false, true] { try applicationsPaint(e, dark: dark, name: "empty", output: output) }
        print("Applications offscreen PNGs: \(output.path)")
    }
}
