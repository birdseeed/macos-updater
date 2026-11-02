# Native shell composition

## Consumer-flow direction, 27 October 2026

The finished consumer flow should present the ordinary app, current status and next action, with expandable provenance (PAT-2731). Technical history creation, loading and retention are preview controls to remove from the finished consumer journey. Usability acceptance includes interaction, deferral and VoiceOver. At main `66d66b28`, `NativeClientSession` composes navigation, local application scanner, DMG inspection, first-run and schedule settings/controllers, network settings and activity; `PatchedApp` composes the menu. This remains read-only: ready count is zero, current state is unknown, and there is no productive dispatcher or transaction. Offscreen native UI is not operating proof.

Privacy direction: failed-update reports default ON with visible opt-out; manual support diagnostics are previewed and opt-out (12 October design). Coverage sharing and analytics require opt-in. Current UI sends nothing. Do not claim broadly that nothing leaves the device. Paid-demand validation and production billing remain separate from private engineering proof; any beta entitlement or distribution must satisfy applicable release acceptance.

`PatchedApp` owns one `NativeClientSession` for its window. The session retains
the existing navigation, local application observations and disk image inspection
controllers. Construction, navigation, view appearance and sheet presentation do
not scan or inspect anything. Scan and Check remain explicit read-only actions.

Applications and Updates reuse the same `LocalApplicationsController` through
the existing `LocalApplicationsView` presentation enum. Updates displays the
accepted read-only projection of those observations; no catalogue or installation
authority is added. The explicit local disk image inspector uses the retained
`ClientController` and the same applications controller, including its nested
Applications and Updates sheets. Done or Escape dismisses the inspector without
discarding its selection or the session's observations.

Activity retains one `NativeActivityController` for the window and observes its
changes directly, including while Help & Support is displayed. Explicit Load
local history, Create empty history and Apply retention buttons operate the
existing account-bound local context. Rendering and route selection do not open
storage. Get help on a current row selects the exact loaded event and revision,
then routes locally to Help & Support. That immutable handoff survives later
loads or failures; a stale changed-row callback refuses without changing the
route, selection or drafts. Support displays the selected literal context and
retains its no-send disclosure. Licence & Macs uses
the existing default refusing licence presentation. Settings retain caller-owned
display drafts for unconnected sections; first-run and schedule choices have explicit local preference-store adapters. Source wiring does not prove persistence across actual guest relaunch. Help &
Support cannot send messages or diagnostic reports.

This is a source composition slice. The inventory reader supplies bounded installed-icon observations through `LocalInstalledIcon`; icons do not establish app identity or update eligibility. An installed consumer updater, accepted native guest interaction and customer release remain unproved. Full
native keyboard, VoiceOver, contrast and reduced-motion acceptance remain pending.
Offscreen rendering checks exercise layout only. Parent-owned verification,
independent whole-diff review and required CI remain separate acceptance gates.

The Testing SPI retains the exact injected history session and labels its
presentation Test double and last-loaded. Native local history is descriptive
and supplies no fresh installed-state validation. Source and fixture checks do
not establish actual native event production, per-user isolation, guest relaunch
or installed success; those outcomes require guest evidence, including the
separately accepted PAT-2710 transaction mechanism for event production. Help &
Support displays selected context locally and cannot send messages or reports.
