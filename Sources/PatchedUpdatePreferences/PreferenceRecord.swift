import Foundation
import PatchedScheduling

/// Synthetic app key. None of these caller-supplied strings authenticates an installed app.
public struct PreferenceAppKey: Hashable, Sendable {
    public let product: String
    public let scope: String
    public let edition: String
    public let channel: String
    public init(product: String, scope: String, edition: String, channel: String) {
        self.product = product; self.scope = scope; self.edition = edition; self.channel = channel
    }
    public init(_ release: ReleaseIdentity) {
        self.init(product: release.product, scope: release.scope, edition: release.edition, channel: release.channel)
    }
}
public enum PreferenceChange: Hashable, Sendable {
    case exclusion(PreferenceAppKey, Bool)
    case skip(ReleaseIdentity)
    case undo(ReleaseIdentity)
}
public struct PreferenceMutationReceipt: Equatable, Sendable {
    public let id: String
    /// Closed, typed canonical JSON of exclusion/skip/undo; at most 4096 UTF8 bytes.
    /// Decode must validate this nested wire independently. Never executed.
    public let operation: String
    public init(id: String, operation: String) { self.id = id; self.operation = operation }
}
public struct PreferenceRecord: Equatable, Sendable {
    public static let maximumBytes = 1_048_576
    public static let maximumExclusions = 256
    public static let maximumSkips = 512
    public static let maximumMutations = 128
    public let schema: UInt64
    public let principal: SchedulingPrincipal
    public let storeScope: String
    public let revision: UInt64
    public let exclusions: Set<PreferenceAppKey>
    public let skips: Set<ReleaseIdentity>
    public let mutations: [PreferenceMutationReceipt]
    /// An unvalidated value declaration only. Only decode acceptance may establish a session record.
    @_spi(Testing) public init(schema: UInt64 = 1, principal: SchedulingPrincipal, storeScope: String,
                              revision: UInt64, exclusions: Set<PreferenceAppKey> = [],
                              skips: Set<ReleaseIdentity> = [], mutations: [PreferenceMutationReceipt] = []) {
        self.schema = schema; self.principal = principal; self.storeScope = storeScope
        self.revision = revision; self.exclusions = exclusions; self.skips = skips; self.mutations = mutations
    }
}
public enum PreferenceRefusal: String, Error, Equatable, Sendable {
    case unimplemented, defaultComposition, identity, malformed, missing, unavailable, conflict
    case uncertain, readback, staleGeneration, reentrant, limit, revisionOverflow
}
public enum PreferenceRecordCodec {
    public static func decode(_ bytes: Data, principal: SchedulingPrincipal, storeScope: String) throws -> PreferenceRecord {
        guard !bytes.isEmpty, bytes.count <= PreferenceRecord.maximumBytes else { throw PreferenceRefusal.malformed }
        do {
            let wire = try JSONDecoder().decode(PreferenceWire.self, from: bytes)
            let record = try wire.record()
            guard record.principal == principal, record.storeScope == storeScope,
                  try encode(record) == bytes else { throw PreferenceRefusal.malformed }
            return record
        } catch { throw PreferenceRefusal.malformed }
    }
    public static func encode(_ record: PreferenceRecord) throws -> Data {
        guard record.schema == 1, validPreferenceText(record.principal.value), validPreferenceText(record.storeScope),
              record.exclusions.count <= PreferenceRecord.maximumExclusions,
              record.skips.count <= PreferenceRecord.maximumSkips,
              record.mutations.count <= PreferenceRecord.maximumMutations else { throw PreferenceRefusal.malformed }
        let apps = try record.exclusions.map { try PreferenceAppWire($0).object() }
        let releases = try record.skips.map { try PreferenceReleaseWire($0).object() }
        var ids = Set<String>()
        let receipts: [[String: Any]] = try record.mutations.map {
            guard validPreferenceText($0.id), ids.insert($0.id).inserted else { throw PreferenceRefusal.malformed }
            try validatePreferenceOperation($0.operation)
            return ["id": $0.id, "operation": $0.operation]
        }
        let bytes = try preferenceJSON([
            "exclusions": try sortedPreferenceObjects(apps), "mutations": receipts,
            "principal": record.principal.value, "revision": NSNumber(value: record.revision),
            "schema": NSNumber(value: record.schema), "skips": try sortedPreferenceObjects(releases),
            "storeScope": record.storeScope
        ])
        guard bytes.count <= PreferenceRecord.maximumBytes else { throw PreferenceRefusal.limit }
        return bytes
    }
}

