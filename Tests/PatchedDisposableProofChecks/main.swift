import Foundation
import Darwin
@_spi(Testing) import ArtifactInspection
@_spi(Testing) import PatchedDisposableProof

// Explicit fixture emission is separate from the gate. It prints bytes only; no caller output
// directory is accepted. The host orchestrator may retain/transfer after its own scope checks.
if Array(CommandLine.arguments.dropFirst()) == ["--emit-current-catalogue-fixtures"] {
    do {
        let now = Date().timeIntervalSince1970
        let envelopes = try ["valid": CatalogueFixture.envelope(now: now),
            "invalid-signature": CatalogueFixture.envelope(now: now, badSignature: true),
            "untrusted-key": CatalogueFixture.envelope(now: now, untrusted: true),
            "replayed-sequence": CatalogueFixture.envelope(sequence: 6, now: now),
            "expired-catalogue": CatalogueFixture.envelope(now: now, expired: true)]
        print(String(decoding: try json(envelopes.mapValues { $0.base64EncodedString() }), as: UTF8.self)); exit(0)
    } catch { print("Fixture emission failed: \(error)"); exit(1) }
}
var checks: [(String, () throws -> Void)] = []
@MainActor func check(_ name: String, _ body: @escaping () throws -> Void) { checks.append((name, body)) }

// Separate additive storage focus: synthetic .build journals and data-only markers.
if Array(CommandLine.arguments.dropFirst()) == ["--pat-2710-profile-storage"] {
    registerProfileStorageChecks()
    guard !checks.isEmpty else { print("Profile storage acceptance: EMPTY"); exit(1) }
    var storageFailures = 0
    for (name, action) in checks {
        do { try action(); print("PASS synthetic: \(name)") }
        catch { storageFailures += 1; print("FAIL synthetic: \(name): \(error)") }
    }
    print("Profile storage acceptance: \(checks.count) cases, \(storageFailures) failures. Synthetic journals and declared marker data only; no runtime/native authority.")
    exit(storageFailures == 0 ? 0 : 1)
}

// Additive Phase A pure checks; this focused mode never registers a runtime call.
if Array(CommandLine.arguments.dropFirst()) == ["--pat-2710-target-profile"] {
    registerTargetProfileChecks()
    guard !checks.isEmpty else { print("Target profile acceptance: EMPTY"); exit(1) }
    var profileFailures = 0
    for (name, action) in checks {
        do { try action(); print("PASS synthetic: \(name)") }
        catch { profileFailures += 1; print("FAIL synthetic: \(name): \(error)") }
    }
    print("Target profile acceptance: \(checks.count) cases, \(profileFailures) failures. Pure declared facts only; no guest/runtime authority.")
    exit(profileFailures == 0 ? 0 : 1)
}

// Focused mode never registers or invokes the existing host/guest runtime checks.
if Array(CommandLine.arguments.dropFirst()) == ["--pat-2710-installed-observer"] {
    registerInstalledBundleObserverChecks()
    guard !checks.isEmpty else { print("Installed observer acceptance: EMPTY"); exit(1) }
    var observerFailures = 0
    for (name, action) in checks {
        do { try action(); print("PASS synthetic: \(name)") }
        catch { observerFailures += 1; print("FAIL synthetic: \(name): \(error)") }
    }
    print("Installed observer acceptance: \(checks.count) cases, \(observerFailures) failures. Synthetic pipeline only; no Security validation or installed proof.")
    exit(observerFailures == 0 ? 0 : 1)
}

