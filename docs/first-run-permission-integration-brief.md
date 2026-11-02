# Draft first-run setup and permission integration brief

PAT-2667. The historical preparation below was written on 16 October 2026,
based on `f54c87f94ebdb8e864323ce6e8544dcf912c0bd8`, for the
live issue.
The CURRENT section records the later source integration. No native permission
observation, helper installation or initial data send is established here.

## CURRENT: durable preference owner and first-run source integration, 24 October 2026

The admitted PAT-2667 source prerequisite supersedes the historical second
`SetupStore` proposal below. Durable first-run choices and completion now belong
to the existing `PreferenceSession`, its one store/CAS, inner revision and queue.
Schema 3 wraps the unchanged schema-2 schedule value, adds only failure-report
preference, completion and inert Network draft, and retains bounded setup request
receipts. Daily checks and notifications stay with schedule settings. See
[first-run-preferences.md](first-run-preferences.md) for exact migration,
readback, refusal, replay and privacy boundaries.

The earlier durable preference source was delivered separately in
PR #123. The current
local source adds `NativeFirstRunController`, `NativeFirstRunView` and a root
route observing the retained setup owner directly. It shares the existing
navigation, local scanner and Network owners. No second setup store, revision,
queue, Network validator or transport is introduced. See
[native-first-run.md](native-first-run.md) for the current actions and limits.

Welcome Continue explicitly opens/reloads saved preferences. Review Continue
saves partial choices before Find apps. Find apps saves completion before an
explicit read-only local scan; Open Updates without scanning saves completion
without scanning. Local observations do not establish fresh catalogue results or
update availability. Back, Network return and presentation retain choices without
I/O. Missing-only creation, reload, Scan without saving choices and Open app
without saving are separate controls. Unavailable/corrupt state is never reset;
save failures remain visibly unsaved and reload retains opt-outs.

The three editable declarations are daily checks, notifications and future
failed-update reports. Daily timer/check dispatch and notification registration
are not connected. Reporting is unavailable; no initial or later send occurs.
Coverage and automatic installation remain OFF and disabled, the optional helper
uninstalled/unavailable, and App Management status unavailable. Completion never
grants permission or helper authority. The existing Network child supplies its
own explicit actions; setup navigation never applies, refreshes or probes it.
Its saved draft is never transport or consent acceptance.

The parent accepted the compiling pre-implementation view RED (56 combined
cases, ten intended view failures and eight new passing controls alongside the
prior 38 controller passes). No post-implementation GREEN is claimed here.
Current compilation, focused/full verification, whole-diff independent review,
required exact-head/main CI and publication remain parent-owned gates. Offscreen
paint and source bindings do not prove native keyboard/VoiceOver, permission
transitions, offline/authenticated-proxy behaviour, guest execution or installed
first launch/relaunch. These remain separately authorised proof work.

## Historical preparation, 16 October 2026

The remainder preserves the original source snapshot and proposals as historical
evidence. Its second persistence owner and old execution/reviewer statements do
not override the current admission or canonical governance.

## Scope and design evidence

The root `AUTHORISED-SCOPE.md` non runner continuation and `evidence/non-runner-continuation-20261015/authorised-scope.json` refill include PAT-2667 preparation. Runtime/VM/runner recovery remains exclusively with Life. Hosted CI, pushes triggering runners, app/helper launch/install, signing, credentials, purchases, actual telemetry/customer/provider delivery and client release remain excluded.

Approved reference source: `/Users/example/.codex/visualizations/2026/10/12/01a13097-c8b0-7bb2-877b-af3fb335da21/patched-updates.html`. Read as source only. `:66` and `:69` declare Focused and Details variants; use their common behaviour and do not invent an exclusive variant decision. `:383` sets failure reports ON, `:385` daily checks/notifications ON, automatic installation/helper OFF; `:442` explains automatic eligibility and separate helper confirmation. `:565`–`:566` supplies welcome → review → find-apps, visible report opt-out, Network access and return; `:719`–`:726` handles back/return and a simulated scan. The timer, preview helper Boolean and sample connectivity are not native evidence. Coverage OFF comes from the live issue and separate consent draft, not an implemented setup control in that HTML.

## Existing source and gaps

All source references below bind to the stated base.

