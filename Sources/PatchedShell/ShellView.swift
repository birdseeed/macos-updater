import SwiftUI

/// Offscreen-capable seam only. No scene, controller, task or operational action.
/// Only the selected caller-owned content is constructed and displayed.
public struct ShellView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @ObservedObject private var navigation: ShellNavigation
    private let destinationLabels: [ShellDestination: String]
    private let settingsLabels: [ShellSettingsSection: String]
    private let destinationContent: (ShellDestination) -> AnyView
    private let settingsContent: (ShellSettingsSection, ShellDrafts) -> AnyView

    public init(navigation: ShellNavigation,
                destinationLabels: [ShellDestination: String] = [:],
                settingsLabels: [ShellSettingsSection: String] = [:],
                destinationContent: @escaping (ShellDestination) -> AnyView,
                settingsContent: @escaping (ShellSettingsSection, ShellDrafts) -> AnyView) {
        self.navigation = navigation
        self.destinationLabels = destinationLabels
        self.settingsLabels = settingsLabels
        self.destinationContent = destinationContent
        self.settingsContent = settingsContent
    }
    private var appearance: ShellAppearance { colorScheme == .dark ? .dark : .light }
    private func color(_ role: ShellColorRole) -> Color { ShellBrand.color(role, appearance: appearance) }
    private func destinationLabel(_ destination: ShellDestination) -> String {
        destinationLabels[destination] ?? navigation.label(for: destination)
    }
    private func sectionLabel(_ section: ShellSettingsSection) -> String {
        settingsLabels[section] ?? navigation.label(for: section)
    }

    public var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                sidebar.frame(width: geometry.size.width < 760 ? 180 : 208)
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: destinationLabel(navigation.destination))
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(20)
                    Divider()
                    if navigation.destination == .settings {
                        settingsTabs
                        Divider()
                    }
                    selectedContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(color(.surface))
            }
        }
        .font(.body)
        .foregroundStyle(color(.text))
        .tint(color(.accent))
        .background(color(.surface))
    }

    private var sidebar: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        ShellBrandMark()
                            .fill(RadialGradient(stops: [
                                .init(color: Color(.sRGB, red: 34 / 255, green: 211 / 255, blue: 238 / 255), location: 0),
                                .init(color: Color(.sRGB, red: 59 / 255, green: 130 / 255, blue: 246 / 255), location: 0.48),
                                .init(color: Color(.sRGB, red: 37 / 255, green: 99 / 255, blue: 235 / 255), location: 1)
                            ], center: UnitPoint(x: 0.82, y: 0.24), startRadius: 0, endRadius: 32 * 0.78),
                                  style: FillStyle(eoFill: true))
                            .frame(width: 32, height: 32).accessibilityHidden(true)
                        Text(verbatim: "Patched").font(.title3.weight(.semibold))
                    }
                    .padding(.horizontal, 10).padding(.bottom, 12)
                    destinationGroup(navigation.mainDestinations)
                    Spacer(minLength: 24)
                    destinationGroup(navigation.lowerDestinations)
                }
                .padding(12)
                .frame(minHeight: geometry.size.height, alignment: .topLeading)
            }
        }
        .background(color(.sidebar))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: "Navigation"))
    }

    private func destinationGroup(_ destinations: [ShellDestination]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(destinations, id: \.self) { destination in
                let selected = navigation.destination == destination
                Button(action: { navigation.select(destination) }) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: symbol(for: destination))
                            .frame(width: 18).accessibilityHidden(true)
                        Text(verbatim: destinationLabel(destination))
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .font(.body.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? color(.onAccent) : color(.text))
                    .padding(.horizontal, 10).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(selected ? color(.accent) : Color.clear))
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: destinationLabel(destination)))
                .accessibilityIdentifier("destination:" + destination.rawValue)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var settingsTabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(navigation.settingsSections, id: \.self) { section in
                    let selected = navigation.settingsSection == section
                    Button(action: { navigation.selectSettings(section) }) {
                        Text(verbatim: sectionLabel(section))
                            .font(.body.weight(selected ? .semibold : .regular))
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(selected ? color(.onAccent) : color(.text))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(selected ? color(.accent) : color(.sidebar)))
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(color(.muted), lineWidth: contrast == .increased ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: sectionLabel(section)))
                    .accessibilityIdentifier("settings:" + section.rawValue)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }.padding(12)
        }
        .onMoveCommand { direction in
            switch direction {
            case .left: navigation.moveSettings(.left)
            case .right: navigation.moveSettings(.right)
            default: break
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: "Settings sections"))
    }

    private var selectedContent: some View {
        GeometryReader { geometry in
            // Existing licence/Macs children own a fixed 480pt width. Preserve them
            // unchanged and make excess width/height reachable in the shell viewport.
            let scroll = ScrollView([.horizontal, .vertical]) {
                Group {
                    if navigation.destination == .settings {
                        settingsContent(navigation.settingsSection, navigation.drafts)
                    } else {
                        destinationContent(navigation.destination)
                    }
                }
                .frame(width: max(480, geometry.size.width - 32), alignment: .topLeading)
                .padding(16)
            }
            if #available(macOS 15.0, *) {
                scroll.defaultScrollAnchor(.topLeading, for: .initialOffset)
            } else {
                scroll
            }
        }
    }

    private func symbol(for destination: ShellDestination) -> String {
        switch destination {
        case .updates: return "arrow.down.circle"
        case .applications: return "square.grid.2x2"
        case .activity: return "clock"
        case .licence: return "key"
        case .support: return "questionmark.circle"
        case .settings: return "gearshape"
        }
    }
}