check("fixed guest and independent bundle bounds") {
    try expect(DisposableScope.targetID == "parallels-0A0A0A0A-0000-4000-8000-000000000001", "Exact Parallels selector")
    try expect(DisposableScope.caseRoots.count == 13 && Set(DisposableScope.caseRoots).count == 13, "Exactly thirteen independent roots")
    try expect(DisposableScope.maximumEntries == 20_000 && DisposableScope.maximumDepth == 40 && DisposableScope.maximumTotalBytes == 2_147_483_648, "Separate provisional real bundle bounds")
}
for action in ["init-run", "prepare-root", "update", "restore-old", "report"] {
    check("parse explicit \(action)") {
        let request = try DisposableArguments.parse(args(action, root: action == "init-run" ? nil : "update"))
        try expect(request.action.rawValue == action && request.explicitTrigger, "Exact explicit action")
        try expect(request.runPath == "/Users/andy/PatchedProof/phase-a", "Fixed run parent")
        try expect(request.targetPath == (action == "init-run" ? nil : "/Users/andy/PatchedProof/phase-a/Cases/update/Applications/Firefox.app"), "Fixed target path")
    }
}
for bad in [".bootstrap-phase-a", "", ".", "..", "../escape", "/Applications", "x/y", "x//y", "x\0y", "x y", "-x", String(repeating: "a", count: 65)] {
    check("unsafe run ID \(String(reflecting: bad))") { try refuses(.unsafePath) { _ = try DisposableArguments.parse(args(run: bad)) } }
}
check("no default arguments") { try refuses(.invalidArguments) { _ = try DisposableArguments.parse([]) } }
check("wrong target") {
    var a = args(); a[1] = "physical-host"
    try refuses(.unknownTarget) { _ = try DisposableArguments.parse(a) }
}
check("trigger required") { try refuses(.userTriggerRequired) { _ = try DisposableArguments.parse(args().filter { $0 != "--explicit-trigger" }) } }
for extra in [["--target-id", DisposableScope.targetID], ["--guest-uuid", "asserted"], ["--clock", "1"], ["--source-revision", "claimed"], ["--unknown"]] {
    check("unknown or duplicate arguments \(extra[0])") { try refuses(.invalidArguments) { _ = try DisposableArguments.parse(args() + extra) } }
}
for root in ["Firefox.app", "/Applications", "update/../swap", "other"] {
    check("unknown case root \(root)") { try refuses(.unknownCase) { _ = try DisposableArguments.parse(args(root: root)) } }
}
for pair in [("recover-after-swap", "update"), ("recover-after-staging", "swap"), ("update", "staging"), ("restore-old", "swap")] {
    check("case mismatch \(pair)") { try refuses(.caseMismatch) { _ = try DisposableArguments.parse(args(pair.0, root: pair.1)) } }
}
for pair in [("staging-failure", "staging"), ("recover-after-staging", "staging"), ("interrupted-swap", "swap"), ("recover-after-swap", "swap")] {
    check("linked recovery root parses \(pair.0)") { try expect(try DisposableArguments.parse(args(pair.0, root: pair.1)).caseRoot == pair.1, "Correct linked root") }
}
check("recorded evidence never live") {
    try refuses(.recordedEvidenceRefused) { try DisposableProof.rejectRecordedEvidence(Data("{\"freshOSValidation\":true,\"installationAuthorized\":true}".utf8)) }
}
// CHECK-MODIFIED PAT-2702: the old OS/hypervisor-only exclusion also rejected the
// CI runner VM. This test-only predicate permits its refusal check only when the
// read-only account observation proves both fixed approved account fields differ.
func hostRefusalPreflight(available: Bool, hypervisor: Int32, version: String,
                          accountName: String?, accountHome: String?) -> Bool {
    if !available || hypervisor != 1 || version != DisposableScope.guestOS { return true }
    guard let accountName, let accountHome, !accountName.isEmpty, !accountHome.isEmpty else { return false }
    return accountName != "andy" && accountHome != "/Users/andy"
}
for (label, available, hypervisor, version, name, home, permitted) in [
    ("approved guest", true, Int32(1), DisposableScope.guestOS, "andy", "/Users/andy", false),
    ("unknown account", true, 1, DisposableScope.guestOS, nil, nil, false),
    ("unknown name", true, 1, DisposableScope.guestOS, nil, "/Users/runner", false),
    ("unknown home", true, 1, DisposableScope.guestOS, "runner", nil, false),
    ("empty name", true, 1, DisposableScope.guestOS, "", "/Users/runner", false),
    ("empty home", true, 1, DisposableScope.guestOS, "runner", "", false),
    ("approved name", true, 1, DisposableScope.guestOS, "andy", "/Users/runner", false),
    ("approved home", true, 1, DisposableScope.guestOS, "runner", "/Users/andy", false),
    ("distinct runner VM", true, 1, DisposableScope.guestOS, "runner", "/Users/runner", true),
    ("physical host", true, 0, DisposableScope.guestOS, "andy", "/Users/andy", true),
    ("different OS", true, 1, "0.0.0", "andy", "/Users/andy", true),
    ("unavailable hypervisor observation", false, 1, DisposableScope.guestOS, "andy", "/Users/andy", true),
] as [(String, Bool, Int32, String, String?, String?, Bool)] {
    check("host refusal preflight \(label)") {
        try expect(hostRefusalPreflight(available: available, hypervisor: hypervisor, version: version,
                                       accountName: name, accountHome: home) == permitted, "Exact test-only invocation boundary")
    }
}
check("host runtime refuses before any write") {
    // This check refuses to invoke runtime on the approved guest. Gates never run live cases.
    var hv: Int32 = 0, size = MemoryLayout<Int32>.size
    let available = sysctlbyname("kern.hv_vmm_present", &hv, &size, nil, 0) == 0
    let os = ProcessInfo.processInfo.operatingSystemVersion
    let version = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    // CHECK-MODIFIED PAT-2702: use the OS account database, never environment overrides.
    var accountName: String?, accountHome: String?
    if let account = getpwuid(getuid()), let name = account.pointee.pw_name, let home = account.pointee.pw_dir {
        accountName = String(cString: name); accountHome = String(cString: home)
    }
    try expect(hostRefusalPreflight(available: available, hypervisor: hv, version: version,
                                   accountName: accountName, accountHome: accountHome), "Negative check cannot execute on the potentially approved guest")
    let run = "host-refusal-" + UUID().uuidString.lowercased()
    let destination = DisposableScope.runParent + "/" + run
    let before = exists(DisposableScope.runParent)
    try refuses(.guestMismatch) { _ = try DisposableProof.execute(DisposableArguments.parse(args("init-run", root: nil, run: run))) }
    try expect(!exists(destination) && exists(DisposableScope.runParent) == before, "Host refusal created state")
}