| Source | Reusable boundary and remaining gap |
| --- | --- |
| `Sources/PatchedApp/PatchedApp.swift:4`–`:14` | Ordinary app still composes `ClientController`/`ClientView` for explicit local-DMG inspection. No onboarding, installed-app scan, shell composition or background registration. |
| `Sources/PatchedShell/ShellNavigation.swift:3`–`:23`, `:35` | Six destinations and Updates/Network/Diagnostics tabs; `ShellDrafts` holds caller-owned display strings only, never applied/persisted choices. |
| `Sources/PatchedShell/ShellView.swift:3`–`:23` | Injected selected-content display seam; no scene, task or operational action. Reuse it after setup; do not mistake rendered navigation for productive composition. |
| `Sources/PatchedUpdatePreferences/PreferenceRecord.swift:17`–`:46` | Typed exact-release skip and automatic-exclusion record, separate from global onboarding, diagnostics and coverage choices. |
| `Sources/PatchedUpdatePreferences/PreferenceStore.swift:9`–`:19`; `PreferenceSession.swift:51`–`:85` | Exact-byte bounded CAS, Testing SPI injection, explicit fresh-fixture bootstrap and refusing ordinary store. No native per-user setup/defaults persistence adapter. Missing existing state is not permission to overwrite choices. |
| `Sources/PatchedScheduling/SchedulePolicy.swift` | `automaticEnabled` defaults false; read-only `permitsCheck` is independent of start policy. Automatic starts recheck identity, eligibility, exclusions, pause, clock, awake/idle and target-closed conditions. No daily timer or notification registration. |
| `Sources/PatchedScheduling/Attention/AttentionTypes.swift:1`–`:16`; `AttentionPresentation.swift:50`–`:53` | Injected unknown/not-determined/granted/denied/revoked permission and separate helper status; visible degraded reasons. These values are not OS observations or installation capabilities. |
| `docs/platform-launch-contract.md`, “Setup and authority” | Accepted drag-and-drop plus optional administrator-approved helper, separate App Management consent, scan/view preserved. Exact signed responsible process and per-OS proof remain UNRUN. No root/TCC bypass or silent FDA/Accessibility workaround. |
| `docs/background-helper-implementation-plan.md:37`, `:120` | Helper transport/controller and `SetupConsentController`/`PermissionStatus` are proposed H3/H7 files, absent at this base. Do not invent an installed service or duplicate helper architecture. |
| `docs/catalogue-service-implementation-plan.md:180`–`:188` | C7 discovery/matching/store/scan-location modules and gate are follow-up proposals, absent at this base. First-scan UI cannot honestly claim an installed-app scan through the DMG inspector. |

The local Network brief is a draft proposing shared revision-bound policy and refusing native adapters. The local coverage contract is a draft proposing OFF interest, explicit exact preview and send, exclusions and withdrawal. Neither is accepted main integration or an activated adapter. Coordinate interfaces with their owners before executable work; do not copy their policy into a second setup implementation.

## Proposed first-run contract

One setup session owns a typed draft and revision. Present welcome, review defaults, then explicit Find apps and transition to Updates with an honest outcome. The common layout uses system fonts, readable wrapping, keyboard traversal and visible back/return actions.

| Choice | Fresh default and meaning |
| --- | --- |
| Daily checks | ON as a preference; no timer/service registration is implied. |
| Notifications | ON as a preference; distinguish OS permission unknown/denied from the preference. Denial retains in-app results/Activity. |
| Unattended third-party installation | OFF; helper approval, setup completion, scan and notification preference never enable it. |
| Failed-update diagnostics | ON with a visible opt-out and plain description of failed app/version, error and bounded redacted diagnostic fields, never raw logs. Exclude personal paths, secrets and proxy credentials; retain a Settings control. Preference alone creates no report or initial upload. |
| Help improve app coverage | OFF, independent of diagnostics, analytics, support, helper and App Management. Turning interest ON or completing setup is not batch send approval. |
| Helper | No registration by default. Separate explicit review and administrator-approved action, with cancel/decline retaining scan/view. |

Explain that running apps quit only after explicit confirmation for the appropriate manual route; automatic work requires the target closed. Per-app automatic exclusions do not silently prevent separately confirmed manual updates. Exact-release skips retain their own bulk/manual/automatic policy. Do not silently alter either policy through setup defaults.

Network is accessible before the first scan. Open/return/back retain every choice and Network draft; returning does not submit, test a connection or start scanning. Use the same Network owner/revision as later Settings and all future consumers. Passwords never enter `ShellDrafts`, setup records, Activity or diagnostics. System/manual/direct mode and proxy errors follow PAT-2666; no direct fallback after proxy/PAC/authentication failure.

Separate local discovery outcome from catalogue connectivity. Offline/proxy failure may permit separately accepted local discovery and cached display, labelled with last successful check/freshness; it cannot become “up to date” or a successful fresh catalogue check. If the scanner or network adapter is absent, show unavailable/deferred honestly and retain view access. Retry is explicit and generation-bound; one scan is active, back/close/relaunch invalidates stale callbacks. A later callback cannot complete a newer session or reset choices.

Completion records only that the person finished setup. Persist selected choices and completion together with bounded validation, revision/CAS and successful readback before showing durable success. Fresh absence and corrupt/unavailable existing state must be distinct; corruption never silently resets opt-outs or enables installation/sharing. A failed save keeps the draft and visible failure; it grants no operation. Relaunch preserves accepted choices and does not automatically replay helper registration, reports or an interrupted scan.

App Management status is refreshed separately at foreground/relaunch and before any future mutation. Stored completion/helper approval cannot manufacture a grant or hide denial/revocation. Helper consent, registration, health and removal/disable are distinct; helper available plus permission denied, and permission granted plus helper unavailable, must render separately. Unknown observations remain unknown. Reapproval is explicit; scanner/view access remains account/helper/permission independent. Native route identity must follow the platform launch contract, not a convenient injected Boolean.

