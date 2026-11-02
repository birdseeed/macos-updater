import Foundation
import Combine
import PatchedDisposableProof

// Disposable native proof composition is separate from the ordinary read-only
// app. Its concrete backend requires fresh physical guest authority.
public enum InstalledAction: String, CaseIterable, Sendable {
    case update, recoverAfterStaging, recoverAfterSwap, restoreOld
    case tamperedArtifact = "tampered-artifact", truncatedArtifact = "truncated-artifact", recordedEvidence = "recorded-evidence"
    case wrongSignerTarget = "wrong-signer-target", wrongSignerStaged = "wrong-signer-staged"
    case invalidCatalogue = "invalid-catalogue", replayedCatalogue = "replayed-catalogue", openApp = "open-app"
    case stagingFailure = "staging-failure", interruptedSwap = "interrupted-swap"
}
public enum InstalledActionTrigger: Sendable { case explicitUserAction, background }
public enum InstalledActionPhase: Sendable { case unavailable, ready, running, succeeded, restored, refused, cancelled }

/// Caller selections name intent only. Paths and pins are never capabilities.
public struct InstalledActionSelection: Sendable, Equatable {
    public let profile: DisposableTargetProfile
    public let runID: String
    public let caseRoot: String
    public let artifactPath: String
    public let targetPath: String
    public let version: String
    public init(runID: String, caseRoot: String, artifactPath: String, targetPath: String, version: String, profile: DisposableTargetProfile = .legacy) {
        self.profile = profile
        self.runID = runID; self.caseRoot = caseRoot; self.artifactPath = artifactPath
        self.targetPath = targetPath; self.version = version
    }
}

/// Opaque, process-local and not serializable; this token is test-only.
/// The test-only token cannot be passed to any installed transaction or harness.
public final class DisposableInstalledActionCapability: Sendable {
    private let nonce: UUID
    private init() { nonce = UUID() }
    @_spi(Testing) public static func testDouble() -> DisposableInstalledActionCapability { .init() }
}

/// These test outputs model a child result and a separate physical readback.
/// Neither is a capability and neither can create one.
@_spi(Testing) public struct InstalledActionTestChild: Sendable {
    public let exitCode: Int32
    public let stdout: Data
    @_spi(Testing) public init(exitCode: Int32, stdout: Data) { self.exitCode = exitCode; self.stdout = stdout }
}
@_spi(Testing) public struct InstalledActionTestReadback: Sendable {
    public let runID: String
    public let targetPath: String
    public let version: String
    public let transactionID: String
    public let targetVerified: Bool
    public let oldRetainedVerified: Bool
    public let fresh: Bool
    @_spi(Testing) public init(runID: String, targetPath: String, version: String, transactionID: String,
                              targetVerified: Bool, oldRetainedVerified: Bool, fresh: Bool) {
        self.runID = runID; self.targetPath = targetPath; self.version = version; self.transactionID = transactionID
        self.targetVerified = targetVerified; self.oldRetainedVerified = oldRetainedVerified; self.fresh = fresh
    }
}
@_spi(Testing) public protocol InstalledActionTestGateway: Sendable {
    func prepare(_ selection: InstalledActionSelection) async throws -> DisposableInstalledActionCapability
    func revalidate(_ capability: DisposableInstalledActionCapability, selection: InstalledActionSelection) async throws
    func execute(_ capability: DisposableInstalledActionCapability, action: InstalledAction) async throws -> InstalledActionTestChild
    func readback(_ capability: DisposableInstalledActionCapability, action: InstalledAction) async throws -> InstalledActionTestReadback
}

@MainActor public final class InstalledActionController: ObservableObject {
    @Published public private(set) var phase: InstalledActionPhase = .unavailable
    public private(set) var selection: InstalledActionSelection?
    public var actionEnabled: Bool { (capability != nil || nativeScope != nil) && phase == .ready && !running }
    public var installedFirefoxProof: Bool { phase == .succeeded && nativeOutcome?.kind == .verifiedUpdate }
    public var productionTrust: Bool { false }
    public var isTestDouble: Bool { gateway != nil }
    private let gateway: (any InstalledActionTestGateway)?
    private let nativeGateway: NativeInstalledActionGateway?
    private var nativeScope: NativeInstalledActionScope?
    public private(set) var nativeOutcome: NativeInstalledActionOutcome?
    @Published public private(set) var refusalReason: String?
    public private(set) var evidencePath: String?
    private var capability: DisposableInstalledActionCapability?
    private var generation: UInt64 = 0
    private var running = false
    public init() { gateway = nil; nativeGateway = nil }
    @_spi(Testing) public init(gateway: any InstalledActionTestGateway) { self.gateway = gateway; nativeGateway = nil }
    private init(native: NativeInstalledActionGateway) { gateway = nil; nativeGateway = native }
    /// Creates a concrete backend, not authority. Only fresh guest validation
    /// during prepare can issue its process-local productive scope.
    public static func nativeDisposable() -> InstalledActionController { .init(native: NativeInstalledActionGateway()) }
    public func select(_ selection: InstalledActionSelection) {
        generation &+= 1; capability = nil
        nativeScope = nil; nativeOutcome = nil; refusalReason = nil; evidencePath = nil
        self.selection = selection; phase = .unavailable
        // The outstanding lease remains held until every dispatched operation returns.
    }
    public func cancel() { generation &+= 1; capability = nil; nativeScope = nil; nativeOutcome = nil; phase = .cancelled }

