# Patched self-update implementation briefs

PAT-2609, 9 October 2026. All paths/commands below are **proposed and do not exist at this source revision** unless explicitly marked existing.
Base `6eb00f2d9e6ac52cac42c525fb6793798cdcb6b8`; dependency-ordered preparation, not authorisation to execute these slices.
Read [architecture](self-update-architecture.md), current repository/root AGENTS.md and latest owning issues before each brief.
Accepted release target: macOS 15+ on Apple silicon; current Package.swift macOS 13 is historical source state. Coordinate the proposed PAT-2611 [platform launch contract](platform-launch-contract.md). No Intel Mac launch coverage.
Parent owns acceptance, Linear, deliberate atomic commits/pushes and any separately authorised merge; leaf implementers do not commit or delegate.
The routing text below records the 9 October proposal; current canonical routing takes precedence. Use fresh self-contained briefs with exact scope. Ordinary bounded code: `gpt-6.1-sol` medium; >400 changed lines or trust-boundary/native installer/signing/CI work: strongest applicable implementer (`gpt-6-astra`, bounded high or repo-required tier).
Every real behaviour/pipeline diff needs independent full-diff correctness/security review under the current canonical `/Users/example/Development/Patched.im/AGENTS.md` and `.claude/skills/run/references/review-gate.md`. The 19 October through-BETA ruling selects fixed `nvidia/nvidia/nemotron-3-ultra-550b-a55b`, high, fresh stateless no-tools direct NVIDIA HTTPS; OpenCode is not required. Approved fresh `gpt-6-astra` high fallback for Sol-authored work follows the same immutable artifact and independence rules. Preserve findings and diagnostics; never switch to escape completed `CHANGES_REQUIRED`. No eligible reviewer means acceptance remains blocked.
New checks must be CHECK-MODIFIED in review, preserve existing gate coverage and diagnose failures rather than silently exit.
For each slice: first compile a refusing/stub predicate, run a decisive positive/negative fixture that fails for the intended reason, implement, then green and existing full gate. Missing commands/build errors are not meaningful red.
All deterministic checks must use test-only keys, fake clocks/transports/service status and disposable private directories; never discover real keys, register services or launch Patched as a hidden test step.

## S1: pure policy, release freshness and maintenance model

**Recommendation:** start here because owner defaults and adversarial admission can be proved without a dependency, network, signing credential or installed target.
Exact new paths: `Sources/PatchedSelfUpdatePolicy/{Policy,ReleaseIdentity,FeedFreshness,ReplayCheckpoint,MaintenanceState,Compatibility,SelfUpdateClock}.swift`;
`Tests/PatchedSelfUpdatePolicyChecks/{main,ConsentChecks,FreshnessChecks,CompatibilityChecks,MaintenanceChecks}.swift`;
`Fixtures/SelfUpdate/{README.md,policy-vectors.json}` and `scripts/verify-self-update-policy.sh`.
Modify existing `Package.swift` for dependency-free library/check executable and existing `scripts/verify.sh` to include it; no Sparkle dependency yet.
Proposed command `./scripts/verify-self-update-policy.sh` builds/runs `patched-self-update-policy-checks`; existing `./scripts/verify.sh` follows.
Red example: a permissive admission stub incorrectly admits an expired/replayed feed or busy recovery; named assertions must fail before implementation.
Acceptance: auto-on fresh default, persistent opt-out, third-party auto-off independence, expired trial/paid/outage self-update allowed, no third-party authority gained;
strict identity/build/arch/OS/schema predicates, feed expiry/sequence/digest conflict, missing/corrupt time/state, maintenance generation races and bounded consent.
**DONE-WHEN:** vectors are deterministic, all checks pass, defaults cannot overwrite opt-out, no production execution authority is introduced and full diff reviewed.
**UNBLOCKS-WHEN:** parent accepts engineering bounds, exact feed-extension schema and catalogue/licence/helper interface proposals, and amends repo scope for pure targets.

## S2: pinned Sparkle adapter and authenticated admission

