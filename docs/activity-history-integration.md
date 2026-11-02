# PAT-2663 bounded Activity implementation

Phase B round 1 of five total implements only the five frozen source bodies and
private helpers. The ordinary owner remains permanently unavailable. Positive
history and presentation describe synthetic fixture observations only; no native
producer, filesystem adapter, application integration or transport is present.
The implementing leaf ran no build, checks, provider review or publication steps.
All checks, interfaces, limits, fixtures and other source remain frozen.

The parent independently compiled and observed group 1 before releasing these
bodies: 231 cases, 148 meaningful failures and 83 passes, including all 20 setup
controls. The original preparation forecast below remains historical and was off
by one. No resampling or round reset occurred. Implementation is unverified until
the parent runs the prospective gate, reviews actual changes and completes the
remaining acceptance, canonical NVIDIA review and publication gates.

Static registration forecast:231 cases,20 setup controls,149 intended behavioural
failures with refusing stubs and82 expected passes. These were unobserved estimates,
not a compiling-red result; the observed parent counts above are authoritative.

Parent-only Package registration:

```swift
.library(name: "PatchedActivity", targets: ["PatchedActivity"]),
.executable(name: "patched-activity-checks", targets: ["PatchedActivityChecks"]),
.target(name: "PatchedActivity"),
.executableTarget(name: "PatchedActivityChecks", dependencies: ["PatchedActivity"],
                  path: "Tests/PatchedActivityChecks"),
```

Place products and targets in their respective existing arrays. Proposed parent
commands: `swift build --product patched-activity-checks`, then from repository root
`swift run --skip-build patched-activity-checks`. No script/gate registration is
authorized to this leaf. Parent should count setup versus behavioural results
from the runner and preserve the exact output and source/check/fixture hashes.

ActivityWire encodes/decodes the closed canonical versioned record described by
Fixtures/Activity/README.md. Codable conformance is descriptive and does not
replace strict ActivityWire validation. Records are observations only. Source
ActivityHistoryOwner default must remain permanently unavailable. Testing SPI
construction injects ActivityStore and a principal/store binding. SPI bootstrap
is explicit fresh-fixture initialization, never automatic missing-store repair.
SPI appendSynthetic requires exact correlated synthetic readback for succeeded
and restored events; it never issues native installed evidence. Readback after
CAS precedes any visible save acknowledgement. Uncertain/failed writes refuse;
new owner/reload/replay reconciles exact bytes exactly once. Reentrancy and
revision/sequence overflow refuse. No await or native filesystem adapter exists.

Resolved records expire at age >= 2592000 elapsed seconds. Unprovable/unknown
or rollback clock holds cleanup and discloses unavailable age. Active,
incomplete, needsRecovery and every correlated unresolved attempt stay held.
Read/relaunch/retry never extends resolution anchors. Protected quota exhaustion
refuses new appends. Selection only touches Activity fixture bytes, with no
journal/backup/replay/service deletion API. Presentation reports actual retained
epoch range, missing dates, 30-day policy, count and 2 MiB limits. Every successful
synthetic view is labelled `Synthetic fixture only`.

Get-help append and explicit encodeDraft/decodeDraft enforce email <=320 UTF8
bytes, user message <=16384 UTF8 bytes and at most256 contexts. Overlimit or
UInt64 context revision overflow refuses without truncating existing bytes.
Codable is descriptive; source draft serialization must use the validated APIs.
Fixture draft persistence stays separately named from the event record.
Get-help append preserves caller email/message bytes, emits separate blocks
keyed by event/attempt/context revision, and deduplicates through reconstructed
drafts. Context contains only finite status/reason/report labels and strictly
canonical UUID correlations. App names, targets, versions/builds, child text,
paths, secrets, inventory and raw journals are omitted rather than purportedly
sanitised. Preview validates reconstructed blocks again; arbitrary raw text
refuses. Missing/mismatched report receipts remain missing. Report status is a
fixture observation, never a send receipt created by Activity. There is no
transport/send/enqueue/mail/installation/App callback in the API. Thus these
operations are structurally absent; future Help integration needs its own
instrumented zero-send proof and accepted native draft ownership.

