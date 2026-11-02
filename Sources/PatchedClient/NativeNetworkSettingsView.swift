import SwiftUI
import PatchedNetworking

/// Explicit actions on the shared client session; presentation never starts observation work.
public struct NativeNetworkSettingsView: View {
    @ObservedObject private var controller: NativeNetworkSettingsController
    @ObservedObject private var probe: NativeNetworkProbeController
    public init(controller: NativeNetworkSettingsController, probe: NativeNetworkProbeController) {
        precondition(probe.settings === controller, "Network view owners must match")
        self.controller = controller; self.probe = probe
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "Network").font(.title2)
            Picker(selection: Binding(get: { controller.mode }, set: { controller.edit(mode: $0) })) {
                Text(verbatim: "System proxy settings").tag(NetworkMode.system)
                Text(verbatim: "Direct").tag(NetworkMode.direct)
                Text(verbatim: "Manual HTTP proxy").tag(NetworkMode.manualHTTP)
            } label: { Text(verbatim: "Future in-app connection choice") }
            if controller.mode == .manualHTTP {
                TextField(text: Binding(get: { controller.host }, set: {
                    controller.edit(mode: .manualHTTP, host: $0, port: controller.port)
                })) { Text(verbatim: "Proxy host") }
                TextField(text: Binding(get: { controller.port }, set: {
                    controller.edit(mode: .manualHTTP, host: controller.host, port: $0)
                })) { Text(verbatim: "Proxy port") }
            }
            Button(action: { _ = controller.applyChoice() }) { Text(verbatim: "Apply choice for this app session") }
            Text(verbatim: controller.text.status)
            if probe.showsDevelopmentControls {
                Text(verbatim: "Catalogue, update and support transport remain unavailable. This development probe tests only its controlled local route.")
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: "Development controlled local probe").font(.headline)
                HStack {
                    Button(action: { probe.test() }) { Text(verbatim: "Test controlled local route") }
                        .disabled(!probe.canTest)
                    Button(action: { probe.cancel() }) { Text(verbatim: "Cancel controlled local check") }
                        .disabled(!probe.isRunning)
                }
                Text(verbatim: probe.statusText).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(verbatim: controller.text.limitation).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button(action: { controller.refresh() }) { Text(verbatim: "Refresh network information") }
                    .disabled(controller.isRefreshing)
                Button(action: { controller.cancelRefresh() }) { Text(verbatim: "Cancel refresh") }
                    .disabled(!controller.isRefreshing)
            }
            Text(verbatim: controller.text.path)
            Text(verbatim: controller.text.proxy)
            Text(verbatim: controller.text.provenance).font(.footnote)
            Text(verbatim: controller.text.freshness).font(.footnote)
            if let guidance = controller.text.guidance {
                Text(verbatim: guidance).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
