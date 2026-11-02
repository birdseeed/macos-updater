import Foundation

/// Process-local guest authority. The private actor owns all retained physical
/// bindings and the one-use lease. No caller supplies observations or a runner.
public final class NativeInstalledActionScope: Sendable {
    private let session: NativeInstalledSession
    private init(_ bindings: sending NativeInstalledBindings) { session = NativeInstalledSession(bindings) }
    /// Selection is intent only; independent physical observation comes first.
    public static func open(runID: String, caseRoot: String, profile: DisposableTargetProfile) throws -> NativeInstalledActionScope {
        _ = try GuestGuard.observe(profile: profile) // Must precede argument/path access, even for malformed inputs.
        let bindings = try NativeInstalledBindings(runID: runID, caseRoot: caseRoot, profile: profile)
        do { try bindings.validatePreparation() }
        catch { throw NativeInstalledActionRefusal(error, evidencePath: try? bindings.recordRefusal(error)) }
        return NativeInstalledActionScope(bindings)
    }
    public static func open(runID: String, caseRoot: String) throws -> NativeInstalledActionScope {
        try open(runID: runID, caseRoot: caseRoot, profile: .legacy)
    }
    public func revalidate() async throws { try await session.revalidate() }
    public func execute(action: DisposableAction) async throws -> NativeInstalledActionOutcome { try await session.execute(action) }
    /// The future output is fixed executable/argv selected by existing scoped
    /// DisposableAction rules. It cannot execute or call GuestRuntime directly.
    public func childCommand(action: DisposableAction) async throws -> NativeInstalledChildCommand { try await session.command(action) }
}

public struct NativeInstalledChildCommand: Sendable {
    public let executable: String
    public let arguments: [String]
    internal init(executable: String, arguments: [String]) {
        self.executable = executable; self.arguments = arguments
    }
}

/// Output-only result, never a decoder or issuer. The internal constructor is
/// reached only after the productive scope's physical completion/refusal checks.
public struct NativeInstalledActionOutcome: Sendable {
    public enum Kind: String, Sendable { case verifiedUpdate, verifiedRestored, verifiedRefusal, needsRecovery }
    public let kind: Kind
    public let reason: String
    public let evidencePath: String
    public let transactionID: String?
    public let installedFirefoxProof: Bool
    public let productionTrust = false
    internal init(kind: Kind, reason: String, evidencePath: String, transactionID: String?) {
        self.kind = kind; self.reason = reason; self.evidencePath = evidencePath; self.transactionID = transactionID
        installedFirefoxProof = kind == .verifiedUpdate
    }
}
public struct NativeInstalledActionRefusal: Error, Sendable {
    public let reason: String
    public let evidencePath: String?
    internal init(_ error: Error, evidencePath: String? = nil) {
        reason = (error as? DisposableFailure)?.rawValue ?? "nativeOperationFailed"; self.evidencePath = evidencePath
    }
}
private actor NativeInstalledSession {
    let bindings: NativeInstalledBindings
    var consumed = false
    init(_ bindings: sending NativeInstalledBindings) { self.bindings = bindings }
    func revalidate() throws { guard !consumed else { throw DisposableFailure.notAuthorized }; try bindings.revalidate() }
    func command(_ action: DisposableAction) throws -> NativeInstalledChildCommand {
        guard !consumed else { throw DisposableFailure.notAuthorized }; return try bindings.command(action)
    }
    func execute(_ action: DisposableAction) throws -> NativeInstalledActionOutcome {
        guard !consumed else { throw DisposableFailure.notAuthorized }; consumed = true
        defer { bindings.nativeLock = nil }
        do { return try bindings.execute(action) }
        catch { throw NativeInstalledActionRefusal(error, evidencePath: try? bindings.recordRefusal(error)) }
    }
}
