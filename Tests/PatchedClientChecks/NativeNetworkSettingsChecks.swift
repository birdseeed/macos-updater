import SwiftUI
import AppKit
import PatchedShell
@_spi(Testing) import PatchedClient
@_spi(Testing) import PatchedNetworking

@MainActor private final class ViewRequest: NativeNetworkObservationRequest {
    var cancellations = 0
    func cancel() { cancellations += 1 }
}
@MainActor private final class ViewProvider: NativeNetworkObservationProvider {
    var calls = 0
    let request = ViewRequest()
    var completion: (@MainActor (NativeNetworkObservation) -> Void)?
    func begin(completion: @escaping @MainActor (NativeNetworkObservation) -> Void) -> any NativeNetworkObservationRequest {
        calls += 1; self.completion = completion; return request
    }
}
@MainActor private func settingsPixels(_ controller: NativeNetworkSettingsController) throws -> Data {
    let renderer = ImageRenderer(content: NativeNetworkSettingsView(controller: controller, probe: NativeNetworkProbeController(settings: controller))
        .frame(width: 640, height: 640, alignment: .topLeading)
        .background(Color.white).environment(\.colorScheme, .light))
    renderer.scale = 1
    guard let image = renderer.cgImage, let data = image.dataProvider?.data as Data? else {
        throw CheckFailure(description: "Network settings offscreen rendering missing")
    }
    try expect(image.width == 640 && image.height == 640 && data.count > 0, "Network settings image bounds wrong")
    return data
}
@MainActor func registerNativeNetworkSettingsChecks() {
    check("PAT2666 native UI: shared app session owner survives navigation and defaults stay idle") {
        let session = NativeClientSession(), owner = session.network
        for destination in ShellDestination.allCases {
            session.navigation.select(destination)
            for section in ShellSettingsSection.allCases { session.navigation.selectSettings(section) }
            try expect(session.network === owner && owner.snapshot == nil && !owner.isRefreshing && owner.choice == nil,
                       "Navigation replaced the shared app session network owner or performed observation")
        }
        let other = NativeClientSession()
        try expect(other.network !== owner, "Separately constructed app sessions share a network draft owner")
    }
    check("PAT2666 native UI: offscreen rendering is inert and actual observation changes the pixels") {
        let provider = ViewProvider(), controller = NativeNetworkSettingsController(provider: ViewProvider())
        let observed = NativeNetworkSettingsController(provider: provider)
        _ = try settingsPixels(observed)
        observed.edit(mode: .manualHTTP, host: "proxy.example", port: "8080")
        // CHECK-MODIFIED PAT-2666: baseline after edit isolates observation-only pixels.
        let before = try settingsPixels(observed)
        try expect(provider.calls == 0 && observed.snapshot == nil && !observed.isRefreshing, "Rendering or edit observed native state")
        observed.refresh()
        try expect(provider.calls == 1, "Explicit UI controller refresh missing")
        guard let completion = provider.completion else { return }
        completion(NativeNetworkObservation(path: .offline, proxy: .pacUnsupported))
        let after = try settingsPixels(observed)
        try expect(before != after, "Actual offline/unsupported observation does not alter visible settings")
        try expect(provider.calls == 1 && provider.request.cancellations == 1, "Render restarted or leaked request")
        try expect(controller.snapshot == nil, "Rendering affected a different app session")
    }
    check("PAT2666 native UI: Network route uses retained real view with explicit controls and truthful text") {
        let root = code(try source("Sources/PatchedClient/NativeClientSession.swift"))
        for required in ["NativeNetworkSettingsController", "network = .native()", "section == .network", "NativeNetworkSettingsView(controller: session.network, probe: session.networkProbe)"] {
            try expect(root.contains(required), "Native Network composition lacks \(required)")
        }
        let view = code(try source("Sources/PatchedClient/NativeNetworkSettingsView.swift"))
        for required in ["Picker", "TextField", "Button", "controller.edit(", "controller.applyChoice()", "controller.refresh()", "controller.text.path", "controller.text.proxy", "controller.text.provenance", "controller.text.freshness", "controller.text.guidance", "controller.isRefreshing"] {
            try expect(view.contains(required), "Network settings view lacks real bound control/display: \(required)")
        }
        for forbidden in [".onAppear", ".task", "Timer", "Task {", "URLSession", "CFNetworkCopy", "NWPathMonitor", "SecItem", "UserDefaults", "Process(", "Font.custom", ".custom(", "SecureField"] {
            try expect(!view.contains(forbidden), "View performs forbidden work or adds credentials: \(forbidden)")
        }
        let native = code(try source("Sources/PatchedNetworking/NativeNetworkSettings.swift"))
        for required in ["NetworkConfiguration(", ".validate()", "CFNetworkCopySystemProxySettings", "NativeNetworkProxySnapshot.classify(", "NWPathMonitor", ".cancel()"] {
            try expect(native.contains(required), "Native adapter missing required actual native boundary: \(required)")
        }
        for forbidden in ["NetworkSyntheticModel", "NetworkPolicy(", "NetworkBoundaries(", "URLSession", "URLRequest", "SecItem", "UserDefaults", "Process(", "FileManager", "getaddrinfo"] {
            try expect(!native.contains(forbidden), "Read-only settings escaped scope: \(forbidden)")
        }
    }
}
