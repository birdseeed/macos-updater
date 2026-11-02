import SwiftUI

public struct ActivityView: View {
    private let presentation: ActivityPresentation
    private let onGetHelp: ((ActivityRow) -> Void)?
    private let rowProbe: ((ActivityRow) -> AnyView)?
    public init(presentation: ActivityPresentation) { self.presentation = presentation; rowProbe = nil; onGetHelp = nil }
    public init(presentation: ActivityPresentation, onGetHelp: @escaping (ActivityRow) -> Void) {
        self.presentation = presentation; rowProbe = nil; self.onGetHelp = onGetHelp
    }
    @_spi(Testing) public init(presentation: ActivityPresentation, rowProbe: @escaping (ActivityRow) -> AnyView) {
        self.presentation = presentation; self.rowProbe = rowProbe; onGetHelp = nil
    }
    public var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: presentation.headline).font(.title2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: presentation.provenance).font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: presentation.retainedRange).font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: presentation.policy).font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(presentation.rows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: 12) {
                            // Inert check-owned row-slot content; never an operating intent.
                            if let rowProbe { rowProbe(row) }
                            Text(verbatim: row.text).font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let onGetHelp {
                                Button(action: { onGetHelp(row) }) { Text(verbatim: "Get help") }
                            }
                        }
                    }
                }.padding().frame(width: max(0, viewport.size.width), alignment: .leading)
            }
        }
    }
}
