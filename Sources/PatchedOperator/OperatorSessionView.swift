import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Lays out the operator session's visible words with system text styles. It holds no
/// verification logic: each button passes one explicit click to the session and nothing
/// runs when the view is shown. Signing and publication are words only, with no control.
public struct OperatorSessionView: View {
    @ObservedObject private var session: OperatorSession

    public init(session: OperatorSession) { self.session = session }

    public var body: some View {
        let text = session.text
        VStack(alignment: .leading, spacing: 12) {
            wrapped("Artifact check").font(.title2)
            card {
                wrapped(text.fileLine).font(.body)
                button("Choose Disk Image…", enabled: true, action: chooseDiskImage)
            }
            card {
                wrapped(text.versionLine).font(.body)
                HStack(spacing: 8) {
                    ForEach(session.versions, id: \.self) { version in
                        button(version, enabled: session.selectedVersion != version) { session.selectVersion(version) }
                    }
                }
            }
            card {
                wrapped(text.status).font(.headline)
                if let provenance = text.provenanceLine { wrapped(provenance).font(.body) }
                if let app = text.appLine { wrapped(app).font(.body) }
                ForEach(text.containerLines, id: \.self) { wrapped($0).font(.body) }
                if let cleanup = text.cleanupLine { wrapped(cleanup).font(.body) }
                HStack(spacing: 8) {
                    button("Verify", enabled: text.verifyEnabled) { session.verify() }
                    button("Cancel", enabled: text.cancelEnabled) { session.cancel() }
                }
            }
            card {
                wrapped(text.signingReason).font(.footnote).foregroundStyle(.secondary)
                wrapped(text.publicationReason).font(.footnote).foregroundStyle(.secondary)
            }
            wrapped(text.footnote).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 420, alignment: .leading)
    }

    /// The system chooser for exactly one local disk image file. Choosing passes the file to
    /// the session and runs nothing; dismissing it cancels, so no earlier result stays shown.
    private func chooseDiskImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = false
        panel.allowedContentTypes = [.diskImage]
        if panel.runModal() == .OK, let url = panel.url { session.select(fileURL: url) } else { session.cancel() }
    }

    private func button(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.body.weight(.semibold)).fixedSize().frame(minWidth: 64) }
            .buttonStyle(OperatorButtonStyle(enabled: enabled))
            .disabled(!enabled)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return VStack(alignment: .leading, spacing: 6, content: content)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Color.secondary.opacity(0.06)))
            .overlay(shape.strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1))
    }

    /// Text that wraps onto further lines instead of being clipped or truncated.
    private func wrapped(_ words: String) -> some View {
        Text(words).fixedSize(horizontal: false, vertical: true)
    }
}
