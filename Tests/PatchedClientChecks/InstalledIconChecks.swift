import Foundation
import Darwin
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import SwiftUI
import AppKit
@_spi(Testing) import PatchedClient

// Independent inert fixtures, literal limits and expectations. No downloaded assets.
private func iconPNG(_ red: UInt8 = 255, width: Int = 64, height: Int = 64) throws -> Data {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for i in stride(from: 0, to: pixels.count, by: 4) {
        pixels[i] = red; pixels[i + 1] = 255 - red; pixels[i + 3] = 255
    }
    let bytes = Data(pixels)
    guard let provider = CGDataProvider(data: bytes as CFData),
          let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
              provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
        throw CheckFailure(description: "Icon fixture CGImage unavailable")
    }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
        throw CheckFailure(description: "Icon fixture encoder unavailable")
    }
    CGImageDestinationAddImage(destination, image, nil)
    try expect(CGImageDestinationFinalize(destination), "Icon fixture PNG encoding failed")
    return output as Data
}
private func iconBE(_ value: Int) -> Data {
    let n = UInt32(value)
    return Data([UInt8((n >> 24) & 255), UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255)])
}
private func iconICNS(_ png: Data) -> Data {
    Data("icns".utf8) + iconBE(png.count + 16) + Data("icp6".utf8) + iconBE(png.count + 8) + png
}
// Native fixture qualification only: never supplies a productive scanner outcome.
private func iconTwoEntryICNS() throws -> Data {
    let small = try iconPNG(width: 64, height: 64), large = try iconPNG(width: 128, height: 128)
    let body = Data("icp6".utf8) + iconBE(small.count + 8) + small +
        Data("ic07".utf8) + iconBE(large.count + 8) + large
    return Data("icns".utf8) + iconBE(body.count + 8) + body
}
private func iconFixtureFailure(_ label: String, _ reason: String) -> CheckFailure {
    CheckFailure(description: "FIXTURE-PREFLIGHT-UNSUPPORTED [" + label + "]: " + reason +
        "; setup/OS decoder diagnostic, never meaningful feature RED")
}
private func iconQualifyFixture(_ bytes: Data, label: String, type: String,
                                minimumCount: Int, expectedDimensions: Set<Int>) throws {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(bytes as CFData, sourceOptions),
          let actualType = CGImageSourceGetType(source) else {
        throw iconFixtureFailure(label, "native ImageIO source/type unavailable")
    }
    guard (actualType as String) == type else {
        throw iconFixtureFailure(label, "unexpected native image type " + (actualType as String))
    }
    let count = CGImageSourceGetCount(source)
    guard count >= minimumCount && count <= 16 else {
        throw iconFixtureFailure(label, "native sourceCount=" + String(count) +
            ", required " + String(minimumCount) + "...16")
    }
    var observedDimensions = Set<Int>()
    for index in 0..<count {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, sourceOptions) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue == height.intValue, expectedDimensions.contains(width.intValue) else {
            throw iconFixtureFailure(label, "unexpected native representation dimensions at " + String(index))
        }
        observedDimensions.insert(width.intValue)
        let thumbnailOptions = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
            kCGImageSourceShouldCache: false] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, thumbnailOptions),
              image.width == 64, image.height == 64 else {
            throw iconFixtureFailure(label, "native 64px thumbnail unavailable at " + String(index))
        }
        var rgba = [UInt8](repeating: 0, count: 16_384)
        let rendered = rgba.withUnsafeMutableBytes { memory -> Bool in
            guard let context = CGContext(data: memory.baseAddress, width: 64, height: 64,
                bitsPerComponent: 8, bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
            return true
        }
        guard rendered && rgba[0] > 240 && rgba[1] < 10 && rgba[2] < 10 && rgba[3] == 255 else {
            throw iconFixtureFailure(label, "native decoded pixels do not match the solid red inert fixture")
        }
    }
    guard observedDimensions == expectedDimensions else {
        throw iconFixtureFailure(label, "native ImageIO did not expose every required physical representation")
    }
}
@MainActor func registerInstalledIconFixturePreflightChecks() {
    check("installed icon fixture preflight: native PNG, ICNS and padded PNG have genuine metadata/thumbnails/pixels") {
        let png = try iconPNG()
        var padded = png
        try expect(padded.count < 1_048_576, "FIXTURE-PREFLIGHT-UNSUPPORTED: PNG fixture exceeds input ceiling")
        padded.append(Data(repeating: 0, count: 1_048_576 - padded.count))
        try iconQualifyFixture(png, label: "original PNG", type: "public.png", minimumCount: 1, expectedDimensions: [64])
        try iconQualifyFixture(iconICNS(png), label: "single-entry ICNS", type: "com.apple.icns", minimumCount: 1, expectedDimensions: [64])
        try iconQualifyFixture(padded, label: "padded 1MiB PNG", type: "public.png", minimumCount: 1, expectedDimensions: [64])
        try iconQualifyFixture(iconTwoEntryICNS(), label: "two-entry ICNS", type: "com.apple.icns", minimumCount: 2, expectedDimensions: [64, 128])
    }
    // CAPTURE PREREQUISITE CONTROL BEGIN
    check("installed icon capture preflight: hidden native ScrollView red and blank qualify actual-view capture") {
        InstalledIconCaptureBudget.elapsed = 0
        InstalledIconCaptureBudget.qualified = false
        let positive = try installedIconNativeRedPixels(ScrollView {
            Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1).frame(width: 64, height: 64)
        })
        let negative = try installedIconNativeRedPixels(ScrollView { Color.white.frame(width: 64, height: 64) })
        installedIconCaptureRequire(positive >= negative + 64, "known red/blank capture controls not qualified")
        InstalledIconCaptureBudget.qualified = true
        print("ICON-CAPTURE-PREFLIGHT red=\(positive) blank=\(negative) qualified=true")
    }
    // CAPTURE PREREQUISITE CONTROL END
}
private struct IconFixture {
    let base: URL, root: URL
    init() throws {
        base = try newDirectory("pat2660-icon")
        root = base.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    func clean() { try? FileManager.default.removeItem(at: base) }
    func app(_ name: String = "A.app", claim: Any? = "Icon.png", bytes: Data? = nil) throws -> URL {
        let app = root.appendingPathComponent(name), contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleDisplayName": "Same", "CFBundleIdentifier": "example.same",
            "CFBundleShortVersionString": "2", "CFBundleVersion": "7"]
        if let claim { plist["CFBundleIconFile"] = claim }
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        if let bytes { try bytes.write(to: contents.appendingPathComponent("Resources/Icon.png")) }
        return app
    }
    func scanner(_ observer: (@Sendable (LocalInventoryReadEvent) -> Void)? = nil) -> LocalApplicationInventory {
        LocalApplicationInventory(fixtureRoots: [root.path], observer: observer)
    }
}
private func iconRow(_ observation: LocalInventoryObservation, _ app: URL) throws -> LocalApplicationObservation {
    guard let row = observation.applications.first(where: { $0.path == app.path }) else {
        throw CheckFailure(description: "Expected physical icon fixture row missing")
    }
    try expect(row.authorityUnknown && !row.installationAllowed && observation.authorityUnknown && !observation.installationAllowed,
               "Icon observation granted authority")
    return row
}
private func iconIdentity(_ row: LocalApplicationObservation) throws {
    try expect(row.displayName == "Same" && row.claimedBundleIdentifier == "example.same" &&
        row.claimedShortVersion == "2" && row.claimedBuild == "7" && row.metadataDisposition == .observed,
        "Optional icon failure changed independent metadata")
}
private final class IconProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0, decodes = 0
    var counts: (Int, Int) { lock.lock(); defer { lock.unlock() }; return (reads, decodes) }
    func event(_ event: LocalInventoryReadEvent) {
        lock.lock(); defer { lock.unlock() }
        if case .beforeIconRead = event { reads += 1 }
        if case .beforeIconDecode = event { decodes += 1 }
    }
}
private final class IconReadHold: @unchecked Sendable {
    private let lock = NSLock(), release = DispatchSemaphore(value: 0)
    private var held = false, used = false, expired = false
    var state: (Bool, Bool) { lock.lock(); defer { lock.unlock() }; return (held, expired) }
    func open() { release.signal() }
    func event(_ event: LocalInventoryReadEvent) {
        guard case .beforeIconRead = event else { return }
        lock.lock()
        if used { lock.unlock(); return }
        used = true; held = true; lock.unlock()
        let timeout = release.wait(timeout: .now() + 8) == .timedOut
        lock.lock(); held = false; expired = timeout; lock.unlock()
    }
}
@MainActor func registerInstalledIconChecks() {
    for format in ["png", "icns"] {
        check("installed icon: real inert \(format) becomes eager per-copy pixels") {
            let f = try IconFixture(); defer { f.clean() }
            let png = try iconPNG(), app = try f.app(claim: "Icon." + format)
            try (format == "png" ? png : iconICNS(png)).write(to: app.appendingPathComponent("Contents/Resources/Icon." + format))
            let probe = IconProbe(), r = await f.scanner({ probe.event($0) }).scan()
            let row = try iconRow(r, app); try iconIdentity(row)
            try expect(row.installedIcon?.rgba.count == 16_384, "Real installed icon not normalised to 64x64 RGBA")
            if let pixels = row.installedIcon?.rgba {
                try expect(pixels[0] > 240 && pixels[1] < 10 && pixels[3] == 255, "Decoded icon pixels do not match real fixture")
            }
            try expect(probe.counts.0 == 1 && probe.counts.1 == 1, "Expected exactly one real read/decode notification")
        }
    }
    check("installed icon: genuine two-entry ICNS uses the held reader and eager pixels") {
        let bytes = try iconTwoEntryICNS()
        // Qualify the actual bytes before interpreting any scanner assertion as feature failure.
        try iconQualifyFixture(bytes, label: "two-entry ICNS reader prerequisite", type: "com.apple.icns",
            minimumCount: 2, expectedDimensions: [64, 128])
        let f = try IconFixture(); defer { f.clean() }
        let app = try f.app(claim: "Icon.icns")
        try bytes.write(to: app.appendingPathComponent("Contents/Resources/Icon.icns"))
        let probe = IconProbe(), row = try iconRow(await f.scanner({ probe.event($0) }).scan(), app)
        try iconIdentity(row)
        guard let rgba = row.installedIcon?.rgba, rgba.count == 16_384 else {
            throw CheckFailure(description: "Qualified two-entry ICNS did not produce eager 64x64 pixels")
        }
        try expect(rgba[0] > 240 && rgba[1] < 10 && rgba[2] < 10 && rgba[3] == 255,
            "Qualified two-entry ICNS returned wrong installed pixels")
        try expect(probe.counts.0 == 1 && probe.counts.1 == 1,
            "Two-entry icon did not use one bounded held read and selected thumbnail decode")
    }
    check("installed icon: absence preserves row and generic fallback") {
        let f = try IconFixture(); defer { f.clean() }
        let app = try f.app(claim: nil), r = await f.scanner().scan(), row = try iconRow(r, app)
        try iconIdentity(row)
        try expect(row.installedIcon == nil && r.completeness == .complete, "Absent optional icon invented pixels or broke scan")
    }
    for bytes in [Data(), Data("not an icon".utf8), Data([137,80,78,71,13,10,26,10])] {
        check("installed icon: malformed/truncated \(bytes.count) bytes retain metadata") {
            let f = try IconFixture(); defer { f.clean() }
            let app = try f.app(bytes: bytes), row = try iconRow(await f.scanner().scan(), app)
            try iconIdentity(row); try expect(row.installedIcon == nil, "Malformed image became an icon")
        }
    }
    let unsafeClaims: [Any] = ["../Icon.png", "/Icon.png", "Nested/Icon.png", "file:///Icon.png", "Icon.png\n", "Icon.svg", 7]
    for claim in unsafeClaims {
        check("installed icon: unsafe/unsupported name \(claim) is never read") {
            let f = try IconFixture(); defer { f.clean() }
            let app = try f.app(claim: claim, bytes: iconPNG()), probe = IconProbe()
            let row = try iconRow(await f.scanner({ probe.event($0) }).scan(), app)
            try iconIdentity(row)
            try expect(row.installedIcon == nil && probe.counts.0 == 0 && probe.counts.1 == 0, "Unsafe icon name reached I/O or decoder")
        }
    }
    for kind in ["symlink", "hardlink", "fifo"] {
        check("installed icon: \(kind) leaf refuses without losing metadata") {
            let f = try IconFixture(); defer { f.clean() }
            let app = try f.app(), file = app.appendingPathComponent("Contents/Resources/Icon.png")
            let outside = f.base.appendingPathComponent("Outside.png"); try iconPNG().write(to: outside)
            if kind == "symlink" { try FileManager.default.createSymbolicLink(atPath: file.path, withDestinationPath: outside.path) }
            else if kind == "hardlink" { try expect(link(outside.path, file.path) == 0, "Hardlink fixture failed") }
            else { try expect(mkfifo(file.path, 0o600) == 0, "FIFO fixture failed") }
            let probe = IconProbe(), row = try iconRow(await f.scanner({ probe.event($0) }).scan(), app)
            try iconIdentity(row)
            try expect(row.installedIcon == nil && probe.counts.1 == 0, "Unsafe icon file decoded")
        }
    }
    for boundary in ["resources", "contents", "bundle", "root"] {
        check("installed icon: symlink \(boundary) never supplies installed pixels") {
            let f = try IconFixture(); defer { f.clean() }
            let app = try f.app(bytes: iconPNG())
            let path = boundary == "root" ? f.root : boundary == "bundle" ? app :
                app.appendingPathComponent(boundary == "resources" ? "Contents/Resources" : "Contents")
            let saved = f.base.appendingPathComponent("Saved")
            try FileManager.default.moveItem(at: path, to: saved)
            try FileManager.default.createSymbolicLink(atPath: path.path, withDestinationPath: saved.path)
            let probe = IconProbe(), r = await f.scanner({ probe.event($0) }).scan()
            try expect(r.applications.allSatisfy { $0.installedIcon == nil } && probe.counts.1 == 0,
                "Symlink ancestor supplied decoded pixels")
            try expect(r.issues.contains { $0.kind == .unsafePath }, "Unsafe ancestry was silent")
        }
    }
    check("installed icon: byte ceiling refuses before read or decode") {
        let f = try IconFixture(); defer { f.clean() }
        let app = try f.app(bytes: Data(repeating: 0, count: 1_048_577)), probe = IconProbe()
        let row = try iconRow(await f.scanner({ probe.event($0) }).scan(), app)
        try iconIdentity(row)
        try expect(row.installedIcon == nil && probe.counts.0 == 0 && probe.counts.1 == 0, "Oversize source entered read/decode")
    }
    check("installed icon: source dimension ceiling refuses before pixel decode") {
        let f = try IconFixture(); defer { f.clean() }
        let app = try f.app(bytes: iconPNG(width: 1025, height: 1)), probe = IconProbe()
        let row = try iconRow(await f.scanner({ probe.event($0) }).scan(), app)
        try iconIdentity(row)
        try expect(row.installedIcon == nil && probe.counts.1 == 0, "Oversize dimensions entered pixel decode")
    }
    for boundary in ["file", "resources", "contents", "bundle", "root"] {
        check("installed icon: actual \(boundary) replacement during captured read refuses old pixels") {
            let f = try IconFixture(); defer { f.clean() }
            let app = try f.app(bytes: iconPNG())
            let target = boundary == "root" ? f.root : boundary == "bundle" ? app : app.appendingPathComponent(
                boundary == "file" ? "Contents/Resources/Icon.png" : boundary == "resources" ? "Contents/Resources" : "Contents")
            let scanner = f.scanner { event in
                guard case .beforeIconRead = event else { return }
                try? FileManager.default.moveItem(at: target, to: f.base.appendingPathComponent("Moved"))
                // A real namespace mutation, not an injected scanner result.
            }
            let r = await scanner.scan()
            try expect(!r.applications.isEmpty, "Changed copy disappeared without safe row")
            try expect(r.applications.allSatisfy { $0.installedIcon == nil }, "Old icon survived changed ancestor/file")
            try expect(r.issues.contains { $0.kind == .changedDuringScan || $0.kind == .unreadable }, "Changed namespace was silent")
        }
    }
    check("installed icon: same-name same-ID copies retain distinct pixel values") {
        let f = try IconFixture(); defer { f.clean() }
        let a = try f.app("A.app", bytes: iconPNG(255)), b = try f.app("B.app", bytes: iconPNG(0))
        let r = await f.scanner().scan(), ar = try iconRow(r, a), br = try iconRow(r, b)
        try expect(ar.physicalIdentity != br.physicalIdentity && ar.installedIcon != nil && br.installedIcon != nil &&
            ar.installedIcon != br.installedIcon, "Same claims mixed two physical copies")
    }
    check("installed icon: new generation discards absent icon and another session shares no cache") {
        let f = try IconFixture(); defer { f.clean() }
        let app = try f.app(bytes: iconPNG()), scanner = f.scanner(), first = await scanner.scan()
        try expect(try iconRow(first, app).installedIcon != nil, "First generation positive fixture missing")
        try FileManager.default.removeItem(at: app.appendingPathComponent("Contents/Resources/Icon.png"))
        let second = await scanner.scan(), other = await f.scanner().scan()
        try expect(second.sessionID == first.sessionID && second.generation == first.generation + 1 &&
            other.sessionID != first.sessionID, "Scanner session/generation fixture invalid")
        try expect(try iconRow(second, app).installedIcon == nil, "Stale generation reused old icon")
        try expect(try iconRow(other, app).installedIcon == nil, "Cross-session icon cache reused")
    }
    check("installed icon: late real read cannot deliver pixels from a replaced copy") {
        let f = try IconFixture(); defer { f.clean() }
        let app = try f.app(bytes: iconPNG()), hold = IconReadHold()
        let c = LocalApplicationsController(inventory: f.scanner { hold.event($0) })
        c.scan()
        let deadline = Date().addingTimeInterval(3)
        while !hold.state.0 && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        guard hold.state.0 else { hold.open(); await c.waitUntilIdle(); throw CheckFailure(description: "No real icon read to hold") }
        try FileManager.default.moveItem(at: app, to: f.base.appendingPathComponent("Old.app"))
        _ = try f.app(bytes: iconPNG(0))
        c.scan() // Must remain the same single-flight scan, not create a new generation.
        _ = c.updatesText; _ = c.text
        hold.open(); await c.waitUntilIdle()
        try expect(!hold.state.1 && c.observation?.generation == 1 &&
            c.observation?.applications.allSatisfy { $0.installedIcon == nil } == true,
            "Late old-copy completion populated replacement or bypassed single-flight")
        c.scan(); await c.waitUntilIdle()
        try expect(c.observation?.generation == 2 && c.text.rows.first?.installedIcon?.rgba.first == 0,
            "Fresh generation failed to observe only replacement pixels")
    }
    check("installed icon: retained snapshot cache has hard count and byte limits") {
        let f = try IconFixture(); defer { f.clean() }
        for n in 0..<65 { _ = try f.app(String(format: "A%03d.app", n), bytes: iconPNG()) }
        let probe = IconProbe(), r = await f.scanner({ probe.event($0) }).scan()
        let icons = r.applications.compactMap(\.installedIcon)
        try expect(r.applications.count == 65 && icons.count == 64, "Retained-icon limit erased rows or failed at literal 64")
        try expect(icons.reduce(0) { $0 + $1.rgba.count } == 1_048_576 && probe.counts.1 == 64, "Pixel cache/decode work exceeded literal cap")
    }
    check("installed icon: aggregate encoded read work is reserved before read") {
        let f = try IconFixture(); defer { f.clean() }
        var bytes = try iconPNG(); bytes.append(Data(repeating: 0, count: 1_048_576 - bytes.count))
        for n in 0..<9 { _ = try f.app(String(format: "A%02d.app", n), bytes: bytes) }
        let probe = IconProbe(), r = await f.scanner({ probe.event($0) }).scan()
        try expect(r.applications.count == 9 && probe.counts.0 == 8, "Aggregate encoded reads did not stop at 8MiB")
        try expect(r.applications.compactMap(\.installedIcon).count == 8, "Bounded positive input or aggregate fallback missing")
    }
    check("installed icon: shared row renders supplied snapshot without further I/O or authority") {
        let f = try IconFixture(); defer { f.clean() }
        _ = try f.app(bytes: iconPNG()); let probe = IconProbe()
        let c = LocalApplicationsController(inventory: f.scanner { probe.event($0) })
        try expect(c.observation == nil && probe.counts.0 == 0, "Construction observed icons")
        c.scan(); c.scan(); await c.waitUntilIdle()
        try expect(c.observation?.generation == 1 && c.text.rows.first?.installedIcon != nil, "Explicit single-flight owner did not supply row icon")
        let before = probe.counts
        for _ in 0..<3 {
            _ = c.text; _ = c.updatesText
            for presentation in [LocalApplicationsPresentation.applications, .updates] {
                let renderer = ImageRenderer(content: LocalApplicationsView(controller: c, presentation: presentation).frame(width: 800, height: 600))
                try expect(renderer.cgImage != nil, "Shared row did not paint offscreen")
            }
        }
        try expect(probe.counts.0 == before.0 && probe.counts.1 == before.1, "Row rendering reopened icon or decoded again")
        try expect(c.readyForUpdateCount == 0 && c.unknownUpdateCount == 1, "Icon promoted update readiness")
        try expect(c.text.rows[0].provenance.lines.contains("Verification: not checked"), "Icon changed trust presentation")
    }
    check("installed icon: view contains eager pixel presentation and honest system fallback only") {
        let view = code(try source("Sources/PatchedClient/LocalApplicationsView.swift"))
        try expect(view.contains("installedIcon") && view.contains("Image(systemName: \"app\")") && view.contains("accessibilityHidden(true)"), "Shared installed icon/fallback/accessibility wiring missing")
        for file in ["LocalApplicationsView.swift", "LocalApplicationsController.swift", "NativeClientSession.swift"] {
            let text = code(try source("Sources/PatchedClient/" + file))
            for forbidden in ["NSWorkspace", "NSImage(contentsOf", "CGImageSource", "Data(contentsOf", "URLSession"] {
                try expect(!text.contains(forbidden), "Presentation/owner performs lazy arbitrary icon work: \(forbidden)")
            }
        }
    }
    // V3 ADDITIVE PAINT CASE BEGIN
    check("installed icon: actual shared Applications and Updates paint red installed pixels then generic fallback") {
        let f = try IconFixture(); defer { f.clean() }
        let app = try f.app(bytes: iconPNG())
        let c = LocalApplicationsController(inventory: f.scanner())
        c.scan(); await c.waitUntilIdle()
        guard let first = c.observation else { throw CheckFailure(description: "Paint fixture scan did not finish") }
        try expect(try iconRow(first, app).installedIcon != nil && c.text.rows.first?.installedIcon != nil,
            "Paint acceptance requires actual held-reader installed pixels")
        let presentations: [LocalApplicationsPresentation] = [.applications, .updates]
        var installedCounts: [Int] = []
        for presentation in presentations {
            installedCounts.append(try installedIconStrongRedPixels(c, presentation))
        }
        // Remove only this exact owned inert file. Preserve the physical app and its plist.
        try FileManager.default.removeItem(at: app.appendingPathComponent("Contents/Resources/Icon.png"))
        c.scan(); await c.waitUntilIdle()
        guard let second = c.observation else { throw CheckFailure(description: "Fallback rescan did not finish") }
        let fallbackRow = try iconRow(second, app)
        try iconIdentity(fallbackRow)
        try expect(second.sessionID == first.sessionID && second.generation == first.generation + 1 &&
            fallbackRow.installedIcon == nil && c.text.rows.first?.installedIcon == nil,
            "Explicit replacement generation did not clear removed installed icon")
        for (index, presentation) in presentations.enumerated() {
            let fallbackCount = try installedIconStrongRedPixels(c, presentation)
            try expect(installedCounts[index] >= fallbackCount + 64,
                "Shared \(presentation.rawValue) row did not paint at least64 additional red installed-icon pixels before fallback")
        }
    }
    // V3 ADDITIVE PAINT CASE END
}

