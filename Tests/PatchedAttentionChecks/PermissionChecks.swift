import PatchedScheduling

@MainActor func registerPermissionChecks() {
    check("ordinary missing composition refuses while scan and view remain available") {
        let value = AttentionController(principal: owner)
        for kind: StartKind in [.manual, .updateAll, .automatic, .loginWindow] {
            try expect(value.decision(for: kind) == .blocked([.missingEvidence]), "missing evidence refuses all starts")
        }
        try expect(value.presentation.scanAvailable && value.presentation.viewAvailable, "read-only availability")
        try expect(value.presentation.actions == [.recheck], "default action is evidence recheck")
    }
    check("known safe unattended case succeeds and does not masquerade as installed") {
        let value = try controller()
        for kind: StartKind in [.manual, .updateAll, .automatic, .loginWindow] {
            try expect(value.decision(for: kind) == .unattendedPolicyEligible, "positive excludes always-refuse implementation")
        }
        try expect(value.lifecycle == .pending, "eligibility is not completion")
        try expect(value.presentation.reasons.isEmpty, "safe input has no attention reason")
    }
    for (permission, reason): (AttentionPermission, AttentionReason) in [
        (.unknown, .missingEvidence), (.notDetermined, .permissionNeeded),
        (.denied, .permissionDenied), (.revoked, .permissionRevoked)
    ] {
        check("permission \(permission.rawValue) blocks starts and gives a reason without blocking read-only work") {
            let value = try controller(observation(permission: permission))
            for kind: StartKind in [.manual, .updateAll, .automatic, .loginWindow] {
                try expect(isBlocked(value.decision(for: kind)), "permission must gate affected starts")
            }
            try expect(hasReason(value, reason), "exact permission reason")
            try expect(value.presentation.scanAvailable && value.presentation.viewAvailable, "scan and view survive")
            try expect(!value.presentation.actions.contains(.launchInstaller), "no installer launch action")
            try expect(value.presentation.actions.contains(permission == .unknown ? .recheck : .reviewAppManagement), "actionable permission guidance")
        }
    }
    check("helper approval does not substitute for App Management") {
        let value = try controller(observation(permission: .denied, helper: .available))
        try expect(hasReason(value, .permissionDenied), "separate grants")
        try expect(isBlocked(value.decision(for: .manual)), "approved helper cannot bypass denial")
    }
    check("unavailable or unknown helper refuses affected update with readable fallback") {
        for helper: AttentionHelper in [.unknown, .unavailable] {
            let value = try controller(observation(helper: helper))
            try expect(isBlocked(value.decision(for: .manual)), "missing helper evidence refuses")
            try expect(hasReason(value, helper == .unknown ? .missingEvidence : .helperUnavailable), "helper reason")
            try expect(value.presentation.scanAvailable && value.presentation.viewAvailable, "helper decline preserves reading")
        }
    }
    check("running or unknown target cannot start for any start kind") {
        for signal: KnownSignal in [.no, .unknown] {
            var input = observation(); input.conditions.targetClosed = signal
            let value = try controller(input)
            for kind: StartKind in [.manual, .updateAll, .automatic, .loginWindow] {
                try expect(isBlocked(value.decision(for: kind)), "never force target closed")
            }
            try expect(hasReason(value, signal == .no ? .targetRunning : .missingEvidence), "running/unknown distinguished")
            try expect(value.presentation.actions.contains(.recheck), "ask for new observation")
        }
    }
    check("permission revocation invalidates earlier restart approval") {
        let exact = binding(requirements(.required))
        var value = try controller(observation(exact))
        try expect(value.approveRestart(binding: exact), "approve original")
        try expect(value.refresh(observation(exact, permission: .revoked)), "read revoked input")
        try expect(isBlocked(value.decision(for: .manual)), "revocation wins")
        try expect(value.refresh(observation(exact)), "later grant observed")
        try expect(hasReason(value, .restartApproval), "grant must not revive stale approval")
    }
}
