import Foundation
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
@_spi(Testing) import PatchedActivity

private struct Rendered { let image: CGImage; let png: Data }
@MainActor private func render<V: View>(_ view: V, width: Int = 720, height: Int = 480, dark: Bool = false) throws -> Rendered {
    let app = NSApplication.shared
    if app.activationPolicy() != .prohibited { _ = app.setActivationPolicy(.prohibited) }
    guard app.activationPolicy() == .prohibited, !app.isActive else { throw Failure(description: "Inactive prohibited fixture process unavailable") }
    let content = view.frame(width: CGFloat(width), height: CGFloat(height))
        .background(dark ? Color.black : Color.white).environment(\.colorScheme, dark ? .dark : .light)
    let host = NSHostingView(rootView: content)
    host.frame = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua); host.wantsLayer = true
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = host.appearance; window.contentView = host
    defer { window.close() }
    func assertUnshown() throws {
        guard app.activationPolicy() == .prohibited, !app.isActive, !window.isVisible else { throw Failure(description: "Owned native fixture became active/visible") }
    }
    try assertUnshown(); host.needsLayout = true; host.layoutSubtreeIfNeeded()
    host.needsDisplay = true; host.displayIfNeeded(); window.displayIfNeeded(); try assertUnshown()
    let deadline = Date().addingTimeInterval(0.20)
    while Date() < deadline { _ = RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.01))) }
    try assertUnshown(); host.layoutSubtreeIfNeeded(); host.displayIfNeeded(); window.displayIfNeeded(); try assertUnshown()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw Failure(description: "Native bitmap allocation failed") }
    host.cacheDisplay(in: host.bounds, to: bitmap); try assertUnshown()
    guard let captured = bitmap.cgImage else { throw Failure(description: "Actual native bitmap absent") }
    let image: CGImage
    if captured.width == width && captured.height == height { image = captured }
    else {
        guard captured.width % width == 0, captured.height % height == 0,
              captured.width / width == captured.height / height, (2...4).contains(captured.width / width),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw Failure(description: "Actual native backing scale outside bounds")
        }
        context.interpolationQuality = .high
        context.draw(captured, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        guard let normalized = context.makeImage() else { throw Failure(description: "Native normalization failed") }
        image = normalized
    }
    try assertUnshown()
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw Failure(description: "PNG unavailable") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw Failure(description: "PNG encoding failed") }
    return Rendered(image: image, png: data as Data)
}
private func pixels(_ image: CGImage) throws -> Int {
    var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let drew = data.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))); return true
    }
    guard drew else { throw Failure(description: "Native pixels unreadable") }
    return stride(from: 0, to: data.count, by: 4).reduce(0) { result, index in
        result + (data[index] > 240 && data[index + 1] < 15 && data[index + 2] > 240 ? 1 : 0)
    }
}
@MainActor func registerOffscreenChecks() {
    check("setup: actual invisible bitmap paints independent 40x40 probe", setup: true) {
        let result = try render(Rectangle().fill(Color(red: 1, green: 0, blue: 1)).frame(width: 40, height: 40))
        let count = try pixels(result.image)
        try expect(result.image.width == 720 && result.image.height == 480 && count >= 1500,
                   "Actual native capture/probe setup failed")
    }
    check("setup: actual invisible 40x40 probe observes GeometryReader onAppear bounds", setup: true) {
        var observed: [CGRect] = []
        let probe = Rectangle().fill(Color(red: 1, green: 0, blue: 1)).frame(width: 40, height: 40)
            .background(GeometryReader { geometry in
                Color.clear.onAppear { observed.append(geometry.frame(in: .global)) }
            })
        let result = try render(probe)
        let count = try pixels(result.image)
        try expect(!observed.isEmpty, "Standalone native geometry onAppear never observed")
        try expect(observed.allSatisfy {
            (39...40).contains($0.width) && (39...40).contains($0.height) &&
            $0.minX >= 0 && $0.maxX <= 720 && $0.minY >= 0 && $0.maxY <= 480
        }, "Standalone native geometry dimensions or bounds incorrect")
        try expect(count >= 1500, "Standalone geometry probe missing actual magenta pixels")
    }
    let specimens: [(String, ActivitySnapshot, String)] = [
        ("unavailable", ActivitySnapshot(available: false), "Activity unavailable"),
        ("empty", ActivitySnapshot(available: true, revision: 1, ageAvailable: true), "No activity"),
        ("unknown", ActivitySnapshot(available: true, revision: 1, events: [event(observed: nil, resolved: nil)]), "Activity"),
        ("mixed", ActivitySnapshot(available: true, revision: 1, events: [event(), event(id: otherID, attempt: otherID, status: .deferred, sequence: 2)], ageAvailable: true), "Activity"),
        ("literal-long", ActivitySnapshot(available: true, revision: 1, events: [event(name: String(repeating: "<b>日本語</b> & ", count: 10))], ageAvailable: true), "Activity")
    ]
    for (name, snapshot, headline) in specimens {
        for dark in [false, true] {
            check("native offscreen actual Activity specimen: \(name)/\(dark)") {
                let store = try OwnedStore()
                let p = ActivityPresentation.make(snapshot)
                try expect(p.headline == headline && p.provenance == "Synthetic fixture only", "Specimen state/provenance missing")
                try expect(p.rows.count == snapshot.events.count, "Presentation omitted rows")
                var probed: [String: String] = [:]; var bounds: [CGRect] = []
                let view = ActivityView(presentation: p, rowProbe: { row in
                    probed[row.eventID] = row.text
                    return AnyView(Rectangle().fill(Color(red: 1, green: 0, blue: 1)).frame(width: 40, height: 40)
                        .background(GeometryReader { geometry in
                            Color.clear.onAppear { bounds.append(geometry.frame(in: .global)) }
                        }))
                })
                let result = try render(view, dark: dark)
                try result.png.write(to: store.directory.appendingPathComponent("activity-\(name)-\(dark).png"), options: .withoutOverwriting)
                try expect(result.image.width == 720 && result.image.height == 480 && !result.png.isEmpty, "Native bounds incorrect")
                try expect(probed == Dictionary(uniqueKeysWithValues: p.rows.map { ($0.eventID, $0.text) }), "Actual view did not request exact row content")
                if !p.rows.isEmpty {
                    try expect(try pixels(result.image) >= p.rows.count * 900, "Actual row probes missing/clipped")
                    try expect(bounds.count >= p.rows.count && bounds.allSatisfy { $0.width >= 39 && $0.height >= 39 && $0.minX >= 0 && $0.maxX <= 720 && $0.minY >= 0 && $0.maxY <= 480 }, "Actual row geometry clipped")
                }
                print("Retained Activity specimen: \(store.directory.path)")
            }
        }
    }
    check("native offscreen: source text changes actual bitmap with same probe") {
        let a = ActivityPresentation(headline: "Activity", provenance: "Synthetic fixture only", retainedRange: "10000000 to 10000000",
            policy: "30 days • 2000 events • 2 MiB", rows: [ActivityRow(eventID: eventID, attemptID: attemptID, text: "Failed fixture alpha")])
        let b = ActivityPresentation(headline: "Activity", provenance: "Synthetic fixture only", retainedRange: "10000000 to 10000000",
            policy: "30 days • 2000 events • 2 MiB", rows: [ActivityRow(eventID: eventID, attemptID: attemptID, text: "Deferred fixture beta")])
        let first = try render(ActivityView(presentation: a))
        let second = try render(ActivityView(presentation: b))
        try expect(first.png != second.png, "Source view discarded row text")
    }
    check("native offscreen: empty and unavailable source states paint differently") {
        let unavailable = ActivityPresentation.make(ActivitySnapshot(available: false))
        let empty = ActivityPresentation.make(ActivitySnapshot(available: true, revision: 0, ageAvailable: true))
        try expect(try render(ActivityView(presentation: unavailable)).png != render(ActivityView(presentation: empty)).png,
                   "Source view concealed unavailable versus empty")
    }
}
