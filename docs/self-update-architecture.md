# Patched self-update architecture

Current boundary, 27 October 2026: ordinary app composition has progressed to [NativeClientSession and the native shell](native-shell-composition.md), including local scanning, preferences, Network, Activity and menu access. The 9 October source inventory below is historical; it does not describe current composition. These local foundations do not implement the proposed self-update pipeline, release trust, helper maintenance handshake or signed installed self-update proof. Self-update readiness remains in scope for beta, with its separate release gates.

PAT-2609, 9 October 2026. Design only; proposed engineering contracts require parent acceptance.
No dependency, code, signing, service, installation or release operation is authorised by this document.

## Historical evidence and authority, 9 October 2026

Source: `6eb00f2d9e6ac52cac42c525fb6793798cdcb6b8`, refreshed by fetch and clean fast-forward to `origin/main`.
`Package.swift` currently declares Swift 6/macOS 13+, dependency-free, with executable proof targets rather than a signed distributable app.
That deployment declaration is historical implementation state: accepted launch policy is **macOS 15+ on Apple silicon**, subject to named operating proof; macOS 13/14 and Intel Macs are not launch coverage.
Coordinate with the proposed [platform launch contract](platform-launch-contract.md) owned by PAT-2611; this document does not prove its matrix or amend build configuration.
`Sources/PatchedApp/PatchedApp.swift` composes the explicit read-only `PatchedClient.ClientView`.
The merged operator session similarly performs explicit local inspection; neither surface installs or releases.
`Sources/PatchedCore/UpdateTransaction.swift` production entry points refuse; fixture authority stays test-only.
Existing `scripts/verify.sh` and `.github/workflows/verify.yml` verify source/fixtures, not self-updating.
[`consumer-release-gates.md`](consumer-release-gates.md) records remaining release gates, including PAT-7 identity/access and PAT-2584 installed proof.
Read alongside PAT-2605/2587 licensing, PAT-2606/2595/2603 catalogue and PAT-2607 helper owner decisions.
The PAT-2607 [background-helper architecture](background-helper-architecture.md) and [plan](background-helper-implementation-plan.md) describe proposed interfaces, not operating capabilities. Parent integration verified their merged documentation; implementation remains absent.
This ticket owns these two documents only; companion owners must accept interface changes before their implementation.
The £500 incremental cap remains, with unknown tool costs recorded as unknown; it grants no purchase authority.

## Accepted customer behaviour

| Control | Contract |
| --- | --- |
| Patched self-update | Automatic ON initially, clear persistent opt-out. Eligible ordinary updates need no per-update prompt. |
| Third-party installation | Separate explicit opt-in, initially OFF. Self-update consent never enables it. |
| Licence | Legitimate Patched checks/downloads/installation remain available after trial/paid expiry and verification outage. No trial reset or new third-party authority. |
| Extra permissions | Ask when required; decline leaves update pending. Never silently approve OS permissions or restore disabled helper approval. |
| Mac restart | Explicit approval before starting a restart-required update; customer chooses restart time. Unknown restart behaviour is ineligible. |
| Timing | Safe opportunity only; no forced quit, wake, logout, restart or login delay. Preserve active installation/recovery and unsaved state. |
| Limited data/power | Small bounded checks allowed; defer automatic downloads on constrained/expensive connections. Pause new automatic installs at low battery/Low Power Mode. |

Recommend separate visible settings “Update Patched automatically” and “Install other app updates automatically”.
Persist explicit false across upgrades/reinstall where preferences survive; a missing migration marker must not overwrite an existing choice.
Opt-out stops new automatic transfers/admission, retaining Check for Updates and explicit manual installation.
It cannot abruptly cancel a transaction beyond its safe interruption point. Explain deferred/attention/error outcomes separately.
No licence token, email code or catalogue availability is required by the self-update transport.
Account-free local discovery/signed catalogue matching and honest viewing remain available before sign-in; verified sign-in is needed for explicit trial start and household control; initial paid activation follows [payment activation](payment-activation-contract.md). Legitimate self-updates need neither. New third-party installs still require entitlement at the trusted transaction boundary.
Revoked/malicious credentials and withdrawn app releases are not newly settled policy; recommend no credential-dependent feed access and independently signed release withdrawal rules.

