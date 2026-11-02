import PatchedDisposableProof

// Literal owner-approved replacement measurements, independent of production constants.
// These checks exercise request parsing only; they do not construct native guest authority.
@MainActor func registerParallelsTargetChecks() {
    check("Parallels exact approved selector parses") {
        let request = try DisposableArguments.parse([
            "--target-id", "parallels-0A0A0A0A-0000-4000-8000-000000000001",
            "--run-id", "parallels-binding", "--case", "init-run", "--explicit-trigger"
        ])
        try expect(request.targetID == "parallels-0A0A0A0A-0000-4000-8000-000000000001", "Exact replacement selector")
        try expect(request.runPath == "/Users/andy/PatchedProof/parallels-binding" && request.targetPath == nil,
                   "Replacement retains isolated run path and no default application destination")
    }
    for selector in [
        "utm-9AAEFEB3-4D36-4ED2-AD13-D2BAADD63246",
        "parallels-0A0A0A0A-0000-4000-8000-000000000003",
        "parallels-0a0a0a0a-0000-4000-8000-000000000001"
    ] {
        check("Parallels refuses unapproved literal selector \(selector)") {
            try refuses(.unknownTarget) {
                _ = try DisposableArguments.parse([
                    "--target-id", selector, "--run-id", "parallels-binding",
                    "--case", "init-run", "--explicit-trigger"
                ])
            }
        }
    }
    check("Parallels contract pins exact selector") {
        try expect(DisposableScope.targetID == "parallels-0A0A0A0A-0000-4000-8000-000000000001", "Replacement only")
    }
    check("Parallels contract pins measured platform UUID digest") {
        try expect(DisposableScope.guestUUIDSHA256 == "d0c5822c54defb6c6971336fc87f86d794dfca4d3d9497a57701f04d016de959",
                   "Exact measured guest identity, separate from VM selector")
    }
    check("Parallels contract pins exact OS") {
        try expect(DisposableScope.guestOS == "27.0.1", "Exact approved OS")
    }
    check("Parallels contract pins exact OS build") {
        try expect(DisposableScope.guestBuild == "26A434", "Exact approved build")
    }
    check("Parallels contract retains non-root account and isolated parent") {
        try expect(DisposableScope.guestUID == 501 && DisposableScope.guestUser == "andy" &&
                   DisposableScope.guestHome == "/Users/andy" && DisposableScope.runParent == "/Users/andy/PatchedProof",
                   "Unchanged account and isolated run parent")
    }
    check("Parallels contract retains exact hostname and architecture") {
        try expect(DisposableScope.guestHostname == "mac-staging.local" && DisposableScope.guestArchitecture == "arm64",
                   "Unchanged hostname and architecture")
    }
}
