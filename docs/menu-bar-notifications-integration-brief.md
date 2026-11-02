# Menu-bar and background notification integration brief

Current menu source, 27 October 2026: [PatchedApp](../Sources/PatchedApp/PatchedApp.swift) now composes `MenuBarExtra` and the main window over the same `NativeClientSession`. The [native menu integration](native-menu-integration.md) provides explicit Scan/navigation actions and shared local observation status, plus close/reopen source wiring. The dated source table and future notification contract below remain historical preparation, not a current claim that no menu exists. Background checks, OS notification permission/delivery and productive update execution remain unavailable; source and offscreen checks do not establish the native notification journey.

PAT-2670 source preparation, 16 October 2026. First implement an inert, independently checked presentation and intent contract; native lifecycle and notification adapters follow only after their dependencies and target authority are accepted. At that preparation snapshot, no implemented menu bar, background component, OS permission, notification delivery or installed proof was supplied.

## Authority and source basis

Live PAT-2670 was read for this preparation. Its explicit first step is a source-grounded bounded brief. The controlling root `.claude/linear-runs/AUTHORISED-SCOPE.md` and `.claude/linear-runs/evidence/non-runner-continuation-20261015/authorised-scope.json` permit autonomous non-runner preparation, including PAT-2670 in refill 1. Life exclusively owns PAT-2689/runtime/VM/runner recovery. Preserve B4 holds, P3 exclusion, exhausted attempts and existing caps. Parent owns acceptance, Git, Linear and publication; this slice creates only this document.

Source baseline: `f54c87f94ebdb8e864323ce6e8544dcf912c0bd8`. Read canonical root and repository `AGENTS.md`, queue-run instructions, and these approved HTML sources:

- `/Users/example/.codex/visualizations/2026/10/12/01a13097-c8b0-7bb2-877b-af3fb335da21/patched-updates.html`
- `/Users/example/.codex/visualizations/2026/10/12/01a13097-c8b0-7bb2-877b-af3fb335da21/patched-homebrew.html`

Both are simulations. Updates provides Focused and Details, menu access, preferences, shared Activity and simulated lifecycle controls. Homebrew supplies a separate managed section and one shared `brew()` action for app/menu, with simulated progress and manual handoff. Preserve their common behaviour without requiring an exclusive Focused-versus-Details design choice; timers and preview toggles are not native specifications or proof.

| Actual source | Reuse and gap |
| --- | --- |
| `Sources/PatchedApp/PatchedApp.swift` | One `WindowGroup` composes `ClientController`/`ClientView`; no menu scene, shell, agent or notification composition. |
| `Sources/PatchedClient/ClientController.swift` | Explicit local disk-image inspection only, with generation-based stale-result rejection and a single running lease. It is not installed-update discovery or a scheduler owner. |
| `Sources/PatchedShell/{ShellNavigation,ShellView,ShellBrand}.swift` | Display-only destinations, injected selected content and drafts, canonical geometric P and system type. No operational callbacks or storage authority. Reuse mark geometry as monochrome template artwork in menu UI. |
| `Sources/PatchedScheduling/{SchedulePolicy,QueueModel,Clock}.swift` | Pure injected policy and principal-bound serial queue. Pause affects new automatic starts; read-only checks remain separate. Typed snapshots are not durable storage. No OS timer, agent or execution authority. |
| `Sources/PatchedScheduling/Attention/{AttentionTypes,AttentionController,AttentionPresentation}.swift` | Pure exact-binding attention, stale-observation rejection and injected readback. Its permission model concerns update/App Management capability, not OS notification authorisation. Do not conflate them. |
| `Sources/PatchedActivity/{ActivityEvent,ActivityHistory,ActivityPresentation,ActivityView,ActivityHelpContext}.swift` | Synthetic history, bounded records and injected CAS store; ordinary `ActivityHistoryOwner()` is unavailable and writes are Testing SPI. No native event producer or notification fallback persistence exists. |
| `docs/background-helper-{architecture,implementation-plan}.md` | Accepted planning boundaries and future H2 user-agent/notification adapters, H6 summaries and dedup. These proposed modules are not installed services. Reconcile their older source basis before adoption. |
| `Package.swift`; `scripts/verify.sh` | Shell, Activity and scheduling libraries/checks exist separately. No dedicated menu/OS notification target or gate is registered. |

## One owner, explicit actions and truthful status

PAT-2661 should own the shared current update projection and action boundary, with PAT-2668 owning preferences/scheduling integration. This ticket consumes that owner rather than constructing a second updater, scanner, queue or automatic-start path. A menu opening, window recreation, destination selection, notification click or Check must never install, quit an app, change policy or broaden a previously approved action.

