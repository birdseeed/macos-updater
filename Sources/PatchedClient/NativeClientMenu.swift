import SwiftUI
import AppKit
import PatchedShell

public enum NativeClientMenuAction: CaseIterable, Sendable {
    case scan, updates, applications, activity, settings
}

public enum NativeClientMenuWindow {
    public static let id = "patched-main"
}

public enum NativeClientLifecyclePolicy {
    /// Keep the user session's menu available after its last window closes.
    /// This does not schedule work or change explicit Quit behaviour.
    public static let continuesSessionAfterLastWindowCloses = true
}

public struct NativeClientMenuText: Equatable, Sendable {
    public let summary: MenuSummary
    public let inventoryStatus: String
    public let observedAt: String?
    public let provenance: String?
    public let scanTitle: String
    public let scanEnabled: Bool
    public let backgroundStatus: String
}

extension NativeClientSession {
    public var menuText: NativeClientMenuText {
        let inventory = applications.text
        return NativeClientMenuText(summary: MenuSummary(), inventoryStatus: inventory.status,
            observedAt: inventory.observedAt, provenance: inventory.provenance,
            scanTitle: inventory.scanTitle, scanEnabled: inventory.scanEnabled,
            backgroundStatus: "Background checks and notifications unavailable.")
    }

    /// Routes request the main window even when the destination is already selected.
    /// Window handling stays with the caller; Scan never changes navigation.
    @discardableResult public func performMenuAction(_ action: NativeClientMenuAction) -> Bool {
        switch action {
        case .scan:
            applications.scan()
            return false
        case .updates:
            navigation.select(.updates)
        case .applications:
            navigation.select(.applications)
        case .activity:
            navigation.select(.activity)
        case .settings:
            navigation.select(.settings)
        }
        return true
    }
}

/// Uses the same canonical mark as the shell, in the menu bar's native colour.
public struct NativeClientMenuLabel: View {
    public init() {}

    /// Eager, bounded canonical pixels; template tint comes from the menu bar.
    @MainActor public static var image: NSImage? {
        let renderer = ImageRenderer(content: ShellBrandMark()
            .fill(.black).frame(width: 18, height: 18))
        renderer.scale = 2
        guard let pixels = renderer.cgImage else { return nil }
        let representation = NSBitmapImageRep(cgImage: pixels)
        representation.size = NSSize(width: 18, height: 18)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        image.isTemplate = true
        return image
    }

    public var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image)
                    .frame(width: 18, height: 18)
            }
        }
        .accessibilityLabel(Text(verbatim: "Patched"))
    }
}

/// Presentation observes the retained child directly: session observation alone
/// does not forward its applications owner's publications.
public struct NativeClientMenuView: View {
    @ObservedObject private var session: NativeClientSession
    @ObservedObject private var applications: LocalApplicationsController
    private let openWindow: () -> Void

    public init(session: NativeClientSession, openWindow: @escaping () -> Void) {
        self.session = session
        self.applications = session.applications
        self.openWindow = openWindow
    }

    public var body: some View {
        let text = session.menuText
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "Patched").font(.headline)
            Text(verbatim: text.summary.title)
                .font(.headline)
                .accessibilityLabel(Text(verbatim: text.summary.accessibilitySummary))
            Text(verbatim: text.inventoryStatus)
                .fixedSize(horizontal: false, vertical: true)
            if let observedAt = text.observedAt {
                Text(verbatim: observedAt).font(.caption).foregroundStyle(.secondary)
            }
            if let provenance = text.provenance {
                Text(verbatim: provenance).font(.caption).foregroundStyle(.secondary)
            }
            Button(action: { session.performMenuAction(.scan) }) {
                Text(verbatim: text.scanTitle)
            }
            .disabled(!text.scanEnabled)
            Divider()
            Button(action: { route(.updates) }) { Text(verbatim: "Updates") }
            Button(action: { route(.applications) }) { Text(verbatim: "Applications") }
            Button(action: { route(.activity) }) { Text(verbatim: "Activity") }
            Button(action: { route(.settings) }) { Text(verbatim: "Settings") }
            Divider()
            Text(verbatim: text.backgroundStatus)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.body)
        .padding(16)
        .frame(width: 340, alignment: .leading)
    }

    private func route(_ action: NativeClientMenuAction) {
        if session.performMenuAction(action) { openWindow() }
    }
}
