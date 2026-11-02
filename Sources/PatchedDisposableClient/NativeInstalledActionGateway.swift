import Foundation
import PatchedDisposableProof

/// Concrete backend only; there is no public injected runner, receipt, report,
/// verified boolean, observation or capability constructor.
actor NativeInstalledActionGateway {
    func prepare(_ selection: InstalledActionSelection) async throws -> NativeInstalledActionScope {
        let scope = try await Task.detached { try NativeInstalledActionScope.open(runID: selection.runID, caseRoot: selection.caseRoot, profile: selection.profile) }.value
        guard selection.targetPath == selection.profile.runParent + "/" + selection.runID + "/Cases/" + selection.caseRoot + "/Applications/Firefox.app",
              selection.artifactPath == selection.profile.runParent + "/" + selection.runID + "/Incoming/Firefox 157.0.1.dmg",
              selection.version == "157.0.1" else { throw DisposableFailure.notAuthorized }
        return scope
    }
    func execute(_ scope: NativeInstalledActionScope, action: InstalledAction) async throws -> NativeInstalledActionOutcome {
        return try await scope.execute(action: action.disposableAction)
    }
}
extension InstalledAction {
    var disposableAction: DisposableAction {
        switch self {
        case .recoverAfterStaging: return .recoverAfterStaging
        case .recoverAfterSwap: return .recoverAfterSwap
        case .restoreOld: return .restoreOld
        default: return DisposableAction(rawValue: rawValue)!
        }
    }
    public var proofActionName: String { disposableAction.rawValue }
    public static func proofAction(named raw: String) -> InstalledAction? {
        Self.allCases.first { $0.disposableAction.rawValue == raw }
    }
}
