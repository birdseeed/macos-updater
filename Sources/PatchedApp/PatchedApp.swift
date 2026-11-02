import SwiftUI
import AppKit
import PatchedClient
import ArtifactInspection

@main
enum PatchedEntry {
    @MainActor static func main() {
        if let status = InstalledIdentityWorker.dispatchChild(arguments: CommandLine.arguments) {
            exit(status)
        }
        PatchedApp.main()
    }
}

private typealias MenuInsertionState<Value> = SwiftUI.State<Value>

// Both scenes retain one session. Only explicit Scan and Check actions start
// read-only work; keeping the menu available does not schedule background work.
struct PatchedApp: App {
    @NSApplicationDelegateAdaptor(PatchedApplicationDelegate.self) private var appDelegate
    @StateObject private var session = PatchedApp.makeSession()
    @StateObject private var mainWindow = PatchedMainWindow()
    @MenuInsertionState private var menuInserted = true

    @MainActor private static func makeSession() -> NativeClientSession {
        #if DEBUG
        if let raw = NativeDevelopmentProbeLaunch.rawEndpoint(arguments: CommandLine.arguments) {
            return NativeClientSession.controlledDevelopment(rawProbeEndpoint: raw)
        }
        #endif
        return NativeClientSession()
    }

    var body: some Scene {
        WindowGroup("Patched", id: NativeClientMenuWindow.id) {
            NativeClientRootView(session: session)
                .background(PatchedMainWindowMarker(owner: mainWindow, reopen: appDelegate.reopen))
        }
        MenuBarExtra(isInserted: $menuInserted, content: {
            PatchedMenuContent(session: session, mainWindow: mainWindow)
        }, label: {
            NativeClientMenuLabel()
        })
        .menuBarExtraStyle(.window)
    }
}

private struct PatchedMenuContent: View {
    @ObservedObject var session: NativeClientSession
    let mainWindow: PatchedMainWindow
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NativeClientMenuView(session: session, openWindow: {
            mainWindow.reopen {
                openWindow(id: NativeClientMenuWindow.id)
            }
            NSApp.activate(ignoringOtherApps: true)
        })
    }
}

/// Records only the window containing this app's root view. No window lookup or
/// window ownership is added to the shared client session.
@MainActor private final class PatchedMainWindow: ObservableObject {
    private weak var window: NSWindow?
    private var opening = false

    func attached(to window: NSWindow) {
        self.window = window
        opening = false
    }

    // Called only by explicit menu or Dock reopen gestures. Coalesce same-turn scene requests;
    // a later explicit gesture can retry if no window attaches.
    func reopen(createWindow: () -> Void) {
        if let window {
            window.makeKeyAndOrderFront(nil)
        } else if !opening {
            opening = true
            createWindow()
            DispatchQueue.main.async { [weak self] in self?.opening = false }
        }
    }
}

private struct PatchedMainWindowMarker: NSViewRepresentable {
    let owner: PatchedMainWindow
    let reopen: NativeClientReopenCoordinator
    @Environment(\.openWindow) private var openWindow

    func makeNSView(context: Context) -> PatchedMainWindowMarkerView {
        registerOpener()
        return PatchedMainWindowMarkerView(owner: owner)
    }

    func updateNSView(_ nsView: PatchedMainWindowMarkerView, context: Context) {
        registerOpener()
    }

    private func registerOpener() {
        // Capture only the stable adapter and the scene action, never this view
        // or the coordinator retaining the closure. It survives root-view removal.
        let owner = owner, openWindow = openWindow
        reopen.register(opener: {
            owner.reopen { openWindow(id: NativeClientMenuWindow.id) }
            NSApp.activate(ignoringOtherApps: true)
        })
    }
}

private final class PatchedMainWindowMarkerView: NSView {
    private let owner: PatchedMainWindow

    init(owner: PatchedMainWindow) {
        self.owner = owner
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { owner.attached(to: window) }
    }
}

@MainActor private final class PatchedApplicationDelegate: NSObject, NSApplicationDelegate {
    let reopen = NativeClientReopenCoordinator()

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        reopen.handleReopen(hasVisibleWindows: hasVisibleWindows)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !NativeClientLifecyclePolicy.continuesSessionAfterLastWindowCloses
    }
}
