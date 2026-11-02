import SwiftUI

/// The same bounded native view is used by offscreen checks. It performs no work on appearance.
public struct LicenceSupportView: View {
    @ObservedObject private var controller: LicenceSupportController
    public init(controller: LicenceSupportController) { self.controller = controller }
    public var body: some View {
        let text = LicenceSupportViewText(controller)
        let displayedBytes = controller.displayedDescriptorBytes
        let displayedDigest = controller.displayedDigest
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: text.title).font(.title2).bold()
            Text(verbatim: text.notice).foregroundStyle(.secondary)
            Text(verbatim: text.status).font(.headline)
            ForEach(Array(text.rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: row.label).font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: row.value).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            ForEach(Array(text.consequences.enumerated()), id: \.offset) { _, consequence in
                Text(verbatim: consequence).fixedSize(horizontal: false, vertical: true)
            }
            Button {
                // Capture this rendered display, so a click on an older view cannot confirm a newer preparation.
                guard let bytes = displayedBytes, let digest = displayedDigest else { return }
                controller.confirm(descriptorBytes: bytes, digest: digest)
            } label: {
                Text(verbatim: text.confirmTitle)
                    .padding(8)
                    .background(text.canConfirm ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.1))
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .disabled(!text.canConfirm)
            Text(verbatim: text.recoveryNotice).foregroundStyle(.secondary)
        }
        .font(.body)
        .padding(24)
        .frame(width: 940, alignment: .leading)
        .frame(minHeight: 220, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .fixedSize(horizontal: false, vertical: true)
    }
}
