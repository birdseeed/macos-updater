# Injected in-process scheduler

PAT-2668, source integration, 24 October 2026. The existing PreferenceSession
owns this bounded model alongside its accepted settings and original QueueModel.
Source implementation does not establish passing checks, independent review,
publication, native operation or client-release readiness.

observeSchedule accepts injected whole-second clock observations and awake,
sleep, invalidation and terminal shutdown events. No system clock, timer, sleep
observer, network check, notification or installation runs. The default owner
still refuses. A loaded V2 owner can describe a read-only check opportunity;
legacy, unloaded and storage-blocked owners cannot begin checks. Notification
choices do not gate checks. Saved pause affects automatic work, which remains
unavailable here; checks and existing manual policy retain their own behaviour.

The first usable awake observation offers one opportunity. A successful
beginScheduledCheck consumes its cadence immediately and returns one opaque
instance-bound attempt. Completion validates the exact current attempt before
performing one bounded action-time read of accepted settings bytes. Begin also
validates exact current accepted bytes. Neither operation adopts external bytes
or writes settings. Missing, malformed, foreign, unavailable or drifted storage
latches the existing refusal until explicit reload. Wrong generations, foreign
attempts, duplicates and reentrant callbacks refuse without discarding valid work.
The existing synchronous busy barrier covers store callbacks in these operations.

A subsequent begin needs at least 86,400 consistent seconds since the previous
begin. Completion, cancellation, saved edits, replay and same-state reload do not
reset that anchor. Long sleep coalesces into one due opportunity on a usable
awake observation; it produces no catch-up loop. Sleep or non-yes awake cancels
pending callbacks. Accepted byte changes and storage latches also cancel them.
Known not-committed edits retain the last accepted state and active attempt.
The scheduler never replaces or advances the original update queue; its existing
completion, failure and recovery remain available across scheduler faults.

ClockSample's existing usability and consistency predicates are reused. Boot
identity must additionally be bounded, free of control characters and equal by
UTF8 within a continuous lifetime. Rollback, wall/monotonic disagreement,
untrusted samples and changed boot latch invalid time. Ordinary observations
cannot clear that latch. Explicit valid reanchor cancels old callbacks and defers
the next opportunity for a full consistent day. Elapsed-time comparisons avoid
addition overflow at the Int64 ceiling. Shutdown is terminal for this scheduler
lifetime, even after preference reload.

scheduleRuntimeSnapshot reads cached model state without I/O. Pause timing
compares the saved absolute UTC deadline against a usable awake sample; missing,
invalid, sleeping or stopped time reports unavailable. Display-zone edits never
move the deadline. The snapshot grants no native time, freshness, notification
permission or installation authority, and automaticInstallationAvailable is
always false.

A reconstructed session loads saved choices into a fresh identity owner. It
rejects old attempts even if generation strings coincide. Cadence is deliberately
in-process only: this supplies no durable daily-run history, queue wire, actual
check result or catalogue freshness. Native clock/boot/sleep adapters, actual
check dispatch, UI/lifecycle composition and separate operating proof remain
outstanding. Native context, descriptor I/O, codecs and saved wire are unchanged.