Depends on S1. Recommend a separate trust-boundary slice: the actual framework lifecycle must prove the barrier before any packaging confidence is useful.
Exact new paths: `Sources/PatchedSelfUpdate/{SparkleController,SparkleDelegate,VerifiedFeedAdapter,SelfUpdateSettings,MaintenanceClient,SelfUpdateStatus}.swift`;
`Tests/PatchedSelfUpdateChecks/{main,AdapterChecks,SignedFeedChecks,QuitRaceChecks,SettingsChecks}.swift`; `scripts/verify-self-update-adapter.sh`.
Modify existing `Package.swift` to add exact Sparkle 2.10.0 only to adapter, add proposed `Package.resolved`, existing `Sources/PatchedApp/PatchedApp.swift` composition and `scripts/verify.sh`.
No changes to `PatchedCore` fixture authority or third-party installer paths; existing app gates stay compile/offscreen only.
Fake first-run/setup status must separate optional helper approval from App Management and ordinary installer permissions: allow/deny/undecided/revoked, truthful responsible-identity unknown state, supported settings navigation and no broad permission workaround. Anonymous/expired viewing and self-update remain ungated by account state.
Proposed command `./scripts/verify-self-update-adapter.sh` builds/runs `patched-self-update-checks` with fakes; existing full gate follows.
First inspect pinned headers/source and prove where signed bytes/extension claims become authenticated and when archive/install scheduling becomes armed.
Red example: a fake termination event bypasses a relaunch-only guard; signature-valid but expired feed must also fail before a download/installer callback.
Acceptance: retained main-actor updater, explicit safe initialisation, settings migration, manual menu, auto default override, identity/key/clock rejection before use, no inventory/credentials in transport;
maintenance admission precedes `shouldProceedWithUpdate`; install-on-quit/crash cannot outlive a missing durable barrier; lost replies never duplicate installation.
Failure to prove authenticated custom feed fields or pre-arm maintenance with public APIs is a blocker, not permission for unsigned parsing/private APIs or a Sparkle fork.
**DONE-WHEN:** tested event traces cover manual/automatic/quit/cancel paths and prove no start during active install/recovery, with no native launch/service installation in the gate.
**UNBLOCKS-WHEN:** repo dependency/native scope amendment, actual SDK/framework API compatibility and accepted PAT-2607 maintenance contract are concrete; independent stronger-tier review available.

## S3: helper compatibility and durable upgrade coordination

Joint with PAT-2607 H8; agree single-writer file ownership before work. Recommend drain-before-upgrade because migrating an active transaction journal expands recovery risk.
This ticket adds `Sources/PatchedSelfUpdate/{UpgradeCoordinator,UpgradeJournal,StateRestoration}.swift` and `Tests/PatchedSelfUpdateChecks/{UpgradeChecks,MultiUserChecks,RecoveryChecks}.swift`.
PAT-2607 owns proposed `Sources/PatchedPrivilegedHelper/MaintenanceCoordinator.swift`, `Sources/PatchedHelperProtocol/MaintenanceMessages.swift` and `Tests/PatchedHelperTransportChecks/MaintenanceChecks.swift`.
Extend proposed `scripts/verify-self-update-adapter.sh`; helper owner extends its proposed `./scripts/verify-helper-transport.sh`; existing full gate follows after both land sequentially.
Red example: second UID starts a third-party transaction after maintenance generation acquired; test must catch it. Inject crash at every upgrade-journal boundary.
Acceptance: authenticated digest-bound maintenance token, machine-wide barrier, no new work across users, disabled vs unreachable distinction, old/new IPC/queue schema compatibility;
private durable queue/settings/drafts survive failure, old helper never replaced while active, incompatible pair blocks new work, expired licence cannot block recovery/self-update.
Opt-out in any affected active user and other Patched copy activity defer shared replacement; no force quit/login hold. Unknown system activity refuses.
**DONE-WHEN:** all cross-user/restart/lost-reply/schema/partial-upgrade fake cases pass without weakening helper peer identity, and native limitations are recorded for S5.
**UNBLOCKS-WHEN:** helper H3-H6 interfaces exist/reviewed, exact supported version matrix and rollback/forward-repair semantics are accepted; target credentials are not needed for fake checks.

## S4: native signed packaging and release/feed CI