## Historical proposed narrow implementation partitions

The second `SetupStore` proposal is superseded by the CURRENT section above.
Filenames below were proposals at the historical base. Parent serialises Package/full-gate and eventual app composition changes; do not widen to helper transport, scheduler, discovery, network or coverage implementation.

1. Add pure `Sources/PatchedSetup/{SetupState,SetupSession,SetupStore,SetupCapabilities}.swift`: typed choices, stages, revisions/generations, explicit commands and independent capability projection. Proposed injected `SetupStore` has bounded read/CAS/readback; `SetupCapabilitySource` distinguishes helper and App Management observations; `SetupScanClient` reports local discovery and catalogue outcomes separately. Ordinary composition refuses effects and native observations remain unavailable. No OS/defaults/Keychain/service adapter in this partition.
2. Independent `Tests/PatchedSetupChecks/{main,StateChecks,DenialChecks}.swift` plus inert `Fixtures/Setup` cover exact state/effect traces. Parent observes meaningful compiling red and freezes interfaces, checks and vectors before a fresh implementation leaf receives source authority. Registration is separately controlled against existing package preservation checks, never weakened to permit additions.
3. Add `Sources/PatchedSetupUI/{SetupView,SetupViewText}.swift` and dedicated offscreen fixtures after the pure contract is accepted. Inject shared Network content and separate coverage disclosure via narrow callbacks; UI rendering has no dispatch/install side effects. Native focus, gestures and OS dialogs still need separate proof.
4. Only after scanner, Network, global settings/report-consent and helper/permission owners have accepted interfaces, scope `Sources/PatchedApp/PatchedApp.swift` composition separately. Preserve its ordinary read-only behaviour until that phase is released. Do not compose Testing SPI, fake permissions or preview callbacks into the productive app. Native persistence/helper registration/permission adapters require their own accepted scopes and target authority.

## Independent meaningful RED matrix

These are proposed assertions, not executed results. Setup/build failures do not count as behavioural red. Positive transitions must fail against always-refusing stubs; targeted guard-removal controls must expose the corresponding denial assertion before parent acceptance.

| Group | Required independent observations |
| --- | --- |
| Defaults and separation | Exact fresh defaults above; report opt-out remains visible. Toggle each choice independently; helper approval/permission grant/Continue never enables automatic installation or coverage sends. No initial report, analytics, licence, support or inventory request. |
| Navigation | Welcome/review/find-apps; Network before scan; back/return retain nondefault choices and redacted Network draft. Opening/editing tabs dispatches no scan, probe, registration or send. |
| Persistence/relaunch | Save/readback success survives a reconstructed session. Conflict, uncertainty, corrupt/unknown schema, wrong user/scope, missing existing state and failed readback preserve refusal and choices. Relaunch creates no replayed effect; completion never masks revoked status. |
| Permissions/helper | Cartesian states of helper unknown/declined/available/removed/disabled and permission unknown/not-determined/granted/denied/revoked. No inference between axes; declines retain scan/view, automatic remains OFF, stale observations cannot enable a start. |
| Scan/network | Explicit single scan, duplicate gesture, cancellation, late callback and generation change. Offline/PAC/proxy-auth failure stays distinct from fresh success; no direct retry fallback, no fake inventory and no cached “up to date” assertion. Network return retains choices. |
| Effect boundaries | Fake sinks observe zero helper registration, mutation, app quit, credential access, report/support/coverage send or secret logging from construction, defaults, decline, setup completion and relaunch. Explicit scan reaches only its injected read-only seam. |
| Layout/copy | Common Focused/Details semantics, light/dark and long text; separate permission/helper explanations, visible report opt-out and coverage OFF; keyboard order and accessible labels declared. Offscreen checks prove paint only. |

## Existing commands and evidence limits

Documented commands only; none was run for this preparation:

- Full repository gate: `./scripts/verify.sh` (`scripts/verify.sh:4` builds Swift).
- Shell fixture gate: `./scripts/verify-native-shell.sh`, building/running `patched-shell-checks`, never an App product.
- Related policy checks: `./scripts/verify-scheduling.sh`, `bash scripts/verify-attention.sh`, `./scripts/verify-client-flow.sh`.
- Existing preference checks: `swift run --skip-build patched-update-preferences-checks` after build; full gate also runs strict package-registration preservation controls.

No setup verification command exists yet. Parent must prospectively accept its fixture-only registration and exact command before execution. Full verification includes unrelated runtime checks; it is not authority to run them under this non runner preparation.

Pure fixtures can establish model transitions and effect denial under injected assumptions; offscreen checks can establish copy/layout. Separately authorised disposable-Mac proof must cover first launch/relaunch, exact responsible signed processes, helper decline/approval/removal, permission deny/revoke/regrant and offline/authenticated-proxy scan behaviour on each accepted OS. Actual service receipt/log-redaction proof is separate from either. Required independent OpenCode/NVIDIA whole-diff security/correctness review, relevant verification, exact-head/main CI and merged readback remain future gates. None is satisfied by this draft or grants installation, real delivery or client-release authority.
