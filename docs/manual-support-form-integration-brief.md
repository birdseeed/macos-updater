# Manual Help & Support form integration brief

PAT-2664 owns the sole manual form, draft and client controller. PAT-2034 owns
its single intake, receipt and downstream Linear delivery pipeline. This is
source-grounded preparation against `f54c87f94ebdb8e864323ce6e8544dcf912c0bd8`,
under the non-runner continuation's refill 2, not completed integration.

Current source note, 27 October 2026: the ordinary [native shell](native-shell-composition.md) now provides local Activity/contextual Help and a no-send support destination. The source table below is the dated preparation baseline, not a current claim that only the local-DMG view exists. The manual form, shared intake contract and actual submission/delivery remain unfinished.

## First step and shared contract gaps

First, parent accepts one form-to-intake contract with the PAT-2034 owner before
any executable work. Reuse the local intake proposal at
`../../patched-mac-app-pat-2034/docs/manual-support-intake-brief.md`, commit
`cdc192aeb4a3508841574ff609827676261de428`; do not create another backend/wire.
That proposal has `requestType`, `title`, build/OS and finite diagnostic contexts,
but no topic or selected-app field. The mockup has topics “Updating an app”,
“Account or licence”, “Something else”, and optional selected app, not a title
or request-type picker. Freeze an explicit mapping or narrow amendment in the
shared proposal, including absent app/context and diagnostic opt-out semantics;
do not silently invent fields, concatenate diagnostic context into user message,
or discard topic/app routing. Keep user-authored text distinct from context.

The mockup says “No account needed”; the intake proposal's verified-principal
seam is not an accepted identity mechanism. Agree account-free request/receipt
ownership and abuse controls before native/service composition. Reply email,
UUID, fixture provenance and licensing sessions cannot supply that authority.
These are preparation dependencies, not permission to add resources or adapters.

## Actual source map and preserved boundaries

| Source | Reuse and limit |
| --- | --- |
| `Sources/PatchedShell/ShellNavigation.swift:4,34,47` and `ShellView.swift:10-24` | Existing `.support` destination and caller-owned content closure; no Help controller or transport. Reuse this destination. |
| `Sources/PatchedApp/PatchedApp.swift:1-19` | Still composes only read-only `ClientController`/`ClientView`; shell/form integration is absent. |
| `Sources/PatchedActivity/ActivityHelpContext.swift:21-42,47-116` | `ActivityDraft` preserves email/message and validated, deduplicated synthetic context blocks. Preview revalidates; 256 contexts is a local ceiling, not an upload allowance. |
| `Sources/PatchedActivity/ActivityView.swift:3-10` and `docs/activity-history-integration.md` | Isolated view; row probe is Testing SPI, not an operational Get help callback. Future routing needs its own intent seam and zero-send proof. |
| `Sources/PatchedLicenceSupport/SupportClient.swift:2-12` | Operator licence lookup/actions with refusing default; separate from personal Help submission. Do not repurpose. |
| `services/catalogue/protocol/support-request-v1.{mjs,schema.json}` | Closed fixture coverage wire: `app`, `notes`, `consent`, `coverage-research`, `patched-catalogue-support`; lacks manual topic/contact/message/diagnostic envelope. Preserve schema, implementation and every existing assertion exactly. |

Approved HTML source, read without launching a browser:
`/Users/example/.codex/visualizations/2026/10/12/01a13097-c8b0-7bb2-877b-af3fb335da21/patched-updates.html`
(`newModel`, `helpWithEvent`, `supportScreen`). It supplies layout, topics,
email/message, default ON checkbox, preview and draft-preserving errors.
Sample reference `DEMO-1042`, sample logs and connectivity-driven confirmation
are illustrative only, never service evidence or native implementation.

## Proposed form and controller behaviour

Use one owner for editable topic, reply email, message, app routing, diagnostic
choice and preview; preserve them across navigation, offline/proxy/server errors
and relaunch through a separately accepted private draft store. The existing
`ShellDrafts` values are settings display strings, not this persistence adapter.
Get help prepares that same draft, preserving prior email/message and checkbox;
deduplicate event/attempt/revision context without replacing user text or sending.
Opening Help, previewing, editing, switching tabs or reconnecting sends nothing.

The 12 October ruling makes diagnostics ON for a new manual draft only. Restore
an existing OFF choice unchanged. This narrow override grants no coverage,
analytics, crash or automatic-report permission. Project finite, bounded context
from accepted typed observations; mark existing Activity input synthetic and
never promote it to native provenance. Preview exactly the proposed outgoing
diagnostics, excluding credentials/tokens, personal paths, full inventory and
arbitrary installer output. User message may itself contain personal information
or secrets: show it literally and disclose the boundary without claiming anonymisation.

Opt-out removes diagnostic fields/content from the outgoing request as well as
the UI preview. Under the shared draft wire use `diagnosticsIncluded:false` and
`diagnostics:null`; never retain generated context in message/title/app routing.
PAT-2034 must independently reject false plus non-null and unexpected diagnostic
fields. Genuine user-entered message remains user text, not silently rewritten.
Agree whether selected-app detail is diagnostic or separately disclosed routing
in the first-step contract; opt-out cannot leak it through a side channel.

