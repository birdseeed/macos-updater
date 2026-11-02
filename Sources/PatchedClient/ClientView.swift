import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Select the property-wrapper type explicitly when an SDK also declares a State macro.
private typealias ClientPresentationState<Value> = State<Value>

/// Lays out the controller's words with system text styles. It holds no check logic: every
/// action is the controller's, on an explicit click, and nothing happens when it appears.
public struct ClientView: View {
    @ObservedObject private var controller: ClientController
    @StateObject private var applicationsController: LocalApplicationsController
    @ClientPresentationState private var applicationsPresentation: LocalApplicationsPresentation?

    public init(controller: ClientController) {
        self.controller = controller
        _applicationsController = StateObject(wrappedValue: LocalApplicationsController())
    }

    /// Reuses the caller's existing read-only observations across shell and inspector views.
    public init(controller: ClientController, applicationsController: LocalApplicationsController) {
        self.controller = controller
        _applicationsController = StateObject(wrappedValue: applicationsController)
    }

    public var body: some View {
        let text = controller.text
        VStack(alignment: .leading, spacing: 12) {
            wrapped(text.notice).font(.footnote).foregroundStyle(.secondary)
            wrapped(text.heading).font(.title2)
            HStack(spacing: 8) {
                Button(action: { applicationsPresentation = .applications }) { wrapped("Applications").font(.body) }
                    .buttonStyle(ClientButtonStyle(enabled: true, prominent: false))
                Button(action: { applicationsPresentation = .updates }) { wrapped("Updates").font(.body) }
                    .buttonStyle(ClientButtonStyle(enabled: true, prominent: false))
            }
            wrapped(text.fileLine).font(.body)
            Button(action: chooseFile) { wrapped(text.chooseTitle).font(.body) }
                .buttonStyle(ClientButtonStyle(enabled: true, prominent: false))
            wrapped(text.versionLine).font(.body)
            HStack(spacing: 8) {
                ForEach(controller.versions, id: \.self) { version in
                    Button(action: { controller.selectVersion(version) }) { wrapped("Firefox " + version).font(.body) }
                        .buttonStyle(ClientButtonStyle(enabled: true, prominent: controller.selectedVersion == version))
                }
            }
            Divider()
            wrapped(text.statusLine).font(.body.weight(.semibold))
            ForEach(text.resultLines, id: \.title) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        wrapped(row.title).font(.body)
                        Spacer(minLength: 0)
                        wrapped(row.status).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    }
                    if !row.detail.isEmpty { wrapped(row.detail).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            if let reason = text.reason { wrapped(reason).font(.body) }
            if let provenance = text.provenanceLine { wrapped(provenance).font(.footnote).foregroundStyle(.secondary) }
            Divider()
            HStack(spacing: 8) {
                Button(action: { controller.check() }) { wrapped(text.checkTitle).font(.body.weight(.semibold)) }
                    .buttonStyle(ClientButtonStyle(enabled: text.checkEnabled, prominent: true))
                    .disabled(!text.checkEnabled)
                Button(action: { controller.cancel() }) { wrapped(text.cancelTitle).font(.body) }
                    .buttonStyle(ClientButtonStyle(enabled: text.cancelEnabled, prominent: false))
                    .disabled(!text.cancelEnabled)
            }
            wrapped(text.footnote).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 420, alignment: .leading)
        .sheet(item: $applicationsPresentation) { presentation in
            VStack(spacing: 0) {
                LocalApplicationsView(controller: applicationsController, presentation: presentation)
                HStack {
                    Spacer()
                    Button(action: { applicationsPresentation = nil }) { Text(verbatim: "Done") }
                        .buttonStyle(ClientButtonStyle(enabled: true, prominent: false))
                        .keyboardShortcut(.cancelAction)
                }
                .padding([.horizontal, .bottom], 20)
            }
            .frame(width: 620, height: 460)
        }
    }

    /// The native chooser: one disk image file, no folders. Choosing only records the selection.
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.diskImage]
        guard panel.runModal() == .OK, let url = panel.url else {
            // Cancelling the chooser clears a stale result and drops any in-flight delivery; the selection stays.
            controller.cancel()
            return
        }
        controller.select(fileURL: url)
    }

    /// Text that wraps onto further lines instead of being clipped or truncated.
    private func wrapped(_ words: String) -> some View {
        Text(words).fixedSize(horizontal: false, vertical: true)
    }
}

/// Painted entirely by SwiftUI, so the control also appears in an offscreen rendering.
/// Prominent is a filled accent shape, plain is an outline, disabled is a grey outline.
struct ClientButtonStyle: ButtonStyle {
    let enabled: Bool
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let filled = enabled && prominent
        return configuration.label
            .foregroundStyle(filled ? Color.white : (enabled ? Color.primary : Color.secondary))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(shape.fill(filled ? Color.accentColor : Color.secondary.opacity(enabled ? 0.08 : 0.15)))
            .overlay(shape.strokeBorder(Color.secondary.opacity(filled ? 0 : 0.5), lineWidth: 1))
            .opacity(enabled && configuration.isPressed ? 0.6 : 1)
            .contentShape(shape)
    }
}
