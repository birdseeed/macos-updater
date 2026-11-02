# Native schedule settings composition

The client retains one schedule settings controller and an inert schedule driver.
Only explicit Reload opens preferences through the retained first-run controller.
It exposes the exact already-acquired PreferenceSession and generation internally;
there is no second store or preference context. Reload preserves unsaved schedule,
setup and network choices. Save applies one selected schedule declaration through
the existing revision/CAS/readback owner. Explicit migration handles legacy V1.
Missing, corrupt, uncertain and stale state never creates replacement preferences.
Blocked or changed owner state hides the accepted projection until explicit reload.
The existing combined 128-mutation and total-byte limits remain authoritative.

The controls display saved legacy automatic-true declarations honestly; these
never enable installation, and new true edits refuse. Pause labels validate the
existing ASCII wire syntax and nonnegative absolute UTC only. They confer no
clock, consent or permission authority. Choices are saved one at a time.

No trusted productive metadata checker is currently accepted. Ordinary driver
start refuses before reading time, subscribing to hooks, reading storage or
consuming a schedule opportunity. It never substitutes an inventory scan or
local disk-image inspection. Construction, rendering and navigation are inert.

Testing SPI alone supplies fake hooks and dispatcher callbacks over the real
driver and existing NativeScheduleClock. PreferenceSession alone owns cadence
and opaque attempt capabilities. The driver keeps one physical child pending
until its exact callback, including after cancellation or shutdown. Stale,
duplicate and synchronous callbacks cannot resurrect requests or publish results.
Clock faults require explicit reanchor with the existing full-day deferral.
Known sleep survives initial observation, ticks and explicit reanchor until wake.
Phase and completion notifications expose settled state. A stop during the initial
running notification remains terminal before subscription or clock sampling; a
stop during reservation publication prevents dispatch and releases only that
undispatched reservation. Completion settles the old logical attempt before
publishing physical release, so a reentrant replacement retains its own attempt.
Stop is terminal and unsubscribes once. These source seams and offscreen controls
do not establish real native scheduling, installed proof or release readiness.

Verification remains parent-owned: frozen focused 59, default client 294,
first-run 66 and full repository gates, followed by independent whole-artifact
correctness/security review and required exact-head/main CI. No build or check
was run by the source implementer.
