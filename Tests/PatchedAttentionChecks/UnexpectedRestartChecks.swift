import PatchedScheduling

@MainActor func registerUnexpectedRestartChecks() {
    check("unexpected restart requirement contradicts approved interactive route and requires recovery") {
        let exact = binding(requirements(.notRequired, .required))
        var value = try controller(observation(exact))
        let attempt = try launched(&value, exact)
        try expect(value.recordInstallerResult(attempt: attempt, result: .reportedSuccess,
                                               readback: installed(exact, pending: .yes)), "unexpected restart readback recorded")
        try expect(value.lifecycle == .recoveryRequired, "unapproved restart requirement is a contradictory outcome")
        try expect(hasReason(value, .recoveryRequired), "unexpected restart requires recovery guidance")
        try expect(value.presentation.actions.contains(.viewRecovery), "recovery action remains available")
        for kind: StartKind in [.manual, .updateAll, .automatic, .loginWindow] {
            try expect(isBlocked(value.decision(for: kind)), "uncertain outcome blocks every new affected start")
        }
        try expect(value.requestManualStart(binding: exact) == nil, "cannot begin another attempt")
        try expect(!value.recordPostRestart(AttentionPostRestartReadback(binding: exact,
            installedRelease: release(), observedBoot: "boot-two", restartPending: .no)),
            "post-restart data cannot erase contradictory requirement uncertainty")
        try expect(value.lifecycle == .recoveryRequired, "uncertainty survives post-restart readback")
    }
}
