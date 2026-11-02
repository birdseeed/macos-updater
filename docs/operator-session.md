# Operator session: read-only local artifact check

**Status: source only.** `OperatorSession` and `OperatorSessionView` are implemented in `Sources/PatchedOperator`, and `PatchedOperatorApp` wires the default session to the view. The gate builds the app and paints the view offscreen. The app has not been launched by a gate or an agent, has not been released, and no genuine disk image has been verified through this surface. This file describes what the code does; it is not evidence of a native run.

## What the operator can do

1. Choose one local disk image through the system chooser: one file, no folders, no multiple selection.
2. Choose one of the compiled Firefox pins, 157.0 or 157.0.1, taken from `FirefoxTargets.pins`. Nothing else can be chosen.
3. Click Verify. Only this click calls `OperatorVerification.verifyPinnedArtifact(version:path:)`, once, away from the main actor.

Choosing or changing the file or version, dismissing the chooser and clicking Cancel run nothing. Each of them, and each new Verify and each refusal, immediately drops the held receipt and any earlier result or refusal. Creating the session or showing the view runs nothing: there is no startup work, timer, network request, download, scan, app launch, installation, key discovery or credential access.

## One run at a time

The verifier is synchronous and cannot be interrupted. The session holds a single-run lease from Verify until that worker has really returned, including after Cancel or a changed selection; Verify stays unavailable until then, so two inspections never overlap. Every selection, cancel and Verify advances a generation counter, and a success or refusal that arrives for an earlier generation is discarded without being shown.

## What is held and shown

- The default session keeps the actual output-only `VerifiedArtifactReceipt` privately. It adds no receipt constructor, decoder or new trust route, and the verifier's own checks are unchanged. The visible summary is derived from the receipt's own fields.
- The app checks and the disk image's signature, Gatekeeper and stapled-ticket results are four separate lines. A failing disk image result is shown as it was observed, apart from the app result.
- Cleanup has its own visible line, apart from the app and disk image lines. A successful receipt with confirmed cleanup shows "Cleanup confirmed". A typed cleanup failure (or a summary reporting cleanup false) is still a refusal with no receipt or success shown, and separately shows "Cleanup not confirmed". No cleanup line appears when idle, ready, verifying or after any other refusal, and any selection, cancel or new Verify clears it.
- A result whose cleanup was not confirmed is a refusal, never a success.
- Live, fixture and replayed provenance have distinct lines. Only a live receipt that itself records a fresh macOS validation says so.
- A refusal shows `Refused.` and the one plain sentence of its `OperatorFailure` case from `OperatorViewText.refusalReason`; any other error shows `The step was refused.` Raw errors and paths are never displayed. The file line shows the last path component only, stripped of control and formatting characters and limited to 80 characters. The version is shown exactly.
- Signing and publication are always unavailable, each with its own reason: no signing capability, and no publication destination. They are text only: the session has no control, callback or code path for either.
- A passed check grants no installation authority and the surface says so.

## Check-only display seam

`OperatorSession.init(displaySummaryVerifier:)` and the `OperatorSessionSummary` initialiser are `@_spi(Testing)`. They let the checks return a display summary without a receipt. Such a session holds no receipt, every summary built this way is labelled `Test double` whatever provenance it names, including live, and its status reads `Test double result. No file was checked.` Nothing in the library accepts a summary in place of a receipt. `PatchedOperatorApp` does not import the SPI.

## Checks

`./scripts/verify-operator-session.sh` builds the package and runs `patched-operator-session-checks`: 19 cases covering selection, unsupported input, exactly-once verification away from the main thread, no overlap, stale success and refusal, cancel, typed and untyped refusals, provenance labels, separate container lines, cleanup refusal, four offscreen paintings of the actual view and source composition guards. The default verifier is exercised only with a ten-byte file and a missing file, both refused before any mount. Writes stay beneath `.build`. The full `./scripts/verify.sh` runs this script after the inherited gates.

## Limits

- No genuine pinned disk image has been verified through the session, and the chooser has never been presented: neither was performed: the app was built and painted offscreen only, never launched.
- A running verification cannot be stopped; Cancel disowns its result and waits for it to end.
- The existing `OperatorController` and `OperatorView` fixture surface and their checks are unchanged but are no longer what `PatchedOperatorApp` shows.
- The receipt's limits in `docs/operator-runbook.md` still apply: it binds bytes and one physical file at the times they were checked.
