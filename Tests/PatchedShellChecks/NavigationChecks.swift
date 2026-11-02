import Foundation
import SwiftUI
import PatchedShell

@MainActor func registerNavigationChecks() {
    check("navigation: approved primary and lower groups have exact order") {
        let state = fixtureNavigation()
        try expect(state.mainDestinations == expectedMain, "Primary destination group/order missing")
        try expect(state.lowerDestinations == expectedLower, "Lower destination group/order missing")
        try expect(state.settingsSections == expectedSections, "Settings section group/order missing")
    }
    for (destination, label) in destinationLabels {
        check("navigation label: \(destination.rawValue)") {
            try expect(fixtureNavigation().label(for: destination) == label, "Approved literal destination label missing")
        }
    }
    for (section, label) in sectionLabels {
        check("settings label: \(section.rawValue)") {
            try expect(fixtureNavigation().label(for: section) == label, "Approved literal settings label missing")
        }
    }
    check("navigation: construction is inert and keeps explicitly supplied selection") {
        var events: [ShellDestination] = []
        let state = fixtureNavigation(destination: .activity, section: .network, onSelection: { events.append($0) })
        try expect(events.isEmpty && state.destination == .activity && state.settingsSection == .network,
                   "Constructing display state triggered a callback or changed selection")
    }
    for destination in expectedMain + expectedLower where destination != .updates {
        check("navigation transition: explicit \(destination.rawValue) once") {
            var events: [ShellDestination] = []
            let state = fixtureNavigation(onSelection: { events.append($0) })
            try expect(state.select(destination), "Explicit destination selection refused")
            try expect(state.destination == destination && events == [destination], "Wrong destination or callback delivery")
            try expect(!state.select(destination) && events == [destination], "Duplicate selection dispatched again")
        }
    }
    for section in expectedSections where section != .updates {
        check("settings transition: explicit \(section.rawValue)") {
            let state = fixtureNavigation(destination: .settings)
            try expect(state.selectSettings(section), "Explicit settings selection refused")
            try expect(state.settingsSection == section, "Settings selection unchanged")
        }
    }
    let keys: [(ShellSettingsSection, ShellTabKey, ShellSettingsSection)] = [
        (.updates, .left, .diagnostics), (.diagnostics, .right, .updates),
        (.updates, .right, .network), (.diagnostics, .left, .network),
        (.network, .home, .updates), (.network, .end, .diagnostics)
    ]
    for (start, key, end) in keys {
        check("settings key: \(start.rawValue) \(key.rawValue) -> \(end.rawValue)") {
            let state = fixtureNavigation(destination: .settings, section: start)
            try expect(state.moveSettings(key) && state.settingsSection == end, "Tab keyboard transition missing")
            try expect(state.destination == .settings, "Tab key changed destination")
        }
    }
    check("drafts: preserve caller identity and edits through all tabs and destinations") {
        let state = fixtureNavigation()
        let drafts = state.drafts
        drafts.values[.network] = "edited synthetic draft"
        for destination in expectedMain + expectedLower { state.select(destination) }
        for section in expectedSections { state.selectSettings(section) }
        try expect(state.destination == .settings && state.settingsSection == .diagnostics, "Round trip did not navigate")
        try expect(state.drafts === drafts && drafts.values[.network] == "edited synthetic draft",
                   "Navigation replaced or reset caller drafts")
        try expect(drafts.values[.updates] == "draft update text" && drafts.values[.diagnostics] == "draft diagnostics text",
                   "An unrelated draft changed")
    }
    check("input: exact valid raw selections accepted") {
        let state = fixtureNavigation()
        try expect(state.selectRaw("settings") && state.destination == .settings, "Valid destination raw input refused")
        try expect(state.selectSettingsRaw("network") && state.settingsSection == .network, "Valid settings raw input refused")
        try expect(state.moveSettingsRaw("end") && state.settingsSection == .diagnostics, "Valid key raw input refused")
    }
    check("input: unknown and nonexact values leave state and callbacks unchanged") {
        var events: [ShellDestination] = []
        let state = fixtureNavigation(onSelection: { events.append($0) })
        let before = state.drafts.values
        for invalid in ["", "unknown", "Settings", " settings", "network\n", "<script>"] {
            try expect(!state.selectRaw(invalid), "Invalid destination accepted")
            try expect(!state.selectSettingsRaw(invalid), "Invalid section accepted")
            try expect(!state.moveSettingsRaw(invalid), "Invalid key accepted")
        }
        try expect(state.destination == .updates && state.settingsSection == .updates && events.isEmpty && state.drafts.values == before,
                   "Invalid input mutated state, drafts or callbacks")
    }
    check("focus declaration: ordered destinations followed by active settings tabs") {
        let state = fixtureNavigation(destination: .settings)
        try expect(state.focusOrder == ["destination:updates", "destination:applications", "destination:activity",
                                       "destination:licence", "destination:support", "destination:settings",
                                       "settings:updates", "settings:network", "settings:diagnostics"],
                   "Declared focus traversal missing; actual native routing remains unverified")
    }
    check("focus declaration: settings tabs absent outside Settings") {
        try expect(fixtureNavigation().focusOrder == ["destination:updates", "destination:applications", "destination:activity",
                                                     "destination:licence", "destination:support", "destination:settings"],
                   "Declared destination traversal missing")
    }
    for (role, light, dark) in expectedPalette {
        check("brand palette: \(role) exact light/dark values") {
            try expect(ShellBrand.hex(role, appearance: .light) == light, "Canonical light token missing")
            try expect(ShellBrand.hex(role, appearance: .dark) == dark, "Canonical dark token missing")
        }
    }
    check("brand contrast: canonical body/accent pairings meet text contrast") {
        func luminance(_ hex: String) throws -> Double {
            guard hex.count == 7, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else {
                throw Failure(description: "Missing or invalid semantic colour")
            }
            let channels = [Double((value >> 16) & 255), Double((value >> 8) & 255), Double(value & 255)].map { value -> Double in
                let normalized = value / 255
                return normalized <= 0.04045 ? normalized / 12.92 : pow((normalized + 0.055) / 1.055, 2.4)
            }
            return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        }
        for appearance in ShellAppearance.allCases {
            for (foreground, background) in [(ShellColorRole.text, ShellColorRole.surface), (.muted, .surface), (.onAccent, .accent)] {
                guard let front = ShellBrand.hex(foreground, appearance: appearance), let back = ShellBrand.hex(background, appearance: appearance) else {
                    throw Failure(description: "Semantic palette not implemented")
                }
                let a = try luminance(front), b = try luminance(back)
                try expect((max(a, b) + 0.05) / (min(a, b) + 0.05) >= 4.5, "Text pairing below 4.5:1")
            }
        }
    }
    check("brand mark: approved open P geometry occupies the master grid") {
        let path = ShellBrandMark().path(in: CGRect(x: 0, y: 0, width: 64, height: 64))
        try expect(!path.isEmpty, "Geometric P is absent")
        let bounds = path.boundingRect
        try expect(abs(bounds.minX - 2) < 0.1 && abs(bounds.minY - 2) < 0.1 && abs(bounds.maxX - 62) < 0.1,
                   "Canonical circle bounds changed")
        try expect(path.contains(CGPoint(x: 32, y: 5), eoFill: true), "Coverage disk missing")
        try expect(!path.contains(CGPoint(x: 32, y: 32), eoFill: true), "Open centre filled")
        try expect(!path.contains(CGPoint(x: 19, y: 52), eoFill: true), "Negative-space stem closed")
        try expect(path.contains(CGPoint(x: 48, y: 48), eoFill: true), "Lower bowl missing")
    }
}
