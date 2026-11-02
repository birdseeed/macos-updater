import Foundation
import SwiftUI
@_spi(Testing) import PatchedLicenceSupport

public enum LicenceSupportUIState: String, Sendable { case idle, readOnly, confirmation, requested, unknown, failed, confirmed }
public struct LicenceSupportRow: Equatable, Sendable {
    public let label: String
    public let value: String
    public init(label: String, value: String) { self.label = label; self.value = value }
}
/// Synthetic readback only. These caller-supplied values establish no provider or human authority.
@_spi(Testing) public struct LicenceSupportFixtureReadback {
    public enum Status { case pending, confirmed, failed, unknown }
    public let accountID: String
    public let action: SupportAction
    public let targetID: String
    public let descriptorDigest: String
    public let descriptorBytes: Data
    public let observedAt: UInt64
    public let accountRevision: UInt64
    public let entitlementRevision: UInt64
    public let targetRevision: UInt64
    public let status: Status
    public init(accountID: String, action: SupportAction, targetID: String, descriptorDigest: String, descriptorBytes: Data,
                observedAt: UInt64, accountRevision: UInt64, entitlementRevision: UInt64, targetRevision: UInt64, status: Status) {
        self.accountID = accountID; self.action = action; self.targetID = targetID
        self.descriptorDigest = descriptorDigest; self.descriptorBytes = descriptorBytes
        self.observedAt = observedAt; self.accountRevision = accountRevision
        self.entitlementRevision = entitlementRevision; self.targetRevision = targetRevision; self.status = status
    }
}
/// Standalone synthetic preview. Ordinary construction has no configurable transport or authority.
@MainActor public final class LicenceSupportController: ObservableObject {
    @Published public private(set) var state: LicenceSupportUIState = .idle
    @Published public private(set) var rows: [LicenceSupportRow] = []
    @Published public private(set) var consequences: [String] = []
    public private(set) var displayedDescriptorBytes: Data?
    public private(set) var displayedDigest: String?
    public var canConfirm: Bool {
        guard state == .confirmation, let prepared, displayGeneration == generation else { return false }
        return matches(prepared) && displayedDescriptorBytes == prepared.descriptorBytes && displayedDigest == prepared.digest
    }
    public var recoveryAvailable: Bool { false }

    private let client: any SupportClient
    private var context: SupportFixtureContext?
    private var now: UInt64 = 0
    private let readback: (SupportConfirmation) throws -> LicenceSupportFixtureReadback?
    private var accountID: String?
    private var prepared: SupportConfirmation?
    // UUIDs avoid any wraparound that could make an old display current again.
    private var generation = UUID()
    private var displayGeneration: UUID?
    private struct DispatchKey: Hashable { let requestID: String; let digest: String }
    // Keep dispatched identities for the controller lifetime, including failed/ambiguous results.
    private var dispatched: [DispatchKey: LicenceSupportUIState] = [:]
    private var dispatchedBindings: [DispatchKey: SupportConfirmation] = [:]

    public init() {
        client = RefusingSupportClient(); readback = { _ in nil }
    }
    @_spi(Testing) public init(client: any SupportClient, context: SupportFixtureContext, now: UInt64,
        readback: @escaping (SupportConfirmation) throws -> LicenceSupportFixtureReadback? = { _ in nil }) {
        self.client = client; self.context = context; self.now = now; self.readback = readback
    }
    @_spi(Testing) public func update(context: SupportFixtureContext, now: UInt64) {
        invalidate(); self.context = context; self.now = now
        rows = []; state = .failed
    }

    public func lookup(accountID: String) {
        invalidate(); self.accountID = nil; rows = []
        let operation = generation
        guard let context, context.kind == "operatorFixture", context.accountID == accountID,
              Self.hex(context.operatorID, length: 32), Self.hex(context.sessionID, length: 32),
              context.sessionID == context.preparedSessionID else { state = .failed; return }
        do {
            let value = try client.lookup(accountID: accountID)
            guard generation == operation else { return }
            guard let safe = safeRows(value, accountID: accountID) else { state = .failed; return }
            self.accountID = accountID; rows = safe; state = .readOnly
        } catch {
            guard generation == operation else { return }
            state = .failed
        }
    }

