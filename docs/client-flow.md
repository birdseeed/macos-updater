# Read-only client flow (PAT-2600)

Current ordinary composition, 27 October 2026: [PatchedApp](../Sources/PatchedApp/PatchedApp.swift) retains one [NativeClientSession](../Sources/PatchedClient/NativeClientSession.swift) for the window and menu. The original local-DMG inspector described below remains an explicit read-only route within the [native shell](native-shell-composition.md). Applications and Updates now share real local observations and bounded installed icons; first-run/preferences, Network settings and local Activity have separate explicit actions. Local observation does not verify a release: Updates stays at ready zero with availability unknown. No productive update dispatcher, consumer transaction or report/support send is connected. The original pins, checks and historical proof limits below are unchanged.

Historical PAT-2600 snapshot, 9 October 2026: the first real client wiring exists in source. `PatchedApp` composes the shared `PatchedClient.ClientView` over the default `ClientController`, which calls the existing `ArtifactInspector.inspectLocal` for one local disk image a person chooses. This is a read-only preflight for the two compiled Firefox pins, 157.0 and 157.0.1. It is not an installed updater, a customer release or support for any other app.

## What it does

1. A person chooses one local `.dmg` file in the native chooser (one file, no folders, disk images only) and one version from `FirefoxTargets.pins`.
2. Choosing does nothing else. No file is read and nothing is inspected.
3. Check, and only Check, runs one inspection of that file against that pin, off the main actor.
4. The view shows the file's name and the exact version, then four separate results: file bytes, the app inside the disk image, the disk image itself (signature, Gatekeeper and notarisation ticket named separately) and removal of the temporary copy.

The inspector, its pins, download policy, safe file handling and mounting are unchanged and remain the only trust checks. The client adds none and relaxes none.

## What it never does

No download, network request, scan of installed apps, replacement, quit, launch, installation, catalogue trust, key or signing use, credential access, schedule or timer. No result enables installation: there is no install action, and a result claiming installation authority is refused.

## Controller contract

- `ClientController()` is the only construction available to product code and always uses the real inspector. The injecting initialiser, `ClientInspectionSummary`'s initialiser and `waitUntilIdle()` are `@_spi(Testing)`; `PatchedApp` does not import that SPI. The SPI is a test seam, not installation authority.
- Phases: `needsSelection`, `ready`, `checking`, `passed`, `notPassed`, `refused`.
- A URL that is not a local file ending in `.dmg`, or a version that is not exactly a compiled pin, is refused and clears that part of the selection, so an earlier choice cannot stay armed.
- One inspection at a time. The lease is held from Check until the inspector itself returns, including after Cancel or a changed selection, because the inspector is synchronous and is not interrupted. Check stays unavailable for that time.
- Every selection change and Cancel advances a generation counter. A result, refusal or error from an earlier generation is discarded and never shown. Changing the selection or cancelling also clears any earlier result. Dismissing the native chooser without a file calls Cancel, so a stale result is cleared; the selection is kept.
- Fail closed. A result is refused when it claims installation authority, names a different version, lacks verified bytes or an app assessment, or is not the inspector's own live assessment with fresh OS validation. A report from the real inspector is also refused unless it is the requested local inspection of the requested path and pin with no network transport.
- `passed` requires verified bytes, passed app checks and verified cleanup. A failed disk image check is shown on its own line and never hidden behind, or allowed to override, the app result. Unverified cleanup is never a pass.

## Visible words

Plain UK English in system text styles. The selected path stays inside the controller; only the file's name is shown, with control characters removed and its length bounded. Inspector refusal codes, command output and thrown errors are never shown: each known refusal has a brief plain reason and anything else is a generic refusal. A result is labelled with where it came from. Only a live result from the real inspector reads as checked now; a test double is labelled as a test double.

## Verification and its limits

`./scripts/verify-client-flow.sh` builds everything, runs `patched-client-checks` (34 cases) and confirms the full gate still runs it. `./scripts/verify.sh` includes it.

What the checks establish:

