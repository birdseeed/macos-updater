import SwiftUI
import PatchedCore

/// Lays out the visible words of one prepared presentation with system text styles.
/// It holds no update logic: the only action is the caller's, on an explicit click.
public struct UpdateView: View {
    let text: UpdateViewText
    let onUpdate: () -> Void

    public init(presentation: UpdatePresentation, onUpdate: @escaping () -> Void) {
        self.text = UpdateViewText(presentation)
        self.onUpdate = onUpdate
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            wrapped(text.previewNotice).font(.footnote).foregroundStyle(.secondary)
            wrapped(text.heading).font(.title2)
            wrapped(text.installedLine).font(.body)
            wrapped(text.checkedLine).font(.body)
            Divider()
            ForEach(text.checks, id: \.title) { row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    wrapped(row.title).font(.body)
                    Spacer(minLength: 0)
                    wrapped(row.status).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
            }
            if let refusal = text.refusalLine { wrapped(refusal).font(.body) }
            if let deferral = text.deferralLine { wrapped(deferral).font(.body) }
            Divider()
            Button(action: onUpdate) { wrapped(text.actionTitle).font(.body.weight(.semibold)) }
                .buttonStyle(UpdateButtonStyle(enabled: text.actionEnabled))
                .disabled(!text.actionEnabled)
            wrapped(text.actionNote).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 420, alignment: .leading)
    }

    /// Text that wraps onto further lines instead of being clipped or truncated.
    private func wrapped(_ words: String) -> some View {
        Text(words).fixedSize(horizontal: false, vertical: true)
    }
}

/// Painted entirely by SwiftUI, so the control also appears in an offscreen rendering.
/// Enabled is a filled accent shape, pressed is the same shape dimmed, disabled is a grey outline.
struct UpdateButtonStyle: ButtonStyle {
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return configuration.label
            .foregroundStyle(enabled ? Color.white : Color.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(shape.fill(enabled ? Color.accentColor : Color.secondary.opacity(0.15)))
            .overlay(shape.strokeBorder(Color.secondary.opacity(enabled ? 0 : 0.5), lineWidth: 1))
            .opacity(enabled && configuration.isPressed ? 0.6 : 1)
            .contentShape(shape)
    }
}
