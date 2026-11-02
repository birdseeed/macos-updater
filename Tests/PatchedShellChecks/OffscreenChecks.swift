import SwiftUI
import PatchedShell
import PatchedCore
import PatchedUI

@MainActor func registerOffscreenChecks() {
    for destination in expectedMain + expectedLower {
        for dark in [false, true] {
            check("render content: \(destination.rawValue) \(dark ? "dark" : "light")") {
                let output = try outputDirectory()
                let state = fixtureNavigation(destination: destination)
                var requested: [ShellDestination] = []
                var requestedSections: [ShellSettingsSection] = []
                let view = ShellView(navigation: state, destinationContent: { value in
                    requested.append(value)
                    return probe("Fixture destination: " + value.rawValue)
                }, settingsContent: { section, _ in
                    requestedSections.append(section)
                    return probe("Fixture settings: " + section.rawValue)
                })
                let result = try render(view, dark: dark)
                try retain(result, name: destination.rawValue + (dark ? "-dark" : "-light"), output: output)
                print("Retained shell specimen: \(output.path)")
                try expect(try probePixelCount(result.image) >= 900, "Selected content probe absent or clipped")
                if destination == .settings {
                    try expect(Set(requestedSections) == [.updates] && requested.isEmpty, "Wrong settings content requested")
                } else {
                    try expect(Set(requested) == [destination] && requestedSections.isEmpty, "Unselected content requested")
                }
            }
        }
    }
    for section in expectedSections {
        check("render settings: \(section.rawValue) receives identical caller drafts") {
            let state = fixtureNavigation(destination: .settings, section: section)
            var suppliedDrafts: [ShellDrafts] = []
            var sections: [ShellSettingsSection] = []
            let result = try render(ShellView(navigation: state, destinationContent: { _ in probe("Wrong content") },
                                               settingsContent: { current, drafts in
                sections.append(current); suppliedDrafts.append(drafts)
                return probe("Fixture section: " + current.rawValue)
            }))
            try expect(Set(sections) == [section] && !suppliedDrafts.isEmpty && suppliedDrafts.allSatisfy { $0 === state.drafts },
                       "Settings content lost current section or caller draft identity")
            try expect(try probePixelCount(result.image) >= 900, "Settings content missing")
        }
    }
    check("render: appearance and layout never dispatch selection or edit drafts") {
        var events: [ShellDestination] = []
        let state = fixtureNavigation(onSelection: { events.append($0) })
        let before = state.drafts.values
        _ = try render(ShellView(navigation: state, destinationContent: { probe($0.rawValue) },
                                 settingsContent: { section, _ in probe(section.rawValue) }))
        try expect(events.isEmpty && state.destination == .updates && state.drafts.values == before,
                   "Offscreen painting performed an action")
    }
    for dark in [false, true] {
        for compact in [false, true] {
            check("render accessibility specimen: \(dark ? "dark" : "light") \(compact ? "compact" : "normal")") {
                let output = try outputDirectory()
                let state = fixtureNavigation()
                let view = ShellView(navigation: state, destinationLabels: [.updates: longLabel],
                                     settingsLabels: [.updates: longLabel],
                                     destinationContent: { _ in probe(longLabel) },
                                     settingsContent: { _, _ in probe(longLabel) })
                let result = try render(view, width: compact ? 640 : 800, height: compact ? 480 : 600,
                                        dark: dark)
                try retain(result, name: "long-label-\(dark)-\(compact)", output: output)
                try expect(try probePixelCount(result.image) >= 900, "Long content clipped or not displayed")
                // Contrast/reduced-motion environment keys are get-only in the current SDK.
                // Native settings, keyboard focus and VoiceOver require separate target proof.
            }
        }
    }
    check("render reuse: real existing update and licence views remain injected, never rebuilt") {
        let output = try outputDirectory()
        var actions = 0
        let update = UpdateView(presentation: .make(UpdateDisplayInput(appName: "Fixture Firefox")), onUpdate: { actions += 1 })
        let specimens: [(String, AnyView)] = [
            ("update", AnyView(update)), ("licence", AnyView(LicenceView(onIntent: { _ in actions += 1 }))),
            ("macs", AnyView(ManageMacsView(onIntent: { _ in actions += 1 })))
        ]
        var outputs = Set<Data>()
        for (name, specimen) in specimens {
            let state = fixtureNavigation()
            let view = ShellView(navigation: state, destinationContent: { _ in specimen },
                                 settingsContent: { _, _ in probe("Fixture settings") })
            let result = try render(view)
            try retain(result, name: "existing-" + name, output: output)
            outputs.insert(result.png)
        }
        try expect(actions == 0, "Painting reused views performed an action")
        try expect(outputs.count == 3, "Shell discarded or replaced existing presentation content")
    }
    check("icon: supplied fixture image paints and differs from honest fallback") {
        let output = try outputDirectory()
        let image = try render(Rectangle().fill(probeColor), width: 40, height: 40).image
        let supplied = ShellIcon(suppliedImage: Image(decorative: image, scale: 1), appName: "Fixture app")
        let fallback = ShellIcon(suppliedImage: nil, appName: "Fixture app")
        let a = try render(supplied, width: 160, height: 100)
        let b = try render(fallback, width: 160, height: 100)
        try retain(a, name: "supplied-fixture-icon", output: output)
        try retain(b, name: "missing-fixture-icon", output: output)
        try expect(try probePixelCount(a.image) >= 900, "Supplied icon missing")
        try expect(a.png != b.png, "Supplied and missing icon paint identically")
        try expect(try probePixelCount(b.image) == 0, "Fallback invented a supplied icon")
    }
    check("icon: supplied and fallback accessibility names keep literal app text") {
        try expect(ShellIcon(suppliedImage: nil, appName: literalLabel).accessibilityName == literalLabel,
                   "Missing icon loses literal app name")
        let image = try render(Rectangle().fill(probeColor), width: 40, height: 40).image
        try expect(ShellIcon(suppliedImage: Image(decorative: image, scale: 1), appName: literalLabel).accessibilityName == literalLabel,
                   "Supplied icon loses literal app name")
    }
}