    public func prepare() async {
        guard !running else { return }
        if let nativeGateway { await prepareNative(nativeGateway); return }
        guard let gateway, let selection else { capability = nil; phase = .refused; return }
        let expectedGeneration = generation
        capability = nil; running = true; phase = .running
        defer { running = false }
        do {
            let prepared = try await gateway.prepare(selection)
            guard generation == expectedGeneration, self.selection == selection else { return }
            capability = prepared; phase = .ready
        } catch {
            if generation == expectedGeneration { capability = nil; phase = .refused }
        }
    }

    public func request(_ action: InstalledAction, trigger: InstalledActionTrigger) async {
        guard !running else { return }
        if let nativeGateway { await requestNative(action, trigger: trigger, gateway: nativeGateway); return }
        guard case .explicitUserAction = trigger, let gateway, let capability, let selection, phase == .ready else {
            self.capability = nil; phase = .refused; return
        }
        let expectedGeneration = generation
        running = true; phase = .running
        // Consume the token even on failure. A later action needs fresh preparation.
        self.capability = nil
        defer { running = false }
        do {
            try await gateway.revalidate(capability, selection: selection)
            guard generation == expectedGeneration, self.selection == selection else { return }
            let result = try await gateway.execute(capability, action: action)
            let transaction = try InstalledChildHeader.validate(result, selection: selection, action: action)
            // Even after cancellation, retain the lease through the physical readback.
            // Cancelling display state cannot turn mutation completion into verified success.
            let physical = try await gateway.readback(capability, action: action)
            guard physical.runID == selection.runID, physical.targetPath == selection.targetPath,
                  physical.transactionID == transaction,
                  physical.version == (action == .update ? selection.version : "157.0"),
                  physical.targetVerified, physical.oldRetainedVerified, physical.fresh else {
                throw InstalledControllerFailure.refused
            }
            guard generation == expectedGeneration, self.selection == selection else { return }
            phase = action == .update ? .succeeded : .restored
        } catch {
            if generation == expectedGeneration { phase = .refused }
        }
    }
    private func prepareNative(_ gateway: NativeInstalledActionGateway) async {
        guard let selection else { phase = .refused; refusalReason = "missingSelection"; return }
        let expectedGeneration = generation
        running = true; phase = .running; nativeScope = nil; nativeOutcome = nil; refusalReason = nil; evidencePath = nil
        defer { running = false }
        do {
            let scope = try await gateway.prepare(selection)
            guard generation == expectedGeneration, self.selection == selection else { return }
            nativeScope = scope; phase = .ready
        } catch { if generation == expectedGeneration { nativeFailure(error) } }
    }
    private func requestNative(_ action: InstalledAction, trigger: InstalledActionTrigger, gateway: NativeInstalledActionGateway) async {
        nativeOutcome = nil; evidencePath = nil; refusalReason = nil
        guard case .explicitUserAction = trigger, let scope = nativeScope, let selection, phase == .ready else {
            nativeScope = nil; phase = .refused; refusalReason = "explicitPreparedActionRequired"; return
        }
        let expectedGeneration = generation
        nativeScope = nil; running = true; phase = .running
        defer { running = false }
        do {
            try await scope.revalidate()
            guard generation == expectedGeneration, self.selection == selection else { return }
            let outcome = try await gateway.execute(scope, action: action)
            guard generation == expectedGeneration, self.selection == selection else { return }
            nativeOutcome = outcome; evidencePath = outcome.evidencePath
            switch outcome.kind {
            case .verifiedUpdate: phase = .succeeded
            case .verifiedRestored: phase = .restored
            case .verifiedRefusal, .needsRecovery: phase = .refused; refusalReason = outcome.reason
            }
        } catch { if generation == expectedGeneration { nativeFailure(error) } }
    }
    private func nativeFailure(_ error: Error) {
        nativeScope = nil; nativeOutcome = nil; phase = .refused
        if let refusal = error as? NativeInstalledActionRefusal { refusalReason = refusal.reason; evidencePath = refusal.evidencePath }
        else { refusalReason = (error as? DisposableFailure)?.rawValue ?? "nativeOperationFailed" }
    }
}

