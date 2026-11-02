import SwiftUI

public enum ShellDestination: String, CaseIterable, Hashable, Sendable {
    case updates, applications, activity, licence, support, settings
}
public enum ShellSettingsSection: String, CaseIterable, Hashable, Sendable {
    case updates, network, diagnostics
}
public enum ShellTabKey: String, Sendable {
    case left, right, home, end
}

/// Caller-owned display drafts only. These strings are never applied or persisted.
@MainActor public final class ShellDrafts {
    public var values: [ShellSettingsSection: String]
    public init(values: [ShellSettingsSection: String]) { self.values = values }
}

/// Main-actor display selection only. Callbacks convey no operational authority.
@MainActor public final class ShellNavigation: ObservableObject {
    @Published public private(set) var destination: ShellDestination
    @Published public private(set) var settingsSection: ShellSettingsSection
    public let drafts: ShellDrafts
    private let onSelection: (ShellDestination) -> Void

    public init(destination: ShellDestination, settingsSection: ShellSettingsSection,
                drafts: ShellDrafts, onSelection: @escaping (ShellDestination) -> Void = { _ in }) {
        self.destination = destination
        self.settingsSection = settingsSection
        self.drafts = drafts
        self.onSelection = onSelection
    }
    public var mainDestinations: [ShellDestination] { [.updates, .applications, .activity, .licence] }
    public var lowerDestinations: [ShellDestination] { [.support, .settings] }
    public var settingsSections: [ShellSettingsSection] { [.updates, .network, .diagnostics] }
    /// Declared traversal, not evidence of native focus or VoiceOver routing.
    public var focusOrder: [String] {
        let destinations = (mainDestinations + lowerDestinations).map { "destination:" + $0.rawValue }
        return destinations + (destination == .settings ? settingsSections.map { "settings:" + $0.rawValue } : [])
    }
    public func label(for destination: ShellDestination) -> String {
        switch destination {
        case .updates: return "Updates"
        case .applications: return "Applications"
        case .activity: return "Activity"
        case .licence: return "Licence & Macs"
        case .support: return "Help & Support"
        case .settings: return "Settings"
        }
    }
    public func label(for section: ShellSettingsSection) -> String {
        switch section {
        case .updates: return "Updates"
        case .network: return "Network"
        case .diagnostics: return "Diagnostics"
        }
    }
    @discardableResult public func select(_ destination: ShellDestination) -> Bool {
        guard self.destination != destination else { return false }
        self.destination = destination
        onSelection(destination)
        return true
    }
    @discardableResult public func selectRaw(_ value: String) -> Bool {
        guard let destination = ShellDestination(rawValue: value) else { return false }
        return select(destination)
    }
    @discardableResult public func selectSettings(_ section: ShellSettingsSection) -> Bool {
        guard settingsSection != section else { return false }
        settingsSection = section
        return true
    }
    @discardableResult public func selectSettingsRaw(_ value: String) -> Bool {
        guard let section = ShellSettingsSection(rawValue: value) else { return false }
        return selectSettings(section)
    }
    @discardableResult public func moveSettings(_ key: ShellTabKey) -> Bool {
        let sections = settingsSections
        guard let current = sections.firstIndex(of: settingsSection) else { return false }
        let next: Int
        switch key {
        case .left: next = (current + sections.count - 1) % sections.count
        case .right: next = (current + 1) % sections.count
        case .home: next = 0
        case .end: next = sections.count - 1
        }
        return selectSettings(sections[next])
    }
    @discardableResult public func moveSettingsRaw(_ value: String) -> Bool {
        guard let key = ShellTabKey(rawValue: value) else { return false }
        return moveSettings(key)
    }
}