    public func prepare(action: SupportAction) {
        invalidate()
        guard let context, let accountID, accountID == context.accountID,
              action != .changeAccountEmail else { rows = []; state = .failed; return }
        let key = DispatchKey(requestID: context.requestID, digest: context.digest)
        if let previous = dispatched[key] {
            guard let binding = dispatchedBindings[key], binding.action == action, matches(binding) else {
                rows = []; state = .failed; return
            }
            state = previous; return
        }
        let operation = generation
        do {
            let candidate = try client.prepare(action: action, accountID: accountID)
            guard generation == operation else { return }
            guard candidate.action == action, matches(candidate) else { rows = []; state = .failed; return }
            // Revalidate exact descriptor bytes against this clock; do not trust a prior parse's time.
            let c = try SupportConfirmation.parse(candidate.descriptorBytes, expectedDigest: candidate.digest,
                                                  operatorID: context.operatorID, now: now)
            let presentation = try SupportPresentation.confirmation(c)
            guard let safe = safeRows(presentation, accountID: accountID) else { rows = []; state = .failed; return }
            rows = safe + [LicenceSupportRow(label: "descriptorDigest", value: c.digest)]
            consequences = presentation.consequenceWords
            prepared = c; displayedDescriptorBytes = c.descriptorBytes; displayedDigest = c.digest
            displayGeneration = operation; state = .confirmation
        } catch {
            guard generation == operation else { return }
            rows = []; state = .failed
        }
    }

    public func confirm(descriptorBytes: Data, digest: String) {
        guard canConfirm, let c = prepared,
              descriptorBytes == displayedDescriptorBytes, digest == displayedDigest else { return }
        let key = DispatchKey(requestID: c.requestID, digest: c.digest)
        guard dispatched[key] == nil else { return }
        // Consume the display and record the attempt BEFORE calling any injected code.
        invalidate(); let operation = generation
        dispatchedBindings[key] = c
        dispatched[key] = .unknown; state = .unknown
        var committed = false
        do {
            let outcome = try client.commit(requestID: c.requestID, digest: c.digest)
            guard generation == operation else { finish(.unknown, key: key, clearRows: true); return }
            guard outcome == .committed else { finish(.failed, key: key); return }
            committed = true
            let fresh = try client.lookup(accountID: c.account.accountID)
            guard generation == operation else { finish(.unknown, key: key, clearRows: true); return }
            guard let safe = safeRows(fresh, accountID: c.account.accountID) else {
                finish(.unknown, key: key, clearRows: true); return
            }
            rows = safe
            switch c.action {
            case .reconcileProviderState, .initiateCancellation, .initiateRefund:
                // A committed intent is only requested. This optional readback is synthetic,
                // separately supplied and never a production provider verification adapter.
                let result = try readback(c)
                guard generation == operation, matches(c) else {
                    finish(.unknown, key: key, clearRows: true); return
                }
                guard let result else { finish(.requested, key: key); return }
                guard readbackMatches(result, c) else { finish(.unknown, key: key); return }
                let status: LicenceSupportUIState = switch result.status {
                case .pending: .requested
                case .confirmed: .confirmed
                case .failed: .failed
                case .unknown: .unknown
                }
                finish(status, key: key)
            case .deactivateActivation, .resendSignInCode:
                finish(.confirmed, key: key)
            case .changeAccountEmail:
                finish(.failed, key: key)
            }
        } catch {
            guard generation == operation else { finish(.unknown, key: key, clearRows: true); return }
            // A definite model refusal is failed; untyped errors cannot establish non-delivery.
            let status: LicenceSupportUIState
            if !committed, let error = error as? SupportError, error != .unknownOutcome { status = .failed }
            else { status = .unknown }
            // Once commit succeeds, ANY later refresh/readback failure is ambiguous.
            finish(status, key: key, clearRows: committed)
        }
    }

