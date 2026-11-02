import SwiftUI

/// Supplied images only. This type cannot discover installed apps or fetch an icon.
public struct ShellIcon: View {
    private let suppliedImage: Image?
    private let appName: String
    public init(suppliedImage: Image?, appName: String) {
        self.suppliedImage = suppliedImage
        self.appName = appName
    }
    public var accessibilityName: String { appName }
    public var body: some View {
        VStack(spacing: 6) {
            if let suppliedImage {
                suppliedImage.resizable().scaledToFit().frame(width: 40, height: 40)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 32)).foregroundStyle(.secondary)
                    .frame(width: 40, height: 40).accessibilityHidden(true)
            }
            Text(verbatim: appName).font(.caption)
                .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityName))
    }
}