// V3 ADDITIVE PAINT HELPER BEGIN
// CHECK-MODIFIED prerequisite correction: the qualified hidden native capture
// includes actual ScrollView rows that ImageRenderer omitted on this host.
@MainActor private enum InstalledIconCaptureBudget {
    static var elapsed: TimeInterval = 0
    static var qualified = false
}
private func installedIconCaptureRefuse(_ reason: String) -> Never {
    print("ICON-CAPTURE-PREREQUISITE-REFUSAL126: " + reason)
    fflush(stdout)
    Darwin.exit(126)
}
private func installedIconCaptureRequire(_ condition: Bool, _ reason: String) {
    if !condition { installedIconCaptureRefuse(reason) }
}
@MainActor private func installedIconStrongRedPixels(_ controller: LocalApplicationsController,
                                                    _ presentation: LocalApplicationsPresentation) throws -> Int {
    installedIconCaptureRequire(InstalledIconCaptureBudget.qualified, "known red/blank controls must pass before actual-view interpretation")
    return try installedIconNativeRedPixels(LocalApplicationsView(controller: controller, presentation: presentation))
}
@MainActor private func installedIconNativeRedPixels<V: View>(_ view: V) throws -> Int {
    let application = NSApplication.shared
    if application.activationPolicy() != .prohibited { _ = application.setActivationPolicy(.prohibited) }
    installedIconCaptureRequire(application.activationPolicy() == .prohibited && !application.isActive,
        "native capture must remain prohibited/inactive")
    let host = NSHostingView(rootView: view.frame(width: 800, height: 600)
        .background(Color.white).environment(\.colorScheme, .light))
    host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
    host.appearance = NSAppearance(named: .aqua)
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.close() }
    let captureStarted = ProcessInfo.processInfo.systemUptime
    host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    let deadline = Date().addingTimeInterval(0.20)
    for _ in 0..<20 {
        if Date() >= deadline { break }
        _ = RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.01)))
    }
    host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        installedIconCaptureRefuse("native bitmap unavailable")
    }
    installedIconCaptureRequire(bitmap.pixelsWide > 0 && bitmap.pixelsWide <= 1600 &&
        bitmap.pixelsHigh > 0 && bitmap.pixelsHigh <= 1200, "native bitmap edge ceiling before capture/destination allocation")
    host.cacheDisplay(in: host.bounds, to: bitmap)
    installedIconCaptureRequire(!window.isVisible && !application.isActive && application.activationPolicy() == .prohibited,
        "native capture became visible or active")
    guard let image = bitmap.cgImage else {
        installedIconCaptureRefuse("native bitmap CGImage unavailable")
    }
    installedIconCaptureRequire(image.width > 0 && image.width <= 1600 && image.height > 0 && image.height <= 1200,
        "capture edge exceeds1600x1200 before destination allocation")
    // Bounds are validated before the fixed1920000-byte destination allocation.
    var pixels = [UInt8](repeating: 0, count: 1_920_000)
    let rendered = pixels.withUnsafeMutableBytes { memory -> Bool in
        guard let context = CGContext(data: memory.baseAddress, width: 800, height: 600,
            bitsPerComponent: 8, bytesPerRow: 3200, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 800, height: 600))
        return true
    }
    installedIconCaptureRequire(rendered, "normalised native RGBA capture unavailable")
    var count = 0
    for index in stride(from: 0, to: 1_920_000, by: 4) {
        if pixels[index] >= 220 && pixels[index + 1] <= 60 && pixels[index + 2] <= 60 && pixels[index + 3] >= 200 {
            count += 1
        }
    }
    let interval = ProcessInfo.processInfo.systemUptime - captureStarted
    installedIconCaptureRequire(interval >= 0, "negative monotonic capture interval")
    InstalledIconCaptureBudget.elapsed += interval
    installedIconCaptureRequire(InstalledIconCaptureBudget.elapsed <= 2, "cumulative native capture/layout budget exceeded2s")
    return count
}
// V3 ADDITIVE PAINT HELPER END