Validate topic/mapping, single reply address, nonblank message, Unicode, exact
fields and byte/scalar bounds before explicit Submit. Preserve rejected drafts;
never truncate Activity input to fit. The shared proposal's 32 KiB body, 4000
message scalars/16384 UTF8 bytes, 320-byte email and 16-context/4096-byte diagnostics
are draft values, not activated policy. Payload/rate limits, access, retention,
deletion/backup/tombstone horizons and approved destination require acceptance
before real storage/delivery. Do not repeat or implement PAT-2034's backend here.

Explicit Submit freezes exact bytes, request UUID and digest in an immutable
attempt. Retry after offline, proxy, server failure or unknown acknowledgement
uses that same attempt; service deduplication returns one original receipt for
same scope/purpose/ID/bytes and conflicts on changed bytes. Disable overlapping
submission and fence stale callbacks by attempt/generation. Later edits remain
a separate editable draft and cannot rewrite an uncertain in-flight request;
resolve uncertainty before permitting an edited replacement submission.
Show received confirmation/reference only from validated durable intake
acknowledgement after committed readback. Timeout, HTTP success alone, malformed
or foreign receipt, reachability and enqueue do not prove receipt. Linear delivery
and email reply remain separate service states; no delivery/reply promise from a fixture.
Replies need the approved service destination and delivery adapter, retaining
credential/resource/customer-message gates; typing email grants no reply authority.

All sends/retries use PAT-2666's one shared Network policy and current revision,
with actionable Settings → Network errors and no direct fallback. Its local
`../../patched-mac-app-pat-2666/docs/shared-network-policy-integration-brief.md`
is preparation, not an adapter. PAT-2665's local
`../../patched-mac-app-pat-2665/docs/automatic-failure-report-integration-brief.md`
may supply safe report correlation/state to Get help; never resend that report,
inherit its ON state, or require it for manual Help. PAT-2655 coverage is separate.

## Narrow later partition and independent RED matrix

Propose `Sources/PatchedHelpSupport/{HelpDraft,HelpSubmission,HelpSession,HelpAdapters}.swift`
for pure state, immutable attempts and refusing draft/intake/network/clock/ID seams;
`Sources/PatchedHelpSupportUI/{HelpController,HelpView,HelpViewText}.swift` for the
sole form; `Tests/PatchedHelpSupportChecks/` for independent checks and inert vectors.
Parent serialises Package/gate registrations and later shell/Activity/App wiring.
No native persistence, transport, service route or productive composition in the
first fixture slice. Independent author prepares compiling positive/adversarial
checks; parent observes meaningful red and freezes interfaces/checks before implementation.

| RED group | Required observations |
| --- | --- |
| Form and routing | Every topic and absent/present app maps exactly; Get help preserves text/OFF, deduplicates contexts and uses one owner. Opening/editing/preview/navigation causes zero sends; valid explicit Submit reaches a fake sink so always-refusing stubs fail meaningfully. |
| Privacy at both boundaries | ON preview equals bounded wire; OFF removes generated diagnostics at UI and captured outgoing bytes; backend rejects injected false-plus-data/unknown fields. Secret/path/full-inventory/raw-child canaries never reach body, headers, URL, logs or errors. |
| Validation and drafts | Empty/invalid/email-header/Unicode/control/limit cases refuse without truncation; draft store failed/uncertain write, corrupt read, relaunch and tab changes preserve or truthfully report unavailable state. Fake durability is not native fsync proof. |
| Receipt and retries | Lost ack, server commit/client crash, parallel retry, same-ID changed bytes, foreign/malformed receipt and stale completion produce one durable effect and truthful state. Edited drafts cannot mutate frozen retries or clear on another attempt's ack. |
| Network and presentation | Offline, proxy 407, origin/server failure and revision changes retain draft/ID/choice with no direct fallback; literal malicious text, long content, light/dark/offscreen geometry and checkbox accessibility remain usable. Native focus/VoiceOver need later native proof. |

Mutation controls must bypass each decisive privacy/receipt/deduplication guard
and fail an independent assertion; missing imports/setup failures are not red.
Existing commands, documented only here: `./scripts/verify-support-request-protocol.sh`,
`swift run --skip-build patched-activity-checks` after build,
`./scripts/verify-native-shell.sh`, full `./scripts/verify.sh`. No focused Help gate
exists yet. No checks/builds were run by this preparation. Parent acceptance,
independent canonical security/correctness review, relevant local verification,
required exact-head/main CI and merged readback remain executable-work gates.
Current selector: canonical root AGENTS.md, 19 October 2026, direct NVIDIA HTTPS primary with approved independent fallback; OpenCode is not required.
Fixtures, offscreen rendering, authorised disposable-Mac gestures/storage and actual
service/email results must be recorded separately. No runtime/VM/runner recovery,
app/helper launch/install/signing, credentials/resources, real delivery or release
is authorised here; PAT-2664 remains incomplete.