The native monochrome P has an accessible status label and textual summary. Define a deterministic pure projection with orthogonal facts so pause, stale data and attention cannot hide each other:

| State | Required meaning |
| --- | --- |
| Ready | Current accepted observation identifies eligible Patched updates; show ready count, never downloaded/queued-as-installed. |
| Needs attention | Current unresolved/refused/recovery/permission state remains visible with its reason and review route. |
| Checking | An actual owned check is outstanding; repeated requests coalesce, and stale results cannot overwrite newer state. |
| Cached | Last accepted observation is retained with known age or “age unavailable”; never imply a fresh check or current eligibility. Missing data means unavailable, not zero updates. |
| Paused | Name what is paused and any accepted deadline. Automatic-install pause does not imply daily checks are paused or an active recovery was stopped. |

Provide **Check**, **Review Updates** (or **Open Updates**), **Activity** and **Settings**. Check requests discovery only through the common owner. Review opens current Updates without starting anything. Activity selects the relevant current event/attempt; Settings selects the appropriate section without applying drafts. Keep external-managed, skipped, deferred/attention and Patched-ready counts distinct. Any future ready-only Update all uses the existing explicit accepted action and eligibility checks; no menu-specific executor.

Consume the local PAT-2674 packet `../../patched-mac-app-pat-2674/docs/manual-homebrew-route-integration-brief.md`, commit `6559ec2` (local preparation, not main). Its supported native set is **empty**. Reserve the same explicit per-app **Update with Homebrew** intent for app and menu, disabled with a reason/manual handoff until accepted support exists. Homebrew keeps ownership and runs only as its verified owning user, never the privileged helper. Exclude it from Patched Update all and unattended scheduling; no installation/adoption, automatic retry, hidden prompt or Patched recovery/verification guarantee. Reuse PAT-2674's coordinator rather than defining brew execution here.

## Background lifecycle, notification grouping and click routing

When the optional background component is enabled and operating, daily checks must continue with the main window closed. When OS notifications are allowed and the notification preference is on, publish grouped available/completed/attention summaries from accepted current observations. OS permission governs delivery, not whether read-only discovery may occur. Denied, revoked, unknown or disabled notifications leave results available through Activity and in-app status; never silently request permission or repeatedly prompt during checks. Actual Focus/privacy/session restrictions may suppress delivery even after permission is granted.

Explain three independent operations: closing the window leaves an enabled background component operating; quitting/disabling background operation stops its future checks/delivery; pausing automatic updates prevents new automatic installs while preserving checks, manual review and safe recovery. The exact background-quit/control mechanism and daily cadence need accepted native composition. Never promise operation while absent, stopped, asleep or outside an eligible user session, or promise wake, restart, logout or login delay. Window close/quit must not blindly cancel a live transaction or Homebrew child.

Proposed notification identity binds principal/session, group kind, target and full release/route identity, observation revision or operation attempt, and material status/reason. Dedup unchanged conditions across repeated checks, lost replies and relaunch using an accepted per-user durable store. A new release, changed reason or newly confirmed completion may create a new summary; app/menu both observe the same dedup owner. Missing/corrupt/uncertain persistence must not cause a notification storm or manufacture success. Coalesce bounded groups and remove superseded pending items; store no secrets, raw logs, paths or command output in notifications.

A click carries only an opaque bounded lookup identity. Resolve it against the current owner's principal/session and actual state before routing. Available opens current Updates for matching candidates; completed opens the exact retained Activity attempt; attention opens its current reason/recovery/permission review. A stale, deleted, resolved, changed-release or foreign-session click opens an honest current overview/unavailable explanation, never reconstructs old eligibility or starts an update. Unknown payloads refuse; do not trust deep-link paths, notification titles or embedded actions as authority.

## Proposed partition and interfaces

All names below are proposals, not existing APIs or implementation permission. Parent accepts interfaces and sequences shared files with PAT-2661/2668/2674.

