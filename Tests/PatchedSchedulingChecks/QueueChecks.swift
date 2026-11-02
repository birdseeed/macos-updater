import PatchedScheduling

@MainActor func registerQueueChecks() {
    check("queue starts once; replies and request IDs cannot replay") {
        var queue = QueueModel(principal: owner, queueID: "fixture-queue")
        try expect(queue.enqueue(entry(), principal: owner), "enqueue first")
        try expect(!queue.enqueue(entry(), principal: owner), "duplicate entry")
        let attempt = try started(queue.start(id: "A", requestID: "request-1", principal: owner,
                                             kind: .automatic, policy: optedIn(), conditions: conditions()))
        try expect(queue.start(id: "A", requestID: "request-1", principal: owner, kind: .automatic,
                               policy: optedIn(), conditions: conditions()) == .rejected, "duplicate start")
        try expect(queue.complete(attempt, principal: owner), "completion")
        try expect(!queue.complete(attempt, principal: owner), "duplicate reply")
        try expect(queue.state(of: "A") == .completed, "committed terminal state")
        try expect(queue.enqueue(entry("B"), principal: owner), "enqueue independent target")
        // CHECK-MODIFIED: fresh input is bound to B's exact target.
        try expect(queue.start(id: "B", requestID: "request-1", principal: owner, kind: .automatic,
                               policy: optedIn(), conditions: conditions(target: "target-B")) == .rejected, "request cannot authorize different work")
    }
    check("queue current skip and identity binding checked at start") {
        var queue = QueueModel(principal: owner, queueID: "fixture-queue")
        try expect(queue.enqueue(entry(), principal: owner), "enqueue")
        var policy = optedIn(); policy.skip(release())
        try expect(queue.start(id: "A", requestID: "skip", principal: owner, kind: .updateAll,
                               policy: policy, conditions: conditions()) == .deferred(.skipped), "unstarted work respects latest skip")
        try expect(queue.state(of: "A") == .pending, "deferred work preserved")
        try expect(queue.start(id: "A", requestID: "wrong-candidate", principal: owner, kind: .automatic,
                               policy: optedIn(), conditions: conditions(release("3"))) == .rejected, "eligibility bound to queued candidate")
        policy.unskip(release())
        _ = try started(queue.start(id: "A", requestID: "unskip", principal: owner, kind: .updateAll,
                                    policy: policy, conditions: conditions()))
    }
    check("queue principal isolation includes late replies and reconstruction") {
        var queue = QueueModel(principal: owner, queueID: "fixture-queue")
        try expect(!queue.enqueue(entry(), principal: other), "other owner enqueue")
        try expect(queue.enqueue(entry(), principal: owner), "owner enqueue")
        try expect(queue.start(id: "A", requestID: "other", principal: other, kind: .automatic,
                               policy: optedIn(), conditions: conditions()) == .rejected, "other owner start")
        let attempt = try started(queue.start(id: "A", requestID: "owner", principal: owner,
                                             kind: .automatic, policy: optedIn(), conditions: conditions()))
        try expect(!queue.complete(attempt, principal: other), "other completion")
        try expect(!queue.fail(attempt, principal: other, scope: .isolated), "other failure")
        queue = QueueModel(restoring: queue.snapshot)
        try expect(queue.state(of: "A") == .recovering(attempt), "uncertain running state requires recovery")
        try expect(!queue.recover(attempt, principal: other, evidence: .verifiedIsolatedRollback), "other recovery")
        try expect(queue.recover(attempt, principal: owner, evidence: .verifiedIsolatedRollback), "owner recovery")
    }
    check("policy changes cannot strand completion or recovery; rollback allows independent work") {
        var queue = QueueModel(principal: owner, queueID: "fixture-queue")
        try expect(queue.enqueue(entry(), principal: owner), "enqueue A")
        try expect(queue.enqueue(entry("B"), principal: owner), "enqueue B")
        let attempt = try started(queue.start(id: "A", requestID: "A1", principal: owner,
                                             kind: .automatic, policy: optedIn(), conditions: conditions()))
        var changed = paused(); changed.automaticEnabled = false; changed.skip(release())
        // CHECK-MODIFIED: fresh input is bound to B's exact target.
        try expect(queue.start(id: "B", requestID: "B1", principal: owner, kind: .automatic,
                               policy: changed, conditions: conditions(target: "target-B")) == .stopped, "serial batch")
        try expect(queue.fail(attempt, principal: owner, scope: .isolated), "enter recovery")
        try expect(!queue.complete(attempt, principal: owner), "recovery cannot be mistaken for commit")
        try expect(queue.recover(attempt, principal: owner, evidence: .verifiedIsolatedRollback), "safe rollback independent of changed policy")
        try expect(queue.state(of: "A") == .restored, "restored distinct from completed")
        try expect(!queue.recover(attempt, principal: owner, evidence: .verifiedIsolatedRollback), "duplicate recovery reply")
        let next = try started(queue.start(id: "B", requestID: "B2", principal: owner,
                                          kind: .automatic, policy: optedIn(), conditions: conditions(target: "target-B")))
        try expect(next.sequence > attempt.sequence, "deterministic increasing attempts")
        try expect(!queue.complete(attempt, principal: owner), "stale reply cannot finish next work")
        try expect(queue.complete(next, principal: owner), "safe completion independent of later policy")
    }
    check("uncertain or shared recovery stops independent work across restart") {
        for evidence: RecoveryEvidence in [.uncertain, .sharedFailure] {
            var queue = QueueModel(principal: owner, queueID: "fixture-queue")
            try expect(queue.enqueue(entry(), principal: owner), "enqueue A")
            try expect(queue.enqueue(entry("B"), principal: owner), "enqueue B")
            let attempt = try started(queue.start(id: "A", requestID: "A1", principal: owner,
                                                 kind: .automatic, policy: optedIn(), conditions: conditions()))
            try expect(queue.fail(attempt, principal: owner, scope: .isolated), "failure")
            try expect(queue.recover(attempt, principal: owner, evidence: evidence), "record unsafe outcome")
            queue = QueueModel(restoring: queue.snapshot)
            try expect(queue.state(of: "A") == .attention, "unsafe attention retained")
            // CHECK-MODIFIED: fresh input is bound to B's exact target.
        try expect(queue.start(id: "B", requestID: "B1", principal: owner, kind: .manual,
                                   policy: optedIn(), conditions: conditions(target: "target-B")) == .stopped, "unsafe barrier")
        }
    }
    check("shared failure cannot be cleared by isolated rollback claim") {
        var queue = QueueModel(principal: owner, queueID: "fixture-queue")
        try expect(queue.enqueue(entry(), principal: owner), "enqueue A")
        try expect(queue.enqueue(entry("B"), principal: owner), "enqueue B")
        let attempt = try started(queue.start(id: "A", requestID: "A1", principal: owner,
                                             kind: .automatic, policy: optedIn(), conditions: conditions()))
        try expect(queue.fail(attempt, principal: owner, scope: .shared), "shared failure")
        try expect(queue.recover(attempt, principal: owner, evidence: .verifiedIsolatedRollback), "record rollback")
        // CHECK-MODIFIED: fresh input is bound to B's exact target.
        try expect(queue.start(id: "B", requestID: "B1", principal: owner, kind: .automatic,
                               policy: optedIn(), conditions: conditions(target: "target-B")) == .stopped, "shared barrier survives")
    }
    // CHECK-ADDED: tokens bind the queue lifetime and principal, not only a counter.
    check("foreign queue and principal replies cannot complete matching local attempt") {
        var first = QueueModel(principal: owner, queueID: "queue-one")
        var second = QueueModel(principal: owner, queueID: "queue-two")
        var foreign = QueueModel(principal: other, queueID: "queue-one")
        try expect(first.enqueue(entry(), principal: owner), "first enqueue")
        try expect(second.enqueue(entry(), principal: owner), "second enqueue")
        try expect(foreign.enqueue(entry(), principal: other), "foreign enqueue")
        let a = try started(first.start(id: "A", requestID: "r", principal: owner, kind: .automatic,
                                        policy: optedIn(), conditions: conditions()))
        let b = try started(second.start(id: "A", requestID: "r", principal: owner, kind: .automatic,
                                         policy: optedIn(), conditions: conditions()))
        var foreignInput = conditions(); foreignInput.principal = other
        let c = try started(foreign.start(id: "A", requestID: "r", principal: other, kind: .automatic,
            policy: SchedulePolicy(principal: other, automaticEnabled: true), conditions: foreignInput))
        try expect(a != b && a != c, "same sequence is not same authority")
        try expect(!first.complete(b, principal: owner), "other queue token")
        try expect(!first.complete(c, principal: owner), "other principal token")
        try expect(first.complete(a, principal: owner), "correct token still works")
    }
    check("snapshot preserves request dedup sequence and interrupted recovery") {
        var queue = QueueModel(principal: owner, queueID: "reconstructed")
        try expect(queue.enqueue(entry(), principal: owner), "enqueue A")
        try expect(queue.enqueue(entry("B"), principal: owner), "enqueue B")
        let a = try started(queue.start(id: "A", requestID: "A1", principal: owner, kind: .automatic,
                                        policy: optedIn(), conditions: conditions()))
        queue = QueueModel(restoring: queue.snapshot)
        try expect(queue.queueID == "reconstructed", "queue identity retained")
        try expect(!queue.complete(a, principal: owner), "lost reply cannot manufacture committed recovery")
        try expect(queue.start(id: "B", requestID: "B1", principal: owner, kind: .automatic,
                               policy: optedIn(), conditions: conditions(target: "target-B")) == .stopped, "recover before next")
        try expect(queue.recover(a, principal: owner, evidence: .verifiedIsolatedRollback), "fresh verified rollback")
        queue = QueueModel(restoring: queue.snapshot)
        try expect(!queue.recover(a, principal: owner, evidence: .verifiedIsolatedRollback), "reconstructed duplicate recovery")
        try expect(queue.start(id: "B", requestID: "A1", principal: owner, kind: .automatic,
                               policy: optedIn(), conditions: conditions(target: "target-B")) == .rejected, "dedup retained")
        let b = try started(queue.start(id: "B", requestID: "B2", principal: owner, kind: .automatic,
                                        policy: optedIn(), conditions: conditions(target: "target-B")))
        try expect(b.sequence == a.sequence + 1, "sequence retained")
        try expect(queue.complete(b, principal: owner), "next completes")
        queue = QueueModel(restoring: queue.snapshot)
        try expect(!queue.complete(b, principal: owner), "reconstructed duplicate completion")
    }
    check("queue binds current evidence to target and principal and deduplicates work") {
        var queue = QueueModel(principal: owner, queueID: "binding")
        try expect(queue.enqueue(entry(), principal: owner), "enqueue")
        let duplicate = QueueEntry(id: "alias", target: "target-A", release: release())
        try expect(!queue.enqueue(duplicate, principal: owner), "same work under new entry ID")
        let wrongPolicy = SchedulePolicy(principal: other, automaticEnabled: true)
        try expect(queue.start(id: "A", requestID: "p", principal: owner, kind: .automatic,
                               policy: wrongPolicy, conditions: conditions()) == .rejected, "wrong policy principal")
        var wrongInput = conditions(); wrongInput.principal = other
        try expect(queue.start(id: "A", requestID: "i", principal: owner, kind: .automatic,
                               policy: optedIn(), conditions: wrongInput) == .rejected, "wrong evidence principal")
        try expect(queue.start(id: "A", requestID: "t", principal: owner, kind: .automatic,
                               policy: optedIn(), conditions: conditions(target: "another-target")) == .rejected, "wrong evidence target")
        queue = QueueModel(restoring: queue.snapshot)
        try expect(queue.start(id: "A", requestID: "off", principal: owner, kind: .automatic,
                               policy: SchedulePolicy(principal: owner), conditions: conditions()) == .deferred(.automaticOff), "restart rechecks current consent")
    }
    check("shared barrier survives restart during recovery") {
        var queue = QueueModel(principal: owner, queueID: "shared-recovery")
        try expect(queue.enqueue(entry(), principal: owner), "enqueue A")
        try expect(queue.enqueue(entry("B"), principal: owner), "enqueue B")
        let attempt = try started(queue.start(id: "A", requestID: "A1", principal: owner, kind: .automatic,
                                              policy: optedIn(), conditions: conditions()))
        try expect(queue.fail(attempt, principal: owner, scope: .shared), "shared failure")
        queue = QueueModel(restoring: queue.snapshot)
        try expect(queue.recover(attempt, principal: owner, evidence: .verifiedIsolatedRollback), "rollback reply")
        try expect(queue.state(of: "A") == .attention, "shared fault still needs attention")
        try expect(queue.start(id: "B", requestID: "B1", principal: owner, kind: .manual,
                               policy: optedIn(), conditions: conditions(target: "target-B")) == .stopped, "shared recovery barrier retained")
    }

}
