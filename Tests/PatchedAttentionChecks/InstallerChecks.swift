import PatchedScheduling

@MainActor func registerInstallerChecks() {
    check("interactive work requires explicit launch, reports pending and cannot launch twice") {
        let exact = binding(requirements(.notRequired, .required))
        var value = try controller(observation(exact))
        try expect(hasReason(value, .interactiveApproval), "interactive reason")
        try expect(value.presentation.actions.contains(.launchInstaller), "explicit action")
        try expect(value.decision(for: .manual) == .explicitRoutePrepared, "prepared does not launch")
        for kind: StartKind in [.updateAll, .automatic, .loginWindow] {
            try expect(isBlocked(value.decision(for: kind)), "no implicit launch")
        }
        _ = try launched(&value, exact)
        try expect(value.lifecycle == .awaitingInstaller, "launch is not installed")
        try expect(hasReason(value, .installerPending), "waiting guidance")
        try expect(value.requestManualStart(binding: exact) == nil, "duplicate launch refused")
        try expect(isBlocked(value.decision(for: .manual)), "in-flight operation blocks new start")
    }
    check("matching independent readback completes interactive route exactly once") {
        let exact = binding(requirements(.notRequired, .required))
        var value = try controller(observation(exact))
        let attempt = try launched(&value, exact)
        try expect(value.recordInstallerResult(attempt: attempt, result: .reportedSuccess,
                                               readback: installed(exact)), "matching result positive")
        try expect(value.lifecycle == .installed, "only readback establishes model completion")
        try expect(!value.recordInstallerResult(attempt: attempt, result: .reportedSuccess,
                                                readback: installed(exact)), "late duplicate completion")
        try expect(value.requestManualStart(binding: exact) == nil, "completed work does not reinstall")
        try expect(value.presentation.scanAvailable && value.presentation.viewAvailable, "read access retained")
    }
    check("installer return without readback cannot manufacture installed success") {
        let exact = binding(requirements(.notRequired, .required))
        var value = try controller(observation(exact))
        let attempt = try launched(&value, exact)
        try expect(value.recordInstallerResult(attempt: attempt, result: .reportedSuccess), "uncertain return recorded")
        try expect(value.lifecycle == .recoveryRequired, "missing readback is uncertain")
        try expect(hasReason(value, .recoveryRequired), "actionable recovery state")
        try expect(value.presentation.actions.contains(.viewRecovery), "recovery guidance")
    }
    check("cancelled failed or unknown installer return never claims success or safe rollback") {
        for result: AttentionInstallerResult in [.cancelled, .failed, .unknown] {
            let exact = binding(requirements(.notRequired, .required))
            var value = try controller(observation(exact))
            let attempt = try launched(&value, exact)
            try expect(value.recordInstallerResult(attempt: attempt, result: result), "uncertain outcome retained")
            try expect(value.lifecycle == .recoveryRequired, "without restoration evidence recovery is required")
            try expect(isBlocked(value.decision(for: .automatic)), "cannot resume own unsafe work")
        }
    }
    check("foreign controller attempts and changed or mismatched completion evidence refuse") {
        let exact = binding(requirements(.notRequired, .required))
        var first = try controller(observation(exact)); var second = try controller(observation(exact))
        let a = try launched(&first, exact); let b = try launched(&second, exact)
        try expect(a != b, "same binding does not merge controller lifetimes")
        try expect(!first.recordInstallerResult(attempt: b, result: .reportedSuccess,
                                                readback: installed(exact)), "foreign token refuses")
        try expect(first.lifecycle == .awaitingInstaller, "foreign reply leaves owned attempt intact")
        try expect(first.recordInstallerResult(attempt: a, result: .reportedSuccess,
                                               readback: installed(exact, identity: release("3"))), "bad readback recorded as uncertain")
        try expect(first.lifecycle == .recoveryRequired, "wrong installed release cannot complete")
        let changed = binding(requirements(.notRequired, .required), revision: 2)
        _ = second.refresh(observation(changed))
        try expect(!second.recordInstallerResult(attempt: b, result: .reportedSuccess,
                                                 readback: installed(exact)), "stale observation reply cannot complete")
        try expect(second.lifecycle == .recoveryRequired, "changed active observation requires recovery")
    }
    check("abandoned interactive operation and revoked permission preserve recovery guidance") {
        let exact = binding(requirements(.notRequired, .required))
        var value = try controller(observation(exact))
        _ = try launched(&value, exact)
        try expect(value.cancel(binding: exact), "abandon recorded")
        try expect(value.lifecycle == .recoveryRequired, "cancel does not prove untouched target")
        _ = value.refresh(observation(exact, permission: .revoked))
        try expect(value.lifecycle == .recoveryRequired, "permission change cannot strand recovery display")
        try expect(value.presentation.actions.contains(.viewRecovery), "safe recovery remains independently available")
        try expect(value.presentation.scanAvailable && value.presentation.viewAvailable, "read-only remains")
    }
    check("installed restart pending clears only through exact new-boot readback") {
        let exact = binding(requirements(.required))
        var value = try controller(observation(exact))
        try expect(value.approveRestart(binding: exact), "pre-start restart approval")
        let attempt = try launched(&value, exact)
        try expect(value.recordInstallerResult(attempt: attempt, result: .reportedSuccess,
                                               readback: installed(exact, pending: .yes)), "installed pending receipt")
        try expect(value.lifecycle == .installedRestartPending, "not up-to-date")
        try expect(hasReason(value, .installedRestartPending), "honest pending restart reason")
        try expect(value.presentation.title == "Installed, restart pending", "explicit pending title")
        for bad in [
            AttentionPostRestartReadback(binding: exact, installedRelease: release(), observedBoot: "boot-one", restartPending: .no),
            AttentionPostRestartReadback(binding: exact, installedRelease: release(), observedBoot: "", restartPending: .no),
            AttentionPostRestartReadback(binding: binding(requirements(.required), target: "other"), installedRelease: release(), observedBoot: "boot-two", restartPending: .no),
            AttentionPostRestartReadback(binding: exact, installedRelease: release("3"), observedBoot: "boot-two", restartPending: .no),
            AttentionPostRestartReadback(binding: exact, installedRelease: release(), observedBoot: "boot-two", restartPending: .unknown)
        ] {
            try expect(!value.recordPostRestart(bad), "unbound or insufficient restart evidence refuses")
            try expect(value.lifecycle == .installedRestartPending, "bad readback cannot clear pending state")
        }
        try expect(value.recordPostRestart(AttentionPostRestartReadback(binding: exact, installedRelease: release(),
            observedBoot: "boot-two", restartPending: .no)), "exact post-restart positive")
        try expect(value.lifecycle == .installed, "restart independently observed")
    }
}
