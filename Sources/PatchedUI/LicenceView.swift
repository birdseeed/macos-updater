import SwiftUI
import PatchedLicensing
/// Offscreen-capable display; callbacks return intent only, never authority.
public struct LicenceView: View {
    let presentation: LicencePresentation
    let onIntent: (LicenceIntent) -> Void
    public init(presentation: LicencePresentation = .make(), onIntent: @escaping (LicenceIntent) -> Void = { _ in }) {
        self.presentation = presentation; self.onIntent = onIntent
    }
    public var body: some View {
        let text = LicenceViewText(presentation)
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: text.heading).font(.title2).accessibilityAddTraits(.isHeader)
            Text(verbatim: text.detail).font(.body)
            if !text.account.isEmpty {
                Text(verbatim: text.account).font(.body).lineLimit(3)
            }
            Text(verbatim: text.trialNote).font(.callout)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(presentation.intents.indices, id: \.self) { index in
                    Button(action: { onIntent(presentation.intents[index]) }) {
                        Text(verbatim: text.actionLabels[index])
                    }.buttonStyle(.plain).accessibilityLabel(Text(verbatim: text.actionLabels[index]))
                }
            }
            Divider()
            Text(verbatim: text.discovery).font(.callout)
            Text(verbatim: text.safety).font(.callout)
        }
        .padding(20).frame(width: 480, alignment: .leading)
    }
}