- Behaviour through labelled test doubles: inert initial state, selection without side effects, one explicit run off the main thread, no overlap or reentrancy, refusals, failures kept apart from success, stale results discarded, cleanup failure, and no route to installation.
- The real inspector through the default controller for two inputs only: a tiny wrong-size file created beneath `.build`, refused by the existing byte checks before any mount, and a missing file.
- Static guards on composition (one inspector call, SPI-only injection, the chooser's limits, system fonts, no forbidden interfaces). These are guards, not a substitute for the behavioural cases.
- Four offscreen pictures of the real `ClientView` (empty, ready, passed, refused) written beneath `.build`. The passed and refused pictures are painted from test doubles and say so in the picture.

What they do not establish:

- No genuine pinned disk image was inspected through this flow. A positive fresh inspection needs separate authority.
- `PatchedApp` was compiled, not launched. The native chooser is compiled and has not been exercised.
- Nothing here is evidence of an installed update, a customer release, a signed or notarised Patched build, or correct behaviour on another Mac.


## Installed icon observation (PAT-2660 remaining integration)

The separate Applications/Updates inventory observes icons only during its existing
explicit, synchronous scan. It reads one safe `CFBundleIconFile` leaf with an
explicit `.png` or `.icns` suffix from held `Contents/Resources` descriptors.
Missing, unsupported or unsafe input uses the generic app symbol. Icon-only
failure preserves independent application metadata; changed application ancestry
or Info.plist strips the affected claims and pixels together.

Encoded reads reserve at most 1 MiB per file and 8 MiB per scan, including failed
attempts. ImageIO admits only PNG/ICNS, at most 16 representations, positive
integral dimensions up to 1024 and at most 4,194,304 summed source pixels using
checked arithmetic. It requests only a thumbnail up to 64 pixels, then eagerly
normalises it into exactly 64 x 64 premultiplied RGBA8 pixels with aspect ratio
preserved and transparent padding. At most 64 icons (1 MiB of pixels) survive in
one snapshot; no further icon read or decode begins after that allowance is full.
Encoded buffers and decoder objects are released between application copies.
These bounds reduce decoder work; they do not isolate platform decoder internals.

The existing controller publishes pixels atomically with the copy's physical
identity, scanner session and generation. Its previous snapshot remains explicitly
stale during a rescan; old and replacement snapshots can coexist with up to 2 MiB
of retained icon pixels, plus system view rendering allocations. There is no
cross-scan cache, additional task, callback or background scanner. Both shared
rows render only those eager pixels, perform no file work and hide decorative
icons from accessibility. Icons change no trust, update readiness or installation
authority.

Verification must bind the inert PNG/ICNS and offscreen shared-row checks, and
independent whole-diff review, to the exact source bytes. These checks establish
source proof only. The painted-row check uses a hidden native host after red/blank
ScrollView controls qualify capture; it does not launch the app or establish guest
UI acceptance. The 16-representation and summed-source-pixel upper boundaries lack
independent runtime vectors. Physical appearance, keyboard and accessibility
acceptance remain separate native proof; no installed or release acceptance is
claimed here.

## Installed developer identity observation (PAT-2661)

An explicit scan may qualify the two compiled Firefox version/bundle pins with
a point-in-time developer signature. Untrusted plist claims remain separate.
The ordinary scanner never calls Security validation in its own process. It
uses the existing packaged `PatchedApp.app/Contents/MacOS/PatchedApp` in a closed
read-only child mode, dispatched before the SwiftUI App or client session is
constructed. No additional toolset product is required. A raw build executable
without that package cannot supply native inventory identity.

The selector matches a safely opened executable to the kernel vnode backing
the current mapped main Mach-O header, including region containment, device and
inode. It holds and rechecks the executable, all named ancestors and exact
package plist bytes. This is physical self-image binding, not Developer ID
authentication or proof against same-user process injection or mutable loaded
pages. A changed or unavailable binding refuses identity.

One monotonic 15-second signature budget spans all rows in a scan. Each owned
child receives at most three seconds, reduced to the remaining shared budget,
and at most 16 KiB of combined output. Both strict, all-architectures,
nested-code pinned validation and its refusal-only diagnostic run in that one
child under the same deadline. The existing bounded runner kills the owned
process group once and reaps its immediate child; an exited leader remains
unreaped while inherited pipes are open until the signalling right is consumed.
No signal is sent after reaping. Filesystem metadata I/O and platform kernel
termination latency retain their usual operating-system limitations.

The bounded request/response protocol binds a fresh nonce, complete compiled
pin, exact path, requirement/flags, full physical app/executable stamps and
plist SHA256. Duplicate/unknown JSON keys, wrong scalar types, mismatched echoes,
bad statuses, identity or timestamps, nonzero exit, stderr, timeout and overflow
all refuse. The parent reconfirms its held app/executable/plist binding on every
transport outcome. A refusal leaves developer identity unknown and allows the
inventory/controller to complete and another explicit scan to start. A fixture
child uses Testing SPI and can qualify only the explicitly fixture-provenance
inventory; it is never selected by the productive entry point.

This observation grants no notarisation, current trust, catalogue match, update
eligibility or installation authority. Synthetic subprocess checks establish
transport and cleanup behaviour only. They do not establish a native signed
bundle observation, app launch, installed operation or release acceptance.
