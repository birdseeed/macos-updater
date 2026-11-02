import Foundation
import PatchedScheduling

/// Untrusted synthetic input. Raw values grant no native identity or execution authority.
public struct InventoryIdentity: Sendable {
    public let instanceID: String
    public let product: String
    public let scope: String
    public let bundleID: String
    public let publisher: String
    public let edition: String
    public let channel: String
    public let architecture: String
    public let location: String
    public let installedVersion: String
    public let installedBuild: String
    public init(instanceID: String, product: String, scope: String, bundleID: String, publisher: String,
                edition: String, channel: String, architecture: String, location: String,
                installedVersion: String, installedBuild: String) {
        self.instanceID = instanceID; self.product = product; self.scope = scope; self.bundleID = bundleID
        self.publisher = publisher; self.edition = edition; self.channel = channel
        self.architecture = architecture; self.location = location
        self.installedVersion = installedVersion; self.installedBuild = installedBuild
    }
}
public struct InventoryCandidate: Sendable {
    public let identity: InventoryIdentity
    public let release: ReleaseIdentity
    public init(identity: InventoryIdentity, release: ReleaseIdentity) { self.identity = identity; self.release = release }
}
public enum InventoryRunningState: Equatable, Sendable { case closed, running, unknown }
public enum InventoryRoute: Equatable, Sendable { case unattended, attention, unknown }
public enum InventoryCatalogueState: Equatable, Sendable { case fresh, stale, offline, missing }
public enum InventoryUpdateEvidence: Sendable {
    case unknown, syntheticCurrent(InventoryIdentity), syntheticAvailable(InventoryCandidate)
}
public struct InventoryObservation: Sendable {
    public let identity: InventoryIdentity
    public let displayName: String
    public let running: InventoryRunningState
    public let route: InventoryRoute
    public let externallyManaged: Bool
    public let update: InventoryUpdateEvidence
    public init(identity: InventoryIdentity, displayName: String, running: InventoryRunningState,
                route: InventoryRoute, externallyManaged: Bool, update: InventoryUpdateEvidence) {
        self.identity = identity; self.displayName = displayName; self.running = running; self.route = route
        self.externallyManaged = externallyManaged; self.update = update
    }
}
public struct InventorySnapshot: Sendable {
    public let principal: SchedulingPrincipal
    public let generation: UInt64
    public let observedAt: UInt64
    public let catalogue: InventoryCatalogueState
    public let rows: [InventoryObservation]
    public init(principal: SchedulingPrincipal, generation: UInt64, observedAt: UInt64,
                catalogue: InventoryCatalogueState, rows: [InventoryObservation]) {
        self.principal = principal; self.generation = generation; self.observedAt = observedAt
        self.catalogue = catalogue; self.rows = rows
    }
}
public enum InventoryRead: Sendable { case unavailable, snapshot(InventorySnapshot) }
public enum InventoryRefusal: Equatable, Sendable {
    case unavailable, principal, reentrant, generation, bounds, identity, preferences, staleSelection, notReady
}
public enum InventoryRefreshResult: Equatable, Sendable {
    case accepted(generation: UInt64), unchanged(generation: UInt64), refused(InventoryRefusal)
}
@_spi(Testing) @MainActor public protocol SyntheticInventorySource: AnyObject {
    func read(maximumRows: Int) -> InventoryRead
}