// Typed decoding keeps UInt64 exact without a floating-point or Boolean coercion.
// Exact canonical re-encoding also rejects unknown/duplicate fields and escapes.
private struct PreferenceWire: Decodable {
    let exclusions: [PreferenceAppWire]
    let mutations: [PreferenceReceiptWire]
    let principal: String
    let revision: UInt64
    let schema: UInt64
    let skips: [PreferenceReleaseWire]
    let storeScope: String

    func record() throws -> PreferenceRecord {
        guard exclusions.count <= PreferenceRecord.maximumExclusions,
              skips.count <= PreferenceRecord.maximumSkips,
              mutations.count <= PreferenceRecord.maximumMutations else { throw PreferenceRefusal.malformed }
        let apps = try exclusions.map { try $0.key() }
        let releases = try skips.map { try $0.identity() }
        guard Set(apps).count == apps.count, Set(releases).count == releases.count else { throw PreferenceRefusal.malformed }
        return PreferenceRecord(schema: schema, principal: SchedulingPrincipal(principal), storeScope: storeScope,
                                revision: revision, exclusions: Set(apps), skips: Set(releases),
                                mutations: mutations.map { PreferenceMutationReceipt(id: $0.id, operation: $0.operation) })
    }
}
private struct PreferenceReceiptWire: Decodable {
    let id: String
    let operation: String
}
private struct PreferenceAppWire: Decodable {
    let channel: String
    let edition: String
    let product: String
    let scope: String
    init(_ key: PreferenceAppKey) {
        channel = key.channel; edition = key.edition; product = key.product; scope = key.scope
    }
    func key() throws -> PreferenceAppKey {
        guard [channel, edition, product, scope].allSatisfy(validPreferenceText) else { throw PreferenceRefusal.malformed }
        return PreferenceAppKey(product: product, scope: scope, edition: edition, channel: channel)
    }
    func object() throws -> [String: Any] {
        _ = try key()
        return ["channel": channel, "edition": edition, "product": product, "scope": scope]
    }
}
private struct PreferenceReleaseWire: Decodable {
    let artifact: String
    let build: String
    let channel: String
    let edition: String
    let product: String
    let release: String
    let scope: String
    init(_ value: ReleaseIdentity) {
        artifact = value.artifact; build = value.build; channel = value.channel; edition = value.edition
        product = value.product; release = value.release; scope = value.scope
    }
    func identity() throws -> ReleaseIdentity {
        guard [artifact, build, channel, edition, product, release, scope].allSatisfy(validPreferenceText) else {
            throw PreferenceRefusal.malformed
        }
        return ReleaseIdentity(product: product, scope: scope, release: release, build: build,
                               edition: edition, channel: channel, artifact: artifact)
    }
    func object() throws -> [String: Any] {
        _ = try identity()
        return ["artifact": artifact, "build": build, "channel": channel, "edition": edition,
                "product": product, "release": release, "scope": scope]
    }
}
private struct PreferenceOperationWire: Decodable {
    let action: String
    let app: PreferenceAppWire?
    let excluded: Bool?
    let release: PreferenceReleaseWire?
}
private func validPreferenceText(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 256 &&
        !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
}
private func preferenceJSON(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
}
private func sortedPreferenceObjects(_ objects: [[String: Any]]) throws -> [[String: Any]] {
    let pairs = try objects.map { (try preferenceJSON($0), $0) }
    return pairs.sorted { $0.0.lexicographicallyPrecedes($1.0) }.map { $0.1 }
}
private func validatePreferenceOperation(_ operation: String) throws {
    guard !operation.isEmpty, operation.utf8.count <= 4096 else { throw PreferenceRefusal.malformed }
    let bytes = Data(operation.utf8)
    let wire = try JSONDecoder().decode(PreferenceOperationWire.self, from: bytes)
    let object: [String: Any]
    switch wire.action {
    case "exclusion":
        guard let app = wire.app, let excluded = wire.excluded, wire.release == nil else { throw PreferenceRefusal.malformed }
        object = ["action": wire.action, "app": try app.object(), "excluded": excluded]
    case "skip", "undo":
        guard let release = wire.release, wire.app == nil, wire.excluded == nil else { throw PreferenceRefusal.malformed }
        object = ["action": wire.action, "release": try release.object()]
    default: throw PreferenceRefusal.malformed
    }
    guard try preferenceJSON(object) == bytes else { throw PreferenceRefusal.malformed }
}
