import SwiftUI

/// Lays out the operator controller's visible words with system text styles. It holds no
/// step logic: each button passes one explicit click to the controller and nothing runs
/// when the view appears.
public struct OperatorView: View {
    @ObservedObject private var controller: OperatorController

    public init(controller: OperatorController) { self.controller = controller }

    public var body: some View {
        let text = controller.text
        VStack(alignment: .leading, spacing: 12) {
            wrapped(text.scopeNotice).font(.footnote).foregroundStyle(.secondary)
            wrapped(text.heading).font(.title2)
            wrapped(text.artifactLine).font(.body)
            ForEach(text.rows, id: \.stage) { row in card(row) }
            wrapped(text.footnote).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 420, alignment: .leading)
    }

    /// One numbered step: its title, what is held for it, why it is refused or unavailable, and its button.
    private func card(_ row: OperatorStageRow) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                wrapped(row.title).font(.headline)
                wrapped(row.status).font(.body).foregroundStyle(row.status == OperatorViewText.notRun ? .secondary : .primary)
                if let reason = row.reason { wrapped(reason).font(.footnote).foregroundStyle(row.actionEnabled ? .primary : .secondary) }
            }
            Spacer(minLength: 0)
            Button(action: { controller.choose(row.stage) }) {
                Text(row.actionTitle).font(.body.weight(.semibold)).fixedSize().frame(minWidth: 64)
            }
            .buttonStyle(OperatorButtonStyle(enabled: row.actionEnabled))
            .disabled(!row.actionEnabled)
        }
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

/// Painted entirely by SwiftUI, so the control also appears in an offscreen rendering.
/// Enabled is a filled accent shape, pressed is the same shape dimmed, disabled is a grey outline.
struct OperatorButtonStyle: ButtonStyle {
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
