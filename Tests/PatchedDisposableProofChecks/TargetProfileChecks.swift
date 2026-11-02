import Foundation
@_spi(Testing) import PatchedDisposableProof

// Independent literals: do not obtain expected identity or paths from profiles.
private struct ProfileContract: Sendable {
    let profile: DisposableTargetProfile
    let id: String, vm: String, hash: String, user: String, home: String, host: String, parent: String
}
private let profileContracts: [ProfileContract] = [
    .init(profile: .legacy, id: "parallels-0A0A0A0A-0000-4000-8000-000000000001",
          vm: "0a0a0a0a-0000-4000-8000-000000000001", hash: "d0c5822c54defb6c6971336fc87f86d794dfca4d3d9497a57701f04d016de959",
          user: "andy", home: "/Users/andy", host: "mac-staging.local", parent: "/Users/andy/PatchedProof"),
    .init(profile: .ssdTesting, id: "parallels-0A0A0A0A-0000-4000-8000-000000000002",
          vm: "0a0a0a0a-0000-4000-8000-000000000002", hash: "a44c836bfbda0c6beb1df7b3b3178a171479d362ecfacd534a62b09890dde705",
          user: "runner", home: "/Users/runner", host: "patched-test-01", parent: "/Users/runner/PatchedTesting")
]
private let profileRoots = ["tampered-artifact", "truncated-artifact", "recorded-evidence", "wrong-signer-target",
    "wrong-signer-staged", "invalid-signature", "untrusted-key", "replayed-sequence", "expired-catalogue",
    "open-app", "staging", "update", "swap"]
private let profilePairs: [(String, String)] = [
    ("tampered-artifact", "tampered-artifact"), ("truncated-artifact", "truncated-artifact"),
    ("recorded-evidence", "recorded-evidence"), ("wrong-signer-target", "wrong-signer-target"),
    ("wrong-signer-staged", "wrong-signer-staged"), ("invalid-catalogue", "invalid-signature"),
    ("invalid-catalogue", "untrusted-key"), ("replayed-catalogue", "replayed-sequence"),
    ("replayed-catalogue", "expired-catalogue"), ("open-app", "open-app"), ("staging-failure", "staging"),
    ("recover-after-staging", "staging"), ("update", "update"), ("interrupted-swap", "swap"),
    ("recover-after-swap", "swap"), ("restore-old", "update")]