| Slice | Proposed files and boundary |
| --- | --- |
| Pure projection/intent | `Sources/PatchedMenuBar/{MenuProjection,MenuIntent,NotificationPolicy,NotificationRoute}.swift`: injected immutable current snapshot; finite status, count and route types; no OS/storage/executor. |
| Independent checks | `Tests/PatchedMenuBarChecks/main.swift`, `Fixtures/MenuBar/README.md` and bounded vectors; proposed `scripts/verify-menu-bar.sh`. Inject fake clock, owner, permission, lifecycle, notification sink and dedup store. |
| Shared-owner integration | Future accepted PAT-2661 owner supplies revision, principal/session, release/route, provenance, observed age, counts, active attempt and explicit intent handling. No new authority constructor or Testing SPI in ordinary app composition. |
| Native menu adapter | Proposed `Sources/PatchedMenuBarNative/{MenuBarView,WindowRouter}.swift`: native template mark, keyboard/VoiceOver controls and window routing. Choose scene/API compatible with the repository's macOS 13 floor during implementation. |
| Background notification adapter | Reconcile proposed `Sources/PatchedBackgroundAgent/{AgentController,NotificationController,UserPolicyStore}.swift` from H2; inject accepted OS authorisation/delivery and per-user durable dedup. No parallel agent design or root notification producer. |
| Activity integration | PAT-2663 accepts a real producer/store/provenance adapter separately. Synthetic success records cannot supply native completion notifications; external Homebrew provenance must remain explicit. |
| Composition/registration | Parent sequences `Sources/PatchedApp/PatchedApp.swift`, `Package.swift` and `scripts/verify.sh` only after accepted contracts, checks and review. Service registration, signing and installed-target proof remain separately gated. |

## Independently authored RED matrix

Author compiling tests against refusing stubs, observe meaningful assertion RED, then parent freezes exact interfaces/checks/fixtures before implementation. Setup/compiler failure is not RED. Assert zero unexpected update/helper/child calls in all navigation, permission and refusal rows. Parent independently checks deliberate single-defect mutations expose the corresponding assertion, then restores frozen bytes.

| Fixture family | Required invariant |
| --- | --- |
| State and counts | Unknown/cached/checking/paused/attention combinations, partial scan and external/skipped entries cannot claim fresh-ready or installed status; both layouts and menu consume identical revision/counts. |
| Inert routes | Construction, paint, menu open, Review, Activity, Settings and notification click make zero update starts; Check invokes only one common check. Unknown actions refuse. |
| Concurrency | App/menu/check timer double requests, late results, queue recovery and Homebrew intent races cannot duplicate/broaden operations or bypass one owner. Window recreation preserves operation identity. |
| Permission/lifecycle | Enabled/absent/stopped background, close-window, background quit, auto pause, sleep/session changes and denied/revoked permission preserve correct checks-versus-delivery distinctions and Activity fallback. No prompt loop or blind child kill. |
| Group/dedup | Repeated unchanged state, restart, lost delivery reply, corrupt/uncertain store, changed release and partial batch produce bounded accurate groups, no storms, no false completion and no cross-user leakage. |
| Click resolution | Stale/deleted/resolved target, release/route substitution, foreign session, malformed/oversized payload and missing history cannot start actions or route to invented results. Re-resolve real current state. |
| Privacy/accessibility | Notification fields reject secrets/control content and respect bounded text/privacy choices; native monochrome mark has a useful status label, keyboard routes and long/localised text remain usable. |
| Homebrew boundary | Empty support set refuses execution; app/menu share one per-app intent; managed entries never enter Patched batch/schedule/helper routes or inherit Patched success/recovery receipts. |

Later authorised verification commands already present, **documented only**:

```sh
./scripts/verify-client-flow.sh
./scripts/verify-native-shell.sh
./scripts/verify-scheduling.sh
swift run --skip-build patched-activity-checks
./scripts/verify.sh
```

These include builds/offscreen checks and have not run for this document. Pure green establishes model behaviour only. Later separately approved native evidence must cover actual closed-window daily checks, quit/pause distinctions, delivered grouped notifications, denied/revoked/session/privacy cases, stale clicks, persisted dedup, real Activity routes, queue concurrency and accessibility on named disposable Macs. Preserve failed attempts and distinguish fixture, offscreen, disposable and actual service outcomes. Required whole-diff correctness/security review under the current canonical root AGENTS.md and `.claude/skills/run/references/review-gate.md`, repository gates, exact-head/main CI and merged readback remain; no hosted CI, push, runner/VM work, real app/helper launch/install/signing, credentials, network probes, customer/provider delivery or release occurs in this preparation.

## 17 October: pure menu summary component

`Sources/PatchedShell/MenuSummary.swift` now supplies immutable textual status
from explicitly supplied display facts. Ready, externally managed, skipped and
deferred counts remain distinct. Missing or negative counts display unavailable;
cached observations label every count cached and retain a known nonnegative age
or an unavailable-age explanation. Checking, automatic-installation pause and
attention remain independently visible, including when counts are unavailable.
The accessibility summary exposes the same ordered facts. Construction performs
no operation and the freshness input supplies no update authority.

The existing shell checks include independent boundary and combination cases.
Local fixture results and independent review are recorded on PAT-2670; this
component supplies no native menu, shared-owner integration, action handling,
background lifecycle, notification delivery, persistence or installed proof.
Required platform CI and operating acceptance remain separate.
