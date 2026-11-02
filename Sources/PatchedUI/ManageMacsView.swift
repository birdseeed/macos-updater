import SwiftUI
import PatchedActivation
public struct ManageMacsView: View {
    let presentation: ManageMacsPresentation
    let onIntent: (MacDisplayIntent) -> Void
    public init(presentation: ManageMacsPresentation = .make(), onIntent: @escaping (MacDisplayIntent) -> Void = { _ in }) {
        self.presentation = presentation; self.onIntent = onIntent
    }
    public var body: some View {
        let text = ManageMacsText(presentation)
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: text.heading).font(.title2).accessibilityAddTraits(.isHeader)
            Text(verbatim: text.capacity).font(.headline)
            Text(verbatim: text.notice).font(.callout)
            // A finite history also paints directly in the offscreen renderer.
            VStack(alignment: .leading, spacing: 12) {
                    ForEach(presentation.rows.indices, id: \.self) { index in
                        let row = presentation.rows[index]
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: row.label).font(.headline).lineLimit(3)
                            // Keep the entire safe target visible even if the name truncates.
                            Text(verbatim: row.opaqueID).font(.system(.caption, design: .monospaced))
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text(verbatim: (row.isThisMac ? "This Mac · " : "") +
                                 (row.status == .active ? "Active" : "Released")).font(.callout)
                            ForEach(row.intents.indices, id: \.self) { actionIndex in
                                Button(action: { onIntent(row.intents[actionIndex]) }) {
                                    Text(verbatim: text.actionLabels[index][actionIndex]).lineLimit(3)
                                }.buttonStyle(.plain)
                                    .accessibilityLabel(Text(verbatim: text.actionLabels[index][actionIndex] + " · " + row.opaqueID))
                            }
                        }.accessibilityElement(children: .contain)
                        Divider()
                    }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(20).frame(width: 480, alignment: .leading)
    }
}
