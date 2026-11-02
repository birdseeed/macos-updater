/// Pure injected attention state. A prepared route and an attempt are model
/// outcomes only; this class has no installer, OS permission or restart adapter.
public final class AttentionController {
    public let principal: SchedulingPrincipal
    public private(set) var lifecycle: AttentionLifecycle = .pending
    private var observation: AttentionObservation?
    private var highestRevision: UInt64 = 0
    private var highestSession: UInt64 = 0
    private var approval: (binding: AttentionBinding, clock: ClockSample)?
    private let attemptOwner = AttentionAttemptOwner()
    private var sequence: UInt64 = 0
    private var activeAttempt: AttentionAttempt?
    private var completedBinding: AttentionBinding?
    private var installedBoot: String?

    public init(principal: SchedulingPrincipal) { self.principal = principal }

    @discardableResult public func refresh(_ input: AttentionObservation) -> Bool {
        guard coherent(input), input.binding.observationRevision >= highestRevision,
              input.binding.sessionGeneration >= highestSession else {
            invalidatePreparation()
            observation = nil
            return false
        }
        if let old = observation {
            let changed = old.binding != input.binding || old.permission != input.permission ||
                old.helper != input.helper || !samePolicy(old.policy, input.policy)
            if changed || !startReasons(input, kind: .manual).isEmpty {
                invalidatePreparation()
            }
        }
        if let approval, !validApproval(approval, in: input) {
            invalidatePreparation()
        }
        highestRevision = input.binding.observationRevision
        highestSession = input.binding.sessionGeneration
        observation = input
        return true
    }

    public func decision(for kind: StartKind) -> AttentionDecision {
        let terminal = lifecycleReason
        if let terminal { return .blocked([terminal]) }
        guard let observation else { return .blocked([.missingEvidence]) }
        var reasons = startReasons(observation, kind: kind)
        let requirements = observation.binding.requirements
        if requirements.interaction == .required && kind != .manual {
            append(.interactiveApproval, to: &reasons)
        }
        if requirements.restart == .required &&
            (kind != .manual || !hasRestartApproval(observation)) {
            append(.restartApproval, to: &reasons)
        }
        guard reasons.isEmpty else { return .blocked(reasons) }
        return isExplicit(observation.binding) ? .explicitRoutePrepared : .unattendedPolicyEligible
    }

    @discardableResult public func approveRestart(binding: AttentionBinding) -> Bool {
        guard lifecycle == .pending, let observation, binding == observation.binding,
              binding.requirements.restart == .required,
              startReasons(observation, kind: .manual).isEmpty,
              observation.conditions.clock.isUsable else { return false }
        approval = (binding, observation.conditions.clock)
        return true
    }

    public func requestManualStart(binding: AttentionBinding) -> AttentionAttempt? {
        guard let observation, binding == observation.binding, isExplicit(binding),
              decision(for: .manual) == .explicitRoutePrepared,
              sequence < UInt64.max else { return nil }
        sequence += 1
        let attempt = AttentionAttempt(owner: attemptOwner, sequence: sequence, binding: binding)
        activeAttempt = attempt
        // Retain the boot independently of subsequent observations.
        installedBoot = observation.conditions.clock.boot
        lifecycle = .awaitingInstaller
        return attempt
    }

    @discardableResult public func recordInstallerResult(
        attempt: AttentionAttempt, result: AttentionInstallerResult,
        readback: AttentionInstalledReadback? = nil
    ) -> Bool {
        guard lifecycle == .awaitingInstaller, activeAttempt == attempt,
              attempt.owner === attemptOwner, observation?.binding == attempt.binding else { return false }
        activeAttempt = nil
        approval = nil
        guard result == .reportedSuccess, let readback,
              readback.binding == attempt.binding,
              readback.installedRelease == attempt.binding.release,
              readback.restartPending != .unknown,
              // Any disagreement with the approved restart requirement is
              // uncertain. Only the agreed pending route can finish through
              // a later distinct-boot readback.
              !(attempt.binding.requirements.restart == .required && readback.restartPending == .no),
              !(attempt.binding.requirements.restart == .notRequired && readback.restartPending == .yes) else {
            lifecycle = .recoveryRequired
            return true
        }
        completedBinding = attempt.binding
        lifecycle = readback.restartPending == .yes ? .installedRestartPending : .installed
        return true
    }

    @discardableResult public func recordPostRestart(_ readback: AttentionPostRestartReadback) -> Bool {
        guard lifecycle == .installedRestartPending, let binding = completedBinding,
              readback.binding == binding, readback.installedRelease == binding.release,
              readback.restartPending == .no, !readback.observedBoot.isEmpty,
              let installedBoot, !installedBoot.isEmpty,
              readback.observedBoot != installedBoot else { return false }
        lifecycle = .installed
        return true
    }

    @discardableResult public func cancel(binding: AttentionBinding) -> Bool {
        guard let observation, observation.binding == binding,
              lifecycle == .pending || lifecycle == .awaitingInstaller else { return false }
        approval = nil
        if lifecycle == .awaitingInstaller {
            activeAttempt = nil
            lifecycle = .recoveryRequired
        }
        return true
    }

