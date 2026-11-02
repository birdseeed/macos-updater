import Foundation

/// Literal display of one installed copy's observations. This is neither candidate
/// evidence nor permission to fetch, verify or install anything.
public struct LocalApplicationProvenanceText: Sendable, Equatable {
    public let lines: [String]
    /// Opaque UI lifetime key; never render it. A rescan discards disclosure state.
    public let disclosureID: String

    internal init(application app: LocalApplicationObservation, observation: LocalInventoryObservation,
                  isScanning: Bool) {
        let identity = app.physicalIdentity
        disclosureID = [observation.sessionID.uuidString, String(observation.generation), app.path,
            String(identity.device), String(identity.inode), String(identity.changeSeconds),
            String(identity.changeNanoseconds), isScanning ? "scanning" : "finished"].joined(separator: "\u{0}")
        let vendor = app.vendorMetadata
        var sources: [String] = [], destinations: [String] = []
        if vendor.sparkleDisposition == .observed, let feed = vendor.sparkleFeedURL {
            sources.append("Sparkle (observed installed claim)")
            destinations.append(LocalProvenanceDisplay.destination(feed))
        } else if vendor.sparkleDisposition != .unavailable {
            sources.append("Sparkle claim unavailable or refused")
        }
        if vendor.electronDisposition == .observed, vendor.electronConfigBytes != nil {
            sources.append("Electron (observed installed configuration)")
            // Raw configuration is not an accepted parsed destination interface.
            destinations.append("unknown (installed configuration has not been interpreted)")
        } else if vendor.electronDisposition != .unavailable {
            sources.append("Electron claim unavailable or refused")
        }
        let freshness = isScanning
            ? "Evidence freshness: stale previous observation; scan in progress."
            : "Evidence freshness: observed " + observation.finishedAt.formatted(date: .abbreviated, time: .standard)
                + "; point-in-time local claims, current state unknown."
        let installedIdentity = app.installedIdentity
        let signatureText: String
        if let installedIdentity {
            signatureText = installedIdentity.provenance == .fixture
                ? "Fixture signature observation: synthetic developer identity for the exact compiled Firefox pin."
                : "Developer signature observed for the exact compiled Firefox pin."
        } else { signatureText = "Verification: not checked" }
        lines = [
            "Publisher: unknown",
            "Update source: " + (sources.isEmpty ? "unknown" : sources.joined(separator: "; ")),
            "Destination: " + (destinations.isEmpty ? "unknown" : destinations.joined(separator: "; ")),
            "Installed version (observed claim): " + LocalProvenanceDisplay.claim(app.claimedShortVersion),
            "Installed build (observed claim): " + LocalProvenanceDisplay.claim(app.claimedBuild),
            "Candidate version: unknown",
            "Candidate build: unknown",
            freshness,
            signatureText,
            installedIdentity == nil
                ? "Installed metadata is an unverified claim. No candidate, publisher identity, signature or notarisation evidence is supplied by this inventory. Supported installation is unknown."
                : "This point-in-time developer identity observation supplies no notarisation, current trust, candidate version, update eligibility or installation authority. Supported installation is unknown."
        ]
    }
}

/// Presentation-only bounds and privacy. Never opens or resolves a destination.
internal enum LocalProvenanceDisplay {
    static func claim(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "unknown" }
        // Version/name claims can contain URLs or local paths too. Withhold these
        // rather than echoing secrets hidden inside an otherwise literal string.
        // Refuse query, fragment and parameter delimiters even without a URL.
        guard !value.contains("/"), !value.contains("\\"), !value.contains("@"),
              !value.contains(where: { "?#&=;%".contains($0) }),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0)
                  || $0.properties.generalCategory == .format }) else {
            return "withheld (unsafe display text)"
        }
        var result = ""
        for character in value {
            if result.utf8.count + character.utf8.count > 160 { return result + "… (shortened)" }
            result.append(character)
        }
        return result
    }

    static func destination(_ value: String) -> String {
        guard value.utf8.count <= LocalInventoryLimits.fieldBytes,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0)
                  || $0.properties.generalCategory == .format }),
              let parts = URLComponents(string: value),
              let scheme = parts.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = parts.host?.lowercased(), !host.isEmpty, host.utf8.count <= 253,
              host.unicodeScalars.allSatisfy({ scalar in
                  (scalar.value >= 97 && scalar.value <= 122)
                  || (scalar.value >= 48 && scalar.value <= 57)
                  || ".-:[]".unicodeScalars.contains(scalar)
              }) else { return "unknown (source destination withheld)" }
        // Rebuild from an allowlisted host, never an absoluteString, raw authority,
        // path, port, fragment, user/password, query or private filesystem location.
        return scheme + "://" + host + " (observed; path and credentials hidden)"
    }

    static func location(_ value: String) -> String {
        value.isEmpty ? "Location unavailable" : "Local application copy (private path hidden)"
    }

    static func explanation(_ value: String) -> String {
        // The existing observation model retains exact paths for copy identity.
        // Its human explanation is the first line; subsequent lines are paths.
        String(value.prefix(while: { $0 != "\n" && $0 != "\r" }))
    }
}