Depends on S2/S3 and PAT-7/PAT-941 prerequisites. Strongest implementer and independent NVIDIA full supply-chain review required.
Recommend native Xcode archive/export wrapper around existing sources: new `packaging/Patched.xcodeproj/project.pbxproj`, shared `Patched` scheme,
`packaging/PatchedApp/{Info.plist,App.entitlements,ExportOptions.plist}`, `ThirdParty/Sparkle/NOTICES`, `docs/self-update-release-runbook.md`;
`scripts/{package-self-update,verify-self-update-package,prepare-self-update-feed,verify-self-update-feed,publish-self-update-release}.sh`;
`tools/SelfUpdateReleaseChecks/{main,FeedChecks,ProvenanceChecks}.swift`, `.github/workflows/self-update-release.yml`, `release/self-update-policy.json`.
Modify existing `AGENTS.md`/README only to record accepted scope and existing `scripts/verify.sh` for offline package/feed fixture checks; coordinate helper packaging paths with PAT-2607, never duplicate ownership.
Proposed offline command `./scripts/verify-self-update-feed.sh --fixtures Fixtures/SelfUpdate` must reject wrong key, changed length/digest, stale/rollback feed, wrong bundle and poisoned release notes.
Proposed signed commands, **only after access is authorised**: `./scripts/package-self-update.sh --source-sha <reviewed-sha> --output <private-output>`;
`./scripts/verify-self-update-package.sh --app <private-output>/Patched.app --dmg <private-output>/Patched.dmg --policy release/self-update-policy.json`.
These wrappers must archive/export, inspect nested signatures/entitlements, enforce actual Team ID/identity/slices/build, notarise/staple, retain notary log and run strict codesign/Gatekeeper/stapler validation.
Signing is inside-out; verify each nested component, not only a recursive top-level pass. Check actual binary dependency SHA/checksum and third-party notices.
Set the later native app/package deployment floor to macOS 15; select arm64 first and verify every embedded Sparkle/helper/tool/plugin native slice. Universal never implies Intel Mac support and is eligible only with a proven native route; no Rosetta install or hidden Intel-only dependency. Keep the exact Sparkle 2.10.0 pin; its lower upstream minimum does not lower Patched policy.
Package genuine drag-and-drop Applications distribution; prove first-run optional-helper decline and separate App Management/installer permission handling rather than treating root/helper approval as privacy consent.
Generate final DMG bytes before archive signature; feed is signed only after all fields/notes are final. No mutation after signing.
CI design: read-only PR checks, pinned action SHAs/toolchain, no pull_request_target checkout of untrusted code, no release secrets on PR/fork runners, isolated owner-approved release environment and least-privilege publication token.
Routine CI produces candidate/provenance; approved isolated signing station performs signing with separate Sparkle/Apple authority; publisher receives signed bytes, not private keys.
Proposed deployment command `./scripts/publish-self-update-release.sh --record <approved-record.json> --destination <accepted-release-origin>` requires exact reviewed SHA/green checks/independent review and release authority; publish artifacts first, signed feed last, read back independently.
No selected hosting/resource path currently exists. Choose independent release/recovery origins and deployment identities before implementing provider-specific configuration; no catalogue or licence secret reuse.
Red example: modified source SHA or red review/check record must refuse signing/publish, compromised artifact upload must fail readback, signed-feed expiry fallback must remain disabled.
**DONE-WHEN:** negative interlock proofs, exact-byte package/feed provenance, key backup/isolated restore drill, authentic recovery distribution and approved hosting readback are evidenced; CI success alone is insufficient.
**UNBLOCKS-WHEN:** verified identity/access, authorised signing/backup environment, named hosting/deployment/cost scope, approved release transition and no-manual-fallback rule are accepted. Provisioning/first release still needs its own authority.

## S5: real signed old-to-new approved-target proof