    public var presentation: AttentionPresentation {
        guard observation != nil || lifecycle != .pending else { return .refusing }
        var reasons: [AttentionReason]
        if case .blocked(let blocked) = decision(for: .manual) { reasons = blocked }
        else { reasons = [] }
        if lifecycle == .pending, let observation,
           observation.binding.requirements.interaction == .required {
            append(.interactiveApproval, to: &reasons)
        }
        var actions: [AttentionAction] = []
        switch lifecycle {
        case .recoveryRequired: actions = [.viewRecovery, .recheck]
        case .awaitingInstaller: actions = [.cancel, .recheck]
        case .installedRestartPending, .installed: actions = [.recheck]
        case .pending:
            if reasons.contains(.permissionNeeded) || reasons.contains(.permissionDenied) ||
                reasons.contains(.permissionRevoked) { actions.append(.reviewAppManagement) }
            if let observation, startReasons(observation, kind: .manual).isEmpty {
                if observation.binding.requirements.restart == .required && !hasRestartApproval(observation) {
                    actions.append(.approveRestart)
                } else if decision(for: .manual) == .explicitRoutePrepared {
                    actions.append(observation.binding.requirements.interaction == .required ? .launchInstaller : .startUpdate)
                }
                if approval != nil { actions.append(.cancel) }
            }
            actions.append(.recheck)
        }
        return AttentionPresentation.make(lifecycle: lifecycle, reasons: reasons, actions: actions)
    }

    private var lifecycleReason: AttentionReason? {
        switch lifecycle {
        case .pending: return nil
        case .awaitingInstaller: return .installerPending
        case .installed: return .alreadyInstalled
        case .installedRestartPending: return .installedRestartPending
        case .recoveryRequired: return .recoveryRequired
        }
    }

    private func coherent(_ input: AttentionObservation) -> Bool {
        let binding = input.binding
        return !principal.value.isEmpty && binding.principal == principal &&
            input.conditions.principal == principal && input.policy.principal == principal &&
            !binding.target.isEmpty && !binding.routeID.isEmpty && binding.release.isComplete &&
            input.conditions.target == binding.target &&
            input.conditions.release == .verified(binding.release)
    }

    private func startReasons(_ input: AttentionObservation, kind: StartKind) -> [AttentionReason] {
        var reasons: [AttentionReason] = []
        switch input.permission {
        case .unknown: append(.missingEvidence, to: &reasons)
        case .notDetermined: append(.permissionNeeded, to: &reasons)
        case .denied: append(.permissionDenied, to: &reasons)
        case .revoked: append(.permissionRevoked, to: &reasons)
        case .granted: break
        }
        switch input.helper {
        case .unknown: append(.missingEvidence, to: &reasons)
        case .unavailable: append(.helperUnavailable, to: &reasons)
        case .available, .notRequired: break
        }
        if input.conditions.targetClosed != .yes {
            append(input.conditions.targetClosed == .no ? .targetRunning : .missingEvidence, to: &reasons)
        }
        let req = input.binding.requirements
        let expectedRoute: InstallationRoute = req.interaction == .required ? .interactive :
            (req.restart == .required ? .restartRequired : .unattended)
        if req.restart == .unknown || req.interaction == .unknown || input.conditions.route != expectedRoute {
            append(.missingEvidence, to: &reasons)
        }
        // Inspect the policy with the original conditions and original route.
        // Its route refusal is expected for a separate explicit manual intent;
        // it never becomes unattended eligibility or a QueueModel start.
        if case .deferred(let reason) = input.policy.decision(for: kind, conditions: input.conditions) {
            if !(reason == .route && kind == .manual && isExplicit(input.binding)) {
                append(.scheduleDeferred(reason), to: &reasons)
            }
        }
        if isExplicit(input.binding) {
            let clock = input.conditions.clock
            if !clock.isUsable || input.conditions.previousClock.map({ !clock.isConsistent(with: $0) }) == true {
                append(.missingEvidence, to: &reasons)
            }
        }
        return reasons
    }

    private func isExplicit(_ binding: AttentionBinding) -> Bool {
        binding.requirements.restart == .required || binding.requirements.interaction == .required
    }

    private func validApproval(_ approval: (binding: AttentionBinding, clock: ClockSample),
                               in input: AttentionObservation) -> Bool {
        let now = input.conditions.clock
        guard approval.binding == input.binding, now.boot == approval.clock.boot,
              now.isConsistent(with: approval.clock) else { return false }
        let elapsed = now.monotonic.subtractingReportingOverflow(approval.clock.monotonic)
        return !elapsed.overflow && elapsed.partialValue >= 0 && elapsed.partialValue < 1_800
    }

    private func hasRestartApproval(_ input: AttentionObservation) -> Bool {
        guard let approval else { return false }
        return validApproval(approval, in: input)
    }

    private func invalidatePreparation() {
        approval = nil
        if lifecycle == .awaitingInstaller {
            activeAttempt = nil
            lifecycle = .recoveryRequired
        }
    }

    private func samePolicy(_ lhs: SchedulePolicy, _ rhs: SchedulePolicy) -> Bool {
        lhs.principal == rhs.principal && lhs.automaticEnabled == rhs.automaticEnabled &&
            lhs.excludedProducts == rhs.excludedProducts && samePause(lhs.pause, rhs.pause) &&
            lhs.skippedReleases == rhs.skippedReleases
    }

    private func samePause(_ lhs: AutomaticPause?, _ rhs: AutomaticPause?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (.some(let lhs), .some(let rhs)):
            return lhs.resumeUTC == rhs.resumeUTC && lhs.displayZone == rhs.displayZone && lhs.anchor == rhs.anchor
        default: return false
        }
    }

    private func append(_ reason: AttentionReason, to reasons: inout [AttentionReason]) {
        if !reasons.contains(reason) { reasons.append(reason) }
    }
}
