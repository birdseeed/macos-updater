# Durable first-run preferences

PAT-2667 source contract and local first-run integration, 24 October 2026.
Earlier durable preference source was delivered separately in
PR #123.
Verification, independent review, CI and publication of the current integration
remain parent-owned. This document describes source, not a native onboarding or
operating-proof result. See [native-first-run.md](native-first-run.md) for the
current controller, view and root route.

`PreferenceSession` is the sole preference, revision, store/CAS and queue owner.
Schema 3 wraps the unchanged canonical schema-2 string in `scheduled`, plus
`setup` and `setupMutations`. The complete envelope is bounded to 1 MiB. The
schema-1 and schema-2 codecs retain their existing formats. Every schema-3 level
must reproduce exactly when canonically encoded: malformed, duplicate, unknown
and noncanonical fields refuse. Principal and store scope bind by exact UTF8 bytes.

Setup stores failure-report preference, monotonic completion and a Network draft.
Daily checks and notifications remain only in `scheduled.settings`; the setup
receipt records all requested choices and the requested completion flag for replay.
Fresh declarations default daily checks, notifications and failure reports ON,
completion false and Network draft system/empty. These defaults do not become
accepted setup until an explicit save succeeds. Coverage sharing remains OFF and
unavailable, the optional helper remains uninstalled and unattended execution
remains unavailable. No saved value grants an OS permission or capability.

`firstRunSetup` exposes only independently read-back schema-3 choices while the
owner is unblocked. It returns nil before schema 3 or while blocked. Construction,
getters and reload never migrate or reset storage. Explicit
`saveFirstRunChoices` can migrate accepted V1 or V2 and save all choices and
completion in one CAS and one revision increment. V1 first receives default
schedule declarations; V2 pause and automatic-update declarations are preserved.
Completion is old completion OR the requested completion flag. Failure-report
opt-outs persist until explicitly changed. Missing, corrupt, foreign, unavailable
or ordinary refusing composition never bootstraps implicitly.

Network draft modes are system, direct and manualHTTP. Host is at most 254 UTF8
bytes; port at most six. Neither permits control characters. Host also refuses
`@` and `://` to avoid retaining userinfo or credential URI forms. System/direct
require empty host and port. Manual incomplete or nonnumeric ports are allowed
as drafts; this is no assurance that arbitrary free text cannot be sensitive.
There is no password, userinfo or secret field. The existing
`NativeNetworkSettingsController` remains the sole validator of accepted Network
configuration. Saving or reopening a draft never probes or changes transport.

All three mutation histories share one 128-receipt budget and one ID namespace;
none is trimmed. Same-ID matching setup requests replay at the current revision
without I/O or restoring historical choices. Changed requests or cross-kind IDs
conflict. New IDs require the current revision. Invalid IDs/drafts, overflow,
full history and envelope growth beyond 1 MiB refuse before store I/O. Caller
generation is compared by exact UTF8 bytes before any store access.

The original shared busy barrier covers save, edits, reload, scheduling and queue
starts. Accepted publication requires committed CAS followed by exact-byte,
strictly decoded readback of the full proposal. Known not-committed results retain
last accepted choices. Conflict, uncertainty or failed readback latch refusal and
hide setup/settings until explicit successful reload. Existing preference and
schedule edits preserve setup and all receipts; schedule migration replays on V3.

A changed accepted byte sequence cancels an old scheduled-check callback while
retaining the consumed daily cadence. Receipt replay preserves the current token.
The existing active queue, completion, failure and recovery retain their original
owner and guards. No second scheduler or store is introduced. This source adds
no network operation, report, coverage send, helper registration, permission
adapter, app launch, installation or unattended authority.

The new `NativeFirstRunController` opens this owner only on an explicit welcome
Continue or Reload saved preferences action. The SwiftUI view binds declarations
through `edit(...)`; it never owns a store or writes directly. Review Continue
saves partial choices before Find apps; explicit Find apps saves completion then
requests the existing read-only local scanner. Open Updates without scanning
saves completion without a scan. Construction, rendering, back, Network return
and Open app without saving perform no preference I/O. Missing-only creation and
Scan without saving choices are separate explicit actions. Failed saves retain
editable opt-outs and visible unsaved status; reload does not overwrite them.

This source integration leaves daily timer/check dispatch and notifications
unconnected. Reporting remains unavailable with no initial send; coverage and
automatic installation remain OFF/unavailable, and the optional helper is
uninstalled. Completion is never permission. Native first-launch/relaunch,
keyboard/VoiceOver, permission, offline/proxy and guest operating proof remain
outstanding. Current implementation GREEN is not claimed before parent execution.