## Framework pin and upstream evidence

Recommend exact Sparkle **2.10.0**, tag commit `eef1a539a373c1f1a320624b1130fc5de7b2e100`.
GitHub latest-release and tag APIs independently read on 9 October: publication `2026-09-13T23:54:06Z`.
Future dependency: `.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")`; commit `Package.resolved` and verify revision.
Its binary-target ZIP checksum is `17e28312b8e18ab7cdbbe09a6fb28cc55a5479ec6c371dbc07cdecd2a14fd959` in the pinned upstream manifest.
No package was resolved or downloaded here. Check checksum/revision again at integration; a mutable upstream tag must fail the provenance gate.
[Release 2.10.0](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0) raises upstream minimum to macOS 12; Patched launch remains macOS 15+ on Apple silicon. This upstream minimum permits that floor but proves no Patched operating coverage; a component requiring a newer OS must be escalated with recommendation/tradeoff rather than silently raising the floor.
[Published advisories](https://github.com/sparkle-project/Sparkle/security/advisories) checked through GitHub API: five public advisories, fixed in 2.9.2, 2.9.5 or 2.9.6; 2.10.0 is outside their declared vulnerable ranges.
They include path-resolution, privileged cleanup, delta traversal and installer XPC defects. This is a dated advisory check, not a claim of vulnerability absence.
Recheck before every dependency change/release, including upstream package artifact integrity and nested binaries.

## Four separate trust authorities

| Authority | Purpose and separation |
| --- | --- |
| Apple Developer ID | Exact verified Patched organisation Team ID, bundle/designated requirements, hardened runtime and notarisation. PAT-7 supplies facts; never reuse Firefox vendor Team ID. |
| Sparkle release signing | Dedicated Ed25519 archive/feed authority, private key absent from catalogue/licensing/VM/hosting. Releases require reviewed source and approved release transition. |
| Catalogue signing | Dedicated restricted Cloudflare signer selected in PAT-2606; only third-party catalogue authority. Public roots embedded in signed Patched app. |
| Licence signing | Separate entitlement keys/service and claims. An active licence grants neither release nor catalogue trust. |

VM inspection, operator receipts, fixture keys and hosted content grant none of these release authorities.
Apple signing/notarisation and Sparkle signatures are complementary, with distinct failure reporting.
Use [Sparkle basic setup](https://sparkle-project.org/documentation/) for app embedding and archive verification; preserve framework symlinks/executable modes.
Initial distribution must be an authentic Developer ID-signed, notarised/stapled Patched DMG from an owner-approved HTTPS download origin.
The release record binds exact DMG hash, app build, source/review SHA and independently established Patched signing identity.
Customer download instructions must identify the genuine origin and expected publisher; a hash served beside a compromised download alone is not independent authentication.
No catalogue URL, licence redirect or unsigned email installs the first trust root.
For compromise recovery, maintain a separately controlled recovery origin and owner-controlled publication credentials, outside catalogue and routine feed deployment authority.
Recommend a pre-established Apple-authenticated manual replacement route with independently verified identity and recovery instructions; verify it before shipping.
If both release and Apple authorities are compromised, stop automated recovery and establish a new authenticated identity with Apple/customer communication under separate owner authority.
Do not claim that the same compromised website or key can authenticate its own repair.

## Feed, artifact and replay contract

Recommend stable channel only, full signed DMGs initially, no deltas or PKG scripts; fewer moving parts make recovery and path hazards testable.
Use distinct proposed HTTPS paths `/mac/stable/appcast.xml`, `/mac/releases/<build>/<sha256>/Patched.dmg` and a separate recovery origin.
Exact domains/provider/resources remain unselected. Recommend a separate release storage/CDN identity, independent of catalogue runtime and licence sessions.
Feed publication is atomic after immutable artifact upload and independently fetched digest/length/signature readback; never overwrite a released build's bytes.
Use reviewed release notes as inert text, no JavaScript/custom URL schemes, no inventory, account or activation IDs in requests.
Publish appcast `sparkle:version` as monotonic integer `CFBundleVersion`, display version separately, expected byte length, EdDSA signature and minimum macOS.
Bind stable channel, bundle identifier, Team ID/designated requirement, supported architecture, app/helper protocol range and queue/journal schema range in the reviewed release record and signed app contents.
Recommend native arm64 Patched release candidates first; universal is acceptable only when every required app/helper/installer component has a usable native Apple-silicon route. This does not add Intel Mac coverage. Inspect actual binaries/plugins/tool dependencies, never filenames.
Automatic third-party candidates likewise require native/universal usable native routes; Intel-only apps remain visible but are not unattended candidates. Do not install Rosetta automatically or widen eligibility because it is present; manual Intel-only workflows need separate accepted scope. A verified migration from an existing Intel-only app additionally needs exact product/edition/channel/licence compatibility and recovery proof.
Reject wrong identity/channel, equal/lower installed build, unsupported OS/slices, unexpected requirement changes and incompatible helper/schema.
[Publishing documentation](https://sparkle-project.org/documentation/publishing/) describes appcast versions and system/hardware eligibility; Patched must test its additional predicates.
A signed archive alone does not establish feed freshness or prevent server freeze/replay.
Propose signed appcast namespace fields `patched:sequence`, `issuedAt`, `expiresAt`, `minimumClientBuild`, with seven-day maximum feed lifetime and monotonic persisted sequence/build floors.
Those fields and strict decoding are Patched requirements, not built-in Sparkle replay protection. Release tools and adapter must agree exact signed bytes/schema before integration.
Reject duplicate/malformed/oversized fields, external XML entities, unknown critical fields, expired/future feeds, sequence rollback and same-sequence changed bytes.
Use trusted clock/monotonic anchors; missing/corrupt replay state or uncertain clock refuses automatic admission and offers independently verified repair, never reset-as-fresh.
Retain per-installation floors across normal upgrades. Full privileged local-state restoration can defeat ordinary storage; disclose this limit.
An offline client cannot know a newer feed exists; signatures cannot prevent withholding until trusted expiry is observed. Report stale/unavailable, never “up to date”.
Signed withdrawal/minimum-safe-build policy must be specified before production; do not infer it from catalogue or licensing status.

Recommend `SURequireSignedFeed=YES`, `SUVerifyUpdateBeforeExtraction=YES`, `SUSignedFeedFailureExpirationInterval=0`.
This deliberately disables Sparkle's timed signed-feed-failure escape; manual independently authenticated recovery remains essential.
[Security settings](https://sparkle-project.org/documentation/customization/) document these flags and their dependencies.
Set `SUEnableAutomaticChecks=YES`, `SUAutomaticallyUpdate=YES`, `SUEnableSystemProfiling=NO` as initial bundle defaults; runtime changes only follow customer choices.
Prove the integration can reject raw signed-feed policy before any untrusted release note/artifact use; do not treat an unverified parallel XML parser as Sparkle's authenticated result.
If pinned public APIs cannot expose authenticated extension fields in time, native integration stays blocked until a reviewed bounded adapter contract is demonstrated; no unsigned fallback.

## Native ownership and packaging

Proposed `PatchedSelfUpdatePolicy` target remains dependency-free; `PatchedSelfUpdate` alone imports Sparkle.
Compose a retained `SPUStandardUpdaterController` on main actor, start explicitly after policy/recovery initialisation, expose truthful canCheckForUpdates/menu/settings state.
[Programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/) supports explicit start and SwiftUI composition; Patched adds its own admission coordination.
A SwiftPM executable build is insufficient: propose a reviewed native Xcode archive/export wrapper producing real `Patched.app` with Info.plist, Frameworks and optional embedded helper layout.
Use existing executable name/source without creating a second independent app controller. Repository amendment must explicitly allow dependency and native packaging work.
Keep Sparkle's installer components separate from PAT-2607's optional privileged third-party helper. Their permissions/lifecycles are not interchangeable.
Recommend unsandboxed direct-distribution app with hardened runtime, secure timestamp, no release get-task-allow/JIT/disabled library validation.
Inspect and sign each required nested executable/framework inside out; do not use `codesign --deep` as a signing strategy.
Retain upstream licence/copyright and bundled third-party notices; inventory actual distributed Sparkle components under its permissive licence before release.
[Apple notarisation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) requires signed executables/hardened runtime and supports notarytool/stapler; retain accepted logs and test actual Gatekeeper behaviour.
[SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) manages embedded services on macOS 13+; registration status is separate from compatible running code and may need user approval.
No automatic registration/reapproval is introduced merely by replacing the bundle.
Accepted consumer setup is download, drag Patched into Applications, then first-run explanation and optional background-helper approval; declining preserves capabilities that do not need it. Do not promise one approval.
App Management is a separate OS consent concern from helper administrator approval and ordinary installer permissions. [Apple Privacy & Security guidance](https://support.apple.com/guide/mac-help/change-privacy-security-settings-on-mac-mchl211c911f/27/mac/27) describes it as permission to update/delete other apps; it does not establish which Patched app/helper/installer identity is responsible for a particular route.
Prove that exact responsible signed identity on each supported OS, with allow/deny/not-yet-decided/revoked states, helper decline/removal/reapproval, relocation and upgrade/signing continuity. Offer plain first-run guidance and supported settings navigation when required; unknown permission means deferred/permission-needed, not installation authority.
No programmatic grant/bypass, system-setting mutation, Full Disk Access or Accessibility workaround. Scanning/viewing permission and installer capability remain distinct; denial/revocation must preserve safe recovery.

## Admission, maintenance and recovery

State: `checking -> available -> deferredDownload/downloaded -> waitingQuiescence -> admitted -> replacing -> verifying -> completed` or `attention/recoveryRequired`.
Check/download is separate from install admission; no cached report or UI Boolean is a capability.
Before Sparkle's potentially install-on-quit stage, acquire a machine-wide maintenance barrier covering all Patched copies/users, app transactions and helper recovery.
The pinned [SPUUpdaterDelegate header](https://github.com/sparkle-project/Sparkle/blob/2.10.0/Sparkle/SPUUpdaterDelegate.h) explicitly says install-on-quit still occurs even when its callback is intercepted.
Therefore relaunch postponement alone is insufficient. Recommend refusing `shouldProceedWithUpdate` until durable quiescence is acquired, initially holding that barrier through the admitted download/install cycle.
This conservative ordering can defer third-party work during a download; keep small discovery outside admission and permit safe cancellation only when no installer remains armed.
Prove unexpected Quit, crash and OS termination cannot bypass the barrier. If that cannot be shown with public APIs, do not arm automatic installation.
Network path/power rechecks apply both before admission and before mutation; unknown safety never becomes consent.
Proposed helper `prepareMaintenance` returns a durable generation, helper build/IPC range, queue/journal schema, zero-active-transaction proof and barrier token bound to release digest.
PAT-2607 owns authenticated IPC and `MaintenanceCoordinator`; this ticket owns the Sparkle side. No unauthenticated Boolean can grant quiescence.
All new third-party starts across users refuse while the barrier is live; already-running work must finish or recover first. Never replace live helper executable/resources.
Persist queue/journals/policy outside replaced bundle, sync before release, and never migrate an active journal. Both old and new pair must read the supported recovery schema.
Use expand-before-contract schema transitions; destructive migrations require separate scope. Hold queue resume until new app/helper handshake and installed signature/version readback succeed.
When helper disabled/declined, distinguish no-installed-helper from unreachable helper with possibly active work. Unknown activity defers; no silent re-enable.
For shared `/Applications` app, coordinate all sessions/processes using it; other-user activity or conflicting opt-out defers automatic replacement. Per-user consent cannot terminate another user's app.
Recommend automatic relaunch only at awake/idle opportunity with restorable UI state and no unsaved editor, file picker, sign-in or support draft; otherwise wait for a safe normal quit.
Persist navigation/preferences and drafts privately, not credentials in a journal. Ordinary Patched relaunch is not Mac restart.
Permission/restart approval binds exact release/digest/requirement, expires after 30 minutes/logout/candidate change; no generic unattended approval or forced restart.
Unexpected required permission/restart leaves attention state before mutation, or uses proven safe recovery after mutation; unsupported routes remain excluded.
Keep validated previous app/helper pair until new health/readback succeeds; automatic repair must not bypass build floor or restore retired catalogue trust.
Recommend forward recovery by higher-build repair release for functional faults; local before-image rollback only within a verified incomplete transaction, with durable floor retained.
A successful download/relaunch is not installed success. Report exact installed version/identity and helper compatibility; uncertain state stops new third-party work and preserves evidence.

## Key lifecycle and independent recovery

Recommend release signing on an isolated owner-controlled release station, not routine CI/hosting/catalogue Worker; CI produces unsigned candidates for reviewed approval/signing.
This is a recommendation pending custody approval, not permission to generate/import/read a key. Separate Apple and Sparkle credentials, access, backups and audit.
Maintain inventory of public key ID/fingerprint, authorised app builds, custodian, recovery location/access and rotation history without private material in source/logs.
Before use, create separately authorised encrypted backup, owner-held recovery secret and second protected copy; record named storage/access and loss/compromise procedures.
Restore drill: isolated approved environment, decrypt without logging, verify expected public fingerprint, sign harmless test bytes, verify independently, destroy ephemeral copy under approved procedure.
A backup file alone is not recovery proof. Drill loss of signing workstation, unavailable hosting and inability to use catalogue/licence services.
Ordinary rotation: publish bridge app through uncompromised existing release/Apple authority, then switch signer; retain old-client compatible path until accepted retirement policy.
Sparkle supports changing one of Apple/EdDSA authorities at a time; pre-extraction validation imposes signed-DMG rotation requirements. Test the exact pinned route, never change both silently.
Compromised Sparkle key cannot authorise its own replacement. Freeze routine release, isolate/revoke access, use independently authenticated Apple/manual recovery or proven unaffected authority, and audit affected builds.
Compromised Apple authority similarly requires independent release authority and Apple incident handling; dual compromise needs separately established customer recovery.
Catalogue compromise: updated app replaces embedded catalogue roots via independent Sparkle/Apple path, retires affected key IDs and advances trust epoch/build floor.
Routine catalogue transition may overlap old/new keys in a bridge build; updated clients enforce exact key ID/epoch/algorithm mapping and reject retired keys even if signatures verify.
Minimum compatible app build and “Update Patched to refresh catalogue trust” state must not require valid third-party entitlement.
Old offline/unupdated clients still trust their embedded compromised key; fresh malicious catalogues can be signed indefinitely while that key remains trusted. Catalogue expiry alone does not contain this window.
Stop known-compromised publication, notify customers through separately authorised channels, require app update/manual recovery, and state the old-client residual risk explicitly.
No catalogue-signed replacement key, cached untrusted root or licensing response repairs trust. Catalogue owner must accept mapping/overlap/retirement fixtures before production.

## Future SME boundary review

Consumer release, actual use and operating tests come first. Keep one shared codebase; a future self-service small-business edition is a possible direction, with no numerical cutoff and no enterprise procurement/assurance obligations or fork now.
Release identity/signature/feed verification, discovery/matching, transaction/recovery and helper maintenance use stable opaque identities and explicit capabilities, independent of household UI, five-Mac limits, offer/pricing and account workflow. Consumer entitlement/allocation stays in its own policy/service boundary; no product-mode flag grants privileged authority.
A later accepted edition could add organisation ownership/roles through account services, managed configuration through explicit policy inputs, and business licensing/administration through separate service/UI composition. Existing consumer permission/account proof cannot establish organisation authority.
Review that consumer constants do not leak into reusable trust/update core; preserve current household policy. Future data migration, deployment ownership, roles, billing and configuration may still need changes and independent review. Do not build tenants, fleet inventory/remote commands, managed overrides, enterprise billing or generic policy/plugin infrastructure now, and never auto-migrate household accounts.

## Remaining gates

Recommend accept pure policy work first: it yields meaningful security/refusal tests without credentials or a target.
Native integration remains gated on authenticated feed extension access, install-on-quit barrier proof and helper owner's accepted maintenance contract.
Packaging/publication needs verified PAT-7 identity/access, chosen independent domains/custody/backup procedure and reviewed release interlock.
Actual signed older-to-newer proof needs separately approved target/install authority and compatible signed app/helper pairs.
No operating claim, first client release or PAT-941 completion follows from these documents; detailed slices are in [implementation plan](self-update-implementation-plan.md).
