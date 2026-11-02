import Foundation
import CryptoKit
@_spi(Testing) import PatchedActivation

// Check-target only. Public synthetic proof evidence, never current ledger state.
struct PreparedFixtureDiagnostic: Codable {
    let schema: Int
    let scope: String
    let os: String
    let architecture: String
    let sessionID: Data
    let operation: UInt8
    let body: Data
    let pathActivationID: Data?
    let now: UInt64
    let expectedAccountRevision: UInt64
    let newActivationID: Data?
    let grant: [UInt64]?
    let auditSucceeds: Bool
    let action: Data
    let accountID: Data
    let activationID: Data?
    let publicKey: Data
    let nonce: Data
    let expiresAt: UInt64
    let referenceMessage: Data
    let signature: Data?
    let challengeID: Data?
    let parse: String
    let productionMessage: String
    let independentSignature: String
    let productionProof: String
    let apply: String
    let currentState: String
    let modelReplay: String
}
enum FixtureDiagnosticError: Error { case unavailable }
@MainActor enum FixtureDiagnostics {
    static let maximumOutputBytes = 65_536
    private static var output: String?
    static func reset() { output = nil }
    private static func unavailable(_ reason: String) -> String {
        "{\"diagnostic\":\"unavailable\",\"reason\":\"" + reason + "\"}"
    }
    private static func identifier(_ value: String) -> Bool {
        value.utf8.count == 32 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func capture(attempt: ModelAttempt, action: Data, context: PossessionContext,
                        signature: Data?, challengeID: String?) throws {
        // Clear first: even a failed capture must replace the preceding prepared fixture.
        output = unavailable("capture-failure")
        let texts = [attempt.sessionID, attempt.pathActivationID ?? "", attempt.newActivationID ?? "",
                     context.accountID, context.activationID ?? "", challengeID ?? ""]
        guard attempt.body.count <= 16_384, action.count <= 1_024,
              context.publicKey.count <= 1_024, context.nonce.count <= 1_024,
              (signature?.count ?? 0) <= 8_192, texts.allSatisfy({ $0.utf8.count <= 1_024 }) else {
            output = unavailable("input-bound"); throw FixtureDiagnosticError.unavailable
        }
        // referenceMessage uses the independent producer's intentionally strict unhex helper.
        // Validate its preconditions here rather than allowing malformed diagnostics to trap.
        guard identifier(context.accountID), context.activationID.map(identifier) ?? true,
              context.operation == attempt.operation else {
            output = unavailable("input-shape"); throw FixtureDiagnosticError.unavailable
        }
        let message = referenceMessage(action, context)
        let parse: String
        do { _ = try DeviceRequest.parse(attempt.body, operation: attempt.operation,
                                        pathActivationID: attempt.pathActivationID); parse = "accepted" }
        catch { parse = "refused" }
        let productionMessage: String
        do { productionMessage = try PossessionProof.message(actionBytes: action, context: context) == message
                ? "matches-reference" : "differs-reference" }
        catch { productionMessage = "refused" }
        var independentSignature = "not-applicable", productionProof = "not-applicable"
        if let signature {
            do {
                let key = try P256.Signing.PublicKey(x963Representation: context.publicKey)
                let parsed = try P256.Signing.ECDSASignature(rawRepresentation: signature)
                independentSignature = key.isValidSignature(parsed, for: message) ? "accepted" : "refused"
            } catch { independentSignature = "refused" }
            do { try PossessionProof.verify(actionBytes: action, signature: signature, context: context,
                                            now: attempt.now); productionProof = "accepted" }
            catch { productionProof = "refused" }
        }
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "other"
        #endif
        let value = PreparedFixtureDiagnostic(schema: 1, scope: "last-prepared-fixture",
            os: ProcessInfo.processInfo.operatingSystemVersionString, architecture: architecture,
            sessionID: Data(attempt.sessionID.utf8), operation: attempt.operation.rawValue, body: attempt.body,
            pathActivationID: attempt.pathActivationID.map { Data($0.utf8) }, now: attempt.now,
            expectedAccountRevision: attempt.expectedAccountRevision,
            newActivationID: attempt.newActivationID.map { Data($0.utf8) },
            grant: attempt.grantingWindow.map { [$0.issuedAt, $0.permittedUntil, $0.hardEnd] },
            auditSucceeds: attempt.auditSucceeds, action: action, accountID: Data(context.accountID.utf8),
            activationID: context.activationID.map { Data($0.utf8) }, publicKey: context.publicKey,
            nonce: context.nonce, expiresAt: context.expiresAt, referenceMessage: message,
            signature: signature, challengeID: challengeID.map { Data($0.utf8) }, parse: parse,
            productionMessage: productionMessage, independentSignature: independentSignature,
            productionProof: productionProof, apply: "not-observed", currentState: "not-captured",
            modelReplay: "not-performed")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(value)
        guard bytes.count <= maximumOutputBytes else {
            output = unavailable("output-bound"); throw FixtureDiagnosticError.unavailable
        }
        output = String(decoding: bytes, as: UTF8.self)
    }
    static func render() throws -> String? { output }
}
// The main harness owns the original failure and process exit. Reporter errors never replace it.
@MainActor func runFixtureDiagnosticCase(_ body: () throws -> Void,
    emit: (String) -> Void = { print($0) },
    report: () throws -> String? = { try FixtureDiagnostics.render() }) throws {
    do { try body() }
    catch {
        let original = error
        do {
            if let text = try report() {
                emit(text.utf8.count <= FixtureDiagnostics.maximumOutputBytes ? text :
                     "{\"diagnostic\":\"unavailable\",\"reason\":\"output-bound\"}")
            }
        }
        catch { emit("{\"diagnostic\":\"unavailable\",\"reason\":\"reporter-failure\"}") }
        throw original
    }
}
