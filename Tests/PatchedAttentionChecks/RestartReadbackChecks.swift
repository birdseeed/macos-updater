import PatchedScheduling

@MainActor func registerRestartReadbackChecks() {
    check("restart-required install cannot claim complete from a no-restart-pending installer readback") {
        let exact = binding(requirements(.required))
        var value = try controller(observation(exact))
        try expect(value.approveRestart(binding: exact), "explicit exact restart approval")
        let attempt = try launched(&value, exact)
        try expect(value.recordInstallerResult(attempt: attempt, result: .reportedSuccess,
                                               readback: installed(exact, pending: .no)), "contradictory readback retained")
        try expect(value.lifecycle == .recoveryRequired, "required restart contradicts completion without distinct restart evidence")
        try expect(hasReason(value, .recoveryRequired), "contradiction gives recovery guidance")
        try expect(value.presentation.actions.contains(.viewRecovery), "recovery remains actionable")
        try expect(isBlocked(value.decision(for: .manual)), "contradiction cannot become up-to-date or new work")
    }
    check("restart pending and recovery survive changed refresh and permission without resurrecting preparation") {
        for needsRecovery in [false, true] {
            let exact = binding(requirements(.required))
            var value = try controller(observation(exact))
            try expect(value.approveRestart(binding: exact), "explicit exact restart approval")
            let attempt = try launched(&value, exact)
            try expect(value.recordInstallerResult(attempt: attempt,
                result: needsRecovery ? .failed : .reportedSuccess,
                readback: needsRecovery ? nil : installed(exact, pending: .yes)), "terminal model observation")
            let expected: AttentionLifecycle = needsRecovery ? .recoveryRequired : .installedRestartPending
            try expect(value.lifecycle == expected, "correct initial terminal state")
            let changed = binding(requirements(), identity: release("3"), revision: 2, session: 2)
            for permission: AttentionPermission in [.revoked, .denied, .granted] {
                try expect(value.refresh(observation(changed, permission: permission)), "changed context may be observed")
                try expect(value.lifecycle == expected, "refresh cannot erase unresolved terminal state")
                try expect(value.presentation.lifecycle == expected, "display retains unresolved state")
                try expect(isBlocked(value.decision(for: .manual)), "no resurrected preparation")
                try expect(value.requestManualStart(binding: changed) == nil, "no fresh manual attempt")
                try expect(!value.approveRestart(binding: exact), "old approval cannot be recreated")
                try expect(!value.recordInstallerResult(attempt: attempt, result: .reportedSuccess,
                                                        readback: installed(exact, pending: .no)), "late completion cannot clear terminal state")
                try expect(value.presentation.scanAvailable && value.presentation.viewAvailable, "read-only remains available")
            }
        }
    }
}