ActivityView is an isolated SwiftUI ScrollView with system fonts and literal
text. Testing SPI rowProbe is an offscreen-only check-owned content/geometry
probe to accompany actual rows. It is not an intent callback. Check capture uses
an inactive prohibited process, never-ordered NSWindow/NSHostingView, guards
before/after layout and capture, bounded 0.20s settling and actual bitmap with
only integral 2...4x normalization. Only the owned window closes. Row identity,
model state text, actual geometry and content pixel differences are asserted;
PNG creation alone is insufficient. Probes establish actual row slot painting,
not literal glyph correctness, every text bound or VoiceOver. Parent must visually
inspect the retained light/dark/long-text PNGs. Native focus/VoiceOver/real navigation,
installed outcomes, native storage isolation and real support delivery remain
unproved. PAT-2690 restoration and B4/P3/runtime work remain outside scope.

Parent-requested pre-freeze setup correction: OwnedStore revalidates the actual
opened nonblocking/no-follow FD as a current-UID0600 single-link regular file
of0...3MiB before allocation, then requires an exact read andEOF plus final
metadata checks. A rename acknowledgement follows fsync on an actual identity-
checked0700 owned-directory FD. Post-rename sync failure throws uncertain.
Eight additive setup controls retain every previous assertion. These checks
establish bounded fixture mechanics only, not atomic CAS against malicious
same-user writers, authenticated native storage or hardware durability proof.
Original14-file hashes are retained in the parent evidence correction note.

A separate check-owned40x40 native probe independently requires GeometryReader
background/onAppear bounds to be observed within720x480, width/height39...40,
and at least1500 actual magenta pixels. Product-row geometry uses the same
mechanism; failure of this setup blocks attribution to the source view.

## Round 2: visible reason and viewport repair

The parent observed all original 231 checks passing after round 1. Additional
independent reason coverage then exposed eight missing visible reason fields:
group 3 built successfully and recorded 240 cases, eight meaningful failures and
232 passes, including all 20 setup controls. Original assertions were unchanged;
the nine additional checks and their registration were frozen before this repair.
The parent also inspected an actual dark empty-state PNG and found a clipped
provenance header and missing policy; wider mixed-row content concealed that
layout problem. Passing row probes did not establish readable header content.

Round 2 of five total changes only ActivityPresentation, ActivityView and this
document. Each row retains its prior details and adds one literal Reason field
with an explicit finite label. The view takes its content width from the offered
viewport through a root GeometryReader; headers and rows wrap vertically using
system fonts and literal text. No fixed product width, interface, check, fixture,
capture helper or operating callback was introduced. Synthetic provenance and
the ordinary unavailable boundary remain unchanged.

The implementing leaf ran no build, checks, provider review or publication.
The parent must run the prospective 240-case gate and inspect new light/dark
empty, unavailable and long-text specimens before accepting this repair. Full
verification, canonical NVIDIA review and publication remain separate gates.

## Native navigation implementation slice, 24 October 2026

This later slice supersedes the historical absence of application integration
above only for local history navigation. `NativeClientSession` owns one inert
`NativeActivityController`. Explicit load/create/retention actions use the
existing native context, retain a successful owner and invalidate both owner and
displayed snapshot on errors or invalid generations. Presentation reuses exact
`ActivityPresentation.make` rows and adds descriptive last-loaded provenance.
The injected session remains the same Testing SPI object even after invalidation.

`ActivityView` preserves its inert default and row-probe constructors. Its
callback constructor supplies a native Get help button for each exact row; only
an explicit click calls the closure. Session intent validates the complete
current row and event/attempt membership before selecting an immutable event,
revision and provenance and routing to Help & Support. Literal selected context
is displayed locally, preserving drafts and the no-message/no-report-sent
statement. Root observation follows the retained Activity controller directly,
so later loads and handoff changes can redraw the same hosting root.

No native event producer, transaction, report transport or automatic storage
operation is added. The implementation describes locally selected history and
does not send a message or report. It does not establish production of actual
native events, per-user isolation, guest relaunch or installed success. The
separately accepted PAT-2710 mechanism governs future event production. Build,
full verification, independent review, CI and delivery acceptance remain
separate requirements; source and fixture checks alone do not establish native
event production or release readiness.