Depends on S4 and separately accepted PAT-2584/2602 target authority. Recommend disposable Apple-silicon guest first, then the named macOS 15/26/27 matrix below, because signing/IPC/runtime failures cannot be simulated away.
New `scripts/prove-self-update.sh`, `tools/prove-self-update.swift`, `docs/self-update-proof-runbook.md`; output proposed `evidence/self-update/<run-id>/{report.json,events.jsonl,checksums.txt}` with no credentials/personal paths.
Proposed command `./scripts/prove-self-update.sh --target-id <approved-id> --scenario <named-case> --old <signed-old.dmg> --new <signed-new.dmg>`.
It must refuse missing/unknown target or scope before setup; approval names app/helper install, test users, disposable destination, exact signed pair, feed destination and recovery baseline.
Do not lower bundle versions in a customer artifact to simulate success; produce genuine signed monotonic older/newer test builds on an isolated test channel, never redirect production feed.
Record source/review SHA, framework pin/hash, OS/build/arch, target/approval identity, exact downloaded/installed hashes, bundle/Team IDs, signatures/notary results, preferences, queue/journal and actual helper handshake.
Required cases: success automatic and manual; opt-out; expired trial/paid/outage; corrupt/short archive; wrong release/Apple signer/bundle; stale/replayed/equal/downgrade feed/build; unsupported OS/architecture;
limited/unknown network and path changes; battery/Low Power/unknown signal; interruption at download/stage/replace/health boundaries; normal Quit/crash; unsaved state; two users/copies; helper active/recovering/disabled/unreachable/incompatible;
permission/restart decline/cancel/change; no forced restart/login hold; failed new helper with intact old recovery; catalogue key bridge/retirement and compromised-catalogue independent escape; unavailable routine feed and restored-backup recovery.
Proposed target labels below identify required proof slots, not existing or authorised machines. Bind each to actual UUID/hardware/OS build and approval before any setup; use the central platform contract for shared evidence.

| Proof slot | Required self-update/setup evidence | State |
| --- | --- | --- |
| `SELFUPDATE-AS15` | macOS 15 Apple silicon: drag/drop, first run, native UI/viewing, app/helper identity, App Management allow/deny/undecided/revoked, upgrade and relocation. | Unproven, target unassigned. |
| `SELFUPDATE-AS26` | macOS 26 Apple silicon: same cases plus signed old/new update/refusal/recovery, queue durability, multi-user and helper decline/remove/reapprove. | Unproven, target unassigned. |
| `SELFUPDATE-AS27` | macOS 27 Apple silicon: full same matrix including permission/signing continuity, safe scheduling and interrupted self-update; host read-only proof is insufficient. | Unproven, target unassigned. |

Every slot ultimately covers all applicable S5 cases, signed catalogue refusal, native architecture eligibility and real third-party installed/recovery interactions through their owning proof tickets. No version row inherits another OS result or future-version support claim.
**DONE-WHEN:** each claimed case has fresh before/after/native evidence, actual old-tree recovery or verified forward repair, no duplicate queue start, preserved settings/drafts/profile and target restored as agreed; independent acceptance checks evidence.
**UNBLOCKS-WHEN:** named target/setup/install/interrupt/recovery authority, signed test pair, controlled feed, tested backup/recovery access and reliable guest login exist. Failure leaves release blocked with exact observed outcome.

## Future SME boundary review

Review each slice for reusable release verification/admission/maintenance core with opaque identities and explicit capability inputs, keeping household/account UI, five-Mac limits and pricing in consumer policy/services. Test that account/product labels cannot alter release or privileged authority.
Consumer launch comes first; future self-service small-business ownership/roles, configuration, deployment and licensing would consume separate service/policy boundaries only after accepted requirements. No fork, organisation implementation, fleet infrastructure, enterprise procurement/assurance workflow, numerical cutoff or automatic household migration now. Record residual schema/ownership/deployment migration needs rather than promising zero rework.

## Completion boundaries

This preparation: `git diff --check` only; parent reads both complete docs against source/owner rulings and primary references, then commits/pushes accepted atomic docs under standing authority.
No proposed command above ran during preparation. No app build, package resolution, key operation, registration, feed deployment or install occurred.
Implementation ready means its slice prerequisites are accepted; pure policy green does not unblock a customer release.
PAT-941 stays blocked until actual signing, installed success/refusal/recovery, supply-chain review, authentic distribution, catalogue trust, licensing and operational release gates have evidence.
