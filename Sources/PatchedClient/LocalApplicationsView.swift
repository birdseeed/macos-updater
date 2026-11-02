import SwiftUI
import CoreGraphics

// Select the property-wrapper type explicitly when an SDK also declares a State macro.
private typealias LocalApplicationPresentationState<Value> = State<Value>

public enum LocalApplicationsPresentation: String, Identifiable {
    case applications, updates
    public var id: String { rawValue }
}

/// Presents local observations as literal, unverified claims, with one explicit action.
public struct LocalApplicationsView: View {
    @ObservedObject private var controller: LocalApplicationsController
    private let presentation: LocalApplicationsPresentation
    public init(controller: LocalApplicationsController, presentation: LocalApplicationsPresentation = .applications) {
        self.controller = controller
        self.presentation = presentation
    }
    public var body: some View {
        let text = presentation == .updates ? controller.updatesText : controller.text
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                literal(text.heading).font(.title2)
                Spacer(minLength: 8)
                Button(action: { controller.scan() }) { literal(text.scanTitle) }
                    .buttonStyle(ClientButtonStyle(enabled: text.scanEnabled, prominent: true))
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(!text.scanEnabled)
            }
            literal(text.status).font(.body.weight(.semibold))
            literal(text.notice).font(.callout).foregroundStyle(.secondary)
            if presentation == .updates {
                literal("Unknown update availability: \(controller.unknownUpdateCount)").font(.callout)
                literal("Ready for update: \(controller.readyForUpdateCount)").font(.callout)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let provenance = text.provenance {
                        literal(provenance).font(.callout.weight(.semibold))
                    }
                    if let observedAt = text.observedAt {
                        literal(observedAt).font(.footnote).foregroundStyle(.secondary)
                    }
                    if !text.roots.isEmpty {
                        literal("Folder scope").font(.headline)
                        ForEach(Array(text.roots.enumerated()), id: \.offset) { _, root in
                            literal(LocalProvenanceDisplay.explanation(root)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(Array(text.rows.enumerated()), id: \.offset) { _, row in
                        Divider()
                        LocalApplicationProvenanceRow(row: row)
                            .id(row.provenance.disclosureID)
                    }
                    if !text.issues.isEmpty {
                        Divider()
                        literal("Observation explanations").font(.headline)
                        ForEach(Array(text.issues.enumerated()), id: \.offset) { _, issue in
                            literal(LocalProvenanceDisplay.explanation(issue)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func literal(_ value: String) -> some View {
        Text(verbatim: value).fixedSize(horizontal: false, vertical: true)
    }
}

/// Expansion is view state only. The owner's immutable row supplies every value;
/// the revision-bound identity resets expansion when a scan replaces that row.
private struct LocalApplicationProvenanceRow: View {
    let row: LocalApplicationsRowText
    @LocalApplicationPresentationState private var isExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            decorativeIcon.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                literal(LocalProvenanceDisplay.claim(row.name)).font(.headline)
                literal(LocalProvenanceDisplay.claim(row.version)).font(.body)
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 6) {
                        literal(LocalProvenanceDisplay.claim(row.build))
                        literal(LocalProvenanceDisplay.location(row.location))
                        literal(row.metadata)
                        ForEach(Array(row.provenance.lines.enumerated()), id: \.offset) { _, line in
                            literal(line)
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                } label: {
                    literal("Source and verification details")
                        .font(.callout)
                }
                .accessibilityHint(Text(verbatim: "Expand to read observed source claims and checks for this application copy."))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var decorativeIcon: some View {
        if let installedIcon = row.installedIcon, let image = pixelImage(installedIcon) {
            Image(decorative: image, scale: 1).resizable().frame(width: 32, height: 32)
        } else {
            Image(systemName: "app").font(.title2)
        }
    }

    // Only eager, fixed-size snapshot pixels enter CoreGraphics here. No file,
    // encoded image, decoder or deferred provider callback reaches presentation.
    private func pixelImage(_ icon: LocalInstalledIcon) -> CGImage? {
        guard icon.rgba.count == 16_384, let provider = CGDataProvider(data: icon.rgba as CFData) else { return nil }
        return CGImage(width: 64, height: 64, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private func literal(_ value: String) -> some View {
        Text(verbatim: value).fixedSize(horizontal: false, vertical: true)
    }
}