for version in ["157.0", "157.0.1"] {
    check("exact approved pin \(version)") { try ProofMechanics.requireExactPin(FirefoxTargets.select(version: version), version: version) }
    for field in ["hash", "length", "team", "bundle", "url", "architectures", "version"] {
        check("pin refuses changed \(field) \(version)") {
            var p = try FirefoxTargets.select(version: version)
            switch field { case "hash": p.sha256 = String(repeating: "0", count: 64)
            case "length": p.byteLength -= 1; case "team": p.teamID = "AAAAAAAAAA"
            case "bundle": p.bundleID = "org.other.app"; case "url": p.url += "?ignored"
            case "architectures": p.architectures = ["arm64"]; default: p.version = "158.0" }
            try refuses(.unapprovedArtifact) { try ProofMechanics.requireExactPin(p, version: version) }
        }
    }
    check("pinned exact bytes metadata \(version)") {
        let p = try FirefoxTargets.select(version: version)
        try ProofMechanics.requireArtifactMetadata(version: version, length: p.byteLength, sha256: p.sha256)
    }
    check("length precedes digest \(version)") { try refuses(.lengthMismatch) { try ProofMechanics.requireArtifactMetadata(version: version, length: 1, sha256: "wrong") } }
    check("pin digest refusal \(version)") { try refuses(.digestMismatch) { try ProofMechanics.requireArtifactMetadata(version: version, length: FirefoxTargets.select(version: version).byteLength, sha256: String(repeating: "0", count: 64)) } }
}
check("same volume accepted") { try ProofMechanics.requireSameVolume(rootDevice: 1, entryDevice: 1) }
check("cross volume refused pure boundary") { try refuses(.crossVolume) { try ProofMechanics.requireSameVolume(rootDevice: 1, entryDevice: 2) } }

let transitions: Set<String> = ["prepared:staging", "staging:staged", "staged:swapIntended", "swapIntended:swapped", "swapped:committed",
    "prepared:rolledBack", "staging:rolledBack", "staged:rolledBack", "swapIntended:rolledBack", "swapped:rolledBack", "committed:swapIntended"]
for from in ProofState.allCases { for to in ProofState.allCases {
    check("transition \(from.rawValue) to \(to.rawValue)") {
        if transitions.contains(from.rawValue + ":" + to.rawValue) { try ProofMechanics.requireTransition(from: from, to: to) }
        else { try refuses(.invalidState) { try ProofMechanics.requireTransition(from: from, to: to) } }
    }
} }
for state in [ProofState.prepared, .staging, .staged, .swapIntended, .rolledBack] {
    check("old still in place recovery \(state.rawValue)") {
        let outcome = try ProofMechanics.recovery(state: state, targetIsOld: true, targetIsNew: false, retainedIsOld: false, stageMatches: false)
        try expect(outcome == (state == .rolledBack ? .none : .oldAlreadyInPlace), "Old recovery decision")
    }
}
for state in [ProofState.swapIntended, .swapped] {
    check("post-exchange recovery \(state.rawValue)") { try expect(try ProofMechanics.recovery(state: state, targetIsOld: false, targetIsNew: true, retainedIsOld: true, stageMatches: true) == .restoredOldBySwap, "Swap recovery decision") }
}
check("committed remains committed") { try expect(try ProofMechanics.recovery(state: .committed, targetIsOld: false, targetIsNew: true, retainedIsOld: true, stageMatches: true) == .none, "Committed recovery") }
for layout in [(false, false, false, false), (true, true, true, true), (false, true, false, true), (false, true, true, false)] {
    check("ambiguous physical recovery \(layout)") { try refuses(.ambiguousState) { _ = try ProofMechanics.recovery(state: .swapIntended, targetIsOld: layout.0, targetIsNew: layout.1, retainedIsOld: layout.2, stageMatches: layout.3) } }
}

registerFilesystemChecks()
registerJournalCatalogueChecks()
registerParallelsTargetChecks()
registerProcessObservationChecks()
registerProcessOwnershipChecks()
registerInstalledBundleObserverChecks()
registerTargetProfileChecks()
registerProfileStorageChecks()
var failures = 0
for (name, action) in checks {
    do { try action(); print("PASS synthetic: \(name)") }
    catch { failures += 1; print("FAIL synthetic: \(name): \(error)") }
}
print("Disposable proof acceptance: \(checks.count) cases, \(failures) failures. Synthetic mechanics only; no live OS trust or installed proof.")
exit(failures == 0 ? 0 : 1)
