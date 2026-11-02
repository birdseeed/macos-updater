import Foundation
import Darwin
import ArtifactInspection
@_spi(Testing) import PatchedCore
@_spi(Testing) import PatchedOperator

// Acceptance checks for the PAT-2583 operator proof. Every write is confined to new
// disposable directories beneath this worktree's .build. No app is launched, no disk
// image is mounted by the unit gate, no network is used and no installed app or
// profile is read or changed. The only private key bytes are the deterministic
// fixture bytes in Support.swift.
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.count == 3 && arguments[0] == "--live-inspection" {
    // Explicit operator command, never run by ./scripts/verify.sh: reads one existing pinned DMG.
    exit(runLiveInspection(version: arguments[1], path: arguments[2]))
}
if arguments.count == 3 && arguments[0] == "--live-catalogue-proof" {
    // Explicit operator command, never run by ./scripts/verify.sh: verify, sign, publish and consume one approved pinned DMG.
    exit(runLiveCatalogueProof(version: arguments[1], path: arguments[2]))
}
if arguments.count == 5 && arguments[0] == "--consumer-probe" {
    // An independent consumer process: the real verifier over the physically published file.
    do {
        let envelope = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
        let verifier = CatalogueVerifier(trust: try Sample.trust(), policy: Sample.policy(), stateDirectory: arguments[3])
        let candidate = arguments[1] == "bootstrap" ? try verifier.bootstrapFreshProofNamespace(envelope: envelope, now: Sample.now)
                                                    : try verifier.verify(envelope: envelope, now: Sample.now)
        _ = try ArtifactVerifier.verify(path: arguments[4], candidate: candidate)
        print("sequence=\(candidate.sequence) origin=\(candidate.origin) freshOSValidation=\(candidate.freshOSValidation) " +
              "installationAuthorized=\(candidate.installationAuthorized) payloadSHA256=\(candidate.payloadSHA256) artifact=matched")
        exit(0)
    } catch let error as CoreFailure { print("refused=\(error.rawValue)"); exit(1) }
    catch { print("failed=\(error)"); exit(3) }
}
if arguments.count == 2 && arguments[0] == "--restart-probe" {
    // An independent operator process with no state from the first writer.
    func refusal(_ action: () throws -> Void) -> String {
        do { try action(); return "accepted" } catch let error as OperatorFailure { return error.rawValue } catch { return "failed" }
    }
    do {
        let root = URL(fileURLWithPath: arguments[1])
        let authority = try FixtureOperatorAuthority.reopenRoot(path: root.path, trust: Sample.trust())
        let receipt = try authority.fixtureReceipt(version: Sample.version, artifactPath: root.appendingPathComponent("input/" + Sample.artifactName).path)
        let rollback = refusal { _ = try authority.sign(receipt: receipt, request: Sample.request(sequence: 7), now: Sample.now, signer: Sample.signer) }
        let equal = refusal {
            _ = try authority.sign(receipt: receipt, request: Sample.request(sequence: 8, expiresAt: Sample.issued + 60), now: Sample.now, signer: Sample.signer)
        }
        let catalogue = try authority.sign(receipt: receipt, request: Sample.request(sequence: 9), now: Sample.now, signer: Sample.signer)
        let published = try authority.publish(catalogue, now: Sample.now)
        print("rollback=\(rollback) equal=\(equal) published=\(published.sequence) origin=\(published.origin) " +
              "freshOSValidation=\(published.freshOSValidation) installationAuthorized=\(published.installationAuthorized)")
        exit(0)
    } catch let error as OperatorFailure { print("refused=\(error.rawValue)"); exit(1) }
    catch { print("failed=\(error)"); exit(3) }
}
if arguments.count == 2 && arguments[0] == "--busy-probe" {
    // A second operator process while the first holds the root lock. Reopening or signing may refuse.
    do {
        let root = URL(fileURLWithPath: arguments[1])
        let authority = try FixtureOperatorAuthority.reopenRoot(path: root.path, trust: Sample.trust())
        let receipt = try authority.fixtureReceipt(version: Sample.version, artifactPath: root.appendingPathComponent("input/" + Sample.artifactName).path)
        _ = try authority.sign(receipt: receipt, request: Sample.request(), now: Sample.now, signer: Sample.signer)
        print("IMPROPER ACCEPTANCE: signed while the lock was held"); exit(2)
    } catch let error as OperatorFailure { print("refused=\(error.rawValue)"); exit(0) }
    catch { print("failed=\(error)"); exit(3) }
}

var cases: [(String, @MainActor () throws -> Void)] = []
@MainActor func check(_ name: String, _ action: @escaping @MainActor () throws -> Void) { cases.append((name, action)) }
if arguments.count == 1 && arguments[0] == "--root-creation-regressions" {
    // Explicit command: only the root creation boundary regressions, with their own count and exit code.
    registerRootCreationBoundaryChecks()
    exit(runRootCreationRegressions(cases))
}
if arguments.count == 1 && arguments[0] == "--root-lock-regressions" {
    // Explicit command: only the root lock reentrancy regressions, with their own count and exit code.
    registerRootLockReentrancyChecks()
    exit(runRootLockRegressions(cases))
}
if arguments.count == 1 && arguments[0] == "--result-chain-regressions" {
    // Explicit command: only the result chain regressions, with their own count and exit code.
    registerResultChainChecks()
    exit(runResultChainRegressions(cases))
}
registerAuthorityChecks()
registerVerificationChecks()
registerSigningChecks()
registerPublicationChecks()
registerSurfaceChecks()
registerRootCreationBoundaryChecks()
registerRootLockReentrancyChecks()
registerResultChainChecks()
var failures = 0
for (name, action) in cases {
    do { try action(); print("PASS operator: \(name)") }
    catch { failures += 1; print("FAIL operator: \(name): \(error)") }
}
print("Fixture operator acceptance: \(cases.count) cases, \(failures) failures. Fixture trust only. No production key, publication, fresh OS trust or installation authority.")
exit(failures == 0 ? 0 : 1)
