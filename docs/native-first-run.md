# Native first-run source integration

PAT-2667, 24 October 2026. This local source integrates the first-run controller
and SwiftUI route over the existing preference, navigation, application and
Network owners. Earlier durable preference source was delivered separately in
PR #123. That source
delivery and this integration are distinct from native first-launch acceptance,
installed behaviour or a client release.

`NativeClientSession` retains one `NativeFirstRunController`, sharing its exact
`ShellNavigation`, `LocalApplicationsController` and
`NativeNetworkSettingsController`. The root observes both the session and its
first-run controller directly. While setup is presented it shows
`NativeFirstRunView`; dismissal restores the existing shell, destinations,
Network settings and local-disk-image inspection sheet and toolbar. The older
Testing initializer suppresses setup only when no explicit controller is supplied,
preserving its existing fixtures. Explicit injection retains the supplied owner.

Construction and painting do not open preferences, scan applications, refresh
Network information, inspect a disk image or save anything. The view has no
lifecycle dispatch or second store/controller. It uses system fonts, the existing
button style, wrapping text and scrolling at a minimum 680 by 520 points.
Keyboard shortcuts and accessibility labels are declared; their presence is not
proof of native keyboard behaviour, VoiceOver order or absence of clipping.

## Explicit actions

Welcome Continue calls `advance()`, which explicitly opens and reloads the local
preference owner before showing review. The factory may create its safe private
container, but never creates or resets the preference record implicitly. The
native factory's identity and filesystem boundaries remain those described in
[native-preference-storage.md](native-preference-storage.md). Its earlier
statement that no UI uses the factory describes the pre-integration source;
this controller is now the explicit call site.

Review offers daily-check, notification and future failed-report declarations,
all initially ON with visible opt-outs. Only `edit(...)` changes these drafts.
Save choices and continue requests a partial save through the sole
`PreferenceSession` CAS/readback owner before showing Find apps. The next Find
apps action saves completion, opens Updates and requests the retained read-only
local scanner. Open Updates without scanning saves completion and navigates
without scanning. Local scan results are unverified observations, with unknown
update availability; no catalogue connection or fresh update check is implied.

Back, Network return and dismissal retain choices without saving. Network
settings composes the existing `NativeNetworkSettingsView` over the same owner;
there are no duplicate setup fields, validator or transport. Its own explicit
apply/refresh controls retain their existing semantics. Opening or returning
from the screen does not invoke them. The saved setup Network value is a draft,
including an incomplete port, rather than an accepted connection choice.

The view displays the controller's finite local state, save status and status
text. Missing and unavailable storage are distinct. Only a missing result
exposes Create fresh preferences, and the controller rechecks its missing-only
authority. Corrupt, existing or unavailable storage is never reset. Reload saved
preferences is explicit; failed-save drafts and opt-outs survive reload and
latched failures remain visible. No success is inferred from a button press.

If the preference factory fails, only a later explicit Reload saved preferences
retries acquisition. A successfully acquired owner is retained even if a later
reload refuses; successful reload clears the obsolete refusal while edited
choices and the Network draft stay unsaved. Construction, painting and navigation
do not retry or save implicitly. The parent accepted the recovery regression's
historical compiling RED: 59 cases, 58 passing and one expected explicit-retry
failure. These RED results do not establish recovery GREEN, full verification,
whole-diff independent review, required CI or native target proof.

Scan without saving choices is a separate explicit bypass for missing or
unavailable preferences. It does not record completion or persist choices.
Open app without saving dismisses setup without either a scan or a write and
retains the current shell selection. Neither bypass means setup was completed.

## Capability and evidence limits

Daily checks and notifications are declarations only: no daily timer, check
dispatch or notification registration is connected. Failed-update reporting is
unavailable and nothing is sent, including an initial report. Coverage sharing
and automatic installation are visibly OFF and disabled. The optional helper
is uninstalled and unavailable in this composition; setup cannot install it.
App Management status is unavailable, separate from helper approval. Completion
grants no macOS permission. The running-app confirmation and automatic-exclusion
copy describes the intended supported routes, not proof of installed execution.

The independent controller and view checks are parent-owned. The parent accepted
a compiling view RED with 56 combined cases: the prior 38 controller checks and
eight new controls passed, while ten intended view assertions failed before UI
implementation. Two additional controller-edge assertions passed within those
controls. These are historical preparation results, not a GREEN claim for this
implementation. Parent compilation, focused/full verification, whole-diff
independent correctness/security review, required exact-head/main CI and source
readback remain acceptance gates.

Offscreen checks can compare paint and detect model/store/provider effects under
injected fixtures. They cannot establish actual native keyboard/VoiceOver use,
permission deny/revoke/regrant, helper installation/removal, signed responsible
processes, offline/authenticated-proxy behaviour, guest execution or installed
relaunch. Those require separately authorised target proof. No app/helper launch,
installation, permission adapter, report/coverage send, provider action or client
release is added by this integration.