private func profileArgs(_ c: ProfileContract, action: String = "update", root: String? = "update", run: String = "profile-a") -> [String] {
    var a = ["--target-id", c.id, "--run-id", run, "--case", action, "--explicit-trigger"]
    if let root { a += ["--case-root", root] }; return a
}
private func declaredIdentity(_ c: ProfileContract) -> SyntheticDeclaredGuestIdentity {
    .init(realUID: 501, effectiveUID: 501, consoleUID: 501, accountName: c.user, accountHome: c.home,
          homeEnvironment: c.home, hypervisor: 1, osVersion: "27.0.1", osBuild: "26A434", architecture: "arm64",
          hostname: c.host, platformUUIDSHA256: c.hash)
}
@MainActor func registerTargetProfileChecks() {
    check("PAT-2710 profile: closed cases and preserved legacy literals [control]") {
        try expect(DisposableTargetProfile.allCases == [.legacy, .ssdTesting], "Exactly two closed cases")
        try expect(DisposableScope.targetID == "parallels-0A0A0A0A-0000-4000-8000-000000000001" &&
            DisposableScope.guestUUIDSHA256 == "d0c5822c54defb6c6971336fc87f86d794dfca4d3d9497a57701f04d016de959" &&
            DisposableScope.guestUID == 501 && DisposableScope.guestUser == "andy" && DisposableScope.guestHome == "/Users/andy" &&
            DisposableScope.guestHostname == "mac-staging.local" && DisposableScope.guestOS == "27.0.1" &&
            DisposableScope.guestBuild == "26A434" && DisposableScope.guestArchitecture == "arm64" &&
            DisposableScope.runParent == "/Users/andy/PatchedProof" && DisposableScope.caseRoots == profileRoots,
            "Every legacy literal and ordered root remains unchanged")
    }
    for c in profileContracts {
        let name = String(describing: c.profile), p = c.profile
        let fields: [(String, String, String)] = [("targetID", p.targetID, c.id), ("hostVMUUID", p.hostVMUUID, c.vm),
            ("guestUUIDSHA256", p.guestUUIDSHA256, c.hash), ("guestUID", String(p.guestUID), "501"),
            ("guestUser", p.guestUser, c.user), ("guestHome", p.guestHome, c.home), ("guestHostname", p.guestHostname, c.host),
            ("guestOS", p.guestOS, "27.0.1"), ("guestBuild", p.guestBuild, "26A434"),
            ("guestArchitecture", p.guestArchitecture, "arm64"), ("runParent", p.runParent, c.parent)]
        for (field, actual, expected) in fields {
            check("PAT-2710 profile: literal \(name).\(field) [SSD differing fields expect RED]") {
                try expect(actual == expected, "\(name).\(field): expected \(expected), observed \(actual)")
            }
        }
        check("PAT-2710 profile: exact resolver \(name) [SSD expect RED]") {
            try expect(try DisposableTargetProfile.resolve(targetID: c.id) == c.profile, "Exact closed resolver")
        }
        var pairs = profilePairs + profileRoots.map { ("prepare-root", $0) } + profileRoots.map { ("report", $0) }
        pairs.append(("init-run", ""))
        for (action, root) in pairs {
            check("PAT-2710 profile: parse \(name) \(action)/\(root) [SSD expect RED]") {
                let r = try DisposableArguments.parse(profileArgs(c, action: action, root: root.isEmpty ? nil : root))
                try expect(r.profile == c.profile && r.targetID == c.id && r.runID == "profile-a" && r.action.rawValue == action &&
                    r.explicitTrigger && r.runPath == c.parent + "/profile-a" && r.caseRoot == (root.isEmpty ? nil : root) &&
                    r.targetPath == (root.isEmpty ? nil : c.parent + "/profile-a/Cases/" + root + "/Applications/Firefox.app"),
                    "Independent exact selector/profile/run/target path contract")
            }
        }
        check("PAT-2710 profile: every forbidden case-action pair \(name) [SSD expect RED]") {
            for action in DisposableAction.allCases { for root in profileRoots {
                let allowed = action == .prepareRoot || action == .report || profilePairs.contains { $0 == (action.rawValue, root) }
                if !allowed { try refuses(.caseMismatch) { _ = try DisposableArguments.parse(profileArgs(c, action: action.rawValue, root: root)) } }
            } }
        }
        for bad in ["../escape", "x/y", "x//y", "x\0y", "x y", "/absolute", "-x", ".bootstrap-a"] {
            check("PAT-2710 profile: escaped run \(name) \(String(reflecting: bad)) [SSD expect RED]") {
                try refuses(.unsafePath) { _ = try DisposableArguments.parse(profileArgs(c, run: bad)) }
            }
        }
        for bad in ["UPDATE", "other", "update/../swap", "/Applications"] {
            check("PAT-2710 profile: unknown root \(name) \(bad) [SSD expect RED]") {
                try refuses(.unknownCase) { _ = try DisposableArguments.parse(profileArgs(c, root: bad)) }
            }
        }
        for bad in ["UPDATE", "unknown"] {
            check("PAT-2710 profile: unknown action \(name) \(bad) [control]") {
                try refuses(.invalidArguments) { _ = try DisposableArguments.parse(profileArgs(c, action: bad)) }
            }
        }
        check("PAT-2710 profile: explicit trigger required \(name) [SSD expect RED]") {
            try refuses(.userTriggerRequired) { _ = try DisposableArguments.parse(profileArgs(c).filter { $0 != "--explicit-trigger" }) }
        }
        for (action, root, pause) in [("staging-failure", "staging", "stage-copy"),
                                     ("wrong-signer-staged", "wrong-signer-staged", "before-swap"),
                                     ("interrupted-swap", "swap", "before-commit")] {
            check("PAT-2710 profile: exact pause \(name) \(action) [SSD expect RED]") {
                let r = try DisposableArguments.parse(profileArgs(c, action: action, root: root) + ["--pause", pause])
                try expect(r.profile == c.profile && r.pause?.rawValue == pause, "Closed case/pause pairing")
            }
        }
        for pause in ["before-commit", "unknown"] {
            check("PAT-2710 profile: invalid pause \(name) \(pause) [SSD expect RED]") {
                try refuses(.invalidArguments) { _ = try DisposableArguments.parse(profileArgs(c) + ["--pause", pause]) }
            }
        }
        check("PAT-2710 profile: recorded path is derived \(name) [SSD expect RED]") {
            let good = c.parent + "/profile-a/Incoming/inspection-157.0.1.json"
            let r = try DisposableArguments.parse(profileArgs(c, action: "recorded-evidence", root: "recorded-evidence") + ["--recorded-evidence", good])
            try expect(r.recordedEvidencePath == good, "Exact derived incoming path")
            let other = c.profile == .legacy ? profileContracts[1] : profileContracts[0]
            try refuses(.unsafePath) { _ = try DisposableArguments.parse(profileArgs(c, action: "recorded-evidence", root: "recorded-evidence") +
                ["--recorded-evidence", other.parent + "/profile-a/Incoming/inspection-157.0.1.json"]) }
        }
        check("PAT-2710 profile: declared identity positive \(name) [expect RED; data only]") {
            try expect(SyntheticDeclaredGuestPredicate.matches(declaredIdentity(c), profile: c.profile), "Exact declared facts must match pure predicate")
        }
        let mutations: [(String, (inout SyntheticDeclaredGuestIdentity) -> Void)] = [
            ("realUID", { $0.realUID = 0 }), ("effectiveUID", { $0.effectiveUID = 0 }), ("consoleUID", { $0.consoleUID = 0 }),
            ("accountName", { $0.accountName = "other" }), ("accountHome", { $0.accountHome += "/other" }),
            ("HOME environment", { $0.homeEnvironment += "/other" }), ("hypervisor", { $0.hypervisor = 0 }),
            ("OS", { $0.osVersion = "27.0.2" }), ("build", { $0.osBuild = "26A435" }), ("architecture", { $0.architecture = "x86_64" }),
            ("hostname", { $0.hostname += ".other" }), ("physical UUID hash", { $0.platformUUIDSHA256 = String(repeating: "0", count: 64) })]
        for (field, mutate) in mutations {
            check("PAT-2710 profile: declared identity refuses \(name) changed \(field) [control]") {
                var facts = declaredIdentity(c); mutate(&facts)
                try expect(!SyntheticDeclaredGuestPredicate.matches(facts, profile: c.profile), "Independent \(field) mutation accepted")
            }
        }
        check("PAT-2710 profile: cross-profile facts and hostname/hash mixes \(name) [control]") {
            let other = c.profile == .legacy ? profileContracts[1] : profileContracts[0]
            try expect(!SyntheticDeclaredGuestPredicate.matches(declaredIdentity(other), profile: c.profile), "Other complete guest matched")
            var facts = declaredIdentity(c); facts.hostname = other.host
            try expect(!SyntheticDeclaredGuestPredicate.matches(facts, profile: c.profile), "Cross-profile hostname matched")
            facts = declaredIdentity(c); facts.platformUUIDSHA256 = other.hash
            try expect(!SyntheticDeclaredGuestPredicate.matches(facts, profile: c.profile), "Cross-profile physical UUID matched")
        }
        for extra in [["--guest-uuid", c.hash], ["--guest-home", c.home], ["--run-parent", c.parent], ["--target-path", "/tmp/app"],
                      ["--profile", "ssdTesting"], ["--target-id", c.id], ["--explicit-trigger"]] {
            check("PAT-2710 profile: refuses freeform or duplicate \(name) \(extra[0]) [control]") {
                try refuses(.invalidArguments) { _ = try DisposableArguments.parse(profileArgs(c) + extra) }
            }
        }
    }
    for bad in ["ssdTesting", "legacy", "parallels-0a0a0a0a-0000-4000-8000-000000000002", "PARALLELS-0A0A0A0A-0000-4000-8000-000000000001",
                "parallels-0A0A0A0A-0000-4000-8000-000000000002/../x", "unknown"] {
        check("PAT-2710 profile: refuses unknown or casefold selector \(bad) [control]") {
            try refuses(.unknownTarget) { _ = try DisposableTargetProfile.resolve(targetID: bad) }
            var a = profileArgs(profileContracts[0]); a[1] = bad
            try refuses(.unknownTarget) { _ = try DisposableArguments.parse(a) }
        }
    }
}