// All comparisons here bind fixture bytes, without Unicode normalisation or native lookup.
enum InventoryValidation {
    static func exact(_ left: String, _ right: String) -> Bool {
        left.utf8.elementsEqual(right.utf8)
    }
    static func fields(_ value: InventoryIdentity) -> [String] {
        [value.instanceID, value.product, value.scope, value.bundleID, value.publisher, value.edition,
         value.channel, value.architecture, value.location, value.installedVersion, value.installedBuild]
    }
    static func fields(_ value: ReleaseIdentity) -> [String] {
        [value.product, value.scope, value.release, value.build, value.edition, value.channel, value.artifact]
    }
    static func exactFields(_ left: [String], _ right: [String]) -> Bool {
        left.count == right.count && zip(left, right).allSatisfy { exact($0.0, $0.1) }
    }
    static func exact(_ left: InventoryIdentity, _ right: InventoryIdentity) -> Bool {
        exactFields(fields(left), fields(right))
    }
    static func exact(_ left: ReleaseIdentity, _ right: ReleaseIdentity) -> Bool {
        exactFields(fields(left), fields(right))
    }
    static func bounded(_ value: String, _ maximum: Int) -> Bool {
        value.utf8.prefix(maximum + 1).count <= maximum
    }
    static func text(_ value: String) -> Bool {
        !value.isEmpty && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    static func configurationText(_ value: String) -> Bool {
        bounded(value, 256) && text(value)
    }
    static func identityBounds(_ value: InventoryIdentity) -> Bool {
        fields(value).enumerated().allSatisfy { index, field in
            bounded(field, index == 0 ? 128 : index == 8 ? 1024 : 256)
        }
    }
    static func releaseBounds(_ value: ReleaseIdentity) -> Bool {
        fields(value).allSatisfy { bounded($0, 256) }
    }
    static func identityShape(_ value: InventoryIdentity) -> Bool {
        guard fields(value).allSatisfy(text), value.instanceID.utf8.allSatisfy({ byte in
            (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) ||
            (byte >= 48 && byte <= 57) || byte == 95 || byte == 46 || byte == 45
        }), value.location.hasPrefix("/"), value.location.hasSuffix(".app") else { return false }
        let components = value.location.split(separator: "/", omittingEmptySubsequences: false)
        return components.count >= 2 && components.dropFirst().allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }
    static func releaseShape(_ value: ReleaseIdentity) -> Bool {
        fields(value).allSatisfy(text) && value.artifact.utf8.count == 64 &&
            value.artifact.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func corresponds(_ release: ReleaseIdentity, _ identity: InventoryIdentity) -> Bool {
        exactFields([release.product, release.scope, release.edition, release.channel],
                    [identity.product, identity.scope, identity.edition, identity.channel])
    }
    static func snapshotRefusal(_ snapshot: InventorySnapshot) -> InventoryRefusal? {
        guard snapshot.rows.count <= 512, bounded(snapshot.principal.value, 256) else { return .bounds }
        var bytes = snapshot.principal.value.utf8.count
        // Bounds and aggregate accounting precede any shape, binding or grouping work.
        for row in snapshot.rows {
            guard identityBounds(row.identity), bounded(row.displayName, 256) else { return .bounds }
            bytes += fields(row.identity).reduce(0) { $0 + $1.utf8.count } + row.displayName.utf8.count
            switch row.update {
            case .unknown: break
            case .syntheticCurrent(let identity):
                guard identityBounds(identity) else { return .bounds }
                bytes += fields(identity).reduce(0) { $0 + $1.utf8.count }
            case .syntheticAvailable(let candidate):
                guard identityBounds(candidate.identity), releaseBounds(candidate.release) else { return .bounds }
                bytes += fields(candidate.identity).reduce(0) { $0 + $1.utf8.count }
                bytes += fields(candidate.release).reduce(0) { $0 + $1.utf8.count }
            }
            guard bytes <= 1_048_576 else { return .bounds }
        }
        for row in snapshot.rows {
            guard identityShape(row.identity), text(row.displayName) else { return .identity }
            switch row.update {
            case .unknown: break
            case .syntheticCurrent(let identity):
                guard identityShape(identity), exact(identity, row.identity) else { return .identity }
            case .syntheticAvailable(let candidate):
                guard identityShape(candidate.identity), releaseShape(candidate.release),
                      exact(candidate.identity, row.identity), corresponds(candidate.release, row.identity) else { return .identity }
            }
        }
        var ids = Set<[UInt8]>()
        var locations = Set<[UInt8]>()
        for row in snapshot.rows {
            guard ids.insert(Array(row.identity.instanceID.utf8)).inserted,
                  locations.insert(Array(row.identity.location.utf8)).inserted else { return .identity }
        }
        return nil
    }
    static func exact(_ left: InventorySnapshot, _ right: InventorySnapshot) -> Bool {
        guard exact(left.principal.value, right.principal.value), left.generation == right.generation,
              left.observedAt == right.observedAt, left.catalogue == right.catalogue,
              left.rows.count == right.rows.count else { return false }
        return zip(left.rows, right.rows).allSatisfy { a, b in
            guard exact(a.identity, b.identity), exact(a.displayName, b.displayName), a.running == b.running,
                  a.route == b.route, a.externallyManaged == b.externallyManaged else { return false }
            switch (a.update, b.update) {
            case (.unknown, .unknown): return true
            case (.syntheticCurrent(let x), .syntheticCurrent(let y)): return exact(x, y)
            case (.syntheticAvailable(let x), .syntheticAvailable(let y)):
                return exact(x.identity, y.identity) && exact(x.release, y.release)
            default: return false
            }
        }
    }
    static func copyKey(_ identity: InventoryIdentity) -> [[UInt8]] {
        [identity.product, identity.scope, identity.bundleID, identity.publisher,
         identity.edition, identity.channel, identity.architecture].map { Array($0.utf8) }
    }
}
