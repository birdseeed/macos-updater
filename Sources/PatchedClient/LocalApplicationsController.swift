import Foundation
import Combine

public enum LocalApplicationsPhase: Sendable, Equatable { case idle, scanning, finished }

/// Display values are observations only; none grants update or installation authority.
public struct LocalApplicationsRowText: Sendable, Equatable {
    public let name: String
    public let version: String
    public let build: String
    public let location: String
    public let metadata: String
    public let provenance: LocalApplicationProvenanceText
    public let installedIcon: LocalInstalledIcon?
}
public struct LocalApplicationsText: Sendable, Equatable {
    public let heading: String
    public let status: String
    public let scanTitle: String
    public let scanEnabled: Bool
    public let notice: String
    public let observedAt: String?
    public let provenance: String?
    public let roots: [String]
    public let issues: [String]
    public let rows: [LocalApplicationsRowText]
    public var allLines: [String] {
        [heading, status, scanTitle, notice] + [observedAt, provenance].compactMap { $0 }
            + roots + issues + rows.flatMap { [$0.name, $0.version, $0.build, $0.location, $0.metadata] + $0.provenance.lines }
    }
}

/// Owns one scanner for explicit, read-only observations. Opening a view does no work.
@MainActor public final class LocalApplicationsController: ObservableObject {
    private let inventory: LocalApplicationInventory
    private var inFlight: Task<Void, Never>?
    @Published public private(set) var phase: LocalApplicationsPhase = .idle
    @Published public private(set) var observation: LocalInventoryObservation?
    public init() { inventory = LocalApplicationInventory() }
    @_spi(Testing) public init(inventory: LocalApplicationInventory) { self.inventory = inventory }
    public var text: LocalApplicationsText {
        LocalApplicationsText(heading: "Applications", status: status,
            scanTitle: phase == .scanning ? "Scanning…" : (observation == nil ? "Scan" : "Scan again"),
            scanEnabled: phase != .scanning, notice: "Update availability has not been checked.",
            observedAt: observation.map { "Observed: " + $0.finishedAt.formatted(date: .abbreviated, time: .standard) },
            provenance: observation?.provenance == .fixture ? "Fixture observation: test folders only." : nil,
            roots: observation?.roots.map { root in
                scope(root.scope) + " · " + rootStatus(root.status) + "\n" + (root.path.isEmpty ? "Path unavailable" : root.path)
            } ?? [],
            issues: observation?.issues.map { issue in
                explanation(issue.kind) + (issue.path.map { "\n" + $0 } ?? "")
            } ?? [],
            rows: observation.map { snapshot in snapshot.applications.map { app in
                LocalApplicationsRowText(name: app.displayName,
                    version: "Claimed version: " + (app.claimedShortVersion ?? "unavailable"),
                    build: "Claimed build: " + (app.claimedBuild ?? "unavailable"),
                    location: app.path, metadata: metadata(app.metadataDisposition),
                    provenance: LocalApplicationProvenanceText(application: app, observation: snapshot,
                        isScanning: phase == .scanning), installedIcon: app.installedIcon)
            } } ?? [])
    }
    public func scan() {
        guard phase != .scanning, inFlight == nil else { return }
        phase = .scanning
        // The actor performs its synchronous filesystem work off MainActor. Retain the
        // scanner through completion, without retaining a closed view's controller.
        inFlight = Task { [weak self, inventory] in
            let result = await inventory.scan()
            guard let self else { return }
            self.observation = result
            self.phase = .finished
            self.inFlight = nil
        }
    }
    @_spi(Testing) public func waitUntilIdle() async { await inFlight?.value }

    private var status: String {
        if phase == .scanning {
            return observation == nil ? "Scanning local application folders…" : "Scanning again… Previous observation shown below."
        }
        guard let observation else { return "Choose Scan to observe local application folders." }
        switch observation.completeness {
        case .unavailable: return "Observation unavailable. Review the folder status and explanations below."
        case .incomplete: return "Observation incomplete. Some folders or metadata could not be observed."
        case .complete:
            if observation.applications.isEmpty {
                return observation.roots.contains { $0.status == .scanned }
                    ? "No applications found in the scanned folders."
                    : "No folders were scanned. Review the folder status below."
            }
            return "Observed \(observation.applications.count) application copies in the scanned folders."
        }
    }
    private func scope(_ value: LocalInventoryRootScope) -> String {
        switch value {
        case .systemApplications: return "System Applications folder"
        case .userApplications: return "User Applications folder"
        case .fixture: return "Fixture folder"
        }
    }
    private func rootStatus(_ value: LocalInventoryRootStatus) -> String {
        switch value {
        case .scanned: return "scanned"
        case .absent: return "absent"
        case .refused: return "refused"
        case .unavailable: return "unavailable"
        }
    }
    private func metadata(_ value: LocalInventoryMetadataDisposition) -> String {
        switch value {
        case .observed: return "Observed metadata; claims unverified."
        case .unavailable: return "Metadata unavailable; claims unverified."
        case .malformed: return "Some metadata is malformed; displayed claims remain unverified."
        case .refused: return "Metadata refused; claims unavailable and unverified."
        }
    }
    private func explanation(_ value: LocalInventoryIssueKind) -> String {
        switch value {
        case .unavailable: return "A folder location is unavailable."
        case .unsafePath: return "A path was refused because it could not be safely observed."
        case .unreadable: return "A folder or file could not be read."
        case .malformedMetadata: return "Application metadata could not be interpreted."
        case .metadataUnavailable: return "Application metadata is unavailable."
        case .changedDuringScan: return "A folder or file changed during the scan; its claims are unavailable."
        case .entryLimit: return "The directory entry limit was reached; coverage is incomplete."
        case .depthLimit: return "The folder depth limit was reached; coverage is incomplete."
        case .applicationLimit: return "The application limit was reached; coverage is incomplete."
        case .plistLimit: return "An application's metadata exceeds the per-file size limit."
        case .totalMetadataLimit: return "The total metadata read limit was reached."
        case .issueLimit: return "The explanation limit was reached; further issues are not listed."
        case .fieldLimit: return "A metadata field exceeds the permitted display size."
        case .pathLimit: return "A path exceeds the permitted size and was refused."
        case .generationExhausted: return "This scanner's observation counter is exhausted; no further scan was made."
        }
    }
}
