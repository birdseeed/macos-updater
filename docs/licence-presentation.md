# Local licence and Manage Macs presentation

PAT-2648 implements standalone pure presentation and SwiftUI views using inert,
caller-supplied display facts. No app composition, session authentication,
verified lease, entitlement grant, activation command or installation permission
is created. A displayed state is not verification evidence. Default management
refuses all target facts; default licence display preserves anonymous discovery.
Discovery, Patched self-update and transaction recovery remain independent in
every displayed licence state. All existing productive guards stay unchanged.

Sign-in has no trial side effect. Only signed-in plus explicit eligible display
facts offer a Start 14-day trial intent. Beta offers no trial and states the free,
no-card, no-auto-conversion terms. Outage never promises an extension. No dates,
remaining days or trusted freshness are inferred. All actions are inert intent
callbacks with no default effect. Future integration must re-authorise every
request at the actual command boundary and obtain any required confirmation;
presentation snapshots and intent revisions are never authentication.

Management accepts at most 50 facts and five active Macs, a nonempty matching
household display identity, current nonzero equal snapshot/current revisions,
nonzero target revisions and unique canonical nonzero 32-character lowercase
hex activation IDs. An optional local activation ID must use that same grammar.
Malformed, stale, terminal-only, cross-household or duplicate-ID snapshots refuse
in full. This Mac is determined only by exact activation ID equality. Released
rows remain visible and are excluded from active capacity; they have no intents.
Active intents bind target ID, target revision and snapshot revision. Replacement
confirmation appears only at the five-active limit; it never allocates a slot.

Untrusted names stay literal through Text(verbatim:), with native system fonts.
Labels are bounded by Swift Characters, not bytes: up to 240 characters and
three logical lines, with one ellipsis when shortened. Multibyte characters
have a separate 16 KiB UTF-8 input ceiling: longer labels become “Label too long”
before Character iteration. Iteration then stops at the display bound.
Truncation happens before duplicate detection. Duplicate displayed names carry
the complete validated ID, with reserved suffix space; generated-label collisions
are disambiguated too. Identity and intent targeting never use a display name.
The finite history paints directly offscreen. Each row separately displays its
complete validated ID on one line, so truncation cannot hide target distinction.
Dynamic action accessibility labels include that full ID, displayed target and
confirmation requirement where applicable. Buttons use native system text with
plain styling so the offscreen renderer can paint the actual labels.

The additive 56-case frozen check executable paints the actual ten licence states
and empty/full/released/refusing/literal management views offscreen. Its PNGs live
only in exclusively created .build directories. Rendering invokes no actions;
no PatchedApp or NSApplication is launched. These checks prove local presentation
behaviour, not native user interaction, real sign-in, accessibility navigation,
service freshness, installation or customer release. Full-gate acceptance,
independent canonical whole-diff review and publication remain parent-owned. Current selector: canonical root AGENTS.md, 19 October 2026, direct NVIDIA HTTPS primary with approved independent fallback; OpenCode is not required.

CHECK-MODIFIED, 11 October 2026: parent explicitly accepted the exact additive
Package.swift product/target/dependency registration and froze it together with
Tests/PatchedLicenceUIChecks/main.swift and scripts/verify-ui.sh before Phase B.
Only the Package.swift entry in
services/catalogue/protocol/fixtures/catalogue-v2/frozen-v1-sha256.json changes
from 7c3d118b5df921a0d4803aba73cc14d034427978175b7ddcd507f262744965ea
to 43d5eb107f9821cfc9e36a8d22f0154b6422057cc41d2b887b8bdc59877109c2.
Every other manifest entry remains exact. This build-registration baseline
correction relaxes no behavioural check. Original Phase A red receipts and the
parent freeze record remain in the parent evidence directory.

Focused gate: ./scripts/verify-ui.sh && ./scripts/verify-licensing.sh &&
./scripts/verify-activation.sh. Full native gate: ./scripts/verify.sh.
