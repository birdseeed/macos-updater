import PatchedScheduling

@MainActor func registerConsentChecks() {
    check("restart requires explicit exact consent and remains manual after approval") {
        let exact = binding(requirements(.required))
        var value = try controller(observation(exact))
        try expect(hasReason(value, .restartApproval), "pre-start explanation")
        try expect(value.presentation.actions.contains(.approveRestart), "explicit approval offered")
        try expect(isBlocked(value.decision(for: .manual)), "before approval")
        try expect(value.approveRestart(binding: exact), "exact approval accepted")
        try expect(value.decision(for: .manual) == .explicitRoutePrepared, "manual preparation positive")
        try expect(value.presentation.actions.contains(.startUpdate), "restart-only offers explicit update action")
        try expect(!value.presentation.actions.contains(.launchInstaller), "interactive launch copy is route-specific")
        for kind: StartKind in [.updateAll, .automatic, .loginWindow] {
            try expect(isBlocked(value.decision(for: kind)), "bulk/global consent never launches restart route")
        }
        try expect(value.lifecycle == .pending, "approval never installs or restarts")
    }
    let mutations: [(String, AttentionBinding)] = [
        ("principal", binding(requirements(.required), principal: foreign)),
        ("target", binding(requirements(.required), target: "target-two")),
        ("release", binding(requirements(.required), identity: release("3"))),
        ("build", binding(requirements(.required), identity: release(build: "21"))),
        ("artifact", binding(requirements(.required), identity: release(artifact: "other-bytes"))),
        ("product", binding(requirements(.required), identity: release(product: "other-product"))),
        ("scope", binding(requirements(.required), identity: release(scope: "shared"))),
        ("edition", binding(requirements(.required), identity: release(edition: "pro"))),
        ("channel", binding(requirements(.required), identity: release(channel: "beta"))),
        ("route", binding(requirements(.required), routeID: "route-two")),
        ("requirements", binding(requirements(.required, .required))),
        ("revision", binding(requirements(.required), revision: 2)),
        ("session", binding(requirements(.required), session: 2))
    ]
    for (field, altered) in mutations {
        check("restart approval rejects mismatched \(field)") {
            let exact = binding(requirements(.required))
            var value = try controller(observation(exact))
            try expect(!value.approveRestart(binding: altered), "approval bound to exact displayed context")
            try expect(value.approveRestart(binding: exact), "original remains approvable")
            try expect(value.requestManualStart(binding: altered) == nil, "mismatched launch refused")
        }
    }
    for (label, time, valid): (String, ClockSample, Bool) in [
        ("one second before expiry", clock(1899, 1809), true),
        ("exclusive expiry", clock(1900, 1810), false),
        ("after expiry", clock(1901, 1811), false),
        ("wall rollback", clock(99, 11), false),
        ("wall jump", clock(500, 11), false),
        ("monotonic rollback", clock(101, 9), false),
        ("new boot", clock(101, 1, boot: "boot-two"), false),
        ("untrusted time", clock(101, 11, trusted: false), false)
    ] {
        check("restart consent lifetime: \(label)") {
            let exact = binding(requirements(.required))
            var value = try controller(observation(exact))
            try expect(value.approveRestart(binding: exact), "original approval")
            _ = value.refresh(observation(exact, time: time))
            if valid {
                try expect(value.decision(for: .manual) == .explicitRoutePrepared, "valid interval")
            } else {
                try expect(isBlocked(value.decision(for: .manual)), "expired or uncertain evidence")
                try expect(value.requestManualStart(binding: exact) == nil, "no stale launch")
            }
        }
    }
    check("refresh changes invalidate previous approval without automatic renewal") {
        for changed in [binding(requirements(.required), revision: 2),
                        binding(requirements(.required), session: 2),
                        binding(requirements(.required), identity: release("3"))] {
            let exact = binding(requirements(.required))
            var value = try controller(observation(exact))
            try expect(value.approveRestart(binding: exact), "original approval")
            try expect(value.refresh(observation(changed)), "changed observation accepted")
            try expect(hasReason(value, .restartApproval), "new context needs new explicit consent")
            try expect(!value.approveRestart(binding: exact), "old display cannot approve current context")
        }
    }
    check("cancellation revokes restart approval") {
        let exact = binding(requirements(.required))
        var value = try controller(observation(exact))
        try expect(value.approveRestart(binding: exact), "approval")
        try expect(value.cancel(binding: exact), "cancel exact pending work")
        try expect(isBlocked(value.decision(for: .manual)), "cancelled consent not usable")
        try expect(value.requestManualStart(binding: exact) == nil, "cancel does not launch")
    }
    check("observed expiry or clock uncertainty permanently invalidates old approval until explicit renewal") {
        let exact = binding(requirements(.required))
        var initialUnknown = try controller(observation(exact, time: clock(trusted: false)))
        try expect(!initialUnknown.approveRestart(binding: exact), "unknown clock cannot issue approval")
        for invalid in [clock(1900, 1810), clock(101, 11, trusted: false)] {
            let exact = binding(requirements(.required))
            var value = try controller(observation(exact))
            try expect(value.approveRestart(binding: exact), "original explicit approval")
            _ = value.refresh(observation(exact, time: invalid))
            try expect(isBlocked(value.decision(for: .manual)), "invalid sample observed")
            _ = value.refresh(observation(exact, time: clock(1901, 1811)))
            try expect(hasReason(value, .restartApproval), "later valid clock cannot revive old approval")
            try expect(value.approveRestart(binding: exact), "fresh explicit approval allowed")
            try expect(value.decision(for: .manual) == .explicitRoutePrepared, "renewal positive")
        }
    }
    check("simultaneous interaction and restart requirements need both explicit steps") {
        let exact = binding(requirements(.required, .required))
        var value = try controller(observation(exact))
        try expect(hasReason(value, .interactiveApproval) && hasReason(value, .restartApproval), "both reasons visible")
        try expect(value.requestManualStart(binding: exact) == nil, "launch before restart consent refuses")
        try expect(value.approveRestart(binding: exact), "restart consent")
        try expect(value.decision(for: .manual) == .explicitRoutePrepared, "still requires explicit launch")
        let attempt = try launched(&value, exact)
        try expect(value.lifecycle == .awaitingInstaller, "explicit launch model only")
        try expect(value.recordInstallerResult(attempt: attempt, result: .reportedSuccess,
                                               readback: installed(exact, pending: .yes)), "matching synthetic readback")
        try expect(value.lifecycle == .installedRestartPending, "pending restart remains distinct")
    }
}