    private func invalidate() {
        generation = UUID(); prepared = nil; displayGeneration = nil
        displayedDescriptorBytes = nil; displayedDigest = nil; consequences = []
    }
    private func finish(_ state: LicenceSupportUIState, key: DispatchKey, clearRows: Bool = false) {
        invalidate(); if clearRows { rows = []; accountID = nil }
        dispatched[key] = state; self.state = state
    }
    private func matches(_ c: SupportConfirmation) -> Bool {
        guard let x = context, c.action != .changeAccountEmail,
              x.kind == "operatorFixture", Self.hex(x.sessionID, length: 32),
              x.sessionID == x.preparedSessionID, x.operatorID == c.operatorID,
              x.accountID == c.account.accountID, x.accountRevision == c.account.accountRevision,
              x.entitlementRevision == c.account.entitlementRevision,
              x.requestID == c.requestID, x.digest == c.digest,
              now <= 9_007_199_254_740_991, c.preparedAt <= now, now < c.expiresAt else { return false }
        let target = Self.targetBinding(c)
        return x.targetID == target.id && x.targetRevision == target.revision
        // x.humanConfirmed is deliberately ignored: only the explicit post-display call confirms.
    }
    private static func targetBinding(_ c: SupportConfirmation) -> (id: String, revision: UInt64) {
        switch c.target {
        case .account(let a): return (a.accountID, a.accountRevision)
        case .activation(let a): return (a.activationID, a.activationRevision)
        case .provider(let p): return (p.subscriptionID, p.subscriptionRevision)
        case .recovery(let r): return (r.caseID, r.account.accountRevision)
        }
    }
    private func readbackMatches(_ value: LicenceSupportFixtureReadback, _ c: SupportConfirmation) -> Bool {
        let target = Self.targetBinding(c)
        return value.accountID == c.account.accountID && value.action == c.action && value.targetID == target.id &&
            value.descriptorDigest == c.digest && value.descriptorBytes == c.descriptorBytes && value.observedAt == now &&
            value.accountRevision == c.account.accountRevision && value.entitlementRevision == c.account.entitlementRevision &&
            value.targetRevision == target.revision
    }
    private static func hex(_ value: String, length: Int) -> Bool {
        value.utf8.count == length && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static let visiblePaths: Set<String> = [
        "requestID", "operatorID", "action", "accountID", "accountRevision", "entitlementRevision", "maskedEmail",
        "preparedAt", "expiresAt", "target.activationID", "target.slot", "target.activationRevision", "target.createdAt",
        "target.lastRefreshAt", "target.cachedLease.state", "target.cachedLease.issuedAt", "target.cachedLease.permittedUntil",
        "target.cachedLease.hardEnd", "target.maxGrantPermittedUntil", "target.subscriptionID", "target.subscriptionRevision",
        "target.currentPeriodStart", "target.currentPeriodEnd", "target.paidThrough", "target.transactionID", "target.periodStart", "target.periodEnd"
    ]
    private func safeRows(_ value: SupportPresentation, accountID: String) -> [LicenceSupportRow]? {
        guard let context, value.fields.count <= 128,
              value.fields.filter({ $0.path == "accountID" }).map(\.text) == [accountID],
              value.fields.filter({ $0.path == "operatorID" }).map(\.text) == [context.operatorID] else { return nil }
        let actions = value.fields.filter { $0.path == "action" }.map(\.text)
        guard actions.count == 1, let action = SupportAction(rawValue: actions[0]) else { return nil }
        let targetPath: String
        switch action {
        case .deactivateActivation: targetPath = "target.activationID"
        case .resendSignInCode: targetPath = "accountID"
        case .reconcileProviderState, .initiateCancellation, .initiateRefund: targetPath = "target.subscriptionID"
        case .changeAccountEmail: return nil
        }
        guard value.fields.filter({ $0.path == targetPath }).map(\.text) == [context.targetID] else { return nil }
        let fields = value.fields.filter { Self.visiblePaths.contains($0.path) }
        guard Set(fields.map(\.path)).count == fields.count,
              fields.allSatisfy({ $0.text.utf8.count <= 254 && $0.text.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value <= 126 } })
        else { return nil }
        return fields.map { LicenceSupportRow(label: $0.path, value: $0.text) }
    }
}
