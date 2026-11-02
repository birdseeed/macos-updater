import PatchedScheduling

@MainActor func registerBoundaryChecks() {
    check("unknown requirements and inconsistent route never gain unattended eligibility") {
        for req in [requirements(.unknown), requirements(.notRequired, .unknown), AttentionRequirements()] {
            let value = try controller(observation(binding(req)))
            for kind: StartKind in [.manual, .updateAll, .automatic, .loginWindow] {
                try expect(isBlocked(value.decision(for: kind)), "unknown installer requirement refuses")
            }
            try expect(hasReason(value, .missingEvidence), "missing requirement reason")
        }
        var mismatch = observation(); mismatch.conditions.route = .interactive
        let value = try controller(mismatch)
        try expect(isBlocked(value.decision(for: .manual)), "route and requirements must agree")
    }
    check("current original scheduling controls remain effective inside attention controller") {
        var skipped = observation(); skipped.policy.skip(release())
        let skippedValue = try controller(skipped)
        try expect(isBlocked(skippedValue.decision(for: .manual)), "skip preserved")
        try expect(hasReason(skippedValue, .scheduleDeferred(.skipped)), "original reason retained")
        var off = observation(); off.policy.automaticEnabled = false
        let offValue = try controller(off)
        try expect(offValue.decision(for: .manual) == .unattendedPolicyEligible, "manual independent of opt-out")
        try expect(isBlocked(offValue.decision(for: .automatic)), "automatic opt-out preserved")
        var paused = observation()
        paused.policy.pause = AutomaticPause(resumeUTC: 200, displayZone: "Europe/Isle_of_Man", anchor: clock())
        let pausedValue = try controller(paused)
        try expect(isBlocked(pausedValue.decision(for: .loginWindow)), "pause retained")
        var excluded = observation(); excluded.policy.excludedProducts = [release().product]
        let excludedValue = try controller(excluded)
        try expect(isBlocked(excludedValue.decision(for: .automatic)), "exclusion retained")
        var unsafe = observation(); unsafe.conditions.eligibility = .unknown
        let unsafeValue = try controller(unsafe)
        try expect(isBlocked(unsafeValue.decision(for: .manual)), "missing independent eligibility refuses")
    }
    check("wrong principals and disagreement between binding and action-time input refuse") {
        var value = AttentionController(principal: owner)
        try expect(!value.refresh(observation(binding(principal: foreign))), "cross-principal refresh")
        for field in 0..<4 {
            var input = observation()
            switch field {
            case 0: input.conditions.principal = foreign
            case 1: input.conditions.target = "other"
            case 2: input.conditions.release = .verified(release("3"))
            default: input.policy = SchedulePolicy(principal: foreign, automaticEnabled: true)
            }
            _ = value.refresh(input)
            try expect(isBlocked(value.decision(for: .manual)), "inconsistent input refuses")
        }
    }
    check("revision and session advance accept fresh input while rollback cannot revive old consent") {
        let first = binding(requirements(.required), revision: 1, session: 1)
        let advanced = binding(requirements(.required), revision: 2, session: 2)
        var value = try controller(observation(first))
        try expect(value.approveRestart(binding: first), "first approval")
        try expect(value.refresh(observation(advanced)), "bound monotonic advance positive")
        try expect(hasReason(value, .restartApproval), "advance needs new consent")
        try expect(value.approveRestart(binding: advanced), "new context may approve")
        for old in [first, binding(requirements(.required), revision: 1, session: 2),
                    binding(requirements(.required), revision: 2, session: 1)] {
            try expect(!value.refresh(observation(old)), "revision or session rollback refuses")
            try expect(isBlocked(value.decision(for: .manual)), "rollback cannot preserve old eligible display")
            try expect(!value.approveRestart(binding: old), "rolled-back context cannot approve")
            try expect(value.refresh(observation(advanced)), "fresh current context can be restored")
            try expect(hasReason(value, .restartApproval), "refusal invalidates prior approval")
            try expect(value.approveRestart(binding: advanced), "explicit current approval restores preparation")
        }
    }
    check("affected attention item defers while independent safe queue item proceeds") {
        let affected = try controller(observation(permission: .denied))
        try expect(isBlocked(affected.decision(for: .updateAll)), "affected selection filtered")
        let safeBinding = binding(target: "target-two")
        let safeInput = observation(safeBinding)
        let safe = try controller(safeInput)
        try expect(safe.decision(for: .updateAll) == .unattendedPolicyEligible, "independent positive")
        var queue = QueueModel(principal: owner, queueID: "attention-batch")
        try expect(queue.enqueue(QueueEntry(id: "affected", target: "target-one", release: release()), principal: owner), "affected remains queued")
        try expect(queue.enqueue(QueueEntry(id: "safe", target: "target-two", release: release()), principal: owner), "independent queued")
        let result = queue.start(id: "safe", requestID: "safe-one", principal: owner, kind: .updateAll,
                                 policy: safeInput.policy, conditions: safeInput.conditions)
        guard case .started(let attempt) = result else { throw AttentionCheckFailure(description: "safe independent queue start") }
        try expect(queue.state(of: "affected") == .pending, "affected work retained")
        try expect(queue.complete(attempt, principal: owner), "safe completion")
    }
    check("original recovery remains independent of changed permission and uncertain shared faults stop batch") {
        for evidence: RecoveryEvidence in [.verifiedIsolatedRollback, .uncertain, .sharedFailure] {
            let input = observation(); var queue = QueueModel(principal: owner, queueID: "recovery-batch")
            _ = queue.enqueue(QueueEntry(id: "one", target: "target-one", release: release()), principal: owner)
            _ = queue.enqueue(QueueEntry(id: "two", target: "target-two", release: release()), principal: owner)
            let result = queue.start(id: "one", requestID: "one", principal: owner, kind: .manual,
                policy: input.policy, conditions: input.conditions)
            guard case .started(let attempt) = result else { throw AttentionCheckFailure(description: "initial safe start") }
            try expect(queue.fail(attempt, principal: owner, scope: .isolated), "enter recovery")
            let denied = try controller(observation(permission: .revoked))
            try expect(isBlocked(denied.decision(for: .manual)), "new affected starts refuse")
            try expect(queue.recover(attempt, principal: owner, evidence: evidence), "recovery takes no permission or start-policy gate")
            let next = observation(binding(target: "target-two"))
            let outcome = queue.start(id: "two", requestID: "two", principal: owner, kind: .manual,
                                     policy: next.policy, conditions: next.conditions)
            if evidence == .verifiedIsolatedRollback {
                guard case .started = outcome else { throw AttentionCheckFailure(description: "isolated verified rollback permits next safe item") }
            } else { try expect(outcome == .stopped, "uncertain/shared recovery barrier retained") }
        }
    }
}