private enum InstalledControllerFailure: Error { case refused }

/// Closed, flat test-child header. Parsing is only evidence comparison after the
/// gateway has a test token; no decoded value can issue or arm a capability.
/// The concrete native backend separately validates the full durable report.
private enum InstalledChildHeader {
    static func validate(_ child: InstalledActionTestChild, selection: InstalledActionSelection,
                         action: InstalledAction) throws -> String {
        guard child.exitCode == 0 else { throw InstalledControllerFailure.refused }
        let fields = try FlatHeader.parse(child.stdout)
        let keys: Set<String> = ["action", "runID", "caseRoot", "targetPath", "transactionID", "state", "recoveryAction",
                                "installedFirefoxProof", "freshOSValidation", "ownedMountsAbsent", "productionTrust", "globalProductReadiness"]
        let recovery = action == .recoverAfterStaging ? "oldAlreadyInPlace" : (action == .update ? "none" : "restoredOldBySwap")
        guard Set(fields.keys) == keys, fields["action"] == .text(action.rawValue),
              fields["runID"] == .text(selection.runID), fields["caseRoot"] == .text(selection.caseRoot),
              fields["targetPath"] == .text(selection.targetPath),
              fields["state"] == .text(action == .update ? "committed" : "rolledBack"),
              fields["recoveryAction"] == .text(recovery),
              fields["installedFirefoxProof"] == .flag(action == .update),
              fields["freshOSValidation"] == .flag(true), fields["ownedMountsAbsent"] == .flag(true),
              fields["productionTrust"] == .flag(false), fields["globalProductReadiness"] == .flag(false),
              case let .text(transaction)? = fields["transactionID"],
              UUID(uuidString: transaction)?.uuidString == transaction else { throw InstalledControllerFailure.refused }
        return transaction
    }
}

private enum HeaderValue: Equatable { case text(String), flag(Bool) }

/// A small bounded JSON object reader rejects duplicate keys, trailing output,
/// numbers standing in for booleans, nesting and every unsupported value type.
/// Foundation handles JSON string escapes after token boundaries are established.
private struct FlatHeader {
    let bytes: [UInt8]
    var position = 0
    static func parse(_ data: Data) throws -> [String: HeaderValue] {
        guard !data.isEmpty, data.count <= 65_536, String(data: data, encoding: .utf8) != nil else {
            throw InstalledControllerFailure.refused
        }
        var reader = FlatHeader(bytes: Array(data))
        return try reader.object()
    }
    mutating func whitespace() {
        while position < bytes.count && [UInt8(32), 9, 10, 13].contains(bytes[position]) { position += 1 }
    }
    mutating func take(_ byte: UInt8) throws {
        whitespace()
        guard position < bytes.count, bytes[position] == byte else { throw InstalledControllerFailure.refused }
        position += 1
    }
    mutating func text() throws -> String {
        whitespace(); let start = position
        try take(34)
        var escaped = false
        while position < bytes.count {
            let byte = bytes[position]; position += 1
            if escaped { escaped = false; continue }
            if byte == 92 { escaped = true; continue }
            if byte == 34 {
                let data = Data(bytes[start..<position])
                guard let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String else {
                    throw InstalledControllerFailure.refused
                }
                return value
            }
            guard byte >= 32 else { throw InstalledControllerFailure.refused }
        }
        throw InstalledControllerFailure.refused
    }
    mutating func value() throws -> HeaderValue {
        whitespace()
        guard position < bytes.count else { throw InstalledControllerFailure.refused }
        if bytes[position] == 34 { return .text(try text()) }
        for (literal, flag) in [(Array("true".utf8), true), (Array("false".utf8), false)] {
            if bytes[position...].starts(with: literal) { position += literal.count; return .flag(flag) }
        }
        throw InstalledControllerFailure.refused
    }
    mutating func object() throws -> [String: HeaderValue] {
        try take(123); var fields: [String: HeaderValue] = [:]
        while true {
            whitespace()
            guard fields.count < 32 else { throw InstalledControllerFailure.refused }
            let key = try text()
            guard fields[key] == nil else { throw InstalledControllerFailure.refused }
            try take(58); fields[key] = try value(); whitespace()
            guard position < bytes.count else { throw InstalledControllerFailure.refused }
            if bytes[position] == 125 { position += 1; break }
            try take(44)
        }
        whitespace()
        guard position == bytes.count else { throw InstalledControllerFailure.refused }
        return fields
    }
}
